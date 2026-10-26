-- HEARTGOLD / SOULSILVER POKeATHLON: RING DROP's art and tables
-- (pokeheartgold asm/overlay_96.s, the event's code 0x02215710..0x0221A57C,
-- event 7, sub-app ov96_0221A880; see scratch_claude/athlon/NOTES.md
-- "## Ring Drop"), written as `gen4_hgss_ring_drop`.
--
--   NARC 0xF2 = /a/2/4/0 (ov96_0221663C / 022163AC / 022194C4), LZ11 packed:
--     ring          main BG2: char 5, screen 6, palette 0 -- the ring on its
--                   stand, 256 x 256 (the touch screen shows rows 0..191)
--     plate         main BG0: char 1, screen 2 -- the clock's plate at the
--                   bottom (the clock icon and digits sit on it, 02219E60)
--     top           sub BG4: char 11, screen 12, palette 8 -- the top screen
--     top_fg        sub BG6: char 9, screen 10 -- the score's layer, with the
--                   three score digits' cells cleared (02219A5C copies them in)
--     digit_<d>     the score glyphs: screen 7 (a 20 x 16 tile atlas, digit d
--                   at tile ((d % 5) * 4, (d / 5) * 8), 4 x 8 tiles) over char 9
--     a_<seq>_<f>   sprite set A, the touch screen (palette 13, anims 14,
--                   cells 15, char 16): 1 faint stars, 2-6 SWITCH (2 ready,
--                   3 off, 4 pressed, 5 refused, 6 flashing = tired), 7 hit
--                   star, 8 smoke, 9 sweat, 10 puff, 11-14 tackle wave (up /
--                   down / left / right), 15-18 its fade, 20 clock, 21 Poke
--                   Ball, 22 ball opening
--     b_<seq>_<f>   sprite set B, the top screen (palette 17, anims 18, cells
--                   19, char 20): 1-4 icon frames (replaced by the teams'
--                   Pokemon icons), 5 sweat, 6-9 places 1st-4th, 10 Poke Ball,
--                   12-15 the team flags (red, blue, green, yellow)
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 MEMBER 9 (ov96_0221918C -- not 7: the per-event
--     tables are not numbered by event id): `params`, 30 ints --
--     [0..4] tackle power x10 by POWER, [5..9] tackle damage x10 by POWER,
--     [10..14] stamina by STAMINA, [15..19] walking speed x10 by SPEED,
--     [20..24] never read, [25..29] the stomp's power and damage x10 by JUMP
--   NARC 0xAA = /a/1/7/0 MEMBER 19 (ov96_02217B84): `sizes` (3 pairs by the
--     performance row's byte 6, 1..3: { body y offset, body radius })

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")
local Lz = require("src.import.Gen5Lz")

local A = {}

local function archive(rom, path)
  local raw = rom:read(path)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  return function(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b)
    elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end, arc
end

local function i32(b, i)
  local a, b2, c, d = b:byte(i, i + 3)
  local v = a + b2 * 256 + c * 65536 + d * 16777216
  if v >= 2 ^ 31 then v = v - 2 ^ 32 end
  return v
end

-- the score digits' cells on BG6: tile (16 + 4 i, 11), 4 x 8 each (02219A5C)
local DIGIT_X, DIGIT_Y = 16, 11

function A.images(rom)
  local m = archive(rom, "/a/2/4/0")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  local pal0 = G.palette(m(0), true)
  out.ring = G.compose(G.tilemap(m(6)), G.tiles(m(5)), pal0)
  out.plate = G.compose(G.tilemap(m(2)), G.tiles(m(1)), pal0)
  local pal8 = G.palette(m(8), true)
  out.top = G.compose(G.tilemap(m(12)), G.tiles(m(11)), pal8)
  local s9 = G.tiles(m(9))
  local fg = G.tilemap(m(10))
  if fg and fg.cells then
    local cols = math.floor((fg.width or 256) / 8)
    for i = 0, 2 do
      for r = 0, 7 do
        for c = 0, 3 do
          local k = (DIGIT_Y + r) * cols + DIGIT_X + 4 * i + c + 1
          if fg.cells[k] then fg.cells[k] = { tile = 0, flipX = false, flipY = false, palette = 0 } end
        end
      end
    end
    out.top_fg = G.compose(fg, s9, pal8)
  end
  local atlas = G.tilemap(m(7))
  if atlas and atlas.cells then
    local acols = math.floor((atlas.width or 160) / 8)
    for d = 0, 9 do
      local cells = {}
      for r = 0, 7 do
        for c = 0, 3 do
          cells[r * 4 + c + 1] = atlas.cells[(math.floor(d / 5) * 8 + r) * acols + (d % 5) * 4 + c + 1]
        end
      end
      out["digit_" .. d] = G.compose({ width = 32, height = 64, cells = cells }, s9, pal8)
    end
  end
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char }
  local SETS = { { "a", 13, 14, 15, 16 }, { "b", 17, 18, 19, 20 } }
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
  local b = p and p(9)
  if b and #b >= 120 then
    out.params = {}
    for k = 0, 29 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local s = p and p(19)
  if s and #s >= 24 then
    out.sizes = {}
    for k = 1, 3 do out.sizes[k] = { i32(s, (k - 1) * 8 + 1), i32(s, (k - 1) * 8 + 5) } end
  end
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_ring_drop/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
