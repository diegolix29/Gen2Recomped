-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FireRed item_pc.c's per-item submenu: WITHDRAW / GIVE / CANCEL.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3ItemPcSubmenu = {}
Gen3ItemPcSubmenu.__index = Gen3ItemPcSubmenu
Gen3ItemPcSubmenu.isOpaque = false

local ENTRIES = {
  { label = "WITHDRAW", kind = "withdraw" },
  { label = "GIVE", kind = "give" },
  { label = "CANCEL", kind = "cancel" },
}
local SELECTED = { x = 48, y = 120, width = 112, height = 32 }

function Gen3ItemPcSubmenu.new(game, itemPc, itemName, onPick)
  local self = setmetatable({
    game = game, itemPc = itemPc, itemName = itemName or "",
    onPick = onPick, index = 1,
  }, Gen3ItemPcSubmenu)
  if itemPc and itemPc.setTransientWindow then itemPc:setTransientWindow("submenu") end
  return self
end

function Gen3ItemPcSubmenu:move(delta)
  self.index = math.max(1, math.min(#ENTRIES, self.index + delta))
  Sound.play(self.game.data, "Press_AB")
end

function Gen3ItemPcSubmenu:close(kind)
  if self.itemPc and self.itemPc.setTransientWindow then
    self.itemPc:setTransientWindow(nil)
  end
  self.game.stack:pop()
  if kind and kind ~= "cancel" and self.onPick then self.onPick(kind) end
end

function Gen3ItemPcSubmenu:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("up") then return self:move(-1) end
  if input:wasPressed("down") then return self:move(1) end
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    return self:close("cancel")
  end
  if input:wasPressed("a") then
    Sound.play(self.game.data, "Press_AB")
    return self:close(ENTRIES[self.index].kind)
  end
end

function Gen3ItemPcSubmenu:keypressed(key)
  if key == "up" then return self:move(-1) end
  if key == "down" then return self:move(1) end
  if key == "b" then return self:close("cancel") end
  if key == "a" then return self:close(ENTRIES[self.index].kind) end
end

function Gen3ItemPcSubmenu:draw()
  local b = self.itemPc and self.itemPc:box("submenu")
            or { x = 176, y = 104, width = 56, height = 48 }
  Font.drawBox(math.floor(b.x / 8), math.floor(b.y / 8),
               math.floor(b.width / 8), math.floor(b.height / 8))
  love.graphics.setColor(0, 0, 0, 1)
  for i, entry in ipairs(ENTRIES) do
    local y = b.y + 2 + (i - 1) * 16
    Font.draw(Strings(entry.label), b.x + 8, y)
    if i == self.index then Font.drawCode(Theme.cursor, b.x, y) end
  end

  Font.drawBox(SELECTED.x / 8, SELECTED.y / 8,
               SELECTED.width / 8, SELECTED.height / 8)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("%s is selected.", self.itemName),
            SELECTED.x, SELECTED.y + 2)
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ItemPcSubmenu
