-- Gen4Grass: swaying 3D tall-grass tufts on the cells the engine says are
-- encounter grass, drawn into Gen 4's own world by Gen4Bridge.
--
-- The tufts use the SAME shader path as the voxel scene's grass: Voxel3D.draw
-- with a `sway` value bends the mesh by its model-space height (y / grassH),
-- driven by Wind, and picks up the hour's tint. So the wind you already tuned
-- moves these too -- nothing here reimplements wind.
--
-- Where grass goes is asked of the map (Map:isEncounterCell, falling back to
-- isGrassCell), and how high the ground is comes from the engine's own height
-- query (Gen4Ground:groundY, via scene.groundY), so a tuft on a slope stands on
-- the slope. Nothing about the map is assumed or duplicated.
--
-- PERFORMANCE: one draw call per tuft, capped at MAX. That is deliberately the
-- simplest thing that works; baking per-chunk meshes needs the shader's sway
-- to read a per-vertex base height (it reads model-space y today), so that is a
-- follow-up, not a shortcut taken here.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local Grass = {
  HEIGHT = 9,       -- world px a tuft stands; also the shader's bend normaliser
  WIDTH = 12,       -- world px across each crossed card
  RADIUS = 8,       -- tiles around the view's ground focus
  PER_CELL = 2,
  MAX = 240,        -- draw-call ceiling
  SWAY = 3.5,       -- wind reach at the tip, world px
}

local mesh, texture

local function buildTexture()
  local ok, data = pcall(love.image.newImageData, 16, 16)
  if not ok then return nil end
  local centres = { 3.5, 8.0, 12.5 }
  for y = 0, 15 do
    -- narrow at the tip (y = 0), broad at the root (y = 15)
    local half = 0.45 + 1.6 * (y / 15)
    local light = 1.0 - 0.38 * (y / 15)
    for x = 0, 15 do
      local a = 0
      for _, cx in ipairs(centres) do
        if math.abs(x + 0.5 - cx) <= half then a = 1 break end
      end
      data:setPixel(x, y, 0.30 * light, 0.72 * light, 0.24 * light, a)
    end
  end
  local okImg, image = pcall(love.graphics.newImage, data)
  if not okImg then return nil end
  image:setFilter("nearest", "nearest")
  return image
end

local function buildMesh()
  local verts, map = {}, {}
  local h, hw = Grass.HEIGHT, Grass.WIDTH / 2
  for card = 0, 2 do
    local a = card * math.pi / 3
    local dx, dz = math.cos(a) * hw, math.sin(a) * hw
    local n = #verts / 4
    -- bottom-left, bottom-right, top-right, top-left (see Voxel3D.pushQuad)
    verts[#verts + 1] = { -dx, 0, -dz, 0, 1, 0.72, 0 }
    verts[#verts + 1] = {  dx, 0,  dz, 1, 1, 0.72, 0 }
    verts[#verts + 1] = {  dx, h,  dz, 1, 0, 1.00, 0 }
    verts[#verts + 1] = { -dx, h, -dz, 0, 0, 1.00, 0 }
    Voxel3D.pushQuad(map, n)
  end
  return Voxel3D.newMesh(verts, map)
end

local function hash(a, b)
  local s = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
  return s - math.floor(s)
end

-- The tufts for the cells around a focus, cached until the focus cell (or the
-- map) changes, so the per-frame cost is the draw calls and nothing else.
local cache = { key = nil, list = {} }

local function collect(scene)
  local map = scene.map
  if not map then return {} end
  local predicate = map.isEncounterCell or map.isGrassCell
  if not predicate then return {} end
  local fx, fz = scene.focusPx()
  local ccx, ccy = math.floor(fx / 16), math.floor(fz / 16)
  local key = tostring(map) .. ":" .. ccx .. ":" .. ccy
  if cache.key == key then return cache.list end

  local cells = {}
  local R = Grass.RADIUS
  for cy = ccy - R, ccy + R do
    for cx = ccx - R, ccx + R do
      local inside = not map.inBounds or map:inBounds(cx, cy)
      if inside and predicate(map, cx, cy) then
        local dx, dy = cx - ccx, cy - ccy
        cells[#cells + 1] = { dx * dx + dy * dy, cx, cy }
      end
    end
  end
  table.sort(cells, function(a, b) return a[1] < b[1] end)

  local list = {}
  for _, c in ipairs(cells) do
    if #list >= Grass.MAX then break end
    local cx, cy = c[2], c[3]
    for i = 1, Grass.PER_CELL do
      local px = cx * 16 + 2 + hash(cx + i * 3.1, cy) * 12
      local pz = cy * 16 + 2 + hash(cx, cy + i * 5.7) * 12
      list[#list + 1] = { px, pz, hash(cx * 1.7 + i, cy * 2.3) * math.pi }
      if #list >= Grass.MAX then break end
    end
  end
  cache.key, cache.list = key, list
  return list
end

function Grass.draw(scene)
  if not mesh then
    texture = texture or buildTexture()
    mesh = buildMesh()
  end
  if not (mesh and texture) then return end
  local list = collect(scene)
  if #list == 0 then return end

  -- These cards are not on the voxel grid and carry no window art.
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  Voxel3D.grassH = Grass.HEIGHT
  for i = 1, #list do
    local t = list[i]
    local px, pz = t[1], t[2]
    local wx, wz = scene.toWorld(px, pz)
    local y = scene.groundY(px, pz) or 0
    local model = Mat4.mul(Mat4.translate(wx, y, wz), Mat4.rotateY(t[3]))
    Voxel3D.draw(mesh, texture, model, 0, nil, Grass.SWAY)
  end
  Voxel3D.grassH = nil
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

function Grass.invalidate()
  cache.key, cache.list = nil, {}
end

return Grass
