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
-- off ground the cartridge's moving plate reaches. Pastoria Gym's water floor
-- is a DynamicTerrainHeight plate over (1,2)-(25,39) at 0, 32 or 64 by the
-- button last pressed, with the H/M/L gates and the 0x59 tiles judged against
-- it (gym_features.c PastoriaGym_*); src/world/Gen4DynamicMapFeatures.lua keeps
-- its state, and the rule waits for the floor. Measured with the rule on:
-- the entrance reaches 70 of the gym's 708 cells.
R.UNPORTED = {
  C06GYM0101 = "Pastoria Gym's water floor",
}

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
  mover.gen4Height, mover.gen4HeightMap = h, map
  mover.gen4HeightX, mover.gen4HeightY = x, y
  return h
end

-- true when `mover` may not step onto (tx, ty) for the height between them
function R.blocks(map, mover, tx, ty)
  if not R.applies(map) or not mover then return false end
  local here = R.standingY(map, mover)
  if not here then return false end
  local list = R.surfaces(map, tx, ty)
  if not list or #list == 0 then return false end
  local there = R.nearest(list, here)
  return math.abs(there - here) >= R.MAX_STEP
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
