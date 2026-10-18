-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MEMORY MATCH. Sixteen cards, eight pairs of Pokemon (the course's, the
-- walker's own and some old friends -- pictures from the player's imported
-- games). Flip two at a time; a pair stays up. 90 seconds. Every pair
-- scores, and clearing the board pays for the time left and for every turn
-- under thirty -- fewer flips, more watts.

local Rewards = require("src.pokewalker.minigames.Rewards")

local M = {}
M.id = "memory"
M.title = "Memory Match"
M.blurb = "Flip cards to pair up Pokemon -- fewer flips, more watts."
M.howTo = {
  "Flip two cards at a time to find the matching Pokemon. Matches stay face up.",
  "Clear the board in 90 seconds. The fewer flips you need, the more watts you earn.",
}

-- THE KNOBS
M.PAIRS = 8
M.TIME = 90
M.PAIR_POINTS = 100
M.TIME_POINTS = 4            -- per second left on a clear
M.TURN_PAR, M.TURN_POINTS = 30, 20   -- per turn under par on a clear
M.SHOW = 0.8                 -- a mismatch stays up this long
M.WATTS_PER_POINTS = 60
-- old friends to fill the board when the course has too few
M.EXTRAS = { 25, 1, 4, 7, 152, 155, 158, 133, 39, 52, 54, 175, 179, 183, 194, 216, 252, 255, 258, 172 }

function M.new(ctx, purse)
  local g = setmetatable({}, { __index = M })
  g.ctx, g.purse = ctx, purse
  g.score, g.time = 0, 0
  g.left = M.TIME
  g.turns, g.pairs = 0, 0
  g.open = {}
  g.cur = 1
  -- the species: the walker, the course's six, then extras; no repeats, and
  -- only ones some imported game has a picture for (ctx.hasArt) when known
  local pool, seen = {}, {}
  local function add(dex, name)
    dex = tonumber(dex)
    if dex and not seen[dex] and #pool < M.PAIRS and (not ctx.hasArt or ctx.hasArt(dex)) then
      seen[dex] = true
      pool[#pool + 1] = { dex = dex, name = name }
    end
  end
  add(ctx.walker.dex, ctx.walker.name)
  for _, e in ipairs(ctx.wild) do add(e.dex, e.name) end
  local extras = {}
  for i, d in ipairs(M.EXTRAS) do extras[i] = d end
  for i = #extras, 2, -1 do local j = ctx.rng(i); extras[i], extras[j] = extras[j], extras[i] end
  for _, d in ipairs(extras) do add(d) end
  -- headless or nothing imported: numbered cards still play
  local n = 1
  while #pool < M.PAIRS do
    if not seen[n] then seen[n] = true; pool[#pool + 1] = { dex = n } end
    n = n + 1
  end
  local cards = {}
  for i, p in ipairs(pool) do
    cards[#cards + 1] = { id = i, dex = p.dex, name = p.name }
    cards[#cards + 1] = { id = i, dex = p.dex, name = p.name }
  end
  for i = #cards, 2, -1 do local j = ctx.rng(i); cards[i], cards[j] = cards[j], cards[i] end
  g.cards = cards
  return g
end

function M:flip(i)
  local c = self.cards[i]
  if not c or c.matched or c.up or self.ending then return false end
  -- a mismatch still showing: put it away now
  if #self.open == 2 then
    for _, k in ipairs(self.open) do self.cards[k].up = false end
    self.open, self.hideIn = {}, nil
  end
  c.up = true
  c.flipT = 0
  self.open[#self.open + 1] = i
  if #self.open == 2 then
    self.turns = self.turns + 1
    local a, b = self.cards[self.open[1]], self.cards[self.open[2]]
    if a.id == b.id then
      a.matched, b.matched = true, true
      self.pairs = self.pairs + 1
      self.score = self.score + M.PAIR_POINTS
      self.open = {}
      Rewards.event(self.purse, "memory_pair", 1)
      if self.pairs >= #self.cards / 2 then
        local bonus = math.floor(self.left) * M.TIME_POINTS + math.max(0, M.TURN_PAR - self.turns) * M.TURN_POINTS
        self.score = self.score + bonus
        self.bonus = bonus
        self.ending = { why = "cleared", t = 0 }
        self.overText = ("Cleared in %d turns with %d s left!"):format(self.turns, math.floor(self.left))
        Rewards.event(self.purse, "memory_cleared", 1)
      end
    else
      self.hideIn = M.SHOW
    end
  end
  return true
end

M.END_PAUSE = 1.2

function M:update(dt)
  self.time = self.time + dt
  if self.ending then
    self.ending.t = self.ending.t + dt
    if self.ending.t >= M.END_PAUSE then self.over = self.ending.why end
    return
  end
  self.left = math.max(0, self.left - dt)
  for _, c in ipairs(self.cards) do if c.flipT then c.flipT = c.flipT + dt end end
  if self.hideIn then
    self.hideIn = self.hideIn - dt
    if self.hideIn <= 0 then
      for _, k in ipairs(self.open) do self.cards[k].up = false end
      self.open, self.hideIn = {}, nil
    end
  end
  if self.left <= 0 then
    self.ending = { why = "time", t = 0 }
    self.overText = ("Time! %d of %d pairs."):format(self.pairs, #self.cards / 2)
  end
end

-- the grid's shape for the area: 4 x 4, or 8 x 2 / 2 x 8 when very wide / tall
function M:shape(w, h)
  local ar = w / math.max(1, h)
  if ar > 2.6 then return 8, 2 elseif ar < 0.38 then return 2, 8 end
  return 4, 4
end

function M:input(a, x, y)
  local cols, rows = self.cols or 4, self.rows or 4
  if x and y then
    local L = self.layout
    if not L then return end
    local c = math.floor((x - L.x) / L.cw) + 1
    local r = math.floor((y - L.y) / L.ch) + 1
    if c >= 1 and c <= cols and r >= 1 and r <= rows then
      self.cur = (r - 1) * cols + c
      self:flip(self.cur)
    end
    return
  end
  self.keyed = true
  local c, r = (self.cur - 1) % cols + 1, math.floor((self.cur - 1) / cols) + 1
  if a == "left" then c = math.max(1, c - 1) elseif a == "right" then c = math.min(cols, c + 1)
  elseif a == "up" then r = math.max(1, r - 1) elseif a == "down" then r = math.min(rows, r + 1)
  elseif a == "a" then self:flip(self.cur) return end
  self.cur = (r - 1) * cols + c
end

function M:wattsFor() return math.floor((self.score or 0) / M.WATTS_PER_POINTS) end

function M:hud()
  return { { "Time", tostring(math.ceil(self.left)) }, { "Turns", tostring(self.turns) } }
end

function M:summary()
  local t = { ("%d pairs in %d turns."):format(self.pairs, self.turns) }
  if self.bonus then t[#t + 1] = ("Clear bonus: +%d"):format(self.bonus) end
  return t
end

-- ------------------------------------------------------------ drawing

function M:draw(x, y, w, h, Gfx, f, s)
  local g = love.graphics
  Gfx.scene(x, y, w, h, self.ctx.course.name, self.time * 4)
  g.setColor(0, 0, 0, 0.35)
  g.rectangle("fill", x, y, w, h)
  local cols, rows = self:shape(w, h)
  self.cols, self.rows = cols, rows
  local gap = math.max(6, 10 * s)
  -- cards a little taller than wide
  local cw = math.min((w - 20 - gap * (cols - 1)) / cols, ((h - 20 - gap * (rows - 1)) / rows) / 1.2)
  local ch = cw * 1.2
  local bw, bh = cw * cols + gap * (cols - 1), ch * rows + gap * (rows - 1)
  local bx, by = x + (w - bw) / 2, y + (h - bh) / 2
  self.layout = { x = bx, y = by, cw = cw + gap, ch = ch + gap }
  for i, c in ipairs(self.cards) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local cx, cy = bx + col * (cw + gap), by + row * (ch + gap)
    -- the flip: a squash about the middle
    local face = c.up or c.matched or (self.ending and self.ending.why == "time")
    local sq = 1
    if c.flipT and c.flipT < 0.15 then sq = math.max(0.05, c.flipT / 0.15) end
    local dx = cw * (1 - sq) / 2
    if face then
      Gfx.card(cx + dx, cy, cw * sq, ch, 10 * s, c.matched and { 0.18, 0.40, 0.30 } or { 0.92, 0.92, 0.88 }, 1)
      if sq > 0.6 then
        local ps = math.min(cw, ch) * 0.82
        Gfx.portrait(c.dex, cx + (cw - ps) / 2, cy + (ch - ps) / 2 - ch * 0.04, ps, c.name)
      end
    else
      Gfx.card(cx + dx, cy, cw * sq, ch, 10 * s, { 0.20, 0.35, 0.70 }, 1)
      g.setColor(1, 1, 1, 0.18)
      g.circle("line", cx + cw / 2, cy + ch / 2, math.min(cw, ch) * 0.28)
      g.circle("fill", cx + cw / 2, cy + ch / 2, math.min(cw, ch) * 0.08)
    end
    if self.keyed and self.cur == i and not self.ending then
      Gfx.setc(Gfx.GOLD)
      g.setLineWidth(3)
      g.rectangle("line", cx - 3, cy - 3, cw + 6, ch + 6, 12 * s)
      g.setLineWidth(1)
    end
  end
  -- the clock running out
  if self.left < 10 and not self.ending then
    Gfx.setc(Gfx.RED, 0.25 + 0.2 * math.sin(self.time * 10))
    g.rectangle("fill", x, y, w, 6 * s)
  end
end

return M
