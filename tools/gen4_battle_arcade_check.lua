-- Run:  python tools/run_lua_check.py tools/gen4_battle_arcade_check.lua <platinum cache dir> [pokeplatinum]
--
-- PLATINUM'S BATTLE ARCADE (src/script/Gen4BattleArcade.lua) against
-- pokeplatinum's battle_arcade.c, battle_arcade_helpers.c and the Game Board
-- app: the opponents and Dahlia, which events each round and battle may deal,
-- the category weights by performance, the board's speed, every effect on
-- the teams (and who is immune), the performance score, the Battle Points,
-- the engine's new Trick Room and deep fog, and the wiring -- every row of
-- the Arcade's frontier script lowered, its two scenes, and the lobby.
--
-- Given a pokeplatinum checkout, the tables are read from the source and
-- compared.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('platinum')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
local pret = arg and arg[2]
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local Commands = require('src.script.Commands')
require('src.script.Gen4Commands')
require('src.script.Gen4FrontierScrCmds')
local A = require('src.script.Gen4BattleArcade')
local VM = require('src.script.Gen4FrontierVM')
local data = { gen4_battle_tower = load('gen4_battle_tower'), gen4_frontier_scripts = load('gen4_frontier_scripts'),
               pokemon = load('pokemon') or {}, moves = load('moves') or {}, constants = load('constants') or {},
               items = load('items') or {}, text = {} }
local growth = { 'MEDIUM_FAST', 'ERRATIC', 'FLUCTUATING', 'MEDIUM_SLOW', 'FAST', 'SLOW' }
for _, def in pairs(data.pokemon) do
  local b = def.baseStats; b.spatk = b.spAttack; b.spdef = b.spDefense; b.special = b.spAttack
  def.evYield = def.evYields; def.evYield.spatk = def.evYield.spAttack; def.evYield.spdef = def.evYield.spDefense
  def.growthRate = growth[def.expRate + 1]; def.level1Moves = {}
  for _, row in ipairs(def.learnset or {}) do if row.level <= 1 then table.insert(def.level1Moves, row.move) end end
  def.spriteFront, def.spriteBack, def.forms, def.picAnim = nil, nil, nil, nil
end
package.loaded['src.core.Data'] = data
local game = { data = data }
local E = A.E

-- ---------------------------------------------------------- the opponents --
check(A.opponentTrainerID(A.SINGLE, 2, 6) == A.DAHLIA_SILVER and A.opponentTrainerID(A.SINGLE, 6, 6) == A.DAHLIA_GOLD,
  'Dahlia is the 21st and 49th in singles')
local ok7 = true
for _ = 1, 200 do local id = A.opponentTrainerID(A.SINGLE, 0, 6); if id < 100 or id >= 119 then ok7 = false end end
check(ok7, "the seventh from the round's final range")

-- ------------------------------------------------------------- the board --
local function has(list, e) for _, x in ipairs(list) do if x == e then return true end end return false end
local r1 = A.available(0, 0)
check(has(r1, E.POISON_FOE) and not has(r1, E.LOWER_FOE_HP) and not has(r1, E.SUNNY) and has(r1, E.NO_EVENT),
  'round 1: the statuses, no HP cut, no weather')
check(not has(A.available(0, 6), E.SPEED_UP) and has(A.available(0, 5), E.SPEED_UP),
  "the board's own events never before a round's seventh battle")
check(has(A.available(4, 28), E.GET_1_BP) and not has(A.available(4, 29), E.GET_1_BP) and has(A.available(4, 29), E.NO_BATTLE),
  '1 BP on battles 1, 3, 5; No Battle on 2, 4, 6')
check(has(A.available(6, 43), E.GET_3_BP) and not has(A.available(5, 43), E.GET_3_BP), '3 BP from round 7')
check(has(A.available(20, 141), E.TRICK_ROOM), 'past round 7, round 7\'s list')
check(A.tier(0) == 4 and A.tier(5) == 3 and A.tier(10) == 2 and A.tier(16) == 1 and A.tier(21) == 0 and A.tier(30) == 0,
  'the category tier by performance (21 / 16 / 10 / 5)')
check(A.randomCategory(4, 9) == A.FOE and A.randomCategory(4, 10) == A.ALLY and A.randomCategory(4, 84) == A.ALLY
  and A.randomCategory(4, 85) == A.ENV and A.randomCategory(4, 95) == A.BONUS, 'sCategoryWeights tier 4: 10 / 75 / 10 / 5')
local grid = A.deal(0, 0, 0)
local legal = #grid == 16
for _, e in ipairs(grid) do if not has(r1, e) then legal = false end end
check(legal, 'sixteen panels, every one an event the round allows')
check(A.CURSOR_FRAMES[3] == 4 and A.CURSOR_FRAMES[7] == 0, 'sCursorMoveFrames')

-- ----------------------------------------------------------- the effects --
local Pokemon = require('src.pokemon.Pokemon')
local save = { party = { Pokemon.new(data, 445, 70), Pokemon.new(data, 448, 50), Pokemon.new(data, 392, 50) },
               player = { name = 'LUCAS' } }
save.party[1].item = 234
local f = A.init(data, save, 0, A.SINGLE, 0, 1, 2)
check(#f.team == 3 and f.team[1].level == 50 and not f.team[1].item and save.party[1].item == 234,
  'three copies at 50, without their items')
A.loadRound(data, f, 0)
A.setupOpponentsParty(game, f)
check(#f.opponentParty == 3 and not f.opponentParty[1].item, 'the opponents at level 50, items taken too')
check(f.rouletteSpeed == 3, 'board speed 3 in the first rounds')
f.currentRound = 7
A.loadRound(data, f, 0)
check(f.rouletteSpeed == 5, '...5 from round 8')
f.currentRound = 0

local max = f.team[2].stats.hp
A.applyEffect(f, E.LOWER_ALLY_HP)
check(f.team[2].hp == max - (math.floor(max * 1.2) - max), 'LowerHP: maxHP - ((u32)(maxHP * 1.2) - maxHP)')
-- Garchomp (Ground) cannot be paralysed; Lucario (Steel) cannot be poisoned
A.applyEffect(f, E.PARALYZE_ALLY)
check(not f.team[1].status and f.team[2].status == 'PAR' and not f.immuneToEffect, 'PAR: all but the Ground type')
f.team[2].status = nil
A.applyEffect(f, E.POISON_ALLY)
check(f.team[2].status == nil and f.team[1].status == 'PSN', 'PSN: never the Steel type')
for _, m in ipairs(f.team) do m.status = nil end
f.randomIndex = 1
A.applyEffect(f, E.SLEEP_ALLY)
local asleep = 0
for _, m in ipairs(f.team) do if m.status == 'SLP' then asleep = asleep + 1 end end
check(asleep == 1 and f.team[2].status == 'SLP' and f.team[2].sleepTurns >= 2 and f.team[2].sleepTurns <= 5,
  'SLP: one, from the random index, for 2-5 turns')
f.randomIndex = 3
A.applyEffect(f, E.ALLY_GET_BERRY)
check(f.team[1].item == 152 and f.team[3].item == 152, 'a Berry for all three, by the random index (Rawst)')
f.currentRound = 6
A.applyEffect(f, E.FOE_GET_ITEM)
check(f.opponentParty[1].item == A.ITEMS[3][4], "round 7's item pool")
f.currentRound = 0
A.applyEffect(f, E.FOE_LEVEL_UP)
check(f.opponentParty[1].level == 53, 'three levels')
A.applyEffect(f, E.TRICK_ROOM)
check(f.weather == 'TRICK_ROOM', 'the field effects ride on the weather')
f.rouletteSpeed = 7; A.applyEffect(f, E.SPEED_UP)
check(f.rouletteSpeed == 7, 'the board stops at speed 7')
-- every foe immune: immuneToEffect
f.opponentParty = { Pokemon.new(data, 445, 50), Pokemon.new(data, 450, 50) }
f.immuneToEffect = false
A.applyEffect(f, E.PARALYZE_FOE)
check(f.immuneToEffect, 'all of them immune: CHECK_IMMUNE_TO_EFFECT answers 1')

-- ------------------------------------------------- performance and BP --
local p = { { hp = 10 }, { hp = 0 }, { hp = 5, status = 'PSN' } }
check(A.performance(p, 2) == 6 + 4 + 10, 'performance: 6 (one status) + 4 (one fainted) + 10 (under 3 turns)')
check(A.performance({ { hp = 1 } }, 9) == 8 + 6 + 0, '...and 0 for 9 turns or more')
f.currentStreak, f.currentRound = 21, 3
check(A.earnedBP(f) == 20, '20 BP for Dahlia')
f.currentStreak = 14
check(A.earnedBP(f) == 2, 'sBPPerRoundSolo')
f.activeEffect = E.GET_3_BP
check(A.freeBP(f) == 3, 'the 3 BP panel')

-- --------------------------------------------------- Trick Room and fog --
local TurnOrder = require('src.battle.TurnOrder')
local function battler(speed) return { curStats = { speed = speed }, stages = {}, mon = {}, statuses = {} } end
local fast, slow = battler(100), battler(50)
check(TurnOrder.firstMover(fast, nil, slow, nil, function() return 0 end, false, { field = {} }),
  'the faster first')
check(not TurnOrder.firstMover(fast, nil, slow, nil, function() return 0 end, false, { field = { trickRoom = 3 } }),
  'Trick Room: the slower first')
local Damage = require('src.battle.Damage')
local att, def = { stages = {} }, { stages = {} }
local move = { accuracy = 100, type = 'NORMAL' }
local hits = 0
for i = 0, 255 do
  if Damage.accuracyRoll({}, move, att, def, function() return i end, nil, data, nil, true) then hits = hits + 1 end
end
check(hits == math.floor(255 * 6 / 10), 'deep fog: a 100% move hits 6/10 of the time')

-- ------------------------------------------------------------------ wiring --
local m = data.gen4_frontier_scripts and data.gen4_frontier_scripts.members[2]
local rows = m and VM.compile(data, 2, VM.entryLabel(data, 2, 0), 537) or {}
local missing, noop = {}, {}
for _, row in ipairs(rows) do
  if row[1] ~= 'label' and row[1] ~= 'jump' and type(Commands[row[1]]) ~= 'function' then missing[row[1]] = true end
  if row[1] == 'g4_noop' and tostring(row[2]):find('^frontier ') then noop[row[2]] = true end
end
local ml, nl = {}, {}
for k in pairs(missing) do ml[#ml + 1] = k end
for k in pairs(noop) do nl[#nl + 1] = k end
check(#rows > 100 and #ml == 0 and #nl == 0,
  ("every row of the Arcade's script is a command (%s | %s)"):format(table.concat(ml, ' '), table.concat(nl, ' ')))
local Scene = require('src.ui.Gen4FrontierScene')
check(Scene.SCENES[15] and Scene.SCENES[15].member == 2 and Scene.SCENES[16].bank == 537, 'FRONTIER_SCENE_ARCADE_*')
local art = require('src.import.Gen4FrontierArt').SCENES
check(art.arcade_corridor[1] == 55 and art.arcade_battle_room[1] == 52, 'their backdrops out of frontier_bg')
local vm = src('src/script/Gen4ScriptVM.lua')
check(vm:find('L.callbattlearcadelobbyfunction', 1, true) and type(Commands.g4_arcade_lobby) == 'function',
  "the lobby's commands")
check(type(require('src.ui.Gen4ArcadeScreen').new) == 'function', 'the Game Board')

-- -------------------------------------------------------------- the source --
if pret then
  local app = src(pret .. '/src/applications/frontier/battle_arcade/main.c')
  local body = app:match('sEffectAvailabilityByRound%[NUM_ARCADE_EFFECTS%] = (%b{})') or ''
  local names = {}
  for line in src(pret .. '/include/constants/battle_frontier.h'):gmatch('[^\n]+') do
    local n, v = line:match('#define (ARCADE_EFFECT_[%w_]+)%s+(%d+)')
    if n then names[n] = tonumber(v) end
  end
  local k, same = 0, true
  for name, bits in body:gmatch('%[(ARCADE_EFFECT_[%w_]+)%] =%s*{ ([%d, ]+) }') do
    k = k + 1
    local e, i = names[name], 0
    for b in bits:gmatch('%d') do
      i = i + 1
      if A.BY_ROUND[e][i] ~= (b == '1') then same = false end
    end
  end
  check(k == 32 and same, 'sEffectAvailabilityByRound matches the source')
  local w = app:match('sCategoryWeights%[%]%[NUM_ARCADE_EFFECT_CATEGORIES%] = (%b{})') or ''
  local t, sameW = 0, true
  for a, b, c, d in w:gmatch('{ (%d+), (%d+), (%d+), (%d+) }') do
    local row = A.WEIGHTS[t]
    if not (row and row[1] == tonumber(a) and row[2] == tonumber(b) and row[3] == tonumber(c) and row[4] == tonumber(d)) then sameW = false end
    t = t + 1
  end
  check(t == 5 and sameW, 'sCategoryWeights matches the source')
  local h = io.popen('git -C "' .. pret .. '" show HEAD:generated/frontier_trainers.txt')
  local tn, n = {}, 0
  for line in h:read('*a'):gmatch('[^\n]+') do tn[line] = n; n = n + 1 end
  h:close()
  check(tn.FRONTIER_TRAINER_ARCADE_STAR_DAHLIA_SILVER == A.DAHLIA_SILVER, "Dahlia's ids")
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
