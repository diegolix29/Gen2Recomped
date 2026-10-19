-- tools/gen5_move_anim_harness/bag.lua
--
-- BAG=4,17: the battle bag, used for real. The battle sits on the state stack,
-- ITEM opens the bag (BattleState:openItems -> the generation's bag screen),
-- each item is used through BagMenu.useItem exactly as the bag's USE does,
-- and the stack is pumped with A presses (the party picker takes its first
-- row) until the battle is back at its command menu. Every text box and
-- battle line is printed; BAG_STEP frames apart the screen goes into
-- bag_<TAG>.png.
--
--   BAG=4            throw a Poke Ball           BAG=17,18  Potion, Antidote
--   BAG_HURT=1       the lead starts at 1/3 HP and poisoned (for medicine)
--   BAG_TICKS=n      ticks per item (default 1500)
--   BAG_STEP=n       draw every n ticks (default 12)

local B = {}

function B.run(ctx)
  local Game, Data, battle, shot, save = ctx.Game, ctx.Data, ctx.battle, ctx.shot, ctx.save
  local StateStack = require("src.core.StateStack")
  local BagMenu = require("src.ui.BagMenu")
  local Bag = require("src.inventory.Bag")
  Game.stack = StateStack
  StateStack:init()
  table.insert(StateStack.states, battle)
  local W, H = 256, 192
  local press = false
  Game.input = {
    wasPressed = function(_, k) return press and k == "a" end,
    isDown = function() return false end,
    wasReleased = function() return false end,
    isPressed = function() return false end,
  }
  -- what is said
  local TextBox = require("src.render.TextBox")
  local realNew = TextBox.new
  TextBox.new = function(game, text, ...)
    print(("[bag] textbox: %s"):format(tostring(text)))
    return realNew(game, text, ...)
  end
  local realSay = battle.say
  battle.say = function(self_, text, ...)
    print(("[bag] battle says: %s"):format(tostring(text)))
    return realSay(self_, text, ...)
  end
  local realSayNext = battle.sayNext
  battle.sayNext = function(self_, text, ...)
    print(("[bag] battle says next: %s"):format(tostring(text)))
    return realSayNext(self_, text, ...)
  end
  local lead = Game.save.party[1]
  if os.getenv("BAG_HURT") and lead then
    lead.hp = math.max(1, math.floor((lead.maxHp or lead.stats and lead.stats.hp or 30) / 3))
    if os.getenv("BAG_PSN") then lead.status = "PSN" end
    if battle.player and battle.player.mon == lead then battle.player.hp = lead.hp end
  end
  local shots = {}
  local step = tonumber(os.getenv("BAG_STEP") or "12")
  local function snap(tag)
    if #shots >= 96 then return end
    local c = love.graphics.newCanvas(W, H)
    love.graphics.push("all"); love.graphics.setCanvas(c); love.graphics.clear(0, 0, 0, 1)
    local okD, errD = pcall(StateStack.draw, StateStack)
    love.graphics.pop()
    if not okD then print("[bag] draw raised: " .. tostring(errD)) end
    shots[#shots + 1] = { canvas = c, tag = tag }
  end
  local function pump(n, label, stopAtMenu, quiet)
    for i = 1, n do
      local atMenu = StateStack:top() == battle and battle.phase == "menu"
      local inBag = StateStack.describe(StateStack:top()):find("BagMenu") ~= nil
      press = (not quiet) and (not atMenu) and (not inBag) and (i % 20 == 0)
      local okU, errU = pcall(StateStack.update, StateStack, 1 / 60)
      if not okU then print("[bag] update raised: " .. tostring(errU)); return false end
      if battle.gen4Ball and battle.updateGen4Ball and StateStack:top() ~= battle then
        -- (the battle's own update ticks it when it is on top)
      end
      if i % step == 0 then snap(("%s t%d"):format(label, i)) end
      if stopAtMenu and StateStack:top() == battle and battle.phase == "menu" and i > 30 then return true end
      if battle.result and battle.afterQueue == "finish" and #battle.queue == 0 and not battle.current then
        return true
      end
    end
    return true
  end
  for id in tostring(os.getenv("BAG")):gmatch("%d+") do
    id = tonumber(id)
    local def = Data.items[id]
    Bag.add(Game.save, id, 5)
    print(("[bag] === item %d %s (fieldUse=%s battleUse=%s pocket mask=%s) ==="):format(
      id, def and def.name or "?", tostring(def and def.fieldUse), tostring(def and def.battleUse),
      tostring(def and (def.battleMask or require('src.inventory.Gen5Items').mask(def)))))
    battle:openItems()
    pump(40, "open", false, true)
    local bag = StateStack:top()
    print("[bag] bag screen: " .. StateStack.describe(bag))
    snap("bag " .. id)
    local shim = bag ~= battle and bag or { items = {}, index = 1, close = function() end }
    local okU, errU = pcall(BagMenu.useItem, Game, battle, id, shim)
    if not okU then print("[bag] useItem raised: " .. tostring(errU)) end
    print("[bag] after use: " .. StateStack:describeAll())
    snap("used " .. id)
    pump(tonumber(os.getenv("BAG_TICKS") or "1500"), "item " .. id, true)
    -- a refusal leaves the bag up: back out of it to the command menu
    local guard = 0
    while StateStack:top() ~= battle and guard < 8 do
      local top = StateStack:top()
      if top and top.close then pcall(top.close, top) end
      if StateStack:top() == top then StateStack:pop() end
      guard = guard + 1
    end
    pump(120, "back " .. id, true)
    print(("[bag] end: phase=%s result=%s stack=%s left=%s foeHP=%s leadHP=%s/%s status=%s"):format(
      tostring(battle.phase), tostring(battle.result), StateStack:describeAll(),
      tostring(Bag.count and Bag.count(Game.save, id) or (Game.save.inventory or {})[id]),
      tostring(battle.enemy and battle.enemy.hp), tostring(lead and lead.hp),
      tostring(lead and (lead.maxHp or (lead.stats and lead.stats.hp))), tostring(lead and lead.status)))
    if battle.result then
      local caught = battle.result == "caught"
      local last = Game.save.party[#Game.save.party]
      print(("[bag] battle over: %s; party %d, last ball=%s"):format(tostring(battle.result), #Game.save.party,
        tostring(last and (last.ball or last.pokeball or last.caughtBall))))
      break
    end
  end
  local cols = 8
  local rows = math.max(1, math.ceil(#shots / cols))
  local sheet = love.graphics.newCanvas(cols * W, rows * (H + 12))
  love.graphics.push("all"); love.graphics.setCanvas(sheet); love.graphics.clear(0.1, 0.1, 0.1, 1)
  for k, s in ipairs(shots) do
    local cx, cy = ((k - 1) % cols) * W, math.floor((k - 1) / cols) * (H + 12)
    love.graphics.draw(s.canvas, cx, cy + 12)
    love.graphics.print(s.tag, cx + 2, cy)
  end
  love.graphics.pop()
  save(sheet, ("bag_%s.png"):format(os.getenv("TAG") or "bw"))
end

return B
