-- Gen4Bump: a small round dirt pile at Platinum's jump-down ledges.
--
-- WHICH LEDGES
--
-- Gen4Lawn already names the jump-off terrain texture: `allpeak`. Lawn stamps
-- edges.png onto the cartridge's own polygons; this builds a round 3D mound in
-- their place, wearing the same picture (assets/ground/grass/edges.png).
--
-- WHAT THIS BUILDS
--
-- For every 16-unit cell that an allpeak shape covers: one low round pile on
-- the TOP of that geometry (the lip you jump from). Native allpeak is hidden
-- only where a pile was built for that shape (Gen4Hide).
--
-- KNOBS: HEIGHT, MIN_W, MAX_W, SINK, SIDES, WINDOW, enabled.
-- Bridge.disabled.bump turns it off.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local Bump = {
  enabled = true,
  TEXTURES = { allpeak = true},
  WINDOW = 10,
  HEIGHT = 10,                      -- pile height (world units; a tile is 16)
  CAP = 0.88,                      -- unused on the round pile (kept so your value stays)
  MIN_W = 26,                      -- never thinner than this in XZ
  MAX_W = 26,                      -- never wider than one tile
  SINK = 0,                      -- planted this far into the upper terrace
  SIDES = 16,                      -- how round the silhouette is (8 = chunky, 16 = smooth)
  RINGS = 5,                       -- vertical slices from the rim to the tip
  UV = 16,                         -- world units per texture repeat
  BUILDS_PER_FRAME = 4,
  MAX_RESIDENT = 20,
  LOG = true,
  DIR = "/assets/ground/grass/",
  FILE = "edges.png",
  version = 0,
  coverVersion = 0,
}

local FX16 = 4096
local CELL = 16

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Bump: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local clock = (love and love.timer and love.timer.getTime) or os.clock

-- cooperative land builds (lib/Gen4Slice): a land is built over several
-- frames instead of in one call. Without it, everything builds as before.
local Slice = optional("Gen4Slice")
local sliceState = {}
local function check() if Slice then Slice.check() end end
local function newMesh(v, m)
  if Slice then return Slice.newMesh(v, m) end
  return V.require("Voxel3D").newMesh(v, m)
end

-- ---------------------------------------------------------------- texture --

local texture
local function bumpTexture()
  if texture ~= nil then return texture or nil end
  texture = false
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets then
    local path = V.path .. Bump.DIR .. Bump.FILE
    local okE, exists = pcall(Assets.exists, path)
    if okE and exists then
      local ok, img = pcall(Assets.image, path)
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        texture = img
        return img
      end
    end
  end
  once("tex", "no %s%s -- jump-down ledges keep their native look", Bump.DIR, Bump.FILE)
  return nil
end

-- ---------------------------------------------------------------- decoding --

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

local function readShape(ground, s, posScale)
  check()
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
    pos[i] = { s16(vdata, at) / FX16 * posScale,
               s16(vdata, at + 2) / FX16 * posScale,
               s16(vdata, at + 4) / FX16 * posScale }
  end
  local list = {}
  for t = 0, tris - 1 do
    local a1, a2, b1, b2, c1, c2 = idata:byte(t * 6 + 1, t * 6 + 6)
    if not c2 then break end
    list[#list + 1] = { a1 + a2 * 256 + 1, b1 + b2 * 256 + 1, c1 + c2 * 256 + 1 }
  end
  return pos, list
end

local function isCliffShape(s)
  local tex = tostring(s.texture or s.srcTexture or ""):lower()
  local mat = tostring(s.material or s.srcMaterial or ""):lower()
  return Bump.TEXTURES[tex] or Bump.TEXTURES[mat] or false
end

-- ------------------------------------------------------------------ mesh --

local LIGHT = { 0.35, 0.80, 0.50 }

local function clampW(w)
  return math.max(Bump.MIN_W, math.min(Bump.MAX_W, w))
end

local function pushTri(b, p, q, r, cx, cy, cz)
  local ux, uy, uz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
  local vx, vy, vz = r[1] - p[1], r[2] - p[2], r[3] - p[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-8 then return end
  nx, ny, nz = nx / len, ny / len, nz / len
  local mx = (p[1] + q[1] + r[1]) / 3 - cx
  local my = (p[2] + q[2] + r[2]) / 3 - cy
  local mz = (p[3] + q[3] + r[3]) / 3 - cz
  if nx * mx + ny * my + nz * mz < 0 then
    nx, ny, nz = -nx, -ny, -nz
    q, r = r, q
  end
  local lit = math.max(0, nx * LIGHT[1] + ny * LIGHT[2] + nz * LIGHT[3])
  local shade = math.min(1.0, 0.50 + 0.55 * lit)
  if ny > 0.55 then shade = -shade end
  local U = Bump.UV
  local base = #b.verts
  b.verts[base + 1] = { p[1], p[2], p[3], p[1] / U, p[3] / U, shade, 0 }
  b.verts[base + 2] = { q[1], q[2], q[3], q[1] / U, q[3] / U, shade, 0 }
  b.verts[base + 3] = { r[1], r[2], r[3], r[1] / U, r[3] / U, shade, 0 }
  b.map[#b.map + 1], b.map[#b.map + 2], b.map[#b.map + 3] = base + 1, base + 2, base + 3
end

-- Round dirt mound: circular footprint, cosine silhouette, sitting on ymax.
local function pile(b, cx, cz, ymax, spanX, spanZ)
  check()
  local rx, rz = clampW(spanX) * 0.5, clampW(spanZ) * 0.5
  local h = Bump.HEIGHT
  local y0 = ymax - Bump.SINK
  local sides = math.max(8, math.floor(Bump.SIDES or 16))
  local rings = math.max(3, math.floor(Bump.RINGS or 5))
  local midY = y0 + h * 0.4
  local ringsPts = {}
  for ring = 0, rings - 1 do
    local t = ring / rings
    local phi = t * (math.pi * 0.5)
    local rr, yy = math.cos(phi), math.sin(phi) * h
    local row = {}
    for s = 0, sides - 1 do
      local ang = (s / sides) * math.pi * 2
      row[s] = { cx + math.cos(ang) * rx * rr, y0 + yy, cz + math.sin(ang) * rz * rr }
    end
    ringsPts[ring] = row
  end
  local tip = { cx, y0 + h, cz }
  for ring = 0, rings - 2 do
    local a, c = ringsPts[ring], ringsPts[ring + 1]
    for s = 0, sides - 1 do
      local n = (s + 1) % sides
      pushTri(b, a[s], a[n], c[n], cx, midY, cz)
      pushTri(b, a[s], c[n], c[s], cx, midY, cz)
    end
  end
  local last = ringsPts[rings - 1]
  for s = 0, sides - 1 do
    pushTri(b, last[s], last[(s + 1) % sides], tip, cx, midY, cz)
  end
end

-- ------------------------------------------------------------------ lands --

local landEntries = setmetatable({}, { __mode = "k" })
local resident = 0
local list = {}
local window = {}
local tick = 0
Bump.active = {}
local lastCoverSig = ""

local function cellKey(x, z)
  return math.floor(x / CELL) .. "," .. math.floor(z / CELL)
end

local function buildLand(ground, land)
  local out = { bumps = 0, shapes = {} }
  local record = ground.terrain.chunks[land]
  if not (record and record.shapes) then return out end
  local b = { verts = {}, map = {} }
  local shapesSeen = 0

  for _, s in ipairs(record.shapes) do
    if isCliffShape(s) then
      shapesSeen = shapesSeen + 1
      local positions, tris = readShape(ground, s, record.posScale or 1)
      if positions then
        local cells = {}
        for _, t in ipairs(tris) do
          local a, c, d = positions[t[1]], positions[t[2]], positions[t[3]]
          if a and c and d then
            local mx = (a[1] + c[1] + d[1]) / 3
            local mz = (a[3] + c[3] + d[3]) / 3
            local key = cellKey(mx, mz)
            local cell = cells[key]
            if not cell then
              cell = { n = 0, sx = 0, sz = 0,
                       xmin = math.huge, xmax = -math.huge,
                       zmin = math.huge, zmax = -math.huge,
                       ymax = -math.huge }
              cells[key] = cell
            end
            for _, p in ipairs({ a, c, d }) do
              cell.n = cell.n + 1
              cell.sx, cell.sz = cell.sx + p[1], cell.sz + p[3]
              cell.xmin, cell.xmax = math.min(cell.xmin, p[1]), math.max(cell.xmax, p[1])
              cell.zmin, cell.zmax = math.min(cell.zmin, p[3]), math.max(cell.zmax, p[3])
              cell.ymax = math.max(cell.ymax, p[2])
            end
          end
        end
        local n = 0
        for _, cell in pairs(cells) do
          local cx = cell.sx / cell.n
          local cz = cell.sz / cell.n
          pile(b, cx, cz, cell.ymax,
               math.max(cell.xmax - cell.xmin, Bump.MIN_W * 0.5),
               math.max(cell.zmax - cell.zmin, Bump.MIN_W * 0.5))
          n = n + 1
        end
        out.bumps = out.bumps + n
        if n > 0 then out.shapes[#out.shapes + 1] = s end
      end
    end
  end

  if #b.verts > 0 then out.mesh = newMesh(b.verts, b.map) end
  if Bump.LOG and shapesSeen > 0 then
    once("land" .. tostring(land),
         "land %s: %d allpeak shape(s) -> %d dirt pile(s); %d native shape(s) hidden",
         tostring(land), shapesSeen, out.bumps, #out.shapes)
  end
  return out
end

local function switchedOn()
  if not Bump.enabled then return false end
  local Bridge = optional("Gen4Bridge")
  return not (Bridge and Bridge.disabled and Bridge.disabled.bump)
end

function Bump.gateKey()
  return tostring(Bump.version) .. (switchedOn() and "+" or "-")
end

function Bump.isBuilt(land)
  if not switchedOn() then return false end
  local e = land ~= nil and landEntries[land]
  return (e and e.mesh) and true or false
end

local function prepare(ground)
  local view = ground and ground.view3d
  if not (Bump.enabled and ground and view and ground.grid and ground.terrain
          and ground.slice and ground.chunkPx and ground.half) then
    list = {}
    return
  end
  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  local camCx, camCy = math.floor(view.x / px), math.floor(view.z / px)
  local qx, qy = math.floor(view.x * 4 / px), math.floor(view.z * 4 / px)
  if window.done and window.ground == ground and window.qx == qx and window.qy == qy then
    list = window.list
    return
  end
  tick = tick + 1
  local want = {}
  local W = Bump.WINDOW
  for cy = camCy - W, camCy + W do
    for cx = camCx - W, camCx + W do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        if land then
          local dx, dz = cx - camCx, cy - camCy
          want[#want + 1] = { dx * dx + dz * dz, cx, cy, land }
        end
      end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)
  local builds, pending, out = 0, 0, {}
  local changed = false
  for _, w in ipairs(want) do
    local land = w[4]
    local entry = landEntries[land]
    if not entry then
      local ok, built
      if builds < Bump.BUILDS_PER_FRAME then
        if Slice then
          local res, why = Slice.landStep(sliceState, Budget, false, "bump", ground, land, buildLand)
          if res ~= nil then ok, built = res ~= false, (res == false and why or res) end
        elseif Budget.allow(false) then
          local t0 = clock()
          ok, built = pcall(buildLand, ground, land)
          Budget.charge(t0, "bump")
        end
      end
      if ok ~= nil then
        builds = builds + 1
        if not ok then
          once("build", "a land failed to build and was skipped: %s", tostring(built))
          built = { bumps = 0, shapes = {} }
        end
        landEntries[land] = built
        entry = built
        resident = resident + 1
        changed = true
      else
        pending = pending + 1
      end
    end
    if entry then
      entry.used = tick
      if entry.mesh then out[#out + 1] = { entry = entry, x = w[2] * px + half, z = w[3] * px + half } end
    end
  end
  if changed then Bump.version = Bump.version + 1 end
  if resident > Bump.MAX_RESIDENT then
    local old = {}
    for land, e in pairs(landEntries) do
      if e.used ~= tick then old[#old + 1] = { e.used or 0, land, e } end
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    local i = 1
    while resident > Bump.MAX_RESIDENT and old[i] do
      local e = old[i][3]
      if e.mesh and e.mesh.release then pcall(e.mesh.release, e.mesh) end
      landEntries[old[i][2]] = nil
      resident = resident - 1
      Bump.version = Bump.version + 1
      i = i + 1
    end
  end
  list = out
  window.ground, window.qx, window.qy, window.list, window.done = ground, qx, qy, out, (pending == 0)

  local active, sig = {}, {}
  for _, w in ipairs(want) do
    local entry = landEntries[w[4]]
    if entry then
      for _, s in ipairs(entry.shapes or {}) do
        active[s] = true
        sig[#sig + 1] = tostring(s)
      end
    end
  end
  Bump.active = active
  -- order-independent: `want` is sorted by distance to the EYE, so turning the
  -- camera reordered an unchanged set and bumped coverVersion, which makes
  -- Gen4Hide re-filter every shape of every drawn model
  table.sort(sig)
  local coverSig = table.concat(sig, ",")
  if coverSig ~= lastCoverSig then
    lastCoverSig = coverSig
    Bump.coverVersion = Bump.coverVersion + 1
  end
end

function Bump.prepare(ground)
  prepare(ground)
end

function Bump.isCovered(record)
  return record ~= nil and Bump.active[record] == true
end

function Bump.draw(scene)
  if not Bump.enabled then return end
  local tex = bumpTexture()
  if not tex then return end
  prepare(scene.ground)
  if #list == 0 then return end
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  local visible = scene.sphereVisible
  local radius = ((scene.ground and scene.ground.chunkPx) or 512) * 0.72 + 80
  for _, item in ipairs(list) do
    if (not visible) or visible(item.x, 0, item.z, radius) then
      Voxel3D.draw(item.entry.mesh, tex, Mat4.translate(item.x, 0, item.z), 0, nil, 0, false)
    end
  end
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

function Bump.invalidate()
  for _, e in pairs(landEntries) do
    if e.mesh and e.mesh.release then pcall(e.mesh.release, e.mesh) end
  end
  landEntries = setmetatable({}, { __mode = "k" })
  resident, list, window = 0, {}, {}
  Bump.active = {}
  texture = nil
  Bump.version = Bump.version + 1
  Bump.coverVersion = Bump.coverVersion + 1
end

return Bump
