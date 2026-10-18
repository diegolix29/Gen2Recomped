# ROM Extraction Notes

There are two ROM-only extraction paths:

- The packaged app uses `src/import/RomImporter.lua` and
  `src/import/RomExtractor.lua` on first boot.
- Developers can run `tools/build_data.py --rom <path> [--clean]` to generate
  data in the source tree for audit and parity work.

Both paths read only the supplied ROM and the checked-in
`tools/rom_manifest.json`. Neither invokes RGBDS, Git, or a disassembly.

## Validation

Only the canonical US Pokemon Red ROM is supported. SHA-1 is checked before
any cached output is removed or written.

## Decoded Data

| Area | ROM data |
| --- | --- |
| world | map headers, block maps, connections, warps, signs, objects |
| tiles | tileset graphics, blocksets, collision, door and warp tile lists |
| text | 2,584 text command streams and RAM/number substitutions |
| Pokemon | names, stats, evolutions, learnsets, Dex data, compressed pictures |
| battle | moves, detailed animations, OAM frames/tiles, effects, type chart, palettes, trainer parties/AI/pictures |
| inventory | item names, prices, key-item flags, TM/HM data |
| encounters | grass and water wild tables |
| UI | fonts, icons, title/intro, trainer card, town map, slots, field effects |
| audio | music, SFX and cry headers, channel programs, wave instruments |

The Python and Lua picture decompressors implement the Gen 1 `pic` format.
Graphics are converted to RGBA PNGs. OAM artwork uses transparent color 0;
battle pictures use edge-connected white matting so white interior details
remain visible.

The in-app importer stores three audio ROM banks as a 48 KiB
`programs.bin`. `src/core/ChipAudio.lua` interprets the channel bytecode and
synthesizes music as a queueable stream; SFX and cries are synthesized on
demand. This avoids shipping or generating a large WAV/OGG tree.

## Metadata Boundary

Names, dimensions, enum ordering, Lua script hooks, and hand-ported field
behavior do not survive compilation in a form the Lua runtime can infer.
Those relationships are bundled in `rom_manifest.json`. The manifest stores
no dialogue strings, images, audio samples, or ROM bytes.

`tools/make_rom_manifest.py` and `tools/verify_rom_data.py` are developer audit
tools. They are not used by the packaged game.

## Trade Cinematics (Gen 1 and Gen 2)

In-game and link trades play the cartridge's own movie, with art taken from
the player's ROM by the importer.

**Gen 1** (`engine/movie/trade.asm`, `src/ui/TradeAnim.lua`).
`src/import/Gen1TradeArt.lua` runs at the end of the field stage and writes
`field.tradeArt` (format 2): `TradingAnimationGraphics` (49 BG tiles, vChars2
$31-$61, size checked against `TradingAnimationGraphicsEnd`) as
`trade/gen1_tiles.png`, `TradingAnimationGraphics2` (the cable ball, 4 OBJ
tiles) and `TradeBubbleIconGFX` (the bubble quadrant, both frames), plus the
Game Boy (6x8) and link cable (12x3) tilemaps read through rows 6/7 of
`TileIDListPointerTable`. The six symbols were added to the Red, Blue and
Yellow manifests (and to `FIELD_ASSET_SYMBOLS` in `make_rom_manifest.py`);
Red and Blue share addresses, Yellow's come from `pokeyellow.sym`. The art is
stored as DMG shades and coloured by the SGB zone pass: the mon's palette
while its pic is up (`SET_PAL_POKEMON_WHOLE_SCREEN`), `PAL_MEWMON` otherwise
(`SET_PAL_GENERIC`). The screen runs Internal/ExternalClockTradeFuncSequence
frame for frame over a modelled $9800/$9C00, SCX ring, WX/WY, OAM and
rBGP/rOBP0/rOBP1; the ball drop/shake/tilt/poof are the `TRADE_BALL_*`
battle animations (AnimPlayer) plus their trade-only special effects.
`tools/extract/gfx.py extract_trade` (the pokered dev path) emits the same
format.

**Gen 2** (`engine/movie/trade_animation.asm`, `src/ui/Gen2TradeAnim.lua`).
Gold, Silver and Crystal have their own movie (link tube, stats window,
both trainers' names, the menu icon in a bubble). `src/import/Gen2TradeArt.lua`
writes `field.gen2TradeAnim`: the decompressed `TradeGameBoyLZ` tiles, both
tilemaps, the arrows, `TradeBallGFX`/`TradePoofGFX`/`TradeCableGFX` laid out
as vTiles0 $62-$77 (the cable request is four tiles long, so $76/$77 get the
first two bubble tiles, as on hardware), `TradeBubbleGFX`, a raw-shade copy of
each menu icon, the six trade framesets and their OAM sets
(`SpriteAnimFrameData` / `SpriteAnimOAMData`), the `Sprites_Sine` table, the
tube palette (`PalPacket_TradeTube` -> `PredefPals`), `PartyMenuOBPals[0]`,
`MapObjectPals[0]` per time of day, and the text tokens of the four
`w*Trademon*Name` buffers. The screen runs TradeAnimation (or
TradeAnimationPlayer2 for the externally clocked link side) one jumptable step
per frame with the sprite-anim functions ported, OBJ priority, and the CGB
palettes through DmgToCgb*'s shade permutations; it draws in true colour and
opts out of the zone pass. Gold/Silver differences (no Wait96/Wait40, no
animated frontpic, slower bulge/scroll-out, longer waits, no OT gender mark)
come from `variant`. Prism and Polished Crystal rename or merge these blobs,
so they import no `gen2TradeAnim` and keep the Gen 1 movie.

`g2_trade` pushes `Gen2TradeAnim`; `LinkState` picks the generation's movie
and passes `externalClock` to the guest. The ROM-cache markers were bumped
(`gen1-trade-art-v1`, `gen2-field-encounters-v8`) so existing caches pick up
the art. Checks: `tests/engine/trade_anim_tests.lua`,
`tests/engine/gen2_trade_anim_tests.lua`, and
`"C:/Program Files/LOVE/lovec.exe" tools/gen12_trade_harness` (extracts the
art from each ROM, plays a real NPC trade through `Commands.trade` /
`g2_trade`, writes frame sheets; `TRADE_EXTERNAL=1` for the link guest's
sequence).
