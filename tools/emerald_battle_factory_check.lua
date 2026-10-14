-- Run:  python tools/run_lua_check.py tools/emerald_battle_factory_check.lua <emerald cache dir> [pokeemerald]
--
-- THE BATTLE FACTORY (src/script/Gen3BattleFactory.lua, src/ui/Gen3FactoryScreen.lua)
-- against pokeemerald's battle_factory.c: the rental tiers and the fixed IVs,
-- the past-rentals rank, the six on offer and the three they face, the type
-- and style hints, the swap, the Battle Points, Noland, and the wiring into
-- specials 241 and 239.
--
-- Given a pokeemerald checkout as the second argument, sFixedIVTable,
-- sInitialRentalMonRanges and sRequiredMoveCounts are read from the source
-- and compared.

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
local P = require('src.script.Gen3BattleFactory')
local data = { moves = load('moves') or {}, pokemon = load('pokemon') or {}, items = {},
               constants = load('constants') or {}, trainers = load('trainers') or {} }
local pool = F.parties(data)
check(pool and pool.mons and #pool.mons == 882, 'gBattleFrontierMons: 882 sets in the cache')

-- ---------------------------------------------------------------- tables --
check(#P.RANGES == 16 and P.RANGES[1][1] == 110 and P.RANGES[8][2] == 849 and P.RANGES[16][2] == 881,
  'sInitialRentalMonRanges: eight tiers a level mode')
check(P.fixedIV(0, false) == 3 and P.fixedIV(0, true) == 6 and P.fixedIV(5, true) == 31 and P.fixedIV(20, false) == 31,
  'sFixedIVTable, the seventh battle a column up, and the top row past challenge 8')
check(P.rentalRank(0) == 0 and P.rentalRank(14) == 0 and P.rentalRank(15) == 1 and P.rentalRank(42) == 4
  and P.rentalRank(43) == 5, 'GetNumPastRentalsRank: 15 / 22 / 29 / 36 / 43')
check(P.BP[0][1] == 3 and P.BP[1][1] == 4 and P.BP[0][30] == 15, "sBattlePointAwards' factory columns")
check(F.battlePoints(0, 0, F.FACTORY) == 3 and F.battlePoints(0, 1, F.FACTORY) == 4,
  'the factory column is the one paid, by mode')
check(F.BRAIN_AT_BY[4][1] == 21 and F.BRAIN_AT_BY[4][2] == 42, 'Noland at the 21st and the 42nd')
check(F.BRAIN_TRAINER and F.BRAIN_TRAINER[4] == 'NOLAND' and data.trainers.NOLAND, "Noland's trainer record")

local lo, hi = 1e9, -1
for _ = 1, 3000 do
  local id = P.monIdFor(0, 0, false)
  lo, hi = math.min(lo, id), math.max(hi, id)
end
check(lo >= 110 and hi <= 199 and hi - lo > 80, 'challenge 0, level 50: GRIMER..FURRET_1')
local ok = true
for _ = 1, 2000 do local id = P.monIdFor(1, 9, true); if id < 372 or id > 881 then ok = false end end
check(ok, 'open level past challenge 7: the whole top range')
ok = true
for _ = 1, 2000 do local id = P.monIdFor(0, 2, true); if id < 372 or id > 467 then ok = false end end
check(ok, 'a better pick takes the next tier')

-- -------------------------------------------------------------- a set --
local returner
for i, row in ipairs(pool and pool.mons or {}) do
  for _, m in ipairs(row.moves or {}) do if m == 'RETURN' then returner = i - 1 break end end
  if returner then break end
end
local m = returner and P.makeMon(data, returner, 50, 9, nil, 1234)
local hasFrust = false
for _, mv in ipairs(m and m.moves or {}) do if mv.id == 'FRUSTRATION' or mv == 'FRUSTRATION' then hasFrust = true end end
check(m and m.happiness == 0 and hasFrust and m.factoryId == returner,
  'a rental: friendship 0, RETURN made FRUSTRATION (SetMonMoveAvoidReturn)')

-- --------------------------------------------------------- a challenge --
local function newCtx()
  local save = { vars = {}, flags = {}, party = {}, player = { id = 4242 } }
  local ctx = { save = save, game = { data = data, stringBuffers = {} } }
  G3.setVar(save, F.VAR_FACILITY, P.FACILITY)
  G3.setVar(save, F.VAR_MODE, F.SINGLES)
  local s = F.state(save)
  s.data = s.data or {}
  s.data[1] = 0
  return ctx, s
end
local ctx, s = newCtx()
P.func(ctx, 0)
local _, fk = P.state(ctx.save)
check(s.data[2] == 0 and P.streak(s, 0, 0) == 0 and fk.rents['0:0'] == 0, 'InitFactoryChallenge: a fresh streak')
P.func(ctx, 13)
local ids, sp, items, n = {}, {}, {}, 0
local dupItem, dupId = false, false
for i = 1, 6 do
  local rec = fk.rentals[i]
  if rec then
    n = n + 1
    local row = P.row(data, rec.monId)
    if ids[rec.monId] then dupId = true end
    ids[rec.monId] = true
    if row.item and items[row.item] then dupItem = true end
    items[row.item or false] = row.item and true or nil
    sp[row.species] = (sp[row.species] or 0) + 1
  end
end
check(n == 6 and not dupId and not dupItem, 'GenerateInitialRentalMons: six sets, no set or held item twice')
P.func(ctx, 12)
local offered = {}
for i = 1, 6 do offered[P.row(data, fk.rentals[i].monId).species] = true end
local clash, theirs = false, {}
for _, id in ipairs(fk.temp) do
  local row = P.row(data, id)
  if offered[row.species] or theirs[row.species] then clash = true end
  theirs[row.species] = true
end
check(#fk.temp == 3 and not clash and s.opponent ~= nil,
  "GenerateOpponentMons: a trainer and three, nothing that's on offer to you")

-- the hints, over a team chosen to say something
local function idOf(species)
  for i, row in ipairs(pool.mons) do if row.species == species then return i - 1 end end
end
local fire = { idOf('CHARIZARD'), idOf('NINETALES'), idOf('ARCANINE') }
fk.temp = fire
P.func(ctx, 14)
check(G3.getVar(ctx.save, 0x800D) == P.TYPES.FIRE, 'GetOpponentMostCommonMonType: three FIRE -> FIRE')
local mixed = { idOf('PIKACHU'), idOf('SQUIRTLE'), idOf('BULBASAUR') }
if mixed[1] and mixed[2] and mixed[3] then
  fk.temp = mixed
  P.func(ctx, 14)
  check(G3.getVar(ctx.save, 0x800D) == P.NUM_TYPES, 'three types once each: no hint (NUMBER_OF_MON_TYPES)')
end
-- a style: three Pokemon each knowing a move from the weather list -> 2+ of style 7
local weather = {}
for i, row in ipairs(pool.mons) do
  for _, mv in ipairs(row.moves or {}) do
    if mv == 'RAIN_DANCE' or mv == 'SUNNY_DAY' or mv == 'SANDSTORM' or mv == 'HAIL' then
      weather[#weather + 1] = i - 1
      break
    end
  end
  if #weather == 2 then break end
end
fk.temp = { weather[1], weather[2] }
P.func(ctx, 15)
check(G3.getVar(ctx.save, 0x800D) >= 7, 'GetOpponentBattleStyle: two weather moves -> FACTORY_STYLE_WEATHER')
fk.temp = {}
P.func(ctx, 15)
check(G3.getVar(ctx.save, 0x800D) == 0, 'no moves of a style: FACTORY_STYLE_NONE')

-- the swap count is only written when a swap was made
G3.setVar(ctx.save, 0x8005, 3)
G3.setVar(ctx.save, 0x8006, 9)
P.func(ctx, 2)
check((fk.rents['0:0'] or 0) == 0, 'SetBattleFactoryData(swaps) with no swap: unchanged')
P.func(ctx, 8)
P.func(ctx, 2)
check(fk.rents['0:0'] == 9, 'after factory_setswapped: written')
P.func(ctx, 1)
check(G3.getVar(ctx.save, 0x800D) == 9, 'GetBattleFactoryData(swaps)')

-- the team you beat, offered back, and your party rebuilt from records
P.func(ctx, 13)
P.func(ctx, 12)
fk.rentals[4], fk.rentals[5], fk.rentals[6] = nil, nil, nil
fk.enemy = {}
for i, id in ipairs(fk.temp) do fk.enemy[i] = P.makeMon(data, id, 50, 3, nil, 1) end
fk.enemy[1].hp = 0
P.func(ctx, 9)
check(fk.beaten and #fk.beaten == 3 and fk.beaten[1].hp and fk.beaten[1].hp > 0
  and fk.rentals[4].monId == fk.temp[1], "SetRentalsToOpponentParty: the beaten three, fresh, in slots 4-6")
G3.setVar(ctx.save, 0x8005, 0)
P.func(ctx, 10)
check(#ctx.save.party == 3 and ctx.save.party[1].factoryId == fk.rentals[1].monId,
  'SetPlayerAndOpponentParties: your three from their records')
ctx.save.party[1].item = nil
P.func(ctx, 16)
check(ctx.save.party[1].item == P.row(data, fk.rentals[1].monId).item, 'RestorePlayerPartyHeldItems')

-- ---------------------------------------------------------------- wiring --
local fr = src('src/script/Gen3BattleFrontier.lua')
check(fr:find('S[241]', 1, true) and fr:find('Gen3BattleFactory', 1, true), 'special 241 is CallBattleFactoryFunction')
check(fr:find('Factory.battle', 1, true) or fr:find('Factory").battle', 1, true),
  'DoSpecialTrainerBattle arm 6 (SPECIAL_BATTLE_FACTORY)')
local fs = src('src/script/Gen3BattleFactory.lua')
check(fs:find('forfeit = true', 1, true) and fs:find('noItems = true', 1, true) and fs:find('noExp = true', 1, true),
  'a Factory battle: no items, no experience, and you may forfeit')
local Screen = require('src.ui.Gen3FactoryScreen')
check(type(Screen.new) == 'function' and type(Screen.update) == 'function', 'the rental and swap screens')

-- -------------------------------------------------------- the source --
if pret then
  local c = src(pret .. '/src/battle_factory.c')
  local iv = c:match('sFixedIVTable%[%]%[2%] =%s*(%b{})') or ''
  local k, same = 0, true
  for a, b in iv:gmatch('{(%d+),%s*(%d+)}') do
    k = k + 1
    if not (P.IVS[k] and P.IVS[k][1] == tonumber(a) and P.IVS[k][2] == tonumber(b)) then same = false end
  end
  check(k == 8 and same, 'sFixedIVTable matches the source')
  local rg = c:match('sInitialRentalMonRanges%[%]%[2%] =%s*(%b{})') or ''
  k, same = 0, true
  for a, b in rg:gmatch('//%s*(%d+)%s*%-%s*(%d+)') do
    k = k + 1
    if not (P.RANGES[k] and P.RANGES[k][1] == tonumber(a) and P.RANGES[k][2] == tonumber(b)) then same = false end
  end
  check(k == 16 and same, 'sInitialRentalMonRanges matches the source (its range comments)')
  local rc = c:match('sRequiredMoveCounts%[[^%]]*%] =%s*(%b{})') or ''
  k, same = 0, true
  for v in rc:gmatch('= (%d+)') do
    k = k + 1
    if P.STYLE_NEED[k] ~= tonumber(v) then same = false end
  end
  check(k == 7 and same, 'sRequiredMoveCounts matches the source')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
