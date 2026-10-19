-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Pokemon Black / White's battle rules.
--
-- RulesetDefaults has no entry for generation 5, so a BW battle fell back to
-- `gen1_faithful`: a freeze that never thawed, sleep for up to seven turns,
-- poison at a sixteenth, the 1/256 miss, Gen 1's speed-derived critical hits.
-- None of that showed while no BW status move landed; it all shows the moment
-- they do. Installed by src/battle/Gen5MoveEffects.lua (`attach`) as the
-- default for a BW cache -- a save that names a ruleset keeps its choice.
--
-- Gen 5 against Platinum, for the fields this engine models:
--   * SLEEP is 1 to 3 turns (Gen 4: 1 to 4). The engine counts the turn the
--     Pokemon wakes on as a lost turn, so 1..3 here is 1..3 turns lost.
--   * Everything else this file names measures the same as Platinum: the
--     2x critical hit on the 1/16, 1/8, 1/4, 1/3, 1/2 stage ladder, the 3/4
--     spread, the 85..100 random factor, Hyper Beam's recharge after a KO,
--     an eighth for poison and burn, Toxic's sixteenths capped at 15, a
--     one-in-five thaw, Poison and Steel immune to poison.
--   * Spread moves: BW keeps a move's TARGET as its own number (4 every
--     other Pokemon, 5 both foes); Gen5MoveEffects writes Platinum's range
--     bits beside it, so the spread table below reads the same field.

local base = require("src.battle.rulesets.gen4_platinum")

local R = {}
for k, v in pairs(base) do R[k] = v end
R.name = "gen5_bw"
R.sleepTurnsMin = 1
R.sleepTurnsMax = 3
return R
