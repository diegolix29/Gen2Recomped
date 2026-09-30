-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BURYING A WALL: Mining_GenerateGameLayout, and the three loops it is.
--
-- `Gen4Mining` (src/import) is the table of what can be buried.  This is what
-- decides, for one wall, which of those rows go in and where.  It is a pure
-- function of the table, the save's two questions and a random source, so a
-- whole wall can be generated and inspected without a screen -- which is how the
-- distribution below was measured rather than argued about.
--
-- THE RANDOM SOURCE IS INJECTED, and not for testability alone: the cartridge
-- draws from `MATH_Rand32(&sMiningEnv->rand, n)`, a generator seeded per mining
-- session, and `rand(n)` here has the same contract -- a uniform integer in
-- 0 .. n-1.  Passing `love.math.random(0, n - 1)` or a seeded LCG both satisfy
-- it; nothing in here assumes which.

local Gen4MiningWall = {}

-- A fresh, empty wall.  `grid` holds the 1-based index into `objects` occupying
-- each cell, or 0 -- which is the cartridge's own sentinel
-- (`buriedObjectGrid[j][i] != 0`) and the reason indices here start at 1 and not
-- 0 as they do in Lua arrays generally.
function Gen4MiningWall.new(table_)
  local M = table_ or require("src.import.Gen4Mining")
  local grid = {}
  for y = 1, M.GRID_HEIGHT do
    local row = {}
    for x = 1, M.GRID_WIDTH do row[x] = 0 end
    grid[y] = row
  end
  return { M = M, grid = grid, objects = {}, itemCount = 0 }
end

-- Mining_TryPlaceObject.  x and y are 0-based cell coordinates.
--
-- The three refusals are the cartridge's, in its order: no free slot, the object
-- would run off the right or bottom edge, or a solid cell of it would land on a
-- cell something already occupies.  It does NOT clamp or nudge -- a bad roll is
-- simply discarded and the caller rolls again, which is why the loops below are
-- written as retries rather than as `for` over a shuffled list.
function Gen4MiningWall.tryPlace(wall, obj, x, y)
  local M = wall.M
  if #wall.objects >= M.MAX_BURIED_OBJECTS then return false end
  local endX, endY = x + obj.w, y + obj.h
  if endX > M.GRID_WIDTH then return false end
  if endY > M.GRID_HEIGHT then return false end
  -- Overlap is tested against the object's SOLID cells only, so two shaped
  -- objects may interlock through each other's holes.
  for cy = 0, obj.h - 1 do
    for cx = 0, obj.w - 1 do
      if M.solidAt(obj, cx, cy) and wall.grid[y + cy + 1][x + cx + 1] ~= 0 then
        return false
      end
    end
  end
  wall.objects[#wall.objects + 1] = { obj = obj, x = x, y = y, dugUp = false }
  local index = #wall.objects
  for cy = 0, obj.h - 1 do
    for cx = 0, obj.w - 1 do
      if M.solidAt(obj, cx, cy) then
        wall.grid[y + cy + 1][x + cx + 1] = index
      end
    end
  end
  return true
end

-- GENERATE ONE WALL.
--
-- opts.rand(n)        -> integer in 0 .. n-1 (required)
-- opts.oddTID         -> trainer id's low bit, TrainerInfo_ID(...) % 2
-- opts.nationalDex    -> Pokedex_IsNationalDexObtained
-- opts.neverMined     -> Underground_HasPlayerNeverMined
-- opts.plateMined(id) -> not Underground_HasPlateNeverBeenMined; may be nil
--
-- THE FIRST DIG IS RIGGED, and rigged twice.  `itemCount` is normally
-- `rand(MAX_BURIED_ITEMS - 1) + 2`, so two to four treasures, but a save that
-- has never mined gets exactly three -- AND no rocks at all, because the rock
-- loop is inside `if (!Underground_HasPlayerNeverMined(...))`.  A clean first
-- wall with three things in it and nothing in the way is the tutorial.
function Gen4MiningWall.generate(opts)
  opts = opts or {}
  local rand = opts.rand
  if type(rand) ~= "function" then return nil, "no random source" end
  local M = opts.table or require("src.import.Gen4Mining")
  local wall = Gen4MiningWall.new(M)

  local total = M.totalWeight(opts.oddTID, opts.nationalDex)
  if total <= 0 then return nil, "every weight is zero" end

  local itemCount = rand(M.MAX_BURIED_ITEMS - 1) + 2
  if opts.neverMined then itemCount = 3 end

  -- The plates already picked FOR THIS WALL, so one wall cannot hold two of the
  -- same plate.  The cartridge writes MINING_TREASURE_RARE_BONE into this slot
  -- for every non-plate row -- its own source marks that `// ?` -- and the value
  -- is never compared against anything but another plate id, so any sentinel
  -- outside the plate range does the same work.  `false` is that sentinel here,
  -- which says what the Rare Bone was standing in for.
  local pickedPlates = {}
  local placed, spins = 0, 0
  -- A BOUND THE CARTRIDGE DOES NOT HAVE, and it is not a behaviour change:
  -- `while (objectsPlaced < itemCount)` has no iteration limit because it cannot
  -- fail to terminate -- at most four small objects on a 13x10 grid always fit
  -- eventually.  That reasoning is sound on a console and is still a hang here if
  -- a caller passes a degenerate `rand`, so the loop gives up and says so rather
  -- than locking the game up.  Measured over 200,000 walls the worst spin count
  -- was far inside this, and the check asserts that.
  local SPIN_LIMIT = 100000
  while placed < itemCount do
    spins = spins + 1
    if spins > SPIN_LIMIT then
      return nil, "gave up placing treasures after " .. SPIN_LIMIT .. " tries"
    end
    local obj = M.pick(rand(total), opts.oddTID, opts.nationalDex)
    if obj then
      local skip = false
      -- A plate already mined on this save is re-rolled, not placed.
      if opts.plateMined and opts.plateMined(obj.id) then skip = true end
      if not skip and M.isPlate(obj.id) then
        if pickedPlates[obj.id] then skip = true else pickedPlates[obj.id] = true end
      end
      if not skip then
        local x, y = rand(M.GRID_WIDTH), rand(M.GRID_HEIGHT)
        if Gen4MiningWall.tryPlace(wall, obj, x, y) then placed = placed + 1 end
      end
    end
  end
  wall.itemCount = placed

  -- THE ROCKS: a fixed hundred attempts, not a target count.  Each try picks a
  -- rock row uniformly -- `rand(typesOfRocks) + NELEMS(sMiningObjects) -
  -- typesOfRocks`, which is an index into the tail of the table, so the rocks are
  -- uniform among themselves and their weight columns are never read.  Most tries
  -- fail once the grid fills, and that is the point: how cluttered a wall ends up
  -- is a consequence of the hundred tries, not a number anybody chose.
  if not opts.neverMined then
    local rocks = M.rocks()
    for _ = 1, 100 do
      local rock = rocks[rand(#rocks) + 1]
      local x, y = rand(M.GRID_WIDTH), rand(M.GRID_HEIGHT)
      if rock then Gen4MiningWall.tryPlace(wall, rock, x, y) end
    end
  end
  wall.spins = spins
  return wall
end

-- What is under this cell: the placed entry, or nil.
function Gen4MiningWall.at(wall, x, y)
  if not wall then return nil end
  local row = wall.grid[y + 1]
  local index = row and row[x + 1]
  if not index or index == 0 then return nil end
  return wall.objects[index], index
end

-- The treasures, in the order they were buried. Rocks are everything after
-- `itemCount`, which is the same split the cartridge uses to decide palettes
-- (`if (index >= ctx->itemCount)` in Mining_DrawBuriedObject).
function Gen4MiningWall.treasures(wall)
  local out = {}
  for i = 1, (wall and wall.itemCount or 0) do out[#out + 1] = wall.objects[i] end
  return out
end

return Gen4MiningWall