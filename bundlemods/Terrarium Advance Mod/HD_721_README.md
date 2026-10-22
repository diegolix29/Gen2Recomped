# HD sprites: full 721 + Mega forms (patch)

Unzip over the mod folder (keeps the same paths). Files:

| File | Change |
| --- | --- |
| `tools/fetch_pp_sprites.py` | NEW. Downloads the Project Pokemon GIFs and names them for the importer |
| `tools/import_hd_pokemon.py` | cap 706 -> 721, form suffixes (`-mega`, `-megax`, `-primal`), `--fit-height`, `--extra` |
| `tools/hd_pokemon_to_meta.py` | NEW. Builds a `hd_sheet_meta_*.lua` table from `data/hd_pokemon.lua` |
| `data/hd_sheet_meta_gen6.lua` | NEW. Geometry for dex 650-706 sheets that the pack already has (the game had none, so they would load as one static frame) |
| `lib/HDPokemonSheets.lua` | `MAX_DEX` 649 -> 721, Gen 6 name table, loads the gen6 + extra meta files, Mega/Primal form keys |
| `lib/HDSheetInstaller.lua` | keeps the old "skip the 2nd pack" threshold now that the cap moved |

## Run it (on your PC, in the mod folder; Python 3 + Pillow)

    python tools/fetch_pp_sprites.py --out pp_gifs --mod .
    python tools/import_hd_pokemon.py pp_gifs --target . --extra --fit-height

* `--mod .` = gap-fill mode: only species/forms the mod has no sprite for (6, 155-157, 651, 698, 707-721 and all Megas/Primals).
  Add `--all` to download everything instead. `--forms all` also fetches Alolan etc. `--list-only` shows the plan.
* Sheets go to `assets/hd-pokemon/`, geometry to `data/hd_sheet_meta_extra.lua` (re-runs accumulate).
* Check `pp_gifs/fetch_report.txt` for names the site did not have. Re-running resumes.
* Sprites already installed by the HD SHEETS pack win over files in `assets/hd-pokemon/` (same stem), which is why gap-fill is the default.

## Limits
* Project Pokemon only supplies FRONT sprites. New species have no back sprite, so the player's side stays native art.
* The game only picks a Mega sheet if the engine reports the form (`mega`, `Mega X`, `mega-y`, `primal`...). Nothing else is needed on the art side.
* Not tested against the real site (blocked from the build sandbox); tested end to end against a local imitation.
