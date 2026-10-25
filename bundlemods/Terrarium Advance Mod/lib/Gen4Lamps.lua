-- Gen4Lamps: 3D posts + point lights on Platinum's own lamp textures.
--
-- Gen4Lawn names the street posts (`c1_o02`, `c1_o02b`, and any later id
-- whose swap is lamp.png). They live on TERRAIN shapes, not on
-- building objects -- Jubilife's logs show them as land polygons. This pass
-- reads those shapes the same way Gen4Rocks reads `imped`, clusters nearby
-- cards into one post, plants StreetLamps' mesh there, and feeds the shader
-- a flame from that spot after dark.
--
-- Native lamp cards are hidden where a post was built (Gen4Hide.lamps).
--
-- BLACK / WHITE (NativeWorld.GEN5_LIGHTS)
--
-- Unova has no `c1_o02`. Its lamps are found three ways, and they are NATIVE
-- models, so they keep their own mesh: no voxel post is drawn over them, no
-- card is hidden, they only get the flame (the light Gen4Light and the voxel
-- shader read):
--   1. a placed PROP (Gen4Ground:objectsFor -> buildingSet.models) whose
--      texture name matches NativeWorld.isLampName and that is post-sized;
--   2. a placed prop that is merely a thin tall post (NativeWorld
--      GEN5_LIGHTS.geometry) -- the name-free fallback;
--   3. a lamp-NAMED terrain mesh, clustered into poles.
-- With LOG on every candidate model is logged once (grep "Gen4Lamps: model").

local V = ...
local Voxel3D = V.require("Voxel3D")
local StreetLamps = V.require("StreetLamps")

local Lamps = {
  enabled = true,
  LOG = true,

  LIGHT_RADIUS = 96,     -- one post's pool, world units (6 tiles). Posts stand ~4
                         -- tiles apart, so pools overlap a little and the dark
                         -- between them survives
  LIGHT_LIMIT = 8,       -- the voxel shader's lamp slots
  -- WHAT FOLDS CARDS INTO ONE POST
  --
  -- A single pole is authored as a few cards (crossed quads, or pole + lantern)
  -- that share one footprint, so they sit within a fraction of a tile of each
  -- other. CLUSTER is that fraction. It used to be 96 -- six tiles -- which is
  -- wider than a street: the poles on both kerbs, and the next pole along, all
  -- folded into ONE post planted in the middle of the road, and the same 96 was
  -- applied twice more (seams, lights). A tile is 16 units; a road is 3+ tiles.
  CLUSTER = 12,          -- cards this close are the same pole
  CLUSTER_MAX = 20,      -- ...even for a wide card (never reach the far kerb)
  SCALE = 1.8,           -- ~80% bigger than the Gen 1-3 mesh
  WINDOW = 2,
  BUILDS_PER_FRAME = 4,
  MAX_RESIDENT = 20,
  version = 4,
}

local FX16 = 4096

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local DayNight = optional("DayNight")
local NW = optional("NativeWorld")
local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local clock = (love and love.timer and love.timer.getTime) or os.clock

local warned = {}
local function note(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then
    V.mod.log:info("%s", "Gen4Lamps: " .. fmt:format(...))
  end
end

-- Exact Gen4Lawn street-post ids (c1_o02 / c1_o02b). Not c1_lamp* (buildings).
local function lampNames()
  local ids = {}
  local Lawn = optional("Gen4Lawn")
  if Lawn and Lawn.lampIds then
    local ok, got = pcall(Lawn.lampIds)
    if ok and type(got) == "table" then
      for name in pairs(got) do ids[tostring(name):lower()] = true end
    end
  end
  if not next(ids) then
    ids.c1_o02, ids.c1_o02b = true, true
  end
  return ids
end

local function isLampShape(s, names)
  local tex = tostring(s.texture or s.srcTexture or ""):lower()
  return names[tex] == true
end

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

-- Pair consecutive triangles into cards: { cx, ymin, cz, w, h }.
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
      local sx, sz, ymin, ymax = 0, 0, math.huge, -math.huge
      local xmin, xmax, zmin, zmax = math.huge, -math.huge, math.huge, -math.huge
      for _, p in ipairs(corners) do
        sx, sz = sx + p[1], sz + p[3]
        ymin, ymax = math.min(ymin, p[2]), math.max(ymax, p[2])
        xmin, xmax = math.min(xmin, p[1]), math.max(xmax, p[1])
        zmin, zmax = math.min(zmin, p[3]), math.max(zmax, p[3])
      end
      cards[#cards + 1] = {
        sx / 4, ymin, sz / 4,
        math.max(xmax - xmin, zmax - zmin),
        math.max(0.01, ymax - ymin),
      }
      i = i + 2
    else
      i = i + 1
    end
  end
  return cards
end

-- Two cards belong to one pole when their footprints overlap: closer than
-- CLUSTER, or closer than 3/4 of the wider card (a wide billboard is allowed to
-- reach a little further), never further than CLUSTER_MAX.
local function sameFootprint(wa, wb, dx, dz)
  local r = math.min(Lamps.CLUSTER_MAX,
                     math.max(Lamps.CLUSTER, 0.75 * math.max(wa or 0, wb or 0)))
  return dx * dx + dz * dz <= r * r
end

-- One post per physical pole. Greedy, ANCHORED on the first card (never chained
-- card to card), so a row of poles cannot creep together however many there are.
local function clusterPosts(cards)
  local used, out = {}, {}
  for i, c in ipairs(cards) do
    if not used[i] then
      local sx, sy, sz, n = c[1], c[2], c[3], 1
      used[i] = true
      for j = i + 1, #cards do
        if not used[j] then
          local q = cards[j]
          if sameFootprint(c[4], q[4], q[1] - c[1], q[3] - c[3]) then
            used[j] = true
            sx, sy, sz, n = sx + q[1], math.min(sy, q[2]), sz + q[3], n + 1
          end
        end
      end
      out[#out + 1] = { x = sx / n, y = sy, z = sz / n }
    end
  end
  return out
end

-- ------------------------------------------------------------ Gen 5 lamps --

local function lower(x) return tostring(x or ""):lower() end

local function isGen5(ground)
  return NW ~= nil and NW.groundIsGen5 ~= nil and NW.groundIsGen5(ground) == true
end

-- Gen4Ground's `placement` (scale, optional turn about the vertical, move) as
-- a row-major 3x4 -- the same copy Gen4Glass keeps.
local function placementOf(object)
  local sx = (object.scaleX and object.scaleX ~= 0) and object.scaleX or 1
  local sy = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
  local sz = (object.scaleZ and object.scaleZ ~= 0) and object.scaleZ or 1
  local yaw = object.rotY and object.rotY ~= 0 and math.rad(object.rotY) or nil
  if yaw then
    local c, s = math.cos(yaw), math.sin(yaw)
    return { c * sx, 0, s * sz, object.x or 0,
             0, sy, 0, object.y or 0,
             -s * sx, 0, c * sz, object.z or 0 }
  end
  return { sx, 0, 0, object.x or 0,
           0, sy, 0, object.y or 0,
           0, 0, sz, object.z or 0 }
end

local MODEL_LOG_MAX = 150
local modelLogged = 0

-- packed building model -> { cx, cz, ymin, ymax, reason } for a lamp, or false
local modelVerdict = setmetatable({}, { __mode = "k" })

local function analyseModel(packed, id)
  local hit = modelVerdict[packed]
  if hit ~= nil then return hit or nil end
  modelVerdict[packed] = false
  local cfg = NW.GEN5_LIGHTS
  local geo = cfg.geometry
  local sid = tonumber(id)
  if sid and cfg.denyModels[sid] then return nil end

  local posScale = packed.posScale or 1
  local huge = math.huge
  local xmin, xmax, ymin, ymax, zmin, zmax = huge, -huge, huge, -huge, huge, -huge
  local tris, named, denied, names = 0, false, false, {}
  local shapes = packed.shapes or {}
  for _, sh in ipairs(shapes) do
    local tex, mat = lower(sh.texture), lower(sh.material)
    names[#names + 1] = tex
    if NW.isLampName(sh.texture, sh.material) then named = true end
    if NW.hasAny(tex, geo.deny) or NW.hasAny(mat, geo.deny) then denied = true end
    tris = tris + (sh.triangleCount or 0)
    local vdata, count = sh.vertices, sh.vertexCount or 0
    if type(vdata) == "string" and count > 0 then
      local stride = math.floor(#vdata / count)
      if stride >= 10 then
        for i = 0, count - 1 do
          local at = i * stride
          local x = s16(vdata, at) / FX16 * posScale
          local y = s16(vdata, at + 2) / FX16 * posScale
          local z = s16(vdata, at + 4) / FX16 * posScale
          if x < xmin then xmin = x end
          if x > xmax then xmax = x end
          if y < ymin then ymin = y end
          if y > ymax then ymax = y end
          if z < zmin then zmin = z end
          if z > zmax then zmax = z end
        end
      end
    end
  end
  if xmin == huge then return nil end

  local w, d, h = xmax - xmin, zmax - zmin, ymax - ymin
  local foot = math.max(w, d)
  local reason
  if sid and cfg.lampModels[sid] then
    reason = "listed"
  elseif named and foot <= cfg.maxNamedFoot and h >= cfg.minNamedHeight then
    reason = "name"
  elseif geo.enabled and not denied and #shapes <= geo.maxShapes
         and foot <= geo.maxFoot and h >= geo.minHeight and h <= geo.maxHeight
         and tris <= geo.maxTris then
    reason = "shape"
  end

  if Lamps.LOG and modelLogged < MODEL_LOG_MAX
     and (reason or named or (foot <= 40 and h >= 16 and h <= 140)) then
    modelLogged = modelLogged + 1
    note("model:" .. tostring(id) .. ":" .. tostring(packed),
         "model %s textures=[%s] size %.0fx%.0fx%.0f tris=%d -> %s",
         tostring(id), table.concat(names, ","), w, d, h, tris,
         reason and ("LAMP (" .. reason .. ")") or "not a lamp")
  end
  if not reason then return nil end
  local v = { cx = (xmin + xmax) / 2, cz = (zmin + zmax) / 2,
              ymin = ymin, ymax = ymax, reason = reason }
  modelVerdict[packed] = v
  return v
end

-- A lamp-named terrain MESH (not cards): fold its vertices into poles. A
-- pole straddling a cell edge is merged back by distance.
local function meshPosts(positions)
  local R = Lamps.CLUSTER
  local cells, list = {}, {}
  for _, p in ipairs(positions) do
    local key = math.floor(p[1] / R) * 65536 + math.floor(p[3] / R)
    local c = cells[key]
    if not c then
      c = { sx = 0, sz = 0, n = 0, ymin = math.huge, ymax = -math.huge }
      cells[key] = c
      list[#list + 1] = c
    end
    c.sx, c.sz, c.n = c.sx + p[1], c.sz + p[3], c.n + 1
    if p[2] < c.ymin then c.ymin = p[2] end
    if p[2] > c.ymax then c.ymax = p[2] end
  end
  local out, used = {}, {}
  for i, c in ipairs(list) do
    if not used[i] then
      used[i] = true
      local cx, cz = c.sx / c.n, c.sz / c.n
      local ymin, ymax = c.ymin, c.ymax
      for j = i + 1, #list do
        if not used[j] then
          local q = list[j]
          local dx, dz = q.sx / q.n - cx, q.sz / q.n - cz
          if dx * dx + dz * dz <= R * R then
            used[j] = true
            ymin, ymax = math.min(ymin, q.ymin), math.max(ymax, q.ymax)
          end
        end
      end
      if ymax - ymin >= 8 then
        out[#out + 1] = { x = cx, y = ymin, z = cz, top = ymax, native = true }
      end
    end
  end
  return out
end

-- Every Gen 5 lamp on one land, as native posts (chunk-local x y z, top).
local function gen5Posts(ground, land, record)
  local cfg = NW.GEN5_LIGHTS
  local posts, props, meshes = {}, 0, 0

  local set = ground.buildingSet
  if set and set.models and type(ground.objectsFor) == "function" then
    local ok, objects = pcall(ground.objectsFor, ground, land, record)
    if ok and type(objects) == "table" then
      for _, object in ipairs(objects) do
        if object.archive ~= "fldeff" and not object.live then
          local id = tonumber(object.model)
          local packed = id and set.models[id + 1]
          if packed and packed.shapes then
            local v = analyseModel(packed, id)
            if v then
              local m = placementOf(object)
              posts[#posts + 1] = {
                x = m[1] * v.cx + m[2] * v.ymin + m[3] * v.cz + m[4],
                y = m[5] * v.cx + m[6] * v.ymin + m[7] * v.cz + m[8],
                z = m[9] * v.cx + m[10] * v.ymin + m[11] * v.cz + m[12],
                top = m[5] * v.cx + m[6] * v.ymax + m[7] * v.cz + m[8],
                native = true,
              }
              props = props + 1
            end
          end
        end
      end
    end
  end

  for _, s in ipairs(record.shapes or {}) do
    if NW.isLampName(s.texture, s.material) then
      local positions = readShape(ground, s, record.posScale or 1)
      if positions then
        local xmin, xmax, zmin, zmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
        for _, p in ipairs(positions) do
          xmin, xmax = math.min(xmin, p[1]), math.max(xmax, p[1])
          ymin, ymax = math.min(ymin, p[2]), math.max(ymax, p[2])
          zmin, zmax = math.min(zmin, p[3]), math.max(zmax, p[3])
        end
        -- a lamp-named wall is a lit building (Gen4Glass), not a pole
        if math.max(xmax - xmin, zmax - zmin) <= cfg.maxNamedFoot
           and ymax - ymin >= cfg.minNamedHeight then
          for _, post in ipairs(meshPosts(positions)) do
            posts[#posts + 1] = post
            meshes = meshes + 1
          end
        elseif Lamps.LOG then
          note("terrain:" .. lower(s.texture),
               "terrain shape %s is lamp-named but %.0fx%.0fx%.0f: left to Gen4Glass",
               lower(s.texture), xmax - xmin, zmax - zmin, ymax - ymin)
        end
      end
    end
  end
  return posts, props, meshes
end

local landEntries = setmetatable({}, { __mode = "k" })
local resident = 0
local list = {}
local window = {}
local tick = 0
Lamps.active = {}
Lamps.coverVersion = 0
local lastCoverSig = ""

local function buildLand(ground, land)
  local out = { posts = {}, shapes = {} }
  local record = ground.terrain and ground.terrain.chunks and ground.terrain.chunks[land]
  if not record then return out end
  if not record.shapes then
    if NW and NW.GEN5_LIGHTS and isGen5(ground) then
      local posts = gen5Posts(ground, land, record)
      for _, post in ipairs(posts) do out.posts[#out.posts + 1] = post end
    end
    return out
  end
  local names = lampNames()
  local pts, found = {}, {}
  for _, s in ipairs(record.shapes) do
    if isLampShape(s, names) then
      local positions, tris = readShape(ground, s, record.posScale or 1)
      if positions then
        local cards = cardsOf(positions, tris)
        if #cards > 0 then
          found[#found + 1] = s
          for _, c in ipairs(cards) do pts[#pts + 1] = c end
        end
      end
    end
  end
  out.posts = clusterPosts(pts)
  -- only hide native cards where a 3D post actually stands in
  if #out.posts > 0 then out.shapes = found end
  if Lamps.LOG and (#pts > 0 or #out.posts > 0) then
    note("land" .. tostring(land),
         "land %s: %d lawn-lamp card(s) -> %d post(s) (ids c1_o02*)",
         tostring(land), #pts, #out.posts)
  end
  -- Black/White: native lamps, flame only (never hidden, never replaced)
  if NW and NW.GEN5_LIGHTS and isGen5(ground) then
    local posts, props, meshes = gen5Posts(ground, land, record)
    for _, post in ipairs(posts) do out.posts[#out.posts + 1] = post end
    if Lamps.LOG and #posts > 0 then
      note("g5land" .. tostring(land),
           "land %s: %d Gen5 lamp(s): %d prop(s), %d terrain mesh pole(s)",
           tostring(land), #posts, props, meshes)
    end
  end
  return out
end

function Lamps.prepare(ground)
  local view = ground and ground.view3d
  if not (Lamps.enabled and ground and view and ground.grid and ground.terrain
          and ground.slice and ground.chunkPx and ground.half) then
    list = {}
    Lamps.active = {}
    return
  end
  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  local camCx, camCy = math.floor(view.x / px), math.floor(view.z / px)
  local qx, qy = math.floor(view.x * 4 / px), math.floor(view.z * 4 / px)
  if window.done and window.ground == ground and window.qx == qx and window.qy == qy
     and window.version == Lamps.version then
    list = window.list
    return
  end
  tick = tick + 1
  local want = {}
  local W = Lamps.WINDOW
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
      if builds < Lamps.BUILDS_PER_FRAME and Budget.allow(false) then
        builds = builds + 1
        local t0 = clock()
        local ok, built = pcall(buildLand, ground, land)
        Budget.charge(t0, "lamps")
        if not ok then
          note("build", "a land failed to build and was skipped: %s", tostring(built))
          built = { posts = {}, shapes = {} }
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
      if #(entry.posts or {}) > 0 then
        out[#out + 1] = { entry = entry, x = w[2] * px + half, z = w[3] * px + half }
      end
    end
  end
  if changed then Lamps.version = Lamps.version + 1 end

  if resident > Lamps.MAX_RESIDENT then
    local old = {}
    for land, e in pairs(landEntries) do
      if e.used ~= tick then old[#old + 1] = { e.used or 0, land } end
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    local i = 1
    while resident > Lamps.MAX_RESIDENT and old[i] do
      landEntries[old[i][2]] = nil
      resident = resident - 1
      Lamps.version = Lamps.version + 1
      i = i + 1
    end
  end

  list = out
  window.ground, window.qx, window.qy, window.list, window.done, window.version =
    ground, qx, qy, out, (pending == 0), Lamps.version

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
  Lamps.active = active
  local coverSig = table.concat(sig, ",")
  if coverSig ~= lastCoverSig then
    lastCoverSig = coverSig
    Lamps.coverVersion = Lamps.coverVersion + 1
  end
end

function Lamps.isCovered(record)
  return record ~= nil and Lamps.active[record] == true
end

-- ---------------------------------------------------------------- sites --
--
-- ONE list of world-space posts, resolved once per window and shared by the
-- 3D draw, the voxel shader's lamp slots and the native-city light receiver.
-- They used to each re-merge the posts at 96 units, so a post could be drawn
-- in one place and light another.
local siteCache = nil     -- { list = <the window list it was built from>, sites = {...} }

-- A pole emitted by two lands on a seam folds to one; nothing else does.
local function mergeSeam(sites)
  local used, out = {}, {}
  for i, s in ipairs(sites) do
    if not used[i] then
      local sx, sy, sz, n, top = s.wx, s.wy, s.wz, 1, s.top
      used[i] = true
      for j = i + 1, #sites do
        if not used[j] then
          local q = sites[j]
          if sameFootprint(0, 0, q.wx - s.wx, q.wz - s.wz) then
            used[j] = true
            sx, sy, sz, n = sx + q.wx, math.min(sy, q.wy), sz + q.wz, n + 1
            if q.top then top = top and math.max(top, q.top) or q.top end
          end
        end
      end
      out[#out + 1] = { wx = sx / n, wy = sy, wz = sz / n, scale = Lamps.SCALE,
                        native = s.native, top = top }
    end
  end
  return out
end

local function sitesFor(ground)
  if siteCache and siteCache.list == list and siteCache.ground == ground then
    return siteCache.sites
  end
  local raw = {}
  for _, item in ipairs(list) do
    for _, p in ipairs(item.entry.posts or {}) do
      local x, z = p.x + item.x, p.z + item.z
      local y = p.y or 0
      -- a native Gen 5 prop stands at its own height; terrain cards are
      -- re-seated on the ground under them
      if ground.groundY and not p.native then
        local gy = ground:groundY(x - (ground.offsetX or 0), z - (ground.offsetY or 0))
        if gy then y = gy end
      end
      raw[#raw + 1] = { wx = x, wy = y, wz = z, native = p.native, top = p.top }
    end
  end
  local sites = mergeSeam(raw)
  siteCache = { list = list, ground = ground, sites = sites }
  if Lamps.LOG and #sites > 0 then
    local parts = {}
    for i, s in ipairs(sites) do
      if i > 16 then parts[#parts + 1] = "..."; break end
      parts[#parts + 1] = string.format("(%.0f,%.0f)", s.wx, s.wz)
    end
    note("sites:" .. tostring(#sites) .. ":" .. tostring(Lamps.version),
         "%d post(s) in the window: %s", #sites, table.concat(parts, " "))
  end
  return sites
end

-- The flame's world height above a post's feet: the bake's own lantern height,
-- times the scale the post is drawn at (the shader hangs the flame lampHeight
-- above lampY, and a 1.8x post has a 1.8x lantern).
function Lamps.flameOffset()
  local ok, h = pcall(function() return StreetLamps.flameHeight() end)
  h = (ok and tonumber(h)) or 19
  return h * Lamps.SCALE
end

local function nightNow()
  local okN, night = pcall(DayNight.windowLight)
  return okN and tonumber(night) or 0
end

-- The voxel shader's lamp slots (Voxel3D meshes: posts, trees, NPC bodies, the
-- glass panes). One light per post, nearest first.
function Lamps.collectLights(scene)
  if not Lamps.enabled then return {} end
  local ground = scene and scene.ground
  local view = scene and scene.view
  if not (ground and view) then return {} end

  local night = nightNow()
  if night <= 0.05 then return {} end

  Lamps.prepare(ground)
  local vx, vz = view.x or 0, view.z or 0
  local out = {}
  for _, s in ipairs(sitesFor(ground)) do
    local dx, dz = s.wx - vx, s.wz - vz
    local y = s.wy
    if s.native and s.top then
      -- the shader hangs the flame a lantern's height above y
      y = math.max(s.wy, s.top - Lamps.flameOffset())
    end
    out[#out + 1] = {
      x = s.wx, y = y, z = s.wz,
      radius = Lamps.LIGHT_RADIUS,
      power = night * 0.9,
      d2 = dx * dx + dz * dz,
    }
  end
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  for i = #out, Lamps.LIGHT_LIMIT + 1, -1 do out[i] = nil end
  if #out > 0 and Lamps.LOG then
    note("lit", "feeding %d lamp flame(s) at night=%.2f", #out, night)
  end
  return out
end

local lastSites = {}

function Lamps.draw(scene)
  if not Lamps.enabled then return end
  lastSites = {}
  local ground = scene and scene.ground
  if not ground then return end
  Lamps.prepare(ground)
  if #list == 0 then return end

  local sites = sitesFor(ground)
  lastSites = sites
  if #sites == 0 then return end
  -- a native Gen 5 lamp keeps its own model: only the flame is added
  local mesh = {}
  for _, site in ipairs(sites) do
    if not site.native then mesh[#mesh + 1] = site end
  end
  if #mesh == 0 then return end
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  pcall(StreetLamps.drawWorld, mesh, nightNow())
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

-- Native-city light: the posts that were just drawn, for Gen4Light (the
-- world-space receiver; Platinum's own shader never sees Voxel3D.lampLights).
-- y is the post's feet, fy the flame -- the point the light really comes from.
function Lamps.worldLights()
  local out = {}
  local night = nightNow()
  if night <= 0.05 then return out end
  local flame = Lamps.flameOffset()
  for _, s in ipairs(lastSites) do
    local fy = s.wy + flame
    if s.native and s.top then fy = math.max(s.wy, s.top - 3) end
    out[#out + 1] = {
      x = s.wx, y = s.wy, z = s.wz,
      fy = fy,
      radius = Lamps.LIGHT_RADIUS,
      power = night,
      kind = "post",
    }
  end
  return out
end

function Lamps.invalidate()
  -- the model verdicts depend on NativeWorld.GEN5_LIGHTS, which can be edited
  modelVerdict = setmetatable({}, { __mode = "k" })
  modelLogged = 0
  landEntries = setmetatable({}, { __mode = "k" })
  resident = 0
  list = {}
  window = {}
  siteCache = nil
  lastSites = {}
  Lamps.active = {}
  Lamps.version = Lamps.version + 1
  Lamps.coverVersion = Lamps.coverVersion + 1
end

return Lamps
