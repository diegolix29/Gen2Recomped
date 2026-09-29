# Gen 4 battle harness

A headless Sinnoh battle, rendered to a PNG, so battle-side work can be looked
at instead of reasoned about.

The terrain harness could stand in Twinleaf and diff frames, which is what made
the camera, the back walls, the grass and the sky checkable. The battle screen
had no equivalent, so the ball throw, the party icons, the HP bar, the move menu
and the stray textbox could only be argued about. That gap, not any one of those
items, was the real blocker.

## Running it

    POKEPORT_DATA_DIR=<platinum cache>/data/generated \
      SPECIES=396 LEVEL=3 PARTY=387 PARTYLEVEL=12 TICKS=30 TAG=starly \
      love tools/gen4_battle_harness

The PNG lands in LOVE's save directory for the identity `bt_gen4`.

| variable | default | meaning |
|---|---|---|
| `POKEPORT_DATA_DIR` | -- | the cache to load (required) |
| `SPECIES` / `LEVEL` | 396 / 3 | the wild Pokemon |
| `PARTY` / `PARTYLEVEL` | 387 / 12 | the player's one Pokemon |
| `TICKS` | 30 | frames to advance before drawing |
| `TAG` | `battle` | output name |
| `W` / `H` | 512 / 384 | canvas size |
| `VERSION` | `platinum` | game version to set |

## What it needs present

Only what one wild battle touches, which is far less than a full install:

- the cache's `.lua` modules,
- `assets/generated/gen4/battle/` -- the three healthbox sheets, the digits,
  `background/plain_day.png`, both `terrain/plain_*_day.png`, and the
  `front/`, `back/` and `anim/` sprites for the two species involved;
- `assets/generated/gen4/font/font_message_sheet.png` -- without it the names
  and numbers on the healthboxes do not draw.

Anything absent draws as a placeholder and says so, so a missing asset is
visible rather than silent.

## Lifecycle

Two steps this harness has to take that are easy to forget, because skipping
either produces a convincing-looking fault in the engine that is not there:

- **`Font.load(Data)`** hands the glyph atlas to the renderer. Without it every
  string reports `no glyph for "A"` and the message area draws as a plain white
  rectangle. A white block in the message area means the font was not loaded --
  not that the text box is broken.
- **`BattleState:enter()`** is where a battle loads its pictures --
  `playerBackPic`, `showPlayerBack` and the rest. Without it they all read as
  missing.

Each cost one wrong diagnosis before it was noticed. If you extend this, keep
the lifecycle honest: a harness that skips a step reports the step, not the
engine.

## What it deliberately does not do

No window, no overworld, no save file on disk, no launcher. It builds the two
things `BattleState.newWild` actually requires -- a loaded dataset and a save
with one healthy Pokemon -- and draws one frame.

The save comes from `SaveData.newGame`, not from a table written here. The first
version hand-built one and raised on `save.inventory`; a hand-made save is how a
harness ends up exercising a shape the game never produces.
