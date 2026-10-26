-- HEARTGOLD / SOULSILVER POKeATHLON: RELAY RUN's art and tables
-- (pokeheartgold asm/overlay_96.s 0x021FC768..0x02201558, sub-app table
-- ov96_0221A8F8; see scratch_claude/athlon/NOTES.md, "## Relay Run"),
-- written as `gen4_hgss_relay_run`.
--
--   NARC 0xB2 = /a/1/7/8 (ov96_021FD060 / 02200068 / 021FD0E4 / 022000E4):
--     track        BG0 of the touch screen: screen 2 over char 1, palette 0
--                  (512 x 256: the clay track, the start line at x 80..96)
--     banner_lo    BG1: screen 3 (scrolled at half the runner's x)
--     banner_hi    BG2: screen 4 (scrolled at twice the runner's x)
--     map          the top screen's BG: screen 7 over char 6, palette 5 (the
--                  round track seen from above, centre (160, 96), radius 80)
--     laps         screen 8 (the "00.0" lap counter), digits = screen 9
--                  (160 x 128: 0-4 / 5-9, 32 x 64 each, ov96_022005B4)
--     <set>_<seq>_<frame>  the sprite sets (palette, anims, cells, char):
--                  obj 14/15/16/17 (touch screen: rocks, patches, the baton
--                  smoke, the switch button ...), top 10/11/12/13 (the map's
--                  markers and the top screen's parts)
--     objSeq[set][seq]  each sequence's frame durations
--   NARC 0xAA = /a/1/7/0 member 2: the star tables (`params`, 40 ints, eight
--     rows of five read by ov96_021FEFE8 -- see HgssPokeathlonRelayRun) and
--     member 12 (`radii`, three (w, h) pairs by the performance row's byte 6)
--   NARC 0xE5 = /a/2/2/7 members 0..9: the obstacle layouts (LCRandom % 10,
--     ov96_021FC768 case 5): `layouts[k]` = { {kind, x, y} ... } -- kind 1 / 2
--     a big rock 48 / 32 px square, 3 a rock patch 64 px square; x on the
--     1024-long lap, y the track's row + 32 (ov96_02200E80 / 021FF1E0)

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
  local m = archive(rom, "/a/1/7/8")
  local out, meta = {}, { objSeq = {} }
  if not m then return out, meta end
  local pal, sheet = G.palette(m(0), true), G.tiles(m(1))
  out.track = G.compose(G.tilemap(m(2)), sheet, pal)
  out.banner_lo = G.compose(G.tilemap(m(3)), sheet, pal)
  out.banner_hi = G.compose(G.tilemap(m(4)), sheet, pal)
  local tpal, tsheet = G.palette(m(5), true), G.tiles(m(6))
  out.map = G.compose(G.tilemap(m(7)), tsheet, tpal)
  out.laps = G.compose(G.tilemap(m(8)), tsheet, tpal)
  out.digits = G.compose(G.tilemap(m(9)), tsheet, tpal)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char }
  local SETS = { { "obj", 14, 15, 16, 17 }, { "top", 10, 11, 12, 13 } }
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
  local b = p and p(2)
  if b then
    out.params = {}
    for k = 0, 39 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local r = p and p(12)
  if r then
    out.radii = {}
    for k = 0, 2 do out.radii[k + 1] = { i32(r, k * 8 + 1), i32(r, k * 8 + 5) } end
  end
  local l = archive(rom, "/a/2/2/7")
  out.layouts = {}
  for k = 0, 9 do
    local mb = l and l(k)
    if mb then
      local list = {}
      for i = 1, #mb - 3, 4 do
        local kind = mb:byte(i)
        if kind ~= 0 then
          list[#list + 1] = { kind = kind, x = mb:byte(i + 2) + mb:byte(i + 3) * 256, y = mb:byte(i + 1) + 32 }
        end
      end
      out.layouts[k] = list
    end
  end
  return out
end

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_relay_run/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
