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
  disabled = {},     -- name -> true when switched off
  enabled = true,    -- master switch
  installed = false,
  reported = {},
}

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
  return scene
end

local function runScene(ground, view, vw, vh)
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
  local began = Voxel3D.beginScene(vw, vh, view.x, view.z, vw, vh, nil, "current")
  if not began then
    Voxel3D.camera = saved
    return
  end
  local scene = buildScene(ground, view, vw, vh)
  for _, name in ipairs(Bridge.order) do
    if not Bridge.disabled[name] then
      local ok, err = pcall(Bridge.effects[name], scene)
      if not ok then
        report("fx:" .. name, "effect '%s' failed: %s", name, tostring(err))
        Bridge.disabled[name] = true      -- don't fail every frame
      end
    end
  end
  Voxel3D.endScene()
  Voxel3D.camera = saved
end

function Bridge.run(ground)
  if not (Bridge.enabled and #Bridge.order > 0) then return end
  local view, vw, vh = ground.view3d, ground.freeW, ground.freeH
  if not (view and vw and vh and view.matrix and view.forward) then return end
  if not Bridge.isGen4() then return end
  local ok, err = pcall(runScene, ground, view, vw, vh)
  if not ok then
    -- make sure a throw between beginScene/endScene can't leave state behind
    pcall(Voxel3D.endScene)
    report("scene", "scene failed: %s", tostring(err))
  end
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

  local original = Ground.endFree
  Ground.endFree = function(self, ...)
    -- Runs while the free canvas is still open (colour + depth): terrain,
    -- buildings and characters are already in it. See the header.
    if Ground.freeOpen and self and self.freeW then Bridge.run(self) end
    return original(self, ...)
  end
  Bridge.installed = true
  return true
end

function Bridge.uninstall()
  if not Bridge.installed then return end
  Bridge.Ground.endFree = Bridge.originalEndFree
  Bridge.Ground.forMap = Bridge.originalForMap
  Bridge.installed = false
end

return Bridge
