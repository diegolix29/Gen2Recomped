-- Shared immutable GPU hulls. Each map owns references to its template
-- variants; the last map releasing a variant releases its GPU allocation.
local V=...
local Budget=V.require("BuildBudget")
local Mat4=V.require("Mat4")
local H={}
local Bounds=V.require("MeshBounds")
local State=V.require("ShaderState")
local templates=setmetatable({}, {__mode="k"})
function H.new()
 local batch={stamps={},owned={},bytes=0}
 function batch:add(quads,mx,my,mz)
  local variants=templates[quads]
  if not variants then variants={};templates[quads]=variants end
  local template=variants[my]
  if not template then
   local mesh=V.require("ChunkMesher").hullTemplate(quads,my)
   assert(mesh,"shared hull template upload failed")
   Budget.disown(mesh)
   template={mesh=mesh,refs=0,variants=variants,height=my}
   variants[my]=template
  end
  if not self.owned[template] then
   template.refs=template.refs+1;self.owned[template]=true
   self.bytes=self.bytes+template.mesh:getVertexCount()*48
  end
  self.stamps[#self.stamps+1]={mesh=template.mesh,pose=Mat4.translate(mx,0,mz),x=mx,z=mz}
 end
 function batch:finish()
  if not love.graphics.drawInstanced then return end
  local groups,order={},{}
  for _,stamp in ipairs(self.stamps)do
   Budget.tick()
   local per=groups[stamp.mesh]
   if not per then per={};groups[stamp.mesh]=per end
   local key=math.floor(stamp.z/128)*65536+math.floor(stamp.x/128)
   local group=per[key]
   if not group then group={mesh=stamp.mesh,offsets={},bounds={math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge}};per[key]=group;order[#order+1]=group end
   group.offsets[#group.offsets+1]={stamp.x,0,stamp.z}
   for _,part in ipairs(stamp.mesh.parts)do
    local box=Bounds.get(part);local b=group.bounds
    b[1]=math.min(b[1],box[1]+stamp.x);b[2]=math.min(b[2],box[2]);b[3]=math.min(b[3],box[3]+stamp.z)
    b[4]=math.max(b[4],box[4]+stamp.x);b[5]=math.max(b[5],box[5]);b[6]=math.max(b[6],box[6]+stamp.z)
   end
  end
  self.groups=order
  for _,group in ipairs(order)do
   Budget.check()
   group.count=#group.offsets
   group.buffer=love.graphics.newMesh({{"StampOffset","float",3}},group.offsets,"points","static")
   group.offsets=nil;Bounds.set(group,group.bounds)
  end
 end
 function batch:release()
  for _,g in ipairs(self.groups or {})do if g.buffer then g.buffer:release()end;Budget.check() end
  self.groups=nil
  for template in pairs(self.owned)do
   template.refs=template.refs-1
   if template.refs==0 then
    template.variants[template.height]=nil;template.mesh:release()
   end
   Budget.check()
  end
  self.owned={};self.stamps={};self.bytes=0
 end
 return Budget.own(batch)
end
function H.draw(mesh,model,sunModel,draw)
 for _,stamp in ipairs(mesh.stamps or {})do
  local pose=model and Mat4.mul(model,stamp.pose) or stamp.pose
  local sun=sunModel and Mat4.mul(sunModel,stamp.pose) or pose
  draw(stamp.mesh,pose,sun)
 end
end
function H.instanced(mesh,texture,vp,model,curve,cx,cz,source,shader)
 local groups=mesh.hullOwner and mesh.hullOwner.groups
 if not groups or mesh.hullOwner.instanceFailed or not shader or not love.graphics.drawInstanced then return false end
 State.copy(source,shader)
 love.graphics.setShader(shader)
 local ok,err=pcall(function()
  for _,group in ipairs(groups)do
   local hidden=curve and curve>0 and Bounds.hiddenCurved(group,vp,model,curve,cx or 0,cz or 0)
    or (not (curve and curve>0) and Bounds.hidden(group,vp and model and Mat4.mul(vp,model) or vp))
   if not hidden then
    for _,part in ipairs(group.mesh.parts)do
     part:attachAttribute("StampOffset",group.buffer,"perinstance")
     if texture then part:setTexture(texture) end
     love.graphics.drawInstanced(part,group.count)
    end
   end
  end
 end)
 love.graphics.setShader(source)
 if not ok then
  -- A driver may advertise instancing and still reject an attribute bind.
  -- Retain the templates and use ordinary translated draws on later frames.
  mesh.hullOwner.instanceFailed=true
  return false
 end
 return true
end

return H
