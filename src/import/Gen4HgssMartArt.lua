-- HEARTGOLD / SOULSILVER'S POKE MART "BUY" TOUCH SCREEN (/a/0/6/0 members
-- 15-25; pokeheartgold asm/overlay_31.s, opened by shop_menu.c's
-- ov01_021F6A9C(fieldSystem, 2, data)). Written as `gen4_hgss_mart_art`.
--
-- HeartGold does not list the goods on the top screen as Platinum does (its
-- top list window, ov03_022594C6[0], is created and never printed into): the
-- choosing is on the touch screen, six items a page.
--
--   panel      screen 17 (SUB BG2, ov31_0225D9D4 state 0) over char 16 in
--              palette 15: the grey header, the blue field and the six dotted
--              slots {x 2-125 | 130-253} x {y 37-74 | 77-114 | 117-154}
--   buttons    screen 18 (SUB BG1, ov31_0225E0E4): the six white item buttons,
--              shown slot by slot where the page has an item
--   quantity   screen 19 (state 1): the item box, the "In Bag" box and the
--              orange count / price box
--   confirm    screen 20 (state 2): the same without the count box
--   cells of 23 / 24 in palette 22 (the resdat's OBJ set), each at its own
--   OAM palette row:
--     cursor 0 (the red slot frame, 128 x 48), cursor_idle 1, prev 2, next 3
--     (the page arrows at (24, 176) / (64, 176)), back 6 (the blue button at
--     (224, 176)), up 12 / down 14 (the count's marks), a_button 20 /
--     b_button 22 (the buy / cancel buttons of the count and the question)

local M = {}

M.PATH = "/a/0/6/0"
M.SCREENS = { panel = 17, buttons = 18, quantity = 19, confirm = 20 }
M.CELLS = { cursor = 0, cursor_idle = 1, prev = 2, next = 3, back = 6,
            up = 12, down = 14, a_button = 20, b_button = 22 }

function M.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local raw = rom:read(M.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not (arc and arc.count >= 26) then return nil end
  local function m(i) local b = arc:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
  local out = {}
  local sheet, pal = G.tiles(m(16)), G.palette(m(15))
  for key, s in pairs(M.SCREENS) do
    local map = G.tilemap(m(s))
    local img = map and sheet and pal and G.compose(map, sheet, pal)
    if img and img.height > 192 then img = { width = img.width, height = 192, rgba = img.rgba:sub(1, img.width * 192 * 4) } end
    out[key] = img
  end
  local osheet, bank, opal = G.tiles(m(23)), Cells.parse(m(24), G), G.palette(m(22))
  for key, c in pairs(M.CELLS) do
    local cell = bank and bank.cells[c + 1]
    local ok, pic = false, nil
    if cell and osheet and opal then ok, pic = pcall(Cells.assemble, cell, osheet, opal, bank, G) end
    if ok and pic then
      pic.originX, pic.originY = Cells.extent(cell)
      out[key] = pic
    end
  end
  return out
end

-- RomExtractorGen4's hgss_screens registry: (x) -> the cache index
function M.build(x)
  local imgs = M.images(x.rom)
  if not imgs then return nil end
  local idx = {}
  for key, image in pairs(imgs) do
    idx[key] = x:saveImage("hgss_mart/" .. key, image, { originX = image.originX, originY = image.originY })
  end
  return idx
end

return M
