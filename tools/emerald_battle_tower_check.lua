-- Run:  python tools/run_lua_check.py tools/emerald_battle_tower_check.lua <emerald cache dir>
--
-- EMERALD'S BATTLE TOWER (src/script/Gen3BattleFrontier.lua) against
-- battle_tower.c and frontier_util.c: who is drawn, the IVs, the team rules,
-- Anabel's appearances, the Battle Points, the level-mode eligibility, the
-- trainers' words, and the engine fixes the tower needed.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('emerald')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/emerald/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local F = require('src.script.Gen3BattleFrontier')
local G3 = require('src.script.Gen3Commands')

-- --------------------------------------------------------------- the data --
local constants = load('constants')
local data = { constants = constants, pokemon = load('pokemon'), moves = load('moves'), items = load('items'),
  trainers = load('trainers'), gen3_frontier_speech = load('gen3_frontier_speech') }
local P = constants and constants.gen3FrontierParties
check(P and #P.trainers == 300 and #P.mons == 882, 'the Frontier\'s 300 trainers and 882 sets are in the cache')
local sp = data.gen3_frontier_speech
check(sp and #sp == 300 and sp.tents and sp.tents[2] and #sp.tents[2] == 30,
  'gen3_frontier_speech: 300 trainers and the tents\' 30 (tools/gen3_frontier_speech_extract.lua)')
local E = require('src.script.EasyChat')
check(sp and E.phrase(data, sp[1].before, 3):find('NEVER GOING') ~= nil, 'Brady says "I AM NEVER GOING TO LOSE !"')

-- --------------------------------------------------------- who is drawn --
local ok = true
for c = 0, 7 do
  for b = 0, 6 do
    for _ = 1, 20 do
      local id = F.trainerFor(c, b, math.random)
      local r = (b == 6) and F.RANGES_HARD[c + 1] or F.RANGES[c + 1]
      if id < r[1] or id > r[2] then ok = false end
    end
  end
end
check(ok, 'GetRandomScaledFrontierTrainerId: each challenge\'s range, the hard one for the seventh')
check(F.trainerFor(12, 3, function() return 0 end) == 200, 'past challenge 7: the last range, 200-299')
check(F.ivsFor(0) == 3 and F.ivsFor(99) == 3 and F.ivsFor(100) == 6 and F.ivsFor(219) == 21 and F.ivsFor(220) == 31,
  'GetFrontierTrainerFixedIvs')
check(F.enemyLevel({ party = { { level = 41 } } }, F.LVL_50) == 50
  and F.enemyLevel({ party = { { level = 41 } } }, F.LVL_OPEN) == 60
  and F.enemyLevel({ party = { { level = 77 } } }, F.LVL_OPEN) == 77, 'level 50; open is the party\'s highest, 60 at least')

-- the team rules
local team = F.trainerParty(data, 150, 3, 50, math.random)
check(#team == 3, 'three Pokemon')
local species, items, natureOk = {}, {}, true
local order = constants.natureOrder
for _, mon in ipairs(team) do
  if species[mon.species] then species.dup = true end
  species[mon.species] = true
  if mon.item then if items[mon.item] then items.dup = true end items[mon.item] = true end
  if mon.ivs.attack ~= 12 then natureOk = false end
end
check(not species.dup and not items.dup, 'no species and no held item twice')
check(natureOk, 'trainer 150: IVs 12 in every stat')
check(F.spread(0x3F)[1] == 85 and F.spread(0x03)[1] == 255 and F.spread(0x03)[3] == 0, 'the EV spread: 510 over the flagged stats')
-- --------------------------------------------------------------- Anabel --
local save = { flags = {}, vars = {}, party = {} }
local ctx = { save = save, game = { data = data } }
G3.setVar(save, F.VAR_FACILITY, 0); G3.setVar(save, F.VAR_MODE, 0)
local s = F.state(save)
s.data[1] = 0
F.setStreak(s, 0, 0, 34)
check(F.brainStatus(ctx) == 1, 'streak 34: the 35th battle is Anabel (silver)')
F.setStreak(s, 0, 0, 33)
check(F.brainStatus(ctx) == 0, 'streak 33: not yet')
save.flags[G3.flagKey(F.FLAG_TOWER_SILVER)] = true
F.setStreak(s, 0, 0, 69)
check(F.brainStatus(ctx) == 2 and F.brainTeam(ctx) == 1, 'with the silver symbol, the 70th is Anabel gold')
save.flags[G3.flagKey(F.FLAG_TOWER_SILVER + 1)] = true
F.setStreak(s, 0, 0, 104)
check(F.brainStatus(ctx) == 4, 'with both: every 35 past 70 (105th) she is back')
G3.setVar(save, F.VAR_MODE, 1)
check(F.brainStatus(ctx) == 0, 'never in doubles')
local brain = F.brainParty(data, 1, 50, math.random)
check(#brain == 3 and brain[2].species == 'LATIOS' and brain[2].ivs.spatk == 31 and brain[2].evs.hp == 252,
  'her gold team: Raikou, Latios, Snorlax at 31 IVs')

-- -------------------------------------------------------- Battle Points --
check(F.battlePoints(1, 0) == 1 and F.battlePoints(1, 1) == 2 and F.battlePoints(5, 0) == 5
  and F.battlePoints(14, 0) == 14 and F.battlePoints(15, 0) == 15 and F.battlePoints(40, 0) == 15, 'sBattlePointAwards\' tower column')

-- ---------------------------------------------------------- eligibility --
local function mon(spc, lvl, item) return { species = spc, level = lvl, item = item } end
local c2 = { save = { party = { mon('METAGROSS', 50), mon('SALAMENCE', 50), mon('MEWTWO', 50) }, vars = {} },
  game = { data = data } }
G3.setVar(c2.save, F.VAR_MODE, 0); G3.setVar(c2.save, F.VAR_FACILITY, 0); G3.setVar(c2.save, F.VAR_RESULT, 0)
F.checkIneligible(c2)
check(G3.getVar(c2.save, 0x8004) == 1, 'Mewtwo cannot enter, so two are not enough')
c2.save.party[3] = mon('TYRANITAR', 55)
F.checkIneligible(c2)
check(G3.getVar(c2.save, 0x8004) == 1, 'level 55 cannot enter Lv. 50')
G3.setVar(c2.save, F.VAR_RESULT, 1)
F.checkIneligible(c2)
check(G3.getVar(c2.save, 0x8004) == 0 and F.state(c2.save).data[1] == 1, '...but can enter Open Level, which is then the mode')

-- ------------------------------------------------------------ the wiring --
local vm = src('src/script/Gen3ScriptVM.lua')
check(vm:find('[0x02021FC4] = 4', 1, true), 'Emerald\'s gStringVar4 (0x02021FC4) is a string buffer, so its msgboxes show')
check(src('src/world/OverworldController.lua'):find('frameScriptThisTick', 1, true),
  'a frame-table script takes the frame\'s input (TryRunOnFrameMapScript before interactions)')
check(src('src/battle/BattleState.lua'):find('if self.noExp then return end', 1, true), 'Frontier battles pay no experience')
check(src('src/core/Game.lua'):find('Gen3BattleFrontier").applyContinue', 1, true), 'a frontier save continues in the lobby')
local saveTbl = { player = { map = 'MAP_G26_N08', x = 1, y = 1 }, gen3ContinueAt = { map = 'MAP_G26_N05', x = 6, y = 6 } }
check(F.applyContinue(saveTbl) and saveTbl.player.map == 'MAP_G26_N05' and saveTbl.gen3ContinueAt == nil, '...once')
for _, n in ipairs({ 234, 235, 239, 245, 448, 524 }) do
  check(type(G3.SPECIALS[n]) == 'function', 'special ' .. n .. ' is served')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
