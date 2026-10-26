-- ROM decoders already yield byte colors. Avoid converting every sample to
-- normalized floats and back through ImageData:setPixel during atlas baking.
local ok,ffi=pcall(require,"ffi")
local A={}
local normalized
local function byteValues()
 if normalized~=nil then return normalized or nil end
 normalized=false
 if not (ok and love and love.image and love.image.newImageData) then return nil end
 local probe
 local success,values=pcall(function()
  probe=love.image.newImageData(256,1,"rgba8")
  local bytes=ffi.cast("uint8_t*",probe:getFFIPointer())
  for i=0,255 do for c=0,3 do bytes[i*4+c]=i end end
  local out={}
  -- Use the host's own normalization, including float rounding. Thresholds
  -- in object carving must see exactly the same values as getPixel.
  for i=0,255 do out[i]=probe:getPixel(i,0) end
  return out
 end)
 if probe then probe:release() end
 if success then normalized=values end
 return normalized or nil
end
function A.reader(image)
 if ok and image.getFFIPointer and image.getFormat and image:getFormat()=="rgba8" then
  local readable,pointer=pcall(image.getFFIPointer,image)
  local values=readable and pointer and byteValues()
  if values then
   local width,height=image:getWidth(),image:getHeight()
   local bytes=ffi.cast("const uint8_t*",pointer)
   return function(x,y)
    -- Preserve native errors for invalid coordinates; all normal atlas reads
    -- have integer in-range coordinates. Retain the owner with the pointer.
    if x<0 or y<0 or x>=width or y>=height or x%1~=0 or y%1~=0 then return image:getPixel(x,y) end
    local at=(y*width+x)*4
    return values[bytes[at]],values[bytes[at+1]],values[bytes[at+2]],values[bytes[at+3]]
   end
  end
 end
 return function(x,y)return image:getPixel(x,y)end
end
function A.writer(image)
 if ok and image.getFFIPointer and image.getFormat and image:getFormat()=="rgba8" then
  local width=image:getWidth()
  local bytes=ffi.cast("uint8_t*",image:getFFIPointer())
  -- The closure retains its ImageData owner, not just an unowned pointer.
  return function(x,y,r,g,b,a)
   local offset=(y*width+x)*4
   bytes[offset],bytes[offset+1],bytes[offset+2],bytes[offset+3]=r,g,b,a
   return image
  end
 end
 return function(x,y,r,g,b,a) image:setPixel(x,y,r/255,g/255,b/255,a/255) end
end
return A
