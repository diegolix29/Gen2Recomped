-- BLACK AND WHITE'S NAMING KEYBOARD (overlay 194, namein_graphic.c /
-- namein_data.c; message bank 81), written as `gen5_naming_art`.
--
-- Reported from play: "the keyboard for black and white still doesnt have rom
-- parity" -- BW was opening Platinum's keyboard. Nothing here is Platinum's:
--
--   /a/1/1/8  THE ART. palette 2 (BG, rows 0-2 + 15), chars 1, screens
--             0  the touch screen's backdrop: the green tab the icon sits in
--                and the band the name is typed into (BG main 0)
--             3  the upper screen's backdrop, the fading grid (BG sub 1)
--             4  the frame of the ABC pages: corners, the four mode tabs
--                (UPPER / lower / Others / qwerty), DELETE and OK (BG main 2)
--             5  the ABC keys, 13 x 5 of 2 x 3 tiles from tile (3, 5)
--             10 the qwerty board, its own frame, Delete / Enter / Shift /
--                Space and the same tabs (BG main 1 instead of 5 + 4)
--             OBJ: palette 9, chars 8, cells 7, anims 6 -- cells 0-3 the
--             underscores (seq 0 the next place pulsing, seq 1 the rest),
--             4 the PC (box name), 5-7 / 8-10 the cursor's two brackets (seq
--             3 / 4), 11 the "?" icon.
--   /a/1/1/9  THE CHARACTERS, UTF-16 with a (cols, rows) header: 0 UPPER,
--             1 lower, 2 Others (13 x 5); 3 / 4 qwerty lower / upper (10 x 3,
--             0x203B where there is no key); 8 the shift pairs.
--
-- EVERY KEY IS PAINTED BY CODE (ov194 0x021F1A1C): screens 4 / 5 / 10 are
-- stored with a mix of palettes 1 and 2, and the app repaints BG 1 and 2
-- wholly in palette 1 before lighting the current mode tab (and both Shift
-- keys while shift is held) in palette 4 -- rows 3 and 4 are copies of row 2
-- (ov194 0x021F17E4). So each board is saved twice, `_dark` all row 1 and
-- `_lit` all row 2, and the screen lights a key by drawing the lit picture's
-- rectangle over it.

local A = {}

A.PATH, A.CHARS = "/a/1/1/8", "/a/1/1/9"
A.BANK = 81

-- THE GAME FONT'S PRIVATE CHARACTERS stay the code points the pages hold
-- (0x246C..0x2484, U+FF65): the BW font (/a/0/2/3) has its own glyph at each,
-- so the key shows the cartridge's picture. Only the gender marks become
-- Unicode, as Gen5Text decodes them in every other string.
A.PRIVATE = { [0x246D] = "\u{2642}", [0x246E] = "\u{2640}" }

local function utf8char(code)
  if A.PRIVATE[code] then return A.PRIVATE[code] end
  if code == 0x20 or code == 0x3000 or code == 0x203B or code == 0 then return "" end
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then
    return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
  end
  return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

-- one page of /a/1/1/9: u16 cols, u16 rows, then the characters row by row
function A.page(bytes)
  if not bytes or #bytes < 4 then return nil end
  local function u16(at) local a, b = bytes:byte(at + 1, at + 2); return a + b * 256 end
  local cols, rows = u16(0), u16(2)
  if cols == 0 or rows == 0 or #bytes < 4 + cols * rows * 2 then return nil end
  local out = { cols = cols, rows = {} }
  for r = 0, rows - 1 do
    local row = {}
    for c = 0, cols - 1 do row[c + 1] = utf8char(u16(4 + (r * cols + c) * 2)) end
    out.rows[r + 1] = row
  end
  return out
end

-- the cells A.build saves, by key: { cell index, sequence it belongs to }
A.SPRITES = {
  underscore_0 = 0, underscore_1 = 1, underscore_2 = 2, underscore_3 = 3,
  icon_box = 4, cursor_l_0 = 5, cursor_l_1 = 6, cursor_l_2 = 7,
  cursor_r_0 = 8, cursor_r_1 = 9, cursor_r_2 = 10, icon_unknown = 11,
}

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local Narc = require("src.import.NarcArchive")
  local raw = x.rom:read(A.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = { source = "ROM:/a/1/1/8 (screens 0/3/4/5/10 on chars 1, pal 2; OBJ 6-9) + /a/1/1/9 + message bank 81 (overlay 194)" }
  local function save(key, pic, extra)
    if not pic then return end
    local rec = x:saveImage("bw_naming/" .. key, pic, extra)
    if rec then out[key] = rec end
  end
  local function crop(img)
    if img and img.height > 192 then return { width = img.width, height = 192, rgba = img.rgba:sub(1, img.width * 192 * 4) } end
    return img
  end
  local pal, chars = G.palette(m(2)), G.tiles(m(1))
  if not (pal and chars) then return nil end
  local function compose(index, force)
    local map = G.tilemap(m(index))
    if not map then return nil end
    if force then
      local cells = {}
      for i, c in ipairs(map.cells) do
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        copy.palette = force
        cells[i] = copy
      end
      map = { width = map.width, height = map.height, cells = cells }
    end
    return crop(G.compose(map, chars, pal))
  end
  save("top", compose(3))
  save("base", compose(0))
  for _, board in ipairs({ { "frame", 4 }, { "keys", 5 }, { "qwerty", 10 } }) do
    save(board[1] .. "_dark", compose(board[2], 1))
    save(board[1] .. "_lit", compose(board[2], 2))
  end
  -- the OBJ cells, each in its own OAM palette row of member 9
  local objPal, sheet, bank = G.palette(m(9)), G.tiles(m(8)), Cells.parse(m(7), G)
  if objPal and sheet and bank then
    for key, index in pairs(A.SPRITES) do
      local cell = bank.cells[index + 1]
      local pic = cell and Cells.assemble(cell, sheet, objPal, bank, G)
      if pic then
        local ox, oy = Cells.extent(cell)
        save("obj_" .. key, pic, { originX = ox, originY = oy })
      end
    end
  end
  -- the characters
  local charsRaw = x.rom:read(A.CHARS)
  local charArc = charsRaw and Narc.parse(charsRaw)
  if charArc then
    out.pages = { A.page(charArc:get(0)), A.page(charArc:get(1)), A.page(charArc:get(2)) }
    out.qwerty = { lower = A.page(charArc:get(3)), upper = A.page(charArc:get(4)) }
  end
  -- the text: titles 0-7 (name, nickname, box, rival, friend, greeting,
  -- thanks, message), 8 "Please enter the name.", 9 the four-digit rule
  out.text = {}
  for i = 0, 17 do
    local ok, s = pcall(x.string, x, A.BANK, i)
    if ok and type(s) == "string" then out.text[i] = s end
  end
  -- the key labels' ink: the text window's palette, row 15 (ov194 0x021F3110)
  out.ink = { text = pal[15 * 16 + 2], shadow = pal[15 * 16 + 3] }
  return out
end

return A
