-- LOVE rendering check using an existing imported Platinum dataset.
function love.load(args)
  local root = love.filesystem.getWorkingDirectory()
  package.path = root .. '/?.lua;' .. package.path
  local dataset = assert(args[1], 'provide dataset root')
  local output = assert(args[2], 'provide output directory')
  local ok, err = pcall(function()
    -- Read the imported dataset through native files, keeping the test source
    -- separate from the game source and LOVE's save-directory mount policy.
    local cache = {}
    package.loaded['src.render.Assets'] = {
      resolve=function(path) return path end, register=function() end,
      image=function(path)
        if not cache[path] then
          local f = assert(io.open(dataset .. '/' .. path,'rb'),path)
          local bytes=f:read('*a'); f:close()
          cache[path]=love.graphics.newImage(love.filesystem.newFileData(bytes,path))
        end
        return cache[path]
      end }
    love.filesystem.newFile = function(path)
      local file, why = io.open(dataset .. '/' .. path,'rb')
      if not file then return nil,why end
      return {seek=function(_,at) return file:seek('set',at) end,
        read=function(_,count) return file:read(count) end,
        close=function() return file:close() end}
    end
    local data = {}
    for _, name in ipairs({'gen4_terrain','gen4_models','gen4_camera','gen4_area_lights'}) do
      local chunk = loadfile(dataset .. '/data/generated/' .. name .. '.lua')
      if chunk then data[name]=chunk() end
    end
    local maps = assert(loadfile(dataset .. '/data/generated/maps.lua'))()
    local headers = assert(loadfile(dataset .. '/data/generated/gen4_map_headers.lua'))()
    local A = require('src.import.Gen4Archives')
    local Ground = require('src.render.Gen4Ground')
    local saved = {}
    for _, map in pairs(maps) do
      local h = headers[map.header]
      local script = h and A.name('/fielddata/script/scr_seq.narc',h.scripts) or ''
      local kind = script == 'scripts_sandgem_town_mart' and 'mart'
        or script == 'scripts_sandgem_town_pokecenter_1f' and 'center'
        or script == 'scripts_sandgem_town' and 'sandgem-zoom'
      if kind and not saved[kind] then
        local ground = assert(Ground.forMap({def=map},data),'no ground for '..kind)
        local vw,vh=kind=='sandgem-zoom' and 1536 or 256,kind=='sandgem-zoom' and 1024 or 192
        local canvas = love.graphics.newCanvas(vw,vh)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0.1,0.1,0.1,1)
        local warp = (map.warps or {})[1]
        local camX = math.max(0, (warp and warp.x or 8)*16-128)
        local camY = math.max(0, (warp and warp.y or 6)*16-144)
        if kind=='sandgem-zoom' then camX,camY=-512,-256 end
        for frame=1,16 do
          ground:draw(camX,camY,vw,vh)
          ground:drawCanopy(camX,camY,vw,vh)
        end
        love.graphics.setCanvas()
        local image = canvas:newImageData()
        local colored = 0
        for y=0,vh-1 do for x=0,vw-1 do
          local r,g,b=image:getPixel(x,y)
          if math.max(r,g,b)-math.min(r,g,b)>0.1 then colored=colored+1 end
        end end
        assert(colored>5000,kind .. ' rendered too little cartridge art')
        local png = image:encode('png')
        local f = assert(io.open(output .. '/' .. kind .. '.png','wb'))
        f:write(png:getString()); f:close()
        saved[kind]=true
      end
    end
    assert(saved.center and saved.mart,'could not find both service maps')
  end)
  local f = assert(io.open(output .. '/services-render-result.txt','w'))
  f:write(ok and 'Service interiors rendered' or tostring(err)); f:close()
  love.event.quit(ok and 0 or 1)
end
