-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SNOW, SNOWSTORM AND BLIZZARD, the way the weather task draws them.
--
-- Reported from play: "the snow animation/weather isnt properly rendering like
-- it should in the rom for platinum".  It was Hoenn's snow (Gen3Weather's SNOW
-- look) wearing Sinnoh's weather id.  This is pokeplatinum
-- src/overlay005/ov5_021D5EB8.c, weathers 5 (ov5_021D79F0), 6 (ov5_021D7E54)
-- and 7 (ov5_021D8FF8), transcribed in scratch notes as a spec and here as code:
--
--   * a 48-slot pool of 8x8 OBJ flakes over the 3D, positions in whole screen
--     pixels on the 256x192 screen, wrapped at x 319 / y 256 with a -64
--     margin (ov5_021D630C)
--   * a spawner that ramps count and interval during the fades
--     (ov5_021D7244, the period equal to the interval) and spawns every
--     interval + 1 ticks once steady
--   * per weather: the spawn ranges, the RNG draws in order, the update rules
--   * flakes of 5 and 6 shifted against the camera's movement (ov5_021D7028,
--     about 1.01 px a world unit); the blizzard's are not
--   * the blizzard's BG2 layer, a 128x128 snow texture scrolling 24 px left and
--     12 px down a tick, shown from the end of the fade-in to the start of the
--     fade-out
-- At the field's 30 ticks a second.  The fog the three also fade in (slope
-- 0x1000, colours 26/24/24) is NOT drawn: this port's Gen 4 fog is baked into
-- vertex colours and has no depth table to ramp.

local Assets = require("src.render.Assets")

local V = {}

V.SNOWING, V.HEAVY_SNOW, V.BLIZZARD = 5, 6, 7
V.POOL = 48
V.WRAP_X, V.WRAP_Y, V.MARGIN = 319, 256, -64
-- ov5_021D7028 with the default field camera: world units to pixels
V.CAM_X, V.CAM_Y = 1.0125, 1.0048
-- blizzard wind phases (Unk_ov5_021F8CDC / Unk_ov5_021F8CEC)
V.WIND_X = { [0] = -4, -6, -8, -10 }
V.WIND_Y = { [0] = 2, 4, 2, 4 }

local function rng(n) return love.math.random(0, n - 1) end
V.rng = rng

local function Game() return package.loaded["src.core.Game"] end

-- the per-weather constants: init ramp (count, interval, targetCount,
-- targetInterval, intervalDelta, countPeriod, countDelta), the steady values,
-- the fade-out ramp (targetCount, targetInterval, intervalDelta, countDelta),
-- the fade delays, the fog's length in ticks (the fades wait on it), and the
-- pre-warm (P, Q)
V.WEATHER = {
  [5] = { ramp = { 1, 24, 1, 14, -5, 1, 0 }, steady = { 1, 14, 1, 14, -5, 1, 0 }, out = { 0, 24, 5, -1 },
          inDelay = 16, inFog = 127, outDelay = 32, outFog = 254, warm = { 2, 24 }, flakes = "snowFlakes" },
  [6] = { ramp = { 1, 30, 6, 3, -5, 2, 1 }, steady = { 6, 3, 6, 3, -5, 2, 1 }, out = { 0, 30, 5, -3 },
          inDelay = 8, inFog = 254, outDelay = 0, outFog = 127, warm = { 2, 3 }, flakes = "heavyFlakes" },
  [7] = { ramp = { 1, 30, 10, 1, -4, 2, 3 }, steady = { 10, 1, 10, 1, -4, 2, 3 }, out = { 0, 12, 4, -4 },
          inDelay = 16, inFog = 127, outDelay = 20, outFog = 127, warm = { 2, 2 }, flakes = "snowFlakes", layer = true },
}

-- ------------------------------------------------------------------ pool

local function wrap(p)
  if p.x > V.WRAP_X then
    p.x = p.x % V.WRAP_X
  elseif p.x < V.MARGIN then
    p.x = p.x + V.WRAP_X
  end
  if p.y > V.WRAP_Y then
    p.y = p.y % V.WRAP_Y
  elseif p.y < V.MARGIN then
    p.y = p.y + V.WRAP_Y
  end
end

local function alloc(st)
  if #st.list >= V.POOL then return nil end
  local p = { x = 0, y = 0 }
  st.list[#st.list + 1] = p
  return p
end

-- ------------------------------------------------------------- the spawner

local function rampInit(st, r)
  st.sp = { count = r[1], interval = r[2], targetCount = r[3], targetInterval = r[4],
            intervalDelta = r[5], countPeriod = r[6], countDelta = r[7], timer = 0, sub = 0 }
end

local function rampTarget(st, o)
  local s = st.sp
  s.targetCount, s.targetInterval, s.intervalDelta, s.countDelta = o[1], o[2], o[3], o[4]
end

-- ov5_021D7244: the fade states' spawner; 3 when both ramps are done
local function rampStep(st, spawn)
  local s = st.sp
  local flags = 0
  if s.intervalDelta == 0 then
    flags = flags + 1
  elseif (s.intervalDelta > 0 and s.interval >= s.targetInterval)
      or (s.intervalDelta < 0 and s.interval <= s.targetInterval) then
    flags = flags + 1
    s.interval = s.targetInterval
  end
  if s.countDelta == 0 then
    flags = flags + 2
  elseif (s.countDelta > 0 and s.count >= s.targetCount)
      or (s.countDelta < 0 and s.count <= s.targetCount) then
    flags = flags + 2
    s.count = s.targetCount
  end
  s.timer = s.timer - 1
  if s.timer <= 0 then
    spawn(st, s.count)
    s.timer = s.interval
    if flags % 2 == 0 then s.interval = s.interval + s.intervalDelta end
    if flags < 2 then
      s.sub = s.sub + 1
      if s.sub >= s.countPeriod then s.sub = 0; s.count = s.count + s.countDelta end
    end
  end
  return flags
end

-- ------------------------------------------------------- SNOWING (5)

-- ov5_021D7C40
local function spawnSnow(st, count)
  if st.b1 == 1 then count = count * 2 end
  for i = 0, count - 1 do
    local p = alloc(st)
    if not p then break end
    p.frame = rng(4)
    p.sway, p.timerX, p.timerY, p.st = 10, 0, 0, 0
    local v1 = love.math.random(0, 0x7FFFFFFF)
    p.linger = 4 + v1 % 60
    p.dir = (v1 % 2 == 0) and 1 or -1
    p.xPer = 4 + rng(2)
    p.yPer = 1 + rng(2)
    p.x = -32 + rng(414)
    if st.b1 == 1 and i >= count / 2 then
      p.y = -40 - rng(20)
    else
      p.y = -8 - rng(20)
    end
    wrap(p)
  end
end

-- ov5_021D7E20 -> ov5_021D7D54; false when the flake goes
local function updateSnow(st, p)
  if p.st == 0 then
    if st.b2 == 1 then p.st = 1 end
  else
    p.linger = p.linger - 1
    if p.linger < 0 then return false end
  end
  if p.timerX >= p.xPer then
    p.x = p.x + p.dir
    p.sway = p.sway + 1
    p.timerX = 0
    if p.sway < 10 then p.xPer = p.xPer - 1 else p.xPer = p.xPer + 1 end
    if p.sway >= 20 then p.sway = 0; p.dir = -p.dir end
  end
  if p.timerY >= p.yPer then
    p.y = p.y + 1
    p.timerY = 0
  end
  wrap(p)
  p.timerX, p.timerY = p.timerX + 1, p.timerY + 1
  local yi = math.floor(p.y)
  if yi > 212 and yi < 232 then
    st.b1 = 1
    return false
  end
  return true
end

-- --------------------------------------------------- HEAVY_SNOW (6)

local DECAY = { [0] = 16, 32, 16, 10 }

-- ov5_021D8098
local function spawnHeavy(st, count)
  for _ = 1, count do
    local p = alloc(st)
    if not p then break end
    st.b1 = st.b1 + 1
    if st.b1 >= 800 then st.b1 = 0 end
    local phase = math.floor(st.b1 / 200)
    p.decay = DECAY[phase]
    p.age, p.st = 0, 0
    p.life = 4 + rng(42)
    local size = math.floor((p.life - 4) / 15)
    p.frame = size
    p.vx = -(size + 1)
    p.vy = 2 * (size + 1)
    p.x = -20 + size * 20 + rng(420)
    p.y = -8
    wrap(p)
  end
end

-- ov5_021D81BC
local function updateHeavy(st, p)
  if p.st == 1 then return false end
  p.x, p.y = p.x + p.vx, p.y + p.vy
  local old = p.age
  p.age = p.age + 1
  if old > p.life then p.st = 1 end
  if p.age % p.decay == 0 then
    p.vx = p.vx - 1
    if p.vy > 1 then p.vy = p.vy - 1 end
  end
  wrap(p)
  return true
end

-- ----------------------------------------------------- BLIZZARD (7)

-- ov5_021D92C4: four flakes per count, from just off the right edge
local function spawnBlizzard(st, count)
  st.b1 = st.b1 + 1
  if st.b1 >= 2048 then st.b1 = 0 end
  local phase = math.floor(st.b1 / 512)
  for _ = 1, count * 4 do
    local p = alloc(st)
    if not p then break end
    p.age, p.st = 0, 0
    p.life = 18 + rng(6)
    p.frame = rng(4)
    local m = p.frame + 1
    p.vx = V.WIND_X[phase] * m
    p.vy = V.WIND_Y[phase] * m
    if p.frame == 3 then p.vx, p.vy = p.vx + V.WIND_X[phase], p.vy + V.WIND_Y[phase] end
    p.ax = V.WIND_X[phase]
    p.x = 256 + rng(24)
    p.y = -32 + rng(168)
    wrap(p)
  end
end

-- ov5_021D93DC
local function updateBlizzard(st, p)
  if p.st == 1 then return false end
  p.x, p.y = p.x + p.vx, p.y + p.vy
  local old = p.age
  p.age = p.age + 1
  if old > p.life then p.st = 1 end
  if p.age % 4 == 0 then
    p.vx = p.vx + p.ax
    if p.vy > 1 then p.vy = p.vy - 1 end
  end
  wrap(p)
  return true
end

local SPAWN = { [5] = spawnSnow, [6] = spawnHeavy, [7] = spawnBlizzard }
local UPDATE = { [5] = updateSnow, [6] = updateHeavy, [7] = updateBlizzard }

-- ov5_021D6FF0: head to tail, a flake may remove itself
local function updateAll(st)
  local upd = UPDATE[st.id]
  local keep = {}
  for _, p in ipairs(st.list) do
    if upd(st, p) then keep[#keep + 1] = p end
  end
  st.list = keep
end

-- ov5_021D7568: spawn, then give the i-th flake Q * floor((i-1)/P) updates
local function prewarm(st)
  local w = V.WEATHER[st.id]
  SPAWN[st.id](st, 20)
  local P, Q = w.warm[1], w.warm[2]
  local upd = UPDATE[st.id]
  local n = 0
  local out = {}
  for i, p in ipairs(st.list) do
    local alive = true
    for _ = 1, n do
      if not upd(st, p) then alive = false; break end
    end
    if alive then out[#out + 1] = p end
    local idx = i - 1
    if idx >= P and idx % P == 0 then n = n + Q end
    if idx >= 19 then
      for j = i + 1, #st.list do out[#out + 1] = st.list[j] end
      break
    end
  end
  st.list = out
end

-- ------------------------------------------------------------- the task

V.state = nil

-- cmd 2 (a weather that starts while you watch) or cmd 3 (`instant`: on map
-- load, already in full swing)
function V.start(id, instant)
  if not V.WEATHER[id] then V.state = nil; return end
  V.state = { id = id, state = instant and 2 or 0, list = {}, b0 = 0, b1 = 0, b2 = 0, bg = 0, layer = false }
  return V.state
end

-- cmd 5: fade out
function V.stop()
  if V.state and V.state.state <= 3 then V.state.stopping = true end
end

function V.id() return V.state and V.state.id end

-- one weather tick (a field frame)
function V.tick(camDx, camDy)
  local st = V.state
  if not st then return end
  local w = V.WEATHER[st.id]
  local spawn = SPAWN[st.id]
  if st.state == 0 then
    rampInit(st, w.ramp)
    st.b0, st.b1, st.b2 = w.inDelay, 0, 0
    st.fog = w.inFog
    st.state = 1
    return
  elseif st.state == 1 then
    local v = rampStep(st, spawn)
    local fogDone = false
    if st.b0 > 0 then st.b0 = st.b0 - 1
    else st.fog = st.fog - 1; fogDone = st.fog <= 0 end
    if fogDone and v == 3 then
      st.state = 3
      if w.layer then st.layer = true end
    end
  elseif st.state == 2 then
    rampInit(st, w.steady)
    st.b1, st.b2, st.bg = 0, 0, 0
    prewarm(st)
    if w.layer then st.layer = true end
    st.state = 3
  elseif st.state == 3 then
    local s = st.sp
    local due = s.timer <= 0
    s.timer = s.timer - 1
    if due then
      local count = s.count
      -- the blizzard doubles in its two strongest winds (l.3427)
      if st.id == 7 and V.WIND_X[math.floor(st.b1 / 512)] <= -8 then count = count * 2 end
      spawn(st, count)
      s.timer = s.interval
    end
    if st.stopping then
      rampTarget(st, w.out)
      st.b0 = w.outDelay
      st.fog = w.outFog
      st.layer = false
      st.state = 4
    end
  elseif st.state == 4 then
    local v = rampStep(st, spawn)
    local fogDone = false
    if st.b0 > 0 then st.b0 = st.b0 - 1
    else st.fog = st.fog - 1; fogDone = st.fog <= 0 end
    if fogDone and v == 3 then
      if st.id == 5 then st.b2 = 1 end
      if #st.list == 0 then st.state = 5 end
    end
  elseif st.state == 5 then
    -- fog off, the task stopped, every flake gone
    V.state = nil
    return
  end
  updateAll(st)
  -- ov5_021D717C: weathers 5 and 6 slide against the camera
  if st.id ~= 7 and (camDx ~= 0 or camDy ~= 0) then
    local dx, dy = (camDx or 0) * V.CAM_X, (camDy or 0) * V.CAM_Y
    for _, p in ipairs(st.list) do
      p.x, p.y = p.x - dx, p.y - dy
      wrap(p)
    end
  end
  if st.id == 7 then st.bg = (st.bg + 12) % 256 end
end

-- -------------------------------------------------------------- drawing

local images = {}
local function image(entry)
  if not (entry and entry.path) then return nil end
  if images[entry.path] == nil then
    local ok, img = pcall(Assets.image, entry.path)
    images[entry.path] = (ok and img) or false
    if ok and img then
      img:setFilter("nearest", "nearest")
      img:setWrap("repeat", "repeat")
    end
  end
  return images[entry.path] or nil
end

local quads = {}
local function quad(img, k)
  local key = tostring(img) .. k
  if not quads[key] then quads[key] = love.graphics.newQuad(k * 8, 0, 8, 8, img:getDimensions()) end
  return quads[key]
end

-- the 256x192 screen, scaled to the view's height and centred across its width
function V.draw(w, h)
  local st = V.state
  local G = Game()
  local rec = G and G.data and G.data.gen4_weather_sys
  if not (st and rec) then return false end
  local cfg = V.WEATHER[st.id]
  local g = love.graphics
  local s = h / 192
  local left = (w - 256 * s) / 2
  g.push("all")
  g.setColor(1, 1, 1, 1)
  -- BG2 over the 3D, under the flakes; BG2HOFS = 2n, BG2VOFS = -n
  if st.layer then
    local img = image(rec.blizzardLayer)
    if img then
      local n = st.bg
      local q = g.newQuad(2 * n - left / s, -n, w / s, h / s, 256, 256)
      g.draw(img, q, 0, 0, 0, s, s)
    end
  end
  local sheet = image(rec[cfg.flakes])
  if sheet then
    -- anim 26 (sets 3/9) shows tile 3 - f; anim 18 (set 1) shows tile f
    local reversed = cfg.flakes == "snowFlakes"
    for _, p in ipairs(st.list) do
      local tile = reversed and (3 - p.frame) or p.frame
      g.draw(sheet, quad(sheet, tile), left + math.floor(p.x) * s, math.floor(p.y) * s, 0, s, s)
    end
  end
  g.pop()
  return true
end

return V
