-- Gen4Water: the voxel scene's water -- its swell, its cel-shaded paint, its
-- glint and its assets/water/water.png -- laid over Platinum's world.
--
-- HOW THE VOXEL SCENE MAKES WATER, AND WHY THIS CAN JUST REUSE IT
--
-- Water in the voxel scene is ordinary terrain geometry whose vertices carry
-- the VertexWater flag; the scene shader sees the flag and (a) lifts each
-- vertex by the swell (Water.WAVE_A/B, the weather's energy, the freeze), (b)
-- paints the surface in flat dithered bands with the hard-ringed glint, and (c)
-- replaces the albedo with assets/water/water.png sampled in world XZ. The
-- displacement is a function of world XZ alone, so it needs no per-mesh setup.
-- Voxel3D.beginScene sends every one of those uniforms and Gen4Bridge opens a
-- Voxel3D scene each frame, so all this module supplies is the GEOMETRY.
--
-- WHERE THE SHEET GOES (this is the second design)
--
-- The first version laid quads over the cells whose tile BEHAVIOUR said water.
-- That missed every water polygon standing over a cell with another behaviour
-- (shores, deep sea past the map edge, bridges' undersides...) and put the
-- sheet at Gen4Ground:groundY, which is not always the water's own height.
--
-- This one is built from the cartridge's OWN water polygons: the terrain
-- shapes Gen4Hide.classify says are water (`sea`, `water01`, `water:lambert5`,
-- translucent terrain...). They are exactly the shapes Gen4Hide stops the
-- engine drawing, so whatever it hides is covered, at the surface the artists
-- put it. Each land chunk is built once (they are shared across the map),
-- re-tessellated so the swell has vertices to move, and drawn at every place
-- the engine draws that chunk.
--
-- HOW FAR IT DRAWS
--
-- As far as the ground does: the engine draws the chunks within FREE_RADIUS
-- (2) of the camera's chunk, and this draws the water on those same chunks.
-- There is no separate, shorter radius for water to disappear at.
--
-- HEIGHT
--
-- The sheet sits LIFT above the native surface (LIFT_FRAC of a 16 unit cell).
--
-- REFLECTIONS
--
-- The water reflection of the voxel scene is not in the water at all: it is
-- the RayFX screen pass, which finds water by its HEIGHT. GW.level publishes
-- the height of the sheet nearest the camera so Gen4Reflect can tell RayFX
-- where Gen 4's water is.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local GW = {
  WINDOW = 2,             -- chunks each way the ENGINE draws (Gen4Ground FREE_RADIUS)
  EDGE = 10,              -- longest triangle edge after tessellation, world units
  MAX_SPLIT = 52,         -- cap on divisions per triangle edge
  LIFT_FRAC = 0.05,       -- of a cell: how far above the native water the sheet rides
  CELL = 16,
  BUILDS_PER_FRAME = 4,   -- land chunks built in one frame (at most)
  BUILD_BUDGET = 0.004,   -- seconds; at least one is always built
  TOP_SHADE = 0.85,       -- ChunkMesher's VOLUME_TOP_SHADE, the water's own
  UP_ONLY = 0.7,          -- keep triangles whose normal is this far up (not falls)
  ready = false,          -- Gen4Hide reads this: the sheet covers what is hidden
  level = nil,            -- world Y of the sheet nearest the camera (Gen4Reflect)
}
GW.LIFT = GW.LIFT_FRAC * GW.CELL

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Water: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local cache = setmetatable({}, { __mode = "k" })   -- ground -> { lands = {}, complete }

-- ----------------------------------------------------------- decoding --

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

local FX16 = 4096          -- Gen4Model's fixed-point scale

-- One shape's triangles as { {x,y,z}, {x,y,z}, {x,y,z} } in the chunk's own
-- space, read the way Gen4Model.new reads them (stride measured off the
-- buffer, positions are the first three s16 of each vertex).
local function shapeTriangles(ground, s, posScale)
  local vdata = ground:slice(s.vertexAt, s.vertexBytes)
  local idata = ground:slice(s.indexAt, s.indexBytes)
  local count, tris = s.vertexCount or 0, s.triangleCount or 0
  if not (vdata and idata) or count < 3 or tris < 1 then return {} end
  local stride = math.floor(#vdata / count)
  if stride < 6 then return {} end
  local pos = {}
  for i = 0, count - 1 do
    local at = i * stride
    pos[i] = {
      s16(vdata, at) / FX16 * posScale,
      s16(vdata, at + 2) / FX16 * posScale,
      s16(vdata, at + 4) / FX16 * posScale,
    }
  end
  local out = {}
  for t = 0, tris - 1 do
    local a1, a2 = idata:byte(t * 6 + 1, t * 6 + 2)
    local b1, b2 = idata:byte(t * 6 + 3, t * 6 + 4)
    local c1, c2 = idata:byte(t * 6 + 5, t * 6 + 6)
    if c2 then
      local a, b, c = pos[a1 + a2 * 256], pos[b1 + b2 * 256], pos[c1 + c2 * 256]
      if a and b and c then out[#out + 1] = { a, b, c } end
    end
  end
  return out
end

local function isUp(tri)
  local a, b, c = tri[1], tri[2], tri[3]
  local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-6 then return false end
  return math.abs(ny) / len >= GW.UP_ONLY
end

-- A triangle cut into n*n smaller ones so the swell has vertices to lift.
-- Vertex layout is Voxel3D.FORMAT: x, y, z, u, v, shade, water.
local function emit(verts, map, a, b, c)
  local function d(p, q)
    local dx, dz = p[1] - q[1], p[3] - q[3]
    return math.sqrt(dx * dx + dz * dz)
  end
  local longest = math.max(d(a, b), d(b, c), d(c, a))
  local n = math.max(1, math.min(GW.MAX_SPLIT, math.ceil(longest / GW.EDGE)))
  local base, k, idx = #verts, 0, {}
  local sh = GW.TOP_SHADE
  for i = 0, n do
    for j = 0, n - i do
      local fi, fj = i / n, j / n
      verts[#verts + 1] = {
        a[1] + (b[1] - a[1]) * fi + (c[1] - a[1]) * fj,
        a[2] + (b[2] - a[2]) * fi + (c[2] - a[2]) * fj,
        a[3] + (b[3] - a[3]) * fi + (c[3] - a[3]) * fj,
        0, 0, sh, 1,
      }
      k = k + 1
      idx[i * (n + 1) + j] = base + k
    end
  end
  for i = 0, n - 1 do
    for j = 0, n - 1 - i do
      local p00 = idx[i * (n + 1) + j]
      local p10 = idx[(i + 1) * (n + 1) + j]
      local p01 = idx[i * (n + 1) + j + 1]
      map[#map + 1], map[#map + 2], map[#map + 3] = p00, p10, p01
      if i + j < n - 1 then
        local p11 = idx[(i + 1) * (n + 1) + j + 1]
        map[#map + 1], map[#map + 2], map[#map + 3] = p10, p11, p01
      end
    end
  end
end

-- ------------------------------------------------------------ building --

local function isWaterShape(Hide, s)
  local pseudo = { srcMaterial = s.material, srcTexture = s.texture, srcAlpha = s.alpha }
  if Hide and Hide.classify then return Hide.classify(pseudo) ~= nil end
  local m = tostring(s.material or ""):lower()
  local t = tostring(s.texture or ""):lower()
  return m == "sea" or t == "sea" or m:find("^water") ~= nil or t:find("^water") ~= nil
end

-- One land chunk's sheet, in the chunk's own space. { mesh = nil } when it has
-- no water, which is most of them.
local function buildLand(ground, land)
  local record = ground.terrain and ground.terrain.chunks and ground.terrain.chunks[land]
  if not (record and record.shapes) then return { mesh = nil } end
  local Hide = optional("Gen4Hide")
  local posScale = record.posScale or 1
  local verts, map = {}, {}
  local ysum, ycount = 0, 0
  for _, s in ipairs(record.shapes) do
    if isWaterShape(Hide, s) then
      for _, tri in ipairs(shapeTriangles(ground, s, posScale)) do
        if isUp(tri) then
          emit(verts, map, tri[1], tri[2], tri[3])
          ysum = ysum + tri[1][2] + tri[2][2] + tri[3][2]
          ycount = ycount + 3
        end
      end
    end
  end
  if #verts == 0 then return { mesh = nil } end
  return { mesh = Voxel3D.newMesh(verts, map), y = ysum / ycount }
end

-- ---------------------------------------------------------------- draw --

function GW.draw(scene)
  GW.level = nil
  local ground, view = scene.ground, scene.view
  if not (ground and view and ground.grid and ground.terrain and ground.slice
          and ground.chunkPx and ground.half) then
    once("ground", "the ground has no chunk grid to read water from -- native water kept")
    GW.ready = false
    return
  end
  local Water = optional("Water")
  local tex = Water and Water.artBlank and Water.artBlank() or nil
  if not tex then
    once("tex", "no base texture for the water sheet")
    GW.ready = false
    return
  end
  if not (Water.artOn and Water.artOn() == 1) then
    once("art", "assets/water/water.png not found -- drawing the flat-blue base "
         .. "with the swell, paint and glint (drop the file in to get the art)")
  end

  local rec = cache[ground]
  if not rec then rec = { lands = {} }; cache[ground] = rec end

  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  local W = GW.WINDOW
  local camCx, camCy = math.floor(view.x / px), math.floor(view.z / px)
  local fx, fz = scene.focusPx()
  fx, fz = fx + scene.offsetX, fz + scene.offsetZ         -- map pixels -> world

  local want = {}
  for cy = camCy - W, camCy + W do
    for cx = camCx - W, camCx + W do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local dx, dz = cx * px + half - fx, cy * px + half - fz
        want[#want + 1] = { dx * dx + dz * dz, cx, cy, land }
      end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)

  local now = love.timer and love.timer.getTime
  local started = now and now() or 0
  local builds, missing = 0, false
  local list, nearest, nearestD = {}, nil, math.huge
  for _, w in ipairs(want) do
    local land = w[4]
    local entry = rec.lands[land]
    if not entry then
      local overBudget = builds >= GW.BUILDS_PER_FRAME
        or (builds > 0 and now and (now() - started) > GW.BUILD_BUDGET)
      if overBudget then
        missing = true
      else
        builds = builds + 1
        local ok, built = pcall(buildLand, ground, land)
        if ok then
          entry = built
        else
          entry = { mesh = nil }
          once("land", "a land chunk failed to build and was skipped: %s", tostring(built))
        end
        rec.lands[land] = entry
      end
    end
    if entry and entry.mesh then
      list[#list + 1] = { mesh = entry.mesh, x = w[2] * px + half, z = w[3] * px + half }
      if w[1] < nearestD then nearestD, nearest = w[1], entry end
    end
  end
  -- Latched per ground: once the whole window has been built, walking into
  -- chunks that are not yet must not hand the native water back for a frame.
  if not missing then rec.complete = true end
  GW.ready = rec.complete == true
  if nearest then GW.level = nearest.y + GW.LIFT end
  if #list == 0 then return end

  Voxel3D.seams(false)
  Voxel3D.glass(false)
  for _, item in ipairs(list) do
    Voxel3D.draw(item.mesh, tex, Mat4.translate(item.x, GW.LIFT, item.z), 0, nil, 0, false)
  end
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

-- Drop every baked sheet: a map was edited, or the mod was reloaded.
function GW.invalidate()
  GW.ready, GW.level = false, nil
  for _, rec in pairs(cache) do
    for _, entry in pairs(rec.lands) do
      if entry.mesh and entry.mesh.release then pcall(entry.mesh.release, entry.mesh) end
    end
  end
  cache = setmetatable({}, { __mode = "k" })
end

return GW
