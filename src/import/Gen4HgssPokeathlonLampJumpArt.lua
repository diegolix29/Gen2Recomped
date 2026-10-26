-- HEARTGOLD / SOULSILVER POKeATHLON: LAMP JUMP's art and tables
-- (pokeheartgold asm/overlay_96.s, the event's code 0x021F5018..0x021F7934,
-- event 5, sub-app ov96_0221A920; see scratch_claude/athlon/NOTES.md
-- "## Lamp Jump"), written as `gen4_hgss_lamp_jump`.
--
--   NARC 0xA8 = /a/1/6/8 (not packed; ov96_021F5980 / 021F6C18):
--     back         the touch screen's BG2 (priority 3, behind the 3D band):
--                  screen 8 over char 7, palette 4 (the main engine is the
--                  touch screen -- the display is swapped)
--     front        BG1 (priority 1, in front of the band): screen 6 over char 5
--     top          the top screen's BG5 (priority 2): screen 13 over char 12,
--                  palette 9 (two rows)
--     top_b        BG4 (priority 1): screen 11 over char 10 -- the score's
--                  digits are written into it at tiles (1 + 4 i, 0)
--     digits       screen 14 over char 10: the digit glyphs, 4 x 8 tiles each,
--                  five a row (ov96_021F6E68)
--     obj_<seq>_<frame>  the one sprite set: palette 0, anims 1, cells 2,
--                  char 3 (res 0x65). Sequences used: 1..5 the points popping
--                  out of a lamp, 7 lamp lit, 8 lamp out, 9 collision spark,
--                  10 lamp burst, 11 dizzy stars, 12 the top screen's (heap
--                  +0x64), 13..16 the team lamp markers
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 member 6 (ov96_021F5018 case 5 -> ov96_021F715C --
--     NOT member 5): `params`, 15 ints read by the stars (course record bytes
--     POWER SPEED JUMP STAMINA SKILL):
--     [0..4]   by JUMP: the catapult's kick, /12 (+0x2C)
--     [5..9]   by STAMINA: frames a collision stuns (+0x30)
--     [10..14] by SKILL: the sideways drift, /12 (+0x34)
--   NARC 0xAA member 16 (case 4): `sizes`, by the performance row's size class
--     (byte 6, 1..3 -- ov96_021E6138): { sprite y offset, body radius }
--   The 29 lamps' places are overlay data (ov96_0221C21C, u16 x / y in 8-px
--     units, written out as `lamps`).

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local A = {}

-- ov96_0221C21C: { x, y } x 8 = pixels in the 384-px-tall two-screen space
-- (y 0..191 the top screen, 192..383 the touch screen)
A.LAMPS = {
  { 16, 8 },
  { 4, 11 }, { 12, 11 }, { 20, 11 }, { 28, 11 },
  { 8, 14 }, { 16, 14 }, { 24, 14 },
  { 4, 17 }, { 12, 17 }, { 20, 17 }, { 28, 17 },
  { 8, 20 }, { 16, 20 }, { 24, 20 },
  { 4, 23 }, { 12, 23 }, { 20, 23 }, { 28, 23 },
  { 8, 25 }, { 16, 25 }, { 24, 25 },
  { 4, 28 }, { 12, 28 }, { 20, 28 }, { 28, 28 },
  { 8, 31 }, { 16, 31 }, { 24, 31 },
}

local function archive(rom, path)
  local raw = rom:read(path)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  local okLz, Lz = pcall(require, "src.import.Gen5Lz")
  return function(i)
    local b = arc:get(i)
    if not b then return nil end
    if okLz and Lz.isCompressed and Lz.isCompressed(b) then return Lz.decompress(b) end
    if G.isCompressed(b) then return G.decompress(b) end
    return b
  end, arc
end

local function i32(b, i)
  local a, b2, c, d = b:byte(i, i + 3)
  local v = a + b2 * 256 + c * 65536 + d * 16777216
  if v >= 2 ^ 31 then v = v - 2 ^ 32 end
  return v
end

-- a palette file's first `rows` sixteen-colour rows (GfGfxLoader_GXLoadPal
-- loads 0x20 / 0x40 bytes), the other rows black
local function rows(pal, n)
  local out = {}
  if pal then for i = 1, n * 16 do out[i] = pal[i] end end
  for i = 1, 256 do out[i] = out[i] or { 0, 0, 0 } end
  return out
end

function A.images(rom)
  local m = archive(rom, "/a/1/6/8")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  local mainPal = rows(G.palette(m(4), true), 1)
  out.back = G.compose(G.tilemap(m(8)), G.tiles(m(7)), mainPal)
  out.front = G.compose(G.tilemap(m(6)), G.tiles(m(5)), mainPal)
  local subPal = rows(G.palette(m(9), true), 2)
  local s10 = G.tiles(m(10))
  out.top = G.compose(G.tilemap(m(13)), G.tiles(m(12)), subPal)
  out.top_b = G.compose(G.tilemap(m(11)), s10, subPal)
  out.digits = G.compose(G.tilemap(m(14)), s10, subPal)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char } (ov96_021F6C18)
  local SETS = { { "obj", 0, 1, 2, 3 } }
  for _, set in ipairs(SETS) do
    local key = set[1]
    local opal, osheet = G.palette(m(set[2]), true), G.tiles(m(set[5]))
    local bank, an = Cells.parse(m(set[4]), G), CA.parse(m(set[3]), G)
    if opal and osheet and bank and an then
      meta.objSeq[key] = {}
      for q = 0, #an.sequences - 1 do
        local list = {}
        for f, fr in ipairs(CA.frames(an, q) or {}) do
          local cell = bank.cells[(fr.cell or 0) + 1]
          local pic = cell and Cells.assemble(cell, osheet, opal, bank, G)
          if pic then
            pic.originX, pic.originY = Cells.extent(cell)
            out[("%s_%d_%d"):format(key, q, f - 1)] = pic
          end
          list[f] = fr.duration or 1
        end
        meta.objSeq[key][q] = list
      end
    end
  end
  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out, meta
end

function A.tables(rom)
  local out = {}
  local p = archive(rom, "/a/1/7/0")
  local b = p and p(6)
  if b and #b >= 60 then
    out.params = {}
    for k = 0, 14 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local s = p and p(16)
  if s and #s >= 24 then
    out.sizes = {}
    for k = 1, 3 do out.sizes[k] = { i32(s, (k - 1) * 8 + 1), i32(s, (k - 1) * 8 + 5) } end
  end
  out.lamps = {}
  for i, l in ipairs(A.LAMPS) do out.lamps[i] = { l[1] * 8, l[2] * 8 } end
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_lamp_jump/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
