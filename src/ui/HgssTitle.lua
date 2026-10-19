-- HGSS title_screen.c's idle title: native logo above, animated legendary
-- below. L/SELECT exposes either full panel when using a single screen.
local Assets=require('src.render.Assets')
local Font=require('src.render.Font')
local Model=require('src.render.Gen4Model')
local Anim=require('src.import.Gen4Anim')
local SecondScreen=require('src.ui.SecondScreen')
local Screens=require('src.ui.Screens')
local Camera=require('src.ui.HgssTitleCamera')
local Title={};Title.__index=Title;Title.isOpaque=true
Title.IDLE_FRAMES=30+2340
Title.SINGLE_LOGO_SCALE=0.62
local FLIP={1,0,0,0,0,-1,0,0,0,0,1,0,0,0,0,1}
function Title:uiSize() return 256,192 end
function Title:wantsFillScale() return true end
function Title:wantsEdgeBleed() return false end
function Title.new(game,opts)
  opts=opts or {}
  local self=setmetatable({game=game,opts=opts,frame=0,bottom=false,cache={},actors={}},Title)
  self.version=require('src.core.GameVersion').get()
  self.camera=Camera.new(self.version)
  self.hg=self.version=='heartgold'
  self.art=game.data.gen4_hgss_title_art or {}
  local set=((game.data.gen4_models or {}).sets or {}).hgssTitle or {}
  local names=self.hg and {'houou_test','houou_efct'} or {'lugia01_10t','lugia_efct'}
  for _,name in ipairs(names) do
    local actor={tracks={},materials={}}
    for _,record in ipairs(set.models or {}) do if record.name==name then
      actor.model=Model.new(record);actor.images=record.patternImages
    end end
    for _,a in ipairs(set.animations or {}) do if a.name==name then
      if a.tracks then
        actor.frames=a.frames
        for _,t in ipairs(a.tracks) do actor.tracks[t.index]=t end
      else actor.materials[#actor.materials+1]=a end
    end end
    if actor.model then self.actors[#self.actors+1]=actor end
  end
  return self
end
function Title:enter()
  self.frame=0;self.nativeRemainder=0;self.opened=false;self.transition=nil;self.replaying=nil;self.tap=nil
  self.camera=Camera.new(self.version)
  local songs=(self.game.data.audio or {}).songs or {}
  if songs.SEQ_GS_POKEMON_THEME then require('src.core.Music').play(self.game.data,'SEQ_GS_POKEMON_THEME') end
end
function Title:resume() self.opened=false end
function Title:openMenu()
  if self.opened then return end
  self.opened=true
  Screens.push(self.game,'Gen4MainMenu',self.opts)
end
function Title:update(dt)
  -- Only the top state updates; reaching here with opened set means B
  -- popped the menu. StateStack does not dispatch a resume callback.
  if self.opened then self:resume() end
  local previous=self.frame
  local ticks=require('src.ui.HgssClock').step(self,self.game,dt)
  self.frame=self.frame+ticks
  if self.transition then
    self.tap=nil
    self.transition=self.transition+ticks
    if self.transition>=66 then
      self.transition=nil;self.replaying=true
      Screens.push(self.game,'HgssIntro',function() self:enter() end)
    end
    return
  end
  local input=self.game.input
  if input:wasPressed('l') or input:wasPressed('select') then self.bottom=not self.bottom end
  if self.frame>=30 and (self.tap or input:wasPressed('a') or input:wasPressed('start')) then self:openMenu() end
  if not self.opened then
    if self.frame>Title.IDLE_FRAMES then
      self.transition=0
      require('src.core.Music').dsFade(0,120)
    else
      for frame=previous+1,self.frame do if frame>30 then Camera.step(self.camera) end end
    end
  end
  self.tap=nil
end
function Title:picture(key,y,alpha)
  local rec=self.art[self.version..'_'..key]
  if not rec then return end
  if self.cache[rec.path]==nil then self.cache[rec.path]=Assets.image(rec.path) or false end
  local pic=self.cache[rec.path]
  if pic then love.graphics.setColor(1,1,1,alpha or 1);love.graphics.draw(pic,0,y or 0) end
end
function Title:scene()
  local g=love.graphics
  if not self.colour then
    self.colour=g.newCanvas(256,192);self.depth=g.newCanvas(256,192,{format='depth24'})
  end
  local old={g.getCanvas()}
  g.push('all');g.setCanvas({self.colour,depthstencil=self.depth});g.clear(0,0,0,0,true,true)
  g.origin();g.setScissor();g.setColor(1,1,1,1)
  local eye=self.camera.eye
  local vp=Model.multiply(FLIP,Model.multiply(Model.perspective(0xB60/65536*math.pi*4,256/192,1,4000),
    Model.lookAt(eye,{-2,124,-38})))
  local place={1,0,0,30,0,1,0,95,0,0,1,0,0,0,0,1}
  vp=Model.multiply(vp,place)
  local fog=Model.depthFog;Model.depthFog=nil
  for index,actor in ipairs(self.actors) do
    local frame=self.frame%math.max(1,actor.frames or 1)
    local pose=actor.model:posed(function(node)
      local t=actor.tracks[node];return t and Anim.unpackFrame(t.matrices,frame) or nil
    end)
    actor.model:draw(vp,pose,require('src.render.Gen4TexAnim').materials(actor.materials,self.frame,actor.images))
  end
  Model.depthFog=fog
  g.setCanvas(old[1] and old or nil);g.pop()
  return self.colour
end
function Title:panel(sub)
  local g=love.graphics;g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  if sub then
    local pic=self:scene();g.setColor(1,1,1,1);g.draw(pic,0,0)
    if self.frame>=30 and not self.transition and self.frame%45<30 then
      local text=(self.art.prompt or ''):gsub('{ALN_CENTER}','')
      Font.draw(text,math.floor((256-Font.width(text))/2),144)
    end
  else
    self:picture('background')
    local f=math.min(31,math.max(0,self.frame-3))
    self:picture('logo',-math.floor(f/2),f/31)
    self:picture('copyright')
  end
  if self.transition and self.transition>60 then
    g.setColor(0,0,0,math.min(1,(self.transition-60)/6));g.rectangle('fill',0,0,256,192)
  end
end
-- ONE SCREEN: both of the cartridge's at once -- the top's glowing ground, the
-- legendary's 3D scene from the bottom in front of it, then the logo, the
-- prompt and the copyright over both (L shows the bottom screen alone)
function Title:single()
  local g=love.graphics;g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  self:picture('background')
  local pic=self:scene();g.setColor(1,1,1,1);g.draw(pic,0,0)
  -- the logo smaller and near the top, so the legendary shows below it,
  -- shrunk through SmoothScale so its outline stays clean
  local f=math.min(31,math.max(0,self.frame-3))
  local rec=self.art[self.version..'_logo']
  if rec then
    if self.cache[rec.path]==nil then self.cache[rec.path]=Assets.image(rec.path) or false end
    local pic=self.cache[rec.path]
    if pic then
      local k=Title.SINGLE_LOGO_SCALE
      require('src.render.SmoothScale').draw(pic,(256-pic:getWidth()*k)/2,-math.floor(f/2)*k-14,k,f/31)
    end
  end
  if self.frame>=30 and not self.transition and self.frame%45<30 then
    local text=(self.art.prompt or ''):gsub('{ALN_CENTER}','')
    Font.draw(text,math.floor((256-Font.width(text))/2),164)
  end
  self:picture('copyright')
  if self.transition and self.transition>60 then
    g.setColor(0,0,0,math.min(1,(self.transition-60)/6));g.rectangle('fill',0,0,256,192)
  end
end
function Title:draw()
  local dual=SecondScreen.separate(self.game)
  if not dual and not self.bottom then self:single() return end
  self:panel(not dual and self.bottom)
  if dual then
    SecondScreen.draw(self.game,function() self:panel(true) end)
    self.game.secondScreenPointerOwner=self
  end
end
function Title:touchpressed() self.tap=true;return true end
return Title
