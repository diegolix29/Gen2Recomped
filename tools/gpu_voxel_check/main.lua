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
 mesh:release();data:release()
 print('PASS all 2,520 vertex channels equal CPU floats across compute workgroups')
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
 print('PASS explicit CPU selection and re-enabling automatic GPU detection')
end
function love.load()
 local ok,why=xpcall(check,debug.traceback)
 if not ok then print('FAIL '..why) end
 love.event.quit(ok and 0 or 1)
end
function love.errorhandler(why) print('FAIL '..tostring(why));return function()return 1 end end
