-- BLACK AND WHITE'S TYPE AND CATEGORY BADGES (/a/1/2/4, found by scanning
-- every archive for a cell bank of eighteen 32 x 16 cells), written as
-- `gen4_graphics.battleObjects`' `type_icons_<type>` -- the key the summary
-- and the battle screens already look up.
--
--   char 23 / cell 24 / palette 22   the eighteen types in type order,
--                                    NORMAL .. DARK, then ???
--   char 26 / cell 27 / palette 22   the categories: 0 status (grey),
--                                    1 physical (the orange burst), 2 special
--                                    (the blue rings) -- which is which BY EYE

local T = {}

T.PATH = "/a/1/2/4"
T.TYPES = { "normal", "fighting", "flying", "poison", "ground", "rock", "bug", "ghost",
            "steel", "fire", "water", "grass", "electric", "psychic", "ice", "dragon", "dark", "mystery" }
T.CATEGORIES = { [0] = "status", "physical", "special" }

function T.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(T.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local out = {}
  local pal = G.palette(m(22))
  local function set(sheetAt, bankAt, names)
    local sheet, bank = G.tiles(m(sheetAt)), Cells.parse(m(bankAt), G)
    if not (sheet and bank and pal) then return end
    for i, cell in ipairs(bank.cells) do
      local name = names[i - 1 + (names[0] and 0 or 1)]
      local pic = name and Cells.assemble(cell, sheet, pal, bank, G)
      if pic then
        local entry = x:saveImage("battle/type_icons/" .. name, pic)
        if entry then out["type_icons_" .. name] = entry end
      end
    end
  end
  set(23, 24, T.TYPES)
  set(26, 27, T.CATEGORIES)
  return out
end

return T
