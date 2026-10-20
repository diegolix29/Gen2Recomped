# Walker delivery and launcher background performance

Walker presents now materialize immediately in the source save: catches enter its PC, and items enter its bag. The current walking Pokemon determines the source game and save slot, including Watt Shop purchases when an older destination was selected. Returning Pokemon retain their original physical PC slot when it is free; sparse slots are selectable without shifting their neighbours.

Delivery loads only the destination ROM's extracted species, item, move, growth and storage records. Shared species/nature normalization matches normal DS game loading. Cartridge version, box shape, growth tables and nature tables are restored afterward, so delivery does not reset or contaminate a running launcher preview. Save validation adopts the destination storage shape before checking delivered slots.

Full bags retain remaining quantities in the save's delivery inbox. Full boxes retain the already-created Pokemon, including its identity, for retry. Unknown species remain queued. Rewards are copied before application and removed from the walker only after the destination save is written successfully. Failed writes preserve rewards and watts. Normal pending event distributions retain their existing game-load handling.

## Launcher backgrounds

Both animated game previews and custom video backgrounds render into a bounded cached canvas and composite into the launcher at its normal UI cadence. Background updates/rendering are capped at 30 FPS, or 15 FPS on NX. Canvas dimensions are at most 960 by 540, or 640 by 360 on NX, with DPI scale 1. Paused backgrounds reuse the last frame; replaced/stopped canvases are explicitly released. Video audio volume changes are applied only when the setting changes.

This reduces repeated background rendering, video frame upload and composition work. It does not add hardware video decoding: LOVE's native video decoder still runs in its own thread. No supplied custom OGV sample was available for a decoder performance measurement.

## Validation

- Native delivery checks used real extracted definitions from 13 imported games: Red, Gold, Silver, Crystal, Polished Crystal, Prism, FireRed, Emerald, Platinum, HeartGold, SoulSilver, Black and White.
- Synthetic isolated save slots verified source routing, sparse PC slots, radar/minigame presents, Watt Shop stale-target override, return placement, save validation, idempotence, partial stacks, full-PC identity preservation and failed-write retention. Player save files were not modified.
- Existing walker economy suite: 68 checks, zero failures.
- Background scheduling suite: 13 checks, including elapsed game time, canvas size, pause, release and restored render hooks.
- Native Emerald and HGSS previews loaded and rendered successfully into cached canvases. Each test recorded 90 UI draws and 7 game renders in a fast hidden-window run; these counts demonstrate caching, not a measured gameplay FPS gain. Captured images were inspected.
- Final runtime syntax check: 27 modified/new Lua modules. Emerald terrain/batching policy checks and existing performance-tier checks also passed during this round.

Runtime app source is updated in the workspace. The two latest mod modules are also installed in the primary AppData and G: mod folders. No packaged application/platform binary was rebuilt, and no public release was made. Switch sustained-play behaviour and real mobile/custom-video decoder costs remain unverified.

Installation encountered a full C: drive. One interrupted AppData module was immediately repaired and both installed modules were byte-verified against the workspace. Only generated binary meshes from an isolated Emerald benchmark profile were archived to G: and removed from that test profile; no player save data was removed. The C: drive still reports no free space and requires attention outside this patch.

## October 20 runner art and launcher touch fixes

Minigame reward species still come from the source ROM, while minigame presentation now chooses the highest-generation imported art available for each species. Runner actors request overworld sheets, never battle/Pokedex portraits. Missing overworld art uses the existing named placeholder. Walking-frame bounds are validated and quads are cached by image/frame to avoid allocating one every draw.

HGSS/BW personal records are numerically keyed and often omit dex. WalkerArt.roster now reads those national IDs, excluding extra personal-form rows after 493/649. This fixes a source roster that could collapse to just the walking Pokemon. Newly spawned runner enemies initialize yy immediately, so drawing between creation and their next physics update no longer performs arithmetic on nil.

The native runner fixture verifies distinct HGSS overworld sprites despite an Emerald presentation-source setting, all 493 HGSS and 649 BW species, immediate-spawn drawing, a captured image, and 15 simulated minutes of update/draw without a crash. Collision termination was disabled only in this endurance fixture to maintain coverage; gameplay collision rules are unchanged. The captured runner image was inspected. Existing minigame tests pass 124/124; focused art tests cover missing art, frame bounds and quad reuse.

Launcher touch controls now defer every selection to native touch release. Movement cancels the tap and scrolls the existing page/list/drawer region; fast swipes and multi-touch also cancel activation. Both Android and iOS use native touch callbacks and ignore duplicate synthesized mouse presses. Actual mouse input retains its existing path. Twenty-two gesture checks pass, including settings and slot rows on hosts without touch polling. Main.lua and these application modules must be included in rebuilt apps; the voxel mod ZIP cannot update them.
