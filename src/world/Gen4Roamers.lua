-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/world/Gen4Roamers.lua -- SINNOH'S SIX THAT WILL NOT STAND STILL.
--
-- `activateroamingpokemon` was unlowered, on three maps: ETERNA CITY'S SOUTH
-- HOUSE (the Kanto birds, once the National Dex is in), FULLMOON ISLAND
-- (Cresselia) and VERITY CAVERN (Mesprit, the moment you look into the lake).
-- Mesprit is main-path. So the command that RELEASES a roamer did nothing, and
-- with nothing released every rule below had nothing to act on.
--
-- THE THIRD SIBLING, AND IT IS NOT EITHER OF THE OTHER TWO. `RoamMons.lua` is
-- Crystal's three beasts and `Gen3Roamers.lua` is Hoenn's one, and Platinum
-- shares the SHAPE with both and the RULES with neither. Copying either one
-- would have been wrong in a way nothing would report:
--
--                      Gen 2            Gen 3            GEN 4
--   slots              3                1                6
--   meeting it         75/256, then     1 in 4 on its    1 IN 2 on its map
--                      1 of 3 slots     map              (see below)
--   moving             every map load   every map load   MAP CONNECTION ONLY
--   where it moves     any route        a 20-node graph  A 29-NODE GRAPH
--   long hop           never            1 load in 16     1 move in 16
--   avoids             nothing          the map 3 loads  THE MAP YOU JUST
--                                       ago              CAME FROM
--
-- THE ODDS DIFFERENCE IS THE ONE THAT MATTERS. Gen 2 rolls a SLOT first and
-- then asks where that one is, so three beasts on your route are no likelier
-- than one. Gen 4 does it the other way round -- `TryEncounterRoamer` collects
-- every active roamer ON YOUR MAP, and only then spends a flat
-- `LCRNG_RandMod(2)`. So with the three birds loose on one route the chance of
-- meeting SOMETHING is still one in two, and the three of them split it. Read
-- as Gen 2's rule it would have been 75/256 x 1/6 per bird; read as Gen 4's it
-- is 1/2 x 1/3. That is a factor of five, and no crash anywhere.
--
-- ...AND ROAMERS CANNOT APPEAR IN A POKE RADAR PATCH OR A DOUBLE BATTLE, which
-- the cartridge says in a comment above the call and this file honours through
-- the caller.

local Gen4Roamers = {}

-- ---------------------------------------------------------------------------
-- THE SIX SLOTS
--
-- `RoamingPokemon_ActivateSlot` is a switch on the slot with the species and
-- the level in each arm -- no table to extract, so transcribed, and the slot
-- numbers are `generated/roaming_slots.txt` in order.
--
-- DARKRAI IS SLOT 2 AND NO SCRIPT EVER ACTIVATES IT. Measured over the whole
-- corpus: the eight `activateroamingpokemon` rows are slots 3, 4, 5 (Eterna's
-- south house, twice each) and 1 and 0. Darkrai's slot exists, the switch has
-- an arm for it, and the thing that fills it is the Member's Card event rather
-- than a field script. Kept in the table because the slot is real; nothing
-- here reaches it.
Gen4Roamers.SLOTS = {
  [0] = { name = "MESPRIT",   species = 481, level = 50 },
  [1] = { name = "CRESSELIA", species = 488, level = 50 },
  [2] = { name = "DARKRAI",   species = 491, level = 40 },
  [3] = { name = "MOLTRES",   species = 146, level = 60 },
  [4] = { name = "ZAPDOS",    species = 145, level = 60 },
  [5] = { name = "ARTICUNO",  species = 144, level = 60 },
}
Gen4Roamers.SLOT_COUNT = 6

-- ---------------------------------------------------------------------------
-- THE TWENTY-NINE PLACES
--
-- `RoamingPokemonRoutes[RI_MAX]`, in enum order, as MAP HEADER IDS. The list
-- is every numbered route in Sinnoh plus two outdoor stretches that are not
-- routes at all -- Valley Windworks and Fuego Ironworks.
--
-- TWENTY-NINE FOR TWENTY-NINE ON THE LABEL, checked against the cache, and the
-- port's own internal names confirm the transcription a second way because
-- THEY CARRY THE ROUTE NUMBER: 342 is R201, 343 is R202, 395 is R222. Three
-- rows would catch a wrong list --
--
--   * ROUTE_220 is header 467 and its internal name is **W220**, not R220: a
--     water route, seventy ids past Route 222's 395.
--   * ROUTE_205_NORTH is 349, not 348 -- the two halves of Route 205 are not
--     adjacent ids.
--   * the last two are D02 and D04, dungeon-prefixed, because the Windworks
--     and the Ironworks are outdoor maps attached to buildings.
--
-- And every one of the 29 carries a wild-encounter table, which it has to:
-- a roamer is met INSTEAD of an ordinary wild encounter, so a place with no
-- encounters is a place a roamer can hide forever.
Gen4Roamers.ROUTES = {
  [0]  = { header = 342, map = "R201",  what = "Route 201" },
  [1]  = { header = 343, map = "R202",  what = "Route 202" },
  [2]  = { header = 344, map = "R203",  what = "Route 203" },
  [3]  = { header = 345, map = "R204A", what = "Route 204 south" },
  [4]  = { header = 346, map = "R204B", what = "Route 204 north" },
  [5]  = { header = 347, map = "R205A", what = "Route 205 south" },
  [6]  = { header = 349, map = "R205B", what = "Route 205 north" },
  [7]  = { header = 350, map = "R206",  what = "Route 206" },
  [8]  = { header = 353, map = "R207",  what = "Route 207" },
  [9]  = { header = 354, map = "R208",  what = "Route 208" },
  [10] = { header = 356, map = "R209",  what = "Route 209" },
  [11] = { header = 362, map = "R210A", what = "Route 210 south" },
  [12] = { header = 363, map = "R210B", what = "Route 210 north" },
  [13] = { header = 365, map = "R211A", what = "Route 211 west" },
  [14] = { header = 366, map = "R211B", what = "Route 211 east" },
  [15] = { header = 367, map = "R212A", what = "Route 212 north" },
  [16] = { header = 371, map = "R212B", what = "Route 212 south" },
  [17] = { header = 373, map = "R213",  what = "Route 213" },
  [18] = { header = 380, map = "R214",  what = "Route 214" },
  [19] = { header = 382, map = "R215",  what = "Route 215" },
  [20] = { header = 383, map = "R216",  what = "Route 216" },
  [21] = { header = 385, map = "R217",  what = "Route 217" },
  [22] = { header = 388, map = "R218",  what = "Route 218" },
  [23] = { header = 391, map = "R219",  what = "Route 219" },
  [24] = { header = 467, map = "W220",  what = "Route 220" },
  [25] = { header = 392, map = "R221",  what = "Route 221" },
  [26] = { header = 395, map = "R222",  what = "Route 222" },
  [27] = { header = 200, map = "D02",   what = "Valley Windworks, outside" },
  [28] = { header = 204, map = "D04",   what = "Fuego Ironworks, outside" },
}
Gen4Roamers.ROUTE_COUNT = 29

-- ---------------------------------------------------------------------------
-- WHERE IT CAN GO NEXT
--
-- `sNearbyRoutes[RI_MAX]`, and the cartridge's own comment says what it means:
-- *"Includes adjacent routes as well as routes connected to adjacent towns"* --
-- so Route 202's five neighbours are the two off Sandgem and all three off
-- Jubilife, not just the two it physically touches.
--
-- !! IT IS NOT SYMMETRIC, AND IT MUST NOT BE TIDIED. Two edges go one way:
--
--     6 -> 9    Route 205 north lists Route 208 (Eterna City between them)
--               and Route 208's own row does not list 205 north back
--     13 -> 6   Route 211 west lists Route 205 north, and 205 north's row
--               does not list 211 west back
--
-- The first is written in pret as a BARE `9` rather than `RI_ROUTE_208`, which
-- is what makes it easy to lose in transcription. Building the graph
-- symmetrically would invent two edges and drop none; building it from one
-- direction only would drop two. Either way a roamer's movement would be
-- subtly wrong in a way no crash reports, so the check asserts THESE TWO
-- asymmetries and no others.
--
-- 78 directed edges over 29 nodes, every node reachable from every other.
Gen4Roamers.NEARBY = {
  [0]  = { 1, 23 },
  [1]  = { 0, 2, 3, 22, 23 },
  [2]  = { 1, 3, 8, 22 },
  [3]  = { 1, 2, 4, 22 },
  [4]  = { 3, 5 },
  [5]  = { 4, 6, 27, 28 },
  [6]  = { 5, 7, 9 },
  [7]  = { 6, 8, 13 },
  [8]  = { 2, 7, 9 },
  [9]  = { 8, 10, 15 },
  [10] = { 9, 11, 15 },
  [11] = { 10, 12, 19 },
  [12] = { 11, 14 },
  [13] = { 6, 7, 14, 20 },
  [14] = { 12, 13, 20 },
  [15] = { 9, 10, 16 },
  [16] = { 15, 17 },
  [17] = { 16, 18, 26 },
  [18] = { 17, 19, 26 },
  [19] = { 11, 18 },
  [20] = { 13, 14, 21 },
  [21] = { 20 },
  [22] = { 1, 2, 3 },
  [23] = { 0, 1, 24 },
  [24] = { 23, 25 },
  [25] = { 24 },
  [26] = { 17, 18 },
  [27] = { 5 },
  [28] = { 5 },
}

-- The two one-way edges, named so the check can assert them rather than
-- rediscover them.
Gen4Roamers.ONE_WAY = { { 6, 9 }, { 13, 6 } }

-- `LCRNG_RandMod(16) == 0` in RoamingPokemon_MoveAllLocations.
Gen4Roamers.LONG_HOP_ONE_IN = 16
-- `LCRNG_RandMod(2) == 0` returns FALSE in TryEncounterRoamer, so a roamer on
-- your map is met on one wild encounter in two.
Gen4Roamers.MEET_ONE_IN = 2

-- ---------------------------------------------------------------------------
-- the save

local function held(save, make)
  if type(save) ~= "table" then return nil end
  if make then save.gen4Roamers = save.gen4Roamers or {} end
  local all = save.gen4Roamers
  if type(all) ~= "table" then return nil end
  return all
end

local function randInt(rng, n)
  if n <= 0 then return 0 end
  rng = rng or (love and love.math and love.math.random) or math.random
  return rng(0, n - 1)
end

-- Header id -> the engine's map id, cached per dataset the way
-- `Gen4Commands.mapForHeader` does. Kept weak so a dataset swap does not pin
-- the old one.
local headerIndex = setmetatable({}, { __mode = "k" })

function Gen4Roamers.mapForHeader(data, header)
  local maps = data and data.maps
  if not maps then return nil end
  local index = headerIndex[maps]
  if not index then
    index = {}
    for id, def in pairs(maps) do
      if type(def) == "table" and def.header then index[def.header] = id end
    end
    headerIndex[maps] = index
  end
  return index[tonumber(header) or -1]
end

-- The map id a route index names, through the cache rather than the table's
-- own `map` field -- that field is PROVENANCE for the check, and resolving
-- through the header is what a mod that renames a map needs.
function Gen4Roamers.mapOf(data, routeIndex)
  local row = Gen4Roamers.ROUTES[tonumber(routeIndex) or -1]
  if not row then return nil end
  return Gen4Roamers.mapForHeader(data, row.header) or row.map
end

function Gen4Roamers.all(save)
  return held(save) or {}
end

-- One roamer's record, or nil when that slot is not roaming.
function Gen4Roamers.active(save, slot)
  local all = held(save)
  local it = all and all[tonumber(slot) or -1]
  if type(it) ~= "table" or it.active ~= true or not it.species then
    return nil
  end
  return it
end

function Gen4Roamers.anyActive(save)
  for slot = 0, Gen4Roamers.SLOT_COUNT - 1 do
    if Gen4Roamers.active(save, slot) then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- releasing one
--
-- `RoamingPokemon_ActivateSlot`: the species and level come off the switch,
-- the IVs and personality off a Pokemon made ONCE and thrown away -- the
-- cartridge keeps only its combined IVs and its personality, and rebuilds the
-- same individual from them at every meeting. Current HP starts at MAX HP, not
-- at zero: Gen 4 stores a real number here where Gen 2 and Gen 3 store zero to
-- mean "make fresh stats", so a Gen 4 roamer's HP field is meaningful from the
-- first frame.
--
-- ...AND THEN IT IS IMMEDIATELY MOVED. The last line of ActivateSlot is
-- `MoveRoamerRandom`, so a roamer is never released onto the route the table
-- happens to have it on -- it starts somewhere random that is not the map the
-- player just came from.
function Gen4Roamers.activate(data, save, slot, rng)
  slot = math.floor(tonumber(slot) or -1)
  local def = Gen4Roamers.SLOTS[slot]
  if not (def and save) then return nil end
  local all = held(save, true)
  local Stats = require("src.pokemon.Stats")
  local roll = rng or (love and love.math and love.math.random) or math.random
  local it = {
    slot = slot,
    name = def.name,
    species = def.species,
    level = def.level,
    active = true,
    status = nil,
  }
  it.personality = roll(0, 65535) * 65536 + roll(0, 65535)
  local okIvs, ivs = pcall(function() return Stats.randomIVs(roll) end)
  it.ivs = okIvs and ivs or nil
  -- MAX HP, which needs the species record; without one the field is left nil
  -- and the battle makes a fresh one, which is the same fallback Gen 2 uses.
  local okHp, hp = pcall(function()
    local mon = require("src.pokemon.Pokemon").new(data, def.species, def.level)
    return mon and mon.stats and mon.stats.hp or nil
  end)
  it.hp = (okHp and tonumber(hp)) or nil
  all[slot] = it
  -- the release ends with a random hop, and it avoids the map the player came
  -- from just as an ordinary move does
  Gen4Roamers.hop(data, save, slot, rng)
  return it
end

-- ---------------------------------------------------------------------------
-- moving

-- A REROLL-UNTIL-ALLOWED IS A UNIFORM PICK OVER THE ALLOWED SET, and writing
-- it as the second thing rather than the first is the difference between exact
-- and nearly.
--
-- Both movement functions in the cartridge are `while (TRUE) { pick; if (ok)
-- break; }`. Transcribing that literally needs a loop bound -- and a bounded
-- reroll has a tail where it gives up and LEAVES THE ROAMER WHERE IT WAS, which
-- the cartridge never does. I wrote it that way first and the check caught it:
-- a step that was supposed to refuse one map returned "stayed put", which
-- satisfied "did not go to the forbidden map" for the wrong reason.
--
-- Filtering first is the same distribution -- a uniform reroll that rejects a
-- fixed subset is uniform over the complement -- and it terminates by
-- construction.
local function pickAllowed(data, candidates, rng, ...)
  local banned = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v ~= nil then banned[v] = true end
  end
  local allowed = {}
  for _, index in ipairs(candidates) do
    local map = Gen4Roamers.mapOf(data, index)
    if map and not banned[map] then
      allowed[#allowed + 1] = { index = index, map = map }
    end
  end
  if #allowed == 0 then return nil end
  return allowed[randInt(rng, #allowed) + 1]
end

local EVERYWHERE = nil
local function everywhere()
  if not EVERYWHERE then
    EVERYWHERE = {}
    for i = 0, Gen4Roamers.ROUTE_COUNT - 1 do EVERYWHERE[#EVERYWHERE + 1] = i end
  end
  return EVERYWHERE
end

-- `MoveRoamerRandom`: anywhere among the 29 that is neither where it stands nor
-- the map the player just left.
--
-- A FRESH ROAMER'S "WHERE IT STANDS" IS ROUTE 201, not nowhere: the save's
-- `roamerRouteIndexes` starts zeroed, so the first hop after
-- `RoamingPokemon_ActivateSlot` is excluding index 0 whether or not the roamer
-- was ever there. Mirrored rather than tidied -- it makes Route 201 very
-- slightly less likely as a starting place, and that is the cartridge's
-- behaviour.
function Gen4Roamers.hop(data, save, slot, rng)
  local it = Gen4Roamers.active(save, slot) or (held(save) or {})[slot]
  if type(it) ~= "table" then return nil end
  local hereMap = Gen4Roamers.mapOf(data, tonumber(it.route) or 0)
  local choice = pickAllowed(data, everywhere(), rng,
                             Gen4Roamers.previousMap(save), hereMap)
  if not choice then return it.map end
  it.route, it.map = choice.index, choice.map
  return choice.map
end

-- `MoveRoamerNearby`: one step along the graph, refusing the map the player
-- just came from -- and NOT refusing where it stands, because a neighbour list
-- never contains its own node (checked: no self-loops).
--
-- THE ONE-NEIGHBOUR CASE FALLS BACK TO THE LONG HOP, which is the cartridge's
-- own branch and not a safety net: Route 217, Route 221, Valley Windworks and
-- Fuego Ironworks have exactly one neighbour each, so a roamer on any of the
-- four whose single exit is the map the player just left has nowhere legal to
-- step. `MoveRoamerNearby` handles that with `numPossibilities == 1` and calls
-- `MoveRoamerRandom`; the multi-neighbour arm does not need it, because only
-- one map is ever forbidden.
function Gen4Roamers.stepNearby(data, save, slot, rng)
  local it = Gen4Roamers.active(save, slot)
  if not it then return nil end
  local here = tonumber(it.route)
  local list = here and Gen4Roamers.NEARBY[here]
  if not (list and #list > 0) then
    return Gen4Roamers.hop(data, save, slot, rng)
  end
  local choice = pickAllowed(data, list, rng, Gen4Roamers.previousMap(save))
  if not choice then return Gen4Roamers.hop(data, save, slot, rng) end
  it.route, it.map = choice.index, choice.map
  return choice.map
end

-- ---------------------------------------------------------------------------
-- where the player has been
--
-- `PlayerRecentRoutes` is two fields and the struct comment says what for:
-- *"Used to prevent roamers from trolling you by moving to the route you just
-- left"*. `SpecialEncounter_UpdateRecentRoutes` only shifts when the map
-- CHANGES, so walking out of a building and back in does not consume the
-- memory.
--
-- ...AND IT IS ONLY KEPT WHILE SOMETHING IS ROAMING
-- (`RoamingPokemon_UpdatePlayerRecentRoutes` guards on
-- `AnyRoamersActive`), which matters: the first map you enter after releasing
-- one is `current`, and `previous` is whatever it was when the last roamer
-- retired.
function Gen4Roamers.previousMap(save)
  local all = held(save)
  local r = all and all.recent
  return type(r) == "table" and r.previous or nil
end

function Gen4Roamers.noteMap(save, mapId)
  if not Gen4Roamers.anyActive(save) then return false end
  local all = held(save, true)
  all.recent = all.recent or {}
  local r = all.recent
  if r.current ~= mapId then
    r.previous, r.current = r.current, mapId
    return true
  end
  return false
end

-- ONE MAP CONNECTION, ALL SLOTS. `FieldSystem_InitFlagsOnMapChange` calls
-- this; `FieldSystem_InitFlagsWarp` DOES NOT -- so a roamer hops when you walk
-- across a route boundary and stays put when you go through a door. Getting
-- that backwards would move every roamer several times per Pokemon Centre
-- visit.
--
-- One move in sixteen leaves the graph entirely.
function Gen4Roamers.moveAll(data, save, rng)
  if not Gen4Roamers.anyActive(save) then return 0 end
  local moved = 0
  for slot = 0, Gen4Roamers.SLOT_COUNT - 1 do
    if Gen4Roamers.active(save, slot) then
      if randInt(rng, Gen4Roamers.LONG_HOP_ONE_IN) == 0 then
        Gen4Roamers.hop(data, save, slot, rng)
      else
        Gen4Roamers.stepNearby(data, save, slot, rng)
      end
      moved = moved + 1
    end
  end
  return moved
end

-- Fly and Teleport: `RoamingPokemon_RandomizeAllLocations`, the long hop for
-- everything at once. Not the ordinary move -- you cannot follow a roamer by
-- flying after it.
function Gen4Roamers.randomizeAll(data, save, rng)
  local n = 0
  for slot = 0, Gen4Roamers.SLOT_COUNT - 1 do
    if Gen4Roamers.active(save, slot) then
      Gen4Roamers.hop(data, save, slot, rng)
      n = n + 1
    end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- meeting one
--
-- `TryEncounterRoamer`: gather every active roamer on this map, then ONE flat
-- coin. Presence decides whether a roll happens at all; the count only decides
-- which one you get. See the table at the top for why this is not Gen 2's
-- rule with different numbers.
--
-- The caller has already decided a wild encounter is happening, and a roamer
-- REPLACES it.
function Gen4Roamers.check(data, save, mapId, rng)
  if mapId == nil then return nil end
  local here = {}
  for slot = 0, Gen4Roamers.SLOT_COUNT - 1 do
    local it = Gen4Roamers.active(save, slot)
    if it and it.map == mapId then here[#here + 1] = slot end
  end
  if #here == 0 then return nil end
  if randInt(rng, Gen4Roamers.MEET_ONE_IN) == 0 then return nil end
  local slot = here[randInt(rng, #here) + 1]
  return slot, Gen4Roamers.active(save, slot)
end

function Gen4Roamers.encounterFor(slot, it)
  if type(it) ~= "table" then return nil end
  return {
    species = it.species,
    level = math.floor(tonumber(it.level) or 50),
    roamerHP = math.floor(tonumber(it.hp) or 0),
    -- the same individual every meeting, from the two numbers the cartridge
    -- keeps (AddRoamerToEnemyParty -> Pokemon_InitAndCalcStats)
    roamerSeed = it.personality and { personality = it.personality,
                                      ivs = it.ivs } or nil,
    roamerStatus = it.status,
    roamerSlot = slot,
  }
end

-- ---------------------------------------------------------------------------
-- after the fight
--
-- !! AND THIS RUNS AFTER EVERY WILD BATTLE, NOT ONLY A ROAMER'S.
-- `RoamerAfterBattle_UpdateRoamers` is `encounter.c` state 4, on the way out of
-- any wild encounter, and it does two things a first reading would miss:
--
--   * MET ONE -> write its HP and status back (or retire it), AND THEN EVERY
--     ROAMER STANDING ON THIS MAP LEAVES -- `MoveRoamersOffMap`, a long hop
--     each, not just the one you fought.
--   * MET AN ORDINARY WILD -> `LCRNG_RandMod(100) < 30`, and on that 30% EVERY
--     ROAMER ON THIS MAP LEAVES ANYWAY.
--
-- I wrote the opposite of both of those from memory before reading the file,
-- which is this port's recurring fault in one line. The second rule in
-- particular is not guessable: grinding ordinary encounters on a roamer's route
-- scares it off three times in ten, so the way to corner one is to meet it, not
-- to stand in the grass beside it.
--
-- Retiring is `BATTLE_RESULT_WIN` with the roamer's HP at zero, or
-- `BATTLE_RESULT_CAPTURED_MON`; anything else is an escape and keeps the
-- damage. Fleeing does NOT heal it -- that is the whole point of a hunt.
Gen4Roamers.LEAVE_AFTER_WILD_PERCENT = 30

function Gen4Roamers.remember(save, slot, hp, status)
  local it = Gen4Roamers.active(save, slot)
  if not it then return false end
  it.hp = math.max(1, math.floor(tonumber(hp) or 0))
  it.status = status or nil
  return true
end

-- Caught or knocked out: `ROAMER_DATA_ACTIVE = 0`, which stops the movement,
-- the encounter and the Marking Map's dot together.
function Gen4Roamers.retire(save, slot)
  local all = held(save)
  local it = all and all[tonumber(slot) or -1]
  if type(it) ~= "table" then return false end
  it.active = false
  return true
end

-- `MoveRoamersOffMap`: every active roamer whose map is this one takes a long
-- hop. The ones elsewhere are untouched.
function Gen4Roamers.clearMap(data, save, mapId, rng)
  local n = 0
  for slot = 0, Gen4Roamers.SLOT_COUNT - 1 do
    local it = Gen4Roamers.active(save, slot)
    if it and it.map == mapId then
      Gen4Roamers.hop(data, save, slot, rng)
      n = n + 1
    end
  end
  return n
end

-- The whole of `RoamerAfterBattle_UpdateRoamers`, in one call the caller makes
-- after ANY wild battle. `slot` is nil when the battle was an ordinary wild.
function Gen4Roamers.afterBattle(data, save, mapId, slot, hp, status, gone, rng)
  if not Gen4Roamers.anyActive(save) then return nil end
  if slot == nil then
    -- the 30% that is easy to miss
    local roll = rng or (love and love.math and love.math.random) or math.random
    if roll(0, 99) < Gen4Roamers.LEAVE_AFTER_WILD_PERCENT then
      return Gen4Roamers.clearMap(data, save, mapId, rng), "scared"
    end
    return 0, "stayed"
  end
  if gone then
    Gen4Roamers.retire(save, slot)
  else
    Gen4Roamers.remember(save, slot, hp, status)
  end
  return Gen4Roamers.clearMap(data, save, mapId, rng), "met"
end

return Gen4Roamers
