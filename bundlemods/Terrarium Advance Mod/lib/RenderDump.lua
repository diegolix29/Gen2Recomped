-- RenderDump: F12 during a battle writes one report of what is on screen.
--
-- For bugs that only show as "this looks wrong" (ORAS flames, world layers
-- drawn over a Pokemon) a per-frame log is noise. One press instead saves:
--   1. every live actor and its draw groups (glow / xlu / noz / texture ...)
--   2. for ORAS species, the ROM-side mesh split (body / glow / skipped and
--      why) with raw material bytes, and each effect texture as a PNG
--   3. a trace of ONE frame: canvas switches, Gen 4/5 world effect passes and
--      every actor group draw, in the order they happened
-- Output: <save dir>/terrarium_dumps/<timestamp>/report.txt (+ PNGs).
--
-- PokemonActors polls F12 (debugFrame and withRenderer) and calls
-- the global hook below: PokemonActors is loaded through a separate
-- bootstrap that has no V.require, so a global is the one shared seam.

local V = ...
local D = {}

local state = nil   -- { dir, lines, trace, actors, scenes, restore }

local function lf() return love and love.filesystem end

local function writeFile(path, bytes)
  local fs = lf()
  if not fs then return false end
  return pcall(fs.write, path, bytes)
end

local function fmtNum(x) return type(x) == "number" and ("%.3f"):format(x) or tostring(x) end

local function canvasLabel(c)
  if not c then return "SCREEN" end
  if type(c) == "table" then
    local first = c[1]
    if type(first) == "table" then first = first[1] end
    local label = first and canvasLabel(first) or "?"
    return label .. (c.depthstencil and " +depth" or "") .. (#c > 1 and (" x" .. #c) or "")
  end
  local okW, w = pcall(c.getWidth, c)
  local okH, h = pcall(c.getHeight, c)
  local okF, f = pcall(c.getFormat, c)
  return ("%s %sx%s %s"):format(tostring(c):match("0x%x+") or tostring(c),
    okW and w or "?", okH and h or "?", okF and f or "")
end

-- ------------------------------------------------------------ the trace

local function push(kind, text)
  if state and state.trace and #state.trace < 4000 then
    state.trace[#state.trace + 1] = kind .. "  " .. text
  end
end
D.trace = push
function D.tracing() return state ~= nil and state.trace ~= nil end

local function startTrace()
  local g = love.graphics
  local saved = { setCanvas = g.setCanvas, clear = g.clear }
  g.setCanvas = function(...)
    local a = ...
    push("canvas", select("#", ...) == 0 and "SCREEN" or canvasLabel(a))
    return saved.setCanvas(...)
  end
  g.clear = function(...)
    push("clear", ("on %s"):format(canvasLabel(g.getCanvas())))
    return saved.clear(...)
  end
  -- Gen 4/5 world effect passes: the hook only fires while profiling
  local Bridge = V and V.Gen4Bridge
  if Bridge then
    saved.bridge, saved.profile, saved.hook = Bridge, Bridge.profile, Bridge.passHook
    Bridge.profile = true
    Bridge.passHook = function(name, dt)
      push("world-pass", ("%s %.2f ms"):format(tostring(name), (dt or 0) * 1000))
      if saved.hook then return saved.hook(name, dt) end
    end
  end
  state.restore = function()
    g.setCanvas, g.clear = saved.setCanvas, saved.clear
    if saved.bridge then
      saved.bridge.profile, saved.bridge.passHook = saved.profile, saved.hook
    end
  end
end

-- ------------------------------------------------------------ the report

local function describeActors(A, out)
  local live = {}
  for _, rec in pairs(A._liveActors or {}) do live[#live + 1] = rec end
  out[#out + 1] = ("LIVE ACTORS: %d"):format(#live)
  local now = love.timer and love.timer.getTime() or 0
  for n, rec in ipairs(live) do
    local sc = rec.scene or {}
    out[#out + 1] = ("[%d] dex %s  variant %s  source %s  stem %s  state %s  opacity %s  hidden %s")
      :format(n, tostring(rec.dex), tostring(rec.variant), tostring(sc.source),
        tostring(sc.stem), tostring(rec.state), fmtNum(rec.opacity), tostring(rec.hidden))
    out[#out + 1] = ("    acquired by %s  draws %d  last drawn %s")
      :format(tostring(rec.acquireSource), tonumber(rec.drawCount) or 0,
        rec.lastDrawAt and ("%.2fs ago"):format(now - rec.lastDrawAt) or "never")
    for i, grp in ipairs(sc.groups or {}) do
      local nv = (grp.mesh and grp.mesh.getVertexCount) and grp.mesh:getVertexCount() or 0
      local d = grp.diffuse or {}
      out[#out + 1] = ("    g%-2d verts %-6d tex %-3s glow %-3s xlu %-3s noz %-3s depthWrite %-3s diffuse %s,%s,%s alpha %s flags 0x%08X")
        :format(i, nv, grp.textured and "Y" or "N", grp.glow and "Y" or "N", grp.xlu and "Y" or "N",
          grp.noz and "Y" or "N", (grp.noz or grp.xlu or grp.glow) and "N" or "Y",
          fmtNum(d[1]), fmtNum(d[2]), fmtNum(d[3]), fmtNum(grp.alpha), grp.renderFlags or 0)
    end
  end
end

local function worldInfo(out)
  local okG, G = pcall(require, "src.core.Game")
  local game = okG and type(G) == "table" and (G.current or G.instance) or nil
  local Host = V and V.Gen4WorldHost
  out[#out + 1] = ("native Gen4/5 world bridge installed: %s"):format(
    tostring(V and V.Gen4Bridge and V.Gen4Bridge.installed))
  if Host and Host.stats then
    local parts = {}
    for k, v in pairs(Host.stats) do
      if type(v) ~= "table" then parts[#parts + 1] = k .. "=" .. tostring(v) end
    end
    table.sort(parts)
    out[#out + 1] = "Gen4WorldHost.stats: " .. table.concat(parts, " ")
  end
  if game then out[#out + 1] = "game: " .. tostring(game.gameId or game.romId or "?") end
end

local function finish()
  local s = state
  state = nil
  if s.restore then pcall(s.restore) end
  local out = s.lines
  out[#out + 1] = ""
  out[#out + 1] = ("FRAME TRACE (%d events, about 60 ms from the press):"):format(#s.trace)
  for _, l in ipairs(s.trace) do out[#out + 1] = "  " .. l end
  local path = s.dir .. "/report.txt"
  writeFile(path, table.concat(out, "\n") .. "\n")
  local full = (lf().getSaveDirectory and lf().getSaveDirectory() or "<save dir>") .. "/" .. path
  local mod = V and V.mod
  if mod and mod.log and mod.log.info then pcall(mod.log.info, mod.log, "RenderDump written: %s", full) end
  print("[Terrarium] RenderDump written: " .. full)
  D.lastPath = full
end

-- Called by PokemonActors on the F12 press (A, its scenes table), then once
-- per battle frame through D.frame.
function D.request(A)
  if state then return end
  local fs = lf()
  if not (fs and love.graphics) then return end
  local dir = "terrarium_dumps/" .. os.date("%Y%m%d_%H%M%S")
  pcall(fs.createDirectory, dir)
  state = { dir = dir, lines = {}, trace = {}, frames = 0,
            t0 = love.timer and love.timer.getTime() or 0 }
  local out = state.lines
  out[#out + 1] = "Terrarium RenderDump " .. os.date("%Y-%m-%d %H:%M:%S")
  pcall(worldInfo, out)
  out[#out + 1] = ""
  pcall(function()
    local okO, OB = pcall(V.require, "OverworldBattle")
    local okS, St = pcall(V.require, "Stadium")
    out[#out + 1] = ("3D-BTL staged: %s, rung: %s"):format(
      tostring(okO and OB and OB.arenaInfo and OB.arenaInfo() ~= nil),
      tostring(okS and St and St.mode and St.mode() or "none"))
    -- 3D-3D: which source each side's model came from (ChainBattleMon)
    pcall(function()
      local parts = {}
      for _, side in ipairs({ "player", "enemy" }) do
        local mon = St.sideMon(side)
        if mon then
          local src = mon.modelSource and mon:modelSource() or "-"
          parts[#parts + 1] = ("%s dex %s -> %s"):format(side, tostring(mon.species), tostring(src or "pic"))
        end
      end
      if #parts > 0 then out[#out + 1] = "3D-3D models: " .. table.concat(parts, ", ") end
    end)
    pcall(function()
      local Ar = V.require("ORASArenas")
      if Ar.active() then
        local info = okO and OB.arenaInfo and OB.arenaInfo()
        out[#out + 1] = ("ORAS ARENA: row %s, stage %s, auto picked because: %s"):format(
          tostring(Ar.choice()), tostring(type(info) == "table" and info._oras or "-"), tostring(Ar.lastPickWhy))
      end
    end)
    V.require("ORASEffectsPlayer").report(out)
  end)
  pcall(function() V.require("ORASBattleTrainers").report(out) end)
  pcall(function() V.require("ORASOverworldNPCs").report(out) end)
  pcall(function()
    local perf = V.mod and V.mod.exports and V.mod.exports.modernUiPerf
    if perf then out[#out + 1] = ""; perf.report(out) end
  end)
  out[#out + 1] = ""
  local okA, errA = pcall(describeActors, A, out)
  if not okA then out[#out + 1] = "actor listing failed: " .. tostring(errA) end

  -- ROM-side breakdown, once per ORAS species on screen
  local okC, Cache = pcall(V.require, "ORASActorCache")
  local seen = {}
  for _, rec in pairs(A._liveActors or {}) do
    local dex = tonumber(rec.dex)
    if dex and not seen[dex] and rec.scene and rec.scene.source == "ORAS" then
      seen[dex] = true
      out[#out + 1] = ""
      out[#out + 1] = ("ORAS ROM BREAKDOWN dex %d"):format(dex)
      if okC and Cache and Cache.inspect then
        local okI, text, why = pcall(Cache.inspect, V.mod, dex, function(name, img)
          local okE, fd = pcall(img.encode, img, "png")
          if okE and fd then writeFile(dir .. "/" .. name, fd:getString()) end
        end)
        out[#out + 1] = okI and (text or ("  failed: " .. tostring(why))) or ("  error: " .. tostring(text))
      else
        out[#out + 1] = "  ORASActorCache unavailable: " .. tostring(Cache)
      end
    end
  end
  startTrace()
end

function D.frame()
  if not state then return end
  state.frames = state.frames + 1
  -- polled several times a frame on some paths: close after a full frame
  -- has certainly passed (60 ms > three 60 Hz frames)
  local t = love.timer and love.timer.getTime() or 0
  if state.frames >= 3 and t - state.t0 >= 0.06 then pcall(finish) end
end

function D.install()
  _G.__terrariumRenderDump = D
  return D
end

return D
