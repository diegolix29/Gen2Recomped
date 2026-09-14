-- Pokemon Colosseum models for overworld Pokemon entities.
--
-- This module reuses the existing Colosseum model system (PokemonActors)
-- for overworld rendering, similar to how OverworldStadium works for Stadium models.
--
-- Integration contract:
--   * VoxelScene captures the real entity beside each rendered pose.
--   * prepare(posed) resolves an exact species, loads a Colosseum model, and stores it.
--   * draw(pose) renders the Colosseum model instead of the 2D sprite.
--
-- Companion mods can tag a spawned NPC:
--
--   local ds = mod.find("DRAMATIC_SHAPE")
--   local ow = ds and ds.exports and ds.exports.lib
--              and ds.exports.lib.require("OverworldColosseum")
--   if ow then ow.tag(npc, "PIKACHU") end
--
-- Accepted tags are National Dex numbers (1-386) or engine species strings.
local V = ...

local ColosseumDex = V.ColosseumDex
local PokemonActors = V.PokemonActors
local Mat4 = V.Mat4
local Voxel3D = V.require("Voxel3D")

local OverworldColosseum = {}

local tagged = setmetatable({}, { __mode = "k" })
local entityDexCache = setmetatable({}, { __mode = "k" })
local slots = setmetatable({}, { __mode = "k" })
local nameCache = {}
local frameNo = 0
local reported = {}
local STALE_FRAMES = 120

local function logOnce(key, fmt, ...)
  if reported[key] then return end
  reported[key] = true
  local log = V.mod and V.mod.log
  if log and log.warn then pcall(log.warn, log, fmt, ...) end
end

local function colosseumEnabled()
  local ok, wilds = pcall(V.require, "ColosseumWilds")
  if ok and wilds and type(wilds.enabled) == "function" then
    return wilds.enabled()
  end
  return PokemonActors ~= nil
end

local function facingVector(facing)
  if facing == "up" then return 0, -1 end
  if facing == "left" then return -1, 0 end
  if facing == "right" then return 1, 0 end
  return 0, 1
end

local function dtForFrame()
  local dt = 1 / 60
  if love and love.timer and love.timer.getDelta then
    local ok, got = pcall(love.timer.getDelta)
    if ok and type(got) == "number" and got > 0 and got < 0.25 then
      dt = got
    end
  end
  return dt
end

local function releaseSlot(slot)
  if slot and slot.model and slot.model.actor then
    pcall(slot.model.actor.release, slot.model.actor)
  end
end

local function gameObject()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or type(Game) ~= "table" then return nil end
  return Game
end

local function gameData()
  local Game = gameObject()
  return Game and Game.data or nil
end

local function cleanName(v)
  if type(v) ~= "string" then return nil end
  local s = v:upper()
  s = s:gsub("[^A-Z0-9]", "")
  return s ~= "" and s or nil
end

local function dexNumber(v)
  if type(v) == "number" then
    local n = math.floor(v)
    if n >= 1 and n <= 386 then return n end
  elseif type(v) == "string" then
    local n = tonumber(v)
    if n then return dexNumber(n) end
  end
  return nil
end

-- Manual species name to National Dex mapping (Gen 1-3: 1-386)
local speciesToDex = {
  -- Gen 1
  BULBASAUR = 1, IVYSAUR = 2, VENUSAUR = 3,
  CHARMANDER = 4, CHARMELEON = 5, CHARIZARD = 6,
  SQUIRTLE = 7, WARTORTLE = 8, BLASTOISE = 9,
  CATERPIE = 10, METAPOD = 11, BUTTERFREE = 12,
  WEEDLE = 13, KAKUNA = 14, BEEDRILL = 15,
  PIDGEY = 16, PIDGEOTTO = 17, PIDGEOT = 18,
  RATTATA = 19, RATICATE = 20,
  SPEAROW = 21, FEAROW = 22,
  EKANS = 23, ARBOK = 24,
  PIKACHU = 25, RAICHU = 26,
  SANDSHREW = 27, SANDSLASH = 28,
  NIDORAN_F = 29, NIDORINA = 30, NIDOQUEEN = 31,
  NIDORAN_M = 32, NIDORINO = 33, NIDOKING = 34,
  CLEFAIRY = 35, CLEFABLE = 36,
  VULPIX = 37, NINETALES = 38,
  JIGGLYPUFF = 39, WIGGLYTUFF = 40,
  ZUBAT = 41, GOLBAT = 42,
  ODDISH = 43, GLOOM = 44, VILEPLUME = 45,
  PARAS = 46, PARASECT = 47,
  VENONAT = 48, VENOMOTH = 49,
  DIGLETT = 50, DUGTRIO = 51,
  MEOWTH = 52, PERSIAN = 53,
  PSYDUCK = 54, GOLDUCK = 55,
  MANKEY = 56, PRIMEAPE = 57,
  GROWLITHE = 58, ARCANINE = 59,
  POLIWAG = 60, POLIWHIRL = 61, POLIWRATH = 62,
  ABRA = 63, KADABRA = 64, ALAKAZAM = 65,
  MACHOP = 66, MACHOKE = 67, MACHAMP = 68,
  BELLSPROUT = 69, WEEPINBELL = 70, VICTREEBEL = 71,
  TENTACOOL = 72, TENTACRUEL = 73,
  GEODUDE = 74, GRAVELER = 75, GOLEM = 76,
  PONYTA = 77, RAPIDASH = 78,
  SLOWPOKE = 79, SLOWBRO = 80,
  MAGNEMITE = 81, MAGNETON = 82,
  FARFETCHD = 83,
  DODUO = 84, DODRIO = 85,
  SEEL = 86, DEWGONG = 87,
  GRIMER = 88, MUK = 89,
  SHELLDER = 90, CLOYSTER = 91,
  GASTLY = 92, HAUNTER = 93, GENGAR = 94,
  ONIX = 95,
  DROWZEE = 96, HYPNO = 97,
  KRABBY = 98, KINGLER = 99,
  VOLTORB = 100, ELECTRODE = 101,
  EXEGGCUTE = 102, EXEGGUTOR = 103,
  CUBONE = 104, MAROWAK = 105,
  HITMONLEE = 106, HITMONCHAN = 107,
  LICKITUNG = 108,
  KOFFING = 109, WEEZING = 110,
  RHYHORN = 111, RHYDON = 112,
  CHANSEY = 113,
  TANGELA = 114,
  KANGASKHAN = 115,
  HORSEA = 116, SEADRA = 117,
  GOLDEEN = 118, SEAKING = 119,
  STARYU = 120, STARMIE = 121,
  MR_MIME = 122,
  SCYTHER = 123,
  JYNX = 124,
  ELECTABUZZ = 125,
  MAGMAR = 126,
  PINSIR = 127,
  TAUROS = 128,
  MAGIKARP = 129, GYARADOS = 130,
  LAPRAS = 131,
  DITTO = 132,
  EEVEE = 133, VAPOREON = 134, JOLTEON = 135, FLAREON = 136,
  PORYGON = 137,
  OMANYTE = 138, OMASTAR = 139,
  KABUTO = 140, KABUTOPS = 141,
  AERODACTYL = 142,
  SNORLAX = 143,
  ARTICUNO = 144,
  ZAPDOS = 145,
  MOLTRES = 146,
  DRATINI = 147, DRAGONAIR = 148, DRAGONITE = 149,
  MEWTWO = 150,
  MEW = 151,
  -- Gen 2
  CHIKORITA = 152, BAYLEEF = 153, MEGANIUM = 154,
  CYNDAQUIL = 155, QUILAVA = 156, TYPHLOSION = 157,
  TOTODILE = 158, CROCONAW = 159, FERALIGATR = 160,
  SENTRET = 161, FURRET = 162,
  HOOTHOOT = 163, NOCTOWL = 164,
  LEDYBA = 165, LEDIAN = 166,
  SPINARAK = 167, ARIADOS = 168,
  CROBAT = 169,
  CHINCHOU = 170, LANTURN = 171,
  PICHU = 172, CLEFFA = 173, IGGLYBUFF = 174,
  TOGEPI = 175, TOGETIC = 176,
  NATU = 177, XATU = 178,
  MAREEP = 179, FLAAFFY = 180, AMPHAROS = 181,
  BELLOSSOM = 182,
  MARILL = 183, AZUMARILL = 184,
  SUDOWOODO = 185,
  POLITOED = 186,
  HOPPIP = 187, SKIPLOOM = 188, JUMPLUFF = 189,
  AIPOM = 190,
  SUNKERN = 191, SUNFLORA = 192,
  YANMA = 193,
  WOOPER = 194, QUAGSIRE = 195,
  ESPEON = 196, UMBREON = 197,
  MURKROW = 198,
  SLOWKING = 199,
  MISDREAVUS = 200,
  UNOWN = 201,
  WOBBUFFET = 202,
  GIRAFARIG = 203,
  PINECO = 204, FORRETRESS = 205,
  DUNSPARCE = 206,
  GLIGAR = 207,
  STEELIX = 208,
  SNUBBULL = 209, GRANBULL = 210,
  QWILFISH = 211,
  SCIZOR = 212,
  SHUCKLE = 213,
  HERACROSS = 214,
  SNEASEL = 215,
  TEDDIURSA = 216, URSARING = 217,
  SLUGMA = 218, MAGCARGO = 219,
  SWINUB = 220, PILOSWINE = 221,
  CORSOLA = 222,
  REMORAID = 223, OCTILLERY = 224,
  DELIBIRD = 225,
  MANTINE = 226,
  SKARMORY = 227,
  HOUNDOUR = 228, HOUNDOOM = 229,
  KINGDRA = 230,
  PHANPY = 231, DONPHAN = 232,
  PORYGON2 = 233,
  STANTLER = 234,
  SMEARGLE = 235,
  TYROGUE = 236, HITMONTOP = 237,
  SMOOCHUM = 238,
  ELEKID = 239,
  MAGBY = 240,
  MILTANK = 241,
  BLISSEY = 242,
  RAIKOU = 243,
  ENTEI = 244,
  SUICUNE = 245,
  LARVITAR = 246, PUPITAR = 247, TYRANITAR = 248,
  LUGIA = 249,
  HO_OH = 250,
  CELEBI = 251,
  -- Gen 3
  TREECKO = 252, GROVYLE = 253, SCEPTILE = 254,
  TORCHIC = 255, COMBUSKEN = 256, BLAZIKEN = 257,
  MUDKIP = 258, MARSHTOMP = 259, SWAMPERT = 260,
  POOCHYENA = 261, MIGHTYENA = 262,
  ZIGZAGOON = 263, LINOONE = 264,
  WURMPLE = 265, SILCOON = 266, BEAUTIFLY = 267, CASCOON = 268, DUSTOX = 269,
  LOTAD = 270, LOMBRE = 271, LUDICOLO = 272,
  SEEDOT = 273, NUZLEAF = 274, SHIFTRY = 275,
  NINCADA = 276, NINJASK = 277, SHEDINJA = 278,
  TAILLOW = 279, SWELLOW = 280,
  SHROOMISH = 281, BRELOOM = 282,
  SPINDA = 283,
  WINGULL = 284, PELIPPER = 285,
  SURSKIT = 286, MASQUERAIN = 287,
  WAILMER = 288, WAILORD = 289,
  SKITTY = 290, DELCATTY = 291,
  KECLEON = 292,
  BALTOY = 293, CLAYDOL = 294,
  NOSEPASS = 295,
  TORKOAL = 296,
  SABLEYE = 297,
  MAWILE = 298,
  ARON = 299, LAIRON = 300, AGGRON = 301,
  MEDITITE = 302, MEDICHAM = 303,
  ELECTRIKE = 304, MANECTRIC = 305,
  PLUSLE = 306,
  MINUN = 307,
  VOLBEAT = 308, ILLUMISE = 309,
  ROSELIA = 310,
  GULPIN = 311, SWALOT = 312,
  CARVANHA = 313, SHARPEDO = 314,
  NUMEL = 315, CAMERUPT = 316,
  TORKOAL = 317,
  SPOINK = 318, GRUMPIG = 319,
  SPINDA = 320,
  TRAPINCH = 321, VIBRAVA = 322, FLYGON = 323,
  CACNEA = 324, CACTURNE = 325,
  SWABLU = 326, ALTARIA = 327,
  ZANGOOSE = 328,
  SEVIPER = 329,
  LUNATONE = 330,
  SOLROCK = 331,
  BARBOACH = 332, WHISCASH = 333,
  CORPHISH = 334, CRAWDAUNT = 335,
  FEEBAS = 336, MILOTIC = 337,
  CASTFORM = 338,
  KECLEON = 339,
  SHUPPET = 340, BANETTE = 341,
  DUSKULL = 342, DUSCLOPS = 343,
  TROPIUS = 344,
  CHIMECHO = 345,
  ABSOL = 346,
  WYNAUT = 347,
  SNORUNT = 348, GLALIE = 349,
  SPHEAL = 350, SEALEO = 351, WALREIN = 352,
  CLAMPERL = 353, HUNTAIL = 354, GOREBYSS = 355,
  RELICANTH = 356,
  LUVDISC = 357,
  BAGON = 358, SHELGON = 359, SALAMENCE = 360,
  BELDUM = 361, METANG = 362, METAGROSS = 363,
  REGIROCK = 364,
  REGICE = 365,
  REGISTEEL = 366,
  LATIAS = 380,
  LATIOS = 381,
  KYOGRE = 382,
  GROUDON = 383,
  RAYQUAZA = 384,
  JIRACHI = 385,
  DEOXYS = 386,
}

local function speciesDex(v)
  local n = dexNumber(v)
  if n then return n end
  if type(v) ~= "string" then return nil end

  -- Trim whitespace and convert to uppercase
  local trimmed = v:match("^%s*(.-)%s*$")
  if not trimmed or trimmed == "" then return nil end
  local upper = trimmed:upper()

  local cacheKey = upper
  local cached = nameCache[cacheKey]
  if cached ~= nil then return cached or nil end

  -- Use manual mapping
  local dex = speciesToDex[upper]
  if dex then
    nameCache[cacheKey] = dex
    return dex
  end

  nameCache[cacheKey] = false
  return nil
end

function OverworldColosseum.tag(entity, speciesOrDex)
  if type(entity) ~= "table" then 
    return false 
  end
  if speciesOrDex == nil then
    tagged[entity] = nil
    return true
  end
  if speciesOrDex == false then
    tagged[entity] = false
    return true
  end
  
  local dex = nil
  
  -- Priority 1: Check if entity.sprite has dsSpecies (this is the dex number used by the sprite system)
  if entity.sprite and entity.sprite.dsSpecies then
    dex = dexNumber(entity.sprite.dsSpecies)
    if dex then
      tagged[entity] = dex
      return true
    end
  end

  -- Priority 2: Check if speciesOrDex is already a dex number
  dex = dexNumber(speciesOrDex)
  if dex then
    tagged[entity] = dex
    return true
  end

  -- Priority 3: Check if entity has dex/id field
  dex = dexNumber(entity.dex or entity.id or entity.speciesId)
  if dex then
    tagged[entity] = dex
    return true
  end
  
  -- Priority 4: Extract species name and try to resolve
  local speciesName = speciesOrDex
  if type(speciesOrDex) == "table" then
    speciesName = speciesOrDex.name or speciesOrDex.id or speciesOrDex.species or speciesOrDex.dex
  end
  
  if type(speciesName) ~= "string" then
    print("Colosseum: Could not resolve species from:", tostring(speciesOrDex))
    return false
  end
  
  -- Trim whitespace from species name
  speciesName = speciesName:match("^%s*(.-)%s*$")
  
  -- Try to get dex from species name
  dex = speciesDex(speciesName)
  if dex then
    tagged[entity] = dex
    return true
  end
  
  return false
end

function OverworldColosseum.untag(entity)
  if type(entity) ~= "table" then return false end
  tagged[entity] = nil
  entityDexCache[entity] = nil
  return true
end

function OverworldColosseum.getTaggedDex(entity)
  if type(entity) ~= "table" then return nil end
  local direct = tagged[entity]
  if direct then
    -- direct is now stored as a dex number
    return tonumber(direct) or nil
  end
  if direct ~= nil then return direct or nil end
  return entityDexCache[entity] or nil
end

function OverworldColosseum.resolveDex(entity)
  if type(entity) ~= "table" then return nil end

  local direct = tagged[entity]
  if direct ~= nil then
    if direct == false then return nil end
    local result = speciesDex(direct)
    if result then
      entityDexCache[entity] = result
      return result
    end
  end

  local cached = entityDexCache[entity]
  if cached then return cached end

  local data = gameData()
  if not data then return nil end

  local species = entity._wildsFollowerSpecies
               or entity.ambientSpecies
               or entity.species
               or (entity.pokepcMon and entity.pokepcMon.species)
  if not species then return nil end

  local result = speciesDex(species)
  if result then
    entityDexCache[entity] = result
    return result
  end

  return nil
end

function OverworldColosseum.safeClaimWilds(state)
  if not (state and state.entities) then return end
  for _, e in ipairs(state.entities) do
    if e and e.wildsAmbientPokemon then
      tagged[e] = false
    end
  end
end

local function prepareOne(p, dex, dt)
  if not (p and p.entity and dex) then return false end
  if p.stadiumMon then return false end

  local slot = slots[p.entity]
  if not slot then
    if not (PokemonActors and PokemonActors.loadOverworldModel) then return false end
    local okModel, model = pcall(PokemonActors.loadOverworldModel, PokemonActors, dex, "normal")
    if not okModel or not model or not model.actor then return false end
    slot = { model = model, lastSeen = frameNo }
    slots[p.entity] = slot
  end
  slot.lastSeen = frameNo

  local actor = slot.model.actor
  pcall(actor.update, actor, dt)
  pcall(actor.spawn, actor, 1)

  local renderFacing = p.facing
  local fx, fz = facingVector(renderFacing)

  local okFirstPerson, FirstPerson = pcall(V.require, "FirstPerson")
  if okFirstPerson and FirstPerson then
    local b = FirstPerson.cardBlend()
    if b > 0 then
      local cameraYaw = FirstPerson.cardYaw(p.px or 0, p.py or 0)
      local face = type(renderFacing) == "string" and string.lower(renderFacing) or renderFacing
      local yaw = 0
      if face == "down" then yaw = cameraYaw * b
      elseif face == "up" then yaw = (cameraYaw + math.pi) * b
      elseif face == "left" then yaw = (cameraYaw + math.pi / 2) * b
      elseif face == "right" then yaw = (cameraYaw - math.pi / 2) * b
      end
      fx = math.sin(yaw)
      fz = math.cos(yaw)
    end
  end

  local x = (p.px or 0) + 8
  local z = (p.py or 0) + 8
  local y = (p.gh or 0) + (p.lift or 0)

  local okMatrix, matrix = pcall(actor.matrix, actor, x, y, z, fx, fz)
  if not okMatrix or not matrix then return false end

  p._colosseumModel = slot.model
  p._colosseumActor = actor
  p._colosseumMatrix = matrix
  p._colosseumDex = dex
  return true
end

function OverworldColosseum.prepare(posed)
  if not colosseumEnabled() then return true end
  frameNo = frameNo + 1
  local dt = dtForFrame()

  for _, p in ipairs(posed or {}) do
    p._colosseumModel = nil
    p._colosseumActor = nil
    p._colosseumMatrix = nil
    p._colosseumDex = nil

    if p.entity and not p.stadiumMon then
      local okDex, dex = pcall(OverworldColosseum.resolveDex, p.entity)
      if okDex and dex and ColosseumDex.supported(dex) then
        local ok, did = pcall(prepareOne, p, dex, dt)
        if not ok or not did then
          logOnce("prepare:" .. tostring(dex),
            "Colosseum overworld model %d could not prepare this frame; using sprite", dex)
        end
      end
    end
  end

  for entity, slot in pairs(slots) do
    if frameNo - (slot.lastSeen or 0) > STALE_FRAMES then
      pcall(releaseSlot, slot)
      slots[entity] = nil
    end
  end
  return true
end

function OverworldColosseum.safePrepare(posed)
  local ok, result = pcall(OverworldColosseum.prepare, posed)
  if not ok then
    logOnce("prepare-frame", "Colosseum overworld prepare error: %s", tostring(result))
    return false
  end
  return result ~= false
end

function OverworldColosseum.draw(p)
  local actor = p and p._colosseumActor
  local matrix = p and p._colosseumMatrix
  if not (actor and matrix and PokemonActors and PokemonActors.withRenderer) then
    return false
  end
  local vp = Voxel3D and Voxel3D.vp
  if not vp then return false end

  local ok, result = pcall(PokemonActors.withRenderer, PokemonActors, vp, function()
    return actor:draw(matrix)
  end)
  if not ok then
    logOnce("draw:" .. tostring(p._colosseumDex),
      "Colosseum overworld draw failed for dex %s; using sprite", tostring(p._colosseumDex))
    return false
  end
  return result ~= false
end

function OverworldColosseum.safeDraw(p)
  local ok, result = pcall(OverworldColosseum.draw, p)
  return ok and result == true
end

function OverworldColosseum.cast(p, shadowMap)
  -- Shadow casting for Colosseum overworld models is not yet implemented.
  return false
end

function OverworldColosseum.safeCast(p, shadowMap)
  local ok, result = pcall(OverworldColosseum.cast, p, shadowMap)
  return ok and result == true
end

-- VoxelScenePatch installs the pose-level hooks (safePrepare/safeDraw/safeCast).
function OverworldColosseum.install()
  return true
end

return OverworldColosseum