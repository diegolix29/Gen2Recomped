-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Pokemon Platinum's battle rules.
--
-- RulesetDefaults pointed generation 4 at `gen3_emerald` and said so in the
-- file: "GEN 4 TAKES GEN 3'S, and that is a judgement rather than a reading".
-- This file is the reading.  Every constant below was taken out of
-- pokeplatinum -- the line is named beside it -- and the ones that came back
-- IDENTICAL to Hoenn's are written out here anyway rather than left to be
-- inherited, because a field that is absent reads as "nobody looked" and a
-- field that is present with a citation reads as "somebody did".
--
-- SO: WHAT ACTUALLY CHANGED IN GEN 4, of the things this engine models?
--
--   ONE THING.  The spread reduction.  Everything else in the list below
--   measured the same as Emerald, which is itself the finding -- Gen 4's
--   famous changes (the physical/special split, abilities, held items) are
--   carried by the MOVE AND SPECIES DATA and by move effects, not by these
--   constants, and the split in particular is already live: it arrives on
--   each move record as `class` and `src/battle/Damage.lua` reads it.
--
-- What is deliberately NOT claimed here: Platinum's ability and held-item
-- hooks, its own rounding inside DamageCalc's later stages, and Sniper's x3
-- crit.  Those are not ruleset fields in this engine and putting them here
-- would be writing a promise the engine does not keep.

return {
  name = "gen4_platinum",

  -- Accuracy is a percentage out of 100; there is no 1/256 miss.
  oneIn256Miss = false,

  -- Crit is a STAGE LADDER, and it is Emerald's ladder exactly:
  -- `sCriticalStageRates[] = { 16, 8, 4, 3, 2 }` at battle_lib.c:7097, each
  -- value implicitly 1/N, the effective stage clamped to 4 at :7130, and the
  -- roll `RandNext() % rate == 0` at :7134.  Focus Energy contributes +2 and
  -- a crit-rate item +1 in the same sum at :7123.
  critStages = true,
  critUsesBaseSpeed = false,

  -- `criticalMul = 2` at :7139 -- a crit doubles the DAMAGE.  (Sniper raises
  -- it to 3 at :7142; this engine has no ruleset field for that, so Sniper is
  -- a move-effect job and is not pretended at here.)
  critMultiplier = 2,

  -- Gen 4 keeps Gen 3's selective handling: the raw stat is used only where
  -- the stage would work against the attacker, not wholesale.
  critIgnoresStages = false,

  -- ---- THE ONE REAL CHANGE: SPREAD MOVES ---------------------------------
  --
  -- Emerald: a spread move does HALF, and only a move whose target byte is
  -- exactly MOVE_TARGET_BOTH -- EARTHQUAKE and EXPLOSION were excluded and hit
  -- three Pokemon for full damage.
  --
  -- Platinum: THREE QUARTERS, and EARTHQUAKE IS IN.  battle_lib.c:7035-7044 is
  -- two consecutive blocks, not one:
  --
  --     if (DOUBLES && range == RANGE_ADJACENT_OPPONENTS
  --         && CountAliveBattlers(TRUE, defender) == 2)  damage = damage * 3 / 4;
  --     if (DOUBLES && range == RANGE_ALL_ADJACENT
  --         && CountAliveBattlers(FALSE, defender) >= 2) damage = damage * 3 / 4;
  --
  -- and the two COUNT DIFFERENT THINGS.  `sameSide = TRUE` (battle_lib.c:2840)
  -- counts the living on the DEFENDER'S side, so Blizzard is reduced only while
  -- both foes are up -- Emerald's condition.  `sameSide = FALSE` (:2833) counts
  -- EVERY living battler EXCEPT THE DEFENDER, across both sides, so Earthquake
  -- is reduced whenever two others are still standing -- including when the
  -- defender is the last foe alive, because the user's own ally is taking it
  -- too.  Reading the second gate as the first would give Earthquake full
  -- damage in exactly the case the cartridge reduces it.
  spreadNum = 3, spreadDen = 4,

  -- WHICH MOVES, as data.  A Gen 3 move record carries `target`; a Gen 4 one
  -- carries `range` (Gen4Moves.parse, offset 8), and 0x08 DOES NOT MEAN THE
  -- SAME THING IN THE TWO -- it is MOVE_TARGET_BOTH in Hoenn and
  -- RANGE_ALL_ADJACENT in Sinnoh.  Naming the field is what keeps those apart
  -- when a player picks this ruleset on an Emerald save.
  --
  -- The values are bit positions, measured off pl_waza_tbl.narc rather than
  -- assumed: across all 471 moves the range byte only ever takes 0, 1, 2, 4,
  -- 8, 16, 32, 64, 128, 256, 512 and 1024, which lines up one-for-one with
  -- generated/move_ranges.txt.  Blizzard, Rock Slide and Hyper Voice read 4;
  -- Surf, Earthquake, Explosion, Self-Destruct and Teeter Dance read 8.
  spreadField = "range",
  spreadRanges = {
    [0x04] = "defenderSide",   -- RANGE_ADJACENT_OPPONENTS: both foes alive
    [0x08] = "othersOnField",  -- RANGE_ALL_ADJACENT: two others alive anywhere
  },

  -- SCREENS in doubles are UNCHANGED from Emerald: `damage * 2 / 3` when two
  -- are alive on the defending side, `damage / 2` otherwise -- Light Screen at
  -- battle_lib.c:7023, Reflect at :6982, both gated on
  -- CountAliveBattlers(TRUE, defender) == 2 and both skipped on a crit.
  -- Divide first then double: 50 goes to 32, not 33.
  screenDoublesNum = 2, screenDoublesDen = 3,

  -- Focus Energy works (it is the +2 term in the crit-stage sum).
  focusEnergyBug = false,

  -- The random factor: `damage *= (100 - RandNext() % 16); damage /= 100;`
  -- at battle_lib.c:7084-7085, so 85..100 out of 100 -- Emerald's range and Emerald's
  -- denominator.
  randMin = 85,
  randMax = 100,
  randDiv = 100,

  -- Opponents spend PP and Struggle when empty.
  enemyUnlimitedPP = false,

  -- Hyper Beam always recharges, knockout or not.
  hyperBeamSkipRechargeOnKO = false,

  -- ---- THE FIVE CONDITIONS, measured, and all five came back Emerald's ----
  --
  -- This is the part that was worth doing even though nothing moved, because
  -- "Gen 4 probably kept these" and "Gen 4 kept these" are different claims
  -- and only one of them can be checked later.
  --
  --   subscript_fall_asleep.s:59 is `Random 3, 2`, and BtlCmd_Random
  --   (battle_script.c:3200) reads the bound, ADDS ONE, and then adds the
  --   offset: (rand % 4) + 2, so 2..5.  The +1 is the whole reason this needed
  --   reading -- `Random 3, 2` looks like 2..4 and is not.
  sleepTurnsMin = 2, sleepTurnsMax = 5,
  --   maxHP/8 for burn and for ordinary poison (subscript_burn_damage.s,
  --   subscript_poison_damage.s)
  statusResidualDiv = 8,
  --   maxHP/16 times the counter, which is the four-bit
  --   MON_CONDITION_TOXIC_COUNTER field and so stops at 15
  toxicResidualDiv = 16,
  toxicCounterMax = 15,
  --   `RandNext() % 5 != 0` keeps the freeze, so a 1-in-5 thaw each turn
  freezeThawOneIn = 5,
  --   subscript_poison.s:34-37 and subscript_badly_poison.s:22-25 both test
  --   TYPE_1 and TYPE_2 against TYPE_POISON and TYPE_STEEL
  poisonImmuneTypes = { "POISON", "STEEL" },
}
