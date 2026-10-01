local job,channel=...
package.path=job.packagePath or package.path
require('love.filesystem')
require('love.data')
require('love.image')
require('love.timer')
require('love.system')
local extractor
local ok,err=xpcall(function()
 if job.action=='verify' then
  local bytes=job.bytes
  if not bytes then
   local file,why=io.open(job.path,'rb')
   if file then bytes=file:read('*a');file:close()
   else bytes=love.filesystem.read(job.path);assert(bytes,why) end
  end
  local digest=love.data.hash('sha1',bytes)
  if type(digest)=='userdata' then digest=digest:getString() end
  local hash=love.data.encode('string','hex',digest)
  local GV=require('src.core.GameVersion')
  local version=GV.forSha1(hash)
  local info=version and GV.info(version)
  channel:push({kind='verified',hash=hash,version=version,size=#bytes,
   bytes=(info and info.generation==4 and job.path) and '' or bytes})
  return
 end
 local CacheFs=require('src.import.CacheFs')
 -- Use the root already resolved by the launcher, including portable and
 -- custom installations, without changing the UI state's active prefix.
 CacheFs.root=function() return job.root end
 CacheFs.prefix=job.prefix or ''
 local function removeSaveTree(path)
  local info=love.filesystem.getInfo(path)
  if not info then return end
  if info.type=='directory' then
   for _,name in ipairs(love.filesystem.getDirectoryItems(path)) do removeSaveTree(path..'/'..name) end
  end
  love.filesystem.remove(path)
 end
 if job.clear then
  for _,rel in ipairs({'data/generated','assets/generated'}) do
   removeSaveTree(CacheFs.prefix..rel);CacheFs.removeTree(rel)
  end
  love.filesystem.remove(CacheFs.prefix..'rom-cache.complete')
  CacheFs.remove('rom-cache.complete')
 end
 local lastStage,lastAt=nil,0
 local function progress(value,total,stage,current,stageTotal)
  local now=love.timer.getTime()
  if stage~=lastStage or now-lastAt>=0.05 or current==stageTotal then
   channel:push({kind='progress',progress=value/total,stage=stage,current=current,total=stageTotal})
   lastStage,lastAt=stage,now
  end
 end
 local E=require(job.module)
 local why
 if job.generation==4 then extractor,why=E.new(job.path,job.version,job.manifest,progress)
 elseif job.generation==1 then extractor=E.new(job.bytes,job.manifest,progress)
 else extractor=E.new(job.bytes,job.version,job.manifest,progress) end
 assert(extractor,why)
 extractor:run()
 if extractor.close then extractor:close();extractor=nil end
 channel:push({kind='complete'})
end,debug.traceback)
if not ok then
 if extractor and extractor.close then pcall(extractor.close,extractor) end
 channel:push({kind='error',error=tostring(err)})
end
