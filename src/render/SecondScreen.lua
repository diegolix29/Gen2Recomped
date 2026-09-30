-- Bridge to native secondary-display output (Android Presentation). The C
-- functions live in mobile/android/love/src/jni/love/src/common/android.cpp.
-- Everything is guarded: off Android, or if the symbols cannot be resolved,
-- this stays inert and the renderer keeps the in-window stacked layout.

local SecondScreen = {}
local C = nil

local function log(msg)
  pcall(function() require("src.core.Logger").info("SecondScreen: %s", msg) end)
end

do
  local ok, ffi = pcall(require, "ffi")
  if not (ok and ffi) then
    log("ffi unavailable (not LuaJIT); second display disabled")
  else
    pcall(ffi.cdef, [[
      int love_android_secondary_ready();
      void love_android_push_secondary(const void *rgba, int w, int h);
      void love_android_secondary_enable(int on);
    ]])
    local okLib, lib = pcall(ffi.load, "love")
    if okLib and lib and pcall(function() return lib.love_android_secondary_ready end) then
      C = lib
      log("bridge linked via ffi.load('love')")
    elseif pcall(function() return ffi.C.love_android_secondary_ready end) then
      C = ffi.C
      log("bridge linked via default namespace")
    else
      log(("bridge symbols not found (ffi.load ok=%s); second display disabled")
        :format(tostring(okLib)))
    end
  end
end

-- ---------------------------------------------------------------------------
-- THE SECOND TRANSPORT: A PAIR OF FILES.
--
-- Reported from play: "the second screen isnt working on the ayn thors bottom
-- screen for platinum".  It cannot: the three C symbols above live in the
-- vendored love-android tree and nothing has compiled them, so `available`
-- answers false, `display` mode is never offered, and the bottom screen stays
-- in the window.
--
-- WHY A SECOND ONE RATHER THAN FINISHING THE FIRST.  The FFI bridge needs new
-- code inside `liblove.so`, which means the NDK sources under
-- `mobile/android/love/src/jni/...` and a full native rebuild.  This one needs
-- no native code at all: a plain Java `Presentation`, which is an ordinary
-- class in the app module, talking to Lua through two files in the save
-- directory.  Both transports answer the same three questions, so the rest of
-- the engine cannot tell them apart and the faster one wins when it exists.
--
-- THE PROTOCOL, in full, because it has two ends and only one of them is in
-- this repository's language:
--
--   second_display/host.txt   written by the HOST, once a second.  Four
--                             space-separated fields: a protocol version, the
--                             number of displays it can see, and the panel's
--                             width and height.  Its MODIFICATION TIME is the
--                             heartbeat -- a host that has gone away stops
--                             touching it and `available` goes false within
--                             `HOST_STALE`.
--   second_display/frame.bin  written by LUA.  A TWELVE-byte header -- the
--                             four characters "G2SD", then version, width,
--                             height and sequence as little-endian u16 -- then
--                             width*height*4 bytes of RGBA.  The sequence
--                             number is what tells the host a new frame has
--                             arrived without it having to compare 192KB.
--   second_display/touch.txt  written by the HOST, read and truncated by Lua.
--                             One event per line: `down|move|up id x y`, with
--                             x and y already in the panel's own 256x192.
--
-- EVERYTHING IS IN THE SAVE DIRECTORY because that is the one place LOVE can
-- write on Android without a permission, and the host can find it: it is under
-- the app's own files directory, which is the one path an Android app always
-- knows.
-- ---------------------------------------------------------------------------
SecondScreen.DIR = "second_display"
SecondScreen.HOST = SecondScreen.DIR .. "/host.txt"
SecondScreen.FRAME = SecondScreen.DIR .. "/frame.bin"
SecondScreen.TOUCH = SecondScreen.DIR .. "/touch.txt"
SecondScreen.PROTOCOL = 1
SecondScreen.MAGIC = "G2SD"
-- How long a host may go quiet before it is treated as gone.  Two seconds is
-- twice its heartbeat, so one missed write is not a disconnection.
SecondScreen.HOST_STALE = 2.0

-- LOVE's clock, or nil where there is not one (a headless check). Declared
-- here rather than beside the native probe because BOTH transports rate-limit
-- against it now, and a local is only visible to what comes after it.
local function clock()
  if love and love.timer and love.timer.getTime then
    local ok, t = pcall(love.timer.getTime)
    if ok then return t end
  end
  return nil
end

local fileHost = nil       -- the last parsed host.txt, or false
local fileSeq = 0

local function fs()
  return love and love.filesystem
end

-- u16, little-endian, as two characters
local function u16(v)
  v = math.floor(tonumber(v) or 0) % 65536
  return string.char(v % 256, math.floor(v / 256))
end

-- Read the host's line and decide whether it is still there.  `now` is passed
-- in rather than read, so a check can drive the clock.
function SecondScreen.readHost(now)
  local f = fs()
  if not (f and f.getInfo) then return nil end
  local info = f.getInfo(SecondScreen.HOST)
  if not info then fileHost = false return nil end
  now = tonumber(now)
  if now == nil and love.timer and love.timer.getTime then
    local okNow, t = pcall(love.timer.getTime)
    now = okNow and t or nil
  end
  -- `modtime` is seconds since the epoch and `now` is LOVE's own clock, so the
  -- two cannot be subtracted.  What can be compared is the modtime against
  -- the last one seen: a host that is alive keeps changing it.
  local stamp = tonumber(info.modtime)
  local body = f.read(SecondScreen.HOST)
  if type(body) ~= "string" then fileHost = false return nil end
  local version, displays, w, h =
    body:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
  if not version then fileHost = false return nil end
  fileHost = {
    version = tonumber(version), displays = tonumber(displays),
    width = tonumber(w), height = tonumber(h), stamp = stamp, seenAt = now,
  }
  return fileHost
end

-- Is a file-protocol host attached?  A host that is present but reports no
-- second display is NOT available: the panel is what the mode needs, not the
-- host.
-- ...AND IT IS ASKED FAR MORE OFTEN THAN IT LOOKS. `SecondScreen.mode` calls
-- this, and `mode` is reached from nineteen places, several of them per frame.
-- The native branch of `available` below has been rate-limited since pass 138
-- for exactly that reason; this branch was not, so every frame did a stat and
-- a read of host.txt per call site -- dozens of small filesystem round trips a
-- frame, on the one platform this whole transport exists for.
--
-- Cached on the same interval as the native probe. A panel that appears or
-- goes away is noticed within PROBE_INTERVAL either way, which is what the
-- host's once-a-second heartbeat is already paced for.
local fileProbedAt, fileProbed = nil, false

function SecondScreen.fileAvailable(now)
  local at = tonumber(now) or clock()
  -- `at < fileProbedAt` covers a clock that went backwards, which is what a
  -- check that rewinds time looks like -- re-probe rather than trust a cache
  -- stamped in the future.
  if at and fileProbedAt and (at - fileProbedAt) < SecondScreen.PROBE_INTERVAL
     and at >= fileProbedAt then
    return fileProbed
  end
  local h = SecondScreen.readHost(now)
  fileProbed = (h and h.version == SecondScreen.PROTOCOL
                and (h.displays or 0) >= 2) and true or false
  fileProbedAt = at or fileProbedAt or 0
  return fileProbed
end

-- Drop the cached answer so the next ask goes back to the file.
function SecondScreen.forgetFileProbe()
  fileProbedAt, fileProbed = nil, false
end

-- Hand the host a frame.  `imageData` is LOVE's own, and its string is the
-- RGBA the host blits; nothing here converts, because a conversion per frame
-- is the cost this design exists to avoid.
function SecondScreen.filePush(imageData, w, h)
  local f = fs()
  if not (f and f.write and imageData and imageData.getString) then
    return false
  end
  local okStr, body = pcall(imageData.getString, imageData)
  if not (okStr and type(body) == "string") then return false end

  -- The file protocol is RGBA8 by definition. Never write a header claiming
  -- 256x192x4 while attaching a differently-sized ImageData payload; that
  -- leaves the Java side with a valid header and an unusable file forever.
  local expected = (tonumber(w) or 0) * (tonumber(h) or 0) * 4
  if #body ~= expected then
    log(("refusing frame: %dx%d expects %d RGBA8 bytes, ImageData returned %d")
      :format(tonumber(w) or 0, tonumber(h) or 0, expected, #body))
    return false
  end

  fileSeq = (fileSeq + 1) % 65536
  local header = SecondScreen.MAGIC .. u16(SecondScreen.PROTOCOL)
    .. u16(w) .. u16(h) .. u16(fileSeq)
  local packet = header .. body
  local ok, wrote = pcall(f.write, SecondScreen.FRAME, packet)
  -- LOVE filesystem.write normally returns true. Treat an explicit false as
  -- failure so SecondScreen.flush keeps the frame dirty and retries.
  return ok and wrote ~= false
end

-- Everything the host has recorded since the last call, in order, and the file
-- is emptied.  Returns a list of { kind, id, x, y }.
function SecondScreen.pollTouch()
  local f = fs()
  if not (f and f.getInfo and f.read) then return nil end
  if not f.getInfo(SecondScreen.TOUCH) then return nil end
  local body = f.read(SecondScreen.TOUCH)
  if type(body) ~= "string" or body == "" then return nil end
  -- EMPTIED BEFORE THE EVENTS ARE HANDED OUT, not after: a handler that
  -- raises must not leave the same taps in the file to be replayed on every
  -- frame for the rest of the session.
  pcall(f.write, SecondScreen.TOUCH, "")
  local out = {}
  for line in body:gmatch("[^\r\n]+") do
    local kind, id, x, y = line:match("^(%a+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
    if kind == "down" or kind == "move" or kind == "up" then
      out[#out + 1] = { kind = kind, id = tonumber(id),
                        x = tonumber(x), y = tonumber(y) }
    end
  end
  if not out[1] then return nil end
  return out
end

function SecondScreen.usable()
  return SecondScreen.fileAvailable() or C ~= nil
end

-- The Java ContentProvider host owns the Android Presentation in packaged
-- builds, so prefer its file protocol whenever its heartbeat is visible.
-- The older FFI bridge owns a different GameActivity Presentation; choosing it
-- merely because its symbols are linked can report "not ready" while the Java
-- host is already displaying the physical lower panel.
function SecondScreen.backend()
  if SecondScreen.fileAvailable() then return "file" end
  if C ~= nil then return "ffi" end
  return nil
end

-- IS A SECOND PANEL ATTACHED RIGHT NOW.
--
-- CACHED, because src/ui/SecondScreen.lua asks this from `mode`, and `mode` is
-- asked several times per frame by every caller that has to decide where to
-- draw.  It is still RE-asked -- a display can be plugged in or pulled out
-- mid-session -- just not thousands of times a second.  The window is short
-- enough that plugging a screen in is noticed within a few frames of a second.
SecondScreen.PROBE_INTERVAL = 0.5
local probedAt, probed = nil, false

function SecondScreen.available()
  -- Prefer the Java host. It is the component that actually owns the Android
  -- Presentation in current APK builds. The FFI bridge remains a fallback for
  -- builds which do not install SecondDisplayHost.
  if SecondScreen.fileAvailable() then return true end
  if not C then return false end
  local now = clock()
  if probedAt and now and (now - probedAt) < SecondScreen.PROBE_INTERVAL then
    return probed
  end
  local ok, r = pcall(C.love_android_secondary_ready)
  probed = (ok and r ~= 0) and true or false
  probedAt = now or probedAt or 0
  return probed
end

-- Force the next `available` call to ask the host again.  Called when the mode
-- changes, so a player who has just plugged a screen in does not wait out the
-- probe interval to see the option take.
function SecondScreen.forget()
  probedAt, probed = nil, false
  SecondScreen.forgetFileProbe()
end

function SecondScreen.push(imageData, w, h)
  if not imageData then return false end
  if SecondScreen.fileAvailable() then
    return SecondScreen.filePush(imageData, w, h)
  end
  if not C then return false end
  return pcall(function()
    C.love_android_push_secondary(imageData:getFFIPointer(), w, h)
  end)
end

function SecondScreen.setEnabled(on)
  if not C then return end
  pcall(function() C.love_android_secondary_enable(on and 1 or 0) end)
end

return SecondScreen
