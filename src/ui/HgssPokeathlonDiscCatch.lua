-- HEARTGOLD / SOULSILVER POKeATHLON: DISC CATCH (pokeheartgold
-- asm/overlay_96.s 0x0220D360..0x02210C98, event 4, sub-app ov96_0221A8A8 =
-- init 0220E3F0 / draw 0220E5F4 / results 0220E60C / exit 0220E670, states
-- ov96_0221DC74 (= _0221DA00[4]) = { 0220E22C fade + 3-2-1, 0220E2DC play
-- (0220F03C logic + 0220F1CC input / sprites until the end flag, then
-- 021E667C finish), 0220E394 end: field5E0[team] = the team's points }; the
-- event's per-frame code sits BEFORE its init, like Block Smash's; the
-- reading is written up in scratch_claude/athlon/NOTES.md, "## Disc Catch").
-- Art and tables: `gen4_hgss_disc_catch`
-- (src/import/Gen4HgssPokeathlonDiscCatchArt.lua).
--
-- THE PIER is the touch screen: twelve Pokemon, four teams of three in
-- columns (ov96_0221CFBC: team t at x 40 / 96 / 160 / 216, rows y 40 / 88 /
-- 152); its four painted bands are worth 1 / 2 / 3 / 5. The discs come from
-- the top of the top screen (x 128) and fly down over both screens: one
-- disc coordinate y runs 0..479 (the top screen is 0..191, the touch screen
-- 288..479) and on to 527 when nobody caught it.
--
-- READ FROM CODE (the logic runs at the Pokeathlon's 30 frames a second):
--   * a Pokemon's numbers (0220F280, NARC 170 MEMBER 7 -- not 4 -- by its
--     course record): J = [JUMP] (5 6 7 9 15; the jump lasts 2 J frames),
--     arc height [5 + JUMP] / 10 (4 4 3 3 1), bump power [10 + POWER] / 10
--     (4.0 .. 6.0), walk [15 + SPEED] / 10 px a frame (2.4 .. 7.2); its
--     {yoff, radius} = member 17 by the performance row's byte 6 (8/8,
--     10/10, 12/14, 0220F4A0 -> 021EAF70)
--   * THE CLOCK: 0x708 = 1800 frames (heap+0x50C), seconds = (clock + 30) /
--     30 after the tick; at 0 the end flag freezes everything (0220F03C)
--   * THE STYLUS (0220F03C's input record, 0220F8C8): a new touch takes the
--     NEAREST of the team's three whose point is within 80 px (0220DAA0 /
--     021EB0CC / 021E6104); while held, if the stylus is more than 8 px
--     (x or y) from it, its target is the stylus (0220D6B0) and it is marked
--     "dragged"; if that target is off the pier, "dragged out". Let go ON it
--     (nearest again) after 5 frames or fewer of holding, while it stands
--     (state 2) = A JUMP (0220D630). A fallen one held is let go.
--   * THE JUMP (0220D630): only with 2 JUMP stars or more -- a 1-star jumper
--     only squashes (0220D52C / 0220D468, SE 0x5F3); state 1 for 2 J frames
--     (it keeps walking), course counter 2 (jump). The arc (0220E8C0): up
--     h x f (2 J - f) / 10 px at frame f, at most 24, the sprite scaled
--     1 - (lift - 4) / 100
--   * WALKING (0220D744): towards the target at walk speed, landing on it
--     within one step; facing by the four 90-degree quarters (0220D6CC)
--   * BUMPS (0220F710, every pair once per contact): two Pokemon standing or
--     jumping whose bodies touch (radius + radius, 0220D5D0) push apart:
--     d = unit(A - B); A's knock = B's power x d + A's last step direction,
--     B's = -(A's power x d + B's last step direction) -- the power x 6 / 5
--     when the one knocked is a small (32-px) walker -- each component
--     clamped to 8 px; the knock carries it (and its target with it), losing
--     0.8 px a frame along itself (+ its power / 100 along its walk when it
--     was dragged), until it is 0 (0220D744 / 0220E960)
--   * FALLING (0220D9A4): standing (not jumping) with its feet outside x
--     8..247 / y 8..179 (0220D8C4) = fallen: counters 1 (fail) and 5 (+ 8 if
--     dragged out), 90 frames away, then back at its own spot (0220D910)
--   * THE DISCS (02210030 / 0220FF88 / 0220FE38, two records): the phase by
--     seconds left (ov96_0221CF1C: >= 55 / 40 / 20 / else): phase 0 one disc
--     at a time, a try every 31 frames; 1 two, every frame; 2 two, every 31;
--     3 two, every frame and at speed 4 or 8 at random (else 4). A disc gets
--     a line k = rand % 15: x = 128 + (k - 7) y 38 / 1000 + 4 sin(2 y deg)
--     (0220E6DC), y += speed a frame; at y 480 nobody caught it (48 more px)
--   * CATCHING (0220FBEC): on the touch screen, the first of the twelve (in
--     team order) that is JUMPING with its feet within its radius + 14 px of
--     the disc's point catches it; its band by the feet's tile row (0220FD28
--     / 0220FCB0): < 9 = 1, < 15 = 2, < 20 = 3, else 5, the band edges curving
--     up one row at tile columns < 8 / > 23, two at < 5 / > 26, three at < 2 /
--     > 29; the team's points + that (cap 200), counter 3 (score) + 1. The
--     disc shows the catch for 20 frames.
--   * THE RIVALS (02210858 / 022108EC / 02210AE0 / 022109D8 / 02210BD0): each
--     rival Pokemon has a home -- its column's x +- 0 / 8 / 16 and a row band
--     by slot (ov96_0221D1B0: 8-px rows 3..7 / 7..12 / 15..20), picked again
--     every 90 frames (0221090C, also ending a chase); every 20 frames it
--     thinks (the first after 2 t + 8 slot): no chase -> walk home, and chase
--     a disc whose point is within radius + 56 px; chasing -> aim at the
--     disc line's x on its own home row (home y + 288); gone -> stop. Chasing,
--     every frame with the disc within radius + 16: jump at rand % 100 <
--     3 / 6 / 36 (by slot, ov96_0221D1B8) -- 0 when the team's points are
--     more than 20 above the average of all four. NOTE the cartridge reads
--     the points of team k (0, 1, 2) for rival team k + 1 (the loop index,
--     not the participant): kept.
--   * Athlete Points (ov96_0221A69C: ov96_0221A5D4 + 0221A61C) = int(150 -
--     120 / (1 + 0.08 points)), at most 200 -- the same as Bulbapedia's
--     floor(30 + 120 p / (12.5 + p)). No-Miss = never fell off. Effort
--     counters: jump, fail (the falls). score = catches (counter 3 adds 1).
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 0220E3F0 puts them on the main
--     engine at y offset 0 (021E61D8 r1, its SpriteSystem list), the touch
--     screen here (gSystem.screensFlipped = 1, main surface at 0); 0220E22C
--     runs the countdown after the fade, 0220E2DC the finish once the end
--     flag is up
--
-- THE RECORD (READ FROM CODE; src/pokemon/HgssPokeathlonRecords.lua): at
-- time up 0220E2A8 hands ov96_021E8318 the team's points as the top screen
-- keeps them (022104C4: +0xE5 << 7 + +0xE6, cut to a byte) for NEW RECORD!
-- (021E839C, higher is better); the end state's field_5E0 (0220E394, the
-- points, at most 200) is what the course's end saves.
--
-- STAND-INS, said so: during the FINISH the field stands still (the
-- cartridge runs 0220F03C on under it); without `gen4_hgss_athlon_common`
-- the 3-2-1 / finish are 3 s of numbers / FINISH!; the Pokemon's world point is
-- Circle Push's reading of 021EB0A4 (feet + (2 + size class) - half the
-- sprite height), the body (bumps) = feet - yoff; the walkers are
-- gen4_follow_mon sheets (icons fallback) with a team-colour ring for the
-- cartridge's team shadows (021E61D8 / 021E64F8 not read); the touch
-- screen shakes 4 / 3 px for 4 frames on our catches (0220D428 -> 0220D360);
-- the top screen is drawn from its BGs and sprites as placed by 0221069C /
-- 0221075C / 0221065C (names in the port's font, the clock's red / flashing
-- palettes 2 / 3 as a tint); a falling Pokemon shrinks 0.1 a frame for 6
-- frames and sinks 4 px a frame at the bottom edge (0220DEAC) and comes
-- back with the puff (sprite a 5); the input is used the frame it comes
-- (the cartridge's record is one frame late); sounds by id (0x8C3 throw,
-- 0x8C4 catch, 0x88D ours scored, 0x8C5 jump, 0x5F3 no jump, 0x89E fall,
-- 0x8B6 back).

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local CLOCK = 0x708                    -- 1800 frames
local GRAB_R = 80                      -- ov96_021E6104
local SUB_Y = 288                      -- the touch screen in disc space
local DISC_END = 480                   -- 0x1E0
local FALL_FRAMES = 90                 -- 0x5A
local CAUGHT_FRAMES = 20
local TAP_FRAMES = 5
local KNOCK_MAX = 8.0                  -- 0x8000
local FRICTION = 0x0CCD / 4096         -- 0.8
local TEAM_RGB = { [0] = { 0.94, 0.25, 0.25 }, { 0.25, 0.45, 0.95 }, { 0.2, 0.75, 0.3 }, { 0.95, 0.85, 0.2 } }
local SE = { throw = 0x8C3, catch = 0x8C4, scored = 0x88D, jump = 0x8C5, nojump = 0x5F3, fall = 0x89E, back = 0x8B6 }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local POWER, JUMP, SPEED = 0, 3, 4
-- ov96_0220F3BC: the disc's state 3..6 -> points
local STATE_PTS = { [3] = 1, [4] = 2, [5] = 3, [6] = 5 }
local FACES = { "up", "down", "left", "right" }

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function len(x, y) return math.sqrt(x * x + y * y) end
local function trunc(v) return v < 0 and math.ceil(v) or math.floor(v) end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_disc_catch
  return type(d) == "table" and d.params ~= nil and d.spawns ~= nil and d.pier ~= nil
end

-- ------------------------------------------------------------ the discs --

-- ov96_0220E6DC: a disc line's x at y
function M.lineX(y, k)
  local x = 128 + trunc((k - 7) * y * 0x26 / 1000)
  local s = math.floor(math.sin(math.rad((2 * y) % 65536 % 360)) * 4096)
  return x + math.floor(s * 64 / 65536)
end

-- ov96_0220FCB0: is the tile (tx, ty) past the curved edge of band N?
local function pastEdge(tx, ty, n)
  if ty == n - 1 and (tx < 8 or tx > 23) then return true end
  if ty == n - 2 and (tx < 5 or tx > 26) then return true end
  if ty == n - 3 and (tx < 2 or tx > 29) then return true end
  return false
end

-- ov96_0220FD28: the band (disc state 3..6) of a catch at screen (x, y)
function M.band(x, y)
  local tx, ty = trunc(x / 8), trunc(y / 8)
  if ty < 9 then return pastEdge(tx, ty, 9) and 4 or 3 end
  if ty < 15 then return pastEdge(tx, ty, 15) and 5 or 4 end
  if ty < 20 then return pastEdge(tx, ty, 20) and 6 or 5 end
  return 6
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

-- the walking sheet (gen4_follow_mon)
function M:sheetOf(mon)
  local fm = self.game.data.gen4_follow_mon
  if not (mon and type(fm) == "table" and fm.sheets) then return nil end
  local ok, Data = pcall(require, "src.import.Gen4HgssFollowMon")
  if not ok then return nil end
  local idx = Data.index(fm, tonumber(mon.species), tonumber(mon.form) or 0, false)
  return fm.sheets[idx] or fm.sheets[tostring(idx)]
end

local function spawnOf(self, t, k)
  local s = self.d.spawns[t] or self.d.spawns[tostring(t)]
  return s[k + 1]
end

-- 0220F280 + 0220F4A0: mon k of team t
local function newMon(self, mon, st, t, k)
  local p = self.d.params
  local class = classOf(self, mon)
  local size = self.d.sizes and (self.d.sizes[class] or self.d.sizes[tostring(class)])
  local sheet = self:sheetOf(mon)
  local tall = (sheet and tonumber(sheet.frameHeight) or 32) >= 64
  local wdy = (2 + class) - (tall and 32 or 16)
  local s = spawnOf(self, t, k)
  local j = star(st, JUMP)
  local m = {
    mon = mon, team = t, slot = k, id = 3 * t + k,
    jumpStars = j,
    J = p[j],                                 -- rec[0]
    lift = p[5 + j],                          -- rec[1]
    power = p[10 + star(st, POWER)] / 10,     -- rec[4]
    speed = p[15 + star(st, SPEED)] / 10,     -- rec[8]
    yoff = size and size[1] or 8, radius = size and size[2] or 8,
    tall = tall, wdy = wdy,
    x = s[1], y = s[2] + wdy,                 -- the world point (0x1C)
    tx = s[1], ty = s[2] + wdy,               -- the target (0x10)
    kx = 0, ky = 0,                           -- the knock (0x34)
    lx = 0, ly = 0,                           -- the last step's direction (0x28)
    state = 2, timer = 0, fallT = 0,          -- 0xC, [0x40] bits 0-7, 0x44
    face = 2, knocked = false, dragged = false, moving = false, dragOut = false,
    flash = 0,                                -- [0x40] bits 8-15
    jumps = 0, falls = 0, catches = 0, fell = false,
    -- the sprite side (0220DEAC)
    vis = { jumpF = nil, squash = 0, fallF = nil, hidden = false, puff = nil, step = 0 },
  }
  return m
end

-- opts: team (three Pokemon), rivals ({3}, {3}, {3}), names, onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, names = opts.names, t = 0, frame = 0, images = {} }, M)
  self.d = game.data.gen4_hgss_disc_catch
  self.mons = {}
  self.teams = {}
  for t = 0, 3 do
    local list = {}
    for k = 0, 2 do
      local mon = t == 0 and opts.team[k + 1] or (opts.rivals and opts.rivals[t] and opts.rivals[t][k + 1])
      local m = newMon(self, mon, starsOf(game, mon, t > 0), t, k)
      list[k] = m
      self.mons[m.id] = m
    end
    -- the team record (heap+0x15C + 0xE4 t): the stylus record and the points
    self.teams[t] = { id = t, mons = list, points = 0, sel = 0, holding = false,
      held = false, new = false, count = 0, last = 0, x = 0, y = 0, flag = 0 }
  end
  self.contact = {}
  for i = 0, 11 do self.contact[i] = {} end
  -- the disc manager (heap+0x4EC)
  self.discs = { [0] = { active = false, state = 0, x = 0, y = 0 }, { active = false, state = 0, x = 0, y = 0 } }
  self.throwIn, self.phase = 0, 0
  self.timer = CLOCK
  self.secs = math.floor((CLOCK + 30) / 30)
  -- the rivals' brains (022107F0: 4 - participants teams)
  self.ai = {}
  for t = 1, 3 do
    for k = 0, 2 do
      local a = { team = t, slot = k, think = 2 * t + 8 * k, again = 2 * t + 8 * k, chase = false, disc = 0, mode = 0, tx = 0, hx = 0, hy = 0 }
      self:rehome(a)
      self.ai[#self.ai + 1] = a
    end
  end
  self.touch = { down = false, new = false, x = 0, y = 0 }
  self.pad = { x = 128, y = 96, held = false, cycle = 0 }
  self.pops = {}
  self.shake = nil
  self.water = { n = 0, k = 0 }
  self.countdown = 90
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (0220E3F0)
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

local function feetOf(m) return m.x, m.y - m.wdy end

-- 0220D8C4: off the pier?
local function offPier(x, y)
  x, y = trunc(x), trunc(y)
  return x < 8 or x >= 0xF8 or y < 8 or y >= 0xB4
end

-- 0220D6CC: the four quarters (1 up 2 down 3 left 4 right)
local function quarter(dx, dy)
  local a = math.atan2(dy, dx) % (2 * math.pi)
  local q = a / (2 * math.pi) * 0x10000
  if q <= 0x2000 or q >= 0xE000 then return 4 end
  if q < 0x6000 then return 2 end
  if q <= 0xA000 then return 3 end
  return 1
end

-- 0220D630: the stylus (or a rival) asks for a jump
function M:jump(m)
  if m.jumpStars ~= 0 then
    m.jumps = m.jumps + 1
    m.timer = 2 * m.J
    m.state = 1
  end
  m.flash = 10
end

-- 0220DAA0: the nearest of team t's three within 80 px of (x, y), or nil
function M:nearest(t, x, y)
  local best, bd = nil, 1 / 0
  for k = 0, 2 do
    local m = self.teams[t].mons[k]
    local d = len(x - m.x, y - m.y)
    if d < GRAB_R and d < bd then best, bd = k, d end
  end
  return best
end

-- 0220F03C: the team's stylus record from the touch
function M:readTouch(tm, down, x, y)
  if down then
    if tm.held then tm.new = false else tm.new, tm.held = true, true end
    tm.x, tm.y = math.floor(x), math.floor(y)
    tm.count = tm.count + 1
  else
    if tm.held then tm.last = tm.count end
    tm.count, tm.new, tm.held = 0, false, false
  end
end

-- 0220F8C8: the stylus on team tm
function M:stepStylus(tm, wasHeld)
  tm.mons[tm.sel].dragged = false
  if tm.new then
    local k = self:nearest(tm.id, tm.x, tm.y)
    if k then tm.holding, tm.sel = true, k end
  elseif tm.held then
    if tm.holding then
      local m = tm.mons[tm.sel]
      if m.state == 3 then
        tm.holding = false
      elseif math.abs(tm.x - trunc(m.x)) > 8 or math.abs(tm.y - trunc(m.y)) > 8 then
        m.tx, m.ty, m.dragged = tm.x, tm.y, true
        m.dragOut = offPier(tm.x, tm.y - m.wdy)
      end
    end
  else
    if tm.holding and wasHeld then
      local m = tm.mons[tm.sel]
      local k = self:nearest(tm.id, tm.x, tm.y)
      if m.state == 2 and k == tm.sel and tm.last <= TAP_FRAMES then self:jump(m) end
    end
    tm.holding = false
  end
end

-- 0220D744: walking / being knocked
function M:move(m)
  local dx, dy = m.tx - m.x, m.ty - m.y
  local dist = len(dx, dy)
  m.moving = dist > 0
  if m.knocked then
    local n = len(m.kx, m.ky)
    local fx, fy = 0, 0
    if n > 0 then fx, fy = math.abs(FRICTION * m.kx / n), math.abs(FRICTION * m.ky / n) end
    if m.dragged then
      local p = m.power / 100
      fx, fy = fx + math.abs(p * m.lx), fy + math.abs(p * m.ly)
    end
    -- 0220E890: each component towards 0 by the friction
    local function slow(v, f)
      if v == 0 then return 0 end
      if math.abs(v) < f then return 0 end
      return v - (v > 0 and f or -f)
    end
    m.kx, m.ky = slow(m.kx, fx), slow(m.ky, fy)
    m.x, m.y = m.x + m.kx, m.y + m.ky
    m.tx, m.ty = m.x, m.y
    if m.kx ~= 0 or m.ky ~= 0 then return end
    m.knocked = false
  end
  if m.moving then
    local ux, uy = dx / dist, dy / dist
    if not m.knocked then m.face = quarter(ux, uy) end
    if dist <= m.speed then
      m.x, m.y = m.x + dx, m.y + dy
    else
      m.x, m.y = m.x + ux * m.speed, m.y + uy * m.speed
    end
    m.lx, m.ly = ux, uy
  end
end

-- 0220D910: back at its own spot
function M:respawn(m)
  local s = spawnOf(self, m.team, m.slot)
  m.x, m.y = s[1], s[2] + m.wdy
  m.tx, m.ty = m.x, m.y
  m.kx, m.ky, m.face, m.knocked = 0, 0, 2, false
end

-- 0220D9A4: one Pokemon's frame
function M:stepMon(m)
  if m.state == 4 then
    m.state = 2
  elseif m.state == 3 then
    m.fallT = m.fallT - 1
    if m.fallT <= 0 then
      self:respawn(m)
      m.state = 4
    end
  elseif m.state == 2 then
    self:move(m)
    if offPier(feetOf(m)) then
      m.falls, m.fell = m.falls + 1, true
      if m.dragOut then m.impede = (m.impede or 0) + 1 end   -- kind 8 (0220D9A4)
      m.dragOut = false
      m.fallT, m.state = FALL_FRAMES, 3
    end
  elseif m.state == 1 then
    m.timer = m.timer - 1
    if m.timer <= 0 then m.timer, m.state = 0, 2 end
    self:move(m)
  end
end

-- 0220F710: the bumps
function M:bumps()
  for i = 0, 11 do
    local a = self.mons[i]
    for j = i + 1, 11 do
      local b = self.mons[j]
      local fa, fb = a.state == 1 or a.state == 2, b.state == 1 or b.state == 2
      local touching = false
      if fa and fb then
        local ax, ay = feetOf(a)
        local bx, by = feetOf(b)
        touching = len(ax - bx, (ay - a.yoff) - (by - b.yoff)) <= a.radius + b.radius
      end
      if touching and not self.contact[i][j] then
        self.contact[i][j] = true
        local dx, dy = a.x - b.x, a.y - b.y
        local n = len(dx, dy)
        if n > 0 then dx, dy = dx / n, dy / n else dx, dy = 0, 0 end
        local pb = b.power
        if not a.tall then pb = trunc(pb * 4096 * 6 / 5) / 4096 end
        a.kx, a.ky = pb * dx + a.lx, pb * dy + a.ly
        local pa = a.power
        if not b.tall then pa = trunc(pa * 4096 * 6 / 5) / 4096 end
        b.kx, b.ky = -(pa * dx + b.lx), -(pa * dy + b.ly)
        a.kx, a.ky = clamp(a.kx, -KNOCK_MAX, KNOCK_MAX), clamp(a.ky, -KNOCK_MAX, KNOCK_MAX)
        b.kx, b.ky = clamp(b.kx, -KNOCK_MAX, KNOCK_MAX), clamp(b.ky, -KNOCK_MAX, KNOCK_MAX)
        b.face = quarter(dx, dy)
        a.knocked, b.knocked = true, true
      elseif not touching then
        self.contact[i][j] = false
      end
    end
  end
end

-- 0220FF88: a new disc when one is free
function M:launch()
  local k = 3
  for i = 0, 3 do
    if (self.d.phases[i] or self.d.phases[tostring(i)] or 0) <= self.secs then k = i; break end
  end
  self.phase = k
  self.throwIn = (k == 0 or k == 2) and 30 or 0
  local speed = k < 3 and 4 or (rand(2) + 1) * 4
  local n = k == 0 and 1 or 2
  for i = 0, n - 1 do
    local d = self.discs[i]
    if not d.active then
      -- 0220FB98
      d.active, d.state, d.x, d.y, d.t = true, 1, 0, 0, 0
      d.idx, d.line, d.speed = i, rand(15), speed
      d.shown = 0
      return
    end
  end
end

-- 0220FBEC: who catches disc d now (team, slot, feet x, y) or nil
function M:catcher(d)
  if d.y < SUB_Y then return nil end
  local dy = d.y - SUB_Y
  for i = 0, 11 do
    local m = self.mons[i]
    if m.state == 1 then
      local fx, fy = feetOf(m)
      fx, fy = trunc(fx), trunc(fy)
      if len(fx - d.x, fy - dy) <= m.radius + 14 then return m, fx, fy end
    end
  end
  return nil
end

-- 0220FE38: one disc's frame
function M:stepDisc(d)
  if not d.active then return end
  if d.state == 1 then
    local m, fx, fy = self:catcher(d)
    if m then
      -- 0220FD28
      d.state = M.band(fx, fy)
      local tm = self.teams[m.team]
      tm.points = math.min(200, tm.points + STATE_PTS[d.state])
      d.team = m.team
      m.catches = m.catches + 1
      d.t = 0
      d.caught = { m = m, x = d.x, y = d.y }
    elseif d.y >= DISC_END then
      d.y, d.state = 0, 2
    else
      d.y = d.y + d.speed
      d.x = M.lineX(d.y, d.line)
    end
  elseif d.state == 2 then
    d.y = d.y + d.speed
    if d.y >= 0x30 then d.active, d.state = false, 0 end
  elseif d.state >= 3 then
    d.t = d.t + 1
    if d.t >= CAUGHT_FRAMES then d.active, d.state = false, 0 end
  end
end

-- 02210030
function M:stepDiscs()
  if self.throwIn == 0 then self:launch() else self.throwIn = self.throwIn - 1 end
  for i = 0, 1 do self:stepDisc(self.discs[i]) end
end

-- ---------------------------------------------------------------- rivals --

-- 0221090C: a new home
function M:rehome(a)
  local rows = self.d.aiRows and (self.d.aiRows[a.slot] or self.d.aiRows[tostring(a.slot)]) or { 3, 5 }
  a.hy = (rows[1] + rand(rows[2])) * 8
  local s = spawnOf(self, a.team, a.slot)
  a.hx = s[1] + (rand(5) - 2) * 8
  a.chase, a.mode = false, 0
end

-- 02210BD0: disc d within radius + r of rival a's Pokemon (world point)
function M:discNear(a, i, r)
  local d = self.discs[i]
  if d.y < SUB_Y then return false end
  local m = self.teams[a.team].mons[a.slot]
  local dx, dy = math.abs(trunc(m.x) - d.x), math.abs(trunc(m.y) - (d.y - SUB_Y))
  local rr = m.radius + r
  return rr * rr >= dx * dx + dy * dy
end

-- 022109D8: a rival thinks
function M:think(a)
  if a.mode == 0 then
    a.tx = a.hx
    for i = 0, 1 do
      if self.discs[i].active and self:discNear(a, i, 0x38) then
        a.disc, a.chase, a.mode = i, true, 1
      end
    end
  elseif a.chase then
    local d = self.discs[a.disc]
    if d.active then
      a.tx = M.lineX(a.hy + SUB_Y, d.line)
    else
      a.chase, a.mode = false, 0
    end
  end
  local m = self.teams[a.team].mons[a.slot]
  m.tx, m.ty, m.dragged = a.tx, a.hy, true
end

-- 02210858 / 02210AE0: the rivals' frame
function M:stepAi()
  local total = 0
  for t = 0, 3 do total = total + (self.teams[t].points % 256) end
  local avg = math.floor(total / 4)
  local jumpPct = self.d.aiJump or { [0] = 3, 6, 36 }
  for _, a in ipairs(self.ai) do
    -- the cartridge's loop index (0..2), not the rival's team (1..3)
    local pts = self.teams[a.team - 1].points % 256
    local m = self.teams[a.team].mons[a.slot]
    if m.state == 1 or m.state == 2 then
      a.again = a.again - 1
      if a.again == 0 then
        self:rehome(a)
        a.again = 90
      end
      a.think = a.think - 1
      if a.think == 0 then
        self:think(a)
        a.think = 20
      end
      if a.chase and self:discNear(a, a.disc, 0x10) then
        local r = rand(100)
        local cut = (avg + 20 >= pts) and (jumpPct[a.slot] or jumpPct[tostring(a.slot)] or 0) or 0
        if r < cut then self:jump(m) end
      end
    end
  end
end

-- ---------------------------------------------------------------- a frame --

function M:step()
  self.frame = self.frame + 1
  if self.timer > 0 then
    self.timer = self.timer - 1
    self.secs = math.floor((self.timer + 30) / 30)
  else
    self.secs = 0
  end
  local me = self.teams[0]
  local wasHeld = me.held
  self:readTouch(me, self.touch.down, self.touch.x, self.touch.y)
  self.touch.new = false
  if self.touch.upAfter then self.touch.down, self.touch.upAfter = false, false end
  self:stepAi()
  self:stepDiscs()
  for t = 0, 3 do
    local tm = self.teams[t]
    if t == 0 then self:stepStylus(tm, wasHeld) else tm.mons[tm.sel].dragged = false end
    for k = 0, 2 do self:stepMon(tm.mons[k]) end
  end
  self:bumps()
  if self.timer <= 0 and not self.over then
    self.over = 90
    if self.cd then self.cd:startFinish(Rec.isNew(self.game, 4, self.teams[0].points % 256)) end
  end
  self:react()
end

-- 0220DC7C / 0220DEAC / 02210390: sounds and the sprites' own state
function M:react()
  local w = self.water
  w.n = w.n + 1
  if w.n >= 4 then w.n, w.k = 0, (w.k + 1) % 6 end
  for i = 0, 1 do
    local d = self.discs[i]
    local st = d.active and d.state or 0
    if (d.shown or 0) == 0 and st == 1 then se(self, SE.throw) end
    if st >= 3 and (d.shown or 0) < 3 then
      se(self, SE.catch)
      self.pops[#self.pops + 1] = { x = d.x, y = d.y - SUB_Y - 40, state = st, team = d.team, t = 0 }
      if d.team == 0 then
        self.shake = { a = 4, c = 4, flip = false }
        if STATE_PTS[st] ~= 1 then se(self, SE.scored) end
      end
      self.teams[d.team].flag = 28
    end
    d.shown = st
    d.spin = ((d.spin or 0) + 10) % 65536
  end
  for t = 0, 3 do
    local tm = self.teams[t]
    if tm.flag > 0 then tm.flag = tm.flag - 1 end
  end
  for i = 0, 11 do
    local m = self.mons[i]
    local v = m.vis
    local flag = m.flash > 0
    if m.flash > 0 then m.flash = m.flash - 1 end
    local fallen = m.state == 3
    if fallen and not v.wasFallen then
      v.fallF, v.jumpF, v.squash = 0, nil, 0
      se(self, SE.fall)
    elseif not fallen and v.wasFallen then
      v.fallF, v.hidden = nil, false
      v.puff = 0
      se(self, SE.back)
    end
    v.wasFallen = fallen
    if v.fallF then
      v.fallF = v.fallF + 1
      if v.fallF >= 6 then v.hidden = true end
    else
      -- the squash plays once a request (bit 17 stays until the flag is
      -- gone); the jump arc again if the flag outlasts it
      if flag and not v.jumpF and not v.failed then
        if m.team == 0 then se(self, m.jumpStars == 0 and SE.nojump or SE.jump) end
        if m.jumpStars == 0 then v.squash, v.failed = 4, true else v.jumpF = 0 end
      end
      if not flag then v.failed = false end
      if v.jumpF then
        v.jumpF = v.jumpF + 1
        if v.jumpF > 2 * m.J then v.jumpF = nil end
      end
      if v.squash > 0 then v.squash = v.squash - 1 end
    end
    if v.puff then
      v.puff = v.puff + 1
      if v.puff > 30 then v.puff = nil end
    end
    if m.moving or m.state == 1 then v.step = v.step + 1 end
  end
  for k = #self.pops, 1, -1 do
    local p = self.pops[k]
    p.t = p.t + 1
    if p.t > CAUGHT_FRAMES then table.remove(self.pops, k) end
  end
  -- 0220D360: the touch screen's shake
  local s = self.shake
  if s then
    s.off = s.flip and -s.a or s.a
    if s.c % 2 == 1 then s.a = s.a - 1 end
    s.flip = not s.flip
    s.c = s.c - 1
    if s.c < 0 then self.shake = nil end
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

local function byte(v) return math.max(0, math.min(255, math.floor(v))) end

function M:touchpressed(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if not px then return false end
  local tc = self.touch
  tc.down, tc.new, tc.x, tc.y = true, true, byte(px), byte(py)
  return true
end
function M:touchmoved(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if px and self.touch.down then self.touch.x, self.touch.y = byte(px), byte(py) end
  return true
end
function M:touchreleased(_, x, y)
  -- the record keeps the last HELD point; a touch let go before a logic
  -- frame saw it is let go the frame after
  if self.touch.new and not self.teams[0].held then self.touch.upAfter = true else self.touch.down = false end
  return true
end

-- PAD / KEYS (not the cartridge's): a cursor stands in for the stylus --
-- the D-pad moves it, A held is the stylus down (a short press on one of
-- ours = a tap = a jump), B moves the cursor to the next of ours, X makes the
-- one under the cursor jump (a tap); SELECT / L shows the top screen
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
    pd.cycle = (pd.cycle + 1) % 3
    local m = self.teams[0].mons[pd.cycle]
    pd.x, pd.y = math.floor(m.x), math.floor(m.y)
  end
  local tc = self.touch
  if input:wasPressed("x") and not tc.down then
    local k = self:nearest(0, pd.x, pd.y)
    if k then
      local m = self.teams[0].mons[k]
      tc.down, tc.new, tc.x, tc.y, tc.upAfter = true, true, byte(m.x), byte(m.y), true
    end
    return
  end
  local a = input:isDown("a")
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
    -- the FINISH (021E667C, 0220E2DC state 1)
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

-- ov96_0221A69C: Athlete Points from the team's points
function M.athletePoints(p)
  local f = p * 0.08
  local v = math.floor(150 - 120 / (1 + f))
  if v > 200 then v = 200 end
  return math.max(0, v)
end

-- ov96_0220E394 (field5E0 = the team's points) and the AP formula
function M:finish()
  if self.done then return end
  self.done = true
  local pts, stats = {}, {}
  for t = 0, 3 do
    local tm = self.teams[t]
    pts[t + 1] = M.athletePoints(tm.points)
    stats[t + 1] = {}
    for k = 0, 2 do
      local m = tm.mons[k]
      stats[t + 1][k + 1] = { miss = m.fell, score = m.catches, jump = m.jumps, dash = 0, hit = 0, fail = m.falls,
        fall = m.falls, impede = m.impede or 0 }   -- kinds 5 / 8 (5 and 1 come together)
    end
  end
  self.game.stack:pop()
  if self.onDone then
    self.onDone({ points = pts, total = self.teams[0].points, stats = stats, record = self.teams[0].points })
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

function M:sprite(key, x, y, sx, sy)
  local img, rec = self:img(key)
  if not img then return false end
  local ox = type(rec) == "table" and tonumber(rec.originX) or 0
  local oy = type(rec) == "table" and tonumber(rec.originY) or 0
  sx = sx or 1
  sy = sy or sx
  love.graphics.draw(img, math.floor(x + ox * sx), math.floor(y + oy * sy), 0, sx, sy)
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
    if not ok then ok, img = pcall(love.graphics.newImage, path) end
    self.monImgs[path] = ok and img or false
    if self.monImgs[path] then self.monImgs[path]:setFilter("nearest", "nearest") end
  end
  return self.monImgs[path] or nil
end

-- the walking Pokemon (gen4_follow_mon), or its icon, centred on its world
-- point (cx, cy), scaled (sx, sy)
function M:walker(m, cx, cy, sx, sy)
  local mon = m.mon
  if not mon then return end
  local g = love.graphics
  local data = self.game.data
  local sheet = self:sheetOf(mon)
  local path = sheet and ((mon.shiny or mon.isShiny) and sheet.shiny or sheet.normal)
  local img = type(path) == "string" and cachedImage(self, path)
  sx, sy = sx or 1, sy or sx or 1
  local step = m.vis.step
  if img then
    local fw, fh = tonumber(sheet.frameWidth) or 32, tonumber(sheet.frameHeight) or 32
    local iw, ih = img:getDimensions()
    local base = ({ up = 0, down = 2, left = 4, right = 6 })[FACES[m.face] or "down"] or 2
    local f = base + (math.floor(step / 4) % 2)
    if (f + 1) * fh > ih then f = 0 end
    g.draw(img, g.newQuad(0, f * fh, fw, fh, iw, ih), math.floor(cx - fw / 2 * sx), math.floor(cy - fh / 2 * sy), 0, sx, sy)
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
  g.draw(icon, g.newQuad(0, (math.floor(step / 4) % frames) * fh, iw, fh, iw, ih),
    math.floor(cx - iw / 2 * sx), math.floor(cy - fh / 2 * sy), 0, sx, sy)
end

-- 0220E8C0: the jump's lift (px, negative = up) and scale at frame f
function M:arc(m, f)
  local r = (f - m.J) * (f - m.J) - m.J * m.J
  if r == 0 then return 0, 1 end
  local h = trunc(m.lift * 4096 / 10)
  if h == 0 then return 0, 1 end
  local v = math.max(h * r, -0x18000)
  local s = 1 - trunc((v - 0x4000) / 100) / 4096
  return math.floor(v / 4096), s
end

-- the disc's scale (0220DC7C: 1.2 + sin / 18)
local function discScale(d)
  return 1.2 + trunc(math.floor(math.sin(math.rad((d.spin or 0) % 360)) * 4096) / 18) / 4096
end

-- the touch screen: the sea, the pier, the Pokemon, the discs
function M:drawBottom()
  local g = love.graphics
  g.setColor(0.1, 0.3, 0.8, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local off = self.shake and self.shake.off or 0
  g.push()
  g.translate(0, off)
  local water = self:img("water_" .. self.water.k)
  if water then g.draw(water, 0, 0) end
  local pier = self:img("pier")
  if pier then g.draw(pier, 0, -8) end
  -- the shadows of the discs on the pier
  for i = 0, 1 do
    local d = self.discs[i]
    if d.active and d.state <= 2 then
      local y = d.state == 2 and d.y + DISC_END or d.y
      if y >= SUB_Y then self:sprite("c_1_0", d.x, y - SUB_Y) end
    end
  end
  -- the Pokemon, back to front (0220DEAC sorts by y)
  local order = {}
  for i = 0, 11 do order[#order + 1] = self.mons[i] end
  table.sort(order, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.id < b.id end)
  for _, m in ipairs(order) do
    local v = m.vis
    local fx, fy = feetOf(m)
    if not v.hidden then
      local lift, sx, sy = 0, 1, 1
      if v.fallF then
        sx = 1 - 0.1 * v.fallF
        sy = sx
        if fy >= 0xB4 then fy = fy + (v.fallF) * 4 end
      elseif v.jumpF then
        lift, sx = self:arc(m, v.jumpF)
        sy = sx
      elseif v.squash > 0 then
        sy = ({ 1.0, 1.3, 1.0, 0.7 })[v.squash] or 1
      end
      if not v.fallF then
        local rgb = TEAM_RGB[m.team]
        g.setColor(rgb[1], rgb[2], rgb[3], 0.85)
        g.ellipse("line", math.floor(fx) + 0.5, math.floor(fy) + 0.5, m.radius + 2, (m.radius + 2) * 0.55)
        if m.team == 0 and self.teams[0].holding and self.teams[0].sel == m.slot then
          g.setColor(1, 1, 1, 0.9)
          g.ellipse("line", math.floor(fx) + 0.5, math.floor(fy) + 0.5, m.radius + 5, (m.radius + 5) * 0.55)
        end
        g.setColor(1, 1, 1, 1)
      end
      self:walker(m, fx, fy + m.wdy + lift, sx, sy)
    end
    if v.puff then self:sprite(self:anim("a", 5, v.puff, true), fx, fy + m.wdy) end
  end
  -- the discs over everything
  for i = 0, 1 do
    local d = self.discs[i]
    if d.active and d.state <= 2 then
      local y = d.state == 2 and d.y + DISC_END or d.y
      if y >= SUB_Y then self:sprite("c_0_0", d.x, y - SUB_Y - 40, discScale(d)) end
    end
  end
  -- the catches: the stars, and our points (0220DBE8)
  for _, p in ipairs(self.pops) do
    self:sprite(self:anim("a", 4, p.t, true), p.x, p.y)
    if p.team == 0 then self:sprite(self:anim("a", p.state - 3, p.t, true), p.x, p.y) end
  end
  g.pop()
  if self.showAim then
    local pd = self.pad
    g.setColor(1, 1, 1, 0.9)
    g.circle("line", pd.x + 0.5, pd.y + 0.5, 5)
    g.line(pd.x - 8, pd.y + 0.5, pd.x + 8, pd.y + 0.5)
    g.line(pd.x + 0.5, pd.y - 8, pd.x + 0.5, pd.y + 8)
    g.setColor(1, 1, 1, 1)
  end
  local Font = require("src.render.Font")
  if self.cd then
    -- the shared 3-2-1 / FINISH (main engine = this screen, surface at 0)
    self.cd:draw(0)
  elseif self.countdown > 0 then
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", 112, 84, 32, 24)
    g.setColor(1, 1, 1, 1)
    Font.draw(tostring(math.ceil(self.countdown / 30)), 124, 92)
  elseif self.over then
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", 88, 84, 80, 24)
    g.setColor(1, 1, 1, 1)
    Font.draw("FINISH!", 100, 92)
  end
end

-- the top screen: the sea, the buoys, the score boards, the clock, the
-- discs coming in
function M:drawTop()
  local g = love.graphics
  g.setColor(0.1, 0.3, 0.8, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local water = self:img("top_water_" .. self.water.k)
  if water then g.draw(water, 0, 0) end
  -- 0221075C: two rows of buoys fanning out from the thrower (sprite b 20)
  for k = 0, 11 do
    local y = 8 + 16 * k
    for side = 0, 1 do
      local x = 128 + (side == 0 and 1 or -1) * (k + 4) * 8
      self:sprite(self:anim("b", 20, self.t / 2 + k * 3), x, y)
    end
  end
  -- the discs and their shadows (sprite c 0 / 2)
  for i = 0, 1 do
    local d = self.discs[i]
    if d.active and d.state == 1 and d.y < SUB_Y then
      self:sprite("c_2_0", d.x, d.y)
      self:sprite("c_0_0", d.x, d.y - 40, discScale(d))
    end
  end
  local back = self:img("top_back")
  if back then g.draw(back, 0, 0) end
  -- 0221058C: our points in the big digits (BG6 tiles 0..11 x 0..7)
  local digits = self:img("digits")
  if digits then
    local iw, ih = digits:getDimensions()
    local v = math.min(999, self.teams[0].points)
    local ds = { math.floor(v / 100) % 10, math.floor(v / 10) % 10, v % 10 }
    for i, dg in ipairs(ds) do
      g.draw(digits, g.newQuad((dg % 5) * 32, math.floor(dg / 5) * 64, 32, 64, iw, ih), 32 * (i - 1), 0)
    end
  end
  local Font = require("src.render.Font")
  -- 0221069C: the four flags and names (ours at (8, 72), the rivals' down
  -- the RIVALS board, ov96_0221D14C), waving when the team scores (02210390)
  local spots = { [0] = { 8, 72 }, { 168, 16 }, { 168, 32 }, { 168, 48 } }
  local textAt = { [0] = { 24, 66 }, { 184, 10 }, { 184, 26 }, { 184, 42 } }
  for t = 0, 3 do
    local s = spots[t]
    local tm = self.teams[t]
    if tm.flag > 0 then self:sprite(self:anim("b", 4 + t, 28 - tm.flag), s[1], s[2])
    else self:sprite(("b_%d_0"):format(t), s[1], s[2]) end
    local name = self.names and self.names[t + 1]
    if type(name) == "string" then Font.draw(name, textAt[t][1], textAt[t][2]) end
  end
  -- 0221065C / 0221040C: the clock and its two digits (red <= 20 s, flashing <= 3 s)
  self:sprite("b_8_0", 210, 76)
  local secs = math.max(0, self.secs - 1)
  if self.countdown > 0 then secs = 60 end
  secs = secs % 100
  if secs <= 3 then g.setColor(1, 0.5, 0.5, (math.floor(self.t / 8) % 2 == 0) and 1 or 0.6)
  elseif secs <= 20 then g.setColor(1, 0.6, 0.6, 1) end
  self:sprite(("b_%d_0"):format(9 + math.floor(secs / 10)), 230, 76)
  self:sprite(("b_%d_0"):format(9 + secs % 10), 246, 76)
  g.setColor(1, 1, 1, 1)
  if self.countdown > 0 and not self.cd then
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", 112, 120, 32, 24)
    g.setColor(1, 1, 1, 1)
    Font.draw(tostring(math.ceil(self.countdown / 30)), 124, 128)
  end
end

function M:draw()
  self.showAim = self.game.input ~= nil and not self.padOff
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
