# Pokemon Platinum / Gen 4 — what is built, what is not

Tracking document for Gen 4 support. Updated as work lands; the "Status" table
is the short answer and everything below it is the reasoning.

---

## Status

| Stage | State |
|---|---|
| Cartridge recognised and hashed | **Done** |
| Registered in the launcher (tab, panel, accent) | **Done** |
| NDS filesystem reader (`NdsRom`) | **Done** |
| NARC archive reader (`NarcArchive`) | **Done** |
| Script command table, 840 opcodes (`Gen4ScriptOps`) | **Done** |
| Nine variable-length script commands | **Deliberately unresolved** |
| Text decode (`pl_msg.narc`, `Gen4Text`) | **Done** — 46,053/46,053 strings |
| Species records (`Gen4Species`) | **Done** — 508 records |
| Graphics: containers, LZ77, palettes, tiles, tilemaps (`Gen4Graphics`) | **Done** |
| Battle sprites — cipher **solved**, sprites decode | **Done** |
| Moves (`Gen4Moves`) — 471 records | **Done** |
| Items (`Gen4Items`) — 446 records | **Done** |
| Learnsets and evolutions (`Gen4Species`) | **Done** |
| Wild encounters (`Gen4Encounters`) — 183 areas | **Done** |
| Trainers and parties (`Gen4Trainers`) — 928 | **Done** |
| Packed trainer names (`Gen4Text`) | **Done** |
| Map matrix + land chunks + permissions (`Gen4Maps`) | **Done** |
| Map events: NPCs, warps, signs, triggers (`Gen4Events`) | **Done** |
| Map names (`Gen4Maps.mapNames`) — 593 | **Done** |
| Map 3D meshes (NSBMD) and BDHC height | Not started |
| Map header table (`Gen4MapHeaders`) — 593 in the ARM9 | **Done** |
| Script decoding (`Gen4Script`) — bytes to instructions | **Done** |
| Script lowering (`Gen4ScriptVM`) — 97.8% of instructions | **Done** |
| Extractor: cartridge to cache (`RomExtractorGen4`) | **Done** — 12 tables |
| Wiring the extractor into `RomImporter` | **Done** |
| Registering scripts per map through `MapScripts` | Not started |
| Script lowering to engine commands | Not started |
| Dual-screen + Poketch presentation | Designed, not built |
| Start-menu style switch | Designed, not built |
| `importable` flipped to `true` | **No** — see "What has to be true" |

The cartridge is **recognised but withheld**. A player who owns it can reach
Platinum's panel in the launcher and read exactly what is and is not ready,
rather than meeting "Not supported yet", which reads as "your dump is wrong"
and sends people hunting for another one.

---

## The cartridge, measured

Every figure here was read from the project's own dump, not copied from a
format note.

```
title        POKEMON PL          game code  CPUE      maker 01
unit 0       version 1 (Rev 1)   size       134,217,728 bytes (128 MiB)
used                             104,607,804 bytes
sha1         0862ec35b24de5c7e2dcb88c9eea0873110d755c
md5          ab828b0d13f09469a71460a34d0de51b

ARM9   rom 0x00004000  size 1,057,784  ram 0x02000000  entry 0x02000800
ARM7   rom 0x00409800  size   161,788
FNT    0x00431000 (7,092)      FAT  0x00432C00 (3,696) -> 462 entries
overlays  122 on the ARM9, 0 on the ARM7
filesystem  340 files in 89 directories
```

462 FAT entries = 122 overlays + 340 files, and the last byte any file
occupies is 104,607,804 — the used-size the header itself reports. The
filesystem walk accounts for the cartridge exactly.

Rev 0 (`ce81046eda7d232513069519cb2085349896dec7`) is registered as an
alternate hash. pokeplatinum builds both and the filesystem layout is the same
in each, which is what the extractor reads.

### Files that will matter

| Path | Bytes | What |
|---|---|---|
| `/fielddata/land_data/land_data.narc` | 16,125,840 | map terrain |
| `/poketool/pokegra/pl_pokegra.narc` | 11,778,676 | species sprites |
| `/msgdata/pl_msg.narc` | 4,351,320 | all text — 724 banks, 46,053 strings |
| `/data/mmodel/mmodel.narc` | 1,465,988 | overworld models |
| `/itemtool/itemdata/pl_item_data.narc` | 440,460 | items |
| `/fielddata/script/scr_seq.narc` | 304,476 | 1,124 script files |
| `/fielddata/encountdata/` | 237,324 | wild encounters |
| `/poketool/personal/pl_personal.narc` | 105,920 | 508 species records, 44 B each |

Message banks located by looking rather than assumed: **412** is species names
(entry 1 BULBASAUR, entry 25 PIKACHU), **706** is Pokedex entries.

Platinum keeps Diamond/Pearl's un-prefixed files beside its own `pl_`-prefixed
ones. The `pl_` file is the one to read; the other is the older game's.

---

## Staying legal

Identical to every other version here, and the reason the two new readers came
first.

* **No cartridge data is committed.** Not a table, not a tile, not a string.
* The ROM stays where the player keeps it. The importer reads it, writes a
  cache under `platinum/` (`cachePrefix`), and that cache is what the game
  loads through `CacheFs.mountVersion`.
* What lives in this repository is **scaffolding**: readers, tables of
  *offsets and shapes*, and code that knows how to ask the cartridge a
  question. Gen 4 does not change the rule; it only changes the question from
  "what is at address X" to "what is inside file Y".
* `Gen4ScriptOps.lua` is opcode numbers, command names and operand widths
  derived from pret/pokeplatinum — a description of the format, the same thing
  `Gen3ScriptOps.lua` is for Emerald. No script bytes from the cartridge.

---

## What is built

### `src/core/GameVersion.lua`

`platinum` registered: generation 4, both revision hashes, `cachePrefix
"platinum/"`, `saveSuffix "_platinum"`, `importable = false`, `experimental`,
and a new `dualScreen = true`. Two new predicates, `GameVersion.isGen4(id)`
and `GameVersion.isDualScreen(id)` — the second asked of the *version* rather
than computed from the generation, because "is Gen 4" and "has two screens"
are not the same claim and field code should say which one it means.

`GameVersion.ORDER` puts platinum after emerald and before the hacks:
cartridges in generation order, then romhacks.

### `src/import/RomImporter.lua`

Platinum has a chip in the tab row. **This is the only navigation into a
version's panel** — Prism was once registered without one and was hashed,
counted and completely unreachable, and the code comment saying so is still
there. Also:

* 128 MiB added to the accepted ROM sizes, `.nds` to the accepted extensions,
  and to all five native file pickers (macOS, Windows, zenity, kdialog, and
  the multi-select variants) plus the drag-and-drop hint.
* A `pokemon_platinum.nds` name for the panel, via a generation-4 branch.
* Chip colour `#a6b0d8 → #4a5286`: the metal with the cool cast the box art
  has, kept clear of Silver's near-white, Crystal's cyan and Polished
  Crystal's purple, because all four sit in one row.
* **A bug fixed on the way.** The "recognised, not playable yet" panel had one
  hardcoded sentence — *"Prism imports its data, but its scripts still
  misbehave"* — shown for **every** withheld game, under a comment reading
  "ONE SENTENCE PER GAME". Prism is importable now, so Platinum was about to
  become the only withheld game and its panel would have explained Prism.
  Replaced with `RomImporter.WITHHELD_REASON`, keyed by version.

### `src/import/NdsRom.lua`

The DS filesystem. `open` / `header` / `list` / `stat` / `read(path)` /
`readId` / `arm9` / `overlay(n)`.

A DS cartridge is a **filesystem, not an address space**, which is the single
biggest structural break from every generation above. `rom:u16(0x3DF884)` has
no meaning here; `rom:read("/poketool/personal/pl_personal.narc")` does.

It never loads the cartridge into memory. 128 MiB as one Lua string is a
number this engine has to run alongside on a phone, and nearly every stage
wants one file. The handle stays open and ranges are read on demand.

Two traps it avoids on purpose: the FNT is walked **by directory id**, not
linearly, because the subtables are not stored in tree order and a forward
walk builds a plausible tree with the wrong parents; and an overlay's bytes
come from the **file id at +0x18** of its table entry, not from the overlay
index, which are different numbers that look interchangeable.

### `src/import/NarcArchive.lua`

`parse(data)` / `count` / `range(i)` / `get(i)` / `all()`. Chunks are located
by walking, not by fixed offset — the header size is a field precisely because
it varies. Verified on two archives of very different shape: `scr_seq.narc`
(1,124 members) and `pl_personal.narc` (508 members of 44 bytes, which is
Platinum's species count and its personal-record size).

### `src/import/Gen4ScriptOps.lua`

All 840 opcodes, `$000`–`$347`, with names and operand specs.

Gen 4 reads its opcode as a **halfword**, not a byte — 840 commands do not fit
in one — so the smallest instruction is two bytes and a Gen 3 decoder fed Gen
4 bytes desyncs on the first command.

**Where the widths come from, and why that is the whole story.**
`Gen3ScriptOps.lua`'s header records what guessing cost: Emerald's `$E0` was
reasoned out from handler call shapes, came out two bytes short, and produced
not garbage but the Sootopolis cutscene playing twice with no warp home —
because a two-byte slip lands on a plausible opcode and the walk sails on. So:

* opcode numbers are the **order of the `ScriptCommand()` lines** in
  pokeplatinum's `include/data/scripts/scrcmd.h`. Position *is* the opcode,
  so all 840 are listed including dummies. Two of those lines are spelled in
  mixed case (`SCRCMD_GetExchangeServiceCornerItemAndCost` at `$2A2`,
  `ScrCmd_GETRANDOMBATTLEGROUNDTRAINERS` at `$2FB`); a reader matching only
  `[A-Z_]` silently drops them and shifts **every opcode after `$2A2` down by
  one** — the same class of failure, one level up. This was hit and fixed.
* operand widths are the stream reads in each handler body, in source order.
  The five primitives consume fixed widths (`ReadByte` 1, `ReadHalfWord` 2,
  `ReadWord` 4, and the inlines `GetVar`/`GetVarPointer` 2 each, both
  `ReadHalfWord` underneath).

**The two ways that could still be wrong, both measured:**

1. A handler reading inside an `if` has no fixed width. Nine do. They are
   marked `*` and listed in `VARIABLE_LENGTH` — **not guessed**.
2. A handler delegating its read to a helper would hide operands. Every
   function in pokeplatinum taking a `ScriptContext *` and transitively
   reaching a stream read was collected, and every handler body checked
   against that set: **zero** handlers delegate.

**Corroboration, which is not proof.** Walking all 1,124 members of
`scr_seq.narc` from all 4,079 entry points decodes 50,835 instructions across
381 distinct opcodes and reaches a clean `end` **4,070 times with no unknown
opcode**; 8 stop at a variable-length command and 1 runs past its member's end
(one member's header parse, listed under open questions). Gen3ScriptOps
explains precisely why this is corroboration and not proof. The proof is the
handler source; the corpus only shows nothing contradicts it.

### `src/import/Gen4Text.lua`

All of Platinum's text: 724 message banks, 46,053 strings. Each bank is
encrypted **twice** — once on its table of offsets and lengths, again with a
different key on the characters:

```
entry table:  k = (seed * 765 * (i+1)) & 0xFFFF;  k |= k << 16
              offset ^= k;  length ^= k          (length counts CHARACTERS)
characters:   key = ((i+1) * 596947) & 0xFFFF
              each u16 ^= key;  key = (key + 18749) & 0xFFFF
```

Both keys stay in 16 bits. In pokeplatinum's C the character key is a **u16
parameter** immediately overwritten by a 32-bit product, so the truncation is
the declaration doing it — and a 32-bit key decodes the first character
correctly and then drifts, which reads as a charmap problem rather than a
cipher one.

**Why this one is known to be right, unlike a script table.** All 46,053
strings decrypt and all 46,053 end in the `0xFFFF` terminator. A wrong key
does not land on a terminator by accident forty-six thousand times, and text
either reads or it does not — there is no plausible-but-wrong here. A second,
independent Python implementation was run over the whole cartridge and
compared line for line against the Lua: **zero differences**.

Escapes: `0xFFFE` introduces `command, argc, args...`; if the command's high
byte is a STRVAR base its low byte is the variable index. 68 distinct escape
commands occur in the cartridge and **every one is covered** — no unknown
control codes anywhere. `0xF100` starts a bit-packed trainer name terminating
on `0x01FF` (885 strings); not decoded yet, marked and stopped rather than
printed as characters.

### `src/import/Gen4Graphics.lua`

Nitro containers and the LZ77 the cartridge wraps most of them in. Magics are
stored reversed, like NARC's chunk tags: `RLCN` = NCLR (palette, section
`TTLP`), `RGCN` = NCGR (tiles, `RAHC`), `RCSN` = NSCR (tilemap, `NRCS`),
`RECN` = NCER (cells). Sections are found by walking from `headerSize` for
`sectionCount` chunks — both fields exist because they vary.

Two things believed from arithmetic rather than from a field:

* **Bit depth**, because `tilesX * tilesY * 32 == dataSize` settles 4bpp
  outright and cannot be misread.
* **Colour count**, as `dataSize / 2`. The palette depth field is the one
  field here whose meaning did not survive inspection — a 16-colour Platinum
  palette carries `4` where the published tables say `3` — and since the byte
  count is unambiguous, nothing needs the enum to be right.

`tilesX`/`tilesY` are `0xFFFF` on an **unsized** sheet (every party icon is
one); the tile count always comes from the byte count instead.

**Validated by looking, not counting.** All 540 party icons in
`pl_poke_icon.narc` render as recognisable Pokémon in the right colours. The
LZ was run over every compressed member of four graphics archives: **125 of
125** decompress to exactly their declared size and each one turns out to be a
valid Nitro container (48 NCGR, 27 NSCR, 23 NCER, 23 NANR). And a second,
independent Python implementation was compared pixel for pixel across all 540
icons — 1,105,920 pixels, **zero differences**.

That cross-check earned its keep immediately: it caught a real bug in the Lua,
where the tile `dataOffset` (which is relative to the start of the section's
*fields*) had the 8-byte tag/size header added a second time. That does not
crash — it produces recognisable shapes displaced by a quarter tile, which is
exactly the kind of wrong that survives a glance.

### `src/import/Gen4Species.lua`

508 records of 44 bytes from `pl_personal.narc`, with names from bank 412.
The 44 summing exactly is the check that the layout is read right, and the
values agree with the published tables (Pikachu 35/55/30/90/50/40 with
Static; Giratina 150/100/120/90/100/120; Arceus 120 across).

**One trap worth naming:** the stat order is hp, attack, defense, **speed**,
spAttack, spDefense. Speed is fourth, not last. Reading it in the display
order every stat screen uses swaps Speed with Special Attack and produces a
table that looks entirely plausible and is wrong for every species.

This stage also proves the floor: cartridge → `NdsRom` → `NarcArchive` →
record + `Gen4Text`, four modules and no special cases.

### `src/import/Gen4Moves.lua` and `src/import/Gen4Items.lua`

471 moves of 16 bytes from `pl_waza_tbl.narc`; 446 items of 34 bytes from
`pl_item_data.narc`. Names come from message banks 647 and 392, both found by
looking rather than assumed.

**Priority is signed.** Quick Attack is +1 and Roar is −6, and reading that
byte unsigned turns every negative-priority move into one that goes first —
no crash, no visual glitch, nothing a battle looks obviously wrong for. It
just quietly plays a different game. Verified: Quick Attack +1, Roar −6.

Item record checks against the published tables: Master Ball 0, Ultra Ball
1200, Poké Ball 200, Potion 300, HP Up 9800. Moves: Pound 40/100/35 normal
physical, Thunderbolt 95/100/15 electric special, Hyper Beam 150/90/5,
Struggle 50 power with 0 accuracy and 1 PP.

### Learnsets and evolutions (in `Gen4Species`)

`wotbl.narc` holds one **variable-length** learnset per species — 24 to 36
bytes, terminated by `0xFFFF`. Each entry is a u16 packing the move in the low
**9** bits and the level in the high **7**. That split is forced: 467 moves
need 9 bits and level 100 needs 7. Reading it the other way round gives move
ids under 128 at levels in the hundreds — a table that still looks plausible.

The structural check is what confirms it: across all 493 species, **6,598
learnset entries, zero move ids out of range and zero levels outside 1–100**.

`evo.narc` holds seven `{method, param, target}` slots per species in 44 bytes.
**Every method number was derived from the cartridge and checked against a
species that can be named**, because the enum lives in a generated header
pokeplatinum builds and does not ship — there was nothing to copy. Grouping
all 246 evolutions by method identified each one: 1 friendship (Golbat,
Chansey, Pichu), 4 level (162 of them), 8/9/10 Tyrogue's three branches,
11/12 Wurmple's personality split, 15 Feebas at beauty 170, 18 Happiny by day
and 19 Gligar by night, 20 knows-move (Aipom/Double Hit), 21 species-in-party
(Mantyke/Remoraid), 24 magnetic field, 25/26 the mossy and icy rocks.

`param` means a different thing per method — a level, an item, a move, a
species, or nothing — so `paramKind` says which. A caller that treats it as
one thing gets Pikachu evolving at level 83.

### `src/import/Gen4Encounters.lua`

183 areas of exactly 424 bytes — and that 424 is the check, because
pokeplatinum's `WildEncounters` struct sums to 424 to the byte.

Two things that look like mistakes and are not. **Species ids are four bytes
here**, not the two they are everywhere else in the cartridge, with three
bytes of padding after each one-byte grass level; reading them as u16 halves
the stride and walks the table into itself. And **a water slot stores maximum
level first, then minimum** — the cartridge really does put the larger number
first, and reversing it prints "Lv55-30", which reads as a display bug rather
than a parse one.

Twelve of the 183 areas have a grass rate of 0 with the whole grass table
zeroed: water-only routes, where level-0 slots are correct data. Validated on
that basis — 2,196 grass slots, zero species out of range, and **zero
out-of-range levels in any area whose rate is non-zero**. The first land area
comes out Geodude, Zubat and Onix at levels 4–8, which is Oreburgh Gate.

### `src/import/Gen4Trainers.lua`

`trdata.narc` (928 × 20-byte headers) and `trpoke.narc` (928, variable) share
an index and are meaningless apart.

**The header's `monDataType` sets the party stride, and it must be read rather
than inferred by dividing the party file by the party size.** Dividing works
for 887 of the 928 and then quietly does not: 39 party files carry trailing
padding, so the division lands on 12 or 20 where the real stride is 10 or 18,
and every mon after the first comes out shifted. Reading `partySize` entries
at the type's own stride and ignoring the remainder is correct for all 928.

`species` also carries the form in its high bits, so the id is the low 10 —
which matters for Wormadam cloaks and Rotom appliances.

Validated across the whole archive: **1,878 party members, zero species,
level, move or item values out of range.** Roark comes out Geodude 12 / Onix
12 / Cranidos 14 with Stealth Rock; Cynthia's six are right down to Garchomp
at 62 holding a Sitrus Berry.

### Packed trainer names (closing the last text gap)

Bank 618 has exactly 928 entries — which is how it was identified as the
trainer-name bank — and 885 of them use the `0xF100` sub-format that was
deferred earlier.

A packed name is **nine bits per character inside fifteen usable bits** of
each halfword, not sixteen, so characters straddle halfword boundaries and one
bit per halfword is skipped. It terminates on `0x01FF`, not `0xFFFF`. Both
oddities matter: packing into 16 bits decodes the first character correctly
and then drifts (which reads as a charmap problem), and watching for `0xFFFF`
means never stopping, so the name runs on into whatever follows.

All 885 decode with no unmapped character, every gym leader resolves, and the
full 46,053-string corpus was re-diffed against the independent Python
implementation afterwards — still zero differences.

### `src/import/Gen4Maps.lua`

**This is where Gen 4 stops resembling every generation above it.** Gen 1–3
give you a map: a grid of metatile ids plus a tileset, and the renderer draws
it. Gen 4 gives you a *matrix* of fixed 32×32 chunks, and each chunk carries a
movement-permission grid, a list of placed building models, a **3D mesh**, and
a separate height structure. The picture is a mesh, not a tilemap — but the
permission grid is a plain 32×32 array of u16, and that alone is enough to
know where the player may walk.

**The matrix** (`map_matrix.narc`, 289 members):

```
u8 width, u8 height, u8 hasHeaders, u8 hasAltitude, u8 nameLength, char name[]
u16 headers[w*h]    -- only when hasHeaders
u8  altitudes[w*h]  -- only when hasAltitude
u16 mapIds[w*h]     -- always; indexes land_data.narc
```

The two optional blocks are why this has to be parsed rather than indexed: a
reader that assumes they are present takes the map ids out of the header table
and builds the world from the wrong chunks. **All 289 members account for
their length exactly** under this layout — that is the check. Matrix 0 is
30×30 and named `map`: the Sinnoh overworld.

**The chunks** (`land_data.narc`, 666 members): four u32 sizes, then
permissions, objects, an `BMD0` NSBMD mesh, and a `BDHC` height block. All 666
satisfy `16 + the four sizes == file length`, all 666 have a 2048-byte
permission block, all 666 carry a BMD0 model.

**Permissions**: one u16 per tile. Bit 15 marks a tile that is not part of the
map — the void around the land — and the low byte is the terrain behaviour.
Across the whole overworld only 54 distinct values occur and only **two**
distinct high bytes, which is what says bit 15 is a flag and not part of a
number.

**Validated by looking.** The 30×30 matrix assembled into a 960×960 permission
image is recognisably Sinnoh: Mt. Coronet running north–south through the
middle, the three lakes as enclosed pockets, the Great Marsh's grid at
Pastoria, Route 223's water column up the east coast to the Battle Zone. A
layout error anywhere in the matrix or the chunk header would have scrambled
that beyond recognition. The Lua render was then compared pixel-for-pixel with
an independent Python one: the only differences are the 432 empty matrix cells
where one drew black and the other drew the void colour — **every real
permission value agrees**.

**Objects** are 48 bytes each, and the offsets were not read off one sample:
every field of all 3,476 placed objects was tabulated. That is what pins the
scale at +28/+32/+36 rather than the +24/+28/+32 a hand-read hex dump
suggested — an error that silently produced `scale 0.0`. Fields +16/+20/+24
are **always 0** and are left unnamed on purpose: they are almost certainly a
rotation, but with every object in the game at zero there is nothing to tell a
rotation from a reserved field, and naming one would be a guess dressed as a
fact. All 360 distinct model ids fall inside `build_model.narc`.

### `src/import/Gen4Events.lua`

`zone_event.narc`, 534 members — who stands on a map, where its exits go, and
what watches the player.

**The counts are interleaved**, not four counts up front: each block is a u32
count immediately followed by its own records.

```
u32 n; Sign[n]     20 bytes      u32 n; Warp[n]     12 bytes
u32 n; Npc[n]      32 bytes      u32 n; Trigger[n]  16 bytes
```

Reading four counts first looks right on member 0 — sixteen zero bytes, which
is an empty map either way — and then falls apart on every populated map. The
interleaved layout accounts for **all 534 members exactly**, and it is the
only combination in a search over every stride from 8 to 40 that does; the
next best fits fewer than 15.

**Which block is which was settled by measurement, not by position:**

* **NPCs** — all 3,555 records have a model id below 470, exactly the member
  count of `mmodel.narc`, the overworld model archive.
* **Warps** — 1,207 of 1,213 have a destination below 593, the number of names
  in `mapname.bin`; the other six are 4095, a "nowhere" sentinel. The fields
  at +0/+2 reach 909, so they cannot be map ids and are coordinates.
* **Triggers** — **all 186** carry a value at +14 of `0x4000` or above, which
  is Gen 4's variable space. A trigger is a variable, a value to match, an
  area and a script.
* **Signs** — the remaining block, and the one identification here that is
  inference rather than proof. Its records carry a script id, a position (+4
  and +8 are u32: the halves at +6 and +10 are zero in all 682) and a small
  type field, which is the shape of an interactable. Labelled as such, with
  that caveat kept in the source.

Validated across every zone: 534 parsed exactly, zero failures, zero NPC
models outside `mmodel`, zero warp destinations outside the name table, zero
triggers below the variable base. Spot-checking one city's warps resolves them
to its two routes and its Pokémon Center by name.

`Gen4Maps.mapNames` reads `mapname.bin` — 593 sixteen-byte zero-padded ASCII
names, which is the count every warp destination stays below.

### `src/import/Gen4MapHeaders.lua`

Every other Gen 4 table lives in the filesystem and opens by name. This one
does not — it is compiled into the **ARM9 binary**, and it is the record that
ties a map to its matrix, area data, script file, text bank, wild encounters,
events and music. Without it the other modules each read correctly and none of
them knows which map it belongs to.

593 records of 24 bytes, matching pokeplatinum's `MapHeader`.

**Found by searching, not by a hardcoded offset.** In this cartridge it sits
at ARM9 offset `0x0E601C` (RAM `0x020E601C`), but that is a fact about one
build — Rev 0 is a different binary, and a fixed offset there would read
whatever happens to live at that address and hand back 593 confident, wrong
records. `find` scans for a run of 24-byte records whose every field indexes
*inside* the archive it names: matrix < 289, events < 534, scripts < 1124,
messages < 724, encounters < 183 or the 0xFFFF sentinel, area < 75.

**Why 593 and not 594.** A loose filter finds 594 consecutive plausible
records; the 594th is not a map. Tightened against the area-data archive it
fails immediately, while all of 0..592 pass **every** cross-check against six
separate archives. 593 is also exactly the number of entries in
`mapname.bin`. Taking the loose answer would have added one phantom map — the
kind of off-by-one that only surfaces when something walks the whole table.

The strongest confirmation is coverage rather than shape: the 593 headers
between them reference **all 534** members of `zone_event.narc`, highest index
533, none left over and none out of range.

#### A join that succeeded and was wrong

`mapLabelTextID` indexes **message bank 433** — 126 display names, "Jubilife
City", "Old Chateau", "Rock Peak Ruins". It does *not* index `mapname.bin`,
which is a separate table of 593 **internal** identifiers keyed by the header
id itself: `C01`, `C05GYM0113`, `D25R0106`.

Both tables have an entry for every map, so joining `labelText` to
`mapname.bin` never errors and never looks broken — it just quietly reports
that Jubilife City is called "C01PC0101". The bound that made it look correct,
`labelText < 593`, holds trivially: `labelText` never exceeds 125. This was
caught by checking a name against the game rather than against a range.

With both joins right the chain reads: header 3 is **Jubilife City** (`C01`)
on the 30×30 overworld matrix with 33 NPCs and 14 warps, bike, run and fly all
allowed; header 100 is **Hearthome City**'s gym (`C05GYM0113`), 1×1, none of
the three allowed; header 300 is the **Old Chateau** (`D25R0106`) with
encounter table 130.

#### And the event structs corrected an axis mistake

pokeplatinum's `MapHeaderData` names its four event arrays `bgEvents`,
`objectEvents`, `warpEvents`, `coordEvents` — in exactly the order the file
stores them, which confirmed the block identification including the one that
had only been inferred. The structs also showed that measuring alone had
produced the right fields with the **wrong axes**: Gen 4 is 3D, so the two
horizontal axes are X and **Z**, and **Y is height**. The byte census found
the height fields sitting at zero on most events and filed them as padding;
they are not, and an object event's height is a 20.12 fixed-point value at +28
rather than the u16 at +30 a census suggested. A census tells you which bytes
vary. It cannot tell you what they mean.

### `src/import/Gen4Script.lua`

`Gen4ScriptOps` says how wide every command is; this walks a real script file
with it and produces instructions — opcode, name, operands, and for a jump the
absolute target rather than the relative offset the cartridge stores. Lowering
sits on top of this; nothing here decides what a command *means*.

**A member is not a script.** Each of `scr_seq.narc`'s 1,124 members holds
several scripts behind a header of u32 offsets that are relative *to the
position after the offset word*. The header ends either at the halfword
`0xFD13` or, more often, simply where the first script begins — there is no
count. So the walk stops when the cursor reaches the lowest target seen, the
only rule that works for both shapes. Reading a count that isn't there takes
the first script's opcodes as more offsets.

**Jumps are signed and relative to the end of the instruction.** `goto` and
`call` measure from the byte *after* the operand, and the offset is negative
for every backward jump, which is most loops. Reading it unsigned sends a loop
several gigabytes forward and the decode just stops — which looks like a short
script, not a misread operand.

**How the jump formula was checked**, since a decoder that reads its own output
will agree with itself all day: starting at every entry point and following
every jump **transitively** reaches 8,567 basic blocks and 78,093 instructions
— twice what a linear walk sees — and of the **15,002 jump operands in them,
zero point outside their own member**. 8,549 of those blocks then decode to a
clean `end`.

That tests two things at once. A wrong sign or base would scatter targets to
negative numbers and gigabyte offsets; a wrong operand width anywhere earlier
in an instruction would shift the jump operand itself and produce the same
mess. Neither happens. Four blocks of 8,567 stop unexpectedly — two run off the
end, two reach an opcode not in the table — which is 0.05%, recorded rather
than smoothed over.

**Coverage, which is what makes lowering plannable:** 4,079 scripts from the
entry points, 50,835 instructions, 381 distinct opcodes.

| commonest N opcodes | share of instructions | scripts fully covered |
|---|---|---|
| 20 | 87.3% | 58.3% |
| 40 | 95.9% | 78.4% |
| 80 | 98.3% | 88.7% |
| 150 | 99.3% | 94.5% |

The top of that list is the shape of a conversation — `lockall`, `faceplayer`,
`message`, `closemessage`, `releaseall` — so a lowering that starts there gets
NPCs talking before anything else works. Decoding a real one gives a Poké Mart
clerk: `playse / lockall / faceplayer / callcommonscript / closemessage /
pokemartcommon / releaseall / end`.

### `src/script/Gen4ScriptVM.lua`

A sibling of `Gen3ScriptVM` by design: `ScriptRunner` and `Commands.resolve`
are generation-agnostic, so a fourth generation needs a lowering and a verb
set, not a fourth script subsystem. Shared verbs (`jump`, `label`,
`show_text`, `ask`, `set_flag`, `play_sound`) are emitted as-is; anything Gen 4
does that no earlier generation has gets a `g4_` verb, exactly as Gen 3 uses
`g3_`.

**Measured against the whole cartridge** — 4,079 scripts, 50,843 instructions —
it lowers **97.8% of instructions** and leaves **85.7% of scripts** with
nothing unimplemented in them at all.

It got there in three passes, and their shape is the useful part:

| pass | instructions | whole scripts |
|---|---|---|
| the conversation set | 87.8% | 52.7% |
| + 8 (trainer preamble, signposts) | 97.3% | 82.4% |
| + 10 load-bearing | 97.8% | 85.7% |

The conversation set alone reached 87.8% of instructions but only 52.7% of
whole scripts, because **a script is only as lowered as its worst command**.
The eight added next were the four generated trainer-battle commands — each
occurring exactly 928 times, once per trainer in `trdata.narc` — and the four
that drive a signpost, which have to lower together or a sign opens and never
closes.

The last ten occur twenty-odd times each and are load bearing anyway: `warp`,
without which the player cannot leave a map; `starttrainerbattle`, without
which the trainer preamble runs and nothing happens; `pokemartcommon`, without
which the clerk says hello and sells nothing. **Frequency is a good guide to
what to lower first and a poor guide to what to stop at.**

What remains is a flat tail of side systems — TV interviews, the journal, the
Battle Tower, Turnback Cave, the Poketch — at a few dozen occurrences each,
left as explicit `g4_unimplemented` rows rather than dropped. A silently
dropped command is a script that runs and quietly does the wrong thing, which
is much harder to find than one that reports what it could not do.

The Poké Mart clerk now lowers completely:

```
{ play_sound, 1500 } { g4_lock_all } { g4_face_player } { g4_common, 2019 }
{ g4_close_message } { g4_pokemart, 1 } { g4_release_all } { jump, end }
```

**What is not here:** this is the lowering half. The extractor half — writing
a script pool into `data/generated` and registering a contribution per map
through `MapScripts` — is not built, so nothing calls this in a running game
yet.

### `src/import/RomExtractorGen4.lua`

Eleven modules read Platinum correctly and none of them wrote anything. This
is the stage runner that puts them in order and lands their output in
`data/generated`, which is what `CacheFs.mountVersion` serves to a running
game.

**It takes a path, not the ROM's bytes** — the one place it deliberately does
not look like `RomExtractorGen2` and `RomExtractorGen3`. Those are handed the
whole cartridge as a Lua string, which is fine at 32 MiB. Platinum is 128 MiB,
the engine has to run alongside it on a phone, and almost every stage wants
*one file* out of a filesystem. `NdsRom` reads ranges on demand; handing it a
128 MiB string would undo that before the first stage ran.

**Measured end to end against the cartridge: 4.2 seconds, 12 tables.**

| table | entries | | table | entries |
|---|---|---|---|---|
| `gen4_text` | 724 banks | | `gen4_map_headers` | 593 |
| `gen4_species` | 508 | | `gen4_map_matrices` | 289 |
| `gen4_moves` | 471 | | `gen4_map_permissions` | 666 |
| `gen4_items` | 446 | | `gen4_map_objects` | 387 |
| `gen4_encounters` | 183 | | `gen4_events` | 534 |
| `gen4_trainers` | 928 | | `gen4_scripts` | 873 / 8,567 blocks |

Every count matches what the individual modules measured independently, and
the spot checks land: Pikachu with 90 base speed, 13 learnset moves and one
evolution; Thunderbolt at 95; Potion at 300; Roark with three Pokémon;
map header 3 as Jubilife City (`C01`) on matrix 0.

Two shape decisions worth naming. Permissions are stored as **one binary
string per chunk** rather than 1,024 numbers — the same choice Gen 3's map
grids make, because a 666-entry table of thousand-element arrays is slow to
load and enormous on disk while a string is neither. And **lowering does not
happen here**: the pool holds decoded instructions and `Gen4ScriptVM` lowers
at load time, so a lowering fix does not require re-importing the cartridge.

The script pool follows jumps as well as entry points — a block reached only
by a `goto` is still a block the runner needs — which is why it holds 8,567
blocks rather than the 4,079 a linear walk finds.

### Wiring it into `RomImporter`

The extractor dispatch already anticipated this. Its comment reads *"Adding a
fourth generation should be a line here, not a bug"* — and it very nearly was
one line:

```lua
[4] = { module = "src.import.RomExtractorGen4", takesVersion = true,
        takesPath = true },
```

`takesPath` is the part that made it more than a line. `startData` now takes an
optional `sourcePath`, and `startPath` passes the whole path rather than
reducing it to a basename. Verification is unchanged — hashing a cartridge
means hashing its bytes and there is no way around that — but the moment the
SHA-1 matches, a Gen 4 import releases the 128 MiB string and hands the
extractor a path instead. Dropping the bytes *there* rather than after the run
is the entire point; keeping them live through extraction would have gained
nothing.

**A dropped file may have no path.** `love.filedropped` gives a File whose
`getFilename` is a real path on desktop and need not be anywhere else, and the
Android save-directory scan reads through `love.filesystem` rather than the
disk. A Gen 4 import that gets that far without a path now fails with a
sentence telling the player to use the Import button, instead of passing `nil`
into `new` and failing inside `NdsRom` with something about a missing ROM
path.

---

## What remains, in dependency order

1. **NCER cell banks** — how an unsized sheet is assembled into a sprite.
   Needed for overworld and battle sprites; the container already parses.
2. **Map meshes** — the NSBMD (`BMD0`) in each chunk and the `BDHC` height
   block. The 3D half of the map problem; the permission grid means a walkable
   world does not wait on it.
3. **Registering scripts per map** through `MapScripts`, which is what makes
   `Gen4ScriptVM`'s lowering reachable from a running game. This is the last
   piece before a Platinum import produces something playable.
4. **Overworld models** — `mmodel.narc`, NSBMD. Deferred: a 2D stand-in gets
   the game walkable long before the model pipeline is worth building.

### What has to be true before `importable = true`

Text decodes, graphics decode, species/items/moves load, at least one map
builds and is walkable, and the common scripts lower well enough to talk to an
NPC. Anything less produces a cache the engine mounts and then fails inside,
which is the outcome the withheld flag exists to prevent.

---

## Dual screen and the Poketch

Design; not built. The requirement is that the second screen is **never a
second window** — the game runs in one window like every other version here,
and the player chooses how the bottom screen reaches them.

### Second-screen modes (switchable at runtime, and in Options)

**1. Swap (default).** One screen is drawn at full size; a key toggles which.
Simple, works at any window size, works on a phone. The DS's own split is
approximated by the fact that the bottom screen is almost never needed
*during* an action — the Poketch and the bag are things you stop to look at.

**2. Inset.** The bottom screen is drawn as a panel in the **top-right
corner** over the main screen, shown and hidden with a hotkey. It is
**interactive in place** — clicks and taps inside the panel go to the bottom
screen's own coordinate space, so the Poketch's buttons, the bag and the touch
controls work without swapping away. Its **size is adjustable** (a scale
setting, and a drag handle on its corner), and it remembers where and how big
it was per version.

**3. Both.** Stacked as the hardware had them, for players who want the
authentic layout and have the window height for it. Offered but not the
default, because at typical window sizes it makes both screens small.

Notes for implementation: the inset panel needs its own input routing (a hit
test before the field's, and pointer coordinates transformed into
bottom-screen space) and its own render target, so field rendering does not
have to know it exists. `GameVersion.isDualScreen(id)` is the gate; nothing
about this should be reachable for Gen 1–3, and no Gen 1–3 draw path should
gain a branch.

### The Poketch

The Poketch is one of the things the bottom screen *shows*, not a third
screen. It gets a slot in the second-screen surface alongside the bag, the
map and the touch controls, and the same hotkey that raises the bottom screen
raises whatever that surface is currently showing. A separate direct hotkey to
raise the Poketch specifically is worth having, since it is the thing players
check most often.

### Start menu

Two styles, player's choice, default to the first:

**1. Main-screen menu (default).** The start menu appears on the main screen
exactly as it does in Red through Emerald — same position, same behaviour,
same keys. This makes Platinum feel continuous with the rest of the launcher's
library and means muscle memory carries over.

**2. Bottom-screen menu.** The authentic DS arrangement, for players who want
it. Uses whichever second-screen mode is active, so on Inset the menu appears
in the corner panel and is clickable there.

The setting belongs with the other per-version options and should be
switchable mid-game, not only at boot.

---

## Mod compatibility

Gen 4 must not disturb the four generations already working. Where things
stand:

* Everything added so far is **new files plus additive registration**. The
  only edits to shared code are in `RomImporter` (one chip, the accepted
  sizes and extensions, one bug fix) and `GameVersion` (one entry, two new
  predicates). No Gen 1–3 branch changed behaviour.
* Mods reach content through the same registries regardless of version, so a
  mod that adds text or sprites should work once Gen 4 populates those
  registries. Mods that hard-code Gen 3 asset ids will not, and should not —
  they are version-specific by construction.
* **A known, pre-existing hazard to keep in mind:** `DRAMATIC_SHAPE` asks for
  `TILESET_03DF704` (Emerald's primary) during FireRed sessions — a mod
  carrying state across a version switch. Gen 4 will make that class of bug
  more visible, not less. Worth fixing before Platinum is playable.

---

## The battle sprites (solved)

`pokegra` and `otherpoke` needed **two** things, and each one disguises the
other.

**1. They are encrypted.** The keystream is the series' usual LCG:

```
key = the FIRST halfword of the tile data
each halfword:  plain = cipher ~ key;  key = (key * 0x41C64E6D + 0x6073) mod 2^16
```

Only the low 16 bits of the state ever matter, so no 32-bit arithmetic is
needed. The first halfword being the key is the same statement as "the picture
starts with transparent pixels", since anything XORed with itself is zero —
the stream is self-seeding and there is no key table anywhere.

**2. They are linear bitmaps, not tiles.** The NCGR layout flag (low byte of
the field at section+20) is `1`, meaning rows of pixels rather than 8×8 tiles.
Measured across every NCGR in the cartridge: 3,872 tiled against 4,160 linear,
and the split is not arbitrary — every sprite archive (pokegra, otherpoke and
the trainer sheets `trfgra`/`trbgra`) is linear; fonts, icons and backgrounds
are tiled. The trainer sheets are linear but **not** encrypted (raw entropy
4.8–5.3), which is how the two properties were separated.

Decrypt without un-tiling and you get real Pokémon colours smeared into
horizontal bands, which reads as "the cipher is nearly right". Un-tile without
decrypting and you get noise, which reads as "the layout is fine, the cipher is
wrong". Neither is a clue about the other.

**How it was found, because the wrong way round wasted real time.** The
published constants were tried and appeared to fail; then all eight
combinations of seed source, direction and key half; then a brute force over
all 65,536 seeds. Every one of those was scored against **member 0 of
pl_pokegra — a placeholder that decrypts to noise no matter what you do to
it.** The algorithm had been right from the first attempt and the test subject
was the problem.

What settled it was not another guess. Assume the leading plaintext is zero,
read the leading ciphertext *as* the keystream, and solve
`k[i+1] = (k[i]*A + C) mod 2^16` for `A` and `C` from the values themselves.
34 of 38 sprites gave `A = 0x4E6D`, `C = 0x6073` — exactly the published LCG —
and the four that disagreed are the ones whose first tile is not blank, so the
"keystream" read from them included picture. **Solving beats searching when
the unknown is small, and a failing test needs its subject checked before its
hypothesis.**

Result: 194 of 194 front sprites decode, none blank, mean transparency 77.3%,
and the rendered sheet is correct Kanto through the legendary birds. The icon
path was re-diffed after the change — zero pixel differences, so the tiled
path did not regress.

## Open questions and known gaps

* **Nine variable-length script commands** (`DOSTRENGTHFUNC`, `DOFLASHFUNC`,
  `DODEFOGFUNC`, `DOGROUPCONNECTIONACTION`, `CALLTVBROADCAST`,
  `CALLTVINTERVIEW`, `MYSTERYGIFTGIVE`, `$27C`, `GIVEPOFFIN`). Each needs its
  handler read individually. The decoder should **refuse** a command it cannot
  size rather than walk past it — a guessed width here is the Sootopolis bug
  again.
* **One script entry point of 4,079** runs past the end of its member. Almost
  certainly one member whose header is parsed slightly wrong rather than a
  table error, since no opcode desynced. Needs a look.
* **`RomImporter:startData` takes the whole ROM as a Lua string** and hashes
  it. At 128 MiB that is tolerable while the import is refused anyway, but the
  real Gen 4 extractor must not go through it — it needs a path-based route
  into `NdsRom`, which already reads on demand. **Design this before writing
  the extractor, not after.**
* **Rev 0 is registered but untested** — no dump on hand. The layout should be
  identical; it has not been confirmed.
* Gen 4's save format is untouched. `saveSuffix "_platinum"` reserves the
  slot and nothing else.
