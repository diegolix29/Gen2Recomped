-- HEARTGOLD / SOULSILVER POKeATHLON PERFORMANCE (pokeheartgold src/pokemon.c:
-- CalcBoxMonPokeathlonPerformance / CalcBoxmonPokeathlonStars /
-- PokeathlonStatScoreToStars).
--
-- A Pokemon's five performance stats, each 0..4 (one to five stars), in the
-- cartridge's order POWER, STAMINA, SKILL, JUMP, SPEED:
--   * the species' row of /a/1/6/9 (poketool/personal/performance.narc, 554
--     x 20 bytes: base[5], 4 unused, min / max [5][2], 1 unused), whose
--     columns are POWER, SPEED, JUMP, STAMINA, SKILL; row = ARC_IDX[species]
--     + form
--   * NAMES, MEASURED: pokeheartgold calls the stats POWER SKILL SPEED JUMP
--     STAMINA and the columns POWER STAMINA JUMP SKILL SPEED. Both are wrong
--     where they disagree with the cartridge: the summary prints stat 4 on its
--     "Speed" row, stat 1 on "Stamina", stat 2 on "Skill" (sub_0208B89C), and
--     Snorlax's published Speed 1/2, Power 4/5, Skill 1/3, Stamina 5/5, Jump
--     2/2 is columns 1, 0, 4, 3, 2. The arithmetic below is the decomp's.
--     (`gen4_hgss_performance`, src/import/Gen4HgssPokeathlon.lua)
--   * today's modifier: the nature's (NATURE_MODS) + 2 x (digit 0 of
--     (pid digit i + (day + 7 - i) x (day + i + 3))) - 9, day = the day of
--     the month -- the same Pokemon performs differently day to day
--   * stars = base + PokeathlonStatScoreToStars(modifier [+ Aprijuice]),
--     kept within min .. max; coloured as AT / ABOVE / BELOW the base

local M = {}

M.POWER, M.STAMINA, M.SKILL, M.JUMP, M.SPEED = 0, 1, 2, 3, 4
M.AT_BASE, M.ABOVE_BASE, M.BELOW_BASE = 0, 1, 2
-- stat -> the row's column (CalcBoxMonPokeathlonPerformance)
local ARC_COL = { [0] = 0, 3, 4, 2, 1 }

-- sPokeathlonPerformanceArcIdxs, by species (0..493)
M.ARC_IDX = {
  [0] = 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
  19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
  39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58,
  59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78,
  79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98,
  99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118,
  119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138,
  139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158,
  159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 173, 174, 175, 176, 177, 178, 179,
  180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199,
  200, 201, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246,
  247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266,
  267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286,
  287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306,
  307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326,
  327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346,
  347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366,
  367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386,
  387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406,
  407, 408, 409, 410, 411, 412, 413, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429,
  430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 445, 448, 449, 450, 451, 452, 453,
  454, 455, 456, 458, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475,
  476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495,
  496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515,
  521, 522, 523, 524, 525, 526, 527, 528, 530, 531, 532, 533, 534, 536,
}

-- sPokeathlonPerformanceNatureMods[nature][stat]
M.NATURE_MODS = {
  { 10, 0, 0, 0, -10 },
  { 35, -35, 0, 0, 0 },
  { 35, 0, 0, 0, -35 },
  { 35, 0, 0, -35, 0 },
  { 35, 0, -35, 0, 0 },
  { -35, 35, 0, 0, 0 },
  { 0, 10, 0, -10, 0 },
  { 0, 35, 0, 0, -35 },
  { 0, 35, 0, -35, 0 },
  { 0, 35, -35, 0, 0 },
  { -35, 0, 0, 0, 35 },
  { 0, -35, 0, 0, 35 },
  { 0, 0, -10, 0, 10 },
  { 0, 0, 0, -35, 35 },
  { 0, 0, -35, 0, 35 },
  { -35, 0, 0, 35, 0 },
  { 0, -35, 0, 35, 0 },
  { 0, 0, 0, 35, -35 },
  { -10, 0, 0, 10, 0 },
  { 0, 0, -35, 35, 0 },
  { -35, 0, 35, 0, 0 },
  { 0, -35, 35, 0, 0 },
  { 0, 0, 35, 0, -35 },
  { 0, 0, 35, -35, 0 },
  { 0, -10, 10, 0, 0 },
}

-- _u32_getDigitN
local function digit(n, d) return math.floor((n % (10 ^ (d + 1))) / (10 ^ d)) end

-- PokeathlonStatScoreToStars
function M.scoreToStars(a)
  if a <= -120 then return -4 elseif a <= -80 then return -3 elseif a <= -40 then return -2
  elseif a <= -15 then return -1 elseif a <= 14 then return 0 elseif a <= 39 then return 1
  elseif a <= 79 then return 2 elseif a <= 119 then return 3 end
  return 4
end

local function speciesId(mon)
  local id = mon and mon.species
  return tonumber(id) or tonumber(tostring(id or ""):match("(%d+)%s*$")) or 0
end

-- the species' row: { base = {[0..4]}, lo = {}, hi = {} } in PERFORMANCE order
function M.row(data, mon)
  local rows = data and data.gen4_hgss_performance
  if type(rows) ~= "table" then return nil end
  local sp = speciesId(mon)
  local idx = M.ARC_IDX[sp]
  if not idx then return nil end
  local raw = rows[idx + (tonumber(mon.form) or 0)] or rows[idx]
  if type(raw) ~= "table" then return nil end
  local out = { base = {}, lo = {}, hi = {} }
  for i = 0, 4 do
    local c = ARC_COL[i]
    out.base[i] = raw[c + 1] or 0
    out.lo[i] = raw[10 + 2 * c] or 0
    out.hi[i] = raw[11 + 2 * c] or 0
  end
  return out
end

-- CalcBoxMonPokeathlonPerformance's daily modifiers; `day` 1..31
function M.dailyMods(mon, day)
  local pid = tonumber(mon and mon.personality) or 0
  local nature = pid % 25
  local mods = {}
  for i = 0, 4 do
    local d = digit(pid, i)
    mods[i] = M.NATURE_MODS[nature + 1][i + 1] + (2 * digit(d + (day + (7 - i)) * (day + (i + 3)), 0) - 9)
  end
  return mods
end

-- CalcBoxmonPokeathlonStars: stars[0..4], colour[0..4]; `aprijuice` an
-- optional [0..4] of the party slot's Aprijuice modifiers
function M.stars(data, mon, aprijuice, day)
  local row = M.row(data, mon)
  if not row then return nil end
  day = day or tonumber(os.date("*t").day)
  local mods = M.dailyMods(mon, day)
  local stars, colour = {}, {}
  for i = 0, 4 do
    local s = M.scoreToStars(mods[i] + (aprijuice and (aprijuice[i] or 0) or 0)) + row.base[i]
    if s < row.lo[i] then s = row.lo[i] elseif s > row.hi[i] then s = row.hi[i] end
    stars[i] = s
    colour[i] = (s == row.base[i]) and M.AT_BASE or ((s < row.base[i]) and M.BELOW_BASE or M.ABOVE_BASE)
  end
  return stars, colour, row
end

return M
