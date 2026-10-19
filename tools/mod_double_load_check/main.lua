-- tools/mod_double_load_check/main.lua
--
-- DOES A MOD LOAD EXACTLY ONCE?  Driven through the REAL main.lua: the
-- launcher comes up, Play is pressed, the game boots, EXIT GAME goes back to
-- the launcher in process (HostShell.toLauncher -> main.lua returnToLauncher),
-- the launcher's backdrop boots its plain-game preview, and Play is pressed
-- again -- ROUNDS times.  Nothing here reimplements bootGame or the launcher.
--
-- Run by tools/mod_double_load_check/run.py, which builds each scenario in a
-- scratch folder (G:) and sets, per run:
--
--   ROOT       the project checkout (src/, assets/, ... are mounted from it;
--              its own mods/ is deliberately NOT, so a scenario decides
--              exactly which mods exist)
--   MODS_ROOT  a folder holding `mods/`, mounted appended -- the stand-in for
--              the game folder, i.e. the SECOND home love.filesystem reads
--              mods/ out of (the save directory is the first)
--   APPDATA    redirects LOVE's save directory (Windows) to scratch
--   IDENTITY   the save-directory name (conf.lua)
--   VERSION    the imported game to Play (its cache sits in the save dir)
--   ROUNDS     how many Play presses (default 2)
--   FAKE_OS    love.system.getOS() answer (Android: the phone code paths)
--   INSTALL    zip path(s) (`;`-separated) installed through
--              LauncherMods.installZip from the first launcher, as the
--              MODS > Import button does; INSTALL_REPLACE=1 passes replace
--   ENABLE     ids (`,`) switched on through LauncherMods.setEnabled first
--
-- Output: `RESULT <key> <value>` lines for run.py, plus the engine's log.
io.stdout:setvbuf("line")

local ROOT = assert(os.getenv("ROOT"), "set ROOT to the project checkout"):gsub("\\", "/")

-- ------- the read path: the engine's own folders, and one mods home
local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local function physMount(dir, point)
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(dir, point, 1) ~= 0 then return true end
    end
  end
  return false
end
for _, top in ipairs({ "src", "assets", "data", "translation", "lib", "legal" }) do
  physMount(ROOT .. "/" .. top, top)
end
if os.getenv("MODS_ROOT") and os.getenv("MODS_ROOT") ~= "" then
  print(("RESULT mods_root_mounted %s"):format(tostring(physMount(os.getenv("MODS_ROOT"), ""))))
end

-- NO NETWORK.  The launcher checks for updates and scrapes art, and a mod
-- under test may be untrusted third-party code: every child process and the
-- socket libraries are refused for the whole run.
do
  local function refused() return nil, "network and child processes are disabled in this check" end
  io.popen = function() return nil end
  os.execute = function() return false end
  for _, name in ipairs({ "socket", "socket.core", "socket.http", "socket.url",
                          "ssl", "ssl.https", "https", "luasocket" }) do
    package.preload[name] = function() error("disabled in mod_double_load_check: " .. name, 0) end
    package.loaded[name] = nil
  end
  _G.__DBL_REFUSED = refused
  -- worker threads have their own Lua state (and so their own io.popen):
  -- only the two that never touch the network are allowed to be real
  local newThread0 = love.thread.newThread
  love.thread.newThread = function(src, ...)
    if type(src) == "string" and (src:find("chip_worker", 1, true)
        or src:find("rom_import_worker", 1, true)) then
      return newThread0(src, ...)
    end
    return newThread0("local _ = ...\n")
  end
end

-- scripted runs must not stop on a "previous launch did not finish" report
local getenv0 = os.getenv
os.getenv = function(k)
  if k == "POKEPORT_NO_BOOT_REPORT" then return "1" end
  return getenv0(k)
end

if getenv0("FAKE_OS") then
  local fake = getenv0("FAKE_OS")
  love.system.getOS = function() return fake end
end

local VERSION = getenv0("VERSION") or "crystal"
local ROUNDS = tonumber(getenv0("ROUNDS") or "2")

-- ------- instrumentation (engine modules, wrapped from outside)
local R = { boots = {}, inits = {} }
_G.__DBL = R

local Loader = require("src.mods.Loader")
local loaders = {}
do
  local new0 = Loader.new
  Loader.new = function(opts)
    local l = new0(opts)
    loaders[#loaders + 1] = { loader = l, noMods = l.noMods == true }
    return l
  end
  local loadMod0 = Loader._loadMod
  Loader._loadMod = function(self, mod)
    R.entryRuns = R.entryRuns or {}
    local key = mod.manifest.id
    R.entryRuns[key] = (R.entryRuns[key] or 0) + 1
    return loadMod0(self, mod)
  end
end

local function report(tag)
  local Game = package.loaded["src.core.Game"]
  local l = loaders[#loaders] and loaders[#loaders].loader
  local noMods = 0
  for _, rec in ipairs(loaders) do if rec.noMods then noMods = noMods + 1 end end
  print(("RESULT %s.loaders %d"):format(tag, #loaders))
  print(("RESULT %s.loaders_nomods %d"):format(tag, noMods))
  if l then
    local ids = {}
    for _, m in ipairs(l.loaded or {}) do
      ids[#ids + 1] = ("%s@%s@%s"):format(m.manifest.id, m.manifest.version, m.path)
    end
    table.sort(ids)
    print(("RESULT %s.loaded %s"):format(tag, table.concat(ids, ",")))
    local states = {}
    for id, m in pairs(l.mods or {}) do states[#states + 1] = id .. "=" .. tostring(m.state) end
    table.sort(states)
    print(("RESULT %s.states %s"):format(tag, table.concat(states, ",")))
    print(("RESULT %s.errors %d"):format(tag, #(l.errors or {})))
    for _, e in ipairs(l.errors or {}) do print(("RESULT %s.error %s"):format(tag, tostring(e))) end
    local ignored = {}
    for _, c in ipairs(l.ignoredCopies or {}) do
      ignored[#ignored + 1] = ("%s@%s@%s"):format(tostring(c.id), tostring(c.version), tostring(c.path))
    end
    print(("RESULT %s.ignored %s"):format(tag, table.concat(ignored, ",")))
  end
  local runs = {}
  for id, n in pairs(R.entryRuns or {}) do runs[#runs + 1] = id .. "=" .. n end
  table.sort(runs)
  print(("RESULT %s.entry_runs %s"):format(tag, table.concat(runs, ",")))
  print(("RESULT %s.inits %d"):format(tag, #R.inits))
  print(("RESULT %s.init_list %s"):format(tag, table.concat(R.inits, ",")))
  -- how many probe wrappers sit on the one engine function the probe wraps,
  -- and which boot's closure the flag-guarded one belongs to
  R.unguarded, R.flagged = 0, {}
  local V = require("src.core.Version")
  pcall(V.title, "probe")
  print(("RESULT %s.unguarded_wraps %d"):format(tag, R.unguarded or 0))
  print(("RESULT %s.flagged_wrap_boots %s"):format(tag, table.concat(R.flagged or {}, ",")))
  print(("RESULT %s.mods_loaded_events %d"):format(tag, R.loadedEvents or 0))
  R.loadedEvents = 0
  print(("RESULT %s.game %s"):format(tag, tostring(Game and Game.mods ~= nil)))
  -- DUMP_SEAMS=1: every engine change the loaded mods made (src/mods/ModSeams)
  if getenv0("DUMP_SEAMS") == "1" then
    local okS, Seams = pcall(require, "src.mods.ModSeams")
    for _, e in ipairs(okS and Seams._journal or {}) do
      print(("RESULT %s.seam %s %s.%s %s->%s"):format(tag, tostring(e.owner),
        tostring(e.label), tostring(e.key), type(e.before), type(e.after)))
    end
  end
end

-- every RomImporter the real main.lua builds (the launcher, and the launcher
-- again after EXIT GAME)
local RI = require("src.import.RomImporter")
local importers = {}
-- THE CACHE IS NOT WHAT IS UNDER TEST.  A CACHE_FORMAT bump marks every
-- existing import "built by another version of this app", and the launcher
-- then offers to re-import instead of Play; the copy each scenario uses is
-- taken as ready so a format bump elsewhere does not stop a mods check.
do
  local report0 = RI.readyReport
  if report0 and getenv0("FORCE_READY") ~= "0" then
    RI.readyReport = function(version, ...)
      local r = report0(version, ...)
      if version == VERSION and type(r) == "table" and not r.ok
          and love.filesystem.getInfo(VERSION .. "/rom-cache.complete") then
        return { ok = true, missing = {}, gaps = {} }
      end
      return r
    end
  end
end
do
  local new0 = RI.new
  RI.new = function(...)
    local self = new0(...)
    importers[#importers + 1] = self
    return self
  end
end

-- ------- the real game
local chunk = assert(loadfile(ROOT .. "/main.lua"))
chunk()
local mainLoad, mainUpdate, mainDraw = love.load, love.update, love.draw

local step = "launcher"
local round = 0
local waitUntil = 0
local frames = 0

local function now() return love.timer.getTime() end

local function installs()
  local LM = require("src.mods.LauncherMods")
  for path in (getenv0("INSTALL") or ""):gmatch("[^;]+") do
    local ok, id, version = LM.installZip(path, { replace = getenv0("INSTALL_REPLACE") == "1" })
    print(("RESULT install %s -> %s %s %s"):format(path:match("[^/\\]+$"), tostring(ok), tostring(id), tostring(version)))
  end
  for id in (getenv0("ENABLE") or ""):gmatch("[^,]+") do
    LM.setEnabled(id, true)
    print(("RESULT enabled %s"):format(id))
  end
  local rows = {}
  for _, row in ipairs(LM.list() or {}) do
    rows[#rows + 1] = ("%s@%s:%s:%s"):format(row.id, tostring(row.version),
      row.enabled and "on" or "off", tostring(row.statusDetail))
  end
  print(("RESULT launcher.rows %s"):format(table.concat(rows, " | ")))
  local notes = {}
  for _, n in ipairs((LM.copiesReport and LM.copiesReport()) or {}) do notes[#notes + 1] = n end
  print(("RESULT launcher.copies %s"):format(table.concat(notes, " | ")))
end

function love.load(args)
  mainLoad(args or {})
  print(("RESULT launcher_up %s"):format(tostring(importers[1] ~= nil)))
  installs()
  waitUntil = now() + 1.2
end

function love.update(dt)
  frames = frames + 1
  local ok, err = pcall(mainUpdate, dt)
  if not ok then
    print("RESULT update_error " .. tostring(err))
    love.event.quit(1)
    return
  end
  if frames > 4000 then print("RESULT timeout true"); love.event.quit(1) return end
  if now() < waitUntil then return end
  if step == "launcher" then
    local imp = importers[#importers]
    round = round + 1
    if not (imp and imp.ready and imp.ready[VERSION]) then
      print(("RESULT not_ready %s"):format(VERSION))
      love.event.quit(1)
      return
    end
    -- the backdrop's preview, if it ran, is report-worthy before Play
    report(("round%d.launcher"):format(round))
    local okP, errP = pcall(imp.play, imp, VERSION)
    if not okP then
      print("RESULT play_error " .. tostring(errP))
      love.event.quit(1)
      return
    end
    report(("round%d.game"):format(round))
    step = "game"
    waitUntil = now() + 0.3
  elseif step == "game" then
    if round >= ROUNDS then
      print("RESULT done true")
      love.event.quit(0)
      return
    end
    require("src.core.HostShell").toLauncher()
    step = "launcher"
    waitUntil = now() + 1.2
  end
end

function love.draw()
  pcall(mainDraw)
end
