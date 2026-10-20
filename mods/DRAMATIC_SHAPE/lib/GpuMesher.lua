-- LÖVE 12 compute path: expand four-corner quads directly into GPU vertices.
-- Terrain classification and topology remain identical to the CPU mesher.
local V = ...
local G = { builds=0, fallbacks=0 }
local shader, checked, reason
local SOURCE = [[
#pragma language glsl4
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
layout(std430) readonly buffer QuadInput { float corners[]; };
struct TerrainVertex { vec4 position; vec2 uv; float shade; float padding; };
layout(std430) writeonly buffer VertexOutput { TerrainVertex vertices[]; };
uniform uint QuadCount;
void computemain() {
  uint q=love_GlobalThreadID.x;
  if (q>=QuadCount) return;
  const uint order[6]=uint[6](0u,1u,2u,0u,2u,3u);
  for (uint k=0u;k<6u;k++) {
    uint a=q*24u+order[k]*6u;
    uint v=q*6u+k;
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
function G.part(data,quads,inspect)
 if not G.available() then return nil,G.status() end
 local input,output,mesh
 local ok,result=pcall(function()
  input=love.graphics.newBuffer("float",data,{shaderstorage=true,datausage="static"})
  output=love.graphics.newBuffer(FORMAT,quads*6,{shaderstorage=true,vertex=true,datausage="static"})
  shader:send("QuadInput",input);shader:send("VertexOutput",output);shader:send("QuadCount",quads)
  love.graphics.dispatchThreadgroups(shader,math.ceil(quads/64))
  mesh=love.graphics.newMesh({
   {buffer=output,name="VertexPosition",location=0},
   {buffer=output,name="VertexTexCoord",location=1},
   {buffer=output,name="VertexShade",location=3},
  },"triangles")
  -- Optional diagnostics readback; the live mesher never waits on the GPU.
  if inspect then inspect(output,mesh) end
  return mesh
 end)
 drop(input);drop(output) -- mesh/shader retain the GPU buffers, not the CPU data
 if not ok then
  drop(mesh);drop(shader);shader=nil;reason=tostring(result);G.fallbacks=G.fallbacks+1
  return nil,reason
 end
 G.builds=G.builds+1
 return result
end
return G
