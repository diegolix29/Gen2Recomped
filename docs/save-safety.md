# Save safety: how a save is kept, and how to get one back

Reported from play on Android, in HeartGold: "it kinda froze after encountering
a Pidgey and now my save is gone". This page lists every way a save could be
lost, what now prevents each one, and how a player gets a save back.

Code: `src/core/SaveSafety.lua` (write, keep, find) and `src/core/SaveData.lua`
(slots, `commitSave`, `load`, the restore API). The check is
`tools/save_safety_check` (see "Checking it" below).

## How a save is written now

Every progress write goes through `SaveData.commitSave` and then
`SaveSafety.atomicWrite`. That covers the in-game SAVE, scripted saves,
the launcher's import, the Pokewalker, events and cloud sync.

1. The new bytes go to `<slot>.lua.tmp`. They are read back and compared byte
   for byte. If the disk is full or the write was cut short, the main file has
   not been touched.
2. The previous main file goes to `<slot>.lua.bak`, but only if it decodes. A
   main file that does not decode is kept as `<slot>.lua.corrupt-<stamp>`. It is
   never rotated into `.bak` and never simply written over.
3. `.tmp` is renamed over the main file. On Windows, rename cannot replace an
   existing file, so the old file is removed first. The verified `.tmp` is the
   copy for that instant.
4. Snapshots are named `<slot>.lua.bak-YYYYmmdd-HHMMSS[-tag]`:
   - A rolling copy is taken at most once every 10 minutes. The newest 8 are kept.
   - Tagged copies are taken at risky moments. The newest 16 are kept:
     - `replaced`: a different playthrough (another trainer name or ID) is about to be written over this one, as in NEW GAME on a used slot.
     - `external`: the file changed on disk while the game had it open.
     - `orphan`: the main file was missing while `.tmp` or `.bak` still held a save.
     - `prerestore`: the restore tool is about to replace the file.
   - `<slot>.lua.backups` indexes the snapshots, for file systems that cannot list a folder.
5. A table without a `player` table is never written. F1 quick-save only works
   in free roam, not mid-battle or under a menu.

`options.lua` is written the same way, with `options.lua.bak`. It holds every
game's save-slot registry. So do `pokewalker.lua`, the Walker's state with the
walking Pokemon, and `cloud_sync*.lua`.

## How a save is found

`SaveSafety.loadBest` tries these copies in order:

1. The main file. A newer `.tmp` wins if it has more play time.
2. `.tmp`
3. `.bak`
4. The snapshots, newest first.
5. The Pokewalker's pre-write backups.
6. The cloud sync's local backups.
7. The same slot in another storage location (read only).

A copy only counts when it decodes and has a `player` or `party` table.

- **Before the title screen asks:** `SaveData.saveFilename` and
  `saveFileExists` restore a missing or unreadable main file from the best copy.
  Every CONTINUE gate calls one of them. So no menu offers only NEW GAME over a
  recoverable save. The load report says which copy was used: "Save recovered
  from the .bak-… backup copy".
- **A lost registry:** if `options.lua` is lost or rolled back, slot files on
  disk that the registry no longer lists are registered again on the next
  launch. New slot IDs never reuse a file left on disk. That includes the
  legacy-to-slot migration, which used to write `slot1` blindly.
- **An unreadable slot:** a slot whose files exist but none decode is shown in
  the launcher as `SAVE NEEDS RESTORE` with "save unreadable - Tools > Restore a
  Save". It is not shown as an empty NEW GAME slot. One bad slot can no longer
  break the whole list.
- **Delete is not erase:** Delete moves the slot to `saves/<game>/deleted/`.

## Every loss path found, and its fix

| Path | Was | Now |
|---|---|---|
| `SaveData.save` / `writeSlot` | Copied main to `.bak` without checking it. A truncated main overwrote the only good `.bak`. Remove, then write, without verifying. | Atomic write. `.bak` only takes a good copy. A bad main is kept as `.corrupt-*`. Snapshots. |
| `SaveData.load` | `.tmp`, then `.bak`, then nothing. An unreadable save looked like no save. | Every copy, in the order above. The main file is put back. |
| Title CONTINUE gates (`love.filesystem.getInfo(saveFilename)`) | A missing main with a good `.bak` showed NEW GAME only. The next save rotated the `.bak` away. | `saveFilename` restores the main file first. `orphan` snapshot on the next write. |
| `saveOptions` | Truncate and write. A cut-short `options.lua` reset the slot registry, so every slot vanished. | Atomic, with `.bak`. Load falls back to `.tmp` and `.bak`. Orphaned slot files are registered again. |
| `tryMigrateLegacy` / `createSlot` | Could pick an ID whose file was still on disk, and write over it. | `freeSlotId` skips every ID with a file. |
| `listSlots` | An undecodable slot showed as `NEW GAME` / `empty slot`. One throwing summary hid every slot. | `unreadable = true`, per-slot `pcall`, and a recovered summary when a backup holds the save. |
| `deleteSlot` | Removed main, `.bak` and `.tmp`. | Moves them to `saves/<game>/deleted/`. The restore tool can bring them back. |
| NEW GAME on a used slot (Gen 4 skips the cartridge's overwrite block) | The first save replaced the old playthrough, and the second rotated it out of `.bak`. | `replaced` snapshot, kept apart from the rolling ones. |
| Pokewalker / events writing while a game in another window has the slot | The game's next save dropped the walk's return, catches, items and events. A returned Pokemon was lost. | `.open` marker: the walker refuses that slot. If the file changed anyway, the game's save keeps an `external` snapshot and merges the inbox and events (`SaveSafety.mergeWalker`). |
| `pokewalker.lua` (written by the in-game passive Watts tick, and on focus loss when Android may kill the app) | Truncate and write. A cut-short file reset the Walker, and the walking Pokemon, already out of its box, was gone. | Atomic, with `.bak`. Load falls back to `.tmp` and `.bak`. |
| Cloud sync | An undecodable local file counted as "changed" and was uploaded over the cloud copy. An empty or partial cloud copy replaced the local save. An older branch from another device replaced a further-played local save. The state file was not atomic. | Undecodable local files are refused. A cloud copy that is not a save counts as missing. A less-played cloud copy comes down as its own slot. Atomic state file. |
| Storage location changes: portable on or off, fused vs unfused, old identity, Android volume or internal fallback | The save looked gone. | `SaveData.otherLocations()` is searched read-only when nothing local survives. A copy found there is copied into the current folder. |
| F1 quick-save mid-battle or during a freeze | Wrote a half-changed state. | Only from free roam. |

The game itself never writes the save slot except through `Game:writeSave`.
That is called by the SAVE menu, scripts and F1, and by the gen2online mod's
scheduler when that mod is enabled. The Walker code that runs in-game
(WalkerEconomy's tick, focus and quit flushes) writes only `pokewalker.lua`.
`WalkerInbox.apply` changes only the in-memory save on load.

## Restoring a save (players)

In the launcher, go to **Tools → Restore a Save** and choose the game.

- **To restore a slot:** choose the slot to see every copy of it, newest first.
  Each copy shows its date and what is in it (name, badges, play time,
  caught), whether it reads as a save, and where it came from. Click a copy,
  then click again to restore it. The current file is snapshotted first, so a
  restore can be undone from the same list.
- **Deleted slots:** these are listed under the game's slots. Click twice to
  bring one back as a new slot.

Most losses need nothing at all: the game restores from the best copy on its
own and says so when the save loads.

## Where the files are

`<save dir>/saves/<game>/` holds `slotN.lua`, `.tmp`, `.bak`, `.bak-*`, `.corrupt-*`, `.backups`, `.open` and `deleted/`. Other backups are in `<save dir>/pokewalker_backups/<game>/` and `<save dir>/cloud_backups/<game>/`.

| Platform | Save dir |
|---|---|
| Windows (packaged) | `%APPDATA%\Gen2Recomp\` |
| Windows (`love .` / unfused) | `%APPDATA%\LOVE\Gen2Recomp\` |
| Portable install (`portable.txt` beside the exe) | the game folder |
| Linux | `~/.local/share/love/Gen2Recomp/` (unfused) or `~/.local/share/Gen2Recomp/` |
| macOS | `~/Library/Application Support/LOVE/Gen2Recomp/` |
| Android | `Android/data/<package>/files/save/pokemon-love2d/` on the phone storage. With a USB cable it can be reached from a PC; Android 11+ file managers cannot open it. |
| iOS | the app's Documents/Application Support container (`save/pokemon-love2d`), reachable through Finder/iTunes file sharing |

The "game data folder" setting moves only the ROM cache. Saves never move with
it.

## Checking it

```
APPDATA=G:/Gen2Recomped/scratch_claude/save_safety/appdata \
ROOT="G:/Github Desktop/0.7.0/Gen2Recomped" \
  "C:/Program Files/LOVE/lovec.exe" tools/save_safety_check
```

The check uses its own identity (`Gen2Recomp_savesafetycheck`) and refuses to
run anywhere else. It covers:

- a truncated main file, an empty one, a `.tmp` from before and after the swap
- `.bak` rotation over a bad main file
- NEW GAME over a save
- a missing main file with only snapshots
- an undecodable slot
- a lost and a truncated `options.lua`
- a Walker write while the game is open (refusal, then merge)
- cloud copies that are older, empty, or an undecodable local file
- delete and undelete, and restore and undo
- a cut-short `pokewalker.lua`
- another storage location
- a disk that cuts writes short
- a save table with no player

It reports 47 checks, 0 failed.
