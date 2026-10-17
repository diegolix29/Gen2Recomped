# The next-gen Pokéwalker

A full-screen app in the launcher's sidebar (**Pokéwalker**, under Games). It works with every game: you take a Pokémon out of any imported game's PC, walk it with your phone's steps, and send it home with what it found.

## Modules

| File | What it is |
| --- | --- |
| `src/pokewalker/Walker.lua` | The rules and the state. The state is `pokewalker.lua` in the save directory. |
| `src/pokewalker/WalkerRoutes.lua` | The 27 HGSS courses: watts, National Dex, types, six encounters, ten items. Sourced from pokemondb and serebii, which agree on all 162 encounters. Four item rows are marked UNCERTAIN. |
| `src/pokewalker/WalkerCourses.lua` | Fills a course from the Pokémon's own game. Out-of-range species are swapped for a same-primary-type, nearest-BST, non-legendary species, with no repeats on a course. Species facts are cached in `pokewalker_species.lua`. |
| `src/pokewalker/WalkerLink.lua` | The launcher side. **Send** lifts the Pokémon's own table out of a save's PC box. **Return / Send presents** writes `save.walkerInbox`. Every save it touches is copied to `pokewalker_backups/`. |
| `src/pokewalker/WalkerInbox.lua` | Runs in `Game:restoreSave`, with the game's data loaded. It levels the returned Pokémon and places catches and items (see "Returning home"). |
| `src/pokewalker/WalkerSteps.lua` | Reads Android's step counter (see "Steps"). `STEP_DEBUG=n` credits n steps once, for desktop tests. |
| `src/pokewalker/WalkerArt.lua` | The Pokémon pictures (see "Art"). |
| `src/ui/PokewalkerScreen.lua` | The app. |

## Rules carried over from the original

From Serebii's Pokéwalker page and pokemondb:

- 20 steps earn 1 W.
- Courses unlock by lifetime watts: 0 / 0 / 50 / 200 … 100000. Hoenn Field onward needs the National Dex; the last seven courses are event-only.
- Groups A, B and C are drawn when you send a Pokémon. A type advantage cuts their step thresholds by 25%.
- **Poké Radar** costs 10 W. You search 4 bushes; the "!" count hints the group.
  - Battles run 4 bars against 4. Choose Attack, Evade or Catch.
  - The wild Pokémon flees at 0. If your Pokémon faints you lose up to 10 W.
  - You can hold 3 catches, swapping when full.
- **Dowsing** costs 3 W: 6 bushes, 2 tries, with close/far hints. You can hold 3 items.
- A walking Pokémon can find watts or an item. Higher friendship gives bigger finds.
- A walk is worth at most one level.
- The 7-day step history appears on the Trainer Card.

## Port choices (estimates, not original data)

- Friendship rises 1 point per 500 steps.
- A find is rolled every 100 steps.
- The radar's group weights are 1 / 3 / 6.
- Battle odds are tuned by hand.
- Event courses have no unlock path yet.

## Returning home

`WalkerInbox` does the following when the game loads the save:

- The returned Pokémon gains its walk's steps as EXP, capped at the next level. Its stats are recalculated as Rare Candy does. It goes back into the PC.
- Catches are built with `Pokemon.new` at their course level and go into the PC.
- Items go into the bag by name.
  - An item the game lacks becomes a Poké Ball if it's a ball, otherwise a Potion.
  - Anything the bag can't hold goes to the PC.

## Steps

`love.system.syncHealthSteps` reads Android's step counter. It stages `steps_pending.json`, which this module consumes.

- The counter runs while the app is closed, so the next read credits the whole walk.
- The launcher reads it every 60 s while open.
- The community Pokéwalker mod reads the same file. If both are installed, they split the steps between them.

## Art

- **Walking:** HGSS follower sheets. Each is 8 frames of 32×32, stacked vertically.
- **Portraits:** Black/White front sprites (649 species), then HGSS, then Platinum.
- Portraits are trimmed to their opaque bounds and scaled in whole steps.
- Everything else (the course scenes, icons and cards) is drawn in code.

## Checks

```
love tools/pokewalker_check
```

25 checks, run in their own identity. The screenshot tool has walker options: `WALKER=1 WALKER_DEMO=1 WALKER_TAB=walk|radar|dowse|bag|card|settings WALKER_PANEL=pickGame|pickSlot|pickCourse|pickMon love tools/launcher_shot`

## Not done yet

- Painted art: prompts and file names are in `docs/pokewalker-art.md`. The app uses the files when present.
- **Walker state across devices.** `pokewalker.lua` isn't part of cloud sync.
- Peer play (Connect).

## Notifications (Android)

`src/pokewalker/WalkerNotify.lua` talks to the phone through `love.system.walkerNotify(json)`. That is a new bridge:

- `love/src/jni/.../common/android.cpp`, `System.cpp` / `System.h`, `wrap_System.cpp`
- → `GameActivity.walkerNotify`
- → `WalkerNotifications.java` and `WalkerAlarmReceiver.java`

**post:** shows a notification now. The launcher sends the diary's new events while you are elsewhere in it.

**watch:** sent after every step update. It carries the coming milestones, in steps from now:
- the next course unlock (exact);
- the walk's encounter groups coming within reach;
- 1,000-step "it may have found something" reminders;
- the day's 5,000 / 10,000 / 15,000 goals.

An inexact half-hourly alarm checks them while the app is closed. Each check reads the hardware step counter against the step bridge's own anchor, adds any staged `steps_pending.json`, and notifies each milestone passed once. It never moves the anchor, so steps are still credited by the app when it next opens.

**stop:** cancels the alarm. Settings → Notifications off sends this.

**Permissions and the manifest:**
- Android 13+ asks for POST_NOTIFICATIONS on the first call.
- RECEIVE_BOOT_COMPLETED re-arms the alarm after a reboot.
- The receiver is registered in `app/src/main/AndroidManifest.xml`.

The native side needs an APK rebuild. It hasn't been compiled or run here.
