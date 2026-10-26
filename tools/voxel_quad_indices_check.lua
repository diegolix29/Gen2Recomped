local ffi=require("ffi")
local owned,releases=0,0
local V={require=function(name)
 assert(name=="BuildBudget")
 return {check=function()end,own=function(o)owned=owned+1;return o end,disown=function()owned=owned-1 end}
end}
love={data={newByteData=function(size)
 local bytes=ffi.new("uint8_t[?]",size)
 return {getFFIPointer=function()return bytes end,getSize=function()return size end,release=function()releases=releases+1 end,size=size}
end}}
local Q=assert(loadfile("mods/DRAMATIC_SHAPE/lib/QuadIndices.lua"))(V)
local calls=0
local mesh={setVertexMap=function(_,data,kind)
 calls=calls+1;assert(kind=="uint16" and data.size==32766*2)
 local p=ffi.cast("const uint16_t*",data:getFFIPointer())
 for i=0,32765,6 do
  assert(p[i]==i and p[i+1]==i+1 and p[i+2]==i+2 and p[i+3]==i and p[i+4]==i+2 and p[i+5]==i+5)
 end
end}
assert(Q.apply(mesh,32766) and calls==1 and owned==0 and releases==1)
assert(not Q.apply(mesh,65536) and not Q.apply(mesh,3))
V.indexedQuads=false;assert(not Q.apply(mesh,32766));V.indexedQuads=nil
local src=ffi.new("float[36]")
for i=0,35 do src[i]=i*.125 end
local compact=assert(Q.compact({getFFIPointer=function()return src end,getSize=function()return 144 end},6))
local out=ffi.cast("const float*",compact:getFFIPointer())
for i=0,23 do assert(out[i]==src[i<18 and i or i+12]) end
assert(Q.apply({setVertexMap=function(_,data,kind)
 assert(data.size==12 and kind=='uint16')
 local p=ffi.cast('const uint16_t*',data:getFFIPointer())
 assert(p[0]==0 and p[1]==1 and p[2]==2 and p[3]==0 and p[4]==2 and p[5]==3)
end},6,true))
owned=owned-1;compact:release()
local attempts=0
local failed={setVertexMap=function(_,data)if data then attempts=attempts+1;error("unsupported driver")end end}
assert(not Q.apply(failed,6) and not Q.apply(failed,6) and attempts==1)
assert(owned==0 and releases==4)
local saved=require
require=function(name)if name=="ffi"then error("no FFI")end;return saved(name)end
local fallback=assert(loadfile("mods/DRAMATIC_SHAPE/lib/QuadIndices.lua"))(V)
require=saved
assert(not fallback.apply(mesh,6))
print("Quad indices: exact triangles, uint16 boundaries, ownership, rejection and portable fallback passed")
