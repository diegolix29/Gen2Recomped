-- FireRed battle-healthbox gender regression: the cartridge suppresses the
-- appended symbol only for an UNNICKNAMED Nidoran♀/♂.  v0.7.77 accidentally
-- imported {71, 1} from Thumb instruction bytes, making species 1 (Bulbasaur)
-- look like a Nidoran and hiding its gender mark.
--   luajit tests/engine/frlg_battle_gender.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Extractor = require("src.import.RomExtractorGen3")
local Gen3Battle = require("src.battle.Gen3Battle")

-- Import-side guard: a FireRed manifest must not read NICK_FN+4E/+52 at all;
-- those are code bytes in this cartridge, not literal species constants.
local fr = setmetatable({ isFireRedManifest = function() return true end },
                        { __index = Extractor })
local noReadRom = { u16 = function()
  error("FireRed must not read Hoenn Nidoran literal offsets")
end }
local named = Extractor.healthboxNamedSpecies(fr, noReadRom)
T.eq(named[1], 29, "FireRed default-name exception starts at Nidoran female")
T.eq(named[2], 32, "FireRed default-name exception ends at Nidoran male")
T.eq(named[1] == 1 or named[2] == 1, false,
  "Bulbasaur is never in the default-name exception")

-- The renderer consumes the imported ids against speciesOrder.  Exercise the
-- actual helper with real Gen 3 gender derivation, including renamed Nidoran.
local data = {
  pokemon = {
    BULBASAUR = { genderRatio = 31 },
    NIDORAN = { genderRatio = 254 },
    NIDORAN_032 = { genderRatio = 0 },
  },
  constants = {
    speciesOrder = { [1] = "BULBASAUR", [29] = "NIDORAN",
                     [32] = "NIDORAN_032" },
  },
}
local record = {
  text = { shadow = { 115, 115, 115 } },
  gender = {
    male = { text = "♂", color = { 65, 205, 255 } },
    female = { text = "♀", color = { 255, 156, 148 } },
    namedSpecies = named,
  },
}
local battle = { data = data }
local function symbol(species, personality, nickname)
  return Gen3Battle.genderSymbol(record, battle, {
    mon = { species = species, personality = personality, nickname = nickname },
  })
end

T.eq(symbol("BULBASAUR", 0), "♀",
  "ordinary female Bulbasaur keeps its appended gender symbol")
T.eq(symbol("BULBASAUR", 255), "♂",
  "ordinary male Bulbasaur keeps its appended gender symbol")
T.eq(symbol("NIDORAN", 0), nil,
  "default-name Nidoran female does not get a duplicate symbol")
T.eq(symbol("NIDORAN_032", 255), nil,
  "default-name Nidoran male does not get a duplicate symbol")
T.eq(symbol("NIDORAN", 0, "QUEEN"), "♀",
  "renamed Nidoran female gets the normal appended symbol again")
T.eq(symbol("NIDORAN_032", 255, "KING"), "♂",
  "renamed Nidoran male gets the normal appended symbol again")

T.finish("frlg battle gender")
