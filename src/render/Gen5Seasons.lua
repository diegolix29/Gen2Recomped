-- BLACK / WHITE: THE SEASON'S TERRAIN TEXTURES.
--
-- The field reads a zone's AREA (zone header +0x02) through ARM9 0x201407C,
-- which loads the area's 10-byte record from /a/0/1/3 at (area + season) * 10
-- whenever 2 <= area < 210 (0x20140E8), and area 0 past the table's 282.
-- The record's +2 is the texture set in /a/0/1/4 -- equal to its own index in
-- both cartridges -- and +7 the light, cycling 32 / 33 / 34 / 35 through the
-- four records of a place. The season is the game's (0x202E83C), the month's
-- place in a four-month cycle (src/world/Gen5FieldRules.lua: January, May
-- and September spring).
--
-- Every outdoor zone of the 126 that have one names the first record of its
-- four (4k + 2), so the set a zone wears in season s is its area + s:
-- Striaton's grass and trees are /a/0/1/4 sets 6, 7, 8, 9 for spring, summer,
-- autumn and winter. Every set is in the cache (Gen5Field writes all of
-- /a/0/1/4), so the season is chosen here, as a map's ground is built.
--
-- A map that shows its neighbours' chunks wears a MERGED set (Gen5Field: the
-- areas in `merged`, its own first); its season's set is merged the same
-- way from each area's season record.

local S = {}

function S.seasonal(area)
  area = tonumber(area)
  return area ~= nil and area >= 2 and area < 210
end

-- the texture set an area wears in `season` (0..3)
function S.areaFor(area, season)
  if S.seasonal(area) and season and season > 0 then return area + season end
  return area
end

-- the game's season now (0 spring .. 3 winter)
function S.current()
  local G = package.loaded["src.core.Game"]
  local ok, R = pcall(require, "src.world.Gen5FieldRules")
  if not (ok and R and R.season) then return 0 end
  local okS, s = pcall(R.season, G and G.save)
  return okS and tonumber(s) or 0
end

local cache = setmetatable({}, { __mode = "k" })

-- setFor(terrain, record, season) -> the texture set `record` (a
-- gen4_terrain.maps entry) wears in `season`; the stored one when the
-- place has no seasons
function S.setFor(terrain, record, season)
  local sets = terrain and terrain.sets
  if not (sets and record) then return nil end
  local key = record.texture
  local base = sets[key]
  season = tonumber(season) or 0
  if season <= 0 then return base end
  if key == record.area and S.seasonal(record.area) then
    return sets[S.areaFor(record.area, season)] or base
  end
  if not (base and type(base.merged) == "table") then return base end
  local byTerrain = cache[terrain]
  if not byTerrain then byTerrain = {}; cache[terrain] = byTerrain end
  local ck = tostring(key) .. "@" .. season
  if byTerrain[ck] then return byTerrain[ck] end
  local entry = { textures = {}, merged = base.merged, season = season }
  for _, area in ipairs(base.merged) do
    local set = sets[S.areaFor(area, season)] or sets[area]
    for name, tex in pairs(set and set.textures or {}) do
      if entry.textures[name] == nil then entry.textures[name] = tex end
    end
  end
  for name, tex in pairs(base.textures or {}) do
    if entry.textures[name] == nil then entry.textures[name] = tex end
  end
  byTerrain[ck] = entry
  return entry
end

return S
