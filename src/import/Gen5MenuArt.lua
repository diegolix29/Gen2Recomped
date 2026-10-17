-- BLACK AND WHITE'S FIELD MENU (/a/0/7/1, the same in both games;
-- scratch_claude/bw_ui_map.md section 3), written as `gen5_menu_art`. No
-- symbols: pairings found by composing every combination, checked against
-- Bulbapedia's capture of the cartridge.
--
--   backdrop      screen 14 on char 2, palette 0: the grid paper with its grey
--                 strips top and bottom
--   buttons_<n>   screens 16 / 17 / 18 (256 x 512; the buttons are in the top
--                 256): the dark folder tabs, 2 columns, for 6 / 4 / 5 entries
--   icon_<i>_<c>  OBJ icon i (char i, cell i + 15, anim i + 25), cell c, in
--                 palette 1 (its rows 8 and up): 5 options, 6 / 7 bag (boy /
--                 girl), 8 Pokemon, 9 save, 10 trainer card, 11 / 12 Pokedex
--   cursor_<c>    13 / 28: the cyan tab the cursor is
--   close         /a/0/8/3's red (x) touch button (char 20, cell 21, pal 19)

local A = {}

A.PATH = "/a/0/7/1"
A.BUTTONS = { [6] = 16, [4] = 17, [5] = 18 }

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local Narc = require("src.import.NarcArchive")
  local raw = x.rom:read(A.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function mm(a, i)
    local b = a and a:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local function m(i) return mm(arc, i) end
  local index = { _source = "ROM:/a/0/7/1 (14/16/17/18 on 2, icons 4-13 / 19-28, pal 0/1), /a/0/8/3 close" }
  local function save(key, image, extra)
    local entry = image and x:saveImage("bw_menu/" .. key, image, extra)
    if entry then index[key] = entry end
  end
  local function crop(img, h)
    if img and img.height > h then return { width = img.width, height = h, rgba = img.rgba:sub(1, img.width * h * 4) } end
    return img
  end
  local p0, p1 = G.palette(m(0)), G.palette(m(1))
  local c2 = G.tiles(m(2))
  if p0 and c2 then
    local map = G.tilemap(m(14))
    save("backdrop", crop(map and G.compose(map, c2, p0), 192))
    for n, s in pairs(A.BUTTONS) do
      map = G.tilemap(m(s))
      save("buttons_" .. n, crop(map and G.compose(map, c2, p0), 192))
    end
  end
  if p1 then
    for i = 4, 13 do
      local sheet, bank = G.tiles(m(i)), Cells.parse(m(i + 15), G)
      if sheet and bank then
        for c, cell in ipairs(bank.cells) do
          local pic = Cells.assemble(cell, sheet, p1, bank, G)
          if pic then
            local ox, oy = Cells.extent(cell)
            save(i == 13 and ("cursor_%d"):format(c - 1) or ("icon_%d_%d"):format(i, c - 1), pic, { originX = ox, originY = oy })
          end
        end
      end
    end
  end
  local shared = Narc.parse(x.rom:read("/a/0/8/3") or "")
  if shared then
    local sheet, bank, pal = G.tiles(mm(shared, 20)), Cells.parse(mm(shared, 21), G), G.palette(mm(shared, 19))
    local cell = bank and bank.cells[1]
    local pic = cell and sheet and pal and Cells.assemble(cell, sheet, pal, bank, G)
    if pic then
      local ox, oy = Cells.extent(cell)
      save("close", pic, { originX = ox, originY = oy })
    end
  end
  return index
end

return A
