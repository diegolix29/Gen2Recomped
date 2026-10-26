-- HEARTGOLD / SOULSILVER POKeATHLON: PENNANT CAPTURE (event 1, sub-app
-- ov96_0221A8D0 = { 022047EC init, 02204DE8 main, 02204DF8 vblank, 02204E58
-- exit }, state table ov96_0221DC50 = { 022052B0, 0220549C, 02205520 };
-- pokeheartgold asm/overlay_96.s 0x022047EC..0x02209130; the reading is
-- written up in scratch_claude/athlon/NOTES.md, "## Pennant Capture"). Art and
-- tables: `gen4_hgss_pennant` (src/import/Gen4HgssPokeathlonPennantArt.lua).
--
-- The game logic runs at 30 ticks a second (the clock shows timer / 30,
-- 02208740); this module steps it every other frame.
--
-- READ FROM CODE:
--   * four teams, one Pokemon of each on the field; the field is /a/2/2/4's
--     512 x 512 screen, the touch screen a 256 x 192 window centred on the
--     player's Pokemon (02205D30); team t starts at (208 + 32 t, 416) facing
--     up (022047EC case 4)
--   * THE CLOCK: 1800 ticks (60 s), one off a tick (022055AC); at 0 the
--     event ends (02205C94 -> 02207C64)
--   * THE FLICK (022055AC): a touch within 80 px of the Pokemon (02205DD4 /
--     021EB0CC, radius ov96_021E6104 = 0x50) starts a drag; let go within 30
--     ticks and the drag (end - start) x Skill x Speed / 8 (params[5 + SKILL]
--     / 10 x params[10 + SPEED] / 10) is ADDED to the velocity, which is then
--     held to the top speed params[20 + SPEED] (9..11 px a tick); the
--     Pokemon faces the way it now goes (022079B8: up / down / left / right
--     by quarter-turns). A touch held 255 ticks brakes everyone (heap 0x510).
--   * MOVING (02205E30): position += velocity; held inside the field
--     (x 144..368, y 104..392, the start lane x 208..304 down to 416);
--     friction 0.6 px a tick a tick (6.0 x 0.1, + 3.0 while braking)
--   * BLOCKS (02207300 / 0220703C): each 32 x 32 block of the layout, grown by
--     the Pokemon's radius: crossing an edge stops it on the edge, a corner
--     pushes it out, inside pushes it to the nearest side; the velocity
--     component into the block bounces at x -0.3
--   * FLAGS (02207818 / 02207870 / 022078B0): five on the field, put at the
--     layout's 20 spots in turn (spot 0, 1, 2 ...); a Pokemon within its
--     radius + 8 px takes one (one a tick) unless it carries 9 already
--   * HOME (02207B8C): at y > 408 inside the lane with flags and not dizzy it
--     DEPOSITS: 10 steps of 5 ticks, one flag counted a step (the team's
--     score, cap 999), then the TAG: it drops out (32 ticks, 8 px a tick),
--     the next of the three comes in (32 ticks) (02206C90 / 02206D58 /
--     02208448 / 02208608 -- the top screen's swap, ~10 ticks)
--   * TACKLES (02207418 / 02207A34): two Pokemon touching (body circles,
--     radius by size class, /a/1/7/0 member 14) -- the FASTER one, if both
--     face the same way and it moves the way it faces (it hits from behind)
--     and is not dizzy, takes 2 of the other's flags (all, if fewer; it holds
--     9 at most), stops dead and is held 18 ticks; the other is knocked on
--     at its speed x Power (params[POWER] / 10), held 6 ticks and DIZZY for
--     params[15 + STAMINA] + the hit speed ticks (no flicks, no deposit);
--     otherwise both are held 6 ticks. Speeds are cut to 11 after a hit.
--     Course counters: event 4 (a hit) for both, event 1 for the robbed one.
--   * THE RIVALS' AI (02208B34 / 02208BB8 / 02208FB8): every 6 ticks each
--     rival team in turn (one a tick) scores 48 targets around its Pokemon
--     (6 x 8 cells of 32 px, a random point in each): +7 a flag there, -3 a
--     Pokemon, -2 a decoration / block (the layout's first 20 pairs), -100
--     off the field, +4 for the cells just ahead, +3 for the far row in the
--     half it is in, and when carrying: + flags carried for the row behind
--     and +2 towards the middle; it flicks at a random best one
--   * the layout: /a/2/2/5 member LCRandom % 20 (022047EC case 5)
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 022047EC puts them on the main
--     engine at y offset 0 (021E6290 r1), the touch screen here
--     (gSystem.screensFlipped = 1, main surface at 0 -- 021EB5C8); 0220549C
--     runs the countdown, then play, then the finish with the field still
--     running (022055AC)
-- Scoring (Bulbapedia; the results app is not read): Athlete Points = flags
-- x 3, at most 200; flags still being counted at the end count (02205520).
-- No-Miss: the cartridge counts a miss each time the Pokemon is TACKLED
-- (event 1, even with no flags to lose) -- Bulbapedia says "flags taken";
-- this follows the code. Effort: hit = the Pokemon's collisions.
--
-- THE RECORD (READ FROM CODE; src/pokemon/HgssPokeathlonRecords.lua): when
-- the clock runs out 02207C64 hands ov96_021E8318 the team's flags + the
-- flags still being counted (record bits 18-27 + bits 11-15), at most 999,
-- for NEW RECORD! (021E839C, higher is better); the end state's field_5E0
-- (02205520, the same sum) is what the course's end saves.
--
-- STAND-INS, said so: without `gen4_hgss_athlon_common` the 3-2-1 is
-- text; the field Pokemon are the walking-Pokemon
-- sheets (gen4_follow_mon -- the event's own mon objects 021EA854 are not
-- read; icons when absent), drawn with the team ring under them; the sprite
-- offsets of those objects ([0x10] [0x18] [0x28]) are not read, so the AI's
-- flick runs from the Pokemon's ground point; a block corner is resolved by
-- the exact ray / circle contact (the cartridge's own sum mixes fixed-point
-- scales); the top screen's front pictures are icons and its timer digits
-- are the event's digit glyphs; the end is a short pause, not the fade.

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local TIME = 1800                         -- 0x708 ticks, 30 a second
local FLICK_HOLD = 30                     -- release within 30 ticks
local TOUCH_R = 0x50                      -- ov96_021E6104
local FRICTION, BRAKE = 0.6, 3.0          -- 6.0 x 0.1; + 3.0 (heap 0x510)
local HIT_CAP = 11                        -- speeds after a collision
local BOUNCE = -0.3                       -- 0xBFD3333333333333
local MAX_CARRY = 9
local FLAGS_ON_FIELD = 5
local AI_EVERY = 6                        -- ov96_02208AA8 [0x557]
local SE = { flick = 0x8CD, spark = 0x8A3, pick = 0x5E2, pickRival = 0x5EB, full = 0x8CE,
  count = 0x88F, dizzy = 0x890 }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local POWER, STAMINA, SKILL, SPEED = 0, 1, 2, 4
local UP, DOWN, LEFT, RIGHT = 1, 2, 3, 4

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_pennant
  return type(d) == "table" and d.params ~= nil and d.layouts ~= nil and d.field ~= nil
end

-- the performance row's raw bytes (byte 6 = the size class 1..3, byte 5 the
-- tall flag -- ov96_021E6138 / 02206380)
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

-- ov96_02206E88: a Pokemon's numbers from its stars
local function monParams(self, mon, rival)
  local p, st = self.d.params, starsOf(self.game, mon, rival)
  local raw = rawRow(self.game.data, mon)
  local class = raw and tonumber(raw[7]) or 2
  if class < 1 or class > 3 then class = 2 end
  local size = (self.d.sizes and self.d.sizes[class]) or { 10, 10 }
  return {
    mon = mon, knock = p[st[POWER]] / 10, skill = p[5 + st[SKILL]] / 10, speed = p[10 + st[SPEED]] / 10,
    dizzy = p[15 + st[STAMINA]], top = p[20 + st[SPEED]],
    body = size[1], radius = size[2], tall = raw and (tonumber(raw[6]) or 0) ~= 0,
    hits = 0, robbed = 0, deposited = 0,
  }
end

-- opts: team (three Pokemon), rivals ({3 teams of 3}), onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, ticks = 0, images = {} }, M)
  local d = game.data.gen4_hgss_pennant
  self.d = d
  local k = rand(20)
  local layout = d.layouts[k] or d.layouts[0]
  self.layoutIndex = k
  self.deco, self.blocks, self.spots = {}, {}, {}
  for _, q in ipairs(layout.deco or {}) do if q then self.deco[#self.deco + 1] = { q[1], q[2] } end end
  for _, q in ipairs(layout.blocks or {}) do if q then self.blocks[#self.blocks + 1] = { q[1], q[2] } end end
  for i = 1, 20 do self.spots[i] = (layout.spots or {})[i] or false end
  -- the AI's "things in the way" list: ov96_02208AF8 run twice over the
  -- same table, so it ends up the 10 decorations and the first 10 blocks
  self.aiAvoid = {}
  local raw = {}
  for i = 1, 10 do raw[i] = (layout.deco or {})[i] or false end
  for i = 1, 10 do raw[10 + i] = (layout.blocks or {})[i] or false end
  for i = 1, 20 do if raw[i] then self.aiAvoid[#self.aiAvoid + 1] = raw[i] end end

  self.teams = {}
  for t = 1, 4 do
    local mons = t == 1 and opts.team or (opts.rivals and opts.rivals[t - 1]) or {}
    local team = {
      index = t, x = 208 + 32 * (t - 1), y = 416, vx = 0, vy = 0, cur = 1, facing = UP,
      carried = 0, score = 0, depositLeft = 0, steps = 0, delay = 0, depositing = false,
      tag = 0, tagT = 0, lift = 0, frozen = 0, dizzy = false, dizzyT = 0, contact = {},
      blockCode = 0, fullLatch = {}, members = {}, cpu = t > 1, gotT = 0, popT = 0, lastCarried = 0,
    }
    for m = 1, 3 do team.members[m] = monParams(self, mons[m], t > 1) end
    self.teams[t] = team
  end
  -- the flags: five slots, spots handed out in turn (ov96_02207818)
  self.flags, self.nextSpot, self.flagCount = {}, 0, 0
  for i = 1, FLAGS_ON_FIELD do self.flags[i] = { active = false } end
  self:refillFlags()
  self.timer = TIME
  self.aiCount, self.aiRound, self.aiTurn = 0, false, 0
  self.fx = {}
  self.countdown = 180
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (022047EC)
  if CD.available(game) then self.cd = CD.new(game, 0) end
  self.drag = nil
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

-- 02207C38: a sound only when it happens on the touch screen
function M:seAt(id, x, y)
  local me = self.teams[1]
  local sx, sy = x - math.floor(me.x) + 128, y - math.floor(me.y) + 96
  if sx >= 0 and sx < 256 and sy >= 0 and sy < 192 then se(self, id) end
end

function M:member(team) return team.members[team.cur] end

-- ------------------------------------------------------------------ rules --

function M:refillFlags()
  while self.flagCount < FLAGS_ON_FIELD do
    local slot
    for _, f in ipairs(self.flags) do if not f.active then slot = f; break end end
    if not slot then break end
    local spot = self.spots[self.nextSpot + 1]
    slot.active, slot.spot, slot.puff = true, self.nextSpot, 0
    slot.x, slot.y = spot and spot[1] or 256, spot and spot[2] or 256
    self.nextSpot = (self.nextSpot + 1) % 20
    self.flagCount = self.flagCount + 1
  end
end

-- 022079B8: the way a velocity points, by quarter-turns
local function facingOf(vx, vy)
  if vx == 0 and vy == 0 then return UP end
  local a = math.atan2(vy, vx) / (2 * math.pi) * 65536
  if a < 0 then a = a + 65536 end
  if a <= 0x2000 or a >= 0xE000 then return RIGHT end
  if a > 0x2000 and a < 0x6000 then return DOWN end
  if a >= 0x6000 and a <= 0xA000 then return LEFT end
  return UP
end

local function mag(x, y) return math.sqrt(x * x + y * y) end

-- the flick (022055AC _022058FE): drag x Skill x Speed / 8 added, top speed
function M:flick(team, dx, dy)
  local mp = self:member(team)
  local k = mp.skill * mp.speed / 8
  local vx, vy = team.vx + dx * k, team.vy + dy * k
  local s = mag(vx, vy)
  if s > mp.top then vx, vy = vx / s * mp.top, vy / s * mp.top end
  team.vx, team.vy = vx, vy
  team.facing = facingOf(vx, vy)
  self:addFx("dust", team.x, team.y)
  self:seAt(SE.flick, team.x, team.y)
end

function M:canFlick(team)
  return team.tag == 0 and not team.dizzy and team.frozen == 0 and not team.depositing
end

-- 0220703C: one block against a move from (ox, oy) to (nx, ny); returns the
-- code (1 top 2 right 3 bottom 4 left edge, 5..8 corners, 9..12 inside) and
-- where the Pokemon ends up
local function segCross(ax, ay, bx, by, cx, cy, dx, dy)
  local rx, ry, sx, sy = bx - ax, by - ay, dx - cx, dy - cy
  local den = rx * sy - ry * sx
  if den == 0 then return nil end
  local t = ((cx - ax) * sy - (cy - ay) * sx) / den
  local u = ((cx - ax) * ry - (cy - ay) * rx) / den
  if t < 0 or t > 1 or u < 0 or u > 1 then return nil end
  return ax + t * rx, ay + t * ry
end

local function blockHit(bx, by, r, ox, oy, nx, ny)
  local x0, y0, x1, y1 = bx - 16, by - 16, bx + 16, by + 16
  -- the four edges, each pushed out by the radius (02206FA4)
  local edges = {
    { x0, y0 - r, x1, y0 - r, 1 }, { x1 + r, y0, x1 + r, y1, 2 },
    { x1, y1 + r, x0, y1 + r, 3 }, { x0 - r, y1, x0 - r, y0, 4 },
  }
  for _, e in ipairs(edges) do
    local ix, iy = segCross(e[1], e[2], e[3], e[4], ox, oy, nx, ny)
    if ix then return e[5], ix, iy end
  end
  -- the corners (ov96_0221CAE0 = 5, 6, 7, 8): back along the move to the
  -- point r from the corner
  local corners = { { x0, y0, 5 }, { x1, y0, 6 }, { x1, y1, 7 }, { x0, y1, 8 } }
  for _, c in ipairs(corners) do
    if mag(nx - c[1], ny - c[2]) <= r then
      local dx, dy = nx - ox, ny - oy
      local fx, fy = ox - c[1], oy - c[2]
      local a = dx * dx + dy * dy
      local t = 0
      if a > 0 then
        local b = 2 * (fx * dx + fy * dy)
        local cc = fx * fx + fy * fy - r * r
        local disc = b * b - 4 * a * cc
        if disc >= 0 then t = math.max(0, math.min(1, (-b - math.sqrt(disc)) / (2 * a))) end
      end
      return c[3], ox + t * dx, oy + t * dy
    end
  end
  -- inside the block itself: out by the nearest side
  if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
    local dl, dr = math.abs(x0 - nx), math.abs(x1 - nx)
    local hcode, hx = (dl < dr) and 12 or 10, (dl < dr) and (x0 - r) or (x1 + r)
    local dt, db = math.abs(y0 - ny), math.abs(y1 - ny)
    local vcode, vy = (dt < db) and 9 or 11, (dt < db) and (y0 - r) or (y1 + r)
    if math.min(dl, dr) <= math.min(dt, db) then return hcode, hx, ny end
    return vcode, nx, vy
  end
  return 0
end

-- 02207300: the blocks near the Pokemon (02206F1C: within the screen around
-- it), the first one hit
function M:blockCollide(team, ox, oy)
  local r = self:member(team).radius
  local fox, foy = math.floor(ox), math.floor(oy)
  for _, b in ipairs(self.blocks) do
    local sx, sy = b[1] - fox + 0x80, b[2] - foy + 0x60
    if sx >= -32 and sx <= 0x120 and sy >= -32 and sy <= 0xE0 then
      local code, px, py = blockHit(b[1], b[2], r, ox, oy, team.x, team.y)
      if code ~= 0 then
        if code >= 9 or code ~= team.blockCode then team.x, team.y = px, py end
        return code
      end
    end
  end
  return 0
end

-- the bounce for a block code (02205E30 jump table)
local BOUNCES = {
  [1] = { y = 1 }, [2] = { x = -1 }, [3] = { y = -1 }, [4] = { x = 1 },
  [5] = { x = 1, y = 1 }, [6] = { x = -1, y = 1 }, [7] = { x = -1, y = -1 }, [8] = { x = 1, y = -1 },
}

local function bounce(team, code)
  local b = BOUNCES[code]
  if not b then return end
  if b.x and ((b.x > 0 and team.vx > 0) or (b.x < 0 and team.vx < 0)) then team.vx = team.vx * BOUNCE end
  if b.y and ((b.y > 0 and team.vy > 0) or (b.y < 0 and team.vy < 0)) then team.vy = team.vy * BOUNCE end
end

-- the field's walls (02205E30 _02205FBE)
local function clampField(team)
  if team.x < 208 or team.x > 304 then
    team.y = math.max(104, math.min(392, team.y))
  else
    team.y = math.max(104, math.min(416, team.y))
  end
  if team.y > 392 then team.x = math.max(208, math.min(304, team.x))
  else team.x = math.max(144, math.min(368, team.x)) end
end

-- 02207A34: a tackle, when one of them hits the other from behind
function M:tackle(a, b)
  local sa, sb = mag(a.vx, a.vy), mag(b.vx, b.vy)
  local atk, vic
  if sa > sb then atk, vic = a, b elseif sa < sb then atk, vic = b, a else return false end
  if atk.facing ~= vic.facing then return false end
  if facingOf(atk.vx, atk.vy) ~= atk.facing then return false end
  if atk.dizzy then return false end
  local take = math.min(2, vic.carried)
  vic.carried = vic.carried - take
  atk.carried = math.min(MAX_CARRY, atk.carried + take)
  vic.dizzy = true
  local vm = self:member(vic)
  vm.robbed = vm.robbed + 1
  vic.dizzyT = vm.dizzy + math.floor(mag(atk.vx, atk.vy))
  local k = self:member(atk).knock
  vic.vx, vic.vy = atk.vx * k, atk.vy * k
  atk.vx, atk.vy = 0, 0
  atk.frozen, vic.frozen = 18, 6
  return true
end

-- 02207418: every pair of Pokemon whose bodies touch
function M:collide()
  local hitAt
  for i = 1, 4 do
    local a = self.teams[i]
    if not a.depositing then
      local ma = self:member(a)
      for j = 1, 4 do
        local b = self.teams[j]
        if j ~= i and not b.depositing then
          local mb = self:member(b)
          local ax, ay = a.x, a.y - ma.body
          local bx, by = b.x, b.y - mb.body
          local dist = mag(ax - bx, ay - by)
          if dist < ma.radius + mb.radius then
            if not a.contact[j] then
              if not self:tackle(a, b) then a.frozen, b.frozen = 6, 6 end
              for _, t in ipairs({ a, b }) do
                local s = mag(t.vx, t.vy)
                if s > HIT_CAP then t.vx, t.vy = t.vx / s * HIT_CAP, t.vy / s * HIT_CAP end
              end
              a.contact[j], b.contact[i] = true, true
              ma.hits, mb.hits = ma.hits + 1, mb.hits + 1
              if not hitAt then
                local nx, ny = ax - bx, ay - by
                local n = mag(nx, ny)
                if n > 0 then nx, ny = nx / n, ny / n end
                hitAt = { bx + nx * mb.radius, by + ny * mb.radius }
              end
            end
          else
            a.contact[j], b.contact[i] = false, false
          end
        end
      end
    end
  end
  if hitAt then
    self:addFx("spark", hitAt[1], hitAt[2])
    self:seAt(SE.spark, hitAt[1], hitAt[2])
  end
end

-- 022078B0: the first flag within reach
function M:pickUp(team)
  local mp = self:member(team)
  for i, f in ipairs(self.flags) do
    if f.active and mag(team.x - f.x, team.y - f.y) < mp.radius + 8 then
      if team.carried >= MAX_CARRY then
        if not team.fullLatch[i] then
          team.fullLatch[i] = true
          if team.index == 1 then se(self, SE.full) end
        end
        return
      end
      team.fullLatch[i] = true
      f.active = false
      self.flagCount = self.flagCount - 1
      team.carried = team.carried + 1
      return
    else
      team.fullLatch[i] = false
    end
  end
end

-- 02207B8C: home with flags
local function atHome(team)
  return team.y > 408 and team.x >= 208 and team.x <= 304 and team.carried > 0 and not team.dizzy
end

-- the tag (02206C90 / 02206D58 with the top screen's swap): out, swap, in
local TAG_OUT, TAG_SWAP, TAG_IN = 32, 10, 32

function M:stepTag(team)
  team.tagT = team.tagT + 1
  if team.tag == 1 then
    team.lift = team.lift + 8
    if team.tagT >= TAG_OUT then team.tag, team.tagT = 2, 0 end
  elseif team.tag == 2 then
    if team.tagT >= (team.cpu and 9 or TAG_SWAP) then
      team.cur = team.cur % 3 + 1
      team.facing = UP
      team.tag, team.tagT = 3, 0
    end
  elseif team.tag == 3 then
    team.lift = team.lift - 8
    if team.tagT >= TAG_IN then
      team.lift, team.tag, team.tagT = 0, 0, 0
      team.depositing, team.facing = false, UP
    end
  end
end

function M:stepTeam(team)
  -- the deposit (02207B8C / 02205EFA)
  if not team.depositing and atHome(team) then
    team.depositLeft, team.carried, team.depositing = team.carried, 0, true
    team.vx, team.vy, team.facing, team.steps, team.delay = 0, 0, DOWN, 10, 0
  end
  if team.steps > 0 and team.depositing then
    if team.delay == 0 then
      if team.depositLeft > 0 then
        team.score = math.min(999, team.score + 1)
        team.depositLeft = team.depositLeft - 1
        local mp = self:member(team)
        mp.deposited = mp.deposited + 1
        self:addFx("flagword", 0, -24, team)
        self:seAt(SE.count, team.x, team.y)
      end
      team.steps = team.steps - 1
      if team.steps == 0 then
        team.tag, team.tagT = 1, 0
        local mp = self:member(team)
        mp.tags = (mp.tags or 0) + 1   -- kind 7 (02205E30)
      else team.delay = 4 end
    else
      team.delay = team.delay - 1
    end
  end
  if team.depositing then return end
  -- moving, the walls, the blocks
  local ox, oy = team.x, team.y
  team.x, team.y = team.x + team.vx, team.y + team.vy
  clampField(team)
  local code = self:blockCollide(team, ox, oy)
  team.blockCode = code
  bounce(team, code)
  self:collide()
  -- friction
  local s = mag(team.vx, team.vy)
  if s > 0 then
    local f = FRICTION + (self.braking and BRAKE or 0)
    if s >= f then team.vx, team.vy = team.vx - team.vx / s * f, team.vy - team.vy / s * f
    else team.vx, team.vy = 0, 0 end
  end
  if team.tag == 0 and team.dizzy then
    team.dizzyT = team.dizzyT - 1
    if team.dizzyT <= 0 then team.dizzy = false end
  end
  self:pickUp(team)
end

-- ------------------------------------------------------------------- AI --

local function inBox(tx, ty, x, y) return x >= tx - 16 and x < tx + 16 and y >= ty - 16 and y < ty + 16 end

local function onField(tx, ty)
  if ty < 0x68 then return false end
  if ty <= 0x188 then return tx >= 0x90 and tx <= 0x170 end
  return tx >= 0xD0 and tx <= 0x130
end

-- 02208BB8: score 48 targets, flick at one of the best
function M:think(team)
  if team.depositing or team.dizzy or team.frozen > 0 then return end
  local x, y = math.floor(team.x), math.floor(team.y)
  local cells = {}
  for i = 0, 47 do
    local col, row = i % 6, math.floor(i / 6)
    cells[i] = { tx = x - 0x60 + col * 32 + rand(32), ty = y - 0x80 + row * 32 + rand(32), score = 0 }
  end
  for _ = 1, 2 do for i = 19, 22 do cells[i].score = cells[i].score + 2 end end
  for i = 0, 47 do
    local c = cells[i]
    for _, f in ipairs(self.flags) do
      if f.active and inBox(c.tx, c.ty, f.x, f.y) then c.score = c.score + 7 end
    end
    for _, o in ipairs(self.teams) do
      if o ~= team and inBox(c.tx, c.ty, math.floor(o.x), math.floor(o.y)) then c.score = c.score - 3 end
    end
    for _, q in ipairs(self.aiAvoid) do
      if inBox(c.tx, c.ty, q[1], q[2]) then c.score = c.score - 2 end
    end
    if not onField(c.tx, c.ty) then c.score = c.score - 100 end
  end
  if y > 256 then for i = 30, 35 do cells[i].score = cells[i].score + 3 end
  elseif y < 256 then for i = 0, 5 do cells[i].score = cells[i].score + 3 end end
  if team.carried > 0 then
    for i = 30, 35 do cells[i].score = cells[i].score + team.carried end
    if x > 256 then for i = 30, 32 do cells[i].score = cells[i].score + 2 end
    elseif x < 256 then for i = 33, 35 do cells[i].score = cells[i].score + 2 end end
  end
  -- 02208FF0: the best score, a random one of those
  local best = -math.huge
  for i = 0, 47 do best = math.max(best, cells[i].score) end
  local top = {}
  for i = 0, 47 do if cells[i].score == best then top[#top + 1] = cells[i] end end
  local pick = top[rand(#top) + 1]
  team.aiFlick = { pick.tx - team.x, pick.ty - team.y }
end

-- 02208B34: every 6 ticks, one rival team a tick
function M:stepAI()
  self.aiCount = self.aiCount + 1
  if self.aiCount >= AI_EVERY then self.aiRound, self.aiCount = true, 0 end
  if self.aiRound then
    self:think(self.teams[2 + self.aiTurn])
    self.aiTurn = self.aiTurn + 1
    if self.aiTurn >= 3 then self.aiTurn, self.aiRound = 0, false end
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

-- where the player's Pokemon stands on the touch screen (always the middle)
function M:homeOnScreen()
  local me = self.teams[1]
  return 128, 96 - self:member(me).body + me.lift
end

function M:touchpressed(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if not px then return false end
  self:press(px, py)
  return true
end
function M:touchmoved(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if px and self.drag then self.drag.cx, self.drag.cy = px, py end
  return true
end
function M:touchreleased(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if px and self.drag then self.drag.cx, self.drag.cy = px, py end
  self:release()
  return true
end

function M:press(px, py)
  if self.countdown > 0 or self.over then return end
  local me = self.teams[1]
  if not self:canFlick(me) then return end
  local hx, hy = self:homeOnScreen()
  if mag(px - hx, py - hy) < TOUCH_R then
    self.drag = { sx = px, sy = py, cx = px, cy = py, held = 0 }
  end
end

function M:release()
  local dr = self.drag
  self.drag, self.braking = nil, false
  if not dr or self.over then return end
  local me = self.teams[1]
  if dr.held <= FLICK_HOLD and self:canFlick(me) then
    self.pendingFlick = { dr.cx - dr.sx, dr.cy - dr.sy }
  end
end

-- pad / keyboard: a direction flicks a 64 px drag that way (diagonals too)
function M:padFlick()
  local input = self.game.input
  if not input then return end
  local any = input:wasPressed("left") or input:wasPressed("right") or input:wasPressed("up") or input:wasPressed("down")
  if not any then return end
  local dx = (input:isDown("right") and 1 or 0) - (input:isDown("left") and 1 or 0)
  local dy = (input:isDown("down") and 1 or 0) - (input:isDown("up") and 1 or 0)
  if dx == 0 and dy == 0 then return end
  local n = mag(dx, dy)
  if self:canFlick(self.teams[1]) then self.pendingFlick = { dx / n * 64, dy / n * 64 } end
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
    -- the FINISH (021E667C) with the field running on (0220549C state 2)
    if self.t % 2 == 0 then
      if not self.cd:finishing() then return self:finish() end
      self:tick()
    end
    return
  end
  if self.over then
    self.over = self.over - 1
    if self.over <= 0 then return self:finish() end
    return
  end
  self:padFlick()
  if self.t % 2 == 0 then self:tick() end
end

function M:tick()
  self.ticks = self.ticks + 1
  if self.timer > 0 then self.timer = self.timer - 1 end
  self:stepAI()
  -- the touch's hold count (022055AC): past 255 ticks everyone brakes
  if self.drag then
    self.drag.held = self.drag.held + 1
    if self.drag.held >= 0xFF then self.braking = true end
  end
  for _, team in ipairs(self.teams) do
    local flick = team.cpu and team.aiFlick or (not team.cpu and self.pendingFlick)
    if team.cpu then team.aiFlick = nil else self.pendingFlick = nil end
    if flick and self:canFlick(team) then self:flick(team, flick[1], flick[2]) end
    if team.tag ~= 0 then self:stepTag(team) end
  end
  -- 02205E30: the held ones count down and sit out this tick
  local held = {}
  for i, team in ipairs(self.teams) do
    if team.frozen > 0 then team.frozen, held[i] = team.frozen - 1, true end
  end
  for i, team in ipairs(self.teams) do
    if not held[i] then
      local before = team.carried
      self:stepTeam(team)
      if team.carried > before then
        team.gotT = 10
        self:addFx("flagup", 0, -16, team)
        self:seAt(team.index == 1 and SE.pick or SE.pickRival, team.x, team.y)
      end
    end
  end
  for _, team in ipairs(self.teams) do
    if team.carried < team.lastCarried and not team.depositing then self:addFx("flagdown", 0, -16, team) end
    team.lastCarried = team.carried
    if team.gotT > 0 then team.gotT = team.gotT - 1 end
  end
  self:refillFlags()
  for _, f in ipairs(self.flags) do if f.active and f.puff then f.puff = f.puff + 1 end end
  for i = #self.fx, 1, -1 do
    local e = self.fx[i]
    e.t = e.t + 1
    if e.t > e.life then table.remove(self.fx, i) end
  end
  if self.timer == 0 and not self.over then
    self.over = 60; self.drag = nil
    if self.cd then
      local me = self.teams[1]
      self.cd:startFinish(Rec.isNew(self.game, 1, math.min(999, me.score + me.depositLeft)))
    end
  end
end

-- the effect sprites and how many of each there are: four flick puffs and
-- four sparks shared by everyone (heap 0x35C / 0x34C, a ring each), two
-- "FLAG!" words a team (T+0x4C), one flag up / down a team (T+0x54); the
-- team ones ride on their Pokemon
local FX_LIFE = { dust = 24, spark = 9, flagword = 21, flagup = 9, flagdown = 44 }
local FX_SLOTS = { dust = 4, spark = 4, flagword = 2, flagup = 1, flagdown = 1 }
function M:addFx(kind, x, y, owner)
  local same, oldest = 0, nil
  for i, e in ipairs(self.fx) do
    local slot = (kind == "flagup" or kind == "flagdown") and (e.kind == "flagup" or e.kind == "flagdown") or e.kind == kind
    if slot and e.owner == owner then
      same = same + 1
      oldest = oldest or i
    end
  end
  if oldest and same >= FX_SLOTS[kind] then table.remove(self.fx, oldest) end
  self.fx[#self.fx + 1] = { kind = kind, x = x, y = y, t = 0, life = FX_LIFE[kind] or 20, owner = owner }
end

function M:finish()
  local points, stats = {}, {}
  for t, team in ipairs(self.teams) do
    -- 02205520: the flags still being counted count too
    local flags = math.min(999, team.score + team.depositLeft)
    team.final = flags
    points[t] = math.min(200, flags * 3)
    stats[t] = {}
    for m = 1, 3 do
      local mp = team.members[m]
      stats[t][m] = { miss = mp.robbed > 0, hit = mp.hits, score = mp.deposited, switch = mp.tags or 0 }
    end
  end
  self.game.stack:pop()
  if self.onDone then self.onDone({ points = points, flags = self.teams[1].final, stats = stats, record = self.teams[1].final }) end
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

function M:sprite(key, x, y)
  local img, rec = self:img(key)
  if not img then return false end
  local ox = type(rec) == "table" and tonumber(rec.originX) or 0
  local oy = type(rec) == "table" and tonumber(rec.originY) or 0
  love.graphics.draw(img, math.floor(x + ox), math.floor(y + oy))
  return true
end

-- a sequence's frame at `tick` (objSeq durations), looping or held at the end
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
  return self:sprite(("%s_%d_%d"):format(set, seq, self:seqFrame(set, seq, tick, hold)), x, y)
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

local DIZZY_SPIN = { UP, RIGHT, DOWN, LEFT }

-- the touch screen: the field around the player's Pokemon
function M:drawField()
  local g = love.graphics
  local me = self.teams[1]
  local cx, cy = math.floor(me.x) - 128, math.floor(me.y) - 96
  g.setColor(0.1, 0.3, 0.7, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local frames = tonumber(self.d.fieldFrames) or 0
  local key = frames > 0 and ("field_" .. (math.floor(self.ticks / 5) % frames)) or "field"
  local img = self:img(key) or self:img("field")
  if img then g.draw(img, -cx, -cy) end
  -- everything on the field, back to front by y (02207BD8)
  local list = {}
  for _, b in ipairs(self.blocks) do list[#list + 1] = { y = b[2], f = function() self:anim("obj", 1, b[1] - cx, b[2] - cy, self.ticks) end } end
  for _, q in ipairs(self.deco) do
    list[#list + 1] = { y = q[2], f = function()
      self:anim("obj", 6, q[1] - cx, q[2] - cy, self.ticks)
      self:anim("obj", 5, q[1] - cx, q[2] - cy, self.ticks)
    end }
  end
  for _, fl in ipairs(self.flags) do
    if fl.active then
      list[#list + 1] = { y = fl.y, f = function()
        self:anim("obj", 0, fl.x - cx, fl.y - cy, self.ticks)
        if fl.puff and fl.puff < 24 then self:anim("obj", 4, fl.x - cx, fl.y - cy, fl.puff, true) end
      end }
    end
  end
  for t, team in ipairs(self.teams) do
    local mp = self:member(team)
    local sx, sy = math.floor(team.x) - cx, math.floor(team.y) - cy + team.lift
    list[#list + 1] = { y = team.y, f = function()
      self:anim("ui", 4 + t, sx, sy, self.ticks)
      local facing = team.facing
      if team.dizzy then facing = DIZZY_SPIN[math.floor(self.ticks / 3) % 4 + 1] end
      local moving = mag(team.vx, team.vy) > 0.3
      local step = moving and math.floor(self.ticks / 4) or math.floor(self.ticks / 12)
      if not (mp.mon and self:walker(mp.mon, facing, sx, sy, step)) then
        if mp.mon then self:monIcon(mp.mon, sx, sy + 4, math.floor(self.ticks / 8)) end
      end
      if team.dizzy then self:anim("obj", 2, sx, sy - (mp.tall and 24 or 16) - 8, self.ticks) end
    end }
  end
  table.sort(list, function(a, b) return a.y < b.y end)
  for _, e in ipairs(list) do e.f() end
  for _, e in ipairs(self.fx) do
    local x, y = e.x - cx, e.y - cy
    if e.owner then x, y = math.floor(e.owner.x) + e.x - cx, math.floor(e.owner.y) + e.y - cy + e.owner.lift end
    if e.kind == "dust" then self:anim("obj", 4, x, y, e.t, true)
    elseif e.kind == "spark" then self:anim("obj", 7, x, y, e.t, true)
    elseif e.kind == "flagword" then self:anim("obj", 3, x, y, e.t, true)
    elseif e.kind == "flagup" then self:anim("obj", 8, x, y, e.t, true)
    elseif e.kind == "flagdown" then self:anim("obj", 9, x, y, e.t, true) end
  end
  -- the drag the player is making
  if self.drag then
    g.setColor(1, 1, 1, 0.7)
    g.setLineWidth(2)
    g.line(self.drag.sx, self.drag.sy, self.drag.cx, self.drag.cy)
    g.setColor(1, 1, 1, 1)
  end
  -- the shared 3-2-1 / FINISH (main engine = this screen, surface at 0)
  if self.cd then self.cd:draw(0) end
end

local function drawPart(img, x, y, qx, qy, qw, qh)
  if qw <= 0 or qh <= 0 then return end
  love.graphics.draw(img, love.graphics.newQuad(qx, qy, qw, qh, img:getDimensions()), x + qx, y + qy)
end

-- the score's three digits (02208374: /a/2/2/4 screen 9 rects, 32 x 64,
-- at tile (14 + 4 i, 3))
function M:drawScore(value)
  local img = self:img("digits")
  if not img then return end
  value = math.max(0, math.min(999, value))
  local ds = { math.floor(value / 100), math.floor(value / 10) % 10, value % 10 }
  for i, dgt in ipairs(ds) do
    local sx, sy = (dgt % 5) * 32, math.floor(dgt / 5) * 64
    love.graphics.draw(img, love.graphics.newQuad(sx, sy, 32, 64, img:getDimensions()), 112 + 32 * (i - 1), 24)
  end
end

-- the top screen (02207DDC / 02207F18 / 02208658 / 02208740)
function M:drawTop()
  local g = love.graphics
  g.setColor(0.85, 0.75, 0.2, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local b = self:img("top_b")
  if b then g.draw(b, 0, 0) end
  local a = self:img("top_a")
  if a then
    -- layer A without its "999" (the digit rect is redrawn)
    drawPart(a, 0, 0, 0, 0, 256, 24)
    drawPart(a, 0, 0, 0, 88, 256, 104)
    drawPart(a, 0, 0, 0, 24, 112, 64)
    drawPart(a, 0, 0, 208, 24, 48, 64)
  end
  local me = self.teams[1]
  self:drawScore(me.score)
  -- the clock: icon at (112, 8), seconds at 128 / 144
  self:anim("ui", 4, 112, 8, 0)
  local secs = math.floor(self.timer / 30)
  self:anim("ui", 9 + math.floor(secs / 10) % 10, 128, 8, 0)
  self:anim("ui", 9 + secs % 10, 144, 8, 0)
  -- the player's Pokemon now and next (front pictures in the cartridge)
  local now = self:member(me).mon
  local nxt = me.members[me.cur % 3 + 1].mon
  if now then self:monIcon(now, 40, 136 + 16, math.floor(self.t / 8), 2) end
  if nxt then self:monIcon(nxt, 40, 48 + 16, 0, 2) end
  -- the four teams: ring + Pokemon at (112 + 40 t, 148), the flags they carry
  -- in a bubble above
  for t, team in ipairs(self.teams) do
    local x = 112 + 40 * (t - 1)
    self:anim("ui", 4 + t, x, 148, 0)
    local mon = self:member(team).mon
    if mon and team.tag ~= 1 then self:monIcon(mon, x, 156, math.floor(self.t / 8)) end
    -- the bubble, its flag and its digit share one point (022081A0); the
    -- cells place them
    self:anim("ui", 3, x, 116, 0)
    self:anim("ui", 0, x, 116, 0)
    self:anim("ui", 9 + math.min(9, team.carried), x, 116, 0)
  end
  if self.countdown > 0 and not self.cd then
    local Font = require("src.render.Font")
    Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 88)
  end
end

function M:draw()
  local g = love.graphics
  if SecondScreen.separate(self.game) then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawField() end)
  else
    local input = self.game.input
    if self.showTop or (input and (input:isDown("select") or input:isDown("l"))) then self:drawTop() else self:drawField() end
    if self.countdown > 0 and not self.cd then
      local Font = require("src.render.Font")
      Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 40)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return M
