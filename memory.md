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

## 2026-10-30 — ORAS context entry + RenderDump (uncommitted, untested in game)
- Status from the user: ORAS models + meshes + flames work for Gen 1-3 species. Gen 4/5 species' flames look wrong, and on a Gen 4 world some world layers draw in front of Gen 1-3 flames. Wanted next: ORAS move animations + effects, ORAS battle arenas (a new Terrarium battle next to the Colosseum one).
- Added the ORAS section to context.md. ORAS history: 7036fb1d, d72b0c41, c2c59576, b16462b7.
- New lib/RenderDump.lua (installed in main.lua after Gen4Bridge, global _G.__terrariumRenderDump). F12 polled from PokemonActors debugFrame and withRenderer. Report: live actors + groups, ORASActorCache.inspect(mod, dex, writePng) ROM breakdown (body/glow/skipped + reason, raw material struct and 0x200 bytes of params, effect textures as PNG), and ~60 ms trace of setCanvas/clear, Gen4Bridge passes (forces Bridge.profile on) and actor group draws.
- H3D materials now keep `at` / `paramsAt` raw offsets.
- Suspects for Gen 4/5 flames: textures in LA8 / ETC1A4 / RGBA formats are not GLOW_FORMATS (mesh skipped); colour comes from the name ("Fire"), so other names (or Chandelure's purple) get white/orange; shared effect textures missing from the species pack are skipped.
- Suspect for world layers over flames: glow groups do not write depth and the arena world is composited separately (Gen4WorldHost.renderPose copies colour), so later world passes can paint over them. Needs the trace.

## 2026-10-30 — First F12 dump: both flame bugs found and fixed (uncommitted, untested in game)
- Dump (Chimchar 390 + Charizard 6 on T02): Chimchar's flame textures are species-prefixed (pm0390_00_FireCoreA1 / FireStenA1, L4/L8) while Charizard's are shared (FireCoreA1). The "own prefix = body" rule made Chimchar's flames opaque BODY groups.
- Fix (ORASActorCache): effectTexture(prefix, tname, t) = intensity format AND (no prefix OR name has Fire/Flame/Sten/Glow). patchSize excludes those from height. Stamp oras-actor=7; a species on =6 runs needsGlowRebuild once on the next ORAS MODELS build: rebuilt if it has a prefixed flame texture, else just re-stamped. Restart after the build.
- Trace: over a native Gen 4/5 world the actors draw INSIDE drawFree, before every Gen4Bridge pass (water, sand, bump, trees, rocks, fence, flowers, lamps, glass, light, grass). Flames write no depth, so those passes painted over them.
- Fix (PokemonActors + main.lua): while Bridge.Ground.freeOpen, Actor:draw skips glow groups and queues {A, actor, matrix, vp, eye} in _G.__terrariumGlow; a Gen4Bridge.after hook (main.lua) calls GLOW.flush, which replays actor:draw(matrix, "glowOnly") inside withRenderer. Records older than 0.1 s are dropped; A.glowDefer = false turns it off. The F12 trace shows "glow-replay N".
- Not checked yet: battles (renderPose / renderBattleBody path) with these changes.

## 2026-10-30 — Overworld flames confirmed; ORAS battle roadmap
- The user confirmed the overworld fire works (Gen 4/5 prefixed flames + flames over Gen 4 world layers). Still uncommitted.
- Already there: ORASActorCache bakes idle (slot 0), physicalA-D (8-11), specialA-C (12-14), damage (16), faint (17), appear (3, flyers 6) as 13-pose vertex banks (MORPH_SLOTS 12). Move effects in battles are the Colosseum (GC) Waza pipeline (WazaHandlers, WazaSequenceRuntime, MoveFXVM, WazaCamera*).
- Roadmap, in order:
  1. Animations: label every ORAS motion slot from the ROM (slots 1-2, 4-5, 7, 15, 18+ unbaked); bake + wire the useful ones (idle variants, intro/roar, status move, hit variants); fix choppiness (13 poses per clip; denser sampling or GPU skinning); keep attachment bones (mouth, hands, tail) in the cache for effects; sync the hit frame with damage.
  2. Move effects: probe the dump for the ORAS move-effect archives (format unknown yet); decode effect models (H3D) and particles (new format); play them through the existing Waza host (lanes, timing, camera); start with a few moves (Ember, Tackle, Water Gun, Thunderbolt); keep Colosseum FX as fallback.
  3. Arenas: probe the battle-field archives, decode with H3D, add a new Terrarium battle style next to Colosseum. Could move before step 2 (reuses the working decoder).

## 2026-10-30 — Battle roadmap step 1: ORAS motions (uncommitted, untested in game)
- Surveyed all 721 species' battle motion slots offline (slot meaning in context.md ORAS section). Slot 25 = cry (jaw only), 18 = material-only loop (fire species: likely flame flicker, for the effects step), 3-5 = full send-out.
- ORASActorCache stamp oras-actor=8 (every species rebuilds): appear = chain 3+4+5 (else 6); new cry (slot 25 over the idle loop) and idleB (slot 1); one-shot banks paged at 3 source frames per pose; joint positions per bone baked into every page and the base bank (groundwork for effect attachment points). The =6 -> =7 re-stamp shortcut (needsGlowRebuild) was removed.
- H3D.poser keeps the bind value when a sample returns nil (needed by chained motions).
- PokemonActors: cry plays after the send-out; idleB every 3-5 idle loops (not while hidden by Fly/Dig, not in info viewers); idle() does not cut appear/cry/idleB; idleB prewarmed. A.orasExtras = false disables both.
- Offline build of Charmander/Charizard/Pikachu: OK; Charizard 13 MB (was 6.7 MB); send-out and page joins continuous in joint tracks.
- Not done in step 1 yet: hit-frame sync (no ORAS timing data found yet; SESD parts may hold it), bodyMap (named attachment points) from boneNames for effects.

## 2026-10-30 — PACK CACHE fixed; ORAS compact banks (uncommitted, untested in game)
- User confirmed the step-1 ORAS animations look right in game.
- PACK CACHE (lib/CacheArchive.lua) never packed anything: (1) addRuntimeSidecars queued <x>_runtime_v1/base.lua for every .lua, including its own sidecars -> endless recursion, stack overflow, job error thrown away (menu stayed LOOSE FILES); (2) kindFor/pinnedLoose used find("^prefix",1,true) -- plain find takes "^" literally, so no path was ever a cache path: packed files could never have been read back. Fixed with a _runtime_v1 guard and startsWith(); the queue now comes from mod.cache:list (falls back to the manifest walk if the listing is empty), which also packs runtime action sidecars; the job error is kept (status().error, build/cache_archive_error.txt).
- Offline test against the user's real cache (deletes faked in memory): 57 species 2.33 GiB -> 288 MiB, 5/5 readEntry round trips byte-identical.
- ORAS compact banks ("OQ16", see context.md): 1259 real banks 139.5 MB -> 39.0 MB (28%), max error 0.00048 units. No stamp bump; existing species convert in place on the next ORAS MODELS run.

## 2026-10-30 — Packed cache re-extracted on restart: three causes fixed (uncommitted, untested in game)
- User packed (cbe_cache_archive: 395 pokemon + 264 movefx units) and the next start rebuilt the MoveFX cache (build/state.txt current_stage=movefx; 1144 cache/movefx files re-extracted).
- Cause 1: main.lua ran BuildPipeline.run (startup cache check) before CacheArchive was loaded, so every packed file read as missing. Fix: CacheArchive is created right before BuildPipeline (env {mod, WorkBudget}, earlyArchiveEnv); installMainUI reuses that instance, sets env.GeneratedAssets and calls install().
- Cause 2: PokemonExtractor.isCached reads cache/pokemon/<dex>[/shiny]/model_cache.lua + rev.txt through mod.cache directly; they had been packed (1185 files), so every species would re-extract on encounter. Fix: pinnedLoose keeps model_cache.lua / rev.txt / extract.txt loose; A.restorePinned() (run once at the early load, marker build/cache_archive_pinned_v2.complete) writes them back from the units by reading unit headers only (offline on the real archive: 1185 restored in 2 s).
- Cause 3: the in-game pack used the manifest-walk fallback (Mewtwo: 48 of ~1000 files packed), so mod.cache:list did not deliver there. Fix: listKeys walks mod.cache.storage.root with its fs directly (fallback mod.cache:list); report in build/cache_archive_<kind>_report.txt. Re-packing also deletes loose copies identical to their archived entry (the re-extracted duplicates).

## 2026-10-30 — PACK CACHE second pass destroyed units: writer fixed + repair (uncommitted, untested in game)
- After the second pack nothing showed in game (log: "dex 6 native action damage cache cache/pokemon/6/actions/damage.lua failed: not_found").
- Cause (pre-existing): writeUnit opened the unit with "w" and wrote only the new batch, so packing a unit that already existed erased the first pack's entries (their loose originals already deleted). Read-only scan of the user's archive: pokemon 21645 of 194317 index entries missing, in all 365 units; movefx 2765 missing in 56 units.
- Fix: writeUnit keeps the existing unit's records it does not replace (unitRecords). A.repairLostEntries() (once at the early load, marker build/cache_archive_repair_v1.complete) drops every unit that lacks an indexed entry (unit file + index rows), deletes the loose cache/pokemon/<dex>[/shiny]/rev.txt or cache/movefx/<stem>/effect.lua so the species/move is extracted again from the disc, and deletes build/hard_cache_registry_v1.lua (stale positive sizes). Scratch-save test: pack -> add -> pack keeps both; repair drops the broken unit and its rev.txt.
- Consequence for the user: every Colosseum species re-extracts on first use (or via Hard Cache Save), the 56 moves via the startup MoveFX repair; then PACK CACHE again.

## 2026-10-31 — CacheArchive: direct reads + auto-pack (uncommitted, untested in game)
- User log after repair + Hard Cache Save + repack: no rebuild ("Colosseum source build: READY"), species load from the archive. Freezes came from readEntry unpacking a whole species unit loose (~150 MB writes; hot log had 1.5 GB of copies).
- readEntry now reads one entry: per-unit header table (unitTables, File:seek) + one open unit file; no loose writes. writeUnit / repair close and forget the unit table.
- Auto-pack: A.markDirty(kind,key) from PokemonActors.extractSource (after extractSpecies) and from every GeneratedAssets.write under cache/pokemon|movefx (hook in A.install); A.tick() (BattleRuntime overworld frames, outside battle) starts a background packKind(kind, keys) for units idle 20 s (AUTO_SETTLE). main.lua after BuildPipeline.run: scanLoose("movefx") + dropHotCopies() (old hot units re-checked, equal loose copies deleted). A.autoPack = false disables.
- packKind: loose file already archived -> deleted if equal, packed again (replacing it in the unit) if different; loose deleted only if size+modtime unchanged since read. zlib level 6 (was 9).
- Offline test (scratch save): auto-pack after settle, 30/30 direct reads identical with 0 writes, re-extracted file replaces the archived one.
- ORAS: user said leave ORAS alone for now. oras/ folder is missing from modstorage (deleted outside our code, before 2026-10-31 12:01); needs ORAS MODELS rebuild later.
- 2026-10-31 follow-up: model library (BattleCache "Preparation paused", "missing or damaged model texture: cache/pokemon/5/tex_01.rgba", DISK CACHE 8/386) -- GeneratedAssets.revalidateInfo asks mod.cache directly, so packed files read as missing. A.install now wraps revalidateInfo to fall back to A.infoEntry (archived size).

## 2026-10-31 — Colosseum cache packing confirmed; next: ORAS
- User confirmed the Colosseum packed cache works in game (loads from cbe_cache_archive, model library prepares after the revalidateInfo fix). Still uncommitted.
- NEXT: back to ORAS. Open items: the oras/ folder is gone from modstorage (rebuild with OPTIONS -> ORAS MODELS; new builds write OQ16 compact banks), ORAS cache packing (same idea as CacheArchive, ORAS ~9 GB with the new animations), then the battle roadmap (step 1 leftovers: hit sync, named attachment points; step 2 move effects; step 3 arenas).

## 2026-10-31 — ORAS rebuild converted nothing: compact banks fixed (uncommitted, untested in game)
- User ran ORAS MODELS on the old float cache: "0 built, 721 skipped" in 8 s. On disk every species got q16.txt ("oras-q16=1") but all 82169 banks were still float (7.13 GiB in modstorage/DRAMATIC_SHAPE/oras/pokemon, files stored as <key>.bin).
- Cause: compactSpecies listed banks with mod.cache:list, which comes back empty in game (same as CacheArchive), converted nothing and still wrote the marker.
- Fix (ORASActorCache): listKeys walks mod.cache.storage.root with its fs (fallback mod.cache:list); compactSpecies writes the marker only when banks were listed and returns seen, converted; the marker is now Q16_MARK "oras-q16=2" (=1 no longer counts, so all 721 convert on the next ORAS MODELS run). Log: "banks compacted (converted of seen)".
- Offline lovec test on copies of dex 1, 6, 150 with mod.cache:list faked empty: 250/250 banks converted, 24.9 -> 7.4 MB (30%), decodeQ16 round trip max error 0.0026 units. Expect the ORAS banks ~7.1 GiB -> ~2.1 GiB.
- Confirmed by the user + on disk: second ORAS MODELS run converted all 721 (build.txt: 721 "banks compacted", 0 failed; all q16.txt = "oras-q16=2"). oras/pokemon is now 3.5 GiB total (was ~9).
- The game log stopped at dex 20 because src/core/Logger.lua drops a line shape (numbers ignored) after 20 repeats. ORASModels now logs only failures + "N / 721 species" every 50; per-species lines stay in oras/build.txt.

## 2026-10-31 — ORAS battle step 1 leftovers: attachment points + hit sync (uncommitted, untested in game)
- Named attachment points: new lib/ORASBodyMap.lua builds the 16-slot body map (origin, mouth, chest, tail, eyes, hands, feet, center...) from the cached boneNames (one naming scheme across all 721: Origin, Waist, SpineN, NeckN, Head, EndHead, Jaw, EndJaw, Upper/LowerBeak, LHand, Tail1..EndTailN, LFoot...). An entry is a 0-based bone index or a pair {a,b} = midpoint (mouth = Jaw+EndJaw, else beak, else Head+EndHead; center = Waist+chest). PokemonActors: scene.boneNames kept, Actor:bodyMap() returns the ORAS map for sc.source=="ORAS" (module loaded via V.mod:read, no V.require there), Actor:attachment() resolves pairs. No rebuild needed. Offline over 721: no missing origin/mouth/chest/center; tail missing on 248, hands 125, feet ~180 (fall back to chest in moveFxWorldPoint); all indexes have joints.
- Hit sync: ORAS has no contact timing, so Actor:orasContactWait() measures it from the physical bank's cached joints: pose where body-core joints (Waist/Hips/Spine*/Neck*/Head/Jaw/hands/forearms/beak) reach furthest +Z; accepted if lunge >= 8% of bounds height and phase 15-85%, else 45%. CurrentSpriteModels damage dispatch passes holdFor (capped 1.2 s) to the target's Actor:hit, which parks it in heldHit; Actor:update releases it via beginHit (skips the duplicate filter); faint/recall wait behind a held hit; resets clear it. Special attacks unchanged. Offline: 642/683 physicalA measured, 41 default (Charizard 0.46 s of 2.2, Pikachu 1.07 s of 1.83).
- Not covered: doubles (lib/doubles) damage path; HP bar may drop before the delayed flinch.
