-- Gigantamax (Dynamax mechanic + a size-up, no form-swap yet) --
-- GalarGmaxDex's own native port of the mechanic studied from
-- ReferentialMods/Dynamax_v0_6_3.zip, registered with this mod's OWN
-- gimmick ring (custom_battle_scene.lua's mod.exports.gimmickRing) instead
-- of requiring either the reference Dynamax mod or gimmick_menu to be
-- installed -- explicit user decision: "we won't need dynamax or gimmick
-- menu mod as requirement for our mod."
--
-- Ported: Max Move data (type x category x power grid, the same bucket
-- table), MAX GUARD (decaying-success protect variant), HP doubling,
-- three-turn duration with end-of-turn countdown, cleanup on faint/
-- battle end, backing out of move-select after arming cancels cleanly,
-- and (now explicitly requested, superseding an earlier draft of this
-- file that deliberately skipped it) the animated grow/shrink sprite
-- sequence via a BattleState:drawBattlerPic wrap -- real draw-code, an
-- explicit one-time exception to the standing "leave canvas untouched"
-- rule, same as the size-up value itself was.
--
-- Deliberately NOT ported: the reference mod's DRAMATIC_SHAPE 3D-stadium
-- scale hook (this project doesn't depend on DRAMATIC_SHAPE).
--
-- Stage curve: 4 stages, CUMULATIVE fraction of total growth reached by
-- the end of each -- 10% / 25% / 45% / 100%, exact user spec. Each stage
-- is a ramp (eases from the previous stage's fraction to this one's) then
-- a pause holding flat at that fraction -- the "dramatic pause." Pause
-- length (0.4s per stage) is explicit user spec; ramp length (0.3s) is
-- NOT specified by the user -- a reasonable default filled in here,
-- flagged as an inferred value rather than a stated one.
return function(mod, GimmickRing)
  local BattleState = require("src.battle.BattleState")

  -- Confirmed bug, fixed here: this used to be `if BattleState
  -- .__galarGigantamaxWrapped then return end` -- an early RETURN gating
  -- the entire rest of this function, including the fully independent
  -- Gen 2 wrap block further down (already self-gated on its own
  -- Gen2BattleState.__galarGigantamaxWrapped flag) and the shared Max
  -- Move/MAXGUARD/GimmickRing registration and lifecycle events, all of
  -- which the header comments already describe as generation-agnostic
  -- or Gen-2-aware in their own right. On any re-init after the first
  -- pass (this engine explicitly supports dev-mode hot reload), the
  -- whole function silently returned here forever. Now only the
  -- genuinely Gen 1-BattleState-specific method patches below are
  -- skipped on a repeat pass.
  -- Declared HERE, above every `if not skipGen1` block, because two of them
  -- need it and they are SIBLINGS: it is assigned in the turn-resolution
  -- block and called again from the update loop, and a local declared in the
  -- first is invisible to the second. Lua compiles that second use to a
  -- GLOBAL read -- nil, and it raises only when reached, which is the moment
  -- a Dynamax grow sequence finishes and the held turn is finally resolved.
  -- The symptom is a Max Move that plays its whole grow animation and then
  -- does nothing at all.
  local vanillaResolveTurn
  local skipGen1 = BattleState.__galarGigantamaxWrapped == true
  if not skipGen1 then
    BattleState.__galarGigantamaxWrapped = true
  end

  -- Gen 2 support (explicit user decision: "the whole system is to affect
  -- BOTH generations"). Gen 2's battle engine is architecturally split --
  -- pure logic in src/battle/gen2/Battle.lua, UI/input/draw in
  -- src/ui/gen2/BattleState.lua (its own separate class) -- unlike Gen 1
  -- where one class does both, so every wrap below needs a real Gen 2
  -- counterpart rather than an `if gen2` branch bolted onto the Gen 1
  -- ones. Both requires are optional (absent under a Red/Blue/Yellow-only
  -- boot).
  local GameVersionForGigantamax = require("src.core.GameVersion")
  local isGen2BootForGigantamax = GameVersionForGigantamax.generation(GameVersionForGigantamax.get()) == 2
  local gen2Ok, Gen2Battle = pcall(require, "src.battle.gen2.Battle")
  local gen2UiOk, Gen2BattleState = pcall(require, "src.ui.gen2.BattleState")
  -- Only warn when a Gen 2 module SHOULD exist and doesn't -- a genuine
  -- Red/Blue/Yellow-only boot never has these files at all, and that's
  -- expected/normal (see the comment above), not worth logging every
  -- single Gen 1 boot. Logged BEFORE the ok/nil normalization below,
  -- since Gen2Battle/Gen2BattleState hold the pcall error string (not
  -- the module) on failure.
  if isGen2BootForGigantamax then
    if not gen2Ok then
      mod.log:warn("galar_gmax_dex: gigantamax: src.battle.gen2.Battle not available on a gen 2 boot: %s",
        tostring(Gen2Battle))
    end
    if not gen2UiOk then
      mod.log:warn("galar_gmax_dex: gigantamax: src.ui.gen2.BattleState not available on a gen 2 boot: %s",
        tostring(Gen2BattleState))
    end
  end
  Gen2Battle = gen2Ok and Gen2Battle or nil
  Gen2BattleState = gen2UiOk and Gen2BattleState or nil
  local function isGen2Battle(battle)
    return Gen2Battle ~= nil and battle ~= nil and getmetatable(battle) == Gen2Battle
  end

  -- Same ctx-vs-positional discriminator modern_combat.lua's own
  -- normalize() uses -- Gen 1's move_effects run(ctx) hands a ctx facade
  -- with a real .battle field; Gen 2's run(battle, attacker, defender,
  -- ...) is positional args. GGD_MAXGUARD_EFFECT is the one move_effects
  -- handler this file registers that a battler can actually select mid-
  -- battle (the Max Move data rows below are all NO_ADDITIONAL_EFFECT,
  -- dispatched by neither engine's custom handler path at all) -- now
  -- that Dynamax reaches Gen 2 too, it needs to handle both call shapes,
  -- not just the ctx one it was written against originally.
  local function normalize(a, b, c)
    if type(a) == "table" and a.battle ~= nil then
      return { battle = a.battle, user = a.user, target = a.target, gen2 = false }
    end
    return { battle = a, user = b, target = c, gen2 = true }
  end

  -- =====================================================================
  -- Data: type list, power tables, Max Move names (verbatim from the
  -- reference mod's own bucket table -- these numbers are Bulbapedia's
  -- documented Max Move power brackets, not something to reinvent).
  -- =====================================================================
  local TYPES = {
    "NORMAL", "FIRE", "WATER", "ELECTRIC", "GRASS", "ICE", "FIGHTING",
    "POISON", "GROUND", "FLYING", "PSYCHIC_TYPE", "BUG", "ROCK", "GHOST",
    "DRAGON", "DARK", "STEEL", "FAIRY",
  }
  local WEAKEN_TYPES = { FIGHTING = true, POISON = true }
  local POWER_TABLE = {
    boost = { { 150, 150 }, { 110, 140 }, { 75, 130 }, { 65, 120 },
              { 55, 110 }, { 45, 100 }, { 1, 90 } },
    weaken = { { 150, 100 }, { 110, 95 }, { 75, 90 }, { 65, 85 },
               { 55, 80 }, { 45, 75 }, { 1, 70 } },
  }
  local MULTIHIT_POWER_TABLE = {
    boost = { { 65, 150 }, { 55, 140 }, { 20, 130 }, { 18, 100 }, { 1, 90 } },
    weaken = { { 65, 100 }, { 55, 90 }, { 20, 80 }, { 18, 75 }, { 1, 70 } },
  }
  local MAX_MOVE_NAMES = {
    NORMAL = "MAX STRIKE", FIRE = "MAX FLARE", WATER = "MAX GEYSER",
    ELECTRIC = "MAX LIGHTNING", GRASS = "MAX OVERGROWTH", ICE = "MAX HAILSTORM",
    FIGHTING = "MAX KNUCKLE", POISON = "MAX OOZE", GROUND = "MAX QUAKE",
    FLYING = "MAX AIRSTREAM", PSYCHIC_TYPE = "MAX MINDSTORM", BUG = "MAX FLUTTERBY",
    ROCK = "MAX ROCKFALL", GHOST = "MAX PHANTASM", DRAGON = "MAX WYRMWIND",
    DARK = "MAX DARKNESS", STEEL = "MAX STEELSPIKE", FAIRY = "MAX STARFALL",
  }
  local MAXGUARD_ID = "GGD_MAXGUARD"
  local DYNAMAX_TURNS = 3

  local SIZE_LEVELS = { 1.2, 1.4, 1.8, 2.2, 2.6 }
  local DEFAULT_SIZE = 1.4

  local function clampLevel(v, levels, default)
    v = tonumber(v)
    if not v then return default end
    local best, bestDiff = default, math.huge
    for _, level in ipairs(levels) do
      local diff = math.abs(level - v)
      if diff < bestDiff then best, bestDiff = level, diff end
    end
    return best
  end

  local function currentSizeMultiplier()
    return clampLevel(mod.options:get("gigantamax_size"), SIZE_LEVELS, DEFAULT_SIZE)
  end

  -- =====================================================================
  -- Grow/shrink sequence timing: 4 stages, CUMULATIVE fraction of total
  -- growth (finalScale - 1.0) reached by the end of each -- exact user
  -- spec (+10%, +15% -> 25%, +20% -> 45%, +55% -> 100%). PAUSE_DURATION
  -- (0.4s, holding flat at that stage's target -- the "dramatic pause")
  -- is explicit user spec; RAMP_DURATION (easing INTO that target) is
  -- not specified and is a reasonable filled-in default, not a stated
  -- value.
  -- =====================================================================
  local STAGE_FRACTIONS = { 0.10, 0.25, 0.45, 1.00 }
  local RAMP_DURATION = 0.3
  local PAUSE_DURATION = 0.4
  local STAGE_DURATION = RAMP_DURATION + PAUSE_DURATION
  local SEQUENCE_DURATION = STAGE_DURATION * #STAGE_FRACTIONS

  local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
  end

  -- Fraction (0..1) of total growth reached at `elapsed` seconds into a
  -- GROW sequence (shrink mirrors this by feeding SEQUENCE_DURATION -
  -- elapsed -- see the update loop below).
  local function growFractionAt(elapsed)
    if elapsed <= 0 then return 0 end
    if elapsed >= SEQUENCE_DURATION then return 1.0 end
    local stageIndex = math.min(#STAGE_FRACTIONS, math.floor(elapsed / STAGE_DURATION) + 1)
    local localT = elapsed - (stageIndex - 1) * STAGE_DURATION
    local fromFrac = stageIndex == 1 and 0 or STAGE_FRACTIONS[stageIndex - 1]
    local toFrac = STAGE_FRACTIONS[stageIndex]
    if localT >= RAMP_DURATION then return toFrac end
    return fromFrac + (toFrac - fromFrac) * easeOutCubic(localT / RAMP_DURATION)
  end

  local function scaleAtFraction(fraction, finalScale)
    return 1.0 + (finalScale - 1.0) * fraction
  end

  -- =====================================================================
  -- Logic: pure-ish helpers
  -- =====================================================================
  local function maxMoveId(typeId, category, power)
    return ("GGD_MAX_%s_%s_%d"):format(typeId, category, power)
  end

  local function bucketPower(basePower, class, isMultiHit)
    local tbl = isMultiHit and MULTIHIT_POWER_TABLE[class] or POWER_TABLE[class]
    for _, pair in ipairs(tbl) do
      if basePower >= pair[1] then return pair[2] end
    end
    return basePower
  end

  -- Given a base move id, returns the Max Move id it converts to (or
  -- MAXGUARD_ID for a status move), or nil if the base move isn't known.
  local function computeMaxMoveId(baseMoveId, movesData)
    local def = movesData and movesData[baseMoveId]
    if not def or not def.type then return nil end
    if def.category == "status" or not def.power or def.power <= 0 then
      return MAXGUARD_ID
    end
    local class = WEAKEN_TYPES[def.type] and "weaken" or "boost"
    local power = bucketPower(def.power or 1, class, def.multiHit ~= nil)
    local category = def.category or "physical"
    return maxMoveId(def.type, category, power)
  end

  -- =====================================================================
  -- Per-battle state -- keyed by the live battle table, cleared on
  -- battle.ended (mirrors the reference mod's own dynaxState pattern).
  -- =====================================================================
  local gState = {}

  local function stateFor(battle)
    local st = gState[battle]
    if not st then
      st = { active = false, usedThisBattle = false, turnsLeft = 0 }
      gState[battle] = st
    end
    return st
  end

  -- Gigantamax does not cure major status or an existing Leech Seed. It
  -- only removes temporary battle conditions and prevents them from
  -- interrupting the Gigantamaxed battler for its three active turns.
  -- Gen 2's equivalents live in one bag (battle:volatile(mon)) instead of
  -- directly on the battler -- Battle:clearVolatile exists but is much
  -- broader (also wipes substitute/leech seed/protect/encore/rollout-
  -- lock/etc and calls untransform, confirmed gen2/Battle.lua:981-985),
  -- so this hand-nulls just the matching fields instead, mirroring Gen
  -- 1's own narrow clear exactly rather than reaching for that.
  local function clearVolatiles(battle, who, gen2)
    if gen2 then
      local vol = battle:volatile(who)
      vol.confuseCount = nil
      vol.disabled, vol.disabledTurns = nil, nil
      vol.bideTurns, vol.bideStored = nil, nil
      vol.flinched = nil
      return
    end
    who.confusedTurns = nil
    who.disabledTurns, who.disabledSlot = nil, nil
    who.bideTurns, who.bideDamage = nil, nil
    who.thrashTurns, who.thrashMove, who.thrashAnnounced = nil, nil, nil
    who.charging, who.chargeReady = nil, nil
    who.trappingTurns, who.boundTurns = nil, nil
    who.trapDamage, who.trapMove = nil, nil
    who.invulnerable = nil
    who.flinched = false
  end

  -- battle.player IS the mon itself on Gen 2 (confirmed: no per-mon
  -- battler wrapper exists there, unlike Gen 1's battle.player.mon).
  local function playerMonOf(battle, gen2)
    return gen2 and battle.player or (battle.player and battle.player.mon)
  end

  -- Selecting GIGANTAMAX from the ring prepares the Max Move list, but
  -- does not yet boost HP/size or start the three-turn timer -- those
  -- begin only when the player picks one of the prepared Max Moves (see
  -- the resolveTurn wrap below), matching the real games' two-step
  -- commitment (choose the gimmick, THEN choose the move that triggers
  -- the actual transformation).
  local function prepareGigantamax(battle)
    local gen2 = isGen2Battle(battle)
    local st = stateFor(battle)
    if st.prepared or st.active or st.usedThisBattle then return false end
    local mon = playerMonOf(battle, gen2)
    if not mon or not mon.moves then return false end

    local moves = mon.moves
    -- Gen 1 only -- confirmed Gen 2 has no separate curMoves alias at all
    -- (battle.player.moves IS what the UI reads too), so this is simply
    -- nil there and the guards below already no-op safely.
    local curMoves = battle.player.curMoves
    local originalIds = {}
    for i, mv in ipairs(moves) do
      originalIds[i] = mv.id
      local maxId = computeMaxMoveId(mv.id, battle.data.moves)
      if maxId then
        mv.id = maxId
        if curMoves and curMoves[i] then curMoves[i].id = maxId end
      end
    end

    st.prepared = true
    st.originalIds = originalIds
    return true
  end

  -- Doubles HP (preserving the current HP fraction) and starts the
  -- 3-turn timer immediately, then starts the GROW sequence -- the
  -- pending action (the Max Move the player actually chose) resolves
  -- only once that sequence finishes (see the update loop below), same
  -- two-step shape the reference mod uses ("HP has not changed yet" is
  -- no longer true past this point -- backing out after this doesn't
  -- happen, since selection already committed to resolving the turn).
  local function beginGigantamaxSequence(battle, pendingAction)
    local gen2 = isGen2Battle(battle)
    local st = stateFor(battle)
    if not st.prepared or st.active then return false end
    local mon = playerMonOf(battle, gen2)
    if not mon then return false end

    -- Gen 2 caches max HP in TWO fields that can drift (mon.stats.hp AND
    -- mon.maxHp -- confirmed gen2/Battle.lua reads mon.maxHp first at
    -- 10+ call sites, gen2/Mon.lua:415-419's own level-up recompute keeps
    -- both in sync) -- both have to double together, not just one, or
    -- almost every native HP read on Gen 2 would keep seeing the old max.
    local maxHp = mon.stats and mon.stats.hp
    if gen2 then maxHp = mon.maxHp or maxHp end
    if maxHp and maxHp > 0 then
      local pct = mon.hp / maxHp
      st.originalMaxHP = maxHp
      local newMax = maxHp * 2
      if mon.stats then mon.stats.hp = newMax end
      if gen2 then mon.maxHp = newMax end
      mon.hp = math.max(1, math.floor(newMax * pct + 0.5))
      if gen2 then
        -- The HP bar's "shown" value lives on the UI SCREEN on Gen 2
        -- (self.shownHp = {player=, enemy=}, confirmed src/ui/gen2/
        -- BattleState.lua:359-362), not on the mon -- the pure Battle
        -- object has no reference to its own screen, so the Gen 2 wrap
        -- block below stashes one (battle.__uiScreen) the moment it sees
        -- one, which by this point it always has (submit/update both run
        -- long before any Gigantamax action can be armed).
        local screen = battle.__uiScreen
        if screen and screen.shownHp then screen.shownHp.player = mon.hp end
      else
        battle.player.shownHP = mon.hp
      end
    end

    st.active = true
    st.prepared = false
    st.usedThisBattle = true
    st.turnsLeft = DYNAMAX_TURNS
    -- Read once here, not live per-frame, so a mid-battle option change
    -- never alters an already-active Gigantamax's size.
    st.finalScale = currentSizeMultiplier()
    st.displayScale = 1.0
    st.sequence = { kind = "grow", elapsed = 0 }
    st.pendingAction = pendingAction
    clearVolatiles(battle, battle.player, gen2)
    return true
  end

  -- The pure data revert (move ids, HP, flags) -- called once a shrink
  -- sequence finishes playing, or immediately when there was nothing to
  -- animate (armed but never actually grew).
  local function finishRevertData(battle)
    local gen2 = isGen2Battle(battle)
    local st = gState[battle]
    if not st or (not st.active and not st.prepared) then return end
    local mon = playerMonOf(battle, gen2)
    if mon and mon.moves and st.originalIds then
      local curMoves = battle.player.curMoves
      -- Encore x Dynamax: if this mon got Encored into one of its own
      -- (now-reverting) Max Move ids, state.encore is about to go stale
      -- -- Battle:forcedMove would stop finding it in mon.moves at all
      -- and quietly drop Encore early. Fix the stored id up to the real
      -- base move it actually represents in the same pass that reverts
      -- mon.moves itself, so Encore keeps forcing the right (now-base)
      -- move for its remaining duration instead.
      local vol = gen2 and battle:volatile(mon)
      for i, id in ipairs(st.originalIds) do
        if vol and vol.encore and mon.moves[i] and mon.moves[i].id == vol.encore then
          vol.encore = id
        end
        if mon.moves[i] then mon.moves[i].id = id end
        if curMoves and curMoves[i] then curMoves[i].id = id end
      end
    end
    if mon and st.originalMaxHP then
      local curMax = mon.stats and mon.stats.hp
      if gen2 then curMax = mon.maxHp or curMax end
      if curMax and curMax > 0 then
        local pct = mon.hp / curMax
        if mon.stats then mon.stats.hp = st.originalMaxHP end
        if gen2 then mon.maxHp = st.originalMaxHP end
        mon.hp = math.max(0, math.floor(st.originalMaxHP * pct + 0.5))
        if gen2 then
          local screen = battle.__uiScreen
          if screen and screen.shownHp then screen.shownHp.player = mon.hp end
        else
          battle.player.shownHP = mon.hp
        end
      end
    end
    st.active = false
    st.prepared = false
    st.sequence = nil
    st.displayScale = nil
    st.finalScale = nil
    st.pendingAction = nil
    st.endingBattle = nil
  end

  -- Starts the SHRINK sequence (mirrors the grow curve) if there's a
  -- live displayScale to animate down from; otherwise reverts instantly
  -- -- e.g. Gigantamax was armed from the ring but the player backed out
  -- before ever choosing a Max Move, so nothing ever grew.
  local function revertGigantamax(battle, resumePhase, endingBattle)
    local st = gState[battle]
    if not st or (not st.active and not st.prepared) then return end
    if st.active and st.displayScale then
      st.sequence = { kind = "shrink", elapsed = 0, resumePhase = resumePhase,
                      endingBattle = endingBattle }
    else
      finishRevertData(battle)
    end
  end

  -- Gen 1's action shape keys the move id as `.id`; Gen 2's as `.move`
  -- (confirmed src/ui/gen2/BattleState.lua:1581-1587's own
  -- `self:submit({kind=, move=})` call site).
  local function hasPreparedMaxMove(battle, action)
    local gen2 = isGen2Battle(battle)
    local st = gState[battle]
    local moveId = action and (gen2 and action.move or action.id)
    if not st or not st.prepared or not moveId then return false end
    return moveId == MAXGUARD_ID or moveId:match("^GGD_MAX_") ~= nil
  end

  -- Mirrors BattleState:enemyMonFainted's own alive-scan (a wild battle's
  -- one enemy has no enemyParty at all; a trainer's does). Gen 1 flags a
  -- wild battle via `battle.kind ~= "trainer"`; Gen 2 uses a real boolean
  -- instead (`self.wild`, confirmed gen2/Battle.lua:244/253) -- reading
  -- Gen 1's own field name against a Gen 2 battle would silently always
  -- read nil (~= "trainer" is always true), wrongly treating every enemy
  -- faint as "the whole trainer team is down."
  local function allEnemiesFainted(battle)
    local gen2 = isGen2Battle(battle)
    local isWild = gen2 and battle.wild or (battle.kind ~= "trainer")
    if isWild then return true end
    for _, mon in ipairs(battle.enemyParty or {}) do
      if mon.hp > 0 then return false end
    end
    return true
  end

  -- =====================================================================
  -- Registration: Max Move data, MAX GUARD move + effect
  -- =====================================================================
  for _, typeId in ipairs(TYPES) do
    if mod.content.type_chart:get(typeId) then
      local class = WEAKEN_TYPES[typeId] and "weaken" or "boost"
      for _, cat in ipairs({ "physical", "special" }) do
        for _, pair in ipairs(POWER_TABLE[class]) do
          local power = pair[2]
          local id = maxMoveId(typeId, cat, power)
          mod.content.moves:register(id, {
            id = id, name = MAX_MOVE_NAMES[typeId] or ("MAX " .. typeId),
            type = typeId, power = power, accuracy = 100, pp = 10,
            effect = "NO_ADDITIONAL_EFFECT", category = cat,
          })
        end
      end
    else
      mod.log:warn("galar_gmax_dex: gigantamax: type %s not in type_chart, skipping its Max Moves", typeId)
    end
  end

  mod.content.move_effects:register("GGD_MAXGUARD_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user = n.user
      local streak = user.maxGuardStreak or 0
      local chance = math.max(1, math.floor(256 / (2 ^ streak)))
      local roll = n.gen2 and n.battle:roller()(256) or n.battle.rng(0, 255)
      if roll < chance then
        user.maxGuard = true
        user.maxGuardStreak = streak + 1
        return {}
      end
      user.maxGuardStreak = 0
      if n.gen2 then
        n.battle:markMissed()
        n.battle:emit({ kind = "message", text = "But it failed!" })
        return {}
      end
      return { n.battle:romText("_ButItFailedText", "But, it failed!") }
    end,
  })
  mod.content.moves:register(MAXGUARD_ID, {
    id = MAXGUARD_ID, name = "MAX GUARD", type = "NORMAL", power = 0,
    accuracy = 100, pp = 10, priority = 4,
    effect = "GGD_MAXGUARD_EFFECT", category = "status",
  })

  -- =====================================================================
  -- Encore x Dynamax (Gen 2 only -- Encore has no Gen 1 equivalent at
  -- all, confirmed elsewhere this mod). Only the player can ever be
  -- Dynamaxed in this pass (confirmed: no code path anywhere in this
  -- file arms/grows/reverts it for battle.enemy), so "is the target
  -- currently Dynamaxed" only ever needs checking against battle.player.
  -- The other interaction rule (a mon Encored right as its own Dynamax
  -- ends gets forced into its base move, not a stale Max Move id) is
  -- handled above, inside finishRevertData's own revert loop -- not
  -- here, since it needs st.originalIds at exactly the moment the ids
  -- are reverting, not at Encore's own cast time.
  -- =====================================================================
  if Gen2Battle then
    local nativeEncoreEffect = Gen2Battle.MOVE_EFFECTS.EFFECT_ENCORE
    if nativeEncoreEffect then
      mod.content.move_effects:override("EFFECT_ENCORE", {
        kind = "primary",
        run = function(battle, attacker, defender, def, moveId, sureHit)
          local st = gState[battle]
          if defender == battle.player and st and st.active then
            battle:markMissed()
            battle:emit({ kind = "message", text = "But it failed!" })
            return
          end
          return nativeEncoreEffect(battle, attacker, defender, def, moveId, sureHit)
        end,
      })
    end
  end

  -- =====================================================================
  -- Gimmick ring registration
  -- =====================================================================
  -- Internal id stays "GIGANTAMAX" (the markActivated key, not GUI text).
  -- name/label corrected to "Dynamax" -- explicit correction: Dynamax is
  -- the general mechanic; Gigantamax is only the alternate-form subset of
  -- it for specific species, not a term that should stand in for the
  -- mechanic's own name wherever it's shown to the player.
  GimmickRing.register({
    id = "GIGANTAMAX",
    name = "Dynamax",
    label = "DYNAMAX",
    priority = 100,
    canActivate = function(battle, battler, state)
      local st = stateFor(battle)
      if st.prepared or st.active or st.usedThisBattle then return false, "already used" end
      local mon = playerMonOf(battle, isGen2Battle(battle))
      if not mon or not mon.moves or #mon.moves == 0 then return false, "no moves" end
      return true
    end,
    activate = function(battle)
      if prepareGigantamax(battle) then
        -- The player now chooses their Max Move; resolveTurn below
        -- starts the actual transformation immediately before that move
        -- resolves. "pending" tells the ring not to mark this activated
        -- yet -- markActivated fires from resolveTurn once it really
        -- begins.
        return "pending"
      end
      return false
    end,
  })

  -- =====================================================================
  -- Size-up + animation: BattleState:drawBattlerPic (confirmed real,
  -- BattleState.lua:4875, signature (battler, x, y, scale)) is the one
  -- place the engine already renders the player's battle pic through a
  -- normal draw call -- wrapping it (not drawPicsLayer/the canvas
  -- pipeline directly) preserves the battle's palette, clipping, and
  -- every existing pic effect exactly as the reference mod's own version
  -- does. Only fires for self.player (this pass is player-only, matching
  -- the reference mod's own documented scope) while st.displayScale is
  -- set, scaling around the picture's bottom-centre so it grows upward
  -- from the ground rather than sliding off its battle slot.
  -- =====================================================================
  if not skipGen1 then
  local vanillaDrawBattlerPic = BattleState.drawBattlerPic
  function BattleState:drawBattlerPic(battler, x, y, scale)
    local st = gState[self]
    local factor = st and st.displayScale
    if factor and battler == self.player and battler.sprite then
      local width = battler.sprite:getWidth() * scale
      local height = battler.sprite:getHeight() * scale
      local anchorX, anchorY = x + width / 2, y + height
      love.graphics.push()
      love.graphics.translate(anchorX, anchorY)
      love.graphics.scale(factor, factor)
      love.graphics.translate(-anchorX, -anchorY)
      vanillaDrawBattlerPic(self, battler, x, y, scale)
      love.graphics.pop()
      return
    end
    return vanillaDrawBattlerPic(self, battler, x, y, scale)
  end

  -- =====================================================================
  -- Turn resolution: a prepared Max Move starts the grow sequence and
  -- STOPS here -- the turn itself (st.pendingAction) only actually
  -- resolves once that sequence finishes, from the update loop below, so
  -- the player watches the full grow-in before their Max Move plays out.
  -- =====================================================================
  vanillaResolveTurn = BattleState.resolveTurn
  function BattleState:resolveTurn(playerAction)
    if hasPreparedMaxMove(self, playerAction) then
      if beginGigantamaxSequence(self, playerAction) then
        GimmickRing.markActivated(self, "GIGANTAMAX", self.player)
        return
      end
    end
    return vanillaResolveTurn(self, playerAction)
  end
  end

  -- Max Guard blocks normal direct moves by forcing their accuracy check
  -- to fail; residual poison/burn/Leech Seed never use this hook and
  -- remain intact. New Leech Seed also fails against an active Gigantamax
  -- battler; a seed already on it before Gigantamax keeps draining.
  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    local move, target = ctx.move, ctx.target
    if target and target.maxGuard and move and move.id ~= MAXGUARD_ID then
      return false
    end
    local st = gState[ctx.battle]
    -- Real bug fixed 2026-08-28: "LEECH_SEED_EFFECT" matches NEITHER
    -- Leech Seed's own real native effect strings (gen1Effect=
    -- "NO_ADDITIONAL_EFFECT", gen2Effect="EFFECT_NORMAL_HIT", confirmed
    -- by direct read of national_dex's own record) NOR this mod's own
    -- real patched one -- main.lua's own CUSTOM_EFFECT_PATCH table
    -- points BOTH Leech Seed and Sappy Seed at the same real id,
    -- "GALAR_LEECHSEED_EFFECT" -- so this check never matched at all,
    -- on either generation. Checking the real patched id catches both
    -- moves that share it in one comparison, the same reason main.lua
    -- itself maps them both to it rather than two separate patches.
    if st and st.active and target == ctx.battle.player
        and move and move.effect == "GALAR_LEECHSEED_EFFECT" then
      return false
    end
    return next(ctx)
  end)

  -- Choosing any move other than MAX GUARD resets its own decaying-streak
  -- back to 100% -- this battler's next attempt (this battle, or a fresh
  -- mon after a switch) starts fresh.
  if not skipGen1 then
  local vanillaPerformMove = BattleState.performMove
  function BattleState:performMove(user, target, moveInst, isCalled)
    if moveInst and moveInst.id ~= MAXGUARD_ID then
      user.maxGuardStreak = nil
    end
    return vanillaPerformMove(self, user, target, moveInst, isCalled)
  end
  end

  -- Gen 2 equivalent of the streak-reset above -- Battle:useMove is the
  -- one real dotted function both playerAttack/enemyAttack funnel every
  -- move through (same confirmed seam modern_status_effects.lua's own
  -- Gen 2 fizzle wrap already uses), so this needs no separate
  -- player/enemy handling.
  if Gen2Battle then
    local vanillaUseMoveForMaxGuard = Gen2Battle.useMove
    function Gen2Battle:useMove(attacker, defender, moveId)
      if moveId ~= MAXGUARD_ID then
        attacker.maxGuardStreak = nil
      end
      return vanillaUseMoveForMaxGuard(self, attacker, defender, moveId)
    end
  end

  -- While a grow/shrink sequence is running it fully owns the frame --
  -- native update is skipped entirely (self:tickFx() keeps presentation
  -- timers like message/HP-bar animation alive, same as the reference
  -- mod does here), st.displayScale is advanced along the stage curve,
  -- and completion either resolves the deferred Max Move (grow) or
  -- finishes the data revert and hands the phase back (shrink).
  --
  -- Sprite frame-cycling (main.lua's installSpriteAnimation, a SEPARATE
  -- wrap further down this same update chain) doesn't run on its own
  -- while native update is skipped -- confirmed live (both sprites froze
  -- for the whole grow/shrink sequence) -- so it's called directly here
  -- too, same fix as the gimmick ring's own update branch.
  --
  -- gigantamax_skip_animation (options.lua): when on, a sequence
  -- completes on the very frame it starts -- frac jumps straight to its
  -- end value and elapsed is forced past SEQUENCE_DURATION, so the exact
  -- same completion path below runs immediately instead of over several
  -- seconds. "0 seconds and 0 stages," exactly as specified, without a
  -- separate instant-vs-animated code path to keep in sync.
  local function skipAnimationOption()
    return mod.options:get("gigantamax_skip_animation") == "true"
  end

  if not skipGen1 then
  local vanillaUpdate = BattleState.update
  function BattleState:update(dt)
    local st = gState[self]
    if st and st.sequence then
      self:tickFx()
      if mod.exports.advanceBattleSprites then
        pcall(mod.exports.advanceBattleSprites, self, dt)
      end
      local seq = st.sequence
      local skip = skipAnimationOption()
      seq.elapsed = seq.elapsed + dt
      local frac
      if skip then
        frac = seq.kind == "shrink" and 0 or 1
        seq.elapsed = SEQUENCE_DURATION
      elseif seq.kind == "shrink" then
        frac = growFractionAt(math.max(0, SEQUENCE_DURATION - seq.elapsed))
      else
        frac = growFractionAt(seq.elapsed)
      end
      st.displayScale = scaleAtFraction(frac, st.finalScale)

      if seq.elapsed >= SEQUENCE_DURATION then
        if seq.kind == "grow" then
          st.sequence = nil
          st.displayScale = st.finalScale
          local action = st.pendingAction
          st.pendingAction = nil
          return vanillaResolveTurn(self, action)
        end
        -- Shrink finished: only the normal three-turn expiry hands the
        -- phase back to the menu -- the battle-ending case leaves
        -- self.phase alone (the engine's own end-of-battle transition
        -- owns it) and just drops this battle's state.
        local endingBattle = seq.endingBattle
        local resumePhase = seq.resumePhase
        finishRevertData(self)
        if endingBattle then
          gState[self] = nil
        else
          self.phase = resumePhase or "menu"
        end
      end
      return
    end

    local result = vanillaUpdate(self, dt)
    -- Backing out of move-select after arming Gigantamax (picked it from
    -- the ring, then left move-select without choosing a Max Move)
    -- restores the ordinary move list -- HP hasn't changed yet at that
    -- point (that only happens once a Max Move is actually chosen), so
    -- this is a clean, silent, instant cancel -- never animated.
    st = gState[self]
    if st and st.prepared and self.phase ~= "moveSelect" then
      finishRevertData(self)
    end
    return result
  end
  end

  -- =====================================================================
  -- Gen 2: parallel wrap block on src.ui.gen2.BattleState (only installed
  -- if that module loads). Same gState/gen-aware helpers above -- only
  -- the actual patch targets differ, since Gen 2 splits UI (this class)
  -- from pure logic (src.battle.gen2.Battle) into two separate classes
  -- instead of Gen 1's combined one.
  -- =====================================================================
  if Gen2BattleState and not Gen2BattleState.__galarGigantamaxWrapped then
    Gen2BattleState.__galarGigantamaxWrapped = true

    -- BattleState:picScale is the real, simpler Gen 2 draw-scale mutate
    -- point (confirmed src/ui/gen2/BattleState.lua:518-524): it already
    -- returns a plain multiplier that drawPic applies internally, so
    -- overriding its return value replaces the whole push/translate/
    -- scale/pop dance Gen 1's drawBattlerPic wrap needed -- no separate
    -- draw-call wrap required here at all.
    local vanillaPicScale = Gen2BattleState.picScale
    function Gen2BattleState:picScale(path, mon, back)
      if back and self.battle and mon == self.battle.player then
        local st = gState[self.battle]
        if st and st.displayScale then return st.displayScale end
      end
      return vanillaPicScale(self, path, mon, back)
    end

    -- BattleState:submit is the one funnel every player move passes
    -- through before Battle:takeTurn (confirmed src/ui/gen2/BattleState
    -- .lua:1581-1587) -- the direct Gen 2 analog of Gen 1's resolveTurn
    -- wrap above. A prepared Max Move/MAXGUARD action defers the same
    -- way: skip native submit entirely, start the grow sequence, and let
    -- the update wrap below replay the action once it finishes.
    local vanillaSubmit = Gen2BattleState.submit
    function Gen2BattleState:submit(action)
      self.battle.__uiScreen = self
      if action and action.kind == "move" and hasPreparedMaxMove(self.battle, action) then
        if beginGigantamaxSequence(self.battle, action) then
          GimmickRing.markActivated(self.battle, "GIGANTAMAX", self.battle.player)
          return
        end
      end
      return vanillaSubmit(self, action)
    end

    -- Animation driver, mirroring the Gen 1 wrap's own math/shape exactly
    -- (same gState/st.sequence fields). Gen 2's own screen has no
    -- tickFx-equivalent HUD-timer method (grepped, none exists) so that
    -- call is simply omitted; sprite frame-cycling still needs the same
    -- manual pump while native update is skipped, called against
    -- self.battle since that's the object with .player/.enemy on Gen 2
    -- (mirrors main.lua's own advanceBattleSprites reuse).
    local vanillaUpdate2 = Gen2BattleState.update
    function Gen2BattleState:update(dt)
      self.battle.__uiScreen = self
      local st = gState[self.battle]
      if st and st.sequence then
        if mod.exports.advanceBattleSprites then
          pcall(mod.exports.advanceBattleSprites, self.battle, dt)
        end
        local seq = st.sequence
        local skip = skipAnimationOption()
        seq.elapsed = seq.elapsed + dt
        local frac
        if skip then
          frac = seq.kind == "shrink" and 0 or 1
          seq.elapsed = SEQUENCE_DURATION
        elseif seq.kind == "shrink" then
          frac = growFractionAt(math.max(0, SEQUENCE_DURATION - seq.elapsed))
        else
          frac = growFractionAt(seq.elapsed)
        end
        st.displayScale = scaleAtFraction(frac, st.finalScale)

        if seq.elapsed >= SEQUENCE_DURATION then
          if seq.kind == "grow" then
            st.sequence = nil
            st.displayScale = st.finalScale
            local action = st.pendingAction
            st.pendingAction = nil
            return vanillaSubmit(self, action)
          end
          local endingBattle = seq.endingBattle
          local resumePhase = seq.resumePhase
          finishRevertData(self.battle)
          if endingBattle then
            gState[self.battle] = nil
          else
            self.phase = resumePhase or "menu"
          end
        end
        return
      end

      local result = vanillaUpdate2(self, dt)
      -- Backing out of move-select after arming Gigantamax, same clean
      -- instant cancel as the Gen 1 branch above -- Gen 2's own
      -- move-select phase is named "moves", not "moveSelect".
      st = gState[self.battle]
      if st and st.prepared and self.phase ~= "moves" then
        finishRevertData(self.battle)
      end
      return result
    end
  end

  -- =====================================================================
  -- Lifecycle: countdown, and the two cleanup triggers
  -- =====================================================================
  mod.events:on("battle.started", function(ev)
    gState[ev.battle] = { active = false, usedThisBattle = false, turnsLeft = 0 }
  end)

  mod.events:on("battle.turn_ended", function(ev)
    if ev.battle.player then ev.battle.player.maxGuard = nil end
    if ev.battle.enemy then ev.battle.enemy.maxGuard = nil end
    local st = gState[ev.battle]
    if st and st.active then
      st.turnsLeft = st.turnsLeft - 1
      if st.turnsLeft <= 0 then
        -- The final Max Move turn is fully resolved first; only THEN
        -- does the shrink sequence start and, once it finishes, hand
        -- the battle menu back.
        revertGigantamax(ev.battle, "menu", false)
      end
    end
  end)

  mod.events:on("battle.fainted", function(ev)
    local battle = ev.battle
    if ev.battler.isPlayer then
      -- The player's own mon fainting reverts instantly, same as the
      -- reference mod -- no time for a dramatic shrink on a fainted mon.
      finishRevertData(battle)
      return
    end
    -- The enemy fainting doesn't necessarily end the battle (a trainer's
    -- next mon may still be coming) -- only an actually-empty enemy side
    -- starts the battle-ending shrink here; otherwise the normal
    -- turnsLeft countdown above still applies.
    local st = gState[battle]
    if st and (st.active or st.prepared) and allEnemiesFainted(battle) then
      revertGigantamax(battle, nil, true)
    end
  end)

  -- Confirmed bug, fixed here: battle.ended fires AFTER
  -- self.game.stack:pop() (BattleState.lua's own comment on that emit --
  -- "the one choke point every battle -- wild, trainer, walk-up, scripted,
  -- link -- passes through on its way out"), meaning this BattleState will
  -- NEVER run :update() again once this handler fires. The previous
  -- version called the general revertGigantamax here, which -- if the mon
  -- was still actively Dynamaxed (a live displayScale, exactly the case
  -- when the player RUNs mid-duration) -- queues an ANIMATED shrink
  -- sequence instead of reverting immediately, expecting a future
  -- update() call to finish it. That call never comes, so
  -- finishRevertData (which only runs once the sequence completes) never
  -- fires, and mon.moves stays permanently stuck on Max Move ids in the
  -- saved party data. Reproduced live via RUN. There is no time left for
  -- any animation once the battle screen is already gone, regardless of
  -- how the battle ended (win/lose/run) or whether a shrink was already
  -- mid-flight from an earlier event in the same cascade (the previous
  -- "let it finish via update()" branch had the identical flaw) -- so
  -- this always finishes the data instantly now, same reasoning already
  -- used for the player-fainted case above.
  mod.events:on("battle.ended", function(ev)
    local battle = ev.battle
    local st = gState[battle]
    if st and (st.active or st.prepared) then
      finishRevertData(battle)
    end
    gState[battle] = nil
  end)

  -- =====================================================================
  -- Exports
  -- =====================================================================
  mod.exports.computeMaxMoveId = computeMaxMoveId

  mod.log:info("galar_gmax_dex: gigantamax gimmick installed (ring entry, staged grow/shrink animation)")
end
