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
--   0x50  motion: u32 member (a GF motion pack, lib/GF1Motion.lua, bones by
--         name), u32 ?, u32 loop; starts at its record's frame
--
-- Bake output (mod cache oras/movefx/):
--   models/<m>.lua  { name, meshes = { { tex, blend, wrapU, wrapV, mat,
--                     uvt = {kind, sx, sy, rot, tx, ty}, colors,
--                     v = { x, y, z, u, v, [r, g, b, a] ... }, idx = {...} } } }
--                   positions in cm, bind pose (rigid bones applied), raw UVs
--   uv/<m>.lua      { frames, mats = { [material] = { x = curve|n, y = curve|n } } }
--   motions/<motion>_<model>.lua  { frames, bones = { [bone] = 12 floats per frame } }
--                   (0x50; mesh.bone[vertex] names the bone each vertex follows)
--   tex/<key>.png   shared with the particles
--
-- Not done yet: stage-sized
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
        -- the texture combiner (0xC0-0xFD) rides in the same list
        local regs, found = {}, false
        for _, c in ipairs(cmds) do
          if c.reg >= 0x100 and c.reg <= 0x107 then regs[c.reg] = c.params[1]; found = true
          elseif c.reg >= 0xC0 and c.reg <= 0xFD then regs[c.reg] = c.params[1] end
        end
        if found then return regs end
      end
    end
  end
  return {}
end

-- The combiner's constant colour, when a stage multiplies by it: battle
-- stages are tex0 x vertex colour (stage 0) x const (stage 1). Stage bases
-- 0xC0 0xC8 0xD0 0xD8 0xF0 0xF8: +0 sources, +2 ops, +3 const (R low byte).
local TEV = { 0xC0, 0xC8, 0xD0, 0xD8, 0xF0, 0xF8 }
local function constColor(regs)
  for _, base in ipairs(TEV) do
    local src, cmb, col = regs[base], regs[base + 2], regs[base + 3]
    if src and cmb and col and cmb % 16 == 1 then
      for k = 0, 2 do
        if math.floor(src / 16 ^ k) % 16 == 14 then
          return { col % 256 / 255, math.floor(col / 256) % 256 / 255,
                   math.floor(col / 65536) % 256 / 255, math.floor(col / 16777216) % 256 / 255 }
        end
      end
    end
  end
  return nil
end
M.constColor = constColor

-- One a/0/3/2 member -> the compact model above, or nil, why.
-- writeTexture(name, width, height, imageData) -> key
-- opts (battle arenas, lib/ORASArenas.lua): raw = vertex positions as stored
-- (the arena bases' bind pose is scaled to nothing until their intro anim),
-- maxSpan = size cap (default M.MAX_SPAN), const = keep the combiner's
-- constant colour as mesh.kc
function M.bakeModel(raw, writeTexture, opts)
  opts = opts or {}
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
  for modelIndex, model in ipairs(models) do
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
        kc = opts.const and constColor(regs) or nil,
      }
    end
    for _, mesh in ipairs(model.meshes) do
      local mat = mats[mesh.materialIndex + 1]
      if mat and mat.tex and model.nodeVisible[mesh.nodeIndex] ~= false then
        local bind = H.bindPose(model, mesh)
        -- opts.raw: true = the vertices as stored; "collapsed" = the bind
        -- pose, except for a mesh whose bone shrinks it to nothing (the arena
        -- bases wait at scale 1e-9 for their intro animation). A stage's
        -- rocks, walls and gates are one mesh per bone, all modelled at the
        -- origin: stored as-is they pile up in the middle of the arena.
        local useRaw = opts.raw == true
        if opts.raw == "collapsed" then
          local function span(get)
            local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
            for i = 1, #bind do
              local q = get(i)
              for a = 1, 3 do
                if q[a] < lo[a] then lo[a] = q[a] end
                if q[a] > hi[a] then hi[a] = q[a] end
              end
            end
            return math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3], 0)
          end
          local posed = span(function(i) return bind[i].position end)
          local stored = span(function(i) return mesh.vertices[i].position or bind[i].position end)
          useRaw = posed < stored * 1e-3
        end
        local colors = mesh.vertices[1] and mesh.vertices[1].color ~= nil
        local v, idx = {}, {}
        -- the bone each vertex follows (first model only: 0x50 motions pose
        -- it); smooth vertices take their heaviest bone
        local skin = modelIndex == 1 and #model.bones > 1 and H.skinning(model, mesh) or nil
        local vbone = skin and {} or nil
        for i, b in ipairs(bind) do
          if vbone then
            local rec = skin[i] or {}
            local bone = rec.rigid
            if not bone and rec.bones then
              local best = -1
              for k, w in ipairs(rec.weights or {}) do
                if w > best and rec.bones[k] then best, bone = w, rec.bones[k] end
              end
            end
            vbone[i] = bone or 1
          end
          local raw0 = mesh.vertices[i].uv0 or { 0, 0 }
          local p = useRaw and mesh.vertices[i].position or b.position
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
            mat = mat.mat, uvt = mat.uvt, colors = colors or nil, v = v, idx = idx, bone = vbone,
            kc = mat.kc,
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
  if out.span > (opts.maxSpan or M.MAX_SPAN) then
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

-- A 0x50 motion (GF motion pack, lib/GF1Motion.lua) on one model -> per
-- frame skin matrices (world * inverse bind, 3x4 row-major) of the bones it
-- moves: { frames, bones = { [model bone] = { 12 per frame ... } } }, or nil.
M.MOTION_EPS = 1e-4
function M.bakeMotion(rawModel, rawMotion)
  local B, H, GF = V.require("BCH"), H3D(), V.require("GF1Motion")
  local h = B.header(rawModel)
  if not h then return nil, "model is not BCH" end
  local d = B.relocate(rawModel, h)
  local model = H.models(d, h)[1]
  if not model then return nil, "no model" end
  local okP, skeleton, motions = pcall(GF.readPack, rawMotion)
  if not okP then return nil, "motion pack: " .. tostring(skeleton) end
  local motion
  for i = 0, 15 do if motions[i] then motion = motions[i]; break end end
  if not motion then return nil, "pack has no motion" end
  local names = {}
  for i, b in ipairs(skeleton) do names[i] = b.name end
  local pose = H.poser(model, GF.sample, names)
  local frames = math.max(1, motion.frames)
  -- size guard: posed vertices against the bind pose. Constrict's vine
  -- (model 430: a 0.01-scaled root over x100 joints whose root scale the
  -- motion grows to 1) comes out 36x too big -- a rig not understood yet,
  -- so it stays in its bind pose rather than fill the screen.
  local verts = {}
  for _, mesh in ipairs(model.meshes) do
    local bind, skinRec = H.bindPose(model, mesh), H.skinning(model, mesh)
    for i, b in ipairs(bind) do
      local rec = skinRec[i] or {}
      local bone = rec.rigid
      if not bone and rec.bones then
        local best = -1
        for k, w in ipairs(rec.weights or {}) do if w > best and rec.bones[k] then best, bone = w, rec.bones[k] end end
      end
      verts[#verts + 1] = { b.position[1], b.position[2], b.position[3], bone or 1 }
    end
  end
  local function span(skin)
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, q in ipairs(verts) do
      local x, y, z = q[1], q[2], q[3]
      local m = skin and skin[q[4]]
      if m then x, y, z = m[1] * x + m[2] * y + m[3] * z + m[4], m[5] * x + m[6] * y + m[7] * z + m[8],
                          m[9] * x + m[10] * y + m[11] * z + m[12] end
      lo[1], lo[2], lo[3] = math.min(lo[1], x), math.min(lo[2], y), math.min(lo[3], z)
      hi[1], hi[2], hi[3] = math.max(hi[1], x), math.max(hi[2], y), math.max(hi[3], z)
    end
    return math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
  end
  local bindSpan = span(nil)
  local tracks, moving = {}, {}
  for f = 0, frames do
    local skin = pose(motion, f)
    local s = span(skin)
    if s > bindSpan * 4 + 100 then
      return nil, ("posed size %.0f cm at frame %d against %.0f cm at rest"):format(s, f, bindSpan)
    end
    for b, m in ipairs(skin) do
      local t = tracks[b] or {}
      tracks[b] = t
      local row = { m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12] }
      local id = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }
      for k = 1, 12 do
        t[#t + 1] = row[k]
        local tol = (k == 4 or k == 8 or k == 12) and 0.05 or M.MOTION_EPS
        if math.abs(row[k] - id[k]) > tol then moving[b] = true end
      end
    end
  end
  local out = { frames = frames, bones = {} }
  for b in pairs(moving) do out.bones[b] = tracks[b] end
  if next(out.bones) == nil then return nil, "motion moves nothing" end
  return out
end

-- skin matrix of bone `b` at frame f (lerped between baked frames)
local function motionMatrix(mo, b, f)
  local t = mo.bones[b]
  if not t then return nil end
  local n = mo.frames
  if f <= 0 then f = 0 elseif f >= n then f = n end
  local i = math.floor(f)
  local u = f - i
  local a = i * 12
  if u < 1e-4 or i >= n then
    return t[a + 1], t[a + 2], t[a + 3], t[a + 4], t[a + 5], t[a + 6],
           t[a + 7], t[a + 8], t[a + 9], t[a + 10], t[a + 11], t[a + 12]
  end
  local c = a + 12
  local r = {}
  for k = 1, 12 do r[k] = t[a + k] + (t[c + k] - t[a + k]) * u end
  return unpack(r)
end
M.motionMatrix = motionMatrix

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
  -- 0x50 motion: from its record's frame, looped when its flag says so,
  -- else held on the last frame (before it starts: the bind pose)
  local mo, mf = lm.motion, nil
  local mi = lm.item.motion
  if mo and mi and age >= mi[1] then
    mf = age - mi[1]
    if mi[3] == 1 and mo.frames > 0 then mf = mf % mo.frames end
  end
  return M.drawPosed(g, lm, { sx, sy, sz, rx, ry, rz, 0, 0, 0, mf and mo or nil, mf }, uvAge,
    toWorld, project, image)
end

-- One copy of lm.data at pose = { sx, sy, sz, rx, ry, rz (radians), tx, ty,
-- tz (effect cm) }; uvAge = frames into its texture scroll (or nil). The love
-- meshes are cached on lm and reused copy after copy.
function M.drawPosed(g, lm, pose, uvAge, toWorld, project, image)
  local sx, sy, sz, rx, ry, rz = pose[1], pose[2], pose[3], pose[4], pose[5], pose[6]
  local tx, ty, tz = pose[7] or 0, pose[8] or 0, pose[9] or 0
  local mo, mf = pose[10], pose[11]
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
      -- this frame's bone matrices (0x50 motion), one per bone used
      local mats
      if mo and mf and mesh.bone then
        mats = {}
        for _, bone in ipairs(mesh.bone) do
          if mats[bone] == nil then mats[bone] = { motionMatrix(mo, bone, mf) } end
        end
      end
      for i = 0, n - 1 do
        local b = i * stride
        local x0, y0, z0 = v[b + 1], v[b + 2], v[b + 3]
        local m = mats and mats[mesh.bone[i + 1]]
        if m and m[1] then
          x0, y0, z0 = m[1] * x0 + m[2] * y0 + m[3] * z0 + m[4],
                       m[5] * x0 + m[6] * y0 + m[7] * z0 + m[8],
                       m[9] * x0 + m[10] * y0 + m[11] * z0 + m[12]
        end
        local x, y, z = rotate(rx, ry, rz, x0 * sx, y0 * sy, z0 * sz)
        local okP, px, py, pd = pcall(project, toWorld(x + tx, y + ty, z + tz))
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

-- ----------------------------------------------------------------- sprays
--
-- 0x7B: many copies of one model, each a little rigid body (Pay Day's coin
-- burst, Ice Punch's shards, Earthquake's falling rocks, Spikes).
--   0x7B  u32 member, u32 ?, u32 count per burst, u32 burst interval (0 =
--         once), u32 ?, u32 100, u32 life frames, u32 shape (0 point,
--         1 sphere, 2 cylinder / disc, 3 box), u32 ?, vec3 shape size cm,
--         s32 arc start deg, s32 arc end deg, u32 chance %, 3 x u32 flags
-- and on the same slot, same frame (the spray's setup):
--   0x7E  attach (who, point, offset cm, easing), as 0x2F / 0x43
--   0x7C  vec3 extra emitter offset cm (+ u32)
--   0x85  start size: vec3 min, vec3 max (random between)
--   0x86  start rotation deg: vec3 min, vec3 max
--   0x83  launch: vec3 direction, s32 spread deg, f32 speed cm/frame, f32 drag
--   0x84  gravity: u32 ?, vec3 direction (zero = down), u32 on, f32 cm/frame^2
--   0x87  size over life: 5 x (s32 frame, vec3), frame -1 = unused
--   0x88  extra rotation over life deg: 5 x (s32 frame, vec3)
--   0x8B  floor: u32 ?, u32 on, u32 ?, u32 ?, f32 ground friction (kept speed)
--   0x89  texture scroll: u32 member, u32 ?

local function s32(S, a, p)
  local v = S.u32(a, p)
  return v >= 0x80000000 and v - 4294967296 or v
end

local function vec(S, a, p) return { S.f32(a, p), S.f32(a, p + 4), S.f32(a, p + 8) } end

local function lifeKeys(S, a)
  local keys = {}
  for k = 0, 4 do
    local p = 1 + k * 16
    if #a < p + 15 then break end
    local f = s32(S, a, p)
    if f < 0 then break end
    keys[#keys + 1] = { f, S.f32(a, p + 4), S.f32(a, p + 8), S.f32(a, p + 12) }
  end
  return #keys > 0 and keys or nil
end

-- the spray starting at recs[i] (op 0x7B) -> baked item, or nil
function M.readSpray(S, recs, i, readAttach)
  local r = recs[i]
  local a = r.args
  if #a < 76 then return nil end
  local it = { r.start, r.finish, r.target, S.u32(a, 1),
    count = S.u32(a, 9), every = S.u32(a, 13), life = math.max(1, S.u32(a, 25)),
    shape = S.u32(a, 29), size = vec(S, a, 37), arc = { s32(S, a, 49), s32(S, a, 53) },
    chance = S.u32(a, 57) }
  for j = i + 1, #recs do
    local q = recs[j]
    if q.start ~= r.start then break end
    if q.target == r.target then
      if q.op == 0x7B or q.op == 0x3F then break end
      local b, n = q.args, #q.args
      if q.op == 0x7E and n >= 20 then
        local at = readAttach(q)
        it.role, it.point, it.off = at.role, at.point, at.off
      elseif q.op == 0x7C and n >= 12 then it.shift = vec(S, b, 1)
      elseif q.op == 0x85 and n >= 24 then it.size0 = { vec(S, b, 1), vec(S, b, 13) }
      elseif q.op == 0x86 and n >= 24 then it.rot0 = { vec(S, b, 1), vec(S, b, 13) }
      elseif q.op == 0x83 and n >= 24 then
        it.launch = { vec(S, b, 1), s32(S, b, 13), S.f32(b, 17), S.f32(b, 21) }
      elseif q.op == 0x84 and n >= 24 and S.u32(b, 17) == 1 then
        -- u32 on; a zero direction = straight down (Pay Day's coins)
        local d, k = vec(S, b, 5), S.f32(b, 21)
        if d[1] == 0 and d[2] == 0 and d[3] == 0 then d = { 0, -1, 0 } end
        it.gravity = { d[1] * k, d[2] * k, d[3] * k }
      elseif q.op == 0x87 then it.sizeKeys = lifeKeys(S, b)
      elseif q.op == 0x88 then it.spinKeys = lifeKeys(S, b)
      elseif q.op == 0x8B and n >= 20 and S.u32(b, 5) == 1 then it.bounce = S.f32(b, 17)
      elseif (q.op == 0x89 or q.op == 0x52) and n >= 4 and it.uv == nil then it.uv = { 0, S.u32(b, 1) }
      end
    end
  end
  for _, x in ipairs({ it.size[1], it.size[2], it.size[3], it.arc[1], it.arc[2] }) do
    if x ~= x or math.abs(x) > 1e5 then return nil end
  end
  return it
end

-- life keys -> value at `age` (linear between keys, held past the ends)
local function atKeys(keys, age, x, y, z)
  if not keys then return x, y, z end
  if age <= keys[1][1] then return keys[1][2], keys[1][3], keys[1][4] end
  for k = 1, #keys - 1 do
    local p, q = keys[k], keys[k + 1]
    if age <= q[1] then
      local u = (age - p[1]) / math.max(1e-6, q[1] - p[1])
      return p[2] + (q[2] - p[2]) * u, p[3] + (q[3] - p[3]) * u, p[4] + (q[4] - p[4]) * u
    end
  end
  local l = keys[#keys]
  return l[2], l[3], l[4]
end

M.MAX_COPIES = 64   -- live copies per spray (Earthquake asks for 40 a frame)

-- A running spray: sp = { item, data, uv, age, rng, copies = {} }, stepped
-- once per timeline frame; floorY = the ground in effect cm (or nil).
function M.newSpray(item, data, uv, seed)
  local state = seed or 1
  local function rnd()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end
  return { item = item, data = data, uv = uv, age = 0, rnd = rnd, copies = {} }
end

local function range(rnd, pair, i, default)
  if not pair then return default end
  local lo, hi = pair[1][i], pair[2][i]
  return lo + (hi - lo) * rnd()
end

local function spawnCopy(sp)
  local it, rnd = sp.item, sp.rnd
  -- spawn point from the shape
  local sx, sy, sz = it.size[1], it.size[2], it.size[3]
  local x, y, z = 0, 0, 0
  if it.shape == 1 then          -- sphere
    local u, v, w = rnd() * 2 - 1, rnd() * 2 - 1, rnd() * 2 - 1
    local l = math.sqrt(u * u + v * v + w * w)
    if l > 1e-6 then
      local r = rnd() ^ (1 / 3) / l
      x, y, z = u * r * sx, v * r * sy, w * r * sz
    end
  elseif it.shape == 2 then      -- cylinder / disc, inside the arc
    local a0, a1 = math.rad(it.arc[1] or 0), math.rad(it.arc[2] or 360)
    local ang = a0 + (a1 - a0) * rnd()
    local r = math.sqrt(rnd())
    x, z = math.cos(ang) * r * sx, math.sin(ang) * r * sz
    y = (rnd() - 0.5) * sy
  elseif it.shape == 3 then      -- box
    x, y, z = (rnd() - 0.5) * sx, (rnd() - 0.5) * sy, (rnd() - 0.5) * sz
  end
  if it.shift then x, y, z = x + it.shift[1], y + it.shift[2], z + it.shift[3] end
  -- launch: direction tipped by up to `spread` degrees, any way round
  local vx, vy, vz, drag = 0, 0, 0, 1
  if it.launch then
    local d, spread, speed = it.launch[1], it.launch[2] or 0, it.launch[3] or 0
    drag = it.launch[4] or 1
    local dl = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
    local dx, dy, dz = 0, 1, 0
    if dl > 1e-6 then dx, dy, dz = d[1] / dl, d[2] / dl, d[3] / dl end
    if spread > 0 then
      -- a perpendicular pair to the direction
      local px, py, pz = 1, 0, 0
      if math.abs(dx) > 0.9 then px, py, pz = 0, 1, 0 end
      local ax, ay, az = dy * pz - dz * py, dz * px - dx * pz, dx * py - dy * px
      local al = math.sqrt(ax * ax + ay * ay + az * az)
      ax, ay, az = ax / al, ay / al, az / al
      local bx, by, bz = dy * az - dz * ay, dz * ax - dx * az, dx * ay - dy * ax
      local tilt, turn = math.rad(spread) * rnd(), rnd() * 2 * math.pi
      local ct, st = math.cos(tilt), math.sin(tilt)
      local cu, su = math.cos(turn), math.sin(turn)
      dx = dx * ct + (ax * cu + bx * su) * st
      dy = dy * ct + (ay * cu + by * su) * st
      dz = dz * ct + (az * cu + bz * su) * st
    end
    vx, vy, vz = dx * speed, dy * speed, dz * speed
  end
  local c = {
    x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, drag = drag, age = 0,
    s = { range(rnd, it.size0, 1, 1), range(rnd, it.size0, 2, 1), range(rnd, it.size0, 3, 1) },
    r = { range(rnd, it.rot0, 1, 0), range(rnd, it.rot0, 2, 0), range(rnd, it.rot0, 3, 0) },
  }
  sp.copies[#sp.copies + 1] = c
end

-- one timeline frame
function M.stepSpray(sp, floorY)
  local it = sp.item
  local span = it[2] - it[1]
  if sp.age <= span then
    local every = it.every or 0
    if (every <= 0 and sp.age == 0) or (every > 0 and sp.age % every == 0) then
      for _ = 1, it.count or 0 do
        if #sp.copies >= M.MAX_COPIES then break end
        if (it.chance or 100) >= 100 or sp.rnd() * 100 < it.chance then spawnCopy(sp) end
      end
    end
  end
  local g = it.gravity
  for i = #sp.copies, 1, -1 do
    local c = sp.copies[i]
    c.age = c.age + 1
    if c.age > it.life then table.remove(sp.copies, i) else
      c.vx, c.vy, c.vz = c.vx * c.drag, c.vy * c.drag, c.vz * c.drag
      if g then c.vx, c.vy, c.vz = c.vx + g[1], c.vy + g[2], c.vz + g[3] end
      c.x, c.y, c.z = c.x + c.vx, c.y + c.vy, c.z + c.vz
      -- the floor: a copy lands (stops falling) and keeps that fraction of
      -- its sliding speed each frame on the ground. Spikes' drag 1.1 times
      -- 0.9 here settles them; a bounce would fling them back up for ever.
      if it.bounce and floorY and c.y <= floorY then
        c.y = floorY
        if c.vy < 0 then c.vy = 0 end
        c.vx, c.vz = c.vx * it.bounce, c.vz * it.bounce
      end
    end
  end
  sp.age = sp.age + 1
  return sp.age <= span or #sp.copies > 0
end

-- draws every live copy; returns the triangle count
function M.drawSpray(g, sp, toWorld, project, image)
  local it = sp.item
  local uvAge = it.uv and (sp.age - it.uv[1]) or nil
  local drawn = 0
  local d2r = math.pi / 180
  for _, c in ipairs(sp.copies) do
    local kx, ky, kz = atKeys(it.sizeKeys, c.age, 1, 1, 1)
    local ex, ey, ez = atKeys(it.spinKeys, c.age, 0, 0, 0)
    local pose = { c.s[1] * kx, c.s[2] * ky, c.s[3] * kz,
      (c.r[1] + ex) * d2r, (c.r[2] + ey) * d2r, (c.r[3] + ez) * d2r, c.x, c.y, c.z }
    drawn = drawn + M.drawPosed(g, sp, pose, uvAge, toWorld, project, image)
  end
  return drawn
end

return M
