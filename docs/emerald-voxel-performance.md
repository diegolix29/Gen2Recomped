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
