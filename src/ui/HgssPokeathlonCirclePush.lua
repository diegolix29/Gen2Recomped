-- HEARTGOLD / SOULSILVER POKeATHLON: CIRCLE PUSH (pokeheartgold
-- asm/overlay_96.s 0x021F010C..0x021F5018, event 2, sub-app ov96_0221A7F4 =
-- init 021F010C / main 021F08E4 / results 021F08F4 / exit 021F095C, states
-- ov96_0221DB50 = { 021F0A7C fade in, 021F0AE0 play, 021F0B58 end }; the
-- reading is written up in scratch_claude/athlon/NOTES.md, "## Circle Push").
-- Art and tables: `gen4_hgss_circle_push`
-- (src/import/Gen4HgssPokeathlonCirclePushArt.lua).
--
-- THE STAGE is the touch screen itself: twelve Pokemon (four teams of three,
-- one corner each, ov96_0221BDD4) on a ring whose playable square is x 16..239,
-- y 16..175 (021F2F7C). A Pokemon's position here is the point the cartridge
-- tests the stage and the circles with (its feet); its "world" point, which
-- the stylus and the drag work on, is that + (2 + size class) - half the
-- sprite height up (021EB0A4 / 021EB06C: 13 px for a 32-px walker).
--
-- READ FROM CODE (the logic runs at the Pokeathlon's 30 frames a second):
--   * a Pokemon's numbers (021F2B24, NARC 170 MEMBER 1 -- not 2 -- by its
--     course record): push = [POWER] / 10 px a frame, stamina = [5 + STAMINA]
--     frames of pushing, walk = [10 + SPEED] / 10 px a frame (2.0 .. 3.5);
--     its body radius = NARC 170 member 11 by the performance row's byte 6
--     (8 / 14 / 18, ov96_021EAF70 + 021EB03C)
--   * SIX ROUNDS (021F1170): the clock steps every 8 frames in round 1, 6 in
--     rounds 2-3, 4 in rounds 4-6, and the round ends at step 43 (344 / 258 /
--     172 frames); the border's 43 chevron blocks clear one a step, clockwise
--     from the top middle (021F2984)
--   * THE CIRCLES (ov96_0221DBC8 / DBB8): 15 layouts, kinds 1 / 2 / 3 / 4 =
--     radius 56 / 32 / 24 / 16 worth 1 / 2 / 3 / 5. Round 1 is layout 0 (one
--     1); rounds 2-3 draw from 1..5 (a 3 and a 2), round 4 from 6..9 (a 2, 3, 5
--     -- layout 6 is 2, 2, 5), rounds 5-6 from 10..14 (two 5s and a 3 -- layout
--     10 is 5, 2, 5); the same group never repeats a layout (021F30F8)
--   * DRAGGING (021F1170 / 021F20C4 / 021F208C): a new touch takes the
--     NEAREST of the team's three whose world point is within 80 px (not while
--     one of them is pushing up or down, 021F2A84) and gives it a +2 px push
--     for 3 frames; while held, its target is the stylus (world point under
--     the stylus). Let go: nobody is held.
--   * WALKING (021F1CC0): towards the target at walk speed (0.5 when tired),
--     landing on it when within one step. A Pokemon on the stage that touches
--     another (radii + radii, 021F218C / 021F21EC) with the target beyond it
--     (021F22FC: any contact with dot > 0) does not walk: it PUSHES -- its push
--     vector is the direction x (push + the grab bonus), and stamina drops 1
--   * THE PUSH (021F234C): each pusher walks its chain of contacts forward
--     (dot > 0), adding its push to itself and passing it on whole when the
--     next one is within 45 deg, else projected onto the line to it; every
--     Pokemon moves by the sum of the pushes it got, and a pushed one stops
--     walking. A pusher out of stamina is let go and TIRED for 60 frames
--     (021F2AA4: then full stamina); one not pushing gets 2 stamina a frame
--   * OFF THE STAGE (021F1CC0): out of x 16..239 / y 16..175 = fallen (course
--     counters 5 and 1 = FAIL, 8 when dragged out); at the end of the round's
--     tally it comes back at its corner (021F2A00) as a ghost that touches
--     nothing until it is clear of everyone, with no stamina
--   * SCORING (021F2834): at step 43 each Pokemon on the stage in a circle
--     (feet nearer the centre than its radius, the first circle in the
--     layout's order) scores its points; the tally adds them one by one
--     every 6 frames after 20 (counter 3 = score), then 90 frames to the next
--     round (the new layout 30 frames in)
--   * THE RIVALS (021F342C / 021F350C): every 20 frames one Pokemon of each
--     rival team in turn (slot 2, 1, 0) thinks, 30 % of the time (up to three
--     times a cycle) not at all; it scores the 5 x 5 cells of 32 px around it
--     (+5 a point inside a circle, +4 the cell of a circle's centre -- which
--     then aims at the centre, -1 / -2 each Pokemon in the cell (-2 a
--     stronger rival), tired: +2 an empty cell, +2 its own, 0 a crowded one,
--     +4 if it stands in a circle); the best of the nearest 3 x 3 (its own
--     cell = stay) if that is 3 or more, else the best of all 25; ties at
--     random. The chosen one gets the grab bonus too.
--   * Athlete Points (ov96_0221A680): 3 x the team's points, at most 200.
--     Bulbapedia agrees (max 66 -> 198). No-Miss = never fell off. Effort
--     counter: fail.
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 021F010C puts them on the main
--     engine at y offset 0 (021E6290 r1), the touch screen here
--     (gSystem.screensFlipped = 1, main surface at 0 -- 021EB5C8); 021F0AE0
--     runs the countdown, play, then the finish with the field stopped
--
-- THE RECORD (READ FROM CODE; src/pokemon/HgssPokeathlonRecords.lua): after
-- the sixth round 021F107C hands ov96_021E8318 the team's points as the top
-- screen shows them (021F46B4: a byte, 021F4688) for NEW RECORD!
-- (021E839C, higher is better); the end state's field_5E0 (021F0B58, the
-- sum of the three's points) is what the course's end saves.
--
-- STAND-INS, said so: READY? (BG2) is shown under the 3-2-1; without
-- `gen4_hgss_athlon_common` the 3-2-1 is 3 s of numbers and the finish 3 s
-- of FINISH text; the top screen's layout (021F3E60 ..
-- 021F4FD8 not read through) is the frame, a panel, ROUND n and the team's
-- points in the big digits, and the four teams' points in text; a fallen
-- Pokemon shrinks (ov96_0221BC9C scales) and drops (BCB4) by eye; tired /
-- returning Pokemon are drawn grey (the cartridge greys their palette,
-- 021F1614) and the held one has a ring; team colours are drawn as rings
-- under the walkers (the cartridge's shadow sprites not read); the walkers'
-- world offset assumes their sprite's [0x28] is 0; no sounds but the
-- clock's warning (0x6D7, once a round at step 32 / 28 / 21) are played; the
-- clock's closing piece (ov96_0221BC8C) is not drawn; the walkers are
-- gen4_follow_mon sheets (or icons), facing the way they walk (the
-- cartridge's four-way pick, 021F1CC0, is by eye).

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local STEPS = 43                       -- the round ends at clock step 43
local GRAB_R = 80                      -- ov96_021E6104
local TIRED_FRAMES = 60
local NONE = 0                         -- no Pokemon held
local TEAM_RGB = { { 0.94, 0.25, 0.25 }, { 0.25, 0.45, 0.95 }, { 0.2, 0.75, 0.3 }, { 0.95, 0.85, 0.2 } }
local SE = { clock = 0x6D7 }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local POWER, STAMINA, SPEED = 0, 1, 4
local COS45 = math.cos(math.pi / 4)
-- ov96_0221BC9C / ov96_0221BCB4: a fallen Pokemon's scale and drop
local FALL_SCALE = { 1.0, 0.9, 0.8, 0.7, 0.6, 0.5 }
local FALL_DROP = { 0, 2, 6, 10, 14, 16 }

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function len(x, y) return math.sqrt(x * x + y * y) end
-- C's division of a signed int by 32 (toward zero)
local function div32(v) local q = v / 32; return q < 0 and math.ceil(q) or math.floor(q) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_circle_push
  return type(d) == "table" and d.params ~= nil and d.layouts ~= nil and d.stage ~= nil
end

-- ---------------------------------------------------------------- set up --

local function starsOf(game, mon, rival)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  if rival then
    local row = mon and P.row(game.data, mon)
    if row then return row.base end
    return { [0] = 1 + rand(3), 1 + rand(3), 1 + rand(3), 1 + rand(3), 1 + rand(3) }
  end
  local s = mon and P.stars(game.data, mon, mon.aprijuice)
  return s or { [0] = 2, 2, 2, 2, 2 }
end

-- the performance row's byte 6 (1..3): the size class
local function classOf(self, mon)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local rows = self.game.data.gen4_hgss_performance
  local idx = mon and P.ARC_IDX and P.ARC_IDX[tonumber(mon.species) or 0]
  local raw = type(rows) == "table" and idx and (rows[idx + (tonumber(mon.form) or 0)] or rows[idx])
  local class = type(raw) == "table" and tonumber(raw[7]) or 1
  if class < 1 or class > 3 then class = 1 end
  return class
end

local function star(st, k)
  local v = tonumber(st and st[k]) or 2
  return math.max(0, math.min(4, v))
end

-- the walking sheet's frame height (32 or 64), for the world offset
function M:sheetOf(mon)
  local fm = self.game.data.gen4_follow_mon
  if not (mon and type(fm) == "table" and fm.sheets) then return nil end
  local ok, Data = pcall(require, "src.import.Gen4HgssFollowMon")
  if not ok then return nil end
  local idx = Data.index(fm, tonumber(mon.species), tonumber(mon.form) or 0, false)
  return fm.sheets[idx] or fm.sheets[tostring(idx)]
end

local function newMon(self, mon, st, t, k)
  local p = self.d.params
  local class = classOf(self, mon)
  local size = self.d.sizes and self.d.sizes[class]
  local sheet = self:sheetOf(mon)
  local half = (sheet and tonumber(sheet.frameHeight) or 32) >= 64 and 32 or 16
  local start = self.d.starts[t][k]
  return {
    mon = mon, team = t, slot = k, id = (t - 1) * 3 + k,
    power = p[0 + star(st, POWER)],
    stamMax = p[5 + star(st, STAMINA)], stamina = p[5 + star(st, STAMINA)],
    speed = p[10 + star(st, SPEED)],
    radius = size and size[2] or 8,
    -- 021EB0A4: world y = feet y + [0x10] - [0x18] (+ [0x28] / 2)
    wdy = (2 + class) - half,
    x = start[1], y = start[2], tx = start[1], ty = start[2],
    state = 1, pushing = false, px = 0, py = 0,
    tired = false, tiredT = 0, boost = 0, boostT = 0,
    points = 0, fail = 0, fell = false, dragOut = false,
    face = "down", step = 0, fall = 0,
  }
end

-- opts: team (three Pokemon), rivals ({3}, {3}, {3}), onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, frame = 0, images = {} }, M)
  local d = game.data.gen4_hgss_circle_push
  self.d = d
  self.mons = {}
  self.teams = {}
  for t = 1, 4 do
    local list = {}
    for k = 1, 3 do
      local mon = t == 1 and opts.team[k] or (opts.rivals and opts.rivals[t - 1] and opts.rivals[t - 1][k])
      local m = newMon(self, mon, starsOf(game, mon, t > 1), t, k)
      list[k] = m
      self.mons[m.id] = m
    end
    self.teams[t] = { id = t, cpu = t > 1, mons = list, total = 0, sel = NONE }
  end
  self.me = self.teams[1]
  self.contact = {}
  for i = 1, 12 do self.contact[i] = {} end
  self.round = 0             -- 0x727 (0-based)
  self.layout = 0            -- 0x730
  self.tick, self.clock = 0, 0 -- 0x725 / 0x726
  self.tally = nil           -- 0x74A..0x75C
  self.nextDelay = 0         -- 0x728
  self.scoreNow = false      -- 0x72B
  self.pops = {}
  self.ai = { tick = 0, every = 20, think = false, team = 0, rot = 0, skips = { [0] = 0, 0, 0 } }
  self.touch = { down = false, new = false, x = 0, y = 0 }
  self.pad = { x = 128, y = 96, held = false }
  self.countdown = 90
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (021F010C)
  if CD.available(game) then self.cd = CD.new(game, 0) end
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

-- ------------------------------------------------------------------ rules --

local function offStage(x, y)
  return x < 16 or x >= 240 or y < 16 or y >= 176
end

-- the circles of the current layout: { r, pts, x, y }
function M:circles()
  local out = {}
  for _, c in ipairs(self.d.layouts[self.layout] or self.d.layouts[tostring(self.layout)] or {}) do
    local kind = self.d.kinds[c[1]]
    out[#out + 1] = { kind = c[1], r = kind.r, pts = kind.pts, x = c[2], y = c[3] }
  end
  return out
end

-- 021F3180: the points (and the circle's index) at a point
function M:pointsAt(x, y)
  for i, c in ipairs(self:circles()) do
    if len(x - c.x, y - c.y) < c.r then return c.pts, i end
  end
  return 0
end

-- 021F30F8: the next layout for the group of round `r` (0-based)
function M:nextLayout(r)
  local base, n
  if r < 1 then return 0 end
  if r < 3 then base, n = 1, 5 elseif r < 4 then base, n = 6, 4 else base, n = 10, 5 end
  local cur = self.layout
  local curGroup = cur < 1 and 0 or (cur < 6 and 1 or (cur < 10 and 2 or 3))
  local want = r < 3 and 1 or (r < 4 and 2 or 3)
  if curGroup == want then
    return ((cur - base + 1) + rand(n - 1)) % n + base
  end
  return base + rand(n)
end

-- 021F218C: two bodies touch
local function touching(a, b)
  return len(a.x - b.x, a.y - b.y) <= a.radius + b.radius
end

-- 021F21EC: the contact table (on-stage Pokemon only)
function M:contacts()
  for i = 1, 12 do
    local a = self.mons[i]
    for j = i, 12 do
      local b = self.mons[j]
      local c = false
      if j ~= i and a.state == 1 and b.state == 1 and touching(a, b) then c = true end
      self.contact[i][j], self.contact[j][i] = c, c
    end
  end
end

-- 021F22FC: nothing in the way along (dx, dy)?
function M:free(m, dx, dy)
  for j = 1, 12 do
    if self.contact[m.id][j] then
      local o = self.mons[j]
      if dx * (o.x - m.x) + dy * (o.y - m.y) > 0 then return false end
    end
  end
  return true
end

-- 021F2AA4: a Pokemon not pushing
local function recover(m)
  if m.tired then
    m.tiredT = m.tiredT - 1
    if m.tiredT <= 0 then m.tiredT, m.tired, m.stamina = 0, false, m.stamMax end
    return
  end
  m.stamina = math.min(m.stamina + 2, m.stamMax)
  if m.stamina == m.stamMax then m.tired, m.tiredT = false, 0 end
end

-- ov96_021E8228 kinds: 1 fail, 3 score, 5 / 8 (fell, dragged out)
function M:fallOff(m)
  m.state, m.tired, m.tiredT = 0, false, 0
  m.fail = m.fail + 1
  m.fell = true
  m.fall = 1
  if m.dragOut then m.impede = (m.impede or 0) + 1 end   -- kind 8 (021F1CC0)
  m.dragOut = false
  for _, tm in ipairs(self.teams) do if tm.sel == m.id then tm.sel = NONE end end
end

-- 021F1CC0 + 021F234C, once a frame
function M:physics()
  for i = 1, 12 do
    local m = self.mons[i]
    if m.boost ~= 0 then
      m.boostT = m.boostT - 1
      if m.boostT <= 0 then m.boost = 0 end
    end
    if m.state ~= 0 and offStage(m.x, m.y) then self:fallOff(m) end
  end
  -- a returning Pokemon joins in once it touches nobody
  for i = 1, 12 do
    local m = self.mons[i]
    if m.state == 2 then
      local clear = true
      for j = 1, 12 do
        local o = self.mons[j]
        if j ~= i and o.state ~= 0 and touching(m, o) then clear = false; break end
      end
      if clear then m.state = 1 end
    end
  end
  for i = 1, 12 do
    local m = self.mons[i]
    if m.state ~= 0 then
      m.pushing, m.px, m.py = false, 0, 0
      local dx, dy = m.tx - m.x, m.ty - m.y
      local dist = len(dx, dy)
      if dist <= 0 then
        recover(m)
      else
        local nx, ny = dx / dist, dy / dist
        local s = m.tired and 0.5 or m.speed / 10
        local gx, gy
        if dist <= s then gx, gy = m.tx, m.ty else gx, gy = m.x + nx * s, m.y + ny * s end
        if math.abs(nx) >= math.abs(ny) then m.face = nx < 0 and "left" or "right"
        else m.face = ny < 0 and "up" or "down" end
        m.step = m.step + 1
        if m.state == 1 then
          if not self:free(m, dx, dy) then
            if not m.tired then
              m.pushing = true
              local f = m.power / 10 + m.boost
              m.px, m.py = nx * f, ny * f
              if m.stamina > 0 then m.stamina = m.stamina - 1 end
            end
          else
            recover(m)
            m.x, m.y = gx, gy
          end
        else
          m.stamina = 0
          m.x, m.y = gx, gy
        end
      end
    end
  end
  self:pushes()
end

-- 021F234C: the pushes passed along the chains
function M:pushes()
  local pushers, before = {}, {}
  for i = 1, 12 do
    local m = self.mons[i]
    if m.pushing and m.state == 1 then pushers[#pushers + 1] = m end
    before[i] = { m.tx - m.x, m.ty - m.y }
  end
  if #pushers == 0 then return end
  local sums = {}
  for n, p in ipairs(pushers) do
    local acc = {}
    for i = 1, 12 do acc[i] = { 0, 0 } end
    local visited, stack, lists = {}, {}, {}
    local cur, vx, vy, adding = p.id, p.px, p.py, true
    while cur do
      visited[cur] = true
      if adding then
        local list = { at = 1 }
        local a = self.mons[cur]
        for j = 1, 12 do
          if self.contact[cur][j] then
            local o = self.mons[j]
            local ex, ey = o.x - a.x, o.y - a.y
            if vx * ex + vy * ey > 0 then list[#list + 1] = { j = j, x = ex, y = ey } end
          end
        end
        lists[cur] = list
        acc[cur][1], acc[cur][2] = acc[cur][1] + vx, acc[cur][2] + vy
      end
      local list = lists[cur]
      local nxt = list[list.at]
      if not nxt then
        visited[cur] = false
        cur = table.remove(stack)
        adding = false
      elseif visited[nxt.j] then
        list.at = list.at + 1
        adding = false
      else
        if #stack >= 12 then break end
        stack[#stack + 1] = cur
        local ax, ay = acc[cur][1], acc[cur][2]
        local al, el = len(ax, ay), len(nxt.x, nxt.y)
        local cosv = (al > 0 and el > 0) and (ax * nxt.x + ay * nxt.y) / (al * el) or 0
        if cosv >= COS45 then
          vx, vy = ax, ay
        else
          -- 021F27B8: onto the line to it
          local k = al * cosv
          vx, vy = nxt.x / el * k, nxt.y / el * k
        end
        list.at = list.at + 1
        cur, adding = nxt.j, true
      end
    end
    sums[n] = acc
  end
  for n, p in ipairs(pushers) do
    local acc = sums[n]
    for i = 1, 12 do
      local m = self.mons[i]
      local ax, ay = acc[i][1], acc[i][2]
      m.x, m.y = m.x + ax, m.y + ay
      if len(ax, ay) ~= 0 and not m.pushing then m.tx, m.ty = m.x, m.y end
    end
    if p.stamina == 0 then
      for _, tm in ipairs(self.teams) do if tm.sel == p.id then tm.sel = NONE end end
      p.tired, p.tiredT = true, TIRED_FRAMES
      p.tx, p.ty, p.px, p.py, p.pushing = p.x, p.y, 0, 0, false
    end
  end
  for i = 1, 12 do
    local m = self.mons[i]
    if (m.tx - m.x) * before[i][1] + (m.ty - m.y) * before[i][2] < 0 then m.tx, m.ty = m.x, m.y end
  end
end

-- 021F2A84: may the team take a new Pokemon?
local function mayGrab(tm)
  for _, m in ipairs(tm.mons) do if m.py ~= 0 then return false end end
  return true
end

-- the player's stylus, once a frame (021F1170 for participant 0)
function M:stepInput(tm)
  local tc = self.touch
  local new, held = tc.new, tc.down
  tc.new = false
  if not held then tm.sel = NONE; return end
  if new then
    if mayGrab(tm) then
      -- 021F20C4: the nearest of the three, world point within 80 px
      local best, bd = nil, GRAB_R
      for _, m in ipairs(tm.mons) do
        local dd = len(m.x - tc.x, m.y + m.wdy - tc.y)
        if dd < bd then best, bd = m, dd end
      end
      if best then
        tm.sel = best.id
        best.boost, best.boostT = 2, 3
      end
    end
  elseif tm.sel ~= NONE then
    local m = self.mons[tm.sel]
    -- 021F208C: the world point goes under the stylus
    local tx, ty = tc.x, tc.y - m.wdy
    if len(tx - m.x, ty - m.y) > 0 then m.tx, m.ty = tx, ty end
    m.dragOut = offStage(m.tx, m.ty)
  end
end

-- ------------------------------------------------------------------ rivals --

-- 021F38FC: a point's 32-px cell (7 x 5 from (16, 16)), -1 off the grid
local function cellOf(x, y)
  local c, r = div32(math.floor(x) - 16), div32(math.floor(y) - 16)
  if c < 0 or r < 0 then return -1 end
  local id = c + 7 * r
  if id > 34 then return -1 end
  return id
end

-- 021F3930: one spot's worth to Pokemon `me`
function M:spotScore(me, cells, circles, circleCells, cand)
  if cand.id < 0 then return 0, false end
  local function inCircle(x, y)
    for _, c in ipairs(circles) do if len(x - c.x, y - c.y) < c.r then return true end end
    return false
  end
  local function crowd()
    if cells[me.id] == -1 then return 0 end
    local s = 0
    for j = 1, 12 do
      if j ~= me.id and cells[j] == cand.id then
        local o = self.mons[j]
        if me.power < o.power then s = s - (o.team == me.team and 1 or 2) else s = s - 1 end
      end
    end
    return s
  end
  local s, flag = 0, false
  if inCircle(cand.px, cand.py) then s = s + 5 end
  if circleCells[cand.id] then s, flag = s + 4, true end
  if me.stamina ~= 0 and me.state == 1 then
    s = s + crowd()
  else
    local c = crowd()
    if c == 0 then s = s + 2 end
    if cells[me.id] == cand.id then s = s + 2 end
    if c ~= 0 then s = 0 end
    if inCircle(me.x, me.y + me.wdy) then s = s + 4 end
  end
  return s, flag
end

-- 021F350C: one rival Pokemon's think
function M:think(me)
  if me.state == 0 then return end
  local ai = self.ai
  if ai.skips[ai.rot] < 3 and rand(100) < 30 then
    ai.skips[ai.rot] = ai.skips[ai.rot] + 1
    return
  end
  local cells = {}
  for j = 1, 12 do
    local o = self.mons[j]
    cells[j] = o.state ~= 0 and cellOf(o.x, o.y - 5) or -1
  end
  cells[me.id] = cellOf(me.x, me.y)
  local circles = self:circles()
  local circleCells, centreOf = {}, {}
  for _, c in ipairs(circles) do
    local id = cellOf(c.x, c.y)
    if id >= 0 and not centreOf[id] then circleCells[id], centreOf[id] = true, c end
  end
  local col, row = div32(math.floor(me.x) - 16), div32(math.floor(me.y) - 16)
  local all, inner, outer = {}, {}, {}
  for k = 0, 24 do
    local dc, dr = k % 5 - 2, math.floor(k / 5) - 2
    local c, r = col + dc, row + dr
    local cand = { col = c, row = r, valid = c >= 0 and r >= 0 and c < 7 and r < 5, k = k }
    all[k + 1] = cand
    if math.abs(dc) <= 1 and math.abs(dr) <= 1 then inner[#inner + 1] = cand else outer[#outer + 1] = cand end
  end
  -- 021F380C: a random point in each cell
  local function place(list)
    for _, c in ipairs(list) do
      if c.valid then
        c.px, c.py, c.id = c.col * 32 + 16 + rand(32), c.row * 32 + 16 + rand(32), c.col + 7 * c.row
      else
        c.px, c.py, c.id = -1, -1, -1
      end
    end
  end
  -- 021F3888 + 021F3B38: score, sort (stable, best first), count the ties
  local function rank(list)
    for _, c in ipairs(list) do
      if not c.valid then c.score = -100
      else
        local s, flag = self:spotScore(me, cells, circles, circleCells, c)
        c.score = s
        if flag then c.px, c.py = centreOf[c.id].x, centreOf[c.id].y end
      end
    end
    local sorted = {}
    for _, c in ipairs(list) do
      local at = #sorted + 1
      for i, o in ipairs(sorted) do if o.score < c.score then at = i; break end end
      table.insert(sorted, at, c)
    end
    local ties = 0
    for _, c in ipairs(sorted) do if c.score == sorted[1].score then ties = ties + 1 end end
    return sorted, ties
  end
  place(inner)
  inner[5].px, inner[5].py = me.x, me.y      -- its own cell: stay
  local sorted, ties = rank(inner)
  if sorted[1].score < 3 then
    place(outer)
    sorted, ties = rank(all)
  end
  local pick = sorted[rand(math.max(1, ties)) + 1]
  me.tx, me.ty = pick.px, pick.py
end

-- 021F342C: every 20 frames, one rival team a frame
function M:stepAi()
  local ai = self.ai
  ai.tick = ai.tick + 1
  if ai.tick >= ai.every then
    ai.think, ai.tick = true, 0
    for k = 0, 2 do ai.skips[k] = 0 end
  end
  if not ai.think then return end
  local tm = self.teams[2 + ai.team]
  local m = tm.mons[(2 - ai.rot) + 1]
  self:think(m)
  m.boost, m.boostT = 2, 3
  ai.team = ai.team + 1
  if ai.team >= 3 then
    ai.team, ai.rot, ai.think = 0, (ai.rot + 1) % 3, false
  end
end

-- ------------------------------------------------------------------ rounds --

-- 021F2834: who is in a circle when the round ends
function M:score()
  local byCircle = {}
  for i = 1, 12 do
    local m = self.mons[i]
    if m.state == 1 then
      local pts, c = self:pointsAt(m.x, m.y)
      if pts > 0 then
        m.points = m.points + pts
        byCircle[c] = byCircle[c] or {}
        table.insert(byCircle[c], { m = m, pts = pts })
      end
    end
  end
  local list = {}
  for c = 1, 4 do for _, e in ipairs(byCircle[c] or {}) do list[#list + 1] = e end end
  self.tally = { list = list, at = 1, delay = 20, gap = 0 }
end

-- 021F2A00: the fallen come back at their corners
function M:returnFallen()
  for _, m in ipairs(self.mons) do
    if m.state == 0 then
      local s = self.d.starts[m.team][m.slot]
      m.state, m.x, m.y, m.tx, m.ty, m.fall, m.face = 2, s[1], s[2], s[1], s[2], 0, "down"
    end
  end
end

function M:endRound()
  self.scoreNow = true
  for _, tm in ipairs(self.teams) do tm.sel = NONE end
  for _, m in ipairs(self.mons) do
    m.tx, m.ty, m.px, m.py = m.x, m.y, 0, 0
    m.stamina, m.tired, m.tiredT, m.boost, m.boostT = m.stamMax, false, 0, 0, 0
  end
end

-- 021F1170's round control
function M:stepRound()
  if self.waitNext then
    self.waitNext, self.clock, self.tally = false, 0, nil
    self.tick = 0
  elseif self.nextDelay > 0 then
    self.nextDelay = self.nextDelay - 1
    if self.nextDelay == 0 then
      self.waitNext = true
    elseif self.nextDelay == 60 then
      self.round = self.round + 1
      if self.round < 6 then self.layout = self:nextLayout(self.round) end
    end
  elseif self.tally then
    local tl = self.tally
    self.clock = STEPS + 1
    if tl.delay > 0 then tl.delay = tl.delay - 1
    elseif tl.gap > 0 then tl.gap = tl.gap - 1
    elseif tl.at > #tl.list then
      self:returnFallen()
      self.nextDelay = 90
    else
      local e = tl.list[tl.at]
      self.teams[e.m.team].total = self.teams[e.m.team].total + e.pts
      self.pops[#self.pops + 1] = { m = e.m, pts = e.pts, t = 0 }
      tl.at, tl.gap = tl.at + 1, 6
    end
  else
    self.tick = self.tick + 1
    local every = self.round < 1 and 8 or (self.round < 3 and 6 or 4)
    if self.tick >= every then
      self.tick = 0
      self.clock = self.clock + 1
      if self.clock >= STEPS then self:endRound() end
    end
  end
  if self.round >= 6 and not self.over then
    self.over = 90
    if self.cd then self.cd:startFinish(Rec.isNew(self.game, 2, self.me.total % 256)) end
  end
end

function M:step()
  self.frame = self.frame + 1
  local prevClock = self.clock
  self:stepRound()
  if self.over then return end
  -- 0x74A: no stylus and no thinking from the round's end to the next start
  if not self.tally then
    self:stepInput(self.me)
    self:stepAi()
  end
  self:physics()
  self:contacts()
  if self.scoreNow then
    self.scoreNow = false
    self:score()
  end
  for i = #self.pops, 1, -1 do
    local p = self.pops[i]
    p.t = p.t + 1
    if p.t > 30 then table.remove(self.pops, i) end
  end
  for _, m in ipairs(self.mons) do if m.state == 0 and m.fall > 0 then m.fall = m.fall + 1 end end
  -- the clock's warning, once a round (021F1614, flag 0x7A8)
  if self.clock ~= prevClock and not self.tally then
    local warn = self.round < 1 and 32 or (self.round < 3 and 28 or 21)
    if self.clock == warn then se(self, SE.clock) end
  end
end

-- ------------------------------------------------------------------ input --

local function toLocal(game, x, y)
  local px, py = SecondScreen.toLocal(game, x, y)
  if not px then
    if SecondScreen.separate(game) then return nil end
    local rect = require("src.render.Renderer").uiPresentation
    if rect then px, py = (x - rect.x) / rect.scaleX, (y - rect.y) / rect.scaleY else px, py = x, y end
  end
  return px, py
end

function M:touchpressed(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if not px then return false end
  local tc = self.touch
  tc.down, tc.new, tc.x, tc.y = true, true, px, py
  return true
end
function M:touchmoved(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if px and self.touch.down then self.touch.x, self.touch.y = px, py end
  return true
end
function M:touchreleased(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if px then self.touch.x, self.touch.y = px, py end
  self.touch.down = false
  return true
end

-- PAD / KEYS (not the cartridge's): a cursor stands in for the stylus --
-- the D-pad moves it, A held is the stylus down (a press grabs the nearest),
-- B jumps the cursor to the next of the team; SELECT / L shows the top screen
function M:padInput()
  local input = self.game.input
  if not input or self.padOff then return end
  if input:wasPressed("select") or input:wasPressed("l") then self.showTop = not self.showTop end
  local pd = self.pad
  local sp = 3
  if input:isDown("left") then pd.x = pd.x - sp end
  if input:isDown("right") then pd.x = pd.x + sp end
  if input:isDown("up") then pd.y = pd.y - sp end
  if input:isDown("down") then pd.y = pd.y + sp end
  pd.x, pd.y = math.max(0, math.min(W - 1, pd.x)), math.max(0, math.min(H - 1, pd.y))
  if input:wasPressed("b") then
    pd.cycle = (pd.cycle or 0) % 3 + 1
    local m = self.me.mons[pd.cycle]
    pd.x, pd.y = m.x, m.y + m.wdy
  end
  local a = input:isDown("a")
  local tc = self.touch
  if a and not pd.held then
    tc.down, tc.new, tc.x, tc.y, pd.held = true, true, pd.x, pd.y, true
  elseif a and pd.held then
    tc.x, tc.y = pd.x, pd.y
  elseif pd.held then
    tc.down, pd.held = false, false
  end
end

function M:update()
  self.t = self.t + 1
  self:padInput()
  -- the Pokeathlon's 30 frames a second
  if self.t % 2 == 1 then return end
  if self.countdown > 0 then
    if self.cd then
      -- the shared 3-2-1 (021E637C)
      if self.cd:countdown() then self.countdown = 0 end
      return
    end
    self.countdown = self.countdown - 1
    return
  end
  if self.over and self.cd then
    -- the FINISH (021E667C), the field stopped (021F0AE0 state 2)
    if not self.cd:finishing() then return self:finish() end
    return
  end
  if self.over then
    self.over = self.over - 1
    if self.over <= 0 then return self:finish() end
    return
  end
  self:step()
end

-- ov96_021F0B58 (field5E0 = the team's points) and ov96_0221A680 (x 3, cap 200)
function M:finish()
  if self.done then return end
  self.done = true
  local pts, stats = {}, {}
  for t, tm in ipairs(self.teams) do
    pts[t] = math.min(200, tm.total * 3)
    stats[t] = {}
    for k, m in ipairs(tm.mons) do
      stats[t][k] = { miss = m.fell, score = m.points, jump = 0, dash = 0, hit = 0, fail = m.fail,
        fall = m.fail, impede = m.impede or 0 }   -- kinds 5 / 8 (5 and 1 come together)
    end
  end
  self.game.stack:pop()
  if self.onDone then
    self.onDone({ points = pts, total = self.me.total, stats = stats, record = self.me.total })
  end
end

-- ------------------------------------------------------------------- draw --

-- an image from a saved path (rec.path) or decoded in memory (rec.image)
function M:img(key)
  local rec = self.d[key]
  if rec == nil then return nil end
  if type(rec) == "table" and rec.image and not rec.path then
    if not self.images[rec] then
      local ok, img = pcall(love.graphics.newImage, rec.image)
      self.images[rec] = ok and img or false
      if self.images[rec] then self.images[rec]:setFilter("nearest", "nearest") end
    end
    return self.images[rec] or nil, rec
  end
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.images[path] = ok and img or false
    if self.images[path] then self.images[path]:setFilter("nearest", "nearest") end
  end
  return self.images[path] or nil, rec
end

function M:sprite(key, x, y, sx)
  local img, rec = self:img(key)
  if not img then return false end
  local ox = type(rec) == "table" and tonumber(rec.originX) or 0
  local oy = type(rec) == "table" and tonumber(rec.originY) or 0
  sx = sx or 1
  love.graphics.draw(img, math.floor(x + ox * sx), math.floor(y + oy * sx), 0, sx, sx)
  return true
end

-- the sequence's frame at time t (frame durations from the art's objSeq)
function M:anim(set, seq, t, once)
  local list = self.d.objSeq and self.d.objSeq[set] and (self.d.objSeq[set][seq] or self.d.objSeq[set][tostring(seq)])
  if type(list) ~= "table" or #list == 0 then return ("%s_%d_0"):format(set, seq) end
  local total = 0
  for _, v in ipairs(list) do total = total + v end
  local at = once and math.min(t, total - 1) or t % math.max(1, total)
  for f, v in ipairs(list) do
    if at < v then return ("%s_%d_%d"):format(set, seq, f - 1) end
    at = at - v
  end
  return ("%s_%d_%d"):format(set, seq, #list - 1)
end

local function cachedImage(self, path)
  self.monImgs = self.monImgs or {}
  if self.monImgs[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.monImgs[path] = ok and img or false
    if self.monImgs[path] then self.monImgs[path]:setFilter("nearest", "nearest") end
  end
  return self.monImgs[path] or nil
end

local GREY_SRC = [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 p = Texel(tex, tc) * color;
  float y = dot(p.rgb, vec3(0.299, 0.587, 0.114));
  return vec4(y, y, y, p.a);
}
]]

function M:grey()
  if self.greyShader == nil then
    local ok, sh = pcall(love.graphics.newShader, GREY_SRC)
    self.greyShader = ok and sh or false
  end
  return self.greyShader or nil
end

-- the walking Pokemon (gen4_follow_mon), or its icon; (x, y) = its feet
function M:walker(m, x, y, scale)
  local mon = m.mon
  if not mon then return end
  local g = love.graphics
  local data = self.game.data
  local sheet = self:sheetOf(mon)
  local path = sheet and ((mon.shiny or mon.isShiny) and sheet.shiny or sheet.normal)
  local img = type(path) == "string" and cachedImage(self, path)
  scale = scale or 1
  if img then
    local fw, fh = tonumber(sheet.frameWidth) or 32, tonumber(sheet.frameHeight) or 32
    local iw, ih = img:getDimensions()
    local base = ({ up = 0, down = 2, left = 4, right = 6 })[m.face] or 2
    local f = base + (math.floor(m.step / 6) % 2)
    if (f + 1) * fh > ih then f = 0 end
    -- the sprite's centre is the world point (021EAF94)
    local cy = y + m.wdy
    g.draw(img, g.newQuad(0, f * fh, fw, fh, iw, ih), math.floor(x - fw / 2 * scale), math.floor(cy - fh / 2 * scale), 0, scale, scale)
    return
  end
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (data.icons and data.icons.bySpecies and data.icons.bySpecies[mon.species]) or (def and def.icon)
  local ipath, fh = entry, nil
  if type(entry) == "table" then ipath, fh = entry.image, tonumber(entry.frameHeight) end
  local icon = type(ipath) == "string" and cachedImage(self, ipath)
  if not icon then return end
  local iw, ih = icon:getDimensions()
  fh = fh or math.min(iw, ih)
  local frames = math.max(1, math.floor(ih / fh))
  g.draw(icon, g.newQuad(0, (math.floor(m.step / 6) % frames) * fh, iw, fh, iw, ih),
    math.floor(x - iw / 2 * scale), math.floor(y + m.wdy - fh / 2 * scale), 0, scale, scale)
end

-- 021F2984: clock step n's 16 x 16 block on BG1 (tile x, tile y)
local function clockBlock(n)
  if n >= 1 and n <= 6 then return 0x12 + 2 * (n - 1), 2 end
  if n >= 16 and n <= 28 then return 0x1a - 2 * (n - 16), 0x14 end
  if n >= 0x26 and n < 0x2b then return 4 + 2 * (n - 0x26), 2 end
  if n >= 7 and n <= 15 then return 0x1c, 4 + 2 * (n - 7) end
  return 2, 0x12 - 2 * (n - 0x1d)
end

-- the touch screen: the ring, the circles, the clock, the Pokemon
function M:drawBottom()
  local g = love.graphics
  g.setColor(0.15, 0.12, 0.2, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local stage = self:img("stage")
  if stage then g.draw(stage, 0, 0) end
  -- BG1: the chevrons not yet cleared
  local border = self:img("border")
  if border then
    local iw, ih = border:getDimensions()
    for n = 1, STEPS do
      if n > self.clock then
        local tx, ty = clockBlock(n)
        g.draw(border, g.newQuad(tx * 8, ty * 8, 16, 16, iw, ih), tx * 8, ty * 8)
      end
    end
    if self.clock < STEPS then
      -- the gap at the top (x 112..143) stays as BG1 has it
      g.draw(border, g.newQuad(112, 16, 32, 16, iw, ih), 112, 16)
    end
  end
  -- the circles (sprite set 0x65, sequence kind - 1)
  if self.round < 6 then
    for _, c in ipairs(self:circles()) do self:sprite(("ring_%d_0"):format(c.kind - 1), c.x, c.y) end
  end
  -- the Pokemon, back to front
  local order = {}
  for _, m in ipairs(self.mons) do order[#order + 1] = m end
  table.sort(order, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.id < b.id end)
  for _, m in ipairs(order) do
    local x, y, scale = m.x, m.y, 1
    local visible = true
    if m.state == 0 then
      local k = math.min(#FALL_SCALE, math.max(1, math.floor(m.fall / 2) + 1))
      scale = FALL_SCALE[k]
      if m.y >= 176 then y = y + FALL_DROP[k] end
      if m.fall > 12 then visible = false end
    end
    if visible then
      local rgb = TEAM_RGB[m.team]
      if m.state ~= 0 then
        g.setColor(rgb[1], rgb[2], rgb[3], 0.85)
        g.ellipse("line", math.floor(x) + 0.5, math.floor(y) + 0.5, m.radius + 2, (m.radius + 2) * 0.55)
        if self.teams[m.team].sel == m.id then
          g.setColor(1, 1, 1, 0.9)
          g.ellipse("line", math.floor(x) + 0.5, math.floor(y) + 0.5, m.radius + 5, (m.radius + 5) * 0.55)
        end
      end
      g.setColor(1, 1, 1, 1)
      local greyed = m.state == 2 or (m.tired and math.floor(self.t / 8) % 2 == 0)
      local sh = greyed and self:grey() or nil
      if sh then g.setShader(sh) elseif greyed then g.setColor(0.6, 0.6, 0.6, 1) end
      self:walker(m, x, y, scale)
      if sh then g.setShader() end
      g.setColor(1, 1, 1, 1)
    end
  end
  -- the tally's points popping up (sprite set 0x68, sequences 3..6)
  local PTS_SEQ = { [1] = 3, [2] = 4, [3] = 5, [5] = 6 }
  for _, p in ipairs(self.pops) do
    self:sprite(self:anim("a", PTS_SEQ[p.pts] or 3, p.t, true), p.m.x, p.m.y + p.m.wdy - 16)
  end
  local Font = require("src.render.Font")
  if self.countdown > 0 then
    g.setColor(1, 1, 1, 0.75)
    local ov = self:img("overlay")
    if ov then g.draw(ov, 0, 0) end
    g.setColor(1, 1, 1, 1)
    if not self.cd then
      g.setColor(0, 0, 0, 0.5)
      g.rectangle("fill", 112, 128, 32, 24)
      g.setColor(1, 1, 1, 1)
      Font.draw(tostring(math.ceil(self.countdown / 30)), 124, 136)
    end
  elseif self.over and not self.cd then
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", 88, 84, 80, 24)
    g.setColor(1, 1, 1, 1)
    Font.draw("FINISH!", 100, 92)
  end
  -- the shared 3-2-1 / FINISH (main engine = this screen, surface at 0)
  if self.cd then self.cd:draw(0) end
end

-- the top screen: the frame, ROUND n, the team's points
function M:drawTop()
  local g = love.graphics
  g.setColor(0.05, 0.08, 0.2, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local panel = self:img("top_18")
  if panel then g.draw(panel, 0, 0) end
  local digits = self:img("top_16")
  if digits then
    local iw, ih = digits:getDimensions()
    local v = math.min(999, self.me.total)
    local ds = { math.floor(v / 100), math.floor(v / 10) % 10, v % 10 }
    for i, d in ipairs(ds) do
      g.draw(digits, g.newQuad((d % 5) * 32, math.floor(d / 5) * 64, 32, 64, iw, ih), 80 + 32 * (i - 1), 64)
    end
  end
  local frame = self:img("top")
  if frame then g.draw(frame, 0, 0) end
  local r = math.min(6, self.round + 1)
  self:sprite("b_0_0", 116, 28)
  self:sprite(("b_%d_0"):format(r), 160, 28)
  local Font = require("src.render.Font")
  for t, tm in ipairs(self.teams) do
    local rgb = TEAM_RGB[t]
    local x, y = 24 + (t - 1) * 56, 150
    g.setColor(rgb[1], rgb[2], rgb[3], 1)
    g.rectangle("fill", x, y, 44, 14)
    g.setColor(0, 0, 0, 1)
    Font.draw(("%2d"):format(tm.total), x + 14, y + 2)
    g.setColor(1, 1, 1, 1)
  end
end

function M:draw()
  if SecondScreen.separate(self.game) then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawBottom() end)
  elseif self.showTop then
    self:drawTop()
  else
    self:drawBottom()
  end
end

return M
