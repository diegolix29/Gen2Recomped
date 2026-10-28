-- Gen4Detail: ONE detail row for the expensive Gen 4/5 world effects, on every
-- platform (desktop and Android alike).
--
-- WHY THIS EXISTS
--
-- Measured with the PerfOverlay on Android, then applied everywhere on request:
-- the 3D trees, the 3D grass and the 3D people were the bulk of the time a Gen 4
-- map spends loading and a large share of every frame after. These cheaper
-- settings were first tied to "is this a phone"; they are now the FAST rung of
-- this row, which is the default on every platform. FULL is the old look.
--
--   FAST (default)                      FULL (the old behaviour)
--   trees  4x4-texel blocks, 150k quads/land   2x2 blocks, 450k quads/land
--   grass  within 896 units of the player      the whole engine window
--          (576 on a phone), thinned LOD       every tile, full bake
--          tufts with distance
--   people 2x texture atlas, 1 smoothing pass  4x atlas, 2 passes
--   arena  world at 0.6 size while the camera  full size while moving
--          moves, full size once it stops
--
-- Changing the row rebuilds the affected effects on the next frame.

local V = ...
local D = {}

D.KEY = "gen4Detail"
D.LABEL = "G4 DETAIL"

local okS, ModSetting = pcall(function() return V.require("ModSetting") end)
if okS and type(ModSetting) == "table" and ModSetting.new then
  -- values[1] is the default
  D.setting = ModSetting.new(D.KEY, D.LABEL, { "fast", "full" }, { "FAST", "FULL" })
end

-- Grass reach on FAST, in world units from the player (16 per tile). Full
-- density everywhere it grows: two tufts per cell read as striped rows (seen
-- on HGSS), so the saving comes from the reach alone. A phone gets less.
local MOBILE = false
do
  local ok, name = pcall(function() return love.system.getOS() end)
  MOBILE = ok and (name == "Android" or name == "iOS") or false
end
D.GRASS_REACH_FAST = MOBILE and 576 or 896

-- Grass LOD rings on FAST: { world units from the player, Grass3D LOD level }.
-- Level 1 is the whole 1719-vertex bake, 2/3/4 keep 1 clump in 3/10/24 (see
-- Grass3D.LOD_KEEP). Past the last ring the last level is used. `sparse` from
-- that level on plants two tufts a cell instead of four: at that distance the
-- rows do not read as stripes. A phone never builds the full bake.
D.GRASS_LODS_FAST = MOBILE
  and { { 160, 2 }, { 384, 3 }, { math.huge, 4 }, sparseFrom = 3 }
  or  { { 224, 1 }, { 512, 2 }, { math.huge, 3 }, sparseFrom = 3 }

D.LEVELS = {
  fast = {
    trees = { texStep = 4, maxQuads = 150000 },
    grass = { reach = D.GRASS_REACH_FAST, tilesPerCell = 4, lods = D.GRASS_LODS_FAST },
    npc = { texScale = 2, blur = 1 },
    arena = { motionScale = 0.6 },
  },
  full = {
    trees = { texStep = 2, maxQuads = 450000 },
    grass = { reach = nil, tilesPerCell = 4 },
    npc = {},
    arena = { motionScale = 1 },
  },
}

-- "fast" | "full"
function D.level()
  if D.forced == "fast" or D.forced == "full" then return D.forced end
  local s = D.setting
  local ok, v = pcall(function() return s and s.get and s:get() or nil end)
  if ok and D.LEVELS[v] then return v end
  return "fast"
end

function D.get(section)
  return D.LEVELS[D.level()][section] or {}
end

function D.row() return D.setting and D.setting:row() or nil end
function D.sync(value) if D.setting and D.setting.sync then D.setting:sync(value) end end

return D
