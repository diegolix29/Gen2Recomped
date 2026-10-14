-- THE BATTLE ARCADE'S GAME BOARD (src/applications/frontier/battle_arcade/
-- main.c), as a text grid: sixteen panels (4 x 4) dealt by
-- src/script/Gen4BattleArcade.lua, the cursor stepping round them --
-- one panel every sCursorMoveFrames[speed] of the app's 30 fps frames, or to
-- a random panel each step after RANDOMIZE_CURSOR -- until A stops it, or the
-- thirty seconds run out. The panel it stops on is the event; it stays lit a
-- second (the app's 30 frames) before the screen closes.
--
-- opts = { arcade, onDone(effect, cursorPos) }

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local S = {}
S.__index = S
S.isOpaque = true

function S:uiSize() return 256, 192 end
function S:wantsFillScale() return true end

-- what each panel says (the board's icons, in words)
S.LABELS = {
  [0] = "Foe HP-", "Foe PSN", "Foe PAR", "Foe BRN", "Foe SLP", "Foe FRZ", "Foe Berry", "Foe Item", "Foe Lv+3",
  "Ally HP-", "Ally PSN", "Ally PAR", "Ally BRN", "Ally SLP", "Ally FRZ", "Ally Berry", "Ally Item", "Ally Lv+3",
  "Sunny", "Rainy", "Sandy", "Hail", "Foggy", "Trick Room", "Speed Up", "Slow Down", "Random", "Swap",
  "1 BP", "No Battle", "No Event", "3 BP",
}

-- the app runs at 30 fps; this screen ticks at 60
local APP = 2
S.START_DELAY = (10 + 24 * 3) * APP     -- the panels turning over
S.TIMEOUT = 30 * 30 * APP               -- rouletteTimer
S.HOLD = 30 * APP

function S.new(game, opts)
  local f = opts.arcade
  return setmetatable({ game = game, data = game.data, arcade = f, onDone = opts.onDone,
    cursor = f.startCursor or 0, timer = 0, wait = S.START_DELAY, left = S.TIMEOUT }, S)
end

function S:stepFrames()
  local A = require("src.script.Gen4BattleArcade")
  return (A.CURSOR_FRAMES[self.arcade.rouletteSpeed or 3] or 4) * APP
end

function S:update()
  if self.closed then return end
  local input = self.game.input
  if self.wait > 0 then self.wait = self.wait - 1 return end
  if self.result then
    self.hold = (self.hold or S.HOLD) - 1
    if self.hold <= 0 then
      self.closed = true
      if self.game.stack:top() == self then self.game.stack:pop() end
      local f = self.arcade
      if self.onDone then self.onDone(f.grid[self.cursor + 1], self.cursor) end
    end
    return
  end
  -- UpdateCursorPosition
  self.timer = self.timer + 1
  if self.timer >= self:stepFrames() then
    self.timer = 0
    if self.arcade.boardRandomized then self.cursor = love.math.random(0, 65535) % 16
    else self.cursor = (self.cursor + 1) % 16 end
    Sound.play(self.data, "Select")
  end
  self.left = self.left - 1
  if (input and input:wasPressed("a")) or self.left <= 0 then
    self.result = true
    Sound.play(self.data, "Press_AB")
  end
end

function S:draw()
  local g = love.graphics
  local f = self.arcade
  g.setColor(0.10, 0.08, 0.22, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  for i = 0, 15 do
    local x, y = 8 + (i % 4) * 60, 8 + math.floor(i / 4) * 36
    local lit = (i == self.cursor) and self.wait == 0
    if lit then g.setColor(1, 0.85, 0.2, 1) else g.setColor(0.25, 0.22, 0.45, 1) end
    g.rectangle("fill", x, y, 56, 32)
    g.setColor(lit and 0 or 1, lit and 0 or 1, lit and 0 or 1, 1)
    local label = (self.wait > 0) and "?" or (S.LABELS[f.grid[i + 1]] or "?")
    Font.draw(label, x + 2, y + 10)
  end
  g.setColor(1, 1, 1, 1)
  if self.result then
    Font.draw(Strings("%s!", S.LABELS[f.grid[self.cursor + 1]] or "?"), 8, 160)
  else
    Font.draw(Strings("A: STOP  %d", math.ceil(self.left / 60)), 8, 160)
  end
end

return S
