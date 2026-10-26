-- HEARTGOLD / SOULSILVER POKeATHLON: LAMP JUMP (pokeheartgold
-- asm/overlay_96.s 0x021F5018..0x021F7934, event 5, sub-app ov96_0221A920 =
-- init 021F5018 / main 021F54C0 / results 021F54D4 / exit 021F553C, states
-- ov96_0221DC1C = { 021F5650 fade + 3-2-1 + play + finish, 021F5730 end };
-- the reading is written up in scratch_claude/athlon/NOTES.md, "## Lamp
-- Jump"). Art and tables: `gen4_hgss_lamp_jump`
-- (src/import/Gen4HgssPokeathlonLampJumpArt.lua).
--
-- THE FIELD is both screens as one 384-px-tall space (y 0..191 the top
-- screen, 192..383 the touch screen). The player's three Pokemon stand on an
-- elastic band stretched across the touch screen (the 3D strip of
-- 021F61C8, 128 samples 2 px apart, at rest at y 288 = touch-screen y 96);
-- 29 lamps hang above it (ov96_0221C21C), most of them on the top screen.
-- Only the player's team is on the field: the rival teams are not played.
--
-- READ FROM CODE (the logic runs at the Pokeathlon's 30 frames a second):
--   * the clock (heap+0x13C) is 1800 frames = 60 s, shown as frames / 30;
--     the last three seconds show a big 3 / 2 / 1 with SE 0x897 (021E6454)
--   * a Pokemon's numbers (021F715C, NARC 170 MEMBER 6 -- not 5 -- by its
--     course record): kick = [JUMP] (0 9 10 11 13) / 12, stun = [5 +
--     STAMINA] frames (50 30 20 15 10), drift = [10 + SKILL] (4 6 8 9 12) /
--     12; its body = NARC 170 member 16 by the performance row's byte 6
--     ({ y offset, radius } 8/8, 10/10, 12/14)
--   * HEIGHT (heap+0xFAC + 0x1C m, [8]) is in 1/64 px: the Pokemon's feet are
--     at y 288 - height / 64 (021F5D3C); its sample on the band is x / 2
--   * THE STYLUS (021F5BA0 / 021F5F68): a new touch takes the nearest of the
--     three that is not stunned whose world point is within 80 px; the
--     catapult goes off when the stylus is lifted, or by itself on the 8th
--     frame it is held (7 frames of hold, then the drag so far)
--   * THE CATAPULT (021F6088): only a drag DOWN, by a Pokemon not already in
--     motion: speed = (drag y / 64 fx) / 2.5 (drag y at most 112 px ->
--     2867), sideways = -(drag x) / 4 (at most 10 px a frame either way)
--     x drift / 12; SE 0x8C2. It first goes DOWN into the band at that speed.
--   * IN THE BAND (021F6798, not flying): height += speed (not below -6144);
--     falling: speed += 819.2 to 0; then rising: += 341.33, at most the speed
--     it came in with. Back at the band's level: (the first time after a pull)
--     x kick / 12; at most 2200; x 0.9; 0 = no jump (SE 0x5F3 after a pull);
--     more than 1408, or the first time after a pull = a JUMP (SE 0x656,
--     course counter 2), else it settles. So a big jump bounces again by
--     itself when it lands (a separate jump) -- and a ONE-star Jump Pokemon
--     (kick 0) cannot jump at all.
--   * IN THE AIR: height += speed, speed -= 128 a frame, falling no faster
--     than it went up; x += drift while above the rest line (021F6B28, x kept
--     in 32..223). Into the band again: drift 2 px nearer 0 (021F7130), speed
--     at least -128 down
--   * THE BAND (021F6BE4 / 021F6B50 / 021F6524 / 021F6424 / 021F64A0): a
--     Pokemon in the band pulls a V from both edges down to its height at its
--     sample, and a straight line joins each pair (0-1, 1-2, 2-0) between
--     them; the band is the lowest of the six. A Pokemon in motion meets the
--     band the OTHER two make; one at rest rides the whole band (021F6BB0)
--   * LAMPS (021F7598 / 021F7620): every 241 frames (the first at once) up to
--     25 of the unlit lamps light, picked at random -- so all 29 can be lit.
--     A lamp within body radius + 8 px of a Pokemon's body goes out
--     (021F6600): points = 1 + the lamps already touched in that jump, at most
--     5 (021F65D8: the count is cleared whenever the Pokemon is not flying);
--     SE 0x88D pitched up the scale (ov96_0221C110), course counter 3 (+1 a
--     lamp); a Pokemon's points cap at 999, the team's too (021F6E38)
--   * COLLISIONS (021F7194): two of the three whose bodies touch are both
--     STUNNED for their stun frames (can't be picked up -- that is all a stun
--     does), a spark at the contact, SE 0x8A3, course counters 4 (hit) and 1
--     (fail = the miss) for both. Both in the air: they swap upward speeds and
--     drifts once (a latch until they part), a falling one stops; otherwise
--     they are pushed 16 px apart (and stunned again each frame they touch)
--   * THE RIVALS (021F7684 / 021F7740 / 021F77EC): every 3 frames each rival
--     team rolls 2 x (its Jump stars) + (its Skill stars) + rand(0..100);
--     100 or more = a lamp: its marker flashes on the top screen and one of
--     its Pokemon (weighted by Jump) gets course counter 3. Their SCORE is not
--     from that: at the end each Pokemon (with Jump > 1 star) scores 80 + 6 x
--     Jump + 2 x Stamina + 2 x Skill + rand(0..20) (021F5730, stars 0..4),
--     and gets counters hit and fail + rand(0..20)
--   * Athlete Points (ov96_0221A6B0): the team's points / 3.5, at most 200.
--     Bulbapedia agrees. No-Miss = never stunned. Effort: jump, hit.
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 021F5018 puts them on the main
--     engine at y offset 0xC0 (021E6290 r1), the touch screen here
--     (gSystem.screensFlipped = 1), whose sprite surface starts at 0xC0
--     (021EB5C8); 021F5650 runs the countdown after the fade, then play, then
--     the finish with the field stopped
--
-- Bulbapedia says the lamps relight 25 at a time every 8 s; the code lights
-- up to 25 of the dark ones every 241 frames, so the field can be full.
--
-- THE RECORD (READ FROM CODE; src/pokemon/HgssPokeathlonRecords.lua): at
-- time up 021F5A88 hands ov96_021E8318 the team's score (the three's +0xB0
-- points, at most 999) for NEW RECORD! (021E839C, higher is better); the
-- end state's field_5E0 (021F5730, the same sum) is what the course's end
-- saves.
--
-- STAND-INS, said so: without `gen4_hgss_athlon_common` the 3-2-1 and
-- the finish are 3 s of numbers and 2 s of FINISH text; the clock's digits
-- are text by the clock sprite (the shared course
-- set's digits, ov96_021EA634, not imported); the band's camera scale is the
-- orthographic camera's (0xA4 half angle at distance 100 = 62.4 px a unit,
-- 021F6398) while the sprites use 64; the walkers' world / body offsets reuse
-- Circle Push's reading (obj [0x10] = 2 + size class, [0x28] = 0); the
-- stunned walker's spin (walker mode 0x14, 021EAD08) cycles its four facings;
-- the band's colours come from 021F61C8 but it is drawn flat (no lighting);
-- the walkers are gen4_follow_mon sheets (or icons); link play is not here.

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local TIME = 1800                      -- heap+0x13C
local REST_Y = 288                     -- 0x120000: feet y at height 0
local GRAB_R = 80                      -- ov96_021E6104
local HOLD = 7                         -- frames of hold before it goes off
local RELIGHT = 240                    -- lamp manager +0x32C
local SAMPLES = 128
local BAND_S = 96 * 4096 / 6300        -- ortho camera: px per world unit
local SE = { launch = 0x8C2, jump = 0x656, flop = 0x5F3, lamp = 0x88D, bump = 0x8A3, dizzy = 0x890, tick = 0x897 }
local LAMP_PITCH = { 0, 128, 256, 320, 448 }   -- ov96_0221C110 (1/64 semitone)
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local STAMINA, SKILL, JUMP = 1, 2, 3
local TEAM_RGB = { { 0.94, 0.25, 0.25 }, { 0.25, 0.45, 0.95 }, { 0.2, 0.75, 0.3 }, { 0.95, 0.85, 0.2 } }
-- ov96_0221C0DC / C0D0: the team markers on the top screen
local MARK_ME = { 22, 72 }
local MARK_RIVAL = { 166, 40 }

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
-- C's int division / double-to-int (toward zero)
local function tdiv(a, b) local q = a / b; return q < 0 and math.ceil(q) or math.floor(q) end
local function fix(v) return v < 0 and math.ceil(v) or math.floor(v) end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local X_MIN, X_MAX = 0x20000, 0xDF000  -- 32..223 px (fx)

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_lamp_jump
  return type(d) == "table" and d.params ~= nil and d.lamps ~= nil and (d.back ~= nil or d.top ~= nil)
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

local function star(st, k)
  local v = tonumber(st and st[k]) or 2
  return math.max(0, math.min(4, v))
end

-- the performance row's bytes (1-based raw): [6] = byte 5 (tall), [7] = byte 6 (size class)
local function rowOf(self, mon)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local rows = self.game.data.gen4_hgss_performance
  local idx = mon and P.ARC_IDX and P.ARC_IDX[tonumber(mon.species) or 0]
  local raw = type(rows) == "table" and idx and (rows[idx + (tonumber(mon.form) or 0)] or rows[idx])
  return type(raw) == "table" and raw or nil
end

function M:sheetOf(mon)
  local fm = self.game.data.gen4_follow_mon
  if not (mon and type(fm) == "table" and fm.sheets) then return nil end
  local ok, Data = pcall(require, "src.import.Gen4HgssFollowMon")
  if not ok then return nil end
  local idx = Data.index(fm, tonumber(mon.species), tonumber(mon.form) or 0, false)
  return fm.sheets[idx] or fm.sheets[tostring(idx)]
end

local function newMon(self, mon, st, k)
  local p = self.d.params
  local raw = rowOf(self, mon)
  local class = raw and tonumber(raw[7]) or 1
  if class < 1 or class > 3 then class = 1 end
  local size = self.d.sizes and self.d.sizes[class]
  local sheet = self:sheetOf(mon)
  local half = (sheet and tonumber(sheet.frameHeight) or 32) >= 64 and 32 or 16
  local x = 0x40 * k * 4096
  return {
    mon = mon, slot = k,
    kick = p[0 + star(st, JUMP)], stunFrames = p[5 + star(st, STAMINA)], drift = p[10 + star(st, SKILL)],
    yoff = size and size[1] or 8, radius = size and size[2] or 8, class = class,
    tall = raw and (tonumber(raw[6]) or 0) ~= 0 or false,
    wdy = (2 + class) - half,
    xt = x, vx = 0,                       -- mon +0x1C / +0x18 (fx)
    -- heap+0xFAC + 0x1C m: [0] speed, [8] height, [0x10] flying, [0x14] in motion, [0x18] entry speed
    vel = 0, pos = 0, fly = false, active = false, j18 = 0,
    fresh = true,                          -- +0x28: the next pass is a pull's
    score = 0, combo = 0,                  -- +0x20 / +0x24
    stun = false, stunT = 0,               -- +0x26 / +0x27
    latch = {},                            -- +0x29 + j
    lamps = 0, jumps = 0, hits = 0, fails = 0,
    step = 0,
  }
end

-- opts: team (three Pokemon), rivals ({3}, {3}, {3}), names, onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, frame = 0, images = {} }, M)
  local d = game.data.gen4_hgss_lamp_jump
  self.d = d
  self.mons = {}
  for k = 1, 3 do self.mons[k] = newMon(self, opts.team[k], starsOf(game, opts.team[k], false), k) end
  -- the band: own V per Pokemon, a line per pair, the whole (heap+0x1A0..)
  self.own, self.pair, self.surf = {}, {}, {}
  for k = 1, 3 do
    self.own[k], self.pair[k] = {}, {}
    for i = 0, SAMPLES - 1 do self.own[k][i], self.pair[k][i] = 0, 0 end
  end
  for i = 0, SAMPLES - 1 do self.surf[i] = 0 end
  -- the lamps (021F74A4 manager: 29 x { lit, pos, lamp / points / burst objs })
  self.lamps = {}
  for i, l in ipairs(d.lamps) do self.lamps[i] = { lit = false, x = l[1], y = l[2], popT = nil, pts = 0, burstT = nil } end
  self.relight = 0
  -- the rival teams (021F7684): they are not on the field
  self.teams = {}
  for t = 1, 4 do
    local tm = { id = t, cpu = t > 1, name = (opts.names and opts.names[t]) or (t == 1 and (((game.save or {}).player or {}).name or "PLAYER")) or ("TEAM " .. t),
      flag = false, markT = nil, points = 0 }
    if t > 1 then
      local list = opts.rivals and opts.rivals[t - 1] or {}
      tm.mons, tm.stars, tm.cum, tm.jumpSum, tm.skillSum, tm.stats = {}, {}, {}, 0, 0, {}
      for k = 1, 3 do
        local st = starsOf(game, list[k], true)
        tm.mons[k], tm.stars[k] = list[k], st
        tm.jumpSum = tm.jumpSum + star(st, JUMP)
        tm.skillSum = tm.skillSum + star(st, SKILL)
        tm.cum[k] = tm.jumpSum
        tm.stats[k] = { lamps = 0, hit = 0, fail = 0 }
      end
    end
    self.teams[t] = tm
  end
  self.ai = { tick = 0, at = 0, on = false }
  self.sparks = {}
  self.sel, self.hold = nil, 0         -- heap+0x140 / +0x141
  self.start = nil                     -- heap+0x16C: the touch's start
  self.timer = TIME
  self.hitFlag = false                 -- heap+0x142
  self.touch = { down = false, new = false, x = 0, y = 0 }
  self.pad = { k = 2, held = false, x = 0, y = 0, used = false }
  self.countdown = 90
  -- the shared 3-2-1 / FINISH sprite at y offset 0xC0 (021F5018)
  if CD.available(game) then self.cd = CD.new(game, 0xC0) end
  self:bandUpdate()
  for _, m in ipairs(self.mons) do m.pos = self.surf[self:idxOf(m)] end
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id, pitch)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then
    pcall(Sound.playSe, self.game.data, id, pitch and { pitch = 2 ^ (pitch / 768) } or nil)
  end
end

-- ------------------------------------------------------------------ band --

-- [0xFA0 + 4 m]: the band sample under the Pokemon
function M:idxOf(m)
  return math.floor(math.floor(clamp(m.xt, X_MIN, X_MAX) / 4096) / 2) % 256
end

-- 021F6BE4 + 021F6B50: Pokemon k's V, `depth` at `idx`, 0 at both edges
function M:setOwn(k, idx, depth)
  local a = self.own[k]
  for i = 0, SAMPLES - 1 do a[i] = 0 end
  a[idx] = depth
  for i = 0, idx - 1 do a[i] = -tdiv((i + 1) * -depth, idx + 1) end
  local r = 127 - idx
  for j = 0, r - 1 do a[idx + 1 + j] = -tdiv((r - j) * -depth, r + 1) end
end

-- 021F6524: the straight line between two Pokemon's depths
function M:setPair(k, a, b)
  local ia, ib = self:idxOf(self.mons[a]), self:idxOf(self.mons[b])
  local l, r, il, ir = a, b, ia, ib
  if ia > ib then l, r, il, ir = b, a, ib, ia end
  local arr = self.pair[k]
  for i = 0, SAMPLES - 1 do arr[i] = 0 end
  local dl, dr = self.own[l][il], self.own[r][ir]
  local n = ir - il
  for t = 0, n - 2 do arr[il + 1 + t] = dl + tdiv((t + 1) * (dr - dl), n) end
end

-- 021F6424: the pairs and the whole band
function M:bandUpdate()
  self:setPair(1, 1, 2)
  self:setPair(2, 2, 3)
  self:setPair(3, 3, 1)
  local o, p = self.own, self.pair
  for i = 0, SAMPLES - 1 do
    self.surf[i] = math.min(o[1][i], o[2][i], o[3][i], p[1][i], p[2][i], p[3][i])
  end
end

-- 021F64A0: the band the other two make (masks 6 / 5 / 3)
local OTHERS = { { 2, 3 }, { 1, 3 }, { 1, 2 } }
-- pair k joins (k, k % 3 + 1): bit b selects own b and pair b
function M:othersAt(k, idx)
  local v = 0
  for _, b in ipairs(OTHERS[k]) do
    v = math.min(v, self.own[b][idx], self.pair[b][idx])
  end
  return v
end

-- ---------------------------------------------------------------- bodies --

-- the feet point in the 384-px space (021F5D3C)
local function feetY(m) return tdiv(0x120000 - m.pos * 64, 4096) end
local function feetX(m) return tdiv(m.xt, 4096) end
-- the body circle (021EB0A4 + 021EAF78): centre, radius
local function body(m)
  return feetX(m), feetY(m) + (2 + m.class) - m.yoff, m.radius
end

-- ----------------------------------------------------------------- rules --

-- 021F65D8: one more lamp this jump
local function lampHit(m)
  if m.combo < 5 then m.combo = m.combo + 1 end
  m.score = math.min(999, m.score + m.combo)
  return m.combo
end

-- 021F6798: one Pokemon's motion
function M:move(k)
  local m = self.mons[k]
  if not m.active then return end
  local idx = self:idxOf(m)
  local surf = self:othersAt(k, idx)
  local function settle(keepVel)
    m.fly, m.pos, m.j18, m.active = false, surf, 0, false
    if not keepVel then m.vel = 0 end
    self:setOwn(k, idx, 0)
  end
  if m.fly then
    if m.j18 <= 0 then
      settle(true)
      m.vel, m.fresh = 0, true
      return
    end
    m.pos = m.pos + m.vel
    -- 021F6B28: sideways while above the rest line
    if m.vx ~= 0 and m.pos > 0 then m.xt = clamp(clamp(m.xt, X_MIN, X_MAX) + m.vx, X_MIN, X_MAX) end
    if m.pos > surf then
      m.vel = fix(m.vel - 128.0)
      if -m.vel > m.j18 then m.vel = -m.j18 end
    elseif m.vel == 0 then
      settle(true)
    elseif m.vel < 0 then
      -- into the band again
      m.fly = false
      -- 021F7130: the drift 2 px nearer 0
      if m.vx > 0 then m.vx = math.max(0, m.vx - 0x2000) elseif m.vx < 0 then m.vx = math.min(0, m.vx + 0x2000) end
      if m.vel > -128.0 then m.vel = -128 end
      m.j18 = m.vel
    else
      settle(false)
    end
  else
    m.pos = m.pos + m.vel
    if m.pos < -6144.0 then m.pos, m.vel = -6144, 0 end
    if m.pos >= surf then
      self:setOwn(k, idx, 0)
      if m.fresh then m.vel = tdiv(m.vel * m.kick, 12) end
      if m.vel > 0x898 then m.vel = 0x898 end
      m.vel = tdiv(m.vel * 9, 10)
      if m.vel == 0 then
        if m.fresh then se(self, SE.flop) end
        settle(true)
      elseif m.vel > 0 then
        if m.vel <= 1408.0 and not m.fresh then
          settle(false)
        else
          -- a jump
          m.fly, m.j18, m.fresh = true, m.vel, false
          m.jumps = m.jumps + 1
          se(self, SE.jump)
        end
      end
    elseif m.vel < 0 then
      m.vel = fix(m.vel + 819.2)
      if m.vel >= 0 then m.vel = 0 end
    else
      m.vel = fix(m.vel + 1024 / 3)
      if m.vel > -m.j18 then m.vel = -m.j18 end
    end
  end
  if not (m.fly and m.active and m.vel ~= 0) then m.combo = 0 end
  if not m.fly and m.active then self:setOwn(k, idx, m.pos) end
  if not m.active then m.fresh = true end
end

-- 021F6600: motion, then the lamps, then the stun clocks
function M:physics()
  for k = 1, 3 do self:move(k) end
  for k = 1, 3 do
    local m = self.mons[k]
    local bx, by, br = body(m)
    for _, l in ipairs(self.lamps) do
      if l.lit then
        local dx, dy = bx - l.x, by - l.y
        if math.sqrt(dx * dx + dy * dy) <= br + 8 then
          l.lit = false
          local c = lampHit(m)
          l.pts, l.popT, l.burstT = c, 0, 0
          self.hitFlag = true
          m.lamps = m.lamps + 1
          se(self, SE.lamp, LAMP_PITCH[c])
        end
      end
    end
  end
  for _, m in ipairs(self.mons) do
    if m.stun then
      m.stunT = (m.stunT - 1) % 256
      if m.stunT == 0 then m.stun = false end
    end
  end
end

-- 021F6BB0: a Pokemon at rest rides the band
function M:ride()
  for _, m in ipairs(self.mons) do
    if not m.active then m.pos = self.surf[self:idxOf(m)] end
  end
end

-- 021F7194: two of the three touching
function M:collisions()
  for i = 1, 3 do
    for j = 1, 3 do
      if i ~= j then
        local a, b = self.mons[i], self.mons[j]
        local ax, ay, ar = body(a)
        local bx, by, br = body(b)
        local dx, dy = bx - ax, by - ay
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > ar + br then
          a.latch[j], b.latch[i] = false, false
        elseif not b.latch[i] then
          a.stun, b.stun = true, true
          a.stunT, b.stunT = a.stunFrames % 256, b.stunFrames % 256
          local nx, ny = 0, 0
          if dist > 0 then nx, ny = dx / dist, dy / dist end
          table.insert(self.sparks, { x = ax + nx * ar, y = ay + ny * ar, t = 0 })
          if #self.sparks > 3 then table.remove(self.sparks, 1) end
          se(self, SE.bump)
          a.hits, b.hits = a.hits + 1, b.hits + 1
          a.fails, b.fails = a.fails + 1, b.fails + 1
          if a.fly and b.fly and a.pos > 0 and b.pos > 0 then
            if not a.latch[j] and not b.latch[i] then
              a.latch[j], b.latch[i] = true, true
              a.vel, b.vel = b.vel, a.vel
              a.vx, b.vx = b.vx, a.vx
              if a.vel < 0 then a.vel = 0 end
              if b.vel < 0 then b.vel = 0 end
            end
          else
            if a.xt <= b.xt then a.xt, b.xt = a.xt - 0x10000, b.xt + 0x10000
            else a.xt, b.xt = a.xt + 0x10000, b.xt - 0x10000 end
            a.xt, b.xt = clamp(a.xt, X_MIN, X_MAX), clamp(b.xt, X_MIN, X_MAX)
          end
        end
      end
    end
  end
end

-- 021F7598 / 021F7620: up to 25 dark lamps light every 241 frames
function M:stepLamps()
  if self.relight > 0 then self.relight = self.relight - 1; return end
  local dark = {}
  for _, l in ipairs(self.lamps) do if not l.lit then dark[#dark + 1] = l end end
  local n = #dark
  for _ = 1, 25 do
    if n <= 0 then break end
    local k = rand(n) + 1
    dark[k].lit = true
    dark[k] = dark[n]
    n = n - 1
  end
  self.relight = RELIGHT
end

-- 021F7740 / 021F77EC: one rival team's roll each frame, every 3 frames
function M:stepAi()
  local ai = self.ai
  ai.tick = ai.tick + 1
  for t = 2, 4 do self.teams[t].flag = false end
  if ai.tick >= 3 then ai.on, ai.tick = true, 0 end
  if not ai.on then return end
  local tm = self.teams[2 + ai.at]
  local v = 0
  if tm.jumpSum ~= 0 then v = 2 * tm.jumpSum + tm.skillSum + rand(101) end
  if v >= 100 then
    tm.flag = true
    local r = rand(tm.jumpSum)
    for k = 1, 3 do
      if r < tm.cum[k] then tm.stats[k].lamps = tm.stats[k].lamps + 1; break end
    end
  end
  ai.at = ai.at + 1
  if ai.at >= 3 then ai.at, ai.on = 0, false end
end

-- 021F6088: the catapult
function M:launch(k, ddx, ddy)
  local m = self.mons[k]
  if ddy <= 0 or m.active then return end
  local vy = fix(tdiv(ddy, 64) / 2.5)
  local vx = clamp(tdiv(-ddx, 4), -0xA000, 0xA000)
  m.vx = tdiv(vx * m.drift, 12)
  m.vel, m.j18, m.active = -vy, -vy, true
  se(self, SE.launch)
end

-- 021F5F68: the nearest of the three under the stylus (not stunned)
function M:pick(tx, ty)
  local best, bd = nil, GRAB_R
  for k, m in ipairs(self.mons) do
    if not m.stun then
      local wx = feetX(m)
      local wy = tdiv(0x60000 - m.pos * 64, 4096) + m.wdy
      local dd = math.sqrt((wx - tx) ^ 2 + (wy - ty) ^ 2)
      if dd < bd then best, bd = k, dd end
    end
  end
  return best
end

-- 021F5BA0: the stylus, once a frame
function M:stepInput()
  local tc = self.touch
  local new = tc.new
  tc.new = false
  -- drag vector in fx: (now - start), y at most 112 px (021F5F34)
  local function drag()
    local dx = math.floor(tc.x) * 4096 - self.start[1]
    local dy = math.floor(tc.y) * 4096 + 0xC0000 - self.start[2]
    if dy > 0x70000 then dy = 0x70000 end
    return dx, dy
  end
  if new and tc.down then
    local k = self:pick(tc.x, tc.y)
    if k then
      self.sel = k
      self.start = { math.floor(tc.x) * 4096, math.floor(tc.y) * 4096 + 0xC0000 }
    end
  elseif tc.down then
    if self.sel then
      if self.hold < HOLD then
        self.hold = self.hold + 1
      else
        local dx, dy = drag()
        self:launch(self.sel, dx, dy)
        self.sel, self.hold = nil, 0
      end
    end
  else
    if self.sel and self.hold < HOLD then
      local dx, dy = drag()
      self:launch(self.sel, dx, dy)
    end
    self.sel, self.hold = nil, 0
  end
end

function M:step()
  self.frame = self.frame + 1
  self:stepInput()
  self:stepAi()
  -- 021F5A88
  self.hitFlag = false
  if self.timer > 0 then self.timer = self.timer - 1 end
  if self.timer <= 0 then
    self.over, self.sel, self.hold = 60, nil, 0
    if self.cd then self.cd:startFinish(Rec.isNew(self.game, 5, self:teamScore())) end
    return
  end
  self:physics()
  self:bandUpdate()
  self:ride()
  self:collisions()
  self:stepLamps()
  -- the effects' clocks and the team markers (021F5D3C / 021F5EC4)
  for _, l in ipairs(self.lamps) do
    if l.popT then l.popT = l.popT + 1; if l.popT > 17 then l.popT = nil end end
    if l.burstT then l.burstT = l.burstT + 1; if l.burstT > 17 then l.burstT = nil end end
  end
  for i = #self.sparks, 1, -1 do
    local s = self.sparks[i]
    s.t = s.t + 1
    if s.t > 17 then table.remove(self.sparks, i) end
  end
  for t, tm in ipairs(self.teams) do
    local flag = (t == 1) and self.hitFlag or tm.flag
    if tm.markT then tm.markT = tm.markT + 1; if tm.markT >= 13 then tm.markT = nil end end
    if flag and not tm.markT then tm.markT = 0 end
  end
  for _, m in ipairs(self.mons) do m.step = m.step + 1 end
  -- the last three seconds (021E6454)
  local n = math.floor((self.timer + 29) / 30)
  if n >= 1 and n <= 3 and n ~= self.lastCount then
    self.lastCount = n
    se(self, SE.tick)
  end
end

function M:teamScore()
  local s = 0
  for _, m in ipairs(self.mons) do s = s + m.score end
  return math.min(999, s)
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
  if self.showTop and not SecondScreen.separate(self.game) then return true end
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
  if px and self.touch.down then self.touch.x, self.touch.y = px, py end
  self.touch.down = false
  return true
end

-- PAD / KEYS (not the cartridge's): LEFT / RIGHT pick one of the three; A
-- puts the stylus on it and, while held, pulls it down 16 px a frame (the
-- full 112 px when it goes off by itself; let go early for a smaller jump);
-- LEFT / RIGHT while A is held drag sideways (the drift goes the other way);
-- SELECT / L shows the top screen on a single screen
function M:padInput()
  local input = self.game.input
  if not input or self.padOff then return end
  if input:wasPressed("select") or input:wasPressed("l") then self.showTop = not self.showTop end
  local pd = self.pad
  local tc = self.touch
  if not pd.held then
    if input:wasPressed("left") then pd.k = (pd.k + 1) % 3 + 1; pd.used = true end
    if input:wasPressed("right") then pd.k = pd.k % 3 + 1; pd.used = true end
  end
  local a = input:isDown("a")
  if a and not pd.held then
    local m = self.mons[pd.k]
    pd.held, pd.used = true, true
    pd.x, pd.y = feetX(m), tdiv(0x60000 - m.pos * 64, 4096) + m.wdy
    tc.down, tc.new, tc.x, tc.y = true, true, pd.x, pd.y
  elseif a and pd.held then
    tc.x, tc.y = pd.x, pd.y
  elseif pd.held then
    pd.held = false
    tc.down = false
  end
end

-- the pad's stylus moves at the logic's rate
function M:padPull()
  local pd = self.pad
  if not pd.held then return end
  local input = self.game.input
  pd.y = math.min(H - 1, pd.y + 16)
  if input and input:isDown("left") then pd.x = math.max(0, pd.x - 6) end
  if input and input:isDown("right") then pd.x = math.min(W - 1, pd.x + 6) end
  self.touch.x, self.touch.y = pd.x, pd.y
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
    else
      self.countdown = self.countdown - 1
    end
    if self.countdown == 0 then self.relight = 0 end
    return
  end
  if self.over and self.cd then
    -- the FINISH (021E667C), the field stopped (021F5650 case 5)
    if not self.cd:finishing() then return self:finish() end
    return
  end
  if self.over then
    self.over = self.over - 1
    if self.over <= 0 then return self:finish() end
    return
  end
  self:step()
  self:padPull()
end

-- ov96_021F5730 (field5E0) and ov96_0221A6B0 (/ 3.5, cap 200)
function M:finish()
  if self.done then return end
  self.done = true
  local pts, stats, scores = {}, {}, {}
  scores[1] = self:teamScore()
  stats[1] = {}
  for k, m in ipairs(self.mons) do
    stats[1][k] = { miss = m.fails > 0, score = m.lamps, jump = m.jumps, dash = 0, hit = m.hits, fail = m.fails, points = m.score }
  end
  for t = 2, 4 do
    local tm = self.teams[t]
    local total = 0
    stats[t] = {}
    for k = 1, 3 do
      local st = tm.stars[k]
      local j = star(st, JUMP)
      if j ~= 0 then total = total + 80 + 6 * j + 2 * star(st, STAMINA) + 2 * star(st, SKILL) + rand(21) end
      local r = rand(21)
      local s = tm.stats[k]
      stats[t][k] = { miss = r > 0, score = s.lamps, jump = 0, dash = 0, hit = r, fail = r }
    end
    scores[t] = total % 65536
  end
  for t = 1, 4 do pts[t] = math.min(200, math.floor(scores[t] / 3.5)) end
  self.game.stack:pop()
  if self.onDone then
    self.onDone({ points = pts, total = scores[1], scores = scores, stats = stats, record = scores[1] })
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
function M:anim(seq, t, once)
  local list = self.d.objSeq and self.d.objSeq.obj and (self.d.objSeq.obj[seq] or self.d.objSeq.obj[tostring(seq)])
  if type(list) ~= "table" or #list == 0 then return ("obj_%d_0"):format(seq) end
  local total = 0
  for _, v in ipairs(list) do total = total + v end
  local at = once and math.min(t, total - 1) or t % math.max(1, total)
  for f, v in ipairs(list) do
    if at < v then return ("obj_%d_%d"):format(seq, f - 1) end
    at = at - v
  end
  return ("obj_%d_%d"):format(seq, #list - 1)
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

local SPIN = { "down", "left", "up", "right" }

-- the walking Pokemon (gen4_follow_mon), or its icon; (x, y) = its feet
function M:walker(m, x, y)
  local mon = m.mon
  if not mon then return end
  local g = love.graphics
  local data = self.game.data
  local face = m.active and "up" or "down"
  if m.stun then face = SPIN[math.floor(m.step / 4) % 4 + 1] end
  local sheet = self:sheetOf(mon)
  local path = sheet and ((mon.shiny or mon.isShiny) and sheet.shiny or sheet.normal)
  local img = type(path) == "string" and cachedImage(self, path)
  local cy = y + m.wdy
  if img then
    local fw, fh = tonumber(sheet.frameWidth) or 32, tonumber(sheet.frameHeight) or 32
    local iw, ih = img:getDimensions()
    local base = ({ up = 0, down = 2, left = 4, right = 6 })[face] or 2
    local f = base + (math.floor(m.step / 8) % 2)
    if (f + 1) * fh > ih then f = 0 end
    g.draw(img, g.newQuad(0, f * fh, fw, fh, iw, ih), math.floor(x - fw / 2), math.floor(cy - fh / 2))
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
  g.draw(icon, g.newQuad(0, (math.floor(m.step / 8) % frames) * fh, iw, fh, iw, ih),
    math.floor(x - iw / 2), math.floor(cy - fh / 2))
end

-- 021F61C8: the band, a strip of 128 + 2 vertex pairs from its height down
-- to -1.5 units, coloured per pair (red, green, blue step 1 mod 31)
function M:drawBand(oy)
  local g = love.graphics
  local verts = {}
  local function px(xw) return 128 + xw * BAND_S end
  local function py(yw) return 96 - yw * BAND_S + 192 - oy end
  local cr, cg, cb = 31, 5, 0                    -- COLOR 0xBF before the strip
  local function pair(xw, top)
    local c = { cr / 31, cg / 31, cb / 31, 17 / 31 }
    verts[#verts + 1] = { px(xw), py(top), 0, 0, c[1], c[2], c[3], c[4] }
    verts[#verts + 1] = { px(xw), py(-1.5), 0, 0, c[1], c[2], c[3], c[4] }
  end
  pair(-2, 0)
  local r, gg, b = 0, 10, 20
  for i = 1, SAMPLES do
    pair((i - 64) * 4 / 128, self.surf[i - 1] / 4096)
    cr, cg, cb = r, gg, b
    r, gg, b = (r + 1) % 31, (gg + 1) % 31, (b + 1) % 31
  end
  if not self.bandMesh then
    local ok, mesh = pcall(g.newMesh, #verts, "strip", "stream")
    self.bandMesh = ok and mesh or false
  end
  if self.bandMesh then
    self.bandMesh:setVertices(verts)
    g.setColor(1, 1, 1, 1)
    g.draw(self.bandMesh)
  end
  -- the band's edge
  g.setColor(1, 1, 1, 0.8)
  local line = {}
  for i = 1, SAMPLES do
    line[#line + 1] = px((i - 64) * 4 / 128)
    line[#line + 1] = py(self.surf[i - 1] / 4096)
  end
  g.line(line)
  g.setColor(1, 1, 1, 1)
end

-- what sits in the 384-px space, drawn for the screen whose top is `oy`
function M:drawWorld(oy)
  local g = love.graphics
  g.push()
  g.translate(0, -oy)
  -- the lamps (+0x10: 7 lit, 8 out) and their points / bursts
  for _, l in ipairs(self.lamps) do
    if l.y > oy - 24 and l.y < oy + H + 24 then
      self:sprite(l.lit and "obj_7_0" or "obj_8_0", l.x, l.y)
      if l.burstT then self:sprite(self:anim(10, l.burstT, true), l.x, l.y) end
      if l.popT then self:sprite(self:anim(l.pts, l.popT, true), l.x, l.y) end
    end
  end
  -- the Pokemon, back to front
  local order = { self.mons[1], self.mons[2], self.mons[3] }
  table.sort(order, function(a, b) return a.slot < b.slot end)
  for _, m in ipairs(order) do
    local x, y = feetX(m), feetY(m)
    if y > oy - 64 and y < oy + H + 64 then
      if self.sel == m.slot then
        g.setColor(1, 1, 1, 0.9)
        g.ellipse("line", x + 0.5, y + 0.5, m.radius + 4, (m.radius + 4) * 0.5)
      end
      g.setColor(1, 1, 1, 1)
      self:walker(m, x, y)
      -- +4: the dizzy stars (seq 11), 24 px up for a tall one, else 16
      if m.stun then self:sprite(self:anim(11, m.step), x, y - (m.tall and 24 or 16)) end
      if self.pad.used and self.pad.k == m.slot and not m.active then
        g.setColor(1, 1, 0.3, 1)
        local ty = y + m.wdy - 22
        g.polygon("fill", x - 4, ty - 6, x + 4, ty - 6, x, ty)
        g.setColor(1, 1, 1, 1)
      end
    end
  end
  for _, s in ipairs(self.sparks) do self:sprite(self:anim(9, s.t, true), s.x, s.y) end
  g.pop()
end

local function drawPart(img, x, y, qx, qy, qw, qh)
  local iw, ih = img:getDimensions()
  love.graphics.draw(img, love.graphics.newQuad(qx, qy, qw, qh, iw, ih), x + qx, y + qy)
end

function M:scoreText()
  local s = self:teamScore()
  if self.scoreFor ~= s then
    -- BufferIntegerAsString(slot 0, score, 3 digits) then message 161 (021F70AC)
    local ok, str = pcall(function()
      local T = require("src.import.Gen4Text")
      T.buffer(self.game, tostring(s))
      return T.resolve(self.game.data, 309, 161, self.game)
    end)
    self.scoreFor = s
    self.scoreStr = (ok and type(str) == "string" and str:find("%d")) and str:gsub("{[^}]*}", "") or ("%d points!"):format(s)
  end
  return self.scoreStr
end

-- the touch screen: BG2, the band, BG1 (the posts), the Pokemon and lamps
function M:drawBottom()
  local g = love.graphics
  g.setColor(0.3, 0.7, 0.4, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local back = self:img("back")
  if back then g.draw(back, 0, 0) end
  self:drawBand(192)
  local front = self:img("front")
  if front then g.draw(front, 0, 0) end
  self:drawWorld(192)
  local Font = require("src.render.Font")
  if self.countdown > 0 then
    if not self.cd then
      g.setColor(0, 0, 0, 0.5)
      g.rectangle("fill", 112, 128, 32, 24)
      g.setColor(1, 1, 1, 1)
      Font.draw(tostring(math.ceil(self.countdown / 30)), 124, 136)
    end
  elseif self.over then
    if not self.cd then
      g.setColor(0, 0, 0, 0.5)
      g.rectangle("fill", 88, 60, 80, 24)
      g.setColor(1, 1, 1, 1)
      Font.draw("FINISH!", 100, 68)
    end
    -- window 4 (BG3, tile row 20): message 161 with the team's score
    g.setColor(0, 0, 0, 0.6)
    g.rectangle("fill", 0, 160, 256, 16)
    g.setColor(1, 1, 1, 1)
    Font.draw(self:scoreText(), 8, 162)
  end
  -- the shared 3-2-1 / FINISH: the touch screen's surface starts at 0xC0
  if self.cd then self.cd:draw(0xC0) end
end

-- the top screen: BG5, BG4 with the score's digits, the lamps above, the
-- clock, the names and the team markers
function M:drawTop()
  local g = love.graphics
  local Font = require("src.render.Font")
  g.setColor(0.4, 0.75, 0.95, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local a = self:img("top")
  if a then g.draw(a, 0, 0) end
  local b = self:img("top_b")
  if b then
    -- BG4 without its digit rect (tiles 1..12 x 0..7, written by 021F6E68)
    drawPart(b, 0, 0, 0, 64, 256, 128)
    drawPart(b, 0, 0, 0, 0, 8, 64)
    drawPart(b, 0, 0, 104, 0, 152, 64)
  end
  local digits = self:img("digits")
  if digits then
    local iw, ih = digits:getDimensions()
    local v = self:teamScore()
    local ds = { math.floor(v / 100), math.floor(v / 10) % 10, v % 10 }
    for i, dg in ipairs(ds) do
      g.draw(digits, g.newQuad((dg % 5) * 32, math.floor(dg / 5) * 64, 32, 64, iw, ih), 8 + 32 * (i - 1), 0)
    end
  end
  self:drawWorld(0)
  -- the clock (+0x64 seq 12 at (168, 8); digits at x 192 / 208)
  self:sprite("obj_12_0", 168, 8)
  g.setColor(0, 0, 0, 0.45)
  g.rectangle("fill", 180, 1, 40, 14)
  g.setColor(1, 1, 1, 1)
  Font.draw(("%02d"):format(math.min(99, math.floor(self.timer / 30))), 190, 4)
  -- the names (windows 0..3, BG6) and the markers (seq 13 + team)
  for t, tm in ipairs(self.teams) do
    local nx, ny, mx, my
    if t == 1 then nx, ny, mx, my = 32, 64, MARK_ME[1], MARK_ME[2]
    else nx, ny, mx, my = 176, 32 + 16 * (t - 2), MARK_RIVAL[1], MARK_RIVAL[2] + 16 * (t - 2) end
    local seq = 12 + t
    self:sprite(tm.markT and self:anim(seq, tm.markT, true) or ("obj_%d_0"):format(seq), mx, my)
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", nx - 2, ny, 80, 14)
    g.setColor(1, 1, 1, 1)
    Font.draw(tostring(tm.name):sub(1, 10), nx, ny + 2)
  end
  local n = math.floor((self.timer + 29) / 30)
  if self.countdown <= 0 and not self.over and n >= 1 and n <= 3 then
    local rgb = TEAM_RGB[1]
    g.setColor(rgb[1], rgb[2], rgb[3], 0.85)
    g.rectangle("fill", 112, 80, 32, 28)
    g.setColor(1, 1, 1, 1)
    Font.draw(tostring(n), 124, 88)
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
