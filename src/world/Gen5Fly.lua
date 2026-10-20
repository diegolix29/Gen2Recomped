-- BLACK / WHITE'S FLY.
--
--   * WHERE: the Town Map's fly points (/a/0/8/6 +24, src/import/
--     Gen5TownMapArt.lua) and each one's zone-header spawn -- two tiles below
--     the town's Pokemon Center door. Castelia, on a matrix of its own, keeps
--     a rail position there; its landing is taken from the Center's door.
--   * WHEN: the zone's field permissions (+0x1E, `gen5Flags` on the map def)
--     bit 0x2000 -- ARM9 0x2013C40, which ov010's field-move context
--     (0x215E908) turns into its Fly and Teleport bits. Routes and towns
--     carry 0xEC40; houses 0x4921 and Relic Castle 0x5D23 do not. Generation
--     V asks no badge for a field move.
--   * WHICH ARE OPEN: the places the player has stood in (Gen5TownMap.remember
--     marks each on arrival), the cartridge's arrival flags' stand-in.
--
-- The choice is made on the Town Map (src/ui/Gen5TownMap.lua, mode "fly").

local Gen5Fly = {}

Gen5Fly.FLAG_FLY = 0x2000

local function bit(flags, b) return math.floor(flags / b) % 2 == 1 end

function Gen5Fly.allowed(def)
  local f = def and tonumber(def.gen5Flags)
  if f then return bit(f, Gen5Fly.FLAG_FLY) end
  -- a cache imported before the flags were kept: outdoors on the main matrix
  return def ~= nil and tonumber(def.layout) == 0
end

local function record(data) return data and data.gen5_town_map end

function Gen5Fly.visit(save, zone)
  if type(save) ~= "table" or not zone then return end
  save.gen5FlyZones = save.gen5FlyZones or {}
  save.gen5FlyZones[tostring(zone)] = true
end

function Gen5Fly.visited(save, zone)
  if type(save) ~= "table" or zone == nil then return false end
  -- a save from before the marks were kept still has the last place stood in
  if tostring(save.gen5TownMapZone) == tostring(zone) then return true end
  local v = save.gen5FlyZones
  return type(v) == "table" and v[tostring(zone)] == true
end

local function mapId(zone) return ("Z%03d"):format(zone) end

-- the landing of a Town Map place, or nil
function Gen5Fly.destination(data, loc)
  if not (loc and loc.flyPoint and loc.spawn) then return nil end
  local id = mapId(loc.zone)
  local def = data and data.maps and data.maps[id]
  if not def then return nil end
  local w, h = tonumber(def.width) or 0, tonumber(def.height) or 0
  if loc.spawn.main then
    local x = (tonumber(loc.spawn.x) or 0) - (tonumber(def.originX) or 0)
    local y = (tonumber(loc.spawn.z) or 0) - (tonumber(def.originY) or 0)
    if x > 0 and y > 0 and x < w and y < h then return { map = id, x = x, y = y } end
  end
  -- off the main matrix: in front of the Pokemon Center
  local pc = {}
  for _, z in ipairs((record(data) or {}).pcZones or {}) do pc[z] = true end
  for _, warp in ipairs(def.warps or {}) do
    if not warp.extentOf and pc[tonumber(warp.destHeader)] then
      local x, y = tonumber(warp.x), (tonumber(warp.y) or 0) + 2
      if x and y < h then return { map = id, x = x, y = y } end
    end
  end
  return nil
end

-- may the player fly to this place now?
function Gen5Fly.open(data, save, loc)
  return Gen5Fly.visited(save, loc and loc.zone) and Gen5Fly.destination(data, loc) ~= nil
end

function Gen5Fly.destinations(data, save)
  local out = {}
  for _, loc in ipairs((record(data) or {}).locations or {}) do
    if Gen5Fly.open(data, save, loc) then out[#out + 1] = loc end
  end
  return out
end

return Gen5Fly
