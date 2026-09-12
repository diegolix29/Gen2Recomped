-- Read-only National Dex and colour identity, shared by battle/cache consumers.
local V=...
local M={version=1}

-- Gen3 species name to National Dex mapping for Pokemon Colosseum compatibility
-- These are Pokemon that appear in Gen3 games but may not have dex/index fields in their definitions
local GEN3_SPECIES_MAP={
  -- Hoenn starters
  TREECKO=252,GROVYLE=253,SCEPTILE=254,
  TORCHIC=255,COMBUSKEN=256,BLAZIKEN=257,
  MUDKIP=258,MARSHTOMP=259,SWAMPERT=260,
  -- Common Hoenn Pokemon
  POOCHYENA=261,MIGHTYENA=262,
  ZIGZAGOON=263,LINOONE=264,
  WURMPLE=265,SILCOON=266,BEAUTIFLY=267,CASCOON=268,DUSTOX=269,
  LOTAD=270,LOMBRE=271,LUDICOLO=272,
  SEEDOT=273,NUZLEAF=274,SHIFTRY=275,
  TAILLOW=276,SWELLOW=277,
  WINGULL=278,PELIPPER=279,
  RALTS=280,KIRLIA=281,GARDEVOIR=282,
  SURSKIT=283,MASQUERAIN=284,
  SHROOMISH=285,BRELOOM=286,
  SLAKOTH=287,VIGOROTH=288,SLAKING=289,
  NINCADA=290,NINJASK=291,SHEDINJA=292,
  WHISMUR=293,LOUDRED=294,EXPLOUD=295,
  MAKUHITA=296,HARIYAMA=297,
  AZURILL=298,
  NOSEPASS=299,
  SKITTY=300,DELCATTY=301,
  SABLEYE=302,
  MAWILE=303,
  ARON=304,LAIRON=305,AGGRON=306,
  MEDITITE=307,MEDICHAM=308,
  ELECTRIKE=309,MANECTRIC=310,
  PLUSLE=311,
  MINUN=312,
  VOLBEAT=313,
  ILLUMISE=314,
  ROSELIA=315,
  GULPIN=316,SWALOT=317,
  CARVANHA=318,SHARPEDO=319,
  WAILMER=320,WAILORD=321,
  NUMEL=322,CAMERUPT=323,
  TORKOAL=324,
  SPOINK=325,GRUMPIG=326,
  SPINDA=327,
  TRAPINCH=328,VIBRAVA=329,FLYGON=330,
  CACNEA=331,CACTURNE=332,
  SWABLU=333,ALTARIA=334,
  ZANGOOSE=335,
  SEVIPER=336,
  LUNATONE=337,
  SOLROCK=338,
  BARBOACH=339,WHISCASH=340,
  CORPHISH=341,CRAWDAUNT=342,
  BALTOY=343,CLAYDOL=344,
  LILEEP=345,CRADILY=346,
  ANORITH=347,ARMALDO=348,
  FEEBAS=349,MILOTIC=350,
  CASTFORM=351,
  KECLEON=352,
  SHUPPET=353,BANETTE=354,
  DUSKULL=355,DUSCLOPS=356,
  TROPIUS=357,
  CHIMECHO=358,
  ABSOL=359,
  WYNAUT=360,
  SNORUNT=361,GLALIE=362,
  SPHEAL=363,SEALEO=364,WALREIN=365,
  CLAMPERL=366,HUNTAIL=367,GOREBYSS=368,
  RELICANTH=369,
  LUVDISC=370,
  BAGON=371,SHELGON=372,SALAMENCE=373,
  BELDUM=374,METANG=375,METAGROSS=376,
  REGIROCK=377,REGICE=378,REGISTEEL=379,
  LATIAS=380,
  LATIOS=381,
  KYOGRE=382,
  GROUDON=383,
  RAYQUAZA=384,
  JIRACHI=385,
  DEOXYS=386,
}

function M.resolve(game,battler)
  if type(battler)~="table" then return nil,"Pokemon identity unavailable" end
  local mon=type(battler.mon)=="table" and battler.mon or battler
  local species=mon.species or mon.id
  local defs=game and game.data and game.data.pokemon
  local def=defs and (defs[species] or defs[tostring(species)])
  local dex=tonumber(def and (def.dex or def.index or def.number))
    or tonumber(mon.dex or mon.speciesIndex or mon.nationalDex)
  if not dex and type(species)=="number" then dex=species end
  if not dex and defs and species then
    local wanted=tostring(species):upper()
    for _,candidate in pairs(defs) do
      if type(candidate)=="table" and (tostring(candidate.id):upper()==wanted
          or tostring(candidate.name):upper()==wanted) then
        dex=tonumber(candidate.dex or candidate.index or candidate.number);break
      end
    end
  end
  -- Try Gen3 species mapping as a fallback
  if not dex and type(species)=="string" then
    dex=GEN3_SPECIES_MAP[species:upper()]
  end
  -- Allow dex > 251 for Gen 3+ Pokemon - Stadium will reject them and fall back to sprites
  if not dex or dex%1~=0 or dex<1 then
    return nil,"No supported National Dex mapping for "..tostring(species)
  end
  -- For Gen3+ Pokemon (dex > 251), return the dex number but mark as unsupported for Stadium
  -- The Stadium system will then fall back to sprites
  return dex,V.ShinySupport.variant(battler)
end
return M
