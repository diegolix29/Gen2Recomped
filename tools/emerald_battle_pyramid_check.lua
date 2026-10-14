-- Run:  python tools/run_lua_check.py tools/emerald_battle_pyramid_check.lua <emerald cache dir> [pokeemerald]
--
-- THE BATTLE PYRAMID (src/script/Gen3BattlePyramid.lua) against pokeemerald's
-- battle_pyramid.c: the floor templates and their roll, the 4x4 layout out of
-- the sixteen squares (one exit left, the player on the entrance), where the
-- trainers and item balls go, the pickup items (SeedRng2 / Random2), the hints
-- out of the ROM, the wild Pokemon, the Pyramid bag, Brandon, the Battle
-- Points, and the wiring into the engine.
--
-- Given a pokeemerald checkout, the generated tables are made again from it
-- and compared with the committed module.

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
local P = require('src.script.Gen3BattlePyramid')
local T = require('src.import.Gen3PyramidTables')
local data = { maps = load('maps') or {}, constants = load('constants') or {}, pokemon = load('pokemon') or {},
               moves = load('moves') or {}, items = load('items') or {}, gen3_frontier_speech = load('gen3_frontier_speech') }

-- --------------------------------------------------------------- tables --
check(#T.FLOOR_TEMPLATES == 16 and T.FLOOR_TEMPLATES[1].numItems == 7 and T.FLOOR_TEMPLATES[16].numTrainers == 8,
  'sPyramidFloorTemplates: sixteen, 7 items on the first, 8 trainers on the last')
check(#T.TEMPLATE_OPTIONS == 34 and T.FLOOR_TEMPLATE_OFFSETS[7] == 29, 'sPyramidFloorTemplateOptions and their offsets')
check(#T.WILD_50 == 20 and #T.WILD_OPEN == 20 and #T.WILD_HEADERS == 7 and #T.WILD_HEADERS[1].slots == 12,
  'twenty rounds of wild Pokemon each way; seven floors of twelve slots')
check(data.constants.itemOrder[T.PICKUP_50[1][1]] == 'HYPER_POTION' and data.constants.itemOrder[T.LONG_REWARDS[1]] == 'BRIGHTPOWDER',
  "items as the cartridge's numbers, read through itemOrder")
check(data.constants.speciesOrder[T.WILD_50[1][1].species] == 'PLUSLE', 'round 1 opens on PLUSLE')
check(P.BP[1] == 5 and P.BP[21] == 15 and F.battlePoints(0, 0, F.PYRAMID) == 5, "sBattlePointAwards' pyramid column, paid")
check(F.BRAIN_AT_BY[6][1] == 21 and F.BRAIN_AT_BY[6][2] == 70 and F.BRAIN_GFX[6] == 234 and F.BRAIN_TRAINER[6] == 'BRANDON',
  'Brandon at the 21st and 70th floors, OBJ_EVENT_GFX_BRANDON')

-- ---------------------------------------------------------------- a floor --
local function newSave(r1, r2, r3, r4, floor)
  local save = { vars = {}, flags = {}, party = {}, player = {}, inventory = { POTION = 3 } }
  local s, r = P.state(save)
  s.data[1], s.data[2] = 0, floor or 0
  r.randoms = { r1, r2, r3, r4 }
  return save, s, r
end
local save, s, r = newSave(0x1234, 0xBEEF, 0x0F0F, 0x2A29, 0)
-- floor 0: roll = randoms[3] % 100 (0x2A29 = 10793 -> 93): {40,0} {70,1} {90,2} {100,3} -> template 3
check(P.templateId(s, r) == 3, 'GetPyramidFloorTemplateId: floor 0, a roll of 93 -> template 3')
local offs = P.layoutOffsets(s, r)
local lo = T.FLOOR_TEMPLATES[4].layoutOffsets
check(offs[0] == lo[(0x1234 % 8) + 1] and offs[1] == lo[(math.floor(0x1234 / 8) % 8) + 1]
  and offs[8] == lo[(math.floor((0x0F0F + 0x2A29 * 65536) / 256) % 8) + 1],
  'GetPyramidFloorLayoutOffsets: three bits a square, the second eight from (2|3<<16) >> 8')
local ent, exit = P.entranceExit(r)
check(ent == 0x2A29 % 16 and exit == 0x1234 % 16, 'the entrance from randoms[3], the exit from randoms[0]')
local _, _, r2 = newSave(5, 0, 0, 5)
local e2, x2 = P.entranceExit(r2)
check(e2 == 6 and x2 == 4, 'and when they coincide, entrance + 1 and exit - 1')

local L = P.layout(data, s, r)
local exits = 0
for i = 0, 32 * 32 - 1 do
  local b = L.blocks:byte(i * 2 + 1) + L.blocks:byte(i * 2 + 2) * 256
  if b % 1024 == P.EXIT then exits = exits + 1 end
end
check(#L.blocks == 32 * 32 * 2 and exits >= 1 and L.exit and math.floor(L.exit.x / 8) + math.floor(L.exit.y / 8) * 4 == exit,
  "the layout: 32x32, the exit square's exit tile the only one left")
check(L.entrance and math.floor(L.entrance.x / 8) + math.floor(L.entrance.y / 8) * 4 == ent,
  "the player starts on the entrance square's (former) exit tile")

local objs = P.placeObjects(data, s, r)
local t = P.template(s, r)
local trainers, items, seen, clash, unique = 0, 0, {}, false, {}
local inside = true
for _, o in ipairs(objs) do
  if o.text == P.TEXT_TRAINER then
    trainers = trainers + 1
    if unique[o.pyramidTrainer] then clash = true end
    unique[o.pyramidTrainer] = true
  else items = items + 1 end
  local k = o.x .. ',' .. o.y
  if seen[k] then clash = true end
  seen[k] = true
  if o.x < 0 or o.y < 0 or o.x > 31 or o.y > 31 then inside = false end
end
check(trainers == t.numTrainers and items == t.numItems, ('the template\'s %d trainers and %d items placed (%d, %d)')
  :format(t.numTrainers, t.numItems, trainers, items))
check(not clash and inside, 'no two in one place, no trainer twice, all on the floor')
check(objs[1].localId == 1 and objs[1].text == P.TEXT_TRAINER and objs[#objs].text == P.TEXT_ITEM,
  'trainers first (local ids 1..), then the item balls')
local same = P.placeObjects(data, s, r)
check(#same == #objs and same[1].x == objs[1].x and same[#same].y == objs[#objs].y,
  'the same randoms place them the same way (only the trainer picks are random)')

-- the floor def, rewritten in place
local def = data.maps[P.FLOOR]
P.prepareFloor(data, save)
check(def.width == 32 and def.height == 32 and #def.objects == #P.objects(data, s, r) and def._blockArray == nil,
  "the Floor map's def becomes this floor (and its decoded blocks are dropped)")

-- --------------------------------------------------------- the pickups --
local rng = P.rng2(0x1234)
local a = rng()
check(a == math.floor(((0x1234 * 1103515245 + 24691) % 2 ^ 32) / 65536), 'Random2: ISO_RANDOMIZE1, the top half')
local ctx = { save = save, game = { data = data, stringBuffers = {} } }
G3.setVar(save, F.VAR_FACILITY, P.FACILITY)
G3.setVar(save, 0x800F, t.numTrainers + 1)            -- the first item ball
G3.setVar(save, 0x8004, 7)
P.func(ctx, 7)
local item = G3.getVar(save, 0x8000)
local g = P.rng2(r.randoms[1])
local roll = g() % 100
local want
for i = T.PICKUP_OFFSETS[1] + 1, #T.PICKUP_SLOTS do
  if roll < T.PICKUP_SLOTS[i][1] then want = T.PICKUP_50[1][T.PICKUP_SLOTS[i][2] + 1] break end
end
check(item == want and G3.getVar(save, 0x8001) == 1, 'SetPickupItem: randoms[index / 2] seeds Random2, the slot table picks')
P.func(ctx, 8)
check(r.taken[t.numTrainers + 1], 'HidePyramidItem: taken for the rest of the floor')

-- ------------------------------------------------------------ the hints --
local h = data.gen3_frontier_speech and data.gen3_frontier_speech.pyramidHints
check(h and h[0] and h[5] and #h[0][1] == 8 and h[2][0][3] ~= '', 'sPostBattleTexts out of the ROM: six groups')
check(P.directionHint({ x = 20, y = 5 }, { x = 5, y = 5 }, 8, 2) == 2, 'the exit to the right, far enough: that direction')
local idx, kind = P.directionHint({ x = 6, y = 5 }, { x = 5, y = 5 }, 8, 2)
check(idx == 0 and kind == 2, 'too near: the default hint instead')
check(select(1, P.directionHint({ x = 3, y = 2 }, { x = 5, y = 5 }, 8, 0)) == 0, 'up and left, more up: up (x > y)')

-- ------------------------------------------------------------- the bag --
P.initBag(save)
P.syncBag(save, P.FLOOR)
check(save.gen3PyramidBag and save.inventory.HYPER_POTION == 1 and save.inventory.ETHER == 1 and not save.inventory.POTION,
  'inside, the bag is the Pyramid bag: a HYPER POTION and an ETHER')
local Bag = require('src.inventory.Bag')
for i = 1, 8 do Bag.add(save, 'ITEM_' .. i, 1, data) end
check(not Bag.add(save, 'ANOTHER', 1, data) and Bag.add(save, 'ETHER', 1, data), 'ten slots, and a slot that is there still takes more')
P.syncBag(save, P.LOBBY)
check(not save.gen3PyramidBag and save.inventory.POTION == 3 and not save.inventory.ETHER, 'outside, the real bag back')
save.party = { { species = 'A', item = 'LEFTOVERS' }, { species = 'B' }, { species = 'C', item = 'ITEM_9' } }
check(P.monsHaveItems(save), 'DoBattlePyramidMonsHaveHeldItem')
check(not P.storeHeldItems(save) and save.party[1].item == 'LEFTOVERS', 'a full bag takes none of them (VAR_RESULT 1)')

-- ------------------------------------------------------- the wild ones --
local wt = P.wildTable(save)
check(wt.grass.rate == 4 and wt.grass.slots[1].species == T.WILD_HEADERS[1].slots[1], "the floor's header: rate 4, index slots")
save.party = {}
local w = P.wildFor(data, save, { species = 1, level = 5 })
check(w and w.species == 'PLUSLE' and w.level >= 30 and w.level <= 40 and #w.pyramidMoves == 3,
  'GenerateBattlePyramidWildMon: the index into the round, its level -5..+5, its moves')
check(P.lobbyHint(7 * 23) == 3, 'GetBattlePyramidHint: the round, mod twenty')

-- ---------------------------------------------------------------- wiring --
check(type(G3.SPECIALS[243]) == 'function' and type(G3.SPECIALS[449]) == 'function' and type(G3.SPECIALS[516]) == 'function',
  'specials 243, 449-452 and 516')
check(F.BRAIN_TEAMS[6] == P.BRANDON and P.BRANDON[1][3].species == 'MOLTRES', "Brandon's two teams")
check(src('src/world/MapLoader.lua'):find('Gen3BattlePyramid").prepareFloor', 1, true), 'MapLoader rebuilds the floor')
local ow = src('src/world/OverworldController.lua')
check(ow:find('Pyramid.wildFor', 1, true) and ow:find('onExitTile', 1, true) and ow:find('trainerBeaten', 1, true)
  and ow:find('syncBag', 1, true), 'the overworld: wild Pokemon, the exit tile, battled trainers, the bag')
check(src('src/script/Gen3Commands.lua'):find('Gen3BattlePyramid").trainerBattle', 1, true)
  and src('src/script/Gen3Commands.lua'):find('P.entrance', 1, true), 'trainerbattle 9 and the warp onto the floor')
check(src('src/world/Gen3Flash.lua'):find('lightRadius', 1, true) and src('src/inventory/Bag.lua'):find('gen3PyramidBag', 1, true),
  'the dark and the ten-slot bag')

if pret then
  local tmp = os.tmpname()
  local ok = os.execute(('python tools/gen3_pyramid_tables_gen.py "%s" "%s" > NUL 2>&1'):format(pret, tmp))
  local fresh = src(tmp)
  os.remove(tmp)
  check(ok and fresh ~= '' and fresh == src('src/import/Gen3PyramidTables.lua'),
    'src/import/Gen3PyramidTables.lua is what the generator makes from this checkout')
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
