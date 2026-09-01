-- Pokemon Stadium 2 / Pokemon Stadium GS ROM reader.
--
-- Unlike Stadium 1, Stadium 2 keeps battle model FRAGMENTs and their skeletal
-- animation banks in two parallel resource archives.  The public reverse-
-- engineering layout used here is:
--
--   0x027ED000  battle Pokemon model archive (282 entries)
--   0x02D7D000  battle animation-bank archive (282 entries)
--
-- Archive entry N is paired with animation entry N.  Entry 0 is a non-roster
-- slot; National Dex species 1..251 live at archive entries 1..251.  The mod
-- never ships any bytes from either game -- the player selects their own ROM
-- and this reader builds local DSM packs in the save directory.

local V = ...

local StadiumRom = V.require("StadiumRom")
local StadiumFragment = V.require("StadiumFragment")

local StadiumRom2 = {}

StadiumRom2.MODEL_ARCHIVE = 0x027ED000
StadiumRom2.ANIM_ARCHIVE  = 0x02D7D000
StadiumRom2.RESOURCE_TABLE = 0x00437620
StadiumRom2.ARCHIVE_COUNT = 282
StadiumRom2.N_POKEMON = 251

-- Canonical US image published by pret/pokestadiumgs.
StadiumRom2.US_MD5 = "1561c75d11cedf356a8ddb1a4a5f9d5d"
StadiumRom2.JP_MD5 = "a17aadcc962393d476edc321e59c504b"

local byte = string.byte
local sub = string.sub

local Rom = {}
Rom.__index = Rom

-- StadiumBuild reads these off the rom instance (rom.N_MOVES etc.) instead of
-- assuming Stadium 1's shape everywhere. Falls back to Stadium 1's 165/DSM3
-- if absent, so Stadium 1's own StadiumRom.lua needs no change.
--
-- The context list is Stadium 2's REAL order as decoded from the dispatch
-- table (entries 251..270), not Stadium 1's StadiumBuild.CONTEXTS -- the two
-- lists name different roles in different positions. "idle" stays first in
-- both because StadiumBuild.pack reads ctx[1] as the idle clip regardless of
-- game. Names past "hit" are the ROM's real slots but their in-game role
-- hasn't been matched to a battle-overlay call site yet, so they're numbered
-- rather than guessed -- same caution as STADIUM2_IMPORTER's animation_dispatch.lua.
Rom.N_MOVES = 251
Rom.PACK_MAGIC = "DSM5"
Rom.CONTEXTS = {
  "idle", "entrance", "faint", "hit",
  "reaction_255", "reaction_256", "reaction_257",
  "reaction_258", "reaction_259", "reaction_260",
  "reaction_261", "reaction_262", "reaction_263",
  "reaction_264", "reaction_265", "reaction_266",
  "reaction_267", "sleep", "reaction_269", "reaction_270",
}

local function be32(s, o)
  local a, b, c, d = byte(s, o + 1, o + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function archiveInString(data, off)
  off = off or 0
  if type(data) ~= "string" or off < 0 or off + 0x10 > #data then return nil end
  local count = be32(data, off + 0x0C)
  if not count or count <= 0 or count >= 4096 then return nil end
  if off + 0x10 + count * 0x10 > #data then return nil end

  local out = {}
  for i = 0, count - 1 do
    local rec = off + 0x10 + i * 0x10
    local rel = be32(data, rec)
    local size = be32(data, rec + 4)
    if not rel or not size or rel < 0 or size < 0 then return nil end
    local start = off + rel
    if start < off or start + size > #data then return nil end
    out[i + 1] = { start = start, size = size, index = i }
  end
  return out
end

function StadiumRom2.open(bytes)
  local data = StadiumRom.normalise(bytes)
  if not data then return nil, "not an N64 ROM (bad magic)" end
  local self = setmetatable({ data = data }, Rom)

  local models = self:archive(StadiumRom2.MODEL_ARCHIVE)
  local anims = self:archive(StadiumRom2.ANIM_ARCHIVE)
  -- Relax validation: check if there are at least enough entries for Pokemon
  -- Some ROM versions may have different archive counts
  if not models or #models < StadiumRom2.N_POKEMON + 1
      or not anims or #anims < StadiumRom2.N_POKEMON + 1 then
    return nil, ("not a compatible Pokemon Stadium 2 ROM (found %d model entries, %d animation entries, need at least %d)"):format(
      models and #models or 0, anims and #anims or 0, StadiumRom2.N_POKEMON + 1)
  end
  return self
end

function Rom:u8(o)
  return byte(self.data, o + 1)
end

function Rom:u32(o)
  return be32(self.data, o) or 0
end

function Rom:archive(off)
  return archiveInString(self.data, off)
end

function Rom:title()
  local raw = sub(self.data, 0x20 + 1, 0x20 + 20)
  return (raw:gsub("%z", ""):gsub("%s+$", ""))
end

function Rom:md5()
  if self.hash ~= nil then return self.hash or nil end
  local ok, hex = pcall(function()
    local digest = love.data.hash("md5", self.data)
    if type(digest) == "userdata" and digest.getString then
      digest = digest:getString()
    end
    return love.data.encode("string", "hex", digest)
  end)
  self.hash = (ok and hex) or false
  return self.hash or nil
end

function Rom:isExpectedUS()
  local hex = self:md5()
  return hex == nil or hex == StadiumRom2.US_MD5
end

function Rom:isKnownRevision()
  local hex = self:md5()
  return hex == nil or hex == StadiumRom2.US_MD5 or hex == StadiumRom2.JP_MD5
end

function Rom:models()
  if not self.modelDir then
    self.modelDir = self:archive(StadiumRom2.MODEL_ARCHIVE) or {}
  end
  return self.modelDir
end

function Rom:animationBanks()
  if not self.animDir then
    self.animDir = self:archive(StadiumRom2.ANIM_ARCHIVE) or {}
  end
  return self.animDir
end

-- There are 282 archive records, but only National Dex 1..251 are installed.
-- Stadium 2 indexes those Pokemon by their actual species number, so build
-- fileno 0 (Bulbasaur) maps to archive record 1, not record 0.
function Rom:modelCount()
  local n = #self:models() - 1
  return n > 0 and n or 0
end

local function rosterRecord(dir, fileno)
  if type(fileno) ~= "number" or fileno < 0 then return nil end
  -- fileno 0 (Bulbasaur) maps to archive index 1, which is dir[2] in 1-based Lua
  -- So we need: dir[fileno + 2]
  return dir[fileno + 2]
end

function Rom:model(fileno)
  local rec = rosterRecord(self:models(), fileno)
  if not rec then return nil end
  local blob = sub(self.data, rec.start + 1, rec.start + rec.size)
  -- Current US GS model entries are direct FRAGMENT resources, but accepting
  -- Stadium's PERS-SZP/Yay0 wrapper here costs nothing and makes the reader
  -- tolerant of resource variants that use it.
  return StadiumRom.decompress(blob)
end

local function bankPayloads(romData, rec)
  if not rec then return nil, "animation bank is missing" end
  local raw = sub(romData, rec.start + 1, rec.start + rec.size)
  raw = StadiumRom.decompress(raw)
  local dir = archiveInString(raw, 0)
  if not dir then return nil, "animation bank has an invalid archive header" end
  local out = {}
  for i = 1, #dir do
    local r = dir[i]
    out[i] = sub(raw, r.start + 1, r.start + r.size)
  end
  return out
end

function Rom:animationPayloads(fileno)
  local rec = rosterRecord(self:animationBanks(), fileno)
  return bankPayloads(self.data, rec)
end

-- StadiumBuild calls this after the model FRAGMENT has been decoded.  The GS
-- model supplies Bone.Channel, while the paired external bank supplies the
-- actual skeletal clips.  StadiumFragment owns the sampling math so Stadium 1
-- and Stadium 2 keep one implementation of the packed/hermite track formats.
function Rom:attachAnimations(data, fileno)
  local expectedSpecies = fileno + 1
  if tonumber(data and data.species) ~= expectedSpecies then
    return false, ("Stadium 2 archive mapping mismatch: entry %d decoded as species %s (expected %d)")
      :format(expectedSpecies, tostring(data and data.species), expectedSpecies)
  end
  local payloads, err = self:animationPayloads(fileno)
  if not payloads then return false, err end
  local anims, aerr = StadiumFragment.decodeGSAnimations(payloads, data.bones)
  if not anims or #anims == 0 then
    return false, aerr or "no Stadium 2 skeletal animations decoded"
  end
  data.anims = anims
  self._animCounts = self._animCounts or {}
  self._animCounts[data.species] = #anims
  return true
end

-- Stadium 2's real per-species move-to-animation dispatch table. Verified
-- against pret/pokestadiumgs: a compressed archive at 0x01718000, 279
-- records (species N's record sits at archive index N -- unlike the model
-- and animation archives, this one has no record-zero placeholder), each
-- holding 271 rows of 0x14 bytes: 251 Gen II move IDs (row n selects move
-- n + 1) followed by 20 fixed battle-context rows. Byte 0 of a row is the
-- animation selector, byte 1 is the signed auxiliary (texture/facial)
-- selector, -1 meaning none.
--
-- Rom:battleRows below returns this table at full width -- all 251 move
-- rows and all 20 real context rows, in the ROM's own order (see
-- Rom.CONTEXTS) -- now that the DSM5 pack format and StadiumBuild carry a
-- per-rom slot count instead of assuming Stadium 1's 165+20 shape.
StadiumRom2.DISPATCH_ARCHIVE = 0x01718000
StadiumRom2.DISPATCH_RECORDS = 279
StadiumRom2.DISPATCH_ROW_SIZE = 0x14
StadiumRom2.DISPATCH_ROWS = 271          -- 251 moves + 20 contexts

local function signed8(v)
  if v >= 0x80 then return v - 0x100 end
  return v
end

-- One archive record decoded into 271 { selector, aux } rows, 0-based.
local function decodeDispatchRecord(payload)
  if type(payload) ~= "string" then return nil end
  local rows = {}
  for i = 0, StadiumRom2.DISPATCH_ROWS - 1 do
    local o = i * StadiumRom2.DISPATCH_ROW_SIZE
    if o + 2 > #payload then break end
    rows[i] = { byte(payload, o + 1), signed8(byte(payload, o + 2)) }
  end
  return rows
end

function Rom:dispatchArchive()
  if not self.dispatchDir then
    self.dispatchDir = self:archive(StadiumRom2.DISPATCH_ARCHIVE) or {}
  end
  return self.dispatchDir
end

-- The record's own selector base: a species whose real clip domain fits
-- inside its decoded animation count indexes clip file 0 directly; a
-- species that reaches the animation count reserves selector 0 for the
-- model's own bind pose and indexes external clips from selector 1. Mirrors
-- STADIUM2_IMPORTER's animation_semantics.lua -- derived from the species'
-- own complete record, never assumed from a role's position.
local function selectorBase(rows, animCount)
  local maximum = 0
  for i = 0, StadiumRom2.DISPATCH_ROWS - 1 do
    local row = rows[i]
    local selector = row and row[1]
    if selector and selector > maximum and selector < 0xFF then
      maximum = selector
    end
  end
  return (maximum < (animCount or 0)) and 0 or 1
end

local function exportedSelector(selector, base)
  if selector == nil then return nil end
  if selector == 0 then return 0 end
  return selector - base
end

-- Real per-species dispatch record for `species` (271 { selector, aux } rows,
-- 0-based), or nil if the archive is missing/unreadable -- battleRows falls
-- back to the generic clip in that case.
function Rom:dispatchRows(species)
  local archive = self:dispatchArchive()
  if #archive ~= StadiumRom2.DISPATCH_RECORDS then return nil end
  local rec = archive[species]
  if not rec then return nil end
  local ok, bytes = pcall(sub, self.data, rec.start + 1, rec.start + rec.size)
  if not ok or type(bytes) ~= "string" then return nil end
  local ok2, payload = pcall(StadiumRom.decompress, bytes)
  if not ok2 or type(payload) ~= "string" then return nil end
  local ok3, rows = pcall(decodeDispatchRecord, payload)
  if not ok3 or type(rows) ~= "table" then return nil end
  return rows
end

-- Full width now: 251 real move slots (row m selects move m + 1) plus the
-- 20 real context rows (251..270), in the ROM's own order -- see the
-- Rom.CONTEXTS comment above for why that's a different order than Stadium
-- 1's list. rows.n = 271 tells StadiumBuild.contextTable/labelAnimations
-- where the context slots start (rows.n - #Rom.CONTEXTS), and
-- StadiumBuild.species reads rom.N_MOVES/rom.CONTEXTS/rom.PACK_MAGIC to size
-- and tag the pack accordingly.
function Rom:battleRows(species)
  local n = (self._animCounts and self._animCounts[species]) or 1
  local idle     = 0
  local attack   = n > 1 and 1 or idle

  local rows = {}
  for e = 0, StadiumRom2.DISPATCH_ROWS - 1 do rows[e] = { idle, -1 } end
  for m = 0, StadiumRom2.DISPATCH_MOVE_COUNT - 1 do rows[m] = { attack, -1 } end

  local dispatch = self:dispatchRows(species)
  if dispatch then
    local base = selectorBase(dispatch, n)
    for e = 0, StadiumRom2.DISPATCH_ROWS - 1 do
      local row = dispatch[e]
      local selector = row and exportedSelector(row[1], base)
      if selector and selector >= 0 then
        rows[e] = { selector, (row[2] and row[2] >= 0) and row[2] or -1 }
      end
    end
  end

  rows.n = StadiumRom2.DISPATCH_ROWS
  return rows
end

-- Read the rare colour (shiny) metadata for a species from Stadium 2 ROM.
-- The rare colour operation is stored as 4 bytes: hue (10.6 deg), saturation, lightness.
-- FF FF FF FF indicates a special texture (not recoloured).
function Rom:rareColour(species)
  if type(species) ~= "number" or species < 1 or species > StadiumRom2.N_POKEMON then
    return nil
  end

  -- Stadium 2 stores rare colour data in the resource table
  -- Offset calculation: base + (species - 1) * 4
  local offset = StadiumRom2.RESOURCE_TABLE + (species - 1) * 4
  if offset + 4 > #self.data then
    return nil
  end

  local Stadium2Palette = V.require("Stadium2Palette")
  return Stadium2Palette.decodeRare(self.data, offset)
end

return StadiumRom2