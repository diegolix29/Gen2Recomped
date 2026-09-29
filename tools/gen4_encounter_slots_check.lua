-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that Platinum's grass-slot substitutions replace the slots
-- the cartridge says they do, that the day/night data is populated well enough to
-- apply unconditionally, and that applying it cannot reach Gen 1, 2 or 3.
--
-- Item 5 on the play-test list closed with a deliberate gap: "which index each
-- one replaces has not been read off the cartridge, and guessing it would put the
-- wrong species in the grass rather than none". This is that gap, measured.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: `WildEncounters_ReplaceSwarmEncounters`
-- names its own parameters `radarSlot1` and `radarSlot2`, and they are NOT radar
-- slots -- the caller passes grass slots 0 and 1. Quoting the callee's signature
-- would have put the swarm Pokemon in the radar's places, in code that runs and
-- looks right. Read the caller.
--
-- Usage: texlua tools/gen4_encounter_slots_check.lua <rom>

local romPath = arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_encounter_slots_check.lua <rom>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Gen4Encounters = require("src.import.Gen4Encounters")
local Encounter = require("src.world.Encounter")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local rom = NdsRom.open(romPath)
if not rom then
  io.stderr:write("could not open " .. romPath .. "\n")
  os.exit(2)
end
local narc = Narc.parse(assert(rom:read("/fielddata/encountdata/pl_enc_data.narc")))

-- ---------------------------------------------------------------------------
section("1. the clock, against rtc.c's 24-entry lookup")
-- ---------------------------------------------------------------------------
-- Asserted hour by hour rather than at the boundaries, because the whole table
-- is four lines of code and an off-by-one inside a band is invisible to a
-- boundary test.

local WANT_ENUM = { [0] = 4, 4, 4, 4, 0, 0, 0, 0, 0, 0,
                    1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3 }
local WANT_BAND = {}
for h = 0, 3 do WANT_BAND[h] = "night" end
for h = 4, 9 do WANT_BAND[h] = nil end       -- morning: the base table stands
for h = 10, 19 do WANT_BAND[h] = "day" end   -- twilight rides with day
for h = 20, 23 do WANT_BAND[h] = "night" end -- late night rides with night

for h = 0, 23 do
  ok(Gen4Encounters.timeOfDayForHour(h) == WANT_ENUM[h],
     "hour %d: enum %d, expected %d", h, Gen4Encounters.timeOfDayForHour(h), WANT_ENUM[h])
  ok(Gen4Encounters.timedBand(h) == WANT_BAND[h],
     "hour %d: band %s, expected %s", h,
     tostring(Gen4Encounters.timedBand(h)), tostring(WANT_BAND[h]))
end

-- The six morning hours must be nil and not a third band: the cartridge's own
-- comment is "Default encounters are morning. They get replaced by this if it is
-- not morning", and the function leaves both slots untouched for it.
local morningNil = 0
for h = 4, 9 do if Gen4Encounters.timedBand(h) == nil then morningNil = morningNil + 1 end end
ok(morningNil == 6, "all six morning hours should substitute nothing, %d did", morningNil)

-- ---------------------------------------------------------------------------
section("2. the data is populated, so the substitution is always safe")
-- ---------------------------------------------------------------------------
-- The reason `timedGrass` can be applied unconditionally rather than guarded on
-- a per-area flag. A zero in either pair would write species 0 into the grass.

local areas, withGrass, dayZero, nightZero, varies = 0, 0, 0, 0, 0
local dayDiff, nightDiff = 0, 0
for i = 0, narc.count - 1 do
  local rec = narc:get(i)
  local a = rec and Gen4Encounters.parse(rec)
  if a then
    areas = areas + 1
    if Gen4Encounters.hasGrass(a) then
      withGrass = withGrass + 1
      local b3, b4 = a.grass[3].species, a.grass[4].species
      if a.day[1] == 0 or a.day[2] == 0 then dayZero = dayZero + 1 end
      if a.night[1] == 0 or a.night[2] == 0 then nightZero = nightZero + 1 end
      if a.day[1] ~= b3 or a.day[2] ~= b4 then dayDiff = dayDiff + 1 end
      if a.night[1] ~= b3 or a.night[2] ~= b4 then nightDiff = nightDiff + 1 end
      if a.day[1] ~= b3 or a.day[2] ~= b4 or a.night[1] ~= b3 or a.night[2] ~= b4 then
        varies = varies + 1
      end
    end
  end
end
io.write(("  %d areas, %d with grass, %d vary by time of day (day %d, night %d)\n")
  :format(areas, withGrass, varies, dayDiff, nightDiff))

ok(areas == 183, "expected 183 encounter areas, got %d", areas)
ok(withGrass == 171, "expected 171 areas with grass, got %d", withGrass)
ok(dayZero == 0, "%d areas have a zero in their day pair; substitution is unsafe", dayZero)
ok(nightZero == 0, "%d areas have a zero in their night pair", nightZero)
-- AND IT IS WORTH DOING -- a substitution that changed nothing would be a
-- feature with no effect, so this is asserted rather than assumed.
ok(varies == 115, "expected 115 areas to vary by time of day, got %d", varies)
ok(nightDiff == 115, "expected 115 areas to differ at night, got %d", nightDiff)
ok(dayDiff == 27, "expected 27 areas to differ by day, got %d", dayDiff)

-- ---------------------------------------------------------------------------
section("3. the substitution lands on slots 3 and 4, and touches nothing else")
-- ---------------------------------------------------------------------------
-- Area 10 is the worked example because all three readings differ: base 307,35
-- / day 307,74 / night 41,35. An area where day equals base could not tell a
-- correct substitution from one that did nothing.

ok(Gen4Encounters.TIMED_SLOTS[1] == 3 and Gen4Encounters.TIMED_SLOTS[2] == 4,
   "TIMED_SLOTS should be {3,4} (cartridge [2],[3] plus one)")
ok(Gen4Encounters.SWARM_SLOTS[1] == 1 and Gen4Encounters.SWARM_SLOTS[2] == 2,
   "SWARM_SLOTS should be {1,2} -- the CALLER's slots, not the callee's names")
ok(Gen4Encounters.RADAR_SLOTS[3] == 11 and Gen4Encounters.RADAR_SLOTS[4] == 12,
   "RADAR_SLOTS should be {5,6,11,12}")

local area = Gen4Encounters.parse(narc:get(10))
ok(area.grass[3].species == 307 and area.grass[4].species == 35,
   "area 10's base slots should be 307,35 -- the worked example has moved")

local night = Gen4Encounters.timedGrass(area, 22)
ok(night ~= nil, "22:00 should substitute")
ok(night and night[3].species == 41, "slot 3 at night should be 41")
ok(night and night[4].species == 35, "slot 4 at night should be 35")

local touched = 0
for i = 1, 12 do
  if night[i].species ~= area.grass[i].species then touched = touched + 1 end
  -- ONLY THE SPECIES. Every assignment in the cartridge writes `.species`, so a
  -- night Pokemon inherits the level and the chance of the slot it displaces.
  ok(night[i].level == area.grass[i].level, "slot %d: the level changed", i)
  ok(night[i].chance == area.grass[i].chance, "slot %d: the chance changed", i)
end
ok(touched == 1, "exactly 1 species should differ on area 10 at night, %d did", touched)

local day = Gen4Encounters.timedGrass(area, 12)
ok(day and day[3].species == 307 and day[4].species == 74, "area 10's day pair")
ok(Gen4Encounters.timedGrass(area, 6) == nil, "morning must return nil, not a copy")

-- AND IT MUST NOT MUTATE THE SOURCE, because the parsed area is the cache's own
-- table and the next band would substitute on top of this one's answer.
ok(area.grass[3].species == 307, "timedGrass MUTATED the base array")

-- ---------------------------------------------------------------------------
section("4. the roll's view follows the clock, and Gen 1/2/3 do not")
-- ---------------------------------------------------------------------------

local data = { encounters = { [10] = area } }
local mapDef = { encounters = 10 }
local morning = Encounter.forMap(data, mapDef, 999, 6)
local dusk = Encounter.forMap(data, mapDef, 999, 22)
ok(morning and morning.grass, "the morning view should hold a grass table")
ok(dusk and dusk.grass, "the night view should hold a grass table")
ok(morning.grass.slots[3].species == 307, "morning slot 3 should be 307")
ok(dusk.grass.slots[3].species == 41, "night slot 3 should be 41")

-- THE STALE-VIEW CONTROL. The view is cached per map, so a view built at noon
-- holds the day species; serving it after dark is the bug the substitution
-- exists to fix, arriving by a different door.
ok(Encounter.forMap(data, mapDef, 999, 22).grass.slots[3].species == 41,
   "the cache served a stale band after dark")
ok(Encounter.forMap(data, mapDef, 999, 6).grass.slots[3].species == 307,
   "the cache did not rebuild on the way back to morning")
-- ...but it must still CACHE within a band, or `gen4Table`'s own cache churns.
ok(Encounter.forMap(data, mapDef, 999, 22) == Encounter.forMap(data, mapDef, 999, 21),
   "two hours in one band should return the same view object")

-- THE GEN 1/2/3 CONTROL, which is the whole of "do not break Crystal". A table
-- with no `grassRate` must come back as THE SAME OBJECT -- not a copy, not a
-- view -- so nothing downstream can observe that this code ran.
local g2 = { rate = 10, slots = { { species = 16, level = 3 } } }
ok(Encounter.forMap({ encounters = { [5] = g2 } }, nil, 5, 22) == g2,
   "a non-Gen 4 table must be returned unchanged, by identity")
-- ...at every hour, since the band is computed before the shape is known.
local sameAtEveryHour = true
for h = 0, 23 do
  if Encounter.forMap({ encounters = { [5] = g2 } }, nil, 5, h) ~= g2 then
    sameAtEveryHour = false
  end
end
ok(sameAtEveryHour, "a non-Gen 4 table changed at some hour of the day")

-- ---------------------------------------------------------------------------
io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
