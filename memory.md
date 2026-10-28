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
