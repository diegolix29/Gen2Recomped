-- src/ui/HgssMartBuy.lua -- HEARTGOLD / SOULSILVER'S POKE MART "BUY" SCREEN,
-- mixed into src/ui/Gen4ShopMenu.lua (`install`).
--
-- Reported from play: "the item list background is see-through and doesn't
-- use the ROM's art". It was Platinum's top-screen list (shop_gra's list
-- window at (12, 2)) drawn over HeartGold's counter art, whose top is clear:
-- HeartGold never prints into that window (shop_menu.c ov03_022594C6[0]). Its
-- goods are chosen on the TOUCH SCREEN (asm/overlay_31.s, art /a/0/6/0 15-25,
-- imported as `gen4_hgss_mart_art` by src/import/Gen4HgssMartArt.lua):
--
--   * screen 17: the header and six dotted slots; screen 18's white buttons
--     where the page has an item -- six a page, two columns of three
--     (slot windows ov31_0225EE88: tiles (4 | 20, 5 | 10 | 15), 11 x 4; the
--     name from bank 222 at (0, 0), the price, bank 435 #18 "${n}", at
--     (36, 16), ink 1/2 on palette 12)
--   * the red frame (cell 0) on the chosen slot at (48 | 176, 56 | 96 | 136)
--   * the money window (1, 0) 9 x 4: bank 435 #30 "Money" and the amount
--   * the page arrows (24, 176) / (64, 176), the page "n/m" (#43) in (10, 21),
--     the blue back button (224, 176) with #17 "CANCEL" centred
--   * choosing: screen 19 (the item, "In Bag", the count and the total) with
--     the count's up / down marks and the A (BUY) / B buttons; the question
--     ("For n, that will be $m") on screen 20 with the same buttons
-- The top screen keeps the field, the clerk's lines, the money and the
-- description band (shop_menu.c windows 1-5).
--
-- MEASURED rather than read: the count / total / In Bag text positions inside
-- screen 19's boxes, and where the up / down marks and A / B buttons sit
-- (overlay 31's sprite templates are not decoded).

local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local M = {}

local W, H = 256, 192
local floor = math.floor
M.PER_PAGE = 6
M.SLOTS = { -- x, y, w, h of each button (screen 18)
  { 2, 37, 124, 38 }, { 130, 37, 124, 38 }, { 2, 77, 124, 38 },
  { 130, 77, 124, 38 }, { 2, 117, 124, 38 }, { 130, 117, 124, 38 },
}
M.CURSOR_AT = { { 48, 56 }, { 176, 56 }, { 48, 96 }, { 176, 96 }, { 48, 136 }, { 176, 136 } }
M.ICON_AT = { { 22, 59 }, { 152, 59 }, { 22, 100 }, { 152, 100 }, { 22, 139 }, { 152, 139 } }
M.TEXT_AT = { { 32, 40 }, { 160, 40 }, { 32, 80 }, { 160, 80 }, { 32, 120 }, { 160, 120 } }
M.PREV, M.NEXT, M.BACK = { 0, 168, 48, 24 }, { 48, 168, 32, 24 }, { 192, 168, 64, 24 }
M.UP, M.DOWN = { 154, 98 }, { 154, 152 }
M.A_AT, M.B_AT = { 88, 176 }, { 216, 176 }
local LIST_INK = { { 0.29, 0.29, 0.33 }, { 0.75, 0.77, 0.82 } }
local WHITE_INK = { { 1, 1, 1 }, { 0.35, 0.35, 0.40 } }

function M.active(self)
  local data = self.game and self.game.data
  local v = data and data.gen4_version
  return v and v.family == "hgss" and data.gen4_hgss_mart_art and not self.goods and not self.frontier
    and (self.mode == "buy" or ((self.mode == "quantity" or self.mode == "confirm") and self.transaction == "buy"))
end

local function art(self, key)
  local rec = (self.game.data.gen4_hgss_mart_art or {})[key]
  if type(rec) ~= "table" then return nil end
  self.hgMartImages = self.hgMartImages or {}
  local img = self.hgMartImages[key]
  if img == nil then
    local ok
    if rec.image then ok, img = pcall(love.graphics.newImage, rec.image)
    else ok, img = pcall(require("src.render.Assets").image, rec.path) end
    img = ok and img or false
    if img then img:setFilter("nearest", "nearest") end
    self.hgMartImages[key] = img
  end
  return img or nil, rec
end

local function sprite(self, key, x, y)
  local img, rec = art(self, key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x + (rec.originX or -img:getWidth() / 2), y + (rec.originY or -img:getHeight() / 2))
  return true
end

local function inRect(r, x, y) return x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] end
local function around(c, x, y, w, h) return x >= c[1] - w and x < c[1] + w and y >= c[2] - h and y < c[2] + h end

function M.page(self) return floor(((self.cursor or 1) - 1) / M.PER_PAGE) end
function M.pages(self) return math.max(1, math.ceil(#self.stock / M.PER_PAGE)) end

local function icon(self, def, id)
  local rec = def and ((self.game.data.gen4_graphics or {}).screens or {})[("items/icon_%03d"):format(tonumber(def.id) or tonumber(id) or 0)]
  local path = type(rec) == "table" and rec.path or rec
  if not path then return nil end
  self.hgMartIcons = self.hgMartIcons or {}
  if self.hgMartIcons[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.hgMartIcons[path] = ok and img or false
  end
  return self.hgMartIcons[path] or nil
end

-- the pad on the grid: up / down a row, left / right a column, past the edge
-- the page (the cartridge's d-pad table ov03_0225947A)
function M.move(self, dx, dy)
  local n = #self.stock
  if n == 0 then return end
  local c = self.cursor - 1
  local page, slot = floor(c / M.PER_PAGE), c % M.PER_PAGE
  local col, row = slot % 2, floor(slot / 2)
  local to = c
  if dy ~= 0 then
    local r = row + dy
    if r >= 0 and r <= 2 then to = page * M.PER_PAGE + r * 2 + col end
  elseif dx ~= 0 then
    local nc = col + dx
    if nc >= 0 and nc <= 1 then to = page * M.PER_PAGE + row * 2 + nc
    else
      local pages = M.pages(self)
      local np = (page + dx) % pages
      to = np * M.PER_PAGE + row * 2 + (dx > 0 and 0 or 1)
      while to >= n and to > np * M.PER_PAGE do to = to - 1 end
    end
  end
  if to >= 0 and to < n and to ~= c then
    self.cursor = to + 1
    self.message = nil
    pcall(function() require("src.core.Sound").playSe(self.game.data, "SEQ_SE_DP_SELECT") end)
  end
end

function M.turnPage(self, d)
  local pages = M.pages(self)
  if pages <= 1 then return end
  local slot = (self.cursor - 1) % M.PER_PAGE
  local np = (M.page(self) + d) % pages
  self.cursor = math.min(#self.stock, np * M.PER_PAGE + slot + 1)
  self.message = nil
  pcall(function() require("src.core.Sound").playSe(self.game.data, "SEQ_SE_DP_SELECT") end)
end

-- the touch screen, in its own 256 x 192
function M.drawTouch(self)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local state = self.mode == "buy" and "panel" or (self.mode == "quantity" and "quantity" or "confirm")
  local back = art(self, state)
  if back then g.draw(back, 0, 0) else g.setColor(0.23, 0.6, 1, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  -- the money window (1, 0) 9 x 4
  Font.pushStyle({ text = WHITE_INK[1], shadow = WHITE_INK[2] })
  Font.draw(self:line(18, "Money"), 8, 0)
  local amount = self:line(19, "$" .. tostring(self.game.save.money or 0), tostring(self.game.save.money or 0))
  Font.draw(amount, 80 - Font.width(amount), 16)
  Font.popStyle()
  if self.mode == "buy" then
    local buttons = art(self, "buttons")
    local page = M.page(self)
    Font.pushStyle({ text = LIST_INK[1], shadow = LIST_INK[2] })
    for i = 1, M.PER_PAGE do
      local id = self.stock[page * M.PER_PAGE + i]
      if id then
        local r = M.SLOTS[i]
        if buttons then
          self.hgMartQuads = self.hgMartQuads or {}
          self.hgMartQuads[i] = self.hgMartQuads[i] or g.newQuad(r[1], r[2], r[3], r[4], buttons:getDimensions())
          g.setColor(1, 1, 1, 1)
          g.draw(buttons, self.hgMartQuads[i], r[1], r[2])
        end
        local def = self:def(id)
        local ic = icon(self, def, id)
        local at = M.ICON_AT[i]
        g.setColor(1, 1, 1, 1)
        if ic then g.draw(ic, at[1] - ic:getWidth() / 2, at[2] - ic:getHeight() / 2) end
        local t = M.TEXT_AT[i]
        Font.draw(Font.fit(def and def.name or "", 88), t[1], t[2])
        local price = tonumber(def and def.price) or 0
        Font.draw(self:line(9, "$" .. price, tostring(price)), t[1] + 36, t[2] + 16)
      end
    end
    Font.popStyle()
    local slot = (self.cursor - 1) % M.PER_PAGE + 1
    local c = M.CURSOR_AT[slot]
    if self.stock[self.cursor] then sprite(self, "cursor", c[1], c[2]) end
    if M.pages(self) > 1 then
      sprite(self, "prev", 24, 176)
      sprite(self, "next", 64, 176)
    end
    Font.pushStyle({ text = WHITE_INK[1], shadow = WHITE_INK[2] })
    local T = require("src.import.Gen4Text")
    T.buffer(self.game, tostring(M.page(self) + 1), tostring(M.pages(self)))
    local pn = T.resolve(self.game.data, 435, 43, self.game) or ("%d/%d"):format(M.page(self) + 1, M.pages(self))
    Font.draw(pn, 84, 172)
    Font.popStyle()
    sprite(self, "back", 224, 176)
    Font.pushStyle({ text = WHITE_INK[1], shadow = WHITE_INK[2] })
    local cancel = self:line(8, "CANCEL")
    Font.draw(cancel, 200 + floor((48 - Font.width(cancel)) / 2), 172)
    Font.popStyle()
  else
    local def = self:def(self.item)
    local ic = icon(self, def, self.item)
    g.setColor(1, 1, 1, 1)
    if ic then g.draw(ic, 88 - ic:getWidth() / 2, 72 - ic:getHeight() / 2) end
    Font.pushStyle({ text = LIST_INK[1], shadow = LIST_INK[2] })
    Font.draw(Font.fit(def and def.name or "", 72), 108, 64)
    local owned = tostring(self:owned(self.item))
    local T = require("src.import.Gen4Text")
    Font.draw(T.resolve(self.game.data, 435, 35, self.game) or "In Bag:", 6, 108)
    T.buffer(self.game, owned)
    local n = T.resolve(self.game.data, 435, 36, self.game) or owned
    Font.draw(n, 72 - Font.width(n), 124)
    if self.mode == "quantity" then
      local q = ("x%02d"):format(self.qty)
      Font.draw(q, 154 - floor(Font.width(q) / 2), 116)
      local total = self:line(22, "$" .. tostring(self.qty * self.unit), tostring(self.qty * self.unit))
      Font.draw(total, 250 - Font.width(total), 116)
    end
    Font.popStyle()
    if self.mode == "quantity" then
      sprite(self, "up", M.UP[1], M.UP[2])
      sprite(self, "down", M.DOWN[1], M.DOWN[2])
    end
    sprite(self, "a_button", M.A_AT[1], M.A_AT[2])
    sprite(self, "b_button", M.B_AT[1], M.B_AT[2])
    Font.pushStyle({ text = WHITE_INK[1], shadow = WHITE_INK[2] })
    local yes = self.mode == "confirm" and self:line(23, "YES") or self:line(15, "BUY")
    Font.draw(yes, M.A_AT[1] - 16 + floor((56 - Font.width(yes)) / 2), 169)
    local no = self.mode == "confirm" and self:line(24, "NO") or self:line(8, "CANCEL")
    Font.draw(no, M.B_AT[1] - 24 + floor((56 - Font.width(no)) / 2), 169)
    Font.popStyle()
  end
end

-- a tap on the touch screen at (x, y)
function M.tap(self, x, y)
  if self.mode == "buy" then
    if self.message then self.message = nil; return true end
    if inRect(M.BACK, x, y) then self:back(); return true end
    if inRect(M.PREV, x, y) then M.turnPage(self, -1); return true end
    if inRect(M.NEXT, x, y) then M.turnPage(self, 1); return true end
    for i, r in ipairs(M.SLOTS) do
      local index = M.page(self) * M.PER_PAGE + i
      if inRect(r, x, y) and self.stock[index] then
        self.cursor = index
        self:choose()
        return true
      end
    end
    return true
  end
  if self.message and self.mode ~= "quantity" and self.mode ~= "confirm" then self.message = nil; return true end
  if self.mode == "quantity" then
    if around(M.UP, x, y, 16, 14) then self:step(1); return true end
    if around(M.DOWN, x, y, 16, 14) then self:step(-1); return true end
  end
  if around(M.A_AT, x, y, 40, 16) then
    if self.mode == "confirm" then self.yesNo = 1 end
    self:choose(); return true
  end
  if around(M.B_AT, x, y, 40, 16) then self:back(); return true end
  return true
end

local function bottomOnSecond(self)
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

function M.install(Shop)
  local draw, update, step, touch = Shop.draw, Shop.update, Shop.step, Shop.touchpressed

  Shop.draw = function(self)
    if not (M.active(self) and self:counterUp()) then return draw(self) end
    if bottomOnSecond(self) then
      -- the top screen as shop_menu.c leaves it: no list there
      local list = self.drawList
      self.drawList = function() end
      draw(self)
      self.drawList = list
      SecondScreen.draw(self.game, function() M.drawTouch(self) end)
    else
      -- one screen: the touch screen, where the choosing is, and the
      -- clerk's line over it
      M.drawTouch(self)
      if self.message then self:drawFieldMessage() end
    end
  end

  Shop.step = function(self, delta)
    if M.active(self) and self.mode == "buy" then return M.move(self, 0, delta > 0 and 1 or -1) end
    return step(self, delta)
  end

  Shop.update = function(self, dt)
    local before = self.mode
    update(self, dt)
    if M.active(self) and self.mode == "buy" and before == "buy" and self.camStep == self:cameraTarget() then
      local input = self.game.input
      if input and input:wasPressed("left") then M.move(self, -1, 0)
      elseif input and input:wasPressed("right") then M.move(self, 1, 0) end
    end
  end

  Shop.touchpressed = function(self, id, px, py)
    if not (M.active(self) and self:counterUp()) then return touch(self, id, px, py) end
    local x, y
    if bottomOnSecond(self) then
      x, y = SecondScreen.toLocal(self.game, px, py)
    else
      local rect = require("src.render.Renderer").uiPresentation
      x, y = px, py
      if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
    end
    if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
    return M.tap(self, floor(x), floor(y))
  end
end

return M
