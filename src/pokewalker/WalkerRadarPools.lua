-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKE RADAR'S WIDER POOL, per game.
--
-- The original Pokewalker's radar only ever turned up the course's three drawn
-- encounters. This port's radar keeps those (they are still the likeliest
-- single finds) and adds the walking Pokemon's OWN game's wild Pokemon, and,
-- rarely, that game's legendaries:
--
--   * THE WILD POOL comes from the imported game's own encounter tables
--     (`<dataDir>/<version>/data/generated/encounters.lua`, every slot of every
--     map: species and the levels it appears at), boiled down once per game to
--     `pokewalker_radar_<version>.lua` in the save directory. Without an import
--     a curated table per game stands in. Either way only species the game's
--     dex holds (Kanto 151, Johto 251, Hoenn 386, Sinnoh 493, Unova 649) and
--     never a legendary (catch rate 3 or below) -- those come only as below.
--   * PROGRESS GATES IT: a species is in reach once its lowest wild level is at
--     or under the course's top level plus one level per 250 walk steps
--     (W.walkSteps: steps and the non-step watts' bonus steps), so a fresh walk
--     on Refreshing Field finds Pidgey-and-friends and a long one finds more.
--   * LEGENDARIES: that game's own, about 1.2% of searches once the walk has
--     1000 steps, rising 0.1% per 1000 steps to 2.2%. High level, more HP
--     bars, harder to catch (Walker.battleTurn). Mythicals are rarer still.
--   * SHINY: 1 in 512 of any radar find, from Gold / Silver on (Kanto has no
--     shinies). The game makes it shiny its own way (WalkerInbox).

local R = {}

R.LEGEND_MIN_STEPS = 1000
R.LEGEND_BASE = 12        -- per mille, at LEGEND_MIN_STEPS
R.LEGEND_PER_1K = 1       -- per mille more each 1000 steps past that
R.LEGEND_MAX = 22         -- per mille
R.SHINY_ODDS = 512
R.COURSE_SHARE = 45       -- percent of ordinary finds that are the course's own
R.STEPS_PER_LEVEL = 250   -- walk steps per level of reach
R.MAX_REACH = 45          -- levels of reach above the course's top
R.MIN_POOL = 6            -- always at least this many wild species in reach
R.CACHE = "pokewalker_radar_%s.lua"

R.FAMILY = {
  red = "kanto", blue = "kanto", yellow = "kanto", green = "kanto",
  gold = "johto", silver = "johto", crystal = "johto", prism = "johto", polishedcrystal = "johto",
  ruby = "hoenn", sapphire = "hoenn", emerald = "hoenn",
  firered = "frlg", leafgreen = "frlg",
  diamond = "sinnoh", pearl = "sinnoh", platinum = "sinnoh",
  heartgold = "hgss", soulsilver = "hgss",
  black = "unova", white = "unova", black2 = "unova", white2 = "unova",
}
R.BY_GEN = { [1] = "kanto", [2] = "johto", [3] = "hoenn", [4] = "sinnoh", [5] = "unova" }

-- ------------------------------------------------- curated wild Pokemon
-- { national dex, name, lowest wild level }

local KANTO = {
  { 16, "Pidgey", 2 }, { 19, "Rattata", 2 }, { 10, "Caterpie", 3 }, { 13, "Weedle", 3 },
  { 21, "Spearow", 3 }, { 29, "Nidoran♀", 2 }, { 32, "Nidoran♂", 2 }, { 39, "Jigglypuff", 3 },
  { 25, "Pikachu", 3 }, { 56, "Mankey", 3 }, { 23, "Ekans", 6 }, { 27, "Sandshrew", 6 },
  { 41, "Zubat", 6 }, { 74, "Geodude", 7 }, { 46, "Paras", 8 }, { 35, "Clefairy", 8 },
  { 63, "Abra", 7 }, { 96, "Drowzee", 9 }, { 52, "Meowth", 10 }, { 43, "Oddish", 12 },
  { 69, "Bellsprout", 12 }, { 48, "Venonat", 13 }, { 100, "Voltorb", 14 }, { 95, "Onix", 13 },
  { 66, "Machop", 15 }, { 54, "Psyduck", 15 }, { 60, "Poliwag", 15 }, { 118, "Goldeen", 15 },
  { 129, "Magikarp", 5 }, { 72, "Tentacool", 5 }, { 98, "Krabby", 15 }, { 116, "Horsea", 15 },
  { 90, "Shellder", 15 }, { 120, "Staryu", 15 }, { 58, "Growlithe", 15 }, { 37, "Vulpix", 18 },
  { 92, "Gastly", 18 }, { 84, "Doduo", 18 }, { 17, "Pidgeotto", 17 }, { 20, "Raticate", 20 },
  { 22, "Fearow", 20 }, { 104, "Cubone", 20 }, { 64, "Kadabra", 20 }, { 81, "Magnemite", 21 },
  { 128, "Tauros", 21 }, { 42, "Golbat", 22 }, { 88, "Grimer", 23 }, { 132, "Ditto", 23 },
  { 147, "Dratini", 22 }, { 102, "Exeggcute", 24 }, { 111, "Rhyhorn", 25 }, { 115, "Kangaskhan", 25 },
  { 123, "Scyther", 25 }, { 127, "Pinsir", 25 }, { 93, "Haunter", 25 }, { 75, "Graveler", 25 },
  { 113, "Chansey", 26 }, { 77, "Ponyta", 28 }, { 79, "Slowpoke", 28 }, { 85, "Dodrio", 29 },
  { 109, "Koffing", 30 }, { 86, "Seel", 30 }, { 49, "Venomoth", 30 }, { 47, "Parasect", 30 },
  { 57, "Primeape", 30 }, { 148, "Dragonair", 30 }, { 125, "Electabuzz", 33 }, { 126, "Magmar", 34 },
}

local JOHTO = {
  { 161, "Sentret", 2 }, { 163, "Hoothoot", 2 }, { 16, "Pidgey", 2 }, { 19, "Rattata", 2 },
  { 206, "Dunsparce", 2 }, { 165, "Ledyba", 3 }, { 167, "Spinarak", 3 }, { 179, "Mareep", 3 },
  { 10, "Caterpie", 3 }, { 13, "Weedle", 3 }, { 194, "Wooper", 4 }, { 191, "Sunkern", 4 },
  { 74, "Geodude", 4 }, { 41, "Zubat", 4 }, { 187, "Hoppip", 5 }, { 69, "Bellsprout", 5 },
  { 60, "Poliwag", 5 }, { 79, "Slowpoke", 5 }, { 129, "Magikarp", 5 }, { 72, "Tentacool", 5 },
  { 95, "Onix", 6 }, { 23, "Ekans", 6 }, { 183, "Marill", 6 }, { 21, "Spearow", 8 },
  { 190, "Aipom", 10 }, { 204, "Pineco", 10 }, { 214, "Heracross", 10 }, { 209, "Snubbull", 10 },
  { 63, "Abra", 10 }, { 96, "Drowzee", 10 }, { 39, "Jigglypuff", 10 }, { 177, "Natu", 12 },
  { 193, "Yanma", 12 }, { 234, "Stantler", 12 }, { 92, "Gastly", 12 }, { 203, "Girafarig", 15 },
  { 200, "Misdreavus", 15 }, { 198, "Murkrow", 15 }, { 170, "Chinchou", 15 }, { 246, "Larvitar", 15 },
  { 147, "Dratini", 15 }, { 213, "Shuckle", 15 }, { 202, "Wobbuffet", 15 }, { 162, "Furret", 15 },
  { 180, "Flaaffy", 15 }, { 84, "Doduo", 15 }, { 58, "Growlithe", 15 }, { 37, "Vulpix", 15 },
  { 207, "Gligar", 20 }, { 216, "Teddiursa", 20 }, { 231, "Phanpy", 20 }, { 228, "Houndour", 20 },
  { 215, "Sneasel", 20 }, { 220, "Swinub", 20 }, { 225, "Delibird", 20 }, { 211, "Qwilfish", 20 },
  { 222, "Corsola", 20 }, { 223, "Remoraid", 20 }, { 241, "Miltank", 20 }, { 128, "Tauros", 20 },
  { 235, "Smeargle", 20 }, { 185, "Sudowoodo", 20 }, { 195, "Quagsire", 20 }, { 164, "Noctowl", 20 },
  { 226, "Mantine", 20 }, { 77, "Ponyta", 20 }, { 227, "Skarmory", 25 }, { 217, "Ursaring", 25 },
  { 232, "Donphan", 30 }, { 229, "Houndoom", 30 }, { 148, "Dragonair", 30 },
}

local HOENN = {
  { 261, "Poochyena", 2 }, { 263, "Zigzagoon", 2 }, { 265, "Wurmple", 2 }, { 270, "Lotad", 3 },
  { 273, "Seedot", 3 }, { 283, "Surskit", 3 }, { 276, "Taillow", 4 }, { 278, "Wingull", 4 },
  { 280, "Ralts", 4 }, { 300, "Skitty", 4 }, { 285, "Shroomish", 5 }, { 287, "Slakoth", 5 },
  { 290, "Nincada", 5 }, { 293, "Whismur", 5 }, { 41, "Zubat", 5 }, { 72, "Tentacool", 5 },
  { 129, "Magikarp", 5 }, { 296, "Makuhita", 6 }, { 304, "Aron", 6 }, { 302, "Sableye", 6 },
  { 303, "Mawile", 6 }, { 74, "Geodude", 6 }, { 183, "Marill", 10 }, { 309, "Electrike", 12 },
  { 311, "Plusle", 12 }, { 312, "Minun", 12 }, { 316, "Gulpin", 12 }, { 43, "Oddish", 12 },
  { 315, "Roselia", 12 }, { 313, "Volbeat", 12 }, { 314, "Illumise", 12 }, { 322, "Numel", 14 },
  { 325, "Spoink", 18 }, { 328, "Trapinch", 18 }, { 331, "Cacnea", 18 }, { 27, "Sandshrew", 18 },
  { 333, "Swablu", 20 }, { 339, "Barboach", 20 }, { 341, "Corphish", 20 }, { 343, "Baltoy", 20 },
  { 320, "Wailmer", 20 }, { 318, "Carvanha", 20 }, { 349, "Feebas", 20 }, { 370, "Luvdisc", 20 },
  { 327, "Spinda", 20 }, { 307, "Meditite", 20 }, { 324, "Torkoal", 20 }, { 177, "Natu", 20 },
  { 299, "Nosepass", 20 }, { 202, "Wobbuffet", 20 }, { 353, "Shuppet", 23 }, { 355, "Duskull", 23 },
  { 335, "Zangoose", 25 }, { 336, "Seviper", 25 }, { 337, "Lunatone", 25 }, { 338, "Solrock", 25 },
  { 352, "Kecleon", 25 }, { 357, "Tropius", 25 }, { 359, "Absol", 25 }, { 358, "Chimecho", 25 },
  { 361, "Snorunt", 25 }, { 363, "Spheal", 25 }, { 366, "Clamperl", 25 }, { 369, "Relicanth", 25 },
  { 116, "Horsea", 25 }, { 371, "Bagon", 25 }, { 279, "Pelipper", 25 }, { 264, "Linoone", 25 },
  { 262, "Mightyena", 25 }, { 84, "Doduo", 25 }, { 227, "Skarmory", 25 },
}

-- FireRed / LeafGreen: Kanto, and the Sevii Islands' Johto visitors
local SEVII = {
  { 177, "Natu", 30 }, { 179, "Mareep", 30 }, { 194, "Wooper", 30 }, { 183, "Marill", 30 },
  { 167, "Spinarak", 30 }, { 165, "Ledyba", 30 }, { 187, "Hoppip", 30 }, { 191, "Sunkern", 30 },
  { 202, "Wobbuffet", 30 }, { 231, "Phanpy", 30 }, { 216, "Teddiursa", 30 }, { 223, "Remoraid", 30 },
  { 225, "Delibird", 30 }, { 220, "Swinub", 30 }, { 215, "Sneasel", 30 }, { 246, "Larvitar", 30 },
  { 198, "Murkrow", 30 }, { 228, "Houndour", 30 }, { 227, "Skarmory", 30 }, { 218, "Slugma", 30 },
  { 161, "Sentret", 30 },
}

local SINNOH = {
  { 396, "Starly", 2 }, { 399, "Bidoof", 2 }, { 401, "Kricketot", 2 }, { 403, "Shinx", 3 },
  { 406, "Budew", 4 }, { 41, "Zubat", 5 }, { 74, "Geodude", 5 }, { 54, "Psyduck", 5 },
  { 66, "Machop", 5 }, { 63, "Abra", 5 }, { 412, "Burmy", 5 }, { 415, "Combee", 5 },
  { 417, "Pachirisu", 5 }, { 418, "Buizel", 5 }, { 422, "Shellos", 5 }, { 129, "Magikarp", 5 },
  { 425, "Drifloon", 10 }, { 427, "Buneary", 10 }, { 420, "Cherubi", 10 }, { 433, "Chingling", 10 },
  { 436, "Bronzor", 10 }, { 438, "Bonsly", 10 }, { 439, "Mime Jr.", 10 }, { 280, "Ralts", 10 },
  { 72, "Tentacool", 10 }, { 278, "Wingull", 10 }, { 431, "Glameow", 15 }, { 434, "Stunky", 15 },
  { 92, "Gastly", 15 }, { 77, "Ponyta", 15 }, { 443, "Gible", 15 }, { 118, "Goldeen", 15 },
  { 449, "Hippopotas", 20 }, { 451, "Skorupi", 20 }, { 453, "Croagunk", 20 }, { 456, "Finneon", 20 },
  { 458, "Mantyke", 20 }, { 441, "Chatot", 20 }, { 397, "Staravia", 20 }, { 404, "Luxio", 20 },
  { 400, "Bibarel", 20 }, { 402, "Kricketune", 20 }, { 198, "Murkrow", 20 }, { 200, "Misdreavus", 20 },
  { 228, "Houndour", 20 }, { 193, "Yanma", 20 }, { 207, "Gligar", 20 }, { 355, "Duskull", 20 },
  { 339, "Barboach", 20 }, { 307, "Meditite", 20 }, { 214, "Heracross", 20 }, { 190, "Aipom", 20 },
  { 455, "Carnivine", 25 }, { 459, "Snover", 25 }, { 234, "Stantler", 25 }, { 279, "Pelipper", 25 },
  { 203, "Girafarig", 25 }, { 215, "Sneasel", 30 }, { 220, "Swinub", 30 }, { 361, "Snorunt", 30 },
  { 75, "Graveler", 30 }, { 42, "Golbat", 30 }, { 419, "Floatzel", 30 }, { 426, "Drifblim", 30 },
}

-- HeartGold / SoulSilver: Johto, Kanto, and the Safari Zone's visitors
local HGSS_EXTRA = {
  { 25, "Pikachu", 10 }, { 46, "Paras", 10 }, { 298, "Azurill", 10 }, { 35, "Clefairy", 15 },
  { 48, "Venonat", 15 }, { 81, "Magnemite", 15 }, { 100, "Voltorb", 15 }, { 123, "Scyther", 15 },
  { 127, "Pinsir", 15 }, { 102, "Exeggcute", 20 }, { 104, "Cubone", 20 }, { 307, "Meditite", 20 },
  { 436, "Bronzor", 20 }, { 113, "Chansey", 25 }, { 132, "Ditto", 25 }, { 352, "Kecleon", 25 },
  { 111, "Rhyhorn", 30 },
}

local UNOVA = {
  { 504, "Patrat", 2 }, { 506, "Lillipup", 2 }, { 509, "Purrloin", 2 }, { 519, "Pidove", 4 },
  { 540, "Sewaddle", 7 }, { 543, "Venipede", 7 }, { 546, "Cottonee", 7 }, { 548, "Petilil", 7 },
  { 511, "Pansage", 10 }, { 513, "Pansear", 10 }, { 515, "Panpour", 10 }, { 517, "Munna", 10 },
  { 524, "Roggenrola", 10 }, { 527, "Woobat", 10 }, { 529, "Drilbur", 10 }, { 531, "Audino", 10 },
  { 532, "Timburr", 10 }, { 522, "Blitzle", 12 }, { 535, "Tympole", 12 }, { 550, "Basculin", 13 },
  { 538, "Throh", 15 }, { 539, "Sawk", 15 }, { 572, "Minccino", 18 }, { 551, "Sandile", 20 },
  { 554, "Darumaka", 20 }, { 556, "Maractus", 20 }, { 557, "Dwebble", 20 }, { 559, "Scraggy", 20 },
  { 561, "Sigilyph", 20 }, { 562, "Yamask", 20 }, { 568, "Trubbish", 20 }, { 574, "Gothita", 20 },
  { 577, "Solosis", 20 }, { 580, "Ducklett", 20 }, { 520, "Tranquill", 20 }, { 507, "Herdier", 20 },
  { 510, "Liepard", 20 }, { 582, "Vanillite", 25 }, { 585, "Deerling", 25 }, { 587, "Emolga", 25 },
  { 588, "Karrablast", 25 }, { 616, "Shelmet", 25 }, { 590, "Foongus", 25 }, { 592, "Frillish", 25 },
  { 595, "Joltik", 25 }, { 597, "Ferroseed", 25 }, { 599, "Klink", 25 }, { 602, "Tynamo", 25 },
  { 618, "Stunfisk", 25 }, { 605, "Elgyem", 30 }, { 607, "Litwick", 30 }, { 610, "Axew", 30 },
  { 613, "Cubchoo", 30 }, { 615, "Cryogonal", 30 }, { 619, "Mienfoo", 30 }, { 622, "Golett", 30 },
  { 624, "Pawniard", 30 }, { 627, "Rufflet", 30 }, { 629, "Vullaby", 30 }, { 631, "Heatmor", 30 },
  { 632, "Durant", 30 }, { 594, "Alomomola", 30 }, { 523, "Zebstrika", 30 }, { 626, "Bouffalant", 35 },
  { 621, "Druddigon", 35 }, { 633, "Deino", 40 },
}

local function concat(a, b)
  local out = {}
  for _, e in ipairs(a) do out[#out + 1] = e end
  for _, e in ipairs(b or {}) do out[#out + 1] = e end
  return out
end

R.CURATED = {
  kanto = KANTO, johto = JOHTO, hoenn = HOENN, frlg = concat(KANTO, SEVII),
  sinnoh = SINNOH, hgss = concat(JOHTO, HGSS_EXTRA), unova = UNOVA,
}

-- --------------------------------------------------------- legendaries
-- { dex, name, level, weight (mythicals 1), only = { versions } }

R.LEGENDS = {
  kanto = {
    { 144, "Articuno", 50, 3 }, { 145, "Zapdos", 50, 3 }, { 146, "Moltres", 50, 3 },
    { 150, "Mewtwo", 70, 2 }, { 151, "Mew", 30, 1 },
  },
  johto = {
    { 243, "Raikou", 40, 3 }, { 244, "Entei", 40, 3 }, { 245, "Suicune", 40, 3 },
    { 249, "Lugia", 45, 2 }, { 250, "Ho-Oh", 45, 2 }, { 251, "Celebi", 30, 1 },
  },
  hoenn = {
    { 377, "Regirock", 40, 3 }, { 378, "Regice", 40, 3 }, { 379, "Registeel", 40, 3 },
    { 380, "Latias", 40, 2, only = { sapphire = true, emerald = true } },
    { 381, "Latios", 40, 2, only = { ruby = true, emerald = true } },
    { 382, "Kyogre", 45, 2, only = { sapphire = true, emerald = true } },
    { 383, "Groudon", 45, 2, only = { ruby = true, emerald = true } },
    { 384, "Rayquaza", 70, 1 }, { 385, "Jirachi", 20, 1 }, { 386, "Deoxys", 30, 1 },
    { 151, "Mew", 30, 1, only = { emerald = true } },
    { 249, "Lugia", 70, 1, only = { emerald = true } }, { 250, "Ho-Oh", 70, 1, only = { emerald = true } },
  },
  frlg = {
    { 144, "Articuno", 50, 3 }, { 145, "Zapdos", 50, 3 }, { 146, "Moltres", 50, 3 },
    { 150, "Mewtwo", 70, 2 }, { 243, "Raikou", 50, 2 }, { 244, "Entei", 50, 2 }, { 245, "Suicune", 50, 2 },
    { 249, "Lugia", 70, 1 }, { 250, "Ho-Oh", 70, 1 }, { 386, "Deoxys", 30, 1 }, { 151, "Mew", 30, 1 },
  },
  sinnoh = {
    { 480, "Uxie", 50, 3 }, { 481, "Mesprit", 50, 3 }, { 482, "Azelf", 50, 3 },
    { 483, "Dialga", 70, 1, only = { diamond = true, platinum = true } },
    { 484, "Palkia", 70, 1, only = { pearl = true, platinum = true } },
    { 485, "Heatran", 50, 2 }, { 486, "Regigigas", 70, 1 }, { 487, "Giratina", 70, 1 },
    { 488, "Cresselia", 50, 2 }, { 491, "Darkrai", 50, 1 }, { 492, "Shaymin", 30, 1 }, { 493, "Arceus", 80, 1 },
    { 377, "Regirock", 30, 2, only = { platinum = true } }, { 378, "Regice", 30, 2, only = { platinum = true } },
    { 379, "Registeel", 30, 2, only = { platinum = true } },
    { 144, "Articuno", 60, 2, only = { platinum = true } }, { 145, "Zapdos", 60, 2, only = { platinum = true } },
    { 146, "Moltres", 60, 2, only = { platinum = true } },
  },
  hgss = {
    { 243, "Raikou", 40, 3 }, { 244, "Entei", 40, 3 }, { 245, "Suicune", 40, 3 },
    { 144, "Articuno", 50, 2 }, { 145, "Zapdos", 50, 2 }, { 146, "Moltres", 50, 2 },
    { 249, "Lugia", 45, 2 }, { 250, "Ho-Oh", 45, 2 }, { 150, "Mewtwo", 70, 1 }, { 251, "Celebi", 30, 1 },
    { 380, "Latias", 35, 1, only = { heartgold = true } }, { 381, "Latios", 35, 1, only = { soulsilver = true } },
    { 383, "Groudon", 50, 1, only = { heartgold = true } }, { 382, "Kyogre", 50, 1, only = { soulsilver = true } },
    { 384, "Rayquaza", 50, 1 }, { 483, "Dialga", 50, 1 }, { 484, "Palkia", 50, 1 }, { 487, "Giratina", 50, 1 },
  },
  unova = {
    { 638, "Cobalion", 42, 3 }, { 639, "Terrakion", 42, 3 }, { 640, "Virizion", 42, 3 },
    { 641, "Tornadus", 40, 2, only = { black = true, black2 = true } },
    { 642, "Thundurus", 40, 2, only = { white = true, white2 = true } },
    { 643, "Reshiram", 50, 2, only = { black = true, black2 = true } },
    { 644, "Zekrom", 50, 2, only = { white = true, white2 = true } },
    { 645, "Landorus", 70, 1 }, { 646, "Kyurem", 75, 1 }, { 494, "Victini", 15, 1 },
    { 647, "Keldeo", 15, 1 }, { 648, "Meloetta", 15, 1 }, { 649, "Genesect", 15, 1 },
  },
}

-- every legendary of every game: kept out of the wild pools
R.LEGEND_DEX = {}
for _, list in pairs(R.LEGENDS) do for _, l in ipairs(list) do R.LEGEND_DEX[l[1]] = true end end

-- ------------------------------------------------------------- helpers

local function Courses() return require("src.pokewalker.WalkerCourses") end

R.FAMILY_GEN = { kanto = 1, johto = 2, hoenn = 3, frlg = 3, sinnoh = 4, hgss = 4, unova = 5 }

-- the game's generation: GameVersion's word, else its family's
local function generation(version)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  local info = ok and GameVersion.info and GameVersion.info(version)
  return info and tonumber(info.generation) or R.FAMILY_GEN[R.FAMILY[version] or ""]
end
R.generation = generation

function R.family(version)
  return R.FAMILY[version] or R.BY_GEN[generation(version) or 2] or "johto"
end

function R.maxDex(version)
  local gen = generation(version)
  return gen and Courses().MAX_DEX[gen] or Courses().maxDexFor(version)
end

local function speciesIndex()
  local ok, idx = pcall(function() return Courses().species() end)
  return ok and type(idx) == "table" and idx or {}
end

local function norm(s) return (tostring(s or ""):upper():gsub("\226\153\128", "F"):gsub("\226\153\130", "M"):gsub("[^%w]", "")) end

-- a species from an encounter slot: a dex number, "SPECIES_129" (Gen 1-2,
-- where the constant IS the dex) or a name ("MAGIKARP", Hoenn's tables)
local function slotDex(v, gen, byName)
  if type(v) == "number" then return v end
  if type(v) ~= "string" then return nil end
  local n = v:match("^SPECIES_(%d+)$")
  if n then return gen and gen <= 2 and tonumber(n) or nil end
  return byName[norm((v:gsub("^SPECIES_", "")))]
end

local function levelsOf(t)
  local lo = tonumber(t.minLevel) or tonumber(t.min) or tonumber(t.level)
  local hi = tonumber(t.maxLevel) or tonumber(t.max) or tonumber(t.level) or lo
  if not lo or lo <= 0 then return nil end
  return lo, math.max(lo, hi or lo)
end

local memo = {}

-- the imported game's own wild Pokemon: { { species, name, minLevel, maxLevel, catchRate } }
-- or nil when the game is not imported (or its tables read as nothing)
function R.imported(version)
  if memo[version] ~= nil then return memo[version] or nil end
  memo[version] = false
  local ok, SaveData = pcall(require, "src.core.SaveData")
  local root = ok and SaveData.dataDir and SaveData.dataDir()
  if not root then return nil end
  local path = root .. "/" .. version .. "/data/generated/encounters.lua"
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  local Ser = require("src.core.SaveSerializer")
  local cache = R.CACHE:format(version)
  if love and love.filesystem and love.filesystem.getInfo(cache) then
    local okc, t = pcall(Ser.decode, love.filesystem.read(cache) or "")
    if okc and type(t) == "table" and t.size == size and type(t.list) == "table" then
      f:close()
      memo[version] = t.list
      return t.list
    end
  end
  f:seek("set", 0)
  local src = f:read("*a"); f:close()
  local chunk = (loadstring or load)(src)
  src = nil
  local okr, enc = pcall(chunk or error)
  if not okr or type(enc) ~= "table" then return nil end
  local gen = generation(version)
  local max = R.maxDex(version)
  local idx = speciesIndex()
  local byName = {}
  for dex, s in pairs(idx) do if s.name then byName[norm(s.name)] = dex end end
  for _, list in pairs(R.CURATED) do for _, e in ipairs(list) do byName[norm(e[2])] = byName[norm(e[2])] or e[1] end end
  local found, seen = {}, {}
  local function walk(t, depth)
    if seen[t] or depth > 12 then return end
    seen[t] = true
    if t.species ~= nil then
      local dex = slotDex(t.species, gen, byName)
      local lo, hi = levelsOf(t)
      if dex and dex >= 1 and dex <= max and lo then
        local e = found[dex]
        if not e then found[dex] = { lo = lo, hi = hi, n = 1 }
        else e.lo, e.hi, e.n = math.min(e.lo, lo), math.max(e.hi, hi), e.n + 1 end
      end
    end
    for _, v in pairs(t) do if type(v) == "table" then walk(v, depth + 1) end end
  end
  walk(enc, 0)
  local names = {}
  for _, list in pairs(R.CURATED) do for _, e in ipairs(list) do names[e[1]] = names[e[1]] or e[2] end end
  local list = {}
  for dex, e in pairs(found) do
    local s = idx[dex]
    local rate = s and tonumber(s.catchRate)
    if not R.LEGEND_DEX[dex] and not (rate and rate <= 3) then
      list[#list + 1] = { species = dex, name = (s and s.name) or names[dex] or ("#" .. dex),
                          minLevel = math.min(e.lo, 100), maxLevel = math.min(e.hi, 100), catchRate = rate }
    end
  end
  table.sort(list, function(a, b) if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end return a.species < b.species end)
  if #list < 12 then return nil end
  memo[version] = list
  if love and love.filesystem then pcall(love.filesystem.write, cache, Ser.encode({ size = size, list = list })) end
  return list
end

-- the game's whole wild pool (before progress): imported, else curated
function R.pool(version)
  local list = R.imported(version)
  if list then return list, "imported" end
  local max = R.maxDex(version)
  local idx = speciesIndex()
  local out, used = {}, {}
  for _, e in ipairs(R.CURATED[R.family(version)] or {}) do
    if e[1] <= max and not used[e[1]] and not R.LEGEND_DEX[e[1]] then
      used[e[1]] = true
      local s = idx[e[1]]
      out[#out + 1] = { species = e[1], name = (s and s.name) or e[2], minLevel = e[3], maxLevel = e[3] + 12,
                        catchRate = s and tonumber(s.catchRate) }
    end
  end
  table.sort(out, function(a, b) if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end return a.species < b.species end)
  return out, "curated"
end

-- the game's legendaries: { { species, name, level, weight } }
function R.legends(version)
  local max = R.maxDex(version)
  local idx = speciesIndex()
  local out = {}
  for _, l in ipairs(R.LEGENDS[R.family(version)] or {}) do
    if l[1] <= max and (not l.only or l.only[version] or not R.knownVersion(version, l.only)) then
      local s = idx[l[1]]
      out[#out + 1] = { species = l[1], name = (s and s.name) or l[2], level = l[3], weight = l[4] or 1 }
    end
  end
  return out
end

-- a version-only legendary for a version of the family the table does not
-- name (Prism, Polished Crystal, a romhack): offered, rather than lost
function R.knownVersion(version, only)
  local fam = R.family(version)
  for v, f in pairs(R.FAMILY) do if f == fam and v == version then return true end end
  return false
end

-- --------------------------------------------------------- progress

local function walkSteps(st)
  local w = st and st.walking
  if not w then return 0 end
  return (tonumber(w.steps) or 0) + (tonumber(w.bonusSteps) or 0)
end

local function courseLevels(st)
  local lo, hi
  for _, e in ipairs((st.walking and st.walking.encounters) or {}) do
    local l = tonumber(e.level)
    if l then lo = math.min(lo or l, l); hi = math.max(hi or l, l) end
  end
  return lo or 5, hi or 8
end

-- the highest wild level in reach now
function R.reach(st)
  local _, hi = courseLevels(st)
  return math.min(100, hi + math.min(R.MAX_REACH, math.floor(walkSteps(st) / R.STEPS_PER_LEVEL)))
end

function R.sourceVersion(st)
  local w = st and st.walking
  return w and w.source and w.source.version or "heartgold"
end

-- the wild species in reach now (never fewer than MIN_POOL: the lowest ones)
function R.unlocked(st, version)
  version = version or R.sourceVersion(st)
  local pool = R.pool(version)
  local reach = R.reach(st)
  local out = {}
  for _, e in ipairs(pool) do if e.minLevel <= reach then out[#out + 1] = e end end
  for i = #out + 1, math.min(R.MIN_POOL, #pool) do out[i] = pool[i] end
  return out
end

-- per mille, this search
function R.legendChance(st)
  local s = walkSteps(st)
  if s < R.LEGEND_MIN_STEPS then return 0 end
  return math.min(R.LEGEND_MAX, R.LEGEND_BASE + math.floor((s - R.LEGEND_MIN_STEPS) / 1000) * R.LEGEND_PER_1K)
end

-- rarity group by catch rate (the course's A / B / C), else by level
local function groupOf(e, reach)
  local r = e.catchRate
  if r then return r <= 45 and "A" or r <= 120 and "B" or "C" end
  if e.minLevel >= reach - 3 then return "A" end
  if e.minLevel >= reach * 0.6 then return "B" end
  return "C"
end

local WEIGHT = { A = 1, B = 3, C = 6 }

local function weighted(list, w, rnd)
  local sum = 0
  for _, e in ipairs(list) do sum = sum + w(e) end
  if sum <= 0 then return list[1] end
  local roll = rnd(sum)
  for _, e in ipairs(list) do
    roll = roll - w(e)
    if roll <= 0 then return e end
  end
  return list[#list]
end

-- one search's find. `course` is the course's reachable encounters,
-- `coursePick(course)` the original's own weighted draw.
function R.roll(st, course, rnd, coursePick)
  local version = R.sourceVersion(st)
  local gen = generation(version) or 2
  local shiny = gen >= 2 and rnd(R.SHINY_ODDS) == 1 or nil
  if rnd(1000) <= R.legendChance(st) then
    local legends = R.legends(version)
    if #legends > 0 then
      local l = weighted(legends, function(e) return e.weight end, rnd)
      return { group = "L", species = l.species, name = l.name, level = l.level, legendary = true,
               mythical = l.weight <= 1 or nil, shiny = shiny, radar = true }
    end
  end
  local wild = R.unlocked(st, version)
  if #course > 0 and (#wild == 0 or rnd(100) <= R.COURSE_SHARE) then
    local pick = coursePick(course)
    if shiny then
      local copy = {}
      for k, v in pairs(pick) do copy[k] = v end
      copy.shiny = true
      return copy
    end
    return pick
  end
  if #wild == 0 then return nil end
  local reach = R.reach(st)
  local e = weighted(wild, function(x) return WEIGHT[groupOf(x, reach)] end, rnd)
  local lo = math.max(1, e.minLevel)
  local hi = math.max(lo, math.min(e.maxLevel or lo, reach))
  local level = lo + rnd(hi - lo + 1) - 1
  return { group = groupOf(e, reach), species = e.species, name = e.name, level = level, shiny = shiny, radar = true }
end

function R._reset() memo = {} end

return R
