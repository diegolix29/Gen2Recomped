-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's main menu.
--
-- Not a box on the title: a screen of its own, the way the cartridge draws it.
-- Each option is a WINDOW -- x = 3, width 26 tiles, the first at y = 1, the
-- next `height + 2` below it -- and CONTINUE's window is five lines tall
-- because it carries the save summary inside it rather than opening a panel.
-- All of that is `sOptions` and the loop in main_menu.c, carried in
-- Gen4Menus and written into the cache by the `menus` stage.
--
-- THE WORDS ARE THE CARTRIDGE'S.  Bank 550 gives CONTINUE, NEW GAME, PLAYER,
-- TIME, BADGES and POKéDEX, and the menus stage writes them out already
-- resolved, so this file has no English of its own to fall back to and no bank
-- lookup to do.  Where a row has no cartridge string -- OPTION, which Platinum
-- does not have on this menu at all -- the record says `fromCartridge = false`
-- and carries the label this port chose.
--
-- WHY OPTION IS HERE ANYWAY.  On the DS, text speed and the message frame live
-- in the in-game START menu, so a player who has not started a game has nowhere
-- to set them.  Every other title this engine boots offers the row before the
-- first save exists; leaving Platinum without it would make it the only one
-- that could not be configured until after NEW GAME.
--
-- THE DEX ROW IS SKIPPED, NOT BLANKED.  RenderContinueOption `continue`s past
-- it while the Pokedex has not been obtained, which closes the gap rather than
-- leaving an empty line -- so the summary is four rows or three, never four
-- with a hole.

local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4MainMenu = {}
Gen4MainMenu.__index = Gen4MainMenu
Gen4MainMenu.isOpaque = true

local W, H = 256, 192

-- The fallbacks, used only where the cache carries no `menus` record -- a
-- Platinum cache extracted before that stage existed.  They are this file's
-- own words and are deliberately the plainest possible: a wrong-looking menu
-- that says CONTINUE beats a right-looking one with blank rows.
local FALLBACK = {
  layout = { optionX = 3, optionWidth = 26, firstY = 1, gap = 2,
             lineTiles = 2, linePixels = 16, margin = 32 },
  colors = { background = { 0.39, 0.39, 1 }, unfocused = { 0.84, 0.84, 0.84 } },
  rows = {
    { id = "continue", lines = 5, label = "CONTINUE" },
    { id = "newGame", lines = 1, label = "NEW GAME" },
    { id = "options", lines = 1, label = "OPTION" },
  },
  continueRows = {
    { label = "PLAYER", value = "playerName" },
    { label = "TIME", value = "playTime" },
    { label = "BADGES", value = "badgeCount" },
    { label = "POKéDEX", value = "seenCount", needsPokedex = true },
  },
}

function Gen4MainMenu:uiSize() return W, H end
function Gen4MainMenu:wantsFillScale() return true end
function Gen4MainMenu:wantsEdgeBleed() return false end

function Gen4MainMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

-- Is there a save on disk?  The active version's own file, which is what every
-- other screen in this engine asks and what decides whether CONTINUE exists.
local function saveOnDisk()
  local ok, info = pcall(function()
    local name = require("src.core.SaveData").saveFilename(GameVersion.get())
    return love.filesystem and love.filesystem.getInfo
       and love.filesystem.getInfo(name) or nil
  end)
  return ok and info ~= nil
end

local function sameItems(_, items) return items end

function Gen4MainMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4MainMenu)
  self.game = game
  self.onNewGame, self.onContinue, self.onCancel =
    opts.onNewGame, opts.onContinue, opts.onCancel
  self.index = 1

  local rec = (game.data and game.data.gen4_menus) or {}
  self.layout = rec.layout or FALLBACK.layout
  self.colors = rec.colors or FALLBACK.colors
  self.continueRows = rec.continueRows or FALLBACK.continueRows

  local haveSave = saveOnDisk()
  local items = {}
  for _, row in ipairs(rec.rows or FALLBACK.rows) do
    -- CONTINUE is the one row the cartridge itself withholds: with no save
    -- there is nothing for it to summarise, and pressing it would load a file
    -- that is not there.
    if row.id ~= "continue" or haveSave then
      items[#items + 1] = {
        key = row.id,
        label = row.label or Strings(row.id:upper()),
        lines = row.lines or 1,
      }
    end
  end
  -- The launcher's own row, as on every other title: without it Platinum would
  -- be the one game with no way back to the game list.
  items[#items + 1] = { key = "exit", label = Strings("EXIT GAME"), lines = 1 }

  local hooked = Runtime.call("ui.title_menu.items", sameItems, game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.title_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  self.items = items
  self.save = haveSave and self:loadSummary() or nil
  return self
end

-- The save, read once, for the CONTINUE window's summary.  A failure here is
-- not fatal: the row still exists and still loads; it simply shows no figures.
function Gen4MainMenu:loadSummary()
  local ok, loaded = pcall(require("src.core.SaveData").load)
  return (ok and loaded) or nil
end

function Gen4MainMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

local function beep(self)
  pcall(function()
    require("src.core.Sound").play(self.game.data, "Press_AB")
  end)
end

function Gen4MainMenu:choose()
  local item = self.items[self.index]
  if not item then return end
  if item.onSelect and not item.key then
    self.game.stack:pop()
    return item.onSelect()
  end
  if item.key == "continue" then
    if self.onContinue then self.onContinue() end
  elseif item.key == "newGame" then
    if self.onNewGame then self.onNewGame() end
  elseif item.key == "options" then
    local boot = self.game.data.field and self.game.data.field.boot
    local screens = boot and boot.screens or {}
    Screens.push(self.game, screens.options or "OptionsMenu")
  elseif item.key == "exit" then
    self.game:returnToLauncher()
  elseif item.onSelect then
    item.onSelect()
  end
end

function Gen4MainMenu:update()
  local input = self.game.input
  if not input then return end
  local n = #self.items
  if n == 0 then return end
  if input:wasPressed("down") then
    self.index = self.index % n + 1
    beep(self)
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
    beep(self)
  elseif input:wasPressed("a") then
    beep(self)
    self:choose()
  elseif input:wasPressed("b") then
    beep(self)
    self:close()
  end
end

-- ------------------------------------------------------------------- draw --

-- The four figures the CONTINUE window shows, by the key the cache names.
-- Each is derived here rather than stored, so a row the cache adds later can
-- be answered without this table changing shape.
function Gen4MainMenu:value(key)
  local save = self.save
  if not save then return "" end
  if key == "playerName" then
    return tostring((save.player and save.player.name) or "")
  elseif key == "playTime" then
    local seconds = 0
    local ok, n = pcall(require("src.core.SaveData").playSeconds, save)
    if ok and tonumber(n) then seconds = math.floor(n) end
    return ("%d:%02d"):format(math.floor(seconds / 3600),
                              math.floor(seconds / 60) % 60)
  elseif key == "badgeCount" then
    local ok, Badges = pcall(require, "src.inventory.Badges")
    if not ok then return "0" end
    local got, count = pcall(Badges.count, self.game.data, save)
    return tostring((got and tonumber(count)) or 0)
  elseif key == "seenCount" then
    local n = 0
    for _ in pairs((save.pokedex or {}).seen or {}) do n = n + 1 end
    if n == 0 then
      for _ in pairs((save.pokedex or {}).owned or {}) do n = n + 1 end
    end
    return tostring(n)
  end
  return ""
end

function Gen4MainMenu:hasPokedex()
  local dex = self.save and self.save.pokedex
  if not dex then return false end
  if next(dex.seen or {}) ~= nil then return true end
  return next(dex.owned or {}) ~= nil
end

-- `tx, ty, tw` are the window's CONTENT rect, which is what the cartridge's
-- own coordinates are in: RenderContinueOption prints at x = 32 and
-- y = TEXT_LINES(i) INSIDE the window, and the frame is drawn outside it.
function Gen4MainMenu:drawContinue(tx, ty, tw)
  local L = self.layout
  local left = tx * 8
  local right = (tx + tw) * 8
  -- Line 0 is the word CONTINUE itself, printed by the caller; the summary
  -- starts on line 1, exactly as the cartridge's loop does.
  local line = 1
  for _, row in ipairs(self.continueRows) do
    if not (row.needsPokedex and not self:hasPokedex()) then
      local value = self:value(row.value)
      local y = ty * 8 + line * L.linePixels
      Font.draw(tostring(row.label or ""), left + L.margin, y)
      -- Right-aligned with the same margin the labels are inset by, which is
      -- what PrintRightAlignedWithMargin does: one number, used on both sides.
      Font.draw(value, right - L.margin - Font.width(value), y)
      line = line + 1
    end
  end
end

function Gen4MainMenu:draw()
  local g = love.graphics
  local bg = self.colors.background or FALLBACK.colors.background
  g.setColor(bg[1], bg[2], bg[3], 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local L = self.layout
  local glyphH = Font.glyphHeight()
  local inset = math.max(0, math.floor((L.linePixels - glyphH) / 2))

  -- THE WINDOW THE PLAYER SEES IS THE FRAME AROUND THE CONTENT, and drawing
  -- the content rect alone is why the boxes were half the height they should
  -- be.  Reported twice: "the tiles are too small", then "the boxes
  -- surrounding the text are still too small thry should match the rom".
  --
  -- `Window_DrawStandardFrame` -> `DrawStandardWindowFrame` (render_window.c)
  -- lays the frame at `x - 1 .. x + width` and `y - 1 .. y + height`, one tile
  -- outside the window on every side, and `RenderOptions` advances by
  -- `height + 2` with the comment "Add 2 to account for the window border".
  -- So a one-line option is 2 content tiles and FOUR visible ones -- 32 px,
  -- not 16 -- and the column is 28 tiles wide, not 26: x = 3, width = 26,
  -- frame from tile 2 to tile 29, which is 16 px to 240 px and centred on a
  -- 256 px screen.  Drawn as the content rect it was 208 px wide starting at
  -- 24, which is neither the right size nor centred.
  --
  -- Everything below is in the cartridge's own numbers; only the cursor is
  -- this port's, because Platinum marks the focused option by swapping its
  -- frame tiles (FOCUSED_OPTION_FRAME_BASE_TILE) rather than by drawing one.
  local tops = {}
  local ty = L.firstY
  for i, item in ipairs(self.items) do
    tops[i] = ty
    ty = ty + (item.lines or 1) * L.lineTiles + L.gap
  end
  local screenTiles = math.floor(H / 8)

  -- ...AND THE COLUMN CAN BE TALLER THAN THE SCREEN, on the cartridge too:
  -- CONTINUE alone is 12 visible tiles and eight options do not fit in 24,
  -- which is what Platinum's scroll arrows are for.  Keeping the selected
  -- window on screen is the same answer; dropping the rows that fall past the
  -- bottom edge -- which is what the old `break` did -- makes EXIT
  -- unreachable the moment a save exists.
  local selTop = tops[self.index] or L.firstY
  local selH = (self.items[self.index] and self.items[self.index].lines or 1)
               * L.lineTiles
  local scroll = 0
  local bottomEdge = selTop + selH + 1
  if bottomEdge > screenTiles then scroll = bottomEdge - screenTiles end
  if selTop - 1 - scroll < 0 then scroll = selTop - 1 end

  for i, item in ipairs(self.items) do
    local th = (item.lines or 1) * L.lineTiles
    local y = tops[i] - scroll
    -- Wholly off either edge: not drawn at all, rather than clipped into a
    -- half window.
    if y + th + 1 > 0 and y - 1 < screenTiles then
      Font.drawBox(L.optionX - 1, y - 1, L.optionWidth + 2, th + 2)

      -- DRAWN AT WHITE, not at black.  Platinum's font page is PRE-TINTED: the
      -- sheet bakes the letter dark and its shadow light, and Font.drawCode blits
      -- it as it stands when no style is pushed.  Multiplying it by black -- which
      -- is what every Game Boy screen in this engine does, because its glyphs are
      -- a mask -- would paint the shadow black as well and thicken every letter.
      Font.draw(item.label, L.optionX * 8, y * 8 + inset)
      if item.key == "continue" then
        self:drawContinue(L.optionX, y, L.optionWidth)
      end
      if i == self.index then
        -- In the frame's own left column, so the label keeps the cartridge's
        -- content origin rather than being pushed a tile right to make room.
        Font.drawCode(Theme.cursor, (L.optionX - 1) * 8, y * 8 + inset)
      end
    end
  end
end

return Gen4MainMenu
