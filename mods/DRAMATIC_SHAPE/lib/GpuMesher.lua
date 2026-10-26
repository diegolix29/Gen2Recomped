-- LÖVE 12 compute path: expand four-corner quads directly into GPU vertices.
-- Terrain classification and topology remain identical to the CPU mesher.
local V = ...
local G = { builds=0, fallbacks=0, outputBytes=0, savedBytes=0, inputBytes=0, inputSavedBytes=0 }
local Budget=V.require("BuildBudget")
local shader, checked, reason
local probed=false
local SOURCE = [[
#pragma language glsl4
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
layout(std430) readonly buffer QuadInput { float corners[]; };
struct TerrainVertex { vec4 position; vec2 uv; float shade; float padding; };
layout(std430) writeonly buffer VertexOutput { TerrainVertex vertices[]; };
uniform uint QuadCount;
uniform uint CornersPerQuad;
void computemain() {
  uint q=love_GlobalThreadID.x;
  if (q>=QuadCount) return;
  const uint order[6]=uint[6](0u,1u,2u,0u,2u,3u);
  for (uint k=0u;k<CornersPerQuad;k++) {
    uint corner=CornersPerQuad==4u ? k : order[k];
    uint a=q*24u+corner*6u;
    uint v=q*CornersPerQuad+k;
    vertices[v].position=vec4(corners[a],corners[a+1u],corners[a+2u],1.0);
    vertices[v].uv=vec2(corners[a+3u],corners[a+4u]);
    vertices[v].shade=corners[a+5u];
  }
}
]]
local FORMAT = {
 {name="VertexPosition",format="floatvec4",location=0},
 {name="VertexTexCoord",format="floatvec2",location=1},
 {name="VertexShade",format="float",location=3},
 {name="Padding",format="float",location=7},
}
local function drop(object) if object and object.release then pcall(object.release,object) end end
function G.available()
 if V.gpuMeshing==false then reason="CPU selected";return false end
 if checked then return shader~=nil end
 checked=true
 local g=love and love.graphics
 if not (g and g.newComputeShader and g.newBuffer and g.dispatchThreadgroups) then
  reason="compute API unavailable";return false
 end
 local ok,value=pcall(g.newComputeShader,SOURCE)
 if ok then shader=value else reason=tostring(value) end
 return shader~=nil
end
function G.status() return V.gpuMeshing~=false and shader and "GPU quad expansion" or reason or "not probed" end
function G.part(data,quads,inspect,compact)
 if not G.available() then return nil,G.status() end
 compact=compact and V.indexedQuads~=false and V.compactQuads~=false and quads*6<=65532
 local corners=compact and 4 or 6
 local input,output,mesh,view
 local uploaded=data:getSize()
 local ok,result=pcall(function()
  local source=data
  local used=quads*24*4
  -- Spatial blocks usually finish below capacity. Upload only live quads,
  -- without copying the CPU slab. Older runtimes retain the original path.
  if V.trimGpuInput~=false and used<uploaded and love.data.newDataView then
   local viewed,value=pcall(love.data.newDataView,data,0,used)
   if viewed then view=Budget.own(value);source=view end
  end
  local buffered,value=pcall(love.graphics.newBuffer,"float",source,{shaderstorage=true,datausage="static"})
  if not buffered and view then
   Budget.disown(view);drop(view);view=nil;source=data
   buffered,value=pcall(love.graphics.newBuffer,"float",data,{shaderstorage=true,datausage="static"})
  end
  assert(buffered,value)
  uploaded=source:getSize()
  input=Budget.own(value,true)
  output=Budget.own(love.graphics.newBuffer(FORMAT,quads*corners,{shaderstorage=true,vertex=true,datausage="static"}),true)
  shader:send("QuadInput",input);shader:send("VertexOutput",output);shader:send("QuadCount",quads);shader:send("CornersPerQuad",corners)
  love.graphics.dispatchThreadgroups(shader,math.ceil(quads/64))
  mesh=Budget.own(love.graphics.newMesh({
   {buffer=output,name="VertexPosition",location=0},
   {buffer=output,name="VertexTexCoord",location=1},
   {buffer=output,name="VertexShade",location=3},
  },"triangles"),true)
  if compact then assert(V.require("QuadIndices").apply(mesh,quads*6,true),"compact GPU indices unavailable") end
  -- Optional diagnostics readback; the live mesher never waits on the GPU.
  if inspect then inspect(output,mesh) end
  return mesh
 end)
 if input then Budget.disown(input) end
 if output then Budget.disown(output) end
 if mesh then Budget.disown(mesh) end
 if view then Budget.disown(view) end
 drop(view)
 drop(input);drop(output) -- mesh/shader retain the GPU buffers, not the CPU data
 if not ok then
  drop(mesh);drop(shader);shader=nil;reason=tostring(result);G.fallbacks=G.fallbacks+1
  return nil,reason
 end
 G.builds=G.builds+1
 G.outputBytes=G.outputBytes+quads*corners*32
 G.inputBytes=G.inputBytes+uploaded
 G.inputSavedBytes=G.inputSavedBytes+data:getSize()-uploaded
 if compact then G.savedBytes=G.savedBytes+quads*2*32 end
 return result,compact
end
function G.probe()
 if probed then return G.available(),G.status() end
 probed=true
 if not G.available() then return false,G.status() end
 local data
 local ok,mesh=pcall(function()
 data=love.data.newByteData(love.data.pack("string",string.rep("f",24),
  0,0,0,0,0,1, 1,0,0,1,0,1, 1,1,0,1,1,1, 0,1,0,0,1,1))
 local function inspect(output)
  local read=love.graphics.readbackBuffer(output)
  local x,y,z,w=love.data.unpack("ffff",read,33)
  read:release()
  assert(x==1 and y==0 and z==0 and w==1,"compute preflight returned incorrect vertices")
 end
 for mode=1,2 do
  local tested=G.part(data,1,inspect,mode==2)
  if not tested then return nil end
  if mode==2 then return tested end
  drop(tested)
 end
 end)
 drop(data)
 if not ok then
  drop(shader);shader=nil;reason=tostring(mesh);G.fallbacks=G.fallbacks+1
  return false,reason
 end
 drop(mesh)
 return mesh~=nil,G.status()
end
return G
