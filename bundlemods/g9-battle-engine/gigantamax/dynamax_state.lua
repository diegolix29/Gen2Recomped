-- Dynamax Level (per-save, 0-10 -- the player's own account-wide
-- progression), Dynamax Level (per-mon, 0-10 -- a specific Pokemon's own
-- fixed level, added 2026-08-28 for NPC trainer definitions, a genuinely
-- different real concept from the per-save one, see that section's own
-- header below), and Gigantamax Factor (per-mon boolean) storage, plus a
-- public mod.exports API for other mods to read AND write all three.
-- Explicit user scope (2026-08-20): we do not decide gimmick
-- activation, we do not write HP, and we do not decide WHEN a value
-- changes -- battle_forms already owns Dynamax/Gigantamax/Mega/Tera/
-- Z-Move activation and mechanics end to end (confirmed via direct
-- source read this session: its own hpscale.lua deliberately never
-- writes real HP either, for the same engine-safety reasons -- a
-- doubled-HP write from this mod on top of that would double-count).
-- This file is pure storage + accessors, with zero runtime battle
-- interference, safe to coexist with battle_forms or anything else.
--
-- Dynamax Level: mod.save:get/set("dynamaxLevel", ...) -- the engine's
-- own documented, namespaced per-mod save bucket
-- (game.save.modData[modId], src/mods/Loader.lua's mod.save
-- implementation, docs/modding.md's own "Durable tool storage" section).
-- Survives save/reload like any other save data; auto-namespaced per mod
-- id, so no collision risk with another mod's own save state. NOT
-- mod.storage -- that's a separate, out-of-band store not rewound by a
-- checkpoint restore, wrong tool for real trainer progress.
--
-- Gigantamax Factor: a bare mon.gigantamaxFactor = true field, set
-- directly on the party/box mon's own save table -- the same pattern
-- battle_forms (mon.battleFormsStone) and wild_forms (mon.form) already
-- use successfully. Confirmed this round-trips safely: the whole save
-- pipeline (SaveSerializer, SaveData.save/validate, Boxes.deposit) is a
-- schema-less, fully generic table walk with no per-field allowlist, so
-- an arbitrary new key on a mon table persists across save/reload and
-- box storage for free. Does NOT survive an actual link-cable trade to
-- another save (a separate, allowlist-based wire protocol,
-- src/link/Protocol.lua) -- would need mon.extra.gigantamaxFactor for
-- that instead; not needed for the currently scoped use, noted for
-- whoever picks this up later.
return function(mod, gmaxData)
  local DYNAMAX_LEVEL_MIN, DYNAMAX_LEVEL_MAX = 0, 10
  local SAVE_KEY = "dynamaxLevel"

  local function clampLevel(n)
    n = tonumber(n) or DYNAMAX_LEVEL_MIN
    if n < DYNAMAX_LEVEL_MIN then n = DYNAMAX_LEVEL_MIN end
    if n > DYNAMAX_LEVEL_MAX then n = DYNAMAX_LEVEL_MAX end
    return math.floor(n)
  end

  -- ---- Dynamax Level: per-save, 0-10 ----
  -- Read API: mod.exports.getDynamaxLevel() -> integer 0-10.
  mod.exports.getDynamaxLevel = function()
    return clampLevel(mod.save:get(SAVE_KEY, DYNAMAX_LEVEL_MIN))
  end

  -- Write API: mod.exports.setDynamaxLevel(n) -> the clamped value it
  -- actually stored. Any other mod can call this directly to grant/set
  -- the level -- we don't gate who calls it or why, that decision is
  -- explicitly theirs (see file header).
  mod.exports.setDynamaxLevel = function(level)
    local clamped = clampLevel(level)
    mod.save:set(SAVE_KEY, clamped)
    return clamped
  end

  -- Convenience write: relative adjustment (e.g. "+1 from a Dynamax
  -- Candy"), still just storage math -- clamps the same as setDynamaxLevel.
  mod.exports.increaseDynamaxLevel = function(amount)
    return mod.exports.setDynamaxLevel(mod.exports.getDynamaxLevel() + (tonumber(amount) or 0))
  end

  -- ---- Dynamax Level: per-mon, 0-10 (a DIFFERENT real concept from the
  -- per-save one above) ----
  -- Added 2026-08-28 for trainers/custom_trainer_registry.lua's own real
  -- need: a specific NPC trainer's own Pokemon has its OWN fixed Dynamax
  -- Level in the actual games (real Sword/Shield gym-leader/story
  -- Dynamax battles), a genuinely different real value from the
  -- player's own account-wide progression tracked above -- not a
  -- narrower/duplicate version of it. Same bare-field storage pattern
  -- mon.gigantamaxFactor already established (a real `nil` when unset,
  -- not a sentinel), for the same save/box/trade round-trip reasons.
  -- Round 12: setMonDynamaxLevel also mirrors the level into battle_forms'
  -- own mon.battleFormsDynamaxLevel stamp (see the write API below), so
  -- battle_forms' own hpscale.lua damage-volume half honors trainer-set
  -- levels directly.
  --
  -- Read API: mod.exports.getMonDynamaxLevel(mon) -> integer 0-10, or
  -- nil if never set for this mon.
  mod.exports.getMonDynamaxLevel = function(mon)
    if not mon or mon.dynamaxLevel == nil then return nil end
    return clampLevel(mon.dynamaxLevel)
  end

  -- Write API: mod.exports.setMonDynamaxLevel(mon, n) -> the clamped
  -- value actually stored, or false if refused (no mon given).
  mod.exports.setMonDynamaxLevel = function(mon, level)
    if not mon then return false end
    local clamped = clampLevel(level)
    mon.dynamaxLevel = clamped
    -- Round 12: immediate mirror into battle_forms' own per-mon stamp --
    -- mon.battleFormsDynamaxLevel, the one battle_forms' own hpscale.lua
    -- reads for the (30+L)/20 damage-volume half -- so battle_forms' own
    -- HP scale reflects this mod's per-mon level even without the
    -- dynamax_battle.lua consumer driving it (same immediate-mirror idiom
    -- tera_state.lua uses for the tera type). battleFormsDynamaxLevel is
    -- battle_forms' documented field; writing it only ever scales the
    -- damage-volume multiplier, never HP itself.
    mon.battleFormsDynamaxLevel = clamped
    return clamped
  end

  -- ---- Gigantamax Factor: per-mon boolean ----
  -- Read API: mod.exports.getGigantamaxFactor(mon) -> true/false.
  mod.exports.getGigantamaxFactor = function(mon)
    return mon ~= nil and mon.gigantamaxFactor == true
  end

  -- Write API: mod.exports.setGigantamaxFactor(mon, true/false) -> the
  -- value actually stored. Same as Dynamax Level: any other mod may call
  -- this directly (e.g. after its own capture/breeding roll decides a
  -- specific individual has the Factor) -- we don't decide when/why,
  -- only persist what we're told. Stored as a real `nil` when false
  -- (not the string/boolean `false`) purely so an unset mon's save
  -- entry stays byte-for-byte identical to one that predates this
  -- field, rather than always growing a new key.
  mod.exports.setGigantamaxFactor = function(mon, value)
    if not mon then return false end
    mon.gigantamaxFactor = value and true or nil
    return mon.gigantamaxFactor == true
  end

  -- ---- Gigantamax-eligible species/forms: read-only reference ----
  -- "any non-mega form of gigantamax's base forms" -- explicit user
  -- definition (e.g. Pikachu and all of Pikachu's alt forms, but never
  -- a _MEGA form). Base species come from gigantamax/gmax_data.lua's own
  -- roster (kept on disk and still loaded for this purpose, even though
  -- its Phase 3 move-registration install is commented out -- see
  -- main.lua's own header for why); alt forms are resolved live through
  -- national_dex's own formsOf/statsBySpecies API rather than a second
  -- hand-maintained list, so this stays correct if national_dex's own
  -- roster grows.
  local gmaxBaseSpecies = {}
  for _, id in ipairs(gmaxData.order) do gmaxBaseSpecies[id] = true end

  -- Read API: mod.exports.isGigantamaxEligibleSpecies(speciesId) ->
  -- true/false. Purely informational -- callers decide for themselves
  -- whether/when to act on it (e.g. before calling setGigantamaxFactor).
  mod.exports.isGigantamaxEligibleSpecies = function(speciesId)
    if type(speciesId) ~= "string" then return false end
    if gmaxBaseSpecies[speciesId] then return true end
    if speciesId:find("_MEGA", 1, true) then return false end
    local nd = mod.find and mod.find("national_dex")
    local ok, rec = pcall(function()
      return nd and nd.exports and nd.exports.statsBySpecies and nd.exports.statsBySpecies(speciesId)
    end)
    local base = ok and rec and rec.baseSpecies
    return base ~= nil and gmaxBaseSpecies[base] == true
  end

  mod.log:info("galar_gmax_dex: dynamax_state installed (Dynamax Level 0-10 per-save AND "
    .. "per-mon, Gigantamax Factor -- storage + API only, no activation/HP)")
end
