-- Scene 3's native NSBMD/NSBCA/NSBTA city miniatures. The camera is fixed;
-- the ROM's joint tracks move the world through it.
local Model=require('src.render.Gen4Model')
local Anim=require('src.import.Gen4Anim')
local C={};C.__index=C
local FLIP={1,0,0,0,0,-1,0,0,0,0,1,0,0,0,0,1}
function C.billboard(matrix,view,yOnly)
  -- City actors use full BB. A caller may decline the distinct BBY case.
  if yOnly then return matrix end
  local out={};for i=1,16 do out[i]=matrix[i] end
  local scales={}
  for col=0,2 do scales[col+1]=math.sqrt(matrix[col+1]^2+matrix[col+5]^2+matrix[col+9]^2) end
  -- Preserve local screen roll while replacing the view-space orientation.
  local x=view[1]*matrix[2]+view[2]*matrix[6]+view[3]*matrix[10]
  local y=view[5]*matrix[2]+view[6]*matrix[6]+view[7]*matrix[10]
  local length=math.sqrt(x*x+y*y)
  local sin,cos=0,1
  if length>1e-8 then sin,cos=-x/length,y/length end
  for row=0,2 do
    local right,up,back=view[row+1],view[row+5],view[row+9]
    out[row*4+1]=(right*cos+up*sin)*scales[1]
    out[row*4+2]=(-right*sin+up*cos)*scales[2]
    out[row*4+3]=back*scales[3]
  end
  return out
end
function C.new(data)
  local set=((data.gen4_models or {}).sets or {}).hgssOpening or {}
  return setmetatable({set=set,actors={}},C)
end
function C:actor(name)
  if self.actors[name]~=nil then return self.actors[name] end
  local a={tracks={},materials={}}
  for _,r in ipairs(self.set.models or {}) do if r.name==name then a.model=Model.new(r) end end
  for _,r in ipairs(self.set.animations or {}) do if r.name==name then
    if r.tracks then a.frames=r.frames;for _,t in ipairs(r.tracks) do a.tracks[t.index]=t end
    else a.materials[#a.materials+1]=r end
  end end
  self.actors[name]=a.model and a or false
  return self.actors[name]
end
function C:draw(name,tick)
  local actor=self:actor(name);if not actor then return end
  local g=love.graphics
  if not self.colour then self.colour,self.depth=Model.newTarget(256,192) end
  if not (self.colour and self.depth) then return end
  local old={g.getCanvas()}
  g.push('all');g.setCanvas({self.colour,depthstencil=self.depth});g.clear(0,0,0,1,true,true)
  g.origin();g.setScissor();g.setColor(1,1,1,1)
  local angle=0xD602/65536*math.pi*2;local distance=410.922119140625
  local eye={0,-math.sin(angle)*distance,96+math.cos(angle)*distance}
  local view=Model.lookAt(eye,{0,0,96})
  local vp=Model.multiply(FLIP,Model.multiply(Model.perspective(0x981/65536*math.pi*4,4/3,150,900),view))
  local frame=math.min(tick,math.max(0,(actor.frames or 1)-1))
  local pose=actor.model:posed(function(node)
    local track=actor.tracks[node];return track and Anim.unpackFrame(track.matrices,frame) or nil
  end,function(matrix,yOnly) return C.billboard(matrix,view,yOnly) end)
  local fog=Model.depthFog;Model.depthFog=nil
  actor.model:draw(vp,pose,require('src.render.Gen4TexAnim').materials(actor.materials,frame))
  Model.depthFog=fog
  g.setCanvas(old[1] and old or nil);g.pop()
  g.setColor(1,1,1,1);g.draw(self.colour,0,0)
end
return C
