-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DIGGING THE WALL: the dirt, the two tools and the collapse.
--
-- `Gen4Mining` is what can be buried, `Gen4MiningWall` puts it in a wall and
-- `Gen4MiningSpots` says which walls you may dig.  This is the game itself --
-- the seven layers of earth over the grid, what a tap takes off, and the meter
-- that ends it.  No drawing: the screen is a separate job, and everything here
-- is decidable without one, which is how the numbers below were measured.

local Gen4MiningDig = {}

-- INITIAL_WALL_INTEGRITY, and the two damages (mining.c).  A pickaxe tap costs
-- 4 and a hammer 8, so a wall survives 49 pickaxe taps or 25 hammer taps -- 24
-- hammer blows leave 4, and the 25th clamps to zero rather than wrapping.
Gen4MiningDig.INITIAL_WALL_INTEGRITY = 196
Gen4MiningDig.PICKAXE_DAMAGE = 4
Gen4MiningDig.HAMMER_DAMAGE = 8

-- Every cell starts at 2 and the stamps below raise some of it.
Gen4MiningDig.BASE_DIRT = 2
Gen4MiningDig.MAX_DIRT = 6

-- Mining_RandomizeDirtLayers' two stamps, verbatim.  Ten of the 8x8 at level 4,
-- then up to fifteen of the 5x5 at level 6.
Gen4MiningDig.LAYER4_MAP = {
  { 0, 0, 4, 4, 4, 4, 0, 0 },
  { 0, 4, 4, 4, 4, 4, 4, 0 },
  { 4, 4, 4, 4, 4, 4, 0, 0 },
  { 4, 4, 4, 4, 4, 4, 0, 0 },
  { 4, 4, 4, 4, 4, 4, 0, 0 },
  { 4, 4, 4, 4, 4, 4, 0, 0 },
  { 0, 4, 4, 4, 4, 4, 4, 0 },
  { 0, 0, 4, 4, 4, 4, 0, 0 },
}
Gen4MiningDig.LAYER6_MAP = {
  { 0, 6, 6, 6, 0 },
  { 6, 6, 6, 6, 6 },
  { 6, 6, 6, 6, 6 },
  { 6, 6, 6, 6, 6 },
  { 0, 6, 6, 6, 0 },
}
Gen4MiningDig.LAYER4_LEN = 8
Gen4MiningDig.LAYER6_LEN = 5

local function grid(w, h, v)
  local out = {}
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = v end
    out[y] = row
  end
  return out
end

-- THE DIRT FIELD.  Mining_RandomizeDirtLayers, including both of the things it
-- does that look like slips and are what the cartridge runs.
--
-- QUIRK ONE, and pokeplatinum marks it `// ?` itself:
--
--     startX = MATH_Rand32(rand, MINING_GAME_WIDTH  + dirtLayer4MapLength) - dirtLayer4MapLength;
--     startY = MATH_Rand32(rand, MINING_GAME_HEIGHT + dirtLayer4MapLength) - dirtLayer6MapLength; // ?
--
-- X subtracts 8, the 8x8 stamp's own length.  Y subtracts 5, the OTHER stamp's.
-- So the level-4 blobs run startY -5..12 where startX runs -8..12: the stamp can
-- hang five rows off the top and twelve off the bottom, and the level-4 terrain
-- sits lower in the grid than a symmetric reading would put it.
--
-- QUIRK TWO, unmarked: the fifteen level-6 stamps decide WHERE THEY MAY GO by
-- reading `dirtLayer4Map` -- the 8x8 -- while writing through `dirtLayer6Map`,
-- the 5x5.  The test therefore masks with the 8x8's top-left 5x5 corner, which
-- is a different shape from the one it then writes.  Both are reproduced; the
-- test mask is spelled out below rather than sliced at runtime, so it is
-- visible rather than looking like an indexing accident of this port's own.
Gen4MiningDig.LAYER6_TEST_MASK = {
  { 0, 0, 4, 4, 4 },
  { 0, 4, 4, 4, 4 },
  { 4, 4, 4, 4, 4 },
  { 4, 4, 4, 4, 4 },
  { 4, 4, 4, 4, 4 },
}

function Gen4MiningDig.randomizeDirt(rand, W, H)
  W = W or 13
  H = H or 10
  local dirt = grid(W, H, Gen4MiningDig.BASE_DIRT)
  local L4, L6 = Gen4MiningDig.LAYER4_LEN, Gen4MiningDig.LAYER6_LEN
  local map4, map6 = Gen4MiningDig.LAYER4_MAP, Gen4MiningDig.LAYER6_MAP
  local test6 = Gen4MiningDig.LAYER6_TEST_MASK

  for _ = 1, 10 do
    local sx = rand(W + L4) - L4
    local sy = rand(H + L4) - L6     -- the `// ?`: L6, not L4
    for y = sy, sy + L4 - 1 do
      if y >= 0 and y < H then
        for x = sx, sx + L4 - 1 do
          if x >= 0 and x < W then
            local v = map4[y - sy + 1][x - sx + 1]
            if v ~= 0 then dirt[y + 1][x + 1] = v end
          end
        end
      end
    end
  end

  for _ = 1, 15 do
    local sx = rand(W + L6) - L6
    local sy = rand(H + L6) - L6
    local canAdd = true
    for y = sy, sy + L6 - 1 do
      if y >= 0 and y < H then
        for x = sx, sx + L6 - 1 do
          if x >= 0 and x < W then
            -- the 8x8's corner, not the 5x5 it is about to write
            if test6[y - sy + 1][x - sx + 1] ~= 0 and dirt[y + 1][x + 1] < 4 then
              canAdd = false
              break
            end
          end
        end
      end
      if not canAdd then break end
    end
    if canAdd then
      for y = sy, sy + L6 - 1 do
        if y >= 0 and y < H then
          for x = sx, sx + L6 - 1 do
            if x >= 0 and x < W then
              local v = map6[y - sy + 1][x - sx + 1]
              if v ~= 0 then dirt[y + 1][x + 1] = v end
            end
          end
        end
      end
    end
  end
  return dirt
end

-- A fresh game over a wall from Gen4MiningWall.generate.
function Gen4MiningDig.new(wall, rand)
  if not (wall and type(rand) == "function") then return nil, "need a wall and a rand" end
  local M = wall.M
  return {
    wall = wall,
    M = M,
    dirt = Gen4MiningDig.randomizeDirt(rand, M.GRID_WIDTH, M.GRID_HEIGHT),
    integrity = Gen4MiningDig.INITIAL_WALL_INTEGRITY,
    hits = 0,
  }
end

local function lower(dirt, x, y, W, H, by)
  if x < 0 or y < 0 or x >= W or y >= H then return end
  for _ = 1, by do
    -- Each decrement is separately guarded in the cartridge, which is what keeps
    -- a cell at 1 from going negative when two are applied.
    if dirt[y + 1][x + 1] ~= 0 then dirt[y + 1][x + 1] = dirt[y + 1][x + 1] - 1 end
  end
end

-- ONE TAP.  Mining_RemoveDirt, then the wall damage its caller applies.
--
--   centre     -2, both tools
--   adjacent   -1 with the pickaxe, -2 with the hammer
--   diagonal    0 with the pickaxe, -1 with the hammer
--
-- AND AN EXPOSED ROCK STOPS THE SPREAD DEAD: if the centre holds a rock and its
-- dirt has just reached zero, the function RETURNS before touching a single
-- neighbour. The centre's own two levels are already gone by then, so a rock
-- costs you the tap and the wall, and gives nothing back.
function Gen4MiningDig.dig(state, x, y, pickaxe)
  if not state then return nil end
  local M, dirt = state.M, state.dirt
  local W, H = M.GRID_WIDTH, M.GRID_HEIGHT
  if x < 0 or y < 0 or x >= W or y >= H then return nil, "off the grid" end

  lower(dirt, x, y, W, H, 2)

  local placed = select(1, require("src.world.Gen4MiningWall").at(state.wall, x, y))
  local cleared = dirt[y + 1][x + 1] == 0
  local index = select(2, require("src.world.Gen4MiningWall").at(state.wall, x, y))
  local isRock = placed and index and index > state.wall.itemCount
  local hitRock = cleared and isRock or false
  local foundItem = cleared and placed and not isRock or false

  if not hitRock then
    if not pickaxe then
      for _, d in ipairs({ { 1, 1 }, { -1, -1 }, { -1, 1 }, { 1, -1 } }) do
        lower(dirt, x + d[1], y + d[2], W, H, 1)
      end
    end
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } }) do
      lower(dirt, x + d[1], y + d[2], W, H, pickaxe and 1 or 2)
    end
  end

  local damage = pickaxe and Gen4MiningDig.PICKAXE_DAMAGE or Gen4MiningDig.HAMMER_DAMAGE
  if state.integrity > damage then
    state.integrity = state.integrity - damage
  else
    state.integrity = 0
  end
  state.hits = state.hits + 1

  return { hitRock = hitRock, foundItem = foundItem }
end

-- Mining_AreAllItemsDugUp: a treasure is out when EVERY solid cell of it reads
-- zero.  Rocks are not counted -- they are the entries past `itemCount`.
function Gen4MiningDig.treasuresOut(state)
  local wall, dirt = state.wall, state.dirt
  local M = state.M
  local out = {}
  for i = 1, wall.itemCount do out[i] = true end
  for y = 0, M.GRID_HEIGHT - 1 do
    for x = 0, M.GRID_WIDTH - 1 do
      local index = wall.grid[y + 1][x + 1]
      if index ~= 0 and index <= wall.itemCount then
        if dirt[y + 1][x + 1] ~= 0 then out[index] = false end
      end
    end
  end
  local n = 0
  for i = 1, wall.itemCount do if out[i] then n = n + 1 end end
  return out, n
end

-- "won" the moment the last treasure is clear, "collapsed" when the meter hits
-- zero, nil while the game is still running.  The cartridge tests them in this
-- order, so a tap that frees the last treasure AND empties the meter is a win.
function Gen4MiningDig.finished(state)
  if not state then return nil end
  local _, n = Gen4MiningDig.treasuresOut(state)
  if n >= state.wall.itemCount then return "won" end
  if state.integrity == 0 then return "collapsed" end
  return nil
end

return Gen4MiningDig