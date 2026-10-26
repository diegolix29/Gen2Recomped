-- Rejecting an index upload after compact allocation must recreate the
-- original six-corner mesh, not leave an invalid four-corner triangle list.
local ffi=require('ffi')
local owned={}
local budget={check=function()end,own=function(o)owned[o]=true;return o end,disown=function(o)owned[o]=nil end}
local sizes,released={},0
love={data={newByteData=function(size)
 local bytes=ffi.new('uint8_t[?]',size)
 return {getSize=function()return size end,getFFIPointer=function()return bytes end,release=function()end}
end},graphics={newMesh=function(_,data)
 sizes[#sizes+1]=data:getSize()
 return {setVertexMap=function(_,map)if map then error('driver rejected indices')end end,
  release=function()released=released+1 end}
end}}
local libs={BuildBudget=budget,Mat4={},MeshBounds={set=function()end,encloseFloats=function(b)return b end}}
local V={}
V.require=function(n)
 if not libs[n]then libs[n]=assert(loadfile('mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))(V)end
 return libs[n]
end
local B=V.require('MeshBatch')
local plain=B.new()
local plainData=love.data.newByteData(144)
B.add(plain,{},plainData,6,{0,0,0,1,1,1},false)
assert(#sizes==1 and sizes[1]==144,'instanced hull opt-out changed its upload layout')
plain:release();owned[plain]=nil;sizes={};released=0
local batch=B.new()
local data=love.data.newByteData(144)
B.add(batch,{},data,6,{0,0,0,1,1,1})
assert(#sizes==2 and sizes[1]==96 and sizes[2]==144,'original allocation not recreated')
assert(batch:getVertexCount()==6 and #batch.parts==1 and released==1)
assert(not owned[data],'input ownership retained after upload')
for object in pairs(owned)do assert(object==batch,'temporary allocation leaked on index rejection')end
batch:release();assert(released==2,'fallback buffer not released')
print('Indexed upload rejection: original mesh restored with no partial buffers or temporary ownership')
