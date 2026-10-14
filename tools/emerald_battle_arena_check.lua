-- Run:  python tools/run_lua_check.py tools/emerald_battle_arena_check.lua <emerald cache dir> [pokeemerald]
--
-- THE BATTLE ARENA (src/battle/Gen3Arena.lua, src/script/Gen3BattleFrontier.lua's
-- arenaFunc) against pokeemerald's battle_arena.c, battle_main.c,
-- battle_util.c and frontier_util.c: the Mind table, the Skill rule, the
-- judgment, who goes down after it, the arena's functions, prizes, Battle
-- Points and Greta -- and the rules every Frontier battle now has (RUN asks
-- to forfeit) and the arena's own (nobody switches).
--
-- Given a pokeemerald checkout as the second argument, the Mind rule is
-- also compared with every row of sMindRatings.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/emerald/data/generated'):gsub('[/\\]$', '')
local pret = arg and arg[2]
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local Arena = require('src.battle.Gen3Arena')
local moves = load('moves') or {}
local text = load('text') or {}
local data = { moves = moves, text = text }

-- ---------------------------------------------------------------- Mind --
check(Arena.mindFor(data, 'TACKLE') == 1, 'a move with power: 1')
check(Arena.mindFor(data, 'GROWL') == 0, 'a move without: 0')
check(Arena.mindFor(data, 'FAKE_OUT') == -1, 'Fake Out: -1')
check(Arena.mindFor(data, 'COUNTER') == 0 and Arena.mindFor(data, 'MIRROR_COAT') == 0
  and Arena.mindFor(data, 'BIDE') == 0, 'Counter, Mirror Coat, Bide: 0')
check(Arena.mindFor(data, 'PROTECT') == -1 and Arena.mindFor(data, 'DETECT') == -1
  and Arena.mindFor(data, 'ENDURE') == -1, 'Protect, Detect, Endure: -1')
check(Arena.mindFor(data, 'SEISMIC_TOSS') == 1, 'Seismic Toss (power 1): 1')
if pret then
  local c = src(pret .. '/src/battle_arena.c')
  local tbl = c:match('sMindRatings%[MOVES_COUNT%]%s*=%s*(%b{})') or ''
  local listed, wrong, n = {}, {}, 0
  -- the cache spells a few ids without the decomp's underscores (THUNDERPUNCH)
  for name, v in tbl:gmatch('%[MOVE_([%w_]+)%]%s*=%s*(%-?%d+)') do listed[name:gsub('_', '')] = tonumber(v) end
  for id, def in pairs(moves) do
    if type(id) == 'string' and type(def) == 'table' and def.power ~= nil and id ~= 'NONE' then
      n = n + 1
      if (listed[id:gsub('_', '')] or 0) ~= Arena.mindFor(data, id) then wrong[#wrong + 1] = id end
    end
  end
  check(n > 300 and #wrong == 0, ('sMindRatings: the rule matches all %d moves (%s)'):format(n, table.concat(wrong, ' ')))
end

-- --------------------------------------------------------------- Skill --
check(Arena.skillFor({ typeMult = 20 }) == 2, 'super effective: +2')
check(Arena.skillFor({ typeMult = 10 }) == 1, 'ordinary: +1')
check(Arena.skillFor({ typeMult = 5 }) == -1, 'not very effective: -1')
check(Arena.skillFor({ failed = true }) == -2, 'missed or failed: -2')
check(Arena.skillFor({ typeMult = 0 }) == -2, 'no effect: -2')
check(Arena.skillFor({ failed = true, protected = true }) == 0, 'stopped by Protect: nothing')
check(Arena.skillFor({ selfProtect = true }) == 0, "the user's own Protect: nothing")
check(Arena.skillFor({}) == 1, 'a status move that worked: +1')
check(Arena.skillFor({ typeMult = 0, ability = true }) == -5, 'an ability made it nothing: -2 and -3')

-- ------------------------------------------------------------ the judge --
local function mon(hp) return { hp = hp } end
local said = {}
local function battle(php, ehp)
  local p = { name = 'METAGROSS', isPlayer = true, mon = mon(php) }
  local e = { name = 'HOPPIP', mon = mon(ehp) }
  local b = { data = data, player = p, enemy = e, trainer = { name = 'JILLIAN' },
    game = { save = { player = { name = 'MAY' } } }, queue = {},
    say = function(self, t) said[#said + 1] = t end,
    sayNext = function(self, t) said[#said + 1] = t end,
    drainNext = function() end,
    onFaint = function(self, x) x.fainted = true end }
  return b
end
local b = battle(100, 100)
Arena.reset(b)
b.arenaState.startHp = { 200, 100 }
b.arenaState.mind = { 3, 1 }
b.arenaState.skill = { 2, 2 }
local r, t1, t2, calls = Arena.judge(b)
check(calls[1] == 'player' and calls[2] == 'tie' and calls[3] == 'opponent',
  'Mind 3-1 the player, Skill 2-2 even, Body 50% vs 100% the opponent')
check(t1 == 3 and t2 == 3 and r == 'tie', 'two for a category, one each for a tie: 3 to 3 is a draw')
b.arenaState.skill = { 4, 2 }
r, t1, t2 = Arena.judge(b)
check(r == 'player' and t1 == 4 and t2 == 2, '4 to 2: the player')

-- three turns, then the referee
said = {}
local b2 = battle(150, 80)
check(Arena.newPair(b2) and said[1] and said[1]:find('METAGROSS VS HOPPIP', 1, true),
  '"REFEREE: METAGROSS VS HOPPIP! Commence battling!" before a new pair moves')
check(not Arena.newPair(b2), '...once')
b2.arenaState.startHp = { 150, 80 }
Arena.turnStarted(b2); Arena.endOfTurn(b2)
Arena.turnStarted(b2); Arena.endOfTurn(b2)
check(b2.enemy.mon.hp == 80 and b2.arenaState.judged == nil, 'two turns: no judgment yet')
Arena.addMind(b2, b2.player, 'TACKLE')
Arena.turnStarted(b2); Arena.endOfTurn(b2)
check(b2.arenaState.judged == 'player' and b2.enemy.mon.hp == 0 and b2.enemy.fainted and b2.player.mon.hp == 150,
  'the third: judged, and the loser is counted as fainted')
local joined = table.concat(said, '|')
check(joined:find('Judging category 1, Mind', 1, true) and joined:find('Judgment: 4 to 2', 1, true)
  and joined:find("MAY's METAGROSS", 1, true), 'the categories, the score, the winner')
check(joined:find('defeated the opponent', 1, true), "the ROM's \"defeated the opponent ... in a REFEREE's decision!\"")
local b3 = battle(100, 100)
Arena.reset(b3); b3.arenaState.turn = 2
Arena.endOfTurn(b3)
check(b3.player.mon.hp == 0 and b3.enemy.mon.hp == 0, 'a draw: both go down')
local b4 = battle(100, 100)
Arena.reset(b4); b4.arenaState.turn = 2
b4.player = { name = 'SALAMENCE', isPlayer = true, mon = mon(100) }
Arena.endOfTurn(b4)
check(b4.player.mon.hp == 100, 'a pair that has not had its three turns together is not judged')

-- --------------------------------------------------------- the facility --
local F = require('src.script.Gen3BattleFrontier')
check(F.ARENA == 3, 'FRONTIER_FACILITY_ARENA = 3')
local bp = {}
for c = 0, 30 do bp[#bp + 1] = F.battlePoints(c, 0, F.ARENA) end
check(bp[1] == 1 and bp[2] == 1 and bp[5] == 2 and bp[12] == 5 and bp[13] == 6 and bp[22] == 15 and bp[31] == 15,
  "sBattlePointAwards' arena column: 1 1 1 2 2 2 3 3 4 4 5 6 ... 15")
check(F.BRAIN_AT_BY[3][1] == 28 and F.BRAIN_AT_BY[3][2] == 56, 'Greta at 28 and 56')
check(F.BRAIN_GFX[3] == 72 and F.BRAIN_TRAINER[3] == 'GRETA', "OBJ_EVENT_GFX_GRETA, TRAINER_GRETA")
check(F.GRETA[0][3].species == 'SHEDINJA' and F.GRETA[1][2].moves[4] == 'DESTINY_BOND', "Greta's two teams")
for _, team in pairs(F.GRETA) do
  for _, m in ipairs(team) do
    for _, mv in ipairs(m.moves) do check(moves[mv], 'Greta\'s ' .. m.species .. ' knows ' .. mv) end
  end
end
check(#F.ARENA_EARLY == 6 and #F.ARENA_LATE == 9 and F.ARENA_LATE[9] == 'CHOICE_BAND', 'the prizes, short and long streak')

-- the functions, on a save
require('src.core.GameVersion').set('emerald')
local G3 = require('src.script.Gen3Commands')
local save = { vars = {}, party = {} }
local ctx = { save = save, game = { data = { items = {} }, stringBuffers = {} } }
G3.setVar(save, F.VAR_FACILITY, F.ARENA)
G3.setVar(save, F.VAR_MODE, 0)
local s = F.state(save)
s.data[1] = 0
F.arenaFunc(ctx, 0)
G3.setVar(save, 0x8005, 2); G3.setVar(save, 0x8006, 1)
F.arenaFunc(ctx, 2)
G3.setVar(save, 0x8005, 1); G3.setVar(save, 0x8006, 12)
F.arenaFunc(ctx, 2)
G3.setVar(save, 0x8005, 2)
F.arenaFunc(ctx, 1)
check(G3.getVar(save, F.VAR_RESULT) == 1, 'ARENA_DATA_WIN_STREAK_ACTIVE set and read back')
G3.setVar(save, 0x8005, 1)
F.arenaFunc(ctx, 1)
check(G3.getVar(save, F.VAR_RESULT) == 12, 'ARENA_DATA_WIN_STREAK: 12')
check(F.streak(s, 0, 0, F.TOWER) ~= 12, "the arena's streak is its own, not the tower's")
F.arenaFunc(ctx, 4)
local early = false
for _, it in ipairs(F.ARENA_EARLY) do if it == s.arenaPrize then early = true end end
check(early, 'SetArenaPrize: a vitamin below 42 wins')

-- --------------------------------------------------------- the wiring --
local fr = src('src/script/Gen3BattleFrontier.lua')
check(fr:find('arena = (fac == F.ARENA) or nil, forfeit = true', 1, true), 'the battle: arena rules, forfeitable')
check(fr:find('local arenaFallback = S[240]', 1, true), 'special 240 is CallBattleArenaFunction')
check(fr:find('if arg == 5 and frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.ARENA then F.battle(ctx)', 1, true),
  'SPECIAL_BATTLE_ARENA (5)')
check(fr:find('setVar(ctx, F.VAR_RESULT, s.lastOutcome)', 1, true), 'the outcome reaches VAR_RESULT, as every battle\'s does')
check(fr:find('[21] = true', 1, true), "frontier_resetsketch no longer zeroes VAR_RESULT on its way past")
local bs = src('src/battle/BattleState.lua')
check(bs:find('require("src.battle.Gen3Arena").newPair(self)', 1, true), 'the referee before each pair')
check(bs:find('require("src.battle.Gen3Arena").endOfTurn(self)', 1, true), 'the judgment at the end of the turn')
check(bs:find('if self.palace or self.arena then', 1, true), 'the next one goes out, unasked')
check(bs:find("can't be switched", 1, true), 'the party menu refuses a switch')
check(bs:find('self.kind == "trainer" and self.forfeitable', 1, true), 'RUN in a Frontier battle asks to forfeit')
check(src('src/battle/TrainerAI.lua'):find('if battle.arena then return nil end', 1, true), 'the trainer never switches')
check(src('src/battle/EffectRegistry.lua'):find('battle.arenaOutcome.typeMult = info.typeMult', 1, true),
  'the damage reports its effectiveness')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
