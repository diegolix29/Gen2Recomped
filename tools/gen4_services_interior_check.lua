-- Inspect an imported Platinum dataset without modifying it.
-- python tools/run_lua_check.py tools/gen4_services_interior_check.lua <dataset root>
package.path = './?.lua;' .. package.path
local root = assert(arg[1], 'provide the imported Platinum dataset root')
local A = require('src.import.Gen4Archives')
local headers = assert(loadfile(root .. '/data/generated/gen4_map_headers.lua'))()
local terrain = assert(loadfile(root .. '/data/generated/gen4_terrain.lua'))()
local maps = assert(loadfile(root .. '/data/generated/maps.lua'))()
local machine = A.find('/fielddata/build_model/build_model.narc','pokecenter_healing_machine.nsbmd')
local checks, rooms = 0, 0
local function check(value, message) checks=checks+1; assert(value,message) end
local function exists(path)
  local f = io.open(root .. '/' .. path,'rb'); if f then f:close(); return true end
end
local byHeader = {}
for _, map in pairs(maps) do if map.header then byHeader[map.header]=map end end
for id, h in pairs(headers) do
  local script = A.name('/fielddata/script/scr_seq.narc',h.scripts) or ''
  if not script:find('unused') and (script:match('_mart$') or script:match('_pokecenter_1f$')) then
    rooms=rooms+1
    local map = byHeader[id]
    check(map ~= nil, script .. ': no map')
    local record = terrain.maps[h.internalName]
    check(record ~= nil, script .. ': no terrain attribution')
    local set = terrain.sets[record.texture]
    check(set and next(set.textures), script .. ': no ROM texture set')
    for name, texture in pairs(set.textures) do
      check(texture.path and exists(texture.path),script .. ': missing texture ' .. name)
    end
    local grid = terrain.matrices[map.layout]
    check(grid and grid.land,script .. ': no terrain matrix')
    local objects, console = 0,false
    for _, land in ipairs(grid.land) do
      local chunk = terrain.chunks[land]
      check(chunk and chunk.shapes and #chunk.shapes>0,script .. ': no terrain geometry')
      for _, object in ipairs(chunk.objects or {}) do
        objects=objects+1
        if object.model==machine then console=true end
      end
    end
    check(objects>0,script .. ': no building props')
    if script:match('_pokecenter_1f$') then check(console,script .. ': no healing console') end
  end
end
check(rooms>20,'expected town service interiors')
print(checks .. ' interior checks passed across ' .. rooms .. ' rooms')
