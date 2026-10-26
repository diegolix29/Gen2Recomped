io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')..'/'
package.path=root..'?.lua;'..package.path
function love.load()
 local ok,err=xpcall(function()
  local V,libs={sharedHulls=true},{}
  V.require=function(n)
   if not libs[n]then libs[n]=assert(loadfile(root..'mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))(V)end
   return libs[n]
  end
  local performance=require('src.core.Performance');performance.tier='high'
  local pixels=V.require('PixelCanvas');local original=pixels.new;local allocations=0
  pixels.new=function(...)allocations=allocations+1;return original(...)end
  local shadow=V.require('ShadowMap')
  assert(shadow.available(),'native shadow support missing')
  assert(shadow.begin(400,325,800,650));shadow.finish('still')
  local texture=shadow.texture();local resolution=shadow.res
  assert(resolution>shadow.SIZES[1],'fixture needs a larger fitted canvas')
  local allocated=allocations
  for _=1,200 do
   assert(shadow.available() and not shadow.stale('still'),'capability probe invalidated finished shadows')
   assert(shadow.texture()==texture and shadow.res==resolution,'probe replaced fitted canvas')
  end
  assert(allocations==allocated,'availability allocated extra shadow canvases')
  performance.tier='balanced';assert(shadow.available() and shadow.stale('still'),'lowered quality did not invalidate')
  assert(shadow.begin(400,325,800,650));shadow.finish('still')
  assert(shadow.res==1024 and allocations==allocated+1,'quality reduction did not resize once')
  performance.tier='high';assert(shadow.available() and shadow.stale('still'),'raised quality did not invalidate')
  assert(shadow.begin(400,325,800,650));shadow.finish('still')
  assert(shadow.res==resolution and allocations==allocated+2,'quality increase did not restore fitted size')
  assert(shadow.stale('moving'),'changed scene stamp was ignored')
  local before=allocations
  assert(shadow.begin(401,325,800,650));shadow.finish('moving')
  assert(allocations==before and not shadow.stale('moving'),'moving camera unnecessarily reallocated canvas')
  assert(shadow.begin(400,325,160,144));shadow.finish('small')
  assert(shadow.res==1024,'view shrink did not fit smaller size')
  assert(shadow.available() and not shadow.stale('small'))
  shadow.invalidate();local failures=0
  pixels.new=function()failures=failures+1;return false,'fixture rejection'end
  assert(not shadow.available() and not shadow.available() and failures==1,'failed native canvas was retried every frame')
  pixels.new=original;shadow.invalidate();assert(shadow.available(),'explicit invalidation did not permit retry')
  print('PASS native shadow canvas: 200 stable probes, resolution/tier changes, moving scene, invalidation and sticky failure')
 end,debug.traceback)
 if not ok then print('FAIL',err)end;love.event.quit(ok and 0 or 1)
end
function love.errorhandler(err)print('FAIL '..tostring(err));return function()return 1 end end
