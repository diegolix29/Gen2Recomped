-- Cartridge Pokegear backgrounds, with both DS panels accessible in SWAP.
local Assets=require('src.render.Assets')
local Font=require('src.render.Font')
local SecondScreen=require('src.ui.SecondScreen')
local Gear={};Gear.__index=Gear;Gear.isOpaque=true
local PAGES={'map','phone','radio','config'}
function Gear:uiSize() return 256,192 end
function Gear:wantsFillScale() return true end
function Gear:wantsEdgeBleed() return false end
function Gear.new(game,opts)
  return setmetatable({game=game,onCancel=opts and opts.onCancel,page=2,
    skin=(tonumber((game.save.hgssPokegear or {}).skin) or 0)%6,cache={},bottom=false,index=1},Gear)
end
function Gear:canPage(page)
  local cards=(self.game.save.hgssPokegear or {}).cards or {}
  return page~=1 and page~=3 or cards[page==1 and 1 or 2]==true
end
function Gear:cycle(direction)
  repeat self.page=(self.page-1+direction)%#PAGES+1 until self:canPage(self.page)
end
function Gear:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end
function Gear:update()
  local input=self.game.input
  if input:wasPressed('b') then return self:close() end
  if input:wasPressed('left') then self:cycle(-1) end
  if input:wasPressed('right') then self:cycle(1) end
  if input:wasPressed('l') or input:wasPressed('select') then self.bottom=not self.bottom end
  if input:wasPressed('up') then self.index=math.max(1,self.index-1) end
  if input:wasPressed('down') then self.index=self.index+1 end
  if PAGES[self.page]=='config' and input:wasPressed('a') then
    self.skin=(self.skin+1)%6
    self.game.save.hgssPokegear=self.game.save.hgssPokegear or {}
    self.game.save.hgssPokegear.skin=self.skin
  end
end
function Gear:picture(key)
  local rec=(self.game.data.gen4_hgss_pokegear_art or {})[key..'_'..self.skin]
  if not rec then return end
  local path=type(rec)=='table' and rec.path or rec
  if self.cache[path]==nil then self.cache[path]=Assets.image(path) or false end
  if self.cache[path] then love.graphics.setColor(1,1,1,1);love.graphics.draw(self.cache[path],0,0) end
end
function Gear:panel(sub)
  local g=love.graphics;g.setColor(1,1,1,1);g.rectangle('fill',0,0,256,192)
  local page=PAGES[self.page]
  self:picture('frame_'..(sub and 'bottom' or 'top'))
  if page=='map' and not sub then self:picture('map_world') end
  self:picture(page..'_'..(sub and 'bottom' or 'top'))
  if page=='phone' and not sub then
    local book=(self.game.data.gen4_hgss_pokegear_art or {}).contacts or {}
    local numbers=((self.game.save.hgssPokegear or {}).numbers or {})
    local contacts={}
    for id,yes in pairs(numbers) do if yes and book[tonumber(id)] then contacts[#contacts+1]=tonumber(id) end end
    table.sort(contacts)
    self.index=math.min(self.index,math.max(1,#contacts))
    g.setColor(1,1,1,1);g.rectangle('fill',8,16,216,144)
    Font.pushStyle({text={0,0,0},shadow={.7,.7,.7}})
    local first=math.max(1,self.index-6)
    for i=first,math.min(#contacts,first+6) do
      local rec=book[contacts[i]]
      local text=require('src.import.Gen4Text').resolve(self.game.data,rec.bank,0,self.game)
      Font.draw((i==self.index and '> ' or '  ')..(text or rec.name or ''),12,20+(i-first)*20)
    end
    Font.popStyle()
  end
  if not sub then self:picture('frame_top') end
end
function Gear:draw()
  local dual=SecondScreen.separate(self.game)
  self:panel(not dual and self.bottom)
  if dual then SecondScreen.draw(self.game,function() self:panel(true) end) end
end
function Gear:touchpressed(id,x,y)
  local px,py=SecondScreen.toLocal(self.game,x,y)
  if not px then
    local rect=require('src.render.Renderer').uiPresentation
    if rect then px,py=(x-rect.x)/rect.scaleX,(y-rect.y)/rect.scaleY else px,py=x,y end
  end
  if px<0 or py<0 or px>=256 or py>=192 then return false end
  -- Hardware buttons also remain available on a single-screen device.
  if py>=160 then
    local slot=math.floor((px-8)/48)
    local pageBySlot={ [0]=4,[1]=3,[2]=1,[3]=2 }
    if slot>=4 then return self:close() end
    local page=pageBySlot[slot]
    if page and self:canPage(page) then self.page=page end
  end
  return true
end
return Gear
