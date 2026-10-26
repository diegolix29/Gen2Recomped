-- gen4_hgss_pokeathlon: the Pokeathlon course tables (see Gen4HgssPokeathlon).
local A = {}

function A.build(x)
  return require("src.import.Gen4HgssPokeathlon").courses(x.rom)
end

return A
