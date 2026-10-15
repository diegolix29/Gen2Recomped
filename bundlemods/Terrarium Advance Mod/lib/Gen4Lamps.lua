-- Gen4Lamps: point lights from Platinum's own lamp textures.
--
-- Gen 4 buildings already have lamp models in their geometry (textures like
-- c1_lamp01, c1_lamp02 in Jubilife). This module detects where those lamp
-- textures are used and emits point lights from those positions at night.
--
-- Unlike StreetLamps (which places posts on Gen 1-3 towns), this reads the
-- existing Gen 4 geometry and lights up what's already there.

local V = ...
local Voxel3D = V.require("Voxel3D")

local Lamps = {
  enabled = true,
  LOG = true,  -- Log lamp detection

  -- Lamp texture names from Gen4Lawn (lower case)
  LAMP_TEXTURES = {
    "c1_lamp01", "c1_lamp02",
    -- Add more as needed for other cities
  },

  LIGHT_RADIUS = 56,    -- same as StreetLamps
  LIGHT_LIMIT = 8,      -- shader limit
}

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local DayNight = optional("DayNight")

-- Cache of lamp positions per ground: ground -> { {x, y, z}, ... }
local cache = setmetatable({}, { __mode = "k" })
local tick = 0

-- Find lamp positions in a ground's terrain
local function findLamps(ground)
  local hit = cache[ground]
  if hit then return hit end

  local positions = {}
  local terrain = ground and ground.terrain
  if not terrain or not terrain.chunks then
    cache[ground] = positions
    return positions
  end

  -- Walk through all chunks to find lamp textures in building models
  -- Buildings are stored as objects with model references
  for land, record in pairs(terrain.chunks) do
    if record.objects then
      for _, object in ipairs(record.objects) do
        if object.archive ~= "fldeff" and not object.live then
          local modelIndex = tonumber(object.model)
          if modelIndex then
            local packed = ground.buildingSet and ground.buildingSet.models
            if packed then
              local model = packed[modelIndex + 1]
              if model and model.shapes then
                for _, shape in ipairs(model.shapes) do
                  local tex = tostring(shape.texture or ""):lower()
                  if Lamps.LAMP_TEXTURES[tex] then
                    -- Use object position + shape offset for lamp location
                    local ox = object.x or 0
                    local oy = object.y or 0
                    local oz = object.z or 0
                    positions[#positions + 1] = {
                      x = ox,
                      y = oy + 24,  -- lamp height above ground
                      z = oz,
                    }
                    break  -- One lamp per building model is enough
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  cache[ground] = positions
  return positions
end

-- Return nearest lamp positions as point lights (same format as StreetLamps.lights)
function Lamps.lights(wx, wz, limit)
  if not Lamps.enabled then return {} end

  local okN, night = pcall(DayNight.windowLight)
  night = okN and tonumber(night) or 0
  if night <= 0.05 then return {} end

  -- Get current ground from scene context
  -- This is called from VoxelScene, which doesn't have direct ground access
  -- For now, return empty - need to hook into Gen4Bridge to get ground
  return {}
end

-- Called from Gen4Bridge with the scene to get lamp positions
function Lamps.collectLights(scene)
  if not Lamps.enabled then return {} end

  local ground = scene and scene.ground
  if not ground then return {} end

  local okN, night = pcall(DayNight.windowLight)
  night = okN and tonumber(night) or 0
  if night <= 0.05 then return {} end

  local positions = findLamps(ground)
  local view = scene and scene.view
  if not view then return {} end

  local vx, vz = view.x or 0, view.z or 0
  local out = {}

  for _, pos in ipairs(positions) do
    local dx, dz = pos.x - vx, pos.z - vz
    local d2 = dx * dx + dz * dz
    out[#out + 1] = {
      x = pos.x,
      y = pos.y,
      z = pos.z,
      radius = Lamps.LIGHT_RADIUS,
      power = night * 0.9,
      d2 = d2,
    }
  end

  -- Sort by distance and limit
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  local limit = math.min(Lamps.LIGHT_LIMIT, #out)
  for i = #out, limit + 1, -1 do out[i] = nil end

  -- Log once when lamps are found
  if #out > 0 and Lamps.LOG then
    local logged = Lamps._logged or {}
    local key = tostring(ground)
    if not logged[key] then
      logged[key] = true
      Lamps._logged = logged
      if V.mod and V.mod.log then
        V.mod.log:info("Gen4Lamps: found %d lamp(s) at night=%.2f", #positions, night)
      end
    end
  end

  return out
end

function Lamps.invalidate()
  cache = setmetatable({}, { __mode = "k" })
end

return Lamps
