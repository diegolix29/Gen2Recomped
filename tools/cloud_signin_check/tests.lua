local n=0
local function check(v,msg) assert(v,msg);n=n+1 end
local time=0
love={timer={getTime=function() return time end},system={}}
local workers={}
love.thread={newChannel=function()
 local c={};function c:pop() local v=self.value;self.value=nil;return v end;return c
end,newThread=function(path)
 check(path=='src/cloud/http_worker.lua','HTTP-only worker')
 local w={running=true};workers[#workers+1]=w
 function w:start(job,channel) self.job=job;self.channel=channel end
 function w:isRunning() return self.running end
 function w:getError() return self.error end
 return w
end}
local Http=require('src.cloud.Http');local Task=require('src.cloud.Task')
local wrote=false
local t=assert(Task.new(function()
 local ok,status,body=pcall(Http.request,'POST','https://example.invalid',{body='test'})
 check(ok,'HTTP can yield through protected auth calls')
 check(status==200 and body=='ok','response returns to auth coroutine')
 wrote=true;return 'finished','account'
end))
check(t:poll()==nil and not wrote,'network yields without blocking')
check(t:poll()==nil,'waiting stays responsive')
workers[1].channel.value={status=200,body='ok'};workers[1].running=false
local r=t:poll();check(r.kind=='done' and r.first=='finished' and r.second=='account' and wrote,'auth completes')
wrote=false
t=assert(Task.new(function() Http.request('GET','https://example.invalid');wrote=true end));t:poll();local w=workers[#workers];t:cancel()
w.channel.value={status=200,body='late'};check(t:poll().kind=='error' and not wrote,'cancel prevents late token writes');w.running=false;Task.reap()
t=assert(Task.new(function() Http.request('GET','https://example.invalid') end));t:poll();time=31
check(t:poll().error:find('timed out'),'deadline stays cancellable');workers[#workers].running=false;Task.reap()
t=assert(Task.new(function() error('auth failure') end));check(t:poll().error:find('auth failure'),'errors reported')
t=assert(Task.new(function() Http.request('GET','https://example.invalid') end));t:poll();workers[#workers].error='transport failed'
check(t:poll().error:find('transport failed'),'worker failure reported');workers[#workers].running=false;Task.reap()
local thread=love.thread;love.thread=nil;check(Task.new(function() end)==nil,'no blocking fallback');love.thread=thread
-- Popup: font line height deliberately exceeds its requested size, the
-- condition which made the old fit loop allocate ever-larger fonts forever.
package.loaded['src.core.Strings']=function(s) return s end
package.loaded['src.translation.Service']={}
package.loaded['src.core.SafeArea']={rect=function() return 0,0,love.graphics.w,love.graphics.h end}
local fonts=0;local copied,opened,cancelled=0,0,0
love.system.setClipboardText=function(code) check(code=='ABCD-EFGH','copy code');copied=copied+1 end
love.system.openURL=function(url) check(url=='https://example.invalid','open URL');opened=opened+1 end
love.graphics=setmetatable({w=360,h=800,newFont=function(px)
 fonts=fonts+1;assert(fonts<100,'unbounded font allocation')
 return {getWidth=function(_,s) return #s*px*.65 end,getHeight=function() return px*1.4 end,
 getWrap=function(_,s,w) local lines={};for i=1,math.max(1,math.ceil(#s*px*.65/w)) do lines[i]='' end;return w,lines end}
end,getDimensions=function() return love.graphics.w,love.graphics.h end},{__index=function() return function() end end})
local pass=0
local RI={_ui={col=function() end,fillGradRounded=function() end,inside=function(r,x,y) return x>=r.x and x<=r.x+r.width and y>=r.y and y<=r.y+r.height end},
 palette=function() return {} end,draw=function() end,mousepressed=function() pass=pass+1 end,keypressed=function() end,
 _hover=function() return false end}
require('src.import.LauncherCloudCode').install(RI)
local ui=setmetatable({_s=1},{__index=RI})
local function flow(kind) return {name='Google Drive',auth={cancel=function() cancelled=cancelled+1 end},flow={kind=kind,code=kind=='device' and 'ABCD-EFGH',url=kind=='device' and 'https://example.invalid'}} end
for _,size in ipairs({{320,568},{360,800},{800,360},{1280,800}}) do
 love.graphics.w,love.graphics.h=unpack(size);ui._cloudFlow=flow('device');ui:draw()
 for _,rect in pairs(ui._cc) do check(rect.x>=0 and rect.y>=0 and rect.x+rect.width<=size[1] and rect.y+rect.height<=size[2],'buttons inside viewport') end
 for _,name in ipairs({'copy','open'}) do local rect=ui._cc[name];ui:mousepressed(rect.x+1,rect.y+1,1) end
 local rect=ui._cc.cancel;ui:mousepressed(rect.x+1,rect.y+1,1);check(not ui._cloudFlow,'cancel closes code popup')
 ui._cloudFlow=flow('pending');ui:draw();ui:keypressed('return');ui:keypressed('c');ui:mousepressed(0,0,1)
 check(pass==0,'modal intercepts input while connecting');local rect=ui._cc.cancel;ui:mousepressed(rect.x+1,rect.y+1,1);check(not ui._cloudFlow,'cancel pending request')
end
check(copied==4 and opened==4 and cancelled==8,'popup controls')
print('Cloud sign-in checks: '..n..' passed')
