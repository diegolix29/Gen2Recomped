-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SHELL EVERY MINIGAME RUNS IN: how to play -> playing -> paused ->
-- results, the header (score, the game's own counters, pause), and one input
-- vocabulary for every device.
--
-- A game module is a table with
--   id, title, blurb, howTo = { lines }
--   new(ctx, purse) -> game          (ctx: minigames/Context, purse: Rewards)
-- and the game it makes has
--   game.score, game.time, game.over (set when the run ends by itself)
--   game:update(dt)
--   game:input(action, x, y)         action "a" (tap / click / A / Space /
--                                    Enter), "up" "down" "left" "right";
--                                    x, y only for a pointer
--   game:draw(x, y, w, h, gfx, fonts, s)
--   game:hud() -> { { label, value }, ... }   the header's counters
--   game:wattsFor() -> watts the score is worth (before the caps)
--   game:summary() -> { lines }      for the results card
--
-- Input, by device:
--   touch / mouse   a tap is "a" at that point (the pause button excepted)
--   keyboard        Space Enter Z X -> "a"; arrows / WASD -> directions;
--                   Esc P Backspace -> pause (or back)
--   gamepad         A -> "a" (the Nintendo layout honoured via GamepadMap),
--                   d-pad -> directions, B / Start -> pause (or back)
-- A frame's dt is clamped, so a phone waking up does not teleport a runner.

local Rewards = require("src.pokewalker.minigames.Rewards")

local B = {}
B.__index = B

B.MAX_DT = 1 / 20

function B.new(module, ctx, st, opts)
  local self = setmetatable({ module = module, ctx = ctx, st = st, opts = opts or {},
                              phase = "intro", t = 0, hits = nil, focus = 1 }, B)
  self.purse = Rewards.newPurse(st, module.id)
  self.game = module.new(ctx, self.purse)
  return self
end

function B:start()
  if self.phase == "intro" then self.phase = "play" end
end

function B:pause() if self.phase == "play" then self.phase = "pause"; self.focus = 1 end end
function B:resume() if self.phase == "pause" then self.phase = "play" end end

-- the run is over (by itself, or quit from pause): pay up once
function B:finish()
  if self.result then return self.result end
  local g = self.game
  g.over = g.over or "quit"
  if g.beforeSettle then g:beforeSettle() end
  local watts = g.wattsFor and g:wattsFor() or 0
  self.result = Rewards.settle(self.purse, g.score or 0, watts, g.time or 0)
  self.phase = "results"
  self.focus = 1
  if self.opts.onFinish then pcall(self.opts.onFinish, self, self.result) end
  return self.result
end

function B:update(dt)
  dt = math.min(math.max(0, dt or 0), B.MAX_DT)
  self.t = self.t + dt
  if self.phase == "play" then
    self.game:update(dt)
    if self.game.over then self:finish() end
  elseif self.game.idle then
    self.game:idle(dt)
  end
end

-- the shell's own menu (pause / results): a list of { label, fn, kind }
function B:menu()
  if self.phase == "pause" then
    return {
      { "Resume", function() self:resume() end, "accent" },
      { "End run", function() self:finish() end, "danger" },
    }
  elseif self.phase == "results" then
    return {
      { "Play again", function() if self.opts.onAgain then self.opts.onAgain(self) end end, "accent" },
      { "Back to games", function() if self.opts.onExit then self.opts.onExit(self) end end },
    }
  end
  return nil
end

-- ------------------------------------------------------------ input

-- the one entry for every device: action as in the header comment
function B:action(a, x, y)
  if self.phase == "intro" then
    if a == "back" then if self.opts.onExit then self.opts.onExit(self) end return true end
    if a == "a" then self:start() end
    return true
  end
  if self.phase == "play" then
    if a == "back" or a == "pause" then self:pause() return true end
    self.game:input(a, x, y)
    return true
  end
  local m = self:menu()
  if not m then return false end
  if a == "back" or a == "pause" then
    if self.phase == "pause" then self:resume() elseif self.opts.onExit then self.opts.onExit(self) end
    return true
  end
  if a == "up" or a == "left" then self.focus = (self.focus - 2) % #m + 1 return true end
  if a == "down" or a == "right" then self.focus = self.focus % #m + 1 return true end
  if a == "a" and x == nil then
    local item = m[self.focus]
    if item then item[2]() end
    return true
  end
  return true
end

function B:pointer(x, y)
  self.padFocus = false
  local Gfx = require("src.pokewalker.minigames.Gfx")
  if Gfx.press(self.hits, x, y) then return true end
  if self.phase == "intro" or self.phase == "play" then return self:action("a", x, y) end
  return true
end

B.KEYS = {
  space = "a", ["return"] = "a", kpenter = "a", z = "a", x = "a",
  up = "up", w = "up", down = "down", s = "down", left = "left", a = "left", right = "right", d = "right",
  escape = "pause", p = "pause", backspace = "back",
}

function B:key(k)
  local a = B.KEYS[k]
  if not a then return false end
  if a == "pause" and self.phase ~= "play" then a = "back" end
  self.padFocus = true
  return self:action(a)
end

-- an SDL gamepad button name, through GamepadMap's face-button layout
function B.padAction(button)
  local mapped = button
  pcall(function() mapped = require("src.core.GamepadMap").mapGamepadButton(button) or button end)
  if button == "dpup" then return "up" elseif button == "dpdown" then return "down"
  elseif button == "dpleft" then return "left" elseif button == "dpright" then return "right" end
  if button == "start" then return "pause" end
  if mapped == "a" then return "a" end
  if mapped == "b" then return "back" end
  if mapped == "x" or mapped == "y" then return "alt" end
  if button == "back" then return "back" end
  return nil
end

function B:pad(button)
  local a = B.padAction(button)
  if not a then return false end
  if a == "back" and self.phase == "play" then a = "pause" end
  if a == "alt" then return true end
  self.padFocus = true
  return self:action(a)
end

-- ------------------------------------------------------------ drawing

function B:draw(x, y, w, h)
  local Gfx = require("src.pokewalker.minigames.Gfx")
  local g = love.graphics
  local s = Gfx.scale(w, h)
  local f = Gfx.fonts(s)
  self.hits = Gfx.newHits()
  Gfx.tick(self.t)
  -- the header: back / pause at the left, the title, the counters at the right
  local hh = math.floor(math.max(44, f.head:getHeight() + 22 * s))
  local gy = y + hh
  g.push("all")
  g.setScissor(math.floor(x), math.floor(gy), math.ceil(w), math.ceil(y + h - gy))
  self.game:draw(x, gy, w, y + h - gy, Gfx, f, s)
  g.setScissor()
  g.pop()
  Gfx.setc(Gfx.BG, 0.94)
  g.rectangle("fill", x, y, w, hh)
  local bw = math.max(hh, f.body:getWidth("Pause") + 30 * s)
  if self.phase == "play" then
    Gfx.button(self.hits, x + 8, y + 6, bw, hh - 12, "Pause", function() self:pause() end, nil, f.body)
  elseif self.phase == "intro" then
    Gfx.button(self.hits, x + 8, y + 6, bw, hh - 12, "Back", function()
      if self.opts.onExit then self.opts.onExit(self) end
    end, nil, f.body)
  end
  -- counters right-aligned; the title gets what is left
  local items = { { "Score", tostring(self.game.score or 0) } }
  for _, it in ipairs(self.game.hud and self.game:hud() or {}) do items[#items + 1] = it end
  local rx = x + w - 10
  local minX = x + bw + 20
  g.setFont(f.head)
  for i = #items, 1, -1 do
    local it = items[i]
    local vw = math.max(f.head:getWidth(it[2]), f.small:getWidth(it[1])) + 16 * s
    if rx - vw < minX + 60 * s then break end
    rx = rx - vw
    Gfx.setc(Gfx.DIM); g.setFont(f.small)
    g.printf(it[1], rx, y + 4, vw, "center")
    Gfx.setc(i == 1 and Gfx.GOLD or Gfx.INK); g.setFont(f.head)
    g.printf(it[2], rx, y + 4 + f.small:getHeight(), vw, "center")
  end
  if rx - minX > 80 * s then
    Gfx.setc(Gfx.INK)
    Gfx.fit(self.module.title, minX, y + (hh - f.head:getHeight()) / 2, rx - minX - 10, f.head, "left")
  end

  if self.phase == "intro" then self:drawIntro(x, gy, w, y + h - gy, Gfx, f, s)
  elseif self.phase == "pause" then self:drawPanel(x, gy, w, y + h - gy, Gfx, f, s, "Paused", {})
  elseif self.phase == "results" then self:drawResults(x, gy, w, y + h - gy, Gfx, f, s) end
end

function B:drawIntro(x, y, w, h, Gfx, f, s)
  local lines = {}
  for _, l in ipairs(self.module.howTo or {}) do lines[#lines + 1] = l end
  if self.ctx.standIn then lines[#lines + 1] = "(Nobody is out walking, so Pikachu stands in. Send a Pokemon on a walk to play with it.)" end
  local left = Rewards.left(self.st)
  lines[#lines + 1] = ("Today's rewards left: %d W, %d items, %d Pokemon."):format(left.watts, left.items, left.pokemon)
  self:drawPanel(x, y, w, h, Gfx, f, s, self.module.title, lines, { { "Start", function() self:start() end, "accent" } })
end

-- a centred card with a title, lines and buttons (the shell's menus)
function B:drawPanel(x, y, w, h, Gfx, f, s, title, lines, buttons)
  local g = love.graphics
  g.setColor(0, 0, 0, 0.45)
  g.rectangle("fill", x, y, w, h)
  buttons = buttons or self:menu() or {}
  local pw = math.min(w - 24, 560 * s)
  local tw = pw - 40 * s
  local th = f.title:getHeight() + 14 * s
  for _, l in ipairs(lines) do
    local _, wrapped = f.body:getWrap(l, tw)
    th = th + #wrapped * f.body:getHeight() + 8 * s
  end
  local bh = math.max(48, f.body:getHeight() + 26 * s)
  local ph = th + 20 * s + #buttons * (bh + 12 * s) + 30 * s
  -- too tall: the lines go smaller
  local font = f.body
  if ph > h - 16 and #lines > 0 then
    font = f.small
    th = f.title:getHeight() + 14 * s
    for _, l in ipairs(lines) do
      local _, wrapped = font:getWrap(l, tw)
      th = th + #wrapped * font:getHeight() + 6 * s
    end
    ph = th + 20 * s + #buttons * (bh + 12 * s) + 30 * s
  end
  local px, py = x + (w - pw) / 2, y + math.max(8, (h - ph) / 2)
  Gfx.card(px, py, pw, ph, 18 * s, Gfx.CARD, 0.96)
  Gfx.setc(Gfx.GOLD)
  Gfx.fit(title, px + 20 * s, py + 16 * s, tw, f.title, "center")
  local ly = py + 16 * s + f.title:getHeight() + 10 * s
  g.setFont(font)
  for _, l in ipairs(lines) do
    Gfx.setc(Gfx.INK)
    g.printf(l, px + 20 * s, ly, tw, "center")
    local _, wrapped = font:getWrap(l, tw)
    ly = ly + #wrapped * font:getHeight() + (font == f.small and 6 or 8) * s
  end
  ly = ly + 14 * s
  local bw = math.min(pw - 40 * s, 340 * s)
  for i, b in ipairs(buttons) do
    Gfx.button(self.hits, px + (pw - bw) / 2, ly, bw, bh, b[1], b[2], b[3], f.body, self.focus == i and self.padFocus == true)
    ly = ly + bh + 12 * s
  end
end

function B:drawResults(x, y, w, h, Gfx, f, s)
  local r = self.result or {}
  local lines = {}
  local why = self.game.overText
  if why then lines[#lines + 1] = why end
  lines[#lines + 1] = ("Score %d%s%s"):format(r.score or 0, r.newBest and "  -- new best!" or "",
    (r.placed and r.rank) and ("   (#%d)"):format(r.rank) or "")
  for _, l in ipairs(self.game.summary and self.game:summary() or {}) do lines[#lines + 1] = l end
  local paid = ("+%d W"):format(r.watts or 0)
  if r.wattsCapped then paid = paid .. "  (today's watt budget is spent)" end
  lines[#lines + 1] = paid
  for _, it in ipairs(r.items or {}) do lines[#lines + 1] = "Got " .. it .. "!" end
  for _, m in ipairs(r.pokemon or {}) do lines[#lines + 1] = ("Caught %s (Lv%d)!"):format(m.name or "?", m.level or 5) end
  if (r.lost and (r.lost.items + r.lost.pokemon) or 0) > 0 then
    lines[#lines + 1] = "The bag was full -- send presents home to make room."
  end
  if (r.friendship or 0) > 0 then
    lines[#lines + 1] = ("%s enjoyed that! (+%d friendship)"):format(self.ctx.walker.name or "Your Pokemon", r.friendship)
  end
  self:drawPanel(x, y, w, h, Gfx, f, s, "Results", lines)
end

return B
