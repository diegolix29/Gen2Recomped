-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Drawing a Gen 4 model, which is the first real 3D this engine does itself.
--
-- The voxel mod has its own 3D and the tilt ground quad is one mesh with one
-- shader, but the engine core has never had a general "here is a mesh, draw
-- it" path -- so Platinum's 590 buildings, Giratina on the title, the field
-- effects and Professor Rowan's briefcase all had geometry sitting in the
-- cache with nothing able to put it on screen.
--
-- THIS IS DELIBERATELY SELF-CONTAINED.  It does not register a pipeline, does
-- not touch the world pass, and does not ask the Renderer for anything: a
-- screen creates one of these, draws it into its own canvas, and throws it
-- away.  The reason is that the first thing to use it is the starter select --
-- a menu with three Poke Balls in a briefcase -- which has no world behind it
-- and no business being part of the world's pipeline.  When the map meshes
-- arrive they will want the pipeline; a menu does not, and building for the
-- harder case first would mean neither worked.
--
-- WHAT DEPTH COSTS.  A 3D scene needs a depth buffer, which means a canvas
-- created with one and `setDepthMode` around the draw.  Both are restored
-- afterwards, unconditionally, because this runs inside somebody else's draw
-- and leaving either set turns the next 2D blit into a puzzle.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")
-- The pose walk lives with the reader that produced the bytecode.  Requiring
-- an importer from a renderer is not pretty; having the same walk written
-- twice and drifting apart would be worse, and this is the walk that decides
-- where every shape stands.
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")

local Gen4Model = {}
Gen4Model.__index = Gen4Model

-- Matches Gen4ModelPack: a vertex is fourteen bytes and a coordinate is fx16.
local VERTEX_BYTES = 14
local FX16 = 4096
local UV_UNITS = 16

-- The vertex shader takes a model-view-projection matrix and nothing else.
--
-- `TransformProjectionMatrix` is LOVE's own 2D transform and is deliberately
-- ignored: the whole point here is to put clip-space coordinates out directly,
-- and mixing the two would apply the 2D camera to a 3D scene.
local SHADER = [[
#ifdef VERTEX
uniform mat4 mvp;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    return mvp * vertex_position;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen)
{
    vec4 texel = Texel(tex, uv);
    // A Gen 4 texture keeps colour 0 transparent, and a transparent texel must
    // not write depth -- otherwise the hole punched through a leaf or a strap
    // occludes whatever is behind it.  Discarding is what makes that correct
    // rather than merely usually correct.
    if (texel.a < 0.5) { discard; }
    return texel * colour;
}
#endif
]]

local shader

local function ensureShader()
  if shader ~= nil then return shader or nil end
  local ok, made = pcall(love.graphics.newShader, SHADER)
  if not ok then
    Logger.error("gen4 model: the mesh shader would not compile (%s); "
                 .. "no 3D model will draw", tostring(made))
    shader = false
    return nil
  end
  shader = made
  return shader
end

-- ---------------------------------------------------------------------------
-- Matrices
-- ---------------------------------------------------------------------------

-- Row-major 4x4s, as flat sixteen-element tables, because that is the layout
-- Shader:send takes and converting once here beats converting at every draw.
local function identity()
  return { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 }
end

local function multiply(a, b)
  local out = {}
  for row = 0, 3 do
    for col = 0, 3 do
      local sum = 0
      for k = 0, 3 do
        sum = sum + a[row * 4 + k + 1] * b[k * 4 + col + 1]
      end
      out[row * 4 + col + 1] = sum
    end
  end
  return out
end

function Gen4Model.perspective(fovY, aspect, near, far)
  local f = 1 / math.tan(fovY / 2)
  return {
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) / (near - far), (2 * far * near) / (near - far),
    0, 0, -1, 0,
  }
end

-- A camera that looks at a point from a distance, around it and above it.
-- Spelled out rather than composed from a `lookAt` because the only thing that
-- ever moves it is a turntable, and two angles read better than an eye vector.
function Gen4Model.orbit(target, distance, yaw, pitch)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local rotateY = {
    cy, 0, -sy, 0,
    0, 1, 0, 0,
    sy, 0, cy, 0,
    0, 0, 0, 1,
  }
  local rotateX = {
    1, 0, 0, 0,
    0, cp, sp, 0,
    0, -sp, cp, 0,
    0, 0, 0, 1,
  }
  local translate = identity()
  translate[4] = -(target and target[1] or 0)
  translate[8] = -(target and target[2] or 0)
  translate[12] = -(target and target[3] or 0)
  local back = identity()
  back[12] = -(distance or 1)
  return multiply(back, multiply(rotateX, multiply(rotateY, translate)))
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
}

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

-- new(record) -> model, or nil when the record carries nothing drawable.
--
-- `record` is one entry of the cache's `gen4_models`: a name, a position scale
-- and a list of shapes, each with its packed vertices, its packed indices and
-- the texture its material wears.
function Gen4Model.new(record)
  if type(record) ~= "table" or type(record.shapes) ~= "table" then return nil end
  if not ensureShader() then return nil end

  local self = setmetatable({}, Gen4Model)
  self.name = record.name
  self.posScale = record.posScale or 1
  self.bounds = record.bounds
  self.shapes = {}
  -- The model's own node transforms and the bytecode that arranges them.  A
  -- model whose nodes are all identity -- most of them -- poses to identity
  -- and costs nothing; the briefcase's do the work.
  self.nodes = record.nodes or {}
  self.ops = record.ops or {}

  for _, shape in ipairs(record.shapes) do
    local image
    if shape.image then
      local ok, loaded = pcall(Assets.image, shape.image)
      if ok and loaded then
        image = loaded
        -- Nearest, always: these are 16 and 64 pixel textures on a model that
        -- will be drawn several times their own size, and smoothing them turns
        -- a Poke Ball's seam into a smear.
        image:setFilter("nearest", "nearest")
        image:setWrap("repeat", "repeat")
      end
    end

    -- The texture's own size is what turns a coordinate in sixteenths of a
    -- texel into the 0-1 the sampler wants.  Without an image there is nothing
    -- to divide by and the shape draws untextured, which is what an untextured
    -- material means anyway.
    local tw, th = 1, 1
    if image then tw, th = image:getDimensions() end

    local count = shape.vertexCount or 0
    local vertices = {}
    -- The shape's own box, kept while the vertices are still here.  It is what
    -- `framing` works from: the header states a bounding box too, but it does
    -- not agree with the geometry on two thirds of this cartridge's models, so
    -- the measured one is the one to trust.
    local lo = { math.huge, math.huge, math.huge }
    local hi = { -math.huge, -math.huge, -math.huge }
    for i = 0, count - 1 do
      local at = i * VERTEX_BYTES
      local r, g, b = shape.vertices:byte(at + 11, at + 13)
      local x = s16(shape.vertices, at) / FX16 * self.posScale
      local y = s16(shape.vertices, at + 2) / FX16 * self.posScale
      local z = s16(shape.vertices, at + 4) / FX16 * self.posScale
      if x < lo[1] then lo[1] = x end
      if y < lo[2] then lo[2] = y end
      if z < lo[3] then lo[3] = z end
      if x > hi[1] then hi[1] = x end
      if y > hi[2] then hi[2] = y end
      if z > hi[3] then hi[3] = z end
      vertices[i + 1] = {
        x, y, z,
        s16(shape.vertices, at + 6) / UV_UNITS / tw,
        s16(shape.vertices, at + 8) / UV_UNITS / th,
        r or 255, g or 255, b or 255, 255,
      }
    end
    if #vertices > 0 then
      local map = {}
      for i = 0, (shape.triangleCount or 0) * 3 - 1 do
        local a, b = shape.indices:byte(i * 2 + 1, i * 2 + 2)
        -- Back to one-based, which is what setVertexMap takes.
        map[i + 1] = (a + b * 256) + 1
      end

      local okMesh, mesh =
        pcall(love.graphics.newMesh, FORMAT, vertices, "triangles", "static")
      if okMesh and mesh then
        if #map > 0 then pcall(mesh.setVertexMap, mesh, map) end
        if image then mesh:setTexture(image) end
        self.shapes[#self.shapes + 1] =
          { mesh = mesh, name = shape.name, index = shape.index,
            lo = lo, hi = hi }
      else
        Logger.warn("gen4 model %s: shape %s would not build (%s)",
                    tostring(record.name), tostring(shape.name), tostring(mesh))
      end
    end
  end

  if #self.shapes == 0 then return nil end
  return self
end

-- framing(pose) -> centre, distance
--
-- The model's own centre and how far away a camera has to sit to see all of
-- it, measured off the geometry IN THE POSE IT WILL BE DRAWN IN.  A pose
-- matters here: the briefcase's three Poke Balls are 60 units apart only once
-- their nodes have placed them, and framing the unposed shapes would put the
-- camera close enough to lose two of them off the sides.
function Gen4Model:framing(pose)
  pose = pose or self:restPose()
  local lo = { math.huge, math.huge, math.huge }
  local hi = { -math.huge, -math.huge, -math.huge }
  for _, shape in ipairs(self.shapes) do
    local m = pose[shape.index]
    for corner = 0, 7 do
      local p = {
        (corner % 2 == 0) and shape.lo[1] or shape.hi[1],
        (math.floor(corner / 2) % 2 == 0) and shape.lo[2] or shape.hi[2],
        (math.floor(corner / 4) % 2 == 0) and shape.lo[3] or shape.hi[3],
      }
      if m then
        p = {
          m[1] * p[1] + m[2] * p[2] + m[3] * p[3] + m[4],
          m[5] * p[1] + m[6] * p[2] + m[7] * p[3] + m[8],
          m[9] * p[1] + m[10] * p[2] + m[11] * p[3] + m[12],
        }
      end
      for k = 1, 3 do
        if p[k] < lo[k] then lo[k] = p[k] end
        if p[k] > hi[k] then hi[k] = p[k] end
      end
    end
  end
  if lo[1] > hi[1] then return { 0, 0, 0 }, 4 end
  local centre = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
  local extent = math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
  return centre, math.max(0.001, extent) * 1.8
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- The rest pose: every shape's place with the model's own node transforms.
-- Built once and kept, because a model with identity nodes would otherwise
-- redo the same walk every frame to arrive at nothing.
function Gen4Model:restPose()
  if not self.rest then
    local nodes = self.nodes
    self.rest = Gen4Nsbmd.pose(self.ops, function(index)
      local node = nodes[index + 1]
      return node and node.matrix
    end)
  end
  return self.rest
end

-- posed(matrixOf) -> { [shape index] = 4x4 }
--
-- The same walk with somebody else's matrices: `matrixOf(node)` returns a
-- joint animation's frame, and a node the animation does not cover falls back
-- to the model's own.  That fallback is not a nicety -- an animation with
-- fewer joints than the model has nodes would otherwise collapse the rest to
-- the origin, which reads as geometry gone missing rather than as a mismatch.
function Gen4Model:posed(matrixOf)
  if not matrixOf then return self:restPose() end
  local nodes = self.nodes
  return Gen4Nsbmd.pose(self.ops, function(index)
    return matrixOf(index) or (nodes[index + 1] and nodes[index + 1].matrix)
  end)
end

-- draw(viewProjection, pose) -- into whatever canvas is set.
--
-- One matrix send per shape rather than one per model, because each shape
-- stands where its node puts it.  `pose` is what `restPose` or `posed`
-- returned; leaving it out draws the rest pose.
--
-- The depth mode is set and RESTORED here rather than left to the caller.
-- This is called from inside a screen's draw, and a depth test left switched
-- on makes the next ordinary 2D draw vanish or show through in ways that look
-- like a bug in the thing that comes after it.
function Gen4Model:draw(viewProjection, pose)
  local g = love.graphics
  if not (shader and viewProjection) then return false end
  pose = pose or self:restPose()
  local previousShader = g.getShader()
  local mode, write = g.getDepthMode()
  local culling = g.getMeshCullMode()

  g.setShader(shader)
  g.setDepthMode("less", true)
  -- BACK FACES ARE NOT CULLED, and that is the cartridge's own choice rather
  -- than laziness: a DS polygon carries its own front/back flags in its
  -- material, plenty of Gen 4 geometry is single-sided sheets meant to be seen
  -- from either side, and culling them uniformly loses the far wall of the
  -- briefcase.  With a depth buffer the cost of drawing both is a few
  -- overdrawn pixels.
  g.setMeshCullMode("none")
  g.setColor(1, 1, 1, 1)
  for _, shape in ipairs(self.shapes) do
    local place = pose[shape.index]
    shader:send("mvp", place and multiply(viewProjection, place) or viewProjection)
    g.draw(shape.mesh)
  end

  g.setMeshCullMode(culling)
  g.setDepthMode(mode, write)
  g.setShader(previousShader)
  return true
end

-- A canvas that can hold a depth buffer, which an ordinary one cannot.
--
-- Returned as a pair because LOVE wants them handed back together
-- (`setCanvas { colour, depthstencil = depth }`), and a caller that kept only
-- the colour one would get a scene with no depth test and no error.
function Gen4Model.newTarget(width, height)
  local okColour, colour = pcall(love.graphics.newCanvas, width, height)
  if not okColour or not colour then return nil end
  local okDepth, depth = pcall(love.graphics.newCanvas, width, height,
                               { format = "depth24", readable = false })
  if not okDepth or not depth then
    -- Without a depth buffer the model would draw in submission order, which
    -- on a solid object means the back of it in front.  Better to draw nothing
    -- and say why.
    Logger.warn("gen4 model: no depth canvas available (%s); "
                .. "3D models cannot be drawn on this device", tostring(depth))
    return nil
  end
  colour:setFilter("nearest", "nearest")
  return colour, depth
end

return Gen4Model
