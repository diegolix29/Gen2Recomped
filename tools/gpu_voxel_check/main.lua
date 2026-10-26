io.stdout:setvbuf('no')
local root=assert(os.getenv('ROOT')):gsub('\\','/')..'/'
package.path=root..'?.lua;'..package.path
local format={{'VertexPosition','float',3},{'VertexTexCoord','float',2},{'VertexShade','float',1}}
local function namespace()
 local libs={Voxel3D={FORMAT=format}}
 local V={}
 V.require=function(n)
  if not libs[n] then libs[n]=assert(loadfile(root..'mods/DRAMATIC_SHAPE/lib/'..n..'.lua'))(V) end
  return libs[n]
 end
 return V
end
local function check()
 local V=namespace();local G=V.require('GpuMesher')
 if not love.graphics.newComputeShader then
  assert(not G.available(),'unsupported runtime enabled compute')
  print('PASS automatic CPU fallback on LOVE 11.5');return
 end
 assert(G.available(),G.status())
 local ffi=require('ffi');local quads=70
 local data=love.data.newByteData(quads*24*4)
 local ptr=ffi.cast('float*',data:getFFIPointer())
 for i=0,quads*24-1 do ptr[i]=(i%31-15)/7 end
 local mesh,why=G.part(data,quads,function(buffer)
  assert(buffer:getElementStride()==32,'GPU storage alignment changed')
  local read=love.graphics.readbackBuffer(buffer)
  local actual=ffi.cast('const float*',read:getFFIPointer())
  local order={0,1,2,0,2,3}
  for q=0,quads-1 do for k=0,5 do
   local src=q*24+order[k+1]*6;local dst=(q*6+k)*8
   assert(actual[dst+3]==1,'position W incorrect')
   for j=0,5 do assert(actual[dst+j+(j>=3 and 1 or 0)]==ptr[src+j],
    ('GPU vertex mismatch quad %d corner %d channel %d'):format(q,k,j))end
  end end
  read:release()
 end)
 assert(mesh,why);assert(mesh:getVertexCount()==quads*6)
 mesh:release()
 print('PASS all 2,520 vertex channels equal CPU floats across compute workgroups')
 local compact,used=G.part(data,quads,function(buffer)
  local read=love.graphics.readbackBuffer(buffer)
  assert(read:getSize()==quads*4*32,'compact compute buffer did not shrink')
  local actual=ffi.cast('const float*',read:getFFIPointer())
  for q=0,quads-1 do for k=0,3 do
   local src=q*24+k*6;local dst=(q*4+k)*8
   assert(actual[dst+3]==1)
   for j=0,5 do assert(actual[dst+j+(j>=3 and 1 or 0)]==ptr[src+j],'compact GPU channel mismatch')end
  end end
  read:release()
 end,true)
 assert(compact and used and compact:getVertexCount()==quads*4)
 local indices=compact:getVertexMap()
 assert(#indices==quads*6)
 for q=0,quads-1 do
  local order={1,2,3,1,3,4}
  for k=1,6 do assert(indices[q*6+k]==q*4+order[k],'compact GPU triangles changed')end
 end
 compact:release();data:release()
 print('PASS compact compute: 1,680 exact channels, four-corner storage and original triangles')
 local slab=love.data.newByteData(4096*96)
 local trimmed=namespace().require('GpuMesher')
 local one=assert(trimmed.part(slab,1,function(buffer)
  local read=love.graphics.readbackBuffer(buffer)
  local p=ffi.cast('const float*',read:getFFIPointer())
  assert(p[0]==0 and p[3]==1 and p[8]==0 and p[11]==1)
  read:release()
 end,true))
 assert(trimmed.inputBytes==96 and trimmed.inputSavedBytes==4095*96,'partial slab was uploaded at full capacity')
 one:release()
 local dataView=love.data.newDataView
 love.data.newDataView=nil
 local old=namespace().require('GpuMesher');one=assert(old.part(slab,1,nil,true));one:release()
 assert(old.inputBytes==slab:getSize() and old.inputSavedBytes==0)
 love.data.newDataView=dataView
 local buffer=love.graphics.newBuffer
 love.graphics.newBuffer=function(format,data,options)
  if type(data)~='number' and data.typeOf and data:typeOf('DataView') then error('simulated rejected DataView')end
  return buffer(format,data,options)
 end
 local rejectedView=namespace().require('GpuMesher');one=assert(rejectedView.part(slab,1,nil,true));one:release()
 assert(rejectedView.inputBytes==slab:getSize() and rejectedView.fallbacks==0)
 love.graphics.newBuffer=buffer;slab:release()
 print('PASS partial GPU input uploads live bytes; missing/rejected DataView retains CPU slab input')
 local original=love.graphics.newComputeShader
 love.graphics.newComputeShader=function()error('simulated unsupported shader')end
 local rejected=namespace().require('GpuMesher')
 assert(not rejected.available(),'shader failure did not select CPU')
 love.graphics.newComputeShader=original
 print('PASS unsupported shader selects CPU')
 local attempts=0;local dispatch=love.graphics.dispatchThreadgroups
 love.graphics.dispatchThreadgroups=function(...)
  attempts=attempts+1
  if attempts==2 then error('simulated device dispatch failure')end
  return dispatch(...)
 end
 local sink=V.require('GpuQuadSink').new()
 local c={{0,0,0},{10,0,0},{10,10,0},{0,10,0}}
 local uv={{0,0},{1,0},{1,1},{0,1}}
 for _=1,4097 do sink.push(c,uv,{.5,.6,.7,.8})end
 local batch=sink.finish()
 love.graphics.dispatchThreadgroups=dispatch
 assert(batch:getVertexCount()==4097*6,'fallback lost terrain')
 assert(attempts==2 and G.fallbacks==1 and not G.available(),'failed GPU was retried')
 assert(#batch.parts==2,'GPU/CPU partial build was not retained')
 batch:release()
 print('PASS mid-build dispatch failure retains GPU part and builds remainder on CPU')
 V.gpuMeshing=false;assert(not G.available())
 local fresh=namespace();fresh.gpuMeshing=false;assert(not fresh.require('GpuMesher').available())
 fresh.gpuMeshing=true;assert(fresh.require('GpuMesher').available())
 assert(fresh.require('GpuMesher').probe(),'startup GPU preflight failed')
 print('PASS explicit CPU selection and re-enabling automatic GPU detection')
 local indexFailure=namespace();local get=indexFailure.require
 local q=get('QuadIndices');q.apply=function()return false end
 local rejectedSink=get('GpuQuadSink').new()
 rejectedSink.push(c,uv,1)
 local recovered=rejectedSink.finish()
 assert(recovered and recovered:getVertexCount()==6 and recovered.parts[1]:getVertexCount()==6,
  'rejected compact indices did not recover original CPU geometry')
 assert(get('GpuMesher').fallbacks==1 and not get('GpuMesher').available())
 recovered:release()
 print('PASS rejected compact GPU index upload falls back to six-corner CPU geometry')
 local cancelled=namespace();local cg=cancelled.require('GpuMesher')
 assert(cg.available())
 local cb=cancelled.require('BuildBudget');local owned={}
 local cancelData=love.data.newByteData(96)
 local co=coroutine.create(function()cg.part(cancelData,1,nil,true)end)
 cb.begin(co,0,owned)
 local resumed,why=coroutine.resume(co);cb.finish();assert(resumed,why)
 assert(coroutine.status(co)=='suspended','compact upload never reached a cancellation checkpoint')
 local objects={};for object in pairs(owned)do objects[#objects+1]=object end
 assert(#objects>=3,'suspended compute buffers/mesh lack cancellation ownership')
 cb.release(owned);assert(next(owned)==nil)
 for _,object in ipairs(objects)do
  local method=object.getVertexCount or object.getSize or object.getElementStride
  if method then assert(not pcall(method,object),'cancelled GPU object remained allocated')end
 end
 co=nil;cancelData:release()
 local nextData=love.data.newByteData(96)
 local retry=assert(cg.part(nextData,1,nil,true),'cancelled index pattern poisoned the next upload')
 retry:release();nextData:release()
 print('PASS cancellation during compact index preparation releases GPU objects and permits retry')
end
function love.load()
 local ok,why=xpcall(check,debug.traceback)
 if not ok then print('FAIL '..why) end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(why) print('FAIL '..tostring(why));return function()return 1 end end
