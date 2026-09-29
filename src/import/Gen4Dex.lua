-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum): the POKEDEX's entry page, and why it composed blank.
--
-- Reported from play: the Pokedex is "looking like gen1 still".  It was, and
-- the reason was not a missing screen -- a screen was refused deliberately,
-- because THE ART COMPOSED BLANK.  275 of the 282 pictures the graphics stage
-- wrote under `pokedex/` are under 400 bytes; `info_main` is 256x192 of nothing
-- and every one of those records carries `borrowedTiles` or `borrowedPalette`,
-- which is the planner saying it could not find the pairing.
--
-- IT COULD NOT FIND THE PAIRING BECAUSE THERE ISN'T ONE.  `zukan.narc` does not
-- name its parts to match: the palettes, the tile sheets and the tilemaps are
-- three separate name spaces, and a handful of sheets and palettes serve dozens
-- of tilemaps.  `info_main.NSCR` has no `info_main.NCGR` and no `info_main.NCLR`
-- anywhere in the archive.  Grouping by base name -- which is exactly right for
-- every other screen archive -- gives it a tilemap with no tiles and no colours,
-- so it borrows the archive's first of each and paints nothing.
--
-- AND IT IS NOT ONE TILEMAP PER PICTURE.  The entry page is FOUR tilemaps laid
-- into one 32x24 grid.  `ov21_021E96A8` is the whole of it in one function:
--
--     Graphics_LoadPaletteFromOpenNARC(narc, banner_sinnoh_NCLR, 0, 0, 0)
--     Graphics_LoadTilesToBgLayerFromOpenNARC(narc, entry_main_NCGR_lz, bg, 3)
--     info_main.NSCR             -> rect (0,  0)
--     info_species_window.NSCR   -> rect (0,  3)
--     info_footprint_window.NSCR -> rect (12, 8)
--     info_entry_window.NSCR     -> rect (0, 16)
--
-- THE PALETTE IS `banner_sinnoh.NCLR`, and that is the fact no amount of
-- looking at names would have produced: the entry page's colours are filed
-- under the banner.  `info.NCLR` exists and is a SPRITE palette, used only for
-- the page buttons.  A reader who paired `info_main` with `info` would get a
-- picture, and a wrong one.
--
-- CHECKED TWICE, because a wrong member index in an unnamed-by-role archive
-- still decodes.  The indices below come from
-- `res/graphics/pokedex/pokedex.order` -- the file pokeplatinum's build feeds
-- its archiver -- and every one of them agrees with the name table this port
-- already carries in `Gen4Archives`.  The RECT sizes are checked a third way:
-- against the widths and heights the graphics stage already recorded for those
-- five members.  info_main is 32x24 tiles at (0,0); info_species_window 12x12
-- at (0,3); info_footprint_window 6x6 at (12,8); info_entry_window 32x8 at
-- (0,16), which ends exactly at the bottom row.  Every rect fits, and the two
-- full-width ones are exactly the screen.
--
-- Members are looked up BY NAME at extraction time rather than by these
-- numbers.  The numbers are here so a reader can check the claim.

local Gen4Dex = {}

Gen4Dex.PATH = "/resource/eng/zukan/zukan.narc"

-- name, and the member it is in this cartridge.
Gen4Dex.PALETTE = "banner_sinnoh.NCLR"          -- 6
Gen4Dex.PALETTE_NATIONAL = "banner_national.NCLR" -- 24, overwrites the first row
Gen4Dex.TILES = "entry_main.NCGR.lz"            -- 33
Gen4Dex.BANNER_MAP = "banner_sinnoh.NSCR.lz"    -- 57

-- The entry page, in the order the app lays them down.
Gen4Dex.ENTRY_LAYERS = {
  { name = "info_main.NSCR.lz",             x = 0,  y = 0 },   -- 50
  { name = "info_species_window.NSCR.lz",   x = 0,  y = 3 },   -- 51
  { name = "info_footprint_window.NSCR.lz", x = 12, y = 8 },   -- 52
  { name = "info_entry_window.NSCR.lz",     x = 0,  y = 16 },  -- 54
}

Gen4Dex.SCREEN_TILES_W, Gen4Dex.SCREEN_TILES_H = 32, 24

-- ---------------------------------------------------------------------------
-- Where the words and the pictures go on that page
-- ---------------------------------------------------------------------------

-- Every one of these is a literal out of `infomain.c`, so the port's page reads
-- like the cartridge's rather than like a tidy arrangement of the same facts.
--
--   PokedexMain_DisplayPokemonSprite(..., 2, 48, 72)     the Pokemon
--   PokedexMain_EntryNameNumber(..., 172 << 12, 32 << 12) the name and number
--   the category box sprite at (192, 52) with its text at (-78, -8)
--   "HT" at (152, 88) and its value at (184, 88)
--   "WT" at (152, 104) and its value at (184, 104)
--   the entry text centred on x = 128 at y = 136, or at x = 8 when it is
--   wider than 240 -- which is the cartridge's own overflow rule and not a
--   clamp invented here
Gen4Dex.LAYOUT = {
  sprite = { x = 48, y = 72 },
  nameNumber = { x = 172, y = 32 },
  category = { x = 192 - 78, y = 52 - 8 },
  heightLabel = { x = 152, y = 88 },
  heightValue = { x = 184, y = 88 },
  weightLabel = { x = 152, y = 104 },
  weightValue = { x = 184, y = 104 },
  entry = { centre = 128, y = 136, maxWidth = 240, overflowX = 8 },
  footprint = { x = 12 * 8, y = 8 * 8, size = 48 },
}

-- Which entry of the Pokedex's own label bank is which.  From
-- `res/text/pokedex.json`: 0 seen, 1 obtained, 5 switch, 7 search, 9 HT,
-- 10 WT, 11 ft, 12 lbs.
Gen4Dex.LABEL = { seen = 0, obtained = 1, height = 9, weight = 10 }

-- How far to walk the three per-species banks.  493 is the national dex and
-- the banks carry a few entries past it for the forms; walking to a fixed
-- ceiling and stopping at the last hit is cheaper than asking each bank its
-- length and cannot read past the end -- `self:string` returns nil for an
-- index the bank does not have.
Gen4Dex.MAX_SPECIES = 600

return Gen4Dex
