-- Run:  python tools/run_lua_check.py tools/gen4_battle_bag_check.lua <cache dir>
--
-- PLATINUM'S BATTLE BAG AND THE BATTLE PARTY LIST'S PAGES, headless.
--
--   * the battle pockets are BattleBag_Init's: each bag item filed under every
--     pocket its ITEM_PARAM_BATTLE_POCKET mask names, six to a page, pages
--     wrapping (BattleBagTask_ChangePocketPage)
--   * the touch rects and cursor tables are the decomp's, including the
--     go-back-to-previous links and the hidden-until-a-key cursor
--   * "Item used last" opens the item's own page; an item no longer carried
--     is forgotten (BattleBag_CanUseLastUsedItem)
--   * TryUseItem refuses a ball at two foes / a hidden foe / a substitute
--   * the party list's prev / next skip eggs; its learn mode refuses an HM
--     and answers 1..4 or nil; an ETHER picks a move before it is used
--   * the art and the inks are in the cache (Gen4BattleArt bbag_* / b*_bg)

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
if not cacheDir or cacheDir == '' then
  print('usage: python tools/run_lua_check.py tools/gen4_battle_bag_check.lua <cache dir>')
  os.exit(2)
end
cacheDir = cacheDir:gsub('[/\\]$', '')
local function load(name)
  local f = loadfile(cacheDir .. '/' .. name .. '.lua')
  return f and f()
end

require('src.core.GameVersion').set('platinum')
local items = load('items') or {}
local art = load('gen4_battle_art') or {}
local anims = load('gen4_battle_anims') or {}
local moves = load('moves') or {}

-- ============================ 1. the cache carries the screens
for _, key in ipairs({ 'bbag_menu', 'bbag_pocket', 'bbag_use_0', 'bbag_use_3',
                       'bbag_pocketbtn_0_0', 'bbag_pocketbtn_3_2', 'bbag_item_0_0', 'bbag_item_off',
                       'bbag_last_0', 'bbag_last_3', 'bbag_usebtn_2_1', 'bbag_cancel_2',
                       'bbag_prev_3', 'bbag_next_0', 'bsummary_bg', 'bsummary_fg', 'bmoves_fg',
                       'bmovesum_bg', 'brestore_fg', 'blearn_bg', 'bconfirm_fg', 'bparty_prev_0',
                       'bparty_next_3', 'bparty_movebtn_0', 'bparty_movebtn_3', 'bparty_learnbtn_0',
                       'bparty_msbtn_2', 'bparty_confirm_0', 'bsummary_exp' }) do
  check(type(art[key]) == 'table' and art[key].path, 'gen4_battle_art carries ' .. key)
end
check(art.bbag_menu and art.bbag_menu.width == 256 and art.bbag_menu.height == 192, 'the bag views are 256x192')
check(art.bbag_pocketbtn_0_0 and art.bbag_pocketbtn_0_0.width == 128 and art.bbag_pocketbtn_0_0.height == 72,
      'a pocket button is 16x9 tiles')
check(art.bbag_item_0_0 and art.bbag_item_0_0.width == 128 and art.bbag_item_0_0.height == 48,
      'an item button is 16x6 tiles')
check(art.bbag_last_0 and art.bbag_last_0.width == 208 and art.bbag_last_0.height == 40,
      'the Item used last / USE bar is 26x5 tiles')
check(art.bsummary_exp and art.bsummary_exp.width == 72, 'the EXP fills are nine tiles')
check(anims.bagInk and anims.bagInk.row0 and anims.bagInk.row4 and anims.bagInk.row0[3],
      'gen4_battle_anims carries the bag windows\' palettes 0 and 4')
check(anims.partyInk13 and anims.partyInk13[15] and anims.partyInk13[1],
      'and the party pages\' palette 13')
local dsrc = io.open('src/core/Data.lua'):read('a')
check(dsrc:find('"gen4_battle_art"', 1, true) and dsrc:find('"gen4_battle_anims"', 1, true),
      'Data.lua loads both modules (by literal name)')

-- ============================ 2. a fake game, a stocked bag
local function input(keys)
  keys = keys or {}
  return { wasPressed = function(_, k) return keys[k] == true end,
           isDown = function() return false end }
end
local stack = { list = {} }
function stack:push(s) self.list[#self.list + 1] = s end
function stack:pop() self.list[#self.list] = nil end
function stack:top() return self.list[#self.list] end

local function newGame(inv, order)
  local game = {
    data = { items = items, moves = moves, text = {}, pokemon = {}, gen4_battle_art = art,
             gen4_battle_anims = anims },
    save = { inventory = inv, bagOrder = order, party = {} },
    stack = stack, input = input(),
  }
  return game
end

-- Potion 17, Super Potion 26, Ether 38 (HP/PP); Antidote 18, Full Heal 27
-- (status); Poke Ball 4, Great Ball 3 (balls); X Attack 57 (battle items)
local inv, order = {}, {}
for _, row in ipairs({ { 4, 10 }, { 17, 3 }, { 26, 2 }, { 38, 1 }, { 18, 4 }, { 27, 1 },
                       { 3, 2 }, { 57, 1 }, { 25, 1 }, { 24, 1 }, { 23, 1 }, { 22, 1 }, { 21, 1 } }) do
  inv[row[1]] = row[2]; order[#order + 1] = row[1]
end
local Bag = require('src.ui.Gen4BattleBag')
local battle = { data = nil, gen4CursorActive = false }
local game = newGame(inv, order)
battle.data, battle.game = game.data, game
local bag = Bag.new(game, { battle = battle })

local function ids(list) local t = {} for _, r in ipairs(list) do t[#t + 1] = r.id end return t end
local function has(list, id) for _, r in ipairs(list) do if r.id == id then return true end end return false end
check(has(bag.pockets[0], 17) and has(bag.pockets[0], 26) and has(bag.pockets[0], 38),
      'POTION, SUPER POTION and ETHER are HP/PP RESTORE (mask bits 2 and 4)')
check(has(bag.pockets[1], 18) and has(bag.pockets[1], 27), 'ANTIDOTE and FULL HEAL are STATUS HEALERS')
check(has(bag.pockets[2], 4) and has(bag.pockets[2], 3) and not has(bag.pockets[0], 4),
      'the balls are POKe BALLS and nowhere else')
check(has(bag.pockets[3], 57), 'X ATTACK is a BATTLE ITEM')
-- field pocket order: the medicine pocket (Potion...) before the balls in a
-- pocket shared by none; within a pocket the bag's own order
local p0 = ids(bag.pockets[0])
check(p0[1] == 17 and p0[2] == 26, 'within a field pocket the bag order holds: ' .. table.concat(p0, ','))

-- ============================ 3. paging
local n0 = #bag.pockets[0]
check(bag.pageCount[0] == math.floor((n0 - 1) / 6), 'pages = (items - 1) / 6, got ' .. tostring(bag.pageCount[0]))
bag.pocket = 0; bag:setScreen('pocket')
local function runPress() for _ = 1, 3 do bag:update(1 / 60) end end
if bag.pageCount[0] > 0 then
  bag:pickPocket(8); runPress()
  check(bag.cur.pages[0] == 1, 'NEXT turns the page')
  bag:pickPocket(8); runPress()
  check(bag.cur.pages[0] == 0, 'NEXT past the last page wraps to the first')
  bag:pickPocket(7); runPress()
  check(bag.cur.pages[0] == bag.pageCount[0], 'PREV from the first wraps to the last')
  bag.cur.pages[0] = 0
end
check(bag:itemAt(1, 0) and bag:itemAt(1, 0).id == 17, 'page position 1 is the first item')

-- ============================ 4. the cursor
local Cursor = require('src.ui.Gen4SubMenuCursor')
battle.gen4CursorActive = false
bag:setScreen('menu')
game.input = input({ right = true })
bag:update(1 / 60)
check(battle.gen4CursorActive == true and bag.cursor.index == 1,
      'the first key only shows the cursor (IsCursorVisible)')
bag:update(1 / 60)
check(bag.cursor.index == 3, 'right from HP/PP is POKe BALLS')
game.input = input({ down = true }); bag:update(1 / 60); bag:update(1 / 60)
check(bag.cursor.index == 6, 'down twice from POKe BALLS is CANCEL')
game.input = input({ up = true }); bag:update(1 / 60)
check(bag.cursor.index == 4, 'up from CANCEL goes back where it came from (prev link)')
game.input = input()
check(Cursor.hit(Bag.MENU_TOUCH, 10, 170) == 5 and Cursor.hit(Bag.MENU_TOUCH, 230, 170) == 6,
      'the menu touch rects: Item used last, CANCEL')
check(Cursor.hit(Bag.POCKET_TOUCH, 20, 170) == 7 and Cursor.hit(Bag.POCKET_TOUCH, 60, 170) == 8,
      'the pocket touch rects: prev, next')
check(Cursor.hit(Bag.USE_TOUCH, 100, 170) == 1, 'USE is the bar')

-- ============================ 5. Item used last
local c = Bag.bagCursor(game)
c.lastItem, c.lastPocket = 26, 0
bag:pickMenu(5); runPress()
check(bag.screen == 'use' and bag:itemAt((bag.cur.positions[0] or 0) + 1, 0).id == 26,
      'Item used last opens its own item')
inv[26] = nil
local bag2 = Bag.new(game, { battle = battle })
check(Bag.bagCursor(game).lastItem == nil, 'an item no longer carried is forgotten')
inv[26] = 2

-- ============================ 6. TryUseItem's refusals
local foeA, foeB = { mon = { hp = 5 } }, { mon = { hp = 5 } }
battle.player = { mon = {} }
battle.enemy = foeA
battle.foesOf = function() return { foeA, foeB } end
bag2.pocket = 2
check(bag2:refusal() ~= nil, 'no ball while two foes stand')
battle.foesOf = function() return { foeA } end
foeA.invulnerable = 'fly'
check(bag2:refusal() ~= nil, 'no ball at a foe out of sight')
foeA.invulnerable = nil; foeA.substituteHP = 10
check(bag2:refusal() ~= nil, 'no ball at a substitute')
foeA.substituteHP = nil
check(bag2:refusal() == nil, 'otherwise the ball flies')
bag2.pocket = 0
foeA.invulnerable = 'dig'
check(bag2:refusal() == nil, 'a POTION is not refused for a hidden foe')

-- ============================ 7. the battle party list's pages
local Party = require('src.ui.Gen4BattleParty')
local function mon(species, hp, egg) return { species = species, hp = hp, stats = { hp = 20 }, level = 10,
  moves = { { id = 1, pp = 10 }, { id = 15, pp = 5 } }, isEgg = egg, egg = egg } end
game.save.party = { mon(1, 10), mon(4, 0), mon(7, 5, true), mon(25, 3) }
local p = Party.new(game, { battle = battle })
p.index = 1
p:stepMon(1); check(p.index == 2, 'NEXT goes to the next member (a fainted one counts)')
p:stepMon(1); check(p.index == 4, '...and skips an egg')
p:stepMon(1); check(p.index == 1, '...and wraps')
p:stepMon(-1); check(p.index == 4, 'PREV wraps backwards')

-- learn mode: an HM is refused, a move is answered, CANCEL answers nil
local answer = 'unset'
local learner = { species = 1, hp = 10, stats = { hp = 20 }, level = 10,
  moves = { { id = 15, pp = 5 }, { id = 1, pp = 10 } } }
package.loaded['src.ui.MoveLearnMenu'] = { hmMoves = function() return { [15] = true } end }
stack.list = {}
local L = Party.new(game, { battle = battle, mode = 'learnMove', mon = learner, moveId = 53,
  onChoose = function(i) answer = i end })
stack:push(L)
check(L.screen == 'learn', 'learn mode opens on the learn page')
L:pickLearn(1); check(L.screen == 'confirm', 'a move opens FORGET / CANCEL')
L:pickConfirm(1); check(L.hmRefused == true and answer == 'unset', 'an HM cannot be forgotten')
L:pickConfirm(3); check(L.screen == 'learn', 'CANCEL goes back to the four moves')
L:pickLearn(2); L:pickConfirm(1)
check(answer == 2 and stack:top() ~= L, 'FORGET answers the slot and closes')
answer = 'unset'; stack.list = {}
local L2 = Party.new(game, { battle = battle, mode = 'learnMove', mon = learner, moveId = 53,
  onChoose = function(i) answer = i end })
stack:push(L2)
L2:pickLearn(5); L2:pickConfirm(1)
check(answer == nil, 'choosing the move to learn answers "don\'t learn"')

-- item mode: an ETHER asks which move, everything else hands the Pokemon on
stack.list = {}
local moved, switched
local U = Party.new(game, { battle = battle, mode = 'useItem', itemId = 38,
  onMove = function(m, i) moved = { m, i } end, onSwitch = function(m) switched = m end })
stack:push(U)
U:pickSlot(1)
check(U.screen == 'restore', 'an ETHER opens RESTORE WHICH MOVE?')
U:pickRestore(2)
check(moved and moved[1] == game.save.party[1] and moved[2] == 2, '...and hands on the Pokemon and the move')
stack.list = {}
local U2 = Party.new(game, { battle = battle, mode = 'useItem', itemId = 17,
  onSwitch = function(m) switched = m end })
stack:push(U2)
U2:pickSlot(4)
check(switched == game.save.party[4] and stack:top() ~= U2, 'a POTION hands the Pokemon straight on')

-- ============================ 8. the party ball wobble (SysTask_AnimatePartyBalls)
local G = require('src.battle.Gen4Battle')
local st = { phase = 0 }
G.ballWobbleStep(st, 50, 0)
check(st.phase == 0, 'below 87% the ball rests')
G.ballWobbleStep(st, 90, 3)
check(st.phase == 1 and st.delay == 13, 'at 87% it waits 10 + rand % 8')
local maxX, minX, frames = 0, 0, 0
for _ = 1, 60 do
  G.ballWobbleStep(st, 90, 0)
  frames = frames + 1
  maxX = math.max(maxX, st.x or 0); minX = math.min(minX, st.x or 0)
  if st.phase == 0 then break end
end
check(maxX == 3 and minX == -3, 'it rocks 3 px each way (0x180 a frame for two frames), got '
      .. maxX .. ' / ' .. minX)
check(st.phase == 0 and (st.x or 0) == 0, 'and settles back after the second bounce')

print(('%d checks, %d failed'):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
