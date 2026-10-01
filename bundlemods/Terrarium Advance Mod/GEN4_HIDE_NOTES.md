# Hiding Platinum's native grass and water (Gen4Hide)

Files: `lib/Gen4Hide.lua` (new), `lib/Gen4Water.lua` (changed), `main.lua` (2 lines).

## How it works
Terrain is one `Gen4Model` per land chunk and `Gen4Model:draw` loops over `model.shapes`,
one material per shape. `Gen4Hide` wraps `Gen4Model.draw` and `Gen4Ground:drawFree`; only
while `drawFree` runs (the free cameras, where Gen4Bridge draws) it hands `draw` a filtered
shape list, and puts the real list back right after. The CARTRIDGE rung, baked chunks,
canopies and building passes are untouched.

- **Grass:** hides the standing cards (`<shape>Cards`, index nil) the engine stamps over
  encounter grass. The flat `nectgr` quad stays as ground, so no hole under your tufts.
- **Water (round 2):** a built Gen4Model shape keeps its material name but NOT its texture or
  alpha, so `Gen4Ground:modelFor` is wrapped to copy the cache's texture name and alpha onto
  each terrain shape. A shape is hidden when its material OR texture name says water
  (`sea`, `water01/02`, `water:lambert5`, anything with water/lake/river/wtr/pond...), or when
  it is translucent terrain (alpha < 31) that is not a shadow/glass/cloud. Waterfalls and
  fountains are never hidden. Tune `Hide.WATER_NAMES / WATER_PATTERNS / WATER_SUBSTRINGS /
  KEEP_SUBSTRINGS`, or set `Hide.ALPHA_HEURISTIC = false`.
- Round 1 only matched three exact names, and the cartridge also names materials like
  `water:lambert5`, so most water kept drawing.

## It stands down instead of leaving a hole
- grass: no Grass3D bake, or the grass effect disabled
- water: water effect disabled/failed, or `Gen4Water.ready` is false (the sheet around the
  camera isn't fully built yet, ring `GW.NEAR` = 3 chunks)

## Gen4Water changes
Readiness is latched per map (no native-water flicker when walking into new chunks).
`RADIUS` 3 -> 8 (1024 units; the engine draws a 5x5 grid of 512-unit chunks, so 3 left a far
hole once native water is gone), `BUILDS_PER_FRAME` 2 -> 4, new `GW.NEAR` and `GW.ready`.

## Switches
`Hide.grass = false` / `Hide.water = false` (e.g. from a console or debug row) to compare.
`Hide.LOG_NAMES` (now ON) logs every distinct shape once, as `Gen4Hide: hid water by ...` or
`Gen4Hide: kept: material ... texture ... alpha ...`. Grep the mod log for `Gen4Hide:`.
It also logs why water is or is not being hidden (`sheet not built yet`, `no ready flag`...).

## Tested / not tested
Tested with stubs (texlua): filtering, exact restore, error path, every stand-down case,
cache refilter, uninstall, `GW.ready` going false -> true -> false. Syntax of all 3 files.
NOT tested in LOVE + Platinum. Look for:
1. Water I did not name. Props (`l_lake`, `r04_w` are build models) go through the same
   `Gen4Model.draw`, so a prop material named `water*`/`sea` is hidden too, but lakes whose
   material has another name stay native. Turn on `LOG_NAMES` and add what you find.
2. Slivers at shorelines: native water follows the artist's polygons, the sheet follows
   cells (2x2 per cell).
3. Water height: if `groundY` over water is the lakebed, the sheet sits low (raise `GW.LIFT`).
4. Frame cost of RADIUS 8 on first entry to a big lake (4 chunk builds/frame).
