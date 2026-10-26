-- HEARTGOLD / SOULSILVER POKeATHLON: BLOCK SMASH (event 3; pokeheartgold
-- asm/overlay_96.s, sub-app ov96_0221A830 = init 02209448 / draw 02209738 /
-- results 02209748 / exit 022097AC, states ov96_0221DC5C = 02209130 ready,
-- 0220935C play, 022093D0 end; the gameplay is 0x022091B4..0x0220D3FF and
-- the reading is written up in scratch_claude/athlon/NOTES.md "## Block
-- Smash"). Art and tables: `gen4_hgss_block_smash`
-- (src/import/Gen4HgssPokeathlonBlockSmashArt.lua).
--
-- THE GAME RUNS AT 30 TICKS A SECOND: the clock starts at 900 and shows
-- clock / 30 (02209E70); every rule below counts those ticks.
--
-- READ FROM CODE:
--   * the stack (0220A744 / 0220AD64): ten blocks of 100 HP at x 120, block k
--     landing at y 168 - 4k; an empty stack refills one block every third
--     tick, each falling from y 0 with its speed + 20 a tick (0220AF64); the
--     strikes wait until all ten have landed (SE 0x8BD). Each block has one
--     crack, at a corner other than the last one's: (-12,-12) (2,-13)
--     (-16,-4) (-2,-4) + rand 0..15 x, 0..11 y (0220AFF8)
--   * a strike (022091B4): a touch on the top block's face (0220A910: within
--     y -18..+12 of it, inside the parallelogram (-30,12) (-16,-18) (16,12)
--     (30,-18)), allowed when the striker is idle or 2+ ticks after its last
--     strike (0220B7CC). Damage = the POWER table (20 40 60 80 100), + 150 in
--     High Tension, else + 160 on the crack; it goes through as many blocks
--     as it kills, the rest carried down (0220AAEC). A block left at <= 60 HP
--     shows cracked, <= 20 crumbling
--   * the crack's hitbox (0220B0A4, ov96_0221DC68) by the SKILL table
--     (0 1 1 2 2): two small rects round the crack, +-1..3 px
--   * FATIGUE (0220B634 / 0220D33C / 0220D2AC): stamina = the STAMINA table
--     (40 60 80 100 120); a strike within 10 ticks of the last costs
--     0 4 4 4 3 3 3 2 2 2 (by ticks since it); 0 = FAINT (the course's
--     fail / miss), out until stamina is back to 8. The striker gets +8 every
--     60 ticks, the two on the bench +5 every 30. Tired (the SWITCH button
--     blinks red, sweat) at <= 40% (0220C768)
--   * TENSION (0220C714 / 0220C680): + 30 for a crack hit; it drains 1 every
--     2 ticks; blue aura from 50; at 100 HIGH TENSION (red aura, SE 0x8BF)
--     for 90 ticks, then tension 0 and the striker's stamina set to 10. The
--     drain and the timer stop while the stack refills
--   * SWITCH (0220A298 / 0220C578): the SWITCH button (x 0..64, y 8..32), or a
--     flick up of 32+ px within 10 ticks on the Pokemon (x 96..176, y 72..152);
--     allowed when idle or striking; tension - 10, High Tension ends (stamina
--     10), the next of the three steps up
--   * the rival teams (0220C93C .. 0220D0F8): the same tables from their
--     Pokemon's stars, one block of 100 HP at a time (no stack, but a 42-tick
--     pause each 10 blocks), a decision every 4..6 ticks: switch at
--     rand%100 < (85 75 10 10 0 by stamina < 5 10 15 20 30) + (-50 -20 -10 by
--     tension >= 90 80 70) -- the switch sets the outgoing stamina to 10 and
--     takes 26 ticks; else crack at rand%100 < 4 / 8 / 16 (by Skill level);
--     while still "hot" (within 10 ticks) only at rand%100 < (100 100 100 80
--     60 by stamina >= 100 40 20 8 0) + (100 60 20 10 by tension >= 100 90 80
--     70). In High Tension they spend no stamina and gain no tension
--   * score = blocks broken (the counter stops at 200); the end hands each
--     team's count to the course (022093D0)
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): 02209448 puts them on the main
--     engine at y offset 0 (021E61D8 r1, its SpriteSystem list), the touch
--     screen here (gSystem.screensFlipped = 1, main surface at 0); 02209130
--     runs the countdown once the stack stands (0220AD34 == 2), and the
--     finish (02209394) with the field stopped
--   * the record (src/pokemon/HgssPokeathlonRecords.lua): at time up
--     022091B4 -> 0220A5DC hands ov96_021E8318 the blocks (0220AD4C) for
--     NEW RECORD! (021E839C, higher is better); the same count is the
--     field_5E0 the course's end saves
-- Code against Bulbapedia: the PLAYER still spends stamina in High Tension
-- (0220B634 has no check; only the rivals' 0220CE04 skips it) -- kept as
-- the code has it.
-- Scoring: Athlete Points = blocks broken, at most 200.
--
-- STAND-INS, said so: the striker is the Pokemon's back sprite (the game
-- loads a sprite of its own through ov96_021EEBE4, not read); the switch
-- animation is the rivals' 26 ticks (the player's 0220B9A8 ball toss not
-- timed); the event's own intro sprite (021E62AC from 02209130) is not
-- drawn; without `gen4_hgss_athlon_common` the 3-2-1 and TIME UP are the
-- font; the digits and the bar text
-- (messages 154/159/301 of bank 309) are the font; the pad strikes the top
-- block at the crack with +-4 px of jitter (A), switches with X / UP.

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local CLOCK = 900
local BLOCK_HP = 100
local STACK_X, STACK_Y = 120, 168
local MON_X, MON_Y = 136, 112
local CRACK_AT = { { -12, -12 }, { 2, -13 }, { -16, -4 }, { -2, -4 } }
-- ov96_0221CDBC / CDB0 / CDA4: { top, bottom, left, right } round the crack
local CRACK_BOX = {
  [0] = { { -2, 2, -1, 1 }, { -1, 1, -2, 2 } },
  { { -2, 2, -2, 2 }, { -1, 1, -3, 3 } },
  { { -2, 2, -3, 3 }, { -3, 3, -2, 2 } },
}
local COST = { [0] = 0, 4, 4, 4, 3, 3, 3, 2, 2, 2 }     -- ov96_0221CE5C
local SWITCH_TICKS = 26
local SE = { hit = 0x8B8, smash = 0x8B9, crack = 0x8BB, loaded = 0x8BD, drop = 0x8C1,
  high = 0x8BF, blue = 0x8C0, faint = 0x890, switch = 0x8B4, ok = 0x89B, no = 0x89C }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL
local POWER, STAMINA, SKILL = 0, 1, 2
local DEFAULT_PARAMS = { [0] = 20, 40, 60, 80, 100, 40, 60, 80, 100, 120, 0, 1, 1, 2, 2 }

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function clampStar(s) s = tonumber(s) or 2; return math.max(0, math.min(4, s)) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_block_smash
  return type(d) == "table" and d.params ~= nil and d.bottom ~= nil and d.a_1_0 ~= nil
end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

-- one Pokemon's record (ov96_0220D200): damage, stamina, crack level
local function athlete(p, mon, st)
  local maxSt = p[5 + clampStar(st[STAMINA])]
  return { mon = mon, dmg = p[clampStar(st[POWER])], maxSt = maxSt, st = maxSt,
    skill = p[10 + clampStar(st[SKILL])], score = 0, hits = 0, faints = 0, switches = 0 }
end

-- opts: team (three Pokemon), rivals ({{3},{3},{3}}), onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, sub = 0, images = {},
    fx = {}, debris = {} }, M)
  local d = game.data.gen4_hgss_block_smash
  self.d = d
  local p = d.params or DEFAULT_PARAMS
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  self.team = {}
  for k = 1, 3 do
    local mon = opts.team and opts.team[k]
    local st = mon and P.stars(game.data, mon, mon.aprijuice) or { [0] = 2, 2, 2, 2, 2 }
    self.team[k] = athlete(p, mon, st)
  end
  self.cur, self.state, self.counter, self.rec = 1, "idle", 0, 0
  self.tension, self.high, self.tcount = 0, false, 0
  self.blocks, self.mode, self.loadCount, self.lastCorner, self.total = {}, "load", 0, 0, 0
  -- the rivals at their species' base stars (made-up stars without a course)
  self.rivals = {}
  for t = 1, 3 do
    local r = { mons = {}, cur = 1, state = 0, fc = 0, interval = 4, hp = BLOCK_HP, count = 0,
      tension = 0, high = false, tcount = 0, rec = 0, hot = false, since = 0 }
    for k = 1, 3 do
      local mon = opts.rivals and opts.rivals[t] and opts.rivals[t][k]
      local row = mon and P.row(game.data, mon)
      local st = row and row.base or { [0] = 1 + rand(3), 1 + rand(3), 1 + rand(3), 1 + rand(3), 1 + rand(3) }
      r.mons[k] = athlete(p, mon, st)
    end
    self.rivals[t] = r
  end
  self.clock = CLOCK
  self.countdown = nil
  -- the shared 3-2-1 / FINISH sprite at y offset 0 (02209448)
  if CD.available(game) then self.cd = CD.new(game, 0) end
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

-- --------------------------------------------------------------- the stack --

function M:topBlock() return self.blocks[#self.blocks] end

function M:spawnBlock()
  local k = #self.blocks
  -- 0220AFF8: a corner other than the last one's
  local c = rand(3)
  if c >= self.lastCorner then c = c + 1 end
  self.lastCorner = c
  local at = CRACK_AT[c + 1]
  self.blocks[k + 1] = { slot = k, hp = BLOCK_HP, x = STACK_X, y = 0, vy = 0, falling = true, anim = 1,
    cx = at[1] + rand(16), cy = at[2] + rand(12) }
  se(self, SE.drop)
end

function M:stepStack()
  if self.mode == "load" then
    if #self.blocks >= 10 then
      local landed = true
      for _, b in ipairs(self.blocks) do if b.falling then landed = false end end
      if landed then self.mode = "ready"; se(self, SE.loaded) end
    else
      local before = self.loadCount
      self.loadCount = self.loadCount + 1
      if before >= 2 then self.loadCount = 0; self:spawnBlock() end
    end
  elseif #self.blocks == 0 then
    self.mode, self.loadCount = "load", 0
  end
  for _, b in ipairs(self.blocks) do
    if b.falling then
      b.vy = b.vy + 20
      b.y = b.y + b.vy
      local target = STACK_Y - 4 * b.slot
      if b.y >= target then b.y, b.falling = target, false end
    end
  end
  for i = #self.debris, 1, -1 do
    local q = self.debris[i]
    q.x = q.x + q.vx
    q.vx = q.vx * 4 / 3
    q.y = q.y - q.vy
    q.vy = q.vy - 4 / 4096
    if q.x < 0 or q.x > 256 then table.remove(self.debris, i) end
  end
  for i = #self.fx, 1, -1 do
    local f = self.fx[i]
    f.t = f.t + 1
    if f.t > (f.life or 12) then table.remove(self.fx, i) end
  end
end

-- 0220A910: the touch on the top block's face
function M:onBlock(tx, ty)
  local b = self:topBlock()
  if not b or self.mode ~= "ready" then return false end
  if ty < b.y - 18 or ty > b.y + 12 then return false end
  local x, y = tx - b.x, ty - b.y
  if x >= -16 and x <= 16 then return true end
  if x >= -30 and x <= -16 then
    local y1 = 12 + (x + 30) * (-18 - 12) / 14
    return y >= y1
  end
  if x >= 16 and x <= 30 then
    local y2 = 12 + (x - 16) * (-18 - 12) / 14
    return y <= y2
  end
  return false
end

function M:onCrack(tx, ty, level)
  local b = self:topBlock()
  if not b then return false end
  local cx, cy = b.x + b.cx, b.y + b.cy
  for _, r in ipairs(CRACK_BOX[level] or CRACK_BOX[0]) do
    if ty >= cy + r[1] and ty <= cy + r[2] and tx >= cx + r[3] and tx <= cx + r[4] then return true end
  end
  return false
end

-- 0220AAEC: the strike; returns the blocks broken and whether the stack emptied
function M:smash(a, tx, ty, crack)
  local dmg = a.dmg
  if self.high then dmg = dmg + 150; se(self, SE.crack)
  elseif crack then dmg = dmg + 160; se(self, SE.crack) end
  self.fx[#self.fx + 1] = { key = (crack or self.high) and "a_18" or "a_7", x = tx, y = ty, t = 0, life = 20 }
  local broken = 0
  while #self.blocks > 0 and dmg > 0 do
    local b = self:topBlock()
    b.hp = b.hp - dmg
    if b.hp > 0 then break end
    table.remove(self.blocks)
    if self.total < 200 then self.total = self.total + 1 end
    a.score = a.score + 1
    broken = broken + 1
    dmg = -b.hp
    -- 0220B1D8: four chips flying out (fx32 speeds, here in pixels)
    for k = 0, 3 do
      self.debris[#self.debris + 1] = { x = b.x, y = b.y, vx = (k % 2 == 0 and 1 or -1) * (4 + rand(8) + 0.5),
        vy = 8 + rand(8) + 0.5, key = "a_" .. (28 + k % 3) }
    end
  end
  if broken > 0 then
    se(self, SE.smash)
  else
    se(self, SE.hit)
    self.fx[#self.fx + 1] = { key = "a_6", x = tx, y = ty, t = 0, life = 9 }
    local b = self:topBlock()
    if b then
      if b.hp <= 20 then b.anim = 3 elseif b.hp <= 60 then b.anim = 2 end
    end
  end
  return broken, broken > 0 and #self.blocks == 0
end

-- ---------------------------------------------------------- the striker --

function M:striker() return self.team[self.cur] end

function M:canSwitch() return self.state == "idle" or self.state == "hit" end
function M:canHit() return self.state == "idle" or (self.state == "hit" and self.counter >= 2) end

function M:endHigh()
  self.high, self.tcount, self.tension = false, 0, 0
  self:striker().st = 10
end

function M:switch()
  if not self:canSwitch() then se(self, SE.no); self.buttonFlash = { "a_22", 8 }; return false end
  se(self, SE.ok)
  self.buttonFlash = { "a_20", 6 }
  local a = self:striker()
  a.switches = a.switches + 1
  self.tension = math.max(0, math.min(100, self.tension - 10))
  if self.high then self:endHigh() end
  self.cur = self.cur % 3 + 1
  self.state, self.counter = "switch", 0
  se(self, SE.switch)
  self.fx[#self.fx + 1] = { key = "a_15", x = MON_X, y = MON_Y, t = 0, life = 24 }
  return true
end

function M:strike(tx, ty)
  local a = self:striker()
  local crack = self:onCrack(tx, ty, a.skill)
  local broken, cleared = self:smash(a, tx, ty, crack)
  -- 0220B634
  if self.state == "hit" then
    a.st = math.max(0, a.st - (COST[math.min(9, self.counter)] or 0))
    if a.st == 0 then
      a.faints = a.faints + 1
      self.state, self.counter, self.rec = "faint", 0, 0
      se(self, SE.faint)
      return
    end
  end
  if not self.high and crack then
    self.tension = math.min(100, self.tension + 30)
    if self.tension >= 100 then
      self.high, self.tcount = true, 0
      se(self, SE.high)
    end
  end
  a.hits = a.hits + 1
  self.state, self.counter = "hit", 0
  if crack then self.shake = { 16, 2 } elseif cleared or self.high then self.shake = { 4, 1 } end
end

-- 0220D2AC: stamina back over time
local function recover(team, cur, rec)
  if rec == 0 then return end
  for k, a in ipairs(team) do
    if a.st < a.maxSt then
      if k == cur then
        if rec % 60 == 0 then a.st = a.st + 8 end
      elseif rec % 30 == 0 then
        a.st = a.st + 5
      end
      if a.st > a.maxSt then a.st = a.maxSt end
    end
  end
end

function M:stepStriker(loading)
  if self.state == "hit" then
    self.counter = self.counter + 1
    if self.counter >= 10 then self.state, self.counter = "idle", 0 end
  elseif self.state == "faint" then
    if self:striker().st >= 8 then self.state, self.counter = "idle", 0 end
  elseif self.state == "switch" then
    self.counter = self.counter + 1
    if self.counter >= SWITCH_TICKS then self.state, self.counter = "idle", 0 end
  end
  -- 0220C680: the tension clock, stopped while the stack refills
  if not loading and self.state ~= "switch" then
    if self.high then
      self.tcount = self.tcount + 1
      if self.tcount >= 90 then self:endHigh() end
    elseif self.tension > 0 then
      self.tcount = self.tcount + 1
      if self.tcount >= 2 then self.tcount, self.tension = 0, self.tension - 1 end
      if self.tension >= 50 and not self.blue then se(self, SE.blue) end
      self.blue = self.tension >= 50
    else
      self.blue = false
    end
  end
  recover(self.team, self.cur, self.rec)
  self.rec = (self.rec + 1) % 2048
end

function M:tired(a)
  return a.st > 0 and a.st * 100 / a.maxSt <= 40
end

-- ------------------------------------------------------------- the rivals --

local function firstAtLeast(v, cuts, vals)
  for i, c in ipairs(cuts) do if v >= c then return vals[i] end end
  return 0
end
local function firstBelow(v, cuts, vals)
  for i, c in ipairs(cuts) do if v < c then return vals[i] end end
  return 0
end

-- 0220CD84
local function rivalState(r, s)
  if s == 1 then
    r.tension = math.max(0, math.min(100, r.tension - 10))
    r.cur = r.cur % 3 + 1
  elseif s == 2 then
    r.rec = 0
  end
  r.state, r.fc = s, 0
end

-- 0220D0F8: the end of High Tension (and every switch): stamina 10
local function rivalCool(r)
  r.high, r.tcount, r.tension = false, 0, 0
  r.mons[r.cur].st = 10
end

-- 0220CE04
function M:rivalHit(r, crack)
  local a = r.mons[r.cur]
  local dmg = a.dmg + (crack and 160 or 0)
  local broken = 0
  r.hp = r.hp - dmg
  while r.hp <= 0 do
    dmg = -r.hp
    r.hp = BLOCK_HP
    broken = broken + 1
    a.score = a.score + 1
    r.hp = r.hp - dmg
  end
  r.count = math.min(255, r.count + broken)
  if not r.high then
    if r.hot then
      a.st = math.max(0, a.st - (COST[math.min(9, r.since)] or 0))
      if a.st == 0 then
        a.faints = a.faints + 1
        rivalState(r, 2)
        return
      end
    end
    if crack then r.tension = math.min(100, r.tension + 30) end
    if r.tension >= 100 then r.high, r.tcount = true, 0 end
  end
  if broken > 0 and r.count % 10 == 0 then rivalState(r, 3) end
  r.hot, r.since = true, 0
  a.hits = a.hits + 1
end

-- 0220CA28 / 0220CAC4
function M:stepRival(r)
  local a = r.mons[r.cur]
  if r.state == 0 then
    r.fc = r.fc + 1
    if r.fc >= r.interval then
      local switchOdds = firstBelow(a.st, { 5, 10, 15, 20, 30 }, { 85, 75, 10, 10, 0 })
        + firstAtLeast(r.tension, { 90, 80, 70 }, { -50, -20, -10 })
      if rand(100) < switchOdds then
        rivalCool(r)
        a.switches = a.switches + 1
        rivalState(r, 1)
      else
        local crack = rand(100) < ({ [0] = 4, 8, 16 })[a.skill]
        if r.hot then
          local go = firstAtLeast(a.st, { 100, 40, 20, 8, 0 }, { 100, 100, 100, 80, 60 })
            + firstAtLeast(r.tension, { 100, 90, 80, 70 }, { 100, 60, 20, 10 })
          if r.since >= 2 and rand(100) < go then self:rivalHit(r, crack) end
        else
          self:rivalHit(r, crack)
        end
      end
      r.fc = 0
      r.interval = 4 + rand(3)
    end
    if r.hot then
      r.since = r.since + 1
      if r.since >= 10 then r.hot, r.since = false, 0 end
    end
  elseif r.state == 1 then
    r.fc = r.fc + 1
    if r.fc >= SWITCH_TICKS then rivalState(r, 0) end
  elseif r.state == 2 then
    if r.mons[r.cur].st >= 8 then rivalState(r, 0) end
  elseif r.state == 3 then
    r.fc = r.fc + 1
    if r.fc >= 0x2a then rivalState(r, 0) end
  end
  -- 0220D07C
  if r.state ~= 3 then
    if r.high then
      r.tcount = r.tcount + 1
      if r.tcount >= 90 then rivalCool(r) end
    elseif r.tension > 0 then
      r.tcount = r.tcount + 1
      if r.tcount >= 2 then r.tcount, r.tension = 0, r.tension - 1 end
    end
  end
  recover(r.mons, r.cur, r.rec)
  r.rec = (r.rec + 1) % 2048
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
  self.taps = self.taps or {}
  self.taps[#self.taps + 1] = { px, py }
  return true
end

function M:touchmoved(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if px and self.swipe then self.swipe.y = py end
  return true
end

function M:touchreleased(_, x, y)
  local px, py = toLocal(self.game, x, y)
  if self.swipe then
    if py then self.swipe.y = py end
    self.swipe.released = true
  end
  return true
end

-- one tap (0220A298 + the strike in 022091B4)
function M:tap(px, py)
  if px >= 0 and px <= 64 and py >= 8 and py <= 32 then return self:switch() end
  local on = self:onBlock(px, py)
  if on or (px >= 0x60 and px <= 0xB0 and py >= 0x48 and py <= 0x98) then
    self.swipe = { y0 = py, y = py, held = 0 }
  end
  if on and self:canHit() and self.mode == "ready" then self:strike(px, py) end
end

function M:padStrike()
  local b = self:topBlock()
  if not b then return end
  self:tap(b.x + b.cx + rand(9) - 4, b.y + b.cy + rand(9) - 4)
end

-- ---------------------------------------------------------------- update --

function M:update()
  local input = self.game.input
  if input then
    if input:wasPressed("a") then self.padA = true end
    if input:wasPressed("x") or input:wasPressed("up") then self.padSwitch = true end
    self.showTop = input.isDown and (input:isDown("select") or input:isDown("l")) or false
  end
  -- 30 ticks a second
  self.sub = (self.sub + 1) % 2
  if self.sub == 1 then return end
  self:tick()
end

function M:tick()
  self.t = self.t + 1
  if self.buttonFlash then
    self.buttonFlash[2] = self.buttonFlash[2] - 1
    if self.buttonFlash[2] <= 0 then self.buttonFlash = nil end
  end
  if self.shake then
    self.shake[1] = self.shake[1] - self.shake[2]
    if self.shake[1] <= 0 then self.shake = nil end
  end
  if self.over then
    self.over = self.over - 1
    self.taps, self.padA, self.padSwitch = nil, nil, nil
    -- the FINISH (021E667C), the field stopped (02209394)
    if self.cd then
      if not self.cd:finishing() then return self:finish() end
      return
    end
    if self.over <= 0 then return self:finish() end
    return
  end
  -- 02209130: the stack fills, then the 3-2-1
  if not self.countdown then
    self:stepStack()
    if self.mode == "ready" then self.countdown = 90 end
    self.taps, self.padA, self.padSwitch = nil, nil, nil
    return
  end
  if self.countdown > 0 then
    -- the shared 3-2-1 (021E637C)
    if self.cd then
      if self.cd:countdown() then self.countdown = 0 end
    else
      self.countdown = self.countdown - 1
    end
    self.taps, self.padA, self.padSwitch = nil, nil, nil
    return
  end
  -- 022091B4
  self:stepStack()
  local loading = self.mode == "load"
  self:stepStriker(loading)
  for _, r in ipairs(self.rivals) do self:stepRival(r) end
  if self.swipe then
    self.swipe.held = self.swipe.held + 1
    if self.swipe.released then
      if self.swipe.y0 - self.swipe.y >= 32 and self:canSwitch() then self:switch() end
      self.swipe = nil
    elseif self.swipe.held >= 10 then
      self.swipe = nil
    end
  end
  for _, tp in ipairs(self.taps or {}) do self:tap(tp[1], tp[2]) end
  self.taps = nil
  if self.padSwitch then self:switch() end
  if self.padA then self:padStrike() end
  self.padA, self.padSwitch = nil, nil
  if self.clock > 0 then self.clock = self.clock - 1 end
  if self.clock == 0 then
    self.over = 60
    -- 022091B4 -> 0220A5DC: the blocks to ov96_021E8318 (021E839C)
    if self.cd then self.cd:startFinish(Rec.isNew(self.game, 3, self.total)) end
  end
end

function M:finish()
  local points, stats = {}, { {}, {}, {}, {} }
  points[1] = math.min(200, self.total)
  for k, a in ipairs(self.team) do
    stats[1][k] = { miss = a.faints > 0, score = a.score, hit = a.hits, fail = a.faints, switch = a.switches }
  end
  for t, r in ipairs(self.rivals) do
    points[t + 1] = math.min(200, r.count)
    for k, a in ipairs(r.mons) do
      stats[t + 1][k] = { miss = a.faints > 0, score = a.score, hit = a.hits, fail = a.faints }
    end
  end
  self.game.stack:pop()
  if self.onDone then self.onDone({ points = points, blocks = self.total, stats = stats, record = self.total }) end
end

-- ------------------------------------------------------------------- draw --

-- a saved image (rec.path) or one decoded in memory (rec.image, ImageData)
function M:img(key)
  local rec = self.d[key]
  if rec == nil then return nil end
  if self.images[key] == nil then
    local img
    if type(rec) == "table" and rec.image and not rec.path then
      local ok, r = pcall(love.graphics.newImage, rec.image)
      img = ok and r or nil
    else
      local path = type(rec) == "table" and rec.path or rec
      local ok, r = pcall(Assets.image, path)
      img = ok and r or nil
    end
    if img then img:setFilter("nearest", "nearest") end
    self.images[key] = img or false
  end
  return self.images[key] or nil, rec
end

function M:sprite(key, x, y)
  local img, rec = self:img(key)
  if not img then return false end
  local ox = type(rec) == "table" and tonumber(rec.originX) or 0
  local oy = type(rec) == "table" and tonumber(rec.originY) or 0
  love.graphics.draw(img, math.floor(x + ox), math.floor(y + oy))
  return true
end

-- a sequence's frame at tick t (looping, or held on the last frame)
function M:seqKey(set, seq, t, hold)
  local durs = self.d.objSeq and self.d.objSeq[set] and self.d.objSeq[set][seq]
  local n = durs and #durs or 1
  if not durs or n <= 1 then return ("%s_%d_0"):format(set, seq) end
  local total = 0
  for _, v in ipairs(durs) do total = total + v end
  local at = hold and math.min(t, total - 1) or (t % total)
  for f, v in ipairs(durs) do
    if at < v then return ("%s_%d_%d"):format(set, seq, f - 1) end
    at = at - v
  end
  return ("%s_%d_%d"):format(set, seq, n - 1)
end

function M:monImage(mon, side)
  if not mon then return nil end
  self.monImgs = self.monImgs or {}
  local key = tostring(mon.species) .. side
  if self.monImgs[key] == nil then
    local ok, path = pcall(function() return require("src.pokemon.Sprites").path(self.game.data, mon.species, side, { mon = mon }) end)
    local img
    if ok and path then
      local ok2, r = pcall(Assets.image, path)
      if not ok2 then ok2, r = pcall(love.graphics.newImage, path) end
      img = ok2 and r or nil
    end
    if img then img:setFilter("nearest", "nearest") end
    self.monImgs[key] = img or false
  end
  return self.monImgs[key] or nil
end

function M:monIcon(mon, x, y, frame, scale)
  if not mon then return end
  local data = self.game.data
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (data.icons and data.icons.bySpecies and data.icons.bySpecies[mon.species]) or (def and def.icon)
  local path, fh = entry, nil
  if type(entry) == "table" then path, fh = entry.image, tonumber(entry.frameHeight) end
  if type(path) ~= "string" then return end
  self.icons = self.icons or {}
  if self.icons[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.icons[path] = ok and img or false
    if self.icons[path] then self.icons[path]:setFilter("nearest", "nearest") end
  end
  local img = self.icons[path]
  if not img then return end
  scale = scale or 1
  local iw, ih = img:getDimensions()
  fh = fh or math.min(iw, ih)
  local frames = math.max(1, math.floor(ih / fh))
  local q = love.graphics.newQuad(0, ((frame or 0) % frames) * fh, iw, fh, iw, ih)
  love.graphics.draw(img, q, math.floor(x - iw * scale / 2), math.floor(y - fh * scale / 2), 0, scale, scale)
end

-- the striker: the back sprite fitted to 80 x 80 round (136, 112)
function M:drawStriker()
  local a = self:striker()
  if self.state == "switch" and self.counter < SWITCH_TICKS / 2 then
    self:sprite(self:seqKey("a", 27, self.t), MON_X, MON_Y + 8)
    return
  end
  local img = self:monImage(a.mon, "back")
  local bob = (self.state == "hit" and self.counter < 3) and 4 or 0
  if img then
    local iw, ih = img:getDimensions()
    local s = 80 / math.max(iw, ih)
    love.graphics.draw(img, math.floor(MON_X - iw * s / 2), math.floor(MON_Y - ih * s / 2 + bob), 0, s, s)
  else
    self:monIcon(a.mon, MON_X, MON_Y + bob, math.floor(self.t / 8), 2)
  end
end

function M:drawBottom()
  local g = love.graphics
  g.setColor(0.2, 0.18, 0.16, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local sx = 0
  if self.shake then sx = ((self.t % 2 == 0) and 1 or -1) * self.shake[1] / 4 end
  g.push()
  g.translate(math.floor(sx), 0)
  local bg = self:img("bottom")
  if bg then g.draw(bg, 0, 0) end
  -- the striker, its aura, sweat / faint
  local a = self:striker()
  if self.high then self:sprite(self:seqKey("a", 16, self.t), MON_X, MON_Y)
  elseif self.tension >= 50 then self:sprite(self:seqKey("a", 17, self.t), MON_X, MON_Y) end
  self:drawStriker()
  if a.st == 0 then self:sprite(self:seqKey("a", 26, self.t), MON_X, MON_Y - 24)
  elseif self:tired(a) then self:sprite(self:seqKey("a", 24, self.t), MON_X, MON_Y - 24) end
  -- the stack, bottom up: each block with its crack
  for _, b in ipairs(self.blocks) do
    self:sprite("a_" .. b.anim .. "_0", b.x, b.y)
    self:sprite("a_4_0", b.x + b.cx, b.y + b.cy)
  end
  for _, q in ipairs(self.debris) do self:sprite(q.key .. "_0", q.x, q.y) end
  for _, f in ipairs(self.fx) do
    local set, seq = f.key:match("^(%a)_(%d+)$")
    self:sprite(self:seqKey(set, tonumber(seq), f.t, true), f.x, f.y)
  end
  g.pop()
  -- SWITCH (0220A298: 0x13 normal, 0x15 not now, 0x17 tired)
  local btn = "a_19_0"
  if self.buttonFlash then btn = self.buttonFlash[1] .. "_0"
  elseif not self:canSwitch() then btn = "a_21_0"
  elseif self:tired(a) then btn = self:seqKey("a", 23, self.t) end
  self:sprite(btn, 32, 16)
  -- the blocks broken (bottom left) and the clock (bottom right)
  local Font = require("src.render.Font")
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", 0, 168, 56, 16)
  g.rectangle("fill", 184, 176, 72, 16)
  g.setColor(1, 1, 1, 1)
  Font.draw(("%03d"):format(self.total), 4, 169)
  self:sprite("a_25_0", 192, 184)
  Font.draw(("%02d"):format(math.max(0, math.floor(self.clock / 30)) % 100), 206, 177)
  if self.cd then
    -- the shared 3-2-1 / FINISH (main engine = this screen, surface at 0)
    self.cd:draw(0)
  elseif self.countdown and self.countdown > 0 then
    Font.draw(tostring(math.ceil(self.countdown / 30)), 124, 40)
  elseif self.over then
    Font.draw("TIME UP!", 96, 40)
  end
end

function M:drawTop()
  local g = love.graphics
  g.setColor(0.3, 0.3, 0.3, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local bg = self:img("top")
  if bg then g.draw(bg, 0, 0) end
  local bar = self:img("top_bar")
  if bar then g.draw(bar, 0, 0) end
  -- the bench: the next one at (40, 136), the one after at (40, 48)
  local nextK, afterK = self.cur % 3 + 1, (self.cur + 1) % 3 + 1
  for _, e in ipairs({ { nextK, 136 }, { afterK, 48 } }) do
    local a = self.team[e[1]]
    self:monIcon(a.mon, 40, e[2], math.floor(self.t / 8), 2)
    if self:tired(a) then self:sprite(self:seqKey("b", 17, self.t), 40, e[2] - 24) end
  end
  -- the four tallies (0220A14C): a slab per 5 blocks, a big stack per 100
  local counts = { self.total }
  for t, r in ipairs(self.rivals) do counts[t + 1] = r.count end
  for t = 0, 3 do
    local x = 0x78 + 0x20 * t
    local n = math.floor((counts[t + 1] or 0) / 5)
    if n > 20 then
      for i = 0, 4 do self:sprite(("b_%d_0"):format(3 * t + 3), x + 6, 0x88 - 0x10 * i - 0x14) end
      n = n - 20
    end
    n = math.min(20, n)
    for i = 0, n - 1 do self:sprite(("b_%d_3"):format(3 * t + 2), x + 6, 0x88 - 4 * i) end
    local mon = t == 0 and self:striker().mon or (self.rivals[t].mons[self.rivals[t].cur].mon)
    if mon then self:monIcon(mon, x, 0x98, 0, 1) else self:sprite(("b_%d_0"):format(13 + t), x, 0x98) end
  end
  local Font = require("src.render.Font")
  local a = self:striker()
  local def = a.mon and self.game.data.pokemon and self.game.data.pokemon[a.mon.species]
  local name = a.mon and (a.mon.nickname or a.mon.name or (def and def.name)) or ""
  Font.draw(tostring(name), 4, 177)
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
