-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 geometry, in the shape the engine can actually load.
--
-- `Gen4Nsbmd` produces a model as Lua tables -- one table per vertex, one per
-- triangle.  That is the right shape to CHECK (it is what the corpus test
-- reads) and the wrong shape to ship: the briefcase alone is 2,430 vertex
-- tables and 1,644 triangle tables, and written as Lua source that is a
-- megabyte of `{ x = ..., y = ... }` for one model out of six.
--
-- So a packed model is two BINARY STRINGS, which is the same trick the map
-- grids already use (`def.blocks` is a 2 KB string, not 1,024 tables).
--
-- THE PRECISION IS THE CARTRIDGE'S OWN, which is what makes this lossless
-- rather than a compromise.  A Gen 4 coordinate is fx16 -- a signed 16-bit
-- number over 4096 -- so storing the raw fixed-point value keeps every
-- position exactly as the display list gave it.  Texture coordinates are in
-- sixteenths of a texel and are likewise integers already.  Nothing here
-- rounds anything that was not already round.
--
--   vertex  14 bytes  x, y, z, u, v as s16; r, g, b as u8; one byte of pad
--   index    2 bytes  u16 into this shape's own vertex array
--
-- The pad byte is not waste: it makes a vertex an even number of bytes, so the
-- engine's unpacker can step through the string two bytes at a time without a
-- special case, and every field lands on an offset it can compute rather than
-- accumulate.

local Gen4ModelPack = {}

Gen4ModelPack.VERTEX_BYTES = 14
Gen4ModelPack.INDEX_BYTES = 2
Gen4ModelPack.FX16 = 4096
-- Texture coordinates arrive in sixteenths of a texel; they are stored that
-- way and divided by the texture's size where the size is known.
Gen4ModelPack.UV_UNITS = 16

local floor, char, concat = math.floor, string.char, table.concat

-- A signed 16-bit value, little endian, clamped rather than wrapped.
--
-- Clamped because a wrap is silent and a clamp is visible: a coordinate that
-- genuinely exceeded the range would put one vertex on the far side of the
-- model, which is noticeable, where a wrap would put it somewhere arbitrary
-- and plausible.  Nothing in this cartridge comes close -- the largest
-- bounding box is under five units -- so this never fires; it is here so that
-- if it ever does, it does so where someone can see it.
local function s16(value)
  value = floor(value + 0.5)
  if value > 32767 then value = 32767 end
  if value < -32768 then value = -32768 end
  if value < 0 then value = value + 65536 end
  return char(value % 256, floor(value / 256))
end

local function u16(value)
  value = floor(value + 0.5)
  if value < 0 then value = 0 end
  if value > 65535 then value = 65535 end
  return char(value % 256, floor(value / 256))
end

local function u8(value)
  value = floor(value * 255 + 0.5)
  if value < 0 then value = 0 end
  if value > 255 then value = 255 end
  return char(value)
end

-- pack(model) -> { shapes = { { vertices, indices, count, triangles, ... } } }
--
-- One packed entry per shape rather than one per model, because a shape is
-- the unit a renderer draws: it has one material, therefore one texture, and
-- therefore one draw call.  Merging them would mean carrying a per-triangle
-- material id and splitting it again at draw time.
function Gen4ModelPack.pack(model)
  local out = {
    name = model.name,
    posScale = model.posScale,
    bounds = model.bounds,
    shapes = {},
    -- WHERE EACH SHAPE STANDS, carried rather than baked.
    --
    -- A shape's vertices are in its node's space, and on the briefcase the
    -- nodes are the only record of where the three Poke Balls are.  Baking
    -- each node's transform into its vertices here would be simpler and would
    -- throw away exactly the thing an animation replaces: the same walk over
    -- the same bytecode, with a joint animation's frame instead of the model's
    -- own node, is what makes the case open.
    nodes = {},
    ops = model.pose,
  }

  for _, bone in ipairs(model.bones or {}) do
    out.nodes[#out.nodes + 1] = { name = bone.name, matrix = bone.matrix }
  end

  for _, shape in ipairs(model.shapes) do
    local material = model.materials[(shape.material or 0) + 1]
    local vertexParts, indexParts = {}, {}

    for _, v in ipairs(shape.vertices) do
      vertexParts[#vertexParts + 1] = concat({
        s16(v.x * Gen4ModelPack.FX16),
        s16(v.y * Gen4ModelPack.FX16),
        s16(v.z * Gen4ModelPack.FX16),
        s16(v.u * Gen4ModelPack.UV_UNITS),
        s16(v.v * Gen4ModelPack.UV_UNITS),
        u8(v.r), u8(v.g), u8(v.b), char(0),
      })
    end

    for _, t in ipairs(shape.triangles) do
      -- ONE-BASED IN, ZERO-BASED OUT.  Gen4Nsbmd indexes its own Lua array, so
      -- its first vertex is 1; a mesh index buffer counts from 0 everywhere
      -- else in the world.  Converting here rather than at draw time means the
      -- renderer never has to know which convention it is holding.
      indexParts[#indexParts + 1] =
        u16(t[1] - 1) .. u16(t[2] - 1) .. u16(t[3] - 1)
    end

    out.shapes[#out.shapes + 1] = {
      name = shape.name,
      -- Its own index, because the pose is keyed by the number the bytecode
      -- uses rather than by position in this list.
      index = shape.index,
      vertices = concat(vertexParts),
      indices = concat(indexParts),
      vertexCount = #shape.vertices,
      triangleCount = #shape.triangles,
      material = material and material.name or nil,
      texture = material and material.texture or nil,
      palette = material and material.palette or nil,
    }
  end

  return out
end

-- unpack(packed) -> vertices, triangles
--
-- The inverse, and it exists to be RUN rather than to be used: the extractor
-- packs a model and then unpacks it again, and the two have to agree on every
-- coordinate.  A packer that drops a field, swaps two, or mis-signs a
-- negative produces a model that still draws -- inside out, or with one wall
-- missing -- which is the failure mode this whole file has been built to make
-- impossible to reach quietly.
function Gen4ModelPack.unpack(shape)
  local vertices, triangles = {}, {}
  local data = shape.vertices
  local stride = Gen4ModelPack.VERTEX_BYTES

  local function s16At(at)
    local a, b = data:byte(at + 1, at + 2)
    if not b then return nil end
    local value = a + b * 256
    if value >= 32768 then value = value - 65536 end
    return value
  end

  for i = 0, shape.vertexCount - 1 do
    local at = i * stride
    local r, g, b = data:byte(at + 11, at + 13)
    vertices[i + 1] = {
      x = s16At(at) / Gen4ModelPack.FX16,
      y = s16At(at + 2) / Gen4ModelPack.FX16,
      z = s16At(at + 4) / Gen4ModelPack.FX16,
      u = s16At(at + 6) / Gen4ModelPack.UV_UNITS,
      v = s16At(at + 8) / Gen4ModelPack.UV_UNITS,
      r = (r or 255) / 255, g = (g or 255) / 255, b = (b or 255) / 255,
    }
  end

  local index = shape.indices
  for i = 0, shape.triangleCount - 1 do
    local at = i * 6
    local function idx(k)
      local a, b = index:byte(at + k + 1, at + k + 2)
      return a and (a + b * 256) or nil
    end
    triangles[i + 1] = { idx(0) + 1, idx(2) + 1, idx(4) + 1 }
  end

  return vertices, triangles
end

-- verify(model, packed) -> ok, complaint
--
-- Round-trip every shape and require the unpacked geometry to match what went
-- in, to the precision the format holds.  The tolerance is half a fixed-point
-- step, because that is the only rounding this does; anything bigger is a bug
-- rather than a representation.
function Gen4ModelPack.verify(model, packed)
  local tolerance = 0.5 / Gen4ModelPack.FX16
  for i, shape in ipairs(model.shapes) do
    local out = packed.shapes[i]
    if not out then return false, ("shape %d is missing"):format(i) end
    if out.vertexCount ~= #shape.vertices then
      return false, ("shape %q: %d vertices packed, %d in")
        :format(shape.name, out.vertexCount, #shape.vertices)
    end
    local vertices, triangles = Gen4ModelPack.unpack(out)
    for k, v in ipairs(shape.vertices) do
      local w = vertices[k]
      if not w then return false, ("shape %q vertex %d lost"):format(shape.name, k) end
      for _, axis in ipairs({ "x", "y", "z" }) do
        if math.abs(v[axis] - w[axis]) > tolerance then
          return false, ("shape %q vertex %d %s: %f in, %f out")
            :format(shape.name, k, axis, v[axis], w[axis])
        end
      end
    end
    for k, t in ipairs(shape.triangles) do
      local u = triangles[k]
      if not u or u[1] ~= t[1] or u[2] ~= t[2] or u[3] ~= t[3] then
        return false, ("shape %q triangle %d changed"):format(shape.name, k)
      end
    end
  end
  return true
end

return Gen4ModelPack
