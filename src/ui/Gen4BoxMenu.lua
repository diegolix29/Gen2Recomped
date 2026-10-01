-- Platinum storage uses the shared safe transfer operations with a DS surface.
local Base=require('src.ui.Gen3BoxMenu')
local Boxes=require('src.pokemon.Boxes')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local Screens=require('src.ui.Screens')
local Bag=require('src.inventory.Bag')
local PC={};PC.__index=PC;setmetatable(PC,{__index=Base});PC.isOpaque=true
function PC:uiSize() return 256,192 end
function PC:wantsFillScale() return true end
function PC:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end
function PC.new(game,opts)
 local self=Base.new(game,opts);setmetatable(self,PC);self.images={};self.icons={};self.message='';return self
end
function PC:iconFor(mon) return require('src.ui.Gen4PartyMenu').iconFor(self,mon) end
function PC:img(key)
 local rec=(((self.game.data.gen4_graphics or {}).screens) or {})[key]
 local path=type(rec)=='table' and rec.path or rec
 if not path then return end
 if self.images[path]==nil then local ok,img=pcall(Assets.image,path);self.images[path]=ok and img or false end
 return self.images[path] or nil
end
function PC:clampCursor() self.row=math.max(0,math.min(5,self.row));self.col=math.max(1,math.min(6,self.col)) end
function PC:changeBox(delta)
 self.game.save.currentBox=((self.game.save.currentBox or 1)-1+delta)%Boxes.count()+1
end
function PC:rememberOrigin()
 if self.held and self.held.from and not self.held.box then self.held.box=self.game.save.currentBox end
end
function PC:returnHeld()
 local held=self.held
 if not held then return false end
 if held.from then self.game.save.boxes[held.box or self.game.save.currentBox][held.from]=held.mon;self.held=nil;return true end
 return Base.returnHeld(self)
end
function PC:placeDisplaced(held,mon)
 if held.from then self.game.save.boxes[held.box or self.game.save.currentBox][held.from]=mon
 else Base.placeDisplaced(self,held,mon) end
end
function PC:carry(slot)
 local held=self.held
 if held then
  local target=self:box()[slot];self:box()[slot]=held.mon;self.held=nil
  if target then self:placeDisplaced(held,target) end
 else Base.carry(self,slot);self:rememberOrigin() end
end
function PC:withdraw(slot)
 local mon=self:box()[slot];if not mon then return end
 if #self.game.save.party>=6 then self.message='Your party is full.';return end
 self:box()[slot]=nil;table.insert(self.game.save.party,mon)
end
local function usable(mon) return mon and not (mon.egg or mon.isEgg) and (mon.hp==nil or mon.hp>0) end
function PC:canRemoveParty(index,replacement)
 if usable(replacement) then return true end
 for i,mon in ipairs(self.game.save.party) do if i~=index and usable(mon) then return true end end
 return false
end
function PC:carryFromParty(index)
 if self.game.save.party[index] and not self:canRemoveParty(index,self.held and self.held.mon) then
  self.message='Keep a usable Pokemon in your party.';return
 end
 return Base.carryFromParty(self,index)
end
function PC:choose()
 if self.row==0 and not self.partyOpen then self.menu={'BOX NAME','WALLPAPER','PARTY','CANCEL'};self.action=1;return end
 if self.partyOpen then
  if self.partyIndex==7 then self.partyOpen=nil;return end
  if self.opts.mode=='deposit' then
   local party=self.game.save.party;local slot=Boxes.firstFree(self:box())
   if #party<=1 or not self:canRemoveParty(self.partyIndex) then self.message='Keep a usable Pokemon in your party.'
   elseif not slot then self.message='This Box is full.'
   elseif party[self.partyIndex] then self:box()[slot]=table.remove(party,self.partyIndex) end
  else self:carryFromParty(self.partyIndex);self:rememberOrigin() end
  return
 end
 local mon,slot=self:selected()
 if self.held then self:carry(slot);return end
 if not mon then return end
 if self.opts.mode=='withdraw' then return self:withdraw(slot) end
 self.menu=self.opts.mode=='items' and {'TAKE ITEM','GIVE ITEM','CANCEL'}
  or {'MOVE','SUMMARY','WITHDRAW','MARK','RELEASE','CANCEL'};self.action=1
end
function PC:runAction(action)
 self.menu=nil;local mon,slot=self:selected()
 if action=='MOVE' then self:carry(slot)
 elseif action=='SUMMARY' then Screens.push(self.game,'SummaryMenu',mon)
 elseif action=='WITHDRAW' then self:withdraw(slot)
 elseif action=='RELEASE' then self.menu={'CONFIRM RELEASE','CANCEL'};self.action=2
 elseif action=='CONFIRM RELEASE' then self:box()[slot]=nil
 elseif action=='MARK' then mon.markings=((mon.markings or 0)+1)%64
 elseif action=='PARTY' then self.partyOpen=true;self.partyIndex=1
 elseif action=='BOX NAME' then
  Screens.push(self.game,'NamingScreen',{title='BOX NAME',default=self:boxName(),maxLen=8,onDone=function(name)
   if name~='' then self.game.save.boxNames=self.game.save.boxNames or {};self.game.save.boxNames[self.game.save.currentBox]=name end
  end})
 elseif action=='WALLPAPER' then self:box().wallpaper=((self:box().wallpaper or self:wallpaperId())+1)%16
 elseif action=='TAKE ITEM' and mon then
  local item=mon.heldItem or mon.item
  if item and item~=0 and Bag.add(self.game.save,item,1,self.game.data) then mon.heldItem=nil;mon.item=nil end
 elseif action=='GIVE ITEM' and mon then
  Screens.push(self.game,'BagMenu',{pick=true,onPick=function(id)
   local item=self.game.data.items[id]
   if not item or item.keyItem then return end
   if (self.game.save.inventory[id] or 0)<1 then return end
   local old=mon.heldItem or mon.item
   if old and old~=0 and not Bag.add(self.game.save,old,1,self.game.data) then return end
   Bag.remove(self.game.save,id,1);mon.heldItem=id;mon.item=nil
  end})
 end
end
function PC:update(dt)
 self.t=(self.t or 0)+(dt or 1/60);local input=self.game.input
 if self.menu then
  if input:wasPressed('up') then self.action=(self.action-2)%#self.menu+1
  elseif input:wasPressed('down') then self.action=self.action%#self.menu+1
  elseif input:wasPressed('a') then self:runAction(self.menu[self.action])
  elseif input:wasPressed('b') then self.menu=nil end
  return
 end
 if input:wasPressed('b') then
  if self:returnHeld() then return end
  if self.partyOpen then self.partyOpen=nil;return end
  self.game.stack:pop();if self.opts.onCancel then self.opts.onCancel() end;return
 end
 if input:wasPressed('select') then self.partyOpen=not self.partyOpen;self.partyIndex=1 end
 if input:wasPressed('l') then self:changeBox(-1) elseif input:wasPressed('r') then self:changeBox(1) end
 if self.partyOpen then
  if input:wasPressed('up') then self.partyIndex=(self.partyIndex-2)%7+1
  elseif input:wasPressed('down') then self.partyIndex=self.partyIndex%7+1 end
 else
  if input:wasPressed('up') then self.row=(self.row+5)%6 elseif input:wasPressed('down') then self.row=(self.row+1)%6 end
  if input:wasPressed('left') then if self.row==0 then self:changeBox(-1) else self.col=(self.col+4)%6+1 end end
  if input:wasPressed('right') then if self.row==0 then self:changeBox(1) else self.col=self.col%6+1 end end
 end
 if input:wasPressed('a') then self:choose() end
end
function PC:draw()
 local g=love.graphics;g.setColor(0.7,0.8,0.9,1);g.rectangle('fill',0,0,256,192);g.setColor(1,1,1,1)
 local main=self:img('storage/main');if main then g.draw(main,0,0) end
 local paper=self:img(('storage/wallpaper_%02d'):format(self:wallpaperId()));if paper then g.draw(paper,88,0) end
 local name=Font.fit(self:boxName(),144);Font.draw(name,172-Font.width(name)/2,13)
 for slot=1,30 do self:drawIcon(self:box()[slot],112+(slot-1)%6*24,40+math.floor((slot-1)/6)*24) end
 local mon=self:selected()
 if mon then
  local path=require('src.pokemon.Sprites').path(self.game.data,mon.species,'front',{mon=mon,kind='summary'})
  if path then
   if self.images[path]==nil then local ok,img=pcall(Assets.image,path);self.images[path]=ok and img or false end
   local image=self.images[path];if image then local w,h=image:getDimensions();g.draw(image,40,56,0,72/w,72/h,w/2,h/2) end
  end
  Font.draw(Font.fit(self:nameOf(mon),68),2,88);Font.draw('Lv '..(mon.level or 1),8,108)
  local item=self.game.data.items[mon.heldItem or mon.item]
  Font.draw(Font.fit(item and item.name or 'None',68),2,136)
 end
 local x,y=112+(self.col-1)*24,40+(self.row-1)*24
 if self.row>0 and not self.partyOpen then self:drawCursor(self.held and 2 or 0,x,y-16) end
 if self.partyOpen then
  g.setColor(0.8,0.9,1,1);g.rectangle('fill',72,24,80,160);g.setColor(1,1,1,1)
  for i=1,6 do self:drawIcon(self.game.save.party[i],112,36+(i-1)*22) end
  g.setColor(1,0.8,0.1,1);g.rectangle('line',96,22+(self.partyIndex-1)*22,32,24);g.setColor(1,1,1,1)
 end
 if self.held then self:drawIcon(self.held.mon,x,y-4) end
 if self.menu then
  local top=192-#self.menu*20;g.setColor(0.9,0.96,1,1);g.rectangle('fill',136,top,120,192-top);g.setColor(1,1,1,1)
  for i,label in ipairs(self.menu) do
   if i==self.action then g.setColor(0.55,0.75,0.85,1);g.rectangle('fill',136,top+(i-1)*20,120,20);g.setColor(1,1,1,1) end
   Font.draw(label,140,top+(i-1)*20+2)
  end
 end
 if self.message~='' then Font.draw(Font.fit(self.message,248),4,176) end
end
function PC:drawCursor(sequence,x,y)
 local key=('storage/cursor_%02d'):format(sequence);local image=self:img(key)
 if image then
  local rec=self.game.data.gen4_graphics.screens[key]
  if type(rec)~='table' then rec={} end
  love.graphics.draw(image,x+(rec.originX or -image:getWidth()/2),y+(rec.originY or 0))
 end
end
function PC:touchpressed(_,px,py)
 local r=require('src.render.Renderer').uiPresentation
 if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
 local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
 if self.menu then local top=192-#self.menu*20;local i=math.floor((y-top)/20)+1;if x>=136 and i>=1 and i<=#self.menu then self:runAction(self.menu[i]) end
 elseif y<24 then if x<120 then self:changeBox(-1) elseif x>224 then self:changeBox(1) else self.row=0;self:choose() end
 elseif self.partyOpen then self.partyIndex=math.min(7,math.floor((y-24)/22)+1);self:choose()
 elseif x>=100 and x<244 and y>=28 and y<148 then self.col=math.floor((x-100)/24)+1;self.row=math.floor((y-28)/24)+1;self:choose() end
 return true
end
return PC
