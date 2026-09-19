-- Boss-fight protection flags: a cross-cutting policy layer other mods
-- (or this mod's own future boss-encounter setup code) can flip on for a
-- specific battle, gating a named set of protections that apply ONLY to
-- the enemy side of the field (the boss). Explicit user spec, this
-- session -- not derived from national_dex or any other data source, so
-- there is no abilities/data-style inclusion-list file here: the flag
-- SET itself is exactly the caller's own inclusion list, held directly
-- on the battle.
--
-- mod.exports.setBossFightProtections(battle, "sun", "mistyTerrain", ...)
-- -- variadic, not a full config object: only the NAMED protections turn
-- on, everything else stays off. Internally stored as battle.bossFightFlags
-- = {name=true, ...}, so a consumer checking one flag never has to reason
-- about the ones it didn't pass.
--
-- Recognized names (each one's actual enforcement lives next to the real
-- primitive it gates, not centralized here -- same "the gate lives beside
-- the thing it gates" convention canSetWeather already established
-- alongside setWeather):
--   sun          -- combat/modern_combat.lua's setWeather/canSetWeather:
--                    the boss's own weather-setting becomes permanent and
--                    beats even a player's primal weather; the player's
--                    side can't set or override weather at all.
--   mistyTerrain -- combat/modern_terrain.lua's setTerrain: same shape,
--                    for terrain.
--   statsDrop    -- combat/modern_combat.lua's changeStage +
--                    combat/modern_movepool_stages.lua's changeNativeStage:
--                    the boss can't have ANY stat lowered, hostile or
--                    self-inflicted.
--   type         -- combat/type_override_primitives.lua's canChangeType:
--                    the boss's type can't be changed by an opponent-
--                    directed effect (Soak et al); its own self-activated
--                    kit (Protean, Color Change, a self-targeted Conversion)
--                    is unaffected.
--   ability      -- ENFORCED (2026-08-28): abilities/ability_dispatch
--                    .lua's own mod.exports.setAbility -- the real "change
--                    a mon's ability" primitive this flag was originally
--                    reserved for -- refuses outright whenever the target
--                    is battle.enemy and this flag is set. Applies equally
--                    to every future ability-changing/copying move or
--                    ability built on top of setAbility (Skill Swap, Worry
--                    Seed, Entrainment, Gastro Acid, Trace, Mummy,
--                    Wandering Spirit, Receiver, Power of Alchemy), since
--                    none of them have any route to the boss's ability
--                    that bypasses setAbility itself.
--   dimensionLock, trickRoom, magicRoom, wonderRoom
--                -- combat/trick_room.lua: room-move banning and
--                    permanent-room application. See that file's own
--                    header for the full four-flag breakdown.
--   hardStatus   -- combat/boss_fight_status.lua (ENFORCED 2026-09-10):
--                    the boss can't be given a major status (poison/burn/
--                    paralyze/sleep/freeze). Both generations' shared
--                    infliction primitives (StatusRegistry.inflict and
--                    Battle:applyStatus) are gated, so native status moves
--                    are covered too. Rest is unaffected -- it writes the
--                    status directly and bypasses both gates, so a boss may
--                    still put ITSELF to sleep.
--   softStatus   -- combat/boss_fight_status.lua (ENFORCED 2026-09-10): the
--                    boss can't be confused -- the mod's own secondary-
--                    confusion chance roll and Flatter/Swagger are both
--                    gated. Leech Seed is a documented no-op here (the mod
--                    has no Leech Seed implementation to gate).
--   antiDrain    -- combat/boss_fight_status.lua (ENFORCED 2026-09-10):
--                    draining a protected enemy deals the would-be heal
--                    back to the ATTACKER as self-harm instead.
--   healblock    -- combat/heal_block.lua (ENFORCED 2026-09-10): while set, the
--                    PLAYER's side can't restore HP by any means (moves, items,
--                    abilities, drain, residuals) -- the boss-fight form of the
--                    Heal Block mechanic. Blocked heals are dropped, never
--                    converted to damage.
--
-- The canonical name list lives in BOSS_FIGHT_FLAG_NAMES below (exported),
-- so a caller -- including this mod's own registerTrainer option plumbing --
-- can validate and iterate the set instead of hardcoding it in several
-- files.
return function(mod)
  -- The canonical flag names, in one place -- display order, not a
  -- priority. Exported so a caller (and this mod's own registerTrainer
  -- option plumbing in trainers/custom_trainer_registry.lua) validates
  -- against the single source of truth instead of a second hardcoded list.
  local BOSS_FIGHT_FLAG_NAMES = {
    "sun", "mistyTerrain",
    "statsDrop", "type", "ability",
    "hardStatus", "softStatus",
    "antiDrain",
    "dimensionLock", "trickRoom", "magicRoom", "wonderRoom",
    "healblock",
  }
  local BOSS_FIGHT_FLAG_SET = {}
  for _, name in ipairs(BOSS_FIGHT_FLAG_NAMES) do BOSS_FIGHT_FLAG_SET[name] = true end
  mod.exports.BOSS_FIGHT_FLAG_NAMES = BOSS_FIGHT_FLAG_NAMES
  -- True for a spellable flag name (including the documented healblock
  -- no-op), false for anything else. A caller parsing free-form input uses
  -- this to separate "known flags" from typos.
  mod.exports.bossFightFlagIsKnown = function(name)
    return name ~= nil and BOSS_FIGHT_FLAG_SET[name] == true
  end

  -- Shared applicator for both public setters below. `flags` is the
  -- {name=true} set that ends up on battle.bossFightFlags; nothing is
  -- filtered here (see setBossFightProtections' own note on the stored set
  -- being exactly the caller's inclusion list).
  -- 2026-09-16 (user: "trick room, wonder room, magic room arent setting
  -- their respective room effects ... at battle start"): a permanent room is
  -- an immediate environmental fact, so it now ANNOUNCES itself the moment it
  -- is applied -- exactly the flavor text casting the move would show -- so
  -- the boss fight's own start visibly establishes the room. Without this the
  -- fields were set correctly but silently, which reads as "nothing happened".
  local function announce(battle, text)
    if type(battle) ~= "table" or type(battle.emit) ~= "function" then return end
    pcall(function() battle:emit({ kind = "message", text = text }) end)
  end

  local function applyFlags(battle, flags)
    if not battle then return end
    battle.bossFightFlags = flags
    -- trickRoom is read as an immediate environmental fact ("the battle
    -- IS permanent Trick Room"), not something contingent on the move
    -- ever being cast -- unlike weather/terrain's boss-lock (which only
    -- activates once the boss sets one through its own kit), so it's
    -- applied right here rather than waiting on a trigger. combat/
    -- trick_room.lua owns the real field (battle.trickRoomActive/
    -- battle.trickRoomTurns) -- written directly here, the same "plain
    -- field write, no dedicated setter required" convention weather/
    -- terrain's own boss-lock already uses. The same now applies to
    -- magicRoom (battle.magicRoomActive) and wonderRoom
    -- (battle.wonderRoomActive, applied to each active mon through that
    -- file's own exported helper since its flag is per-battler).
    if flags.trickRoom then
      battle.trickRoomActive = true
      battle.trickRoomTurns = math.huge
      announce(battle, "The dimensions were twisted!")
    end
    -- Magic Room / Wonder Room got their real field effects in the same
    -- round this comment changed (combat/trick_room.lua now owns
    -- battle.magicRoomActive/magicRoomTurns and the per-mon Wonder Room
    -- swap), so the boss-lock's "permanent" half is real for all three now,
    -- not a move-ban-only flag. Wonder Room's flag lives on each active
    -- mon, so it is applied through that file's own exported helper.
    if flags.magicRoom then
      battle.magicRoomActive = true
      battle.magicRoomTurns = math.huge
      announce(battle, "It created a bizarre area in which held items lose their effects!")
    end
    if flags.wonderRoom then
      battle.wonderRoomActive = true
      battle.wonderRoomTurns = math.huge
      local applyWonderRoomToActives = mod.exports.applyWonderRoomToActives
      if applyWonderRoomToActives then applyWonderRoomToActives(battle, true) end
      announce(battle, "It created a bizarre area in which Defense and Sp. Def are swapped!")
    end
  end

  -- Variadic public form (the original API, unchanged): names, not a config
  -- object. Only the NAMED protections turn on, everything else stays off.
  mod.exports.setBossFightProtections = function(battle, ...)
    local flags = {}
    for _, name in ipairs({ ... }) do
      flags[name] = true
    end
    applyFlags(battle, flags)
  end

  -- Table public form: `flags` is a {name=true} set (the same shape stored
  -- on battle.bossFightFlags), or an array of names. Used by this mod's own
  -- registerTrainer option plumbing, which builds its set as a table and
  -- cannot splice it into a variadic call without depending on
  -- unpack/table.unpack across Lua versions. Unknown names are stored too,
  -- matching setBossFightProtections -- validation belongs at the caller.
  mod.exports.setBossFightFlagTable = function(battle, flags)
    local copy = {}
    if type(flags) == "table" then
      for k, v in pairs(flags) do
        if type(k) == "number" then
          if type(v) == "string" then copy[v] = true end
        elseif v then
          copy[k] = true
        end
      end
    end
    applyFlags(battle, copy)
  end

  -- Plain read helper -- every gate below reads through this rather than
  -- poking battle.bossFightFlags directly, so a battle with no boss-fight
  -- flags set at all (the overwhelming majority of battles) never needs
  -- more than one nil check at each call site.
  mod.exports.bossFightHas = function(battle, name)
    return battle ~= nil and battle.bossFightFlags ~= nil and battle.bossFightFlags[name] == true
  end

  mod.log:info("g9-battle-engine: boss_fight installed (setBossFightProtections, setBossFightFlagTable, bossFightHas, BOSS_FIGHT_FLAG_NAMES)")
end
