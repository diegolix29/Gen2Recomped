-- Worker Lua states do not inherit CacheFs's Switch filesystem shim.
local WorkerFs={}
function WorkerFs.prefix()
  return require('src.core.Platform').isNX() and require('src.core.GameVersion').cachePrefix() or nil
end
function WorkerFs.read(prefix,path)
  if prefix and prefix~='' then
    local bytes=love.filesystem.read(prefix..path)
    if bytes then return bytes end
  end
  return love.filesystem.read(path)
end
return WorkerFs
