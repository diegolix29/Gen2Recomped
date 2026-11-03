-- ORAS move effect MODELS: the BCH meshes of GARC a/0/3/2 that move
-- timelines show next to their particles (Pay Day's coin, Scratch's slash,
-- Vice Grip's pincers, Earthquake's floor).
--
-- Timeline records on a model's effect slot (lib/ORASEffects.lua bakes them
-- into entry.models = { { start, end, slot, member, role, point, off,
-- travel, scale, rot, uv } }):
--   0x3F  show model (u32 a/0/3/2 member, ...) from start to end
--   0x43  attach, same layout as 0x2F (who, body point, offset cm, easing);
--         a later / timed one flies the model there
--   0x49  size vec3; a timed one grows / shrinks to it over its span
--   0x47  rotation vec3 in degrees (+ u32); a timed one turns to it
--   0x52 / 0x89  texture scroll: u32 member of a BCH holding a material
--         animation (texture 0 translation) for the model's material
--
-- Bake output (mod cache oras/movefx/):
--   models/<m>.lua  { name, meshes = { { tex, blend, wrapU, wrapV, mat,
--                     uvt = {kind, sx, sy, rot, tx, ty}, colors,
--                     v = { x, y, z, u, v, [r, g, b, a] ... }, idx = {...} } } }
--                   positions in cm, bind pose (rigid bones applied), raw UVs
--   uv/<m>.lua      { frames, mats = { [material] = { x = curve|n, y = curve|n } } }
--   tex/<key>.png   shared with the particles
--
-- Not done yet: model emitters (0x7B), model motions (0x50), stage-sized
-- models (MAX_SPAN, skipped at bake), material
-- constant colours / fades, depth against the Pokemon.

local V = ...

local M = {}

M.GARC_PATH = "a/0/3/2"
M.MAX_SPAN = 600     -- cm; bigger models are stage pieces (see bakeModel)

local function H3D() return V.require("H3D") end

-- ------------------------------------------------------------------ bake

-- PICA blend (reg 0x101): src rgb bits 16-19, dst rgb bits 20-23
--   0x01010000 ONE / ZERO -> opaque, 0x76760000 alpha, 0x16160000 additive
local function blendOf(v)
  if not v then return "alpha" end
  local src, dst = math.floor(v / 0x10000) % 16, math.floor(v / 0x100000) % 16
  if dst == 1 then return "add" end
  if src == 1 and dst == 0 then return "opaque" end
  return "alpha"
end
M.blendOf = blendOf

-- the material's fragment registers: its params hold a (pointer, count) of
-- PICA commands inside the command section (at +0xC8 in every file seen;
-- scanned so a different layout still finds it)
local function fragmentRegs(d, h, paramsAt)
  local B, PICA = V.require("BCH"), V.require("PICA")
  if not paramsAt or paramsAt <= 0 then return {} end
  for off = 0, 0x1A0, 4 do
    local ptr, cnt = B.u32(d, paramsAt + off + 1), B.u32(d, paramsAt + off + 5)
    if ptr and cnt and cnt > 0 and cnt < 256 and ptr >= h.commands and ptr < h.commands + h.commandsLen then
      local ok, cmds = pcall(PICA.commands, PICA.words(d, ptr, cnt))
      if ok then
        local regs, found = {}, false
        for _, c in ipairs(cmds) do
          if c.reg >= 0x100 and c.reg <= 0x107 then regs[c.reg] = c.params[1]; found = true end
        end
        if found then return regs end
      end
    end
  end
  return {}
end

-- One a/0/3/2 member -> the compact model above, or nil, why.
-- writeTexture(name, width, height, imageData) -> key
function M.bakeModel(raw, writeTexture)
  local B, H, PICA = V.require("BCH"), H3D(), V.require("PICA")
  local h, why = B.header(raw)
  if not h then return nil, why end
  local d = B.relocate(raw, h)
  local models = H.models(d, h)
  if not models[1] then return nil, "no model" end
  local textures = H.textures(d, h)
  local keys = {}
  local function texKey(name)
    if not name then return nil end
    if keys[name] ~= nil then return keys[name] or nil end
    local t = textures[name]
    keys[name] = false
    if t and t.width > 0 and t.height > 0 then
      local ok, img = pcall(PICA.decodeTexture, d, t.address, t.width, t.height, t.format)
      if ok and img then keys[name] = writeTexture(name, t.width, t.height, img) or false end
    end
    return keys[name] or nil
  end
  local out = { name = models[1].name, meshes = {} }
  for _, model in ipairs(models) do
    local mats = {}
    for i, mt in ipairs(model.materials) do
      local regs = fragmentRegs(d, h, mt.paramsAt)
      local at = regs[0x104]
      local u = mt.uvTransform
      mats[i] = {
        tex = texKey(mt.textures[1]), blend = blendOf(regs[0x101]),
        cutout = at and at % 2 == 1 and (math.floor(at / 256) % 256) / 255 or nil,
        wrapU = mt.wrapU, wrapV = mt.wrapV, mat = mt.name,
        uvt = u and { u.kind, u.sx, u.sy, u.rot, u.tx, u.ty } or nil,
      }
    end
    for _, mesh in ipairs(model.meshes) do
      local mat = mats[mesh.materialIndex + 1]
      if mat and mat.tex and model.nodeVisible[mesh.nodeIndex] ~= false then
        local bind = H.bindPose(model, mesh)
        local colors = mesh.vertices[1] and mesh.vertices[1].color ~= nil
        local v, idx = {}, {}
        for i, b in ipairs(bind) do
          local raw0 = mesh.vertices[i].uv0 or { 0, 0 }
          local p = b.position
          v[#v + 1], v[#v + 2], v[#v + 3] = p[1], p[2], p[3]
          v[#v + 1], v[#v + 2] = raw0[1] or 0, raw0[2] or 0
          if colors then
            local c = mesh.vertices[i].color or { 1, 1, 1, 1 }
            for k = 1, 4 do v[#v + 1] = math.max(0, math.min(1, c[k] or 1)) end
          end
        end
        for _, sm in ipairs(mesh.submeshes) do
          for _, ix in ipairs(sm.indices) do idx[#idx + 1] = ix + 1 end
        end
        if #idx >= 3 then
          out.meshes[#out.meshes + 1] = {
            tex = mat.tex, blend = mat.blend, cutout = mat.cutout, wrapU = mat.wrapU, wrapV = mat.wrapV,
            mat = mat.mat, uvt = mat.uvt, colors = colors or nil, v = v, idx = idx,
          }
        end
      end
    end
  end
  if #out.meshes == 0 then return nil, "no visible textured mesh" end
  -- Stage-sized models (Earthquake's 20 m floor, move 621's rings) cover the
  -- whole fight: with no depth test against the Pokemon and the ground they
  -- would paint over everything. Left for the arena work.
  local lo, hi = math.huge, -math.huge
  for _, ms in ipairs(out.meshes) do
    local st = ms.colors and 9 or 5
    for i = 0, #ms.v / st - 1 do
      for c = 1, 3 do
        local x = ms.v[i * st + c]
        if x < lo then lo = x end
        if x > hi then hi = x end
      end
    end
  end
  out.span = hi - lo
  if out.span > M.MAX_SPAN then
    return nil, ("stage-sized (%.0f cm), needs depth against the arena"):format(out.span)
  end
  return out
end

-- One a/0/3/2 member holding material animations -> texture 0 translation
-- curves per material, or nil.
function M.bakeUV(raw)
  local B, H = V.require("BCH"), H3D()
  local h = B.header(raw)
  if not h then return nil end
  local d = B.relocate(raw, h)
  local ok, anims = pcall(H.materialAnimations, d, h)
  if not (ok and anims and anims[1]) then return nil end
  local out = { frames = 0, mats = {} }
  for _, a in ipairs(anims) do
    out.frames = math.max(out.frames, tonumber(a.frames) or 0)
    for _, el in ipairs(a.elements) do
      if el.target == H.TARGET.texCoord0Trans and el.material and (el.x ~= nil or el.y ~= nil) then
        out.mats[el.material] = { x = el.x, y = el.y }
      end
    end
  end
  if next(out.mats) == nil then return nil end
  return out
end

-- ------------------------------------------------------------- per frame

-- keys = { {f0, f1, x, y, z}, ... } in timeline order: an instant one sets
-- the value, a timed one moves from the current value to it over its span
local function keyed(keys, age, x, y, z)
  for _, k in ipairs(keys or {}) do
    if age < k[1] then break end
    local span = k[2] - k[1]
    if span <= 0 or age >= k[2] then x, y, z = k[3], k[4], k[5]
    else
      local u = (age - k[1]) / span
      x, y, z = x + (k[3] - x) * u, y + (k[4] - y) * u, z + (k[5] - z) * u
    end
  end
  return x, y, z
end

-- size and rotation (radians) of a live model at `age` frames
function M.pose(item, age)
  local sx, sy, sz = keyed(item.scale, age, 1, 1, 1)
  local rx, ry, rz = keyed(item.rot, age, 0, 0, 0)
  local r = math.pi / 180
  return sx, sy, sz, rx * r, ry * r, rz * r
end

-- texture 0 matrix of a mesh at uv-animation frame `f` (nil frame: static)
function M.uvMatrix(mesh, uv, f)
  local t = mesh.uvt
  if not t then return nil end
  local tx, ty = t[5], t[6]
  local a = uv and f and uv.mats and uv.mats[mesh.mat]
  if a then
    local H = H3D()
    if uv.frames and uv.frames > 0 then f = math.min(f, uv.frames) end
    tx = tonumber(H.sampleCurve(a.x, f)) or tx
    ty = tonumber(H.sampleCurve(a.y, f)) or ty
  end
  return H3D().uvMatrix(t[1], t[2], t[3], t[4], tx, ty)
end

-- ------------------------------------------------------------------ draw

local WRAP = { [0] = "clamp", [1] = "clampzero", [2] = "repeat", [3] = "mirroredrepeat" }

local function rotate(rx, ry, rz, x, y, z)
  -- R = Rz * Ry * Rx, as the particles
  local cx, sx = math.cos(rx), math.sin(rx)
  y, z = y * cx - z * sx, y * sx + z * cx
  local cy, sy = math.cos(ry), math.sin(ry)
  x, z = x * cy + z * sy, -x * sy + z * cy
  local cz, sz = math.cos(rz), math.sin(rz)
  x, y = x * cz - y * sz, x * sz + y * cz
  return x, y, z
end
M.rotate = rotate

-- Draws one live model. lm = { data, item, uv, age, meshes = {} (love meshes,
-- kept here) }; toWorld(x, y, z) maps effect cm (after size and rotation) to
-- the battle's world; project(x, y, z) -> screen x, y[, depth]; image(key) ->
-- love Image. Returns the triangle count drawn.
function M.draw(g, lm, age, toWorld, project, image)
  local sx, sy, sz, rx, ry, rz = M.pose(lm.item, age)
  local uvAge = lm.item.uv and (age - lm.item.uv[1]) or nil
  local drawn = 0
  lm.meshes = lm.meshes or {}
  for mi, mesh in ipairs(lm.data.meshes) do
    local img = image(mesh.tex)
    if img then
      local stride = mesh.colors and 9 or 5
      local n = #mesh.v / stride
      local verts, depth, ok = {}, {}, true
      local t = M.uvMatrix(mesh, lm.uv, uvAge and math.max(0, uvAge) or nil)
      local v = mesh.v
      for i = 0, n - 1 do
        local b = i * stride
        local x, y, z = rotate(rx, ry, rz, v[b + 1] * sx, v[b + 2] * sy, v[b + 3] * sz)
        local okP, px, py, pd = pcall(project, toWorld(x, y, z))
        if not (okP and px and py) then ok = false; break end
        local u0, v0 = v[b + 4], v[b + 5]
        local u, w = u0, v0
        if t then u, w = u0 * t.m11 + v0 * t.m21 + t.m41, u0 * t.m12 + v0 * t.m22 + t.m42 end
        -- BCH textures are stored bottom-up: V = 1 is the image's top row
        local r, gg, bb, a = 1, 1, 1, 1
        if mesh.colors then r, gg, bb, a = v[b + 6], v[b + 7], v[b + 8], v[b + 9] end
        verts[i + 1] = { px, py, u, 1 - w, r, gg, bb, a }
        depth[i + 1] = tonumber(pd)
      end
      if ok and n > 0 then
        local m = lm.meshes[mi]
        if m == nil then
          local okM, made = pcall(g.newMesh, n, "triangles", "stream")
          m = okM and made or false
          lm.meshes[mi] = m
        end
        if m then
          -- back to front when the projection gives depth
          local map = mesh.idx
          if depth[1] then
            local tris = {}
            for k = 1, #map - 2, 3 do
              local a, b2, c = map[k], map[k + 1], map[k + 2]
              tris[#tris + 1] = { a, b2, c, (depth[a] or 0) + (depth[b2] or 0) + (depth[c] or 0) }
            end
            table.sort(tris, function(p, q) return p[4] > q[4] end)
            map = {}
            for _, tr in ipairs(tris) do map[#map + 1] = tr[1]; map[#map + 1] = tr[2]; map[#map + 1] = tr[3] end
          end
          m:setVertices(verts)
          pcall(m.setVertexMap, m, map)
          pcall(img.setWrap, img, WRAP[mesh.wrapU] or "repeat", WRAP[mesh.wrapV] or "repeat")
          m:setTexture(img)
          if mesh.blend == "add" then g.setBlendMode("add", "alphamultiply")
          else g.setBlendMode("alpha", "alphamultiply") end
          g.draw(m)
          drawn = drawn + #map / 3
        end
      end
    end
  end
  return drawn
end

return M
