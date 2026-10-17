-- BLACK AND WHITE'S PC BOXES (/a/1/1/6, the same in both games; found by
-- scanning for an archive with a 168 x 160 wallpaper screen and twenty-four
-- wallpaper sets), written as `gen5_box_art`. Checked against Bulbapedia's
-- capture of the cartridge.
--
--   base         screen 0 on char 1, palette 4: the white under the wallpaper
--   frame        screen 2 on char 3, palette 4: the touch screen's frame, the
--                dotted ground to the right, the black foot
--   preview      screen 5 on char 6, palette 7, its top 256 x 192: the top
--                screen's windows (title bar, No. / name / type, nickname /
--                NATURE / ABILITY / ITEM, MOVES LEARNED) on the dotted ground
--   wall_<n>     wallpaper n (0 .. 23): the shared screen 13 on char 14 + n,
--                palette 38 + n
--   party        screen 8 on char 12, palette 4: the party panel (88 x 120)
--   hand_<c>     OBJ char 67, cell 68, palette 70: the << >> arrows (0-3), the
--                slot square, the menu highlight bars, the hand

local A = {}

A.PATH = "/a/1/1/6"
A.WALLPAPERS = 24

local function crop(img, w, h)
  if not img then return nil end
  local rows = {}
  for r = 0, math.min(h, img.height) - 1 do
    rows[#rows + 1] = img.rgba:sub(r * img.width * 4 + 1, r * img.width * 4 + w * 4)
  end
  return { width = w, height = math.min(h, img.height), rgba = table.concat(rows) }
end

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local index = { _source = "ROM:/a/1/1/6 (0/2 on 1/3 pal 4, 5 on 6 pal 7, wallpapers 13 on 14+n pal 38+n, party 8 on 12, OBJ 67/68/70)" }
  local function save(key, image, extra)
    local entry = image and x:saveImage("bw_box/" .. key, image, extra)
    if entry then index[key] = entry end
  end
  local function bg(key, s, c, p, w, h)
    local map, sheet = G.tilemap(m(s)), G.tiles(m(c))
    local pal = G.palette(m(p))
    local img = map and sheet and pal and G.compose(map, sheet, pal)
    save(key, w and crop(img, w, h) or img)
  end
  bg("base", 0, 1, 4, 256, 192)
  bg("frame", 2, 3, 4)
  bg("preview", 5, 6, 7, 256, 192)
  bg("party", 8, 12, 4)
  for n = 0, A.WALLPAPERS - 1 do bg("wall_" .. n, 13, 14 + n, 38 + n) end
  local sheet, bank = G.tiles(m(67)), Cells.parse(m(68), G)
  local pal = G.palette(m(70))
  if sheet and bank and pal then
    for i, cell in ipairs(bank.cells) do
      local pic = Cells.assemble(cell, sheet, pal, bank, G)
      if pic then
        local ox, oy = Cells.extent(cell)
        save(("hand_%d"):format(i - 1), pic, { originX = ox, originY = oy })
      end
    end
  end
  index.ink = {}
  for n = 0, A.WALLPAPERS - 1 do
    local p = G.palette(m(38 + n))
    if p and p[3] and p[2] then index.ink[n] = { p[3], p[2] } end
  end
  return index
end

return A
