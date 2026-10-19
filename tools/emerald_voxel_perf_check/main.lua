local root=assert(os.getenv("ROOT")):gsub("\\","/").."/"
package.path=root.."?.lua;"..root.."?/init.lua;"..package.path
local CM,map,V,ready,mesh,buildStart
local slices,draws={},{}
local tag=os.getenv("PERF_TAG") or "after"
local abandoned
local originalDraw
function love.load()
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
 local libs={};V={}
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
    return original(...)
   end
  end
 end
 local savedRequire=require
 if os.getenv("PERF_NO_FFI")=="1" then
  _G.require=function(name)if name=="ffi" then error("test table-only runtime") end;return savedRequire(name)end
 end
 CM=V.require("ChunkMesher")
 _G.require=savedRequire
 CM.request(map,true,nil,true);buildStart=love.timer.getTime()
 if os.getenv("PERF_PREEMPT")=="1" then
  CM.pump(false)
  abandoned=map
  map=require("src.world.MapLoader").load(data,"MAP_G02_N02")
  CM.request(map,true,nil,true)
 end
 originalDraw=love.graphics.draw
 love.graphics.draw=function(m,...)
  if ready and m.getVertexCount then draws[#draws+1]=m:getVertexCount() end
  return originalDraw(m,...)
 end
end
local elapsed,frameTimes={},{}
function love.update()
 if not ready then
  local start=love.timer.getTime();collectgarbage("step",1);CM.pump(false);slices[#slices+1]=love.timer.getTime()-start
  mesh=CM.peek(map,true)
  if mesh then
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
   parts=mesh.parts and #mesh.parts or 1,pumpMax=slices[#slices],pumpP95=slices[math.max(1,math.ceil(#slices*.95))],
   renderMedian=frameTimes[math.ceil(#frameTimes/2)],renderMax=frameTimes[#frameTimes],imageHash=hash}
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
    CM.refresh(map.id);CM.request(map,true,nil,true)
    local attempts=0
    repeat CM.pump(true);attempts=attempts+1;assert(attempts<2000,"refresh stalled") until CM.pending()==0
    mesh=CM.peek(map,true)
    assert(mesh and mesh:getVertexCount()==oldCount+6,"forced refresh reused stale terrain")
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
  print("RESULT",require("src.link.Json").encode(report));img:release();love.event.quit()
 else img:release() end
end

function love.errorhandler(message)
 print(debug.traceback(tostring(message),2))
 return function() return 1 end
end
