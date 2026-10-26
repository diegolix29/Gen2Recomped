-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A DS MAP OBJECT CANNOT STEP BETWEEN TWO GROUNDS 20 UNITS APART.
--
-- Reported from play (HeartGold, Violet Gym): *"you can walk from the ground
-- up to the top where the elevator takes you without taking the elevator, and
-- you can walk outside of the path that should be walkable at the top of the
-- elevator as well."* Falkner's gym is one tall room: the floor by the door at
-- 32 (16 on the entrance mat), the whole upper hall at 496, and nothing but the
-- terrain's own heights between them -- row 18 (496) and row 19 (32) are both
-- open ground in the permission grid. The port asked only the permission bit,
-- so the step up the 464-unit wall was a step like any other.
--
-- THE CARTRIDGE'S RULE (pokeplatinum terrain_collision_manager.c
-- GetVerticalDirection / TerrainCollisionManager_WillPlayerCollide; HGSS
-- sub_02054954 / sub_020549A8 -> bit 2 of the map object's collision flags in
-- sub_02060AF4): the height of the tile ahead, sampled at its centre and
-- chosen as the plate NEAREST the object's own height (CalculateObjectHeight;
-- a lift's dynamic plate competes the same way), against the object's own
-- height. `|ahead - here| >= 20` is a collision, whatever the permission says.
-- That one test is every raised floor on both cartridges: the Violet walkway,
-- Ecruteak's planks, Olivine's lighthouse ledges, Mahogany's ice, the Bell and
-- Burned Towers, Eterna/Canalave/Sunyshore's platforms, Mt. Coronet's ledges.
--
-- Heights come from the ground the map is drawn with (`Gen4Ground:heightsAt`,
-- which already honours `def.gen4HeightEdits` -- the lifts and platforms the
-- gym scripts move), or from `map.gen4HeightsAt(x, y)` when a headless check
-- hangs one on. No source: no rule, and the step is judged as before.
--
-- A TILE WITH NO PLATE is not judged. The cartridge answers 0 there; the port
-- reads such a tile as the ground around it (`Gen4Ground:heightAt`), and
-- doorway thresholds into raised cave mouths are exactly those tiles -- a rule
-- that refused them would be the reported cave-mouth bug again.

local R = {}

R.MAX_STEP = 20

-- PLATINUM ROOMS WHOSE MOVING FLOOR IS NOT PORTED, where the rule would wall
-- off ground the cartridge's moving plate reaches. Empty now: Pastoria Gym's
-- water floor (a DynamicTerrainHeight plate over (1,2)-(25,39) at 0, 32 or 64
-- by the button last pressed, gym_features.c PastoriaGym_*) is the plate
-- below (`def.gen4DynamicPlate`, src/world/Gen4PastoriaGym.lua), with its
-- H/M/L gates and 0x59 tiles judged against it.
R.UNPORTED = {}

-- THE DYNAMIC PLATE (pokeplatinum terrain_collision_manager.c GetHeight): a
-- rectangle of tiles whose height a gym moves (Pastoria's water floor),
-- `def.gen4DynamicPlate = { x, y, w, h, height }` in tiles. Inside it the
-- height an object takes is the BDHC plate nearest it, unless the dynamic
-- one is ABOVE that plate and nearer the object (a tie is the BDHC's):
--
--   if (dynamicHeight <= bdhcHeight) -> BDHC
--   else nearer of the two to the object's own height, BDHC on a tie
--   (no BDHC plate at all -> the dynamic height)
--
-- Answers the height and where it came from ("bdhc" | "dynamic").
function R.plateAt(map, x, y)
  local p = map and map.def and map.def.gen4DynamicPlate
  if type(p) ~= "table" then return nil end
  if x >= p.x and x < p.x + p.w and y >= p.y and y < p.y + p.h then return p end
  return nil
end

function R.resolve(map, x, y, list, objY)
  local bdhc = (list and #list > 0) and R.nearest(list, objY or 0) or nil
  local p = R.plateAt(map, x, y)
  if not p then return bdhc, bdhc and "bdhc" or nil end
  local dyn = tonumber(p.height) or 0
  if not bdhc then return dyn, "dynamic" end
  if dyn <= bdhc then return bdhc, "bdhc" end
  if math.abs(bdhc - (objY or 0)) <= math.abs(dyn - (objY or 0)) then return bdhc, "bdhc" end
  return dyn, "dynamic"
end

function R.applies(map)
  local def = map and map.def
  if not def or def.generation ~= 4 then return false end
  -- Black / White walk rails and their own levels (Gen5Field); the Distortion
  -- World walks walls and ceilings (Gen4DistSurface)
  if def.gen5 or def.gen4DistWorld then return false end
  if def.cameraFamily ~= "hgss" and R.UNPORTED[def.sourceId or def.id] then return false end
  return true
end

-- THE CARTRIDGE'S OWN LOOKUP: the plates of the tile centre's chunk found
-- through the BDHC's strip index (Gen4Bdhc.heightsVia, CalculateObjectHeight's
-- BDHC_FindStripIndexByScanline), not by testing every plate -- the brute-force
-- walk the renderer draws with finds a plate the cartridge never sees on a few
-- tiles in a thousand, and a raised plate seen there would be a wall that is
-- not one. An edit (`def.gen4HeightEdits`: lifts, platforms) replaces the
-- tile's plates, as the dynamic plate under a lift does.
local function sample(def, grid, bdhcOf, tiles, unit, half, x, y)
  local edits = def and def.gen4HeightEdits
  local over = type(edits) == "table" and edits[math.floor(x) .. "," .. math.floor(y)]
  if type(over) == "number" then return { over } end
  local mx, my = math.floor(x) + (def.originX or 0), math.floor(y) + (def.originY or 0)
  if mx < 0 or my < 0 then return {} end
  local cx, cy = math.floor(mx / tiles), math.floor(my / tiles)
  if cx >= grid.width or cy >= (grid.height or 0) then return {} end
  local land = grid.land[cy * grid.width + cx + 1]
  local bdhc = land and bdhcOf(land)
  if not bdhc then return {} end
  local Bdhc = require("src.import.Gen4Bdhc")
  local recs = Bdhc.heightsVia(bdhc, ((mx % tiles) + 0.5) * unit - half, ((my % tiles) + 0.5) * unit - half)
  local list = {}
  for i = 1, #recs do list[i] = recs[i].height end
  table.sort(list, function(a, b) return a > b end)
  return list
end

-- every surface under the centre of (x, y), or nil when there is no source
function R.surfaces(map, x, y)
  local own = map.gen4HeightsAt
  if own then return own(x, y) end
  local ground = map.renderer and map.renderer.gen4Ground
  if not ground then return nil end
  local grid, terrain = ground.grid, ground.terrain
  if ground.bdhcFor and grid and grid.land and terrain then
    local ok, list = pcall(sample, map.def or ground.def or {}, grid,
                           function(land) return ground:bdhcFor(land) end,
                           terrain.chunkTiles or 32, terrain.tileUnits or 16,
                           (terrain.chunkUnits or 512) / 2, x, y)
    if ok then return list end
  end
  if not ground.heightsAt then return nil end
  local ok, list = pcall(ground.heightsAt, ground, x, y)
  return ok and list or nil
end

function R.nearest(list, y)
  local best, gap
  for i = 1, #list do
    local h = list[i]
    local d = math.abs(h - y)
    if gap == nil or d < gap then best, gap = h, d end
  end
  return best
end

-- The height `mover` stands at, kept on the mover between steps so a bridge's
-- deck and the path under it stay apart (the nearest plate to where it was).
-- Forgotten on another map: a map object arriving by warp starts at y 0 and
-- takes the plate nearest it (MapObject_Create, then the height recalculated
-- from the terrain), which on a bridge is the path under it. A hop keeps it:
-- the cartridge recalculates the height through the jump the same way.
function R.standingY(map, mover)
  local x, y = mover.cellX, mover.cellY
  if not (x and y) then return nil end
  local list = R.surfaces(map, x, y)
  if not list then return nil end
  local held = mover.gen4Height
  if held and mover.gen4HeightMap ~= map then held = nil end
  local h
  if #list == 0 then h = held
  else h = R.nearest(list, held or 0) end
  -- ...or the dynamic plate's (Pastoria's water floor), by GetHeight's rule
  if R.plateAt(map, x, y) then h = R.resolve(map, x, y, list, held or 0) end
  mover.gen4Height, mover.gen4HeightMap = h, map
  mover.gen4HeightX, mover.gen4HeightY = x, y
  return h
end

-- true when `mover` may not step onto (tx, ty) for the height between them
-- BLACK / WHITE'S FLOORS. Reported from play (the Dreamyard): you walk
-- through the wall off the raised floor, and up the stairs without rising.
-- The zone's heights are the imported flat values (`def.gen4HeightEdits`, a
-- tile not listed being the ground at 0) and its stairs and hills are the
-- slope tiles (`def.gen5SlopeTiles`); the same 20-unit step is a wall unless
-- one end is a slope -- which is how a flight of stairs joins two floors.
R.GEN5_MOVING = { [121] = true }
function R.gen5Blocks(map, mover, tx, ty)
  local def = map and map.def
  if not (def and def.gen5 and mover and mover.cellX) then return false end
  -- (a rail map's grid is its rails rasterised: no floors of its own -- but
  -- Victory Road's are eleven flat paths at their own heights, which
  -- src/world/Gen5VictoryRoad.lua marks `gen5RailLayers`)
  if def.gen5NoGrid and not def.gen5RailLayers then return false end
  -- Drayden's gym (zone 121): its walkways are raised and lowered by the gym's
  -- own code (Gen5DragonGym), not by fixed heights -- the zones the importer
  -- keeps the layers of apart (Gen5Field.LAYERS_APART)
  if R.GEN5_MOVING[tonumber(def.header) or -1] then return false end
  local slopes = def.gen5SlopeTiles or {}
  local fk, tk = mover.cellX .. "," .. mover.cellY, tx .. "," .. ty
  if slopes[fk] or slopes[tk] then return false end
  local edits = def.gen4HeightEdits or {}
  local here, ahead = tonumber(edits[fk]) or 0, tonumber(edits[tk]) or 0
  return math.abs(ahead - here) >= R.MAX_STEP
end

function R.blocks(map, mover, tx, ty)
  if not R.applies(map) or not mover then return false end
  local here = R.standingY(map, mover)
  if not here then return false end
  local list = R.surfaces(map, tx, ty)
  local plate = R.plateAt(map, tx, ty)
  if not plate and (not list or #list == 0) then return false end
  local there, source = R.resolve(map, tx, ty, list, here)
  if math.abs(there - here) >= R.MAX_STEP then return true end
  if not plate then return false end
  -- TerrainCollisionManager_WillPlayerCollide, past the height: the gym's own
  -- rule first (PastoriaGym_DynamicMapFeaturesCheckCollision -- a gate tile
  -- opens only at ONE height of the object's own, and its answer is final),
  -- then a DYNAMIC_HEIGHT_COLLISION tile (0x59) whose height came from the
  -- plate is a wall: the water, not a floor
  local b = map.cellBehaviour and map:cellBehaviour(tx, ty)
  local gates = map.def.gen4PastoriaGates
  if gates and b and gates[b] ~= nil then return math.abs(here - gates[b]) >= 0.5 end
  return source == "dynamic" and b == 0x59
end

-- A HEADLESS SOURCE, for checks: the cache's own parsed BDHC
-- (`gen4_map_heights`) through the matrix (`gen4_terrain.matrices`), sampled
-- exactly as above.
function R.cacheSource(def, terrain, heights)
  local grid = terrain and terrain.matrices and terrain.matrices[def.layout]
  local chunks = heights and heights.chunks
  if not (grid and grid.land and chunks) then return nil end
  local tiles, unit, half = terrain.chunkTiles or 32, terrain.tileUnits or 16, (terrain.chunkUnits or 512) / 2
  return function(x, y)
    return sample(def, grid, function(land) return chunks[land] end, tiles, unit, half, x, y)
  end
end

return R
