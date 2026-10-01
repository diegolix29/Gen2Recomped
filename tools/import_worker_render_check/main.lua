local task,started,frames,maxStep= nil,0,0,0
local phase=1
function love.load()
 package.path=love.filesystem.getWorkingDirectory()..'/?.lua;'..package.path
 local nativeThread=love.thread.newThread
 love.thread.newThread=function(path)
  local file=assert(io.open(love.filesystem.getWorkingDirectory()..'/'..path,'rb'))
  local bytes=file:read('*a');file:close()
  return nativeThread(love.filesystem.newFileData(bytes,path))
 end
 assert(loadfile('src/import/RomImporter.lua'))
 local T=require('src.import.RomImportTask')
 task=assert(T.new({action='extract',generation=1,module='tools.import_worker_fixture',manifest={}}))
 started=love.timer.getTime()
end
function love.update()
 local t=love.timer.getTime();frames=frames+1
 local message=task:poll()
 while message do
  assert(message.kind~='error',message.error)
  if message.kind=='verified' then
   assert(phase==2 and message.version=='platinum' and message.size==134217728)
   assert(message.bytes=='','path imports must not send a second ROM copy back to the UI')
   assert(frames>=5,'ROM hashing must leave the UI running')
   print('Background Platinum hashing passed: '..frames..' responsive UI frames')
   love.event.quit(0);return
  end
  if message.kind=='complete' then
   assert(frames>=5,'extraction must leave the UI running')
   assert(maxStep<0.05,'worker polling stalled the UI')
   print('Background extraction passed: '..frames..' responsive UI frames')
   phase=2;frames=0;started=love.timer.getTime()
   task=assert(require('src.import.RomImportTask').new({action='verify',path=love.filesystem.getWorkingDirectory()..'/Pokemon - Platinum Version (USA) (Rev 1).nds'}))
   return
  end
  message=task:poll()
 end
 maxStep=math.max(maxStep,love.timer.getTime()-t)
 assert(love.timer.getTime()-started<10,'worker timeout')
end
function love.draw() love.graphics.print('Launcher remains responsive during extraction',10,10) end

