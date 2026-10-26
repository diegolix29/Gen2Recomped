-- HEARTGOLD / SOULSILVER POKeATHLON: GOAL ROLL's art and tables
-- (pokeheartgold asm/overlay_96.s, the event's code 0x02210C98..0x02215710,
-- event 9, sub-app ov96_0221A81C; see scratch_claude/athlon/NOTES.md
-- "## Goal Roll"), written as `gen4_hgss_goal_roll`.
--
--   NARC 0xEC = /a/2/3/4 (ov96_02211A24 / 022146C0 / 0221362C):
--     field        the touch screen's pitch: screen 2 over char 1, palette 0
--                  (BG1 of the main engine -- the display is swapped, the main
--                  engine is the touch screen)
--     field_b      screen 4 over char 3, palette 0 (BG2)
--     top, top_b   the top screen: screens 8 / 9 over chars 6 / 7, palette 5
--                  (BG5 / BG6)
--     digits       screen 10 over char 7: the score's digit glyphs (4 x 8
--                  tiles each, five a row -- ov96_0221497C)
--     <set>_<seq>_<frame>  sprite sets (palette, anims, cells, char):
--                  obj 15/16/17/18 (the pitch's: ov96_02210C98 case 2, res
--                  0x65), top 11/12/13/14 (the top screen's, res 0x66)
--     objSeq[set][seq]  each sequence's frame durations; objXY[set][seq][f]
--                  the frame's translation where the animation has one (the
--                  GOAL! banners 17 / 18 slide in and out)
--   NARC 0xAA = /a/1/7/0 member 8 (ov96_02210C98 case 4 -> ov96_0221359C --
--     NOT member 9): `params`, 30 ints read by the stars (course record bytes
--     POWER SPEED JUMP STAMINA SKILL):
--     [0..4]   by SKILL: the Power Shot's cone, degrees either side (+0x6C)
--     [5..9]   by SKILL: read into +0x6E, never used by the event
--     [10..14] by STAMINA: stamina (+0x70 max, +0x71 now)
--     [15..19] by SPEED: walking speed x10 (+0x64)
--     [20..24] by SPEED: dash speed x10 (+0x68)
--     [25..29] by POWER: what a Power Shot takes off a Pokemon's stamina (+0x72)
--   NARC 0xAA member 11: `sizes`, by the performance row's size class (byte 6,
--     1..3 -- ov96_021E6138): { sprite y offset, body radius } (021EAF70)

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local A = {}

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

function A.images(rom)
  local m = archive(rom, "/a/2/3/4")
  local out, meta = {}, { objSeq = {}, objXY = {} }
  if not m then return out, meta end
  local pal = G.palette(m(0), true)
  out.field = G.compose(G.tilemap(m(2)), G.tiles(m(1)), pal)
  out.field_b = G.compose(G.tilemap(m(4)), G.tiles(m(3)), pal)
  local tpal = G.palette(m(5), true)
  local s6, s7 = G.tiles(m(6)), G.tiles(m(7))
  out.top = G.compose(G.tilemap(m(8)), s6, tpal)
  out.top_b = G.compose(G.tilemap(m(9)), s7, tpal)
  out.digits = G.compose(G.tilemap(m(10)), s7, tpal)
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  -- { key, palette, anims, cells, char }
  local SETS = { { "obj", 15, 16, 17, 18 }, { "top", 11, 12, 13, 14 } }
  for _, set in ipairs(SETS) do
    local key = set[1]
    local opal, osheet = G.palette(m(set[2]), true), G.tiles(m(set[5]))
    local bank, an = Cells.parse(m(set[4]), G), CA.parse(m(set[3]), G)
    if opal and osheet and bank and an then
      meta.objSeq[key], meta.objXY[key] = {}, {}
      for q = 0, #an.sequences - 1 do
        local list, xy = {}, nil
        for f, fr in ipairs(CA.frames(an, q) or {}) do
          local cell = bank.cells[(fr.cell or 0) + 1]
          local pic = cell and Cells.assemble(cell, osheet, opal, bank, G)
          if pic then
            pic.originX, pic.originY = Cells.extent(cell)
            out[("%s_%d_%d"):format(key, q, f - 1)] = pic
          end
          list[f] = fr.duration or 1
          if fr.x or fr.y then
            xy = xy or {}
            xy[f] = { tonumber(fr.x) or 0, tonumber(fr.y) or 0 }
          end
        end
        meta.objSeq[key][q] = list
        meta.objXY[key][q] = xy
      end
    end
  end
  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out, meta
end

function A.tables(rom)
  local out = {}
  local p = archive(rom, "/a/1/7/0")
  local b = p and p(8)
  if b and #b >= 120 then
    out.params = {}
    for k = 0, 29 do out.params[k] = i32(b, k * 4 + 1) end
  end
  local s = p and p(11)
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
    out[name] = x:saveImage("hgss_goal_roll/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  out.objXY = meta.objXY
  for k, v in pairs(A.tables(x.rom)) do out[k] = v end
  return out
end

return A
