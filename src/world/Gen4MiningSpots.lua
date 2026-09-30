-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHERE THE DIGGABLE WALLS ARE, and they are not scattered.
--
-- `Gen4MiningWall` says what is buried in one wall.  This says which of the
-- Underground's 156,142 wall cells is a wall you can dig, and where the game
-- puts the handful it spawns.
--
-- THE RULE IS TWO CONDITIONS AND THEY ARE BOTH ABOUT THE NEIGHBOURS
-- (`Mining_CanSpawnMiningSpotOnCoordinates`, src/underground/mining.c):
--
--     if (TerrainCollisionManager_CheckCollision(fieldSystem, x, z)) {
--         if (!TerrainCollisionManager_CheckCollision(fieldSystem, x, z + 1)) return TRUE;
--         if (!TerrainCollisionManager_CheckCollision(fieldSystem, x, z - 1)) return TRUE;
--         if (!TerrainCollisionManager_CheckCollision(fieldSystem, x + 1, z)) return TRUE;
--         if (!TerrainCollisionManager_CheckCollision(fieldSystem, x - 1, z)) return TRUE;
--     }
--
-- The cell itself must be IMPASSABLE and at least one of its four cardinal
-- neighbours must be walkable: a wall face with floor in front of it, which is
-- the only kind of wall a player can stand next to and dig into.
--
-- `CheckCollision` returning TRUE meaning "blocked" is worth stating outright,
-- because reading it the other way inverts this whole function into something
-- that still runs.  `Field_CheckMapTransition` settles it: it walks one step,
-- and `if (CheckCollision(...) == FALSE) return FALSE;` -- a warp is only taken
-- when the cell stepped into IS blocked, which is the same fact that makes 16%
-- of Sinnoh's warp cells read as blocked on import.
--
-- Measured against the real Underground: 24,824 of the 480x480 map's cells
-- qualify, spread over 182 of its 225 chunks.  The neighbour test is what makes
-- that a number rather than a formality -- without it, 116,664 main-area wall
-- cells pass, so it discards 78.7% of them.

local Gen4MiningSpots = {}

-- underground/defs.h.  The main area is an OPEN rectangle: the secret-base test
-- is `x > START_X && z > START_Z && x < MAX_X && z < MAX_Z`, strict at both
-- ends, so the usable span is x 33..478 and z 65..478 rather than 32..479.
Gen4MiningSpots.MAIN_AREA_START_X = 32
Gen4MiningSpots.MAIN_AREA_START_Z = 64
Gen4MiningSpots.MAX_X = 479
Gen4MiningSpots.MAX_Z = 479
Gen4MiningSpots.MAX_MINING_SPOTS = 250

-- The cluster: one valid centre, then this many spots within ten tiles of it.
-- `MATH_Rand16(rand, 6) + 6`, so six to eleven, and `MATH_Rand16(rand, 6)` traps,
-- so zero to five.  A hundred tries each; a try that lands badly is discarded,
-- not nudged.
Gen4MiningSpots.SPOT_COUNT_BASE = 6
Gen4MiningSpots.SPOT_COUNT_SPREAD = 6
Gen4MiningSpots.TRAP_COUNT_SPREAD = 6
Gen4MiningSpots.CLUSTER_RADIUS = 10
Gen4MiningSpots.TRIES = 100

-- Gen4Maps.BLOCKED_CELL, which is what an impassable Underground cell reads as
-- and also what `Map:blockAt` border-extends with.
local BLOCKED = 255

local function solid(map, x, z)
  if not (map and map.blockAt) then return true end
  return map:blockAt(x, z) == BLOCKED
end
Gen4MiningSpots.isSolid = solid

-- UndergroundMan_AreCoordinatesInSecretBase.  Everything OUTSIDE the open
-- rectangle answers true -- the function is written as "return FALSE when
-- inside", so the whole border of the map counts as base ground.
function Gen4MiningSpots.inSecretBase(x, z)
  if x > Gen4MiningSpots.MAIN_AREA_START_X
     and z > Gen4MiningSpots.MAIN_AREA_START_Z
     and x < Gen4MiningSpots.MAX_X
     and z < Gen4MiningSpots.MAX_Z then
    return false
  end
  return true
end

-- Mining_CanSpawnMiningSpotOnCoordinates, in its own order.
function Gen4MiningSpots.canSpawnAt(map, x, z)
  if Gen4MiningSpots.inSecretBase(x, z) then return false end
  if z > Gen4MiningSpots.MAX_Z - 1 then return false end
  if x > Gen4MiningSpots.MAX_X - 1 then return false end
  if not solid(map, x, z) then return false end
  return (not solid(map, x, z + 1))
      or (not solid(map, x, z - 1))
      or (not solid(map, x + 1, z))
      or (not solid(map, x - 1, z))
end

-- A trap goes on WALKABLE ground, which is the other half of the same test and
-- the reason the two loops in Mining_SpawnMiningSpotsAndTraps look alike and are
-- not: `if (!TerrainCollisionManager_CheckCollision(...))`.
function Gen4MiningSpots.canTrapAt(map, x, z)
  return not solid(map, x, z)
end

-- THE CLUSTER.  Mining_SpawnMiningSpotsAndTraps.
--
-- rand(n) -> 0 .. n-1, the contract MATH_Rand16 has.
-- opts.matrixWidth / matrixHeight are the map's size in 32-cell chunks; the
-- cartridge reads them off the live matrix and subtracts two before scaling,
-- which is the margin the secret bases sit in.
--
-- A BOUND THE CARTRIDGE DOES NOT HAVE, again: the do/while that picks the centre
-- has no iteration limit because a 480x480 cave always has a diggable wall. True
-- on a console, still a hang here if a caller hands over a degenerate `rand` or a
-- map with no walls at all, so it gives up and says so.
function Gen4MiningSpots.spawnCluster(map, rand, opts)
  opts = opts or {}
  if type(rand) ~= "function" then return nil, "no random source" end
  local mw = opts.matrixWidth or 15
  local mh = opts.matrixHeight or 15
  local xRange = (mw - 2) * 32
  local zRange = (mh - 2) * 32
  if xRange <= 0 or zRange <= 0 then return nil, "matrix is too small" end

  local cx, cz
  for _ = 1, 10000 do
    local x = rand(xRange) + Gen4MiningSpots.MAIN_AREA_START_X
    local z = rand(zRange) + Gen4MiningSpots.MAIN_AREA_START_Z
    if Gen4MiningSpots.canSpawnAt(map, x, z) then cx, cz = x, z break end
  end
  if not cx then return nil, "found no diggable wall to centre on" end

  local R = Gen4MiningSpots.CLUSTER_RADIUS
  local spots = {}
  local wanted = rand(Gen4MiningSpots.SPOT_COUNT_SPREAD)
                 + Gen4MiningSpots.SPOT_COUNT_BASE
  for _ = 1, wanted do
    for _ = 1, Gen4MiningSpots.TRIES do
      -- `MATH_Rand16(rand, 20) + centerX - 10`: a 20-wide window centred on the
      -- centre, so the offset runs -10 .. +9 and is NOT symmetric.  Writing it
      -- as -10 .. +10 would be a 21-wide window and a different distribution.
      local x = rand(2 * R) + cx - R
      local z = rand(2 * R) + cz - R
      if Gen4MiningSpots.canSpawnAt(map, x, z) then
        if #spots >= Gen4MiningSpots.MAX_MINING_SPOTS then break end
        spots[#spots + 1] = { x = x, z = z }
        break
      end
    end
  end

  local traps = {}
  local wantedTraps = rand(Gen4MiningSpots.TRAP_COUNT_SPREAD)
  for _ = 1, wantedTraps do
    for _ = 1, Gen4MiningSpots.TRIES do
      local x = rand(2 * R) + cx - R
      local z = rand(2 * R) + cz - R
      if Gen4MiningSpots.canTrapAt(map, x, z) then
        traps[#traps + 1] = { x = x, z = z }
        break
      end
    end
  end

  return { centre = { x = cx, z = cz }, spots = spots, traps = traps,
           wanted = wanted }
end

-- Mining_SpawnMiningSpotNearBuriedSphere: the same window and the same hundred
-- tries, centred on a sphere instead of on the cluster's own centre.
function Gen4MiningSpots.spawnNearSphere(map, rand, sphereX, sphereZ)
  if type(rand) ~= "function" then return nil end
  local R = Gen4MiningSpots.CLUSTER_RADIUS
  for _ = 1, Gen4MiningSpots.TRIES do
    local x = rand(2 * R) + sphereX - R
    local z = rand(2 * R) + sphereZ - R
    if Gen4MiningSpots.canSpawnAt(map, x, z) then return { x = x, z = z } end
  end
  return nil
end

return Gen4MiningSpots