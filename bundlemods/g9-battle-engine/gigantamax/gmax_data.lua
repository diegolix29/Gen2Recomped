-- Phase 3 -- Gigantamax form metadata for the 34 Gigantamax-capable
-- species, from Pokemon_Stats/pokemon_forms_gmax.txt.
--
-- gmaxMove is either one of gmax_moves.lua's own new registrations, or
-- (Urshifu only) one of dynamax's two pre-existing reserved ids -- see
-- gmax_moves.lua's header. Height is the Gigantamax form's own listed
-- height in meters (kept for dex-entry/flavor use; nothing here resizes
-- the actual battle sprite -- that's Dynamax's own generic grow-animation
-- scale, unrelated to this per-species number).
--
-- Alcremie: the source data carries 63 near-duplicate Gigantamax records
-- (one per flavor/decoration cosmetic combination), all identical except
-- for which of its 63 regular forms they revert to. Per the earlier scope
-- decision, only one representative entry is kept here.
--
-- Eternatus is intentionally absent: its "Eternamax" form in the source
-- data has no GmaxMove at all -- in the real games it's a scripted
-- battle-only transformation, not something a player's own Eternatus can
-- use via the normal Dynamax mechanic. Its data (a full stat override,
-- BaseStats = 255,115,250,130,125,250) is noted here for any future
-- story/raid-boss content, but is deliberately not wired into the battle
-- mechanic this phase builds:
--   ETERNAMAX_STATS = { hp = 255, attack = 115, defense = 250, speed = 130,
--     special = 188 } -- special = round((125+250)/2), same conversion
--     rule as Phase 1's species.

return {
  order = {
    "VENUSAUR", "CHARIZARD", "BLASTOISE", "BUTTERFREE", "PIKACHU",
    "MEOWTH", "MACHAMP", "GENGAR", "KINGLER", "LAPRAS", "EEVEE",
    "SNORLAX", "GARBODOR", "MELMETAL", "RILLABOOM", "CINDERACE",
    "INTELEON", "CORVIKNIGHT", "ORBEETLE", "DREDNAW", "COALOSSAL",
    "FLAPPLE", "APPLETUN", "SANDACONDA", "TOXTRICITY", "CENTISKORCH",
    "HATTERENE", "GRIMMSNARL", "ALCREMIE", "COPPERAJAH", "DURALUDON",
    "URSHIFU", "ELDEGOSS",
  },

  species = {
    VENUSAUR = { heightM = 24.0, gmaxMove = "GMAXVINELASH",
      dexText = "In battle, this Pokemon swings around two thick vines. If these vines slammed into a 10-story building, they could easily topple it." },
    CHARIZARD = { heightM = 28.0, gmaxMove = "GMAXWILDFIRE",
      dexText = "This colossal, flame-winged figure of a Charizard was brought about by Gigantamax energy." },
    BLASTOISE = { heightM = 25.0, gmaxMove = "GMAXCANNONADE",
      dexText = "Water fired from this Pokemon's central main cannon has enough power to blast a hole into a mountain." },
    BUTTERFREE = { heightM = 17.0, gmaxMove = "GMAXBEFUDDLE",
      dexText = "Crystallized Gigantamax energy makes up this Pokemon's blindingly bright and highly toxic scales." },
    PIKACHU = { heightM = 21.0, gmaxMove = "GMAXVOLTCRASH",
      dexText = "Its Gigantamax power expanded, forming its supersized body and towering tail." },
    MEOWTH = { heightM = 33.0, gmaxMove = "GMAXGOLDRUSH",
      dexText = "Its body has grown incredibly long and the coin on its forehead has grown incredibly large all thanks to Gigantamax power." },
    MACHAMP = { heightM = 25.0, gmaxMove = "GMAXCHISTRIKE",
      dexText = "The Gigantamax energy coursing through its arms makes its punches hit as hard as bomb blasts." },
    GENGAR = { heightM = 20.0, gmaxMove = "GMAXTERROR",
      dexText = "It lays traps, hoping to steal the lives of those it catches. If you stand in front of its mouth, you'll hear your loved ones' voices calling out to you." },
    KINGLER = { heightM = 19.0, gmaxMove = "GMAXFOAMBURST",
      dexText = "The flow of Gigantamax energy has spurred this Pokemon's left pincer to grow to an enormous size. That claw can pulverize anything." },
    LAPRAS = { heightM = 24.0, gmaxMove = "GMAXRESONANCE",
      dexText = "Over 5,000 people can ride on its shell at once. And it's a very comfortable ride, without the slightest shaking or swaying." },
    EEVEE = { heightM = 18.0, gmaxMove = "GMAXCUDDLE",
      dexText = "Gigantamax energy upped the fluffiness of the fur around Eevee's neck. The fur will envelop a foe, capturing its body and captivating its mind." },
    SNORLAX = { heightM = 35.0, gmaxMove = "GMAXREPLENISH",
      dexText = "Gigantamax energy has affected stray seeds and even pebbles that got stuck to Snorlax, making them grow to a huge size." },
    GARBODOR = { heightM = 21.0, gmaxMove = "GMAXMALODOR",
      dexText = "Due to Gigantamax energy, this Pokemon's toxic gas has become much thicker, congealing into masses shaped like discarded toys." },
    MELMETAL = { heightM = 25.0, gmaxMove = "GMAXMELTDOWN",
      dexText = "In a distant land, there are legends about a cyclopean giant. In fact, the giant was a Melmetal that was flooded with Gigantamax energy." },
    RILLABOOM = { heightM = 28.0, gmaxMove = "GMAXDRUMSOLO",
      dexText = "Gigantamax energy has caused Rillaboom's stump to grow into a drum set that resembles a forest." },
    CINDERACE = { heightM = 27.0, gmaxMove = "GMAXFIREBALL",
      dexText = "Gigantamax energy can sometimes cause the diameter of this Pokemon's fireball to exceed 300 feet." },
    INTELEON = { heightM = 40.0, gmaxMove = "GMAXHYDROSNIPE",
      dexText = "Gigantamax Inteleon's Water Gun move fires at Mach 7. As the Pokemon takes aim, it uses the crest on its head to gauge wind and temperature." },
    CORVIKNIGHT = { heightM = 14.0, gmaxMove = "GMAXWINDRAGE",
      dexText = "Imbued with Gigantamax energy, its wings can whip up winds more forceful than any a hurricane could muster. The gusts blow everything away." },
    ORBEETLE = { heightM = 14.0, gmaxMove = "GMAXGRAVITAS",
      dexText = "Its brain has grown to a gargantuan size, as has the rest of its body. This Pokemon's intellect and psychic abilities are overpowering." },
    DREDNAW = { heightM = 24.0, gmaxMove = "GMAXSTONESURGE",
      dexText = "It responded to Gigantamax energy by becoming bipedal. First it comes crashing down on foes, and then it finishes them off with its massive jaws." },
    COALOSSAL = { heightM = 42.0, gmaxMove = "GMAXVOLCALITH",
      dexText = "Its body is a colossal stove. With Gigantamax energy stoking the fire, this Pokemon's flame burns hotter than 3,600 degrees Fahrenheit." },
    FLAPPLE = { heightM = 24.0, gmaxMove = "GMAXTARTNESS",
      dexText = "Under the influence of Gigantamax energy, it produces much more sweet nectar, and its shape has changed to resemble a giant apple." },
    APPLETUN = { heightM = 24.0, gmaxMove = "GMAXSWEETNESS",
      dexText = "Due to Gigantamax energy, this Pokemon's nectar has thickened. The increased viscosity lets the nectar absorb more damage than before." },
    SANDACONDA = { heightM = 22.0, gmaxMove = "GMAXSANDBLAST",
      dexText = "Sand swirls around its body with such speed and power that it could pulverize a skyscraper." },
    -- Both Toxtricity natures (Amped = base form, Low Key = PokedexForm 2)
    -- share the same Gigantamax move in the source data.
    TOXTRICITY = { heightM = 24.0, gmaxMove = "GMAXSTUNSHOCK",
      dexText = "Out of control after its own poison penetrated its brain, it tears across the land in a rampage, contaminating the earth with toxic sweat." },
    CENTISKORCH = { heightM = 75.0, gmaxMove = "GMAXCENTIFERNO",
      dexText = "The heat that comes off a Gigantamax Centiskorch may destabilize air currents. Sometimes it can even cause storms." },
    HATTERENE = { heightM = 26.0, gmaxMove = "GMAXSMITE",
      dexText = "Beams like lightning shoot down from its tentacles. It's known to some as the Raging Goddess." },
    GRIMMSNARL = { heightM = 32.0, gmaxMove = "GMAXSNOOZE",
      dexText = "Gigantamax energy has caused more hair to sprout all over its body. With the added strength, it can jump over the world's tallest building." },
    ALCREMIE = { heightM = 30.0, gmaxMove = "GMAXFINALE",
      dexText = "It launches swarms of missiles, each made of cream and loaded with 100,000 kilocalories. Get hit by one of these, and your head will swim." },
    COPPERAJAH = { heightM = 23.0, gmaxMove = "GMAXSTEELSURGE",
      dexText = "After this Pokemon has Gigantamaxed, its massive nose can utterly demolish large structures with a single smashing blow." },
    DURALUDON = { heightM = 43.0, gmaxMove = "GMAXDEPLETION",
      dexText = "It's grown to resemble a skyscraper. Parts of its towering body glow due to a profusion of energy." },
    -- Urshifu is registered as a single flat species in Phase 1 (no forms
    -- system yet -- see species_data.lua), so it cannot yet actually carry
    -- two distinct Gigantamax styles with different heights/moves the way
    -- the source data models them (Single Strike vs Rapid Strike, the
    -- same style split already simplified away in Phase 1's evolution
    -- data). This entry uses the Single Strike Style's data; Rapid Strike
    -- (height 26.0, GMAXRAPIDFLOW, and notably its own FIGHTING/WATER
    -- typing rather than base Urshifu's FIGHTING/DARK) is not represented
    -- until a real forms system exists. Both moves are still registered
    -- below via dynamax's own reserved ids either way.
    URSHIFU = { heightM = 29.0, gmaxMove = "MOD_GMAX_ONE_BLOW",
      dexText = "The energy released by this Pokemon's fists forms shock waves that can blow away Dynamax Pokemon in just one hit." },
    ELDEGOSS = { heightM = 30.0, gmaxMove = "GMAXCICLON",
      dexText = "TO DO. (Eldegoss has no official Gigantamax in the source games -- this pack's own data marks its dex entry as unfinished. GMAXCICLON is fully defined in moves_dynamax.txt regardless, so it's registered like any other.)" },
  },

  -- Not part of species.order / not battle-wired -- see the file header.
  eternamax = {
    heightM = 100.0,
    baseStats = { hp = 255, attack = 115, defense = 250, speed = 130, special = 188 },
    dexText = "Infinite amounts of energy pour from this Pokemon's enlarged core, warping the surrounding space-time.",
  },
}
