-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that a tap takes off exactly what the cartridge says, that
-- the wall lasts exactly as long, that both of Mining_RandomizeDirtLayers'
-- oddities survive the port, and -- the part no amount of reading gives you --
-- that the game is actually winnable with these numbers.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: every constant here can be right while
-- the game is unplayable. 196 integrity, 4 and 8 damage, seven dirt layers and a
-- four-cell splash are each individually checkable and jointly decide whether
-- four buried treasures can be uncovered before the wall falls in. Section 6
-- plays 2,000 walls and reports the win rate, with a random-tapping control
-- beside it -- because a win rate of 100% would mean the wall never collapses
-- and 0% would mean it always does, and both would be the mechanics being wrong
-- in a way no constant reveals.
--
-- Usage: texlua tools/gen4_mining_dig_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local M    = require("src.import.Gen4Mining")
local Wall = require("src.world.Gen4MiningWall")
local Dig  = require("src.world.Gen4MiningDig")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function lcg(seed)
  local s = seed
  return function(n)
    s = (1103515245 * s + 12345) % 2147483648
    if n <= 0 then return 0 end
    return math.floor(s / 65536) % n
  end
end

-- ---------------------------------------------------------------------------
section("1. the constants")
-- ---------------------------------------------------------------------------
ok(Dig.INITIAL_WALL_INTEGRITY == 196, "INITIAL_WALL_INTEGRITY should be 196")
ok(Dig.PICKAXE_DAMAGE == 4, "a pickaxe tap should cost 4")
ok(Dig.HAMMER_DAMAGE == 8, "a hammer tap should cost 8")
ok(Dig.BASE_DIRT == 2, "every cell should start at dirt 2")
ok(#Dig.LAYER4_MAP == 8 and #Dig.LAYER4_MAP[1] == 8, "the level-4 stamp is 8x8")
ok(#Dig.LAYER6_MAP == 5 and #Dig.LAYER6_MAP[1] == 5, "the level-6 stamp is 5x5")
-- The stamps carry their own level in their cells; a stamp of 4s that wrote 6s
-- would be a different terrain with the same shape.
for _, row in ipairs(Dig.LAYER4_MAP) do
  for _, v in ipairs(row) do ok(v == 0 or v == 4, "the level-4 stamp holds a %d", v) end
end
for _, row in ipairs(Dig.LAYER6_MAP) do
  for _, v in ipairs(row) do ok(v == 0 or v == 6, "the level-6 stamp holds a %d", v) end
end

section("2-3. the two oddities, tested on what randomizeDirt DOES")
-- BOTH OF THESE WERE ASSERTED THE WRONG WAY ROUND FIRST, and the planted faults
-- caught it rather than the other way about.
--
-- The first version checked that `LAYER6_TEST_MASK` equals `LAYER4_MAP`'s corner
-- and that the startY histogram of a model built INSIDE this file differs from a
-- symmetric one. Both passed happily while the shipped `randomizeDirt` used the
-- tidy mask and the tidy startY, because neither assertion ever asked the
-- shipped function anything. Tables and a local model are not the code.
--
-- So: a reference implementation with each oddity on a switch, and an exact
-- cell-for-cell comparison against `Dig.randomizeDirt`. Any deviation at all
-- fails, and the two sensitivity checks below prove the comparison can see each
-- oddity individually -- otherwise "it matches" would be worth nothing.
local function reference(seedRand, quirkStartY, quirkMask)
  local W, H, L4, L6 = 13, 10, 8, 5
  local map4, map6 = Dig.LAYER4_MAP, Dig.LAYER6_MAP
  local dirt = {}
  for y = 1, H do dirt[y] = {} for x = 1, W do dirt[y][x] = 2 end end
  for _ = 1, 10 do
    local sx = seedRand(W + L4) - L4
    -- the `// ?`: the cartridge subtracts the OTHER stamp's length here
    local sy = seedRand(H + L4) - (quirkStartY and L6 or L4)
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
    local sx = seedRand(W + L6) - L6
    local sy = seedRand(H + L6) - L6
    local canAdd = true
    for y = sy, sy + L6 - 1 do
      if y >= 0 and y < H then
        for x = sx, sx + L6 - 1 do
          if x >= 0 and x < W then
            -- the cartridge guards with dirtLayer4Map, the 8x8, while writing
            -- through the 5x5
            local mask = quirkMask and map4[y - sy + 1][x - sx + 1]
                                    or map6[y - sy + 1][x - sx + 1]
            if mask ~= 0 and dirt[y + 1][x + 1] < 4 then canAdd = false break end
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
local function same(a, b)
  for y = 1, 10 do
    for x = 1, 13 do if a[y][x] ~= b[y][x] then return false, x, y end end
  end
  return true
end

local SEEDS = 400
local mismatched, firstBad = 0, nil
for seed = 1, SEEDS do
  local got = Dig.randomizeDirt(lcg(seed * 131), 13, 10)
  local want = reference(lcg(seed * 131), true, true)
  local eq, bx, by = same(got, want)
  if not eq then
    mismatched = mismatched + 1
    firstBad = firstBad or ("seed %d at %d,%d: got %d, the cartridge gives %d")
      :format(seed, bx, by, got[by][bx], want[by][bx])
  end
end
io.write(("  %d seeds compared cell for cell, %d mismatched\n"):format(SEEDS, mismatched))
ok(mismatched == 0,
   "randomizeDirt disagrees with the cartridge on %d of %d seeds -- %s",
   mismatched, SEEDS, tostring(firstBad))

-- SENSITIVITY. Each oddity switched off in the reference must change the field,
-- or the comparison above cannot see it and its passing means nothing.
for _, probe in ipairs({ { "the startY length", false, true },
                         { "the level-6 test mask", true, false } }) do
  local label, qy, qm = probe[1], probe[2], probe[3]
  local differing = 0
  for seed = 1, SEEDS do
    local a = reference(lcg(seed * 131), true, true)
    local b = reference(lcg(seed * 131), qy, qm)
    if not same(a, b) then differing = differing + 1 end
  end
  io.write(("  tidying %-22s changes %d of %d fields\n"):format(label, differing, SEEDS))
  ok(differing > SEEDS / 20,
     "tidying %s changes only %d of %d fields, so the comparison above is "
     .. "nearly blind to it", label, differing, SEEDS)
end

-- and the mask constant is still the 8x8's corner, which is what makes the
-- reference's `quirkMask` arm the cartridge's rather than a third thing
for y = 1, 5 do
  for x = 1, 5 do
    ok(Dig.LAYER6_TEST_MASK[y][x] == Dig.LAYER4_MAP[y][x],
       "the published test mask at %d,%d is %d; dirtLayer4Map's corner has %d",
       x, y, Dig.LAYER6_TEST_MASK[y][x], Dig.LAYER4_MAP[y][x])
  end
end

section("4. what one tap takes off")
-- A flat field at 6 and an empty wall, so the numbers are unambiguous.
local function flatState(level)
  local w = Wall.new(M)
  w.itemCount = 0
  local st = { wall = w, M = M, integrity = Dig.INITIAL_WALL_INTEGRITY, hits = 0, dirt = {} }
  for y = 1, M.GRID_HEIGHT do
    st.dirt[y] = {}
    for x = 1, M.GRID_WIDTH do st.dirt[y][x] = level end
  end
  return st
end
for _, tool in ipairs({ { "pickaxe", true, 2, 1, 0 }, { "hammer", false, 2, 2, 1 } }) do
  local name, pick, dCentre, dAdj, dDiag = tool[1], tool[2], tool[3], tool[4], tool[5]
  local st = flatState(6)
  Dig.dig(st, 6, 5, pick)
  ok(6 - st.dirt[6][7] == dCentre, "%s: centre fell by %d, expected %d",
     name, 6 - st.dirt[6][7], dCentre)
  ok(6 - st.dirt[6][8] == dAdj, "%s: the cell east fell by %d, expected %d",
     name, 6 - st.dirt[6][8], dAdj)
  ok(6 - st.dirt[5][7] == dAdj, "%s: the cell north fell by %d, expected %d",
     name, 6 - st.dirt[5][7], dAdj)
  ok(6 - st.dirt[7][8] == dDiag, "%s: the diagonal fell by %d, expected %d",
     name, 6 - st.dirt[7][8], dDiag)
  ok(st.dirt[6][9] == 6, "%s: a cell two away was touched", name)
end
-- a cell at 1 goes to 0, not to -1: the two decrements are separately guarded
local st = flatState(1)
Dig.dig(st, 6, 5, true)
ok(st.dirt[6][7] == 0, "a cell at 1 went to %d instead of 0", st.dirt[6][7])
local st0 = flatState(0)
Dig.dig(st0, 6, 5, false)
ok(st0.dirt[6][7] == 0, "a cell at 0 went to %d", st0.dirt[6][7])

section("5. how long the wall lasts")
for _, tool in ipairs({ { "pickaxe", true, 49 }, { "hammer", false, 25 } }) do
  local name, pick, want = tool[1], tool[2], tool[3]
  local s = flatState(6)
  local n = 0
  while s.integrity > 0 and n < 500 do
    Dig.dig(s, 0, 0, pick)
    n = n + 1
  end
  io.write(("  %-8s taps to collapse: %d\n"):format(name, n))
  ok(n == want, "%s should break the wall in %d taps, took %d", name, want, n)
end

section("6. is it winnable")
-- An ORACLE player: always taps the undug treasure cell with the most dirt left,
-- hammer while there is plenty to clear and pickaxe once it is nearly out. This
-- is the best case. A random tapper is the control. If the oracle never wins the
-- numbers are too harsh; if the random tapper always wins they are too soft.
local function play(seed, oracle)
  local rand = lcg(seed)
  local wall = Wall.generate({ rand = rand, oddTID = seed % 2 == 1 })
  if not wall then return nil end
  local st = Dig.new(wall, rand)
  for _ = 1, 200 do
    local done = Dig.finished(st)
    if done then return done, st.hits end
    local bx, by, best = nil, nil, -1
    if oracle then
      for y = 0, M.GRID_HEIGHT - 1 do
        for x = 0, M.GRID_WIDTH - 1 do
          local index = wall.grid[y + 1][x + 1]
          if index ~= 0 and index <= wall.itemCount and st.dirt[y + 1][x + 1] > 0 then
            if st.dirt[y + 1][x + 1] > best then
              best, bx, by = st.dirt[y + 1][x + 1], x, y
            end
          end
        end
      end
    end
    if not bx then bx, by = rand(M.GRID_WIDTH), rand(M.GRID_HEIGHT) end
    Dig.dig(st, bx, by, best >= 0 and best <= 2)
  end
  return Dig.finished(st) or "unfinished", st.hits
end
for _, mode in ipairs({ { "oracle", true }, { "random", false } }) do
  local won, lost, other, hits, runs = 0, 0, 0, 0, 2000
  for seed = 1, runs do
    local r, h = play(seed * 7717, mode[2])
    if r == "won" then won = won + 1; hits = hits + (h or 0)
    elseif r == "collapsed" then lost = lost + 1
    else other = other + 1 end
  end
  io.write(("  %-7s: won %d, collapsed %d, neither %d  (%.1f%% win, %.1f taps to win)\n")
           :format(mode[1], won, lost, other, won / runs * 100,
                   won > 0 and hits / won or 0))
  if mode[2] then
    ok(won > 0, "the oracle player never once cleared a wall in %d games -- with "
       .. "these numbers the game cannot be won", runs)
    ok(lost > 0, "the oracle player never once lost in %d games, so the wall "
       .. "never collapses and the meter is doing nothing", runs)
  else
    ok(won < runs, "random tapping wins every game, so the meter is too generous")
  end
  ok(other == 0, "%d games ended in neither state", other)
end

section("7. the rock short-circuit")
-- A rock whose dirt has just reached zero returns before the splash. Built by
-- hand: place a rock, clear it to 1, then tap.
local w = Wall.new(M)
local rock = M.rocks()[1]
ok(rock ~= nil, "no rock rows in the table")
ok(Wall.tryPlace(w, rock, 5, 4) == true, "could not place a rock")
w.itemCount = 0                       -- everything placed is a rock
local st2 = { wall = w, M = M, integrity = 196, hits = 0, dirt = {} }
for y = 1, M.GRID_HEIGHT do
  st2.dirt[y] = {}
  for x = 1, M.GRID_WIDTH do st2.dirt[y][x] = 6 end
end
st2.dirt[5][6] = 2                    -- the rock's own cell, one tap from bare
local res = Dig.dig(st2, 5, 4, false) -- hammer, which would normally splash
ok(res ~= nil and res.hitRock == true, "tapping an exposed rock did not report it")
ok(st2.dirt[5][6] == 0, "the rock's own cell should still have been cleared")
ok(st2.dirt[5][7] == 6 and st2.dirt[4][6] == 6,
   "the splash reached the neighbours (%d, %d); hitting a rock returns first",
   st2.dirt[5][7], st2.dirt[4][6])
ok(st2.integrity == 196 - Dig.HAMMER_DAMAGE,
   "a tap that hit a rock still costs the wall: %d", st2.integrity)

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)