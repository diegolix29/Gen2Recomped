-- HEARTGOLD / SOULSILVER POKeATHLON: DISC CATCH's art and tables
-- (pokeheartgold asm/overlay_96.s, the event's code 0x0220D360..0x02210C98,
-- event 4, sub-app ov96_0221A8A8; the reading is written up in
-- scratch_claude/athlon/NOTES.md, "## Disc Catch"), written as
-- `gen4_hgss_disc_catch`.
--
--   NARC 0xED = /a/2/3/5 (LZ11 packed but the palettes; ov96_0220EE8C /
--   0220EFD0 / 0220EB3C):
--     water_<k>    the touch screen's BG0: screen 5 + k (k = 0..5) over char
--                  4, palette 0 -- the sea, one screen every 4 frames
--                  (0220EFD0 cycles 5..10 into BG0 and BG4)
--     pier         the touch screen's BG1: screen 1 over char 2, palette 0
--                  (scrolled 8 px down, ScheduleSetBgPosText(1, 4, 8))
--     top_water_<k> the top screen's BG4: the same screens over char 4 with
--                  the sub palette (member 3)
--     top_back     BG5: screen 12 over char 11
--     top_front    BG6: screen 13 over char 11 (the score's place, "999")
--     digits       screen 14 over char 11: the score glyphs (0221058C)
--     <set>_<seq>_<frame>  the sprite sets (palette, anims, cells, char):
--                  a = 19/20/21/22 (0x2710, the touch screen's), b = 23/24/
--                  25/26 (0x2711, the top screen's), c = 15/16/17/18
--                  (0x2712 / 0x2713, loaded on both screens)
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 MEMBER 7 (the literal ReadWholeNarcMemberByIdPair(
--     0xAA, 7) in ov96_0220F280 -- not 4): `params`, 20 ints read per Pokemon
--     from its course record (POWER SPEED JUMP STAMINA SKILL):
--     [JUMP] -> half the jump's frames (5 6 7 9 15), [5 + JUMP] -> the jump
--     arc's height x 10 (4 4 3 3 1), [10 + POWER] / 10 -> bump power (4.0 ..
--     6.0), [15 + SPEED] / 10 -> walk px a frame (2.4 .. 7.2).
--     MEMBER 17 (0220F4A0): `sizes` = { yoff, radius } by the performance
--     row's byte 6 (size class 1..3): 8/8, 10/10, 12/14.
--   Overlay data, written out as tables: `spawns` (ov96_0221CFBC: each
--   team's three spots on the touch screen, by team colour / order),
--   `phases` (ov96_0221CF1C: the seconds-left thresholds 55 / 40 / 20 / 0),
--   `aiRows` (ov96_0221D1B0: per slot { first row, rows } in 8-px rows),
--   `aiJump` (ov96_0221D1B8: per slot the % a frame to jump at a near disc).

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")
local Lz = require("src.import.Gen5Lz")

local A = {}

-- ov96_0221CFBC: team t's three spots (screen x, y), team 0 = the player's
A.SPAWNS = {
  [0] = { { 40, 40 }, { 40, 88 }, { 40, 152 } },
  { { 96, 40 }, { 96, 88 }, { 96, 152 } },
  { { 160, 40 }, { 160, 88 }, { 160, 152 } },
  { { 216, 40 }, { 216, 88 }, { 216, 152 } },
}
-- ov96_0221CF1C: phase k while seconds left >= PHASES[k]
A.PHASES = { [0] = 55, 40, 20, 0 }
-- ov96_0221D1B0 / 0221D1B1: per slot { first 8-px row, rows } of its home
A.AI_ROWS = { [0] = { 3, 5 }, { 7, 6 }, { 15, 6 } }
-- ov96_0221D1B8: per slot, % a frame to jump at a disc within 16 px
A.AI_JUMP = { [0] = 3, 6, 36 }

local function archive(rom, path)
  local raw = rom:read(path)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  return function(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b)
    elseif b and G.isCompressed and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end, arc
end

local function i32(b, i)
  local a, b2, c, d = b:byte(i, i + 3)
  local v = a + b2 * 256 + c * 65536 + d * 16777216
  if v >= 2 ^ 31 then v = v - 2 ^ 32 end
  return v
end

function A.images(rom)
  local m = archive(rom, "/a/2/3/5")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  local pal0, pal3 = G.palette(m(0), true), G.palette(m(3), true)
  local water = G.tiles(m(4))
  for k = 0, 5 do
    local map = G.tilemap(m(5 + k))
    out["water_" .. k] = G.compose(map, water, pal0)
    out["top_water_" .. k] = G.compose(map, water, pal3)
  end
  out.pier = G.compose(G.tilemap(m(1)), G.tiles(m(2)), pal0)
  local top = G.tiles(m(11))
  out.top_back = G.compose(G.tilemap(m(12)), top, pal3)
  out.top_front = G.compose(G.tilemap(m(13)), top, pal3)
  -- screen 14: the score glyphs, 5 a row, 4 x 8 tiles each (ov96_0221058C
  -- copies digit d from tile ((d % 5) 4, (d / 5) 8) to BG6 tile (4 i, 0))
  out.digits = G.compose(G.tilemap(m(14)), top, pal3)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char } (ov96_0220EB3C)
  local SETS = { { "a", 19, 20, 21, 22 }, { "b", 23, 24, 25, 26 }, { "c", 15, 16, 17, 18 } }
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
  local b = p and p(7)
  if b and #b >= 80 then
    out.params = {}
    for k = 0, 19 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local s = p and p(17)
  if s and #s >= 24 then
    out.sizes = {}
    for c = 1, 3 do out.sizes[c] = { i32(s, (c - 1) * 8 + 1), i32(s, (c - 1) * 8 + 5) } end
  end
  out.spawns = A.SPAWNS
  out.phases = A.PHASES
  out.aiRows = A.AI_ROWS
  out.aiJump = A.AI_JUMP
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_disc_catch/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
