-- Platinum counter: cartridge shop background, with transactions kept on the
-- DS surface so quantity and confirmation never open a Game Boy menu.
local Assets = require('src.render.Assets')
local Font = require('src.render.Font')
local Bag = require('src.inventory.Bag')
local Shop = {}
local LIST_X,LIST_Y,ROW_HEIGHT,VISIBLE_ROWS=96,16,16,7
Shop.layout={iconX=22,iconY=172,listX=LIST_X,listY=LIST_Y,rowHeight=ROW_HEIGHT,visibleRows=VISIBLE_ROWS,descriptionX=40,descriptionY=144}
Shop.__index = Shop
Shop.isOpaque = false
function Shop:uiSize() return 256, 192 end
function Shop:wantsFillScale() return true end
function Shop:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end

function Shop.new(game, stock, onQuit)
  return setmetatable({ game = game, stock = stock or {}, onQuit = onQuit,
    mode = 'menu', cursor = 1, scroll = 0, message = 'How may I help you?' }, Shop)
end

function Shop:close()
  self.game.stack:pop()
  if self.onQuit then self.onQuit() end
end

function Shop:rows()
  if self.mode == 'menu' then return { 'BUY', 'SELL', 'QUIT' } end
  if self.mode == 'sell' then return Bag.order(self.game.save) end
  return self.stock
end

function Shop:back()
  if self.mode == 'menu' then return self:close() end
  if self.mode == 'quantity' or self.mode == 'confirm' then self.mode = self.transaction
  else self.mode, self.cursor, self.scroll = 'menu', 1, 0 end
end

function Shop:choose()
  if self.mode == 'menu' then
    if self.cursor == 3 then return self:close() end
    self.mode = self.cursor == 1 and 'buy' or 'sell'
    self.cursor, self.scroll, self.message = 1, 0, nil
    return
  end
  if self.mode == 'confirm' then return self:transact() end
  if self.mode == 'quantity' then self.mode = 'confirm'; return end
  local id = self:rows()[self.cursor]
  local def = id and self.game.data.items[id]
  if not def then return self:back() end
  local price = tonumber(def.price) or 0
  if self.mode == 'sell' and (def.keyItem or def.fieldPocket == 7
      or tonumber(id) and tonumber(id) >= 420 and tonumber(id) <= 427
      or price <= 0) then
    self.message = "I can't buy that item."; return
  end
  self.unit = self.mode == 'sell' and math.floor(price / 2) or price
  self.max = self.mode == 'sell' and (self.game.save.inventory[id] or 0)
    or math.min(99, price > 0 and math.floor((self.game.save.money or 0) / price) or 99)
  if self.max < 1 then self.message = "You don't have enough money."; return end
  self.item, self.transaction, self.qty, self.mode = id, self.mode, 1, 'quantity'
end

function Shop:transact()
  local save, cost = self.game.save, self.qty * self.unit
  if self.transaction == 'buy' then
    if (save.money or 0) < cost then self.message = "You don't have enough money."
    elseif not Bag.add(save, self.item, self.qty, self.game.data) then self.message = 'Your Bag is full.'
    else save.money = (save.money or 0) - cost; self.message = 'Thank you!'
      -- Platinum awards one Premier Ball per purchase of at least ten Poke Balls.
      if self.item == 4 and self.qty >= 10 and self.game.data.items[12] then Bag.add(save, 12, 1, self.game.data) end
    end
  else
    if (save.inventory[self.item] or 0) >= self.qty then
      Bag.remove(save, self.item, self.qty); save.money = math.min(999999, (save.money or 0) + cost)
      self.message = 'Thank you!'
    end
  end
  self.mode = self.transaction
  self.cursor = math.max(1, math.min(self.cursor, #self:rows() + 1))
end

function Shop:step(delta)
  if self.mode == 'quantity' then self.qty = (self.qty - 1 + delta) % self.max + 1; return end
  if self.mode == 'confirm' then return end
  local count = #self:rows() + (self.mode == 'menu' and 0 or 1)
  self.cursor = (self.cursor - 1 + delta) % math.max(1, count) + 1
  self.message = nil
  self.scroll = math.max(0, math.min(self.scroll, self.cursor - 1))
  if self.cursor > self.scroll + VISIBLE_ROWS then self.scroll = self.cursor - VISIBLE_ROWS end
end

function Shop:selectedItem()
  local id = (self.mode == 'quantity' or self.mode == 'confirm') and self.item
    or self.mode ~= 'menu' and self:rows()[self.cursor]
  return id and self.game.data.items[id], id
end

function Shop:description()
  local def = self:selectedItem()
  return self.message or def and def.description or ''
end

function Shop:touchpressed(id,px,py)
  local rect=require('src.render.Renderer').uiPresentation
  if not rect or px<rect.x or py<rect.y or px>=rect.x+rect.w or py>=rect.y+rect.h then return false end
  local x,y=(px-rect.x)/rect.scaleX,(py-rect.y)/rect.scaleY
  if y>=168 then self:back(); return true end
  if self.mode=='quantity' then
    if y>=72 and y<96 then self:step(x<176 and -1 or 1)
    elseif y>=96 and y<128 then self:choose() end
  elseif self.mode=='confirm' then
    if y>=96 and y<128 then if x<176 then self:choose() else self:back() end end
  elseif self.mode~='menu' and x>=160 and x<192 and (y<16 or y>=128 and y<144) then
    self:step(y<16 and -1 or 1)
  elseif x>=LIST_X and y>=LIST_Y and y<LIST_Y+VISIBLE_ROWS*ROW_HEIGHT then
    local row=self.scroll+math.floor((y-LIST_Y)/ROW_HEIGHT)+1
    local count=#self:rows()+(self.mode=='menu' and 0 or 1)
    if row<=count then self.cursor=row; self.message=nil; self:choose() end
  elseif x<104 and y>=96 and y<128 and self.mode~='menu' then
    local count=#self:rows()+1
    self.scroll=math.max(0,math.min(math.max(0,count-VISIBLE_ROWS),self.scroll+(x<52 and -VISIBLE_ROWS or VISIBLE_ROWS)))
  end
  return true
end

function Shop:drawSprite(key,x,y)
  local rec=((self.game.data.gen4_graphics or {}).screens or {})[key]
  if not rec then return false end
  local path=type(rec)=='table' and rec.path or rec
  self.icons=self.icons or {}
  if self.icons[path]==nil then local ok,img=pcall(Assets.image,path);self.icons[path]=ok and img or false end
  local image=self.icons[path]
  if not image then return false end
  local ox,oy=0,0
  if type(rec)=='table' then ox,oy=rec.originX or 0,rec.originY or 0 end
  love.graphics.draw(image,x+ox,y+oy);return true
end

function Shop:update()
  local input = self.game.input
  if input:wasPressed('b') then self:back()
  elseif input:wasPressed('up') then self:step(self.mode == 'quantity' and 1 or -1)
  elseif input:wasPressed('down') then self:step(self.mode == 'quantity' and -1 or 1)
  elseif input:wasPressed('right') and self.mode == 'quantity' then self:step(10)
  elseif input:wasPressed('left') and self.mode == 'quantity' then self:step(-10)
  elseif input:wasPressed('a') then self:choose() end
end

function Shop:draw()
  local g = love.graphics
  local art = ((self.game.data.gen4_graphics or {}).screens or {})['shop/tilemap']
  local path = type(art) == 'table' and art.path or art
  if path and self.image == nil then
    local ok, img = pcall(Assets.image, path); self.image = ok and img or false
  end
  g.setColor(1, 1, 1, 1)
  if self.image then g.draw(self.image, 0, 0) end
  -- Keep the ROM's list and description panels visible. Game Boy windows
  -- previously covered almost every pixel of the imported shop artwork.
  g.setColor(0.94, 0.98, 1, 1)
  g.rectangle('fill', 0, 8, 84, 32)
  g.setColor(1, 1, 1, 1)
  Font.draw('$' .. tostring(self.game.save.money or 0), 8, 16)
  if self.mode == 'quantity' or self.mode == 'confirm' then
    local def = self.game.data.items[self.item]
    Font.draw(def.name, 112, 16)
    Font.draw('x' .. self.qty .. '   $' .. self.qty * self.unit, 112, 48)
    Font.draw('In Bag: '..tostring(self.game.save.inventory[self.item] or 0),8,120)
    if self.mode=='quantity' then Font.draw('-                 +',112,80) end
    Font.draw(self.mode == 'confirm' and 'A: YES   B: NO' or 'A: OK   B: CANCEL', 104, 96)
  else
    local rows = self:rows()
    for i = 1, VISIBLE_ROWS do
      local index, y = self.scroll + i, LIST_Y + (i - 1) * ROW_HEIGHT
      local id = rows[index]
      if id or self.mode ~= 'menu' and index == #rows + 1 then
        local def = self.mode ~= 'menu' and self.game.data.items[id]
        local label = self.mode == 'menu' and id or def and def.name or 'CANCEL'
        if index == self.cursor then
          if not self:drawSprite('shop/cursor_00',172,y+8) then
            g.setColor(0.55,0.75,0.85,1);g.rectangle('fill',96,y-2,152,16)
          end
          g.setColor(1,1,1,1)
        end
        local right = def and (self.mode == 'sell' and ('x' .. (self.game.save.inventory[id] or 0)) or ('$' .. (def.price or 0)))
        Font.draw(Font.fit(label, right and 144 - Font.width(right) or 152), LIST_X, y)
        if def then
          Font.draw(right, 248 - Font.width(right), y)
        end
      end
    end
  end
  if self.mode=='buy' or self.mode=='sell' then
    if self.scroll>0 then self:drawSprite('shop/scroll_00',177,8) end
    if self.scroll+VISIBLE_ROWS<#self:rows()+1 then self:drawSprite('shop/scroll_01',177,132) end
  end
  local def, id = self:selectedItem()
  local rec = def and ((self.game.data.gen4_graphics or {}).screens or {})[('items/icon_%03d'):format(tonumber(def.id) or tonumber(id) or 0)]
  if rec then
    local path = type(rec) == 'table' and rec.path or rec
    self.icons = self.icons or {}
    if self.icons[path] == nil then local ok, icon = pcall(Assets.image,path); self.icons[path] = ok and icon or false end
    local icon = self.icons[path]
    if icon then g.draw(icon,Shop.layout.iconX-icon:getWidth()/2,Shop.layout.iconY-icon:getHeight()/2) end
  end
  local y = Shop.layout.descriptionY
  Font.pushStyle({text={1,1,1},shadow={0,0,0}})
  for line in (tostring(self:description()) .. '\n'):gmatch('([^\n]*)\n') do
    if y > 184 then break end
    Font.draw(Font.fit(line, 212), 40, y); y = y + 14
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

return Shop
