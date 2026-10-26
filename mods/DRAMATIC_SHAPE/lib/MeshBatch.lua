-- Terrain keeps its exact vertex stream, but uploads bounded GPU buffers.
-- Conservative per-buffer bounds let every camera (including battle and sun)
-- skip terrain outside its view instead of submitting a map-sized mesh.
local V = ...
local Bounds = V.require("MeshBounds")
local Budget = V.require("BuildBudget")
local Mat4 = V.require("Mat4")
local okFFI, ffi = pcall(require, "ffi")
local Batch = {}
function Batch.new()
  local batch = { parts = {}, count = 0 }
  function batch:getVertexCount() return self.count end
  function batch:release()
    if self.hullOwner then self.hullOwner:release();self.hullOwner=nil;self.stamps=nil end
    for _, part in ipairs(self.parts) do part:release();Budget.check() end
    self.parts = {}; self.count = 0
  end
  return Budget.own(batch,true)
end
function Batch.add(batch, format, data, count, knownBounds, indexed)
  Budget.own(data)
  local x0,y0,z0,x1,y1,z1 = math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge
  local ptr = okFFI and data.getFFIPointer and ffi.cast("const float*", data:getFFIPointer())
  for i = 0, knownBounds and -1 or count - 1 do
    local x,y,z
    if ptr then x,y,z = ptr[i*6],ptr[i*6+1],ptr[i*6+2]
    else x,y,z = love.data.unpack("fff", data, i*24+1) end
    x0=math.min(x0,x); y0=math.min(y0,y); z0=math.min(z0,z)
    x1=math.max(x1,x); y1=math.max(y1,y); z1=math.max(z1,z)
    if i % 2048 == 0 then Budget.check() end
  end
  Budget.check()
  -- Every caller supplies an exactly sized Data block. Upload at creation:
  -- allocating an empty mesh first also zeroed/copied the whole buffer before
  -- setVertices replaced it, doubling driver work on every spatial chunk.
  local indices=V.require("QuadIndices")
  local compact=indexed~=false and indices.compact(data,count)
  local part = love.graphics.newMesh(format, compact or data, "triangles", "static")
  batch.parts[#batch.parts+1] = part
  if compact then
    if not indices.apply(part,count,true) then
      -- An advertised API can still be rejected by a driver. Recreate the
      -- original six-vertex stream rather than drawing four as triangles.
      part:release()
      local slot=#batch.parts;batch.parts[slot]=nil
      part=love.graphics.newMesh(format,data,"triangles","static")
      batch.parts[slot]=part
    end
    Budget.disown(compact);compact:release()
  elseif indexed~=false then indices.apply(part,count) end
  Bounds.set(part, knownBounds and Bounds.encloseFloats(knownBounds) or {x0,y0,z0,x1,y1,z1})
  batch.count = batch.count + count
  Budget.check()
  Budget.disown(data)
end
function Batch.addTable(batch, format, vertices,indexed)
  local x0,y0,z0,x1,y1,z1 = math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge
  for i,v in ipairs(vertices) do
    x0=math.min(x0,v[1]); y0=math.min(y0,v[2]); z0=math.min(z0,v[3])
    x1=math.max(x1,v[1]); y1=math.max(y1,v[2]); z1=math.max(z1,v[3])
    if i % 2048 == 0 then Budget.check() end
  end
  Budget.check()
  local part = love.graphics.newMesh(format, vertices, "triangles", "static")
  batch.parts[#batch.parts+1] = part
  -- Table sinks emit the same six-vertex quad stream as byte sinks.
  if indexed~=false then V.require("QuadIndices").apply(part,#vertices) end
  Bounds.set(part, {x0,y0,z0,x1,y1,z1})
  batch.count = batch.count + #vertices
  Budget.check()
end

-- Uniforms are set once by the caller, not once per terrain part.
local planeScratch={}
function Batch.draw(mesh, texture, vp, model, curve, cx, cz)
  local clip = vp and model and Mat4.mul(vp,model) or vp
  local curved=curve and curve>0
  -- Direct support-plane tests were faster in alternating native full-pass
  -- measurements. Keep the prepared variant available to diagnostic probes.
  local prepared=V.terrainPlanes==true
  local planes=not curved and prepared and Bounds.planes(clip,planeScratch)
  for _,part in ipairs(mesh.parts) do
    local hidden
    if curved then hidden=Bounds.hiddenCurved(part,vp,model,curve,cx or 0,cz or 0)
    elseif prepared then hidden=Bounds.hiddenPlanes(part,planes)
    else hidden=Bounds.hidden(part,clip) end
    if not hidden then
      if texture then part:setTexture(texture) end
      love.graphics.draw(part)
    end
  end
end
return Batch
