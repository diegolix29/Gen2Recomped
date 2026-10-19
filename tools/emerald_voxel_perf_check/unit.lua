-- ROM-free checks for conservative chunk culling and buffer ownership.
local n=0
local function check(v,msg) assert(v,msg);n=n+1 end
local drawn,freed={},0
love={graphics={newMesh=function(_,vertices)
 local m={vertices=vertices}
 function m:setVertices(data) self.data=data end
 function m:setTexture(tex) self.texture=tex end
 function m:release() freed=freed+1 end
 return m
end,draw=function(mesh) drawn[#drawn+1]=mesh end},data={unpack=function(_,data,pos)
 local i=(pos-1)/24*6;return data[i+1],data[i+2],data[i+3]
end}}
local libs={};local V={}
V.require=function(name)
 if name=='BuildBudget' then return {check=function()end} end
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
print('Voxel chunk checks: '..n..' passed')
