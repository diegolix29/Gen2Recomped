local ffi=require("ffi")
local A=assert(loadfile("mods/DRAMATIC_SHAPE/lib/AtlasPixels.lua"))()
local bytes=ffi.new("uint8_t[?]",8*4)
local image={getFFIPointer=function()return bytes end,getFormat=function()return "rgba8" end,getWidth=function()return 4 end}
local write=A.writer(image)
for y=0,1 do for x=0,3 do write(x,y,x*60,y*255,17,255-x*30) end end
for y=0,1 do for x=0,3 do
 local at=(y*4+x)*4
 assert(bytes[at]==x*60 and bytes[at+1]==y*255 and bytes[at+2]==17 and bytes[at+3]==255-x*30)
end end
local calls=0
local fallback={getFormat=function()return "rgba16" end,getFFIPointer=function()error("unsupported format read directly")end,
 setPixel=function(_,x,y,r,g,b,a)
  calls=calls+1;assert(x==2 and y==3 and r==17/255 and g==0 and b==1 and a==0)
 end}
A.writer(fallback)(2,3,17,0,255,0)
local saved=require
require=function(name)if name=="ffi" then error("no FFI")end;return saved(name)end
local portable=assert(loadfile("mods/DRAMATIC_SHAPE/lib/AtlasPixels.lua"))()
require=saved
portable.writer(fallback)(2,3,17,0,255,0)
assert(calls==2)
local reads=0
fallback.getPixel=function(_,x,y)reads=reads+1;return x,y,.25,.75 end
for _,module in ipairs({A,portable})do
 local r,g,b,a=module.reader(fallback)(2,3)
 assert(r==2 and g==3 and b==.25 and a==.75)
end
local unreadable={getFormat=function()return 'rgba8' end,
 getFFIPointer=function()error('pointer unavailable')end,getPixel=fallback.getPixel}
assert(A.reader(unreadable)(2,3)==2 and reads==3)
print("Atlas pixel access: byte writes, unsupported/read-protected formats and no-FFI fallbacks passed")
