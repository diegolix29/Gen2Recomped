-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE ELLIPTICAL LUNGE, WALKED AGAINST THE CARTRIDGE'S OWN ARITHMETIC.
--
-- Nineteen Emerald moves swing the battler round an ellipse -- QUICK ATTACK's
-- nine-frame dart, AERIAL ACE, WING ATTACK, STEEL WING, SUBMISSION -- and
-- until now the port drew none of it. `RomExtractorGen3:ellipseOffsets` turns
-- one script call into the offsets the cartridge would produce, one pair a
-- frame, and this is what says it produces the right ones.
--
-- THE REFERENCE IS NOT THIS FILE'S OPINION. `tools/gen3_ellipse_ref.lua` was
-- computed from pokeemerald's own `AnimTask_TranslateMonElliptical_Step` and
-- the cartridge's own `gSineTable`, for the real arguments of all twenty calls
-- read out of the ROM's script table. Agreeing with it is agreeing with the
-- hardware; a check that recomputed the same formula next to the code would
-- only prove the formula was copied consistently.
--
-- WHY IT DOES NOT NEED THE ROM. `ellipseOffsets` is pure given a shape, and a
-- shape is a sine table and two addresses. The table travels in the fixture,
-- so this runs anywhere -- which is the point, because the import that would
-- exercise it needs LOVE and a cartridge and cannot run in a check.
--
-- Usage: texlua tools/gen3_ellipse_check.lua

package.path = "./?.lua;" .. package.path

-- LuaJIT's `bit`, which texlua has not got. RomGba wants it at require time.
package.preload["bit"] = function()
  local function tou32(v) return math.floor(v) % 4294967296 end
  local function op(a, b, f)
    a, b = tou32(a), tou32(b)
    local r, m = 0, 1
    for _ = 1, 32 do
      r = r + f(a % 2, b % 2) * m
      a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
    end
    return r
  end
  local M = {}
  function M.band(a, b, ...) local r = op(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end)
    for _, c in ipairs({...}) do r = M.band(r, c) end return r end
  function M.bor(a, b, ...) local r = op(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end)
    for _, c in ipairs({...}) do r = M.bor(r, c) end return r end
  function M.bxor(a, b, ...) local r = op(a, b, function(x, y) return (x ~= y) and 1 or 0 end)
    for _, c in ipairs({...}) do r = M.bxor(r, c) end return r end
  function M.bnot(a) return 4294967295 - tou32(a) end
  function M.lshift(a, n) return tou32(tou32(a) * 2 ^ n) end
  function M.rshift(a, n) return math.floor(tou32(a) / 2 ^ n) end
  function M.arshift(a, n) return M.rshift(a, n) end
  function M.tobit(a) local v = tou32(a) return v >= 2147483648 and v - 4294967296 or v end
  function M.tohex(a) return ("%08x"):format(tou32(a)) end
  return M
end

love = {
  filesystem = { getInfo = function() return nil end,
                 read = function() return nil end },
  graphics = { getWidth = function() return 240 end,
               getHeight = function() return 160 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local okReq, Rom = pcall(require, "src.import.RomExtractorGen3")
ok(okReq and type(Rom) == "table",
   "src.import.RomExtractorGen3 did not load: %s", tostring(Rom))
if not (okReq and type(Rom) == "table") then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local REF = dofile("tools/gen3_ellipse_ref.lua")
ok(type(REF) == "table", "the reference fixture did not load")

-- ---------------------------------------------------------------------------
section("1. the decoder exists and takes a shape")
-- ---------------------------------------------------------------------------
ok(type(Rom.ellipseOffsets) == "function", "ellipseOffsets is missing")
ok(type(Rom.monEllipse) == "function", "monEllipse is missing")
local E = Rom.MON_ELLIPSE
ok(type(E) == "table", "MON_ELLIPSE is missing")
ok(E and E.COS == 64, "Cos is Sin(i + %s); the cartridge offsets by 64",
   tostring(E and E.COS))
ok(E and E.PHASE_MASK == 0xFF, "the phase mask is %s, not a byte",
   tostring(E and E.PHASE_MASK))
ok(E and E.MAX_SPEED == 5, "the cartridge clamps the speed at 5, not %s",
   tostring(E and E.MAX_SPEED))

-- THE SINE TABLE, rebuilt from the reference's own first call so the shape
-- handed to the decoder is the cartridge's. gSineTable is 320 entries: a
-- 256-entry copy would be read off the end by Cos, which indexes i + 64.
local SINE = {}
do
  -- sin over 256 steps in Q8.8, which is what the cartridge stores, extended
  -- by a quarter turn so Cos can read i + 64.
  for i = 0, 319 do
    SINE[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5)
  end
end
ok(SINE[0] == 0 and SINE[64] == 256 and SINE[128] == 0 and SINE[192] == -256,
   "the sine table is not the cartridge's shape: [0]=%d [64]=%d [128]=%d [192]=%d",
   SINE[0], SINE[64], SINE[128], SINE[192])

local SHAPE = { plain = 0x0D5738, wrapper = 0x0D5830, sine = SINE,
                source = "check" }

-- ---------------------------------------------------------------------------
section("2. every real call, frame for frame")
-- ---------------------------------------------------------------------------
local moves, calls, frames = 0, 0, 0
local worst = nil
for name, list in pairs(REF) do
  moves = moves + 1
  for _, want in ipairs(list) do
    calls = calls + 1
    local got = Rom.ellipseOffsets(Rom, want.args, SHAPE, want.side)
    if not got then
      ok(false, "%s: the decoder refused its own arguments {%s}",
         name, table.concat(want.args, ", "))
    else
      local bad = nil
      if #got.xs ~= #want.xs then
        bad = ("%d frames, not %d"):format(#got.xs, #want.xs)
      else
        for i = 1, #want.xs do
          frames = frames + 1
          if got.xs[i] ~= want.xs[i] or got.ys[i] ~= want.ys[i] then
            bad = ("frame %d is %d,%d and the cartridge gives %d,%d")
                  :format(i, got.xs[i], got.ys[i], want.xs[i], want.ys[i])
            break
          end
        end
      end
      ok(bad == nil, "%s {%s}: %s", name, table.concat(want.args, ", "),
         tostring(bad))
      if bad and not worst then worst = name end
      -- whose Pokemon moves, and whether the number is the player's
      ok((got.target == true) == (want.args[1] == 1),
         "%s: argument zero is %d and the record says target=%s",
         name, want.args[1], tostring(got.target))
      ok((got.authoredForPlayer == true) == (want.side == true),
         "%s: it is the %s task and authoredForPlayer is %s", name,
         want.side and "side-respecting" or "plain",
         tostring(got.authoredForPlayer))
      ok(got.life == #got.xs, "%s: life is %s for a %d-frame track",
         name, tostring(got.life), #got.xs)
    end
  end
end
io.write(("  %d moves, %d calls, %d frames compared\n")
         :format(moves, calls, frames))
ok(moves >= 18, "only %d move(s) in the reference", moves)
ok(frames > 800, "only %d frame(s) compared", frames)

-- ---------------------------------------------------------------------------
section("3. the track is a lunge, not a drift")
-- ---------------------------------------------------------------------------
-- A move that swings out and does not come back leaves the Pokemon standing
-- somewhere it does not belong for the rest of the battle.
for name, list in pairs(REF) do
  for _, want in ipairs(list) do
    local got = Rom.ellipseOffsets(Rom, want.args, SHAPE, want.side)
    if got then
      ok(got.xs[1] == 0 and got.ys[1] == 0,
         "%s starts at %d,%d rather than where the Pokemon stands",
         name, got.xs[1], got.ys[1])
      ok(got.xs[#got.xs] == 0 and got.ys[#got.ys] == 0,
         "%s ends at %d,%d -- the Pokemon never comes home",
         name, got.xs[#got.xs], got.ys[#got.ys])
      local reach = 0
      for _, x in ipairs(got.xs) do reach = math.max(reach, math.abs(x)) end
      ok(reach > 0, "%s never moves at all", name)
      ok(reach <= math.abs(want.args[2]),
         "%s reaches %d, past the %d its script asked for",
         name, reach, math.abs(want.args[2]))
    end
  end
end

-- ---------------------------------------------------------------------------
section("4. it refuses what it should")
-- ---------------------------------------------------------------------------
-- A decoder that accepts anything turns an unrelated task that happens to
-- share an address into a lunge.
local BAD = {
  { { 2, 24, 6, 1, 5 }, "a battler that is neither side" },
  { { 0, 0, 6, 1, 5 }, "no horizontal travel at all" },
  { { 0, 900, 6, 1, 5 }, "a lunge wider than the screen" },
  { { 0, 24, -6, 1, 5 }, "a negative vertical amplitude" },
  { { 0, 24, 6, 0, 5 }, "zero cycles" },
  { { 0, 24, 6, 99, 5 }, "more cycles than any move asks for" },
  { { 0, 24, 6, 1 }, "only four arguments" },
}
for _, row in ipairs(BAD) do
  local got = Rom.ellipseOffsets(Rom, row[1], SHAPE, true)
  ok(got == nil, "the decoder accepted %s", row[2])
end
-- ...and a speed past the cap is CLAMPED, not refused: the cartridge clamps it
-- itself, so refusing would drop a call the hardware plays.
do
  local capped = Rom.ellipseOffsets(Rom, { 0, 24, 6, 1, 9 }, SHAPE, true)
  local five = Rom.ellipseOffsets(Rom, { 0, 24, 6, 1, 5 }, SHAPE, true)
  ok(capped ~= nil, "a speed above the cap was refused instead of clamped")
  if capped and five then
    ok(#capped.xs == #five.xs,
       "speed 9 gave %d frames and speed 5 gave %d; the cap is not applied",
       #capped.xs, #five.xs)
  end
end
-- a shape with no sine is not a shape
ok(Rom.ellipseOffsets(Rom, { 0, 24, 6, 1, 5 }, { plain = 1 }, true) == nil,
   "the decoder ran without a sine table")

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
