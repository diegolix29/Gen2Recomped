-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- NFGR: Platinum's fonts, and therefore every word the game says.
--
-- Four of these live in /graphic/pl_font.narc -- system, message, subscreen and
-- unown -- and none of the rest of the graphics path can read them, because an
-- NFGR is not a Nitro container at all.  It has no "RGCN"-style magic and no
-- tagged sections; it is a 16-byte header, a run of glyphs and a table of
-- widths.
--
--   u32 size              offset where the glyph data starts (0x10)
--   u32 widthTableOffset  offset of the one-byte-per-glyph width table
--   u32 numGlyphs
--   u8  maxWidth, maxHeight
--   u8  glyphWidth, glyphHeight   -- in TILES, 1 or 2, not pixels
--
-- A glyph is glyphWidth * glyphHeight tiles of 16 bytes, so 64 bytes for the
-- 2x2 case every text font uses.  The whole file accounts for itself exactly:
-- 16 + numGlyphs * 16 * gw * gh + numGlyphs == the member's length, which is
-- the check that the header was read right.
--
-- THE FIRST TRAP IS THAT THESE LOOK COMPRESSED AND ARE NOT.  Every NFGR begins
-- `10 00 00 00`, and an LZ77 member begins with 0x10 too -- so a decompressor
-- that tests only the first byte accepts it, reads a declared output size of
-- ZERO from the next three bytes, and returns an empty string.  Not an error,
-- not garbage: nothing.  The font simply disappears, and the caller sees a
-- zero-length file rather than a bad one.  Gen4Graphics.isCompressed now also
-- requires a non-zero declared size, which is what tells the two apart.
--
-- THE SECOND TRAP IS THE BIT ORDER.  Glyph pixels are 2bpp and packed
-- MSB-FIRST -- the opposite of the 4bpp graphics everywhere else in this
-- cartridge, where the LOW nibble is the first pixel.  Worse, within each
-- two-byte row the HIGH byte holds the FIRST four pixels: the game reads the
-- row as a u16 and looks up `row >> 8` before `row & 0xFF`.  Getting either
-- one backwards produces legible-looking glyphs that are mirrored in fours,
-- which reads as a font problem rather than a bit-order one.
--
-- THE THIRD IS THAT A PIXEL IS A ROLE, NOT A COLOUR.  The two bits select from
-- { nothing, foreground, shadow, background } -- Text_GenerateFontHalfRowLookupTable
-- builds that table from three colours the caller passes per text box.  So a
-- glyph has no palette of its own, and the same glyph is drawn white-on-black
-- in a battle and black-on-white in a menu.  Rendering one to a PNG means
-- CHOOSING colours; this module keeps the roles and supplies a default.

local Gen4Font = {}

local byte, floor = string.byte, math.floor

local function u32(s, at)
  local a, b, c, d = byte(s, at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

Gen4Font.HEADER_BYTES = 16
Gen4Font.TILE_BYTES = 16

-- The four roles a 2-bit pixel can carry, in value order.
Gen4Font.ROLES = { [0] = "none", "foreground", "shadow", "background" }

-- The default colouring, and both halves of it are constrained by something
-- outside this file.
--
-- BACKGROUND IS TRANSPARENT.  On the hardware it is the text box's own fill,
-- so it covers the whole 16x16 cell while a glyph only ADVANCES by its width
-- -- six or seven pixels for most letters.  Painting it opaque makes each cell
-- overwrite most of the one before it, and a line comes out as a row of blocks
-- with the letters crushed together: legible, wrong, and easy to mistake for a
-- bad width table.
--
-- THE LETTER IS THE DARK TONE AND THE SHADOW THE LIGHT ONE, and that order is
-- not a taste.  src/render/Font.lua recolours a pre-tinted page with a shader
-- that tells the two apart by LUMINANCE -- `lum < 0.5` is the ink, anything
-- else is the shadow -- so a sheet baked light-on-dark would have every
-- {COLOR} swap paint the letter with the shadow's colour and the shadow with
-- the letter's.  It would look fine until something recoloured it.  Baking it
-- dark-on-light also matches the Gen 3 page and the light boxes this engine
-- draws, so the same sheet is right for both paths.
Gen4Font.DEFAULT_COLORS = {
  [0] = nil,               -- nothing
  { 40, 40, 52 },          -- foreground: the letter, and the DARK tone
  { 184, 184, 200 },       -- shadow: the LIGHT tone
  nil,                     -- background: the text box's, not the glyph's
}

-- parse(data) -> { numGlyphs, glyphWidth, glyphHeight, maxWidth, maxHeight,
--                  tilesWide, tilesHigh, pixelWidth, pixelHeight, widths = {} }
function Gen4Font.parse(data)
  if type(data) ~= "string" or #data < Gen4Font.HEADER_BYTES then
    return nil, "not a font"
  end

  local dataOffset = u32(data, 1)
  local widthTableOffset = u32(data, 5)
  local numGlyphs = u32(data, 9)
  local maxWidth, maxHeight, tilesWide, tilesHigh = byte(data, 13, 16)
  if not tilesHigh then return nil, "font header is truncated" end

  -- The game asserts both of these are 1 or 2; anything else means this is not
  -- an NFGR and should not be read as one.
  if tilesWide < 1 or tilesWide > 2 or tilesHigh < 1 or tilesHigh > 2 then
    return nil, "font tile dimensions are out of range"
  end
  if numGlyphs == 0 or numGlyphs > 65535 then return nil, "implausible glyph count" end

  local glyphBytes = Gen4Font.TILE_BYTES * tilesWide * tilesHigh
  local expected = dataOffset + numGlyphs * glyphBytes + numGlyphs

  local font = {
    dataOffset = dataOffset,
    widthTableOffset = widthTableOffset,
    numGlyphs = numGlyphs,
    maxWidth = maxWidth, maxHeight = maxHeight,
    tilesWide = tilesWide, tilesHigh = tilesHigh,
    pixelWidth = tilesWide * 8, pixelHeight = tilesHigh * 8,
    glyphBytes = glyphBytes,
    data = data,
    -- Whether the file is exactly the size its own header implies.  Recorded
    -- rather than asserted, because a font that is merely padded is still
    -- readable and refusing it would lose a font over a trailing byte.
    exact = (expected == #data),
    expectedBytes = expected,
  }

  font.widths = {}
  for i = 0, numGlyphs - 1 do
    font.widths[i] = byte(data, widthTableOffset + i + 1) or maxWidth
  end

  return font
end

-- glyph(font, index) -> array of pixelWidth * pixelHeight ROLE values (0..3),
-- row-major, plus the glyph's advance width.
--
-- `index` is zero-based.  A character code maps to it by subtracting one --
-- charcode 1 is glyph 0 -- which is what FontManager_TryLoadGlyph does.
function Gen4Font.glyph(font, index)
  if not font or index < 0 or index >= font.numGlyphs then return nil end

  local at = font.dataOffset + index * font.glyphBytes
  local w, h = font.pixelWidth, font.pixelHeight
  local out = {}
  for i = 1, w * h do out[i] = 0 end

  for tile = 0, font.tilesWide * font.tilesHigh - 1 do
    -- Tiles run in reading order inside the glyph.
    local tileX = (tile % font.tilesWide) * 8
    local tileY = floor(tile / font.tilesWide) * 8
    local tileAt = at + tile * Gen4Font.TILE_BYTES

    for row = 0, 7 do
      local low = byte(font.data, tileAt + row * 2 + 1)
      local high = byte(font.data, tileAt + row * 2 + 2)
      if not high then break end
      -- High byte first: the game evaluates `row16 >> 8` before `row16 & 0xFF`,
      -- and on a little-endian u16 the high byte is the SECOND byte stored.
      for half = 0, 1 do
        local source = (half == 0) and high or low
        for pixel = 0, 3 do
          -- MSB first within the byte.
          local shift = 2 ^ (6 - pixel * 2)
          local value = floor(source / shift) % 4
          local x = tileX + half * 4 + pixel
          local y = tileY + row
          out[y * w + x + 1] = value
        end
      end
    end
  end

  return out, font.widths[index] or font.maxWidth
end

-- sheet(font, options) -> { width, height, rgba }
--
-- Every glyph laid out on a grid, for looking at.  `columns` defaults to 32;
-- `colors` is a role -> { r, g, b } table, nil for transparent.
function Gen4Font.sheet(font, options)
  options = options or {}
  local columns = options.columns or 32
  local colors = options.colors or Gen4Font.DEFAULT_COLORS
  if not font then return nil end

  local gw, gh = font.pixelWidth, font.pixelHeight
  local rows = math.ceil(font.numGlyphs / columns)
  local width, height = columns * gw, rows * gh

  local out = {}
  local blank = string.char(0, 0, 0, 0)
  for i = 1, width * height do out[i] = blank end

  for index = 0, font.numGlyphs - 1 do
    local pixels = Gen4Font.glyph(font, index)
    if pixels then
      local ox = (index % columns) * gw
      local oy = floor(index / columns) * gh
      for y = 0, gh - 1 do
        for x = 0, gw - 1 do
          local role = pixels[y * gw + x + 1]
          local colour = colors[role]
          if colour then
            out[(oy + y) * width + ox + x + 1] =
              string.char(colour[1], colour[2], colour[3], 255)
          end
        end
      end
    end
  end

  return { width = width, height = height, rgba = table.concat(out) }
end

-- looksLikeFont(data) -> true when the header parses and the file accounts for
-- itself exactly.  Used to tell an NFGR from anything else in an archive,
-- since it carries no magic to test.
function Gen4Font.looksLikeFont(data)
  local font = Gen4Font.parse(data)
  return font ~= nil and font.exact == true
end

return Gen4Font
