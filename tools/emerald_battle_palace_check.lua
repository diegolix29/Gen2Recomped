-- Run:  python tools/run_lua_check.py tools/emerald_battle_palace_check.lua <emerald cache dir>
--
-- BATTLE PALACE RULES (src/battle/Gen3Palace.lua) and THE BATTLE PALACE
-- (src/script/Gen3BattleFrontier.lua) against pokeemerald: the move groups,
-- the natures' odds, the fallback and its coin flip, the half-HP flag, the
-- palace's streak, Spenser, its Battle Points, and that Verdanturf's tent
-- (the same facility number) is not mistaken for it.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('emerald')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/emerald/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local Palace = require('src.battle.Gen3Palace')
local moves = load('moves')
local data = { moves = moves, text = load('text'), constants = load('constants') }

-- --------------------------------------------------------- the move groups --
check(Palace.group(moves.TACKLE) == Palace.ATTACK, 'TACKLE: attack')
check(Palace.group(moves.GROWL) == Palace.SUPPORT, 'GROWL (both foes, no power): support')
check(Palace.group(moves.PROTECT) == Palace.DEFENSE, 'PROTECT (user): defense')
check(Palace.group(moves.SPIKES) == Palace.SUPPORT, 'SPIKES (opponents\' field): support')
check(Palace.group(moves.COUNTER) == Palace.SUPPORT, 'COUNTER (depends): support')
check(Palace.group(moves.SURF) == Palace.ATTACK, 'SURF (both foes, power): attack')

-- ------------------------------------------------------------- the odds --
local L = Palace.LIKELIHOOD
check(L[0][1] == 61 and L[0][2] == 68 and L[3][1] == 38 and L[3][2] == 69 and L[3][3] == 70 and L[3][4] == 85,
  'PALACE_STYLE: Hardy 61/68, Adamant 38/69 and 70/85 below half')
local function battler(nature, list, low)
  local cur = {}
  for i, id in ipairs(list) do cur[i] = { id = id, pp = 10 } end
  return { curMoves = cur, palaceLow = low, mon = { personality = nature, hp = 100, stats = { hp = 200 } } }
end
local battle = { data = data }
-- Adamant (3) with only attacks: roll 0 -> attack group -> an attack
local b = battler(3, { 'TACKLE', 'SURF' })
local seq = { 0, 0 }
local function rolls(t) local i = 0 return function(n) i = i + 1; return (t[i] or 0) % n end end
check(Palace.choose(battle, b, rolls({ 0, 1 })).id == 'SURF', 'roll 0 for Adamant: the attack group, its 2nd move')
-- roll 50 for Adamant is defense (38 <= 50 < 69); no defense move: fallback
local f = Palace.choose(battle, b, rolls({ 50, 0, 49 }))
check(f.id == 'TACKLE', 'no move in the group: a usable one, kept on a roll under 50')
local g = Palace.choose(battle, b, rolls({ 50, 0, 50 }))
check(g.special == 'palaceFail', '...and lost on 50 or more ("appears incapable")')
-- below half: Adamant's second set (70 attack) -- roll 69 attacks, not 38's split
local low = battler(3, { 'TACKLE', 'PROTECT' }, true)
check(Palace.choose(battle, low, rolls({ 69, 0 })).id == 'TACKLE', 'at half HP the second odds apply')
local nopp = battler(3, { 'TACKLE' })
nopp.curMoves[1].pp = 0
check(Palace.choose(battle, nopp, rolls({ 0 })).special == 'palaceFail', 'nothing usable: incapable')
check(Palace.isLow({ hp = 100, stats = { hp = 200 } }) and not Palace.isLow({ hp = 101, stats = { hp = 200 } })
  and not Palace.isLow({ hp = 50, stats = { hp = 200 }, status = 'SLP' }), 'half HP or below, and awake')
check(Palace.flavorLine(battle, battler(0, {}), 'X') == 'X is eager for more!', 'Hardy: "is eager for more!"')
check(Palace.flavorLine(battle, battler(1, {}), 'X'):find('glint') ~= nil, 'Lonely: a glint in its eyes')
check(Palace.incapableLine(battle, 'X'):find('incapable') ~= nil, 'the incapable line from the ROM')

-- ---------------------------------------------------------- the facility --
local F = require('src.script.Gen3BattleFrontier')
local G3 = require('src.script.Gen3Commands')
local save = { flags = {}, vars = {}, party = {} }
local ctx = { save = save, game = { data = data } }
G3.setVar(save, F.VAR_FACILITY, F.PALACE); G3.setVar(save, F.VAR_MODE, 0)
local s = F.state(save)
s.data[1] = 0
F.setStreak(s, 0, 0, 20, F.PALACE)
check(F.brainStatus(ctx) == 1, 'palace streak 20: the 21st is Spenser (silver)')
F.setStreak(s, 0, 0, 34, F.PALACE)
check(F.brainStatus(ctx) == 0 and F.streak(s, 0, 0, F.TOWER) == 0, 'the tower\'s streak is its own')
data.pokemon = load('pokemon')
local sp = F.brainParty(data, 1, 50, math.random, F.PALACE)
check(#sp == 3 and sp[3].species == 'SUICUNE' and sp[1].ivs.attack == 31,
  'Spenser\'s gold team: Arcanine, Slaking, Suicune at 31 IVs')
check(F.battlePoints(1, 0, F.PALACE) == 4 and F.battlePoints(3, 0, F.PALACE) == 5
  and F.battlePoints(3, 1, F.PALACE) == 6 and F.battlePoints(40, 0, F.PALACE) == 15, 'the palace\'s BP column')
G3.setVar(save, 0x8004, 6)
G3.SPECIALS[237](ctx)
check(F.streak(s, 0, 0, F.PALACE) == 35, 'IncrementPalaceStreak')
G3.setVar(save, 0x8004, 1); G3.setVar(save, 0x8005, 1)
G3.SPECIALS[237](ctx)
check(G3.getVar(save, 0x800D) == 35, 'GetPalaceData: the streak')

-- the tent is the same facility number: its level mode tells them apart
s.data[1] = F.LVL_TENT
local tentSave = src('src/script/Gen3BattleFrontier.lua')
check(tentSave:find('return F.lvl(F.state(ctx.save)) == F.LVL_TENT', 1, true), 'a tent challenge is FRONTIER_LVL_TENT')
check(src('src/script/Gen3Commands.lua'):find('palace = (fac == 2) or nil', 1, true),
  'Verdanturf\'s tent fights under Palace rules, with no EXP and no whiteout')
check(src('src/battle/BattleState.lua'):find('if self.palace and self.phase == "menu" then', 1, true),
  'no orders in a Palace battle')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
