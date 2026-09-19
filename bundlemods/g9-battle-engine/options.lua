-- Mod Manager option schema for g9-battle-engine (combat-only fork:
-- see main.lua's own header for what this fork does and doesn't own).
--
-- Declared in manifest.json's "options_schema" field, same as Wilds of
-- Kanto's own options.lua, so the Mod Manager can lazy-load and render
-- this list even before/without the mod's own entry chunk running (a
-- disabled mod's options are still viewable/editable this way). main.lua
-- also calls mod.options:define() with this exact table at load time, so
-- both the static manifest path and the live mod.options:get() reads
-- share one source of truth instead of two schemas that could drift.
--
-- Visible labels stay short: the Mod Manager's row layout truncates long
-- labels (same constraint every other mod's options.lua documents).
--
-- mod.options:define() REPLACES the whole schema on every call -- it is
-- not additive across multiple calls within the same mod (confirmed from
-- Loader.lua: loader.optionSchemas[modId] = schema, a plain overwrite).
-- gmax_custom_art and animated_battle_sprites used to be defined by their
-- own separate mod.options:define() calls elsewhere in main.lua
-- (installGmaxAssetPacks, installSpriteAnimation) -- each call silently
-- discarded whatever schema came before it, which is exactly why only the
-- LAST-registered option ever showed up in the Mod Manager screen. Both
-- rows now live here instead, in this one shared schema, and those two
-- functions no longer call mod.options:define at all -- see main.lua.
-- Keys/types/choices/defaults are unchanged from their original
-- definitions, so every existing mod.options:get(...) read elsewhere in
-- this mod keeps working exactly as before.
-- [g9-battle-engine] gmax_custom_art, animated_battle_sprites,
-- wild_spawns_enabled, use_base_area_tables, classic_encounters,
-- wild_max_per_map, follower_enabled, wild_contact_radius, and
-- national_dex_sprites removed -- all sprite/spawn/overworld/follower
-- toggles with nothing left in this fork to control. See
-- g9-battle-engine for those.
-- gimmicks and vanilla_enhanced_layout removed too (2026-08-20): both
-- custom battle scenes (Gen 1 overlay + Gen 2 full screen) that these
-- controlled are deleted outright, not just uncalled -- see main.lua's
-- own header.
-- Round 104 (2026-09-10) removed five more rows, each with its code:
--   gen2_wide_layout (GEN 2 MOVE TYPE READOUT)  -- combat/gen2_wide_scene.lua deleted.
--   custom_menu_scene (CUSTOM MENU SCREENS)     -- ui/custom_menu_takeover.lua and
--                                                  ui/custom_party_scene.lua deleted.
--   gigantamax_size (GIGANTAMAX SIZE)           -- Gen 1 draw-time size-up removed from
--   gigantamax_skip_animation (SKIP GIGANTAMAX     gigantamax/dynamax_battle.lua (battle_forms
--     GROW/SHRINK)                                 owns Dynamax sizing on both generations).
--   bf_tera_dev (BATTLE FORMS TERA DEV)         -- gigantamax/tera_state.lua now forces
--                                                  battle_forms' TERA TYPE option to AUTO
--                                                  unconditionally; the dev escape hatch is gone.
-- gigantamax/dynamax_battle.lua stays -- its Dynamax Level drive and
-- max_move_subeffects.lua are unaffected by the size-up removal.
-- Round 105 (2026-09-16) renamed two rows and gave one of them a real
-- body:
--   show_hp_lost_messages -> damage_numbers  (label SHOW HP LOST MESSAGES
--     -> DAMAGE NUMBERS). No longer a placeholder: ON makes the battle
--     scene float each Pokemon's HP change over its own HP bar -- a red
--     "-N" for damage taken, a green "+N" for HP recovered -- each one
--     living one second then fading to invisible. main.lua exports
--     mod.exports.damageNumbersEnabled() (which reads this key) so
--     g9-Battle-Scene gates on the SAME option the Mod Manager shows;
--     the scene derives the two values itself from the HP vector the
--     engine already stamps on every emitted event (event.g9SceneHp),
--     so no per-hit amount plumbing is needed and the numbers are
--     correct for every HP change either generation emits.
--     Works on both generations.
--   dev_tools -> adv_stats (label DEV TOOLS -> ADV.STATS; the party-
--     submenu entry and its in-screen titles read "Adv.Stats" now too).
--     stats/dev_stats_screen.lua is unchanged except that on a Gen 1
--     boot its window is 20% larger in both axes (160x144 -> 192x173)
--     with its layout scaled to match.
-- Round 176 (2026-09-18) added one row, defaulting ON:
--   train_screen (TRAIN SCREEN) -- stats/train_screen.lua, the party-
--     submenu editor MOVED here from g9-battle-sample (it edits THIS mod's
--     modern stats, so this is where it belongs).  Rides with the engine.
return {
  -- Damage Numbers (round 105, renamed from show_hp_lost_messages).
  -- Read by main.lua's mod.exports.damageNumbersEnabled(), which the
  -- battle scene consults before floating a number. The scene computes
  -- the delta from the per-event HP vector the engine stamps
  -- (event.g9SceneHp), so this option only has to say ON/OFF.
  {
    key = "damage_numbers",
    label = "DAMAGE NUMBERS",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "ON: the battle scene floats each Pokemon's HP change over its own HP bar as it happens -- a red \"-N\" for damage taken and a green \"+N\" for HP recovered -- each fading out over one second. Works on both generations. OFF (default): no floating numbers.",
  },
  {
    key = "gym_badge_buff",
    label = "GYM BADGE BUFF",
    type = "choice",
    default = "true",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "ON (default): owning certain badges boosts the player's WHOLE side's stats/move-type damage (real Gold/Silver mechanic, now correctly applied to every player-side battler in a doubles/triples fight, not just the lead -- native Gen 2 only ever checked the single primary battler). OFF: no badge stat/type boost for anyone.",
  },
  {
    key = "adv_stats",
    label = "ADV.STATS",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "ON: adds an Adv.Stats entry to the party submenu (selected Pokemon) showing its ability/nature/Tera type/Dynamax level/Gigantamax Factor, real combat stats, and full EV/IV distribution across 3 pages (the Gen 1 window is 20% larger). OFF (default): party submenu is unchanged.",
  },
  -- TRAIN screen (round 176, 2026-09-18). The party-submenu editor moved
  -- here from g9-battle-sample; ON by default so it rides with the engine.
  {
    key = "train_screen",
    label = "TRAIN SCREEN",
    type = "choice",
    default = "true",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "ON (default): adds a TRAIN entry to the party submenu (selected field Pokemon) that opens an editor for its IVs / EVs / Nature / gender and a MOVES page that teaches Egg, Relearn and Tutor moves the species can learn for 5000 each (never TMs/TRs; an HM slot is never forgotten). Edits ride the save like any other field. OFF: the party submenu is left exactly as the engine found it.",
  },
}
