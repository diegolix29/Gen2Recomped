-- HEARTGOLD / SOULSILVER POKeATHLON: the team-choosing screen's information
-- panel (pokeheartgold asm/overlay_97.s, the course's first sub-overlay;
-- src/ui/HgssPokeathlonTeamInfo.lua), written as `gen4_hgss_athlon_team`.
--
--   NARC 0xF3 = /a/2/4/1 (ov97_0221F14C / 0221F7DC):
--     back          screen 2 over char 1, palette 0 (BG3, priority 3): the
--                   header bar, the field, the medal strip
--     plate         screen 3 over char 1 (BG2, priority 2): the stats table
--                   and the nickname plate, shown only while the cursor is on
--                   a Pokemon
--     medal_<i>     OBJ set (char 7, palette 4, cells 6, anims 5) sequence i,
--                   i = 0..4 the five single courses' Medals (Speed, Power,
--                   Skill, Stamina, Jump); 32 x 32 about its centre
--   /a/0/1/6 member 7 (LoadFontPal0): `ink` = the font palette's colours
--     1..8 (the lines print (1, 2), a male sign (7, 8), a female one (3, 4))
--
-- The stars are the summary's (`gen4_hgss_summary_art` perf_<c>: /a/1/6/2
-- char 66, palette 65, cells 67, anims 68 -- the same resources ov97 loads as
-- NARC 0xA2 members 0x41..0x44); the Pokemon is its front picture.

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local A = {}

A.PATH = "/a/2/4/1"
A.FONT_PATH, A.FONT_PALETTE = "/a/0/1/6", 7

local function archive(rom, path)
  local raw = rom:read(path)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  return function(i)
    local b = arc:get(i)
    return b and (G.isCompressed(b) and G.decompress(b) or b)
  end
end

-- a 256 x 256 screen cut to the DS's 192 lines
local function screen(m, n, sheet, pal)
  local img = G.compose(G.tilemap(m(n)), sheet, pal)
  if img and img.height > 192 then
    img = { width = img.width, height = 192, rgba = img.rgba:sub(1, img.width * 192 * 4) }
  end
  return img
end

function A.images(rom)
  local out = {}
  local m = archive(rom, A.PATH)
  if not m then return out end
  local pal, sheet = G.palette(m(0), true), G.tiles(m(1))
  out.back = screen(m, 2, sheet, pal)
  out.plate = screen(m, 3, sheet, pal)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  local opal, osheet = G.palette(m(4), true), G.tiles(m(7))
  local bank, anim = Cells.parse(m(6), G), CA.parse(m(5), G)
  if opal and osheet and bank and anim then
    for q = 0, 4 do
      local fr = (CA.frames(anim, q) or {})[1]
      local cell = fr and bank.cells[(fr.cell or 0) + 1]
      local pic = cell and Cells.assemble(cell, osheet, opal, bank, G)
      if pic then
        pic.originX, pic.originY = Cells.extent(cell)
        out["medal_" .. q] = pic
      end
    end
  end
  return out
end

function A.tables(rom)
  local out = {}
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
    out[name] = x:saveImage("hgss_athlon_team/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
