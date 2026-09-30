-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- DOES A SINNOH SESSION ACTUALLY USE THE PANEL IT FOUND?
--
-- Reported from play: "make sure platinum is detecting and using the second
-- screen properly if it exists within android".
--
-- Detection was never the problem. The options row has offered DEVICE only
-- when a panel is really attached since pass 138, and it was right to. What
-- was missing is smaller and worse: NOTHING EVER SEEDED THE OPTION. A nil fell
-- through to `swap`, so Platinum on an AYN Thor opened with the bottom screen
-- sharing the top one and the panel dark -- indistinguishable, from the sofa,
-- from a device that was never detected at all.
--
-- The second thing measured here is a cost rather than a fault: `mode` is
-- reached from nineteen places and the file transport re-read host.txt on
-- every one of them.
--
-- Usage: texlua tools/gen4_platinum_panel_check.lua

package.path = "./?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local CLOCK = 1000
local READS = { host = 0 }
local FILES = {}

love = {
  timer = { getTime = function() return CLOCK end },
  filesystem = {
    getInfo = function(path)
      local b = FILES[path]
      if not b then return nil end
      return { size = #b, modtime = 5, type = "file" }
    end,
    read = function(path)
      if path:find("host", 1, true) then READS.host = READS.host + 1 end
      return FILES[path]
    end,
    write = function(path, body) FILES[path] = body or "" return true end,
    createDirectory = function() return true end,
  },
  graphics = { getWidth = function() return 480 end,
               getHeight = function() return 320 end },
}

local Transport = require("src.render.SecondScreen")
local SecondScreen = require("src.ui.SecondScreen")
SecondScreen._setTransport(Transport)

local function host(displays)
  love.filesystem.write(Transport.HOST,
    ("%d %d 256 192\n"):format(Transport.PROTOCOL, displays))
  Transport.forgetFileProbe()
end
local function noHost()
  FILES[Transport.HOST] = nil
  Transport.forgetFileProbe()
end

-- A Sinnoh session, as `SecondScreen` sees one.
local function sinnoh(saved)
  return { data = { isGen4Cache = true },
           save = { options = { secondScreenMode = saved } } }
end

-- ---------------------------------------------------------------------------
section("1. with a panel attached, Platinum uses it out of the box")
-- ---------------------------------------------------------------------------
host(2)
ok(Transport.backend() == "file",
   "the file transport is not the active backend (%s)",
   tostring(Transport.backend()))
ok(SecondScreen.deviceReady() == true,
   "a host reporting two displays is not seen as ready")
do
  local g = sinnoh(nil)
  ok(SecondScreen.available(g) == true, "a Gen 4 session has no second screen")
  ok(SecondScreen.mode(g) == "display",
     "Platinum opened in %q with a panel attached, so the panel stays dark",
     SecondScreen.mode(g))
end

-- ---------------------------------------------------------------------------
section("2. with one screen, nothing changes")
-- ---------------------------------------------------------------------------
host(1)
do
  local g = sinnoh(nil)
  ok(SecondScreen.deviceReady() == false, "one display reported as ready")
  ok(SecondScreen.mode(g) == "swap",
     "on a one-screen device Platinum defaults to %q, not \"swap\"",
     SecondScreen.mode(g))
end
noHost()
do
  local g = sinnoh(nil)
  ok(SecondScreen.mode(g) == "swap",
     "with no host at all Platinum defaults to %q", SecondScreen.mode(g))
end

-- ---------------------------------------------------------------------------
section("3. it is a DEFAULT, not an override")
-- ---------------------------------------------------------------------------
-- The moment the player picks something it is written down, and the panel does
-- not get to overrule it on the next boot.
host(2)
for _, pick in ipairs({ "swap", "inset", "off", "display" }) do
  local g = sinnoh(pick)
  ok(SecondScreen.mode(g) == pick,
     "the player chose %q and got %q", pick, SecondScreen.mode(g))
end
-- ...and a saved `display` on a machine that has since lost its panel still
-- degrades to swap rather than to nothing, which is the pass-138 rule.
host(1)
do
  local g = sinnoh("display")
  ok(SecondScreen.mode(g) == "swap",
     "a saved DEVICE with no panel answers %q, not \"swap\"",
     SecondScreen.mode(g))
end
-- an unrecognised saved value is not a licence to take the panel either
host(2)
do
  local g = sinnoh("nonsense")
  ok(SecondScreen.mode(g) == "swap",
     "a corrupt saved mode answered %q", SecondScreen.mode(g))
end

-- ---------------------------------------------------------------------------
section("4. Gen 1, 2 and 3 are untouched, panel or no panel")
-- ---------------------------------------------------------------------------
-- THE CONTROL THAT MATTERS for "don't break crystal, gold silver or prism":
-- the default above is inside `mode`, which every generation reaches.
host(2)
do
  local g = { data = {}, save = { options = {} } }
  ok(SecondScreen.mode(g) == "off",
     "a Gen 1/2 session answers %q with a panel attached", SecondScreen.mode(g))
  local g3 = { data = { isGen3Cache = true }, save = { options = {} } }
  ok(SecondScreen.mode(g3) == "off",
     "a Gen 3 session answers %q with a panel attached", SecondScreen.mode(g3))
  -- and nothing about them changes when the option IS set, either
  local forced = { data = {}, save = { options = { secondScreenMode = "display" } } }
  ok(SecondScreen.mode(forced) == "off",
     "a Gen 1/2 session with DEVICE saved answers %q", SecondScreen.mode(forced))
end

-- ---------------------------------------------------------------------------
section("5. asking nineteen times a frame costs one read, not nineteen")
-- ---------------------------------------------------------------------------
host(2)
do
  local g = sinnoh(nil)
  READS.host = 0
  CLOCK = CLOCK + 10
  -- one frame's worth of call sites
  for _ = 1, 19 do SecondScreen.mode(g) end
  ok(READS.host <= 1,
     "one frame of `mode` calls read host.txt %d times", READS.host)
  ok(READS.host >= 1, "the host file was never read at all, so the cache "
     .. "cannot be answering from anything")
  -- ...AND THE CACHE STILL EXPIRES. A panel unplugged mid-session has to be
  -- noticed, or `display` keeps pushing frames into nothing.
  READS.host = 0
  CLOCK = CLOCK + Transport.PROBE_INTERVAL + 0.01
  SecondScreen.mode(g)
  ok(READS.host >= 1,
     "after PROBE_INTERVAL the host file was not re-read, so a panel that "
     .. "went away is never noticed")
  -- unplugged for real
  host(1)
  CLOCK = CLOCK + 10
  ok(SecondScreen.mode(g) == "swap",
     "the panel went away and Platinum still reports %q", SecondScreen.mode(g))
  -- ...and plugged back in
  host(2)
  CLOCK = CLOCK + 10
  ok(SecondScreen.mode(g) == "display",
     "the panel came back and Platinum reports %q", SecondScreen.mode(g))
end

-- ---------------------------------------------------------------------------
section("5b. forget() drops the file probe too, not just the native one")
-- ---------------------------------------------------------------------------
-- `forget` is the public "re-ask everything" door -- it existed for the native
-- probe alone, and a file-transport answer left cached behind it is a panel
-- state nothing can clear.
do
  host(2)
  CLOCK = CLOCK + 10
  ok(SecondScreen.deviceReady() == true, "the panel is not ready to begin with")
  -- move the host underneath the module WITHOUT touching the probe cache
  love.filesystem.write(Transport.HOST,
    ("%d 1 256 192\n"):format(Transport.PROTOCOL))
  ok(SecondScreen.deviceReady() == true,
     "the cache did not hold, so this cannot measure forget()")
  Transport.forget()
  ok(SecondScreen.deviceReady() == false,
     "forget() left the file transport still reporting a panel")
end

-- ---------------------------------------------------------------------------
section("6. a frame reaches the panel")
-- ---------------------------------------------------------------------------
-- End to end on the transport: a Sinnoh bottom screen, pushed, at the size the
-- host is written to read.
host(2)
do
  local W, H = 256, 192
  local body = string.rep("\7\8\9\255", W * H)
  local img = { body = body }
  function img:getString() return self.body end
  ok(Transport.push(img, W, H) == true, "a Sinnoh frame would not go out")
  local frame = FILES[Transport.FRAME]
  ok(type(frame) == "string" and #frame == 12 + W * H * 4,
     "the frame is %s bytes, not %d",
     type(frame) == "string" and #frame or "no", 12 + W * H * 4)
  ok(frame and frame:sub(1, 4) == "G2SD", "the frame carries the wrong magic")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
