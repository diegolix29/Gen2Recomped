local P=assert(loadfile('mods/DRAMATIC_SHAPE/lib/HullPoints.lua'))({})
local point=P.new()
local a=point(-12,32,7)
assert(a==point(-12,32,7) and a[1]==-12 and a[2]==32 and a[3]==7)
assert(point(-12,33,7)~=a and point(-11,32,7)~=a and point(-12,32,8)~=a)
assert(P.new()(-12,32,7)~=a,'pool retained points across unrelated templates')
for _,c in ipairs({{.25,1,2},{-257,0,0},{0,256,0},{0,0,512}})do
 local p,q=point(unpack(c)),point(unpack(c))
 assert(p~=q and p[1]==c[1] and p[2]==c[2] and p[3]==c[3],'unfamiliar coordinates were aliased or rounded')
end
local seen={}
math.randomseed(9548)
for i=1,10000 do
 local x,y,z=math.random(-256,255),math.random(-256,255),math.random(-256,255)
 local p=point(x,y,z)
 local old=seen[p]
 assert(not old or old[1]==x and old[2]==y and old[3]==z,'point key collision')
 seen[p]={x,y,z}
end
local off=assert(loadfile('mods/DRAMATIC_SHAPE/lib/HullPoints.lua'))({internHullPoints=false}).new()
assert(off(1,2,3)~=off(1,2,3),'diagnostic baseline did not disable sharing')
print('Hull corner pools: 10,000 coordinate cases, exact values, isolation and fallback passed')
local uv=P.newUV()
local a=uv(.123456789,.987654321)
assert(a==uv(.123456789,.987654321) and a[1]==.123456789 and a[2]==.987654321)
assert(uv(.1234567891,.987654321)~=a and uv(.123456789,.9876543211)~=a)
assert(P.newUV()(.123456789,.987654321)~=a)
local unshared=assert(loadfile('mods/DRAMATIC_SHAPE/lib/HullPoints.lua'))({internHullUV=false}).newUV()
assert(unshared(.1,.2)~=unshared(.1,.2))
print('Hull UV pools: exact fractional coordinates, seams and template isolation passed')
local lonely=P.new()(128,-256,255)
local precise=P.newUV()(1/3,1e-150)
collectgarbage('collect')
assert(lonely[1]==128 and lonely[2]==-256 and lonely[3]==255,'point did not retain its own storage')
assert(precise[1]==1/3 and precise[2]==1e-150,'UV double precision changed')
local plain=assert(loadfile('mods/DRAMATIC_SHAPE/lib/HullPoints.lua'))({packedHullPoints=false})
assert(type(plain.new()(1,2,3))=='table' and type(plain.newUV()(.1,.2))=='table')
local original=require
require=function(name)if name=='ffi' then error('simulated no FFI')end;return original(name)end
local fallback=assert(loadfile('mods/DRAMATIC_SHAPE/lib/HullPoints.lua'))({})
require=original
local p,u=fallback.new()(-256,255,0),fallback.newUV()(1/3,1e-150)
assert(type(p)=='table' and type(u)=='table' and p[1]==-256 and u[2]==1e-150)
print('Hull storage: owning coordinates, exact double UVs, diagnostic and no-FFI fallbacks passed')
