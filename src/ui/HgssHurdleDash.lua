-- HEARTGOLD / SOULSILVER POKeATHLON: HURDLE DASH (pokeheartgold
-- asm/overlay_96.s 0x021F94A8..0x021FC758; the reading is written up in
-- scratch_claude/athlon/NOTES.md). Art and tables: `gen4_hgss_hurdle_dash`
-- (src/import/Gen4HgssHurdleDashArt.lua).
--
-- READ FROM CODE (the per-runner update 021FA34C and its helpers):
--   * a runner speeds up by its acceleration (Skill: params[10 + stars] / 100)
--     to its top speed (Speed: params[15 + stars] / 10) each frame, and moves
--     that far; it finishes at distance 0x1000 and runs out to 0x1080
--   * the course: one of the three layouts (/a/2/2/6, LCRandom % 3); a lane's
--     hurdle stands at cell c (distance / 8); it is put on the track when the
--     runner's cell reaches it, at y -8, and comes down the screen at the
--     runner's speed (021FC0FC / 021FBF90 / 021FBEFC)
--   * a tap on a lane (|x - laneX| < 24, 88 < y < 168 on the touch screen)
--     jumps its runner (021FB784 / 021FA7BC): rise params[stars] frames,
--     hang params[5 + stars] frames, fall, the heights from the jump tables by
--     Jump stars (ov96_0221C55C / C589 -- 0 stars only sinks: Diglett digs)
--   * a jump started with a hurdle just ahead (the feet within 24 px under
--     it, 021FAB04) is a GOOD JUMP (021FBCB8): the combo goes up (to 4) and the
--     speed becomes top speed + 1.0 and stays there (no acceleration while the
--     combo lasts) -- the boost tunnel, blue, red at 4
--   * a runner on the ground that meets a hurdle knocks it over and TRIPS
--     (021FA34C): speed 0.5, combo 0, 30 frames down
--   * the rivals (021FBA3C): the same speeds from their Pokemon's stars; at
--     each hurdle LCRandom % 100 against their temperament (good, trip):
--     (10,50) (20,50) (30,60) (20,70) (30,70) (40,80)
--   * the event ends when the player's three have finished; a team's time is
--     the sum of its three finish times
--   * the 3-2-1 and the FINISH are the course's shared sprites
--     (src/ui/HgssPokeathlonCountdown.lua): ov96_021F94A8 puts them on the
--     main engine at y offset 0x110 (021E6290 r1), the touch screen here
--     (gSystem.screensFlipped = 1), whose sprite surface starts at 0x110
--     (021EB5C8); 021F9240 runs the countdown before the race and the finish
--     once the player's three are home, the field running on until it ends
--   * the record (src/pokemon/HgssPokeathlonRecords.lua): once the three are
--     home 021F9240 hands ov96_021E8318 the sum of their finish ticks (u16)
--     for NEW RECORD! (021E839C, lower is better); the end state 021F9380
--     saves field_5E0 = that sum cut to tenths of a second (021FBDEC:
--     30 (s / 30) + 3 ((s % 30) / 3)), committed at the course's end
-- THE CLOCK: the events run their logic at 30 ticks a second (Relay Run's
-- 2700-tick 90 s, Block Smash's 900-tick 30 s), so every speed and frame
-- count here is per tick, one tick every other frame; times are ticks / 30.
-- Scoring (Bulbapedia; the results app is still to be read): Athlete Points
-- = floor(11500 / the team's time in seconds).
--
-- The rivals are the course's opponents' Pokemon at their species' base
-- stars (ov96_021E8484).
-- STAND-INS, said so: the top screen shows the upper track and the clock;
-- without `gen4_hgss_athlon_common` the 3-2-1 is text.

local SecondScreen = require("src.ui.SecondScreen")
local Assets = require("src.render.Assets")
local CD = require("src.ui.HgssPokeathlonCountdown")
local Rec = require("src.pokemon.HgssPokeathlonRecords")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local LANES = { 48, 128, 208 }
local FINISH, RUNOUT = 0x1000, 0x1080
local FOOT = 0x78 + 0x110            -- the runner's feet in sprite space (392)
local VIEW_SHIFT = 24                -- sprite space -> the two screens (0..383)
local RISE = { [0] = { -4, -4, -4, -4, 0, 0, 0, 0, 0 }, { -2, -3, 6, 12, 16, 17, 18, 18, 18 },
  { -2, -3, 6, 11, 15, 17, 18, 19, 20 }, { -2, -3, 6, 11, 15, 17, 18, 19, 20 },
  { -2, -3, 6, 10, 14, 17, 18, 19, 20 } }
local FALL = { [0] = { 4, 4, 4, 4, 0, 0, 0, 0, 0 }, { 18, 18, 17, 16, 13, 10, 6, 0, 0 },
  { 20, 20, 19, 18, 17, 15, 11, 6, 0 }, { 20, 20, 19, 18, 17, 15, 11, 6, 0 },
  { 20, 20, 19, 18, 17, 15, 11, 6, 0 } }
local TEMPER = { { 10, 50 }, { 20, 50 }, { 30, 60 }, { 20, 70 }, { 30, 70 }, { 40, 80 } }
local SE = { jump = 0x60A, dig = 0x8AA, land = 0x8A8, good1 = 0x8A6, good2 = 0x8A7, good4 = 0x8A9,
  crash = 0x8A5, finish = 0x8AB, rivalFinish = 0x8A1 }
-- performance stats (HgssPokeathlonPerformance): 0 POWER 1 STAMINA 2 SKILL 3 JUMP 4 SPEED
local SKILL, JUMP, SPEED = 2, 3, 4

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end

function M.available(game)
  local d = game and game.data and game.data.gen4_hgss_hurdle_dash
  return type(d) == "table" and d.params ~= nil and d.layouts ~= nil and d.lane_1 ~= nil
end

local function starsOf(game, mon)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local s = mon and P.stars(game.data, mon, mon.aprijuice)
  return s or { [0] = 2, 2, 2, 2, 2 }
end

-- opts: team (three Pokemon), onDone(result)
function M.new(game, opts)
  local self = setmetatable({ game = game, onDone = opts.onDone, t = 0, frame = 0, images = {} }, M)
  local d = game.data.gen4_hgss_hurdle_dash
  self.d = d
  local p = d.params
  local layout = d.layouts[rand(3)] or d.layouts[0]
  self.runners = {}
  for lane = 1, 3 do
    local mon = opts.team[lane]
    local st = starsOf(game, mon)
    self.runners[lane] = {
      mon = mon, lane = lane, dist = 0, speed = 0, combo = 0, state = "run", trip = 0,
      max = p[15 + st[SPEED]] / 10, accel = p[10 + st[SKILL]] / 100,
      jumpStars = st[JUMP], rise = p[st[JUMP]], hang = p[5 + st[JUMP]],
      height = 0, jt = 0, hurdles = {}, nextHurdle = 1, cells = layout[lane - 1] or {},
      broken = 0, jumps = 0,
    }
  end
  -- the rivals: three teams of three runners at their species' base stars
  -- (made-up stars only when the course gave no teams)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  self.rivals = {}
  for team = 1, 3 do
    for k = 1, 3 do
      local mon = opts.rivals and opts.rivals[team] and opts.rivals[team][k]
      local row = mon and P.row(game.data, mon)
      local sp, sk = row and row.base[SPEED] or (1 + rand(3)), row and row.base[SKILL] or (1 + rand(3))
      local tm = TEMPER[rand(6) + 1]
      self.rivals[#self.rivals + 1] = { team = team, dist = 0, speed = 0, combo = 0, trip = 0,
        max = p[15 + sp] / 10, accel = p[10 + sk] / 100, good = tm[1], tripCut = tm[2],
        cells = layout[(k - 1) % 3] or {}, nextHurdle = 1 }
    end
  end
  self.countdown = 180
  -- the shared 3-2-1 / FINISH sprite at y offset 0x110 (ov96_021F94A8)
  if CD.available(game) then self.cd = CD.new(game, 0x110) end
  return self
end

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id) end
end

-- ------------------------------------------------------------------ rules --

function M:jump(r)
  if r.state ~= "run" or r.dist >= FINISH then return end
  r.state, r.jt, r.phase = "jump", 0, 1
  r.jumps = r.jumps + 1
  se(self, r.jumpStars > 0 and SE.jump or SE.dig)
  -- 021FAB04: a hurdle whose bottom is just above the feet -> a good jump
  for _, h in ipairs(r.hurdles) do
    if h.up then
      local gap = FOOT - h.y
      if gap >= 0 and gap < 24 then return self:goodJump(r) end
    end
  end
end

function M:goodJump(r)
  if r.combo >= 4 then return end
  r.goods = (r.goods or 0) + 1
  r.combo = r.combo + 1
  se(self, r.combo == 1 and SE.good1 or (r.combo == 4 and SE.good4 or SE.good2))
  r.speed = r.max + 1.0
end

function M:stepRunner(r)
  if r.dist >= RUNOUT then return end
  if r.state == "trip" then
    r.trip = r.trip - 1
    if r.trip <= 0 then r.state = "run" end
  elseif r.combo == 0 and r.speed < r.max then
    r.speed = math.min(r.max, r.speed + r.accel)
  end
  local before = r.dist
  r.dist = r.dist + r.speed
  local step = r.dist - before
  -- the jump (phase 1 rise, 2 hang, 3 fall)
  if r.state == "jump" then
    r.jt = r.jt + 1
    local row = r.jumpStars
    if r.phase == 1 then
      r.height = (RISE[row] or RISE[1])[math.min(r.jt, 9)] or 0
      if r.jt >= r.rise then r.phase, r.jt = 2, 0 end
    elseif r.phase == 2 then
      if r.jt >= r.hang then r.phase, r.jt = 3, 0 end
    else
      r.height = (FALL[row] or FALL[1])[math.min(r.jt, 9)] or 0
      if r.jt >= r.rise then
        r.state, r.height = "run", 0
        se(self, SE.land)
      end
    end
  end
  -- hurdles: put on the track when the runner's cell reaches them, then down
  local cell = math.floor(r.dist / 8) - 1
  while r.cells[r.nextHurdle] and cell >= r.cells[r.nextHurdle] do
    r.hurdles[#r.hurdles + 1] = { y = -8 + (r.dist % 8), up = true }
    r.nextHurdle = r.nextHurdle + 1
  end
  for i = #r.hurdles, 1, -1 do
    local h = r.hurdles[i]
    h.y = h.y + step
    if h.y >= 520 then table.remove(r.hurdles, i)
    elseif h.up and r.state ~= "jump" and h.y >= FOOT - 8 and h.y <= FOOT + 8 then
      -- knocked over: the runner trips
      h.up, h.knock = false, 0
      se(self, SE.crash)
      r.broken = r.broken + 1
      r.combo, r.speed, r.state, r.trip = 0, 0.5, "trip", 30
    elseif not h.up then
      h.knock = (h.knock or 0) + 1
    end
  end
  if not r.finish and r.dist >= FINISH then
    r.finish = self.frame
    se(self, SE.finish)
  end
end

function M:stepRival(r)
  if r.finish then return end
  if r.trip > 0 then
    r.trip = r.trip - 1
  elseif r.combo == 0 and r.speed < r.max then
    r.speed = math.min(r.max, r.speed + r.accel)
  end
  r.dist = r.dist + r.speed
  local cell = math.floor(r.dist / 8)
  while r.cells[r.nextHurdle] and cell >= r.cells[r.nextHurdle] do
    r.nextHurdle = r.nextHurdle + 1
    local roll = rand(100)
    if roll < r.good then
      r.goods = (r.goods or 0) + 1
      if r.combo < 4 then r.combo = r.combo + 1 end
      r.speed = r.max + 1.0
    elseif roll < r.tripCut then
      r.trips = (r.trips or 0) + 1
      r.trip, r.combo, r.speed = 30, 0, 0.5
    end
  end
  if r.dist >= FINISH then r.finish = self.frame end
end

-- ------------------------------------------------------------------ input --

function M:lanePressed(lane)
  local r = self.runners[lane]
  if r then self:jump(r) end
end

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
  if py > 88 and py < 168 then
    for lane, lx in ipairs(LANES) do
      if math.abs(px - lx) < 24 then self:lanePressed(lane) end
    end
  end
  return true
end
function M:touchmoved() return true end
function M:touchreleased() return true end

function M:update()
  self.t = self.t + 1
  local input = self.game.input
  if self.countdown > 0 then
    if self.cd then
      -- the shared 3-2-1 (021E637C), one logic tick every other frame
      self.half = not self.half
      if not self.half and self.cd:countdown() then self.countdown = 0 end
      return
    end
    self.countdown = self.countdown - 1
    return
  end
  if input then
    if input:wasPressed("left") then self:lanePressed(1) end
    if input:wasPressed("up") or input:wasPressed("down") then self:lanePressed(2) end
    if input:wasPressed("right") then self:lanePressed(3) end
  end
  if self.over and not self.cd then
    self.over = self.over - 1
    if self.over <= 0 then return self:finish() end
    return
  end
  -- the events run their logic at 30 ticks a second (every other frame)
  self.half = not self.half
  if self.half then return end
  -- the FINISH (021E667C) while the runners run on (021F9240 state 2)
  if self.over and not self.cd:finishing() then return self:finish() end
  self.frame = self.frame + 1
  local done = true
  for _, r in ipairs(self.runners) do
    self:stepRunner(r)
    if not r.finish then done = false end
  end
  for _, r in ipairs(self.rivals) do self:stepRival(r) end
  if done and not self.over then
    self.over = 90
    if self.cd then
      self.endFrame = self.frame
      -- 021F9240: the three finish ticks' sum to ov96_021E8318 (u16)
      local sum = 0
      for _, r in ipairs(self.runners) do sum = sum + r.finish end
      self.cd:startFinish(Rec.isNew(self.game, 0, sum % 65536))
    end
  end
end

function M:finish()
  -- the rivals still running finish at their current pace
  for _, r in ipairs(self.rivals) do
    while not r.finish do self.frame = self.frame + 1; self:stepRival(r) end
  end
  local times = { 0, 0, 0, 0 }
  for _, r in ipairs(self.runners) do times[1] = times[1] + r.finish end
  for _, r in ipairs(self.rivals) do times[r.team + 1] = times[r.team + 1] + r.finish end
  local points, broken = {}, 0
  for i = 1, 4 do
    local seconds = times[i] / 30
    points[i] = math.floor(11500 / math.max(1, seconds))
  end
  -- per Pokemon (the course's bonuses): a broken hurdle is a miss and a fail;
  -- jumps, and the good jumps as dashes
  local stats = { {}, {}, {}, {} }
  for lane, r in ipairs(self.runners) do
    broken = broken + r.broken
    stats[1][lane] = { miss = r.broken > 0, jump = r.jumps, dash = r.goods or 0, fail = r.broken }
  end
  local k = { 0, 0, 0 }
  for _, r in ipairs(self.rivals) do
    k[r.team] = k[r.team] + 1
    stats[r.team + 1][k[r.team]] = { miss = (r.trips or 0) > 0, jump = (r.goods or 0) + (r.trips or 0),
      dash = r.goods or 0, fail = r.trips or 0 }
  end
  self.game.stack:pop()
  if self.onDone then
    -- 021F9380 / 021FBDEC: field5E0 = the time cut to tenths (the saved record)
    local t1 = times[1]
    local record = (30 * math.floor(t1 / 30) + 3 * math.floor((t1 % 30) / 3)) % 65536
    self.onDone({ points = points, seconds = times[1] / 30, broken = broken, stats = stats, record = record })
  end
end

-- ------------------------------------------------------------------- draw --

function M:img(key)
  local rec = self.d[key]
  local path = type(rec) == "table" and rec.path or rec
  if not path then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.images[path] = ok and img or false
    if self.images[path] then self.images[path]:setFilter("nearest", "nearest") end
  end
  return self.images[path] or nil, rec
end

function M:sprite(key, x, y, scale)
  local img, rec = self:img(key)
  if not img then return end
  scale = scale or 1
  local ox = type(rec) == "table" and rec.originX or 0
  local oy = type(rec) == "table" and rec.originY or 0
  love.graphics.draw(img, x + ox * scale, y + oy * scale, 0, scale, scale)
end

function M:monIcon(mon, x, y, frame)
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
  local iw, ih = img:getDimensions()
  fh = fh or math.min(iw, ih)
  local frames = math.max(1, math.floor(ih / fh))
  local q = love.graphics.newQuad(0, ((frame or 0) % frames) * fh, iw, fh, iw, ih)
  love.graphics.draw(img, q, x - iw, y - fh * 2, 0, 2, 2)
end

-- the whole track in sprite space, y from `top`, as one screen
function M:drawSpace(top)
  local g = love.graphics
  g.setColor(0.2, 0.55, 0.3, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  for lane, lx in ipairs(LANES) do
    local r = self.runners[lane]
    local strip = self:img("lane_" .. lane)
    if strip then
      local sy = (r.dist % 512) - 512 - top - VIEW_SHIFT
      -- each strip carries its own lane where it stands; only VOFS scrolls
      for k = 0, 2 do g.draw(strip, 0, sy + 512 * k) end
    end
  end
  for lane, lx in ipairs(LANES) do
    local r = self.runners[lane]
    for _, h in ipairs(r.hurdles) do
      local key = h.up and "hurdle_0_0" or ("knock_0_" .. math.min(2, math.floor((h.knock or 0) / 4)))
      self:sprite(key, lx, h.y - top - VIEW_SHIFT)
    end
    local fy = FOOT - top - VIEW_SHIFT
    if fy > -64 and fy < H + 64 then
      self:sprite("obj_12_0", lx, fy)
      if r.combo > 0 then self:sprite(r.combo >= 4 and "boost_2_0" or "boost_1_0", lx, fy - 16) end
      if r.mon then self:monIcon(r.mon, lx, fy - r.height, math.floor(self.t / 8)) end
    end
  end
end

function M:drawTop()
  self:drawSpace(0)
  local Font = require("src.render.Font")
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, W, 16)
  love.graphics.setColor(1, 1, 1, 1)
  local fr = self.endFrame or self.frame
  Font.draw(("%d.%02d"):format(math.floor(fr / 30), math.floor((fr % 30) * 100 / 30)), 8, 1)
  if self.countdown > 0 and not self.cd then
    Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 88)
  end
end

function M:drawBottom()
  self:drawSpace(192)
  -- the shared 3-2-1 / FINISH: the touch screen's surface starts at 0x110
  if self.cd then self.cd:draw(0x110) end
end

function M:draw()
  if SecondScreen.separate(self.game) then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawBottom() end)
  else
    self:drawBottom()
    if self.countdown > 0 and not self.cd then
      local Font = require("src.render.Font")
      Font.draw(tostring(math.ceil(self.countdown / 60)), 124, 40)
    end
  end
end

return M
