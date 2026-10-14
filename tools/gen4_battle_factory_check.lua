-- Run:  python tools/run_lua_check.py tools/gen4_battle_factory_check.lua <platinum cache dir> [pokeplatinum]
--
-- PLATINUM'S BATTLE FACTORY (src/script/Gen4BattleFactory.lua) against
-- pokeplatinum's battle_factory.c and battle_factory_helpers.c: the opponents'
-- ranges and Thorton, the set pools and their upgrades by trades, the six
-- rentals and the three they face, the trade, the Battle Points, the streak's
-- record, and the wiring -- every row of the Factory's frontier script lowered,
-- its two scenes, and the lobby's one command.
--
-- Given a pokeplatinum checkout, the pool tables are read from the source and
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
require('src.script.Gen4BattleHall')
local B = require('src.script.Gen4BattleFactory')
local VM = require('src.script.Gen4FrontierVM')
local data = { gen4_battle_tower = load('gen4_battle_tower'), gen4_frontier_scripts = load('gen4_frontier_scripts') }
local sets = data.gen4_battle_tower and data.gen4_battle_tower.sets or {}

-- ---------------------------------------------------------- the opponents --
local inRange, final = true, true
for _ = 1, 300 do
  local id = B.opponentTrainerID(B.DOUBLE, 0, 3)
  if id < 0 or id >= 99 then inRange = false end
  local f7 = B.opponentTrainerID(B.DOUBLE, 0, 6)
  if f7 < 100 or f7 >= 119 then final = false end
end
check(inRange and final, 'round 1: battles one to six from 0..98, the seventh from 100..118 (min + rand % spread)')
check(B.opponentTrainerID(B.SINGLE, 2, 6) == B.THORTON_SILVER and B.opponentTrainerID(B.SINGLE, 6, 6) == B.THORTON_GOLD
  and B.opponentTrainerID(B.DOUBLE, 2, 6) ~= B.THORTON_SILVER, 'Thorton at the 21st and 49th, in singles only')
local ids = {}
B.pickTrainers(B.SINGLE, 0, ids, 14)
local seen, dup = {}, false
for i = 0, 13 do if seen[ids[i]] then dup = true end seen[ids[i]] = true end
check(not dup and ids[13] ~= nil, 'fourteen trainers a round, none twice')
local _, pi = B.opponentPool(99, 0)
local _, pj = B.opponentPool(100, 0)
local _, pt = B.opponentPool(B.THORTON_GOLD, 0)
check(pi == 1 and pj == 2 and pt == 10, 'the pool is the first whose trainerIDMax is above the id')
check(B.upgradable(0) == 0 and B.upgradable(6) == 0 and B.upgradable(7) == 1 and B.upgradable(34) == 4
  and B.upgradable(35) == 5, 'sTradeCountsNeededForUpgrades: one more upgraded slot past 6, 13, 20, 27, 34 trades')

-- ------------------------------------------------------------- the pools --
local pools, p1 = B.playerPool(0, 0)
local got, ivs = B.selectFromPool(data, nil, 6, pools, p1, 7)   -- 7 trades: one slot from the next pool
local species, items, clash = {}, {}, false
for i, id in ipairs(got) do
  local s = sets[id]
  if species[s.species] or items[s.item] then clash = true end
  species[s.species], items[s.item] = true, true
end
local lowOk = true
for i = 1, 5 do if got[i] < 1 or got[i] > 150 or ivs[i] ~= 0 then lowOk = false end end
check(#got == 6 and not clash, 'six sets, no species or item twice')
check(lowOk and got[6] >= 151 and got[6] <= 250 and ivs[6] == 4, 'the last slot from the next pool up, at its IVs')

local save = { party = {}, player = {} }
local f = B.init(save, 0, B.SINGLE, 0)
B.newRound(data, f)
local rentalSpecies, rentalItems = {}, {}
for _, e in ipairs(f.rentals) do rentalSpecies[e.species], rentalItems[e.item] = true, true end
local free = true
for _, e in ipairs(f.opponentEntries) do
  if rentalSpecies[e.species] or rentalItems[e.item] then free = false end
end
check(#f.rentals == 6 and #f.opponentEntries == 3 and free, "six rentals; the first team shares no species or item with them")
check(f.rentals[1].personality and f.rentals[1].personality % 25 == f.rentals[1].nature, "a personality of the set's nature")

f.selected = { [0] = 5, 0, 2 }
B.takeRentals(f)
check(f.playerEntries[1] == f.rentals[6] and f.playerEntries[2] == f.rentals[1] and f.playerSets[3] == f.rentalSets[3],
  'AddSelectedRentalsToParty: the app\'s picks, in order')
B.nextOpponent(data, f)
check(#f.opponentEntries == 3 and f.beatenSets[1] ~= nil, 'SetupNextOpponent: the beaten sets kept, a new team')
local mine1, theirs2 = f.playerEntries[1], f.opponentParty[2]
f.selected = { [0] = 0, 1 }
f.tradeCount = 0
check(B.applyTrade(f) and f.playerEntries[1] == theirs2 and f.playerSets[1] == f.beatenSets[2] and f.tradeCount == 1,
  'ApplyTrade: yours for theirs, the set id carried, a trade counted')
f.selected = { [0] = 0xFF }
check(not B.applyTrade(f), '0xFF keeps your team')
local _ = mine1

-- ----------------------------------------------------------- BP and streaks --
f.currentRound, f.currentStreak = 1, 7
check(B.earnedBP(f) == 5, 'the first round cleared: 5 BP')
f.currentStreak = B.SILVER
check(B.earnedBP(f) == 20, "Thorton's silver battle: 20")
f.challengeType = B.DOUBLE
f.currentRound = 12
check(B.earnedBP(f) == 9, 'past the eighth round, the eighth row')
f.challengeType = B.SINGLE
f.saveStreak, f.currentStreak, f.tradeCount = true, 14, 3
B.save(f, 0)
local f2 = B.init(save, 0, B.SINGLE, 0)
check(f2.currentStreak == 14 and f2.tradeCount == 3 and f2.currentRound == 2, 'a saved streak is carried into the next challenge')
local f3 = B.init(save, 0, B.SINGLE, 1)
check(f3.currentStreak == 0, 'open level keeps its own')
check(B.level(f3) == 100 and B.level(f2) == 50, 'level 50, or 100 at Open Level')

-- ------------------------------------------------------------------ wiring --
local store = data.gen4_frontier_scripts
local m = store and store.members[1]
check(m and m.entries[1] == 0x2D6, 'fr_script member 1 is the Factory (_02D6)')
local missing, noop = {}, {}
for i = 0, (m and #m.entries or 1) - 1 do
  local rows = m and VM.compile(data, 1, VM.entryLabel(data, 1, i), 365) or {}
  for _, row in ipairs(rows) do
    if row[1] ~= 'label' and row[1] ~= 'jump' and type(Commands[row[1]]) ~= 'function' then missing[row[1]] = true end
    if row[1] == 'g4_noop' and tostring(row[2]):find('^frontier ') then noop[row[2]] = true end
  end
end
local ml, nl = {}, {}
for k in pairs(missing) do ml[#ml + 1] = k end
for k in pairs(noop) do nl[#nl + 1] = k end
check(#ml == 0 and #nl == 0, ('every row of the Factory\'s script is a command (%s | %s)'):format(table.concat(ml, ' '), table.concat(nl, ' ')))
local Scene = require('src.ui.Gen4FrontierScene')
check(Scene.SCENES[3] and Scene.SCENES[3].member == 1 and Scene.SCENES[4] and Scene.SCENES[4].bank == 365,
  'FRONTIER_SCENE_FACTORY_CORRIDOR and _BATTLE_ROOM')
local art = require('src.import.Gen4FrontierArt').SCENES
check(art.factory_corridor and art.factory_corridor[1] == 2 and art.factory_battle_room[1] == 1,
  'their backdrops out of frontier_bg (battle_factory_corridor / _battle_room)')
check(src('src/script/Gen4ScriptVM.lua'):find('L.deleteactivebattlefactorystreak', 1, true)
  and type(Commands.g4_bf_delete_streak) == 'function', "the lobby's DeleteActiveBattleFactoryStreak")

-- -------------------------------------------------------------- the source --
if pret then
  local c = src(pret .. '/src/overlay104/battle_factory_helpers.c')
  local names = {}
  local h = io.popen('git -C "' .. pret .. '" show HEAD:generated/frontier_trainers.txt')
  local n = 0
  for line in h:read('*a'):gmatch('[^\n]+') do names[line] = n; n = n + 1 end
  h:close()
  local opp = c:match('sBattleFactoryOpponentPools%[%] = (%b{})') or ''
  local k, same = 0, true
  for a, b, cc, d in opp:gmatch('{ (FRONTIER_TRAINER_[%w_]+), (FRONTIER_TRAINER_[%w_]+), (FRONTIER_TRAINER_[%w_]+), (FRONTIER_TRAINER_[%w_]+) }') do
    k = k + 1
    local row = B.OPPONENT_POOLS[k]
    if not (row and row[1] == names[a] and row[2] == names[b] and row[3] == names[cc] and row[4] == names[d]) then same = false end
  end
  check(k == 8 and same, 'sBattleFactoryOpponentPools matches the source')
  for name, mine in pairs({ sLevel50Pools = B.POOLS_50, sOpenLevelOpponentPools = B.POOLS_OPEN_OPPONENT,
                            sOpenLevelPlayerPools = B.POOLS_OPEN_PLAYER }) do
    local body = c:match(name .. '%[%] = (%b{})') or ''
    local j, ok = 0, true
    for t, lo, hi, iv, up in body:gmatch('trainerIDMax = (FRONTIER_TRAINER_[%w_]+),%s*%.setIDMin = (%d+),%s*%.setIDMax = (%d+),%s*%.ivs = (%d+),%s*%.canBeUpgraded = (%a+)') do
      j = j + 1
      local p = mine[j]
      if not (p and p.trainerIDMax == names[t] and p.min == tonumber(lo) and p.max == tonumber(hi)
              and p.ivs == tonumber(iv) and p.up == (up == 'TRUE')) then ok = false end
    end
    check(j == 10 and ok, name .. ' matches the source')
  end
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
