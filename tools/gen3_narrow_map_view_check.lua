-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- A MAP NARROWER THAN THE WINDOW, AND WHAT THE REST OF THE WINDOW SHOWS.
--
-- Reported from play, three times now: "petalburg gym in emerald still showing
-- as a black background when i warp through the rooms even with no mods on".
--
-- Passes 141 and 144 proved the gym's data, tilesets, id space, window bounds,
-- camera, all 38 warps and every arrival cell correct -- 1,826 checks between
-- them -- and they were right. The gym renders exactly what the cartridge says.
-- What none of them measured is how much of the SCREEN that accounts for.
--
-- It is nine blocks wide. `data/layouts/PetalburgCity_Gym/border.bin` on the
-- cartridge is metatile 0x208 four times, and 0x208 is black in all 256 of its
-- pixels. Nine blocks is 144 world pixels; a Game Boy Advance shows 240, so
-- even the cartridge draws three black columns either side. This engine's
-- world pass shows `windowPixels / zoomScale`, which on a phone in landscape
-- is several times 240 -- and every extra column is more of the same black.
--
-- So this measures the thing the reporter can see and the other checks could
-- not: the fraction of the view that is off the map. The fix clamps the view
-- to the map's own extent or the generation's own screen, whichever is larger.
--
-- Usage: texlua tools/gen3_narrow_map_view_check.lua

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

-- A LOVE stub big enough for Renderer's scale maths and nothing more.
local WIN = { w = 240, h = 160 }
love = {
  graphics = {
    getWidth = function() return WIN.w end,
    getHeight = function() return WIN.h end,
    getDimensions = function() return WIN.w, WIN.h end,
    getPixelDimensions = function() return WIN.w, WIN.h end,
    getDPIScale = function() return 1 end,
  },
  window = { getMode = function() return WIN.w, WIN.h, {} end },
  timer = { getTime = function() return 0 end },
}

local Renderer = require("src.render.Renderer")

local function renderer(uiW, uiH)
  local r = setmetatable({}, { __index = Renderer })
  r.WIDTH, r.HEIGHT = uiW, uiH
  r.MAX_UI_WIDTH, r.MAX_UI_HEIGHT = 4096, 4096
  return r
end

-- the share of a vw x vh view that is OFF a map bw x bh pixels, with the
-- camera centred -- which is what Camera:follow does, always
local function voidShare(vw, vh, bw, bh)
  local onW = math.min(vw, bw)
  local onH = math.min(vh, bh)
  return 1 - (onW * onH) / (vw * vh)
end

-- Petalburg Gym, from the cartridge: 9 x 112 blocks of 16 world pixels.
local GYM_W, GYM_H = 9 * 16, 112 * 16
local GBA_W, GBA_H = 240, 160

-- ---------------------------------------------------------------------------
section("1. the clamp exists and is opt-in")
-- ---------------------------------------------------------------------------
ok(type(Renderer.setWorldBounds) == "function",
   "Renderer:setWorldBounds is missing, so nothing can clamp the view")
do
  local r = renderer(GBA_W, GBA_H)
  -- 640x360, NOT 960x640: at 960x640 the fit scale is a clean 4 and the view
  -- is already 240x160, so a clamp to 240 would be invisible and every check
  -- below it would pass whatever the clamp did. A window whose view is
  -- genuinely wider than the screen is the only one that can tell.
  WIN.w, WIN.h = 640, 360
  local baseW, baseH = r:worldViewSize()
  ok(baseW > GBA_W, "the unclamped view at 640x360 is %d wide, not wider than "
     .. "the GBA's %d -- this section cannot measure anything", baseW, GBA_W)
  -- UNSET IS UNCHANGED. Every caller that is not the overworld -- a battle, a
  -- menu, the title screen -- never sets bounds and must see what it always saw.
  ok(r.worldBoundsW == nil, "bounds are set before anyone asked")
  r:setWorldBounds(nil, nil)
  local w2, h2 = r:worldViewSize()
  ok(w2 == baseW and h2 == baseH,
     "clearing the bounds changed the view from %dx%d to %dx%d",
     baseW, baseH, w2, h2)
  -- zero and negative are not extents. `if bw and bh` would take 0 as true,
  -- so this has to be refused where it is set, not where it is read.
  for _, bad in ipairs({ { -1, 0 }, { 0, 0 }, { 0, 100 }, { "x", "y" } }) do
    r:setWorldBounds(bad[1], bad[2])
    local w3, h3 = r:worldViewSize()
    ok(w3 == baseW and h3 == baseH,
       "bounds %s,%s were accepted: the view became %dx%d instead of %dx%d",
       tostring(bad[1]), tostring(bad[2]), w3, h3, baseW, baseH)
  end
  -- AND BOUNDS THAT WERE SET MUST BE CLEARABLE, or the gym's 144px follows
  -- the player onto the next map and frames the whole region to a doorway.
  r:setWorldBounds(GYM_W, GYM_H)
  local clamped = r:worldViewSize()
  ok(clamped < baseW, "the gym's bounds did not clamp anything (%d)", clamped)
  r:setWorldBounds(nil, nil)
  local w4, h4 = r:worldViewSize()
  ok(w4 == baseW and h4 == baseH,
     "after clearing, the view stayed at %dx%d instead of returning to %dx%d",
     w4, h4, baseW, baseH)
end

-- ---------------------------------------------------------------------------
section("2. a map at least as big as the screen is untouched")
-- ---------------------------------------------------------------------------
for _, win in ipairs({ { 240, 160 }, { 480, 320 }, { 960, 640 }, { 1920, 1080 } }) do
  WIN.w, WIN.h = win[1], win[2]
  local r = renderer(GBA_W, GBA_H)
  local baseW, baseH = r:worldViewSize()
  -- Route 101 is 20x20 blocks; Hoenn's big routes are far larger, and every
  -- Gen 1/2 map is at least a screen across.
  r:setWorldBounds(20 * 16, 20 * 16)
  local w, h = r:worldViewSize()
  local capW = math.max(GBA_W, 320)
  ok(w == math.min(baseW, capW) or w == baseW,
     "a 320px-wide map at window %dx%d came out %d, not %d", win[1], win[2],
     w, baseW)
  -- and a genuinely large map is bit-for-bit what it was
  r:setWorldBounds(120 * 16, 120 * 16)
  local bw, bh = r:worldViewSize()
  ok(bw == baseW and bh == baseH,
     "a 1920px map at window %dx%d changed from %dx%d to %dx%d",
     win[1], win[2], baseW, baseH, bw, bh)
end

-- ---------------------------------------------------------------------------
section("3. the view never drops below the generation's own screen")
-- ---------------------------------------------------------------------------
-- THIS IS THE GUARD THAT KEEPS GEN 1 AND 2 OUT OF IT. Clamping to the map
-- alone would frame a small map tighter than its cartridge ever did.
for _, ui in ipairs({ { 160, 144 }, { 240, 160 }, { 256, 192 } }) do
  WIN.w, WIN.h = 1280, 720
  local r = renderer(ui[1], ui[2])
  r:setWorldBounds(32, 32)   -- absurdly small: two blocks
  local w, h = r:worldViewSize()
  ok(w >= ui[1] and h >= ui[2],
     "a 2x2-block map on a %dx%d screen framed to %dx%d, tighter than the "
     .. "cartridge", ui[1], ui[2], w, h)
end

-- ---------------------------------------------------------------------------
section("4. Petalburg Gym: what the reporter actually sees")
-- ---------------------------------------------------------------------------
io.write("   window     view before   void before   view after   void after\n")
local improved, worsened = 0, 0
for _, win in ipairs({ { 240, 160 }, { 480, 320 }, { 640, 360 },
                       { 960, 540 }, { 1280, 720 } }) do
  WIN.w, WIN.h = win[1], win[2]
  local r = renderer(GBA_W, GBA_H)
  local bw, bh = r:worldViewSize()
  local before = voidShare(bw, bh, GYM_W, GYM_H)
  r:setWorldBounds(GYM_W, GYM_H)
  local aw, ah = r:worldViewSize()
  local after = voidShare(aw, ah, GYM_W, GYM_H)
  io.write(("  %4dx%-4d  %4dx%-4d    %5.1f%%       %4dx%-4d   %5.1f%%\n")
    :format(win[1], win[2], bw, bh, before * 100, aw, ah, after * 100))
  ok(after <= before + 1e-9,
     "at %dx%d the clamp made it WORSE: %.1f%% -> %.1f%%",
     win[1], win[2], before * 100, after * 100)
  -- the cartridge's own framing is the floor, so the view can never be
  -- narrower than 240 and the void can never beat the GBA's own 40%
  ok(aw >= GBA_W and ah >= GBA_H,
     "at %dx%d the clamp framed tighter than the GBA: %dx%d", win[1], win[2],
     aw, ah)
  if after < before - 1e-9 then improved = improved + 1 end
  if after > before + 1e-9 then worsened = worsened + 1 end
end
ok(improved >= 3, "only %d of 5 window sizes showed less void; the clamp is "
   .. "not doing anything on a phone", improved)
ok(worsened == 0, "%d window size(s) got worse", worsened)

-- A CLAMPED VIEW IS STILL AN EVEN ONE. Camera:follow halves it, and an odd
-- half puts the tile layer on a fractional pixel against the sprites -- which
-- is the shimmer the parity fix-up above the clamp exists to stop. The clamp
-- runs after it, so it needs its own.
do
  WIN.w, WIN.h = 1600, 900
  local r = renderer(GBA_W, GBA_H)
  local baseW = r:worldViewSize()
  -- 301 and 171 world pixels: odd, above the GBA's screen so `max` picks them,
  -- and BELOW the unclamped view so `min` actually lands on them.
  r:setWorldBounds(301, 171)
  local w, h = r:worldViewSize()
  ok(w < baseW, "a 301px bound did not clamp a %d-wide view", baseW)
  ok(w % 2 == 0, "the clamped view is %d wide -- odd, so the world layer "
     .. "lands on a half pixel", w)
  ok(h % 2 == 0, "the clamped view is %d tall -- odd", h)
end

-- ...AND THE CONTROL. At the GBA's own size there is nothing to fix, and a
-- clamp that changed the classic framing would be a regression, not a fix.
do
  WIN.w, WIN.h = 240, 160
  local r = renderer(GBA_W, GBA_H)
  local bw, bh = r:worldViewSize()
  r:setWorldBounds(GYM_W, GYM_H)
  local aw, ah = r:worldViewSize()
  ok(aw == bw and ah == bh,
     "at the GBA's own 240x160 the view changed from %dx%d to %dx%d",
     bw, bh, aw, ah)
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
