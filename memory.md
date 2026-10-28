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
