-- HEARTGOLD / SOULSILVER POKeATHLON: BLOCK SMASH's art and tables
-- (pokeheartgold asm/overlay_96.s, the event's code 0x02208BB8..0x0220E3F0;
-- see scratch_claude/athlon/NOTES.md "## Block Smash"), written as
-- `gen4_hgss_block_smash`.
--
--   NARC 0xEA = /a/2/3/2 (ov96_02209D14 / 02209A14 / 02209B04), LZ11 packed:
--     bottom       the touch screen's stage: char 1, screen 2, palette 0
--     top          the top screen's tally board: char 4, screen 5, palette 3
--     top_bar      the top screen's second layer (screen 6, a name bar)
--     a_<seq>_<f>  sprite set A (palette 7, char 8, cells 9, anims 10): the
--                  block (1 whole, 2 cracked, 3 crumbling), the crack mark 4,
--                  chips 5/6, the hit flash 7, the stacks 8-13, smoke 14/15,
--                  the tension auras 16 (red) / 17 (blue), the fist 18, the
--                  SWITCH button 19-23, sweat 24, the clock 25, the faint
--                  stars 26, the Poke Ball 27, rubble 28-30
--     b_<seq>_<f>  sprite set B (palette 11, char 12, cells 13, anims 14): the
--                  top screen's tally slabs per team (1-12), team flags 13-16,
--                  bench sweat 17, the Poke Ball 18
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 member 5 (ov96_0220D200 -- NOT member 3: the
--     per-event tables are not numbered by event id): `params`, 15 ints --
--     [0..4] damage per hit by POWER, [5..9] stamina by STAMINA,
--     [10..14] the crack hitbox size (0..2) by SKILL

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
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
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
  local m = archive(rom, "/a/2/3/2")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  local pal0, pal3 = G.palette(m(0), true), G.palette(m(3), true)
  out.bottom = G.compose(G.tilemap(m(2)), G.tiles(m(1)), pal0)
  local topSheet = G.tiles(m(4))
  out.top = G.compose(G.tilemap(m(5)), topSheet, pal3)
  out.top_bar = G.compose(G.tilemap(m(6)), topSheet, pal3)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char }
  local SETS = { { "a", 7, 10, 9, 8 }, { "b", 11, 14, 13, 12 } }
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
  local b = p and p(5)
  if b and #b >= 60 then
    out.params = {}
    for k = 0, 14 do out.params[k] = i32(b, k * 4 + 1) end
  end
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_block_smash/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
