-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S 123 ABILITIES, BY THE ID THE SPECIES TABLE STORES.
--
-- WHY THIS EXISTS.  `Gen4Species` reads bytes 22 and 23 of a species record as
-- `abilities = { id, id }`, and every table in `src/battle/Abilities.lua`
-- compares against a NAME -- "WATER_ABSORB", "SAND_VEIL", "INTIMIDATE".  So a
-- number never matched anything and NO ABILITY DID ANYTHING IN SINNOH AT ALL.
-- Measured before the fix: of every ability entry across all 508 species,
-- ZERO were names.
--
-- THIS IS THE THIRD TIME THIS EXACT BUG HAS APPEARED IN THIS PORT, in a third
-- field of the same shape: `move.effect` was a number where the battle
-- dispatched on a name ([[gen4_move_effects]]), `move.type` was a number where
-- `Damage` wanted a name ([[gen4_type_system]]), and neither search found this
-- one. Anything the cartridge stores as an id and this engine dispatches on by
-- name is worth checking before it is reported from play.
--
-- WHERE THE NAMES COME FROM, and why they are not a transcription.
--
--   (1) pokeplatinum's `generated/abilities.txt` is an ORDERED list, one name
--       a line, index 0 `ABILITY_NONE` through index 123.
--   (2) Its `res/pokemon/<name>/data.json` names each species' two abilities
--       independently -- Chimchar's are `["ABILITY_BLAZE", "ABILITY_NONE"]`.
--
-- Joining the cartridge's own numeric species table to (2) by SPECIES NAME and
-- resolving through (1): **492 species agree, 0 disagree.** The four that do
-- not join are name-spelling misses, not data ones -- species 0 (the "-----"
-- placeholder), both NIDORAN (gender symbols) and FARFETCH'D (a curly
-- apostrophe) -- and their resolved names are Poison Point / Rivalry and Keen
-- Eye / Inner Focus, which are right.
--
-- And the table CLOSES: the species table uses 124 distinct ids, the highest
-- is 123, and every one of them has a name here. No id falls off the end.
--
-- THE `ABILITY_` PREFIX IS STRIPPED because that is the spelling the engine
-- already uses -- `Abilities.lua` has SPEED_BOOST, WATER_ABSORB, SAND_STREAM
-- and the rest written exactly that way, from the Gen 3 side.
--
-- INDEX 0 IS "NONE" AND IS A SENTINEL, NOT AN ABILITY.  See `Gen4Abilities.of`
-- below and `Abilities.of` for the rule it stands for.

local Gen4Abilities = {}

-- 0-based, as the cartridge stores it: NAMES[0] is the sentinel.
local NAMES = {
  [0] = "NONE",
  "STENCH",          "DRIZZLE",         "SPEED_BOOST",     "BATTLE_ARMOR",
  "STURDY",          "DAMP",            "LIMBER",          "SAND_VEIL",
  "STATIC",          "VOLT_ABSORB",     "WATER_ABSORB",    "OBLIVIOUS",
  "CLOUD_NINE",      "COMPOUND_EYES",   "INSOMNIA",        "COLOR_CHANGE",
  "IMMUNITY",        "FLASH_FIRE",      "SHIELD_DUST",     "OWN_TEMPO",
  "SUCTION_CUPS",    "INTIMIDATE",      "SHADOW_TAG",      "ROUGH_SKIN",
  "WONDER_GUARD",    "LEVITATE",        "EFFECT_SPORE",    "SYNCHRONIZE",
  "CLEAR_BODY",      "NATURAL_CURE",    "LIGHTNING_ROD",   "SERENE_GRACE",
  "SWIFT_SWIM",      "CHLOROPHYLL",     "ILLUMINATE",      "TRACE",
  "HUGE_POWER",      "POISON_POINT",    "INNER_FOCUS",     "MAGMA_ARMOR",
  "WATER_VEIL",      "MAGNET_PULL",     "SOUNDPROOF",      "RAIN_DISH",
  "SAND_STREAM",     "PRESSURE",        "THICK_FAT",       "EARLY_BIRD",
  "FLAME_BODY",      "RUN_AWAY",        "KEEN_EYE",        "HYPER_CUTTER",
  "PICKUP",          "TRUANT",          "HUSTLE",          "CUTE_CHARM",
  "PLUS",            "MINUS",           "FORECAST",        "STICKY_HOLD",
  "SHED_SKIN",       "GUTS",            "MARVEL_SCALE",    "LIQUID_OOZE",
  "OVERGROW",        "BLAZE",           "TORRENT",         "SWARM",
  "ROCK_HEAD",       "DROUGHT",         "ARENA_TRAP",      "VITAL_SPIRIT",
  "WHITE_SMOKE",     "PURE_POWER",      "SHELL_ARMOR",     "AIR_LOCK",
  "TANGLED_FEET",    "MOTOR_DRIVE",     "RIVALRY",         "STEADFAST",
  "SNOW_CLOAK",      "GLUTTONY",        "ANGER_POINT",     "UNBURDEN",
  "HEATPROOF",       "SIMPLE",          "DRY_SKIN",        "DOWNLOAD",
  "IRON_FIST",       "POISON_HEAL",     "ADAPTABILITY",    "SKILL_LINK",
  "HYDRATION",       "SOLAR_POWER",     "QUICK_FEET",      "NORMALIZE",
  "SNIPER",          "MAGIC_GUARD",     "NO_GUARD",        "STALL",
  "TECHNICIAN",      "LEAF_GUARD",      "KLUTZ",           "MOLD_BREAKER",
  "SUPER_LUCK",      "AFTERMATH",       "ANTICIPATION",    "FOREWARN",
  "UNAWARE",         "TINTED_LENS",     "FILTER",          "SLOW_START",
  "SCRAPPY",         "STORM_DRAIN",     "ICE_BODY",        "SOLID_ROCK",
  "SNOW_WARNING",    "HONEY_GATHER",    "FRISK",           "RECKLESS",
  "MULTITYPE",       "FLOWER_GIFT",     "BAD_DREAMS",
}

Gen4Abilities.NAMES = NAMES
Gen4Abilities.COUNT = 124

-- The name for an id, or nil for the sentinel and for anything out of range.
--
-- NIL RATHER THAN "NONE" IS THE POINT.  The cartridge's rule is in
-- `pokemon.c`: `if (ability2 != ABILITY_NONE) { ability = personality & 1 ?
-- ability2 : ability1 } else { ability = ability1 }`. The port expresses "no
-- second ability" as a HOLE in the list, the way the Gen 3 extractor already
-- does, so `list[slot] or list[1]` falls through on its own. Writing the
-- sentinel out as a value instead is what made half of Sinnoh's Pokemon
-- announce "%s's / 0!" -- in Lua, 0 is TRUTHY, so the `or` never fired.
function Gen4Abilities.name(id)
  local n = NAMES[tonumber(id) or -1]
  if n == nil or n == "NONE" then return nil end
  return n
end

-- A species' ability list in the shape the battle reads: names, with an absent
-- second ability left as a hole rather than a zero.
function Gen4Abilities.list(first, second)
  local out = {}
  out[1] = Gen4Abilities.name(first)
  out[2] = Gen4Abilities.name(second)
  -- A species whose FIRST ability is the sentinel would otherwise return a
  -- list starting at [2]; nothing in Platinum does that, and if a hack did,
  -- a one-ability list is the right answer rather than a gap at the front.
  if out[1] == nil and out[2] ~= nil then out[1], out[2] = out[2], nil end
  return out
end

return Gen4Abilities
