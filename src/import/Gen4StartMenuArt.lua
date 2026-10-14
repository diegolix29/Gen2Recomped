-- PLATINUM'S FIELD START MENU ICONS (src/start_menu.c StartMenu_InitSprites),
-- from /graphic/menu_gra.narc: icons.NCGR, icons_cell.NCER, icons_anim.NANR
-- under menu.NCLR.
--
-- Each option's icon is animation option * 3 + {0 still, 1 swell, 2 wiggle}
-- (a female player's BAG is option 9's), and its palette is SET, not added:
-- Sprite_SetExplicitPaletteWithOffset(PALETTE_GRAYSCALE = 0 or PALETTE_COLORED
-- = 1) -- so every cell is assembled twice, with menu.NCLR row 0 and row 1,
-- whatever its OAM entries say.
--
-- Pictures: icon_<cell>_<row> (32x32, origin -16,-16). Data
-- (`gen4_start_menu_ink`): anims[seq + 1] = { mode, frames = { { cell,
-- duration, rot, sx, sy, x, y } } } -- the swell is an SRT scale 1 -> 1.3 -> 1,
-- the wiggle a +-10 degree rotation.

local Gen4StartMenuArt = {}

Gen4StartMenuArt.PATH = "/graphic/menu_gra.narc"

local function opener(rom)
  local G = require("src.import.Gen4Graphics")
  local A = require("src.import.Gen4Archives")
  local bytes = rom:read(Gen4StartMenuArt.PATH)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return function(name)
    local i = A.find(Gen4StartMenuArt.PATH, name)
    local b = i and narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

function Gen4StartMenuArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local member = opener(rom)
  if not member then return nil, "menu_gra missing" end
  local pal = G.palette(member("menu.NCLR"))
  local sheet = G.tiles(member("icons.NCGR"))
  local bank = Cells.parse(member("icons_cell.NCER"), G)
  if not (pal and sheet and bank) then return nil, "menu_gra icons unreadable" end
  local out = {}
  for row = 0, 1 do
    local colours = {}
    for i = 1, 16 do colours[i] = pal[row * 16 + i] or { 0, 0, 0 } end
    for i, cell in ipairs(bank.cells) do
      local flat = { oam = {} }
      for k, v in pairs(cell) do if k ~= "oam" then flat[k] = v end end
      for j, o in ipairs(cell.oam) do
        local c = {}
        for k, v in pairs(o) do c[k] = v end
        c.palette = 0
        flat.oam[j] = c
      end
      local pic = Cells.assemble(flat, sheet, colours, bank, G)
      if pic then
        pic.originX, pic.originY = Cells.extent(flat)
        out[("icon_%02d_%d"):format(i - 1, row)] = pic
      end
    end
  end
  return out
end

function Gen4StartMenuArt.data(rom)
  local G = require("src.import.Gen4Graphics")
  local member = opener(rom)
  if not member then return nil end
  return { anims = require("src.import.Gen4PoketchArt").anims(member("icons_anim.NANR"), G) }
end

return Gen4StartMenuArt
