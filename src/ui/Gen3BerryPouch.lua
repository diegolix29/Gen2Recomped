-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FIRERED'S BERRY POUCH, a screen of its own (berry_pouch.c) -- see
-- Gen3TMCase.lua for the fuller account of why opening it used to push the
-- ordinary bag at a locked pocket instead.
--
-- WHAT THIS DRAWS FROM THE ROM (RomExtractorGen3:extractBerryPouchScreen):
-- the pouch's own background (gBerryPouchBgGfx/Bg1Tilemap, with the same
-- male/female bank-0 palette split the FRLG bag screen reads) and the real
-- window positions out of berry_pouch.c's own sWindowTemplates_Main.
--
-- NOT EXTRACTED: the pouch's own sprite (the one that wobbles when a berry
-- is added or removed) and the SELL flow berry_pouch.c offers when opened
-- from a Mart -- both out of scope here, matching the TM Case's own
-- stated line. Selling a berry still works from the ordinary bag.

local Font = require("src.render.Font")
local Bag = require("src.inventory.Bag")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3BerryPouch = {}
Gen3BerryPouch.__index = Gen3BerryPouch
Gen3BerryPouch.isOpaque = true

local GBA_W, GBA_H = 240, 160
local ROW_PITCH = 16

local FALLBACK = {
  windows = {
    list = { x = 88, y = 8, width = 144, height = 112 },
    description = { x = 40, y = 128, width = 200, height = 32 },
    title = { x = 8, y = 8, width = 72, height = 16 },
  },
  list = { rows = 7 },
}

function Gen3BerryPouch:uiSize() return GBA_W, GBA_H end
function Gen3BerryPouch:wantsFillScale() return true end

function Gen3BerryPouch:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

function Gen3BerryPouch:screen()
  local r = (self.game.data.constants or {}).gen3BerryPouchScreen
  if type(r) ~= "table" or type(r.windows) ~= "table" then return FALLBACK end
  return r
end

function Gen3BerryPouch:box(key)
  local r = self:screen()
  return r.windows[key] or FALLBACK.windows[key]
end

function Gen3BerryPouch:listRows()
  local r = self:screen()
  local n = math.floor(tonumber(r.list and r.list.rows) or FALLBACK.list.rows)
  return math.max(1, n)
end

local function isBerry(def)
  return def and (def.berry or def.pocket == "BERRY"
                  or (def.id and tostring(def.id):find("BERRY")))
end

function Gen3BerryPouch:rebuild()
  local game, save = self.game, self.game.save
  local rows = {}
  for _, id in ipairs(Bag.order(save)) do
    local def = game.data.items and game.data.items[id]
    if isBerry(def) then
      rows[#rows + 1] = {
        id = id, label = def.name or id,
        qty = (save.inventory or {})[id] or 0,
        description = def.description or def.desc,
      }
    end
  end
  rows[#rows + 1] = { close = true, label = Strings("CLOSE") }
  self.rows = rows
  self.index = math.min(self.index or 1, #rows)
  self.top = math.max(1, math.min(self.top or 1, #rows - self:listRows() + 1))
end

function Gen3BerryPouch.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3BerryPouch)
  self.game = game
  self.onCancel = opts.onCancel
  self.index, self.top = 1, 1
  self:rebuild()
  return self
end

function Gen3BerryPouch:selected() return self.rows[self.index] end

function Gen3BerryPouch:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3BerryPouch:moveCursor(delta)
  local n = #self.rows
  if n == 0 then return end
  self.index = (self.index - 1 + delta) % n + 1
  local visible = self:listRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then
    self.top = self.index - visible + 1
  end
  Sound.play(self.game.data, "Press_AB") -- SE_SELECT
end

function Gen3BerryPouch:choose()
  local row = self:selected()
  if not row or row.close then return self:close() end
  local Gen3ItemMenu = require("src.ui.Gen3ItemMenu")
  self.game.stack:push(Gen3ItemMenu.new(self.game, {
    entries = { { label = "USE", kind = "use" },
                { label = "GIVE", kind = "give" },
                { label = "TOSS", kind = "toss" },
                { label = "EXIT", kind = "cancel" } },
    columns = 1,
    onPick = function(kind) self:act(kind, row.id) end,
  }))
end

function Gen3BerryPouch:act(kind, id)
  local game = self.game
  local Logger = require("src.core.Logger")
  if kind == "use" then
    local ok, err = pcall(require("src.ui.BagMenu").useItem, game, nil, id, self)
    if not ok then
      Logger.warn("gen3 berry pouch: %s could not be used: %s",
                  tostring(id), tostring(err))
    end
  elseif kind == "give" then
    local ok, err = pcall(require("src.ui.BagMenu").giveItem, game, id,
                          function() self:rebuild() end)
    if not ok then
      Logger.warn("gen3 berry pouch: %s could not be given: %s",
                  tostring(id), tostring(err))
    end
  elseif kind == "toss" then
    self:toss(id)
  end
end

-- The same "how many, then ask, then answer" the ordinary bag's TOSS uses
-- (Gen3BagMenu:toss); a berry tosses the same way a potion does.
function Gen3BerryPouch:toss(id)
  local game = self.game
  local def = game.data.items and game.data.items[id]
  local name = (def and def.name) or id
  local QuantityBox = require("src.ui.QuantityBox")
  local TextBox = require("src.render.TextBox")
  local held = (game.save.inventory or {})[id] or 1
  game.stack:push(QuantityBox.new(game, {
    max = held,
    onDone = function(qty)
      if not qty or qty <= 0 then return end
      local ask = Strings("Throw away this\n%s?", name)
      game.stack:push(TextBox.new(game, ask, nil, {
        choice = function(yes)
          if not yes then return end
          Bag.remove(game.save, id, qty)
          self:rebuild()
        end,
      }))
    end,
  }))
end

function Gen3BerryPouch:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close()
  end
end

function Gen3BerryPouch:keypressed(key)
  if key == "down" then return self:moveCursor(1) end
  if key == "up" then return self:moveCursor(-1) end
  if key == "a" then return self:choose() end
  if key == "b" then return self:close() end
end

function Gen3BerryPouch:background()
  local r = self:screen()
  local images = r.images
  if type(images) ~= "table" then return nil end
  local player = (self.game.save or {}).player or {}
  local path = (player.gender == "girl" and images.female) or images.male
               or images.female
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  return ok and img or nil
end

local function drawRows(self)
  local r = self:screen()
  local L = r.list or {}
  local win = self:box("list")
  local pitch = math.max(8, math.floor(tonumber(L.rowHeight) or ROW_PITCH))
  local itemX = win.x + (tonumber(L.itemX) or 8)
  local qtyX = win.x + (tonumber(L.quantityX) or (win.width - 30))
  local top = win.y + (tonumber(L.upTextY) or 2)
  local first = self.top
  local rows = self:listRows()
  for i = 0, rows - 1 do
    local row = self.rows[first + i]
    if not row then break end
    local y = top + i * pitch
    Font.draw(row.label, itemX, y)
    if not row.close and row.qty then
      local faced = Font.pushFace("small")
      Font.draw(Strings("x%03d", row.qty), qtyX, y)
      if faced then Font.popFace() end
    end
    if first + i == self.index then
      Font.drawCode(Theme.cursor, win.x + (tonumber(L.cursorX) or 0), y)
    end
  end
end

-- Same reasoning as Gen3TMCase.lua: the pouch's background PICTURE does not
-- bake in its panel borders, so these are drawn every time, background or
-- not, using the real 9-slice window-frame system.
local function panel(self, key)
  local b = self:box(key)
  Font.drawBox(math.floor(b.x / 8), math.floor(b.y / 8),
               math.floor(b.width / 8), math.floor(b.height / 8))
  return b
end

-- FIRERED (berry_pouch.c): the field already carries the frames, so no
-- boxes go over it -- the title and description print white on its dark
-- panels ({0,1,2}), the list dark on light ({0,2,3}), the pouch OBJ stands
-- at (40,76) and the berry's icon at (24,147).
function Gen3BerryPouch:drawFireRed(field, art)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  g.draw(field, 0, 0)
  local function img(key)
    self._img = self._img or {}
    local path = art.images[key]
    if not path then return nil end
    if self._img[path] == nil then
      local ok, im = pcall(require("src.render.Assets").image, path)
      self._img[path] = ok and im or false
    end
    return self._img[path] or nil
  end
  local pouch = img("berry_pouch")
  if pouch then
    local wobble = self.wobble and self.wobble > 0 and math.floor(math.sin(self.wobble * 0.8) * 2) or 0
    g.draw(pouch, 40 - 32 + wobble, 76 - 32)
  end
  local cc = art.colors or {}
  local function rgb(t, f) t = t or f return { t[1] / 255, t[2] / 255, t[3] / 255, 1 } end
  local white = rgb(cc.white, { 255, 255, 255 })
  local dark = rgb(cc.dark, { 98, 98, 98 })
  local light = rgb(cc.light, { 214, 214, 206 })
  local function text(s, x, y, ink, shadow, small)
    local faced = small and Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
    local two = Font.beginTwoTone(ink, shadow)
    if not two then g.setColor(ink) end
    Font.draw(s, x, y)
    if two then Font.endTwoTone() end
    if faced then Font.popFace() end
    g.setColor(1, 1, 1, 1)
  end
  local title = Strings("BERRY POUCH")
  local tb = self:box("title")
  text(title, tb.x + math.floor((72 - Font.width(title)) / 2), tb.y + 1, white, dark)

  local win = self:box("list")
  local rows = self:listRows()
  for i = 0, rows - 1 do
    local row = self.rows[self.top + i]
    if not row then break end
    local y = win.y + 2 + i * ROW_PITCH
    text(row.label, win.x + 9, y, dark, light)
    if not row.close and row.qty then
      text(Strings("×%3d", row.qty), win.x + 110, y + 2, dark, light, true)
    end
    if self.top + i == self.index then Font.drawCode(Theme.cursor, win.x + 1, y) end
  end

  local row = self:selected()
  local desc = self:box("description")
  local s = row and (row.close and Strings("The BERRY POUCH will be\nput away.") or row.description) or ""
  local y = desc.y + 2
  for line in (tostring(s) .. "\n"):gmatch("([^\n]*)\n") do
    text(line, desc.x, y, white, dark)
    y = y + 14
  end
  if row and not row.close then
    local ok, icon, quad, size = pcall(require("src.ui.Gen3BagMenu").itemIcon, { game = self.game }, row.id)
    if ok and icon then g.draw(icon, quad, 24 - math.floor(size / 2), 147 - math.floor(size / 2)) end
  end
  g.setColor(1, 1, 1, 1)
end

function Gen3BerryPouch:draw()
  love.graphics.setColor(1, 1, 1, 1)
  local field = self:background()
  local art = (self.game.data.constants or {}).gen3FRLGPocketArt
  if field and type(art) == "table" and art.images and art.images.berry_pouch then
    return self:drawFireRed(field, art)
  end
  if field then
    love.graphics.draw(field, 0, 0)
  else
    love.graphics.setColor(0.20, 0.45, 0.30, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  love.graphics.setColor(1, 1, 1, 1)
  panel(self, "title")
  panel(self, "list")
  panel(self, "description")

  local titleBox = self:box("title")
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("BERRY POUCH"), titleBox.x + 4, titleBox.y + 4)
  love.graphics.setColor(1, 1, 1, 1)

  drawRows(self)

  local row = self:selected()
  local desc = self:box("description")
  local D = (self:screen()).description or {}
  local pitch = tonumber(D.lineHeight) or 14
  local y = desc.y + (tonumber(D.y) or 3)
  local text = row and (row.close
                        and Strings("The BERRY POUCH will be\nput away.")
                        or row.description) or ""
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(line, desc.x + (tonumber(D.x) or 2), y)
    y = y + pitch
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3BerryPouch
