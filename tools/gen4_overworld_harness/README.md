# gen4_overworld_harness

A headless Sinnoh **overworld**, rendered to a PNG and traced per tick.

The terrain harness draws the ground; the battle harness draws a battle.
Neither stands up an `OverworldState`, so nothing about the live cast -- who is
on the map, who is drawn, who follows the player -- could be looked at. Items 9
and 10 of the play-test list are both exactly that.

    POKEPORT_DATA_DIR=<platinum cache>/data/generated \
      MAP=T01 WALK=down TICKS=90 TAG=barry \
      love tools/gen4_overworld_harness

The PNG lands in LOVE's save directory for the identity `ow_gen4`.

## Environment

| var | meaning |
|---|---|
| `MAP`, `X`, `Y`, `FACING` | where to stand (default `T01` 15,25 down) |
| `WALK` | a direction to hold for the whole run |
| `TICKS` | frames to step before the screenshot |
| `TRACE` | print player/follower state every tick |
| `FOLLOW` | make someone the partner -- **a sprite name**, or a localId |
| `CLEAR_FLAG` / `SET_FLAG_AFTER` | run a flag through the engine's own `Commands` |
| `THEN_MAP`, `THEN_AT`, `THEN_X`, `THEN_Y` | cross a seam mid-run |
| `W`, `H`, `TAG`, `VERSION` | output size, filename, cartridge |

## Two things it does on purpose

**It boots the services `Game:boot` boots, in that order.** The battle harness
was assembled the other way -- adding each service as a nil was hit -- and
reported three engine faults that were all missing lifecycle (`enter`,
`Font.load`, `Game.input`). Anything added here should be added because
`Game:boot` does it.

**It draws through `Game:draw`, not `OverworldState:draw`.** Calling the state's
own `draw` into a canvas gives a BLACK FRAME, not even the player: `Game:_draw`
is what sizes the UI surface, picks the visible base and runs the world pass.

## `FOLLOW` names a sprite

The first version took a localId and the first run adopted T01's `map_signpost`
-- localId 4, no character art -- so "the follower did not draw" was true and
meant nothing. Two objects can also share a localId on a Gen 4 map (T01's
guitarist and its arrow signpost are both 3), so a number is not an identifier
here. The live cast is printed either way.

## What it needs that the repo does not carry

The Platinum **assets** (`assets/generated/gen4/overworld/*.png`, and
`terrain/chunks.bin` if you want ground under the cast). Without the sprites
every actor draws as a placeholder and the frame is empty -- which looks exactly
like a rendering fault and is not one.
