-- HEARTGOLD / SOULSILVER POKeATHLON: PENNANT CAPTURE's art and tables
-- (pokeheartgold asm/overlay_96.s 0x022047EC..0x02209130, event 1, sub-app
-- ov96_0221A8D0; the reading is written up in scratch_claude/athlon/NOTES.md,
-- "## Pennant Capture"), written as `gen4_hgss_pennant`.
--
--   NARC 0xE2 = /a/2/2/4 (ov96_02205048 / 022050B4 / 02207DDC / 02207E7C):
--     field         screen 2 over char 1, palette 0: the 512 x 512 field the
--                   touch screen scrolls over (BG0, camera = the player's
--                   Pokemon - (128, 96), ov96_02205D30)
--     field_<f>     the same with BG0 chars 0x1800.. replaced by frame f
--                   (0..5) of char 3 (ov96_02207BE4: a frame every 5 ticks)
--     top_a, top_b  screens 7 / 8 over chars 5 / 6, palette 4 (the top
--                   screen's two layers, 02207DDC)
--     digits        screen 9 over char 5 (the 3-digit flag counter's glyph
--                   rects, 02208374)
--     <set>_<seq>_<frame>  sprite sets (palette, anims, cells, char):
--                   obj 14/15/16/17 (field sprites: 0 flag, 1 block, 2 dizzy
--                   stars, 3 planted flag, 4 puff, 5/6 decoration, 7 spark,
--                   8/9 flag up / down), ui 10/11/12/13 (the top screen's)
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 member 4: the star tables (`params`, 25 ints: by
--     POWER knock x10, by SKILL flick x10, by SPEED flick x10, by STAMINA
--     dizzy frames, by SPEED top speed) -- ov96_02206E88
--   NARC 0xAA = /a/1/7/0 member 14: `sizes` (3 pairs by the performance row's
--     byte 6, 1..3: { sprite y offset, body radius })
--   NARC 0xE3 = /a/2/2/5 members 0..19: the field layouts (LCRandom % 20),
--     `layouts[k] = { deco = {10 x {x, y}}, blocks = {20}, spots = {20} }`
--     in pixels (bytes x 8; a pair with a 0 is empty) -- ov96_022052B0

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local A = {}

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

-- the BG0 animation: ov96_02207BE4 copies 0x800 bytes of char 3 (frame f at
-- f * 0x800) to BG0 char offset 0x1800
local ANIM_AT, ANIM_LEN = 0x1800, 0x800

function A.images(rom)
  local m = archive(rom, "/a/2/2/4")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  local pal, sheet = G.palette(m(0), true), G.tiles(m(1))
  local fmap = G.tilemap(m(2))
  out.field = G.compose(fmap, sheet, pal)
  local anim = G.tiles(m(3))
  if sheet and anim and anim.pixels then
    local frames = math.floor(#anim.pixels / ANIM_LEN)
    meta.fieldFrames = frames
    for f = 0, frames - 1 do
      local chunk = anim.pixels:sub(f * ANIM_LEN + 1, (f + 1) * ANIM_LEN)
      local px = sheet.pixels
      local patched = {}
      for k, v in pairs(sheet) do patched[k] = v end
      patched.pixels = px:sub(1, ANIM_AT) .. chunk .. px:sub(ANIM_AT + ANIM_LEN + 1)
      out["field_" .. f] = G.compose(fmap, patched, pal)
    end
  end
  local tpal = G.palette(m(4), true)
  local s5, s6 = G.tiles(m(5)), G.tiles(m(6))
  out.top_a = G.compose(G.tilemap(m(7)), s5, tpal)
  out.top_b = G.compose(G.tilemap(m(8)), s6, tpal)
  out.digits = G.compose(G.tilemap(m(9)), s5, tpal)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  local SETS = { { "obj", 14, 15, 16, 17 }, { "ui", 10, 11, 12, 13 } }
  for _, set in ipairs(SETS) do
    local key = set[1]
    local opal, osheet = G.palette(m(set[2]), true), G.tiles(m(set[5]))
    local bank, an = Cells.parse(m(set[4]), G), CA.parse(m(set[3]), G)
    if opal and osheet and bank and an then
      meta.objSeq[key] = {}
      for q = 0, #an.sequences - 1 do
        local frames = CA.frames(an, q) or {}
        local list = {}
        for f, fr in ipairs(frames) do
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
  local b = p and p(4)
  if b then
    out.params = {}
    for k = 0, 24 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local s = p and p(14)
  if s then
    out.sizes = {}
    for k = 1, 3 do out.sizes[k] = { i32(s, (k - 1) * 8 + 1), i32(s, (k - 1) * 8 + 5) } end
  end
  local l = archive(rom, "/a/2/2/5")
  out.layouts = {}
  for k = 0, 19 do
    local mb = l and l(k)
    if mb and #mb >= 100 then
      local function pairsAt(first, n)
        local list = {}
        for i = 0, n - 1 do
          local x, y = mb:byte(first + i * 2), mb:byte(first + i * 2 + 1)
          list[i + 1] = (x ~= 0 and y ~= 0) and { x * 8, y * 8 } or false
        end
        return list
      end
      out.layouts[k] = { deco = pairsAt(1, 10), blocks = pairsAt(21, 20), spots = pairsAt(61, 20) }
    end
  end
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_pennant/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  out.fieldFrames = meta.fieldFrames
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
