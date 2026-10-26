-- HEARTGOLD / SOULSILVER POKeATHLON: SNOW THROW (pokeheartgold
-- asm/overlay_96.s 0x02201558..0x022047EC, event 8, sub-app ov96_0221A858 =
-- init 02201558 / main 02201B18 / vblank 02201B34 / exit 02201B98, states
-- ov96_0221DC48 (= _0221DA00[8]) = { 02202154 play, 022021D4 end:
-- field5E0[team] = the team's hits }; the reading is written up in
-- scratch_claude/athlon/NOTES.md, "## Snow Throw").
-- Art and tables: `gen4_hgss_snow_throw`
-- (src/import/Gen4HgssPokeathlonSnowThrowArt.lua).
--
-- THE ARENA is a 66 x 66 world square (fx units, round (33, 33)); the twelve
-- Pokemon never move: team t's three stand at ov96_0221C98C (team 0 = the
-- player at z 61, 1 the right side x 61, 2 the far side z 5, 3 the left
-- side x 5). The top screen draws it in perspective (02204134: world ->
-- screen, top y 0..191, the touch screen 288..479); the touch screen is the
-- near strip with the player's three seen from behind.
--
-- READ FROM CODE (the logic runs at the Pokeathlon's 30 frames a second):
--   * a Pokemon's numbers (0220329C, NARC 170 MEMBER 3 by its course record):
--     skill = [SKILL] / 10 (1.6 .. 1.0), power = [5 + POWER] / 10 (1.0 ..
--     1.6), spread = [10 + SKILL] degrees (6 4 3 2 0), fatigue taken =
--     [15 + STAMINA] (3 2 2 2 1); health starts at 120 (+0x16)
--   * THE CLOCK: 0x708 = 1800 frames = 60 s (heap+0x5E8), one off a frame
--     after the shared 3-2-1 (021E637C); at 0 everything freezes (0x5D0)
--   * THE STYLUS (0220223C, the player's input record): a new touch within
--     4.0 world units (022031A8; touch -> world 0220404C) of one of the
--     team's three that has not fainted and whose ball is none or in hand
--     takes it -- no ball yet: a ball in its hand, size 0, 0 taps. Let go ON
--     it = a tap: taps 1..4 = size 0..3 (no more after 4). Let go anywhere
--     else = a throw, unless the stylus went DOWN the screen: direction = the
--     world points' difference, its whole length clamped to 1..2, speed =
--     clamp(fatigue x length x (2 - skill) / (1 + hold / 30), 1, 3) with
--     fatigue 0.5 / 0.6 / 0.7 / 0.8 / 1 at health <= 60 / 70 / 80 / 90 /
--     above, then turned by rand % (2 spread) - spread degrees (02204320)
--   * THE BALLS (02203468): a thrown ball moves by its speed a frame and is
--     gone outside 1..64; a burst one lasts 8 frames
--   * COLLISIONS (02203754): any two balls in flight OR IN HAND nearer than
--     4.0 burst together (a ball in hand is a shield)
--   * HITS (02203544): a ball in flight nearer than 3.0 to a Pokemon of
--     another team bursts; the thrower scores 1 (counter 3, cap 999); the
--     target loses 30 + int(int(|speed|) x size factor (1 / 20 / 50 / 100 for
--     size 0..3) x thrower's power x its fatigue taken) health (not below 0);
--     fatigue = 120 - health: over 40 = FAINTED for that many frames (counter
--     1); hit again while fainted adds the fatigue to the time (a byte)
--   * RECOVERY (022033FC): health +1 a frame up to 120; faint time -1 a
--     frame; tired (sweat) at health <= 100
--   * THE RIVALS (022043C0 / 022044A0 / 0220472C): every 40 frames one
--     Pokemon slot of each rival team in turn (one team a frame) acts, if
--     not fainted and its ball is none or in hand: r = rand % 51; health + r
--     <= 120 and fewer than 4 taps: make / grow its ball like a tap; else
--     THROW at the best of the nine others by hits / 20 + rand % 21 (+1
--     fainted, + fatigue / 20; ties at random), turned +-3 deg and by its
--     spread, speed clamp(elapsed / 40 + health / 50 + rand % 51, 1, 2)
--     (elapsed = frames since the start: in practice always 2)
--   * Athlete Points (ov96_0221A720 + 0221A61C): 3 x the team's hits, at most
--     200 -- Bulbapedia agrees. No-Miss = never fainted from a snowball
--     (counter 1). Effort counter: fail (the faints). score = hits.
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 02201558 puts them on the main
--     engine at y offset 0 (021E6290 r1) -- the TOP screen in this event
--     (gSystem.screensFlipped = 0; main surface at 0, sub at 0x120 --
--     021EB5C8); 02202154 runs the countdown, play, then the finish
--   * the record (src/pokemon/HgssPokeathlonRecords.lua): at time up 022038D4
--     hands ov96_021E8318 the team's hits (the packed & 0x3FF, at most 999)
--     for NEW RECORD! (021E839C, higher is better); the end state's
--     field_5E0 (022021D4, the same hits) is what the course's end saves
--
-- STAND-INS, said so: during the FINISH the field stands still (the
-- cartridge runs 0220223C on under it); on one screen the 3-2-1 / FINISH
-- are drawn over the touch screen's view too; without
-- `gen4_hgss_athlon_common` they are 3 s of numbers / FINISH!; the hold
-- counter 0x5EA is shared
-- and the rival teams' empty input records reset it every frame, so the
-- "/ (1 + hold / 30)" is always / 1 here too (read, not a stand-in); a
-- spread of 0 (5 SKILL stars) takes rand % 0 on the cartridge -- here no
-- turn; the rivals are gen4_follow_mon walkers (icons fallback) at
-- ov96_0221C8C8 / 0221C8EC, their animations (021EAC5C 0x10 throw, 0x14
-- faint, 0x16 hit) by eye (a shake, grey, faster steps); the player's three
-- are their back sprites fitted to the 80 x 80 frames of sprite set b (seq
-- 1 + k idle, 4 + k throw, 7 + k hit, 10 + k fainted, the frame offsets
-- read from the cells) at x 16 + 50 k, y 88 (GetMonPicHeight not read: 0);
-- the clock (022038A0 sets the sprite's sequence) and the team flags are
-- placed by eye, the seconds in text; the player's name is the port's font;
-- the touch screen shakes 8 px for 10 frames when one of ours is hit
-- (02203CE4); sounds by id (0x8AC throw, 0x8B1 size, 0x88F HIT!, 0x8B0
-- ours hit, 0x890 faint, 0x8B3 ours burst).

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local NONE = 12                         -- 0x5CC: no Pokemon held
local CLOCK = 0x708                     -- 1800 frames
local HEALTH = 120                      -- +0x16 at the start
local GRAB_R, HIT_R, CLASH_R = 4.0, 3.0, 4.0
local BURST_FRAMES = 8
local AI_EVERY = 40                     -- 0x28 (ai+0xC7)
local SIZE_F = { [0] = 1.0, 20.0, 50.0, 100.0 }
local SUB_Y = 288                       -- the touch screen in sprite space (021EB5C8 0x120000)
local SE = { throw = 0x8AC, size = 0x8B1, hit = 0x88F, ours = 0x8B0, faint = 0x890, burst = 0x8B3 }
local TEAM_RGB = { { 0.94, 0.25, 0.25 }, { 0.25, 0.45, 0.95 }, { 0.2, 0.75, 0.3 }, { 0.95, 0.85, 0.2 } }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local POWER, STAMINA, SKILL = 0, 1, 2

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function len(x, z) return math.sqrt(x * x + z * z) end
local function trunc(v) return v < 0 and math.ceil(v) or math.floor(v) end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_snow_throw
  return type(d) == "table" and d.params ~= nil and d.spots ~= nil and d.field ~= nil
end

-- ------------------------------------------------------------ projection --

-- 0220404C: a touch-screen point (y 0..191) -> world (x, z)
function M.toWorld(x, y)
  local Y = y + SUB_Y
  local z = 293 / 13 + Y * 5 / 52
  local wx = (x * 0.19375 + Y / 8 - 15.5 - 10) / (Y / 512 + 0.39402173913043476)
  return wx, z
end

-- 02204134: world (x, z) -> sprite space (top 0..191, touch 288..479)
function M.toScreen(x, z)
  local a = 4 / (1 + (z - 57) * (z - 57))
  local b = 11 + z * z * z / 7600
  local c = (24 - z) * (24 - z) * (24 - z) / 4403
  local y8 = a + (b - c - 1)
  local Y = trunc(y8 * 8)
  local x8 = (x * (8 / 23) + 10) - (Y / 8 - 10) * (20 / 31) * (64 - x) / 64
  return trunc(x8 * 8), Y
end

-- MTX_RotY43_ by FX angle units (65536 a turn), applied to (x, z)
local function rotY(x, z, a)
  local r = a * 2 * math.pi / 65536
  local s, c = math.sin(r), math.cos(r)
  return x * c + z * s, -x * s + z * c
end

-- 02204320: turn by rand % (2 s) - s degrees (0xB6 fx units each)
local function spread(x, z, s)
  if s <= 0 then return x, z end
  local d = rand(2 * s) - s
  return rotY(x, z, (d * 0xB6) % 65536)
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

-- 0220329C: the per-Pokemon record (heap+0x418 + 0x20 i)
local function newMon(self, mon, st, i)
  local p = self.d.params
  local spot = self.d.spots[i] or self.d.spots[tostring(i)]
  return {
    mon = mon, id = i, team = math.floor(i / 3), slot = i % 3,
    x = spot[1], z = spot[2],
    skill = p[star(st, SKILL)] / 10,          -- +4
    power = p[5 + star(st, POWER)] / 10,      -- +8
    taken = p[15 + star(st, STAMINA)],        -- +0xC
    spread = p[10 + star(st, SKILL)],         -- +0x10
    hits = 0, health = HEALTH, faint = 0, cond = 0, justHit = false, -- +0x14 / 16 / 18 / 19 / 1B
    faints = 0, fainted = false,
    anim = { seq = 1, t = 0 }, shake = 0, step = 0,
  }
end

-- opts: team (three Pokemon), rivals ({3}, {3}, {3}), onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, names = opts.names, t = 0, frame = 0, images = {} }, M)
  self.d = game.data.gen4_hgss_snow_throw
  self.mons, self.balls = {}, {}
  for i = 0, 11 do
    local t = math.floor(i / 3)
    local mon = t == 0 and opts.team[i % 3 + 1] or (opts.rivals and opts.rivals[t] and opts.rivals[t][i % 3 + 1])
    self.mons[i] = newMon(self, mon, starsOf(game, mon, t > 0), i)
    -- the ball record (heap+0xB8 + 0x48 i)
    self.balls[i] = { id = i, state = 0, x = 0, z = 0, vx = 0, vz = 0, taps = 0, size = 0, burstT = 0, hitFlag = false, shown = 0 }
  end
  self.timer = CLOCK                 -- 0x5E8
  self.sel = NONE                    -- 0x5CC (the player's)
  self.press = nil                   -- 0xE0 / 0xEC of the held ball
  self.hold = 0                      -- 0x5EA
  self.ai = { tick = 0, think = false, k = 0, slot = 0 }
  self.touch = { down = false, x = 0, y = 0, was = false, new = false }
  self.pad = { thrower = 2, target = 4 }
  self.pops = {}
  self.countdown = 90
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (02201558)
  if CD.available(game) then self.cd = CD.new(game, 0) end
  self.shakeT = 0
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

-- ------------------------------------------------------------------ rules --

-- 022031A8: which of team t's three is within 4.0 of world (x, z) (NONE if none)
function M:monAt(t, x, z)
  for i = 3 * t, 3 * t + 2 do
    local m = self.mons[i]
    if len(m.x - x, m.z - z) <= GRAB_R then return i end
  end
  return NONE
end

-- the taps -> size rule (0220223C / 022044A0)
local function tap(b)
  if b.taps >= 4 then return false end
  b.taps = b.taps + 1
  b.size = math.min(3, b.taps - 1)
  return true
end

-- the fatigue factor on a throw (0220223C)
local function fatigue(m)
  local h = m.health
  if h <= 60 then return 0.5 elseif h <= 70 then return 0.6 elseif h <= 80 then return 0.7
  elseif h <= 90 then return 0.8 end
  return 1.0
end

-- 0220223C's throw: direction (dx, dz) in world units
function M:throw(i, dx, dz)
  local m, b = self.mons[i], self.balls[i]
  local l = clamp(trunc(len(dx, dz)), 1, 2)
  local v = fatigue(m) * (l * (2.0 - m.skill)) / (self.hold / 30 + 1.0)
  v = clamp(v, 1.0, 3.0)
  local n = len(dx, dz)
  local ux, uz = 0, 0
  if n > 0 then ux, uz = dx / n, dz / n end
  ux, uz = spread(ux, uz, m.spread)
  b.vx, b.vz = ux * v, uz * v
  b.state = 1
end

-- the player's stylus (0220223C for participant 0)
function M:stepInput()
  local tc = self.touch
  local down, new = tc.down, tc.new
  tc.new = false
  local b
  if down and new then
    local wx, wz = M.toWorld(tc.x, tc.y)
    local i = self:monAt(0, wx, wz)
    if i ~= NONE then
      local m = self.mons[i]
      b = self.balls[i]
      if m.cond ~= 1 and (b.state == 0 or b.state == 2) then
        self.sel = i
        self.press = { wx = wx, wz = wz, x = tc.x, y = tc.y }
        if b.state == 0 then
          b.x, b.z, b.state, b.taps, b.size = m.x, m.z, 2, 0, 0
        end
      end
    end
    self.hold = 0
    -- a touch let go before the frame saw it: the release comes next frame
    if tc.upAfter then tc.down, tc.upAfter = false, false end
  elseif down then
    -- 0x5EA counts while held, but the rival teams' records reset it
    -- after us each frame (see the header)
    self.hold = 0
  elseif self.sel ~= NONE then
    local i = self.sel
    b = self.balls[i]
    local wx, wz = M.toWorld(tc.x, tc.y)
    local at = self:monAt(0, wx, wz)
    if at == i then
      tap(b)
    elseif tc.y - self.press.y <= 0 then
      self:throw(i, wx - self.press.wx, wz - self.press.wz)
    end
    self.sel = NONE
    self.hold = 0
  end
end

-- 0220472C + 022044A0: one rival Pokemon's turn
function M:decide(i, elapsed)
  local m, b = self.mons[i], self.balls[i]
  local r = rand(51)
  if m.health + r <= HEALTH and b.taps < 4 then
    if b.state == 0 then
      b.taps, b.state, b.x, b.z = 1, 2, m.x, m.z
    else
      tap(b)
    end
    return
  end
  -- the target: hits / 20 + rand % 21 (+1 fainted, + fatigue / 20)
  local list = {}
  for j = 0, 11 do
    local o = self.mons[j]
    local pr = math.floor(o.hits / 20) + rand(21)
    if o.cond == 1 then pr = pr + 1 end
    pr = pr + trunc((HEALTH - o.health) / 20)
    if o.team ~= m.team then
      local at = #list + 1
      for k, e in ipairs(list) do if e.pr < pr then at = k; break end end
      table.insert(list, at, { j = j, pr = pr })
    end
  end
  local ties = 0
  for _, e in ipairs(list) do if e.pr == list[1].pr then ties = ties + 1 end end
  local o = self.mons[list[rand(math.max(1, ties)) + 1].j]
  local dx, dz = o.x - m.x, o.z - m.z
  local n = len(dx, dz)
  dx, dz = dx / n, dz / n
  dx, dz = spread(dx, dz, 3)
  dx, dz = spread(dx, dz, m.spread)
  local v = elapsed / 40 + (m.health / 50 + rand(51))
  v = clamp(v, 1.0, 2.0)
  b.vx, b.vz = dx * v, dz * v
  b.state = 1
  b.x, b.z = m.x, m.z
end

-- 022043C0: every 40 frames, one rival team a frame, slot by slot
function M:stepAi()
  local ai = self.ai
  ai.tick = ai.tick + 1
  if ai.tick >= AI_EVERY then ai.think, ai.tick = true, 0 end
  if not ai.think then return end
  local i = ai.slot + 3 * (1 + ai.k)
  local b = self.balls[i]
  if (b.state == 0 or b.state == 2) and self.mons[i].cond ~= 1 then
    self:decide(i, CLOCK - self.timer)
  end
  ai.k = ai.k + 1
  if ai.k >= 3 then ai.k, ai.slot, ai.think = 0, (ai.slot + 1) % 3, false end
end

-- 022033FC: faint time, health, condition
function M:stepMons()
  for i = 0, 11 do
    local m = self.mons[i]
    if m.faint ~= 0 then m.faint = m.faint - 1 end
    if m.health < HEALTH then m.health = m.health + 1 end
    if m.faint ~= 0 then m.cond = 1 elseif m.health <= 100 then m.cond = 2 else m.cond = 0 end
  end
end

-- 02203468: the balls fly; bursts end; out of 1..64 = gone
function M:stepBalls()
  for i = 0, 11 do
    local b = self.balls[i]
    if b.state == 1 then
      b.x, b.z = b.x + b.vx, b.z + b.vz
    elseif b.state == 3 then
      b.burstT = b.burstT + 1
      if b.burstT >= BURST_FRAMES then b.burstT, b.state = 0, 0 end
    end
    if b.x < 1 or b.x > 64 or b.z < 1 or b.z > 64 then
      b.state, b.vx, b.vz = 0, 0, 0
    end
  end
end

-- 02203754: balls in flight or in hand nearer than 4.0 burst together
function M:clashes()
  local hit = {}
  for i = 0, 11 do
    local a = self.balls[i]
    if a.state == 1 or a.state == 2 then
      for j = 0, 11 do
        local o = self.balls[j]
        if j ~= i and (o.state == 1 or o.state == 2) and len(a.x - o.x, a.z - o.z) < CLASH_R then
          hit[i], hit[j] = true, true
        end
      end
    end
  end
  for i = 0, 11 do
    if hit[i] then
      local b = self.balls[i]
      b.state, b.size, b.taps = 3, 0, 0
    end
  end
end

-- 02203544: balls in flight on Pokemon of other teams
function M:hits()
  for i = 0, 11 do
    local tg = self.mons[i]
    tg.justHit = false
    for j = 0, 11 do
      local b = self.balls[j]
      local th = self.mons[j]
      if b.state == 1 and th.team ~= tg.team and len(tg.x - b.x, tg.z - b.z) < HIT_R then
        b.state = 3
        th.hits = math.min(999, th.hits + 1)
        b.hitFlag = true
        tg.justHit = true
        local f = SIZE_F[b.size] or 1.0
        b.size, b.taps = 0, 0
        local dmg = trunc(trunc(len(b.vx, b.vz)) * f * th.power * tg.taken)
        tg.health = math.max(0, tg.health - dmg - 30)
        local d = (HEALTH - tg.health) % 256
        if tg.faint == 0 then
          if d > 40 then
            tg.faint = d
            tg.faints, tg.fainted = tg.faints + 1, true
          end
        else
          tg.faint = (tg.faint + d) % 256
          tg.faints, tg.fainted = tg.faints + 1, true
        end
      end
    end
  end
end

-- 0220223C, once a frame
function M:step()
  self.frame = self.frame + 1
  if self.timer > 0 then self.timer = self.timer - 1 end
  self:stepInput()
  self:stepAi()
  self:stepMons()
  self:stepBalls()
  self:clashes()
  self:hits()
  if self.timer == 0 and not self.over then
    self.over = 90
    -- 022038D4: the team's hits to ov96_021E8318 (021E839C)
    if self.cd then self.cd:startFinish(Rec.isNew(self.game, 8, self:teamHits(0))) end
  end
  self:react()
end

-- 02202958's sounds and animations, from the state just made
function M:react()
  for i = 0, 11 do
    local m, b = self.mons[i], self.balls[i]
    if b.hitFlag then
      b.hitFlag = false
      if m.team == 0 then
        self.pops[#self.pops + 1] = { x = b.x, z = b.z, t = 0 }
        se(self, SE.hit)
      end
    end
    local a = m.anim
    a.t = a.t + 1
    if m.cond == 1 then
      if a.seq ~= 10 then
        a.seq, a.t = 10, 0
        se(self, SE.faint)
      end
    elseif m.justHit then
      a.seq, a.t = 7, 0
      m.shake = 8
      if m.team == 0 then
        se(self, SE.ours)
        self.shakeT = 10
      end
    elseif b.state == 1 and not m.threw then
      a.seq, a.t = 4, 0
      m.threw = true
      if m.team == 0 then se(self, SE.throw) end
    elseif a.seq == 10 or (a.seq ~= 1 and a.t * 2 >= self:seqTotal("b", a.seq + m.slot)) then
      a.seq, a.t = 1, 0
    end
    if b.state ~= 1 then m.threw = false end
    if m.shake > 0 then m.shake = m.shake - 1 end
    m.step = m.step + ((b.state == 1 and m.threw and a.seq == 4) and 3 or 1)
    if m.team == 0 then
      if b.size ~= b.shown and (b.state == 1 or b.state == 2) then se(self, SE.size) end
      if b.state == 3 and b.burstT == 0 then se(self, SE.burst) end
      b.shown = b.size
    end
  end
  for k = #self.pops, 1, -1 do
    local p = self.pops[k]
    p.t = p.t + 1
    if p.t > 40 then table.remove(self.pops, k) end
  end
  if self.shakeT > 0 then self.shakeT = self.shakeT - 1 end
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
  -- the input record keeps the last HELD point (022028BC)
  if self.touch.new then self.touch.upAfter = true else self.touch.down = false end
  return true
end

-- PAD / KEYS (not the cartridge's): UP / DOWN pick which of our three
-- throws, LEFT / RIGHT pick the rival it aims at (shown by a ring), A = a tap
-- (make / grow the ball), B = throw at the aimed one (a full-length flick);
-- SELECT / L shows the top screen
function M:padInput()
  local input = self.game.input
  if not input or self.padOff then return end
  if input:wasPressed("select") or input:wasPressed("l") then self.showTop = not self.showTop end
  local pd = self.pad
  if input:wasPressed("up") then pd.thrower = (pd.thrower + 1) % 3 end
  if input:wasPressed("down") then pd.thrower = (pd.thrower + 2) % 3 end
  if input:wasPressed("left") then pd.target = (pd.target - 3 + 8) % 9 + 3 end
  if input:wasPressed("right") then pd.target = (pd.target - 3 + 1) % 9 + 3 end
  pd.wantTap = pd.wantTap or input:wasPressed("a")
  pd.wantThrow = pd.wantThrow or input:wasPressed("b")
end

-- the pad's actions, inside the logic frame (as the stylus would)
function M:stepPad()
  local pd = self.pad
  local i = pd.thrower
  local m, b = self.mons[i], self.balls[i]
  if pd.wantTap then
    pd.wantTap = false
    if m.cond ~= 1 and (b.state == 0 or b.state == 2) then
      if b.state == 0 then b.x, b.z, b.state, b.taps, b.size = m.x, m.z, 2, 0, 0 end
      tap(b)
    end
  end
  if pd.wantThrow then
    pd.wantThrow = false
    if m.cond ~= 1 and (b.state == 0 or b.state == 2) then
      if b.state == 0 then b.x, b.z, b.state, b.taps, b.size = m.x, m.z, 2, 0, 0 end
      local o = self.mons[pd.target]
      local dx, dz = o.x - m.x, o.z - m.z
      local n = len(dx, dz)
      self:throw(i, dx / n * 2, dz / n * 2)
    end
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
    -- the FINISH (021E667C, 02202154 state 2)
    if not self.cd:finishing() then return self:finish() end
    return
  end
  if self.over then
    self.over = self.over - 1
    if self.over <= 0 then return self:finish() end
    return
  end
  self:stepPad()
  self:step()
end

-- ov96_022021D4 (field5E0 = the team's hits) and ov96_0221A720 (x 3, cap 200)
function M:teamHits(t)
  local s = 0
  for k = 0, 2 do s = s + self.mons[3 * t + k].hits end
  return math.min(999, s)
end

function M:finish()
  if self.done then return end
  self.done = true
  local pts, stats = {}, {}
  for t = 0, 3 do
    pts[t + 1] = math.min(200, self:teamHits(t) * 3)
    stats[t + 1] = {}
    for k = 0, 2 do
      local m = self.mons[3 * t + k]
      stats[t + 1][k + 1] = { miss = m.fainted, score = m.hits, jump = 0, dash = 0, hit = 0, fail = m.faints }
    end
  end
  self.game.stack:pop()
  if self.onDone then
    self.onDone({ points = pts, total = self:teamHits(0), stats = stats, record = self:teamHits(0) })
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

-- a sequence's whole length (frames)
function M:seqTotal(set, seq)
  local list = self.d.objSeq and self.d.objSeq[set] and (self.d.objSeq[set][seq] or self.d.objSeq[set][tostring(seq)])
  local total = 0
  for _, v in ipairs(type(list) == "table" and list or {}) do total = total + v end
  return math.max(1, total)
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

-- the walking sheet (gen4_follow_mon)
function M:sheetOf(mon)
  local fm = self.game.data.gen4_follow_mon
  if not (mon and type(fm) == "table" and fm.sheets) then return nil end
  local ok, Data = pcall(require, "src.import.Gen4HgssFollowMon")
  if not ok then return nil end
  local idx = Data.index(fm, tonumber(mon.species), tonumber(mon.form) or 0, false)
  return fm.sheets[idx] or fm.sheets[tostring(idx)]
end

function M:icon(mon, x, y, frame)
  local data = self.game.data
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (data.icons and data.icons.bySpecies and data.icons.bySpecies[mon.species]) or (def and def.icon)
  local ipath, fh = entry, nil
  if type(entry) == "table" then ipath, fh = entry.image, tonumber(entry.frameHeight) end
  local icon = type(ipath) == "string" and cachedImage(self, ipath)
  if not icon then return end
  local iw, ih = icon:getDimensions()
  fh = fh or math.min(iw, ih)
  local frames = math.max(1, math.floor(ih / fh))
  local g = love.graphics
  g.draw(icon, g.newQuad(0, (frame % frames) * fh, iw, fh, iw, ih), math.floor(x - iw / 2), math.floor(y - fh / 2))
end

-- a rival walker, its sprite centred on (x, y) (021EAF94); returns its height
function M:walker(m, x, y, face)
  local mon = m.mon
  if not mon then return 32 end
  local g = love.graphics
  local sheet = self:sheetOf(mon)
  local path = sheet and ((mon.shiny or mon.isShiny) and sheet.shiny or sheet.normal)
  local img = type(path) == "string" and cachedImage(self, path)
  if img then
    local fw, fh = tonumber(sheet.frameWidth) or 32, tonumber(sheet.frameHeight) or 32
    local iw, ih = img:getDimensions()
    local base = ({ up = 0, down = 2, left = 4, right = 6 })[face] or 2
    local f = base + (math.floor(m.step / 8) % 2)
    if (f + 1) * fh > ih then f = 0 end
    g.draw(img, g.newQuad(0, f * fh, fw, fh, iw, ih), math.floor(x - fw / 2), math.floor(y - fh / 2))
    return fh
  end
  self:icon(mon, x, y, math.floor(m.step / 8))
  return 32
end

-- the ball, its shadow and its burst at sprite-space point (X, Y), drawn on
-- the screen whose space starts at `oy` (02202958)
function M:drawBall(b, oy)
  local X, Y = M.toScreen(b.x, b.z)
  local ly = Y - oy
  if ly < -32 or ly > H + 32 then return end
  if b.state == 1 or b.state == 2 then
    local s = (Y + 312) / 752 * (1 + b.size / 3)
    if b.state == 1 then self:sprite("c_1_0", X, ly, s) end
    self:sprite("c_0_0", X, ly - 8 - trunc(Y / 20), s)
  elseif b.state == 3 then
    self:sprite(self:anim("c", 3, b.burstT * 2, true), X, ly - 8 - trunc(Y / 20))
  end
end

-- the top screen: the field, the nine rivals, the balls
function M:drawTop()
  local g = love.graphics
  g.setColor(0.6, 0.8, 0.95, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local field = self:img("field")
  if field then g.draw(field, 0, 0) end
  local list = {}
  for k = 0, 8 do
    local i = (3 + k) % 12
    local p = self.d.walkers[k] or self.d.walkers[tostring(k)]
    list[#list + 1] = { kind = "mon", m = self.mons[i], x = p[1], y = p[2], k = k, pr = (self.d.walkerPriority or {})[k] or k }
  end
  for i = 0, 11 do
    local b = self.balls[i]
    if b.state ~= 0 then
      local _, Y = M.toScreen(b.x, b.z)
      if Y < H + 32 then list[#list + 1] = { kind = "ball", b = b, y = Y } end
    end
  end
  table.sort(list, function(a, b) if a.y ~= b.y then return a.y < b.y end return (a.pr or 0) < (b.pr or 0) end)
  local faces = self.d.faces or { "left", "down", "right" }
  for _, e in ipairs(list) do
    if e.kind == "mon" then
      local m = e.m
      local dx = (m.shake > 0) and ((m.shake % 2 == 0) and 2 or -2) or 0
      local rgb = TEAM_RGB[m.team + 1]
      g.setColor(rgb[1], rgb[2], rgb[3], 0.8)
      g.ellipse("line", e.x + 0.5, e.y + 8.5, 10, 4)
      g.setColor(1, 1, 1, 1)
      local greyed = m.cond == 1
      local sh = greyed and self:grey() or nil
      if sh then g.setShader(sh) end
      local fh = self:walker(m, e.x + dx, e.y, faces[m.team] or "down")
      if sh then g.setShader() end
      local top = e.y - ((fh or 32) >= 64 and 40 or 25)
      if m.cond == 1 then self:sprite(self:anim("c", 2, self.t), e.x, top)
      elseif m.cond == 2 then self:sprite(self:anim("a", 0, self.t), e.x, top) end
      if self.pad.target == m.id and self.showAim then
        g.setColor(1, 1, 1, 0.9)
        g.circle("line", e.x + 0.5, e.y + 0.5, 14)
        g.setColor(1, 1, 1, 1)
      end
    else
      self:drawBall(e.b, 0)
    end
  end
  -- the HIT! pops (sprite set a seq 6) where our balls hit
  for _, p in ipairs(self.pops) do
    local X, Y = M.toScreen(p.x, p.z)
    self:sprite(self:anim("a", 6, p.t, true), X, Y - 8)
  end
  -- the clock and the seconds (022038A0; placed by eye)
  local Font = require("src.render.Font")
  self:sprite("a_5_0", 12, 12)
  g.setColor(0, 0, 0, 0.45)
  g.rectangle("fill", 22, 5, 22, 14)
  g.setColor(1, 1, 1, 1)
  Font.draw(("%2d"):format(math.floor((self.timer + 29) / 30)), 24, 8)
  -- the rival teams' flags and hits (a seq 1..4; placed by eye)
  local spots = { { 236, 72 }, { 175, 34 }, { 52, 72 } }
  for t = 1, 3 do
    local s = spots[t]
    self:sprite(("a_%d_0"):format(t + 1), s[1], s[2])
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", s[1] + 6, s[2] - 6, 22, 12)
    g.setColor(1, 1, 1, 1)
    Font.draw(("%2d"):format(self:teamHits(t)), s[1] + 8, s[2] - 4)
  end
  if self.cd then
    -- the shared 3-2-1 / FINISH (main engine = the top screen here)
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

-- one of ours: the back sprite fitted to the 80 x 80 frame (sprite set b,
-- seq anim + k), centred on (16 + 50 k, 88) with the frame's own offset
function M:drawOwn(m)
  local g = love.graphics
  local k = m.slot
  local a = m.anim
  local key = self:anim("b", a.seq + k, a.t * 2, a.seq ~= 1 and a.seq ~= 10)
  local _, rec = self:img(key)
  local ox = type(rec) == "table" and (tonumber(rec.originX) or -40) + 40 or 0
  local oy = type(rec) == "table" and (tonumber(rec.originY) or -40) + 40 or 0
  local cx, cy = 16 + 50 * k - ox, 88 - oy
  local img
  if m.mon then
    local ok, path = pcall(function() return require("src.pokemon.Sprites").path(self.game.data, m.mon.species, "back", { mon = m.mon }) end)
    if ok and type(path) == "string" then img = cachedImage(self, path) end
  end
  local sh = (m.cond == 1) and self:grey() or nil
  if sh then g.setShader(sh) end
  if img then
    local iw, ih = img:getDimensions()
    local s = 80 / math.max(iw, ih)
    g.draw(img, math.floor(cx - iw * s / 2), math.floor(cy - ih * s / 2), 0, s, s)
  elseif m.mon then
    self:icon(m.mon, cx, cy, math.floor(self.t / 8))
  else
    self:sprite(key, 16 + 50 * k, 88)
  end
  if sh then g.setShader() end
  if m.cond == 2 then self:sprite(self:anim("b", 0, self.t), 16 + 50 * k, 72) end
  if m.cond == 1 then self:sprite(self:anim("c", 2, self.t), 16 + 50 * k, 72) end
end

-- the touch screen: the snow, our three, their balls, the score
function M:drawBottom()
  local g = love.graphics
  g.setColor(0.8, 0.9, 0.95, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local sy = (self.shakeT > 0 and self.shakeT % 2 == 1) and 8 or 0
  local back = self:img("panel_back")
  if back then g.draw(back, 0, sy) end
  -- ours, the right-most first (02203E30: priority 0x13 - k)
  for k = 2, 0, -1 do self:drawOwn(self.mons[k]) end
  for i = 0, 11 do
    local b = self.balls[i]
    if b.state ~= 0 then self:drawBall(b, SUB_Y) end
  end
  local mid = self:img("panel_mid")
  if mid then g.draw(mid, 0, sy) end
  local front = self:img("panel_front")
  if front then g.draw(front, 0, sy) end
  -- the score in the glyphs (02203BD0: tile x 19 / 23 / 27, y 16)
  local digits = self:img("digits")
  if digits then
    local iw, ih = digits:getDimensions()
    local v = self:teamHits(0)
    local ds = { math.floor(v / 100) % 10, math.floor(v / 10) % 10, v % 10 }
    g.setColor(0.04, 0.2, 0.3, 1)
    g.rectangle("fill", 152, 128 + sy, 96, 56)
    g.setColor(1, 1, 1, 1)
    for i, d in ipairs(ds) do
      g.draw(digits, g.newQuad((d % 5) * 32, math.floor(d / 5) * 64, 32, 64, iw, ih), 152 + 32 * (i - 1), 128 + sy)
    end
  end
  local Font = require("src.render.Font")
  local save = self.game.save
  local name = (self.names and self.names[1]) or (save and ((save.player and save.player.name) or save.playerName or save.name))
  if type(name) == "string" then Font.draw(name, 40, 160 + sy) end
  -- the pad's thrower
  if self.showAim then
    local k = self.pad.thrower
    g.setColor(1, 1, 0.4, 0.9)
    g.rectangle("line", 16 + 50 * k - 20.5, 40.5, 40, 4)
    g.setColor(1, 1, 1, 1)
  end
  if self.countdown > 0 and not self.cd then
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", 112, 40, 32, 24)
    g.setColor(1, 1, 1, 1)
    Font.draw(tostring(math.ceil(self.countdown / 30)), 124, 48)
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
    -- one screen: the top screen's 3-2-1 / FINISH over the touch view too
    if self.cd then self.cd:draw(0) end
  end
end

return M
