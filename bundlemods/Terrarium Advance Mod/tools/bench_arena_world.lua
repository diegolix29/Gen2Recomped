-- Colosseum OVERWORLD arena on a native Gen 4/5 world: how many full world
-- renders a fight asks for, per second, under each policy. Headless: LOVE and
-- the engine are stubbed, the real lib/ArenaOverworldSnapshot.lua and
-- lib/BattleCam.lua are loaded, and Gen4WorldHost.renderPose is a counter.
--
--   lua tools/bench_arena_world.lua [old_snapshot.lua] [old_battlecam.lua]
--   (run from the mod root; LuaJIT or Lua 5.1+)
--
-- The two optional paths are older copies of the modules to compare against
-- (e.g. `git show HEAD:<path> > old.lua`). Without them only the new policy
-- is measured.
--
-- The "est ms/s" column multiplies renders by an ASSUMED cost per world render
-- (RENDER_MS below). Those numbers are placeholders, not measurements: the
-- real cost has to be read off a device (the fight-over log line reports
-- "ms avg render submit"). The counts are exact for the stubbed scene.

local OLD_SNAPSHOT = arg and arg[1]
local OLD_BATTLECAM = arg and arg[2]
local NEW_SNAPSHOT = "lib/ArenaOverworldSnapshot.lua"
local NEW_BATTLECAM = "lib/BattleCam.lua"

local RENDER_MS = { Windows = 9, Android = 35 }   -- assumed, see header

local clockT = 0
local osName = "Windows"
love = {
  timer = { getTime = function() return clockT end },
  system = { getOS = function() return osName end },
}

local function loadMod(path, V)
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a"); f:close()
  local chunk = assert((loadstring or _G.load)(src, "@" .. path))
  return chunk(V)
end

local quiet = { info = function() end, warn = function() end, debug = function() end,
                error = function() end }

-- One fight: `seconds` of frames at `fps`. opts.fail makes every render fail;
-- opts.buildFor keeps Gen4Budget building for that many seconds; opts.steerFor
-- moves the player's orbit for that many seconds from t=2.
local function fight(snapshotPath, camPath, opts)
  clockT = 0
  osName = opts.os or "Windows"
  local renders, attempts = 0, 0
  local Budget = { total = 0 }
  local Host = {
    stats = { draws = 0 },
    isState = function() return true end,
    renderPose = function(state, pocket, cam, w, h)
      attempts = attempts + 1
      if opts.fail then return nil, "could not copy the world's colour" end
      renders = renders + 1
      return { getWidth = function() return w end, getHeight = function() return h end }
    end,
  }
  local mods = {}
  local V = {
    mod = { log = quiet },
    ArenaCatalog = {
      enabled = function() return true end,
      selected = function() return "overworld" end,
      definition = function() return { liveOverworld = true } end,
    },
    voxelRequire = function(name) return mods[name] end,
  }
  local BattleCam = loadMod(camPath, V)
  mods.BattleCam = BattleCam
  mods.Gen4WorldHost = Host
  mods.Gen4Budget = Budget
  mods.BattleArena = { find = function()
    return { mid = { 840, 270 }, player = { 800, 300 }, enemy = { 880, 240 },
             playerCell = { 50, 18 }, enemyCell = { 55, 15 }, shape = "wide", x = 53, y = 17 }
  end }
  mods.BattleScene = { groundY = function() return 0 end }
  local Snap = loadMod(snapshotPath, V)
  assert(Snap.capture({ game = {} }, { map = { id = "R201" }, player = { cellX = 53, cellY = 17 } }),
         "capture refused")
  BattleCam.reset()

  local dt = 1 / (opts.fps or 60)
  local frames = math.floor((opts.seconds or 10) / dt + 0.5)
  for _ = 1, frames do
    clockT = clockT + dt
    if opts.buildFor and clockT < opts.buildFor then Budget.total = Budget.total + 1 end
    if opts.steerFor and clockT >= 2 and clockT < 2 + opts.steerFor then
      BattleCam.orbitGoal = math.min(1, BattleCam.orbitGoal + dt * 0.5)
    end
    BattleCam.update(dt)
    Snap.draw(1280, 720, Snap.cameraPose())
  end
  local secs = frames * dt
  return { renders = renders, attempts = attempts, perSec = attempts / secs,
           estMs = attempts / secs * (RENDER_MS[osName] or 10) }
end

local rows = {}
local function row(label, r)
  rows[#rows + 1] = string.format("%-58s %6d %6d %8.1f %9.0f", label, r.attempts, r.renders,
                                  r.perSec, r.estMs)
end

if OLD_SNAPSHOT and OLD_BATTLECAM then
  row("OLD, as shipped (copy fails every frame), Windows 60fps",
      fight(OLD_SNAPSHOT, OLD_BATTLECAM, { fail = true }))
  row("OLD knobs, copy working, drift on, Windows 60fps",
      fight(OLD_SNAPSHOT, OLD_BATTLECAM, {}))
  row("OLD, as shipped, Android 30fps",
      fight(OLD_SNAPSHOT, OLD_BATTLECAM, { fail = true, os = "Android", fps = 30 }))
end
row("NEW desktop tier, Windows 60fps", fight(NEW_SNAPSHOT, NEW_BATTLECAM, {}))
row("NEW desktop tier, meshes building first 2s",
    fight(NEW_SNAPSHOT, NEW_BATTLECAM, { buildFor = 2 }))
row("NEW mobile tier, Android 30fps", fight(NEW_SNAPSHOT, NEW_BATTLECAM, { os = "Android", fps = 30 }))
row("NEW mobile tier, meshes building first 2s",
    fight(NEW_SNAPSHOT, NEW_BATTLECAM, { os = "Android", fps = 30, buildFor = 2 }))
row("NEW mobile tier, player steers camera for 1s",
    fight(NEW_SNAPSHOT, NEW_BATTLECAM, { os = "Android", fps = 30, steerFor = 1 }))
row("NEW, render keeps failing (backoff), Windows 60fps",
    fight(NEW_SNAPSHOT, NEW_BATTLECAM, { fail = true }))

print(string.format("%-58s %6s %6s %8s %9s", "10 s fight", "tries", "ok", "tries/s", "est ms/s"))
for _, r in ipairs(rows) do print(r) end

-- BattleCam parity: with holdDrift off the new rig must equal the old one
-- exactly, every frame -- Gen 1-3 shots read this path.
local failures = 0
if OLD_BATTLECAM then
  local Vb = { mod = { log = quiet } }
  local A, B = loadMod(OLD_BATTLECAM, Vb), loadMod(NEW_BATTLECAM, Vb)
  local arena = { mid = { 840, 270 }, cam = nil }
  local maxd = 0
  for _, cam in ipairs({ "tele", "wide" }) do
    arena.cam = cam
    A.reset(); B.reset()
    for i = 1, 3600 do
      A.update(1 / 60); B.update(1 / 60)
      if i % 600 == 0 then A.orbitGoal, B.orbitGoal = 0.4, 0.4 end
      local ca = A.rig(arena, 12); local cb = B.rig(arena, 12)
      for k = 1, 3 do
        maxd = math.max(maxd, math.abs(ca.eye[k] - cb.eye[k]), math.abs(ca.focus[k] - cb.focus[k]))
      end
      maxd = math.max(maxd, math.abs(ca.fov - cb.fov))
    end
  end
  print(string.format("BattleCam parity (holdDrift off, 2 rigs x 3600 frames): max diff %.3g -> %s",
                      maxd, maxd == 0 and "IDENTICAL" or "DIFFERENT"))
  if maxd ~= 0 then failures = failures + 1 end
end
-- and with holdDrift on, the pose must not move at all while nothing steers
do
  local B = loadMod(NEW_BATTLECAM, { mod = { log = quiet } })
  local arena = { mid = { 840, 270 } }
  B.reset(); B.holdDrift = true
  local first = B.rig(arena, 0)
  local moved = 0
  for _ = 1, 1800 do
    B.update(1 / 60)
    local c = B.rig(arena, 0)
    for k = 1, 3 do moved = math.max(moved, math.abs(c.eye[k] - first.eye[k])) end
  end
  print(string.format("BattleCam holdDrift on, 30 s: eye moved %.3g -> %s", moved,
                      moved == 0 and "STILL" or "MOVING"))
  if moved ~= 0 then failures = failures + 1 end
end
_G.__exitCode = failures > 0 and 1 or 0
if not _G.__runnerHost and failures > 0 then os.exit(1) end
