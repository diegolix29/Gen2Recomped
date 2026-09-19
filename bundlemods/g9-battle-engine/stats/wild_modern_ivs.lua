-- Wild-encounter modern IV/EV generation.
--
-- Pokemon.new (src/pokemon/Pokemon.lua:60-85) unconditionally rolls old-
-- system DVs (Stats.randomDVs) and computes Gen-1 mon.stats for every mon
-- it creates, wild included -- confirmed there's no flag to skip that, and
-- no dedicated Hooks:wrap chain around Pokemon.new or BattleState.newWild
-- itself (only battle.started, a plain Runtime.emit, fires afterward).
-- BattleState.newWild (src/battle/BattleState.lua:576-594) is the real,
-- already-shipped engine function every wild-encounter path calls
-- (vanilla grass/water/fishing encounters, scripted wild tables, and
-- GalarGmaxDex's own overworld_spawns.lua via the "start_battle wild ..."
-- script command) -- so wrapping it here, the same way
-- installBigPartyIcons/installMoveNameDisplay already wrap other native
-- functions elsewhere in this mod, covers every one of those callers in
-- one place: call vanilla first, then immediately overwrite the wild mon
-- it just built.
--
-- Explicit design: a wild mon gets FULLY RANDOM modern IVs -- NOT derived
-- from the DVs Pokemon.new just rolled into mon.dvs (those are discarded,
-- never read again) -- and EVs zeroed. ModernStats.initialize is the
-- right call for that (fresh random per stat); ModernStats.ensure is a
-- different function reserved for mons that predate this system entirely
-- (e.g. loaded from an old save) and need their existing dvs/statExp
-- CONVERTED, not randomized. ModernStats.recalcAll then computes
-- mon.stats for all six modern keys from those fresh ivs/evs, so combat
-- reads consistent modern numbers immediately -- not a mix of new IVs and
-- stale Gen-1-formula stats left over from Pokemon.new's own dvs roll.
--
-- self.enemy.mon at this point is the exact same table Pokemon.new
-- returned -- BattleState's makeBattler stashes it with no copy, and nor
-- does the catch path (Party.add/Boxes.deposit both table.insert the same
-- reference, confirmed by reading storeCaughtMon directly) -- so whatever
-- gets set here survives untouched through the whole battle and into a
-- catch, exactly matching the intended "generate once, persist forever"
-- flow.
--
-- self.player (an existing party mon, not built via Pokemon.new) is never
-- touched -- this only ever processes self.enemy, the wild mon.
--
-- Exposed as mod.exports.generateWildMon(game, mon) -- a plain, reusable
-- function, not hardwired only into the newWild wrap below -- because
-- BattleState.newWild is only ONE path a wild mon can come from (see the
-- header above: vanilla grass/water/fishing, scripted wild tables, this
-- mod's own overworld_spawns.lua). Any OTHER wild-encounter entry point
-- (a future engine version, another mod, a different script command) can
-- call this same function on its own freshly-created mon table instead of
-- this file needing to special-case every possible caller. The newWild
-- wrap is just the one caller this file installs itself.
return function(mod)
  local BattleState = require("src.battle.BattleState")
  local ModernStats = mod.exports.ModernStats

  -- national_dex (optional_dependencies, manifest.json) is the real base-
  -- stat/ability source of truth when installed -- real split
  -- spAttack/spDefense and a species' actual ability list, not this
  -- codebase's own single-"special" placeholder data or a fabricated
  -- ability name. Looked up once per call (mod:find is cheap, a table
  -- lookup) so a mid-session install/uninstall of national_dex is picked
  -- up immediately rather than cached stale at this file's own load time.
  local function nationalDexExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  local function generateWildMon(game, mon)
    if type(mon) ~= "table" then return mon end
    local ok, err = pcall(function()
      local nd = nationalDexExports()
      ModernStats.initialize(mon)
      -- Explicit user rule: a wild mon always gets an ability/nature, not
      -- just IVs/EVs -- generated once here, same idempotent contract, so
      -- catching and re-processing the same mon later never re-rolls it.
      ModernStats.generateAbility(mon, ModernStats.resolveAbilities(mon.species, nd))
      ModernStats.generateNature(mon)
      -- Gen1 has no native gender concept at all -- tentatively
      -- GalarGmaxDex-owned 50/50 until national_dex exposes real
      -- per-species ratios (see ModernStats.generateGender's own header).
      -- Needed so Attract's gender-compatibility check has something to
      -- compare for a wild-caught mon.
      ModernStats.generateGender(mon)
      local def = ModernStats.resolveBase(mon.species, game.data.pokemon[mon.species], nd)
      if def then
        ModernStats.recalcAll(def, mon)
      end
    end)
    if not ok then
      mod.log:warn("galar_gmax_dex: wild_modern_ivs: failed for %s: %s",
        tostring(mon.species), tostring(err))
    end
    return mon
  end
  mod.exports.generateWildMon = generateWildMon

  -- Gen 1 only: under a Gold boot, require("src.battle.BattleState")
  -- resolves to the Gen2Compat facade over src/ui/gen2/BattleState.lua,
  -- which deliberately has no newWild (Gold's own wild-encounter pipeline
  -- is Mon.new + Battle.new -- see gen2_modern_stats.lua). Skip installing
  -- a wrap around a field that doesn't exist there rather than defining a
  -- BattleState.newWild that would error if anything ever called it.
  if type(BattleState.newWild) ~= "function" then return end

  if BattleState.__galarWildModernIvsWrapped then return end
  BattleState.__galarWildModernIvsWrapped = true

  local vanillaNewWild = BattleState.newWild
  function BattleState.newWild(game, species, level, opts)
    local self = vanillaNewWild(game, species, level, opts)
    local mon = self and self.enemy and self.enemy.mon
    if mon then
      generateWildMon(game, mon)
    end
    return self
  end

  mod.log:info("galar_gmax_dex: wild modern IV/EV generation installed")
end
