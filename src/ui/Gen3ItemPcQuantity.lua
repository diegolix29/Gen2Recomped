-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FireRed Item PC quantity picker (item_pc.c).
--
-- ItemPc_WithdrawMultipleInitWindow uses subwindow 1 at (6,15), 16x4 for the
-- question, then window 3 at (24,15), 5x4 for the value.  The small-font
-- "×NNN" starts at +8,+10 inside window 3.  This is deliberately separate
-- from QuantityBox: that state is the Game Boy/portable generic selector at
-- (15,9), which is correct elsewhere and visibly wrong on this 240x160 screen.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local Gen3ItemPcQuantity = {}
Gen3ItemPcQuantity.__index = Gen3ItemPcQuantity
Gen3ItemPcQuantity.isOpaque = false

function Gen3ItemPcQuantity:uiSize() return 240, 160 end
function Gen3ItemPcQuantity:wantsFillScale() return true end
function Gen3ItemPcQuantity:wantsEdgeBleed() return false end

function Gen3ItemPcQuantity.new(game, itemPc, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3ItemPcQuantity)
  self.game = game
  self.itemPc = itemPc
  self.max = math.max(1, tonumber(opts.max) or 99)
  self.qty = math.min(math.max(1, tonumber(opts.start) or 1), self.max)
  self.onDone = opts.onDone
  self.itemName = tostring(opts.itemName or "")
  self.verb = tostring(opts.verb or "WITHDRAW"):upper()
  if itemPc and itemPc.setTransientWindow then itemPc:setTransientWindow("quantity") end
  return self
end

local function finish(self, qty)
  if self.itemPc and self.itemPc.setTransientWindow then
    self.itemPc:setTransientWindow(nil)
  end
  self.game.stack:pop()
  if self.onDone then self.onDone(qty) end
end

local function wrap(v, max)
  if v < 1 then return max end
  if v > max then return 1 end
  return v
end

function Gen3ItemPcQuantity:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("up") then
    self.qty = wrap(self.qty + 1, self.max)
  elseif input:wasPressed("down") then
    self.qty = wrap(self.qty - 1, self.max)
  elseif input:wasPressed("a") then
    Sound.play(self.game.data, "Press_AB")
    finish(self, self.qty)
  elseif input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    finish(self, nil)
  end
end

function Gen3ItemPcQuantity:keypressed(key)
  if key == "up" then self.qty = wrap(self.qty + 1, self.max); return end
  if key == "down" then self.qty = wrap(self.qty - 1, self.max); return end
  if key == "a" then
    return finish(self, self.qty)
  end
  if key == "b" then
    return finish(self, nil)
  end
end

local function drawLines(text, x, y)
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(line, x, y)
    y = y + 14
  end
end

function Gen3ItemPcQuantity:draw()
  local q = self.itemPc and self.itemPc:box("quantity")
            or { x = 192, y = 120, width = 40, height = 32 }
  local prompt = self.itemPc and self.itemPc:subBox("quantityPrompt")
                 or { x = 48, y = 120, width = 128, height = 32 }
  local styles = self.game.data.font and self.game.data.font.uiTextStyles or {}

  -- sSubwindowTemplates[1], the question beside the number.
  if self.itemPc and self.itemPc.drawContentFrame then
    self.itemPc:drawContentFrame(prompt, "standard")
  else
    Font.drawBox(prompt.x / 8 - 1, prompt.y / 8 - 1,
                 prompt.width / 8 + 2, prompt.height / 8 + 2, 1)
  end
  love.graphics.setColor(0, 0, 0, 1)
  if styles.dark then Font.pushStyle(styles.dark) end
  local verb = self.verb == "DEPOSIT" and Strings("Deposit how many")
               or Strings("Withdraw how many")
  drawLines(verb .. "\n" .. self.itemName .. Strings("(s)?"),  -- strings: line-break glue between translated parts
            prompt.x, prompt.y + 2)

  -- sWindowTemplates[3] + ItemPc_AddTextPrinterParameterized(..., 8, 10).
  if self.itemPc and self.itemPc.drawContentFrame then
    self.itemPc:drawContentFrame(q)
  else
    Font.drawBox(math.floor(q.x / 8) - 1, math.floor(q.y / 8) - 1,
                 math.floor(q.width / 8) + 2, math.floor(q.height / 8) + 2, 1)
  end
  love.graphics.setColor(0, 0, 0, 1)
  local faced = Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
  Font.draw(("×%03d"):format(self.qty), q.x + 8, q.y + 10)
  if faced then Font.popFace() end
  if styles.dark then Font.popStyle() end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ItemPcQuantity
