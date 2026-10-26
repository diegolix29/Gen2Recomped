local ffi=require('ffi')
local cleanup={}
local libs={Rewrap={onUnwind=function(fn)cleanup[#cleanup+1]=fn end}}
local V={}
V.require=function(n)
 if not libs[n]then libs[n]=assert(loadfile('mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))(V)end
 return libs[n]
end
love={image={newImageData=function(w,h)
 local bytes=ffi.new('uint8_t[?]',w*h*4)
 return {getFormat=function()return 'rgba8'end,getWidth=function()return w end,getFFIPointer=function()return bytes end,bytes=bytes}
end}}
local fallbacks=0
local original=function()fallbacks=fallbacks+1;return function()end,function()return 'fallback'end end
local pixelCanvas=original
local function bake(w,h)return pixelCanvas(w,h)end
local M=V.require('EnginePixelCanvas')
assert(M.install(bake) and M.installed)
local plot,finish=bake(2,2)
plot(0,0,127,255,17);plot(-1,0,1,2,3);plot(2,1,1,2,3)
local image=finish()
assert(image.bytes[0]==127 and image.bytes[1]==255 and image.bytes[2]==17 and image.bytes[3]==255)
for i=4,15 do assert(image.bytes[i]==0,'transparent background changed')end
love.image.newImageData=function()error('unsupported RGBA allocation')end
local _,failed=bake(2,2);assert(failed()=='fallback' and fallbacks==1)
for i=#cleanup,1,-1 do cleanup[i]()end
assert(not M.installed and pixelCanvas==original)
assert(not M.install(function()return 1 end),'unknown private layout was modified')
local saved=debug;debug=nil
assert(not M.install(bake),'missing debug API did not preserve original path')
debug=saved
print('Engine pixel canvas: byte colors, transparency, bounds, failure fallback and exact unload restoration passed')
