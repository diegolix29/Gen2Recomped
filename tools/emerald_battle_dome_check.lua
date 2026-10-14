-- Run:  python tools/run_lua_check.py tools/emerald_battle_dome_check.lua <emerald cache dir> [pokeemerald]
--
-- THE BATTLE DOME (src/script/Gen3BattleDome.lua) against pokeemerald's
-- battle_dome.c: the bracket tables, the seeding stats (bugs kept), the
-- type-effectiveness points and their quirks, who meets whom round by round,
-- the paper matches (Tucker always wins), the Battle Points by tournaments
-- won, Tucker's appearances, and the wiring.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('emerald')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/emerald/data/generated'):gsub('[/\\]$', '')
local pret = arg and arg[2]
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local G3 = require('src.script.Gen3Commands')
local F = require('src.script.Gen3BattleFrontier')
local D = require('src.script.Gen3BattleDome')
local data = { moves = load('moves') or {}, pokemon = load('pokemon') or {}, constants = load('constants') or {},
               trainers = load('trainers') or {}, type_chart = load('type_chart') }

-- --------------------------------------------------------------- tables --
check(D.ID_TO_OPPONENT[0][1] == 8 and D.ID_TO_OPPONENT[15][4] == 8 and D.TREE_OPPONENTS[1] == 8,
  'sIdToOpponentId and sTourneyTreeTrainerOpponentIds')
check(D.BP[1] == 1 and D.BP[3] == 2 and D.BP[30] == 15 and F.battlePoints(0, 0, F.DOME) == 1,
  "sBattlePointAwards' dome column, paid")
check(F.BRAIN_AT_BY[1][1] == 4 and F.BRAIN_AT_BY[1][2] == 9 and F.BRAIN_AT_BY[1][3] == 5,
  'Tucker at the 4th and 9th tournament won, then every 5th')
check(F.BRAIN_TRAINER[1] == 'TUCKER' and F.BRAIN_GFX[1] == 71 and data.trainers.TUCKER, "Tucker's record and sprite")
check(D.TUCKER[1][3].species == 'LATIAS' and D.TUCKER[0][1].moves[4] == 'COUNTER', "Tucker's two teams")

-- --------------------------------------------------------------- the stats --
-- every EV flag set: the first loop shifts `bits` to 0 and the second never
-- finds a flag -- no EVs at all
local all = D.stats(data, 'METAGROSS', 50, 31, 63, 0)
local plain = D.stats(data, 'METAGROSS', 50, 31, 0, 0)
check(all.attack == plain.attack and all.hp == plain.hp, 'CalcDomeMonStats: the shifted-out mask gives no EVs')
local big = D.stats(data, 'BLISSEY', 100, 31, 0, 0)
check(big.spdef < 256 and big.hp > 255, 'the five non-HP stats go through a byte; HP does not')
check(D.stats(data, 'SHEDINJA', 50, 0, 0, 0).hp == 1, "Shedinja's 1 HP")

-- ------------------------------------------------------------ the points --
check(D.typePoints(data, 'EARTHQUAKE', 'MAGNETON', 'good') == 8 and D.typePoints(data, 'EARTHQUAKE', 'MAGNETON', 'ai') == 20,
  'x4: 8 points picking, 20 between two AIs')
check(D.typePoints(data, 'EARTHQUAKE', 'FLYGON', 'good') == 2 and D.typePoints(data, 'EARTHQUAKE', 'FLYGON', 'bad') == 0,
  "Levitate: neutral to the 'good' pick, and 0 (not 8) to the 'bad' one")
check(D.typePoints(data, 'TACKLE', 'SHEDINJA', 'good') == 2, 'Wonder Guard never recognised: a neutral hit')
check(D.typePoints(data, 'SWORDS_DANCE', 'PIKACHU', 'good') == 0, 'a move with no power scores nothing')

-- ----------------------------------------------------------- the bracket --
local d = { trainers = {}, mons = {} }
for i = 0, 15 do d.trainers[i] = { trainerId = (i == 0) and D.PLAYER or (100 + i), eliminated = false, at = 0 } end
check(D.opponentOf(d, 0, D.PLAYER) == 8, 'round 1: seed 1 meets seed 9')
d.trainers[8].eliminated = true
check(D.opponentOf(d, 1, D.PLAYER) == 4, 'round 2: the first still standing of 4 / 12')
d.trainers[4].eliminated = true
check(D.opponentOf(d, 1, D.PLAYER) == 12, '...or the other')
d.trainers[12].eliminated = true
check(D.opponentOf(d, 1, D.PLAYER) == 0xFF, 'and nobody, when both are out')

-- the paper match: Tucker always wins
local p = F.parties(data)
local function someMon() for i = 1, #(p and p.mons or {}) do if p.mons[i].species then return i end end end
local m = someMon()
local d2 = { trainers = {}, mons = {}, brainTeam = 1 }
for i = 0, 15 do
  d2.trainers[i] = { trainerId = 200 + i, eliminated = false, at = 0 }
  d2.mons[i] = { m, m, m }
end
d2.trainers[3].trainerId = D.BRAIN
D.decideRound(data, d2, 0)
check(not d2.trainers[3].eliminated and d2.trainers[11].eliminated, 'DecideRoundWinners: the Frontier Brain always wins')
local out = 0
for i = 0, 15 do if d2.trainers[i].eliminated then out = out + 1 end end
check(out == 8, 'a round halves the field')

-- -------------------------------------------------------------- wiring --
check(type(G3.SPECIALS[236]) == 'function', 'special 236 is CallBattleDomeFunction')
local fr = src('src/script/Gen3BattleFrontier.lua')
check(fr:find('Gen3BattleDome").battle', 1, true) and fr:find('F.DOME', 1, true), 'DoSpecialTrainerBattle arm 3')
check(D.WON == 1 and D.LOST == 2 and D.RETIRED == 9, 'DOME_PLAYER_WON_MATCH / _LOST_MATCH / _RETIRED')
check(type(require('src.ui.Gen3DomeScreen').new) == 'function', 'the tourney tree and the opponent card')

if pret then
  local c = src(pret .. '/src/battle_dome.c')
  local body = c:match('sIdToOpponentId%[[^%]]*%]%[[^%]]*%] =%s*(%b{})') or ''
  local k, same = 0, true
  for i, a, b, cc, dd in body:gmatch('%[(%d+)%]%s*=%s*{%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+)}') do
    k = k + 1
    local row = D.ID_TO_OPPONENT[tonumber(i)]
    if not (row[1] == tonumber(a) and row[2] == tonumber(b) and row[3] == tonumber(cc) and row[4] == tonumber(dd)) then same = false end
  end
  check(k == 16 and same, 'sIdToOpponentId matches the source')
  local tree = c:match('sTourneyTreeTrainerOpponentIds%[[^%]]*%] = (%b{})') or ''
  local j, ok = 0, true
  for n in tree:gmatch('%d+') do
    if D.TREE_OPPONENTS[j] ~= tonumber(n) then ok = false end
    j = j + 1
  end
  check(j == 16 and ok, 'sTourneyTreeTrainerOpponentIds matches the source')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
