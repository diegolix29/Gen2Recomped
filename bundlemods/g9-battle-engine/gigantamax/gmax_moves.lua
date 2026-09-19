-- Phase 3 -- the 32 Gigantamax-exclusive moves' data (the other 2 G-Max
-- moves in our 33-species roster, Urshifu's Single Strike and Rapid
-- Strike styles, reuse dynamax's own already-registered
-- MOD_GMAX_ONE_BLOW / MOD_GMAX_RAPID_FLOW -- see gmax_data.lua for why:
-- dynamax's own main.lua already registers those two under its own ids,
-- "reserved for future Gigantamax species/form definitions... even
-- though no species currently converts into them" -- this mod is that
-- future definition, so it reuses dynamax's existing, fully-working
-- registration, including the Max Guard bypass wiring, rather than
-- duplicating it under a different id).
--
-- This table is data only -- main.lua's installGigantamaxMoves hands it
-- to dynamax's own exports.registerGmaxMoves, which owns the actual
-- mod.content.moves:register call (see dynamax/main.lua's "Gigantamax
-- moves" section). Per-species assignment (which Pokémon gets which
-- G-Max move) is fed the same way, via gmax_data.lua's own gmaxMove
-- field and dynamax's exports.setGigantamaxMove -- both are real, wired,
-- and reach a Dynamaxed Pokémon's actual move list in battle, closing
-- the gap this comment used to describe as open (dynamax's own
-- computeMaxMoveId now takes an optional species parameter for exactly
-- this).
--
-- Source: Pokemon_Stats/moves_dynamax.txt. Every single G-Max move's
-- entire real function IS its FunctionCode (field-wide multi-turn damage,
-- side-wide status infliction, hazard-setting, etc.) -- none are a bare
-- damage roll the way some of Phase 2's moves were. This engine's real
-- primitives for any of that (a field/side-wide, multi-turn effect
-- system) were not found anywhere in either reference mod, so every one
-- of these registers as a stub: real name/type/category/pp/power (power
-- is literal Power=1 from the source where that's what it says -- the
-- same runtime-computed-elsewhere placeholder convention Dynamax's own
-- generic Max Move templates use, not a value this file invents) with
-- effect="NO_ADDITIONAL_EFFECT". functionCode is kept as documentation
-- of exactly what's missing, same convention as moves_new.lua -- the
-- move now reliably REACHES battle, it just does nothing beyond a bare
-- hit yet.
return {
  GMAXBEFUDDLE = { name = "G-Max Befuddle", type = "BUG", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "PoisonParalyzeOrSleepTargetSide" },
  GMAXCANNONADE = { name = "G-Max Cannonade", type = "WATER", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "StartCannonadeOnFoeSide" },
  GMAXCENTIFERNO = { name = "G-Max Centiferno", type = "FIRE", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "BindTargetSideUserCanSwitch" },
  GMAXCHISTRIKE = { name = "G-Max Chi Strike", type = "FIGHTING", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "UserSideCriticalBoost1" },
  GMAXCICLON = { name = "G-Max Cyclone", type = "GRASS", category = "special", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "LowerTargetSideAccuracy1" },
  GMAXCUDDLE = { name = "G-Max Cuddle", type = "NORMAL", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "GMAX_CUDDLE_EFFECT", functionCode = "InfatuateTargetSide" },
  GMAXDEPLETION = { name = "G-Max Depletion", type = "DRAGON", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "LowerPPOfTargetSideLastMoveBy2" },
  GMAXDRUMSOLO = { name = "G-Max Drum Solo", type = "GRASS", category = "physical", power = 160, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "IgnoreTargetAbility" },
  GMAXFINALE = { name = "G-Max Finale", type = "FAIRY", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "HealUserSideOneSixthOfTotalHP" },
  GMAXFIREBALL = { name = "G-Max Fireball", type = "FIRE", category = "physical", power = 160, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "IgnoreTargetAbility" },
  GMAXFOAMBURST = { name = "G-Max Foam Burst", type = "WATER", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "LowerTargetSideSpeed2" },
  GMAXGOLDRUSH = { name = "G-Max Gold Rush", type = "NORMAL", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "ConfuseTargetSideAddMoney" },
  GMAXGRAVITAS = { name = "G-Max Gravitas", type = "PSYCHIC", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "DamageTargetStartGravity" },
  GMAXHYDROSNIPE = { name = "G-Max Hydrosnipe", type = "WATER", category = "physical", power = 160, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "IgnoreTargetAbility" },
  GMAXMALODOR = { name = "G-Max Malodor", type = "POISON", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "PoisonTargetSide" },
  GMAXMELTDOWN = { name = "G-Max Meltdown", type = "STEEL", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "DisableTargetSideUsingSameMoveConsecutively" },
  GMAXREPLENISH = { name = "G-Max Replenish", type = "NORMAL", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "RestoreUserSideConsumedBerries" },
  GMAXRESONANCE = { name = "G-Max Resonance", type = "ICE", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "DamageTargetStartWeakenDamageAgainstUserSide" },
  GMAXSANDBLAST = { name = "G-Max Sandblast", type = "GROUND", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "BindTargetSideUserCanSwitch" },
  GMAXSMITE = { name = "G-Max Smite", type = "FAIRY", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "ConfuseTargetSide" },
  GMAXSNOOZE = { name = "G-Max Snooze", type = "DARK", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "DamageTargetSleepTargetNextTurn" },
  GMAXSTEELSURGE = { name = "G-Max Steelsurge", type = "STEEL", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "DamageTargetAddSteelsurgeToFoeSide" },
  GMAXSTONESURGE = { name = "G-Max Stonesurge", type = "ROCK", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "DamageTargetAddStealthRocksToFoeSide" },
  GMAXSTUNSHOCK = { name = "G-Max Stun Shock", type = "ELECTRIC", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "PoisonOrParalyzeTargetSide" },
  GMAXSWEETNESS = { name = "G-Max Sweetness", type = "GRASS", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "CureStatusConditionsUsersSide" },
  GMAXTARTNESS = { name = "G-Max Tartness", type = "GRASS", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "LowerTargetSideEva1" },
  GMAXTERROR = { name = "G-Max Terror", type = "GHOST", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "TrapTargetSideInBattle" },
  GMAXVINELASH = { name = "G-Max Vine Lash", type = "GRASS", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "StartVineLashOnFoeSide" },
  GMAXVOLCALITH = { name = "G-Max Volcalith", type = "ROCK", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "StartVolcalithOnFoeSide" },
  GMAXVOLTCRASH = { name = "G-Max Volt Crash", type = "ELECTRIC", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "ParalyzeTargetSide" },
  GMAXWILDFIRE = { name = "G-Max Wildfire", type = "FIRE", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "StartWildfireOnFoeSide" },
  GMAXWINDRAGE = { name = "G-Max Wind Rage", type = "FLYING", category = "physical", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT", functionCode = "RemoveSideEffectsAndTerrain" },
}
