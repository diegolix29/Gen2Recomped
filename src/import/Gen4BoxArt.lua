-- PLATINUM'S POKEMON STORAGE SYSTEM ART (src/applications/pc_boxes/), from
-- /graphic/box.narc.  Member numbers are the cartridge's own -- the archive has
-- no name table in this port -- and each is quoted from the call that loads it.
--
-- BACKGROUNDS (main engine, BG palette = member 5's seven rows):
--
--   main          BG2: tiles 1, map 0 (ov19_021D75CC) -- the left preview
--                 panel, the bottom-left info box; transparent over the box
--   party_panel   BG2: map 6 rows 2..25, 15 tiles wide, laid at tile x 14
--                 (ov19_021DCD64 with the panel fully up) -- PARTY PKMN
--   wallpaper_NN  BG3, the whole visible 256 x 192 (ov19_021D7A9C / 7D00):
--                 tile 0x18 in the wallpaper's palette everywhere, the
--                 wallpaper's own 21 x 20 map from tile column 11, and four
--                 rows of its tile 0 under it.  Members per wallpaper are
--                 Unk_ov19_021E0178: palette 28 + 3n, tiles 29 + 3n, map 30 + 3n
--   marking_off_i / marking_on_i   the six preview markings, BG2 tiles
--                 132 + i / 152 + i in palette row 2 (ov19_021DB24C), drawn at
--                 tile (4 + i, 19)
--
-- SPRITES (OBJ palette = member 26, loaded at slot 0):
--
--   cursor_NN     the hand, NCGR/NCER/NANR 12/13/14, sequences 0..9 -- 0 open,
--                 1 grabbing, 2 holding, 5 its shadow on the slot, 6/7 the
--                 header arrows, 8/9 the arrows while the cursor is on the
--                 header.  No explicit palette: the cell's own OAM rows.
--   buttons_N     PARTY PKMN / CLOSE BOX, NCGR/NCER/NANR 9/10/11, sequences
--                 0 (neither), 1 (PARTY PKMN pressed), 2 (CLOSE BOX pressed);
--                 Sprite_SetExplicitPalette(.., 1) -- member 26 row 1 for
--                 every OAM entry (ov19_021DA864)
--
-- TEXT THAT IS NOT TEXT: `special_name` and `special_level` are
-- font_special_chars' 23 tiles in a row (0-9, "/", "Lv.", "No.", ...) in the
-- two colour pairs the preview builds its contexts with --
-- FontSpecialChars_Init(9, 6, 15) and (1, 2, 15) in rows 1 and 3.
--
-- `data(rom)` is the ink the screen prints with, all from member 5 unless
-- said otherwise (gen4_box_ink).
--
-- Written to assets/generated/gen4/box/<key>.png, indexed in `gen4_box_art`.

local Gen4BoxArt = {}

Gen4BoxArt.PATH = "/graphic/box.narc"
Gen4BoxArt.FONT_PATH = "/graphic/pl_font.narc"
Gen4BoxArt.WALLPAPERS = 32

-- the members of wallpaper n (Unk_ov19_021E0178: map, tiles, palette)
function Gen4BoxArt.wallpaperMembers(n)
  return 30 + 3 * n, 29 + 3 * n, 28 + 3 * n
end

local floor = math.floor

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom:read(path)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function row(colours, r)
  local out = {}
  for i = 1, 16 do out[i] = colours[r * 16 + i] or { 0, 0, 0 } end
  return out
end

local function assemble(cell, sheet, colours, bank, forcePalette)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  if not cell then return nil end
  local use = cell
  if forcePalette then
    use = {}
    for k, v in pairs(cell) do use[k] = v end
    use.oam = {}
    for i, o in ipairs(cell.oam) do
      local c = {}
      for k, v in pairs(o) do c[k] = v end
      c.palette = 0
      use.oam[i] = c
    end
  end
  local pic = Cells.assemble(use, sheet, colours, bank, G)
  if pic then pic.originX, pic.originY = Cells.extent(use) end
  return pic
end

function Gen4BoxArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom, Gen4BoxArt.PATH)
  if not member then return nil, "box.narc missing" end
  local out = {}

  local sheet, pal = G.tiles(member(1)), G.palette(member(5))
  local mainMap, partyMap = G.tilemap(member(0)), G.tilemap(member(6))
  if not (sheet and pal and mainMap) then return nil, "box.narc main panel unreadable" end
  -- ov19_021DAADC puts the info window's 12 x 2 (of 12 x 4) over tile (1, 21)
  -- with Window_PutRectToTilemap.  The window is filled with colour 0, so what
  -- the player sees there is BG3 -- the map's own cells under it (37 and 69, a
  -- placeholder pattern) never show.
  local cells = {}
  local mcols = floor((mainMap.width or 256) / 8)
  for i, c in ipairs(mainMap.cells) do
    local col, r = (i - 1) % mcols, floor((i - 1) / mcols)
    if r >= 21 and r <= 22 and col >= 1 and col <= 12 then
      cells[i] = { tile = 0x7fff, palette = 0 }
    else
      cells[i] = c
    end
  end
  out.main = G.compose({ width = mainMap.width, height = mainMap.height, cells = cells }, sheet, pal)

  if partyMap then
    local cols = floor((partyMap.width or 120) / 8)
    local cells = {}
    for r = 2, 25 do
      for c = 0, 14 do
        local src = partyMap.cells[r * cols + c + 1] or { tile = 0, palette = 0 }
        cells[#cells + 1] = src
      end
    end
    out.party_panel = G.compose({ width = 120, height = 192, cells = cells }, sheet, pal)
  end

  -- the MARK menu's six symbols: member 25 is a 6 x 2-tile bitmap (top row
  -- set, bottom row clear) that ov19_021DB638 blits into the menu window, so
  -- its pixel values are the window's palette 4
  local marks = G.tiles(member(25))
  if marks then
    local cells = {}
    for t = 0, 11 do cells[t + 1] = { tile = t, palette = 4 } end
    out.marking_menu = G.compose({ width = 48, height = 16, cells = cells }, marks, pal)
  end
  for i = 0, 5 do
    out["marking_off_" .. i] = G.compose({ width = 8, height = 8, cells = { { tile = 132 + i, palette = 2 } } }, sheet, pal)
    out["marking_on_" .. i] = G.compose({ width = 8, height = 8, cells = { { tile = 152 + i, palette = 2 } } }, sheet, pal)
  end

  -- the wallpapers, as the whole of BG3 the screen shows
  for n = 0, Gen4BoxArt.WALLPAPERS - 1 do
    local m, t, p = Gen4BoxArt.wallpaperMembers(n)
    local wmap, wsheet, wpal = G.tilemap(member(m)), G.tiles(member(t)), G.palette(member(p))
    if wmap and wsheet and wpal then
      local wcols = floor((wmap.width or 168) / 8)
      local cells = {}
      for r = 0, 23 do
        for c = 0, 31 do
          local cell = { tile = 0x18, palette = 0 }
          if c >= 11 then
            local x = c - 11
            if r < 20 then
              local src = wmap.cells[r * wcols + x + 1]
              if src then cell = { tile = src.tile, flipX = src.flipX, flipY = src.flipY, palette = 0 } end
            else
              cell = { tile = 0, palette = 0 }
            end
          end
          cells[#cells + 1] = cell
        end
      end
      out[("wallpaper_%02d"):format(n)] = G.compose({ width = 256, height = 192, cells = cells }, wsheet, row(wpal, 0))
      -- the 23 BG3 columns ov19_021D8764 writes per box: the 21 x 20 map with
      -- four rows of tile 0 under it, then two columns of tile 0
      local strip = {}
      for r = 0, 23 do
        for c = 0, 22 do
          local cell = { tile = 0, palette = 0 }
          if c < 21 and r < 20 then
            local src = wmap.cells[r * wcols + c + 1]
            if src then cell = { tile = src.tile, flipX = src.flipX, flipY = src.flipY, palette = 0 } end
          end
          strip[#strip + 1] = cell
        end
      end
      out[("paper_%02d"):format(n)] = G.compose({ width = 184, height = 192, cells = strip }, wsheet, row(wpal, 0))
      -- one column of ov19_021D7A9C's fill: tile 0x18 of the wallpaper in slot 0
      local fill = {}
      for r = 0, 23 do fill[r + 1] = { tile = 0x18, palette = 0 } end
      out[("paper_fill_%02d"):format(n)] = G.compose({ width = 8, height = 192, cells = fill }, wsheet, row(wpal, 0))
    end
  end

  -- THE JUMP POPUP (ov19_021DB8E4): BG1 tiles 4 with map 3 -- the 32 x 10
  -- band ov19_021DC0A0 lays over tile rows 5..14 -- and the 32 x 32 8bpp box
  -- thumbnail (NCGR 17, cell 18) whose frame is OBJ row 15 (member 20's first
  -- sixteen colours, loaded at slot 15); its inside is filled at run time
  -- (ov19_021DBBA8) from member 27, kept as ink
  local bandSheet, bandMap = G.tiles(member(4)), G.tilemap(member(3))
  if bandSheet and bandMap then out.jump_band = G.compose(bandMap, bandSheet, pal) end
  local thumb, framePal = G.tiles(member(17)), G.palette(member(20))
  if thumb and framePal then
    local colours = {}
    for i = 0, 15 do colours[240 + i + 1] = framePal[240 + i + 1] or framePal[i + 1] end
    local cells = {}
    for t = 0, 15 do cells[t + 1] = { tile = t, palette = 0 } end
    local pic = G.compose({ width = 32, height = 32, cells = cells }, thumb, colours)
    if pic then pic.originX, pic.originY = -16, -16 end
    out.jump_thumb = pic
  end

  -- sprites over member 26
  local obj = G.palette(member(26))
  if obj then
    local csheet, cbank, canim = G.tiles(member(12)), Cells.parse(member(13), G), Anim.parse(member(14), G)
    if csheet and cbank and canim then
      for seq = 0, #canim.sequences - 1 do
        local frames = Anim.frames(canim, seq)
        local cell = frames and frames[1] and cbank.cells[frames[1].cell + 1]
        out[("cursor_%02d"):format(seq)] = assemble(cell, csheet, obj, cbank, false)
      end
    end
    local bsheet, bbank, banim = G.tiles(member(9)), Cells.parse(member(10), G), Anim.parse(member(11), G)
    if bsheet and bbank and banim then
      for seq = 0, #banim.sequences - 1 do
        local frames = Anim.frames(banim, seq)
        local cell = frames and frames[1] and bbank.cells[frames[1].cell + 1]
        out["buttons_" .. seq] = assemble(cell, bsheet, row(obj, 1), bbank, true)
      end
    end
  end

  -- THE BOTTOM SCREEN (ov19_021DCF88, every mode but COMPARE): sub BG tiles
  -- 127 under palette 128 (three rows at sub BG 0); SUB_3 map 124 (the
  -- backdrop with the two dial wells), SUB_2 map 125 (512 x 256: the dial's
  -- cover, scrolled to 0 / -128 / 128) and SUB_1 map 126 (512 x 256: the two
  -- dial faces, "SELECT BOX" / "MARKINGS", scrolled to 0 / -96 / 88).
  local subSheet, subPal = G.tiles(member(127)), G.palette(member(128))
  if subSheet and subPal then
    for key, m in pairs({ sub_bg = 124, sub_cover = 125, sub_dials = 126 }) do
      local map = G.tilemap(member(m))
      if map then out[key] = G.compose(map, subSheet, subPal) end
    end
  end
  -- sub OBJ palette 144 (Graphics_LoadPartialPaletteFromOpenNARC at sub OBJ
  -- 0, through the sprite list's palette proxy: no explicit palette, so each
  -- OAM entry's own row is the one used)
  local subObj = G.palette(member(144))
  local function cellsOf(tiles, cells, anims, colours, prefix, forceRow)
    local sh, bank, an = G.tiles(member(tiles)), Cells.parse(member(cells), G), Anim.parse(member(anims), G)
    if not (sh and bank and an and colours) then return end
    for i, cell in ipairs(bank.cells) do
      out[prefix .. (i - 1)] = assemble(cell, sh, forceRow and row(colours, forceRow) or colours, bank, forceRow ~= nil)
    end
  end
  -- the two corner buttons (NCGR/NCER/NANR 138/139/140): sequence 0 cell 0
  -- (up), 1 cells 1 x 8 then 2 x 8 (pressed), 2 cells 3 / 4; the right one
  -- is the same sprite flipped (Sprite_SetFlipMode 1)
  cellsOf(138, 139, 140, subObj, "sub_button_")
  -- the markings dial's eight buttons (141/142/143): cell 2t off, 2t + 1 lit
  -- -- OFF, ITEM, circle, triangle, square, heart, star, diamond
  cellsOf(141, 142, 143, subObj, "sub_mark_")

  -- COMPARE MODE'S BOTTOM SCREEN (ov19_021DEC04): tiles 132, palette 133
  -- (four rows at sub BG 0), maps 129 (battle stats), 130 (contest) and 131
  -- (moves) on SUB_1 / SUB_2 / SUB_3, one shown per compare mode; sprites
  -- 134/135/136 over palette 137 (three rows at sub OBJ 0), each with an
  -- explicit palette -- the left button 0, the right 1 (flipped), the toggle
  -- 2, the contest dots their slot's 0 / 1.
  local cmpSheet, cmpPal = G.tiles(member(132)), G.palette(member(133))
  if cmpSheet and cmpPal then
    for key, m in pairs({ cmp_battle = 129, cmp_contest = 130, cmp_moves = 131 }) do
      local map = G.tilemap(member(m))
      if map then out[key] = G.compose(map, cmpSheet, cmpPal) end
    end
  end
  local cmpObj = G.palette(member(137))
  if cmpObj then
    local sh, bank = G.tiles(member(134)), Cells.parse(member(135), G)
    if sh and bank then
      local function one(cell, pal, key)
        local c = bank.cells[cell + 1]
        if c then out[key] = assemble(c, sh, row(cmpObj, pal), bank, true) end
      end
      for c = 0, 2 do one(c, 0, "cmp_left_" .. c); one(c, 1, "cmp_right_" .. c) end
      for c = 3, 5 do one(c, 2, "cmp_toggle_" .. c) end
      one(6, 0, "cmp_dot_0"); one(7, 1, "cmp_dot_1")
    end
  end

  -- font_special_chars in the preview's two colour pairs
  local font = opener(rom, Gen4BoxArt.FONT_PATH)
  local special = font and G.tiles(font(require("src.import.Gen4SpecialChars").MEMBER))
  if special then
    local cells = {}
    for t = 0, 22 do cells[t + 1] = { tile = t, palette = 0 } end
    local function strip(r, fg, sh)
      return G.compose({ width = 23 * 8, height = 8, cells = cells }, special,
        { { 0, 0, 0 }, pal[r * 16 + fg + 1], pal[r * 16 + sh + 1] })
    end
    out.special_name = strip(1, 9, 6)
    out.special_level = strip(3, 1, 2)
    -- the jump popup's box counts, FontSpecialChars_Init(2, 13, 4) in row 2
    out.special_jump = strip(2, 2, 13)
  end

  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

-- The colours the screen prints with, as 0..255 triples.
function Gen4BoxArt.ink(pal, wallpaperPals, thumbs)
  local function at(r, i)
    local c = pal and pal[r * 16 + i + 1]
    return c and { c[1], c[2], c[3] }
  end
  local ink = {
    -- ov19_021DB0E4: species (9, 6) in row 1, nickname (1, 2) in row 3,
    -- the gender symbols (7, 8) and (3, 4) in row 3, the held item (9, 6)
    species = { at(1, 9) or { 255, 247, 255 }, at(1, 6) or { 115, 115, 132 } },
    nickname = { at(3, 1) or { 239, 230, 255 }, at(3, 2) or { 90, 90, 107 } },
    male = { at(3, 7) or { 148, 230, 239 }, at(3, 8) or { 41, 123, 165 } },
    female = { at(3, 3) or { 247, 132, 132 }, at(3, 4) or { 197, 41, 41 } },
    item = { at(1, 9) or { 255, 247, 255 }, at(1, 6) or { 115, 115, 132 } },
    -- ov19_021DB57C: the action menu (11, 12) on 15, row 4
    menu = { at(4, 11) or { 16, 25, 33 }, at(4, 12) or { 173, 189, 189 } },
    menuFill = at(4, 15) or { 255, 255, 255 },
    -- the message window's default printer colours (1, 2) on 15, row 4
    message = { at(4, 1) or { 107, 107, 99 }, at(4, 2) or { 197, 206, 206 } },
    -- BG palette 0 colour 0 is the backdrop
    backdrop = at(0, 0) or { 132, 230, 173 },
    -- ov19_021D7C58: the box name, (2, 1) in the wallpaper's own palette
    wallpaper = {},
    -- the jump popup (ov19_021DBF4C / BFC4): the box name (2, 8) on 7 and the
    -- counts' paper 4, BG row 2
    jumpName = { at(2, 2) or { 255, 255, 255 }, at(2, 8) or { 214, 90, 90 } },
    jumpPlate = at(2, 7) or { 247, 132, 132 },
    jumpCount = at(2, 4) or { 230, 165, 90 },
    -- ov19_021DBBA8: a thumbnail's inside is OBJ row 13 colour `wallpaper`
    -- (less 8 from 24 up) and each Pokemon a 2 x 2 dot in row 14 at
    -- { 14, 15, 5, 4, 13, 12, 3, 11, 10, 9 }[body colour] -- member 27
    jumpPaper = {},
    jumpBody = {},
  }
  for i = 0, 23 do
    local c = thumbs and thumbs[i + 1]
    if c then ink.jumpPaper[i] = { c[1], c[2], c[3] } end
  end
  for colour, slot in pairs({ [0] = 0xe, 0xf, 0x5, 0x4, 0xd, 0xc, 0x3, 0xb, 0xa, 0x9 }) do
    local c = thumbs and thumbs[16 + slot + 1]
    if c then ink.jumpBody[colour] = { c[1], c[2], c[3] } end
  end
  for n, p in pairs(wallpaperPals or {}) do
    local c2, c1 = p[3], p[2]
    if c2 and c1 then ink.wallpaper[n] = { { c2[1], c2[2], c2[3] }, { c1[1], c1[2], c1[3] } } end
  end
  return ink
end

function Gen4BoxArt.data(rom)
  local G = require("src.import.Gen4Graphics")
  local member = opener(rom, Gen4BoxArt.PATH)
  local pal = member and G.palette(member(5))
  if not pal then return {} end
  local papers = {}
  for n = 0, Gen4BoxArt.WALLPAPERS - 1 do
    local _, _, p = Gen4BoxArt.wallpaperMembers(n)
    papers[n] = G.palette(member(p))
  end
  local ink = Gen4BoxArt.ink(pal, papers, G.palette(member(27)))
  -- the bottom screen: ov19_021DE350's box names TEXT_COLOR(1, 2, 0) in
  -- window palette 2 of member 128; compare mode's words TEXT_COLOR(15, 14, 0)
  -- in palettes 0 (left windows) and 1 (right) of member 133; SUB backdrop
  -- colour 0 of each
  local function pair(p, r, a, b)
    local x, y = p and p[r * 16 + a + 1], p and p[r * 16 + b + 1]
    return x and y and { { x[1], x[2], x[3] }, { y[1], y[2], y[3] } } or nil
  end
  local sub, cmp = G.palette(member(128)), G.palette(member(133))
  ink.subName = pair(sub, 2, 1, 2)
  ink.subBackdrop = sub and sub[1] and { sub[1][1], sub[1][2], sub[1][3] }
  ink.cmpLeft = pair(cmp, 0, 15, 14)
  ink.cmpRight = pair(cmp, 1, 15, 14)
  ink.cmpBackdrop = cmp and cmp[1] and { cmp[1][1], cmp[1][2], cmp[1][3] }
  return ink
end

return Gen4BoxArt
