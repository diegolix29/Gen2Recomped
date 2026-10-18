-- Native BW main-menu window art and save summary. Network applications
-- remain unported; OPTION and EXIT GAME are launcher additions.
local Base=require('src.ui.Gen4MainMenu')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local S=require('src.ui.SecondScreen')
local Menu={};Menu.__index=Menu;Menu.isOpaque=true
-- Native menu: BLDCNT=0x0844 (BG2 over BG3), BLDALPHA=0x0310.
-- A frame adds 3/16 of the backdrop without reducing its own intensity.
-- Quantize before mixing, as the DS does; ordinary alpha blending makes
-- White's frames too dark and loses the red tint over the Poké Ball.
local blendShader
local function frameShader()
  if blendShader~=nil then return blendShader or nil end
  local ok,made=pcall(love.graphics.newShader,[[
    extern Image menuBackdrop;
    extern vec2 frameOrigin;
    extern vec2 frameSize;
    vec4 effect(vec4 color,Image image,vec2 uv,vec2 screen) {
      vec4 pixel=Texel(image,uv);
      vec3 source=floor(pixel.rgb*31.0+0.5);
      vec3 back=floor(Texel(menuBackdrop,(frameOrigin+uv*frameSize)/vec2(256.0,192.0)).rgb*31.0+0.5);
      return vec4(min(vec3(31.0),source+floor(back*3.0/16.0))/31.0,pixel.a)*color;
    }
  ]])
  blendShader=ok and made or false
  return blendShader or nil
end
Menu.uiSize=Base.uiSize;Menu.wantsFillScale=Base.wantsFillScale
Menu.wantsEdgeBleed=Base.wantsEdgeBleed;Menu.sgbPalettes=Base.sgbPalettes
Menu.choose=Base.choose;Menu.close=Base.close;Menu.value=Base.value
Menu.hasPokedex=Base.hasPokedex;Menu.loadSummary=Base.loadSummary
function Menu.new(game,opts)
  local self=Base.new(game,opts)
  setmetatable(self,Menu)
  self.art=game.data.gen5_main_menu_art or {};self.images={};self.t=0
  for _,row in ipairs(self.items) do
    if row.key=='continue' then row.label=(self.art.text or {})[0] or row.label
    elseif row.key=='newGame' then row.label=(self.art.text or {})[1] or row.label end
  end
  return self
end
function Menu:rects()
  local out={};local y=16
  for i,row in ipairs(self.items) do
    local large=row.key=='continue'
    local h=large and 112 or 24
    out[i]={x=large and 24 or 32,y=y,w=large and 208 or 192,h=h,large=large}
    y=y+h
  end
  return out,y
end
function Menu:targetScroll()
  local r=self:rects()[self.index]
  if not r then return end
  local current=self.scrollTarget or 0
  if r.y<current then current=r.y end
  if r.y+r.h>current+192 then current=r.y+r.h-192 end
  self.scrollTarget=math.max(0,current)
end
Menu.scrollStep=Base.scrollStep
function Menu:update(dt)
  self.t=self.t+(dt or 1/60);self:scrollStep(dt or 1/60)
  local input=self.game.input
  if input:wasPressed('up') then self.index=math.max(1,self.index-1);self:targetScroll()
  elseif input:wasPressed('down') then self.index=math.min(#self.items,self.index+1);self:targetScroll()
  elseif input:wasPressed('a') or input:wasPressed('start') then self:choose()
  elseif input:wasPressed('b') then self:close() end
end
function Menu:picture(key,x,y,alpha)
  local rec=self.art[key];if not rec then return end
  if self.images[rec.path]==nil then self.images[rec.path]=Assets.image(rec.path) or false end
  local pic=self.images[rec.path]
  if pic then
    local g=love.graphics;local old=g.getShader()
    local bg=self.art.background and self.images[self.art.background.path]
    local shader=key~='background' and bg and frameShader()
    if shader then
      shader:send('menuBackdrop',bg)
      shader:send('frameOrigin',{x,y-(self.scrollPos or 0)})
      shader:send('frameSize',{rec.width,rec.height})
      g.setShader(shader)
    end
    g.setColor(1,1,1,alpha or 1);g.draw(pic,x,y)
    if shader then g.setShader(old) end
  end
end
function Menu:summary(r)
  local save=self.save or {};local words=self.art.text or {}
  local function value(id,values)
    return (words[id] or ''):gsub('{CMD %x+ (%d+)}',function(slot)
      return tostring(values[tonumber(slot)+1] or '')
    end)
  end
  local seconds=require('src.core.SaveData').playSeconds(save) or 0
  Font.draw(tostring((save.player or {}).name or ''),r.x+16,r.y+25)
  Font.draw(value(9,{math.floor(seconds/3600),('%02d'):format(math.floor(seconds/60)%60)}),r.x+16,r.y+43)
  if self:hasPokedex() then Font.draw(value(10,{self:value('ownedCount')}),r.x+16,r.y+61) end
  Font.draw(value(11,{self:value('badgeCount')}),r.x+16,r.y+79)
end
function Menu:drawMenu()
  local g=love.graphics
  g.setColor(0,0,0,1);g.rectangle('fill',0,0,256,192)
  self:picture('background',0,0)
  g.push('all');g.translate(0,-(self.scrollPos or 0))
  local ink=self.art.ink or {text={238,238,238},shadow={139,139,139}}
  local function rgb(c) return {c[1]/255,c[2]/255,c[3]/255} end
  Font.pushStyle({text=rgb(ink.text),shadow=rgb(ink.shadow)})
  local rects=self:rects()
  for i,row in ipairs(self.items) do
    local r=rects[i];local prefix=r.large and 'large_' or 'small_'
    if i==self.index then
      self:picture(prefix..'focus_low',r.x,r.y)
      -- The source palette supplies both pulse endpoints. Exact native
      -- phase timing remains separate from the verified window geometry.
      self:picture(prefix..'focus_high',r.x,r.y,(1-math.cos(self.t*math.pi*2))/2)
    else self:picture(prefix..'idle',r.x,r.y) end
    Font.draw(row.label,r.x+(r.large and 14 or 6),r.y+3)
    if r.large then self:summary(r) end
  end
  Font.popStyle();g.pop()
end
function Menu:draw()
  self:drawMenu()
  if S.separate(self.game) then
    S.draw(self.game,function()
      love.graphics.setColor(0,0,0,1);love.graphics.rectangle('fill',0,0,256,192)
    end)
    self.game.secondScreenPointerOwner=self
  end
end
function Menu:touchpressed(id,x,y)
  if self.game.secondScreenInjecting then return false end
  if S.combined(self.game) and S.toLocal(self.game,x,y) then return false end
  local r=require('src.render.Renderer').uiPresentation
  if r then x,y=(x-r.x)/r.scaleX,(y-r.y)/r.scaleY end
  if x<0 or x>=256 or y<0 or y>=192 then return false end
  y=y+(self.scrollPos or 0)
  for i,box in ipairs(self:rects()) do
    if x>=box.x and x<box.x+box.w and y>=box.y and y<box.y+box.h then
      self.index=i;self:targetScroll();self:choose();return true
    end
  end
  return false
end
return Menu
