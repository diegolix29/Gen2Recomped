io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')..'/'
package.path=root..'?.lua;'..package.path
function love.load()
 local ok,err=xpcall(function()
 local ffi=require('ffi');pcall(ffi.cdef,'int PHYSFS_mount(const char*,const char*,int);')
 local fs=ffi.load('love');assert(fs.PHYSFS_mount(root,'',1)~=0);assert(fs.PHYSFS_mount(os.getenv('EMERALD_CACHE'),'',1)~=0)
 require('src.core.GameVersion').set('emerald')
 local data=require('src.core.Data');data:load();require('src.core.Game').data=data
 local V,libs,dc={},{},{}
 V.require=function(n)if not libs[n]then libs[n]=assert(loadfile(root..'mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))(V)end;return libs[n]end
 V.data=function(n)if not dc[n]then dc[n]=assert(loadfile(root..'mods/DRAMATIC_SHAPE/data/'..n..'.lua'))()end;return dc[n]end
 local G=V.require('Gen3');local Updates=V.require('AtlasUpdates');local TR=require('src.render.TileRenderer')
 local function pixels(image,w,h)
  local c=love.graphics.newCanvas(w,h);love.graphics.push('all');love.graphics.setCanvas(c)
  love.graphics.clear(0,0,0,0);love.graphics.setBlendMode('replace');love.graphics.setColor(1,1,1,1);love.graphics.draw(image)
  love.graphics.pop();local p=c:newImageData();local bytes=p:getString();p:release();c:release();return bytes
 end
 for _,id in ipairs({'MAP_G00_N10','MAP_G00_N34','MAP_G00_N03','MAP_G00_N30'})do
  local m=require('src.world.MapLoader').load(data,id)
  local source=G.atlasDataForTileset(m.tileset);local w,h=source:getDimensions();local sourceBytes=source:getString()
  local patches=assert(G.animPatchesForTileset(m.tileset));local perRow=G.atlasInfoFor(m.tileset).perRow
  local reference=love.image.newImageData(w,h);reference:paste(source,0,0,0,0,w,h)
  local full,partial=love.graphics.newImage(source),love.graphics.newImage(source)
  full:setFilter('nearest','nearest');partial:setFilter('nearest','nearest')
  local plan=Updates.new(source,patches,perRow)
  local function old(step)
   local strip=patches.strips[step+1]
   for i,t in ipairs(patches.slots)do
    local x,y=(t%perRow)*8,math.floor(t/perRow)*8
    if x+8<=w and y+8<=h then reference:paste(strip,x,y,(i-1)*8,0,8,8) end
   end
   full:replacePixels(reference)
  end
  for step=0,patches.steps-1 do
   old(step);plan:apply(partial,patches.strips[step+1])
   assert(pixels(full,w,h)==pixels(partial,w,h),'native pixels differ: '..id..' step '..step)
  end
  local times={}
  for _,mode in ipairs({'full','bands'})do
   local start=love.timer.getTime()
   for i=1,320 do local step=i%patches.steps
    if mode=='full'then old(step)else plan:apply(partial,patches.strips[step+1])end
   end
   times[mode]=love.timer.getTime()-start
  end
  print('PASS_ATLAS',id,'steps',patches.steps,'fullBytes',w*h*4,'bandBytes',plan.bytes,'calls',#plan.bands,'fullSeconds',times.full,'bandSeconds',times.bands)
  -- Exercise the actual TerrainAtlas integration and its one-time rejection
  -- fallback, including partial success before the driver rejects a band.
  local atlas=V.require('TerrainAtlas');local originalNew=Updates.new;local calls=0
  atlas.invalidate()
  for _=1,patches.steps do
   local current=atlas.forMap(m)
   local step=math.floor(TR.animFrame()/patches.period)%patches.steps;old(step)
   assert(pixels(current,w,h)==pixels(full,w,h),'TerrainAtlas integration changed animation pixels')
   -- tick caps catch-up at 0.25 seconds: advance exact individual ticks.
   for _=1,patches.period do TR.tick(1/60) end
  end
  Updates.new=function(...)
   local p=originalNew(...);local apply=p.apply
   p.apply=function(self,image,strip)
    return apply(self,{replacePixels=function(_, ...)
     calls=calls+1;if calls==2 then error('fixture: rejected partial upload')end
     return image:replacePixels(...)
    end},strip)
   end
   return p
  end
  atlas.invalidate();local fallback=atlas.forMap(m)
  Updates.new=originalNew
  assert(calls==2,'rejection fixture did not exercise a partially uploaded atlas')
  local step=math.floor(TR.animFrame()/patches.period)%patches.steps;old(step)
  assert(pixels(fallback,w,h)==pixels(full,w,h),'rejection left a mixed frame')
  for _=1,patches.period do TR.tick(1/60) end;fallback=atlas.forMap(m)
  step=math.floor(TR.animFrame()/patches.period)%patches.steps;old(step)
  assert(calls==2 and pixels(fallback,w,h)==pixels(full,w,h),'fallback retried rejected uploads or lost next frame')
  atlas.invalidate();plan:release();assert(#plan.bands==0,'band buffers retained after release')
  assert(source:getString()==sourceBytes,'private animation modified the shared static source')
  reference:release();full:release();partial:release()
 end
 print('PASS all native animation frames, unchanged pixels, rejected partial upload fallback and cleanup')
 end,debug.traceback)
 if not ok then print('FAIL',err)end;love.event.quit(ok and 0 or 1)
end
function love.errorhandler(err)print('FAIL '..tostring(err));return function()return 1 end end
