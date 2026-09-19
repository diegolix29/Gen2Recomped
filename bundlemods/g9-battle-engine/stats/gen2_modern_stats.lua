-- Gen 2 (Gold) wild/trainer modern stats.
--
-- A SEPARATE implementation from wild_modern_ivs.lua/trainer_modern_stats.lua,
-- not a reuse -- confirmed by reading the current engine source directly
-- that Gen 2's battle pipeline shares nothing with Gen 1's:
--   - src/ui/gen2/BattleState.lua and src/battle/BattleState.lua are two
--     unrelated tables (same local variable name, zero relationship --
--     confirmed via require-call-site grep, neither requires the other).
--   - Gen 2 has no newWild/newTrainer at all to monkey-patch. Every mon
--     (wild, trainer, egg, evolution, trade, roamer, prize) goes through
--     one universal src/battle/gen2/Mon.lua Mon.new -- wrapping THAT would
--     catch all of those, not just battles, so this hooks the battle
--     chokepoint instead: src/battle/gen2/Battle.lua's Battle.new emits
--     Runtime.emit("battle.started", { battle=, kind="wild"|"trainer",
--     battleType=, trainer=, ... }) once self.enemy/self.enemyParty are
--     built and stats are already computed, but before anything draws --
--     confirmed via direct source read (Battle.lua ~line 314). Same event
--     NAME Gen 1's BattleState:enter() raises (gimmick_dynamax.lua already
--     listens to it), which is why this file has to check WHICH class
--     ev.battle actually is before touching anything -- see isGen2Battle
--     below -- otherwise this would double-process every Gen 1 battle
--     alongside the newWild/newTrainer wraps that already handle those.
--
-- Field-shape differences from Gen 1's Pokemon.new, confirmed by reading
-- Mon.new (src/battle/gen2/Mon.lua) directly -- these are NOT cosmetic:
--   - mon.stats already has SEPARATE specialAttack/specialDefense (Gen 2
--     canonically splits special at the stat level, one shared DV at the
--     dv level) -- so unlike Gen 1, there's no "bolt spa/spd on top of a
--     single .special" trick needed; this writes the real native fields
--     Gen 2 combat already reads, directly.
--   - mon.gender/mon.shiny/mon.unownLetter are computed FROM mon.dvs at
--     Mon.new's creation time (Mon.gender/Mon.isShiny) and never
--     recomputed after. This file deliberately never touches those three
--     fields -- only .ivs/.evs/.stats/.hp/.maxHp -- so a wild/trainer
--     mon's identity (gender, shininess, Unown letter) stays exactly what
--     it was the moment it was born, decoupled from whatever modern IVs
--     end up driving its battle stats. Re-deriving them from the new IVs
--     would be wrong anyway -- IVs and DVs are unrelated numbers here,
--     and Gen 2's real gender/shiny formulas are DV-specific.
return function(mod)
  local ok, Gen2Battle = pcall(require, "src.battle.gen2.Battle")
  if not ok or type(Gen2Battle) ~= "table" then return end
  local ModernStats = mod.exports.ModernStats

  if Gen2Battle.__galarGen2ModernStatsWrapped then return end
  Gen2Battle.__galarGen2ModernStatsWrapped = true

  local function isGen2Battle(battle)
    return battle ~= nil and getmetatable(battle) == Gen2Battle
  end

  -- national_dex (optional_dependencies, manifest.json) is the real base-
  -- stat/ability source of truth when installed -- see wild_modern_ivs.lua's
  -- identical helper for the full reasoning. battle.data is Gen 2's own
  -- game.data reference (Battle.new: self.data = opts.data), there's no
  -- full game object on the battle instance to pull it from otherwise.
  local function nationalDexExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  -- Writes computeAll's {hp,attack,defense,speed,spa,spd} into BOTH Gen
  -- 2's native mon.stats.specialAttack/specialDefense (what its own
  -- combat/TrainerAI actually read) and this mod's own spa/spd keys
  -- (kept alongside for consistency with every other screen this mod
  -- already draws IV/EV/stat data from) -- a fresh mon, so hp/maxHp both
  -- become the newly computed max, same as Gen 1's Pokemon.new setting
  -- hp = stats.hp at creation.
  local function applyComputedStats(mon, computed)
    mon.stats = mon.stats or {}
    mon.stats.hp = computed.hp
    mon.stats.attack = computed.attack
    mon.stats.defense = computed.defense
    mon.stats.speed = computed.speed
    mon.stats.specialAttack = computed.spa
    mon.stats.specialDefense = computed.spd
    mon.stats.spa = computed.spa
    mon.stats.spd = computed.spd
    mon.hp = computed.hp
    mon.maxHp = computed.hp
  end

  -- Wild: fully random modern IVs/EVs, exactly like wild_modern_ivs.lua's
  -- generateWildMon -- ModernStats.initialize never reads mon.dvs, so
  -- Gold's own fixed/rolled DVs (already spent on gender/shiny/Unown by
  -- Mon.new) are simply irrelevant here, not read or discarded specially.
  local function generateGen2Wild(battle)
    local mon = battle.enemy
    if type(mon) ~= "table" then return end
    local nd = nationalDexExports()
    ModernStats.initialize(mon)
    -- Explicit user rule: every mon always gets an ability/nature.
    -- Independent of the gender/shiny/Unown exclusion above -- those stay
    -- DV-derived and untouched; ability/nature have no DV relationship at
    -- all in this modern layer, so generating them here is safe.
    ModernStats.generateAbility(mon, ModernStats.resolveAbilities(mon.species, nd))
    ModernStats.generateNature(mon)
    local def = ModernStats.resolveBase(mon.species, battle.data and battle.data.pokemon and battle.data.pokemon[mon.species], nd)
    if def then
      applyComputedStats(mon, ModernStats.computeAll(def.baseStats, mon.ivs, mon.evs, mon.level, mon.nature))
    end
  end

  -- Trainer: the SAME provider registry trainer_modern_stats.lua exposes
  -- (mod.exports.resolveTrainerSpec) -- one registration API for both
  -- generations, explicit user design ("an api open that allows other
  -- mods to feed our battle engine", not a per-generation registry).
  -- Fallback with no provider: ModernStats.ensure, the DV/stat-exp
  -- conversion path -- Gen 2 trainer mons carry mon.dvs/mon.statExp in
  -- the exact same shape Gen 1's do (confirmed from Mon.new's own return
  -- table), so the SAME function works unmodified; only its two computed
  -- fields (mon.stats.spa/spd) need mirroring into the native
  -- specialAttack/specialDefense names afterward, since .ensure doesn't
  -- know Gen 2's key convention exists.
  local function generateGen2TrainerMon(battle, mon, trainer, slotIndex)
    if type(mon) ~= "table" then return end
    local nd = nationalDexExports()
    local def = ModernStats.resolveBase(mon.species, battle.data and battle.data.pokemon and battle.data.pokemon[mon.species], nd)
    local resolveSpec = mod.exports.resolveTrainerSpec
    local ctx = {
      data = battle.data, trainer = trainer,
      oppClass = trainer and (trainer.classId or trainer.class),
      partyIndex = trainer and (trainer.memberId or trainer.index) or 1,
      slotIndex = slotIndex, species = mon.species, level = mon.level, mon = mon,
    }
    local spec = type(resolveSpec) == "function" and resolveSpec(ctx) or nil
    if spec then
      ModernStats.applySpec(mon, spec)
      if def then
        applyComputedStats(mon, ModernStats.computeAll(def.baseStats, mon.ivs, mon.evs, mon.level, mon.nature))
      end
    elseif def then
      ModernStats.ensure(def, mon)
      mon.stats = mon.stats or {}
      if mon.stats.spa ~= nil then mon.stats.specialAttack = mon.stats.spa end
      if mon.stats.spd ~= nil then mon.stats.specialDefense = mon.stats.spd end
    end
    -- Explicit user rule: every mon always gets an ability/nature.
    ModernStats.generateAbility(mon, ModernStats.resolveAbilities(mon.species, nd))
    ModernStats.generateNature(mon)
  end

  -- Player-side ability generation -- a real, confirmed gap: every one of
  -- this file's own generation calls above (generateGen2Wild/
  -- generateGen2TrainerMon), plus wild_modern_ivs.lua/trainer_modern_stats
  -- .lua, only ever ran on the OPPONENT's mon. The player's own party never
  -- got ModernStats.generateAbility called on it at all, so battle.player
  -- .ability stayed nil for essentially every real player-owned Pokemon --
  -- confirmed by grepping every call site of generateAbility in this mod
  -- before writing this. Explicit user rule: a caught Pokemon's ability is
  -- an individually SAVED property, generated once and kept from then on
  -- -- exactly what generateAbility's own idempotent contract already
  -- guarantees (only fills mon.ability when it's genuinely nil, never
  -- re-rolls an existing one), so calling it here on every battle start is
  -- safe to run every single battle without ever disturbing an ability a
  -- mon already has -- from a prior battle, or from an explicit swap via
  -- ModernStats.toggleHiddenAbility/toggleRegularAbility.
  --
  -- Only the ability is generated here, not IVs/EVs/stats/nature -- unlike
  -- the opponent side, the player's own party already carries its real,
  -- earned stats; nothing else about it should be touched at battle start.
  local function generatePlayerAbilities(battle)
    local nd = nationalDexExports()
    for _, mon in ipairs(battle.party or {}) do
      if type(mon) == "table" then
        ModernStats.generateAbility(mon, ModernStats.resolveAbilities(mon.species, nd))
      end
    end
  end

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not isGen2Battle(battle) then return end
    local ok2, err = pcall(function()
      generatePlayerAbilities(battle)
      if ev.kind == "wild" then
        generateGen2Wild(battle)
      elseif ev.kind == "trainer" then
        for slotIndex, mon in ipairs(battle.enemyParty or {}) do
          generateGen2TrainerMon(battle, mon, ev.trainer, slotIndex)
        end
      end
    end)
    if not ok2 then
      mod.log:warn("galar_gmax_dex: gen2_modern_stats: failed: %s", tostring(err))
    end
  end)

  mod.log:info("galar_gmax_dex: gen2 modern stats installed")
end
