# Emerald: story screen effects

These effects follow pret's pokeemerald. The checks run against the imported
Emerald cache.

## The Mirage Tower comes down (`src/world/Gen3MirageTower.lua`)

Specials 411, 413, 483, 484 and 485, from `mirage_tower.c`. None of the
scripts waits on them; they run alongside the message that follows.

- **4F, after taking a fossil:** 16 ceiling crumbs fall while the camera
  shakes (`StartScreenShake(2, 1, 16, 3)`).
- **Route 111:**
  - The tower is drawn on BG0 in the map's own BG palette 6.
  - The 18 tiles under it become sand you can walk on.
  - BG0 rocks 2 px side to side, flipping every third frame.
  - It then dissolves from the bottom row up: one pixel per frame per row,
    a new row every second frame, sinking a pixel every second finished row.
- **The fossil you didn't take** falls from the top of the screen to y 96,
  then dissolves 2 pixels per frame.
- **Two oddities, kept on purpose:**
  - Each erase clears the other half of the byte it lands on.
  - The fossil and the crumbs use the player's palette (the crumbs come out
    green).
- **The art comes from your ROM:** `mirage_tower.c`'s graphics at
  `0x617274`–`0x617D44`, checked pixel for pixel against pokeemerald. They are
  read by `RomExtractorGen3:extractMirageTower` into
  `constants.gen3MirageTower`. For an existing cache, run
  `tools/gen3_mirage_tower_extract.lua`.
- **Where it draws:** everything is placed in world pixels. The cartridge's
  camera holds the player at screen (112, 72), so the tower's screen
  rectangle is exactly its 18 cells.
- **Checks:** `tools/emerald_mirage_tower_check.lua` (28) and
  `tools/gen3_mirage_tower_harness`.

## Camera shakes, the Orbs, and `waitstate` (`src/world/Gen3ScreenFx.lua`)

- **ShakeCamera (312)** now follows `Task_ShakeCamera`:
  - VAR_0x8004/8005 are the pan amounts and 0x8006/8007 the number of
    shakes and the frames between them.
  - The whole view moves, map and sprites alike.
- **DoOrbEffect / FadeOutOrbEffect (284/285):**
  - A red or blue circle (by VAR_RESULT, centred on x 104, 136 or 120)
    grows 2 px every second frame to radius 160.
  - Inside it, red or blue is blended over the scene at BLDALPHA(12, 7).
  - The camera then rocks 4 px every 4 frames until the fade-out, which
    steps the blend out every 8 frames.
- **`waitstate`** used to only restore fades. It now waits, as the cartridge
  does, for the first running effect to call `ScriptContext_Enable`. It
  checks the live effects rather than a counter, so a dropped effect can
  never leave a script parked.
- **Check:** `tools/emerald_screen_fx_check.lua` (25).

## Smaller specials

- **133 SwapRegisteredBike:** a registered bike moves with Rydel's swap.
- **80 GetContestPlayerId, 82/83 BufferContestWinnerTrainerName/MonName:**
  the contest results lines.

## The census (`tools/emerald_specials_census.lua`)

This ranks the specials Emerald's scripts call that nothing handles: 88 left
over 150 call sites, mostly the Battle Frontier, secret-base battles, TV,
link play and records windows. Every script opcode Emerald uses is lowered.

## In-game trades, Emerald and FireRed (`src/ui/Gen3TradeAnim.lua`)

Special 257 (DoInGameTradeScene) used to swap the two Pokemon with nothing on
screen. It now plays the cartridge's trade sequence, drawn from the player's
own ROM, for Emerald's four trades and FireRed's nine (FireRed reaches the
same specials through `specialRemap`).

- **Which sequence:** `CB2_InitInGameTrade` (pokeemerald `src/trade.c`,
  pokefirered `src/trade_scene.c`) zero-allocates the trade state and never
  sets `isCableTrade`, so every in-game trade runs `DoTradeAnim_Wireless`:
  the wireless-adapter GBA, the signal rings and the white crossing column,
  not the cable sequence. The two games' state machines are the same code;
  FireRed differs only in its text box art, its font metrics and where the
  received Pokemon's cry is played.
- **What is ported, state by state:** every case of `DoTradeAnim_Wireless`
  with its own frame counts, positions and scroll values (the 180 px slide,
  the 80-frame wait, `gbaScale` -0x34/+0x34 with `sXY = 0x8000 / gbaScale`
  through `BgAffineSet`, `bg1vofs` 348 -> 316 -> 166 and back, the glow's
  -2/+4 travel, the crossing at +-3 px, ...). Under it sits a small model of
  the hardware the trade drives:
  - palette RAM with palette.c's `BeginNormalPaletteFade` /
    `UpdateNormalPaletteFade` (BG and OBJ halves on alternate frames,
    deltaY `2 + |delay|`, the five finishing frames) and util.c's 5-bit
    `BlendPalette`;
  - sprite.c's frame and affine animation commands (`ANIMCMD_LOOP`'s jump
    back, absolute vs relative affine frames, `affineAnimEnded`) and the
    callbacks the trade installs: the bouncing ball (108-step velocity
    table, the four bounce sounds), `CreateTradePokeballSprite` /
    `CreatePokeballSpriteToReleaseMon` (`BATTLER_AFFINE_RETURN` and
    `_EMERGE`, the `y2 = -data[1] >> 8` rise, the sine fly-out), the sixteen
    open particles, the link-mon glow and the shadow's colour-4 cycle;
  - BG0-BG2 composited per pixel in a shader with BG priority, WIN0 (the
    crossing column) and `BLDALPHA(16, 4)` blending (the glow and GBA over the
    signal rings);
  - the four tasks: `Task_AnimateWirelessSignal` (the signal's palette walk),
    `Task_Open/CloseCenterWhiteColumn`, and `LaunchBallFadeMonTask`.
- **The swap is TradeMons:** it happens at `STATE_TRY_EVOLUTION`, after the
  last A press, and the received Pokemon takes the traded one's party SLOT
  (`SWAP(*playerMon, *partnerMon)`), not the end of the party. Friendship is
  set to 70, the dex is told, the trade evolution runs before the field
  returns, and `BufferInGameTradeMonName` leaves the received nickname and the
  offered species name for the thank-you line. The field fades out (18
  frames) before the scene and back in before the script continues
  (`FieldCB_ContinueScriptHandleMusic`).
- **The art comes from your ROM:** `src/import/Gen3TradeArt.lua`
  (`RomExtractorGen3:extractTradeScene`) reads 31 blobs at addresses taken
  from pret's `.sym` files for BPEE rev 0 and BPRE rev 0, keyed by game code
  and revision, and verifies each one's shape before writing anything (LZ77
  header and decompressed size, BGR555 words, tilemap tile/bank bounds, the
  bounce table's range, the signal table's 0xFF sentinel, gSineTable at
  0/64/128/192, the four sentences' placeholders, `gSpeciesInfo` being the
  manifest's `gBaseStats`). Pictures are colour-INDEX PNGs under
  `assets/generated/trade/`; palettes and tables go in the data module
  `gen3_trade_art`. A cartridge the table does not name, or a blob that does
  not verify, skips the stage and special 257 keeps the bare swap.
  `tools/gen3_trade_art_check.py` compares all 27 asset blobs byte for byte
  with the decomp's own `.bin`, `.pal` and `.png` sources (0 mismatches on
  both ROMs). The Emerald and FireRed import markers were bumped so old
  caches re-import once; `MODE=extract` in the harness adds the art to an
  existing cache without one.
- **Kept as the cartridge has it:** the in-game trade uses the wireless art
  even with no adapter; the opened battle ball's third frame is blank
  (`CreateTradePokeballSprite` loads `gBallSpriteSheets` directly, without
  `LoadBallGfx`'s shared open frame); the GBA jumps from ~2x (the last affine
  frame) to the 1x text-mode picture when the zoom-out ends; the Pokemon's
  palette alternates between the ball colour and the white fade while both
  `Task_FadeMon_ToNormal_Step` and the palette fade write it.
- **Approximated:** the Pokemon pictures are the cache's colour front sprites,
  so their palette blends are the same 5-bit formula applied per pixel in a
  shader; Emerald's received-Pokemon front animation uses
  `src/pokemon/MonAnim.lua`; the evolution scene inside the trade is the
  port's `Gen3EvolutionState`, after which the trade scene (not the evolution
  screen) fades out; `MUS_EVOLUTION` restarts after the `MUS_EVOLVED` fanfare
  rather than resuming; sounds play by the decomp's song numbers.
- **Checks:** `tools/gen3_trade_harness` (`MODE=extract|scene|script`;
  pictures go to `G:/Gen2Recomped/scratch_claude/gen3trade`), and the in-game
  trade block of `tests/gen3_specials_test.lua`.
