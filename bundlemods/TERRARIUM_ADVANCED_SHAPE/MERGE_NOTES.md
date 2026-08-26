# Merge notes: ADVANCED_SHAPE + TERRARIUM

This mod's code is TERRARIUM's codebase (a superset fork of the older
"Dramatic Shape" voxel mod), rebranded under ADVANCED_SHAPE's manifest
identity (`id: DRAMATIC_SHAPE`, priority 100) as requested, with three
specific behaviours restored from ADVANCED_SHAPE.

## What changed for the merge

### 1. Horizon art (`lib/HorizonArt.lua`, new file)

TERRARIUM's `lib/Skyline.lua` builds a real, flat-coloured height-field
silhouette out of the connection graph's own map data -- genuinely useful,
and left in place. ADVANCED_SHAPE's horizon is a different thing: a
painted 360-degree cylinder (`lib/backdrop.png`) centred on the player.

`lib/HorizonArt.lua` is ADVANCED_SHAPE's `lib/Backdrop.lua`, ported and
simplified to not depend on the separate "ds_fp_ceiling" companion mod it
originally shipped for -- it just loads its own bundled `backdrop.png`.
It draws BEHIND Skyline's silhouettes (sky -> horizon art -> Skyline ->
terrain), so the placed towns and routes Skyline draws still read as real
shapes standing in front of a painted sky, rather than replacing them.

Wired in at `lib/VoxelScene.lua`, just before the existing `Skyline.frame()
/ Skyline.draw(...)` call.

`backdrop2.png` / `backdrop3.png` / `backdrop4.png` were also copied over
from ADVANCED_SHAPE (alternate panoramas) but are not wired up to anything
-- only `backdrop.png` is loaded by `HorizonArt.draw`. Swap the path in
`HorizonArt.lua`'s `texture()` function to use one of the others.

### 2. Sprites turn with camera yaw (`lib/VoxelScene.lua`)

TERRARIUM's fork of `frameFor()` and `billboardMatrix()` had dropped the
camera-yaw handling entirely -- sprites always showed their south-facing
frame and never rotated to face the camera as it orbited. Ported back from
ADVANCED_SHAPE:

- `frameFor(def, facing, phase, flip, yaw)` remaps facing (up/down/left/
  right) based on the camera's yaw before picking a sprite frame.
- `billboardMatrix(px, py, y, mirror, yaw)` rotates the card around Y by
  `yaw` before applying the lean, when not in the first-person blend.

`yaw` is threaded through every caller: `VoxelScene.render` computes it
from `cam:angle()` (or `Voxel3D.camera.yaw` if a placed camera exists,
e.g. a free-fly mod), then passes it to `castShadows`, `drawShadow`,
`drawEntity`, `drawGhost`, and `Voxel3D.beginScene`.

### 3. Camera turns on yaw (`lib/Voxel3D.lua`)

TERRARIUM's `Voxel3D.viewProjection`'s orbit-camera branch (no placed
camera) always sat the eye due south of the focus point, ignoring the
flat camera's own rotation completely. Ported ADVANCED_SHAPE's version:
the eye position and up-vector both rotate around the focus by `yaw`, so
turning the flat/2D camera now turns the voxel orbit camera too.
`viewProjection` and `beginScene` both gained an optional trailing `yaw`
parameter (defaults to 0, so existing callers -- e.g. `BattleScene.lua`,
which doesn't pass one -- are unaffected).

### 4. Shared pipeline flag (`main.lua`)

TERRARIUM registered its pipeline under `"terrarium_voxel"` /
`"terrarium_tiltshift"` rather than the plain `"voxel"` / `"tiltshift"`
ids ADVANCED_SHAPE (and several of its own files -- `Horde.lua`, `VR.lua`,
`SettingsMenu.lua`) use, specifically so both mods could be installed
side by side without fighting over the same pipeline slot. That's no
longer the situation: this is one merged mod, so `main.lua`'s
`PIPE_VOXEL` / `PIPE_TILT` constants were changed to `"voxel"` /
`"tiltshift"`. Nothing else needed to change -- every other TERRARIUM
file already went through these two local constants rather than
hardcoding the string, confirmed by grepping for the old literal names
across `lib/`.

One pre-existing quirk this fixes as a side effect: TERRARIUM's SELECT-
button gamepad handler already hardcoded the literal `"voxel"` (not
`PIPE_VOXEL`) when checking `Pipelines.canToggle` / `Pipelines.level` --
apparently written to interoperate with a separately-installed
ADVANCED_SHAPE's pipeline. Now that this mod's own pipeline IS `"voxel"`,
SELECT and the `v` hotkey both correctly drive the same flag.

## Verified, not just asserted

Both the syntax (`luac5.4 -p` on every `.lua` file) and the settings
registration were checked against a stub Lua harness that stubs
`love.*` and every `src.*` engine module the mod requires, then executes
`main.lua`'s real top-level code. Confirmed against the untouched
TERRARIUM source: identical settings schema count (35) and identical
hook-wrap count (11) before and after this merge -- the merge itself
was not silently dropping any of TERRARIUM's settings. If you're
comparing against ADVANCED_SHAPE's own settings, most of that gap is the
VR/Horde/Stadium/Shiny systems described below, which this merge does
not include, rather than anything TERRARIUM already had going missing.



ADVANCED_SHAPE-exclusive systems -- VR (`VR.lua`, `VRGL.lua`, `VRRig.lua`,
`VRXR.lua`, `Diorama.lua`), Horde battles, Stadium battles, the Shiny
hunting system, and `PlayerModel` swapping -- are not present in this
merge. They depend on deeply reworked versions of `Structures.lua`,
`Buildings.lua`, `OverworldBattle.lua`, and `BattleScene.lua` that diverge
from TERRARIUM's own rewrites of those same files by 700-2900 lines each.
Reconciling that safely needs a way to actually run the mod against the
game; a text-only merge risks shipping something that compiles but breaks
at runtime. If any of those systems matter to you, they're best added
one at a time so each can be checked in-game before moving to the next.
