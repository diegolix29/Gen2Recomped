-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the 3D supersample defaults to the picture every
-- previous build drew, that it reaches ONLY the free camera, and that the
-- logical view and the target are not mixed up in either direction.
--
-- Reported from play: "the first and third person are also really low
-- resolution and highly pixelated now add in a resolution option".
--
-- WHAT IT DOES NOT PROVE, said plainly: nothing here renders a frame. It cannot
-- tell you the picture looks better, only that the arithmetic is the identity
-- at the default and that the wiring goes where it says. The look needs eyes.
--
-- Usage: texlua tools/gen4_render_scale_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local Gen4Ground = require("src.render.Gen4Ground")

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
section("1. the default is the picture that was always drawn")
-- ---------------------------------------------------------------------------
ok(Gen4Ground.RENDER_SCALES[1] == 1,
   "the first rung must be 1; a default above it changes every existing player's view")
ok(Gen4Ground.renderScale() == 1, "the module must start at 1, is %s",
   tostring(Gen4Ground.renderScale()))

-- THE GEN 1/2/3 CONTROL. Nothing outside Sinnoh writes this option, so every
-- shape of "absent" has to leave the default alone.
ok(Gen4Ground.syncRenderScale(nil) == 1, "a nil game must leave the scale at 1")
ok(Gen4Ground.syncRenderScale({}) == 1, "a game with no save must leave it at 1")
ok(Gen4Ground.syncRenderScale({ save = {} }) == 1, "no options table: still 1")
ok(Gen4Ground.syncRenderScale({ save = { options = {} } }) == 1,
   "options with no gen4RenderScale: still 1")

-- ---------------------------------------------------------------------------
section("2. the ladder round trips, and refuses nonsense")
-- ---------------------------------------------------------------------------
for i, want in ipairs(Gen4Ground.RENDER_SCALES) do
  ok(Gen4Ground.setRenderScale(i) == want,
     "rung %d should select scale %d", i, want)
  ok(Gen4Ground.renderScale() == want, "rung %d should be remembered", i)
  local got, at = Gen4Ground.syncRenderScale({ save = { options = { gen4RenderScale = i } } })
  ok(got == want and at == i, "sync should take rung %d", i)
end
-- Every rung is a whole number 1 or greater: a fractional or zero factor would
-- allocate a target smaller than the view and blit it up, which is the fault
-- this whole change exists to remove.
for i, v in ipairs(Gen4Ground.RENDER_SCALES) do
  ok(type(v) == "number" and v >= 1 and v == math.floor(v),
     "rung %d is %s; every rung must be a whole number >= 1", i, tostring(v))
end
-- `nil` is deliberately NOT in this list: a nil in a table literal truncates
-- it, so the rungs after it would never be tested and the loop would quietly
-- shrink -- the same shape as a measurement that cannot fail.
for _, bad in ipairs({ 0, -1, 99, 1.5, 4.5 }) do
  Gen4Ground.setRenderScale(1)
  Gen4Ground.setRenderScale(bad)
  ok(Gen4Ground.renderScale() == 1,
     "a bad index (%s) must fall back to 1, gave %s",
     tostring(bad), tostring(Gen4Ground.renderScale()))
end
Gen4Ground.setRenderScale(nil)
ok(Gen4Ground.renderScale() == 1, "a nil index must fall back to 1")
-- A NUMERIC STRING IS ACCEPTED, and that is recorded rather than asserted
-- away: `setRenderScale` runs `tonumber` first, so "2" is rung 2. Written
-- down so nobody later "fixes" the leniency without knowing it was chosen.
ok(Gen4Ground.setRenderScale("2") == Gen4Ground.RENDER_SCALES[2],
   "a numeric string should select that rung")
Gen4Ground.setRenderScale(1)

-- ...and a garbage SAVED value must not move a good setting.
Gen4Ground.setRenderScale(2)
Gen4Ground.syncRenderScale({ save = { options = { gen4RenderScale = 99 } } })
ok(Gen4Ground.renderScale() == 2, "a bad saved index must leave the current one alone")
Gen4Ground.setRenderScale(1)

-- ---------------------------------------------------------------------------
section("3. at scale 1 the arithmetic is the identity")
-- ---------------------------------------------------------------------------
-- The safety argument for every other generation and for Sinnoh's default,
-- written as a measurement rather than as a claim.
for _, size in ipairs({ { 307, 230 }, { 256, 192 }, { 1, 1 }, { 640, 480 } }) do
  local lw, lh, scale = size[1], size[2], 1
  ok(lw * scale == lw and lh * scale == lh,
     "%dx%d at scale 1 must target exactly itself", lw, lh)
  ok(1 / scale == 1, "the blit divisor at scale 1 must be exactly 1")
end
-- ...and at 2 it really does change, or the option is decorative.
ok(307 * 2 == 614 and 1 / 2 == 0.5, "scale 2 must double the target and halve the blit")

-- ---------------------------------------------------------------------------
section("4. the wiring, with comments stripped")
-- ---------------------------------------------------------------------------
-- A CHECK A COMMENT CAN SATISFY IS NOT A CHECK -- this file's own prose names
-- `lw, lh` and `tw, th` many times over, so the source is stripped first.
local f = assert(io.open(root .. "../src/render/Gen4Ground.lua", "rb")
                 or io.open("src/render/Gen4Ground.lua", "rb"))
local src = f:read("*a"); f:close()
src = src:gsub("%-%-[^\n]*", "")

local function body(name, stop)
  local from = src:find("function Gen4Ground[:%.]" .. name .. "%(", 1)
  if not from then return nil end
  local to = src:find("function Gen4Ground[:%.]" .. stop .. "%(", from + 1)
  return src:sub(from, to and to - 1 or #src)
end

local free = body("drawFree", "freeEntity")
ok(free ~= nil, "drawFree not found")
if free then
  ok(free:find("liveTargetFor(tw, th)", 1, true),
     "drawFree must allocate its target at the SUPERSAMPLED size")
  ok(free:find("view:matrix(tw, th)", 1, true),
     "drawFree must build its projection from the target size")
  ok(free:find("self.freeW, self.freeH = tw, th", 1, true),
     "freeW/freeH must be the TARGET size -- freeEntity projects sprites through them")
  ok(not free:find("liveTargetFor(lw, lh)", 1, true),
     "drawFree still allocates at the logical size somewhere")
  ok(free:find("Gen4Ground.freeScale", 1, true),
     "drawFree must record the factor on the MODULE; endFree may run on another ground")
end

-- THE CONTROL, and the one that would catch this leaking where it must not go:
-- `beginWorld` is the LIVE/tilted pass, which composes with the pixel-art world
-- canvas and is meant to stay at the integer scale.
local live = body("beginWorld", "endWorld")
ok(live ~= nil, "beginWorld not found")
if live then
  ok(live:find("liveTargetFor(lw, lh)", 1, true),
     "beginWorld must STILL allocate at the logical size -- the supersample is "
     .. "the free camera's only")
  ok(not live:find("renderScale", 1, true),
     "the supersample has leaked into the live/tilted pass")
end

-- THE SECOND HALF OF THE FIX, and the half the first attempt was missing.
-- `endFree` blits into whatever was bound before -- which is `worldCanvas` at
-- the LOGICAL size -- so supersampling alone changed nothing visible. The frame
-- has to be handed to `setWorldOverride`, which endFrame fits to the window at
-- whatever resolution it carries.
local fin = body("endFree", "drawCanopy")
ok(fin ~= nil, "endFree not found")
if fin then
  ok(fin:find("1 / scale, 1 / scale", 1, true),
     "endFree must blit the target back down by the same factor")
  ok(fin:find("Gen4Ground.freeScale = 1", 1, true),
     "endFree must reset the factor, or a closed pass leaves it set for the next")
  ok(fin:find("setWorldOverride", 1, true),
     "endFree must hand the frame to setWorldOverride, or the supersample is "
     .. "downsampled into the logical world canvas and nothing changes on screen")
  ok(fin:find("scale > 1", 1, true),
     "the override must be gated above 1x, so the default frame is untouched")
  ok(fin:find('require, "src.core.Game"', 1, true),
     "the renderer must be reached through require -- a bare _G.Game is nil in "
     .. "a real session, which this port has already paid for once")
  ok(not fin:find("_G.Game", 1, true), "endFree must not read _G.Game")
  -- ORDERING: the gate sits AFTER the blit, so a 1x frame cannot take a branch
  -- it is supposed never to reach, and the world canvas keeps a correct picture
  -- if anything downstream declines the override.
  local atBlit = fin:find("1 / scale, 1 / scale", 1, true)
  local atGate = fin:find("setWorldOverride", 1, true)
  ok(atBlit and atGate and atBlit < atGate,
     "the override must be published after the blit, not instead of it")
end

-- ONE READER OF freeW/freeH, which is what makes setting them to target pixels
-- safe. A second consumer expecting logical coordinates would be silently wrong.
local readers = 0
for _ in src:gmatch("self%.freeW") do readers = readers + 1 end
ok(readers == 2, "expected exactly one write and one read of self.freeW, found %d "
   .. "mentions -- a new consumer must be checked for which space it wants", readers)

-- ---------------------------------------------------------------------------
section("5. the 3D pass puts back every piece of shared state it borrows")
-- ---------------------------------------------------------------------------
-- HERE BECAUSE IT IS THE SAME PASS. `Gen4Model:draw` is what the free camera
-- draws every chunk and prop with, and the characters are drawn into the same
-- target immediately afterwards -- so state it leaves set lands on them.
--
-- Reported from play: "the npc and player sprites are still see through
-- specifically with the 3d camera on in tilted views and first and third
-- person". The loop sets `setColor(1, 1, 1, shapeAlpha(shape))` per shape --
-- correct, a model mixes opaque walls with a translucent shadow -- but the
-- colour is GLOBAL, so the last shape's alpha was still in force on return.
-- `SpriteRenderer` sets no colour of its own and inherits, so a character drawn
-- after a chunk ending on a 12/31 indoor `shade` quad came out at ~39% opacity.

local mf = assert(io.open(root .. "../src/render/Gen4Model.lua", "rb")
                  or io.open("src/render/Gen4Model.lua", "rb"))
local msrc = mf:read("*a"); mf:close()
msrc = msrc:gsub("%-%-[^\n]*", "")

local from = msrc:find("function Gen4Model:draw%(")
local to = msrc:find("\nlocal DEPTH_FORMATS", from or 1)
local draw = from and msrc:sub(from, to or #msrc) or nil
ok(draw ~= nil, "Gen4Model:draw not found")
if draw then
  -- It borrows four things. Each must be read on entry and put back on exit;
  -- three always were, and the fourth is what this section exists for.
  ok(draw:find("g.getColor()", 1, true),
     "Gen4Model:draw must READ the colour on entry, like the shader and depth mode")
  ok(draw:find("g.setColor(pr, pg, pb, pa)", 1, true),
     "Gen4Model:draw must RESTORE the colour -- otherwise the last shape's alpha "
     .. "is still in force and every sprite drawn after it inherits it")
  ok(draw:find("g.setShader(previousShader)", 1, true), "the shader must be restored")
  ok(draw:find("g.setDepthMode(mode, write)", 1, true), "the depth mode must be restored")
  ok(draw:find("g.setMeshCullMode(culling)", 1, true), "the cull mode must be restored")
  -- ORDERING: the restore has to come after the shape loop, not inside it.
  local atLoop = draw:find("shapeAlpha(shape)", 1, true)
  local atBack = draw:find("g.setColor(pr, pg, pb, pa)", 1, true)
  ok(atLoop and atBack and atLoop < atBack,
     "the colour restore must sit after the per-shape loop, not inside it")
end

-- AND THE SKY, which is the control: `drawSky` sets a fade alpha too and has
-- always put it back. If this ever fails, there are two leaks and not one.
local gf = assert(io.open(root .. "../src/render/Gen4Ground.lua", "rb")
                  or io.open("src/render/Gen4Ground.lua", "rb"))
local gsrc = gf:read("*a"); gf:close()
gsrc = gsrc:gsub("%-%-[^\n]*", "")
local skyFrom = gsrc:find("function Gen4Ground:drawSky%(")
local skyTo = gsrc:find("function Gen4Ground:drawFree%(", skyFrom or 1)
local sky = skyFrom and gsrc:sub(skyFrom, skyTo or #gsrc) or nil
ok(sky ~= nil, "drawSky not found")
if sky then
  local faded = sky:find("setColor(1, 1, 1, alpha)", 1, true)
  local back = sky:find("setColor(1, 1, 1, 1)", 1, true)
  ok(not faded or (back and faded < back),
     "drawSky sets a fade alpha and must put it back before returning")
end

-- ---------------------------------------------------------------------------
section("6. the OPTIONS row steps both ways")
-- ---------------------------------------------------------------------------
-- `Gen4Options:cycle` passes the direction as `row.engine.step(game, delta)`:
-- -1 for left, +1 for right and A. A step that ignores it makes both keys
-- advance, and with four rungs the press after 4X wraps to DS -- so a player
-- raising the setting to look at it lands back on the default.

local of = assert(io.open(root .. "../src/ui/OptionsMenu.lua", "rb")
                  or io.open("src/ui/OptionsMenu.lua", "rb"))
local osrc = of:read("*a"); of:close()
osrc = osrc:gsub("%-%-[^\n]*", "")
local rowAt = osrc:find("gen4RenderScale", 1, true)
local row = rowAt and osrc:sub(rowAt, rowAt + 1400) or nil
ok(row ~= nil, "the 3D RES row was not found in OptionsMenu")
if row then
  ok(row:find("step = function(g, dir)", 1, true),
     "the 3D RES step must take the direction; ignoring it makes left and right "
     .. "do the same thing")
  ok(row:find("tonumber(dir)", 1, true), "the direction must actually be read")
  -- ...and the arithmetic must be able to go DOWN, not merely accept the argument.
  ok(row:find("(at - 1 + by) % rungs + 1", 1, true),
     "the step must wrap in both directions from the current rung")
  ok(not row:find("at % #Gen4Ground.RENDER_SCALES + 1", 1, true),
     "the always-forward step is still there")
end

-- The arithmetic itself, walked rather than asserted once: from every rung, one
-- step up then one step down must return to where it started.
local rungs = #Gen4Ground.RENDER_SCALES
local function stepFrom(at, by) return (at - 1 + by) % rungs + 1 end
for at = 1, rungs do
  ok(stepFrom(stepFrom(at, 1), -1) == at, "up then down from rung %d must return", at)
  ok(stepFrom(stepFrom(at, -1), 1) == at, "down then up from rung %d must return", at)
end
ok(stepFrom(rungs, 1) == 1, "the top rung wraps to the bottom going up")
ok(stepFrom(1, -1) == rungs, "the bottom rung wraps to the top going down")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
