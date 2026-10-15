-- Gen4Bridge: Terrarium's effects, drawn INTO the engine's own Gen 4 world.
--
-- WHY THIS EXISTS
--
-- On Gen 1/2/3 this mod builds the 3D world itself: it extrudes the tilemap
-- into voxels and owns the frame through the `voxel` render pipeline. Gen 4
-- (Platinum) already has a real 3D world -- src/render/Gen4Ground.lua draws
-- terrain and buildings from the cartridge's own models through a real camera
-- (src/render/Gen4View.lua) -- so there is nothing to extrude, and letting the
-- voxel pipeline take the world pass would REPLACE that world with a voxelised
-- tilemap. So on Gen 4 the `voxel` pipeline stands down (see main.lua:
-- `available`) and this module runs instead. It adds effects on top of the
-- engine's world and never replaces any of it.
--
-- HOW IT HOOKS IN (engine untouched)
--
-- In a free camera (third / first person, and every numeric CAM TILT rung)
-- Gen4Ground:drawFree() leaves its canvas OPEN -- colour + depth -- while the
-- overworld draws characters into it, and Gen4Ground:endFree() closes it. This
-- module wraps endFree(): just before the original runs, the canvas still holds
-- terrain + buildings + characters with a live depth buffer, so anything drawn
-- now is depth-tested against the real scene. That is the whole seam.
--
-- The mod's own shader renderer (Voxel3D) already has an "external target"
-- mode (beginScene with slot "current") that draws into whatever canvas is
-- bound, and an explicit-camera mode (Voxel3D.camera with view/proj). We feed
-- it Gen4View's own view-projection matrix, so a mesh placed at a Gen 4 world
-- position lands exactly where the engine would put it, and every uniform the
-- shader takes (wind, water, tint, glass mask, lamps, fog) keeps working.
--
-- Coordinates are shared: +x east, +y up, +z south, one unit per map pixel,
-- sixteen per tile -- the voxel scene's convention too. A Gen 4 map adds its
-- matrix origin (ground.offsetX / offsetY) to a map-pixel position.
--
-- NOT COVERED YET: the CARTRIDGE (oblique) rung, where Gen4Ground bakes chunks
-- with its own depth units. Effects only draw when the camera is a free one.
-- See GEN4_PORT_NOTES.md.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local Bridge = {
  effects = {},      -- name -> draw(scene)
  order = {},        -- registration order == draw order
  pre = {},          -- name -> draw(scene): effects drawn BEFORE the terrain (the sky),
  preOrder = {},     -- into the same open Voxel3D scene, see Bridge.runPre
  stats = { runs = 0, pres = 0 },   -- passes actually run; ArenaOverworldSnapshot reports them
  after = {},        -- fn(ground, view, vw, vh): screen passes run once the effects
                     -- are drawn and BEFORE the engine blits the frame (Gen4Reflect)
  disabled = {},     -- name -> true when switched off
  enabled = true,    -- master switch
  installed = false,
  reported = {},
  lastRunFrame = {}, -- ground -> frame id to prevent duplicate calls per frame
  lastPreFrame = {}, -- ground -> frame id for pre-pass
}

-- The shared per-frame build budget (lib/Gen4Budget.lua). Resolved once.
local budgetMod
local function budget()
  if not budgetMod then
    local ok, B = pcall(V.require, "Gen4Budget")
    if ok and type(B) == "table" then budgetMod = B end
  end
  return budgetMod
end

-- True while a warp fade hides the world: nothing on screen to hitch, so the
-- budget may spend much more building meshes. Only `transitioning` is read (the
-- same flag main.lua's own COVERED test uses for warps); the stack-top test is
-- left out on purpose, because a Gen 4 world can run with an empty stack and
-- that would read as "covered" for the whole game.
local function worldCovered()
  local okG, Game = pcall(require, "src.core.Game")
  local ow = okG and type(Game) == "table" and Game.overworld or nil
  return (ow and ow.transitioning) and true or false
end

-- Gen4Sun: the Gen 4 half of lib/ShadowMap + lib/Shadows. VoxelScene fills the
-- map on Gen 1-3 and never runs here, so this is what gives a Platinum map its
-- cast shadows. Resolved once; nil if the module will not load (no shadows,
-- everything else keeps working).
local sunMod, sunTried
local function sun()
  if not sunTried then
    sunTried = true
    local ok, S = pcall(V.require, "Gen4Sun")
    if ok and type(S) == "table" then sunMod = S
    elseif V.mod and V.mod.log then
      V.mod.log:warn("Gen4Bridge: shadows unavailable: " .. tostring(S))
    end
  end
  return sunMod
end
Bridge.sun = sun

local function frameEnd()
  local B = budget()
  if not B then return end
  B.covered = worldCovered()      -- read by the NEXT frame's builds
  B.nextFrame()
end

local function report(key, fmt, ...)
  if Bridge.reported[key] then return end
  Bridge.reported[key] = true
  if V.mod and V.mod.log then
    V.mod.log:warn("Gen4Bridge: " .. fmt:format(...))
  end
end

-- ------------------------------------------------------------ detection --

local function generation()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and GameVersion and GameVersion.generation) then return nil end
  local okGen, value = pcall(GameVersion.generation)
  return okGen and tonumber(value) or nil
end

function Bridge.isGen4()
  return generation() == 4
end

-- True when this module owns Terrarium's world-side effects: a Gen 4 game AND
-- the hook is in. main.lua's `voxel` pipeline asks this to stand down.
function Bridge.active()
  return Bridge.installed and Bridge.isGen4()
end

-- ------------------------------------------------------------- registry --

-- register(name, drawFn [, opts]). drawFn(scene) runs inside an open Voxel3D
-- scene (shader bound, depth test on, depth write on). Effects that blend
-- (glass, water) should call scene.blend() first and scene.opaque() after.
function Bridge.register(name, fn)
  if type(fn) ~= "function" then return false end
  if not Bridge.effects[name] then Bridge.order[#Bridge.order + 1] = name end
  Bridge.effects[name] = fn
  return true
end

-- registerPre(name, drawFn): like register, but the effect runs BEFORE the first
-- terrain shape of the frame (Gen4Sky's hook calls Bridge.runPre then), with the
-- depth buffer still clear. Nothing is drawn over yet, so the effect is the
-- backdrop: everything the engine draws afterwards covers it. Same scene, same
-- error isolation as register.
function Bridge.registerPre(name, fn)
  if type(fn) ~= "function" then return false end
  if not Bridge.pre[name] then Bridge.preOrder[#Bridge.preOrder + 1] = name end
  Bridge.pre[name] = fn
  return true
end

function Bridge.setEffect(name, on)
  Bridge.disabled[name] = (on == false) or nil
end

-- --------------------------------------------------------------- scene --

local FOCUS_DISTANCE = 128   -- only used to give Voxel3D an eye->focus vector

local function buildScene(ground, view, vw, vh)
  local offX, offZ = ground.offsetX or 0, ground.offsetY or 0
  local fx, fy, fz = view:forward()
  local scene = {
    ground = ground, view = view, vw = vw, vh = vh,
    map = ground.terrariumMap,            -- tagged in install(); may be nil
    offsetX = offX, offsetZ = offZ,
    eye = { view.x, view.y, view.z },
    forward = { fx, fy, fz },
    clock = ground.clock,
    Voxel3D = Voxel3D, Mat4 = Mat4,
  }
  -- map pixel -> world x,z
  function scene.toWorld(px, py) return px + offX, py + offZ end
  -- terrain height (world units) at a map-pixel position
  function scene.groundY(px, py) return ground:groundY(px, py) end
  -- where the view ray meets the ground, in MAP PIXELS: the centre for culling.
  function scene.focusPx()
    local ex, ez = view.x - offX, view.z - offZ
    local gy = ground:groundY(ex, ez) or 0
    if fy < -0.05 then
      local t = math.min((view.y - gy) / -fy, 900)
      return ex + fx * t, ez + fz * t
    end
    return ex + fx * 160, ez + fz * 160
  end
  -- Voxel3D.depth() only knows "always" and test+write, so a blended pass
  -- (glass, water: tested against the scene but never written) sets the mode
  -- itself. The scene is open when these run, so the shader stays bound.
  function scene.blend()
    love.graphics.setDepthMode("lequal", false)
  end
  function scene.opaque()
    love.graphics.setDepthMode("lequal", true)
  end
  -- scene.sphereVisible(x, y, z, r): false only when a sphere (world units) is
  -- well outside the view. Effects use it to skip whole chunks the camera cannot
  -- see (see Gen4Cull). Absent when the view's fov is unreadable: callers must
  -- treat nil as "draw everything".
  do
    local okC, Cull = pcall(V.require, "Gen4Cull")
    local fovRad
    if type(view.effectiveFovY) == "function" then
      local okF, f = pcall(view.effectiveFovY, view, vh)
      if okF and tonumber(f) then fovRad = math.rad(f) end
    end
    if okC and type(Cull) == "table" and fovRad then
      scene.sphereVisible = Cull.sphereTest(scene.eye, scene.forward, fovRad,
                                            (tonumber(vw) or 1) / math.max(tonumber(vh) or 1, 1))
    end
  end
  return scene
end

local function runScene(ground, view, vw, vh, order, effects, tag)
  local vp = view:matrix(vw, vh)          -- Gen4's world->clip, Y already flipped
  local fx, fy, fz = view:forward()
  local saved = Voxel3D.camera
  Voxel3D.camera = {
    eye = { view.x, view.y, view.z },
    focus = { view.x + fx * FOCUS_DISTANCE, view.y + fy * FOCUS_DISTANCE,
              view.z + fz * FOCUS_DISTANCE },
    fov = math.rad(view:effectiveFovY(vh)),
    curve = 0,                            -- Gen 4 draws a flat world: no horizon bend
    -- Voxel3D.viewProjection returns S * proj * view with S = scale(1,-1,1).
    -- Gen4View:matrix already applied that flip, so cancel it here:
    -- S * (S * vp) * I == vp.
    view = Mat4.identity(),
    proj = Mat4.mul(Mat4.scale(1, -1, 1), vp),
  }

  -- Street-lamp flames from Gen4Lawn post ids only (c1_o02 / c1_o02b).
  -- Building brightness is c1_lamp01 / c1_lamp02 via Gen4Glass + Tint.
  local lampLights = {}
  local lightScene = { ground = ground, view = view }
  -- the post is drawn at Gen4Lamps.SCALE, so its flame is that much higher than
  -- the bake's own lantern height
  local okH, flameY = pcall(function() return V.require("Gen4Lamps").flameOffset() end)
  if okH and tonumber(flameY) then Voxel3D.lampHeight = flameY end
  if Bridge.lampCollector then
    local okL, lamps = pcall(Bridge.lampCollector, lightScene)
    if okL and type(lamps) == "table" then
      for _, l in ipairs(lamps) do lampLights[#lampLights + 1] = l end
    end
  end
  table.sort(lampLights, function(a, b) return (a.d2 or 0) < (b.d2 or 0) end)
  for i = #lampLights, 9, -1 do lampLights[i] = nil end
  Voxel3D.lampLights = #lampLights > 0 and lampLights or nil
  Voxel3D.lampFlicker = (#lampLights > 0) and 1 or 0

  local began = Voxel3D.beginScene(vw, vh, view.x, view.z, vw, vh, nil, "current")
  if not began then
    Voxel3D.camera = saved
    if tag == "fx:" then
      pcall(function() V.require("Gen4Tint").feed(nil) end)
    end
    return
  end
  if tag == "fx:" then
    local okC, col = pcall(function() return V.require("DayNight").lampColor() end)
    if okC then Voxel3D.lampColor = col end
  end
  local scene = buildScene(ground, view, vw, vh)
  local Sun = sun()
  for _, name in ipairs(order) do
    if not Bridge.disabled[name] then
      -- the meshes these effects draw are recorded as shadow casters (the sun
      -- pass at the top of next frame's drawFree replays them)
      if Sun and tag == "fx:" then Sun.capturing = Sun.CASTING[name] == true end
      local ok, err = pcall(effects[name], scene)
      if not ok then
        report(tag .. name, "effect '%s' failed: %s", name, tostring(err))
        Bridge.disabled[name] = true      -- don't fail every frame
      end
    end
  end
  if Sun then
    Sun.capturing = false
    -- the receiver goes last: it darkens the engine's terrain where the map
    -- says the sun does not reach, after everything that can stand in the way
    if tag == "fx:" and not Bridge.disabled["shadows"] then
      local okR, errR = pcall(Sun.receive, scene)
      if not okR then
        report("shadows", "the shadow receiver failed: %s", tostring(errR))
        Bridge.disabled["shadows"] = true
      end
    end
  end
  -- Native Gen 4 city never samples Voxel3D.lampLights. Tint gets street
  -- posts AND building wall-lights after the night multiply.
  if tag == "fx:" then
    local lights = {}
    local okW, world = pcall(function() return V.require("Gen4Lamps").worldLights() end)
    if okW and type(world) == "table" then
      for _, l in ipairs(world) do lights[#lights + 1] = l end
    elseif #lampLights > 0 then
      for _, l in ipairs(lampLights) do lights[#lights + 1] = l end
    end
    local okG, panes = pcall(function()
      return V.require("Gen4Glass").screenLights(view.x, view.z)
    end)
    if okG and type(panes) == "table" then
      for _, l in ipairs(panes) do lights[#lights + 1] = l end
    end
    pcall(function() V.require("Gen4Tint").feed(lights, vw, vh) end)
  end
  Voxel3D.endScene()
  Voxel3D.camera = saved
  Voxel3D.lampLights = nil  -- Clean up after the scene
end

function Bridge.run(ground)
  if not (Bridge.enabled and #Bridge.order > 0) then return end
  local view, vw, vh = ground.view3d, ground.freeW, ground.freeH
  if not (view and vw and vh and view.matrix and view.forward) then return end
  if not Bridge.isGen4() then return end

    -- Prevent duplicate calls in the same frame to fix flickering on desktop
  local frameId = ground.clock or (love and love.timer and love.timer.getTime() and love.timer.getTime())
  if Bridge.lastRunFrame[ground] == frameId then return end
  Bridge.lastRunFrame[ground] = frameId

  Bridge.stats.runs = Bridge.stats.runs + 1
  local ok, err = pcall(runScene, ground, view, vw, vh, Bridge.order, Bridge.effects, "fx:")
  if not ok then
    -- make sure a throw between beginScene/endScene can't leave state behind
    pcall(Voxel3D.endScene)
    report("scene", "scene failed: %s", tostring(err))
  end
  for i, fn in ipairs(Bridge.after) do
    local okA, errA = pcall(fn, ground, view, vw, vh)
    if not okA then
      report("after:" .. i, "screen pass %d failed: %s", i, tostring(errA))
    end
  end
end

-- The pre-terrain pass. Called by Gen4Sky from inside Gen4Ground:drawFree, on the
-- first terrain shape, while the free canvas is bound and its depth is clear.
-- Returns true when the scene ran.
function Bridge.runPre(ground)
  if not (Bridge.enabled and #Bridge.preOrder > 0) then return false end
  local view, vw, vh = ground.view3d, ground.freeW, ground.freeH
  if not (view and vw and vh and view.matrix and view.forward) then return false end
  if not Bridge.isGen4() then return false end

  -- Prevent duplicate calls in the same frame to fix flickering on desktop
  local frameId = ground.clock or (love and love.timer and love.timer.getTime() and love.timer.getTime())
  if Bridge.lastPreFrame[ground] == frameId then return false end
  Bridge.lastPreFrame[ground] = frameId

  Bridge.stats.pres = Bridge.stats.pres + 1
  local ok, err = pcall(runScene, ground, view, vw, vh, Bridge.preOrder, Bridge.pre, "pre:")
  if not ok then
    pcall(Voxel3D.endScene)
    report("prescene", "pre-terrain scene failed: %s", tostring(err))
    return false
  end
  return true
end

-- ------------------------------------------------------------- install --

function Bridge.install()
  if Bridge.installed then return true end
  local ok, Ground = pcall(require, "src.render.Gen4Ground")
  if not (ok and type(Ground) == "table" and type(Ground.endFree) == "function") then
    return false      -- not a Gen 4 build of the engine: nothing to hook
  end
  Bridge.Ground = Ground
  Bridge.originalEndFree = Ground.endFree
  Bridge.originalForMap = Ground.forMap

  -- Tag each ground with the Map it was built for; effects need the map's
  -- cell queries (grass, water) and Gen4Ground doesn't keep the map itself.
  if type(Ground.forMap) == "function" then
    local forMap = Ground.forMap
    Ground.forMap = function(map, data, ...)
      local g = forMap(map, data, ...)
      if g then g.terrariumMap = map end
      return g
    end
  end

  -- Only the newest install is live; a wrapper left over from an earlier run of
  -- this file (mod reload) passes straight through instead of drawing every
  -- effect a second time.
  local token = {}
  Ground.__terrariumBridgeToken = token

  local original = Ground.endFree
  Ground.endFree = function(self, ...)
    if Ground.__terrariumBridgeToken ~= token then return original(self, ...) end
    -- Runs while the free canvas is still open (colour + depth): terrain,
    -- buildings and characters are already in it. See the header.
    if Ground.freeOpen and self and self.freeW then Bridge.run(self) end
    -- close the frame's shared build budget after the engine has finished with
    -- the canvas, and pass every return value of the original through
    local function finish(...)
      frameEnd()
      return ...
    end
    return finish(original(self, ...))
  end
  Bridge.installed = true

  -- The passes that belong to every Gen 4 game, registered here so they are
  -- FIRST in draw order: the water sheet is opaque and writes depth, and what
  -- main.lua registers after install() (grass, the battle actors) draws over it.
  local okW, GW = pcall(V.require, "Gen4Water")
  if okW and type(GW) == "table" and GW.draw then
    Bridge.register("water", GW.draw)
  else
    report("water", "the water pass did not load: %s", tostring(GW))
  end
  -- The voxel scene's textured ground on the beach sand. Opaque, so it goes
  -- before grass and the actors, after the water it may sit beside.
  local okS, GS = pcall(V.require, "Gen4Sand")
  if okS and type(GS) == "table" and GS.draw then
    Bridge.register("sand", GS.draw)
  else
    report("sand", "the sand pass did not load: %s", tostring(GS))
  end
  -- Neighbour-tile blend skirts for Gen4Lawn swaps (grass/road/sand seams).
  local okL, GL = pcall(V.require, "Gen4Lawn")
  if okL and type(GL) == "table" and GL.draw then
    Bridge.register("lawn", GL.draw)
  else
    report("lawn", "the lawn blend pass did not load: %s", tostring(GL))
  end
  -- Small dirt piles on Platinum jump-down ledges (`criff` / `criffp`). Opaque,
  -- after the lawn, before the trees.
  local okB, GB = pcall(V.require, "Gen4Bump")
  if okB and type(GB) == "table" and GB.draw then
    Bridge.register("bump", GB.draw)
  else
    report("bump", "the bump pass did not load: %s", tostring(GB))
  end
  -- The voxel scene's 3D trees in place of Platinum's flat tree cards. Opaque,
  -- after the ground passes, before grass and the actors.
  local okT, GT = pcall(V.require, "Gen4Trees")
  if okT and type(GT) == "table" and GT.draw then
    Bridge.register("trees", GT.draw)
  else
    report("trees", "the tree pass did not load: %s", tostring(GT))
  end
  -- Small grey voxel rocks where Platinum draws its route rocks (`imped`). Opaque,
  -- after the trees. Gen4Lawn hides the native rock card only where these are built.
  local okR, GR = pcall(V.require, "Gen4Rocks")
  if okR and type(GR) == "table" and GR.draw then
    Bridge.register("rocks", GR.draw)
  else
    report("rocks", "the rock pass did not load: %s", tostring(GR))
  end
  -- Real 3D fences (posts, rails or pickets) where Platinum draws its flat fence
  -- banners (`imped`). Opaque, after the rocks. Gen4Hide drops the native banner
  -- only where every card of the shape has a fence built for it.
  local okF, GF = pcall(V.require, "Gen4Fence")
  if okF and type(GF) == "table" and GF.draw then
    Bridge.register("fence", GF.draw)
  else
    report("fence", "the fence pass did not load: %s", tostring(GF))
  end
  -- Small flowers on Gen 4 flower beds (`bed` shapes). Opaque, after the fence.
  local okF2, GFl = pcall(V.require, "Gen4Flowers")
  if okF2 and type(GFl) == "table" and GFl.draw then
    Bridge.register("flowers", GFl.draw)
  else
    report("flowers", "the flower pass did not load: %s", tostring(GFl))
  end
  -- 3D posts on Gen4Lawn's street-lamp ids (`c1_o02` / `c1_o02b`).
  -- Opaque, before the glass overlay.
  local okLp, GLp = pcall(V.require, "Gen4Lamps")
  if okLp and type(GLp) == "table" then
    if GLp.draw then Bridge.register("lamps", GLp.draw) end
    Bridge.lampCollector = GLp.collectLights
  else
    report("lamps", "the lamp collector did not load: %s", tostring(GLp))
  end
  -- Lit windows on Platinum's own buildings (the Gen 4 half of GlassMask).
  -- Blended, after the opaque passes, before grass.
  local okG, GG = pcall(V.require, "Gen4Glass")
  if okG and type(GG) == "table" and GG.draw then
    Bridge.register("glass", GG.draw)
  else
    report("glass", "the glass pass did not load: %s", tostring(GG))
  end
  -- Night light ON Platinum's own roads and walls (world space, depth tested).
  -- After glass so it can use the wall meshes Glass just prepared. Gen4Tint's
  -- screen-space discs stand down while this runs.
  local okLt, GLt = pcall(V.require, "Gen4Light")
  if okLt and type(GLt) == "table" and GLt.draw then
    Bridge.register("light", GLt.draw)
  else
    report("light", "the light receiver did not load: %s", tostring(GLt))
  end
  -- The voxel scene's sky (bands, clouds, sun/moon, stars, painted horizon, scenery)
  -- on Gen 4, with the engine's own horizon image hidden. Pre-terrain, so it is
  -- the backdrop. See lib/Gen4Sky.lua.
  local okK, GK = pcall(V.require, "Gen4Sky")
  if okK and type(GK) == "table" and GK.install then
    local okI, errI = pcall(GK.install)
    if not (okI and errI ~= false) then report("sky", "the sky pass did not install: %s", tostring(errI)) end
  else
    report("sky", "the sky pass did not load: %s", tostring(GK))
  end
  return true
end

-- Drop every baked Gen 4 effect mesh (water, sand, lawn, trees, grass). The voxel
-- pipeline's invalidate used to be the only reset path and it knew none of
-- these, so a graphics reset, a mod reload or a cache reset left the old
-- meshes (and, on a lost GL context, dead ones) in place.
function Bridge.invalidateAll()
  local S = sun()
  if S then pcall(S.invalidate) end
  for _, name in ipairs({ "Gen4Sand", "Gen4Lawn", "Gen4Bump", "Gen4Rocks", "Gen4Fence", "Gen4Flowers", "Gen4Trees", "Gen4Water", "Gen4Grass", "Gen4NpcModels", "Gen4Glass", "Gen4Lamps", "Gen4Light" }) do
    local ok, mod = pcall(V.require, name)
    if ok and type(mod) == "table" and type(mod.invalidate) == "function" then
      local okI, err = pcall(mod.invalidate)
      if not okI then report("inv:" .. name, "%s.invalidate failed: %s", name, tostring(err)) end
    end
  end
end

function Bridge.uninstall()
  if not Bridge.installed then return end
  pcall(function() V.require("Gen4Sky").uninstall() end)
  pcall(function() V.require("Gen4Lawn").uninstall() end)
  local S = sun()
  if S then pcall(S.suspend) end
  Bridge.Ground.__terrariumBridgeToken = nil

  Bridge.Ground.endFree = Bridge.originalEndFree
  Bridge.Ground.forMap = Bridge.originalForMap
  Bridge.installed = false
end

return Bridge