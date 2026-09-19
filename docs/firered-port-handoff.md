# FireRed port — session handoff

Branch `firered-port` in this repo (`D:\gen1recomp-0.1.75-windows\gen2recomp-firered`).
Read this whole file before touching code — it's written so a fresh session
(no prior context) can pick the work back up without re-deriving anything.

Last commits, newest first:
```
0a4e087 FireRed: finish Item PC and Mum parity
bc961a5 FireRed: enforce cartridge warp trigger rules
868d7ec Docs: log three reopened manual-play reports and the prompt to fix them
4daa52a Docs: close the pre-PR sweep with the Gen 1 / Emerald inventory
dd5d701 Gen3: stop the PP-item move picker falling into the Game Boy list
b8c2292 Docs: re-check the three reopened PC/NPC items live
921e852 Docs: log the PC item storage fix
aa9bb40 FireRed: give the PC's item storage FireRed's list, not the Game Boy's
71343ac Docs: log the directional warp fix and open the pre-PR sweep
8008c6f FireRed: fire arrow/stair warps from the walk, not the arrival
9a3fbcf Docs: reopen manual FireRed PC and NPC issues
d1cedf8 FireRed: use Gen3 PC menu and constrain NPC movement
0d869e5 Dramatic Shape: complete B30 Pokemon Tower profile
dc5a3e0 FireRed: preserve Gen3 command overrides
6525abf Docs: verify FireRed FLY bird sprite
6603a21 FireRed: use the real FLY bird sprite
8d00cca Docs: verify FireRed naming-screen fidelity
eb86f72 FireRed: match naming-screen icons
384269d Docs: verify FireRed FLY round trip
d8b92bc FireRed: open Town Map for FLY
7331cfd Docs: close FireRed final handoff checklist
a266457 FireRed: close gameplay and visual parity gaps
d6cba1c FireRed: implement V.S. Seeker rematches
72e94be FireRed: credit Tranzue for the port
e90de37 FireRed: allow immediate exits from house mats
2fcd262 FireRed: route imported wild battle commands
157a4c3 FireRed: give yes-no menu a full lower row
ac35ca8 FireRed: keep Gen3 wild events and choice labels visible
9f31cdb FireRed: play Poké Flute cue for Snorlax events
bdda3db Docs: log the Flash/Fly HM fix
249aed8 FireRed: fix FLASH/FLY/DIVE badge gate never placing (party menu HMs dead)
051a900 Docs: verify the naming-screen mon icon through a real catch
0e36dc7 Docs: log the naming-screen icon fix's real-flow verification
9de1fa0 Draw the naming screen's player/Pokémon icon (naming_screen.c sIconFunctions)
```
Nothing has been pushed anywhere. Never push — this is Ceedrack's
personal-use codebase (Gen2Recomped License, see LICENSE.md); commit locally
only. Never commit `tools/rom_manifest_firered.json` (untracked, ROM-derived,
contains the charmap).

## How to build/run/test (read this before doing anything else)

- ROM path: `D:\gen1recomp-0.1.75-windows\firered3d\FireRedLeafGreenRecomp\variants\firered\roms\firered_usa.gba`
  — **not** the "(patched).gba" file in the repo root, that's a different hack
  (Pokémon Adventures Red Chapter).
- `lovec.exe` is at `C:\Program Files\LOVE\lovec.exe` (not on PATH). Use
  PowerShell `Start-Process -PassThru -RedirectStandardOutput/-Error`, then
  `$p.WaitForExit()` — `-Wait` alone is unreliable for seeing full log output
  here.
- Reimport after any `src/import/RomExtractorGen3.lua` or
  `src/script/Gen3SpecialsFRLG.lua` change:
  ```powershell
  $env:POKEPORT_VERSION='firered'; $env:POKEPORT_NO_MODS='1'
  $env:POKEPORT_IMPORT_ONLY='1'; $env:POKEPORT_FORCE_IMPORT='1'
  $env:POKEPORT_IMPORT_ROM='D:\gen1recomp-0.1.75-windows\firered3d\FireRedLeafGreenRecomp\variants\firered\roms\firered_usa.gba'
  & 'C:\Program Files\LOVE\lovec.exe' .
  ```
  Then clear `POKEPORT_IMPORT_ONLY`/`POKEPORT_FORCE_IMPORT` before running a
  driver, or it re-imports every launch.
- Headless test driver:
  `$env:POKEPORT_DRIVER='tests/drivers/_frlg_XXX.lua'` then run lovec the same
  way. Drivers live in `tests/drivers/`, are gitignored, and write PNGs to
  `ngshots/`. Read screenshots back with the Read tool (they render as
  images).
- Test with mods off: always keep `POKEPORT_NO_MODS=1` set.
- Also set `POKEPORT_NO_BOOT_REPORT=1` for drivers/imports. Otherwise a
  previous failed launch can stop on the crash-report screen before the
  driver starts, with empty redirected logs.
- On this Codex Windows host, LÖVE could not initialize its filesystem
  inside the sandbox. Request execution escalation for LÖVE runs; do not
  bypass the sandbox. Keep gameplay windows visible: the user explicitly
  wants to watch automated runs, so do not pass `-WindowStyle Hidden`.
- Git may report differing repository ownership for the sandbox account.
  Read-only Git inspection used a command-local
  `-c safe.directory=D:/gen1recomp-0.1.75-windows/gen2recomp-firered`;
  no global Git configuration was changed.
- Preserve the pre-existing deletion of Android
  `RoundTripLatencyActivity.java` and untracked screenshots/manifest.
- Screenshot cleanup is unnecessary. Do not work around a sandbox denial
  with another shell. Keep filesystem operations in PowerShell and validate
  absolute targets before any recursive deletion or move.
- Existing drivers worth knowing about (all in `tests/drivers/`, all
  gitignored so check they still exist before assuming):
  `_frlg_tiles.lua` (TILE_ONLY=spin,stairs,cycle,fast,furniture,pc,tower),
  `_frlg_events.lua` (EVENT_ONLY=trash,silph,ferry,hof),
  `_frlg_hms.lua` (HM_ONLY=cut,smash,strength,surf,waterfall,bike),
  `_frlg_art.lua` (ART_ONLY=diploma,seagallop,fossil,credits,regionmap,ssanne;
  CREDITS_FAST=1 shortens the credits page durations for testing),
  `_frlg_npcwalk.lua`, `_frlg_card.lua`, `_frlg_audit.lua` (specials
  coverage — needs `FRLG_SPECIALS` env pointing at a scratchpad file listing
  pokefirered's `data/specials.inc`), `_frlg_terrain.lua` (needs `FRLG_MB` =
  path to pokefirered's `metatile_behaviors.h`).

## Reference material

- `D:\gen1recomp-0.1.75-windows\pokefirered` — shallow pret clone, **the**
  ground truth for behaviour. Has real C source with named symbols; far more
  reliable than guessing from ASM.
- `firered3d\FireRedLeafGreenRecomp\variants\firered\symbols\all_symbols.tsv`
  — FireRed's symbol table (address/size/kind/name). Addresses are raw
  `0x08xxxxxx`; this engine's `rom:u8/u32/bytes/lz77` index ROM-file offsets
  with that `0x08000000` prefix **stripped**. A script-label symbol sometimes
  sits one byte early (on the previous script's `0x02`/`0x03` end byte, or a
  string's `0xFE`/`0xFF` terminator) — `RomExtractorGen3:frlgScriptStart`
  handles this, use it for any new script-address work.
- Memory file `firered-port-route.md` (in this Claude installation's memory
  dir) has the accumulated technical notes — symbol addresses, gotchas,
  driver env-var names, etc. Read it if it's available to you.

## What's done and verified (tested in-game, screenshots checked)

- **Import pipeline**: 4,021 scripts decode with 0 failures. Tilesets,
  sprites (386 species × front/back/shiny/icon, all present), trainer pics,
  overworld art, all UI screens (start menu, bag, PC, box storage, Pokédex,
  town map, naming screen, trainer card, summary).
- **All 196 script specials** the FRLG scripts actually call have handlers
  (`src/script/Gen3SpecialsFRLG.lua`) — Trainer Tower, Route 5 Day Care, size
  records (Heracross/Magikarp), Cape Brink tutor, Deoxys puzzle, Icefall Cave
  ice, Five Island resort, Daisy's massage, berry powder shop, PC menu,
  elevator (floor window + list + shake + **window-view metatile cycling**),
  Seagallop ferry + **crossing scene**, Bill's teleporter animation, S.S. Anne
  departure including its **wake trail and smoke puffs** (see verification
  below), old man catching demo, Hall of Fame, credits.
- **Tile behaviours**: 106/111 carried into the engine (the rest have no C
  effect on this cartridge). Spin tiles, Cycling Road pull-down + grass, fast
  water refusal, side stairs (0xEC–0xEF, correct facing plus FireRed's exact
  16-frame fixed-point diagonal `ExitStairsMovement` slide), 31
  furniture/sign/PC/TV metatile scripts, ice/waterfall correctly
  distinguished (previously conflated by the shape-based Emerald deriver).
- **HMs tested on real map objects**: Cut, Rock Smash, Strength (was reading
  Emerald's flag, fixed to FireRed's `FLAG_SYS_USE_STRENGTH` = 0x805),
  Waterfall, Surf (FireRed's own "used SURF!" text, not the Game Boy
  fallback), Bicycle (step speed correct).
- **NPC/object fixes**: FireRed's "clone" objects (`kind == 255` in the
  imported map data — off-map stand-ins so a neighbour's NPC shows across a
  map seam) were being spawned as real, frozen, walk-through duplicates —
  this is what caused the "duplicated fat man in Pallet Town" bug. Fixed in
  `objectVisible` (`src/world/OverworldController.lua`) and in the
  neighbour-ghost spawner (`rebuildNeighbors`) — clones never spawn, and an
  off-map neighbour object is never turned into a ghost either (the
  neighbour's own real object already covers it).
- **Trainer Tower**: floors/trainers/prizes read from ROM
  (`extractFireRedTrainerTower`), challengers now actually appear on their
  floor (fixed a post-transition object-sync ordering bug — a script that
  finishes *inside* `run()` rather than being polled the next frame wasn't
  triggering the entity resync), battle pics draw in true colour (was being
  squashed through the Game Boy 4-shade SGB remap — affects **all** Gen 3
  trainer battles, not just the tower; fixed in
  `BattleState.trainerPalette`).
- **Hall of Fame**: full FireRed-specific ceremony
  (`src/ui/Gen3HallOfFameFRLG.lua`) — team flies in one at a time with cries
  and stat lines, confetti, player walks in, NAME/IDNo./TIME window,
  "LEAGUE CHAMPION! CONGRATULATIONS!".
- **Credits**: full FireRed-specific roll (`src/ui/Gen3CreditsFRLG.lua`) —
  runs the actual `sCreditsScript` read from ROM, city fly-over maps with the
  player/rival running sprite, starter POKé BALL reveal scenes with the normal
  front sprite plus both cartridge-specific larger poses and the timed circle
  shrink/reveal, copyright card, THE END.
- **Diploma, museum fossil pictures, town-map SWITCH button for Sevii
  pages** — all drawn from ROM-extracted art (`extractFireRedExtraArt`,
  `constants.gen3FRLGArt`).
- **Port splash card** added before the GAME FREAK logo
  (`src/ui/Gen3IntroFRLG.lua`, `Gen3IntroFRLG:drawCard`) — names the engine,
  Ceedrack, the port author, and states it's an unaffiliated fan project. No
  Nintendo/GAME FREAK marks used. Override text via
  `data.field.boot.studio = { credit=, author=, portAuthor=, year=, notice=,
  notice2= }`.

## S.S. Anne departure — fixed and verified 2026-09-16/17

The earlier movement-only diagnosis was incomplete. The ship's 128x64
frame stores four consecutive 64x32 OAM pieces. Decoding those bytes as one
row-major 128x64 image scrambled the artwork before it ever moved.

- `RomExtractorGen3:overworldFramePixels` now composes oversized object
  frames from their ROM subsprite tables (signed coordinates, shape/size,
  and tile offsets). Ordinary sprites retain their existing decode path.
- Special 401 uses a visual `shiftPx`, consumed by `NPC:pose` and the
  billboard anchor. The map/collision coordinates remain stationary, as
  they do in the cartridge's `x2` animation. Horizontal movement does not
  change y sorting; true-color redraw and reflections consume the pose.
  Terrain/collision/sight checks retain map coordinates intentionally.
- The cutscene now uses `runner.waitingCheck`. The old detached field task
  was invisible to the stuck-script watchdog, which could cancel the scene
  at 720 frames. The off-screen check uses the shifted sprite centre.
- `extractFireRedSSAnneArt` now extracts the cartridge's own raw 4bpp wake and
  smoke sheets (`sWakeTiles`/`sSmokeTiles`) with `gObjectEventPal_SSAnne`.
  Special 401 creates the wake after the 50-frame horn pause, emits smoke every
  70 movement frames while the funnel is on-screen, and advances the exact
  12-frame wake / 10-20-20-30-frame smoke animation cadence from `ss_anne.c`.
  The wake is drawn behind the ship and the smoke above it; both remain purely
  visual and are cleared after the final 40-frame horn pause.

Verification: `tests/parity_frlg_ship.lua` passes 11 checks, including
synthetic four-piece ROM composition, unchanged map position, visual speed,
live wait registration, the 50-frame wake delay, 70-frame smoke cadence,
eventual completion and effect cleanup. Before the original movement fixes,
the composition check and three departure assertions failed.

After a full forced ROM reimport, `tests/frlg_ship_driver.lua` completed
the actual departure script and returned to Vermilion with scene variable
0x407E = 2 after 1,407 driver frames. Screenshots
`ngshots/ship_fx_wake.png`, `ngshots/ship_fx_smoke.png`,
`ngshots/ship_fx_verify_{180,480,900,1200,return}.png` show the intact moving
ship, the wake behind the stern, smoke drifting from the funnel, the ship
leaving the screen cleanly, and the return to the dock. The focused screenshots
were read back after the final import. Import: 4,021 scripts; 152 overworld
sheets, zero unreadable.

## Gym progression and Psychic category — verified 2026-09-16

The gym coverage now has both halves: the existing leader driver verifies
all eight real battle/reward chains, and `tests/frlg_gym_puzzles_driver.lua`
starts at every gym entrance and reaches the leader through the real map
mechanics.

`tests/frlg_gyms_driver.lua` separately passed each leader's defeated flag,
badge flag, TM reward flag, exactly one awarded TM, and completed script:
Brock TM39, Misty TM03, Surge TM34, Erika TM19, Koga TM06, Sabrina TM04,
Blaine TM38, and Giovanni TM26.

- Brock and Misty: complete collision-correct walkways, including trainer
  sight battles. The driver pathfinder uses `Collision.canMove`, so Cerulean's
  elevation/directional walkway rules are exercised rather than bypassed.
- Surge: reads the two randomized switch positions initialized by
  `SetVermilionTrashCans`, interacts with both trash cans, and crosses the
  opened electric barrier.
- Erika: uses Cut on the required tree and traverses the hedge/trainer route.
- Koga: solves the invisible-wall collision maze.
- Sabrina: uses a legal four-pad route to the central room and avoids crossing
  unintended pads while moving within each room.
- Blaine: answers all six quiz machines correctly (YES, NO, NO, NO, YES, NO),
  opening each door before advancing.
- Giovanni: plans around the actual FRLG arrow and stop tile behaviours and
  lets the runtime perform every forced spinner movement.

The combined run passed all 8 routes. The eight final-position screenshots
`ngshots/gym_puzzle_{Brock,Misty,Surge,Erika,Koga,Sabrina,Blaine,Giovanni}.png`
were read back and show the player at each leader with the puzzle route open.
Use `POKEPORT_DRIVER=tests/frlg_gym_puzzles_driver.lua`,
`POKEPORT_SPEED=8`, and optionally `GYM_ONLY=<leader>`.

The `PSYCHC has no category` warning was a registry rebuild bug, not bad ROM
extraction. `data/generated/type_chart.lua` had the correct `special` category,
but `TypeChart.registerInto` registered only the built-in Gen 1 names; the mod
catalog rebuild then discarded generated Gen 3 records such as `PSYCHC`,
`ELECTR`, and `FIGHT`. It now registers the generated type table when present
and falls back to the built-in table for older datasets. The focused regression
`tests/parity_gen3_type_categories.lua` passes 3/3. The combined gym run used
PSYCHIC throughout many real trainer battles and emitted no missing-category
warning.

## Team Rocket progression and traversal — verified 2026-09-16

This group is closed. Two visible drivers cover both story scripts and
physical routes.

`tests/frlg_rocket_driver.lua` passes the real Game Corner grunt/poster reveal;
Hideout Lift Key, both B4F guards, Giovanni and Silph Scope; Silph Card Key,
7F rival, Lapras gift, 11F Giovanni, and the president's Master Ball.

`tests/frlg_rocket_traversal_driver.lua` covers everything that remained:

- all four Mt. Moon Rocket grunts, Super Nerd Miguel, the real YES choice on
  the Dome Fossil, the fossil item, and both completion flags;
- a physical Game Corner machine interaction, three-coin bet, spin, three reel
  stops, result, and clean return to the overworld;
- the actual Silph 5F Card Key item ball, a 2F barrier script, its door flag,
  and walking through the cells that were blocked before the door opened;
- the open poster's real warp followed by collision- and spinner-aware travel
  through Hideout B1F, B2F, B3F, and B4F using each floor's real stair warp.

The slot run exposed a FireRed cache gap: `extractSlotMachine` previously
recognized only Emerald's reel layout, so FireRed's `playslotmachine` command
returned without opening a screen. The FireRed branch now imports its 3x21
reel table, seven payout classes, per-symbol palettes, reel art, digits, and
background from the cartridge. `Gen3Slots` applies FireRed's asymmetric cherry
and grouped Pokemon payout rules while preserving the Emerald rules. A forced
ROM reimport completed with 4,021 scripts and reported `3 reels, 7 symbols, 7
payouts, 9 pictures`.

The final visible traversal run and separate story regression both exited
successfully. Screenshots were read back for Mt. Moon, the slot screen/result,
the crossed Card Key barrier, B4F arrival, the poster staircase, and Silph's
president room. Logs: `ngshots/rocket_traversal.log` and
`ngshots/rocket_progression.log`.

The Mt. Moon Rocket grunt and Super Nerd battles also exposed a shared battle
placement bug. FireRed's cave backdrop has edge detail on rows away from the
platform surface; the scanner used those rows' horizontal extremes while using
the surface row's height, shifting opponent trainers and Pokemon left toward
the HP panel. `measurePlatforms` now keeps x bounds and y from the same widest
platform row. `tests/frlg_mtmoon_battle_placement_driver.lua` visibly checks
both encounters at the trainer and Pokemon phases; the measured centers are
now opponent `175.5` and player `63.5`, matching the drawn cave platforms.
Screenshots: `ngshots/mtmoon_rocket_trainer.png`,
`ngshots/mtmoon_rocket_mons.png`, `ngshots/mtmoon_scientist_trainer.png`, and
`ngshots/mtmoon_scientist_mons.png`.

## League and Sevii regression coverage — verified 2026-09-17

FireRed's League import uses raw group-and-number map IDs while the story
layer uses named rooms. `Data:seedDefaults` now aliases the six League maps,
binds the imported Elite Four objects to their story text and names Lance and
the Champion objects for their scripted entrances. It also exposes the three
imported original-Champion parties (`TERRY_438` through `TERRY_440`) as the
shared `OPP_RIVAL3` class in starter order.

Visible runs passed Lorelei, Bruno, Agatha and Lance with their victory flags;
the Champion driver then entered from Lance's room, fought the imported rival
party and set `EVENT_BEAT_CHAMPION_RIVAL`. The Hall of Fame driver consumed
the Champion handoff marker and recorded the team. It explicitly vetoes the
save callback, so no test writes the player's real save.

`tests/frlg_champion_driver.lua` and `tests/frlg_hall_of_fame_driver.lua`
hold those regressions. `DoPokemonLeagueLightingEffect` remains visually a
no-op, but it does not prevent the battle or ceremony progression.

`tests/frlg_sevii_progression_driver.lua` passed the imported FireRed special
paths for Cape Brink's fully-friendly Blastoise tutor selection and reward
flag, Resort Gorgeous's requested species/reward selection, all eleven Birth
Island triangle touches through Deoxys awakening, Icefall Cave's persisted
cracked ice, and Trainer Tower's eight floor initializations, timer record and
prize. This coverage operates on an isolated fresh save and does not write to
disk.

## Launcher and developer-console regressions — verified 2026-09-17

FireRed is now an official launcher tab before Emerald, with its own
red-orange accent. It is included in `GameVersion.ORDER`, so readiness,
import, save-slot selection and the launcher counter all use the same version
list. `tests/firered_launcher_driver.lua` verifies its placement and
importability.

The developer console no longer synthesizes printable keys from key names.
`love.textinput` is forwarded through `Game` to the active overlay, which
preserves Caps Lock, keyboard-layout symbols, composed text and paste.
`tests/console_textinput_driver.lua` asserts an uppercase identifier with an
underscore reaches the console unchanged.

## Flash and Fly HMs — fixed and verified 2026-09-17

Both were previously untested and, it turned out, both were actually dead
from the party menu: `Gen3PartyMenu:flashUsableBy`/`:flyUsableBy` (and
`:knowsFieldMove` under them) gate every badge-locked field move through
`constants.gen3FieldMoves`, which `RomExtractorGen3:fieldMoveGates` derives
by finding `checkflag`+`checkpartymove` pairs in map scripts and voting on
which badge-flag block they agree on. On this ROM the vote only ever found
**one** script-based candidate (CUT and ROCK SMASH are scripted at their map
objects; FLASH/FLY/SURF/STRENGTH/WATERFALL are asked for in native code —
`SetUpFieldMove_Flash` and siblings — with no script bytecode to find at
all), and the heuristic's own safety check correctly refuses to trust a
single vote. So `gen3FieldMoves` came back empty and FLASH/FLY/DIVE were
unreachable from the party menu no matter what the party knew, even though
CUT/ROCK_SMASH/STRENGTH/SURF/WATERFALL kept working fine through their
separate *object-script* path (which is why those five tested clean earlier
and this pair didn't get caught until now).

**Fix** (`src/import/RomExtractorGen3.lua`, `fieldMoveGates`): when the
script vote can't clear its own bar, fall back to `FLAG_BADGE01_GET = $820`
— a fixed fact about every FireRed/LeafGreen revision (pret's
`include/constants/flags.h`), not a value this port derives, and already
relied on elsewhere in this port (`tests/drivers/_frlg_hms.lua`'s badge
setup). Gated to `isFireRedManifest()` so Ruby/Sapphire/Emerald — where this
constant does not hold — keep using the heuristic untouched.

Initial verification with `tests/drivers/_frlg_flash_fly.lua` (mods off,
forced reimport) proved FLASH lights Rock Tunnel's full radius from the party
menu (`ngshots/hmff_01_flash_before.png` → `hmff_03_flash_after.png`,
`flashUsableBy` false → true) and proved FLY becomes usable, but that pass did
not have a visited town to drive a real destination/landing round trip.

**FLY round trip closed 2026-09-18.** A follow-up
`tests/drivers/_frlg_fly_roundtrip.lua` intentionally did not seed
`save.visited`: it entered a real imported FLY town first, letting the normal
map-entry path set the visited flag, then moved to Route 1 and invoked FLY from
a level-60 Pidgeot through `Gen3PartyMenu:useFieldMove`. That exposed one real
bug: `OverworldState:openRegionMap` required Hoenn's
`gen3MapSectionRects/gen3RegionMapPlaces` before opening any Gen 3 map, so
FireRed's already-imported `gen3FRLGRegionMap` was rejected and FLY silently
fell back to the generic text `FlyMenu`. Commit `d8b92bc` accepts either
Hoenn's section data or FireRed's own region-map grid.

After the fix the same live driver opens FireRed's cartridge-style Town Map,
restricts it to the visited destination, runs the Pokémon field-move sweep
*after* the destination is selected, performs the departure animation and
lands on the imported heal-location FLY warp. The selected retail-ROM target
was `MAP_G03_N00`, landing exactly at `(6,8)`. The driver printed
`PASS FLY round trip MAP_G03_N00 ... 6 8` with exit code 0. Captures are
`ngshots/fly_roundtrip_01_picker.png`, `_02_field_move.png`,
`_03_departure.png`, and `_04_arrived.png`.

**FLY rider sprite corrected 2026-09-18.** A visual follow-up found that the
departure effect was using the selected Pokémon's battle front sprite (the
fallback in `fxBird`) rather than FireRed's dedicated field-effect bird. The
reference `FldEff_FlyOut` creates `FLDEFFOBJ_BIRD` from
`gFieldEffectObjectPic_Bird`; its five 64x64 frames are bird-only, Red fly-out,
Red fly-in, Leaf fly-out and Leaf fly-in, with fly-out selected by
`playerGender * 2 + 1`. Exact source-data matching against the retail ROM
located the 0x2800-byte sheet at `0x39D3C8` and
`gFieldEffectObjectPalette0` at `0x35B968`. `extractFireRedFlyBird` now writes
that cartridge sheet and records Red/Leaf fly-out frames 1/3; `fxBird` prefers
it and therefore hides the separate player exactly as the existing fly draw
path expects. A forced retail-ROM reimport succeeded, the same end-to-end FLY
driver again printed `PASS FLY round trip MAP_G03_N00 ... 6 8`, and the fresh
`ngshots/fly_roundtrip_03_departure.png` was visually checked: it shows the
FireRed rider-bird rather than Pidgeot's battle sprite, with no duplicate
player underneath.

## Final handoff checklist — closed 2026-09-17

The gameplay-verification block (Snorlax, Safari, save/load and V.S. Seeker)
and the final three visual-parity items are closed. There are no known blockers
left in this handoff checklist.

1. **Diagonal side-stair walk-in animation:** `Player:startStairExit` now
   reproduces `ExitStairsMovement`'s four exact fixed-point direction speeds,
   starts at `speed * 16`, reverses the speed, and converges the render-only
   OAM offset to zero across 16 frames while the player fast-walks in place.
   Field controls remain locked during the slide and the logical destination
   cell never moves. `TILE_ONLY=stairs` was rerun after the final import;
   `ngshots/tile_{01_stairs_entry,02_stairs_mid,03_stairs_settled}.png` were
   read back and show the diagonal arrival and correct final west-facing pose.
2. **Credits Pokémon reveal:** `extractFireRedExtraArt` now extracts both
   larger credits poses for Charizard, Venusaur, Blastoise and Pikachu from
   the retail ROM, using each species' normal palette and the exact
   `WindowTemplate` coordinates from `credits.c`. `DoCreditsMonScene`'s
   overlapping 16-frame fade/40-frame hold, 8/4/4-frame pose staging,
   16-frame circle shrink, 32-frame hold, reveal/cry, 128-frame hold and
   fade-out are represented in `Gen3CreditsFRLG`. The focused
   `_frlg_credits_mon_reveal.lua` driver passed all pose-dimension assertions;
   its Charizard front/pose1/pose2/circle/ball captures plus the other three
   final reveals were read back.
3. **S.S. Anne wake trail + smoke puffs:** the retail wake/smoke OBJ art is
   extracted and Special 401 follows `CreateWakeBehindBoat` /
   `CreateSmokeSprite` timing and screen offsets. `tests/parity_frlg_ship.lua`
   passes 11/11 checks; the real departure driver asserted that both effects
   rendered and returned to Vermilion cleanly at driver frame 1407. The wake,
   smoke and return screenshots were read back after the final import.

Final focused regression sweep after the last importer/special changes:
`tests/frlg_vs_seeker_test.lua` **11/11**, `tests/parity_frlg_ship.lua`
**11/11**, and `tests/parity_gen3_type_categories.lua` **3/3**. A final forced
retail-ROM import completed successfully before the three visual drivers were
rerun; the existing two accepted cache gaps (`data/generated/scenes.lua` and
`assets/generated/ui/summary_info.png`) remain unchanged.

## Naming-screen icon — pixel-exact player/mon + rival complete — 2026-09-18

Item 6 from the previous version of this list (the mon icon, `kind = "mon"`,
only verified in isolation) is closed. Ran a real wild-battle catch through
`tests/drivers/_frlg_catch_nickname_check.lua` (mods off): teleport to Route 1
(`MAP_G03_N19`), start a wild RATTATA battle (`BattleState.newWild`), throw a
Poké Ball with `battle.rng` forced to guarantee the catch, answer YES to the
nickname prompt. The naming screen came up with `kind = "mon"`,
`species = "RATTATA"`, and `ngshots/catch_02_naming_screen.png` shows
Rattata's own bouncing party icon over the plate — the same code path as the
isolated `_frlg_nickname_check.lua` driver, now confirmed end-to-end from an
actual battle capture rather than a hand-built `mon` table. Party count went
from 1 to 2 afterward, so the catch itself completed correctly too.

The original player/mon report remains verified end-to-end, and the final
fidelity caveats are now closed too. `naming_screen.c` does **not** use one
shared bottom anchor: `NamingScreen_CreatePlayerIcon` creates the 16x32 player
sprite at centre `(56,37)`, `NamingScreen_CreateMonIcon` creates the 32x32 party
icon at centre `(56,40)`, and `NamingScreen_CreateRivalIcon` creates its 16x32
rival sprite at centre `(56,37)`. The port previously used a shared bottom
anchor of `y=52`, putting the player about one pixel high and the Pokémon icon
four pixels high. `NamingScreen:drawIcon` now converts those exact cartridge
centres to LÖVE top-left coordinates using each sprite's real dimensions.

The old "rival icon cannot be extracted" note was also wrong. The retail USA
ROM contains `sRival_Gfx` as an exact second 0x900-byte copy of Blue's normal
nine-frame overworld sheet: the ordinary `gObjectEventPic_Blue` copy starts at
`0x38A428`, while the naming-screen-private copy is at `0x3E1980`.
`gNamingScreenRival_Pal` is the 32-byte palette at `0xE98004`, immediately
between `gNamingScreenKeyboard_Pal` (`0xE97FE4`) and
`gNamingScreenMenu_Pal` (`0xE98024`) exactly as `graphics.c` lays them out.
`RomExtractorGen3:extractFireRedNaming` now composes that real sheet/palette and
records the cartridge's `sAnim_Rival` sequence: tile offsets `0,24,0,32` are
16x32 frame indices `{0,3,0,4}`, held 10 frames each. Oak's NEW NAME branch now
passes `kind = "rival"`, so the real keyboard flow draws and animates Blue.

Fresh verification after a forced retail-ROM reimport (mods off) reported
`Gen3 FireRed naming screen: 18 images` (the added eighteenth image is the rival
sheet). `tests/drivers/_frlg_naming_fidelity.lua` drove the real Oak sequence,
chose GIRL, captured the player keyboard, deliberately chose NEW NAME instead
of a rival preset, reached `kind = "rival"`, checked the imported 16x32 / nine
frame / `{0,3,0,4}` / 10-tick record, and finished with
`PASS naming fidelity RED GREEN girl`. Visual reads of
`ngshots/naming_fidelity_player.png`, `naming_fidelity_rival_0.png`, and
`naming_fidelity_rival_2.png` show Leaf and Blue centred on the plate; the two
rival captures show different valid animation poses. The real catch driver was
also rerun after the coordinate correction: it reached `kind = "mon"`,
`species = "RATTATA"`, party count 2, and the fresh
`ngshots/catch_02_naming_screen.png` shows Rattata centred at the cartridge's
`(56,40)` target. There is no remaining naming-icon fidelity caveat from this
handoff.

## Start-flow reports checked — one closed, one was a real bug (fixed) — 2026-09-17

The two items logged in the previous version of this section were re-checked
this session by actually running the flow and reading back real screenshots
(not just reading code).

1. **"Start menu entries missing (expected NEW GAME, OPTIONS, EXIT)"** — not
   a bug. Ran `tests/drivers/_frlg_title.lua`
   (`POKEPORT_DRIVER=tests/drivers/_frlg_title.lua`), read back
   `ngshots/title_menu.png`: it shows `CONTINUE` (with PLAYER/POKéDEX/TIME/
   BADGES filled in from the save) and `NEW GAME`, both rendering correctly.
   **This is cartridge-accurate** — real FireRed's main menu (pokefirered
   `main_menu.c`) only ever has CONTINUE + NEW GAME; OPTION lives inside the
   in-game START menu once you're playing, not on this screen, and a GBA
   cartridge has no EXIT at all. `src/ui/Gen3MainMenu.lua` already documents
   this in its own header comment and deliberately skips OPTION/EXIT for
   `GameVersion.get() == "firered"` (see the `~= "firered"` check, ~line 94).
   Whoever filed the original report was likely expecting Emerald's four-row
   menu and flagging FireRed's genuinely-shorter one as broken.
2. **"Player sprite missing during name entry"** — real bug, now fixed. The
   **Oak-speech naming sequence** (`src/ui/Gen3OakSpeechFRLG.lua`, the
   "which one is right for you?" platform scene) was never the issue — it
   already showed the player's trainer sprite correctly (verified via
   `tests/drivers/_frlg_newgame.lua`, `ngshots/frlg_ng_015.png` and
   `ngshots/frlg_ng_024.png`).

   The actual bug was the **keyboard-typing screen** (`src/ui/NamingScreen.lua`).
   A first pass this session grepped pokefirered's `naming_screen.c` for
   "Pic"/"Sprite" only, found nothing, and wrongly concluded the cartridge
   draws no portrait there at all — that conclusion was wrong and got
   committed to this doc. The user corrected it directly after seeing the
   actual screen: *"in keyboard typing there's only a green patch.... above
   that there should be player sprite and if pokemon name is typing then the
   pokemon sprite."* A broader grep (`MonIcon\|OBJ_EVENT\|PlayerAvatar\|Icon`)
   found the real dispatch table, `sIconFunctions` in `naming_screen.c`:
   `NamingScreen_CreatePlayerIcon` draws the player's own overworld walk
   sprite (south-facing stand frame) next to the question when naming the
   player, `NamingScreen_CreateRivalIcon` uses its private animated Blue sheet
   for a newly-entered rival name, and `NamingScreen_CreateMonIcon` draws the
   species' bouncing party icon when giving a Pokémon a nickname. This port's
   `src/ui/NamingScreen.lua` had never drawn either — the plate's background
   tiles decode fine (including the green ground-shadow ellipse the icon
   normally stands on), but nothing was ever drawn on top of it, so the
   ellipse sat empty.

   **Fix**: `NamingScreen` now takes `opts.kind` (`"player"`, `"mon"`, or
   `"rival"`, plus `opts.species`/`opts.mon` for the mon case) and draws the
   corresponding icon over the plate in both `drawFireRed` and `drawGen3`.
   The player icon resolves the current gender's overworld walk sheet the
   same way `Player:refreshForm` does (`Sprites.playerForm` +
   `FieldDefaults.fieldValue(data, "playerSprites", "walk")`), crops its
   south-facing standing frame (frame 0), and draws it directly — Gen 3
   overworld sheets import as `trueColor = true` full-RGBA PNGs
   (`RomExtractorGen3:extractOverworldSprites`), so no palette remap is
   needed outside the world-render pipeline. The mon icon reuses the exact
   resolution `Gen3PartyMenu:iconFor` uses (`data.icons.bySpecies` /
   `data.pokemon[species].icon`, through the `pokemon.icon` mod seam) and
   the same two-frame bounce. The 2026-09-18 fidelity pass additionally
   extracts FireRed's private rival naming sheet/palette and its four-step
   animation, and gives Oak's rival NEW NAME keyboard `kind = "rival"`.
   Wired through every real call site: `Gen3OakSpeechFRLG.lua`'s player- and
   rival-naming calls, and the two
   nickname sites in `Gen3Commands.lua` plus the caught-mon nickname site in
   `BattleState.lua` (all `kind = "mon", mon = mon`).

   Verified by pushing `NamingScreen` directly with each `kind`
   (`tests/drivers/_frlg_keyboard_check.lua` for `"player"`,
   `tests/drivers/_frlg_nickname_check.lua` for `"mon"`) and reading back
   `ngshots/keyboard_check_01.png` (Red standing on the ground-shadow patch,
   full colour) and `ngshots/nickname_check_01.png` (Charizard's party icon).
   The later fidelity pass replaced the old estimated `y=52` bottom anchor
   with the exact `CreateSprite` centres from `naming_screen.c`: player/rival
   `(56,37)`, mon `(56,40)`. See the completed naming-screen section above for
   the fresh screenshots and the rival-sheet extraction evidence.

   **Re-verified against the real full new-game flow, not just the isolated
   drivers above** (`tests/drivers/_frlg_newgame.lua`, mods off): Pikachu
   intro through Oak's speech, gender select, player naming, rival naming,
   completion, no errors. The driver picked GIRL, and
   `ngshots/frlg_ng_naming_014_player.png` shows **Leaf's** own overworld
   sprite (not Red's) standing on the patch — confirming the gender lookup
   (`Sprites.playerForm` reading `save.player.gender`) resolves correctly
   live off a real gender choice, not just the hardcoded default in the
   throwaway drivers. Run finished cleanly (`DONE true`, name RED, rival
   GARY, gender girl). The nickname (`kind = "mon"`) path was subsequently
   exercised through a real wild catch as well; see the naming-screen section
   above and `ngshots/catch_02_naming_screen.png`.

Lesson for next time a "missing sprite/menu row" report shows up: check the
**real cartridge's own layout** (pokefirered source) before assuming this
port is wrong — FireRed's screens are frequently *shorter* than Emerald's
equivalents by design, not broken.

## Live gameplay verification block — closed 2026-09-17

This pass used the retail FireRed ROM with mods off and exercised the remaining
gameplay blockers through real field/battle/save paths rather than logic-only
tests.

- **Poké Flute / Snorlax:** `tests/drivers/_frlg_snorlax.lua` now drives the
  Route 16 object at `(31,13)` through the real YES prompt, wake-up text,
  Poké Flute cue, level-30 SNORLAX battle, victory, hide flag and object
  removal. The run verifies `FLAG_G3_0807` (special-wild battle) clears after
  the fight, `FLAG_G3_0080` remains set, the NPC disappears and the map script
  finishes. Screenshot: `ngshots/frlg_snorlax_battle_entry.png`; result log:
  `ngshots/frlg_snorlax_result.txt`.
- **Safari Zone:** a real Fuchsia gate admission deducts exactly ¥500, gives 30
  Safari Balls and enters the Center. A Safari battle reaches the
  BALL/BAIT/ROCK/RUN menu; a forced miss consumes one ball and RUN returns to
  the field. Exhausting the final step through normal overworld movement clears
  Safari mode and the PA return lands at the entrance `(4,1)`. Two importer
  defects were fixed while doing this: FRLG uses **600** steps (not Emerald's
  500), and its map-rooted `ExitSafariMode` callers do not themselves contain
  the global return warp. `extractSafari` now derives the return from the gate
  map's warp back into the Safari map instead of inventing a destination.
- **Save/load round trip:** `tests/drivers/_frlg_save_roundtrip.lua` routes the
  real `SaveData.save`/`SaveData.load("firered")` writer and parser through an
  isolated on-disk filesystem under `ngshots/`, never the player's normal save
  directory. Money, bag items, event flags, defeated trainers, party
  species/level/nickname/HP, map position/facing, Gen 3 vars and nested V.S.
  Seeker state all survive the serialized reload with no `.tmp`/`.bak`
  recovery.
- **V.S. Seeker:** the retail import exposes 221 `sRematches` rows. A live Route
  3 run uses Youngster Ben (`trainer 89`, object 9) after 100 real walking
  steps; the nearby scan arms him and selects his first cartridge rematch party
  (`trainer 101`). His real object script reaches the type-5 rematch record,
  starts trainer 101, wins, records `FLAG_G3_0565`, clears that object's armed
  state, then recharges after another 100 real walking steps without resurrecting
  the consumed rematch. This exposed two shared wiring bugs: FRLG's trainer flag
  block is the cartridge-declared `$0500..$07FF` even though the trainer table
  has extra non-flaggable rows, and specials 60/61 must use FireRed's V.S.
  Seeker rather than Emerald's Match Call. Type-5/type-7 records now correctly
  fall through to post-battle talk when the object is not currently armed.
  Screenshots: `ngshots/frlg_vs_seeker_armed.png` and
  `ngshots/frlg_vs_seeker_battle.png`; result log:
  `ngshots/frlg_vs_seeker_live_result.txt`.

Emerald's Match Call path remains unchanged by the FireRed-specific special
dispatch above.

## Poké Flute / Snorlax implementation note (2026-09-17)

The imported Route 16 Snorlax event is present at the cartridge coordinate
`(31,13)` and its talk script reaches the level-30 wild-battle branch. The
FireRed command stream contains the Snorlax cry and delay, but no standalone
Poké Flute audio command. `g3_wild_battle` now supplies the cartridge cue by
playing `Pokeflute` immediately before the scripted wild battle. The existing
engine has no separate Poké Flute field animation; the wake-up presentation is
currently the cry, delay, transition, and battle entry. The focused live
regression is complete; see the verification block above.

## Pre-PR regression sweep — closed 2026-09-19

The three manual-play items that reopened this sweep are now closed. R3 is
`bc961a5`; R1 and R2 are `0a4e087`. The older subsections below are retained
where they explain how the bugs were found, but any text describing those
three as "open", routing FireRed TOSS through the PC, or treating the bag-list
screen as the final Item PC implementation is historical and superseded by the
round-2 closure section below.

Manual play before opening a PR reported three things: the item list behind
the PC's WITHDRAW ITEM row is "gbc color", the reopened PC/NPC items below are
"not fixed properly", and "when exiting the house even the tile beside the
house... the exit is leading to exit... same with stairs". The request also
asks for a full sweep for anything still using Gen 1 menus or Emerald parts.
Work items are being committed and logged here one at a time so a fresh
session can resume mid-sweep.

### 1. Directional warps — fixed, `8008c6f`

`Warp.onArrive` fired **every** Gen 3 warp the moment it was stepped on,
because the Gen 3 tileset sets `warpsAreEvents = true` and
`Map:isWarpTileCell` therefore answered "yes" for any cell carrying a warp
event. On the cartridge the exit mats, arrow panels and side staircases are
not arrival warps at all: `IsWarpMetatileBehavior` (the list
`TryStartWarpEventScript` checks on a completed step) deliberately excludes
them, and they fire only from `TryArrowWarp`, which runs under
`input->heldDirection && input->dpadDirection == playerDirection`.

So walking *along* a two-cell doormat re-entered the building, and stepping
onto a side staircase from above took it. A census of every imported warp
event (`tests/drivers/_frlg_warp_census.lua`) shows the scale: 527 warps on
`$65` (the interior exit mats, **90** of them directly beside another `$65`
warp), 68/64/32 on `$62`/`$63`/`$64`, and 246 across `$EC..$EF`.

**Numbering note for future work:** this cartridge's data puts the four side
staircases at **`$EC..$EF`**, not the `$6C..$6F` a current pret
`metatile_behaviors.h` names — the census finds zero warps on `$6C..$6F`, and
the port's own `ExitStairsMovement` arrival slide already reads `$EC..$EF`.
Trust the census over the header here. `doorTiles` still lists Hoenn's `$6C`
"water door"; on FireRed that value is simply unused, so it was left alone.

`Map:frlgWarpDirection` now names the eight directional behaviours and the
direction each must be walked in; `isWarpTileCell`/`isDoorTileCell` decline
them and `Warp.extraCheck` fires them. Because `isWarpTileCell` declines
them, `refreshStandingOnWarp` leaves the cell armed, which is what the
narrower `$65`-only special case in `e90de37` had been added for — pressing
DOWN on an exit mat still leaves the building. FireRed-gated, so Emerald
(different numbering) is untouched.

Verified by `tests/drivers/_frlg_warp_dirs.lua`, 9/9 checks: walking along a
real two-cell mat does not warp, DOWN on it still exits, and stepping onto a
`$EC` staircase from above stays put. `ngshots/warpdir_02_mat_sideways.png`
shows the player standing on the Viridian Forest gate mat after walking along
it.

### 2. PC item storage was the Game Boy list — intermediate fix, `aa9bb40`

`aa9bb40` removed the Gen 1 `ListMenu`, but this was only an intermediate fix:
it borrowed the bag screen and also inherited an incorrect TOSS row. FireRed's
final cartridge-faithful Item PC implementation is documented under R1 below
and landed in `0a4e087`.

The "gbc color" report. `Gen3PlayerPC`'s ITEM STORAGE rows called
`PlayerPC.withdraw/deposit/toss` wholesale, and all three push
`src/ui/ListMenu.lua` — a hardcoded 160x144 white Game Boy page in the Game
Boy font. Only the *store* and the rules were ever shared between the
cartridges; the screen was not.

Same class of bug as the catching tutorial's Gen 1 bag, and the same answer:
`Gen3BagMenu` already draws the cartridge's list, frame, item icon,
quantities and description box, and already supports a list that is not the
bag's own contents plus a pick handed back instead of used
(`opts.rows` + `pick`/`onPick`, written for `DisplayListMenuID`'s tutorial
arm). WITHDRAW and TOSS now open that list over `save.pcItems` under their
own header with the pocket switch locked off; DEPOSIT opens the **real bag**,
which is what the cartridge opens. The store, the 50-stack
`PC_ITEM_CAPACITY` rule, the key-item/HM "always one, no prompt" rule and the
quantity prompt are unchanged, and `PlayerPC` keeps its flows for Gen 1/2.

Verified by `tests/drivers/_frlg_pc_items.lua`, 12/12 checks: all three rows
open `Gen3BagMenu` rather than `ListMenu`, a withdrawn POTION moves PC→bag
(3→2, bag 1), a deposit moves it back (→3), and a toss removes an ANTIDOTE
(2→1). Screenshots `ngshots/pcitem_03_withdraw.png`, `pcitem_08_toss.png`.

### 3. PP-item move picker was the Game Boy list — fixed, `dd5d701`

Found by the sweep rather than reported. Using an ETHER/ELIXIR/PP UP out of
FireRed's bag reaches `BagMenu.useItem`, whose "which move?" step pushed
`ListMenu` — so a Gen 3 item flow dropped onto a Gen 1 screen halfway
through. There is no ripped move-picker window to reuse, but `Menu` is
bordered with the **cartridge's own nine-slice** (`Font.drawBox` prefers the
extracted `sWindowFrames`; this dataset carries 10 frames and defaults to
frame 1), so on Gen 3 the pick now uses that window and font with the PP in
the label. Gen 1/2 keep `ListMenu`. Verified by
`tests/drivers/_frlg_ether_move.lua`, 2/2, screenshot `ngshots/ether_01.png`.

### 4. Gen 1 / Emerald sweep — where things actually stand

**Routing.** Every screen a FireRed player reaches by name goes through
`src/ui/Screens.lua`'s `GEN3_ALIASES`: bag, party, summary, start menu, box,
storage menu, player PC, trainer card, options, dex, dex entry, move-learn and
the evolution scene. `Gen3Pokedex`/`Gen3DexEntry` delegate again to
`Gen3PokedexFRLG`, and the title, intro, Hall of Fame and credits each have
their own `*FRLG` screen. Shop goes to `Gen3ShopMenu`.

**Remaining `ListMenu` (Game Boy) call sites, all triaged:**

| Site | Reachable on FireRed? |
| --- | --- |
| `PlayerPC.lua` ×3 | No — Gen 1/2 only now (see item 2 above) |
| `BagMenu.lua:695` (the bag itself) | No — `Gen3BagMenu` serves the alias |
| `BagMenu.lua` "which move?" | **Was yes** — fixed in item 3 above |
| `BoxMenu.lua` ×4 | No — `BoxMenu` aliases to `Gen3BoxMenu` |
| `ShopMenu.lua` ×2, `PokedexMenu.lua` | No — Gen 3 screens serve these |
| `FlyMenu.lua` | Only if `openRegionMap` declines; since `d8b92bc` it does not (FireRed's Town Map is accepted), so this is a fallback, not a path |
| `BattleState.lua:3932` | Fallback behind the `Gen3BagMenu` branch above it |
| `BindingsMenu.lua` | Engine settings, not a cartridge screen — leave |

**Emerald numbering applied to FireRed** — one real instance found and fixed
(item 1's `doorTiles`/stairs). The lesson generalises: several imported
tables are shared between Hoenn and Kanto and a few carry **Hoenn's** byte
values. When a behaviour-keyed table misbehaves on FireRed, census the
cartridge's own data before trusting either the table's comment or a pret
header (`tests/drivers/_frlg_warp_census.lua` is the pattern).

**Gen 3 screens with no FireRed-specific branch at all** (`grep -c
'firered\|frlg\|FRLG\|FireRed'` = 0): `Gen3StorageMenu`, `Gen3MoveLearnMenu`,
`Gen3EvolutionState`, `Gen3ItemMenu`, `Gen3StarterSelect`, `Gen3Cutscene`,
`Gen3DexSearch`, plus the Hoenn-only ones FireRed never opens (`Gen3Contest`,
`Gen3BerryBlender`, `Gen3PokeblockCase`/`Feed`, `Gen3Pokenav`,
`Gen3Roulette`, `Gen3EasyChat`, `Gen3WallClock`). The first group is
**reachable** on FireRed and is drawn from shared Gen 3 art, which is right
for the storage system and close for the rest; none of them was reported and
none was verified pixel-for-pixel this pass. That is the honest next place to
look if more "this screen looks like Emerald" reports come in.

## Round-2 manual reports — resolved 2026-09-19

Three reports from manual play after the first sweep reopened R1/R2/R3. They
have now all been implemented and re-verified against the retail FireRed ROM
with mods off. The source analysis that led to each fix is summarized here so
a later regression has a concrete cartridge reference rather than a guess.

### R1. FireRed Item PC — closed, `0a4e087`

The second pass found an important source correction before polishing the
half-fix: FireRed does **not** have a TOSS row in player PC item storage.
`pokefirered/src/player_pc.c`'s `sMenuActions_ItemPc` is exactly
`WITHDRAW ITEM / DEPOSIT ITEM / CANCEL`. The top player-PC menu is likewise
the cartridge's three rows (`ITEM STORAGE / MAILBOX / TURN OFF`). The extractor
now reads those FireRed tables with their real row counts instead of applying
Emerald's four-row assumption.

WITHDRAW now uses a dedicated `Gen3ItemPcFRLG` built from the retail-ROM
`gItemPcTiles`, `gItemPcTilemap` and `gItemPcBgPals`. Its source-backed layout
matches `item_pc.c`: list `(7,1) 19x12`, description `(5,14) 25x6`, label
`(1,1) 5x4`, quantity `(24,15) 5x4`, and action submenu `(22,13) 7x6`. Pressing
A on an item opens the real `WITHDRAW / GIVE / CANCEL` submenu; SELECT enters
the cartridge's insertion-style item reorder and persists that slot order via
`save.pcOrder`.

The transient furniture is FireRed-specific too, rather than the shared
Game-Boy-style `QuantityBox`: the withdraw question is subwindow 1 at `(6,15)
16x4`, the number remains in window 3 with `×NNN` at local `(8,10)`, withdraw
result/refusal text uses subwindow 2 at `(6,15) 23x4`, and the no-party GIVE
message uses window 5 at `(2,15) 26x4`. The Item PC remains directly underneath
all of those nonopaque states.

DEPOSIT still opens the real FireRed bag, as `player_pc.c` requires, but now
uses the cartridge's `gBagBg_ItemPC_Tilemap` variant instead of the ordinary bag
background. GIVE follows `PARTY_ACTION_GIVE_PC_ITEM`: one PC item moves to the
chosen Pokémon, and when swapping a held item the old item goes to the bag; a
full bag rejects that swap without consuming the PC item. The existing
50-stack capacity and key-item/HM one-at-a-time rules are retained.

Final focused validation after a **forced retail-ROM reimport** passed **50/50**
checks in `_frlg_pc_items.lua`, including the exact three menu rows, no TOSS,
WITHDRAW/GIVE/CANCEL, SELECT reorder, all transient window geometries, key/HM
withdraw, 50-stack refusal, GIVE, and DEPOSIT. Screenshots read back include
`pcitem_02_storage.png`, `pcitem_03b_submenu.png`, `pcitem_03c_reorder.png`,
`pcitem_04_quantity.png`, `pcitem_04b_withdraw_message.png`, and
`pcitem_06_deposit.png`. A second normal launch used the generated cache
directly, proving the new FireRed required-file markers do not cause a reimport
loop.

The same forced import exposed an older FireRed manifest omission in the shared
save decoder, so `0a4e087` also fills the source-defined FireRed SaveBlock2,
party, PC-item and box-storage layout fields only when they are absent. The
retained `tests/parity_frlg_save_layout.lua` regression passes **17/17** and
explicitly confirms Emerald is not assigned those FireRed-only offsets.

### R2. Player-house Mum facing/talk turn — closed, `0a4e087`

The live failure was not `NPC:update` ignoring `frozen`: the logical facing and
talk freeze path were already correct. Mum's imported overworld sheet contains
only the three standing directional frames (south, north, west). The extractor
previously required a complete walking set before preserving directional
interpretation, so those three pictures were classified as generic
`poseFrames`; `SpriteRenderer` intentionally ignores facing for a pose
sequence. That is why her internal direction changed while the visible sprite
did not.

`RomExtractorGen3:extractOverworldSprites()` now retains a valid three-frame
standing directional set when the animation table proves those directions
exist and marks a row as a walker only when its complete movement set is
present. `NPC.new` keeps both `spawnFacing` and `gen3MovementType`, and the Gen 3
`faceOriginal` movement command resolves the object's cartridge-facing from its
current movement type before falling back to older fields. This also makes
Mum's pre-rival script restore `FACE_LEFT` exactly as the source does.

Focused live validation on `MAP_G04_N00`, Mum at `(8,4)`, movement type 9,
confirmed `frames=3`, `poseFrames=nil`, `walker=false`, default visible LEFT,
and real A-button talk from all four sides. Screenshot pixels were read back:
left = frame 2 unflipped, right = frame 2 flipped, up = frame 1, down = frame 0,
and the script-restored state is again frame 2 unflipped. The final shared-tree
rerun exited 0 with no failures. A full Emerald reimport also completed with 0
unreadable overworld rows; the only short runtime "walker" rows seen by the
scratch smoke were pre-existing synthetic five-frame `_REFLECT` entries, not
extractor regressions.

### R3. FireRed warp trigger semantics — closed, `bc961a5`

The narrow directional-warp fix in `8008c6f` was not enough. FireRed had still
been treating any imported `warp_event` as an arrival warp, and after its
directional checks `Warp.extraCheck` could fall through to pokered's unrelated
"facing the map edge" fallback. That made ordinary destination cells live
warps, including cells beside house mats.

`Map:isWarpTileCell()` is now FireRed-gated to the cartridge's exact
`IsWarpMetatileBehavior` allowlist from `field_control_avatar.c`: `$60` cave
door, `$61` ladder, `$66` fall warp, `$67` regular warp, `$68` Lavaridge 1F,
`$69` warp door, `$6A/$6B` escalators, and `$71` Union Room. The directional
`$62..$65` arrows/mats and `$EC..$EF` side stairs remain walk-direction
triggers through `frlgWarpDirection`; after that FireRed returns false before
the Gen 1 edge-facing fallback. Emerald is unchanged.

The live census still imports all **486** warp destinations on ordinary `$00`
floor, but **0** are arrival-active after the fix. That is intentional data,
not missing extraction. Validation passed the retained exhaustive parity suite
**264/264**, the FireRed live census/behavior driver **14/14**, directional
mat/stair driver **9/9**, and six representative live warp classes **6/6**.
The exact Pallet player-house round trip was rerun too: the interior exit mat is
`$65`, standing beside it is inert, and the first DOWN press exits correctly.
The retained regression is `tests/parity_frlg_warp_allowlist.lua`.

### Pre-PR status after R1/R2/R3

There are **no remaining R1/R2/R3 blockers** before Ceedrack's PR. The retained
Gen 1 / Emerald routing audit above found no other FireRed path that currently
drops into a Game Boy cartridge screen. A handful of reachable shared Gen 3
screens (`Gen3MoveLearnMenu`, `Gen3EvolutionState`, `Gen3ItemMenu`,
`Gen3StarterSelect`, `Gen3Cutscene`, `Gen3DexSearch`) are intentionally shared
and were not pixel-compared to FireRed during this sweep; that is nonblocking
polish to revisit only if a concrete manual report identifies a mismatch.

The forced retail import still prints the repository's pre-existing accepted
warning that `data/generated/scenes.lua` and `assets/generated/ui/summary_info.png`
are not produced. The importer explicitly accepts that cache rather than
re-importing forever; neither warning is an R1/R2/R3 regression or a known
play blocker. The new Item PC and Item-PC bag assets *are* produced and a
normal follow-up launch consumes them without reimporting.

Ground rules learned the hard way in this repo, do not relearn them:
- Trust the cartridge's own data over any header. This port's side stairs are
  $EC..$EF even though a current pret metatile_behaviors.h names them
  $6C..$6F, and doorTiles still carries Hoenn's $6C "water door". Census the
  imported data before trusting a constant.
- A driver that "passes" can be lying. One wander driver passed only because
  the player had drifted into a house and it was watching entities that no
  longer existed. Assert the map has not changed and re-resolve entities each
  frame.
- Grep the pret source more than one way before concluding the cartridge does
  not do something. A naming-screen feature was declared "not a bug" once
  because the grep said "Pic"/"Sprite" and the real code said "Icon".

## Earlier manual PC/NPC reports — rechecked and closed 2026-09-18

The manual play report after commit `d1cedf8` had said these issues were still
present. They were kept open at that point pending the live re-check recorded
immediately below:

1. **Pokémon Center PC still shows the generic Gen 1 UI.** The focused driver
   can open the fallback menu and log `SOMEONE’S PC`, the player PC, and `LOG
   OFF`, but that does not prove the real facing-tile interaction reaches the
   same path in the visible game. Reproduce this from a fresh FireRed save at
   a real Pokémon Center PC and capture the screen and map position before
   changing the menu again.
2. **Talking to NPCs still leaves them facing the old direction.** The isolated
   `talkTo` check reports the expected direction, but the live report wins:
   verify the actual input path, the active entity selected by `interact`, and
   any script/cutscene code that immediately reposes the NPC.
3. **The Pallet Town fat NPC can still leave its allowed area and enter the
   water.** The elevation guard and the Pallet probe pass in isolation, so the
   next check must observe the live wander loop over time, including the
   imported movement range, map-cell coordinates, and the map's water/elevation
   grid. Do not close this issue from a mocked collision result alone.

At that point `d1cedf8` was treated as an attempted fix rather than a completed
resolution; the live runs below supplied the missing evidence and closed all
three reports.

### Re-checked live on 2026-09-18 — none of the three reproduces

Each was re-run the way this section demanded (real interaction, real map, live
loop; mods off) rather than through an isolated probe. Drivers are kept in
`tests/drivers/` (gitignored) and named below so the next session can repeat
them instead of re-deriving them.

1. **Centre PC — does not reproduce.** `_frlg_center_find.lua` takes the
   cartridge's own `constants.gen3HealLocations[*].respawn` map (a healer's
   room, i.e. a Pokémon Centre interior), finds its `MB_PC` (`$83`) tile,
   stands the player on the walkable cell *south* of it facing north, and
   presses A — the real facing-tile interaction. On `MAP_G05_N04` at PC tile
   `(11,1)`, player `(11,2)` facing up, it opens `SOMEONE'S PC / RED's PC /
   LOG OFF`, then the storage menu (`WITHDRAW/DEPOSIT/MOVE POKéMON / MOVE
   ITEMS / SEE YA!`), then `src.ui.Gen3BoxMenu` — the Gen 3 chain end to end.
   `ngshots/centre_02_pc_menu.png` shows it inside a real Centre (heal
   machine, counter, Poké Ball floor mark).
   The window is `src/ui/Menu.lua`, which is *not* a Gen 1 look: `Font.drawBox`
   prefers the cartridge's own nine-slice, and the probe
   (`_frlg_frame_probe.lua`) confirms the dataset carries it —
   `font.frame = "sheet"`, `frames.image =
   assets/generated/fonts/gen3_frames.png`, `count = 10`, sheet loads 24x240,
   `options.gen3Frame` unset so it draws frame 1, FireRed's default. The
   earlier report predates `d1cedf8` and the item-storage fix above.
2. **NPC facing — does not reproduce.** `_frlg_npc_face.lua` drives the real
   input path (`U.tap "a"` → `interact` → `talkTo`) against Pallet Town's own
   objects. `TEXT_MAP_G03_N00_OBJ_001` turned `up` → `down` for a player
   standing south of it and stayed turned while the text was up;
   `ngshots/npcface_01.png` shows the NPC visibly facing the player with
   FireRed's dialogue frame. `OBJ_002` was already facing the player, turned
   correctly, and then resumed its idle turning once the text closed — which
   is the cartridge's behaviour for a look-around object, not a bug (the
   driver's original "must stay turned forever" assertion was wrong and was
   relaxed).
3. **Pallet Town wanderer — does not reproduce.** `_frlg_npc_wander.lua`
   watches the live wander loop for **3600 frames** with the player parked on
   a warp-free cell, re-resolving objects by `localId` every frame and
   aborting if the map ever changes. `OBJ_002` — the wide-ranging one, range
   `6,2` — was off its origin cell on 3356 of 3600 frames and **never** stood
   on a water cell and **never** exceeded its imported range; `OBJ_001`
   (range `1,4`) stayed put, which is collision, not a failure.
   **A caveat worth keeping:** an earlier version of this driver silently
   "passed" because the player drifted into a house and it went on watching
   entities that no longer existed. Any future version of this check must
   assert the map has not changed and must re-resolve entities each frame.

These three are closed on this evidence. If any of them resurfaces in manual
play, it is a **new** regression from something after 2026-09-18, and the
drivers above are the fastest way to show it.

## Process notes for whoever picks this up

- **Always verify with a driver + screenshot read-back**, not just by
  reading the code. Several bugs this session (Trainer Tower not spawning,
  trainer pics wrong colour, the clone-object duplicate) were only found by
  actually looking at rendered output — the code read as plausible in
  isolation.
- When adding a new FRLG-only special, check `pokefirered/data/specials.inc`
  for the exact index and `pokefirered/src/*.c` for the real C function
  (grep by name) before writing the handler — don't guess behaviour.
- Never commit `tools/rom_manifest_firered.json`.
- The retained regression files include (`tests/parity_frlg_ship.lua`,
  `tests/parity_frlg_warp_allowlist.lua`, `tests/parity_frlg_save_layout.lua`,
  `tests/parity_gen3_type_categories.lua`, `tests/frlg_ship_driver.lua`,
  `tests/frlg_gyms_driver.lua`, `tests/frlg_gym_puzzles_driver.lua`,
  `tests/frlg_rocket_driver.lua`,
  `tests/frlg_rocket_traversal_driver.lua`, and
  `tests/frlg_mtmoon_battle_placement_driver.lua`,
  `tests/frlg_champion_driver.lua`, `tests/frlg_hall_of_fame_driver.lua`, and
  `tests/frlg_sevii_progression_driver.lua`,
  `tests/firered_launcher_driver.lua`, and
  `tests/console_textinput_driver.lua`) have narrow `.gitignore` exceptions
  so they can be retained; other scratch tests stay ignored. The previously
  uncommitted retained regressions plus the final gameplay/visual parity fixes
  were committed locally as `a266457` on 2026-09-17.
- Loose top-level `frlg_*.png` files in the repo root are old manual
  screenshots from earlier sessions, not driver output. Leave them alone for
  this task; they are untracked and not load-bearing.
