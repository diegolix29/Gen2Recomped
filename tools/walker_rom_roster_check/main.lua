io.stdout:setvbuf("no")
local root=assert(os.getenv("ROOT")):gsub("\\","/").."/"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
local board,Gfx
function love.load()
 require("src.core.GameVersion").set("emerald")
 local Art=require("src.pokewalker.WalkerArt")
 Art._roots={assert(os.getenv("ROM_CACHE_ROOT"))};Art.forget()
 local roster=Art.roster("emerald")
 assert(#roster>=380,"Emerald full roster missing")
 local ctx=require("src.pokewalker.minigames.Context").build({walking={species=25,name="Pikachu",source={version="emerald"}},course=0},99)
 assert(ctx.version=="emerald" and #ctx.wild==#roster,"wrong context source")
 local seen={};for _,e in ipairs(roster)do seen[e.dex]=true end
 ctx.hasArt=function(dex)local img,v=Art.front(dex,false,ctx.version);return img~=nil and v==ctx.version end
 board=require("src.pokewalker.minigames.MemoryMatch").new(ctx,{})
 local count=0
 for _,c in ipairs(board.cards)do
  assert(seen[c.dex],"foreign memory card")
  local img,v=Art.front(c.dex,false,"emerald");assert(img and v=="emerald","ROM-specific picture missing")
  c.up=true;count=count+1
 end
 assert(Art.front(649,false,"emerald")==nil,"borrowed Genesect from another ROM")
 print("PASS Emerald source roster",#roster,"species;",count,"ROM-specific card images")
 Gfx=require("src.pokewalker.minigames.Gfx");Gfx.version="emerald"
 if os.getenv("HUB")=="1" then
  _G.hub=require("src.ui.WalkerMinigames").new(nil,{course=0,watts=0},{version="emerald"})
  assert(hub.artVersion=="emerald" and hub.rosterCount==#roster,"hub source is wrong")
 end
end
function love.draw()
 local s=Gfx.scale(800,650);local f=Gfx.fonts(s)
 if hub then hub:draw(0,0,800,650) else board:draw(0,0,800,650,Gfx,f,s) end
 local img=love.graphics.captureScreenshot(function(data)
  local file=assert(io.open(root.."tmp/emerald_perf/"..(hub and "minigames-hub-emerald.png" or "minigames-emerald.png"),"wb"));file:write(data:encode("png"):getString());file:close()
  print("PASS ROM-specific memory board screenshot");love.event.quit()
 end)
end
function love.errorhandler(err)print(debug.traceback(tostring(err),2));return function()return 1 end end
