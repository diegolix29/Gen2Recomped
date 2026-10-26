-- PerfOverlay: an on-screen performance readout for desktop AND Android.
--
-- WHY THIS EXISTS
--
-- The Android build has no log a player can read, so "it feels choppy" could
-- not be turned into a number. This draws the numbers over the game, small
-- enough to leave the picture readable, so a screenshot carries them.
--
-- TOGGLES (any of them)
--   * the PERF OVERLAY row in the mod's settings (remembered)
--   * F3 on a keyboard
--   * a THREE-FINGER TAP on a touch screen
-- F3 and the tap flip it for this session on top of the row.
--
-- WHAT IT SHOWS
--   frame    FPS, average frame time over the last second, the worst frame in
--            the last 1 s and 10 s, and how many frames in the last 10 s went
--            over 33 ms (a dropped frame at 30 fps) and 50 ms (a visible hitch)
--   split    time spent in the game's draw call vs everything else
--            (update + present/vsync wait), and Lua heap size
--   gpu      love.graphics.getStats for the frame: draw calls, canvas and
--            shader switches, texture memory
--   loading  Gen 4/5 effect mesh builds (Gen4Budget) per second and the time
--            they took, the slowest single build in the last 10 s, engine land
--            and building model loads, trees still waiting to be built
--   by type  where the build time went over the last 5 s (trees, npc, grass...)
--   arena    on a Colosseum overworld fight: world renders per second, how many
--            frames reused the last world, the device tier
--
-- COST WHEN OFF: one boolean test per frame. The engine-load timers and the
-- build hook only measure while the overlay is showing.

local V = ...
local P = { installed = false, forced = nil, visible = false }

P.OPTION_KEY = "perfOverlay"
P.RING = 600                  -- frames of history (10 s at 60 fps)

local clock = (love and love.timer and love.timer.getTime) or os.clock

-- ------------------------------------------------------------- settings --

local optionValue, optionAt = false, -math.huge
local function optionOn()
  local t = clock()
  if t - optionAt < 0.5 then return optionValue end
  optionAt = t
  local m = V and V.mod
  local opts = m and m.options
  local v = false
  if opts and type(opts.get) == "function" then
    local ok, value = pcall(opts.get, opts, P.OPTION_KEY)
    if ok then v = (value == true or value == 1 or value == "1" or value == "on" or value == "true") end
  end
  optionValue = v
  return v
end

function P.enabled()
  if P.forced ~= nil then return P.forced end
  return optionOn()
end

function P.toggle()
  P.forced = not P.enabled()
  return P.forced
end

-- ---------------------------------------------------------------- state --

local ring = { dt = {}, draw = {}, n = 0, head = 0 }
local frameBuildMs, frameBuilds, frameEngMs, frameEngN = 0, 0, 0, 0
local kindAcc, kindShown, kindAt = {}, {}, nil
local peak = { ms = 0, kind = nil, t = -math.huge }
local perSec = { t = nil, builds = 0, buildMs = 0, engN = 0, engMs = 0, renders = 0, reuses = 0, skips = 0 }
local shown = { builds = 0, buildMs = 0, engN = 0, engMs = 0, renders = 0, reuses = 0, skips = 0,
                logN = 0, logMs = 0 }

-- LOG COST. Every engine and mod log line goes through src.core.Logger (the
-- mod's V.mod.log included). Counted always (one add); timed only while the
-- overlay shows. The time is what the logger itself spends (format, the
-- repeat limiter, print to the console / logcat, the buffered file write) --
-- not the caller building its own message string first.
local logN, logMs = 0, 0
local logLast = { n = 0, ms = 0, t = nil }
local function hookLogger()
  local okL, Logger = pcall(require, "src.core.Logger")
  if not (okL and type(Logger) == "table") or Logger.__perfOverlayHooked then return end
  Logger.__perfOverlayHooked = true
  for _, level in ipairs({ "info", "warn", "error", "debug", "report" }) do
    local inner = Logger[level]
    if type(inner) == "function" then
      Logger[level] = function(...)
        logN = logN + 1
        if not P.visible then return inner(...) end
        local t0 = clock()
        inner(...)
        logMs = logMs + (clock() - t0) * 1000
      end
    end
  end
end
local arenaLast = nil
local gpu = nil

local function push(dt, drawMs)
  ring.head = ring.head % P.RING + 1
  ring.dt[ring.head] = dt
  ring.draw[ring.head] = drawMs
  if ring.n < P.RING then ring.n = ring.n + 1 end
end

-- stats over the last `seconds` of frames
local function window(seconds)
  local sum, n, worst, over33, over50, drawSum, acc = 0, 0, 0, 0, 0, 0, 0
  local i = ring.head
  for _ = 1, ring.n do
    local dt = ring.dt[i]
    if not dt then break end
    acc = acc + dt
    if acc > seconds and n > 0 then break end
    sum, n = sum + dt, n + 1
    drawSum = drawSum + (ring.draw[i] or 0)
    if dt > worst then worst = dt end
    if dt > 0.033 then over33 = over33 + 1 end
    if dt > 0.050 then over50 = over50 + 1 end
    i = i - 1
    if i < 1 then i = P.RING end
  end
  return { avg = n > 0 and sum / n or 0, worst = worst, over33 = over33, over50 = over50,
           draw = n > 0 and drawSum / n or 0, n = n }
end

-- ----------------------------------------------------- measurement hooks --

-- Gen4Budget.charge reports every effect mesh build here while visible.
local function onCharge(kind, ms)
  if not P.visible then return end
  frameBuildMs, frameBuilds = frameBuildMs + ms, frameBuilds + 1
  kind = kind or "?"
  kindAcc[kind] = (kindAcc[kind] or 0) + ms
  if ms > peak.ms or clock() - peak.t > 10 then peak.ms, peak.kind, peak.t = ms, kind, clock() end
end

local function hookBudget()
  local okB, B = pcall(V.require, "Gen4Budget")
  if okB and type(B) == "table" then B.onCharge = onCharge end
end

-- Engine model loads (Gen4Ground.modelFor runs only on a cache miss; building
-- is a cache lookup that decodes on first use, so only slow calls count).
local engineHooked = false
local function hookEngine()
  if engineHooked then return true end
  local Ground = package.loaded["src.render.Gen4Ground"]
  if type(Ground) ~= "table" then return false end
  engineHooked = true
  local function timed(name, minMs)
    local inner = Ground[name]
    if type(inner) ~= "function" then return end
    Ground[name] = function(self, ...)
      if not P.visible then return inner(self, ...) end
      local t0 = clock()
      local a, b, c = inner(self, ...)
      local ms = (clock() - t0) * 1000
      if ms >= minMs then frameEngMs, frameEngN = frameEngMs + ms, frameEngN + 1 end
      return a, b, c
    end
  end
  timed("modelFor", 0)
  timed("building", 0.3)
  return true
end

-- ------------------------------------------------------------- sampling --

local function sampleSecond(now)
  if not perSec.t then perSec.t = now end
  perSec.builds = perSec.builds + frameBuilds
  perSec.buildMs = perSec.buildMs + frameBuildMs
  perSec.engN = perSec.engN + frameEngN
  perSec.engMs = perSec.engMs + frameEngMs
  frameBuilds, frameBuildMs, frameEngN, frameEngMs = 0, 0, 0, 0
  -- the arena's own cumulative counters, differenced per second
  local Snap = V and V.ArenaOverworldSnapshot
  local st = Snap and type(Snap.stats) == "function" and Snap.stats() or nil
  if now - perSec.t >= 1 then
    local span = now - perSec.t
    shown.builds, shown.buildMs = perSec.builds / span, perSec.buildMs / span
    shown.engN, shown.engMs = perSec.engN / span, perSec.engMs / span
    if st and arenaLast and arenaLast.ref == st then
      shown.renders = ((st.renders or 0) - arenaLast.renders) / span
      shown.reuses = ((st.reuses or 0) - arenaLast.reuses) / span
      shown.skips = ((st.motionSkips or 0) - arenaLast.skips) / span
    else
      shown.renders, shown.reuses, shown.skips = 0, 0, 0
    end
    arenaLast = st and { ref = st, renders = st.renders or 0, reuses = st.reuses or 0,
                         skips = st.motionSkips or 0 } or nil
    perSec.t, perSec.builds, perSec.buildMs, perSec.engN, perSec.engMs = now, 0, 0, 0, 0
    shown.logN, shown.logMs = (logN - logLast.n) / span, (logMs - logLast.ms) / span
    logLast.n, logLast.ms = logN, logMs
    hookEngine()                 -- Gen4Ground may load after the overlay first showed
  end
  -- by-type totals roll every 5 s
  kindAt = kindAt or now
  if now - kindAt >= 5 then
    local list = {}
    for k, ms in pairs(kindAcc) do list[#list + 1] = { k, ms } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    kindShown, kindAcc, kindAt = list, {}, now
  end
end

-- ---------------------------------------------------------------- draw --

local function fmt(ms) return string.format("%.1f", ms) end

local function lines()
  local w1, w10 = window(1), window(10)
  local fps = (love.timer and love.timer.getFPS) and love.timer.getFPS() or 0
  local out = {}
  out[#out + 1] = string.format("FPS %d   frame %s ms   worst %s ms (1s) %s ms (10s)",
    fps, fmt(w1.avg * 1000), fmt(w1.worst * 1000), fmt(w10.worst * 1000))
  out[#out + 1] = string.format("last 10s: %d frames > 33 ms, %d > 50 ms", w10.over33, w10.over50)
  out[#out + 1] = string.format("draw %s ms   update+wait %s ms   lua %.0f MB",
    fmt(w1.draw), fmt(math.max(0, w1.avg * 1000 - w1.draw)), collectgarbage("count") / 1024)
  if gpu then
    out[#out + 1] = string.format("gpu: %d draws  %d canvas  %d shader  tex %.0f MB",
      gpu.drawcalls or 0, gpu.canvasswitches or 0, gpu.shaderswitches or 0,
      (gpu.texturememory or 0) / 1048576)
  end
  local trees = ""
  local okT, GT = pcall(V.require, "Gen4Trees")
  if okT and type(GT) == "table" and (GT.pendingLands or 0) > 0 then
    trees = string.format("   trees waiting: %d land(s)", GT.pendingLands)
  end
  out[#out + 1] = string.format("loading: %.0f builds/s %.0f ms/s   slowest %s ms (%s)%s",
    shown.builds, shown.buildMs, fmt(peak.ms), tostring(peak.kind or "-"), trees)
  out[#out + 1] = string.format("log: %.0f lines/s  %.1f ms/s in the logger", shown.logN, shown.logMs)
  if shown.engN > 0 or shown.engMs > 0 then
    out[#out + 1] = string.format("engine models: %.1f loads/s  %.0f ms/s", shown.engN, shown.engMs)
  end
  if #kindShown > 0 then
    local parts = {}
    for i = 1, math.min(4, #kindShown) do
      parts[#parts + 1] = string.format("%s %.0f", kindShown[i][1], kindShown[i][2])
    end
    out[#out + 1] = "build ms, last 5s: " .. table.concat(parts, "  ")
  end
  local Snap = V and V.ArenaOverworldSnapshot
  if Snap and type(Snap.nativeWorld) == "function" and Snap.nativeWorld() then
    local tier = type(Snap.tierName) == "function" and Snap.tierName() or "?"
    out[#out + 1] = string.format("arena world: %.0f renders/s  %.0f reused/s  %.0f motion-skips/s  tier %s",
      shown.renders, shown.reuses, shown.skips, tier)
  end
  return out
end

local function drawOverlay()
  local g = love.graphics
  local font = g.getFont()
  local w, h = g.getDimensions()
  -- readable on a phone: grow with the short side of the screen
  local s = math.max(1, math.floor(math.min(w, h) / 420))
  local text = lines()
  local lh = font:getHeight() + 2
  local width = 0
  for _, t in ipairs(text) do width = math.max(width, font:getWidth(t)) end
  g.push("all")
  g.setCanvas()
  g.origin()
  g.setShader()
  g.setScissor()
  g.setBlendMode("alpha")
  g.scale(s, s)
  g.setColor(0, 0, 0, 0.62)
  g.rectangle("fill", 4, 4, width + 12, #text * lh + 8, 4, 4)
  for i, t in ipairs(text) do
    local warn = (i == 1 and ring.dt[ring.head] and ring.dt[ring.head] > 0.033)
    if warn then g.setColor(1, 0.75, 0.4, 1) else g.setColor(1, 1, 1, 1) end
    g.print(t, 10, 8 + (i - 1) * lh)
  end
  g.pop()
end

-- Called once per rendered frame, after the game has drawn.
function P.frame(drawSeconds)
  local on = P.enabled()
  if on ~= P.visible then
    P.visible = on
    if on then hookBudget(); hookEngine() end
  end
  if not on then return end
  local dt = (love.timer and love.timer.getDelta) and love.timer.getDelta() or 0
  push(dt, (drawSeconds or 0) * 1000)
  local g = love.graphics
  if g and g.getStats then
    local ok, st = pcall(g.getStats)
    if ok then gpu = st end
  end
  sampleSecond(clock())
  local ok, err = pcall(drawOverlay)
  if not ok and not P.warned then
    P.warned = true
    local l = V and V.mod and V.mod.log
    if l then pcall(l.warn, l, "PerfOverlay draw failed: %s", tostring(err)) end
  end
end

-- ------------------------------------------------------------- install --

function P.install()
  if P.installed then return true end
  local okG, Game = pcall(require, "src.core.Game")
  if not (okG and type(Game) == "table" and type(Game.draw) == "function") then return false end
  P.installed = true
  hookLogger()

  local innerDraw = Game.draw
  function Game:draw(...)
    local t0 = clock()
    local a, b, c = innerDraw(self, ...)
    local okF = pcall(P.frame, clock() - t0)
    return a, b, c
  end

  local innerKey = Game.keypressed
  if type(innerKey) == "function" then
    function Game:keypressed(key, ...)
      if key == "f3" then P.toggle(); return end
      return innerKey(self, key, ...)
    end
  end

  -- three fingers down at once toggles; held fingers do not repeat
  local innerTouch = Game.touchpressed
  if type(innerTouch) == "function" then
    local lastToggle = -math.huge
    function Game:touchpressed(id, x, y, ...)
      local touch = love.touch
      local n = (touch and touch.getTouches) and #touch.getTouches() or 0
      if n >= 3 and clock() - lastToggle > 0.6 then
        lastToggle = clock()
        P.toggle()
      end
      return innerTouch(self, id, x, y, ...)
    end
  end
  return true
end

P._test = { window = window, push = push, lines = lines, onCharge = onCharge,
            ring = ring, shown = shown }
return P
