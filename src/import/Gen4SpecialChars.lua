-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4SpecialChars.lua -- THE NUMBERS THAT ARE NOT TEXT.
--
-- !! THIS FILE EXISTS BECAUSE A NOTE IN THIS PORT WAS WRONG, AND THE NOTE WAS
-- MINE.  docs/gen4-platinum.md said the healthbox's HP numbers were blitted
-- from `sHealthBoxPartsBitmap` -- "HEALTHBOX_PART_NUMBERS_LEFT, _NUMBERS_RIGHT
-- and _SLASH (healthbox.c 840-845)".  Those three parts ARE at those lines and
-- they are NOT the numbers: line 840 is inside `Healthbox_ToggleHPDisplayMode`,
-- which `switch`es on the box type and RETURNS for anything but
-- PLAYER_SLOT_1/2 -- the two DOUBLES boxes, where the bar and the numbers are
-- alternatives.  They are the empty NUMBER FIELD that replaces the bar.
--
-- WHAT ACTUALLY DRAWS A NUMBER, on every box and in both places:
--
--     FontSpecialChars_DrawBattleScreenText(ctx, value, 3, padding, buf)
--
-- called by HealthBox_DrawCurrentHP (1245), HealthBox_DrawMaxHP (1262) and
-- HealthBox_DrawLevelNumber (1208).  The face is `font_special_chars.NCGR`
-- inside pl_font.narc: TWENTY-THREE 8x8 TILES, one glyph per tile --
--
--     0..9  the digits      10  "/"      11-12  "Lv."
--     13-14 "No."           15-16 "ID."  17-22  three unused Lv variants
--
-- and `sNonNumericWidths` in font_special_chars.c states every one of those
-- offsets outright, in tiles, which is the second reading of the layout.
--
-- A SECOND CORRECTION RIDES ALONG.  The same note said DrawLevelNumber and
-- DrawMaxHP print with FONT_SYSTEM "(healthbox.c 1316, 1355)".  Those two lines
-- are `HealthBox_DrawBallCount` and `HealthBox_DrawBallsLeftMessage` -- the
-- SAFARI ball counter.  Only ONE thing on a healthbox is set in the system
-- face, and it is the NICKNAME (1143).  Everything numeric is this strip.
--
-- ---------------------------------------------------------------------------
-- THE COLOURS ARE THE CALLER'S, NOT THE SHEET'S
--
-- The tile data is not a picture.  Every nibble is 0, 1 or 2 -- background,
-- foreground, shadow -- and `FontSpecialChars_Init(fg, shadow, bg)` rewrites
-- them into real palette indices before the strip is ever drawn.  The battle
-- asks for (14, 2, 15) at battle_main.c 529, into the HEALTHBOX family's own
-- palette, and the line after it is what makes this one table and not two:
--
--     battleSys->specialCharsLevel = battleSys->specialCharsHP;
--
-- THE LEVEL AND THE HP ARE THE SAME FACE IN THE SAME COLOURS.
--
-- MEASURED, in the healthbox palette: 14 is WHITE (255, 255, 255), 2 is the
-- dark green (41, 49, 41), and 15 is (107, 115, 90) -- WHICH IS THE COLOUR THE
-- BOX ALREADY IS under the number band.  The assembled art says the same thing
-- from the other side: rows 39..47 of healthbox_player_singles are that exact
-- green, flat, all the way across.  So the background is not a colour the
-- cartridge paints ON, it is the colour that was already there -- and this
-- stage writes it TRANSPARENT, which is the same picture on the box and the
-- right one anywhere else the strip is used.
--
-- (It is used elsewhere: the party screen's HP, the bag, the shop and the
-- Battle Castle all build their own context off this same sheet with their own
-- three colours.  Only the battle's are written here, because only the battle
-- draws from it yet.)

local Gen4SpecialChars = {}

Gen4SpecialChars.PATH = "/graphic/pl_font.narc"

-- pl_font.order: font_system, font_message, font_subscreen, font_unown,
-- font_special_chars, screen_indicators, font.NCLR, screen_indicators.NCLR.
-- The first four are NFGR (a font format this reader does not decode) and the
-- fifth is the NCGR wanted here -- the only LZ-compressed member of the eight,
-- which is a second way to find it if the order file ever moves.
Gen4SpecialChars.MEMBER = 4

Gen4SpecialChars.TILE = 8
Gen4SpecialChars.TILE_BYTES = 32        -- TILE_SIZE_4BPP
Gen4SpecialChars.COUNT = 23

-- Zero-based tile indices, from sNonNumericWidths' own offsets (divided by
-- TILE_SIZE_4BPP) plus the ten digits the numeric path indexes directly as
-- `charcode - CHAR_WIDE_0`.
Gen4SpecialChars.DIGIT_0 = 0
Gen4SpecialChars.DIGITS = 10
Gen4SpecialChars.GLYPHS = {
  slash = { at = 10, tiles = 1 },
  level = { at = 11, tiles = 2 },
  number = { at = 13, tiles = 2 },
  id = { at = 15, tiles = 2 },
}

-- The three roles, as the BATTLE asks for them (battle_main.c 529).  Indices
-- into the healthbox family's palette; `bg` is recorded rather than used,
-- because a value of 0 is what compose treats as transparent and that is what
-- this sheet is written with.  See the header for why they are the same thing.
Gen4SpecialChars.BATTLE_FG = 14
Gen4SpecialChars.BATTLE_SHADOW = 2
Gen4SpecialChars.BATTLE_BG = 15

-- The raw nibble values in the sheet, before any caller rewrites them.
Gen4SpecialChars.RAW_BG = 0
Gen4SpecialChars.RAW_FG = 1
Gen4SpecialChars.RAW_SHADOW = 2

-- Build the little palette `Gen4Graphics.compose` needs to draw the strip in
-- one caller's colours.  Entry 1 is never read (compose leaves value 0
-- transparent) and is present so the array is dense; entries 2 and 3 are the
-- caller's foreground and shadow, in the raw values' own order.
--
-- `palette` is the family palette as Gen4Graphics.palette returns it: one
-- { r, g, b } per entry, so the cartridge's index k is palette[k + 1].
function Gen4SpecialChars.rolePalette(palette, fg, shadow)
  if type(palette) ~= "table" then return nil end
  fg = fg or Gen4SpecialChars.BATTLE_FG
  shadow = shadow or Gen4SpecialChars.BATTLE_SHADOW
  local f, s = palette[fg + 1], palette[shadow + 1]
  if not (f and s) then return nil end
  return { f, f, s }
end

-- Is this member the strip?  Decoded tile count and the fact that nothing in
-- it uses a nibble above the three roles -- which is the whole content of "it
-- is not a picture".  The three unused Lv variants DO carry higher values, so
-- the test is over the twenty-three's first seventeen tiles: the digits, the
-- slash and the three two-tile words.
Gen4SpecialChars.ROLE_TILES = 17

function Gen4SpecialChars.looksRight(pixels)
  if type(pixels) ~= "string" then return false, "no pixels" end
  local need = Gen4SpecialChars.TILE_BYTES * Gen4SpecialChars.COUNT
  if #pixels < need then
    return false, ("%d bytes, expected at least %d"):format(#pixels, need)
  end
  local roleBytes = Gen4SpecialChars.TILE_BYTES * Gen4SpecialChars.ROLE_TILES
  for i = 1, roleBytes do
    local b = pixels:byte(i)
    if b % 16 > Gen4SpecialChars.RAW_SHADOW
       or math.floor(b / 16) > Gen4SpecialChars.RAW_SHADOW then
      return false, ("tile %d uses a value above %d")
        :format(math.floor((i - 1) / Gen4SpecialChars.TILE_BYTES),
                Gen4SpecialChars.RAW_SHADOW)
    end
  end
  return true
end

return Gen4SpecialChars
