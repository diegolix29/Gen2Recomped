-- =============================================================================
-- Custom trainer roster registration API
--   mod.exports.registerTrainer(trainerId, party, options)
-- =============================================================================
--
-- WHAT THIS IS
-- A public API any other mod can call to fully replace a real trainer's
-- team -- species/level/gender/moves, the modern per-mon data this ROM
-- never had a concept of at all (ability, nature, IVs, EVs, Tera Type,
-- Dynamax Level, Gigantamax Factor, held item), and the trainer's battle
-- combat mode. A caller mod does not need to know anything about this
-- engine's internals.
--
-- THE THREE THINGS A CALLER MOD TELLS THIS ENGINE
--
--   1. TO THE BASE ENGINE (g1r itself), per Pokemon: species, level,
--      gender and moves. Delivered by integration point 1 below
--      (the Trainers.party monkeypatch): each party entry becomes a real
--      Mon object through the same Mon.new every wild/gift/trade mon in
--      the game goes through, and mon.gender is stamped explicitly
--      because base Mon.new has no gender option of its own (it otherwise
--      derives gender from DVs, which a trainer mon never rolls).
--
--   2. TO THE G9 BATTLE ENGINE BETA, those SAME fields PLUS the modern
--      per-mon stats: ability, nature, IVs, EVs, Tera Type, Dynamax Level
--      and Gigantamax Factor. Delivered by integration points 2 and 3
--      below (the trainer-stats provider + the battle.started
--      application). These are what make a registered roster fight with
--      modern stats instead of the base engine's DV/stat-exp conversion.
--      Every modern field is OPTIONAL: an entry that omits them just gets
--      this engine's normal per-mon generation for that field.
--
--   3. THE TRAINER'S COMBAT MODE: "native" (also accepted: "primitive",
--      "vanilla", "single", "singles", or the number 1), "doubles"
--      (2), "triples" (3), or "bossFight" (also accepted: "bossfight",
--      "boss_fight", "boss-fight", "boss"). Delivered by integration
--      point 4 below. "native" is the ordinary, unmodified base-engine
--      trainer battle. "doubles"/"triples"/"bossFight" route the battle
--      through the separate g9-Battle-Scene mod's same-named layout
--      presets when it is installed, falling straight through to the
--      ordinary battle when it is not. The SAME `options` table also
--      carries an optional `maxHpMultiplier` (1x-5x, default 1x = no
--      change): a boss fight can hand a registered boss a bigger health
--      pool, applied to every Pokemon on THAT one trainer's roster and
--      nobody else's. See integration point 3b below.
--
--      The SAME `options` table also carries `bossFight` -- the boss-fight
--      PROTECTIONS owned by combat/boss_fight.lua. It is a table of
--      { flag = true, ... } naming the protections this trainer's enemy
--      side should get (e.g. { hardStatus = true, statsDrop = true }); an
--      array of flag-name strings works too. The recognized names are
--      combat/boss_fight.lua's own exported BOSS_FIGHT_FLAG_NAMES: sun,
--      mistyTerrain, statsDrop, type, ability, hardStatus, softStatus,
--      antiDrain, dimensionLock, trickRoom, magicRoom, wonderRoom,
--      healblock. The set is applied at battle start (integration point 3c
--      below), scoped to that one registered trainer's battle. Optional and
--      freely combinable with maxHpMultiplier; meant for bossFight-style
--      encounters but not gated on combatType, because the flags are the
--      caller's own inclusion list. See the g9-trainer-sample mod's own
--      README.md for the flag-by-flag table.
--
-- Gen 2 (Gold/Silver/Crystal) ONLY, matching this mod's own established
-- scope everywhere else (Battle2/gen2/Battle.lua throughout) -- Gen 1's
-- own separate trainer pipeline (src/battle/BattleState.lua's newTrainer)
-- is a different real function this file does not touch; Tera/Dynamax/
-- Gigantamax are Gen2-exclusive concepts in this project regardless.
--
-- TRAINER IDENTITY: "CLASS:MEMBERID" (e.g. "YOUNGSTER:JOEY1"), matching
-- this ROM's own real trainer identity directly -- confirmed by reading
-- the actual engine source: src/world/gen2/Trainers.lua's own
-- Trainers.lookup(trainerData, class, member) returns { class=, classId=,
-- member=, id=, name=, roster=, ... }, and src/world/gen2/World.lua's own
-- startScriptedBattle (the ONE real place every scripted trainer battle
-- in the game gets built, confirmed by that function's own comment) then
-- carries it forward as opts.trainer = { classId = record.classId,
-- memberId = record.id, ... } -- the exact same classId/memberId pair
-- this file keys its own registry on, and the exact pair
-- stats/gen2_modern_stats.lua's own generateGen2TrainerMon already reads
-- into its ctx.oppClass/ctx.partyIndex for the (pre-existing, already-
-- shipped) provider system. CLASS is the trainer CLASS id (e.g.
-- "BEAUTY", "FALKNER", "YOUNGSTER"); MEMBERID is that one named trainer's
-- own real id within the class (e.g. "VICTORIA") -- confirmed real and
-- populated on every trainer in a live ROM extraction (tests fixture + a
-- real Crystal cache both checked when this was first written), NOT a
-- guessed convention.
--
-- FULL EXAMPLE
--   mod.find("g9-battle-engine").exports.registerTrainer(
--     "YOUNGSTER:JOEY1", {
--       { species = "EXCADRILL", level = 14, gender = "female",
--         moves = { "EARTHQUAKE", "ROCKSLIDE", "PROTECT" },
--         ability = "MOLDBREAKER", nature = "JOLLY",
--         ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
--         evs = { hp = 0, atk = 252, def = 0, spa = 0, spd = 4, spe = 252 },
--         teraType = "GROUND", dynamaxLvl = 10, gigantamax = false,
--         heldItem = "CHOICE_BAND" },
--       -- up to 5 more entries
--     }, { combatType = "native", maxHpMultiplier = 1 })
--
--   -- A boss example, with protections and extra health:
--   mod.find("g9-battle-engine").exports.registerTrainer(
--     "FALKNER:FALKNER1", { { species = "PIDGEOT", level = 36 } },
--     { combatType = "bossFight", maxHpMultiplier = 3,
--       bossFight = { hardStatus = true, softStatus = true,
--                     statsDrop = true, antiDrain = true } })
--
-- See the g9-trainer-sample mod for a complete, working caller mod.
--
-- FOUR REAL INTEGRATION POINTS, one per concern, each reusing an existing
-- real primitive rather than inventing a new one:
--   1. Species/level/gender/moves/held item -- monkeypatches the real
--      native `Trainers.party(data, entry)` (src/world/gen2/Trainers.lua),
--      the ONE real function that turns a trainer's roster rows into
--      actual battle Mon objects. A registered trainer's roster REPLACES
--      `entry.roster` entirely for that one lookup; every other trainer in
--      the game falls straight through to the real, unmodified behavior.
--   2. Ability/nature/IVs/EVs/gender -- registers on the EXISTING,
--      already-shipped `mod.exports.registerTrainerStatsProvider` chain
--      (stats/trainer_modern_stats.lua) at high priority, so an explicit
--      trainer registration always wins over any other installed provider
--      for the same mon. Reuses ModernStats.applySpec's own real spec
--      shape (stats/engine_modern_stats.lua) -- not a second, parallel
--      stat-writing path.
--   3. Tera Type / Dynamax Level / Gigantamax Factor -- a battle.started
--      listener (Gen2-gated) calling the real, already-shipped per-mon
--      setters (gigantamax/tera_state.lua's setTeraType, gigantamax/
--      dynamax_state.lua's setGigantamaxFactor) directly on each
--      constructed party mon. Dynamax Level itself is the one field this
--      project had NO per-mon storage for before this file -- see
--      gigantamax/dynamax_state.lua's own header for why (Dynamax Level
--      there is deliberately PER-SAVE, the player's own real account-wide
--      progression, a genuinely different real concept from "what level
--      should THIS specific opposing trainer's Pokemon Dynamax at" -- the
--      same distinction Bulbapedia's own Sword/Shield mechanics draw) --
--      stored here as a plain mon.dynamaxLevel field, the same bare-field
--      pattern mon.gigantamaxFactor already established successfully.
--   4. Combat type (native/doubles/triples/bossFight) -- a World:
--      startBattle wrap routing a registered trainer's doubles/triples/
--      bossFight battle through the SEPARATE, optional mods/g9-Battle-
--      Scene mod's own named layout preset system (mod.exports
--      .pushLayoutBattle). g9-Battle-Scene is resolved live via
--      mod.find, never a hard dependency -- "native" (the default) and a
--      missing/absent g9-Battle-Scene both fall straight through to the
--      ordinary native trainer battle. bossFight maps to that mod's own
--      layouts/bossFight.lua preset (its README calls it a "4v1 boss
--      fight"); like doubles/triples this file only routes -- it never
--      decides the roster, so the caller registers exactly the boss
--      (typically a single ace).
return function(mod)
  local gen2Ok_Trainers, Trainers = pcall(require, "src.world.gen2.Trainers")
  if not gen2Ok_Trainers then
    mod.log:info("g9-battle-engine: custom_trainer_registry requires Gen 2; skipped on this Gen 1 game")
    -- src.world.gen2.Trainers does not exist on a Gen 1 game, so there is no
    -- gen2 trainer registry to install. Publish inert stubs anyway so caller
    -- mods that call these exports unconditionally keep working on Gen 1
    -- instead of hitting a nil-export error mid-battle.
    mod.exports.registerTrainer = function() return false end
    mod.exports.unregisterTrainer = function() return false end
    mod.exports.getRegisteredTrainer = function() return nil end
    mod.exports.hasRegisteredTrainer = function() return false end
    mod.exports.setTrainerMaxHpMultiplier = function() return false end
    return
  end
  -- Re-install guard, same real pattern stats/gen2_modern_stats.lua's own
  -- Gen2Battle.__galarGen2ModernStatsWrapped already established in this
  -- codebase -- flag lives on the real, shared, require-cached Trainers
  -- table itself (confirmed real and single-instance: src/mods/Sandbox
  -- .lua's own sandboxedRequire delegates straight to the real global
  -- require, so every mod's require("src.world.gen2.Trainers") returns
  -- the SAME table, not a per-mod copy), not on a local -- a local
  -- inside this closure would be worthless as a re-run guard since a
  -- second run gets its own fresh one. Without this, a second install
  -- (a mod-reload/re-init, if this loader ever does one) would silently
  -- build a SECOND, empty `registry` closure and repoint mod.exports
  -- .registerTrainer at it -- any earlier registerTrainer call (a
  -- caller mod whose own main.lua only ran once) would then be writing
  -- into an orphaned registry nothing still reads from, while every
  -- live battle.started/Trainers.party/World:startBattle check reads
  -- the new, empty one.
  if Trainers.__g9CustomTrainerRegistryInstalled then
    mod.log:warn("g9-battle-engine: custom_trainer_registry: install "
      .. "attempted a second time, refused -- mod.exports.registerTrainer "
      .. "still points at the FIRST install's own registry, unchanged")
    return
  end
  Trainers.__g9CustomTrainerRegistryInstalled = true
  local Mon = require("src.battle.gen2.Mon")
  local ModernStats = mod.exports.ModernStats
  local setTeraType = mod.exports.setTeraType
  local setGigantamaxFactor = mod.exports.setGigantamaxFactor
  local setMonDynamaxLevel = mod.exports.setMonDynamaxLevel
  local registerTrainerStatsProvider = mod.exports.registerTrainerStatsProvider
  local isGen2Battle = mod.exports.isGen2Battle
  local setBossFightFlagTable = mod.exports.setBossFightFlagTable
  local bossFightFlagIsKnown = mod.exports.bossFightFlagIsKnown
  assert(ModernStats and setTeraType and setGigantamaxFactor and setMonDynamaxLevel
      and registerTrainerStatsProvider and isGen2Battle
      and setBossFightFlagTable and bossFightFlagIsKnown,
    "custom_trainer_registry: stats/engine_modern_stats.lua, stats/trainer_modern_stats.lua, "
      .. "gigantamax/tera_state.lua, gigantamax/dynamax_state.lua, combat/modern_combat.lua and "
      .. "combat/boss_fight.lua must all load first")

  -- [ "CLASS:MEMBERID" ] = { party = <array of up to 6 entries>,
  --                          combatType = "native" | "doubles" | "triples" | "bossFight" }
  local registry = {}

  -- One canonical spelling each, so a caller can write whatever reads
  -- naturally ("primitive", "vanilla", "single", 1, "boss", ...) and
  -- every downstream check only ever sees "native"/"doubles"/"triples"/
  -- "bossFight". bossFight's canonical spelling deliberately matches
  -- g9-Battle-Scene's own layouts/bossFight.lua preset file name
  -- exactly, because that canonical value is the layout name this file
  -- hands to getLayoutData/pushLayoutBattle in integration point 4.
  local COMBAT_TYPE_ALIASES = {
    native = "native", primitive = "native", vanilla = "native",
    single = "native", singles = "native", [1] = "native",
    doubles = "doubles", double = "doubles", [2] = "doubles",
    triples = "triples", triple = "triples", [3] = "triples",
    bossfight = "bossFight", boss_fight = "bossFight",
    ["boss-fight"] = "bossFight", boss = "bossFight",
  }
  local function normalizeCombatType(combatType)
    if combatType == nil then return nil end
    if type(combatType) == "string" then
      return COMBAT_TYPE_ALIASES[combatType:lower()]
    end
    return COMBAT_TYPE_ALIASES[combatType]
  end

  -- Max HP multiplier -- the "boss has more health" control. A caller sets
  -- it on the SAME `options` table as combatType (registerTrainer's third
  -- argument), and it scales the max HP of every Pokemon on that ONE
  -- trainer's roster by 1x..5x (1x = untouched, the default). Intended for
  -- bossFIGHT-style opponents (a 4v1 ace, a raid wall), but deliberately
  -- enforced PER REGISTERED TRAINER rather than gated on combatType: a
  -- caller that wants a tanky normal trainer can have one, and a caller
  -- that only wants it on its boss simply sets it only on that boss.
  -- Out-of-range values are CLAMPED, not rejected, matching this file's
  -- own forgiving-input convention (combatType/gender normalise rather
  -- than throw); a non-number is refused and falls back to 1x.
  local MAX_HP_MULTIPLIER_MIN, MAX_HP_MULTIPLIER_MAX = 1, 5
  local function normalizeMaxHpMultiplier(value)
    if value == nil then return 1 end
    local n = tonumber(value)
    if n == nil then return nil end
    if n < MAX_HP_MULTIPLIER_MIN then n = MAX_HP_MULTIPLIER_MIN end
    if n > MAX_HP_MULTIPLIER_MAX then n = MAX_HP_MULTIPLIER_MAX end
    return n
  end

  -- Reads whichever spelling of the option a caller used (an options table
  -- is free-form, so the usual aliases all work); returns nil when the
  -- caller set none of them, so registerTrainer can tell "not given" from
  -- "given as 1".
  local function rawMaxHpMultiplier(options)
    if type(options) ~= "table" then return nil end
    local raw = options.maxHpMultiplier
    if raw == nil then raw = options.hpMultiplier end
    if raw == nil then raw = options.maxHp end
    if raw == nil then raw = options.maxhp end
    return raw
  end

  -- Boss-fight protections (combat/boss_fight.lua). `options.bossFight` is
  -- the primary spelling; the table-taking setBossFightFlagTable export is
  -- the reason this file can build a set-table and hand it over without
  -- depending on unpack/table.unpack across Lua versions. A caller may
  -- write either a { name = true } dict, an array of name strings, or one
  -- bare name string. Unknown names are dropped with a warning (this file's
  -- own forgiving-input convention) rather than refusing the registration.
  local function rawBossFightFlags(options)
    if type(options) ~= "table" then return nil end
    local raw = options.bossFight
    if raw == nil then raw = options.bossFightFlags end
    if raw == nil then raw = options.bossFightProtections end
    if raw == nil then raw = options.bossProtections end
    if raw == nil then raw = options.protections end
    return raw
  end

  -- Returns set, unknownList. `set` is nil when nothing usable was given.
  local function normalizeBossFightFlags(raw)
    if raw == nil then return nil, nil end
    local set, unknown = {}, {}
    local function add(name)
      if type(name) ~= "string" then return end
      if bossFightFlagIsKnown(name) then set[name] = true
      else unknown[#unknown + 1] = name end
    end
    if type(raw) == "table" then
      for k, v in pairs(raw) do
        if type(k) == "number" then add(v)     -- array of flag-name strings
        elseif v then add(k) end               -- { flag = true } dict
      end
    elseif type(raw) == "string" then
      add(raw)
    else
      return nil, { tostring(raw) }
    end
    return set, unknown
  end

  -- mon.gender's real native values are "male"/"female"/"unknown"
  -- (src/battle/gen2/Mon.lua's own Mon.gender, and what Mon.gender's own
  -- GENDERS guard accepts from a gender.roll hook). A caller can write
  -- either the full word or the usual one-letter shorthand.
  local GENDER_ALIASES = {
    male = "male", m = "male", boy = "male", [1] = "male",
    female = "female", f = "female", girl = "female", [2] = "female",
    genderless = "unknown", unknown = "unknown", none = "unknown",
    genderless_ = "unknown", [0] = "unknown",
  }
  local function normalizeGender(gender)
    if gender == nil then return nil end
    if type(gender) == "string" then return GENDER_ALIASES[gender:lower()] end
    return GENDER_ALIASES[gender]
  end

  local function keyFor(classId, memberId)
    if classId == nil or memberId == nil then return nil end
    return tostring(classId) .. ":" .. tostring(memberId)
  end

  -- Real nature-id case normalization: this project's own convention
  -- writes ability/type/item ids ALL-CAPS everywhere (WONDERGUARD,
  -- GROUND, CHOICE_SCARF, ...), but ModernStats.NATURES (stats/
  -- engine_modern_stats.lua) is the one place natures are still spelled
  -- Capitalized ("Jolly", "Adamant") -- the exact strings its own
  -- computeAll/natureMult key off. Built once so a trainer definition
  -- can write NATURE in whichever case reads naturally without silently
  -- mismatching that table.
  local NATURE_BY_UPPER = {}
  for _, n in ipairs(ModernStats.NATURES) do NATURE_BY_UPPER[n:upper()] = n end
  local function normalizeNature(nature)
    if type(nature) ~= "string" then return nil end
    return NATURE_BY_UPPER[nature:upper()]
  end

  local STAT_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

  -- Builds ModernStats.applySpec's own real spec shape from one party
  -- entry's gender/ivs/evs/ability/nature fields. Unset IVs default to 31
  -- (a fully-realized modern Pokemon's own common default), unset EVs to
  -- 0 -- confirmed necessary: ModernStats.applySpec's own real per-stat
  -- loop reads `part.iv`/`part.ev` off whatever sub-table IS given and
  -- falls back to a bare 0 for anything missing, so a caller that only
  -- half-fills `ivs` would otherwise silently zero the rest. Real EV
  -- cap (510 total, 252 per stat) enforced here too, scaled down
  -- proportionally rather than truncating whichever stat happens to be
  -- listed last in a definition that goes over.
  local function specFromEntry(entry)
    local spec = {
      gender = normalizeGender(entry.gender),
      ability = entry.ability,
      nature = normalizeNature(entry.nature),
    }
    local ivs, evs = entry.ivs or {}, entry.evs or {}
    for _, key in ipairs(STAT_KEYS) do
      local iv = tonumber(ivs[key])
      if iv == nil then iv = 31 end
      iv = math.max(0, math.min(31, math.floor(iv)))
      local ev = math.max(0, math.min(252, math.floor(tonumber(evs[key]) or 0)))
      spec[key] = { iv = iv, ev = ev }
    end
    local total = 0
    for _, key in ipairs(STAT_KEYS) do total = total + spec[key].ev end
    if total > 510 then
      local scale = 510 / total
      for _, key in ipairs(STAT_KEYS) do
        spec[key].ev = math.floor(spec[key].ev * scale)
      end
    end
    return spec
  end

  ------------------------------------------------------------------
  -- Public API.
  --
  --   mod.find("g9-battle-engine").exports.registerTrainer(
  --     "YOUNGSTER:JOEY1", {
  --       { species = "EXCADRILL", level = 14, gender = "female",
  --         moves = { "EARTHQUAKE", "ROCKSLIDE", "PROTECT" },
  --         ability = "MOLDBREAKER", nature = "JOLLY",
  --         ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
  --         evs = { hp = 0, atk = 252, def = 0, spa = 0, spd = 4, spe = 252 },
  --         teraType = "GROUND", dynamaxLvl = 10, gigantamax = false,
  --         heldItem = "CHOICE_BAND" },
  --     }, { combatType = "native", maxHpMultiplier = 1 })
  --
  -- Only species/level are required per entry; every other field is
  -- optional and defaults the same way a vanilla trainer row does, EXCEPT
  -- where a field is modern-only:
  --   species    (required)  real species id, e.g. "EXCADRILL"
  --   level      (required)  number
  --   gender     optional    "male"/"female"/"unknown" (or m/f/1/2/...)
  --                          -- base-engine gender, stamped onto the mon
  --   moves      optional    array of real move ids; omitted -> whatever
  --                          the species knows at that level
  --   nickname   optional    display nickname string
  --   heldItem   optional    real registered item id, e.g. "CHOICE_BAND"
  --                          (WITH the underscore and WITH quotes)
  --   ability    optional    ability id; omitted -> generated
  --   nature     optional    "JOLLY"/"Jolly"/... (case-insensitive)
  --   ivs/evs    optional    { hp=, atk=, def=, spa=, spd=, spe= }; IVs
  --                          default to 31 and EVs to 0 per stat
  --   teraType   optional    real type id, e.g. "GROUND"
  --   dynamaxLvl optional    number
  --   gigantamax optional    boolean
  --
  -- `options` is optional:
  --   combatType        "native" (default -- the ordinary native single
  --                     battle, g9-Battle-Scene never invoked at all),
  --                     "doubles", "triples", or "bossFight". See
  --                     integration point 4 below.
  --   maxHpMultiplier   1-5 (default 1). Multiplies the max HP of every
  --                     Pokemon on THIS trainer's roster -- the boss-fight
  --                     health control. Out-of-range values are clamped;
  --                     a non-number is refused and falls back to 1.
  --                     Alias spellings accepted: hpMultiplier, maxHp,
  --                     maxhp. See integration point 3b below.
  --   bossFight         a table of { flag = true, ... } (or an array of
  --                     flag-name strings) naming the boss-fight
  --                     protections combat/boss_fight.lua should apply to
  --                     this trainer's enemy side at battle start. Known
  --                     flag names are combat/boss_fight.lua's own
  --                     exported BOSS_FIGHT_FLAG_NAMES: sun, mistyTerrain,
  --                     statsDrop, type, ability, hardStatus, softStatus,
  --                     antiDrain, dimensionLock, trickRoom, magicRoom,
  --                     wonderRoom, healblock. Unknown names are dropped
  --                     with a warning. Alias key spellings accepted:
  --                     bossFightFlags, bossFightProtections,
  --                     bossProtections, protections. See integration
  --                     point 3c below.
  --
  -- A registered trainer's multiplier can also be changed at runtime
  -- without re-registering the roster, via
  -- mod.exports.setTrainerMaxHpMultiplier(trainerId, multiplier) -- see
  -- the public API section further down.
  ------------------------------------------------------------------
  mod.exports.registerTrainer = function(trainerId, party, options)
    if type(trainerId) ~= "string" or trainerId == "" then
      mod.log:warn("g9-battle-engine: registerTrainer: trainerId must be a non-empty string")
      return false
    end
    if type(party) ~= "table" or #party == 0 then
      mod.log:warn("g9-battle-engine: registerTrainer(%s): party must be a non-empty array",
        trainerId)
      return false
    end
    for i, row in ipairs(party) do
      if i <= 6 and (type(row) ~= "table" or type(row.species) ~= "string" or not row.level) then
        mod.log:warn("g9-battle-engine: registerTrainer(%s): slot %d needs at least "
          .. "species (string) and level", trainerId, i)
        return false
      end
      if i <= 6 and row.gender ~= nil and normalizeGender(row.gender) == nil then
        mod.log:warn("g9-battle-engine: registerTrainer(%s): slot %d gender %q is not "
          .. "\"male\"/\"female\"/\"unknown\"", trainerId, i, tostring(row.gender))
        return false
      end
    end
    if #party > 6 then
      mod.log:warn("g9-battle-engine: registerTrainer(%s): party has %d entries, only "
        .. "the first 6 are used", trainerId, #party)
    end
    local rawCombatType = options and options.combatType
    local combatType = normalizeCombatType(rawCombatType)
    if rawCombatType ~= nil and combatType == nil then
      mod.log:warn("g9-battle-engine: registerTrainer(%s): combatType %q is not "
        .. "\"native\"/\"primitive\"/\"doubles\"/\"triples\"/\"bossFight\", defaulting to \"native\"",
        trainerId, tostring(rawCombatType))
    end
    local rawMaxHp = rawMaxHpMultiplier(options)
    local maxHpMultiplier = normalizeMaxHpMultiplier(rawMaxHp)
    if rawMaxHp ~= nil and maxHpMultiplier == nil then
      mod.log:warn("g9-battle-engine: registerTrainer(%s): maxHpMultiplier %q is not a "
        .. "number, defaulting to 1", trainerId, tostring(rawMaxHp))
      maxHpMultiplier = 1
    elseif rawMaxHp ~= nil and maxHpMultiplier ~= tonumber(rawMaxHp) then
      mod.log:warn("g9-battle-engine: registerTrainer(%s): maxHpMultiplier %s is outside "
        .. "1-5, clamped to %s", trainerId, tostring(rawMaxHp), tostring(maxHpMultiplier))
    end
    local rawBossFight = rawBossFightFlags(options)
    local bossFightFlags, unknownBossFight = normalizeBossFightFlags(rawBossFight)
    if rawBossFight ~= nil and bossFightFlags == nil then
      mod.log:warn("g9-battle-engine: registerTrainer(%s): bossFight must be a table "
        .. "of flag names (or an array of them), ignoring", trainerId)
    elseif unknownBossFight and #unknownBossFight > 0 then
      mod.log:warn("g9-battle-engine: registerTrainer(%s): ignoring unknown bossFight "
        .. "flag(s): %s", trainerId, table.concat(unknownBossFight, ", "))
    end
    registry[trainerId] = { party = party, combatType = combatType or "native",
      maxHpMultiplier = maxHpMultiplier or 1, bossFightFlags = bossFightFlags }
    return true
  end

  -- Removes a registration, so a caller can add/remove trainers at runtime
  -- (e.g. turning its own feature off). Returns true when something was
  -- actually removed. After this, the trainer reverts to its vanilla roster.
  mod.exports.unregisterTrainer = function(trainerId)
    if type(trainerId) ~= "string" or registry[trainerId] == nil then return false end
    registry[trainerId] = nil
    return true
  end

  -- Read-only introspection: a copy of one registration, or nil. Handy for
  -- a caller checking its own state, or a debugging mod.
  mod.exports.getRegisteredTrainer = function(trainerId)
    local record = registry[trainerId]
    if not record then return nil end
    return { trainerId = trainerId, party = record.party, combatType = record.combatType,
      maxHpMultiplier = record.maxHpMultiplier, bossFightFlags = record.bossFightFlags }
  end

  -- Runtime max-HP control: change an already-registered trainer's
  -- multiplier without re-registering the whole roster. Returns the
  -- clamped value actually stored (1-5), or false when trainerId has no
  -- registration or `multiplier` is not a number. Useful for a caller
  -- that powers a boss up (or restores it) between battles -- the new
  -- value is read fresh on the next battle.started, so it applies to the
  -- next fight, not one already in progress.
  mod.exports.setTrainerMaxHpMultiplier = function(trainerId, multiplier)
    if type(trainerId) ~= "string" or registry[trainerId] == nil then return false end
    if multiplier == nil then return false end
    local normalized = normalizeMaxHpMultiplier(multiplier)
    if normalized == nil then return false end
    registry[trainerId].maxHpMultiplier = normalized
    return normalized
  end

  -- Lets another mod that ALSO makes its own blanket combat-type
  -- decisions (Sample-Battle-Scene-G9's own tryDoublesTrainer, which
  -- forces doubles on ANY trainer with 2+ Pokemon regardless of this
  -- registry -- confirmed a real conflict, 2026-08-28: it installs its
  -- own World:startBattle wrap AFTER this file's own (it loads later in
  -- the dependency chain, g9-battle-engine -> g9-Battle-Scene ->
  -- Sample-Battle-Scene-G9), so it runs FIRST and can return before this
  -- file's own combatType check ever gets a turn) defer to a REGISTERED
  -- trainer's own explicit choice instead of guessing from party size.
  mod.exports.hasRegisteredTrainer = function(classId, memberId)
    local key = keyFor(classId, memberId)
    return key ~= nil and registry[key] ~= nil
  end

  ------------------------------------------------------------------
  -- 1. Species/level/gender/moves/held item -- Trainers.party monkeypatch.
  ------------------------------------------------------------------
  local nativeParty = Trainers.party
  function Trainers.party(data, entry)
    local key = entry and keyFor(entry.classId, entry.id or entry.name)
    local record = key and registry[key]
    local custom = record and record.party
    if not custom then return nativeParty(data, entry) end
    local party = {}
    for i = 1, math.min(6, #custom) do
      local row = custom[i]
      local ok, result = pcall(function()
        local moves = nil
        if row.moves and #row.moves > 0 then
          moves = {}
          for _, id in ipairs(row.moves) do
            local moveDef = data and data.moves and data.moves[id]
            moves[#moves + 1] = { id = id, pp = moveDef and moveDef.pp or 0,
              maxPp = moveDef and moveDef.pp or 0 }
          end
        end
        -- Real, confirmed trainer-mon DV rule (Trainers.lua's own
        -- comment: "Trainer mons roll no DVs: the cart gives every one
        -- of them 9/8/8/8/8") -- kept exactly as the vanilla path
        -- already does, since a registered trainer is still a REAL
        -- in-game trainer, not a wild encounter. A caller-supplied
        -- gender is stamped after construction because base Mon.new has
        -- no gender option of its own (it derives gender from these DVs).
        local mon = Mon.new(data, row.species, row.level, {
          moves = moves, item = row.heldItem, nickname = row.nickname,
          dvs = { attack = 9, defense = 8, speed = 8, special = 8 },
        })
        if mon then
          local gender = normalizeGender(row.gender)
          if gender then mon.gender = gender end
        end
        return mon
      end)
      if ok and result then
        party[#party + 1] = result
      else
        mod.log:warn("g9-battle-engine: registerTrainer(%s): slot %d (%s) failed to "
          .. "build, skipped: %s", key, i, tostring(row and row.species), tostring(result))
      end
    end
    return party
  end

  ------------------------------------------------------------------
  -- 2. Ability/nature/IVs/EVs/gender -- registerTrainerStatsProvider entry.
  -- Priority 100: an explicit trainer registration should always win
  -- over any other installed provider for the same mon (there are none
  -- as of this file's own writing, but the contract should hold for
  -- whatever gets added later too).
  ------------------------------------------------------------------
  registerTrainerStatsProvider(function(ctx)
    local key = keyFor(ctx.oppClass, ctx.partyIndex)
    local record = key and registry[key]
    local row = record and record.party and record.party[ctx.slotIndex]
    if not row then return nil end
    return specFromEntry(row)
  end, 100)

  ------------------------------------------------------------------
  -- 3. Tera Type / Dynamax Level / Gigantamax Factor -- applied once the
  -- real party mon objects exist (battle.started, same real event/
  -- timing stats/gen2_modern_stats.lua's own listener already uses --
  -- registered independently here since none of these three fields
  -- depend on ability/nature/IV/EV generation having run first).
  ------------------------------------------------------------------
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if ev.kind ~= "trainer" or not (battle and isGen2Battle(battle)) then return end
    local trainer = ev.trainer
    local key = trainer and keyFor(trainer.classId or trainer.class, trainer.memberId or trainer.id)
    local record = key and registry[key]
    local custom = record and record.party
    if not custom then return end
    for slotIndex, mon in ipairs(battle.enemyParty or {}) do
      local row = custom[slotIndex]
      if row and type(mon) == "table" then
        if row.teraType then setTeraType(mon, row.teraType, battle) end
        if row.gigantamax ~= nil then setGigantamaxFactor(mon, row.gigantamax) end
        if row.dynamaxLvl ~= nil then setMonDynamaxLevel(mon, row.dynamaxLvl) end
      end
    end
  end)

  ------------------------------------------------------------------
  -- 3b. Max HP multiplier -- applied to a registered trainer's Pokemon
  --     once their FINAL stats exist.
  --
  --     Priority -1000, deliberately: the event bus dispatches
  --     highest-priority-first, and the listener that actually computes
  --     each trainer mon's final mon.stats/mon.hp/mon.maxHp from its
  --     modern IVs/EVs/nature is stats/gen2_modern_stats.lua's OWN
  --     battle.started handler, registered at the default 0 (as are every
  --     other non-explicit listener; only main.lua's TypeChart bootstrap
  --     asks for 1000). Running at the default priority would race that
  --     computation -- equal priorities are not an ordering guarantee --
  --     and an unlucky order would scale a maxHp that modern stats then
  --     overwrote, silently. -1000 puts this after every default handler,
  --     so it is the final word on the boss's HP.
  --
  --     Scoped exactly like the other integration points: the multiplier
  --     lives on the registry record and only battle.enemyParty (the
  --     registered trainer's own side) is touched, so no other battle and
  --     no other trainer is ever affected.
  ------------------------------------------------------------------
  -- Scales one mon's max HP in place. mon.maxHp is the real max every HP
  -- read (heals, HP-ratio effects, the HUD) eventually compares against,
  -- but mon.stats.hp is kept in lockstep too, since Gen 2's native
  -- primitive functions read the stats table directly. Current HP is
  -- scaled proportionally, except that a mon already at its old max stays
  -- at the new max -- a boss that starts a fight full should still start
  -- full, only fuller.
  local function scaleMonMaxHp(mon, multiplier)
    if type(mon) ~= "table" or multiplier == nil or multiplier <= 1 then return false end
    local oldMax = tonumber(mon.maxHp)
      or (type(mon.stats) == "table" and tonumber(mon.stats.hp))
    if not oldMax or oldMax <= 0 then return false end
    local newMax = math.max(1, math.floor(oldMax * multiplier + 0.5))
    local oldHp = tonumber(mon.hp)
    mon.maxHp = newMax
    if type(mon.stats) == "table" then mon.stats.hp = newMax end
    if oldHp == nil then
      mon.hp = newMax
    else
      local scaled = (oldHp >= oldMax) and newMax or math.floor(oldHp * multiplier + 0.5)
      mon.hp = math.max(0, math.min(newMax, scaled))
    end
    return true
  end

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if ev.kind ~= "trainer" or not (battle and isGen2Battle(battle)) then return end
    -- One scale per battle object: battle.started is emitted exactly once,
    -- but the guard makes a second emit (a future caller-driven replay)
    -- harmless rather than compounding the multiplier.
    if battle.__g9CustomTrainerMaxHpScaled then return end
    local trainer = ev.trainer
    local key = trainer and keyFor(trainer.classId or trainer.class, trainer.memberId or trainer.id)
    local record = key and registry[key]
    local multiplier = record and record.maxHpMultiplier
    if not multiplier or multiplier <= 1 then return end
    battle.__g9CustomTrainerMaxHpScaled = true
    local scaled = 0
    for slotIndex, mon in ipairs(battle.enemyParty or {}) do
      if record.party[slotIndex] and scaleMonMaxHp(mon, multiplier) then
        scaled = scaled + 1
      end
    end
    if scaled > 0 then
      mod.log:info("g9-battle-engine: registerTrainer(%s): scaled %d Pokemon to x%s max HP",
        key, scaled, tostring(multiplier))
    end
  end, -1000)

  ------------------------------------------------------------------
  -- 3c. Boss-fight protections -- applied to a registered trainer's own
  --     battle at start, from combat/boss_fight.lua (the flag policy
  --     layer). This file's job is only to carry the caller's inclusion
  --     set here and hand it over via setBossFightFlagTable; each
  --     protection's actual gate lives next to the primitive it gates.
  --
  --     Priority -500: after every default-priority battle.started
  --     handler (so the enemy side exists and any roster/stat work has
  --     settled), and deliberately independent of 3b's -1000 -- the two
  --     touch different fields and do not rely on a relative order.
  --
  --     Once per battle object, same guard idiom as 3b: battle.started
  --     is emitted once, but a second emit is made harmless rather than
  --     re-applying the (idempotent, but chatty) group.
  ------------------------------------------------------------------
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if ev.kind ~= "trainer" or not (battle and isGen2Battle(battle)) then return end
    if battle.__g9CustomTrainerBossFightApplied then return end
    local trainer = ev.trainer
    local key = trainer and keyFor(trainer.classId or trainer.class, trainer.memberId or trainer.id)
    local record = key and registry[key]
    local flags = record and record.bossFightFlags
    if not (flags and next(flags) ~= nil) then return end
    battle.__g9CustomTrainerBossFightApplied = true
    setBossFightFlagTable(battle, flags)
    local names = {}
    for name in pairs(flags) do names[#names + 1] = name end
    table.sort(names)
    mod.log:info("g9-battle-engine: registerTrainer(%s): applied boss-fight protections (%s)",
      key, table.concat(names, ", "))
  end, -500)

  ------------------------------------------------------------------
  -- 4. Combat type (native/doubles/triples/bossFight) -- World:startBattle
  --    wrap.
  --
  -- World:startScriptedBattle (src/world/gen2/World.lua) has ALREADY run
  -- by the time World:startBattle fires -- it builds the real opts
  -- .trainer table (classId/memberId/party/...) and calls
  -- World:startBattle(opts) itself, so opts.trainer.party here already
  -- holds THIS file's own custom roster from integration point 1 above
  -- whenever this is a registered trainer, not the vanilla one.
  --
  -- REAL DIVISION OF RESPONSIBILITY (2026-08-29, explicit user
  -- correction after live testing): this file tells g1r's own native
  -- engine the roster and moves (integration point 1) and holds the stats
  -- to process them in battle (integration points 2/3). It does NOT
  -- decide who fights in a doubles/triples/bossFight layout -- confirmed by direct
  -- read of g9-Battle-Scene's own Screen.new (mods/g9-Battle-Scene/
  -- battle_screen.lua): it builds its enemy battler list with a bare
  -- `for i, mon in ipairs(payload.enemies)` loop, N-agnostic, and has no
  -- way to pull a roster on its own. `trainer.party` -- the SAME real
  -- array integration point 1 already built -- is forwarded here
  -- completely unmodified; g9-Battle-Scene remains fully agnostic to
  -- WHICH Pokemon these are, only ever told the layout name.
  --
  -- Player-side ally selection is a genuinely separate, native concern
  -- (which of the PLAYER's own party comes out) -- kept at the same
  -- layout-preset-driven `allyCount` slice mods/Sample-Battle-Scene-G9's
  -- own tryDoublesTrainer already established, untouched by this
  -- correction (the directive was specifically about the NPC/enemy
  -- roster).
  --
  -- g9-Battle-Scene is a genuinely separate, optional mod -- resolved
  -- live via mod.find, never a hard dependency. Falls straight through
  -- to the real native trainer battle (nativeStartBattle, unmodified)
  -- whenever: this isn't a registered trainer; combatType is "native"
  -- (the default); g9-Battle-Scene isn't installed; or that mod has no
  -- matching "doubles"/"triples"/"bossFight" preset file (pushLayoutBattle's own real,
  -- confirmed refusal contract -- returns nil rather than a partial
  -- push, so this can always tell success from failure and never risk
  -- silently losing a battle).
  ------------------------------------------------------------------
  local World = require("src.world.gen2.World")
  local nativeStartBattle = World.startBattle
  function World:startBattle(opts, onDone)
    local trainer = opts and opts.trainer
    local key = trainer and keyFor(trainer.classId or trainer.class, trainer.memberId or trainer.id)
    local record = key and registry[key]
    local combatType = record and record.combatType
    if record and (combatType == "doubles" or combatType == "triples" or combatType == "bossFight")
        and type(trainer.party) == "table" and #trainer.party > 0 then
      local ok, handled = pcall(function()
        local exportMod = mod.find("g9-Battle-Scene")
        local save = self.game and self.game.save
        if not (exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle
            and save and save.party) then
          return false
        end
        local layoutData = exportMod.exports.getLayoutData
          and exportMod.exports.getLayoutData(combatType)
        -- The preset's own allyCount wins when it declares one (doubles=2,
        -- triples=3, g9-Battle-Scene's bossFight=4 for its 4v1 layout);
        -- defaultCount is only the fallback for a preset that omits it.
        local defaultCount = (combatType == "triples") and 3 or 2
        local allyCount = math.max(1, math.min(6, (layoutData and layoutData.allyCount) or defaultCount))
        -- The player roster: the first `allyCount` LIVING party mons in party
        -- order (2026-09-12, user report).  A raw party[1..allyCount] slice
        -- put a fainted mon on the field with no switch prompt -- and since a
        -- registered trainer's battle is built HERE (the sample defers to
        -- hasRegisteredTrainer rather than pushing its own layout), the skip
        -- has to live here too.  Walking the whole party (rather than
        -- slicing) keeps the lead correct when party[1] is the fainted one.
        local players = {}
        for i = 1, #save.party do
          if #players >= allyCount then break end
          local mon = save.party[i]
          if mon and (mon.hp or 0) > 0 then players[#players + 1] = mon end
        end
        return exportMod.exports.pushLayoutBattle(combatType, self.game, self, {
          enemies = trainer.party, players = players, trainer = trainer,
        }) and true or false
      end)
      if ok and handled then return true end
      if not ok then
        mod.log:warn("g9-battle-engine: registerTrainer(%s): combatType=%s push errored, "
          .. "falling back to the ordinary trainer battle: %s", key, combatType, tostring(handled))
      else
        mod.log:warn("g9-battle-engine: registerTrainer(%s): combatType=%s requested but "
          .. "g9-Battle-Scene is unavailable or has no matching preset, falling back to the "
          .. "ordinary trainer battle", key, combatType)
      end
    end
    return nativeStartBattle(self, opts, onDone)
  end

  mod.log:info("g9-battle-engine: custom_trainer_registry installed "
    .. "(mod.exports.registerTrainer, unregisterTrainer, getRegisteredTrainer, "
    .. "hasRegisteredTrainer, setTrainerMaxHpMultiplier)")
end
