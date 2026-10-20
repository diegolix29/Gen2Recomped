-- No decoder or player files needed: exercise actual backdrop cache policy.
local now,videoDraws,canvasDraws,volumeCalls,videoReleased,canvasReleased=0,0,0,0,0,0
local osName="Windows"
local currentCanvas,created
local video={playing=true}
function video:getDimensions()return 1920,1080 end
function video:getSource()return {setVolume=function()volumeCalls=volumeCalls+1 end} end
function video:isPlaying()return self.playing end
function video:pause()self.playing=false end
function video:play()self.playing=true end
function video:rewind()error('paused video should not rewind')end
function video:release()videoReleased=videoReleased+1 end
love={timer={getTime=function()return now end},system={getOS=function()return osName end},graphics={}}
local g=love.graphics
for _,name in ipairs({'push','pop','origin','setScissor','setShader','setColor','setBlendMode','clear'})do g[name]=function()end end
function g.getCanvas()return currentCanvas end
function g.setCanvas(c)currentCanvas=c end
function g.newCanvas(w,h,opts)
 assert(opts.dpiscale==1,'retina-scaled cache')
 local c={w=w,h=h}
 function c:getWidth()return self.w end
 function c:getHeight()return self.h end
 function c:getDimensions()return self.w,self.h end
 function c:setFilter()end
 function c:release()canvasReleased=canvasReleased+1 end
 created=c;return c
end
function g.draw(drawable)
 if drawable==video then videoDraws=videoDraws+1 else canvasDraws=canvasDraws+1 end
end
local B=require('src.import.LauncherBackdrop');local state=B._state
state.current='video';state.want='video';state.video=video
for i=1,120 do now=i/60;B.update(1/60,false);assert(B.draw(1920,1080)) end
assert(videoDraws>=45 and videoDraws<=61,'background conversion not rate-limited')
assert(canvasDraws==120 and created.w==960 and created.h==540,'UI composition not full cadence/bounded size')
assert(volumeCalls==1,'volume set every frame')
local before=videoDraws
B.setPaused(true)
for i=1,60 do now=now+1/60;B.update(1/60,false);B.draw(1920,1080)end
assert(videoDraws==before,'paused cache redrawn')
B.setPaused(false);osName='NX';state.videoNext=0;videoDraws=0
for i=1,120 do now=now+1/60;B.update(1/60,false);B.draw(1920,1080)end
assert(videoDraws<=31 and videoDraws>=24,'NX background cadence not bounded')
state.music=false;B.update(1/60,false);B.update(1/60,false)
assert(volumeCalls==2,'music toggle did not update once')
B.stop();assert(videoReleased==1 and canvasReleased==1,'video/canvas resources not released')
assert(not state.videoCanvas and not state.video,'stopped backdrop retained resources')
-- Game-title backgrounds also render independently of the launcher UI.
osName='Windows';now=10
local Renderer={splitViewport={w=1,h=1}};local originalViewport=Renderer.splitViewport
package.loaded['src.render.Renderer']=Renderer
function g.getDimensions()return 1920,1080 end
function g.getWidth()return 1920 end
function g.getHeight()return 1080 end
function g.getDPIScale()return 2 end
local updates,renders,simulated=0,0,0
state.game={data={},update=function(_,dt)updates=updates+1;simulated=simulated+dt end,
 _draw=function()renders=renders+1;local w,h=g.getDimensions();assert(w==960 and h==540 and g.getDPIScale()==1,'unbounded preview render')end}
state.want='emerald';state.current='emerald';state.music=true
for i=1,120 do now=now+1/60;B.update(1/60,false);assert(B.draw(1920,1080))end
assert(updates==60 and math.abs(simulated-2)<.001,'preview simulation time changed')
assert(renders>=45 and renders<=61,'game preview drew at UI cadence')
assert(Renderer.splitViewport==originalViewport and g.getDPIScale()==2,'preview graphics hooks leaked')
B.stop()
print('Launcher background cache: 13 checks passed; UI composition every frame, video and game previews throttled')
