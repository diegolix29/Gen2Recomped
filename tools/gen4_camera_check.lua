-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the Gen 4 camera table is the cartridge's, and that
-- everything drawn in a Sinnoh map is drawn through the SAME projection.
--
-- Reported from play: the overworld "doesn't seem to have a camera like gen4
-- did". It has one -- `Gen4Ground` projects with the cartridge's own
-- `z*sin(pitch) - y*cos(pitch)`, and that part is right. THE SPRITES DO NOT.
-- Nothing outside `src/render/` projects anything through `Gen4Camera`, so the
-- player, the NPCs and the props are still placed on the flat 16-pixel tile
-- grid while the ground under them is compressed to 85.8% of its depth.
--
-- Measured on the bench (tools/gen4-camera-bench, a LOVE app that draws both and
-- screenshots them): at four tiles the two disagree by 9.1 px, at eight by 18.2,
-- and at sixteen by 36.4 -- TWO AND A QUARTER TILES. A character at the far edge
-- of the view is drawn more than two tiles off the ground it is standing on, and
-- a world whose ground tilts while its people do not is a world that does not
-- read as tilted at all.
--
-- Usage: texlua tools/gen4_camera_check.lua <rom> <pokeplatinum dir>

local romPath, pretDir = arg[1], arg[2]
if not romPath or not pretDir then
  io.stderr:write("usage: texlua tools/gen4_camera_check.lua <rom> <pokeplatinum dir>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local Cam = require("src.render.Gen4Camera")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function stripComments(t) return (tostring(t):gsub("%-%-[^\r\n]*", "")) end
local function port(rel)
  local f = io.open(root .. "../" .. rel, "rb") or io.open(rel, "rb")
  if not f then return nil end
  local s = f:read("a"); f:close(); return s
end

local abs, sin, cos, rad, tan = math.abs, math.sin, math.cos, math.rad, math.tan

-- ---------------------------------------------------------------------------
section("1. the seventeen rows, and the rule that makes them one to one")
-- ---------------------------------------------------------------------------
local n = 0
for _ in pairs(Cam.TYPES) do n = n + 1 end
ok(n == 17, "%d camera types, expected 17", n)
ok(Cam.SCREEN_W == 256 and Cam.SCREEN_H == 192,
   "the screen is %dx%d, expected the DS's 256x192", Cam.SCREEN_W, Cam.SCREEN_H)

-- `tan(halfFov) * distance` is half the screen height in world units, and on
-- this cartridge it lands on 96 for every row -- which is what says one world
-- unit is one screen pixel. A row that misses badly is a row read wrong.
-- TWO ROWS MISS, AND THEY ARE NAMED RATHER THAN WAVED THROUGH. The camera file
-- used to claim all seventeen came within 1.3%; it was written from the four rows
-- quoted in it. Checking all of them found stark_room2 at +19.89% and unused_16
-- at -4.57%, and BOTH were re-read from pret's `sCameraTypes` and match exactly
-- -- so the cartridge really does render Stark Mountain's second room about 1.2x
-- off one-unit-per-pixel. Listing the exceptions by name means a THIRD one fails
-- here instead of being absorbed by a loosened tolerance.
local EXPECTED_MISSES = { stark_room2 = true, unused_16 = true }
local misses = {}
local worst, worstId = 0, nil
for id, cfg in pairs(Cam.TYPES) do
  local half = Cam.halfHeight(cfg)
  local err = abs(half - 96) / 96
  if err > 0.013 then misses[cfg.id] = err end
  if err > worst and not EXPECTED_MISSES[cfg.id] then worst, worstId = err, cfg.id end
  ok(err < 0.013 or EXPECTED_MISSES[cfg.id],
     "camera %s: tan(halfFov)*distance is %.2f, %.1f%% off the DS's 96 rows",
     tostring(cfg.id), half, err * 100)
  ok(cfg.pitch > 0 and cfg.pitch < 90,
     "camera %s has pitch %s, which is not below horizontal",
     tostring(cfg.id), tostring(cfg.pitch))
  ok(cfg.far > cfg.near, "camera %s has far %s behind near %s",
     tostring(cfg.id), tostring(cfg.far), tostring(cfg.near))
end
ok(worst < 0.013,
   "the worst row that is supposed to obey the rule (%s) is %.2f%% off",
   tostring(worstId), worst * 100)
local missCount = 0
for _ in pairs(misses) do missCount = missCount + 1 end
ok(missCount == 2,
   "%d rows miss the 1:1 rule, expected exactly 2 (stark_room2, unused_16)", missCount)
for name in pairs(EXPECTED_MISSES) do
  ok(misses[name],
     "camera %s now obeys the 1:1 rule -- if the table changed, the note in "
     .. "Gen4Camera about it needs to change too", name)
end
-- ...and that they are not all the same row, or the table says nothing.
local pitches = {}
for _, cfg in pairs(Cam.TYPES) do pitches[cfg.pitch] = true end
local distinct = 0
for _ in pairs(pitches) do distinct = distinct + 1 end
ok(distinct >= 10,
   "only %d distinct pitches across 17 cameras -- if they were all equal this "
   .. "file could not tell one from another", distinct)

-- ---------------------------------------------------------------------------
section("2. the projection is the cartridge's, and the oblique is not it")
-- ---------------------------------------------------------------------------
local cfg = Cam.forType(0)
local s, c = Cam.scales(cfg)
ok(abs(s - sin(rad(cfg.pitch))) < 1e-9 and abs(c - cos(rad(cfg.pitch))) < 1e-9,
   "scales() is not sin/cos of the pitch")
ok(abs(s - 0.8576) < 0.001, "DEFAULT's ground scale is %.4f, expected 0.8576", s)
ok(abs(c - 0.5143) < 0.001, "DEFAULT's height scale is %.4f, expected 0.5143", c)

-- `project` is z*sin - y*cos, tested on points rather than on its source.
local px, py = Cam.project(cfg, 10, 0, 100)
ok(px == 10, "x is not passed through (%s)", tostring(px))
ok(abs(py - 100 * s) < 1e-6, "ground depth is scaled by %.4f, expected sin", py / 100)
local _, hy = Cam.project(cfg, 0, 100, 0)
ok(abs(hy + 100 * c) < 1e-6, "height is scaled by %.4f, expected -cos", -hy / 100)

-- THE OBLIQUE IS THE SAME PICTURE STRETCHED BY 1/sin, AND THAT IS WHY IT LOOKS
-- FLAT. Shape ratios are identical -- a roof against a wall comes out 1.668 in
-- both -- so the oblique is not a different angle, it is the right angle with
-- the world made 16.6% too tall and 16.6% too little ground on screen.
local lean = Cam.lean(cfg)
ok(abs(lean - c / s) < 1e-9, "lean() is not cot(pitch)")
local roofCart, wallCart = 24 * s, 24 * c       -- a 24-deep roof, a 24-tall wall
local roofObl, wallObl = 24 * 1, 24 * lean
ok(abs((roofCart / wallCart) - (roofObl / wallObl)) < 1e-9,
   "the oblique and the cartridge disagree on a roof:wall ratio (%.4f vs %.4f) "
   .. "-- they must not, because cot = cos/sin makes them the same shape",
   roofCart / wallCart, roofObl / wallObl)
ok(abs((roofObl / roofCart) - 1 / s) < 1e-9,
   "the oblique's stretch is %.4f, expected 1/sin = %.4f", roofObl / roofCart, 1 / s)
ok(abs(1 / s - 1.166) < 0.001, "1/sin is %.4f, expected 1.166", 1 / s)

-- ---------------------------------------------------------------------------
section("3. the ground renderer uses sin and cos, not 1 and cot")
-- ---------------------------------------------------------------------------
local ground = stripComments(port("src/render/Gen4Ground.lua") or "")
ok(#ground > 0, "Gen4Ground.lua could not be read")
ok(ground:find("Gen4Camera.scales", 1, true),
   "Gen4Ground no longer asks the camera for sin and cos")
-- Row 2 of the projection matrix is the screen-Y row: the height term must be
-- -2*cos/height and the ground term 2*sin/height. The oblique's were
-- -2*lean/height and 2/height, and telling them apart is the whole point.
ok(ground:find("0, -2 * cosP / height, 2 * sinP / height", 1, true),
   "the ground's screen-Y row is not `-2*cos/height, 2*sin/height` -- if it is "
   .. "back to `-2*lean/height, 2/height` the world is oblique again")
ok(ground:find("local leanPx = height - 2 * half * sinP", 1, true),
   "the canvas headroom is no longer computed from sin")

-- AND `scale()` HAS TO ACTUALLY RETURN THEM. A planted `return 1, 0` passed
-- everything else in this file: the call site still calls it, the (1 - sin) term
-- is still written, and (1 - 1) is zero -- so every sprite silently stops being
-- compressed while the ground still is. An accessor that lies makes each of its
-- consumers look correct on its own.
ok(ground:find("self.groundScale, self.heightScale = sinP, cosP", 1, true),
   "Gen4Ground no longer stores sin and cos as its ground and height scales")
ok(ground:find("return self.groundScale or 1, self.heightScale or 0", 1, true),
   "Gen4Ground:scale() no longer returns the stored scales -- if it returns a "
   .. "constant, every sprite reads a pitch of 90 while the ground draws at the "
   .. "map's own")

-- ---------------------------------------------------------------------------
section("4. the sprites are projected with the ground")
-- ---------------------------------------------------------------------------
-- I GOT THIS WRONG FIRST TIME AND THE CORRECTION IS THE POINT OF THE SECTION.
--
-- The first draft asserted that `Gen4Camera.project` was called by something, saw
-- that nothing calls it, and reported "nothing projects sprites -- the ground is
-- compressed and every character stays on the flat grid". That conclusion was
-- false. The projection IS applied; it just does not go through that function.
-- `OverworldState:draw` asks the ground for its scale and folds the whole thing
-- into a per-entity CAMERA OFFSET:
--
--     py - camY' = (py - camY) * sin - rise
--     camY'      = camY + (py - camY) * (1 - sin) + rise
--
-- which is algebraically the same projection and touches one seam instead of
-- every sprite path. TEST THE BEHAVIOUR, NOT THE NAME OF THE FUNCTION THAT
-- MIGHT HAVE IMPLEMENTED IT -- a check written against an implementation it
-- expected will call correct code broken.
local ow = stripComments(port("src/world/OverworldController.lua") or "")
ok(#ow > 0, "OverworldController.lua could not be read")

ok(ow:find("ground:scale()", 1, true) or ow:find("groundForRise:scale()", 1, true),
   "nothing asks the Gen 4 ground for its scale, so no sprite can be compressed "
   .. "to match it")
-- The (1 - sin) term is the compression itself.
ok(ow:find("(1 - groundSin)", 1, true),
   "the per-entity camera offset no longer carries the (1 - sin) term -- without "
   .. "it a character drifts off the ground by z*(1-sin), which is 36 px at "
   .. "sixteen tiles")
-- ...and the terrain lift, which is the other half of standing on something.
ok(ow:find(":rise(", 1, true),
   "nothing asks the ground how high the terrain is under an entity")

-- BOTH DRAW PATHS HAVE TO APPLY IT. `riseOf` used to be a local inside the flat
-- path while the tilt path drew at a plain `cam.y`, so turning tilt on detached
-- every Sinnoh character from the ground again. `Tilt.active()` is
-- `level > 0 or angle > 0` -- a player option with no generation gate -- so that
-- path is reachable on any Platinum map.
local corrected = 0
for _ in ow:gmatch("cam%.y %+ riseOf%(e%)") do corrected = corrected + 1 end
ok(corrected >= 2,
   "only %d entity draw call(s) add riseOf -- the flat path and the tilt path "
   .. "both draw characters and both need it", corrected)
local bare = 0
for _ in ow:gmatch("e:draw%(cam%.x, cam%.y%)") do bare = bare + 1 end
ok(bare == 0,
   "%d entity draw call(s) still pass a bare cam.y, so those sprites are not "
   .. "projected with the ground", bare)

-- The size of the drift the correction is cancelling, so it stays a number.
local function groundPx(z) return z * s end
local function spritePx(z) return z end
for _, tiles in ipairs({ 4, 8, 16 }) do
  local z = tiles * 16
  local drift = spritePx(z) - groundPx(z)
  ok(abs(drift - z * (1 - s)) < 1e-6,
     "the uncorrected drift at %d tiles is %.2f px, expected z*(1-sin) = %.2f",
     tiles, drift, z * (1 - s))
end
local driftAt16 = 256 * (1 - s)
ok(abs(driftAt16 - 36.4) < 0.2,
   "the uncorrected drift at sixteen tiles is %.2f px, expected 36.4 (2.28 tiles)",
   driftAt16)

-- ---------------------------------------------------------------------------
section("5. what a screen actually covers")
-- ---------------------------------------------------------------------------
-- The cartridge fits 223.9 world units of ground into 192 rows; the flat grid
-- fits 192. That 1.166x is the "zoomed in" half of the play report.
local coversCart = Cam.SCREEN_H / s
ok(abs(coversCart - 223.9) < 0.5,
   "192 rows cover %.1f world units under the cartridge projection, expected 223.9",
   coversCart)
ok(abs(coversCart / Cam.SCREEN_H - 1 / s) < 1e-9,
   "the extra ground a compressed view shows is not exactly 1/sin")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
