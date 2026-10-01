-- Extraction and hashing run in an isolated Lua state; the launcher only
-- drains progress messages. Keep the coroutine path for hosts without threads.
local Task={}
Task.__index=Task
function Task.available()
 return love and love.thread and love.thread.newThread and love.thread.newChannel
end
function Task.new(job)
 if not Task.available() then return nil end
 local ok,result=pcall(function()
  local channel=love.thread.newChannel()
  local thread=love.thread.newThread('src/import/rom_import_worker.lua')
  job.packagePath=package.path
  thread:start(job,channel)
  return setmetatable({thread=thread,channel=channel},Task)
 end)
 return ok and result or nil
end
function Task:poll()
 local result=self.channel:pop()
 if result then return result end
 local err=self.thread:getError()
 if err and not self.failed then self.failed=true;return {kind='error',error=err} end
end
return Task
