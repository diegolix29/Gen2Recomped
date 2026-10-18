-- BLACK AND WHITE'S BAG (/a/0/8/8, the same in both games; bw_ui_map.md
-- section 5), written as `gen5_bag_art`. No symbols: the pairings were found
-- by composing every combination and checked against Bulbapedia's capture.
--
--   touch_<m|f>    screen 5 (boy, palette 4) / 2 (girl, palette 1) on chars
--                  3 / 0: the pattern behind the list, its scrollbar slot
--   top_<m|f>      screen 23 (boy, palette 16) / 24 (girl, palette 12) on
--                  char 17: the item panel, the description below
--   bag_<m|f>_<c>  the bag picture's parts (char 15 / 11, cell 14 / 10,
--                  palette 16 / 12): c 0-4 the five pockets' pieces at rest
--                  (4 is the bag itself, the Key Items), 5-9 and 10-14 the
--                  same lit and opened
--   row            char 20 / cell 19 / palette 21: the dark list capsule
--   scroll_<c>     27 / 26 / 28: the scrollbar's arrows and thumb
--   tm_<c>         31 / 30 / 32: the check marks and TM / HM discs
--   register_<c>   38 / 37 / 39: the registered-item button faces

local A = {}

A.PATH = "/a/0/8/8"

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
  local index = { _source = "ROM:/a/0/8/8 (touch 5/2 on 3/0, top 23/24 on 17, bag 15/11, row 20, scroll 27, discs 31, register 38)" }
  local function save(key, image, extra)
    local entry = image and x:saveImage("bw_bag/" .. key, image, extra)
    if entry then index[key] = entry end
  end
  local function bg(key, s, c, p)
    local map, sheet, pal = G.tilemap(m(s)), G.tiles(m(c)), G.palette(m(p))
    local img = map and sheet and pal and G.compose(map, sheet, pal)
    if img and img.height > 192 then img = { width = img.width, height = 192, rgba = img.rgba:sub(1, img.width * 192 * 4) } end
    save(key, img)
  end
  bg("touch_m", 5, 3, 4)
  bg("touch_f", 2, 0, 1)
  bg("top_m", 23, 17, 16)
  bg("top_f", 24, 17, 12)
  -- under the top panel: the pattern (screen 7 on char 6), palette 8 for the
  -- girl (the capture's colour), 4 for the boy (BY EYE)
  bg("top_back_f", 7, 6, 8)
  bg("top_back_m", 7, 6, 4)
  -- the quantity window (screen 35 on char 33, palette 34): 136 x 48
  local qmap, qsheet, qpal = G.tilemap(m(35)), G.tiles(m(33)), G.palette(m(34))
  local q = qmap and qsheet and qpal and G.compose(qmap, qsheet, qpal)
  if q then
    local w, h = 136, 48
    local rows = {}
    for r = 0, h - 1 do
      local from = (r * q.width) * 4
      rows[#rows + 1] = q.rgba:sub(from + 1, from + w * 4)
    end
    save("quantity", { width = w, height = h, rgba = table.concat(rows) })
  end
  local function sprites(prefix, c, b, p)
    local sheet, bank, pal = G.tiles(m(c)), Cells.parse(m(b), G), G.palette(m(p))
    if not (sheet and bank and pal) then return end
    for i, cell in ipairs(bank.cells) do
      local pic = Cells.assemble(cell, sheet, pal, bank, G)
      if pic then
        local ox, oy = Cells.extent(cell)
        save(("%s_%d"):format(prefix, i - 1), pic, { originX = ox, originY = oy })
      end
    end
  end
  sprites("bag_m", 15, 14, 16)
  sprites("bag_f", 11, 10, 12)
  sprites("row", 20, 19, 21)
  sprites("scroll", 27, 26, 28)
  sprites("tm", 31, 30, 32)
  sprites("register", 38, 37, 39)
  -- the shared touch buttons (/a/0/8/3 char 20, cell 21, palette 19): the
  -- (x), back, the scroll arrows, the check box
  local shared = require("src.import.NarcArchive").parse(x.rom:read("/a/0/8/3") or "")
  if shared then
    local function sm(i)
      local b = shared:get(i)
      if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
      return b
    end
    local sheet, bank, pal = G.tiles(sm(20)), Cells.parse(sm(21), G), G.palette(sm(19))
    if sheet and bank and pal then
      for i, cell in ipairs(bank.cells) do
        local pic = Cells.assemble(cell, sheet, pal, bank, G)
        if pic then
          local ox, oy = Cells.extent(cell)
          save(("button_%d"):format(i - 1), pic, { originX = ox, originY = oy })
        end
      end
    end
  end
  return index
end

return A
