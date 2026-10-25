-- Caches the live voxel FIELD (ChunkMesher pocket + BattleArena marks) at
-- battle start so Colosseum Battle Environments' OVERWORLD entry can stage
-- the fight on the same 3D ground OverworldBattle uses -- not a PNG blit of
-- the last overworld frame (which included the player sprite).
--
-- CBE still owns camera, actors, crowd and move FX. This module only holds
-- the map pocket and draws its terrain into the already-bound arena canvas
-- (Voxel3D.beginScene slot "current").
--
-- GEN 4 (Platinum): there is no voxel field -- the world is the cartridge's own
-- 3D terrain. capture() still caches the pocket; draw() then renders the native
-- world through CBE's own camera pose (Gen4WorldHost.renderPose) and keeps the
-- colour, and blit() lays it into the arena canvas once Arena.lua has rebound
-- it. Actors keep projecting through the pose, which the world was drawn with,
-- so they stand on the real ground. See nativeWorld() / blit() below.
local V = ...
local M = {}

local field = nil

-- GEN 4 cost knobs. Every arena frame used to re-render the whole native world
-- (all Gen4Bridge effects included) at window-pixel size. Now:
--   WORLD_SCALE  fraction of the arena canvas the world is rendered at (the blit
--                scales it back up). 1 = full size (the default). 0.5 = a quarter
--                of the pixels. The engine's fov helper takes the canvas height,
--                so a smaller canvas may change the world's perspective against
--                the actors. If you try < 1, watch the log for "FOV mismatch" and
--                check the Pokemon still sit on the ground.
--   REFRESH      seconds a rendered world is reused while the camera has not
--                moved. 0 = render every frame (old behaviour); math.huge = only
--                when the camera moves (water / wind / sky freeze meanwhile).
--   POSE_EPS     world units / radians the arena pose may drift before the
--                cached world is thrown away. At ~20 px per unit, 0.05 is ~1 px,
--                so the actors cannot visibly slide against a reused world.
--   HOLD_DRIFT   hold BattleCam's slow parallax drift still on a native world.
--                The drift moves the pose ~0.014 units a frame, so it crossed
--                POSE_EPS every ~4 frames and forced a full world re-render
--                about 15 times a second. Gen 1-3 voxel fields never read this.
--   SUPERSAMPLE  false renders the arena world at the engine's 1x target even
--                when the player's Gen 4 RENDER SCALE row supersamples walking.
--
-- Each knob left nil here takes its value from the device tier below. Set
-- one (e.g. M.WORLD_SCALE = 1) to override the tier on every device.
M.WORLD_SCALE = nil
M.REFRESH = nil
M.HOLD_DRIFT = nil
M.SUPERSAMPLE = nil
M.POSE_EPS = 0.05
M.POSE_EPS_FOV = 0.0005
M.LOG_STATS = true
M.STATS_EVERY = 5      -- seconds between running-total log lines during a fight
-- A world render that FAILS used to be retried every frame -- a full Sinnoh
-- pass per frame, all thrown away. Now a failure waits FAIL_RETRY seconds
-- (doubling per consecutive failure, capped at FAIL_RETRY_MAX) before trying
-- again. The arena draws its backdrop meanwhile.
M.FAIL_RETRY = 0.5
M.FAIL_RETRY_MAX = 4
-- While Gen4Budget is still building meshes for the arena window (grass,
-- sand, trees arriving over the first frames), a reused world would freeze a
-- half-built picture. Until the builds stop, the refresh is at most this.
M.WARM_REFRESH = 0.25

-- Device tiers. "mobile" is Android/iOS. A phone pays for every world render
-- in fill on a tiler, so it renders the world at 3/4 size (1280x720 arena ->
-- 960x540 world, scaled back up) and only re-renders when the camera moves
-- (water and wind hold still between moves). Desktop keeps full size and a
-- 4 Hz refresh so animated water still moves. Safe to shrink: renderPose
-- draws in "third" mode, whose fov does not depend on the canvas height, so
-- the actors still sit on the ground.
--   MOTION_SCALE  while the camera is moving (a drag, a zoom), the world is
--                 rendered at this fraction of WORLD_SCALE; one full-size render
--                 follows as soon as it stops. The eye cannot read detail in a
--                 moving picture, but it does feel every dropped frame.
--   MOTION_EVERY  while moving, render the world on one frame in this many and
--                 keep the last picture between (actors still move every frame).
M.TIERS = {
  desktop = { WORLD_SCALE = 1, REFRESH = 0.25, HOLD_DRIFT = true, SUPERSAMPLE = true,
              MOTION_SCALE = 1, MOTION_EVERY = 1 },
  mobile = { WORLD_SCALE = 0.75, REFRESH = math.huge, HOLD_DRIFT = true, SUPERSAMPLE = false,
             MOTION_SCALE = 0.5, MOTION_EVERY = 2 },
}
M.MOTION_SCALE = nil
M.MOTION_EVERY = nil
M.TIER = nil           -- nil = pick by OS; or "desktop" / "mobile" to force

local mobileOS = nil
local function isMobile()
  if mobileOS == nil then
    local ok, name = pcall(function() return love.system.getOS() end)
    mobileOS = ok and (name == "Android" or name == "iOS") or false
  end
  return mobileOS
end

function M.tierName()
  if M.TIER == "desktop" or M.TIER == "mobile" then return M.TIER end
  return isMobile() and "mobile" or "desktop"
end

-- A knob's live value: the module override when set, else the tier's.
local function knob(name)
  local v = M[name]
  if v ~= nil then return v end
  local t = M.TIERS[M.tierName()] or M.TIERS.desktop
  return t[name]
end
M.knob = knob

local function log(level, fmt, ...)
  local m = V.mod
  local l = m and m.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

local function voxel(name)
  if type(V.voxelRequire) == "function" then
    local ok, mod = pcall(V.voxelRequire, name)
    if ok then return mod end
  end
  return V[name]
end

local function engineReq(name)
  local req = V.engineRequire or require
  local ok, mod = pcall(req, name)
  if ok then return mod end
  return nil
end

-- This module runs in the Colosseum namespace, which has no V.require of its
-- own: main-mod modules are reached through voxel() (-> the main V.require).
local function gen4Host()
  local H = voxel("Gen4WorldHost")
  if type(H) == "table" then return H end
  return nil
end

-- True only when CBE is on and the player's selected arena is OVERWORLD.
-- Do not call ArenaCatalog.resolve here: that binds the battle, and capture
-- runs at pushBattle -- before battle.started's releaseBattle / re-acquire.
local function wantsSnapshot(battle)
  local ArenaCatalog = V.ArenaCatalog
  if not (ArenaCatalog and type(ArenaCatalog.enabled) == "function") then
    return false, "catalog missing"
  end
  local game = (battle and battle.game) or (V.mod and V.mod.game)
  local okEnabled, enabled = pcall(ArenaCatalog.enabled, game)
  if not (okEnabled and enabled) then return false, "cbe off" end
  local selected = "auto"
  if type(ArenaCatalog.selected) == "function" then
    local okSel, sel = pcall(ArenaCatalog.selected, game)
    if okSel and sel then selected = sel end
  end
  local def = type(ArenaCatalog.definition) == "function"
    and ArenaCatalog.definition(selected) or nil
  if type(def) == "table" and def.liveOverworld == true then
    return true, selected
  end
  return false, "arena=" .. tostring(selected)
end

local function overworldState(hint)
  if hint and hint.map and hint.player then return hint end
  local Game = engineReq("src.core.Game")
  return Game and Game.overworld or nil
end

-- Same map pocket OverworldBattle.stageFor uses on an A rung: authored or
-- searched cells, never the carried Stadium discs and never a BattleCanvas PNG.
local function findPocket(state, battle)
  local BattleArena = voxel("BattleArena")
  if not (BattleArena and type(BattleArena.find) == "function") then
    return nil, "BattleArena missing"
  end
  local map, player = state.map, state.player
  if not (map and player) then return nil, "no map/player" end
  local bt = battle and tostring(battle.battleType or ""):lower() or ""
  local surfing = (bt == "fish" or bt == "fishing")
    or (player.surfing == true)
  local ok, arena = pcall(BattleArena.find, map, player.cellX, player.cellY, surfing)
  if not (ok and arena) then return nil, "no pocket" end
  arena.surfing = surfing and true or false
  if surfing then arena.water = true end
  return arena
end

local function groundYFor(pocket)
  local BattleScene = voxel("BattleScene")
  local host = pocket.map
  if BattleScene and type(BattleScene.groundY) == "function" and host then
    local ok, y = pcall(BattleScene.groundY, host, pocket)
    if ok and y then return y end
  end
  return 0
end

function M.capture(battle, stateHint)
  local wanted, why = wantsSnapshot(battle)
  if not wanted then return false end
  local state = overworldState(stateHint)
  if not state then
    log("warn", "overworld arena field skipped: no overworld state")
    return false
  end
  -- A Gen 4 map is drawn by the engine's own 3D ground: nothing to voxelise.
  local Host = gen4Host()
  local native = Host ~= nil and type(Host.isState) == "function"
    and type(Host.renderPose) == "function" and Host.isState(state) and true or false
  local Voxel3D = V.Voxel3D or voxel("Voxel3D")
  if not native and not (Voxel3D and Voxel3D.available and Voxel3D.available()) then
    log("warn", "overworld arena field skipped: voxel unavailable")
    return false
  end
  local pocket, whyPocket = findPocket(state, battle)
  if not pocket then
    log("warn", "overworld arena field skipped: %s", tostring(whyPocket))
    return false
  end
  if native then
    -- The telephoto rig stands five tiles back, which on a Sinnoh interior is
    -- through a wall. Wide is the same composition at a distance a room holds
    -- (the same choice Gen4WorldHost.renderBattle makes for the 3D battles).
    if pocket.cam == nil then pocket.cam = "wide" end
  else
    local VoxelScene = voxel("VoxelScene")
    local ChunkMesher = voxel("ChunkMesher")
    if VoxelScene and type(VoxelScene.prefetch) == "function" then
      pcall(VoxelScene.prefetch, state)
    end
    if ChunkMesher and type(ChunkMesher.pump) == "function" then
      pcall(ChunkMesher.pump, true)
    end
  end
  local host = pocket.map or state.map
  field = {
    state = state,
    pocket = pocket,
    host = host,
    groundY = groundYFor(pocket),
    mapId = host and host.id or (state.map and state.map.id),
    gen4 = native or nil,
  }
  if native then
    local B = voxel("Gen4Bridge")
    local Budget = voxel("Gen4Budget")
    if Budget then
      if type(Budget.flushBurst) == "function" then pcall(Budget.flushBurst) end
      Budget.peakMs, Budget.peakKind = 0, nil
    end
    field.stats = { frames = 0, renders = 0, reuses = 0, ms = 0,
                    failures = 0, backoff = 0,
                    why = { first = 0, size = 0, refresh = 0, warm = 0, pose = 0, settle = 0 },
                    motionSkips = 0,
                    poseEye = 0, poseFocus = 0, poseFov = 0,
                    dtMax = 0, dt25 = 0, dt50 = 0, dt100 = 0,
                    build0 = Budget and tonumber(Budget.total) or 0,
                    buildMs0 = Budget and tonumber(Budget.totalMs) or 0,
                    dc = 0, cs = 0, ss = 0,
                    draws0 = (Host.stats and Host.stats.draws) or 0,
                    bridge0 = (B and B.stats and B.stats.runs) or 0,
                    pre0 = (B and B.stats and B.stats.pres) or 0 }
  end
  log("info", "overworld arena field cached map=%s pocket=%s@(%s,%s) (arena=%s%s)",
      tostring(field.mapId), tostring(pocket.shape),
      tostring(pocket.x), tostring(pocket.y), tostring(why),
      native and ", native Gen 4 world" or "")
  return true
end

function M.field()
  return field
end

-- One line per fight: how many arena frames there were, how many re-rendered the
-- world, and how many world passes the overworld itself still drew meanwhile.
-- overworldPerFrame ~1.0 means the real overworld is drawing underneath the arena.
local function logStats(label)
  local st = field and field.stats
  if not (M.LOG_STATS and st and st.frames > 0) then return end
  local Host = gen4Host()
  local own = Host and Host.stats and (Host.stats.draws - st.draws0) or 0
  log("info", "Gen4 arena world (" .. (label or "fight over") .. "): %d arena frames, %d world renders (%.0f%%), %d reused, "
      .. "%.2f ms avg render submit (CPU), %d overworld world passes during the fight "
      .. "(%.2f per arena frame), scale %.2f, refresh %.2fs",
      st.frames, st.renders, 100 * st.renders / st.frames, st.reuses,
      st.renders > 0 and st.ms / st.renders or 0, own, own / st.frames,
      tonumber(knob("WORLD_SCALE")) or 1, tonumber(knob("REFRESH")) or 0)
  do
    local w = st.why or {}
    local Budget = voxel("Gen4Budget")
    log("info", "Gen4 arena world (" .. (label or "fight over") .. "): camera-motion: %d frames kept the "
        .. "last world, %d full-size renders after the camera stopped", st.motionSkips or 0, w.settle or 0)
    log("info", "Gen4 arena world (" .. (label or "fight over") .. "): re-render reasons -- first %d, "
        .. "size %d, refresh %d, meshes-building %d, camera-moved %d (largest move: eye %.3f, focus %.3f, "
        .. "fov %.5f rad); frames: worst %.0f ms, %d over 25 ms, %d over 50 ms, %d over 100 ms; "
        .. "mesh builds this fight: %d, %.0f ms total, slowest %.0f ms (%s)",
        w.first or 0, w.size or 0, w.refresh or 0, w.warm or 0, w.pose or 0,
        st.poseEye or 0, st.poseFocus or 0, st.poseFov or 0,
        (st.dtMax or 0) * 1000, st.dt25 or 0, st.dt50 or 0, st.dt100 or 0,
        Budget and ((tonumber(Budget.total) or 0) - (st.build0 or 0)) or 0,
        Budget and ((tonumber(Budget.totalMs) or 0) - (st.buildMs0 or 0)) or 0,
        Budget and tonumber(Budget.peakMs) or 0, tostring(Budget and Budget.peakKind or "-"))
  end
  log("info", "Gen4 arena world (" .. (label or "fight over") .. "): tier %s, %d failed renders, "
      .. "%d frames skipped by the retry backoff, drift held %s",
      M.tierName(), st.failures or 0, st.backoff or 0,
      tostring(knob("HOLD_DRIFT") and true or false))
  local tag = "Gen4 arena world (" .. (label or "fight over") .. "): "
  -- Is any effect pass running more often than there are world passes?
  local B = voxel("Gen4Bridge")
  if B and B.stats then
    local runs, pres = B.stats.runs - (st.bridge0 or 0), B.stats.pres - (st.pre0 or 0)
    local passes = st.renders + own
    log("info", tag .. "Gen4Bridge.run x%d and sky pre-pass x%d for %d world passes (%d arena renders + %d overworld)"
        .. " -- anything well above %d means a pass is running twice", runs, pres, passes, st.renders, own, passes)
  end
  -- What a world render costs LÖVE, and whether GPU resources are growing.
  if st.renders > 0 and st.tex then
    local mb = 1024 * 1024
    log("info", tag .. "a world render costs %.0f draw calls, %.1f canvas switches, %.1f shader switches; "
        .. "GPU textures %.1f MB (first render %.1f MB), canvases %d (first %d), images %d (first %d)",
        st.dc / st.renders, st.cs / st.renders, st.ss / st.renders,
        st.tex / mb, (st.tex0 or st.tex) / mb, st.cv or 0, st.cv0 or 0, st.im or 0, st.im0 or 0)
  end
end

-- What the engine's stack will draw under the arena. visibleBase is the lowest
-- state the stack draws; if the overworld sits at or above it, the overworld is
-- still being drawn under the arena (a second full world pass for nothing).
local function logStack()
  if not M.LOG_STATS then return end
  local Game = engineReq("src.core.Game")
  local stack = Game and Game.stack
  local states = stack and stack.states
  if type(states) ~= "table" then
    log("info", "Gen4 arena stack: unavailable (no stack.states)")
    return
  end
  local base
  if type(stack.visibleBase) == "function" then
    local ok, v = pcall(stack.visibleBase, stack)
    if ok then base = tonumber(v) end
  end
  local ow, parts = nil, {}
  for i, s in ipairs(states) do
    if type(s) == "table" and s.isOverworld == true then ow = i end
  end
  for i = math.max(1, #states - 3), #states do
    local s = states[i]
    local flag = type(s) == "table" and s.isOpaque
    parts[#parts + 1] = string.format("[%d]%s%s", i,
      flag == true and "opaque" or (flag == false and "clear" or "?"),
      (type(s) == "table" and s.isOverworld == true) and "(overworld)" or "")
  end
  local under
  if base and ow then under = ow >= base end   -- not and/or: false must stay false
  log("info", "Gen4 arena stack: depth %d, visibleBase %s, %s -- overworld drawn under the arena: %s",
      #states, tostring(base), table.concat(parts, " "),
      under == nil and "unknown" or (under and "YES" or "no"))
end

function M.stats()
  return field and field.stats or nil
end

function M.clear()
  pcall(logStats)
  local wasGen4, endedOn = field and field.gen4, field and field.state
  field = nil
  if wasGen4 then
    local Host = gen4Host()
    if Host and type(Host.afterBattle) == "function" then
      pcall(Host.afterBattle, endedOn)
    end
  end
end

-- BattleCam pose in world pixels, so CBE's compositor and the voxel field
-- share one camera.
function M.cameraPose()
  if not (field and field.pocket) then return nil end
  local BattleCam = voxel("BattleCam")
  if not (BattleCam and type(BattleCam.rig) == "function") then return nil end
  -- A native world re-renders whenever the pose moves, so on Gen 4/5 the
  -- drift is held for this pose only (see HOLD_DRIFT). Steering, zoom and the
  -- free-look layer on top are untouched.
  local hold = field.gen4 and knob("HOLD_DRIFT") and true or false
  local held = BattleCam.holdDrift
  if hold then BattleCam.holdDrift = true end
  local ok, cam = pcall(BattleCam.rig, field.pocket, field.groundY or 0)
  BattleCam.holdDrift = held
  if not (ok and cam and cam.eye and cam.focus and cam.fov) then return nil end
  return cam
end

local function trainerBehind(pocket, side)
  local p, e = pocket.player, pocket.enemy
  if not (p and e) then return nil end
  local dx, dz = p[1] - e[1], p[2] - e[2]
  local len = math.sqrt(dx * dx + dz * dz)
  if len < 1e-3 then dx, dz, len = 0, 1, 1 end
  dx, dz = dx / len, dz / len
  local behind = 19.2  -- 20% closer (was 24)
  if side == "player" then
    return { p[1] + dx * behind, p[2] + dz * behind }
  end
  return { e[1] - dx * behind, e[2] - dz * behind }
end

-- Rewrite CBE arena marks into world-pixel space so Pokemon/trainers stand
-- on the cached pocket instead of the generic stadium disc.
function M.applyTo(arena, def)
  if not (arena and field and field.pocket) then return false end
  local pocket = field.pocket
  arena.liveField = true
  arena.mid = { pocket.mid[1], pocket.mid[2] }
  arena.groundY = field.groundY or 0
  arena.map = field.host
  arena.playerCell = pocket.playerCell
  arena.enemyCell = pocket.enemyCell
  local BattleCam = voxel("BattleCam")
  if BattleCam and type(BattleCam.rigFor) == "function" then
    arena.camera = BattleCam.rigFor(pocket)
  end
  local profile = {
    pokemon = { player = pocket.player, enemy = pocket.enemy },
    trainers = {
      player = trainerBehind(pocket, "player"),
      enemy = trainerBehind(pocket, "enemy"),
    },
    trainerScale = def and def.trainerScale,
  }
  if V.PlayerTrainer and type(V.PlayerTrainer.setArenaProfile) == "function" then
    pcall(V.PlayerTrainer.setArenaProfile, V.PlayerTrainer, profile)
  end
  if V.Trainer and type(V.Trainer.setArenaProfile) == "function" then
    pcall(V.Trainer.setArenaProfile, V.Trainer, profile)
  end
  return true
end

local function paletteFor(state, home)
  local PaletteFX = engineReq("src.render.PaletteFX")
  if not (PaletteFX and state and type(state.paletteNameFor) == "function") then
    return function() return nil end
  end
  local Game = engineReq("src.core.Game")
  local data = Game and Game.data
  return function(map)
    return PaletteFX.pal(data, state:paletteNameFor(map or home))
  end
end

-- True while the cached field is a native Gen 4 world. Arena.lua asks this to
-- decide two things: keep the pose-built view-projection for the actors (there
-- is no Voxel3D.vp for this field, only a stale one from some earlier scene),
-- and call blit() once the arena canvas is rebound.
function M.nativeWorld()
  return field ~= nil and field.gen4 == true
end

-- love.graphics.getStats() deltas around a world render: draw calls, canvas and
-- shader switches, plus the running GPU texture / canvas / image counts.
local function gpuStats()
  local g = love and love.graphics
  if not (g and type(g.getStats) == "function") then return nil end
  local ok, t = pcall(g.getStats)
  if not (ok and type(t) == "table") then return nil end
  return { dc = tonumber(t.drawcalls) or 0, cs = tonumber(t.canvasswitches) or 0,
           ss = tonumber(t.shaderswitches) or 0, tex = tonumber(t.texturememory) or 0,
           cv = tonumber(t.canvases) or 0, im = tonumber(t.images) or 0 }
end

local function now()
  local t = love and love.timer and love.timer.getTime
  return t and t() or os.clock()
end

local function copyPose(p)
  return { eye = { p.eye[1], p.eye[2], p.eye[3] },
           focus = { p.focus[1], p.focus[2], p.focus[3] }, fov = p.fov }
end

-- Returns moved, plus the largest eye / focus / fov change (for the stats).
local function poseMoved(a, b)
  if not (a and b) then return true, 0, 0, 0 end
  local eps = tonumber(M.POSE_EPS) or 0.05
  local de, df = 0, 0
  for i = 1, 3 do
    de = math.max(de, math.abs((a.eye[i] or 0) - (b.eye[i] or 0)))
    df = math.max(df, math.abs((a.focus[i] or 0) - (b.focus[i] or 0)))
  end
  local dv = math.abs((a.fov or 0) - (b.fov or 0))
  return de > eps or df > eps or dv > (tonumber(M.POSE_EPS_FOV) or 0.0005), de, df, dv
end

-- Render the native world through the arena pose, or reuse the last render.
-- A render is reused while: same size, the pose has not moved past POSE_EPS, and
-- less than REFRESH seconds have passed. field.worldColour keeps pointing at the
-- host's reused canvas, which nothing else writes between renders.
local function drawNative(w, h, pose)
  local st = field.stats
  if st then
    st.frames = st.frames + 1
    if st.frames == 1 then pcall(logStack) end
    -- A run that ends mid-fight (crash, closed window) never reaches clear();
    -- log the running totals every few seconds so the numbers survive.
    local tn = now()
    -- frame pacing, measured between arena frames (this runs once per frame)
    if field.frameAt then
      local fdt = tn - field.frameAt
      if fdt > (st.dtMax or 0) then st.dtMax = fdt end
      if fdt > 0.025 then st.dt25 = st.dt25 + 1 end
      if fdt > 0.050 then st.dt50 = st.dt50 + 1 end
      if fdt > 0.100 then st.dt100 = st.dt100 + 1 end
    end
    field.frameAt = tn
    field.statAt = field.statAt or tn
    if tn - field.statAt >= (tonumber(M.STATS_EVERY) or 5) then
      field.statAt = tn
      pcall(logStats, "so far")
    end
  end
  local Host = gen4Host()
  if not (Host and type(Host.renderPose) == "function") then
    field.worldColour = nil
    return false
  end
  local cam = pose
  if not (cam and cam.eye and cam.focus and cam.fov) then
    cam = M.cameraPose()
  end
  if not cam then
    field.worldColour = nil
    log("warn", "native arena world skipped: no camera pose")
    return false
  end

  -- is the camera moving RIGHT NOW (since last frame, not since the last render)?
  local camMoving = field.prevPose ~= nil and poseMoved(field.prevPose, cam) or false
  field.prevPose = copyPose(cam)
  local motionEvery = math.max(1, math.floor(tonumber(knob("MOTION_EVERY")) or 1))
  if camMoving and field.worldColour and motionEvery > 1 then
    field.motionFrame = (field.motionFrame or 0) + 1
    if field.motionFrame % motionEvery ~= 0 then
      if st then st.motionSkips = (st.motionSkips or 0) + 1 end
      return true                 -- keep last frame's world for this frame
    end
  end
  local lowRes = false
  local scale = tonumber(knob("WORLD_SCALE")) or 1
  local motionScale = tonumber(knob("MOTION_SCALE")) or 1
  if camMoving and motionScale < 1 then
    scale = scale * motionScale
    lowRes = true
  end
  if scale < 0.25 then scale = 0.25 elseif scale > 1 then scale = 1 end
  local rw = math.max(2, math.floor(w * scale + 0.5))
  local rh = math.max(2, math.floor(h * scale + 0.5))

  local t0 = now()
  local refresh = tonumber(knob("REFRESH")) or 0
  -- meshes still arriving: do not freeze a half-built window
  local Budget = voxel("Gen4Budget")
  local builds = Budget and tonumber(Budget.total) or nil
  if builds and builds ~= field.worldBuilds then
    refresh = math.min(refresh, tonumber(M.WARM_REFRESH) or 0.25)
  end
  local moved, de, df, dv = poseMoved(field.worldPose, cam)
  local sameSize = field.worldSize and field.worldSize[1] == rw and field.worldSize[2] == rh
  local fresh = (t0 - (field.worldAt or -math.huge)) < refresh
  -- a low-resolution motion picture is never kept once the camera settles
  local settle = field.worldLowRes and not lowRes
  if refresh > 0 and field.worldColour and sameSize and fresh and not moved and not settle then
    if st then st.reuses = st.reuses + 1 end
    return true
  end
  -- why this frame is about to pay for a world render (stats only)
  local reason
  if not field.worldColour then reason = "first"
  elseif settle then reason = "settle"
  elseif not sameSize then reason = "size"
  elseif moved then reason = "pose"
  elseif refresh < (tonumber(knob("REFRESH")) or 0) then reason = "warm"
  else reason = "refresh" end

  -- back off after a failure instead of paying for a full world pass that
  -- will be thrown away again on the very next frame
  if field.failUntil and t0 < field.failUntil then
    if st then st.backoff = (st.backoff or 0) + 1 end
    return false
  end

  if st and st.why then
    st.why[reason] = (st.why[reason] or 0) + 1
    if reason == "pose" then
      if de > st.poseEye then st.poseEye = de end
      if df > st.poseFocus then st.poseFocus = df end
      if dv > st.poseFov then st.poseFov = dv end
    end
  end
  field.worldColour = nil
  local gpuBefore = gpuStats()
  local colour, whyNot = Host.renderPose(field.state, field.pocket, cam, rw, rh,
                                         { noSupersample = not knob("SUPERSAMPLE") })
  local gpuAfter = gpuStats()
  if not colour then
    field.failCount = (field.failCount or 0) + 1
    local wait = (tonumber(M.FAIL_RETRY) or 0.5) * 2 ^ math.min(field.failCount - 1, 6)
    field.failUntil = now() + math.min(wait, tonumber(M.FAIL_RETRY_MAX) or 4)
    if st then st.failures = (st.failures or 0) + 1 end
    if field.warned ~= whyNot then
      field.warned = whyNot
      log("warn", "native arena world not drawn: %s (retrying with backoff)",
          tostring(whyNot))
    end
    return false
  end
  field.failCount, field.failUntil = 0, nil
  field.worldLowRes = lowRes
  field.worldBuilds = builds
  field.worldColour = colour
  local lf = Host.lastFov
  if lf and lf.eff and lf.want and math.abs(lf.eff - lf.want) > 0.05 and not field.fovWarned then
    field.fovWarned = true
    log("warn", "arena world FOV mismatch: the world draws at %.2f deg (effectiveFovY at "
        .. "height %d) but the actors project at %.2f deg -- Pokemon will not sit on the "
        .. "ground; set ArenaOverworldSnapshot.WORLD_SCALE = 1", lf.eff, lf.h or 0, lf.want)
  end
  field.worldPose = copyPose(cam)
  field.worldSize = { rw, rh }
  field.worldAt = t0
  if st then
    st.renders = st.renders + 1
    st.ms = st.ms + (now() - t0) * 1000
    if gpuBefore and gpuAfter then
      st.dc = st.dc + (gpuAfter.dc - gpuBefore.dc)
      st.cs = st.cs + (gpuAfter.cs - gpuBefore.cs)
      st.ss = st.ss + (gpuAfter.ss - gpuBefore.ss)
      st.tex0, st.cv0, st.im0 = st.tex0 or gpuBefore.tex, st.cv0 or gpuBefore.cv, st.im0 or gpuBefore.im
      st.tex, st.cv, st.im = gpuAfter.tex, gpuAfter.cv, gpuAfter.im
    end
  end
  return true
end

-- Lay the native world into the arena canvas. Called by Arena.lua AFTER it has
-- rebound its own colour+depth target, because rendering the world binds the
-- engine's canvases and leaves the arena unbound. Colour only: the engine's
-- depth buffer is a different attachment (and on desktop was often the SAME
-- internal buffer as the arena, which made Colosseum models flicker). Actors
-- then sit in front of the world and only test against each other.
function M.blit(w, h)
  if not (field and field.gen4 and field.worldColour) then return false end
  local g = love and love.graphics
  if not g then return false end
  local src = field.worldColour
  local prevShader = g.getShader()
  local blendMode, alphaMode = g.getBlendMode()
  local depthCmp, depthWrite
  if g.getDepthMode then depthCmp, depthWrite = g.getDepthMode() end
  local ok = pcall(function()
    g.setShader()
    if g.setDepthMode then g.setDepthMode("always", false) end
    -- Replace, not premultiplied: Gen4 shaders often write RGB with alpha 0
    -- on desktop GL, and premultiplied then lets the arena show through the
    -- snapshot (and through discarded model texels) every other frame.
    g.setBlendMode("replace")
    g.setColor(1, 1, 1, 1)
    local sw = src.getWidth and src:getWidth() or w
    local sh = src.getHeight and src:getHeight() or h
    g.draw(src, 0, 0, 0, w / sw, h / sh)
  end)
  pcall(g.setBlendMode, blendMode, alphaMode)
  pcall(g.setShader, prevShader)
  if g.setDepthMode then
    if depthCmp then pcall(g.setDepthMode, depthCmp, depthWrite)
    else pcall(g.setDepthMode) end
  end
  return ok
end

-- Draw cached voxel terrain into the currently bound CBE arena framebuffer.
-- Caller owns clear/sky; this only submits field meshes with the CBE pose.
function M.draw(w, h, pose)
  if not (field and field.pocket and field.state) then return false end
  if field.gen4 then return drawNative(w, h, pose) end
  local Voxel3D = V.Voxel3D or voxel("Voxel3D")
  local VoxelScene = voxel("VoxelScene")
  local ChunkMesher = voxel("ChunkMesher")
  local TerrainAtlas = voxel("TerrainAtlas")
  local Mat4 = V.Mat4 or voxel("Mat4")
  if not (Voxel3D and VoxelScene and ChunkMesher and TerrainAtlas
      and type(Voxel3D.beginScene) == "function") then
    return false
  end
  local state = overworldState(field.state) or field.state
  local pocket = field.pocket
  local host = pocket.map or field.host or state.map
  if not host then return false end
  if ChunkMesher.pump then pcall(ChunkMesher.pump, true) end

  local Map = engineReq("src.world.Map")
  local outdoor = host.def and Map and Map.isOutdoor and Map.isOutdoor(host.def) or false
  local DayNight = voxel("DayNight")
  if DayNight then
    if type(DayNight.applyRig) == "function" then pcall(DayNight.applyRig, outdoor) end
    if type(DayNight.tint) == "function" then
      Voxel3D.tint = DayNight.tint(outdoor or (DayNight.isCanopy and DayNight.isCanopy(host)))
    end
    if type(DayNight.lampColor) == "function" then Voxel3D.lampColor = DayNight.lampColor() end
    if type(DayNight.windowLight) == "function" then Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0 end
  end
  Voxel3D.skyAmount = outdoor and 1 or 0
  Voxel3D.glassGlint = 0
  Voxel3D.lampLights = nil
  Voxel3D.lampFlicker = 0
  local GlassMask = voxel("GlassMask")
  if outdoor and GlassMask and type(GlassMask.texture) == "function" then
    Voxel3D.glassMask = GlassMask.texture(host.tileset)
  else
    Voxel3D.glassMask = nil
  end
  local ForestAtmos = voxel("ForestAtmos")
  if ForestAtmos and type(ForestAtmos.frame) == "function" then
    local atmos = ForestAtmos.frame(host)
    Voxel3D.fog = atmos and {
      color = atmos.fog.color,
      density = atmos.fog.density * 0.5,
      start = atmos.fog.start,
      heightK = atmos.fog.heightK,
    } or nil
  end

  local neighbors = (host == state.map) and (state.neighbors or {}) or {}
  local Host = voxel("Gen4WorldHost")
  local terrain, nbMesh
  if VoxelScene and VoxelScene.prefetch then
    terrain, nbMesh = VoxelScene.prefetch(state)
  end
  if host ~= state.map and ChunkMesher then
    terrain = ChunkMesher.peek(host, false) or ChunkMesher.peek(host, true) or terrain
    nbMesh = nbMesh or {}
  end
  if not terrain then
    if Host and Host.isMap and Host.isMap(host) and Host.renderBattle then
      local okShot, shot = pcall(Host.renderBattle, state, pocket)
      if okShot and shot and shot.canvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(shot.canvas, 0, 0)
        return true
      end
    end
    return false
  end

  local water = ChunkMesher.pair and select(2, ChunkMesher.pair(host, false))
  if not water and ChunkMesher.pair then
    water = select(2, ChunkMesher.pair(host, true))
  end

  local pal = paletteFor(state, host)
  local function atlasFor(map)
    return TerrainAtlas.forMap(map, VoxelScene._modeColors(pal, map))
  end

  local cam = pose
  if not (cam and cam.eye and cam.focus and cam.fov) then
    cam = M.cameraPose()
  end
  if not cam then return false end

  local BattleCam = voxel("BattleCam")
  local cx, cy = pocket.mid[1], pocket.mid[2]
  local vh = (BattleCam and BattleCam.frameH and BattleCam.frameH(pocket)) or 34
  local vw = vh * (w / math.max(1, h))

  local prevCam = Voxel3D.camera
  Voxel3D.camera = cam
  local ok = pcall(function()
    if not Voxel3D.beginScene(w, h, cx, cy, vw, vh, nil, "current") then
      return
    end
    Voxel3D.drawGroup(terrain, atlasFor(host), nil, nil, nil, nil)
    for i, nb in ipairs(neighbors) do
      if nbMesh and nbMesh[i] and nb.map then
        local model = Mat4 and Mat4.translate and Mat4.translate(nb.ox, 0, nb.oy) or nil
        Voxel3D.drawGroup(nbMesh[i], atlasFor(nb.map), model, nil, nil, nil)
      end
    end
    if water then Voxel3D.draw(water, atlasFor(host)) end
    local Wind = voxel("Wind")
    local sway = (Wind and Wind.amount and Wind.amount()) or 0
    -- Overworld walking pulls Grass3D camera-ward so tufts overdraw feet
    -- (the GB grass-over-sprite trick). CBE overworld-arena fights are not
    -- that mode: Pokemon/trainers draw after this pass into the same depth
    -- buffer, and a 6-20px pull puts every tuft nearer the lens than the
    -- actors, so grass wins the depth test and covers the whole fight.
    -- Plant the meadow at world depth (pull=0) and let actors sit on top.
    local grassTex = atlasFor(host)
    local Grass3D = voxel("Grass3D")
    if Grass3D and Grass3D.available and Grass3D.available() and Grass3D.texture then
      local gt = Grass3D.texture()
      if gt then grassTex = gt end
    end
    for _, b in ipairs(ChunkMesher.grass(host) or {}) do
      local model = Mat4 and Mat4.translate and Mat4.translate(0, b.y, 0) or nil
      Voxel3D.draw(b.mesh, grassTex, model, 0, nil, sway)
    end
    for _, nb in ipairs(neighbors) do
      for _, b in ipairs(ChunkMesher.grass(nb.map) or {}) do
        local model = Mat4 and Mat4.translate and Mat4.translate(nb.ox, b.y, nb.oy) or nil
        Voxel3D.draw(b.mesh, grassTex, model, 0, nil, sway)
      end
    end
    Voxel3D.endScene()
  end)
  Voxel3D.camera = prevCam
  if not ok then
    pcall(Voxel3D.endScene)
    return false
  end
  return true
end

-- Kept so older Arena.lua backdrop code does not error. Always empty: the
-- field is 3D geometry, not a still of the player.
function M.image()
  return nil, 0, 0
end

function M.install()
  local req = V.engineRequire or require
  local ok, OverworldState = pcall(req, "src.world.OverworldController")
  if not (ok and OverworldState) then
    log("warn", "overworld arena field hook not installed: OverworldController unavailable")
    return false
  end
  if OverworldState.cbeOverworldSnapshotHook then return true end
  local inner = OverworldState.pushBattle
  function OverworldState:pushBattle(battle)
    pcall(M.capture, battle, self)
    return inner(self, battle)
  end
  OverworldState.cbeOverworldSnapshotHook = true
  log("info", "overworld arena field hook installed on OverworldState.pushBattle")
  return true
end

return M
