-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DOWSING / TREASURE HUNT. A field of 6 x 6 grass tiles hides watt caches, a
-- big cache and up to two of the course's items. Twelve digs. An empty dig
-- tells you how near the closest buried thing still is: HOT (next to it),
-- WARM (two away), COOL (three) or COLD. Finding everything ends the run
-- early and every dig left over is worth a bonus.

local Rewards = require("src.pokewalker.minigames.Rewards")
local Context = require("src.pokewalker.minigames.Context")

local M = {}
M.id = "treasure"
M.title = "Treasure Hunt"
M.blurb = "Dig for buried watts and items with hot / cold hints."
M.howTo = {
  "Watts and items are buried under the grass. Tap a tile to dig (or move with the arrows / d-pad and press A).",
  "An empty hole says how close the nearest treasure is: Hot, Warm, Cool or Cold. You have 12 digs.",
}

-- THE KNOBS
M.COLS, M.ROWS = 6, 6
M.DIGS = 12
M.CACHES = 5                     -- small watt caches, 2..5 W of points each
M.BIG = 8                        -- the one big cache
M.ITEMS = 2                      -- at most, and only while the day's budget has room
M.POINTS_PER_W = 30
M.ITEM_POINTS = 150
M.LEFTOVER_DIG = 40
M.WATTS_PER_POINTS = 30
M.HINTS = { "Hot!", "Warm", "Cool", "Cold" }

function M.new(ctx, purse)
  local g = setmetatable({}, { __index = M })
  g.ctx, g.purse = ctx, purse
  g.score, g.time = 0, 0
  g.digs = M.DIGS
  g.cells = {}
  g.cur = { c = 1, r = 1 }
  g.found, g.foundW = 0, 0
  g.anims = {}
  for r = 1, M.ROWS do for c = 1, M.COLS do g.cells[(r - 1) * M.COLS + c] = { c = c, r = r } end end
  -- bury: shuffle the cells, take from the front
  local order = {}
  for i = 1, #g.cells do order[i] = i end
  for i = #order, 2, -1 do local j = ctx.rng(i); order[i], order[j] = order[j], order[i] end
  local k = 0
  local function nextCell() k = k + 1; return g.cells[order[k]] end
  for _ = 1, M.CACHES do local c = nextCell(); c.hide = { kind = "watts", w = 1 + ctx.rng(4) } end
  local big = nextCell(); big.hide = { kind = "watts", w = M.BIG, big = true }
  local nItems = math.min(M.ITEMS, math.max(0, math.min(Rewards.LIMITS.ITEMS_PER_RUN, Rewards.left(purse.st).items)))
  for _ = 1, nItems do local c = nextCell(); c.hide = { kind = "item", name = Context.pickItem(ctx) } end
  g.total = M.CACHES + 1 + nItems
  return g
end

function M:cell(c, r)
  if c < 1 or r < 1 or c > M.COLS or r > M.ROWS then return nil end
  return self.cells[(r - 1) * M.COLS + c]
end

-- distance (king's moves) to the nearest still-buried thing, or nil
function M:nearest(c, r)
  local best
  for _, cell in ipairs(self.cells) do
    if cell.hide and not cell.dug then
      local d = math.max(math.abs(cell.c - c), math.abs(cell.r - r))
      if not best or d < best then best = d end
    end
  end
  return best
end

function M:dig(c, r)
  local cell = self:cell(c, r)
  if not cell or cell.dug or self.ending or self.digs <= 0 then return nil end
  cell.dug = true
  self.digs = self.digs - 1
  self.anims[#self.anims + 1] = { c = c, r = r, t = 0 }
  local h = cell.hide
  if h then
    self.found = self.found + 1
    if h.kind == "watts" then
      self.score = self.score + h.w * M.POINTS_PER_W
      self.foundW = self.foundW + h.w
      Rewards.event(self.purse, "treasure_watts", h.w)
    else
      self.score = self.score + M.ITEM_POINTS
      h.kept = Rewards.addItem(self.purse, h.name)
      Rewards.event(self.purse, "treasure_item", 1)
    end
    cell.result = "found"
  else
    local d = self:nearest(c, r)
    cell.hint = d and math.min(4, d) or 4
    cell.result = "empty"
  end
  if self.found >= self.total then
    self.score = self.score + self.digs * M.LEFTOVER_DIG
    self.ending = { why = "cleared", t = 0 }
    self.overText = ("Found all %d treasures with %d digs to spare!"):format(self.total, self.digs)
    Rewards.event(self.purse, "treasure_cleared", 1)
  elseif self.digs <= 0 then
    self.ending = { why = "done", t = 0 }
    self.overText = ("Out of digs -- found %d of %d."):format(self.found, self.total)
  end
  if self.ending then for _, x in ipairs(self.cells) do x.reveal = true end end
  return cell
end

function M:input(a, x, y)
  if self.ending then return end
  if x and y then
    local L = self.layout
    if not L then return end
    local c = math.floor((x - L.x) / L.cell) + 1
    local r = math.floor((y - L.y) / L.cell) + 1
    if self:cell(c, r) then self.cur.c, self.cur.r = c, r; self:dig(c, r) end
    return
  end
  if a == "left" then self.cur.c = math.max(1, self.cur.c - 1)
  elseif a == "right" then self.cur.c = math.min(M.COLS, self.cur.c + 1)
  elseif a == "up" then self.cur.r = math.max(1, self.cur.r - 1)
  elseif a == "down" then self.cur.r = math.min(M.ROWS, self.cur.r + 1)
  elseif a == "a" then self:dig(self.cur.c, self.cur.r) end
  self.keyed = true
end

-- the board stays up a moment with everything shown before the results
M.END_PAUSE = 1.6

function M:update(dt)
  self.time = self.time + dt
  if self.ending then
    self.ending.t = self.ending.t + dt
    if self.ending.t >= M.END_PAUSE then self.over = self.ending.why end
  end
  for i = #self.anims, 1, -1 do
    local an = self.anims[i]
    an.t = an.t + dt
    if an.t > 0.8 then table.remove(self.anims, i) end
  end
end

function M:wattsFor() return math.floor((self.score or 0) / M.WATTS_PER_POINTS) end

function M:hud()
  return { { "Digs", tostring(self.digs) }, { "Found", ("%d/%d"):format(self.found, self.total) } }
end

function M:summary()
  return { ("Found %d of %d treasures (%d W of caches)."):format(self.found, self.total, self.foundW) }
end

-- ------------------------------------------------------------ drawing

local HINT_COL = { { 0.95, 0.30, 0.20 }, { 0.98, 0.62, 0.22 }, { 0.45, 0.70, 0.95 }, { 0.30, 0.42, 0.85 } }

function M:draw(x, y, w, h, Gfx, f, s)
  local g = love.graphics
  Gfx.scene(x, y, w, h, self.ctx.course.name, 0)
  g.setColor(0, 0, 0, 0.25)
  g.rectangle("fill", x, y, w, h)
  -- the board: square cells, as big as fit, with room for a line of text
  local textH = f.body:getHeight() + 16 * s
  local cell = math.floor(math.min((w - 24) / M.COLS, (h - textH - 24) / M.ROWS))
  local bw, bh = cell * M.COLS, cell * M.ROWS
  local bx, by = math.floor(x + (w - bw) / 2), math.floor(y + textH + (h - textH - bh) / 2)
  self.layout = { x = bx, y = by, cell = cell }
  g.setColor(0.30, 0.22, 0.14, 1)
  g.rectangle("fill", bx - 6, by - 6, bw + 12, bh + 12, 10)
  for _, c in ipairs(self.cells) do
    local cx, cy = bx + (c.c - 1) * cell, by + (c.r - 1) * cell
    local pad = math.max(2, cell * 0.05)
    if c.dug then
      g.setColor(0.45, 0.32, 0.20, 1)
      g.rectangle("fill", cx + pad, cy + pad, cell - pad * 2, cell - pad * 2, cell * 0.12)
      g.setColor(0.30, 0.20, 0.12, 1)
      g.ellipse("fill", cx + cell / 2, cy + cell / 2, cell * 0.3, cell * 0.2)
      if c.result == "empty" and c.hint then
        local col = HINT_COL[c.hint]
        Gfx.setc(col, 0.55)
        g.rectangle("fill", cx + pad, cy + pad, cell - pad * 2, cell - pad * 2, cell * 0.12)
        Gfx.setc(Gfx.INK)
        Gfx.fit(M.HINTS[c.hint], cx + pad, cy + cell / 2 - f.small:getHeight() / 2, cell - pad * 2, f.small, "center")
      end
    else
      local shade = ((c.c + c.r) % 2 == 0) and 0.04 or 0
      g.setColor(0.24 + shade, 0.58 + shade, 0.26, 1)
      g.rectangle("fill", cx + pad, cy + pad, cell - pad * 2, cell - pad * 2, cell * 0.12)
      g.setColor(0.18, 0.46, 0.20, 1)
      for k = 0, 2 do
        local gx = cx + cell * (0.25 + k * 0.25)
        g.polygon("fill", gx - cell * 0.06, cy + cell * 0.7, gx, cy + cell * 0.42, gx + cell * 0.06, cy + cell * 0.7)
      end
    end
    local hd = c.hide
    if hd and (c.dug or c.reveal) then
      local a = c.dug and 1 or 0.45
      if hd.kind == "watts" then
        Gfx.orb(cx + cell / 2, cy + cell * 0.42, cell * (hd.big and 0.24 or 0.17), self.time)
        g.setFont(f.small); Gfx.setc(Gfx.GOLD, a)
        g.printf(("%d W"):format(hd.w), cx, cy + cell * 0.68, cell, "center")
      else
        Gfx.item(hd.name, cx + cell / 2, cy + cell * 0.45, cell * 0.22)
        g.setFont(f.small); Gfx.setc(Gfx.INK, a)
        Gfx.fit(hd.name, cx + 2, cy + cell * 0.72, cell - 4, f.small, "center")
      end
      if not c.dug then g.setColor(0, 0, 0, 0.35); g.rectangle("fill", cx + pad, cy + pad, cell - 2 * pad, cell - 2 * pad, cell * 0.12) end
    end
    if self.keyed and self.cur.c == c.c and self.cur.r == c.r and not self.ending then
      Gfx.setc(Gfx.GOLD)
      g.setLineWidth(3)
      g.rectangle("line", cx + 2, cy + 2, cell - 4, cell - 4, cell * 0.12)
      g.setLineWidth(1)
    end
  end
  for _, an in ipairs(self.anims) do
    local cx, cy = bx + (an.c - 0.5) * cell, by + (an.r - 0.5) * cell
    g.setColor(0.55, 0.40, 0.25, 1 - an.t / 0.8)
    for k = 0, 5 do
      local ang = k * math.pi / 3
      local d = an.t * cell * 0.8
      g.circle("fill", cx + math.cos(ang) * d, cy + math.sin(ang) * d - an.t * cell * 0.3, cell * 0.05)
    end
  end
  -- the dowsing walker beside the line of text
  g.setFont(f.body); Gfx.setc(Gfx.INK)
  local msg = self.ending and (self.overText or "") or "Tap a tile to dig. Colours tell you how close you are."
  Gfx.fit(msg, x + 10, y + 8 * s, w - 20, f.body, "center")
end

return M
