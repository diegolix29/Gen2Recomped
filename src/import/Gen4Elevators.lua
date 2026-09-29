-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4Elevators.lua -- THE SIX LIFTS, AND THE WARP NOBODY CLAIMED.
--
-- !! TWO NOTES IN THIS PORT SAID SOMETHING SETTLED AND BOTH WERE WRONG, and
-- between them they left every lift in Sinnoh a dead end.
--
-- FIRST. Gen4Events' own comment on the warp block called 4095 a "`nowhere`
-- sentinel" and left six warps with no destination. `field_control.c` 1011:
--
--     if (warpEvent->destWarpID == 0x100) {
--         GF_ASSERT(warpEvent->destHeaderID == 0xfff);
--         *nextMap = *(FieldOverworldState_GetSpecialLocation(...));
--     }
--
-- 4095 is 0xfff, and it is a DYNAMIC DESTINATION: the warp goes wherever the
-- SPECIAL LOCATION was last set. It is Gen 3's MAP_G127_N127 by another
-- spelling, and this port already has that seam.
--
-- MEASURED, and it is not six warps scattered about: all six are WARP 1 AT
-- (3, 6) WITH ANCHOR 256 -- 0x100, the exact pair pret asserts -- and the six
-- maps are the six LIFT CARS:
--
--     C01R0208  Jubilife TV         C07R0206  Veilstone Store
--     C05R0103  Hearthome City      T07R0103  Resort Area
--     C05R0803  Hearthome City      C08R0802  Vista Lighthouse
--
-- Six identical warps in six lift cars is not a coincidence and it is not
-- "nowhere".
--
-- SECOND. Gen4ScriptVM lowered `setspeciallocation` to a NOOP, with the
-- comment "it stamps the MET LOCATION on what you catch in the marsh". The
-- slot has FOUR readers in the cartridge and the met-location one is not among
-- them:
--
--     field_control.c   1011  the lift cars' dynamic warp  <- this one
--     encounter.c        484  the Great Marsh, when the balls run out
--     field_map_change.c 1084  coming back up from the Underground
--     unk_02049D08.c     228  the Battle Tower's communication club
--
-- So the lift scripts were writing a destination into a command that threw it
-- away, and the door they then walked you into had nothing to resolve.
--
-- ---------------------------------------------------------------------------
-- WHAT A LOCATION IS
--
-- `Location` (include/location.h) is five fields and the ORDER IS NOT THE ONE
-- THE OPERAND NAMES SUGGEST:
--
--     mapHeaderID, warpId, x, z, faceDirection
--
-- -- so `setspeciallocation 14 1 18 2 1` is header 14, WARP 1, then (18, 2)
-- and facing south. The second operand is a warp index, not an x, and it is
-- the one that places you: `FieldMapChange_...` (field_map_change.c 226)
--
--     if (location->warpId != WARP_ID_NONE) {
--         warpEvent = MapHeaderData_GetWarpEventByIndex(..., warpId);
--         location->x = warpEvent->x;  location->z = warpEvent->z;
--     }
--
-- overwrites the coordinates from the warp, and the map-connection path hands
-- the change `(headerID, warpId, 0, 0, dir)` with the coordinates ZEROED.
-- Reading operand 2 as an x would have put the player on the wrong tile on
-- every floor of the Veilstone store, whose middle floors say warp 2 and whose
-- ends say warp 1. WARP_ID_NONE is -1, which is where the x/z are used
-- instead -- the Underground's return does exactly that.
--
-- ---------------------------------------------------------------------------
-- THE LIFT REMEMBERS THE FLOOR YOU GOT ON AT, and that is the same slot
-- (field_map_change.c 232):
--
--     if (warpEvent->destWarpID == 0x100) {
--         *specialLocation = *entranceLocation;
--     }
--
-- -- arriving in a car OVERWRITES the slot with where you came from. That is
-- the whole of how the two-floor lifts work: Hearthome's and the Vista
-- Lighthouse's cars have no panel at all, they ask `getfloorsabove` about the
-- special location and warp you to the other floor. Without the entrance
-- capture those three lifts answer about whatever floor was chosen last, and
-- with nothing chosen yet they answer about nothing.
--
-- ---------------------------------------------------------------------------
-- HOW MANY FLOORS ABOVE
--
-- `FieldMenu_GetFloorsAbove` is a SWITCH, not a table -- eighteen cases over
-- map header ids with a default of 1 -- so there is nothing in the cartridge's
-- data to extract and this is TRANSCRIBED. What makes it checkable is that the
-- eighteen header ids were resolved against the cache's own headers and every
-- one landed on the building it names:
--
--     11..14   Jubilife TV 1F..4F          3 2 1 0
--     103,104  Hearthome SE house 1F,2F    1 0
--     112,113  Hearthome NE house 1F,2F    1 0
--     137..141 Veilstone Store 1F..5F      4 3 2 1 0
--     566      Veilstone Store B1F         5
--     150      Sunyshore City              1
--     164      Vista Lighthouse            0
--     461,462  Resort Area Ribbon Syn.     1 0
--
-- EIGHTEEN FOR EIGHTEEN ON THE LABEL, including the three that would catch a
-- wrong id list: Veilstone's B1F is 566, four hundred ids from its own
-- building; the Resort Area's pair sit at 461/462 rather than beside the
-- Veilstone run; and the Vista Lighthouse's lower floor is SUNYSHORE CITY
-- itself, because that lift's ground floor is outdoors. And the SCRIPTS AGREE:
-- the Jubilife lift's own `setspeciallocation 11 / 12 / 13 / 14` names those
-- four ids outright.
--
-- Keyed by the port's INTERNAL NAME rather than by header id, because that is
-- what a map is called everywhere else here; the id is kept beside each row as
-- the provenance.

local Gen4Elevators = {}

-- The warp sentinel pair. Either one alone would be a guess; together they are
-- what field_control.c tests.
Gen4Elevators.DYNAMIC_HEADER = 4095      -- 0xfff
Gen4Elevators.DYNAMIC_ANCHOR = 256       -- 0x100
Gen4Elevators.DYNAMIC_MAP = "GEN4_SPECIAL_LOCATION"

-- `WARP_ID_NONE` is -1 (include/location.h) and the operand is a u16, so this
-- is what a script writes when it means "use the coordinates".
Gen4Elevators.WARP_NONE = 0xFFFF

-- The six lift cars, by internal name -- recorded so the check can assert that
-- the dynamic warps are exactly these and not six others.
Gen4Elevators.CARS = {
  "C01R0208", "C05R0103", "C05R0803",
  "C07R0206", "T07R0103", "C08R0802",
}

-- FieldMenu_GetFloorsAbove, transcribed. `header` is the cartridge's map
-- header id and is not read at runtime; it is here so the transcription can be
-- checked against a cache without going back to the C.
Gen4Elevators.FLOORS_ABOVE = {
  C01R0201 = { above = 3, header = 11 },   -- Jubilife TV 1F
  C01R0202 = { above = 2, header = 12 },   -- Jubilife TV 2F
  C01R0203 = { above = 1, header = 13 },   -- Jubilife TV 3F
  C01R0204 = { above = 0, header = 14 },   -- Jubilife TV 4F
  C05R0101 = { above = 1, header = 103 },  -- Hearthome SE house 1F
  C05R0102 = { above = 0, header = 104 },  -- Hearthome SE house 2F
  C05R0801 = { above = 1, header = 112 },  -- Hearthome NE house 1F
  C05R0802 = { above = 0, header = 113 },  -- Hearthome NE house 2F
  C07R0201 = { above = 4, header = 137 },  -- Veilstone Store 1F
  C07R0202 = { above = 3, header = 138 },  -- Veilstone Store 2F
  C07R0203 = { above = 2, header = 139 },  -- Veilstone Store 3F
  C07R0204 = { above = 1, header = 140 },  -- Veilstone Store 4F
  C07R0205 = { above = 0, header = 141 },  -- Veilstone Store 5F
  C07R0207 = { above = 5, header = 566 },  -- Veilstone Store B1F
  C08      = { above = 1, header = 150 },  -- Sunyshore City
  C08R0801 = { above = 0, header = 164 },  -- Vista Lighthouse
  T07R0101 = { above = 1, header = 461 },  -- Resort Area, Ribbon Syndicate 1F
  T07R0102 = { above = 0, header = 462 },  -- Resort Area, Ribbon Syndicate 2F
}

-- The switch's `default`, and it is not zero. A lift asked about a floor the
-- table does not name answers ONE, which is what keeps Hearthome's two-floor
-- car working: `above == 1` is its "go up" branch.
Gen4Elevators.FLOORS_ABOVE_DEFAULT = 1

function Gen4Elevators.floorsAbove(mapId)
  local row = Gen4Elevators.FLOORS_ABOVE[mapId]
  if row then return row.above end
  return Gen4Elevators.FLOORS_ABOVE_DEFAULT
end

-- ---------------------------------------------------------------------------
-- THE FLOOR LABEL
--
-- `StringTemplate_SetFloorNumber(template, idx, floor)` is not a number
-- formatter -- it is a lookup, and the operand is NOT A SIGNED FLOOR:
--
--     GF_ASSERT(floor <= 5);
--     if (floor == 0) floor = MenuEntries_Text_B1F;
--     else            floor += MenuEntries_Text_1F - 1;
--
-- so ZERO IS THE BASEMENT and 1..5 are the floors. The Veilstone store's own
-- `bufferfloornumber 0 5 / 4 / 3 / 2 / 1 / 0` is 5F down to B1F, which is
-- exactly its six floors and is how the mapping was checked against a script.
-- Formatting the operand as a number would have printed the basement as "0F".
--
-- The strings are CARTRIDGE TEXT, not literals: bank 361 (the menu-entries
-- bank -- generated/text_banks.txt line 362, the same zero-based-line rule
-- that puts the party menu at 453), entry 116 "1F" through 120 "5F", 121
-- "B1F". Verified by reading the bank: 114 "TOUGH CONTEST", 116 "1F", 121
-- "B1F", 123 "LOOKOUT" -- the neighbours line up, so the offset is right.
Gen4Elevators.FLOOR_BANK = 361
Gen4Elevators.FLOOR_1F = 116
Gen4Elevators.FLOOR_B1F = 121
Gen4Elevators.FLOOR_MAX = 5

function Gen4Elevators.floorEntry(floor)
  floor = tonumber(floor) or 1
  if floor == 0 then return Gen4Elevators.FLOOR_B1F end
  return Gen4Elevators.FLOOR_1F + floor - 1
end

-- The same six labels as English literals, for a cache whose text bank is
-- missing: a lift that says "3F" from a fallback is still a working lift, and
-- one that says TEXT_B0361_00118 is not.
Gen4Elevators.FLOOR_FALLBACK = { [0] = "B1F", "1F", "2F", "3F", "4F", "5F" }

function Gen4Elevators.floorLabel(floor)
  floor = tonumber(floor) or 1
  local label = Gen4Elevators.FLOOR_FALLBACK[floor]
  if label then return label end
  if floor < 0 then return ("B%dF"):format(-floor) end
  return ("%dF"):format(floor)
end

-- ---------------------------------------------------------------------------
-- THE DEPARTMENT STORE'S REGULAR
--
-- `SystemVars_GetDepartmentStoreBuyCount(varsFlags) >= 5` is the whole of
-- `ScrCmd_CheckIsDepartmentStoreRegular`. The counter is
-- VAR_DEPARTMENT_STORE_REGULAR_COUNTER, 0x4042 by the same enum walk over
-- generated/vars_flags.txt that put VAR_PLAYER_STARTER at 0x4030 -- checked
-- twice against the scripts, which name VAR_ELEVATOR_FLOORS_ABOVE (0x40CE) and
-- VAR_RESULT (0x800C) with exactly the ids the walk produces.
--
-- It is incremented by the SHOP, once per purchase at one of the nine
-- Veilstone department-store counters (`Shop_FinishPurchase`, on the
-- `incBuyCount` flag that `ScrCmd_PokeMartSpecialties` and
-- `ScrCmd_PokeMartDecor` set for those mart ids and no others). This port
-- declines the specialty counters -- their stock lists are a second table the
-- cache does not carry -- so the counter sits at zero and the question
-- answers "no" until they are extracted. That is the same answer the
-- cartridge gives a player who has bought nothing, and it starts working on
-- its own the day the stock lists land, which is why the threshold is read
-- from the var rather than hard-answered.
Gen4Elevators.BUY_COUNT_VAR = 0x4042
Gen4Elevators.REGULAR_PURCHASES = 5

return Gen4Elevators
