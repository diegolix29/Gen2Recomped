-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE'S MENU CURSOR, as a glyph of the message face.
--
-- Every menu here asks Theme.cursor for its arrow -- a CHARACTER of the font.
-- BW's message font (/a/0/2/3 member 0, 5,064 glyphs) has no right-pointing
-- arrow but "→" and "⇒" (the code Gen 1's $ED landed on, drawn as a stray
-- mark beside YES), and its other faces (members 1 - 4) none either; the
-- cartridge's list cursor is not a character. So the solid "▶" is painted
-- into the sheet's first free cell in the face's own two inks (letter and
-- shadow), the charmap gains it and `symbols.cursor` names it -- not ROM art,
-- the one piece here that is not.
--
-- add(sheet, font, columns, def, colors) -> code or nil

local M = {}

-- rows of the arrow: { first x, last x } from the top, a 5-wide, 9-tall wedge
local SHAPE = { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 3 }, { 0, 2 }, { 0, 1 }, { 0, 0 } }

function M.add(sheet, font, columns, def, colors)
  if not (sheet and font and def) then return nil end
  local index = font.numGlyphs
  local gw, gh = font.pixelWidth, font.pixelHeight
  local ox, oy = (index % columns) * gw, math.floor(index / columns) * gh
  if oy + gh > sheet.height then return nil end
  local fg, sh = colors and colors[1], colors and colors[2]
  if not (fg and sh) then return nil end
  local function rgba(c) return string.char(c[1], c[2], c[3], 255) end
  local paint = {}
  local top = math.max(0, math.floor((gh - #SHAPE) / 2) - 1)
  local left = 2
  for r, span in ipairs(SHAPE) do
    for x = span[1], span[2] do
      paint[(top + r) * gw + left + x + 1] = paint[(top + r) * gw + left + x + 1] or "s"
      paint[(top + r - 1) * gw + left + x] = "f"
    end
  end
  local W = sheet.width
  local rgbaStr = sheet.rgba
  local parts, at = {}, 1
  for y = 0, gh - 1 do
    local rowStart = ((oy + y) * W + ox) * 4 + 1
    parts[#parts + 1] = rgbaStr:sub(at, rowStart - 1)
    local cells = {}
    for x = 0, gw - 1 do
      local p = paint[y * gw + x]
      cells[#cells + 1] = p == "f" and rgba(fg) or p == "s" and rgba(sh) or rgbaStr:sub(rowStart + x * 4, rowStart + x * 4 + 3)
    end
    parts[#parts + 1] = table.concat(cells)
    at = rowStart + gw * 4
  end
  parts[#parts + 1] = rgbaStr:sub(at)
  sheet.rgba = table.concat(parts)
  local code = index + 1
  def.charmap = def.charmap or {}
  def.charmap[#def.charmap + 1] = { code = code, seq = "▶" }
  def.symbols = { cursor = code, cursorHollow = code }
  return code
end

return M
