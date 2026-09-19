# Item-effects audit: national_dex item flags vs. this mod's held-item handling

This is the item-effects counterpart to `combat/NATIVE_COVERAGE.md` (the move
audit). It answers, for **items specifically**, the same three questions the
move audit answered: what is already **wired**, what is genuinely **missing**,
and what is **hardcoded** — and for every hardcoded thing, *why*, and whether
national_dex's item API can replace it.

It was produced in round 93, on the same direct-read discipline as every other
audit in this project: the primary source of truth is
`scratch/showdown/items.ts` (Pokémon Showdown Gen 9, `smogon/pokemon-showdown`
master), the fact source is national_dex's own
`data/items/generated/flags.lua` (the payload behind its `itemFlags(id)`
accessor), and the roster of items this mod's engine can actually produce is
`scratch/zeak/x/tools/rom_manifest_gold.json`'s `itemOrder`.

Nothing in this document is a code change. It is the report a wiring phase
would be planned from, exactly as `MISSING_EFFECTS_PLAN.md`'s phases were
planned from `NATIVE_COVERAGE.md`.

---

## 1. The item API national_dex actually exposes

From national_dex's `src/api.lua` (`API_VERSION = 9`):

| accessor | returns | backing payload |
|---|---|---|
| `itemFlags(id)` | structured **facts** for one item, or `nil` | `data/items/generated/flags.lua` (530 keys) |
| `itemById(id)` | the PokeAPI catalogue record for one item | `data/items/generated/api/*.lua` (38 shards) |
| `listItems()` | the sorted id list | catalogue index |

The design intent is stated verbatim in `api.lua`: **"FACTS, not behaviour …
an item that DOES something is an item_effects `use` function on the engine's
own registry, which no data file can hold."** The facts `flags.lua` carries —
and therefore the *only* things `itemFlags` can ever give a consumer — are:

```
gen (530)  num (530)  isNonstandard (282)  fling (279)  basePower (346,
  across fling and naturalGift)  itemUser (135)  megaStone (92)
isBerry (67)  naturalGift (67)  type (67)  forcedForme (44)  isPokeball (28)
onEat (20)  isGem (18)  onMemory (17)  onPlate (17)  boosts (12)
ignoreKlutz (8)  onDrive (4)  isChoice (3)  plus fling.status /
fling.volatileStatus, isPrimalOrb, duration, onTryMovePriority, ...
```

(The counts above are per-field occurrences among the 530 keys.)

Two consequences dominate this whole audit, and they are the reason the report
looks the way it does:

1. **The API is a source of *facts*, never *mechanics*.** `itemFlags("SPELLTAG")`
   will hand you its fling power; it will never tell you it boosts Ghost moves
   by 20%. Every wired *behaviour* in this mod stays hand-written. What the API
   can legitimately replace is the hand-written *data tables* (fling powers,
   berry/ball/mail classification, plate/memory/drive types).
2. **The API's id namespace is Showdown's, not the ROM's.** See §2.

There is one more negative fact worth naming up front, quoted from `api.lua`:
**"NOTHING HERE IS REGISTERED … A reply describes an item; it does not put one
in anybody's bag."** national_dex cannot register an item into this engine.
That is why the twenty modern items this mod introduces are registered by hand
(`modern_held_items_phase2.lua:100`), and must stay that way.

---

## 2. The id-namespace mismatch (why a naive API swap does not work)

The ROM roster (`itemOrder`, 250 ids) uses the cart's own **underscore**
constants — `QUICK_CLAW`, `KINGS_ROCK`, `SCOPE_LENS`, `BLACKBELT_I`,
`PSNCUREBERRY`, `LIGHT_BALL`. national_dex's `flags.lua` uses Showdown's
**CamelCase, separator-free** ids — `QUICKCLAW`, `KINGSROCK`, `SCOPELENS`,
`BLACKBELT`, `PSNCUREBERRY`, `LIGHTBALL`. Normalizing both sides by stripping
non-alphanumerics and upper-casing (`norm`) matches:

- **47 of the 250 ROM ids** have a `flags.lua` record (the "holdable battle
  item" family — the 250 also includes potions, TMs, key items and mail, which
  Showdown either does not carry or carries without facts).
- **Every one of the 47 is a genuine match** — no normalization collision was
  found.
- **The only rename needed is `BLACKBELT_I → BLACKBELT`.** `BLACKBELT_I` is the
  ROM's name for the Fighting-boost belt; `norm("BLACKBELT_I") = "BLACKBELTI"`
  does *not* equal `"BLACKBELT"`. Every other mismatch normalizes cleanly.

So an API-backed table needs exactly one small rename map plus `norm`. That is
trivially cheap — and it is why the fling table (§6) is replaceable today.

### The 13 items the API cannot describe at all

`flags.lua` is generated from Showdown's `items.js` but **omits every item
tagged `tags: ["True Past"]`**. Cross-checking `items.ts` against `flags.lua`
finds **52** items that carry a real handler in `items.ts` but have no
`flags.lua` record. 35 are Z-Crystals (the Z-move system — irrelevant to a Gen
2 roster), 1 is a Mega Stone, 3 are CAP/nonsense (`leek`, `prettyfeather`,
`vilevial`) — and **13 are exactly the Gen-2-exclusive held items this mod's
own roster is built from:**

```
berry  goldberry  mysteryberry  psncureberry  przcureberry  burntberry
iceberry  bitterberry  mintberry  miracleberry  pinkbow  polkadotbow
berserkgene
```

This is the single most important structural finding: **the item API's blind
spot coincides with this ROM's item roster.** For fling powers and type data
the API is authoritative; for the Gen-2 berry set, the two bows and Berserk
Gene there is *nothing to read*, so the mod's own knowledge of them is not
laziness — it is unavoidable. `KNOWN_BERRIES` (§6) is hardcoded for exactly
this reason.

---

## 3. What is already wired

The engine's native held-item layer is one chokepoint: `Battle:heldEffect(mon,
trigger)` (`gen2/Battle.lua:890`), consulted at triggers `priority`, `endure`,
`flinch`, `damage`, `accuracy`, `confuse`, `residual`, and driven per item by a
ROM `heldEffect` byte. The Gen-2 native held effects the codebase names are:
`HELD_LEFTOVERS`, `HELD_BERRY`, the `HELD_HEAL_*` family, `HELD_QUICK_CLAW`,
`HELD_CRITICAL_UP`, `HELD_FOCUS_BAND`, `HELD_FLINCH`, `HELD_BRIGHTPOWDER`,
`HELD_PREVENT_CONFUSE`, the dynamic `HELD_<TYPE>_BOOST` family, and
`HELD_AMULET_COIN`.

The mod hooks that one chokepoint and, per the standing directive "we override
item behavior for native items, always, in terms of combat", owns item
behaviour outright. Wired today:

**a. Native-item audit / override — `combat/modern_held_items.lua`**

| item | real Gen 9 behaviour | mod state |
|---|---|---|
| QUICK_CLAW | 1/8 priority (`items.ts:4985`) | native shape kept, probability corrected 60/256 → 1/8 |
| FOCUS_BAND | 1/10 survive lethal move (`items.ts:2249`) | native shape kept, 30/256 → 1/10 |
| KINGS_ROCK | 10% flinch, no double-dip on a move that already flinches (`items.ts:3205`) | native shape + the double-dip exemption added |
| BRIGHTPOWDER | multiplicative 0.9 accuracy (`items.ts:659`) | native flat subtract suppressed, real product installed |
| SCOPE_LENS | +1 crit stage (`items.ts:5550`) | `registerCritStageModifier`; dead native path removed |
| LEFTOVERS | 1/16/turn (`items.ts:3334`) | verified native, unchanged |

**b. Twenty newly-registered modern items — `combat/modern_held_items_phase2.lua:74`**

`CHOICE_BAND`, `CHOICE_SPECS`, `CHOICE_SCARF`, `LIFE_ORB`, `ASSAULT_VEST`,
`EVIOLITE`, `EXPERT_BELT`, `ROCKY_HELMET`, `BLACK_SLUDGE`, `LIGHT_CLAY`,
`QUICK_POWDER`, `IRON_BALL`, `LAGGING_TAIL`, `FULL_INCENSE`, `DEEP_SEA_TOOTH`,
`DEEP_SEA_SCALE`, `SOUL_DEW`, `ADAMANT_ORB`, `LUSTROUS_ORB`, `GRISEOUS_ORB`.

(Stat multipliers, Choice lock via `forcedMove`/`useMove`, Assault Vest's
status ban, Life Orb 1.3× + 1/10 recoil, Expert Belt 1.2× on super-effective,
Rocky Helmet 1/6 contact, Black Sludge, Light Clay 8-turn screens, Iron Ball
ground/speed, Lagging Tail/Full Incense −0.1 priority, Quick Powder 2× Speed on
Ditto, the three orbs' 1.2×.)

**c. Type-boost family — `combat/modern_held_items_phase2.lua:123,131`**

15 plain items (`TYPE_BOOST_ITEMS`) at `4915/4096` (1.2×) plus 4
species-locked orbs (`SPECIES_TYPE_BOOST_ITEMS`: Adamant/Lustrous/Griseous Orb,
Soul Dew).

**d. Native combat fixes** — `LIGHT_BALL`, `THICK_CLUB`, `METAL_POWDER`
(`modern_held_items_phase2.lua:327/330`, real Showdown handlers at
`items.ts:3417/6288/3972`).

**e. Item-interaction moves** — `combat/modern_items.lua` and
`combat/modern_item_moves.lua`: Fling, Knock Off, Covet, Incinerate, Bug Bite,
Pluck, Corrosive Gas, Recycle, Belch, Trick, Switcheroo, Bestow, Thief,
Spectral Thief, Core Enforcer, Plasma Fists, Flame Burst.

**f. Ability ↔ item interaction** — `abilities/engine/item_interaction.lua`
(Frisk, Magician, Pickpocket, Harvest) plus Ripen, Cheek Pouch, Klutz, Unnerve,
As One, Sticky Hold in `combat/modern_items.lua`.

**g. Magic Room** — `combat/trick_room.lua` (`battle.magicRoomActive`), read by
every item-suppression site.

**h. The one place the item API is already consumed** —
`combat/modern_type_modify_moves.lua:68,98`. Judgment (`rec.onPlate`),
Multi-Attack (`rec.onMemory`), Techno Blast (`rec.onDrive`) and Natural Gift
(`rec.naturalGift`) read `itemFlags(id)` via `itemFactRecord`, with Magic
Room/Klutz suppression (`ignoresItem`, `:91`). This is the working precedent a
fuller API adoption would extend.

**i. Berserk Gene** — natively modelled already: `Battle:checkBerserkGene`
(`gen2/Battle.lua:4086`) consumes the gene on switch-in, gives +2 Attack and
confusion, matching `items.ts:7877`. **Not a gap.**

---

## 4. What is genuinely missing

ROM-reachable items with real Showdown behaviour and *no* handler in this mod:

| item | real Showdown Gen 9 | source | API can supply? |
|---|---|---|---|
| **LUCKY_PUNCH** | +2 crit ratio for Chansey | `items.ts:3517` | partially — `itemFlags("LUCKYPUNCH").itemUser = {"Chansey"}` |
| **STICK** | +2 crit ratio for Farfetch'd | `items.ts:6092` | partially — `.itemUser = {"Farfetch’d"}` |
| **SPELL_TAG** | Ghost moves ×1.2 | `items.ts:5898` | no (behaviour); the item *is* in flags (fling 30) |
| **BERRY_JUICE** | heal 20 HP when ≤ ½ max, consumed | `items.ts:447` | item in flags; behaviour is not |
| **PINK_BOW** | Normal moves ×1.1 | `items.ts:8070` | **no** — True Past, absent from flags |
| **POLKADOT_BOW** | Normal moves ×1.1 | `items.ts:8083` | **no** — True Past, absent from flags |
| **Fling secondaries** | flung Poison Barb poisons; flung King's Rock flinches; flung Light Ball paralyzes | `items.ts:508/3205/3417` (`fling.status`, `fling.volatileStatus`) | **yes** — `fling.status`/`fling.volatileStatus` are in flags |

Notes:

- **SPELL_TAG is the conspicuous hole in the type-boost family** — all 15 other
  Gen-2 damage-type items are present, but Ghost is missing, so a Spell Tag
  holder currently gets nothing. It is the one *behavioural* gap in an otherwise
  complete family.
- **LUCKY_PUNCH / STICK** are the crit items not covered by the Scope Lens work.
  The native `HELD_CRITICAL_UP` path is +1 and unconditional; these need +2 and
  a species gate. Scope Lens's `registerCritStageModifier` is the seam.
- **BERRY_JUICE** is a plain `onUpdate` consume-and-heal-20; the mod's
  `held_item.trigger` wrap is the natural home.
- **Fling secondaries** are a real sub-effect the mod's Fling
  (`modern_items.lua:342-380`) does not apply: it computes power, consumes the
  item, and prints "threw its X!" — but never applies the flung item's
  `fling.status` / `fling.volatileStatus`. This is the cleanest *API-backed* fix
  in the list, because the exact facts are already exported.

The two bows are True Past and therefore **cannot** be sourced from the API
(§2); their 1.1× Normal boost is a hand-written behaviour like any other.

---

## 5. Missing by construction (out of combat scope)

These ROM items have no combat behaviour and are correctly absent from the
combat layer; listing them prevents a future audit from re-flagging them:
`AMULET_COIN` (prize money, native), `LUCKY_EGG`/`EXP_SHARE` (growth, native),
`CLEANSE_TAG`/`SMOKE_BALL`/`EVERSTONE` (overworld/evolution), `SACRED_ASH`,
`UP_GRADE`/`DRAGON_SCALE`/`METAL_COAT` (evolution items — note METAL_COAT is
*also* a Steel boost and already wired as such), the balls, mail, apricorns,
TMs and key items.

Note the Showdown roster also contains ~330 modern items (Focus Sash, Air
Balloon, Weakness Policy, resist berries, etc.) that the Gen 2 ROM simply
cannot produce. Those are an *optional expansion* target in the shape of the
phase-2 batch, not gaps.

---

## 6. What is hardcoded, and why

Every hand-written data table in the item layer, with its justification and an
API verdict. The reason-code vocabulary mirrors the move audit.

| table | file:line | entries | why hardcoded | API verdict |
|---|---|---|---|---|
| `KNOWN_BERRIES` | `modern_items.lua:110` | 10 | no `isBerry` field in the ROM item schema; and the API omits all 10 as True Past (§2) | **keep** — genuinely unreplaceable |
| `ITEM_FLING_POWER` | `modern_items.lua:190` | 26 | originally hand-read from `items.ts` because no structured source existed at the time | **replace** — all 26 match `itemFlags(id).fling.basePower` exactly (verified), `BLACKBELT_I` via the rename map |
| `DEFAULT_FLING_POWER` | `modern_items.lua:199` | 1 | default for unlisted items | keep as fallback (or read `fling.basePower` with this default) |
| `BALL_ITEMS` | `modern_items.lua:118` | 13 | "project owns classification" | **replace + fix** — `itemFlags(id).isPokeball` reproduces 12 of them and exposes a bug: **`LIGHT_BALL` is wrongly listed as a ball**, so it is currently unflingable (`items.ts:3417`: Light Ball *is* flingable, 30 + paralysis) |
| `MAIL_ITEMS` | `modern_items.lua:124` | 10 | no schema field; used for both "unflingable" and "unremovable" | keep (Showdown has no mail-facts field; PokeAPI `category` is the only remote source) |
| `APRICORN_ITEMS` | `modern_items.lua:129` | 7 | same | keep |
| `KEY_ITEMS_HELD_UNLIKELY` | `modern_items.lua:134` | 8 | same | keep |
| `TYPE_BOOST_ITEMS` | `phase2.lua:123` | 15 | item→type coupling is not in the ROM schema, and `itemFlags` exports no "boosted type" field for these (it only carries `onPlate`/`onMemory`/`onDrive`/`naturalGift.type`) | **keep** — facts do not cover this; add `SPELL_TAG` |
| `SPECIES_TYPE_BOOST_ITEMS` | `phase2.lua:131` | 4 | same, plus species lock | keep |
| `NEW_ITEMS` registration | `phase2.lua:74` | 20 | national_dex explicitly does not register items | keep |

Also hardcoded-in-effect, though not a table: the type-boost *behaviour*
(`registerDamageModifier("held_item_type_boost", 90, ...)`, `phase2.lua:141`)
and every other item mechanic are hand-written, because the API carries no
behaviour. This is not a defect — it is the documented contract of
`itemFlags`.

### Summary of the "hardcoded and why"

Two genuinely different reasons hide behind the word "hardcoded" here, and the
report should keep them apart:

1. **Unavoidable** (no source exists): `KNOWN_BERRIES` (though *modern* berries
   could be classified via `isBerry`), the mail/apricorn/key-item tables, and
   the type-boost mappings. The API is a fact feed, and these facts simply are
   not in it.
2. **Provisional** (a source now exists): `ITEM_FLING_POWER` — and only
   `ITEM_FLING_POWER`. All 26 values are exactly reproducible from
   `itemFlags`, which means the table can be deleted in favour of a lookup.
   `BALL_ITEMS` is half-provisional: `isPokeball` covers 12 of its 13 entries
   and reveals the 13th is a classification bug.

---

## 7. Reproducing the audit

1. Parse `scratch/ndex/mod/data/items/generated/flags.lua` keys (one-line
   records, `KEY = { ... }`).
2. Parse `scratch/showdown/items.ts` top-level blocks (lines matching
   `^\t<key>: \{` … `^\t\},$`); a block's *behaviour keys* are every key that is
   not presentation (`name`, `spritenum`, `num`, `gen`, `isNonstandard`,
   `itemUser`, `shortDesc`, `desc`, `rating`, `entry`).
3. Read the ROM roster from `rom_manifest_gold.json`'s `itemOrder` (250 ids).
4. Normalize ids on both sides (`strip non-alnum, upper`); apply the single
   rename `BLACKBELT_I → BLACKBELT`; diff.
5. The residual sets are: ROM ids with flags (47), ROM ids without (203), and
   flagged items with behaviour but no flags record (52 — see §2's breakdown).
6. Verify the fling powers by reading `fling.basePower` per ROM item and
   comparing to `ITEM_FLING_POWER` (26/26 match).
7. Every Showdown line number in this document is the block's opening line in
   `scratch/showdown/items.ts`; every mod line number is the table/function
   declaration in `scratch/engine-extract/`.

No harness round was added for this audit — it is a document, not behaviour.
The next phase that acts on §4/§6 should add its own round, and should re-run
the fling/BALL_ITEMS replacement against `itemFlags` to prove the values agree
before deleting the tables.

---

## Follow-up (round 94)

The wiring this report planned is shipped — see `combat/MISSING_EFFECTS_PLAN.md`'s
"Item effects — phased wiring" section (phases 24-30) and the README's
"Item-effects wiring (round 94)" section. Before deleting the tables the report
named, the values were re-verified directly against `itemFlags`: all 26
`ITEM_FLING_POWER` entries match `fling.basePower` exactly, `isPokeball`
reproduces the twelve real Poké Balls (and excludes LIGHT_BALL, confirming the
report's bug call), and the API additionally covers 11 ROM items the old table
had omitted (the five evolution stones, SUN_STONE, UP_GRADE, SPELL_TAG,
THICK_CLUB and two more). `KNOWN_BERRIES` stays hardcoded, now layered with the
`isBerry` fact; the ten True-Past berries, the two bows and Berserk Gene are
supplied by the new `combat/modern_item_facts.lua` override table, which is also
the shared ROM->Showdown id bridge every item read now goes through.
