-- BLACK AND WHITE'S POKEMON SUMMARY (/a/0/7/8, the same in both games;
-- bw_ui_map.md section 7), written as `gen5_summary_art`. No symbols: the
-- pairings were found by composing every combination, checked against
-- Bulbapedia's captures of the cartridge.
--
--   grid          screen 62 on char 12, palette 0: the grid paper behind all
--   info          screen 63 on char 8, palette 0: the touch info page (the
--                 info grid, the Pokemon's panel, the item box, the EXP bar)
--   skills        screen 66 on char 8, palette 0: the touch moves page's ground
--   memo          screen 64 on char 10, palette 0: the top's lined memo panel
--   stats         screen 67 on char 10, palette 0: the top's dark diagonal
--   header_info   screen 65 on char 9, palette 1: POKeMON INFO <<STATUS>>
--   header_ribbons screen 69 on char 9, palette 1
--   stats_page / moves_page   73 / 74 on char 10: the SKILLS top, its move details
--   header_stats / header_moves   75 / 76 on char 9: <<STATS>> / <<BATTLE MOVES>>
--   capsule_<c>   OBJ char 15 / cell 81 in palette 5: the move capsule
--   cursor        OBJ char 14 / cell 80 cell 0 in palette 3: the red outline

local A = {}

A.PATH = "/a/0/7/8"

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local index = { _source = "ROM:/a/0/7/8 (62 on 12, 63/66 on 8, 64/67 on 10, 65/69 on 9; capsules 15/81 p5, cursor 14/80 p3)" }
  local function save(key, image, extra)
    local entry = image and x:saveImage("bw_summary/" .. key, image, extra)
    if entry then index[key] = entry end
  end
  local function bg(key, s, c, p)
    local map, sheet = G.tilemap(m(s)), G.tiles(m(c))
    local pal = G.palette(m(p))
    local img = map and sheet and pal and G.compose(map, sheet, pal)
    if img and img.height > 192 then img = { width = img.width, height = 192, rgba = img.rgba:sub(1, img.width * 192 * 4) } end
    save(key, img)
  end
  bg("grid", 62, 12, 0)
  bg("info", 63, 8, 0)
  bg("skills", 66, 8, 0)
  bg("memo", 64, 10, 0)
  bg("stats", 67, 10, 0)
  bg("header_info", 65, 9, 1)
  bg("header_ribbons", 69, 9, 1)
  -- the SKILLS top (73) and its move-detail page (74) on char 10, and their
  -- title strips <<STATS>> (75) and <<BATTLE MOVES>> (76) on char 9
  bg("stats_page", 73, 10, 0)
  bg("moves_page", 74, 10, 0)
  bg("header_stats", 75, 9, 1)
  bg("header_moves", 76, 9, 1)
  local function obj(prefix, c, b, p, only)
    local sheet, bank = G.tiles(m(c)), Cells.parse(m(b), G)
    local pal = G.palette(m(p))
    if not (sheet and bank and pal) then return end
    for i, cell in ipairs(bank.cells) do
      if not only or only[i - 1] then
        local pic = Cells.assemble(cell, sheet, pal, bank, G)
        if pic then
          local ox, oy = Cells.extent(cell)
          save(("%s_%d"):format(prefix, i - 1), pic, { originX = ox, originY = oy })
        end
      end
    end
  end
  obj("capsule", 15, 81, 5, { [0] = true, [15] = true })
  obj("cursor", 14, 80, 3, { [0] = true })
  return index
end

return A
