-- tools/gen4_touch_screen_parity_check.lua -- the bottom screens of Platinum's
-- SUMMARY and BAG, and the bag's action menu / item moving, as logic (no LOVE):
--
--   * summary (subscreen.c): the eight touch rectangles, the five-button
--     layout before the Contest Hall (FLAG_CONTEST_HALL_VISITED = 0x978) and
--     the contest pages hidden with it; a tap presses a button, sets its page,
--     holds while the stylus stays on it and leaves it lit; the pad clears it;
--     an egg's tap on SKILLS stays on its page; EXIT closes on release; the
--     condition graph grows over four frames from its centre corners
--   * bag (main.c): the pocket buttons' rectangles by pocket count, the dial
--     button as A, the dial's arc arithmetic (ApproximateArcLength) and its
--     13-pixel steps, MakeItemActionsMenu per pocket, TRASH's count and
--     question, Item_MoveInPocket through SELECT
--
--   python tools/run_lua_check.py tools/gen4_touch_screen_parity_check.lua

package.path = "./?.lua;" .. package.path
package.loaded['src.render.Font'] = { width = function(s) return #tostring(s) * 6 end,
  pushStyle = function() end, popStyle = function() end, draw = function() end }
package.loaded['src.core.Logger'] = { warn = function() end, info = function() end }
package.loaded['src.core.Strings'] = function(s, ...) if select('#', ...) > 0 then return s:format(...) end return s end
package.loaded['src.render.Assets'] = { image = function() return nil end }
package.loaded['src.ui.Theme'] = { cursor = 0 }
package.loaded['src.render.Gen4Palettes'] = { text = function() return nil end }
package.loaded['src.core.Sound'] = { play = function() end, playCry = function() end }
package.loaded['src.ui.SecondScreen'] = { mode = function() return "display" end, stowed = function() return false end,
  draw = function() end, toLocal = function(_, x, y) return x, y end,
  separateMode = function(mode) return mode == "display" end }

local PASS, FAIL = 0, 0
local function check(cond, what)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print("FAIL: " .. what) end
end
local function keys(...)
  local set = {}
  for _, k in ipairs({ ... }) do set[k] = true end
  return { wasPressed = function(_, k) return set[k] or false end, isDown = function() return false end }
end
local idle = keys()

-- ------------------------------------------------------------- summary --
do
  local Summary = require('src.ui.Gen4SummaryMenu')
  local closed = 0
  local function make(flags, mon)
    mon = mon or { species = 392, level = 5, moves = {}, contest = { cool = 40, tough = 200 } }
    local game = { data = { text = {} }, save = { party = { mon }, flags = flags }, input = idle,
      stack = { pop = function() closed = closed + 1 end } }
    return Summary.new(game, mon), game
  end
  local s, game = make({ FLAG_G4_0978 = true })
  check(#s:visiblePages() == 8, 'after the Contest Hall: eight pages')
  check(s:subLayout() == Summary.SUB_LAYOUTS.normal, 'and the eight-button touch screen')
  local r = Summary.SUB_LAYOUTS.normal.buttons
  check(r[1].rect[1] == 32 and r[1].rect[4] == 47 and r[8].rect[3] == 208 and r[5].rect[3] == 136,
    'sSubscreenRectangles_Normal')
  local n = make({})
  check(#n:visiblePages() == 5 and n:subLayout() == Summary.SUB_LAYOUTS.noContest
    and Summary.SUB_LAYOUTS.noContest.scroll == 4, 'before it: five pages, five buttons, SUB_0 scrolled 4')
  check(make({}, nil) and Summary.new({ data = { text = {} }, save = {}, input = idle, stack = {} },
    { mon = { species = 1, moves = {} }, showContest = true }):showContest(), 'a caller can still force showContest')

  -- tap SKILLS: pressed, page set, held, then lit
  s:touchpressed('t', 60, 140)
  check(s:pageKey() == 'skills' and s.subPress and s.subPress.index == 3, 'a tap presses SKILLS and sets its page')
  for _ = 1, 10 do s:update() end
  check(s.subPress ~= nil, 'the press holds while the stylus stays on the button')
  s:touchreleased('t'); s:update()
  check(s.subPress == nil and s.subLit == 3, 'released, the button stays lit')
  game.input = keys('right'); s:update(); game.input = idle
  check(s.subLit == nil and s:pageKey() == 'moves', 'the pad changes page and puts it out')
  -- the pad is not read during a press
  s:touchpressed('t', 220, 100)
  game.input = keys('left'); s:update(); game.input = idle
  check(s:pageKey() == 'ribbons', 'no pad input during a press')
  s:touchreleased('t'); for _ = 1, 6 do s:update() end
  -- EXIT closes on release
  s:touchpressed('t', 228, 50); s:touchreleased('t')
  for _ = 1, 6 do s:update() end
  check(closed == 1, 'EXIT leaves once the stylus lets go')
  -- an egg stays on MEMO
  local egg = make({ FLAG_G4_0978 = true }, { species = 392, isEgg = true, egg = true, moves = {} })
  egg:touchpressed('t', 60, 140); egg:touchreleased('t')
  for _ = 1, 6 do egg:update() end
  check(egg:pageKey() == 'memo' and egg.subLit == nil, 'an egg cannot open SKILLS; the button goes back to rest')
  -- the condition graph grows
  local g = make({ FLAG_G4_0978 = true })
  for i, p in ipairs(g.pages) do if p.key == 'condition' then g.page = i end end
  g:update()
  local q0 = g:conditionQuads(g.graphFrame)
  check(g.graphFrame == 0 and q0[1][1] == q0[1][7] and q0[1][2] == q0[1][8], 'frame 0: each quad on its centre corner')
  for _ = 1, 4 do g:update() end
  local full = g:conditionQuads(nil)
  local now = g:conditionQuads(g.graphFrame)
  check(g.graphFrame == 4 and now[1][1] == full[1][1] and now[2][3] == full[2][3], 'frame 4: grown')
  check(#g:conditionFlashes() == 1, 'one condition flash, on the highest stat')
end

-- ----------------------------------------------------------------- bag --
do
  local Bag = require('src.ui.Gen4BagMenu')
  local items = {
    [1] = { id = 1, name = 'A', fieldPocket = 0, fieldUseFunc = 1 },
    [2] = { id = 2, name = 'B', fieldPocket = 0 },
    [3] = { id = 3, name = 'C', fieldPocket = 0 },
    [4] = { id = 4, name = 'D', fieldPocket = 0, preventToss = true },
    [5] = { id = 450, name = 'Bike', fieldPocket = 7, fieldUseFunc = 5, preventToss = true, canRegister = true },
    [6] = { id = 6, name = 'TM', fieldPocket = 3, fieldUseFunc = 3 },
    [7] = { id = 7, name = 'Berry', fieldPocket = 4, fieldUseFunc = 8 },
  }
  local save = { inventory = { [1] = 3, [2] = 1, [3] = 9, [4] = 1, [5] = 1, [6] = 1, [7] = 2 },
    bagOrder = { 1, 2, 3, 4, 5, 6, 7 }, player = {} }
  local game = { data = { items = items, text = {} }, save = save, input = idle,
    stack = { pop = function() end, push = function() end } }
  local b = Bag.new(game, {})
  check(b:pocketButtonAt(30, 100) == 2 and b:pocketButtonAt(150, 170) == 5 and b:pocketButtonAt(128, 80) == nil,
    'sPocketButtonTouchRectangles_8Pockets')
  check(Bag.BUTTON_RECTS[4][2][1] == 120 and Bag.BUTTON_RECTS[1][1][3] == 136, 'the 4- and 1-pocket rectangles')
  check(b:dialButtonAt(104, 56) and b:dialButtonAt(151, 103) and not b:dialButtonAt(152, 80), 'sDialBtnTouchRect')
  -- the arc: a quarter of the way round clockwise from the top is positive
  check(Bag.arcLength(0, 80, -10, 79) > 0 and Bag.arcLength(0, 80, 10, 79) < 0, 'ApproximateArcLength signs the turn')
  -- the action menus
  local function actions(id) return table.concat(b:itemActions(id), ',') end
  check(actions(1) == 'use,give,trash,cancel', 'ITEMS: USE GIVE TRASH CANCEL')
  check(actions(2) == 'give,trash,cancel', 'no field function: no USE')
  check(actions(4) == 'cancel', 'too important: no GIVE / TRASH')
  b.pocket = 8
  check(actions(5) == 'use,register,cancel', 'a registrable key item')
  save.onBike = true; save.registeredItem = 5
  check(actions(5) == 'walk,deselect,cancel', 'on the bike: WALK; registered: DESELECT')
  save.onBike, save.registeredItem = nil, nil
  b.pocket = 4
  check(actions(6) == 'use,give,cancel', 'TMs: no TRASH')
  b.pocket = 5
  check(actions(7) == 'checkTag,use,give,trash,cancel', 'berries: CHECK TAG first')
  -- A opens it, B shuts it
  b.pocket = 1; b.listPos, b.cursorPos = 0, 1; b:rebuild()
  game.input = keys('a'); b:update(); game.input = idle
  check(b.menu and b.menu.kind == 'actions' and b.menu.id == 1, 'A on an item opens its actions')
  game.input = keys('b'); b:update(); game.input = idle
  check(b.menu == nil, 'B closes them')
  -- TRASH: how many, then the question, then the message
  b:openActions(b:selected())
  for i, a in ipairs(b.menu.rows) do if a == 'trash' then b.menu.index = i end end
  game.input = keys('a'); b:update()
  check(b.trash and b.trash.stage == 'count' and b.trash.n == 1, 'TRASH asks how many')
  game.input = keys('up'); b:update(); b:update()
  game.input = keys('down'); b:update(); b:update(); b:update()
  check(b.trash.n == 3, 'up / down step and wrap (sub_0208C15C)')
  game.input = keys('a'); b:update()
  check(b.menu and b.menu.kind == 'yesno', 'then YES / NO')
  b:update(); game.input = idle
  check(save.inventory[1] == nil and b.message ~= nil, 'YES throws them away and says so')
  game.input = keys('a'); b:update(); game.input = idle
  check(b.message == nil, 'A puts the message away')
  -- moving: SELECT on B, two down, A -> B goes after C
  save.inventory[1] = 3; save.bagOrder = { 1, 2, 3, 4, 5, 6, 7 }
  b.listPos, b.cursorPos = 0, 2; b:rebuild()
  game.input = keys('select'); b:update()
  check(b.moving and b.moving.id == 2, 'SELECT picks the item up')
  game.input = keys('down'); b:update(); b:update()
  game.input = keys('a'); b:update(); game.input = idle
  check(b.moving == nil and table.concat(save.bagOrder, ',') == '1,3,2,4,5,6,7', 'Item_MoveInPocket puts it before the bar')
  check(b:selected().id == 2, 'and the cursor follows it')
  b.pocket = 4; b:rebuild()
  check(not b:canMove(), 'TMs cannot be moved')
  -- touch: a pocket button changes pocket and lights; the dial button is A
  b.pocket = 1; b:rebuild()
  b:touchpressed('t', 30, 100)
  check(b.pocket == 2 and b.pocketPress, 'a pocket button changes pocket')
  for _ = 1, 3 do b:update() end
  check(b:pocketButtonFace(2) == 2 and b.shock, 'pressed face and the shockwave on frame 3')
  b:touchreleased('t'); for _ = 1, 5 do b:update() end
  check(b:pocketButtonFace(2) == 1, 'lit once released')
  game.input = keys('left'); b:update(); game.input = idle
  check(b:pocketButtonFace(2) == 0 and b.pocket == 1, 'the pad puts it out')
  b.listPos, b.cursorPos = 0, 1; b:rebuild()
  b:touchpressed('t', 128, 80); b:update(); b:touchreleased('t')
  check(b.menu and b.menu.kind == 'actions' and b:dialButtonFace() == 2, 'the dial button is A')
  b.menu = nil
  -- the dial: anticlockwise drag scrolls the list down, 13 pixels a step
  save.inventory = {}; save.bagOrder = {}
  for i = 1, 3 do save.inventory[i] = 1; save.bagOrder[#save.bagOrder + 1] = i end
  for i = 10, 30 do items[i] = { id = i, name = 'X' .. i, fieldPocket = 0 }; save.inventory[i] = 1; save.bagOrder[#save.bagOrder + 1] = i end
  b.listPos, b.cursorPos = 0, 1; b:rebuild()
  b:touchpressed('t', 128, 30)
  for k = 1, 16 do
    local a = math.rad(-90 - k * 90 / 16)
    b:touchmoved('t', 128 + 50 * math.cos(a), 80 + 50 * math.sin(a)); b:update()
  end
  for _ = 1, 8 do b:update() end
  check(b.index > 3 and b.dialRotation and b.dialRotation > 180, 'turning the dial scrolls and turns it')
  b:touchreleased('t'); b:update()
  check(b.dial == nil, 'letting go stops the dial')
end

print(('%d checks, %d failed'):format(PASS, FAIL))
if FAIL > 0 then error('touch screen parity checks failed') end
