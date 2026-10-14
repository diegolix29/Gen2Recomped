-- HeartGold / SoulSilver's roamers: the tables pokeheartgold's field_roamer.c
-- and constants/roamer.h hold, in the shape Gen4Roamers reads (generated from
-- them: sRoamerLocations, sRoamerAdjacencyTable, Save_CreateRoamerByID).
--
-- Raikou and Entei long-hop only within Johto (locations 0..15), Latias and
-- Latios only within Kanto (16..40) -- RoamerLocationSetRandom's loc_min /
-- loc_num -- so each slot carries its `region`.

local H = {}

local JOHTO, KANTO = {}, {}
for i = 0, 15 do JOHTO[#JOHTO + 1] = i end
for i = 16, 40 do KANTO[#KANTO + 1] = i end

H.SLOTS = {
  [0] = { name = "RAIKOU", species = 243, level = 40, region = JOHTO },
  [1] = { name = "ENTEI",  species = 244, level = 40, region = JOHTO },
  [2] = { name = "LATIAS", species = 380, level = 35, region = KANTO },
  [3] = { name = "LATIOS", species = 381, level = 35, region = KANTO },
}
H.SLOT_COUNT = 4

H.ROUTES = {
  [0] = { header = 33, map = "R29", what = "Route 29" },
  [1] = { header = 34, map = "R30", what = "Route 30" },
  [2] = { header = 35, map = "R31", what = "Route 31" },
  [3] = { header = 36, map = "R32", what = "Route 32" },
  [4] = { header = 37, map = "R33", what = "Route 33" },
  [5] = { header = 38, map = "R34", what = "Route 34" },
  [6] = { header = 39, map = "R35", what = "Route 35" },
  [7] = { header = 40, map = "R36", what = "Route 36" },
  [8] = { header = 41, map = "R37", what = "Route 37" },
  [9] = { header = 42, map = "R38", what = "Route 38" },
  [10] = { header = 43, map = "R39", what = "Route 39" },
  [11] = { header = 44, map = "R42", what = "Route 42" },
  [12] = { header = 45, map = "R43", what = "Route 43" },
  [13] = { header = 46, map = "R44", what = "Route 44" },
  [14] = { header = 47, map = "R45", what = "Route 45" },
  [15] = { header = 48, map = "R46", what = "Route 46" },
  [16] = { header = 9, map = "R01", what = "Route 1" },
  [17] = { header = 10, map = "R02", what = "Route 2" },
  [18] = { header = 11, map = "R03", what = "Route 3" },
  [19] = { header = 12, map = "R04", what = "Route 4" },
  [20] = { header = 13, map = "R05", what = "Route 5" },
  [21] = { header = 14, map = "R06", what = "Route 6" },
  [22] = { header = 15, map = "R07", what = "Route 7" },
  [23] = { header = 16, map = "R08", what = "Route 8" },
  [24] = { header = 17, map = "R09", what = "Route 9" },
  [25] = { header = 18, map = "R10", what = "Route 10" },
  [26] = { header = 19, map = "R11", what = "Route 11" },
  [27] = { header = 20, map = "R12", what = "Route 12" },
  [28] = { header = 21, map = "R13", what = "Route 13" },
  [29] = { header = 22, map = "R14", what = "Route 14" },
  [30] = { header = 23, map = "R15", what = "Route 15" },
  [31] = { header = 24, map = "R16", what = "Route 16" },
  [32] = { header = 25, map = "R17", what = "Route 17" },
  [33] = { header = 26, map = "R18", what = "Route 18" },
  [34] = { header = 91, map = "W19", what = "Route 19" },
  [35] = { header = 92, map = "W20", what = "Route 20" },
  [36] = { header = 93, map = "W21", what = "Route 21" },
  [37] = { header = 27, map = "R22", what = "Route 22" },
  [38] = { header = 28, map = "R24", what = "Route 24" },
  [39] = { header = 30, map = "R26", what = "Route 26" },
  [40] = { header = 32, map = "R28", what = "Route 28" },
}
H.ROUTE_COUNT = 41

H.NEARBY = {
  [0] = { 1, 15 },
  [1] = { 0, 2 },
  [2] = { 1, 3, 7 },
  [3] = { 2, 4, 7 },
  [4] = { 3, 5 },
  [5] = { 4, 6 },
  [6] = { 5, 7 },
  [7] = { 2, 3, 8 },
  [8] = { 7, 9, 11 },
  [9] = { 8, 10, 11 },
  [10] = { 9 },
  [11] = { 8, 9, 12, 13 },
  [12] = { 11, 13 },
  [13] = { 11, 12, 15 },
  [14] = { 13, 15 },
  [15] = { 0, 14 },
  [16] = { 17, 37 },
  [17] = { 16, 37, 18 },
  [18] = { 17, 19 },
  [19] = { 18, 20, 38 },
  [20] = { 19, 21, 22, 23, 24, 38 },
  [21] = { 22, 23, 26 },
  [22] = { 20, 21, 23, 31 },
  [23] = { 20, 21, 22, 25, 27 },
  [24] = { 19, 20, 25, 38 },
  [25] = { 23, 24, 27 },
  [26] = { 21, 27 },
  [27] = { 23, 25, 26, 28 },
  [28] = { 27, 29 },
  [29] = { 28, 30 },
  [30] = { 29, 33, 34 },
  [31] = { 22, 37 },
  [32] = { 31, 33 },
  [33] = { 30, 32, 34 },
  [34] = { 30, 33 },
  [35] = { 34, 36 },
  [36] = { 16, 34 },
  [37] = { 16, 17, 39, 40 },
  [38] = { 19, 20, 24 },
  [39] = { 37, 40 },
  [40] = { 37, 39, 24 },
}

return H
