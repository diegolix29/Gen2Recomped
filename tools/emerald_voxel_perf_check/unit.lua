-- ROM-free checks for conservative chunk culling and buffer ownership.
local n=0
local function check(v,msg) assert(v,msg);n=n+1 end
local drawn,freed={},0
love={graphics={newMesh=function(_,vertices)
 local m={vertices=vertices,data=type(vertices)=='table' and vertices or nil}
 function m:setVertices(data) self.data=data end
 function m:setTexture(tex) self.texture=tex end
 function m:release() freed=freed+1 end
 return m
end,draw=function(mesh) drawn[#drawn+1]=mesh end},data={unpack=function(_,data,pos)
 local i=(pos-1)/24*6;return data[i+1],data[i+2],data[i+3]
end}}
local libs={};local V={}
V.require=function(name)
 if name=='BuildBudget' then return {check=function()end,own=function(o)return o end,disown=function()end} end
 if not libs[name] then libs[name]=assert(loadfile('mods/DRAMATIC_SHAPE/lib/'..name..'.lua'))(V) end
 return libs[name]
end
local B=V.require('MeshBatch');local Bounds=V.require('MeshBounds')
local batch=B.new()
local function verts(x) return {{x,0,0,0,0,1},{x+1,0,0,1,0,1},{x,1,0,0,1,1}} end
B.addTable(batch,{},verts(0));B.addTable(batch,{},verts(10))
check(batch:getVertexCount()==6 and #batch.parts==2,'table-only runtime creates bounded parts')
local box=Bounds.get(batch.parts[1]);check(box[1]==0 and box[4]==1 and box[5]==1,'exact bounds')
local vp=V.require('Mat4').identity()
B.draw(batch,'texture',vp)
check(#drawn==1 and drawn[1]==batch.parts[1],'off-screen part culled')
check(drawn[1].texture=='texture','atlas stays attached')
drawn={};B.draw(batch,nil,nil)
check(#drawn==2,'unknown/curved camera draws conservatively')
local third=B.new();local data={-2,3,4,0,0,1, -1,4,5,0,0,1, -2,4,5,0,0,1}
B.add(third,{},data,3)
box=Bounds.get(third.parts[1]);check(box[1]==-2 and box[2]==3 and box[6]==5,'byte data fallback bounds')
check(third.parts[1].data==data,'unmodified vertex stream uploaded')
local trusted=B.new()
local savedUnpack=love.data.unpack
love.data.unpack=function()error('known bounds must not rescan the vertex stream')end
B.add(trusted,{},data,3,{-2,3,4,-1,4,5})
love.data.unpack=savedUnpack
check(Bounds.get(trusted.parts[1])[6]>=5,'known streamed bounds bypass redundant vertex scans')
trusted:release();freed=freed-1
batch:release();third:release();check(freed==3,'all GPU parts released')
batch:release();check(freed==3,'release is idempotent')
-- A translated chunk is tested in world coordinates, not local map space.
check(Bounds.hidden({},{})==false,'unregistered meshes never culled')
local bendPart={};Bounds.set(bendPart,{0,10,0,1,11,0})
check(Bounds.hidden(bendPart,vp),'flat box is above the view')
check(not Bounds.hiddenCurved(bendPart,vp,nil,1,0,3),'curved terrain entering view is preserved')
check(Bounds.hiddenCurved(bendPart,vp,nil,10,0,3),'curved terrain below view is culled')
check(not Bounds.hiddenCurved(bendPart,vp,V.require('Mat4').scale(2,2,2),1,0,3),'unfamiliar transforms stay conservative')
libs.Voxel3D={FORMAT={}}
libs.Gen3={mapIsGen3=function()return true end,describe=function()return {perRow=16,width=128,height=2336}end,
 tileAt=function()return 1 end}
local cache=V.require('VoxelDiskCache')
local function up(fn,name)
 for i=1,30 do local key,value=debug.getupvalue(fn,i);if key==name then return value end end
 error('missing cache-key function '..name)
end
local bodyKey=up(up(cache.has,'signature'),'bodySignature')
local blocks=up(cache.load,'parseBlocks')
local layout=blocks('VXM2\nx\n6\n0\nT 6 0 0 0 1 2 3\n',6,0)
check(layout and layout[1][1]==6 and layout[1][2][6]==3,'cache preserves spatial block layout')
check(not blocks('VXM2\nx\n6\n0\n',6,0),'legacy cache uses bounded scan')
check(not blocks('T 12 0 0 0 1 2 3',6,0),'corrupt layout counts fall back safely')
check(not blocks('T 6 2 0 0 1 2 3',6,0),'inverted cache bounds rejected')
check(not blocks('T 6 nan 0 0 1 2 3',6,0),'non-finite cache bounds rejected')
local function map(border,elevation,collision,width)
 return {id='same',def={width=1,height=1,tileset='pair',border=border,elevationCells={elevation or 0},collisionCells={collision or 0}},
  tileset={blockTiles=2,imageWidth=width},tileAt=function()return 1 end}
end
local key=bodyKey(map({4,5,6,7},0,0))
check(key==bodyKey(map({4,5,6,7},0,0)),'border table addresses never enter cache identity')
check(key==bodyKey(map({4,5,6,7},0,0,999)),'renderer side effects never change canonical atlas identity')
check(key~=bodyKey(map({4,5,6,8},0,0)),'border edits invalidate geometry')
check(key~=bodyKey(map({4,5,6,7},1,0)),'elevation edits invalidate geometry')
check(key~=bodyKey(map({4,5,6,7},0,1)),'collision edits invalidate geometry')
local budget=assert(loadfile('mods/DRAMATIC_SHAPE/lib/BuildBudget.lua'))()
local transition={};local battle={}
check(not budget.covered(setmetatable({alpha=function()return 1 end},battle),transition),'battles never get hidden-screen budgets')
check(not budget.covered(setmetatable({alpha=function()return .5 end},transition),transition),'visible fade keeps responsive budget')
check(budget.covered(setmetatable({alpha=function()return 1 end},transition),transition),'opaque fade permits covered budget')
check(not budget.covered(nil,transition),'absent overlay is visible')
check(math.abs(budget.frameCost(1/60,.0015,.004,1/60)-.007)<1e-9,'VSync wait is not charged as world rendering work')
check(budget.frameCost(.04,.005,.004,1/60)==.035,'over-budget frames retain conservative allowance')
check(budget.frameCost(1/60,.0015,nil,1/60)> .015,'unmeasured hosts retain old timing fallback')
-- A cancelled suspended job releases its allocations immediately.
do
 local Budget=assert(loadfile('mods/DRAMATIC_SHAPE/lib/BuildBudget.lua'))()
 local owned, released={},0
 local object={release=function()released=released+1 end}
 local co=coroutine.create(function()Budget.own(object);Budget.check()end)
 Budget.begin(co,-1,owned);assert(coroutine.resume(co));Budget.finish()
 check(coroutine.status(co)=='suspended' and owned[object],'suspended allocation tracked')
 Budget.release(owned)
 check(released==1 and next(owned)==nil,'cancel releases resources without garbage collection')
 local keep={release=function()error('completed allocation released')end}
 co=coroutine.create(function()Budget.own(keep);Budget.disown(keep)end)
 Budget.begin(co,1,owned);assert(coroutine.resume(co));Budget.finish();Budget.release(owned)
 check(next(owned)==nil,'transferred allocations are disowned')
end
-- A civic model settles the entire foundation to the doorstep datum.
do
 local Civic=assert(loadfile('mods/DRAMATIC_SHAPE/lib/EmeraldBuildings.lua'))({})
 local key=(12+64)*4096+10+64
 local S={shapeAt={[key]={h=16}},runs={},objectQuads={{{0,0,0},{1,0,0},{1,1,0},{0,1,0}}},
 civicPlacements={{door={10,12},tx=8,ty=4,width=8,height=8,first=1,last=1,base=0}}}
 Civic.settle(S)
 local same=true
 for y=4,11 do for x=8,15 do same=same and S.civicFloor[(y+64)*4096+x+64]==16 end end
 check(same and S.objectQuads[1][1][2]==16,'foundation and building settle together')
 Civic.settle(S)
 check(S.objectQuads[1][1][2]==16,'settling is idempotent')
end
-- Render queries retain a complete analysis throughout a sliced rebuild.
do
 local A=assert(loadfile('mods/DRAMATIC_SHAPE/lib/AnalysisCache.lua'))()
 local cache,begin,clear=A.new();local old,new={},{}
 cache.map=old
 local co=coroutine.create(function()
  local tx=begin('map');check(cache.map==nil,'rebuild starts with private cache miss')
  cache.map=new;coroutine.yield();tx.commit()
 end)
 assert(coroutine.resume(co));check(cache.map==old,'render sees published analysis while rebuild is suspended')
 assert(coroutine.resume(co));check(cache.map==new,'analysis commits atomically')
 local cancelled
 co=coroutine.create(function()cancelled=begin('map');cache.map={};coroutine.yield()end)
 assert(coroutine.resume(co));cancelled.release()
 check(cache.map==new,'cancel retains published analysis')
 clear();check(cache.map==nil,'global invalidation clears published analysis')
end
print('Voxel chunk checks: '..n..' passed')
