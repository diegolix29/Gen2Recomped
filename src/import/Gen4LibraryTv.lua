-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S CANALAVE LIBRARY TELEVISION (StartLibraryTV, library 3F): the
-- news of the Lake Valor explosion the counterpart turns on.
--
-- READ FROM CODE: pokeplatinum src/library_tv/library_tv.c,
-- LibraryTV_SetVramBank.  Three layers, all on the main screen and all at
-- priority 1, so drawn BG0 over BG1 over BG3 (BG2 is cleared and stays empty
-- -- its message loader is opened and never printed from):
--
--   BG0  /demo/intro/intro_tv.narc tiles 1, screen 4   the set's bezel
--   BG1  /demo/intro/intro_tv.narc tiles 2, screen 5   the scan lines
--   BG3  /graphic/library_tv.narc  tiles 2, screen 4   the picture (256 colour)
--
-- ONE PALETTE for all three: Graphics_LoadPalette(LIBRARY_TV, 3, main BG,
-- offset 0, size 0 = the whole file).  The intro's own palettes are NOT
-- loaded, so the bezel and scan lines wear library_tv's colours -- composing
-- them with the intro's would be the intro's picture, not this one.
-- Bg_MaskPalette(BG_LAYER_MAIN_0, 0) makes the backdrop black.  The font
-- palette lands in row 1 and nothing prints with it.
--
-- The app's timing and blend (BG1 at 4/16 over BG2|BG3 at 12/16, the scan
-- lines scrolled down a quarter pixel a frame) are the screen's:
-- src/ui/Gen4LibraryTvScreen.lua.

local M = {}

M.INTRO_TV = "/demo/intro/intro_tv.narc"
M.LIBRARY_TV = "/graphic/library_tv.narc"
M.PALETTE = 3
M.LAYERS = {
  { name = "bezel",     path = "/demo/intro/intro_tv.narc", tiles = 1, screen = 4 },
  { name = "scanlines", path = "/demo/intro/intro_tv.narc", tiles = 2, screen = 5 },
  { name = "picture",   path = "/graphic/library_tv.narc",  tiles = 2, screen = 4 },
}

function M.build(x)
  local lib = assert(x:archiveAt(M.LIBRARY_TV), "no " .. M.LIBRARY_TV)
  local palette = assert(x:paletteMember(lib, M.PALETTE), "no library_tv palette")
  local out = { source = "ROM:" .. M.LIBRARY_TV .. " + " .. M.INTRO_TV .. " (pokeplatinum library_tv.c)",
                layers = {} }
  for _, layer in ipairs(M.LAYERS) do
    local arc = assert(x:archiveAt(layer.path), "no " .. layer.path)
    local image = x:composeWith(arc, layer.tiles, layer.screen, palette)
    local entry = x:saveImage("library_tv/" .. layer.name, image,
                              { tiles = layer.tiles, screen = layer.screen })
    out.layers[layer.name] = entry
  end
  return out
end

return M
