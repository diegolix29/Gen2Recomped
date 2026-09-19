-- Round 13: Max Move / G-Max Move sub-effects, processed the SAME way this
-- mod processes every other move -- NOT a parallel bespoke system.
--
-- Explicit user scope (2026-09-07): "process dynamax/max/gigantamax moves and
-- subeffects according to pokemon showdown, we don't decide base power, we
-- just process them like we do other moves." So:
--   * battle_forms owns base power (its BATTLE_FORMS_<STEM>_<POWER> power
--     ladder, including the 90-150 and the 70-100 Fighting/Poison
--     reductions, and the fixed-160 G-Max specials). This file never
--     touches power.
--   * This file supplies the Showdown-verified SUB-EFFECT each Max/G-Max
--     move carries -- stat boosts/drops, weather, terrain, hazards, status,
--     volatiles, residuals -- and wires it through the EXACT same canonical
--     pipeline every other damaging move's secondary effect already uses:
--     a kind="full" move_effects record (invisible to Gen 2's
--     damage-preempting dispatch, gen2/Battle.lua:1533-1538 -- the same
--     real reason modern_movepool_stages.lua's secondary() registers
--     kind="full" and no run field) plus one shared battle.damage_dealt
--     listener keyed on the move's own real `effect` field.
--
-- Two round-12 bugs this file is the intended fix for (found by re-reading
-- the old section-3 listener against Showdown's real source, this session):
--   * MAXDARKNESS dropped "speed". Real Showdown (maxdarkness,
--     showdown-moves.ts:11071) drops SPECIAL DEFENSE ({ spd: -1 } on
--     source.foes()) -- fixed here.
--   * The old code routed the speed changes (MAXAIRSTREAM/MAXSTRIKE) through
--     plain changeStage(...,"speed",...), which is a dead store -- modern_
--     combat.lua's own store only ever tracks atk/def/spa/spd and nothing
--     reads a "speed" write back. Speed/accuracy/evasion must go through the
--     NATIVE path: bossStatsDropBlocked gate -> Gen 2's
--     battle:changeStageAgainstMist -> Gen 1's NativeMoveEffects.changeStage
--     (the exact changeNativeStage modern_movepool_stages.lua established).
--     All three native stats route that way here (native = true).
--
-- No __g9Dynamaxed gate on the listener: battle_forms' own src/maxmoves.lua
-- only ever aliases a BATTLE_FORMS_MAX*/GMAX* id into a mon's move slot
-- while that mon is Dynamaxed (src/substitute.lua), so these ids -- and
-- therefore these effects -- are only ever reached mid-Dynamax. That is the
-- same real condition Showdown's own `if (!source.volatiles['dynamax'])
-- return;` checks on every one of these moves; we inherit it from the id
-- convention instead of re-testing it.
--
-- How the moves are matched: every BATTLE_FORMS_<STEM>_<POWER> id
-- (battle_forms' own PREFIX convention, src/maxmoves.lua and
-- data/maxmoves.lua / data/gmaxmoves.lua -- the stem is the FULL
-- "MAXKNUCKLE"/"GMAXCANNONADE", with no underscore between prefix and
-- stem) is discovered by walking mod.content.moves and matching
-- ^BATTLE_FORMS_(MAX%u+)_%d+$ / ^BATTLE_FORMS_(GMAX%u+)_%d+$. Each matched
-- id gets its own `effect` field patched to G9_<STEM>_EFFECT (registered
-- as kind="full"), then the one shared listener dispatches on that effect.
-- MAXGUARD (a status move, no _%d+ suffix) is naturally excluded, and
-- battle_forms' own status-move effects (Max Guard's MAX_GUARD_EFFECT) are
-- untouched. Patch runs SYNCHRONOUSLY at install: battle_forms' manifest
-- priority (80) is below this mod's (95), so every one of its moves is
-- already registered when this entry runs -- the exact same ordering
-- modern_combat_protect.lua's own patch loop relies on. The whole loop is
-- pcall-guarded so a registry surprise can never crash the boot.
--
-- Showdown verification: every mechanic below was re-read from the fetched
-- smogon source (data/moves.ts) this session, not guessed:
--   Max boosts (self + all allies): maxknuckle +1 atk, maxooze +1 spa,
--     maxquake +1 spd, maxairstream +1 spe, maxsteelspike +1 def.
--   Max drops (all foes): maxstrike -1 spe, maxflutterby -1 spa,
--     maxphantasm -1 def, maxwyrmwind -1 atk, maxdarkness -1 spd.
--   Max weather: maxflare sunnyday, maxgeyser raindance, maxrockfall
--     sandstorm, maxhailstorm hail (this mod's established convention maps
--     hail -> SNOW -- see modern_weather.lua).
--   Max terrain: maxlightning electric, maxovergrowth grassy, maxmindstorm
--     psychic, maxstarfall misty.
--   G-Max (all verified in the source): befuddle 1/3 each slp/par/psn per
--     foe; cannonade/vinelash/wildfire/volcalith = a 4-turn side condition
--     dealing 1/6 max HP per turn, gated on NOT having that type; centiferno/
--     sandblast = partially-trapped per foe; chistrike = +1 crit layer (max
--     3) to self+allies; cuddle = attract per foe; depletion = -2 PP on each
--     foe's last-used move; finale = heal 1/6 to self+allies; foamburst =
--     -2 spe per foe; goldrush = confusion per foe; gravitas = gravity field
--     (NO primitive in this engine -- honest no-op, see below); malodor =
--     poison per foe; meltdown = torment per foe EXCEPT a Dynamaxed one
--     (Showdown: `if (!pokemon.volatiles['dynamax']) addVolatile('torment')`
--     -- approximated via our own __g9Dynamaxed marker, which dynamax_battle
--     sets from battle_forms' trigger); oneblow = no sub-effect at all
--     (bypasses Protect -- battle_forms'/the engine's concern, this file
--     never decides that); replenish = 50% restore-last-berry (no berry
--     tracking exists here -- honest no-op); resonance = aurora veil side
--     condition (NO primitive -- honest no-op); smite = confusion per foe;
--     snooze = 50% yawn per foe (checked on the landed hit, so it applies
--     through a Substitute -- the same real onAfterSubDamage half Showdown
--     models; the existing turn_ended yawn machinery in modern_status_
--     volatiles.lua applies the actual sleep); steelsurge = sharp-steel
--     hazard on the foe's side (CLOSES modern_hazards.lua's own INTERACTION
--     TODO); stonesurge = stealth-rock hazard on the foe's side; stunshock =
--     50/50 par/psn per foe; sweetness = cure status for the whole user's
--     side party (Showdown: source.side.pokemon); tartness = -1 evasion per
--     foe; terror = trapped per foe (Gen 2 reuses the native trapsTarget
--     switch gate; Gen 1 has no switch gate -- marker + documented comment);
--     voltcrash = paralysis per foe; drumsolo/fireball/hydrosnipe = fixed
--     160 base power, no sub-effect (never decided here).
--   Not wired at all: gmaxwindrage / gmaxrapidflow -- battle_forms' own
--     gmaxmoves data registers no ids for Corviknight or Urshifu-Rapid-
--     Strike, so discovery finds nothing to patch; documented here, not
--     guessed.
--
-- Depletion detail (why matching the slot by id is correct): while a mon is
-- Dynamaxed, battle_forms ALIASES the Max/G-Max id INTO the base move's
-- slot (sharing its PP -- "a Max Move has no PP of its own"), so the foe's
-- lastMove (a BATTLE_FORMS id mid-Dynamax) and the slot that id lives in
-- are the same real PP pool. Deducting 2 from that slot is therefore
-- equivalent to Showdown's own baseMove resolution (`if (move.isMax &&
-- move.baseMove) move = baseMove; deductPP(move.id, 2)`).
--
-- Deliberate no-ops (registered inert via discovery, never guessed at):
-- GMAXGRAVITAS (no Gravity field primitive), GMAXRESONANCE (no Aurora Veil
-- primitive), GMAXREPLENISH (no lastItem/berry tracking), GMAXONEBLOW
-- (Protect bypass is not a sub-effect), GMAXDRUMSOLO/GMAXFIREBALL/
-- GMAXHYDROSNIPE (fixed power, no sub-effect). GMAXWINDRAGE/GMAXRAPIDFLOW
-- never even get ids (above). Each is documented here rather than silently
-- half-built.
--
-- Known latent bug this file deliberately does NOT propagate: healFraction
-- (below) is written gen-agnostically (m = who.mon or who) because modern_
-- movepool_damage.lua:84's own healFraction reads .mon directly and crashes
-- on Gen 2 -- that bug is out of this file's scope, this file just doesn't
-- copy it.
return function(mod)
  if mod.exports.maxMoveSubeffectsInstalled then return mod.exports end
  mod.exports.maxMoveSubeffectsInstalled = true

  local NativeMoveEffects = require("src.battle.MoveEffects")
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  -- ------------------------------------------------------------------
  -- Small shared helpers (read mod.exports lazily at call time -- this file
  -- loads in Phase 2, BEFORE modern_combat/modern_terrain populate those
  -- exports, but its handlers only ever run during a real battle, by which
  -- point every mod has finished loading).
  -- ------------------------------------------------------------------
  local function emitAll(battle, msgs)
    if not (battle and msgs) then return end
    for _, m in ipairs(msgs) do
      if type(m) == "string" then
        pcall(function() battle:emit({ kind = "message", text = m }) end)
      end
    end
  end

  local function percentRoll(battle, gen2, chance)
    if gen2 then return battle.random(100) < chance end
    return battle.rng(1, 100) <= chance
  end

  local function rangeRoll(battle, gen2, lo, hi)
    if gen2 then return lo + battle.random(hi - lo + 1) end
    return battle.rng(lo, hi)
  end

  local function hasStatus(who)
    local id = mod.exports.canonicalStatusOf
    return id and id(who) ~= nil
  end

  local function displayNameOf(battle, who, gen2)
    local displayNameFor = mod.exports.displayNameFor
    return displayNameFor and displayNameFor(battle, who, gen2) or "???"
  end

  local function healFraction(battle, who, denom)
    local m = who.mon or who
    local maxHp = m.maxHp or (m.stats and m.stats.hp) or 1
    if (m.hp or 0) < maxHp then
      local amount = math.max(1, math.floor(maxHp / denom))
      local tryHeal = mod.exports.g9TryHeal
      if tryHeal then
        tryHeal(battle, who, amount)
      else
        m.hp = math.min(maxHp, (m.hp or 0) + amount)
      end
    end
  end

  -- Native stat route (speed/accuracy/evasion): bossStatsDropBlocked first
  -- (ahead of either native branch, same call-site placement modern_movepool
  -- _stages.lua's own changeNativeStage justifies), then Gen 2's real
  -- changeStageAgainstMist (which emits its own message) / Gen 1's real
  -- NativeMoveEffects.changeStage.
  local function changeNativeStage(battle, user, who, stat, delta, gen2, fromEnemy)
    local bossStatsDropBlocked = mod.exports.bossStatsDropBlocked
    if bossStatsDropBlocked and bossStatsDropBlocked(battle, who, delta) then
      return { romText(battle.data, "_NothingHappenedText", "Nothing happened!") }
    end
    if gen2 then
      battle:changeStageAgainstMist(user, who, stat, delta)
      return {}
    end
    return NativeMoveEffects.changeStage(battle, who, stat, delta, fromEnemy)
  end

  local function applyStageChange(battle, user, who, gen2, stat, delta, native, fromEnemy)
    if native then
      return changeNativeStage(battle, user, who, stat, delta, gen2, fromEnemy)
    end
    local changeStage = mod.exports.changeStage
    if not changeStage then return {} end
    return changeStage(battle, who, stat, delta, fromEnemy, gen2)
  end

  -- Real adjacency: requestAdjacency (N-way when a scene mod is present,
  -- native two-battler fallback otherwise), pcall-guarded like every other
  -- consumer.
  local function alliesAndSelf(battle, user)
    local out = { user }
    local requestAdjacency = mod.exports.requestAdjacency
    if requestAdjacency then
      local ok, adj = pcall(requestAdjacency, battle, user, nil)
      if ok and adj and adj.allies then
        for _, ally in ipairs(adj.allies) do out[#out + 1] = ally end
      end
    end
    return out
  end

  local function adjacentFoes(battle, user)
    local out = {}
    local requestAdjacency = mod.exports.requestAdjacency
    if requestAdjacency then
      local ok, adj = pcall(requestAdjacency, battle, user, nil)
      if ok and adj and adj.enemies then
        for _, foe in ipairs(adj.enemies) do out[#out + 1] = foe end
      end
    end
    return out
  end

  -- ------------------------------------------------------------------
  -- Effect registration (kind="full", no run field -- invisible to Gen 2's
  -- damage-preempting dispatch, so the battle_forms move keeps dealing its
  -- real damage; the sub-effect rides battle.damage_dealt instead).
  -- ------------------------------------------------------------------
  local registered = {}
  local function registerFull(effectId)
    if registered[effectId] then return end
    registered[effectId] = true
    mod.content.move_effects:register(effectId, { kind = "full" })
  end

  -- ------------------------------------------------------------------
  -- MAX Move secondaries (Showdown-verified, see header).
  -- ------------------------------------------------------------------
  local MAX_BOOST = {
    MAXKNUCKLE = { stat = "attack", delta = 1 },
    MAXOOZE = { stat = "spa", delta = 1 },
    MAXQUAKE = { stat = "spd", delta = 1 },
    MAXAIRSTREAM = { stat = "speed", delta = 1, native = true },
    MAXSTEELSPIKE = { stat = "defense", delta = 1 },
  }
  local MAX_DROP = {
    MAXSTRIKE = { stat = "speed", delta = -1, native = true },
    MAXFLUTTERBY = { stat = "spa", delta = -1 },
    MAXPHANTASM = { stat = "defense", delta = -1 },
    MAXWYRMWIND = { stat = "attack", delta = -1 },
    MAXDARKNESS = { stat = "spd", delta = -1 },
  }
  local MAX_WEATHER = {
    MAXFLARE = "SUN", MAXGEYSER = "RAIN", MAXROCKFALL = "SAND", MAXHAILSTORM = "SNOW",
  }
  local MAX_TERRAIN = {
    MAXLIGHTNING = "ELECTRIC", MAXOVERGROWTH = "GRASSY",
    MAXMINDSTORM = "PSYCHIC", MAXSTARFALL = "MISTY",
  }
  local WEATHER_TEXT = {
    SUN = "The sunlight\ngot bright!",
    RAIN = "It started\nto rain!",
    SAND = "A sandstorm\nbrewed!",
    SNOW = "It started\nto snow!",
  }
  local TERRAIN_TEXT = {
    ELECTRIC = "An electric current ran across the battlefield!",
    GRASSY = "Grass grew to cover the battlefield!",
    MISTY = "Mist swirled around the battlefield!",
    PSYCHIC = "The battlefield got weird!",
  }

  local function statHandler(targets, ch)
    return function(n, ev)
      local msgs = {}
      for _, who in ipairs(targets(n.battle, n.user)) do
        if who then
          -- fromEnemy derives the same way modern_movepool_stages.lua's own
          -- applyChange derives it: a self-directed change is never hostile;
          -- a target-directed change is hostile (Mist/Substitute-gated) only
          -- when it's a drop, never a buff.
          local fromEnemy = (not ch.self) and ch.delta < 0
          for _, m in ipairs(applyStageChange(n.battle, n.user, who, n.gen2,
              ch.stat, ch.delta, ch.native, fromEnemy)) do
            msgs[#msgs + 1] = m
          end
        end
      end
      emitAll(n.battle, msgs)
    end
  end

  local function weatherHandler(key)
    return function(n, ev)
      local currentWeather = mod.exports.currentWeather
      if currentWeather and currentWeather(n.battle, n.gen2) == key then return end
      local canSetWeather = mod.exports.canSetWeather
      if canSetWeather and not canSetWeather(n.battle, false, n.user) then return end
      local setWeather = mod.exports.setWeather
      if not setWeather then return end
      pcall(setWeather, n.battle, n.gen2, key, nil, n.user)
      emitAll(n.battle, { WEATHER_TEXT[key] })
    end
  end

  local function terrainHandler(key)
    return function(n, ev)
      local setTerrain = mod.exports.setTerrain
      if not setTerrain then return end
      pcall(setTerrain, n.battle, n.user, key, TERRAIN_TEXT[key])
    end
  end

  local HANDLERS = {}
  for stem, ch in pairs(MAX_BOOST) do HANDLERS["G9_" .. stem .. "_EFFECT"] = statHandler(alliesAndSelf, ch) end
  for stem, ch in pairs(MAX_DROP) do HANDLERS["G9_" .. stem .. "_EFFECT"] = statHandler(adjacentFoes, ch) end
  for stem, key in pairs(MAX_WEATHER) do HANDLERS["G9_" .. stem .. "_EFFECT"] = weatherHandler(key) end
  for stem, key in pairs(MAX_TERRAIN) do HANDLERS["G9_" .. stem .. "_EFFECT"] = terrainHandler(key) end

  -- ------------------------------------------------------------------
  -- G-Max secondaries. Each GMAX_* handler below runs per landed hit
  -- (battle.damage_dealt), matching Showdown's own onHit/onAfterSubDamage
  -- placement -- including through a Substitute where Showdown does.
  -- ------------------------------------------------------------------
  local STATUS_CODES = {
    poison = { gen1 = "PSN", gen2 = "poison" },
    paralysis = { gen1 = "PAR", gen2 = "paralyze" },
    sleep = { gen1 = "SLP", gen2 = "sleep" },
  }

  -- One-status-at-a-time rule up front (Showdown's trySetStatus); the
  -- engine's own applyStatus/inflict already re-check it and ability
  -- immunity natively. Max/G-Max sources deliberately omit StatusRegistry's
  -- `secondary` option (avoids the Gen 1 FreezeBurnParalyzeEffect type-match
  -- quirk -- same choice the codebase already makes for Yawn/Dire Claw).
  local function inflictStatus(n, target, key, source)
    if hasStatus(target) then return end
    local codes = STATUS_CODES[key]
    if not codes then return end
    if n.gen2 then
      pcall(n.battle.applyStatus, n.battle, target, codes.gen2, source)
    else
      local StatusRegistry = require("src.battle.StatusRegistry")
      pcall(StatusRegistry.inflict, StatusRegistry, n.battle, target, codes.gen1,
        { source = source })
    end
  end

  local function inflictConfusion(n, target)
    -- Boss-fight "softStatus" protection, same gate modern_movepool_status
    -- .lua's own confuseTarget applies.
    if target == n.battle.enemy and mod.exports.bossFightHas
        and mod.exports.bossFightHas(n.battle, "softStatus") then
      return nil
    end
    local hasStatusImmunity = mod.exports.hasStatusImmunity
    if hasStatusImmunity and hasStatusImmunity(target, "confusion", n.battle) then
      return nil
    end
    if n.gen2 then
      local vol = n.battle:volatile(target)
      if vol.confuseCount then return nil end
      vol.confuseCount = rangeRoll(n.battle, true, 2, 5)
    else
      if target.confusedTurns then return nil end
      target.confusedTurns = rangeRoll(n.battle, false, 2, 5)
    end
    return Strings("%s\nbecame confused!", displayNameOf(n.battle, target, n.gen2))
  end

  -- Partially trapped (G-Max Centiferno/Sandblast). Reuses the exact
  -- GALAR_TRAP_EFFECT machinery (main.lua:442) -- native Gen 2 wrapCount
  -- (trap + native wrap residual) and Gen 1's trappingTurns/boundTurns --
  -- but SKIPS the gen2 substitute gate, a documented divergence: Showdown's
  -- Max onHit applies through a Substitute (real source confirms
  -- addVolatile on a plain hit), unlike ordinary trap moves.
  local function partiallyTrap(n, target, moveId)
    if n.gen2 then
      local state = n.battle:volatile(target)
      if not state.wrapCount then
        state.wrapCount = rangeRoll(n.battle, true, 4, 5)
        state.wrapMove = moveId
        state.wrapMoveId = moveId
        emitAll(n.battle, { Strings("%s was\npartially trapped!", displayNameOf(n.battle, target, true)) })
      end
    else
      if not target.trappingTurns then
        target.trappingTurns = rangeRoll(n.battle, false, 4, 5)
        target.boundTurns = target.trappingTurns
        target.trapMove = moveId
        emitAll(n.battle, { Strings("%s was\npartially trapped!", displayNameOf(n.battle, target, false)) })
      end
    end
  end

  local GMAX = {}

  GMAX.BEFUDDLE = function(n, ev)
    local source = ev.move and ev.move.id
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      local pick = ({ "sleep", "paralysis", "poison" })[(n.gen2 and n.battle.random(3) or (n.battle.rng(1, 3) - 1)) + 1]
      inflictStatus(n, foe, pick, source)
    end
  end

  -- Cannonade/Vine Lash/Wildfire/Volcalith: a 4-turn side condition dealing
  -- 1/6 max HP each turn, gated on NOT having the move's type (Showdown's
  -- own `if (!target.hasType(X)) this.damage(baseMaxhp/6)`). Stored per side
  -- on the battle, ticked down by the turn_ended listener below; re-using
  -- the move refreshes the duration (onSideStart re-fires) like Showdown.
  local GMAX_RESIDUAL = {
    CANNONADE = { type = "WATER", text = "A torrent of water\nrages around %s's team!" },
    VINELASH = { type = "GRASS", text = "Thorns lash\naround %s's team!" },
    WILDFIRE = { type = "FIRE", text = "Wildfire engulfs\n%s's team!" },
    VOLCALITH = { type = "ROCK", text = "Rocks are hurled at\n%s's team!" },
  }
  for stem, cfg in pairs(GMAX_RESIDUAL) do
    GMAX[stem] = function(n, ev)
      local side = n.battle:sideOf(n.target)
      n.battle.g9GmaxResidual = n.battle.g9GmaxResidual or {}
      n.battle.g9GmaxResidual[side] = n.battle.g9GmaxResidual[side] or {}
      n.battle.g9GmaxResidual[side][stem] = { type = cfg.type, turns = 4 }
      emitAll(n.battle, { Strings(cfg.text, displayNameOf(n.battle, n.target, n.gen2)) })
    end
  end

  GMAX.CENTIFERNO = function(n, ev)
    local source = ev.move and ev.move.id
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do partiallyTrap(n, foe, source) end
  end
  GMAX.SANDBLAST = function(n, ev)
    local source = ev.move and ev.move.id
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do partiallyTrap(n, foe, source) end
  end

  -- Chi Strike: +1 crit layer (max 3) to self + allies. The crit half rides
  -- this mod's own registerCritStageModifier chain (the same one Scope Lens
  -- uses); the modifier is registered lazily on first use because this file
  -- loads before modern_combat exports it.
  local chiCritRegistered = false
  local function ensureChiCrit()
    if chiCritRegistered then return end
    chiCritRegistered = true
    local registerCritStageModifier = mod.exports.registerCritStageModifier
    if not registerCritStageModifier then return end
    pcall(registerCritStageModifier, "gmaxchistrike", function(ctx)
      return math.min(3, (ctx.user and ctx.user.g9GmaxChiStrikeLayers) or 0)
    end)
  end
  GMAX.CHISTRIKE = function(n, ev)
    ensureChiCrit()
    for _, ally in ipairs(alliesAndSelf(n.battle, n.user)) do
      ally.g9GmaxChiStrikeLayers = math.min(3, (ally.g9GmaxChiStrikeLayers or 0) + 1)
      emitAll(n.battle, { Strings("%s's critical-hit\nratio rose!", displayNameOf(n.battle, ally, n.gen2)) })
    end
  end

  GMAX.CUDDLE = function(n, ev)
    local tryAttract = mod.exports.tryAttract
    if not tryAttract then return end
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      local ok, applied, msg = pcall(tryAttract, n.battle, n.user, foe, n.gen2)
      if ok and applied and msg then emitAll(n.battle, { msg }) end
    end
  end

  -- Depletion: -2 PP on each foe's last-used move (see file header for why
  -- matching the slot by the BATTLE_FORMS id is the real equivalent of
  -- Showdown's baseMove resolution).
  GMAX.DEPLETION = function(n, ev)
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      local lastMove = n.gen2 and n.battle:volatile(foe).lastMove or foe.lastMove
      if lastMove and lastMove ~= "STRUGGLE" then
        local slots = n.gen2 and foe.moves or (foe.curMoves or {})
        local slot
        for _, mv in ipairs(slots) do
          if mv and mv.id == lastMove then slot = mv break end
        end
        if slot then
          slot.pp = math.max(0, (slot.pp or 0) - 2)
          emitAll(n.battle, { Strings("%s's PP\nwas reduced!", displayNameOf(n.battle, foe, n.gen2)) })
        end
      end
    end
  end

  GMAX.FINALE = function(n, ev)
    for _, ally in ipairs(alliesAndSelf(n.battle, n.user)) do healFraction(n.battle, ally, 6) end
  end

  GMAX.FOAMBURST = function(n, ev)
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      emitAll(n.battle, changeNativeStage(n.battle, n.user, foe, "speed", -2, n.gen2, true))
    end
  end

  GMAX.GOLDRUSH = function(n, ev)
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      local msg = inflictConfusion(n, foe)
      if msg then emitAll(n.battle, { msg }) end
    end
  end

  -- Gravitas: pseudoWeather gravity -- no Gravity field primitive exists in
  -- this engine, so this is a documented no-op (never guessed at).
  GMAX.GRAVITAS = function(n, ev) end

  GMAX.MALODOR = function(n, ev)
    local source = ev.move and ev.move.id
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do inflictStatus(n, foe, "poison", source) end
  end

  -- Meltdown: torment per foe, EXCEPT a Dynamaxed one (Showdown checks the
  -- target's own dynamax volatile; approximated with our __g9Dynamaxed
  -- marker, which dynamax_battle sets from battle_forms' trigger).
  GMAX.MELTDOWN = function(n, ev)
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      local m = foe.mon or foe
      if not m.__g9Dynamaxed then
        local tStore = n.gen2 and n.battle:volatile(foe) or foe
        if not tStore.tormented then
          tStore.tormented = true
          emitAll(n.battle, { Strings("%s was\ntormented!", displayNameOf(n.battle, foe, n.gen2)) })
        end
      end
    end
  end

  -- One Blow: no sub-effect (its real trait is bypassing Protect/Max Guard,
  -- which battle_forms'/the engine's own Protect family owns -- never this
  -- file). Replenish: 50% restore-last-berry -- no berry tracking exists in
  -- this engine -- documented no-op. Resonance: aurora veil side condition
  -- -- no primitive -- documented no-op.
  GMAX.ONEBLOW = function(n, ev) end
  GMAX.REPLENISH = function(n, ev) end
  GMAX.RESONANCE = function(n, ev) end

  GMAX.SMITE = function(n, ev)
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      local msg = inflictConfusion(n, foe)
      if msg then emitAll(n.battle, { msg }) end
    end
  end

  -- Snooze: 50% yawn per foe, only if no status and not sleep-immune
  -- (Showdown's own guards, in that order), applied on the landed hit so it
  -- works through a Substitute (the onAfterSubDamage half). The actual sleep
  -- lands via the existing yawnTurns countdown in modern_status_volatiles.
  GMAX.SNOOZE = function(n, ev)
    local hasStatusImmunity = mod.exports.hasStatusImmunity
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      if not hasStatus(foe)
          and not (hasStatusImmunity and hasStatusImmunity(foe, "sleep", n.battle))
          and percentRoll(n.battle, n.gen2, 50) then
        foe.yawnTurns = 2
        emitAll(n.battle, { Strings("%s\ngrew drowsy!", displayNameOf(n.battle, foe, n.gen2)) })
      end
    end
  end

  -- Steelsurge / Stonesurge: real hazards on the foe's side via the one
  -- shared hazards accessor. Steelsurge closes modern_hazards.lua's own
  -- INTERACTION TODO (its switch-in damage block was already fully built).
  GMAX.STEELSURGE = function(n, ev)
    local hazardsFor = mod.exports.hazardsFor
    if not hazardsFor then return end
    local h = hazardsFor(n.battle, n.battle:sideOf(n.target))
    if h.sharpSteel then return end
    h.sharpSteel = true
    emitAll(n.battle, { Strings("Sharp steel floated in the\nair around %s's team!", displayNameOf(n.battle, n.target, n.gen2)) })
  end
  GMAX.STONESURGE = function(n, ev)
    local hazardsFor = mod.exports.hazardsFor
    if not hazardsFor then return end
    local h = hazardsFor(n.battle, n.battle:sideOf(n.target))
    if h.stealthRock then return end
    h.stealthRock = true
    emitAll(n.battle, { Strings("Pointed stones\nfloat in the air\naround %s's team!", displayNameOf(n.battle, n.target, n.gen2)) })
  end

  GMAX.STUNSHOCK = function(n, ev)
    local source = ev.move and ev.move.id
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      local par = n.gen2 and n.battle.random(2) == 0 or n.battle.rng(1, 2) == 1
      inflictStatus(n, foe, par and "paralysis" or "poison", source)
    end
  end

  -- Sweetness: cure status for the WHOLE user's side (Showdown:
  -- source.side.pokemon), not just the active battlers -- party array plus
  -- the active roster (a Gen 1 party may not contain the active mon).
  GMAX.SWEETNESS = function(n, ev)
    local cureStatusOf = mod.exports.cureStatusOf
    if not cureStatusOf then return end
    local side = n.battle:sideOf(n.user)
    local party = side == "enemy" and n.battle.enemyParty or n.battle.party
    if party then
      for _, mon in ipairs(party) do pcall(cureStatusOf, mon) end
    end
    for _, ally in ipairs(alliesAndSelf(n.battle, n.user)) do pcall(cureStatusOf, ally) end
  end

  GMAX.TARTNESS = function(n, ev)
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      emitAll(n.battle, changeNativeStage(n.battle, n.user, foe, "evasion", -1, n.gen2, true))
    end
  end

  -- Terror: trapped per foe. Gen 2 reuses the native switch gate (Battle:
  -- switchLocked reads volatile(target).trapsTarget -- same real field
  -- abilities/engine/trap_abilities.lua relies on). Gen 1 has no switch
  -- gate at all -- marker + documented comment, no fake trap.
  GMAX.TERROR = function(n, ev)
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do
      if n.gen2 then
        n.battle:volatile(foe).trapsTarget = n.user
      else
        local m = foe.mon or foe
        m.g9GmaxTrapped = true
      end
      emitAll(n.battle, { Strings("%s can no\nlonger escape!", displayNameOf(n.battle, foe, n.gen2)) })
    end
  end

  GMAX.VOLTCRASH = function(n, ev)
    local source = ev.move and ev.move.id
    for _, foe in ipairs(adjacentFoes(n.battle, n.user)) do inflictStatus(n, foe, "paralysis", source) end
  end

  -- Drumsolo / Fireball / Hydrosnipe: fixed 160 base power, no sub-effect
  -- (power is battle_forms' own -- see header).
  GMAX.DRUMSOLO = function(n, ev) end
  GMAX.FIREBALL = function(n, ev) end
  GMAX.HYDROSNIPE = function(n, ev) end

  -- GMAX table keys are the bare stem (CANNONADE, BEFUDDLE, ...); the effect
  -- id carries the full GMAX prefix so it matches the discovery loop's
  -- G9_GMAX<STEM>_EFFECT derived from battle_forms' real move ids.
  for stem, fn in pairs(GMAX) do HANDLERS["G9_GMAX" .. stem .. "_EFFECT"] = fn end

  -- ------------------------------------------------------------------
  -- Shared dispatch: ONE battle.damage_dealt listener for every Max/G-Max
  -- sub-effect, keyed on the move's own real `effect` field -- the exact
  -- same shape modern_movepool_stages.lua's own secondary() listener uses.
  -- ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local move = ev and ev.move
    local effectId = move and move.effect
    local handler = effectId and HANDLERS[effectId]
    if not (battle and handler and ev.user and ev.target and (ev.damage or 0) > 0) then return end
    local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle) or false
    local n = { battle = battle, user = ev.user, target = ev.target, gen2 = gen2 }
    local ok, err = pcall(handler, n, ev)
    if not ok then
      mod.log:warn("galar_gmax_dex: max_move_subeffects: %s handler errored (%s)",
        tostring(effectId), tostring(err))
    end
  end)

  -- G-Max residual tick (Cannonade/Vine Lash/Wildfire/Volcalith): 1/6 max
  -- HP per turn for each active battler on the affected side, type-gated
  -- (a battler that HAS the move's type is immune -- Showdown's own check),
  -- Magic Guard immune (indirect damage, same family the hazards/sand code
  -- already handles). Gen 2 via emit + damage; Gen 1 via applyDamage/
  -- drainNext/sayNext/onFaint, exactly mirroring modern_hazards.lua's own
  -- switch-in residual shape. Cleared with the battle (per-battle field).
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local residual = battle.g9GmaxResidual
    if not residual then return end
    local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle) or false
    local roster = mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }
    local magicGuardBlocksHazard = mod.exports.magicGuardBlocksHazard
    for side, byStem in pairs(residual) do
      for stem, entry in pairs(byStem) do
        for _, who in ipairs(roster) do
          if who and battle:sideOf(who) == side then
            local m = who.mon or who
            if m and (m.hp or 0) > 0 then
              local immune = false
              for _, t in ipairs(mod.exports.curTypesOf(who, gen2)) do
                if t == entry.type then immune = true break end
              end
              if not immune and not (magicGuardBlocksHazard and magicGuardBlocksHazard(m)) then
                local maxHp = (m.stats and m.stats.hp) or m.maxHp or 1
                local dmg = math.max(1, math.floor(maxHp / 6))
                local name = displayNameOf(battle, who, gen2)
                if gen2 then
                  m.hp = math.max(0, m.hp - dmg)
                  battle:emit({ kind = "message", text = name .. " is hurt by the G-Max move!" })
                  battle:emit({ kind = "damage", side = side, amount = dmg, hp = m.hp, anim = false })
                else
                  battle:applyDamage(who, dmg)
                  battle:drainNext(who, m.hp)
                  battle:sayNext(Strings("%s is hurt\nby the G-Max move!", name))
                  if m.hp <= 0 then battle:onFaint(who) end
                end
              end
            end
          end
        end
        entry.turns = entry.turns - 1
        if entry.turns <= 0 then byStem[stem] = nil end
      end
    end
  end)

  -- ------------------------------------------------------------------
  -- Discovery + patch: walk every registered move, match battle_forms'
  -- own id convention, patch each real damaging Max/G-Max move's `effect`
  -- field onto its G9_<STEM>_EFFECT record. Synchronous (priority order
  -- guarantees battle_forms' moves exist), pcall-guarded (a registry
  -- surprise logs and the boot continues). Counts are logged so real
  -- coverage is checkable rather than silently trusted.
  -- ------------------------------------------------------------------
  do
    local runOk, runErr = pcall(function()
      local maxPatched, gmaxPatched = 0, 0
      for id in mod.content.moves:each() do
        if type(id) == "string" then
          -- battle_forms' confirmed id convention (data/maxmoves.lua,
          -- data/gmaxmoves.lua): M.PREFIX = "BATTLE_FORMS_", the stem is the
          -- FULL "MAXKNUCKLE"/"GMAXCANNONADE", and the power rung is a
          -- trailing _<power> suffix. No underscore between prefix and stem.
          local stem = id:match("^BATTLE_FORMS_(MAX%u+)_%d+$")
          local isGmax = false
          if not stem then
            stem = id:match("^BATTLE_FORMS_(GMAX%u+)_%d+$")
            isGmax = true
          end
          if stem then
            local effectId = "G9_" .. stem .. "_EFFECT"
            if HANDLERS[effectId] then
              registerFull(effectId)
              local ok = pcall(function() mod.content.moves:patch(id, { effect = effectId }) end)
              if ok then
                if isGmax then gmaxPatched = gmaxPatched + 1 else maxPatched = maxPatched + 1 end
              end
            end
          end
        end
      end
      mod.log:info("galar_gmax_dex: max_move_subeffects: marked %d Max Move(s) and %d G-Max Move(s) with Showdown sub-effects",
        maxPatched, gmaxPatched)
    end)
    if not runOk then
      mod.log:warn("galar_gmax_dex: max_move_subeffects: discovery/patch errored, skipped (%s)", tostring(runErr))
    end
  end

  mod.log:info("galar_gmax_dex: max_move_subeffects installed (Showdown-verified Max/G-Max secondaries via move.effect)")
  return mod.exports
end
