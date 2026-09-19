# Wiring a move sub-effect — contributor guide

This mod owns move *sub-effects* (what a move does beyond its base power/
accuracy/PP/type) for the moves it and its sibling mods (`battle_forms`,
`national_dex`) register. National Dex owns the base properties. This guide
is the standardized procedure for adding a new sub-effect without stepping
on that split, and without repeating a real, previously-shipped bug.

## The one rule that matters most

**Never re-register a move that already exists. Always `:patch()`.**

```lua
mod.content.moves:patch("PROTECT", { effect = PROTECT_EFFECT_ID })
```

`Registry:patch(id, partialFields)` merges only the fields you name onto
the *existing* record. National Dex's `power`/`accuracy`/`pp`/`type`/
`category` are never touched, never shadowed, never duplicated — the
engine reads one merged record per move id, always. `Registry:register`
creates a brand-new entry and **throws** if the id already exists; it's
the wrong tool for adding a sub-effect to a move somebody else registered,
and should only ever be reached for for a genuinely new move id.

## Step 1 — register the effect record

```lua
mod.content.move_effects:register(YOUR_EFFECT_ID, {
  kind = "primary",   -- or "secondary" — see the note below, NEVER "full"
  run = function(battle, attacker, defender, def, moveId, sureHit)
    -- your logic
  end,
})
```

## Step 2 — point the move at it

```lua
mod.content.moves:patch("YOUR_MOVE_ID", { effect = YOUR_EFFECT_ID })
```

That's the whole wiring. Two calls, never more.

## The bug this guide exists to prevent

This mod is Gen-2-only. Gen 2's `Battle` class has its **own** move-effect
dispatch, completely separate from Gen 1's `BattleState`/`EffectRegistry`,
and the two use *different record shapes*:

| | Gen 1 (`BattleState`/`EffectRegistry`) | Gen 2 (`gen2/Battle.lua`) — **use this one** |
|---|---|---|
| record shape | `{ kind = "full", perform = function(ctx) ... end }` | `{ kind = "primary"/"secondary", run = function(battle, attacker, defender, def, moveId, sureHit) ... end }` |
| args | one `ctx` table | six positional arguments |
| RNG | `ctx.rng(lo, hi)`, 1..n inclusive | `battle:roller()(n)`, 0..n-1 |
| messaging | handler's return value is read as message lines | **return value is discarded entirely** — call `battle:emit({kind="message", text=...})` yourself |

Registering the Gen 1 shape against a move that only ever runs under Gen 2
is a **silent no-op**: the record resolves fine, `effectRecord.run` is
`nil`, the dispatch's `if handler then` branch never fires, and the move
does nothing — no crash, no warning, nothing in any log. This exact bug
shipped for Protect and Max Guard earlier this session and took a full
investigation to trace, because every symptom (no message, no effect, no
error) looked like something else was wrong. Confirmed directly against
`src/battle/gen2/Battle.lua:1533-1538` and the `move_effects` schema
(`src/mods/Schemas.lua:1280-1288`, which only defines `kind`/
`accuracyChecked`/`run` — `perform` isn't a field at all, for either gen).

**If you are targeting Gen 2 (which this mod always is): `kind = "primary"`
or `"secondary"`, always `run`, never `perform`.**

## Messaging

Since the `run` handler's return value is discarded, show text by calling
`battle:emit(...)` yourself, inside the handler:

```lua
battle:emit({ kind = "message", text = battle:monName(attacker) .. " did the thing!" })
```

Write message text as a literal string, not through `Strings()`/
`romText()` — those exist for the classic engine's own vocabulary, and
plain English is what every native Gen 2 effect (`Battle.MOVE_EFFECTS` in
`gen2/Battle.lua`) already does.

## RNG

Use `battle:roller()`, a `function(n) -> 0..n-1` — **not** `ctx.rng(lo,
hi)`, which is Gen 1's 1..n-inclusive convention and doesn't exist on Gen 2
at all. A `1/x` chance is `battle:roller()(x) == 0`.

## Reuse what's already exported — don't re-derive it

`combat/modern_combat.lua` exports generation-safe helpers every sub-effect
file should use instead of reinventing:

- `mod.exports.isGen2Battle(battle)`
- `mod.exports.curTypesOf(who, gen2)` — live, Transform/Tera-aware type list
- `mod.exports.changeStage(battle, who, stat, delta, fromEnemy, gen2)`
- `mod.exports.registerDamageModifier(id, priority, fn)` — a named,
  priority-ordered slot in the damage formula, for anything that scales a
  hit's damage rather than gating whether the move's own effect runs
- `mod.exports.registerPowerOverride(moveId, fn)` — real per-move variable
  base power (Heat Crash, Flail, etc.), computed *before* the damage
  formula runs

Any file using these must load **after** `modern_combat.lua` in `main.lua`
— see the load-order comments there for the current sequence.

## When a record alone isn't enough

Some effects need to intercept *before* the move's own effect would run at
all (e.g. blocking a status move outright against a Protected target).
`move_effects` records can't do that — for this, wrap the relevant
**class-level** method on the shared `Battle` table (`require("src.battle.
gen2.Battle")`), not a per-instance one:

```lua
local Battle = require("src.battle.gen2.Battle")
local native = Battle.useMove
function Battle:useMove(attacker, defender, moveId)
  -- your check
  return native(self, attacker, defender, moveId)
end
```

This is an established, working pattern in this mod
(`modern_combat_protect.lua`'s Part D — wraps `Battle:useMove` and
`Battle.moveEffectRecordFor` together to block a status move without
skipping its PP cost or its "used X!" announcement). `modern_hazards.lua`
already cites that file by name as the origin of this technique. Reuse it
rather than inventing a new interception shape.

## Defensive coding

- Wrap registration loops (anything iterating `mod.content.moves:each()`
  or similar) in `pcall`, not just each individual call inside the loop —
  an uncaught error partway through a loop can abort the rest of that
  file's setup, not just the one iteration.
- A monkeypatched class method should restore the original on both the
  success and error path if it does anything beyond a plain wrap-and-call.

## Ground truth, not assumption

Before shipping a sub-effect against unfamiliar territory, check the real
dispatch code rather than pattern-matching from a Gen 1 example or from
memory:

- Dispatch site: `src/battle/gen2/Battle.lua`, search `moveEffectRecordFor`
- Schema: `src/mods/Schemas.lua`, `R.move_effects`
- Native reference implementations: `Battle.MOVE_EFFECTS` in the same file
  — every native Gen 2 effect (Protect, Spikes, weather starters, etc.) is
  a real, working example of the `run` shape

## Minimal working template

```lua
return function(mod)
  local EFFECT_ID = "YOUR_MOD_YOUR_EFFECT"

  mod.content.move_effects:register(EFFECT_ID, {
    kind = "primary",
    run = function(battle, attacker, defender, def, moveId, sureHit)
      -- e.g. a 30% chance to do something
      if battle:roller()(10) < 3 then
        battle:emit({ kind = "message",
          text = battle:monName(attacker) .. " triggered the effect!" })
        -- your effect here
      end
    end,
  })

  mod.content.moves:patch("YOUR_MOVE_ID", { effect = EFFECT_ID })

  mod.log:info("your-mod: YOUR_EFFECT_ID wired to YOUR_MOVE_ID")
end
```
