-- HEARTGOLD / SOULSILVER'S PC BOXES (/a/0/1/9, overlay 14; the loads are
-- mapped in scratch_claude/hgss_ui_screens_map.md "PC boxes"), written as
-- `gen4_hgss_box_art` in the `build(x) -> index` shape. Overlay 14 puts the
-- main engine on the TOUCH screen: the boxes are there, the preview on top.
--
--   base          BG3 screen 0 on char 1, palette 4 (512 x 256; its first
--                 256 x 192): the cream under the wallpaper
--   frame         BG2 screen 2 on char 3, palette 4: the blue frame round the box
--   wall_<n>      the wallpaper n (0 .. 23): char 16 + n, the one shared
--                 screen 15, palette 40 + n -- at (0, 8), tile row 1
--   preview       sub screen 5 on char 6, palette 7: the top screen's panel
--   party         screen 8 on char 14, palette 4: the party panel (88 x 144)
--   marks         screen 10: the marking panel; message 11 (256 x 48)
--   hand_<c>      OBJ char 66, cell 67, palette 69: 0-3 the box arrows (left,
--                 left pressed, right, right pressed), 4 the slot marker, 5 / 7
--                 the menu highlight, 8-11 / 13-16 the hand, 12 its shadow

local A = {}

A.PATH = "/a/0/1/9"
A.WALLPAPERS = 24

local function crop(img, w, h)
  if not img then return nil end
  if img.width == w and img.height == h then return img end
  local rows = {}
  for r = 0, math.min(h, img.height) - 1 do
    rows[#rows + 1] = img.rgba:sub(r * img.width * 4 + 1, r * img.width * 4 + w * 4)
  end
  return { width = w, height = math.min(h, img.height), rgba = table.concat(rows) }
end

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local raw = x.rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i) local b = arc:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
  local index = { _source = "ROM:/a/0/1/9 (overlay 14)" }
  local function save(key, image, extra)
    local entry = image and x:saveImage("hgss_box/" .. key, image, extra)
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
  bg("preview", 5, 6, 7)
  bg("party", 8, 14, 4)
  bg("party_plain", 9, 14, 4)
  bg("marks", 10, 14, 4)
  bg("message", 11, 14, 4)
  for n = 0, A.WALLPAPERS - 1 do bg("wall_" .. n, 15, 16 + n, 40 + n) end
  local sheet, bank = G.tiles(m(66)), Cells.parse(m(67), G)
  local pal = G.palette(m(69))
  if sheet and bank and pal then
    for i, cell in ipairs(bank.cells) do
      local pic = Cells.assemble(cell, sheet, pal, bank, G)
      if pic then
        local ox, oy = Cells.extent(cell)
        save(("hand_%d"):format(i - 1), pic, { originX = ox, originY = oy })
      end
    end
  end
  -- the wallpaper's own letter / shadow for the box name: colours 2 / 1 of
  -- its palette row, as Platinum's (ov19_021D7C58)
  index.ink = {}
  for n = 0, A.WALLPAPERS - 1 do
    local p = G.palette(m(40 + n))
    if p and p[3] and p[2] then index.ink[n] = { p[3], p[2] } end
  end
  return index
end

return A
