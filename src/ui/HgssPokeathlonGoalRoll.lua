-- HEARTGOLD / SOULSILVER POKeATHLON: GOAL ROLL (event 9, sub-app
-- ov96_0221A81C = { 02210C98 init, 02211650 draw sprites, 02211660 results,
-- 022116C8 exit }, per-event state table ov96_0221DC88 = { 022117EC play,
-- 02211870 points } (pokeheartgold src/pokeathlon/pokeathlon_data.c);
-- pokeheartgold asm/overlay_96.s 0x02210C98..0x02215710; the reading is
-- written up in scratch_claude/athlon/NOTES.md, "## Goal Roll"). Art and
-- tables: `gen4_hgss_goal_roll` (src/import/Gen4HgssPokeathlonGoalRollArt.lua).
--
-- The game logic runs at 30 ticks a second (the clock 0xA8C = 2700 = 90 s,
-- shown as timer / 30 -- 0221490C); this module steps it every other frame.
--
-- READ FROM CODE:
--   * four teams, ALL TWELVE Pokemon on the 256 x 192 touch screen at once,
--     team t's three at ov96_0221D408 (team 0 (88,80) (48,80) (72,56) ...),
--     facing down; each team's goal is its CORNER of the pitch, the line
--     between its two posts (ov96_0221D4B4: (64,24)-(8,80), (192,24)-(248,80),
--     (64,184)-(8,128), (192,184)-(248,128))
--   * THE CLOCK (02211B94): 2700 ticks, one off a tick; at 0 the event ends.
--     At 900 (30 s left) the SECOND BALL comes in (02212B94) and the top
--     screen's clock gives way to message 311 of bank 309 (0221490C)
--   * TOUCH (02211B94 / 02213364): a new touch takes the team's own Pokemon
--     nearest the stylus within 80 px (ov96_021E6104) unless it is dashing,
--     fainted or being knocked; while held, the stylus point IS its target
--     (DRAG TO MOVE); let go within 8 ticks of the touch with the target
--     moved and it DASHES there (state 1, course counter 6) -- unless tired
--     (state 3) or fainted (state 2)
--   * MOVING (022124F8): towards the target at the walking speed
--     params[15 + SPEED] / 10 (2.8..3.6 px a tick), dashing params[20 + SPEED]
--     / 10 (3.2..4.0), tired 2.0; facing by the way it goes (quarter-turns);
--     standing still it gets 2 stamina back every 10 ticks (02213558); a dash
--     ends on arrival. The walls (02213728): the pitch is x 8..247, y 16..183
--     less the Pokemon's radius; Pokemon also stop at the four goal lines
--     (pushed out by their radius); a hit stops it on the wall
--   * KNOCKS: a kick's recoil (3 ticks back from the ball, 3+2+1 px); a
--     Power Shot's victim is knocked 7 ticks (7+6+...+1 px), then held to 30
--     ticks, spinning (02213FB4)
--   * THE BALL (022127F4 / 02212B94): radius 8 (golden 12) against the
--     Pokemon's body circle (centre lifted by the size class's y offset,
--     radius by size class, /a/1/7/0 member 11). Touching it sends it straight
--     away from the Pokemon at the speed table's first entry: a Pokemon that
--     is not moving only turns it (same speed); a WALKING one kicks it with
--     ov96_0221D5AA[SKILL] (5,5,5,4,4,4,4,3,... px a tick, one entry a tick,
--     30 at most); a DASHING one whose way lies within params[SKILL] degrees
--     of the ball (180 for every star count: always) makes a POWER SHOT:
--     ov96_0221D514[SKILL] (7,7,6,5,5,...), course counter 4, the shooter
--     recoils. While the shot is still at least ov96_0221D640[POWER] (7 7 6 5
--     4) px a tick it is LIVE: it hits any other Pokemon it touches (team
--     mates too) for params[25 + POWER] (20..50) stamina -- at 0 the Pokemon
--     FAINTS (state 2, 90 ticks, then full stamina; course counter 1 = the
--     miss) -- and keeps going. Stamina below 30 = TIRED (state 3,
--     sweating, 2 px a tick, cannot dash) (022132FC).
--     Walls bounce the ball (the component into the wall reversed); the eight
--     posts (radius 8) reflect it; two balls that meet swap speed (02212F0C:
--     a slow one (<= 3) takes a fast one's, otherwise both roll off at 3)
--   * GOALS (022130EC): a ball whose centre crosses a goal line (x + y <= 80,
--     x - y >= 176, y - x >= 128, x + y >= 384 -- ov96_0221D474 /
--     sub_02020E80) scores for the team of the last Pokemon that touched it
--     (nobody yet: nothing): +1 white / +2 golden (cap 99) and the goal's
--     team -1 (not below 0); in its own goal the toucher's team only loses 1
--     (course counters 8 and 1 = the miss). Course counter 3 for a goal.
--     After 10 ticks the ball comes back at one of 15 spots (ov96_0221D438,
--     not the spot either ball last used) and drops in for 8 ticks
--   * THE GOLDEN BALL (02212B94): when the first ball comes back, golden on
--     LCRandom % 100 < base + misses (cap 100): base 0 while the clock is
--     >= 1200, 5 >= 600, 10 >= 300, else 25; each white one adds 1 to
--     `misses` (cap 100), a golden one clears it. The second ball is always
--     white. Both start at (128, 104), the first one dropping in at once
--   * THE RIVALS' AI (02214B84 / 022155A0): each CPU team's three Pokemon get
--     roles once (02214ABC: role 0 by SKILL + stamina, roles 1 / 2 by SKILL +
--     POWER -- with the cartridge's neighbour-only comparisons); one decision
--     a tick (team after team, a role per round, a round every 3 ticks); a
--     decision returns ticks to wait before the next one.
--     Role 0 (02214EB4, the keeper): a free ball in its own quarter and not
--     past it (0221567C) -> run at it, dash 80 % (wait 10); otherwise back to
--     one of its three home spots (ov96_0221D678, +-8 jitter, wait 6).
--     Role 1 (02214C3C, the striker): per ball -- touching it: off to a spot
--     by its quarter (ov96_0221D678[3 - quarter]); same quarter and behind it
--     (02215650): dash at it; same quarter: 20 % nothing, 70 % walk, 10 % dash
--     (wait 3); another quarter: 60 % nothing, 20 % walk, 20 % dash (wait 10).
--     Role 2 (02215184): behind a ball in its quarter -> dash at it; with
--     the keeper's stamina >= 50 -> wander to the emptiest quarter
--     (02215478); else like the keeper. Quarters split at (128, 96).
--   * POINTS (ov96_0221A730): the place's ov96_0221D99C = 100 / 80 / 70 / 60
--     + 5 x goals, at most 200; a team tied with k others takes the place k
--     further down (two teams level first both take 80)
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 02210C98 puts them on the main
--     engine at y offset 0 (021E6290 r1), the touch screen here
--     (gSystem.screensFlipped = 1, main surface at 0 -- 021EB5C8); 022117EC
--     runs the countdown, play, then the finish
-- No-Miss: the cartridge counts a miss for fainting under a Power Shot and
-- for an own goal (counter 1) -- as Bulbapedia has it. Effort: dash (counter
-- 6), hit (counter 4, Power Shots); score = the Pokemon's goals (counter 3).
--
-- THE RECORD (READ FROM CODE; src/pokemon/HgssPokeathlonRecords.lua): at
-- time up 02214618 hands ov96_021E8318 the team's goals as the top screen
-- keeps them (02214904: +0x44, a byte) for NEW RECORD! (021E839C, higher is
-- better); the end state's field_5E0 (02211870, the goals 0x6F4) is what
-- the course's end saves.
--
-- STAND-INS, said so: during the FINISH the field stands still (the
-- cartridge runs 02211B94 on under it); without `gen4_hgss_athlon_common`
-- the 3-2-1 and the finish are text; the field Pokemon are the
-- walking-Pokemon sheets (gen4_follow_mon -- the event's own mon objects,
-- ov96_021EA854, are not read; icons when absent) on a team-coloured ring,
-- their sprite offsets ([0x10] [0x18] [0x28] of those objects) are not read,
-- so a Pokemon's spot is its ground point and its body centre is that point
-- lifted by the size class's y offset; the walls' fixed-point / whole-pixel
-- rounding is done in floats; the goal-mouth flash (obj seqs 19-22) draws
-- nothing from this ROM's cells and is left out; the clock's digit sprites
-- (the course's shared resource 0xAAF) are the font; the place for the
-- points (byte 9 of the course's team record, worked out outside the event)
-- is the number of teams with more goals; the end is a short pause, not the
-- fade. The pad: a direction walks the chosen Pokemon, A dashes it the way
-- it faces, R / B choose the next one.

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local TIME = 2700                         -- 0xA8C ticks, 30 a second
local SECOND_BALL = 900                   -- 0xE1 << 2
local TOUCH_R = 0x50                      -- ov96_021E6104
local DASH_HOLD = 8                       -- release within 8 ticks
local TIRED = 30                          -- 022132FC
local FAINT_TICKS = 90
local POWER_KNOCK, POWER_STUN = 7, 30
local KICK_RECOIL = 3
local SPAWN_TICKS, GOAL_TICKS = 8, 10
local NOBODY = 12
local SE = { dash = 0x8CC, faint = 0x890, power = 0x8C7, myGoal = 0x8CB, goal = 0x8C6,
  drop = 0x8C9, dropGold = 0x8CA }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local POWER, STAMINA, SKILL, SPEED = 0, 1, 2, 4
local UP, DOWN, LEFT, RIGHT = 1, 2, 3, 4

-- ov96_0221D408: the teams' starting spots
local START = {
  { { 88, 80 }, { 48, 80 }, { 72, 56 } }, { { 168, 80 }, { 208, 80 }, { 184, 56 } },
  { { 88, 128 }, { 48, 128 }, { 72, 152 } }, { { 168, 128 }, { 208, 128 }, { 184, 152 } },
}
-- ov96_0221D4B4: the posts, two a team
local POSTS = {
  { 64, 24 }, { 8, 80 }, { 192, 24 }, { 248, 80 }, { 64, 184 }, { 8, 128 }, { 192, 184 }, { 248, 128 },
}
-- ov96_0221D474: each goal line's two points (sub_02020E80 >= 0 = inside)
local GOAL_LINE = {
  { { 64, 16 }, { 0, 80 } }, { { 256, 80 }, { 192, 16 } },
  { { 0, 128 }, { 64, 192 } }, { { 192, 192 }, { 256, 128 } },
}
-- ov96_0221D3D8 (the nets) / ov96_0221D3A8 (the GOAL! banners) / the nets'
-- rotation (ov96_0221D1F4 + 12: 0, 0x4000, 0xC000, 0x8000)
local NET = { { 32, 48 }, { 224, 48 }, { 32, 160 }, { 224, 160 } }
local BANNER = { { 0, 40 }, { 255, 40 }, { 0, 152 }, { 255, 152 } }
local NET_TURN = { 0, 0.25, 0.75, 0.5 }
-- ov96_0221D438 / 0221D43A: the 15 spots a ball drops in at
local SPOTS = {
  { 80, 88 }, { 104, 88 }, { 128, 88 }, { 152, 88 }, { 176, 88 },
  { 80, 104 }, { 104, 104 }, { 128, 104 }, { 152, 104 }, { 176, 104 },
  { 80, 120 }, { 104, 120 }, { 128, 120 }, { 152, 120 }, { 176, 120 },
}
-- ov96_0221D514 (Power Shot) / ov96_0221D5AA (kick): speed a tick by SKILL
local SHOT = {
  [0] = { 7, 7, 6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 7, 7, 6, 6, 5, 5, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 3, 3, 3, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 7, 7, 6, 6, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 4, 4, 4, 4, 3, 3, 2, 2, 1, 0, 0, 0, 0, 0, 0 },
  { 7, 7, 7, 7, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 3, 3, 3, 2, 2, 1, 0, 0, 0, 0 },
  { 7, 7, 7, 7, 7, 7, 7, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 3, 3, 3, 2, 2, 1 },
}
local KICK = {
  [0] = { 5, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 5, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 5, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 4, 4, 4, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  { 4, 4, 4, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local LIVE = { [0] = 7, 7, 6, 5, 4 }      -- ov96_0221D640, by the shooter's POWER
local PLACE_AP = { 100, 80, 70, 60 }      -- ov96_0221D99C
-- ov96_0221D678 (+ 12 per team 1..3): three home spots near the team's
-- corner; the striker's index 3 (3 - quarter 0) reads the next bytes
-- (ov96_0221D69C), as the cartridge does
local HOME = {
  [0] = { { 208, 64 }, { 184, 48 }, { 224, 88 } },
  [1] = { { 48, 144 }, { 72, 160 }, { 32, 120 } },
  [2] = { { 208, 144 }, { 184, 160 }, { 224, 120 } },
  [3] = { { 2048, 2056 }, { 0, 0 }, { 0, 0 } },
}
local TEAM_RGB = { { 0.9, 0.2, 0.3 }, { 0.2, 0.35, 0.95 }, { 0.15, 0.7, 0.25 }, { 0.95, 0.85, 0.15 } }

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function mag(x, y) return math.sqrt(x * x + y * y) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_goal_roll
  return type(d) == "table" and d.params ~= nil and d.sizes ~= nil
end

-- the performance row's raw bytes (byte 6 = the size class 1..3)
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

-- ov96_0221359C: a Pokemon's numbers from its stars (/a/1/7/0 member 8)
local function monParams(self, mon, rival, t, k)
  local p, st = self.d.params, starsOf(self.game, mon, rival)
  local raw = rawRow(self.game.data, mon)
  local class = raw and tonumber(raw[7]) or 2
  if class < 1 or class > 3 then class = 2 end
  local size = (self.d.sizes and self.d.sizes[class]) or { 10, 14 }
  local stamina = p[10 + st[STAMINA]]
  local x, y = START[t][k][1], START[t][k][2]
  return {
    mon = mon, team = t, index = (t - 1) * 3 + (k - 1), slot = k,
    cone = p[st[SKILL]], stamina = stamina, maxStamina = stamina,
    walk = p[15 + st[SPEED]] / 10, dash = p[20 + st[SPEED]] / 10, damage = p[25 + st[POWER]],
    skill = st[SKILL], power = st[POWER],
    yoff = size[1], radius = size[2], class = class,
    x = x, y = y, tx = x, ty = y, dx = 0, dy = 0, facing = DOWN, state = 0,
    knock = 0, kx = 0, ky = 0, kf = 0, kt = 0, faintT = 0, rest = 0,
    dustT = 0, dustI = 0,
    goals = 0, points = 0, dashes = 0, hits = 0, missed = false,
  }
end

-- opts: team (three Pokemon), rivals ({3 teams of 3}), names (optional
-- {4}), onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, ticks = 0, images = {} }, M)
  self.d = game.data.gen4_hgss_goal_roll
  self.teams = {}
  self.mons = {}
  for t = 1, 4 do
    local list = t == 1 and opts.team or (opts.rivals and opts.rivals[t - 1]) or {}
    local team = { index = t, cpu = t > 1, score = 0, members = {}, plate = nil,
      name = (opts.names and opts.names[t]) or (t == 1 and (((game.save or {}).player or {}).name or "PLAYER")) or ("TEAM " .. t) }
    for k = 1, 3 do
      local mp = monParams(self, list[k], t > 1, t, k)
      team.members[k] = mp
      self.mons[#self.mons + 1] = mp
    end
    self.teams[t] = team
  end
  -- the two balls (heap 0x62C, 0x4C each): both at (128, 104), spot 7, the
  -- first one dropping in (ov96_02213444 / 02210C98 case 2)
  self.balls = {}
  for b = 1, 2 do
    local ball = self:freshBall()
    ball.x, ball.y, ball.spot = 128, 104, 7
    ball.kind = b == 1 and 1 or 0
    self.balls[b] = ball
  end
  self.misses = 0                         -- heap 0x743
  self.timer = TIME
  -- the AI (ov96_02214A24 / 02214ABC)
  self.ai = { count = 0, active = false, turn = 0, role = 0, roles = {} }
  for t = 2, 4 do self.ai.roles[t] = self:sortRoles(self.teams[t]) end
  self.sel = nil                          -- heap 0x734: the player's chosen Pokemon
  self.held, self.heldT = false, 0        -- heap 0x704 / 0x708 / 0x742
  self.padSel = 1
  self.fx = {}
  self.countdown = 180
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (02210C98)
  if CD.available(game) then self.cd = CD.new(game, 0) end
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

-- ov96_02213444: a ball back to rest
function M:freshBall()
  return { x = 128, y = 104, vx = 0, vy = 0, dx = 0, dy = 0, kind = 0, state = 3, wait = 0,
    toucher = NOBODY, idx = 0, dur = 0, kick = 0, speed = 0, row = 0, dmg = 0, power = 0,
    spawnT = 0, latch = {}, wall = false, spot = 7 }
end

-- ------------------------------------------------------------------ geometry --

local function quarter(x, y)           -- ov96_022143FC: the goal a point is nearest
  if x < 128 then return y < 112 and 0 or 2 end
  return y < 112 and 1 or 3
end

local function q96(cx, cy, x, y)        -- ov96_02215614 (the AI's quarters)
  if x < cx and y < cy then return 0 end
  if x >= cx and y < cy then return 1 end
  if x < cx and y >= cy then return 2 end
  return 3
end

-- sub_02020E80: which side of a->b the point c is
local function side(ax, ay, bx, by, cx, cy)
  return cx * (ay - by) + ax * (by - cy) + bx * (cy - ay) >= 0
end

-- sub_02020EB0: segments a-b and c-d cross
local function crosses(ax, ay, bx, by, cx, cy, dx, dy)
  return (side(ax, ay, bx, by, cx, cy) ~= side(ax, ay, bx, by, dx, dy))
    and (side(cx, cy, dx, dy, ax, ay) ~= side(cx, cy, dx, dy, bx, by))
end

local function trunc(v) return v >= 0 and math.floor(v) or -math.floor(-v) end

-- sub_02020F4C: the crossing point of two segments (whole pixels), or nil
local function crossPoint(ax, ay, bx, by, cx, cy, dx, dy)
  if not crosses(ax, ay, bx, by, cx, cy, dx, dy) then return nil end
  local rx, ry, sx, sy = bx - ax, by - ay, dx - cx, dy - cy
  local den = rx * sy - ry * sx
  if den == 0 then return nil end
  local u = ((cx - ax) * sy - (cy - ay) * sx) / den
  local px, py = math.floor(ax + u * rx + 0.5), math.floor(ay + u * ry + 0.5)
  local function within(p, a, b) return p >= math.min(a, b) and p <= math.max(a, b) end
  if within(px, ax, bx) and within(py, ay, by) and within(px, cx, dx) and within(py, cy, dy) then return px, py end
  return nil
end

-- ov96_02213D2C: a straight wall a-b against the move o->n; where it stops
local function wallHit(ax, ay, bx, by, ox, oy, nx, ny)
  if not crosses(trunc(ax), trunc(ay), trunc(bx), trunc(by), trunc(ox), trunc(oy), trunc(nx), trunc(ny)) then return nil end
  local wx, wy = bx - ax, by - ay
  local n = mag(wx, wy)
  wx, wy = wx / n, wy / n
  if ay == by then
    local d0, d1 = math.abs(ay - oy), math.abs(ay - ny)
    if d1 == 0 then return nil end
    local t = d0 / (d0 + d1)
    return ox + t * wx, ay + t * wy
  elseif ax == bx then
    local d0, d1 = math.abs(ax - ox), math.abs(ax - nx)
    if d1 == 0 then return nil end
    local t = d0 / (d0 + d1)
    return ax + t * wx, oy + t * wy
  end
  return nil
end

-- the goal lines as walls for the Pokemon (02213728 mode 1): a, b, normal
local DIAG = {
  [0] = { -32, 112, 96, -16, 1, 1 }, { 160, -16, 288, 112, -1, 1 },
  { 96, 224, -32, 96, 1, -1 }, { 288, 96, 160, 224, -1, -1 },
}

-- ov96_02213728: the pitch's walls. Returns the code (0 none, 1 left,
-- 2 right, 3 top, 4 bottom, 5..8 a goal line) and where it ends up
local function walls(nx, ny, ox, oy, r, mons)
  local q = quarter(nx, ny)
  local code, outx, outy = 0, nil, nil
  local diagHit, fallback = false, false
  local dax, day, dbx, dby
  if mons then
    local d = DIAG[q]
    local s = 1 / math.sqrt(2)
    dax, day = trunc(d[1] + r * d[5] * s), trunc(d[2] + r * d[6] * s)
    dbx, dby = trunc(d[3] + r * d[5] * s), trunc(d[4] + r * d[6] * s)
    local px, py = crossPoint(dax, day, dbx, dby, trunc(ox), trunc(oy), trunc(nx), trunc(ny))
    if px then
      if not side(dax, day, dbx, dby, px, py) then outx, outy, fallback = ox, oy, true
      else outx, outy = px, py end
      diagHit, code = true, 5 + q
    end
  end
  -- a straight wall's hit, weighed against the goal line's
  local function settle(px, py, wcode, keepDiag)
    if fallback then return code, outx, outy end
    if diagHit and keepDiag(px, py) then return code, outx, outy end
    if mons and crossPoint(dax, day, dbx, dby, trunc(ox), trunc(oy), trunc(px), trunc(py)) then
      return wcode, ox, oy
    end
    return wcode, px, py
  end
  local function sides(rr)
    if nx < 128 then
      local x = rr + 8
      if nx < x and ox == x then return 1, ox, oy end
      local px, py = wallHit(x, 183, x, 16, ox, oy, nx, ny)
      if px then return settle(px, py, 1, function(hx) return outx >= hx end) end
    else
      local x = 247 - rr
      if nx > x and ox == x then return 2, ox, oy end
      local px, py = wallHit(x, 16, x, 183, ox, oy, nx, ny)
      if px then return settle(px, py, 2, function(hx) return outx <= hx end) end
    end
    return code, outx, outy
  end
  if ny < 112 then
    -- (the cartridge's early test reads 16 - r here, not 16 + r)
    if ny < r + 16 and oy == 16 - r then return 3, ox, oy end
    local px, py = wallHit(8, r + 16, 247, r + 16, ox, oy, nx, ny)
    if px then return settle(px, py, 3, function(_, hy) return outy >= hy end) end
    return sides(r)
  end
  local y = 183 - r
  if ny > y and oy == y then return 4, ox, oy end
  local px, py = wallHit(247, y, 8, y, ox, oy, nx, ny)
  if px then return settle(px, py, 4, function(_, hy) return outy <= hy end) end
  return sides(r)
end

local function facingOf(dx, dy)          -- 022124F8 (VEC_AngleBetween)
  local a = math.atan2(dy, dx) / (2 * math.pi) * 65536
  if a < 0 then a = a + 65536 end
  if a <= 0x2000 or a >= 0xE000 then return RIGHT end
  if a > 0x2000 and a < 0x6000 then return DOWN end
  if a >= 0x6000 and a <= 0xA000 then return LEFT end
  return UP
end

local SPIN = { [UP] = RIGHT, [RIGHT] = DOWN, [DOWN] = LEFT, [LEFT] = UP }   -- 02213FB4

-- ------------------------------------------------------------------ the mons --

-- 022124F8: one Pokemon's tick (knocks, faint, walking)
function M:stepMon(mp)
  mp.dx, mp.dy = 0, 0
  if mp.knock ~= 0 then
    if (mp.knock == 2 or mp.knock == 3) and mp.kt > 0 then mp.kt = mp.kt - 1 end
    if mp.kf == 0 and mp.kt <= 0 then
      mp.knock, mp.kt = 0, 0
    else
      mp.x, mp.y = mp.x + mp.kf * mp.kx, mp.y + mp.kf * mp.ky
      mp.tx, mp.ty = mp.x, mp.y
      if mp.kf > 0 then mp.kf = mp.kf - 1 end
      if mp.state ~= 2 and mp.knock == 3 then mp.facing = SPIN[mp.facing] or UP end
    end
  end
  if mp.state == 2 or mp.faintT ~= 0 then
    mp.faintT = mp.faintT - 1
    if mp.faintT <= 0 then
      mp.faintT, mp.state, mp.stamina = 0, 0, mp.maxStamina
    end
    return
  end
  if mp.knock ~= 0 then return end
  local dx, dy = mp.tx - mp.x, mp.ty - mp.y
  local d = mag(dx, dy)
  if d <= 0 then
    -- 02213558: standing still, 2 stamina back every 10 ticks
    mp.rest = mp.rest + 1
    if mp.rest >= 10 then
      mp.rest = 0
      mp.stamina = math.min(mp.maxStamina, mp.stamina + 2)
    end
    return
  end
  dx, dy = dx / d, dy / d
  mp.dx, mp.dy = dx, dy
  local spd = mp.state == 1 and mp.dash or (mp.state == 3 and 2.0) or mp.walk
  if d <= spd then mp.x, mp.y = mp.tx, mp.ty
  else mp.x, mp.y = mp.x + dx * spd, mp.y + dy * spd end
  mp.facing = facingOf(dx, dy)
end

function M:stepMons()
  local prev = {}
  for i, mp in ipairs(self.mons) do
    prev[i] = { mp.x, mp.y }
    self:stepMon(mp)
  end
  for i, mp in ipairs(self.mons) do
    local o = prev[i]
    if mp.x ~= o[1] or mp.y ~= o[2] then
      local code, x, y = walls(mp.x, mp.y, o[1], o[2], mp.radius, true)
      if code ~= 0 and x then mp.x, mp.y, mp.tx, mp.ty = x, y, x, y end
    end
    if mp.x == mp.tx and mp.y == mp.ty and mp.state ~= 3 and mp.state ~= 2 then mp.state = 0 end
    -- the dash's dust (02211F38: one of three every 5 ticks)
    if mp.state == 1 then
      if mp.dustT == 0 then
        self:addFx("dust", mp.x, mp.y)
        mp.dustT = 5
        if mp.team == 1 then se(self, SE.dash) end
      else
        mp.dustT = mp.dustT - 1
      end
    end
  end
end

-- 022132FC: tired below 30 stamina
function M:tiredness()
  for _, mp in ipairs(self.mons) do
    if mp.state ~= 2 then
      if mp.stamina < TIRED then mp.state = 3
      elseif mp.state ~= 1 then mp.state = 0 end
    end
  end
end

-- ------------------------------------------------------------------ the balls --

local function ballRadius(ball) return ball.kind == 2 and 12 or 8 end

-- ov96_022134D4: send the ball along (dx, dy) at its speed
local function launch(ball, dx, dy)
  local n = mag(dx, dy)
  if n > 0 then dx, dy = dx / n, dy / n else dx, dy = 0, 0 end
  ball.dx, ball.dy = dx, dy
  ball.vx, ball.vy = dx * ball.speed, dy * ball.speed
end

-- ov96_02213E60: a spot neither ball used last
function M:respawn(ball)
  local free = {}
  for s = 0, 14 do
    if s ~= self.balls[1].spot and s ~= self.balls[2].spot then free[#free + 1] = s end
  end
  local s = free[rand(#free) + 1] or 7
  ball.x, ball.y, ball.spot = SPOTS[s + 1][1], SPOTS[s + 1][2], s
end

-- ov96_02212F94: a ball's half of two balls meeting
local function meet(a, b, which)
  if a.speed <= 3 and b.speed > 3 then
    a.state, a.idx, a.dur, a.kick, a.speed, a.row = b.state, b.idx, b.dur, b.kick, b.speed, b.row
  else
    a.state, a.idx, a.dur, a.kick, a.speed, a.row = 0, 0, 30, 1, 3, 0
  end
  local dx, dy = a.x - b.x, a.y - b.y
  if dx == 0 and dy == 0 then dx, dy = 0, which == 0 and -1 or 1 end
  launch(a, dx, dy)
  if b.toucher < NOBODY then a.toucher = b.toucher end
end

-- 02212B94: the balls' tick
function M:stepBalls()
  local b2 = self.balls[2]
  if b2.kind == 0 and self.timer <= SECOND_BALL then
    b2.state, b2.kind = 3, 1
    self.secondWind = 90
    se(self, SE.drop)
  end
  for bi, ball in ipairs(self.balls) do
    if ball.kind ~= 0 then
      if ball.state == 3 then
        ball.spawnT = ball.spawnT + 1
        if ball.spawnT >= SPAWN_TICKS then ball.spawnT, ball.state = 0, 0 end
      elseif ball.state == 1 then
        ball.wait = ball.wait - 1
        if ball.wait <= 0 then
          local fresh = self:freshBall()
          local keepSpot = ball.spot
          for k, v in pairs(fresh) do ball[k] = v end
          ball.spot = keepSpot
          self:respawn(ball)
          if bi == 1 then
            local base = (self.timer >= 1200 and 0) or (self.timer >= 600 and 5) or (self.timer >= 300 and 10) or 25
            local chance = math.min(100, base + self.misses)
            if rand(100) < chance then
              ball.kind, self.misses = 2, 0
            else
              ball.kind = 1
              if self.misses < 100 then self.misses = self.misses + 1 end
            end
          else
            ball.kind = 1
          end
          se(self, (bi == 1 and ball.kind == 2) and SE.dropGold or SE.drop)
        end
      elseif ball.speed ~= 0 then
        local ox, oy = ball.x, ball.y
        ball.x, ball.y = ball.x + ball.vx, ball.y + ball.vy
        if ball.speed >= LIVE[ball.power] then
          ball.state = ball.kick == 2 and 2 or 0
        else
          ball.state, ball.dmg = 0, 0
        end
        local tab = (ball.kick == 2 and SHOT) or (ball.kick == 1 and KICK) or nil
        local row = tab and tab[ball.row]
        ball.speed = row and row[ball.idx + 1] or 0
        launch(ball, ball.dx, ball.dy)
        ball.idx = ball.idx + 1
        if ball.idx >= ball.dur then
          ball.vx, ball.vy, ball.dx, ball.dy, ball.kick, ball.speed = 0, 0, 0, 0, 0, 0
        elseif ball.speed == 0 then
          ball.dx, ball.dy, ball.idx, ball.dur, ball.kick = 0, 0, 0, 0, 0
        end
        ball.wall = false
        local code, x, y = walls(ball.x, ball.y, ox, oy, 8, false)
        if code ~= 0 and x then ball.x, ball.y, ball.wall = x, y, true end
        if code == 1 or code == 2 then ball.dx, ball.vx = -ball.dx, -ball.vx
        elseif code == 3 or code == 4 then ball.dy, ball.vy = -ball.dy, -ball.vy end
      else
        ball.state, ball.dmg, ball.power, ball.kick = 0, 0, 0, 0
      end
    end
  end
  -- two balls meeting (ov96_02212F0C)
  local a, b = self.balls[1], self.balls[2]
  local function inPlay(x) return x.kind ~= 0 and x.state ~= 1 and x.state ~= 3 end
  if inPlay(a) and inPlay(b) and mag(a.x - b.x, a.y - b.y) <= ballRadius(a) + 8 then
    local copy = {}
    for k, v in pairs(a) do copy[k] = v end
    meet(a, b, 0)
    meet(b, copy, 1)
  end
end

-- 022127F4: the balls against the Pokemon, then the posts
function M:ballContacts()
  for _, ball in ipairs(self.balls) do
    if ball.kind ~= 0 and (ball.state == 0 or ball.state == 2) then
      local br = ballRadius(ball)
      for i, mp in ipairs(self.mons) do
        local m = i - 1
        local bx, by = mp.x, mp.y - mp.yoff
        if mag(bx - ball.x, by - ball.y) <= mp.radius + br then
          if ball.latch[m] and ball.wall then
            -- against a wall: not again
          elseif mp.knock == 3 or mp.knock == 2 then
            -- being knocked: nothing
          else
            local nx, ny = ball.x - bx, ball.y - by
            local n = mag(nx, ny)
            if n > 0 then nx, ny = nx / n, ny / n end
            if ball.state == 2 then
              if ball.toucher ~= m then
                self:powerHit(mp, ball, nx, ny)
                ball.latch[m] = true
              end
            else
              if mp.dx ~= 0 or mp.dy ~= 0 then
                local inCone = mp.dx * nx + mp.dy * ny >= math.cos(math.rad(mp.cone))
                if mp.state == 1 and inCone then
                  -- the Power Shot
                  ball.state, ball.kick, ball.row, ball.dmg, ball.power = 2, 2, mp.skill, mp.damage, mp.power
                  ball.speed = SHOT[mp.skill][1]
                  mp.knock, mp.kx, mp.ky, mp.kf = 1, -nx, -ny, KICK_RECOIL
                  mp.state = 0
                  mp.hits = mp.hits + 1
                  se(self, SE.power)
                  self:addFx("shot", ball.x, ball.y)
                else
                  ball.kick, ball.row = 1, mp.skill
                  ball.speed = KICK[mp.skill][1]
                end
                ball.idx, ball.dur = 1, 30
              end
              launch(ball, nx, ny)
              ball.toucher = m
              ball.latch[m] = true
            end
          end
        else
          ball.latch[m] = false
        end
      end
      -- the posts (radius 8): the first one hit reflects the ball
      for _, p in ipairs(POSTS) do
        if mag(p[1] - ball.x, p[2] - ball.y) <= 8 + br then
          local nx, ny = p[1] - ball.x, p[2] - ball.y
          local n = mag(nx, ny)
          if n > 0 then
            nx, ny = nx / n, ny / n
            local d = ball.vx * nx + ball.vy * ny
            if d > 0 then
              ball.vx, ball.vy = ball.vx - 2 * d * nx, ball.vy - 2 * d * ny
              local v = mag(ball.vx, ball.vy)
              if v > 0 then ball.dx, ball.dy = ball.vx / v, ball.vy / v end
            end
          end
          break
        end
      end
    end
  end
end

-- a Live Power Shot meets a Pokemon (022127F4 _022128E8)
function M:powerHit(mp, ball, nx, ny)
  local left = mp.stamina - ball.dmg
  mp.knock, mp.kt, mp.kf, mp.kx, mp.ky = 3, POWER_STUN, POWER_KNOCK, -nx, -ny
  if left <= 0 then
    mp.stamina, mp.state, mp.faintT = 0, 2, FAINT_TICKS
    mp.missed = true
    if mp.team == 1 then se(self, SE.faint) end
  else
    mp.stamina = left
  end
  self:addFx("spark", mp.x, mp.y - mp.yoff)
end

-- 022130EC: a ball over a goal line
function M:goals()
  for bi, ball in ipairs(self.balls) do
    if ball.kind ~= 0 and (ball.state == 0 or ball.state == 2) then
      local px, py = trunc(ball.x), trunc(ball.y)
      local g = quarter(px, py)
      local L = GOAL_LINE[g + 1]
      if side(L[1][1], L[1][2], L[2][1], L[2][2], px, py) then
        ball.state, ball.wait = 1, GOAL_TICKS
        ball.vx, ball.vy, ball.speed = 0, 0, 0
        local m = ball.toucher
        if m ~= NOBODY then
          local mp = self.mons[m + 1]
          local tt = mp.team
          local goalTeam = self.teams[g + 1]
          local scorer = self.teams[tt]
          if g + 1 == tt then
            mp.points = math.max(0, mp.points - 1)
            scorer.score = math.max(0, scorer.score - 1)
            mp.missed = true
            mp.impede = (mp.impede or 0) + 1   -- kind 8 (022130EC)
            self:plate(tt, "own")
          else
            local v = ball.kind == 2 and 2 or 1
            if mp.points + v <= 99 then mp.points = mp.points + v end
            if scorer.score + v <= 99 then scorer.score = scorer.score + v end
            goalTeam.score = math.max(0, goalTeam.score - 1)
            mp.goals = mp.goals + 1
            self:plate(tt, ball.kind == 2 and "plus2" or "plus1")
            self:plate(g + 1, "minus")
          end
          -- 022123B0: the net, the banner, the sound
          self:addFx("net", NET[g + 1][1], NET[g + 1][2], g + 1)
          if tt == 1 and g ~= 0 then
            self:addFx("banner", BANNER[g + 1][1], BANNER[g + 1][2], g + 1)
            se(self, SE.myGoal)
          else
            se(self, SE.goal)
          end
        end
      end
    end
  end
end

-- 02214278: a name plate flashes "+1" / "+2" / "-1" for 30 ticks
function M:plate(t, kind)
  self.teams[t].plate = { kind = kind, t = 0 }
end

-- ------------------------------------------------------------------- AI --

-- ov96_02214ABC: the CPU team's roles
function M:sortRoles(team)
  local a, b = {}, {}
  for k = 1, 3 do
    local mp = team.members[k]
    a[k] = mp.skill + mp.maxStamina
    b[k] = mp.skill + mp.power
  end
  -- the cartridge compares neighbours only: the last k with a[k-1] < a[k]
  local r0 = 1
  for k = 2, 3 do if a[k - 1] < a[k] then r0 = k end end
  local o1, o2
  if r0 == 1 then if b[2] >= b[3] then o1, o2 = 2, 3 else o1, o2 = 3, 2 end
  elseif r0 == 2 then if b[1] >= b[3] then o1, o2 = 1, 3 else o1, o2 = 3, 1 end
  else if b[1] >= b[2] then o1, o2 = 1, 2 else o1, o2 = 2, 1 end end
  return { { mon = team.members[r0], wait = 0 }, { mon = team.members[o1], wait = 0 }, { mon = team.members[o2], wait = 0 } }
end

local function freeQuarter(ball)
  if ball.state == 0 and ball.kind ~= 0 then return q96(128, 96, trunc(ball.x), trunc(ball.y)) end
  return 4
end

-- ov96_02215650: the Pokemon is behind the ball for a shot away from its
-- own corner (in its own quarter) / towards the quarter's corner
local function behind(ball, mp, mq, team)
  local rel = q96(trunc(ball.x), trunc(ball.y), trunc(mp.x), trunc(mp.y))
  local want = team
  if team ~= mq then want = 3 - mq end
  return rel == want
end

-- ov96_0221567C
local function notPast(ball, mp, mq, team)
  if team ~= mq then return false end
  local rel = q96(trunc(ball.x), trunc(ball.y), trunc(mp.x), trunc(mp.y))
  return rel ~= 3 - team
end

local function touching(mp, ball)       -- ov96_022156E8 (ground point)
  return mag(mp.x - ball.x, mp.y - ball.y) < mp.radius + ballRadius(ball)
end

local function goAt(mp, ball, dash)
  mp.tx, mp.ty = ball.x, ball.y
  if dash then mp.state = 1 end
end

-- ov96_02214DBC
local function strike(mp, ball, code, mq)
  local r = rand(100)
  if code == 0 or code == 8 then return 0 end
  if code == 1 or code == 9 then
    if mq ~= 4 then
      local spot = HOME[3 - mq][1]
      mp.tx, mp.ty = spot[1], spot[2]
    end
    return 0
  end
  if code == 2 then
    if r < 60 then return 0 end
    goAt(mp, ball, r >= 80)
    return 10
  end
  if code == 3 then
    if r < 20 then return 0 end
    goAt(mp, ball, r >= 90)
    return 3
  end
  if code == 4 or code == 13 then goAt(mp, ball, true) end
  return 0
end

-- ov96_02215058
local function guard(mp, ball, code, team)
  if code == 6 or code == 11 then
    local spots = HOME[team - 1]
    for _, s in ipairs(spots) do
      if math.abs(trunc(mp.x) - s[1]) <= 8 and math.abs(trunc(mp.y) - s[2]) <= 8 then return 0 end
    end
    local s
    if rand(2) == 0 then s = spots[1] elseif rand(2) == 0 then s = spots[2] else s = spots[3] end
    mp.tx, mp.ty = s[1] + 8 - rand(17), s[2] + 8 - rand(17)
    return 6
  end
  if code == 7 or code == 12 then
    mp.tx, mp.ty = ball.x, ball.y
    if rand(100) < 80 then mp.state = 1 end
    return 10
  end
  return 0
end

-- ov96_02215478: off to the emptiest quarter (neighbour comparisons)
function M:wander(mp, team)
  local counts = { [0] = 0, 0, 0, 0 }
  for _, o in ipairs(self.mons) do
    local q = q96(128, 96, trunc(o.x), trunc(o.y))
    counts[q] = counts[q] + 1
  end
  local pick = 0
  for i = 1, 3 do if counts[i - 1] > counts[i] and i ~= team then pick = i end end
  local rx, ry = rand(64), rand(32)
  local x = (pick == 0 or pick == 2) and 128 - rx or 128 + rx
  local y = (pick == 0 or pick == 1) and 96 - ry or 96 + ry
  mp.tx, mp.ty = x, y
  return 10
end

-- pick between the two balls' codes; equal ones: the FARTHER ball (as the
-- cartridge's compare runs)
function M:pickBall(mp, c1, c2, flag)
  local f1, f2 = c1 == flag, c2 == flag
  if f1 == f2 then
    local a, b = self.balls[1], self.balls[2]
    if mag(mp.x - a.x, mp.y - a.y) >= mag(mp.x - b.x, mp.y - b.y) then return a, c1 end
    return b, c2
  end
  if c1 >= c2 then return self.balls[1], c1 end
  return self.balls[2], c2
end

-- 02214EB4: role 0
function M:keeper(mp, team)
  if mp.state ~= 0 or mp.knock ~= 0 then return 0 end
  local mq = q96(128, 96, trunc(mp.x), trunc(mp.y))
  local codes = {}
  for b, ball in ipairs(self.balls) do
    local bq = freeQuarter(ball)
    if bq == 4 then codes[b] = 5
    elseif team == bq then codes[b] = notPast(ball, mp, mq, team) and 7 or 6
    else codes[b] = 6 end
  end
  local ball, code = self:pickBall(mp, codes[1], codes[2], 7)
  return guard(mp, ball, code, team)
end

-- 02214C3C: role 1
function M:striker(mp, team)
  if mp.state ~= 0 or mp.knock ~= 0 then return 0 end
  local mq = q96(128, 96, trunc(mp.x), trunc(mp.y))
  local codes = {}
  for b, ball in ipairs(self.balls) do
    local bq = freeQuarter(ball)
    if bq == 4 then codes[b] = 0
    elseif touching(mp, ball) then codes[b] = 1
    elseif mq == bq then codes[b] = behind(ball, mp, mq, team) and 4 or 3
    else codes[b] = 2 end
  end
  if codes[1] >= codes[2] then return strike(mp, self.balls[1], codes[1], mq) end
  return strike(mp, self.balls[2], codes[2], mq)
end

-- 02215184: role 2
function M:rover(mp, team, roles)
  if mp.state ~= 0 or mp.knock ~= 0 then return 0 end
  local mq = q96(128, 96, trunc(mp.x), trunc(mp.y))
  local bq, codes = {}, {}
  for b, ball in ipairs(self.balls) do
    bq[b] = freeQuarter(ball)
    codes[b] = 8
    if bq[b] ~= 4 and not touching(mp, ball) and mq == bq[b] and behind(ball, mp, mq, team) then codes[b] = 13 end
  end
  if codes[1] == 13 then return strike(mp, self.balls[1], 13, mq) end
  if codes[2] == 13 then return strike(mp, self.balls[2], 13, mq) end
  if roles[1].mon.stamina >= 50 then return self:wander(mp, team) end
  for b, ball in ipairs(self.balls) do
    if bq[b] == 4 then codes[b] = 10
    elseif team == bq[b] then codes[b] = behind(ball, mp, mq, team) and 12 or 11
    else codes[b] = 11 end
  end
  local ball, code = self:pickBall(mp, codes[1], codes[2], 7)
  if code == 10 then return self:wander(mp, team) end
  return guard(mp, ball, code, team)
end

-- 02214B84: one decision a tick
function M:stepAI()
  local ai = self.ai
  ai.count = ai.count + 1
  if ai.count >= 3 then ai.active, ai.count = true, 0 end
  if not ai.active then return end
  local t = 2 + ai.turn
  local roles = ai.roles[t]
  local entry = roles[ai.role + 1]
  if entry.wait == 0 then
    local mp, team = entry.mon, t - 1
    local was = mp.state
    local w
    if ai.role == 0 then w = self:keeper(mp, team)
    elseif ai.role == 1 then w = self:striker(mp, team)
    else w = self:rover(mp, team, roles) end
    entry.wait = w or 0
    if mp.state == 1 and was ~= 1 then mp.dashes = mp.dashes + 1 end
  else
    entry.wait = entry.wait - 1
  end
  ai.turn = ai.turn + 1
  if ai.turn >= 3 then
    ai.turn = 0
    ai.role = (ai.role + 1) % 3
    ai.active = false
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
  self.touch = { x = px, y = py, down = true }
  return true
end
function M:touchmoved(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if px and self.touch then self.touch.x, self.touch.y = px, py end
  return true
end
function M:touchreleased(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if self.touch then
    if px then self.touch.x, self.touch.y = px, py end
    self.touch.down = false
  end
  return true
end

-- 02213364: the team's own Pokemon nearest the point within 80 px
function M:pick(px, py)
  local best, bestD
  for k, mp in ipairs(self.teams[1].members) do
    local d = mag(trunc(mp.x) - px, trunc(mp.y) - py)
    if d < TOUCH_R and (not bestD or d < bestD) then best, bestD = k, d end
  end
  return best
end

-- 02211B94: the player's touch this tick
function M:stepTouch()
  local tc = self.touch
  local down = tc and tc.down
  local fresh = false
  if down then
    if not self.held then fresh, self.held = true, true end
  else
    self.held = false
  end
  if fresh then
    local k = self:pick(tc.x, tc.y)
    if k then
      local mp = self.teams[1].members[k]
      if mp.state ~= 2 and mp.state ~= 1 and mp.knock == 0 then
        self.sel, self.heldT = k, 0
        self.padSel = k
      end
    end
  elseif down then
    if self.sel then
      if self.heldT < 20 then self.heldT = self.heldT + 1 end
      local mp = self.teams[1].members[self.sel]
      mp.tx, mp.ty = trunc(tc.x), trunc(tc.y)
    end
  else
    if self.sel then
      local mp = self.teams[1].members[self.sel]
      if mp.state ~= 3 and mp.state ~= 2 then
        if self.heldT <= DASH_HOLD and (mp.tx ~= mp.x or mp.ty ~= mp.y) then
          mp.state = 1
          mp.dashes = mp.dashes + 1
        else
          mp.state = 0
        end
      end
      self.heldT, self.sel = 0, nil
    end
    if tc and not tc.down then self.touch = nil end
  end
end

-- the pad: a direction walks the chosen Pokemon, A dashes it, R / B the next
function M:stepPad()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("r") or input:wasPressed("b") then self.padSel = self.padSel % 3 + 1 end
  local mp = self.teams[1].members[self.padSel]
  if not mp or mp.state == 2 or mp.knock ~= 0 then return end
  local dx = (input:isDown("right") and 1 or 0) - (input:isDown("left") and 1 or 0)
  local dy = (input:isDown("down") and 1 or 0) - (input:isDown("up") and 1 or 0)
  if input:wasPressed("a") and mp.state ~= 3 and mp.state ~= 1 then
    local fx = ({ [LEFT] = -1, [RIGHT] = 1 })[mp.facing] or 0
    local fy = ({ [UP] = -1, [DOWN] = 1 })[mp.facing] or 0
    if dx ~= 0 or dy ~= 0 then fx, fy = dx, dy end
    local n = mag(fx, fy)
    mp.tx, mp.ty = trunc(mp.x + fx / n * 48), trunc(mp.y + fy / n * 48)
    mp.state = 1
    mp.dashes = mp.dashes + 1
  elseif (dx ~= 0 or dy ~= 0) and mp.state ~= 1 then
    local n = mag(dx, dy)
    mp.tx, mp.ty = trunc(mp.x + dx / n * 16), trunc(mp.y + dy / n * 16)
  end
end

-- ------------------------------------------------------------------- loop --

function M:update()
  self.t = self.t + 1
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
    -- the FINISH (021E667C, 022117EC state 2)
    if self.t % 2 == 0 and not self.cd:finishing() then return self:finish() end
    return
  end
  if self.over then
    self.over = self.over - 1
    if self.over <= 0 then return self:finish() end
    return
  end
  -- the pad reads presses every frame (wasPressed is a frame's)
  self:stepPad()
  if self.t % 2 == 0 then self:tick() end
end

-- 02211B94: one tick
function M:tick()
  self.ticks = self.ticks + 1
  if self.timer > 0 then self.timer = self.timer - 1 end
  self:stepTouch()
  self:stepAI()
  self:stepMons()
  self:stepBalls()
  self:ballContacts()
  self:goals()
  self:tiredness()
  for _, team in ipairs(self.teams) do
    if team.plate then
      team.plate.t = team.plate.t + 1
      if team.plate.t > 30 then team.plate = nil end
    end
  end
  if self.secondWind then
    self.secondWind = self.secondWind - 1
    if self.secondWind <= 0 then self.secondWind = nil end
  end
  for i = #self.fx, 1, -1 do
    local e = self.fx[i]
    e.t = e.t + 1
    if e.t > e.life then table.remove(self.fx, i) end
  end
  if self.timer <= 0 and not self.over then
    self.over = 60; self.touch = nil
    if self.cd then self.cd:startFinish(Rec.isNew(self.game, 9, self.teams[1].score % 256)) end
  end
end

local FX_LIFE = { dust = 18, spark = 12, shot = 9, net = 13, banner = 69 }
function M:addFx(kind, x, y, goal)
  self.fx[#self.fx + 1] = { kind = kind, x = x, y = y, t = 0, life = FX_LIFE[kind] or 20, goal = goal }
end

-- ov96_0221A730: the place's points + 5 a goal, at most 200
function M:pointsFor(t)
  local mine = self.teams[t].score
  local above, level = 0, 0
  for u, team in ipairs(self.teams) do
    if u ~= t then
      if team.score > mine then above = above + 1 elseif team.score == mine then level = level + 1 end
    end
  end
  local place = math.min(4, above + level + 1)
  return math.min(200, PLACE_AP[place] + 5 * mine)
end

function M:finish()
  if self.done then return end
  self.done = true
  local points, stats = {}, {}
  for t, team in ipairs(self.teams) do
    points[t] = self:pointsFor(t)
    stats[t] = {}
    for k = 1, 3 do
      local mp = team.members[k]
      stats[t][k] = { miss = mp.missed, score = mp.goals, dash = mp.dashes, hit = mp.hits, impede = mp.impede or 0 }
    end
  end
  self.game.stack:pop()
  if self.onDone then
    self.onDone({ points = points, goals = { self.teams[1].score, self.teams[2].score, self.teams[3].score, self.teams[4].score }, stats = stats,
      record = self.teams[1].score % 65536 })
  end
end

-- ------------------------------------------------------------------- draw --

function M:img(key)
  local rec = self.d[key]
  if type(rec) == "table" and rec.image and not rec.path then
    -- decoded in memory (a harness's ROM read): an ImageData, made once
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

function M:sprite(key, x, y, r)
  local img, rec = self:img(key)
  if not img then return false end
  local ox = type(rec) == "table" and tonumber(rec.originX) or 0
  local oy = type(rec) == "table" and tonumber(rec.originY) or 0
  if r and r ~= 0 then
    love.graphics.draw(img, math.floor(x), math.floor(y), r, 1, 1, -ox, -oy)
  else
    love.graphics.draw(img, math.floor(x + ox), math.floor(y + oy))
  end
  return true
end

-- a sequence's frame at `tick` (objSeq durations), looping or held
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

function M:anim(set, seq, x, y, tick, hold, r)
  local f = self:seqFrame(set, seq, tick, hold)
  local xy = self.d.objXY and self.d.objXY[set]
  xy = xy and (xy[seq] or xy[tostring(seq)])
  local off = xy and (xy[f + 1] or xy[tostring(f + 1)])
  if off then x, y = x + (tonumber(off[1]) or 0), y + (tonumber(off[2]) or 0) end
  return self:sprite(("%s_%d_%d"):format(set, seq, f), x, y, r)
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

-- the walking-Pokemon sheet (gen4_follow_mon: up x2, down x2, left x2,
-- right x2), feet at (x, y)
local WALK = { [UP] = 0, [DOWN] = 2, [LEFT] = 4, [RIGHT] = 6 }
function M:walker(mon, facing, x, y, step)
  local rec = self.game.data.gen4_follow_mon
  if type(rec) ~= "table" or not rec.lut then return false end
  local ok, F = pcall(require, "src.import.Gen4HgssFollowMon")
  if not ok then return false end
  local idx = F.index(rec, tonumber(mon.species), tonumber(mon.form) or 0, false)
  local sheet = rec.sheets and (rec.sheets[idx] or rec.sheets[tostring(idx)])
  local img = sheet and self:image((mon.shiny and sheet.shiny) or sheet.normal)
  if not img then return false end
  local fw, fh = tonumber(sheet.frameWidth) or 32, tonumber(sheet.frameHeight) or 32
  local f = (WALK[facing] or 2) + (step % 2)
  local iw = img:getWidth()
  local qx, qy
  if iw >= fw * 8 then qx, qy = f * fw, 0 else qx, qy = 0, f * fh end
  local q = love.graphics.newQuad(qx, qy, fw, fh, img:getDimensions())
  love.graphics.draw(img, q, math.floor(x - fw / 2), math.floor(y - fh + 4))
  return true
end

local PLATE_TEXT = { plus1 = "+1", plus2 = "+2", minus = "-1", own = "-1" }

-- the four name plates along the touch screen's top (windows ov96_0221D360,
-- 02214044 / 02214278)
function M:drawPlates()
  local g = love.graphics
  local Font = require("src.render.Font")
  for t, team in ipairs(self.teams) do
    local x = (t - 1) * 64
    local text = team.name
    if team.plate then
      text = PLATE_TEXT[team.plate.kind] or text
      if math.floor(team.plate.t / 5) % 2 == 0 then
        local c = TEAM_RGB[t]
        g.setColor(1, 1, 1, 0.35)
        g.rectangle("fill", x + 4, 2, 56, 12)
        g.setColor(c[1], c[2], c[3], 1)
      end
    end
    g.setColor(1, 1, 1, 1)
    Font.draw(tostring(text):sub(1, 7), x + 6, 3)
  end
end

-- the touch screen: the pitch, the balls, the Pokemon
function M:drawField()
  local g = love.graphics
  g.setColor(0.4, 0.75, 0.25, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local pitch = self:img("field_b")
  if pitch then g.draw(pitch, 0, 0) end
  local bars = self:img("field")
  if bars then g.draw(bars, 0, 0) end
  -- the nets (obj seq 1, turned per corner) and the posts (2 + 2t + k)
  for i = 1, 4 do
    local hit
    for _, e in ipairs(self.fx) do if e.kind == "net" and e.goal == i then hit = e end end
    if hit then self:anim("obj", 15, NET[i][1], NET[i][2], hit.t, true, NET_TURN[i] * 2 * math.pi)
    else self:anim("obj", 1, NET[i][1], NET[i][2], self.ticks, false, NET_TURN[i] * 2 * math.pi) end
  end
  for i, p in ipairs(POSTS) do self:anim("obj", 1 + i, p[1], p[2], 0) end
  -- everything standing, back to front; the player's own team over the rest
  -- (0221457C)
  local list = {}
  for _, mp in ipairs(self.mons) do
    list[#list + 1] = { y = mp.y + (mp.team == 1 and 1000 or 0), f = function() self:drawMon(mp) end }
  end
  for _, ball in ipairs(self.balls) do
    if ball.kind ~= 0 and ball.state ~= 1 then
      list[#list + 1] = { y = ball.y, f = function() self:drawBall(ball) end }
    end
  end
  table.sort(list, function(a, b) return a.y < b.y end)
  for _, e in ipairs(list) do e.f() end
  for _, e in ipairs(self.fx) do
    if e.kind == "dust" then self:anim("obj", 14, e.x, e.y, e.t, true)
    elseif e.kind == "spark" then self:anim("obj", 16, e.x, e.y - 12, e.t, true)
    elseif e.kind == "banner" then self:anim("obj", (e.goal == 1 or e.goal == 3) and 17 or 18, e.x, e.y, e.t, true) end
  end
  self:drawPlates()
  -- the chosen Pokemon and the drag
  local sel = self.sel or (not self.touch and self.padSel)
  local mp = sel and self.teams[1].members[sel]
  if mp and self.sel and self.touch then
    g.setColor(1, 1, 1, 0.7)
    g.setLineWidth(1)
    g.line(mp.x, mp.y - mp.yoff, self.touch.x, self.touch.y)
  end
  if mp and not self.touch then
    g.setColor(1, 1, 1, 0.8)
    g.polygon("fill", mp.x - 3, mp.y - 2 * mp.yoff - 22, mp.x + 3, mp.y - 2 * mp.yoff - 22, mp.x, mp.y - 2 * mp.yoff - 18)
  end
  g.setColor(1, 1, 1, 1)
  -- the shared 3-2-1 / FINISH (main engine = this screen, surface at 0)
  if self.cd then self.cd:draw(0) end
end

function M:drawBall(ball)
  local x, y = ball.x, ball.y
  if ball.state == 3 then
    -- 02213F5C: dropping in (ov96_0221DC80 bounce)
    local bounce = { 0, 4, 2, 1, 0, 1, 0, 1 }
    y = y + (bounce[(ball.spawnT % 8) + 1] or 0)
  end
  if ball.kind == 2 then self:anim("obj", 11, x, y, self.ticks)
  else self:anim("obj", 10, x, y, self.ticks) end
  if ball.state == 2 then self:anim("obj", 13, x, y, self.ticks) end
end

function M:drawMon(mp)
  local g = love.graphics
  local c = TEAM_RGB[mp.team]
  g.setColor(c[1], c[2], c[3], 0.8)
  g.ellipse("line", mp.x, mp.y, mp.radius * 0.8 + 2, mp.radius * 0.4 + 1)
  g.setColor(1, 1, 1, 1)
  local moving = mp.dx ~= 0 or mp.dy ~= 0
  local step = moving and math.floor(self.ticks / (mp.state == 1 and 3 or 5)) or math.floor(self.ticks / 15)
  if mp.mon then
    if mp.state == 2 then g.setColor(0.7, 0.7, 0.7, 1) end
    if not self:walker(mp.mon, mp.facing, mp.x, mp.y, step) then
      self:monIcon(mp.mon, mp.x, mp.y + 4, math.floor(self.ticks / 8))
    end
    g.setColor(1, 1, 1, 1)
  end
  -- the status sprite (02211F38: 8 px up, 16 for the big size class)
  local head = mp.y - 16 - (mp.class == 3 and 16 or 8)
  if mp.state == 3 then self:anim("obj", 12, mp.x, head, self.ticks)
  elseif mp.state == 2 then self:anim("obj", 16, mp.x, head, self.ticks) end
end

local function drawPart(img, x, y, qx, qy, qw, qh)
  if qw <= 0 or qh <= 0 then return end
  love.graphics.draw(img, love.graphics.newQuad(qx, qy, qw, qh, img:getDimensions()), x + qx, y + qy)
end

-- the score's two digits (0221497C: /a/2/3/4 screen 10's glyphs, 4 x 8
-- tiles, at tile (6 + 4 i, 10))
function M:drawScore(value)
  local img = self:img("digits")
  if not img then return end
  value = math.max(0, math.min(99, value))
  local ds = { math.floor(value / 10), value % 10 }
  for i, dgt in ipairs(ds) do
    local sx, sy = (dgt % 5) * 32, math.floor(dgt / 5) * 64
    love.graphics.draw(img, love.graphics.newQuad(sx, sy, 32, 64, img:getDimensions()), 48 + 32 * (i - 1), 80)
  end
end

function M:secondWindText()
  if self.windText == nil then
    local ok, s = pcall(function() return require("src.import.Gen4Text").resolve(self.game.data, 309, 311, self.game) end)
    s = ok and type(s) == "string" and s:gsub("{[^}]*}", "") or nil
    self.windText = (s and s ~= "") and s or "Second wind!"
  end
  return self.windText
end

-- the top screen (022146C0 / 0221490C / 0221497C / 02214718)
function M:drawTop()
  local g = love.graphics
  local Font = require("src.render.Font")
  g.setColor(0.85, 0.9, 0.95, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local a = self:img("top")
  if a then g.draw(a, 0, 0) end
  local b = self:img("top_b")
  if b then
    -- layer B without its "99" (the digit rect is drawn over)
    drawPart(b, 0, 0, 0, 0, 256, 80)
    drawPart(b, 0, 0, 0, 144, 256, 48)
    drawPart(b, 0, 0, 0, 80, 48, 64)
    drawPart(b, 0, 0, 112, 80, 144, 64)
  end
  self:drawScore(self.teams[1].score)
  -- the team's flag (ov96_0221D660: (54, 152), seq team + 1)
  self:anim("top", 1, 54, 152, 0)
  Font.draw(tostring(self.teams[1].name):sub(1, 10), 64, 146)
  if self.timer > SECOND_BALL then
    -- the clock (ov96_0221D66C (176, 128) seq 5; digits at 192 / 208)
    self:anim("top", 5, 176, 128, 0)
    local secs = math.floor(self.timer / 30)
    Font.draw(("%02d"):format(secs % 100), 188, 123)
  else
    -- message 311 in window ov96_0221D658 (152, 112)
    g.setColor(1, 1, 1, 1)
    Font.draw(self:secondWindText(), 156, 116)
  end
  if self.countdown > 0 and not self.cd then
    Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 40)
  end
end

function M:draw()
  local g = love.graphics
  local Font = require("src.render.Font")
  if SecondScreen.separate(self.game) then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawField() end)
  else
    local input = self.game.input
    if self.showTop or (input and (input:isDown("select") or input:isDown("l"))) then self:drawTop() else self:drawField() end
    if self.countdown > 0 and not self.cd then Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 88) end
    if self.secondWind then Font.draw(self:secondWindText(), 88, 40) end
    if self.over and not self.cd then Font.draw("FINISH!", 104, 88) end
  end
  g.setColor(1, 1, 1, 1)
end

return M
