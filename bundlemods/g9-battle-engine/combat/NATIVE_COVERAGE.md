# Native-coverage audit and residual-gap inventory (Phase 0)

This document is the audit behind this mod's "what is still missing?" answer.
It exists so that (a) genuinely-impossible moves are named once and never
re-flagged, and (b) every real remaining gap is enumerated, grouped, and
mapped to a wiring phase in `MISSING_EFFECTS_PLAN.md`. Produced in round 81
(Phase 0 of the missing-effects pipeline); regenerate it with the recipe at
the bottom whenever national_dex or this mod's move handling changes.

## Data sources

- **national_dex move records** — `national_dex`'s `moveById` payload, one
  pretty-printed record per modern move. Every record carries (among many
  other fields): `engineMove` (true when the BASE engine already models the
  move for this gen, i.e. not a mod concern at all), `category`, `damageClass`,
  `power`, `ailment`/`ailmentChance`, `flinchChance`, `drain`, `healing`,
  `critRate`, `minHits`/`maxHits`, `minTurns`/`maxTurns`, `statChance`,
  `statChanges`, `target`. 833 moves total, **163 flagged `engineMove = true`**
  and therefore native; the other **670 are the mod's responsibility.**
- **PokeAPI target labels** (`selected-pokemon`, `user`, `user-and-allies`,
  `all-allies`, `ally`, `users-field`, ...) — coarse, used only as
  corroboration (see the Follow Me / Ally Switch note below).
- **Showdown move blocks** — `scratch/showdown/moves.ts`, the real source of
  truth for a move's mechanics. The audit only cares whether a block carries
  any handler *beyond* the flat-data baseline (`num, accuracy, basePower,
  category, name, pp, priority, flags, target, type, contestType, zMove,
  maxMove, isNonstandard, shortDesc, desc, condition`). A block with only
  baseline keys is a plain damage move the engine's own damage pipeline
  computes correctly.
- **This mod's own id references** — every `"MOVEID"` token in the mod's Lua,
  plus the unquoted keys of `main.lua`'s `CUSTOM_EFFECT_PATCH` table.

## Classification

Of the 670 mod-responsibility moves:

| bucket | count | meaning |
|---|---|---|
| referenced | 268 | the id appears in the mod's code or in `CUSTOM_EFFECT_PATCH` — handled by a bespoke handler |
| generically handled | 191 | no bespoke handler, but a field the mod's generic listeners already consume (`flinchChance`, `ailment`+`ailmentChance`, `confusion`+chance, `statChance`+`statChanges`, `drain`, or a native crit/multihit/turn field) |
| structural exemptions | 6 | impossible to observe in a single battle — see below |
| (plain damage) | 49 | no handler beyond baseline; the damage pipeline handles them (Aerial Ace, Dragon Claw, X-Scissor, Seed Bomb, ...) |
| **residual gaps** | **156** | a real Showdown handler exists and nothing in the mod provides it — **the wiring backlog** |

(Some overlap exists between buckets depending on precedence; the table is
the disjoint resolution the audit uses: referenced first, then generic, then
exemptions, then the remainder split into plain damage vs. residual.)

## Structural exemptions (impossible in singles)

These six have a real mechanic that **needs a second allied battler** and can
therefore never be observed in a 1-vs-1 fight. They are named in
`combat/structural_exemptions.lua` (booted by `main.lua` as
`structural_exemptions`) and exported as
`mod.exports.isStructurallyExempt(id)` / `mod.exports.structuralExemptions`.
The harness's round 81 check fails if any of them is ever patched by the mod,
so the registry can never silently contradict a real implementation.

- **ALLYSWITCH** — Showdown `onHit` fails unless `gameType` is doubles/triples
  (`moves.ts:302-330`).
- **DRAGONCHEER** — targets `all-allies` (user excluded); empty target set in
  singles (`moves.ts:4057+`).
- **FOLLOWME** — `onTry` refuses unless `activePerHalf > 1` (`moves.ts:6040+`).
- **HELPINGHAND** — target `ally`, never the user (`moves.ts:8574+`).
- **RAGEPOWDER** — same `activePerHalf > 1` gate as Follow Me (`moves.ts:14599+`).
- **SPOTLIGHT** — `onTryHit` fails when `activePerHalf === 1` (`moves.ts:17764+`).

Deliberately **not** exempt (they include the user and therefore function in
singles as ordinary self-boosts, so they are wiring targets, not exemptions):
**HOWL, GEARUP, MAGNETICFLUX** (each targets `user-and-allies`), and the
doubles-flavoured guard family **WIDEGUARD, QUICKGUARD, CRAFTYSHIELD,
MATBLOCK, SAFEGUARD** (each protects the user's own side, which is the user).

## Residual-gap inventory → wiring phases

156 moves with a real unhandled mechanic, grouped by the shape of their
Showdown handler so each phase shares one primitive. Full id lists are in
`MISSING_EFFECTS_PLAN.md`'s phase sections (13-23).

- **Phase 13 — conditional / variable power** (33): `registerPowerOverride` +
  new turn-state tracking (moved-after, took-damage, statused, HP fraction,
  consecutive use, happiness, target types). The largest phase. **DONE
  (round 82):** `combat/modern_power_conditions.lua`, 29 of the 33 moves;
  STOMPINGTANTRUM, TEMPERFLARE, PURSUIT and COMEUPPANCE deferred to a later
  phase (they need previous-move-failed / switch interception / a flat
  `damageCallback`, not a scaled power).
- **Phase 14 — type-modifying moves** (12): `onModifyType` / `onModifyMove`
  (Hidden Power, Judgment, Multi-Attack, Techno Blast, Weather Ball, Terrain
  Pulse, Tera Blast/Starstorm, Photon Geyser, ...). **DONE (round 83):**
  `combat/modern_type_modify_moves.lua`, all 12 moves; the type/category half
  rides a priority-150 `battle.damage` wrap (mutate + restore the shared move
  record), the power half rides `registerPowerOverride`. Honest partials in
  the file: Natural Gift does not fail without a berry, Weather Ball ignores
  Air Lock / Cloud Nine, and Raging Bull / Tera Starstorm keep the record's
  Normal for a species the engine does not build.
- **Phase 15 — self stat-stage boosts** (19): `boosts` with `statChance = 0`
  (Quiver Dance, Victory Dance, Tail Glow, Work Up, ... plus Howl/Gear Up/
  Magnetic Flux), routed through `modern_movepool_stages.lua`'s `primary(...)`.
  **DONE (round 84):** 19 effects added to `combat/modern_movepool_stages.lua`
  + `main.lua`'s `CUSTOM_EFFECT_PATCH`. Seven carry a real second mechanic
  (Fillet Away / Belly Drum HP cost + fail, Captivate gender gate, Gear Up /
  Magnetic Flux Plus-Minus gate, Tidy Up hazard/Substitute clearing, Geomancy
  charge, Curse Ghost/self branch). Honest partials in the file: Autotomize's
  weight halving is not modelled, the Ghost Curse residual is Gen 2 only, and
  Gear Up / Magnetic Flux reach only the user in singles.
- **Phase 16 — recovery moves** (5): Heal Order, Milk Drink, Slack Off,
  Roost, Aqua Ring. **DONE (round 85):** `combat/modern_recovery_moves.lua`.
  Heal Order / Milk Drink / Slack Off turned out to be **already native**
  (national_dex gen1Effect = HEAL_EFFECT/gen2Effect = EFFECT_HEAL, both
  `*Modeled = true`, and the engine's own heal primitives split on move id
  and heal floor(maxHp/2) for anything but Rest) -- nothing is repointed for
  them. Roost's plain 50% heal was likewise native; the move is repointed
  only so its unmodelled second half (the `duration: 1` Flying-type drop)
  resolves in the same handler, modelled at `resolvedTypeMult`'s own
  `defensiveTypesOf` seam (wrapped, not replaced, so modern_tera's Stellar
  override still runs first). Aqua Ring had no native effect at all -- a full
  1/16 end-of-turn self volatile with a switch-scoped flag. Honest partial in
  the file: Aqua Ring's real "passed on by Baton Pass" half is deferred
  (Baton Pass itself is phase 20).
- **Phase 17 — charge / two-turn / consecutive** (12): Solar Blade, Meteor
  Beam, Shell Trap, Sky Drop, Beak Blast, Ice Ball/Rollout, Round, Echoed
  Voice, the Pledge combo. **DONE (round 86):**
  `combat/modern_charge_moves.lua`. Solar Blade / Meteor Beam / Sky Drop ride
  the engine's own charge machinery (a `charge` record + a Gen 2
  `Effects.CHARGE` entry); Solar Blade's sun-skip extends modern_weather's
  `SUN_SKIPS_CHARGE` and its weak-weather halving is a power override; Meteor
  Beam's charge-turn Sp. Atk rides the real `battle.charge_required` hook; Ice
  Ball/Rollout (`30 * 2^(n-1)`, cap 5, x2 while Defense Curl is up) and Echoed
  Voice (`40 * mult`, 1..5) ride `registerPowerOverride` fed by a
  `move_used` counter; Shell Trap's fail-if-not-hit rides `registerFailGate`
  and Beak Blast's contact burn reads the shared `makesContact`. Honest
  partials in the file: Sky Drop's target-carry half, Ice Ball/Rollout's
  5-turn lock, and the Gen 1 charge announce text are not modelled. Round /
  the Pledges are **already native** (their base damage is correct; only the
  partner's-move half is missing, and it is unobservable in 1-vs-1 -- recorded
  under the structural exemptions' own reasoning).
- **Phase 18 — guard/contact interaction & ignore-ability** (21): Phantom
  Force, Shadow Force, Hyperspace Hole, Chip Away, Sacred Sword, Darkest
  Lariat, Moongeist Beam, Sunsteel Strike, Flying Press, Synchronoise,
  Poltergeist, False Swipe, Supercell Slam, Steel Roller, Ice Spinner, ...
  **DONE (round 87):** `combat/modern_guard_contact.lua` plus the
  damage-formula additions in `modern_combat.lua` and the suppression hook in
  `ability_dispatch.lua`. The three protect-breakers join `BYPASSES_PROTECT`
  (the two Force moves also get charge records); Chip Away / Sacred Sword /
  Darkest Lariat's ignore-defensive/evasion are read off the move record
  (defensive zeroed in the formula, evasion zeroed around the accuracy roll);
  Moongeist Beam / Sunsteel Strike's ignore-ability sets
  `ability_dispatch`'s `ignoredAbilityMon` around the damage computation;
  Flying Press / Synchronoise / False Swipe live in `computeModernDamage`.
  Honest partials in the file: Hyperspace Hole's `bypasssub` Substitute-pierce,
  Order Up's Commander/Tatsugiri forme boost, Supercell Slam's crash-on-miss
  self-damage (only its Reckless boost half is wired), Gen 1 Ceaseless Edge
  Spikes ticking (no Gen 1 switch-in Spikes anywhere), and the Gen 2-only
  Poltergeist/Steel Roller fail gates.
- **Phase 19 — item/held-item interaction** (8): Switcheroo, Trick, Thief,
  Core Enforcer, Spectral Thief, Plasma Fists, Bestow, Flame Burst.
  **DONE (round 88):** `combat/modern_item_moves.lua`. Trick / Switcheroo
  swap held items (Sticky Hold + the Mail exemption refuse, both sides
  restored on an abort), Bestow gives the user's item away, Thief steals on a
  landed hit when the user holds nothing, Spectral Thief copies every positive
  stage (both the mod's atk/def/spa/spd store and the native
  speed/accuracy/evasion store) from the target to the user before the hit
  resolves, Core Enforcer suppresses the target's ability when it has already
  moved this turn, Plasma Fists sets `battle.ionDelugeTurns` (Ion Deluge), and
  Flame Burst's 1/16 ally splash is real code with no targets in 1-vs-1.
  Honest partials in the file: Core Enforcer / Flame Burst's
  `onAfterSubDamage` half (no sub-damage seam). (The family was a Gen 1
  structural no-op until round 99 wired it onto the Gen-1 held-item slot --
  see README.md's round-99 section.)
- **Phase 20 — pivots & move-copying** (11): Baton Pass, Shed Tail, Chilly
  Reception, Assist, Copycat, Sketch, Instruct, Lock-On/Mind Reader, Psych Up,
  Psycho Shift.
  **DONE (round 89):** `combat/modern_pivot_moves.lua`. Baton Pass wraps the
  native handler and carries the mod's per-mon stage bucket across the pivot
  (plus a `lockOn` noCopy drop); Shed Tail pays half max HP and re-applies a
  quarter-max-HP substitute to the incoming mon on the real switch event;
  Chilly Reception sets Snow then switches; Assist samples another party
  member's move, Copycat repeats the battle's previous move (a battle-global
  tracker), Instruct makes the target repeat its last move immediately (all
  three via a nested `copyDepth` dispatch); Sketch permanently rewrites its own
  slot; Lock-On/Mind Reader re-point at the native `EFFECT_LOCK_ON`; Psych Up
  copies 7 stage keys plus the crit volatiles; Psycho Shift transfers the
  user's status and cures it only on a successful transfer. Honest notes in
  the file: Copycat's tracker can capture a move that then missed/failed, and
  the whole family is a Gen 2 structural no-op on Gen 1 (no pivot primitive).
- **Phase 21 — status/volatile infliction residue** (9): Will-O-Wisp, Spite,
  Forest's Curse, Trick-or-Treat, Power Trick, Magnet Rise, Eerie Spell,
  Sparkling Aria, Pollen Puff.
  **DONE (round 90):** `combat/modern_status_moves.lua`. Spite / Eerie Spell
  cut the target's last-used move's PP (Showdown `deductPP`: clamp at 0, fail
  when nothing is removed); Sparkling Aria cures a burned target on a landed
  hit; Forest's Curse / Trick-or-Treat append a single added type (a new
  `addMonType`, switch-scoped, gated through `canChangeType`); Power Trick
  swaps the user's raw Atk/Def and reverts on a second use / switch-out /
  battle end; Magnet Rise grants a 5-turn Ground immunity (resolved beside
  Telekinesis in `resolvedTypeMult`). Already native / structural, not wired:
  Will-O-Wisp (`EFFECT_BURN`, `effectModeled=true` on Gen 2) and Pollen Puff's
  ally heal (unreachable in 1-vs-1; its damage is native and correct).
- **Phase 22 — field/side protection & delayed** (11): Hail, Safeguard, Wide
  Guard, Quick Guard, Crafty Shield, Mat Block, Doom Desire, Future Sight,
  Present, First Impression, Grassy Glide.
  **DONE (round 91):** `combat/modern_side_protection.lua`. Safeguard is
  re-pointed at the base engine's own `EFFECT_SAFEGUARD` (it was already fully
  native -- national_dex shadowed the move), with a direct fallback. The four
  guards are per-side `battle.g9Guards` flags cleared at `battle.turn_ended`;
  Wide/Quick Guard arm the shared Protect stall chain; a blocked move is
  nullified through the same `moveEffectRecordFor` substitution seam Protect and
  the action-order fail gate use (PP spent, "used Y!" still announced). Future
  Sight / Doom Desire ride a shared 2-turn side-slot scheduler
  (`resolveTurn = turn + 1`, Showdown's `endingTurn = (turn - 1) + 2`) using the
  engine's own `Damage.calc`; Present rolls once on `battle.move_used` and its
  heal tier is a `battle.damage` wrap; Grassy Glide is a
  `registerPriorityModifier` (+1 on Grassy Terrain while grounded). HAIL is
  **deliberately deferred** (the standing "we won't bring hail yet" instruction
  -- Snow/Snowscape is its real replacement), so 10 of the 11 ids ship.
- **Phase 23 — recharge / self-recoil / self-drop** (15): the `self` group
  (Blast Burn, Frenzy Plant, Hydro Cannon, Giga Impact, Roar of Time, ...),
  Mind Blown, Steel Beam, Misty Explosion. **DONE (round 92):** shipped as
  `combat/modern_self_effects.lua`. The eight recharge moves set the native
  `volatile.recharge` (Gen 2) / `mustRecharge` (Gen 1) on a landed hit; Mind
  Blown / Steel Beam's half-MAX-HP loss fires on the `Battle.useMove` wrap (Gen 2)
  or the record's `onMiss`/`afterDamage` (Gen 1), hit or miss, Magic-Guard-blocked
  but not Rock-Head; Misty Explosion's `selfdestruct:"always"` faint rides the
  same wrap plus a `registerDamageModifier` 1.5x on grounded Misty Terrain;
  Glaive Rush's `self` volatile sits on the USER (doubles incoming damage via
  `registerDamageModifier("glaive_rush", 90)` and makes every incoming move a
  `battle.accuracy` sure hit, cleared at the holder's next `battle.move_used`);
  Baddy Bad / Glitzy Glow set Reflect / Light Screen on the user's side (Light
  Clay 5 -> 8) and Sparkly Swirl cures the whole side (Gen-2-state halves,
  `clearVolatile`/`screens`/`cureStatusOf` reuse). All fifteen planned ids ship.

Removed from earlier plans as genuinely dead (engine-native or already wired)
after this audit: HAZE, MIST, CONVERSION, DESTINY BOND, GRUDGE, SPIDER WEB
(native base-engine effects), and FOCUS_ENERGY / PSYCH_UP / MIMIC (native or
present in the codebase).

## Reproducing the audit

1. Dump national_dex move records and parse the `engineMove` / field data.
2. Parse `scratch/showdown/moves.ts` blocks and keep the non-baseline keys.
3. Scan this mod's Lua for `"MOVEID"` tokens and `CUSTOM_EFFECT_PATCH` keys.
4. Apply the classification table above; the residual set is every move with a
   non-baseline Showdown key that is neither referenced, generic, exempt, nor
   plainly-damaging.
5. Re-run the fengari harness (round 81) — it asserts the exemption registry
   boots, names the six ids, and stays disjoint from the move-patch log.
