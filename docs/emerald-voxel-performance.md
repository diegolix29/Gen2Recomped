# Emerald voxel performance investigation

The Emerald terrain renderer built a large GPU mesh per map and submitted the complete mesh in each applicable pass. It does not automatically build the entire world. Neighbour preparation, abandoned urgent jobs and oversized mesh uploads nevertheless increased transition stalls. Explicit PREBAKE is a separate, user-started operation.

## Changes

- Split Gen 3 terrain into 128-pixel spatial regions and bounded 32,766-vertex GPU buffers. Clip individual buffers against the camera and shadow frusta. Conservative curved-world bounds retain visible bent terrain. Unknown transforms draw conservatively.
- Send common shader uniforms once per batch. Preserve the ordinary Mesh path, water rendering and reflection/shadow compatibility. Release partial uploads on failure.
- Demote abandoned urgent jobs and prioritize the destination once shared asset analysis finishes. Pause automatic neighbour geometry work beneath battles and interactive overlays; allow the required current map to finish. Only a fully opaque Transition receives the covered-screen build budget.
- Use a 4 ms cold-build bootstrap, then adaptive slices. Add cooperative checkpoints to building/structure analysis and cache pruning. Static Gen 3 atlas preparation now uses a private animation-state copy and cooperative pixel sampling before map analysis; map analysis jobs remain serialized to protect shared state.
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

- 28 ROM-free batching, bounds, culling, cache-signature and scheduling policy checks.
- Lua syntax checks for 13 runtime modules; existing performance-tier suite 36/36.
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

Hash guards verified every target before writing. Preserved the customized G: main.lua, which already contains the scheduler changes. The follow-up now updates Gen3.lua with sliced preparation and explicit context eviction. Numbered mod copies and user settings were left untouched. Backups and the verified 85-file test ZIP are in `tmp/emerald_perf`; no public release/version bump or app binary build was performed. Restart the application to load updated Lua modules.

## October 19 follow-up: foundations, transitions and launcher games

Civic buildings now record their whole footprint and settle its ground to the same doorstep datum as the model. This takes precedence over the foliage-clump floor heuristic, which could lower the ground independently. Both `stampGround` and the actual emitted ground quads use this settled height. Native assertions passed for all 28 audited Centers and Marts across 17 outdoor maps, including footprint height agreement. Front/side screenshots were captured and inspected. Geometry cache revision r4 forces older sunk foundations to rebuild once.

Further transition/memory changes:

- Slice static atlas analysis, carving and map-floor sampling before map geometry. Use private Gen3Tiles animation state so 2D frame updates cannot change a suspended static bake. Add checkpoints to per-map scans and tree/building emission; clock sampling now runs every fourth active tick.
- Replace route-sized Lua vertex tables on non-FFI platforms with packed binary blocks. Support persistent cache writes and reads there, including water streams. Auxiliary grass/flower/figure uploads also use bounded mesh batches.
- Track temporary GPU batches and byte buffers by job. Cancelled builds release unpublished allocations immediately; published cache meshes transfer ownership and survive unrelated cancellation. Drop raw FFI buffers incrementally after upload.
- Evict map-specific civic templates and Gen3 contexts alongside their meshes. Correct an ImageData release guard that previously accepted tables only and skipped actual LOVE userdata.
- Limit unseen history to an estimated 128 MiB on NX / 256 MiB elsewhere, counting both GPU and CPU vertex streams. Visible live maps remain protected: this is a history budget, not a cap on the whole renderer. Cancel unfinished work for maps no longer in the live neighbourhood, including suspended atlas cleanup.

The warmed engine-bridge Oldale probe recorded a build-slice 95th percentile around 7.4–8.3 ms, versus about 44 ms in the preceding cold probe. Views remain pixel-identical. These are sampled desktop build times, not device frame-rate guarantees or an end-to-end transition benchmark. The final ownership-cancellation probe recorded an 11.7 ms 95th percentile. Exact timings vary with GC, CPU/GPU contention and whether atlas data was already warm.

Native regression runs additionally verified immediate cancellation cleanup, eight repeated eviction/reentry cycles, the history-budget eviction branch, cross-launch no-FFI cache reuse, shadow rendering, destination preemption from an unfinished Route 119 build, and pausing automatic background work under battle/menu overlays. Terrain screenshot SHA-256 remains `e17f897ecf4a371aa6038c6f1db9953926c118b5ab346e11c6b1da64d525650d` for Oldale.

Launcher minigames now read the full roster from the chosen imported ROM's pokemon data and use that ROM's art. The walking Pokemon pins the source; without one, the hub provides a Change ROM control for available imports. Seeded per-run shuffling varies memory boards; tiny hack rosters repeat legal art rather than inserting foreign species. Radar/course rules are unchanged. The native Emerald check loaded 411 species entries and verified all 16 memory-card images came from Emerald, while rejecting Genesect art from other imports. Hub and memory-board screenshots were captured and inspected. The expanded headless minigame suite passes 124 checks; the performance-tier suite passes 36.

Runtime updates are installed in the workspace and the two primary mod folders listed above. Custom entry points, numbered mod copies, settings and saves are preserved. Follow-up backups are in `tmp/emerald_perf/transition-backups`; the refreshed test mod ZIP is `tmp/emerald_perf/DramaticShapes-Emerald-performance-test.zip`. Launcher changes are application source changes and need an application rebuild to distribute; the mod ZIP alone cannot update a packaged launcher. No public release or platform executable rebuild was performed.

Switch hardware has not been tested. Occasional cold-work spikes still occur: roughly 90–125 ms in sampled Oldale runs and 254 ms in the Route 119 preemption fixture. Reentry stress runs also include GC and analysis work. This patch therefore does **not** establish completely hang-free transitions or prove the reported long-session Switch freeze is eliminated. Memory cleanup and bounded unseen history address identified retention paths, but on-device sustained play and memory traces are still required. Total visible-neighbourhood memory, engine import/tileset initialization and manually requested PREBAKE are separate costs.

## Walker-delivery round: additional Route 119 slicing

Gen3 preparation now reuses its private static tile copy within one preparation job rather than cloning and decoding it again for analysis, atlas, shape and floor sampling. Cancellation still releases that context. Hollow-fill and civic-stamp settlement scans now yield between rows/cells; these were previously uninterrupted work ahead of the next checkpoint.

The sampled Route 119 worst build slice fell from 199.5 ms to 71.2 ms; the 95th percentile was 8.15 ms. Vertex counts and the screenshot SHA-256 stayed identical (`7250e71aa294b2c6c90af0e106fcfb963b88f1bf44404e89f94df32a621e616c`). Total cold build time increased from 14.74 s to 16.12 s with more cooperative slicing, so this is a reduction in individual stalls, not a faster total cold bake. Terrain draw median was about 3.52 ms on this desktop. Switch remains untested, and occasional cold-work spikes remain.

The two updated modules, Gen3.lua and Structures.lua, are synchronized to both primary mod installations with byte guards and backups in `tmp/emerald_perf/walker-round-backups`. The test ZIP is refreshed from the workspace runtime files. Application launcher/walker changes are separate from this mod package and require rebuilding the application.

## Further transition work: custom G: install and neighbour scheduling

The complete runtime was copied into `G:/Gen2Recomped/mods/DRAMATIC_SHAPE`, including its entry point and previously missing Rewrap/NativeStage modules. Twenty-six files initially differed. Backups are under `tmp/emerald_perf/custom-full-sync-backup`. This replaces the older installed entry point with the workspace version; settings, unrelated files and numbered mod copies are preserved.

Additional changes:

- Static tile-analysis copies cache decoded cartridge metatile entries for the lifetime of one preparation job, avoiding repeated table allocation. Empty metatiles also get cooperative checkpoints.
- Map-floor sampling composites only the actual floor metatiles. The above-player colour histogram is reused from the tileset analysis. The existing shape/carve/counting algorithm remains unchanged.
- At paced frame rates, the build allowance uses measured world rendering work plus a 3 ms host reserve, rather than treating VSync wait as CPU work. Over-budget frames and hosts without measurements keep the conservative elapsed-time estimate. Background builds retain the 5 ms ceiling; this does not make native calls preemptible.
- Neighbour requests carry distance from the player to their map rectangle. Once shared analysis is safe to leave and foreground work is complete, the closest pending neighbour wins instead of whichever map happened to enter the queue first. Battles/menus still pause background work.

Native tests exercised the actual VoxelScene.prefetch entry point, verified it queues current and adjacent maps before crossing, completed neighbouring terrain while still on Oldale, and confirmed seam promotion reuses the same mesh without a new job. The test uses an isolated profile and simulated 60 Hz pacing; its hidden-window elapsed time is not a walking/gameplay frame-rate guarantee. Oldale's captured terrain remains pixel-identical (`e17f897ecf4a371aa6038c6f1db9953926c118b5ab346e11c6b1da64d525650d`).

In the sampled Route 119 cold body build, total build time was 14.70 s before these changes and 13.75 s afterward; worst sampled pump time was 93.8 ms versus 61.8 ms. Vertex count and screenshot hash are identical. These single desktop samples are subject to JIT/GC/driver variation. The 15-second cold-build complaint is not fully solved: large forests still require substantial analysis and geometry expansion. A separate eight-cycle eviction/cache/cancellation stress run still recorded a roughly 102 ms worst slice. Do not describe transitions as hang-free, or infer Switch performance from these measurements.

Verification: 31 ROM-free checks, 14 runtime syntax checks, native live-neighbour scheduling/promotion, cancellation cleanup, eight eviction/reentry cycles, persistent cache roundtrip, shadow rendering and inspected screenshots. Final changed modules are copied to the custom G: installation with byte verification. Switch hardware remains untested.

## October 20: atomic refresh and repeated-hull streaming

Seam corrections previously called Structures.invalidate immediately while the previous terrain mesh stayed visible. A render-time query could then rebuild the shape analysis synchronously outside the job budget. AnalysisCache now provides a coroutine-private replacement: render queries retain the complete published analysis until its replacement mesh commits. Cancellation retains the published version. Native refresh tests verified both sides of this swap while forcing a derived geometry change.

The scheduler now follows FrameCap.current instead of always assuming 60 Hz. Visible budgets scale with the target interval; a paced 30 Hz background receives a 10 ms ceiling rather than being classified as an overloaded 60 Hz frame and held to 1.5 ms. Busy frames still use available headroom. A native policy regression verifies this alongside the live-neighbour queue/promotion tests.

Shared tree/prop hulls flatten into double-precision StampStream records once per geometry job. FFI and packed sinks copy these records with translation and the original contact shading rather than repeatedly walking nested corner/UV tables. Boundary-crossing hulls retain the clipping path. Geometry and texture semantics are unchanged; batches can have different conservative bounds. Route 119 retained 14,029,260 vertices and the exact reference screenshot hash, with a sampled build of 11.77 s (previous round: 13.75 s). Worst sampled slice was still 60.6 ms, so cold loading and all hitches are not eliminated.

Validation passed: 36 pure checks, 16 mod syntax checks, native atomic refresh with a forced geometry replacement, actual neighbour prefetch and warm promotion, paced 30 Hz policy, non-FFI tree streaming with disk-cache roundtrip, and pixel-identical Oldale/Route 119 images. The isolated native runner also completed 15 simulated minutes of update/draw testing. Switch hardware was not available.

The complete 87-file runtime is verified in `G:/Gen2Recomped/mods/DRAMATIC_SHAPE`; changed files are backed up under `tmp/emerald_perf/oct20-final-backups`. The refreshed test ZIP contains the same runtime. Application touch/runner fixes remain app source changes and need an application rebuild to distribute.

## Shared GPU hulls and bounded backtracking history

Emerald's repeated round-tree/prop hulls now share immutable GPU templates, with separate variants where their ground-contact shading differs by height. Instance offsets are grouped into 128px spatial regions. Terrain, lighting, grid, reflection and shadow shader state is preserved when selecting instanced shader variants. Drivers without advertised instancing support retain the expanded path; Gen 1/2 retain their existing geometry path.

Route 119's 1,364 eligible hull copies previously expanded into the terrain stream. The new path stores 2,135,838 base vertices plus 872,892 shared-template vertices: 3,008,730 total versus 14,029,260 previously, about 78.6% less vertex storage (excluding instance offsets and non-vertex analysis data). This is not a measurement of total process RAM or total VRAM. The full draw still renders all required copies; probe submitted-vertex counts now include instance multiplicity. Sampled camera submission was 63 calls / 2,903,190 effective vertices, versus the preceding expanded path's 93 calls / 2,763,558 vertices. Submission can rise slightly with conservative grouping while draw-call count drops.

Uncontended sampled cold builds were approximately 9.0-9.6 seconds versus the previous 11.77-second sample. Draw medians remained around 3 ms; these single desktop samples do not establish end-to-end device FPS. A later graphics-parity run took 17.15 seconds wall time despite fewer build pumps, illustrating scheduling/JIT/driver variation. Cold analysis is still substantial (about five seconds in the sampled large route), and worst sampled build slices still reached roughly 50-70 ms; the combined repeated-entry stress fixture reached about 126 ms. Do not claim Gen 2-equivalent smoothness or completely hitch-free loading yet.

Ownership is reference-counted across map batches. Cancelling a job or evicting one map releases its instance buffers and references; a template survives while another map owns it, and the last owner releases its GPU mesh. Cache files store the base stream and reconstruct shared hull references from the current analysis on load. A distinct signature prevents loading an older expanded cache and drawing trees twice. Prebaking omits shared copies without allocating GPU hull meshes, then reconstructs them when loaded.

The history-byte limit now applies to unseen cached maps independently of protected visible terrain. Previously a large visible route could consume the entire history allowance, causing unnecessary rebuilding when backtracking. Live maps remain protected; unseen history remains bounded by 128 MiB on NX / 256 MiB elsewhere. Shared templates are conservatively counted per owner for this policy.

Verification passed: 13 shared-ownership/uniform tests, 36 existing batching/analysis/policy tests, 18 runtime syntax checks, native cancellation, eight eviction/reentry cycles, atomic refresh, persistent-cache reload, non-FFI buffers, no-GPU-mesh prebaking, nearest-neighbour prefetch and warm promotion, 30 Hz pacing, and the independent-history regression. Flat Route 119 and Oldale screenshots retain their prior SHA-256 hashes. Curved Route 119 remains `c7221c09e2e3598f8d91cc8d15b226c2a63df2689c66426f135bb80d69419f91`.

An additional native reference comparison rendered the shared and expanded geometry with the same translated model, lighting, voxel-grid, reflection and shadow passes. All pixel comparisons passed. It exposed and fixed reflection culling: bounds now use the mirrored model while uniforms retain the original model. Actual Route 119 shadow pixels match the expanded reference (`0e6307460be5d83b165580b38fd3f6e27c076329875f22a7bf04a1bdc753c847`). Captured terrain images were inspected. Switch hardware remains untested.

The complete 89-file runtime is synchronized to the custom `G:/Gen2Recomped/mods/DRAMATIC_SHAPE` installation with guarded backups under `tmp/emerald_perf/shared-gpu-install-backups`; settings and numbered copies are preserved. The local test ZIP contains the same runtime. Restart the app to load the changed modules.

If a driver advertises instancing but rejects an attribute bind, the renderer restores its shader and falls back to translated shared-template draws. The focused test verifies this fallback without losing ownership or GPU cleanup.


### First-entry stalls after neighbouring meshes are ready (October 20)

The supplied play log repeats shape passes around map crossings and also logs
new engine metatile-sheet bakes. Destination mesh readiness alone does not
cover `OverworldState:rebuildNeighbors`: it loads a new ring of maps and their
flat renderer atlases synchronously. A real Emerald outdoor pair took
0.31–0.35 seconds to bake on this PC; multiple newly visible pairs can compound
that cost. These logs have no timestamps, so they do not isolate every reported
1–2 second pause.

`EngineSheets.lua` now prepares the connections beyond rendered neighbours,
nearest first, in nominal 1 ms slices. It uses the engine's actual bake/cache,
including animation and reflection covers, rather than substitute artwork.
Directed connections and multiple connections on an edge are supported. Actual
consumers finish a still-pending bake before reading the engine's temporary
failure sentinel. Reimport, teardown and mod reload finish pending work before
clearing caches or removing hooks. Live sheets are touched before prewarming;
no new pair is started when the live pairs fill the engine cache allowance.
This is a mod-only patch; it requires no application executable rebuild.

Animation patches previously remained lazy until `TerrainAtlas.forMap` first
drew the new map. The mesher now prepares those patches and their texture before
publishing terrain. Preparation uses a private animation state, yields during
patch composition, and releases scratch ImageData explicitly. Cancellation
removes unfinished cache sentinels so a later build can retry.

Validation:
- `tools/emerald_sheet_prefetch_check`: real ROM bottom/top/reflection pixels
  exactly match the synchronous bake; warm sheet lookup 0.0024 ms. Early entry
  and mod reload during a suspended bake pass. 219 background slices in the
  last run, largest 38 ms (allocation/upload sections remain indivisible).
- `tools/emerald_voxel_perf_check`, `PERF_ANIMATION=1`: first-draw atlas lookup
  0.016 ms; the live engine animation state remains unchanged across suspended
  preparation and cancellation. Neighbour promotion still adds no rebuild job.
- Route 119 build: 9.06 seconds of accelerated hidden test wall time, screenshot
  hash `7250e71aa294b2c6c90af0e106fcfb963b88f1bf44404e89f94df32a621e616c`,
  identical to the prior terrain output; screenshot inspected. This fixture
  does not pace background slices at real gameplay frame rates.
- 36 scheduler/stream checks, 13 shared-hull checks, 20 module syntax checks.

The project runtime and `G:/Gen2Recomped/mods/DRAMATIC_SHAPE` were synchronized
and all 90 runtime files compared byte-for-byte. Numbered alternative installs
were left alone. Backups are under `tmp/emerald_perf/seam-prefetch-backups`.
Cold shape/geometry builds still take seconds of CPU time; no claim of fully
hitch-free gameplay, fixed Switch freezes, or Gen 2 performance parity is made.


### Route 114 / Meteor Falls revisit and boundary fixes (October 20, follow-up)

New play logs confirm the project mod takes precedence over the custom G: copy.
The exact reproduction uses Route 114 (`MAP_G00_N30`), Meteor Falls
(`MAP_G24_N00`), and crossings toward Fallarbor / Route 115.

Further causes found and changed:
- History considered only the immediately previous live set, then kept the
  cheapest neighbours first. It now retains bounded LRU history across several
  interior changes, prioritising maps the player actually visited. New entries
  record their root/live recency when created, not only on the next set change.
- Cancelling a refresh before its analysis finished discarded the valid old
  terrain. The existing analysis transaction rolls back correctly; cancellation
  now preserves that old mesh and leaves any required refresh pending on return.
- The engine's separate 32-map renderer LRU could evict the map object behind a
  retained mesh, losing weak-keyed Gen3 context. EngineSheets protects the two
  most recently visited completed voxel maps during engine trimming as well.
- Ghost NPC ground queries on unbuilt neighbours entered Gen3 terrain analysis
  from the render thread. Cold ghost cards now wait for their terrain; their
  pose clocks continue advancing. Cold height queries return a cheap fallback
  when neither terrain nor context is prepared.
- setLive detached and synchronously deleted whole GPU neighbourhoods. Detached
  entries now go through RetireQueue in nominal 1 ms pump slices, with release
  checkpoints per GPU buffer and template. Template cache entries are removed
  before a suspended final release, preventing reuse of half-released buffers.
- Repeated 2x2 water rocks were separately carved into large Lua quad tables.
  Immutable templates now share by source surface and sixteen source tile IDs.
  Door-approach height queries also reuse their direction table.
- Cold/background ceilings increased from 4/5 to 8 ms at 60 Hz, still reduced by
  measured frame headroom and scaled to the actual target rate. Builds now log
  queue wall time and active build CPU separately (`voxel mesh ready`).

Measured checks:
- Route 114 body fixture: 7.36 s prior accelerated run versus 5.64 s after
  template reuse, identical image hash
  `869844776875b1b1571e4b25646396f2448fc2e24508bf4820fefe3318620eed`.
  Stored vertex count fell from 1,280,880 to 1,002,630.
- Full Route 114 with ROM connection masks and real 60 Hz pacing: mesh ready at
  7.58 s, active build CPU 3.37 s. Full image hash
  `48dc193034b9c6606166ac4bd36107fcccf7a715d86860c49ec97aced138676b`;
  final rerun produced the same image and its screenshot was inspected.
- Cave tests preserve the engine map object, survive a cancelled refresh and
  two interior live-set changes, prioritise the route under memory pressure,
  and return the existing GPU mesh in about 5–8 microseconds. This is cache
  lookup timing, not a measured full in-game warp duration.
- Cold ghost pose/height tests forbid Gen3.forMap on the unbuilt neighbour;
  its animation pose runs once and no terrain context is constructed.
- Deferred eviction test verifies release does not happen in setLive, then
  happens during pump. Pure retirement checks cover slicing, appending during
  suspension, complete drain and queue reuse.
- Non-FFI Oldale/adjacent-route path passes cache/retirement/priority tests and
  retains its prior terrain hash. Route 119 terrain, translated/grid-lit view,
  planar reflection and shadow comparisons against expanded geometry pass.
- 36 scheduler/stream checks, 13 shared-hull checks, 21 syntax checks, diff check.

Cold generation is still several seconds. The largest sampled native pump was
about 57–62 ms in paced/combined checks, so this is not evidence of zero frame
hitches. Hardware Switch freezes and complete real-game transition timings
remain unverified. The new queue/CPU log timings will distinguish rebuilds from
background scheduling delays in subsequent play logs.

Installed all 91 runtime files in the project and custom G: mod directories;
byte-for-byte verification performed. Numbered alternative mods were untouched.
Custom-folder backups: `tmp/emerald_perf/route-cache-backups`.


### Queued refresh starvation and transient missing terrain (October 20)

Reported logs: `MAP_G00_N19 full refresh; queued 45.38s, build CPU 1.41s`
and `MAP_G00_N31 full refresh; queued 79.29s, build CPU 1.26s`. The existing
`queued` number includes the entire elapsed lifetime of the job, including
suspended slices and overlay pauses, not only time before work first starts.
New logs include `first slice` delay and the number of resumed slices as well.

A defect in the previous retirement patch was reproduced: swapSlot called the
old mesh's release before replacing its cache reference. Release now has budget
checkpoints, so a suspended refresh could leave a render frame looking at GPU
buffers that had already been deleted. swapSlot now publishes the replacement
and queues retirement afterward. The build also stages grass, flowers and
figures, then commits analysis and all drawable slots without a yield between
them. Failed refreshes retain the previous drawable slot.

The scheduler previously treated a refresh of the visible current map as urgent
and chose other jobs mostly by distance. Missing neighbouring terrain now wins
over automatic seam refreshes and border-only completion. Cold foreground
terrain and explicit foreground edits keep priority; the shared preparation
barrier remains because concurrent unfinished tileset analysis is unsafe.
Automatic seam refreshes are labelled separately from block-edit refreshes.

Checks:
- Native atomic refresh test asserts every suspended frame retains the old
  published analysis and auxiliary generation until the replacement terrain
  commits, and that no displayed terrain is passed to release. A forced geometry
  addition proves it rebuilt. A separate intentional-failure fixture preserves
  the prior terrain and records the failure.
- Real Oldale / Route 101 test repeats the same request pattern as live frames:
  missing neighbour completes before the queued current-map seam refresh;
  the delayed refresh then completes normally. Terrain image hash stays
  `e17f897ecf4a371aa6038c6f1db9953926c118b5ab346e11c6b1da64d525650d`;
  screenshot inspected.
- Full Route 114 plus a real neighbour passes cave-history and cold-ghost
  checks. Full Route 114 image hash remains
  `48dc193034b9c6606166ac4bd36107fcccf7a715d86860c49ec97aced138676b`.
- Existing 36 stream/scheduler checks, 13 hull checks, retirement checks,
  21 module syntax checks and diff whitespace check pass.
- One initial combined fixture failed its exact vertex-count assertion because
  the unrelated neighbour fixture legitimately changed seam geometry. The
  isolated forced-refresh test passes the exact count assertion; the real-map
  priority test covers neighbour-driven seam updates independently.

GPU capability was inspected in the actual native test runtime, not inferred
from the GPU brand: LOVE 11.5, OpenGL 3.3, NVIDIA RTX 3060, instancing=true,
`love.graphics.newComputeShader=nil`, `dispatchThreadgroups=nil`. Rendering,
shader effects and shared-hull instancing already use the GPU. No GPU mesh-
generation path was added: this runtime provides no compute dispatch interface.
A portable compute implementation would require backend/engine work and parity
validation; an unused GPU toggle would not accelerate the Lua map analysis.

This is not a hardware verification of the reported 30–79 second waits or all
boundary freezes. The new scheduling and publication paths are regression-tested;
real Switch and mobile timings remain unverified. All 91 runtime files match
between the project and custom G: folders. Prior custom mesher backed up under
`tmp/emerald_perf/atomic-queue-backups`; the test ZIP was refreshed.

## 2026-10-20: CPU work, cache reloads and memory pressure

These changes apply to the existing 11.5 CPU path as well as the 12 preview:

- Terrain sinks collect conservative bounds while emitting geometry. Uploads
  no longer scan all six expanded vertices again just to find those bounds.
- Shared hull uploads skip an intermediate double-precision expanded stream.
- Static ROM pixel events are replayed across analysis passes. This preserves
  duplicate overdraw events, ordering, colors and sheet placement; it is not
  a flattened composite with different sample counts. The cache is capped at
  8 MiB, publishes only complete decodes and clears on art/ROM invalidation.
- Forest/rock template cache entries are weak, pinned by live map quad arrays.
  Leaving regions no longer retains every template for the entire session.
- CPU raw buffers start at 48 KiB and grow only within a 768 KiB block.
  ByteData ownership permits immediate release of replaced and uploaded CPU
  allocations, and explicit cleanup when a build is cancelled.
- Frustum culling uses plane support vertices instead of transforming eight
  corners per box; 10,000 perspective/orthographic/rotated cases match the old
  reference. A neighbour transform is composed once per forest pass.
- Shader uniform argument arrays are reused instead of allocated every draw.
- New VXM2 cache metadata preserves spatial block boundaries and bounds.
  Reloading a mesh no longer combines distant chunks into broad culling boxes
  or scans every vertex to recover their bounds. Old or malformed layout
  metadata falls back to the previous bounded scan. That first read repairs
  its index for future visits without changing the binary geometry. Existing
  cache files do not need deletion; newly built entries preserve the finer
  spatial boundaries immediately.

Sequential Route 119 CPU comparison, same 11.5 runtime/map/camera on this PC:

| Metric | Prior custom-folder mod | Updated mod |
| --- | ---: | ---: |
| Total build wall time | 10.98 s | 10.11 s |
| Median completed render | 3.00 ms | 2.63 ms |
| Maximum pump slice | 52.75 ms | 43.72 ms |
| Submitted vertices | 2,903,190 | 2,903,190 |

Both screenshots hash to
`7250e71aa294b2c6c90af0e106fcfb963b88f1bf44404e89f94df32a621e616c`.
This is one local comparison, before the final spatial-cache/raw-buffer
ownership refinements; it is not a device-wide FPS guarantee. Other cold
runs still show 80–125 ms outliers, and map analysis remains expensive.
The eight-cycle eviction/reentry stress run completed with matching pixels;
its reported 67.21 s spans all cycles, not one map's load time.

Native validation additionally covers Route 114 adjacent prefetch and warm
boundary promotion, unchanged engine animation state, failed and atomic
refreshes, spatial cache round trips, cancellation, and 11.5 non-FFI packed
fallback. OpenGL shadow/reflection comparisons remain pixel-identical.
Snapshots and JSON/log evidence live under `tmp/emerald_perf`.

See [love12-migration.md](love12-migration.md) for the separate LÖVE 12 preview,
real compute path, CPU fallback, runtime pin and platform limitations.

Deployment: 17 changed/new canonical mod files copied into
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE`, with pre-copy hash guards and backups in
`tmp/emerald_perf/love12-perf-custom-backup`. All 134 selected source/custom
files match (including unchanged assets and their documentation). The test
mod ZIP and isolated Windows 12 preview were refreshed. Numbered mod copies
and the stable runtime executables were not changed.

## 2026-10-20: subsequent build and frame-spike pass

- Engine sheet cache misses requested from a voxel job now use the sheet
  prefetcher's independent coroutine. Its layers obey the caller's budget;
  cancelling that caller leaves a resumable sheet job instead of a poisoned
  `false` cache sentinel or partially animated shared state. Ordinary engine
  consumers can still finish a pending sheet immediately when necessary.
- Byte-backed meshes upload their initial data in `newMesh`, avoiding an
  empty buffer allocation followed by a second full `setVertices` upload.
  Runtimes exposing DataView also avoid copying raw CPU blocks before upload.
- Static atlas writes use the ROM decoder's byte colors directly on RGBA8
  ImageData. Other formats and runtimes without FFI use the native setter.
  Native tests compare every byte value and transparency against that setter.
- Gen 3 grass analysis retains templates plus placements instead of thousands
  of duplicated quad/vertex tables. Placements expand straight into bounded
  buffers in 256-pixel spatial groups. Grass remains in its existing separate
  render pass. A grass-instancing experiment was rejected because additional
  draw calls slowed the close view; dense tree instancing is unchanged.

Native 11.5 sheet fixture: a synchronous cold bake took 314 ms. The budgeted
voxel caller completed the same work over 86 slices, with a 24.4 ms maximum
slice. Bottom/top/reflection pixels match, and abandoning the voxel caller
mid-bake still produces a complete, reusable engine cache. These are different
work distributions, not a claim that total preparation takes only 24.4 ms.

Two interleaved Route 119 trials using the final grass chunk layout:

| Metric | Turn-start snapshot | Updated |
| --- | ---: | ---: |
| Build wall time | 6.19 / 5.98 s | 5.96 / 5.78 s |
| Completed render median | 2.71 / 2.71 ms | 2.87 / 2.71 ms |
| Lua heap after build | 250 / 238 MiB | 187 / 191 MiB |
| Submitted vertices, including grass | 3,001,488 | 2,961,942 |
| Visible draw calls | 66 | 66 |

The result is a modest build improvement and substantially less Lua memory;
this PC test does not establish a consistent render-time improvement. All
four scene hashes are identical (`c33c100f...33dee3e`). A separate close grass
view with world curvature also matches the reference exactly (`9fd65178...bc8a164`).
The fixture deliberately omits actors and the separate water pass.

Overall mesher outliers still reach approximately 50–126 ms in other runs;
the engine-bake fix does not eliminate every source of frame spikes. GPU
uploads and other analysis work remain. Android, iOS and Switch hardware
timings are unverified. Logs, JSON and inspected screenshots use the
`tmp/emerald_perf/round2-*` prefix. Tests cover cache reload/legacy repair,
cancellation, cave return, neighbor scheduling, animation state, CPU packed
fallback, real GPU expansion, and OpenGL shadow/reflection parity.

Deployment for this pass: seven changed/new runtime files installed into
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE`; all 135 selected mod files hash-match
the project. Replaced files are in `tmp/emerald_perf/round2-custom-backup`.
The mod test ZIP and isolated LÖVE 12 Windows preview were rebuilt; its packed
135 mod files match source and its launcher boot/render smoke test passed.
The final large-route packed fallback also matches the CPU/GPU scene hash.

## 2026-10-20: cold-sheet stalls and selective render optimization

The remaining cold-sheet tail was the host's `pixelCanvas`: a large Lua
table of per-pixel strings followed by an uninterruptible `table.concat`.
`EnginePixelCanvas` substitutes direct RGBA8 writes at that known private
factory. It is guarded by the upvalue name, debug API, FFI and readable image
format; otherwise the original host baker is retained. Both consumers of
the shared factory benefit, including reflection covers. Unload restores
the original function only while this mod still owns the replacement.

`EngineSheets` also slices `entries`, because the animation setup scan runs
before its layer-drawing checkpoints. Immutable metatile classification data
is parsed at mod startup instead of the first visible map build. That moves
parsing work into loading; it does not remove the parsing cost.

Matched native 11.5 sheet regression fixture:

| Metric | Turn-start mod | Updated mod |
| --- | ---: | ---: |
| First voxel caller slice | 16.28 ms | 1.02 ms |
| Maximum voxel caller slice | 26.15 ms | 3.59 ms |

Bottom/top sheets, all animation slots and reflection-cover pixels match
the original baker. Cancellation leaves the independent bake resumable;
mod unload restores the exact original private factory. These figures
describe the sheet fixture, not every map's worst frame.

Rendering changes:

- Ordinary CPU terrain uploads keep four corners per quad, with a uint16
  triangle index buffer. Their vertex data is one third smaller; the added
  index buffer means total allocation savings are less than one third.
  Raw six-vertex disk caches remain compatible. A rejected index upload
  recreates the original mesh, with tested resource cleanup.
- Dense instanced tree/rock hulls keep their original upload path. Indexing
  those improved the camera-only fixture but slowed the combined shadow
  pass, so that experiment is not the shipped default.
- Successful scalar and texture uniform values are reused across scene
  shader variants. Mutable vectors/matrices are always resent, and failed
  sends are retried. No table-identity shortcut is used for mutable data.
- Instance groups record offset ranges once; multi-part templates can cull
  an off-camera part independently of the rest of a visible group.

The benchmark now caches companion data like the real mod loader and can
measure 120 frames including sun rendering (`PERF_FULL_RENDER=1`). Its GPU
fence still uses a canvas readback. Earlier camera-only gains from indexing
all hulls must not be interpreted as final whole-scene FPS gains.

The selected full shadow/terrain/grass CPU fixture ranged around 3.91–4.25 ms
against 4.07–4.21 ms before; this does not establish a consistent large
whole-scene improvement. Native 12 OpenGL compute measured 4.28 ms before
and 4.25 ms after. Final CPU and GPU screenshots share hash
`bcba7232...86550e`; separate grid, translated-lighting and reflection tests
also match. The static fixture excludes actors and the separate water pass.

The clearest gains are reduced cold-sheet stalls and smaller ordinary
terrain buffers. Other first-build slices still show roughly 70–110 ms
outliers, and mobile/Switch hardware performance remains unverified.
Evidence is under `tmp/emerald_perf/round3-*`. Added checks cover compact
triangle/index bytes, rejected uploads, missing APIs, mutable uniforms,
partial instance culling, exact sheet pixels and private-hook restoration.

Deployment: nine changed/new runtime files copied into the canonical
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE`, backed up under
`tmp/emerald_perf/round3-custom-backup`. All 137 selected source, custom-folder
and packed-preview files match. The test mod ZIP and isolated LÖVE 12 preview
were rebuilt; native 11.5/12 entry checks, GPU failure recovery and packed
launcher boot/render checks pass. Existing imported data needs no re-import.

## 2026-10-21: steady-frame allocations and submission overhead

The sheet prefetcher now remembers when the current neighbourhood has no
remaining candidates. It still touches live sheets every update, but stops
allocating candidate/sort tables and looking up the same connections until
`rebuildNeighbors` replaces the neighbourhood. Dataset changes and sheet
release reset this state. A native regression verifies 1,000 skipped scans,
1,000 live-sheet touches, and renewed discovery after topology replacement.
In that small fixture, temporary allocation fell from 563.3 to 110.9 KiB per
1,000 calls; time fell from 1.67 to 0.65 ms **total**, not per frame. Collection
was stopped only inside this diagnostic allocation sample, then restarted.
Gameplay collector settings are unchanged.

The update-side voxel prefetch queues meshes without allocating the two
render-only neighbour result lists. Live-set tracking compares stored map
IDs rather than rebuilding a table and concatenated signature every frame.
The render/VR caller still gets its own result lists. Cancellation, neighbour
promotion, retirement, multi-floor cave return, packed CPU uploads and
legacy-cache repair checks pass with this path.

Rendering/preparation changes:

- Numeric vector/matrix uniforms keep value snapshots. Equal values skip
  repeated native sends, including across different table identities;
  in-place mutations still send. Copies preserve the last submitted values
  if the caller subsequently mutates its array without sending it. Unfamiliar
  tables retain the conservative resend path; failed sends retry.
- Ordinary terrain batches extract six camera planes once per batch instead
  of once per part. An independent eight-corner reference agrees across
  10,000 orthographic/perspective/rotated cases, including edge contacts.
- Object extraction can read RGBA8 atlas bytes directly. Its normalization
  table comes from the host's own `getPixel`, preserving float rounding at
  carving thresholds. Unsupported formats, unreadable pointers and runtimes
  without FFI use native reads. Native checks cover all 256 channel values.

Full Route 119 shadow/terrain/grass screenshots retain hash
`bcba7232...86550e` on CPU and LÖVE 12 OpenGL compute. Translated lighting,
grid, reflection, shared-hull shadow and close curved-grass screenshots
also match; the latter retains `9fd65178...8a164`. Screenshots were inspected.
The full CPU rendering samples ranged around 4.22–4.74 ms against a 4.35 ms
turn-start sample: this does **not** establish a material whole-scene FPS
increase. Smaller 64px instance groups reduced submitted vertices but slowed
the full pass; the existing 128px default remains.

The harness now preloads immutable classifications as the real mod does and
reports explicit GC time separately from `ChunkMesher.pump`. A sampled route
build saw 30.5 ms of GC and 36.0 ms of pump work at their separate maxima;
the cache/refresh fixture saw a 103.1 ms GC outlier and a 49.9 ms pump outlier.
Thus remaining long-frame stalls are not solved by the rendering changes.
The steady-state allocation reduction addresses one contributor, while large
analysis heaps and native/JIT work still need investigation. No mobile or
Switch hardware measurements were available. Evidence: `tmp/emerald_perf/round4-*`.

Deployment: eight runtime files updated in the workspace and the canonical
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE`, with changed-file backups under
`tmp/emerald_perf/round4-custom-backup`. All 137 selected files match source,
custom folder and rebuilt `dist/love12-preview/game.love`. The performance
test mod ZIP was refreshed. Native 11.5/12 mod-entry checks, compute failure
recovery and packed preview boot/render checks pass. Restart the game to
load the changes; no ROM re-import is needed.

## 2026-10-21: shared hull corners and compact compute output

`HullPoints` reuses identical integer corner arrays while constructing each
immutable round template. Its pool is local to that construction and is
discarded afterward; templates retain only the shared corners. Fractional or
out-of-range coordinates keep ordinary arrays without rounding. Mutable
camera/pose vectors do not use this pool. The 10,000-case check covers key
collisions, exact coordinates, pool isolation and fallback.

In the Route 119 fixture this avoided 232,528 small table allocations.
Retained Lua memory, measured after collection outside timed frames, fell
from 146.0 to 125.3 MiB (20.7 MiB / 14.2%). The selected paired run's worst
build slice fell from 50.9 to 34.0 ms, while its 95th percentile stayed around
11.5 ms. Other runs still have larger outliers: the refresh fixture recorded
67.0 ms of explicit collection and 59.5 ms of build work at separate maxima.
This reduces allocation/retention pressure, not every source of a long frame.

The LÖVE 12 compute path now writes four vertices for ordinary indexed
terrain quads instead of six. Triangle indices preserve the original two
triangles; CPU raw/disk streams and logical vertex counts remain unchanged.
Dense instanced hull templates retain six vertices, as selected by earlier
full-pass measurements. The final route fixture allocated 25.9 MiB less
compute output; ordinary output vertex buffers are one third smaller.
Index-buffer storage is additional. The combined GPU render median remained
around 4.88–4.93 ms against 4.88 ms before, so no material whole-scene GPU FPS
gain is claimed from this memory change.

Input/output GPU buffers and the pending mesh now have cancellation ownership
while compact index preparation can yield. The native check cancels inside
that preparation, verifies released objects and then successfully retries.
Rejected index uploads, shader compilation and mid-build dispatch failures
recover through CPU geometry. Startup preflight validates both output layouts;
the benchmark now performs preflight outside visible build timing, matching
the real mod entry.

Alternating warmed full-pass tests found the direct terrain support-plane
test faster than the previously prepared plane table: 3.90 versus 4.03 ms in
that CPU-mesher fixture (about 3.3%). Direct tests are the default again;
`PERF_COMPARE_TERRAIN_CULLING=1` retains a diagnostic comparison. Extending
prepared planes to hull groups was also slower and was rejected. A separate
proven-opaque hull shadow shader preserved pixels but was about 2.9% slower;
that experiment was removed.

CPU/GPU route screenshots retain `bcba7232...86550e`; translated lighting,
reflection and shared-hull shadow pixels match expanded geometry. Close
curved grass retains `9fd65178...8a164`. Crystal Cherrygrove before/after
screenshots also match (`755f3ab2...67ec0`), checking that corner reuse leaves
the existing Gen 2 trees intact. Packed CPU fallback, cache repair, neighbour
promotion, cave return, retirement, cancellation and atomic refresh checks
pass, as do real mod entry checks on 11.5 and 12. Screenshots were inspected.
The fixture excludes actors and the separate water pass; mobile/Switch
hardware was not measured. Evidence: `tmp/emerald_perf/round5-*`.

Deployment: five changed/new runtime files installed in the workspace and
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE`, with backups under
`tmp/emerald_perf/round5-custom-backup`. All 138 selected source, custom-folder
and packed-preview files match. The performance test mod ZIP and isolated
LÖVE 12 preview were rebuilt; packed launcher boot/render checks pass.
Restart to load the mod changes; existing imports and caches remain usable.

### Round 6: smaller uploads, fewer temporary tables, mobile walker repair

Round hull templates now share exact UV pairs within each immutable template,
as well as XYZ corners. The pool uses unrounded floating-point keys and is
discarded after construction. It does not change texture seams, triangles,
mutable pose data or rendered pixels. Route 119 avoided another 86,330 tiny
tables; retained Lua heap fell from 126.19 to 117.95 MiB on the CPU fixture
and 125.92 to 118.92 MiB on the compute fixture.

Compute input buffers previously uploaded the full 4,096-quad CPU slab even
for partially filled spatial blocks. A zero-copy DataView now limits uploads
to live quads. Unsupported or rejected views use the original input buffer.
Views and GPU objects remain owned by the cancellable build. In Route 119,
input uploads fell from 112,066,752 to 54,746,208 bytes (51.1%); output
geometry is unchanged. Exact-channel tests, rejected/missing view fallback,
dispatch/index failures and mid-build cancellation all pass.

Selected matched runs on the local RTX 3060/OpenGL desktop:

| Measurement | Before | After |
| --- | ---: | ---: |
| CPU build completion | 6.26 s | 4.37 s |
| CPU worst measured build pump | 73.7 ms | 40.4 ms |
| CPU 95th-percentile pump | 11.53 ms | 11.44 ms |
| CPU full-pass render median | 4.15 ms | 3.85 ms |
| Compute build completion | 5.17 s | 4.47 s |
| Compute worst measured pump, including explicit GC | 31.3 ms | 36.8 ms |
| Compute full-pass render median | 4.34 ms | 4.23 ms |

These are individual paired runs, not mobile performance guarantees. The
draw count and vertex topology are unchanged; small render differences can
include timing noise. The durable changes are fewer allocations and less
input transfer. Long-frame outliers remain, including garbage collection.
Both Route 119 screenshots retain `bcba7232...86550e`. Screenshots were
inspected. Neighbour promotion, cave return, retirement, disk/legacy cache
round trips, cancellation and atomic refresh checks pass. Actual mod startup
passes on 11.5 and the isolated 12 preview. Evidence: `tmp/emerald_perf/round6-*`.

The Android walker failure came from species lookup depending on a custom
data folder. Emerald's named/internal species IDs are now resolved from
the source game's cache using the same default, portable and virtual-cache
reader as artwork. Course facts use that reader too. The screen repairs old
walks with a missing dex from their preserved raw Pokemon, without replacing
its identity or changing its source save. Successful ROM imports invalidate
artwork misses; changed cache folders invalidate prior source lookups.

A native regression fixture simulates Android with no custom folder and
denies direct cache file reads, forcing LOVE's virtual filesystem. It checks
Emerald walking/portrait art, higher-generation import precedence (HGSS
followers, BW portraits), cache-folder changes and persisted legacy repair.
Both images render in `round6-mobile-walker.png`. Existing minigame,
ROM-roster and multi-game delivery checks pass. This is simulated mobile
filesystem coverage, not an Android/iOS device test.

Deployment: three mod files updated in the workspace and
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE`; all 138 runtime files match. Backups are
under `tmp/emerald_perf/round6-custom-backup`. The performance mod ZIP and
isolated desktop preview were rebuilt and its packed launcher renders.
Walker fixes are application source changes: Android users need a rebuilt
mobile app, not only the mod ZIP. No release mobile package was built here.

### Round 7: entry hitches after destination voxels are ready

The remaining entry stall also exists outside meshing: `setMap` expands the
engine's neighbour set, builds flat renderers for newly exposed maps and
loads their NPC sprite images. A ready destination voxel mesh does not make
that work ready. The new native `tools/emerald_seam_perf_check` uses actual
Emerald maps, `OverworldController:setMap` and the real engine sheet hooks,
with isolated new-game state and music disabled. Every destination is
asserted to be an already-loaded neighbour. This fixture isolates entry work;
it does not measure a complete interactive walking/render frame.

Prefetch now follows the same view-sized neighbour graph that entering each
nearby map will request, rather than preparing only direct connections. The
plan is memoized per neighbourhood. It also uploads future NPC image assets
one per update, without spawning NPCs, running their scripts or moving the
player. Discovery is refreshed on topology/data changes. The existing
12-pair sheet allowance limits speculative preparation; live pairs are now
explicitly protected against eviction. Instrumented builds record this work
under `EngineSheets.pump`, separately from `ChunkMesher.pump`.

The engine now shares immutable atlas Quads with their sheet record rather
than allocating the same animated-slot Quads for every map. Their first
construction can be sliced by the prefetch job. No caller releases those
shared Quads with a map's private batches. The mod guards the new host APIs,
so it can still run with an older host; sharing and explicit pinning require
an updated application build.

Matched entry trace, milliseconds (preparation drained before each entry):

| Loaded destination | Previous code | Final code |
| --- | ---: | ---: |
| MAP_G00_N29 | 3.93 | 3.05 |
| MAP_G00_N13 | 24.86 | 4.36 |
| MAP_G00_N28 | 15.43 | 4.60 |
| MAP_G00_N26 | 129.76 | 5.35 |
| MAP_G00_N27 | 1.80 | 2.08 |
| MAP_G00_N12 | 1.41 | 1.02 |

These are desktop fixture runs, not device guarantees or proof that every
boundary is now hitch-free. Another final run measured 1.0–5.2 ms entries;
its largest preparation slice was 8.9 ms and an explicit GC step reached
18.3 ms. The separate full Route 119 build still produced a 68.5 ms maximum
pump including GC, so general cold-build outliers remain.

Full shadow/terrain/grass pixels and disk-cache round trips are unchanged
(`bcba7232...86550e`); the screenshot was inspected. Sheet tests verify
bottom/top/reflection hashes, zero repeated shared-Quad allocations, bounded
live-sheet protection, early entry, cancellation recovery and mod unload.
Native mod startup passes on 11.5 and the isolated 12 runtime; exact GPU
geometry, failure fallback and cancellation checks pass too. Texture-getter
and shader-copy render experiments gave no reliable full-pass improvement
and were removed. No new steady-state FPS gain is claimed this round.

Evidence is under `tmp/emerald_perf/round7-*`. The canonical workspace and
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE` receive the two changed mod runtime
files; the rebuilt desktop preview also includes the engine changes. No
mobile/Switch hardware or release mobile package was tested/built here.

### Round 8: less tile-bake garbage and bounded hull preparation

The cold-build trace found remaining overshoots in private hull setup before
face emission. `roundTemplate` now checks the cooperative budget in 20
additional row loops, including silhouette classification, background
matching and disc construction. Inner pixel loops stay free of new budget
polls. These passes only modify local working tables, so a yield does not
publish partial geometry. Existing refresh/cancellation ownership is retained.

CPU sampling also identified temporary entry decoding in `Gen3Tiles.drawLayer`.
Each layer draw allocated an eight-entry table plus eight entry records,
then used four entries and discarded them all. This path now reads the four
required ROM words directly. Palette banks, tile banks, flips, transparency,
plot order and animated tile overrides are unchanged. `entries()` remains
available to callers that need the decoded records. No new persistent cache
or larger memory allowance is introduced.

The new pure `tools/gen3_layer_decode_check.lua` compares 1,920 randomized
layer cases against the previous algorithm, including both banks, flips,
missing palettes, transparency, tile overrides and truncated metadata.
For 2,000 warmed layer draws with GC stopped only during measurement,
temporary allocation fell from 2,775.8 to 7.5 KiB (99.7%). The real sheet
fixture can load the old decoder with `PERF_REFERENCE_GEN3_TILES`; native
bottom/top/reflection hashes match it exactly. Cancellation, early-entry,
shared-Quad and live-sheet eviction checks also pass.

Selected matched Route 119 desktop runs:

| Measurement | Previous | Final |
| --- | ---: | ---: |
| Build completion | 9.48 s | 8.86 s |
| Largest pump including explicit GC | 47.37 ms | 37.72 ms |
| Largest build-only pump | 46.91 ms | 37.46 ms |
| 95th-percentile pump | 12.29 ms | 11.79 ms |
| Largest explicit GC step | 13.70 ms | 30.65 ms |

Individual runs fluctuate; the allocation reduction is the controlled
measurement. The larger final GC step illustrates why this is not a claim
that all hitches are gone. The separate final GPU run still reached a
70.4 ms combined pump, dominated by a 62.4 ms explicit GC step.
Steady render geometry and draw counts are
unchanged, and no separate steady-state FPS gain is claimed. The screenshot
retains `bcba7232...86550e` and was inspected. Already-loaded map-entry traces
still pass (approximately 0.9–6.3 ms in the final run), along with 1,619
Emerald map-definition checks, cache/legacy round trips and atomic refresh.
The final Emerald GPU scene keeps the same screenshot hash; Crystal's
Cherrygrove reference also remains `755f3ab2...67ec0` after the new hull checks.

Evidence: `tmp/emerald_perf/round8-*`. The one changed mod runtime file is
installed in the canonical workspace and `G:/Gen2Recomped/mods/DRAMATIC_SHAPE`.
The rebuilt desktop preview also includes the decoder optimization, which
is an application change and requires an updated app build. No release
Android/iOS/Switch package or device benchmark was produced here.

### Round 9: smaller immutable hull coordinates

Shared hull corners and UV pairs were still retained as 151,110 individual
Lua tables in the Route 119 scene. On FFI hosts `HullPoints` now stores those
private immutable values in owning numeric buffers with the same one-based
coordinate access. Interned integer XYZ points are already restricted to
[-256,255], so int16 storage is exact. UVs retain full double precision.
Fractional/out-of-range XYZ points, diagnostic opt-out and hosts without FFI
retain ordinary arrays. There are no borrowed slab pointers, larger cache
budgets, changes to mutable pose vectors or new GC settings.

Matched CPU fixture results:

| Measurement | Previous tables | Compact coordinates |
| --- | ---: | ---: |
| Retained Lua heap after diagnostic collection | 118.02 MiB | 108.86 MiB |
| Largest build-only pump | 44.12 ms | 34.23 ms |
| Largest combined pump | 44.88 ms | 36.11 ms |
| 95th-percentile combined pump | 10.69 ms | 12.52 ms |
| Largest explicit GC step | 26.70 ms | 27.10 ms |

The durable saving is 9.17 MiB (7.8%) less retained heap and 151,110 fewer
coordinate tables to traverse. Timing remains variable; the percentile and
GC figures do not show a uniform frame-time improvement. The final compute
fixture retained 108.95 MiB and still had a 47.55 ms maximum combined pump.
No steady-state rendering FPS gain is claimed from this storage change.

The 10,000-coordinate test now also checks independent ownership after GC,
exact tiny/fractional UV doubles, opt-out, and missing-FFI behavior. Native
CPU and GPU Route 119 screenshots retain `bcba7232...86550e`; Crystal's
Cherrygrove retains `755f3ab2...67ec0`. The screenshot was inspected. Both
compact and forced-table/packed-upload paths pass cancellation, legacy/disk
cache round trips and atomic refresh. Actual mod startup passes on 11.5 and
the isolated 12 runtime. Evidence: `tmp/emerald_perf/round9-*`.

This change is wholly in the mod runtime. The workspace and
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE` receive the updated `HullPoints.lua`,
with backup under `tmp/emerald_perf/round9-custom-backup`. All 138 selected
runtime files match. The mod test ZIP and desktop preview are rebuilt.
Restart the app to load it; imports and disk mesh caches remain compatible.
Mobile/Switch hardware has not been measured.

### Round 10: partial-build cleanup at seams and shadow snapshot allocations

Changing the live neighborhood already retired completed meshes incrementally,
but cancelled unfinished jobs still released their partial GPU batches inside
`setLive`. Those batches can contain many buffers even when the destination
map is already drawable. GPU owners are now explicitly tagged and passed to
the same budgeted retirement queue. CPU data, files and analysis rollback
remain immediate, and explicit invalidation still drains resources immediately.
The cancelled job detaches before retirement, so it cannot publish stale work.

Native cancellation fixtures captured 12 CPU-upload parts and 17 compute-path
parts. Boundary cancellation took 1.60 ms and 0.81 ms respectively; neither
freed its partial GPU batch inline. Subsequent retirement pumps released every
buffer. This demonstrates removal of this synchronous cleanup path, rather
than a before/after measurement of a whole gameplay crossing.

Shadow invalidation also formatted a new concatenated signature each frame.
It now compares reusable numeric/reference snapshots against the last actually
rendered snapshot, committing only after a successful shadow pass. This retains
pose reversion, mesh replacement, battle changes and rate-limited shadow timing.
The small static signature used by the rate limiter is unchanged.

For 2,000 diagnostic signatures with 64 actors on LÖVE 11.5, signature CPU time
fell from 45.54 ms to 12.72 ms; temporary allocation fell from 4,593.71 KiB to
6.95 KiB. The LÖVE 12 comparison measured 51.22 ms to 12.59 ms. These figures
describe shadow bookkeeping only, not overall rendering speed. Native shadow
textures match for all 16 tested frames on both runtimes: HIGH casts 16 times,
BALANCED casts 3 times in each implementation. The frames include actor motion,
reversion and camera movement.

The Route 119 full-scene screenshot remains `bcba7232...86550e` and was inspected.
The warmed six-map engine-entry trace measured 0.78–13.59 ms; that fixture does
not include the entire walking update, draw or scripts. Spikes remain: the
Route 119 CPU build reached 48.15 ms including GC, and a separate cache/refresh
fixture reached 108.47 ms, mostly its 101.49 ms explicit GC step. This round
does not establish hitch-free crossings or mobile/Switch frame times.

Checks cover 10,000 shadow-snapshot frames, sliced retirement, immediate cleanup
fallback, native compute channels/cancellation, disk and legacy cache reloads,
atomic refresh, shared hull ownership and actual mod startup on 11.5 and 12.
Evidence: `tmp/emerald_perf/round10-*`. The canonical workspace mod and
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE` are synchronized, with changed-file backups
under `tmp/emerald_perf/round10-custom-backup`. The mod test ZIP and isolated
desktop preview are rebuilt. Restart to load the mod changes; no re-import is
required. No other numbered mod folders or player saves are changed.

### Round 11: lazy neighbor textures and smaller animation uploads

The expanded native crossing fixture now warms the source scene and all
destination voxel meshes, enters the destination through `OverworldState:setMap`,
then measures voxel prefetch, its first pump, engine-sheet prefetch and the
first two full renders separately. This exposed work missing from the earlier
map-entry-only trace: Lua eagerly evaluates `atlasFor(neighbor)` even for
`draw(nil, texture)`. Newly exposed neighbors without meshes therefore baked
their textures synchronously in draw, bypassing the cooperative build queue.

The render-side atlas lookup now declines Gen3 maps without either published
terrain variant. Their queued build prepares animation textures before atomic
publication of terrain and auxiliaries, as before. Drawn maps and fallback
terrain retain their textures. The fixture asserts that render never requests
an unready neighbor's atlas.

Matched stable-runtime captures, with the destination already loaded:

| Crossing stage | Previous runtime | Lazy texture lookup |
| --- | ---: | ---: |
| First render after entering MAP_G00_N29 | 25.06 ms | 16.39 ms |
| First render after entering MAP_G00_N13 | 514.21 ms | 10.96 ms |
| Second render on MAP_G00_N13 | 10.72 ms | 8.20 ms |
| Engine setMap on MAP_G00_N13 | 14.74 ms | 10.21 ms |

The large second-crossing stall included synchronous atlas preparations for
newly exposed maps. Both captured images match their baseline hashes exactly:
`d97733c3...f2a437c` and `3477ddba...8dffe8`. The second capture was inspected.
These are controlled desktop submission-time samples, not a guarantee of every
gameplay frame or a measurement on mobile/Switch.

Gen3 water/flower animation also uploaded a complete 1.2–1.4 MB atlas each step.
`AtlasUpdates` now retains reusable bands of changed rows, including original
static pixels in the small gaps between them. Neighboring dirty rows are merged
to limit driver calls. Actual source pixels, patch ordering, texture filtering
and the engine animation clock are unchanged. There are no additional full
animation-frame textures. The normal path also avoids retaining the previous
full-size mutable CPU atlas copy.

| Tileset fixture | Previous bytes/step | Band bytes/step | Upload calls/step |
| --- | ---: | ---: | ---: |
| Oldale | 1,196,032 | 294,912 | 5 |
| Route 119 | 1,335,296 | 389,120 | 7 |
| Rustboro | 1,409,024 | 393,216 | 8 |
| MAP_G00_N30 | 1,425,408 | 335,872 | 8 |

That is 71–76% less uploaded data. The final 11.5 test, applying 320 steps,
measured 159.91→119.50 ms, 203.49→152.01 ms, 226.29→155.71 ms and
167.26→145.01 ms respectively. These are texture-update component timings;
earlier runs fluctuated and do not establish a whole-scene FPS gain.
If a backend rejects partial uploads after even one successful band, that same
animation step overwrites the whole atlas and subsequent steps use the old full
upload path. Native tests on 11.5 and 12 compare every animation frame against
full uploads, exercise actual TerrainAtlas clock integration, inject that
partial rejection, verify the next fallback frame, and check cleanup and that
the shared static source remains unchanged.

Finally, a second edit/seam refresh can supersede an unfinished refresh. That
path now defers tagged GPU owners just like neighborhood cancellation, while
rolling back CPU analysis immediately. Native CPU and compute tests verify the
published mesh survives, partial buffers retire, and a replacement completes.
The OpenGL Route 119 capture still matches `bcba7232...86550e`.

Cold build and GC spikes remain. The CPU superseded-refresh stress fixture
reached 96.31 ms in a pump; the final compute fixture reached 38.16 ms. This
round fixes a reproduced loaded-map render stall, not all sources of stutter.
Evidence: `tmp/emerald_perf/round11-*`. Cache/legacy reloads, atomic refresh,
ownership checks and actual mod startup pass. The canonical workspace and
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE` are synchronized, with changed-file backups
under `tmp/emerald_perf/round11-custom-backup`. The mod test ZIP and isolated
desktop preview are rebuilt. Restart to load the changes; no ROM re-import is
required. Mobile/Switch hardware has not been measured.

### Round 12: retain the fitted shadow canvas

Profiling the full warmed crossing scene found repeated shadow-canvas creation
in both `ShadowMap.available` and `ShadowMap.begin`. The capability probe always
requested the smallest 1024px canvas, replacing an existing 1536/2048px canvas.
The subsequent pass enlarged it again. Besides allocating/releasing large GPU
resources every frame, this cleared readiness and defeated shadow reuse.

Availability now keeps an existing fitted canvas. The view-fitting pass still
chooses the correct size on a real view change, and changing the tier's
resolution cap invalidates the frame so that the new quality is applied.
Unsupported allocation remains a sticky failure until explicit invalidation.
The balanced-tier rate limiter also now requires a valid existing shadow frame:
it cannot postpone the redraw needed after invalidation or a resolution change.

Two matched 400-render desktop samples on the warmed native crossing scene:

| Submission-time measurement | Previous runtime | Retained canvas |
| --- | ---: | ---: |
| Stationary median | 7.62 ms | 2.54 ms |
| Stationary p95 | 15.87 ms | 8.58 ms |
| Moving-camera median | 8.16 ms | 4.77 ms |
| Moving-camera p95 | 17.21 ms | 13.05 ms |
| New canvases during either 400-render sample | 800 | 0 |

The moving-camera sample changes the camera by a quarter world pixel per render;
all 400 frames still cast shadows, so its improvement does not rely on skipping
the moving scene's sun pass. The stationary sample reuses its finished frame.
These timings include GPU command submission, not display presentation or a
completion fence. There is still variability: the moving sample's worst render
was 83.51 ms versus 21.64 ms in the previous run. This is a repeatable resource
churn fix and a median/p95 improvement, not proof that all tail spikes are gone.

The two already-loaded map crossings preserve their exact screenshot pixels.
First render times in the stationary pair fell from 15.59→9.23 ms and
13.72→8.16 ms. Engine setMap itself was variable (9.10→13.36 ms on the second
crossing), so no engine-entry speedup is claimed this round. The capture was
inspected. The CPU/compute Oldale reference remains `e4426bfb...480f0`.

With reuse actually functioning, animated cutout silhouettes must be included
in the shadow dependencies. TerrainAtlas now exposes the discrete animation
phase from already-prepared clock metadata, without preparing art or touching
GPU resources. Gen3 uses its extracted period/step count; Gen1/2 uses each
animation specification's own period and sequence. This metadata is weak-keyed
by tileset and cleared on invalidation. Stable frames reuse shadows, while a
texture-animation step forces a redraw even when the camera and actors are
still, including at balanced quality.

Native tests on 11.5 and 12 verify 200 stable capability probes without allocation,
quality/view changes, moving-scene invalidation, explicit retry after allocation
failure, and animation-triggered redraws at high/balanced quality. With sunlight
held fixed, eight animated frames per tier match a forced fresh shadow-map
render byte for byte. A pure mixed-period test checks 301 Gen1/2 clock values,
unprepared tilesets, no art access and invalidation. Full terrain animation,
ownership, syntax, numeric/legacy shadow stamps and actual mod startup checks
also pass. Evidence: `tmp/emerald_perf/round12-*`.

The three changed runtime files are synchronized in the canonical workspace and
`G:/Gen2Recomped/mods/DRAMATIC_SHAPE`, with replaced-file backups under
`tmp/emerald_perf/round12-custom-backup`. The mod test ZIP and isolated desktop
preview are rebuilt. Restart to load this mod-only change; imports and mesh
caches remain compatible. Mobile/Switch hardware has not been benchmarked;
the existing iOS path disables this shadow pass and does not gain directly
from this canvas fix.

### Round 13: seam-step floor height and reusable actor poses

The reported player dip is reproduced through the actual engine connection
path, rather than a teleport: `crossConnection` rebases the player one cell
outside the incoming map and animates the step into it. VoxelScene's out-of-map
height shortcut always returned zero to avoid sampling a raised border tree.
That shortcut also ignored a raised departing street. On Route 115 → Rustboro
(`MAP_G00_N30` → `MAP_G00_N03`) the visible floor is 16, but the old player pose
answered zero at all four sampled points in the seam step. Camera ground
following read that same incorrect height.

Root actor height queries now receive the live neighbor placements. An
out-of-bounds cell is translated into the neighbor whose actual map body
contains it, and reads that map's existing floor query, including its elevation
and sub-cell stair/waterfall interpolation. It does not read the incoming
border block, introduce a fabricated height, start a new build or change game
collision/elevation rules. Callers without a matching neighbor retain the
previous zero fallback. Both native CPU and compute fixtures now answer 16
throughout the real crossing, and camera ground follows 16 too. The diorama
capture `round13-height-capture.png` was inspected.

The headless height check exercises the actual height-function source with
16 floor cases across all four directions (flat, raised and recessed), a
sub-cell stair sample, exclusion of incoming border art and missing/unrelated
neighbor fallbacks.

The render loop also allocated a fresh pose array and record for every visible
actor every frame. These records are only consumed during the same synchronous
sun, camera, reflection and eye passes. VoxelScene now reuses private records,
rewrites every pose field including nil values/player flags, clears references
in records no longer used when a cast shrinks, and drops the pool on mod unwind.
No actor motion, shader state, NPC spawning or shadow dependency was changed.

Matched native measurements over 400 pose passes with 61 actors, GC stopped
only during this diagnostic allocation measurement:

| Pose component | Previous records | Reused records |
| --- | ---: | ---: |
| Temporary Lua allocation | 12,357.75 KiB | 1,450.61 KiB |
| Component CPU time | 113.97 ms | 103.25 ms |
| Moving-camera render median | 5.86 ms | 5.60 ms |
| Moving-camera render p95 | 7.07 ms | 6.54 ms |

The controlled result is 88% less temporary allocation in this workload and
24,800 fewer pose-record/list allocations over those 400 passes. The small
render-time differences remain subject to run variation; this is not a claim
that all map-entry stalls or GC spikes are fixed. No production GC settings
were changed. The two in-bounds crossing captures retain their exact baseline
hashes; only the off-map seam step intentionally changes player/camera height.

Native tests cover reuse, cast shrink/regrowth, clearing old sprite/palette
references and stale player flags. Compute-path animation/shadow comparisons
at high and balanced quality pass after pooling. Syntax, ownership, clock,
numeric shadow stamp and actual mod-entry checks pass. Evidence:
`tmp/emerald_perf/round13-*`. The updated VoxelScene is synchronized in the
canonical workspace and `G:/Gen2Recomped/mods/DRAMATIC_SHAPE`, with backup under
`tmp/emerald_perf/round13-custom-backup`. The mod test ZIP and isolated desktop
preview are rebuilt. Restart; no ROM re-import is required. These measurements
are desktop tests; Android/iOS/Switch hardware has not been benchmarked.
