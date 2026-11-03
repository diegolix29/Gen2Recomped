-- Pokemon Prism species -> National Dex.
--
-- Prism keeps its own internal species order (tools/pokeprism.sym, the
-- PokemonPalettes table): slot 13 is CHINGLING, not WEEDLE, and so on. The
-- importer stores that internal number as `def.dex`, which the engine needs
-- as-is (save conversion, the in-game Pokedex). Every model/sprite lookup in
-- this mod wants the National Dex number instead, so on Prism each species
-- gets a `def.nationalDex` taken from the Naljo Pokedex
-- (https://rijon.fandom.com/wiki/Naljo_Pok%C3%A9dex).
--
-- The five Prism-original legendaries have no National Dex number. They get
-- nationalDex = 0 and prismFakemon = true, so they are drawn as their 2D
-- sprite instead of borrowing whatever species shares their internal slot.
local V=...
local M={}

-- Internal Prism index -> National Dex (0 = Prism original). 253 is the EGG.
M.byIndex={
  [1]=1, -- BULBASAUR
  [2]=2, -- IVYSAUR
  [3]=3, -- VENUSAUR
  [4]=4, -- CHARMANDER
  [5]=5, -- CHARMELEON
  [6]=6, -- CHARIZARD
  [7]=7, -- SQUIRTLE
  [8]=8, -- WARTORTLE
  [9]=9, -- BLASTOISE
  [10]=10, -- CATERPIE
  [11]=11, -- METAPOD
  [12]=12, -- BUTTERFREE
  [13]=433, -- CHINGLING
  [14]=358, -- CHIMECHO
  [15]=325, -- TORKOAL
  [16]=16, -- PIDGEY
  [17]=17, -- PIDGEOTTO
  [18]=18, -- PIDGEOT
  [19]=276, -- TAILLOW
  [20]=277, -- SWELLOW
  [21]=21, -- SPEAROW
  [22]=22, -- FEAROW
  [23]=427, -- BUNEARY
  [24]=428, -- LOPUNNY
  [25]=25, -- PIKACHU
  [26]=26, -- RAICHU
  [27]=403, -- SHINX
  [28]=404, -- LUXIO
  [29]=405, -- LUXRAY
  [30]=309, -- ELECTRIKE
  [31]=310, -- MANECTRIC
  [32]=361, -- SNORUNT
  [33]=362, -- GLALIE
  [34]=478, -- FROSLASS
  [35]=313, -- VOLBEAT
  [36]=314, -- ILLUMISE
  [37]=37, -- VULPIX
  [38]=38, -- NINETALES
  [39]=39, -- JIGGLYPUFF
  [40]=40, -- WIGGLYTUFF
  [41]=41, -- ZUBAT
  [42]=42, -- GOLBAT
  [43]=304, -- ARON
  [44]=305, -- LAIRON
  [45]=306, -- AGGRON
  [46]=46, -- PARAS
  [47]=47, -- PARASECT
  [48]=48, -- VENONAT
  [49]=49, -- VENOMOTH
  [50]=436, -- BRONZOR
  [51]=437, -- BRONZONG
  [52]=451, -- SKORUPI
  [53]=452, -- DRAPION
  [54]=408, -- CRANIDOS
  [55]=409, -- RAMPARDOS
  [56]=410, -- SHIELDON
  [57]=411, -- BASTIODON
  [58]=58, -- GROWLITHE
  [59]=59, -- ARCANINE
  [60]=293, -- WHISMUR
  [61]=294, -- LOUDRED
  [62]=295, -- EXPLOUD
  [63]=63, -- ABRA
  [64]=64, -- KADABRA
  [65]=65, -- ALAKAZAM
  [66]=66, -- MACHOP
  [67]=67, -- MACHOKE
  [68]=68, -- MACHAMP
  [69]=69, -- BELLSPROUT
  [70]=70, -- WEEPINBELL
  [71]=71, -- VICTREEBEL
  [72]=72, -- TENTACOOL
  [73]=73, -- TENTACRUEL
  [74]=74, -- GEODUDE
  [75]=75, -- GRAVELER
  [76]=76, -- GOLEM
  [77]=77, -- PONYTA
  [78]=78, -- RAPIDASH
  [79]=79, -- SLOWPOKE
  [80]=80, -- SLOWBRO
  [81]=81, -- MAGNEMITE
  [82]=82, -- MAGNETON
  [83]=462, -- MAGNEZONE
  [84]=425, -- DRIFLOON
  [85]=426, -- DRIFBLIM
  [86]=302, -- SABLEYE
  [87]=442, -- SPIRITOMB
  [88]=353, -- SHUPPET
  [89]=354, -- BANETTE
  [90]=355, -- DUSKULL
  [91]=356, -- DUSCLOPS
  [92]=92, -- GASTLY
  [93]=93, -- HAUNTER
  [94]=94, -- GENGAR
  [95]=95, -- ONIX
  [96]=337, -- LUNATONE
  [97]=338, -- SOLROCK
  [98]=329, -- VIBRAVA
  [99]=330, -- FLYGON
  [100]=296, -- MAKUHITA
  [101]=297, -- HARIYAMA
  [102]=102, -- EXEGGCUTE
  [103]=103, -- EXEGGUTOR
  [104]=331, -- CACNEA
  [105]=332, -- CACTURNE
  [106]=106, -- HITMONLEE
  [107]=107, -- HITMONCHAN
  [108]=328, -- TRAPINCH
  [109]=109, -- KOFFING
  [110]=110, -- WEEZING
  [111]=111, -- RHYHORN
  [112]=112, -- RHYDON
  [113]=113, -- CHANSEY
  [114]=114, -- TANGELA
  [115]=115, -- KANGASKHAN
  [116]=465, -- TANGROWTH
  [117]=303, -- MAWILE
  [118]=118, -- GOLDEEN
  [119]=119, -- SEAKING
  [120]=270, -- LOTAD
  [121]=271, -- LOMBRE
  [122]=272, -- LUDICOLO
  [123]=123, -- SCYTHER
  [124]=369, -- RELICANTH
  [125]=125, -- ELECTABUZZ
  [126]=126, -- MAGMAR
  [127]=466, -- ELECTIVIRE
  [128]=467, -- MAGMORTAR
  [129]=129, -- MAGIKARP
  [130]=130, -- GYARADOS
  [131]=359, -- ABSOL
  [132]=132, -- DITTO
  [133]=133, -- EEVEE
  [134]=134, -- VAPOREON
  [135]=135, -- JOLTEON
  [136]=136, -- FLAREON
  [137]=137, -- PORYGON
  [138]=0, -- VARANEOUS
  [139]=345, -- LILEEP
  [140]=346, -- CRADILY
  [141]=347, -- ANORITH
  [142]=348, -- ARMALDO
  [143]=143, -- SNORLAX
  [144]=144, -- ARTICUNO
  [145]=145, -- ZAPDOS
  [146]=146, -- MOLTRES
  [147]=374, -- BELDUM
  [148]=375, -- METANG
  [149]=376, -- METAGROSS
  [150]=150, -- MEWTWO
  [151]=151, -- MEW
  [152]=152, -- CHIKORITA
  [153]=153, -- BAYLEEF
  [154]=154, -- MEGANIUM
  [155]=155, -- CYNDAQUIL
  [156]=156, -- QUILAVA
  [157]=157, -- TYPHLOSION
  [158]=158, -- TOTODILE
  [159]=159, -- CROCONAW
  [160]=160, -- FERALIGATR
  [161]=161, -- SENTRET
  [162]=162, -- FURRET
  [163]=280, -- RALTS
  [164]=281, -- KIRLIA
  [165]=282, -- GARDEVOIR
  [166]=475, -- GALLADE
  [167]=167, -- SPINARAK
  [168]=168, -- ARIADOS
  [169]=169, -- CROBAT
  [170]=170, -- CHINCHOU
  [171]=171, -- LANTURN
  [172]=172, -- PICHU
  [173]=477, -- DUSKNOIR
  [174]=174, -- IGGLYBUFF
  [175]=175, -- TOGEPI
  [176]=176, -- TOGETIC
  [177]=177, -- NATU
  [178]=178, -- XATU
  [179]=179, -- MAREEP
  [180]=180, -- FLAAFFY
  [181]=181, -- AMPHAROS
  [182]=468, -- TOGEKISS
  [183]=183, -- MARILL
  [184]=184, -- AZUMARILL
  [185]=322, -- NUMEL
  [186]=323, -- CAMERUPT
  [187]=320, -- WAILMER
  [188]=321, -- WAILORD
  [189]=283, -- SURSKIT
  [190]=284, -- MASQUERAIN
  [191]=285, -- SHROOMISH
  [192]=286, -- BRELOOM
  [193]=193, -- YANMA
  [194]=469, -- YANMEGA
  [195]=470, -- LEAFEON
  [196]=196, -- ESPEON
  [197]=197, -- UMBREON
  [198]=471, -- GLACEON
  [199]=199, -- SLOWKING
  [200]=200, -- MISDREAVUS
  [201]=429, -- MISMAGIUS
  [202]=333, -- SWABLU
  [203]=334, -- ALTARIA
  [204]=204, -- PINECO
  [205]=205, -- FORRETRESS
  [206]=464, -- RHYPERIOR
  [207]=207, -- GLIGAR
  [208]=208, -- STEELIX
  [209]=472, -- GLISCOR
  [210]=349, -- FEEBAS
  [211]=350, -- MILOTIC
  [212]=212, -- SCIZOR
  [213]=447, -- RIOLU
  [214]=448, -- LUCARIO
  [215]=215, -- SNEASEL
  [216]=216, -- TEDDIURSA
  [217]=217, -- URSARING
  [218]=218, -- SLUGMA
  [219]=219, -- MAGCARGO
  [220]=220, -- SWINUB
  [221]=221, -- PILOSWINE
  [222]=443, -- GIBLE
  [223]=444, -- GABITE
  [224]=445, -- GARCHOMP
  [225]=371, -- BAGON
  [226]=372, -- SHELGON
  [227]=373, -- SALAMENCE
  [228]=228, -- HOUNDOUR
  [229]=229, -- HOUNDOOM
  [230]=473, -- MAMOSWINE
  [231]=231, -- PHANPY
  [232]=232, -- DONPHAN
  [233]=233, -- PORYGON2
  [234]=474, -- PORYGONZ
  [235]=461, -- WEAVILE
  [236]=236, -- TYROGUE
  [237]=237, -- HITMONTOP
  [238]=0, -- FAMBACO
  [239]=239, -- ELEKID
  [240]=240, -- MAGBY
  [241]=700, -- SYLVEON
  [242]=242, -- BLISSEY
  [243]=383, -- GROUDON
  [244]=382, -- KYOGRE
  [245]=384, -- RAYQUAZA
  [246]=246, -- LARVITAR
  [247]=247, -- PUPITAR
  [248]=248, -- TYRANITAR
  [249]=249, -- LUGIA
  [250]=250, -- HOOH
  [251]=0, -- RAIWATO
  [252]=0, -- PHANCERO
  [254]=0, -- LIBABEEL
}

-- Name checks, so a Prism build with a different order is left alone instead
-- of getting wrong models: the table is only applied when these all agree.
local NAME_AT={
  [1]="BULBASAUR",[13]="CHINGLING",[50]="BRONZOR",[138]="VARANEOUS",
  [152]="CHIKORITA",[238]="FAMBACO",[241]="SYLVEON",[246]="LARVITAR",
  [252]="PHANCERO",[254]="LIBABEEL",
}

local function norm(s) return (tostring(s or ""):upper():gsub("[^A-Z0-9]","")) end

local function engineRequire(name)
  return pcall(V.engineRequire or require,name)
end

function M.isPrism()
  local ok,GameVersion=engineRequire("src.core.GameVersion")
  if not ok or type(GameVersion)~="table" then return false end
  local id=type(GameVersion.get)=="function" and GameVersion.get() or GameVersion.current
  return id=="prism"
end

local function orderMatches(defs)
  local seen=0
  for _,def in pairs(defs) do
    if type(def)=="table" then
      local want=NAME_AT[tonumber(def.index or def.dex)]
      if want then
        if norm(def.name)~=want then return false,def end
        seen=seen+1
      end
    end
  end
  return seen>0
end

local function log(level,fmt,...)
  local l=V.mod and V.mod.log
  if l and type(l[level])=="function" then pcall(l[level],l,fmt,...) end
end

local done=setmetatable({},{__mode="k"})

-- Idempotent; one table lookup after the first call for a data.pokemon table.
function M.apply(defs)
  if type(defs)~="table" then return false end
  if done[defs]~=nil then return done[defs] end
  if not M.isPrism() then return false end  -- not cached: the game can change
  local ok,bad=orderMatches(defs)
  if not ok then
    done[defs]=false
    log("warn","PrismNationalDex: species order does not match the known Prism build (%s); left unmapped",
      tostring(bad and bad.name))
    return false
  end
  local n=0
  for _,def in pairs(defs) do
    if type(def)=="table" then
      local nat=M.byIndex[tonumber(def.index or def.dex)]
      if nat then
        def.nationalDex=nat
        def.prismFakemon=nat==0 or nil
        n=n+1
      end
    end
  end
  done[defs]=true
  log("info","PrismNationalDex: mapped %d Prism species to National Dex",n)
  return true
end

local function liveData(game)
  local data=type(game)=="table" and game.data or nil
  if not data then
    local ok,Game=engineRequire("src.core.Game")
    data=ok and type(Game)=="table" and Game.data or nil
  end
  if not data then
    local ok,Data=engineRequire("src.core.Data")
    data=ok and type(Data)=="table" and Data or nil
  end
  return data
end

-- Apply to the live game data, wherever it is reachable.
function M.applyLive(game)
  local data=liveData(game)
  return M.apply(data and data.pokemon)
end

-- Overworld code (wild spawns, roamers, followers) turns Gen 2 species ids
-- like "SPECIES_013" into a dex number by reading the digits. On Prism those
-- digits are Prism's internal order, so this answers the National Dex instead.
-- `pattern` is the caller's own match pattern (one capture of the digits).
-- Returns the dex (number or digit string), or nil when `s` is not such an id
-- or is a Prism-original species with no National Dex number.
function M.speciesConst(s,pattern)
  if type(s)~="string" then return nil end
  local digits=s:match(pattern or "SPECIES_(%d+)")
  if not digits then return nil end
  local data=liveData()
  local defs=data and data.pokemon
  if type(defs)=="table" and M.apply(defs) then
    local def=defs["SPECIES_"..digits] or defs[s]
    local nat=type(def)=="table" and tonumber(def.nationalDex)
    if nat then return nat>0 and nat or nil end
  end
  return digits
end

return M
