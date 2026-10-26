-- HEARTGOLD / SOULSILVER POKeATHLON: CIRCLE PUSH's art and tables
-- (pokeheartgold asm/overlay_96.s 0x021F010C..0x021F5018, sub-app table
-- ov96_0221A7F4; see scratch_claude/athlon/NOTES.md, "## Circle Push"),
-- written as `gen4_hgss_circle_push`.
--
--   NARC 0xA7 = /a/1/6/7 (ov96_021F0D60 / 021F3CBC / 021F010C):
--     stage        BG0 of the touch screen: screen 6 over char 5, palette 4
--                  (the round ring seen from above, playable x 16..240,
--                  y 16..176 -- ov96_021F2F7C)
--     border       BG1: screen 7 over char 5 (the clock: 43 tiles round the
--                  edge are cleared one by one, ov96_021F2984)
--     overlay      BG2: screen 10 over char 9, palette 8 at slot 1 (blended
--                  at 12/4 -- the light over the ring)
--     top          the top screen: screen 13 over char 12 (BG5), palettes
--                  21 (slots 0-1), 11 (slot 2), 14 (slot 3)
--     top_<n>      screens 16..20 over char 15 loaded at tile 0x80 (BG6; 16 =
--                  the big digits 0-4 / 5-9, 32 x 64 each, ov96_021F4EF8) and
--                  23 / 24 over char 22 (BG7) -- the score board's parts
--     <set>_<seq>_<frame>  the sprite sets (palette, anims, cells, char):
--                  ring 0/1/2/3 (the four circles, sequence = kind - 1),
--                  a 25/26/27/28 and b 29/30/31/32 (the round / score parts)
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 member 1 (ov96_021F2B24, read with
--     ReadWholeNarcMemberByIdPair(0xAA, 1) in ov96_021F010C): 15 ints,
--     [0..4] POWER -> push (/10 px a frame), [5..9] STAMINA -> push frames,
--     [10..14] SPEED -> walk (/10 px a frame); member 11 = three (w, h) body
--     sizes by the performance row's byte 6 (ov96_021EAF70).
--   The circle layouts are not in a NARC: they are overlay data
--   (ov96_0221DBC8 -> 15 layouts of up to three { kind, x, y }, kinds 1..4 =
--   ov96_0221DBB8 { radius, points } = (56, 1) (32, 2) (24, 3) (16, 5)) and
--   are written out as `layouts` / `kinds` by this module.

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local A = {}

-- ov96_0221DBB8 -> ov96_0221BE10 / BE0C / BE04 / BE08: { radius, points }
A.KINDS = { { r = 56, pts = 1 }, { r = 32, pts = 2 }, { r = 24, pts = 3 }, { r = 16, pts = 5 } }

-- ov96_0221DBC8[0..14] (ov96_0221BF74, BF14, BEF4, BED4, BEB4, BE74, BE94,
-- BF54, BF94, BE14, BE34, BF34, BFB4, BE54, BFD4): { kind, x, y } in
-- touch-screen pixels. Layout 0 is round 1; 1..5 rounds 2-3; 6..9 round 4;
-- 10..14 rounds 5-6 (ov96_021F30F8).
A.LAYOUTS = {
  [0] = { { 1, 128, 96 } },
  { { 3, 64, 64 }, { 2, 144, 104 } },
  { { 3, 200, 64 }, { 2, 96, 112 } },
  { { 3, 128, 56 }, { 2, 128, 128 } },
  { { 2, 192, 64 }, { 3, 136, 56 } },
  { { 2, 88, 80 }, { 3, 200, 128 } },
  { { 2, 64, 64 }, { 2, 192, 64 }, { 4, 56, 136 } },
  { { 2, 72, 96 }, { 3, 144, 96 }, { 4, 200, 96 } },
  { { 2, 192, 64 }, { 3, 64, 96 }, { 4, 184, 144 } },
  { { 3, 144, 56 }, { 2, 96, 136 }, { 4, 184, 104 } },
  { { 4, 208, 48 }, { 2, 128, 96 }, { 4, 48, 144 } },
  { { 4, 128, 56 }, { 3, 128, 96 }, { 4, 128, 136 } },
  { { 4, 200, 48 }, { 3, 72, 96 }, { 4, 184, 144 } },
  { { 4, 104, 48 }, { 3, 168, 112 }, { 4, 48, 144 } },
  { { 4, 48, 48 }, { 4, 208, 48 }, { 3, 128, 128 } },
}

-- ov96_0221BDD4: the start spots, team t mon m (touch-screen pixels)
A.STARTS = {
  { { 40, 40 }, { 40, 72 }, { 88, 40 } },
  { { 216, 40 }, { 168, 40 }, { 216, 72 } },
  { { 40, 168 }, { 88, 168 }, { 40, 146 } },
  { { 216, 168 }, { 216, 146 }, { 168, 168 } },
}

local function archive(rom, path)
  local raw = rom:read(path)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  return function(i)
    local b = arc:get(i)
    return b and (G.isCompressed(b) and G.decompress(b) or b)
  end, arc
end

local function i32(b, i)
  local a, b2, c, d = b:byte(i, i + 3)
  local v = a + b2 * 256 + c * 65536 + d * 16777216
  if v >= 2 ^ 31 then v = v - 2 ^ 32 end
  return v
end

-- a palette file's first `rows` sixteen-colour rows placed at slot `at`
local function place(into, pal, at, rows)
  if not pal then return end
  for i = 1, rows * 16 do
    if pal[i] then into[at * 16 + i] = pal[i] end
  end
end

local function fill(p)
  local top = 0
  for i in pairs(p) do if i > top then top = i end end
  for i = 1, top do p[i] = p[i] or { 0, 0, 0 } end
  return p
end

function A.images(rom)
  local m = archive(rom, "/a/1/6/7")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  -- main (touch) BG palettes: 4 at slot 0, 8 at slot 1 (ov96_021F0D60)
  local mainPal = {}
  place(mainPal, G.palette(m(4), true), 0, 1)
  place(mainPal, G.palette(m(8), true), 1, 1)
  fill(mainPal)
  local sheet5 = G.tiles(m(5))
  out.stage = G.compose(G.tilemap(m(6)), sheet5, mainPal)
  out.border = G.compose(G.tilemap(m(7)), sheet5, mainPal)
  -- BG2's map is repainted with palette 1 over its whole 32 x 24
  -- (BgTilemapRectChangePalette in ov96_021F0D60)
  local ov = G.tilemap(m(10))
  if ov and ov.cells then for _, c in ipairs(ov.cells) do c.palette = 1 end end
  out.overlay = G.compose(ov, G.tiles(m(9)), mainPal)
  -- sub (top) BG palettes: 21 at 0 (two rows), 11 at 2, 14 at 3
  local subPal = {}
  place(subPal, G.palette(m(21), true), 0, 2)
  place(subPal, G.palette(m(11), true), 2, 1)
  place(subPal, G.palette(m(14), true), 3, 1)
  fill(subPal)
  -- BG5 is repainted with palette 2 and BG6 with palette 3 (ov96_021F3CBC);
  -- BG6's maps get +0x80 on every tile (ov96_021F4FD8) to meet their char,
  -- loaded at tile 0x80, so composed against the sheet they need neither
  local function slot(map, s)
    if map and map.cells then for _, c in ipairs(map.cells) do c.palette = s end end
    return map
  end
  out.top = G.compose(slot(G.tilemap(m(13)), 2), G.tiles(m(12)), subPal)
  local sheet15 = G.tiles(m(15))
  for s = 16, 20 do out["top_" .. s] = G.compose(slot(G.tilemap(m(s)), 3), sheet15, subPal) end
  local sheet22 = G.tiles(m(22))
  for s = 23, 24 do out["top_" .. s] = G.compose(G.tilemap(m(s)), sheet22, subPal) end
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char } (ov96_021F010C, ids 0x65 / 0x68 / 0x69)
  local SETS = { { "ring", 0, 1, 2, 3 }, { "a", 25, 26, 27, 28 }, { "b", 29, 30, 31, 32 } }
  for _, set in ipairs(SETS) do
    local key = set[1]
    local opal, osheet = G.palette(m(set[2]), true), G.tiles(m(set[5]))
    local bank, anim = Cells.parse(m(set[4]), G), CA.parse(m(set[3]), G)
    if opal and osheet and bank and anim then
      meta.objSeq[key] = {}
      for q = 0, #anim.sequences - 1 do
        local list = {}
        for f, fr in ipairs(CA.frames(anim, q) or {}) do
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
  return out, meta
end

function A.tables(rom)
  local out = {}
  local p = archive(rom, "/a/1/7/0")
  local b = p and p(1)
  if b and #b >= 60 then
    out.params = {}
    for k = 0, 14 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local r = p and p(11)
  if r and #r >= 24 then
    out.sizes = {}
    for k = 0, 2 do out.sizes[k + 1] = { i32(r, k * 8 + 1), i32(r, k * 8 + 5) } end
  end
  out.kinds = A.KINDS
  out.layouts = A.LAYOUTS
  out.starts = A.STARTS
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_circle_push/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
