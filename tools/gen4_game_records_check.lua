-- Run:  python tools/run_lua_check.py tools/gen4_game_records_check.lua <platinum cache dir> [pokeplatinum]
--
-- PLATINUM'S GAME RECORDS AND TRAINER SCORE (src/pokemon/Gen4GameRecords.lua)
-- against game_records.c: the limits, the score events and their cap, the
-- engine's moments that write them (battles, catches, a new species,
-- evolutions, hatches, fish, steps, money and BP, the Hall of Fame, berries,
-- the Tower), the Villa's furniture requirements, the Trainer Card's score,
-- and the wiring. Given a pokeplatinum checkout, the id lists, the high-limit
-- table and the score increments are compared with the source.

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

local R = require('src.pokemon.Gen4GameRecords')
local Commands = require('src.script.Commands')
require('src.script.Gen4Commands')
local data = { gen4_dex = load('gen4_dex') }

-- ------------------------------------------------------------- the limits --
check(R.ID.STEPS == 0 and R.ID.TRAINER_SCORE == 1 and R.ID.TIMES_ENTERED_HALL_OF_FAME == 73
  and R.ID.BATTLE_ARCADE_VICTORIES == 63, 'the record ids')
check(R.limit(R.ID.STEPS) == 999999999 and R.limit(R.ID.CAUGHT_POKEMON) == 999999
  and R.limit(R.ID.TIMES_ENTERED_HALL_OF_FAME) == 9999 and R.limit(R.ID.UNK_071) == 65535,
  'GetRecordLimit: 999,999,999 / 999,999 / 65,535 / 9,999')
local save = {}
R.set(save, R.ID.CAUGHT_POKEMON, 999998)
R.add(save, R.ID.CAUGHT_POKEMON, 5)
check(R.get(save, R.ID.CAUGHT_POKEMON) == 999999, 'capped at the limit')
R.raise(save, R.ID.CAUGHT_POKEMON, 5)
check(R.get(save, R.ID.CAUGHT_POKEMON) == 999999, 'SetAndLimitRecordValue never lowers')

-- -------------------------------------------------------------- the score --
local s2 = {}
R.score(s2, R.EVENT.WON_TRAINER_BATTLE)
R.score(s2, R.EVENT.BADGE_EARNED)
check(R.trainerScore(s2) == 33, 'a trainer win 3, a badge 30')
R.set(s2, R.ID.TRAINER_SCORE, R.TRAINER_SCORE_LIMIT - 1)
R.score(s2, R.EVENT.NATIONAL_DEX_DIPLOMA_RECEIVED)
check(R.trainerScore(s2) == R.TRAINER_SCORE_LIMIT, 'the score stops at 99,999,999')
check(R.SCORE[R.EVENT.UNK_15] == 7 and R.SCORE[R.EVENT.CAUGHT_SPECIES] == 20, 'a hatch 7, a new species 20')

-- ------------------------------------------------------ the battle's end --
local s3 = {}
R.afterBattle(data, s3, { kind = 'wild' }, 'win')
R.afterBattle(data, s3, { kind = 'trainer' }, 'win')
R.afterBattle(data, s3, { kind = 'trainer' }, 'lose')
check(R.get(s3, R.ID.WILD_BATTLES_FOUGHT) == 1 and R.get(s3, R.ID.TRAINER_BATTLES_FOUGHT) == 2
  and R.trainerScore(s3) == 5, 'battles fought; a wild win 2, a trainer win 3, a loss nothing')
local sinnoh = data.gen4_dex and data.gen4_dex.orders and data.gen4_dex.orders.sinnoh
local first = sinnoh and tonumber(sinnoh[2])
local s4 = {}
R.afterBattle(data, s4, { kind = 'wild', enemy = { mon = { species = first } } }, 'caught')
check(R.trainerScore(s4) == 2 and R.get(s4, R.ID.CAUGHT_POKEMON) == 1, 'a Sinnoh catch: 2 points, one caught')
local s5 = {}
R.afterBattle(data, s5, { kind = 'wild', enemy = { mon = { species = 151 } } }, 'caught')
check(R.trainerScore(s5) == 3, 'Mew is not in the Sinnoh dex: 3')
local s6 = {}
R.afterBattle(data, s6, { kind = 'wild', battleTower = true }, 'win')
R.afterBattle(data, s6, { kind = 'trainer', linkBattle = true }, 'win')
check(R.trainerScore(s6) == 0 and R.get(s6, R.ID.WILD_BATTLES_FOUGHT) == 0, 'never for a Frontier or link battle')
local s7 = {}
R.afterBattle(data, s7, { kind = 'wild', hooked = true }, 'run')
check(R.get(s7, R.ID.CAUGHT_FISH) == 1, 'a fish hooked counts, caught or not')
R.evolved(s7); R.hatched(s7)
check(R.get(s7, R.ID.POKEMON_EVOLVED) == 1 and R.get(s7, R.ID.EGGS_HATCHED) == 1 and R.trainerScore(s7) == 27,
  'an evolution (20, new species or not) and a hatch (7)')

-- -------------------------------------------------------------- the Villa --
local v = {}
check(R.villa(v, 1) and not R.villa(v, 13) and not R.villa(v, 15), 'the TABLE needs nothing; the BUST and PIANO do')
for _, id in ipairs({ R.ID.BATTLE_TOWER_VICTORIES, R.ID.BATTLE_FACTORY_VICTORIES, R.ID.BATTLE_CASTLE_VICTORIES,
                      R.ID.BATTLE_HALL_VICTORIES }) do R.add(v, id, 1) end
check(not R.villa(v, 13), 'the BUST: a win in all five facilities')
R.add(v, R.ID.BATTLE_ARCADE_VICTORIES, 1)
check(R.villa(v, 13), '...all five')
check(not R.villa(v, 14, function() return 1 end) and R.villa(v, 14, function(x) return x == 0x4052 and 2 or 0 end),
  'the SILVER BUST: any facility\'s silver print')
R.set(v, R.ID.STEPS, 299999)
check(not R.villa(v, 20), 'the CHANDELIER: 300,000 steps')
R.increment(v, R.ID.STEPS)
check(R.villa(v, 20), '...300,000')

-- ---------------------------------------------------------------- wiring --
local vm = src('src/script/Gen4ScriptVM.lua')
check(vm:find('L.checkmetfurniturerequirements', 1, true) and type(Commands.g4_villa_requirements) == 'function',
  'checkmetfurniturerequirements')
check(vm:find('"g4_trainer_score"', 1, true) and type(Commands.g4_trainer_score) == 'function', 'incrementtrainerscore')
check(src('src/world/OverworldController.lua'):find('R.afterBattle(Game.data, Game.save, battle, result)', 1, true)
  and src('src/world/OverworldController.lua'):find('Gen4GameRecords").increment(Game.save, 0)', 1, true),
  'the battle end and the step')
check(src('src/battle/BattleState.lua'):find('newSpecies(game.save)', 1, true), 'a new Pokedex page')
check(src('src/pokemon/Evolution.lua'):find('evolved(game.save)', 1, true), 'an evolution')
check(src('src/pokemon/Gen4BattleTower.lua'):find('BATTLE_POINTS_RECEIVED', 1, true), 'BP received and spent')
check(src('src/ui/Gen4TrainerCard.lua'):find('trainerScore(save)', 1, true), "the Trainer Card's SCORE")
check(src('src/script/Gen4FrontierScrCmds.lua'):find('R.increment(ctx.save, id)', 1, true), "the frontier's IncrementRecordValue")

if pret then
  local function lines(p)
    local h = io.popen('git -C "' .. pret .. '" show HEAD:' .. p)
    local t = {}
    for l in h:read('*a'):gmatch('[^\n]+') do t[#t + 1] = l end
    h:close()
    return t
  end
  local recs, evs = lines('generated/game_records.txt'), lines('generated/trainer_score_events.txt')
  -- each list ends with its MAX_ sentinel
  local ok = #recs == 149 and recs[149] == 'MAX_RECORDS'
  for i = 1, 148 do if R.ID[recs[i]:sub(8)] ~= i - 1 then ok = false end end
  check(ok, 'generated/game_records.txt matches')
  local c = src(pret .. '/src/game_records.c')
  local same = true
  for n in c:gmatch('%[(RECORD_[%w_]+)%] = TRUE') do if not R.HIGH[R.ID[n:sub(8)]] then same = false end end
  for n, inc in c:gmatch('%[(TRAINER_SCORE_EVENT_[%w_]+)%] = (%d+)') do
    if R.SCORE[R.EVENT[n:sub(21)]] ~= tonumber(inc) then same = false end
  end
  check(same and #evs == 52, 'sUsesHighLimit and sTrainerScoreIncrements match')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
