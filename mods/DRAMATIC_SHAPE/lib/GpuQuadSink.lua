-- Keep four corners on the CPU; the compute shader expands them into six
-- drawable vertices. Fixed-size blocks bound allocations and dispatch time.
local V=...
local ffi=require("ffi")
local GPU=V.require("GpuMesher")
local Budget=V.require("BuildBudget")
local Batch=V.require("MeshBatch")
local Bounds=V.require("MeshBounds")
local Format=V.require("Voxel3D").FORMAT
local M={}
local CAPACITY=4096
local order={0,1,2,0,2,3}
function M.new()
 local blocks,total={},0
 local current
 local function append(c,uv,shade)
  if not current or current.count==CAPACITY then
   Budget.check()
   local data=Budget.own(love.data.newByteData(CAPACITY*24*4))
   current={data=data,ptr=ffi.cast("float*",data:getFFIPointer()),count=0,
    bounds={math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge}}
   blocks[#blocks+1]=current
  end
  local dst,at,b=current.ptr,current.count*24,current.bounds
  local flat=type(shade)~="table"
  for i=1,4 do
   local p,t=c[i],uv[i]
   dst[at],dst[at+1],dst[at+2]=p[1],p[2],p[3]
   dst[at+3],dst[at+4],dst[at+5]=t[1],t[2],flat and shade or shade[i]
   at=at+6
  end
  -- One bounds update per quad, without rescanning the expanded triangles.
  local a,d,e,f=c[1],c[2],c[3],c[4]
  b[1]=math.min(b[1],a[1],d[1],e[1],f[1]);b[4]=math.max(b[4],a[1],d[1],e[1],f[1])
  b[2]=math.min(b[2],a[2],d[2],e[2],f[2]);b[5]=math.max(b[5],a[2],d[2],e[2],f[2])
  b[3]=math.min(b[3],a[3],d[3],e[3],f[3]);b[6]=math.max(b[6],a[3],d[3],e[3],f[3])
  current.count=current.count+1;total=total+6
 end
 local function expand(block)
  local data=Budget.own(love.data.newByteData(block.count*36*4))
  local dst=ffi.cast("float*",data:getFFIPointer())
  for q=0,block.count-1 do
   for k=0,5 do ffi.copy(dst+q*36+k*6,block.ptr+q*24+order[k+1]*6,24) end
   if q%256==0 then Budget.check() end
  end
  return data
 end
 local sink={push=append,vertexCount=function()return total end}
 -- Disk caches retain their existing CPU format. Expand only when a cache
 -- write is requested, never read the live GPU buffer back to the CPU.
 function sink.rawBlocks(fn)
  for i,b in ipairs(blocks)do
   local data=expand(b)
   fn(ffi.cast("const float*",data:getFFIPointer()),b.count*6,i)
   Budget.disown(data);data:release();Budget.check()
  end
 end
 function sink:writeRaw(path)
  local file=love.filesystem.newFile(path)
  if not file or not file:open("w") then return false,"could not write terrain cache" end
  local cleanup=Budget.own({release=function()file:close()end})
  local ok,err=pcall(function()
   sink.rawBlocks(function(ptr,count)
    assert(file:write(ffi.string(ptr,count*24)),"short terrain cache write")
   end)
  end)
  file:close();Budget.disown(cleanup)
  if not ok then love.filesystem.remove(path) end
  return ok,err
 end
 function sink.pushStamp(template,mx,my,mz)
  local src=template.data
  local corners,uv,shades={},{},{}
  local unique={0,1,2,5}
  for first=0,template.count-1,6 do
   for k=1,4 do
    local at=(first+unique[k])*7
    local y=src[at+1]+my;local shade=src[at+5]
    if src[at+6]==1 and y<6 then shade=shade*(1-(0.12*2.4)*(1-y/6)) end
    corners[k]={src[at]+mx,y,src[at+2]+mz}
    uv[k]={src[at+3],src[at+4]};shades[k]=shade
   end
   append(corners,uv,shades)
   if first%768==0 then Budget.check() end
  end
  return true
 end
 function sink.finish()
  if total==0 then return nil end
  local batch=Batch.new()
  local ok,err=pcall(function()
   for i,b in ipairs(blocks)do
    Budget.check()
    local part=GPU.part(b.data,b.count)
    if part then
     batch.parts[#batch.parts+1]=part;batch.count=batch.count+b.count*6
     Bounds.set(part,b.bounds)
    else
     -- Allocation, shader and dispatch failures all keep the original quad
     -- data intact, so this block and subsequent builds can fall back safely.
     local data=expand(b)
     Batch.add(batch,Format,data,b.count*6)
     Budget.disown(data);data:release()
    end
    Budget.disown(b.data);b.data:release();blocks[i]=false
    Budget.check()
   end
  end)
  if not ok then batch:release();error(err) end
  return batch
 end
 return sink
end
return M
