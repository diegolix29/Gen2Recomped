-- Run:  python tools/run_lua_check.py tools/gen4_battle_hall_check.lua <platinum cache dir> [pokeplatinum]
--
-- PLATINUM'S BATTLE HALL (src/script/Gen4BattleHall.lua, src/ui/Gen4HallTypeScreen.lua)
-- against pokeplatinum's battle_hall.c, battle_hall_helpers.c and the type
-- grid app: the tables (generated from the source), the ROM's pl_bsdpm sets
-- lined up against them, the opponents' level, the trainer and Pokemon
-- picks, Argenta, the doubles foe, and which cells the grid lets you choose.
--
-- Given a pokeplatinum checkout, the generated tables are made again from it
-- and compared with the committed module.

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

require('src.script.Commands')
require('src.script.Gen4Commands')
require('src.script.Gen4FrontierScrCmds')
local H = require('src.script.Gen4BattleHall')
local T = require('src.import.Gen4BattleHallTables')
local data = { gen4_battle_tower = load('gen4_battle_tower') }
local rec = data.gen4_battle_tower

-- --------------------------------------------------------------- tables --
check(T.COUNT == 477 and T.GROUP[1] == 1 and T.GROUP[2] == 155 and T.GROUP[3] == 271 and T.GROUP[4] == 376,
  'sBattleHallPotentialOpponents: 477, in four groups (GROUP_n_START)')
check(T.SPECIES[0] == 1 and T.MON_TYPES[0][1] == 12 and T.MON_TYPES[0][2] == 3,
  'the list opens on BULBASAUR, GRASS / POISON')
check(T.IVS[0] == 8 and T.IVS[9] == 26, 'sIVsPerTypeRank: 8 up to 26')
check(T.GRID[0] == 0 and T.GRID[1] == 10 and T.GRID[16] == 8 and T.GRID[17] == 0xFE and T.GRID[19] == 9,
  'sBattleHallAppGridOrder: NORMAL, FIRE ... STEEL, the two summary cells, then ???')
check(T.CLASSES_BY_RANK[0][0] == 2 and T.CLASSES_BY_TYPE[9][0] == T.CLASSES_BY_TYPE[9][3],
  'the trainer classes by rank and by type (Flying: Bird Keepers all four)')

-- the ROM's sets against the source's list
check(rec and rec.hallSets, 'the cache has gen4_battle_tower.hallSets (tools/gen4_battle_tower_extract.lua)')
local n, same = 0, 0
for k, set in pairs(rec and rec.hallSets or {}) do
  if k > 0 then
    n = n + 1
    if set.species == T.SPECIES[k - 1] then same = same + 1 end
  end
end
check(n == T.COUNT and same == n, ('pl_bsdpm member k is list position k - 1 (%d of %d agree)'):format(same, n))

-- --------------------------------------------------------- the level --
local function hall(level, rank, challenge)
  local save = { party = { { species = 445, level = level }, { species = 448, level = level } }, player = {} }
  local h = H.init(save, 0, challenge or H.SINGLE, 0, 1)
  h.selectedIdx, h.selectedType = 0, 0
  h.ranks[0] = rank or 0
  h.levelSqrt = H.levelSqrt(H.highestLevel(h))
  return h, save
end
check(H.opponentsLevel((hall(50, 0))) == 29, 'level 50, rank 1, nothing beaten yet: 29 (50 - 3 x root 50, rounded up)')
local h9 = hall(50, 9)
check(H.opponentsLevel(h9) == 42, 'level 50, rank 10: 42')
h9.ranks[4] = 3
h9.ranks[11] = 1
check(H.opponentsLevel(h9) == 43, 'two other types beaten: + half a level each, rounded up')
check(H.opponentsLevel((hall(8, 0))) == 1, 'under level 10 the sum goes negative: (int) truncates, so level 1')
check(H.opponentsLevel((hall(100, 9))) == 88, 'level 100, rank 10: 88')

-- ------------------------------------------------------- the trainers --
local ids = {}
local okClass, okFresh = true, true
for battle = 0, 9 do
  H.pickClasses(4, 1, 3, battle, ids)
  local cls = ids[battle * 2]
  H.pickTrainers(data, H.SINGLE, 1, 0, 3, battle, ids)
  local id = ids[battle * 2]
  if not (rec.trainers[id] and rec.trainers[id].class == cls) then
    -- a whole lap without one swaps the class; the trainer still has the class it ended on
    if not rec.trainers[id] then okClass = false end
  end
  for b = 0, battle - 1 do if ids[b * 2] == id then okFresh = false end end
end
check(okClass and okFresh, 'a round of ten: each a frontier trainer of the class drawn, none met twice')
local arg50 = {}
H.pickTrainers(data, H.SINGLE, 1, 4, 0, 9, arg50)
local arg170 = {}
H.pickTrainers(data, H.SINGLE, 1, 16, 0, 9, arg170)
local dbl = {}
H.pickClasses(0, 2, 0, 9, dbl)
H.pickTrainers(data, H.DOUBLE, 2, 4, 0, 9, dbl)
check(arg50[18] == H.ARGENTA_SILVER and arg170[18] == H.ARGENTA_GOLD and dbl[18] ~= H.ARGENTA_SILVER,
  'Argenta at the 50th and 170th -- in singles only')

-- ------------------------------------------------------- the Pokemon --
local function typesOf(k) return T.MON_TYPES[k - 1] end
local mons, typed, mine, fresh, inRange = {}, true, true, true, true
for battle = 0, 9 do
  local k = H.pickMon(10, 0, battle, 6, mons, H.NEXT_NORMAL)   -- FIRE at rank 1, as a Charizard
  local t = typesOf(k)
  if not (t[1] == 10 or t[2] == 10) then typed = false end
  if T.SPECIES[k - 1] == 6 then mine = false end
  if k - 1 < T.GROUP[1] - 1 or k - 1 > T.GROUP[2] - 1 then inRange = false end
  -- group 1 has eight FIRE-types: until they are spent none comes twice, and
  -- after that (the lap found nothing new) just never the one before
  if battle < 8 then
    for b = 0, battle - 1 do if mons[b * 2] == k then fresh = false end end
  elseif mons[(battle - 1) * 2] == k then
    fresh = false
  end
end
check(typed and mine and inRange and fresh,
  'a FIRE round at rank 1: FIRE-types from group 1, never yours, fresh until the eight are spent')
local hi = {}
local k = H.pickMon(16, 9, 0, 445, hi, H.NEXT_NORMAL)
check(k - 1 >= T.GROUP[3] - 1, 'rank 10 draws from groups 3 and 4')
local gold = {}
k = H.pickMon(0, 5, 9, 445, gold, H.NEXT_GOLD)
check(k - 1 >= T.GROUP[4] - 1 and T.SPECIES[k - 1] ~= 445, "Argenta (gold): group 4, any type, not yours")

-- ------------------------------------------------- the opponent's side --
local hd = hall(50, 2, H.DOUBLE)
hd.trainerIDs[0], hd.monIndices[0] = 10, 5
hd.opponentsLevel = H.opponentsLevel(hd)
local party, level = H.opponentParty(hd, data)
check(party and #party == 2 and party[1].setID == party[2].setID
  and math.abs(party[1].personality - party[2].personality) == 250025
  and party[1].personality % 25 == party[2].personality % 25 and party[1].ivs == T.IVS[2],
  "doubles: the same set twice, the personality 25 x 10001 apart (same nature), the rank's IVs")
check(level == hd.opponentsLevel, "at BattleHall_CalcOpponentsLevel's level")
local hm = hall(57, 2)
hm.trainerIDs[0], hm.monIndices[0] = H.ARGENTA_SILVER, 300
local mp, ml = H.opponentParty(hm, data)
check(mp and #mp == 1 and mp[1].ivs == 31 and ml == 57, "Argenta's Pokemon: 31 IVs, at your level")

-- -------------------------------------------------------- the grid --
local Screen = require('src.ui.Gen4HallTypeScreen')
local game = { data = { text = {} }, stack = { push = function() end, pop = function() end } }
local hs = hall(50, 0)
local scr = Screen.new(game, { hall = hs })
check(scr:selectable(0) and scr:selectable(1) and scr:selectable(16), 'a type below rank 10 is a choice')
-- the ranks are kept by grid cell (GetCursorPos), not by TYPE_*: cell 1 is FIRE
hs.ranks[1] = 10
check(not scr:selectable(1) and scr:selectable(2), 'a type at rank 10 cannot be chosen')
check(not scr:selectable(Screen.MYSTERY_CELL), '??? cannot be chosen before Argenta is on her way')
hs.streak = 49
check(scr:nextIsMatron(), "the app's streak is the challenge's + 1: 49 wins and the next is hers")
scr.matron = true
check(scr:selectable(Screen.MYSTERY_CELL) and not scr:selectable(0), 'then ??? is the only choice')

-- ------------------------------------------------------- the lobby --
local Lobby = require('src.script.Gen4BattleHallLobby')
local function party(...)
  local out = {}
  for i, v in ipairs({ ... }) do out[i] = { species = v[1], level = v[2] } end
  return { party = out, player = {} }
end
check(Lobby.eligible(party({ 445, 30 }), 1) and not Lobby.eligible(party({ 445, 29 }), 1),
  'CheckPartyIsBattleHallEligible: level 30 and up')
check(not Lobby.eligible(party({ 150, 70 }), 1), '... and off the frontier banlist')
check(Lobby.eligible(party({ 445, 50 }, { 445, 40 }), 2) and not Lobby.eligible(party({ 445, 50 }, { 448, 50 }), 2),
  'doubles: two of the SAME species')
local ls = party({ 445, 50 })
local lr = H.record(ls)
lr.latest, lr.latestSpecies = { [0] = 37 }, { [0] = 445 }
check(Lobby.updateWinRecord(ls, 0) and Lobby.totalSingles(ls) == 37, "a streak's end writes the species' best")
lr.latest[0] = 12
check(Lobby.updateWinRecord(ls, 0) and Lobby.records(ls, 0)[445] == 37,
  'a shorter one leaves the best (the cartridge still answers "changed": the two differ)')
lr.latestSpecies[1], lr.latest[1] = 448, 5
Lobby.updateWinRecord(ls, 1)
check(Lobby.speciesWithRecords(ls) == 2 and Lobby.totalSingles(ls) == 37, 'species counted over every challenge; the total is singles only')
local k = Lobby.recordKeeper(ls, 0)
check(k.earned == 1 + 3 and k.next == 2 and k.response == 1 and k.passed == 30 and k.goal == 50,
  'the record keeper: 10 and 30 passed (1 + 3 BP), 50 next')
k = Lobby.recordKeeper(ls, 2)
check(k.earned == 0 and k.response == 2, 'asked again: nothing new, the next goal')
lr.streakActive[0] = true
Lobby.clearStreak(ls, 0)
check(not lr.streakActive[0] and lr.latest[0] == 0, 'BattleHall_ClearActiveStreak')

local PMsrc = src('src/ui/Gen4PartyMenu.lua')
check(PMsrc:find('sel.minLevel', 1, true) and PMsrc:find('sel.sameKind', 1, true),
  'the party menu: a level floor and "the same kind of Pokemon"')
local vm = src('src/script/Gen4ScriptVM.lua')
local lowered = true
for _, c in ipairs({ 'callbattlehalllobbyfunction', 'getbattlehallselectedslots', 'deleteactivebattlehallstreak',
  'checkifbattlehallstreakis50', 'getnumspecieswithbattlehallrecords', 'getbattlehalltotalsinglesrecord',
  'getbattlehallrecordkeeperstats', 'checkbattlehallpartnerusesdifferentspecies' }) do
  if not vm:find('L.' .. c .. ' = ', 1, true) then lowered = false; print('  not lowered: ' .. c) end
end
check(lowered, "every Battle Hall lobby command is lowered")

-- ------------------------------------------------------------- wiring --
local hsrc = src('src/script/Gen4BattleHall.lua')
check(hsrc:find('Gen4HallTypeScreen', 1, true) and hsrc:find('H.setupNext(h, ctx.game.data)', 1, true),
  'OpenBattleHallApp opens the grid; SetupNextOpponent picks')
check(not hsrc:find('not ported yet', 1, true), 'the Hall no longer leaves at the app')

-- ---------------------------------------------------- the source --
if pret then
  local tmp = os.tmpname()
  local ok = os.execute(('python tools/gen4_battle_hall_tables_gen.py "%s" "%s" > NUL 2>&1'):format(pret, tmp))
  local fresh = src(tmp)
  os.remove(tmp)
  check(ok and fresh ~= '' and fresh == src('src/import/Gen4BattleHallTables.lua'),
    'src/import/Gen4BattleHallTables.lua is what the generator makes from this checkout')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
