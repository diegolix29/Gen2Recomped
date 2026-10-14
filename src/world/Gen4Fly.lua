-- PLATINUM'S FLY, per pokeplatinum src/spawn_locations.c and
-- src/field_move_tasks.c.
--
-- The party menu offered every Sinnoh field move but FLY, so HM02 did nothing
-- at all. The cartridge's pieces:
--
--   * WHERE: `sSpawnLocations`, which the extractor already writes as
--     `field.healLocations` -- each row's `fly` destination (header, x, z).
--   * WHICH ARE OPEN: a row is open when its FIRST-ARRIVAL flag is set
--     (`CheckFlyLocationUnlocked`), flag SYSTEM_FLAGS_FIRST_ARRIVAL_TO_ZONE +
--     the row's `firstArrival` = 0x9B1 + n. Entering a map sets the flag of
--     the row whose fly map it is, when that row is `unlockOnMapEntry`
--     (`TryUnlockFlyLocationByMap`, run on every map change); the rest are set
--     by the maps' own scripts (`setflag 0x9C0` .. -- the Pokemon League's and
--     the routes' rows), which this port already runs.
--   * WHEN: `FieldMoves_CheckFly` -- the Cobble Badge, a map that allows Fly,
--     no partner, and not in the Great Marsh's Safari Game.
--
-- The destination is chosen from a list here, where the cartridge draws the
-- town map; the choice, the unlocking and the landing spot are the
-- cartridge's.

local Gen4Fly = {}

Gen4Fly.FIRST_ARRIVAL_BASE = 0x9B1

function Gen4Fly.flagKey(firstArrival)
  return ("FLAG_G4_%04X"):format(Gen4Fly.FIRST_ARRIVAL_BASE + (tonumber(firstArrival) or 0))
end

local function rows(data)
  return (data and data.field and data.field.healLocations) or {}
end

-- THE SPAWN TABLE NAMES MATRIX TILES, NOT THE MAP'S OWN. sSpawnLocations
-- gives Jubilife's landing as (180, 777) -- the Sinnoh matrix -- and the map
-- def is cut out of that matrix at (128, 736), so the spot is (52, 41) of
-- the map. Handed over unconverted, every fly landed far outside the town:
-- the player stood in the void. A coordinate past the map's own size is
-- taken back by the map's origin.
local function localSpot(data, mapId, x, y)
  local def = data and data.maps and data.maps[mapId]
  x, y = tonumber(x) or 0, tonumber(y) or 0
  if def and def.width and def.height and (x >= def.width or y >= def.height) then
    x, y = x - (tonumber(def.originX) or 0), y - (tonumber(def.originY) or 0)
  end
  return x, y
end
Gen4Fly.localSpot = localSpot

-- TryUnlockFlyLocationByMap: the FIRST row whose fly map is this header.
function Gen4Fly.onEnter(data, save, header)
  header = tonumber(header)
  if not (header and type(save) == "table") then return nil end
  for _, row in ipairs(rows(data)) do
    if row.fly and tonumber(row.fly.header) == header then
      if row.unlockOnMapEntry then
        save.flags = save.flags or {}
        save.flags[Gen4Fly.flagKey(row.firstArrival)] = true
        return row
      end
      return nil
    end
  end
  return nil
end

function Gen4Fly.unlocked(save, row)
  local flags = type(save) == "table" and save.flags
  return type(flags) == "table" and flags[Gen4Fly.flagKey(row.firstArrival)] == true
end

-- The open destinations, one per fly map, in spawn-table order.
function Gen4Fly.destinations(data, save)
  local out, seen = {}, {}
  for _, row in ipairs(rows(data)) do
    local fly = row.fly
    if fly and fly.map and not seen[fly.map] and Gen4Fly.unlocked(save, row) then
      seen[fly.map] = true
      local def = data.maps and data.maps[fly.map]
      local x, y = localSpot(data, fly.map, fly.x, fly.y)
      out[#out + 1] = { map = fly.map, x = x, y = y,
                        label = (def and def.label) or fly.map }
    end
  end
  return out
end

-- The spawn row the town map's choice lands at: the row carrying that
-- first-arrival id (the League and the outside of Victory Road share a map
-- header, so the header alone cannot say).
function Gen4Fly.destinationFor(data, firstArrival)
  for _, row in ipairs(rows(data)) do
    if row.fly and row.firstArrival == firstArrival then
      local x, y = localSpot(data, row.fly.map, row.fly.x, row.fly.y)
      return { map = row.fly.map, x = x, y = y }
    end
  end
  return nil
end

-- FieldMoves_CheckFly. Answers ok, or false and the reason.
function Gen4Fly.check(data, save, mapDef)
  local F = require("src.world.Gen4FieldMoves")
  if not F.badgeHeld(data, save, "FLY") then return false, "badge" end
  if not (mapDef and mapDef.allowFly) then return false, "location" end
  local okF, Follower = pcall(require, "src.world.Gen4Follower")
  if okF and Follower.hasPartner and Follower.hasPartner(save) then return false, "partner" end
  if type(save) == "table" and save.safari then return false, "location" end
  return true
end

return Gen4Fly
