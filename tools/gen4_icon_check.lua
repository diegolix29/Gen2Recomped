-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_icon_check.lua -- is the party-icon palette table the right array.
--
-- `sPokemonIconPaletteIndex` is found by scanning the ARM9 for a run of bytes
-- below the number of populated sub-palettes, and over the whole binary TWO
-- runs match. The tie-break -- take the one whose values are most evenly spread
-- -- is a judgement, not a derivation, so the answer it picks was checked by
-- RENDERING A HUNDRED ICONS AND LOOKING AT THEM.
--
-- This asserts what that render was checked against. A WRONG TABLE DOES NOT
-- FAIL, IT MIS-COLOURS: the party list still draws, in the wrong palettes,
-- which reads as a palette bug rather than as "the scan found the wrong array".
-- That is exactly the kind of fault that needs a check rather than an eye.
--
-- Run:  texlua tools/gen4_icon_check.lua [arm9.bin]
--
-- Dump the ARM9 with the header's own offsets (0x20 = position, 0x2C = size).
-- Without one, only the module's own constants are checked, and it SAYS SO
-- rather than reporting a pass it did not earn.

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local Icons = require("src.import.Gen4Icons")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-52s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-52s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end

io.write("the party icons\n")

ok(Icons.FIRST_SHEET == 7,
   "the sheets start after the palette and three cell banks",
   Icons.FIRST_SHEET, 7)
ok(Icons.WIDTH == 32 and Icons.FRAME_HEIGHT == 32 and Icons.FRAMES == 2,
   "32x32, two frames -- the up and down of the bounce",
   ("%dx%d x%d"):format(Icons.WIDTH, Icons.FRAME_HEIGHT, Icons.FRAMES),
   "32x32 x2")
-- 1072 bytes a sheet: a 48-byte NCGR header and 1024 of 4bpp pixels, which is
-- exactly 32 x 64. The arithmetic is the check.
ok(Icons.WIDTH * Icons.FRAME_HEIGHT * Icons.FRAMES / 2 == 1024,
   "...which is the 1024 pixel bytes each sheet carries",
   Icons.WIDTH * Icons.FRAME_HEIGHT * Icons.FRAMES / 2, 1024)
ok(Icons.RAMPS == 3, "three of the palette's sixteen ramps carry colour",
   Icons.RAMPS, 3)

local verified = 0
for _ in pairs(Icons.VERIFIED) do verified = verified + 1 end
ok(verified >= 5, "enough species were checked by eye to catch a wrong table",
   verified, ">= 5")
-- The seven must not all name the same ramp, or agreeing with them would prove
-- nothing: the OTHER candidate run puts every one of them on ramp 0.
local ramps = {}
for _, r in pairs(Icons.VERIFIED) do ramps[r] = true end
local distinct = 0
for _ in pairs(ramps) do distinct = distinct + 1 end
ok(distinct >= 2, "...and they do not all name the same ramp", distinct, ">= 2")

local path = arg and arg[1]
if path then
  local f = io.open(path, "rb")
  if not f then
    io.write("\ncannot read " .. path .. "\n")
    os.exit(2)
  end
  local bin = f:read("*a"); f:close()
  local at, spread = Icons.findPaletteTable(bin, 540)
  ok(at ~= nil, "the palette table is found in this ARM9",
     at and ("0x%X"):format(at - 1) or "nil", "an offset")
  if at then
    local good, wrong = Icons.verify(bin, at)
    ok(good, "...and agrees with every species checked by eye",
       good and "all" or table.concat(wrong, ", "), "all")
    -- The tie-break itself, stated as a number so a future build that makes
    -- the two runs comparable is visible rather than silently coin-flipped.
    ok(spread and spread > 1.2,
       "...and won on spread by a margin, not a whisker",
       spread and ("%.3f bits"):format(spread) or "nil", "> 1.2")
  end
else
  io.write("\n(the ARM9 was not checked -- pass a dump of it as the first\n"
           .. " argument to verify the table against the cartridge)\n")
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
