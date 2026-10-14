-- Run:  python tools/run_lua_check.py tools/gen4_battle_castle_check.lua <platinum cache dir> [pokeplatinum]
--
-- PLATINUM'S BATTLE CASTLE (src/script/Gen4BattleCastle.lua) against
-- pokeplatinum's battle_castle.c, battle_castle_helpers.c and the two apps:
-- the opponents' ranges and Darach, the teams from the Tower's sets, the
-- Castle Points earned after a battle and their cap, every price the apps
-- charge and every refusal, the ranks, the revive between battles, the Battle
-- Points, the streak's record, and the wiring -- every row of the Castle's
-- frontier script lowered, its three scenes, and the lobby's commands.
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
require('src.script.Gen4BattleHall')
require('src.script.Gen4BattleFactory')
local B = require('src.script.Gen4BattleCastle')
local VM = require('src.script.Gen4FrontierVM')
local data = { gen4_battle_tower = load('gen4_battle_tower'), gen4_frontier_scripts = load('gen4_frontier_scripts'),
               pokemon = load('pokemon') or {}, moves = load('moves') or {}, constants = load('constants') or {},
               items = load('items') or {}, text = {} }
-- the field normalization Data:seedDefaults applies to every personal row (as
-- tools/gen4_daycare_check.lua does)
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

-- ---------------------------------------------------------- the opponents --
local inRange, final = true, true
for _ = 1, 300 do
  local id = B.opponentTrainerID(B.DOUBLE, 0, 3)
  if id < 0 or id >= 99 then inRange = false end
  local f7 = B.opponentTrainerID(B.DOUBLE, 0, 6)
  if f7 < 100 or f7 >= 119 then final = false end
end
check(inRange and final, 'round 1: trainers 0-98, the seventh from 100-118')
local late = true
for _ = 1, 200 do
  local id = B.opponentTrainerID(B.SINGLE, 12, 2)
  if id < 200 or id >= 299 then late = false end
end
check(late, 'past the eighth round the last range is kept')
check(B.opponentTrainerID(B.SINGLE, 2, 6) == B.DARACH_SILVER and B.opponentTrainerID(B.SINGLE, 6, 6) == B.DARACH_GOLD,
  'Darach is the 21st and 49th in singles')
check(B.opponentTrainerID(B.DOUBLE, 2, 6) ~= B.DARACH_SILVER, '...and nowhere in doubles')
local trs = data.gen4_battle_tower and data.gen4_battle_tower.trainers or {}
local darach = trs[B.DARACH_SILVER]
check(darach and darach.sets and #darach.sets >= 3 and trs[B.DARACH_GOLD] and #B.pickSets(data, B.DARACH_GOLD, 3) == 3,
  "Darach's two teams are in pl_btdtr")
-- sTrainerClassToObjectID has no row for him (his scenes place object 217
-- themselves, _0F1A), so GET_OPPONENT_OBJECT_ID falls back as the cartridge does
check(require('src.pokemon.Gen4BattleTower').CLASS_GFX[darach and darach.class or -1] == nil,
  "Darach's class is not in sTrainerClassToObjectID")
local ids = {}
B.pickTrainers(B.SINGLE, 0, ids, 14)
local dup = false
for i = 0, 13 do for j = 0, i - 1 do if ids[i] == ids[j] then dup = true end end end
check(not dup and ids[13] ~= nil, 'fourteen trainers a round, none twice')

local sets = data.gen4_battle_tower and data.gen4_battle_tower.sets or {}
local okTeam = true
for _ = 1, 50 do
  local picked = B.pickSets(data, 150, 3)
  if #picked ~= 3 then okTeam = false end
  for a = 1, #picked do
    for b = a + 1, #picked do
      local s, t = sets[picked[a]], sets[picked[b]]
      if s.species == t.species or s.item == t.item then okTeam = false end
    end
  end
end
check(okTeam, "SelectPokemonForTrainer: three of the trainer's sets, no species or item twice")
local e = B.entries(data, { B.pickSets(data, 150, 1)[1] }, 12)[1]
check(e and e.ivs == 12 and e.personality % 25 == sets[e.setID].nature, "the set's nature, the trainer's IVs")

-- ------------------------------------------------------------- the run --
local Pokemon = require('src.pokemon.Pokemon')
local function mon(sp, level)
  local m = Pokemon.new(data, sp, level)
  m.item = 234
  return m
end
local save = { party = { mon(392, 70), mon(395, 40), mon(389, 50), mon(25, 10) }, player = { name = 'LUCAS' } }
local f = B.init(data, save, 0, B.SINGLE, 0, 1, 2)
check(B.cp(save, B.SINGLE) == 10, 'a new challenge starts with 10 CP')
check(#f.team == 3 and f.team[1].level == 50 and f.team[2].level == 40 and not f.team[1].item,
  'the three as copies: no items, above 50 brought down to 50')
check(save.party[1].level == 70 and save.party[1].item == 234, 'the party itself untouched')
check(B.rank(save, B.SINGLE, B.RANK_HEALING) == 1 and B.rank(save, B.SINGLE, B.RANK_SUMMARY) == 1, 'every rank 1')
B.loadRound(data, f, 0)
B.setupOpponentsParty(game, f)
check(f.trainerIDs[0] and #f.opponentParty == 3 and f.opponentParty[1].level == 50, 'the first opponent, three at level 50')

-- the CP after a battle: all three standing at full HP, no status, no PP
-- used: 3*3 + 3*3 + 3 + 8 = 29
check(B.cpFromBattle(f) == 29 and not f.monFainted, 'CalcCPEarnedFromBattle: a clean win is 29')
f.team[1].hp = 0
f.team[2].hp = math.floor(f.team[2].stats.hp / 2)
f.team[3].hp = 1
f.team[3].status = 'psn'
for _, m in ipairs(f.team[3].moves) do m.pp = 0 end
-- standing 2 (6), half-or-more 1 (2), below half 1 (1), no status 1 (1), PP used > 15 (0)
check(B.cpFromBattle(f) == 10 and f.monFainted, '...and a costly one 10, a Pokemon down')
f.levelAdj[1] = B.ADJ_UP
check(B.cpFromBattle(f) == 17, 'a raised opponent pays 7 more')
f.levelAdj[1] = nil
for _, m in ipairs(f.team) do m.hp, m.status = 0, nil; for _, mv in ipairs(m.moves) do mv.pp = 0 end end
f.startingPP = {}
check(B.cpFromBattle(f) == 8, 'everyone down: only the 8 for no PP spent')
B.prepForNextBattle(f)
check(f.team[1].hp == 1 and not f.team[3].status, 'RevivePokemon: the fainted at 1 HP, every status gone')

-- the cap
save.gen4Castle.cp[B.SINGLE] = 9995
B.receiveCP(save, B.SINGLE, 29)
check(B.cp(save, B.SINGLE) == 9999, 'CP is capped at 9999')
save.gen4Castle.cp[B.SINGLE] = 30

-- ------------------------------------------------------------- the apps --
local ok, why = B.heal(f, 1, B.HEAL_PP)
check(not ok and why == 'rank', 'PP restoring needs healing rank 2')
ok = B.heal(f, 1, B.HEAL_HP)
check(ok and f.team[1].hp == f.team[1].stats.hp and B.cp(save, B.SINGLE) == 20, 'RESTORE HP: 10 CP')
ok, why = B.heal(f, 1, B.HEAL_HP)
check(not ok and why == 'nobenefit' and B.cp(save, B.SINGLE) == 20, '...and not again on full HP')
check(#B.rentals(f, 'berries') == 8 and #B.rentals(f, 'items') == 0, 'rental rank 1: eight Berries, no items')
ok = B.rent(f, 2, B.BERRIES[7], B.BERRY_PRICES[7])
check(ok and f.team[2].item == 157 and B.cp(save, B.SINGLE) == 15, 'a Lum Berry rented for 5 CP')
ok, why = B.rankUp(f, B.RANK_RENTALS)
check(not ok and why == 'cp', 'rank up refused short of 100 CP')
save.gen4Castle.cp[B.SINGLE] = 400
check(B.rankUp(f, B.RANK_RENTALS) and B.cp(save, B.SINGLE) == 300 and #B.rentals(f, 'items') == 12,
  'rental rank 2 for 100: twelve items')
check(B.rankUp(f, B.RANK_RENTALS) and B.cp(save, B.SINGLE) == 150 and #B.rentals(f, 'items') == 27
  and #B.rentals(f, 'berries') == 32, 'rank 3 for 150: everything')
ok, why = B.rankUp(f, B.RANK_RENTALS)
check(not ok and why == 'max', 'and no higher')
check(B.reveal(f, 1) and f.identity[1] and B.cp(save, B.SINGLE) == 149, 'CHECK: 1 CP')
local before = f.opponentParty[2].stats.attack
check(B.adjustLevel(f, 2, B.ADJ_UP) and f.opponentParty[2].level == 55 and f.opponentParty[2].stats.attack > before
  and B.cp(save, B.SINGLE) == 148, 'LEVEL +5: 1 CP, level 55')
ok, why = B.adjustLevel(f, 2, B.ADJ_UP)
check(not ok and why == 'highest', "...and it can't go higher")
check(B.adjustLevel(f, 2, B.ADJ_DOWN) and f.opponentParty[2].level == 50 and B.cp(save, B.SINGLE) == 133,
  'LEVEL -5 from +5 (15 CP) is back to 50')
check(B.adjustLevel(f, 2, B.ADJ_DOWN) and f.opponentParty[2].level == 45 and B.cp(save, B.SINGLE) == 118, '...and once more is 45')
check(B.unlockStats(f, 3) and B.cp(save, B.SINGLE) == 116, 'the stats: 2 CP')
ok, why = B.unlockMoves(f, 3)
check(not ok and why == 'rank', 'the moves need information rank 2')
check(B.rankUp(f, B.RANK_SUMMARY) and B.cp(save, B.SINGLE) == 66 and B.unlockMoves(f, 3) and B.cp(save, B.SINGLE) == 61,
  'information rank 2 for 50, then the moves for 5')
B.prepForNextBattle(f)
check(not f.identity[1] and not f.levelAdj[2] and not f.statsUnlocked[3], 'every purchase forgotten by the next battle')

-- ----------------------------------------------------------- the records --
f.currentStreak, f.currentRound = 21, 3
check(B.earnedBP(f) == 20, '20 BP for beating Darach')
f.currentStreak = 14
check(B.earnedBP(f) == 4, 'sBPPerRoundSolo by round')
f.currentStreak, f.currentRound = 7, 0
B.saveOnRound(f)
check(f.currentRound == 1 and save.gen4Castle.streakActive[B.SINGLE] and save.gen4Castle.records[B.SINGLE] == 7,
  'SaveOnCompletingRound: the streak kept and recorded')
local g = B.init(data, save, 0, B.SINGLE, 0, 1, 2)
check(g.currentStreak == 7 and B.rank(save, B.SINGLE, B.RANK_RENTALS) == 3, 'a kept streak keeps its CP and ranks')
B.saveOnLoss(g)
check(B.rank(save, B.SINGLE, B.RANK_RENTALS) == 1 and not save.gen4Castle.streakActive[B.SINGLE],
  'SaveOnLoss: the ranks back to 1, the streak ended')
B.clearStreak(save, B.SINGLE)
check(B.cp(save, B.SINGLE) == 0 and save.gen4Castle.latest[B.SINGLE] == 0, 'ClearActiveStreak')

-- ------------------------------------------------------------------ wiring --
local store = data.gen4_frontier_scripts
local m = store and store.members[0]
check(m and #m.entries == 1, 'fr_script member 0 is the Castle')
local missing, noop = {}, {}
local rows = m and VM.compile(data, 0, VM.entryLabel(data, 0, 0), 200) or {}
for _, row in ipairs(rows) do
  if row[1] ~= 'label' and row[1] ~= 'jump' and type(Commands[row[1]]) ~= 'function' then missing[row[1]] = true end
  if row[1] == 'g4_noop' and tostring(row[2]):find('^frontier ') then noop[row[2]] = true end
end
local ml, nl = {}, {}
for k in pairs(missing) do ml[#ml + 1] = k end
for k in pairs(noop) do nl[#nl + 1] = k end
check(#rows > 100 and #ml == 0 and #nl == 0,
  ("every row of the Castle's script is a command (%s | %s)"):format(table.concat(ml, ' '), table.concat(nl, ' ')))
local Scene = require('src.ui.Gen4FrontierScene')
check(Scene.SCENES[11] and Scene.SCENES[11].member == 0 and Scene.SCENES[12].bank == 200 and Scene.SCENES[13],
  'FRONTIER_SCENE_CASTLE_CORRIDOR, _BATTLE_ROOM and _13')
local art = require('src.import.Gen4FrontierArt').SCENES
check(art.castle_corridor[1] == 26 and art.castle_battle_room[1] == 30 and art.castle_passage[1] == 28,
  'their backdrops out of frontier_bg')
local vm = src('src/script/Gen4ScriptVM.lua')
check(vm:find('L.callbattlecastlelobbyfunction', 1, true) and vm:find('L.getbattlecastleselectedslots', 1, true)
  and vm:find('L.deleteactivebattlecastlestreak', 1, true) and type(Commands.g4_castle_lobby) == 'function',
  "the lobby's commands")
check(type(require('src.ui.Gen4CastleScreen').new) == 'function', 'the self and opponent apps')

-- -------------------------------------------------------------- the source --
if pret then
  local c = src(pret .. '/src/overlay104/battle_castle_helpers.c')
  local names = {}
  local h = io.popen('git -C "' .. pret .. '" show HEAD:generated/frontier_trainers.txt')
  local n = 0
  for line in h:read('*a'):gmatch('[^\n]+') do names[line] = n; n = n + 1 end
  h:close()
  local opp = c:match('sBattleCastleOpponentPools%[%] = (%b{})') or ''
  local k, same = 0, true
  for a, b, cc, d in opp:gmatch('{ (FRONTIER_TRAINER_[%w_]+), (FRONTIER_TRAINER_[%w_]+), (FRONTIER_TRAINER_[%w_]+), (FRONTIER_TRAINER_[%w_]+) }') do
    k = k + 1
    local row = B.OPPONENT_POOLS[k]
    if not (row and row[1] == names[a] and row[2] == names[b] and row[3] == names[cc] and row[4] == names[d]) then same = false end
  end
  check(k == 8 and same, 'sBattleCastleOpponentPools matches the source')
  check(names.FRONTIER_TRAINER_CASTLE_VALET_DARACH_SILVER == B.DARACH_SILVER
    and names.FRONTIER_TRAINER_CASTLE_VALET_DARACH_GOLD == B.DARACH_GOLD, "Darach's ids")
  local app = src(pret .. '/src/applications/frontier/battle_castle/self_app.c')
  local items = {}
  local ih = io.popen('git -C "' .. pret .. '" show HEAD:generated/items.txt')
  local j = 0
  for line in ih:read('*a'):gmatch('[^\n]+') do items[line] = j; j = j + 1 end
  ih:close()
  local function list(name)
    local out = {}
    for w in (app:match(name .. '%[[^%]]*%] = (%b{})') or ''):gmatch('[%w_]+') do
      out[#out + 1] = items[w] or tonumber(w)
    end
    return out
  end
  local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
  end
  check(same(list('sItemsForRent'), B.ITEMS) and same(list('sItemPrices'), B.ITEM_PRICES), 'sItemsForRent / sItemPrices')
  check(same(list('sBerriesForRent'), B.BERRIES) and same(list('sBerryPrices'), B.BERRY_PRICES), 'sBerriesForRent / sBerryPrices')
  check(same(list('sHealingCosts'), B.HEAL_COST), 'sHealingCosts')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
