-- Run:  texlua tools/hgss_battle_transition_check.lua
--
-- HEARTGOLD / SOULSILVER'S OWN BATTLE TRANSITIONS (src/render/
-- HgssBattleTransition.lua). What is checked:
--   1. the choice: class / species param, the generic terrain + time-of-day
--      chooser, doubles, the Frontier, Pal Park;
--   2. the wild land and cave effects' cell start ticks against the grids
--      worked out of overlay_120.s (the spec's tables), their length, and
--      that both screens end black;
--   3. an effect not written yet plays Platinum's nearest, never a Sinnoh
--      leader's banner.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

package.loaded['src.import.Gen4ScriptBands'] = { family = 'hgss' }
local H = require('src.render.HgssBattleTransition')
check(H.active(), 'the hgss family is detected')

-- ============================ 1. the choice
local DAY, NIGHT = 12, 22
check(H.choose({ species = 16, terrain = 'grass', hour = DAY }) == 0, 'wild Pidgey, grass, day -> 0')
check(H.choose({ species = 16, terrain = 'grass', hour = NIGHT }) == 1, 'wild at night -> 1')
check(H.choose({ species = 16, terrain = 'grass', hour = 2 }) == 1, 'LATE (02:00) counts as night')
check(H.choose({ species = 16, terrain = 'grass', hour = 19 }) == 0, 'EVE (19:00) is not night')
check(H.choose({ species = 129, terrain = 'water', hour = DAY }) == 2, 'wild, water, day -> 2')
check(H.choose({ species = 41, terrain = 'cave', hour = NIGHT }) == 5, 'wild, cave, night -> 5')
check(H.choose({ species = 41, terrain = 'cave', hour = DAY, enemyLevel = 90, leadLevel = 2 }) == 4,
      'no level comparison: a far stronger Zubat is still 4')
check(H.choose({ trainer = true, trainerClass = 1, terrain = 'grass', hour = DAY }) == 6, 'trainer, land, day -> 6')
check(H.choose({ trainer = true, trainerClass = 1, terrain = 'cave', hour = NIGHT }) == 11, 'trainer, cave, night -> 11')
check(H.choose({ trainer = true, trainerClass = 66, hour = DAY }) == 12, 'Falkner -> 12')
check(H.choose({ trainer = true, trainerClass = 110, hour = DAY }) == 27, 'Blue -> 27')
check(H.choose({ trainer = true, trainerClass = 86 }) == 33, 'Lance -> 33')
check(H.choose({ trainer = true, trainerClass = 23 }) == 28, 'the rival -> 28')
check(H.choose({ trainer = true, trainerClass = 66, double = true }) == 38, 'a leader in a double -> 38')
check(H.choose({ trainer = true, trainerClass = 55, double = true }) == 39, 'grunts keep theirs in a double')
check(H.choose({ trainer = true, trainerClass = 109 }) == 46, 'Red -> 46')
check(H.choose({ trainer = true, trainerClass = 1, frontier = true }) == 37, 'Frontier single -> 37')
check(H.choose({ species = 245, terrain = 'grass', hour = DAY }) == 0, 'Suicune uses the generic effect')
check(H.choose({ species = 249 }) == 36, 'Lugia -> 36')
check(H.choose({ species = 249, zone = 109, hour = DAY }) == 0, 'Pal Park: every species is generic')
check(H.choose({ species = 16, double = true }) == 38, 'a wild double -> 38')

-- ============================ 2. the wild effects' cells
local LAND_DAY = {
   0,  1,  2,  3,  4,  5,  6,  7,
  15, 14, 13, 12, 11, 10,  9,  8,
  16, 17, 18, 19, 20, 21, 22, 23,
  23, 22, 21, 20, 19, 18, 17, 16,
   8,  9, 10, 11, 12, 13, 14, 15,
   7,  6,  5,  4,  3,  2,  1,  0,
}
local LAND_NIGHT = {
   7,  6,  5,  4,  3,  2,  1,  0,
   8,  9, 10, 11, 12, 13, 14, 15,
  23, 22, 21, 20, 19, 18, 17, 16,
  16, 17, 18, 19, 20, 21, 22, 23,
  15, 14, 13, 12, 11, 10,  9,  8,
   0,  1,  2,  3,  4,  5,  6,  7,
}
local CAVE_NIGHT = {
  23, 23, 22, 21, 19, 17, 14, 11,
  22, 21, 20, 18, 16, 13, 10,  8,
  20, 19, 17, 15, 12,  9,  7,  5,
  18, 16, 14, 11,  8,  6,  4,  3,
  15, 13, 10,  7,  5,  3,  2,  1,
  12,  9,  6,  4,  2,  1,  0,  0,
}
local function grid(starts)
  local g = {}
  for t, cells in pairs(starts) do for _, c in ipairs(cells) do g[c + 1] = t end end
  return g
end
local function same(a, b)
  for i = 1, 48 do if a[i] ~= b[i] then return false, i end end
  return true
end
check(same(grid(H.landStarts(false)), LAND_DAY), 'effect 0 start grid')
check(same(grid(H.landStarts(true)), LAND_NIGHT), 'effect 1 start grid')
check(same(grid(H.caveStarts(false)), H.CAVE_DAY), 'effect 4 start grid')
check(same(grid(H.caveStarts(true)), CAVE_NIGHT), 'effect 5 start grid')

-- run each through Gen4BattleTransition
local T = require('src.render.Gen4BattleTransition')
for _, case in ipairs({ { 0, { species = 16, terrain = 'grass', hour = DAY }, 16 },
                        { 1, { species = 16, terrain = 'grass', hour = NIGHT }, -16 },
                        { 4, { species = 41, terrain = 'cave', hour = DAY }, 16 },
                        { 5, { species = 41, terrain = 'cave', hour = NIGHT }, -16 } }) do
  local id, ctx, col = case[1], case[2], case[3]
  local t = T.new({}, nil, ctx)
  check(t.hgssEffect == id and t.name == 'hgss_' .. id, ('effect %d is played (%s)'):format(id, tostring(t.name)))
  local peak, n, maxW, cells = 0, 0, 0, 0
  while not t.finished and n < 400 do
    t:step(); n = n + 1
    if math.abs(t.S.bright) > math.abs(peak) then peak = t.S.bright end
  end
  for _, r in pairs(t.S.rects) do
    cells = cells + 1
    if (r.w or 0) > maxW then maxW = r.w end
    check(r.w == 32 and r.h == 32, ('effect %d: every cell closed to 32x32'):format(id))
  end
  check(cells == 48, ('effect %d: 48 cells (%d)'):format(id, cells))
  check(peak == col, ('effect %d: flash peaks at %d (%s)'):format(id, col, tostring(peak)))
  check(t.S.cover == 'black' and t.S.other == -16, ('effect %d: both screens end black'):format(id))
  -- 1 + flash (~22) + 1 + 28 + 1
  check(n >= 50 and n <= 58, ('effect %d: %d ticks'):format(id, n))
end

-- the land bars open sideways: mid-way a cell is narrower than it is tall
do
  local t = T.new({}, nil, { species = 16, terrain = 'grass', hour = DAY })
  local seen = false
  for _ = 1, 400 do
    t:step()
    for _, r in pairs(t.S.rects) do if r.w == 16 and r.h == 32 then seen = true end end
    if t.finished then break end
  end
  check(seen, 'land: a 16x32 bar half open')
end

-- ============================ 3. not written yet
local t = T.new({}, nil, { trainer = true, trainerClass = 66, hour = DAY })
check(t.hgssEffect == 12 and t.name == 'hgss_12', 'Falkner plays his own: ' .. tostring(t.name))
t = T.new({}, nil, { trainer = true, trainerClass = 55, hour = DAY })
check(t.hgssEffect == 39 and t.name == 'hgss_39', 'a Rocket grunt plays 39: ' .. tostring(t.name))

-- ============================ 4. the water, trainer and Red effects run out
local RUNS = {
  { 2, { species = 129, terrain = 'water', hour = DAY } },
  { 3, { species = 129, terrain = 'water', hour = NIGHT } },
  { 6, { trainer = true, trainerClass = 1, terrain = 'grass', hour = DAY } },
  { 7, { trainer = true, trainerClass = 1, terrain = 'grass', hour = NIGHT } },
  { 8, { trainer = true, trainerClass = 1, terrain = 'water', hour = DAY } },
  { 9, { trainer = true, trainerClass = 1, terrain = 'water', hour = NIGHT } },
  { 10, { trainer = true, trainerClass = 1, terrain = 'cave', hour = DAY } },
  { 11, { trainer = true, trainerClass = 1, terrain = 'cave', hour = NIGHT } },
  { 46, { trainer = true, trainerClass = 109 } },
}
for _, case in ipairs(RUNS) do
  local id = case[1]
  local tt = T.new({}, nil, case[2])
  check(tt.name == 'hgss_' .. id, ('effect %d is the HGSS one (%s)'):format(id, tostring(tt.name)))
  local n = tt:runAll(600)
  check(tt.finished, ('effect %d finishes'):format(id))
  check(tt.S.cover == 'black' and tt.S.other == -16, ('effect %d ends black on both screens'):format(id))
  check(n > 25 and n < 120, ('effect %d: %d ticks'):format(id, n))
end

-- ============================ 5. the leaders and the rival end white
local CLASS_FOR = {}
for class, p in pairs(H.CLASS_PARAM) do if p <= 21 and not CLASS_FOR[p] then CLASS_FOR[p] = class end end
for id = 12, 28 do
  local p = id <= 27 and id - 12 or 21
  local tt = T.new({}, nil, { trainer = true, trainerClass = CLASS_FOR[p], trainerName = 'X' })
  check(tt.name == 'hgss_' .. id, ('leader effect %d chosen (%s)'):format(id, tostring(tt.name)))
  local n, peak, named = 0, 0, false
  while not tt.finished and n < 400 do
    tt:step(); n = n + 1
    if tt.S.bright > peak then peak = tt.S.bright end
    if tt.S.name and tt.S.name.text == 'X' then named = true end
  end
  check(tt.finished and tt.S.cover == 'white' and tt.S.other == 16, ('leader %d ends white on both screens'):format(id))
  check(named and peak == 16, ('leader %d: the white peak and the name'):format(id))
  check(n >= 110 and n <= 130, ('leader %d: %d ticks (~120)'):format(id, n))
end

-- ============================ 6. 37-45 and their final colours
local ENDS = {
  { 37, { trainer = true, trainerClass = 1, frontier = true }, 'black', -16 },
  { 38, { trainer = true, trainerClass = 1, double = true }, 'black', -16 },
  { 39, { trainer = true, trainerClass = 55 }, 'black', -16 },
  { 40, { trainer = true, trainerClass = 118, trainerName = 'X' }, 'white', 16 },
  { 41, { trainer = true, trainerClass = 117, trainerName = 'X' }, 'white', 16 },
  { 42, { trainer = true, trainerClass = 116, trainerName = 'X' }, 'white', 16 },
  { 43, { trainer = true, trainerClass = 114, trainerName = 'X' }, 'white', 16 },
  { 44, { trainer = true, trainerClass = 124, trainerName = 'X' }, 'white', 16 },
  { 45, { trainer = true, trainerClass = 47 }, 'black', -16 },
  { 29, { trainer = true, trainerClass = 87, trainerName = 'X' }, 'white', 16 },
  { 30, { trainer = true, trainerClass = 89, trainerName = 'X' }, 'white', 16 },
  { 31, { trainer = true, trainerClass = 112, trainerName = 'X' }, 'white', 16 },
  { 32, { trainer = true, trainerClass = 88, trainerName = 'X' }, 'white', 16 },
  { 33, { trainer = true, trainerClass = 86, trainerName = 'X' }, 'white', 16 },
  { 35, { species = 250 }, 'white', 16 },
  { 36, { species = 249 }, 'white', 16 },
}
for _, e in ipairs(ENDS) do
  local id = e[1]
  local tt = T.new({}, nil, e[2])
  check(tt.name == 'hgss_' .. id, ('effect %d chosen (%s)'):format(id, tostring(tt.name)))
  local n = tt:runAll(600)
  check(tt.finished and tt.S.cover == e[3] and tt.S.other == e[4],
        ('effect %d ends %s (%s / %s)'):format(id, e[3], tostring(tt.S.cover), tostring(tt.S.other)))
  check(n > 35 and n < 140, ('effect %d: %d ticks'):format(id, n))
end

do
  local tt = T.new({}, nil, { species = 150 })
  check(tt.hgssEffect == 34 and tt.name == 'mythical', 'Mewtwo: 34 plays the shared keyframes (' .. tostring(tt.name) .. ')')
end

print(('hgss battle transitions: %d passed, %d failed'):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
