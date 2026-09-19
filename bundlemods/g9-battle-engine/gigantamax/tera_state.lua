-- Tera Type storage + public API: per-mon read/modify, same shape and
-- reasoning as gigantamax/dynamax_state.lua's Dynamax Level/Gigantamax
-- Factor pair. We own this storage outright -- explicit user instruction
-- (2026-08-20): battle_forms's own "TERA TYPE" mod option (src/tera.lua)
-- is a placeholder built for testing before this API existed, and is
-- meant to be rewired to read from here later.
--
-- THAT REWIRING IS NOW IN PLACE, from our side -- round 8 (2026-09-06)
-- built the BATTLE_FORMS_STAMP mirror below; round 9 (2026-09-06) closed
-- the last two ways battle_forms could still decide a type itself (see
-- the OWNERSHIP GATE below). battle_forms resolves a Terastallization's
-- type as: its TERA TYPE option (if a concrete choice) -> its own
-- mon.battleFormsTeraType stamp (the field its Tera Orb shop writes) -> a
-- DVs-derived answer (src/teratype.lua). We keep that stamp equal to our
-- stored value, so with battle_forms' option reading as AUTO the stamp is
-- consulted first and OUR per-Pokemon stored type is the one its
-- activation actually deploys (writes into formTypes, announces, mirrors
-- back into mon.teraType as the same value). No battle_forms edit needed
-- -- this is the seam battle_forms itself documents as its per-mon
-- override. Per explicit user instruction ("battle forms should only keep
-- that dev power when enabled... everything else of tera is to be owned
-- by g9-battle-engine"), battle_forms' TERA TYPE option never
-- overrides anything: it is ALWAYS forced to AUTO by
-- ensureBattleFormsGate (below), and every active battler is pre-stamped
-- (modern_tera's ensureTeraStamps) so the DVs-derived fallback is
-- unreachable too -- battle_forms only reports WHEN tera triggers; WHAT
-- type deploys is always this mod's answer. Round 104 (2026-09-10)
-- removed the bf_tera_dev escape hatch that used to let battle_forms'
-- dev choice win while it was ON; the gate is now unconditional.
-- battle_forms' own activation flow (menu cell, once-per-battle registry
-- slot) is otherwise untouched. This file owns the STORED VALUE and now
-- the type battle_forms deploys; it still never decides when/how a
-- Terastallization triggers -- same ownership line already drawn for
-- Dynamax Level/Gigantamax Factor.
--
-- Stored as a bare `mon.teraType` field (a type id string, or nil for
-- "unset") -- schema-less save round-tripping, the identical pattern
-- `mon.gigantamaxFactor`/battle_forms's own `mon.battleFormsStone` already
-- rely on (src/mods/SaveSerializer.lua's generic table walk, confirmed
-- this session). Does NOT survive a real link-cable trade (a separate
-- allowlist wire protocol) unless moved under mon.extra -- not needed for
-- the currently scoped use.
--
-- STELLAR is a real, valid value here even though no chart record and no
-- battle_forms menu choice exists for it (src/tera.lua's own TERA_CHOICES
-- lists the 18 standard types only) -- see combat/modern_tera.lua's own
-- header for why Stellar structurally cannot be represented by
-- battle_forms's mechanism at all, and is this mod's own domain instead.
return function(mod)
  local SAVE_FIELD = "teraType"

  -- Every type id the RUNNING game's merged chart can resolve, same
  -- guarded-registry-read pattern battle_forms's own src/tera.lua uses
  -- (typeExists) -- a type chosen here that the loaded chart has never
  -- heard of (DARK/STEEL/FAIRY without National Dex's chart layered in)
  -- would silently do nothing useful downstream, so it is refused here
  -- instead of accepted and failing later.
  local function chartHasType(battle, typeId)
    local chart = battle and battle.data and battle.data.type_chart
    local types = chart and chart.types
    return types ~= nil and types[typeId] ~= nil
  end

  -- STELLAR is accepted unconditionally, chart or no chart -- it is
  -- deliberately absent from every type chart on purpose (no matchup rows
  -- of its own is the whole mechanic, see modern_tera.lua), so "the chart
  -- doesn't know this type" is never a valid refusal reason for it the way
  -- it is for the 18 standard types.
  mod.exports.isValidTeraType = function(typeId, battle)
    if type(typeId) ~= "string" or typeId == "" then return false end
    if typeId == "STELLAR" then return true end
    if not battle then return true end -- no live battle to check against yet; accept, defer the real check to activation time
    return chartHasType(battle, typeId)
  end

  -- battle_forms' own per-mon override field, mirrored so OUR stored value
  -- is the one battle_forms actually deploys (see the file header -- this
  -- is the rewiring, done from our side).  Written unconditionally, the
  -- same way battle_forms mirrors INTO mon.teraType even when no peer is
  -- loaded: a field nothing reads costs nothing when battle_forms is
  -- absent.  Mirrored from BOTH setters and the lazy-roll path, and the
  -- plain-read path too (a mon whose store predates this fix gets its
  -- stamp backfilled on the first read), so the two can never drift.
  local BATTLE_FORMS_STAMP = "battleFormsTeraType"
  local function syncBattleFormsStamp(mon, typeId)
    if not mon or mon[BATTLE_FORMS_STAMP] == typeId then return end
    mon[BATTLE_FORMS_STAMP] = typeId
  end

  -- Same fallback love.math.random/math.random shape the base engine's
  -- own gen2/Battle.lua module-local `rand` helper uses (confirmed this
  -- session) -- a personality-style roll like this has no battle to seed
  -- an RNG from (it can fire from a party/box screen, outside any battle
  -- at all), so it is deliberately NOT battle.random/roller()-seeded the
  -- way an in-battle roll would be.
  local function randomIndex(n)
    if love and love.math and love.math.random then return love.math.random(n) end
    return math.random(n)
  end

  -- The mon's own real types, with or without a live battle to read them
  -- through -- battle.data.pokemon[id] when one is handed in (matches
  -- combat/modern_tera.lua's own originalTypesOf, unaffected by any
  -- battle-only override), else a plain registry read so this also works
  -- from the party screen, a Nuzlocke/box tool, or anywhere else outside
  -- a battle.
  local function speciesTypesOf(mon, battle)
    local id = mon and mon.species
    if not id then return nil end
    if battle and battle.data and battle.data.pokemon and battle.data.pokemon[id] then
      return battle.data.pokemon[id].types
    end
    local registry = mod.content and mod.content.pokemon
    if not registry or type(registry.get) ~= "function" then return nil end
    local ok, rec = pcall(registry.get, registry, id)
    return ok and rec and rec.types or nil
  end

  -- One of the mon's OWN real types, unmodified -- dual-type rolls one of
  -- the two at random (50/50), monotype has only the one answer. Persists
  -- the roll into mon.teraType itself so it reads back identically to an
  -- explicit choice from here on -- there is no separate "default vs
  -- chosen" flag to track, since a later setTeraType call is meant to
  -- freely overwrite either the same way (explicit user spec: "that can
  -- be replaced later by any other").
  local function rollDefaultTeraType(mon, battle)
    local types = speciesTypesOf(mon, battle)
    if not types or #types == 0 then return nil end
    local pick = types[1]
    if #types > 1 then pick = types[randomIndex(#types)] end
    mon[SAVE_FIELD] = pick
    return pick
  end

  -- Read API: mod.exports.getTeraType(mon, battle) -> a type id string,
  -- never nil for a mon with any real species types at all. `battle` is
  -- optional context for resolving those types (see speciesTypesOf above)
  -- -- pass it when calling from inside a live battle, omit it anywhere
  -- else. A mon with no stored value yet -- a brand-new one, OR one that
  -- existed before this file did and so never got one -- is handled
  -- identically, by design, per explicit user instruction: both roll a
  -- random default here, on first read, rather than one path initializing
  -- at creation time and a second, separate migration path backfilling
  -- old saves. One mechanism, not two. Every path -- stored value, lazy
  -- roll, and the backfill below -- keeps mon.battleFormsTeraType in
  -- sync so battle_forms deploys exactly this stored type (see the file
  -- header). A mon carrying ONLY battle_forms' own stamp (a Tera Orb shop
  -- purchase made before this mod ever stored a type for it) is adopted
  -- into our storage rather than clobbered with a random roll -- the
  -- player's purchase wins.
  mod.exports.getTeraType = function(mon, battle)
    if not mon then return nil end
    local t = mon[SAVE_FIELD]
    if type(t) == "string" and t ~= "" then
      syncBattleFormsStamp(mon, t)
      return t
    end
    local stamped = mon[BATTLE_FORMS_STAMP]
    if type(stamped) == "string" and stamped ~= "" and mod.exports.isValidTeraType(stamped, battle) then
      mon[SAVE_FIELD] = stamped
      syncBattleFormsStamp(mon, stamped)
      return stamped
    end
    local rolled = rollDefaultTeraType(mon, battle)
    if rolled then syncBattleFormsStamp(mon, rolled) end
    return rolled
  end

  -- Write API: mod.exports.setTeraType(mon, typeId, battle) -> the value
  -- actually stored, or false if refused (invalid mon, invalid/unresolved
  -- type). `battle` is optional context for the chart-membership check
  -- above -- pass the live battle when calling this from inside one, omit
  -- it (e.g. from a party-screen picker outside battle) to accept any of
  -- the 18 known ids plus STELLAR without a live chart to check against.
  -- Any other mod may call this directly, same as Dynamax
  -- Level/Gigantamax Factor -- we don't decide when/why a Tera Type gets
  -- chosen or changed, only persist what we're told. Clearing (nil)
  -- clears BOTH our stored field and the mirrored battle_forms stamp;
  -- setting a valid type writes BOTH, so battle_forms' next activation
  -- deploys exactly what was set here (see the file header).
  mod.exports.setTeraType = function(mon, typeId, battle)
    if not mon then return false end
    if typeId == nil then
      mon[SAVE_FIELD] = nil
      syncBattleFormsStamp(mon, nil)
      return nil
    end
    if not mod.exports.isValidTeraType(typeId, battle) then return false end
    mon[SAVE_FIELD] = typeId
    syncBattleFormsStamp(mon, typeId)
    return typeId
  end

  -- OWNERSHIP GATE (round 9, 2026-09-06). Explicit user instruction: "battle
  -- forms should only keep that dev power when enabled, battle forms
  -- shouldn't have any control over tera system, we only rely on it to read
  -- when tera is triggered, everything else of tera is to be owned by
  -- g9-battle-engine." battle_forms' own TERA TYPE manager option is its
  -- dev/test tool -- src/tera.lua reads it live at every activation via its
  -- deps.chosen() = mod.options:get("tera_type") and, when it is a concrete
  -- type, it overrides every Pokemon regardless of our stamp. This wraps that
  -- read on the battle_forms mod object itself (mod.find -- the same seam its
  -- documented per-mon stamp is) so that battle_forms' tera_type read is
  -- ALWAYS forced to "auto": its dev choice can never override, and the stamp
  -- mirror above is the only thing battle_forms can see -- our stored type is
  -- the type it deploys. It only reports WHEN Terastallization triggers
  -- (mod.battle_forms.tera_applied) and mechanically writes the type we
  -- already decided. (Round 104, 2026-09-10: the bf_tera_dev option that used
  -- to re-open battle_forms' dev tool while ON was removed -- the gate is now
  -- unconditional.) The wrap is idempotent and pcall-guarded end to end: battle_forms
  -- is an optional dependency that may boot before OR after us, so this is
  -- also re-ensured by modern_tera on every battle.started and on the
  -- tera_applied event (by which point battle_forms is certainly loaded); an
  -- options API whose shape we don't recognise is left alone -- the stamp
  -- mirror alone still makes our type win in the AUTO case -- and the
  -- failure is logged, never fatal.
  local BF_GATE_MARK = "__g9BattleFormsTeraOwned"
  mod.exports.ensureBattleFormsGate = function()
    local ok, bfMod = pcall(function() return mod.find and mod.find("battle_forms") end)
    if not ok or type(bfMod) ~= "table" then return false end
    local options = bfMod.options
    if type(options) ~= "table" or type(options.get) ~= "function" then
      mod.log:warn("galar_gmax_dex: tera_state: battle_forms present but its options.get is not a patchable field; TERA TYPE dev override stays as battle_forms set it")
      return false
    end
    if options[BF_GATE_MARK] then return true end
    options[BF_GATE_MARK] = true
    local origGet = options.get
    options.get = function(self, key, ...)
      if key == "tera_type" then return "auto" end
      return origGet(self, key, ...)
    end
    mod.log:info("galar_gmax_dex: tera_state: battle_forms TERA TYPE option forced to AUTO (unconditional) -- battle_forms only reports WHEN tera triggers")
    return true
  end
  mod.exports.ensureBattleFormsGate()

  mod.log:info("galar_gmax_dex: tera_state installed (per-mon Tera Type storage + API, no activation)")
end
