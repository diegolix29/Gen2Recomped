local checks,task,jobs,at=0,nil,{},0
local function check(ok,label)
 assert(ok,label);checks=checks+1;print('PASS '..label)
end
local root
local function nextJob()
 at=at+1
 if not jobs[at] then print(('DS cartridge verification: %d passed'):format(checks));love.event.quit(0);return end
 task=assert(require('src.import.RomImportTask').new(jobs[at].job))
end
function love.load()
 local ok,why=xpcall(function()
  root=love.filesystem.getWorkingDirectory()
  package.path=root..'/?.lua;'..package.path
  local native=love.thread.newThread
  love.thread.newThread=function(path)
   local f=assert(io.open(root..'/'..path,'rb'));local bytes=f:read('*a');f:close()
   return native(love.filesystem.newFileData(bytes,path))
  end
  local V=require('src.import.RomVerification')
  local identities=require('src.import.NdsTrimIdentity')
  local names={
   heartgold='Pokemon - HeartGold Version (USA).nds',
   soulsilver='Pokemon - SoulSilver Version (USA, Australia).nds',
   black='Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds',
   white='Pokemon - White Version (USA, Europe) (NDSi Enhanced).nds',
  }
  local scanPaths={}
  for _,version in ipairs({'heartgold','soulsilver','black','white'}) do
   local rec=identities.games[version];local full=root..'/'..names[version]
   local f=assert(io.open(full,'rb'));local bytes=f:read('*a');f:close()
   check(V.identify(bytes).version==version,version..' original SHA-1 recognized')
   local minimum=bytes:sub(1,rec.contentSize)
   check(V.identify(minimum).trimmed,version..' minimum padding-only trim accepted')
   minimum=nil;collectgarbage('collect')
   local extent=version=='heartgold' or version=='soulsilver'
   extent=extent and math.floor(122.89*1048576) or 200*1048576
   local trimmed=bytes:sub(1,extent)
   bytes=nil;collectgarbage('collect')
   local id=V.identify(trimmed)
   check(id.version==version and id.hash==rec.sha1 and id.trimmed,version..' partially retained FF padding accepted')
   local path=root..'/tmp/nds_import_verification/'..version..'.nds'
   f=assert(io.open(path,'wb'));f:write(trimmed);f:close()
   scanPaths[#scanPaths+1]=full;scanPaths[#scanPaths+1]=path
   jobs[#jobs+1]={job={action='verify',path=path},version=version}
   if version=='heartgold' then
    local corrupt=trimmed:sub(1,8*1048576)..'X'..trimmed:sub(8*1048576+2)
    check(not V.identify(corrupt).version,'modified retained data rejected')
    corrupt=nil;collectgarbage('collect')
    check(not V.identify(trimmed..'\0').version,'non-FF added padding rejected')
    check(not V.identify(trimmed:sub(1,rec.contentSize-1)).version,'missing final game byte rejected')
   end
   trimmed=nil;collectgarbage('collect')
  end
  jobs[#jobs+1]={job={action='scan',paths=scanPaths},scan=true}
  for _,version in ipairs({'black','white'}) do
   jobs[#jobs+1]={job={action='extract',generation=5,version=version,
    module='tools.nds_import_path_fixture',root=root..'/tmp/nds_import_verification',
    path=root..'/tmp/nds_import_verification/'..version..'.nds'},extract=true}
  end
  nextJob()
 end,debug.traceback)
 if not ok then print(why);love.event.quit(1) end
end
function love.update()
 if not task then return end
 local ok,why=xpcall(function()
  local msg=task:poll()
  while msg do
   assert(msg.kind~='error',msg.error)
   if msg.kind=='verified' then
    local spec=jobs[at]
    check(msg.version==spec.version and msg.trimmed and msg.bytes=='',spec.version..' background trimmed verification without a ROM copy')
    nextJob();return
   elseif msg.kind=='scanned' then
    check(#msg.results==8,'background batch includes full and trimmed DS files')
    for _,entry in ipairs(msg.results) do check(entry.version~=nil,'background scan '..entry.name) end
    nextJob();return
   elseif msg.kind=='complete' then
    check(jobs[at].extract,'Gen5 worker opens the real cartridge extractor by path')
    nextJob();return
   end
   msg=task:poll()
  end
 end,debug.traceback)
 if not ok then print(why);task=nil;love.event.quit(1) end
end
