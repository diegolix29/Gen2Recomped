-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum): the KEYBOARD's own art and geometry.
--
-- Reported from play, twice: the naming screen "is falling back to gen1", and
-- then, after it had a Gen 4 screen of its own, that it "still needs a lot of
-- work before it matches the platinum rom".  It did.  The layout was right --
-- six rows of thirteen, the repeated home-row buttons, the three English pages
-- -- because that much was read out of `NamingScreen_LoadKeyboardLayout`.
-- Everything a player actually LOOKS at was this port's own invention, because
-- `/data/namein.narc` had never been opened.
--
-- THIS ARCHIVE HAS NO NAME TABLE EITHER, so every index below is arithmetic,
-- and arithmetic is what this project has been burned by most.  None of it is
-- inferred: the order is `res/graphics/naming_screen/naming_screen.order` in
-- pokeplatinum -- the file its build feeds to the archiver, which reproduces
-- this cartridge byte for byte -- and every index is then cross-checked
-- against the symbol the app's own loader uses for it in
-- `NamingScreen_LoadGraphicsFromNarc`.  Two independent statements of the same
-- fact, which is the only kind of check worth having here.
--
--    0  naming_screen.NCLR              the background palette
--    1  naming_screen_sprites.NCLR
--    2  naming_screen_main_tiles.NCGR   the tiles BOTH backgrounds are drawn from
--    3  naming_screen_dummy_0.NCGR
--    4  naming_screen_bg.NSCR           the full-screen backdrop
--    5  naming_screen_dummy_1.NSCR
--    6  naming_screen_chars_bg_0.NSCR   the keyboard panel, page 0 (UPPER)
--    7  naming_screen_chars_bg_1.NSCR   page 1 (lower)
--    8  naming_screen_chars_bg_2.NSCR   page 2 (OTHERS)
--    9  naming_screen_chars_bg_3.NSCR   page 3 (the Japanese fourth page)
--   10  naming_screen_sprites.NCGR      the buttons and the cursor
--   12  naming_screen_sprites_cell.NCER
--   14  naming_screen_sprites_anim.NANR
--
-- THE SPRITES ARE NOT EXTRACTED HERE and that is said plainly rather than
-- quietly skipped: members 10/12/14 are a cell bank and its animations, and
-- composing one is a different job from composing a tilemap.  The home row's
-- buttons and the cursor are therefore still drawn in the engine's own frame.
-- The panel behind them, the backdrop, and the colours the keyboard is painted
-- in are the cartridge's.

local Gen4Naming = {}

Gen4Naming.PATH = "/data/namein.narc"

Gen4Naming.PALETTE = 0
Gen4Naming.TILES = 2
Gen4Naming.BACKGROUND_MAP = 4
-- One panel per page, in page order: `naming_screen_chars_bg_0_NSCR_lz +
-- currentCharsIdx` is exactly how the app indexes them when the page changes.
Gen4Naming.PANEL_MAPS = { 6, 7, 8, 9 }

-- ---------------------------------------------------------------------------
-- Where it all sits
-- ---------------------------------------------------------------------------

-- THE PANEL'S RESTING POSITION, and it is a background offset rather than a
-- coordinate.  `NamingScreen_InitializeCharsPosition` parks the active layer at
-- (-11, -80) and the one sliding in at (238, -80); the hardware SCROLLS the
-- view, so an offset of -11 puts the picture eleven pixels to the RIGHT.
Gen4Naming.PANEL_X, Gen4Naming.PANEL_Y = 11, 80

-- ...and the character window inside it: `Window_Add(..., BG_LAYER_MAIN_1, 2,
-- 1, 26, 12, 1, ...)` -- tile (2, 1), twenty-six by twelve tiles, palette row
-- one.  Twenty-six tiles is 208 pixels, which is thirteen columns of sixteen;
-- twelve tiles is 96, which is five rows of nineteen with a pixel to spare.
-- The port had thirteen by SIX at sixteen square and had to guess where to put
-- it; this is the cartridge's own rectangle.
Gen4Naming.WINDOW_TILE_X, Gen4Naming.WINDOW_TILE_Y = 2, 1
Gen4Naming.WINDOW_TILES_W, Gen4Naming.WINDOW_TILES_H = 26, 12
Gen4Naming.WINDOW_PALETTE_ROW = 1

-- The cells, from `NamingScreen_InitializeCharsGraphics` and the
-- `NamingScreen_PrintChars` call inside it: sixteen wide, nineteen tall, five
-- rows, and a glyph sits four pixels down from its cell's top.
Gen4Naming.CELL_W, Gen4Naming.CELL_H = 16, 19
Gen4Naming.CHAR_ROWS, Gen4Naming.COLS = 5, 13
Gen4Naming.GLYPH_INSET = 4

-- THE KEYBOARD IS A CHECKERBOARD, not a flat panel, and it is painted by code
-- rather than stored in the tilemap -- which is why opening the archive alone
-- would not have produced it.  Two colours per page, as palette indices into
-- the window's own row:
--
--   `Window_FillTilemap(window, bgColor)` fills with sCharsBgColor[page], and
--   then two loops fill 16x19 rectangles with sCharsAltBgColor[page]: the odd
--   columns of rows 0, 2 and 4, and the even columns of rows 1 and 3.
--
-- The fourth entry of the alt table is duplicated because the Japanese screen
-- has a fifth page; the English screen never reads past index 2.
Gen4Naming.BG_COLOUR = { 4, 7, 13, 10 }
Gen4Naming.ALT_COLOUR = { 3, 6, 12, 9, 9 }

-- THE HOME ROW IS SPRITES, at their own screen coordinates -- they are not in
-- the panel and not affected by its offset.  `sSpriteAnimations` puts six of
-- them at y = 0x44 and x = 4, 36, 68, 101, 136 and 176.
--
-- Those six are the six buttons the navigation model already has, and their
-- spacing CONFIRMS that model rather than merely being consistent with it: the
-- buttons span 2, 2, 2, 2, 3 and 2 cells of the keyboard's own sixteen-pixel
-- pitch, so laid out from x = 4 they would start at 4, 36, 68, 100, 132 and
-- 180.  Against the cartridge's 4, 36, 68, 101, 136, 176 that is exact on
-- three and within five pixels on the rest -- the difference being that a
-- sprite's x is its art's anchor and not its cell's edge.
--
-- So the row is drawn on the cell pitch from this origin, which is the
-- cartridge's arrangement to within the width of the art that is not extracted.
Gen4Naming.HOME_X = 4
Gen4Naming.HOME_Y = 0x44
Gen4Naming.HOME_SPRITE_X = { 4, 36, 68, 101, 136, 176 }

return Gen4Naming
