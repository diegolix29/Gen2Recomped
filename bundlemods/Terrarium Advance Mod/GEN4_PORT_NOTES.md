# Terrarium on Gen 4 (Platinum): what is done, what is not

## What the engine already gives us (verified in the engine source)

Gen2Recomped's `main` has a full Gen 4 pipeline (`platinum` in
`src/core/GameVersion.lua`, generation 4, marked experimental). Its overworld is
a real 3D world, not a tilemap:

- `src/render/Gen4Ground.lua` draws terrain chunks and buildings from the
  cartridge's models, with a colour + depth target.
- `src/render/Gen4View.lua` is the camera: `matrix(vw, vh)` (world->clip),
  `project()`, `forward()`, orbit / zoom, first and third person, and
  `field3d` (the cartridge camera at a chosen tilt).
- `src/render/Gen4Camera.lua` holds the cartridge's 17 camera types and the
  CAM TILT ladder.
- World space: +x east, +y up, +z south, 1 unit = 1 map pixel, 16 per tile.
  That is the same convention the voxel scene uses.
- Height query: `Gen4Ground:groundY(px, py)`. Matrix origin: `offsetX/offsetY`.

Two facts drove the design:

1. `manifest.json` `generations` gates loading (`ModGens`). It was `[1,2,3]`, so
   the mod did not load on Platinum at all. Now `[1,2,3,4]`.
2. A `drawWorld` render pipeline REPLACES the engine's world pass. Left alone,
   the `voxel` pipeline would swap Platinum's real 3D world for a voxelised
   tilemap. On Gen 4 it now reports `available = false`.

## What is implemented

- `lib/Gen4Bridge.lua`: the scene provider. Wraps `Gen4Ground:endFree()`. In a
  free camera the engine leaves its canvas open (terrain + buildings +
  characters, live depth buffer) until `endFree`, so drawing just before it is
  depth-tested against the real scene. It feeds `Gen4View:matrix()` into
  `Voxel3D`'s existing external-target + explicit-camera modes, so the whole
  shader (wind, water, tint, glass mask, lamps, fog) works unchanged.
  `Bridge.register(name, fn(scene))` adds an effect. Errors are isolated per
  effect. Engine files are not modified.
- `lib/Gen4Grass.lua`: swaying 3D grass on `Map:isEncounterCell` cells, standing
  on the engine's terrain height, driven by your existing `Wind`.
- `main.lua`: installs the bridge on a Gen 4 cartridge only; `voxel.available`
  stands down on Gen 4.

## Tested vs untested

Tested (stubbed harness, `texlua`): hook fires before the engine closes the
canvas; the matrix reaching `Voxel3D` equals `Gen4View:matrix()` exactly; no-op
on Gen 1/2; a throwing effect is disabled and the scene still closes; syntax of
all edited files.

NOT tested: anything in a running LOVE + Platinum. I have no LOVE runtime or
ROM here. First things to check in-game:
- grass appears on the right cells (Gen 4 may need a different predicate than
  `isEncounterCell`; see `collect()` in `Gen4Grass.lua`);
- depth matches (grass hidden behind buildings, feet not sunk in slopes);
- the log line `Gen4Bridge:` on any failure.

## Not done yet

1. **Cartridge (oblique) rung.** Effects draw only in free cameras (first /
   third person and CAM TILT rungs). The default `cartridge` rung bakes chunks
   with its own depth units (`Gen4Ground:beginWorld` / `screenMatrix`); needs a
   second provider. Workaround: set CAM TILT to a numeric rung.
2. **3D battles with Colosseum models.** Not started. Plan: an arena/battler
   effect registered on the bridge, placed with `scene.groundY`, with the battle
   camera driven through `Gen4View` (orbit/zoom API already exists). Needs a
   read of `src/battle/Gen4Battle.lua` and how the Gen 4 battle state hands
   over the frame.
3. **Glass masks.** The voxel glass mask is keyed to voxel faces. Gen 4
   buildings need per-window data (NSBMD materials), so this is its own task.
4. **Water and puddles** (`GroundFX`, `water_*`): need a water-surface source
   from Gen 4's terrain/behaviours, then the same bridge registration.
5. Grass performance: one draw per tuft (capped at 240). Chunk-baking needs the
   shader's sway to read a per-vertex base height.
6. Shadows/day-night: Gen 4 bakes light into vertex colours (`Gen4Shade`); the
   effect meshes use the mod's tint, so match them via `Voxel3D.tint`.
