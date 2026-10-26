-- HEARTGOLD / SOULSILVER POKeATHLON: the course's shared event sprites,
-- written as `gen4_hgss_athlon_common` (src/ui/HgssPokeathlonCountdown.lua).
--
-- NARC 0x99 = /a/1/5/3 (the shared loader ov96_021E9D10, resource ids 20..33,
-- palettes 23 / 24 = members 0 / 10):
--   count_<seq>_<f>  resource 20 (char 3, cells 2, anims 1): seq 0 "3",
--                    1 "2", 2 "1", 3 "FINISH" -- the 3-2-1 and the finish
--   record_<seq>_<f> resource 27 (char 19, cells 18, anims 17): NEW RECORD!
--   objSeq[set][seq] each sequence's frame durations

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")

local A = {}

A.SETS = { { "count", 3, 2, 1 }, { "record", 19, 18, 17 } }

function A.images(rom)
  local raw = rom:read("/a/1/5/3")
  local arc = raw and N.parse(raw)
  local out, meta = {}, { objSeq = {} }
  if not arc then return out, meta end
  local function m(i)
    local b = arc:get(i)
    return b and (G.isCompressed(b) and G.decompress(b) or b)
  end
  local Cells = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  local pal = G.palette(m(0), true)
  for _, set in ipairs(A.SETS) do
    local key = set[1]
    local sheet, bank, anim = G.tiles(m(set[2])), Cells.parse(m(set[3]), G), CA.parse(m(set[4]), G)
    if pal and sheet and bank and anim then
      meta.objSeq[key] = {}
      for q = 0, #anim.sequences - 1 do
        local list = {}
        for f, fr in ipairs(CA.frames(anim, q) or {}) do
          local cell = bank.cells[(fr.cell or 0) + 1]
          local pic = cell and Cells.assemble(cell, sheet, pal, bank, G)
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

function A.build(x)
  local out = {}
  local images, meta = A.images(x.rom)
  for name, img in pairs(images) do
    out[name] = x:saveImage("hgss_athlon_common/" .. name, img, { originX = img.originX, originY = img.originY })
  end
  out.objSeq = meta.objSeq
  return out
end

return A
