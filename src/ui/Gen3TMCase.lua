-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FIRERED'S TM CASE, a screen of its own (tm_case.c) -- not the bag at a
-- locked pocket, which is what opening TM CASE from the bag used to push.
--
-- Reported from play: "I see that many dialogue boxes are using the generic
-- or the emerald dialogue boxes instead of the OG firered ones" alongside a
-- direct ask for TM CASE and BERRY POUCH as real screens. The bag reuse drew
-- the shopkeeper's own backpack picture and pocket tabs behind a list of
-- TMs, which is not what a TM Case looks like on the cartridge at all.
--
-- WHAT THIS DRAWS FROM THE ROM (RomExtractorGen3:extractTMCaseScreen):
-- the case's own background in both palettes, and the real window
-- positions (list, description, title) out of tm_case.c's own
-- sWindowTemplates.
--
-- WHAT IS RECONSTRUCTED RATHER THAN EXTRACTED, and why that is a stated
-- line rather than an oversight: the disc sprite that slides in and out of
-- the case, and the type/power/accuracy/PP panel's icon sheet
-- (BlitMenuInfoIcon) -- both are their own small reverse-engineering jobs.
-- The INFORMATION survives: the move's type, power, accuracy and PP are
-- already in data/generated/moves.lua and are drawn as text labels here
-- instead of icons, and the list itself, the description (which for a TM
-- IS the move's own description -- ItemId_GetDescription -- not boilerplate
-- about technical machines), and the USE/GIVE/CLOSE actions are the real
-- thing.

local Font = require("src.render.Font")
local Bag = require("src.inventory.Bag")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3TMCase = {}
Gen3TMCase.__index = Gen3TMCase
Gen3TMCase.isOpaque = true

local GBA_W, GBA_H = 240, 160
local ROW_PITCH = 16

-- A dataset imported before this stage existed, or one where the sheet
-- could not be read: three drawn boxes rather than nothing.
local FALLBACK = {
  windows = {
    list = { x = 80, y = 8, width = 152, height = 80 },
    description = { x = 96, y = 96, width = 144, height = 64 },
    title = { x = 0, y = 8, width = 80, height = 16 },
  },
  list = { rows = 5 },
}

function Gen3TMCase:uiSize() return GBA_W, GBA_H end
function Gen3TMCase:wantsFillScale() return true end

function Gen3TMCase:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

function Gen3TMCase:screen()
  local r = (self.game.data.constants or {}).gen3TMCaseScreen
  if type(r) ~= "table" or type(r.windows) ~= "table" then return FALLBACK end
  return r
end

function Gen3TMCase:box(key)
  local r = self:screen()
  return r.windows[key] or FALLBACK.windows[key]
end

function Gen3TMCase:listRows()
  local r = self:screen()
  local n = math.floor(tonumber(r.list and r.list.rows) or FALLBACK.list.rows)
  return math.max(1, n)
end

-- TM01/HM01 in the small face, then the move's own name in the normal one --
-- GetTMNumberAndMoveString (tm_case.c), read off the item's own machine
-- record rather than the ROM's string table (the two agree: it is built
-- from the same item index and move name either way).
local function tmLabel(def)
  local n = def.machine and tonumber(def.machine.number) or 0
  local kind = (def.machine and def.machine.kind) or "TM"
  return ("%s%02d"):format(kind, n)
end

function Gen3TMCase:rebuild()
  local game, save = self.game, self.game.save
  local rows = {}
  for _, id in ipairs(Bag.order(save)) do
    local def = game.data.items and game.data.items[id]
    if def and def.machine then
      rows[#rows + 1] = {
        id = id, def = def,
        prefix = tmLabel(def),
        label = (game.data.moves and game.data.moves[def.machine.move]
                and game.data.moves[def.machine.move].name) or def.machine.move,
        qty = (save.inventory or {})[id],
        description = def.description or def.desc,
      }
    end
  end
  rows[#rows + 1] = { close = true, label = Strings("CLOSE") }
  self.rows = rows
  self.index = math.min(self.index or 1, #rows)
  self.top = math.max(1, math.min(self.top or 1, #rows - self:listRows() + 1))
end

function Gen3TMCase.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3TMCase)
  self.game = game
  self.onCancel = opts.onCancel
  self.index, self.top = 1, 1
  self:rebuild()
  return self
end

function Gen3TMCase:selected() return self.rows[self.index] end

function Gen3TMCase:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3TMCase:moveCursor(delta)
  local n = #self.rows
  if n == 0 then return end
  self.index = (self.index - 1 + delta) % n + 1
  local visible = self:listRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then
    self.top = self.index - visible + 1
  end
  Sound.play(self.game.data, "Press_AB") -- SE_SELECT (List_MoveCursorFunc)
end

-- USE teaches the move (the engine's own TM/HM flow, shared with the
-- ordinary bag -- a TM does the same thing from either screen); GIVE hands
-- the case to a party member; both come back here rather than to the bag.
function Gen3TMCase:choose()
  local row = self:selected()
  if not row or row.close then return self:close() end
  local Gen3ItemMenu = require("src.ui.Gen3ItemMenu")
  self.game.stack:push(Gen3ItemMenu.new(self.game, {
    entries = { { label = "USE", kind = "use" },
                { label = "GIVE", kind = "give" },
                { label = "EXIT", kind = "cancel" } },
    columns = 1,
    onPick = function(kind) self:act(kind, row.id) end,
  }))
end

function Gen3TMCase:act(kind, id)
  local game = self.game
  if kind == "use" then
    local ok, err = pcall(require("src.ui.BagMenu").useItem, game, nil, id, self)
    if not ok then
      require("src.core.Logger").warn("gen3 tm case: %s could not be used: %s",
                                      tostring(id), tostring(err))
    end
  elseif kind == "give" then
    local ok, err = pcall(require("src.ui.BagMenu").giveItem, game, id,
                          function() self:rebuild() end)
    if not ok then
      require("src.core.Logger").warn("gen3 tm case: %s could not be given: %s",
                                      tostring(id), tostring(err))
    end
  end
end

function Gen3TMCase:update()
  if self:frlgArt() then self:updateDisc() end
  local input = self.game.input
  if not input then return end
  if input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close()
  end
end

function Gen3TMCase:keypressed(key)
  if key == "down" then return self:moveCursor(1) end
  if key == "up" then return self:moveCursor(-1) end
  if key == "a" then return self:choose() end
  if key == "b" then return self:close() end
end

function Gen3TMCase:background()
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
    if row.close then
      Font.draw(row.label, itemX, y)
    else
      Font.draw(row.label, itemX + 40, y)
      local faced = Font.pushFace("small")
      Font.draw(row.prefix, itemX, y)
      if row.def and row.def.machine and row.def.machine.kind == "TM"
         and row.qty then
        local qty = Strings("x%03d", row.qty)
        Font.draw(qty, qtyX, y)
      end
      if faced then Font.popFace() end
    end
    if first + i == self.index then
      Font.drawCode(Theme.cursor, win.x + (tonumber(L.cursorX) or 0), y)
    end
  end
end

-- Draw one window's real 9-slice border at its extracted position.  Unlike
-- the ordinary bag screen, the TM Case's background PICTURE is mostly just
-- the case artwork and a floor strip -- none of its panel borders are baked
-- into the tilemap, so these are drawn every time, background or not.
local function panel(self, key)
  local b = self:box(key)
  Font.drawBox(math.floor(b.x / 8), math.floor(b.y / 8),
               math.floor(b.width / 8), math.floor(b.height / 8))
  return b
end

-- ---------------------------------------------------------------------------
-- FIRERED, LAYER BY LAYER (tm_case.c): BG2 the blue field, the disc OBJ, BG0
-- the text windows, BG1 the case over the disc's lower half.  The disc sinks
-- ten pixels a frame into the case and rises again when the cursor moves
-- (SpriteCB_SwapDisc), leaning left and down with the machine's number.
-- ---------------------------------------------------------------------------
local DISC_BASE_X, DISC_BASE_Y, DISC_DEPTH, DISC_STEP = 41, 46, 20, 10
local NUM_TMS, NUM_HMS = 50, 8

function Gen3TMCase:frlgArt()
  local r = (self.game.data.constants or {}).gen3FRLGPocketArt
  return (type(r) == "table" and r.images and r.images.tm_menu_male) and r or nil
end

function Gen3TMCase:frlgImage(key)
  local r = self:frlgArt()
  local path = r and r.images[key]
  if not path then return nil end
  self._img = self._img or {}
  if self._img[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self._img[path] = ok and img or false
  end
  return self._img[path] or nil
end

-- which disc the selected row shows, and where it stands
function Gen3TMCase:discFor(row)
  if not (row and row.def and row.def.machine) then return nil end
  local m = row.def.machine
  local n = tonumber(m.number) or 1
  local idx = (m.kind == "HM") and (n - 1) or (n - 1 + NUM_HMS)
  local total = NUM_TMS + NUM_HMS
  local move = self.game.data.moves and self.game.data.moves[m.move]
  local typeRow = 0
  local alias = { FIGHT = "FIGHTING", ELECTR = "ELECTRIC", PSYCHC = "PSYCHIC", TYPE_09 = "MYSTERY" }
  local name = move and tostring(move.type):upper()
  name = name and (alias[name] or name)
  for i, t in ipairs((self:frlgArt() or {}).types or {}) do
    if name == t then typeRow = i - 1 end
  end
  return { x = DISC_BASE_X - math.floor(14 * idx / total),
           y = DISC_BASE_Y + math.floor(8 * idx / total),
           hm = m.kind == "HM", typeRow = typeRow, id = row.id }
end

function Gen3TMCase:updateDisc()
  local want = self:discFor(self:selected())
  local d = self.disc
  if not d then
    self.disc = { shown = want, y2 = want and 0 or DISC_DEPTH }
    return
  end
  local same = (d.shown and d.shown.id) == (want and want.id)
  if not same then
    -- sink the old one, then swap and raise
    if d.shown and d.y2 < DISC_DEPTH then
      d.y2 = math.min(DISC_DEPTH, d.y2 + DISC_STEP)
      return
    end
    d.shown = want
    d.y2 = DISC_DEPTH
  end
  if d.shown and d.y2 > 0 then d.y2 = math.max(0, d.y2 - DISC_STEP) end
end

function Gen3TMCase:drawFireRed(art)
  local g = love.graphics
  local gender = (((self.game.save or {}).player or {}).gender == "girl") and "female" or "male"
  g.setColor(1, 1, 1, 1)
  local menu = self:frlgImage("tm_menu_" .. gender)
  if menu then g.draw(menu, 0, 0) end

  local d = self.disc
  local discs = self:frlgImage("discs")
  if discs and d and d.shown then
    local q = g.newQuad(d.shown.hm and 32 or 0, d.shown.typeRow * 32, 32, 32, discs:getDimensions())
    g.draw(discs, q, d.shown.x - 16, d.shown.y - 16 + d.y2)
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

  -- title window (0,1) 10x2, centred in 72 pixels
  local title = Strings("TM CASE")
  text(title, math.floor((72 - Font.width(title)) / 2), 8 + 1, white, dark)

  -- the list window (10,1) 19x10
  local L = { x = 80, y = 8 }
  local rows = self:listRows()
  local hmTag = self:frlgImage("hm_tag")
  for i = 0, rows - 1 do
    local row = self.rows[self.top + i]
    if not row then break end
    local y = L.y + 2 + i * ROW_PITCH
    if row.close then
      text(row.label, L.x + 8, y, dark, light)
    else
      local m = row.def.machine
      local hm = m.kind == "HM"
      local numX = L.x + 8 + (hm and 18 or 0)
      local number = hm and ("No%d"):format(tonumber(m.number) or 0)
                         or ("No%02d"):format(tonumber(m.number) or 0)
      text(number, numX, y + 2, dark, light, true)
      local faced = Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
      local w = Font.width(number .. " ")
      if faced then Font.popFace() end
      text(row.label, numX + w, y, dark, light)
      if hm and hmTag then
        g.draw(hmTag, L.x + 8, y + 2)
      elseif row.qty then
        text(Strings("×%3d", row.qty), L.x + 126, y + 2, dark, light, true)
      end
    end
    if self.top + i == self.index then
      Font.drawCode(Theme.cursor, L.x, y)
    end
  end

  -- the description window (12,12) 18x8
  local row = self:selected()
  local desc = row and (row.close and Strings("The TM CASE will be\nput away.") or row.description) or ""
  local y = 96 + 3
  for line in (tostring(desc) .. "\n"):gmatch("([^\n]*)\n") do
    text(line, 96 + 2, y, white, dark)
    y = y + 14
  end

  -- move info: the four label icons at (8,104), the values at (56,104)
  local Summary = require("src.ui.Gen3SummaryMenu")
  local srec = Summary.frlgRecord(self.game)
  local sheet
  if srec then
    local ok, img = pcall(require("src.render.Assets").image, srec.images.menu_info)
    sheet = ok and img or nil
  end
  local function icon(off, w, x, yy)
    if not sheet then return end
    g.draw(sheet, g.newQuad((off % 16) * 8, math.floor(off / 16) * 8, w, 12, sheet:getDimensions()), x, yy)
  end
  icon(0xA8, 40, 8, 104); icon(0xC0, 40, 8, 116); icon(0xC8, 40, 8, 128); icon(0xE0, 40, 8, 140)
  local move = row and not row.close and row.def and row.def.machine
               and self.game.data.moves and self.game.data.moves[row.def.machine.move]
  local function val(v, i) text(v, 56 + 7, 104 + 12 * i, dark, light) end
  if move then
    local off = srec and (srec.typeIcons or {})[tostring(move.type):upper()]
    if off then icon(off, 32, 56, 104) end
    val((move.power or 0) < 2 and "---" or ("%3d"):format(move.power), 1)
    val((move.accuracy or 0) == 0 and "---" or ("%3d"):format(move.accuracy), 2)
    val(("%3d"):format(move.pp or 0), 3)
  else
    for i = 0, 3 do val("---", i) end
  end

  -- BG1, over everything: the case
  local case = self:frlgImage("tm_case_" .. gender)
  if case then g.draw(case, 0, 0) end
  g.setColor(1, 1, 1, 1)
end

function Gen3TMCase:draw()
  local art = self:frlgArt()
  if art then return self:drawFireRed(art) end
  love.graphics.setColor(1, 1, 1, 1)
  local field = self:background()
  if field then
    love.graphics.draw(field, 0, 0)
  else
    love.graphics.setColor(0.15, 0.35, 0.55, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  love.graphics.setColor(1, 1, 1, 1)
  panel(self, "title")
  panel(self, "list")
  panel(self, "description")
  local infoLabels = panel(self, "moveInfoLabels")
  local infoBox = panel(self, "moveInfo")

  local titleBox = self:box("title")
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("TM CASE"), titleBox.x + 4, titleBox.y + 4)
  love.graphics.setColor(1, 1, 1, 1)

  drawRows(self)

  local row = self:selected()
  local desc = self:box("description")
  local D = (self:screen()).description or {}
  local pitch = tonumber(D.lineHeight) or 14
  local y = desc.y + (tonumber(D.y) or 3)
  local text = row and (row.close and Strings("The TM CASE will be\nput away.")
                        or row.description) or ""
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(line, desc.x + (tonumber(D.x) or 2), y)
    y = y + pitch
  end

  -- THE MOVE INFO PANEL, as text rather than the cartridge's icon sheet
  -- (see the header comment): the same four facts -- type, power, accuracy,
  -- PP -- in the same four rows, at the ROM's own window positions, drawn
  -- with the font instead of a picture.
  if row and not row.close and row.def and row.def.machine then
    local move = self.game.data.moves and self.game.data.moves[row.def.machine.move]
    if move then
      local faced = Font.pushFace("small")
      local function stat(i, label, value)
        Font.draw(label, infoLabels.x + 2, infoLabels.y + i * 12 + 2)
        Font.draw(tostring(value or "---"), infoBox.x + 2, infoBox.y + i * 12 + 2)
      end
      stat(0, "TYPE", move.type)
      stat(1, "POWER", (move.power or 0) > 1 and move.power or "---")
      stat(2, "ACC", (move.accuracy or 0) > 0 and move.accuracy or "---")
      stat(3, "PP", move.pp)
      if faced then Font.popFace() end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3TMCase
