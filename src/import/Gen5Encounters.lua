-- BLACK AND WHITE'S WILD ENCOUNTERS (/a/1/2/6, 112 tables).
--
-- A table is one season (232 bytes) or four (928: spring, summer, autumn,
-- winter, for the routes whose grass changes with the season):
--
--   00 u8 rates: grass, dark grass, rustling grass, surf, rippling surf,
--      fishing, rippling fishing, (padding)
--   08 56 slots of { u16 species (low 11 bits) | form (high 5), u8 min, u8 max }:
--      12 grass, 12 dark grass, 12 rustling, 5 surf, 5 rippling surf,
--      5 fishing, 5 rippling fishing
--
-- The layout is the research community's, confirmed against the cartridge by
-- tools/gen5_import_check.lua: Route 1 (zone 317, table 77) is Patrat and
-- Lillipup at levels 2-4. Written in Gen4Encounters' shape -- grassRate,
-- grass, surf, the rods -- so Encounter.forMap reads it as it reads
-- Platinum's, with the Gen 5 kinds beside it.

local E = {}

E.SEASON_BYTES = 232
E.GRASS_RATES = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
E.WATER_RATES = { 60, 30, 5, 4, 1 }
E.FISH_RATES = { 40, 40, 15, 4, 1 }
E.SEASONS = { "spring", "summer", "autumn", "winter" }

local function u16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end

local function slots(s, base, at, n, rates)
  local out = {}
  for i = 0, n - 1 do
    local o = base + at + i * 4
    local v = u16(s, o)
    local minL, maxL = s:byte(o + 3), s:byte(o + 4)
    out[i + 1] = { species = v % 2048, form = math.floor(v / 2048), level = minL,
                   minLevel = minL, maxLevel = maxL, chance = rates[i + 1] }
  end
  return out
end

-- season(bytes, index) -> one season's table in Gen4Encounters' shape
function E.season(s, index)
  local base = (index or 0) * E.SEASON_BYTES
  if #s < base + E.SEASON_BYTES then return nil end
  local r = function(i) return s:byte(base + i + 1) end
  return {
    family = "bw",
    grassRate = r(0),
    grass = slots(s, base, 8, 12, E.GRASS_RATES),
    darkGrassRate = r(1), darkGrass = slots(s, base, 8 + 48, 12, E.GRASS_RATES),
    rustlingRate = r(2), rustling = slots(s, base, 8 + 96, 12, E.GRASS_RATES),
    surf = { rate = r(3), slots = slots(s, base, 8 + 144, 5, E.WATER_RATES) },
    ripplingSurf = { rate = r(4), slots = slots(s, base, 8 + 164, 5, E.WATER_RATES) },
    superRod = { rate = r(5), slots = slots(s, base, 8 + 184, 5, E.FISH_RATES) },
    ripplingFishing = { rate = r(6), slots = slots(s, base, 8 + 204, 5, E.FISH_RATES) },
  }
end

-- all(archive) -> { [table] = spring's view, with .seasons = all of them }
function E.all(archive)
  local out = {}
  for i = 0, archive.count - 1 do
    local s = archive:get(i)
    if s and #s >= E.SEASON_BYTES then
      local seasons = {}
      for k = 0, math.floor(#s / E.SEASON_BYTES) - 1 do seasons[E.SEASONS[k + 1] or k] = E.season(s, k) end
      -- spring is the table itself; the other three ride beside it (a copy
      -- would only repeat it, and a reference to itself cannot be written)
      local base = seasons.spring
      base.id = i
      if #s >= E.SEASON_BYTES * 4 then
        base.seasons = { summer = seasons.summer, autumn = seasons.autumn, winter = seasons.winter }
      end
      out[i] = base
    end
  end
  return out
end

return E
