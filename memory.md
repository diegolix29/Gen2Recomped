# Repository Memory Log — gen2rec

## 2026-10-28
- Initialized shared memory for this repo: filled context.md (overview, git, architecture, deps, build/test) from README, docs/architecture.md and scripts/. No code changes.
- Branch `gen5-fixes` @ 4512eefb; working tree clean apart from these two untracked files.

## 2026-10-28 — Terrarium Advance Mod Gen 4/5 performance pass (uncommitted, untested)
- Diagnosis from the user's Android PerfOverlay shots: the grass bake is 1719 verts / 1800 tris PER TUFT, 64 tufts per 4x4-cell chunk, so about 110k Lua vertex tables per chunk (150-300 ms builds). Grass chunks were never freed.
- lib/Grass3D.lua: added LOD templates (Grass3D.LOD_KEEP {1,3,10,24} keep one of N blade clumps, chosen by angle) and meshFromInstancesLod, an FFI ByteData stamp uploaded with setVertices(Data) and setVertexMap(Data, uint16/uint32, 0-based). Falls back to tables if that fails.
- lib/Gen4Grass.lua: per-chunk LOD with hysteresis (lodFor), chunks that leave the window are released, and LOD swaps keep the old mesh until the new one is ready.
- lib/Gen4Detail.lua: FAST grass reach is now 896 on desktop / 576 on mobile (was 1024/768). GRASS_LODS_FAST rings: desktop {224:1, 512:2, rest:3}, mobile {160:2, 384:3, rest:4}, sparse (2 tufts per cell) from level 3.
- lib/Gen4Trees.lua: finishBucketFast writes shaded vertices into ByteData with the FFI and shares one generated quad index buffer. Falls back to the old table path.
- lib/Gen4NpcModels.lua: disk cache for Gen 4/5 bodies in the save dir under terrarium_cache/npc3d/<md5>.bin, keyed by sheet pixels + pose + PAD + solid opts. Bump CACHE_VERSION when SpriteSolid output changes. padRGBA is now lazy (makeFacingsJob in the pump).
- Main risk for testing: the Data-variant setVertexMap assumes 0-based raw indices. Garbled grass, trees or NPCs would point there.
- Syntax checked with lovec loadstring (scratchpad harness). The user does the in-game testing.

## 2026-10-28 — Terrarium per-draw pass (uncommitted, untested)
- Voxel3D.lua shader: a "rooted grass" encoding. VertexWater < -0.5 means the tuft root is at -(VertexWater) - 4097, and `ly` (height above the root) replaces the raw vertex_position.y in the grass bend and crush math. isWaterHeight is false for rooted vertices.
- Grass3D.meshFromInstancesLod(instances, level, rooted) and Grass3D.canRoot(): FFI-only, stamps the real ground Y. Gen4Grass now builds ONE rooted mesh per chunk (was one per terrace), skips chunks outside the view (scene.sphereVisible), and draws runs of meshes that share a model with a plain love.graphics.draw after one Voxel3D.draw.
- Gen4Trees.draw: one cached translate matrix per land (was a new one per bucket per frame).
- Profiling: Gen4Bridge.profile / Bridge.passStats (draws + ms per effect pass), shown by PerfOverlay as "passes/frame: name Nd X.Xms" (top 5, 5 s average) while the overlay is open.

## 2026-10-28 — Hitch capture (uncommitted, untested)
- Verified: the NPC disk cache works. %APPDATA%/LOVE/Gen2Recomp/terrarium_cache/npc3d held 53 bodies (9.8 MB). Gen 5 uses the same path (Bridge.isNativeWorld covers gen 4 and 5; Gen4WorldHost calls Npc.drawPose/pump).
- The user's desktop shot after the draw pass: 58 fps, 11.5 ms draw, 406 draws, pass costs all under 0.5 ms, builds peak 11 ms. Yet 41 frames in 10 s went over 50 ms, so the stutters are NOT the budgeted builds.
- Gen4WorldHost collect() (a full GC) runs only at fight start/end on mobile, not while walking.
- src/core/FrameProfile.lua: added FrameProfile.setHitchCapture(on, threshold) and lastHitch / hitches. Sections are summed per frame and the top 5 of any frame over the threshold are kept, plus the heap change (a negative value means a GC sweep). The window report is unchanged.
- Gen4Bridge also deposits "fx <pass>" times into FrameProfile.add. PerfOverlay turns capture on while it shows and prints "last hitch Ns ago: X ms" and "in: section ms ...".
- Next step: read the user's hitch line to find the real stutter source (engine land/model loads, GC, or a specific pass).
- Correction (same day): the user plays the packaged Gen2Recomped.exe. It bundles its own src/ (its FrameProfile.lua is dated 2026-09-17), so engine src/ edits do NOT reach it until the exe is rebuilt, while mod edits do. The hitch capture now lives in the mod's PerfOverlay: it wraps FrameProfile.section/add, takes pass times through Bridge.passHook, and times "g4 <fn>" for the Gen4Ground calls (modelFor, building, decalModelFor, bdhcFor, permBlockFor, objectsFor, runtimePropsFor, animationsFor, bake, canopyFor, bakeAnimated, liveModel, canvasFor, drawSky, drawFree, drawCanopy). The src/core/FrameProfile.lua hitch code stays and is harmless.

## 2026-10-28 — Walk-stutter pass (uncommitted, untested)
- Hitch data from the user (run through Play-Windows.bat, so src/ edits ARE live): hitches of 98 and 141 ms were all in draw, inside "g4 drawFree" (89 and 134 ms). The fx passes were tiny and one hitch frame had a -57 MB heap drop (GC). The log showed a load burst of 2964 meshes / 2037 ms, with single builds up to trees 70 ms, fence 38 ms and water 31 ms.
- Ground.drawFree is wrapped by Gen4Hide (runs 7 effect prepare() calls), Gen4Lawn and Gen4Sky (whose first Model.draw runs the sky and Bridge.runPre passes, i.e. the sun/shadow pre passes).
- Fixes:
  - Gen4Lawn Model.draw reuses one scratch materials table (was a new table per engine draw call).
  - Gen4Sky caches the horizon-filtered shape list per source list (was a new table per draw).
  - Gen4Hide.filtered builds its cover key once per drawFree (Hide.frameKey).
  - Gen4Hide times each prepare as "prepare <name>" and Gen4Sky times "sky+pre passes"; both deposit into the PerfOverlay hitch line.
  - Gen4Bridge.run has a GC pacer: up to GC_BUDGET (1.5 ms desktop / 2 ms phone) of collectgarbage("step", 0) per frame, then it rests until the heap grows to GC_REST x 1.25. It shows as "fx gc pacer".

## 2026-10-28 — Model sharing across route changes (uncommitted, untested)
- Finding: every map is its own Gen4Ground, and self.liveModels (land meshes) and self.buildings / self.fieldModels were per ground. The first step over a route border therefore re-decoded and rebuilt every land and building already in view.
- src/render/Gen4Ground.lua: Gen4Ground:sharedStore() shares the live models, buildings and field models between grounds keyed by terrain, set, buildingSet, fldeffSet, arealight, lightMember, lightBand and outdoors. A fogged map or the Distortion World keeps per-ground caches. Up to SHARED_STORES (3) stores are kept, evicting the least recently used. dropLitModels lets go of a shared store without freeing it. The LRU for shared stores is LIVE_CACHE_SHARED (48).
- Engine change, so it is live through Play-Windows.bat; the packaged exe needs a rebuild.
- Terrarium effects (trees, water, fence, rocks, flowers, bump, lamps) were already keyed by the shared land record, so they survive map changes. Gen4Glass was per ground; it now shares one cache per terrain unless the map has def.gen4ModelEdits.

## 2026-10-28 — drawFree hitch pass 2 (uncommitted, untested)
- User screenshots: hitches of 50-156 ms, mostly "g4 drawFree" (20-149 ms) with heap drops of 19-59 MB (GC). Smaller causes: prepare rocks 30, prepare trees 27, fx bump 15. Route-change reuse confirmed working from the log.
- src/render/Gen4Model.lua: added Gen4Model.multiplyInto(out, a, b). Gen4Model:draw now sends mvp and the uvRotScale/uvTranslate values from scratch tables (it allocated per shape per frame). Gen4Ground.drawFree uses scratch FREE_LAND_MVP / FREE_BUILDING_MVP for the per-land and per-building matrices.
- New lib/Gen4Slice.lua: coroutine land builds. Slice.landStep(state, Budget, warm, kind, ground, land, buildLand) keeps one job in flight per module and drops it if unstepped for 0.5 s on another land. Slice.check() yields at checkpoints. Slice.newMesh converts table verts into a ByteData in chunks (FFI) inside a job.
- Gen4Rocks, Gen4Fence, Gen4Bump and Gen4Water now build through it, with check() in boulder / readShape, buildBay / buildPost / readShape, pile / readShape and emit / shapeTriangles, and newMesh() for their final mesh.

## 2026-10-28 — Load throttling in drawFree (uncommitted, untested)
- The overlay showed logging is negligible (0-16 lines/s, at most 2.2 ms/s), so debug logs are not the stutter.
- Remaining hitches: "g4 drawFree" of 60-150 ms, sometimes with -50 MB GC and sometimes with g4 liveModel/modelFor ~27 ms (a new land loading). Gen4Model.new builds one Lua table per vertex (eager, not lazy), so a land load means tens of thousands of tables plus GC debt.
- src/render/Gen4Ground.lua: Gen4Ground.FREE_LOADS_PER_FRAME = 2 (0 = off). While drawFree runs, liveModel() and building() build at most 2 new models per frame; a deferred one returns nil without caching the miss and appears a frame later. Not applied with drawAllChunks or forceField3d. The freeLoads / freeLoadAllowed locals sit above Gen4Ground:building so both functions can see them.
- An idea not done (large refactor): an FFI vertex path in Gen4Model.new. The vertex tables are reused for billboard pivots, the back-wall cap and grass.

## 2026-10-28 — GC owned by the pacer (uncommitted, untested)
- Desktop shot after the load throttle: 58 fps but 21 frames > 50 ms in 10 s; the hitch was 66 ms with "g4 drawFree 58" and no liveModel/modelFor or GC drop listed, so the time was untimed self time in drawFree. Most likely LuaJIT's allocation-driven GC steps (295 MB heap) running inside whatever code allocates. The log's Gen4Budget burst also showed trees max 52.8 ms.
- Gen4Bridge.lua: the pacer now owns the collector while a native world draws (Bridge.GC_OWN = true). After each pacer run it calls collectgarbage("stop"). A global collectgarbage wrapper (state shared in _G.__terrariumGc) re-stops it after any step/restart/collect, such as the engine's per-update step in src/core/Game.lua, and hands GC back ("restart") once the world has not been drawn for Bridge.GC_RELEASE (1 s). The budget grows x3 when the heap passes 2x the post-cycle size and x6 past 3x.
- Diagnostic meaning: if hitches now show up as "fx gc pacer", the cost is one atomic GC step (unbounded) and the fix is a smaller heap; if they stay in "g4 drawFree", it is not GC, and drawFree needs finer sections.

## 2026-10-30 — PERFORMANCE perf-test rows (uncommitted, untested in game)
- Goal: find what makes mobile slow with Terrarium Advance: ground tile swaps, the sky, or mesh-building effects. Vertex fixes alone did not help.
- New lib/PerfTest.lua, three ModSetting rows in PERFORMANCE (keys perfTestTiles / perfTestSky / perfTestMesh):
  - TILE SWAP ON/OFF: Gen4Lawn.enabled + Gen4Sand.enabled (+ bridge "sand"/"lawn"). Gen 1-2: TerrainAtlas.withOverrides skips data/tile_overrides.lua stamps (next map load).
  - SKY FULL/FLAT/OFF (Gen 4/5): FLAT = Bridge.setEffect("sky", false) so only Sky.paint runs; OFF = Gen4Sky.enabled false (engine horizon).
  - MESH FX ON/OFF (Gen 4/5): Bridge.setEffect off for water, bump, trees, rocks, fence, flowers, lamps, grass; Gen4Hide keeps native cards.
- PerfTest.install wraps Gen4Ground.drawFree last (outermost) and applies only on change; it only re-enables effects it disabled itself. Installed at the end of installNativeWorldFx in main.lua.
- Lawn's modelFor texture tagging still runs while TILE SWAP is OFF (load-time only); the per-draw material merge is skipped.
- Syntax checked with lovec loadstring.
