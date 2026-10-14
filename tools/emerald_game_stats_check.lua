-- Run:  python tools/run_lua_check.py tools/emerald_game_stats_check.lua <emerald cache dir> [pokeemerald]
--
-- EMERALD'S GAME STATS (src/pokemon/Gen3GameStats.lua) against overworld.c,
-- battle_setup.c and gym_leader_rematch.c: the ids, the 0xFFFFFF cap, the
-- battle counts and the Gym Leader rematch they roll every 60th wild and
-- 20th trainer battle (the Frontier's every 20th of its own count), which
-- leader is armed and at what step, the capture, the Hall of Fame and its
-- first play time, and the wiring of every engine-side counter.

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

local S = require('src.pokemon.Gen3GameStats')
local G3 = require('src.script.Gen3Commands')
local MC = require('src.script.MatchCall')
local data = { constants = load('constants') or {}, trainers = load('trainers') or {} }

-- ------------------------------------------------------------ the counters --
local save = { flags = {} }
S.set(save, S.STEPS, S.MAX - 1)
S.increment(save, S.STEPS); S.increment(save, S.STEPS)
check(S.get(save, S.STEPS) == S.MAX, 'IncrementGameStat stops at 0xFFFFFF')
check(S.increment(save, 60) == 0 and S.get(save, 52) == 0, 'nothing past the 52 used')

-- ------------------------------------------------------- the battle counts --
local s2 = { flags = {} }
S.battleBegun(data, s2, { kind = 'wild', hooked = true })
S.battleBegun(data, s2, { kind = 'trainer' })
S.afterBattle(s2, { kind = 'wild' }, 'caught')
check(S.get(s2, S.TOTAL_BATTLES) == 2 and S.get(s2, S.WILD_BATTLES) == 1 and S.get(s2, S.TRAINER_BATTLES) == 1
  and S.get(s2, S.FISHING_ENCOUNTERS) == 1 and S.get(s2, S.POKEMON_CAPTURES) == 1,
  'all battles, wild, trainer, a fish, a capture')
S.battleBegun(data, s2, { kind = 'trainer', gen3Frontier = true })
S.battleBegun(data, s2, { kind = 'trainer', linkBattle = true })
check(S.get(s2, S.TOTAL_BATTLES) == 2 and s2.gen3FrontierBattles == 1, 'a Frontier battle counts its own; a link battle nothing')

-- ------------------------------------------------- the Gym Leader rematch --
local rows = MC.rematchRows(data)
check(#rows >= 73 and rows[66] and rows[73], 'gRematchTable reaches Juan (72)')
local function cleared()
  local s = { flags = {}, rematches = {} }
  s.flags[G3.flagKey(S.FLAG_GAME_CLEAR)] = true
  -- every leader's first fight won
  for _, i in ipairs(S.LEADERS_AFTER) do s.flags[G3.flagKey(0x500 + rows[i + 1].trainers[1])] = true end
  return s
end
local s3 = cleared()
check(S.rematchIndex(data, s3, 65) == 1, "GetRematchIndex: Roxanne's first fought, her second next (1)")
local always = function(a, b) return a end            -- 0: under 31 and the first of the pool
local pick = S.updateGymLeaderRematch(data, s3, always)
check(pick == 65 and s3.rematches[65] == 1, 'before New Mauville: one leader armed, at step 1')
check(not s3.rematches[67], "Wattson is not in the list before New Mauville")
local s4 = cleared()
s4.flags[G3.flagKey(S.FLAG_WATTSON_REMATCH)] = true
for _ = 1, 8 do S.updateGymLeaderRematch(data, s4, always) end
check(s4.rematches[67] == 1, 'after it, Wattson too')
local s5 = cleared()
check(S.updateGymLeaderRematch(data, s5, function() return 31 end) == nil, '31 in 100 is too many (the roll is <= 30)')
local s6 = { flags = {}, rematches = {} }
check(S.updateGymLeaderRematch(data, s6, always) == nil, 'nothing before the game is cleared')
-- before New Mauville, a leader already a step up is not armed again (max 1)
local s7 = cleared()
for _, i in ipairs(S.LEADERS_BEFORE) do s7.flags[G3.flagKey(0x500 + rows[i + 1].trainers[2])] = true end
check(S.updateGymLeaderRematch(data, s7, always) == nil, 'before New Mauville, nobody past their first rematch')
-- the 60th wild battle rolls it
local s8 = cleared()
S.set(s8, S.WILD_BATTLES, 59)
S.battleBegun(data, s8, { kind = 'wild' }, always)
check(s8.rematches[65] == 1, 'TryUpdateGymLeaderRematchFromWild on the 60th')
local s9 = cleared()
S.set(s9, S.TRAINER_BATTLES, 18)
S.battleBegun(data, s9, { kind = 'trainer' }, always)
check(next(s9.rematches) == nil, '...and not on the 19th trainer battle')

-- --------------------------------------------------------- the Hall of Fame --
local s10 = { flags = {}, playTime = 3 * 3600 + 25 * 60 + 9 }
package.loaded['src.core.SaveData'] = { playSeconds = function(sv) return sv.playTime end }
S.enteredHallOfFame(s10)
S.enteredHallOfFame(s10)
check(S.get(s10, S.ENTERED_HOF) == 2 and S.get(s10, S.FIRST_HOF_PLAY_TIME) == 3 * 65536 + 25 * 256 + 9,
  'entered twice; the first time kept as hours << 16 | minutes << 8 | seconds')

-- ------------------------------------------------------------------ wiring --
local ow = src('src/world/OverworldController.lua')
check(ow:find('S.battleBegun(Game.data, Game.save, battle)', 1, true) and ow:find('GAME_STAT_STEPS', 1, true)
  and ow:find('GAME_STAT_HATCHED_EGGS', 1, true) and ow:find('GAME_STAT_JUMPED_DOWN_LEDGES', 1, true),
  'the battle, the step, the hatch, the ledge')
check(src('src/pokemon/Evolution.lua'):find('GAME_STAT_EVOLVED_POKEMON', 1, true), 'an evolution')
check(src('src/ui/Gen3ShopMenu.lua'):find('GAME_STAT_SHOPPED', 1, true), 'a purchase')
local sm = src('src/ui/Gen3StartMenu.lua')
check(sm:find('GAME_STAT_CHECKED_POKEDEX', 1, true) and sm:find('GAME_STAT_SAVED_GAME', 1, true), 'the Pokedex and a save')
check(src('src/ui/Gen3HallOfFame.lua'):find('enteredHallOfFame', 1, true), 'the Hall of Fame')
check(src('src/world/Gen3PartyFieldMoves.lua'):find('"g3_game_stat",18', 1, true), 'Cut and Rock Smash')
local fr = src('src/script/Gen3BattleFrontier.lua') .. src('src/script/Gen3BattleDome.lua') .. src('src/script/Gen3BattlePike.lua')
  .. src('src/script/Gen3BattleFactory.lua') .. src('src/script/Gen3BattlePyramid.lua')
local n = 0
for _ in fr:gmatch('frontier = true') do n = n + 1 end
check(n == 5, "every Frontier battle marked (the tower's, the Dome's, the Pike's, the Factory's, the Pyramid's)")

if pret then
  local h = src(pret .. '/include/constants/game_stat.h')
  local same, k = true, 0
  for name, v in h:gmatch('#define GAME_STAT_([%w_]+)%s+(%d+)') do
    k = k + 1
    if S[name] ~= nil and S[name] ~= tonumber(v) then same = false end
  end
  check(k >= 52 and same, 'game_stat.h matches')
  local r = src(pret .. '/include/constants/rematches.h')
  local body = r:match('enum%s*(%b{})') or ''
  local idx, at = 0, {}
  for name in body:gmatch('(REMATCH_[%w_]+)') do at[name] = idx; idx = idx + 1 end
  check(at.REMATCH_ROXANNE == 65 and at.REMATCH_JUAN == 72 and at.REMATCH_WATTSON == 67, 'the leaders\' rematch indices')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
