-- Gen4Rocks: small grey voxel rocks standing where Platinum's route rocks are.
--
-- WHAT PLATINUM DRAWS
--
-- The little rocks scattered on routes are terrain shapes whose texture is
-- `imped` (found with the Gen4Lawn colour probe). They are flat cards, like the
-- tree cards Gen4Trees replaces.
--
-- WHAT THIS BUILDS INSTEAD
--
-- For every card of an `imped` shape: one chunky rock made of three stacked
-- voxel blocks (wide base, narrower middle, small cap), offset and sized from a
-- hash of the card's position so the rocks differ but never change between
-- frames. Flat grey, per-face shade like the voxel trees (top 1.0, front .9,
-- side .78, back .68). Same Voxel3D mesh path as Gen4Trees / Gen4Sand.
--
-- HIDING THE NATIVE CARD
--
-- Gen4Lawn swaps `imped` for a fully transparent picture (the model shader
-- discards alpha < 0.5) -- but ONLY on lands where this module has built rocks
-- (Rocks.isBuilt(land)), so a rock is never hidden without a replacement.
--
-- KNOBS: Rocks.SIZE (rock width / card width), MIN_W, MAX_W, Y_OFFSET, SINK,
-- WINDOW, enabled. Bridge.disabled.rocks turns it off.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local Rocks = {
  enabled = true,
  TEXTURES = { imped = true },   -- terrain texture names that are rocks
  WINDOW = 2,                    -- lands each way around the camera
  SIZE = 0.7,                    -- rock width as a fraction of the card's width
  MIN_W = 5,                     -- never narrower than this (world units; a tile is 16)
  MAX_W = 11,                    -- ...never wider than this
  HEIGHT = 0.75,                 -- rock height as a fraction of its width
  -- Trees need Y_OFFSET = -10 because a tall card still shows after the sink.
  -- A rock is only ~8 units tall: the same -10 bury the whole mesh under the
  -- terrain, Lawn then hides the native card, and nothing is left on screen.
  Y_OFFSET = 0,
  SINK = 1.0,                    -- planted this far into the ground
  BUILDS_PER_FRAME = 4,
  MAX_RESIDENT = 20,
  LOG = true,
  version = 0,                   -- bumps whenever the set of built lands changes
}

local FX16, UV_UNITS = 4096, 16
local SHADE = { top = 1.0, front = 0.9, side = 0.78, back = 0.68 }

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Rocks: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local clock = (love and love.timer and love.timer.getTime) or os.clock

-- ---------------------------------------------------------------- texture --

-- An 8x8 grey noise picture generated here, so there is no file to ship. Each
-- block face samples one texel (flat grey, voxel look).
local GRID = 8
local texture                 -- Image | false
local function rockTexture()
  if texture ~= nil then return texture or nil end
  local ok, img = pcall(function()
    local data = love.image.newImageData(GRID, GRID)
    for y = 0, GRID - 1 do
      for x = 0, GRID - 1 do
        local g = 0.50 + 0.16 * (((x * 7 + y * 13 + x * y) % 5) / 4 - 0.5) * 2   -- 0.34..0.66
        data:setPixel(x, y, g, g, g * 1.04, 1)
      end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
  end)
  texture = ok and img or false
  if not texture then once("tex", "could not build the rock texture: %s", tostring(img)) end
  return texture or nil
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

local function posKey(p)
  return string.format("%.2f,%.2f,%.2f", p[1], p[2], p[3])
end

-- Pair consecutive triangles into cards: each pair that shares an edge has four
-- distinct corners. Returns { {cx, baseY, cz, width}, ... }.
local function cardsOf(positions, tris)
  local cards = {}
  local i = 1
  while i < #tris do
    local seen, corners = {}, {}
    for _, t in ipairs({ tris[i], tris[i + 1] }) do
      for k = 1, 3 do
        local p = positions[t[k]]
        if p then
          local key = posKey(p)
          if not seen[key] then seen[key] = true; corners[#corners + 1] = p end
        end
      end
    end
    if #corners == 4 then
      local sx, sz, ymin = 0, 0, math.huge
      local xmin, xmax, zmin, zmax = math.huge, -math.huge, math.huge, -math.huge
      for _, p in ipairs(corners) do
        sx, sz = sx + p[1], sz + p[3]
        ymin = math.min(ymin, p[2])
        xmin, xmax = math.min(xmin, p[1]), math.max(xmax, p[1])
        zmin, zmax = math.min(zmin, p[3]), math.max(zmax, p[3])
      end
      cards[#cards + 1] = { sx / 4, ymin, sz / 4, math.max(xmax - xmin, zmax - zmin) }
      i = i + 2
    else
      i = i + 1        -- not a pair: slide by one and try again
    end
  end
  return cards
end

-- ------------------------------------------------------------------ mesh --

local function hash(x, z)
  local h = math.floor(x * 73.1 + z * 151.7) % 2147483647
  h = (h * 1103515245 + 12345) % 2147483648
  return h / 2147483648
end

local function box(b, x0, y0, z0, w, h, d, cell)
  local u = ((cell % GRID) + 0.5) / GRID
  local v = (math.floor(cell / GRID) % GRID + 0.5) / GRID
  local function face(f, shade)
    local corners = Voxel3D.FACE_CORNERS[f]
    local sh = (f == 3) and -shade or shade      -- +Y is flagged "faces the sky"
    local n = #b.verts / 4
    for k = 1, 4 do
      local c = corners[k]
      b.verts[#b.verts + 1] = { x0 + c[1] * w, y0 + c[2] * h, z0 + c[3] * d, u, v, sh, 0 }
    end
    Voxel3D.pushQuad(b.map, n)
  end
  face(3, SHADE.top)
  face(5, SHADE.front)
  face(6, SHADE.back)
  face(1, SHADE.side)
  face(2, SHADE.side)
end

local function buildRock(b, cx, baseY, cz, cardW)
  local w = math.max(Rocks.MIN_W, math.min(Rocks.MAX_W, cardW * Rocks.SIZE))
  local h = w * Rocks.HEIGHT
  local r1, r2, r3, r4 = hash(cx, cz), hash(cz, cx + 3.1), hash(cx + 9.7, cz - 4.3), hash(cx - 2.2, cz + 8.8)
  local y = baseY - Rocks.SINK
  -- base
  local w0, d0, h0 = w, w * (0.8 + 0.25 * r1), h * 0.45 + Rocks.SINK
  box(b, cx - w0 / 2, y, cz - d0 / 2, w0, h0, d0, math.floor(r1 * 60))
  y = y + h0
  -- middle, shifted off-centre
  local w1, d1, h1 = w0 * (0.62 + 0.12 * r2), d0 * (0.6 + 0.12 * r3), h * 0.35
  local ox, oz = (r2 - 0.5) * (w0 - w1), (r3 - 0.5) * (d0 - d1)
  box(b, cx - w1 / 2 + ox, y, cz - d1 / 2 + oz, w1, h1, d1, math.floor(r2 * 60))
  y = y + h1
  -- cap
  local w2, d2, h2 = w1 * (0.5 + 0.15 * r4), d1 * (0.5 + 0.15 * r1), h * 0.25
  local px, pz = ox + (r4 - 0.5) * (w1 - w2), oz + (r1 - 0.5) * (d1 - d2)
  box(b, cx - w2 / 2 + px, y, cz - d2 / 2 + pz, w2, h2, d2, math.floor(r3 * 60))
  return 15
end

-- ------------------------------------------------------------------ lands --

local landEntries = setmetatable({}, { __mode = "k" })   -- land -> { mesh, rocks }
local resident = 0
local list = {}
local window = {}
local tick = 0

local function buildLand(ground, land)
  local out = { rocks = 0 }
  local record = ground.terrain.chunks[land]
  if not (record and record.shapes) then return out end
  local b = { verts = {}, map = {} }
  local shapesSeen, leftover = 0, 0
  for _, s in ipairs(record.shapes) do
    local tex = tostring(s.texture or s.srcTexture or ""):lower()
    local mat = tostring(s.material or s.srcMaterial or ""):lower()
    if Rocks.TEXTURES[tex] or Rocks.TEXTURES[mat]
        or tex:find("imped", 1, true) or mat:find("imped", 1, true) then
      shapesSeen = shapesSeen + 1
      local positions, tris = readShape(ground, s, record.posScale or 1)
      if positions then
        local cards = cardsOf(positions, tris)
        if #cards == 0 then leftover = leftover + 1 end
        for _, c in ipairs(cards) do
          buildRock(b, c[1], c[2], c[3], c[4])
          out.rocks = out.rocks + 1
        end
      end
    end
  end
  if #b.verts > 0 then out.mesh = Voxel3D.newMesh(b.verts, b.map) end
  if Rocks.LOG and shapesSeen > 0 then
    once("land" .. tostring(land), "land %s: %d imped shape(s) -> %d rocks (%d shape(s) had no usable cards)",
         tostring(land), shapesSeen, out.rocks, leftover)
  end
  return out
end

function Rocks.isBuilt(land)
  local e = land ~= nil and landEntries[land]
  return (e and e.mesh) and true or false
end

local function prepare(ground)
  local view = ground and ground.view3d
  if not (Rocks.enabled and ground and view and ground.grid and ground.terrain
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
  local W = Rocks.WINDOW
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
      if builds < Rocks.BUILDS_PER_FRAME and Budget.allow(false) then
        builds = builds + 1
        local t0 = clock()
        local ok, built = pcall(buildLand, ground, land)
        Budget.charge(t0, "rocks")
        if not ok then
          once("build", "a land failed to build and was skipped: %s", tostring(built))
          built = { rocks = 0 }
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
  if changed then Rocks.version = Rocks.version + 1 end
  -- evict the oldest lands past the cap
  if resident > Rocks.MAX_RESIDENT then
    local old = {}
    for land, e in pairs(landEntries) do
      if e.used ~= tick then old[#old + 1] = { e.used or 0, land, e } end
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    local i = 1
    while resident > Rocks.MAX_RESIDENT and old[i] do
      local e = old[i][3]
      if e.mesh and e.mesh.release then pcall(e.mesh.release, e.mesh) end
      landEntries[old[i][2]] = nil
      resident = resident - 1
      Rocks.version = Rocks.version + 1
      i = i + 1
    end
  end
  list = out
  window.ground, window.qx, window.qy, window.list, window.done = ground, qx, qy, out, (pending == 0)
end

function Rocks.draw(scene)
  if not Rocks.enabled then return end
  local tex = rockTexture()
  if not tex then return end
  prepare(scene.ground)
  if #list == 0 then return end
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  local visible = scene.sphereVisible
  local radius = ((scene.ground and scene.ground.chunkPx) or 512) * 0.72 + 80
  for _, item in ipairs(list) do
    if (not visible) or visible(item.x, 0, item.z, radius) then
      Voxel3D.draw(item.entry.mesh, tex, Mat4.translate(item.x, Rocks.Y_OFFSET or 0, item.z), 0, nil, 0, false)
    end
  end
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

function Rocks.invalidate()
  for _, e in pairs(landEntries) do
    if e.mesh and e.mesh.release then pcall(e.mesh.release, e.mesh) end
  end
  landEntries = setmetatable({}, { __mode = "k" })
  resident, list, window = 0, {}, {}
  texture = nil
  Rocks.version = Rocks.version + 1
end

return Rocks
