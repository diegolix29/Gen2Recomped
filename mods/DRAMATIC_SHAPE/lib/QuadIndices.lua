-- The immutable quad stream is 0,1,2,0,2,3. Reuse the first triangle's
-- corners in the GPU vertex cache without changing raw/cache geometry.
local V=...
local Budget=V.require("BuildBudget")
local ok,ffi=pcall(require,"ffi")
local Q={applied=0}
local patterns={}
local disabled=false
function Q.compact(data,count)
 if V.indexedQuads==false or V.compactQuads==false or disabled or not ok
    or not (love and love.data and love.data.newByteData)
    or count==0 or count%6~=0 or count>65532
    or not data.getFFIPointer or not data.getSize or data:getSize()~=count*24 then return nil end
 local out=Budget.own(love.data.newByteData(count*16))
 local src=ffi.cast("const uint8_t*",data:getFFIPointer())
 local dst=ffi.cast("uint8_t*",out:getFFIPointer())
 for q=0,count/6-1 do
  ffi.copy(dst+q*96,src+q*144,72)
  ffi.copy(dst+q*96+72,src+q*144+120,24)
  if q%128==0 then Budget.check() end
 end
 return out
end
function Q.apply(mesh,count,compact)
 if V.indexedQuads==false or disabled or not ok or not mesh.setVertexMap
    or count==0 or count%6~=0 or count>65532 then return false end
 if not (love.data and love.data.newByteData) then return false end
 local step=compact and 4 or 6
 local record=patterns[step]
 if not record or record.capacity<count then
  local nextCapacity=math.max(count,32766)
  local nextPattern=ffi.new("uint16_t[?]",nextCapacity)
  for i=0,nextCapacity-1,6 do
   local base=i/6*step
   nextPattern[i],nextPattern[i+1],nextPattern[i+2]=base,base+1,base+2
   nextPattern[i+3],nextPattern[i+4],nextPattern[i+5]=base,base+2,base+step-1
   if i%1536==0 then Budget.check() end
  end
  record={pattern=nextPattern,capacity=nextCapacity};patterns[step]=record
 end
 local data=Budget.own(love.data.newByteData(count*2))
 ffi.copy(data:getFFIPointer(),record.pattern,count*2)
 Budget.check()
 -- Exact Data size also works on older runtimes with no index-count arg.
 local success=pcall(mesh.setVertexMap,mesh,data,"uint16")
 Budget.disown(data);data:release()
 if not success then
  disabled=true
  pcall(mesh.setVertexMap,mesh)
  return false
 end
 Q.applied=Q.applied+1
 return true
end
return Q
