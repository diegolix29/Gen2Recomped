-- BLACK AND WHITE'S FONTS: Nitro NFTR ("RTFN" on disk), /a/0/2/3.
--
-- Gen 4's fonts are Game Freak's own NFGR; Gen 5 moved to the SDK's standard
-- font format, whose layout is public (the NitroSystem font file):
--
--   header  "RTFN", u16 BOM, u16 version, u32 size, u16 header size, u16 blocks
--   FINF    u32 size, u8 type, u8 line feed, u16 alt glyph, 3 bytes default
--           widths, u8 encoding, u32 CGLP, u32 CWDH, u32 CMAP (each pointing
--           8 bytes into its block)
--   CGLP    u32 size, u8 cell width, u8 cell height, u16 bytes per glyph,
--           u8 baseline, u8 max width, u8 bpp, u8 rotation, then the glyphs
--           (row-major, most significant bits first)
--   CWDH    u32 size, u16 first, u16 last, u32 next, then { s8 left, u8 glyph
--           width, u8 advance } per glyph
--   CMAP    u32 size, u16 first code, u16 last code, u16 type, u16 pad, u32 next,
--           then type 0: u16 first glyph (code - first + it); type 1: u16 per
--           code (0xFFFF none); type 2: u16 count, { u16 code, u16 glyph } pairs
--
-- A glyph's 2-bit pixels are the same four roles Gen4Font colours (none, text,
-- shadow, background), so the sheet is drawn by Gen4Font.sheet unchanged.

local F = {}

local function u8(s, o) return s:byte(o + 1) or 0 end
local function u16(s, o) return u8(s, o) + u8(s, o + 1) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end
local function s8(s, o) local v = u8(s, o); return v >= 128 and v - 256 or v end

function F.parse(data)
  if type(data) ~= "string" or data:sub(1, 4) ~= "RTFN" then return nil, "not an NFTR font" end
  local finf = u16(data, 12)
  if data:sub(finf + 1, finf + 4) ~= "FNIF" then return nil, "no FINF block" end
  local cglp, cwdh, cmap = u32(data, finf + 0x10), u32(data, finf + 0x14), u32(data, finf + 0x18)
  -- each offset points 8 bytes into its block (past magic and size)
  local g = cglp
  local cellW, cellH, glyphBytes = u8(data, g), u8(data, g + 1), u16(data, g + 2)
  local bpp = u8(data, g + 6)
  local blockSize = u32(data, g - 4)
  local count = math.floor((blockSize - 16) / glyphBytes)
  local font = { pixelWidth = cellW, pixelHeight = cellH, bpp = bpp, glyphBytes = glyphBytes,
                 numGlyphs = count, glyphAt = g + 8, data = data, widths = {}, lefts = {}, advances = {},
                 codes = {} }
  -- widths: possibly several CWDH blocks chained by `next`
  local at = cwdh
  while at and at > 0 and at < #data do
    local first, last, nextAt = u16(data, at), u16(data, at + 2), u32(data, at + 4)
    for i = first, last do
      local o = at + 8 + (i - first) * 3
      font.lefts[i], font.widths[i], font.advances[i] = s8(data, o), u8(data, o + 1), u8(data, o + 2)
    end
    at = nextAt ~= 0 and nextAt or nil
  end
  -- character map, chained the same way
  at = cmap
  local guard = 0
  while at and at > 0 and at < #data and guard < 512 do
    guard = guard + 1
    local first, last, kind, nextAt = u16(data, at), u16(data, at + 2), u16(data, at + 4), u32(data, at + 8)
    local body = at + 12
    if kind == 0 then
      local base = u16(data, body)
      for c = first, last do font.codes[c] = base + (c - first) end
    elseif kind == 1 then
      for c = first, last do
        local gi = u16(data, body + (c - first) * 2)
        if gi ~= 0xFFFF then font.codes[c] = gi end
      end
    elseif kind == 2 then
      local n = u16(data, body)
      for i = 0, n - 1 do font.codes[u16(data, body + 2 + i * 4)] = u16(data, body + 4 + i * 4) end
    end
    at = nextAt ~= 0 and nextAt or nil
  end
  font.maxWidth = cellW
  -- EACH GLYPH SLOT OPENS WITH ITS OWN WIDTH RECORD. The slot is 48 bytes and
  -- a 12 x 15 bitmap at 2 bpp is 45: the first three are { s8 left, u8 glyph
  -- width, u8 advance } -- every glyph, the space included, carries them --
  -- and the bitmap follows. (Read as bitmap they are the stray top row of
  -- dots every line of text showed; "T" is 0, 6, 6 and the space 4, 0, 4.)
  font.recordBytes = glyphBytes - math.ceil(cellW * cellH * bpp / 8)
  if font.recordBytes < 0 then font.recordBytes = 0 end
  if font.recordBytes >= 3 then
    for i = 0, count - 1 do
      local base = font.glyphAt + i * glyphBytes
      font.lefts[i] = s8(data, base)
      font.widths[i] = u8(data, base + 2)
    end
  end
  return font
end

-- glyph(font, index) -> { role per pixel, row-major }
function F.glyph(font, index)
  if index < 0 or index >= font.numGlyphs then return nil end
  local base = font.glyphAt + index * font.glyphBytes + (font.recordBytes or 0)
  local out, bits = {}, font.bpp
  local per = math.floor(8 / bits)
  for p = 0, font.pixelWidth * font.pixelHeight - 1 do
    local byte = u8(font.data, base + math.floor(p / per))
    local shift = 8 - bits * (p % per + 1)
    out[p + 1] = math.floor(byte / 2 ^ shift) % (2 ^ bits)
  end
  return out
end

-- sheet(font) -> image through Gen4Font.sheet's colouring
function F.sheet(font, options)
  local Gen4Font = require("src.import.Gen4Font")
  local saved = Gen4Font.glyph
  Gen4Font.glyph = function(_, index) return F.glyph(font, index) end
  local ok, sheet = pcall(Gen4Font.sheet, font, options)
  Gen4Font.glyph = saved
  return ok and sheet or nil
end

local function utf8(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

-- charmap(font, base) -> { { code = glyph + base, seq = UTF-8 } }, sorted
function F.charmap(font, base)
  local out = {}
  for cp, gi in pairs(font.codes) do
    if cp >= 0x20 and gi < font.numGlyphs then out[#out + 1] = { code = gi + (base or 1), seq = utf8(cp) } end
  end
  table.sort(out, function(a, b) return a.code < b.code end)
  return out
end

return F
