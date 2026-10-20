io.stdout:setvbuf("no")
local root=assert(os.getenv("ROOT")):gsub("\\","/").."/"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
local runner,Gfx,fonts,frames,elapsed= nil,nil,nil,0,0
function love.load()
 local A=require("src.pokewalker.WalkerArt");A._roots={assert(os.getenv("ROM_CACHE_ROOT"))};A.forget()
 local hg=A.roster("heartgold");local bw=A.roster("black")
 assert(#hg==493 and #bw==649,"DS national roster missing or includes personal-form IDs")
 local images={}
 for _,dex in ipairs({1,4,7,25})do
  local image,fw,fh,facings,version=A.walk(dex,false)
  assert(image and version=="heartgold","highest imported overworld art not used")
  assert(not images[image],"different species share the same walking picture");images[image]=true
 end
 print("PASS 493 HGSS / 649 BW species; distinct highest-generation walking images")
 local st=require("src.pokewalker.Walker").newState();st.course=0
 st.walking={species=25,name="Pikachu",level=5,source={version="heartgold"}}
 local ctx=require("src.pokewalker.minigames.Context").build(st,914)
 assert(#ctx.wild==493,"walking Pokemon replaced the wild roster")
 local R=require("src.pokewalker.minigames.Rewards");R._economy=false
 require("src.pokewalker.Walker").save=function()end
 runner=require("src.pokewalker.minigames.JumpRunner").new(ctx,R.newPurse(st,"runner"))
 Gfx=require("src.pokewalker.minigames.Gfx");Gfx.version="emerald";fonts=Gfx.fonts(1)
 local rng=ctx.rng;ctx.rng=function(n)if n==100 then return 30 end;return 1 end
 runner:spawnChunk(8)
 for _,e in ipairs(runner.ents)do if e.kind=="mon" then assert(type(e.yy)=="number","new spawn cannot render before first update")end end
 runner:draw(0,0,960,650,Gfx,fonts,1)
 ctx.rng=rng
 runner.crash=function()end -- endurance fixture: collisions must not end coverage
 print("PASS newly spawned enemies render in their creation frame")
end
function love.update()
 for i=1,30 do
  if math.floor(elapsed*4)%3==0 then runner:input("a") end
  runner:update(1/60);elapsed=elapsed+1/60
 end
end
function love.draw()
 runner:draw(0,0,960,650,Gfx,fonts,1);frames=frames+1
 if frames==1 then
  love.graphics.captureScreenshot(function(data)
   local f=assert(io.open(root.."tmp/emerald_perf/runner-highest-overworld.png","wb"))
   f:write(data:encode("png"):getString());f:close()
  end)
 end
 if elapsed>=900 then print("PASS 15-minute simulated runner update/draw endurance",frames,"rendered frames");love.event.quit()end
end
function love.errorhandler(err)print(debug.traceback(tostring(err),2));return function()return 1 end end
