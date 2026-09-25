-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's OPTIONS screen.
--
-- Six rows and CLOSE, and every word on it -- the row names, the values each
-- row cycles through and the one-line description above the list -- comes out
-- of message bank 220, written by the `menus` stage:
--
--   TEXT SPEED    SLOW / MID / FAST
--   BATTLE SCENE  ON / OFF
--   BATTLE STYLE  SHIFT / SET
--   SOUND         STEREO / MONO
--   BUTTON MODE   NORMAL / START = X / L = A
--   FRAME         TYPE 1 .. TYPE 20
--   CLOSE
--
-- THE ORDER IS WHY THIS IS NOT THE GEN 3 SCREEN WITH DIFFERENT WORDS.
-- `OPTIONS_SOUND_MODE_STEREO = 0, OPTIONS_SOUND_MODE_MONO` -- Platinum lists
-- STEREO first; Emerald lists MONO first.  Reusing Gen 3's row would put the
-- right two words on screen in the wrong order, store the opposite of what the
-- player picked, and look completely correct doing it.  BUTTON MODE differs the
-- same way: Emerald's middle setting is LR and Platinum's is START = X.
--
-- WHICH ROWS ACTUALLY BITE, stated rather than implied:
--
--   TEXT SPEED, BATTLE SCENE, BATTLE STYLE, SOUND  map onto options this port
--                                                  already honours.
--   FRAME                                          is live here in a way it is
--                                                  not on the Game Boy screens:
--                                                  it picks one of Platinum's
--                                                  twenty message boxes, and
--                                                  Font.drawBox reads it.
--   BUTTON MODE                                    stores, and only L = A does
--                                                  anything -- see BINDINGS.
--
-- CONFIRM is extracted and deliberately absent.  Platinum stages the changes
-- and applies them on CONFIRM; this engine applies each one as it is made, the
-- way every other OPTION screen in it does, so the row would either do nothing
-- or promise a staging model that is not there.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4Options = {}
Gen4Options.__index = Gen4Options
Gen4Options.isOpaque = true

local W, H = 256, 192

-- The description strip at the top, then the list.  Both are Platinum's own
-- window frame, which is what `Font.drawBox` now draws on a Gen 4 cache.
local DESC = { tx = 1, ty = 1, tw = 30, th = 4 }
local LIST = { tx = 1, ty = 6, tw = 30 }
local ROW_STEP = 2
local LABEL_X = 3
local VALUE_X = 136
local CURSOR_X = 1
-- How many rows fit between the list's top border and the bottom of the
-- screen: 192px is 24 tiles, the list opens at 6 and a row is two tiles.
local VISIBLE = 8

local FRAME_TYPES = 20

function Gen4Options:uiSize() return W, H end
function Gen4Options:wantsFillScale() return true end
function Gen4Options:wantsEdgeBleed() return false end

function Gen4Options:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

-- How each row reads and writes the save's own options table.  This lives here
-- rather than in the cache for the same reason the Gen 3 screen keeps its own:
-- the extractor stays a description of the cartridge, and what the ENGINE does
-- with a setting is the engine's business.
local BINDINGS = {
  -- The frame delays TextBox actually reads, fastest last.
  textSpeed = { field = "textSpeed", choices = { 5, 3, 1 } },
  battleScene = { field = "battleAnim", choices = { true, false } },
  battleStyle = { field = "battleStyle", choices = { "shift", "set" } },
  -- STEREO FIRST.  The Gen 3 row is { false, true } because Emerald lists MONO
  -- first; writing that here would store mono when the player picked stereo.
  sound = { field = "stereo", choices = { true, false } },
  -- BUTTON MODE STORES ALL THREE AND ONLY ONE OF THEM BITES.
  --
  -- NORMAL and L = A mean exactly what they mean on Emerald, and Input.lua
  -- already honours the second through `gen3ButtonMode`, so those two are
  -- mirrored onto it.  START = X is a DS mapping with no counterpart here --
  -- there is no X to move START onto -- so it is stored, shown, and does
  -- nothing, which is said out loud rather than left for a player to discover.
  buttonMode = { field = "gen4ButtonMode", choices = { 1, 2, 3 },
                 mirror = { field = "gen3ButtonMode", map = { 1, 1, 3 } } },
  -- `gen3Frame` is the field Font.lua's frame chooser reads, on every
  -- generation.  The name is Gen 3's because that is where the chooser was
  -- written; renaming it would mean changing Font.lua for nothing, and a save
  -- carried between cartridges keeps one frame choice, which is the behaviour
  -- a player would expect anyway.
  frame = { field = "gen3Frame" },
}

function Gen4Options.new(game, opts)
  local self = setmetatable({}, Gen4Options)
  self.game = game
  self.onCancel = opts and opts.onCancel
  self.index = 1
  self.scroll = 0
  self.blink = 0

  local record = ((game.data and game.data.gen4_menus) or {}).options or {}
  self.title = record.title or Strings("OPTIONS")
  self.rows = {}
  for _, row in ipairs(record.rows or {}) do
    if row.label and row.key ~= "close" then
      self.rows[#self.rows + 1] = {
        key = row.key, label = row.label, values = row.values,
        description = row.description, binding = BINDINGS[row.key],
      }
    elseif row.key == "close" then
      self.closeLabel = row.label
      self.closeDescription = row.description
    end
  end
  self.cartridgeRows = #self.rows
  self.closeLabel = self.closeLabel or Strings("CLOSE")

  -- THE ENGINE'S OWN SETTINGS, APPENDED -- the same argument the Gen 3 screen
  -- makes.  Platinum's screen has six rows and no volume sliders, no video
  -- mode, no key bindings and no mod manager; a player on Platinum who could
  -- not reach those would have lost every setting the other versions have, for
  -- no better reason than that a DS had no menu for them.
  --
  -- Taken through the `ui.options.rows` hook, not straight from buildRows: the
  -- hook is the seam every mod adds, removes and reorders rows through, and a
  -- screen that skips it shows a mod's rows on every version but this one.
  local covered = {
    textSpeed = true, animations = true, battleStyle = true,
    sound = true, stereo = true, frame = true,
  }
  local okRows, extra = pcall(function()
    local rows = require("src.ui.OptionsMenu").buildRows(game)
    local Runtime = require("src.mods.Runtime")
    local hooked = Runtime.call("ui.options.rows",
                                function(_, vanilla) return vanilla end,
                                game, rows)
    if type(hooked) ~= "table" then
      Logger.error("gen4 options: ui.options.rows returned %s; keeping the "
                   .. "vanilla rows", type(hooked))
      return rows
    end
    return hooked
  end)
  if okRows and type(extra) == "table" then
    for _, row in ipairs(extra) do
      if row.label and not covered[row.id] then
        self.rows[#self.rows + 1] = {
          key = row.id, label = row.label, engine = row,
        }
      end
    end
  else
    Logger.warn("gen4 options: the engine's own rows are unavailable (%s)",
                tostring(extra))
  end

  if #self.rows == 0 then
    Logger.warn("gen4 options: this dataset carries no OPTION vocabulary")
  end
  return self
end

-- Which value a row is currently showing, 1-based.
function Gen4Options:choiceOf(row)
  local options = (self.game.save and self.game.save.options) or {}
  local bind = row.binding
  if not bind then return 1 end
  if row.key == "frame" then
    return math.max(1, math.min(FRAME_TYPES, options[bind.field] or 1))
  end
  local current = options[bind.field]
  for i, v in ipairs(bind.choices or {}) do
    if v == current then return i end
  end
  return 1
end

function Gen4Options:cycle(row, delta)
  if row and row.engine then
    if row.engine.step then pcall(row.engine.step, self.game, delta) end
    return
  end
  local save = self.game.save
  if not (save and row and row.binding) then return end
  save.options = save.options or {}
  local bind = row.binding
  local at = self:choiceOf(row) - 1
  if row.key == "frame" then
    save.options[bind.field] = (at + delta) % FRAME_TYPES + 1
  else
    local choices = bind.choices or {}
    if #choices == 0 then return end
    local pick = (at + delta) % #choices + 1
    save.options[bind.field] = choices[pick]
    -- A row whose setting the engine already has under another name writes
    -- both, so the two cannot drift apart.
    if bind.mirror then
      save.options[bind.mirror.field] = bind.mirror.map[pick]
    end
  end
  if self.game.applyOptions then
    pcall(self.game.applyOptions, self.game, save.options)
  end
end

function Gen4Options:valueText(row)
  if row.engine then
    local ok, text = pcall(function()
      return row.engine.value and row.engine.value(self.game) or ""
    end)
    return (ok and text) or ""
  end
  local values = row.values or {}
  return values[self:choiceOf(row)] or values[1] or ""
end

function Gen4Options:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- Keep the cursor inside the window.  CLOSE is the row after the last one and
-- scrolls with the rest rather than sitting in a fixed strip.
function Gen4Options:clampScroll()
  local total = #self.rows + 1
  local maxScroll = math.max(0, total - VISIBLE)
  if self.index <= self.scroll then self.scroll = self.index - 1 end
  if self.index > self.scroll + VISIBLE then
    self.scroll = self.index - VISIBLE
  end
  self.scroll = math.max(0, math.min(self.scroll, maxScroll))
end

function Gen4Options:update()
  self.blink = (self.blink + 1) % 60
  local input = self.game.input
  if not input then return end
  local n = #self.rows + 1                  -- the rows, then CLOSE
  local row = self.rows[self.index]
  if input:wasPressed("down") then
    self.index = self.index % n + 1
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
  elseif input:wasPressed("right") then
    self:cycle(row, 1)
  elseif input:wasPressed("left") then
    self:cycle(row, -1)
  elseif input:wasPressed("a") then
    if self.index > #self.rows then return self:close() end
    if row and row.engine and row.engine.activate then
      return pcall(row.engine.activate, self.game)
    end
    self:cycle(row, 1)
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
  self:clampScroll()
end

-- The line above the list: whichever row is selected explains itself, in the
-- cartridge's own wording.  CLOSE has one too ("Return to the game.").
function Gen4Options:description()
  if self.index > #self.rows then return self.closeDescription or "" end
  local row = self.rows[self.index]
  if not row then return "" end
  if row.description then return row.description end
  -- An engine row carries no cartridge description; its own label is better
  -- than an empty strip that looks like a missing string.
  return row.label or ""
end

function Gen4Options:draw()
  local g = love.graphics
  local colors = ((self.game.data and self.game.data.gen4_menus) or {}).colors
  local bg = (colors and colors.background) or { 0.39, 0.39, 1 }
  g.setColor(bg[1], bg[2], bg[3], 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local glyphH = Font.glyphHeight()
  local inset = math.max(0, math.floor((ROW_STEP * 8 - glyphH) / 2))

  -- Drawn at white, not black: Platinum's font page is pre-tinted, so
  -- multiplying it by black paints the letter's shadow black too.  See the
  -- same note on Gen4MainMenu.
  Font.drawBox(DESC.tx, DESC.ty, DESC.tw, DESC.th)
  Font.draw(self.title, (DESC.tx + 1) * 8, (DESC.ty + 1) * 8)
  local desc = self:description()
  local y = (DESC.ty + 2) * 8 + 2
  for line in (tostring(desc) .. "\n"):gmatch("([^\n]*)\n") do
    if y < (DESC.ty + DESC.th) * 8 then
      Font.draw(line, (DESC.tx + 1) * 8, y)
      y = y + glyphH + 1
    end
  end

  local total = #self.rows + 1
  local shown = math.min(VISIBLE, total)
  Font.drawBox(LIST.tx, LIST.ty, LIST.tw, shown * ROW_STEP + 2)

  for slot = 1, shown do
    local i = slot + self.scroll
    local rowY = (LIST.ty + 1 + (slot - 1) * ROW_STEP) * 8 + inset
    if i <= #self.rows then
      local row = self.rows[i]
      Font.draw(row.label, (LIST.tx + LABEL_X) * 8, rowY)
      Font.draw(self:valueText(row), VALUE_X, rowY)
    elseif i == total then
      Font.draw(self.closeLabel, (LIST.tx + LABEL_X) * 8, rowY)
    end
    if i == self.index then
      Font.drawCode(Theme.cursor, (LIST.tx + CURSOR_X) * 8, rowY)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4Options
