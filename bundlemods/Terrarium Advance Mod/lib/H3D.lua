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
--             +28 name
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
  return { address = address, stride = stride, attrs = attrs, fixed = fixedAttrs,
           positionOffset = { off[1], off[2], off[3] } }
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
    if not out[name] then out[name] = { val[1], val[2], val[3], val[4] } end
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
      model.materials[i + 1] = {
        name = str(d, b + 0x28),
        textures = { str(d, b + 0x1C), str(d, b + 0x20), str(d, b + 0x24) },
        uvTransform = params and params > 0 and H3D.uvTransform(d, params + 0x0C) or nil,
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

return H3D
