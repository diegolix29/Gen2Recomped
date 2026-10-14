-- Run:  python tools/run_lua_check.py tools/gen4_battle_tower_check.lua <platinum cache dir>
--
-- PLATINUM'S BATTLE TOWER (src/pokemon/Gen4BattleTower.lua,
-- src/script/Gen4BattleTowerCommands.lua, src/import/Gen4BattleTowerData.lua)
-- against unk_02049D08.c, unk_0204AEE8.c, unk_020494DC.c and overlay104: the
-- trainers and sets, the struct's RNG, who is drawn for which room, how a team
-- is built, the records, the Battle Points, and the commands the tower's
-- scripts run.

package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or 'G:/Gen2Recomped/platinum/data/generated'):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local function src(p) local f = io.open(p, 'rb'); local s = f and f:read('*a'); if f then f:close() end return s or '' end

local BT = require('src.pokemon.Gen4BattleTower')

-- ------------------------------------------------------------- the data --
local rec = load('gen4_battle_tower')
check(rec, 'the cache has gen4_battle_tower (tools/gen4_battle_tower_extract.lua)')
local nt, ns = 0, 0
for _ in pairs(rec and rec.trainers or {}) do nt = nt + 1 end
for _ in pairs(rec and rec.sets or {}) do ns = ns + 1 end
check(nt == 315 and ns == 951, ('315 trainers and 951 sets (%d, %d)'):format(nt, ns))
check(rec and rec.trainers[0].class == 2 and #rec.trainers[0].sets > 0, 'Youngster Jim: class 2 (Youngster) with sets')
check(rec and rec.trainers[126].class == 16, 'trainer 126 read raw, not as LZ77 (its first byte is 0x10)')
check(rec and rec.trainers[305] and rec.trainers[306], 'Palmer, silver and gold')

-- ---------------------------------------------------------------- the RNG --
check(BT.next(12345) == 1487781686, 'sub_0206BFF0: x * 48828125 + 1, 32 bits')
check(BT.next2(12345) == 1658452350, 'sub_0206BFFC: x * 1566083941 + 1, 32 bits')
local bt0 = { seed = 12345 }
check(BT.random(bt0) == 22702 and BT.random(bt0) == 33433, 'BattleTower_GetRandom: the seed / 65535, as u16')

-- ------------------------------------------------------- who is drawn --
local save = { party = {}, player = { gender = 0 } }
local bt = BT.init(save, 0, BT.SINGLE)
check(bt.size == 3 and bt.next == 1, 'singles: three each, from opponent 1')
bt.seed = 1
local ok = true
for room = 0, 6 do
  for n = 0, 5 do
    local id = BT.trainerFor(bt, room, n)
    if id < BT.RANGES[room + 1][1] or id > BT.RANGES[room + 1][2] then ok = false end
  end
  local boss = BT.trainerFor(bt, room, 6)
  if room ~= 2 and room ~= 6 and (boss < BT.BOSS_RANGES[room + 1][1] or boss > BT.BOSS_RANGES[room + 1][2]) then ok = false end
end
check(ok, 'every room draws from its own range, the seventh from the boss range')
check(BT.trainerFor(bt, 2, 6) == 305 and BT.trainerFor(bt, 6, 6) == 306, 'Palmer is the 21st and the 49th')
local btD = BT.init({ party = {}, player = {} }, 0, BT.DOUBLE)
btD.seed = 7
check(BT.trainerFor(btD, 2, 6) ~= 305, 'but not in doubles')
bt.roomNum = 3
BT.chooseTrainers(bt)
local uniq, seen = true, {}
for n = 0, 6 do if seen[bt.trainers[n]] then uniq = false end; seen[bt.trainers[n]] = true end
check(uniq, 'seven trainers, none twice')

-- ---------------------------------------------------------- a team --
local data = { gen4_battle_tower = rec }
local party = BT.createParty(bt, data, 150, 3)
check(party and #party == 3, 'three Pokemon')
if party then
  local sp, natures, shiny, items = {}, true, false, {}
  for _, p in ipairs(party) do
    if sp[p.species] then sp.dup = true end
    sp[p.species] = true
    if p.personality % 25 ~= rec.sets[p.setID].nature then natures = false end
    if BT.shiny(p.otId, p.personality) then shiny = true end
  end
  check(not sp.dup, 'no species twice')
  check(natures, 'each personality carries its set\'s nature')
  check(not shiny, 'none shiny')
  check(party[1].ivs == 12, 'trainer 150: IVs 31 / 8 * 4 = 12')
  local n = 0
  for _, e in ipairs(party[1].evs) do if e > 0 then n = n + 1 end end
  check(n == 0 or party[1].evs[1] + party[1].evs[2] + party[1].evs[3] + party[1].evs[4] + party[1].evs[5] + party[1].evs[6] <= 510,
    'EVs: 510 shared by the flagged stats, 255 at most')
end
check(BT.ivsFor(0) == 3 and BT.ivsFor(219) == 21 and BT.ivsFor(305) == 31, 'IVs by trainer id')

-- ----------------------------------------------------------- entering --
local function mon(sp, item, egg) return { species = sp, item = item, level = 50, isEgg = egg } end
check(BT.enoughValid({ party = { mon(25), mon(6), mon(9) } }, 3), 'three different: enough')
check(not BT.enoughValid({ party = { mon(25), mon(25), mon(9) } }, 3), 'two the same species: not enough')
check(not BT.enoughValid({ party = { mon(25, 1), mon(6, 1), mon(9, 1) } }, 3), 'all holding the same item: not enough')
check(not BT.enoughValid({ party = { mon(150), mon(6), mon(9) } }, 3), 'Mewtwo is banned')
check(BT.enoughValid({ party = { mon(25, 1), mon(6, 1), mon(9), mon(3) } }, 3), 'some three of four will do')
local bt2 = BT.init({ party = { mon(25), mon(6, 5), mon(9, 5) }, player = {} }, 0, BT.SINGLE)
bt2.slots = { [0] = 0, [1] = 1, [2] = 2 }
check(BT.checkDuplicates(bt2) == 2, 'duplicate items: 2')

-- ---------------------------------------------------------- the records --
local s3 = { party = {}, player = {} }
local b3 = BT.init(s3, 0, BT.SINGLE)
for _ = 1, 7 do BT.advance(b3) end
check(BT.hasDefeatedSeven(b3) and BT.streak(b3) == 7, 'seven beaten')
BT.winRound(b3)
local r3 = BT.record(s3)
check(BT.flag(r3, 8, 0) and BT.room(r3, BT.SINGLE, 0) == 1 and BT.stat(r3, 1) == 7 and BT.stat(r3, 0) == 7,
  'a won round: the streak lives on, room 1, current and best 7')
check(BT.reward(b3) == 3 and BT.bp(s3) == 3, 'room 1 pays 3 BP')
local b4 = BT.init(s3, 0, BT.SINGLE)
check(b4.streakBase == 7 and b4.roomNum == 1, 'the next challenge carries on from 7, room 1')
BT.advance(b4); BT.advance(b4)
BT.endStreak(b4)
check(not BT.flag(r3, 8, 0) and BT.room(r3, BT.SINGLE, 0) == 0 and BT.stat(r3, 1) == 9 and BT.stat(r3, 0) == 9,
  'a loss ends it: room 0, best and last 9')
b4.beatPalmer = 1
check(BT.reward(b4) == 20, 'beating Palmer pays 20')
check(BT.addBP(s3, 20000) == 9999, 'BP stop at 9999')
local s5 = { party = {}, player = {} }
local b5 = BT.init(s5, 0, BT.SINGLE)
b5.slots = { [0] = 1, [1] = 2, [2] = 0 }; b5.trainers = { [0] = 4 }; b5.next = 3; b5.seed = 99
BT.suspend(b5)
local b6 = BT.init(s5, 1, 0xFFFF)
check(b6.mode == BT.SINGLE and b6.next == 3 and b6.defeated == 2 and b6.slots[0] == 1 and b6.seed == 99,
  'Rest, then Continue: the challenge picks up where it was')

-- ------------------------------------------------------------ the commands --
local Commands = require('src.script.Commands')
require('src.script.Gen4Commands')
for _, name in ipairs({ 'g4_bt_init', 'g4_bt_null', 'g4_bt_free', 'g4_bt_call', 'g4_bt_battle', 'g4_bt_select',
  'g4_bt_intro', 'g4_bt_reward', 'g4_bt_banlist_message', 'g4_bt_trophy', 'g4_bt_teala', 'g4_frontier_scene',
  'g4_bp_window', 'g4_get_bp', 'g4_give_bp', 'g4_remove_bp', 'g4_check_bp', 'g4_exchange_item' }) do
  check(type(Commands[name]) == 'function', name .. ' is a command')
end
local vars = {}
local G4 = require('src.script.Gen4Commands')
local game = { data = { gen4_battle_tower = rec, trainers = {} } }
local ctx = { game = game, save = { party = { mon(25), mon(6), mon(9) }, player = {} } }
Commands.g4_bt_call(ctx, 100, 0, 0x8000)
check(G4.getVar(ctx.save, 0x8000) == 1, 'CHECK_IS_NULL before the struct: TRUE')
Commands.g4_bt_init(ctx, 0, 0)
Commands.g4_bt_call(ctx, 100, 0, 0x8000)
check(G4.getVar(ctx.save, 0x8000) == 0, '...and FALSE after initbattletower')
Commands.g4_bt_call(ctx, 1, 0, 0x8000)
check(G4.getVar(ctx.save, 0x8000) == 1, 'CHECK_ENOUGH_VALID_POKEMON')
Commands.g4_bt_call(ctx, 57, 0, 0x8001)
Commands.g4_bt_call(ctx, 52, 0, 0)
check(game.gen4BattleTower.trainers[6] ~= nil, 'UNK_57 then UNK_52: the seven are drawn')
Commands.g4_bt_call(ctx, 40, 0, 0)
Commands.g4_bt_call(ctx, 41, 0, 0x8002)
check(#game.gen4BattleTower.opponent.party == 3 and G4.getVar(ctx.save, 0x8002) > 0, 'SET_OPPONENT_TEAMS, GET_OPPONENT_OBJECT_ID')
Commands.g4_give_bp(ctx, 40)
Commands.g4_check_bp(ctx, 32, 0x8003)
Commands.g4_exchange_item(ctx, 1, 0, 0x8004, 0x8005)
check(G4.getVar(ctx.save, 0x8003) == 1 and G4.getVar(ctx.save, 0x8004) == 333 and G4.getVar(ctx.save, 0x8005) == 32,
  'BP: 40 is enough for TM06 at 32')
Commands.g4_exchange_item(ctx, 0, 25, 0x8004, 0x8005)
local lastItem = G4.getVar(ctx.save, 0x8004)
Commands.g4_exchange_item(ctx, 1, 14, 0x8006, 0x8007)
check(lastItem == 50 and G4.getVar(ctx.save, 0x8006) == 353 and G4.getVar(ctx.save, 0x8007) == 80,
  'the last item (Rare Candy, 48) and the last TM (TM26, 80)')
Commands.g4_bt_free(ctx)
check(game.gen4BattleTower == nil, 'freebattletower')
local _ = vars

-- A COMMAND'S RETURN IS A JUMP: ScriptRunner reads a number as the row to go
-- to, so the save commands' answers must go in their vars only. Returning
-- them sent Common_SaveGame -- the Battle Tower's save before every
-- challenge -- back to the start of the attendant's script.
do
  local fake = { save = { gen4Vars = {}, player = {} }, game = { data = {} } }
  for _, name in ipairs({ 'g4_check_save_type', 'g4_misc_save_init', 'g4_hall_of_fame_corrupted', 'g4_store_save_result' }) do
    local okC, r = pcall(Commands[name], fake, 0x8000)
    check(okC and type(r) ~= 'number', name .. ' returns no number (it would be taken as a jump)')
  end
end
check(src('src/core/Game.lua'):find('self.overworld.fadeOverlay = nil', 1, true),
  'returning to the title drops the overworld\'s stale fade (Rest froze the resumed challenge)')

-- the Exchange Service Corner (ScrCmd_PokeMartFrontier + MART_TYPE_FRONTIER)
do
  local BTC = require('src.script.Gen4BattleTowerCommands')
  local tms, tmPrice = BTC.frontierStock(0)
  local items, itemPrice = BTC.frontierStock(1)
  check(#tms == 15 and tms[1] == 333 and tmPrice[333] == 32 and tmPrice[353] == 80, 'the right counter: fifteen TMs, TM06 32 BP ... TM26 80 BP')
  check(#items == 26 and items[1] == 46 and itemPrice[46] == 1 and itemPrice[50] == 48, 'the left counter: 26 items, Protein 1 BP ... Rare Candy 48 BP')
  local Shop = require('src.ui.Gen4ShopMenu')
  local sg = { data = { items = { [46] = { id = 46, name = 'Protein', price = 9800 } }, text = {} },
    save = { money = 50000, inventory = {}, gen4Frontier = { bp = 5 } } }
  local shop = Shop.new(sg, items, function() end, nil, { frontier = { price = function(id) return itemPrice[id] end } })
  check(shop:def(46).price == 1 and shop:def(46).name == 'Protein', 'priced in BP, the item otherwise as it is')
  check(shop:funds() == 5, 'the funds are the BP, not the money')
  shop:pay(3)
  check(BT.bp(sg.save) == 2 and sg.save.money == 50000, 'paying takes BP and leaves the money alone')
end

-- ------------------------------------------------------------- the wiring --
local vm = src('src/script/Gen4ScriptVM.lua')
for _, op in ipairs({ 'initbattletower', 'setbattletowernull', 'freebattletower', 'callbattletowerfunction',
  'printbattletowerintromessage', 'messageseenbanlistspecies', 'launchbattlefrontierscene', 'showbattlepoints',
  'getbattlepoints', 'givebattlepoints', 'checkbattlepoints', 'getexchangeservicecorneritemandcost' }) do
  check(vm:find('L.' .. op .. ' = ', 1, true), op .. ' is lowered')
end
check(src('src/battle/BattleState.lua'):find('slot.prebuilt', 1, true), 'trainer slots can carry a whole Pokemon')
check(src('src/ui/Gen4PartyMenu.lua'):find('function Gen4PartyMenu:confirmSelection', 1, true), 'the party menu chooses a team')
check(src('src/core/Game.lua'):find('applySpecialLocation', 1, true), 'Continue after Rest returns to the lobby')

-- the party menu's team choice
local PM = require('src.ui.Gen4PartyMenu')
local popped, got = 0, nil
local g2 = { data = { gen4_graphics = {}, text = {} }, save = { party = { mon(25), mon(150), mon(6), mon(9) } },
  stack = { pop = function() popped = popped + 1 end } }
local pm = PM.new(g2, { select = { count = 3, maxLevel = 100, banlist = true, unique = true, onDone = function(s) got = s end } })
check(pm:eligibility(2) == 'banned' and pm:eligibility(1) == 'eligible', 'Mewtwo is BANNED, Pikachu may enter')
pm.index = 1; pm:runAction('enter')
pm.index = 3; pm:runAction('enter')
pm.index = #g2.save.party + 1; pm:choose()
check(got == nil and pm.selectNotice ~= nil, 'CONFIRM with two: "Three Pokemon are needed."')
pm.selectNotice = nil
pm.index = 4; pm:runAction('enter')
check(pm.index == #g2.save.party + 1, 'the third moves the cursor onto CONFIRM')
pm:choose()
check(got and got[1] == 1 and got[2] == 3 and got[3] == 4 and popped == 1, 'CONFIRM hands back slots 1, 3, 4 in order')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
