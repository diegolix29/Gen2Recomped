-- Gen4Sun: the two halves of Platinum's cast shadows that the mod's own
-- Voxel3D meshes cannot supply, because the engine draws that part of the
-- world itself.
--
-- THE PROBLEM
--
-- lib/ShadowMap renders "everything that casts" from the sun into a depth
-- map, and lib/Voxel3D's scene shader samples it for everything IT draws.
-- On Gen 1-3 that is the whole world, so shadows land on the ground, climb
-- walls and drape over roofs for free. On Gen 4 the terrain and the
-- buildings are the ENGINE's (src/render/Gen4Ground + Gen4Model, drawn with
-- Gen4Model's own shader), so neither half works there:
--
--   * nothing the engine drew ever reached the sun pass, so a Platinum house
--     threw no shadow; and
--   * nothing the engine drew ever READS the map, so even a tree's shadow had
--     no ground to fall on.
--
-- This module is the two missing pieces. Gen4Bridge owns the frame and the
-- sun pass itself (Gen4Bridge.castShadows); this file holds what that pass
-- needs that is specific to Gen4Ground:
--
--   castBuildings(ShadowMap, ground, box)
--       every building / prop shape the engine has already built, drawn into
--       the open sun pass with the engine's own placement matrices.
--
--   drawReceiver(scene)
--       a Bridge effect: a thin grid laid on the BDHC height map that is
--       drawn as translucent shade wherever the sun map says "shadowed". It
--       is the ground's stand-in for a shader the engine does not let us
--       change. Depth-tested, never depth-writing, so characters, trees and
--       walls drawn earlier still cover it.
--
-- WHAT IT DOES NOT DO: the engine's buildings and terrain do not RECEIVE
-- shadows (a tree's shadow does not climb a wall, a house's shadow does not
-- fall across another house's roof). Only the ground does. The terrain mesh
-- itself does not CAST either -- hills and cliffs throw nothing -- because
-- the terrain is also what the ground receiver is laid on, and casting it
-- would shadow the ground with itself.

local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")

local Sun = {
  -- the ground receiver. Off leaves casting alone (Voxel3D meshes still
  -- receive) but the engine's terrain stays unshaded.
  groundShadows = true,
  -- the engine's buildings and props cast into the sun pass
  castsBuildings = true,
  CELL = 8,            -- receiver grid spacing, world units
  LIFT = 0.75,         -- how far above BDHC height the receiver floats. The
                       -- cartridge's real terrain differs from the height map
                       -- by a unit or so across a slope; under that the shade
                       -- would vanish in patches, over it it would float. This
                       -- errs on floating.
  TINT = { 0.04, 0.05, 0.12 },   -- the shade's colour: near-black, a touch cool
  stats = { cast = 0, shapes = 0, cells = 0 },
}

-- ------------------------------------------------------------- reporting --

local reported = {}
local function once(key, fmt, ...)
  if reported[key] then return end
  reported[key] = true
  if V.mod and V.mod.log and V.mod.log.warn then
    pcall(V.mod.log.warn, V.mod.log, "Gen4Sun: " .. fmt:format(...))
  end
end

-- ------------------------------------------------------------- buildings --

-- Gen4Model's own constant: a shape whose stated alpha is below it is
-- translucent (glass, and the cartridge's blob "kage" shadows), and a pane or
-- a blob of shade must not itself throw a shadow.
local ALPHA_MAX = 31

local function castable(shape)
  if type(shape) ~= "table" or not shape.mesh then return false end
  if shape.matrixSlots then return false end    -- per-vertex skinned (Giratina)
  local a = tonumber(shape.alpha)
  if a and a < ALPHA_MAX then return false end
  local m = tostring(shape.material or ""):lower()
  local t = tostring(shape.texture or ""):lower()
  if m:find("kage", 1, true) or t:find("kage", 1, true) then return false end
  return true
end

-- Gen4Ground's local `placement(object)`, which it does not export: scale,
-- an optional quarter-turn about the vertical (Gen5Field), then translate.
-- Returns nil for a live prop that is hidden this frame.
local function placementOf(object)
  local ox, oy, oz = object.x or 0, object.y or 0, object.z or 0
  local live = object.live
  if live then
    if live.hidden then return nil end
    ox, oy, oz = ox + (live.dx or 0), oy + (live.dy or 0), oz + (live.dz or 0)
  end
  local sx = (object.scaleX and object.scaleX ~= 0) and object.scaleX or 1
  local sy = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
  local sz = (object.scaleZ and object.scaleZ ~= 0) and object.scaleZ or 1
  local yaw = object.rotY and object.rotY ~= 0 and math.rad(object.rotY) or nil
  if yaw then
    local c, s = math.cos(yaw), math.sin(yaw)
    return { c * sx, 0, s * sz, ox,
             0,      sy, 0,     oy,
             -s * sx, 0, c * sz, oz,
             0,      0,  0,     1 }
  end
  return { sx, 0, 0, ox,
           0, sy, 0, oy,
           0, 0, sz, oz,
           0, 0, 0,  1 }
end

local restPoses = setmetatable({}, { __mode = "k" })   -- building -> its rest pose
local function restPoseOf(building)
  local pose = restPoses[building]
  if pose == nil then
    local ok, p = pcall(building.restPose, building)
    pose = (ok and type(p) == "table") and p or false
    restPoses[building] = pose
  end
  return pose or nil
end

-- Draw every building and prop of the chunks that overlap `box` into the OPEN
-- sun pass. `box` is the same { x0, z0, x1, z1 } the pass was fitted to.
--
-- Only buildings the engine has ALREADY built are used (`ground.buildings`
-- is its cache): this runs after the engine's own drawFree in the same frame,
-- so everything on screen is warm, and decoding a model here would put a
-- stall in the sun pass that the engine's pass would otherwise have taken.
function Sun.castBuildings(shadowMap, ground, box)
  if not Sun.castsBuildings then return 0 end
  local grid, terrain = ground and ground.grid, ground and ground.terrain
  local px = ground and ground.chunkPx
  if not (grid and terrain and terrain.chunks and px and px > 0
          and type(ground.objectsFor) == "function") then
    return 0
  end
  local half = ground.half or px / 2
  -- a casting building may stand outside the box and throw INTO it, so the
  -- chunk range is the box widened by the shadow's own reach
  local pad = box.pad or 0
  local cx0 = math.floor((box.x0 - pad) / px)
  local cx1 = math.floor((box.x1 + pad) / px)
  local cy0 = math.floor((box.z0 - pad) / px)
  local cy1 = math.floor((box.z1 + pad) / px)
  local cache = ground.buildings
  local fields = ground.fieldModels
  local drawn, shapes = 0, 0
  for cy = math.max(0, cy0), math.min(grid.height - 1, cy1) do
    for cx = math.max(0, cx0), math.min(grid.width - 1, cx1) do
      local land = grid.land[cy * grid.width + cx + 1]
      local record = land and terrain.chunks[land]
      if record then
        local lift = 0
        if type(ground.chunkLift) == "function" then
          local okL, l = pcall(ground.chunkLift, ground, cx, cy)
          lift = okL and tonumber(l) or 0
        end
        local chunk = Mat4.translate(cx * px + half, lift, cy * px + half)
        local okO, objects = pcall(ground.objectsFor, ground, land, record)
        if okO and type(objects) == "table" then
          for _, object in ipairs(objects) do
            local store = (object.archive == "fldeff") and fields or cache
            local building = store and store[object.model]
            if building then
              local place = placementOf(object)
              if place then
                local base = Mat4.mul(chunk, place)
                local pose = restPoseOf(building)
                for _, shape in ipairs(building.shapes or {}) do
                  if castable(shape) then
                    local m = pose and pose[shape.index]
                    shadowMap.draw(shape.mesh, nil,
                                   m and Mat4.mul(base, m) or base)
                    shapes = shapes + 1
                  end
                end
                drawn = drawn + 1
              end
            end
          end
        end
      end
    end
  end
  Sun.stats.cast, Sun.stats.shapes = drawn, shapes
  return drawn
end

-- --------------------------------------------------------- ground receiver --

local SHADER = [[
  varying highp vec3 vSun;
#ifdef VERTEX
  uniform highp mat4 vp;        // the Gen 4 view-projection (Voxel3D.vp)
  uniform highp mat4 sunVP;     // world -> the sun map's unit cube
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec4 w = vec4(vertex_position.xyz, 1.0);
    vSun = (sunVP * w).xyz;
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform Image sunMap;
  uniform highp float sunBias;
  uniform highp vec2 sunTexel;
  uniform highp float shade;    // Voxel3D.SHADOW_ALPHA: the hour's shadow weight
  uniform highp vec3 shadeColor;
  float sunDepth(vec2 uv) {
    vec4 c = Texel(sunMap, uv);
    return c.r + c.g * (1.0 / 255.0);
  }
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 p = vSun;
    // outside the sun's frustum nothing was recorded, so nothing occludes
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) discard;
    // the same rim fade the scene shader uses, so the covered region does not
    // end on a hard line
    vec2 e = min(p.xy, 1.0 - p.xy);
    float edge = smoothstep(0.0, 0.06, min(e.x, e.y));
    if (edge <= 0.0) discard;
    float z = p.z - sunBias;
    // the scene shader's 2x2 filter: four taps half a texel out on the diagonals
    float lit = step(z, sunDepth(p.xy + sunTexel * vec2(-0.5, -0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5, -0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2(-0.5,  0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5,  0.5)));
    float dark = (1.0 - lit * 0.25) * edge * shade;
    if (dark <= 0.004) discard;
    return vec4(shadeColor, dark);
  }
#endif
]]

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
}

local shader = nil          -- nil = untried, false = unavailable
local function getShader()
  if shader == nil then
    local g = love and love.graphics
    if not (g and g.newShader) then
      shader = false
    else
      local ok, sh = pcall(g.newShader, SHADER)
      if not ok then once("shader", "ground receiver shader failed: %s", tostring(sh)) end
      shader = (ok and sh) or false
    end
  end
  return shader or nil
end

-- Heights of the receiver lattice, per ground, so the BDHC lookup is paid once
-- per vertex rather than once per frame.
local heights = setmetatable({}, { __mode = "k" })     -- ground -> { key -> y | false }
local recv = { mesh = nil, ground = nil, key = nil, cells = 0 }

local function latticeKey(ix, iz)
  return (ix + 8192) * 16384 + (iz + 8192)
end

local function heightAt(ground, store, ix, iz)
  local k = latticeKey(ix, iz)
  local h = store[k]
  if h == nil then
    local wx, wz = ix * Sun.CELL, iz * Sun.CELL
    local ok, y = pcall(ground.groundY, ground, wx - (ground.offsetX or 0), wz - (ground.offsetY or 0))
    h = (ok and tonumber(y)) or false
    store[k] = h
  end
  return h
end

local function releaseMesh()
  if recv.mesh and recv.mesh.release then pcall(recv.mesh.release, recv.mesh) end
  recv.mesh, recv.key, recv.cells = nil, nil, 0
end

-- (Re)build the receiver grid for `box` when its lattice window changed.
local function meshFor(ground, box)
  local cell = Sun.CELL
  local ix0, ix1 = math.floor(box.x0 / cell), math.ceil(box.x1 / cell)
  local iz0, iz1 = math.floor(box.z0 / cell), math.ceil(box.z1 / cell)
  local key = ("%d:%d:%d:%d"):format(ix0, ix1, iz0, iz1)
  if recv.mesh and recv.ground == ground and recv.key == key then
    return recv.mesh, recv.cells
  end
  releaseMesh()
  if type(ground.groundY) ~= "function" then return nil, 0 end
  local store = heights[ground]
  if not store then store = {}; heights[ground] = store end

  local nx, nz = ix1 - ix0 + 1, iz1 - iz0 + 1
  if nx < 2 or nz < 2 or nx * nz > 20000 then return nil, 0 end
  local verts, index = {}, {}
  local lift = Sun.LIFT
  local have = {}
  for j = 0, nz - 1 do
    for i = 0, nx - 1 do
      local ix, iz = ix0 + i, iz0 + j
      local h = heightAt(ground, store, ix, iz)
      local v = j * nx + i + 1
      verts[v] = { ix * cell, (h or 0) + lift, iz * cell, 0, 0 }
      have[v] = h ~= false
    end
  end
  local cells = 0
  for j = 0, nz - 2 do
    for i = 0, nx - 2 do
      local a = j * nx + i + 1
      local b, c, d = a + 1, a + nx, a + nx + 1
      -- a cell with a corner off the height map is left out whole rather
      -- than stretched down to nothing
      if have[a] and have[b] and have[c] and have[d] then
        index[#index + 1] = a; index[#index + 1] = b; index[#index + 1] = c
        index[#index + 1] = b; index[#index + 1] = d; index[#index + 1] = c
        cells = cells + 1
      end
    end
  end
  if cells == 0 then return nil, 0 end
  local ok, mesh = pcall(love.graphics.newMesh, FORMAT, verts, "triangles", "static")
  if not (ok and mesh) then
    once("mesh", "ground receiver mesh failed: %s", tostring(mesh))
    return nil, 0
  end
  pcall(mesh.setVertexMap, mesh, index)
  recv.mesh, recv.ground, recv.key, recv.cells = mesh, ground, key, cells
  Sun.stats.cells = cells
  return mesh, cells
end

-- A Gen4Bridge effect. Runs inside the open Voxel3D scene, so the Gen 4
-- depth buffer is live; leaves the scene's shader, blend and depth state as it
-- found them.
function Sun.drawReceiver(scene)
  if not Sun.groundShadows then return end
  local box = scene and scene.shadowBox
  if not box then return end
  if not ShadowMap.active() then return end
  local sh = getShader()
  if not sh then return end
  local ground = scene.ground
  if not ground then return end
  local mesh, cells = meshFor(ground, box)
  if not mesh or cells == 0 then return end

  local g = love.graphics
  local prevShader = g.getShader()
  local prevBlend, prevAlpha = g.getBlendMode()
  local prevMode, prevWrite = g.getDepthMode()
  local prevCull = g.getMeshCullMode()
  local tint = Sun.TINT
  g.setShader(sh)
  g.setBlendMode("alpha", "alphamultiply")
  g.setDepthMode("lequal", false)       -- tested against the scene, never written
  g.setMeshCullMode("none")
  g.setColor(1, 1, 1, 1)
  pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
  pcall(sh.send, sh, "sunVP", "row", ShadowMap.uvVP)
  local tex = ShadowMap.texture()
  if tex then pcall(sh.send, sh, "sunMap", tex) end
  pcall(sh.send, sh, "sunBias", ShadowMap.bias)
  local texel = 1 / ShadowMap.res
  pcall(sh.send, sh, "sunTexel", { texel, texel })
  pcall(sh.send, sh, "shade", Voxel3D.SHADOW_ALPHA or 0.4)
  pcall(sh.send, sh, "shadeColor", { tint[1], tint[2], tint[3] })
  local ok, err = pcall(g.draw, mesh)
  if not ok then once("draw", "ground receiver draw failed: %s", tostring(err)) end
  g.setMeshCullMode(prevCull)
  g.setDepthMode(prevMode, prevWrite)
  g.setBlendMode(prevBlend, prevAlpha)
  g.setShader(prevShader)
end

-- Drop the baked receiver and its height cache (map change, graphics reset,
-- mod reload).
function Sun.invalidate()
  releaseMesh()
  recv.ground = nil
  heights = setmetatable({}, { __mode = "k" })
  shader = nil
end

return Sun
