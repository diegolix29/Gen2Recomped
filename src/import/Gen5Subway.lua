-- src/import/Gen5Subway.lua -- BLACK AND WHITE'S BATTLE SUBWAY, FROM THE CARTRIDGE.
--
-- Everything the Gear Station's trains choose and pay out, decoded from the
-- ROM (Black and White alike; nothing here is typed in from a guide):
--
--   /a/2/1/5   315 trainers, Platinum's pl_btdtr shape: u16 class, u16 count,
--              u16 set ids. Member 0 is a dummy -- the subway's trainer id t
--              is member t + 1 (ov10 0x0216880C loads `id + 1` from arc 0xD7).
--              0-299 the line trainers, 300-302 Hilbert / 303-305 Hilda (the
--              Multi Train partner: attack, defense, balance), 306-313 Ingo
--              and Emmet.
--   /a/2/1/4   1,000 Pokemon sets of 16 bytes: u16 species, u16 moves x4,
--              u8 EV flags, u8 nature, u16 item, u16 form (ov10 0x021684E8
--              builds one: level 50, the trainer's IVs, EVs 510 / flagged
--              stats capped at 255, friendship 0 with Frustration).
--   /a/1/0/5   the regulations; members 20 / 21 / 22 are the Single, Double
--              and Multi trains (ov21 0x021CBC94 by play mode): byte 2 / 3 the
--              team size, byte 4 the level (50), a species bit field from
--              byte 10 (Mewtwo ... Genesect).
--   system 11  the trainers' names, by id; system 184 their lines, id * 3 +
--              0 / 1 / 2 (ov10 0x0216C6E8: intro; ov21 battle: win / loss).
--
-- And from the overlays, found by their contents rather than an address:
--
--   ov21  the trainer ranges per train (0x021DB3D0 in Black): Single /
--         Double / Multi trains 1-3 {0,49} {30,69} {50,109} for cars 1-6 and
--         {50,69} {70,89} for car 7 of trains 1-2; the Super trains 1-4
--         {110,159} .. {180,219} and {160,179} .. {220,239}, then 200-299
--         from the fifth on (ov21 0x021CBD90). Train 3's seventh car and the
--         Super trains' seventh are the bosses (306 / 307 Single, 308 / 309
--         Double, 310+311 / 312+313 Multi).
--   ov21  the BP per train (0x021DACDC): Single / Double / Multi 3 BP for
--         each of trains 1-3, the Super lines 5, 6, 7, 8, 9, then 10; a boss
--         10 (30 on a Super line) -- ov21 0x021C9DB0.
--   ov10  the class -> overworld sprite table (0x0217208C, 53 pairs; any
--         other class is sprite 10) and the four items a team that could not
--         avoid a repeated item holds instead (0x02172084).
--
-- The IV bands are code, not data (ov10 0x0216883C: compare-and-return on the
-- trainer id), so they are written out below with that address.

local Narc = require("src.import.NarcArchive")

local M = {}

M.PATH = { trainers = "/a/2/1/5", sets = "/a/2/1/4", regulations = "/a/1/0/5" }
M.REGULATION = { single = 20, double = 21, multi = 22 }
M.BANK = { names = 11, lines = 184 }

-- ov10 0x0216883C: the trainer's IVs by its id (all six alike)
M.IV_BANDS = { { 50, 3 }, { 70, 6 }, { 90, 9 }, { 110, 12 }, { 160, 15 }, { 180, 18 }, { 200, 21 } }
M.IV_TOP = 31

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

-- find(bytes, list of u16) -> 0-based offset or nil
local function findWords(bytes, words)
  local pat = {}
  for i, w in ipairs(words) do pat[i] = string.char(w % 256, math.floor(w / 256)) end
  local at = bytes:find(table.concat(pat), 1, true)
  return at and at - 1 or nil
end

function M.trainers(rom)
  local arc = Narc.parse(rom:read(M.PATH.trainers))
  local out = {}
  for m = 1, arc.count - 1 do
    local d = arc:get(m)
    if d and #d >= 4 then
      local n = u16(d, 2)
      local sets = {}
      for k = 0, n - 1 do sets[#sets + 1] = u16(d, 4 + k * 2) end
      out[m - 1] = { class = u16(d, 0), sets = sets }
    end
  end
  return out
end

function M.sets(rom)
  local arc = Narc.parse(rom:read(M.PATH.sets))
  local out = {}
  for m = 0, arc.count - 1 do
    local d = arc:get(m)
    if d and #d >= 16 then
      local raw = u16(d, 0)
      out[m] = {
        species = raw % 2048,
        moves = { u16(d, 2), u16(d, 4), u16(d, 6), u16(d, 8) },
        evFlags = d:byte(11), nature = d:byte(12), item = u16(d, 12), form = u16(d, 14),
      }
    end
  end
  return out
end

function M.regulations(rom)
  local arc = Narc.parse(rom:read(M.PATH.regulations))
  local out = {}
  for key, member in pairs(M.REGULATION) do
    local d = arc:get(member)
    if d and #d >= 12 then
      local banned = {}
      for sp = 1, 649 do   -- the field runs past the last species into other rules
        local byte = 10 + math.floor(sp / 8)
        if byte < #d and math.floor(d:byte(byte + 1) / 2 ^ (sp % 8)) % 2 == 1 then banned[#banned + 1] = sp end
      end
      out[key] = { member = member, kind = d:byte(1), minCount = d:byte(3), count = d:byte(4),
                   level = d:byte(5), levelRule = d:byte(6), banned = banned }
    end
  end
  return out
end

-- the train ranges and BP table out of overlay 21, the sprite table out of 10
function M.tables(rom)
  local out = {}
  local ov21 = rom.overlay and rom:overlay(21)
  if ov21 then
    local at = findWords(ov21, { 0, 49, 30, 69, 50, 109 })
    if at then
      local function pairsAt(o, n)
        local t = {}
        for i = 0, n - 1 do t[i + 1] = { u16(ov21, o + i * 4), u16(ov21, o + i * 4 + 2) } end
        return t
      end
      out.ranges = {
        normal = pairsAt(at, 3), normalLast = pairsAt(at - 8, 2),
        super = pairsAt(at + 12, 4), superLast = pairsAt(at + 28, 4),
        superLate = { 200, 299 },   -- ov21 0x021CBE98: rand % 100 + 200
      }
    end
    local bp = ov21:find(string.char(3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 5, 6, 7, 8, 9, 10), 1, true)
    if bp then
      local rows = {}
      for r = 0, 6 do
        local row = {}
        for k = 0, 9 do row[k + 1] = ov21:byte(bp + r * 10 + k) end
        rows[r + 1] = row
      end
      out.bp = rows
      out.bossBp, out.superBossBp = 10, 30   -- ov21 0x021C9E5A, immediates
    end
  end
  local ov10 = rom.overlay and rom:overlay(10)
  if ov10 then
    local at = findWords(ov10, { 213, 157, 234, 217, 2, 11 })
    if at then
      out.reservedItems = { u16(ov10, at), u16(ov10, at + 2), u16(ov10, at + 4), u16(ov10, at + 6) }
      local gfx = {}
      for i = 0, 52 do gfx[u16(ov10, at + 8 + i * 4)] = u16(ov10, at + 10 + i * 4) end
      out.classSprite, out.defaultSprite = gfx, 10
    end
  end
  return out
end

-- build(extractor) -> the record the importer stores as constants.gen5Subway
-- (`extractor` is RomExtractorGen5's: `.rom` and `:string(bank, index)`)
function M.build(x)
  local rom = x.rom
  local ok, trainers = pcall(M.trainers, rom)
  if not ok or not trainers then return nil end
  local rec = {
    source = "ROM:" .. M.PATH.trainers .. " + " .. M.PATH.sets .. " + " .. M.PATH.regulations .. " + ov21/ov10",
    trainers = trainers, sets = M.sets(rom), regulations = M.regulations(rom),
    ivBands = M.IV_BANDS, ivTop = M.IV_TOP, lineBank = M.BANK.lines,
  }
  for k, v in pairs(M.tables(rom)) do rec[k] = v end
  if x.string then
    rec.names = {}
    for id = 0, 313 do rec.names[id] = x:string(M.BANK.names, id) end
  end
  return rec
end

return M
