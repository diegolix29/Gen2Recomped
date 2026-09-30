-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE SECOND DISPLAY'S FILE PROTOCOL, BOTH DIRECTIONS.
--
-- Reported from play: "the second screen isnt working on the ayn thors bottom
-- screen for platinum". It cannot: `display` mode is gated on a transport, the
-- only transport was an FFI bridge to three C symbols that live in the vendored
-- love-android tree, and nothing has compiled them.
--
-- So there is a second transport, and it needs no native code at all: a plain
-- Java `Presentation` -- an ordinary class in the app module -- talking to Lua
-- through two files in the save directory. The Java half cannot be tested from
-- here. THIS half can, and it is the half that has to be exactly right, because
-- the other end is written against it.
--
-- WHAT IS ACTUALLY CHECKED: the bytes. A header the host parses one field out
-- of step reads a plausible frame at the wrong size, and the panel shows
-- garbage rather than nothing -- so the header is asserted byte by byte, not
-- "a string was written".
--
-- Usage: texlua tools/gen4_second_display_file_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
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

-- ---------------------------------------------------------------------------
-- A FILESYSTEM IN A TABLE.  Not a stub that answers: the contents are kept, so
-- what the transport WROTE can be read back and taken apart.
-- ---------------------------------------------------------------------------
local FS = { files = {}, clock = 1000 }
love = {
  timer = { getTime = function() return FS.clock end },
  filesystem = {
    getInfo = function(path)
      local f = FS.files[path]
      if not f then return nil end
      return { size = #f.body, modtime = f.modtime, type = "file" }
    end,
    read = function(path)
      local f = FS.files[path]
      if not f then return nil end
      return f.body, #f.body
    end,
    write = function(path, body)
      FS.clock = FS.clock + 1
      FS.files[path] = { body = body or "", modtime = FS.clock }
      return true
    end,
    append = function(path, body)
      local f = FS.files[path]
      FS.files[path] = { body = (f and f.body or "") .. (body or ""),
                         modtime = FS.clock }
      return true
    end,
    createDirectory = function() return true end,
  },
  graphics = { getWidth = function() return 240 end,
               getHeight = function() return 160 end },
}

local T = require("src.render.SecondScreen")

local function host(version, displays, w, h)
  love.filesystem.write(T.HOST,
    ("%d %d %d %d\n"):format(version, displays, w, h))
end
local function imageData(body)
  local d = { body = body }
  function d:getString() return self.body end
  function d:release() end
  return d
end

-- ---------------------------------------------------------------------------
section("1. whether a host is there at all")
-- ---------------------------------------------------------------------------
ok(T.PROTOCOL == 1, "the protocol version is %s", tostring(T.PROTOCOL))
ok(T.MAGIC == "G2SD" and #T.MAGIC == 4, "the magic is %q", tostring(T.MAGIC))
ok(T.fileAvailable() == false,
   "a transport with no host.txt at all reports a panel")
host(1, 2, 256, 192)
ok(T.fileAvailable() == true, "a host reporting two displays is not available")
local h = T.readHost()
ok(h and h.displays == 2 and h.width == 256 and h.height == 192,
   "the host line parsed to %s", tostring(h and h.displays))
-- ONE display is a phone with no panel, and must NOT be available -- this is
-- the case that decides whether the option appears in the menu at all.
host(1, 1, 256, 192)
ok(T.fileAvailable() == false,
   "a host that can see only ONE display still reports a second panel")
-- a protocol the host does not speak
host(99, 2, 256, 192)
ok(T.fileAvailable() == false, "a host speaking protocol 99 was accepted")
-- junk
love.filesystem.write(T.HOST, "hello\n")
ok(T.fileAvailable() == false, "a host.txt of junk was accepted")
host(1, 2, 256, 192)
ok(T.fileAvailable() == true, "the good host stopped being available")
ok(T.backend() == "file", "the backend answers %s, not \"file\"",
   tostring(T.backend()))

-- ---------------------------------------------------------------------------
section("2. the frame, byte by byte")
-- ---------------------------------------------------------------------------
local W, H = 256, 192
local body = string.rep("\1\2\3\255", W * H)
ok(T.push(imageData(body), W, H) == true, "a frame would not go out")
local frame = love.filesystem.read(T.FRAME)
ok(type(frame) == "string", "nothing was written to %s", T.FRAME)
if type(frame) == "string" then
  ok(#frame == 12 + W * H * 4,
     "the frame is %d bytes; a twelve-byte header plus %dx%dx4 is %d",
     #frame, W, H, 12 + W * H * 4)
  ok(frame:sub(1, 4) == "G2SD", "the magic is %q", frame:sub(1, 4))
  local function u16at(i)
    return frame:byte(i) + frame:byte(i + 1) * 256
  end
  ok(u16at(5) == 1, "the header's version field is %d", u16at(5))
  ok(u16at(7) == W, "the header's width is %d, not %d", u16at(7), W)
  ok(u16at(9) == H, "the header's height is %d, not %d", u16at(9), H)
  local seq1 = u16at(11)
  ok(frame:sub(13) == body,
     "the pixels after the header are not the ones handed in")
  -- THE SEQUENCE IS WHAT TELLS THE HOST A FRAME IS NEW.  Without it the host
  -- has to compare 192KB to know, which is the cost this design avoids.
  T.push(imageData(body), W, H)
  local frame2 = love.filesystem.read(T.FRAME)
  local seq2 = frame2:byte(11) + frame2:byte(12) * 256
  ok(seq2 == (seq1 + 1) % 65536,
     "the sequence went %d -> %d; the host cannot tell the frames apart",
     seq1, seq2)
end
-- a frame with no ImageData is a refusal, not a zero-length file
ok(T.push(nil, W, H) == false, "a nil frame was pushed")

-- ---------------------------------------------------------------------------
section("3. the taps coming back")
-- ---------------------------------------------------------------------------
love.filesystem.write(T.TOUCH,
  "down 3 128 96\nmove 3 130 98\nup 3 130 98\n")
local events = T.pollTouch()
ok(events and #events == 3, "%s event(s) parsed, not 3",
   tostring(events and #events))
if events and #events == 3 then
  ok(events[1].kind == "down" and events[1].id == 3
     and events[1].x == 128 and events[1].y == 96,
     "the first event parsed as %s %s %s,%s", tostring(events[1].kind),
     tostring(events[1].id), tostring(events[1].x), tostring(events[1].y))
  ok(events[3].kind == "up", "the last event is %s", tostring(events[3].kind))
end
-- EMPTIED, or every frame replays the same taps for the rest of the session
ok(love.filesystem.read(T.TOUCH) == "",
   "the touch file still holds %q after being read",
   tostring(love.filesystem.read(T.TOUCH)))
ok(T.pollTouch() == nil, "a second poll returned events from an empty file")
-- junk lines are dropped, good ones beside them are not
-- The junk must include a WELL-FORMED line with a kind the protocol has no
-- handler for.  Lines that simply fail the pattern are rejected by the pattern
-- and say nothing about whether the kind is checked at all -- which is exactly
-- the hole the first version of this check had.
love.filesystem.write(T.TOUCH,
  "nonsense\nsideways 1 10 20\ndown 1 10 20\n\nwibble 2 3\n")
local mixed = T.pollTouch()
ok(mixed and #mixed == 1, "%s event(s) survived a file with junk in it, not 1",
   tostring(mixed and #mixed))
ok(mixed and mixed[1] and mixed[1].kind == "down",
   "the surviving event is a %s, so \"sideways\" was taken as a tap",
   tostring(mixed and mixed[1] and mixed[1].kind))

-- ---------------------------------------------------------------------------
section("4. and the taps reach the game's own handlers")
-- ---------------------------------------------------------------------------
local UI = require("src.ui.SecondScreen")
UI._setTransport(T)
host(1, 2, 256, 192)
do
  local game = { data = { isGen4Cache = true },
                 save = { options = { secondScreenMode = "display" } } }
  ok(UI.mode(game) == "display",
     "with a file host attached the mode answers %q", UI.mode(game))
  local got = {}
  local function record(name)
    return function(self, id, x, y)
      -- the point must resolve INSIDE the handler, which is where the battle,
      -- the mining screen and the Poketch all ask
      local lx, ly = UI.toLocal(self, x, y)
      got[#got + 1] = { name, id, x, y, lx, ly }
    end
  end
  game.touchpressed = record("down")
  game.touchmoved = record("move")
  game.touchreleased = record("up")
  love.filesystem.write(T.TOUCH, "down 7 40 50\nmove 7 41 51\nup 7 41 51\n")
  local taken = UI.pumpInput(game)
  ok(taken == 3, "%d of 3 taps were taken", taken)
  ok(#got == 3, "%d handler call(s)", #got)
  if #got == 3 then
    ok(got[1][1] == "down" and got[1][2] == 7 and got[1][3] == 40
       and got[1][4] == 50, "the down tap arrived as %s %s %s,%s",
       tostring(got[1][1]), tostring(got[1][2]), tostring(got[1][3]),
       tostring(got[1][4]))
    ok(got[1][5] == 40 and got[1][6] == 50,
       "the handler resolved it to %s,%s instead of 40,50",
       tostring(got[1][5]), tostring(got[1][6]))
    ok(got[2][1] == "move" and got[3][1] == "up",
       "the three taps did not reach three different handlers")
  end
  ok(game.secondScreenInjecting == nil,
     "the injecting flag was left set, so every later WINDOW click becomes a "
     .. "panel tap")
  -- ...AND THE CONTROL: with no panel the same taps must not be delivered,
  -- or `pumpInput` is doing it regardless of the mode.
  host(1, 1, 256, 192)
  love.filesystem.write(T.TOUCH, "down 7 40 50\n")
  local before = #got
  UI.pumpInput(game)
  ok(#got == before, "%d tap(s) were delivered with no second panel attached",
     #got - before)
  -- ...and `pumpInput` must not even LOOK.  `injectTouch` refuses out of
  -- display mode on its own, so a `pumpInput` that ignored the mode would
  -- still pass the check above -- while draining the host's file and throwing
  -- the taps away every frame.  What that costs is measurable: the file.
  ok(love.filesystem.read(T.TOUCH) == "down 7 40 50\n",
     "the touch file was drained with no panel attached (now %q)",
     tostring(love.filesystem.read(T.TOUCH)))
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
