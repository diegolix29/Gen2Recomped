io.stdout:setvbuf("no")
local root=assert(os.getenv("ROOT")):gsub("\\","/").."/"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
local CM,map,V,ready,mesh,buildStart
local bodyOnly=os.getenv("PERF_FULL")~="1"
local masks
local slices,draws={},{}
local tag=os.getenv("PERF_TAG") or "after"
local abandoned,preloadedNeighbor
local rootCompleted
local originalDraw,originalInstanced
function love.load()
 if os.getenv("PERF_GPU_INFO")=="1" then
  print("GPU_RUNTIME",love.getVersion())
  print("GPU_RENDERER",love.graphics.getRendererInfo())
  local caps=love.graphics.getSupported()
  print("GPU_FEATURES","instancing="..tostring(caps.instancing),
   "newComputeShader="..type(love.graphics.newComputeShader),
   "dispatchThreadgroups="..type(love.graphics.dispatchThreadgroups))
 end
 if tag:match("^before") then
  local file=assert(io.open(root.."tmp/emerald_perf/baseline/ChunkMesher.lua","rb"),"prepare baseline source snapshots first")
  file:close()
 end
 require("src.core.GameVersion").set("emerald")
 local data=require("src.core.Data");data:load();require("src.core.Game").data=data
 local Assets=require("src.render.Assets")
 local assetRoot=assert(os.getenv("EMERALD_CACHE")):gsub("\\","/").."/"
 local function imageData(path)
  local f=assert(io.open(assetRoot..path,"rb"));local b=f:read("*a");f:close()
  return love.image.newImageData(love.filesystem.newFileData(b,path))
 end
 Assets.imageData=imageData;Assets.image=function(path)return love.graphics.newImage(imageData(path))end
 local libs={};V={sharedHulls=os.getenv("PERF_SHARED_HULLS")=="1"}
 if os.getenv("PERF_CPU")=="1" then V.gpuMeshing=false end
 V.require=function(n)
  if not libs[n] then
   local path=root.."mods/DRAMATIC_SHAPE/lib/"..n..".lua"
   if tag:match("^before") then local baseline=root.."tmp/emerald_perf/baseline/"..n..".lua";local f=io.open(baseline,"rb");if f then f:close();path=baseline end end
   local saved=require
   if n=="MeshBatch" and os.getenv("PERF_NO_FFI")=="1" then
    _G.require=function(name)if name=="ffi" then error("test byte-data fallback") end;return saved(name)end
   end
   libs[n]=assert(loadfile(path))(V)
   _G.require=saved
  end
  return libs[n]
 end
 V.data=function(n)return assert(loadfile(root.."mods/DRAMATIC_SHAPE/data/"..n..".lua"))()end
 V.mod={options={get=function(_,key)return os.getenv("PERF_DISK")=="1" and key=="voxelDiskCache" end}}
 map=require("src.world.MapLoader").load(data,os.getenv("PERF_MAP") or "MAP_G00_N10")
 if os.getenv("PERF_ENGINE")=="1" then
  local game=require("src.core.Game")
  game.overworld={map=map,neighbors={},gen3WorldFor=require("src.world.OverworldController").gen3WorldFor}
  assert(game.overworld:gen3WorldFor(map.def,map,map.tileset),"engine world bridge unavailable")
 end
 if os.getenv("TRACE_BUDGET") then
  local b=V.require("BuildBudget");local last=love.timer.getTime();local ticks=0
  for _,name in ipairs({"tick","check"})do
   local original=b[name]
   b[name]=function(...)
    ticks=ticks+1
    if name=="check" or ticks%32==0 then
     local now=love.timer.getTime()
     if now-last>.03 then print("GAP",now-last,debug.traceback("",2)) end
     last=now
    end
    local result=original(...)
    last=love.timer.getTime() -- exclude time spent suspended between frames
    return result
   end
  end
 end
 if os.getenv("PERF_STAGES")=="1" then
  for _,spec in ipairs({{"Gen3","prepare"},{"Structures","forMap"}})do
   local mod=V.require(spec[1]);local original=mod[spec[2]]
   mod[spec[2]]=function(...)
    local start=love.timer.getTime();local result=original(...)
    local duration=love.timer.getTime()-start
    if duration>.05 then print("STAGE",spec[1],spec[2],duration) end
    return result
   end
  end
 end
 local savedRequire=require
 if os.getenv("PERF_NO_FFI")=="1" then
  _G.require=function(name)if name=="ffi" then error("test table-only runtime") end;return savedRequire(name)end
 end
 CM=V.require("ChunkMesher")
 _G.require=savedRequire
 if os.getenv("PERF_CANCEL")=="1" then
  local Batch=V.require("MeshBatch");local new=Batch.new
  _G.cancelBatches={}
  Batch.new=function()local b=new();cancelBatches[#cancelBatches+1]=b;return b end
 end
 if os.getenv("PERF_NEIGHBORS")=="1" then
  local function up(fn,name)
   for i=1,60 do local n,v=debug.getupvalue(fn,i);if n==name then return v end end
   error("missing scheduler state "..name)
  end
  local choose=up(CM.pump,"nextJob");local jobs=up(CM.request,"jobs")
  local far={id="test-far",distance=10000};local near={id="test-near",distance=1}
  jobs[1]=far;jobs[2]=near
  assert(choose(false)==near,"far neighbor blocks nearby one")
  far.urgent=true;assert(choose(false)==far,"neighbor preempts foreground")
  assert(choose(true)==far,"foreground-only loses urgent map")
  far.urgent=false;assert(choose(true)==nil,"overlay runs neighbor")
  far.co=coroutine.create(function()end)
  assert(choose(false)==far,"shared analysis was interleaved")
  far.co=nil
  far.urgent=true;far.drawable=true;far.seamRefresh=true
  assert(choose(false)==near,"drawable current-map seam refresh starved missing neighbour")
  far.assetsReady=true;far.co=coroutine.create(function()end)
  assert(choose(false)==near,"prepared refresh geometry preempted missing neighbour")
  near.urgent=true
  assert(choose(false)==near,"cold foreground lost to existing terrain maintenance")
  far.seamRefresh=false;far.rebuild=true
  assert(choose(false)==near,"cold foreground lost to an edit refresh")
  jobs[1]=nil;jobs[2]=nil
  print("PASS missing terrain precedes drawable refreshes; foreground and shared preparation remain protected")
  local allowance=up(CM.pump,"sliceFor")
  love.timer.getDelta=function()return 1/30 end
  CM.setFrameTarget(1/30);CM.observeDraw(.004)
  assert(math.abs(allowance(false,false)-.016)<1e-6,"30 Hz background work was starved")
  CM.setFrameTarget(1/60)
  print("PASS 30 Hz paced frames receive proportional background allowance")
  local neighbors=require("src.world.OverworldController").computeNeighbors(data.maps,map.id,1,0,0)
  assert(neighbors[1],"neighbor fixture has no connection")
  preloadedNeighbor=require("src.world.MapLoader").load(data,neighbors[1].id)
  local Scene=V.require("VoxelScene")
  local ox,oy=neighbors[1].ox,neighbors[1].oy
  local previewState={map=map,neighbors={{map=preloadedNeighbor,ox=ox,oy=oy}},
   player={px=0,py=0},game={data=data},computeNeighbors=require("src.world.OverworldController").computeNeighbors}
  assert(pcall(Scene.prefetch,previewState),"live scene prefetch failed")
  assert(CM.pending()==2,"live scene did not queue adjacent map before crossing")
  CM.invalidate()
  print("PASS live scene queues foreground and adjacent maps before entering them")
  CM.request(preloadedNeighbor,true,nil,false,1)
  love.timer.getDelta=function()return 1/60 end
  CM.observeDraw(.004)
 end
 if os.getenv("PERF_PREBAKE_SHARED")=="1" then
  local create=love.graphics.newMesh;local allocations=0
  love.graphics.newMesh=function(...)allocations=allocations+1;return create(...)end
  local ok,why=CM.bake(map,"body",nil)
  love.graphics.newMesh=create
  assert(ok,why);assert(allocations==0,"prebake created shared GPU templates")
  print("PASS shared-hull prebake writes cache without GPU mesh allocations")
 end
 if os.getenv("PERF_ANIMATION")=="1" then
  local tiles=map.renderer.gen3.tiles
  tiles:setAnimFrame(3)
  _G.animationEngineSnapshot={tiles=tiles,frame=tiles.animFrame,override=tiles.tileOverride,cache=tiles.tileCache}
 end
 if os.getenv("PERF_PROFILE")=="1" then
  local profile=require("jit.profile");_G.voxelProfile={}
  profile.start("li5",function(thread,samples,vmstate)
   local stack=vmstate.." "..profile.dumpstack(thread,"pl",5)
   voxelProfile[stack]=(voxelProfile[stack] or 0)+samples
  end)
 end
 if not bodyOnly then masks=assert(V.require("VoxelScene").masksFor(map),"full map masks unavailable") end
 CM.request(map,bodyOnly,masks,true);buildStart=love.timer.getTime()
 if os.getenv("PERF_PREEMPT")=="1" then
  CM.pump(false)
  abandoned=map
  map=require("src.world.MapLoader").load(data,"MAP_G02_N02")
  CM.request(map,bodyOnly,masks,true)
 end
 originalInstanced=love.graphics.drawInstanced
 if originalInstanced then
  love.graphics.drawInstanced=function(m,n,...)
   if ready then draws[#draws+1]=m:getVertexCount()*n end
   return originalInstanced(m,n,...)
  end
 end
 originalDraw=love.graphics.draw
 love.graphics.draw=function(m,...)
  if ready and m.getVertexCount then draws[#draws+1]=m:getVertexCount() end
  return originalDraw(m,...)
 end
end
local elapsed,frameTimes={},{}
local previousPacedFrame
function love.update()
 if os.getenv("PERF_PACED")=="1" then
  local now=love.timer.getTime()
  if previousPacedFrame then love.timer.sleep(math.max(0,1/60-(now-previousPacedFrame))) end
  previousPacedFrame=love.timer.getTime()
 end
 if _G.animationEngineSnapshot then
  local snap=animationEngineSnapshot;local t=snap.tiles
  assert(t.animFrame==snap.frame and t.tileOverride==snap.override and t.tileCache==snap.cache,
   "suspended voxel preparation changed live engine animation state")
 end
 if CM.buildFailure(map.id) then error(CM.buildFailure(map.id)) end
 if not ready then
  local start=love.timer.getTime();collectgarbage("step",1);CM.pump(false);slices[#slices+1]=love.timer.getTime()-start
  if os.getenv("PERF_CANCEL")=="1" and not _G.cancelTestDone then
   local partial
   for _,b in ipairs(cancelBatches)do if b:getVertexCount()>0 then partial=b;break end end
   if partial then
    CM.invalidate(map.id)
    for _,b in ipairs(cancelBatches)do assert(#b.parts==0,"cancelled job retained GPU allocation")end
    print("PASS suspended build releases partial GPU batches immediately")
    _G.cancelTestDone=true
    CM.request(map,bodyOnly,masks,true)
    return
   end
  end
  mesh=CM.peek(map,bodyOnly)
  if mesh and preloadedNeighbor then
   rootCompleted=rootCompleted or love.timer.getTime()
   if not CM.peek(preloadedNeighbor,true) then return end
   local retained=CM.peek(preloadedNeighbor,true)
   local pending=CM.pending()
   assert(CM.request(preloadedNeighbor,true,nil,true)==retained,"seam crossing rebuilds prefetched terrain")
   assert(CM.pending()==pending,"promotion queued redundant work")
   print("PASS neighbor ready before crossing; warm seam promotion adds no job",preloadedNeighbor.id,love.timer.getTime()-rootCompleted)
   preloadedNeighbor=nil
  end
  if mesh then
   if _G.voxelProfile then
    require("jit.profile").stop()
    local rows={};for stack,n in pairs(voxelProfile)do rows[#rows+1]={stack=stack,n=n} end
    table.sort(rows,function(a,b)return a.n>b.n end)
    for i=1,math.min(25,#rows)do print("PROFILE",rows[i].n,rows[i].stack) end
    _G.voxelProfile=nil
   end
   if os.getenv("PERF_ANIMATION")=="1" and not _G.animationPreparedChecked then
    local atlas=V.require("TerrainAtlas")
    local start=love.timer.getTime()
    assert(atlas.forMap(map),"prepared map has no animated atlas")
    local duration=love.timer.getTime()-start
    assert(duration<.02,"prepared terrain still builds its atlas on first draw")
    _G.animationPreparedChecked=true
    print("PASS prepared map animation atlas ready before first draw; live engine animation state unchanged",duration)
   end
   if os.getenv("PERF_REFRESH_PRIORITY")=="1" and not _G.refreshPriorityChecked then
    local cold=require("src.world.MapLoader").load(require("src.core.Data"),"MAP_G00_N16")
    local held=mesh
    if CM.peek(cold,true) then CM.invalidate(cold.id) end
    CM.refresh(map.id,"seam");CM.request(map,bodyOnly,masks,true)
    CM.request(cold,true,nil,false,100)
    local loops=0
    repeat
     CM.request(map,bodyOnly,masks,true);CM.request(cold,true,nil,false,100)
     CM.pump(false);loops=loops+1;assert(loops<5000,"cold neighbour starved behind refresh")
     assert(CM.peek(map,bodyOnly)==held,"drawable current-map refresh overtook missing neighbour")
    until CM.peek(cold,true)
    print("PASS real missing neighbour finishes before current-map seam refresh",cold.id,loops)
    repeat CM.request(map,bodyOnly,masks,true);CM.pump(true) until CM.pending()==0
    mesh=CM.peek(map,bodyOnly)
    _G.refreshPriorityChecked=true
   end
   if os.getenv("PERF_FAIL_REFRESH")=="1" and not _G.failedRefreshChecked then
    local original=V.require("Gen3").prepare
    local old=mesh
    CM.refresh(map.id);CM.request(map,bodyOnly,masks,true)
    V.require("Gen3").prepare=function()error("intentional refresh failure fixture")end
    CM.pump(false)
    V.require("Gen3").prepare=original
    assert(CM.peek(map,bodyOnly)==old,"failed refresh erased the last drawable terrain")
    assert(CM.pending()==0 and CM.buildFailure(map.id),"failed refresh was not recorded")
    for i=1,40 do local n,v=debug.getupvalue(CM.buildFailure,i);if n=="buildErrors" then v[map.id]=nil;break end end
    _G.failedRefreshChecked=true
    print("PASS failed refresh retains its previous drawable terrain")
   end
   if os.getenv("PERF_RETIRE")=="1" and not _G.retirementChecked then
    local cache
    for i=1,40 do local n,v=debug.getupvalue(CM.pair,i);if n=="cache" then cache=v;break end end
    local released=0
    cache["retire-probe"]={full={getVertexCount=function()return CM.historyByteLimit end,
      release=function()released=released+1 end}}
    CM.setLive({[map.id]=true,["retire-probe"]=true},map.id)
    CM.setLive({[map.id]=true},map.id)
    assert(released==0,"boundary change synchronously released GPU terrain")
    CM.pump(false,true)
    assert(released==1,"detached terrain was not retired during background pump")
    _G.retirementChecked=true
    print("PASS boundary eviction detaches immediately and releases GPU terrain in pump")
   end
   if os.getenv("PERF_CAVE_HISTORY")=="1" and not _G.caveHistoryChecked then
    local cache
    for i=1,40 do local n,v=debug.getupvalue(CM.pair,i);if n=="cache" then cache=v;break end end
    local route=mesh
    local ML=require("src.world.MapLoader")
    V.require("EngineSheets") -- install the renderer-LRU protection seam
    local loaderCache
    for i=1,40 do local n,v=debug.getupvalue(ML.cached,i);if n=="cache" then loaderCache=v;break end end
    local held=assert(ML.cached(map.id),"missing retained engine map fixture")
    for i=1,40 do loaderCache["lru-probe-"..i]={renderer={release=function()end}} end
    ML.trim({["lru-probe-40"]=true})
    assert(ML.cached(map.id)==held,"engine LRU evicted the retained route's terrain context")
    for i=1,40 do ML.evict("lru-probe-"..i) end
    local release=function()end
    local tiny=function()return {getVertexCount=function()return 1 end,release=release} end
    cache["cave-a"]={full=tiny()};cache["cave-b"]={full=tiny()};cache["distant"]={full=tiny()}
    CM.setLive({[map.id]=true,distant=true},map.id)
    CM.refresh(map.id);CM.request(map,bodyOnly,masks,true);CM.pump(false)
    CM.setLive({["cave-a"]=true},"cave-a")
    assert(CM.peek(map,bodyOnly)==route,"cancelled refresh discarded published route")
    CM.setLive({["cave-b"]=true},"cave-b")
    assert(CM.peek(map,bodyOnly)==route,"second cave floor discarded route history")
    local entryBytes
    for i=1,40 do local n,v=debug.getupvalue(CM.setLive,i);if n=="entryBytes" then entryBytes=v;break end end
    local limit=CM.historyByteLimit
    CM.historyByteLimit=entryBytes(cache[map.id])+48
    cache["distant"]={full=tiny()}
    CM.setLive({[map.id]=true,distant=true},map.id)
    CM.setLive({["cave-a"]=true},"cave-a")
    assert(CM.peek(map,bodyOnly)==route,"small distant map displaced recently visited route")
    CM.historyByteLimit=limit
    CM.setLive({[map.id]=true},map.id)
    local start=love.timer.getTime()
    assert(CM.request(map,bodyOnly,masks,true)==route,"cave exit lost warm route")
    print("PASS multi-floor cave return retains terrain across cancelled refresh",love.timer.getTime()-start)
    CM.invalidate("cave-a");CM.invalidate("cave-b");CM.invalidate("distant")
    _G.caveHistoryChecked=true
   end
   if os.getenv("PERF_COLD_GHOST")=="1" and not _G.coldGhostChecked then
    local Scene=V.require("VoxelScene");local G3=V.require("Gen3")
    local cold=require("src.world.MapLoader").load(require("src.core.Data"),"MAP_G00_N31")
    assert(not G3.peekMap(cold),"ghost fixture is already analysed")
    local original=G3.forMap
    G3.forMap=function(m,...) assert(m~=cold,"render forced cold neighbour analysis");return original(m,...) end
    assert(Scene.groundAt(cold,0,0)==0,"cold height fallback changed")
    local poses
    for i=1,100 do local n,v=debug.getupvalue(Scene.render,i);if n=="posesOf" then poses=v;break end end
    assert(poses,"missing pose fixture")
    local calls=0
    local npc={cellX=0,cellY=0,py=0,pose=function() calls=calls+1;return nil,0,0,"down",0,false end}
    local result=poses({map=map,ghosts={{map=cold,npc=npc,ox=0,oy=0}},entities={}},function()return nil end)
    assert(#result==0 and calls==1,"cold ghost was drawn or stopped animating")
    G3.forMap=original
    assert(not G3.peekMap(cold),"ghost pose populated cold context")
    print("PASS cold ghost posing/height lookup never builds neighbouring terrain")
    _G.coldGhostChecked=true
   end
   if os.getenv("PERF_HISTORY_VISIBLE")=="1" and not _G.historyVisibleChecked then
    local cache
    for i=1,30 do local name,value=debug.getupvalue(CM.pair,i);if name=="cache" then cache=value;break end end
    assert(cache,"missing fixture cache")
    local fake="history-visible-fixture"
    local entryBytes
    for i=1,30 do local name,value=debug.getupvalue(CM.setLive,i);if name=="entryBytes" then entryBytes=value;break end end
    local needed=assert(entryBytes)(cache[map.id])
    cache[fake]={full={getVertexCount=function()return needed end,release=function()end}}
    CM.setLive({[map.id]=true,[fake]=true})
    local limit=CM.historyByteLimit;CM.historyByteLimit=needed+1
    CM.setLive({[fake]=true})
    assert(CM.peek(map,bodyOnly)==mesh,"large visible map incorrectly consumed the unseen history allowance")
    CM.historyByteLimit=limit;CM.setLive({[map.id]=true});CM.invalidate(fake)
    _G.historyVisibleChecked=true
    print("PASS visible terrain does not consume the bounded unseen-map history")
   end
   if os.getenv("PERF_LEGACY")=="1" then
    assert(V.require("VoxelDiskCache").hits>0,"existing cache was not reused: "..tostring(V.require("VoxelDiskCache").lastError))
    assert(CM.pending()==0,"cached terrain published before map analysis completed")
    print("PASS existing terrain cache reused after its analysis completed")
   end
   if abandoned then
    assert(not CM.peek(abandoned,true),"abandoned map blocked the destination build")
    print("PASS destination preempts abandoned map geometry")
    local pending=CM.pending()
    assert(pending>0,"preemption fixture lost its background job")
    CM.pump(false,true)
    assert(CM.pending()==pending and CM.lastSlice()==0,"overlay advanced automatic background work")
    print("PASS battle/menu overlay pauses background neighbour builds")
   end
   if os.getenv("PERF_STRESS")=="1" then
    _G.stressLoops=(_G.stressLoops or 0)+1
    if _G.stressLoops<=8 then
      local retained=mesh
      CM.setLive({[map.id]=true})
      local limit=CM.historyByteLimit;CM.historyByteLimit=0
      CM.setLive({});CM.historyByteLimit=limit
      CM.pump(false,true)
      while #retained.parts>0 do CM.pump(false,true) end
      assert(#retained.parts==0,"history budget retained unseen GPU parts")
      for key in pairs(V.require("Buildings").stats())do
        assert(not key:find(":"..map.id..":",1,true),"evicted civic template retained")
      end
      collectgarbage("step",100)
      CM.request(map,bodyOnly,masks,true)
      print("PASS eviction/reentry cycle",_G.stressLoops)
      return
    end
   end
   ready=true;print("BUILD",tag,map.id,#slices,love.timer.getTime()-buildStart) end
 end
end
function love.draw()
 if not ready then return end
 local g=V.require("Voxel3D");V.require("VoxelState").angle=math.rad(35)
 local cx,cz=map.def.width*8,map.def.height*8
 g.camera={eye={cx+70,90,cz+130},focus={cx,8,cz},fov=math.rad(45),curve=tonumber(os.getenv("PERF_CURVE")) or 0}
 assert(g.beginScene(800,650,cx,cz,180,146))
 draws={};local start=love.timer.getTime()
 g.draw(mesh,V.require("Gen3").atlasForTileset(map.tileset));g.endScene()
 local img=g.canvas():newImageData() -- GPU fence: measure completion, not submission.
 local dt=love.timer.getTime()-start
 if #elapsed>1 then frameTimes[#frameTimes+1]=dt end
 elapsed[#elapsed+1]=dt
 if #elapsed==10 then
  local total=0;for _,n in ipairs(draws)do total=total+n end
  table.sort(slices);table.sort(frameTimes)
  local hash=love.data.encode("string","hex",love.data.hash("sha256",img:getString()))
  local report={tag=tag,map=map.id,vertices=mesh:getVertexCount(),submitted=total,draws=#draws,
   hullCopies=mesh.stamps and #mesh.stamps or 0,
   storedVertices=mesh:getVertexCount()+(mesh.hullOwner and mesh.hullOwner.bytes/48 or 0),
   parts=mesh.parts and #mesh.parts or 1,pumpMax=slices[#slices],pumpP95=slices[math.max(1,math.ceil(#slices*.95))],
   renderMedian=frameTimes[math.ceil(#frameTimes/2)],renderMax=frameTimes[#frameTimes],imageHash=hash}
  if love.graphics.newComputeShader then
   local gpu=V.require("GpuMesher")
   report.gpuBuilds=gpu.builds;report.cpuFallbacks=gpu.fallbacks;report.mesher=gpu.status()
  else report.mesher="CPU (compute API unavailable)" end
  local output=root.."tmp/emerald_perf/"..tag.."-"..map.id
  local f=assert(io.open(output..".json","wb"));f:write(require("src.link.Json").encode(report));f:close()
  f=assert(io.open(output..".png","wb"));f:write(img:encode("png"):getString());f:close()
  if os.getenv("PERF_DISK")=="1" then
   local cache=V.require("VoxelDiskCache")
   local hit,loaded=cache.load(map,"body",nil)
   assert(hit and loaded and loaded:getVertexCount()==mesh:getVertexCount(),"disk-cache batch roundtrip failed")
   assert(g.beginScene(800,650,cx,cz,180,146))
   g.draw(loaded,V.require("Gen3").atlasForTileset(map.tileset));g.endScene()
   local check=g.canvas():newImageData()
   local diskHash=love.data.encode("string","hex",love.data.hash("sha256",check:getString()))
   check:release();loaded:release()
   assert(diskHash==hash,"disk-cache reload changed rendered pixels")
   print("PASS spatial terrain disk-cache roundtrip")
   if os.getenv("PERF_REFRESH")=="1" then
    local structures=V.require("Structures")
    local original,depth=structures.forMap,0
    structures.forMap=function(m)
     depth=depth+1;local value=original(m);depth=depth-1
     if depth==0 and m.id==map.id and not value._refreshFixture then
      value._refreshFixture=true
      value.objectQuads[#value.objectQuads+1]={
       {8,70,8},{9,70,8},{9,70,9},{8,70,9},
       uv={{0,0},{0,0},{0,0},{0,0}},shade=1}
     end
     return value
    end
    local oldCount=mesh:getVertexCount()
    local held=mesh;local release=held.release;local releasedWhilePublished=false
    held.release=function(self)
     if CM.peek(map,bodyOnly)==self then releasedWhilePublished=true end
     return release(self)
    end
    local cacheTable
    for i=1,40 do local n,v=debug.getupvalue(CM.pair,i);if n=="cache" then cacheTable=v;break end end
    local oldAux=cacheTable[map.id].flowers
    local published=original(map)
    CM.refresh(map.id)
    assert(original(map)==published,"refresh discarded the displayed analysis")
    CM.request(map,bodyOnly,masks,true)
    CM.pump(false)
    assert(original(map)==published,"suspended refresh exposed partial analysis")
    print("PASS refresh keeps published analysis available to render queries")
    local attempts=0
    repeat
     CM.pump(true);attempts=attempts+1;assert(attempts<2000,"refresh stalled")
     if CM.peek(map,bodyOnly)==held then
      assert(original(map)==published,"analysis switched before terrain")
      assert(cacheTable[map.id].flowers==oldAux,"auxiliary mesh switched before terrain")
     end
     assert(not releasedWhilePublished,"published terrain was released during refresh")
    until CM.pending()==0
    CM.pump(false,true) -- release old buffers after the completed publication
    assert(not releasedWhilePublished,"retirement released terrain still in its cache slot")
    print("PASS refresh never releases drawable terrain or publishes mixed-generation auxiliaries")
    mesh=CM.peek(map,bodyOnly)
    assert(mesh and mesh:getVertexCount()==oldCount+6,"forced refresh reused stale terrain")
    assert(original(map)~=published,"completed refresh did not commit analysis")
    print("PASS replacement mesh commits its new analysis atomically")
    structures.forMap=original
    print("PASS forced refresh rebuilds derived geometry instead of cached terrain")
   end
   if os.getenv("PERF_PRUNE")=="1" then
    local raw={vertexCount=function()return 6 end,writeRaw=function(_,path)return love.filesystem.write(path,string.rep("\0",144))end}
    local budget=V.require("BuildBudget")
    local co=coroutine.create(function()for i=1,7 do assert(cache.store(map,"full",{},raw,nil)) end end)
    local yields=0
    repeat
     budget.begin(co,1e-9)
     local ok,why=coroutine.resume(co)
     budget.finish();assert(ok,why)
     if coroutine.status(co)~="dead" then yields=yields+1 end
    until coroutine.status(co)=="dead"
    assert(yields>0,"cache pruning ignored the frame budget")
    print("PASS disk-cache pruning yields to the frame budget",yields)
   end
  end
  -- Shadow rendering uses its own light frustum and must accept the same batches.
  local shadow=V.require("ShadowMap")
  love.graphics.push("all")
  assert(shadow.begin(cx,cz,180,146),"shadow pass unavailable")
  shadow.draw(mesh,V.require("Gen3").atlasForTileset(map.tileset))
  shadow.finish("terrain-check")
  love.graphics.pop()
  print("PASS terrain batches in shadow pass")
  if os.getenv("PERF_SHADOW_COMPARE")=="1" then
   local function shadowHash()
    local image=shadow.texture():newImageData()
    local h=love.data.encode("string","hex",love.data.hash("sha256",image:getString()));image:release();return h
   end
   local actual=shadowHash()
   local shared=V.sharedHulls;V.sharedHulls=false
   local reference=CM.build(map,bodyOnly,masks,true)
   V.sharedHulls=shared
   love.graphics.push("all")
   assert(shadow.begin(cx,cz,180,146));shadow.draw(reference,V.require("Gen3").atlasForTileset(map.tileset));shadow.finish("expanded-reference")
   love.graphics.pop()
   assert(shadowHash()==actual,"shared tree shadows differ from expanded geometry")
   local grid=V.require("VoxelGrid");local savedGrid=grid.override;grid.override=true
   local pose=V.require("Mat4").translate(16,0,-16)
   local function sceneHash(target,reflected)
    assert(g.beginScene(800,650,cx,cz,180,146))
    local capture
    if reflected then
     capture=assert(g.beginPlanar(16,function()g.draw(target,V.require("Gen3").atlasForTileset(map.tileset),pose)end))
     g.endPlanar()
    else g.draw(target,V.require("Gen3").atlasForTileset(map.tileset),pose)end
    g.endScene()
    local pixels=(capture or g.canvas()):newImageData()
    local h=love.data.encode("string","hex",love.data.hash("sha256",pixels:getString()));pixels:release();return h
   end
   assert(sceneHash(mesh,false)==sceneHash(reference,false),"translated grid/lit tree pixels differ")
   assert(sceneHash(mesh,true)==sceneHash(reference,true),"reflected tree pixels differ")
   grid.override=savedGrid
   print("PASS translated grid, lighting and reflected pixels match expanded geometry")
   reference:release()
   print("PASS shared-hull shadow pixels match expanded geometry",actual)
  end
  print("RESULT",require("src.link.Json").encode(report));img:release();love.event.quit()
 else img:release() end
end

function love.errorhandler(message)
 print(debug.traceback(tostring(message),2))
 return function() return 1 end
end
