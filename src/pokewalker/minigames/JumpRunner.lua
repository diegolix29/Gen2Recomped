-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- JUMP RUNNER. The walking Pokemon runs along its course; tap (click, A,
-- Space) to jump and tap again in the air to double jump.
--   * bounce on the course's wild Pokemon (land on them from above) for
--     points -- several in one jump multiply -- and a small chance to catch one
--   * jump through hoops for a bonus; grab watt orbs and the odd item
--   * rocks and logs can be landed on; running into one, or into a wild
--     Pokemon from the side, ends the run
--   * the course speeds up the longer you last
--
-- The world is measured in tiles (the runner is about one tile tall), y up
-- from the ground. All rules are here and headless; draw() only paints.

local Rewards = require("src.pokewalker.minigames.Rewards")
local Context = require("src.pokewalker.minigames.Context")

local M = {}
M.id = "runner"
M.title = "Jump Runner"
M.blurb = "Run the course: jump, double jump, bounce on wild Pokemon."
M.howTo = {
  "Tap, click, A or Space to jump -- and again in the air to double jump.",
  "Land on wild Pokemon to bounce off them (you might catch one!). Running into one, or into a rock, ends the run.",
  "Jump through hoops for bonus points and grab the watt orbs and items.",
}

-- THE KNOBS
M.GRAVITY = 42
M.JUMP_V = 15.5           -- about 2.9 tiles high
M.DOUBLE_V = 12.5         -- about 1.9 more
M.BOUNCE_V = 12
M.SPEED0, M.SPEED_MAX, M.ACCEL = 6, 14, 0.05   -- tiles/s, tiles/s, tiles/s per second
M.PLAYER_X = 2.5          -- tiles from the left of the view
M.PLAYER_W, M.PLAYER_H = 0.66, 0.9
M.BUFFER, M.COYOTE = 0.12, 0.08
M.AHEAD = 18              -- spawn this far ahead of the runner
M.POINTS = { stomp = 50, hoop = 30, orb = 10, item = 25, perTile = 1 }
M.CATCH_CHANCE = { A = 0.04, B = 0.06, C = 0.08 }
M.ITEM_EVERY = 260        -- tiles between item pickups
M.WATTS_PER_POINTS = 250  -- score -> watts
M.ORB_WATTS_MAX = 10      -- orbs pay 1 W each, up to this a run

function M.new(ctx, purse)
  local g = setmetatable({}, { __index = M })
  g.ctx, g.purse = ctx, purse
  g.score, g.time = 0, 0
  g.dist, g.speed = 0, M.SPEED0
  g.py, g.vy, g.ground, g.jumps = 0, 0, true, 0
  g.buffer, g.coyote = 0, 0
  g.ents, g.pops = {}, {}
  g.nextSpawn, g.nextItem = 14, 60
  g.stomps, g.hoops, g.orbs, g.items, g.combo = 0, 0, 0, 0, 0
  g.distPoints = 0
  return g
end

-- ------------------------------------------------------------ spawning

local function add(g, e) g.ents[#g.ents + 1] = e; return e end

local function rock(g, x, kind)
  local w, h = 0.9, 0.8
  if kind == "log" then w, h = 1.6, 0.6 elseif kind == "stump" then w, h = 0.8, 1.35 end
  return add(g, { kind = "block", look = kind or "rock", x = x, y = 0, w = w, h = h })
end

local function mon(g, x, flying)
  local e = Context.pickWild(g.ctx)
  local y=flying and (1.5+g.ctx.rand()*.6) or 0
  return add(g, { kind = "mon", x = x, y = y, yy=y, w = 0.9, h = 0.85,
                  vx = flying and 0 or -(0.8 + g.ctx.rand() * 0.8), flying = flying, dex = e.dex, name = e.name,
                  level = e.level, group = e.group, phase = g.ctx.rand() * 6 })
end

local function orbArc(g, x, n, height)
  for i = 0, n - 1 do
    local u = i / math.max(1, n - 1)
    add(g, { kind = "orb", x = x + i * 0.9, y = 0.9 + height * 4 * u * (1 - u), r = 0.28 })
  end
end

-- the next stretch of course at world x; returns its length
function M:spawnChunk(x)
  local r = self.ctx.rng
  local hard = math.min(1, self.dist / 900)          -- 0 at the start, 1 by 900 tiles
  local roll = r(100)
  if self.dist + M.AHEAD >= self.nextItem and Rewards.canItem(self.purse) then
    self.nextItem = self.nextItem + M.ITEM_EVERY
    add(self, { kind = "item", x = x + 1, y = 1.6, r = 0.36, name = Context.pickItem(self.ctx) })
    return 3
  end
  if roll <= 22 then
    rock(self, x, ({ "rock", "log", "stump" })[r(hard > 0.3 and 3 or 2)])
    if r(2) == 1 then orbArc(self, x - 1.2, 4, 2.4) end
    return 2
  elseif roll <= 46 then
    mon(self, x, false)
    if hard > 0.4 and r(3) == 1 then mon(self, x + 2.2, false) return 4 end
    return 2
  elseif roll <= 60 then
    rock(self, x, "rock")
    add(self, { kind = "hoop", x = x + 0.45, cy = 2.5 + self.ctx.rand() * 0.5, r = 0.85 })
    return 2
  elseif roll <= 72 then
    add(self, { kind = "hoop", x = x, cy = 1.9 + self.ctx.rand() * 1.4, r = 0.85 })
    orbArc(self, x + 2, 3, 0.4)
    return 4
  elseif roll <= 84 then
    mon(self, x, true)
    return 2
  elseif roll <= 92 then
    orbArc(self, x, 6, 1.8)
    return 6
  else
    rock(self, x, "log")
    mon(self, x + 3.2 + hard, false)
    return 5
  end
end

-- ------------------------------------------------------------ the rules

function M:input(a)
  if a == "a" or a == "up" then self.buffer = M.BUFFER end
end

function M:pop(x, y, text, c)
  self.pops[#self.pops + 1] = { x = x, y = y, text = text, t = 0, c = c }
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

function M:tryJump()
  if self.buffer <= 0 then return end
  if self.ground or self.coyote > 0 then
    self.vy, self.jumps, self.ground, self.coyote = M.JUMP_V, 1, false, 0
    self.buffer = 0
  elseif self.jumps < 2 then
    self.vy, self.jumps = M.DOUBLE_V, 2
    self.buffer = 0
  end
end

function M:crash(text)
  self.over = "crash"
  self.overText = text
end

function M:step(dt)
  self.time = self.time + dt
  self.speed = math.min(M.SPEED_MAX, self.speed + M.ACCEL * dt)
  local dx = self.speed * dt
  self.dist = self.dist + dx
  local whole = math.floor(self.dist)
  if whole > self.distPoints then
    self.score = self.score + (whole - self.distPoints) * M.POINTS.perTile
    self.distPoints = whole
  end
  self.buffer = math.max(0, self.buffer - dt)
  self.coyote = math.max(0, self.coyote - dt)
  self:tryJump()

  -- vertical motion, landing on the ground or a block's top
  local prevY = self.py
  self.vy = self.vy - M.GRAVITY * dt
  self.py = self.py + self.vy * dt
  local px = self.dist + M.PLAYER_X - M.PLAYER_W / 2
  local support = 0
  for _, e in ipairs(self.ents) do
    if e.kind == "block" and px < e.x + e.w and e.x < px + M.PLAYER_W then
      local top = e.y + e.h
      if prevY >= top - 0.06 then support = math.max(support, top) end
    end
  end
  local wasGround = self.ground
  if self.py <= support and self.vy <= 0 then
    self.py, self.vy, self.ground, self.jumps, self.combo = support, 0, true, 0, 0
  else
    self.ground = false
    if wasGround then self.coyote = M.COYOTE end
  end

  -- everything else
  local keep = {}
  for _, e in ipairs(self.ents) do
    local alive = true
    if e.kind == "mon" then
      -- a walker stops at a rock or log rather than walk through it
      if (e.vx or 0) < 0 then
        for _, b in ipairs(self.ents) do
          if b.kind == "block" and e.x >= b.x + b.w - 0.05 and e.x + e.vx * dt < b.x + b.w + 0.1 then e.vx = 0 end
        end
      end
      e.x = e.x + (e.vx or 0) * dt
      e.phase = e.phase + dt
      if e.flying then e.yy = e.y + math.sin(e.phase * 3) * 0.25 else e.yy = e.y end
      if not e.dead and overlap(px, self.py, M.PLAYER_W, M.PLAYER_H, e.x + 0.12, e.yy, e.w - 0.24, e.h * 0.9) then
        if self.vy < 0 and prevY >= e.yy + e.h * 0.45 then
          -- a stomp: bounce, score (more for each in one jump), maybe a catch
          self.combo = self.combo + 1
          local pts = M.POINTS.stomp * self.combo
          self.score = self.score + pts
          self.stomps = self.stomps + 1
          self.vy, self.jumps = M.BOUNCE_V, 1
          e.dead = 0
          self:pop(e.x, e.yy + 1.4, ("+%d"):format(pts))
          Rewards.event(self.purse, "runner_stomp", 1)
          local chance = M.CATCH_CHANCE[e.group] or 0.04
          if Rewards.canPokemon(self.purse) and self.ctx.rand() < chance then
            if Rewards.addPokemon(self.purse, e.dex, e.level, e.name) then
              self:pop(e.x, e.yy + 2.2, ("Caught %s!"):format(e.name or "it"), "gold")
              Rewards.event(self.purse, "runner_catch", 1)
            end
          end
        else
          self:crash(("Bumped into a wild %s!"):format(e.name or "Pokemon"))
        end
      end
      if e.dead then
        e.dead = e.dead + dt
        if e.dead > 0.5 then alive = false end
      end
    elseif e.kind == "block" then
      if overlap(px + 0.08, self.py + 0.02, M.PLAYER_W - 0.16, M.PLAYER_H - 0.1, e.x, e.y, e.w, e.h)
         and self.py < e.y + e.h - 0.08 then
        self:crash(e.look == "log" and "Tripped over a log!" or "Ran into a rock!")
      end
    elseif e.kind == "hoop" then
      local cx = self.dist + M.PLAYER_X
      if not e.done and cx >= e.x then
        e.done = true
        local mid = self.py + M.PLAYER_H / 2
        if math.abs(mid - e.cy) < e.r * 0.7 then
          e.scored = true
          self.hoops = self.hoops + 1
          self.score = self.score + M.POINTS.hoop
          self:pop(e.x, e.cy + 1, ("+%d"):format(M.POINTS.hoop), "blue")
          Rewards.event(self.purse, "runner_hoop", 1)
        end
      end
    elseif e.kind == "orb" or e.kind == "item" then
      local cx, cy = self.dist + M.PLAYER_X, self.py + M.PLAYER_H / 2
      local rr = e.r + 0.45
      if (cx - e.x) ^ 2 + (cy - e.y) ^ 2 < rr * rr then
        alive = false
        if e.kind == "orb" then
          self.orbs = self.orbs + 1
          self.score = self.score + M.POINTS.orb
          if self.orbs <= M.ORB_WATTS_MAX then Rewards.addWatts(self.purse, 1) end
          Rewards.event(self.purse, "runner_orb", 1)
          self:pop(e.x, e.y + 0.6, "+1 W", "gold")
        else
          self.score = self.score + M.POINTS.item
          if Rewards.addItem(self.purse, e.name) then
            self.items = self.items + 1
            self:pop(e.x, e.y + 0.8, ("Got %s!"):format(e.name), "gold")
          else
            self:pop(e.x, e.y + 0.8, ("+%d"):format(M.POINTS.item))
          end
        end
      end
    end
    -- gone off the left edge
    if (e.x + (e.w or e.r or 1) + 2) < self.dist then alive = false end
    if alive then keep[#keep + 1] = e end
  end
  self.ents = keep

  -- new course ahead; the gap grows with the speed so a jump always fits
  while self.nextSpawn < self.dist + M.AHEAD do
    local len = self:spawnChunk(self.nextSpawn)
    local gap = math.max(4, self.speed * 0.7) + self.ctx.rand() * 3
    self.nextSpawn = self.nextSpawn + len + gap
  end
  for i = #self.pops, 1, -1 do
    local p = self.pops[i]
    p.t = p.t + dt
    if p.t > 1 then table.remove(self.pops, i) end
  end
end

function M:update(dt)
  if self.over then return end
  local n = math.max(1, math.ceil(dt / (1 / 120)))
  for _ = 1, n do
    self:step(dt / n)
    if self.over then break end
  end
end

function M:wattsFor()
  return math.floor((self.score or 0) / M.WATTS_PER_POINTS)
end

function M:hud()
  return { { "Distance", ("%d m"):format(math.floor(self.dist)) }, { "Orbs", tostring(self.orbs) } }
end

function M:summary()
  return {
    ("Ran %d m in %d s: %d bounced, %d hoops, %d orbs."):format(math.floor(self.dist), math.floor(self.time), self.stomps, self.hoops, self.orbs),
  }
end

-- the run's totals go in with the purse (Base calls this before paying)
function M:beforeSettle()
  Rewards.event(self.purse, "runner_distance", math.floor(self.dist))
end

-- ------------------------------------------------------------ drawing

function M:draw(x, y, w, h, Gfx, f, s)
  local g = love.graphics
  -- tiles to pixels: at least 12 tiles across, at most 7.5 tall
  local k = math.min(w / 12, h / 7.5)
  local bandH = 7.5 * k
  local top = y + math.max(0, (h - bandH) / 2)
  local gy = top + 6.2 * k
  local sh = math.max((gy - y) / 0.72, (y + h - gy) / 0.28)
  Gfx.scene(x, gy - 0.72 * sh, w, sh, self.ctx.course.name, self.dist * k * 0.3)
  -- the track itself: a dirt path along the ground line (the painted course
  -- backgrounds put their own horizon wherever they like)
  g.setColor(0.36, 0.62, 0.30, 1)
  g.rectangle("fill", x, gy - k * 0.06, w, k * 0.14)
  g.setColor(0.62, 0.48, 0.32, 1)
  g.rectangle("fill", x, gy + k * 0.08, w, k * 0.55)
  g.setColor(0.50, 0.38, 0.24, 1)
  local stripe = k * 1.5
  local off = (self.dist * k) % stripe
  for sxp = x - off, x + w, stripe do
    g.rectangle("fill", sxp, gy + k * 0.32, k * 0.5, k * 0.08)
  end
  g.setColor(0, 0, 0, 0.18)
  g.rectangle("fill", x, gy + k * 0.63, w, k * 0.05)
  local function sx(wx) return x + (wx - self.dist) * k end
  local function sy(wy) return gy - wy * k end
  for _, e in ipairs(self.ents) do
    local ex = sx(e.x)
    if ex > x - 3 * k and ex < x + w + 3 * k then
      if e.kind == "block" then
        if e.look == "log" then
          g.setColor(0.45, 0.30, 0.16, 1)
          g.rectangle("fill", ex, sy(e.h), e.w * k, e.h * k, e.h * k * 0.5)
          g.setColor(0.62, 0.45, 0.26, 1)
          g.ellipse("fill", ex + e.w * k - e.h * k * 0.3, sy(e.h / 2), e.h * k * 0.28, e.h * k * 0.45)
        elseif e.look == "stump" then
          g.setColor(0.40, 0.28, 0.16, 1)
          g.rectangle("fill", ex, sy(e.h), e.w * k, e.h * k, k * 0.1)
          g.setColor(0.70, 0.55, 0.32, 1)
          g.ellipse("fill", ex + e.w * k / 2, sy(e.h), e.w * k / 2, k * 0.12)
        else
          g.setColor(0.42, 0.42, 0.46, 1)
          g.rectangle("fill", ex, sy(e.h), e.w * k, e.h * k, k * 0.3)
          g.setColor(1, 1, 1, 0.18)
          g.rectangle("fill", ex + k * 0.12, sy(e.h) + k * 0.1, e.w * k * 0.4, k * 0.18, k * 0.08)
        end
      elseif e.kind == "mon" then
        local size = 1.15 * k
        g.push()
        if e.dead then
          g.translate(ex + e.w * k / 2, sy(e.yy))
          g.scale(1, math.max(0.2, 1 - e.dead * 1.6))
          g.translate(-(ex + e.w * k / 2), -sy(e.yy))
        end
        Gfx.walker(e.dex, ex + e.w * k / 2, sy(e.yy), size, "left", self.time, e.name)
        g.pop()
        if e.flying then
          g.setColor(1, 1, 1, 0.5)
          local fl = math.sin(self.time * 18) * 0.15 * k
          g.ellipse("fill", ex + e.w * k * 0.15, sy(e.yy + 0.7) + fl, k * 0.22, k * 0.1)
          g.ellipse("fill", ex + e.w * k * 0.85, sy(e.yy + 0.7) - fl, k * 0.22, k * 0.1)
        end
      elseif e.kind == "hoop" then
        g.setLineWidth(math.max(3, k * 0.14))
        Gfx.setc(e.scored and Gfx.ACCENT or Gfx.GOLD)
        g.ellipse("line", ex, sy(e.cy), e.r * k * 0.38, e.r * k)
        g.setLineWidth(1)
      elseif e.kind == "orb" then
        Gfx.orb(ex, sy(e.y), e.r * k, self.time)
      elseif e.kind == "item" then
        g.setColor(1, 1, 1, 0.35 + 0.2 * math.sin(self.time * 6))
        g.circle("fill", ex, sy(e.y), e.r * k * 1.5)
        Gfx.item(e.name, ex, sy(e.y), e.r * k)
      end
    end
  end
  -- the runner
  local wk = self.ctx.walker
  local tilt = self.ground and 0 or math.max(-0.25, math.min(0.25, -self.vy * 0.02))
  local px, py = sx(self.dist + M.PLAYER_X), sy(self.py)
  if not self.ground then
    g.setColor(0, 0, 0, 0.22 * math.max(0.2, 1 - self.py / 4))
    g.ellipse("fill", px, gy, k * 0.4 * math.max(0.4, 1 - self.py / 5), k * 0.1)
  end
  g.push()
  g.translate(px, py); g.rotate(tilt); g.translate(-px, -py)
  Gfx.walker(wk.dex, px, py, 1.25 * k, "right", self.ground and self.time * self.speed / 5 or 0, wk.name, not self.ground)
  g.pop()
  if self.jumps == 2 and not self.ground then
    g.setColor(1, 1, 1, 0.5)
    g.circle("line", px, py + k * 0.1, k * 0.5)
  end
  -- the pop-up numbers
  for _, p in ipairs(self.pops) do
    local c = p.c == "gold" and Gfx.GOLD or p.c == "blue" and Gfx.BLUE or Gfx.INK
    Gfx.setc(c, 1 - p.t)
    g.setFont(f.head)
    g.printf(p.text, sx(p.x) - 150, sy(p.y + p.t * 0.8), 300, "center")
  end
  -- speed lines as it gets fast
  if self.speed > 9 then
    g.setColor(1, 1, 1, (self.speed - 9) / 20)
    for i = 0, 5 do
      local ly = top + (i * 1.13 % 1) * bandH * 0.6 + bandH * 0.1
      local lx = x + ((i * 0.37 - self.time * 2) % 1) * w
      g.rectangle("fill", lx, ly, k * 1.5, 2)
    end
  end
end

return M
