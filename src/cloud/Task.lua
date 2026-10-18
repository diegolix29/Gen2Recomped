-- Run auth control flow on the main Lua state, yielding only HTTP I/O to a
-- worker. Tokens/browser callbacks stay here; a cancelled request's late
-- response can never resume auth code or write credentials.
local Http=require('src.cloud.Http')
local T={};T.__index=T
local retired={}
local function now() return love.timer.getTime() end
function T.reap()
 for i=#retired,1,-1 do
  if not retired[i].thread:isRunning() then table.remove(retired,i) end
 end
end
function T.new(fn)
 if not (love.thread and love.thread.newThread and love.thread.newChannel) then
  return nil,'Background networking is unavailable in this build.'
 end
 T.reap()
 local self=setmetatable({co=coroutine.create(fn)},T)
 Http.async[self.co]=true
 return self
end
function T:cancel()
 if self.co then Http.async[self.co]=nil;self.co=nil end
 -- LOVE's thread destructor may wait. Retain in-flight workers until they
 -- exit, rather than letting GC turn CANCEL into a blocking thread join.
 if self.worker then retired[#retired+1]=self.worker;self.worker=nil end
 self.terminal={kind='error',error='Sign-in cancelled.'}
end
function T:fail(why)
 self:cancel();self.terminal={kind='error',error=tostring(why)}
 return self.terminal
end
function T:poll()
 T.reap()
 if self.terminal then return self.terminal end
 local response
 if self.worker then
  response=self.worker.channel:pop()
  if not response then
   local why=self.worker.thread:getError()
   if why then return self:fail('Cloud network worker failed: '..tostring(why)) end
   if now()>self.worker.deadline then return self:fail('The cloud request timed out. Please try again.') end
   if not self.worker.thread:isRunning() then
    response=self.worker.channel:pop()
    if not response then return self:fail('Cloud network worker stopped without a response.') end
   else return end
  end
  retired[#retired+1]=self.worker;self.worker=nil
 end
 local ok,a,b
 if response then ok,a,b=coroutine.resume(self.co,response.status,response.body)
 else ok,a,b=coroutine.resume(self.co) end
 if not ok then return self:fail(a) end
 if coroutine.status(self.co)=='dead' then
  Http.async[self.co]=nil;self.co=nil
  self.terminal={kind='done',first=a,second=b};return self.terminal
 end
 if type(a)~='table' or a.kind~='http' then return self:fail('Invalid cloud network request.') end
 local started,why=pcall(function()
  local channel=love.thread.newChannel()
  local thread=love.thread.newThread('src/cloud/http_worker.lua')
  thread:start({method=a.method,url=a.url,opts=a.opts,packagePath=package.path},channel)
  self.worker={thread=thread,channel=channel,deadline=now()+30}
 end)
 if not started then return self:fail('Could not start cloud networking: '..tostring(why)) end
end
return T
