-- HEARTGOLD / SOULSILVER POKeATHLON: RING DROP (event 7, sub-app
-- ov96_0221A880 = { 02215AC4 init, 02215CD0 draw sprites, 02215CE8 results,
-- 02215D4C exit }, state table ov96_0221DC90 = { 02215984 fade in + 3-2-1,
-- 022159F0 play, 02215A70 end } -- the table sits in pokeathlon_data.c, not
-- in overlay_96.s; pokeheartgold asm/overlay_96.s 0x02215710..0x0221A57C;
-- the reading is written up in scratch_claude/athlon/NOTES.md, "## Ring
-- Drop"). Art and tables: `gen4_hgss_ring_drop`
-- (src/import/Gen4HgssPokeathlonRingDropArt.lua).
--
-- The game logic runs at 30 ticks a second (the clock shows timer / 30,
-- 0221768C); this module steps it every other frame.
--
-- A POKeMON'S POINT here is the cartridge's: its object's "ground" point
-- (A+0x2C), which the stylus and the switch corners work on; its feet (the
-- "world" point the ring test and the spawn points use, 021EB06C / 021EB0A4)
-- are s - (2 + class) px below it, s = 16 (32 for a big walker), class = the
-- performance row's byte 8 (021E6108); its body circle (021EB03C) is centred
-- s - yoff below it with the radius of /a/1/7/0 member 19 by the row's byte 6.
--
-- READ FROM CODE:
--   * four teams, one Pokemon each on the ring; team t starts at the world
--     point ov96_0221D6E4 (72,96) (184,96) (64,136) (192,136) (02217B84)
--   * THE CLOCK: 1800 ticks (heap+0x438 = 0x708, 60 s), one off a tick; at 0
--     everything stops (02215FC8: the sync word's bit 31); 0x6D7 at 450
--   * A POKeMON'S NUMBERS (0221918C, /a/1/7/0 MEMBER 9 by its course record):
--     tackle power [POWER]/10, tackle damage [5+POWER]/10, stamina
--     [10+STAMINA], walking speed [15+SPEED]/10 px a tick, stomp power and
--     damage both [25+JUMP]/10 ([20..24] are never read)
--   * THE STYLUS (02215FC8 / 022180CC): a touch within 80 px (021E6104) of
--     the Pokemon's point grabs it (not while switching or out); while held
--     it walks to the stylus at its speed (half below 30 stamina, 022187A8).
--     Let go within 7 ticks: moved <= 4 px = a JUMP (tap), moved > 12 px = a
--     TACKLE at the point let go (flick) -- only when idle (state 1) or new
--     (state 4), not fainted, not switching. The SWITCH button (x 104..159,
--     y 0..31, sprite at (128, 16), 02219460: 2 ready / 6 flashing below 30
--     stamina / 3 off / 4 pressed / 5 refused) works when idle within 64 px
--     of the team's corner ov96_0221D708 (48,48) (208,48) (32,144) (224,144)
--   * THE STATES (02218B1C): 1 idle, 2 knocked (stun), 3 out, 4 new (60
--     ticks), 5 tackle wind-up (4), 6 dash (6: velocity += dir x 0.7 a tick
--     from dir x 4.0, 02218DF8 / 02218F18), 7 recovery (16), 8 jump crouch
--     (5), 9 rise (10 ticks of ov96_0221D7D0 by JUMP stars: 1 star never
--     leaves the ground), 10 hang (10), 11 fall (8 px a tick, ov96_0221D69C),
--     12 landing (10). Gravity 2 px a tick a tick outside 9..11 (02218AF0).
--     A hit stops both for 4 ticks ([0x5D]).
--   * THE RING (02218934): the feet inside the trapezoid ov96_0221D6D4
--     (32,160) (48,64) (208,64) (224,160); checked when idle, knocked, new,
--     landing and at the end of a tackle (not during the dash). Out ->
--     02219030: 60 ticks away, then the NEXT Pokemon (stamina full for the
--     one that fell) comes in at the spawn point, new for 60 ticks
--   * HITS (02217E7C / 022178A0): two Pokemon (not out, new, hanging or
--     switching; heights within 5 px) whose body circles touch (+8 px for a
--     dasher) push each other apart along the line between them: by 3.0 x
--     the tackler's power from a dash (+1 point, its damage x 2 off the
--     other's stamina), by the stomp power from a fall (+2 points, the stomp
--     damage), else by 3.0; each axis held to 12 px a tick. The pushed one
--     is knocked: a dash or stomp stuns it for floor(10 x (1 - stamina /
--     max)) ticks (02218FFC) during which it slides unslowed, then it slows
--     1.0 px a tick each axis (0.7 after a plain bump). Who pushed it is
--     remembered until it stops (a chain passes the credit on).
--   * STAMINA (02217FD0): 0 = fainted 60 ticks (cannot walk, then 20);
--     the two on the bench get 0.2 a tick back
--   * POINTS: tackle hit 1, stomp 2, knocking one out 10 (to whoever pushed
--     it last), falling out alone -10 (not below 0); 200 at most
--   * SWITCHING (0221910C / 02216770 / 02216934 / 02216A54): out goes a Poke
--     Ball (1 + 10 ticks up), the top screen's swap, the next Pokemon at the
--     spawn point, the ball drops in (1 + 10 ticks), new for 60 ticks
--   * THE RIVALS (0221A400 / 0221A08C / 0221A3AC / 0221A314): every 3 ticks
--     after their wait: tackle the best of those within 32 px (+ facing it:
--     80 %, else 10 %) or within 48 px facing it (50 %); else jump (5 % with
--     one within 48 px + 5 / 10 / 30 % for 1 / 2 / 3 within 32 px); else 60 %
--     chase (60 % the one with the least stamina), 20 % wait 10 ticks, 20 %
--     walk to a random point; then switch at odds by stamina (< 10 % 100,
--     < 20 % 70, < 30 % 50, < 40 % 30, < 50 % 10) -- walking to its corner
--     ov96_0221D98C first
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 02215AC4 puts them on the main
--     engine at y offset 0 (021E61D8 r1, its SpriteSystem list), the touch
--     screen here (gSystem.screensFlipped = 1, main surface at 0); 02215984
--     runs the countdown after the fade, 022159F0 the finish after play
-- Scoring: Athlete Points = floor(points x 1.5), at most 200 (ov96_0221A700,
-- the course's AP table) -- Bulbapedia agrees. Course counters (021E8228):
-- 1 a miss (out or fainted), 2 a jump (only with JUMP stars), 3 a score, 4 a
-- hit, 5 out, 7 a switch, 8 out alone -> res.stats miss / fail = 1, jump,
-- hit, score = the number of times it scored (the counter's +1, not points).
--
-- THE RECORD (READ FROM CODE; src/pokemon/HgssPokeathlonRecords.lua): at
-- time up 02216200 hands ov96_021E8318 the team's score as the top screen
-- keeps it (0221978C: +0xC2, cut to a byte) for NEW RECORD! (021E839C,
-- higher is better); the end state's field_5E0 (02215A70, score & 0xFFF,
-- at most 200) is what the course's end saves.
--
-- STAND-INS, said so: during the FINISH the field stands still (the
-- cartridge runs 02215FC8 on under it); without `gen4_hgss_athlon_common`
-- the 3-2-1 and the finish are text; the top screen's swap animation
-- (02219794) is taken as 20 ticks (the rivals' 02219940 is 13); the
-- walkers are gen4_follow_mon sheets (icons when absent) with their
-- object's [0x28] taken as 0, scaled by depth (1.2 - (160 - y) x 12 / 4096,
-- 02216C38) but not squashed in the wind-up / crouch; team colours are
-- drawn as ellipses under them (the shadow sprites are not read); the
-- clock's digits are text (the shared digit sprites 021EA374 are not read);
-- the top screen's front pictures are icons and its name windows plain
-- text; screen shake is 4 px / 10 ticks (tackle) and 10 px / 15 ticks
-- (stomp) on the touch screen by eye (02215710 not stepped exactly).

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local TIME = 1800                         -- heap+0x438 = 0x708
local TOUCH_R = 0x50                      -- ov96_021E6104
local TAP_TICKS = 7                       -- 022180CC: a tap / flick within 7 ticks
local TAP_DIST, FLICK_DIST = 4, 12        -- 0x4000 / 0xC000
local TIRED = 30                          -- 0x1E000: half speed, the button flashes
local BENCH_RECOVER = 0.2                 -- 0x444CC000 = 819.2 / 4096
local FAINT_TICKS, FAINT_BACK = 60, 20    -- 02217FD0
local OUT_TICKS, NEW_TICKS = 60, 60       -- 02219030 / 02218578(4)
local DASH_START, DASH_ACCEL = 4.0, 0.7   -- 02218DF8 / 02218F18 (0xB33)
local KNOCK_CAP = 12                      -- 02215958(0xC000)
local GRAVITY = 2                         -- 02218AF0
local CORNER_R = 64
local SWAP_TICKS, SWAP_TICKS_CPU = 20, 13 -- 02219794 (stand-in) / 02219940
-- the jump's height a tick by JUMP stars (ov96_0221D7D0, 10 a row) and its
-- fall a tick (ov96_0221D69C)
local RISE = {
  [0] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 8, 14, 18, 20, 21, 22, 22, 23, 23, 24 },
  { 10, 18, 24, 28, 29, 30, 30, 31, 31, 32 },
  { 10, 19, 27, 33, 37, 38, 38, 39, 39, 40 },
  { 10, 19, 27, 34, 40, 44, 45, 46, 47, 48 },
}
local FALL = { [0] = 0, 8, 8, 8, 8 }
-- team t's spawn (world), switch corner (ground), the rivals' corner walk
local SPAWN = { { 72, 96 }, { 184, 96 }, { 64, 136 }, { 192, 136 } }       -- ov96_0221D6E4
local CORNER = { { 48, 48 }, { 208, 48 }, { 32, 144 }, { 224, 144 } }      -- ov96_0221D708
local AI_CORNER = { { 48, 64 }, { 208, 64 }, { 32, 160 }, { 224, 160 } }   -- ov96_0221D98C
local RING = { { 32, 160 }, { 48, 64 }, { 208, 64 }, { 224, 160 } }        -- ov96_0221D6D4
local AI_TACKLE = { [0] = 0, 10, 50, 80 }                                  -- ov96_0221D97C
local AI_JUMP = { 5, 10, 30 }                                              -- ov96_0221D978
local SE = { hit = 0x8D0, stomp = 0x8D2, bump = 0x8D4, tackle = 0x8D1, tackleRival = 0x8D5,
  jump = 0x60A, jumpFlat = 0x5F3, land = 0x8D3, out = 0x89E, ballOut = 0x8B4, ballIn = 0x8B5,
  back = 0x8B6, button = 0x89B, refused = 0x89C, warn = 0x6D7, dizzy = 0x890 }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local POWER, STAMINA, JUMP, SPEED = 0, 1, 3, 4
local UP, DOWN, LEFT, RIGHT = 1, 2, 3, 4
local TEAM_RGB = { { 0.95, 0.3, 0.4 }, { 0.35, 0.5, 0.95 }, { 0.3, 0.8, 0.35 }, { 0.95, 0.8, 0.2 } }

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function mag(x, y) return math.sqrt(x * x + y * y) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_ring_drop
  return type(d) == "table" and d.params ~= nil and d.ring ~= nil
end

-- the performance row's raw bytes (byte 6 the size class, byte 8 the class
-- -- ov96_021E6138 / 021E6108)
local function rawRow(data, mon)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local rows = data and data.gen4_hgss_performance
  if type(rows) ~= "table" or not mon then return nil end
  local sp = tonumber(mon.species) or tonumber(tostring(mon.species or ""):match("(%d+)%s*$")) or 0
  local idx = P.ARC_IDX[sp]
  if not idx then return nil end
  local raw = rows[idx + (tonumber(mon.form) or 0)] or rows[idx]
  return type(raw) == "table" and raw or nil
end

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

local function clampClass(v) v = tonumber(v) or 2; if v < 1 or v > 3 then v = 2 end; return v end

-- 0221918C: a Pokemon's numbers from its stars; 02217AE4 / 02217B84 its body
function M:monParams(mon, rival)
  local p, st = self.d.params, starsOf(self.game, mon, rival)
  local raw = rawRow(self.game.data, mon)
  local sizeClass = clampClass(raw and raw[7])
  local class = clampClass(raw and raw[9])
  local size = (self.d.sizes and self.d.sizes[sizeClass]) or { 10, 10 }
  local mp = {
    mon = mon, power = p[st[POWER]] / 10, dmg = p[5 + st[POWER]] / 10, max = p[10 + st[STAMINA]],
    speed = p[15 + st[SPEED]] / 10, jumpK = p[25 + st[JUMP]] / 10, jumpD = p[25 + st[JUMP]] / 10,
    jumpStars = st[JUMP], yoff = size[1], radius = size[2], o10 = 2 + class, s = self:bigWalker(mon) and 32 or 16,
    misses = 0, scores = 0, jumps = 0, hits = 0,
  }
  mp.stamina = mp.max
  return mp
end

-- opts: team (three Pokemon), rivals ({3 teams of 3}), names, onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, ticks = 0, images = {} }, M)
  self.d = game.data.gen4_hgss_ring_drop
  self.names = opts.names or {}
  self.teams = {}
  for t = 1, 4 do
    local mons = t == 1 and opts.team or (opts.rivals and opts.rivals[t - 1]) or {}
    local a = {
      index = t, cpu = t > 1, cur = 1, members = {}, state = 1, prev = 0, facing = DOWN,
      x = 0, y = 0, tx = 0, ty = 0, vx = 0, vy = 0, dx = 0, dy = 0, z = 0, vz = 0,
      score = 0, knocked = false, fainted = false, tap = false, flick = false, switching = false,
      phase = 0, cmd = 0, t58 = 0, t59 = 0, t5a = 0, t5b = 0, t5c = 0, t5d = 0, t5e = NEW_TICKS,
      button = 3, latch = {}, fx = 0,
      vis = { phase = 0, step = 0, n = 0, falling = false, fallT = 0, scale = 1, lastState = 4, wave = nil, waveT = 0 },
      ai = t > 1 and { wait = 0, swCnt = 0, think = 0, chase = -1, chasing = false, goSwitch = false } or nil,
    }
    for m = 1, 3 do a.members[m] = self:monParams(mons[m], t > 1) end
    self.teams[t] = a
    self:respawn(a)
    self:setState(a, 1)
  end
  self.timer = TIME
  self.rec = { held = false, new = false, count = 0, dur = 0, x = 0, y = 0, sx = 0, sy = 0, grabbed = false }
  self.touch = { down = false, x = 0, y = 0, latched = false }
  self.fxList = {}
  self.shake = nil
  self.countdown = 180
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (02215AC4)
  if CD.available(game) then self.cd = CD.new(game, 0) end
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

function M:member(a) return a.members[a.cur] end

-- ---------------------------------------------------------------- geometry --

-- 021EB06C: the ground point -> the feet; 021EB0A4 back
function M:feet(a)
  local mp = self:member(a)
  return a.x, a.y + mp.s - mp.o10
end

-- 021EB03C: the body circle
function M:body(a)
  local mp = self:member(a)
  local r = mp.radius
  if a.state == 6 then r = r + 8 end
  return a.x, a.y + mp.s - mp.yoff, r
end

-- 02218934: the feet outside the ring
function M:isOut(a)
  if a.x <= 0 or a.y <= 0 then return true end
  local wx, wy = self:feet(a)
  if wy < 64 or wy > 160 then return true end
  local p0, p1, p2, p3 = RING[1], RING[2], RING[3], RING[4]
  local left = (wx - p0[1]) * (p1[2] - p0[2]) / (p1[1] - p0[1]) + p0[2]
  local right = (wx - p2[1]) * (p3[2] - p2[2]) / (p3[1] - p2[1]) + p2[2]
  return not (wy >= left and wy >= right)
end

-- 022186CC: the way a direction points, by quarter-turns
local function facingOf(dx, dy)
  if dx == 0 and dy == 0 then return UP end
  local ang = math.atan2(dy, dx) / (2 * math.pi) * 65536
  if ang < 0 then ang = ang + 65536 end
  if ang <= 0x2000 or ang >= 0xE000 then return RIGHT end
  if ang > 0x2000 and ang < 0x6000 then return DOWN end
  if ang >= 0x6000 and ang <= 0xA000 then return LEFT end
  return UP
end
local FACE_VEC = { [UP] = { 0, -1 }, [DOWN] = { 0, 1 }, [LEFT] = { -1, 0 }, [RIGHT] = { 1, 0 } }

local function normalize(x, y)
  local n = mag(x, y)
  if n == 0 then return 0, 0 end
  return x / n, y / n
end

-- ------------------------------------------------------------------ rules --

-- 02218578
function M:setState(a, s)
  a.t5e = (s == 4) and NEW_TICKS or 0
  if s == 7 then a.t59 = 16 end
  a.state = s
end

-- 02218A68: in at the team's spawn point
function M:respawn(a)
  local sp = SPAWN[a.index]
  local mp = self:member(a)
  a.x, a.y = sp[1], sp[2] - mp.s + mp.o10
  a.tx, a.ty, a.vx, a.vy = a.x, a.y, 0, 0
  a.facing = DOWN
  a.knocked, a.tap, a.flick = false, false, false
end

-- 02219398: the next of the three
function M:nextMember(a)
  a.cur = a.cur % 3 + 1
end

-- 0221862C (02218688 + the corner): may it switch now?
function M:canAct(a)
  return not a.knocked and not a.fainted and not a.switching and a.state == 1
end
function M:canSwitch(a)
  if not self:canAct(a) then return false end
  local c = CORNER[a.index]
  return mag(a.x - c[1], a.y - c[2]) <= CORNER_R
end

-- 0221910C
function M:startSwitch(a)
  a.switching, a.phase = true, 1
  local sm = self:member(a)
  sm.switches = (sm.switches or 0) + 1   -- kind 7 (0221910C)
  a.tx, a.ty = a.x, a.y
end

-- 02218744: on the ring and in play
function M:active(a)
  return a.state ~= 10 and not a.switching and a.state ~= 4 and a.state ~= 3
end

-- 02219030: out of the ring
function M:fallOut(a)
  a.t5b, a.t58 = OUT_TICKS, 0
  local mp = self:member(a)
  mp.falls = (mp.falls or 0) + 1   -- kind 5 (02219030)
  if not a.attacker then
    mp.impede = (mp.impede or 0) + 1   -- kind 8: out alone
    a.score = math.max(0, a.score - 10)
  else
    local b = a.attacker
    b.score = math.min(200, b.score + 10)
    local bm = self:member(b)
    bm.scores = bm.scores + 1
    a.attacker = nil
  end
  mp.misses = mp.misses + 1
  self:setState(a, 3)
end

-- 02218F58: the jump
function M:jumpStart(a)
  a.tap, a.t5a = false, 5
  local mp = self:member(a)
  if mp.jumpStars ~= 0 then mp.jumps = mp.jumps + 1 end
  self:setState(a, 8)
end

-- 02218DF8: the tackle at a point
function M:tackleStart(a, px, py)
  a.flick = false
  a.dx, a.dy = normalize(px - a.x, py - a.y)
  a.vx, a.vy = a.dx * DASH_START, a.dy * DASH_START
  if a.vx ~= 0 or a.vy ~= 0 then
    a.facing = facingOf(a.dx, a.dy)
    a.t59 = 4
    self:setState(a, 5)
  end
end

-- 02215944: each axis towards 0 by its own amount
local function slow(v, by)
  if v == 0 then return 0 end
  if math.abs(v) < by then return 0 end
  return v - (v > 0 and by or -by)
end

-- 022187A8: sliding when knocked, else walking to the target
function M:move(a)
  local ddx, ddy = a.tx - a.x, a.ty - a.y
  local dist = mag(ddx, ddy)
  local mp = self:member(a)
  if a.knocked then
    local fr = (a.prev == 6 or a.prev == 9) and 1.0 or 0.7
    if a.t58 <= 0 then
      local nx, ny = normalize(a.vx, a.vy)
      a.vx, a.vy = slow(a.vx, math.abs(nx * fr)), slow(a.vy, math.abs(ny * fr))
    end
    a.x, a.y = a.x + a.vx, a.y + a.vy
    a.tx, a.ty = a.x, a.y
    if a.vx ~= 0 or a.vy ~= 0 then return end
    for j = 1, 4 do a.latch[j] = false end
    a.attacker, a.knocked = nil, false
  end
  if a.fainted or a.t58 > 0 or dist <= 0 then return end
  local nx, ny = normalize(ddx, ddy)
  if not a.knocked then a.facing = facingOf(nx, ny) end
  local speed = mp.speed
  if mp.stamina < TIRED then speed = speed / 2 end
  if dist <= speed then a.x, a.y = a.x + ddx, a.y + ddy
  else a.x, a.y = a.x + nx * speed, a.y + ny * speed end
  a.dx, a.dy = nx, ny
end

-- 02218B1C: one tick of a Pokemon
function M:stepMon(a)
  if a.t5d > 0 then
    a.t5d = a.t5d - 1
    if a.t5d > 0 then return end
  end
  local s = a.state
  if s <= 4 or s == 9 then self:move(a)
  elseif s == 6 then
    a.vx, a.vy = a.vx + a.dx * DASH_ACCEL, a.vy + a.dy * DASH_ACCEL
    a.x, a.y = a.x + a.vx, a.y + a.vy
  end
  local mp = self:member(a)
  s = a.state
  if s == 1 or s == 4 then
    if self:isOut(a) then self:fallOut(a)
    elseif s == 1 and a.knocked then -- nothing while sliding
    elseif a.tap then self:jumpStart(a)
    elseif a.flick then self:tackleStart(a, a.fx1, a.fy1)
    elseif s == 4 then
      a.t5e = a.t5e - 1
      if a.t5e <= 0 then self:setState(a, 1) end
    end
  elseif s == 2 then
    if self:isOut(a) then self:fallOut(a)
    else
      a.t58 = a.t58 - 1
      if a.t58 <= 0 then self:setState(a, 1) end
    end
  elseif s == 3 then
    a.t5b = a.t5b - 1
    if a.t5b <= 0 then
      -- 02218A50: the one that fell is rested, the next comes in
      mp.stamina = mp.max
      self:nextMember(a)
      self:respawn(a)
      self:setState(a, 4)
    end
  elseif s == 5 then
    a.t59 = a.t59 - 1
    if a.t59 <= 0 then a.t59 = 6; self:setState(a, 6) end
  elseif s == 6 then
    a.t59 = a.t59 - 1
    if a.t59 <= 0 then
      a.tx, a.ty, a.vx, a.vy = a.x, a.y, 0, 0
      self:setState(a, 7)
    end
  elseif s == 7 then
    a.t59 = a.t59 - 1
    if a.t59 <= 0 then
      -- 02218EB8
      a.vx, a.vy, a.tx, a.ty = 0, 0, a.x, a.y
      self:setState(a, 1)
      if self:isOut(a) then self:fallOut(a) end
    end
  elseif s == 8 then
    a.t5a = a.t5a - 1
    if a.t5a <= 0 then a.t5a = 0; self:setState(a, 9) end
  elseif s == 9 then
    local row = RISE[mp.jumpStars] or RISE[0]
    a.z = row[a.t5a + 1] or 0
    a.t5a = a.t5a + 1
    if a.t5a >= 10 then a.t5a = 10; self:setState(a, 10) end
  elseif s == 10 then
    a.t5a = a.t5a - 1
    if a.t5a <= 0 then a.t5a = 0; self:setState(a, 11) end
  elseif s == 11 then
    if a.z == 0 then
      -- 02218FD4: landed
      self:setState(a, 12)
      a.t5a, a.z, a.tx, a.ty = 10, 0, a.x, a.y
      if self:isOut(a) then self:fallOut(a) end
    else
      a.z = math.max(0, a.z - (FALL[mp.jumpStars] or 8))
    end
  elseif s == 12 then
    a.t5a = a.t5a - 1
    if a.t5a <= 0 then self:setState(a, 1) end
  end
  -- 02218AF0
  if a.state < 9 or a.state > 11 then
    if a.z <= 0 then a.vz = 0
    else
      a.z = math.max(0, a.z - a.vz)
      a.vz = a.vz + GRAVITY
    end
  end
end

-- 02218598: heights within 5 px and the body circles touching
function M:touching(a, b)
  if math.abs(a.z - b.z) > 5 then return false end
  local ax, ay, ar = self:body(a)
  local bx, by, br = self:body(b)
  return mag(ax - bx, ay - by) <= ar + br
end

-- 022178A0: `b` pushes `v` along (dx, dy)
function M:hit(v, b, dx, dy)
  if v.state == 11 then return false end
  local bm = self:member(b)
  local k, dmg
  local attack = b.state == 6 or b.state == 11
  if b.state == 6 then
    k, dmg = bm.power * 3, bm.dmg * 2
    b.score = math.min(200, b.score + 1)
  elseif b.state == 11 then
    k, dmg = bm.jumpK, bm.jumpD
    b.score = math.min(200, b.score + 2)
  else
    k = 3
  end
  if attack then bm.scores, bm.hits = bm.scores + 1, bm.hits + 1 end
  v.vx = math.max(-KNOCK_CAP, math.min(KNOCK_CAP, v.vx + dx * k))
  v.vy = math.max(-KNOCK_CAP, math.min(KNOCK_CAP, v.vy + dy * k))
  -- 02217868: the pusher faces it
  if not attack then b.facing = facingOf(-dx, -dy) end
  if attack then
    v.t5d, b.t5d = 4, 4
    local vm = self:member(v)
    vm.stamina = math.max(0, vm.stamina - dmg)
  end
  if not v.attacker or attack then
    v.attacker = b
    if b.attacker and b.attacker ~= v then v.attacker = b.attacker end
  end
  v.knocked, v.prev = true, b.state
  if attack then
    self:hitEffect(v, b, b.state == 6 and 1 or 2)
  else
    v.bump = true
  end
  return true
end

-- 02217E08: what a knock does to the one knocked
local function reaction(a)
  if not a.knocked then return 0 end
  local s, p = a.state, a.prev
  local hard = p == 11 or p == 6
  if s == 5 or s == 6 or s == 7 or s == 8 or s == 12 then
    if hard then return 3 elseif s == 6 then return 2 else return 1 end
  elseif s == 1 or s == 2 or s == 9 then
    return hard and 3 or 0
  end
  return 0
end

-- 02217DC8 / 02218FFC
function M:react(a, k)
  if k == 1 then self:setState(a, 1)
  elseif k == 2 then self:setState(a, 7); a.t59 = 1
  elseif k == 3 then
    local mp = self:member(a)
    local ratio = mp.max > 0 and mp.stamina / mp.max or 1
    a.t58 = math.max(0, math.floor(10 * (1 - ratio) - 3 / 4096))
    self:setState(a, 2)
  end
end

-- 02217E7C: every pair once
function M:collide()
  for i = 1, 4 do
    local a = self.teams[i]
    if self:active(a) and a.t5d <= 0 then
      for j = i + 1, 4 do
        local b = self.teams[j]
        if self:active(b) and self:touching(a, b) then
          if a.latch[j] and not a.knocked then a.latch[j] = false end
          if not a.latch[j] then
            local dx, dy = a.x - b.x, a.y - b.y
            if dx == 0 and dy == 0 then dx, dy = (rand(64) - 32) / 4096, (rand(64) - 32) / 4096 end
            dx, dy = normalize(dx, dy)
            local ri = self:hit(a, b, dx, dy)
            local rj = self:hit(b, a, -dx, -dy)
            local ki, kj = reaction(a), reaction(b)
            self:react(a, ki)
            self:react(b, kj)
            if ri or rj then a.latch[j] = true end
          end
        end
      end
    end
  end
end

-- 02217FD0: fainting, and the bench getting its breath back
function M:stamina()
  for _, a in ipairs(self.teams) do
    for m, mp in ipairs(a.members) do
      if m == a.cur then
        if a.fainted then
          a.t5c = a.t5c - 1
          if a.t5c <= 0 then
            mp.stamina = FAINT_BACK
            a.tx, a.ty = a.x, a.y
            a.fainted = false
          end
        elseif mp.stamina <= 0 then
          a.t5c, a.fainted, a.tap, a.flick = FAINT_TICKS, true, false, false
          mp.misses = mp.misses + 1
        end
      else
        mp.stamina = mp.stamina + BENCH_RECOVER
      end
      if mp.stamina > mp.max then mp.stamina = mp.max end
    end
  end
end

-- ------------------------------------------------------------------- AI --

-- 0221A08C: what a rival does next
function M:decide(a)
  local ai = a.ai
  local flags, near, mid = {}, 0, 0
  for j, b in ipairs(self.teams) do
    flags[j] = 0
    if b ~= a then
      local dx, dy = b.x - a.x, b.y - a.y
      local d = mag(dx, dy)
      local nx, ny = normalize(dx, dy)
      local aligned = facingOf(nx, ny) == a.facing
      if d <= 32 then
        flags[j] = aligned and 3 or 1
        near = near + 1
      elseif d <= 48 then
        if aligned then flags[j] = 2 end
        mid = mid + 1
      end
    end
  end
  local best, bestFlag = 1, 0
  for j = 1, 4 do
    if self.teams[j] ~= a and flags[j] > bestFlag then best, bestFlag = j, flags[j] end
  end
  if rand(100) < AI_TACKLE[bestFlag] then
    local b = self.teams[best]
    a.flick, a.fx1, a.fy1 = true, b.x, b.y
    ai.wait = 16
    return
  end
  local r = rand(100)
  local thr = (mid > 0 and 5 or 0) + (near > 0 and AI_JUMP[math.min(3, near)] or 0)
  if r < thr then
    a.tap = true
    ai.wait = 20
    return
  end
  r = rand(100)
  if r < 60 then
    local r4 = rand(100)
    if ai.chasing then return end
    local bestJ, prevJ, low = -1, -1, 999
    for j, b in ipairs(self.teams) do
      if b ~= a and b.state ~= 3 and b.state ~= 4 and not b.switching then
        local st = math.floor(self:member(b).stamina)
        if low > st then prevJ, bestJ, low = bestJ, j, st end
      end
    end
    ai.chase = (r4 < 60) and bestJ or prevJ
    if ai.chase ~= -1 then
      ai.chasing = true
      ai.wait = 0
    end
  elseif r < 80 then
    ai.wait = 10
  else
    a.tx, a.ty = 56 + rand(145), 72 + rand(80)
    ai.wait = 10
  end
end

-- 0221A3AC: switch at odds by stamina
function M:switchRoll(a)
  local mp = self:member(a)
  local pct = mp.max > 0 and math.floor(mp.stamina * 100 / mp.max) or 100
  local odds = 0
  if pct < 10 then odds = 100 elseif pct < 20 then odds = 70 elseif pct < 30 then odds = 50
  elseif pct < 40 then odds = 30 elseif pct < 50 then odds = 10 end
  return rand(100) < odds
end

-- 0221A400: one rival, one tick
function M:stepAI(a)
  local ai = a.ai
  if a.switching then return end
  if ai.chasing and not ai.goSwitch then
    local b = self.teams[ai.chase]
    if not b or b.state == 3 or b.switching or a.knocked then
      a.tx, a.ty = a.x, a.y
      ai.chasing = false
    else
      a.tx, a.ty = b.x, b.y
    end
  end
  if ai.goSwitch then
    if self:canAct(a) then
      -- 0221A314: to the corner, and switch there
      local c = AI_CORNER[a.index]
      a.tx, a.ty = c[1], c[2]
      local wx, wy = self:feet(a)
      if mag(wx - c[1], wy - c[2]) <= CORNER_R then
        self:startSwitch(a)
        ai.goSwitch = false
      end
    end
    return
  end
  ai.wait = ai.wait - 1
  if ai.wait > 0 then return end
  if ai.wait < 0 then ai.wait = 0 end
  ai.think = ai.think - 1
  if ai.think > 0 then return end
  ai.think = 3
  if not self:canAct(a) then return end
  self:decide(a)
  ai.swCnt = ai.swCnt - 1
  if ai.swCnt <= 0 then
    if self:switchRoll(a) then ai.goSwitch = true end
    ai.swCnt = 0
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
  self.touch.down, self.touch.x, self.touch.y, self.touch.latched = true, px, py, true
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

local function inButton(x, y) return x >= 0x68 and x < 0xA0 and y >= 0 and y < 0x20 end

-- 02215FC8: the touch record, sampled once a tick
function M:sampleTouch()
  local rec, tc = self.rec, self.touch
  local down = tc.down or tc.latched
  tc.latched = false
  rec.new = false
  if down then
    if not rec.held then
      rec.held, rec.new, rec.sx, rec.sy = true, true, tc.x, tc.y
    end
    rec.x, rec.y = tc.x, tc.y
    rec.count = rec.count + 1
  elseif rec.held then
    rec.held, rec.dur, rec.count, rec.released = false, rec.count, 0, true
  end
end

-- 022180CC's touch half for the player
function M:playerInput(a)
  local rec = self.rec
  if rec.new then
    if inButton(rec.x, rec.y) then
      if self:canSwitch(a) then self:startSwitch(a) end
    elseif not a.switching and a.state ~= 3 and mag(a.x - rec.x, a.y - rec.y) <= TOUCH_R then
      rec.grabbed = true
    end
  elseif rec.held then
    if rec.grabbed then
      if a.state == 3 then rec.grabbed = false
      elseif math.abs(rec.x - math.floor(a.x)) > 1 or math.abs(rec.y - math.floor(a.y)) > 1 then
        a.tx, a.ty = rec.x, rec.y
      end
    end
  elseif rec.released then
    rec.released = false
    if rec.grabbed and (a.state == 1 or a.state == 4) and not a.fainted and not a.switching then
      local moved = mag(rec.x - rec.sx, rec.y - rec.sy)
      if moved <= TAP_DIST then
        if rec.dur <= TAP_TICKS then a.tap, a.flick = true, false end
      elseif moved > FLICK_DIST and rec.dur <= TAP_TICKS then
        a.flick, a.tap, a.fx1, a.fy1 = true, false, rec.x, rec.y
      end
    end
    rec.grabbed = false
  end
end

-- pad / keyboard: arrows walk, A tackles the way it faces, B jumps, X / R
-- switch (in the corner)
function M:padInput(a)
  local input = self.game.input
  if not input then return end
  local dx = (input:isDown("right") and 1 or 0) - (input:isDown("left") and 1 or 0)
  local dy = (input:isDown("down") and 1 or 0) - (input:isDown("up") and 1 or 0)
  if (dx ~= 0 or dy ~= 0) and a.state ~= 3 and not a.switching then
    local nx, ny = normalize(dx, dy)
    a.tx, a.ty = a.x + nx * 16, a.y + ny * 16
    self.padFacing = facingOf(nx, ny)
  end
  local ok = (a.state == 1 or a.state == 4) and not a.fainted and not a.switching
  if self.padA and ok then
    local f = FACE_VEC[self.padFacing or a.facing] or FACE_VEC[DOWN]
    a.flick, a.tap, a.fx1, a.fy1 = true, false, a.x + f[1] * 32, a.y + f[2] * 32
  elseif self.padB and ok then
    a.tap, a.flick = true, false
  end
  if self.padX and self:canSwitch(a) then self:startSwitch(a) end
  self.padA, self.padB, self.padX = false, false, false
end

-- 02219460: the SWITCH button's look
function M:buttonState(a)
  local mp = self:member(a)
  local v
  if self:canSwitch(a) then v = (mp.stamina < TIRED) and 1 or 0 else v = 3 end
  local rec = self.rec
  if rec.new and inButton(rec.x, rec.y) then
    v = (v <= 1) and 2 or 4
  elseif rec.held and inButton(rec.x, rec.y) and (a.button == 2 or a.button == 4) then
    v = a.button
  end
  if v ~= a.button then
    if v == 2 then se(self, SE.button) elseif v == 4 then se(self, SE.refused) end
  end
  a.button = v
end

-- ------------------------------------------------------------------- loop --

function M:update()
  self.t = self.t + 1
  local input = self.game.input
  if input then
    if input:wasPressed("a") then self.padA = true end
    if input:wasPressed("b") then self.padB = true end
    if input:wasPressed("x") or input:wasPressed("r") then self.padX = true end
  end
  if self.countdown > 0 then
    if self.cd then
      -- the shared 3-2-1 (021E637C), one logic tick every other frame
      if self.t % 2 == 0 and self.cd:countdown() then self.countdown = 0 end
      return
    end
    self.countdown = self.countdown - 1
    return
  end
  if self.over and self.cd then
    -- the FINISH (021E667C, 022159F0 state 1)
    if self.t % 2 == 0 and not self.cd:finishing() then return self:finish() end
    return
  end
  if self.over then
    self.over = self.over - 1
    if self.over <= 0 then return self:finish() end
    return
  end
  if self.t % 2 == 0 then self:tick() end
end

function M:tick()
  self.ticks = self.ticks + 1
  if self.timer > 0 then self.timer = self.timer - 1 end
  if self.timer == 450 then se(self, SE.warn) end
  local me = self.teams[1]
  self:sampleTouch()
  self:buttonState(me)
  -- the switch's two hand-offs from the animation (02215FC8)
  for _, a in ipairs(self.teams) do
    if a.switching then
      if a.phase == 1 and a.cmd == 1 then
        self:nextMember(a)
        self:respawn(a)
        a.phase = 2
      elseif a.phase == 2 and a.cmd == 2 then
        a.switching, a.phase = false, 0
        self:setState(a, 4)
      end
    end
  end
  for t = 2, 4 do self:stepAI(self.teams[t]) end
  for _, a in ipairs(self.teams) do
    if not a.cpu then
      self:playerInput(a)
      self:padInput(a)
    end
    local ox, oy = a.x, a.y
    self:stepMon(a)
    a.moving = a.x ~= ox or a.y ~= oy
  end
  self:collide()
  self:stamina()
  self:stepVisuals()
  if self.timer == 0 and not self.over then
    self.over = 60
    self.touch.down = false
    if self.cd then self.cd:startFinish(Rec.isNew(self.game, 7, self.teams[1].score % 256)) end
  end
end

-- the field's effects (02216C38 / 02216AA4): sounds, the hit star, the
-- tackle waves, the fall, the switch's Poke Ball
function M:stepVisuals()
  for t, a in ipairs(self.teams) do
    local v = a.vis
    local s, last = a.state, v.lastState
    if a.bump then se(self, SE.bump); a.bump = false end
    if s == 5 and last ~= 5 then se(self, t == 1 and SE.tackle or SE.tackleRival) end
    if s == 6 and last ~= 6 then v.wave, v.waveT = 11 + a.facing - 1, 0 end
    if (last == 6 and s ~= 6) or (s == 7 and last == 5) then v.wave, v.waveT = 15 + a.facing - 1, 0 end
    if v.wave then
      v.waveT = v.waveT + 1
      if v.waveT > 16 then v.wave = nil end
    end
    if s == 8 and last ~= 8 then
      local mp = self:member(a)
      if mp.jumpStars ~= 0 then se(self, SE.jump) elseif t == 1 then se(self, SE.jumpFlat) end
    end
    if s == 12 and last ~= 12 and self:member(a).jumpStars ~= 0 then se(self, SE.land) end
    -- the fall (6 ticks shrinking) and the way back in
    if s == 3 and not v.falling then
      v.falling, v.fallT, v.scale = true, 6, 1
      se(self, SE.out)
    elseif s ~= 3 and v.falling then
      v.falling = false
      self:addFx("smoke", a.x, a.y)
      se(self, SE.back)
    end
    if v.falling and v.fallT > 0 then
      v.fallT = v.fallT - 1
      v.scale = v.scale - 0.1
    end
    -- the switch (02216770 / 02216934 / 02216A54)
    if a.phase ~= v.phase then
      if a.phase == 0 then
        self:addFx("smoke", a.x, a.y)
        se(self, SE.back)
        a.cmd, v.ballY = 0, nil
      end
      v.phase, v.step, v.n = a.phase, 0, 0
    end
    if v.phase == 1 then
      if v.step == 0 then
        self:addFx("smoke", a.x, a.y)
        v.ballX, v.ballY = a.x, a.y
        se(self, SE.ballOut)
        v.step, v.n = 1, 0
      elseif v.step == 1 then
        v.ballY = v.ballY - 40
        v.n = v.n + 1
        if v.n >= 10 then v.ballY, v.step, v.n = nil, 2, 0 end
      elseif v.step == 2 then
        v.n = v.n + 1
        if v.n > (a.cpu and SWAP_TICKS_CPU or SWAP_TICKS) then a.cmd, v.step = 1, 3 end
      end
    elseif v.phase == 2 then
      if v.step == 0 then
        v.ballX, v.ballY = a.x, a.y - 400
        se(self, SE.ballIn)
        v.step, v.n = 1, 0
      elseif v.step == 1 then
        v.ballY = v.ballY + 40
        v.n = v.n + 1
        if v.n >= 10 then v.step = 2 end
      elseif v.step == 2 then
        a.cmd, v.step = 2, 3
      end
    end
    v.lastState = s
  end
  for i = #self.fxList, 1, -1 do
    local e = self.fxList[i]
    e.t = e.t + 1
    if e.t > e.life then table.remove(self.fxList, i) end
  end
  if self.shake then
    self.shake.t = self.shake.t + 1
    if self.shake.t >= self.shake.n then self.shake = nil end
  end
end

local FX_LIFE = { smoke = 24, star = 15 }
function M:addFx(kind, x, y)
  self.fxList[#self.fxList + 1] = { kind = kind, x = x, y = y, t = 0, life = FX_LIFE[kind] or 20 }
end

-- 02216D9A: the hit star between the two, its sound, the shake when the
-- player's Pokemon is the one hit
function M:hitEffect(v, b, kind)
  self:addFx("star", (v.x + b.x) / 2, (v.y + b.y) / 2)
  se(self, kind == 1 and SE.hit or SE.stomp)
  if v.index == 1 then
    self.shake = kind == 1 and { amp = 4, n = 10, t = 0 } or { amp = 10, n = 15, t = 0 }
  end
end

function M:finish()
  local points, stats = {}, {}
  for t, a in ipairs(self.teams) do
    -- ov96_0221A700: floor(points x 1.5), at most 200
    points[t] = math.min(200, math.floor(a.score * 1.5))
    stats[t] = {}
    for m = 1, 3 do
      local mp = a.members[m]
      stats[t][m] = { miss = mp.misses > 0, fail = mp.misses, score = mp.scores, jump = mp.jumps, hit = mp.hits,
        fall = mp.falls or 0, switch = mp.switches or 0, impede = mp.impede or 0 }
    end
  end
  self.game.stack:pop()
  if self.onDone then self.onDone({ points = points, score = self.teams[1].score, stats = stats, record = self.teams[1].score }) end
end

-- ------------------------------------------------------------------- draw --

function M:img(key)
  local rec = self.d[key]
  if type(rec) == "table" and rec.image and not rec.path then
    if self.images[rec] == nil then
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

function M:seqFrame(set, seq, tick, hold)
  local list = self.d.objSeq and self.d.objSeq[set] and (self.d.objSeq[set][seq] or self.d.objSeq[set][tostring(seq)])
  if type(list) ~= "table" or #list == 0 then return 0 end
  local total = 0
  for _, dur in ipairs(list) do total = total + dur end
  if hold and tick >= total then return #list - 1 end
  tick = tick % math.max(1, total)
  for f, dur in ipairs(list) do
    if tick < dur then return f - 1 end
    tick = tick - dur
  end
  return 0
end

function M:anim(set, seq, x, y, tick, hold)
  local f = self:seqFrame(set, seq, tick, hold)
  if not self:sprite(("%s_%d_%d"):format(set, seq, f), x, y) then
    return self:sprite(("%s_%d_0"):format(set, seq), x, y)
  end
  return true
end

function M:image(path)
  if type(path) ~= "string" then return nil end
  self.extern = self.extern or {}
  if self.extern[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.extern[path] = ok and img or false
    if self.extern[path] then self.extern[path]:setFilter("nearest", "nearest") end
  end
  return self.extern[path] or nil
end

function M:monIcon(mon, x, y, frame, scale)
  local data = self.game.data
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (data.icons and data.icons.bySpecies and data.icons.bySpecies[mon.species]) or (def and def.icon)
  local path, fh = entry, nil
  if type(entry) == "table" then path, fh = entry.image, tonumber(entry.frameHeight) end
  local img = self:image(path)
  if not img then return false end
  scale = scale or 1
  local iw, ih = img:getDimensions()
  fh = fh or math.min(iw, ih)
  local frames = math.max(1, math.floor(ih / fh))
  local q = love.graphics.newQuad(0, ((frame or 0) % frames) * fh, iw, fh, iw, ih)
  love.graphics.draw(img, q, math.floor(x - iw * scale / 2), math.floor(y - fh * scale), 0, scale, scale)
  return true
end

-- the walking-Pokemon sheet's record (gen4_follow_mon)
function M:walkerSheet(mon)
  local rec = self.game.data and self.game.data.gen4_follow_mon
  if type(rec) ~= "table" or not rec.lut or not mon then return nil end
  local ok, F = pcall(require, "src.import.Gen4HgssFollowMon")
  if not ok then return nil end
  local idx = F.index(rec, tonumber(mon.species), tonumber(mon.form) or 0, false)
  return rec.sheets and (rec.sheets[idx] or rec.sheets[tostring(idx)])
end

-- 021E6168: the walker is a big one (tp_param byte 1) -- here, its frame
function M:bigWalker(mon)
  local sheet = self:walkerSheet(mon)
  return sheet ~= nil and (tonumber(sheet.frameHeight) or 32) >= 64
end

-- feet at (x, y), scaled about the feet
local WALK = { [UP] = 0, [DOWN] = 2, [LEFT] = 4, [RIGHT] = 6 }
function M:walker(mon, facing, x, y, step, scale)
  local sheet = self:walkerSheet(mon)
  local img = sheet and self:image((mon.shiny and sheet.shiny) or sheet.normal)
  if not img then return false end
  local fw, fh = tonumber(sheet.frameWidth) or 32, tonumber(sheet.frameHeight) or 32
  local f = (WALK[facing] or 2) + (step % 2)
  local iw = img:getWidth()
  local qx, qy
  if iw >= fw * 8 then qx, qy = f * fw, 0 else qx, qy = 0, f * fh end
  local q = love.graphics.newQuad(qx, qy, fw, fh, img:getDimensions())
  love.graphics.draw(img, q, math.floor(x), math.floor(y + 4), 0, scale, scale, fw / 2, fh)
  return true
end

local DIZZY_SPIN = { UP, RIGHT, DOWN, LEFT }

function M:drawField()
  local g = love.graphics
  g.push()
  if self.shake then
    local k = self.shake.t % 3
    local amp = self.shake.amp * (1 - self.shake.t / self.shake.n)
    g.translate(k == 0 and -amp / 2 or (k == 2 and amp / 2 or 0), k == 0 and -amp or (k == 2 and amp or 0))
  end
  g.setColor(0.16, 0.16, 0.23, 1)
  g.rectangle("fill", -16, -16, W + 32, H + 32)
  g.setColor(1, 1, 1, 1)
  local ring = self:img("ring")
  if ring then g.draw(ring, 0, 0) end
  local plate = self:img("plate")
  if plate then g.draw(plate, 0, 0) end
  -- the Pokemon, back to front by their feet (02216C38's sort)
  local list = {}
  for t, a in ipairs(self.teams) do
    local mp = self:member(a)
    local fx, fy = self:feet(a)
    local v = a.vis
    local hidden = (v.falling and v.fallT <= 0) or a.switching
    if not hidden and mp.mon then
      list[#list + 1] = { y = fy, f = function()
        local scale = 1.2 - (160 - a.y) * 12 / 4096
        local dy = 0
        if v.falling then
          scale = scale * math.max(0.1, v.scale)
          if fy >= 160 then dy = 4 * (6 - v.fallT) end
        end
        if not v.falling then
          local c = TEAM_RGB[t]
          g.setColor(c[1], c[2], c[3], 0.55)
          g.ellipse("fill", fx, fy, mp.radius + 2, (mp.radius + 2) / 2)
          g.setColor(1, 1, 1, 1)
        end
        local facing = a.facing
        if a.fainted then facing = DIZZY_SPIN[math.floor(self.ticks / 3) % 4 + 1] end
        local moving = a.state == 6 or a.moving
        local step = moving and math.floor(self.ticks / 2) or math.floor(self.ticks / 8)
        if a.state == 4 and math.floor(self.ticks / 2) % 2 == 1 then g.setColor(1, 1, 1, 0.5) end
        if not self:walker(mp.mon, facing, fx, fy - a.z + dy, step, scale) then
          self:monIcon(mp.mon, fx, fy - a.z + dy + 4, math.floor(self.ticks / 8))
        end
        g.setColor(1, 1, 1, 1)
        -- sweat below 30, the faint stars at 0 (02216C38), 24 px over the point
        if not v.falling and not a.switching then
          if mp.stamina <= 0 or a.fainted then self:anim("a", 1, a.x, a.y - a.z - 24, self.ticks)
          elseif mp.stamina < TIRED then self:anim("a", 9, a.x, a.y - a.z - 24, self.ticks) end
        end
        if v.wave then self:anim("a", v.wave, a.x, a.y, v.waveT, true) end
      end }
    end
  end
  table.sort(list, function(p, q) return p.y < q.y end)
  for _, e in ipairs(list) do e.f() end
  for _, a in ipairs(self.teams) do
    local v = a.vis
    if v.ballY then self:anim("a", 21, v.ballX, v.ballY, self.ticks) end
  end
  for _, e in ipairs(self.fxList) do
    if e.kind == "smoke" then self:anim("a", 8, e.x, e.y, e.t, true)
    elseif e.kind == "star" then self:anim("a", 7, e.x, e.y, e.t, true) end
  end
  -- the SWITCH button (0221768C: 0 -> 2, 1 -> 6, 2 -> 4, 3 -> 3, 4 -> 5)
  local me = self.teams[1]
  local BTN = { [0] = 2, 6, 4, 3, 5 }
  self:anim("a", BTN[me.button] or 3, 128, 16, self.ticks)
  -- the clock on its plate: icon at (114, 180), seconds at 134 / 150 (text)
  self:anim("a", 20, 114, 180, 0)
  local Font = require("src.render.Font")
  local secs = math.floor(self.timer / 30)
  Font.draw(("%02d"):format(secs), 128, 175)
  g.pop()
  -- the shared 3-2-1 / FINISH (main engine = this screen, surface at 0)
  if self.cd then self.cd:draw(0) end
end

-- the top screen (022194C4 / 0221768C / 02219A5C / 02219C30)
function M:drawTop()
  local g = love.graphics
  g.setColor(0.75, 0.2, 0.2, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local top = self:img("top")
  if top then g.draw(top, 0, 0) end
  local fg = self:img("top_fg")
  if fg then g.draw(fg, 0, 0) end
  local me = self.teams[1]
  -- the score's three digits at tile (16 + 4 i, 11)
  local v = math.max(0, math.min(999, me.score))
  local ds = { math.floor(v / 100), math.floor(v / 10) % 10, v % 10 }
  for i, dgt in ipairs(ds) do
    local img = self:img("digit_" .. dgt)
    if img then g.draw(img, 128 + 32 * (i - 1), 88) end
  end
  -- the player's team flag
  self:anim("b", 12, 134, 160, 0)
  -- the four teams' Pokemon at (120 + 32 t, 36) and their places at y 24
  -- (shown only between 55 and 10 seconds left, 022196E4)
  local secs = math.floor(self.timer / 30)
  local order = {}
  for t = 1, 4 do order[t] = { t = t, s = self.teams[t].score } end
  table.sort(order, function(p, q) if p.s ~= q.s then return p.s > q.s end return p.t < q.t end)
  local place, rank = {}, 0
  for i, o in ipairs(order) do
    if i == 1 or o.s ~= order[i - 1].s then rank = i - 1 end
    place[o.t] = rank
  end
  for t, a in ipairs(self.teams) do
    local x = 120 + 32 * (t - 1)
    local mon = self:member(a).mon
    if a.switching then self:anim("b", 10, x, 36, 0)
    elseif mon then self:monIcon(mon, x, 52, math.floor(self.t / 8)) end
    if secs >= 10 and secs <= 55 then self:anim("b", 6 + place[t], x, 24, 0) end
  end
  -- the bench: the next one big at (40, 136), the one after at (40, 48);
  -- sweat when tired
  local nxt = me.members[me.cur % 3 + 1]
  local after = me.members[(me.cur + 1) % 3 + 1]
  if nxt.mon then self:monIcon(nxt.mon, 40, 136 + 16, 0, 2) end
  if after.mon then self:monIcon(after.mon, 40, 48 + 16, 0, 2) end
  if nxt.stamina < TIRED then self:anim("b", 5, 40, 112, self.t) end
  if after.stamina < TIRED then self:anim("b", 5, 40, 24, self.t) end
  local Font = require("src.render.Font")
  if self.names[1] then Font.draw(tostring(self.names[1]), 144, 152) end
  if self.countdown > 0 and not self.cd then Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 40) end
  if self.over and not self.cd then Font.draw("FINISH!", 100, 40) end
end

function M:draw()
  local g = love.graphics
  if SecondScreen.separate(self.game) then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawField() end)
  else
    local input = self.game.input
    if self.showTop or (input and (input:isDown("select") or input:isDown("l"))) then self:drawTop() else self:drawField() end
    local Font = require("src.render.Font")
    if self.countdown > 0 and not self.cd then Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 88) end
    if self.over and not self.cd then Font.draw("FINISH!", 100, 88) end
  end
  g.setColor(1, 1, 1, 1)
end

return M
