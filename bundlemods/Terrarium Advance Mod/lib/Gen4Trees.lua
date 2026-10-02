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
-- WHAT IS LEFT NATIVE (so nothing ever vanishes)
--
-- A terrain shape is hidden by Gen4Hide ONLY when this module has voxel trees
-- for EVERY triangle in it. A shape is left native, entirely, when it
--   * is a `conttree*` strip (a forest border: one card holds 2-4 trees and a
--     quad cannot be split on a derivable seam -- see Gen4Model.STRIP_REPEATS),
--   * has any card wider than STRIP_REPEATS texture repeats,
--   * has any triangle that is not part of a tree card, or
--   * is outside WINDOW chunks of the camera, or not built yet.
-- So Platinum's own cards keep drawing in all of those cases.
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
  WINDOW = 1,             -- chunks each way that get voxel trees
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
  local pos = {}
  for i = 1, count do
    local at = (i - 1) * stride
    pos[i] = {
      s16(vdata, at) / FX16 * posScale,
      s16(vdata, at + 2) / FX16 * posScale,
      s16(vdata, at + 4) / FX16 * posScale,
      s16(vdata, at + 6) / UV_UNITS,
      s16(vdata, at + 8) / UV_UNITS,
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

-- Is this triangle one half of a tree card? (Gen4Model's test: the upward form
-- of the normal sits on the cartridge's lean.)
local function isCardTri(pa, pb, pc)
  local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
  local vx, vy, vz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-6 then return false end
  nx, ny, nz = nx / len, ny / len, nz / len
  if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
  return math.abs(nx) < TREE_TOL and math.abs(ny - TREE_NY) < TREE_TOL
     and math.abs(math.abs(nz) - TREE_NZ) < TREE_TOL
end

-- ----------------------------------------------------------- textures --

local textures = {}   -- path -> { data, image, w, h } | false

local function textureFor(ground, s)
  local set = ground.set
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

-- One card -> blocks in bucket `b`. Returns the number of quads emitted.
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
  -- THE CARD LIES BACK about 35 degrees from vertical (normal 0, .819, .575), so
  -- its y extent is only ~58% of the art's real height. The tree stands upright
  -- at the card's full SLANT length, which is what the art was drawn at.
  local width = xmax - xmin
  local height = math.sqrt((ymax - ymin) ^ 2 + (zmax - zmin) ^ 2)
  if width < 1 or height < 1 then return 0 end

  -- which way the art runs: the u at the card's left / right, the v at its
  -- bottom / top, read off the corners (a card may be mirrored)
  local uL = meanWhere(positions, comp, 1, xmin, 0.5, 4) or umin
  local uR = meanWhere(positions, comp, 1, xmax, 0.5, 4) or umax
  local vB = meanWhere(positions, comp, 2, ymin, 0.5, 5) or vmax
  local vT = meanWhere(positions, comp, 2, ymax, 0.5, 5) or vmin

  local nx = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(uR - uL) / GT.TEX_STEP + 0.5)))
  local ny = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(vB - vT) / GT.TEX_STEP + 0.5)))
  local sx, sy = width / nx, height / ny
  local pivX, pivZ = nearBase(positions, comp, ymin)
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
      local r, g, bl, a = tex.data:getPixel(tx, ty)
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
        local x0, w = xmin + (i - 1) * sx, (k - i + 1) * sx
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
        local x0 = xmin + (i2 - 1) * sx
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

-- One land chunk -> { buckets = {{mesh, tex}}, shapes = {record,...}, quads }
local function buildLand(ground, land)
  local record = ground.terrain.chunks[land]
  local out = { buckets = {}, shapes = {}, quads = 0 }
  if not (record and record.shapes) then return out end
  local posScale = record.posScale or 1
  local byPath, order = {}, {}
  local skipped = {}

  for _, s in ipairs(record.shapes) do
    local name = tostring(s.texture or ""):lower()
    local skip
    if name:find("conttree", 1, true) then
      skip = "continuous strip"
    elseif out.quads >= GT.MAX_QUADS then
      skip = "quad budget"
    end
    local positions, tris, tex
    if not skip then
      positions, tris = readShape(ground, s, posScale)
      if not positions then skip = "unreadable" end
    end
    if not skip then
      -- every triangle must be a card, or hiding the shape would take geometry
      for _, t in ipairs(tris) do
        local pa, pb, pc = positions[t[1]], positions[t[2]], positions[t[3]]
        if not (pa and pb and pc and isCardTri(pa, pb, pc)) then skip = "not all cards"; break end
      end
    end
    if not skip then
      tex = textureFor(ground, s)
      if not tex then skip = "no texture" end
    end
    local comps
    if not skip then
      -- cards = connected components of the triangle graph; each must be 4 verts
      local parent = {}
      local function find(a)
        while parent[a] ~= a do
          parent[a] = parent[parent[a]]
          a = parent[a]
        end
        return a
      end
      for _, t in ipairs(tris) do
        for k = 1, 3 do if not parent[t[k]] then parent[t[k]] = t[k] end end
        local ra = find(t[1])
        for k = 2, 3 do
          local rk = find(t[k])
          if rk ~= ra then parent[rk] = ra end
        end
      end
      local groups, glist = {}, {}
      for i in pairs(parent) do
        local r = find(i)
        local g = groups[r]
        if not g then g = {}; groups[r] = g; glist[#glist + 1] = g end
        g[#g + 1] = i
      end
      comps = glist
      for _, comp in ipairs(comps) do
        if #comp ~= 4 then skip = "card is not a quad"; break end
        local lo, hi = math.huge, -math.huge
        for _, i in ipairs(comp) do
          local u = positions[i][4]
          if u < lo then lo = u end
          if u > hi then hi = u end
        end
        if (hi - lo) > STRIP_REPEATS * tex.w then skip = "wide strip"; break end
      end
    end

    if skip then
      skipped[skip] = (skipped[skip] or 0) + 1
    else
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
  local active, list = {}, {}
  GT.active, GT.list = active, list
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
      for _, s in ipairs(entry.shapes) do active[s] = true end
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
  GT.active, GT.list = {}, {}
  GT.coverVersion = GT.coverVersion + 1
end

return GT
