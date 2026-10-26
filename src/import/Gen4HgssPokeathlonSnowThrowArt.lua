-- HEARTGOLD / SOULSILVER POKeATHLON: SNOW THROW's art and tables
-- (pokeheartgold asm/overlay_96.s 0x02201558..0x022047EC, event 8, sub-app
-- ov96_0221A858; the reading is written up in scratch_claude/athlon/NOTES.md,
-- "## Snow Throw"), written as `gen4_hgss_snow_throw`.
--
--   NARC 0xDB = /a/2/1/7 (uncompressed; ov96_02201E10 / 02203A64 /
--   02201E70 / 02203B44):
--     field        the top screen (main engine after GfGfx_SwapDisplay):
--                  BG1 = screen 2 over char 1, palette 0 (the snowfield in
--                  perspective, the three rival teams round its far edges)
--     panel_back   the touch screen's BG7: screen 6 over char 4
--     panel_mid    BG6: screen 7 over char 5
--     panel_front  BG5: screen 8 over char 5 (all with palette 3, four rows)
--     digits       screen 9 over char 5: the score glyphs, 5 a row, 4 x 8
--                  tiles each (ov96_02203BD0 copies them to BG5 tile x
--                  19 / 23 / 27, y 16)
--     emblem_<t>   the 4 x 4-tile team emblem screen 9 holds at tile (4 t,
--                  16), copied to BG5 tile (0, 18) by 02203A64 (t = the
--                  player's participant index)
--     <set>_<seq>_<frame>  the sprite sets (palette, anims, cells, char):
--                  a = 14/15/16/17 (id 0x69), b = 10/11/12/13 (0x65, the
--                  touch screen's: the three Pokemon frames + their sweat),
--                  c = 18/19/20/21 (0x6A, the field's: ball, shadow, burst)
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 MEMBER 3 (the literal ReadWholeNarcMemberByIdPair(
--     0xAA, 3) in ov96_02201558 -- not 8): 20 ints, read per Pokemon by
--     ov96_0220329C from its course record (POWER SPEED JUMP STAMINA SKILL):
--     [SKILL] / 10 -> +4 throw skill (16 14 12 11 10), [5 + POWER] / 10 ->
--     +8 throw power (10 11 12 14 16), [10 + SKILL] -> +0x10 aim spread in
--     degrees (6 4 3 2 0), [15 + STAMINA] -> +0xC fatigue taken (3 2 2 2 1).
--   The arena is overlay data, written out as `spots` (ov96_0221C98C: the
--   twelve Pokemon's world points, x / z in 0..66), `walkers` (ov96_0221C8C8 /
--   0221C8EC: the nine rival walkers' feet on the top screen, in order from
--   the next team) and `faces` (ov96_0221C7D0: their facing by team).

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local A = {}

-- ov96_0221C98C (= ov96_0221CA30): { x, z } world points of mon 0..11 (team
-- t = mon / 3: 0 near side, 1 right, 2 far, 3 left); the arena is 66 x 66
-- round (33, 33), balls live in 1..64
A.SPOTS = {
  [0] = { 25, 61 }, { 33, 61 }, { 41, 61 },
  { 61, 41 }, { 61, 33 }, { 61, 25 },
  { 41, 5 }, { 33, 5 }, { 25, 5 },
  { 5, 25 }, { 5, 33 }, { 5, 41 },
}

-- ov96_0221C8C8 / ov96_0221C8EC: walker k (0..8) = mon ((me + 1) * 3 + k) % 12,
-- feet on the top screen (the sprite goes 25 px up, 40 for a tall one --
-- ov96_02201558 case 4 with 021E8BB0's flag); ov96_0221CA1C = draw order
A.WALKERS = {
  [0] = { 246, 170 }, { 248, 130 }, { 249, 100 },
  { 199, 70 }, { 175, 70 }, { 150, 70 },
  { 82, 100 }, { 63, 130 }, { 37, 170 },
}
A.WALKER_PRIORITY = { [0] = 0, 2, 4, 6, 7, 8, 5, 3, 1 }
-- ov96_0221C7D0: the walkers' direction by rival team (021EAC0C: 3 left,
-- 2 down, 4 right)
A.FACES = { "left", "down", "right" }

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

-- a w x h tile window of a tilemap (cells in row order, `width` tiles wide)
local function cut(map, x0, y0, w, h)
  if not (map and map.cells) then return nil end
  local mw = math.floor((map.width or 256) / 8)
  local cells = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local c = map.cells[(y0 + y) * mw + (x0 + x) + 1]
      cells[#cells + 1] = c or { tile = 0, palette = 0 }
    end
  end
  local out = {}
  for k, v in pairs(map) do out[k] = v end
  out.cells, out.width, out.height = cells, w * 8, h * 8
  return out
end

function A.images(rom)
  local m = archive(rom, "/a/2/1/7")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  -- top: palette 0 (one row) at slot 0 (ov96_02201E10)
  local topPal = {}
  place(topPal, G.palette(m(0), true), 0, 1)
  fill(topPal)
  out.field = G.compose(G.tilemap(m(2)), G.tiles(m(1)), topPal)
  -- touch screen: palette 3, four rows (02203A64)
  local subPal = {}
  place(subPal, G.palette(m(3), true), 0, 4)
  fill(subPal)
  local sheet5 = G.tiles(m(5))
  out.panel_back = G.compose(G.tilemap(m(6)), G.tiles(m(4)), subPal)
  out.panel_mid = G.compose(G.tilemap(m(7)), sheet5, subPal)
  out.panel_front = G.compose(G.tilemap(m(8)), sheet5, subPal)
  local glyphs = G.tilemap(m(9))
  out.digits = G.compose(glyphs, sheet5, subPal)
  local ok, err = pcall(function()
    for t = 0, 3 do
      local e = cut(glyphs, 4 * t, 16, 4, 4)
      if e then out["emblem_" .. t] = G.compose(e, sheet5, subPal) end
    end
  end)
  if not ok then meta.emblemError = err end
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char } (ov96_02201E70 / 02203B44)
  local SETS = { { "a", 14, 15, 16, 17 }, { "b", 10, 11, 12, 13 }, { "c", 18, 19, 20, 21 } }
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
  local b = p and p(3)
  if b and #b >= 80 then
    out.params = {}
    for k = 0, 19 do out.params[k] = i32(b, k * 4 + 1) end
  end
  out.spots = A.SPOTS
  out.walkers = A.WALKERS
  out.walkerPriority = A.WALKER_PRIORITY
  out.faces = A.FACES
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_snow_throw/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
