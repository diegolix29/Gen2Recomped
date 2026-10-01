-- Gen4Water: the voxel scene's water -- its swell, its cel-shaded paint, its
-- glint and its assets/water/water.png -- laid over Platinum's own water.
--
-- HOW THE VOXEL SCENE MAKES WATER, AND WHY THIS CAN JUST REUSE IT
--
-- There is no separate "water renderer". Water in the voxel scene is ordinary
-- terrain geometry whose vertices carry the VertexWater flag; the scene shader
-- sees the flag and (a) lifts each vertex by the swell (Water.WAVE_A/B, the
-- weather's energy, the freeze, all sent as uniforms), (b) paints the surface in
-- flat dithered bands with the hard-ringed glint, and (c) replaces the albedo
-- with assets/water/water.png sampled in world XZ. The displacement is a
-- function of world XZ alone, so it needs no per-mesh setup at all.
--
-- Voxel3D.beginScene sends every one of those uniforms, and Gen4Bridge opens a
-- Voxel3D scene each frame, so on Gen 4 they are already in place. All this
-- module has to supply is the GEOMETRY: a flat sheet of water-flagged quads
-- over the cells Platinum says are water. Water.step (the swell clock, ticked
-- by Weather every frame), the WATER row (CALM / SWELL / FLAT), wet/freeze and
-- the water.png drop-in all work exactly as they do in the voxel scene, and
-- for the same reason: they are the same code.
--
-- WHERE THE SHEET GOES
--
-- Cells whose tile behaviour is one of Platinum's still-water values (a Gen 4
-- map stores the behaviour in the cell itself -- Map:blockAt IS the behaviour;
-- see Gen4Battle.behaviourUnder in the engine): WATER_RIVER 16, WATER_SEA 21,
-- and the three unnamed values 17, 18 and 20 the engine's own surfable set
-- lists between them. Left out on purpose: WATERFALL (19, a vertical sheet, not
-- a surface), PUDDLE and SHALLOW_WATER (22, 23 -- you walk through them), and
-- the bridges (115, 120, 124) which are deck, not water.
--
-- The sheet sits at the engine's own height for the cell (Gen4Ground:groundY)
-- plus LIFT, so it covers the engine's water rather than fighting it for the
-- same depth. It is opaque and writes depth, like the voxel scene's water.
--
-- The base texture is Water.artBlank(), a 1x1 blue: with water.png present the
-- shader replaces the albedo with it anyway, and without it you get the flat
-- blue with the same paint and glint rather than a tileset tile that Gen 4 does
-- not have.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local GW = {
  CHUNK = 8,              -- cells per side of one baked sheet
  RADIUS = 8,             -- chunks around the view's ground focus that are drawn (8 x 128 = 1024 units,
                          -- most of what the engine draws, so hiding the native water leaves no far hole)
  NEAR = 3,               -- ring that must be fully built before Gen4Hide drops the native water
  ready = false,          -- Gen4Hide reads this: the sheet is complete around the camera
  SUB = 2,                -- quads per cell side (the swell is a vertex effect)
  LIFT = 1.0,             -- world units above the engine's own water height
  BUILDS_PER_FRAME = 4,
  TOP_SHADE = 0.85,       -- ChunkMesher's VOLUME_TOP_SHADE, the water's own
  BEHAVIOURS = { [16] = true, [17] = true, [18] = true, [20] = true, [21] = true },
}

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

local cache = setmetatable({}, { __mode = "k" })   -- map -> { chunks = {...} }

local function isWater(map, cx, cy)
  if not (map.blockAt and map.inBounds and map:inBounds(cx, cy)) then return false end
  local ok, b = pcall(map.blockAt, map, cx, cy)
  return ok and GW.BEHAVIOURS[b] == true
end

-- One chunk's sheet: SUBxSUB water-flagged quads per water cell, each at its
-- cell's own height. Vertex layout is Voxel3D.FORMAT: x, y, z, u, v, shade,
-- water. UVs are unused by the water art (it samples world XZ) but must exist.
local function buildChunk(scene, map, kx, ky)
  local C, S = GW.CHUNK, GW.SUB
  local step = 16 / S
  local verts, indices = {}, {}
  local n = 0
  for cy = ky * C, ky * C + C - 1 do
    for cx = kx * C, kx * C + C - 1 do
      if isWater(map, cx, cy) then
        local y = scene.groundY(cx * 16 + 8, cy * 16 + 8) or 0
        for sy = 0, S - 1 do
          for sx = 0, S - 1 do
            local x0, z0 = cx * 16 + sx * step, cy * 16 + sy * step
            local x1, z1 = x0 + step, z0 + step
            local sh, w = GW.TOP_SHADE, 1
            -- winding matches the voxel mesher's top faces (Voxel3D.pushQuad
            -- takes them bottom-left, bottom-right, top-right, top-left; the
            -- pipeline draws with culling off, so orientation is not visible)
            verts[#verts + 1] = { x0, y, z1, 0, 1, sh, w }
            verts[#verts + 1] = { x1, y, z1, 1, 1, sh, w }
            verts[#verts + 1] = { x1, y, z0, 1, 0, sh, w }
            verts[#verts + 1] = { x0, y, z0, 0, 0, sh, w }
            Voxel3D.pushQuad(indices, n)
            n = n + 1
          end
        end
      end
    end
  end
  if n == 0 then return { mesh = nil } end
  return { mesh = Voxel3D.newMesh(verts, indices) }
end

function GW.draw(scene)
  GW.ready = false
  local map = scene.map
  if not map then return end
  local Water = optional("Water")
  if not Water then return end
  local tex = Water.artBlank and Water.artBlank() or nil
  if not tex then
    once("tex", "no base texture for the water sheet")
    return
  end
  if not (Water.artOn and Water.artOn() == 1) then
    once("art", "assets/water/water.png not found -- drawing the flat-blue base "
         .. "with the swell, paint and glint (drop the file in to get the art)")
  end

  local rec = cache[map]
  if not rec then rec = { chunks = {} }; cache[map] = rec end

  local fx, fz = scene.focusPx()
  local span = GW.CHUNK * 16
  local kx0, ky0 = math.floor(fx / span), math.floor(fz / span)
  local R = GW.RADIUS
  local want = {}
  for ky = ky0 - R, ky0 + R do
    for kx = kx0 - R, kx0 + R do
      local dx, dy = kx - kx0, ky - ky0
      if dx * dx + dy * dy <= R * R + 1 then want[#want + 1] = { dx * dx + dy * dy, kx, ky } end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)

  local builds, list = 0, {}
  local nearMissing = false
  for _, w in ipairs(want) do
    local key = w[2] .. ":" .. w[3]
    local chunk = rec.chunks[key]
    if not chunk and builds < GW.BUILDS_PER_FRAME then
      builds = builds + 1
      local ok, built = pcall(buildChunk, scene, map, w[2], w[3])
      if ok then
        chunk = built
      else
        chunk = { mesh = nil }
        once("chunk", "a chunk failed to build and was skipped: %s", tostring(built))
      end
      rec.chunks[key] = chunk
    end
    if not chunk and w[1] <= GW.NEAR * GW.NEAR + 1 then nearMissing = true end
    if chunk and chunk.mesh then list[#list + 1] = chunk.mesh end
  end
  -- latched per map: once the ring around the camera has been complete, walking
  -- into new chunks must not hand the native water back for a frame or two
  if not nearMissing then rec.complete = true end
  GW.ready = rec.complete == true
  if #list == 0 then return end

  Voxel3D.seams(false)
  Voxel3D.glass(false)
  local model = Mat4.translate(scene.offsetX, GW.LIFT, scene.offsetZ)
  for _, mesh in ipairs(list) do
    Voxel3D.draw(mesh, tex, model, 0, nil, 0, false)
  end
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

-- Drop every baked sheet: a map was edited, or the mod was reloaded.
function GW.invalidate()
  GW.ready = false
  for _, rec in pairs(cache) do
    for _, chunk in pairs(rec.chunks) do
      if chunk.mesh and chunk.mesh.release then pcall(chunk.mesh.release, chunk.mesh) end
    end
  end
  cache = setmetatable({}, { __mode = "k" })
end

return GW
