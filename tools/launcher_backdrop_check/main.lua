io.stdout:setvbuf("no")
local root=assert(os.getenv("ROOT")):gsub("\\","/").."/"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
local B,frames,draws= nil,0,0
function love.load()
 local SD=require("src.core.SaveData");assert(not SD.isPortable(),"use an isolated profile")
 SD.setDataDir(assert(os.getenv("ROM_CACHE_ROOT")))
 require("src.import.CacheFs").root() -- mount the configured cache before probing a version
 B=require("src.import.LauncherBackdrop")
 B.request(os.getenv("GAME") or "emerald",false);B._state.wantSince=-100
 B.update(1/60,false)
 assert(B._state.game,B.failedFor(os.getenv("GAME") or "emerald"))
 local game=B._state.game;local original=game._draw
 game._draw=function(...)draws=draws+1;return original(...)end
end
function love.update(dt)B.update(dt,false)end
function love.draw()
 frames=frames+1
 love.graphics.clear(.03,.05,.1,1)
 assert(B.draw(1280,720,{x=220,y=0,w=1060,h=720}),"preview draw failed")
 love.graphics.setColor(.08,.12,.2,.95);love.graphics.rectangle("fill",0,0,220,720)
 love.graphics.setColor(1,1,1,1);love.graphics.print("Launcher UI",20,30)
 love.graphics.print("Cached ROM preview",20,60)
 if frames==90 then
  assert(draws<frames*.8,"preview drew on every UI frame")
  local canvas=B._state.canvas
  assert(canvas:getWidth()<=960 and canvas:getHeight()<=540,"preview resolution unbounded")
  print("PASS native preview caching",frames,"UI frames",draws,"game renders",canvas:getWidth(),canvas:getHeight())
  love.graphics.captureScreenshot(function(img)
   local file=assert(io.open(root.."tmp/emerald_perf/launcher-background-cache.png","wb"));file:write(img:encode("png"):getString());file:close()
   B.stop();love.event.quit()
  end)
 end
end
function love.errorhandler(err)print(debug.traceback(tostring(err),2));return function()return 1 end end
