-- HEARTGOLD / SOULSILVER'S FIELD MENU (/a/0/1/4; src/start_menu.c and
-- overlay 27, the field touch menu, in pokeheartgold): the bottom screen's
-- green panel of icon buttons. Written as `gen4_hgss_menu_art`.
--
--   panel          screen 9 / char 8 / palette 7 (`ov27_0225CEEC/F0/F4`): the
--                  green panel x 4..164 with its header strip, the grey column
--   idle           screen 11 / char 10 / palette 7: the field's touch screen
--                  while the menu is shut (the Poke Ball)
--   icon_<g>_<s>   each button's own NCGR g with its one cell (g + 1), 40 x 32,
--                  in palette 14 row s: 0 at rest, 1 selected (the red rim)
--   close          the header's (x) mark, cell 13 of 70 / 68
--
-- `ink` is palette 7 row 4 (the labels' window palette): colour 14 letter,
-- 7 shadow (`ov27_0225CEC4` state 0).

local A = {}

A.PATH = "/a/0/1/4"
-- `ov27_0225CF94`: { NCGR, bank 196 entry }
A.ICONS = {
  pokedex = { 18, 0 }, pokemon = { 21, 1 }, bag = { 24, 2 }, bagFemale = { 27, 2 },
  pokegear = { 30, 14 }, trainerCase = { 33, 3 }, save = { 36, 4 }, options = { 39, 5 },
  retire = { 42, 8 },
}

function A.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local raw = rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i) local b = arc:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
  local out = {}
  local function bg(key, s, c, p, h)
    local map, sheet, pal = G.tilemap(m(s)), G.tiles(m(c)), G.palette(m(p))
    local img = map and sheet and pal and G.compose(map, sheet, pal)
    if img and h and img.height > h then img = { width = img.width, height = h, rgba = img.rgba:sub(1, img.width * h * 4) } end
    out[key] = img
  end
  bg("panel", 9, 8, 7, 192)
  bg("idle", 11, 10, 7, 192)
  local ipal = G.palette(m(14))
  if ipal then
    for _, def in pairs(A.ICONS) do
      local g = def[1]
      local sheet, bank = G.tiles(m(g)), Cells.parse(m(g + 1), G)
      local cell = bank and bank.cells[1]
      for row = 0, 1 do
        local pal = {}
        for k = 1, 256 do pal[k] = ipal[k] or { 0, 0, 0 } end
        for k = 1, 16 do pal[k] = ipal[row * 16 + k] end
        local pic = cell and sheet and Cells.assemble(cell, sheet, pal, bank, G)
        if pic then
          pic.originX, pic.originY = Cells.extent(cell)
          out[("icon_%d_%d"):format(g, row)] = pic
        end
      end
    end
    local bank, sheet = Cells.parse(m(68), G), G.tiles(m(70))
    local cell = bank and bank.cells[14]
    local pic = cell and sheet and Cells.assemble(cell, sheet, ipal, bank, G)
    if pic then pic.originX, pic.originY = Cells.extent(cell); out.close = pic end
  end
  return out
end

function A.ink(rom)
  local G = require("src.import.Gen4Graphics")
  local raw = rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  local pal = arc and G.palette(arc:get(7))
  if not pal then return nil end
  local function c(k) local v = pal[4 * 16 + k + 1] or { 0, 0, 0 }; return { v[1] / 255, v[2] / 255, v[3] / 255 } end
  return { letter = c(14), shadow = c(7) }
end

return A
