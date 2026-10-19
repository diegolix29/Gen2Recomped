-- tools/gen5_move_anim_harness/bagui.lua
--
-- BAGUI=1: BW's own battle bag screen (src/ui/Gen5BattleBag.lua), driven the
-- way a player drives it -- the keys and taps on the touch screen -- with
-- each step drawn as the two screens, battle above, bag below, into
-- bagui_<TAG>.png:
--
--   the pockets, the cursor shown by a key, HP/PP RESTORE tapped, an item's
--   USE screen, back twice, POKe BALLS, the Poke Ball, USE -- the bag closes
--   and the throw starts (BAGUI_TICKS frames of it, BAGUI_STEP apart).
--   With DOUBLE=1 the USE is refused (two foes) and the message is shown.

local B = {}

function B.run(ctx)
  local Game, Data, battle, save = ctx.Game, ctx.Data, ctx.battle, ctx.save
  local StateStack = require("src.core.StateStack")
  local Bag = require("src.inventory.Bag")
  local SecondScreen = require("src.ui.SecondScreen")
  Game.stack = StateStack
  StateStack:init()
  table.insert(StateStack.states, battle)
  Game.save.inventory, Game.save.bagOrder = {}, nil
  for _, id in ipairs({ 17, 26, 18, 23, 4, 3, 2, 57, 58, 56 }) do Bag.add(Game.save, id, 5, Data) end
  local pressed = {}
  Game.input = {
    wasPressed = function(_, k) return pressed[k] == true end,
    isDown = function() return false end,
    wasReleased = function() return false end,
    isPressed = function() return false end,
  }
  SecondScreen.toLocal = function(_, x, y) return x, y end
  local W, H = 256, 192
  local shots = {}
  local function snap(tag)
    local c = love.graphics.newCanvas(W, H * 2 + 4)
    love.graphics.push("all"); love.graphics.setCanvas(c); love.graphics.clear(0.1, 0.1, 0.1, 1)
    love.graphics.push(); pcall(battle.draw, battle); love.graphics.pop()
    local top = StateStack:top()
    if top and top.drawBottom then
      love.graphics.push(); love.graphics.translate(0, H + 4)
      love.graphics.setScissor(0, H + 4, W, H)
      local ok, err = pcall(top.drawBottom, top)
      if not ok then print("[bagui] draw raised: " .. tostring(err)) end
      love.graphics.setScissor()
      love.graphics.pop()
    end
    love.graphics.pop()
    shots[#shots + 1] = { canvas = c, tag = tag }
    print(("[bagui] %s: %s"):format(tag, StateStack:describeAll()))
  end
  local function tick(n, key)
    for i = 1, n or 1 do
      pressed = {}
      if key and i == 1 then pressed[key] = true end
      local ok, err = pcall(StateStack.update, StateStack, 1 / 60)
      if not ok then print("[bagui] update raised: " .. tostring(err)) return end
    end
  end
  local function tap(x, y)
    local top = StateStack:top()
    if top and top.touchpressed then top:touchpressed("mouse", x, y) end
  end
  battle:openItems()
  tick(30)
  local bag = StateStack:top()
  print("[bagui] bag screen: " .. StateStack.describe(bag))
  snap("pockets")
  tick(1, "right"); tick(1, "right"); snap("keys: cursor on POKE BALLS")
  tap(40, 40); tick(3); snap("HP/PP pressed"); tick(10); snap("HP/PP RESTORE")
  tap(40, 30); tick(10); snap("Potion: USE screen")
  tap(230, 170); tick(10); tap(230, 170); tick(10)
  tap(180, 40); tick(10); snap("POKE BALLS")
  local row
  for i = 1, 6 do local r = bag.itemAt and bag:itemAt(i) if r and tonumber(Data.items[r.id].id) == 4 then row = i end end
  local r = bag.R and bag.R.pocket[row or 1]
  if r then tap(r[1] + 20, r[2] + 20); tick(10) end
  snap("Poke Ball: USE screen")
  tap(100, 170); tick(3); snap("USE pressed"); tick(10)
  snap(bag.message and "refused" or "USE: the throw")
  if bag.message then
    tick(1, "a"); tick(4); snap("message cleared")
  else
    local step = tonumber(os.getenv("BAGUI_STEP") or "20")
    for i = 1, tonumber(os.getenv("BAGUI_TICKS") or "400") do
      pressed = { a = (i % 30 == 0) }
      pcall(StateStack.update, StateStack, 1 / 60)
      if i % step == 0 and #shots < 40 then snap(("throw t%d"):format(i)) end
    end
  end
  local cols = 6
  local rows = math.max(1, math.ceil(#shots / cols))
  local sheet = love.graphics.newCanvas(cols * W, rows * (H * 2 + 4 + 12))
  love.graphics.push("all"); love.graphics.setCanvas(sheet); love.graphics.clear(0.1, 0.1, 0.1, 1)
  for k, s in ipairs(shots) do
    local cx, cy = ((k - 1) % cols) * W, math.floor((k - 1) / cols) * (H * 2 + 4 + 12)
    love.graphics.draw(s.canvas, cx, cy + 12)
    love.graphics.print(s.tag, cx + 2, cy)
  end
  love.graphics.pop()
  save(sheet, ("bagui_%s.png"):format(os.getenv("TAG") or "bw"))
end

return B
