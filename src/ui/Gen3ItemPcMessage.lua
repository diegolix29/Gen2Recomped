-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FireRed Item PC message overlay. item_pc.c keeps the Item PC alive and uses
-- one of two transient lower windows rather than opening the generic dialogue:
-- withdraw results use sSubwindowTemplates[2] at (6,15), 23x4, while the
-- no-party GIVE refusal uses sWindowTemplates[5] at (2,15), 26x4.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")

local Gen3ItemPcMessage = {}
Gen3ItemPcMessage.__index = Gen3ItemPcMessage
Gen3ItemPcMessage.isOpaque = false

function Gen3ItemPcMessage.new(game, itemPc, text, onDone, kind)
  local self = setmetatable({}, Gen3ItemPcMessage)
  self.game = game
  self.itemPc = itemPc
  self.text = tostring(text or "")
  self.onDone = onDone
  self.kind = kind or "result"
  if itemPc and itemPc.setTransientWindow then itemPc:setTransientWindow("message") end
  return self
end

function Gen3ItemPcMessage:messageBox()
  if self.kind == "noParty" then
    return self.itemPc and self.itemPc:box("message")
           or { x = 16, y = 120, width = 208, height = 32 }
  end
  return self.itemPc and self.itemPc:subBox("result")
         or { x = 48, y = 120, width = 184, height = 32 }
end

local function finish(self)
  Sound.play(self.game.data, "Press_AB")
  if self.itemPc and self.itemPc.setTransientWindow then
    self.itemPc:setTransientWindow(nil)
  end
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen3ItemPcMessage:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("a") or input:wasPressed("b") then finish(self) end
end

function Gen3ItemPcMessage:keypressed(key)
  if key == "a" or key == "b" then finish(self) end
end

function Gen3ItemPcMessage:draw()
  local b = self:messageBox()
  Font.drawBox(math.floor(b.x / 8), math.floor(b.y / 8),
               math.floor(b.width / 8), math.floor(b.height / 8))
  love.graphics.setColor(0, 0, 0, 1)
  local y = b.y + 2
  for line in (self.text .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(line, b.x, y)
    y = y + 14
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ItemPcMessage
