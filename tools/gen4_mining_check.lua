-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the mining table is pokeplatinum's, that `pick` is the
-- exact inverse of the weight columns for EVERY roll rather than approximately
-- right on average, and that generating a wall cannot produce an overlap, an
-- out-of-bounds object, a duplicate plate or a hang.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: a weighted picker is the classic thing
-- to test statistically, and a statistical test of a picker is both flaky and
-- weak -- an off-by-one at a bucket boundary moves one row's frequency by a
-- fraction of a percent and hides inside the noise forever. Section 3 walks
-- EVERY roll from 0 to totalWeight-1, in all four save combinations, and asserts
-- the row it lands on is the row whose cumulative interval contains it. 4,038
-- assertions that cannot be lucky.
--
-- Usage: texlua tools/gen4_mining_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local M    = require("src.import.Gen4Mining")
local Wall = require("src.world.Gen4MiningWall")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

-- ---------------------------------------------------------------------------
section("1. the table, against sMiningObjects")
-- ---------------------------------------------------------------------------
ok(#M.OBJECTS == 85, "sMiningObjects has 85 rows, this table has %d", #M.OBJECTS)
local pool, rocks = M.weightedPool(), M.rocks()
io.write(("  %d rows: %d in the weighted pool, %d rock rows\n")
         :format(#M.OBJECTS, #pool, #rocks))
ok(#pool == 71, "the weighted pool should be 71 rows, got %d", #pool)
ok(#rocks == 14, "there should be 14 rock rows, got %d", #rocks)
ok(#pool + #rocks == #M.OBJECTS,
   "pool + rocks = %d but the table has %d rows -- some row is in neither, and "
   .. "`weightedPool` BREAKS at the first rock rather than filtering, so a rock "
   .. "in the middle of the table would silently truncate the pool",
   #pool + #rocks, #M.OBJECTS)
-- that break is only equivalent to a filter because every rock sits at the tail
for i, obj in ipairs(M.OBJECTS) do
  if obj.id >= M.ROCK_FIRST then
    ok(i > #pool, "row %d (%s) is a rock but sits inside the weighted pool",
       i, obj.name)
  end
end

section("2. the four weight columns are four different numbers")
local totals = {}
for _, combo in ipairs({ { "oddTID", true, false }, { "evenTID", false, false },
                         { "oddTIDDex", true, true }, { "evenTIDDex", false, true } }) do
  local t = M.totalWeight(combo[2], combo[3])
  totals[combo[1]] = t
  io.write(("  %-11s total %d\n"):format(combo[1], t))
end
ok(totals.oddTID == 1017, "odd-TID total should be 1017, got %d", totals.oddTID)
ok(totals.evenTID == 1015, "even-TID total should be 1015, got %d", totals.evenTID)
ok(totals.oddTIDDex == 987, "odd-TID National Dex total should be 987, got %d", totals.oddTIDDex)
ok(totals.evenTIDDex == 1019, "even-TID National Dex total should be 1019, got %d", totals.evenTIDDex)
-- The control for "the columns are distinct": if an implementation collapsed
-- them, all four totals would agree. They must not.
local same = totals.oddTID == totals.evenTID and totals.oddTID == totals.oddTIDDex
             and totals.oddTID == totals.evenTIDDex
ok(not same,
   "all four weight totals are equal, so the columns have been collapsed and "
   .. "trainer-id parity no longer changes what is buried")
-- Armor/Skull Fossil: the clearest case, 0 on one parity and 25 on the other.
for _, pair in ipairs({ { "MINING_TREASURE_ARMOR_FOSSIL", "evenTID", "oddTID" },
                        { "MINING_TREASURE_SKULL_FOSSIL", "oddTID", "evenTID" } }) do
  local row
  for _, o in ipairs(M.OBJECTS) do if o.name == pair[1] then row = o end end
  ok(row ~= nil, "%s is missing from the table", pair[1])
  if row then
    ok(row[pair[2]] == 25 and row[pair[3]] == 0,
       "%s should be 25 on %s and 0 on %s, table says %d and %d",
       pair[1], pair[2], pair[3], row[pair[2]], row[pair[3]])
  end
end

section("3. pick() is the exact inverse of the weights, for EVERY roll")
local rollsChecked = 0
for _, combo in ipairs({ { true, false }, { false, false }, { true, true }, { false, true } }) do
  local oddTID, dex = combo[1], combo[2]
  local total = M.totalWeight(oddTID, dex)
  -- the cumulative interval each row owns
  local lo, want = 0, {}
  for i, obj in ipairs(pool) do
    local w = M.weightOf(obj, oddTID, dex)
    for r = lo, lo + w - 1 do want[r] = i end
    lo = lo + w
  end
  ok(lo == total, "the intervals cover %d but the total is %d", lo, total)
  for roll = 0, total - 1 do
    local _, index = M.pick(roll, oddTID, dex)
    rollsChecked = rollsChecked + 1
    if index ~= want[roll] then
      ok(false, "roll %d (oddTID=%s dex=%s) picked row %s, the weights say %s",
         roll, tostring(oddTID), tostring(dex), tostring(index), tostring(want[roll]))
      break
    end
  end
  -- one past the end must not resolve: the cartridge's GF_ASSERT(FALSE) case
  ok(M.pick(total, oddTID, dex) == nil,
     "a roll of exactly totalWeight resolved to a row; it is out of range")
end
io.write(("  %d rolls checked across the four save combinations\n"):format(rollsChecked))
ok(rollsChecked > 4000, "only %d rolls checked", rollsChecked)

section("4. rows no save can ever dig, and rows the National Dex unlocks")
local never, dexOnly = {}, {}
for _, o in ipairs(pool) do
  if o.oddTID == 0 and o.evenTID == 0 and o.oddTIDDex == 0 and o.evenTIDDex == 0 then
    never[#never + 1] = o.name
  elseif o.oddTID == 0 and o.evenTID == 0 then
    dexOnly[#dexOnly + 1] = o.name
  end
end
io.write(("  unobtainable on any save: %s\n"):format(
  #never > 0 and table.concat(never, ", ") or "none"))
io.write(("  National Dex only (%d rows): %s\n"):format(#dexOnly, table.concat(dexOnly, ", ")))
-- MINING_TREASURE_OVAL_STONE carries 0 in all four columns, so the Oval Stone
-- is in the table and cannot be dug up. Pinned so a transcription slip that
-- gave it a weight shows up here rather than as a rumour.
ok(#never == 1 and never[1] == "MINING_TREASURE_OVAL_STONE",
   "expected exactly the Oval Stone to be unobtainable, got %s",
   table.concat(never, ", "))
ok(#dexOnly >= 5, "only %d rows are National-Dex-only; the fossils should be", #dexOnly)

section("5. the Damp Rock quirk stays fixed")
local damp
for _, o in ipairs(M.OBJECTS) do if o.name == "MINING_TREASURE_DAMP_ROCK" then damp = o end end
ok(damp ~= nil, "the Damp Rock is missing")
if damp then
  ok(damp.w == 3 and damp.h == 3, "the Damp Rock should be 3x3, got %dx%d", damp.w, damp.h)
  local solid = true
  for y = 0, damp.h - 1 do
    for x = 0, damp.w - 1 do
      if not M.solidAt(damp, x, y) then solid = false end
    end
  end
  -- sDampRockShape is declared [3][4] with rows of three, so its 'o' sits at
  -- byte 9 and the stride-3 read never reaches it. Solid is the game's answer;
  -- a notch at (1,2) means somebody transcribed the initialiser.
  ok(solid,
     "the Damp Rock has a hole in it -- the shape initialiser was transcribed "
     .. "literally instead of read at stride width/2 (see Gen4Mining's note)")
end
-- The control: shapes DO produce holes, or `solidAt` is just returning true.
local holes = 0
for _, o in ipairs(M.OBJECTS) do
  if o.occ then
    for y = 0, o.h - 1 do
      for x = 0, o.w - 1 do
        if not M.solidAt(o, x, y) then holes = holes + 1 end
      end
    end
  end
end
io.write(("  holes across every shaped row: %d\n"):format(holes))
ok(holes > 50,
   "only %d holes in the whole table, so solidAt answers true almost always and "
   .. "section 5's 'solid' proves nothing", holes)

section("6. occupancy geometry matches each row's declared size")
for _, o in ipairs(M.OBJECTS) do
  if o.occ then
    ok(#o.occ == o.h, "%s: %d occupancy rows for height %d", o.name, #o.occ, o.h)
    for i, row in ipairs(o.occ) do
      ok(#row == o.w, "%s row %d is %d chars for width %d", o.name, i, #row, o.w)
    end
  end
end

section("7. generating walls")
-- A small deterministic LCG, so a failure is reproducible from its seed.
local function lcg(seed)
  local s = seed
  return function(n)
    s = (1103515245 * s + 12345) % 2147483648
    if n <= 0 then return 0 end
    return math.floor(s / 65536) % n
  end
end
local WALLS = 4000
local worstSpins, counts, tooMany, overlaps, oob, dupPlates, failed = 0, {}, 0, 0, 0, 0, 0
local rockless = 0
for seed = 1, WALLS do
  local wall, why = Wall.generate({ rand = lcg(seed), oddTID = seed % 2 == 1,
                                    nationalDex = seed % 3 == 0 })
  if not wall then failed = failed + 1
  else
    counts[wall.itemCount] = (counts[wall.itemCount] or 0) + 1
    if wall.spins > worstSpins then worstSpins = wall.spins end
    if #wall.objects > M.MAX_BURIED_OBJECTS then tooMany = tooMany + 1 end
    -- every solid cell of every object must own its grid cell, and nothing else
    local seen = {}
    local plates = {}
    for index, p in ipairs(wall.objects) do
      if p.x < 0 or p.y < 0 or p.x + p.obj.w > M.GRID_WIDTH
         or p.y + p.obj.h > M.GRID_HEIGHT then oob = oob + 1 end
      if M.isPlate(p.obj.id) then
        if plates[p.obj.id] then dupPlates = dupPlates + 1 end
        plates[p.obj.id] = true
      end
      for cy = 0, p.obj.h - 1 do
        for cx = 0, p.obj.w - 1 do
          if M.solidAt(p.obj, cx, cy) then
            local key = (p.y + cy) * 100 + (p.x + cx)
            if seen[key] then overlaps = overlaps + 1 end
            seen[key] = index
            if wall.grid[p.y + cy + 1][p.x + cx + 1] ~= index then
              overlaps = overlaps + 1
            end
          end
        end
      end
    end
  end
end
io.write(("  %d walls: item counts 2=%d 3=%d 4=%d, worst spin count %d\n")
         :format(WALLS, counts[2] or 0, counts[3] or 0, counts[4] or 0, worstSpins))
ok(failed == 0, "%d of %d walls failed to generate", failed, WALLS)
ok(overlaps == 0, "%d overlapping cells across %d walls", overlaps, WALLS)
ok(oob == 0, "%d objects placed out of bounds", oob)
ok(tooMany == 0, "%d walls exceeded MAX_BURIED_OBJECTS", tooMany)
ok(dupPlates == 0, "%d walls hold the same plate twice", dupPlates)
ok((counts[2] or 0) > 0 and (counts[3] or 0) > 0 and (counts[4] or 0) > 0,
   "item count is not varying across 2..4 -- got 2=%d 3=%d 4=%d",
   counts[2] or 0, counts[3] or 0, counts[4] or 0)
ok(counts[1] == nil and counts[5] == nil,
   "a wall was generated with an item count outside 2..4")
ok(worstSpins < 10000, "worst spin count %d is close to the give-up limit", worstSpins)

section("8. the first dig is rigged, twice")
for seed = 1, 200 do
  local wall = Wall.generate({ rand = lcg(seed * 977), neverMined = true })
  if wall then
    if wall.itemCount ~= 3 then
      ok(false, "a never-mined wall has %d treasures, not 3", wall.itemCount)
      break
    end
    if #wall.objects ~= 3 then
      ok(false, "a never-mined wall holds %d objects, so rocks were placed",
         #wall.objects)
      break
    end
    rockless = rockless + 1
  end
end
io.write(("  %d never-mined walls: all three treasures, no rocks\n"):format(rockless))
ok(rockless == 200, "only %d of 200 never-mined walls were clean", rockless)
-- and the control: an ordinary wall DOES get rocks, or section 8 says nothing
local withRocks = 0
for seed = 1, 200 do
  local wall = Wall.generate({ rand = lcg(seed * 977) })
  if wall and #wall.objects > wall.itemCount then withRocks = withRocks + 1 end
end
io.write(("  control -- ordinary walls that got at least one rock: %d of 200\n")
         :format(withRocks))
ok(withRocks > 150,
   "only %d of 200 ordinary walls got a rock, so 'no rocks' in section 8 is not "
   .. "distinguishing anything", withRocks)

section("9. the guards bite")
ok(Wall.generate({ rand = nil }) == nil, "generate accepted a nil random source")
-- a degenerate rand that always returns 0 cannot place four objects at (0,0),
-- so the spin limit must trip rather than hang
local wall, why = Wall.generate({ rand = function() return 0 end })
ok(wall == nil and why ~= nil,
   "a rand that always returns 0 did not trip the give-up limit (it returned %s)",
   tostring(wall))
-- the overlap detector itself: place one object twice on purpose
local w2 = Wall.new(M)
local obj = pool[1]
ok(Wall.tryPlace(w2, obj, 0, 0) == true, "could not place the first object at 0,0")
ok(Wall.tryPlace(w2, obj, 0, 0) == false,
   "tryPlace allowed a second object on top of the first")
ok(Wall.tryPlace(w2, obj, M.GRID_WIDTH - 1, 0) == false,
   "tryPlace allowed an object to run off the right edge")
ok(Wall.tryPlace(w2, obj, 0, M.GRID_HEIGHT - 1) == false,
   "tryPlace allowed an object to run off the bottom edge")

section("10. the bounds check, which the shipped table cannot exercise")
-- Removing `if endX > M.GRID_WIDTH then return false end` from tryPlace changes
-- NOTHING for any row in this table, and that is worth knowing rather than
-- discovering later. The overlap loop reads wall.grid[y][x] for each SOLID cell,
-- an off-grid column gives nil, and `nil ~= 0` refuses the placement by
-- accident. The accident only holds while every row has at least one solid cell
-- in its rightmost column and bottom row -- measured below, all 85 do, the most
-- hollow right column being 75% holes.
local hollowRight, hollowBottom = 0, 0
for _, o in ipairs(M.OBJECTS) do
  if o.occ then
    local right, bottom = true, true
    for y = 0, o.h - 1 do if M.solidAt(o, o.w - 1, y) then right = false end end
    for x = 0, o.w - 1 do if M.solidAt(o, x, o.h - 1) then bottom = false end end
    if right then hollowRight = hollowRight + 1 end
    if bottom then hollowBottom = hollowBottom + 1 end
  end
end
io.write(("  rows with an all-hole right column %d, all-hole bottom row %d\n")
         :format(hollowRight, hollowBottom))
-- So the check uses a SYNTHETIC row instead of hoping the table contains one.
-- This is the assertion that actually holds the bounds check up: a 2x2 object
-- whose right column is empty, offered a position where that column is off the
-- grid. Nothing in the overlap loop can see it; only the explicit test can.
local ghostRight = { name = "SYNTHETIC_HOLLOW_RIGHT", id = 1, w = 2, h = 2,
                     oddTID = 0, evenTID = 0, oddTIDDex = 0, evenTIDDex = 0,
                     occ = { "10", "10" } }
local ghostBottom = { name = "SYNTHETIC_HOLLOW_BOTTOM", id = 1, w = 2, h = 2,
                      oddTID = 0, evenTID = 0, oddTIDDex = 0, evenTIDDex = 0,
                      occ = { "11", "00" } }
local w3 = Wall.new(M)
ok(M.solidAt(ghostRight, 1, 0) == false and M.solidAt(ghostRight, 0, 0) == true,
   "the synthetic row is not shaped the way this section needs")
ok(Wall.tryPlace(w3, ghostRight, M.GRID_WIDTH - 1, 0) == false,
   "an object whose right column is off the grid was accepted -- the endX bounds "
   .. "check in tryPlace is missing or wrong, and no row in the shipped table "
   .. "can reveal that")
ok(Wall.tryPlace(w3, ghostBottom, 0, M.GRID_HEIGHT - 1) == false,
   "an object whose bottom row is off the grid was accepted -- the endY bounds "
   .. "check in tryPlace is missing or wrong")
-- and the control: the same object one cell in must be accepted, or the two
-- assertions above would pass on a tryPlace that refuses everything.
ok(Wall.tryPlace(w3, ghostRight, M.GRID_WIDTH - 2, 0) == true,
   "the synthetic object was refused even in bounds, so section 10 refuses "
   .. "everything and proves nothing")
io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)