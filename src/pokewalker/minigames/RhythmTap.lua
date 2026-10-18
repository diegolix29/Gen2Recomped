-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- RHYTHM TAP. A beat plays and notes slide toward the walking Pokemon; tap
-- as each one reaches it. Perfect / Great / Good by how close; a streak
-- multiplies the score (x2 at 10, x3 at 20, x4 at 30) and a miss -- or a tap
-- with no note near it -- ends the streak. The tempo climbs from 96 to 132
-- BPM over the 80-second song and off-beat notes creep in.
--
-- THE MUSIC is a click track made here (a kick on the bar, ticks between,
-- a chime for each hit), not the launcher's background music: that is
-- whichever game's title music the backdrop is running, and it has no tempo
-- map to tap against. The backdrop is held still while the minigames are
-- open (src/ui/WalkerMinigames.lua), so the two never play over each other.
-- Without love.audio (a headless check, the screenshot harness) it is silent
-- and plays the same.

local Rewards = require("src.pokewalker.minigames.Rewards")

local M = {}
M.id = "rhythm"
M.title = "Rhythm Tap"
M.blurb = "Tap to the beat; streaks multiply your score."
M.howTo = {
  "Notes slide toward your Pokemon. Tap (or A / Space) as each one reaches it.",
  "Keep a streak going to multiply your score -- a miss, or a tap with no note near, breaks it.",
}

-- THE KNOBS
M.SONG = 80                    -- seconds of notes
M.LEADIN = 2.0
M.BPM0, M.BPM1 = 96, 132
M.WINDOWS = { { "Perfect", 0.05, 100 }, { "Great", 0.10, 70 }, { "Good", 0.15, 40 } }
M.STREAK_STEP, M.MULT_MAX = 10, 4
M.APPROACH = 1.4               -- seconds a note is on screen before its time
M.WATTS_PER_POINTS = 1200
M.AUDIO_OFFSET = 0             -- seconds; added to every sound's time

function M.new(ctx, purse)
  local g = setmetatable({}, { __index = M })
  g.ctx, g.purse = ctx, purse
  g.score, g.time = 0, 0
  g.clock = -M.LEADIN
  g.streak, g.best, g.hits, g.misses, g.perfects = 0, 0, 0, 0, 0
  g.counts = { 0, 0, 0 }
  g.pops = {}
  g:compose()
  g.nextBeat, g.nextNote = 1, 1
  return g
end

-- the chart: the beats (for the click track) and the notes (to tap)
function M:compose()
  local beats, notes = {}, {}
  local t, i = 0, 0
  while t < M.SONG do
    local u = t / M.SONG
    local bpm = M.BPM0 + (M.BPM1 - M.BPM0) * u
    local step = 60 / bpm
    beats[#beats + 1] = { t = t, down = i % 4 == 0 }
    -- on the beat: most beats, fewer rests as it goes
    local rest = (i % 8 == 7 and u < 0.5) or (self.ctx.rng(100) <= (u < 0.25 and 15 or 8))
    if i >= 4 and not rest then notes[#notes + 1] = { t = t } end
    -- off-beats from a quarter of the way in
    if u > 0.25 and i >= 4 and self.ctx.rng(100) <= math.floor(10 + 30 * u) then
      notes[#notes + 1] = { t = t + step / 2, off = true }
    end
    t = t + step
    i = i + 1
  end
  self.beats, self.notes = beats, notes
  self.length = (notes[#notes] and notes[#notes].t or M.SONG) + 1.2
end

function M:mult() return math.min(M.MULT_MAX, 1 + math.floor(self.streak / M.STREAK_STEP)) end

function M:pop(text, c) self.pops[#self.pops + 1] = { text = text, t = 0, c = c } end

function M:breakStreak()
  if self.streak >= 10 then Rewards.event(self.purse, "rhythm_streak", self.streak) end
  self.streak = 0
end

-- a tap at the song's clock: the nearest unjudged note in the widest window
function M:tap(at)
  at = at or self.clock
  local best, bestD
  for k = self.nextNote, #self.notes do
    local n = self.notes[k]
    if n.t - at > M.WINDOWS[3][2] then break end
    if not n.judged then
      local d = math.abs(n.t - at)
      if d <= M.WINDOWS[3][2] and (not bestD or d < bestD) then best, bestD = n, d end
    end
  end
  if not best then
    -- nothing there: a stray tap breaks the streak (no mashing)
    if self.clock > 0 then self:breakStreak(); self:pop("Off beat", "red") end
    return nil
  end
  local gi = 3
  for i, wdw in ipairs(M.WINDOWS) do if bestD <= wdw[2] then gi = i break end end
  best.judged, best.grade = true, gi
  self.streak = self.streak + 1
  self.best = math.max(self.best, self.streak)
  self.hits = self.hits + 1
  self.counts[gi] = self.counts[gi] + 1
  if gi == 1 then self.perfects = self.perfects + 1 end
  self.score = self.score + M.WINDOWS[gi][3] * self:mult()
  self:pop(M.WINDOWS[gi][1], gi == 1 and "gold" or gi == 2 and "green" or "blue")
  self:sound("hit")
  return gi
end

function M:input(a)
  if a == "a" or a == "up" or a == "down" or a == "left" or a == "right" then self:tap() end
end

function M:update(dt)
  if self.over then return end
  self.time = self.time + dt
  self.clock = self.clock + dt
  -- the click track
  while self.beats[self.nextBeat] and self.beats[self.nextBeat].t <= self.clock + M.AUDIO_OFFSET do
    self:sound(self.beats[self.nextBeat].down and "kick" or "tick")
    self.nextBeat = self.nextBeat + 1
  end
  -- notes gone by unhit
  while self.notes[self.nextNote] do
    local n = self.notes[self.nextNote]
    if not n.judged and self.clock - n.t > M.WINDOWS[3][2] then
      n.judged, n.missed = true, true
      self.misses = self.misses + 1
      self:breakStreak()
      self:pop("Miss", "red")
    end
    if n.judged then self.nextNote = self.nextNote + 1 else break end
  end
  for i = #self.pops, 1, -1 do
    local p = self.pops[i]
    p.t = p.t + dt
    if p.t > 0.7 then table.remove(self.pops, i) end
  end
  if self.clock >= self.length then
    self:breakStreak()
    self.over = "done"
    self.overText = ("Song over! Best streak %d."):format(self.best)
  end
end

function M:beforeSettle()
  Rewards.event(self.purse, "rhythm_perfect", self.perfects)
  Rewards.event(self.purse, "rhythm_best_streak", self.best)
  self:sound(nil)
end

function M:wattsFor() return math.floor((self.score or 0) / M.WATTS_PER_POINTS) end

function M:hud()
  return { { "Streak", tostring(self.streak) }, { "Mult", "x" .. self:mult() } }
end

function M:summary()
  return {
    ("%d of %d notes: %d perfect, %d great, %d good. Best streak %d."):format(self.hits, #self.notes,
      self.counts[1], self.counts[2], self.counts[3], self.best),
  }
end

-- ------------------------------------------------------------ the sound

local bank
local function makeBank()
  if bank ~= nil then return bank or nil end
  bank = false
  if not (love and love.audio and love.sound) then return nil end
  local ok, b = pcall(function()
    local rate = 22050
    local function tone(len, fn)
      local n = math.floor(rate * len)
      local sd = love.sound.newSoundData(n, rate, 16, 1)
      for i = 0, n - 1 do sd:setSample(i, math.max(-1, math.min(1, fn(i / rate, i / n)))) end
      return love.audio.newSource(sd, "static")
    end
    local seed = 1
    local function noise() seed = (seed * 16807) % 2147483647; return seed / 1073741823.5 - 1 end
    return {
      kick = tone(0.16, function(t, u) return math.sin(2 * math.pi * (55 + 90 * (1 - u) ^ 3) * t) * (1 - u) ^ 2 * 0.9 end),
      tick = tone(0.05, function(_, u) return noise() * (1 - u) ^ 3 * 0.35 end),
      hit = tone(0.09, function(t, u) return (math.sin(2 * math.pi * 880 * t) + 0.5 * math.sin(2 * math.pi * 1320 * t)) * (1 - u) ^ 2 * 0.35 end),
    }
  end)
  if ok and b then bank = b end
  return bank or nil
end

-- the game names a sound; the bank plays it (sound(nil) silences all)
function M:sound(name)
  if self.silent then return end
  local b = makeBank()
  if not b then return end
  if name == nil then for _, s in pairs(b) do pcall(s.stop, s) end return end
  local s = b[name]
  if s then pcall(function() s:stop(); s:play() end) end
end

-- ------------------------------------------------------------ drawing

function M:draw(x, y, w, h, Gfx, f, s)
  local g = love.graphics
  Gfx.scene(x, y, w, h, self.ctx.course.name, math.max(0, self.clock) * 20)
  g.setColor(0, 0, 0, 0.30)
  g.rectangle("fill", x, y, w, h)
  -- the track: across in landscape, down in portrait; the Pokemon at the
  -- hit mark, notes coming in from the far end
  local across = w >= h
  local size = math.min(w, h) * 0.30
  local hx, hy, len
  if across then
    hx, hy = x + w * 0.20, y + h * 0.55
    len = w * 0.72
  else
    hx, hy = x + w / 2, y + h * 0.78
    len = h * 0.68
  end
  local lane = size * 0.55
  g.setColor(0, 0, 0, 0.35)
  if across then g.rectangle("fill", hx - lane / 2, hy - lane / 2, len + lane, lane, lane / 2)
  else g.rectangle("fill", hx - lane / 2, hy - len - lane / 2, lane, len + lane, lane / 2) end
  -- beat lines
  g.setColor(1, 1, 1, 0.12)
  for k = self.nextBeat - 2, self.nextBeat + 6 do
    local b = self.beats[k]
    if b then
      local d = (b.t - self.clock) / M.APPROACH * len
      if d >= 0 and d <= len then
        if across then g.rectangle("fill", hx + d - 1, hy - lane / 2, 2, lane)
        else g.rectangle("fill", hx - lane / 2, hy - d - 1, lane, 2) end
      end
    end
  end
  -- the hit mark, pulsing with the beat
  local prev = self.beats[math.max(1, self.nextBeat - 1)]
  local since = prev and (self.clock - prev.t) or 1
  local pulse = since >= 0 and math.max(0, 1 - since * 4) or 0
  Gfx.setc(Gfx.GOLD, 0.6 + 0.4 * pulse)
  g.setLineWidth(math.max(3, 4 * s))
  g.circle("line", hx, hy, lane * 0.5 + pulse * 6 * s)
  g.setLineWidth(1)
  -- notes
  for k = self.nextNote, #self.notes do
    local n = self.notes[k]
    local d = (n.t - self.clock) / M.APPROACH * len
    if d > len + lane then break end
    if not n.judged and d >= -lane then
      local nx, ny = across and hx + d or hx, across and hy or hy - d
      Gfx.setc(n.off and Gfx.BLUE or Gfx.ACCENT)
      g.circle("fill", nx, ny, lane * 0.36)
      g.setColor(1, 1, 1, 0.8)
      g.circle("line", nx, ny, lane * 0.36)
    end
  end
  -- the walker, dancing: a hop on every beat
  local wk = self.ctx.walker
  local hop = pulse * size * 0.15
  local wx, wy = across and hx or hx, (across and hy - lane / 2 - 4 or hy + lane * 0.2) - hop
  if not across then wx = hx + lane * 0.9 + size * 0.35 end
  Gfx.walker(wk.dex, wx, across and wy or hy + size * 0.35 - hop, size, "down", self.time, wk.name)
  -- the judgement and the streak
  local p = self.pops[#self.pops]
  if p then
    local c = p.c == "gold" and Gfx.GOLD or p.c == "green" and Gfx.ACCENT or p.c == "blue" and Gfx.BLUE or Gfx.RED
    Gfx.setc(c, 1 - p.t / 0.7)
    g.setFont(f.title)
    local px = across and hx - 150 or hx - 150
    local py = across and hy + lane - p.t * 20 or hy - len * 0.5 - p.t * 20
    g.printf(p.text, px, py, 300, "center")
  end
  if self.streak >= 3 then
    Gfx.setc(Gfx.INK)
    g.setFont(f.big)
    local txt = ("%d"):format(self.streak)
    local sx = across and x + w * 0.62 or x + w * 0.25
    local sy = across and y + h * 0.12 or y + h * 0.08
    g.printf(txt, sx - 150, sy, 300, "center")
    g.setFont(f.small); Gfx.setc(Gfx.GOLD)
    g.printf(("streak  x%d"):format(self:mult()), sx - 150, sy + f.big:getHeight(), 300, "center")
  end
  if self.clock < 0 then
    g.setFont(f.title); Gfx.setc(Gfx.INK)
    g.printf(("Get ready... %d"):format(math.ceil(-self.clock)), x, y + h * 0.3, w, "center")
  end
  -- the song's progress
  local u = math.max(0, math.min(1, self.clock / self.length))
  g.setColor(0, 0, 0, 0.4); g.rectangle("fill", x, y + h - 6 * s, w, 6 * s)
  Gfx.setc(Gfx.GOLD); g.rectangle("fill", x, y + h - 6 * s, w * u, 6 * s)
end

return M
