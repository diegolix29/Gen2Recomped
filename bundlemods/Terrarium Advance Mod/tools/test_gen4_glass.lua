-- Gen4Glass test harness (stubbed LOVE + engine; needs Lua 5.3+ for string.pack).
--   lua tools/test_gen4_glass.lua [lib/Gen4Glass.lua]      (run from the mod root)
-- Property tests: the glass-triangle filter never drops a triangle that touches a
-- pane, the grid clustering equals the pairwise one, the nearest-N pick equals a
-- full sort. Scenario: build + draw 5x5 lands by night and by day, print the counts.
local path = arg[1] or "lib/Gen4Glass.lua"
math.randomseed(12345)

-- ---------------------------------------------------------------- stubs --
local fakeTime = 0
local counters

local DataMT = {}
DataMT.__index = DataMT
function DataMT:getPixel(x, y)
  local p = self.px[y * self.w + x + 1]
  if not p then return 0, 0, 0, 0 end
  return p[1], p[2], p[3], p[4]
end
function DataMT:setPixel(x, y, r, g, b, a) self.px[y * self.w + x + 1] = { r, g, b, a } end
function DataMT:getDimensions() return self.w, self.h end
function DataMT:release() end

local FIX = {}
local function solid(w, h, r, g, b)
  local d = setmetatable({ w = w, h = h, px = {} }, DataMT)
  for y = 0, h - 1 do for x = 0, w - 1 do d:setPixel(x, y, r, g, b, 1) end end
  return d
end
do
  local wall = solid(8, 8, 0.5, 0.5, 0.5)
  for y = 2, 3 do for x = 2, 3 do wall:setPixel(x, y, 1, 1, 1, 1) end end
  FIX["tex/wall.png"] = wall
  FIX["tex/garasu.png"] = solid(4, 4, 0.3, 0.4, 0.5)
  FIX["tex/roof.png"] = solid(8, 8, 0.4, 0.2, 0.2)       -- no white: no glass
end

love = {
  timer = { getTime = function() return fakeTime end },
  image = {
    newImageData = function(a, b)
      if type(a) == "string" then
        local f = assert(FIX[a], "no fixture " .. a)
        local c = setmetatable({ w = f.w, h = f.h, px = {} }, DataMT)
        for i, p in pairs(f.px) do c.px[i] = p end
        return c
      end
      return setmetatable({ w = a, h = b, px = {} }, DataMT)
    end,
  },
  graphics = {
    newImage = function(d)
      return { w = d.w, h = d.h, setFilter = function() end, setWrap = function() end,
               release = function() end, getDimensions = function(s) return s.w, s.h end }
    end,
  },
}
package.preload["src.render.Assets"] = function()
  return { resolve = function(p) return p end }
end

local Voxel3D
local function resetCounters()
  counters = { meshes = 0, verts = 0, tris = 0, glassPass = 0, draws = 0, flatten = 0 }
end
resetCounters()
Voxel3D = {
  newMesh = function(verts, map)
    counters.meshes = counters.meshes + 1
    counters.verts = counters.verts + #verts
    counters.tris = counters.tris + #map / 3
    assert(#map % 3 == 0, "index count not a multiple of 3")
    for _, i in ipairs(map) do assert(verts[i], "index " .. tostring(i) .. " out of range") end
    return { release = function() end, nverts = #verts, ntris = #map / 3 }
  end,
  seams = function() end, glass = function() end,
  flatten = function() counters.flatten = counters.flatten + 1 end,
  glassPass = function() counters.glassPass = counters.glassPass + 1 end,
  draw = function() counters.draws = counters.draws + 1 end,
  lampHeight = 19,
}

local night = 1.0
local DayNight = {
  windowLight = function() return night end,
  lampColor = function() return { 1.0, 0.84, 0.5 } end,
}
local Distance = { reach = function(px) return 1.5 * px end }
local V
V = {
  mod = { log = { info = function() end } },
  require = function(name)
    if name == "Voxel3D" then return Voxel3D end
    if name == "DayNight" then return DayNight end
    if name == "Gen4Distance" and V.useDistance ~= false then return Distance end
    if name == "Mat4" then return { translate = function(x, y, z) return { x, y, z } end } end
    error("no module " .. name)
  end,
}

local chunk = assert(loadfile(path))
local Glass = chunk(V)
Glass.LOG = false

local fails = 0
local function check(cond, msg)
  if not cond then fails = fails + 1; print("  FAIL: " .. msg) end
end

-- ------------------------------------------------- fixture: packed model --
local function pack_shape(image, texture, material, verts, tris)
  -- verts: { {x,y,z,u,v}, ... } in raw s16; u,v in 1/16 texel
  local parts = {}
  for _, v in ipairs(verts) do
    parts[#parts + 1] = string.pack("<hhhhh", v[1], v[2], v[3], v[4], v[5]) .. string.rep("\0", 6)
  end
  local idx = {}
  for _, t in ipairs(tris) do
    for k = 1, 3 do idx[#idx + 1] = string.pack("<H", t[k]) end
  end
  return { image = image, texture = texture, material = material,
           vertices = table.concat(parts), indices = table.concat(idx),
           vertexCount = #verts, triangleCount = #tris }
end
local T = 16  -- raw UV units per texel
local function quad(u0, v0, u1, v1, ox)
  ox = ox or 0
  return {
    { ox + 0,    0, 0, u0 * T, v0 * T },
    { ox + 4096, 0, 0, u1 * T, v0 * T },
    { ox + 4096, 4096, 0, u1 * T, v1 * T },
    { ox + 0,    4096, 0, u0 * T, v1 * T },
  }, { { 0, 1, 2 }, { 0, 2, 3 } }
end
local function shape(image, tex, mat, u0, v0, u1, v1)
  local vs, ts = quad(u0, v0, u1, v1)
  return pack_shape(image, tex, mat, vs, ts)
end

local packed = { posScale = 64, shapes = {
  shape("tex/wall.png", "t1_s01", "m_wall", 0, 0, 8, 8),      -- covers the window: KEPT
  shape("tex/wall.png", "t1_s01", "m_wall", 5, 5, 7, 7),      -- blank corner: DROPPED
  shape("tex/wall.png", "t1_s01", "m_wall", 0, 0, 24, 3),     -- 3 repeats: KEPT
  shape("tex/wall.png", "t1_s01", "m_wall", 7.5, 2, 9.5, 3),  -- wraps, misses the pane: DROPPED
  shape("tex/garasu.png", "wtk_garasu3", "m_g", 0, 0, 1, 1),  -- whole glass: KEPT
  shape("tex/roof.png", "t1_roof", "m_roof", 0, 0, 8, 8),     -- no glass texture: nothing
} }

local function makeGround(landsW)
  local g = { grid = { width = landsW, height = landsW, land = {} }, chunkPx = 512, half = 256,
              terrain = { chunks = {} }, outdoors = true, buildingSet = { models = { packed } } }
  g.objectsFor = function(self, land, record) return record.objects end
  for i = 1, landsW * landsW do
    g.grid.land[i] = i
    local objs = {}
    for k = 1, 4 do objs[k] = { model = 0, x = k * 90, y = 0, z = (i % 3) * 70 } end
    g.terrain.chunks[i] = { objects = objs }
  end
  return g
end
local function makeScene(ground, x, z)
  return { ground = ground, view = { x = x, z = z }, eye = { x, 50, z },
           blend = function() end, opaque = function() end,
           sphereVisible = function() return true end }
end

-- ------------------------------------------------------ property tests --
if Glass._boxHasGlass then
  print("[props] summed-area triangle test vs brute force")
  local w, h = 16, 12
  for trial = 1, 300 do
    local bits, count = {}, 0
    local density = math.random() * 0.15
    for i = 1, w * h do if math.random() < density then bits[i] = true; count = count + 1 end end
    local sat = Glass._buildSat(bits, w, h)
    local entry = { whole = false, sat = sat, bits = bits, w = w, h = h }
    for q = 1, 60 do
      local u0 = (math.random() - 0.5) * 6
      local v0 = (math.random() - 0.5) * 6
      local u1 = u0 + math.random() * (math.random() < 0.3 and 2.5 or 0.3)
      local v1 = v0 + math.random() * (math.random() < 0.3 and 2.5 or 0.3)
      -- brute force: every texel any point of the box lands on
      local want = false
      local xa, xb = math.floor(u0 * w), math.floor(u1 * w)
      local ya, yb = math.floor(v0 * h), math.floor(v1 * h)
      for ty = ya, yb do
        for tx = xa, xb do
          if bits[(ty % h) * w + (tx % w) + 1] then want = true end
        end
      end
      local got = Glass._boxHasGlass(entry, u0, u1, v0, v1)
      if got ~= want then
        check(false, ("box mismatch trial %d: got %s want %s"):format(trial, tostring(got), tostring(want)))
        break
      end
    end
  end

  print("[props] a triangle that touches glass is never dropped")
  local w2, h2 = 8, 8
  local bits = {}
  for y = 2, 3 do for x = 2, 3 do bits[y * w2 + x + 1] = true end end
  bits[6 * w2 + 6 + 1] = true
  local entry = { whole = false, sat = Glass._buildSat(bits, w2, h2), bits = bits, w = w2, h = h2 }
  local dropped, keptN, bad = 0, 0, 0
  for trial = 1, 20000 do
    local function rp() return { (math.random() - 0.5) * 5, (math.random() - 0.5) * 5 } end
    local a, b, c = rp(), rp(), rp()
    if math.random() < 0.7 then   -- mostly small triangles
      b = { a[1] + (math.random() - 0.5) * 0.4, a[2] + (math.random() - 0.5) * 0.4 }
      c = { a[1] + (math.random() - 0.5) * 0.4, a[2] + (math.random() - 0.5) * 0.4 }
    end
    local touches = false
    for s = 1, 150 do
      local r1, r2 = math.random(), math.random()
      if r1 + r2 > 1 then r1, r2 = 1 - r1, 1 - r2 end
      local u = a[1] + r1 * (b[1] - a[1]) + r2 * (c[1] - a[1])
      local v = a[2] + r1 * (b[2] - a[2]) + r2 * (c[2] - a[2])
      if Glass._glassAt(entry, u, v) then touches = true; break end
    end
    local keep = Glass._boxHasGlass(entry, math.min(a[1], b[1], c[1]), math.max(a[1], b[1], c[1]),
                                    math.min(a[2], b[2], c[2]), math.max(a[2], b[2], c[2]))
    if keep then keptN = keptN + 1 else dropped = dropped + 1 end
    if touches and not keep then bad = bad + 1 end
  end
  print(("  kept %d, dropped %d, wrongly dropped %d"):format(keptN, dropped, bad))
  check(bad == 0, "a glass-touching triangle was dropped")
  check(dropped > 1000, "filter should drop a real share of triangles")

  print("[props] clusterPoints: grid vs plain pairwise")
  local function plain(pts, radius)
    local out, used, r2 = {}, {}, radius * radius
    for i, p in ipairs(pts) do
      if not used[i] then
        local sx, sy, sz, n = p[1], p[2], p[3], 1
        used[i] = true
        for j = i + 1, #pts do
          if not used[j] then
            local q = pts[j]
            local dx, dz = q[1] - p[1], q[3] - p[3]
            if dx * dx + dz * dz <= r2 then used[j] = true; sx, sy, sz, n = sx + q[1], sy + q[2], sz + q[3], n + 1 end
          end
        end
        out[#out + 1] = { x = sx / n, y = sy / n, z = sz / n }
      end
    end
    return out
  end
  for trial = 1, 50 do
    local pts = {}
    for i = 1, math.random(1, 400) do
      pts[i] = { (math.random() - 0.5) * 500, math.random() * 60, (math.random() - 0.5) * 500 }
    end
    local a, b = plain(pts, 20), Glass._clusterPoints(pts, 20)
    local same = (#a == #b)
    if same then
      table.sort(a, function(p, q) return p.x < q.x or (p.x == q.x and p.z < q.z) end)
      table.sort(b, function(p, q) return p.x < q.x or (p.x == q.x and p.z < q.z) end)
      for i = 1, #a do
        if math.abs(a[i].x - b[i].x) > 1e-6 or math.abs(a[i].z - b[i].z) > 1e-6 then same = false end
      end
    end
    if not same then check(false, "cluster mismatch trial " .. trial .. (" (%d vs %d)"):format(#a, #b)); break end
  end

  print("[props] nearest(): partial pick vs full sort")
  for trial = 1, 200 do
    local flat = {}
    for i = 1, math.random(0, 300) do flat[i] = { x = math.random() * 1000, z = math.random() * 1000 } end
    local wx, wz, limit = math.random() * 1000, math.random() * 1000, math.random(1, 20)
    local ids, d2s, n = Glass._nearest(flat, wx, wz, limit)
    local all = {}
    for i, p in ipairs(flat) do all[i] = { (p.x - wx) ^ 2 + (p.z - wz) ^ 2, i } end
    table.sort(all, function(a, b) return a[1] < b[1] end)
    check(n == math.min(limit, #flat), "nearest count")
    for i = 1, n do
      if math.abs(d2s[i] - all[i][1]) > 1e-6 then check(false, "nearest order wrong"); break end
    end
  end
end

-- ------------------------------------------------ build / draw scenario --
print("[scene] 5x5 lands, night")
local ground = makeGround(5)
fakeTime = 100
local scene = makeScene(ground, 2.5 * 512, 2.5 * 512)
resetCounters()
local frames = 0
for f = 1, 60 do
  fakeTime = fakeTime + 0.016
  Glass.draw(scene)
  frames = frames + 1
end
local st = counters
print(("  after %d frames: meshes=%d verts=%d tris=%d"):format(frames, st.meshes, st.verts, st.tris))
local lastCounters
resetCounters()
fakeTime = fakeTime + 0.016
Glass.draw(scene)
lastCounters = counters
print(("  one steady frame: glassPass=%d draws=%d flatten=%d"):format(
  lastCounters.glassPass, lastCounters.draws, lastCounters.flatten))
local walls = Glass.wallPieces()
local sl1 = Glass.screenLights(scene.view.x, scene.view.z)
local sl2 = Glass.screenLights(scene.view.x, scene.view.z)
print(("  walls=%d  screenLights=%d  (same table twice: %s)"):format(#walls, #sl1, tostring(sl1 == sl2)))
if sl1[1] then print(("  first light radius=%s power=%.3f"):format(tostring(sl1[1].radius), sl1[1].power)) end

local summary = { tris = st.tris, verts = st.verts, glassPass = lastCounters.glassPass,
                  draws = lastCounters.draws, lights = #sl1, meshes = st.meshes }

print("[scene] daytime builds nothing (new) / builds everything (old)")
Glass.invalidate()
local dground = makeGround(5)
night = 0
resetCounters()
for f = 1, 60 do fakeTime = fakeTime + 0.016; Glass.draw(makeScene(dground, 2.5 * 512, 2.5 * 512)) end
print(("  by day: meshes built=%d draws=%d"):format(counters.meshes, counters.draws))
summary.dayMeshes = counters.meshes
print("  dusk: the lamps come on")
night = 0.5
resetCounters()
for f = 1, 5 do fakeTime = fakeTime + 0.016; Glass.draw(makeScene(dground, 2.5 * 512, 2.5 * 512)) end
print(("  first 5 dusk frames: meshes built=%d draws=%d"):format(counters.meshes, counters.draws))
night = 1

print("SUMMARY " .. string.format("tris=%d verts=%d meshes=%d glassPass/frame=%d draws/frame=%d lights=%d dayMeshes=%d",
  summary.tris, summary.verts, summary.meshes, summary.glassPass, summary.draws, summary.lights, summary.dayMeshes))
print(fails == 0 and "ALL CHECKS PASSED" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
