-- BW's new-game dialogue and choices. Upper-screen controls stay on the
-- primary panel in single-screen mode; NamingScreen handles its keyboard.
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local Screens=require('src.ui.Screens')
local S=require('src.ui.SecondScreen')
local Intro={};Intro.__index=Intro;Intro.isOpaque=true
function Intro:uiSize() return 256,192 end
function Intro:wantsFillScale() return true end
function Intro:wantsEdgeBleed() return false end
function Intro:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end
function Intro.new(game,onDone)
  return setmetatable({game=game,onDone=onDone,art=game.data.gen5_juniper_art or {},
    gender='boy',choice=1,frame=0,cache={},phase='welcome'},Intro)
end
function Intro:text(id)
  -- one value: gsub's count would ride into {text(19),text(20)}
  return (((self.art.text or {})[id] or ''):gsub('{VAR1}',function()
    return (self.game.save.player or {}).name or ''
  end):gsub('\r\n','\n'):gsub('\r','\n'))
end
function Intro:say(id,phase)
  self.message=id;self.phase=phase;self.pages={};self.page=1;self.choice=1
  -- Blank lines are cartridge page breaks, not vertical spacing.
  for paragraph in (self:text(id)..'\n\n'):gmatch('(.-)\n\n+') do
    if paragraph~='' then
      local lines={}
      for line in (paragraph..'\n'):gmatch('([^\n]*)\n') do
        local row=''
        for word in line:gmatch('%S+') do
          local nextRow=row=='' and word or row..' '..word
          if row~='' and Font.width(nextRow)>232 then lines[#lines+1]=row;row=word
          else row=nextRow end
        end
        lines[#lines+1]=row
      end
      for first=1,#lines,2 do
        self.pages[#self.pages+1]=table.concat(lines,'\n',first,math.min(first+1,#lines))
      end
    end
  end
  if #self.pages==0 then self.pages[1]='' end
end
function Intro:enter()
  self:say(6,'welcome')
  -- SEQ_BGM_STARTING, Juniper's "Introduction" (Gen5Audio special.professor)
  local song=((self.game.data.audio or {}).special or {}).professor
  if song then require('src.core.Music').play(self.game.data,song) end
end
function Intro:finish()
  if self.done then return end
  self.done=true;self.game.stack:pop()
  if type(self.onDone)=='function' then self.onDone() end
end
function Intro:askName()
  local player=self.game.save.player
  player.gender=self.gender
  local avatar=self.game.overworld and self.game.overworld.player
  if avatar and avatar.refreshForm then avatar:refreshForm(self.game.data) end
  Screens.push(self.game,'NamingScreen',{kind='player',female=self.gender=='girl',
    title=self.art.namePrompt,maxLen=7,
    onDone=function(name)
      player.name=name;self:say(self.gender=='girl' and 18 or 17,'confirmName')
    end})
end
function Intro:choices()
  if self.phase=='gender' then return {'boy','girl'} end
  if (self.phase=='confirmGender' or self.phase=='confirmName') and self.page==#self.pages then
    return {self:text(19),self:text(20)}
  end
end
function Intro:advance()
  if self.done then return end
  if self.page<#self.pages then self.page=self.page+1;return end
  local p=self.phase
  if p=='welcome' then self:say(7,'professor')
  elseif p=='professor' then self.phase='release';self.elapsed=0
  elseif p=='inhabited' then self:say(9,'pokemon')
  elseif p=='pokemon' then self:say(10,'yourself')
  elseif p=='yourself' then self:say(11,'gender')
  elseif p=='gender' then
    self.gender=self.choice==1 and 'boy' or 'girl'
    self:say(self.gender=='boy' and 12 or 13,'confirmGender')
  elseif p=='confirmGender' then
    if self.choice==2 then self:say(11,'gender') else self:say(16,'name') end
  elseif p=='name' then self:askName()
  elseif p=='confirmName' then
    if self.choice==2 then self:say(16,'name') else self:say(21,'wonderful') end
  elseif p=='wonderful' then self:say(22,'friends')
  elseif p=='friends' then self:say(23,'cheren')
  elseif p=='cheren' then self:say(24,'bianca')
  elseif p=='bianca' then self:say(25,'gift')
  elseif p=='gift' then self:say(26,'journey')
  elseif p=='journey' then self.phase='shrink';self.elapsed=0 end
end
function Intro:update(dt)
  local speed=self.game.logicSpeed and self.game:logicSpeed() or 1
  local ticks=(dt or 1/60)*60/math.max(1,speed)
  self.frame=self.frame+ticks
  local i=self.game.input;local tap=self.tap;self.tap=nil
  if self.phase=='release' or self.phase=='shrink' then
    local previous=self.elapsed;self.elapsed=self.elapsed+ticks
    if self.phase=='release' then
      if previous<110 and self.elapsed>=110 then
        pcall(require('src.core.Sound').playCry,self.game.data,572)
      end
      if self.elapsed>=160 then self:say(8,'inhabited') end
    elseif self.elapsed>=90 then self:finish() end
    return
  end
  local choices=self:choices()
  if choices then
    if i:wasPressed('left') or i:wasPressed('up') then self.choice=1 end
    if i:wasPressed('right') or i:wasPressed('down') then self.choice=2 end
  end
  if tap or i:wasPressed('a') then self:advance()
  elseif i:wasPressed('b') and choices and self.phase~='gender' then
    self.choice=2;self:advance()
  end
end
function Intro:picture(rec)
  if type(rec)=='string' then rec=self.art[rec] end
  if not rec then return end
  local path=type(rec)=='table' and rec.path or rec
  if self.cache[path]==nil then self.cache[path]=Assets.image(path) or false end
  return self.cache[path]
end
function Intro:image(rec,x,y,sx,sy)
  local pic=self:picture(rec)
  if pic then love.graphics.setColor(1,1,1,1);love.graphics.draw(pic,x or 0,y or 0,0,sx or 1,sy or sx or 1) end
end
function Intro:juniper(sequence,clock)
  local anim=(self.art.juniper or {})[sequence]
  if not anim then return end
  local duration=0
  for _,f in ipairs(anim.play) do duration=duration+f.dur end
  if duration==0 then return end
  local t=sequence==2 and math.min(clock,duration-1) or clock%duration
  for _,f in ipairs(anim.play) do
    t=t-f.dur
    if t<0 then
      self:image(anim.frames[f.frame],128-anim.origin[1],79-anim.origin[2]);return
    end
  end
end
function Intro:portrait(gender,x,dim)
  self:image(gender..(dim and '_dim' or '_portrait'),x,0)
end
function Intro:band(gender,x,w)
  local rec=self.art[gender=='boy' and 'blue' or 'pink']
  local pic=self:picture(rec)
  if not pic then return end
  local g=love.graphics
  g.setColor(1,1,1,1)
  for xx=x,x+w-1,32 do for yy=30,99,32 do
    local q=g.newQuad(0,0,math.min(32,x+w-xx),math.min(32,100-yy),32,32)
    g.draw(pic,q,xx,yy)
  end end
end
function Intro:panel(sub)
  local g=love.graphics
  g.setColor(38/255,38/255,38/255,1);g.rectangle('fill',0,0,256,192)
  self:image(sub and 'bottom' or 'background',0,0)
  if sub then return end
  local p=self.phase
  if p=='gender' then
    self:band('boy',0,128);self:band('girl',128,128)
    self:portrait('boy',0,self.choice~=1);self:portrait('girl',128,self.choice~=2)
  elseif p=='confirmGender' or p=='name' or p=='confirmName' or p=='wonderful' then
    self:band(self.gender,0,256);self:portrait(self.gender,64)
  elseif p=='cheren' or p=='bianca' then
    local rec=self.art[p]
    if rec then self:image(rec,128-rec.width/2,140-rec.height) end
  elseif p=='shrink' then
    local rec=self.art[self.gender]
    if rec then
      local scale=math.max(0,1-self.elapsed/90)
      self:image(rec,128-rec.width*scale/2,140-rec.height*scale,scale)
    end
    return
  else
    self:juniper(p=='release' and 2 or 0,p=='release' and self.elapsed or self.frame)
    if p=='inhabited' or p=='pokemon' or (p=='release' and self.elapsed>=110) then self:image('minccino',56,78,0.875) end
  end
  if p=='release' then return end
  self:image('message_frame',0,144)
  local ink=self.art.ink or {}
  local function rgb(c) return c and {c[1]/255,c[2]/255,c[3]/255} end
  Font.pushStyle({text=rgb(ink.text) or {0.3,0.3,0.3},shadow=rgb(ink.shadow) or {0.65,0.65,0.65}})
  local y=152
  for row in ((self.pages[self.page] or '')..'\n'):gmatch('([^\n]*)\n') do Font.draw(row,12,y);y=y+16 end
  local choices=self:choices()
  if choices and p~='gender' then
    g.setColor(1,1,1,1);g.rectangle('fill',170,98,84,42)
    g.setColor(0,0,0,1);g.rectangle('line',170,98,84,42)
    for n,text in ipairs(choices) do Font.draw(text,192,104+(n-1)*16) end
    g.setColor(0.3,0.3,0.3,1);local cy=109+(self.choice-1)*16
    g.polygon('fill',179,cy,184,cy+3,179,cy+6)
  end
  Font.popStyle()
end
function Intro:draw()
  self:panel(false)
  if S.separate(self.game) then
    S.draw(self.game,function() self:panel(true) end);self.game.secondScreenPointerOwner=self
  end
end
function Intro:touchpressed(_,x,y)
  if S.toLocal(self.game,x,y) then return false end -- blank lower panel
  local r=require('src.render.Renderer').uiPresentation
  if not r then return false end
  local px,py=(x-r.x)/r.scaleX,(y-r.y)/r.scaleY
  if px<0 or py<0 or px>=256 or py>=192 then return false end
  local choices=self:choices()
  if self.phase=='gender' then self.choice=px<128 and 1 or 2
  elseif choices then
    if px<170 or py<98 or py>=140 then return false end
    self.choice=py<120 and 1 or 2
  end
  self.tap=true;return true
end
return Intro
