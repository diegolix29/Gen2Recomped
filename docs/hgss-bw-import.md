# HeartGold, SoulSilver, Black and White: import status

## BW Juniper introduction: October 16, 2026

- NEW GAME now opens `Gen5JuniperIntro` before the bedroom, using system
  message bank 44: welcome, Pokémon explanation, gender/name confirmation,
  Cheren and Bianca introductions, and the journey speech. Rejected gender
  and name choices return to their prompts; completing the flow returns to
  the bedroom once. Cheren and Bianca retain their cartridge names.
- Added `Gen5JuniperArt`. `/a/1/7/0` supplies the stage backgrounds, player
  portraits, smaller player/friend cells and Juniper's multi-cell actor.
  The existing `Gen5MonAnim` decoder bakes Juniper's idle/blink and ball
  release from NCER/NANR/NMCR/NMAR, preserving the 116/148-tick sequences.
  Minccino's front art comes from `/a/0/0/4`.
- Original-ROM captures identified the intro's rounded nine-tile message
  frame: `/a/0/0/5[11]`, palette 0 (native BG1 character 16, palette 8).
  It differs from the field's eighteen-tile frame. Screenshot inspection
  also corrected Juniper's vertical origin and Minccino's placement. Native
  BG1's font palette matches `/a/0/2/3[5]`; both ink and shadow are imported.
- Gender selection now carries into the field. The sprite table's IDs
  1/2/3 are male walk/run/bike; 4/5/6 are female walk/run/bike. Both walking
  and bicycle forms are configured, with the correct female walking sheet
  at model member 9. Selecting a name refreshes the live player form.
- Directions/A and scaled upper-panel taps operate the choices. The lower
  panel explicitly shows its native blank backdrop in combined/display
  modes. Single-screen users keep the introduction on the primary panel;
  naming uses the existing keyboard controller.
- **Parity limits:** BW's native naming keyboard is still unported (the
  shared naming screen remains functional). Gender-band geometry, portrait
  transitions, friend staging, shrink timing, music and Minccino animation
  still need native controllers/calibration. These captures verify the
  imported actors/frame and working flow, not full opening-scene parity.
  The Game Freak animation and coronation/opening movie remain pending.
- Validation: full Black/White import **99/99**, Juniper checks **186 passed**,
  boot **104 passed**, main menu **45 passed**. App screenshots inspected:
  `%APPDATA%/LOVE/hgss_ow/ow_bw_juniper_dual.png`,
  `ow_bw_juniper_gender_verified.png`, `ow_bw_juniper_minccino_verified.png`,
  `ow_bw_juniper_naming_verified.png`, `ow_bw_white_juniper_verified.png`.
  `tmp/bw_juniper_comparison.png` pairs the original ROM and app welcome.
- BW cache revision is `gen5-juniper-v4`; **re-import Black/White** to receive
  the new assets, new-game routing and female avatar configuration.

## BW native main menu: October 16, 2026

- Added `Gen5MainMenu` and `Gen5MainMenuArt`. The menu now uses BW's
  shared `/a/0/3/5` graphics: background map 2 / tiles 3 / palette 4;
  option and Continue frames 7/6; idle/focus palette rows 1/2/3. The unused
  `/a/0/2/7` editor layouts do not supply the live menu's window geometry.
  Labels and save-summary formats are system text bank 179. Text uses the
  shared window palette's row 5, roles 1/2, including its muted white ink.
- Verified the menu against **both original ROMs** in a temporary DeSmuME
  Libretro runner. Live native BG maps establish the option rectangle
  `(32,16,192,24)` and its 24-pixel row spacing. The lower screen is blank;
  the app now paints it explicitly instead of leaving the field panel there.
  Single-screen mode keeps all controls on the primary panel.
- Native registers also establish `BLDCNT=0x0844`, `BLDALPHA=0x0310`:
  BG2 adds 3/16 of BG3 to its frame colours in 5-bit channels. A dedicated
  frame shader reproduces this, including White's lighter frames and the
  red tint over the Poké Ball. Palette pulse endpoints come from the ROM;
  pulse phase timing remains reconstructed.
- New Game / Continue callbacks, B to title, OPTION, EXIT GAME, save
  summaries, scrolling and scaled pointer input work. OPTION/EXIT GAME are
  app additions. Native network/Mystery Gift/microphone applications remain
  unported and are omitted rather than shown as working options.
- The original ROM captures also corrected the boot-card order: Nintendo's
  company card precedes the copyright card. Their timing remains reconstructed;
  the Game Freak animation, opening movie and Juniper flow are still pending.
- Added optional `tools/ds_rom_reference.py` to run an externally supplied
  Libretro core, copy the ROM into an isolated output folder, capture frames
  and save/load test states. It never opens the app's saves. No emulator,
  ROM, firmware or generated capture is committed. Reference dependencies
  used here: [official Libretro core build](https://buildbot.libretro.com/nightly/windows/x86_64/latest/desmume_libretro.dll.zip),
  [Libretro API](https://github.com/libretro/libretro-common/blob/master/include/libretro.h),
  [DeSmuME state layout](https://github.com/libretro/desmume/blob/master/desmume/src/saves.cpp).
- Validation: full BW import **97/97**, boot checks **104 passed**, main-menu
  checks **45 passed**. Native captures and app screenshots were inspected
  for both versions, Continue, and title-to-menu navigation. The sampled
  background columns match the original ROMs at **4,992/4,992 5-bit pixels
  per version**. This is a background comparison, not a claim of whole-screen
  parity (supported options differ, and the pulse is at a different phase).
  Final app captures: `%APPDATA%/LOVE/hgss_ow/ow_bw_black_menu_verified.png`,
  `ow_bw_white_menu_verified.png`, `ow_bw_summary_verified.png`.
  Reference captures and `tmp/bw_menu_comparison.png` remain local and ignored.
- BW cache revision is now `gen5-menu-v3`; re-import Black/White to apply.
  Native camera choreography, title effect actors/eye patterns, audio/timing,
  coronation/opening movie and Juniper/gender/naming remain open work.

## BW retail title assets and boot wiring: October 15, 2026

- Black and White now import their own international title logo, patterned
  backdrop, PRESS START cell, developer credit and boot cards from `/a/0/2/6`
  and `/a/1/6/4`. Dedicated `Gen5Intro` / `Gen5Title` states replace the
  Platinum splash/title fallback. Card timings are reconstructed.
- The retail animated title dragons are `/a/1/6/0` members 227/235, with
  joint animations 226/234. Both articulated meshes and every joint frame
  are imported. `/titledemo.narc` contains prototype meshes and an unused
  Japanese logo; these are **not** used by this implementation.
- Native screenshot inspection caught a shifted logo caused by forwarding
  `palette()`'s secondary return into `compose()`'s tile-base argument. It
  also caught the prototype model and White's inadequate background contrast;
  all three issues were corrected before the verified captures.
- Both panels work in combined layouts. L/SELECT switches the full panel in
  single-screen mode; A/START/tap opens the existing menu with its original
  New Game / Continue callbacks. Existing BW caches must be re-imported for
  the new `gen5-boot-v2` revision.
- Verification: full Black/White import **97/97**, dedicated boot checks
  **104 passed**, native Black and White title renders, White single-screen
  render, copyright/studio cards and title-to-menu transition inspected.
  Captures are in `%APPDATA%/LOVE/hgss_ow/`:
  `ow_bw_title_native.png`, `ow_bw_white_title_verified.png`,
  `ow_bw_white_single_verified.png`, `ow_bw_copyright_verified.png`,
  `ow_bw_studio_cards.png`, `ow_bw_title_menu_verified.png`.
- **Remaining:** the coronation/opening movie, Juniper/gender/naming flow,
  BW's native main menu (currently the shared fallback), native title camera
  choreography, background/effect actors, eye texture patterns and exact
  lighting/audio/timing. The current title camera is reconstructed and the
  dragon joint tracks run at 30 Hz. This pass does not establish full boot
  ROM parity; NEW GAME still enters the bedroom.

## Five-scene HGSS opening path: October 15, 2026

- Added scene 3's dedicated New Bark, Goldenrod and Ecruteak NSBMD models,
  NSBCA joints and NSBTA texture animation from opening members 97–105.
  The fixed camera uses the source's target, distance, angle and projection.
- Screenshot inspection caught the miniature characters lying flat. Native
  SBC billboard commands now survive extraction and accept a camera transform
  during posing; city characters retain their position/scale and face the view.
  Both SBC parsers also consume optional billboard store/restore operands.
  Operand widths were cross-checked against actual city bytecode and the
  [NNS-G3D renderer implementation](https://github.com/magcius/noclip.website/blob/master/src/nns_g3d/render.ts).
- Added rival panel/silhouette reveals, the three beast strips, Eusine, Unown
  flybys and Rocket executives. Layers retain separate scrolls and windows,
  including the 254-tick expansion/pan at the end of scene 3.
- Added scene 4's hand animations and all three native starter sprites. The
  opening imports `/a/0/5/9` member 4's nine SPL resources and texture art.
  Grass/fire/water groups are 6–8 / 3–5 / 0–2; each waits for live particles
  to finish before swapping panels. The emitter-position callback uses a copy
  of resource fields, preserving the cached originals.
- Added the sparkle and scene 5's separate foreground/background maps, native
  scrolling directions and sequential panel reveal. All five scenes now run
  through to the title. Single-screen mode follows the active scene/attack;
  L/SELECT still changes panels, including the city/rival handoff.
- Corrected the opening/title/professor application clock to 30 Hz after checking
  `main.c`'s two-VBlank main loop. A fractional accumulator keeps it independent
  of the engine's 60 Hz update rate; checks cover 30, 60 and 120 Hz callers.
  Native camera holds and movie/particle timings now run at the proper speed.
  Title audio fading uses 120 engine ticks for the source's 60 application ticks.

Verified native screenshots under `C:/Users/cedri/AppData/Roaming/LOVE/hgss_ow/`:
`ow_hgss_newbark_billboards.png`, `ow_hgss_opening_goldenrod.png`,
`ow_hgss_opening_ecruteak.png`, `ow_hgss_opening_rival.png`,
`ow_hgss_opening_beasts.png`, `ow_hgss_opening_rockets.png`,
`ow_ss_opening_hands.png`, `ow_hgss_opening_chikorita.png`,
`ow_hgss_opening_cyndaquil.png`, `ow_ss_opening_totodile_single.png`,
`ow_hgss_opening_final.png`, `ow_ss_full_opening_complete.png`.
The corrected application clock was also verified in `ow_ss_city_30hz.png`
and `ow_ss_full_opening_30hz.png`; earlier snapshots show the same native poses
but were taken before the clock correction.

Validation: HGSS import **114/114**, BW import **97/97**, cache/Platinum
particle round trip **30/30**, opening/resource/lifecycle checks, billboard
geometry checks, title/menu/camera checks and the 25-slot Giratina round trip.
Re-import HGSS for `hgss-opening-montage-v6`.

**Parity limits:** source state-dispatch overhead is omitted from movie timing;
the two numbered panel-wipe effects currently use brightness reveals; city
global lighting and title material-colour animation are not calibrated to the
hardware. Starter particles reuse the existing SPL simulator's 2D projection,
not the original perspective camera. The five-scene path is playable, but this
does not claim frame/pixel-exact movie parity. BW boot/professor flow and the
service/UI gaps below remain outstanding.

## Opening movie and title motion: October 15, 2026

- Extended HGSS beyond the studio card with the first two native movie scenes:
  HeartGold sunrise / SoulSilver sunset, independently scrolling foregrounds,
  animated sun and approaching legendary, flowers crossing both panels, and
  the Ethan-to-Lyra pan with its foreground masks and scanline wipe.
- Opening sprites use the ROM's NCER origins and NANR translation, rotation,
  scale and durations. One-shot flybys clamp to their final frame. Large
  backgrounds keep all four 256-pixel screen blocks and wrap at native size.
- The opening selects `SEQ_GS_TITLE`. Single-screen mode automatically brings
  the active scene forward; L/SELECT still changes panels. Skip remains locked
  until the studio card, and completion/skip invokes the boot callback once.
- Title cameras now follow the four version-specific source targets, with
  `duration * 30` holds and five-unit movement per axis. After the source's
  2340-tick idle period (following the 30-tick lockout), the title fades audio
  for 60 ticks, fades the screen for six, and replays the opening. Returning
  from replay resets the title camera and clock without growing the stack.

Validation: HGSS import **112/112**, BW import **97/97**, cache/Platinum particle
round trip **30/30**, opening resource/timeline/input checks and title camera/
idle-replay checks passed. Native LOVE screenshots were inspected for both
versioned skies, the legendary flybys, Ethan, Lyra, single-screen sunset,
opening-to-title completion, the closer title camera and idle replay:
`C:/Users/cedri/AppData/Roaming/LOVE/hgss_ow/ow_hgss_sunrise.png`,
`ow_hgss_bird_flyby.png`, `ow_hgss_ethan.png`, `ow_ss_sunset_flyby.png`,
`ow_ss_lyra.png`, `ow_ss_opening_complete.png`, `ow_hgss_title_camera.png`,
`ow_hgss_idle_replay.png`.

**Still incomplete:** movie scenes 3–5 (3D city flyovers, rival/beasts/Rocket
montage, starter particles and final legendary layers), title material-colour
lighting, BW's boot/professor flow and the service/UI gaps below. Scene timing
uses the source's animation durations but omits application state-transition
overhead; this is not a claim of complete frame-exact movie parity.
Re-import HGSS for `hgss-opening-scenes-v5` and its additional movie assets.

## Opening continuation: October 15, 2026

- HGSS New Game now uses `HgssOakIntro`, with bank 219 dialogue, time-of-day
  greetings, Marill's native cell animation, gender/name confirmation, avatar
  refresh and the cartridge shrink pictures. Rival naming remains in the later
  story event. Tutorial pages currently use a simplified controller rather than
  reproducing every interactive DS hardware demonstration.
- Added native HGSS copyright and Game Freak credits from `/a/2/6/2`, including
  the 30-frame hold, 60-frame fade, 20-frame delay and 110-frame studio hold.
  Both panels render in dual-screen mode. Single-screen mode automatically
  brings the Game Freak credit forward; L/SELECT switches full panels.
- Fixed displaced starter-preview tiles: `palette()` returns a second value,
  which had accidentally become `compose()`'s base-tile offset. Screenshot
  verification now shows the native preview background, Chikorita and the
  separate 3D turntable correctly.
- Cache-wiring verification now recognizes the HGSS `{module, output}` build
  dispatch and uses ripgrep on Windows instead of the unavailable grep command.
- HGSS now boots into its own title: native logos and backgrounds, animated
  Ho-Oh above the clouds or Lugia underwater, native prompt and title music.
  Both panels render together; L/SELECT exposes the legendary on one screen.
- Fixed shared DS geometry decoding: VTX_DIFF uses signed 4.12 register deltas;
  inherited transforms remain distinct from matrix slot zero; each shape keeps
  the matrix palette present when it was issued. Added envelope blending with
  inverse-bind matrices and Maya segment-scale compensation for the title actors.
- HGSS main menu now imports its own frames, arrows, message-bank 442 labels,
  23-tile window width and four-tile option height. Continue reports caught
  Pokemon. Touch works on the lower panel in dual layouts and the scaled primary
  panel on single-screen devices. OPTION and EXIT GAME remain app additions;
  DS connectivity services are not offered as working features.

Validation: HGSS import/services/intro **111/111**, BW import **97/97**, cache
wiring and Platinum particle round trip **30/30**, PC/main-menu/mart **33/33**,
new title/menu input and geometry checks passed, as did the native cursor and
Giratina round trip (25 joint slots). OBJ composition checks passed. Native
screenshots were inspected for Oak's speech, the starter preview/turntable,
copyright, Game Freak credits, both legendary title scenes, title-to-menu
transition and SoulSilver's single-screen legendary view at frame 180.
Screenshots: `C:/Users/cedri/AppData/Roaming/LOVE/hgss_ow/ow_hgss_title_hg_fixed.png`,
`ow_hgss_title_ss_fixed.png`, `ow_hgss_title_menu.png`, `ow_hgss_ss_title_single.png`.
Re-import HGSS for new art/boot routing (`hgss-title-models-v4`); Platinum and BW
markers also change to rebuild their geometry with the corrected decoder.

**Not complete at this checkpoint:** the remaining HGSS opening movie scenes,
title attract loop and material-colour lighting animation, BW opening/professor flow and the
service/UI gaps listed below. The older ignored title experiment files are
stale; the verified title implementation now lives in `src/ui/HgssTitle.lua`.

## HGSS field/service repair pass: October 14, 2026

- `ReleaseAll` now unpauses the walking Pokémon, including Elm's starter
  scene. Map entry clears the old object's transient pause/recall state.
- HGSS's `MartBuy`, `SpecialMartBuy`, `PartyHasPokerus`, `PokeCenAnim`,
  `GetTrcardStars`, and storage command 158 reach their shared runtime handlers.
  Common mart stock is read from HGSS ARM9. Its purchase list opens directly
  after the ROM's BUY choice; its messages use HGSS bank 435 with its own
  entry mapping. PC interaction selects common script 2010 (not Platinum's
  2018). Fresh-party Pokerus checks write zero instead of reusing a stale var.
- Ethan/Lyra battle back pictures are extracted from `/a/0/0/6`, DP-order
  decrypted, and assigned to the player forms. Trainer fronts carry trueColor.
- The overworld lower panel uses HGSS's idle touch art rather than Platinum's
  Poketch. L opens the HGSS menu on one-screen layouts too.
- Starter choice renders the Pokémon preview and 3D turntable on their own
  panels. Single-screen mode shows the preview when inspecting a starter;
  L/SELECT switches views, and A/B still confirm/cancel. Both panels accept
  controls without a physical second display.
- Pokegear now opens with extracted backgrounds for all six skins, contact
  names from the ROM's phone-bank table, and map/radio card gates. L/SELECT
  switches its panels on one screen. **This is a basic page viewer, not full
  Pokegear parity**: phone-call scripts, radio programs, map scrolling and
  live markers still need their native controllers.
- HGSS move resources now import: 496/501 programs decode through the shared
  interpreter, plus the native particles and cell sprites. Programs 192, 224,
  226, 231 and 276 use HGSS-only opcodes 85–87 and retain generic effects;
  their handlers are not implemented yet.

Native screenshot checks: walking Chikorita in the bedroom; two-panel starter
preview/turntable; six-skin Pokegear resource composition; trainer backs;
HGSS BUY interaction (SoulSilver UI ROM with the existing shared HGSS field
fixture). An injured Chikorita healed from 8/34 to 34/34 in the nurse harness.
The screenshot harness needs native LOVE outside the sandbox on this host.
Validation: HGSS import/services 92/92; BW import 97/97; Platinum nurse-script
traversal 152 reachable instructions with its existing contest-text exception.

**Still outstanding from the current request:** full HGSS and BW Game Freak
boot/movies, native title/main menus and professor introductions; complete
Pokegear controllers; HGSS-specific shop touch layout; the five extra HGSS
animation programs; BW trainer/player art and move effects. These have not
been completed or claimed as ROM parity. New import resources require a
re-import; the HGSS cache marker now invalidates older imports.

## Continuation: October 14, 2026

Reviewed the previous research in `G:/Gen2Recomped/scratch_claude/`:
`evolution_map.md`, `hgss_ui_screens_map.md`, and `bw_ui_map.md`.

Implemented and rendered this pass:

- **BW animated battle sprites:** finished connecting `Gen5MonAnim` to import
  and runtime. Import preserves each species' Nitro resources in a compact
  `G5AN` bundle; it does not bake thousands of frames into oversized PNG
  strips. `Gen5MonAnimPlayer` advances the ROM's NCER/NANR/NMCR/NMAR sequences
  at 60 Hz and draws the body parts with their affine transforms. Both the
  player's back and the foe's front animate. Normal/shiny palettes and female
  body-part sheets are selected per Pokémon. Existing imports need re-import.
- **BW move-button type colours:** found the native u32 type-to-palette table
  in overlay 94 (Black file offset `0x14090`). Checked the same table in White.
  All 17 types now use the ROM palette on both the full touch screen and the
  single-screen strip. This replaces the previous unassigned palette list.
- **HGSS evolution:** the existing Gen4 scene now imports HGSS's identical
  top backdrop and particles, its own bottom screen, and message bank 197.
  Member 15 of the bottom-screen archive has a PMCP that already assigns its
  colours to slot 9; treating it as slot zero made the screen black, caught
  and corrected by screenshot review. The GS SDAT catalogue/archive is now
  included from the HGSS terrain pass; evolution and congratulations resolve
  to native sequences 1011 and 1188. The optional move-choice plate art is
  extracted, but its move-learning interaction is still pending.

Validation:

- HGSS import: 72 checks, zero failures.
- BW import: 97 checks, zero failures.
- Animation resources: 3,894 checks, zero failures, covering all 649 front
  and back bundles in both Black and White, references over 120 ticks, and
  truncated-bundle rejection.
- Native visual harness: 48 CPU/GPU animation raster comparisons; distinct
  female/shiny Pikachu; all 17 move-button colours; HGSS evolution assets.
- HGSS evolution parity: 19 checks, zero failures, including both HG and SS,
  byte-identical backdrop/particle pixels, message-bank selection and music.
- Existing Platinum battle scene: 186 checks, zero failures; level evolution:
  21; cross-generation data unload: 7; HGSS animation-script timing: 4.

Screenshots were captured and inspected in the workspace's `tmp/`:
`bw-animated-sprites.png`, `bw-animation-variants.png`, `bw-move-types.png`,
`battle_bw_parity_moves.png`, `hgss-evolution-assets.png`, and `evolution.png`.
`tools/hgss_bw_visual_check` regenerates the asset/animation contact sheets.
The evolution and battle harnesses now support HGSS/BW ROM overrides and a
workspace output directory, so they also render the actual runtime screens.

**Still open:** BW's evolution scene and the remaining family-specific options,
trainer card, start menu, PC, summary, bag and Pokédex layouts from the research.
BW's battle target screen and camera motion remain pending. Its camera constants
are still approximate. The live animation view currently clips to the existing
96×96 sprite viewport, plays idle sequence zero, and does not implement the
untagged motion-parameter member; oversized/special animations and additional
forms still need their own playback verification. Full ROM parity is not claimed.

All four cartridges are registered (`src/core/GameVersion.lua`) as dual-screen
games with the same second-screen modes as Platinum, single screen included.
All four are importable from the launcher and marked `PRE-ALPHA`. No
`POKEPORT_UNLOCK` override is required. The remaining parity limitations below
still apply.

## HeartGold / SoulSilver (generation 4, family `hgss`)

These games go through `RomExtractorGen4` with the per-version differences in
`src/import/Gen4Versions.lua`. Sources are pret/pokeheartgold and the
cartridges themselves.

| Stage | Status | Notes |
|---|---|---|
| text, species, moves, items, trainers, trainer lines | ported | numbered archive paths from `Gen4HgssFiles` (generated), text banks found by reading |
| encounters | ported | HGSS's own 0xC4 record (`Gen4Encounters.parseHgss`): one level per slot, a whole species table per morning/day/night, fishing 40/30/15/10/5, rock smash 80/20 |
| maps | ported | 540 headers in HGSS's layout (`Gen4MapHeaders.parseHgss`), read from the BLZ-compressed ARM9 (`NdsBlz`); land chunks' extra sound section skipped |
| events, regions | ported | Platinum's format; every file consumed to the byte, no dangling warps |
| scripts, link | ported | 853-command table generated from `asm/macros/script.inc` (`tools/gen4_hgss_scrcmd_gen.py`), with HGSS's common-script bands. 96.3% of 181,648 instructions lower through Platinum's VM via `Gen4HgssScriptAliases`; the rest are reported as unimplemented. |
| camera | ported | HGSS's own 17 field cameras (`Gen4Camera.HGSS_TYPES`, decoded from the overlay table) under Platinum's camera code, tilt ladder and controls |
| terrain | ported | all 676 land-chunk models, 106 texture sets (/a/0/4/4), each map's set and indoor/outdoor flag from HGSS's own area record (`Gen4HgssArea`, read from overlay 1's loader) |
| building models | ported | outdoor /a/0/4/0 (340) and indoor /a/1/4/8 (222), each with its own textures; `Gen4Ground` picks the indoor set for rooms |
| overworld sprites | ported | 832 sheets; sprite id → archive member from pret's table (`Gen4HgssObjectGfx`, generated by `tools/gen4_hgss_sprites_gen.py`); HGSS's 17 animation tables (`Gen4HgssFacings`) are byte-identical to Platinum's named ones; var sprites resolve as on Platinum: `map_object.c` maps ids 101–117 to `VAR_OBJ_0 + (id − 101)`. An earlier HGSS-only base of 100 put every friend one var out. Objects are re-dressed once a map's entry script has filled the var (`OverworldState:refreshGen4VarSprites`) |
| boot location, blackout and fly points | ported | `Gen4HgssField`: the bedroom start (`T20R0202` 6,6, facing down) and all 30 `sSpawnMaps` rows (18 bytes each), found together in the ARM9 and agreeing with each other |
| player sheets | ported | walk / bike / surf / field move / fishing for both players, from `player_avatar.c`'s state switch |
| area lights | ported | `/data/arealight.narc` is byte-identical to Platinum's |
| fonts, window frames | ported | font members named by their match to Platinum's (`Gen4Versions.MEMBER_NAMES`); `/a/0/3/8` is Platinum's frame archive with one member inserted, which matches the loader's frame+2 / frame+26 arithmetic |
| constants, type chart | ported | `Gen4HgssConstants`. The type chart is found in battle overlay 12 now that `NdsRom` unpacks BLZ overlays (127 of HGSS's 129 are packed). Also builds the curves, the TMs and HMs (HM05 Whirlpool), 16 badges and the new game's 143 SetFlags. Trades are built (13, from /a/1/1/2 and bank 200); marts and berries are not yet built. |
| Pokémon battle sprites | ported | all 493 species: 2,641 images (front/back, shiny, female, 78 forms), none missing |
| trainer pictures | ported | `/a/0/5/8`, five members per class like Platinum's, but descrambled in Diamond/Pearl's order (`Gen4Graphics.decryptSpriteDP`, per `UnscanPokepic` in pokepic.c); 129 classes on all 738 trainers |
| terrain heights | ported | all 676 chunks |
| battle backdrops | ported | `Gen4HgssBattle`: the 23 backdrops (Platinum's order, Johto's Elite Four rooms) × 3 times × colour/grey from `/a/0/0/7`. Same member arithmetic as Platinum except the palette base, 0xB0, per overlay 12's loader. |
| battle platforms, health boxes, HUD | ported | `Gen4HgssBattleUi` runs Platinum's battle importers over HGSS's numbered archives through a ROM view: `pl_batt_obj` → `/a/0/0/8` (same members; 343–345 add the Bug Contest net and Sport Ball), `pl_batt_bg` → `/a/0/0/7` (subscreen tilemaps 6 lower, palettes from 171 four higher, Frontier 340/341 nine higher), `pl_b_plist_gra` → `/a/0/7/1`, `b_bag_gra` → `/a/0/7/7`, `pl_font` → `/a/0/1/6` (one higher from member 4), status/item icons → `/a/0/3/9` / `/a/0/2/1`. The healthbox parts are in overlay 12 with gauges a row taller (HP 3, EXP 2); the move-button type palettes are in overlay 6. Platform members are assumed identical to Platinum's and not yet verified against the overlay 12 table. |
| party icons | ported | `/a/0/2/0` (`PATH.monIcons`), pl_poke_icon's shape with four more sheets; the ARM9 palette table is found and verified as on Platinum. |
| starter choice | ported | `ChooseStarter` opens Elm's turntable (`src/ui/Gen4HgssStarterSelect.lua`). It is drawn from the cartridge's own `choose_starter_main_res` (/a/0/8/2, the models stage's `hgssStarter` set), with choose_starter_app.c's camera (out −49.57° / 100, in −30.76° / 60 over 8 steps), its 120° turntable steps, the rock and open animations, and bank 190's words. As in `CreateStarter`, the choice goes straight into the party at level 5; the lab script then reads slot 0. `SetStarterChoice` / `GetStarterChoice` read and write the save's starter field. Choosing Chikorita in Elm's Lab gives it, then plays the lab's "received" line. `PlaceStarterBallsInElmsLab` stands `labo_mb` (room model 0x8D) on the machine at the cartridge's three points. The count follows its rule: none after Falkner's TM51, 1 after meeting the passer-by boy, 2 once you have a Pokémon, else 3. It goes through the map def's `gen4RuntimeProps`, which `Gen4Ground:objectsFor` merges like Platinum's healing balls; any script command can now stand a prop that way. |
| texture edges | ported (all Gen 4) | the material's texture parameter (+0x14) is now read. Bits 16–19 give repeat or mirror per axis and are packed as `shape.wrap` when not plain repeat. The starter balls' highlight is clamped, and repeated it had tiled every ball in white dots. Platinum gets the same on its next re-import (310 of 2,013 shapes, mostly untextured building faces). |
| intro, title, menus' art, area popup, move animations, cries | not yet | written to `gen4_version.notPorted`. Until then the boot screens are Platinum's Gen 4 screens. |

## Seeing it

```
CACHE_ROOT=G:/Gen2Recomped VERSION=heartgold ROM="./Pokemon - HeartGold Version (USA).nds" \
  love tools/gen4_hgss_import_harness
INSTALL=G:/Gen2Recomped/heartgold VERSION=heartgold MAP=T20 X=14 Y=14 \
  love tools/gen4_hgss_overworld_harness
```

The first harness imports into the version's own folder (`heartgold/`, the
launcher's layout); the second mounts that folder and runs the real overworld,
writing `ow_<TAG>.png` to the `hgss_ow` save folder. Rendered so far:

- New Bark Town: ground, Elm's Lab and houses, NPCs and the rival by the lab
  window, under HGSS's own default camera (48.7°)
- the player's bedroom: indoor building set and the indoor camera
- Route 29: trees, grass and flowers

All three are drawn by the same renderer and camera controls as Platinum.

`HARNESS=gen4_battle_harness` runs the battle harness on the same mounted
install. A wild battle draws HGSS's Pokémon sprite on its backdrop. The
platforms and HUD are still missing.

Scripts run as well. Entering the house downstairs (`T20R0201`) plays Mom's
opening scene from the map's own frame table, and her line prints in HGSS's
font inside HGSS's message box.

Elm's Lab (`T20R0101`) plays through. Its row-10 trigger (scene var 0x4108 = 0) walks the player to Elm. He explains his research and turns to the email, then walks back and releases. `GetFriendSprite` dresses the friend as Lyra or Ethan, and the text names Lyra for a boy. The machine shows its starter balls, and choosing one runs Elm's turntable and puts the starter in the party. The follower commands (`ScrCmd_605`–`609`) are no-ops, as they are on the cartridge whenever no Pokémon walks behind the player. Leaving the lab, the assistant's row-11 trigger hands over the Potions. On Route 29 Lyra and her Marill walk up, and `CatchingTutorial` runs the demonstration: Lyra's Marill L5 against a wild Rattata L2, from BattleSetup_New_Tutorial. Cherrygrove's doors (`ScrCmd_307`–`311`) are Platinum's door-animation family under other numbers. `tools/gen4_hgss_overworld_harness` takes `SET_VARS` / `SET_FLAGS` / `CLEAR_FLAGS` to start a scene from its story state. After the starter, the lab names it ("RED received CHIKORITA…"). `bufferpartymonspecies` takes a party slot, per pokeplatinum's scrcmd_strings.c; it had been read as a species id, which printed "-----" on Platinum too. `NicknameInput` opens the nickname screen under the naming bank's own title ("CHIKORITA's nickname?", bank 249; 422 on Platinum, which also showed "YOUR NAME?" until now). `NameRival` opens it for the rival ("This boy's name?"), stores `save.player.rival` and answers 1 on an empty name, so the lab asks again. Mr. Pokémon's house (`R30R0201`) plays through: he walks to the door, gives the Mystery Egg, and Oak gives the Pokédex and registers his number. The Pokégear is save state (`save.hgssPokegear`: cards, phone numbers below 75, map level), and `CheckRegisteredPhoneNumber` reads it. Mom's savings answer `CheckBankBalance` / `BankOrWalletIsFull`. `BankTransaction`'s amount dial is not built, so it answers cancelled, the script's own exit. Also aliased: `ScrCmd_795` / `796` money box, `HasEnoughMoneyVar`, `WaitButtonOrDpad`, and `ScrCmd_573` (Platinum's `UnlockMysteryGift`, now lowered on both as a save flag). `GetPersonCoords` reads an object's matrix position, answering 255 / 255 when it is absent. **Encounters and trainers:** Route 29's grass rolls from HGSS's own tables (Pidgey from the 25% grass rate; `ENC_FORCE=1` / `ENC_DEBUG=1` on the overworld harness pass and log the rolls). Route 30's trainers spot the player and battle through the shared trainer script (scr_seq_0953). After a win, that script asks `GoToIfDefeated` before running `SetTrainerFlag` itself. So on HGSS `checkwonbattle` no longer marks the trainer early; Platinum's scripts never set the flag, so it still does there. Marking early had sent every first win down the rematch / phone-gift branch. `LoadPhoneDat` answers 255 (no phone entry) while the phone is not built, and `ScrCmd_574` is `getmovementtype`. Object labels now come from HGSS's own sprite names; they had been Platinum's, so Route 30's apricorn trees read `wall_blocking_rotoms_room`. **Violet City:** the in-game trade runs: the man in T22R0601 takes a Bellsprout and gives Onix. HGSS's trade commands are Platinum's five, renamed, plus the party menu and its answer. The table is `/a/1/1/2`: 13 records of 0x54 bytes whose first twenty u32s are Platinum's layout field for field. The names come from bank 200, the 13 nicknames and then the OT names (`NPC_TRADE_OT_NUM` = id + 13; the Onix's OT is Rudy). The aide in the Pokémart (T22FS0101) gives `GiveTogepiEgg`'s Egg: Togepi, level 1, Growl / Charm plus Extrasensory, as scrcmd_pokemon_misc.c builds it. Cameron's photos go into `save.hgssPhotoAlbum` (36 at most); the album screen is not built. `MoveWarp` and `ScrCmd_379` are Platinum's `setwarpeventpos` and `gettimeofday`. **Falkner's gym:** the lift works (field/gymmick/violet.c). `VioletGymInit` puts build model 111 down at (0xF8, 32, 0x148) and pins the 3 × 3 tiles (14–16, 19–21) to its height. `VioletGymElevator` carries both to 496 and back, 16 units a frame, with the state in `save.hgssGymmick`. Until Sprout Tower is cleared, the gym guy stands on the trigger tile (`FLAG_HIDE_VIOLET_GYM_GYM_GUY_AFTER_SPROUT`), as on the cartridge. Two fixes came out of it. **`Gen4Ground:livePass` always draws the player's own chunk row**: the camera follows the player's raised position, and 464 units up the view's top edge left the chunk-row range entirely, so the gym drew black. **Trainer lines read bank 728 on HGSS** (trainer_data.c), not Platinum's 617. Falkner battles from his platform and gives the Zephyr Badge (`BADGE_ZEPHYR`), clearing the gym's other trainers, then points the player to Azalea Town. The gym's top floor draws because `followCamera` now hands `Gen4Ground` the target's ground position (`cameraFeetX` / `cameraFeetZ`) in every camera mode. Anything worked back from the view is rows off the floor on a map this tall, and three things now use the real feet: the chunk rows the live pass draws, where the 3D / tilted / third-person camera stands (it had been 230 units under the walkway), and the height the default camera's perspective spread pivots about (anchored at 0, it drew the top floor at three times its size). **Baked lighting:** HGSS's map geometry is lightmapped (`_lm` materials). Its display lists issue `COLOR`, not `NORMAL`, so the DS never lights it and the vertex colours are its lighting. The decoder now records whether a vertex was given a normal (`noNormal`), and a shape with none is packed `unlit` and left out of the area-light shade. Its resting normal (0, 0, 1) had been shaded as a wall facing the camera, and Falkner's floors drew at about a third of their brightness. Platinum's terrain issues `NORMAL` and renders pixel-identically. **Bugsy's gym** (T23GYM0102): the Spinarak carts work (field/gymmick/azalea.c, transcribed in `src/world/HgssAzaleaGym.lua`). `AzaleaGymInit` puts the four carts (build model 118) on stations 0, 1, 2 and 7 and both switches off, as on every entry. A station's trigger runs `AzaleaGymSpinarak n`: the player steps on, and the cart runs its route for the current switch state at 2 units a frame, stopping each axis at its node as the cartridge does. Stations 3, 4, 5, 9, 10 and 11 run their route backwards, with the player a tile below the cart. The player is then put on the last node's tile and steps off. From station 0 that is 209 frames, landing on (9, 24). `AzaleaGymSwitch` flips its bit in `save.hgssGymmick`. The levers' own animations, the end-of-ride camera shake and the ride's sound are not built. Bugsy battles and gives the Hive Badge. His TM89's "put it in the Pocket" line reads HGSS's pocket names (msg_0226, with the colour code and glyph stripped); it had read Platinum's bank 395 and printed a gap. **Ilex Forest's Headbutt tutor** works on Platinum's tutor commands. HGSS's tutor data now imports: `sTutorMoves` (52 rows of move, BP cost and tutor NPC, found in its overlay by the first two rows) and `fielddata/wazaoshie/waza_oshie.bin` (64 bits per moveset). `ScrCmd_656` is "can learn from NPC 3"; `PartySelectUI`, `PokemonSummaryScreen` / `GetMoveSelection` (the forget-a-move pick), `SetMonMove`, `MonHasMove` and `CountMonMoves` lower onto the existing commands. **Apricorns** (`src/world/HgssApricorns.lua`, from apricorn_tree_sys.c and the box code): each tree object carries its index (param 0 of the `apricorn_tree` band; all 31 import) and shows its fruit's sprite (262 bare, 263–269 by colour). Shaking it gives one Apricorn into `save.hgssApricorns` (99 at most) and leaves it bare until the next day. Kurt's house runs: `ScrCmd_739` opens the box as a list and a quantity box, he keeps the colour and count, and the next visit gives that many balls (Red Level, Yellow Moon, Blue Lure, Green Friend, Pink Love, White Fast, Black Heavy). The box screen's own art and the tree's shake animation are not built; the shake waits its 32 frames. The HGSS overworld harness takes `APRICORNS="3=5"` and `KURT="2=3"`. `ScreenShake ampX, ampY, count, period` shakes the camera's look-at target by amp × sin over each period, `count` times, and the script waits (ov02_02246548). The Headbutt man's demonstration in Ilex Forest (trigger at (37, 42)) plays with it. **Goldenrod and Routes 34–36:** Whitney battles, cries without giving the badge, the lass's scene at (13, 11) sets flag 0xB7, and talking to Whitney again gives the Plain Badge and TM45. `ScrCmd_522` is the hour (her postgame schedule). Route 36's Sudowoodo: on HGSS `CheckBattleWon` is `IsBattleResultWin`, true for anything but a loss or draw. The port had read it as "won" only, so catching or fleeing white-outs; now a catch sets `FLAG_CAUGHT_SUDOWOODO`, fleeing clears the road and a loss white-outs. `GetStaticEncounterOutcome` gives the outcome code (win 1, lose 2, draw 3, caught 4, fled 5), and `StaticWildWonOrCaughtCheck` is true unless the Pokémon was beaten or caught. Platinum's `checkwonbattle` is unchanged. The Department Store lift names floors from msg_0191 (`BufferDeptStoreFloorNo`), its floor window and car animation are no-ops as on Platinum's lift, and choosing 6F sets the exit to T25R1006. Also lowered: `CountAliveMons`, `PartyCountNotEgg`, `CheckDaycareEgg`, `GetItemQuantity` (which also lowers Platinum's one use of the same name), `AddMoney`, `SetObjectMovementType`, `ScrCmd_582` (the special spawn for Dig / Escape Rope), and the follower's `ScrCmd_596` / `600`. The overworld harness takes `SHOW_FLAGS` and `SHOW_SAVE` with `PARTY_DETAIL`. **Morty's gym** (T27GYM0101; field/gymmick/ecruteak.c, `src/world/HgssEcruteakGym.lua`): `EcruteakGymInit` fogs the room to black, as GymmickInit_Ecruteak does (fog offset 0, every density step at 127, colour 0). The fog is drawn per material: polyAttr bit 15 is the DS's fog-enable, imported as `noFog` where it is clear, and a fogged map (`def.gen4Fog`) bakes every other shape in the fog colour. People are billboards and stay visible, so only the people show, as on the cartridge. The 15 pit rectangles (coord script 002) drop the player back to the entrance. Each medium (objects 2–5) carries model 128 (`gym04spot`), placed on her every frame through `def.gen4PropFollow`, which also covers her walk up to the player. Its texture is a black darkness mask, so under the fog it shows nothing. `ExtinguishEcruteakGymCandle` (both the spotted and the talked-to branch) waits 30 frames, shrinks the light over 4, saves the candle as out, and turns the medium into `SPRITE_ITAKO_` (250). Falling into a pit re-runs the init and relights all four, as InitEcruteakGym does on the cartridge. Morty is home once `VAR_UNK_4079` is 1 (the Burned Tower); until then the old man walks the player out. Morty battles and gives the Fog Badge. The overworld harness takes `CMD_TRACE="pattern|pattern"` (log matching commands with their operands) and `FOG_OFF=1`. **Burned Tower to the Lake of Rage:** the beasts' scene in the Burned Tower B1F plays. `ScrCmd_523 obj, count, step, ampX, ampZ` rattles each beast in place (sub_0205BED8: offset amp × sin, the angle stepping each frame, `count` turns), and `CreateRoamer 0` / `1` release Raikou and Entei. HGSS's roamers run on Platinum's `Gen4Roamers` with HGSS's own tables (`src/world/HgssRoamers.lua`, generated from field_roamer.c: four slots, Raikou/Entei at 40 and Latias/Latios at 35, 41 locations and their adjacency). The rules are the same in both games: one long hop in 16, otherwise a neighbour other than the map just left, met one in two on its map. A long hop stays in the slot's region (Johto for the beasts, Kanto for the Latis), as RoamerLocationSetRandom does. Two fixes came out of it. `mapForHeader` prefers Generation 4 maps, and of two Gen 4 maps on one header prefers the plain id; another map def with a `header` field (`R_38`) had been answering for Route 38. The encounter check matches by header as well as by id. Chuck's gym: `CianwoodGymInit` / `CianwoodGymTurnWinch` keep the winch in the save, turn it once (answering 1, then 0) and wait out the camera pans; the waterfall props' animation (models 173–175) is not played, and the system flag the script sets only silences the waterfall's sound. Loan Pokémon (npc_trade.c): `GiveLoanMon` builds Shuckie (trade 6, Cianwood) or Kenya (trade 7, Route 35, with its mail) from the trade table at the script's level. `CheckReturnLoanMon` answers 0, 1 (not the loaned one), 2 (holding an item) or 4 (it would leave fewer than two able Pokémon), `ReturnLoanMon` removes it, and `KenyaCheckPartyOrMailbox` looks for Kenya's mail on the party (the mailbox is not built). Lance's departure from the Lake of Rage (`ScrCmd_775`) lifts him and Dragonite off the screen over 40 frames before the script hides them; the cartridge's flight path is not transcribed. Mahogany's `RunScript` / `CompareLocalToValue` / `ScrCmd_062` rows are bytes after a `goto` that no path reaches, so they are left alone. **The Rocket Hideout (Mahogany):** the B1F floor traps are wild battles (`RocketTrapBattle`: Koffing 21, Voltorb 23, Geodude 21); their flash (`ScrCmd_708`), the Persian statues' alarm (`709`) and the B2F doors' prop animations (`710`) are pictures and lower as no-ops. `MovePerson` is Platinum's `setobjecteventpos`, and `ScrCmd_530 n, on` writes sys_vars.c's magic value (or 0) into var 0x4036 + n. B2F's scene plays to `MultiBattle`, which is Platinum's tag battle in the same operand order: Lance (675) beside the player against Ariana (479) and a grunt (499). It is a long scene: the harness needs about 5,000 ticks at a press every 12. B2F's entry scene (Lance healing the party) runs while `VAR_UNK_40A9` is 0, and the doors at (30–31, 22) move aside once it reaches 3. `ScrCmd_436` (leaving the overworld for an app) is a no-op. **The Rocket disguise** (Radio Tower): `SetAvatarBits` is Platinum's `setplayerstate`. On HGSS bit 10 (`PLAYER_TRANSITION_ROCKET`) puts on the disguise and WALKING takes it off; the player is re-dressed as `rhero` / `rheroine` (sprites 258 / 259, members 95 / 96) through `Player:refreshForm`. `RocketCostumeFlagAction` / `Check` keep the save's costume flag. **Clair's gym** (T30GYM0101; field/gymmick/blackthorn.c, `src/world/HgssBlackthornGym.lua`): `BlackthornGymInit` puts the three platforms (build models 120, 121, 120 at height 48) back at (13, 75), (9, 58) rot 1 and (14, 32) on every entry. Each is a 3 × 6 floor with three buttons. Stepping on the centre one turns it a quarter about the player in 16 frames; if a wall is in the way it turns only as far as the extent tables allow and swings back, or not at all. Stepping on a side one carries the platform and the player its own width along the rotated axis, a tile every 2 frames, and bonks back to the start on anything that is not open magma. The geometry (walls, rotation probes, floor and buttons) is the C's, including its rotation check testing only `width − 1` right-wall points. Three hooks on the map def wire it in: `gen4PropFollow` runs the animation each frame; `gen4StepHook`, asked first in `onStepComplete`, is FieldSystem_ProcessStep's button test; `gen4CollisionHook`, asked first in Collision's tile verdict, is GymmickCheckCollision_Blackthorn (a platform's floor is walkable, bare magma 0x2C is not). Runtime props now carry `rotY` and a `ground` flag. A `ground` prop is never painted over the sprites; the platform's origin is its middle row, so a player standing on the rows north of it had been covered by the whole platform. In the harness, platform 1 slides five tiles west carrying the player (13 → 8). Its rotation at the start spot is refused by the walls, as it must be. The overworld harness takes `SHOW_HEIGHTS="x,z;…"` and `SHOW_PLAYER=1`. **The Hall of Fame:** the League's last room plays to the end. `HallOfFameAnim` is the machine's balls lighting one per Pokémon (prop 0x26), a no-op like Platinum's healing animation. `HOFCredits <vsTrainerRed>` is CallTask_GameClear on Platinum's `g4_clear_game`: the same game-clear flag (0x964), the Hall of Fame screen and entry, the save with HGSS's own lines (msg_0040 entries 15 and 16, "Saving… Don't turn off the power." / "… saved the game."), and the credits. After Red on Mt. Silver (1) there is no Hall of Fame screen and no entry. HGSS skips the port's Mystery Gift deliveryman, which is Platinum's. The survey that found these rows missing now counts scene scripts (map callbacks and frame tables) as well as object and sign scripts. Across the whole game, what stays unlowered is side systems: the Game Corner, Union Room, Pokéathlon, Sinjoh Ruins, the Bug-Catching Contest, Vermilion's trash-can locks, the Deoxys meteorite on Route 3 and the Battle Frontier. **Kanto's gyms:** Lt. Surge's trash cans run as gymmick_init.c / vermilion.c (a random can, then a random neighbour of it; the can check answers 1/0, 2/3, 4; a gate's three stops run two tiles apart). With the Thunder Badge both gates stand open. In the harness the first can opened gate 0. Fuchsia's and Viridian's inits set the gymmick only: Janine's walls are map collision and Blue's spin tiles are forced movement; their flash and spin animations are not built. `SetBikeStateLock` is Platinum's `forcebicycling`. `ScrCmd_452` / `453` show and close the Latias/Latios picture during Steven's scene on Vermilion's pier (DrawPokemonPicFromSpecies: an 80 × 80 front picture framed at DS tile (9, 4)), and mark the species seen. The window is Gen 2's passive pokepic box (`src/ui/PicBox`), so the script keeps running under it. In the harness (`VAR_UNK_4130` = 1, Steven's flag 0x2FD clear) the HeartGold scene shows Latias and releases it onto Route 5. Blackthorn's move relearner and tutors lower onto Platinum's reminder and tutor screens. **Voltorb Flip** (the Game Corner's machines, `CasinoGame` scrcmd 780): the art imports from `/a/2/6/4` (NARC_application_voltorb_flip, its `_lz` members LZ11) as `gen4_voltorb_flip`; the rules are `src/pokemon/VoltorbFlipGame.lua` (the 80 boards, the free-multiplier redraw, the payout, the level rules including the five-good-rounds jump to Lv. 8) and the screen is `src/ui/HgssVoltorbFlip.lua` (the board on the touch screen, the top screen's level and coin counters, the memo by touch or buttons, the quit prompt, the coin award, and SELECT holding the top screen up on one screen). **The Bug-Catching Contest** (`src/world/HgssBugContest.lua`, from overlay_bug_contest.c): scrcmds 784–790 (overlay load, start / end, the winners, judging, the caught Pokémon's name, minutes left, the registered entrants) and 507 `CountPCEmptySpace`; the run keeps the first healthy Pokémon and twenty Sport Balls, five rival entrants score from mushi_trainer.csv, the park's grass rolls mushi_encount.csv's four sets, the clock counts real minutes while flag 0x996 is set (std 10400 at twenty), the battle is the shared contest battle (BALL from the bag's slot, 1.5x), the start menu drops BAG and SAVE and offers RETIRE (std 10404), and judging scores, ranks (ties to the player) and pays out. The contest battle's touch screen is the cartridge's (battle_input.c): FIGHT / BALL / POKéMON / RUN, the net with the caught Pokémon's icon, its gender and level, and the Sport Ball with the balls left along the top. **Game Corner and odds and ends:** HGSS's points box (ScrCmd_116–118: coins, BP or athlete points in a 10 × 2 window, msg_0191 #193 / #220 / #223) and `CheckGiveCoins` run, so Goldenrod's coin seller sells. The money box reads HGSS's own lines (bank 435 #30 / #31, FieldSystem_ShowMoneyBox), not Platinum's bank 543, which on HGSS is Elm's lab. HGSS script menus sit at the script's own tile (ov01_021EDC84: the window's top-left at (x, y), frame outside, as wide as the widest row in pixels), drawn on the DS surface, and `{CURSOR_X n}` in a menu row pads to its column. Also lowered: `ScrCmd_517` / `518` (party has species; set every party Deoxys's form), `CheckMonSeen`, `GiveRibbon`, `MonHasRibbon`, `MonAddFriendship`, `WaitButtonOrDelay`, `ScrCmd_374` (hide an object), `ScrCmd_446` (map id), `ScrCmd_545` (Unown forms seen), `ScrCmd_840` (Pokémon Center / League entrance by map id), `FollowerPokeIsEventTrigger` (0: no event met data), `MysteryGift` (Platinum's stages in the same order), `MomGiftCheck` (`save.hgssMomGifts`), `BufferSealName` (msg_0015 by id) and `GetBuenasPassword` (VAR 0x4033 rerolled once a day). The Lake of Rage's Magikarp record (`src/pokemon/HgssSizeRecord.lua`, scrcmd_size_record.c) measures by the Pokédex heights now imported from /a/0/7/4 (`constants.dexHeights` / `dexWeights`). Item icons import from /a/0/1/8 (537, the ARM9 table found as on Platinum). **Walking Pokémon** (`src/import/Gen4HgssFollowMon.lua` → `gen4_follow_mon`, `src/world/HgssFollowMon.lua`; spec in scratch_claude/follow_mon_spec.md): the species → follower index tables from the ARM9 (sModelIndexLUT 0x020FF088, sFormMaxLUT, sFemaleFlagLUT), the 566 sheets from /a/0/8/1 297.. in both palettes (normal, shiny), and /a/1/4/1's too-tall flags. The lead (first not fainted, not an egg) follows where the header's followMode allows (0 never, 1 not too tall, 2 always; no Diglett / Dugtrio in the Bell Tower), comes out on the player's first step, trails to the tile the player leaves, never blocks, and is recalled while biking or surfing and by scripts (600 / 606 / 607 / 609 / 602 / 604 / 783; 729 / 730 / 727 / 596 / 732 answer from it). Talking to it runs the cartridge's rules (/a/2/2/0: 30 for the place, 70 general, in 30–41, 0–29, 42–99 order) into /a/2/2/1's results: hops (/a/2/2/2), bank 265's lines, YES / NO branches, friendship and mood. Mood drifts toward 0 a step. Not yet: emote bubbles, sounds, the Poké Ball pop, accessory / Shiny Leaf gifts, and conditions on the tile behaviour or Pokéathlon stars (such rules never match).  **Screens:** the naming screen (namein → /a/0/3/1), the party menu (pl_plist_gra → /a/0/2/1, egg bar tile 0x4B) and the mart's top screen (shop_gra → /a/0/6/0) import through the same ROM view as the battle; the other HGSS screens (options, card, start menu, PC, summary, bag, Pokédex) are HGSS designs of their own and still use Platinum's layouts over fallbacks (scratch_claude/hgss_ui_screens_map.md). **Sprite animation:** each species' own frame script (Platinum pl_poke_data, HGSS /a/1/8/0, 89 bytes a species: `src/import/Gen4PokeAnimScript.lua`) now times the two-frame battle picture instead of one pattern for all; the motion programs (squash, shake …) are recorded, not yet played. Not yet: the Pokégear and the Battle Frontier. `GetPhoneBookRematch` answers 0 while the phone is not built. Overall, 97.2% of HGSS's 181,648 script instructions lower. Most of the rest is the Battle Frontier, Pokéathlon, Union Room / Wi-Fi, the Game Corner and gym puzzles.

Check: `python tools/run_lua_check.py tools/gen4_hgss_import_check.lua`
(88 checks). The check intercepts every write, so it never touches an
installed cache. Platinum re-extracts identically after these changes.

## Black / White (generation 5, family `bw`)

These games use their own extractor (`src/import/RomExtractorGen5.lua`).
pokeblack builds the cartridge but has not decompiled the data readers yet.
So every record layout in `Gen5Data.lua` is checked against values from the
ROM rather than taken on trust.

| Stage | Status |
|---|---|
| text (encrypted, plus 9-bit compressed strings) | ported |
| species, learnsets, evolutions, forms | ported |
| moves, items (prices stored in tens), trainers and parties | ported |
| zones, matrices, map chunks | ported | `Gen5Maps` / `Gen5Field`. 427 zone headers (`/a/0/1/2`, 48 bytes each, every field measured against the archive it indexes), 255 matrices, and all 649 chunks (`WB`, `GC`, `NG`, `RD`). Every chunk's NSBMD packs through Gen 4's model pipeline. |
| ground textures | ported | each zone's area index names its set in `/a/0/1/4` (Striaton's 39 texture references are all in set 6) |
| walkability | ported | 8 bytes per tile: byte 4 is the behaviour, bit 0 of byte 6 is collision (read off a 13×15 room), translated to Gen 4 permission words |
| encounters | ported | `Gen5Encounters`: `/a/1/2/6`, 232 bytes per season (12 tables have all four). Grass, dark grass, rustling grass, surf, rippling surf, fishing and rippling fishing. Route 1 is Patrat and Lillipup from level 2. |
| type chart | ported | a 17×17 byte table found by signature (overlay 93 in Black) |
| font | ported | `Gen5Font`: the NFTR message font (5,064 glyphs, 12×15). Each 48-byte glyph slot opens with its own 3-byte width record (left, width, advance), then the 45-byte bitmap. Reading the record as bitmap was the stray dotted row on every line. |
| constants | ported | types, natures, growth curves (`/a/0/1/7`) and 8 badges |
| buildings | ported | Packs: `/a/2/2/9` (52 outdoor) and `/a/2/3/0` (64 indoor), each "AB" (building records by id, then the models in order), textured by `/a/1/7/6` / `/a/1/7/7`. Placements are x, y, z, a quarter-turn rotation (`Gen4Ground` now honours `rotY`) and the id. Pack = ⌊area ÷ 4⌋ outdoors and area − 210 indoors, from which pack holds every id a zone places; no header field gives it directly. 3,975 of 4,531 placements resolve; the rest are reported. |
| texture sets across zone borders | ported | a map's box takes in its neighbours' chunks, so it wears a merged set: its own first, then each neighbouring zone's |
| map events | ported | `Gen5Events`: `/a/1/2/5` (interactables, NPCs, warps, triggers at 20 / 36 / 20 / 22 bytes; 427 of 428 files add up exactly). Absolute matrix tiles are taken back to each map. |
| overworld sprites | ported | `Gen5Overworld`: the sprite table `/a/0/4/8` (799 ids) maps each to a member of `/a/0/4/9` (764 texture files, like Gen 4's `mmodel`). Frame order read from the sheets: three per direction for 12+ frames, a 7-frame layout for most NPCs. The player is sprite id 1 (Hilbert). |
| LZ11 | ported | `Gen5Lz` (BW's sprites and battle art use it) |
| script decode | ported | `Gen5ScriptOps` derives every command's operand width from the cartridge's own Thumb handlers (no decomp or public table exists). (1) Find the 624-slot handler table (overlay 10). (2) Identify the readers by shape: helpers that load, read and store back the script pointer at context offset 0x14. (3) A command's width is its handler's inline byte reads plus its callees' reads. (4) The table/opcode alignment (+15) is the one that makes the cartridge's own scripts decode: 3,233 of 3,383 entries end cleanly in Black, against 1,384 at the next best offset. Callee reads are counted one call deep: following deeper made 0x1C (run common script) 6 bytes instead of 2, which swallowed the `pop var` after every common-script call. Tail-jump stubs (`ldr r3, =routine; bx r3`) are followed to the routine. Three handlers are stubs, and 0x38's routine reads a var-or-value and an inline byte. Measured as 0 bytes, it made every script that used it decode askew afterwards (`38 0025 02, 32, 39` read as `38, 25 0232 0039`). With stubs followed, 3,349 of 3,383 entries end cleanly (99%), up from 3,233. Some stubs load a constant first and the routine second (`ldr r2, =constant; ldr r3, =routine; bx r3`: 0x4D, 0x4F, 0x61, 0x62); following those too gives 3,360. Before that, 0x4D read as 6 bytes and Striaton's TM gift decoded askew. |
| scripts running | partly | `Gen5ScriptLink` names the commands whose meaning the scripts make plain, in Platinum's words. That covers lock/release, face player, messages (0x3C/0x3D, with the message id at operand 3), wait for a press, close message, sound, flags, setting a variable, call/jump/return/end and wait-for-movement. It builds the same map-script pool HGSS uses, with 1,510 NPCs and signs linked. Story text also answers to `TEXT_B<bank>_<entry>`. **Conditionals:** the direct form (0x19 compare, then 0x1F with a condition byte) maps one to one. The stack form (push var 0x09 / push flag 0x10, push constant 0x08, then 0x11 and 0x1F 0xFF) is parsed as an expression. 0x11's operators come from its handler: 0–5 are < == > <= >= != (unsigned), 6 is OR and 7 is AND. **0x1F 0xFF jumps when the expression is false**: its handler pops the value and falls through on 1, as in a compiled `if (expression) { … }`. An earlier reading had this backwards, which inverted every stack conditional. That showed up when Z054's masseuse said she was exhausted on a fresh save; she checks `flag 0xAAE == 0` and sets 0xAAE herself after a massage. Each expression is rewritten as a chain of Platinum compare / check flag + `gotoif` that jumps when it fails. That gives 6,376 conditional jumps. About 5 expressions, which need a label in the middle of the chain, are left unlowered. **Common scripts:** 0x1C runs the shared script <id>. The id table (46 bands, e.g. 2000–2099 → member 854 with text bank 158) is found in overlay 10 by shape and written to `gen5_version.scriptBands`. `Gen4ScriptBands.setFamily("bw", rows)` makes Platinum's `callcommonscript` resolve through it. The push/pop pairs that save 0x8000/0x8001 around these calls become copies into slot vars from 0x8100 and back (BW's own temporary vars stop at 0x8054). Also named from their handlers: 0x29 copy var, 0x2A set var to a var-or-value, 0x26 / 0x27 add / subtract, 0x03 wait frames. Named from their handlers plus the scripts around them: 0x6C remove object, 0x6D set position (Platinum's operand order), 0x4C buffer the player's name, 0x34 / 0x36 a second message box and its close, and 0x47 the yes/no box (0 is YES, as in Platinum). Several BW commands expand into a few Platinum rows (`rewriteCompound`). 0x107 is the party menu (Platinum's trade menu and selected slot; the ok var is 1 unless cancelled). 0x102 is "is that slot an Egg" (Platinum's species read gives an Egg as 0). 0xB3 is a brightness fade (Platinum's `fadescreen`) and 0xFD mode 1 raises friendship. Also 0xA9 / 0xAA (jingle and wait), 0xB4 (wait for fade) and 0xCB (random below a bound: the DS LCG at 0x020056EC). Z054's masseuse runs end to end: offer, YES/NO, party menu, the Egg and cancel checks, fade, jingle, a random 30 / 10 / 5 friendship and the matching line. `PARTY_DETAIL=1` on `tools/gen4_hgss_overworld_harness` prints each member's friendship afterwards. 0x43 / 0x44 are the sign-style box and its close; Platinum's message + waitabpress, then closemessage. Striaton's city sign reads "Striaton City / Three Stand Together…". 0xA8 waits for the last sound. 0x38 / 0x4A are two more message boxes, 0x39 closes them and 0x4B waits on them; 0x6E reads the player's facing. 0x85 starts a trainer battle (Platinum's `starttrainerbattle`; the trainer may be a var). 0x8D writes **1 for a win**, 0x8E returns to the field and 0x8C blacks out: the scripts run `if (var == 1) { 0x8E } else { 0x8C }`. An earlier reading had all three backwards, which the gym's shape cannot tell apart. The bedroom battle settles it: Bianca's battle may be lost, so 0x8E runs unconditionally, then `if (var == 1)` gives "you're gonna be an awesome Trainer" (bank 430 #37). 0x8D is Platinum's `checkwonbattle`, which also marks the trainer beaten. 0xD5 / 0xD6 / 0xE1 check, give and count badges. Talking to Striaton's gym leader (Z007) runs the challenge and starts the battle against Chili's Lillipup L12; the battle screen has no BW art yet. With `AUTO_BATTLE=win` (`tools/gen4_hgss_overworld_harness` settles a script's battle at once) the gym gives the Trio Badge, and the three leaders explain it. With `lose` it reaches the black-out row; as on Platinum that row is a no-op because the battle's own teardown blacks out. **Cutscene camera:** 0x143 <pitch, yaw, distance, x, y, z, frames> names a point to look at, in fx32 world units (tile = value ÷ 65536, absolute matrix tiles). The gym's points at its three leaders, and Nacrene's (644.5, 583.5) is local (36.5, 7.5). It becomes Platinum's `addfreecamera`; 0x144 / 0x147 / 0x140 become `restorecamera`, and 0x13F / 0x141 / 0x142 / 0x145 are no-ops. BW's own pitch, distance and frame count are not carried, so a cutscene shows under whatever CAM TILT the player chose. The view jumps to the point rather than panning there. 91% of 81,173 instructions are now named (the shared files are in the pool). Talking to Z005's NPCs runs common script 10110 and prints its "Hello!" from bank 424. Talking to Striaton's NPCs runs their scripts and prints their lines. **Movement:** 0x64 is `applymovement` (object, u32 offset from the byte after the 8-byte instruction). All 4,129 lists end at 0xFE in Gen 4's {u16 action, u16 count} form. The object ids are Gen 4's: 0xFF is the player (1,060 sites); otherwise it is the NPC's local id. So `Gen4Movement` decodes them unchanged and Platinum's `g4_move` runs them. 98.3% of steps use actions Gen 4 already numbers the same way. The other 25 ids (all above 0x99, 177 steps) are skipped, not guessed. In Z033's queue, the NPC turns to the player, talks, then turns back. NPC visibility flags share the scripts' flag names. |
| tile heights | ported | the same 8-byte tile records: bytes 0–1 are 0 on a flat tile, and then bytes 2–3 are its height in world units (signed). The gym's dais is 14 on exactly its tiles, Striaton's ledges 24, Nacrene's streets 120. They are written as each map's `gen4HeightEdits`, the per-tile override `Gen4Ground:heightsAt` reads before any BDHC, so people stand on raised floors in 3D views. Sloped tiles (non-zero bytes 0–1, 3%) are not decoded yet and take their neighbours' height. |
| building placement | fixed | a placement's z is stored negated (north positive). Read as it stood, Nuvema's living-room furniture stood half a chunk south of its floor (floor z −250..−72, pieces 120..232) and Striaton's gym a block from its door; negated, both sit where the walls and doors say. Rotation is used as stored. |
| character transparency | fixed | the field draws character billboards with colour 0 clear whatever the texture's bit 29 says; Cheren's sheet leaves the bit off and came out on a green square. `Gen4Models.sheet(..., { color0Transparent = true })` for BW's palette formats. |
| new-game start | ported | the new-game location setter (ARM9 0x2014204) is called with zone 391, the player's room, and takes the spot from the zone header's +0x24 / +0x2C (now parsed as `spawnX` / `spawnZ`): (5, 6), facing 2. The first blackout point is the living room below (zone 390). BW's intro is not ported, so a new game opens in the room. |
| the opening (Nuvema → Route 1) | plays | Runs in the harness from the bedroom to Juniper's demonstration. **Gift box** (zone 391, member 782): 0x153 <var> is the starter app (`src/ui/Gen5StarterSelect`: Juniper's letter, the three choices with bank 430's type lines, YES/NO). The script turns 0/1/2 into Snivy/Tepig/Oshawott and gives it with 0x10C <dest, species, item, level> (Platinum's `givepokemon`). 0x057 / 0x053 / 0x054 buffer a species name / a party Pokémon's species / its nickname (byte slot first). Bianca's and Cheren's battles follow; 0x101 <dest, slot> asks whether HP is full (or an Egg) and 0x104 heals the party. **Shared files:** 0x1C runs a common script in its own context, so a shared file's `end` is lowered as a return; otherwise the give-item script's `end` ended Mom's scene. **The bag:** 0xB5 add, 0xB6 take, 0xB7 fits, 0xB8 has, 0xB9 count (Platinum's shapes); 0xBB is the pocket, bits 7–10 of the item record's u16 at 0x08, kept as `bwPocket` (0 Items, 1 Medicine, 2 TMs, 3 Berries, 4 Key Items); 0x052 names it from system bank 55. Mom gives the Xtransceiver, then the Town Map outside. **The lab** (member 792): 0x105 opens the naming screen (Platinum's `openpokemonnamingscreen`, title from system bank 81), 0x110 answers whether it now has a nickname; the Pokédex is `setflag 0x962`. **Route 1** (member 634): 0x17D is Juniper's catching demonstration. Its routine (0x0216E95C) builds a level 7 Minccino (Pound, Growl) against a wild level 2 Patrat (Tackle, Leer). The name on her side is reconstructed (no name bank holds it). Juniper then gives five Poké Balls. Still unnamed and stepped over: 0x09E, 0x0E7, 0x06B, 0x098, 0x25F, 0x048, 0x069, 0x24E–0x250 (cosmetic as far as the scripts show: nothing reads them back). |
| Accumula → Route 2 → Striaton | plays | **New-game flags:** a new game runs one shared script of nothing but `setflag`s to hide the actors whose stories haven't begun (Platinum's 112). Black's is a subroutine of band 9600 (member 866): 131 flags and `0x4116 = 1`. `Gen5ScriptLink.newGame` finds it by that shape, and the constants stage writes it as `gen4NewGame`. Without it, Accumula's Plasma crowd stood in the square from the first frame. **Triggers:** the value is the record's *second* halfword (the +6 one is 0 everywhere). Accumula's speech fires at 0x407A == 2, after Juniper's tour; Route 1's exit fires at 0x407C == 1. Coord triggers are now linked into the pool (they weren't before). **Shared object scripts:** an object script id past the zone's own (the nurse 2100, the PC 2101, 10100+) is filed under `shared.objects` as `{band, entry}`, as on Gen 4. **Counters:** BW's counter behaviour is 0xD4 (`Map:isCounterCell`). **Commands:** 0x0BE <zone, x, y, facing> is a warp (Juniper into the Pokémon Center). The nurse uses 0x0CE (time of day), 0x0D0 / 0x0D4 (today / the DS-profile birthday; equal triggers "Is today your birthday?", and `save.player.birthday` supplies one) and 0x100 (Pokérus). 0x03A <message, x, y, window> / 0x03B are the floating windows (the crowd's murmurs; shown in the ordinary box). 0x0E3 gives the Running Shoes (Mom's Xtransceiver call on Route 2). 0x068 is the player's matrix position (Striaton's guard: `if (x == 750)`). 0x0E0 is the version id (21 Black, 20 White). In the harness: Juniper's welcome and tour, the nurse across the counter, Ghetsis's speech and N's battle, Mom's call, Bianca's Route 2 battle, Striaton's no-badge guard. Unread: 0x0CC (the calling script's own id, handed to the item-ball script), 0x018 (compare a local register), 0x021 / 0x022 (a save halfword / byte). |
| Striaton → Fennel → Dreamyard | plays | **The gym's curtains** are invisible blockers. An NPC record's halfwords at +14/+16 are a pair whose meaning depends on the object. Sprite 185 (no picture, 54 objects) is a blocker that many tiles wide and tall (the gym's curtains are 7 × 1). A trainer's +14 is its sight range, and on anyone else the pair is the wander range. Blockers import as `buried` (hidden but solid) with `footprintW/H`, which `Collision.entityBlocks` honours. The right doorway's script walks the curtain aside; the wrong ones only rustle (0x187/0x189 sounds). **Decode fix:** some tail-jump stubs load a constant first and the routine second (0x4D, 0x4F, 0x61, 0x62). Read as 6 bytes, 0x4D swallowed the gym's `setvar 0x4088 = 1` after the TM, so Fennel never appeared. **Machines:** the ARM9's u16 table (TM01–92, HM01–06, TM93–95) is stamped on items 328–425 and 618–620 as `machine.move` (BW's ids aren't one run, so ItemEffects' join can't place them). 0x04D / 0x04F / 0x050 buffer an item name, a machine name and a machine's move. 0x056 buffers a type name (from the constants' own names). 0x0C2 is a warp like 0x0BE (Fennel's "follow me"). **GC chunks** (47 of them, the Dreamyard's included) have four sections: model, permissions, a second layer, buildings. Read as WB, every tile fell back to blocked. **Cut:** 0x116 is `findpartyslotwithmove` (6 = none). BW's last-talked var is 0x8011 (the overworld sets it on talk, as 0x800D on Gen 4), so the tree's shared script removes the right object. In the harness: the curtains, Chili, the Trio Badge and TM83, Fennel's HM01, the Cut tree, the Panpour gift and the Plasma grunts' battles, to the scene's end (0x4094 = 4). `PARTYMOVES=15,33` on the overworld harness sets the lead's moves. Not read yet: RD chunks' 24-byte tiles (8 chunks), GC's second layer. |
| trainers, Route 3, Wellspring Cave, Nacrene | plays | **Trainers:** an object whose script is in the 3000/5000 bands is a trainer (id = script − 3000 or − 5000), as on Gen 4; Striaton's 3009/3010 are Waiter Maxwell and Waitress Tia. Its sight range is the record's +14 halfword, and `sightWays` is Gen 4's rule on the trainer type. They now spot the player. **Trainer lines:** `/a/0/9/0` (1,762 {trainer, type} records, one per line of system bank 189) and `/a/0/9/1` (one offset per trainer, 616) are Platinum's index; the trainers stage writes `gen4_trainer_messages`. All 1,762 are reached with no duplicates, and types 0/1/2 are the challenge, the defeat and the after-battle line. **The shared trainer script** (band 3000, member 863): 0x084 trainer id, 0x097 beaten?, 0x095 / 0x096 set / clear the beaten flag (an event flag at a base plus the id), 0x092 after-battle kind (1 = heals you, from the record's byte 0x10; 2 = prize item, 0x12), 0x08A battle type, 0x103 party count, 0x088 / 0x087 message types and the line, 0x08B the encounter music, 0x066 / 0x073 the object's movement type. 0x086 <partner, foe, foe> is a tag battle (Wellspring Cave: Cheren with you against two grunts). 0x025 <flag, dest> puts a flag's state into a var, and 0x006 is a no-op. In the harness: Route 3's twins (a double battle, refused with one Pokémon as on the cartridge), Cheren, the stolen-Pokémon chase, both Wellspring grunt battles and the reward, Nacrene's arrival and Lenora's museum welcome. `PARTY=495,515` on the overworld harness builds a party of several. Not modelled: triple/rotation battle types (0x08A answers only double), and some ops that look cosmetic (0x15A, 0x1F3–0x1F7 in one zone each, 0x1B1, 0x06B, 0x0AB/0x0AC emotes, 0x09E). |
| walking between places | ported | **Doors and stairs:** in BW a door's or staircase's cell is a plain solid tile (byte 4 = 0x01, like the wall beside it), so the warp event on it is all that makes it an entrance. Pressing into a solid cell carrying a warp takes it, and pressing off the warp underfoot (an exit mat, a map edge) takes that, except on the cell the player just arrived on, until they step off it. Arriving facing south walks one step out of the doorway, as on Gen 4. **Warp records:** +4 is the kind (1 mat, 2 door, 3/4 stairs and passages) and +14/+16 a width × height. Extra cells are appended after the real warps, so `destWarp` keeps indexing. `destWarp` is stored 1-based, as the engine reads `warps[destWarp]`. **Seams:** zones cut from one matrix get Gen 4's edge `connections` (`RomExtractorGen4.linkRegions`). A BW zone is a set of chunks, not a rectangle (Route 2's box wraps round Accumula's single chunk), so after each step the matrix's zone table (`headers` on `gen4_map_matrices`) names whose chunk the player is in, and the player is handed over seamlessly. **Not Sinnoh:** Platinum's hidden-path collision patches key on the overworld matrix id, and BW's Unova overworld is matrix 0 too; they walled off Route 1's road into Accumula, and are now skipped on BW maps. Lenora's gym plays through: the quiz books, the stairs to the basement, Lenora (trainer 21), the Basic Badge and TM67. |
| Pinwheel Forest; rails (not yet) | plays to Castelia's edge | Pinwheel Forest (Z154/Z155) plays: Burgh's split, its trainers, the three-grunt chase (309, 296, 297), the Dragon Skull (579) recovered and returned to Lenora. Triggers have a **second shape**: when +8 is 1, an elevation sits between the position and the extent (x, y, signed z, width, height). There are nine such triggers (Castelia's, Route 4's, Victory Road's); read as the first shape, they were 65,531 tiles wide. **Rails are the next blocker.** Castelia (matrix 132) and Skyarrow Bridge (133) are built from "NG" chunks with no permission grid. Their warps carry +6 = 1 and rail coordinates (a line, a distance along it, a signed offset across) instead of tiles, so they need BW's rail system: its data (not yet located; ruled out: the event files, `/a/2/2/0`, `/a/1/5/6`, the 668-member move/learnset archives), rail movement, and rail-coordinate placement. **What the code says about rails (Black):** the rail zones are a fixed u16 list in the ARM9 at 0x0209E010: 28 (Castelia's centre), 249 (Skyarrow Bridge), 214, 209, 211, 66, 241–244, 36. `0x02013C70` asks whether a zone is on it. The new-game setter `0x02014204` then stores the zone header's spawn fields (+0x24/+0x28/+0x2C, Castelia's 3, 8, 1) as a rail location in the Location struct (+0x0C = 1, then halfwords +0x10/+0x14/+0x16) instead of a position. The player object carries a grid mover (+8) and a rail mover (+0x0C). Overlay 21's event check at 0x0218A340 branches into the rail code around 0x0219F01C–0x021A3960. Castelia's streets (Z030–Z034, Z037, Z041) are ordinary grid maps; only Z028 and Z036 and the bridge are rails, but every road into Castelia passes through Z028. Not the rail file (checked): `/a/0/8/1`, `/a/1/5/8`, `/a/0/9/8`, `/a/1/7/1`, `/a/2/3/1` (bitmaps), and the archives overlay 21 opens through the table at 0x021A2978 (graphics). **The camera, found on the way:** zone header halfword +0x1C bits 9–15 (`0x02013BBC`) is passed to the camera set-up at `0x0218E018`, which opens archives 60 (`/a/0/6/0`, one 1,672-byte table) and 108 (`/a/1/0/8`, 282 records of 28 bytes). Every Pokémon Center interior shares index 3. That is BW's camera table, now read: 44-byte records (38 in Black) at index × 44, giving distance (+0x00, world units), pitch (+0x04, not negated: 0x25D8 = 53.2°), half field of view (+0x12, 0x0E38 = 20°) and the look-at offset (+0x20 VecFx32). The default's distance and field of view give 1.1 pixels per unit, the scale Platinum's rows give. Each map def carries its record as `gen5Camera`, which `Gen4Camera.forMap` prefers; the player's CAM TILT choice still applies on top. Near and far planes are not decoded (far is taken from the u16 at +0x1A × 16, near is 16). |
| rail data | extracted (not walked yet) | **Found:** zone → a packed u16 table in the ARM9 right after the rail-zone list (`0x0209E026` in Black: low 11 bits the zone, high 5 an index 0–16) → `/a/1/0/9[index]` = {u16 rail file, u16 camera area} (`0x021BB278`) → `/a/0/7/9[rail file]` (`0x0219EF7C`). A rail file is a header of u32 offsets and four record sections, named in the cartridge's own bytes: **points** (`RE_POINT_n`, 112 bytes: four line slots, four direction keys, four widths, fx32 x/y/z), **lines** (`RE_LINE_n`, 72 bytes: point a, point b, then shape/camera references), **line shapes** (36 bytes; types 3, 5, 6 seen) and **curves** (36 bytes; type 1 = a circle about an fx32 centre, e.g. Castelia's round plaza about (767, 15, 765)). Castelia's centre (zone 28) is file 5: 8 points and 6 lines. Skyarrow Bridge (249) is file 11: 21 points and 20 lines. **NG chunk geometry** (an earlier reading here was wrong): `posScale` is only each model's vertex precision (Castelia's four NG chunks are 256, 128, 8 and 256), not a chunk size. Measured from the vertices, NG models reach two or three chunks past their own cell, and all of one matrix's NG chunks share ONE coordinate frame. The bridge deck (y ≈ 220) runs x −288…0 in chunk 641 and x 0…352 in chunk 644, meeting exactly at x = 0. Rail coordinates sit in a frame offset from that one by an origin not yet identified (on the bridge roughly x +1.4–2.3k, z +2.5–3.2k: the deck at z 1,240…1,926 carries rail points at z 4,415). Finding where the field code places NG models is the next step. The field stage writes `gen5_rails` (by file) and `gen5Rail = {file, cameraArea}` on each rail zone's def. Rail maps (matrices made only of NG chunks) are marked `gen5NoGrid`. Their grid is sized to the rails, all blocked, with every rail line rasterised in as walkable: straight runs, or arcs about a type-1 curve's centre, as wide as the points' widths, at the rail's own height. Gen4Ground draws a `gen5NoGrid` map's whole matrix (at most 2 × 3 chunks) rather than the cells round the camera. **Not yet:** the NG frame's origin (so the drawn models and the walkable rails line up), drawing NG chunks at their real size, movement along lines (line, distance along, offset across), and placing warps/NPCs/triggers by rail position. The camera areas (`/a/1/5/8`, 72-byte records) are also unread. |
| Castelia (rails placed, story to Burgh) | plays: Skyarrow → Castelia → Insect Badge | **NG chunk size is per map.** Skyarrow's rails run to z 4,852 on a 2 × 3 matrix and fit only 2,048-unit chunks; Castelia's ring (x 382–1,156, z 479–1,216) lies on chunk 636's street at the normal 512. No header field has been found that says which, so the rails decide: a rail map whose rails reach past twice its matrix's normal size takes the large chunk (`gen5ChunkScale`, 4 or 1, read by Gen4Ground). **Rail positions:** a record whose flag halfword is 1 is placed by <line, along, across>. The flag sits at +6 for warps and signs and at +8 for triggers, each followed by the three; an NPC's flag is at +24, with the three at +28 where its tile x/y otherwise sit. A line's sixth word is its step count (Castelia's arc from point 2 to 3 is about 477 units over 30), `along` is the step from its first point, and `across` is whole tiles, positive to the right of the line's direction. An extent is in the rail's own axes: width counts steps along, height tiles across, so Z030's exits are 1 × 8 strips across a street. The trigger "elevation" shape read earlier was this. `Gen5Events.placeOnRails` places every rail-positioned entry on every map that has rail data. That includes ordinary grid maps that still place events by rail: Castelia's plaza Z030, Icirrus, Opelucid, the League, Village Bridge and Celestial Tower. **Hybrid maps:** Z030 is one 32 × 32 chunk whose rails start at the plaza's south edge and run on to row 44. Its grid is grown to take them, keeping every cartridge cell, with the corridors opened (maps cut at the matrix corner only). On rail maps a warp is taken by stepping onto it (door cells are open ground there); elsewhere the press-into-a-solid-warp rule stands. **Story ops:** 0x069 spawns a temporary object (x, y, dir, id, sprite, script); 0x048 is the message by gender and 0x049 by version (Black first); 0x06B is addobject; 0x0AB / 0x0AC play and wait on a cry; and 0x098 / 0x09E / 0x248 (cutscene music) and 0x11E / 0x01D (badge record, common-script close) are presentation only. **Elevators** (band 10405, bank 261) work: 0x0B2 opens a menu and is **7 bytes**, not the derived 6. Its handler loads and stores the script pointer itself, so it was taken for a reader and its two read calls were never followed; the fix lifts clean script ends from 3,360 to 3,379 of 3,383. 0x0AF adds a line and 0x0B0 shows the menu. 0x1CB <u32> points, relative to the script pointer, at the building's floor table inside the script file itself (10-byte records <label, zone, x, y, z> ending at a 0xFFFF label). 0x1CC adds every floor but the current one, 0x1CD picks the floor, and 0x0A7 rides there. **Burgh's gym (Z029):** the honey walls are overlay 38's sprite-0 objects, walked through (`def.passable`). The floor switches are coord events whose 0x18C <gate> only animates (0x18D / 0x18E / 0x18F too). **Played in the harness:** the Z031 gym door (Cheren, Burgh); Z038 (the theft of Bianca's Munna); Z030 and Z028 (Burgh: "That way!"); Z031 (the Plasma door, tag battle); Z056 (the Sages, Munna returned, 0x40D7 = 1); and Z029 (both switches, Burgh, the Insect Badge). **Not yet:** rail movement itself (corridors only), the per-line rail cameras (section C: kind 1/0x11–0x13 pitch/yaw/distance, kind 3 a fixed eye and target, kind 5/6 an orbit about a point), and NG maps with a non-zero origin. |
| Route 4, Nimbasa (story to Elesa) | plays: Route 4 → Nimbasa → Bolt Badge | Route 4 (Z326) plays: Cheren's trigger and battle, the Xtransceiver call (0x155 is the caller picture, inside 0x14B/0x14A), and its trainers. Nimbasa: the gate (Z090), the arrival with Bianca and her father (Z062; 0x13D/0x13E bracket the scene, and the Bicycle comes through the item-gift script, whose key-item op 0x240 is bookkeeping), and the amusement park chase (Z064, trainer 89). **BW's variable sprites are ids 162–177**, the sixteen the sprite table points at member 0, reading vars 0x4020–0x402F. Platinum's 101–117 rule was hiding BW's item balls (id 110, on 90-odd maps). **The park's daily visitor:** 0x0D2 <var> is the season ((month − 1) % 4), 0x02B <var, value> multiplies, and 0x232 <index, dest> reads a 16-sprite table by season × 2 + badges. The table is read off 0x232's handler (`Gen5ScriptOps.handlerTable`, `constants.gen5ParkVisitors`). 0x078 is asked before a scene (followed by 0x075 1, read as "on the bicycle"; lowered as 0). 0x253, 0x154, 0x254, 0x1D3/0x1D4 and 0x022 (an unidentified save byte, read as 0) are presentation or unread. **Nimbasa Gym's roller coaster (Z063, overlay 39 in Black):** the platforms are islands. Three tables, found by the dock→track bytes `00 00 00 01 01 02 02 03 03`: the track of each of the nine docks; per track, the dock pair it joins with its switch at 0 and at 1 (+0x1C); and the docks as u16 tiles (+0x4C): (14,39) (22,39) (16,27) (16,15) (41,40) (49,40) (34,8) (22,8) (5,39). Stepping on a dock rides its track; 0x180 <n> (the four floor switches) turns track n over; 0x17F only records two trainer flags. **Played:** entrance → middle island → switch 0 → station 1's island → switch 1 → east island → switch 2 → Elesa; the Bolt Badge is awarded. **Not yet:** the coaster's ride animation (it is a teleport between docks); the 10 s stall in the park chase, where an actor's last step waits on a cell (it resolves). |
| Route 5, Driftveil, Cold Storage, Clay | plays to the Quake Badge | Route 5 (Z329) plays both scenes on var 0x4093 (Elesa sets 1; Cheren and the drawbridge raise it to 2, then 3). 0x09F is cutscene music. Its "10 s stall" warnings were Elesa's long walk, not a hang. The Driftveil Drawbridge (Z253) is walkable from row 45; row 44 has the deck's pillars. Driftveil's arrival (Z096, 0x408F → 1) plays. Cold Storage plays: the approach (Z191, 0x4090), then the grunt maze (Z192, exit hatch at (5,7)), then the storehouse (Z193). There, each of the six grunt battles adds 1 to 0x408B, and the Sages' scene runs at 7 (0x408F → 2). Driftveil's next trigger then sets 3. **Doors fixed:** `Map:isWalkableCell` made any warp cell passable (a cave-mouth rule from earlier generations). BW's doors and hatches are solid and are taken by pressing into them, so on gen5 maps that fallback is now off (Cold Storage's hatch was walked over). Pressing along the strip of the same warp you stand on no longer re-takes it: Castelia's Z034 side door to Z047 is 1 × 3 and bounced the player straight back in. **0x0C4 <zone, x, height, z, dir>** is the warp with an elevation word (67 sites). Driftveil Gym's lobby lift (Z098) drops into Clay's mine (Z097, tile (17, 25), 50 units up). The lift ops 0x1B6 / 0x192 / 0x021 are presentation and a save halfword. **Clay's gym (Z097), done:** three levels of walkways stacked on the same tiles (heights 50, 40, 30 in tiles) over Clay's floor at −59, which is what the permission grid describes. Overlay 43 (found by the first lift's bytes) holds six lifts, 24 bytes each (x, z, width, height, two fx heights), and eight walkways (+0x90, 20 bytes each: x, z, width, height, fx height). Lift n's flag 0x0A + n is set while the lift is at its lower height: the panels' scripts move it with 0x190 <n> only from the other end ("can't go any higher / lower"). The zone has no init scripts; the overlay runs its entry script, so the import reads that script's set/clear run on 0x0A–0x0F as the lifts' starting places (`gen5Lifts.initial`). **Heights on records:** NPC +34 is the object's level in tiles; sign +16 is its height in world units (the lift panels stand at 800 / 640 / 480 / −944). `src/world/Gen5DriftveilGym.lua` keeps the player's level (50 on the lobby lift's 0x0C4 arrival). It provides the collision rule (that level's walkways and the lifts standing at it; Clay's floor uses the grid), the floor heights (`gen4HeightEdits`), and other levels' people hidden and passable. `Map:signAtCell` picks the panel of the current level; a ride carries the player when aboard. BW's invisible blockers no longer answer A (they shared the panels' cells). Sprite-0 gimmick objects are buried (not drawn; their picture is the overlay's model). **Played:** lift 0 (50→40), lift 2 (40→30), lift 4 (30→50), lift 5 (50→−59), Clay, the Quake Badge (0x408F → 4). Burgh's and Elesa's gyms re-run clean. |
| Chargestone, Mistralton, Skyla | plays to the Jet Badge | Chargestone Cave (Z195): the five triggers on 0x409B (0 → 5) play in order, with their battles. The cave mouth's 0x1EB <index, x, y, z> stores a position in a save slot (lowered as a no-op). Mistralton (Z107): Cedric Juniper's Pokédex check works. 0x0DF <mode, species, var> asks whether a species is seen (Klink, 599), 0x0DD the seen count, 0x05C <slot, var, …> buffers a number, and 0x1D2 is the Pokédex upgrade (form detection). **Skyla's gym (Z108, overlay 41 in Black)** is islands joined by cannons. Two tables are found by the first landing record (9, 15, 2, 19, 0): ten cannons 0x118 bytes before it, as fx32 x / height / z (cannon 0 at (15.5, 28.5), in the wall between the entrance and the next island); and per cannon, four 20-byte landings by firing direction (0 up, 1 down, 2 right, 3 left: <id, x, height, z, index>, id −1 for none), indexed `0xC60 + cannon × 0x50 + direction × 0x14` by the overlay's own code. A press into the wall cell within a tile of a cannon's centre fires it the way the player faces (`def.gen5Cannons`, the gen5 branch of `checkGen4EntranceWarp`). **Played:** eight shots, (15,19) → (3,19) → (21,19) → (10,29) → (10,13) → (25,13) → (5,13) → (5,34) → (26,36) → (26,4) → (15,6); four trainers; Skyla; the Jet Badge. **Harness:** `WALKTO="x,y;…"` walks by a breadth-first path over `Collision.canMove`, waiting out scripts. |
| Route 7, Twist Mountain, Icirrus, Brycen | plays to the Freeze Badge | Route 7 (Z337, 0x40E7) and Twist Mountain's entrance scene (Z198, 0x40B4 → 2) play. 0x07B <object, x, height, z> is a placement without a facing. Twist Mountain is crossed by a route planned over four maps (Z200 → Z199 → Z201 → Z202 → Icirrus), and its exit scene sets 0x40BB. Icirrus (Z113): Cedric reads the party. 0x10D <var, mode> is the first non-egg slot, 0x0FC <var, slot> its friendship (70+ is "taken a shine"), and 0x0FE <var, slot> its species. **Hybrid only past the grid:** a grid map is grown for its rails only when the rails leave its bounds (Z030 yes; Icirrus Gym's stay inside its 64 × 64, and opening them cut through the gym's walls). **Brycen's gym (Z114, overlay 45 in Black):** the rails inside the grid are tracks. A chain of lines that starts at a trigger is a ride (`gen5RailTracks`: start and end cell, eight of them). One that doesn't is a walkway over the gaps (the bridges at heights 48 and 96), opened as ground. 0x195 <n> (the eight ride triggers) starts ride n only while switch group a stands at b. The gate table is found by its bytes, eight u16 pairs (0,0) (0,1) (1,0) (1,1) (2,0) (2,0) (2,1) (2,1), and a group's state is its switch's var 0x4001 + a. The three switches rotate L-shaped block arms about a fixed pivot (objects 3/4, 6/7, 9/10, moved by 0x06D) and flip their var. 0x193/0x194 animate, 0x077 is the ride's preamble, and 0x0DA <a, b, c> is a post-badge save record. Behaviour 0x18 (700 of the gym's cells, and 182 in Cold Storage) is not sliding ice. **Played:** the entrance ride, switch (15,29), the (18,29) ride, Brycen, the Freeze Badge. **Harness:** `REPEL=<steps>` keeps wild battles off story runs; WALKTO waits out battles and boxes, and moves to the next target when a warp changes the map. |
| Dragonspiral Tower | plays to the summit (0x40A7 → 9) | **BW water is a behaviour:** 0x3D is river and pond (Striaton's river, Dragonspiral's lake), 0x3F is sea (Driftveil's harbour, 1,520 cells of Undella Bay), and 0x41 is the bank (flags 0xC3 on all 922 cells: solid to walkers, crossed by surfers). The river's cells carry no collision bit, so before this they were walked on. `Map.gen5WaterAt` feeds `isWalkableCell` and `isWaterCell`. Surf is offered on gen5 maps (`tryFieldMoveOW` is called for Gen 5; `useSurfFieldMove` has a gen5 branch; `partyKnows` asks no badge, since BW has no field-move badges). Dragonspiral's entrance (Z206 → Z207, kind 2) stands one solid cell beyond the lake, and a surfer pressing into the wall at the water's edge goes in. **Rail rasterising:** the cell each sample point falls in is always opened, and two rail cells meeting only at a corner get a side cell opened, so the spiral floors (Z209, Z211) are walkable. **Script warps name matrix tiles:** the summit sends the player to zone 205 at (179, 146), local (19, 18), so on gen5 a coordinate past the map's size is taken back by its origin (`g4_warp`). 0x148 (the tower shaking) and 0x1EC (a model's set-up) are presentation. **Played:** the approach (Z205), the surf in, then every floor's trigger (0x40A7 2 → 8), nine trainers, the summit (→ 9), and back out to Z205. |
| Dragonspiral → Relic Castle → Nacrene → Opelucid | plays to Drayden's gym door | **0x021 <entry> queues the destination's script for the next warp** (all 43 uses stand before a warp; it had been read as a lift note, so these scenes never ran). Dragonspiral's summit queues zone 205's entry 4, Alder and Cedric at the tower's foot (0x409D → 1). The Desert Resort meeting at (61,30) sets 0x409D → 2. Relic Castle's quicksand is a coord over the pit: 0x0C1 <zone, x, z> is the fall, 0x0D8 <n, var> stores whether condition n of overlay 10's ten-row table (0x2170FB0: var 0x4031 + n against its value) holds, and picks the landing tile; the B3F pit queues Z165's entry 1, whose scene queues Z158's entry 5 (0x4092 → 6). Lenora hands over the stone in front of the museum (Z016, row 10, 0x4092 → 7). Opelucid's three arrival scenes run on 0x40A8 (0 → 3). Runtime: `src/world/Gen5PostWarp.lua`. **Drayden's gym (Z121, overlay 46, `src/world/Gen5DragonGym.lua`)** plays to the Legend Badge: the dragons' walkways are rail lines; per statue the save keeps a head and two switches (0x19A flips one, 0x199 settles the head: off/off 0, on/on 1, on/off 2, off/on 3), and the overlay's table at 0x21F4430 lists six lines a statue, all opened except the first two -- the neck to the floor above -- unless the head is 1. A listed line is the open one (0x21B9510). The statues' moving heads are not drawn. The rail-handler table is `table[op + 15]` (Gen5ScriptOps' offset), which is how 0x0D8's real handler was found. |
| Opelucid → Route 10 → Badge Gates → Victory Road → League → Elite Four | plays to the Champion's room scene | Leaving Drayden's gym runs Opelucid's scene (0x40B8 1 → 2); the Opelucid Gate (Z132, (2,11)) sets 3 and hands over to Route 10, whose trigger at (61,21) holds the battle (→ 4). The eight Badge Check Gates (Z356–Z363) let a player with all eight badges through and push one without them back. Victory Road's entrance (Z214, 0x40CF → 1) and the League's (Z136, 0x40A1 → 1) play. **The League's grounds are the one 64 × 64 chunk in the game** (chunk 120: the permission section's header is width, height): read as 32 × 32 the map stopped at row 31 while its spawn and entrance lie at rows 48–49, and the player stood off the map. `Gen5Field.bigGrid` builds it whole and the renderer takes chunk scale 2. **The Elite Four rooms (Z140–Z143)** ride a lift from the entry floor's platform (15, 25) to the member's floor (0x1A2 <n>, overlay task n − 1, gimmick 0x2C): the overlay is not decoded, so the ride is a lift up the player's column to the first floor tile above the solid rows, (15, 13). The room after the four (Z144) plays its scene (0x40A2 → 1; 0x25F records a save value). **Into N's Castle:** Z144's warp to Z139 is a kind-2 warp at (14, 0), the corner above a corridor that runs 15..17, so nothing can stand beside it (63 of Black's 271 kind-2 warps are like that). A press into the wall next to such a warp takes it. Z139's own kind-2 at (30, 11) leads into N's Castle (Z264), where the Seven Sages' scene plays. |
| N's Castle → the ending | plays to the game clear | Z264's gym-leader scene, the floors Z265 → Z269 → Z273 → Z277 (side warps kind 3/4 at the walls), the sage's scene in Z277 (0x40DC → 1) and the throne room (Z278, 0x40B6 0 → 6). **Text:** a BW message's 0xF000 escapes reached the box as `{CMD xxxx}` (4,269 strings) and `{VAR4+}`; `gen4Markup` now fills `{VARn}` and the 0x02xx numbers from the string slots and drops the formatting/timing codes. **The dragon:** 0x178 <species, level, flags> is the scripted wild battle (17 sites), 0x17B answers "not lost", 0x17C "got away uncaught" (N's Castle sets 0x133 on a catch), 0x17A closes it, 0x013 adds to a var, 0x121 counts the party able to battle, 0x245 <mode> moves the caught dragon from the Box into the party (mode 0 room?, 1 from the Box, 2 swap with a slot). **After N:** `returntofield` then 0x021 queues the next scene on the field's own reload, which `Gen5PostWarp` now runs without a warp. 0x156 <kind> is the game clear: kind 0 ends N's Castle and (the ending's art not being imported) puts the player in their room (Z391). |
| battle art, abilities | not yet | |

The Black/White field renders through `Gen4Ground`, with Platinum's camera
code and controls (the default camera; Gen 5's own camera table is not
identified yet). Every CAM TILT mode works on HGSS and BW: cartridge, the fixed angles, third person and first person. The options row is offered for every Gen 4-shaped cache. `CAM_TILT=cartridge|78|72|66|60|53|47|41|third|first` on `tools/gen4_hgss_overworld_harness` picks one before the first frame. Third person now stops in front of walls, for every Gen 4 cartridge (`Gen4Ground:clearCameraLine`). The line from the player's chest to the eye is marched a few units at a time. The first blocked tile (bit 15 of the permission word) that is not water and is crossed less than 32 units above its ground brings the eye in to just before it. The eye moves along the same line, so the player stays centred and the pitch is unchanged, and it never comes nearer than 12 units. Tested with Striaton's Pokémon Center and a Twinleaf house behind the player; open ground, HGSS and Platinum's default views are unchanged, and `gen4_tilt_height_check` still passes 90 / 90. Striaton City renders with its buildings: the Pokémon Center and the Gym. Route 1 renders its water, cliffs and trees.

Platinum's hidden-path chunk edits (`Gen4HiddenPaths`) are now limited to
Platinum. They are written against Platinum's matrix 0 and were stamping Sinnoh
chunks into Unova's (and Johto's) matrix 0.

`OUT_DIR=<folder>` makes `tools/gen4_hgss_overworld_harness` write its PNGs
there, not to LÖVE's save folder on the system drive.

Striaton City now draws with Hilbert and its NPCs among the buildings.

Check: `python tools/run_lua_check.py tools/gen5_import_check.lua` (88 checks).

```
CACHE_ROOT=G:/Gen2Recomped VERSION=black ROM="./Pokemon - Black Version (USA, Europe) (NDSi Enhanced).nds" \
  love tools/gen4_hgss_import_harness
INSTALL=G:/Gen2Recomped/black VERSION=black MAP=Z006 X=48 Y=16 love tools/gen4_hgss_overworld_harness
```


## Mods

`ModGens` declares generations 1 to 5. `Manifest` no longer drops a mod's
Gen 4 or Gen 5 claim.

## Black / White battles

BW battles use the two-screen battle with BW's own pieces: the stills and live multi-cell animations from /a/0/0/4 (`Gen5BattleSprites`, 20 members a species, 96 x 96 in four 1D OAM blocks; feet rows measured for placement), the HUD from /a/0/1/1 (`Gen5BattleUi`: healthboxes 165-176 on palette 163, gauge parts 164, party balls 189-192, the touch screen 91/92 with maps 93/104 and ROM-mapped type colours), the field in 3D (`Gen5BattleScene` packs batt_bgNN / batt_stageNN with their own TEX0; `src/render/Gen5BattleSceneView.lua` draws them, and the Pokémon stand as billboards on the projected platform centres, the near one scaled by depth). The camera is set by eye (no symbols); its values live in one table. Text: the message window is /a/0/0/5 tileset 10 (white for the field, palette 4 dark for battle, white letters), names in /a/0/2/3 member 2 (11 x 13). `src/battle/Gen5BattleHud.lua` draws the boxes, the bottom screen and the single-screen strip. Not yet: the target screen and the camera's moves; additional animation limitations are listed in the continuation above.

## Black / White evolution scene

`src/import/Gen5EvolutionArt.lua` reads /a/1/8/2 (the same in both games; overlay 195, shinka_demo*.c): the particle set (member 10: 9 emitters, 5 textures, read by Gen4Particle unchanged), the cylinder model (member 8, demo_sinka01 streaks) and the scene's emitter schedule (0-4 at frame 0, 5-6 at 500, 7 at 755, 8 at 783) into `gen5_evolution`. `src/ui/Gen5EvolutionState.lua` plays it on the shared Gen3EvolutionState transaction: "What? X is evolving!" (system bank 172 #0), the picture whitening a sixteenth a frame, 8 frames, the effect (SHDEMO_01, _02 at 90, _03 on the beats 530/585/640/695, _05 at 740), the two silhouettes trading places tile by tile over an 18 x 18 grid on each beat, the climax at 740, 30 frames, the fade back two frames a step, 30 frames, the new cry and #2; B while it may be stopped cuts the effect and fades the old form back for #1. Screens routes `EvolutionState` here on a Gen 5 cache. Approximate, and said so in the module: the morph's tile order (random here), the glow quad, and the cylinder (drawn as its A5I3 streak texture scrolling across the letterboxed field rather than through the model path, which draws that format opaque). `tools/gen5_evolution_harness` renders the timeline.

## Black / White party icons and party screen

`src/import/Gen5Icons.lua` imports all 649 party icons from /a/0/0/7 (member 7 + 2N, 32 x 64, two frames) into `gen4_species_sprites.icons`, the record every icon reader uses. The palette row (of three in member 0) is a table not yet found in the ARM9 or any overlay, so it is CHOSEN per icon: the row whose average colour over the icon is nearest the average colour of the species' own battle picture; the record carries `paletteChosen`. `src/import/Gen5PartyArt.lua` gives Gen4PartyMenu BW's plates (map 18 / tileset 12 / palette 6, a sampler of every plate state; navy at rest, teal under the cursor, red fainted, pink being moved, striped empty -- the state of each colour read by eye) and its blue grid backdrop (map 20 / tileset 15 / palette 2) as `gen4_party_art` and `gen4_graphics.screens["party/menu"]`; BW's party screen has Platinum's geometry (128 x 48 plates, the right column 8 lower). Still Platinum's: the plate's inner layout (name, level, HP placement), the cursor and the cancel button.

## HeartGold / SoulSilver trainer card

`src/import/Gen4HgssTrainerCardArt.lua` reads /a/0/4/9 (overlay 51). It is a new import stage, `hgss_screens`, and writes `gen4_trainer_card_art` with `hgss = true` and the per-face text ink. What it reads:

- **Card:** tiles 41, front/back 47/48, palette 0 with the level's rows 1-8 and 15 (members 0-5; no Pokédex 6).
- **Behind the card:** the diamond frame, 42/49.
- **Trainer:** tiles 44 with Ethan 54 / Lyra 55.
- **Badge board:** the backdrop 50 and the board 51 (Johto) or 52 (Johto + Kanto), on palette 28. The two league emblems are patch 53.
- **Badges:** all 16 badge sprites from 46/30/58/59. The ROM's badges are monochrome metal: blue-grey for Johto, gold for Kanto.
- **Buttons:** the two bottom-bar buttons, 45/29/56/57.

`src/ui/HgssTrainerCard.lua` extends Platinum's screen; flip, level faces, clock and signature are unchanged. `Screens` routes `TrainerCard` to it when the cache's card art is HGSS's.

The screens are swapped compared with Platinum. The card is the played (touch) screen, with "Touch Card to flip." and Cancel on the bottom bar. The badge board is the other screen. Without a second screen, the board is a third page. Text rows and windows come from `ov51_021E7F48`, and every word comes from bank 727.

Assumed, and said so in the module:

- The Kanto board appears once any Kanto badge is won. The cartridge uses a save flag the port does not keep.
- The Kanto emblem's tile row and the signature box position were measured off the art.

`BADGES=n` in `tools/gen4_overworld_harness` gives the first n badges.

## Black / White trainer card

The card is `/a/0/4/0`, which has "TRAINER CARD" in its header. The research map's `/a/0/6/3` is another app. There are no symbols, so every pairing was found by composing each map against each tileset and palette (`scratch_claude/bw040*`).

`src/import/Gen5TrainerCardArt.lua` writes `gen4_trainer_card_art` with `bw = true`. It runs from `extractBattleSprites`. What it reads:

- **Card faces:** front 41 and back 36, both on tileset 28.
- **Level colours:** palettes 5-10 for Black and 15-20 for White. They are Normal, Purple, Red, Silver, Gold, Black / White, matching Bulbapedia's level table.
- **Trainer:** Hilbert 43 and Hilda 44, on tileset 31.
- **Badge board:** map 33 on tileset 25, a strip of eight sockets.
- **Badges:** tiles 27 and cells 45. Palette 21 is clean; 22 and 23 are the dulled and dirty polish states.

`/a/0/7/2` holds the trainer battle pictures, eight members each: an 80×80 still laid out as 64×64, 16×64, 32×16, 32×16 and 16×16 OAM blocks. Hilbert is trainer 0 and Hilda is trainer 1. The card does not use them, because maps 43/44 already carry the trainer.

`src/ui/Gen5TrainerCard.lua` extends the HGSS card and uses bank 187 for its words. A tap or A flips the card; B leaves. The badge board is the second screen, or a third page in single-screen mode.

Measured off the art, and assumed:

- Row positions, and which word sits on which row.
- The board's palette (2).
- The dark ink.

Not used yet:

- The rim-decorated faces 38/39/42 on tileset 32.
- The 3D `gym_leader` models 49/50, whose eight leader-face textures go with bank 187's leader name/title/quote lines.
- The sparkle cells 8-10.

## HeartGold / SoulSilver field menu and bag

**Field menu.** `src/import/Gen4HgssMenuArt.lua` reads /a/0/1/4 and writes `gen4_hgss_menu_art`. It covers the green touch panel (screen 9), the idle Poké Ball screen (11), each button's icon (NCGR 18-48, palette 14 row 0, or row 1 for the red-rimmed selected icon), the header's close mark and the label ink.

`src/ui/HgssStartMenu.lua` extends Platinum's menu and follows pokeheartgold `start_menu.c` and overlay 27:

- Order: RETIRE, POKéDEX, POKéMON, BAG, POKéGEAR, the player's name, SAVE, OPTIONS. Each shows once its flag is set (0x6B, 0x6A, 0x11B, 0x9C, 0x11C, 0x11D, 0x11E).
- Icons sit at `ov27_0225D038`, with their words centred below them; words come from bank 196.
- Touch areas come from `ov27_0225CF68`, including the header strip, which closes the menu.
- With a second screen the menu is drawn there. Otherwise the green panel is drawn over the world.
- POKéGEAR does nothing yet; the Pokégear app isn't ported.
- Checked against Bulbapedia's capture of the cartridge.

**Bag.** `src/import/Gen4HgssBagArt.lua` reads /a/0/1/5 and writes `gen4_hgss_bag_art`:

- **Top screen:** backdrops 94/93 (boy/girl) and panel 54.
- **Touch screen:** panel 39, buttons 43 and action screen 45, each tinted per pocket by palette 41 row p.
- **Sprites:** 51/47/49/50. The pocket tabs wear their own palette rows.
- **3D trainer with bag:** models 55/74 are packed with the eight per-pocket BCA0 joint tracks (65+p / 84+p). The lit-pocket texture comes from BTP0 57+p (`kaban<p+1>` → `?_kaban.2`).

`src/ui/HgssBagMenu.lua` extends Platinum's bag, which keeps pockets, actions, trash, register, battle and pick handling. What it adds:

- **Touch screen:** eight pocket tabs; six items per page in two columns of three, from `ov15_02200684`; previous/next/back buttons; the action screen as a 2×2 grid with back meaning CANCEL.
- **Top screen:** the 3D trainer seen from behind, playing the pocket's animation with its pocket lit (checked against Bulbapedia's captures), plus the item's name and description.
- **Text:** bank 10 (entries renumbered from Platinum's bank 7).
- **Single screen:** only the touch screen is drawn.

Measured or assumed: where the item name and count sit inside a slot, the camera, the cursor drawn as a rounded rectangle, and the text inks.

Not yet: the TM type/category icons, the quantity screens 52/53, and moving items.

**Harness.** `tools/gen4_overworld_harness` takes `SECOND_SCREEN=vertical` (with `H=768`) to capture both screens.

## HeartGold / SoulSilver Pokémon summary

`src/import/Gen4HgssSummaryArt.lua` reads /a/1/6/2 and writes `gen4_hgss_summary_art`. Every summary background comes from this archive, per `sub_020887C4`:

- **Palette:** 0, on both screens.
- **Top pages:** char 2, screens 13 / 19 / 10.
- **Touch pages:** char 1, screens 12 / 17 / 9. Screens 77 / 78 are the same pages with only two tabs.
- **Caught-ball icons:** all 26, with their palettes from the `_02104C68` table.

`src/ui/HgssSummaryMenu.lua` extends Platinum's summary and keeps its species, dex number, types, HP/EXP arithmetic and picture. The memo comes from bank 302, which is numbered like Platinum's bank 455.

HGSS's three pages:

- **INFO:** the trainer memo on top; the info grid and EXP bar on the touch screen.
- **MOVES:** stats and ability on top; the four moves on the touch screen.
- **RIBBONS:** only when the Pokémon has a ribbon.

The right-hand column is the same on every page. On top it shows the ball, name, gender, level, picture and item. On the touch screen it shows the six party boxes (tap one to switch) and Cancel.

Words come from bank 302; abilities from 720 (names) and 722 (descriptions). In single-screen mode SELECT swaps between the two screens.

Text positions were measured off the art and Bulbapedia's captures; the summary itself is still assembly. A summary opened to choose a move to forget still uses Platinum's screen.

The harness now takes `PRESS_KEY=<button>` for its scheduled press, and `SCREEN=SummaryMenu` opens on the lead.

## Black / White field menu, bag and item icons

**Field menu.** `src/import/Gen5MenuArt.lua` reads /a/0/7/1 and writes `gen5_menu_art`:

- the grid-paper backdrop (screen 14);
- the 6 / 5 / 4-entry tab layouts (screens 16 / 18 / 17 on char 2);
- the icons (char i, cell i+15, palette 1). Cell 0 is a displaced pose; cells 1-4 are the resting icon bobbing.
- the cyan cursor tab (13);
- the red ✕ from /a/0/8/3.

`src/ui/Gen5StartMenu.lua` extends Platinum's menu and lays it out as in Bulbapedia's capture: POKéMON, POKéDEX / BAG, name / SAVE, OPTIONS, two to a row, with words from bank 34. It is drawn on the touch screen, or over the world in single-screen mode.

**Bag.** `src/import/Gen5BagArt.lua` reads /a/0/8/8 and writes `gen5_bag_art`:

- **Touch screen:** list background 5 / 2 (boy / girl), palettes 4 / 1.
- **Top screen:** item panel 23 / 24 (palettes 16 / 12), over the pattern of screen 7.
- **Bag picture:** pieces from char 15 / 11. Cells 0-4 are each pocket's piece at rest (4 is the bag itself), 5-9 lit and 10-14 opened. They share one anchor.
- **Sprites:** list capsule, scrollbar, TM discs, register buttons.
- **Shared buttons** (/a/0/8/3, cell 21): 0 is ✕, 1 is back, 18 / 19 are « ».

`src/ui/Gen5BagMenu.lua` extends the HGSS bag, which in turn extends Platinum's item logic:

- five pockets, taken from the items' own `bwPocket`;
- the bag picture on the left, with the open pocket's piece shown opened;
- seven-row capsule list, scrollbar, and « pocket name » with back;
- actions as capsules over the list;
- words from bank 3 (numbered like HGSS's bank 10) and pocket names from bank 55.

Positions were measured off Bulbapedia's capture. Stand-ins: the black foot bar is drawn as a gradient because its art isn't found yet, and the boy's top palette was chosen by eye.

**Item icons.** `src/import/Gen5ItemIcons.lua` writes `gen4_graphics.screens["items/icon_NNN"]`. The item → (picture member, palette member) table is in the ARM9 (Black 0x9AB6C). It is found by its opening run, (1001,1002)(2,3)(4,5), rather than by address.

### Follow-ups (October 14)

**HGSS summary**

- **Move details:** press A on the moves page, or tap a move. The details panel replaces the party column and shows the Pokémon's icon, the move's type, category, power, accuracy and description, with the move in a red frame. The panel is drawn in the page's own colours, following Bulbapedia's capture; its art hasn't been paired yet.
- **Switching moves:** A on one move, then another, swaps them, as does the Switch button.
- **Move-learning:** every summary push now goes to the HGSS summary when its art is present, including the move-learning push (`choose`) that the Gen 4 alias used to decline. That push shows screen 18 with a fifth row holding the offered move. A or a tap on one of the four answers with that slot; the fifth row or B refuses.
- **Harness:** `LEARN_CHOOSE=<move>` opens the summary in this mode, and `PRESS_KEYS="5:right,9:a"` presses buttons on chosen ticks.

**BW bag**

- **Bag picture:** the mapping from bag piece to pocket comes from Bulbapedia's per-pocket captures. The bag itself is Items, the green case Medicine, the disc case TMs, the pouch Berries, the keyed box Key Items. Pieces at rest use cells 0-4; the open pocket's piece is opened (cells 10-14).
- **List rows:** each row opens with its grey cap (31: cells 3 / 6 / 7 for item / TM / HM). TMs read "No. NN Move" from bank 3 #69 via the items' `machine.move`. Long names are squeezed to fit.
- **Foot:** «, », the registered-item box and check box (Key Items), the red ✕ and the blue back.
- **Toss:** the count is the quantity window (screen 35), and the prompt comes from the ROM's bank 3.
- **Single screen:** SELECT shows the top screen.
- **Still a stand-in:** the black foot bar's art isn't found yet. The boy's top palette was chosen by eye.

## Black / White Pokémon summary and type badges

**Summary art.** `src/import/Gen5SummaryArt.lua` reads /a/0/7/8 and writes `gen5_summary_art`, all on palette 0 unless noted:

- **Grid paper:** screen 62 on char 12.
- **Touch info page:** screen 63 on char 8.
- **Touch moves page:** screen 66 on char 8.
- **Top memo panel:** screen 64 on char 10.
- **Top stats diagonal:** screen 67 on char 10.
- **Title strips:** 65 «STATUS» and 69 «RIBBONS», both on char 9 with palette 1.
- **Move capsules:** char 15, cell 81, palette 5.
- **Red cursor:** char 14, cell 80, palette 3.

The pairings were found by composing combinations (passing the palette as the last `compose` argument shifts every tile; see the memory note) and checked against Bulbapedia's captures.

**Summary screen.** `src/ui/Gen5SummaryMenu.lua` extends the HGSS summary, so it inherits move details, switching and the move-learning answer.

- **STATUS page:** the memo on top (bank 188: nature, M/D/20YY, place, met level, characteristic). The touch screen shows the info grid with the Unova Dex number (national 494-649 → 000-155 until the National Dex), the Pokémon's panel, the item and the EXP bar.
- **SKILLS page:** stats with the HP bar, plus the ability (banks 182 / 183) on top; the four move capsules on the touch screen. A move's details replace the stats on top.
- **Words:** bank 158, numbered like HGSS's 302.
- **Stand-ins:** the SKILLS top's value column and ability box; the «STATS» word (only the «STATUS» strip is used); the caught ball shown as its item icon at half size. The foot's page icons aren't found yet; the current page is outlined.

**Type badges.** `src/import/Gen5TypeIcons.lua` reads /a/1/2/4, found by scanning for a cell bank of eighteen 32×16 cells, and writes `gen4_graphics.battleObjects.type_icons_*`:

- the types: char 23, cell 24, palette 22, in type order;
- the categories: char 26, cell 27, palette 22. Cell 0 is status, 1 physical, 2 special, judged by eye.

## HeartGold / SoulSilver PC boxes

**Art.** `src/import/Gen4HgssBoxArt.lua` reads /a/0/1/9 (overlay 14) and writes `gen4_hgss_box_art`:

- **Touch-screen layers:** base 0 on char 1, frame 2 on char 3 (palette 4).
- **Wallpapers:** all 24 (char 16+n, shared screen 15, palette 40+n), drawn at (0, 8), with each wallpaper's own ink for the box name.
- **Top-screen preview panel:** 5 on char 6, palette 7.
- **Panels:** party panel 8/9, marking panel 10 and message bar 11, all on char 14.
- **Hand and arrow sprites:** char 66, cell 67, palette 69.

**Screen.** `src/ui/HgssBoxMenu.lua` extends Platinum's PC, which keeps all of the box logic.

- **Touch screen (the game screen):** the box with its header arrows and 30 icons at (20 + 24c, 53 + 24r); the party panel down the right; the action menu as a button column (x 166-250 from y 42, 24 px apart); EXIT.
- **Other screen:** the preview, i.e. the message bar, No., species, gender, type badges, nickname, level, NATURE / ABILITY / ITEM, moves and picture.
- **Words:** bank 24 (box words; wallpapers from 35) and bank 25 (messages, numbered like Platinum's 19). The wallpaper menu lists HGSS's 24 wallpapers.
- **Single screen:** SELECT shows the preview.

Positions were measured against Bulbapedia's capture. Stand-ins: the buttons are drawn in the panel colours (their art isn't paired yet), and the moves box behind the move list isn't drawn.

## Black / White PC boxes

**Art.** The box archive is /a/1/1/6, found by scanning for a 168×160 wallpaper screen with 24 wallpaper sets. `src/import/Gen5BoxArt.lua` writes `gen5_box_art`:

- **Touch screen:** base 0 on char 1 and frame 2 on char 3 (palette 4); the frame includes the dotted ground and the black foot.
- **Top screen:** 5 on char 6, palette 7. Its top 256×192 holds the windows: title bar, No. / name / type, nickname / NATURE / ABILITY / ITEM, MOVES LEARNED.
- **Wallpapers:** shared screen 13 on char 14+n, palette 38+n, drawn at (0, 8), with each wallpaper's ink for the box name.
- **Party panel:** 8 on char 12.
- **Hand and arrows:** OBJ char 67, cell 68, palette 70.

**Screen.** `src/ui/Gen5BoxMenu.lua` extends the HGSS PC, and through it keeps Platinum's box logic. It is laid out as in Bulbapedia's capture:

- **Box:** « » arrows round the box name; 30 icons at (22 + 24c, 50 + 24r).
- **Right of the box:** the party panel in the dotted area when open, or the action menu as a button column.
- **Foot:** PARTY PKMN, the red ✕ and the blue back.
- **Top screen:** the mode's title (bank 10 #37-40), the Pokémon's No., species and type, nickname, gender, level, nature, ability (bank 182), item, MOVES LEARNED and picture.
- **Words:** bank 9 (wallpapers from 41) and bank 10 (messages, mapped from Platinum's numbers).

Follow-up: the BW summary's SKILLS top now uses its own art: screen 73 on char 10 (the stat columns and ability box), plus screen 74 for a move's details, with the «STATS» (75) and «BATTLE MOVES» (76) title strips. These replace the drawn stand-ins. The page icons in the foot are still not found.

## Trainer pictures and battle music (all three DS games)

- **Map-local flags reset on every map load (Gen 4).** `Gen4Commands.clearTempFieldEventData` clears flags 0x00–0x3F and vars 0x4000–0x401F. It runs from the map-load seam in OverworldController, as pokeheartgold's `ClearTempFieldEventData` (field_warp_tasks.c) does.
  - Without it, Twinleaf Mom's `checkflag 2` heal branch stuck forever. She never gave the Journal, so flag 143 was never set and Dawn's Route 202 trigger kept saying "did you tell your family?".
- **BW trainer pictures:** `src/import/Gen5TrainerPics.lua`, run from `extractTrainers`.
  - `/a/0/7/2` holds 95 pictures of 8 members each. +0 is an 80×80 still made of 1D blocks (64x64, 16x64, 32x16, 32x16, 16x16); +7 is the palette.
  - Class → picture comes from an ARM9 u8 table (Black 0x9C23C). It is found by content: 0..46, then 40.
  - The backs are in `/a/0/7/3` (6 pictures). They are drawn from RECN cell 0 over the linear 256×128 parts bitmap (+1), read as a 32-tile-wide grid, which gives a 56×128 standing pose. They are stamped as `field.playerForms.boy/girl.back`.
- **BW audio:** `src/import/Gen5Audio.lua` reads `/wb_sound_data.sdat` (SYMB names intact) and writes `audio`.
  - Zone music is 4 u16 per zone, one per season. The month cycles Jan=spring … Apr=winter.
  - NitroAudio plays the sequences unchanged.
- **Battle themes by class:** `src/import/Gen4BattleMusic.lua` writes `gen4_battle_music`, read through `BattleState:computeMusicKind`. A number is played as is.
  - **Platinum:** 35 `{transition, seq}` rows. The class switch at ARM9 0x02051C20 (class−62, 41 cases, default row 33) is decoded from its jump table.
  - **HGSS:** 45 rows (pokeheartgold asm/unk_020517A4.s). They are preceded by 32 `class|row<<10` and 11 `species|row<<10` entries. Wild/trainer themes swap to the Kanto ones when the map header's region is nonzero.
  - **HGSS jingles:** WIN3 for leaders, Elite Four and Champion; WINBRAIN for the Frontier Brains; WIN1 for other trainers; WIN2 for wild battles.
  - **BW:** overlay 21 0x021CF748 reads ARM9 0x0209FEE4 (28 u16 `class | index<<7`). An index below 11 picks from overlay 21's list (rival ×2, gym, Elite Four, champion, N, N, N2, Ghetsis, Plasma, Cynthia); any other class gets VS_TRAINER. BW victory jingles (WIN3 for leaders, Elite Four and Champion) are inferred, not traced.
- **Eyes-meet themes:**
  - **HGSS:** `{class, Johto, Kanto}` rows; default EYE_J_SHOUNEN.
  - **BW:** `{class, theme}` rows at ARM9 0x0A35A8.
  - Both are written as `gen4_trainer_music` (with a `default`). The sighting sting now runs for every DS game (`isNds`).
- `audio.battle` for HGSS now uses the `SEQ_GS_VS_*` / `SEQ_GS_WIN*` names. It was empty, so HGSS battles had no music.

## Openings (boot → title → professor → bedroom)

- **Harness:** `BOOT=1` on tools/gen4_overworld_harness runs the engine's own splash → title chain (Game:makeTitleState). Other options:
  - `SHOTS="t1,t2"` saves frames mid-run.
  - `MENU_PICK=new` puts the main-menu cursor on NEW GAME.
  - `TOPIC_PICK=3` answers HGSS Oak's topic menu.
- **Platinum** plays through: copyright, ESRB, Game Freak, the opening movie, the title, then Rowan's speech, naming and the TV scene in the bedroom.
- **HeartGold** plays through: copyright, Game Freak, the opening montage, the HgssTitle logo, the HGSS main menu, then Oak (topics, Marill, gender, naming, shrink) into the bedroom. Fixes in this pass:
  - The stale cache booted Platinum's `Gen4Title`; a full re-import fixed it.
  - `startFacing` was the cartridge's number. It reached `Collision.target` and crashed right after Oak's speech; it is now a name.
  - `HgssOakIntro:text` returned gsub's count, which put a number into the topic list and crashed the draw. The same bug existed in `Gen5JuniperIntro:text`.
- **Black/White** plays through: boot cards, the title, the main menu, then Juniper (Minccino, gender, naming, Cheren/Bianca) into the bedroom scene.
  - **The title is driven by ROM data from `/a/1/6/0`.** Each part has its BCA0 just before it:
    - **dragon:** 227 (`title_b_01`, 5,620 frames); White 235 (`title_w_01`)
    - **stage:** 232 (`title_b_03`: check_b / glow / rays); White 240
    - **camera track:** Black 233, White 241. Format: u32 frame count, u32 0x00010100, then six floats per frame (look-at, eye) in model units. 224 is the 451-frame riza_bridge scene, not the title.
  - The field of view is still 42° by assumption.
  - `fx_rays1` is left out: its translucent texture needs DS blending plus a material fade not yet read.
  - PRESS START sits on the top screen (rows 164–170).
  - Music: `SEQ_BGM_TITLE`; Juniper plays `SEQ_BGM_STARTING`.
  - **Not ported:** BW's opening movie between the copyright card and the title (its camera tracks are 233/241's siblings) and the Game Freak logo animation.

## Black/White opening movies and HGSS prize money

- **BW boot order (ARM9 state machine at 0x0202F9F8):**
  1. Overlay 88 boot cards (proc 0x021BD8E8).
  2. Overlay 179 mode 0.
  3. Mode 1, unless skipped.
  4. Mode 2.
  5. Overlay 88 title (proc 0x021BD574).
- **Overlay 179** is `cdemo_main.c`, a scripted movie player.
  - **Movie records:** 12-byte entries of `u16 archive, u16 frames, u32 bytes, u32 VRAM offset`. Each frame is one LZ11 member: a 256-wide RGB555 bitmap, shown at 15 fps (ticks against 66,667 µs).
  - **Scripts:** ops of a size from the overlay's own table: 0 wait, 1/2 fade, 5 wait for fade, 14 BGM, 18 play movie, 20 end.
  - **Mode 0:** `/a/2/2/5`, 151 frames, Game Freak logo, `SEQ_BGM_GF_LOGO`.
  - **Mode 1:** `/a/1/3/4`, 670 frames, N's coronation, `SEQ_BGM_TITLE`. It is 170 lines placed 11 lines down, and starts 80 frames after the music.
  - **Mode 2:** `/a/2/2/6`, 174 frames, the "Hopes! Dreams! Discoveries!" reel, `SEQ_BGM_TITLE01`.
- **Import:** `src/import/Gen5OpeningArt.lua` finds the overlay by its string and reads the records, scripts and op sizes. It copies the three archives into the cache (`bw_opening/movie_N.narc`, about 26 MB).
- **Playback:** `src/ui/Gen5Opening.lua` decodes a frame at a time (about 5 ms each). `Gen5Intro` pushes it before the title, and A/START skips to the title.
- **Title music:** the title proc plays 0x3EF, `SEQ_BGM_POKEMON_THEME`.
- `/a/1/6/0`'s `cdemo_*` 3D scene is not the opening. It is the cruise ship arriving in Castelia (an in-game cutscene).
- **HGSS prize money:** `Gen4TrainerPrize.parseHgss` reads `sPrizeMoneyTbl` from overlay 12 (0x81 `{class, multiplier}` rows; unknown classes use the Youngster row). It is written with the `battle_music` stage. Falkner pays 13×4×30 = $1,560.
- **BW prize money:** BW pays by the same formula, using each trainer's `moneyRate`.

## Mystery Gifts after the Hall of Fame (all three DS games), and White

- **White** imports in full, and its opening plays: the same ROM-read movies (overlay 179 matches Black's) through to the White title.
- **Platinum:** unchanged. One gift per Hall of Fame entry, delivered by the Poké Mart deliveryman.
- **HGSS:** now gets the offer too (it was skipped before). The list is `Gen4MysteryGift.HGSS`, with the deliveryman's text from bank 209. Each gift opens the cartridge's own event check:
  - **shiny Pichu** — `FollowerPokeIsEventTrigger EVENT_SPIKY_EARED_PICHU` at the Ilex shrine.
  - **Celebi** — `EVENT_CELEBI`.
  - **Arceus** — `PlayerHasSpecies` (Ruins of Alph), which leads to Sinjoh Ruins.
  - **Shaymin** — `GetPartySlotWithFatefulEncounter 492`, the Gracidea in Goldenrod.
  - **Enigma Stone (536)** — Latias/Latios in Pewter.
  - **Manaphy Egg.**
- **Gift Pokémon** carry `fatefulEncounter`. `g4_follower_event_trigger` follows pokeheartgold's `MonMetadataMatchesEvent` plus the per-event species check (the Pichu must be shiny).
- **HGSS start gift:** the shiny Pichu is queued from the start (`start = true`). It waits at the first Poké Mart and does not count against the post-HoF picks.
- **`GiveSpikyEarPichu`** (pokeheartgold `scrcmd_pokemon_misc.c`) gives Pichu form 1, level 30, Naughty, female, with Helping Hand / Volt Tackle / Swagger / Pain Split and a Zap Plate. Verified: the whole Ilex shrine event plays and the Spiky-eared Pichu joins.
- **Stand-ins (cutscenes not ported):**
  - `scrcmd_810` (the Celebi time-travel task) becomes a pause.
  - The Sinjoh Ruins visuals (`cinematic`, `unowncircle`, 815/817/819/820, `MystriStageGymmickInit`) become pauses or no-ops, so the event's commands still run.
- **HGSS item IDs:** Explorer Kit (428) has no data in HGSS, so data members from 406 on are the item ID minus 23 (`Gen4Items.itemId(member, hgss)`). Items from 429 up had their neighbour's record, and Enigma Stone (536) was missing.
- **BW** (`src/pokemon/Gen5MysteryGift.lua`): one gift per game clear (op 0x156, kinds 0 and 1), delivered at once to the bag, party or PC:
  - Liberty Pass (`checkitem 574`, Castelia harbor) — Victini.
  - Celebi — Castelia's Zorua scene.
  - shiny Entei / Raikou / Suicune — Lostlorn Forest's Zoroark.
- **BW op 0x220** `<species, 0, slotVar, resultVar>` is `bwpartyhaseventmon` (a fateful Pokémon of that species in the party). Verified: with a fateful Celebi the Zorua scene plays; without one it does not.

## Second screen consistency, the Pokétch gate, single-screen titles

- **`SecondScreen.separate(game)` / `separateMode(mode)`:** "the bottom screen has a panel of its own" (display, inset, vertical, horizontal). 29 screens asked this four different ways. The party menu, for one, drew its lower screen only in display/inset, so top/bottom mode showed the Pokétch fallback beneath it.
- **The field's lower screen:**
  - **Platinum:** shows the Pokétch only once it is owned (`Gen4PoketchState.owned`: `enablepoketch`, or for older saves a registered app or any badge); before that it is blank. L no longer opens the watch early.
  - **HGSS:** keeps its field panel.
  - **BW:** blank (the C-Gear is not built), where it used to show Platinum's Pokétch.
- **Single-screen titles** (HGSS, BW, White) compose both screens. The legendary's 3D scene sits behind a smaller logo near the top (0.62×), shrunk through `src/render/SmoothScale.lua` (a 4× nearest upscale, then linear sampling down).
- **BW unnamed ops:** the large clusters are side content (Battle Subway, Nimbasa's stations, Musical Theater, Royal Unova, White Forest). Those on story maps (Nacrene, Castelia, Opelucid, the League, N's Castle) are non-blocking helpers the story runs already passed through.

## Save import / export (Platinum, HGSS, Black/White) and emulator saves

- `src/save_convert/NdsSave.lua`: shared CRC16-CCITT, PK4/PK5 crypto (block
  shuffle + PRNG), Gen 4 charmap / Gen 5 UTF-16 text, engine mon <-> record,
  and emulator wrappers: raw 512 KiB (melonDS, DraStic), DeSmuME `.dsv`
  (122-byte footer), no$gba (plain and run-length), 1 MiB padded images.
- `src/save_convert/Gen4Save.lua` (Pt / HGSS) and `src/save_convert/Gen5Save.lua`
  (BW): offsets from pokeplatinum / pokeheartgold structs and PKHeX
  (SAV4Pt, SAV4HGSS, SaveBlockAccessor5BW). Trainer flags: Pt/HGSS 0x550 + id,
  BW 0x58C + id (ov10 0x0215A4EC). Imports keep `save.rawImport` and each
  mon's record (`mon.ndsRaw`), so exports patch only what the port models.
- Exports write both partitions / both BW copies with fresh footers and CRCs;
  the launcher writes `exports/*.sav` and a DeSmuME `*.dsv` beside it.
- Verified: empty encrypted box/party slots match a save Black wrote byte for
  byte; a port save written onto that cartridge image re-imports with the
  Mystery Gift / Entralink / extra regions untouched; an exported Platinum
  save boots in the harness (`IMPORT_SAV=<file>`). Unplayed saves are refused.
- Check: `python tools/run_lua_check.py tools/nds_save_check.lua <version> <cache> [realSave]`.
- Not verified on real hardware: Pt/HGSS images (no cartridge save on hand);
  blank BW exports (no template) reproduce the init values seen in a fresh
  save but not every block's.

## The Kimono Girls' dance (Ho-Oh / Lugia legendary cutscene)

- Ported from pokeheartgold `src/field/legend_cutscene_camera.c`:
  `src/import/Gen4HgssLegendArt.lua` reads `/a/1/7/4` (demo/legend.narc):
  clear bell rise/idle/shimmer, corner bells, Lugia's eye glimmer, the bird's
  ring, SoulSilver's waves (models + BCA/BTA/BTP/BMA), HeartGold's leaves
  (BG2/BG3 tilemaps 41..52 on 53/54) -> `gen4_legend_art` (hgss_screens stage).
- `src/world/HgssLegendCutscene.lua` runs the bell state machine, the camera
  set-ups and linear translation paths (camera_translation.c), the leaves /
  waves, the eye glimmer and the bird's final approach; the script ops lower to
  `g4_legend <op>` (blocking ops hold through `runner.waitingCheck`).
- Engine seams: `Gen4View.scripted` (a script's camera: distance, pitch,
  half-FOV, look-at offset, clip planes), `Gen4Camera.setCutsceneField3d`
  (real 3D view while it runs), `Gen4Ground:drawFree` draws the parts,
  `drawFieldWeather` draws the leaves; `Gen4TexAnim` now plays BMA0 alpha.
- `cinematic` rebuilds the field (the camera returns, the bell objects go),
  as it does on the cartridge. The flying-legendary movie itself
  (sub_02097BE0, undecompiled, time-of-day variants) is still a pause.
- Verified in the harness on HeartGold Bell Tower (D17R0110, var 0x40FA = 1,
  CLEAR_FLAGS=0x244): leaves, shimmering corner bells, camera pans, Ho-Oh's
  descent. SoulSilver's Whirl Islands path needs a SoulSilver cache to test.
- Also lowered: getfossilpokemon, getsealquantity, getpartymonform2,
  buffersealnameplural (msg 16), scrcmd_420 (game stat), submoneyvar,
  checknationaldexcomplete (HGSS's nine mythicals), checkseenallletterunown.

## BW message banks, stack expressions; Platinum odds and ends

- BW 0x3D / 0x3C open with a u16 BANK SELECTOR (read as two bytes before):
  0x0400 = the script's own bank; otherwise a var holding the bank. Only
  0x0400 and 0x8006 occur in Black. 0x0CC <dest> stores the running script's
  bank into a var (ov10 0x0215AADC reads ctx+0x18, set by 0x0215A760's message
  load), which is how NPCs hand the shared item-gift script (common 2800,
  member 862) their own lines -- those printed `TEXT_B` before.
- Stack expressions the jumping-code rewrite cannot spell (ORs of ANDs on the
  false branch, nested sums) are kept as postfix programs on `bwevalgoto` and
  run by `g4_bw_eval` (0 < 1 == 2 > 3 <= 4 >= 5 != 6 OR 7 AND). Black now has
  no unlowered 0x08 / 0x09 / 0x11 / 0x1F rows.
- Platinum: getpartymonconteststat, choosetwocustommessagewords (two Easy
  Chat picks), checkheapmemory (no-op probe).
- Re-link after these: STAGE_ONLY=extractScripts,extractField per BW version.

## HGSS Safari Zone

- `src/import/Gen4HgssSafari.lua` reads `/a/2/3/0` (12 areas: base slots x
  3 times of day per land / surf / 3 rods, bonus slots and their block
  unlock conditions) -> `gen4_hgss_safari` (hgss_screens stage).
- `src/world/HgssSafariZone.lua`: two area sets in `save.hgssSafari`, set 0
  seeded with default arrangement `rand % 10` (rand = TID | SID << 16, as
  overlay_36.c uses the same random for both); matrix 212's six 0xFFFF
  cells become land 652 + area (PlaceSafariZoneAreas) in the ground grid and
  the collision (MapLoader, with a rebuild when the arrangement changes);
  encounters by the area under the player (ov02_0224E31C) and time band,
  bonus slots over slot 0 upward; HGSS counts no steps, only balls (band
  `safari` entries 3 balls-out / 4 storage-out).
- Script ops: safarizoneaction, natdexflagaction, updatesafarizoneigt,
  checksafarizonechallengecompleted (Geodude / Sandshrew met in the zone),
  scrcmd_247 (dummy). Harness: HGSS_SAFARI=1.
- Not yet: Baoba's block placement (objects = 0, so bonus slots stay
  locked, like a fresh cartridge), area-level day growth, linked layouts.

## Platinum small commands (batch from pokeplatinum)

getpartymonlevel, getpartymonnature, buffernaturename (bank 202),
buffermonnicknamefrompc, checkhasseenspecies, countrepeatedspeciesinparty,
checkhasalllegendarytitansinparty, getrotomformsinsave, setrotomform (form
move swap, Thunder Shock fallback), countpartyribbons,
checkpartycombeegendercount, checkshouldshowghost, getdailyrandomlevel /
initdailyrandomlevel (VAR 0x4041, 2..99), checkispartymonoutsider,
turnonpokedexlanguagedetection, judgestats (BattleTower messages
122/123/124/127/125/126), getcurrentbgm, checkabpress, getgbacartridgeversion
(0), setfavoritemon, buffertrainername, Jubilife lottery (VAR 0x403C; the
cartridge's setter writes the HIGH half into the LOW var -- kept; synced daily
from the record-mixed RNG * 0x41C64E6D + 12345), checkalltoughwordsunlocked,
trybufferandunlockrandomtoughword. Daily upkeep in Gen4Daily.onDays.
Not yet: footprint types (Dr. Footprint table), size contest, Catching Show,
dress-up photos, rankings, link features.

## Platinum: size contest, event legendaries

- Route 222 size contest (size_contest.c): init (33280) / buffer record /
  buffer party size / result / update, record in VAR 0x4035, maths shared
  with HgssSizeRecord. Platinum constants now carry `dexHeights`
  (zukan_data.narc member 0, via extractConstants).
- StartFatefulEncounter (Shaymin) -> a legendary wild battle whose Pokemon
  carries `fatefulEncounter` (Commands.start_battle opts.fateful).
- DrawPokemonPreview / RemovePokemonPreview (Cresselia): the framed front
  sprite at tile (10, 5), species marked seen; `waitabpress` now waits for a
  press while a picture is up (it stays a no-op after messages).
- ShakeObject / FlickerObject: held for times x speed frames (no visual yet).

## Platinum: Jubilife TV passwords, Battleground, massage girl

- GetWallpaperFromCustomMessageWords (wallpaper_passwords.c): word indices
  in the password word bank (pms_aikotoba.narc member 0 -> constants
  `passwordWords`, 351 words), diffs, RotateBits x5, nibble XOR, RotateBits by
  the key, then trainer id / 0x6 tag / checksum. 0xFF wrong, 0 already
  unlocked, else wallpaper + 1; unlocked mask in `save.gen4UnlockedWallpapers`.
  Round-trip checked against a constructed password.
- CheckIsMysteryGiftPhrase: the four words laid out as bank 372 entry 1 and
  compared with entry 0 ("EVERYONE HAPPY / WI-FI CONNECTION").
- GetRandomBattlegroundTrainers: OBJ_EVENT_GFX ids, leaders 126..133, stat
  trainers 141..145, 0xFFF for none, with the cartridge's retry loop.
- TryGetRandomMassageGirlAccessory: accessories 34..49 the case can fit
  (they stack to 9), else 0xFFFF.
- Smaller queries: CountPartyMonsBelowLevelThreshold, GetPlayer3DPos
  (Distortion World: Gen4DistSurface.position), CheckBackdrop +
  AddContestBackdrop (save.gen4Backdrops), GetCapturedFlagCount
  (save.underground.capturedFlags), CheckIsTodayPlayerBirthday
  (save.player.birthday), GiveBag (FLAG 0x960; the menu is not gated on it),
  UndergroundNPCMessage (bank 636), DrawPokemonPreviewFromPartySlot,
  Wi-Fi / Chatot-recording queries answer "none", IsCommGameCodePlatinum 1.
- Dr. Footprint: constants `footprintTypes` from overlay 5's sFootprintTypes
  (signature = Bulbasaur..Metapod records; type + 8 * hasPrint; Origin
  Giratina has no print).
- Veilstone 4F decor counters (PokeMartDecor): constants `martDecor`
  (Gen4Mart.decor, ARM9 pointer pair) and `goodPrices` (sGoodData, 28-byte
  ARM9 records found by goods 1..20's footprints). Gen4ShopMenu `goods.single`
  buys one at a time with the room check first; `goods.thanks` gives the
  "We'll send the X to your PC" line. Goods go to the Underground PC.
- Not yet: Floaroma's berry-priced accessory shop (its own UI), dress-up
  photos, Catching Show, rankings, scratch-off cards, Union Room / link.

## Characters occluded by the world (Platinum, HGSS, BW)

- Cartridge (pokeplatinum): map objects are FULL billboards
  (generic_32x32.nsbmd SBC `node billboard(XY) shape`, quad x -16..16,
  y 0..32 from the feet), so one depth per sprite -- the origin's: tile
  centre + jump/sprite/terrain offsets (ov5_021ECDA0) + `z += 6`
  (ov5_021EDEB4), through the map's own depth buffer.
- Port: on the cartridge camera the live pass's depth buffer is kept after
  its blit (`Gen4Ground:noteLiveFrame`); the overworld's entity pass
  re-binds that target with depth kept (`beginSprites`), draws each
  character through the depth-sprite shader at `billboardDepth` (shadows
  tested but not written), and composites it back (`endSprites`). The
  canopy height-cut overlay is skipped on such frames. Free cameras
  (`freeEntity`) take depth at the same +6 origin.
- Checked: Twinleaf sign / table hide legs from behind and not from in
  front; a door's front cell is unclipped; HG New Bark sign; BW Striaton
  trees; third person. Platinum playthrough beats 1-5 pass.
- Not covered: neighbour-map ghosts and the "!" emote are still drawn flat.

## HGSS: field moves, small queries, Ruins of Alph puzzles

- Field-move script (scr_seq_0146: Cut, Rock Smash, Strength...): 183 ->
  the HM cut-in, 560 <kind, var> -> the obstacle animation (writes its var;
  the script spins `Wait 1` until it is nonzero, so leaving it out could
  hang Cut), 598 / 734 follower motion (no-op), 733 follower check (0),
  GetPartySlotWithMove (= FindPartySlotWithMove), GetPlayerState (0 walk,
  1 bike, 2 surf; also Platinum 0x0CA). Route 2's cut tree checked.
- BufferItemNameIndef (msg_0223), CountAliveMonsAndPC, PartyCountEgg,
  CountTranformedRotomsInParty, SetObjectFacing (= SetObjectEventDir),
  MonAddContestValue (cap 255, untouched at max Sheen).
- AlphPuzzle <n> (src/ui/HgssAlphPuzzle.lua over gen4_alph_puzzle from
  src/import/Gen4HgssAlphPuzzle.lua): /a/1/7/2 found by shape; the four
  layouts read from overlay 110 by shape (+0x15C4; the Ho-Oh board repeats
  tile 5 and the later cell wins, as InitTileData does); touch-only rules,
  rotation by tap (8 x 0x800), drag with drop marks, solved check, glow via
  a white mask of OBJ colours 0x2B..0x2F, FLAG_SYS_ALPH_PUZZLE_* (0x977+n).
  All four boards solved by a simulated-touch test.
- Not yet: OpenAlphHiddenRoom (the wall inscription screen, asm-only),
  Pal Park, Pokeathlon, Union Room / link, Frontier (scrcmd_412).

## BW: what is left unlowered

97% of Black's 89,551 script instructions lower. The rest is mostly
facility dispatchers: 0x15A <function, arg, arg, resultVar> (591 uses, zones
75/76) and 0x1F3 / 0x1F5 / 0x1F6 (Nimbasa's stadium and court, zones 81+).
Each 0x15A function id needs its own handler reversed out of ov21.

## HGSS: field moves from the overworld, Headbutt, Rock Smash items

- Pressing A now reaches HGSS's field-move script the way
  field_control.c GetInteractedMetatileScript does (Gen4TileScripts.
  hgssFieldMoveRow, band `field_move`, std_field_* = 10000 + n): Headbutt
  behaviour 0x06 -> 14, Rock Climb 0x4B/0x4C by facing -> 3, Surf (not
  surfing, Fog Badge, a Surf user) -> 4, and only while surfing Waterfall
  0x13 -> 5 / Whirlpool 0x11 -> 16. The Platinum Waterfall row stands down
  on HGSS. (The chunk-model-0xD0 Headbutt test is not ported.)
- Surf / Waterfall / RockClimb lower to Platinum's tasks (gen4Climb now runs
  on HGSS maps: same behaviour numbers); Whirlpool carries across its 0x11
  run; StrengthFlagAction = Platinum's; CheckEscortMode 0 (never true in
  HGSS); Capitalize; follower-only 728 / 731 no-op, 829 answers 0.
- Headbutt (field/headbutt.c): /a/2/5/2 per map header (60 maps), tree
  cells, tree type by index and trainer id's last digit (sRareTreeLUT_*),
  slots 50/15/15/10/5/5, level in range, Repel honoured. Route 1 tree ->
  wild Hoothoot Lv2.
- Rock Smash (field/rock_smash_item.c): the map's rock smash encounter
  (rate, slots 80/20) first, else /a/2/5/3 odds (17 maps; +5 Suction Cups /
  Magnet Pull / Keen Eye / follower), 25/20/10x5/5 draw, Serene Grace /
  Super Luck +1, HG / SS tables. Checked statistically (2,000 smashes).
- Data: src/import/Gen4HgssFieldMoves.lua -> gen4_hgss_field_moves
  (hgss_screens stage).

## Pass 33: HGSS std scripts, Day Care, tutors, certificates, weather

**Audit gap.** The map-based audit (scratch `audit.lua`) only walks scripts that a map references. The std scripts reached through `CallStd` were never scanned, and that is where most of what was left lives. `audit_all.lua` (`ONLYM=Mxxxx` for one file) scans them.

**Day Care (`std_daycare`, scr_seq_0265).** HGSS's names now map onto Platinum's Day Care handlers; the buffer slots and return values are the same (get_egg.c).
- New handler: `GetTailDaycareMonSpeciesAndNick` (`g4_daycare_tail`).
- `DaycareSanitizeMon` is `TryRevertPokemonForm`.
- 551 / 552 are the party menu and its result.
- Verified on Route 34 (R34R0101): with three Pokémon, the lady takes the first.
- The ROM refuses a deposit that would leave fewer than two Pokémon across the party and PC.

**Battle Frontier move tutors (`std_frontier_move_tutor_*`, scr_seq_0002).**
- 652 gives the page count.
- `MoveTutorChooseMove` builds the menu: seven moves to a page when they fit, otherwise six plus NEXT (0xFFFD), then QUIT (0xFFFE). The labels are msg_0748 #0/#2/#3.
- `TutorMoveGetPrice`, `TutorMoveTeachInSlot`, and 556 (spend BP) are lowered.
- Data: the existing HGSS rows in `gen4_move_tutor`.
- Verified in D32R0103: Pikachu is offered ThunderPunch 64 BP / Knock Off 40 BP.

**Certificates (`ShowCertificate`).**
- New import `src/import/Gen4HgssCertificates.lua` (/a/1/2/6, ov78_021E5EA4 member table) writes `gen4_hgss_certificates`, in the `hgss_screens` stage.
- The ink comes from NARC_graphic_font (/a/0/1/6) member 7.
- The screen is `src/ui/HgssCertificate.lua`: msg_0004 text at the ROM's positions.
- In two-screen modes the sheet slides from the top screen to the bottom one. The Shiny Leaf sheet's 3D Pokémon is not drawn.
- Harness: `SCREEN=HgssCertificate CERT=0|1|2`.

**Pokéathlon numbers.**
- Give/Take/CheckAthletePoints use `save.hgssAthletePoints`, the value the points box already shows.
- 724 / 725 read and adjust `save.hgssPokeathlonRecords`.
- 712 (the record viewers) is a no-op.

**Goldenrod Underground (D37R0102/0103).**
- Accessory lottery: 830–833 (overlay_02_02251E74.c, 39 accessories / 14 backdrops) and 553 (percent roll).
- Fashion Case commands 403–407.
- 622: an object's facing.
- The dress-up portrait studio (154 / 155 / 255, overlay 41) is not ported: no portrait is ever saved.

**Professor Oak's rating (scr_seq_0148).**
- `GetDexEvalResult` uses the ROM's bands from unk_0205BB1C.s:
  - Johto: ≤9 … ≤253 → msg_0666 #28–45.
  - National: ≤100 … ≤483 → #46–56.
- A completed dex gives #22/23 or #24/25 by gender, with SEQ_ME_HYOUKA6; otherwise the fanfare is HYOUKA1.
- The Johto/National seen/owned counts and `CheckJohtoDexComplete` (≥ 254 owned, excluding Mew and Celebi) are lowered.

**Flash and small std commands.**
- `FlashAction` uses the flash flag; `FlashEffect` sets weather 12.
- `SurvivePoisoning`, `GetMonTypes`, `PartyLegalCheck` (always FALSE), and `BufferTrainerClassNameIndef` are lowered.

**HGSS weather ids.** `Gen4Weather.nameFor` now reads HGSS headers through `HGSS_NAMES` (pokeheartgold weather.h):
- 1 is RAIN. Route 33 and T29 were reading as CLOUDY.
- 11 is the dark caves' Flash darkness: D03 / D05 / D40 / D42, nine maps. These were reading as HAILING and snowing.
- 13 is low light.
- The darkness mask itself is still not drawn, on Platinum as well as HGSS.

**Left in HGSS's std scripts.**
- `scrcmd_465` (std_group, 458 uses).
- Pokéathlon courses.
- Phone calls: owned by the Pokégear work.
- Photo album and seals.
- Save-screen stats.
- `martsell` and the egg-hatch / whiteout std scripts. The engine does these natively, so those scripts never run.

**BW.** 97.0% of instructions are lowered. The largest remaining ops are 0x15A (356), 0x1F3–0x1F7 (Nimbasa stadium) and 0x169/16A/16B.

## Pass 34: HGSS Groups, text names, dark caves

**Groups (`std_group`, scr_seq_0143; `ScrCmd_465`, 458 uses).** These are HGSS's record-mixing groups, made and joined at the Pokémon Center NPC on T22R0301 (13, 8). Lowered to `g4_hgss_group`. `save.hgssGroups` has six slots (friend_group.h):
- 0 is the group the player made.
- 1 is the group they are in.
- 2–5 are groups met over record mixing. These are never filled, since there's no wireless.

The modes:
- 0: the slot is filled.
- 1: the slot is the joined group.
- 2 / 3: the group's name / leader's name to a buffer.
- 4: the naming screen (msg_0249 #5). Returns 0 for a name, 1 for blank, 2 for a name already in use.
- 5: join a group.
- 6: lead and join slot 0.
- 7: four or more other groups exist.

Verified: talk, MAKE GROUP, name it; the line reads "The AAAAAAA group, huh?".

**Text names.** HGSS fills `STRVAR_3`, `STRVAR_4` and `STRVAR_34` the same way as `STRVAR_1` (`MsgArray_ControlCodeIsStrVar`). These were printed as braces. That affected 208 lines, the Groups among them. Fixed in `Commands.gen4Markup`.

**Small HGSS commands.**
- 494 is `BufferECWord`, an Easy Chat word to a buffer.
- 706 / 642 ask whether a Hall of Fame record exists.
- 164 opens the PC Hall of Fame browser. It is still `pending`, as on Platinum.
- 289 sets the Union Room avatar (`save.player.avatar`).

**Dark caves (both games).** The darkness is drawn now (`src/render/Gen4FlashDark.lua`). It is Platinum's DARK_FLASH weather task (ov5_021DB04C): an H-blank window centred at (128, 84).
- On the map's load, the radius closes from 256 to 32 over 30 frames.
- When the weather ends on the same map (Flash: Platinum clears it, HGSS's FlashEffect switches to 12), it opens back to 256.
- Leaving a dark map does not play the opening.
- It is drawn a span per row, black outside, as the cartridge does. It replaces the uniform Hoenn veil these maps wore.
- Frame-timed from the overworld's weather clock.

Checked in Whirl Islands (D40R0101, HGSS) and Wayward Cave (D21R0101, Platinum).

**Left in HGSS.** The Union Room (wireless), the PC Hall of Fame browser (both games), Pokéathlon courses, Pal Park migration (509/510; needs a GBA save), phone calls, the photo album and seals.
