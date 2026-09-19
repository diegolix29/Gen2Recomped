-- Grants EV yield to every mon that gains EXP from an enemy faint, per the
-- user's exact spec: "if nat dex says pokemonX yields 1 attack, we give 1
-- atk ev to our pokemon (all) who gain exp from that fainted enemy in
-- combat." Hooks battle.exp_gained -- fires ONCE PER RECIPIENT mon that
-- actually gains EXP from a KO (confirmed via direct source read of both
-- src/battle/BattleState.lua's applyShare/awardExp -- Gen 1, lines ~3806-
-- 3925 -- and src/battle/gen2/Battle.lua's giveExperiencePass/
-- awardExperience -- Gen 2 -- same event name, compatible payload:
-- {battle=, mon=<recipient>, gained=, levels=, index=<Gen2 only>}), NOT
-- battle.fainted (fires for both sides, before EXP is computed, no
-- recipient list).
--
-- battle.enemy.mon/.def (Gen1) / battle.enemy (Gen2, raw mon table) are
-- still the just-fainted enemy's data at this exact moment -- confirmed by
-- reading BattleState.lua directly: enemy-party advancement happens later
-- in enemyMonFainted, after awardExp() (which raises this event) returns.
--
-- Gen 2 EXP_SHARE gotcha: a mon that's both a battle participant AND an
-- EXP_SHARE holder fires this event TWICE for the same KO (once per
-- giveExperiencePass call -- participants, then holders). Deliberately NOT
-- deduped here -- matches native mon.statExp, which double-increments for
-- the exact same case, so this mirrors an already-established engine
-- precedent rather than special-casing around it.
return function(mod)
  local ModernStats = mod.exports.ModernStats
  local ok, Gen2Battle = pcall(require, "src.battle.gen2.Battle")
  Gen2Battle = ok and Gen2Battle or nil

  local function isGen2Battle(battle)
    return Gen2Battle ~= nil and battle ~= nil and getmetatable(battle) == Gen2Battle
  end

  -- national_dex (optional_dependencies, manifest.json) is the real EV-
  -- yield source of truth when installed -- see wild_modern_ivs.lua's
  -- identical helper for the full reasoning. With no national_dex,
  -- ModernStats.resolveEvYield returns all-zero yield, a safe no-op.
  local function nationalDexExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  -- Duck-types the fainted enemy's species out of battle.enemy -- Gen 1's
  -- enemy is a battler wrapper (.mon holds the real mon table), Gen 2's
  -- enemy IS the raw mon table directly (confirmed via gen2_modern_stats.lua's
  -- own header comment and battle.enemy usage).
  local function faintedSpecies(battle)
    local enemy = battle and battle.enemy
    if type(enemy) ~= "table" then return nil end
    if type(enemy.mon) == "table" then return enemy.mon.species end
    return enemy.species
  end

  -- Recomputes a Gen 1 recipient's stats after granting EV yield, preserving
  -- current damage instead of resetting to full. mon.stats.hp
  -- IS this mon's max HP in Gen 1 (no separate maxHp field), so none is set.
  local function recomputeGen1(game, mon)
    local def = ModernStats.resolveBase(mon.species, game.data.pokemon[mon.species], nationalDexExports())
    if not def then return end
    mon.stats = mon.stats or {}
    local oldMax = mon.stats.hp or 1
    local oldHp = math.max(0, math.min(mon.hp or 0, oldMax))
    local missing = math.max(0, oldMax - oldHp)
    ModernStats.recalcAll(def, mon)
    if oldHp <= 0 then
      mon.hp = 0
    else
      mon.hp = math.max(1, mon.stats.hp - missing)
    end
  end

  -- Same idea for Gen 2, plus mirroring spa/spd into the native
  -- specialAttack/specialDefense fields (recalcAll only writes the modern
  -- keys) and keeping maxHp in sync, since Gen 2 mons DO carry a separate
  -- maxHp field (unlike Gen 1) -- see gen2_modern_stats.lua's
  -- applyComputedStats for the field-shape precedent.
  local function recomputeGen2(battle, mon)
    local def = ModernStats.resolveBase(mon.species, battle.data and battle.data.pokemon and battle.data.pokemon[mon.species], nationalDexExports())
    if not def then return end
    mon.stats = mon.stats or {}
    local oldMax = mon.stats.hp or 1
    local oldHp = math.max(0, math.min(mon.hp or 0, oldMax))
    local missing = math.max(0, oldMax - oldHp)
    ModernStats.recalcAll(def, mon)
    mon.stats.specialAttack = mon.stats.spa
    mon.stats.specialDefense = mon.stats.spd
    if oldHp <= 0 then
      mon.hp = 0
    else
      mon.hp = math.max(1, mon.stats.hp - missing)
    end
    mon.maxHp = mon.stats.hp
  end

  mod.events:on("battle.exp_gained", function(ev)
    local battle = ev and ev.battle
    local mon = ev and ev.mon
    if type(battle) ~= "table" or type(mon) ~= "table" then return end
    local ok2, err = pcall(function()
      local species = faintedSpecies(battle)
      if not species then return end
      local yield = ModernStats.resolveEvYield(species, nationalDexExports())
      ModernStats.grantEvYield(mon, yield)
      if isGen2Battle(battle) then
        recomputeGen2(battle, mon)
      elseif battle.game then
        recomputeGen1(battle.game, mon)
      end
    end)
    if not ok2 then
      mod.log:warn("galar_gmax_dex: ev_yield_on_faint: failed: %s", tostring(err))
    end
  end)

  mod.log:info("galar_gmax_dex: ev yield on faint installed")
end
