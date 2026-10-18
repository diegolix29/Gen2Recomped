-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CATCH TIMING. A wild Pokemon from the course; a ring shrinks over it, again
-- and again. Tap when the ring meets the gold circle: the closer, the better
-- the throw (Perfect / Great / Good) and the likelier the catch. Six balls a
-- run; a Pokemon left waiting too long wanders off with a ball. The ring
-- speeds up after every throw, and rarer Pokemon (group A) have a smaller
-- circle and a lower base catch rate.

local Rewards = require("src.pokewalker.minigames.Rewards")
local Context = require("src.pokewalker.minigames.Context")

local M = {}
M.id = "catch"
M.title = "Catch Timing"
M.blurb = "Throw when the shrinking ring meets the circle."
M.howTo = {
  "A ring shrinks over the wild Pokemon. Tap (or A / Space) when it lines up with the gold circle.",
  "Perfect, Great and Good throws catch more often. You have 6 balls.",
}

-- THE KNOBS
M.BALLS = 6
M.PERIOD0, M.PERIOD_MIN, M.PERIOD_STEP = 1.7, 0.75, 0.9   -- seconds per shrink; x0.9 a throw
M.TARGET = { A = 0.30, B = 0.36, C = 0.40 }                -- the circle, as a fraction of the ring's start
M.GRADES = { { "Perfect", 0.035, 300, 1.6 }, { "Great", 0.08, 200, 1.25 }, { "Good", 0.15, 100, 0.85 } }
M.BASE = { A = 0.25, B = 0.40, C = 0.55 }
M.CATCH_POINTS = { A = 400, B = 300, C = 200 }
M.TIMEOUT = 7              -- seconds before it wanders off
M.WATTS_PER_POINTS = 100

function M.new(ctx, purse)
  local g = setmetatable({}, { __index = M })
  g.ctx, g.purse = ctx, purse
  g.score, g.time = 0, 0
  g.balls, g.period = M.BALLS, M.PERIOD0
  g.caught, g.throws, g.perfects = 0, 0, 0
  g.log = {}
  g:nextMon()
  return g
end

function M:nextMon()
  local e = Context.pickWild(self.ctx)
  self.mon = { dex = e.dex, name = e.name, level = e.level, group = e.group or "C" }
  self.target = M.TARGET[self.mon.group] or 0.38
  self.phase, self.pt, self.waited = "aim", 0, 0
  self.ring = 1
  self.grade = nil
end

-- the ring's size now: 1 -> 0 over a period, then again
function M:ringAt(t) return 1 - (t % self.period) / self.period end

-- how good a tap with the ring at `ring` is: grade index (1..3) or nil
function M:gradeFor(ring)
  local err = math.abs(ring - self.target)
  for i, gr in ipairs(M.GRADES) do if err <= gr[2] then return i end end
  return nil
end

function M:catchChance(group, gradeIdx)
  if not gradeIdx then return 0 end
  return math.min(0.95, (M.BASE[group] or 0.4) * M.GRADES[gradeIdx][4])
end

function M:throw()
  local gi = self:gradeFor(self.ring)
  self.balls = self.balls - 1
  self.throws = self.throws + 1
  self.grade = gi
  self.phase, self.pt = "throw", 0
  if gi then
    self.score = self.score + M.GRADES[gi][3]
    if gi == 1 then
      self.perfects = self.perfects + 1
      Rewards.event(self.purse, "catch_perfect", 1)
    end
  end
  local caught = gi and self.ctx.rand() < self:catchChance(self.mon.group, gi)
  self.shakes = caught and 3 or (gi and self.ctx.rng(3) - 1 or 0)
  self.caughtNow = caught
  self.kept = false
  if caught then
    self.caught = self.caught + 1
    self.score = self.score + (M.CATCH_POINTS[self.mon.group] or 200)
    Rewards.event(self.purse, "catch_caught", 1)
    self.kept = Rewards.addPokemon(self.purse, self.mon.dex, self.mon.level, self.mon.name)
  end
  self.log[#self.log + 1] = { name = self.mon.name, grade = gi and M.GRADES[gi][1] or "Miss", caught = caught, kept = self.kept }
end

function M:input(a)
  if a == "a" and self.phase == "aim" and self.pt > 0.15 then self:throw() end
end

function M:update(dt)
  if self.over then return end
  self.time = self.time + dt
  self.pt = self.pt + dt
  if self.phase == "aim" then
    self.ring = self:ringAt(self.pt)
    self.waited = self.waited + dt
    if self.waited >= M.TIMEOUT then
      self.balls = self.balls - 1
      self.log[#self.log + 1] = { name = self.mon.name, grade = "Wandered off" }
      self.grade, self.caughtNow, self.shakes = nil, false, 0
      self.phase, self.pt, self.fled = "result", 0, true
    end
  elseif self.phase == "throw" and self.pt >= 0.55 then
    self.phase, self.pt = self.grade and "shake" or "result", 0
  elseif self.phase == "shake" and self.pt >= 0.45 * math.max(1, self.shakes) + 0.2 then
    self.phase, self.pt = "result", 0
  elseif self.phase == "result" and self.pt >= 1.1 then
    self.fled = nil
    if self.balls <= 0 then
      self.over = "done"
      self.overText = self.caught > 0 and ("%d caught with %d balls."):format(self.caught, M.BALLS) or "Out of balls!"
      return
    end
    self.period = math.max(M.PERIOD_MIN, self.period * M.PERIOD_STEP)
    self:nextMon()
  end
end

function M:wattsFor() return math.floor((self.score or 0) / M.WATTS_PER_POINTS) end

function M:hud()
  return { { "Balls", tostring(self.balls) }, { "Caught", tostring(self.caught) } }
end

function M:summary()
  local t = { ("%d throws: %d perfect, %d caught."):format(self.throws, self.perfects, self.caught) }
  for _, l in ipairs(self.log) do
    if l.caught and not l.kept then
      t[#t + 1] = ("%s was caught for points, but today's Pokemon are all claimed -- it went back to the wild."):format(l.name or "?")
      break
    end
  end
  return t
end

-- ------------------------------------------------------------ drawing

function M:draw(x, y, w, h, Gfx, f, s)
  local g = love.graphics
  Gfx.scene(x, y, w, h, self.ctx.course.name, self.time * 6)
  local R = math.min(w * 0.42, h * 0.30)
  local cx, cy = x + w / 2, y + h * 0.60
  -- the patch of grass it stands on
  g.setColor(0, 0, 0, 0.18)
  g.ellipse("fill", cx, cy + R * 0.52, R * 0.75, R * 0.16)
  g.setColor(0.30, 0.62, 0.30, 0.9)
  g.ellipse("fill", cx, cy + R * 0.48, R * 0.7, R * 0.14)
  local monVisible = self.phase == "aim" or (self.phase == "result" and not self.caughtNow) or (self.phase == "throw")
  if self.fled then monVisible = false end
  local ps = R * 0.95
  if monVisible then Gfx.portrait(self.mon.dex, cx - ps / 2, cy - ps / 2, ps, self.mon.name) end
  -- the rings
  if self.phase == "aim" then
    local gi = self:gradeFor(self.ring)
    g.setLineWidth(math.max(4, R * 0.05))
    Gfx.setc(Gfx.GOLD, 0.9)
    g.circle("line", cx, cy, R * self.target)
    local col = gi == 1 and { 1, 1, 1 } or gi == 2 and Gfx.ACCENT or gi == 3 and Gfx.BLUE or Gfx.RED
    Gfx.setc(col, 0.95)
    g.setLineWidth(math.max(3, R * 0.035))
    g.circle("line", cx, cy, R * self.ring)
    g.setLineWidth(1)
    -- the patience bar
    local left = 1 - self.waited / M.TIMEOUT
    g.setColor(0, 0, 0, 0.4)
    g.rectangle("fill", cx - R * 0.6, cy + R * 0.85, R * 1.2, 8 * s, 4 * s)
    Gfx.setc(left > 0.3 and Gfx.ACCENT or Gfx.RED)
    g.rectangle("fill", cx - R * 0.6, cy + R * 0.85, R * 1.2 * math.max(0, left), 8 * s, 4 * s)
  end
  -- the ball
  local by0 = y + h - 30 * s
  if self.phase == "throw" then
    local u = math.min(1, self.pt / 0.55)
    local bx = cx
    local by = by0 + (cy - by0) * u - math.sin(u * math.pi) * R * 0.6
    Gfx.item("poke ball", bx, by, R * 0.12 * (1.4 - 0.4 * u))
  elseif self.phase == "shake" or (self.phase == "result" and self.grade and not self.fled) then
    local wob = 0
    if self.phase == "shake" then
      local k = self.pt / 0.45
      if math.floor(k) < self.shakes then wob = math.sin(k * math.pi * 2) * 0.35 end
    end
    if not (self.phase == "result" and not self.caughtNow) then
      g.push()
      g.translate(cx, cy + R * 0.42)
      g.rotate(wob)
      Gfx.item("poke ball", 0, -R * 0.1, R * 0.12)
      g.pop()
      if self.phase == "result" then
        Gfx.setc(Gfx.GOLD, 0.8)
        for i = 0, 5 do
          local a = i * math.pi / 3 + self.pt * 2
          g.circle("fill", cx + math.cos(a) * R * 0.3, cy + R * 0.32 + math.sin(a) * R * 0.2, 3 * s)
        end
      end
    end
  end
  -- the words
  local label
  if self.phase == "aim" then label = ("A wild %s!"):format(self.mon.name or "Pokemon")
  elseif self.phase == "result" then
    if self.fled then label = ("%s wandered off..."):format(self.mon.name or "It")
    elseif self.caughtNow then label = ("Gotcha! %s was caught!"):format(self.mon.name or "It")
    elseif self.grade then label = "Oh no! It broke free!" else label = "Missed!" end
  elseif self.grade then label = M.GRADES[self.grade][1] .. "!"
  elseif self.phase == "throw" then label = "Missed!" end
  if label then
    g.setFont(f.title)
    local tw = math.min(w - 20, f.title:getWidth(label) + 40 * s)
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", cx - tw / 2, y + 12 * s, tw, f.title:getHeight() + 12 * s, 12 * s)
    Gfx.setc(Gfx.INK)
    Gfx.fit(label, cx - tw / 2 + 10, y + 18 * s, tw - 20, f.title, "center")
  end
  -- the balls left
  local br = math.max(8, 12 * s)
  for i = 1, M.BALLS do
    local bx = cx + (i - (M.BALLS + 1) / 2) * br * 2.6
    if i <= self.balls then Gfx.item("poke ball", bx, by0, br)
    else g.setColor(0, 0, 0, 0.35); g.circle("fill", bx, by0, br) end
  end
  if self.phase == "aim" then
    local hint = "Tap when the ring meets the gold circle"
    local hw = f.small:getWidth(hint) + 24 * s
    local hy = by0 - br - f.small:getHeight() - 14 * s
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", cx - hw / 2, hy - 4 * s, hw, f.small:getHeight() + 8 * s, 8 * s)
    Gfx.setc(Gfx.INK)
    g.setFont(f.small)
    g.printf(hint, x, hy, w, "center")
  end
end

return M
