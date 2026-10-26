io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')..'/'
package.path=root..'?.lua;'..package.path
function love.load()
 require('src.core.GameVersion').set('emerald')
 local data=require('src.core.Data');data:load();require('src.core.Game').data=data
 local libs={};local V={}
 V.require=function(n) if not libs[n] then libs[n]=assert(loadfile((os.getenv('PERF_MOD_LIB') or root..'mods/DRAMATIC_SHAPE/lib')..'/'..n..'.lua'))(V) end;return libs[n] end
 local TR=require('src.render.TileRenderer');local ML=require('src.world.MapLoader')
 local originalBake=TR.gen3SheetsFor
 local TileClass=require('src.render.Gen3Tiles')
 local directLayer=TileClass.drawLayer
 if os.getenv('PERF_REFERENCE_GEN3_TILES') then
  TileClass.drawLayer=assert(loadfile(os.getenv('PERF_REFERENCE_GEN3_TILES')))().drawLayer
 end
 local originalFactory,factorySlot
 for i=1,64 do local n,v=debug.getupvalue(originalBake,i);if n=='pixelCanvas' then originalFactory,factorySlot=v,i;break end end
 local ts,def
 for _,d in pairs(data.maps) do
  local t=ML.tilesetFor(data,d)
  if t and t.id=='TILESET_03DF704_03DF74C' then ts,def=t,d;break end
 end
 assert(ts,'missing outdoor tileset fixture')
 local start=love.timer.getTime()
 local reference=assert(TR.gen3SheetsFor(ts,data,data.constants.gen3Layout))
 local function hash(image)
  local c=love.graphics.newCanvas(image:getDimensions());love.graphics.push('all');love.graphics.setCanvas(c);love.graphics.clear();love.graphics.setColor(1,1,1,1);love.graphics.draw(image);love.graphics.pop()
  local d=c:newImageData();local h=love.data.encode('string','hex',love.data.hash('sha256',d:getString()));d:release();c:release();return h
 end
 local hashes={hash(reference.bottom),hash(reference.top),reference.cover and hash(reference.cover)}
 TileClass.drawLayer=directLayer
 print('cold synchronous sheet seconds',love.timer.getTime()-start)
 TR.releaseGen3Sheets()
 local warm=V.require('EngineSheets')
 local state={map={id='root'},neighbors={{map={def={width=10,height=10,connections={north={list={{map='test'}}}}}},ox=0,oy=0}}}
 local fake={maps={test=def},tilesets=data.tilesets,map_tilesets=data.map_tilesets,constants=data.constants}
 local slices,maxSlice=0,0
 repeat
  local t=love.timer.getTime();warm.pump(state,fake,.001);maxSlice=math.max(maxSlice,love.timer.getTime()-t);slices=slices+1
  assert(slices<10000)
 until not warm.pending()
 assert(slices>1,'did not slice the bake')
 start=love.timer.getTime();local warmed=assert(TR.gen3SheetsFor(ts,data,data.constants.gen3Layout));local duration=love.timer.getTime()-start
 assert(hash(warmed.bottom)==hashes[1] and hash(warmed.top)==hashes[2],'prefetch changed ROM pixels')
 assert(not hashes[3] or hash(warmed.cover)==hashes[3],'prefetch changed reflection cover')
 assert(duration<.02,'warm entry rebuilt sheet')
 local quadCount=0;local newQuad=love.graphics.newQuad
 love.graphics.newQuad=function(...)quadCount=quadCount+1;return newQuad(...)end
 local shared=TR.gen3QuadsFor(warmed)
 for i=1,20 do assert(TR.gen3QuadsFor(warmed)==shared)end
 love.graphics.newQuad=newQuad
 assert(quadCount==0 and shared[(warmed.slots or warmed.metatiles)-1],
  'prepared atlas quads were rebuilt or incompletely published')
 local x,y,w,h=shared[0]:getViewport();assert(x==0 and y==0 and w==16 and h==16)
 print('PASS shared atlas quads preserve ROM slots with zero repeated allocations')
 print('PASS directed/list connections, sliced preparation, exact bottom/top/reflection pixels',slices,'slices; max',maxSlice,'warm lookup',duration)
 warm.pump(state,fake,.001) -- one final scan discovers there is no new pair
 local lookups,touches=0,0
 local lookup,touch=ML.tilesetFor,TR.touchGen3
 ML.tilesetFor=function(...)lookups=lookups+1;return lookup(...)end
 TR.touchGen3=function(...)touches=touches+1;return touch(...)end
 -- Give the fixture a real live pair so its LRU protection remains observable.
 state.map.tileset=ts
 collectgarbage('collect')
 local heap=collectgarbage('count');local idleStart=love.timer.getTime()
 -- Diagnostic only: measure allocated bytes without collection masking the
 -- difference. The real application keeps its incremental collector enabled.
 collectgarbage('stop')
 for i=1,1000 do warm.pump(state,fake,.001) end
 local idleTime=love.timer.getTime()-idleStart;local allocated=collectgarbage('count')-heap
 collectgarbage('restart')
 print('IDLE_PREFETCH',1000,'seconds',idleTime,'allocatedKiB',allocated,'lookups',lookups,'touches',touches)
 if os.getenv('PERF_OLD_IDLE')~='1' then
  assert(lookups==0 and touches==1000,'completed prefetch rescanned or stopped protecting live sheets')
 end
 state.neighbors={state.neighbors[1]};warm.pump(state,fake,.001)
 assert(lookups>0,'new neighbourhood did not restart prefetch discovery')
 ML.tilesetFor,TR.touchGen3=lookup,touch
 print('PASS completed neighbourhood skips 1000 discovery scans while keeping live LRU touches; topology change rescans')
 TR.releaseGen3Sheets()
 local budget=V.require('BuildBudget')
 local result
 local co=coroutine.create(function()result=TR.gen3SheetsFor(ts,data,data.constants.gen3Layout)end)
 local slices,maxSlice,firstSlice=0,0,0
 repeat
  local t=love.timer.getTime();budget.begin(co,.001,{})
  local ok,err=coroutine.resume(co);budget.finish();assert(ok,err)
  slices=slices+1;local spent=love.timer.getTime()-t
  if slices==1 then firstSlice=spent end
  maxSlice=math.max(maxSlice,spent)
 until coroutine.status(co)=='dead'
 assert(slices>1,'voxel preparation performed a synchronous engine sheet bake')
 assert(hash(result.bottom)==hashes[1] and hash(result.top)==hashes[2],'voxel preparation changed sheet pixels')
 assert(not hashes[3] or hash(result.cover)==hashes[3],'voxel preparation changed reflection cover')
 print('PASS cold engine sheets obey voxel job budget',slices,'slices; max',maxSlice,'first',firstSlice)
 TR.releaseGen3Sheets()
 local abandoned=coroutine.create(function()TR.gen3SheetsFor(ts,data,data.constants.gen3Layout)end)
 budget.begin(abandoned,.000001,{})
 local ok,err=coroutine.resume(abandoned);budget.finish();assert(ok,err)
 assert(coroutine.status(abandoned)=='suspended' and warm.pending(),'cold bake did not survive caller suspension')
 abandoned=nil -- model cancellation: do not resume the original voxel job
 repeat warm.pump(state,data,.001) until not warm.pending()
 local recovered=assert(TR.gen3SheetsFor(ts,data,data.constants.gen3Layout),'cancelled caller poisoned engine cache')
 assert(hash(recovered.bottom)==hashes[1] and hash(recovered.top)==hashes[2],'cancelled caller changed engine art')
 print('PASS cancelled voxel caller leaves a resumable engine bake and complete cache')
 TR.releaseGen3Sheets();warm.pump(state,fake,.000001);assert(warm.pending())
 assert(TR.gen3SheetsFor(ts,data,data.constants.gen3Layout),'consumer saw incomplete sentinel')
 assert(not warm.pending(),'consumer did not finish pending work')
 print('PASS entering early finishes pending bake without missing tiles')
 TR.releaseGen3Sheets();warm.pump(state,fake,.000001);assert(warm.pending());V.require('Rewrap').unwindAll();assert(not warm.pending())
 print('PASS mod reload finishes pending sheet before removing hooks')
 if factorySlot then
  local _,factory=debug.getupvalue(originalBake,factorySlot)
  assert(factory==originalFactory,'mod unload left the private pixel baker replaced')
  print('PASS private pixel factory restored on mod unload')
 end
 local function up(fn,want)
  for i=1,64 do local n,v=debug.getupvalue(fn,i);if n==want then return v end end
 end
 local sheets=assert(up(originalBake,'gen3Sheets'))
 local evict=assert(up(originalBake,'gen3Evict'))
 local used=assert(up(evict,'gen3Used'))
 local pinned,released={},{}
 for key in pairs(sheets)do pinned[key]=true end
 for i=1,13 do
  local key='pin-fixture-'..i
  local image={release=function()released[key]=true end}
  sheets[key]={bottom=image,top=image};used[key]=-1000000
  if i<=10 then pinned[key]=true end
 end
 TR.pinGen3Sheets(pinned);evict()
 local count=0;for _ in pairs(sheets)do count=count+1 end
 assert(count==TR.GEN3_SHEET_CACHE,'prefetch escaped the sheet cache limit')
 for key in pairs(pinned)do assert(sheets[key] and not released[key],'prefetch released a live map texture')end
 TR.releaseGen3Sheets()
 print('PASS live sheets survive prefetch eviction while the cache remains bounded')
 love.event.quit()
end
function love.errorhandler(why)print('FAIL '..tostring(why));return function()return 1 end end
