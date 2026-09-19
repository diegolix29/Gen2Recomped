-- Evolution parameters + custom evolution items, for ALL 1025 national-dex
-- species -- species_data.lua's refurbished role now that national_dex
-- (optional_dependencies, manifest.json) is the base-stat/type/ability
-- source of truth for anything it covers (see engine_modern_stats.lua's
-- ModernStats.resolveBase). national_dex's own schema documents an
-- `evolutions` field but ships it EMPTY for every one of its 1025+326
-- records (confirmed directly: grepped all 1200 `evolutions = ` entries
-- in its data/species/generated/national.lua, every one is `{}`) -- so
-- evolution parameters are NOT something national_dex provides, and stay
-- this mod's own job.
--
-- Source: WIP_species_data.lua (C:\Proyectos\DynamaxRecomp), a from-
-- scratch parse of the same Pokemon_Stats/pokemon.txt pack the original
-- 51-species species_data.lua drew from, now covering the full national
-- dex (1-1025) instead of just the 51 species needed for Gigantamax
-- evolution-line completeness. Extracted mechanically (brace-matched, not
-- regex over multi-line blocks, to avoid truncating nested rows) -- see
-- the extraction script in this session's scratchpad if this ever needs
-- re-running against an updated WIP file.
--
-- Two deliberate departures from a pure mechanical copy:
--   * MILCERY keeps the ALREADY-DEPLOYED hand-built substitute (one ITEM-
--     triggered row per Sweet flavor) instead of the raw source's
--     method="HOLDITEM" (hold a Sweet + level up while spinning) -- this
--     engine has no held-item mechanic to express that, and the ITEM
--     substitute is what's live in the current species_data.lua today.
--     Overwriting it with dead HOLDITEM data would silently break an
--     evolution that currently works.
--   * Applin's DIPPLIN branch and Duraludon's ARCHALUDON branch, omitted
--     from the old 51-species file (their targets weren't registered
--     species there), are INCLUDED here -- DIPPLIN/ARCHALUDON exist as
--     their own entries in the source data's full 1025-species coverage,
--     so the reference is no longer dangling.
--
-- Engine evolution-method support (src/pokemon/Evolution.lua, read
-- directly): the dispatcher only recognizes LEVEL, ITEM, TRADE natively,
-- plus HAPPINESS via this mod's own installHappinessEvolution
-- (main.lua) -- an unrecognized evo.method is silently skipped by
-- Evolution.pendingFor's `if method and method.check then` guard, never
-- an error, just permanently dormant. Of the 456 species below with a
-- non-empty evolutions array, ~369 use one of those four supported
-- methods; the remainder use one of ~35 more exotic methods from the
-- source pack (day/night, gender-specific, location flags, move-known
-- checks, trade-for-species, walking distance, and more) that this
-- engine/mod has no trigger logic for yet. Included anyway rather than
-- dropped -- dormant data costs nothing at runtime and this stays a
-- complete, faithful transcription of the source rather than a silently
-- narrowed one -- but every evolution using one of those methods will
-- not fire in-game until (if ever) matching Evolution.METHODS entries
-- get built for them, the same way HAPPINESS already was.
--
-- NOT included here (that's national_dex's job when it's installed, or
-- the OLD species_data.lua's job for the 51-species subset if it isn't):
-- baseStats, types, catchRate, baseExp, growthRate, height/weight,
-- dexEntry, abilities, learnsets. A consumer building a full species
-- registration record needs to merge THIS file's evolutions with a
-- stats/types source separately -- see the open main.lua question this
-- was flagged alongside.
return {
  -- Consumable evolution items this pack introduces, beyond the native
  -- stones -- canonical English names (Sword/Shield), not the old Spanish
  -- source text. Registered as real items in main.lua and wired through
  -- the same generic "use item -> check species evolutions table" hook
  -- installEvolutionItems already uses.
  items = {
    TARTAPPLE        = { name = "Tart Apple" },
    SWEETAPPLE       = { name = "Sweet Apple" },
    SCROLLOFDARKNESS = { name = "Scroll of Darkness" },
    SCROLLOFWATERS   = { name = "Scroll of Waters" },
    STRAWBERRYSWEET  = { name = "Strawberry Sweet" },
    BERRYSWEET       = { name = "Berry Sweet" },
    LOVESWEET        = { name = "Love Sweet" },
    STARSWEET        = { name = "Star Sweet" },
    CLOVERSWEET      = { name = "Clover Sweet" },
    FLOWERSWEET      = { name = "Flower Sweet" },
    RIBBONSWEET      = { name = "Ribbon Sweet" },
    -- New with the full 1025-species pass -- items other evolution rows
    -- below reference that the old 51-species item table never needed.
    -- FIRESTONE/LEAFSTONE/MOONSTONE/THUNDERSTONE/WATERSTONE are
    -- deliberately NOT here -- the source pack's own ids for those five
    -- don't match this engine's real native ones (confirmed by reading
    -- the engine's own generated items.lua: FIRE_STONE, LEAF_STONE,
    -- MOON_STONE, THUNDER_STONE, WATER_STONE, underscored) -- every
    -- evolutions[] row below referencing one of those five was remapped
    -- to the real native id instead of registering a second, dead
    -- duplicate item.
    SYRUPYAPPLE      = { name = "Syrupy Apple" },
    METALALLOY       = { name = "Metal Alloy" },
    AUSPICIOUSARMOR  = { name = "Auspicious Armor" },
    MALICIOUSARMOR   = { name = "Malicious Armor" },
    CRACKEDPOT       = { name = "Cracked Pot" },
    UNREMARKABLETEACUP = { name = "Unremarkable Teacup" },
    -- Gen 4/8 evolution items with no Gen-1/2 native equivalent at all
    -- (confirmed absent from the engine's own generated items.lua under
    -- any naming).
    SUNSTONE         = { name = "Sun Stone" },
    DUSKSTONE        = { name = "Dusk Stone" },
    SHINYSTONE       = { name = "Shiny Stone" },
    ICESTONE         = { name = "Ice Stone" },
    LINKINGCORD      = { name = "Linking Cord" },
    BLACKAUGURITE    = { name = "Black Augurite" },
  },

  evolutions = {
    BULBASAUR = {
        { method = "LEVEL", species = "IVYSAUR", level = 16 },
      },
    IVYSAUR = {
        { method = "LEVEL", species = "VENUSAUR", level = 32 },
      },
    CHARMANDER = {
        { method = "LEVEL", species = "CHARMELEON", level = 16 },
      },
    CHARMELEON = {
        { method = "LEVEL", species = "CHARIZARD", level = 36 },
      },
    SQUIRTLE = {
        { method = "LEVEL", species = "WARTORTLE", level = 16 },
      },
    WARTORTLE = {
        { method = "LEVEL", species = "BLASTOISE", level = 36 },
      },
    CATERPIE = {
        { method = "LEVEL", species = "METAPOD", level = 7 },
      },
    METAPOD = {
        { method = "LEVEL", species = "BUTTERFREE", level = 10 },
      },
    WEEDLE = {
        { method = "LEVEL", species = "KAKUNA", level = 7 },
      },
    KAKUNA = {
        { method = "LEVEL", species = "BEEDRILL", level = 10 },
      },
    PIDGEY = {
        { method = "LEVEL", species = "PIDGEOTTO", level = 18 },
      },
    PIDGEOTTO = {
        { method = "LEVEL", species = "PIDGEOT", level = 36 },
      },
    RATTATA = {
        { method = "LEVEL", species = "RATICATE", level = 20 },
      },
    SPEAROW = {
        { method = "LEVEL", species = "FEAROW", level = 20 },
      },
    EKANS = {
        { method = "LEVEL", species = "ARBOK", level = 22 },
      },
    PIKACHU = {
        { method = "ITEM", species = "RAICHU", item = "THUNDER_STONE" },
      },
    SANDSHREW = {
        { method = "LEVEL", species = "SANDSLASH", level = 22 },
      },
    NIDORANFE = {
        { method = "LEVEL", species = "NIDORINA", level = 16 },
      },
    NIDORINA = {
        { method = "ITEM", species = "NIDOQUEEN", item = "MOON_STONE" },
      },
    NIDORANMA = {
        { method = "LEVEL", species = "NIDORINO", level = 16 },
      },
    NIDORINO = {
        { method = "ITEM", species = "NIDOKING", item = "MOON_STONE" },
      },
    CLEFAIRY = {
        { method = "ITEM", species = "CLEFABLE", item = "MOON_STONE" },
      },
    VULPIX = {
        { method = "ITEM", species = "NINETALES", item = "FIRE_STONE" },
      },
    JIGGLYPUFF = {
        { method = "ITEM", species = "WIGGLYTUFF", item = "MOON_STONE" },
      },
    ZUBAT = {
        { method = "LEVEL", species = "GOLBAT", level = 22 },
      },
    GOLBAT = {
        { method = "HAPPINESS", species = "CROBAT" },
      },
    ODDISH = {
        { method = "LEVEL", species = "GLOOM", level = 21 },
      },
    GLOOM = {
        { method = "ITEM", species = "VILEPLUME", item = "LEAF_STONE" },
        { method = "ITEM", species = "BELLOSSOM", item = "SUNSTONE" },
      },
    PARAS = {
        { method = "LEVEL", species = "PARASECT", level = 24 },
      },
    VENONAT = {
        { method = "LEVEL", species = "VENOMOTH", level = 31 },
      },
    DIGLETT = {
        { method = "LEVEL", species = "DUGTRIO", level = 26 },
      },
    MEOWTH = {
        { method = "LEVEL", species = "PERSIAN", level = 28 },
      },
    PSYDUCK = {
        { method = "LEVEL", species = "GOLDUCK", level = 33 },
      },
    MANKEY = {
        { method = "LEVEL", species = "PRIMEAPE", level = 28 },
      },
    PRIMEAPE = {
        { method = "LEVELUSEMOVECOUNT", species = "ANNIHILAPE" },
      },
    GROWLITHE = {
        { method = "ITEM", species = "ARCANINE", item = "FIRE_STONE" },
      },
    POLIWAG = {
        { method = "LEVEL", species = "POLIWHIRL", level = 25 },
      },
    POLIWHIRL = {
        { method = "ITEM", species = "POLIWRATH", item = "WATER_STONE" },
        { method = "CABLELINKITEM", species = "POLITOED" },
      },
    ABRA = {
        { method = "LEVEL", species = "KADABRA", level = 16 },
      },
    KADABRA = {
        { method = "TRADE", species = "ALAKAZAM" },
        { method = "ITEM", species = "ALAKAZAM", item = "LINKINGCORD" },
      },
    MACHOP = {
        { method = "LEVEL", species = "MACHOKE", level = 28 },
      },
    MACHOKE = {
        { method = "TRADE", species = "MACHAMP" },
        { method = "ITEM", species = "MACHAMP", item = "LINKINGCORD" },
      },
    BELLSPROUT = {
        { method = "LEVEL", species = "WEEPINBELL", level = 21 },
      },
    WEEPINBELL = {
        { method = "ITEM", species = "VICTREEBEL", item = "LEAF_STONE" },
      },
    TENTACOOL = {
        { method = "LEVEL", species = "TENTACRUEL", level = 30 },
      },
    GEODUDE = {
        { method = "LEVEL", species = "GRAVELER", level = 25 },
      },
    GRAVELER = {
        { method = "TRADE", species = "GOLEM" },
        { method = "ITEM", species = "GOLEM", item = "LINKINGCORD" },
      },
    PONYTA = {
        { method = "LEVEL", species = "RAPIDASH", level = 40 },
      },
    SLOWPOKE = {
        { method = "LEVEL", species = "SLOWBRO", level = 37 },
        { method = "CABLELINKITEM", species = "SLOWKING" },
      },
    MAGNEMITE = {
        { method = "LEVEL", species = "MAGNETON", level = 30 },
      },
    MAGNETON = {
        { method = "ITEM", species = "MAGNEZONE", item = "THUNDER_STONE" },
        { method = "LOCATIONFLAG", species = "MAGNEZONE" },
      },
    FARFETCHD = {
        { method = "NONE", species = "SIRFETCHD" },
      },
    DODUO = {
        { method = "LEVEL", species = "DODRIO", level = 31 },
      },
    SEEL = {
        { method = "LEVEL", species = "DEWGONG", level = 34 },
      },
    GRIMER = {
        { method = "LEVEL", species = "MUK", level = 38 },
      },
    SHELLDER = {
        { method = "ITEM", species = "CLOYSTER", item = "WATER_STONE" },
      },
    GASTLY = {
        { method = "LEVEL", species = "HAUNTER", level = 25 },
      },
    HAUNTER = {
        { method = "TRADE", species = "GENGAR" },
        { method = "ITEM", species = "GENGAR", item = "LINKINGCORD" },
      },
    ONIX = {
        { method = "CABLELINKITEM", species = "STEELIX" },
      },
    DROWZEE = {
        { method = "LEVEL", species = "HYPNO", level = 26 },
      },
    KRABBY = {
        { method = "LEVEL", species = "KINGLER", level = 28 },
      },
    VOLTORB = {
        { method = "LEVEL", species = "ELECTRODE", level = 30 },
      },
    EXEGGCUTE = {
        { method = "ITEM", species = "EXEGGUTOR", item = "LEAF_STONE" },
      },
    CUBONE = {
        { method = "LEVEL", species = "MAROWAK", level = 28 },
      },
    LICKITUNG = {
        { method = "HAS_MOVE", species = "LICKILICKY" },
      },
    KOFFING = {
        { method = "LEVEL", species = "WEEZING", level = 35 },
      },
    RHYHORN = {
        { method = "LEVEL", species = "RHYDON", level = 42 },
      },
    RHYDON = {
        { method = "CABLELINKITEM", species = "RHYPERIOR" },
      },
    CHANSEY = {
        { method = "HAPPINESS", species = "BLISSEY" },
      },
    TANGELA = {
        { method = "HAS_MOVE", species = "TANGROWTH" },
      },
    HORSEA = {
        { method = "LEVEL", species = "SEADRA", level = 32 },
      },
    SEADRA = {
        { method = "CABLELINKITEM", species = "KINGDRA" },
      },
    GOLDEEN = {
        { method = "LEVEL", species = "SEAKING", level = 33 },
      },
    STARYU = {
        { method = "ITEM", species = "STARMIE", item = "WATER_STONE" },
      },
    MRMIME = {
        { method = "NONE", species = "MRRIME" },
      },
    SCYTHER = {
        { method = "CABLELINKITEM", species = "SCIZOR" },
        { method = "ITEM", species = "KLEAVOR", item = "BLACKAUGURITE" },
      },
    ELECTABUZZ = {
        { method = "CABLELINKITEM", species = "ELECTIVIRE" },
      },
    MAGMAR = {
        { method = "CABLELINKITEM", species = "MAGMORTAR" },
      },
    MAGIKARP = {
        { method = "LEVEL", species = "GYARADOS", level = 20 },
      },
    EEVEE = {
        { method = "ITEM", species = "VAPOREON", item = "WATER_STONE" },
        { method = "ITEM", species = "FLAREON", item = "FIRE_STONE" },
        { method = "ITEM", species = "LEAFEON", item = "LEAF_STONE" },
        { method = "LOCATIONFLAG", species = "LEAFEON" },
        { method = "ITEM", species = "GLACEON", item = "ICESTONE" },
        { method = "LOCATIONFLAG", species = "GLACEON" },
        { method = "HAPPINESSMOVETYPE", species = "SYLVEON" },
        { method = "HAPPINESSDAY", species = "ESPEON" },
        { method = "HAPPINESSNIGHT", species = "UMBREON" },
      },
    PORYGON = {
        { method = "CABLELINKITEM", species = "PORYGON2" },
      },
    OMANYTE = {
        { method = "LEVEL", species = "OMASTAR", level = 40 },
      },
    KABUTO = {
        { method = "LEVEL", species = "KABUTOPS", level = 40 },
      },
    DRATINI = {
        { method = "LEVEL", species = "DRAGONAIR", level = 30 },
      },
    DRAGONAIR = {
        { method = "LEVEL", species = "DRAGONITE", level = 55 },
      },
    CHIKORITA = {
        { method = "LEVEL", species = "BAYLEEF", level = 16 },
      },
    BAYLEEF = {
        { method = "LEVEL", species = "MEGANIUM", level = 32 },
      },
    CYNDAQUIL = {
        { method = "LEVEL", species = "QUILAVA", level = 14 },
      },
    QUILAVA = {
        { method = "LEVEL", species = "TYPHLOSION", level = 36 },
      },
    TOTODILE = {
        { method = "LEVEL", species = "CROCONAW", level = 18 },
      },
    CROCONAW = {
        { method = "LEVEL", species = "FERALIGATR", level = 30 },
      },
    SENTRET = {
        { method = "LEVEL", species = "FURRET", level = 15 },
      },
    HOOTHOOT = {
        { method = "LEVEL", species = "NOCTOWL", level = 20 },
      },
    LEDYBA = {
        { method = "LEVEL", species = "LEDIAN", level = 18 },
      },
    SPINARAK = {
        { method = "LEVEL", species = "ARIADOS", level = 22 },
      },
    CHINCHOU = {
        { method = "LEVEL", species = "LANTURN", level = 27 },
      },
    PICHU = {
        { method = "HAPPINESS", species = "PIKACHU" },
      },
    CLEFFA = {
        { method = "HAPPINESS", species = "CLEFAIRY" },
      },
    IGGLYBUFF = {
        { method = "HAPPINESS", species = "JIGGLYPUFF" },
      },
    TOGEPI = {
        { method = "HAPPINESS", species = "TOGETIC" },
      },
    TOGETIC = {
        { method = "ITEM", species = "TOGEKISS", item = "SHINYSTONE" },
      },
    NATU = {
        { method = "LEVEL", species = "XATU", level = 25 },
      },
    MAREEP = {
        { method = "LEVEL", species = "FLAAFFY", level = 15 },
      },
    FLAAFFY = {
        { method = "LEVEL", species = "AMPHAROS", level = 30 },
      },
    MARILL = {
        { method = "LEVEL", species = "AZUMARILL", level = 18 },
      },
    HOPPIP = {
        { method = "LEVEL", species = "SKIPLOOM", level = 18 },
      },
    SKIPLOOM = {
        { method = "LEVEL", species = "JUMPLUFF", level = 27 },
      },
    AIPOM = {
        { method = "HAS_MOVE", species = "AMBIPOM" },
      },
    SUNKERN = {
        { method = "ITEM", species = "SUNFLORA", item = "SUNSTONE" },
      },
    YANMA = {
        { method = "HAS_MOVE", species = "YANMEGA" },
      },
    WOOPER = {
        { method = "LEVEL", species = "QUAGSIRE", level = 20 },
      },
    MURKROW = {
        { method = "ITEM", species = "HONCHKROW", item = "DUSKSTONE" },
      },
    MISDREAVUS = {
        { method = "ITEM", species = "MISMAGIUS", item = "DUSKSTONE" },
      },
    GIRAFARIG = {
        { method = "HAS_MOVE", species = "FARIGIRAF" },
      },
    PINECO = {
        { method = "LEVEL", species = "FORRETRESS", level = 31 },
      },
    DUNSPARCE = {
        { method = "HASMOVERANDFORM", species = "DUDUNSPARCE" },
      },
    GLIGAR = {
        { method = "NIGHTHOLDITEM", species = "GLISCOR" },
      },
    SNUBBULL = {
        { method = "LEVEL", species = "GRANBULL", level = 23 },
      },
    SNEASEL = {
        { method = "NIGHTHOLDITEM", species = "WEAVILE" },
      },
    TEDDIURSA = {
        { method = "LEVEL", species = "URSARING", level = 30 },
      },
    URSARING = {
        { method = "ITEMNIGHT", species = "URSALUNA" },
      },
    SLUGMA = {
        { method = "LEVEL", species = "MAGCARGO", level = 38 },
      },
    SWINUB = {
        { method = "LEVEL", species = "PILOSWINE", level = 33 },
      },
    PILOSWINE = {
        { method = "HAS_MOVE", species = "MAMOSWINE" },
      },
    CORSOLA = {
        { method = "NONE", species = "CURSOLA" },
      },
    REMORAID = {
        { method = "LEVEL", species = "OCTILLERY", level = 25 },
      },
    HOUNDOUR = {
        { method = "LEVEL", species = "HOUNDOOM", level = 24 },
      },
    PHANPY = {
        { method = "LEVEL", species = "DONPHAN", level = 25 },
      },
    PORYGON2 = {
        { method = "CABLELINKITEM", species = "PORYGONZ" },
      },
    STANTLER = {
        { method = "LEVELUSEMOVECOUNT", species = "WYRDEER" },
      },
    TYROGUE = {
        { method = "ATTACK_GREATER", species = "HITMONLEE" },
        { method = "DEFENSE_GREATER", species = "HITMONCHAN" },
        { method = "ATTACK_DEFENSE_EQUAL", species = "HITMONTOP" },
      },
    SMOOCHUM = {
        { method = "LEVEL", species = "JYNX", level = 30 },
      },
    ELEKID = {
        { method = "LEVEL", species = "ELECTABUZZ", level = 30 },
      },
    MAGBY = {
        { method = "LEVEL", species = "MAGMAR", level = 30 },
      },
    LARVITAR = {
        { method = "LEVEL", species = "PUPITAR", level = 30 },
      },
    PUPITAR = {
        { method = "LEVEL", species = "TYRANITAR", level = 55 },
      },
    TREECKO = {
        { method = "LEVEL", species = "GROVYLE", level = 16 },
      },
    GROVYLE = {
        { method = "LEVEL", species = "SCEPTILE", level = 36 },
      },
    TORCHIC = {
        { method = "LEVEL", species = "COMBUSKEN", level = 16 },
      },
    COMBUSKEN = {
        { method = "LEVEL", species = "BLAZIKEN", level = 36 },
      },
    MUDKIP = {
        { method = "LEVEL", species = "MARSHTOMP", level = 16 },
      },
    MARSHTOMP = {
        { method = "LEVEL", species = "SWAMPERT", level = 36 },
      },
    POOCHYENA = {
        { method = "LEVEL", species = "MIGHTYENA", level = 18 },
      },
    ZIGZAGOON = {
        { method = "LEVEL", species = "LINOONE", level = 20 },
      },
    LINOONE = {
        { method = "NONE", species = "OBSTAGOON" },
      },
    WURMPLE = {
        { method = "SILCOON", species = "SILCOON" },
        { method = "CASCOON", species = "CASCOON" },
      },
    SILCOON = {
        { method = "LEVEL", species = "BEAUTIFLY", level = 10 },
      },
    CASCOON = {
        { method = "LEVEL", species = "DUSTOX", level = 10 },
      },
    LOTAD = {
        { method = "LEVEL", species = "LOMBRE", level = 14 },
      },
    LOMBRE = {
        { method = "ITEM", species = "LUDICOLO", item = "WATER_STONE" },
      },
    SEEDOT = {
        { method = "LEVEL", species = "NUZLEAF", level = 14 },
      },
    NUZLEAF = {
        { method = "ITEM", species = "SHIFTRY", item = "LEAF_STONE" },
      },
    TAILLOW = {
        { method = "LEVEL", species = "SWELLOW", level = 22 },
      },
    WINGULL = {
        { method = "LEVEL", species = "PELIPPER", level = 25 },
      },
    RALTS = {
        { method = "LEVEL", species = "KIRLIA", level = 20 },
      },
    KIRLIA = {
        { method = "LEVEL", species = "GARDEVOIR", level = 30 },
        { method = "ITEMMALE", species = "GALLADE" },
      },
    SURSKIT = {
        { method = "LEVEL", species = "MASQUERAIN", level = 22 },
      },
    SHROOMISH = {
        { method = "LEVEL", species = "BRELOOM", level = 23 },
      },
    SLAKOTH = {
        { method = "LEVEL", species = "VIGOROTH", level = 18 },
      },
    VIGOROTH = {
        { method = "LEVEL", species = "SLAKING", level = 36 },
      },
    NINCADA = {
        { method = "NINJASK", species = "NINJASK" },
        { method = "SHEDINJA", species = "SHEDINJA" },
      },
    WHISMUR = {
        { method = "LEVEL", species = "LOUDRED", level = 20 },
      },
    LOUDRED = {
        { method = "LEVEL", species = "EXPLOUD", level = 40 },
      },
    MAKUHITA = {
        { method = "LEVEL", species = "HARIYAMA", level = 24 },
      },
    AZURILL = {
        { method = "HAPPINESS", species = "MARILL" },
      },
    NOSEPASS = {
        { method = "LOCATIONFLAG", species = "PROBOPASS" },
        { method = "ITEM", species = "PROBOPASS", item = "THUNDER_STONE" },
      },
    SKITTY = {
        { method = "ITEM", species = "DELCATTY", item = "MOON_STONE" },
      },
    ARON = {
        { method = "LEVEL", species = "LAIRON", level = 32 },
      },
    LAIRON = {
        { method = "LEVEL", species = "AGGRON", level = 42 },
      },
    MEDITITE = {
        { method = "LEVEL", species = "MEDICHAM", level = 37 },
      },
    ELECTRIKE = {
        { method = "LEVEL", species = "MANECTRIC", level = 26 },
      },
    ROSELIA = {
        { method = "ITEM", species = "ROSERADE", item = "SHINYSTONE" },
      },
    GULPIN = {
        { method = "LEVEL", species = "SWALOT", level = 26 },
      },
    CARVANHA = {
        { method = "LEVEL", species = "SHARPEDO", level = 30 },
      },
    WAILMER = {
        { method = "LEVEL", species = "WAILORD", level = 40 },
      },
    NUMEL = {
        { method = "LEVEL", species = "CAMERUPT", level = 33 },
      },
    SPOINK = {
        { method = "LEVEL", species = "GRUMPIG", level = 32 },
      },
    TRAPINCH = {
        { method = "LEVEL", species = "VIBRAVA", level = 35 },
      },
    VIBRAVA = {
        { method = "LEVEL", species = "FLYGON", level = 45 },
      },
    CACNEA = {
        { method = "LEVEL", species = "CACTURNE", level = 32 },
      },
    SWABLU = {
        { method = "LEVEL", species = "ALTARIA", level = 35 },
      },
    BARBOACH = {
        { method = "LEVEL", species = "WHISCASH", level = 30 },
      },
    CORPHISH = {
        { method = "LEVEL", species = "CRAWDAUNT", level = 30 },
      },
    BALTOY = {
        { method = "LEVEL", species = "CLAYDOL", level = 36 },
      },
    LILEEP = {
        { method = "LEVEL", species = "CRADILY", level = 40 },
      },
    ANORITH = {
        { method = "LEVEL", species = "ARMALDO", level = 40 },
      },
    FEEBAS = {
        { method = "CABLELINKITEM", species = "MILOTIC" },
        { method = "BEAUTY", species = "MILOTIC" },
      },
    SHUPPET = {
        { method = "LEVEL", species = "BANETTE", level = 37 },
      },
    DUSKULL = {
        { method = "LEVEL", species = "DUSCLOPS", level = 37 },
      },
    DUSCLOPS = {
        { method = "CABLELINKITEM", species = "DUSKNOIR" },
      },
    WYNAUT = {
        { method = "LEVEL", species = "WOBBUFFET", level = 15 },
      },
    SNORUNT = {
        { method = "LEVEL", species = "GLALIE", level = 42 },
        { method = "ITEMFEMALE", species = "FROSLASS" },
      },
    SPHEAL = {
        { method = "LEVEL", species = "SEALEO", level = 32 },
      },
    SEALEO = {
        { method = "LEVEL", species = "WALREIN", level = 44 },
      },
    CLAMPERL = {
        { method = "CABLELINKITEM", species = "HUNTAIL" },
        { method = "CABLELINKITEM", species = "GOREBYSS" },
      },
    BAGON = {
        { method = "LEVEL", species = "SHELGON", level = 30 },
      },
    SHELGON = {
        { method = "LEVEL", species = "SALAMENCE", level = 50 },
      },
    BELDUM = {
        { method = "LEVEL", species = "METANG", level = 20 },
      },
    METANG = {
        { method = "LEVEL", species = "METAGROSS", level = 45 },
      },
    TURTWIG = {
        { method = "LEVEL", species = "GROTLE", level = 18 },
      },
    GROTLE = {
        { method = "LEVEL", species = "TORTERRA", level = 32 },
      },
    CHIMCHAR = {
        { method = "LEVEL", species = "MONFERNO", level = 14 },
      },
    MONFERNO = {
        { method = "LEVEL", species = "INFERNAPE", level = 36 },
      },
    PIPLUP = {
        { method = "LEVEL", species = "PRINPLUP", level = 16 },
      },
    PRINPLUP = {
        { method = "LEVEL", species = "EMPOLEON", level = 36 },
      },
    STARLY = {
        { method = "LEVEL", species = "STARAVIA", level = 14 },
      },
    STARAVIA = {
        { method = "LEVEL", species = "STARAPTOR", level = 34 },
      },
    BIDOOF = {
        { method = "LEVEL", species = "BIBAREL", level = 15 },
      },
    KRICKETOT = {
        { method = "LEVEL", species = "KRICKETUNE", level = 10 },
      },
    SHINX = {
        { method = "LEVEL", species = "LUXIO", level = 15 },
      },
    LUXIO = {
        { method = "LEVEL", species = "LUXRAY", level = 30 },
      },
    BUDEW = {
        { method = "HAPPINESSDAY", species = "ROSELIA" },
      },
    CRANIDOS = {
        { method = "LEVEL", species = "RAMPARDOS", level = 30 },
      },
    SHIELDON = {
        { method = "LEVEL", species = "BASTIODON", level = 30 },
      },
    BURMY = {
        { method = "LEVELFEMALE", species = "WORMADAM" },
        { method = "LEVELMALE", species = "MOTHIM" },
      },
    COMBEE = {
        { method = "LEVELFEMALE", species = "VESPIQUEN" },
      },
    BUIZEL = {
        { method = "LEVEL", species = "FLOATZEL", level = 26 },
      },
    CHERUBI = {
        { method = "LEVEL", species = "CHERRIM", level = 25 },
      },
    SHELLOS = {
        { method = "LEVEL", species = "GASTRODON", level = 30 },
      },
    DRIFLOON = {
        { method = "LEVEL", species = "DRIFBLIM", level = 28 },
      },
    BUNEARY = {
        { method = "HAPPINESS", species = "LOPUNNY" },
      },
    GLAMEOW = {
        { method = "LEVEL", species = "PURUGLY", level = 38 },
      },
    CHINGLING = {
        { method = "HAPPINESSNIGHT", species = "CHIMECHO" },
      },
    STUNKY = {
        { method = "LEVEL", species = "SKUNTANK", level = 34 },
      },
    BRONZOR = {
        { method = "LEVEL", species = "BRONZONG", level = 33 },
      },
    BONSLY = {
        { method = "HAS_MOVE", species = "SUDOWOODO" },
      },
    MIMEJR = {
        { method = "HAS_MOVE", species = "MRMIME" },
      },
    HAPPINY = {
        { method = "DAYHOLDITEM", species = "CHANSEY" },
      },
    GIBLE = {
        { method = "LEVEL", species = "GABITE", level = 24 },
      },
    GABITE = {
        { method = "LEVEL", species = "GARCHOMP", level = 48 },
      },
    MUNCHLAX = {
        { method = "HAPPINESS", species = "SNORLAX" },
      },
    RIOLU = {
        { method = "HAPPINESSDAY", species = "LUCARIO" },
      },
    HIPPOPOTAS = {
        { method = "LEVEL", species = "HIPPOWDON", level = 34 },
      },
    SKORUPI = {
        { method = "LEVEL", species = "DRAPION", level = 40 },
      },
    CROAGUNK = {
        { method = "LEVEL", species = "TOXICROAK", level = 37 },
      },
    FINNEON = {
        { method = "LEVEL", species = "LUMINEON", level = 31 },
      },
    MANTYKE = {
        { method = "HASINPARTY", species = "MANTINE" },
      },
    SNOVER = {
        { method = "LEVEL", species = "ABOMASNOW", level = 40 },
      },
    SNIVY = {
        { method = "LEVEL", species = "SERVINE", level = 17 },
      },
    SERVINE = {
        { method = "LEVEL", species = "SERPERIOR", level = 36 },
      },
    TEPIG = {
        { method = "LEVEL", species = "PIGNITE", level = 17 },
      },
    PIGNITE = {
        { method = "LEVEL", species = "EMBOAR", level = 36 },
      },
    OSHAWOTT = {
        { method = "LEVEL", species = "DEWOTT", level = 17 },
      },
    DEWOTT = {
        { method = "LEVEL", species = "SAMUROTT", level = 36 },
      },
    PATRAT = {
        { method = "LEVEL", species = "WATCHOG", level = 20 },
      },
    LILLIPUP = {
        { method = "LEVEL", species = "HERDIER", level = 16 },
      },
    HERDIER = {
        { method = "LEVEL", species = "STOUTLAND", level = 32 },
      },
    PURRLOIN = {
        { method = "LEVEL", species = "LIEPARD", level = 20 },
      },
    PANSAGE = {
        { method = "ITEM", species = "SIMISAGE", item = "LEAF_STONE" },
      },
    PANSEAR = {
        { method = "ITEM", species = "SIMISEAR", item = "FIRE_STONE" },
      },
    PANPOUR = {
        { method = "ITEM", species = "SIMIPOUR", item = "WATER_STONE" },
      },
    MUNNA = {
        { method = "ITEM", species = "MUSHARNA", item = "MOON_STONE" },
      },
    PIDOVE = {
        { method = "LEVEL", species = "TRANQUILL", level = 21 },
      },
    TRANQUILL = {
        { method = "LEVEL", species = "UNFEZANT", level = 32 },
      },
    BLITZLE = {
        { method = "LEVEL", species = "ZEBSTRIKA", level = 27 },
      },
    ROGGENROLA = {
        { method = "LEVEL", species = "BOLDORE", level = 25 },
      },
    BOLDORE = {
        { method = "TRADE", species = "GIGALITH" },
        { method = "ITEM", species = "GIGALITH", item = "LINKINGCORD" },
      },
    WOOBAT = {
        { method = "HAPPINESS", species = "SWOOBAT" },
      },
    DRILBUR = {
        { method = "LEVEL", species = "EXCADRILL", level = 31 },
      },
    TIMBURR = {
        { method = "LEVEL", species = "GURDURR", level = 25 },
      },
    GURDURR = {
        { method = "TRADE", species = "CONKELDURR" },
        { method = "ITEM", species = "CONKELDURR", item = "LINKINGCORD" },
      },
    TYMPOLE = {
        { method = "LEVEL", species = "PALPITOAD", level = 25 },
      },
    PALPITOAD = {
        { method = "LEVEL", species = "SEISMITOAD", level = 36 },
      },
    SEWADDLE = {
        { method = "LEVEL", species = "SWADLOON", level = 20 },
      },
    SWADLOON = {
        { method = "HAPPINESS", species = "LEAVANNY" },
      },
    VENIPEDE = {
        { method = "LEVEL", species = "WHIRLIPEDE", level = 22 },
      },
    WHIRLIPEDE = {
        { method = "LEVEL", species = "SCOLIPEDE", level = 30 },
      },
    COTTONEE = {
        { method = "ITEM", species = "WHIMSICOTT", item = "SUNSTONE" },
      },
    PETILIL = {
        { method = "ITEM", species = "LILLIGANT", item = "SUNSTONE" },
      },
    BASCULIN = {
        { method = "LEVELRECOILDAMAGEFORM0", species = "BASCULEGION" },
      },
    SANDILE = {
        { method = "LEVEL", species = "KROKOROK", level = 29 },
      },
    KROKOROK = {
        { method = "LEVEL", species = "KROOKODILE", level = 40 },
      },
    DARUMAKA = {
        { method = "LEVEL", species = "DARMANITAN", level = 35 },
      },
    DWEBBLE = {
        { method = "LEVEL", species = "CRUSTLE", level = 34 },
      },
    SCRAGGY = {
        { method = "LEVEL", species = "SCRAFTY", level = 39 },
      },
    YAMASK = {
        { method = "LEVEL", species = "COFAGRIGUS", level = 34 },
        { method = "NONE", species = "RUNERIGUS" },
      },
    TIRTOUGA = {
        { method = "LEVEL", species = "CARRACOSTA", level = 37 },
      },
    ARCHEN = {
        { method = "LEVEL", species = "ARCHEOPS", level = 37 },
      },
    TRUBBISH = {
        { method = "LEVEL", species = "GARBODOR", level = 36 },
      },
    ZORUA = {
        { method = "LEVEL", species = "ZOROARK", level = 30 },
      },
    MINCCINO = {
        { method = "ITEM", species = "CINCCINO", item = "SHINYSTONE" },
      },
    GOTHITA = {
        { method = "LEVEL", species = "GOTHORITA", level = 32 },
      },
    GOTHORITA = {
        { method = "LEVEL", species = "GOTHITELLE", level = 41 },
      },
    SOLOSIS = {
        { method = "LEVEL", species = "DUOSION", level = 32 },
      },
    DUOSION = {
        { method = "LEVEL", species = "REUNICLUS", level = 41 },
      },
    DUCKLETT = {
        { method = "LEVEL", species = "SWANNA", level = 35 },
      },
    VANILLITE = {
        { method = "LEVEL", species = "VANILLISH", level = 35 },
      },
    VANILLISH = {
        { method = "LEVEL", species = "VANILLUXE", level = 47 },
      },
    DEERLING = {
        { method = "LEVEL", species = "SAWSBUCK", level = 34 },
      },
    KARRABLAST = {
        { method = "TRADESPECIES", species = "ESCAVALIER" },
      },
    FOONGUS = {
        { method = "LEVEL", species = "AMOONGUSS", level = 39 },
      },
    FRILLISH = {
        { method = "LEVEL", species = "JELLICENT", level = 40 },
      },
    JOLTIK = {
        { method = "LEVEL", species = "GALVANTULA", level = 36 },
      },
    FERROSEED = {
        { method = "LEVEL", species = "FERROTHORN", level = 40 },
      },
    KLINK = {
        { method = "LEVEL", species = "KLANG", level = 38 },
      },
    KLANG = {
        { method = "LEVEL", species = "KLINKLANG", level = 49 },
      },
    TYNAMO = {
        { method = "LEVEL", species = "EELEKTRIK", level = 39 },
      },
    EELEKTRIK = {
        { method = "ITEM", species = "EELEKTROSS", item = "THUNDER_STONE" },
      },
    ELGYEM = {
        { method = "LEVEL", species = "BEHEEYEM", level = 42 },
      },
    LITWICK = {
        { method = "LEVEL", species = "LAMPENT", level = 41 },
      },
    LAMPENT = {
        { method = "ITEM", species = "CHANDELURE", item = "DUSKSTONE" },
      },
    AXEW = {
        { method = "LEVEL", species = "FRAXURE", level = 38 },
      },
    FRAXURE = {
        { method = "LEVEL", species = "HAXORUS", level = 48 },
      },
    CUBCHOO = {
        { method = "LEVEL", species = "BEARTIC", level = 37 },
      },
    SHELMET = {
        { method = "TRADESPECIES", species = "ACCELGOR" },
      },
    MIENFOO = {
        { method = "LEVEL", species = "MIENSHAO", level = 50 },
      },
    GOLETT = {
        { method = "LEVEL", species = "GOLURK", level = 43 },
      },
    PAWNIARD = {
        { method = "LEVEL", species = "BISHARP", level = 52 },
      },
    BISHARP = {
        { method = "LEVELDEFEATITSKINDWITHITEM", species = "KINGAMBIT" },
      },
    RUFFLET = {
        { method = "LEVEL", species = "BRAVIARY", level = 54 },
      },
    VULLABY = {
        { method = "LEVEL", species = "MANDIBUZZ", level = 54 },
      },
    DEINO = {
        { method = "LEVEL", species = "ZWEILOUS", level = 50 },
      },
    ZWEILOUS = {
        { method = "LEVEL", species = "HYDREIGON", level = 64 },
      },
    LARVESTA = {
        { method = "LEVEL", species = "VOLCARONA", level = 59 },
      },
    CHESPIN = {
        { method = "LEVEL", species = "QUILLADIN", level = 16 },
      },
    QUILLADIN = {
        { method = "LEVEL", species = "CHESNAUGHT", level = 36 },
      },
    FENNEKIN = {
        { method = "LEVEL", species = "BRAIXEN", level = 16 },
      },
    BRAIXEN = {
        { method = "LEVEL", species = "DELPHOX", level = 36 },
      },
    FROAKIE = {
        { method = "LEVEL", species = "FROGADIER", level = 16 },
      },
    FROGADIER = {
        { method = "LEVEL", species = "GRENINJA", level = 36 },
      },
    BUNNELBY = {
        { method = "LEVEL", species = "DIGGERSBY", level = 20 },
      },
    FLETCHLING = {
        { method = "LEVEL", species = "FLETCHINDER", level = 17 },
      },
    FLETCHINDER = {
        { method = "LEVEL", species = "TALONFLAME", level = 35 },
      },
    SCATTERBUG = {
        { method = "LEVEL", species = "SPEWPA", level = 9 },
      },
    SPEWPA = {
        { method = "LEVEL", species = "VIVILLON", level = 12 },
      },
    LITLEO = {
        { method = "LEVEL", species = "PYROAR", level = 35 },
      },
    FLABEBE = {
        { method = "LEVEL", species = "FLOETTE", level = 19 },
      },
    FLOETTE = {
        { method = "ITEM", species = "FLORGES", item = "SHINYSTONE" },
      },
    SKIDDO = {
        { method = "LEVEL", species = "GOGOAT", level = 32 },
      },
    PANCHAM = {
        { method = "LEVELDARKINPARTY", species = "PANGORO" },
      },
    ESPURR = {
        { method = "LEVEL", species = "MEOWSTIC", level = 25 },
      },
    HONEDGE = {
        { method = "LEVEL", species = "DOUBLADE", level = 35 },
      },
    DOUBLADE = {
        { method = "ITEM", species = "AEGISLASH", item = "DUSKSTONE" },
      },
    SPRITZEE = {
        { method = "CABLELINKITEM", species = "AROMATISSE" },
      },
    SWIRLIX = {
        { method = "CABLELINKITEM", species = "SLURPUFF" },
      },
    INKAY = {
        { method = "LEVEL", species = "MALAMAR", level = 30 },
      },
    BINACLE = {
        { method = "LEVEL", species = "BARBARACLE", level = 39 },
      },
    SKRELP = {
        { method = "LEVEL", species = "DRAGALGE", level = 48 },
      },
    CLAUNCHER = {
        { method = "LEVEL", species = "CLAWITZER", level = 37 },
      },
    HELIOPTILE = {
        { method = "ITEM", species = "HELIOLISK", item = "SUNSTONE" },
      },
    TYRUNT = {
        { method = "LEVELDAY", species = "TYRANTRUM" },
      },
    AMAURA = {
        { method = "LEVELNIGHT", species = "AURORUS" },
      },
    GOOMY = {
        { method = "LEVEL", species = "SLIGGOO", level = 40 },
      },
    SLIGGOO = {
        { method = "LEVELRAIN", species = "GOODRA" },
      },
    PHANTUMP = {
        { method = "TRADE", species = "TREVENANT" },
        { method = "ITEM", species = "TREVENANT", item = "LINKINGCORD" },
      },
    PUMPKABOO = {
        { method = "TRADE", species = "GOURGEIST" },
        { method = "ITEM", species = "GOURGEIST", item = "LINKINGCORD" },
      },
    BERGMITE = {
        { method = "LEVEL", species = "AVALUGG", level = 37 },
      },
    NOIBAT = {
        { method = "LEVEL", species = "NOIVERN", level = 48 },
      },
    ROWLET = {
        { method = "LEVEL", species = "DARTRIX", level = 17 },
      },
    DARTRIX = {
        { method = "LEVEL", species = "DECIDUEYE", level = 34 },
      },
    LITTEN = {
        { method = "LEVEL", species = "TORRACAT", level = 17 },
      },
    TORRACAT = {
        { method = "LEVEL", species = "INCINEROAR", level = 34 },
      },
    POPPLIO = {
        { method = "LEVEL", species = "BRIONNE", level = 17 },
      },
    BRIONNE = {
        { method = "LEVEL", species = "PRIMARINA", level = 34 },
      },
    PIKIPEK = {
        { method = "LEVEL", species = "TRUMBEAK", level = 14 },
      },
    TRUMBEAK = {
        { method = "LEVEL", species = "TOUCANNON", level = 28 },
      },
    YUNGOOS = {
        { method = "LEVELDAY", species = "GUMSHOOS" },
      },
    GRUBBIN = {
        { method = "LEVEL", species = "CHARJABUG", level = 20 },
      },
    CHARJABUG = {
        { method = "ITEM", species = "VIKAVOLT", item = "THUNDER_STONE" },
        { method = "LOCATIONFLAG", species = "VIKAVOLT" },
      },
    CRABRAWLER = {
        { method = "LOCATIONFLAG", species = "CRABOMINABLE" },
        { method = "ITEM", species = "CRABOMINABLE", item = "ICESTONE" },
      },
    CUTIEFLY = {
        { method = "LEVEL", species = "RIBOMBEE", level = 25 },
      },
    ROCKRUFF = {
        { method = "LEVEL", species = "LYCANROC", level = 25 },
      },
    MAREANIE = {
        { method = "LEVEL", species = "TOXAPEX", level = 38 },
      },
    MUDBRAY = {
        { method = "LEVEL", species = "MUDSDALE", level = 30 },
      },
    DEWPIDER = {
        { method = "LEVEL", species = "ARAQUANID", level = 22 },
      },
    FOMANTIS = {
        { method = "LEVELDAY", species = "LURANTIS" },
      },
    MORELULL = {
        { method = "LEVEL", species = "SHIINOTIC", level = 24 },
      },
    SALANDIT = {
        { method = "LEVELFEMALE", species = "SALAZZLE" },
      },
    STUFFUL = {
        { method = "LEVEL", species = "BEWEAR", level = 27 },
      },
    BOUNSWEET = {
        { method = "LEVEL", species = "STEENEE", level = 18 },
      },
    STEENEE = {
        { method = "HAS_MOVE", species = "TSAREENA" },
      },
    WIMPOD = {
        { method = "LEVEL", species = "GOLISOPOD", level = 30 },
      },
    SANDYGAST = {
        { method = "LEVEL", species = "PALOSSAND", level = 42 },
      },
    TYPENULL = {
        { method = "HAPPINESS", species = "SILVALLY" },
      },
    JANGMOO = {
        { method = "LEVEL", species = "HAKAMOO", level = 35 },
      },
    HAKAMOO = {
        { method = "LEVEL", species = "KOMMOO", level = 45 },
      },
    COSMOG = {
        { method = "LEVEL", species = "COSMOEM", level = 43 },
      },
    COSMOEM = {
        { method = "LEVELDAY", species = "SOLGALEO" },
        { method = "LEVELNIGHT", species = "LUNALA" },
      },
    POIPOLE = {
        { method = "HAS_MOVE", species = "NAGANADEL" },
      },
    MELTAN = {
        { method = "LEVEL", species = "MELMETAL", level = 45 },
      },
    GROOKEY = {
        { method = "LEVEL", species = "THWACKEY", level = 16 },
      },
    THWACKEY = {
        { method = "LEVEL", species = "RILLABOOM", level = 35 },
      },
    SCORBUNNY = {
        { method = "LEVEL", species = "RABOOT", level = 16 },
      },
    RABOOT = {
        { method = "LEVEL", species = "CINDERACE", level = 35 },
      },
    SOBBLE = {
        { method = "LEVEL", species = "DRIZZILE", level = 16 },
      },
    DRIZZILE = {
        { method = "LEVEL", species = "INTELEON", level = 35 },
      },
    SKWOVET = {
        { method = "LEVEL", species = "GREEDENT", level = 24 },
      },
    ROOKIDEE = {
        { method = "LEVEL", species = "CORVISQUIRE", level = 18 },
      },
    CORVISQUIRE = {
        { method = "LEVEL", species = "CORVIKNIGHT", level = 38 },
      },
    BLIPBUG = {
        { method = "LEVEL", species = "DOTTLER", level = 10 },
      },
    DOTTLER = {
        { method = "LEVEL", species = "ORBEETLE", level = 30 },
      },
    NICKIT = {
        { method = "LEVEL", species = "THIEVUL", level = 18 },
      },
    GOSSIFLEUR = {
        { method = "LEVEL", species = "ELDEGOSS", level = 20 },
      },
    WOOLOO = {
        { method = "LEVEL", species = "DUBWOOL", level = 24 },
      },
    CHEWTLE = {
        { method = "LEVEL", species = "DREDNAW", level = 22 },
      },
    YAMPER = {
        { method = "LEVEL", species = "BOLTUND", level = 25 },
      },
    ROLYCOLY = {
        { method = "LEVEL", species = "CARKOL", level = 18 },
      },
    CARKOL = {
        { method = "LEVEL", species = "COALOSSAL", level = 34 },
      },
    APPLIN = {
        { method = "ITEM", species = "FLAPPLE", item = "TARTAPPLE" },
        { method = "ITEM", species = "APPLETUN", item = "SWEETAPPLE" },
        { method = "ITEM", species = "DIPPLIN", item = "SYRUPYAPPLE" },
      },
    SILICOBRA = {
        { method = "LEVEL", species = "SANDACONDA", level = 36 },
      },
    ARROKUDA = {
        { method = "LEVEL", species = "BARRASKEWDA", level = 26 },
      },
    TOXEL = {
        { method = "LEVEL", species = "TOXTRICITY", level = 30 },
      },
    SIZZLIPEDE = {
        { method = "LEVEL", species = "CENTISKORCH", level = 28 },
      },
    CLOBBOPUS = {
        { method = "HAS_MOVE", species = "GRAPPLOCT" },
      },
    SINISTEA = {
        { method = "ITEM", species = "POLTEAGEIST", item = "CRACKEDPOT" },
      },
    HATENNA = {
        { method = "LEVEL", species = "HATTREM", level = 32 },
      },
    HATTREM = {
        { method = "LEVEL", species = "HATTERENE", level = 42 },
      },
    IMPIDIMP = {
        { method = "LEVEL", species = "MORGREM", level = 32 },
      },
    MORGREM = {
        { method = "LEVEL", species = "GRIMMSNARL", level = 42 },
      },
    MILCERY = {
        { method = "ITEM", species = "ALCREMIE", item = "STRAWBERRYSWEET" },
        { method = "ITEM", species = "ALCREMIE", item = "BERRYSWEET" },
        { method = "ITEM", species = "ALCREMIE", item = "LOVESWEET" },
        { method = "ITEM", species = "ALCREMIE", item = "STARSWEET" },
        { method = "ITEM", species = "ALCREMIE", item = "CLOVERSWEET" },
        { method = "ITEM", species = "ALCREMIE", item = "FLOWERSWEET" },
        { method = "ITEM", species = "ALCREMIE", item = "RIBBONSWEET" },
      },
    SNOM = {
        { method = "HAPPINESSNIGHT", species = "FROSMOTH" },
      },
    CUFANT = {
        { method = "LEVEL", species = "COPPERAJAH", level = 34 },
      },
    DURALUDON = {
        { method = "ITEM", species = "ARCHALUDON", item = "METALALLOY" },
      },
    DREEPY = {
        { method = "LEVEL", species = "DRAKLOAK", level = 50 },
      },
    DRAKLOAK = {
        { method = "LEVEL", species = "DRAGAPULT", level = 60 },
      },
    KUBFU = {
        { method = "ITEM", species = "URSHIFU", item = "SCROLLOFDARKNESS" },
        { method = "ITEM", species = "URSHIFU", item = "SCROLLOFWATERS" },
      },
    SPRIGATITO = {
        { method = "LEVEL", species = "FLORAGATO", level = 16 },
      },
    FLORAGATO = {
        { method = "LEVEL", species = "MEOWSCARADA", level = 36 },
      },
    FUECOCO = {
        { method = "LEVEL", species = "CROCALOR", level = 16 },
      },
    CROCALOR = {
        { method = "LEVEL", species = "SKELEDIRGE", level = 36 },
      },
    QUAXLY = {
        { method = "LEVEL", species = "QUAXWELL", level = 16 },
      },
    QUAXWELL = {
        { method = "LEVEL", species = "QUAQUAVAL", level = 36 },
      },
    LECHONK = {
        { method = "LEVEL", species = "OINKOLOGNE", level = 18 },
      },
    TAROUNTULA = {
        { method = "LEVEL", species = "SPIDOPS", level = 15 },
      },
    NYMBLE = {
        { method = "LEVEL", species = "LOKIX", level = 24 },
      },
    PAWMI = {
        { method = "LEVEL", species = "PAWMO", level = 18 },
      },
    PAWMO = {
        { method = "LEVELWALK", species = "PAWMOT" },
      },
    TANDEMAUS = {
        { method = "LEVELRANDFORM", species = "MAUSHOLD" },
      },
    FIDOUGH = {
        { method = "LEVEL", species = "DACHSBUN", level = 26 },
      },
    SMOLIV = {
        { method = "LEVEL", species = "DOLLIV", level = 25 },
      },
    DOLLIV = {
        { method = "LEVEL", species = "ARBOLIVA", level = 35 },
      },
    NACLI = {
        { method = "LEVEL", species = "NACLSTACK", level = 24 },
      },
    NACLSTACK = {
        { method = "LEVEL", species = "GARGANACL", level = 38 },
      },
    CHARCADET = {
        { method = "ITEM", species = "ARMAROUGE", item = "AUSPICIOUSARMOR" },
        { method = "ITEM", species = "CERULEDGE", item = "MALICIOUSARMOR" },
      },
    TADBULB = {
        { method = "ITEM", species = "BELLIBOLT", item = "THUNDER_STONE" },
      },
    WATTREL = {
        { method = "LEVEL", species = "KILOWATTREL", level = 25 },
      },
    MASCHIFF = {
        { method = "LEVEL", species = "MABOSSTIFF", level = 30 },
      },
    SHROODLE = {
        { method = "LEVEL", species = "GRAFAIAI", level = 28 },
      },
    BRAMBLIN = {
        { method = "LEVELWALK", species = "BRAMBLEGHAST" },
      },
    TOEDSCOOL = {
        { method = "LEVEL", species = "TOEDSCRUEL", level = 30 },
      },
    CAPSAKID = {
        { method = "ITEM", species = "SCOVILLAIN", item = "FIRE_STONE" },
      },
    RELLOR = {
        { method = "LEVELWALK", species = "RABSCA" },
      },
    FLITTLE = {
        { method = "LEVEL", species = "ESPATHRA", level = 35 },
      },
    TINKATINK = {
        { method = "LEVEL", species = "TINKATUFF", level = 24 },
      },
    TINKATUFF = {
        { method = "LEVEL", species = "TINKATON", level = 38 },
      },
    WIGLETT = {
        { method = "LEVEL", species = "WUGTRIO", level = 26 },
      },
    FINIZEN = {
        { method = "LEVEL", species = "PALAFIN", level = 38 },
      },
    VAROOM = {
        { method = "LEVEL", species = "REVAVROOM", level = 40 },
      },
    GLIMMET = {
        { method = "LEVEL", species = "GLIMMORA", level = 35 },
      },
    GREAVARD = {
        { method = "LEVELNIGHT", species = "HOUNDSTONE" },
      },
    CETODDLE = {
        { method = "ITEM", species = "CETITAN", item = "ICESTONE" },
      },
    FRIGIBAX = {
        { method = "LEVEL", species = "ARCTIBAX", level = 35 },
      },
    ARCTIBAX = {
        { method = "LEVEL", species = "BAXCALIBUR", level = 54 },
      },
    GIMMIGHOUL = {
        { method = "LEVELCOINS", species = "GHOLDENGO" },
      },
    DIPPLIN = {
        { method = "HAS_MOVE", species = "HYDRAPPLE" },
      },
    POLTCHAGEIST = {
        { method = "ITEM", species = "SINISTCHA", item = "UNREMARKABLETEACUP" },
      },
  },
}
