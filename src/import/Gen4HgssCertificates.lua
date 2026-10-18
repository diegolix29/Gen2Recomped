-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S CERTIFICATES (`ShowCertificate <id>`,
-- pokeheartgold src/certificates_app.c ov78_021E5EA4): the Johto Pokedex
-- diploma (0), the National Pokedex diploma (1) and the Shiny Leaf crown's
-- certificate (2), each two backgrounds out of NARC_a_1_2_6 (/a/1/2/6):
--
--               BG3 (back)            BG1 (frame, palette line 1)
--   id    NSCR  NCGR  NCLR      NSCR  NCGR  NCLR
--   0      15     3     9        12     0     6
--   1      16     4    10        13     1     7
--   2      17     5    11        14     2     8
--
-- Each palette is loaded as one 16-colour line (0x20 bytes) and BG1's tilemap
-- is repainted onto line 1 (BgTilemapRectChangePalette), so both layers read
-- the first sixteen colours of their own NCLR whatever their cells name.
-- The same picture is on both screens; the text (msg_0004) is printed by
-- src/ui/HgssCertificate.lua.

local Gen4Graphics = require("src.import.Gen4Graphics")

local C = { PATH = "/a/1/2/6", FONT_PATH = "/a/0/1/6", FONT_PALETTE = 7 }

C.LAYERS = {
  [0] = { back = { 15, 3, 9 }, front = { 12, 0, 6 } },
  [1] = { back = { 16, 4, 10 }, front = { 13, 1, 7 } },
  [2] = { back = { 17, 5, 11 }, front = { 14, 2, 8 } },
}

local function member(arc, i)
  local b = arc and arc:get(i)
  if b and Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
end

-- one 16-colour line, repeated across every line a cell could name
local function oneLine(pal)
  if not pal then return nil end
  local out = {}
  for line = 0, 15 do
    for i = 1, 16 do out[line * 16 + i] = pal[i] end
  end
  return out
end

function C.build(x)
  local Narc = require("src.import.NarcArchive")
  local arc = assert(Narc.parse(assert(x.rom:read(C.PATH))))
  local out = { source = "ROM:" .. C.PATH .. " (certificates_app.c ov78_021E5EA4)", certificates = {} }
  for id, layers in pairs(C.LAYERS) do
    local rec = {}
    for _, name in ipairs({ "back", "front" }) do
      local scr, chr, pal = layers[name][1], layers[name][2], layers[name][3]
      local map = Gen4Graphics.tilemap(member(arc, scr))
      local tiles = Gen4Graphics.tiles(member(arc, chr))
      local colours = oneLine((Gen4Graphics.palette(member(arc, pal))))
      local img = map and tiles and colours and Gen4Graphics.compose(map, tiles, colours)
      rec[name] = img and x:saveImage(("certificates/%d_%s"):format(id, name), img) or nil
      if name == "back" and colours and colours[1] then
        rec.backdrop = { colours[1][1], colours[1][2], colours[1][3] }
      end
    end
    if rec.back or rec.front then out.certificates[id] = rec end
  end
  assert(next(out.certificates), "no certificate composed")
  -- THE INK: every line prints MAKE_TEXT_COLOR(1, 2, 0) on LoadFontPal0 --
  -- NARC_graphic_font (/a/0/1/6) member 7 -- letter colour 1, shadow 2
  local okF, font = pcall(function() return Narc.parse(assert(x.rom:read(C.FONT_PATH))) end)
  local fp = okF and font and Gen4Graphics.palette(member(font, C.FONT_PALETTE))
  if fp and fp[2] and fp[3] then
    out.ink = { { fp[2][1], fp[2][2], fp[2][3] }, { fp[3][1], fp[3][2], fp[3][3] } }
  end
  return out
end

return C
