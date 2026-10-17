-- NdsSave -- what Platinum, HeartGold/SoulSilver and Black/White saves share.
--
-- All three are 512 KiB of flash, every block guarded by a CRC16-CCITT, and
-- every Pokemon a 136-byte record (236 in a Gen 4 party, 220 in a Gen 5 one)
-- whose four 32-byte blocks are shuffled by the personality and XORed with a
-- PRNG stream. The layouts are pokeplatinum / pokeheartgold's own structs and
-- PKHeX's SAV4Pt / SAV4HGSS / SAV5BW offsets; the BW one was checked against
-- a DeSmuME save the cartridge itself wrote (tmp/bw_reference/content.dsv).
--
-- EMULATORS DO NOT ALL WRITE THE SAME FILE. melonDS, DraStic and most others
-- write the raw 524288 bytes; DeSmuME's .dsv appends a 122-byte footer; no$gba
-- wraps the image in its own header and may run-length compress it; a few
-- tools pad the file to 1 MiB. `unwrap` turns any of them into the raw image,
-- and `wrapDesmume` writes the .dsv form back out.
--
-- Pure Lua (LuaJIT's bit library), no love.* at require time.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local NdsSave = {}

NdsSave.SIZE = 0x80000

-- ------------------------------------------------------------- byte buffer --
-- A mutable 0-based byte array built from a string; ffi when it is there
-- (LuaJIT, LOVE), a plain table otherwise.
local okFfi, ffi = pcall(require, "ffi")

local Buf = {}
Buf.__index = Buf

function NdsSave.buffer(src)
  local n = type(src) == "number" and src or #src
  local self = setmetatable({ n = n }, Buf)
  if okFfi then
    self.b = ffi.new("uint8_t[?]", n)
    if type(src) == "string" then ffi.copy(self.b, src, n) end
  else
    local b = {}
    if type(src) == "string" then
      for i = 0, n - 1 do b[i] = src:byte(i + 1) end
    else
      for i = 0, n - 1 do b[i] = 0 end
    end
    self.b = b
  end
  return self
end

function Buf:u8(o) return self.b[o] end
function Buf:u16(o) return self.b[o] + self.b[o + 1] * 256 end
function Buf:u32(o)
  return self.b[o] + self.b[o + 1] * 256 + self.b[o + 2] * 65536 + self.b[o + 3] * 16777216
end
function Buf:set8(o, v) self.b[o] = math.floor(v) % 256 end
function Buf:set16(o, v)
  v = math.floor(v) % 65536
  self.b[o] = v % 256; self.b[o + 1] = math.floor(v / 256)
end
function Buf:set32(o, v)
  v = math.floor(v) % 4294967296
  for i = 0, 3 do self.b[o + i] = v % 256; v = math.floor(v / 256) end
end
function Buf:sub(o, n)
  if okFfi then return ffi.string(self.b + o, n) end
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.char(self.b[o + i]) end
  return table.concat(t)
end
function Buf:put(o, s)
  if okFfi then ffi.copy(self.b + o, s, #s) return end
  for i = 1, #s do self.b[o + i - 1] = s:byte(i) end
end
function Buf:fill(o, n, v)
  if okFfi then ffi.fill(self.b + o, n, v) return end
  for i = o, o + n - 1 do self.b[i] = v end
end
function Buf:copy(dst, src, n)
  if okFfi then ffi.copy(self.b + dst, self.b + src, n) return end
  for i = 0, n - 1 do self.b[dst + i] = self.b[src + i] end
end
function Buf:string() return self:sub(0, self.n) end

-- ------------------------------------------------------------------ CRC16 --
-- CCITT, polynomial 0x1021, seed 0xFFFF: CalcCRC16Checksum in both decomps.
local CRC = {}
for i = 0, 255 do
  local c = lshift(i, 8)
  for _ = 1, 8 do
    if band(c, 0x8000) ~= 0 then c = band(bxor(lshift(c, 1), 0x1021), 0xFFFF)
    else c = band(lshift(c, 1), 0xFFFF) end
  end
  CRC[i] = c
end

function NdsSave.crc16(buf, off, len)
  local c = 0xFFFF
  local b = buf.b
  for i = off, off + len - 1 do
    c = bxor(band(lshift(c, 8), 0xFFFF), CRC[bxor(rshift(c, 8), b[i])])
  end
  return c
end

-- ------------------------------------------------------- emulator wrappers --
local DESMUME_TAG = "|-DESMUME SAVE-|"
local DESMUME_SNIP = "|<--Snip above here to create a raw sav by excluding this DeSmuME savedata footer:"
local NOCASH_MAGIC = "NocashGbaBackupMediaSavDataFile"

local function le32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end
local function str32(v)
  v = math.floor(v) % 4294967296
  return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256,
    math.floor(v / 16777216) % 256)
end

-- no$gba: "NocashGbaBackupMediaSavDataFile" 0x1A, then at 0x40 "SRAM", u32
-- compression (0 plain, 1 run-length), u32 size; plain data starts at 0x4C,
-- compressed data at 0x50 after its own u32 length. The run-length codes are
-- 00 end, 01..7F copy that many bytes, 80..FF repeat the next byte (n-80h).
local function unwrapNocash(bytes)
  if bytes:sub(0x41, 0x44) ~= "SRAM" then return nil end
  local mode, size = le32(bytes, 0x44), le32(bytes, 0x48)
  if mode == 0 then return bytes:sub(0x4D, 0x4C + size) end
  if mode ~= 1 then return nil end
  local out, i = {}, 0x51
  local total = 0
  while i <= #bytes and total < size do
    local c = bytes:byte(i); i = i + 1
    if c == 0 then break
    elseif c < 0x80 then
      out[#out + 1] = bytes:sub(i, i + c - 1); i = i + c; total = total + c
    else
      local n = c - 0x80
      out[#out + 1] = string.rep(bytes:sub(i, i), n); i = i + 1; total = total + n
    end
  end
  local raw = table.concat(out)
  if #raw < size then raw = raw .. string.rep("\255", size - #raw) end
  return raw:sub(1, size)
end

-- unwrap(bytes) -> raw image, container name | nil, error
function NdsSave.unwrap(bytes)
  if type(bytes) ~= "string" then return nil, "expected save bytes" end
  local size = NdsSave.SIZE
  if #bytes == size then return bytes, "raw" end
  if bytes:sub(1, #NOCASH_MAGIC) == NOCASH_MAGIC then
    local raw = unwrapNocash(bytes)
    if raw and #raw >= size then return raw:sub(1, size), "no$gba" end
    return nil, "this no$gba save could not be unpacked"
  end
  if bytes:sub(-#DESMUME_TAG) == DESMUME_TAG then
    -- the footer says how much of the file is the save: its first u32 (after
    -- the snip line) is the real size
    local at = bytes:find(DESMUME_SNIP, 1, true)
    local real = at and le32(bytes, at - 1 + #DESMUME_SNIP) or size
    if real >= size then return bytes:sub(1, size), "desmume" end
    return nil, ("this DeSmuME save holds %d bytes, not a 512 KB DS save"):format(real)
  end
  -- padded (1 MiB flash images, trailing junk): the first 512 KiB is the save
  if #bytes > size then return bytes:sub(1, size), "padded" end
  return nil, ("a DS save is %d bytes (512 KB); this file is %d"):format(size, #bytes)
end

-- DeSmuME's .dsv: the raw image and the footer it writes for 512 KiB flash
-- (sizes, backup type 6, address size 3), copied from a save it produced.
function NdsSave.wrapDesmume(raw)
  local size = #raw
  return raw .. DESMUME_SNIP .. str32(size) .. str32(size) .. str32(6) .. str32(3)
    .. str32(size) .. str32(0) .. DESMUME_TAG
end

-- ------------------------------------------------------- Pokemon records --
NdsSave.STORED = 136
NdsSave.PARTY4 = 236
NdsSave.PARTY5 = 220

-- ABCD order for each of the 24 shuffles: canonical block i lives at stored
-- position ORDER[sv][i] (PKHeX BlockPosition)
local ORDER = {
  {0,1,2,3},{0,1,3,2},{0,2,1,3},{0,3,1,2},{0,2,3,1},{0,3,2,1},
  {1,0,2,3},{1,0,3,2},{2,0,1,3},{3,0,1,2},{2,0,3,1},{3,0,2,1},
  {1,2,0,3},{1,3,0,2},{2,1,0,3},{3,1,0,2},{2,3,0,1},{3,2,0,1},
  {1,2,3,0},{1,3,2,0},{2,1,3,0},{3,1,2,0},{2,3,1,0},{3,2,1,0},
}

-- seed * 0x41C64E6D + 0x6073 (mod 2^32), exact in doubles
local function nextSeed(seed)
  local lo = (seed * 0x4E6D) % 4294967296
  local hi = ((seed * 0x41C6) % 65536) * 65536
  return (lo + hi + 0x6073) % 4294967296
end

-- XOR a byte table range [from, to) as u16 words with the stream
local function crypt(t, from, to, seed)
  for o = from, to - 1, 2 do
    seed = nextSeed(seed)
    local x = math.floor(seed / 65536)
    t[o] = bxor(t[o], x % 256)
    t[o + 1] = bxor(t[o + 1], math.floor(x / 256))
  end
end

local function toTable(s)
  local t = {}
  for i = 1, #s do t[i - 1] = s:byte(i) end
  return t, #s
end
local function toString(t, n)
  local parts = {}
  for i = 0, n - 1 do parts[#parts + 1] = string.char(t[i]) end
  return table.concat(parts)
end
local function t16(t, o) return t[o] + t[o + 1] * 256 end
local function t32(t, o) return t[o] + t[o + 1] * 256 + t[o + 2] * 65536 + t[o + 3] * 16777216 end

function NdsSave.pkmChecksum(t)
  local sum = 0
  for o = 8, 0x86, 2 do sum = sum + t16(t, o) end
  return sum % 65536
end

-- stored (encrypted, shuffled) -> canonical bytes, checksumOk
function NdsSave.decryptPkm(stored)
  local t, n = toTable(stored)
  local pid, chk = t32(t, 0), t16(t, 6)
  crypt(t, 8, NdsSave.STORED, chk)
  if n > NdsSave.STORED then crypt(t, NdsSave.STORED, n, pid) end
  local sv = math.floor(pid / 8192) % 32 % 24
  local order = ORDER[sv + 1]
  local out = {}
  for i = 0, 7 do out[i] = t[i] end
  for i = NdsSave.STORED, n - 1 do out[i] = t[i] end
  for block = 0, 3 do
    local from = 8 + order[block + 1] * 32
    for k = 0, 31 do out[8 + block * 32 + k] = t[from + k] end
  end
  return toString(out, n), NdsSave.pkmChecksum(out) == chk
end

-- canonical -> stored; refreshes the checksum first
function NdsSave.encryptPkm(canon)
  local t, n = toTable(canon)
  local chk = NdsSave.pkmChecksum(t)
  t[6], t[7] = chk % 256, math.floor(chk / 256)
  local pid = t32(t, 0)
  local sv = math.floor(pid / 8192) % 32 % 24
  local order = ORDER[sv + 1]
  local out = {}
  for i = 0, 7 do out[i] = t[i] end
  for i = NdsSave.STORED, n - 1 do out[i] = t[i] end
  for block = 0, 3 do
    local to = 8 + order[block + 1] * 32
    for k = 0, 31 do out[to + k] = t[8 + block * 32 + k] end
  end
  crypt(out, 8, NdsSave.STORED, chk)
  if n > NdsSave.STORED then crypt(out, NdsSave.STORED, n, pid) end
  return toString(out, n)
end

-- an empty slot is NOT zero bytes: the cartridge encrypts a zeroed record
-- with checksum 0 like any other, and reads raw zeros as a Bad Egg
function NdsSave.emptyPkm(size)
  return NdsSave.encryptPkm(string.rep("\0", size or NdsSave.STORED))
end

-- ------------------------------------------------------------------- text --
-- Gen 4 writes the font's own character codes (the ROM charmap the cache
-- carries in font.lua); Gen 5 writes UTF-16. Both end at 0xFFFF.
local function utf8chars(s)
  return (s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*")
end
local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
local function codepoint(ch)
  local a, b, c = ch:byte(1, 3)
  if a < 0x80 then return a end
  if a < 0xE0 then return (a - 0xC0) * 64 + (b - 0x80) end
  return (a - 0xE0) * 4096 + (b - 0x80) * 64 + (c - 0x80)
end

-- a codec: { decode(words) -> string, encode(string, max) -> words }
function NdsSave.textCodec(gen, charmap)
  if gen >= 5 then
    -- the two gender symbols sit in the private area on the cartridge
    local toUni = { [0x246D] = 0x2642, [0x246E] = 0x2640 }
    local fromUni = { [0x2642] = 0x246D, [0x2640] = 0x246E }
    return {
      decode = function(words)
        local out = {}
        for _, w in ipairs(words) do
          if w == 0xFFFF or w == 0 then break end
          out[#out + 1] = utf8char(toUni[w] or w)
        end
        return table.concat(out)
      end,
      encode = function(s, max)
        local words = {}
        for ch in utf8chars(s) do
          if #words >= max then break end
          local cp = codepoint(ch)
          words[#words + 1] = fromUni[cp] or cp
        end
        return words
      end,
    }
  end
  local toSeq, fromSeq = {}, {}
  for _, row in ipairs((charmap and charmap.charmap) or charmap or {}) do
    if type(row) == "table" and row.code and type(row.seq) == "string" then
      toSeq[row.code] = toSeq[row.code] or row.seq
      if not fromSeq[row.seq] then fromSeq[row.seq] = row.code end
    end
  end
  -- the font has no plain-ASCII apostrophe/quote twins of its own; keep the
  -- straight forms writable by borrowing the curly ones' codes
  fromSeq["'"] = fromSeq["'"] or fromSeq["’"]
  return {
    decode = function(words)
      local out = {}
      for _, w in ipairs(words) do
        if w == 0xFFFF then break end
        out[#out + 1] = toSeq[w] or ""
      end
      return table.concat(out)
    end,
    encode = function(s, max)
      local words = {}
      for ch in utf8chars(s) do
        if #words >= max then break end
        local code = fromSeq[ch] or fromSeq[ch:upper()]
        if code then words[#words + 1] = code end
      end
      return words
    end,
  }
end

-- words from / to a byte string region (n u16 slots, 0xFFFF-terminated,
-- the rest padded with 0xFFFF the way the games pad their names... except
-- trash bytes from a template, which the record keeps when unchanged)
function NdsSave.readWords(t16fn, off, n)
  local words = {}
  for i = 0, n - 1 do words[i + 1] = t16fn(off + i * 2) end
  return words
end

-- ---------------------------------------------------- canonical <-> engine --
local STAT_KEYS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
NdsSave.STAT_KEYS = STAT_KEYS
local CONTEST_KEYS = { "cool", "beauty", "cute", "smart", "tough", "sheen" }

-- ball byte <-> item id. 1..16 are the item ids themselves; HGSS's Apricorn
-- balls (items 492..499) are 17..24, BW's Dream Ball (item 576) is 25.
local function ballToItem(b)
  if b >= 1 and b <= 16 then return b end
  if b >= 17 and b <= 24 then return 492 + (b - 17) end
  if b == 25 then return 576 end
  return 4
end
local function itemToBall(id)
  id = tonumber(id)
  if not id then return 4 end
  if id >= 1 and id <= 16 then return id end
  if id >= 492 and id <= 499 then return 17 + (id - 492) end
  if id == 576 then return 25 end
  return 4
end
NdsSave.ballToItem, NdsSave.itemToBall = ballToItem, itemToBall

local BALL_NAMES = {
  MASTER_BALL = 1, ULTRA_BALL = 2, GREAT_BALL = 3, POKE_BALL = 4, SAFARI_BALL = 5,
  NET_BALL = 6, DIVE_BALL = 7, NEST_BALL = 8, REPEAT_BALL = 9, TIMER_BALL = 10,
  LUXURY_BALL = 11, PREMIER_BALL = 12, DUSK_BALL = 13, HEAL_BALL = 14,
  QUICK_BALL = 15, CHERISH_BALL = 16,
}

local STATUS_BITS = { PSN = 0x08, BRN = 0x10, FRZ = 0x20, PAR = 0x40, TOX = 0x80 }

-- What the species record says its abilities are, as ids in slot order.
function NdsSave.abilityIds(ctx, def)
  if not def then return {} end
  if type(def.abilityIds) == "table" then return def.abilityIds end
  local names = def.abilities or {}
  local out = {}
  for i, name in ipairs(names) do out[i] = ctx.abilityByName[name] or 0 end
  return out
end

local function speciesDef(ctx, species, form)
  local data = ctx.data
  local def = data.pokemon and data.pokemon[species]
  if form and form > 0 and ctx.formDefinition then
    local ok, fdef = pcall(ctx.formDefinition, data, { species = species, form = form })
    if ok and fdef then return fdef end
  end
  return def
end

-- canonical bytes (136/236/220) -> engine mon, or nil for an empty slot
function NdsSave.decodeMon(canon, ctx, isParty)
  local t = toTable(canon)
  local species = t16(t, 0x08)
  if species == 0 then return nil end
  local gen = ctx.gen
  local pid = t32(t, 0x00)
  local tid, sid = t16(t, 0x0C), t16(t, 0x0E)
  local ivWord = t32(t, 0x38)
  local flags40 = t[0x40]
  local form = math.floor(flags40 / 8)
  local mon = {
    species = species,
    form = form,
    personality = pid,
    otId = tid + sid * 65536,
    secretId = sid,
    exp = t32(t, 0x10),
    happiness = t[0x14],
    evs = {}, ivs = {}, contest = {}, moves = {},
    ndsRaw = canon:sub(1, NdsSave.STORED),
    ndsGame = t[0x5F],
  }
  for i, k in ipairs(STAT_KEYS) do mon.evs[k] = t[0x17 + i] end
  for i, k in ipairs(CONTEST_KEYS) do mon.contest[k] = t[0x1D + i] end
  for i, k in ipairs(STAT_KEYS) do mon.ivs[k] = math.floor(ivWord / 2 ^ ((i - 1) * 5)) % 32 end
  -- the engine's Johto-era DVs ride along on every mon; keep them derived
  mon.dvs = { hp = math.floor(mon.ivs.hp / 2), attack = math.floor(mon.ivs.attack / 2),
    defense = math.floor(mon.ivs.defense / 2), speed = math.floor(mon.ivs.speed / 2),
    special = math.floor(mon.ivs.spatk / 2) }
  if math.floor(ivWord / 2 ^ 30) % 2 == 1 then mon.isEgg = true end
  local nicknamed = math.floor(ivWord / 2 ^ 31) % 2 == 1
  local item = t16(t, 0x0A)
  if item ~= 0 then mon.item = item end
  local markings = t[0x16]
  if markings ~= 0 then mon.markings = markings end
  for i = 1, 4 do
    local id = t16(t, 0x26 + i * 2)
    if id ~= 0 then
      mon.moves[#mon.moves + 1] = { id = id, pp = t[0x2F + i], ppUps = t[0x33 + i] }
    end
  end
  if flags40 % 2 == 1 then mon.fatefulEncounter = true end
  if math.floor(flags40 / 4) % 2 == 1 then mon.gender = "none"
  elseif math.floor(flags40 / 2) % 2 == 1 then mon.gender = "female"
  else mon.gender = "male" end
  -- nature: Gen 4 derives it from the personality, Gen 5 stores it
  local natureIndex = gen >= 5 and t[0x41] or pid % 25
  local order = ctx.natureOrder
  mon.nature = order and order[natureIndex + 1] or natureIndex
  mon.ndsNature = natureIndex
  -- ability: which of the species' slots this record's id is
  local def = speciesDef(ctx, species, form)
  local abilityId = t[0x15]
  local ids = NdsSave.abilityIds(ctx, def)
  if gen >= 5 and t[0x42] % 2 == 1 then
    mon.abilitySlot = 3
  else
    for slot, id in ipairs(ids) do
      if id == abilityId and slot <= 2 then mon.abilitySlot = slot break end
    end
    if not mon.abilitySlot then mon.abilitySlot = 1 end
  end
  mon.ndsAbility = abilityId
  -- names
  local function words(off, n)
    local out = {}
    for i = 0, n - 1 do out[i + 1] = t16(t, off + i * 2) end
    return out
  end
  local nick = ctx.text.decode(words(0x48, 11))
  if nicknamed and nick ~= "" and not mon.isEgg then mon.nickname = nick end
  local ot = ctx.text.decode(words(0x68, 8))
  if ot ~= "" then mon.ot = ot end
  mon.otGender = math.floor(t[0x84] / 128) == 1 and "girl" or "boy"
  local metLevel = t[0x84] % 128
  if metLevel > 0 then mon.metLevel = metLevel end
  -- locations: Platinum/HGSS keep theirs at 0x44/0x46 and a Diamond-Pearl
  -- compatible copy at 0x7E/0x80; Gen 5 uses 0x7E/0x80 only
  local met = gen >= 5 and t16(t, 0x80) or (t16(t, 0x46) ~= 0 and t16(t, 0x46) or t16(t, 0x80))
  local egg = gen >= 5 and t16(t, 0x7E) or (t16(t, 0x44) ~= 0 and t16(t, 0x44) or t16(t, 0x7E))
  if met ~= 0 then mon.metLocation = met end
  if egg ~= 0 then mon.eggLocation = egg end
  if t[0x7B] ~= 0 then mon.metDate = { year = 2000 + t[0x7B], month = t[0x7C], day = t[0x7D] } end
  if t[0x78] ~= 0 then mon.eggDate = { year = 2000 + t[0x78], month = t[0x79], day = t[0x7A] } end
  if t[0x82] ~= 0 then mon.pokerus = t[0x82] end
  local ball = t[0x83]
  if gen == 4 and t[0x86] >= 17 then ball = t[0x86] end
  mon.ball = ballToItem(ball)
  if mon.isEgg then mon.eggCycles = mon.happiness end
  -- level and stats: the party block carries them; a box mon's come from its
  -- experience, the way the cartridge recomputes them on withdraw
  if isParty and #canon > NdsSave.STORED then
    local status = t32(t, 0x88)
    mon.level = t[0x8C]
    mon.hp = t16(t, 0x8E)
    mon.maxHp = t16(t, 0x90)
    mon.stats = { hp = mon.maxHp, attack = t16(t, 0x92), defense = t16(t, 0x94),
      speed = t16(t, 0x96), spatk = t16(t, 0x98), spdef = t16(t, 0x9A) }
    mon.stats.special = mon.stats.spatk
    if status % 8 > 0 then mon.status = "SLP"; mon.sleepTurns = status % 8
    elseif band(status, 0x80) ~= 0 then mon.status = "TOX"
    elseif band(status, 0x08) ~= 0 then mon.status = "PSN"
    elseif band(status, 0x10) ~= 0 then mon.status = "BRN"
    elseif band(status, 0x20) ~= 0 then mon.status = "FRZ"
    elseif band(status, 0x40) ~= 0 then mon.status = "PAR" end
  else
    mon.level = ctx.levelFor and ctx.levelFor(def, mon.exp) or 1
  end
  if not mon.stats and ctx.statsFor then
    local ok, stats = pcall(ctx.statsFor, def, mon)
    if ok and stats then mon.stats = stats; mon.hp = stats.hp; mon.maxHp = stats.hp end
  end
  return mon
end

-- engine mon -> canonical bytes (stored or party sized); the record it came
-- from (mon.ndsRaw) is the base, so ribbons, seals, trash bytes and every
-- other field the port does not model survive the round trip untouched
function NdsSave.encodeMon(mon, ctx, size)
  local base = type(mon.ndsRaw) == "string" and #mon.ndsRaw == NdsSave.STORED and mon.ndsRaw
    or string.rep("\0", NdsSave.STORED)
  local t = toTable(base .. string.rep("\0", size - NdsSave.STORED))
  local function w8(o, v) t[o] = math.floor(tonumber(v) or 0) % 256 end
  local function w16(o, v) v = math.floor(tonumber(v) or 0) % 65536; t[o] = v % 256; t[o + 1] = math.floor(v / 256) end
  local function w32(o, v)
    v = math.floor(tonumber(v) or 0) % 4294967296
    for i = 0, 3 do t[o + i] = v % 256; v = math.floor(v / 256) end
  end
  local gen = ctx.gen
  local species = tonumber(mon.species) or 0
  local form = tonumber(mon.form) or 0
  local fresh = base == string.rep("\0", NdsSave.STORED)
  local baseSpecies = t16(t, 0x08)
  local pid = tonumber(mon.personality)
  if not pid then
    -- a Pokemon the port built before personalities: derive one that keeps
    -- its nature and stays put across exports
    pid = ((species * 2654435761) + (tonumber(mon.exp) or 0)) % 4294967296
  end
  w32(0x00, pid)
  w16(0x04, 0)
  w16(0x08, species)
  w16(0x0A, tonumber(mon.item or mon.heldItem) or 0)
  local otFull = tonumber(mon.otId) or tonumber(ctx.player.id) or 0
  local tid = otFull % 65536
  local sid = math.floor(otFull / 65536) % 65536
  if otFull < 65536 then
    -- caught in the port: the player's own id, and the player's secret half
    sid = tonumber(mon.secretId) or ((tid == (tonumber(ctx.player.id) or -1) % 65536) and tonumber(ctx.player.secretId) or 0) or 0
  end
  w16(0x0C, tid); w16(0x0E, sid)
  w32(0x10, tonumber(mon.exp) or 0)
  w8(0x14, mon.isEgg and (tonumber(mon.eggCycles) or tonumber(mon.happiness) or 0)
    or (tonumber(mon.happiness or mon.friendship) or 70))
  -- ability
  local def = speciesDef(ctx, species, form)
  local ids = NdsSave.abilityIds(ctx, def)
  local slot = tonumber(mon.abilitySlot)
  local abilityId
  if slot and ids[slot] and ids[slot] ~= 0 then abilityId = ids[slot]
  elseif not fresh and mon.ndsAbility then abilityId = mon.ndsAbility
  else
    local pick = gen >= 5 and (math.floor(pid / 65536) % 2 + 1) or (pid % 2 + 1)
    abilityId = (ids[pick] and ids[pick] ~= 0) and ids[pick] or ids[1] or 0
  end
  w8(0x15, abilityId)
  w8(0x16, tonumber(mon.markings) or t[0x16])
  w8(0x17, ctx.language or 2)
  local evs = mon.evs or {}
  for i, k in ipairs(STAT_KEYS) do w8(0x17 + i, math.min(255, tonumber(evs[k]) or 0)) end
  local contest = mon.contest or {}
  for i, k in ipairs(CONTEST_KEYS) do w8(0x1D + i, tonumber(contest[k]) or t[0x1D + i]) end
  -- moves
  for i = 1, 4 do
    local m = (mon.moves or {})[i]
    local id = m and (tonumber(m.id) or 0) or 0
    w16(0x26 + i * 2, id)
    w8(0x2F + i, m and (tonumber(m.pp) or 0) or 0)
    w8(0x33 + i, m and (tonumber(m.ppUps) or 0) or 0)
  end
  -- IVs, egg and nickname bits
  local ivs = mon.ivs
  if not ivs and mon.dvs then
    local d = mon.dvs
    ivs = { hp = (d.hp or 0) * 2, attack = (d.attack or 0) * 2, defense = (d.defense or 0) * 2,
      speed = (d.speed or 0) * 2, spatk = (d.special or 0) * 2, spdef = (d.special or 0) * 2 }
  end
  ivs = ivs or {}
  local word = 0
  for i, k in ipairs(STAT_KEYS) do word = word + (math.min(31, tonumber(ivs[k]) or 0)) * 2 ^ ((i - 1) * 5) end
  if mon.isEgg then word = word + 2 ^ 30 end
  local defName = def and def.name or ""
  local nick = mon.nickname
  local nicknamed = (not mon.isEgg) and type(nick) == "string" and nick ~= ""
    and nick:upper() ~= tostring(defName):upper()
  if nicknamed then word = word + 2 ^ 31 end
  w32(0x38, word)
  -- fateful / gender / form
  local gender = mon.gender
  if not gender and ctx.genderOf then gender = ctx.genderOf(mon) end
  local g = tostring(gender or ""):lower()
  local flags = (mon.fatefulEncounter or mon.fateful) and 1 or 0
  if g == "female" then flags = flags + 2 elseif g == "none" or g == "genderless" then flags = flags + 4 end
  flags = flags + (form % 32) * 8
  w8(0x40, flags)
  if gen >= 5 then
    local nat = mon.ndsNature
    if ctx.natureIndex and mon.nature ~= nil then nat = ctx.natureIndex[mon.nature] or nat end
    w8(0x41, nat or (pid % 25))
    local hidden = slot == 3 and 1 or 0
    w8(0x42, (t[0x42] - t[0x42] % 2) + hidden)
  end
  -- names
  local function putWords(off, n, words)
    for i = 0, n - 1 do
      local v = words[i + 1]
      if v == nil then v = (i == #words) and 0xFFFF or 0 end
      w16(off + i * 2, v)
    end
  end
  local nameText = mon.isEgg and (ctx.eggName or "EGG") or (nicknamed and nick or defName)
  if gen == 4 and not nicknamed and not mon.isEgg then nameText = tostring(nameText):upper() end
  if fresh or nicknamed or mon.isEgg or baseSpecies ~= species then
    putWords(0x48, 11, ctx.text.encode(nameText, 10))
  end
  if fresh then w8(0x5F, ctx.gameId) end
  if fresh or mon.ot then
    putWords(0x68, 8, ctx.text.encode(mon.ot or ctx.player.name or "", 7))
  end
  -- origins
  local function date(off, d)
    if type(d) ~= "table" then return end
    w8(off, (tonumber(d.year) or 2000) - 2000); w8(off + 1, tonumber(d.month) or 1); w8(off + 2, tonumber(d.day) or 1)
  end
  date(0x78, mon.eggDate)
  date(0x7B, mon.metDate)
  local met = tonumber(mon.metLocation)
  local egg = tonumber(mon.eggLocation)
  if gen == 4 then
    if met then w16(0x46, met); w16(0x80, met) end
    if egg then w16(0x44, egg); w16(0x7E, egg) end
  else
    if met then w16(0x80, met) end
    if egg then w16(0x7E, egg) end
  end
  w8(0x82, tonumber(mon.pokerus or mon.gen4Pokerus) or t[0x82])
  local ballId = tonumber(mon.ball) or BALL_NAMES[tostring(mon.ball or "")] or 4
  local ballByte = itemToBall(ballId)
  if gen == 4 and ballByte >= 17 then
    w8(0x83, 4); w8(0x86, ballByte)
  else
    w8(0x83, ballByte)
    if gen == 4 and ctx.family == "hgss" then w8(0x86, ballByte) end
  end
  local metLevel = tonumber(mon.metLevel) or (fresh and tonumber(mon.level)) or (t[0x84] % 128)
  w8(0x84, (metLevel % 128) + ((mon.otGender == "girl" or mon.otGender == "female" or mon.otGender == 1) and 128 or 0))
  -- party block
  if size > NdsSave.STORED then
    local status = 0
    local s = mon.status
    if s == "SLP" then status = math.max(1, math.min(7, tonumber(mon.sleepTurns) or 2))
    elseif s and STATUS_BITS[s] then status = STATUS_BITS[s] end
    w32(0x88, status)
    w8(0x8C, tonumber(mon.level) or 1)
    local stats = mon.stats or {}
    local maxHp = tonumber(mon.maxHp or stats.hp) or 1
    w16(0x8E, math.max(0, math.min(maxHp, tonumber(mon.hp) or maxHp)))
    w16(0x90, maxHp)
    w16(0x92, tonumber(stats.attack) or 0)
    w16(0x94, tonumber(stats.defense) or 0)
    w16(0x96, tonumber(stats.speed) or 0)
    w16(0x98, tonumber(stats.spatk or stats.special) or 0)
    w16(0x9A, tonumber(stats.spdef or stats.special) or 0)
  end
  return toString(t, size)
end

return NdsSave
