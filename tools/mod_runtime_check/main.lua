io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.load()
 local ok,why=xpcall(function()
  local ffi=require('ffi')
  pcall(ffi.cdef,'int PHYSFS_mount(const char*,const char*,int);')
  local lib=ffi.load('love')
  assert(lib.PHYSFS_mount(root,'',1)~=0)
  assert(lib.PHYSFS_mount(assert(os.getenv('EMERALD_CACHE')),'',1)~=0)
  require('src.core.GameVersion').set('emerald')
  local data=require('src.core.Data');data:load();require('src.core.Game').data=data
  local fs=setmetatable({getDirectoryItems=function(path)
   if path=='mods' then return {'DRAMATIC_SHAPE'} end
   return love.filesystem.getDirectoryItems(path)
  end},{__index=love.filesystem})
  local loader=require('src.mods.Loader').new({fs=fs})
  loader:load(data)
  local V=assert(_G.__DRAMATIC_SHAPE_V,'actual bundled mod was not loaded')
  for _,mod in pairs(loader.mods)do assert(not mod.failed,mod.error or 'mod failed')end
  assert(V.mod.options:get('voxelGpuMeshing')~=nil,'GPU setting was not registered')
  local startupData
  for i=1,20 do local n,v=debug.getupvalue(V.data,i);if n=='dataFiles' then startupData=v end end
  assert(startupData and startupData.gen3_metatiles,'classification data was not prepared during mod startup')
  if love.graphics.newComputeShader then
   assert(V.require('GpuMesher').available(),V.require('GpuMesher').status())
   assert(V.require('GpuMesher').builds>=1,'GPU preflight was not dispatched')
  end
  print('PASS actual Dramatic Shapes entry, option schema, hooks and runtime preflight',love.getVersion())
 end,debug.traceback)
 if not ok then print('FAIL '..why)end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(why)print('FAIL '..tostring(why));return function()return 1 end end
