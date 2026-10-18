-- Scene 4: the three native cell animations and SPL emitter groups. Each
-- attack waits for its live emitters/particles to finish, as the ROM does.
local Particles=require('src.battle.Gen4ParticleSystem')
local Timeline=require('src.ui.HgssOpeningTimeline')
local S={};S.__index=S
local NAMES={'chikorita','cyndaquil','totodile'}
local IDS={{6,7,8},{3,4,5},{0,1,2}}
function S.new(art)
  local seq=art.sequences and art.sequences.hands_sparkle and art.sequences.hands_sparkle[2]
  local length=0;for _,f in ipairs(seq and seq.frames or {}) do length=length+(f.duration or 1) end
  return setmetatable({art=art,frame=-1,starts={},systems={},sparkleLength=math.max(1,length)},S)
end
function S:spawn()
  self.systems={}
  for _,id in ipairs(IDS[self.stage]) do
    local source=(self.art.emitters or {})[id+1]
    if source then
      local e={};for k,v in pairs(source) do e[k]=v end
      e.fields={};for k,v in pairs(source.fields or {}) do e.fields[k]=v end
      -- SPLEmitterCB overrides the resource's initial position on creation.
      e.fields.basePos={0,0,1/64}
      local system=Particles.fromEmitters({e})
      if system then self.systems[#self.systems+1]=system:start(77+id) end
    end
  end
end
function S:step(tick)
  if self.done then return end
  for f=self.frame+1,tick do
    if f==56 then self.stage=1;self.starts[1]=f end
    if self.stage and not self.fadeStart then
      local start=self.starts[self.stage]
      if f==start+1 then self:spawn() end
      if f>start then
        local active=false
        for _,system in ipairs(self.systems) do active=system:update() or active end
        -- A legacy cache lacking SPA data can still complete the opening.
        if #self.systems==0 then active=f-start<76 end
        if not active then
          if self.stage<3 then self.stage=self.stage+1;self.starts[self.stage]=f
          else self.fadeStart=f end
        end
      end
    end
    if self.fadeStart and f>=self.fadeStart+26 then
      self.sparkleStart=self.fadeStart+26
      if f>=self.sparkleStart+self.sparkleLength then self.done=true;self.doneFrame=f end
    end
    self.frame=f
    if self.done then break end
  end
end
function S:particles(intro)
  local g=love.graphics
  for _,system in ipairs(self.systems) do
    system:draw(128,96,function(texture,x,y,sx,sy,alpha,rotation,colour)
      local image=intro:image('opening_particle_'..texture);if not image then return end
      local w,h=image:getDimensions();local c=colour or {255,255,255}
      g.setColor(c[1]/255,c[2]/255,c[3]/255,alpha)
      g.draw(image,x,y,rotation,sx*32/w,sy*32/h,w/2,h/2)
    end)
  end
end
function S:draw(intro,sub,tick)
  local g=love.graphics
  local mainBottom=self.stage~=2
  local main=sub==mainBottom
  if self.sparkleStart then
    if not sub then intro:actor('hands_sparkle',2,tick-self.sparkleStart,128,96) end
    return
  end
  intro:background('starter_bg_'..(main and (mainBottom and 56 or 55) or (mainBottom and 55 or 56)))
  if tick>=10 and tick<56 then
    local slide=Timeline.clamp((tick-10)/10,0,1)+Timeline.clamp((tick-46)/10,0,1)
    intro:background('starter_bg_'..(sub and 58 or 57),(sub and 192 or -192)*(1-slide),0)
    intro:actor('hands_sparkle',sub and 1 or 0,tick-10,128,96)
  end
  if main then
    for i,start in ipairs(self.starts) do intro:actor(NAMES[i],0,tick-start,128,96) end
    self:particles(intro)
  end
  local fade=self.fadeStart and Timeline.clamp((tick-self.fadeStart)/26,0,1) or math.max(0,1-tick/10)
  if fade>0 then g.setColor(0,0,0,fade);g.rectangle('fill',0,0,256,192) end
end
return S
