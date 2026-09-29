-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4PlatformLifts.lua -- THE NINE RISING PLATFORMS, AND THE ONE
-- QUESTION THEY ASK THAT THIS PORT CAN ANSWER.
--
-- Not the department-store lifts (those are src/import/Gen4Elevators.lua, and
-- they were a dead end for two comments). These are the PLATFORM lifts: a 3x2
-- slab that rises between two heights in the room it is already in. Three on
-- Iron Island and six in the Pokemon League.
--
-- THE PORT ALREADY DECIDED THESE ARE SCENERY, and it decided it on Iron Island
-- alone. `Gen4ScriptVM`'s note argued B1F-right, B2F-left and B3F by dumping
-- their connected components and finding the rooms warp-connected -- and then
-- lowered `triggerplatformlift` to a no-op for ALL NINE, six of which it had
-- not looked at. That is the same half-argument that cost the department-store
-- lifts, so the League half is measured here.
--
-- MEASURED, in the cache's own permission grid, for all six League rooms: the
-- COLUMN BETWEEN THE TWO WARPS IS OPEN FLOOR END TO END.
--
--     C10R0102  Aaron's elevator      x=4, y 3..15   13/13 open
--     C10R0104  Bertha's              x=4, y 3..15   13/13
--     C10R0106  Flint's               x=4, y 3..15   13/13
--     C10R0108  Lucian's              x=4, y 3..15   13/13
--     C10R0110  Cynthia's elevator    x=4, y 3..23   21/21
--     C10R0111  the Champion's room   x=8, y 3..18   16/16
--
-- Each room is a shaft with a warp in the wall at the top (behaviour 0x6E) and
-- a warp on the floor at the bottom, and every tile between them is behaviour
-- 0 with no collision bit. So the lift's rise is a HEIGHT change on ground the
-- player can already walk: the Elite Four are reachable in order without it,
-- and Cynthia's room ends in an explicit `Warp` to the Hall of Fame hallway
-- rather than in the platform. The no-op is right for all nine; it is now right
-- for a reason on all nine.
--
-- ---------------------------------------------------------------------------
-- WHAT IS STILL WORTH LOWERING
--
-- `checkplatformliftnotusedwhenenteredmap <destVar>` -- five sites, all five
-- League elevator rooms, and an unlowered VAR-WRITER is the dangerous kind: the
-- `gotoif` behind it reads whatever was in the var. The script shape is the
-- same in all five:
--
--     SetVar VAR_MAP_LOCAL_0x00, 0
--     InitPersistedMapFeaturesForPlatformLift
--     CheckPlatformLiftNotUsedWhenEnteredMap VAR_MAP_LOCAL_0x01
--     GoToIfEq VAR_MAP_LOCAL_0x01, FALSE, <DisablePlatformLift>   -- sets 0x00 = 1
--
-- and VAR_MAP_LOCAL_0x00 is the condition on the room's own coord event, which
-- this port honours (`Gen4ScriptVM.bind` carries `var`/`value` through). So the
-- var decides whether the lift's trigger is live -- which in this port runs a
-- no-op and a `setvar`, so NOTHING A PLAYER SEES CHANGES TODAY. It is worth
-- lowering anyway, and the reason is stated rather than dressed up: the slot
-- becomes truthful for the height work, and a var-writer that writes nothing is
-- the class of fault this port has been bitten by five times.
--
-- ---------------------------------------------------------------------------
-- THE ANSWER IS "DID YOU COME IN AT THE BOTTOM"
--
-- `PersistedMapFeatures_InitForPlatformLift` sets `notUsedWhenEnteredMap` TRUE
-- and then, in the SIX LEAGUE CASES ONLY, clears it when the arrival z is not
-- the room's bottom-floor warp z:
--
--     data->notUsedWhenEnteredMap = TRUE;
--     ...
--     case MAP_HEADER_POKEMON_LEAGUE_ELEVATOR_TO_AARON_ROOM:
--         if (location->z == ..._BOTTOM_FLOOR_WARP_Z) { floorID = BOTTOM; }
--         else { floorID = TOP; notUsedWhenEnteredMap = FALSE; }
--
-- The three Iron Island cases set `floorID` the same way and never touch the
-- flag, so Iron Island answers TRUE on both floors. That asymmetry is the whole
-- of the rule and it is easy to read past.
--
-- THE Z VALUES CHECK OUT AGAINST THE CACHE, nine for nine: every one of the
-- nine `#define ..._BOTTOM_FLOOR_WARP_Z` constants is the y of a real warp on
-- the map it names. The one that proves the COORDINATE SPACE is Iron Island
-- B2F-left, whose constant is written `MAP_TILES_COUNT_Z * 1 + 16` = 48 on a
-- 64x64 map: only a matrix coordinate can be 48 there, and the cache's warp
-- sits at y 48. So the comparison is against the player's MATRIX y, which is
-- what `toMatrix` produces.
--
-- ---------------------------------------------------------------------------
-- WHAT IS NOT HERE
--
-- `sPerMapPlatformLiftConfiguration` also carries `floorHeights` and
-- `preventGoingDown` (all six League lifts prevent it). Those are HEIGHT data
-- with nothing in this port to check them against, so they are named -- they
-- are in pret's src/platform_lift.c -- and not copied. `start` IS kept, because
-- it is checkable: a 3x2 slab from each start tile must contain that room's own
-- lift coord event, and eight of the nine do (the Champion's room has no coord
-- event -- its lift is triggered by the script after Cynthia).

local Gen4PlatformLifts = {}

-- PLATFORM_LIFT_SIZE_X / _Y.
Gen4PlatformLifts.SIZE_X = 3
Gen4PlatformLifts.SIZE_Y = 2

Gen4PlatformLifts.BOTTOM_FLOOR = 0
Gen4PlatformLifts.TOP_FLOOR = 1

-- KEYED BY HEADER ID, unlike Gen4Elevators' floor table, and for a reason
-- rather than by accident: the cartridge's own switch is on
-- `location->mapHeaderID`, and a Gen 4 map def carries `header` outright, so
-- this needs no name lookup. Gen4Elevators is keyed by map NAME because what it
-- stores is a warp destination, which the engine addresses by name.
--
-- `bottomZ` is a MATRIX z. `start` is the platform's corner, local to the map.
Gen4PlatformLifts.LIFTS = {
  [291] = { map = "D24R0103", bottomZ = 26, start = { 10, 23 }, league = false,
            what = "Iron Island B1F, right room" },
  [293] = { map = "D24R0105", bottomZ = 48, start = { 18, 44 }, league = false,
            what = "Iron Island B2F, left room" },
  [294] = { map = "D24R0106", bottomZ = 15, start = { 8, 11 },  league = false,
            what = "Iron Island B3F" },
  [176] = { map = "C10R0102", bottomZ = 15, start = { 3, 11 },  league = true,
            what = "Pokemon League, the elevator to Aaron" },
  [178] = { map = "C10R0104", bottomZ = 15, start = { 3, 11 },  league = true,
            what = "Pokemon League, the elevator to Bertha" },
  [180] = { map = "C10R0106", bottomZ = 15, start = { 3, 11 },  league = true,
            what = "Pokemon League, the elevator to Flint" },
  [182] = { map = "C10R0108", bottomZ = 15, start = { 3, 11 },  league = true,
            what = "Pokemon League, the elevator to Lucian" },
  [184] = { map = "C10R0110", bottomZ = 23, start = { 3, 19 },  league = true,
            what = "Pokemon League, the elevator to Cynthia" },
  [185] = { map = "C10R0111", bottomZ = 18, start = { 7, 8 },   league = true,
            what = "Pokemon League, the Champion's room" },
}

-- The five rooms that ASK. The Champion's room and all three Iron Island rooms
-- call `initpersistedmapfeaturesforplatformlift` and never the check, which is
-- why the map-reach report says five maps and not nine.
Gen4PlatformLifts.ASKING = { 176, 178, 180, 182, 184 }

function Gen4PlatformLifts.row(header)
  return Gen4PlatformLifts.LIFTS[tonumber(header) or -1]
end

-- BOTTOM when the arrival z is the bottom-floor warp's, TOP otherwise -- the
-- switch's `if` for all nine. Nothing in this port reads it yet; the height
-- feature will, and deriving it twice is how the two copies start disagreeing.
function Gen4PlatformLifts.floorId(header, z)
  local row = Gen4PlatformLifts.row(header)
  if not row then return Gen4PlatformLifts.BOTTOM_FLOOR end
  if (tonumber(z) or -1) == row.bottomZ then
    return Gen4PlatformLifts.BOTTOM_FLOOR
  end
  return Gen4PlatformLifts.TOP_FLOOR
end

-- TRUE unless a LEAGUE room was entered from above. A map the switch does not
-- name keeps the initialiser's own TRUE, which is also the honest answer: a
-- lift that is not in the table has not been used.
function Gen4PlatformLifts.notUsedWhenEnteredMap(header, z)
  local row = Gen4PlatformLifts.row(header)
  if not (row and row.league) then return true end
  return (tonumber(z) or -1) == row.bottomZ
end

return Gen4PlatformLifts
