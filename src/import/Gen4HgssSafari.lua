-- HEARTGOLD / SOULSILVER'S SAFARI ZONE ENCOUNTERS: /a/2/3/0, one member per
-- area type (Plains, Meadow, Savannah, Peak, Rocky Beach, Wetland, Forest,
-- Swamp, Marshland, Wasteland, Mountain, Desert).
--
-- pokeheartgold src/unk_02097268.c SafariZoneAreaSet_LoadAreaEncounters:
--
--   u8 bonusCount[5]  (land, surf, old / good / super rod), padded to 8
--   then for each of the five types:
--     base  { u16 species, u16 level } x 10 slots x 3 times of day
--     bonus { u16 species, u16 level } x n x 3 times of day
--     unlock { u8 type1, level1, type2, level2 } x n
--
-- A bonus slot replaces slot 0, 1, ... when the blocks placed in its area
-- reach its levels (src/world/HgssSafariZone.lua applies the rule).

local A = { PATH = "/a/2/3/0", SLOTS = 10, TIMES = 3, TYPES = 5 }

function A.parse(d)
  local function u8(o) return d:byte(o + 1) or 0 end
  local function u16(o) return u8(o) + u8(o + 1) * 256 end
  local out = { types = {} }
  local at = 8
  for t = 0, A.TYPES - 1 do
    local n = u8(t)
    local rec = { base = {}, bonus = {}, unlock = {}, bonusCount = n }
    for tod = 0, A.TIMES - 1 do
      local row = {}
      for s = 0, A.SLOTS - 1 do
        row[s + 1] = { species = u16(at), level = u16(at + 2) }
        at = at + 4
      end
      rec.base[tod] = row
    end
    for tod = 0, A.TIMES - 1 do
      local row = {}
      for s = 0, n - 1 do
        row[s + 1] = { species = u16(at), level = u16(at + 2) }
        at = at + 4
      end
      rec.bonus[tod] = row
    end
    for s = 0, n - 1 do
      rec.unlock[s + 1] = { u8(at), u8(at + 1), u8(at + 2), u8(at + 3) }
      at = at + 4
    end
    out.types[t] = rec
  end
  return out
end

function A.build(x)
  local Narc = require("src.import.NarcArchive")
  local arc = assert(Narc.parse(assert(x.rom:read(A.PATH))))
  local out = { source = "ROM:" .. A.PATH .. " (pokeheartgold unk_02097268.c)", areas = {} }
  for area = 0, (arc.count or 12) - 1 do
    local d = arc:get(area)
    if d then out.areas[area] = A.parse(d) end
  end
  return out
end

return A
