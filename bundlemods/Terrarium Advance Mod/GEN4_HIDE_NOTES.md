# Gen 4: hide native grass/water, and the 3D grass / water that replace them

Files: `lib/Gen4Hide.lua`, `lib/Gen4Water.lua`, `lib/Gen4Grass.lua`, `lib/Gen4Reflect.lua`,
`lib/Gen4Bridge.lua`. `main.lua` is NOT shipped: it needs only these two lines inside the
`if Gen4Bridge.isGen4() and Gen4Bridge.install() then` block, after the grass register:
    pcall(function() V.require("Gen4Hide").install() end)
    pcall(function() V.require("Gen4Reflect").install() end)

## Round 4: lake water, shore growth, hide-only-where-covered
- Lakes you cannot reach are PROPS (build models), not terrain. The sheet only read terrain
  shapes, so lake water was hidden and never replaced. Each land's sheet is now terrain water
  PLUS the water shapes of every prop on that land, placed like Gen4Ground places a building
  (scale, then translate, chunk units).
- Gen4Hide tags prop shapes the same way it tags terrain (wraps `Gen4Ground.building`).
- Native water is now hidden ONLY where the sheet has built triangles from that exact cache
  shape (`GW.isCovered(shape.src)`). A water shape the sheet cannot use stays native.
- The sheet grows `EXPAND_FRAC` (0.10 of a cell = 1.6 units) past every shore edge (a skirt of
  the same height on each boundary edge) and rides `LIFT_FRAC` (now 0.10 = 1.6 units, i.e. the
  earlier 5% plus 5% more) above the water. Both are knobs on `GW`.
- `GW.LOG` (on) writes one line per land with water:
  `Gen4Water: land N: a terrain + b prop water triangles (c not horizontal, skipped), d shore edges grown`.

## Gen4Hide (unchanged this round)
Wraps `Gen4Model.draw` during `Gen4Ground:drawFree` and skips the native grass cards and the
shapes `Hide.classify` calls water. `LOG_NAMES` is off again.

## Gen4Water: built from the cartridge's own water polygons
- The sheet is now made from the SAME terrain shapes Gen4Hide hides (via `Hide.classify`), read
  out of the cache with `ground:slice`, kept where the triangle faces up, and re-tessellated
  (`EDGE` 10 units, `MAX_SPLIT` 52) so the swell has vertices. Whatever is hidden is covered,
  at the height the artists put it. The old version used tile behaviours + `groundY`, which
  missed water over other behaviours and sat at the wrong height.
- One mesh per LAND chunk (shared across the map), drawn at every place the engine draws that
  chunk: `translate(cx*chunkPx + half, LIFT, cy*chunkPx + half)`.
- Draws the full engine window (`WINDOW` 2 = Gen4Ground FREE_RADIUS), so water reaches as far
  as the ground does.
- `LIFT = LIFT_FRAC (0.05) * 16 = 0.8` units above the native surface. Change `GW.LIFT_FRAC`.
- Publishes `GW.ready` (window fully built; latched) and `GW.level` (Y of the sheet nearest the
  camera) for Gen4Hide and Gen4Reflect.

## Gen4Grass: the same window as the ground
Grass chunks are wanted on every engine chunk within `WINDOW` (2) of the camera's, nearest
first, built under a 4 ms/frame budget (`BUILD_BUDGET`, at most `BUILDS_PER_FRAME` 24). The old
3-chunk circle around the player is only a fallback now. All built chunks are drawn.

## Gen4Reflect: the voxel scene's water reflection
The reflection is RayFX (the RTX row, RT/MAX), a screen pass that finds water by HEIGHT. Gen 4's
water is not at the voxel scene's height, so it never found any. Gen4Reflect:
1. wraps `Gen4Model.newTarget` to give Gen 4 a READABLE depth buffer;
2. after Gen4Bridge's effects (new `Bridge.after` hook) and before the engine blits, runs
   `RayFX.apply` over the Gen 4 colour + depth with `WATER_Y/WATER_BASE` moved to `GW.level`,
   and copies the result back into the colour canvas.
Limits: only at RT/MAX; AO comes with it (same pass); one water height per frame (the nearest
sheet); nothing happens if the driver refuses a readable depth canvas (logged once, "Gen4Reflect:").

## Switches
`Hide.grass/water`, `Reflect.enabled`, `GW.LIFT_FRAC`, `GW.EDGE`, `Grass.WINDOW`, `GW.WINDOW`.

## Tested / not tested
Stub tests: sheet geometry (area preserved, placement, height, vertical/shadow shapes skipped,
cache, latch, no-grid fallback), grass window edges and per-frame bound, reflection band
set/restore, copy-back, every early exit, error path, uninstall. NOT run in LOVE + Platinum:
check the reflection in particular (canvas/depth handling is the part only the real driver
proves), the shoreline where sheet meets bank, and frame time on big seas (25 chunks of sea
is about 200k triangles).
