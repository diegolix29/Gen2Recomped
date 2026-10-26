-- HEARTGOLD / SOULSILVER POKeATHLON DOME: THE SIDE ROOMS' RECORD SCREENS
-- (pokeheartgold asm/overlay_99.s, ScrCmd_712's four apps; overlay 98 is
-- their library), written as `gen4_hgss_athlon_rooms` for
-- src/ui/HgssPokeathlonCourseRecord.lua, HgssPokeathlonMedalList.lua,
-- HgssPokeathlonEventRecord.lua and HgssPokeathlonTrophies.lua.
--
-- Everything is NARC 0xB1 = /a/1/7/7, its members LZ11-packed (src.import.
-- Gen5Lz). On the cartridge engine A (main) is the BOTTOM screen in all four
-- (ov98_0221F090 clears POWCNT bit 15), so "_b" below is the touch screen and
-- "_t" the top one.
--
--   course records (ov99_021E5C88 / 5D58), palettes 30 -> main rows 0-2,
--   36 -> row 15; 33 -> sub rows 0-1, 39 -> row 15:
--     c_b1        char 31 screen 32 (main BG1, priority 3)
--     c_b2_<c>    char 62 screen 63 + c (main BG2, priority 2), course c's panel
--     c_b3        char 37 screen 38 (main BG3, priority 1)
--     c_t0        char 34 screen 35 (sub BG0, priority 3)
--     c_t1_<c>    char 68 screen 69 + c (sub BG1, priority 2), course c's panel
--     c_t3        char 40 screen 41 (sub BG3, priority 1)
--   the medals list (ov99_021E7D30 / 7DA4), palette 42 main, 43 sub:
--     m_b0        char 44 screen 46 (main BG0, priority 3)
--     m_b2        char 44 screen 47 (main BG2, 512 wide, priority 2)
--     m_star      char 48's 2 x 2 tiles 1 2 / 3 4 (main BG3, ov99_021E73E0's
--                 Medalist mark over an icon)
--     m_t0        char 45 screen 49 (sub BG0); m_t2 char 45 screen 50 (sub BG2,
--                 the "Medalist Pokemon" banner)
--   the event records (ov99_021E8590 / 87D0), palette 51 on both engines:
--     e_b0 / e_t0 char 52 screens 53 / 54; `_link` = row 1 from the file's
--                 row 2 (ov99_021E87D0's swap, 0x40 instead of 0x20)
--     e_icon_<ev>_<act>  char 55 (a 60 x 12 tile sheet) 6 x 6 tiles at
--                 (6 ev, 6 act) -- ov99_021E86D4's blit
--   the trophies (ov99_021E69D8): t_b0 = 56 / 57 / 58, t_t0 = 59 / 60 / 61
--   OBJ sets {palette, char, cell, anim}: o0 = 0 1 2 3 (cursors, crowns,
--     markers), o4 = 4 5 6 7 (the Medals, seq = course), o8 = 8 9 10 11 (big
--     digits), o12 = 12 13 14 15 (the "1ST" ribbon), o16 = 16 17 18 19 (the
--     player: seq 0 boy, 1 girl), o20 = 20 21 22 23 (small digits 0-9,
--     sparkles 10-12), o24 = 24 25 26 27 (the page arrows); every cell as
--     o<set>_c<cell>, and `seqs["o<set>_<seq>"]` = { {cell key, ticks, dx, dy} ... }
--   /a/0/1/6 member 7 (LoadFontPal0): `ink` = the font palette's colours 1..8;
--   `banner_ink` = palette 43 row 1 colours 1 2 3 (window 11's ink and fill)

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")
local Lz = require("src.import.Gen5Lz")

local A = {}

A.PATH = "/a/1/7/7"
A.FONT_PATH, A.FONT_PALETTE = "/a/0/1/6", 7
A.SETS = { { 0, 1, 2, 3 }, { 4, 5, 6, 7 }, { 8, 9, 10, 11 }, { 12, 13, 14, 15 },
  { 16, 17, 18, 19 }, { 20, 21, 22, 23 }, { 24, 25, 26, 27 } }

local function archive(rom, path)
  local raw = rom:read(path)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  return function(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

-- a 256-colour palette with rows placed: spec = { {member, row, fromRow, rows} }
local function palette(m, spec)
  local out = {}
  for i = 1, 256 do out[i] = { 0, 0, 0 } end
  for _, s in ipairs(spec) do
    local p = G.palette(m(s[1]), true) or {}
    for i = 0, s[4] * 16 - 1 do
      local c = p[s[3] * 16 + i + 1]
      if c then out[s[2] * 16 + i + 1] = c end
    end
  end
  return out
end

local function cut(img, h)
  if img and img.height > h then
    img = { width = img.width, height = h, rgba = img.rgba:sub(1, img.width * h * 4) }
  end
  return img
end

local function screen(m, char, scr, pal)
  local sheet = G.tiles(m(char))
  local map = G.tilemap(m(scr))
  return sheet and map and cut(G.compose(map, sheet, pal), 192)
end

-- tiles of `sheet` laid out as a w x h block starting at `first`, row stride `stride`
local function block(sheet, pal, first, w, h, stride)
  local cells = {}
  for ty = 0, h - 1 do
    for tx = 0, w - 1 do cells[ty * w + tx + 1] = { tile = first + ty * stride + tx, palette = 0 } end
  end
  return G.compose({ width = w * 8, height = h * 8, cells = cells }, sheet, pal)
end

function A.images(rom)
  local out = {}
  local m = archive(rom, A.PATH)
  if not m then return out end
  -- course records
  local pc = palette(m, { { 30, 0, 0, 3 }, { 36, 15, 0, 1 } })
  local pt = palette(m, { { 33, 0, 0, 2 }, { 39, 15, 0, 1 } })
  out.c_b1, out.c_b3 = screen(m, 31, 32, pc), screen(m, 37, 38, pc)
  out.c_t0, out.c_t3 = screen(m, 34, 35, pt), screen(m, 40, 41, pt)
  for c = 0, 4 do
    out["c_b2_" .. c] = screen(m, 62, 63 + c, pc)
    out["c_t1_" .. c] = screen(m, 68, 69 + c, pt)
  end
  -- the medals list
  local pm, ps = palette(m, { { 42, 0, 0, 2 } }), palette(m, { { 43, 0, 0, 2 } })
  out.m_b0, out.m_b2 = screen(m, 44, 46, pm), screen(m, 44, 47, pm)
  out.m_t0, out.m_t2 = screen(m, 45, 49, ps), screen(m, 45, 50, ps)
  local s48 = G.tiles(m(48))
  out.m_star = s48 and block(s48, pm, 0, 2, 2, 2)
  -- the event records
  local pe = palette(m, { { 51, 0, 0, 16 } })
  local pl = palette(m, { { 51, 0, 0, 16 }, { 51, 1, 2, 1 } })
  out.e_b0, out.e_t0 = screen(m, 52, 53, pe), screen(m, 52, 54, pe)
  out.e_b0_link, out.e_t0_link = screen(m, 52, 53, pl), screen(m, 52, 54, pl)
  local s55 = G.tiles(m(55))
  if s55 then
    for ev = 0, 9 do
      for act = 0, 1 do out[("e_icon_%d_%d"):format(ev, act)] = block(s55, pe, 6 * ev + 360 * act, 6, 6, 60) end
    end
  end
  -- the trophies
  out.t_b0 = screen(m, 57, 58, palette(m, { { 56, 0, 0, 2 } }))
  out.t_t0 = screen(m, 60, 61, palette(m, { { 59, 0, 0, 2 } }))
  -- the OBJ sets
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  for _, set in ipairs(A.SETS) do
    local opal, osheet = G.palette(m(set[1]), true), G.tiles(m(set[2]))
    local bank, anim = Cells.parse(m(set[3]), G), CA.parse(m(set[4]), G)
    if opal and osheet and bank and anim then
      local done = {}
      for q = 0, #anim.sequences - 1 do
        for _, fr in ipairs(CA.frames(anim, q) or {}) do
          local key = ("o%d_c%d"):format(set[1], fr.cell or 0)
          if not done[key] then
            done[key] = true
            local cell = bank.cells[(fr.cell or 0) + 1]
            local pic = cell and Cells.assemble(cell, osheet, opal, bank, G)
            if pic then
              pic.originX, pic.originY = Cells.extent(cell)
              out[key] = pic
            end
          end
        end
      end
    end
  end
  return out
end

function A.tables(rom)
  local out = { seqs = {} }
  local m = archive(rom, A.PATH)
  if m then
    local CA = require("src.import.Gen4CellAnim")
    local Cells = require("src.import.Gen4Cells")
    for _, set in ipairs(A.SETS) do
      local anim, bank = CA.parse(m(set[4]), G), Cells.parse(m(set[3]), G)
      for q = 0, ((anim and anim.sequences) and #anim.sequences or 0) - 1 do
        local list = {}
        for _, fr in ipairs(CA.frames(anim, q) or {}) do
          local cell = bank and bank.cells[(fr.cell or 0) + 1]
          -- an empty cell (no OAM) is a blank frame
          local key = (cell and #cell.oam > 0) and ("o%d_c%d"):format(set[1], fr.cell or 0) or false
          -- a translated frame (NANR element type 2 / SRT) moves the cell
          list[#list + 1] = { key, tonumber(fr.duration) or 1, fr.x or 0, fr.y or 0 }
        end
        out.seqs[("o%d_%d"):format(set[1], q)] = list
      end
    end
    local p43 = G.palette(m(43), true)
    if p43 then out.banner_ink = { p43[18], p43[19], p43[20] } end
  end
  local f = archive(rom, A.FONT_PATH)
  local fp = f and G.palette(f(A.FONT_PALETTE))
  if fp then
    out.ink = {}
    for i = 1, 8 do
      local c = fp[i + 1]
      if c then out.ink[i] = { c[1], c[2], c[3] } end
    end
  end
  return out
end

function A.build(x)
  local out = {}
  for name, img in pairs(A.images(x.rom)) do
    out[name] = x:saveImage("hgss_athlon_rooms/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
