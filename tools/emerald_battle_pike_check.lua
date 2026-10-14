-- Run:  python tools/run_lua_check.py tools/emerald_battle_pike_check.lua <emerald cache dir>
--
-- THE BATTLE PIKE (src/script/Gen3BattlePike.lua) against pokeemerald's
-- battle_pike.c and wild_encounter.c: which rooms the doors can hide, the
-- hint and its group, the status rooms, the heals, Lucy's turn, the wild
-- room's Pokemon, the talkers' words out of the ROM, the Battle Points, and
-- the wiring into the specials, the battles and the step encounter.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
require('src.core.GameVersion').set('emerald')
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/emerald/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local G3 = require('src.script.Gen3Commands')
local F = require('src.script.Gen3BattleFrontier')
local P = require('src.script.Gen3BattlePike')
local data = { moves = load('moves') or {}, pokemon = load('pokemon') or {}, items = {},
               gen3_frontier_speech = load('gen3_frontier_speech') }

-- ---------------------------------------------------------------- tables --
check(P.HINTS[P.SINGLE] == P.HINT_PEOPLE and P.HINTS[P.HEAL_FULL] == P.HINT_PEOPLE
  and P.HINTS[P.NPC] == P.HINT_WHISPERING and P.HINTS[P.DOUBLE] == P.HINT_WHISPERING
  and P.HINTS[P.STATUS] == P.HINT_NOSTALGIA and P.HINTS[P.HEAL_PART] == P.HINT_NOSTALGIA
  and P.HINTS[P.WILD] == P.HINT_POKEMON and P.HINTS[P.HARD] == P.HINT_POKEMON
  and P.HINTS[P.BRAIN] == P.HINT_BRAIN, 'sRoomTypeHints: four groups of two, and the Queen')
check(#P.NPCS == 25, 'sNPCTable: 25 talkers')
check(P.BP[1] == 1 and P.BP[3] == 2 and P.BP[6] == 4 and P.BP[9] == 8 and P.BP[13] == 10 and P.BP[30] == 15,
  "sBattlePointAwards' pike column")
check(F.battlePoints(0, 0, F.PIKE) == 1 and F.battlePoints(9, 0, F.PIKE) == 8, 'the pike column is the one paid')
check(F.BRAIN_AT_BY[5][1] == 28 and F.BRAIN_AT_BY[5][2] == 140 and F.BRAIN_AT_BY[5][3] == 56,
  'Lucy at 28, 140 and every 56 after')
check(F.LUCY[0][2].species == 'SHUCKLE' and F.LUCY[1][3].moves[1] == 'DRAGON_DANCE', "Lucy's two teams")
local speech = data.gen3_frontier_speech
check(speech and speech.pikeNpc and speech.pikeNpc[0] and speech.pikeNpc[41],
  "sNPCSpeeches: 42 rows out of the ROM (tools/gen3_frontier_speech_extract.lua)")
check(speech and speech.pikeNpc[0][6] and speech.pikeNpc[0][6] ~= 0xFFFF,
  'row 0 ends on a move ("...I need a HELPING HAND")')

-- --------------------------------------------------------- a challenge --
local function mon(species, hp, max, status)
  return { species = species, level = 50, hp = hp, stats = { hp = max }, status = status,
           moves = { { id = 'TACKLE', pp = 35 } } }
end
local function newCtx(party)
  local save = { vars = {}, flags = {}, party = party, player = {} }
  local ctx = { save = save, game = { data = data, stringBuffers = {} } }
  G3.setVar(save, F.VAR_FACILITY, P.FACILITY)
  local s = F.state(save)
  s.data = s.data or {}
  s.data[1], s.data[2] = 0, 3
  return ctx, s
end
local ctx, s = newCtx({ mon('METAGROSS', 187, 187), mon('SALAMENCE', 202, 202), mon('TYRANITAR', 207, 207) })
local _, pk = P.state(ctx.save)

-- the hinted door is the hinted room; the others never share its group
pk.hintIndex, pk.hintType = 1, P.HEAL_FULL
G3.setVar(ctx.save, P.VAR_ROOM, 1)
check(P.nextRoom(ctx) == P.HEAL_FULL, 'GetNextRoomType: the door she spoke of is what she said')
G3.setVar(ctx.save, P.VAR_ROOM, 0)
local peopleSeen = false
for _ = 1, 300 do
  local r = P.nextRoom(ctx)
  if r == P.SINGLE or r == P.HEAL_FULL then peopleSeen = true end
end
check(not peopleSeen, "...and the other doors are never in her hint's group (people)")
pk.healDisabled = true
pk.hintType = P.NPC
local healSeen = false
for _ = 1, 300 do
  local r = P.nextRoom(ctx)
  if r == P.HEAL_FULL or r == P.HEAL_PART then healSeen = true end
end
check(not healSeen, 'no heal room while healing is switched off (a full-health team)')
pk.healDisabled = nil

-- the double room needs two standing; the status room somebody to hit
local ctx2 = newCtx({ mon('METAGROSS', 0, 187), mon('SALAMENCE', 0, 202), mon('TYRANITAR', 207, 207) })
local _, pk2 = P.state(ctx2.save)
pk2.hintType = P.NPC
local doubleSeen = false
for _ = 1, 300 do if P.nextRoom(ctx2) == P.DOUBLE then doubleSeen = true end end
check(not doubleSeen, 'two down: no double battle room')

-- the status room: count by room, and the types it cannot touch
local ctx3, s3 = newCtx({ mon('METAGROSS', 187, 187), mon('SALAMENCE', 202, 202), mon('TYRANITAR', 207, 207) })
local _, pk3 = P.state(ctx3.save)
s3.data[2] = 3
local hit, steelToxic = 0, false
for _ = 1, 200 do
  for _, m in ipairs(ctx3.save.party) do m.status = nil end
  P.inflictStatus(ctx3, pk3)
  local n = 0
  for _, m in ipairs(ctx3.save.party) do if m.status then n = n + 1 end end
  hit = math.max(hit, n)
  if ctx3.save.party[1].status == 'PSN' then steelToxic = true end
end
check(hit == 1, 'rooms 1-4: one Pokemon takes the status')
check(not steelToxic, 'Metagross (Steel) is never badly poisoned')
s3.data[2] = 12
for _ = 1, 50 do
  for _, m in ipairs(ctx3.save.party) do m.status = nil end
  P.inflictStatus(ctx3, pk3)
end
check(pk3.statusMon == P.STATUSMON_KIRLIA or pk3.statusMon == P.STATUSMON_DUSCLOPS, 'a Kirlia or a Dusclops does it')
for _, m in ipairs(ctx3.save.party) do m.status = nil end
pk3.statusFlag = nil
check(P.STATUS_OF[P.ST_SLEEP] == 'SLP' and P.STATUS_OF[P.ST_FREEZE] == 'FRZ', "the port's own status codes")

-- the heals: only those that need it, at most n
local ctx4 = newCtx({ mon('METAGROSS', 10, 187), mon('SALAMENCE', 202, 202), mon('TYRANITAR', 207, 207, 'PAR') })
P.tryHeal(ctx4, 1)
local healed = (ctx4.save.party[1].hp == 187 and 1 or 0) + (ctx4.save.party[3].status == nil and 1 or 0)
check(healed == 1 and ctx4.save.party[2].hp == 202, 'TryHealMons(1): one of the two that needed it')
P.tryHeal(ctx4, 2)
check(ctx4.save.party[1].hp == 187 and ctx4.save.party[3].status == nil, '...and the other on the next')

-- Lucy's turn
local ctx5, s5 = newCtx({ mon('METAGROSS', 187, 187) })
P.setStreak(s5, 26)
check(P.queenFight(ctx5, 1) == 1, 'streak 26, next room 27: the Pike Queen (silver)')
check(P.setHint(ctx5) == 1 and select(2, P.state(ctx5.save)).hintType == P.BRAIN, 'and the hint is the dreadful presence')
P.setStreak(s5, 27)
check(P.queenFight(ctx5, 0) == 1, '...and in that room, GetCurrentRoomPikeQueenFightType says so')

-- the wild room
local tbl = P.wildTable(ctx.save)
check(tbl.grass.rate == 10 and #tbl.grass.slots == 12 and tbl.grass.slots[3].species == 'DUSCLOPS',
  'the first tier: Seviper, Milotic, and Dusclops')
P.setStreak(s, 41 * 14)
check(P.wildTable(ctx.save).grass.slots[3].species == 'BRELOOM', 'past 40 challenges: Breloom')
P.setStreak(s, 0)
local w = P.wildFor(data, ctx.save, { species = 'DUSCLOPS' })
check(w and w.level == 45 and w.pikeMoves[4] == 'SHADOW_PUNCH', 'level 50: 50 - 5, and its four moves')
s.data[1] = 1
ctx.save.party[1].level = 70
w = P.wildFor(data, ctx.save, { species = 'SEVIPER' })
check(w and w.level == 66 and w.pikeMoves[3] == 'POISON_FANG', 'open level: the party best - 4, open moves')
s.data[1] = 0

-- ------------------------------------------------------------ the wiring --
local fr = src('src/script/Gen3BattleFrontier.lua')
check(fr:find('require("src.script.Gen3BattlePike").install()', 1, true), 'special 242 is CallBattlePikeFunction')
check(fr:find('if arg == 9 then require("src.script.Gen3BattlePike").doubleBattle(ctx) return end', 1, true),
  'SPECIAL_BATTLE_PIKE_DOUBLE: two trainers')
check(fr:find('local per = (fac == F.PIKE) and 14 or', 1, true), 'Battle Points by challenges of fourteen rooms')
local ow = src('src/world/OverworldController.lua')
check(ow:find('if pikeWild then encDef = Pike.wildTable(Game.save) end', 1, true)
  and ow:find('enc = Pike.wildFor(Game.data, Game.save, enc)', 1, true), 'the wild room rolls its own table')
check(ow:find('Pike.afterWild(Game.save, result)', 1, true), "...and records the outcome its ON_RESUME reads")
check(src('src/battle/BattleState.lua'):find("Items can't be used now.", 1, true), "the Frontier's bag stays shut")

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
