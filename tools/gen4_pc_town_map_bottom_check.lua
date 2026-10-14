-- tools/gen4_pc_town_map_bottom_check.lua -- the bottom screens of Platinum's
-- PC storage (ov19_021DCF88 / ov19_021DEC04, src/ui/Gen4BoxMenu.lua) and Town
-- Map (graphics.c, src/ui/Gen4TownMap.lua), as logic (no LOVE, no cache):
--
--   * PC: the dial ring's steps (touch_dial.c: 0 / 1 / 2 past 4.219 / 33.75
--     degrees, sign by the dial's side); a corner tap opens the BOX dial, the
--     open runs press -> SUB_1 scroll -> cover fade -> items; a turn of one
--     step moves the offset and the box is jumped to 20 frames after the
--     stylus leaves; the pad closes a dial; MOVE ITEMS has no markings dial;
--     the markings filter mask (SetMonSpriteTransparencyMask) and which icons
--     it fades (ov19_021DA63C); the arc's end stops; compare mode's slots
--   * Town Map: the map history ring (overworld_map_history.c) and what the
--     map shows of it (TownMapContext_Init / LoadLocationHistory); the zoom
--     button's switch both ways and the touch rectangle back
--
--   python tools/run_lua_check.py tools/gen4_pc_town_map_bottom_check.lua

package.path = "./?.lua;" .. package.path
package.loaded['src.render.Font'] = { width = function(s) return #tostring(s) * 6 end, fit = function(s) return s end,
  pushStyle = function() end, popStyle = function() end, draw = function() end, drawBox = function() end,
  drawCode = function() end, drawDialogueBox = function() end }
package.loaded['src.core.Logger'] = { warn = function() end, info = function() end }
package.loaded['src.render.Assets'] = { image = function() return nil end, register = function() end }
package.loaded['src.ui.Theme'] = { cursor = 0 }
package.loaded['src.core.Sound'] = { play = function() end, playCry = function() end }
package.loaded['src.ui.SecondScreen'] = { mode = function() return "display" end, stowed = function() return false end,
  combined = function() return false end, draw = function() end, toLocal = function(_, x, y) return x, y end }

local PASS, FAIL = 0, 0
local function check(cond, what)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print("FAIL: " .. what) end
end
local function keys(...)
  local set = {}
  for _, k in ipairs({ ... }) do set[k] = true end
  return { wasPressed = function(_, k) return set[k] or false end, isDown = function(_, k) return set[k] or false end }
end
local idle = keys()

-- ------------------------------------------------------------------- PC --
local Boxes = require('src.pokemon.Boxes')
local PC = require('src.ui.Gen4BoxMenu')
local function pcGame(mode)
  local save = { party = { { species = 25, level = 5, hp = 10 } }, options = {}, inventory = {}, currentBox = 1 }
  Boxes.ensure(save)
  save.boxes[1][1] = { species = 387, level = 5, markings = 1, item = 17 }
  save.boxes[1][2] = { species = 390, level = 5, markings = 0 }
  save.boxes[1][3] = { species = 393, level = 5, markings = 5 }
  local game = { data = { text = {}, pokemon = {}, items = {} }, save = save, input = idle, stack = { pop = function() end } }
  return PC.new(game, { mode = mode or 'move' }), game
end
local function frames(s, n) for _ = 1, n do s:update(1 / 60) end end

check(PC.dialSteps(300, 303, 1) == 0, 'under 4.219 degrees: no step')
check(PC.dialSteps(300, 310, 1) == 1 and PC.dialSteps(300, 340, 1) == 2, '4.219 / 33.75 degrees: one, two steps')
check(PC.dialSteps(300, 290, 1) == -1 and PC.dialSteps(300, 310, -1) == -1, 'the sign: turn and side')
local x0, y0 = PC.arcPoint(0)
local x7, y7 = PC.arcPoint(7)
check(x0 == 16 and y0 == -16 and x7 == 106 and y7 == 200, 'the arc ends (Unk_ov19_021E0264 0 / 7)')

local s, game = pcGame()
s:touchpressed('t', 10, 180)
check(s.subState.dial == PC.DIAL_BOX and s.subState.task, 'a tap on the left corner opens the BOX dial')
frames(s, 20)
check(s.subState.sub1 ~= 0 and s.subState.sub1 > -96, 'after the press, SUB_1 scrolls')
frames(s, 20)
check(s.subState.sub1 == -96 and s.subState.cover == -128, 'SUB_1 at -96, SUB_2 at -128')
frames(s, 80)
check(not s:subBusy() and s.subState.names, 'items in, box names up')
-- a one-step turn in the ring about (0, 192), then off the ring
s:touchpressed('t', 45, 130)
s:touchmoved('t', 65, 160)
check(s.subState.offset == 1 and s.subState.scroll, 'one step clockwise: the dial offers box 2')
s:touchreleased('t')
frames(s, 10)
check(game.save.currentBox == 1, 'no jump before 20 frames')
frames(s, 20)
check(game.save.currentBox == 2, '...then box 2 (TOUCH_BOX_JUMP_WAIT_FOR_INPUT_OR_JUMP)')
frames(s, 40)
game.input = keys('a'); s:update(1 / 60); game.input = idle
check(s.subState.dial == PC.DIAL_NONE and s.subState.task, 'A closes the dial')
frames(s, 40)
check(s.subState.sub1 == 0 and not s.subState.task, 'closed: SUB_1 back at 0')

-- the markings dial and its filter
game.save.currentBox = 1
s:touchpressed('u', 250, 180); s:touchreleased('u')
frames(s, 160)
check(s.subState.dial == PC.DIAL_MARKS and not s:subBusy(), 'the right corner opens the markings dial')
s:touchpressed('u', 184, 104); s:touchreleased('u')   -- button 3 = kind 2 = circle
check(s:markMask() == 2, 'circle: mask bit 1')
check(not s:iconFaded(game.save.boxes[1][1]) and s:iconFaded(game.save.boxes[1][2]), 'unmarked Pokemon fade')
s:touchpressed('u', 163, 134); s:touchreleased('u')   -- kind 1 = ITEM
check(s:markMask() == 3 and s:iconFaded(game.save.boxes[1][3]), 'ITEM: no item fades too')
s:touchpressed('u', 152, 168); s:touchreleased('u')   -- OFF
check(s:markMask() == 0 and s:markLit(0), 'OFF clears the filter and lights')

-- MOVE ITEMS
local it = pcGame('items')
it:touchpressed('v', 250, 180)
check(it.subState.dial == PC.DIAL_NONE, 'MOVE ITEMS: no markings dial')
check(it:iconFaded(it.game.save.boxes[1][2]) and not it:iconFaded(it.game.save.boxes[1][1]), 'MOVE ITEMS fades the itemless')

-- compare
local c = pcGame('compare')
c.row, c.col = 1, 1
check(c:compareMon(0) == c.game.save.boxes[1][1] and c:compareMon(1) == nil, 'compare: the cursor fills the active slot')
c:touchpressed('w', 10, 180); c:touchreleased('w')
c.col = 2
check(c.compare.slot == 1 and c:compareMon(0) == c.game.save.boxes[1][1] and c:compareMon(1) == c.game.save.boxes[1][2],
  'the left button sets it; the cursor now fills the right')
c:touchpressed('w', 128, 178); c:touchreleased('w')
check(c.compare.mode == 1, 'the middle button turns the page')

-- ------------------------------------------------------------- Town Map --
local TM = require('src.ui.Gen4TownMap')
local save = {}
for _, p in ipairs({ { 3, 27 }, { 3, 27 }, { 3, 26 }, { 4, 25 }, { 3, 26 }, { 4, 23 } }) do TM.pushHistory(save, p[1], p[2], 1) end
check(save.gen4MapHistory.pointer == 5, 'a push only when the cell changes')
local hist = TM.historyEntries(save, 9, 9)
check(#hist == 3 and hist[1].x == 3 and hist[1].z == 26 and hist[3].x == 3 and hist[3].z == 27,
  'the entries before the current one, newest first, one per cell')
check(#TM.historyEntries(save, 3, 26) == 2, 'the player\'s own cell is left out')
check(#TM.historyEntries({}, 0, 0) == 0, 'no record, no dots')

local tgame = { data = { gen4_town_map = { blocks = {}, flyLocations = {}, firstArrival = {} },
  gen4_town_map_ink = { zoomHit = { { 100, 0, 255 } } }, text = {} }, save = { flags = {} },
  input = idle, stack = { pop = function() end } }
local m = TM.new(tgame, { mode = 'map' })
m:touchpressed('a', 10, 50)
check(not m.switching, 'a tap on colours 1 / 4 is not the button')
m:touchreleased('a')
m:touchpressed('a', 128, 100)
check(m.switching and m.switching.to, 'a tap elsewhere presses the zoom button')
for _ = 1, 40 do m:update() end
check(m.zoomed and not m.switching, 'the zoomed map is up')
m:touchreleased('a')
m:touchpressed('a', 20, 20)
check(not m.switching, 'zoomed: only the button rectangle goes back')
m:touchreleased('a')
m:touchpressed('a', 120, 100)
for _ = 1, 20 do m:update() end
check(not m.zoomed, 'and it does')
local wall = TM.new(tgame, { mode = 'wall' })
wall:touchpressed('b', 128, 100)
check(not wall.switching, 'the wall map takes no touch')

print(("%d checks, %d failed"):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
