# Nintendo Switch (love-nx) notes

`love.system.getOS()` reports `"NX"` (`src/core/Platform.lua`). love-nx is
statically linked: there is no `dlopen`, so every FFI route to PhysFS
(`PHYSFS_mount`, `PHYSFS_unmount`, ...) fails or quietly does nothing.

## How a version's cache is reached

`CacheFs.mountVersion` tries three mounts and checks that each one worked.
On love-nx none of them makes `<version>/data/generated` visible under its
plain path. The last resort is the **prefix shim**
(`CacheFs.installPrefixShim`). It wraps the loaders so that a missing
`data/generated/...` or `assets/generated/...` path is looked up again as
`<version>/...`:

- `require("data.generated.*")` (through a package searcher)
- `love.filesystem.read` and `love.filesystem.getInfo`
- `love.graphics.newImage`, `love.graphics.newFont` and `love.image.newImageData`
- `love.audio.newSource` and `love.sound.newSoundData`
- `love.filesystem.newFile`, `love.filesystem.lines` and `love.filesystem.newFileData(path)` (added for the ground fix below)

Any new loader that opens a generated file by path has to go through one of
these wrapped functions, or it will work on desktop and fail only on Switch.

## DS games had no ground (fixed)

**What players saw.** Platinum, HeartGold/SoulSilver and Black/White drew
their buildings, the player and the NPCs over a flat clear colour, with no
terrain, both indoors and outdoors.

**Cause.** `Gen4Ground` reads the packed terrain files with
`love.filesystem.newFile` plus `seek`/`read`, so it does not load the whole
17 MB file. The files are:

- `assets/generated/gen4/terrain/chunks.bin` (the chunk geometry)
- `heights.bin` (the BDHC heights)
- `permissions.bin` (collision)

The shim did not wrap `newFile`. Everything else still loaded through
wrapped paths: buildings come from `require`d Lua modules and textures from
`newImage`. Only the terrain file came back as "Does not exist". The log
shows `gen4 ground: ... chunks.bin would not open`, followed by
`drew LIVE -- 0 chunk(s)`.

These were ruled out:

- **Depth buffer.** depth24 works on Switch; the hardware log reports it.
  `Gen4Model.newTarget` already falls back to depth24stencil8, depth32f and
  depth16.
- **Shaders.** `Gen4Model` already has a fallback shader without the height
  cut.
- **Vertex formats.** All vertex attributes are already float.
- **Vertex decoding.** It is pure Lua (`string.byte`) and uses no FFI.

**Fixes.**

1. `CacheFs.installPrefixShim` now also wraps `newFile`, `lines` and the
   one-argument form of `newFileData`.
2. `src/render/Gen4RangeFile.lua` opens the three terrain files. It tries
   `newFile` first. If no handle opens, it reads the whole file once through
   `love.filesystem.read`, which goes through the shim, and serves `seek` and
   `read` from that string.

## Simulating the Switch on desktop

Set `POKEPORT_SIMULATE_SWITCH=1` (`Platform.simulatesSwitch()`). This:

- turns off CacheFs's FFI `PHYSFS_mount`;
- makes `mountVersion` go straight to the prefix shim.

`Platform.isNX()` is left unchanged, so the UI and input still behave as on
desktop.

The HGSS overworld harness also accepts the flag. With it, the harness:

- mounts the parent of `INSTALL` (the cache root) instead of `INSTALL`;
- installs the shim;
- drops its own `io.open` shortcuts (`POKEPORT_DATA_DIR`,
  `POKEPORT_ASSET_ROOT`).

Add `SIM_OLD_SHIM=1` to restore the unwrapped `newFile`. This tests the
`Gen4RangeFile` fallback.

```
mkdir -p G:/Gen2Recomped/scratch_claude/switchground/x
POKEPORT_SIMULATE_SWITCH=1 INSTALL=G:/Gen2Recomped/heartgold VERSION=heartgold MAP=T20 X=20 Y=14 \
  TICKS=40 SHOTS=30 OUT_DIR=G:/Gen2Recomped/scratch_claude/switchground/x \
  "/c/Program Files/LOVE/lovec.exe" tools/gen4_hgss_overworld_harness
python tools/run_lua_check.py tools/switch_terrain_paths_check.lua
```

With the fix, the simulated runs match the normal desktop runs pixel for
pixel for:

- HGSS T20 and T20R0101
- BW Z006 and Z391

Platinum T01 and T01R0101 differ by 64 and 184 pixels, all in the player's
shadow. That comes from the harness's own `io.open` image loader, which the
simulation turns off; it is not a ground difference.

## Still to confirm on hardware

- The ground appears in Platinum, HGSS and BW, indoors and outdoors.
- The log no longer prints `would not open` for `terrain/*.bin`.
- If it prints `read whole ... newFile refused it`, love-nx's `File` handle
  does not work and the fallback is in use.
- Collision and heights are correct. Both came from the same unreadable
  files, so walking through walls or a flat player height on Switch had the
  same cause.
- The reported vertical smearing of the back-wall trees and strips in an
  interior was not reproduced in simulation. With the terrain missing,
  nothing in the simulated interiors smeared. Check whether it disappears
  once the room geometry loads. If it does not, suspect texture or UV
  precision on the Switch GPU.
