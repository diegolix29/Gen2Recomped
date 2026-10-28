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
