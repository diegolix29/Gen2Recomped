# Missing effects — phased wiring plan

Prepared 2026-09-12 (round sixty-nine). Companion to `combat/SUBEFFECTS.md`
(the wiring procedure), `combat/MULTI_BATTLE_HOOKS.md` (the N-way contract),
`combat/MOVEPOOL_EFFECT_COVERAGE.md` (the dated 2026-08-23 move audit),
`PROGRESS.md` (ability phases) and `list.md` (the running gap tracker).

## What "missing" means here

The mod's own `main.lua` generically auto-wires, for **every** move in
national_dex's roster, from the live record alone:

- flinch chance (`flinchChance`),
- confusion chance (`ailment == "confusion"`),
- secondary major status (`ailment` + `ailmentChance`, with a live
  TARGET/USER direction read for stat changes),
- secondary stat changes (`statChanges` + `statChance`),
- drain/recoil (`drain`, clamped to real HP lost),
- multi-hit (`minHits`/`maxHits`) and high-crit (`critRate >= 1`).

So a move is **not** missing just because it has one of those. It is
missing when its real mechanic is something those six buckets — plus the
`CUSTOM_EFFECT_PATCH` map in `main.lua` — cannot express. The audit below
was built by parsing all 833 national_dex move records and diffing against
every quoted move id in the mod's own source (192 files), then excluding
(a) Gen 1/2 moves the base engine already runs natively, (b) spread
damaging moves (already covered by `computeModernDamage`'s own inline
0.75x-per-target reduction + `resolveMoveTargets`), (c) turn-based status/stat
secondaries (generic), and (d) doubles-only moves with no singles meaning.

## Standing constraints (unchanged, apply to every phase)

- **Showdown is the source of truth.** Transcribe with `file:line`
  citations from `scratch/showdown/*.ts`; never recall formulas.
- **Never re-register a move.** `mod.content.moves:patch(id, {effect=...})`
  only. Never a `run` field on a record for a move that must still deal
  damage (Gen 2's dispatch pre-empts its own damage path).
- `kind="primary"/"secondary"` + `run`, or `kind="full"` + a
  `battle.damage_dealt` listener (the modern_switch_moves pattern).
- RNG is `battle:roller()(n)` → `0..n-1` on Gen 2; `battle.random(n)` on the
  Gen 2 object. Emit text with `battle:emit({kind="message", text=...})`.
- Reuse exported primitives (`changeStage`, `curStatsOf`, `curTypesOf`,
  `registerPowerOverride`, `registerDamageModifier`, `requestSwitch`,
  `requestAdjacency`, `resolveTurnActions`, `emitAll`, `cureStatusOf`,
  `abilityIdOf`, `setAbility`, `displayNameFor`).
- Every phase ends with: fengari harness green (`scratch/run-harness.js`),
  a new `roundNN` check block, KV persist (byte-identical), a mod README
  section where user-facing, and a manifest/project version bump.
- Gen 1 must stay non-crashing (guard `isGen2Battle`; Gen 1 uses
  `battle.rng(1,n)` inclusive and `EffectRegistry` shapes).

---

## Phase 0 — Native-coverage audit + structural-exemption registry

**Closes:** nothing gameplay-facing; removes false "missing" claims and
makes the exemptions explicit instead of implied.

**Work:** for every Gen 1/2 move national_dex registers, assert the base
engine has a real effect for it (several Gen 1 moves — HAZE, MIST,
FOCUS ENERGY, MIMIC, PSYCH UP, SPIDER WEB, CONVERSION, DESTINY BOND,
GRUDGE — did **not** turn up under the obvious base-effect names; if
national_dex leaves them at `EFFECT_NORMAL_HIT` they are silently dead
and must be added to a later phase). Add `combat/structural_exemptions.lua`
documenting, by name and reason, every move that is impossible rather than
unbuilt: **ALLYSWITCH** (no second ally slot), **SNIPESHOT** (no
redirection to be immune to in singles), and the doubles-only support set
(**FOLLOWME, RAGEPOWDER, SPOTLIGHT, HELPINGHAND, WIDEGUARD, QUICKGUARD,
CRAFTYSHIELD, MATBLOCK, DRAGONCHEER, COACHING, DECORATE, FLOWERSHIELD,
AROMATICMIST, GEARUP, HOWL, MAGNETICFLUX, TAKEHEART**'s ally half).
**Files:** new `combat/structural_exemptions.lua`, `combat/NATIVE_COVERAGE.md`.
**Harness:** a `roundNN` check that the exemption list has no id the mod
also patches; a boot check that no exempt id is left with a broken effect.

**STATUS: DONE (round 81).** The audit ran over the full national_dex move
set (833 records; 163 `engineMove = true` native, 670 mod-responsibility) and
the Showdown blocks, and the results are written up in
`combat/NATIVE_COVERAGE.md`. Two corrections to the plan text above:

1. The exemption registry is deliberately **narrower** than the move list
   first sketched here. It contains exactly six moves whose real mechanic
   needs a second allied battler and is therefore unobservable in singles:
   **ALLYSWITCH, DRAGONCHEER, FOLLOWME, RAGEPOWDER, HELPINGHAND, SPOTLIGHT**.
   The moves that were grouped with them but actually *include the user* —
   **HOWL, GEARUP, MAGNETICFLUX** (`user-and-allies`) and the guard family
   (**WIDEGUARD, QUICKGUARD, CRAFTYSHIELD, MATBLOCK, SAFEGUARD**) — are
   single-battler-FUNCTIONAL (they boost/protect the user, who is the whole
   side in singles), so they are wiring targets in phases 15/22, not
   exemptions. **SNIPESHOT** is also not exempt: its `tracksTarget` half is
   moot in singles but its real `critRatio: 2` high-crit is handled by the
   native crit path, so it is already covered. **COACHING / DECORATE /
   FLOWERSHIELD / AROMATICMIST / TAKEHEART** were already mod-patched long
   before this phase, so they were never candidates.
2. The three Gen 1 "silently dead" suspects are resolved: **HAZE, MIST,
   CONVERSION, DESTINY BOND, GRUDGE, SPIDER WEB** are native base-engine
   effects (`gen2/Effects.lua`), and **FOCUS ENERGY / PSYCH UP / MIMIC** are
   native or otherwise present — none needs a phase. They are recorded as
   dead in `NATIVE_COVERAGE.md`.

The registry ships as `combat/structural_exemptions.lua`, booted by `main.lua`
as `structural_exemptions` (right after `corrosion`), exporting
`mod.exports.structuralExemptions` and `mod.exports.isStructurallyExempt(id)`.
Harness round 81 = 8 checks green (registry booted, helper exported, the six
known ids present, an ordinary move rejected, `nil` rejected, reason text
present, size pinned at 6, and — JS-side, where the move-patch recorder
lives — the exemption set disjoint from every patched move). The audit also
produced the residual-gap inventory below, which becomes phases 13-23.
132/132 subsystems, 0 failures; manifest 2.4.5 → 2.4.6.

**Residual backlog note:** the 156 moves the audit could not attribute to a
handler belong to phases 13-23 below. They were NOT in the original phase
list (which stopped at 12); the new sections were added in this round so the
backlog is preserved in the plan rather than living only in this doc.

## Phase 1 — Force/drag switch-out

**Closes:** **DRAGONTAIL, CIRCLETHROW** (Gen 5, `g2=EFFECT_NORMAL_HIT`;
ROAR/WHIRLWIND are already native `EFFECT_FORCE_SWITCH` and stay native).

**Primitive:** a target-directed drag, reusing the native forced-switch
machinery (bench pick, `forcedSwitch`, `clearVolatile`, trap/spike on
send) but **without** Gen 2's "user must move second" gate (real Gen 5+
rule: Dragon Tail drags regardless of order) and WITH the Suction Cups /
Guard Dog block. On a landed, non-zero damaging hit (so keep it
`kind="full"` + a `battle.damage_dealt` listener, the
`modern_switch_moves.lua` shape), request a bench pick on the *target's*
side.
**PS:** `moves.ts` `dragontail` (4209-4221)/`circlethrow` (2451-2463)
(`forceSwitch: true`); `battle-actions.ts` `forceSwitch` (1353-1366),
`getRandomSwitchable` (163), `canSwitch` (`battle.ts:1566-1584`);
`abilities.ts` `SuctionCups` (4693-4699), `GuardDog` (1728-1734).
**Files:** new `combat/modern_force_switch.lua`; edit `main.lua` boot
list.
**Harness:** drag replaces target; fails on a 1-mon side; Suction Cups /
Guard Dog holder is not dragged; Gen 1 inert.

**STATUS: DONE (round 69).** Shipped as `combat/modern_force_switch.lua`,
booted in `main.lua` right after `modern_switch_moves`. Implementation
notes where the shipped code diverges from the plan above: (1) the
Suction Cups / Guard Dog / Ingrain block lives in the new file's own
`dragBlocked` (and `mod.exports.dragBlocked` is exported), **not** in
`abilities/engine/prevent_misc.lua`'s `FORCE_SWITCH_MOVES` table —
that wrap cancels the *whole move*, which is correct for the status
moves Roar/Whirlwind but wrong for a damaging one, where only the drag
is cancelled and the damage still lands. (2) The enemy pick uses
`battle:switchMonAtSide` with a random bench index directly rather than
`getRandomSwitchable`, matching the native Gen 2 random drag
(`base-gen2-Battle.lua:2963`); the player pick reuses
`mod.exports.requestSwitch`. (3) Substitute deliberately does not block
(only Dynamax/Commanded/Commanding define `onDragOut` in
`conditions.ts`). Harness round69 = 13 checks green.

## Phase 2 — Stat-stage and stat-source manipulation

**Closes:** **POWERSWAP, GUARDSWAP, HEARTSWAP, SPEEDSWAP** (swap the two
active mons' stage pair), **POWERSPLIT, GUARDSPLIT** (average the pair of
raw stats for both mons), **POWERSHIFT** (swap the *user's* own Atk ↔ SpA
base stats), **STRENGTHSAP** (target Atk −1, user Atk +that amount),
**TOPSYTURVY** (invert every stage on the target), **SHELLSMASH,**
**SPICYEXTRACT, SYRUPBOMB, ACUPRESSURE**.

**Primitive:** a real stage read/write pair (`modern_combat.lua`'s store
for atk/def/spa/spd, `mon.stages` / `battle.stages[side]` for
speed/acc/eva) and a raw-stat read. Most of these are plain stage deltas
that could have gone through `modern_movepool_stages.lua`'s `primary()`/
`secondary()` helpers — the ones that need a new primitive are the
swaps/splits/Shift/Topsy.
**Files:** new `combat/modern_stat_manipulation.lua`; extend
`modern_movepool_stages.lua` registration helper if a shared
"apply stage on a chosen mon" entry is wanted.
**PS:** `moves.ts` entries for each; `pokemon.ts` `powerswap` family (the
stage swap is on `self`/`target`), `powershift` (`setAbility`-style base
stat swap), `topsyturvy` (negate each stage).
**Harness:** swap/split round-trips, Shift idempotence, Topsy sign flip,
Strength Sap healing clamped to the real HP restored.

**STATUS: DONE (round 70).** Shipped as
`combat/modern_stat_manipulation.lua`, booted in `main.lua` right after
`modern_movepool_stages`. Thirteen effect ids
(`GALAR_POWERSWAP_EFFECT`, `GALAR_GUARDSWAP_EFFECT`,
`GALAR_HEARTSWAP_EFFECT`, `GALAR_SPEEDSWAP_EFFECT`,
`GALAR_POWERSPLIT_EFFECT`, `GALAR_GUARDSPLIT_EFFECT`,
`GALAR_POWERSHIFT_EFFECT`, `GALAR_STRENGTHSAP_EFFECT`,
`GALAR_TOPSYTURVY_EFFECT`, `GALAR_ACUPRESSURE_EFFECT`,
`GALAR_SYRUPBOMB_EFFECT`, `GMAX_SHELLSMASH_EFFECT`,
`GMAX_SPICYEXTRACT_EFFECT`) are wired through `main.lua`'s
`CUSTOM_EFFECT_PATCH`. Implementation notes where the shipped code
diverges from the plan above:

1. **Shell Smash and Spicy Extract run through a bespoke `run` in this
   file, not `modern_movepool_stages.lua`'s `primary()` helper.** Both are
   ordinary ordered multi-stat sets, but the shared helper's Gen 2 return
   value is discarded by the engine's dispatch, so going through it would
   print nothing on Gen 2. The new file applies them through the exported
   `changeStage` (per-change direction: an ally-targeted +2 like Spicy
   Extract's Atk is `fromEnemy=false`, the -2 Def is `fromEnemy=true`),
   which keeps every real message tier and ability reaction.
2. **`accuracyChecked` is set ONLY for Strength Sap** (its real 100-accuracy
   move). Every other move here is self-targeted or a Showdown
   `accuracy: true` never-miss move, and a national_dex `accuracy=0` with
   `accuracyChecked=true` would make Gen 1 roll against a threshold of ~0.
   (This is a real latent bug in `modern_movepool_stages.lua`'s generic
   `primary()`, which sets `accuracyChecked = targetDirected or nil`, for
   target-directed moves with `accuracy=0` — CONFIDE, DECORATE, PLAY NICE;
   Gen 2 is unaffected because its roll happens after the run dispatch.
   Flagged to the user, not fixed this round.)
3. **Acupressure is deliberately NOT Substitute-blocked.** Showdown's own
   `substitute` condition `onTryPrimaryHit` returns early when
   `target === source` (moves.ts:18340-18354), so a self-targeting move
   bypasses its own Substitute. The `substituteBlocks` guard is therefore
   applied only to the target-directed moves (Power/Guard Split,
   Topsy-Turvy, Strength Sap, Spicy Extract), matching each one's real
   `bypasssub` flag; the swap family (Power/Guard/Heart/Speed Swap) has no
   `bypasssub` but is target-directed and IS gated.
4. **A protected boss (`bossFightHas(battle, "statsDrop")`) refuses the
   whole direct-write effect** when any enemy-side mon would be worsened,
   the same rule Clear Smog already established — a swap/split/Topsy can
   never desync the two sides by half-applying.
5. **Power Shift's state lives directly on the mon** (`powerShiftActive` /
   `powerShiftPre`), reverted by this file's own `battle.battler_switched`
   and `battle.ended` listeners (`mod.exports.revertPowerShift` exported) —
   NOT in `status_condition_cleanup.lua`'s `SWITCH_SCOPED`, because a plain
   nil-out there could not swap the raw stats back. **Syrup Bomb's
   `syrupBombTurns`/`syrupBombSource` WERE added to `SWITCH_SCOPED`** (a
   noCopy volatile), alongside the file's own source-on-field residual.
6. **Gen 2 native speed/accuracy/evasion writes route through
   `Battle:changeStageAgainstMist`** (which emits its own message and
   respects Mist); the mod store only ever holds atk/def/spa/spd. Raw
   swaps/splits read/write `storedStats` directly (NOT `rawStat`, which
   applies Wonder Room's key swap); Gen 2's spa/spd writes also mirror onto
   the native `specialAttack`/`specialDefense` keys.

Harness round70 = 35 checks green (plus the JS-side 13-move patch check);
every earlier round stays green; 123/123 subsystems, 0 failures.

## Phase 3 — Critical-hit overrides

**Closes:** **LASERFOCUS** (next damaging move always crits),
**WICKEDBLOW, SURGINGSTRIKES, FROSTBREATH, STORMTHROW, FLOWERTRICK**
(always-crit, plus Flower Trick's sure-hit).

**Primitive:** a `forceCrit`/`alwaysCrit` path in the damage formula
(the crit roll already exists in `modern_combat.lua`; add an explicit
override that bypasses the roll, and let Laser Focus set a one-shot
`laserFocus` volatile consumed by the next damaging hit).
**Files:** new `combat/modern_crit_override.lua`; tiny hook in
`modern_combat.lua`'s crit computation; `main.lua` patch map.
**PS:** `moves.ts` `wickedblow`/`surgingstrikes`/`frostbreath`/
`stormthrow`/`flowertrick` (`willCrit: true`), `laserfocus` volatile.
**Harness:** forced crit lands through a crit-immune target only where
real (Battle Armor/Shell Armor still block — real rule), Laser Focus is
consumed by the next damaging move and not by a status move.

**STATUS: DONE (round 71).** Shipped as `combat/modern_crit_override.lua`,
booted in `main.lua` right after `modern_stat_manipulation`. The five
always-crit moves are recognised from national_dex's own `critRate = 6`
sentinel (no move-id list) and the effect-level pieces
(`GALAR_LASERFOCUS_EFFECT`) are wired through `main.lua`'s
`CUSTOM_EFFECT_PATCH`. Implementation notes where the shipped code
diverges from the plan above:

1. **The always-crit override is NOT a new `forceCrit` seam bypassing the
   roll.** It rides `modern_combat.lua`'s existing crit **stage** modifier
   chain (`registerCritStageModifier`): a `critStageModifiers` entry
   returns +3 when `move.alwaysCrit`, which the existing clamp/denominator
   table resolves to `CRIT_STAGE_DENOM[3] = 1` — a guaranteed crit through
   exactly the same path every high-crit move already uses. Keyed off
   `move.alwaysCrit`, which `main.lua`'s `wireMovepoolSubEffects` patches
   for `critRate >= 6` (Showdown's `willCrit`), replacing the old
   `highCrit` mapping for that sentinel.
2. **`modern_combat.lua` now threads the defender into the crit ctx on
   BOTH call shapes** (the `battle.crit` hook call and the direct
   `modernCritRoll` fallback). Before this round the tables omitted
   `target`, so `modernCritRoll`'s Battle Armor / Shell Armor check
   (`CRIT_IMMUNE_ABILITY`) read `ctx.target == nil` and never fired on the
   modern path — a pre-existing latent bug this round closes, so a
   guaranteed crit is still correctly negated by a crit-immune holder
   (Showdown runs the `CriticalHit` event even for `willCrit` moves).
3. **Laser Focus is Showdown's real `duration = 2` volatile, not the
   plan's "one-shot consumed by the next damaging move."** `moves.ts`
   `laserfocus` (10013-10044) grants crit-ratio 5 (`onModifyCritRatio`)
   for two turns; implemented as a direct switch-scoped field
   (`laserFocusTurns`) whose `battle.turn_ended` listener decrements it,
   and a second `critStageModifiers` entry grants +3 while it is set. Its
   `onEnd` is `[silent]`, so it expires with no message.
4. **Flower Trick's Showdown `accuracy: true` is a `sureHit` flag** (a
   `critRate >= 6` move whose dex accuracy is 0), honoured by a
   `battle.accuracy` hook wrap (priority 45). Gen 2 already treats a
   non-positive dex accuracy as never-miss, so this is a no-op there — it
   exists because Gen 1's percent-domain threshold turns `accuracy = 0`
   into a ~255/256 miss (the same class of latent bug flagged in phase 2
   note 2, below).
5. **`laserFocusTurns` was added to `status_condition_cleanup.lua`'s
   `SWITCH_SCOPED`** — the real volatile is switch-scoped, so a switch-out
   must clear it.

Harness round71 = 13 checks green (plus the JS-side 6-move patch check);
every earlier round stays green; 124/124 subsystems, 0 failures.

**Pre-existing bug found, flagged, NOT fixed this round:**
`modern_movepool_stages.lua`'s generic `primary()` sets
`accuracyChecked = targetDirected or nil`, so a target-directed move with
national_dex `accuracy = 0` (CONFIDE, DECORATE, PLAY NICE) misses ~255/256
on Gen 1. Gen 2 is unaffected (its accuracy roll happens after the run
dispatch). Same root cause as phase 2 note 2; awaiting a user decision.

## Phase 4 — Damage-stat source overrides

**Closes:** **FOULPLAY** (uses the target's Attack stat),
**BODYPRESS** (uses the user's Defense as Attack),
**PSYSHOCK / SECRETSWORD** (damage off Defense when the move would be
special; Secret Sword may already be covered — verify).

**Primitive:** an attacker-stat / defender-stat substitution seam in the
damage formula, next to the existing Unaware stage zeroing.
**Files:** new `combat/modern_damage_source.lua`; small hook in
`modern_combat.lua`.
**PS:** `moves.ts` `foulplay` (`useSourceDefenseMod`/`onModifyAtk` →
target's Atk stage-included), `bodypress` (`onModifyAtk` → user Def).
**Harness:** Foul Play scales with the *target's* Attack boosts, not the
user's; Body Press scales with the user's Defense.

**STATUS: DONE (round 72).** Shipped as `combat/modern_damage_source.lua`,
booted in `main.lua` right after `modern_crit_override`. The primitive is a
new `modern_combat.lua` seam, `registerDamageSourceOverride(id, fn)`,
consulted in `computeModernDamage` right after the category/Psychock
stat selection; each shipped move is registered by id (like Showdown's own
`overrideOffensiveStat`/`overrideOffensivePokemon` move-data properties).
Implementation notes:

1. **Psyshock / Psystrike / Secret Sword were already covered** inline in
   `modern_combat.lua` (`overrideDefensiveStat: 'def'`) — verified, not
   re-registered here. Only Body Press and Foul Play needed the new seam.
2. **The override moves BOTH the raw stat read and the stat-stage read.**
   `computeModernDamage` now reads the offensive stat from `atkMon` (the
   user, or the target for Foul Play) and its stage from that same mon's
   bucket, matching Showdown's
   `attacker.calculateStat(attackStat, attacker.boosts[attackStat], ...)`
   (battle-actions.ts:1710-1711). The Unaware checks were re-based on the
   effective `atkMon`/`defMon` for the same reason.
3. **Burn was re-keyed from `atkStat == "attack"` to `not special`.** Real
   Showdown halves a burned Physical move's damage at the END of the
   formula (battle-actions.ts:1816), independent of which stat was read, so
   the user's burn must still halve Body Press (Physical, reads Defense);
   Special moves are untouched, as before.
4. **The held-item user branch now takes the move's CATEGORY stat**
   (`atkEventStat`), matching Showdown's ModifyAtk/ModifySpA events
   (battle-actions.ts:1713), so an unconditional Choice Band still boosts
   Body Press (`modern_held_items_phase2.lua`'s
   `applyHeldItemStatMultiplier` gained an optional 8th arg, defaulting to
   the old behaviour so every non-overridden move is byte-identical).

Harness round72 = 8 checks green; every earlier round stays green;
125/125 subsystems, 0 failures.

**Harness-stub fix (not a mod change):** the fengari harness stubbed both
`src.pokemon.Stats.applyStage` and `src.battle.gen2.Damage.applyStage` as
identity, which made any stage-included damage read untestable. Both now
implement the real Gen-3+ stage multiplier ((2+stage)/2 positive,
2/(2−stage) negative, floored, min 1). All prior rounds stayed green.

## Phase 5 — Action order and chosen-move visibility

**Closes:** **SUCKERPUNCH** (fails unless the target chose a damaging
move — needs chosen-action visibility), **UPPERHAND, THUNDERCLAP** (+priority
gated on the target's chosen move), **FAKEOUT** (first turn out only),
**FOCUSPUNCH** (fail if the user took damage this turn), **AFTERYOU**
(target acts next), **QUASH** (target acts last).

**Primitive:** expose the acting battlers' chosen `action.move` to
sub-effects (the `resolveTurnActions` contract already attaches the chosen
move to each battler); a re-order entry (After You/Quash) if the queue is
re-sortable, else honest-partial. Fake Out/Focus Punch only need flags
that already exist (`first turn out`, `counterTookThisTurn`).
**Files:** new `combat/modern_action_order.lua`; possibly a small export
from `turn_order.lua`.
**PS:** `moves.ts` `suckerpunch` (`onTry` reads `target.moveThisTurn`/
`getMove`), `upperhand`, `fakeout`, `focuspunch`, `afteryou`, `quash`.
**Harness:** Sucker Punch fails vs. a status-choosing target and lands
vs. an attacking one; Fake Out flinches only on switch-in turn; Focus
Punch fails after being hit; After You/Quash reorder or are documented
honest-partial if the queue is frozen.

**STATUS: DONE (round 73).** Shipped as `combat/modern_action_order.lua`,
booted in `main.lua` right after `modern_damage_source`, plus new seams in
`combat/turn_order.lua`. Primitive shape:

1. **Chosen-move visibility is published, not inferred.** `turn_order.lua`'s
   `resolveTurnActions` already had each actor's chosen `.move` on its
   `actingBattlers` entry, so it now builds
   `battle.__g9ChosenMoves[mon] = moveId` for the whole turn, clears the
   entry as each actor resolves (Showdown's "an acted mon is spliced out of
   the queue, `willMove` returns null"), and nils the map at turn end. The
   native single-actor path publishes the same map from
   `ctx.playerMove`/`ctx.enemyMove` via a `battle.turn_order` hook wrap, so
   `mod.exports.actionGateReason` works in both the scene and native flows.
2. **The fail gates wrap `Battle:useMove`**, exactly like
   `modern_combat_protect.lua` Part D: on failure, substitute
   `Battle.moveEffectRecordFor` for the duration of one native call so the
   move is still announced and its PP spent, then run a
   `{kind="primary", run=...}` record that calls `markMissed` and emits the
   failure line ("But it failed!" / "<name> lost its focus and couldn't
   move!"). `SUCKERPUNCH`/`THUNDERCLAP` fail unless the target is still
   queued with a non-Status chosen move (Me First exempt);
   `UPPERHAND` requires the target's chosen move to have strictly positive
   BASE priority; `FAKEOUT` requires it to be the user's first action
   since switch-in; `FOCUSPUNCH` fails after a move-owned damaging hit.
3. **After You / Quash are real reorders.** `turn_order.lua` gained
   `indexOfActorForMon` and `mod.exports.prioritizeActor`/`deprioritizeActor`
   built on a live `__g9OrderedActors` list + `__g9OrderIndex` cursor (the
   resolution loop was converted from `for ... ipairs` to an index-based
   `while` so moving a not-yet-visited actor can't perturb already-consumed
   entries; both `break`s preserved). After You patches the target to the
   next slot, Quash to the last.

Implementation notes / honest partials:

1. **Both reorders and all five gates only fire where chosen-move state
   exists.** In a scene-driven multi-battler turn that's every case; a plain
   native singles battle never has more than one active per side, so After
   You/Quash correctly fail there (`activeBattlerCount <= 2`), and the gates
   read the native-published map. There is no queue-freezing hack: the reorder
   only ever touches actors not yet visited.
2. **Upper Hand and Fake Out's own flinches are NOT re-implemented here.**
   Both national_dex records carry `flinchChance 100`, and `main.lua`'s
   existing generic `installMovepoolEffects` listener applies it after a
   landed hit; neither id is in `GENERIC_SECONDARY_EXEMPT`, so this file
   deliberately leaves that end to end with the shared path.
3. **Focus Punch keys off `__g9LostFocus`, set only by `battle.damage_dealt`
   entries that carry a `moveId`** — residual chip (burn/sand/hazards) does
   not trigger Showdown's `condition.onHit`, so it must not break the punch.
   This is deliberately distinct from `modern_combat.lua`'s broader
   `damagedThisTurn` (which includes residual for Assurance).
4. **Correction (round 92): the Fake Out gate's `> 1` was off by one.** This
   gate runs BEFORE native `useMove` emits `battle.move_used` (the same seam
   `modern_side_protection.lua`'s own FIRSTIMPRESSION gate documents), so
   `__g9MoveActions` holds COMPLETED actions only — Showdown's
   `activeMoveActions > 1` (moves.ts:5098) already counts the current action,
   making the faithful test `completed > 0`, exactly what First Impression
   used. The old `> 1` wrongly let Fake Out fire again on the second action
   since switch-in; fixed, with `round73`'s `fakeOut` pair and new `round92`
   seam checks pinning the completed-vs-including distinction.

**Harness-stub fix (not a mod change):** the fengari harness's
`src.battle.gen2.Battle` `useMove`/`sideOf` were inert JS stubs, so no
fail-gate record could ever dispatch and `move_targeting.lua`'s captured
`nativeSideOfMulti` was nil. Both are now real Lua leaves in the harness
(spend PP, announce "used X!", dispatch `Battle.moveEffectRecordFor`; binary
`sideOf`), which also let the round68 powder "move runs" cases assert their
true PP cost (1). All prior rounds stayed green.

Harness round73 = 43 checks green; every earlier round stays green;
126/126 subsystems, 0 failures.

## Phase 6 — Party recovery and sacrifice

**Closes:** **AROMATHERAPY, HEALBELL** (cure the whole party's status),
**JUNGLEHEALING** (user's side: heal + cure), **REFRESH** (self status),
**TAKEHEART** (self status + SpA/SpD +1), **WISH** (delayed half-max heal
next turn), **HEALINGWISH, LUNARDANCE** (user faints; heal the
replacement), **REVIVALBLESSING** (revive a fainted party member),
**LASTRESORT** (fail unless every other known move has been used),
**MEMENTO** (self-faint + target Atk/SpA −2), **DESTINYBOND, GRUDGE**
(faint-triggered).

**Primitive:** a whole-party iterator (`battle.party`/`battle.enemyParty`,
already used by Sweetness/Aromatherapy-shaped code in
`max_move_subeffects.lua`), `cureStatusOf`, a `party`-scoped revive, and
a per-mon used-moves set for Last Resort.
**Files:** new `combat/modern_party_support.lua`,
`combat/modern_faint_sacrifice.lua`.
**PS:** `moves.ts` `aromatherapy`/`healbell` (`onHit` side status clear),
`wish` (`slot.side.addSlotCondition('Wish')`), `healingwish`/`lunardance`
(`onTryHit` → healing wish side condition), `revivalblessing`,
`lastresort` (`onTry` checks `moveHistory`), `memento`, `destinybond`,
`grudge`.
**Harness:** Aromatherapy clears a benched mon's status; Wish heals the
mon in the slow slot next turn; Healing Wish heals the incoming mon;
Last Resort fails before and succeeds after the rest of the moveset.

**STATUS: DONE (round 74).** Shipped as `combat/modern_party_support.lua` +
`combat/modern_faint_sacrifice.lua`, booted in `main.lua` right after
`modern_action_order`, plus a reusable fail-gate seam exported by that file.
Primitive shape:

1. **`modern_party_support.lua` owns the shared party vocabulary** and
   exports it for the sibling file: `g9NameOf`, `g9RawMon`, `g9MaxHpOf`,
   `g9SidePartyOf`, `g9ActiveOf`, `g9AlliesAndSelf`, `g9HealFraction`,
   `g9HealAmount`, `g9CanSwitchOut`, `g9WishesOn`. "The party" is the real
   `battle.party`/`battle.enemyParty` array (the same arrays
   `modern_combat_protect.lua` and `max_move_subeffects.lua` already read for
   party-wide effects), and `alliesAndSelf` additionally folds in
   `requestAdjacency`'s allies so a scene-driven multi-battler turn is covered.
2. **Aromatherapy / Heal Bell** (`kind="primary"`, no `accuracyChecked`) walk
   the whole side (party + active roster) calling `cureStatusOf`, and fail with
   "But it failed!" when nobody had a status. **Jungle Healing** heals 25% and
   cures each ally, succeeding if either half landed. **Refresh** fails on
   no-status / Sleep / Freeze. **Take Heart** boosts SpA/SpD +1 then cures.
3. **Wish** is a per-side slot condition (`battle.__g9Wishes[side] = {hp,
   turns=2}`) resolved by a `battle.turn_ended` listener: the first end-of-turn
   pass decrements 2->1 with no heal (Showdown's `turn <= startingTurn` guard),
   the second (turn+1) decrements 1->0 and heals the CURRENT occupant by the
   stored flat half-max (`g9HealAmount`, not a fraction of the replacement's
   own max -- faithful to `slot.hp = source.maxhp/2`).
4. **Revival Blessing** fails when the side has no fainted member, else revives
   the first fainted party mon to half max and clears its status counters.
5. **`modern_faint_sacrifice.lua`** covers the self-KO family. Healing Wish /
   Lunar Dance fail (with no self-KO) when `g9CanSwitchOut` is false, else
   store `battle.__g9PendingHeal[side] = {restoresPp=...}` and drop the user to
   0 HP; a `battle.battler_switched` listener full-heals / clears the incoming
   mon (Lunar Dance also restores every move's PP). Memento drops Atk/SpA -2
   (`accuracyChecked=true`, so a miss cancels the whole move) then faints the
   user. Destiny Bond / Grudge arm a per-mon volatile (`g9VolatileOf`, i.e.
   `mon.volatile`) and read a `battle.damage_dealt` listener's
   `__g9LastMoveHit[target] = {user, moveId}` -- residual chip carries no
   `moveId`, so it can't arm the retribution -- then a `battle.fainted` listener
   takes the killer down / zeroes its PP, and a `battle.move_used` listener
   clears the volatile when the holder moves again.
6. **Last Resort** rides `modern_action_order.lua`'s reusable `registerFailGate`
   seam (newly exported this round) so it is announced, spends PP, and prints
   the shared failure line through the exact Sucker Punch path.

Implementation notes / honest partials:

1. **The 1v1 reduction of "slot" is "side".** Healing Wish / Lunar Dance store
   the pending heal per side (a doubles scene still keys by side, so the first
   switch-in on that side consumes it; a true per-slot queue would need the
   scene's slot ids). Wish likewise keys by side and always heals whoever is
   active when it resolves.
2. **Revival Blessing auto-picks the first fainted member** (there is no target
   picker for a party-revive); it clears `status`/`statusTurns`/`toxicCounter`
   alongside the half-max HP restore.
3. **Ability exemptions (Sap Sipper / Good as Gold / Soundproof on allyTeam
   moves) are not modelled** -- this engine's Aromatherapy / Heal Bell have no
   separate ally slot to reach in a 1v1 battle, exactly as the file header
   notes.
4. **Destiny Bond's retribution reuses the existing faint announce**: the HP
   write to 0 lets `turn_residuals.lua`'s `announceFaints` emit the real
   `kind="faint"` text and `battle.fainted` runtime event, so only the "took
   its attacker down with it!" line is added here.
5. **Volatiles are read/written through `g9VolatileOf(mon)` (the mon's own
   table) rather than `battle:volatile(mon)`.** `Battle:volatile` is literally
   `mon.volatile = mon.volatile or {}; return mon.volatile`, so this is
   identical -- but the faint/move_used listeners run on every battle in the
   engine, including minimal scene stubs, and the direct accessor can't trip a
   nil-method error there.

Harness round74 = 48 checks green; every earlier round stays green;
128/128 subsystems, 0 failures.

## Phase 7 — Side conditions, screens and hazard manipulation

**Closes:** **COURTCHANGE** (swap both sides' side conditions — hazards +
screens together), **BRICKBREAK** (remove the target's screens),
**DEFOG** (clear the target's hazards + screens, −1 evasion self in
modern gens), **MAGICCOAT** (bounce a status move back), **SNATCH**
(steal a status move), **IMPRISON** (target can't use shared moves).

**Primitive:** read/write both sides' hazard store
(`modern_hazards.lua`'s `hazardsFor`) and screens
(`battle:screenActive`), a status-move interception (the proven
`Battle:useMove` class wrap in `modern_combat_protect.lua` Part D), and
an "imprisoned" volatile checked in `usableMoves`.
**Files:** new `combat/modern_side_conditions.lua`; extend
`modern_hazards.lua`; small hook in the move-availability gate.
**PS:** `moves.ts` `courtchange` (`swapSideConditions`), `brickbreak`/
`psychicfangs` (`onTryHit` → `side.removeSideCondition` screens),
`defog`, `magiccoat` (status-bounce flag), `snatch`, `imprison`.
**Harness:** Court Change swaps hazards both ways; Brick Break clears
Reflect/Light Screen; Magic Coat reflects a Toxic direction; Imprison
blocks a shared move.

**STATUS: DONE (round 75).** Shipped as `combat/modern_side_conditions.lua`,
booted in `main.lua` right after `modern_hazards` (it reads that file's
exported `hazardsFor` store and wraps `Battle:useMove` / `Battle:usableMoves`).
Primitive shape:

1. **`hazardsFor` is the one hazard store;** screens are the engine's own
   side-keyed `battle.screens[side] = { lightScreen, reflect, safeguard }`
   (`Battle.LINK_SCREENS`, gen2/Battle.lua:5389). Court Change, Defog and
   Brick Break all read/write those two stores plus the native
   `battle.spikes[side]` count.
2. **Court Change** (`kind="primary"`) lifts screens + spikes + the four
   mod hazards off both sides and swaps them; it fails with "But it
   failed!" iff nothing at all was present (Showdown's `if (!success)
   return false`).
3. **Brick Break / Psychic Fangs** get an empty `kind="full"` record (the
   Rapid Spin precedent -- a primary `run` would bypass the damage path,
   gen2/Battle.lua:1750-1755) and shatter the DEFENDER's reflect/lightScreen
   from inside the `Battle:useMove` wrap, *before* the native call -- so the
   move's own hit is not screened, exactly Showdown's `onTryHit` ordering.
4. **Defog** (`kind="primary"`) lowers the target's evasion (skipped behind
   a Substitute), clears the target side's screens + all hazards, clears the
   user side's hazards, and clears the terrain (mirroring
   `modern_terrain.lua`'s own end text + `g9.terrain_changed` event).
5. **Magic Coat / Snatch** are one-turn volatiles (`magiccoat` / `snatch`),
   armed by their records and consumed inside the `Battle:useMove` wrap:
   the opposing active's `magiccoat` bounces a `reflectable` move back
   (attacker/defender swapped, one-bounce guarded -- the exact shape
   `abilities/engine/magic_bounce.lua` already uses for the ability), and
   `snatch` steals a `snatch`-flagged self/field move (the thief becomes
   both user and target). A `battle.turn_ended` listener drops both
   volatiles after their turn (Showdown `duration 1`).
6. **Imprison** records the holder's move ids in a `volatile.imprison`
   (`+ imprisonMoves`) and filters them out of the FOE's `Battle:usableMoves`
   answer (the one seam both the player menu and the AI read).

Implementation notes / honest partials:

1. **Only the side conditions this engine actually models are swapped.**
   Showdown's list also names tailwind, auroraveil, luckychant and the
   pledge/G-Max side conditions. Phase 8 (`combat/modern_field_effects.lua`)
   added the first three to this same `battle.screens[side]` table, so Court
   Change now swaps them too; only the pledge/G-Max side conditions remain
   unmodelled.
2. **Mist is not swapped.** This engine models Mist as a per-MON volatile
   (gen2/Battle.lua:2043), not a side condition as Showdown stores it, so
   Court Change leaves it alone rather than faking a side-wide swap.
3. **Defog's `bypasssub`/infiltrates is not modelled** -- the evasion drop
   is simply skipped when the target is behind a Substitute, which is the
   same observable outcome for a non-infiltrating Defog. The terrain clear
   and every side clear still run.
4. **Snatch gates on national_dex's `snatch` move flag**, and only ever
   steals an OPPONENT's move (the `Battle:useMove` wrap keys off the
   opposing active mon), so a doubles ally's move is never taken.
5. **Imprison filters at the move-selection seam** (`Battle:usableMoves`)
   rather than also cancelling a move mid-turn; since both the player menu
   and `Ai.lua` resolve legal moves through that seam, the effective
   in-game restriction is identical.

Harness round75 = 30 checks green (Court Change's two-way swap + no-op
fail; Defog's four clears; Brick Break's pre-hit shatter + Safeguard kept;
Magic Coat bounce/redirect/no-bounce; Snatch steal/redirect/no-steal;
Imprison's block + self-exemption; the turn-end expiry), plus JS-side
`movePatches` for all seven phase-7 move repointings. Every earlier round
stays green; 129/129 subsystems, 0 failures.

## Phase 8 — Field effects (rooms, sports, global state)

**Closes:** **GRAVITY** (no Flying/Levitate grounding, accuracy ×5/3,
grounds everyone), **MAGICROOM** (items suppressed), **WONDERROOM**
(Def/SpD swapped), **IONDELUGE** (Normal → Electric for the turn),
**ELECTRIFY** (target's next move becomes Electric), **MUDSPORT /
WATERSPORT** (halve Fire/Electric power 5 turns), **NATUREPOWER**
(terrain-dependent), **POWDER** (target's Fire move explodes),
**TAILWIND** (double the side's Speed 4 turns), **AURORAVEIL** (screen,
hail-gated), **LUCKYCHANT** (no crits on the side), **FAIRYLOCK**,
**TEATIME**.

**Primitive:** a battle-scoped field state table (`modern_weather.lua` /
`trick_room.lua` are the models), plus reads in the damage formula
(Gravity accuracy, Mud/Water Sport power, Wonder Room stat swap) and in
the move-type resolution (Ion Deluge/Electrify/Nature Power).
**Files:** new `combat/modern_field_effects.lua`,
`combat/modern_rooms.lua`; small hooks in `modern_combat.lua`.
**PS:** `moves.ts` `gravity`, `magicroom`, `wonderroom`, `iondeluge`,
`electrify`, `mudsport`, `watersport`, `naturepower`, `powder`,
`tailwind`, `auroraveil`, `luckychant`, `fairyLock`, `teatime`.
**Harness:** Gravity grounds a Flying target and boosts low-accuracy
hits; Wonder Room swaps the defense read; Tailwind doubles the side's
effective Speed; Aurora Veil only lands in hail.

**STATUS: DONE (round 76).** Shipped as `combat/modern_field_effects.lua`,
booted in `main.lua` right after `modern_items` (it reads `modern_combat`'s
`normalize`/`currentWeather`/`registerDamageModifier`, `field_duration`'s
`resolveFieldDuration`, `modern_side_conditions`' own `battle.screens[side]`
table, and `modern_items`' newly-exported berry applier). The three ROOMS
were already shipped in `combat/trick_room.lua` (round 34) -- nothing was
redone there; Phase 8 only closed the remaining field effects around them,
so there is no separate `combat/modern_rooms.lua`.

Primitive shape:

1. **Whole-field state lives on the battle object** (`battle.gravityTurns`,
   `battle.mudSportTurns`, `battle.waterSportTurns`, `battle.ionDelugeTurns`,
   `battle.fairyLockTurns`), the convention `battle.weather` /
   `battle.trickRoomTurns` already use. The three SIDE-scoped effects
   (Tailwind / Aurora Veil / Lucky Chant) ride the engine's own
   `battle.screens[side]` table -- so Court Change, Defog and Brick Break in
   `modern_side_conditions.lua` reach them without a second store (Court
   Change now swaps Tailwind/Lucky Chant/Aurora Veil; Brick Break and Defog
   clear Aurora Veil).
2. **Durations** tick off the real `battle.turn_ended` (the same event
   weather/trick_room use), so the casting turn counts as the first. Every
   setter fails (Showdown's pseudoWeather/sideCondition add returning false)
   when the effect is already active.
3. **Type overrides (Ion Deluge / Electrify) and Powder** ride ONE
   class-level `Battle:useMove` wrap: the damage path reads the move's own
   `def.type`, so the override mutates that shared definition for exactly one
   synchronous native call and restores it inside a pcall -- there is no
   exported move-type seam. Powder spends the move's PP and announces
   "used X!" like a real blocked move, then deals `maxhp/4` and stops.
4. **Gravity's grounding** is published as `mon.gravityGrounded` and read by
   three existing groundedness checks (`modern_combat.lua`'s
   `resolvedTypeMult`, `modern_hazards.lua`'s `isGroundedForHazards`,
   `modern_terrain.lua`'s `isGrounded`) -- a separate flag from Smack Down's
   `groundedByMove`, so ending Gravity can never clear a genuine Smack Down.
5. **Damage modifiers** (`registerDamageModifier`): Mud/Water Sport weaken
   Electric/Fire (`1352/4096` -- transcribed exactly from Showdown, NOT the
   0.5 the one-line phase summary implied); Aurora Veil halves (skipped on a
   crit, and when the matching screen is already up).
6. **Lucky Chant** wraps the real `battle.crit` hook (the seam
   `modern_combat.lua:1620` already calls) and returns false -- Showdown's
   `onCriticalHit: false`.
7. **Tailwind** wraps `Battle:effectiveSpeed` (x2 for the side); **Fairy
   Lock** composes onto `trap_abilities.lua`'s own `Battle:switchLocked`
   wrap; **Nature Power** re-dispatches through `Battle:useMove` under
   `copyDepth` (the port's own Metronome/Mirror Move recursion guard).
8. **Tea Time** makes every active mon eat its held Berry using the mod's
   existing classification (`modern_items.lua`'s exported `knownBerries`)
   and its newly-exported `applyEatenBerryEffect`.

Honest partials:
1. **Gravity** does not cancel an in-flight Fly/Bounce/Magnet Rise/
   Telekinesis (those two-turn/volatile states are only partly modelled
   here); it does ground for Ground-move immunity, Spikes/Toxic Spikes/
   Sticky Web and terrain.
2. **Mud/Water Sport** use Showdown's real `1352/4096` (~0.33).
3. **Tea Time** eats only the mod's known berries (the item schema carries
   no `isBerry` flag).
4. **Electrify's** "target will move this turn" `onTryHit` gate and
   **Aurora Veil's** Infiltrator bypass are not modelled (no such flags in
   the damage ctx / move model here).

Fairy Lock was listed under both Phase 8 and Phase 9; it is DONE here, so
Phase 9's entry for it needs no further work.

Harness round76 = 38 checks green (records; Gravity's set/recast/Spikes
grounding/accuracy x5-3; Mud+Water Sport both ways + recast; Ion Deluge's
mutate-and-restore through the useMove wrap; Electrify's type; Powder's
detonation + plain-move no-op; Nature Power's terrain map + dispatch;
Tailwind's Speed doubling + recast; Aurora Veil's snow gate + halving +
Brick Break clear + Court Change swap; Lucky Chant's hook suppression;
Fairy Lock's switch block; Tea Time's berry eat + fail; the turn-end tick),
plus JS-side `movePatches` for all twelve phase-8 move repointings. Every
earlier round stays green; 130/130 subsystems, 0 failures.

## Phase 9 — Trapping additions

**Closes:** **BLOCK, JAWLOCK** (traps BOTH sides), **ANCHORSHOT,
SPIRITSHACKLE** (damaging trap), **OCTOLOCK** (trap + Def/SpD −1/turn),
**FAIRYLOCK** (no switches next turn for either side).

**Primitive:** the existing `GALAR_TRAP_EFFECT` (wrap/trap state) +
`battle.trappingTurns`, extended to apply to the *attacker* too for
Jaw Lock, and a per-turn Octolock residual.
**Files:** extend `main.lua`'s `CUSTOM_EFFECT_PATCH` + a new
`combat/modern_trap_moves.lua`; extend `turn_residuals.lua` for Octolock.
**PS:** `moves.ts` `block`, `jawlock` (`trapped` both), `anchorshot`,
`spiritshackle` (`onHit` `trap`), `octolock` (`volatiles.octolock`),
`fairylock`.
**Harness:** Block/SHACKLE trap; Jaw Lock traps user too; Octolock ticks
Def/SpD down each residual.

**STATUS: DONE (round 77).** Shipped as `combat/modern_trap_moves.lua`,
booted in `main.lua` right after `modern_field_effects`. Two moves beyond
the plan's own list were folded in because they are literally the same
mechanic and equally dead: **MEANLOOK** and **SPIDERWEB** are both left at
`effect = "EFFECT_NORMAL_HIT"` / `effectModeled = false` by national_dex
(registry_gen2.lua:460 and :711) exactly like Block, and share Block's own
Showdown `onHit`. FAIRYLOCK was closed by Phase 8, so it is untouched here.

Primitive shape:

1. **These are NOT `GALAR_TRAP_EFFECT`, and must not be.** Showdown's
   `trapped` volatile (conditions.ts:208-216) has no chip damage and no
   duration -- it only pins (`onTrapPokemon -> tryTrap`). That is genuinely
   different from `partiallytrapped` (conditions.ts:222-253, the 1/8-per-turn
   chip), which `GALAR_TRAP_EFFECT` already models through Gen 2's native
   `wrapCount`. Reusing it would hand a pin move an unearned per-turn chip.
2. **The pin IS the native field.** `Battle:switchLocked`
   (gen2/Battle.lua:4010-4013) and every other gate (TryPlayerSwitch's
   `.check_trapped`, `tryEnemyFlee`, `vanillaEnemySwitchOrItem`) read the
   OPPONENT's `volatile(...).trapsTarget`; the canonical setter is native
   `EFFECT_MEAN_LOOK` (:2884, `self:volatile(attacker).trapsTarget = true`)
   and `Battle:breakTrapsOnSend` (:4000-4005) clears it on a send. Writing
   that same field is the faithful port -- the pin follows the trapper, dies
   with it, and is cleared on a fresh send on the trapped side.
3. **Status pins (Mean Look / Block / Spider Web) use `kind="primary"`+`run`
   on one shared record `GALAR_TRAP_PIN_EFFECT`;** Octolock adds its own
   record for the residual. Both fail ("But it failed!") on a recast
   (Showdown's `addVolatile` returning false) and against a natural trapping
   immunity. The damaging pins (Jaw Lock / Anchor Shot / Spirit Shackle) get
   the empty `kind="full"` record (invisible to Gen 2's
   `handler(...); return` pre-emption, gen2/Battle.lua:1750-1755) plus a
   `battle.damage_dealt` listener -- the Rapid Spin precedent
   (combat/modern_hazards.lua:295-300). A Substitute soaks the hit inside
   `Battle:dealDamage` before that event fires, so a subbed target is never
   pinned for free.
4. **Ghost immunity is the real modern rule.** `pokemon.tryTrap`
   (pokemon.ts:1607-1611) -> `runStatusImmunity('trapped')` ->
   `dex.getImmunity('trapped')`: Ghost-types (Gen 6+) cannot be trapped. The
   status pins fail outright (Octolock's own `onTryImmunity` is literally
   this check); the damaging pins simply don't apply. `curTypesOf` is read
   nil-safely so a species record without live types cannot crash the path.
5. **Octolock's residual** is Showdown's `onResidualOrder: 14`:
   `{ def: -1, spd: -1 }` each end of turn while the source is still on the
   field and alive, else the volatile ends silently. The coat lives on the
   holder as direct fields (`octolockActive` / `octolockSource`), added to
   `status_condition_cleanup.lua`'s `SWITCH_SCOPED` list so a switch-out
   sheds it -- as does the Gen 1 `g9Trapped` marker.

Honest partials:

1. **Gen 1 has no switch gate at all.** There is no "can I switch" choke
   point upstream of `resolveSwitch` (abilities/engine/trap_abilities.lua's
   own header documents this), so the Gen 1 half records `g9Trapped` on the
   target and cannot refuse a switch -- the same honest gap GMAX.TERROR
   already carries (gigantamax/max_move_subeffects.lua:610-622).
2. **The native pin is one-directional per gate.** `switchLocked()` only
   answers "can the player switch" and reads the ENEMY's flag; the enemy-side
   gates read the PLAYER's flag. `trapsTarget` is a boolean per mon, so a
   multi-battler scene can only ever pin/extend the lead pair's own gates --
   the same 1v1 reduction the native engine itself has.
3. **Jaw Lock pins both directions but does not re-check `source.isActive`**
   on a later turn (Showdown's anchor shot / spirit shackle guard the
   `addVolatile` on `source.isActive` at the moment of the hit only); the
   native pin already dies with its holder via `breakTrapsOnSend`.

Harness round77 = 18 checks green (records; the pin + `switchLocked` gate +
recast fail; Ghost immunity; the Gen 1 marker; Octolock's set/residual
Def+SpD drop/recast fail/Ghost fail/source-gone silent end; Jaw Lock pinning
BOTH sides; Anchor Shot and Spirit Shackle pinning only the target; a
zero-damage event not pinning), plus JS-side `trapMovePatches` for all seven
phase-9 move repointings. Every earlier round stays green; 131/131
subsystems, 0 failures.

**Harness improvement (not a mod change):** round 77 needed the native
`trapsTarget` gate to be observable, but the harness's `Battle.switchLocked`
was an inert JS stub -- and Lua tables reach JS stubs as opaque pointers, so
a JS stub can never read `battle.player/enemy`. It is now a real Lua leaf
next to the existing `useMove`/`sideOf` leaves (gen2/Battle.lua:4010-4013),
and `Damage.isSpecial` was given to both `src.battle.Damage` and
`src.battle.gen2.Damage` (the real Gen 2 type-based split) so a
`battle.damage_dealt` listener that reaches `modern_movepool_counter`'s
`categoryOf` no longer logs a harness error. All prior rounds stayed green.

## Phase 10 — Ability-manipulation moves

**Closes:** **ROLEPLAY** (copy the target's ability), **SIMPLEBEAM**
(target → Simple), **DOODLE** (target's ability → the user's side),
**CORROSIVEGAS** (destroys the target's held ITEM — see the correction
below).

**Primitive:** `mod.exports.setAbility` (already battle-only,
boss-immune), the same seam `modern_ability_change_moves.lua` uses for
Skill Swap/Worry Seed/Entrainment/Gastro Acid.
**Files:** extend `combat/modern_ability_change_moves.lua`;
`combat/modern_items.lua` (Corrosive Gas); `main.lua` patch map.
**PS:** `moves.ts` `roleplay`, `simplebeam`, `doodle`, `corrosivegas`.
**Harness:** Roleplay copies and restores on switch-out; Corrosive Gas
nulls the target's ability; Doodle copies within the target's side.

**PLAN CORRECTION (found while transcribing):** the original Phase 10
line read "CORROSIVEGAS (target loses its ability)" — that is WRONG.
`moves.ts:2914-2934` is `onHit(target, source) { const item =
target.takeItem(source); ... }`, a Status move that DESTROYS THE
TARGET'S HELD ITEM and has nothing to do with abilities. It is therefore
implemented in `combat/modern_items.lua` beside Knock Off / Thief /
Covet, not in the ability file, and patched by that file directly.

**STATUS: DONE (round 78).** Shipped in `combat/
modern_ability_change_moves.lua` (Role Play / Simple Beam / Doodle) and
`combat/modern_items.lua` (Corrosive Gas), with ROLEPLAY/SIMPLEBEAM/
DOODLE added to `main.lua`'s `CUSTOM_EFFECT_PATCH` and CORROSIVEGAS
patched directly. Implementation notes where the shipped code diverges
from the plan / the earlier assumption:

1. **The old single `UNCHANGEABLE = { MULTITYPE }` table is gone.** Its
   header assumed the engine built none of Showdown's exotic
   ability-flag abilities; it does (ability_copy, damage_immunity,
   form_change_scope, form_combat_effects, forecast_weather,
   multitype_switchin, neutralizing_gas, stat_immunity, stat_multiplier,
   switch_priority_misc, truant). The file now carries the four real,
   per-move Showdown flag sets, each restricted to the ids this engine
   actually builds: `FAIL_ROLEPLAY` (Role Play / Doodle's target),
   `CANT_SUPPRESS` (Worry Seed / Simple Beam / Gastro Acid / Entrainment's
   target / Role Play's source), `FAIL_SKILLSWAP` (Skill Swap),
   `NO_ENTRAIN` (Entrainment's source). This is the faithful split --
   Skill Swap now fails on a `cantsuppress`-only ability (Gulp Missile)
   it previously ignored, and Entrainment now fails on a `noentrain`
   source (Flower Gift, Forecast, Imposter, ...) it previously ignored.
2. **Skill Swap no longer fails on two identical abilities.** Showdown's
   `battle.ts:1320` only enforces that in `gen <= 5`; Gen 9 (this mod's
   mechanics generation) allows it. Documented, not a regression.
3. **A real Gen 2 message bug is fixed.** The four pre-existing handlers
   returned `{ Strings(...) }` — but Gen 2's dispatch discards a run
   handler's return value (the `combat/SUBEFFECTS.md` rule), so Skill
   Swap / Worry Seed / Entrainment / Gastro Acid silently printed NOTHING
   in-game. All handlers now route through the same `finish()` helper
   Phase 2's `modern_stat_manipulation.lua` established (Gen 2 emits each
   line, Gen 1 returns the list). Corrosive Gas does the same inline.
4. **Corrosive Gas is a status move** so it uses `kind="primary"`+`run`
   (the `.run`-preempts-damage gotcha only bites damaging moves); it
   reuses `modern_items.lua`'s `itemOf` / `isUnremovable` (Mail) / Sticky
   Hold checks verbatim, and fails ("But, it failed!") when the target
   holds no removable item.
5. **Doodle's `alliesAndSelf()` loop reduces to the user in 1v1** (there
   is no second ally slot), exactly as its own `adjacentFoe` target
   archetype and this engine's singles reduction allow; the skip rules
   (already-has-it, `cantsuppress`) and the fail-when-nothing-changed
   behaviour are kept.

Harness round78 = 23 checks green (records; Role Play copy/same/failroleplay/
source-cantsuppress; Simple Beam set/Simple/Truant/cantsuppress; Doodle
copy/same/target-failroleplay/source-cantsuppress; Corrosive Gas removal /
no-item / Sticky Hold / Mail; and the per-move flag-set gates on Skill Swap /
Worry Seed / Entrainment / Gastro Acid), plus JS-side `amMovePatches` for all
four phase-10 move repointings. Every earlier round stays green; 131/131
subsystems, 0 failures.

## Phase 11 — Ability gaps close-out

**Closes (documented gaps in the mod's own comments):**

- **CORROSION** — holder's Poison moves poison Steel/Poison. The old
  deferral ("status APIs never see the attacker") is stale: the generic
  listener in `main.lua` *does* have the attacker, so gate the
  Steel/Poison immunity there on `abilityIdOf(user) == "CORROSION"`.
- **POISONPUPPETEER** — holder's poison also confuses (Pecharunt-only,
  read the base species).
- **KLUTZ** — a passive held-item suppression primitive (Leftovers, Quick
  Claw, King's Rock...), i.e. a real item-effect gate, not just the Fling/
  Recycle gate that exists.
- **UNAWARE** — the accuracy half (ignore the target's evasion stage when
  the holder attacks).
- **MOLD BREAKER** — extend the existing per-ability bypasses into a
  general "attacker ignores the defender's ability" primitive.
- **SHEER FORCE** — the +30% damage half (the secondary-suppression half
  already exists in `main.lua`).
- **damage_immunity.lua** — the Gen 2 sand-chip half for Magic Guard
  (`Gen2Effects.sandstormDamage`).
- **switchin_stat_change.lua** — the native-store stats gap for
  SUPERSWEETSYRUP and kin.
- **Keen Eye / Illuminate** — the accuracy/evasion immunity family on the
  gen-native accuracy path (the same gap the mod's comments name).

**Files:** `abilities/data/corrosion.lua` (un-defer), `inflict_status.lua`,
`klutz.lua`, `unaware.lua`, `mold_breaker.lua`, `damage_multiplier.lua`,
`abilities/engine/damage_immunity.lua`, `switchin_stat_change.lua`,
`modern_combat.lua`.
**Harness:** one check per ability; verify boss-fight immunity still
applies to every new hostile trigger.

**STATUS: DONE (round 79).** Shipped across `combat/modern_combat.lua`
(three new shared primitives), `main.lua` (the generic secondary
listener), `abilities/engine/{inflict_status,type_immunity,damage_immunity,
accuracy_multiplier}.lua`, `combat/{modern_combat_protect,modern_items}.lua`,
and the matching `abilities/data/*` markers. Implementation notes where the
shipped code diverges from the plan above:

1. **SHEER FORCE's +30 % damage half was ALREADY built.** The plan listed
   it as a gap, but `abilities/engine/damage_multiplier.lua:567`
   (`sheer_force_damage_half`, registered 90) already multiplies a
   SHEERFORCE holder's move by 1.3, and `main.lua:298` already suppresses
   SHEERFORCE/SHIELDST-flagged secondaries. Nothing new was written -- the
   stale "gap" comments in `damage_multiplier.lua` /
   `abilities/data/damage_multiplier.lua` were corrected instead.
2. **The SUPERSWEETSYRUP / native-store stats gap was already closed in an
   earlier round** -- `switchin_stat_change.lua` was not re-touched here.
3. **CORROSION is un-deferred, not a new file.**
   `abilities/data/corrosion_deferred.lua` was renamed to
   `abilities/data/corrosion.lua` (boot name `"corrosion"`, `main.lua`
   boot list updated) -- the old "status APIs never see the attacker"
   deferral was stale because `main.lua`'s generic secondary listener
   *does* have the user.
4. **Three shared primitives now live in `combat/modern_combat.lua`:**
   `attackerIgnoresDefenderAbility(user)` (the `MOLD_BREAKER_FAMILY` =
   MOLDBREAKER / TERAVOLT / TURBOBLAZE table),
   `statusTypeImmune(battle, mon, canonical)` (Fire never burns; Poison /
   Steel are never poisoned -- Showdown `sim/pokemon.ts` `setStatus` ->
   `runStatusImmunity`, with the `tox` -> `psn` normalization), and
   `corrosionPiercesPoison(user)` (a plain **source-ability** check, per
   Showdown's `source?.hasAbility('corrosion')` -- the real code keys off
   the *inflicting source's* ability, not the move's type). All three are
   exported, so every mod-owned infliction site shares one copy.
5. **The type-immunity check is applied at both status-application seams**:
   `abilities/engine/inflict_status.lua`'s `inflict` (all four call sites
   now pass the real `source`) and `combat/modern_combat_protect.lua`'s
   contact-shield riders (Baneful Bunker / Burning Bulwark), which
   previously carried their own inline type check.
6. **Poison Puppeteer** rides that same generic listener: Pecharunt only
   (`source.species.id === 'pecharunt'`), target != user, gated on a
   confusion-immunity check, and only fires when the poison actually
   landed (so a Steel target still gets nothing unless Corrosion pierced).
7. **Klutz is a real held-item suppression gate** in
   `combat/modern_items.lua`'s existing `held_item.trigger`
   `mod.hooks:wrap`: a holder with abilityIdOf == "KLUTZ" returns
   `nil, 0`, which answers the engine's single chokepoint for **all eight**
   trigger kinds (residual/consume/... ) at once. Honest partial: this
   suppresses trigger-driven item effects (Leftovers, Quick Claw, King's
   Rock, berries, ...), not an item's own passive stat read
   (`itemBoostPercent`) -- that native held-item path is Phase 12.
8. **Mold Breaker is now one primitive, not scattered checks.**
   `abilities/engine/type_immunity.lua` (all type-immunity abilities) and
   `abilities/engine/damage_immunity.lua` (Wonder Guard AND the
   Bulletproof / Soundproof / Wind Rider `FLAG_IMMUNITY` set) both call
   `attackerIgnoresDefenderAbility(ctx.user)`, so a Mold Breaker /
   Teravolt / Turboblaze attacker now bypasses the same set the real
   ability does.
9. **The accuracy / evasion family lives in
   `abilities/engine/accuracy_multiplier.lua`.** Sand Veil (x0.8 in sand),
   Snow Cloak (x0.8 in snow) and Tangled Feet (x0.5 while confused) are
   registered as `evasionAbilityModifier`s that read the defender's own
   evasion stat, matching Showdown's `onModifyAccuracy` shape. The
   ignore-evasion half (Keen Eye / Illuminate / Mind's Eye on the
   attacker, Unaware on the defender) temporarily zeroes the relevant
   Gen 2 `battle.stages[side].evasion` / `.accuracy` around the native
   accuracy roll and restores it afterwards (pcall-wrapped), which is the
   only way to ignore the *stage* the native `vanillaAccuracyRoll` reads
   fresh.
10. **Magic Guard's Gen 2 sand chip** closes
    `abilities/engine/damage_immunity.lua` by replacing `Battle:tickWeather`
    (the native function is captured and delegated to for every non-sand
    weather, so the sand path is the only one reproduced), gating the
    per-mon chip on `SAND_CHIP_IMMUNE_ABILITY` = { SANDFORCE, SANDRUSH,
    SANDVEIL, MAGICGUARD, OVERCOAT }. The type gate
    (`Gen2Effects.sandstormHits`) and the fraction
    (`Gen2Effects.sandstormDamage`) still come from the engine, so only the
    immunity decision is the mod's.

**Harness-stub note:** round 79 exposed a robustness gap in the new
`statusTypeImmune` -- with a mock battle that isn't the real Gen 2 Battle
class, `isGen2Battle(battle)` is false and the type read came back empty.
The helper now derives the gen2 flag the same way
`modern_combat.lua`'s own immunity-negation path already does
(`isGen2Battle(battle) or monLooksGen2(mon)`), so a bare mon still reads
`.types`. Round 32's Baneful Bunker / Burning Bulwark type-immunity checks
(the original regressions) went back green.

Harness round79 = 25 checks green (the three primitives; Corrosion's
steel-blocked vs. corrosion-lands listener pair; Poison Puppeteer +
species guard; Klutz suppression + non-Klutz passthrough; the Mold Breaker
primitive; Sand Veil / Snow Cloak / no-weather / Tangled Feet accuracy
values; Keen Eye's evasion-ignore + restore, the plain-move control, and
Unaware's accuracy-ignore + restore; Magic Guard's sand chip). Every
earlier round stays green; 131/131 subsystems, 0 failures.

## Phase 12 — Items, held-item and terrain residue

**Closes:** `modern_held_items_phase2.lua` never reading `heldEffect`/
`itemBoostPercent` (native held-item path); the Toxic Spikes Levitate
exemption (the ability system now exists, so the "no abilities yet"
deferral is stale); the Misty Terrain confusion gap; the
`type_override_primitives.lua` `isDynamaxed` export TODO.

**Files:** `combat/modern_held_items_phase2.lua`, `combat/modern_hazards.lua`,
`combat/modern_terrain.lua`, `combat/type_override_primitives.lua`.
**Harness:** native `heldEffect` items observed; Levitate mon is not
poisoned by Toxic Spikes; Misty Terrain blocks confusion.

**STATUS: DONE (round 80).** Two of this phase's four original bullets were
already closed by earlier work before this round, so only the two genuinely
open ones were wired:

1. **The Toxic Spikes Levitate exemption was ALREADY CLOSED** (2026-08-27):
   `combat/modern_hazards.lua`'s shared `isGroundedForHazards` carries
   `GROUND_IMMUNE_ABILITY = { LEVITATE = true, EELEVATE = true }` and is
   consulted by the Toxic Spikes switch-in resolution, so a Levitate /
   Eelevate mon is no longer poisoned by it. The plan's "no abilities yet"
   deferral note was stale. Nothing to do.
2. **The `modern_held_items_phase2.lua` `heldEffect`/`itemBoostPercent`
   bullet was ALREADY CLOSED** by that file's own earlier pass:
   `computeModernDamage` replaces the native damage computation and never
   reads the native fields, so the type-boost family (the only real
   `itemBoostPercent` contributors) is re-implemented on the live
   `registerDamageModifier` chain (`held_item_type_boost`, priority 90),
   Scope Lens moved to `registerCritStageModifier`, and
   Light Ball / Thick Club / Metal Powder live in
   `applyHeldItemStatMultiplier`. Nothing to do.
3. **Misty Terrain now blocks the generic confusion secondary.** Root
   cause: `main.lua`'s generic secondary listener wrote
   `battle:volatile(target).confuseCount` directly instead of calling
   `Battle:applyConfusion`, so `combat/modern_terrain.lua`'s Misty wrap --
   which intercepts exactly that dotted entry point -- never saw it. Both
   that branch AND Poison Puppeteer's confusion now route through
   `battle:applyConfusion(target, nil, user)` (the direct write is kept only
   as a fallback for a minimal battle stub with no such method), with `user`
   as the inflicting source so the native Safeguard cross-side check still
   applies. Strictly-more-correct side effects: confusion now also honours
   Substitute, the held `HELD_PREVENT_CONFUSE` item and the native
   already-confused guard, and it prints the real "became confused!" text.
4. **The `type_override_primitives.lua` `isDynamaxed` TODO is CLOSED.**
   battle_forms still exports no active-Dynamax query -- but it does not
   need to: this mod's OWN `gigantamax/dynamax_battle.lua` stamps
   `mon.__g9Dynamaxed = true` on battle_forms' `dynamax_applied` event and
   clears it on `dynamax_reverted` (dynamax_battle.lua:109/134), keyed on
   the live mon identity. `canChangeType`'s `viaOpponent` branch now returns
   false when that marker is set (probing both the raw mon and a Gen 1
   battler wrapper's `.mon`), so Soak / Magic Powder targeting a Dynamaxed
   mon fails as the real Gen 8+ rule requires. Self-directed type changes
   are unaffected (the real asymmetry).

**Harness fix (not a mod change):** the fengari harness had no
`Battle:applyConfusion`, so `modern_terrain.lua`'s captured native upvalue
was nil and any confusion that reached the wrap would error. A faithful
native leaf (transcribing gen2/Battle.lua:3452-3482 -- HP/Safeguard/
Substitute/held-item/already-confused gates, then
`confuseCount = turns or random(4)+2`, plus the real message) is now defined
in the harness's Lua prologue next to the existing
`useMove`/`sideOf`/`switchLocked` leaves.

Harness round80 = 6 checks green (canChangeType's four Dynamax cases --
opponent-blocked / self-allowed / plain-allowed / Gen 1 battler-wrapper;
Misty Terrain blocking the confusion secondary, and the control landing it
with no terrain). Every earlier round stays green; 131/131 subsystems, 0
failures.

---

## Phases 13-23 — The residual backlog (post-audit)

These phases were added after Phase 0's audit (round 81). Each closes a
family of the 156 residual gaps enumerated in `combat/NATIVE_COVERAGE.md`.
They are ordered by lever: the primitives they need either already exist
(`registerPowerOverride`, `registerDamageModifier`, `registerCritStageModifier`,
the stat-stage registry) or are small, so the early phases are pure wiring and
the later ones add a seam apiece.

### Phase 13 — Conditional / variable power (33 moves)

**Primitive:** `registerPowerOverride(id, fn)` (already exported by
`combat/modern_combat.lua`) plus a small per-battle turn-state tracker
(moved-after-target this turn, took-damage this turn, was-hit-super-effectively,
consecutive uses, ally-fainted count, user's happiness, the target's current
types). Where a real Showdown `onBasePower` multiplies rather than replaces,
use `registerDamageModifier`.
**Moves:** AVALANCHE, BOLTBEAK, DRAGONENERGY, ERUPTION, FISHIOUSREND,
FRUSTRATION, FURYCUTTER, HEX, LASTRESPECTS, PAYBACK, RAGEFIST, RETURN, REVENGE,
RISINGVOLTAGE, STOMPINGTANTRUM, STOREDPOWER, TEMPERFLARE, WATERSPOUT, BRINE,
COLLISIONCOURSE, ELECTRODRIFT, FACADE, FICKLEBEAM, FUSIONBOLT, FUSIONFLARE,
LASHOUT, PSYBLADE, RETALIATE, SMELLINGSALTS, WAKEUPSLAP, PURSUIT, EXPANDINGFORCE,
COMEUPPANCE.
**PS:** `moves.ts` per-move `basePowerCallback`/`onBasePower`; e.g. Avalanche
(1586), Payback (13492), Hex (8244), Facade (5798), Brine (2073), Stored Power
(18461), Last Respects (10225), Collision Course (3049), Electro Drift (5380).
**Harness:** representative formula checks (Avalanche after moving, Facade while
statused, Hex on a statused target, Brine at ≤50% HP, Stored Power on a boosted
user, Last Respects with N fainted), and a no-op check that an ordinary move's
power is untouched.

**STATUS: DONE (round 82).** Shipped as
`combat/modern_power_conditions.lua`, booted in `main.lua` right after
`modern_movepool_counter`. Implementation notes where the shipped code
diverges from the plan above:

1. **Every one of the 29 wired moves goes through `registerPowerOverride`,
   NOT `registerDamageModifier`.** The plan's "where a real Showdown
   `onBasePower` multiplies rather than replaces, use
   `registerDamageModifier`" line was retired: doubling the FINISHED damage
   is a couple of HP off from doubling the base power (the formula's own +2
   and inner floors), so the onBasePower family (Hex ×2, Brine ×2, Facade
   ×2, Rising Voltage ×2, Psyblade ×1.5, Expanding Force ×1.5, Collision
   Course / Electro Drift `chainModify([5461,4096])`, Fickle Beam ×2, Fusion
   Bolt/Flare ×2, Lashout ×2, Retaliate ×2, Smellingsalts ×2, Wake-Up Slap
   ×2) is expressed as a floored base-power multiplier at the same seam the
   pure-substitution family uses. `registerPowerOverride`'s callback now
   receives `ctx.move`, so an override reads the record's own stored power.
2. **The 29th move (COMEUPPANCE), plus STOMPINGTANTRUM, TEMPERFLARE and
   PURSUIT, are explicitly DEFERRED (documented in the file, not faked).**
   Comeuppance returns a flat `damageCallback` (not a scaled power) and
   needs the `tookDamageThisTurn` tracker wired to a *damage-return* seam, not
   a power one; Stomping Tantrum / Temper Flare need "the previous move
   failed"; Pursuit needs switch interception. They move to a later phase.
3. **Three "extra" helpers ride the same file.** Smellingsalts / Wake-Up Slap
   also CURE their target's par/slp on hit (Showdown `onHit`), the `Comatose`
   ability counts as statused/asleep-like for Hex / Wake-Up Slap, and Facade
   is exempted from the burn half-damage cut (the real `move.id !== 'facade'`
   in battle-actions.ts:1816 — an edit inside `modern_combat.lua`'s burn
   block, not this file).
4. **`modern_combat.lua` gained `move = move` in the `registerPowerOverride`
   call ctx** and, more importantly, a **category-resolution fix**: national_dex
   writes modern move categories LOWERCASE (`"physical"`), while
   `MoveCategory.of` only recognises the capitalized spelling and otherwise
   falls back to its `power == 0 → "Status"` heuristic — so every computed-power
   modern move (Return, Frustration, Flail, Reversal) was misread as a status
   move and returned 0 damage BEFORE its override ran. `computeModernDamage`
   now lets the record's own explicit lowercase category win, but only when
   `MoveCategory.of` returned "Status" (a record with a real stored power keeps
   the type-chart answer untouched). This is a real in-game bug, not a harness
   artifact: national_dex's `RETURN`/`FRUSTRATION` records are `power = 0,
   category = "physical"`.

**Harness-stub fix (not a mod change):** the neutral `src.battle.TypeChart`
stub gained `_setEffectiveness(moveType, value)` so round 82 can install the
real 2x matchup (`resolvedTypeMult` reads `>10` as super effective) for the two
super-effective conditional-power moves, then clear it. Both the tested move
and its same-type control pick up the same multiplier, so the equality check
still isolates the power difference.

Harness round82 = 50 checks green; every earlier round stays green;
133/133 subsystems, 0 failures.

### Phase 14 — Type-modifying moves (12 moves)

**Primitive:** `combat/type_override_primitives.lua`'s existing per-move hooks
(the same seam Soak / Magic Powder / Conversion use) for `onModifyType`.
**Moves:** HIDDENPOWER, JUDGMENT, MULTIATTACK, REVELATIONDANCE, TECHNOBLAST,
NATURALGIFT, RAGINGBULL, WEATHERBALL, TERRAINPULSE, TERABLAST, TERASTARSTORM,
PHOTONGEYSER.
**PS:** `moves.ts` `onModifyType`/`onModifyMove` (Hidden Power 8190, Judgment
9767, Multi-Attack 11647, Techno Blast 19157, Weather Ball 20629, Terrain Pulse
19132, Tera Blast 19217, Photon Geyser 13934).
**Harness:** each move reports the expected type under its condition (e.g.
Weather Ball in sun, Terrain Pulse on Electric Terrain, Tera Blast when
Terastallized) and the base type otherwise.

**STATUS: DONE (round 83).** Shipped as
`combat/modern_type_modify_moves.lua`, booted in `main.lua` right after
`modern_items` (the file reads `modern_items.lua`'s `itemOf` lazily, so it must
boot after it). All twelve moves are wired; the phase's contract is exposed as
`mod.exports.typeModifyRules` / `mod.exports.typeModifyCategories` so a driver
can assert the dispatch tables without a damage roll. Implementation notes
where the shipped code diverges from the plan above:

1. **The seam is a `battle.damage` wrap (priority 150), NOT
   `type_override_primitives.lua`.** That primitive rewrites a mon's *stored
   types* for conversion moves (Soak / Magic Powder / Conversion); these twelve
   change the *move's* type for a single use, which is Showdown's own
   `Move.prototype.type` read after its `ModifyType` event. The equivalent
   already-established seam is the one `type_override_moves.lua`'s
   Aerilate/Pixilate family uses: mutate the shared move record, run `next`,
   restore. Priority 150 sits just inside the ability seam (200), so an ability
   conversion runs first and can still be refined. Because `computeModernDamage`'s
   STAB and its `resolvedTypeMult` effectiveness read the SAME mutated
   `move.type`, and gen2-Battle's "It doesn't affect" gate is driven off the
   returned `info.effectiveness` (gen2-Battle.lua:1264), the conversion is
   fully effective, not cosmetic.
2. **The power half rides `registerPowerOverride`** (the Phase 13 convention,
   base power substituted BEFORE the formula): Weather Ball 50→100 in any
   weather, Terrain Pulse 50→100 on any terrain while grounded, Tera Blast
   100 for a Stellar Terastallization, Natural Gift takes the held berry's
   `naturalGift.basePower`. **The category half** (Photon Geyser / Tera Blast /
   Tera Starstorm → Physical when the user's raw Attack exceeds its raw SpA) is
   applied by the same wrapper, so the formula's physical/special branch sees it.
3. **Item facts come from `national_dex.exports.itemFlags`** — the separate
   `onPlate` / `onMemory` / `onDrive` / `naturalGift` payload (read lazily,
   tolerated nil on an older national_dex). Its Title-case types are normalized
   to engine ids (`"Psychic"` → `PSYCHIC_TYPE`). `battle.magicRoomActive` and a
   Klutz holder suppress the item, matching Showdown's `ignoringItem()`.
4. **Hidden Power** reads this engine's own DV-derived `Battle:hiddenPower`
   routine (gen2-Battle.lua:556 / :543) when present, else Showdown's default
   Dark. **Honest partials (documented in the file, not faked):** Natural Gift
   does NOT fail without a berry (Showdown's `onPrepareHit` returns false; a
   fail-gate seam is not applied here, so it plays as an ordinary Normal move);
   Weather Ball honours ANY stored weather, so Air Lock / Cloud Nine are not
   modelled (the same limitation the mod's other weather reads carry); Raging
   Bull / Tera Starstorm match both Showdown-hyphen and engine-underscore
   species-id spellings, and a species this engine does not build keeps the
   record's Normal (the honest base answer).

### Phase 15 — Self stat-stage boosts (19 moves)

**Primitive:** `combat/modern_movepool_stages.lua`'s `primary(...)`/`secondary(...)`
registry plus `main.lua`'s `CUSTOM_EFFECT_PATCH` mapping (the same path that
already wires Nasty Plot / Calm Mind / Dragon Dance).
**Moves:** QUIVERDANCE, VICTORYDANCE, TAILGLOW, WORKUP, FILLETAWAY, AUTOTOMIZE,
DEFENDORDER, SHELTER, TICKLE, TIDYUP, FEATHERDANCE, BABYDOLLEYES, CAPTIVATE,
GEOMANCY, BELLYDRUM, CURSE (self path), HOWL, GEARUP, MAGNETICFLUX.
**PS:** `moves.ts` `boosts` maps; note TICKLE / FEATHERDANCE / BABYDOLLEYES /
CAPTIVATE are target-directed, so they use the opposing stage writer, not the
self one.
**Harness:** each move lands its real stage deltas on the right side; Gen 1
stays inert.

**STATUS: DONE (round 84).** Shipped as additions to
`combat/modern_movepool_stages.lua` (no new file), repointed by `main.lua`'s
`CUSTOM_EFFECT_PATCH`. All 19 moves are wired. Implementation notes where the
shipped code diverges from the plan above:

1. **Why they were dead.** national_dex gives each a real `statChanges` list
   with `statChance = 0` (an unconditional whole-move change, not a secondary),
   and `installMovepoolEffects`'s generic branch only fires when
   `statChance > 0` -- so none was ever applied. Their real Showdown shape is
   the flat `boosts` map on a Status move, which is exactly what this file's
   existing `primary()`/`applyChange` helpers express: attack/defense/spa/spd
   into modern_combat's own store (the one `computeModernDamage` reads),
   speed through the native path.
2. **Four already carried a native effect id** (Baby-Doll Eyes, Feather Dance,
   Howl, Shelter). That is not the same as working: the native effect writes
   the ENGINE's own stage table, which `computeModernDamage` never reads, so on
   Gen 2 those drops never reached modern damage, and Feather Dance was also
   dead on Gen 1 (`gen1EffectModeled = false`). Repointing them here is the
   real fix.
3. **Seven have a real second mechanic**, handled by their own bespoke record
   rather than `primary()`: Fillet Away and Belly Drum cost half max HP (and
   fail at/below half, or -- Belly Drum -- at max Attack); Captivate is
   gender-gated (opposite known genders only); Gear Up / Magnetic Flux only
   reach Plus/Minus holders; Tidy Up also clears every Substitute on the field
   and both sides' hazards (native Spikes in `battle.spikes[side]`, the four
   mod hazards in `battle.hazards[side]`); Geomancy charges for a turn; Curse
   is two moves in one body (a Spe -1 / Atk +1 / Def +1 self boost for a
   non-Ghost user, or a half-max-HP-curse on the target for a Ghost one, riding
   the engine's own `mon.volatile.cursed` residual).
4. **Honest partials (documented in the file, not faked):** Autotomize's real
   weight-halving is not modelled (this engine tracks no weight in the modern
   damage path); the Ghost Curse residual is Gen 2 only (the Gen 1 residual has
   no curse arm -- a pre-existing engine limit); Gear Up / Magnetic Flux reach
   only the user in singles (there is no second ally slot).

### Phase 16 — Recovery moves (5 moves)

**Primitive:** the engine's heal primitives (the same ones Recover / Synthesis
use) plus the `healing` field already read generically nowhere — these five are
not caught by the generic listener because they are whole-move heals.
**Moves:** HEALORDER, MILKDRINK, SLACKOFF, ROOST, AQUARING.
**PS:** `moves.ts` `heal` (Heal Order 7987, Milk Drink 11497, Slack Off 17423,
Roost 14838, Aqua Ring 314), plus `battle-actions.ts:1198-1222` (the
`moveData.heal` handler that decides the ordering and the full-HP fail).
**Harness:** the user's HP rises by the real fraction; Roost also drops the
Flying type for the turn.

**STATUS: DONE (round 85).** Shipped as
`combat/modern_recovery_moves.lua`, booted in `main.lua` right after
`modern_movepool_damage`. Implementation notes where the shipped code
diverges from the plan above:

1. **Three of the five are already native, so nothing is repointed for
   them.** Heal Order / Milk Drink / Slack Off are a plain `heal: [1, 2]`
   self-move with nothing else; national_dex gives all three gen1Effect =
   `HEAL_EFFECT` / gen2Effect = `EFFECT_HEAL` with both `*Modeled` flags
   true, and this engine's own heal primitives (MoveEffects.lua's
   `HEAL_EFFECT`, gen2-Battle.lua's `EFFECT_HEAL`) already split on move
   id and heal floor(maxHp/2) for anything that is not Rest. The plan's
   premise that all five "are not caught by the generic listener" was
   simply wrong for these three -- re-registering an already-working
   native handler would be pure risk for no behavioral gain, so they are
   left alone and recorded as native-covered in NATIVE_COVERAGE.md.
2. **Roost is repointed only for its second half.** Its 50% heal was
   native and correct; the missing mechanic was the `self: {volatileStatus
   : 'roost' }` condition's `duration: 1` `onType` filter (FLYING removed
   until end of turn). `GALAR_ROOST_EFFECT` now resolves both halves in one
   handler, and the drop is modelled at `resolvedTypeMult`'s existing
   `mod.exports.defensiveTypesOf` seam -- wrapped, never replaced, so
   modern_tera's Stellar override still runs first. Because
   `resolvedTypeMult` is reached through the unconditional `battle.damage`
   wrap that is every battle's only damage path on both generations, the
   filter works on Gen 1 and Gen 2 alike (the plan's heal-primitive
   framing would have left Gen 1 unsupported the way the stored-type
   mutation is).
3. **Ordering matched to Showdown literally.** `battle-actions.ts:1201`
   runs the `moveData.heal` block FIRST and, at full HP, emits `-fail`,
   sets `damage[i] = false` and `continue`s -- skipping every later block,
   the `self` volatile included. So a full-HP Roost fails and does NOT
   drop the Flying type; the handler gates both halves on the same
   condition. A Terastallized user still heals but keeps its Flying
   typing (the real condition's own `onStart` terastallized guard).
4. **Aqua Ring is the one genuinely missing move** (gen1Effect
   `NO_ADDITIONAL_EFFECT`, gen2Effect `EFFECT_NORMAL_HIT`, both modeled
   false). It is a self volatile with a 1/16 end-of-turn residual -- the
   same direct-write residual shape modern_status_volatiles.lua already
   uses for Ingrain -- and a switch-scoped flag added to
   status_condition_cleanup.lua's `SWITCH_SCOPED` list.
5. **Honest partial (documented in the file, not faked):** Aqua Ring's
   real "passed on by Baton Pass" half is not modelled -- Baton Pass itself
   has no handler in this mod yet (phase 20). A switch and a battle end
   both clear the ring, which is the half the cleanup file owns.

Harness round85 = 16 checks green; every earlier round stays green;
135/135 subsystems, 0 failures.

### Phase 17 — Charge / two-turn / consecutive-use (12 moves)

**Primitive:** the engine's charge-turn machinery (Solar Beam / Fly / Dig shape)
for the `priorityChargeCallback`/`onTryMove` family, plus the consecutive-use
counter for Ice Ball/Rollout and the combo state for the Pledges/Round/Echoed
Voice.
**Moves:** SOLARBLADE, METEORBEAM, SHELLTRAP, SKYDROP, BEAKBLAST, ICEBALL,
ROLLOUT, ECHOEDVOICE, ROUND, WATERPLEDGE, FIREPLEDGE, GRASSPLEDGE.
**PS:** `moves.ts` `onTryMove`/`onModifyMove`/`basePowerCallback` per move.
**Harness:** a charged move spends the charge turn and fires on the second;
Ice Ball/Rollout power escalates; Round doubles with an ally's Round (using the
party-support seam).

**STATUS: DONE (round 86).** Shipped as
`combat/modern_charge_moves.lua`, booted in `main.lua` right after
`modern_recovery_moves`. Implementation notes where the shipped code diverges
from the plan above:

1. **Three charge moves ride the engine's own charge machinery rather than a
   new seam.** Solar Blade / Meteor Beam / Sky Drop each get a `move_effects`
   record with a `charge` table plus a matching Gen 2 `Effects.CHARGE` entry,
   exactly the shape `modern_weather.lua`'s own GALAR_SOLARBEAM_EFFECT already
   uses. Gen 1's announce text is keyed by move id in BattleState's own
   `CHARGE_TEXT`, which cannot be extended from a mod, so a modern charge move
   falls back to the engine's generic line (cosmetic only); Sky Drop
   additionally sets `charge.invulnerable` so the user leaves the field on
   turn 1.
2. **Solar Blade's sun-skip extends `modern_weather.lua`'s own
   `SUN_SKIPS_CHARGE` table** (the Solar Beam mechanism), Gen 1 only -- the
   same documented Gen 2 limitation Solar Beam already has (Gen 2 uses its own
   `Effects.CHARGE` system). Its weak-weather power halving (rain/sand/snow,
   Showdown's `weakWeathers`) is a `registerPowerOverride`, with the Mega Sol
   exemption reusing the same personal-"as if sun" carve-out Synthesis heals
   already use.
3. **Meteor Beam's charge-turn Sp. Atk rides the real
   `battle.charge_required` hook** -- called on the charge turn only, since the
   release turn is already `releasing` and never reaches the charge branch.
   The boost is exported as `mod.exports.applyChargeTurnBonus` (unit-testable)
   and keyed by BOTH the move id and the repointed effect string, because
   Gen 1's payload carries the move arg (`.id`) while Gen 2's carries the def
   (`self.data.moves[id]`, which may only expose `.effect`).
4. **The Ice Ball / Rollout / Echoed Voice ladders ride
   `registerPowerOverride`**, fed by a `battle.move_used` counter that mirrors
   `modern_power_conditions.lua`'s own Fury Cutter volatile
   (`battle.__g9TurnIndex` + a last-use turn). Ice Ball/Rollout are
   `30 * 2 ** (uses - 1)` capped at five, doubled once more while Defense
   Curl's marker is up; Echoed Voice is `40 * mult`, mult 1..5, field-wide.
   The counters are set on the real event, never inside an override (the AI
   also runs overrides to preview a candidate move -- the exact double-count
   trap Fury Cutter's own comment names).
5. **Shell Trap / Beak Blast arm from the `battle.turn_started` payload's
   chosen actions and react on `battle.damage_dealt`.** Shell Trap's "fires
   only if hit by a physical move" rides `modern_action_order.lua`'s reusable
   `registerFailGate` seam; Beak Blast burns any mon that makes contact with
   the armed user (through the shared `mod.exports.makesContact`, so Long
   Reach is honoured). Both clear at turn end and on switch.
6. **Honest partials (documented in the file, not faked):** Sky Drop's
   target-carry half is not modelled (this engine's charge machinery is
   user-side only -- Fly/Dig make only the USER semi-invulnerable), so it
   plays as a one-mon Fly that deals damage; Ice Ball/Rollout's real 5-turn
   `onLockMove` is not modelled (no generic lock seam, and reusing the rampage
   lock would wrongly add Outrage's confusion) so the player may stop early;
   Echoed Voice's ladder resets on a skipped turn (the field-wide
   pseudo-weather is moot in singles). The Shell Trap gate itself is Gen 2
   (`registerFailGate` runs inside `Battle:useMove`); the charge and power
   halves work on both generations.
7. **ROUND / Water Pledge / Fire Pledge / Grass Pledge are deliberately NOT
   repointed** -- their base damage is already correct, and their only missing
   half is a partner's move (Round doubles when an ally used Round; a Pledge
   becomes 150 and lays a field condition when an ally used a different
   Pledge). In this engine's 1-vs-1 shape there is no ally action to pair
   with, so those halves are genuinely unobservable -- the same situation
   `combat/structural_exemptions.lua` already documents for Follow Me /
   Helping Hand, and unlike those the base move is fully correct. Recorded in
   NATIVE_COVERAGE.md.

Harness round86 = 42 in-driver checks green (plus the JS-side move-patch
assertion); every earlier round stays green; 136/136 subsystems, 0 failures.

### Phase 18 — Guard / contact interaction & ignore-ability (21 moves)

**Primitive:** the damage-modifier and move-flag seams (protect-breaking,
ignore-defensive/evasion, ignore-ability, contact callbacks), reusing
`modern_move_flags.lua` and the existing `breaksProtect`/`ignoreAbility` flags.
**Moves:** PHANTOMFORCE, SHADOWFORCE, HYPERSPACEHOLE, CHIPAWAY, SACREDSWORD,
DARKESTLARIAT, MOONGEISTBEAM, SUNSTEELSTRIKE, FLYINGPRESS, SYNCHRONOISE,
POLTERGEIST, FALSESWIPE, SUPERCELLSLAM, STEELROLLER, ICESPINNER, THOUSANDWAVES,
FREEZYFROST, CEASELESSEDGE, STONEAXE, FELLSTINGER, ORDERUP.
**PS:** `moves.ts` `breaksProtect` (Phantom Force 13785 / Shadow Force 15410 /
Hyperspace Hole 8937), `ignoreAbility` (Moongeist Beam 11295 / Sunsteel Strike
18844), `ignoreDefensive`+`ignoreEvasion` (Chip Away 2497 / Sacred Sword 14690 /
Darkest Lariat 3610), `onEffectiveness` (Flying Press 6106), False Swipe
`onDamage` (FALSE SWIPE 5592).
**Harness:** each flag is observed on a real damage computation (protect bypass,
ability ignored, stage boost ignored) and a control proving ordinary moves are
unaffected.

**STATUS: DONE (round 87).** Shipped as `combat/modern_guard_contact.lua`
(booted in `main.lua` right after `modern_trap_moves`, which owns the last of
its dependencies), plus edits to `combat/modern_combat.lua` (the three
damage-formula moves), `abilities/ability_dispatch.lua` (the ignore-ability
suppression), `combat/modern_side_conditions.lua` (exported `clearTerrain`),
`abilities/engine/damage_multiplier.lua` (Supercell Slam joins Reckless's crash
list) and `main.lua` (the extended `BYPASSES_PROTECT` table + the new
`IGNORE_DEFENSIVE`/`IGNORE_EVASION`/`IGNORE_ABILITY` maps, applied in
`wireMovepoolSubEffects`). Implementation notes where the shipped code diverges
from the plan above:

1. **The three protect-breakers ride the existing `bypassesProtect` flag.**
   Phantom Force / Shadow Force / Hyperspace Hole join Feint in
   `BYPASSES_PROTECT`, which `wireMovepoolSubEffects` stamps onto the live
   record that `modern_combat_protect.lua`'s own battle.damage hook already
   reads. The two Force moves are ALSO charge moves, so they get their own
   `GALAR_PHANTOMFORCE_EFFECT` / `GALAR_SHADOWFORCE_EFFECT` charge records (the
   Sky Drop shape, `invulnerable = true`) via `CUSTOM_EFFECT_PATCH` and a Gen 2
   `Effects.CHARGE` entry.
2. **ignoreDefensive is implemented directly in `computeModernDamage`**, not as
   a new seam: it zeroes the effective defender's Def/SpD stage for the
   computation only (the exact hole Unaware's attacker half already plugs),
   driven by the move record's own flag.
3. **ignoreEvasion rides `battle.accuracy`** by zeroing the defender's native
   evasion stage for the duration of one roll and restoring it immediately
   after -- the zero-and-restore idiom `abilities/engine/accuracy_multiplier.lua`
   already established for Keen Eye/Unaware. Handles both Gen 2's
   `battle.stages[side].evasion` and Gen 1's wrapper `target.stages.evasion`.
4. **ignoreAbility rides a new `battle.damage` wrap** that sets a single
   module-local `ignoredAbilityMon` inside `abilities/ability_dispatch.lua` (the
   one choke point every ability check funnels through -- the same reasoning
   Neutralizing Gas's own comment gives for living there) for the duration of
   the computation, then clears it error-or-not. This blinds Filter/Solid
   Rock/Wonder Guard/Sturdy/etc. to the target exactly as Showdown's
   `move.ignoreAbility` does.
5. **Flying Press / Synchronoise / False Swipe live in `computeModernDamage`**
   -- two as extra per-row applications / early immunities, False Swipe as a
   post-formula `target.hp - 1` clamp (returning 0 at 1 HP so the engine's
   min-1 clamp can't faint it).
6. **The on-hit riders are one `battle.damage_dealt` listener keyed by move id**
   (Ice Spinner / Steel Roller terrain clear via the newly-exported
   `clearTerrain`, Thousand Waves' pin via `trapApplyPin`, Freezy Frost's
   reset of both the modern and native stage stores, Ceaseless Edge's Spikes and
   Stone Axe's Stealth Rock via `hazardsFor`/the native `battle.spikes` store,
   Fell Stinger's KO-gated +3 Attack via `changeStage`). Poltergeist / Steel
   Roller's fail conditions ride `registerFailGate`, exported as named
   predicates (`poltergeistGate`/`steelRollerGate`) so they are unit-testable.
7. **Honest partials (documented in the file, not faked):** Hyperspace Hole's
   `bypasssub` Substitute-pierce is not modelled (no hook on this engine's
   Substitute redirection, the same gap every other bypasssub move carries);
   Order Up needs Commander/Tatsugiri form, neither of which the mod models, so
   it deals plain damage; Supercell Slam's crash-on-miss self-damage has no
   "the move missed" event to hang off (only its Reckless boost half is wired);
   Ceaseless Edge's Spikes tick on Gen 2 only (Gen 1 has no switch-in Spikes
   damage anywhere in this engine); the two fail gates are Gen 2-only
   (`registerFailGate` runs inside `Battle:useMove`).

Harness round87 = 33 in-driver checks green (plus the JS-side move-patch
assertions); every earlier round stays green; 137/137 subsystems, 0 failures.

### Phase 19 — Item / held-item interaction (8 moves)

**Primitive:** the existing item-swap/steal seams
(`modern_ability_change_moves.lua` / `modern_items.lua` shapes) and the
`item_dispatch` surfaces; Plasma Fists' pseudo-weather rides
`registerPseudoWeather` from the field-effects phase.
**Moves:** SWITCHEROO, TRICK, THIEF, COREENFORCER, SPECTRALTHIEF,
PLASMAFISTS, BESTOW, FLAMEBURST.
**PS:** `moves.ts` `stealsBoosts` (Spectral Thief 18068), `onHit` (Thief 19062,
Bestow 1344, Core Enforcer 3029, Flame Burst 5877), `pseudoWeather` (Plasma
Fists 13651).
**Harness:** items swap/steal against real held-item data; Spectral Thief takes
the boosts; Plasma Fists sets the ion-deluge-like pseudo-weather.

**STATUS: DONE (round 88).** Shipped as `combat/modern_item_moves.lua` (booted
in `main.lua` right after `modern_guard_contact`, which is after
`modern_items` / `modern_field_effects` / `modern_ability_change_moves`), plus
one export added to `combat/modern_ability_change_moves.lua`
(`mod.exports.CANNOT_SUPPRESS`). Implementation notes where the shipped code
diverges from the plan above:

1. **The plan's `registerPseudoWeather` primitive does not exist.** The
   field-effects phase wires each pseudo-weather as a plain battle-scoped
   counter (`battle.gravityTurns` / `mudSportTurns` / `waterSportTurns` /
   `ionDelugeTurns` / `fairyLockTurns`), so Plasma Fists sets
   `battle.ionDelugeTurns = 1` directly -- exactly what the Ion Deluge move
   sets and what `modern_field_effects`' own `turn_ended` tick clears -- and
   the existing `effectiveMoveType` turns Normal moves Electric for free.
2. **Trick / Switcheroo share one handler.** Showdown's `onHit` bodies are
   byte-identical (only the message name differs), so both move records point
   at the same local `itemSwapRun`; the take/restore contract mirrors
   `Pokemon.takeItem` (an item string on success, false when refused, nil when
   empty) and respects Sticky Hold plus this mod's `isUnremovable` (Mail)
   exemption -- the same two checks Knock Off already applies.
3. **The removal refusal is read through `modern_items`' exports**, not a
   re-derivation: `isUnremovable` for the Mail exemption and `abilityIdOf` for
   Sticky Hold.
4. **Spectral Thief steals from BOTH stage stores** (the mod's `stagesFor`
   bucket for atk/def/spa/spd, the native per-side/per-mon store for
   speed/accuracy/evasion), before the hit is computed -- the real
   `hitStepStealBoosts` position ahead of `hitStepMoveHitLoop` -- so the
   stolen Attack boosts the very hit that takes it. An immune hit never steals,
   matching Showdown's immunity-before-steal ordering, checked through the
   mod's own `resolvedTypeMult`.
5. **Core Enforcer reuses the Gastro Acid suppression** (`setAbility(..., nil)`)
   and `modern_ability_change_moves`' exported `CANNOT_SUPPRESS` set; the
   `newlySwitched || queue.willMove(target)` gate reduces to "the target has
   already moved this turn" (a just-switched mon has not, so the moved check
   subsumes the switched check), read off the same `movedThisTurn` flag
   `modern_power_conditions` writes.
6. **Thief is Covet's twin** (Showdown `onAfterHit`, user must hold nothing),
   wired on `battle.damage_dealt` exactly as Covet already is.
7. **Flame Burst's ally splash is REAL code, found to have zero targets in
   1-vs-1** (a target side has no other active battler), so it runs and finds
   nobody -- the move keeps its already-correct plain damage. It is exported
   (`flameBurstSplash`) and unit-tested against a stubbed roster, not faked.
8. **Honest partials (documented in the file, not faked):** Core Enforcer and
   Flame Burst's real `onAfterSubDamage` half is not modelled -- this engine's
   `dealDamage` absorbs a Substitute hit and returns before it emits
   `battle.damage_dealt`, so there is no sub-damage seam (the same gap every
   bypasssub move here carries); the family's own earlier "every move is a
   structural no-op on Gen 1" status was closed by round 99, which wired all
   of it onto the Gen-1 held-item slot (see README.md's round-99 section).

Harness round88 = 24 in-driver checks green (plus the JS-side move-patch
assertions); every earlier round stays green; 138/138 subsystems, 0 failures.

### Phase 20 — Pivots & move-copying (11 moves)

**Primitive:** `combat/modern_switch_moves.lua`'s pivot/self-switch seam (the
U-turn shape) plus the move-copying primitives for Assist/Copycat/Sketch/
Instruct.
**Moves:** BATONPASS, SHEDTAIL, CHILLYRECEPTION, ASSIST, COPYCAT, SKETCH,
INSTRUCT, LOCKON, MINDREADER, PSYCHUP, PSYCHOSHIFT.
**PS:** `moves.ts` `selfSwitch`/`onHit` per move; Lock-On `onTryHit` (Lock-On
10443, Mind Reader 11578); Psych Up `onHit` (Psych Up 14160).
**Harness:** Baton Pass carries boosts/volatiles; Assist/Copycat call a real
move; Lock-On makes the next move sure-hit.

**STATUS: DONE (round 89).** Shipped as `combat/modern_pivot_moves.lua` (booted
in `main.lua` right after `modern_item_moves`, consuming `switch_primitives`'
`requestSwitch` and `modern_combat`/`field_duration`'s weather + stage
exports). Implementation notes where the shipped code diverges from the plan
above:

1. **Baton Pass is wrapped, not re-registered.** The native Gen 2
   `EFFECT_BATON_PASS` already does the real volatile-table move, so the file
   reads it live from `Battle.MOVE_EFFECT_RECORDS.EFFECT_BATON_PASS` and pcall
   chains it, copying the mod's own per-mon atk/def/spa/spd `stagesFor` bucket
   forward keyed on the PRE-switch side (`Battle:sideOf` is a plain
   `mon == self.player` identity test, captured before the native handler
   flips `self.player`). It also appends `"lockOn"` to the live
   `Effects.BATON_PASS_DROPS` list, since Showdown's `lockon` is `noCopy`.
2. **Shed Tail's substitute transfer rides `battle.battler_switched`.** The
   hard plan ("hand a substitute to the incoming mon") does not survive this
   engine's own switch path, which `clearVolatile`s BOTH the outgoing and
   incoming mon (`Battle:switch` / `switchMonAtSide`). A pending stamp
   (`battle.__g9ShedTailSub`) is re-applied on the real switch event, copying
   ONLY `substitute` (never boosts), per `pokemon.ts:1248-1250`.
3. **Assist / Copycat / Instruct share one nested-dispatch seam** -- a
   `Battle:useMove` under `battle.copyDepth`, the same called-move guard
   `modern_field_effects.lua`'s Nature Power uses. Instruct is a synchronous
   nested dispatch (the engine's `runTurn` is an unexported local closure, so
   real queue re-insertion is impossible); Showdown's own `queue.prioritize`
   makes the instructed move resolve immediately after Instruct, which this
   reproduces.
4. **Copycat reads a battle-global last-move tracker** (`battle.move_used` sets
   `__g9PrevMoveId`/`__g9LastMoveId`), because Showdown sets `this.lastMove`
   at the END of a runMove -- so Copycat must read the PREVIOUS move. Honest
   simplification flagged in-file: a move that then misses/fails is still
   copyable here (Showdown skips failed moves only via `clearActiveMove(true)`).
5. **Sketch writes the learnset slot directly** (`mon.moves[idx] = {...}`),
   which persists like the native Transform/learn paths since `Battle.party`
   IS `save.party` on Gen 2.
6. **Lock-On / Mind Reader are a pure re-point** at the native
   `Battle.MOVE_EFFECTS.EFFECT_LOCK_ON` (the target-side `lockOn` + the
   `Battle:consumeLockOn` sure-hit arm), which was unreachable only because
   national_dex registers both ids at `EFFECT_NORMAL_HIT`.
7. **Psych Up copies 7 stage keys** (mod store: atk/def/spa/spd; native
   per-side store: speed/accuracy/evasion) plus the `focusEnergy` volatile and
   the mod's own `laserFocusTurns`; `dragoncheer`/`gmaxchistrike` are not
   modelled by this engine at all -- flagged rather than faked.
8. **Psycho Shift's refusal leaves the user statused.** Gen 2's
   `applyStatus`/the status-immunity helpers gate the transfer; if refused the
   move fails and the cure is skipped, matching `battle-actions.ts:1223-1229` +
   `:1317-1334` (a refused `trySetStatus` false-combines damage, so `selfDrops`
   skips the cure).
9. **Honest partial/family note:** every handler routes through `normalize()`
   so a Gen 1 caller cannot crash, but the pivot primitives and native Gen 2
   dispatch are Gen 2 machinery -- `isGen2Battle` gates them rather than
   half-building a Gen 1 path, exactly like `modern_force_switch.lua`.

Harness round89 = 28 in-driver checks green (plus the JS-side move-patch
assertions); every earlier round stays green; 139/139 subsystems (was 138),
0 failures.

### Phase 21 — Status/volatile infliction residue (9 moves)

**Primitive:** the status APIs + `modern_status_volatiles.lua`.
**Moves:** WILLOWISP, SPITE, FORESTSCURSE, TRICKORTREAT, POWERTRICK, MAGNETRISE,
EERIESPELL, SPARKLINGARIA, POLLENPUFF.
**PS:** `moves.ts` `status` (Will-O-Wisp 20744), `onHit` (Spite 18018, Forest's
Curse 6079, Trick-or-Treat 19485), `volatileStatus` (Power Trick 14015, Magnet
Rise 10830), `secondary` (Eerie Spell 5300, Sparkling Aria 17449), Pollen Puff
`onHit` (13968).
**Harness:** Will-O-Wisp burns through the real status path; Magnet Rise grants
Ground immunity; Power Trick swaps the stat pair.

**STATUS: DONE (round 90).** Shipped as `combat/modern_status_moves.lua` (booted
in `main.lua` right after `modern_pivot_moves`), plus small edits to
`combat/modern_combat.lua` (the Magnet Rise Ground-immunity arm in
`resolvedTypeMult`) and `combat/status_condition_cleanup.lua` (two fields added
to `SWITCH_SCOPED`). Implementation notes where the shipped code diverges from
the plan above:

1. **Two of the nine needed no wiring at all, recorded honestly.** WILLOWISP is
   already native on Gen 2 -- national_dex's `registry_gen2` gives it
   `effect = "EFFECT_BURN", effectModeled = true` and Gen 2's own EFFECT_BURN
   applies the burn. POLLENPUFF's only effect beyond its plain 90-BP damage is
   an ALLY heal (`moves.ts:13563-13586`, `if (source.isAlly(target))`); this
   engine's default format is 1-vs-1, where a target is never an ally, so the
   heal has no reachable trigger -- the same structural no-op class as Flame
   Burst's ally splash in phase 19. Nothing was repointed for either.
2. **Spite and Eerie Spell share one PP-drain rule** -- Showdown's
   `Pokemon#deductPP` (`pokemon.ts:888-900`): subtract up to N, clamp at 0,
   RETURN the amount actually removed (0 = the move fails). Spite is a
   repointed status handler (up to 4); Eerie Spell is a `battle.damage_dealt`
   rider (up to 3), because its damage is already native
   (`EFFECT_NORMAL_HIT` / `effectModeled=true`) and a repointed record would
   pre-empt the damage.
3. **Sparkling Aria's burn cure is a `battle.damage_dealt` rider.** Showdown
   marks hit targets with a `sparklingaria` volatile then cures a burned target
   in `onAfterMove` (the marker only exists so Shield Dust / Sheer Force behave,
   `moves.ts:17358-17388`); in 1-vs-1 that reduces to "on a landed hit, cure the
   target's burn".
4. **Forest's Curse / Trick-or-Treat own a new `addMonType`, NOT
   `setMonTypes`.** Showdown models an added type as a SINGLE `addedType` slot
   appended to the base list (`pokemon.ts:2132-2138`), which
   `type_override_primitives.lua`'s own header explicitly names as outside its
   (whole-list-replacing) scope. `addMonType` appends, removes any previous
   added type first (so Forest's Curse then Trick-or-Treat swaps Grass for
   Ghost rather than stacking), fails when the target already has the type, and
   books the slot on `mon.addedType` -- which is now in `SWITCH_SCOPED` so a
   switch drops it (the base types are already restored by
   `type_override_primitives`' own `clearVolatile` wrap). It is gated through
   the existing `canChangeType(..., { viaOpponent = true })`, so Tera / Dynamax
   / boss-type protections apply for free.
5. **Power Trick mirrors Power Shift.** Both swap the user's raw
   `mon.stats.attack`/`.defense`; Power Trick gets its own
   `powerTrickActive`/`powerTrickPre` fields and its own `battle.battler_switched`
   / `battle.ended` revert listeners (deliberately NOT in `SWITCH_SCOPED`, which
   could only nil a flag, never swap the stats back). A second use toggles the
   trick off (Showdown's `onRestart` -> `onEnd`).
6. **Magnet Rise reuses Telekinesis's exact shape**: a mon-local
   `magnetRiseTurns` counter (5), decremented in a `battle.turn_ended` listener,
   with the Ground immunity resolved beside Telekinesis's own in
   `resolvedTypeMult` (`return 0` while `magnetRiseTurns` is set and Gravity is
   not up). Recase refreshes the counter; hard-cast fails under ingrain /
   smackdown (`groundedByMove`) / Gravity.
7. **Honest notes in-file:** the Gen 1 last-move/type shapes are read so a Gen 1
   caller cannot crash, but the raw-stat and added-type halves target Gen 2's
   raw-mon fields (the mod's manifest declares gen2 only) -- the same split
   `modern_stat_manipulation.lua` documents.

Harness round90 = 22 in-driver checks green (plus the JS-side move-patch
assertions); every earlier round stays green; 140/140 subsystems (was 139),
0 failures.

### Phase 22 — Field/side protection & delayed moves (11 moves)

**STATUS: DONE (round 91).** Shipped as `combat/modern_side_protection.lua`
(booted in `main.lua` right after `modern_status_moves`, so its `Battle.useMove`
wrap sits closest to native among the blockers). Ten of the eleven planned ids
are wired; **HAIL is deliberately deferred** under the standing "we won't bring
hail yet" instruction recorded in `combat/modern_weather.lua`'s own header
(Snow/Snowscape is Gen 9's real replacement and the only Ice weather this mod
builds), so this phase ships 10 of its 11 ids on purpose.

**Primitive:** `combat/modern_side_conditions.lua` and
`combat/modern_field_effects.lua`'s existing registries.
**Moves:** SAFEGUARD, WIDEGUARD, QUICKGUARD, CRAFTYSHIELD, MATBLOCK,
DOOMDESIRE, FUTURESIGHT, PRESENT, FIRSTIMPRESSION, GRASSYGLIDE (HAIL deferred).
**PS:** `moves.ts` `sideCondition` (Safeguard 15576, Wide Guard 20809,
Quick Guard 14490, Crafty Shield 3143, Mat Block 10984), the `futuremove` slot
condition (conditions.ts:379-425; Future Sight 6392, Doom Desire 3847), Present
13920, First Impression 5474, Grassy Glide 7656.

Implementation notes where the shipped code diverges from the plan above:

1. **Safeguard is already native, so it is only re-pointed.** The base Gold
   engine owns the whole mechanic (`EFFECT_SAFEGUARD` at gen2/Battle.lua:2719,
   `Battle:safeguarded` :3345, the `applyStatus`/`applyConfusion` gates
   :3403/:3455, a damaging move's secondary-status gate, and the screen tick
   :5201); national_dex shadows the move at `EFFECT_NORMAL_HIT`, and that is the
   ONLY reason it did nothing. `GALAR_SAFEGUARD_EFFECT` forwards to the native
   handler, with a direct fallback so a build without it still sets the native
   `screens[side].safeguard`. Court Change / Defog / Brick Break keep working
   unchanged through `combat/modern_side_conditions.lua`.
2. **The four guards are per-SIDE flags** (`battle.g9Guards[side]`), created
   lazily and cleared at each `battle.turn_ended` (Showdown's duration-1 side
   conditions tick at the owner's side residual). Wide Guard / Quick Guard arm
   the shared Protect stall chain through the new exported
   `modern_combat_protect.armStallChain`. Mat Block's first-turn-out rule is
   checked INSIDE its effect `run` (after native `useMove` has incremented
   `__g9MoveActions`), so `> 1` is literally Showdown's `activeMoveActions > 1`;
   the fail-gate seam used by First Impression runs one step earlier, so it
   needs the equivalent `> 0`.
3. **A blocked move is nullified through the existing `moveEffectRecordFor`
   substitution seam** (the one `modern_combat_protect.lua` Part D and
   `modern_action_order.lua`'s fail gate already established), so PP is spent
   and "X used Y!" is still announced, and only the effect is swapped for the
   guard line. `guardBlockReason` is a pure, exported decision function so every
   branch is directly harness-testable.
4. **Future Sight / Doom Desire supersede the native 4-turn volatile with the
   shared current-Showdown 2-turn scheduler** (`resolveTurn = turn + 1`,
   conditions.ts:384 `endingTurn = (turn - 1) + 2`): scheduled on the target's
   SIDE, one slot per side, damage rolled once at schedule time with the engine's
   own `Damage.calc` (falling back to the plain formula), and landed on whoever
   stands there at `battle.turn_ended`. The same "cross-gen rule prefers the
   current Showdown behaviour" call `modern_weather.lua` documented for its
   starters. The one named difference from Showdown: the fused damage is kept
   rather than recomputed against a switched-in occupant.
5. **Present rolls once per use** (on `battle.move_used`, cached on the user) so
   the `registerPowerOverride` base power (0/40/80/120) and the 20% heal tier
   read the SAME number; the heal half rides one priority-45 `battle.damage`
   wrap. Grassy Glide gets only a `registerPriorityModifier` (+1 on Grassy
   Terrain while grounded) -- its damage is already native.

Harness round91 = 37 in-driver checks green (plus the JS-side 7-move patch
check); every earlier round stays green; 141/141 subsystems (was 140), 0
failures.

### Phase 23 — Recharge / self-recoil / self-drop (15 moves)

**STATUS: DONE (round 92).** Shipped as `combat/modern_self_effects.lua` (booted
in `main.lua` right after `modern_side_protection`, so it is the last combat
blocker and its `Battle.useMove` wrap is the outermost of the chain). All fifteen
planned ids are wired -- the final phase of the missing-effects pipeline.

**Primitive:** the engine's recharge/recoil primitives plus
`registerDamageModifier` for the self-directed halves.
**Moves:** BADDYBAD, BLASTBURN, FRENZYPLANT, GIGAIMPACT, GLAIVERUSH,
GLITZYGLOW, HYDROCANNON, METEORASSAULT, PRISMATICLASER, ROAROFTIME, ROCKWRECKER,
SPARKLYSWIRL, MISTYEXPLOSION, MINDBLOWN, STEELBEAM.
**PS:** `moves.ts` `self` (recharge / self-drop), `selfdestruct` (Misty
Explosion 11613), `mindBlownRecoil` (Mind Blown 11641 / Steel Beam 18312), the
Glaive Rush / Gigaton Hammer / Meteor Assault self-rules.
**Harness:** a recharge move forces the recharge turn; the self-drop reduces the
right stat; Mind Blown/Steel Beam recoil is a fraction of real HP lost (the
existing overkill-clamp rule).

Implementation notes where the shipped code diverges from the plan above:

1. **Recharge spans both generations' own native flags, set by this file's own
   real logic rather than a native effect id** (national_dex shadows all eight
   recharge moves at `EFFECT_NORMAL_HIT`, so the native `EFFECT_HYPER_BEAM`
   auto-set is unreachable). Gen 2 sets `volatile(mon).recharge` -- consumed by
   `checkTurn` (gen2/Battle.lua:984) -- from a `battle.damage_dealt` listener;
   Gen 1 sets `mon.mustRecharge` from `GALAR_RECHARGE_EFFECT.afterDamage`, read
   by BattleState.lua:2107. Both fire on a landed hit only.
2. **Mind Blown / Steel Beam is half MAX HP, hit OR miss.** Current Showdown
   keeps a `mindBlownRecoil` user-hit path (battle-actions.ts:1382) AND an
   `onMoveFail` half-max path, and there is NO KO-skip clause -- so the loss must
   fire even on a miss/Protect/immunity, which a `damage_dealt` listener cannot
   see. It rides the `Battle.useMove` wrap (Gen 2) and the record's own
   `onMiss`/`afterDamage` (Gen 1). Magic Guard blocks it (real ability-id check,
   abilities.ts:2465); Rock Head deliberately does NOT.
3. **Misty Explosion's `selfdestruct: "always"`** also cannot ride a damage
   listener -- the user faints once the move is USED, Protect/miss/immunity
   notwithstanding. Gen 2 does it on the useMove wrap (reproducing
   `Battle:selfdestructUser`'s status/HP/Lech-Seed cleanup, gen2/Battle.lua:1410,
   because that native is keyed on a different effect id), Gen 1 forwards to
   `BattleState:selfDestruct` from its record. Its own `onBasePower` 1.5x on
   grounded Misty Terrain is a dedicated `registerDamageModifier` entry -- Misty
   Terrain itself does NOT boost Fairy moves in current Showdown.
4. **Glaive Rush's drawback volatile lives on the USER** (`self.volatileStatus`),
   not the target: while held, every move aimed AT the holder always hits
   (`battle.accuracy` wrap returning true) and deals double damage
   (`registerDamageModifier("glaive_rush", 90)`). Applied on a landed hit and
   cleared at the holder's own next `battle.move_used` (Showdown's
   `onBeforeMovePriority: 100`), matching the `noCopy` switch-wipe that
   `clearVolatile` (gen2/Battle.lua:1112) already performs.
5. **Baddy Bad / Glitzy Glow / Sparkly Swirl are Gen 2-only halves.** The
   screens ride the real `battle.screens` table (Light Clay 5 -> 8 through the
   shared `resolveFieldDuration` primitive, exactly like the native screens) and
   the cure reuses `status_cure.lua`'s `cureStatusOf` over
   `g9SidePartyOf` + the active mon, so all three are the same Gen-2-state line
   Phase 7's `modern_side_conditions.lua` already draws. Gen 1 keeps the move's
   ordinary damage -- not a regression. Their four records are empty
   `kind="full"` markers (the Fling/Knock-Off precedent), so Gen 2's own damage
   path is untouched.

Harness round92 = 27 in-driver checks green (plus the JS-side 15-move patch
check); every earlier round stays green; 142/142 subsystems (was 141), 0
failures.

---

## Item effects — phased wiring (post-audit, rounds 94+)

The move pipeline above is finished (phases 0-23). This section is the item
counterpart, planned from `combat/ITEM_EFFECTS_AUDIT.md` (round 93) exactly
as phases 13-23 were planned from `combat/NATIVE_COVERAGE.md`. The audit is
the input document: it names the shared `held_item.trigger` chokepoint, the
`national_dex.exports.itemFlags(id)` facts accessor (and its 530-key
`data/items/generated/flags.lua` payload), the ROM-vs-Showdown id namespace
mismatch, and the exact list of wired / missing / hardcoded items.

Three constraints shape every phase below:

1. **`itemFlags` is facts, never mechanics.** It can replace hand-written
   *data tables* (fling powers, `isPokeball` / `isBerry` classification,
   plate/memory/drive types) but never a *behaviour*. Every wired mechanic
   stays hand-written.
2. **The id namespace differs.** ROM `mon.item` ids are underscore constants
   (`KINGS_ROCK`, `BLACKBELT_I`); `itemFlags` keys are Showdown separator-free
   ids (`KINGSROCK`, `BLACKBELT`). A tiny bridge (`norm` + one rename) is
   required, and it is the foundation everything else stands on.
3. **The API's blind spot is this ROM's roster.** `flags.lua` omits all
   thirteen Showdown `tags: ["True Past"]` items, and they are exactly the
   Gen-2 berries, the two bows and Berserk Gene. For those the mod's own
   knowledge is unavoidable, so the bridge carries a documented override
   table rather than pretending the API can answer.

Each phase ships on its own: code + a harness round + persist + manifest
bump, exactly like the move phases.

### Phase 24 — Item-facts foundation + id bridge

**Closes:** the entire class of "raw ROM id handed to `itemFlags`" reads.
`combat/modern_type_modify_moves.lua:98` currently passes `mon.item`
verbatim, so Judgment / Multi-Attack / Techno Blast / Natural Gift see
`nil` facts for every underscore id (only `BLACKBELT_I` even normalizes, and
that one still misses its rename).

**Work:** new `combat/modern_item_facts.lua`, booted immediately before
`modern_items`. It owns `norm(id)` (strip non-alphanumerics, upper), the
`BLACKBELT_I -> BLACKBELT` rename map, a `TRUE_PAST_FACTS` override table for
the thirteen API-blind items (the ten berries carry `isBerry` +
`naturalGift` + the generic 10 fling; the two bows are marked True Past;
Berserk Gene carries its +2 Atk), and the accessors every later phase reads:
`itemFactId`, `itemFact` (nil-tolerant, override-then-API merge), and
`itemFlingFacts`. `modern_type_modify_moves.lua` is repointed through
`itemFact`, with the raw `itemFlags` call kept as a fallback.
**Files:** new `combat/modern_item_facts.lua`; edit
`combat/modern_type_modify_moves.lua`; boot list in `main.lua`.

### Phase 25 — API-backed classification and fling facts

**Closes:** the provisional hardcoded tables the audit flagged
(`ITEM_FLING_POWER`, `BALL_ITEMS`), and the two concrete bugs inside them:
`LIGHT_BALL` wrongly classified as a Poké Ball (so it was unflingable), and
the 26-entry fling table missing every evolution-stone / Spell-Tag / Thick
Club entry the API already knows.

**Work:** in `combat/modern_items.lua`, delete `ITEM_FLING_POWER` in favour
of `itemFlingFacts(id).basePower` (berries still 10, unlisted items still
`DEFAULT_FLING_POWER`), and delete `BALL_ITEMS` in favour of
`isPokeballItem(id)` from the facts module. `isUnflingable` keeps the
API-blind Mail / Apricorn / key-item / TM sets and consults the new
`isPokeballItem`; berry detection (`Incinerate`, `Bug Bite`/`Pluck`, and the
exports other files read) consults `isBerryItem` so modern berries are
classified too. The extra 11 items the API adds over the old table
(5 evolution stones, SUN_STONE, UP_GRADE, SPELL_TAG, THICK_CLUB) are the
concrete correctness win.
**Files:** `combat/modern_items.lua`.

### Phase 26 — Fling secondaries

**Closes:** flung Poison Barb / King's Rock / Light Ball's on-hit status and
volatile (`fling.status`, `fling.volatileStatus`), which the current Fling
handler never applies.

**Work:** in `modern_items.lua`'s existing `battle.damage_dealt` Fling
handler, after the item is consumed, apply the flung item's real
`fling.volatileStatus` (flinch -> `battle:volatile(target).flinched = true`,
the shape `main.lua`'s generic flinch listener already uses) and
`fling.status` (Showdown `psn/par/brn/slp/frz/tox` mapped to the engine's
words and routed through `battle:applyStatus`, guarded so a stub battle
cannot crash). This is the audit's cleanest API-backed fix.
**Files:** `combat/modern_items.lua`.

### Phase 27 — Missing type boosts (Spell Tag + the two bows)

**Closes:** **SPELL_TAG** (Ghost x1.2 -- the conspicuous hole in the
otherwise-complete 15-item type-boost family) and **PINK_BOW / POLKADOT_BOW**
(Normal x1.1, True Past and therefore unreadable from the API).

**Work:** add `SPELL_TAG = "GHOST"` to
`combat/modern_held_items_phase2.lua`'s `TYPE_BOOST_ITEMS`, and add the two
bows to the same `held_item_type_boost` modifier as a separate Normal-only
`4506/4096` (1.1x) branch, with an in-file note that the value is
hand-written because `flags.lua` omits them.
**Files:** `combat/modern_held_items_phase2.lua`.

### Phase 28 — Crit items (Lucky Punch + Stick)

**Closes:** **LUCKY_PUNCH** (+2 crit ratio, Chansey only) and **STICK**
(+2, Farfetch'd only) -- the crit items the Scope Lens work left behind.

**Work:** extend `combat/modern_held_items.lua`'s existing
`registerCritStageModifier("scopelens", ...)` chain with a companion entry
that returns +2 for these two items, gated on the API's own
`itemFlags(id).itemUser` species list (read through the facts module), with
a hardcoded Chansey / Farfetch'd fallback when the API is absent.
**Files:** `combat/modern_held_items.lua`.

### Phase 29 — Berry Juice

**Closes:** **BERRY_JUICE** (heal 20 HP when at or below half max,
consumed), which is not a native `HELD_BERRY` item so it never reaches the
`held_item.trigger` residual chokepoint.

**Work:** a `battle.turn_ended` residual in `modern_items.lua` mirroring the
native berry tick (gate on `hp * 2 <= maxHp`), healing a flat 20, consuming
the item, and recording `ggdLastConsumedItem` for Recycle (NOT
`ggdConsumedBerryThisBattle` -- Berry Juice is not a Berry, so it must not
enable Belch).
**Files:** `combat/modern_items.lua`.

### Phase 30 — Retire the dead `items/` loads (cleanup)

**Closes:** the non-functional pre-existing `items/` tree that `main.lua`'s
`damage_brain` boot loads for no reason. **Correction to the audit's
first pass:** the tree is NOT entirely dead. `combat/damage_pipeline.lua`
itself requires two of its files, and one of them is genuinely live --
`items/engine/damage_modifiers.lua` is the special/fixed-damage Life Orb
boost the pipeline calls, and `items/item_dispatch.lua` is invoked (though
inert, see below). So this phase removes only the redundant side-effect-only
loads, never the two the pipeline needs:
- `main.lua`'s `damage_brain` block drops its own
  `require("items/item_dispatch")` plus the four loads nothing consumes
  (`items/engine/utility_effects`, `items/engine/status_triggers`,
  `items/item_effects_combat`, `items/item_effects_dispatch`) -- each returns
  a table its caller discards and registers no hook. `combat/damage_pipeline`
  still loads the two it uses.
- `items/item_dispatch.lua` shipped a real wrong-field bug: it reads
  `mon.heldItem`, a field that does not exist anywhere in this engine (held
  items live on `mon.item`). It is inert today only because
  `items/data/items_battle.lua` is a no-op stub, but the read is fixed to
  `mon.item` so a future data entry could not be silently ignored.

**Files:** `main.lua`, `items/item_dispatch.lua`.

**STATUS: DONE (round 94).** All six working phases (24-29) shipped in one
round: they are a single cohesive subsystem built on the one
`combat/modern_item_facts.lua` foundation, so they share a harness round
(the move phases grouped their own primitives the same way). Phase 30
(cleanup) shipped alongside them and is verified by the boot staying at
143/143 with zero new failures. Implementation notes where the shipped code
diverges from the plan above:

1. **The bridge's single rename is keyed on the NORMALIZED id, not the raw
   one.** `norm("BLACKBELT_I")` is `"BLACKBELTI"`, so the rename map's key is
   `BLACKBELTI -> BLACKBELT`; the first cut keyed it `BLACKBELT_I` and the
   harness caught it (`bridgeRename=FAIL`) -- a good example of why the round
   exists.
2. **The True-Past table carries each berry's fling 10** (Showdown gives
   every `isBerry` item a generic 10 with no per-item field), so the API and
   the override agree on fling power for the ten berries.
3. **Fling secondaries ride the existing `battle.damage_dealt` Fling
   handler, after the item is cleared.** Flinch writes the same
   `volatile.flinched` flag `main.lua`'s generic flinch listener uses; a
   major status is routed through `battle:applyStatus` with Showdown's short
   ids mapped to the engine's words, guarded so a battle stub without
   `applyStatus` cannot crash.
4. **`isUnflingable` follows Showdown's real rule** -- an item whose facts
   carry no `fling` field is unflingable -- with the twelve Poké Balls
   covered by the explicit `isPokeball` fact and berries exempted (they are
   always flingable at 10). The old `BALL_ITEMS` table is gone, so
   `LIGHT_BALL` is flingable again.
5. **Berry Juice is its own `battle.turn_ended` residual**, not a
   `held_item.trigger` case: it is not a native `HELD_BERRY` item, so it
   never reaches that chokepoint. It records `ggdLastConsumedItem` (Recycle)
   but not `ggdConsumedBerryThisBattle` (Belch), because it is not a Berry.
6. **Two pure helpers were exported for direct testing** --
   `modern_items.flingPowerOf` / `isUnflingable` and
   `modern_held_items_phase2.heldItemTypeBoostMultiplier` /
   `modern_held_items.critItemStage` -- matching the project's existing
   "export the decision, not just the registration" pattern.
7. **Phase 30 corrected the audit's own claim.** `items/engine/
   damage_modifiers.lua` is LIVE (the special/fixed-damage Life Orb boost
   `combat/damage_pipeline.lua` calls), so only the side-effect-only loads
   were removed from `main.lua`; the two the pipeline genuinely requires
   stay. `items/item_dispatch.lua`'s `mon.heldItem` read (a field that does
   not exist -- held items are on `mon.item`) was fixed.

Harness round94 = 43 checks green (the bridge, the accessors, the True-Past
overrides, isPokeball, the species gate, fling power/unflingable, the three
Fling secondaries, both type-boost additions, both crit items, and Berry
Juice); every earlier round stays green; 143/143 subsystems (was 142), 0
failures.

---

## Execution order and rationale


Phases are ordered so shared primitives land before their dependents:
stat read/write (2) before swaps/Shift; a crit seam (3) before nothing
else needs it; the action-visibility seam (5) last among "hard" ones
because it needs `resolveTurnActions` to expose chosen actions; the
ability/field/item phases (8, 11, 12) last because they touch the widest
surface (damage formula, status application, items). Phase 0 runs first
so the exemption list stops the audit from re-flagging impossible moves
every session.

The post-audit backlog (phases 13-23) runs after 12, ordered by shared
primitive: 13-14 (power/type) are the biggest and add the turn-state tracker
that 17 also uses; 15-16 are pure stat-stage/heal wiring on existing
registries; 18-19 ride the move-flag and item seams; 20-23 are the long tail,
each needing at most a small seam of its own. Whenever one of these phases
turns out to close a move already handled elsewhere, record it in
`combat/NATIVE_COVERAGE.md` rather than re-wiring it.

Each phase ships on its own: code + harness block + persist + manifest
bump. No phase blocks on a later one.
