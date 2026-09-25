-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's BAG, which was falling back to Kanto's.
--
-- EIGHT POCKETS, not five.  Gen 1-3 have four or five; Platinum has ITEMS,
-- MEDICINE, POKé BALLS, TMs & HMs, BERRIES, MAIL, BATTLE ITEMS and KEY ITEMS,
-- and every one of those words is bank 395's, in the order an item record's
-- own `fieldPocket` numbers them.  The bank index IS the pocket number, so
-- nothing here pairs the two by hand.
--
-- WHICH POCKET AN ITEM IS IN is the item's own `fieldPocket`, and getting to
-- read that at all took fixing the item table: the name bank has 468 entries
-- and the data archive 446, so a member index is the item id only up to 112
-- and is off by twenty-two after that.  Before that fix this screen would have
-- put the Bicycle, the Town Map and the Old Rod in with the TMs -- see
-- `Gen4Items.checkPockets`, which now passes 445 of 445.
--
-- THE ART IS THE CARTRIDGE'S: `bag/bag_ui_main` is the screen, and the pocket
-- icons are one 64x64 sheet of sixteen-pixel cells whose top eight are the
-- icons and whose bottom eight are the small markers under an unselected one.
-- That split was measured rather than assumed -- on a sixteen-pixel grid the
-- top eight cells carry 160 opaque pixels each and the bottom eight carry 40.
--
-- WHAT AN ITEM DOES IS NOT REIMPLEMENTED HERE.  Using, giving and tossing all
-- live in `BagMenu.useItem`, which is published for exactly this reason and is
-- what Emerald's bag calls too.  This screen is Platinum's list and Platinum's
-- words; it is not a second copy of what a Potion does.

local Bag = require("src.inventory.Bag")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4BagMenu = {}
Gen4BagMenu.__index = Gen4BagMenu
Gen4BagMenu.isOpaque = true

local W, H = 256, 192

-- Where the screen puts things, off `bag/bag_ui_main` itself.  Carried in the
-- cache (`gen4_menus.bag.layout`) so a re-import can correct it without a code
-- change; these are the fallback for a cache written before that.
local LAYOUT = {
  list = { x = 108, y = 8, w = 142, h = 122 },
  pocketName = { x = 6, y = 88, w = 90 },
  pocketIcons = { x = 6, y = 106 },
  description = { x = 40, y = 146 },
  itemIcon = { x = 3, y = 150 },
}
local ROW_H = 16
local ICON = 16
local ICON_COLUMNS = 4

function Gen4BagMenu:uiSize() return W, H end
function Gen4BagMenu:wantsFillScale() return true end
function Gen4BagMenu:wantsEdgeBleed() return false end

function Gen4BagMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4BagMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4BagMenu)
  self.game = game
  self.onCancel = opts.onCancel
  self.onPick = opts.onPick
  self.pick = opts.pick and true or false
  self.battle = opts.battle
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}

  local menus = (game.data or {}).gen4_menus or {}
  local record = menus.bag or {}
  self.layout = record.layout or LAYOUT
  self.iconSize = record.icon or ICON
  self.iconColumns = record.iconColumns or ICON_COLUMNS
  self.pockets = record.pockets
  if not self.pockets or #self.pockets == 0 then
    Logger.warn("gen4 bag: this cache carries no pocket names -- "
                .. "falling back to the engine's own")
    self.pockets = { Strings("ITEMS"), Strings("MEDICINE"), "POKé BALLS",
                     "TMs & HMs", Strings("BERRIES"), Strings("MAIL"),
                     Strings("BATTLE ITEMS"), Strings("KEY ITEMS") }
  end

  -- A bag opened AT ONE POCKET stays there: the berry tree asking which berry
  -- you are planting has no business offering the TM case.
  self.pocket = 1
  if opts.pocket then
    local wanted = tostring(opts.pocket):upper()
    for i, name in ipairs(self.pockets) do
      if tostring(name):upper():find(wanted, 1, true) then self.pocket = i end
    end
    self.lockPocket = true
  end

  self.index, self.top = 1, 1
  self:rebuild()
  return self
end

function Gen4BagMenu:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- The rows of the pocket that is open, in acquisition order -- which is what
-- `Bag.order` walks and what the cartridge's own list does.
function Gen4BagMenu:rebuild()
  local game = self.game
  local want = self.pocket - 1
  local rows = {}
  for _, id in ipairs(Bag.order(game.save) or {}) do
    local def = game.data.items and game.data.items[id]
    -- `fieldPocket` is the cartridge's; an item with none at all (a dataset
    -- from another generation, or an id this cartridge does not have) counts
    -- as ITEMS rather than disappearing.
    local pocket = def and def.fieldPocket or 0
    if pocket == want then
      rows[#rows + 1] = {
        id = id,
        label = (def and def.name) or tostring(id),
        qty = (game.save.inventory or {})[id],
        description = def and def.description,
        -- KEY ITEMS and MAIL are never thrown away, which the record says
        -- outright rather than the pocket implying it.
        important = def and def.preventToss or nil,
      }
    end
  end
  rows[#rows + 1] = { close = true, label = Strings("CLOSE BAG") }
  self.rows = rows
  self.index = math.max(1, math.min(self.index, #rows))
  self:clampScroll()
end

function Gen4BagMenu:listRows()
  return math.max(1, math.floor(self.layout.list.h / ROW_H))
end

function Gen4BagMenu:clampScroll()
  local visible = self:listRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then self.top = self.index - visible + 1 end
  self.top = math.max(1, math.min(self.top, math.max(1, #self.rows - visible + 1)))
end

function Gen4BagMenu:selected() return self.rows[self.index] end

function Gen4BagMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4BagMenu:movePocket(delta)
  if self.lockPocket then return end
  self.pocket = (self.pocket - 1 + delta) % #self.pockets + 1
  self.index, self.top = 1, 1
  self:rebuild()
end

function Gen4BagMenu:choose()
  local row = self:selected()
  if not row or row.close then return self:close() end

  -- A bag opened to ANSWER A QUESTION hands the answer back and closes.
  if self.pick then
    self.game.stack:pop()
    if self.onPick then self.onPick(row.id) end
    return
  end

  -- Everything else is the engine's own item flow, in battle and out of it.
  -- The shim is what `BagMenu.useItem` expects of a list; rebuilding after it
  -- is what makes a consumed item leave this screen.
  local shim = {
    items = {}, index = 1,
    close = function() end,
    refresh = function() self:rebuild() end,
  }
  local ok, err = pcall(function()
    require("src.ui.BagMenu").useItem(self.game, self.battle, row.id, shim)
  end)
  if not ok then
    Logger.warn("gen4 bag: %s could not be used: %s", tostring(row.id), tostring(err))
  end
  self:rebuild()
end

function Gen4BagMenu:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("up") then
    self.index = (self.index - 2) % #self.rows + 1
    self:clampScroll()
  elseif input:wasPressed("down") then
    self.index = self.index % #self.rows + 1
    self:clampScroll()
  elseif input:wasPressed("left") then
    self:movePocket(-1)
  elseif input:wasPressed("right") then
    self:movePocket(1)
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
end

-- ------------------------------------------------------------------- draw --

function Gen4BagMenu:drawPocketIcons()
  local g = love.graphics
  local sheet = self:img("bag/pocket_selector_icons")
  if not sheet then return end
  local sw, sh = sheet:getDimensions()
  local size, columns = self.iconSize, self.iconColumns
  local at = self.layout.pocketIcons
  for i = 1, math.min(#self.pockets, 8) do
    local cell = i - 1
    -- The icon itself; the small marker for the same pocket sits two rows
    -- down in the same sheet.
    local row = math.floor(cell / columns) + (i == self.pocket and 0 or 2)
    local quad = g.newQuad((cell % columns) * size, row * size, size, size, sw, sh)
    local x = at.x + (cell % columns) * (size + 2)
    local y = at.y + math.floor(cell / columns) * (size + 2)
    g.setColor(1, 1, 1, i == self.pocket and 1 or 0.75)
    g.draw(sheet, quad, x, y)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4BagMenu:draw()
  local g = love.graphics
  g.setColor(0.06, 0.07, 0.12, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local back = self:img("bag/bag_ui_main")
  if back then
    g.draw(back, 0, 0)
  else
    Font.drawBox(0, 0, 32, 24)
  end

  -- The pocket's name, in the plate the art leaves for it.
  local name = tostring(self.pockets[self.pocket] or "")
  Font.draw(name, self.layout.pocketName.x + 2, self.layout.pocketName.y)
  self:drawPocketIcons()

  -- The list.
  local list = self.layout.list
  local visible = self:listRows()
  local highlight = self:img("bag/item_highlight")
  for slot = 0, visible - 1 do
    local i = self.top + slot
    local row = self.rows[i]
    if not row then break end
    local y = list.y + slot * ROW_H
    if i == self.index then
      if highlight then
        g.setColor(1, 1, 1, 1)
        g.draw(highlight, list.x - 4, y - 2)
      else
        Font.drawCode(Theme.cursor, list.x - 8, y)
      end
    end
    Font.draw(Font.fit(row.label, list.w - 40), list.x, y)
    if row.qty and not row.close then
      local text = ("x%d"):format(row.qty)
      Font.draw(text, list.x + list.w - Font.width(text) - 2, y)
    end
  end

  -- The description, in the strip the art leaves along the bottom.
  local row = self:selected()
  local text = (row and row.description) or ""
  local y = self.layout.description.y
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    if y > H - 8 then break end
    Font.draw(Font.fit(line, W - self.layout.description.x - 4),
              self.layout.description.x, y)
    y = y + 14
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4BagMenu
