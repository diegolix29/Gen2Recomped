-- HEARTGOLD / SOULSILVER POKeATHLON: HURDLE DASH's art and tables
-- (pokeheartgold asm/overlay_96.s 0x021F94A8..0x021FC758; see
-- scratch_claude/athlon/NOTES.md), written as `gen4_hgss_hurdle_dash`.
--
--   NARC 0x9C = /a/1/5/6 (ov96_021FA020 / 021FC320):
--     lane_<1..3>   screens 2 / 3 / 4 over char 1, palette 0: a 256 x 512
--                   strip each, the lane at x 16..88, scrolled per lane
--     finish        screen 5 (256 x 256), the line's strip
--     <set>_<seq>_<frame>  the sprite sets (palette, anims, cells, char):
--                   hurdle 6/7/8/9, knock 6/10/11/12, dust 13-16, boost 17-20
--                   (blue / red tunnel), obj 21-24 (numbered boxes, team
--                   shadows 12-15, rank digits), place 25-28, clock 29-32
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 member 0: the star tables (`params`, 20 ints: by
--     JUMP rise frames, by JUMP hang frames, by SKILL accel x100, by SPEED top
--     speed x10)
--   NARC 0xE4 = /a/2/2/6 members 0..2: the three courses, `layouts[k][lane]`
--     = the hurdle cells (distance / 8) of that lane

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

function A.images(rom)
  local m = archive(rom, "/a/1/5/6")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  local pal, sheet = G.palette(m(0), true), G.tiles(m(1))
  for lane = 1, 3 do out["lane_" .. lane] = G.compose(G.tilemap(m(lane + 1)), sheet, pal) end
  out.finish = G.compose(G.tilemap(m(5)), sheet, pal)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- the archive's sprite sets { key, palette, anims, cells, char }:
  -- hurdle (standing / knocked), dust, the boost tunnel, the generic course
  -- set (numbered boxes, team shadows, rank digits), places, the clock
  local SETS = { { "hurdle", 6, 7, 8, 9 }, { "knock", 6, 10, 11, 12 }, { "dust", 13, 14, 15, 16 },
    { "boost", 17, 18, 19, 20 }, { "obj", 21, 22, 23, 24 }, { "place", 25, 26, 27, 28 },
    { "clock", 29, 30, 31, 32 } }
  for _, set in ipairs(SETS) do
    local key = set[1]
    local opal, osheet = G.palette(m(set[2]), true), G.tiles(m(set[5]))
    local bank, anim = Cells.parse(m(set[4]), G), CA.parse(m(set[3]), G)
    if opal and osheet and bank and anim then
      meta.objSeq[key] = {}
      for q = 0, #anim.sequences - 1 do
        local frames = CA.frames(anim, q) or {}
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
  local b = p and p(0)
  if b then
    out.params = {}
    for k = 0, 19 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local l = archive(rom, "/a/2/2/6")
  out.layouts = {}
  for k = 0, 2 do
    local mb = l and l(k)
    if mb then
      local lanes = {}
      for lane = 0, 2 do
        local cells = {}
        for i = 0, 511 do
          local v = mb:byte(lane * 512 + i + 1)
          if v and v ~= 0 then cells[#cells + 1] = i end
        end
        lanes[lane] = cells
      end
      out.layouts[k] = lanes
    end
  end
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_hurdle_dash/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
