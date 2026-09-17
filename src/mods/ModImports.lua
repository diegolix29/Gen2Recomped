-- Base files a mod needs but cannot ship: `required_imports` in manifest.json.
--
-- Some mods are extractors.  STADIUM2_IMPORTER rips models out of a Pokemon
-- Stadium 2 cartridge; it cannot legally ship the cartridge, and the sandbox
-- gives a mod no way to reach outside its own folder, so the mod's own
-- discovery ends in "the engine sandbox has no scoped external ROM picker".
-- The manifest has always DECLARED the requirement:
--
--   "required_imports": [ {
--       "id": "stadium2_rom", "name": "Pokemon Stadium 2 (USA) ROM",
--       "file": "baseroms/stadium2.z64", "format": "n64",
--       "size": 67108864, "md5": "1561c75d..." } ]
--
-- and the engine ignored the field completely, so the only way to satisfy it
-- was to unzip the release, drop a 64 MB file inside it, re-zip and reinstall.
-- That is the "I can't import the Stadium 2 ROM" report.
--
-- What this module does is simple on purpose: it writes the player's file
-- INTO THE MOD'S OWN FOLDER at the declared path.  Every mod already reads its
-- own folder (`mod:read(relative)`), so a mod needs no new API and no change
-- at all to pick the file up -- STADIUM2_IMPORTER's Discovery.find() looks in
-- exactly the two places this writes to.  The engine's job is only to get the
-- bytes there, and to refuse the wrong file before it does.

local Logger = require("src.core.Logger")

local ModImports = {}

-- The launcher's own trees -- the shared base-file bank under imports/base/
-- and the copy written into a mod's own folder -- follow the player's chosen
-- game-data folder, which love.filesystem cannot reach: it always resolves a
-- write to the OS save directory.  CacheFs.dataFs reads and enumerates through
-- love.filesystem (every home at once, including the chosen root, which is
-- mounted) and routes writes and removes at whichever root is live.
--
-- Falls back to love.filesystem when CacheFs is unavailable, which is how the
-- headless tests run: they inject their own fs and never load it.
local function fs()
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.dataFs then
    local okFs, handle = pcall(CacheFs.dataFs)
    if okFs and handle then return handle end
  end
  return love and love.filesystem
end

-- A declared import, normalised.  `file` is where the mod expects to read it
-- from, relative to the mod folder; everything else is validation.
-- THE SAME GAME IN MORE THAN ONE DUMP.
--
-- A cartridge has one md5 and a manifest names it.  A disc does not: the USA
-- release of a GameCube title exists as several good dumps, and a mod that
-- wants any of them was writing both hashes into the one `md5` string --
-- "aaa..., bbb..." -- which then matched NOTHING.  `check` compared the whole
-- string against a digest, so the import could never be accepted, and
-- `sharedKey` used it as a FILENAME, comma and space included.
--
-- So the field takes either shape: one hash, several in a string, or a list.
-- Every 32-hex run is taken and the rest is ignored, which also absorbs the
-- stray whitespace that comes with writing two of them by hand.  `md5` stays
-- a single string -- it is what names the shared bank and nothing else should
-- have to learn a new shape -- and `md5s` carries the full set for the one
-- place that compares.
local HASH = ("%x"):rep(32)

local function md5Set(raw)
  local out = {}
  local function add(value)
    if type(value) ~= "string" then return end
    for hash in value:lower():gmatch(HASH) do out[#out + 1] = hash end
  end
  if type(raw) == "table" then
    for _, value in ipairs(raw) do add(value) end
  else
    add(raw)
  end
  return out[1], out[1] and out or nil
end

-- "474336453031" or { "...", "..." } -> a list of lowercase hex strings, or
-- nil.  Odd-length or non-hex entries are dropped rather than guessed at: a
-- half-read signature that matches half a file is worse than no check.
local function magicSet(raw)
  if raw == nil then return nil end
  local list = (type(raw) == "table") and raw or { raw }
  local out = {}
  for _, value in ipairs(list) do
    if type(value) == "string" then
      local hex = value:gsub("%s", ""):lower()
      if #hex > 0 and #hex % 2 == 0 and hex:match("^%x+$") then
        out[#out + 1] = hex
      end
    end
  end
  return out[1] and out or nil
end

local function normalise(raw, index)
  if type(raw) ~= "table" then return nil end
  local file = raw.file
  if type(file) ~= "string" or file == "" then return nil end
  -- never let a manifest write outside its own folder
  if file:find("%.%.") or file:sub(1, 1) == "/" or file:find("^%a:") then
    return nil
  end
  -- WHERE the mod reads it from.  "mod" (the default) is inside the mod's own
  -- folder, which is all a sandboxed `mod:read` can reach.  "save" is the
  -- PhysFS root -- the save directory and the game folder, searched under one
  -- name -- and some mods genuinely want that: STADIUM2_OVERWORLD_MODELS
  -- looks for `baseroms/stadium2.z64` there and nowhere else, so writing its
  -- cartridge into the mod folder satisfied the manifest and left the mod
  -- still reporting no ROM.  The `..`/absolute guard above applies to both.
  local root = (raw.root == "save" or raw.root == "root") and "save" or "mod"
  local first, all = md5Set(raw.md5)
  return {
    id = tostring(raw.id or ("import" .. index)),
    name = tostring(raw.name or raw.id or file),
    description = type(raw.description) == "string" and raw.description or nil,
    file = file,
    root = root,
    format = type(raw.format) == "string" and raw.format:lower() or nil,
    -- WHAT TO RUN ONCE THE FILE IS THERE.
    --
    -- A base file is the start of the mod's work, not the end of the engine's,
    -- and for a disc that work is a long extraction.  A mod can subscribe to
    -- `imports.ready` for this, which is the general answer -- but subscribing
    -- is Lua, and this whole contract is otherwise declarative: the manifest
    -- already says what file it needs and where to put it, so it may as well
    -- say what to call when it lands.  The value names an export the mod
    -- publishes (mod.exports.<name>); anything else is ignored.
    onReady = type(raw.on_ready) == "string" and raw.on_ready ~= ""
      and raw.on_ready or nil,
    -- BYTES THAT PROVE IT IS THE RIGHT FILE, when a hash cannot.
    --
    -- `md5` is the proper answer and is only checked when the file fits this
    -- device's hash budget -- never, for a 1.4 GB disc.  So a disc could match
    -- on size, import cleanly, and be the wrong REGION: a PAL Colosseum
    -- (GC6P01) is byte-for-byte the same length as the USA one (GC6E01) the
    -- mod needs, and the mod only found out after the copy, from inside its
    -- own structural check, as "not structurally valid".
    --
    -- A few bytes at a known offset settle that in constant time at any size.
    -- A list means alternatives (several good dumps, several regions a mod
    -- actually supports); hex, because a game id is bytes and quoting them as
    -- text invites an encoding to get in the way.
    magic = magicSet(raw.magic),
    magicOffset = math.max(0, math.floor(tonumber(raw.magic_offset) or 0)),
    size = tonumber(raw.size),
    md5 = first,
    md5s = all,
  }
end

-- Manifest.validate hands the parsed list straight through; this is also the
-- reader for a raw manifest table, so the launcher can ask before a mod loads.
function ModImports.parse(raw)
  local list = raw and raw.required_imports
  if type(list) ~= "table" then return nil end
  local out = {}
  for index, entry in ipairs(list) do
    local row = normalise(entry, index)
    if row then out[#out + 1] = row end
  end
  return out[1] and out or nil
end

function ModImports.of(manifest)
  if type(manifest) ~= "table" then return nil end
  return manifest.requiredImports or ModImports.parse(manifest.raw)
end

-- The extensions a picker should offer for one entry.  `format` names a family
-- rather than a single suffix, because a console ROM legitimately arrives in
-- more than one byte order and the mod normalises them itself.
ModImports.FORMATS = {
  n64 = { "z64", "n64", "v64" },
  gb = { "gb", "gbc" },
  gba = { "gba" },
  nds = { "nds" },
  -- A DISC, which is the same argument as a cartridge's byte orders and then
  -- some.  Asked for by a mod that wants a Pokemon Colosseum disc: a GameCube
  -- dump is `.gcm` from some rippers, `.iso` from most, and `.ciso`/`.rvz`
  -- once somebody has compressed it -- all the same disc, and a mod that
  -- declared one spelling refused the other three.
  --
  -- A `format` is only needed when a mod will take MORE than one suffix: with
  -- none, extensions() falls back to the suffix of the declared `file`, which
  -- is why a manifest naming `baseroms/colosseum.iso` already works for a
  -- player whose dump happens to be spelled that way.
  gamecube = { "gcm", "iso", "ciso", "rvz" },
  wii = { "iso", "wbfs", "rvz", "nkit" },
  zip = { "zip" },
}

function ModImports.extensions(entry)
  if not entry then return {} end
  local byFormat = entry.format and ModImports.FORMATS[entry.format]
  if byFormat then return byFormat end
  local suffix = tostring(entry.file or ""):match("%.(%w+)$")
  return suffix and { suffix:lower() } or {}
end

function ModImports.accepts(entry, name)
  local want = ModImports.extensions(entry)
  if #want == 0 then return true end
  local suffix = tostring(name or ""):match("%.(%w+)$")
  if not suffix then return false end
  suffix = suffix:lower()
  for _, ext in ipairs(want) do
    if ext == suffix then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The shared store
--
-- Two mods can want the SAME base file: STADIUM2_IMPORTER and
-- STADIUM2_OVERWORLD_MODELS both extract from a Pokemon Stadium 2 cartridge.
-- Making the player find and import a 64 MB ROM once per mod is the kind of
-- thing that reads as the feature being broken, so an accepted file is also
-- kept under imports/base/ and any other mod that declares a matching entry
-- is satisfied from there without asking again.
--
-- Matching is by DECLARED IDENTITY -- md5 when the manifest gives one, else
-- id plus size -- not by filename, so two mods that spell the same cartridge
-- differently still share it.
local SHARED_DIR = "imports/base"

function ModImports.sharedKey(entry)
  if not entry then return nil end
  if entry.md5 then return entry.md5 end
  if entry.size then return ("%s-%d"):format(entry.id, entry.size) end
  return entry.id
end

function ModImports.sharedPath(entry)
  local key = ModImports.sharedKey(entry)
  return key and (SHARED_DIR .. "/" .. key .. ".bin") or nil
end

-- THE BANK DOES NOT HAVE TO HOLD THE BYTES.
--
-- A `root = "save"` entry already puts the file at the PhysFS root under a
-- stable name that no mod owns and no uninstall removes -- `baseroms/`, for a
-- cartridge.  Banking a SECOND 64 MB copy of it under imports/base/ buys
-- nothing and is a third of a gigabyte for three mods.  So once such a copy
-- exists the bank is downgraded to a one-line pointer at it.
--
-- A `root = "mod"` entry still banks real bytes: that file lives inside a mod
-- folder and goes away with the mod, so the copy is the only thing that keeps
-- the next mod from asking for the cartridge again.
--
-- A pointer whose target has since been deleted simply reads as "nothing
-- banked" and the ordinary import flow asks for the file -- the store is a
-- convenience, never the only copy of anything the player cannot replace.
function ModImports.sharedPointerPath(entry)
  local key = ModImports.sharedKey(entry)
  return key and (SHARED_DIR .. "/" .. key .. ".path") or nil
end

-- Read a shared copy back, or nil.  Follows a pointer bank.
function ModImports.shared(entry)
  local f = fs()
  if not f then return nil end
  local path = ModImports.sharedPath(entry)
  if path and f.getInfo(path, "file") then return f.read(path) end

  local ptr = ModImports.sharedPointerPath(entry)
  if not (ptr and f.getInfo(ptr, "file")) then return nil end
  local target = tostring(f.read(ptr) or ""):gsub("%s+$", "")
  if target == "" then return nil end
  local info = f.getInfo(target, "file")
  if not info then return nil end
  -- cheap guard before 64 MB is read: the pointer is only as good as the file
  -- still sitting at the other end of it
  if entry.size and info.size and info.size ~= entry.size then return nil end
  return f.read(target)
end

-- ...and the same lookup answering a PATH, which is what the streaming
-- installer wants.  A pointer bank can aim at a 1.4 GB disc, so the one caller
-- that used to read it whole is exactly the one that must not.
function ModImports.sharedSource(entry)
  local f = fs()
  if not f then return nil end
  local path = ModImports.sharedPath(entry)
  if path and f.getInfo(path, "file") then return path end
  local ptr = ModImports.sharedPointerPath(entry)
  if not (ptr and f.getInfo(ptr, "file")) then return nil end
  local target = tostring(f.read(ptr) or ""):gsub("%s+$", "")
  if target == "" then return nil end
  local info = f.getInfo(target, "file")
  if not info then return nil end
  if entry.size and info.size and info.size ~= entry.size then return nil end
  return target
end

-- HOW BIG A BASE FILE THE BANK WILL HOLD A COPY OF.
--
-- The bank exists so a second mod wanting the same file does not send the
-- player looking for it again, and for a 64 MB cartridge a copy is a fair
-- price.  A DISC IS NOT: a GameCube dump is about 1.4 GB, so banking one
-- turns a single import into nearly three gigabytes on disk -- and the player
-- is never told, because the bank is silent by design.
--
-- Above this, the bank keeps a POINTER at the copy that was just written
-- instead (the same one-line record a `root = "save"` entry already gets).  It
-- is a weaker promise -- uninstalling the mod that owns the folder takes the
-- target with it, and the next mod asks again -- but "ask again" is a far
-- better failure than quietly filling a disk.
ModImports.MAX_BANK_BYTES = 256 * 1024 * 1024

-- Forward-declared: keepShared is the first caller and bankPointer is defined
-- below it, so without this the call would resolve to a nil global.
local bankPointer

local function keepShared(entry, bytes, wrotePath)
  local f = fs()
  local path = ModImports.sharedPath(entry)
  if not (f and path) then return end
  if f.getInfo(path, "file") then return end   -- already banked
  if #bytes > ModImports.MAX_BANK_BYTES then
    -- nothing to point at means nothing to bank; the ordinary import flow
    -- simply asks the next mod for the file
    if wrotePath then bankPointer(entry, wrotePath) end
    return
  end
  if f.createDirectory then
    f.createDirectory("imports")
    f.createDirectory(SHARED_DIR)
  end
  pcall(f.write, path, bytes)
end

-- Point the bank at a copy that already exists at a stable path, and drop the
-- byte bank if one was taken earlier (that is the 64 MB this reclaims).
function bankPointer(entry, path)
  local f = fs()
  local ptr = ModImports.sharedPointerPath(entry)
  if not (f and ptr and path) then return end
  local bytes = ModImports.sharedPath(entry)
  local banked = bytes and f.getInfo(bytes, "file")
  if f.getInfo(ptr, "file") and not banked then return end
  if f.createDirectory then
    f.createDirectory("imports")
    f.createDirectory(SHARED_DIR)
  end
  if not pcall(f.write, ptr, path) then return end
  if banked and f.remove then
    -- only after the pointer is on disk, so a crash between the two leaves
    -- the store with a copy too many rather than none at all
    pcall(f.remove, bytes)
    Logger.info("mod import: shared store now points at %s (freed %d bytes)",
      path, tonumber(banked.size) or 0)
  end
end

-- Satisfy every entry a mod declares from the shared store, silently.  Called
-- when the launcher builds its list, so a second mod that wants a cartridge
-- the player already gave the first one is simply ready.
-- AUTOMATIC ADOPTION HAS A SIZE CEILING, and it is the same ceiling that
-- decides whether the bank keeps bytes or a pointer.
--
-- The bank exists so a player who hands over a 64 MB Stadium cartridge for one
-- mod is not asked for it again by the next: silently satisfying the second
-- mod is the whole feature.  That reasoning holds while "satisfying" costs a
-- few tens of megabytes.  It stops holding at a GameCube disc, where it means
-- the launcher writes 1.4 GB per declaring mod, on every launch that finds one
-- unsatisfied, without anybody asking -- reported from a log showing two
-- back-to-back 1.4 GB streams into two mod folders before the window was even
-- up.
--
-- So above MAX_BANK_BYTES the bank still remembers WHERE the file is (that is
-- what the pointer is for, and it is what stops the player having to find it
-- again), but putting a second copy inside a second mod is a decision with a
-- price, and the player makes it by pressing Import base file on that mod's
-- card.  One press, one stream, and nothing happens behind their back.
function ModImports.autoAdoptLimit()
  return ModImports.MAX_BANK_BYTES
end

function ModImports.adoptShared(manifest)
  local adopted = 0
  for _, row in ipairs(ModImports.missing(manifest) or {}) do
    local banked = ModImports.sharedSource(row.entry)
    local size = nil
    if banked then
      local f = fs()
      local info = f and f.getInfo(banked, "file")
      size = info and info.size or row.entry.size
    end
    -- An unknown size is treated as small: every base file that predates this
    -- was, and refusing to adopt something we cannot measure would turn a
    -- working setup into one that asks again for no reason.
    local tooBig = size ~= nil and size > ModImports.autoAdoptLimit()
    if banked and not tooBig
       and ModImports.installFrom(manifest, row.entry,
                                  { savePath = banked },
                                  { fromShared = true }) then
      adopted = adopted + 1
    end
  end
  return adopted
end

-- Where the file lands.  A mod folder under the save directory is writable; a
-- mod baked into a read-only source tree is not, and there the write simply
-- fails and says so rather than pretending.
--
-- `root = "save"` puts it at the top of the LOVE save directory instead of
-- inside the mod, which is what a mod declares when the file is big and shared
-- (a 64 MB cartridge two mods both extract from).  Worth knowing when the
-- panel says "ready" and the mod folder looks empty: for those entries the
-- file was never meant to be in the mod folder at all.  ModImports.describe
-- below is what the card prints so that is not a guess.
function ModImports.pathFor(manifest, entry)
  if not entry then return nil end
  if entry.root == "save" then return entry.file end
  if not (manifest and manifest.path) then return nil end
  return manifest.path .. "/" .. entry.file
end

-- A one-line "where is it" for the launcher.  "<name>: ready" on its own was
-- true and useless -- it says a file exists without saying which file or
-- where, so a player looking in the mod folder for a `root = "save"` entry
-- reasonably concludes the panel is lying.
function ModImports.describe(manifest, entry)
  local path = ModImports.pathFor(manifest, entry)
  if not path then return tostring(entry and entry.name or "file") end
  -- a mod-folder path already names the mod folder; only the save-dir case
  -- needs the prefix, and that is exactly the case that confused people
  local where = (entry.root == "save") and ("save dir/" .. path) or path
  -- ...and if it is in the shared store, SAY SO.  adoptShared installs a file
  -- the player gave a DIFFERENT mod, silently, when the launcher builds its
  -- list -- correct, declared by the manifest, and completely invisible: the
  -- report this answers is "it is auto-installing the ROM and I don't know
  -- where it is getting this from".
  local f = fs()
  local bank = ModImports.sharedPath(entry)
  local ptr = ModImports.sharedPointerPath(entry)
  local shared = f ~= nil
    and ((bank ~= nil and f.getInfo(bank, "file") ~= nil)
      or (ptr ~= nil and f.getInfo(ptr, "file") ~= nil))
  return ("%s: ready (%s)%s"):format(tostring(entry.name), where,
    shared and " -- shared with your other mods that want this file" or "")
end

-- Is one entry already satisfied?  Presence is the test the mod itself makes,
-- so presence is the test here -- a size mismatch is reported but a file that
-- is there is not deleted behind the player's back.
function ModImports.have(manifest, entry)
  local f = fs()
  local path = ModImports.pathFor(manifest, entry)
  if not (f and path) then return false end
  local info = f.getInfo(path, "file")
  if not info then return false end
  if entry.size and info.size and info.size ~= entry.size then
    return false, ("%s is %d bytes; expected %d")
      :format(entry.file, info.size, entry.size)
  end
  return true
end

-- Every unsatisfied entry for one mod, or nil when it needs nothing.
function ModImports.missing(manifest)
  local list = ModImports.of(manifest)
  if not list then return nil end
  local out = {}
  for _, entry in ipairs(list) do
    local ok, why = ModImports.have(manifest, entry)
    if not ok then
      out[#out + 1] = { entry = entry, reason = why }
    end
  end
  return out[1] and out or nil
end

function ModImports.satisfied(manifest)
  return ModImports.missing(manifest) == nil
end

local function md5Of(bytes)
  if not (love and love.data and love.data.hash and love.data.encode) then
    return nil
  end
  local ok, value = pcall(function()
    local digest = love.data.hash("md5", bytes)
    if type(digest) == "userdata" and digest.getString then
      digest = digest:getString()
    end
    return love.data.encode("string", "hex", digest)
  end)
  return ok and value or nil
end

-- N64 cartridge dumps come in three byte orders and only the mod knows which
-- one it wants, so the size and hash checks have to allow all three.  Byte
-- swapping is the mod's job (STADIUM2_IMPORTER's Rom.normalise does it), which
-- is why this converts only for the purpose of CHECKING the hash.
local N64_ORDERS = {
  { magic = "\128\055\018\064", swap = 0 },   -- z64, big endian
  { magic = "\055\128\064\018", swap = 2 },   -- v64, byte swapped
  { magic = "\064\018\055\128", swap = 4 },   -- n64, little endian
}

local function toBigEndian(bytes)
  if #bytes < 4 then return bytes end
  local head = bytes:sub(1, 4)
  for _, order in ipairs(N64_ORDERS) do
    if head == order.magic then
      if order.swap == 0 then return bytes end
      if order.swap == 2 then return (bytes:gsub("(.)(.)", "%2%1")) end
      return (bytes:gsub("(.)(.)(.)(.)", "%4%3%2%1"))
    end
  end
  return bytes
end

-- Check bytes against one entry WITHOUT writing anything.  Returns true, or
-- false plus a sentence the launcher can put on screen.
function ModImports.check(entry, bytes)
  if type(bytes) ~= "string" or bytes == "" then
    return false, "that file is empty"
  end
  if entry.size and #bytes ~= entry.size then
    return false, ("that file is %d bytes; %s needs %d")
      :format(#bytes, entry.name, entry.size)
  end
  if entry.md5 then
    local want = entry.md5s or { entry.md5 }
    local function accepted(hash)
      if not hash then return false end
      hash = hash:lower()
      for _, one in ipairs(want) do
        if hash == one then return true end
      end
      return false
    end
    local hash = md5Of(bytes)
    -- an n64 entry accepts any of the three byte orders: hash the big-endian
    -- form, which is what the declared md5 is taken over
    if not accepted(hash) and entry.format == "n64" then
      hash = md5Of(toBigEndian(bytes))
    end
    if hash and not accepted(hash) then
      return false, ("that is not the right file (MD5 %s)"):format(hash:sub(1, 8))
    end
  end
  return true
end

-- Validate and install.  Returns true, or false + why.  `fromShared` skips
-- banking the bytes again (they came out of the store).
function ModImports.install(manifest, entry, bytes, fromShared)
  local ok, why = ModImports.check(entry, bytes)
  if not ok then return false, why end
  local f = fs()
  local path = ModImports.pathFor(manifest, entry)
  if not (f and path) then return false, "no writable mod folder" end
  local dir = path:match("^(.*)/[^/]*$")
  if dir and f.createDirectory then f.createDirectory(dir) end
  local wrote, err = f.write(path, bytes)
  if not wrote then
    return false, ("could not write %s (%s)"):format(entry.file, tostring(err))
  end
  if not fromShared then keepShared(entry, bytes, path) end
  -- the file now sits at a stable root path, so the bank need not hold bytes
  if entry.root == "save" then bankPointer(entry, path) end
  Logger.info("mod import: %s -> %s (%d bytes)%s", entry.id, path, #bytes,
    fromShared and " [adopted from the shared store, not imported]" or "")
  return true
end

-- ---------------------------------------------------------------------------
-- COPYING A BASE FILE WITHOUT HOLDING IT
--
-- Reported from play: importing a ROM from the launcher was crashing it.  Every
-- path here read the whole file into one Lua string -- the picker's, the
-- inbox's, the mod folder's -- and then `install` held that string while
-- love.data.hash walked it, while love.filesystem.write copied it out, and
-- while keepShared wrote a second copy.  For a 64 MB Stadium 2 cartridge that
-- is a couple of hundred megabytes live at once, which a desktop shrugs off
-- and an Android heap does not; for the 1.4 GB GameCube disc a mod now wants
-- it cannot work anywhere.
--
-- So the bytes are STREAMED: a megabyte at a time, source to destination, with
-- one chunk live.  Peak memory stops depending on the size of the file, which
-- is the whole of the fix -- a phone copies a disc as comfortably as a
-- cartridge, and a 32-bit build never has to find a contiguous 1.4 GB.
--
-- WHAT THIS COSTS IS THE HASH, and it is worth being plain about.  LOVE's
-- love.data.hash takes a whole string and there is no incremental form, so a
-- file too big to hold is a file too big to MD5 -- and hashing it by
-- reading it back in one piece would put back exactly the allocation this
-- removes.  So:
--
--   * SIZE is always checked, before a byte is copied.  It is cheap, it comes
--     off getInfo, and for a cartridge or a disc it is most of the answer.
--   * MD5 is checked when the file is small enough that holding it is safe on
--     THIS machine -- see hashLimit, which is far lower on a phone than on a
--     64-bit desktop.
--   * When it is skipped, the caller is TOLD, and says so.  A verification
--     that silently stops happening is worse than one that admits it.
-- ---------------------------------------------------------------------------

ModImports.COPY_CHUNK = 1024 * 1024

-- How many bytes this machine can be asked to hold in one string just to hash
-- them.  Deliberately conservative: the number is a budget for one transient
-- allocation on top of everything the launcher or the running game is already
-- holding, not a measure of free memory.
function ModImports.hashLimit()
  local os_ = love and love.system and love.system.getOS and love.system.getOS()
  if os_ == "Android" or os_ == "iOS" then return 24 * 1024 * 1024 end
  -- A 32-bit process has about 2 GB of address space for everything, and it
  -- fragments; a 64 MB cartridge is already an uncomfortable single block.
  local arch = jit and jit.arch
  if arch and arch ~= "x64" and arch ~= "arm64" and arch ~= "mips64" then
    return 48 * 1024 * 1024
  end
  return 256 * 1024 * 1024
end

-- A reader over either kind of path, with the size known up front and nothing
-- read until it is asked for.  `savePath` is a PhysFS name (the inbox, a mod
-- folder); `path` is an absolute one off a native picker.
function ModImports.openSource(source)
  local f = fs()
  if type(source) == "table" and source.savePath then
    if not (f and f.newFile) then return nil, "no filesystem" end
    local info = f.getInfo(source.savePath, "file")
    if not info then return nil, "that file is not there any more" end
    local handle = f.newFile(source.savePath)
    local ok = handle and handle:open("r")
    if not ok then return nil, "that file could not be opened" end
    return {
      size = info.size,
      read = function(n)
        local chunk = handle:read(n)
        return (chunk and #chunk > 0) and chunk or nil
      end,
      close = function() pcall(handle.close, handle) end,
    }
  end
  local path = type(source) == "table" and source.path or source
  if type(path) ~= "string" then return nil, "no file given" end
  local handle = io.open(path, "rb")
  if not handle then
    -- a save-dir-relative name handed in as a plain string
    if f and f.getInfo(path, "file") then
      return ModImports.openSource({ savePath = path })
    end
    return nil, "that file could not be opened"
  end
  local size = handle:seek("end")
  handle:seek("set")
  return {
    size = size,
    read = function(n)
      local chunk = handle:read(n)
      return (chunk and #chunk > 0) and chunk or nil
    end,
    close = function() pcall(handle.close, handle) end,
  }
end

-- Copy `reader` to a PhysFS path a chunk at a time.  Returns the bytes
-- written, or nil plus a reason -- and cleans up a half-written file, because
-- a truncated cartridge that LOOKS installed is the worst of the outcomes
-- (the mod finds a file, reads garbage, and blames the dump).
-- `head`, when given, is bytes already taken off the front of `reader` -- the
-- signature check consumes a prefix, and a stream cannot be rewound, so those
-- bytes have to be written back before the rest or the copy is short by
-- exactly that much.
local function streamTo(reader, path, head)
  local f = fs()
  if not (f and f.newFile) then return nil, "no writable filesystem" end
  local dir = path:match("^(.*)/[^/]*$")
  if dir and f.createDirectory then f.createDirectory(dir) end
  local out = f.newFile(path)
  local opened, openErr = out:open("w")
  if not opened then
    return nil, ("could not write %s (%s)"):format(path, tostring(openErr))
  end
  local written = 0
  if head and #head > 0 then
    local ok, err = out:write(head)
    if not ok then
      pcall(out.close, out)
      pcall(f.remove, path)
      return nil, ("could not write %s (%s)"):format(path, tostring(err))
    end
    written = #head
  end
  while true do
    local chunk = reader.read(ModImports.COPY_CHUNK)
    if not chunk then break end
    local ok, err = out:write(chunk)
    if not ok then
      pcall(out.close, out)
      pcall(f.remove, path)
      return nil, ("could not write %s (%s)"):format(path, tostring(err))
    end
    written = written + #chunk
  end
  pcall(out.close, out)
  return written
end

-- Install from a FILE rather than from bytes.
--
-- Returns ok, why, notes -- where `notes` is a sentence about what could not
-- be verified, or nil when everything was.
-- matchMagic(entry, prefix) -> true, or false plus what was there instead.
-- `prefix` is the first bytes of the candidate, at least magicOffset + the
-- signature length.  Separate from the reading so it can be tested without a
-- filesystem, and so `have` can use it later without re-deriving the rule.
function ModImports.matchMagic(entry, prefix)
  if not (entry and entry.magic) then return true end
  local want = entry.magic
  local at = (entry.magicOffset or 0) + 1
  local need = 0
  for _, hex in ipairs(want) do need = math.max(need, #hex / 2) end
  local got = tostring(prefix or ""):sub(at, at + need - 1)
  local hexGot = got:gsub(".", function(c) return ("%02x"):format(c:byte()) end)
  for _, hex in ipairs(want) do
    if hexGot:sub(1, #hex) == hex then return true end
  end
  -- Printable where it is printable: a disc's game id is ASCII, and "GC6P01"
  -- next to "GC6E01" is a diagnosis anybody can read, where two hex strings
  -- are a puzzle.
  local shown = got:gsub("%c", "."):gsub("[\128-\255]", ".")
  return false, shown, hexGot
end

function ModImports.installFrom(manifest, entry, source, opts)
  opts = opts or {}
  local path = ModImports.pathFor(manifest, entry)
  if not path then return false, "no writable mod folder" end
  local reader, why = ModImports.openSource(source)
  if not reader then return false, why end

  -- SIZE FIRST, so the wrong file costs nothing.  This is the check that used
  -- to happen after the whole thing was in memory.
  if entry.size and reader.size and reader.size ~= entry.size then
    reader.close()
    return false, ("that file is %d bytes; %s needs %d")
      :format(reader.size, entry.name, entry.size)
  end

  -- ...THEN THE SIGNATURE, still before a byte is copied.  The prefix read
  -- here is CARRIED FORWARD rather than re-read, because the reader is a
  -- stream: consuming it twice would skip that much of the file.
  local prefix = nil
  if entry.magic then
    local need = (entry.magicOffset or 0)
    for _, hex in ipairs(entry.magic) do need = math.max(need, (entry.magicOffset or 0) + #hex / 2) end
    prefix = reader.read(need)
    local ok, shown, hexGot = ModImports.matchMagic(entry, prefix)
    if not ok then
      reader.close()
      return false, ("that is not the right %s -- it starts with %s (%s)")
        :format(tostring(entry.name), tostring(shown), tostring(hexGot))
    end
  end

  -- ...then the hash, when the file is small enough to hold.  Read once here
  -- and hand the same string to install(), so a cartridge takes exactly the
  -- path it always took and nothing about the verified case changes.
  local limit = ModImports.hashLimit()
  if entry.md5 and reader.size and reader.size <= limit then
    local rest = reader.read(reader.size)
    reader.close()
    local whole = (prefix or "") .. (rest or "")
    if rest == nil and not prefix then return false, "that file could not be read" end
    local ok, installWhy = ModImports.install(manifest, entry, whole, opts.fromShared)
    return ok, installWhy, nil
  end

  local skipped = nil
  if entry.md5 then
    skipped = ("%s is %d MB, too large to checksum on this device -- its size "
               .. "matches, but the MD5 was not checked")
              :format(entry.name, math.floor((reader.size or 0) / 1048576))
  end
  local written, streamWhy = streamTo(reader, path, prefix)
  reader.close()
  if not written then return false, streamWhy end
  if entry.size and written ~= entry.size then
    pcall(fs().remove, path)
    return false, ("only %d of %d bytes could be copied"):format(written, entry.size)
  end
  -- The bank never holds a file this big (see keepShared); a pointer at the
  -- copy just written is what the next mod gets.  Not when the bytes CAME from
  -- the bank, though -- that would aim an existing record at a copy inside a
  -- mod folder that an uninstall can take away.
  if not opts.fromShared then bankPointer(entry, path) end
  Logger.info("mod import: %s -> %s (%d bytes, streamed)%s", entry.id, path,
              written, skipped and " [hash skipped]" or "")
  return true, nil, skipped
end

-- ---------------------------------------------------------------------------
-- Getting the bytes, from anywhere, on any platform
--
-- The launcher's MODS panel was the only place a required import could be
-- satisfied, and only for a mod whose manifest declared one.  That left two
-- holes the reports land in: a mod that ships its own "STADIUM 2 ROM FILE ->
-- CHOOSE" row inside its OPTIONS screen had nothing behind it on desktop (its
-- own picker is Android-only and the engine sandbox hides love.system from
-- mod code), and a mod with no `required_imports` block got no button at all.
--
-- So the acquisition is engine-owned and lives here rather than in the
-- launcher: ManagerState hangs an IMPORT row off every declared entry, in
-- game, on every platform, and the launcher calls the same functions.
-- ---------------------------------------------------------------------------

-- Everywhere a file may already be waiting, in the order it should be trusted.
ModImports.INBOX_DIRS = { SHARED_DIR, "imports", "imports/mods", "" }

-- A file already sitting in the save directory, without asking anyone.
function ModImports.fromInbox(entry)
  local f = fs()
  if not (f and entry) then return nil end
  for _, dir in ipairs(ModImports.INBOX_DIRS) do
    for _, name in ipairs(f.getDirectoryItems(dir) or {}) do
      local path = (dir == "") and name or (dir .. "/" .. name)
      local info = ModImports.accepts(entry, name) and f.getInfo(path, "file")
      -- size off getInfo first: a save dir with several cartridges in it must
      -- not read every one of them into memory to reject them by hash
      -- ...and the PATH is the answer, not the bytes: installFrom streams it
      -- from here and never has the whole cartridge in hand.  The hash is
      -- checked there, where the decision about whether it can be afforded
      -- lives.
      if info and (not entry.size or info.size == nil
                   or info.size == entry.size) then
        return path
      end
    end
  end
  return nil
end

-- A file the player already dropped INSIDE the mod's own folder.
--
-- This is what people actually do, and it is the most reasonable guess: the
-- mod's README says it wants a Stadium 2 cartridge, so the cartridge goes in
-- the mod's folder.  STADIUM2_OVERWORLD_MODELS then never finds it, because
-- it reads `baseroms/` at the PhysFS root and not its own directory -- so a
-- 64 MB file sat there doing nothing while the mod reported no ROM.  Adopt it.
--
-- Size is checked off getInfo before anything is read, so the common case
-- (nothing there, or the wrong file) never touches 64 MB of disk.
function ModImports.fromModFolder(manifest, entry)
  local f = fs()
  if not (f and entry and manifest and manifest.path) then return nil end
  local roots = { manifest.path }
  local dir = tostring(entry.file):match("^(.*)/[^/]*$")
  if dir then roots[#roots + 1] = manifest.path .. "/" .. dir end
  local target = ModImports.pathFor(manifest, entry)
  for _, root in ipairs(roots) do
    for _, name in ipairs(f.getDirectoryItems(root) or {}) do
      local path = root .. "/" .. name
      if path ~= target and ModImports.accepts(entry, name) then
        local info = f.getInfo(path, "file")
        if info and (not entry.size or info.size == nil
                     or info.size == entry.size) then
          return path
        end
      end
    end
  end
  return nil
end

-- Shared store, then the mod's own folder, then the inbox.  No picker, no
-- prompt: this is the "you already gave us this cartridge" path and it must be
-- tried before anything asks.
function ModImports.acquire(manifest, entry)
  -- IS IT ALREADY THERE?  Asked FIRST, and it was not asked at all.
  --
  -- Without this the next branch finds the file in the shared bank and
  -- installs it again -- over a copy byte-for-byte identical to itself.  For
  -- the 64 MB cartridge this API was written for that was a wasteful no-op
  -- nobody noticed.  For a 1.4 GB disc it is 1.4 GB rewritten every time the
  -- player presses the mod's own import button, and then a return of "used the
  -- one you already imported", which reads like a refusal and is why a mod
  -- stopped there instead of going on to extract.
  --
  -- `present` is its own answer rather than folded into "shared", so a mod can
  -- tell "I have just fetched this for you" from "it was already in place"
  -- without parsing the sentence.
  if ModImports.have(manifest, entry) == true then
    return true, "present"
  end
  local banked = ModImports.sharedSource(entry)
  if banked then
    local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                  { savePath = banked },
                                                  { fromShared = true })
    if ok then return true, "shared", notes end
    return false, why
  end
  -- Both of these answer a PATH now, and installFrom streams it: the file may
  -- be a 1.4 GB disc and the point is never to hold one.
  local path = ModImports.fromModFolder(manifest, entry)
  if path then
    local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                  { savePath = path })
    if ok then return true, "mod folder", notes end
    return false, why
  end
  path = ModImports.fromInbox(entry)
  if path then
    local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                  { savePath = path })
    if ok then return true, "inbox", notes end
    return false, why
  end
  return false, nil
end

local function commandOutput(command)
  local ok, HostShell = pcall(require, "src.core.HostShell")
  if not ok then return nil end
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  pipe:close()
  result = tostring(result or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return result ~= "" and result or nil
end

-- A native "choose a file" dialog for one entry's extensions.  Deliberately
-- the same three shells the ROM button already uses, so a player who can pick
-- a Game Boy cartridge can pick a base file.  nil means "this platform has no
-- picker", which is a normal answer, not an error.
function ModImports.pickPath(entry)
  local exts = ModImports.extensions(entry)
  if #exts == 0 then return nil end
  if not (love and love.system and love.system.getOS) then return nil end
  local okPlatform, Platform = pcall(require, "src.core.Platform")
  if okPlatform and Platform.canSpawnProcess and not Platform.canSpawnProcess() then
    return nil
  end
  local prompt = "Choose your " .. tostring(entry.name or "file")
  local os_ = love.system.getOS()
  local quoted, globs, semis = {}, {}, {}
  for index, ext in ipairs(exts) do
    quoted[index] = '"' .. ext .. '"'
    globs[index] = "*." .. ext
    semis[index] = "*." .. ext
  end
  if os_ == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {%s})' 2>/dev/null]])
        :format(prompt, table.concat(quoted, ", ")))
  elseif os_ == "Windows" then
    -- the ASCII-temp-name copy the ROM picker does, and for the same reason:
    -- io.open on Windows needs ANSI bytes, and a cartridge path with a
    -- non-ASCII folder in it cannot be opened otherwise
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Base file (" .. table.concat(semis, ";") .. ")|"
        .. table.concat(semis, ";") .. "|All files (*.*)|*.*';",
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_modimport_pick.bin';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput('powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif os_ == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Base file | %s" 2>/dev/null]])
        :format(prompt, table.concat(globs, " ")))
    if path then return path end
    return commandOutput(
      ([[kdialog --getopenfilename "$HOME" "%s|Base file" 2>/dev/null]])
        :format(table.concat(globs, " ")))
  end
  return nil
end

-- Android / iOS: love.system.pickFile drops the pick into the save directory
-- under a fixed basename and returns immediately, so the answer arrives on a
-- later frame.  ModImports.poll consumes it.
ModImports.PICK_NAMES = { "picked_base.bin", "picked_rom.gb", "picked_rom.gbc",
                          "picked_rom.z64", "picked_rom.n64", "picked_rom.v64" }

local function mobilePick()
  if not (love and love.system and love.system.pickFile) then return false end
  local ok, started = pcall(love.system.pickFile, "base")
  if ok and started then return true end
  ok, started = pcall(love.system.pickFile, "rom")
  return (ok and started) and true or false
end

-- Consume a mobile pick if one has landed.  Safe to call every frame.
function ModImports.poll(manifest, entry)
  local f = fs()
  if not (f and entry) then return false end
  for _, name in ipairs(ModImports.PICK_NAMES) do
    if f.getInfo(name, "file") then
      -- STREAMED, and removed only once it has landed.  This is the Android
      -- path, which is exactly where reading a 64 MB cartridge into one string
      -- was killing the process -- and the pick is a real file in the save
      -- directory, so there is nothing to hold.
      local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                    { savePath = name })
      f.remove(name)
      return ok, notes or why or "that is not the right file"
    end
  end
  return false
end

-- TELL THE MOD ITS BASE FILE IS THERE.
--
-- A base file is not the end of anything -- it is the START of whatever the
-- mod does with it, which for a disc is usually an extraction that takes
-- minutes.  The engine has no idea what that is, so the only correct thing it
-- can do is say "it is here" and get out of the way.
--
-- Without this the manager's row was a dead end: a player with the file
-- already in place pressed it, got "ALREADY IMPORTED", and nothing ran -- the
-- engine had swallowed the one press that was meant to start the work.
--
-- `already` distinguishes "this just arrived" from "you pressed the row and it
-- was already here", because a mod may want to build on the first and rebuild
-- on the second.  Returns whether anything was actually listening, so the
-- caller can tell a press that started something from one that did not.
ModImports.READY_EVENT = "imports.ready"

function ModImports.announce(manifest, entry, already)
  if not (manifest and entry) then return false end
  local ok, Runtime = pcall(require, "src.mods.Runtime")
  if not (ok and type(Runtime) == "table" and Runtime.emit) then return false end
  -- `wants` is the cheap guard the rest of the engine uses, and here it is
  -- also the ANSWER: no listener means no mod asked to be told, which is what
  -- the manager reports instead of pretending something began.
  if Runtime.wants and not Runtime.wants(ModImports.READY_EVENT) then
    return false
  end
  Runtime.emit(ModImports.READY_EVENT, {
    mod = manifest.id,
    import = entry.id,
    file = entry.file,
    already = already and true or false,
  })
  return true
end

-- WHAT THE ENGINE ACTUALLY SEES for one entry, in one line, for a log.
--
-- A mod that reports "not imported" while the panel beside it says READY is
-- two components disagreeing about the same file, and every way of guessing
-- which one is wrong costs a round trip with somebody who just wants to play.
-- This says, from the engine's side: which ids are declared, which one was
-- asked for, where that file is expected, and whether it is there.
-- `live` is the mod's OWN imports object when the caller can reach it (the
-- loader keeps one per mod).  That is the last thing this cannot otherwise
-- see: every check here can read correct against a freshly built api while the
-- object the mod is actually holding answers differently, and those are two
-- completely different bugs.
function ModImports.diagnose(manifest, entry, live)
  local ids = {}
  for _, row in ipairs(ModImports.of(manifest) or {}) do
    ids[#ids + 1] = tostring(row.id)
  end
  local path = entry and ModImports.pathFor(manifest, entry) or nil
  local f = fs()
  local info = (f and path) and f.getInfo(path, "file") or nil
  local ok, why = false, nil
  if entry then ok, why = ModImports.have(manifest, entry) end
  -- ...AND WHAT THE MOD-FACING API ITSELF ANSWERS, asked through the same
  -- public call a mod makes.  Everything above is the engine checking its own
  -- bookkeeping, and all of it can be right while `mod.imports:info(id)` still
  -- hands a mod nil -- which is the disagreement worth splitting, because one
  -- answer means the engine is wrong and the other means the mod is holding a
  -- different object than it thinks.
  local apiSays = "?"
  pcall(function()
    local probe = ModImports.api(manifest, nil)
    local row = probe and probe.info and probe.info(nil, entry and entry.id)
    apiSays = row and ("row(ready=" .. tostring(row.ready) .. ")") or "nil"
  end)
  -- ...and the same question put to the object the MOD is holding.
  local liveSays = "unavailable"
  if live then
    liveSays = "?"
    pcall(function()
      if type(live.info) ~= "function" then
        liveSays = "no info fn (" .. type(live.info) .. ")"
        return
      end
      -- THE SECOND RETURN IS THE ANSWER.  `info` answers (row) or (nil, why),
      -- and a wrapper around it -- a mod normalising CISO/trimmed disc images,
      -- say -- puts its whole diagnosis in that second value.  Throwing it
      -- away left "nil" on its own, which says something failed and nothing
      -- about what, and cost several rounds of guessing.
      local row, why = live:info(entry and entry.id)
      liveSays = row and ("row(ready=" .. tostring(row.ready) .. ")")
                 or ("nil(" .. tostring(why) .. ")")
      -- ALWAYS list what the live object declares, and emphatically not only
      -- when the lookup succeeded: a nil lookup is the case this line exists
      -- for, and the list beside it is what says WHY -- an id spelled
      -- differently, a shorter list, or an empty one because the object was
      -- built from a manifest that declared nothing.  Printing it only on
      -- success withheld the evidence in precisely the failure it was added
      -- to explain.
      if type(live.list) == "function" then
        local declared = {}
        for _, r in ipairs(live:list() or {}) do
          declared[#declared + 1] = tostring(r.id)
        end
        liveSays = liveSays .. " of [" .. table.concat(declared, ",") .. "]"
      end
      -- WHEN THE LOOKUP FAILED, SAY WHAT THE OBJECT ACTUALLY IS.
      --
      -- Naming the one method that was missing produced a riddle -- an object
      -- with `info` and no `list` matches neither the imports api nor the
      -- cache, and every guess at which third thing it might be cost another
      -- round trip.  The object's own shape answers that in one line and needs
      -- no theory at all.
      if not row then
        local shape = {}
        for k, v in pairs(live) do shape[#shape + 1] = tostring(k) .. "=" .. type(v) end
        table.sort(shape)
        if #shape > 12 then
          shape[13] = "..."
          for i = #shape, 14, -1 do shape[i] = nil end
        end
        liveSays = liveSays .. " shape{" .. table.concat(shape, " ") .. "}"
        local mt = getmetatable(live)
        if mt then liveSays = liveSays .. "+mt" end
      end
    end)
  end
  -- AND THE RANGE READ ITSELF, which is what a wrapper is built on: a mod
  -- normalising a disc image reads its header and tables through
  -- mod.imports:read(id, offset, length) before it will call the file valid.
  -- Sixteen bytes from the front, as hex -- a GameCube disc opens with its
  -- game id, so this is both "does the read path work" and "is this the disc
  -- it claims to be", and those are the two remaining suspects.
  local head = "?"
  pcall(function()
    local probe = ModImports.api(manifest, nil)
    local bytes, err = probe.read(nil, entry and entry.id, 0, 16)
    if type(bytes) ~= "string" then
      head = "nil(" .. tostring(err) .. ")"
      return
    end
    local hex = {}
    for i = 1, #bytes do hex[i] = ("%02X"):format(bytes:byte(i)) end
    head = ("%d:%s |%s|"):format(#bytes, table.concat(hex),
                                 (bytes:gsub("%c", ".")))
  end)
  return ("mod=%s declared=[%s] asked=%s path=%s onDisk=%s have=%s api:info=%s api:read=%s mod:info=%s%s")
    :format(tostring(manifest and manifest.id),
            table.concat(ids, ","),
            tostring(entry and entry.id),
            tostring(path),
            info and tostring(info.size) or "no",
            tostring(ok),
            apiSays,
            head,
            liveSays,
            why and (" (" .. tostring(why) .. ")") or "")
end

-- The line to show when nothing else worked: where to put the file by hand.
function ModImports.hint(entry)
  local f = fs()
  local dir = (f and f.getSaveDirectory and f.getSaveDirectory()) or ""
  local exts = ModImports.extensions(entry)
  return ("Copy your %s (.%s) into:\n%s/imports/")
    :format(tostring(entry.name), table.concat(exts, "/"), dir)
end

-- One call that does the whole thing.  Returns:
--   true,  message, how   installed (or already in place)
--   nil,   message        a picker was opened; poll() will finish it
--   false, message        nothing doing; the message says where to put the file
--
-- `how` is the third return so a mod can branch on the OUTCOME rather than on
-- the wording -- "present", "shared", "mod folder", "inbox" or "picked".  A mod
-- that only reads the first two values is unaffected, which is every mod
-- written before this.
function ModImports.choose(manifest, entry)
  if not (manifest and entry) then return false, "nothing to import" end
  local ok, how = ModImports.acquire(manifest, entry)
  if ok then
    if how == "present" then
      -- Phrased as a STATE, not as something that was just declined.  "Used
      -- the one you already imported" was true and read as a refusal.
      return true, tostring(entry.name) .. " is ready", how
    elseif how == "shared" then
      return true, "Used the " .. tostring(entry.name) .. " you already imported",
             how
    elseif how == "mod folder" then
      return true, "Found your " .. tostring(entry.name) .. " in the mod folder",
             how
    end
    return true, "Imported " .. tostring(entry.name), how
  end
  if how then return false, how end   -- found something, but it was wrong

  local path = ModImports.pickPath(entry)
  if path then
    local okInstall, why, notes =
      ModImports.installFrom(manifest, entry, { path = path })
    if okInstall then
      return true, notes or ("Imported " .. tostring(entry.name)), "picked"
    end
    return false, why
  end

  if mobilePick() then
    return nil, "Choose your " .. tostring(entry.name) .. " in the file picker."
  end
  return false, ModImports.hint(entry)
end

-- HOW MUCH OF AN IMPORT ONE `read` MAY HAND BACK.
--
-- The files behind this API are cartridges: STADIUM2_IMPORTER's is a 64 MB
-- N64 ROM.  A mod walking one in chunks is the normal case, and a slice API
-- that loads the whole file per call allocates 64 MB per chunk -- which is
-- the difference between working and an out-of-memory kill on Android and
-- the Deck.  Below is what one sliced read may return; a mod that wants more
-- than this asks again with a further offset.
--
-- A WHOLE-FILE read (no offset, no length) is NOT capped: it is the call a
-- mod makes once, deliberately, for a file it already declared the size of.
ModImports.MAX_READ_BYTES = 8 * 1024 * 1024

-- One slice of a file without reading the rest of it.
--
-- love.filesystem.newFile/seek/read is the only path that actually avoids the
-- allocation; an injected fs in a test has read() and nothing else, so this
-- returns nil there and the caller falls back to reading whole and cutting.
-- Never the other way around: the fallback is the slow path, not the default.
local function slice(path, offset, length)
  local f = fs()
  if not (f and f.newFile) then return nil end
  local handle = f.newFile(path, "r")
  if not handle then return nil end
  if offset > 0 and handle.seek then
    if handle:seek(offset) == false then
      if handle.close then handle:close() end
      return nil
    end
  end
  local data = handle:read(length)
  if handle.close then handle:close() end
  return data
end

-- The mod-facing view, hung off the mod api as `mod.imports`.  A mod that
-- wants to be polite can ask whether its base file arrived before it starts,
-- rather than failing halfway through an extract.
--
-- ------- this table is a published API, so it only ever GROWS
--
-- `list`, `have`, `path` and `read` are what mods written against this engine
-- already call, and every field `list` returns is one a mod filters on --
-- `format` to offer the right extensions, `size` to size a progress bar,
-- `root` to tell a mod-folder file from a save-dir one.  A revision that
-- narrows any of them breaks a mod silently, at the one moment the mod is
-- trying to find out whether it can run at all.  `info` and the offset/length
-- arguments to `read` are additions on top; nothing above them moved.
function ModImports.api(manifest, read)
  local list = ModImports.of(manifest) or {}
  local byId = {}
  for _, entry in ipairs(list) do byId[entry.id] = entry end
  local api
  api = {
    list = function()
      local copy = {}
      for index, entry in ipairs(list) do
        copy[index] = { id = entry.id, name = entry.name, file = entry.file,
                        root = entry.root, format = entry.format,
                        size = entry.size }
      end
      return copy
    end,
    -- ...and WHY NOT, when not.  ModImports.have checks the declared size as
    -- well as existence -- a half-copied cartridge is the failure this API is
    -- for -- and the reason it gives is the one the launcher shows.
    have = function(_, id)
      local entry = byId[id]
      if not entry then return false, "no import declared with that id" end
      local ok, why = ModImports.have(manifest, entry)
      return ok == true, why
    end,
    path = function(_, id)
      local entry = byId[id]
      return entry and entry.file or nil
    end,
    -- Everything the mod declared about one import plus what is on disk now.
    -- `ready` is the same answer `have` gives, so a mod needs one call rather
    -- than two to decide whether to start.
    info = function(_, id)
      local entry = byId[id]
      if not entry then return nil end
      local ok, why = ModImports.have(manifest, entry)
      local row = { id = entry.id, name = entry.name, file = entry.file,
                    root = entry.root, format = entry.format,
                    size = entry.size, ready = ok == true, reason = why }
      local f, at = fs(), ModImports.pathFor(manifest, entry)
      local on = f and at and f.getInfo(at, "file") or nil
      if on then
        row.bytes = on.size
        row.modtime = on.modtime
      end
      -- A MANIFEST NEED NOT DECLARE A SIZE, and `size` is the field a mod
      -- bounds a chunked read with.  An entry for a disc image that does not
      -- declare one -- because the same title ships in more than one length,
      -- or because nobody wanted a 1.4 GB number in a JSON file -- left `size`
      -- nil, and a mod that reads it to work out how many chunks to ask for
      -- stops there with "import size is unavailable" even though the file is
      -- sitting right beside it and `bytes` already knew how long it was.
      --
      -- The declared size still WINS when there is one: it is the number
      -- `have` refuses a half-copied file against, and a fallback that
      -- overrode it would quietly turn that check into a tautology.  This only
      -- fills a hole.
      if row.size == nil then row.size = row.bytes end
      return row
    end,
    -- `read(id)` is the whole file; `read(id, offset, length)` is a slice,
    -- capped at MAX_READ_BYTES so chunking a cartridge stays chunked.
    read = function(_, id, offset, length)
      local entry = byId[id]
      if not entry then return nil end
      local whole = function()
        if entry.root == "save" then
          local f = fs()
          return f and f.read(entry.file) or nil
        end
        if not read then return nil end
        return read(entry.file)
      end
      if offset == nil and length == nil then return whole() end
      local at = math.floor(tonumber(offset) or 0)
      if at < 0 then return nil, "offset must not be negative" end
      local want = math.floor(tonumber(length) or ModImports.MAX_READ_BYTES)
      if want < 0 then return nil, "length must not be negative" end
      if want > ModImports.MAX_READ_BYTES then
        return nil, ("a sliced read is capped at %d bytes; ask again with a "
                     .. "further offset"):format(ModImports.MAX_READ_BYTES)
      end
      if want == 0 then return "" end
      local path = ModImports.pathFor(manifest, entry)
      local cut = path and slice(path, at, want)
      if cut ~= nil then return cut end
      local body = whole()
      if not body then return nil end
      return body:sub(at + 1, at + want)
    end,
  }
  return api
end

return ModImports