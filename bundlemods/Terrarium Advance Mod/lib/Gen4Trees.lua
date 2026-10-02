-- Gen4Trees: the voxel scene's chunky 3D trees, standing in Gen 4's world.
--
-- WHAT PLATINUM DRAWS NOW
--
-- A Sinnoh tree is a FLAT CARD: one 4-vertex quad leaning back toward the
-- cartridge's camera (normal (0, 0.819, 0.575)), many of them per terrain
-- shape (`tree01`, `tree2_01`, `tree04_2`, `tree3_02`, `bf_tree03`, plus the
-- `conttree*` forest-border strips). The engine turns them to face the camera
-- (Gen4Model's BillboardPivot) but they are still flat sprites.
--
-- WHAT THIS DOES INSTEAD
--
-- Reads each single-tree card out of the terrain cache (the same way
-- Gen4Water reads water), reads the card's own texture pixels, and builds the
-- voxel scene's kind of tree from them: the sprite cut into blocks, every
-- opaque block a prism wearing its texel's colour, standing upright on the
-- card's base. Rows are given a depth in proportion to how wide the row is,
-- so a canopy bulges and a trunk stays slim -- round, not a cardboard cutout.
-- Identical neighbouring texels on a row are merged into one wide face, so a
-- flat patch of leaf is one quad and not thirty.
--
-- It uses Gen4Bridge's seam (drawn inside the engine's open depth-tested
-- canvas) and Voxel3D's shader, like Gen4Water / Gen4Sand / Gen4Grass.
--
-- VOID / BORDER TREES (`conttree*`)
--
-- The ring around a Sinnoh map is the same sprite as the walkable trees,
-- tiled sideways on one wide card (Platinum's void-fill). This module splits
-- that card on each texture repeat and stands one voxel tree per copy, so
-- the border matches the trees inside the map.
--
-- WHAT IS LEFT NATIVE (so nothing ever vanishes)
--
-- A shape is hidden by Gen4Hide only when this module has voxel trees for it.
-- A shape is left native when it has geometry that is not a tree card, or is
-- outside WINDOW chunks of the camera, or is not built yet.
--
-- COST
--
-- Trees are baked ONCE PER LAND CHUNK (shared across the map, drawn at every
-- place the engine draws that chunk), one mesh per texture, in a few-ms-per-
-- frame budget. WINDOW (1 = the 3x3 chunks around the camera) is smaller than
-- the ground's window on purpose: a dense forest chunk is a few hundred
-- thousand vertices. Raise GT.WINDOW if the frame time allows it.
--
-- KNOBS: GT.enabled, GT.WINDOW, GT.TEX_STEP (texels per block), GT.DEPTH_FRAC,
-- GT.MAX_QUADS (per land). Bridge.disabled.trees turns the effect off.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local GT = {
  enabled = true,
  WINDOW = 2,             -- chunks each way (same window as Gen4Ground / water)
  TEX_STEP = 2,           -- texels per block edge (1 = full resolution, 4x the quads)
  MAX_BLOCKS = 40,        -- most blocks across one card, whatever the step says
  DEPTH_FRAC = 0.55,      -- a row's depth = this x the row's width ...
  MIN_DEPTH = 3,          -- ... but never thinner than this (world units)
  MAX_DEPTH = 18,         -- ... or deeper than this
  SINK = 0.4,             -- planted this far below the card's base
  MAX_QUADS = 90000,      -- stop covering shapes in a land past this many quads
  BUILDS_PER_FRAME = 2,
  BUILD_BUDGET = 0.004,   -- seconds
  LOG = true,
  coverVersion = 0,       -- bumps whenever the set of covered shapes changes
  active = {},            -- cache shape record -> true (covered AND in the window)
  coveredNames = {},      -- lowercased texture/material/name -> true (hide fallback)
}

-- the cartridge's tree lean, the same constants Gen4Model classifies by
local TREE_NY, TREE_NZ, TREE_TOL = 0.819, 0.575, 0.04
local STRIP_REPEATS = 1.25
local FX16, UV_UNITS = 4096, 16

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Trees: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local cache = setmetatable({}, { __mode = "k" })   -- ground -> { lands = {} }

-- ----------------------------------------------------------- decoding --

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

-- A shape's vertices { x, y, z, u, v } (u, v in TEXELS) and triangles, read the
-- way Gen4Model.new reads them. Stride is measured off the buffer.
local function readShape(ground, s, posScale)
  local vdata, idata = s.vertices, s.indices
  if type(vdata) ~= "string" or type(idata) ~= "string" then
    vdata = ground:slice(s.vertexAt, s.vertexBytes)
    idata = ground:slice(s.indexAt, s.indexBytes)
  end
  local count, tris = s.vertexCount or 0, s.triangleCount or 0
  if not (vdata and idata) or count < 3 or tris < 1 then return nil end
  local stride = math.floor(#vdata / count)
  if stride < 10 then return nil end
  -- pos is the first three s16. UV is next when the vertex is pos+uv (stride
  -- 10), otherwise the last two s16 (pos+normal+uv and similar packs).
  local uvAt = stride >= 16 and (stride - 4) or 6
  local pos = {}
  for i = 1, count do
    local at = (i - 1) * stride
    pos[i] = {
      s16(vdata, at) / FX16 * posScale,
      s16(vdata, at + 2) / FX16 * posScale,
      s16(vdata, at + 4) / FX16 * posScale,
      s16(vdata, at + uvAt) / UV_UNITS,
      s16(vdata, at + uvAt + 2) / UV_UNITS,
    }
  end
  local triList = {}
  for t = 0, tris - 1 do
    local a1, a2, b1, b2, c1, c2 = idata:byte(t * 6 + 1, t * 6 + 6)
    if not c2 then break end
    triList[#triList + 1] = { a1 + a2 * 256 + 1, b1 + b2 * 256 + 1, c1 + c2 * 256 + 1 }
  end
  return pos, triList
end

-- Is this triangle one half of a tree card? The cartridge lean is
-- (0, 0.819, 0.575) toward the default camera, but trees also face east/west
-- and some caches store an upright billboard. Match any yaw of that lean, or
-- a nearly-vertical card.
local function isCardTri(pa, pb, pc)
  local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
  local vx, vy, vz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-6 then return false end
  nx, ny, nz = nx / len, ny / len, nz / len
  if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
  local horiz = math.sqrt(nx * nx + nz * nz)
  return math.abs(ny - TREE_NY) < TREE_TOL and math.abs(horiz - TREE_NZ) < TREE_TOL
end

local function isUprightCard(pa, pb, pc)
  local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
  local vx, vy, vz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-6 then return false end
  ny = ny / len
  local horiz = math.sqrt(nx * nx + nz * nz) / len
  return horiz > 0.85 and math.abs(ny) < 0.4
end

local TREE_SUB = { "tree", "palm", "yashi", "matsu", "sugi" }

local function namesOf(s)
  return (tostring(s.texture or "") .. "\n" .. tostring(s.material or "")
          .. "\n" .. tostring(s.name or "")):lower()
end

function GT.isTreeName(s)
  local n = namesOf(s)
  -- conttree IS a tree: the void-fill border, same sprite, tiled
  for _, sub in ipairs(TREE_SUB) do
    if n:find(sub, 1, true) then return true end
  end
  return false
end

-- Pair triangles into 4-corner cards. NSBMD tree quads often duplicate
-- vertices, so the two halves do not share indices -- matching only on
-- index would leave every tree native. Union-find on shared vertices would
-- glue neighbouring trees into one blob. Consecutive tris (the usual export
-- order) plus unique XYZ is the pairing that actually finds a card.
local function posKey(p)
  return string.format("%.3f:%.3f:%.3f", p[1], p[2], p[3])
end

local function uniquePosList(positions, a, b)
  local seen, list = {}, {}
  local function add(i)
    local p = positions[i]
    if not p then return end
    local k = posKey(p)
    if not seen[k] then seen[k] = i; list[#list + 1] = i end
  end
  for k = 1, 3 do add(a[k]) end
  for k = 1, 3 do add(b[k]) end
  return list
end

local function uvSpanU(positions, verts)
  local lo, hi = math.huge, -math.huge
  for _, i in ipairs(verts) do
    local u = positions[i][4]
    if u < lo then lo = u end
    if u > hi then hi = u end
  end
  return hi - lo
end

local function acceptCard(positions, verts, maxUvW)
  if #verts ~= 4 then return false end
  return not maxUvW or uvSpanU(positions, verts) <= maxUvW
end

local function cardsFromTris(positions, tris, maxUvW)
  local used, cards = {}, {}
  for i = 1, #tris - 1, 2 do
    local verts = uniquePosList(positions, tris[i], tris[i + 1])
    if acceptCard(positions, verts, maxUvW) then
      used[i], used[i + 1] = true, true
      cards[#cards + 1] = verts
    end
  end
  for i = 1, #tris do
    if not used[i] then
      local bestJ, bestN
      for j = i + 1, #tris do
        if not used[j] then
          local verts = uniquePosList(positions, tris[i], tris[j])
          if acceptCard(positions, verts, maxUvW) then
            local n = #verts
            if not bestN or n < bestN then bestJ, bestN = j, n end
          end
        end
      end
      if bestJ then
        used[i], used[bestJ] = true, true
        cards[#cards + 1] = uniquePosList(positions, tris[i], tris[bestJ])
      end
    end
  end
  local leftover = 0
  for i = 1, #tris do
    if not used[i] then leftover = leftover + 1 end
  end
  return cards, leftover
end

-- ----------------------------------------------------------- textures --

local textures = {}   -- path -> { data, image, w, h } | false

local function textureFor(ground, s, set)
  set = set or ground.set
  local list = set and set.textures
  if not list then return nil end
  local rec = (s.palette and list[tostring(s.texture) .. "#" .. s.palette]) or list[s.texture]
  local path = rec and rec.path
  if not path then return nil end
  local hit = textures[path]
  if hit ~= nil then return hit or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  local okD, data = pcall(function()
    return love.image.newImageData(okA and Assets.resolve(path) or path)
  end)
  if not (okD and data) then textures[path] = false; return nil end
  local okI, image = pcall(love.graphics.newImage, data)
  if not (okI and image) then textures[path] = false; return nil end
  image:setFilter("nearest", "nearest")
  image:setWrap("clamp", "clamp")
  local w, h = data:getDimensions()
  hit = { data = data, image = image, w = w, h = h, path = path }
  textures[path] = hit
  return hit
end

-- ------------------------------------------------------------ meshing --

local function face(b, f, x0, y0, z0, dx, dy, dz, u, v)
  local corners = Voxel3D.FACE_CORNERS[f]
  local shade = Voxel3D.FACE_SHADE[f]
  if f == 3 then shade = -shade end          -- the mesher's "faces the sky" flag
  local n = #b.verts / 4
  for k = 1, 4 do
    local c = corners[k]
    b.verts[#b.verts + 1] = { x0 + c[1] * dx, y0 + c[2] * dy, z0 + c[3] * dz, u, v, shade, 0 }
  end
  Voxel3D.pushQuad(b.map, n)
end

local function nearBase(positions, comp, ymin)
  local sx, sz, n = 0, 0, 0
  for _, i in ipairs(comp) do
    if positions[i][2] - ymin <= 0.5 then
      sx, sz, n = sx + positions[i][1], sz + positions[i][3], n + 1
    end
  end
  if n < 1 then
    for _, i in ipairs(comp) do
      sx, sz, n = sx + positions[i][1], sz + positions[i][3], n + 1
    end
  end
  if n < 1 then return 0, 0 end
  return sx / n, sz / n
end

local function meanWhere(positions, comp, axis, value, tol, field)
  local sum, n = 0, 0
  for _, i in ipairs(comp) do
    if math.abs(positions[i][axis] - value) <= tol then
      sum, n = sum + positions[i][field], n + 1
    end
  end
  if n == 0 then return nil end
  return sum / n
end

-- One sprite-wide column of a card (a single tree, or one repeat of a void strip).
local function emitTree(b, tex, uL, uR, vB, vT, originX, baseY, pivZ, width, height)
  if width < 1 or height < 1 then return 0 end
  local nx = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(uR - uL) / GT.TEX_STEP + 0.5)))
  local ny = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(vB - vT) / GT.TEX_STEP + 0.5)))
  local sx, sy = width / nx, height / ny

  local grid, rowCount = {}, {}
  for j = 1, ny do
    local row, cnt = {}, 0
    local v = vT + (vB - vT) * ((j - 0.5) / ny)
    local ty = math.floor(v) % tex.h
    for i = 1, nx do
      local u = uL + (uR - uL) * ((i - 0.5) / nx)
      local tx = math.floor(u) % tex.w
      local okP, r, g, bl, a = pcall(tex.data.getPixel, tex.data, tx, ty)
      if not okP then r, g, bl, a = 0, 0, 0, 0 end
      if a > 1 then r, g, bl, a = r / 255, g / 255, bl / 255, a / 255 end
      if a >= 0.5 then
        row[i] = { key = math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256
                         + math.floor(bl * 255 + 0.5),
                   u = (tx + 0.5) / tex.w, v = (ty + 0.5) / tex.h }
        cnt = cnt + 1
      end
    end
    grid[j], rowCount[j] = row, cnt
  end

  local depth = {}
  for j = 1, ny do
    local d = rowCount[j] * sx * GT.DEPTH_FRAC
    depth[j] = math.max(GT.MIN_DEPTH, math.min(GT.MAX_DEPTH, d))
  end

  local before = #b.verts / 4
  for j = 1, ny do
    local row = grid[j]
    local y0 = baseY + (ny - j) * sy
    local d = depth[j]
    local z0 = pivZ - d * 0.5
    local i = 1
    while i <= nx do
      local cell = row[i]
      if cell then
        local k = i
        while row[k + 1] and row[k + 1].key == cell.key do k = k + 1 end
        local x0, w = originX + (i - 1) * sx, (k - i + 1) * sx
        face(b, 5, x0, y0, z0, w, sy, d, cell.u, cell.v)
        face(b, 6, x0, y0, z0, w, sy, d, cell.u, cell.v)
        i = k + 1
      else
        i = i + 1
      end
    end
    for i2 = 1, nx do
      local cell = row[i2]
      if cell then
        local x0 = originX + (i2 - 1) * sx
        if not row[i2 - 1] then face(b, 2, x0, y0, z0, sx, sy, d, cell.u, cell.v) end
        if not row[i2 + 1] then face(b, 1, x0, y0, z0, sx, sy, d, cell.u, cell.v) end
        local above = grid[j - 1] and grid[j - 1][i2]
        if not above then
          face(b, 3, x0, y0, z0, sx, sy, d, cell.u, cell.v)
        elseif depth[j - 1] < d then
          local step = (d - depth[j - 1]) * 0.5
          face(b, 3, x0, y0, z0, sx, sy, step, cell.u, cell.v)
          face(b, 3, x0, y0, z0 + d - step, sx, sy, step, cell.u, cell.v)
        end
      end
    end
  end
  return #b.verts / 4 - before
end

-- One card -> blocks in bucket `b`. Wide void strips (the same sprite tiled)
-- are split on each texture repeat so each copy is its own tree.
local function buildCard(b, tex, positions, comp)
  local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
  local zmin, zmax = math.huge, -math.huge
  local umin, umax, vmin, vmax = math.huge, -math.huge, math.huge, -math.huge
  for _, i in ipairs(comp) do
    local p = positions[i]
    if p[1] < xmin then xmin = p[1] end
    if p[1] > xmax then xmax = p[1] end
    if p[2] < ymin then ymin = p[2] end
    if p[2] > ymax then ymax = p[2] end
    if p[3] < zmin then zmin = p[3] end
    if p[3] > zmax then zmax = p[3] end
    if p[4] < umin then umin = p[4] end
    if p[4] > umax then umax = p[4] end
    if p[5] < vmin then vmin = p[5] end
    if p[5] > vmax then vmax = p[5] end
  end
  -- Width is the long ground axis of the card (east-west trees are wide in Z).
  -- Height is the slant length the art was drawn at.
  local spanX, spanZ = xmax - xmin, zmax - zmin
  local width = math.max(spanX, spanZ)
  local height = math.sqrt((ymax - ymin) ^ 2 + math.min(spanX, spanZ) ^ 2)
  if width < 1 or height < 1 then return 0 end

  -- which way the art runs: the u at the card's left / right, the v at its
  -- bottom / top, read off the corners (a card may be mirrored)
  local uL, uR
  if spanX >= spanZ then
    uL = meanWhere(positions, comp, 1, xmin, 0.5, 4) or umin
    uR = meanWhere(positions, comp, 1, xmax, 0.5, 4) or umax
  else
    uL = meanWhere(positions, comp, 3, zmin, 0.5, 4) or umin
    uR = meanWhere(positions, comp, 3, zmax, 0.5, 4) or umax
  end
  local vB = meanWhere(positions, comp, 2, ymin, 0.5, 5) or vmax
  local vT = meanWhere(positions, comp, 2, ymax, 0.5, 5) or vmin

  local nx = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(uR - uL) / GT.TEX_STEP + 0.5)))
  local ny = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(vB - vT) / GT.TEX_STEP + 0.5)))
  local sx, sy = width / nx, height / ny
  local pivX, pivZ = nearBase(positions, comp, ymin)
  local originX = pivX - width * 0.5
  local baseY = ymin - GT.SINK

  -- sample the card's art into a grid; row 1 is the top
  local grid, rowCount = {}, {}
  for j = 1, ny do
    local row, cnt = {}, 0
    local v = vT + (vB - vT) * ((j - 0.5) / ny)
    local ty = math.floor(v) % tex.h
    for i = 1, nx do
      local u = uL + (uR - uL) * ((i - 0.5) / nx)
      local tx = math.floor(u) % tex.w
      local okP, r, g, bl, a = pcall(tex.data.getPixel, tex.data, tx, ty)
      if not okP then r, g, bl, a = 0, 0, 0, 0 end
      if a > 1 then r, g, bl, a = r / 255, g / 255, bl / 255, a / 255 end
      if a >= 0.5 then
        row[i] = { key = math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256
                         + math.floor(bl * 255 + 0.5),
                   u = (tx + 0.5) / tex.w, v = (ty + 0.5) / tex.h }
        cnt = cnt + 1
      end
    end
    grid[j], rowCount[j] = row, cnt
  end

  -- a row's depth follows its width: canopies bulge, trunks stay slim
  local depth = {}
  for j = 1, ny do
    local d = rowCount[j] * sx * GT.DEPTH_FRAC
    depth[j] = math.max(GT.MIN_DEPTH, math.min(GT.MAX_DEPTH, d))
  end

  local before = #b.verts / 4
  for j = 1, ny do
    local row = grid[j]
    local y0 = baseY + (ny - j) * sy
    local d = depth[j]
    local z0 = pivZ - d * 0.5
    -- front and back: one quad per run of the same colour
    local i = 1
    while i <= nx do
      local cell = row[i]
      if cell then
        local k = i
        while row[k + 1] and row[k + 1].key == cell.key do k = k + 1 end
        local x0, w = originX + (i - 1) * sx, (k - i + 1) * sx
        face(b, 5, x0, y0, z0, w, sy, d, cell.u, cell.v)
        face(b, 6, x0, y0, z0, w, sy, d, cell.u, cell.v)
        i = k + 1
      else
        i = i + 1
      end
    end
    -- sides and top, only where the neighbour is empty (the silhouette)
    for i2 = 1, nx do
      local cell = row[i2]
      if cell then
        local x0 = originX + (i2 - 1) * sx
        if not row[i2 - 1] then face(b, 2, x0, y0, z0, sx, sy, d, cell.u, cell.v) end
        if not row[i2 + 1] then face(b, 1, x0, y0, z0, sx, sy, d, cell.u, cell.v) end
        local above = grid[j - 1] and grid[j - 1][i2]
        if not above then
          face(b, 3, x0, y0, z0, sx, sy, d, cell.u, cell.v)
        elseif depth[j - 1] < d then
          -- the row above is slimmer: a ledge of this row shows front and back
          local step = (d - depth[j - 1]) * 0.5
          face(b, 3, x0, y0, z0, sx, sy, step, cell.u, cell.v)
          face(b, 3, x0, y0, z0 + d - step, sx, sy, step, cell.u, cell.v)
        end
      end
    end
  end
  return #b.verts / 4 - before
end

local function packedFor(ground, object)
  local index = object.model
  if index == nil then return nil end
  if object.archive == "fldeff" then
    local set = ground.fldeffSet
    local at = set and set.byMember and set.byMember[index]
    return at and set.models and set.models[at], set
  end
  local set = ground.buildingSet
  return set and set.models and set.models[index + 1], set
end

local function objectPlace(object)
  local function scale(v) return (v and v ~= 0) and v or 1 end
  local yaw = object.yaw or object.rotY or object.rotationY or 0
  if math.abs(yaw) > 8 then yaw = math.rad(yaw) end
  return { sx = scale(object.scaleX), sy = scale(object.scaleY), sz = scale(object.scaleZ),
           x = object.x or 0, y = object.y or 0, z = object.z or 0, yaw = yaw }
end

local function applyPlace(positions, place)
  if not place then return positions end
  local c, s = math.cos(place.yaw or 0), math.sin(place.yaw or 0)
  local out = {}
  for i, p in ipairs(positions) do
    local x, y, z = p[1] * place.sx, p[2] * place.sy, p[3] * place.sz
    out[i] = { x * c - z * s + place.x, y + place.y, x * s + z * c + place.z, p[4], p[5] }
  end
  return out
end

-- One land chunk -> { buckets = {{mesh, tex}}, shapes = {record,...}, quads }
local function buildLand(ground, land)
  local record = ground.terrain.chunks[land]
  local out = { buckets = {}, shapes = {}, quads = 0 }
  if not (record and record.shapes) then return out end
  local byPath, order = {}, {}
  local skipped = {}

  local function takeShape(s, posScale, texSet, place)
    local skip
    local named = GT.isTreeName(s)
    if namesOf(s):find("conttree", 1, true) then
      skip = "continuous strip"
    elseif out.quads >= GT.MAX_QUADS then
      skip = "quad budget"
    end
    local positions, tris, tex, comps
    if not skip then
      positions, tris = readShape(ground, s, posScale)
      if not positions then skip = "unreadable" end
    end
    if not skip then
      positions = applyPlace(positions, place)
      if not named then
        local allCards = true
        for _, t in ipairs(tris) do
          local pa, pb, pc = positions[t[1]], positions[t[2]], positions[t[3]]
          if not (pa and pb and pc and isCardTri(pa, pb, pc)) then
            allCards = false
            break
          end
        end
        if not allCards then skip = "not all cards" end
      end
    end
    if not skip then
      tex = textureFor(ground, s, texSet)
      if not tex then skip = "no texture" end
    end
    if not skip then
      local leftover
      comps, leftover = cardsFromTris(positions, tris, STRIP_REPEATS * tex.w)
      if leftover > 0 or #comps == 0 then skip = "not all cards" end
    end

    if skip then
      skipped[skip] = (skipped[skip] or 0) + 1
      return
    end
    local b = byPath[tex.path]
    if not b then
      b = { verts = {}, map = {}, tex = tex.image }
      byPath[tex.path] = b
      order[#order + 1] = b
    end
    for _, comp in ipairs(comps) do
      out.quads = out.quads + buildCard(b, tex, positions, comp)
    end
    out.shapes[#out.shapes + 1] = s
  end

  for _, s in ipairs(record.shapes) do
    local okS, errS = pcall(takeShape, s, record.posScale or 1, ground.set, nil)
    if not okS then
      skipped["error"] = (skipped["error"] or 0) + 1
      once("shape", "a terrain tree shape failed and was left native: %s", tostring(errS))
    end
  end
  for _, object in ipairs(record.objects or {}) do
    local packed, texSet = packedFor(ground, object)
    if packed and packed.shapes then
      local place = objectPlace(object)
      for _, s in ipairs(packed.shapes) do
        local okS, errS = pcall(takeShape, s, packed.posScale or 1, texSet, place)
        if not okS then
          skipped["error"] = (skipped["error"] or 0) + 1
          once("shape", "a prop tree shape failed and was left native: %s", tostring(errS))
        end
      end
    end
  end

  for _, b in ipairs(order) do
    local mesh = Voxel3D.newMesh(b.verts, b.map)
    if mesh then out.buckets[#out.buckets + 1] = { mesh = mesh, tex = b.tex } end
  end
  if GT.LOG and (#out.shapes > 0 or next(skipped)) then
    local why = {}
    for k, n in pairs(skipped) do why[#why + 1] = ("%d %s"):format(n, k) end
    once("land" .. tostring(land),
         "land %s: %d tree shapes voxelised (%d quads); left native: %s",
         tostring(land), #out.shapes, out.quads, #why > 0 and table.concat(why, ", ") or "none")
  end
  return out
end

-- ------------------------------------------------------------- window --

local lastSignature = ""

-- Work out which lands are in the window, build what the budget allows, and
-- publish GT.active (shape records covered RIGHT NOW). Idempotent per frame;
-- Gen4Hide calls it before the native pass, GT.draw calls it again.
function GT.prepare(ground)
  local active, list, names = {}, {}, {}
  GT.active, GT.list, GT.coveredNames = active, list, names
  local view = ground and ground.view3d
  if not (GT.enabled and ground and view and ground.grid and ground.terrain
          and ground.slice and ground.chunkPx and ground.half and ground.set) then
    return
  end
  local rec = cache[ground]
  if not rec then rec = { lands = {} }; cache[ground] = rec end

  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  local W = GT.WINDOW
  local camCx, camCy = math.floor(view.x / px), math.floor(view.z / px)
  local want = {}
  for cy = camCy - W, camCy + W do
    for cx = camCx - W, camCx + W do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local dx, dz = cx - camCx, cy - camCy
        want[#want + 1] = { dx * dx + dz * dz, cx, cy, grid.land[cy * grid.width + cx + 1] }
      end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)

  local now = love.timer and love.timer.getTime
  local started = now and now() or 0
  local builds = 0
  local sig = {}
  for _, w in ipairs(want) do
    local land = w[4]
    local entry = rec.lands[land]
    if not entry then
      local over = builds >= GT.BUILDS_PER_FRAME
        or (builds > 0 and now and (now() - started) > GT.BUILD_BUDGET)
      if not over then
        builds = builds + 1
        local ok, built = pcall(buildLand, ground, land)
        if ok then
          entry = built
        else
          entry = { buckets = {}, shapes = {}, quads = 0 }
          once("build", "a land chunk failed to build and was skipped: %s", tostring(built))
        end
        rec.lands[land] = entry
      end
    end
    if entry then
      sig[#sig + 1] = tostring(land)
      for _, s in ipairs(entry.shapes) do
        active[s] = true
        local n = namesOf(s)
        for part in n:gmatch("[^\n]+") do
          if part ~= "" and part ~= "nil" then names[part] = true end
        end
      end
      if #entry.buckets > 0 then
        list[#list + 1] = { entry = entry, x = w[2] * px + half, z = w[3] * px + half }
      end
    end
  end
  local signature = table.concat(sig, ",")
  if signature ~= lastSignature then
    lastSignature = signature
    GT.coverVersion = GT.coverVersion + 1
  end
end

-- Gen4Hide asks this per cache shape record.
function GT.isCovered(record)
  return record ~= nil and GT.active[record] == true
end

-- Fallback when a built model shape did not keep its cache `src` pointer:
-- hide by the same texture/material/name the voxel pass just covered.
function GT.isCoveredName(shape)
  local names = GT.coveredNames
  if not (shape and names) then return false end
  for _, n in ipairs({
    shape.srcTexture, shape.texture, shape.srcMaterial, shape.material, shape.name
  }) do
    local k = tostring(n or ""):lower()
    if k ~= "" and k ~= "nil" and names[k] then return true end
  end
  return false
end

-- ---------------------------------------------------------------- draw --

function GT.draw(scene)
  if not GT.enabled then return end
  GT.prepare(scene.ground)
  if #GT.list == 0 then return end
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  for _, item in ipairs(GT.list) do
    for _, b in ipairs(item.entry.buckets) do
      Voxel3D.draw(b.mesh, b.tex, Mat4.translate(item.x, 0, item.z), 0, nil, 0, false)
    end
  end
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

-- Drop every baked tree: a map was edited, or the mod was reloaded.
function GT.invalidate()
  for _, rec in pairs(cache) do
    for _, entry in pairs(rec.lands) do
      for _, b in ipairs(entry.buckets or {}) do
        if b.mesh and b.mesh.release then pcall(b.mesh.release, b.mesh) end
      end
    end
  end
  cache = setmetatable({}, { __mode = "k" })
  textures = {}
  GT.active, GT.list, GT.coveredNames = {}, {}, {}
  GT.coverVersion = GT.coverVersion + 1
end

return GT
