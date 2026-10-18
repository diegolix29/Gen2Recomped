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
-- The search / entry pages' art and the search data: A.addPages and
-- A.searchData below (keys search_*, area_*, size_*, forms_*, compare_*,
-- return_*, srch_*, srch2_*, size105_/109_/111_/114_*, searchAnims,
-- search2Anims, size*Anims, and `search` = heights, weights, body styles,
-- sort / filter lists, slider stops, area flags, size scales).
-- NOT DONE: the area map's marker OBJ and zukan_enc (/a/1/3/3) per-species
-- places, the foreign-language entry OBJ (53-56), the footprint frame OBJ
-- (77-79), the slider / arrow / scroll OBJ of the new pages.

local A = {}

A.PATH = "/a/0/6/8"
A.FOOT = "/a/0/6/9"
A.DATA = "/a/0/7/4"
A.HW = "/a/0/7/5"

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
  local meta = {}
  A.addPages(m, out, main, sub, meta)
  return out, anims, meta
end

-- THE SEARCH AND ENTRY PAGES' BACKGROUNDS (added for SEARCH / AREA / SIZE /
-- FORMS; drawn by src/ui/HgssDexSearch.lua and src/ui/HgssDexDetails.lua).
-- Read from ov18_021E7048 (search, state 5), ov18_021E71D0 (its sub-pages),
-- ov18_021E7BD0 / 7D90 / 800C / 81A8 / 7ED8 (the entry pages 1-4) and the
-- fragment table ov18_021E6308 (fragment 6 = member 69, 7 = 70, 23 = 88):
--   search_bg            MAIN2 screen 57 over char 58
--   search_<page>        MAIN2 screens 62-68 over char 58 (order, name, type,
--                        height, weight, area, body)
--   search_bar / search_okbar
--                        fragments 6 / 7 (members 69 / 70, 32 x 4, row 20)
--                        over char 4 (MAIN1)
--   search_top3 / search_top2
--                        SUB3 screen 59 / SUB2 screen 60 over char 58
--   area_base            MAIN3 screen 82 over char 83; area_tabs_<0|1> MAIN0
--                        screen 80 (no National Dex) / 81 over char 83
--   area_top             SUB3 screen 84 over char 85; area_map SUB0 screen 86
--                        over char 87 (512 wide, scrolled -72 / +104)
--   area_unknown         fragment 23 (member 88, 20 x 4) over char 85
--   size_base / size_top MAIN3 89 over 90 / SUB2 91 over 92
--   forms_base / forms_front / forms_one / forms_top
--                        MAIN3 96 / MAIN0 95 over 93, member 100 (16 x 4, at
--                        (16,16) when one form was seen) / SUB3 97 over 94
--   compare_base / compare_top
--                        MAIN3 98 over 93 / SUB3 99 over 94
--   return_base / return_top
--                        MAIN3 101 over 102 / SUB2 103 over 104 (page 4,
--                        "RETURN TO LIST")
-- Main pages use palette member 2, the top ones member 18. Each picture is
-- independent: a member that fails to decode is simply absent and the UI
-- draws its fallback.
function A.addPages(m, out, main, sub, meta)
  local G = require("src.import.Gen4Graphics")
  local function cut(img, w, h)
    if img and (img.width > w or img.height > h) then return crop(img, 0, 0, math.min(w, img.width), math.min(h, img.height)) end
    return img
  end
  local chars = {}
  local function ch(i)
    if chars[i] == nil then chars[i] = G.tiles(m(i)) or false end
    return chars[i] or nil
  end
  local function pic(key, member, char, pal, w, h)
    local ok, err = pcall(function()
      local map = G.tilemap(m(member))
      local img = map and ch(char) and G.compose(map, ch(char), pal)
      out[key] = cut(img, w or 256, h or 192)
    end)
    if not ok then out[key] = nil end
    return err
  end
  pic("search_bg", 57, 58, main)
  for i, name in ipairs({ "order", "name", "type", "height", "weight", "area", "body" }) do
    pic("search_" .. name, 61 + i, 58, main)
  end
  pic("search_bar", 69, 4, main, 256, 32)
  pic("search_okbar", 70, 4, main, 256, 32)
  pic("search_top3", 59, 58, sub)
  pic("search_top2", 60, 58, sub)
  pic("area_base", 82, 83, main)
  pic("area_tabs_0", 80, 83, main)
  pic("area_tabs_1", 81, 83, main)
  pic("area_top", 84, 85, sub)
  pic("area_map", 86, 87, sub, 512, 192)
  pic("area_unknown", 88, 85, sub, 160, 32)
  pic("size_base", 89, 90, main)
  pic("size_top", 91, 92, sub)
  pic("forms_base", 96, 93, main)
  pic("forms_front", 95, 93, main)
  pic("forms_one", 100, 93, main, 128, 32)
  pic("forms_top", 97, 94, sub)
  pic("compare_base", 98, 93, main)
  pic("compare_top", 99, 94, sub)
  pic("return_base", 101, 102, main)
  pic("return_top", 103, 104, sub)
  -- the search's OBJ (ov18_021F2F3C): char 72 / pal 75 / cell 73 / anim 74
  -- (`srch_<cell>`, `searchAnims[a]` = first cell of animation a) and
  -- char 23 / pal 32 / cell 24 / anim 25 (`srch2_<cell>`, `search2Anims`)
  local Cells = require("src.import.Gen4Cells")
  local CellAnim = require("src.import.Gen4CellAnim")
  -- the SIZE page's OBJ (ov18_021F4A6C): chars 105 / 109 (cell 106, anim
  -- 107) and 111 / 114 (cell 112, anim 113), palettes 108 / 110 -- the
  -- trainer's figure, boy and girl (`size_<char>_<cell>`)
  for _, set in ipairs({ { "size105_", "size105Anims", 105, 108, 106, 107 }, { "size109_", "size109Anims", 109, 110, 106, 107 },
                         { "size111_", "size111Anims", 111, 108, 112, 113 }, { "size114_", "size114Anims", 114, 110, 112, 113 },
                         { "srch_", "searchAnims", 72, 75, 73, 74 }, { "srch2_", "search2Anims", 23, 32, 24, 25 } }) do
    pcall(function()
      local sheet, pal = G.tiles(m(set[3])), G.palette(m(set[4]))
      local bank, anim = Cells.parse(m(set[5]), G), CellAnim.parse(m(set[6]), G)
      if not (sheet and pal and bank) then return end
      for i, cell in ipairs(bank.cells) do
        local p = Cells.assemble(cell, sheet, pal, bank, G)
        if p then p.originX, p.originY = Cells.extent(cell); out[set[1] .. (i - 1)] = p end
      end
      if anim then
        local firsts = {}
        for a = 0, #anim.sequences - 1 do
          local f = CellAnim.frames(anim, a)
          if f and f[1] then firsts[a] = f[1].cell end
        end
        if meta then meta[set[2]] = firsts end
      end
    end)
  end
end

-- THE SEARCH'S DATA (ov18_021E8410 / ov18_021F7ED4): zukan_data (/a/0/7/4)
-- members 0 / 1 / 2 = height (dm) / weight (hg) / body style per species
-- (u32, u32, u8; index = species), the sort and filter lists (members 13-17
-- alphabetical / heaviest / lightest / tallest / shortest, 18-43 the first
-- letters a-z, 62-78 the types normal..dark, 79-92 the body styles), and
-- zukan_hw_data (/a/0/7/5): member 0 the slider's 153 {height, weight}
-- stops (u16 pairs), member 1 a byte of area flags per species (bit 0 Johto,
-- bit 1 Kanto, bit 2 unknown, bit 3 all; the HeartGold / SoulSilver file is
-- whichever this ROM carries).
function A.searchData(rom)
  local Narc = require("src.import.NarcArchive")
  local function open(path)
    local raw = rom:read(path)
    local arc = raw and Narc.parse(raw)
    if not arc then return nil end
    -- raw members (json2bin, no LZ): a list that starts with species 16
    -- (0x10) would read as an LZ77 header, so nothing is decompressed here
    return function(i) return arc:get(i) end
  end
  local data, hw = open(A.DATA), open(A.HW)
  if not data then return nil end
  local function u16s(b)
    local t = {}
    if not b then return t end
    for k = 0, math.floor(#b / 2) - 1 do
      local lo, hi = b:byte(k * 2 + 1, k * 2 + 2)
      t[#t + 1] = lo + hi * 256
    end
    return t
  end
  local function list(i)
    local t = {}
    for _, v in ipairs(u16s(data(i))) do if v == 0 then break end t[#t + 1] = v end
    return t
  end
  local function u32s(b)
    local t = {}
    if not b then return t end
    for k = 0, math.floor(#b / 4) - 1 do
      local a, b2, c, d = b:byte(k * 4 + 1, k * 4 + 4)
      t[k] = a + b2 * 256 + c * 65536 + d * 16777216
    end
    return t
  end
  local out = { height = u32s(data(0)), weight = u32s(data(1)), body = {} }
  local bodyRaw = data(2) or ""
  for k = 1, #bodyRaw do out.body[k - 1] = bodyRaw:byte(k) end
  -- members 3-10: the SIZE page's scales and y offsets (u16 per species,
  -- ov18_021E8410): player / mon scale for a girl (3 / 4) and a boy (5 / 6),
  -- player / mon y for a girl (7 / 8) and a boy (9 / 10)
  out.size = {}
  for k, name in ipairs({ "playerScaleF", "monScaleF", "playerScaleM", "monScaleM", "playerYF", "monYF", "playerYM", "monYM" }) do
    local t = {}
    for i, v in ipairs(u16s(data(2 + k))) do t[i - 1] = v >= 32768 and v - 65536 or v end
    out.size[name] = t
  end
  out.sorts = { alphabetical = list(13), heaviest = list(14), lightest = list(15), tallest = list(16), shortest = list(17) }
  out.letters, out.types, out.bodies = {}, {}, {}
  for l = 0, 25 do out.letters[l] = list(18 + l) end
  for t = 0, 16 do out.types[t] = list(62 + t) end
  for s = 0, 13 do out.bodies[s] = list(79 + s) end
  if hw then
    local stops = u16s(hw(0))
    out.stops = {}
    for k = 0, math.floor(#stops / 2) - 1 do out.stops[k] = { stops[k * 2 + 1], stops[k * 2 + 2] } end
    local flags = hw(1) or ""
    out.areaFlags = {}
    for k = 1, #flags do out.areaFlags[k - 1] = flags:byte(k) end
  end
  return out
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
  local images, anims, meta = A.images(x.rom)
  if not images then return nil end
  local index = {}
  for key, image in pairs(images) do
    index[key] = x:saveImage("hgss_dex/" .. key, image, { originX = image.originX, originY = image.originY })
  end
  index.listAnims = anims
  for key, value in pairs(meta or {}) do index[key] = value end
  index.orders = A.orders(x.rom)
  local okSearch, search = pcall(A.searchData, x.rom)
  index.search = okSearch and search or nil
  index.source = "ROM:/a/0/6/8 (zukan_gra), /a/0/6/9 (pokefoot), /a/0/7/4 (zukan_data)"
  return index
end

return A
