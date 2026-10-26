io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')
local ffi=require('ffi')
pcall(ffi.cdef,'int PHYSFS_mount(const char*,const char*,int);')
assert(ffi.load('love').PHYSFS_mount(root..'/dist/love12-preview/game.love','',0)~=0)
local source=assert(love.filesystem.read('main.lua'))
assert(source:find('Copyright (c)',1,true),'preview archive did not override the harness entry')
love.setDeprecationOutput(false)
assert(love.filesystem.load('main.lua'))()
assert(_G.POKEPORT_LOVE12_PREVIEW and _G.POKEPORT_NOTIFY_ONLY_UPDATES,'preview channel guard missing')
local draw=love.draw
local frames=0
love.draw=function()
 draw();frames=frames+1
 if frames==20 then
  love.graphics.captureScreenshot(function(pixels)
   local output=assert(io.open(root..'/tmp/love12-research/packed-launcher.png','wb'))
   output:write(pixels:encode('png'):getString());output:close()
   print('PASS packed LÖVE 12 application boot, preview channel guard and launcher render')
   love.event.quit()
  end)
 end
end
