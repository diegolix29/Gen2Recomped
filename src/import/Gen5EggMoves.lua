-- BLACK / WHITE'S EGG MOVES.
--
-- Platinum compiles `sEggMoves` into overlay 5 (src/import/Gen4EggMoves.lua);
-- Black / White moved them into their own archive, /a/1/2/3: one member per
-- species index, a u16 count and then that many u16 moves (Bulbasaur: 14 --
-- Skull Bash, Charm, Petal Dance ...). Empty members (index 0 and the alt
-- forms) carry no list.
--
-- Written to the same cache module, `gen4_egg_moves`, in the same
-- { [species] = { moves } } shape, so Gen4DayCare.buildMoves reads it as is.

local Gen5EggMoves = {}

Gen5EggMoves.PATH = "/a/1/2/3"

function Gen5EggMoves.parse(arc)
  local out, n = {}, 0
  for species = 1, (arc and arc.count or 0) - 1 do
    local b = arc:get(species)
    if b and #b >= 2 then
      local count = b:byte(1) + b:byte(2) * 256
      local list = {}
      for i = 1, count do
        local o = 1 + i * 2
        if o + 1 > #b then break end
        list[#list + 1] = b:byte(o) + b:byte(o + 1) * 256
      end
      if #list > 0 then out[species] = list; n = n + 1 end
    end
  end
  return out, n
end

function Gen5EggMoves.build(self)
  local bytes = self.rom and self.rom:read(Gen5EggMoves.PATH)
  if not bytes then return nil end
  local out, n = Gen5EggMoves.parse(require("src.import.NarcArchive").parse(bytes))
  return n > 0 and out or nil
end

return Gen5EggMoves
