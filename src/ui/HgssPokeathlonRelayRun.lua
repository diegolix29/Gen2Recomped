-- HEARTGOLD / SOULSILVER POKeATHLON: RELAY RUN (pokeheartgold
-- asm/overlay_96.s 0x021FC768..0x02201558, event 6, sub-app ov96_0221A8F8 =
-- init 021FC768 / main 021FCD74 / exit 021FCE10; the reading is written up in
-- scratch_claude/athlon/NOTES.md, "## Relay Run"). Art and tables:
-- `gen4_hgss_relay_run` (src/import/Gen4HgssPokeathlonRelayRunArt.lua).
--
-- THE TRACK is one 1024-px lap laid out flat: x 0..1023 along it (wrapping),
-- y 32..168 across it (021FDE7C clamps). The touch screen follows the
-- player's runner, drawn at x 80; the top screen is the round map (each team
-- at angle x / 1024 of a turn, centre (160, 96), radius 80, 0220050C) and the
-- player's laps "LL.T" (T = x / 102.4, 022005B4).
--
-- READ FROM CODE (the logic runs at the Pokeathlon's 30 frames a second --
-- the course's own clock counts 1800 frames to the minute; 2700 = 90 s):
--   * a Pokemon's numbers (021FEFE8, NARC 170 member 2, by its stars):
--     skill = [10 + SKILL] / 10, pace = [15 + SPEED] / 10, power =
--     [POWER] / 10, stamina = [5 + STAMINA], top speed [25 + SPEED] px/frame,
--     sweating top [30 + SPEED], top in a rock patch [35 + SPEED], fainted for
--     [20 + STAMINA] frames
--   * THE FLICK (021FD4D0): touch within 80 px of the runner, drag, let go
--     within 30 frames: velocity += drag x skill x pace / 8 (021FF72C: a y
--     against the running y replaces it), cut to the top speed (021FF6DC:
--     3 in a rock patch, the sweating top at stamina <= 40, else the top).
--     A drag more than 16 px LEFT is a SWITCH instead (and a leftward drag
--     never pushes). Holding the stylus 255 frames brakes everyone by 3 more.
--     A flick that reaches top - 3 counts a DASH (course counter 6)
--   * the SWITCH button (x < 64, y < 32, 021FDE6C) -- yellow, flashing while
--     the runner sweats, grey (dead) while switching / stunned / fainted,
--     red when pressed (021FFE5C); switching: the runner leaves (20 frames),
--     the next comes in (20 frames) (021FEBF0 / 021FED3C), next = (cur+1) % 3
--   * MOVING (021FDE7C): x += vx, y += vy; friction 0.4 px/frame a frame;
--     crossing x 1024 adds a lap (to 60; running backwards over the line
--     takes one back); in a rock patch (kind 3, 64 px box, 021FF574) speed
--     is cut to 3; a big rock (kind 1 / 2: 48 / 32 px box) is a wall: the
--     runner (radius 8, NARC 170 member 12 by the performance row's byte 6)
--     bounces off its sides and corners (021FF2A0 codes 2..9 flip vx / vy)
--   * STAMINA (021FDE7C tail): the runner loses 0.5 a frame moving, gets 0.5
--     back standing; the two resting get 0.5 a frame; <= 40 SWEATING, 0
--     FAINTS (fail counter 1): stands for its faint frames, comes back at 40
--     and stays capped at 40 until switched out
--   * BUMPING (021FF764): a runner moving into another (radii 8 + 8) pushes
--     it by its velocity x power (capped at 11), stops dead, is stunned 18
--     frames, the other 6; a sweating Pokemon bumped (or bumping) faints;
--     both count a HIT (counter 4)
--   * THE RIVALS (02200EF4 / 02200F84): every 10 frames each looks at 16
--     spots ahead (4 rows of 40 px x 4 columns of 40 px, base 2 4 6 6, +3 the
--     two far columns), marks down rows with runners (-4 / -2, +2 one just
--     behind in its own row), columns with runners (-3), rows with rocks (-6)
--     or patches (-1); tired (stamina <= 20) it wants 8 more (-2 far), 5 less
--     if the next one sweats; best spot below the bar -> SWITCH, else flick
--     at it; ties drawn at random
--   * SCORE (021FD46C / ov96_0221A6D0): laps x 1024 + x; Athlete Points =
--     that / 1024 x 10, at most 200; each Pokemon's score = its own distance /
--     1024 (021FDB64, counter 3)
--   * the course record: the player's Pokemon at today's stars (with the
--     Aprijuice), the rivals' at their species' base stars (ov96_021E8484)
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 021FC768 puts them on the main
--     engine at y offset 0 (021E6290 r1), the touch screen here
--     (gSystem.screensFlipped = 1, main surface at 0 -- 021EB5C8); 021FD3EC
--     runs the countdown, play, then the finish
-- Bulbapedia agrees (AP = laps x 10, cap 200). No-Miss = never fainted.
-- Effort counters: dash, hit, fail (6, 4, 1).
--
-- THE RECORD (READ FROM CODE; src/pokemon/HgssPokeathlonRecords.lua): at
-- time up 021FFEE8 hands ov96_021E8318 (laps, at most 60) << 10 + the
-- distance into the lap for NEW RECORD! (021E839C, higher is better); the
-- end state's field_5E0 (021FD46C: laps << 10 + x, the laps not capped) is
-- what the course's end saves.
--
-- STAND-INS, said so: during the FINISH the field stands still (the
-- cartridge runs 021FD4D0 on under it); without `gen4_hgss_athlon_common`
-- the 3-2-1 and the finish are 3 s of numbers and 3 s of the laps; the top
-- screen's six timer sprites and its four big icons
-- (02200180 / 022002F8) are a plain clock and the walking sprites; the
-- runners are HGSS's walking-Pokemon sheets (gen4_follow_mon) or the icons;
-- the wait between leaving and coming in (022006BC for the player) is the
-- rivals' 9 frames (02200900) for everyone; effects (dust, sweat, stars,
-- smoke, the bump's burst) are placed by eye.

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local LAP = 1024
local TIME = 0xA8C                 -- 2700 frames at 30 a second
local Y_MIN, Y_MAX = 32, 168
local START_Y = { 67, 94, 121, 148 } -- (p + 1) x 27 + 40
local VIEW_X = 80                  -- the followed runner's screen x
local FRICTION, BRAKE = 0.4, 3.0
local SWEAT, TIRED = 40, 20
local PUSH_CAP = 11
local LEAVE, WAIT, ENTER = 20, 9, 20
local SE = { bump = 0x8A3, leave = 0x8B4, enter = 0x8B5, ready = 0x8B6, button = 0x89B, dead = 0x89C }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local POWER, STAMINA, SKILL, SPEED = 0, 1, 2, 4
-- the AI's spots: base score by column (ov96_0221C770)
local AI_BASE = { 2, 4, 6, 6 }
-- the switch button's sequence by state (021FDC7C): 0 ready, 1 flashing,
-- 2 pressed, 3 dead, 4 dead pressed
local BUTTON_SEQ = { [0] = 11, 15, 12, 13, 14 }

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function len(x, y) return math.sqrt(x * x + y * y) end
-- x2 - x1 on the round lap, in -512..511
local function wrapDx(dx) return (dx + 512) % LAP - 512 end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_relay_run
  return type(d) == "table" and d.params ~= nil and d.layouts ~= nil and d.track ~= nil
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

-- the performance row's byte 6 (1..3) picks the radius (NARC 170 member 12)
local function radiusOf(self, mon)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local rows = self.game.data.gen4_hgss_performance
  local idx = mon and P.ARC_IDX[tonumber(mon.species) or 0]
  local raw = type(rows) == "table" and idx and (rows[idx + (tonumber(mon.form) or 0)] or rows[idx])
  local class = type(raw) == "table" and tonumber(raw[7]) or 1
  if class < 1 or class > 3 then class = 1 end
  local r = self.d.radii and self.d.radii[class]
  return r and r[2] or 8
end

local function newMon(self, mon, st)
  local p = self.d.params
  return {
    mon = mon,
    power = p[0 + st[POWER]] / 10,
    stamMax = p[5 + st[STAMINA]], stamina = p[5 + st[STAMINA]],
    skill = p[10 + st[SKILL]] / 10,
    pace = p[15 + st[SPEED]] / 10,
    faintFrames = p[20 + st[STAMINA]],
    top = p[25 + st[SPEED]], sweatTop = p[30 + st[SPEED]], patchTop = p[35 + st[SPEED]],
    state = 0, dist = 0, radius = radiusOf(self, mon),
    dash = 0, hit = 0, fail = 0, fainted = false,
  }
end

-- opts: team (three Pokemon), rivals ({3}, {3}, {3}), onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, frame = 0, images = {} }, M)
  local d = game.data.gen4_hgss_relay_run
  self.d = d
  self.timer = TIME
  local layout = d.layouts[rand(10)] or d.layouts[0] or {}
  self.obstacles = {}
  for _, o in ipairs(layout) do
    local w = o.kind == 1 and 48 or (o.kind == 2 and 32 or 64)
    self.obstacles[#self.obstacles + 1] = { kind = o.kind, x = o.x, y = o.y, w = w }
  end
  self.teams = {}
  for t = 1, 4 do
    local mons = {}
    for k = 1, 3 do
      local mon = t == 1 and opts.team[k] or (opts.rivals and opts.rivals[t - 1] and opts.rivals[t - 1][k])
      mons[k] = newMon(self, mon, starsOf(game, mon, t > 1))
    end
    self.teams[t] = { id = t, cpu = t > 1, mons = mons, cur = 1, x = 0, y = START_Y[t], vx = 0, vy = 0,
      laps = 0, maxLaps = 0, back = false, stun = 0, patch = false, class = 0, capped = false,
      faint = 0, switching = nil, contact = {}, button = 0 }
  end
  self.me = self.teams[1]
  self.touch = { down = false, new = false, x = 0, y = 0 }
  self.drag = { active = false, frames = 0, sx = 0, sy = 0, ex = 0, ey = 0 }
  self.brake = false
  self.ai = { tick = 10, run = nil }
  self.countdown = 90
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (021FC768)
  if CD.available(game) then self.cd = CD.new(game, 0) end
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

local function curMon(p) return p.mons[p.cur] end

-- ------------------------------------------------------------------ rules --

-- 021FF6DC: how fast a flick may make the runner go
local function flickTop(p)
  local m = curMon(p)
  if p.patch then return m.patchTop end
  if m.stamina <= SWEAT then return m.sweatTop end
  return m.top
end

function M:startSwitch(p)
  if p.switching then return end
  p.switching = 0
  curMon(p).switches = (curMon(p).switches or 0) + 1   -- kind 7 (021FD4D0)
  se(self, SE.leave)
end

-- 021FD4D0's flick: d = the drag (end - start)
function M:flick(p, dx, dy)
  if dx < 0 then
    if dx < -16 then self:startSwitch(p) end
    return
  end
  local m = curMon(p)
  local k = m.skill * m.pace / 8
  dx, dy = dx * k, dy * k
  -- 021FF72C: x adds; y adds when it runs the same way, else replaces
  local nx = p.vx + dx
  local ny = (p.vy * dy >= 0) and (p.vy + dy) or dy
  local cap = flickTop(p)
  local s = len(nx, ny)
  if s > cap then nx, ny = nx / s * cap, ny / s * cap end
  p.vx, p.vy = nx, ny
  if len(nx, ny) >= m.top - 3 then m.dash = m.dash + 1 end
end

function M:faint(p, m)
  m.stamina, m.state = 0, 2
  p.faint = m.faintFrames
  m.fail = m.fail + 1
  m.fainted = true
end

-- the switch's timing (021FEBF0 out, 02200900 wait, 021FED3C in)
function M:stepSwitch(p)
  p.switching = p.switching + 1
  if p.switching == LEAVE + WAIT then
    p.cur = p.cur % 3 + 1
    se(self, SE.enter)
  elseif p.switching >= LEAVE + WAIT + ENTER then
    p.switching, p.capped = nil, false
    se(self, SE.ready)
  end
end

-- the player's touch, once a frame (021FD4D0 for participant 0)
function M:stepInput(p)
  local tc, dr = self.touch, self.drag
  local new, held = tc.new, tc.down
  tc.new = false
  local inButton = tc.x < 64 and tc.y < 32
  -- the button (021FFE5C)
  local state = 0
  if p.switching or p.stun > 0 or curMon(p).state == 2 then state = 3
  elseif curMon(p).state == 1 then state = 1 end
  if inButton and held then
    if new then
      p.button = state <= 1 and 2 or 4
      se(self, p.button == 2 and SE.button or SE.dead)
    end
  else
    p.button = state
  end
  if p.switching or curMon(p).state == 2 or p.stun > 0 then
    dr.active, dr.frames = false, 0
    return
  end
  local reset = false
  if new then
    if inButton then
      self:startSwitch(p)
    elseif len(tc.x - VIEW_X, tc.y - p.y) < 80 then
      dr.active, dr.sx, dr.sy, dr.ex, dr.ey = true, tc.x, tc.y, tc.x, tc.y
    end
  elseif held then
    if dr.frames < 0xFF then dr.frames = dr.frames + 1 else self.brake = true end
    if dr.active then dr.ex, dr.ey = tc.x, tc.y end
  else
    if dr.active then
      if dr.frames <= 30 then p.pending = { dr.ex - dr.sx, dr.ey - dr.sy } end
      dr.active = false
      self.brake = false
    end
    reset = true
  end
  if p.pending then
    local f = p.pending
    p.pending = nil
    self:flick(p, f[1], f[2])
  end
  if reset then dr.frames = 0 end
end

-- the obstacles near a point: is it in a patch; the rocks to bounce off
function M:obstacleHit(p)
  local r = curMon(p).radius
  p.patch = false
  for _, o in ipairs(self.obstacles) do
    local cx0 = o.x + wrapDx(p.x - o.x)      -- the runner beside this obstacle
    local cx = cx0
    if o.kind == 3 then
      -- 021FF574: the runner's point inside the 64-px box
      if cx >= o.x - 32 and cx < o.x + 32 and p.y >= o.y - 32 and p.y < o.y + 32 then p.patch = true end
    else
      local h = o.w / 2
      local x0, x1, y0, y1 = o.x - h, o.x + h, o.y - h, o.y + h
      local qx, qy = math.max(x0, math.min(cx, x1)), math.max(y0, math.min(p.y, y1))
      local ex, ey = cx - qx, p.y - qy
      local dist = len(ex, ey)
      if dist < r then
        if ex == 0 and ey == 0 then
          -- inside: out by the nearest side, no bounce (codes 0xA..0xD)
          local l, rr, t, b = cx - x0, x1 - cx, p.y - y0, y1 - p.y
          local mn = math.min(l, rr, t, b)
          if mn == l then cx = x0 - r elseif mn == rr then cx = x1 + r elseif mn == t then p.y = y0 - r else p.y = y1 + r end
        else
          -- a side flips the speed into it, a corner both (codes 2..9)
          if ex ~= 0 and ((ex < 0 and p.vx > 0) or (ex > 0 and p.vx < 0)) then p.vx = -p.vx end
          if ey ~= 0 and ((ey < 0 and p.vy > 0) or (ey > 0 and p.vy < 0)) then p.vy = -p.vy end
          cx, p.y = qx + ex / dist * r, qy + ey / dist * r
        end
        p.x = p.x + (cx - cx0)
      end
    end
  end
end

-- 021FF764: runners bumping
function M:bumps()
  for _, a in ipairs(self.teams) do
    if not a.switching and a.stun == 0 then
      for _, b in ipairs(self.teams) do
        if b ~= a and not b.switching then
          local dx, dy = wrapDx(b.x - a.x), b.y - a.y
          local reach = curMon(a).radius + curMon(b).radius
          if len(dx, dy) < reach then
            if not a.contact[b.id] and dx * a.vx + dy * a.vy > 0 then
              local pw = curMon(a).power
              if len(a.vx, a.vy) ~= 0 then
                b.vx, b.vy = b.vx + a.vx * pw, b.vy + a.vy * pw
                local s = len(b.vx, b.vy)
                if s > PUSH_CAP then b.vx, b.vy = b.vx / s * PUSH_CAP, b.vy / s * PUSH_CAP end
              end
              if curMon(b).state == 1 then self:faint(b, curMon(b)) end
              a.vx, a.vy = 0, 0
              if curMon(a).state == 1 then self:faint(a, curMon(a)) end
              a.contact[b.id], b.contact[a.id] = true, true
              if not self.bump then
                self.bump = { x = a.x + dx / 2, y = a.y + dy / 2, t = 12 }
                se(self, SE.bump)
              end
              b.stun, a.stun = 6, 18
              curMon(a).hit = curMon(a).hit + 1
              curMon(b).hit = curMon(b).hit + 1
            end
          else
            a.contact[b.id], b.contact[a.id] = false, false
          end
        end
      end
    end
  end
end

-- 021FDE7C, one participant
function M:stepRunner(p)
  if p.stun > 0 then p.stun = p.stun - 1; return end
  p.x, p.y = p.x + p.vx, p.y + p.vy
  local m = curMon(p)
  m.dist = m.dist + p.vx
  p.y = math.max(Y_MIN, math.min(Y_MAX, p.y))
  self:obstacleHit(p)
  self:bumps()
  -- the lap line
  if p.x >= LAP then
    p.x = p.x - LAP
    if not p.back and p.laps < 60 then p.laps = p.laps + 1 end
    p.maxLaps = math.max(p.maxLaps, p.laps)
    p.back = false
  elseif p.x < 0 then
    p.x = p.x + LAP
    if p.laps > 0 then p.laps = p.laps - 1 else p.back = true end
  end
  -- a rock patch holds it to 3, then friction
  local s = len(p.vx, p.vy)
  if not p.switching and p.patch and s > m.patchTop then
    p.vx, p.vy, s = p.vx / s * m.patchTop, p.vy / s * m.patchTop, m.patchTop
  end
  if s > 0 then
    local dec = FRICTION + (self.brake and BRAKE or 0)
    if s >= dec then p.vx, p.vy = p.vx - p.vx / s * dec, p.vy - p.vy / s * dec
    else p.vx, p.vy = 0, 0 end
  end
  s = len(p.vx, p.vy)
  if s >= m.top - 1 then p.class = 3 elseif s >= m.top - 3 then p.class = 2
  elseif s == 0 then p.class = 0 else p.class = 1 end
  if p.switching then return end
  -- stamina
  for k, mm in ipairs(p.mons) do
    local st = mm.stamina
    if k == p.cur then
      if mm.state ~= 2 then
        st = st + (p.class == 0 and 0.5 or -0.5)
        if p.capped then st = math.min(st, SWEAT) else st = math.min(st, mm.stamMax) end
      else
        p.faint = p.faint - 1
        if p.faint <= 0 then mm.state, st = 1, SWEAT end
      end
    else
      st = math.min(st + 0.5, mm.stamMax)
    end
    if st <= 0 then
      if mm.state ~= 2 then
        p.capped = true
        self:faint(p, mm)
      end
      mm.stamina = 0
    else
      mm.stamina = st
      mm.state = st <= SWEAT and 1 or 0
    end
  end
end

-- 02200F84: one rival's look ahead
function M:think(p)
  if p.switching or curMon(p).state == 2 or p.stun > 0 then return end
  local function row(y) return math.max(0, math.min(3, math.floor((y - 32) / 40))) end
  local myRow = row(p.y)
  local cells = {}
  for k = 0, 15 do
    local c, r = k % 4, math.floor(k / 4)
    cells[k + 1] = { dx = 40 * c + rand(40), y = 40 * r + 32 + rand(40), score = AI_BASE[c + 1], r = r, c = c }
  end
  local pen = { [0] = 0, 0, 0, 0 }
  for r = 0, 3 do
    for _, q in ipairs(self.teams) do
      if q ~= p then
        local d = wrapDx(q.x - p.x)
        if d >= 0 and d < 160 then
          if row(q.y) == r then pen[r] = pen[r] - (myRow == r and 4 or 2) end
          local col = math.floor(d / 40)
          cells[r * 4 + col + 1].score = cells[r * 4 + col + 1].score - 3
        elseif d < 0 and d >= -80 and row(q.y) == r and myRow == r then
          pen[r] = pen[r] + 2
        end
      end
    end
    local top, bottom = 32 + 40 * r, 72 + 40 * r
    for _, o in ipairs(self.obstacles) do
      local bx = wrapDx(o.x - o.w / 2 - p.x)
      local by = o.y - o.w / 2
      if bx > 0 and bx <= 160 and top < by + o.w and by < bottom then
        pen[r] = pen[r] - (o.kind == 3 and 1 or 6)
      end
    end
  end
  local bar = 0
  for _, c in ipairs(cells) do
    c.score = c.score + pen[c.r]
    if self.timer < TIME and c.c >= 2 then c.score = c.score + 3 end
  end
  if curMon(p).stamina <= TIRED then
    for _, c in ipairs(cells) do if c.c >= 2 then c.score = c.score - 2 end end
    bar = bar + 8
  end
  if p.mons[p.cur % 3 + 1].state == 1 then bar = bar - 5 end
  local best, ties = -1e9, {}
  for _, c in ipairs(cells) do
    if c.score > best then best, ties = c.score, { c } elseif c.score == best then ties[#ties + 1] = c end
  end
  local pick = ties[rand(#ties) + 1]
  if pick.score >= bar then
    p.pending = { pick.dx, pick.y - p.y }
  else
    self:startSwitch(p)
  end
end

-- 02200EF4: a tick every 10 frames, then one rival a frame
function M:stepAi()
  local ai = self.ai
  ai.tick = ai.tick - 1
  if ai.tick <= 0 then ai.tick, ai.run = 10, 2 end
  if ai.run then
    self:think(self.teams[ai.run])
    ai.run = ai.run + 1
    if ai.run > 4 then ai.run = nil end
  end
end

function M:step()
  self.frame = self.frame + 1
  if self.timer > 0 then self.timer = self.timer - 1 end
  for _, p in ipairs(self.teams) do
    if p.switching then
      self:stepSwitch(p)
      p.pending = nil
    elseif p.cpu then
      if p.pending and curMon(p).state ~= 2 and p.stun == 0 then
        local f = p.pending
        self:flick(p, f[1], f[2])
      end
      p.pending = nil
    else
      self:stepInput(p)
    end
  end
  self:stepAi()
  for _, p in ipairs(self.teams) do self:stepRunner(p) end
  if self.bump then
    self.bump.t = self.bump.t - 1
    if self.bump.t <= 0 then self.bump = nil end
  end
  if self.timer <= 0 and not self.over then
    self.over = 90
    if self.cd then
      local v = math.min(60, self.me.laps) * LAP + math.floor(self.me.x)
      self.cd:startFinish(Rec.isNew(self.game, 6, v % 65536))
    end
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

-- PAD / KEYS (not the cartridge's): A or RIGHT flicks right (UP / DOWN held
-- steer it), LEFT or B switches, SELECT / L shows the top screen on one
function M:padInput()
  local input = self.game.input
  if not input then return end
  local p = self.me
  if input:wasPressed("select") or input:wasPressed("l") then self.showTop = not self.showTop end
  if self.countdown > 0 or self.over or p.switching or curMon(p).state == 2 or p.stun > 0 then return end
  if input:wasPressed("left") or input:wasPressed("b") then
    self:startSwitch(p)
  elseif input:wasPressed("right") or input:wasPressed("a") then
    local dy = 0
    if input:isDown("up") then dy = -40 elseif input:isDown("down") then dy = 40 end
    p.pending = { 56, dy }
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
    -- the FINISH (021E667C, 021FD3EC state 2)
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

-- the cartridge's field (021FD46C) and Athlete Points (ov96_0221A6D0)
local function points(p)
  local v = p.laps * LAP + math.floor(p.x)
  return math.min(200, math.floor(v / LAP * 10))
end

function M:finish()
  if self.done then return end
  self.done = true
  local pts, stats = {}, {}
  for t, p in ipairs(self.teams) do
    pts[t] = points(p)
    stats[t] = {}
    for k, m in ipairs(p.mons) do
      stats[t][k] = { miss = m.fainted, score = math.max(0, math.floor(m.dist / LAP)),
        dash = m.dash, hit = m.hit, fail = m.fail, switch = m.switches or 0 }
    end
  end
  self.game.stack:pop()
  if self.onDone then
    self.onDone({ points = pts, laps = self.me.laps + math.floor(self.me.x) / LAP, stats = stats,
      record = (self.me.laps * LAP + math.floor(self.me.x)) % 65536 })
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

function M:sprite(key, x, y)
  local img, rec = self:img(key)
  if not img then return false end
  local ox = type(rec) == "table" and tonumber(rec.originX) or 0
  local oy = type(rec) == "table" and tonumber(rec.originY) or 0
  love.graphics.draw(img, math.floor(x + ox), math.floor(y + oy))
  return true
end

-- the sequence's frame at time t (frame durations from the art's objSeq)
function M:anim(set, seq, t)
  local list = self.d.objSeq and self.d.objSeq[set] and (self.d.objSeq[set][seq] or self.d.objSeq[set][tostring(seq)])
  if type(list) ~= "table" or #list == 0 then return ("%s_%d_0"):format(set, seq) end
  local total = 0
  for _, v in ipairs(list) do total = total + v end
  local at = t % math.max(1, total)
  for f, v in ipairs(list) do
    if at < v then return ("%s_%d_%d"):format(set, seq, f - 1) end
    at = at - v
  end
  return ("%s_%d_0"):format(set, seq)
end

local function cachedImage(self, path)
  self.mons = self.mons or {}
  if self.mons[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.mons[path] = ok and img or false
    if self.mons[path] then self.mons[path]:setFilter("nearest", "nearest") end
  end
  return self.mons[path] or nil
end

-- the walking Pokemon facing right (gen4_follow_mon), or its icon
function M:runner(mon, x, y, step)
  if not mon then return end
  local data = self.game.data
  local fm = data.gen4_follow_mon
  if type(fm) == "table" and fm.sheets then
    local Data = require("src.import.Gen4HgssFollowMon")
    local idx = Data.index(fm, tonumber(mon.species), tonumber(mon.form) or 0, false)
    local sheet = fm.sheets[idx] or fm.sheets[tostring(idx)]
    local path = sheet and ((mon.shiny or mon.isShiny) and sheet.shiny or sheet.normal)
    local img = type(path) == "string" and cachedImage(self, path)
    if img then
      local fw, fh = tonumber(sheet.frameWidth) or 32, tonumber(sheet.frameHeight) or 32
      local iw, ih = img:getDimensions()
      local f = 6 + (step % 2)
      if (f + 1) * fh > ih then f = 0 end
      love.graphics.draw(img, love.graphics.newQuad(0, f * fh, fw, fh, iw, ih), math.floor(x - fw / 2), math.floor(y - fh + 8))
      return
    end
  end
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (data.icons and data.icons.bySpecies and data.icons.bySpecies[mon.species]) or (def and def.icon)
  local path, fh = entry, nil
  if type(entry) == "table" then path, fh = entry.image, tonumber(entry.frameHeight) end
  local img = type(path) == "string" and cachedImage(self, path)
  if not img then return end
  local iw, ih = img:getDimensions()
  fh = fh or math.min(iw, ih)
  local frames = math.max(1, math.floor(ih / fh))
  love.graphics.draw(img, love.graphics.newQuad(0, (step % frames) * fh, iw, fh, iw, ih), math.floor(x - iw / 2), math.floor(y - fh + 8))
end

-- a BG strip scrolled by `hofs`, repeated across the screen
function M:strip(key, hofs)
  local img = self:img(key)
  if not img then return end
  local w = img:getWidth()
  local x0 = -(math.floor(hofs) % w)
  for k = 0, 2 do
    if x0 + k * w < W then love.graphics.draw(img, x0 + k * w, 0) end
  end
end

-- the touch screen: the track around the player's runner
function M:drawBottom()
  local g = love.graphics
  g.setColor(0.8, 0.45, 0.3, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local cam = self.me.x
  self:strip("track", cam)
  -- 021FFBD8: the start line is filled over while 272 < x < 768
  if cam > 272 and cam < 768 then
    local img = self:img("track")
    if img then
      local iw, ih = img:getDimensions()
      local q = g.newQuad(112, 24, 16, 168, iw, ih)
      local sx = 80 - (math.floor(cam) % 512)
      for k = 0, 1 do g.draw(img, q, sx + 512 * k, 24) end
    end
  end
  self:strip("banner_lo", cam / 2)
  self:strip("banner_hi", cam * 2)
  for _, o in ipairs(self.obstacles) do
    local sx = wrapDx(o.x - cam) + VIEW_X
    if sx >= -32 and sx <= 288 then self:sprite(("obj_%d_0"):format(o.kind - 1), sx, o.y) end
  end
  -- the runners, back to front by y
  local order = {}
  for _, p in ipairs(self.teams) do order[#order + 1] = p end
  table.sort(order, function(a, b) return a.y < b.y end)
  for _, p in ipairs(order) do
    local sx = wrapDx(p.x - cam) + VIEW_X
    if sx > -48 and sx < W + 48 then
      local m = curMon(p)
      self:sprite("top_" .. (3 + p.id) .. "_0", sx, p.y - 4)
      if p.class >= 2 then self:sprite(self:anim("obj", p.class == 3 and 4 or 5, self.t), sx - 8, p.y) end
      local hidden = p.switching and p.switching < LEAVE + WAIT and p.switching >= LEAVE
      local yoff = 0
      if p.switching then
        if p.switching < LEAVE then yoff = -p.switching * 20
        elseif p.switching >= LEAVE + WAIT then yoff = -(LEAVE + WAIT + ENTER - p.switching) * 20 end
        if p.switching < 8 or (p.switching >= LEAVE + WAIT and p.switching < LEAVE + WAIT + 8) then
          self:sprite(self:anim("obj", 8, p.switching), sx, p.y - 8)
        end
      end
      if not hidden then
        local stepf = p.class == 0 and 0 or math.floor(self.t / (p.class == 3 and 3 or 6))
        self:runner(m.mon, sx, p.y + yoff, stepf)
      end
      if m.state == 2 or p.stun > 0 then self:sprite(self:anim("obj", 7, self.t), sx, p.y - 24)
      elseif m.state == 1 then self:sprite(self:anim("obj", 6, self.t), sx + 8, p.y - 20) end
    end
  end
  if self.bump then
    self:sprite(self:anim("obj", 9, 12 - self.bump.t), wrapDx(self.bump.x - cam) + VIEW_X, self.bump.y)
  end
  self:sprite(("obj_%d_0"):format(BUTTON_SEQ[self.me.button] or 11), 32, 16)
  local Font = require("src.render.Font")
  if (self.over or self.timer <= 0) and not self.cd then
    self:sprite("obj_10_0", 104, 96)
    Font.draw(("%d.%d"):format(self.me.laps, math.floor(self.me.x / 102.4)), 140, 90)
  end
  if self.cd then
    -- the shared 3-2-1 / FINISH (main engine = this screen, surface at 0)
    self.cd:draw(0)
  elseif self.countdown > 0 then
    g.setColor(0, 0, 0, 0.4)
    g.rectangle("fill", 112, 80, 32, 24)
    g.setColor(1, 1, 1, 1)
    Font.draw(tostring(math.ceil(self.countdown / 30)), 124, 88)
  end
end

-- the top screen: the round map, the laps, the clock
function M:drawTop()
  local g = love.graphics
  g.setColor(0.1, 0.4, 0.2, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local map = self:img("map")
  if map then g.draw(map, 0, 0) end
  local laps = self:img("laps")
  if laps then g.draw(laps, 0, 0) end
  local digits = self:img("digits")
  if digits then
    local iw, ih = digits:getDimensions()
    -- CopyRectToBgTilemapRect replaces the counter's tiles: the map shows
    -- through where the digit has none
    local function digit(d, x, y)
      if map then g.draw(map, g.newQuad(x, y, 32, 64, map:getDimensions()), x, y) end
      g.draw(digits, g.newQuad((d % 5) * 32, math.floor(d / 5) * 64, 32, 64, iw, ih), x, y)
    end
    local l = math.min(99, self.me.laps)
    digit(math.floor(l / 10), 112, 64)
    digit(l % 10, 144, 64)
    digit(math.min(9, math.floor(self.me.x / 102.4)), 192, 64)
  end
  for _, p in ipairs(self.teams) do
    local a = p.x / LAP * 2 * math.pi
    local x, y = 160 + 80 * math.sin(a), 96 + 80 * math.cos(a)
    self:sprite("top_" .. (3 + p.id) .. "_0", x, y - 4)
    self:runner(curMon(p).mon, x, y, 0)
  end
  local Font = require("src.render.Font")
  g.setColor(0, 0, 0, 0.5)
  g.rectangle("fill", 0, 0, 48, 16)
  g.setColor(1, 1, 1, 1)
  local secs = math.ceil(self.timer / 30)
  Font.draw(("%d:%02d"):format(math.floor(secs / 60), secs % 60), 6, 1)
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
