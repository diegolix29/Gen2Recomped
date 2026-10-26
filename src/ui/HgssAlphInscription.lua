-- THE RUINS OF ALPH WALL INSCRIPTIONS (HeartGold / SoulSilver).
--
-- ScrCmd_OpenAlphHiddenRoom <n> (pokeheartgold scrcmd_pokemon_misc.c ->
-- overlay 2 OpenAlphHiddenRoom, 0x022467C4) is not a door: it is the stone
-- panel on the puzzle rooms' back wall. The task (ov02_02246818):
--   * state 0: /a/1/7/4 palette 15 / character 16 / screen 17 onto main BG1
--     (Gen4HgssLegendArt `alphPanel`), window { BG1, x 9, y 10, 14 x 2 tiles,
--     ov02_0225324C }, bank 198 entry n -- ESCAPE, LIGHT, WATER, HO OH --
--     printed in FONT_UNOWN (font 3) centred in the window's 112 px, and SE
--     0x5DC;
--   * state 1: A alone (gSystem newKeys & 1) closes it, with SE 0x5DC again.
-- The script around it is LockAll / the command / ReleaseAll.

local Assets = require("src.render.Assets")
local Panel = {}; Panel.__index = Panel

local W, H = 256, 192
local WIN_X, WIN_Y, WIN_W = 9 * 8, 10 * 8, 14 * 8
local SE = 1500

local function image(path)
  if type(path) == "table" then path = path.path end
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter("nearest", "nearest"); return img end
end

local function se(data, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, data, id) end
end

-- the character codes of `text` (Gen4Text.CHARS reversed), one glyph each
local reverse
local function codes(text)
  if not reverse then
    reverse = {}
    for code, ch in pairs(require("src.import.Gen4Text").CHARS or {}) do
      if type(ch) == "string" and reverse[ch] == nil then reverse[ch] = code end
    end
  end
  local out = {}
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = reverse[ch] or reverse[" "] or 0x1DE
  end
  return out
end

function Panel.new(game, index, onDone)
  local self = setmetatable({ game = game, data = game.data, onDone = onDone }, Panel)
  local art = game.data.gen4_legend_art or {}
  self.panel = image(art.alphPanel)
  -- the font record's Unown face (font 3 of /a/0/1/6, the import's `font`)
  self.font = ((game.data.font or {}).faces or {}).unown
  self.sheet = self.font and image(self.font.image)
  local text = game.data.text and game.data.text[("TEXT_B%04d_%05d"):format(198, tonumber(index) or 0)] or ""
  self.text = tostring(text):gsub("[\r\n\f\v]+$", "")
  self.codes = codes(self.text)
  se(self.data, SE)
  return self
end

function Panel:uiSize() return W, H end

function Panel:update()
  local input = self.game.input
  if input and input:wasPressed("a") then
    se(self.data, SE)
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function Panel:draw()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if self.panel then g.draw(self.panel, 0, 0) end
  local f, sheet = self.font, self.sheet
  if not (f and sheet) then
    g.setColor(0.25, 0.18, 0.1, 1)
    g.printf(self.text, WIN_X, WIN_Y + 2, WIN_W, "center")
    g.setColor(1, 1, 1, 1)
    return
  end
  local gw, gh, cols = f.glyphWidth or 16, f.glyphHeight or 16, f.glyphsPerRow or 32
  local widths, base = f.widths or {}, f.base or 1
  local function width(c) local w = widths[c - base + 1]; return (w and w > 0) and w or (f.advance or gw) end
  local total = 0
  for _, c in ipairs(self.codes) do total = total + width(c) end
  -- ov02_0224686C: x = (0x70 - width) / 2
  local x = WIN_X + math.floor((WIN_W - total) / 2)
  local sw, sh = sheet:getDimensions()
  self.quads = self.quads or {}
  g.setColor(0.3, 0.2, 0.1, 1)
  for _, c in ipairs(self.codes) do
    local glyph = c - base
    local q = self.quads[glyph]
    if not q then
      q = g.newQuad((glyph % cols) * gw, math.floor(glyph / cols) * gh, gw, gh, sw, sh)
      self.quads[glyph] = q
    end
    g.draw(sheet, q, x, WIN_Y)
    x = x + width(c)
  end
  g.setColor(1, 1, 1, 1)
end

return Panel
