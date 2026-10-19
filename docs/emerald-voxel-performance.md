# Emerald voxel performance investigation

The Emerald terrain renderer built a large GPU mesh per map and submitted the complete mesh in each applicable pass. It does not automatically build the entire world. Neighbour preparation, abandoned urgent jobs and oversized mesh uploads nevertheless increased transition stalls. Explicit PREBAKE is a separate, user-started operation.

## Changes

- Split Gen 3 terrain into 128-pixel spatial regions and bounded 32,766-vertex GPU buffers. Clip individual buffers against the camera and shadow frusta. Conservative curved-world bounds retain visible bent terrain. Unknown transforms draw conservatively.
- Send common shader uniforms once per batch. Preserve the ordinary Mesh path, water rendering and reflection/shadow compatibility. Release partial uploads on failure.
- Demote abandoned urgent jobs and prioritize the destination once shared asset analysis finishes. Pause automatic neighbour geometry work beneath battles and interactive overlays; allow the required current map to finish. Only a fully opaque Transition receives the covered-screen build budget.
- Use a 4 ms cold-build bootstrap, then adaptive slices. Add cooperative checkpoints to building/structure analysis and cache pruning. Shared Gen 3 atlas/context analysis remains atomic to protect shared state.
- Repair persistent cache identities: border tables previously contributed their process-specific memory address. Hash their contents instead, with actual Gen 3 block dimensions, canonical atlas metadata, elevations and collisions. Existing broken keys rebuild once; newly written caches survive subsequent launches.
- Complete auxiliary map analysis before publishing cached terrain. Explicit refresh bypasses stale cached geometry. Keep the existing raw cache format and release partially loaded batches on cancellation/failure.

## Validation

Desktop native LOVE terrain probes use an existing private Emerald import. They render terrain only, excluding actors and the water composition/postprocessing passes. Screenshot hashes are identical before and after for the sampled views; these are not complete gameplay or battle-animation captures.

| Sampled view | Before submitted vertices | After submitted vertices | Desktop terrain draw median |
| --- | ---: | ---: | --- |
| Route 119, flat | 14,029,260 | 2,824,308 | about 4.1 ms to 3.2 ms |
| Route 119, curved (0.0004) | 14,029,260 | 5,555,856 | 4.25 ms to 4.32 ms |
| Oldale, cold spatial build | 575,622 | about 251,000 | about 1.9 ms to 1.8 ms |

Flat Route 119 submits approximately 80% fewer vertices. Curved culling reduces submission by 60.4%, but additional draw-call CPU overhead offsets the GPU saving on this desktop. Total geometry remains unchanged; this does not establish reduced total VRAM or whole-game FPS.

Checks completed:

- 23 ROM-free batching, bounds, culling, cache-signature and scheduling policy checks.
- Lua syntax checks for 12 runtime modules; existing performance-tier suite 36/36.
- Native FFI and non-FFI terrain builds and byte-data cache reloads, shadow rendering and exact screenshot comparisons.
- Cross-launch cache reuse, including a check that terrain is published only after analysis finishes. Final Oldale cache-read screenshot SHA-256: `e17f897ecf4a371aa6038c6f1db9953926c118b5ab346e11c6b1da64d525650d`.
- Destination job preemption with an unfinished Route 119 build, plus background pause under interactive overlays.
- Budgeted cache pruning and forced-refresh geometry replacement despite unchanged cache identity.
- Existing Emerald Center/Mart geometry and grass-footprint checks (two buildings).

The probe lives in `tools/emerald_voxel_perf_check`. Run ROM-free checks through `tools/run_lua_check.py` with `unit.lua` and `check_syntax.lua`. Native probes require ROOT, EMERALD_CACHE and POKEPORT_DATA_DIR environment variables and LOVE; use an isolated IDENTITY, never a player save profile. PERF_DISK=1 enables cache checks; PERF_LEGACY=1 asserts an existing newly written cache is reused; PERF_NO_FFI=1 exercises fallback uploads. PERF_PREEMPT, PERF_REFRESH and PERF_PRUNE enable the respective regressions. Native outputs and screenshots are under ignored `tmp/emerald_perf`.

## Installation and limits

Updated runtime sources in the workspace and both primary installations:

- `G:/Gen2Recomped/mods/DRAMATIC_SHAPE`
- `C:/Users/cedri/AppData/Roaming/LOVE/Gen2Recomp/mods/DRAMATIC_SHAPE`

Hash guards verified every target before writing. Preserved the customized G: main.lua, which already contains the scheduler changes. Restored the installed Gen3.lua files to the unchanged workspace implementation. Numbered mod copies and user settings were left untouched. Backups and the verified 85-file test ZIP are in `tmp/emerald_perf`; no public release/version bump or app binary build was performed. Restart the application to load updated Lua modules.

Switch hardware has not been tested. Cold builds still show occasional roughly 0.3–0.55 second stalls from atomic analysis, GC and other engine work; cumulative cold build time varies and is not consistently faster. Persistent cache reuse and reduced offscreen submission address repeated work, but do not eliminate every freeze. Battle terrain uses the shared optimized renderer; end-to-end battle move effects and sustained mobile/Switch frame rates still require device testing. Manually requested PREBAKE remains a separate workload.
