-- Underwater is outdoors for escape-warp recording, but never for Fly.
local Rules = {}
local travel = { TOWN=true, CITY=true, ROUTE=true, OCEAN_ROUTE=true,
                 [1]=true, [2]=true, [3]=true, [6]=true }
function Rules.allowsTravel(def)
  return def ~= nil and travel[def.mapType] == true
end
function Rules.isOutdoor(def)
  return Rules.allowsTravel(def)
    or (def ~= nil and (def.mapType == "UNDERWATER" or def.mapType == 5))
end
function Rules.recordsEscape(from, dest)
  return Rules.isOutdoor(from) and not Rules.isOutdoor(dest)
end
function Rules.allowsEscape(def, point)
  return def ~= nil and def.allowEscaping == true and point ~= nil
end
-- THE SEA FLOOR'S WILD POKEMON live in the seaweed.  StandardWildEncounter
-- rolls waterMonsInfo when MetatileBehavior_IsWaterWildEncounter answers --
-- surfable-or-underwater AND TILE_FLAG_HAS_ENCOUNTERS -- and on an UNDERWATER
-- map the only behaviours with that bit are MB_SEAWEED (0x22) and
-- MB_SEAWEED_NO_SURFACING (0x2A).  The diver is not "surfing", so the
-- surfing-water arm of the step roll never asked; this is that question.
local UNDERWATER_ENCOUNTER = { [0x22] = true, [0x2A] = true }
function Rules.isUnderwaterEncounter(map, cx, cy)
  local def = map and map.def
  if not (def and (def.mapType == "UNDERWATER" or def.mapType == 5)) then return false end
  local b = map.cellBehaviour and map:cellBehaviour(cx, cy)
  return b ~= nil and UNDERWATER_ENCOUNTER[b] == true
end
return Rules
