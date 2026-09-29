-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's KEYBOARD, which was falling back to the Game Boy's.
--
-- Reported from play: "the keyboard where you type your name or your pokemons
-- nickname is also not correct for gen4 platinum its falling back to gen1".
-- It was: nothing in GEN4_ALIASES named `NamingScreen`, so every prompt --
-- the player's name, the rival's, a nickname, a box -- opened Kanto's.
--
-- THE GRID IS THE CARTRIDGE'S, read out of applications/naming_screen.c
-- rather than eyeballed: SIX ROWS OF THIRTEEN, where row 0 is the HOME ROW of
-- buttons and rows 1 to 5 are the characters.  `NamingScreen_LoadKeyboardLayout`
-- builds exactly that -- `sHomeRowLayouts[page]` into row 0 and
-- `sCharCodes[page][0..4]` into the rest -- and the three English pages are
-- UPPER, lower and OTHERS.
--
-- THE HOME ROW REPEATS ITS BUTTONS ACROSS CELLS, and that is not padding: it
-- is how a button two or three cells wide is navigated with a d-pad.  UPPER
-- takes cells 1-2, lower 3-4, OTHERS 5-6, the space/skip key 7-8, BACK 9-11
-- and OK 12-13.  Kept as the cartridge writes it, so the cursor moves through
-- them the way it does on hardware.
--
-- THE PICTURES ARE THE CARTRIDGE'S NOW, and so is the geometry.  Reported from
-- play after the first version of this screen: it "still needs a lot of work
-- before it matches the platinum rom".  It did, and the reason was that
-- `/data/namein.narc` had never been opened -- so the layout was Platinum's and
-- everything a player looks at was a guess.  `Gen4Naming` reads it now, and
-- with it the screen stops guessing:
--
--   * THE BACKDROP AND THE PANEL are composed pictures, one panel per page.
--   * THE PANEL SITS WHERE THE APP PARKS IT.  Its layer rests at background
--     offset (-11, -80), and an offset scrolls the VIEW, so the picture is at
--     screen (11, 80).
--   * THE CHARACTER GRID IS THIRTEEN BY FIVE, not thirteen by six, in cells
--     SIXTEEN BY NINETEEN, not sixteen square.  `Window_Add(..., 2, 1, 26, 12,
--     ...)` is the rectangle and `NamingScreen_InitializeCharsGraphics` is the
--     pitch: five `PrintChars` calls at `i * 19 + 4`.  The home row is not in
--     that window at all -- it is sprites, above the panel.
--   * THE KEYBOARD IS A CHECKERBOARD, painted by code in two palette indices
--     per page rather than stored in the tilemap, which is why opening the
--     archive alone would still have left a frame with nothing in it.
--
-- WHAT IS STILL NOT THE CARTRIDGE'S, said plainly rather than quietly skipped:
-- the home row's BUTTON ART and the CURSOR.  Both are the sprite cell bank at
-- members 10/12/14, and composing one is a different job from composing a
-- tilemap.  They are the engine's own frames, drawn at the cartridge's own
-- positions.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen4NamingScreen = {}
Gen4NamingScreen.__index = Gen4NamingScreen
Gen4NamingScreen.isOpaque = true

local W, H = 256, 192

Gen4NamingScreen.ROWS = 6
Gen4NamingScreen.COLS = 13

-- The home row, cell for cell.  A repeated name is one button spanning those
-- cells; the drawing merges them and the cursor does not.
local HOME = {
  "upper", "upper", "lower", "lower", "others", "others",
  "space", "space", "back", "back", "back", "ok", "ok",
}

-- WHAT EACH BUTTON SAYS, AND THESE WORDS ARE THE PORT'S.  The cartridge's home
-- row is six wordless pictures out of the sprite bank, which is not composed
-- here -- so there is nothing to copy and something has to be written.  They
-- are short because the buttons are two cells wide (three for BACK), and a
-- label that does not fit its own button is the fault this screen was reported
-- for in the first place.
local LABEL = {
  upper = "A-Z", lower = "a-z", others = "SYM",
  space = "SPC", back = "BACK", ok = "OK",
}

-- The three English pages, five rows of thirteen each.  `sCharCodesUpper0..4`
-- and their lower and OTHERS counterparts, with the cartridge's CHAR_SPACE
-- written as an empty cell -- a blank key is a real key on this keyboard and
-- pressing it types nothing, which is what the cartridge does with it.
local PAGES = {
  {
    id = "upper", label = "UPPER",
    rows = {
      { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "", ",", "." },
      { "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "", "'", "-" },
      { "U", "V", "W", "X", "Y", "Z", "", "", "", "", "", "♂", "♀" },
      { "", "", "", "", "", "", "", "", "", "", "", "", "" },
      { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "", "", "" },
    },
  },
  {
    id = "lower", label = "lower",
    rows = {
      { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "", ",", "." },
      { "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "", "'", "-" },
      { "u", "v", "w", "x", "y", "z", "", "", "", "", "", "♂", "♀" },
      { "", "", "", "", "", "", "", "", "", "", "", "", "" },
      { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "", "", "" },
    },
  },
  {
    id = "others", label = "OTHERS",
    rows = {
      { ",", ".", ":", ";", "!", "?", "", "", "", "♂", "♀", "", "" },
      { "\"", "\"", "'", "'", "(", ")", "", "", "", "", "", "", "" },
      { "…", "·", "~", "@", "#", "%", "+", "-", "*", "/", "=", "", "" },
      { "◎", "○", "□", "△", "◇", "♠", "♥", "♦", "♣", "★", "♪", "", "" },
      { "☀", "☁", "☂", "☃", "☺", "☻", "☹", "☻", "Ｚ", "↑", "↓", "", "" },
    },
  },
}

-- WHERE EVERYTHING SITS, and every number is the cartridge's.
--
-- The previous version of this file put the grid at (24, 64) on sixteen-square
-- cells and said so in a comment about multiples of eight.  The multiples of
-- eight were a real fix -- `Font.drawBox` takes TILES and `Font.draw` takes
-- PIXELS, and a layout that is not a whole number of tiles puts every box a
-- fraction of a tile from the text inside it, which is what "text is outside of
-- boxes" was.  But it was a fix to a layout that was invented.  This one is
-- read, and it is not all multiples of eight, because the cartridge's is not:
-- the rows are NINETEEN pixels.  The boxes are gone with the guess, so nothing
-- rounds any more.
local PANEL_X, PANEL_Y = 11, 80
local GRID_X, GRID_Y = PANEL_X + 2 * 8, PANEL_Y + 1 * 8   -- 27, 88
local CELL_W, CELL_H = 16, 19
local CHAR_ROWS = 5
local GLYPH_INSET = 4

-- The home row, at the y its sprites use and on the keyboard's own column
-- pitch from the x its first sprite uses.  See Gen4Naming for why those two
-- numbers are the whole arrangement.
local HOME_X, HOME_Y, HOME_H = 4, 0x44, 16

-- THE PROMPT AND THE TYPED NAME ARE ON THE OTHER SCREEN on hardware: the
-- keyboard is the top screen and `LoadMessageBoxGraphics` puts the message box
-- on BG_LAYER_SUB_0.  With one screen they go above the keyboard, in the space
-- the panel does not use, and those two positions are this port's and are the
-- only positions on this screen that are.
local TITLE_Y = 8
local ENTRY_Y = 32

-- The checkerboard, when the cache has no colours for it.  Deliberately drab:
-- a stand-in that looks like a choice is a stand-in nobody replaces.
local FALLBACK_BG = { 0.24, 0.27, 0.36 }
local FALLBACK_ALT = { 0.19, 0.22, 0.30 }

function Gen4NamingScreen:uiSize() return W, H end
function Gen4NamingScreen:wantsFillScale() return true end
function Gen4NamingScreen:wantsEdgeBleed() return false end

function Gen4NamingScreen:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4NamingScreen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4NamingScreen)
  self.game = game
  -- The same options the Game Boy screen takes, because the alias has to serve
  -- every existing call site unchanged.
  self.title = opts.title or Strings("YOUR NAME?")
  self.maxLen = opts.maxLen or 7
  self.onDone = opts.onDone
  self.kind = opts.kind
  self.species = opts.species or (opts.mon and opts.mon.species)

  self.glyphs = {}
  for ch in tostring(opts.default or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #self.glyphs < self.maxLen then self.glyphs[#self.glyphs + 1] = ch end
  end

  self.page = 1
  self.row, self.col = 1, 1   -- 1 is the home row; 2..6 are the characters

  self.art = (game.data or {}).gen4_naming or nil
  self.cache = {}
  if not self.art then
    Logger.warn("gen4 naming screen: this cache carries no `gen4_naming` "
                .. "record -- the keyboard is drawn in the engine's own frame")
  end
  return self
end

-- One of the cache's pictures.  The record is `{ path, width, height, ... }`.
function Gen4NamingScreen:img(entry)
  local path = (type(entry) == "table" and entry.path) or entry
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- The two colours this page's checkerboard is painted in.  `bgColour` and
-- `altColour` are INDICES into the window's palette row and `colours` is that
-- row, so a cache with the pictures but no palette still gets a keyboard --
-- in the fallback colours, which is visibly a fallback.
function Gen4NamingScreen:checkerColours()
  local art = self.art or {}
  local list = art.colours
  local function colour(indices, fallback)
    local index = indices and indices[self.page]
    local rgb = index and list and list[index + 1]
    if type(rgb) == "table" and rgb[1] then return rgb end
    return fallback
  end
  return colour(art.bgColour, FALLBACK_BG), colour(art.altColour, FALLBACK_ALT)
end

-- What is in a cell, as { kind = "button"|"char", value = ... }.
function Gen4NamingScreen:cell(row, col)
  if row == 1 then
    local id = HOME[col]
    return id and { kind = "button", value = id } or nil
  end
  local page = PAGES[self.page]
  local line = page and page.rows[row - 1]
  local ch = line and line[col]
  if ch == nil then return nil end
  return { kind = "char", value = ch }
end

function Gen4NamingScreen:close(name)
  self.game.stack:pop()
  if self.onDone then self.onDone(name) end
end

function Gen4NamingScreen:typed()
  return table.concat(self.glyphs)
end

function Gen4NamingScreen:press(cell)
  if not cell then return end
  if cell.kind == "char" then
    -- A BLANK KEY IS A REAL KEY and types nothing, which is what the
    -- cartridge's CHAR_SPACE cells do in the middle of a page.
    if cell.value ~= "" and #self.glyphs < self.maxLen then
      self.glyphs[#self.glyphs + 1] = cell.value
    end
    return
  end
  local id = cell.value
  if id == "upper" then self.page = 1
  elseif id == "lower" then self.page = 2
  elseif id == "others" then self.page = 3
  elseif id == "space" then
    if #self.glyphs < self.maxLen then self.glyphs[#self.glyphs + 1] = " " end
  elseif id == "back" then
    if #self.glyphs > 0 then self.glyphs[#self.glyphs] = nil end
  elseif id == "ok" then
    self:close(self:typed())
  end
end

function Gen4NamingScreen:move(dx, dy)
  local rows, cols = Gen4NamingScreen.ROWS, Gen4NamingScreen.COLS
  if dy ~= 0 then
    self.row = (self.row - 1 + dy) % rows + 1
  end
  if dx ~= 0 then
    if self.row == 1 then
      -- OFF THE BUTTON IN ONE STEP.  A button three cells wide would otherwise
      -- take three presses to leave, which is not how it behaves on hardware:
      -- the cursor sits on the BUTTON, so moving means moving to the next one.
      local id = HOME[self.col]
      local col = self.col
      repeat
        col = (col - 1 + dx) % cols + 1
      until HOME[col] ~= id or col == self.col
      self.col = col
    else
      self.col = (self.col - 1 + dx) % cols + 1
    end
  end
  -- Landing on the home row from a character row keeps the column, which can
  -- be in the middle of a wide button; that is fine, because the button is
  -- selected by span rather than by its first cell.
end

function Gen4NamingScreen:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("left") then self:move(-1, 0) end
  if input:wasPressed("right") then self:move(1, 0) end
  if input:wasPressed("up") then self:move(0, -1) end
  if input:wasPressed("down") then self:move(0, 1) end
  if input:wasPressed("a") then self:press(self:cell(self.row, self.col)) end
  if input:wasPressed("b") then
    if #self.glyphs > 0 then self.glyphs[#self.glyphs] = nil end
  end
  if input:wasPressed("start") then self:close(self:typed()) end
end

-- ------------------------------------------------------------------- draw --

-- The selection, and the page you are on, drawn BEHIND whatever sits in the
-- cell so neither one covers the other. Colours only; the frame is already
-- there.
-- A BOX IN PIXELS.  `Font.drawBox` takes TILE coordinates, and this screen's
-- rows are nineteen pixels tall because the cartridge's are -- so a tile box
-- cannot land on one.  Rounding the cells to eight to suit the box is what the
-- previous version did, and it made the layout wrong in order to make the
-- drawing tidy.  The box is drawn in pixels instead.
local function frame(x, y, w, h)
  local g = love.graphics
  g.setColor(0.08, 0.10, 0.16, 0.72)
  g.rectangle("fill", x, y, w, h)
  g.setColor(0.86, 0.88, 0.94, 1)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  g.setColor(1, 1, 1, 1)
end

local function highlight(x, y, w, h, selected, active)
  local g = love.graphics
  if selected then
    g.setColor(0.98, 0.83, 0.30, 0.85)
  elseif active then
    g.setColor(0.35, 0.47, 0.78, 0.60)
  else
    return
  end
  g.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
  g.setColor(1, 1, 1, 1)
end

-- THE HOME ROW, in the engine's frame because its art is a sprite bank this
-- port does not compose -- but at the cartridge's own y and on the keyboard's
-- own column pitch, so the six buttons land within a few pixels of where their
-- sprites do.  See Gen4Naming.HOME_SPRITE_X for that comparison written out.
function Gen4NamingScreen:drawHomeRow()
  local col = 1
  while col <= Gen4NamingScreen.COLS do
    local id = HOME[col]
    local span = 0
    while HOME[col + span] == id do span = span + 1 end
    local x = HOME_X + (col - 1) * CELL_W
    local w = span * CELL_W
    local selected = self.row == 1 and self.col >= col and self.col < col + span
    local active = (id == PAGES[self.page].id)
    frame(x, HOME_Y, w, HOME_H)
    -- The selection is a HIGHLIGHT, not a ">" in front of the word.  Prefixing
    -- it pushed every label one glyph right and out of its own button, and on
    -- the widest labels pushed the last letter out entirely -- so the thing
    -- meant to show where you are was itself putting text outside the boxes.
    highlight(x, HOME_Y, w, HOME_H, selected, active)
    local label = LABEL[id] or ""
    -- Centred in its own button, and measured rather than assumed: a clip here
    -- would mean the label did not fit, which is the fault this screen was
    -- reported for, so it is worth seeing if it ever happens.
    local width = Font.width(label)
    Font.draw(label, x + math.floor((w - width) / 2), HOME_Y + 2)
    col = col + span
  end
end

-- THE CHECKERBOARD, exactly as `NamingScreen_InitializeCharsGraphics` paints
-- it: the whole window in one colour, then 16x19 rectangles of the other over
-- the ODD columns of rows 0, 2 and 4 and the EVEN columns of rows 1 and 3.
function Gen4NamingScreen:drawChecker()
  local g = love.graphics
  local base, alt = self:checkerColours()
  local cols = Gen4NamingScreen.COLS
  g.setColor(base[1], base[2], base[3], 1)
  g.rectangle("fill", GRID_X, GRID_Y, cols * CELL_W, CHAR_ROWS * CELL_H)
  g.setColor(alt[1], alt[2], alt[3], 1)
  for row = 0, CHAR_ROWS - 1 do
    -- Rows 0, 2, 4 start on the second column; rows 1 and 3 start on the first.
    for col = (row % 2 == 0) and 1 or 0, cols - 1, 2 do
      g.rectangle("fill", GRID_X + col * CELL_W, GRID_Y + row * CELL_H,
                  CELL_W, CELL_H)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4NamingScreen:draw()
  local g = love.graphics
  local art = self.art or {}

  -- The backdrop.  A flat fill when the cache has none, so a pre-`naming`
  -- cache still gets a readable screen rather than whatever was behind it.
  local background = self:img(art.background)
  if background then
    g.setColor(1, 1, 1, 1)
    g.draw(background, 0, 0)
  else
    g.setColor(0.13, 0.16, 0.27, 1)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end

  -- The prompt and the typed name, which are the bottom screen's on hardware.
  Font.draw(self.title, 16, TITLE_Y)
  local shown = {}
  for i = 1, self.maxLen do shown[i] = self.glyphs[i] or "_" end
  frame(8, ENTRY_Y - 5, W - 16, 22)
  Font.draw(table.concat(shown, " "), 16, ENTRY_Y)

  -- The panel for THIS page, at the offset the app parks its layer at.  The
  -- checkerboard goes on top of it, inside the window it frames.
  local panel = self:img((art.panels or {})[self.page])
  if panel then
    g.setColor(1, 1, 1, 1)
    g.draw(panel, PANEL_X, PANEL_Y)
  end
  self:drawChecker()
  if not panel then
    frame(GRID_X - 2, GRID_Y - 2, Gen4NamingScreen.COLS * CELL_W + 4,
          CHAR_ROWS * CELL_H + 4)
  end

  for row = 2, Gen4NamingScreen.ROWS do
    local y = GRID_Y + (row - 2) * CELL_H
    for col = 1, Gen4NamingScreen.COLS do
      local cell = self:cell(row, col)
      local x = GRID_X + (col - 1) * CELL_W
      -- Highlight first, glyph second: drawing the cursor as a GLYPH put it in
      -- the same cell as the letter it was pointing at, so the two drew on top
      -- of each other.
      highlight(x, y, CELL_W, CELL_H, self.row == row and self.col == col, false)
      if cell and cell.value ~= "" then
        local width = Font.width(cell.value)
        Font.draw(cell.value, x + math.floor((CELL_W - width) / 2),
                  y + GLYPH_INSET)
      end
    end
  end

  -- LAST, because on hardware they are sprites and sprites draw over
  -- backgrounds: the buttons sit at y = 68 and the panel starts at 80, so a
  -- button drawn first would have its bottom four pixels covered by the panel.
  self:drawHomeRow()
  g.setColor(1, 1, 1, 1)
end

return Gen4NamingScreen
