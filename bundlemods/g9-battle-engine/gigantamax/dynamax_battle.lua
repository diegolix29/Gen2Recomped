-- Dynamax combat-property processor (round 13).
--
-- Explicit user scope (2026-08-20, restated 2026-09-07): battle_forms owns
-- Dynamax/Gigantamax activation and mechanics end to end -- WHEN a Pokemon
-- Dynamaxes, its 3-turn clock, its Max Move substitution (BATTLE_FORMS_*
-- ids), its damage-volume half (hpscale.lua), its Max Guard, and its sprite
-- sizing on BOTH generations (gen2dynamaxgrow.lua on Gen 2; the Gen 1
-- draw-time seam was this mod's until round 104 removed it -- see below).
-- This mod does NOT decide when a gimmick activates and does NOT provide its
-- own gimmick activation. It READS the activation trigger battle_forms
-- already emits -- mod.battle_forms's own `dynamax_applied` /
-- `dynamax_reverted` events (src/formapi.lua, fired from src/dynamax.lua's
-- own apply/teardown) -- and CONSUMES it to process the Dynamax combat
-- properties battle_forms deliberately leaves open, exactly the same
-- consume-only relationship tera_state.lua already has with `tera_applied`:
--
--   1. Dynamax Level drive. battle_forms' damage-volume half is
--      (30 + L) / 20 -- hpscale.lua reads L from the mon's
--      battleFormsDynamaxLevel stamp, which defaults to 0 (x1.5 HP). The
--      REAL level that should drive that multiplier is the one this mod
--      stores (dynamax_state.lua): per-mon when a trainer set one, else
--      battle_forms' own candy stamp when a Dynamax Candy was used, else
--      the player's per-save progression. On `dynamax_applied` we derive
--      that effective level and mirror it back into the mon's
--      battleFormsDynamaxLevel stamp so battle_forms' own hpscale uses
--      OUR answer (same read-backfill idiom tera_state.lua uses for the
--      tera type). Level 0 (x1.5) stays the default -- an unleveled
--      player who never touched a Candy or a trainer definition behaves
--      exactly as battle_forms ships.
--
--   2. Max Move secondary effects. battle_forms registers every damaging
--      Max Move as NO_ADDITIONAL_EFFECT (its own deliberate scope -- the
--      move data is generic across games and their gmaxmoves.lua has no
--      per-move secondaries). The Showdown-verified secondaries for Max
--      AND G-Max moves are processed in max_move_subeffects.lua, the
--      SAME way this mod processes every other move: a kind="full"
--      move-effects record (invisible to Gen 2's damage-preempting
--      dispatch) plus one shared battle.damage_dealt listener keyed on
--      the move's own effect field. Moves are discovered by battle_forms'
--      own BATTLE_FORMS_<STEM>_<POWER> id convention; the power ladder
--      (90-150 / 70-100 Fighting+Poison / fixed-160 G-Max) stays
--      battle_forms' -- this file never decides base power. maxguard
--      (status) is battle_forms' own -- skipped.
--
-- Round 104 removed the Gen 1 draw-time size-up this file used to carry
-- (the BattleState:drawBattlerPic wrap + its eased grow/shrink tween, plus
-- the gigantamax_size / gigantamax_skip_animation options): battle_forms
-- owns Dynamax sprite sizing on both generations now, so the Gen 1 seam was
-- redundant. The only thing this file still stamps is the __g9Dynamaxed
-- marker that combat/type_override_primitives.lua reads for its Dynamax
-- type-change immunity.
--
-- Why gimmick_dynamax.lua stays DISABLED (canonical-disabled, not
-- deleted): it is a full parallel Dynamax engine -- its own activation
-- ring, its own Max Move resolution, its OWN doubled-HP write and
-- per-battle 3-turn clock. battle_forms already owns all of that (the
-- 2026-08-20 scope note's whole point: a doubled-HP write from this mod
-- on top of battle_forms' would double-count), so booting both would
-- double HP, double substitutes, and race two 3-turn clocks. This file
-- is the consume-only replacement for that parallel engine.
return function(mod)
  if mod.exports.dynamaxBattleInstalled then return mod.exports end
  mod.exports.dynamaxBattleInstalled = true

  local clampLevel = function(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    if n > 10 then n = 10 end
    return math.floor(n)
  end

  -- ---------------------------------------------------------------------
  -- Trigger source: battle_forms' own events (pcall-guarded so the
  -- consume side still comes up if battle_forms is absent -- a
  -- dynamax_battle with no dynamax source just idles; the level/store
  -- reads remain safe no-ops).
  -- ---------------------------------------------------------------------
  local appliedEvent, revertedEvent = "mod.battle_forms.dynamax_applied", "mod.battle_forms.dynamax_reverted"
  local okBf, bf = pcall(function() return mod.find and mod.find("battle_forms") end)
  if okBf and bf and bf.exports and bf.exports.events then
    if type(bf.exports.events.dynamaxApplied) == "string" then
      appliedEvent = bf.exports.events.dynamaxApplied
    end
    if type(bf.exports.events.dynamaxReverted) == "string" then
      revertedEvent = bf.exports.events.dynamaxReverted
    end
  end

  -- ---------------------------------------------------------------------
  -- 1. Dynamax Level drive + Dynamaxed marker. Keyed on the mon itself
  --    (battle_forms' payload carries the LIVE mon, not a battle -- Gen 1
  --    it is battle.player.mon, Gen 2 it is battle.player).
  -- ---------------------------------------------------------------------
  local function handleApplied(ev)
    local mon = ev and ev.mon
    if not mon then return end
    mon.__g9Dynamaxed = true
    local effective
    local perMon = mod.exports.getMonDynamaxLevel and mod.exports.getMonDynamaxLevel(mon)
    if perMon ~= nil then
      effective = perMon
    elseif type(ev.dynamaxLevel) == "number" and ev.dynamaxLevel > 0 then
      -- battle_forms' own Dynamax Candy stamp (mon.battleFormsDynamaxLevel
      -- already set by its dynamaxlevel.lua) -- a per-mon candy is more
      -- specific than the per-save progression, so it wins over it.
      effective = ev.dynamaxLevel
    else
      effective = mod.exports.getDynamaxLevel and mod.exports.getDynamaxLevel() or 0
    end
    effective = clampLevel(effective)
    -- Mirror OUR effective level back into the stamp battle_forms' own
    -- hpscale.lua reads, so its (30+L)/20 damage-volume half reflects the
    -- level this mod actually stores. Same read-backfill idiom
    -- tera_state.lua uses for battleFormsTeraType.
    mon.battleFormsDynamaxLevel = effective
    return effective
  end

  local function handleReverted(ev)
    local mon = ev and ev.mon
    if not mon then return end
    mon.__g9Dynamaxed = nil
  end

  -- ---------------------------------------------------------------------
  -- Public predicate over the __g9Dynamaxed marker (round 27). Accepts
  -- either a battle battler (Gen 2: the live mon IS the battler) or a bare
  -- mon (Gen 1: battle.player.mon) -- checks the given table, then its own
  -- `.mon`, so every caller can ask with whatever handle it holds. combat/
  -- type_override_primitives.lua already reads the marker directly for its
  -- Dynamax type-change immunity; the newer consumers (status/flinch
  -- immunity in abilities/engine/status_immunity.lua and hit_taken.lua,
  -- and the Leech Seed gate) go through this so the marker's shape stays
  -- known in exactly one place.
  mod.exports.isDynamaxed = function(mon)
    if not mon then return false end
    if mon.__g9Dynamaxed then return true end
    local inner = mon.mon
    return (inner and inner.__g9Dynamaxed) == true
  end

  -- ---------------------------------------------------------------------
  -- Wiring: subscribe to the trigger and defensively clear the marker on
  -- battle end (battle_forms emits a revert itself on teardown, but a
  -- battle ending mid-Dynamax should never leave a stale marker behind).
  -- ---------------------------------------------------------------------
  mod.events:on(appliedEvent, function(ev)
    handleApplied(ev)
  end)
  mod.events:on(revertedEvent, function(ev)
    handleReverted(ev)
  end)
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, b in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      local mon = b and (b.mon or b)
      if mon then
        mon.__g9Dynamaxed = nil
      end
    end
  end)

  mod.log:info("galar_gmax_dex: dynamax_battle installed (consumes battle_forms' "
    .. "dynamax_applied/reverted -- Dynamax Level drive; Max Move secondaries live in max_move_subeffects.lua)")
  return mod.exports
end
