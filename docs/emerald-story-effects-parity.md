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
