-- HEARTGOLD / SOULSILVER'S INTO-BATTLE TRANSITIONS, after pokeheartgold
-- (unk_020517A4.s, overlay_01_021EFB38.s, overlay_120.s / overlay_119.s).
--
-- The frame of them is Platinum's (src/render/Gen4BattleTransition.lua: the
-- 30 Hz coroutine scripts, the flash, the black rectangles over the field);
-- what differs is WHICH plays and the wild ones themselves:
--
--   * the choice (BattleSetup_GetTransitionAndMusicParam): a param from the
--     trainer's class or the wild lead's species, then a table to an effect
--     id 0..46; the ordinary ones (0xFFFF) go to the generic chooser, which
--     is the TERRAIN (plain / water / cave) and the TIME OF DAY -- HGSS's
--     "night" (NITE or LATE) took the place of Platinum's "stronger
--     opponent", and no level is compared at all;
--   * the wild land and cave effects (0/1, 4/5): two flashes, white by day
--     and black by night, then 48 black 32 px cells close over the field,
--     one pair a tick -- vertical bars opening sideways along two snakes
--     from opposite corners (land), squares growing on a diagonal sweep
--     (cave) -- and both screens left black.
--
-- An effect not written here yet plays Platinum's nearest (the same terrain
-- and side, day as the weaker, night as the stronger), never a Sinnoh gym
-- leader's banner picked by a Johto class number.

local H = {}

local floor = math.floor

-- BattleSetup_GetTransitionAndMusicParam's class table (_020FC3CA), with
-- pokeheartgold's TRAINERCLASS_* numbers
local CLASS_PARAM = {
  [66] = 0, [67] = 1, [70] = 2, [72] = 3, [74] = 4, [75] = 5, [73] = 6, [76] = 7,
  [98] = 8, [103] = 9, [104] = 10, [105] = 11, [106] = 12, [107] = 13, [108] = 14, [110] = 15,
  [87] = 16, [89] = 17, [112] = 18, [88] = 19, [86] = 20,
  [23] = 21, [119] = 21,
  [55] = 29, [62] = 29, [118] = 30, [117] = 31, [116] = 32, [114] = 33, [124] = 34,
  [47] = 43, [109] = 44,
}
H.CLASS_PARAM = CLASS_PARAM

-- the wild species table (_020FC3B4), national dex
local SPECIES_PARAM = {
  [243] = 22, [244] = 23, [245] = 24, [250] = 25, [249] = 26,
  [382] = 27, [383] = 27, [384] = 27, [150] = 28, [380] = 28, [381] = 28,
}

local PAL_PARK = 109
local GENERIC = -1

-- param -> effect id (_020FC40A); GENERIC is 0xFFFF
local PARAM_EFFECT = {}
for p = 0, 15 do PARAM_EFFECT[p] = 12 + p end
for p = 16, 20 do PARAM_EFFECT[p] = 13 + p end
PARAM_EFFECT[21] = 28
PARAM_EFFECT[22], PARAM_EFFECT[23], PARAM_EFFECT[24] = GENERIC, GENERIC, GENERIC
PARAM_EFFECT[25], PARAM_EFFECT[26], PARAM_EFFECT[27], PARAM_EFFECT[28] = 35, 36, 34, 34
for p = 29, 34 do PARAM_EFFECT[p] = 10 + p end
PARAM_EFFECT[35], PARAM_EFFECT[36], PARAM_EFFECT[37], PARAM_EFFECT[38] = 37, 37, 38, 38
PARAM_EFFECT[39], PARAM_EFFECT[40] = 37, 38
PARAM_EFFECT[41], PARAM_EFFECT[42] = GENERIC, GENERIC
PARAM_EFFECT[43], PARAM_EFFECT[44] = 45, 46

local KEEP_IN_DOUBLES = { [29] = true, [30] = true, [31] = true, [32] = true, [33] = true,
                          [34] = true, [43] = true, [44] = true }

function H.active()
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  return okB and Bands.family == "hgss"
end

-- GF_RTC_GetTimeOfDayByHour: NITE 20-23, LATE 0-3
function H.isNight(ctx)
  local hour = tonumber(ctx and ctx.hour) or tonumber(os.date("%H")) or 12
  return hour >= 20 or hour < 4
end

function H.param(ctx)
  if ctx.trainer then
    local p = CLASS_PARAM[tonumber(ctx.trainerClass) or -1] or 41
    if ctx.frontier then return ctx.double and 37 or 35 end
    if KEEP_IN_DOUBLES[p] then return p end
    if ctx.double then return 37 end
    if ctx.link then return 36 end
    return p
  end
  local p = 42
  if tonumber(ctx.zone) ~= PAL_PARK then p = SPECIES_PARAM[tonumber(ctx.species) or -1] or 42 end
  if p >= 42 and ctx.double then p = 38 end
  return p
end

-- ov01_021F0D20: the generic 0..11
function H.generic(ctx)
  local base = 0
  if ctx.terrain == "cave" then base = 4 elseif ctx.terrain == "water" then base = 2 end
  if H.isNight(ctx) then base = base + 1 end
  return (ctx.trainer and 6 or 0) + base
end

-- choose(ctx) -> effect id 0..46
function H.choose(ctx)
  ctx = ctx or {}
  local e = PARAM_EFFECT[H.param(ctx)]
  if e == nil or e == GENERIC then e = H.generic(ctx) end
  return e
end

-- Platinum's nearest, for the ones not written yet
local PLATINUM = {
  [34] = "mythical",   -- ov116_0225F3AC's perspective keyframes are Platinum's MYTHICAL_SNAPS
  [2] = "water_low", [3] = "water_high",
  [6] = "trainer_grass_low", [7] = "trainer_grass_high",
  [8] = "trainer_water_low", [9] = "trainer_water_high",
  [10] = "trainer_cave_low", [11] = "trainer_cave_high",
  [37] = "frontier", [38] = "double",
}
function H.fallback(id, ctx)
  if PLATINUM[id] then return PLATINUM[id] end
  local g = H.generic(ctx or {})
  local names = { [0] = "grass_low", "grass_high", "water_low", "water_high", "cave_low", "cave_high",
                  "trainer_grass_low", "trainer_grass_high", "trainer_water_low",
                  "trainer_water_high", "trainer_cave_low", "trainer_cave_high" }
  return names[g]
end

-- ---------------------------------------------------------------------------
-- The effects. `K` is Gen4BattleTransition's kit: tick, wait, waitFor,
-- spawn, flash, blackout, Lin.
-- ---------------------------------------------------------------------------

-- 0/1's pair order (ov120_0226032C day, ov120_022602FC night): pair k opens
-- cell T[k] and its point mirror 47 - T[k]
local function landOrder(night)
  local T = {}
  for k = 0, 23 do
    local c
    if k < 8 then c = night and 7 - k or k
    elseif k < 16 then c = night and k or 23 - k
    else c = night and 39 - k or k end
    T[k] = c
  end
  return T
end

-- 4's start tick per cell (ov120_02260314 / 022602E4), rows top first; 5 is
-- the same with every cell c read as 47 - c
local CAVE_DAY = {
   0,  0,  1,  2,  4,  6,  9, 12,
   1,  2,  3,  5,  7, 10, 13, 15,
   3,  4,  6,  8, 11, 14, 16, 18,
   5,  7,  9, 12, 15, 17, 19, 20,
   8, 10, 13, 16, 18, 20, 21, 22,
  11, 14, 17, 19, 21, 22, 23, 23,
}
H.CAVE_DAY = CAVE_DAY

-- the cells that start on each tick: starts[t] = { cells }
local function landStarts(night)
  local T, starts = landOrder(night), {}
  for k = 0, 23 do starts[k] = { T[k], 47 - T[k] } end
  return starts
end

local function caveStarts(night)
  local starts = {}
  for c = 0, 47 do
    local t = CAVE_DAY[c + 1]
    local cell = night and 47 - c or c
    starts[t] = starts[t] or {}
    table.insert(starts[t], cell)
  end
  return starts
end
H.landStarts, H.caveStarts = landStarts, caveStarts

-- ov120_0225F318 / 0225F4DC: each started cell's rect grows 0 -> 32 over 4
-- steps (LinearS32, one update a tick, the first on the tick it starts) and
-- is drawn without erasing; done when the last has had its 5th update
local function closeCells(S, K, starts, square)
  local live, t, last = {}, 0, 0
  for k in pairs(starts) do if k > last then last = k end end
  while true do
    for _, c in ipairs(starts[t] or {}) do
      local rect = {}
      S.rects[#S.rects + 1] = rect
      live[#live + 1] = { lin = K.Lin(0, 32, 4), rect = rect,
                          cx = (c % 8) * 32 + 16, cy = floor(c / 8) * 32 + 16 }
    end
    local any = false
    for _, cell in ipairs(live) do
      if not cell.done then
        local v, d = cell.lin()
        local r = cell.rect
        r.w = v
        r.h = square and v or 32
        r.x = cell.cx - floor(v / 2)
        r.y = cell.cy - floor(r.h / 2)
        cell.done = d
        any = any or not d
      end
    end
    if t >= last and not any then return end
    t = t + 1
    K.tick()
  end
end

local function wild(cellsFor, square)
  return function(night)
    return function(S, K)
      K.tick()                                       -- state 0: the window
      local f = K.flash(S, night and -16 or 16, night and -16 or 16, 2)
      K.waitFor(function() return f.done end)
      K.tick()                                       -- state 3: the controller
      closeCells(S, K, cellsFor(night), square)
      K.tick()
      K.blackout(S)                                  -- sub_0200FC20(0)
    end
  end
end

local land, cave = wild(landStarts, false), wild(caveStarts, true)

local PAL0, PAL1, PAL_WATER = "hgss/0", "hgss/1", "hgss/160"
local FX = 4096

-- the camera: D from the field's distance, applied every tick it is updated
local function camera(S, K, delta, v0, n)
  local D = K.Quad(K.D0, K.D0 + delta, v0, n)
  return function()
    local v, d = D()
    S.zoom = K.zoomFor(v)
    return d
  end
end

-- ov01_021F12E8 on BG0: line L shows table[(phase / 100 + L) % 192]; the
-- port's ScreenShake reads `pos` as that table index
local function wave(S, K, angleStep, amp, speed, interlace)
  S.shake = { inc = angleStep, amp = amp, pos = 0, invert = interlace and 2 or nil }
  return K.spawn(S, function(h)
    while not h.dead do K.tick(); S.shake.pos = (S.shake.pos + speed / 100) % 192 end
  end)
end

local function ball(S, K, key, x, y, pri)
  return K.sprite(S, { key = key, cell = 0, x = x, y = y, palette = PAL0,
                       visible = false, pri = pri or 1 })
end

-- 2/3 (ov120_0225FF00): the field wobbles, the bubbles (BG3) rise swaying,
-- the wave (BG1) shoots up after them, black
local function water(night)
  return function(S, K)
    K.tick()                                         -- state 0: the BGs
    K.tick(); K.tick()                               -- state 1: the loader
    local bg3 = { key = "hgss_water_bg3", palette = PAL_WATER, vofs = 0, hofs = 0, visible = false }
    local bg1 = { key = "hgss_water_bg1", palette = PAL_WATER, vofs = 0, hofs = 0, visible = false }
    S.layers = { bg3, bg1 }                          -- BG1 over BG3, both over the field
    local A, B = K.Quad(0, 320, 0, 18), K.Quad(0, 320, 8, 30)
    local c = night and -16 or 16
    local f = K.flash(S, c, c, 2)
    K.waitFor(function() return f.done end)
    K.tick()                                         -- state 3
    wave(S, K, 0xD52, 3, 400, false)
    bg3.visible = true
    local angle = 0
    K.spawn(S, function(h)
      while not h.dead do
        local v = B()
        bg3.vofs, bg3.hofs = v, floor(16 * math.sin(angle / 180 * math.pi))
        angle = (angle + 15) % 360
        K.tick()
      end
    end)
    K.wait(11)                                       -- state 4
    bg1.visible = true                               -- state 5
    local done = false
    repeat local v; v, done = A(); bg1.vofs = v; K.tick() until done
    K.blackout(S)
  end
end

-- 6 (ov119_0225F37C): two balls cross spinning, the screen splits four ways
local function trainerLandDay(S, K)
  K.tick()
  local f = K.flash(S, 16, -16, 2)
  K.waitFor(function() return f.done end)
  local b0, b1 = ball(S, K, "hgss_ball", 128, 0), ball(S, K, "hgss_ball", 128, 0)
  local X, R = K.LinF(-192, 192, 8), K.Lin(0, 0x1FFFE, 8)
  K.tick()                                           -- state 3
  b0.visible, b1.visible = true, true
  local d
  repeat
    local x, r
    x, d = X(); r = R()
    b0.x, b0.y, b0.rot = 128 - x, 64, r
    b1.x, b1.y, b1.rot = 128 + x, 128, -r
    K.tick()
  until d
  S.split = { x = 0, y = 0 }                         -- state 5
  local sx = K.drive(S, K.Quad(0, 255, 1, 8), function(v) S.split.x = v end)
  local sy = K.drive(S, K.Quad(0, 96, 1, 8), function(v) S.split.y = v end)
  local cam = camera(S, K, -500, -10, 8)
  repeat cam(); K.tick() until sx.done and sy.done
  b0.visible, b1.visible = false, false
  K.blackout(S)
end

-- 7 (ov119_0225F020): the ball grows from a dot spinning, opens, and the
-- screen slashes in two after its halves
local function trainerLandNight(S, K)
  K.tick()
  local f = K.flash(S, -16, -16, 2)
  K.waitFor(function() return f.done end)
  local b0 = ball(S, K, "hgss_ball_split", 128, 96, 0)
  local b1 = ball(S, K, "hgss_ball_split", 128, 96, 2)
  local Sc, R = K.Quad(0x29 / FX, 1, 2 / FX, 10), K.Lin(0, 0xFFFF, 10)
  K.tick()                                           -- state 3
  b0.visible, b1.visible = true, true
  local d
  repeat
    local s, r
    s, d = Sc(); r = R()
    b0.scale, b1.scale = s, s
    b0.rot, b1.rot = r, r - 0x100
    K.tick()
  until d
  -- state 5: the halves (anim seqs 1 / 2: cells 1 and 2)
  b0.cell, b1.cell, b0.rot, b1.rot, b0.scale, b1.scale = 1, 2, 0, 0, 1, 1
  S.slice = { pps = 96, x = 0 }
  local slice = K.drive(S, K.Quad(0, 255, 10, 6), function(v)
    S.slice.x = floor(v); b0.x, b1.x = 128 - v, 128 + v
  end)
  local cam = camera(S, K, -500, -10, 6)
  repeat cam(); K.tick() until slice.done
  b0.visible, b1.visible = false, false
  S.slice = nil
  K.blackout(S)
end

-- 8 (ov119_0225FA2C): the field shreds, three balls rise spinning, each
-- painting a black column up behind it
local function trainerWaterDay(S, K)
  K.tick()
  local f = K.flash(S, 16, -16, 2)
  K.spawn(S, function() K.wait(14); wave(S, K, 0x2AA, 12, 800, true) end)
  K.waitFor(function() return f.done end)
  local cam = camera(S, K, -500, -10, 16)
  local live = {}
  local function launch(x, spin)
    local b = ball(S, K, "hgss_ball", x, 231)
    b.visible = true
    local Y, R, C = K.Lin(231, -32, 6), K.Lin(0, spin, 6), K.Lin(312, 0, 6)
    local h = K.spawn(S, function()
      local d
      repeat
        local cy
        cy, d = C()
        S.rects[#S.rects + 1] = { x = x - 43, y = cy - 32, w = 86, h = 64 }
        b.y = Y(); b.rot = R()
        K.tick()
      until d
      b.visible = false
    end)
    live[#live + 1] = h
  end
  K.wait(7); launch(43, 0xFFFF)                      -- state 3
  K.wait(5); launch(215, -0xFFFF)                    -- state 4
  K.wait(3); launch(129, 0xFFFF)                     -- state 5
  local function all() for _, h in ipairs(live) do if not h.done then return false end end return true end
  while not all() do cam(); K.tick() end             -- state 6
  K.blackout(S)
end

-- 9 (ov119_0225F670): the field shreds, a ghostly ball fades in spinning,
-- swells, collapses, and a black box opens from the centre
local function trainerWaterNight(S, K)
  K.tick()
  local f = K.flash(S, -16, -16, 2)
  K.spawn(S, function() K.wait(12); wave(S, K, 0x2AA, 12, 800, true) end)
  K.waitFor(function() return f.done end)
  local b0 = ball(S, K, "hgss_ball_split", 128, 96, 0)
  local b1 = ball(S, K, "hgss_ball_split", 128, 96, 1)
  local A, R = K.Lin(0, 16, 8), K.Lin(0, 0xFFFF, 8)
  b0.alpha, b1.alpha = 0, 0
  K.tick()                                           -- state 3
  b0.visible, b1.visible = true, true
  local prev, d = 0, false
  repeat
    local a, r
    a, d = A(); r = R()
    b0.alpha, b1.alpha = a / 16, a / 16
    b0.rot, b1.rot = r, prev
    prev = r
    K.tick()
  until d
  b0.rot, b1.rot, b0.alpha, b1.alpha = 0, 0, 1, 1
  local Sc = K.Quad(1, 0x29 / FX, 0.1, 8)            -- state 5
  local cam = camera(S, K, -500, -10, 8)
  local box = K.fade(S, "box", "black", 8)
  local sd = false
  repeat
    if not sd then local s; s, sd = Sc(); b0.scale, b1.scale = s, s end
    cam(); K.tick()
  until sd and box.done
  b0.visible, b1.visible = false, false
  S.other = -16
end

-- 10 (ov119_02260258): three balls drop spinning, then black blocks stack
-- up from the bottom row
local BLOCK_COLUMNS = { 0, 2, 5, 7, 1, 6, 3, 4 }
local function trainerCaveDay(S, K)
  K.tick()
  local f = K.flash(S, 16, -16, 2)
  K.waitFor(function() return f.done end)
  local live = {}
  local function drop(x, spin)
    local b = ball(S, K, "hgss_ball", x, -32)
    b.visible = true
    local Y, R = K.Lin(-32, 224, 5), K.Lin(0, spin, 5)
    live[#live + 1] = { b = b, h = K.spawn(S, function()
      local d
      repeat local y; y, d = Y(); b.y = y; b.rot = R(); K.tick() until d
    end) }
  end
  K.tick(); drop(128, 0xFFFF)                        -- state 3
  K.tick(); drop(208, -0xFFFF)                       -- state 4
  K.wait(3); drop(48, 0xFFFF)                        -- state 5
  local function all() for _, l in ipairs(live) do if not l.h.done then return false end end return true end
  K.waitFor(all)                                     -- state 6
  for _, l in ipairs(live) do l.b.visible = false end
  K.tick()                                           -- state 7
  local cam = camera(S, K, -1000, 10, 64)
  for i = 0, 47 do                                   -- state 8: one a tick, in place the next
    cam(); K.tick()
    local col, row = BLOCK_COLUMNS[i % 8 + 1], floor(i / 8)
    S.rects[#S.rects + 1] = { x = 32 * col, y = 160 - 32 * row, w = 32, h = 32 }
  end
  cam(); K.tick()
  K.blackout(S)
end

-- 11 (ov119_0225FF9C): the ball falls toward the camera, growing, then the
-- half-circle iris closes
local function trainerCaveNight(S, K)
  K.tick()
  local f = K.flash(S, -16, -16, 2)
  K.waitFor(function() return f.done end)
  local b = ball(S, K, "hgss_ball", 128, -32)
  local Y, Sc, R = K.Quad(0, 256, 2, 12), K.Quad(0.1, 2, 0, 12), K.Lin(0, 0xFFFF, 12)
  K.tick()                                           -- state 3
  b.visible = true
  local d
  repeat
    local y
    y, d = Y(); b.y = y - 32; b.scale = (Sc()); b.rot = R()
    K.tick()
  until d
  b.visible = false
  local cam = camera(S, K, -1000, 10, 8)             -- state 5
  local iris = K.fade(S, "dome", "black", 8)
  repeat cam(); K.tick() until iris.done
  S.other = -16
end

-- 46 (ov120_0225F714): Red's ball over a random dissolve to black
local function red(S, K)
  K.tick()
  local f = K.flash(S, -16, -16, 2)
  K.waitFor(function() return f.done end)
  K.sprite(S, { key = "hgss_red", cell = 0, x = 128, y = 96, palette = PAL1, pri = 0 })
  K.tick()                                           -- state 3
  local order = {}
  for i = 0, 47 do order[i] = i end
  local rnd = (love and love.math and love.math.random) or math.random
  for i = 0, 46 do
    local j = rnd(0, 47)
    order[i], order[j] = order[j], order[i]
  end
  for i = 0, 47 do
    local c = order[i]
    S.rects[#S.rects + 1] = { x = (c % 8) * 32, y = floor(c / 8) * 32, w = 32, h = 32 }
    K.tick()
  end
  K.blackout(S)
end

-- 12-28 (ov115_0225F220): the gym leaders and the rival. One white flash
-- (the bottom screen stays white); the band scrolls in behind a zigzag edge;
-- three VS echoes collapse onto the jittering logo; the mugshot slides in as
-- a silhouette, overshoots and springs back; a white peak brings its colours,
-- darkens the field and shows the name; then white
local VS_PAL = "hgss/" .. 0x3B
local JITTER = { { 0, 0 }, { 0, 2 }, { 2, 2 } }
-- ov115_0225F020 / 0225F0B4: the VS at (x, y), as a task of 16 calls --
-- ghost i (cell 1, 2.0 -> 1.0 over 6) from call 3i, hidden on its 7th
-- update; the logo itself (cell 0, its 3-tick jitter) from call 9 on
function H.vs(S, K, x, y)
  return K.spawn(S, function()
    local ghosts = {}
    for c = 0, 15 do
      if c % 3 == 0 and c <= 9 then
        if c < 9 then
          ghosts[#ghosts + 1] = { lin = K.LinF(2, 1, 6), s = K.sprite(S, { key = "hgss_vs", cell = 1,
            x = x, y = y, scale = 2, pri = 0, palette = VS_PAL }) }
        else
          local real = K.sprite(S, { key = "hgss_vs", cell = 0, x = x, y = y, pri = 0, palette = VS_PAL })
          K.spawn(S, function(h)
            local i = 0
            while not h.dead do
              local o = JITTER[i % 3 + 1]
              real.x, real.y = x + o[1], y + o[2]
              i = i + 1
              K.tick()
            end
          end)
        end
      end
      for _, g in ipairs(ghosts) do
        if not g.done then
          local v, d = g.lin()
          g.s.scale = v
          if d then g.done, g.s.visible = true, false end
        end
      end
      K.tick()
    end
  end)
end

local function leader(id)
  local slot = id == 28 and 8 or (id - 12) % 8
  local band = ("hgss_band_%d/banner"):format(slot)
  local mug = ("hgss_leader_%d/mugshot"):format(id)
  return function(S, K, T)
    K.tick()                                         -- state 0
    local f = K.flash(S, 16, 16, 1)
    K.waitFor(function() return f.done end)          -- states 1-2
    -- state 3 (W): the band, its scroll, the wipe
    S.banner = { key = band, scroll = 0, edge = 255 }
    K.spawn(S, function(h)
      while not h.dead do K.tick(); S.banner.scroll = (S.banner.scroll + 30) % 512 end
    end)
    local reveal = K.drive(S, K.Lin(255, 0, 6), function(v) S.banner.edge = v end)
    K.waitFor(function() return reveal.done end)     -- W+7
    K.wait(12)                                       -- the flag at W+9, 10 idle
    -- state 5's VS, W+20..W+35
    local vs = H.vs(S, K, 72, 74)
    K.waitFor(function() return vs.done end)
    -- state 6 / 7: the silhouette slides in (272, 220, 193, 191, 214)
    local m = K.sprite(S, { key = mug, cell = 0, x = 272, y = 66, dark = 14, pri = 1 })
    K.tick()
    local Q, d = K.Quad(272, 214, -64, 4), false
    repeat local v; v, d = Q(); m.x = v; K.tick() until d
    K.tick()                                         -- state 8
    K.wait(10)
    local up = K.Lin(0, 16, 3)
    repeat
      local v; v, d = up(); S.bright = v
      if d then                                      -- the white peak
        m.dark = 0
        S.darkField = 14
        S.name = { text = T and T.trainerName, x = 122, y = 80 }
      end
      K.tick()
    until d
    K.tick()                                         -- state 10
    local down = K.Lin(16, 0, 3)
    repeat local v; v, d = down(); S.bright = v; K.tick() until d
    K.wait(27)
    local w = K.fade(S, "bright", "white", 15)
    K.waitFor(function() return w.done end)
    S.other = 16
  end
end

local TURN, DEG = 0x10000, 0x10000 / 360

-- 29-33 (ov115_0225F978): the Elite Four and Lance. One white flash; the
-- field freezes, a quarter bright; the player and the opponent slide in as
-- silhouettes on their flame streaks, overshoot and settle; the VS; the name;
-- a white peak brings their colours and sets the streaks' palettes cycling;
-- a growing diagonal shake; they fly apart into white. (The cartridge's 3D
-- particle bursts -- SPA 0x97 / 0x98 -- are not drawn; their time is kept.)
local E4_STREAK_PAL = { [29] = 0x2F, [30] = 0x33, [31] = 0x34, [32] = 0x35, [33] = 0x36 }
local function league(id)
  local shakeSteps = id == 33 and 9 or 32
  local oppKey = ("hgss_e4_%d/mugshot"):format(id)
  local streakPal = "hgss/" .. E4_STREAK_PAL[id]
  return function(S, K, T)
    K.tick()                                         -- state 0
    local girl = T and (T.playerGender == "girl" or T.playerGender == "female")
    local p = K.sprite(S, { key = girl and "hgss_player_female/mugshot" or "hgss_player_male/mugshot",
                            cell = 0, x = -128, y = 92, dark = 14, pri = 1, visible = false })
    local r = K.sprite(S, { key = oppKey, cell = 0, x = 384, y = 92, dark = 14, pri = 1, visible = false })
    local sp = K.sprite(S, { key = "hgss_streak", cell = 0, x = -112, y = 96, palette = streakPal,
                             pri = 2, visible = false })
    local sr = K.sprite(S, { key = "hgss_streak", cell = 12, x = 368, y = 96, palette = streakPal,
                             pri = 2, visible = false })
    K.tick()                                         -- state 1
    local f = K.flash(S, 16, 16, 1)                  -- state 2
    K.spawn(S, function() K.wait(8); S.freeze = true end)
    K.waitFor(function() return f.done end)          -- state 3
    K.tick()                                         -- state 4 (W)
    local jitter = 0
    local function place(px, py, rx, ry)
      p.x, p.y, r.x, r.y = px, py, rx, ry
      sp.x, sp.y, sr.x, sr.y = px + 16 + jitter, py + 4, rx - 16 + jitter, ry + 4
    end
    -- state 5 / 6: the slides (-128 -> 56, 384 -> 200), the name, the VS
    local Q0, Q30 = K.Quad(-128, 56, 80, 6), K.Quad(384, 200, -80, 6)
    place(-128, 92, 384, 92)
    p.visible, r.visible, sp.visible, sr.visible = true, true, true, true
    K.tick()
    local vs
    local d, n = false, 0
    repeat
      local a, b
      a, d = Q30(); b = Q0()
      place(b, 92, a, 92)
      n = n + 1
      if n == 3 then S.name = { text = T and T.trainerName, x = 168, y = 104 } end
      if n == 4 then vs = H.vs(S, K, 128, 96) end
      K.tick()
    until d
    vs = vs or H.vs(S, K, 128, 96)
    local px, rx = p.x, r.x
    -- state 7: the VS, and the first particle burst's time (to about W+38)
    K.waitFor(function() return vs.done end)
    K.wait(18)
    -- state 8: the white peak; true colours; the streaks start cycling
    local up = K.Lin(0, 16, 3)
    repeat local v; v, d = up(); S.bright = v; K.tick() until d
    p.dark, r.dark = 0, 0
    K.spawn(S, function(h)
      local t = 0
      while not h.dead do
        sp.cell, sr.cell = t % 12, 12 + t % 12
        jitter = (t % 2) * 2
        place(p.x, p.y, r.x, r.y)
        t = t + 1
        K.tick()
      end
    end)
    K.tick()                                         -- state 9
    local down = K.Lin(16, 0, 6)
    repeat local v; v, d = down(); S.bright = v; K.tick() until d
    K.wait(8)
    -- state 12: the shake, growing to 2 px along the diagonal
    local Q = K.Quad(0, -2, 0, shakeSteps)
    local t4 = 0
    repeat
      local s; s, d = Q()
      t4 = t4 + 1
      local sg = (math.floor(t4 / 2) % 2 == 0) and 1 or -1
      place(px + s * sg, 92 + s * sg, rx - s * sg, 92 - s * sg)
      K.tick()
    until d
    -- state 13: apart, diagonally, under an 8-step white
    S.name = nil
    local F = K.Quad(0, 192, 24, 16)
    local w = K.fade(S, "bright", "white", 8)
    repeat
      local q = F()
      place(px - q, 92 - q, rx + q, 92 + q)
      K.tick()
    until w.done
    S.other = 16
  end
end

-- 35 / 36 (ov116_0225F1BC): Ho-Oh and Lugia. One white flash; under a short
-- blur the view widens (perspective + 0x100 over 40), holds, then dives at
-- the player (distance - 660 / - 550, Quad v0 0.5 over 8); a 60-step white
local function bird(dive)
  return function(S, K)
    K.tick()
    local f = K.flash(S, 16, 16, 1)
    K.waitFor(function() return f.done end)
    S.blur = 5 / 18                                  -- motion blur (5, 13)
    local fov, d = K.Lin(K.FOV0, K.FOV0 + 0x100, 40), false
    repeat local v; v, d = fov(); S.zoom = K.fovZoom(v); K.tick() until d
    local z = S.zoom
    K.wait(6)
    local dist = K.Quad(K.D0, K.D0 + dive, 0.5, 8)
    repeat local v; v, d = dist(); S.zoom = z * K.zoomFor(v); K.tick() until d
    local w = K.fade(S, "bright", "white", 60)
    K.waitFor(function() return w.done end)
    S.other = 16
  end
end

-- 37 (ov114_0225F020): Frontier / link single. A translucent ball fades in,
-- shrinks, and the circle iris (fade 16) closes; black
local function frontier(S, K)
  K.tick()
  local f = K.flash(S, 16, -16, 2)
  K.waitFor(function() return f.done end)
  local b = K.sprite(S, { key = "hgss_ball_split", cell = 0, x = 128, y = 96, palette = PAL0, alpha = 0 })
  K.tick()                                           -- state 3
  local A, d = K.Lin(0, 16, 12), false
  repeat local a; a, d = A(); b.alpha = a / 16; K.tick() until d
  b.alpha = 1
  local Sc, sd = K.Quad(1, 0x19A / FX, 1 / FX, 6), false
  local iris = K.fade(S, "circle", "black", 6)
  repeat
    if not sd then local v; v, sd = Sc(); b.scale = v end
    K.tick()
  until sd and iris.done
  b.visible = false
  S.other = -16
end

-- 38 (ov114_0225F280): doubles. Four balls burst up / down / left / right,
-- then the cross-wedge wipe (fade 34); black
local function double(S, K)
  K.tick()
  local f = K.flash(S, 16, -16, 2)
  K.waitFor(function() return f.done end)
  local balls = {}
  for i = 1, 4 do balls[i] = K.sprite(S, { key = "hgss_ball", cell = 0, x = 128, y = 96, palette = PAL0 }) end
  K.tick()                                           -- state 3
  local Q1, Q2, d = K.Quad(0, 128, 0x19A / FX, 4), K.Quad(0, 160, 0x19A / FX, 4), false
  repeat
    local a, b
    a, d = Q1(); b = Q2()
    balls[1].y, balls[2].y, balls[3].x, balls[4].x = 96 - a, 96 + a, 128 - b, 128 + b
    K.tick()
  until d
  local w = K.fade(S, "x", "black", 8)
  K.waitFor(function() return w.done end)
  for _, b in ipairs(balls) do b.visible = false end
  S.other = -16
end

-- 39 (ov117_0225F020): six spinning "R"s swoop in from the edges, shrinking,
-- onto (128, 100); then the cross-wedge wipe; black
local EMBLEMS = {   -- { from x, from y, v0 x, v0 y, spin in degrees }, ov117_0225FAF4
  { 260, 0, -30, 20, 720 }, { -16, 160, 30, -20, 360 }, { 0, -16, 30, 20, -1080 },
  { 140, 160, -10, -20, -720 }, { 260, 80, -30, 1, -1080 }, { 0, 160, 30, -20, 360 },
}
local EMBLEM_DELAYS = { 4, 3, 4, 2, 3, 3 }
local function rocketGrunt(S, K)
  K.tick()
  local f = K.flash(S, -16, -16, 2)
  K.waitFor(function() return f.done end)
  local live = {}
  local i, countdown = 1, EMBLEM_DELAYS[1]
  while i <= #EMBLEMS do
    countdown = countdown - 1
    if countdown < 0 then
      local e = EMBLEMS[i]
      local sp = K.sprite(S, { key = "hgss_rocket_r", cell = 0, x = e[1], y = e[2], scale = 2,
                               palette = "hgss/3" })
      local X, Y = K.Quad(e[1], 128, e[3], 8), K.Quad(e[2], 100, e[4], 8)
      local Sc, R = K.Quad(2, 0.01, -0.1, 8), K.Lin(0, floor(e[5] * DEG), 8)
      live[#live + 1] = K.spawn(S, function()
        while true do
          local x, d = X()
          if d then sp.visible = false; return end
          sp.x, sp.y, sp.scale, sp.rot = x, (Y()), (Sc()), (R())
          K.tick()
        end
      end)
      i = i + 1
      countdown = EMBLEM_DELAYS[i] or 0
    end
    K.tick()
  end
  K.waitFor(function() return live[#live].done end)
  local w = K.fade(S, "x", "black", 12)
  K.waitFor(function() return w.done end)
  S.other = -16
end

-- 40-44 (ov117_0225F524): the executives and Giovanni. Red speed lines
-- stream over the field, a dark panel with an R outline opens as a band
-- from the centre line, the rails and the filled R fade in as the mugshot
-- glides in with the name, a white jolt, the mugshot leaves left; white
local ROCKET_GREY = { 41 / 255, 41 / 255, 41 / 255 }   -- 0x14A5
local function executive(id)
  local mugKey = ("hgss_exec_%d/mugshot"):format(id)
  return function(S, K, T)
    local m = K.sprite(S, { key = mugKey, cell = 0, x = 320, y = 128, pri = 0, visible = false })
    local lines = { key = "hgss_rocket_lines", palette = "hgss/215", hofs = 0, alpha = 12 / 16, visible = false }
    local panel = { key = "hgss_rocket_panel", palette = "hgss/215", visible = false, clip = { 96, 96 } }
    S.layers = { lines, panel }                      -- BG3 (prio 1) over BG1 (prio 2)
    K.flash(S, 16, -16, 1)                           -- not waited for
    K.tick()                                         -- state 0
    lines.visible = true
    for _ = 1, 12 do lines.hofs = lines.hofs + 24; K.tick() end
    panel.visible = true                             -- state 3: the band opens
    local A, d = K.Quad(0, 96, 4, 4), false
    repeat
      local a; a, d = A()
      panel.clip = { 96 - a, 96 + a }
      lines.hofs = lines.hofs + 24
      K.tick()
    until d
    panel.clip, lines.hofs = nil, 0
    -- the panel is the whole screen now; past the DS's edges, its grey
    S.fieldFill = ROCKET_GREY
    K.wait(13)
    -- state 6: the rails and filled R over the outline, the mugshot in
    local rails = { key = "hgss_rocket_rails", palette = "hgss/215", alpha = 0, visible = true }
    S.layers = { panel, rails }
    m.visible = true
    local counter, x = 0, 320
    while true do
      counter = math.min(16, counter + 4)
      rails.alpha = counter / 16
      x = x + 2 * (128 - x) / 3
      if x <= 130 then x = 128 end
      m.x = x
      if counter > 4 then S.name = { text = T and T.trainerName, x = x + 8, y = 160 } end
      if x == 128 and counter == 16 then break end
      K.tick()
    end
    -- the brightness jolt over everything but the backdrop; the field off
    S.fieldFill = ROCKET_GREY
    for v = 16, 0, -2 do S.bright = v; K.tick() end
    K.wait(16)
    panel.visible = false
    local Q, prev = K.Quad(128, -96, 2, 8), 128
    repeat
      local v; v, d = Q()
      m.x = prev
      if S.name then S.name.x = prev + 8; S.name.hidden = prev <= -8 end
      prev = v
      K.tick()
    until d
    S.other = 16
    local w = K.fade(S, "bright", "white", 4)
    K.waitFor(function() return w.done end)
    m.visible = false
  end
end

-- 45 (ov118_0225F020): Kimono Girls. Two shoji doors slide shut over the
-- field, and open again onto black
local function kimono(S, K)
  local left = { key = "hgss_kimono", palette = "hgss/166", wrapW = 512, hofs = 128, visible = false }
  local right = { key = "hgss_kimono_mirror", palette = "hgss/166", wrapW = 512, hofs = 256, visible = false }
  S.layers = { right, left }
  K.tick()
  local f = K.flash(S, -16, -16, 2)
  K.waitFor(function() return f.done end)
  local Q, d = K.Quad(128, 0, 5, 18), false
  left.visible, right.visible = true, true
  K.tick()                                           -- state 3
  repeat local q; q, d = Q(); left.hofs, right.hofs = q, 384 - q; K.tick() until d
  K.wait(6)
  S.fieldFill = { 0, 0, 0 }                          -- BG0 off behind the closed doors
  K.tick()
  Q = K.Quad(0, 128, 5, 18)
  K.tick()
  repeat local q; q, d = Q(); left.hofs, right.hofs = q, 384 - q; K.tick() until d
  K.blackout(S)
end

H.SCRIPTS = {
  [0] = land(false), [1] = land(true),
  [2] = water(false), [3] = water(true),
  [4] = cave(false), [5] = cave(true),
  [6] = trainerLandDay, [7] = trainerLandNight,
  [8] = trainerWaterDay, [9] = trainerWaterNight,
  [10] = trainerCaveDay, [11] = trainerCaveNight,
  [46] = red,
}
for id = 12, 28 do H.SCRIPTS[id] = leader(id) end
H.SCRIPTS[37], H.SCRIPTS[38], H.SCRIPTS[39], H.SCRIPTS[45] = frontier, double, rocketGrunt, kimono
for id = 29, 33 do H.SCRIPTS[id] = league(id) end
H.SCRIPTS[35], H.SCRIPTS[36] = bird(-660), bird(-550)
for id = 40, 44 do H.SCRIPTS[id] = executive(id) end

-- script(id) -> function(S, K) or nil
function H.script(id) return H.SCRIPTS[id] end

return H
