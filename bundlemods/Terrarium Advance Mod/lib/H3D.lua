-- H3D: models and textures out of a relocated BCH (lib/BCH.lua), for the
-- Omega Ruby / Alpha Sapphire Pokemon import.  Struct layouts are SPICA's
-- (SPICA/Formats/CtrH3D), checked word for word against Ivysaur's model in
-- the anatomy probe (lib/ORASProbe.lua):
--
--   model     +00 flags u8, bone scaling u8, silhouette count u16
--             +04 world transform (12 floats)
--             +34 materials {ptr, count, tree}   (H3DMaterial inline, 0x2C each)
--             +40 meshes {ptr, count}            (H3DMesh inline, 0x38 each)
--             +48 four layer ranges {start, end}
--             +68 submesh cullings {ptr, count}
--             +70 skeleton {ptr, count, tree}    (H3DBone inline, 0x64 each)
--             +7C node visibility {ptr, count}   +84 name
--   material  +00 params ptr, +04..+0C texture objects, +10 texture commands
--             {ptr, count}, +18 mappers ptr, +1C/+20/+24 texture 0-2 names,
--             +28 name.  Params +0C: texture coords (see uvTransform);
--             mapper (16 bytes): sampler u8, wrap U u8, wrap V u8, ...
--   mesh      +00 material index u16, +02 flags u8, +04 node index u16,
--             +06 key u16, +08 enable commands {ptr, count}, +10 submeshes
--             {ptr, count}, +18 disable commands, +20 centre (3 floats),
--             +2C parent, +30 user data, +34 metadata
--   submesh   +00 skinning u8 (0 none, 1 smooth, 2 rigid), +02 bone count u16,
--             +04 bone palette u16[20], +2C commands {ptr, count}
--   bone      +00 flags u32, +04 parent s16, +08 scale, +14 rotation (Euler
--             XYZ, radians), +20 translation, +2C inverse transform, +5C name
--   texture   +00/+08/+10 unit 0-2 commands {ptr, count}, +18 format u8,
--             +19 mipmap count u8, +1C name  (behind a pointer table)
--
-- Vertices are read the way SPICA's VerticesConverter does: attribute order,
-- format and element count from the mesh's PICA commands; each value times
-- its scale uniform; the position offset uniform added to positions; shorts
-- and floats aligned to two bytes inside the vertex.

local V = ...
local BCH = V.require("BCH")
local PICA = V.require("PICA")

local H3D = {}

local u32, f32 = BCH.u32, BCH.f32
local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function s16(s, p) local v = u16(s, p); return v >= 32768 and v - 65536 or v end
local function u8(s, p) return s:byte(p) end

-- absolute-offset readers over relocated data
local function W(d, at) return u32(d, at + 1) end
local function F(d, at) return f32(u32(d, at + 1)) end
local function str(d, at)
  local p = W(d, at)
  return p and p > 0 and BCH.cstring(d, p) or nil
end

-- the n-th entry of a content-header kind (pointer table)
local function contentEntries(d, h, kind)
  for i, k in ipairs(BCH.KINDS) do
    if k == kind then
      local base = h.content + (i - 1) * 12
      local tableAt, count = W(d, base), W(d, base + 4)
      local out = {}
      for n = 0, (count or 0) - 1 do out[n + 1] = W(d, tableAt + n * 4) end
      return out
    end
  end
  return {}
end

-- ------------------------------------------------------------ attributes

local NAME = { [0] = "position", "normal", "tangent", "color", "uv0", "uv1", "uv2",
               "boneIndex", "boneWeight" }
local FMT_SIZE = { [0] = 1, 1, 2, 4 }             -- byte, ubyte, short, float

-- nibble `i` (0..15) of a 64-bit value held as two 32-bit halves
local function nibble(lo, hi, i)
  if i < 8 then return math.floor(lo / 16 ^ i) % 16 end
  return math.floor(hi / 16 ^ (i - 8)) % 16
end

local function meshLayout(words)
  local cmds, uniforms = PICA.commands(words)
  local R = PICA.REG
  local fmtLo, fmtHi, attrLo, attrHi, permLo, permHi = 0, 0, 0, 0, 0, 0
  local address, stride, count, total = 0, 0, 0, 0
  local fixed, fixedIndex = {}, 0
  for _, c in ipairs(cmds) do
    local p = c.params[1]
    if c.reg == R.ATTR_FORMAT_LO then fmtLo = p
    elseif c.reg == R.ATTR_FORMAT_HI then fmtHi = p
    elseif c.reg == R.ATTR0_OFFSET then address = p
    elseif c.reg == R.ATTR0_CONFIG1 then attrLo = p
    elseif c.reg == R.ATTR0_CONFIG2 then
      attrHi = p % 0x10000
      stride = math.floor(p / 0x10000) % 256
      count = math.floor(p / 0x10000000)
    elseif c.reg == R.VSH_PERM_LO then permLo = p
    elseif c.reg == R.VSH_PERM_HI then permHi = p
    elseif c.reg == R.VSH_NUM_ATTR then total = p + 1
    elseif c.reg == R.FIXED_INDEX then fixedIndex = p % 16
    elseif c.reg >= R.FIXED_DATA0 and c.reg <= R.FIXED_DATA2 then
      fixed[fixedIndex] = fixed[fixedIndex] or {}
      fixed[fixedIndex][c.reg - R.FIXED_DATA0 + 1] = p
    end
  end

  local u7, u8v = uniforms[7] or { 1, 1, 1, 1 }, uniforms[8] or { 1, 1, 1, 1 }
  local SCALE = { position = u7[1], normal = u7[2], tangent = u7[3], color = u7[4],
                  uv0 = u8v[1], uv1 = u8v[2], uv2 = u8v[3], boneWeight = u8v[4] }

  local attrs = {}
  for i = 0, count - 1 do
    local slot = nibble(attrLo, attrHi, i)
    local name = NAME[nibble(permLo, permHi, slot)] or ("user" .. nibble(permLo, permHi, slot))
    local f = nibble(fmtLo, fmtHi, slot)
    attrs[#attrs + 1] = { name = name, format = f % 4, elements = math.floor(f / 4) + 1,
                          scale = SCALE[name] or 1 }
  end

  local fixedAttrs = {}
  for i = 0, total - 1 do
    if math.floor(fmtHi / 2 ^ (16 + i)) % 2 == 1 and fixed[i] then
      local w = fixed[i]
      local x, y, z, ww = PICA.vec24(w[1] or 0, w[2] or 0, w[3] or 0)
      fixedAttrs[NAME[nibble(permLo, permHi, i)] or ("user" .. i)] = { x, y, z, ww }
    end
  end

  local off = uniforms[6] or { 0, 0, 0, 0 }
  local weightElements = 0
  for _, a in ipairs(attrs) do if a.name == "boneWeight" then weightElements = a.elements end end
  return { address = address, stride = stride, attrs = attrs, fixed = fixedAttrs,
           positionOffset = { off[1], off[2], off[3] }, weightElements = weightElements }
end

-- one vertex: { position = {x,y,z}, normal = ..., uv0 = {u,v}, boneIndex = {...}, ... }
local function readVertex(d, layout, v)
  local base = layout.address + v * layout.stride
  local o = 0
  local out = {}
  for _, a in ipairs(layout.attrs) do
    local size = FMT_SIZE[a.format]
    if size >= 2 and o % 2 == 1 then o = o + 1 end
    local vals = {}
    for e = 1, a.elements do
      local p = base + o + 1
      local x
      if a.format == 0 then x = d:byte(p); if x >= 128 then x = x - 256 end
      elseif a.format == 1 then x = d:byte(p)
      elseif a.format == 2 then x = s16(d, p)
      else x = f32(u32(d, p)) end
      vals[e] = x * a.scale
      o = o + size
    end
    out[a.name] = vals
  end
  if out.position then
    local po = layout.positionOffset
    out.position[1] = out.position[1] + po[1]
    out.position[2] = out.position[2] + po[2]
    out.position[3] = out.position[3] + po[3]
  end
  for name, val in pairs(layout.fixed) do
    if not out[name] then
      if name == "boneWeight" then
        -- a fixed weight vec4's w is a homogeneous 1.0 (eyes and irises
        -- carry (1, 0, 0, 1)): only x, y, z are weights
        out[name] = { val[1], val[2], val[3] }
      elseif name == "boneIndex" then
        -- fixed indices supply as many bones as the vertex has weights:
        -- Squirtle's Body02 has fixed (0, 1, 2, 3) against a real
        -- 4-element weight attribute, and its 4th index is a real bone
        local n = (layout.weightElements or 0) >= 4 and 4 or 3
        out[name] = { val[1], val[2], val[3], n == 4 and val[4] or nil }
      else
        out[name] = { val[1], val[2], val[3], val[4] }
      end
    end
  end
  return out
end

local function indexBuffer(d, words)
  local cmds = PICA.commands(words)
  local R = PICA.REG
  local address, count, mode = 0, 0, 0
  for _, c in ipairs(cmds) do
    if c.reg == R.INDEX_CONFIG then address = c.params[1]
    elseif c.reg == R.NUM_VERTICES then count = c.params[1]
    elseif c.reg == R.PRIMITIVE_CONFIG then mode = math.floor(c.params[1] / 256) % 4 end
  end
  local wide = address >= 0x80000000
  local at = address % 0x80000000
  local list = {}
  for i = 0, count - 1 do
    list[i + 1] = wide and u16(d, at + i * 2 + 1) or d:byte(at + i + 1)
  end
  -- triangle strips become a list
  if mode == 1 then
    local tri = {}
    for i = 1, #list - 2 do
      local a, b, c = list[i], list[i + 1], list[i + 2]
      if a ~= b and b ~= c and a ~= c then
        if i % 2 == 1 then tri[#tri + 1] = a; tri[#tri + 1] = b; tri[#tri + 1] = c
        else tri[#tri + 1] = b; tri[#tri + 1] = a; tri[#tri + 1] = c end
      end
    end
    list = tri
  end
  return list, mode
end

-- ---------------------------------------------------------------- bones

local function matMul(a, b)                -- 4x4, row-major tables of 16
  local r = {}
  for i = 0, 3 do
    for j = 0, 3 do
      local s = 0
      for k = 0, 3 do s = s + a[i * 4 + k + 1] * b[k * 4 + j + 1] end
      r[i * 4 + j + 1] = s
    end
  end
  return r
end
H3D.matMul = matMul

-- column-vector convention: local = T * Rz * Ry * Rx * S (SPICA's
-- CalculateTransform, written for column vectors)
function H3D.localMatrix(s, r, t)
  local cx, sx = math.cos(r[1]), math.sin(r[1])
  local cy, sy = math.cos(r[2]), math.sin(r[2])
  local cz, sz = math.cos(r[3]), math.sin(r[3])
  local rx = { 1, 0, 0, 0,  0, cx, -sx, 0,  0, sx, cx, 0,  0, 0, 0, 1 }
  local ry = { cy, 0, sy, 0,  0, 1, 0, 0,  -sy, 0, cy, 0,  0, 0, 0, 1 }
  local rz = { cz, -sz, 0, 0,  sz, cz, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 }
  local sm = { s[1], 0, 0, 0,  0, s[2], 0, 0,  0, 0, s[3], 0,  0, 0, 0, 1 }
  local tm = { 1, 0, 0, t[1],  0, 1, 0, t[2],  0, 0, 1, t[3],  0, 0, 0, 1 }
  return matMul(tm, matMul(rz, matMul(ry, matMul(rx, sm))))
end

function H3D.transformPoint(m, p)
  return m[1] * p[1] + m[2] * p[2] + m[3] * p[3] + m[4],
         m[5] * p[1] + m[6] * p[2] + m[7] * p[3] + m[8],
         m[9] * p[1] + m[10] * p[2] + m[11] * p[3] + m[12]
end

function H3D.transformDir(m, p)
  return m[1] * p[1] + m[2] * p[2] + m[3] * p[3],
         m[5] * p[1] + m[6] * p[2] + m[7] * p[3],
         m[9] * p[1] + m[10] * p[2] + m[11] * p[3]
end

local function readBones(d, at, count)
  local bones = {}
  for i = 0, count - 1 do
    local b = at + i * 0x64
    bones[i + 1] = {
      flags = W(d, b),
      parent = s16(d, b + 4 + 1),
      scale = { F(d, b + 0x08), F(d, b + 0x0C), F(d, b + 0x10) },
      rotation = { F(d, b + 0x14), F(d, b + 0x18), F(d, b + 0x1C) },
      translation = { F(d, b + 0x20), F(d, b + 0x24), F(d, b + 0x28) },
      name = str(d, b + 0x5C),
    }
  end
  -- world (bind) matrices; parents always precede children in H3D skeletons
  for _, bone in ipairs(bones) do
    bone.localMatrix = H3D.localMatrix(bone.scale, bone.rotation, bone.translation)
    local parent = bone.parent >= 0 and bones[bone.parent + 1]
    bone.world = parent and parent.world and matMul(parent.world, bone.localMatrix) or bone.localMatrix
  end
  return bones
end

-- ------------------------------------------------------ texture transform
--
-- Material params +0x0C holds TextureCoords[0] (24 bytes): flags u8,
-- transform type u8 (0 Maya, 1 SoftImage, 2 3dsMax), mapping u8, camera s8,
-- scale x/y, rotation, translation x/y.  An eye sheet is how this shows: the
-- eye texture holds several frames and the coordinate transform picks one.
-- The matrix is SPICA's TextureTransform, applied as a row vector:
-- u' = u*m11 + v*m21 + m41, v' = u*m12 + v*m22 + m42.

function H3D.uvTransform(d, at)
  local kind = d:byte(at + 2)
  local sx, sy = F(d, at + 4), F(d, at + 8)
  local rot = F(d, at + 12)
  local tx, ty = F(d, at + 16), F(d, at + 20)
  local ca, sa = math.cos(rot), math.sin(rot)
  local t = { m11 = sx * ca, m12 = sy * sa, m21 = sx * -sa, m22 = sy * ca,
              kind = kind, sx = sx, sy = sy, rot = rot, tx = tx, ty = ty }
  if kind == 0 then
    t.m41 = sx * ((0.5 * sa - 0.5 * ca) + 0.5 - tx)
    t.m42 = sy * ((0.5 * -sa - 0.5 * ca) + 0.5 - ty)
  elseif kind == 1 then
    t.m41 = sx * (-ca * tx - sa * ty)
    t.m42 = sy * (sa * tx - ca * ty)
  elseif kind == 2 then
    t.m41 = sx * ca * (-tx - 0.5) - sx * sa * (ty - 0.5) + 0.5
    t.m42 = sy * sa * (-tx - 0.5) + sy * ca * (ty - 0.5) + 0.5
  else
    t.m41, t.m42 = 0, 0
  end
  return t
end

function H3D.applyUV(t, uv)
  if not (t and uv) then return uv end
  local u, v = uv[1], uv[2] or 0
  return { u * t.m11 + v * t.m21 + t.m41, u * t.m12 + v * t.m22 + t.m42 }
end

-- ---------------------------------------------------------------- model

function H3D.models(d, h)
  local models = {}
  for _, m in ipairs(contentEntries(d, h, "models")) do
    local model = { name = str(d, m + 0x84), materials = {}, meshes = {} }

    local matAt, matCount = W(d, m + 0x34), W(d, m + 0x38)
    for i = 0, matCount - 1 do
      local b = matAt + i * 0x2C
      local params = W(d, b)
      -- texture mapper 0 (16 bytes each, three of them): sampler type u8,
      -- wrap U u8, wrap V u8 (0 clamp to edge, 1 clamp to border, 2 repeat,
      -- 3 mirror).  ORAS bodies are commonly half a texture, mirrored.
      local mappers = W(d, b + 0x18)
      local wrapU = mappers and mappers > 0 and d:byte(mappers + 2) or 2
      local wrapV = mappers and mappers > 0 and d:byte(mappers + 3) or 2
      model.materials[i + 1] = {
        name = str(d, b + 0x28),
        textures = { str(d, b + 0x1C), str(d, b + 0x20), str(d, b + 0x24) },
        uvTransform = params and params > 0 and H3D.uvTransform(d, params + 0x0C) or nil,
        wrapU = wrapU, wrapV = wrapV,
      }
    end

    model.bones = readBones(d, W(d, m + 0x70), W(d, m + 0x74))

    local meshAt, meshCount = W(d, m + 0x40), W(d, m + 0x44)
    for i = 0, meshCount - 1 do
      local b = meshAt + i * 0x38
      local layout = meshLayout(PICA.words(d, W(d, b + 0x08), W(d, b + 0x0C)))
      local mesh = { materialIndex = u16(d, b + 1), nodeIndex = u16(d, b + 4 + 1),
                     layout = layout, submeshes = {} }
      local subAt, subCount = W(d, b + 0x10), W(d, b + 0x14)
      local maxIndex = -1
      for s = 0, subCount - 1 do
        local sb = subAt + s * 0x34
        local palette = {}
        for k = 0, u16(d, sb + 2 + 1) - 1 do palette[k + 1] = u16(d, sb + 4 + k * 2 + 1) end
        local indices, mode = indexBuffer(d, PICA.words(d, W(d, sb + 0x2C), W(d, sb + 0x30)))
        for _, ix in ipairs(indices) do if ix > maxIndex then maxIndex = ix end end
        mesh.submeshes[s + 1] = { skinning = u8(d, sb + 1), palette = palette,
                                  indices = indices, mode = mode }
      end
      mesh.vertexCount = maxIndex + 1
      mesh.vertices = {}
      for v = 0, maxIndex do mesh.vertices[v + 1] = readVertex(d, layout, v) end
      model.meshes[i + 1] = mesh
    end
    models[#models + 1] = model
  end
  return models
end

-- Bind-pose positions/normals for every vertex of a mesh, in model space.
-- Smooth-skinned vertices already are; rigid ones are relative to their
-- single bone (the palette entry their first bone index names).  A vertex is
-- assigned to the first submesh that references it.
function H3D.bindPose(model, mesh)
  local owner = {}
  for _, sm in ipairs(mesh.submeshes) do
    for _, ix in ipairs(sm.indices) do owner[ix] = owner[ix] or sm end
  end
  local mat = model.materials[mesh.materialIndex + 1]
  local uvT = mat and mat.uvTransform
  local out = {}
  for i, v in ipairs(mesh.vertices) do
    local p, n = v.position or { 0, 0, 0 }, v.normal
    local sm = owner[i - 1]
    if sm and sm.skinning == 2 then
      local bi = v.boneIndex and math.floor(v.boneIndex[1] + 0.5) or 0
      local bone = model.bones[(sm.palette[bi + 1] or 0) + 1]
      if bone then
        local x, y, z = H3D.transformPoint(bone.world, p)
        p = { x, y, z }
        if n then local a, b, c = H3D.transformDir(bone.world, n); n = { a, b, c } end
      end
    end
    out[i] = { position = p, normal = n, uv = H3D.applyUV(uvT, v.uv0) }
  end
  return out
end

-- --------------------------------------------------------------- posing
--
-- A battle motion (lib/GF1Motion.lua) animates bones by NAME; every motion
-- bone of the species checked exists in the model skeleton.  A model bone the
-- motion animates gets a local matrix from the motion's channels (any channel
-- the motion leaves out keeps the bone's bind value); the rest keep their
-- bind local.  Smooth-skinned vertices are in bind (model) space, so they move
-- by world * inverse(bind world); rigid ones are in their bone's space and
-- move by that bone's world.

function H3D.affineInverse(m)
  local a, b, c = m[1], m[2], m[3]
  local d, e, f = m[5], m[6], m[7]
  local g, h, i = m[9], m[10], m[11]
  local det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
  if math.abs(det) < 1e-12 then det = 1e-12 end
  local r = {
    (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det, 0,
    (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det, 0,
    (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det, 0,
    0, 0, 0, 1,
  }
  local tx, ty, tz = m[4], m[8], m[12]
  r[4] = -(r[1] * tx + r[2] * ty + r[3] * tz)
  r[8] = -(r[5] * tx + r[6] * ty + r[7] * tz)
  r[12] = -(r[9] * tx + r[10] * ty + r[11] * tz)
  return r
end

-- poser(motion, frame) -> skin[boneIndex] (world * inverse bind), world[boneIndex]
-- (1-based bone indices, as model.bones)
function H3D.poser(model, sample, skeletonNames)
  local gfIndex = {}
  for i, name in ipairs(skeletonNames or {}) do gfIndex[name] = i - 1 end
  local inverseBind = {}
  for i, bone in ipairs(model.bones) do inverseBind[i] = H3D.affineInverse(bone.world) end
  return function(motion, frame)
    local world, skin = {}, {}
    for i, bone in ipairs(model.bones) do
      local localM = bone.localMatrix
      local gi = motion and gfIndex[bone.name]
      if gi then
        local curves = motion.curves
        local animated = false
        for c = 0, 8 do if curves[gi * 9 + c] then animated = true; break end end
        if animated then
          local t = { bone.translation[1], bone.translation[2], bone.translation[3] }
          local r = { bone.rotation[1], bone.rotation[2], bone.rotation[3] }
          local s = { bone.scale[1], bone.scale[2], bone.scale[3] }
          for c = 0, 8 do
            local curve = curves[gi * 9 + c]
            if curve then
              local v = sample(curve, frame)
              if c < 3 then t[c + 1] = v elseif c < 6 then r[c - 2] = v else s[c - 5] = v end
            end
          end
          localM = H3D.localMatrix(s, r, t)
        end
      end
      local parent = bone.parent >= 0 and world[bone.parent + 1]
      world[i] = parent and matMul(parent, localM) or localM
      skin[i] = matMul(world[i], inverseBind[i])
    end
    return skin, world
  end
end

-- Per-vertex skinning recipe for one mesh: list[vertex] = { rigid = bone } or
-- { bones = {...}, weights = {...} } (1-based model bone indices), from the
-- first submesh that references the vertex.  Unused index slots (weight 0, or
-- past the palette) are dropped.
function H3D.skinning(model, mesh)
  local owner = {}
  for _, sm in ipairs(mesh.submeshes) do
    for _, ix in ipairs(sm.indices) do owner[ix] = owner[ix] or sm end
  end
  local out = {}
  for i, v in ipairs(mesh.vertices) do
    local sm = owner[i - 1]
    local rec = { position = v.position or { 0, 0, 0 } }
    if sm and sm.skinning ~= 0 then
      local idx = v.boneIndex or { 0 }
      if sm.skinning == 2 then
        rec.rigid = (sm.palette[math.floor(idx[1] + 0.5) + 1] or 0) + 1
      else
        local w = v.boneWeight or { 1 }
        local sum = 0
        for k = 1, #w do sum = sum + w[k] end
        rec.bones, rec.weights = {}, {}
        for k = 1, #idx do
          local weight = w[k]
          if weight == nil then weight = (k == #w + 1 and 1 - sum > 0.005) and (1 - sum) or 0 end
          local pal = sm.palette[math.floor(idx[k] + 0.5) + 1]
          if weight > 0 and pal then
            rec.bones[#rec.bones + 1] = pal + 1
            rec.weights[#rec.weights + 1] = weight
          end
        end
        -- weights are percentages quantized to bytes; renormalize what is kept
        local total = 0
        for _, w2 in ipairs(rec.weights) do total = total + w2 end
        if total > 0 and math.abs(total - 1) > 1e-4 then
          for k = 1, #rec.weights do rec.weights[k] = rec.weights[k] / total end
        end
      end
    end
    out[i] = rec
  end
  return out
end

function H3D.skinPoint(rec, skin, world)
  local p = rec.position
  if rec.rigid then return H3D.transformPoint(world[rec.rigid] or skin[1], p) end
  if rec.bones and #rec.bones > 0 then
    local x, y, z = 0, 0, 0
    for k, b in ipairs(rec.bones) do
      local m = skin[b]
      if m then
        local w = rec.weights[k]
        local a, bb, c = H3D.transformPoint(m, p)
        x, y, z = x + a * w, y + bb * w, z + c * w
      end
    end
    return x, y, z
  end
  return p[1], p[2], p[3]
end

-- ------------------------------------------------------------- textures

-- { [name] = { width, height, format, mipmaps, address, length } }
function H3D.textures(d, h)
  local out = {}
  for _, t in ipairs(contentEntries(d, h, "textures")) do
    local name = str(d, t + 0x1C)
    local cmds = PICA.commands(PICA.words(d, W(d, t), W(d, t + 4)))
    local w, hh, addr = 0, 0, 0
    for _, c in ipairs(cmds) do
      if c.reg == PICA.REG.TEX0_DIM then
        hh = c.params[1] % 0x800
        w = math.floor(c.params[1] / 0x10000) % 0x800
      elseif c.reg == PICA.REG.TEX0_ADDR1 then addr = c.params[1]
      end
    end
    local fmt = d:byte(t + 0x18 + 1)
    if name then
      out[name] = { name = name, width = w, height = hh, format = fmt,
                    mipmaps = d:byte(t + 0x19 + 1), address = addr,
                    length = PICA.textureLength(w, hh, fmt) }
    end
  end
  return out
end

-- ------------------------------------------------------ material animation
--
-- Per SPICA (H3DAnimation / H3DAnimationElement / H3DAnimVector /
-- H3DFloatKeyFrameGroup / KeyFrameQuantizationHelper).  An animation: name,
-- flags u8, type u8, curve count u16, frame count f32, element pointer list
-- and count.  An element: material name, target u16 (H3D.TARGET), primitive
-- u8 (2 = vector2), then a flags word and one word per axis: a curve
-- pointer, or the value itself when constant.

H3D.TARGET = { texCoord0Trans = 21, texCoord1Trans = 24, texCoord2Trans = 27 }

local function u24(d, at) local a, b, c = d:byte(at + 1, at + 3); return a + b * 256 + c * 65536 end
local function s12(v) return v >= 2048 and v - 4096 or v end

-- A key frame group (file version >= 0x20 layout): start, end, repeat
-- bytes, curve index, interpolation u8 (0 step, 1 linear, 2 hermite),
-- quantization u8, count u16, value scale, value offset, frame scale,
-- 1/duration, key pointer.
local function readCurve(d, c)
  local interp, quant, count = d:byte(c + 13), d:byte(c + 14), u16(d, c + 15)
  local vs, vo, fs = F(d, c + 16), F(d, c + 20), F(d, c + 24)
  local p = W(d, c + 32)
  local keys = {}
  for i = 1, count do
    local f, v, sin, sout
    if quant == 0 then          -- Hermite128
      f, v, sin, sout = F(d, p), F(d, p + 4), F(d, p + 8), F(d, p + 12); p = p + 16
    elseif quant == 1 then      -- Hermite64
      local fv = W(d, p)
      f, v = fv % 4096, math.floor(fv / 4096) % 1048576
      sin, sout = s16(d, p + 5) / 256, s16(d, p + 7) / 256; p = p + 8
    elseif quant == 2 then      -- Hermite48
      f, v = d:byte(p + 1), u16(d, p + 2)
      local sl = u24(d, p + 3)
      sin, sout = s12(sl % 4096) / 32, s12(math.floor(sl / 4096) % 4096) / 32; p = p + 6
    elseif quant == 3 then      -- UnifiedHermite96
      f, v, sin = F(d, p), F(d, p + 4), F(d, p + 8); sout = sin; p = p + 12
    elseif quant == 4 then      -- UnifiedHermite48
      f, v, sin = u16(d, p + 1) / 32, u16(d, p + 3), s16(d, p + 5) / 256; sout = sin; p = p + 6
    elseif quant == 5 then      -- UnifiedHermite32
      f = d:byte(p + 1)
      local vsl = u24(d, p + 1)
      v, sin = vsl % 4096, s12(math.floor(vsl / 4096) % 4096) / 32; sout = sin; p = p + 4
    elseif quant == 6 then      -- StepLinear64
      f, v, sin, sout = F(d, p), F(d, p + 4), 0, 0; p = p + 8
    elseif quant == 7 then      -- StepLinear32
      local fv = W(d, p)
      f, v, sin, sout = fv % 4096, math.floor(fv / 4096) % 1048576, 0, 0; p = p + 4
    else
      return nil
    end
    keys[i] = { f * fs, v * vs + vo, sin, sout }
  end
  return { interp = interp, keys = keys }
end

function H3D.sampleCurve(cv, frame)
  if type(cv) == "number" then return cv end
  local k = cv and cv.keys
  if not (k and k[1]) then return nil end
  if frame <= k[1][1] then return k[1][2] end
  for i = 1, #k - 1 do
    local a, b = k[i], k[i + 1]
    if frame <= b[1] then
      local span = b[1] - a[1]
      if span <= 0 or cv.interp == 0 then return span <= 0 and b[2] or a[2] end
      local t = (frame - a[1]) / span
      if cv.interp == 1 then return a[2] + (b[2] - a[2]) * t end
      local t2, t3 = t * t, t * t * t
      return (2 * t3 - 3 * t2 + 1) * a[2] + (t3 - 2 * t2 + t) * span * a[4]
           + (-2 * t3 + 3 * t2) * b[2] + (t3 - t2) * span * b[3]
    end
  end
  return k[#k][2]
end

-- Material animations of a BCH: { name, frames, elements = { material,
-- target, x, y } } where x / y are curves, constants, or nil.
function H3D.materialAnimations(d, h)
  local out = {}
  for _, a in ipairs(contentEntries(d, h, "materialAnimations")) do
    local anim = { name = str(d, a), frames = F(d, a + 8), elements = {} }
    local ep, ec = W(d, a + 12), W(d, a + 16) or 0
    for k = 0, ec - 1 do
      local e = W(d, ep + k * 4)
      local target, prim = u16(d, e + 5), d:byte(e + 7)
      local el = { material = str(d, e), target = target, prim = prim }
      if prim == 2 then
        -- H3DAnimVectorFlags: bit n = axis n constant, bit 8+n = axis n absent
        local flags = W(d, e + 8)
        for axis = 0, 1 do
          local constant = math.floor(flags / 2 ^ axis) % 2 == 1
          local absent = math.floor(flags / 2 ^ (axis + 8)) % 2 == 1
          local at = e + 12 + axis * 4
          local v
          if constant then v = F(d, at)
          elseif not absent and (W(d, at) or 0) > 0 then v = readCurve(d, W(d, at)) end
          el[axis == 0 and "x" or "y"] = v
        end
      end
      anim.elements[#anim.elements + 1] = el
    end
    out[#out + 1] = anim
  end
  return out
end

return H3D
