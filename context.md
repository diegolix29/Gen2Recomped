# Repository Context — gen2rec (Gen2Recomped)

## Overview
- Native LÖVE2D (Lua) recreation of Pokémon games, decoded from a player-supplied ROM (no ROM shipped, no emulation). Fork of bryanthaboi/gen1recomp, by UNDERdecodedHD.
- Started as Gold/Silver/Crystal on the Gen 1 engine; now also runs FireRed/Emerald (Gen 3, Alpha), Platinum/HGSS (Gen 4, Pre-alpha), Black/White (Gen 5, Pre-alpha), Polished Crystal and Prism. Also Monster Walker, Map Editor, Save Editor, translation, cloud saves, DS dual-screen, touch.
- Supported dumps are pinned by SHA-1 (table in README.md, details in docs/rom-revisions.md).
- License: source-available "Gen2Recomped License" (LICENSE.md), no redistribution / commercial use.

## Git
- Remote: `G2` = https://github.com/diegolix29/Gen2Recomped (there is no `origin`).
- Main branch: `main`. Active branch (2026-10-28): `gen5-fixes`, tip 4512eefb "Rebase new emerald voxels"; it sits 2 commits past main's 8d5b4387 (fff10edc, 4512eefb).
- Many old feature branches (COLO-*, FIX-BUILDINGS, Fixing-Carpet, ...).

## Architecture
- Entry: `conf.lua` (save identity "Gen2Recomp" on desktop, "pokemon-love2d" on mobile; `--editor` / `--developer` flags or env POKEPORT_EDITOR / POKEPORT_DEV) then `main.lua`. `manifest.lua` is large (~336 KB).
- Import: `src/import/RomImporter.lua` + `RomExtractor.lua` verify the ROM and write a private cache (data/generated/*.lua, assets/generated/**). Gameplay reads only the cache.
- `src/` areas: audio, battle (Gen1–Gen4 battle/anim modules), cloud, contest, core (Game, Data, ChipAudio, FixedStep 60 Hz, StateStack, SaveData), dev, import, inventory, link (lua-enet P2P), mods, net, pokemon, pokewalker, render, save_convert, script (ScriptRunner coroutines + Commands), translation, ui, update, world (Map/Player/NPC/Warp/Encounter plus per-game modules such as Gen5*.lua).
- Map scripts are hand-ported in `data/scripts/<map>.lua`.
- Mods: `mods/`, bundled ones in `bundlemods/` (BATTLE_CINEMATICS, Kanto-in-Motion, red_3d_player, wild_skies, ...); see docs/modding.md.
- Docs: `docs/architecture.md` plus many per-feature parity notes (emerald-*, gen2-*, platinum-*, hgss-bw-import.md, emerald-voxel-performance.md).
- Misc folders: `Claude outputs/` (earlier AI notes), `cmd runs/`, `Python/`, `ports/`, `mobile/`.

## Dependencies
- LÖVE 12.0-development nightly (pinned in scripts/love12-runtime.json); LuaJIT / Lua 5.1 semantics (CI also uses lua5.4).
- Python + Pillow for the developer data path `tools/build_data.py`.

## Build / Run / Test
- Windows dev launch: `Play-Windows.bat` (sets POKEPORT_DEV=1 and runs scripts/bootstrap.ps1). Setup: scripts/setup.ps1; run: scripts/run.ps1 (prefers lovec.exe for console output).
- Packaged exe build: scripts/build-windows-exe-script.ps1 (output Gen2Recomped.exe in the repo root). Other targets: build_android, build_ios, build_msix, build_switch, build_xbox_uwp, build_linux_arm64, build-rg34xxsp.sh.
- Tests: `scripts/test.sh` (tiers T1–T5; `--quick`, `--bless`). Lint: scripts/lint.sh (.luacheckrc).

## Current State / Open Work
- Branch name suggests Gen 5 (Black/White) fixes; recent commits are about Emerald voxels and load lag / perf settings.

## Colosseum cache packing (lib/CacheArchive.lua, PACK CACHE menu)
- Units: <save>/cbe_cache_archive/{pokemon,movefx}/<key>.cbeu (zlib per file), index cache/archive_v1/<kind>.lua, readEntry rehydrates a whole unit loose (1.5 GB hot cap). Must be loaded BEFORE BuildPipeline.run (main.lua creates it early). Identity files that code reads via mod.cache directly stay loose (pinnedLoose): manifests, movefx index/coverage, per-species model_cache.lua / rev.txt / extract.txt.

## ORAS import (Terrarium Advance Mod, bundlemods/Terrarium Advance Mod/)
- Player-supplied decrypted Omega Ruby / Alpha Sapphire dump, launcher import id `pokemon_oras` (file pokemon_oras.3ds), read in slices by lib/N3DSRom.lua. Built from OPTIONS -> ORAS MODELS (lib/ORASModels.lua); lib/ORASProbe.lua writes survey reports (mod cache oras/probe.txt, oras/export.txt).
- Models: GARC a/0/0/8 (lib/GARC.lua). Member 0 = index (4 bytes per species: u16 first form, u8 forms, u8 flags); form f block starts at member 2 + 8f. Block slots: +1 model BCH, +3 textures, +4 shiny textures, +6 battle motions (GF1Motion), +2 face/eye anim. Gen 6 model names are internal numbers, not dex.
- Decode: lib/BCH.lua (relocate), lib/H3D.lua (models, materials, bones, skinning), lib/PICA.lua (textures), lib/GF1Motion.lua. lib/ORASActorCache.lua bakes species into mod cache oras/pokemon/<dex>/ (rev.txt stamp "oras-actor=8"; bump C.STAMP on layout change; cache ~3.4 GB at =7, about twice that with paged actions). lib/ORASRuntime.lua installs PokemonActors without the Colosseum runtime. Drawn by lib/PokemonActors.lua (sc.source == "ORAS").
- Flames: meshes whose texture is not the species' own (pmNNNN prefix) and is an intensity format (L8/A8/LA4/L4/A4) become GLOW groups: colour hardcoded by texture name (glowColor, "Fire"/"Core"), drawn additive + unlit, no depth write, after the body. Other non-own meshes are skipped. H3D does not decode material blend/stencil/constant colours yet.
- Battle motion pack (block +6, part 1) has 28 slots: 0 idle A, 1 idle B, 2 idle C, 3/4/5 send-out drop/land/recover, 6 flyer send-out, 8-11 physical, 12-15 special, 16 damage, 17 faint, 18 material-only loop (fire species, Zygarde), 25 cry (jaw only, 70 frames). Part 2 = 18 per-motion bounding boxes (6 floats each); parts 3.. = per-motion BCH material/visibility anims; SESD parts = sound timing. Block +7 (PK) is a 36-slot non-battle pack (Amie/refresh).
- Baked actions: physicalA-D, specialA-C, damage, faint, appear (chain 3+4+5, else 6), cry (25 layered over idle), idleB (1). One-shot banks are dense pages (ACTION_FRAMES_PER_SLOT = 3 source frames per pose) and carry jointPositions/jointFrames for every model bone (base.lua has boneNames). PokemonActors plays cry after appear and idleB every 3-5 idle loops (A.orasExtras = false turns both off).
- Offline probe: a lovec harness can open the dump directly (fake mod.imports over io.open on <save dir>/bundlemods/Terrarium Advance Mod/pokemon_oras.3ds) and call ORASActorCache.buildSpecies with a fake mod.cache.
- Compact banks: ORASActorCache writes every pose bank as "OQ16" (int16, per-file scales, slot deltas wrapped to 16 bits, zlib, padded to a multiple of 176 bytes so size checks pass; same .f32 names). RuntimeMeshCache.meshFromBytes decodes it (decodeQ16); plain float banks still load. About 28% of the float size, max error ~0.0005 units. Species already built are converted in place on the next ORAS MODELS run (marker oras/pokemon/<dex>/q16.txt; C.compactBanks = false skips).
- Debug keys in battle (PokemonActors): F9 overlay, F5 isolate group, F6 skin fix, F10 decode mode, F7/F8 scale trim, F12 RenderDump (lib/RenderDump.lua) -> <save dir>/terrarium_dumps/<time>/report.txt + effect texture PNGs.
