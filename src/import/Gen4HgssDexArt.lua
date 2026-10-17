-- HEARTGOLD / SOULSILVER'S POKEDEX ART (zukan_gra = /a/0/6/8, 123 unnamed
-- members; pokefoot = /a/0/6/9; zukan_data = /a/0/7/4), written as the cache
-- module `gen4_hgss_dex_art` by RomExtractorGen4's `hgss_screens` stage
-- (`build(x)` -> index). Drawn by src/ui/HgssPokedex.lua.
--
-- SOURCES. pokeheartgold src/application/pokedex/ov18_021E5C40.c and
-- asm/overlay_18.s (overlay 18); scratch_claude/hgss_ui_screens_map.md
-- "Pokedex". HG puts the touch UI on the MAIN engine (`GX_DISP_SELECT_SUB_MAIN`).
--
-- READ FROM CODE (ov18_021E6868 / ov18_021E6308 / ov18_021E6AEC / sprite
-- loaders, cited per entry below):
--   touch (MAIN) palette member 2 (16 rows), top (SUB) palette member 18
--   cover_<mode>[_lock]  BG0: screen 0 (512 x 256) over char 1, its left
--                        block; the header fragment 7 (mode 0) / 8 (mode 1)
--                        stamped at (5,3) (ov18_021E6A70); `_lock` fills rows
--                        15-16, cols 3-28 with tile 0x16 (no National Dex:
--                        the NATIONAL/JOHTO switch is blanked, :1029)
--   edge                 BG0 screen 0's right block, cols 0-2 (fragment 14,
--                        "START/INFO" edge the lid leaves when it slides open)
--   grid                 BG3 fragment 5 = screen 10 (32 x 5) over char 3: one
--                        row of five 40 x 40 cells; the list stacks ten
--   digits               char 3 tiles in palette row 1 (ov18_021E6AEC):
--                        tile 2 = the caught ball, 3+d = caught digit d,
--                        14+d = seen digit d -> one 8 x 168 strip, [ball,
--                        caught 0-9, seen 0-9] left to right
--   plate                BG2 fragment 4 = screen 9 (32 x 4), at row 15
--   bar_cover / bar_list / bar_list2 / bar_details
--                        fragments 0/1/8/16 = screens 5/6/71/11 over char 4;
--                        rows 19 (5 high) / 19 / 19 / 20 (4 high)
--   top_cover            SUB0 screen 16 over char 17 (the closed lid's ring)
--   top_entry / top_foreign / top_blank
--                        SUB3 screens 20 / 21 / 22 over char 19
--   list_<cell>          OBJ char 12 / pal 15 (5 rows) / cell 13 / anim 14
--                        (ov18_021F2648), every cell; `listAnims[a]` = first
--                        cell of animation a
--   unknown_pic          OBJ char 26 / pal 32 / cell 27 (the picture slot's
--                        own "?" art, ov18_021F2724)
--   caught_ball          OBJ char 29 / pal 32 / cell 30 (the ball by the name)
--   type_<t>             OBJ cell 33 / pal 35 (4 rows) over the type's own
--                        char: `ov18_021FBE10`[t], palette row
--                        `ov18_021FBDFC`[t] (ov18_021F21FC), t = TYPE_* id
--   foot_<species>       pokefoot: NCLR 0, NCER 2, NCGR 3 + species
--   orders               zukan_data member 11 (national) / 12 (Johto), u16
--                        species lists
--
-- NOT DONE: the area (82-87), size (89-92, OBJ 105-114), forms (93-100),
-- search (57-68, OBJ 72-75 / 23-25) and confirm (101-104) states' art, the
-- foreign-language entry OBJ (53-56), the footprint frame OBJ (77-79).

local A = {}

A.PATH = "/a/0/6/8"
A.FOOT = "/a/0/6/9"
A.DATA = "/a/0/7/4"

-- `ov18_021FBE10` (char member per TYPE_*) and `ov18_021FBDFC` (palette row)
A.TYPE_CHAR = { [0] = 36, 42, 50, 46, 44, 41, 47, 43, 45, 36, 37, 39, 38, 40, 51, 49, 52, 48 }
A.TYPE_ROW = { [0] = 0, 2, 0, 3, 1, 1, 3, 2, 0, 0, 2, 2, 1, 1, 1, 0, 2, 3 }

local function crop(img, x, y, w, h)
  if not img then return nil end
  local rows = {}
  for r = 0, h - 1 do
    local at = ((y + r) * img.width + x) * 4
    rows[#rows + 1] = img.rgba:sub(at + 1, at + w * 4)
  end
  return { width = w, height = h, rgba = table.concat(rows) }
end

-- a 512 x 256 screen's 32 x 32 block `b`, as a linear 32 x 24 tilemap
local function block(map, b, rows)
  local cells = {}
  for r = 0, (rows or 24) - 1 do
    for c = 0, 31 do cells[r * 32 + c + 1] = map.cells[b * 1024 + r * 32 + c + 1] end
  end
  return { width = 256, height = (rows or 24) * 8, cells = cells }
end

function A.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local CellAnim = require("src.import.Gen4CellAnim")
  local Narc = require("src.import.NarcArchive")
  local raw = rom:read(A.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function m(i) local b = arc:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
  local out, anims = {}, {}

  local main = G.palette(m(2))
  local sub = G.palette(m(18))
  if not (main and sub) then return nil end

  -- ---------------------------------------------------------------- touch
  local char1, char3, char4 = G.tiles(m(1)), G.tiles(m(3)), G.tiles(m(4))
  local map0 = G.tilemap(m(0))
  if map0 and char1 then
    for mode, frag in pairs({ [0] = 7, [1] = 8 }) do
      for _, lock in ipairs({ false, true }) do
        local left = block(map0, 0)
        local head = G.tilemap(m(frag))
        if head then G.stamp(left, head, 5, 3) end
        if lock then
          for r = 15, 16 do
            for c = 3, 28 do
              local cell = left.cells[r * 32 + c + 1]
              left.cells[r * 32 + c + 1] = { tile = 0x16, flipX = false, flipY = false, palette = cell and cell.palette or 0 }
            end
          end
        end
        out["cover_" .. mode .. (lock and "_lock" or "")] = G.compose(left, char1, main)
      end
    end
    out.edge = crop(G.compose(block(map0, 1), char1, main), 0, 0, 24, 192)
  end
  local function frag(key, member, chars, pal)
    local map = G.tilemap(m(member))
    out[key] = map and chars and G.compose(map, chars, pal or main)
  end
  frag("grid", 10, char3)
  frag("plate", 9, char4)
  frag("bar_cover", 5, char4)
  frag("bar_list", 6, char4)
  frag("bar_list2", 71, char4)
  frag("bar_details", 11, char4)
  if char3 then
    local cells = { { tile = 2, palette = 1 } }
    for d = 0, 9 do cells[#cells + 1] = { tile = 3 + d, palette = 1 } end
    for d = 0, 9 do cells[#cells + 1] = { tile = 14 + d, palette = 1 } end
    out.digits = G.compose({ width = #cells * 8, height = 8, cells = cells }, char3, main)
  end

  -- ------------------------------------------------------------------ top
  local char17, char19 = G.tiles(m(17)), G.tiles(m(19))
  local function screen(key, member, chars)
    local map = G.tilemap(m(member))
    local img = map and chars and G.compose(map, chars, sub)
    if img and (img.width > 256 or img.height > 192) then img = crop(img, 0, 0, 256, 192) end
    out[key] = img
  end
  screen("top_cover", 16, char17)
  screen("top_entry", 20, char19)
  screen("top_foreign", 21, char19)
  screen("top_blank", 22, char19)

  -- ------------------------------------------------------------------ OBJ
  local function put(key, cell, sheet, pal, bank)
    local pic = cell and sheet and pal and Cells.assemble(cell, sheet, pal, bank, G)
    if pic then pic.originX, pic.originY = Cells.extent(cell); out[key] = pic end
  end
  do
    local sheet, pal = G.tiles(m(12)), G.palette(m(15))
    local bank, anim = Cells.parse(m(13), G), CellAnim.parse(m(14), G)
    if sheet and pal and bank then
      for i, cell in ipairs(bank.cells) do put("list_" .. (i - 1), cell, sheet, pal, bank) end
      if anim then
        for a = 0, #anim.sequences - 1 do
          local f = CellAnim.frames(anim, a)
          if f and f[1] then anims[a] = f[1].cell end
        end
      end
    end
  end
  do
    local pal = G.palette(m(32))
    local bank = Cells.parse(m(27), G)
    put("unknown_pic", bank and bank.cells[1], G.tiles(m(26)), pal, bank)
    bank = Cells.parse(m(30), G)
    put("caught_ball", bank and bank.cells[1], G.tiles(m(29)), pal, bank)
  end
  do
    local pal = G.palette(m(35))
    local bank = Cells.parse(m(33), G)
    if pal and bank then
      for t = 0, 17 do
        if t ~= 9 then
          local row = {}
          for k = 1, 256 do row[k] = pal[A.TYPE_ROW[t] * 16 + (k - 1) % 16 + 1] or { 0, 0, 0 } end
          put("type_" .. t, bank.cells[1], G.tiles(m(A.TYPE_CHAR[t])), row, bank)
        end
      end
    end
  end
  -- footprints (pokefoot, the same layout as Platinum's)
  local footRaw = rom:read(A.FOOT)
  local foot = footRaw and Narc.parse(footRaw)
  if foot then
    local function fm(i) local b = foot:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
    local pal, bank = G.palette(fm(0)), Cells.parse(fm(2), G)
    if pal and bank then
      pal = CellAnim.paletteFor(pal, CellAnim.bankOf(bank) or 0)
      for species = 1, 493 do
        local b = fm(3 + species)
        put(("foot_%03d"):format(species), bank.cells[1], b and G.tiles(b), pal, bank)
      end
    end
  end
  return out, anims
end

-- zukan_data's species lists (u16 each, 0-terminated or padded)
function A.orders(rom)
  local raw = rom:read(A.DATA)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local G = require("src.import.Gen4Graphics")
  local function list(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    if not b then return nil end
    local t = {}
    for k = 0, math.floor(#b / 2) - 1 do
      local lo, hi = b:byte(k * 2 + 1, k * 2 + 2)
      local v = lo + hi * 256
      if v == 0 then break end
      t[#t + 1] = v
    end
    return t
  end
  return { national = list(11), johto = list(12) }
end

function A.build(x)
  local images, anims = A.images(x.rom)
  if not images then return nil end
  local index = {}
  for key, image in pairs(images) do
    index[key] = x:saveImage("hgss_dex/" .. key, image, { originX = image.originX, originY = image.originY })
  end
  index.listAnims = anims
  index.orders = A.orders(x.rom)
  index.source = "ROM:/a/0/6/8 (zukan_gra), /a/0/6/9 (pokefoot), /a/0/7/4 (zukan_data)"
  return index
end

return A
