-- Dynamic Arena Generator
-- Extracts actual overworld voxel geometry and converts it to arena format at runtime
-- Caches arenas per map ID + trigger location for reuse

local V = ...

local ChunkMesher = V.require("ChunkMesher")
local Voxel3D = V.require("Voxel3D")
local TerrainAtlas = V.require("TerrainAtlas")
local BattleArena = V.require("BattleArena")

local DynamicArena = {}

-- Cache: mapId -> arenaKey -> arena data
local arenaCache = {}

-- Generate a unique key for an arena location
local function arenaKey(map, arena)
  return string.format("%s_%d_%d_%d_%d", 
    map.id or "unknown",
    arena.x or 0, arena.y or 0, arena.w or 0, arena.h or 0)
end

-- Convert Voxel3D vertex format to arena vertex format
-- Voxel3D: {x,y,z, u,v, shade, water}
-- Arena: {x,y,z, u,v, r,g,b,a}
local function convertVertex(vx, vy, vz, u, v, shade, water)
  -- Shade is baked lighting (0-1), convert to color
  -- Base color is white, shaded by the shade value
  local s = math.max(0, math.min(1, math.abs(shade)))
  local r, g, b = s, s, s
  local a = 1.0
  return {vx, vy, vz, u, v, r, g, b, a}
end

-- Extract terrain geometry from the map around the arena area
local function extractTerrain(map, arena)
  -- Define the extraction area (arena footprint + margin)
  local margin = 4 -- cells of margin around the arena
  local cellSize = 16 -- world pixels per cell
  
  local ax = (arena.x - margin) * cellSize
  local ay = (arena.y - margin) * cellSize
  local aw = (arena.w + margin * 2) * cellSize
  local ah = (arena.h + margin * 2) * cellSize
  
  -- Create a mask table to restrict extraction to the arena area
  -- ChunkMesher expects a table of mask rectangles: {x0, z0, x1, z1}
  local masks = {
    {ax, ay, ax + aw, ay + ah}
  }
  
  -- Extract geometry from ChunkMesher
  local v, i, n, wv, wi, wn = ChunkMesher.geometry(map, false, masks, true)
  
  -- Convert vertices to arena format
  local arenaVertices = {}
  for j = 1, n do
    local base = (j - 1) * 7 -- Voxel3D format: 7 floats per vertex
    local vx, vy, vz = v[base + 1], v[base + 2], v[base + 3]
    local u, v_coord = v[base + 4], v[base + 5]
    local shade = v[base + 6]
    local water = v[base + 7]
    
    -- Convert to arena format
    local av = convertVertex(vx, vy, vz, u, v_coord, shade, water)
    arenaVertices[#arenaVertices + 1] = av
  end
  
  -- Convert water vertices if present
  local waterVertices = {}
  if wv and wn > 0 then
    for j = 1, wn do
      local base = (j - 1) * 7
      local vx, vy, vz = wv[base + 1], wv[base + 2], wv[base + 3]
      local u, v_coord = wv[base + 4], wv[base + 5]
      local shade = wv[base + 6]
      local water = wv[base + 7]
      
      -- Water gets a blue tint
      local av = convertVertex(vx, vy, vz, u, v_coord, shade, water)
      av[6] = av[6] * 0.6 -- r
      av[7] = av[7] * 0.8 -- g
      av[8] = av[8] * 1.0 -- b
      av[9] = 0.7 -- alpha (semi-transparent)
      waterVertices[#waterVertices + 1] = av
    end
  end
  
  return arenaVertices, waterVertices, i
end

-- Build arena data from extracted terrain
local function buildArenaData(map, arena, vertices, waterVertices, indices)
  local groups = {}
  
  -- Main terrain group
  if #vertices > 0 then
    local terrainGroup = {
      vertices = vertices,
      alpha = 1,
      xlu = false,
      noz = false,
      diffuse = {1, 1, 1},
      ambient = {0.5, 0.5, 0.5},
      specular = {0.01, 0.01, 0.01},
      shininess = 1,
      -- Use the terrain atlas texture
      texture = {
        path = TerrainAtlas.path(),
        w = TerrainAtlas.width(),
        h = TerrainAtlas.height()
      }
    }
    groups[#groups + 1] = terrainGroup
  end
  
  -- Water group
  if #waterVertices > 0 then
    local waterGroup = {
      vertices = waterVertices,
      alpha = 0.7,
      xlu = true, -- transparent
      noz = false,
      diffuse = {0.22, 0.55, 0.69},
      ambient = {0.12, 0.30, 0.40},
      specular = {0.08, 0.10, 0.12},
      shininess = 16,
      texture = {
        path = TerrainAtlas.path(),
        w = TerrainAtlas.width(),
        h = TerrainAtlas.height()
      },
      flow = 1 -- animated water
    }
    groups[#groups + 1] = waterGroup
  end
  
  -- Calculate bounds
  local minX, minY, minZ = math.huge, math.huge, math.huge
  local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
  
  for _, v in ipairs(vertices) do
    minX = math.min(minX, v[1])
    minY = math.min(minY, v[2])
    minZ = math.min(minZ, v[3])
    maxX = math.max(maxX, v[1])
    maxY = math.max(maxY, v[2])
    maxZ = math.max(maxZ, v[3])
  end
  
  -- Battle pads (standard positions)
  local battlePads = {
    {kind='pokemon', slot='player-left', cx=-19.2, cz=70, r=68},
    {kind='pokemon', slot='player-right', cx=-19.2, cz=70, r=68},
    {kind='pokemon', slot='enemy-left', cx=19.2, cz=-70, r=68},
    {kind='pokemon', slot='enemy-right', cx=19.2, cz=-70, r=68},
    {kind='trainer', slot='player-trainer', cx=56, cz=116, r=24},
    {kind='trainer', slot='enemy-trainer', cx=-56, cz=-116, r=24},
  }
  
  local singlePads = {
    {kind='pokemon', slot='player-single', cx=-19.2, cz=70, r=68},
    {kind='pokemon', slot='enemy-single', cx=19.2, cz=-70, r=68},
  }
  
  return {
    version = 7,
    source = "Dynamic Arena / " .. (map.id or "unknown"),
    prototype = false,
    bounds = {
      min = {minX, minY, minZ},
      max = {maxX, maxY, maxZ}
    },
    battlePads = battlePads,
    singlePads = singlePads,
    groupCount = #groups,
    vertexCount = #vertices + #waterVertices,
    groups = groups
  }
end

-- Main function: generate or retrieve a dynamic arena for the given location
function DynamicArena.generate(map, arena)
  if not map or not arena then return nil end
  
  local key = arenaKey(map, arena)
  
  -- Check cache
  if arenaCache[key] then
    return arenaCache[key]
  end
  
  -- Extract terrain
  local vertices, waterVertices, indices = extractTerrain(map, arena)
  
  if #vertices == 0 then
    V.mod.log:warn("[DynamicArena] No terrain extracted for arena %s", key)
    return nil
  end
  
  -- Build arena data
  local arenaData = buildArenaData(map, arena, vertices, waterVertices, indices)
  
  -- Cache it
  arenaCache[key] = arenaData
  
  V.mod.log:info("[DynamicArena] Generated arena %s with %d vertices", key, #vertices + #waterVertices)
  
  return arenaData
end

-- Clear the cache (call when changing maps or reloading)
function DynamicArena.clearCache()
  arenaCache = {}
end

-- Get cache statistics
function DynamicArena.cacheStats()
  local count = 0
  local totalVertices = 0
  for key, data in pairs(arenaCache) do
    count = count + 1
    totalVertices = totalVertices + (data.vertexCount or 0)
  end
  return { count = count, totalVertices = totalVertices }
end

return DynamicArena
