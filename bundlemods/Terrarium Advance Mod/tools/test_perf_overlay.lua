-- PerfOverlay headless test: stubbed LOVE, real lib/PerfOverlay.lua.
--   lua tools/test_perf_overlay.lua      (run from the mod root)
-- Feeds 6 s of frames (two hitches, some mesh builds, an arena fight) and
-- checks the lines the overlay would print.
local t, dt = 0, 1 / 60
local printed = {}
love = {
  timer = { getTime = function() return t end, getDelta = function() return dt end,
            getFPS = function() return 58 end },
  graphics = {
    getFont = function() return { getHeight = function() return 12 end,
                                  getWidth = function(_, s) return #s * 6 end } end,
    getDimensions = function() return 1280, 720 end,
    push = function() end, pop = function() end, setCanvas = function() end,
    origin = function() end, setShader = function() end, setScissor = function() end,
    setBlendMode = function() end, scale = function() end, setColor = function() end,
    rectangle = function() end,
    print = function(s) printed[#printed + 1] = s end,
    getStats = function() return { drawcalls = 455, canvasswitches = 4, shaderswitches = 146,
                                   texturememory = 217 * 1048576 } end,
  },
}
local Budget = {}
local Trees = { pendingLands = 3 }
local arena = { renders = 0, reuses = 0, motionSkips = 0 }
local V = {
  mod = { options = { get = function(_, k) return k == "perfOverlay" end },
          log = { warn = function(_, ...) print("WARN", ...) end } },
  require = function(name) if name == "Gen4Budget" then return Budget end
                           if name == "Gen4Trees" then return Trees end error("no " .. name) end,
  ArenaOverworldSnapshot = { stats = function() return arena end, nativeWorld = function() return true end,
                             tierName = function() return "mobile" end },
}
local f = assert(io.open("lib/PerfOverlay.lua", "rb")); local src = f:read("*a"); f:close()
local P = assert((loadstring or load)(src, "@lib/PerfOverlay.lua"))(V)

for frame = 1, 360 do
  dt = (frame == 200) and 0.093 or ((frame == 300) and 0.045 or 1 / 60)
  t = t + dt
  if frame % 10 == 0 and Budget.onCharge then Budget.onCharge(frame == 120 and "trees" or "grass", frame == 120 and 40 or 2) end
  arena.renders = arena.renders + (frame % 15 == 0 and 1 or 0)
  arena.reuses = arena.reuses + (frame % 15 == 0 and 0 or 1)
  printed = {}
  P.frame(0.006)
end

for _, s in ipairs(printed) do print(s) end
local all = table.concat(printed, "\n")
local fails = 0
local function check(cond, msg) if not cond then print("FAIL: " .. msg); fails = fails + 1 end end
check(all:find("FPS 58", 1, true), "FPS line")
check(all:find("worst %S+ ms %(1s%) 93%.0 ms %(10s%)"), "10 s worst frame is the 93 ms hitch")
check(all:find("2 frames > 33 ms, 1 > 50 ms", 1, true), "hitch counts")
check(all:find("gpu: 455 draws", 1, true), "gpu stats")
check(all:find("trees waiting: 3", 1, true), "trees waiting")
check(all:find("build ms, last 5s: grass", 1, true) or all:find("build ms, last 5s: trees", 1, true), "by-type line")
check(all:find("arena world: [45] renders/s"), "arena renders per second (one every 15 frames)")
check(all:find("tier mobile", 1, true), "tier")
check(all:find("log: %d+ lines/s"), "log cost line")

-- off: draws nothing and measures nothing
V.mod.options.get = function() return false end
P.forced = false
printed = {}
P.frame(0.006)
check(#printed == 0, "nothing drawn when off")

print(fails == 0 and "PASS" or ("FAILED " .. fails))
_G.__exitCode = fails > 0 and 1 or 0
if not _G.__runnerHost and fails > 0 then os.exit(1) end
