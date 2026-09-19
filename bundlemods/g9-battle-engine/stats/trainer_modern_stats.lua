-- Trainer-mon modern stats: an open API other mods can feed real modern
-- data through, with a DV/stat-exp conversion fallback when they don't.
--
-- BattleState.newTrainer (src/battle/BattleState.lua:695-764, confirmed by
-- reading the current dev-branch source directly) builds each party mon
-- via Pokemon.new, then immediately overwrites mon.dvs with the trainer's
-- fixed DV table and recomputes mon.stats from it (the "fixed trainer
-- DVs, recomputed stats" comment right there in engine source) -- there is
-- no hook around that loop, and no per-mon extension point beyond
-- "trainer.party" (which only lets a mod rewrite the PARTY DEFINITION --
-- species/level/moves -- before any mon object exists yet, not supply
-- modern per-mon data after). So this wraps BattleState.newTrainer itself,
-- same monkey-patch pattern as wild_modern_ivs.lua's newWild wrap and this
-- mod's other native-class patches (installBigPartyIcons,
-- installMoveNameDisplay).
--
-- Provider API: another mod calls
--   mod.find("galar_gmax_dex").exports.registerTrainerStatsProvider(fn, priority)
-- fn(ctx) is called once per trainer party mon, where ctx = { game=,
-- oppClass=, partyIndex=, slotIndex=, species=, level=, mon= }. Returning
-- nil/false means "no opinion, keep asking" -- the next-highest-priority
-- provider is tried, then the fallback below. Returning a spec table means
-- "here's this mon's real modern data" --
--   { gender=, ability=, nature=,
--     hp={iv=,ev=}, atk={iv=,ev=}, def={iv=,ev=},
--     spa={iv=,ev=}, spd={iv=,ev=}, spe={iv=,ev=} }
-- applied via ModernStats.applySpec + recalcAll, so all six mon.stats come
-- from that data, exactly like a wild mon's fresh IVs do.
--
-- Explicit user design for the no-provider case: fall back to "the
-- conversion system of DV and stat exp" -- ModernStats.ensure, the exact
-- function modern_combat.lua already calls before every damage calc
-- (confirmed idempotent/fill-only-if-missing) -- NOT a full recalcAll.
-- That keeps hp/atk/def/spe exactly as the trainer's fixed-DV Gen-1
-- formula already computed them (matching what TrainerAI/Damage.lua have
-- always read for these mons) and only derives spa/spd fresh from the
-- converted special DV -- a mon nobody supplies modern data for reads
-- identically to how it always has, plus the two new stats.
return function(mod)
  local BattleState = require("src.battle.BattleState")
  local ModernStats = mod.exports.ModernStats

  local providers = {} -- { {fn=, priority=}, ... }, sorted high-priority-first

  local function registerTrainerStatsProvider(fn, priority)
    assert(type(fn) == "function", "registerTrainerStatsProvider needs a function")
    providers[#providers + 1] = { fn = fn, priority = priority or 0 }
    table.sort(providers, function(a, b) return a.priority > b.priority end)
  end
  mod.exports.registerTrainerStatsProvider = registerTrainerStatsProvider

  local function specFor(ctx)
    for _, entry in ipairs(providers) do
      local ok, spec = pcall(entry.fn, ctx)
      if ok and type(spec) == "table" then
        return spec
      elseif not ok then
        mod.log:warn("galar_gmax_dex: trainer_modern_stats: provider errored: %s", tostring(spec))
      end
    end
    return nil
  end
  -- Exposed so gen2_modern_stats.lua's battle.started listener can ask the
  -- SAME provider list -- one registration API serving both generations
  -- (explicit user design: "an api open that allows other mods to feed our
  -- battle engine", not a per-generation registry another mod would need
  -- to register with twice).
  mod.exports.resolveTrainerSpec = specFor

  -- national_dex (optional_dependencies, manifest.json), when installed,
  -- is the real base-stat/ability source of truth -- real split
  -- spAttack/spDefense and a species' actual ability list, instead of
  -- this codebase's own single-"special" data or a fabricated ability
  -- name. See wild_modern_ivs.lua's identical helper for the full
  -- reasoning.
  local function nationalDexExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  local function generateTrainerMon(game, mon, oppClass, partyIndex, slotIndex)
    if type(mon) ~= "table" then return end
    local nd = nationalDexExports()
    local def = ModernStats.resolveBase(mon.species, game.data.pokemon[mon.species], nd)
    local ctx = {
      -- data is the consistent cross-generation field (game.data here,
      -- battle.data on Gen 2 -- see gen2_modern_stats.lua, which has no
      -- full game object to hand a provider, only the battle's own .data)
      -- -- a provider that needs species defs should read ctx.data, not
      -- assume ctx.game exists. game is kept too, Gen-1-side convenience.
      game = game, data = game.data, oppClass = oppClass, partyIndex = partyIndex,
      slotIndex = slotIndex, species = mon.species, level = mon.level, mon = mon,
    }
    local ok, err = pcall(function()
      local spec = specFor(ctx)
      if spec then
        ModernStats.applySpec(mon, spec)
        if def then ModernStats.recalcAll(def, mon) end
      elseif def then
        ModernStats.ensure(def, mon)
      end
      -- Explicit user rule: every mon always gets an ability/nature, not
      -- just IVs/EVs. Idempotent -- only fills what's still nil after
      -- whichever branch above ran (a provider's spec may have already
      -- set one or both; .applySpec/.ensure never touch ability/nature
      -- themselves, so this is the one place that's guaranteed to run
      -- for every trainer mon regardless of which path fed it).
      ModernStats.generateAbility(mon, ModernStats.resolveAbilities(mon.species, nd))
      ModernStats.generateNature(mon)
      -- Gen1 has no native gender concept at all -- tentatively
      -- GalarGmaxDex-owned 50/50 until national_dex exposes real
      -- per-species ratios. Idempotent: a provider spec's own gender (if
      -- any) wins, this only fills what's still nil.
      ModernStats.generateGender(mon)
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: trainer_modern_stats: failed for %s slot %s: %s",
        tostring(mon.species), tostring(slotIndex), tostring(err))
    end
  end

  -- Gen 1 only: under a Gold boot, require("src.battle.BattleState")
  -- resolves to the Gen2Compat facade over src/ui/gen2/BattleState.lua,
  -- which deliberately has no newTrainer (Gold's own trainer-party
  -- pipeline is Trainers.party + Battle.new -- see gen2_modern_stats.lua).
  -- Skip installing a wrap around a field that doesn't exist there rather
  -- than defining a BattleState.newTrainer that would error if anything
  -- ever called it.
  if type(BattleState.newTrainer) ~= "function" then return end

  if BattleState.__galarTrainerModernStatsWrapped then return end
  BattleState.__galarTrainerModernStatsWrapped = true

  local vanillaNewTrainer = BattleState.newTrainer
  function BattleState.newTrainer(game, oppClass, partyIndex)
    local self = vanillaNewTrainer(game, oppClass, partyIndex)
    if self and self.enemyParty then
      for slotIndex, mon in ipairs(self.enemyParty) do
        generateTrainerMon(game, mon, oppClass, partyIndex or 1, slotIndex)
      end
    end
    return self
  end

  mod.log:info("galar_gmax_dex: trainer modern stats provider API installed")
end
