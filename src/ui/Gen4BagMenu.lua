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
-- icons are one row of sixteen cells -- two per pocket, the second being the
-- pocket that is open.
--
-- THE PREVIOUS READING OF THAT SHEET IS WORTH KEEPING AS A WARNING.  It said
-- four by four on a sixteen-pixel grid, top eight cells 160 opaque pixels and
-- bottom eight 40, "the icons and the small markers" -- all true of the file
-- and none of it true of the cartridge.  The file had been laid out eight
-- tiles wide instead of thirty-two, so it held the right sixty-four tiles in
-- the wrong arrangement, and measuring it could only ever agree with itself.
-- A measurement of the output of a step you have not checked is a measurement
-- of that step, not of the cartridge.
--
-- THE TWO PLATES WERE ALSO THE WRONG WAY ROUND.  The grey plate is the
-- POCKET_INDICATOR window and holds the icons; the black panel beneath it is
-- the POCKET_NAMES window and holds the word.  This file had the name in the
-- grey plate and the icons in the black panel, which is why the name read as
-- grey-on-grey.  `Window_Add` settles it: indicator at tile (0, 11) and names
-- at tile (0, 13), which is pixel y 88 and y 104.
--
-- WHAT AN ITEM DOES IS NOT REIMPLEMENTED HERE.  Using, giving and tossing all
-- live in `BagMenu.useItem`, which is published for exactly this reason and is
-- what Emerald's bag calls too.  This screen is Platinum's list and Platinum's
-- words; it is not a second copy of what a Potion does.

local Bag = require("src.inventory.Bag")
local Font = require("src.render.Font")
local Gen4Palettes = require("src.render.Gen4Palettes")
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
  description = { x = 40, y = 146 },
  itemIcon = { x = 3, y = 150 },
}
local ROW_H = 16

-- THE POCKET STRIP, every number of it the cartridge's own.
--
--   * `BagUI_DrawPocketSelectorIcons` (src/applications/bag/windows.c) blits
--     from a bitmap declared `32 * POCKET_MAX` by 16: one row, thirty-two
--     pixels per pocket, the unfocused icon at `pocketType * 32` and the
--     focused one sixteen further along.  Only a 10x10 corner is blitted.
--   * `Window_Add` puts the POCKET_INDICATOR window at tile (0, 11), which is
--     pixel (0, 88), and the blit lands at y = 3 inside it.
--   * `Window_Add` puts POCKET_NAMES at tile (0, 13) = pixel (0, 104);
--     `PrintPocketNameCentered` writes at y = 2 inside it, centred on window
--     x = 146, and `BagUI_ClearPocketNameBox` shows window column 12
--     (x = 96) at screen column 0.  So the name is centred on screen x = 50.
--
-- The art agrees with the last of those without being asked to: the black
-- panel `bag_ui_main` paints runs from x 5 to x 96, whose centre is 50.
local ICON_BLIT = 10
local ICON_CELL = 16
local ICON_STRIDE = 32
local INDICATOR_Y = 88
local ICON_INSET = 3
local NAME_CENTER_X = 50
local NAME_Y = 106

-- WHERE THE SELECTED ITEM'S OWN ICON GOES.
-- `sBagUISpriteTemplates[BAG_SPRITE_ITEM]` is `{ .x = 22, .y = 172 }`, and a
-- DS sprite's template position is its CENTRE, so a 32x32 icon lands at
-- (6, 156) -- inside the white frame the art leaves at the bottom left.
-- Centred from the image's own size, so a re-extraction at another size
-- still lands.
local ITEM_ICON_X, ITEM_ICON_Y = 22, 172

-- THE CARTRIDGE'S TEXT COLOURS, which are not baked into the glyphs.
--
-- Platinum's font sheet carries ROLES, not colours: every pixel is 0 for
-- nothing, 1 for the letter or 2 for its shadow, and each printer call names
-- which palette entry each role takes.  The bag's text windows all use BG
-- palette 3 -- `main.c` loads it whole out of `bag_ui_main.NCLR` -- and asks
-- for three pairs out of it:
--
--   * TEXT_COLOR(1, 2, 0)    the pocket name, the item rows and their counts
--   * TEXT_COLOR(15, 14, 0)  the description strip
--   * TEXT_COLOR(8, 9, 0)    the count of an item being moved
--
-- THE CACHE PUBLISHES THESE NOW, which is what the note here used to call the
-- proper fix: `gen4_graphics.palettes` carries one hex string per palette file
-- and this screen's record names its own, so the three pairs below are read
-- out of `bag_ui_main.NCLR` at the entries the cartridge asks for.  What
-- remains written down is the SLOT AND THE TWO INDICES -- 3, and (1,2),
-- (15,14), (8,9) -- because those live in the bag's C code, not in any file
-- the importer can read.
--
-- THE WRITTEN-DOWN COLOURS WERE WRONG BY ONE, which is why this matters more
-- than tidiness.  Five of the six were a unit low in at least one channel:
-- the list ink is (16, 25, 33) and not (16, 24, 32), its shadow
-- (173, 189, 189) and not (172, 189, 189), and the moving pair
-- (165, 181, 206) / (107, 140, 181) rather than (164, 180, 205) /
-- (106, 139, 180).  They had been read off a decoder that FLOORED the
-- 5-bit-to-8-bit conversion where `Gen4Graphics` -- which composed every
-- picture on this screen -- ROUNDS it.  Only the description pair survived,
-- because 31 and 0 floor and round alike.  A one-unit error is invisible on
-- screen, and nothing was ever going to catch it.
--
-- These stay as the FALLBACK for a cache written before that stage, corrected
-- to the cartridge's own rounding.
local INK = {
  list = { { 16 / 255, 25 / 255, 33 / 255 },
           { 173 / 255, 189 / 255, 189 / 255 } },
  description = { { 1, 1, 1 }, { 0, 0, 0 } },
  moving = { { 165 / 255, 181 / 255, 206 / 255 },
             { 107 / 255, 140 / 255, 181 / 255 } },
}
-- Bank 3 of `bag_ui_main`, and the letter/shadow entries of each TEXT_COLOR.
local INK_SLOT = 3
local INK_ENTRIES = {
  list = { 1, 2 }, description = { 15, 14 }, moving = { 8, 9 },
}

-- THE SELECTED ROW'S OUTLINE IS A MASK, NOT A PICTURE.  `item_highlight`
-- carries ONE ink and no colour of its own -- it extracts as a white
-- silhouette because that is all it is -- and the cartridge paints it at
-- runtime: `BagUI_SetHighlightSpritesPalette` sets an OBJ palette slot on
-- both this and the pocket highlight, 1 in the ordinary state and 2 once an
-- item is picked and its action menu opens.
--
-- WHICH COLOURS THOSE SLOTS HOLD is settled by two things agreeing.  The
-- bag loads its sprite palettes in order -- the bag's own (one palette,
-- taking slot 0) then `ui_elements` (two, taking slots 1 and 2) -- so slot 1
-- is `ui_elements` sub-palette 0 and slot 2 is sub-palette 1.  And those are
-- the only two sub-palettes in the file with any colour in them at all:
-- sub-0 ink is (255, 0, 0) and sub-1 ink is (123, 123, 123), while sub-2
-- through sub-15 are entirely black.  Shift the mapping by one and the
-- action-menu highlight comes out black on a white list, and the red would
-- belong to nothing.
--
-- So: RED while you are choosing, grey while the action menu is up.  Only
-- the first is reachable here; this screen has no action menu yet.
local HIGHLIGHT = { { 1, 0, 0 }, { 123 / 255, 123 / 255, 123 / 255 } }

-- Two tones, not one: `Font.pushStyle` with both `text` and `shadow` restates
-- the letter's colour and leaves the shadow where the cartridge put it.  A
-- single-colour tint would paint letter and shadow the same and come out a
-- pixel thicker on two sides, which is what bold looks like.
function Gen4BagMenu:ink(which)
  local pair = (self.inkPairs and self.inkPairs[which]) or INK[which]
  Font.pushStyle({ text = pair[1], shadow = pair[2] })
end

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

  -- The bag's own three ink pairs, out of the cache when it carries palettes.
  -- All three or none: a cache that publishes one publishes all of them, and
  -- mixing a read pair with a written-down one would hide which is in use.
  local pairs_ = {}
  for which, at in pairs(INK_ENTRIES) do
    pairs_[which] = Gen4Palettes.text(game.data, "bag/bag_ui_main",
                                      INK_SLOT, at[1], at[2])
  end
  if pairs_.list and pairs_.description and pairs_.moving then
    self.inkPairs = pairs_
  end

  local menus = (game.data or {}).gen4_menus or {}
  local record = menus.bag or {}
  -- Only the plates measured off the art come from the cache.  The pocket
  -- strip and the pocket name do not, because both are arithmetic over the
  -- number of pockets this bag was opened with; see `iconRow` below.
  self.layout = record.layout or LAYOUT
  if not self.layout.list then self.layout = LAYOUT end
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
  --
  -- AN EXACT NAME BEATS A CONTAINING ONE, because these names contain each
  -- other: "ITEMS" is inside "BATTLE ITEMS" and "KEY ITEMS" as well as being
  -- a pocket of its own.  A loop that simply kept the last substring hit sent
  -- every bag opened at ITEMS to KEY ITEMS, and BERRIES -- which nothing else
  -- contains -- went on landing correctly, so the fault could only be seen by
  -- opening at a name that is a substring of another.
  self.pocket = 1
  if opts.pocket then
    local wanted = tostring(opts.pocket):upper()
    local exact, loose
    for i, name in ipairs(self.pockets) do
      local upper = tostring(name):upper()
      if upper == wanted then
        exact = exact or i
      elseif upper:find(wanted, 1, true) then
        loose = loose or i
      end
    end
    self.pocket = exact or loose or 1
    self.lockPocket = true
  end

  self.index, self.top = 1, 1
  self:rebuild()
  return self
end

-- WHOSE BAG THIS IS.  `Gen4RowanIntro` writes `save.player.gender`; anything
-- absent reads as the boy, which is the cartridge's default before the
-- question is asked.
function Gen4BagMenu:female()
  local player = (self.game.save or {}).player or {}
  local g = player.gender
  return g == "girl" or g == "female" or g == 1
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
        -- The NUMERIC id, which is what names the icon.  `id` here is
        -- whatever key the inventory used and is a string on this cache;
        -- the record's own `id` is the cartridge's number.
        iconId = def and tonumber(def.id) or tonumber(id),
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
  if self.closed then return end
  self.closed=true
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
  if self.closed then return end
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
    close = function() self:close() end,
    refresh = function() self:rebuild() end,
  }
  local ok, err = pcall(function()
    require("src.ui.BagMenu").useItem(self.game, self.battle, row.id, shim)
  end)
  if not ok then
    Logger.warn("gen4 bag: %s could not be used: %s", tostring(row.id), tostring(err))
  end
  if not self.closed then self:rebuild() end
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

-- WHERE THE STRIP STARTS AND HOW FAR APART IT SITS is worked out at runtime
-- rather than written down, because the count varies: the field bag carries
-- eight pockets and the battle bag five, and the cartridge re-spreads the row
-- to fill the same ninety pixels either way.  `CalcPocketSelectorIconsPos`
-- (src/applications/bag/main.c):
--
--     pocketSelectorIconsX = 6 + (90 - 10 * numPockets) / (numPockets + 1)
--     spacing              = 10 + pocketSelectorIconsX - 6
--
-- Integer division, so eight pockets give x = 7 and a pitch of 11 -- eight
-- ten-pixel icons ending at 94, inside the ninety the art leaves.
function Gen4BagMenu:iconRow()
  local n = #self.pockets
  local x = 6 + math.floor((90 - ICON_BLIT * n) / (n + 1))
  return x, ICON_BLIT + x - 6
end

function Gen4BagMenu:drawPocketIcons()
  local g = love.graphics
  local sheet = self:img("bag/pocket_selector_icons")
  if not sheet then return end
  local sw, sh = sheet:getDimensions()

  -- A CACHE FROM BEFORE THE SHEET'S WIDTH WAS KNOWN HOLDS A DIFFERENT
  -- PICTURE, not a smaller one: the same sixty-four tiles, laid eight wide
  -- instead of thirty-two.  Nothing about it is missing, so nothing about it
  -- fails -- it simply draws as soup.  Say so once and draw nothing, because
  -- an empty strip is a question and a strip of soup is a wrong answer.
  if sh ~= ICON_CELL or sw < ICON_STRIDE * #self.pockets then
    if not self.warnedIcons then
      self.warnedIcons = true
      Logger.warn("gen4 bag: pocket_selector_icons is %dx%d, not %dx%d -- the bag archive needs re-importing", sw, sh,
                  ICON_STRIDE * #self.pockets, ICON_CELL)
    end
    return
  end

  local x0, pitch = self:iconRow()
  local y = INDICATOR_Y + ICON_INSET
  g.setColor(1, 1, 1, 1)
  for i = 1, #self.pockets do
    -- The pocket's own pair of cells; the open pocket takes the second.
    local sx = (i - 1) * ICON_STRIDE + (i == self.pocket and ICON_CELL or 0)
    local quad = g.newQuad(sx, 0, ICON_BLIT, ICON_BLIT, sw, sh)
    g.draw(sheet, quad, x0 + pitch * (i - 1), y)
  end
end

function Gen4BagMenu:draw()
  local g = love.graphics
  g.setColor(0.06, 0.07, 0.12, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  -- FOUR LAYERS, IN THE CARTRIDGE'S ORDER.  `main.c` puts `item_list_border`
  -- on BG_LAYER_MAIN_3, the item list and the pocket name on MAIN_2,
  -- `bag_ui_main` on MAIN_1 and the pocket icons, the description and the
  -- message boxes on MAIN_0 -- and a DS layer's priority counts DOWN towards
  -- the front, so the art is drawn OVER the list text and the white panel
  -- UNDER it.
  --
  -- THE WHITE PANEL IS WHY THE TEXT WAS A GHOST.  `bag_ui_main` leaves the
  -- item list and the pocket name box as HOLES -- 1456 of the name box's 1472
  -- pixels are transparent -- and this file drew nothing behind either, so
  -- both came out the clear colour above.  Platinum's text there is a
  -- near-black letter with a light shadow: on `item_list_border`'s white it
  -- reads as ordinary dark text, and on near-black it reads as the shadow
  -- alone, which is exactly how it looked.
  local panel = self:img("bag/item_list_border")
  if panel then g.draw(panel, 0, 0) end

  -- MAIN_2: the pocket name, centred in its box -- not in the grey plate
  -- above it, which is where the icons go.
  local name = tostring(self.pockets[self.pocket] or "")
  self:ink("list")
  Font.draw(name, math.floor(NAME_CENTER_X - Font.width(name) / 2), NAME_Y)

  -- MAIN_2: the list.
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
        -- THE CELL IS TALLER THAN THE ROW IT MARKS.  `item_highlight_cell`
        -- is 152x32 with the outline itself seventeen rows inside it, and a
        -- list row is MAX_LETTER_HEIGHT -- sixteen.  Centring the cell on
        -- the row is that difference rather than a nudge that looked right,
        -- and it is taken from the image so a re-extraction at another cell
        -- size still lands.
        local paint = HIGHLIGHT[1]
        g.setColor(paint[1], paint[2], paint[3], 1)
        g.draw(highlight, list.x - 4,
               y + (ROW_H - highlight:getHeight()) / 2)
        g.setColor(1, 1, 1, 1)
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
  Font.popStyle()

  -- MAIN_1: the art itself, which clips both boxes to their own shape.
  local back = self:img("bag/bag_ui_main")
  if back then
    g.setColor(1, 1, 1, 1)
    g.draw(back, 0, 0)
  elseif not panel then
    Font.drawBox(0, 0, 32, 24)
  end

  -- THE BAG ITSELF, WHICH THE ART LEAVES A SHADOW FOR AND NOTHING DREW.
  --
  -- `bag_ui_main` paints a shadow on the blue panel with nothing above it,
  -- because the sixteen `bag_sprite_male_00..07` / `bag_sprite_female_00..07`
  -- frames in the cache were never referenced by this file at all.  Eight per
  -- gender is ONE PER POCKET -- the cartridge turns the bag to whichever
  -- pocket is open.
  --
  -- BOTH NUMBERS ARE THE CARTRIDGE'S, not placed by eye against the shadow:
  --
  --   * `src/applications/bag/sprites.c`, `sBagUISpriteTemplates`:
  --     `[BAG_SPRITE_BAG] = { .x = 48, .y = 50, ... }`.
  --   * `src/applications/bag/main.c` selects the animation with the bare
  --     pocket -- `ManagedSprite_SetAnim(sprites[BAG_SPRITE_BAG],
  --     pocketType)` at three sites -- so the frame IS the pocket, 0-based,
  --     which is the same 0-based enum `rebuild` already matches against.
  --
  -- A DS sprite's template position is its CENTRE, so a 64x64 frame lands at
  -- (48 - 32, 50 - 32).  Drawn from the sheet's own size rather than a
  -- written-down 64, so a re-extraction at another size still centres.
  local bag = self:img(("bag/bag_sprite_%s_%02d")
                       :format(self:female() and "female" or "male",
                               math.max(0, self.pocket - 1)))
  if bag then
    g.setColor(1, 1, 1, 1)
    g.draw(bag, 48 - bag:getWidth() / 2, 50 - bag:getHeight() / 2)
  end

  -- MAIN_0: the pocket strip and the description strip.
  self:drawPocketIcons()

  local row = self:selected()

  -- THE ITEM'S OWN ICON.  One picture per ITEM rather than per sprite,
  -- because a third of the items borrow another's shape and recolour it --
  -- see `Gen4ItemIcons`.  Absent until the icon archive has been imported,
  -- and an empty frame is the honest state until then.
  local icon = row and row.iconId
                and self:img(("items/icon_%03d"):format(row.iconId))
  if icon then
    g.setColor(1, 1, 1, 1)
    g.draw(icon, ITEM_ICON_X - icon:getWidth() / 2,
           ITEM_ICON_Y - icon:getHeight() / 2)
  end

  local text = (row and row.description) or ""
  local y = self.layout.description.y
  self:ink("description")
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    if y > H - 8 then break end
    Font.draw(Font.fit(line, W - self.layout.description.x - 4),
              self.layout.description.x, y)
    y = y + 14
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

return Gen4BagMenu
