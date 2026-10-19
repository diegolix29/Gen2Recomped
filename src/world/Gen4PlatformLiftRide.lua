-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S NINE PLATFORM LIFTS, RIDDEN (pokeplatinum src/platform_lift.c).
--
-- Three on Iron Island, six in the Pokemon League: a 3 x 2 slab that carries
-- the player between the room's two floors. The port had lowered the trigger to
-- a no-op because the shaft between the floors is open permission-wise
-- (src/import/Gen4PlatformLifts.lua). With the height rule
-- (src/world/Gen4HeightRule.lua) the top floor is 144 or 160 units above the
-- bottom one and is a wall from it, as on the cartridge -- so the lift has to
-- carry the player, as on the cartridge.
--
--   * on entry (`initpersistedmapfeaturesforplatformlift`): the floor is the
--     bottom one when the player arrived on the bottom warp's z, the top one
--     otherwise; the slab's tiles are pinned to that floor's height
--     (DynamicTerrainHeightManager_SetPlate -> `def.gen4HeightEdits`) and the
--     lift model is drawn there (the chunk's own copy is hidden through
--     `def.gen4ModelEdits`, a placed copy follows the height);
--   * `triggerplatformlift`: up from the bottom, down from the top -- except the
--     League's six, which never go down (`preventGoingDown`) -- 1 unit a field
--     frame (2 going up in the League), the player carried with it.

local Lifts = require("src.import.Gen4PlatformLifts")

local Ride = {}

local TILE = 16
-- sPerMapPlatformLiftConfiguration's floorHeights / preventGoingDown, by header
Ride.CONFIG = {
  [291] = { floors = { TILE * 1, TILE * 9 }, down = true,  kind = "iron" },
  [293] = { floors = { TILE * 1, TILE * 9 }, down = true,  kind = "iron", placed = { x = 16 * 19 + 8, z = 16 * 44 + 8 } },
  [294] = { floors = { TILE * 1, TILE * 9 }, down = true,  kind = "iron" },
  [176] = { floors = { 0, TILE * 10 }, down = false, kind = "league" },
  [178] = { floors = { 0, TILE * 5 },  down = false, kind = "league" },
  [180] = { floors = { 0, TILE * 5 },  down = false, kind = "league" },
  [182] = { floors = { 0, TILE * 5 },  down = false, kind = "league" },
  [184] = { floors = { 0, TILE * 5 },  down = false, kind = "league" },
  [185] = { floors = { 0, TILE * 15 }, down = false, kind = "league" },
}
-- field frames are two engine ticks (FieldDefaults.world)
Ride.TICKS_PER_FRAME = 2

local MODEL_NAMES = { "iron_island_platform_lift.nsbmd", "pokemon_league_platform_lift.nsbmd" }
local function liftModels()
  if Ride.models then return Ride.models end
  local set = {}
  local ok, A = pcall(require, "src.import.Gen4Archives")
  if ok and A and A.find then
    for _, name in ipairs(MODEL_NAMES) do
      local id = A.find("/fielddata/build_model/build_model.narc", name)
      if id then set[id] = name end
    end
  end
  Ride.models = set
  return set
end

-- The ride's state lives on the map def for as long as the map is loaded.
local function stateOf(def)
  return def and def.gen4PlatformLift
end

-- Pin the slab's tiles to `y` and draw the lift there.
function Ride.setHeight(def, data, y)
  local row = Lifts.row(def.header)
  if not row then return end
  def.gen4HeightEdits = def.gen4HeightEdits or {}
  for dx = 0, Lifts.SIZE_X - 1 do
    for dz = 0, Lifts.SIZE_Y - 1 do
      def.gen4HeightEdits[(row.start[1] + dx) .. "," .. (row.start[2] + dz)] = y
    end
  end
  local st = stateOf(def)
  if st then st.y = y end
  -- the lift model: the chunk's copy hidden, a placed copy at `y`
  local terrain = data and data.gen4_terrain
  local grid = terrain and terrain.matrices and terrain.matrices[def.layout]
  local models = liftModels()
  local props = {}
  if grid and grid.land and next(models) then
    local half = (terrain.chunkUnits or 512) / 2
    def.gen4ModelEdits = def.gen4ModelEdits or {}
    for i, land in ipairs(grid.land) do
      local rec = terrain.chunks and terrain.chunks[land]
      local own = rec and rec.objects
      if own then
        local keep, found = {}, false
        local key = tostring(land)
        local src = (st and st.ownObjects and st.ownObjects[key]) or own
        for _, o in ipairs(src) do
          if models[o.model] then
            found = true
            local cx, cz = (i - 1) % grid.width, math.floor((i - 1) / grid.width)
            props[#props + 1] = { model = o.model,
              x = o.x + half + cx * (terrain.chunkUnits or 512) - (def.originX or 0) * TILE,
              z = o.z + half + cz * (terrain.chunkUnits or 512) - (def.originY or 0) * TILE,
              y = y, rotY = o.rotY }
          else
            keep[#keep + 1] = o
          end
        end
        if found then
          if st then
            st.ownObjects = st.ownObjects or {}
            st.ownObjects[key] = st.ownObjects[key] or src
            st.edited = st.edited or {}
            st.edited[key] = true
          end
          def.gen4ModelEdits[key] = keep
        end
      end
    end
  end
  -- Iron Island B2F's left room loads its lift by hand (MapPropManager_LoadOne)
  local cfg = Ride.CONFIG[tonumber(def.header) or -1]
  if #props == 0 and cfg and cfg.placed and next(models) then
    for id, name in pairs(models) do
      if name == MODEL_NAMES[1] then
        props[1] = { model = id, x = cfg.placed.x, z = cfg.placed.z, y = y }
      end
    end
  end
  -- a fresh list each time, so Gen4Ground re-reads it
  def.gen4RuntimeProps = props
end

-- PlatformLift_DynamicMapFeaturesInit, after PersistedMapFeatures_InitForPlatformLift
function Ride.place(def, data, matrixZ)
  local cfg = def and Ride.CONFIG[tonumber(def.header) or -1]
  if not cfg then return nil end
  local floor = Lifts.floorId(def.header, matrixZ)
  def.gen4PlatformLift = { floor = floor, header = def.header }
  Ride.setHeight(def, data, cfg.floors[floor + 1])
  return floor
end

-- PlatformLift_Trigger: answers a step function for the ride (true when done),
-- or nil when the lift does not move (a League lift already at the top)
function Ride.trigger(def, data)
  local cfg = def and Ride.CONFIG[tonumber(def.header) or -1]
  local st = stateOf(def)
  if not (cfg and st) then return nil end
  if not cfg.down and st.floor == Lifts.TOP_FLOOR then return nil end
  local up = st.floor == Lifts.BOTTOM_FLOOR
  local target = cfg.floors[(up and Lifts.TOP_FLOOR or Lifts.BOTTOM_FLOOR) + 1]
  local y = st.y or cfg.floors[st.floor + 1]
  local per = ((up and cfg.kind == "league") and 2 or 1) / Ride.TICKS_PER_FRAME
  st.floor = up and Lifts.TOP_FLOOR or Lifts.BOTTOM_FLOOR
  return function()
    if up then y = math.min(target, y + per) else y = math.max(target, y - per) end
    Ride.setHeight(def, data, y)
    return y == target
  end
end

return Ride
