-- HGSS's always-present field touch panel. The idle art is ROM overlay 27's
-- screen 11; opening the menu uses the same state as pressing START.
local Assets = require("src.render.Assets")
local SecondScreen = require("src.ui.SecondScreen")
local Panel = {}
Panel.__index = Panel
function Panel.new(game) return setmetatable({ game = game }, Panel) end
function Panel:drawWatch()
  local rec = (self.game.data.gen4_hgss_menu_art or {}).idle
  if not rec then return end
  if not self.image then self.image = Assets.image(rec.path) end
  love.graphics.setColor(1, 1, 1, 1)
  if self.image then love.graphics.draw(self.image, 0, 0) end
end
function Panel:touchpressed(id, x, y)
  local px, py = SecondScreen.toLocal(self.game, x, y)
  if not px or px < 0 or py < 0 or px >= 256 or py >= 192 then return false end
  local top = self.game.stack:top()
  if not (top and top.player and top.map) then return false end
  self.game.secondScreenUp = true
  require("src.ui.Screens").push(self.game, "StartMenu")
  return true
end
return Panel
