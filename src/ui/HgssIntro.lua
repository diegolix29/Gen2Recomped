-- The five HGSS opening scenes, using their own resources throughout.
local Assets=require('src.render.Assets')
local SS=require('src.ui.SecondScreen')
local Timeline=require('src.ui.HgssOpeningTimeline')
local Intro={};Intro.__index=Intro;Intro.isOpaque=true
function Intro:uiSize() return 256,192 end
function Intro:wantsFillScale() return true end
function Intro:wantsEdgeBleed() return false end
function Intro.new(game,onDone)
  return setmetatable({game=game,onDone=onDone,frame=0,cache={},bottom=false,
    art=game.data.gen4_hgss_boot_art or {}},Intro)
end
function Intro:enter()
  local music=require('src.core.Music');music.stop()
  if ((self.game.data.audio or {}).songs or {}).SEQ_GS_TITLE then
    music.play(self.game.data,'SEQ_GS_TITLE')
  end
end
function Intro:finish()
  if self.done then return end
  self.done=true;self.game.stack:pop()
  if self.onDone then self.onDone() end
end
function Intro:update(dt)
  local previous=self.frame
  self.frame=self.frame+require('src.ui.HgssClock').step(self,self.game,dt)
  local function crossed(frame) return previous<frame and self.frame>=frame end
  -- The Game Freak credit is on the lower panel; its other panel is black.
  -- Bring the credit forward automatically on single-screen layouts.
  if crossed(110) then self.bottom=true end
  if crossed(Timeline.SCENE2) then self.bottom=false end
  if crossed(Timeline.SCENE3) then self.bottom=false end
  if crossed(Timeline.SCENE3+require('src.ui.HgssOpeningMontage').CITIES_END) then self.bottom=true end
  if self.art.scene4 and self.frame>=Timeline.SCENE4 then
    if not self.starters then self.starters=require('src.ui.HgssOpeningStarters').new(self.art) end
    self.starters:step(self.frame-Timeline.SCENE4)
    if self.starters.done and not self.finalStart then self.finalStart=Timeline.SCENE4+self.starters.doneFrame end
    if self.starters.stage and self.lastStarter~=self.starters.stage then
      self.lastStarter=self.starters.stage;self.bottom=self.lastStarter~=2
    end
    if self.starters.sparkleStart and not self.sparkleShown then self.sparkleShown=true;self.bottom=false end
  end
  local input=self.game.input
  if input:wasPressed('l') or input:wasPressed('select') then self.bottom=not self.bottom end
  local duration=self.art.sequences and Timeline.END or 220
  if self.art.scene4 then duration=self.finalStart and self.finalStart+Timeline.FINAL_LENGTH or math.huge end
  if not self.art.studio_top or self.frame>=duration
     or (self.frame>=110 and (self.tap or input:wasPressed('a') or input:wasPressed('start') or input:wasPressed('b'))) then
    self:finish()
  end
  self.tap=nil
end
function Intro:final(sub,tick)
  local version=require('src.core.GameVersion').get()
  local motion=Timeline.clamp((tick-36)/73,0,1)
  local scroll=(version=='heartgold' and -64 or 64)*motion
  if sub then
    self:background('final_bottom_back',0,160+scroll)
    self:background('final_bottom_front',0,-64*motion)
  else
    self:background('final_top_back',0,160+scroll)
    self:background('final_top_front',0,scroll)
  end
  local g=love.graphics
  local black=1-Timeline.clamp((tick-(sub and 0 or 18))/18,0,1)
  if black>0 then g.setColor(0,0,0,black);g.rectangle('fill',0,0,256,192) end
  local white=Timeline.clamp((tick-56)/50,0,1)
  if white>0 then g.setColor(1,1,1,white);g.rectangle('fill',0,0,256,192) end
end
function Intro:image(key)
  local rec=self.art[key];if not rec then return end
  if self.cache[rec.path]==nil then self.cache[rec.path]=Assets.image(rec.path) or false end
  return self.cache[rec.path],rec
end
function Intro:picture(key,x,y,alpha)
  local pic=self:image(key)
  if pic then love.graphics.setColor(1,1,1,alpha or 1);love.graphics.draw(pic,x or 0,y or 0) end
end
function Intro:background(key,scrollX,scrollY,alpha)
  local pic=self:image(key);if not pic then return end
  local w,h=pic:getDimensions()
  local x,y=-(math.floor(scrollX or 0)%w),-(math.floor(scrollY or 0)%h)
  love.graphics.setColor(1,1,1,alpha or 1)
  -- Text backgrounds wrap at their native 256/512-pixel dimensions.
  for xx=x,255,w do for yy=y,191,h do love.graphics.draw(pic,xx,yy) end end
end
function Intro:actor(name,sequence,tick,x,y)
  local f=Timeline.pose(self.art.sequences,name,sequence,tick);if not f then return end
  local pic,rec=self:image(name..'_'..f.cell);if not pic then return end
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(pic,x+(f.x or 0),y+(f.y or 0),f.rotation or 0,
    f.scaleX or 1,f.scaleY or 1,-(rec.originX or 0),-(rec.originY or 0))
end
function Intro:sky(sub,s)
  if sub then
    self:background('sky_bottom_3')
    self:background('sky_bottom_2',0,s.scroll2)
    self:actor('sky_actor',0,s.tick,128,96)
    self:background('sky_bottom_1',0,s.scroll1)
    if s.bird then self:actor('sky_actor',1,s.bird,128,96) end
    self:picture('studio_bottom',0,0,s.credit)
  else
    self:background('sky_top')
    self:picture('studio_top',0,0,s.credit)
  end
end
function Intro:trainers(sub,s)
  if sub then self:background('grass_bottom',0,s.tick*64)
  else
    self:background('grass_top',0,s.tick*64)
    self:background('trainers_back',s.pan,320-s.enter-s.dropBack)
    for i=0,5 do
      self:actor('trainers',i,0,(i<3 and 64 or 320)-s.pan,-96+s.enter+s.dropBack)
    end
    self:background('trainers_front',s.pan,192-s.enter-s.dropFront)
  end
  local timings={1,8,16,24,28,32,34,38,42,48}
  for i,start in ipairs(timings) do if s.tick>=start then
    self:actor('flowers',(i-1)%4,s.tick-start,128,sub and 0 or 192)
  end end
  local g=love.graphics
  if sub and s.bottomBlack>0 then
    g.setColor(0,0,0,s.bottomBlack);g.rectangle('fill',0,0,256,192)
  elseif not sub and s.wipe>0 then
    -- The source calls this a circle wipe, but its HBlank callback clips
    -- each scanline at 127 + y*cot(angle). Reproduce that edge directly.
    g.setColor(1,1,1,1)
    local angle=s.wipe*math.pi
    for y=0,191 do
      local edge=s.wipe>=1 and 0 or Timeline.clamp(math.floor(127+y*math.cos(angle)/math.sin(angle)),0,255)
      g.rectangle('fill',edge,y,256-edge,1)
    end
  end
end
function Intro:panel(sub)
  local g=love.graphics;g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  if self.art.scene4 and self.frame>=Timeline.SCENE4 then
    if self.finalStart then self:final(sub,self.frame-self.finalStart)
    elseif self.starters then self.starters:draw(self,sub,self.frame-Timeline.SCENE4) end
    return
  end
  if self.art.sequences and self.frame>=Timeline.SKY then
    local s=Timeline.at(self.frame)
    if s.scene=='sky' then self:sky(sub,s)
    elseif s.scene=='montage' then require('src.ui.HgssOpeningMontageView').draw(self,sub,s)
    else self:trainers(sub,s) end
    if s.white and s.white>0 then g.setColor(1,1,1,s.white);g.rectangle('fill',0,0,256,192) end
    return
  end
  local key,alpha
  if self.frame<90 then key='copyright';alpha=self.frame<30 and 1 or (90-self.frame)/60
  elseif self.frame>=110 then key='studio';alpha=1 end
  if key then self:picture(key..(sub and '_bottom' or '_top'),0,0,alpha) end
end
function Intro:draw()
  local dual=SS.separate(self.game)
  self:panel(not dual and self.bottom)
  if dual then
    SS.draw(self.game,function() self:panel(true) end)
    self.game.secondScreenPointerOwner=self
  end
end
function Intro:touchpressed() self.tap=true;return true end
return Intro
