-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S 146 HOLD EFFECTS, BY THE ID THE ITEM TABLE STORES.
--
-- THE FOURTH TIME THIS PORT HAS SHIPPED AN ID WHERE THE ENGINE WANTS A NAME,
-- after `move.effect`, `move.type` and `species.abilities` -- and the one the
-- pass-107 audit (`tools/gen4_idname_check.lua`) found rather than a play
-- report. `battle/HoldItems.lua` compares against 33 names; every one of the
-- 446 Gen 4 items carried a number, 158 of them non-zero, and not one held
-- item did anything in Sinnoh.
--
-- WHY THIS IS NOT A PREFIX STRIP, and why it took a table rather than a rule.
--
-- pokeplatinum names a hold effect after its BEHAVIOUR; this engine names it
-- after the ITEM. `HOLD_EFFECT_HP_RESTORE_GRADUAL` is LEFTOVERS,
-- `HOLD_EFFECT_CHOICE_ATK` is CHOICE_BAND, `HOLD_EFFECT_CUBONE_ATK_UP` is
-- THICK_CLUB. That is the same split the move effects had, and it means the
-- join has to go through ITEM IDENTITY, which is stronger than any assumption
-- about numbering.
--
-- HOW EACH ROW WAS SETTLED. Every non-zero id was listed with the items that
-- carry it and its pokeplatinum name, and the mapping read off THAT rather
-- than from memory -- which is why each row below carries the item it was
-- decided by. Joining the cache's items to `res/items/data/*.json` by item
-- name: 438 of 446 join, 146 distinct ids resolved, and NO ID CARRIES MORE
-- THAN ONE pokeplatinum name. The id determines the effect with no ambiguity.
--
-- CHECKED THREE WAYS: all 33 engine names are mapped, none is mapped twice,
-- and -- the one that matters for the 113 ids the engine does not implement --
-- NO UNMAPPED ID'S POKEPLATINUM NAME IS ALSO AN ENGINE NAME. So the rest can
-- carry their own names without any of them accidentally firing an engine
-- rule.
--
-- WHAT IS DELIBERATELY LEFT UNMAPPED, because a MIS-mapped hold effect does
-- the WRONG thing and that is worse than doing nothing:
--
--   * id 13, Sitrus Berry (`HP_PCT_RESTORE`). The engine's RESTORE_HP heals a
--     FLAT `param`, which is right for Oran's 10 and Berry Juice's 20 and
--     wrong for Sitrus, whose 25 is a PERCENTAGE. Mapping it would heal 25 HP.
--     It stays silent until the engine has a percentage rule.
--   * the five weather rocks, the plates, the Choice Scarf and Specs, Life
--     Orb, Focus Sash and the rest of Sinnoh's own items -- the engine has no
--     rule for them at all, so they carry their pokeplatinum name and read as
--     work rather than as integers.
--
-- INDEX 0 IS "NONE" AND IS A SENTINEL, NOT AN EFFECT.

local Gen4HoldEffects = {}

-- WHAT THE ENGINE KNOWS: { engine name, pokeplatinum name, the item that
-- settled it }. The second and third columns are not used at runtime; they are
-- the evidence, kept beside the claim.
local ENGINE = {
  [1] = { "RESTORE_HP", "HP_RESTORE", "Oran Berry / Berry Juice" },
  [5] = { "CURE_PAR", "PRZ_RESTORE", "Cheri Berry" },
  [8] = { "CURE_BRN", "BRN_RESTORE", "Rawst Berry" },
  [10] = { "RESTORE_PP", "PP_RESTORE", "Leppa Berry" },
  [11] = { "CURE_CONFUSION", "CONFUSE_RESTORE", "Persim Berry" },
  [12] = { "CURE_STATUS", "STATUS_RESTORE", "Lum Berry" },
  [14] = { "CONFUSE_SPICY", "HP_RESTORE_SPICY", "Figy Berry" },
  [17] = { "CONFUSE_BITTER", "HP_RESTORE_BITTER", "Aguav Berry" },
  [36] = { "ATTACK_UP", "PINCH_ATK_UP", "Liechi Berry" },
  [39] = { "SP_ATTACK_UP", "PINCH_SPATK_UP", "Petaya Berry" },
  [41] = { "CRITICAL_UP", "PINCH_CRITRATE_UP", "Lansat Berry" },
  [42] = { "RANDOM_STAT_UP", "PINCH_RANDOM_UP", "Starf Berry" },
  [48] = { "EVASION_UP", "ACC_REDUCE", "BrightPowder / Lax Incense" },
  [49] = { "RESTORE_STATS", "STATDOWN_RESTORE", "White Herb" },
  [54] = { "CURE_ATTRACT", "HEAL_INFATUATION", "Mental Herb" },
  [55] = { "CHOICE_BAND", "CHOICE_ATK", "Choice Band" },
  [57] = { "BUG_POWER", "STRENGTHEN_BUG", "SilverPowder" },
  [60] = { "SOUL_DEW", "LATI_SPECIAL", "Soul Dew" },
  [61] = { "DEEP_SEA_TOOTH", "CLAMPERL_SPATK", "DeepSeaTooth" },
  [62] = { "DEEP_SEA_SCALE", "CLAMPERL_SPDEF", "DeepSeaScale" },
  [64] = { "PREVENT_EVOLVE", "NO_EVOLVE", "Everstone" },
  [67] = { "SCOPE_LENS", "CRITRATE_UP", "Scope Lens / Razor Claw" },
  [69] = { "LEFTOVERS", "HP_RESTORE_GRADUAL", "Leftovers" },
  [71] = { "LIGHT_BALL", "PIKA_SPATK_UP", "Light Ball" },
  [73] = { "ROCK_POWER", "STRENGTHEN_ROCK", "Hard Stone / Rock Incense" },
  [76] = { "FIGHTING_POWER", "STRENGTHEN_FIGHT", "Black Belt" },
  [78] = { "WATER_POWER", "STRENGTHEN_WATER", "Mystic Water / Sea, Wave Incense" },
  [81] = { "ICE_POWER", "STRENGTHEN_ICE", "NeverMeltIce" },
  [84] = { "FIRE_POWER", "STRENGTHEN_FIRE", "Charcoal" },
  [89] = { "LUCKY_PUNCH", "CHANSEY_CRITRATE_UP", "Lucky Punch" },
  [90] = { "METAL_POWDER", "DITTO_DEF_UP", "Metal Powder" },
  [91] = { "THICK_CLUB", "CUBONE_ATK_UP", "Thick Club" },
  [92] = { "STICK", "FARFETCHD_CRITRATE_UP", "Stick" },
}

-- Everything else, by its own name. 1-based array, id 1 first.
local PRET = {
  "HP_RESTORE",                        "GIRATINA_BOOST",                    "DIALGA_BOOST",
  "PALKIA_BOOST",                      "PRZ_RESTORE",                       "SLP_RESTORE",
  "PSN_RESTORE",                       "BRN_RESTORE",                       "FRZ_RESTORE",
  "PP_RESTORE",                        "CONFUSE_RESTORE",                   "STATUS_RESTORE",
  "HP_PCT_RESTORE",                    "HP_RESTORE_SPICY",                  "HP_RESTORE_DRY",
  "HP_RESTORE_SWEET",                  "HP_RESTORE_BITTER",                 "HP_RESTORE_SOUR",
  "WEAKEN_SE_FIRE",                    "WEAKEN_SE_WATER",                   "WEAKEN_SE_ELECTRIC",
  "WEAKEN_SE_GRASS",                   "WEAKEN_SE_ICE",                     "WEAKEN_SE_FIGHT",
  "WEAKEN_SE_POISON",                  "WEAKEN_SE_GROUND",                  "WEAKEN_SE_FLYING",
  "WEAKEN_SE_PSYCHIC",                 "WEAKEN_SE_BUG",                     "WEAKEN_SE_ROCK",
  "WEAKEN_SE_GHOST",                   "WEAKEN_SE_DRAGON",                  "WEAKEN_SE_DARK",
  "WEAKEN_SE_STEEL",                   "WEAKEN_NORMAL",                     "PINCH_ATK_UP",
  "PINCH_DEF_UP",                      "PINCH_SPEED_UP",                    "PINCH_SPATK_UP",
  "PINCH_SPDEF_UP",                    "PINCH_CRITRATE_UP",                 "PINCH_RANDOM_UP",
  "HP_RESTORE_SE",                     "PINCH_ACC_UP",                      "PINCH_PRIORITY",
  "RECOIL_PHYSICAL",                   "RECOIL_SPECIAL",                    "ACC_REDUCE",
  "STATDOWN_RESTORE",                  "EVS_UP_SPEED_DOWN",                 "EXP_SHARE",
  "SOMETIMES_PRIORITY",                "FRIENDSHIP_UP",                     "HEAL_INFATUATION",
  "CHOICE_ATK",                        "SOMETIMES_FLINCH",                  "STRENGTHEN_BUG",
  "MONEY_UP",                          "ENCOUNTERS_DOWN",                   "LATI_SPECIAL",
  "CLAMPERL_SPATK",                    "CLAMPERL_SPDEF",                    "FLEE",
  "NO_EVOLVE",                         "MAYBE_ENDURE",                      "EXP_UP",
  "CRITRATE_UP",                       "STRENGTHEN_STEEL",                  "HP_RESTORE_GRADUAL",
  "EVOLVE_SEADRA",                     "PIKA_SPATK_UP",                     "STRENGTHEN_GROUND",
  "STRENGTHEN_ROCK",                   "STRENGTHEN_GRASS",                  "STRENGTHEN_DARK",
  "STRENGTHEN_FIGHT",                  "STRENGTHEN_ELECTRIC",               "STRENGTHEN_WATER",
  "STRENGTHEN_FLYING",                 "STRENGTHEN_POISON",                 "STRENGTHEN_ICE",
  "STRENGTHEN_GHOST",                  "STRENGTHEN_PSYCHIC",                "STRENGTHEN_FIRE",
  "STRENGTHEN_DRAGON",                 "STRENGTHEN_NORMAL",                 "EVOLVE_PORYGON",
  "HP_RESTORE_ON_DMG",                 "CHANSEY_CRITRATE_UP",               "DITTO_DEF_UP",
  "CUBONE_ATK_UP",                     "FARFETCHD_CRITRATE_UP",             "ACCURACY_UP",
  "POWER_UP_PHYS",                     "POWER_UP_SPEC",                     "POWER_UP_SE",
  "EXTEND_SCREENS",                    "HP_DRAIN_ON_ATK",                   "CHARGE_SKIP",
  "PSN_USER",                          "BRN_USER",                          "DITTO_SPEED_UP",
  "ENDURE",                            "ACCURACY_UP_SLOWER",                "BOOST_REPEATED",
  "SPEED_DOWN_GROUNDED",               "PRIORITY_DOWN",                     "RECIPROCATE_INFAT",
  "HP_RESTORE_PSN_TYPE",               "EXTEND_HAIL",                       "EXTEND_SANDSTORM",
  "EXTEND_SUN",                        "EXTEND_RAIN",                       "EXTEND_TRAPPING",
  "CHOICE_SPEED",                      "DMG_USER_CONTACT_XFR",              "LVLUP_ATK_EV_UP",
  "LVLUP_DEF_EV_UP",                   "LVLUP_SPATK_EV_UP",                 "LVLUP_SPDEF_EV_UP",
  "LVLUP_SPEED_EV_UP",                 "LVLUP_HP_EV_UP",                    "SWITCH",
  "LEECH_BOOST",                       "CHOICE_SPATK",                      "ARCEUS_FIRE",
  "ARCEUS_WATER",                      "ARCEUS_ELECTRIC",                   "ARCEUS_GRASS",
  "ARCEUS_ICE",                        "ARCEUS_FIGHTING",                   "ARCEUS_POISON",
  "ARCEUS_GROUND",                     "ARCEUS_FLYING",                     "ARCEUS_PSYCHIC",
  "ARCEUS_BUG",                        "ARCEUS_ROCK",                       "ARCEUS_GHOST",
  "ARCEUS_DRAGON",                     "ARCEUS_DARK",                       "ARCEUS_STEEL",
  "EVOLVE_RHYDON",                     "EVOLVE_ELECTABUZZ",                 "EVOLVE_MAGMAR",
  "EVOLVE_PORYGON2",                   "EVOLVE_DUSCLOPS",
}

Gen4HoldEffects.ENGINE = ENGINE
Gen4HoldEffects.PRET = PRET
Gen4HoldEffects.COUNT = #PRET

-- The name for an id: the engine's where there is one, otherwise the
-- cartridge's own. Nil for the sentinel and for anything out of range, so an
-- absent hold effect is a HOLE rather than the string "NONE" -- the same shape
-- `Gen4Abilities` writes, and for the same reason.
function Gen4HoldEffects.name(id)
  id = tonumber(id)
  if not id or id <= 0 then return nil end
  local row = ENGINE[id]
  if row then return row[1] end
  return PRET[id]
end

return Gen4HoldEffects
