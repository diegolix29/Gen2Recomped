# Multi-battler combat — contract for a future doubles/triples/asymmetric mod

This mod owns combat resolution end to end (damage math, sub-effects, turn
order) for whatever battlers exist. This document is the spec for a future
mod that adds real multi-battler support (doubles, triples, or asymmetric
formats like 4v1 or 1v5) — what you get from us for free, what the actual
integration contract is, and what genuinely doesn't exist yet and needs its
own engine change.

The core principle, stated precisely: **we own combat resolution — the
move, the target(s), the priority, the Speed, the Trick Room state, the
RNG, the damage math, the ordering — you own only which battlers exist and
what each one has chosen to do.** A battler's chosen move and chosen
target(s) are already attached to whatever structure represents "battler X
is acting this turn" the moment it's submitted (the same shape the native
engine's own `action = { kind = "move", move = moveId, ... }` already is)
— so you don't hand us a separately-computed parallel array of priority
numbers, Speed numbers, a Trick Room flag, and an RNG function. You hand us
*who is acting*. Everything else, we already have or already own.

## What you get for free, no wiring needed

`useMove(attacker, defender, moveId)` → `hitOnce` → `battle.damage` →
`dealDamage` is already generic over who's fighting. None of it hardcodes
`battle.player`/`battle.enemy` — `attacker`/`defender` are parameters
throughout. If your mod calls `battle:useMove(someBattler, someTarget,
moveId)` for any two battlers you control, it flows through the exact same
pipeline as today's player-vs-enemy fights — STAB, Tera, Protect/Max
Guard, every `registerDamageModifier` entry, all of it — automatically.

You do not need to ask us anything to get correct damage output for a
battler we've never heard of. This is already true today.

## The actual integration contract — battler identity only

**BUILT** (2026-08-27, `combat/turn_order.lua`) — this section used to say
"not yet built" and that claim went stale without anyone updating it,
which is exactly what led a later session to wrongly conclude no real
multi-battler combat exists in this ecosystem at all (it does —
`g9-Battle-Scene`'s own `combat.lua`/`battle_screen.lua` already drive
real singles/doubles/triples/boss-fight rosters through this exact
function). The shape below is the real, live signature, not a proposal:

```lua
mod.exports.resolveTurnActions(battle, actingBattlers) -> nil
```

- `actingBattlers`: a flat list of battler references — nothing else. No
  `priority`, no `speed`, no `move`, no `targets`. Each battler's own
  chosen move and target(s) are read directly off whatever field the
  submission step already populated on it (the same place the native
  engine already keeps `action.move` for the player today) — not
  re-supplied in a second, parallel structure.
- We derive priority from the battler's own chosen move. We derive Speed
  from the battler's own current stats/stages/status — the same read we
  already do to compute its damage. We derive Trick Room from our own
  tracked state (see "Trick Room ownership" below). We derive RNG from
  `battle:roller()`, which we already have direct access to.
- We process one action at a time, in our own correctly-derived order,
  calling our own `battle:useMove(...)` pipeline for each. Because we
  compute each hit's real damage ourselves (see `combat/modern_combat.lua`),
  we know with certainty — the instant we compute it, not by predicting
  ahead of the roll that produced it — whether it drops a target below 0
  HP or changes a stat stage. That knowledge updates who still counts as
  a valid remaining actor *before* we decide who's next, which is what
  makes fainting mid-turn and Speed drops mid-turn resolve correctly
  without ever guessing an outcome in advance.

No caller-side computation, no caller-side comparator, no caller-side RNG
plumbing. Tell us who's acting; we do the rest, the same way `useMove`
already asks nothing of a caller beyond attacker/target/move today.

## Trick Room ownership

Trick Room is not an input a caller provides — it is a real move
(`TRICKROOM`, already registered by National Dex, currently sitting at
`NO_ADDITIONAL_EFFECT`) that this mod will own as a sub-effect, the exact
procedure `combat/SUBEFFECTS.md` describes: `:patch()` it with a real
effect, track activation/duration/expiry as our own battle-scoped state.
Once that exists, `resolveTurnActions` (and today's `battle.turn_order`
wiring) read it directly. Not yet built — flagged here so it isn't
mistaken for already covered.

## The internal primitive underneath this: `computeTurnOrder`

`combat/turn_order.lua` also exports a lower-level function:

```lua
mod.exports.computeTurnOrder(actors, opts) -> orderedActors
```

This is **not** the integration point described above — it's the pure
comparator `resolveTurnActions` (and today's 2-battler `battle.turn_order`
wrap) use internally once priority/Speed/Trick-Room/RNG have already been
derived. It takes already-resolved numbers (`{ id, priority, speed }` per
actor, `opts.trickRoom`, `opts.roller`) and returns them in order —
priority bracket, then Trick-Room-aware Speed, then a real Fisher-Yates
shuffle (seeded from the roller) for genuine ties, never left to
comparator luck.

It stays a plain, stateless, battle-object-free function on purpose —
reusable, testable in isolation, and asymmetric-ready by construction: it
has no concept of "sides" or "how many per side" anywhere in it, so 1v1,
2v2, 3v3, 4v1, 1v5, and 4vN all go through the identical code path with no
special-casing. A caller integrating with this mod should reach for
`resolveTurnActions` once it exists, not this — calling this directly
means you're the one deriving priority/Speed/Trick-Room/RNG yourself,
exactly the caller-side computation the contract above exists to avoid.

## What's still missing — stated honestly, not papered over

**UPDATE, 2026-08-28: `g9-Battle-Scene` already brought this.** The two
gaps below are still real and unfixable from inside `gen1recomp-dev`
itself, but a real caller doesn't need either one fixed to run doubles/
triples combat — `g9-Battle-Scene`'s own `combat.lua`/`battle_screen.lua`
sidestep both simply by never routing multi-battler turn resolution
through `runTurn`/`Battle:takeTurn`/`battle.player`/`battle.enemy` in the
first place: it keeps its own real, N-agnostic roster
(`self.enemyBattlers[i]`/`self.playerBattlers[i]`, explicitly built
"looped, not hardcoded to exactly 2"), drives its own turn loop from
player menu input, and calls `resolveTurnActions(battle, actingBattlers)`
directly with however many real battlers are acting — `battle.player`/
`battle.enemy` end up mattering only as whatever `Battle.new` happened to
set them to (the party's first living mon per side), a detail the actual
combat math never depends on. This is a *cleaner* solution than either
gap below anticipated, not a workaround for them — no monkeypatch of
`Battle:takeTurn` was needed at all. Left below for what they still
genuinely constrain (see the real, still-open `sideOf` gap right after):

1. **No mid-turn hook exists.** `gen2/Battle.lua`'s own turn-resolution
   function (`runTurn`) is a `local function`, not `Battle.runTurn` — it
   is not exported and cannot be wrapped by any mod. The two actions it
   runs (`playerAttack()`/`enemyAttack()`) are themselves local closures
   *defined inside* it — doubly unreachable. There is no code running
   between the first action finishing and the second one starting that a
   mod could attach to. `battle.turn_order` is the only exposed hook, and
   it fires exactly once, before either action executes. Still true, and
   still why `g9-Battle-Scene` never calls `runTurn`/`Battle:takeTurn` at
   all for its own battles rather than trying to hook into either.

2. **No multi-battler data model exists inside `gen2/Battle.lua`
   itself.** `battle.player`/`battle.enemy` are still the only two
   battler slots on the native class — not an array, two fixed fields.
   Still true; still why a THIRD or later battler's own real identity has
   to live entirely in the calling mod's own arrays (exactly what
   `g9-Battle-Scene` does), never in the Battle instance itself.
- A real, N-way `Battle:sideOf(mon)`. The native one is a hard binary --
  `(mon == self.player) and "player" or "enemy"`, literally a two-way
  ternary -- and `dealDamage` and other native code call it internally to
  tag emitted events (`battle:emit({kind=..., side=..., ...})`). Feed the
  existing pipeline a third or fourth battler that isn't literally
  `self.player`, and every event about it gets silently tagged
  `"enemy"` regardless of which real side it's on. This doesn't affect
  `resolveTurnActions`'s own correctness at all -- damage math and
  ordering never consult `side` -- but a custom multi-battle combat scene
  consuming the event stream to decide *what to draw where* would render
  wrong. `sideOf` is a public method (unlike `runTurn`), reachable and
  overridable -- extending it to return a real side/team index instead of
  a binary string is part of the same fork, not a separate ask.

Once that loop exists and calls `mod.exports.resolveTurnActions(battle,
actingBattlers)` per turn (built here, against that loop, once it's real),
the whole re-sort-after-every-action mechanic (PR #6100's actual rule)
falls out for free — it's already how `resolveTurnActions` is specified
to work.

## Targeting: the same ownership split, applied to adjacency

**Update, 2026-08-27**: this half is now real, built, and waiting —
unlike turn order, targeting doesn't need the engine-level battler-slot
gap closed first, since it's a pure per-move-use function of data a
caller hands in, not a standing turn-resolution loop.

`combat/move_targeting.lua` exports:

```lua
mod.exports.resolveMoveTargets(battle, caster, moveId, chosenTarget) -> { battler, ... }
```

Same principle as `resolveTurnActions`, but **the trigger for asking a
caller for position data lives on OUR side, not theirs.** An earlier
draft of this had battle scene call a query function first to decide
whether to bother calling the resolver — correctly rejected: that put a
comparator over move data on the wrong side of the seam, for a fact
only this mod needs to know (the move's own real `target` archetype).

`chosenTarget` is just whatever single mon the caller already has in
hand — the same thing it would otherwise pass straight to
`battle:useMove` as the defender, never a separately-built "adjacency
bundle." For the overwhelming majority of moves (real archetype
`"selected-pokemon"`), that's the whole story — `resolveMoveTargets`
returns `{chosenTarget}` and never asks anyone for anything.

Only for the two archetypes that structurally can't be satisfied by one
already-known target — `"all-other-pokemon"` (Earthquake, Surf — every
adjacent battler except the caster, both sides at once) and
`"all-opponents"` (Muddy Water — every adjacent enemy only), both
confirmed directly against live national_dex records — does this file
fire a request, through the same hook bus `combat/turn_order.lua`
already uses for `battle.turn_order` (confirmed generic in
`src/mods/Runtime.lua`/`Hooks.lua`, not engine-exclusive — any code can
call a named hook, any mod can wrap one):

```lua
Runtime.call("g9.request_adjacency", fallbackFn, battle, caster, moveId)
-- -> { allies = {...}, enemies = {...} }  -- real roster, caster excluded
```

A battle-scene mod's entire contribution is one handler:

```lua
mod.hooks:wrap("g9.request_adjacency", function(nextFn, battle, caster, moveId)
  return { allies = {...}, enemies = {...} }
end, 0, "your-mod-id")
```

No move-awareness, no branching, no comparator on that side at all — it
answers a position query whenever one arrives, full stop. We decide
when to ask; it only ever answers. Without a battle-scene mod wrapping
this hook, a built-in fallback degrades correctly to today's native
two-battler case (the other of `battle.player`/`battle.enemy` is the
only possible adjacent enemy, no allies exist) — so this is already
correct, with zero wiring, for every format this engine runs today.

Boss-fight rule, explicit and caller-side: in a boss fight, the
`allies` a wrapped handler reports should be the FULL ally roster
regardless of real proximity ("adjacent allies = all allies,"
independent of which boss-fight protections are active) — this file
has no roster to enforce that against, it can only honor whatever list
it's handed.

**Second real consumer, not move-triggered**: `move_targeting.lua` also
exports the underlying primitive directly —

```lua
mod.exports.requestAdjacency(battle, caster, moveId) -> { allies = {...}, enemies = {...} }
```

— for anything that needs real adjacent-battler position without
resolving a move's target list at all. `abilities/engine/
switchin_stat_change.lua`'s foes-scope switch-in abilities (Intimidate,
Intrepid Sword, Dauntless Shield) are the first real case: the real
rule is "every adjacent opponent," not "the" opponent, and a hard-binary
`(mon == battle.player) and battle.enemy or battle.player` lookup was
exactly the class of gap this doc's own sideOf section warns about —
correct only for today's 2-battler case. `moveId` is optional here (nil
for a non-move trigger) — a wrapped handler never inspects it regardless
(no move-awareness, ever), so this reuses the exact same hook and the
exact same battle-scene-side contract with nothing new to implement.

**Spread-move damage reduction is now real too**, built directly on this:
`combat/modern_combat.lua`'s own `computeModernDamage` reads
`ctx.opts.targetCount` (a new, purely additive field on the same `opts`
table it already threads through — absent or 1 on every call site today,
so a genuine no-op until a real caller sets it) and applies the real Gen
9 0.75x-per-target rule whenever it's above 1, EXCEPT against a
protected boss (explicit user rule: AoE diminishing is removed entirely
in a boss fight, regardless of which boss-fight flags are active — Life
Dew and Earthquake hit everyone at full force).

**UPDATE, 2026-08-28**: the reason this used to be blocked (nothing
wrapped `"g9.request_adjacency"` with real position data) is CLOSED —
`g9-Battle-Scene/battle_screen.lua` now answers it from its own real
roster. That does NOT mean spread moves are callable end to end yet,
though — a real, DIFFERENT gap sits above it, found while fixing the
first one rather than assumed away: `g9-Battle-Scene`'s own turn-
resolution (`combat.lua`'s `Combat.resolveTurn`) never actually calls
`resolveMoveTargets` at all — it builds `actingBattlers` with exactly
one `target = action.target.mon` per acting battler, straight from
whatever the player/AI chose, and hands that directly to
`resolveTurnActions`. A spread move used through that flow today still
only ever hits the one chosen target, never expanding to the real
roster this file's own adjacency fix now makes available. Closing that
needs `g9-Battle-Scene`'s own queued-action building to call
`resolveMoveTargets(battle, caster, moveId, chosenTarget)` and loop
`useMove` once per resolved target (exactly the call-flow the paragraph
below already specifies) — not yet done. The `"selected-pokemon"` path
(the overwhelming majority of moves) needs nothing new at all and is
already correct today, since it's driven entirely by `chosenTarget` —
whatever the caller already has.

The call-flow: whoever drives move execution (today, nothing new —
that's still the native `useMove` dispatch; eventually, whatever loop
`resolveTurnActions` ends up calling) calls `resolveMoveTargets(battle,
caster, moveId, chosenTarget)` at the point it would otherwise call
`battle:useMove(...)` directly. For a multi-target result (more than
one battler in the returned list, only possible on the two spread
archetypes), it loops `useMove` once per resolved target, passing
`opts.targetCount = #targets` each time so the spread-reduction
step in `modern_combat.lua` applies correctly.

## The actual ask, if you're building this

Bring the battler slots and the turn-resolution loop. Call
`mod.exports.resolveTurnActions(battle, actingBattlers)`, handing us only
battler identity — not priority, not Speed, not targets, not a
comparator. Everything about *what a battler is* and *when it
structurally gets a turn* is your mod's own responsibility to build;
everything about *what actually happens once it's decided to act* is
already ours, and stays ours through this one, minimal seam.

**Done, by `g9-Battle-Scene` (2026-08-27/28):** the battler slots
(`self.enemyBattlers`/`self.playerBattlers`), the turn-resolution loop
(`combat.lua`'s `Combat.resolveTurn`, driven from its own menu input), and
the `"g9.request_adjacency"` wrap (`battle_screen.lua`, answered straight
from that same real roster) — real singles/doubles/triples/boss-fight
combat, not a stub. **Not done anywhere yet**: a real, N-way
`Battle:sideOf` override (the gap named above) — nothing currently
corrects a non-primary battler's event `side` tag, so anything in
`g9-battle-engine` that reads `battle.player`/`battle.enemy`
directly instead of the caster/target it was actually handed (a real risk
for code added without this multi-battler context in mind — audit before
assuming any given ability/status file generalizes correctly to battler
#2 or #3) may misclassify or silently no-op for one.
