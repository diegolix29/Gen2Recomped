-- `mod.imports` and `mod.cache`: the two things a ported mod asks the host for
-- before it can do any work.
--
-- Both already existed here under other names, which is the whole point of
-- this file.  A mod written against the Gen 1 port says
--
--   local rom = mod.imports:read("stadium2", offset, 0x8000)
--   mod.cache:write("models/pikachu.bin", blob)
--
-- and this engine's answers to those two questions are src/mods/ModImports.lua
-- and src/mods/Storage.lua.  So this is an ADAPTER and not a second
-- implementation: `imports` IS ModImports.api, and `cache` is the Gen 1
-- spelling of mod.storage's byte side.  Writing either one out again would
-- give the engine two import tables that drift apart and two blob stores with
-- different sandboxes -- and the sandbox is the part that has to be right.
--
-- ------- what this deliberately does NOT do
--
-- No host paths and no filesystem handles leave this file.  An import can
-- only be addressed by an id the calling mod's own manifest declares, and a
-- cache key can only land inside that mod's namespace: both id and key are
-- validated by the module that owns the namespace, not here.
--
-- ------- WHERE THE TWO SPELLINGS ACTUALLY DIVERGE
--
-- Being an adapter means the differences between the Gen 1 API and this one
-- are this file's problem, and two of them were being left for the mod to
-- discover at runtime:
--
--   * `info` ANSWERED IN THE WRONG SHAPE.  Gen 1's mod.cache:info handed back
--     a love.filesystem row, so a ported mod tests `info.type == "file"`.
--     Storage:stat answers in its own shape -- key/kind/size/modtime, and no
--     `type` at all -- so that test read false for every key that was really
--     there.  From inside the mod that is indistinguishable from an empty
--     cache: it loads, its UI works, and it never uses a byte of what it
--     wrote.  Both shapes travel now; `kind` still says bytes or record.
--
--   * A KEY THE STORE WOULD NOT TAKE WAS A DEAD END.  Storage's key rules are
--     deliberately narrow -- letters, digits, `-` `_` `.` and `/` -- because a
--     key becomes a path.  A Gen 1 mod keying its cache on a species name, a
--     file name out of a disc image, or a base64 digest gets `invalid_key` on
--     every write, and a mod that does not check the return value simply
--     caches nothing.  Rather than widening the store's rules for everybody,
--     the adapter ESCAPES what the store will not take (see cacheKey below).
--
-- Neither of those needs a second blob directory beside modstorage, and this
-- file still does not open one: same store, same namespace, same sandbox.

local ModImports = require("src.mods.ModImports")
local ModStorage = require("src.mods.Storage")

local ImportAccess = {}

-- One cache write.  mod.storage has no ceiling of its own -- it is the store
-- a mod puts a decoded 300 MB asset pack in, a key at a time -- but a SINGLE
-- key that large is a mod holding the whole thing in a Lua string, which is
-- the allocation that kills the process rather than the disk.  A mod with
-- more than this splits it, which is what the store is shaped for anyway.
ImportAccess.MAX_CACHE_WRITE_BYTES = 64 * 1024 * 1024

-- An ALIAS, not a second limit: a ported mod that reads the cap off the
-- import API finds it here, and there is still exactly one number, owned by
-- the module that enforces it.
ImportAccess.MAX_READ_BYTES = ModImports.MAX_READ_BYTES

local MAX_KEY = ModStorage.MAX_KEY or 180

-- Is this key already spelled the way the store spells keys?  Same rules as
-- Storage's own validKey, minus the upward-traversal test, which the caller
-- has already made and answers differently.
local function looksNative(key)
  if #key == 0 or #key > MAX_KEY then return false end
  if key:find("[^%w%-_%./]") then return false end
  if key:sub(1, 1) == "/" or key:sub(-1) == "/" then return false end
  if key:find("//", 1, true) then return false end
  return true
end

local function hex(c)
  return ("_%02x"):format(c:byte())
end

-- THE KEY THE STORE WILL BE GIVEN.
--
-- Three outcomes, and the order matters:
--
--   1. A key that climbs out of the namespace is REFUSED, never rewritten.  A
--      mod that asked for `../../escape.bin` gets an answer -- and the answer
--      is no -- rather than a quietly different file it did not ask for.
--   2. A key the store already accepts is handed over BYTE FOR BYTE.  This is
--      the property that makes the escape below safe to add to a shipped
--      engine: every key any mod has ever successfully written is already
--      native, so nothing that is on disk today moves, and no cache has to be
--      rebuilt.  The escape can only change keys that previously failed.
--   3. Anything else is folded to segments and escaped: `.` segments drop,
--      empty ones collapse, and every byte the store will not take becomes
--      `_` plus two hex digits.  "worlds/M2 guild (1F).fsys" is stored as
--      "worlds/M2_20guild_20_281F_29.fsys".
--
-- The one seam worth knowing about: inside branch 3, `_` is escaped too (to
-- `_5f`), so the mapping is reversible and two different awkward keys can
-- never land on one file.  What it cannot rule out is a mod writing a literal
-- native key that happens to look like somebody else's escaped one --
-- "a_20b" and "a b" share a file.  That is a collision between a key that
-- works today and one that did not work at all until now, it needs a mod to
-- use both spellings for different data, and the alternative (a reserved
-- prefix) is itself a legal key.  Listed rather than hidden.
local function cacheKey(key)
  if type(key) ~= "string" or key == "" then
    return nil, "a cache key is a non-empty string"
  end
  if key:find("\0", 1, true) then
    return nil, "a cache key may not contain a zero byte"
  end
  if key:find("\\", 1, true) then
    return nil, "a cache key separates with / rather than a backslash"
  end
  for segment in key:gmatch("[^/]+") do
    if segment == ".." then return nil, "a cache key may not traverse upward" end
  end
  if looksNative(key) then return key end

  local parts = {}
  for segment in key:gmatch("[^/]+") do
    if segment ~= "." then
      parts[#parts + 1] = (segment:gsub("[^%w%-%.]", hex))
    end
  end
  if not parts[1] then return nil, "a cache key is a non-empty string" end
  local folded = table.concat(parts, "/")
  if #folded > MAX_KEY then
    return nil, ("a cache key is at most %d characters once escaped; this one "
                 .. "is %d"):format(MAX_KEY, #folded)
  end
  return folded
end

-- mod.cache: installation-scoped generated data, in the Gen 1 port's spelling.
--
-- Same store as mod.storage (modstorage/<mod-id>/), same sandbox, same key
-- rules -- what differs is the signature.  mod.storage takes the live game as
-- its first argument so a later revision can scope by it; the Gen 1 API never
-- had one, and a ported mod calling cache:read("key") must not silently pass
-- "key" as the game.  So the game argument is dropped here and nowhere else.
--
-- Errors come back as `nil/false, code, message` -- the store's own shape, not
-- narrowed, so `local blob, err = mod.cache:read(k)` puts the machine-readable
-- code in `err` and "not_found" is a normal answer rather than a failure.
-- Nothing in here raises: a key this store will not take is a value a mod can
-- branch on, and turning that into an error would take down a mod that has
-- been checking the return value all along.
local function makeCache(modId, fs)
  local store = ModStorage.new(modId, fs)
  local cache = { modId = modId }

  function cache:write(key, bytes)
    -- ...and the Gen 1 call that passes three arguments lands here first.
    -- Dropping the game argument means `cache:write(game, key, value)` puts a
    -- table in `key` and the key in `bytes`, which would otherwise come back
    -- as a baffling "invalid_key" naming a table.
    if type(key) ~= "string" and type(bytes) == "string" then
      return false, "invalid_key",
             "mod.cache:write takes (key, bytes) -- this port has no game "
             .. "argument; mod.storage keeps the game-scoped signatures"
    end
    if type(bytes) ~= "string" then
      return false, "invalid_value", "mod.cache:write takes a byte string"
    end
    if #bytes > ImportAccess.MAX_CACHE_WRITE_BYTES then
      return false, "too_large",
             ("mod.cache:write is capped at %d bytes a key; split generated "
              .. "data across keys"):format(ImportAccess.MAX_CACHE_WRITE_BYTES)
    end
    local stored, why = cacheKey(key)
    if not stored then return false, "invalid_key", why end
    return store:writeBytes(nil, stored, bytes)
  end

  function cache:read(key)
    local stored, why = cacheKey(key)
    if not stored then return nil, "invalid_key", why end
    return store:readBytes(nil, stored)
  end

  function cache:delete(key)
    local stored, why = cacheKey(key)
    if not stored then return false, "invalid_key", why end
    return store:delete(nil, stored)
  end

  -- `list` answers in the STORED spelling, which for an escaped key is not
  -- the one the mod wrote.  Both spellings read back to the same blob -- an
  -- escaped key is native by construction, so it passes through branch 2 --
  -- so a mod that lists and then reads works either way round.
  function cache:list(prefix)
    if prefix == nil or prefix == "" then return store:list(nil, prefix) end
    local stored, why = cacheKey(prefix)
    if not stored then return nil, "invalid_key", why end
    return store:list(nil, stored)
  end

  -- size and kind without paying for the payload; see Storage:stat.  `type`
  -- rides along in love.filesystem's spelling because that is what a ported
  -- mod tests, and `key` comes back the way the MOD spelled it rather than
  -- the way the store did.
  function cache:info(key)
    local stored, why = cacheKey(key)
    if not stored then return nil, "invalid_key", why end
    local row, code, message = store:stat(nil, stored)
    if not row then return nil, code, message end
    row.key = key
    row.type = "file"
    return row
  end

  function cache:exists(key)
    local stored = cacheKey(key)
    return stored ~= nil and store:stat(nil, stored) ~= nil
  end

  -- the store underneath, for a mod that wants the game-scoped signatures or
  -- context(); handed over rather than hidden, because it is the same sandbox.
  -- It takes the store's own key spelling, so a key that needed escaping above
  -- has to be spelled the stored way here -- `mod.cache:info(k).key` is not
  -- that spelling, `mod.cache:list()` is.
  cache.storage = store
  return cache
end

-- `read` is the mod-folder reader the loader already has (relative path in,
-- bytes out).  It is passed through to ModImports.api unchanged so an
-- injected filesystem in a test reaches the same files the sandbox does.
function ImportAccess.new(manifest, fs, read)
  assert(type(manifest) == "table", "import access needs a manifest")
  return ModImports.api(manifest, read), makeCache(manifest.id, fs)
end

return ImportAccess
