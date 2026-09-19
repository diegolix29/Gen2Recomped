> **OUTDATED APPROACH, 2026-08-23.** Everything below audits coverage
> under the OLD model — native Gen2 labels / this mod's own `GALAR_*`
> custom effect ids. That model is superseded: new move-effect work reads
> `national_dex`'s `dex.exports.moveById(id)` directly for its modern
> fields (`ailment`/`ailmentChance`/`flinchChance`/`statChance`/
> `statChanges`/`drain`/`healing`/`critRate`/`minHits`/`maxHits`/
> `minTurns`/`maxTurns` — explicitly NOT `gen1Effect`/`gen2Effect`/their
> `Modeled` flags), consumed through `combat/showdown_primitives.lua`'s
> verb set while the Gen 9 combat-mode toggle is on. This audit is still
> accurate for the OLD, still-running toggle-off/native-Gen2 fallback
> path — the STUBBED buckets below are real gaps in THAT path, not a
> to-do list for the new one. Left in place as historical grounding, not
> deleted, since it took a real cross-file audit to produce and the old
> path keeps running when the toggle is off.

# moves_new.lua effect coverage — tracking doc

Point-in-time audit (2026-08-23) of every move in `combat/moves_new.lua`,
classified by whether its real secondary effect (per `functionCode`, the
original PBS FunctionCode kept on every entry for exactly this purpose) is
actually implemented anywhere in this mod, and if not, what's missing.

**Why this file exists:** `moves_new.lua`'s own header comment is stale —
it undersells real coverage (describes only flinch/confuse/trap as done,
"145 moves" stubbed). A real cross-reference against every implementation
file tells a different story: most of what looks stubbed by `effect ==
"NO_ADDITIONAL_EFFECT"` in that file is actually still stubbed, but a large
chunk of moves carrying a `GMAX_*_EFFECT`/`GALAR_*_EFFECT` id are already
real, working implementations living in separate files
(`modern_movepool_stages.lua` etc.) that a header-comment-only read would
miss entirely. This file is the corrected picture, with citations.

**Staleness warning:** this is a snapshot, not live state. Re-verify
against the actual registration code before trusting a citation here as
still accurate — files change; this doc might not have been updated to
match. If this doc and the code disagree, the code is right.

**Counts at audit time: 146 ALREADY_COVERED / 7 STUBBED_NEEDS_EXISTING_LABEL / 26 STUBBED_NEEDS_NEW_MECHANIC** (179 moves total).

---

## STUBBED_NEEDS_NEW_MECHANIC (26) — genuinely new engineering

No existing primitive in this codebase covers these. Grouped by the
missing primitive — building one often clears several moves at once.

**Type-override** (no type-change mechanism exists at all):
- **BURNUP** — user loses Fire type
- **MAGICPOWDER** — sets target's type to Psychic
- **SOAK** — sets target's type to Water

**Terrain system** (unbuilt entirely):
- **GRASSYTERRAIN**
- **MISTYTERRAIN**
- **PSYCHICTERRAIN**

**Forced switch-out** (no mid-battle switch hook):
- **DRAGONTAIL** — forces the target out
- **UTURN** — forced self-switch after damage

**Guaranteed-crit override** (no crit-override hook found anywhere):
- **LASERFOCUS** — guarantees next hit crits
- **WICKEDBLOW** — always crits

**Stockpile family** (needs a stack-counter mechanic):
- **STOCKPILE**
- **SWALLOW** — blocked on Stockpile not existing

**Mid-turn action visibility** (`turn_order.lua`'s own header already flags
the reorder seam, `mod.exports.resolveTurnActions`, as "not yet built"):
- **AFTERYOU** — needs mid-turn action-queue reordering
- **SUCKERPUNCH** — fails unless the target already chose a damaging move
  this turn; no pre-resolution visibility into the opponent's chosen move

**Standalone gaps:**
- **ALLYSWITCH** — no ally battler slot exists (also an exemption
  candidate, see below)
- **BELLYDRUM** — explicitly deferred in `modern_movepool_stages.lua`'s
  own "Left alone, explicitly, NOT guessed at" list
- **CURSE** — Ghost-conditional recurring-damage volatile; same "Left
  alone" list
- **ENTRAINMENT** — copies user's ability onto target; no battle-effective
  ability system exists (`modern_hazards.lua`'s own comment confirms this)
- **FOULPLAY** — uses target's Attack instead of user's; no stat-source
  override in the damage formula
- **HEALINGWISH** — user faints, heals+cures its replacement
- **LASTRESORT** — fails unless every other known move has been used; no
  per-mon move-usage-history tracker
- **MAGICCOAT** — bounces status moves back at the user; no reflection
  mechanism
- **ROLLOUT** — escalating power per consecutive turn; no multi-turn
  power-scaling counter
- **SMACKDOWN** — must force-hit a semi-invulnerable target and set a
  persistent "grounded" flag; the existing `invulnerable` flag is only
  ever read, never bypassed/cleared
- **SNIPESHOT** — "cannot be redirected"; nothing to redirect away from
  without a Follow Me/Rage Powder mechanic (also an exemption candidate)
- **UPROAR** — locks user in (Outrage's `thrashTurns` machinery could
  cover that half) AND prevents any Pokémon from sleeping battle-wide (no
  hook into status infliction for this)
- **WICKEDBLOW** — (listed above, crit-override group)

---

## STUBBED_NEEDS_EXISTING_LABEL (7) — just needs wiring, not new logic

- **AROMATHERAPY** — cure whole party's status. Whole-party iteration
  already proven in `modern_items.lua`'s `battle.started` handler
  (`battle.party`/`battle.enemyParty`); status is a plain mutable field.
- **BRICKBREAK** — remove screens. Native `reflect`/`lightScreen` fields
  already exist and are already nulled by a native effect elsewhere
  (`src/battle/MoveEffects.lua:217-224` sets them, `:247` clears them).
- **COURTCHANGE** — swap side conditions. `modern_hazards.lua`'s own
  per-side hazard table (`hazardsFor(battle, side)` / `battle.hazards[side]`)
  is already the right addressable state, just not wired to this move.
- **ENDURE** — survive at 1 HP, decaying success chance. The exact chain
  primitive (`protectChainX`/`protectChainTurn`) already works for
  Protect (`modern_combat_protect.lua`); that file's own header already
  names Endure as a candidate to point at the same id.
- **FAKEOUT** — guaranteed flinch, first-turn-out only. Flinch itself is
  the proven `GALAR_FLINCH_EFFECT_<chance>` mechanism
  (`main.lua`'s `installMovepoolEffects`); only needs a "first turn out"
  gate added on top (that gate was not separately confirmed to exist).
- **FOCUSPUNCH** — fails if user was hit this turn. The exact "damage
  taken this turn" tracker (`counterTookThisTurn`, cleared on
  `battle.turn_started`) already exists for Metal Burst/Mirror Coat
  (`modern_movepool_counter.lua`).
- **JAWLOCK** — traps both user and target. `GALAR_TRAP_EFFECT`
  (`main.lua`) already implements single-target trapping
  (`trappingTurns`/`boundTurns`); just needs applying to both sides.

---

## Structural-impossibility exemption candidates

Same class of reasoning `main.lua`'s `isMoveDataComplete` already applies
to `ROUND`'s `UsedAfterAllyRoundWithDoublePower` (a doubles-only mechanic
in a confirmed singles-only engine — nothing to implement, not a gap).
Worth adding the same explicit exemption rather than ever "fixing":

- **ALLYSWITCH** — requires an ally battler slot; none exists.
- **SNIPESHOT** — redirect-immunity has no meaning without a redirection
  effect to be immune to, and a singles engine has exactly one possible
  target.

---

## ALREADY_COVERED (146) — terse, grouped by source

**Structural exemptions (`main.lua` `isMoveDataComplete`):** functionCode
`"None"` (17): AERIALACE, BOOMBURST, BRANCHPOKE, BRUTALSWING,
DAZZLINGGLEAM, DISARMINGVOICE, DRAGONCLAW, DRAGONPULSE, DYNAMAXCANNON,
FALSESURRENDER, HIGHHORSEPOWER, HYPERVOICE, LEAFAGE, OVERDRIVE, PSYCHOCUT,
SHOCKWAVE, STONEEDGE. `multiHit` (4): BULLETSEED, DOUBLEHIT,
DOUBLEIRONBASH, ROCKBLAST. `"RemoveProtections"`: FEINT (`bypassesProtect`,
read in `modern_combat_protect.lua` Part B). `"ProtectUser"`: PROTECT,
DETECT (real `GMAX_PROTECT_EFFECT` in `modern_combat_protect.lua:94-118`).
`"UsedAfterAllyRoundWithDoublePower"`: ROUND.

**`main.lua` installMovepoolEffects (GALAR_FLINCH/CONFUSE/TRAP):**
ASTONISH, DARKPULSE, DRAGONRUSH, IRONHEAD, DOUBLEIRONBASH (flinch);
DYNAMICPUNCH, SWEETKISS, WATERPULSE (confuse); SANDTOMB (trap — known
Gen2-broken, flagged in main.lua's own header, real working Gen1 handler).

**`modern_movepool_stages.lua` (primary/secondary stat changes + Clear
Smog):** ACIDSPRAY, ANCIENTPOWER, APPLEACID, AROMATICMIST, BREAKINGSWIPE,
BUGBUZZ, BULKUP, BULLDOZE, CALMMIND, CHARGE (partial — only +1 SpDef self,
Electric-boost volatile deferred, flagged in-source), CHARM, CLEARSMOG,
CLOSECOMBAT, COIL, CONFIDE, COSMICPOWER, COTTONGUARD, COTTONSPORE, CRUNCH,
DECORATE, DRAGONDANCE, DRUMBEATING, EERIEIMPULSE, ENERGYBALL, FAKETEARS,
FIRELASH, FLAMECHARGE, FLASHCANNON, GRAVAPPLE, HAMMERARM, HONECLAWS,
IRONDEFENSE, LEAFSTORM, LEAFTORNADO, LIQUIDATION, LUNGE, METALCLAW,
METALSOUND, NASTYPLOT, NOBLEROAR, PLAYNICE, PLAYROUGH, POWERUPPUNCH,
RAZORSHELL, ROCKPOLISH, ROCKSMASH, ROCKTOMB, SCARYFACE, SHIFTGEAR,
SPIRITBREAK, STEELWING, STRUGGLEBUG, SUPERPOWER, SWEETSCENT, TARSHOT
(partial — -1 Speed only, fire-weakness volatile deferred, flagged
in-source), TEARFULLOOK.

**`modern_movepool_status.lua`:** FLAMEWHEEL, PYROBALL (burn10); INFERNO
(burn100); DISCHARGE, DRAGONBREATH, SPARK (paralyze30); NUZZLE
(paralyze100); CROSSPOISON, POISONTAIL (poison10); GUNKSHOT, POISONJAB,
SLUDGEBOMB (poison30); FLATTER, SWAGGER (stat-raise+confuse combo).

**`modern_movepool_damage.lua`:** BRAVEBIRD, WOODHAMMER (recoil 1/3);
HEADSMASH (recoil 1/2); DRAININGKISS (drain 3/4); HEALPULSE, LIFEDEW,
SYNTHESIS (heal — Synthesis flat 1/2, weather-conditional part deferred,
flagged in-source); PAINSPLIT; BOUNCE, OUTRAGE, ETERNABEAM
(charge/thrash/recharge).

**`modern_movepool_counter.lua`:** METALBURST, MIRRORCOAT.

**`modern_hazards.lua`:** STEALTHROCK, TOXICSPIKES, RAPIDSPIN.

**`modern_weather.lua`:** RAINDANCE, SUNNYDAY, SANDSTORM, SNOWSCAPE,
BLIZZARD (accuracy-exception hook), SOLARBEAM (charge + Sun skip; Gen2
charge-skip gap explicitly flagged in-source).

**`modern_status_effects.lua`:** ATTRACT, TAUNT, TORMENT.

**`modern_combat.lua` (registerDamageModifier/registerPowerOverride/
special-cased formula):** ACROBATICS, VENOSHOCK, ASSURANCE, TWISTER
(modifiers); HEATCRASH, HEAVYSLAM, FLAIL, POWERTRIP (partial — atk/def/
spa/spd stages only, speed/acc/evasion out of scope, flagged in-source)
(power overrides); ENDEAVOR (hardcoded `move.id=="ENDEAVOR"` branch in
`computeModernDamage`, confirmed non-stub).

**`modern_items.lua` (Gen2-only, real handlers + runtime `:patch`):**
FLING, KNOCKOFF, COVET, INCINERATE, BUGBITE, PLUCK, BELCH, RECYCLE.

**`gigantamax/gimmick_dynamax.lua`:** ENCORE — overrides native
`EFFECT_ENCORE` for Dynamax interaction; confirmed real only on Gen 2
(Gen 1's own `MoveEffects.lua` has no Encore equivalent at all).

---

## Notable caveats carried forward

- **CHARGE, TARSHOT, POWERTRIP, SYNTHESIS** are "covered" but knowingly
  partial — each has a real, working registration, with a documented
  missing half (own file comments call this out explicitly, not silently
  dropped).
- **ENCORE** only works on Gen 2; a Gen 1 boot registers
  `effect="EFFECT_ENCORE"` pointing at an id Gen 1's own move_effects
  registry never seeds, so it's non-functional there (not a crash —
  `Registry:override` doesn't assert prior existence — but inert/wrong-
  signature if ever dispatched).
- **SANDTOMB**'s trap effect is real on Gen 1 but known-broken on Gen 2
  per `main.lua`'s own header (never wired to Gen 2's native `wrapCount`
  mechanism).

---

## Relationship to the Gen 9 Showdown-ownership effort

See the `project-dynamaxrecomp-combat-ownership` memory (session context,
not in this repo) for the standing architecture decision this audit feeds:
new Gen-9-mode logic reuses native's existing `effect` labels where they
overlap (most of the ALREADY_COVERED bucket above already speaks that
vocabulary or a close cousin of it), and only the STUBBED buckets above
represent real remaining label/mechanic design work.
