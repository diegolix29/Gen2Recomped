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
| `src/pokewalker/WalkerEconomy.lua` | Watts besides steps, the rewards API for the minigames, the login streak, achievements, leaderboards and Watt Shop purchases (see "Economy"). |
| `src/pokewalker/WalkerShop.lua` | The Watt Shop's shelves: items per generation, the daily Pokémon stock, the weekly Mystery Gifts, cosmetics. |
| `src/ui/WalkerEconomyPages.lua` | The Watt Shop, Awards and Leaderboard pages, installed into the screen. |
| `src/pokewalker/WalkerEvents.lua` | The Watt Shop's **Events** shelf: the real per-game event distributions (key items and event Pokémon) and their delivery. |
| `src/ui/WalkerEventsPage.lua` | The Events tab (game chips, key events, event Pokémon). |

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
- Event courses have no unlock path yet. (Now they do: the Watt Shop sells them; see "Economy".)

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

### Which game's pictures (2026-10-17)

Searched game by game, highest generation first, among the games imported:

- **Walking:** HeartGold / SoulSilver's follower sheet, else Emerald / FireRed's two-frame menu sprite, else the Gen 2 games' (Crystal, Polished Crystal, Prism, Gold, Silver -- in Gen 2 those are the overworld Pokemon sprites). Black / White have no overworld Pokemon, so with only B/W in the walk is the front with a bob.
- **Portrait:** Black / White, HGSS, Platinum, then Emerald / FireRed, the Gen 2 games and Yellow / Blue / Red (`pokemon.lua` `spriteFront`).

**Android and packaged builds showed none of them.** `WalkerArt` opened `SaveData.dataDir() .. "/<game>/..."` only. That is the player's chosen game-data folder, and it is nil in portable mode (on purpose) and whenever no folder was chosen -- Android's default. So the pictures worked only on a source run with a custom folder set. It now tries each cache root with `io.open`: `CacheFs.root()` (portable or custom), `SaveData.dataDir()`, the portable folder, then LOVE's save directory, and `love.filesystem.read` last for a folder only Android's JNI bridge mounted. Red's un-prefixed paths skip that last step, because the version overlays answer them for the active game.

Check: `lovec tools/walker_art_check` (21). It writes a tiny Crystal cache into its own save directory to stand in for Android's default, then walks the generation order against `FIX`, a folder of `only_<game>/<game>` junctions to the real caches (`G:/Gen2Recomped/scratch_claude/walker_art_fixture`).

### Layout on phones (2026-10-17)

Reported from Android: the launcher's footer sat over the Walk page's Bring it home / Send presents home buttons and the Diary. The screen returned the height it was asked for, but in landscape a phone is about 393 dp tall, the launcher asks for `560 * s` = 392, and the page has a 220 px floor below the hero and tiles. So it drew about 116 px more than it reported. The launcher pages the column and places its footer on that number, so the footer landed on the page. Changes:

- `P:draw` returns the height it drew, and `pageWalk` reports its own.
- Under 640 px wide (a phone in portrait), the Pokemon's card stacks over the Diary instead of two half-width cards.
- Under 110 px per tile, the tiles go two rows of three.
- "Read my steps now" sizes to its label, and the diary starts under it.

Screenshots: `FAKE_OS=Android W=393 H=851 WALKER=1 WALKER_DEMO=1 PAGE_SCROLL=max lovec tools/launcher_shot` (and 851x393, 1080x2340, 2340x1080). `SAFE=x,y,w,h` fakes `love.window.getSafeArea`.

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

## Economy (2026-10-17)

Everything lives in the walker state under `st.econ`, so `pokewalker.lua` stays one file. All values below are this port's own; the original had no shop.

### One state per process

`W.load()` returns the same table every time (`W.live`). `W.save(st)` makes `st` the live state, and `W.reload()` reads the disk again. Before this, the screen, the launcher's background step pump and now the passive watts each held their own copy, and the last one to save overwrote the others.

### Passive watts

- 5 W an hour while the app is open, at most 50 W a day (local midnight) from this source.
- `main.lua` feeds `E.tick(dt)` from `love.update` before it hands the frame to the launcher or the game, so the time counts in both. A single frame counts for at most 5 s, so a stall isn't paid.
- Credits happen every 60 s of play. Partial progress (`econ.passive.secs`) is saved whenever a watt comes in, at least every 5 minutes, on focus loss and on quit.
- **Background:** `love.focus(false)` saves and notes the wall-clock time. `love.focus(true)` credits the time away minus whatever frames ran meanwhile, within the cap. Android stops frames in the background, so the gap is paid. Desktop keeps ticking while unfocused, so nothing is counted twice.
- A player who never opened the walker gets no file written. Their time waits in memory, up to one day's worth.

### Daily login and streak

The first walker open of a day pays 5 W × the streak (5, 10, 15 … capped at 30 W). Missing a day starts the streak over at 1. Each bonus is written to the Diary, and the Diary title shows "N-day streak" when there's room.

### The rewards API (`src/pokewalker/WalkerEconomy.lua`)

| Call | What it does |
| --- | --- |
| `E.earn(st, watts, source)` | Adds watts with no cap. They count toward lifetime watts, so courses unlock on them. Recorded per source in `econ.earned`. Returns the watts added. |
| `E.grantItem(st, name, count, source)` | Adds to `st.items`, stacking same-named grants as `count`. Returns `true`, or `false` and a reason (10 stacks at most). |
| `E.grantPokemon(st, dex, level, source)` | Adds to `st.caught` in the radar's shape (`species, name, level`). Returns the entry, or `false` and a reason (6 at most, dex 1–649). |
| `E.recordScore(st, gameId, score)` | Adds the score to that game's top-10 board (`econ.scores[gameId]`, `{ score, t }`, best first; a tie ranks under the earlier score). Returns the rank, or `nil` if it didn't place. |
| `E.achievement(st, event, amount)` | Adds to a counter and returns the achievements newly earned. |
| `E.friendship(st, amount, exp)` | Raises the walking Pokémon's friendship (capped at 255) and adds `exp` (default `amount * 10`) to `walking.bonusExp`. Returns the friendship, or `false` if nobody is walking. |
| `E.save(st)` | Same as `W.save`. |

Granted items and Pokémon carry `granted = true`. They don't take the original's three found-item and three catch places: Dowsing, finds and the radar count only their own (`W.heldCount`), and a swap replaces only a find. They go home with **Send presents home** as before.

**Coming home:** `WalkerLink.deliver` writes `bonusExp` into `returning`. `WalkerInbox` adds it to the walk's steps but still caps the EXP at one level. Friendship arrives as the walked value, so whatever the minigames added is kept. Item stacks keep their `count` in the bag.

**Fixed along the way:** `WalkerInbox` compared names with the "é" stripped. "POKé BALL" therefore never matched, and every ball sent home became a Potion. The "é" now reads as E.

### Achievements

26 achievements, each paying its watts once:

- steps: 1k / 10k / 50k / 100k / 500k
- watts earned: 100 / 1k / 5k / 20k
- catches: 1 / 10 / 50
- dowsed items: 10
- minigames: finished 1 / 25 / 100; new bests 1 / 10; 3 different boards
- shop purchases: 1 / 10 / 50
- login streak: 3 / 7 / 30
- a walking Pokémon at 255 friendship

The screen feeds `catch` and `dowse`, and `recordScore` feeds `minigame_plays` / `minigame_best`. Steps and watts are read from the state; the screen checks them every 2 s.

### Watt Shop

There's a **Watt Shop** tile. Purchases go to a game and save chosen through the walk's own game → save picker (only games with a save are listed). The default is the walking Pokémon's game. Every purchase asks first, showing the balance before and after. Delivery goes through `WalkerLink.deliverTo` into `save.walkerInbox`, with a backup in `pokewalker_backups/`, and the game unpacks it on its next load.

- **Items:** 63 items by generation (medicine, balls, evolution items, held items, training, other), sold in bundles. Every name was checked against Crystal, Emerald, Platinum, HeartGold and Black's own `items.lua`.
- **Pokémon:** six a day for the target game, drawn deterministically from its own dex range with no legendaries. Each sells once a day. Level is 5–25 and price is 40 + BST/4 (doubled at BST 580+).
- **Mystery Gifts:** four a week (two Pokémon, two rare items), each claimable once a week. Examples are Mew, Celebi, Jirachi, Shaymin, Victini, Master Ball and Rare Candy x5. A gift the target game can't hold is marked and can't be bought for it.
- **Cosmetics:** walk-scene backgrounds, shell colours (they frame the hero and colour the selected tile), sound sets (button beeps at the Sound setting; tap a set to hear it), and the seven event courses (500 W, plus 100 W for each further one). Event courses now have an unlock path.

### Events shelf (2026-10-18)

The **Events** tab sells the real distributions, per game, once per save. A row of chips lists every imported game with a save. Tapping another game asks which of its saves to deliver to.

- **Key events**, delivered the way the cartridge's own Mystery Gift left them:
  - Crystal: GS Ball. This sets `save.gen2MobileEvent = $0B`, the Mobile Adapter byte that `CheckGSBall` reads, so the Goldenrod receptionist hands it over.
  - Emerald: Eon Ticket, MysticTicket, AuroraTicket and Old Sea Map. These go through `Gen3MysteryGift.unlock` (the SS Tidal row's flag, the ticket, and var `0x403F` for the Eon Ticket), plus the Wonder Card's `FLAG_RECEIVED_*`.
  - FireRed: MysticTicket (flags `0x84A`, `0x2A8`) and AuroraTicket (flags `0x84B`, `0x2A7`). These need the National Pokédex.
  - Platinum: Member Card, Oak's Letter, Secret Key, Azure Flute and the Manaphy Egg.
  - HeartGold/SoulSilver: Enigma Stone and the Manaphy Egg.
  - Gen 4 gifts wait with the Poké Mart deliveryman (`Gen4MysteryGift`), whose handlers set the distribution magic.
  - Black/White: Liberty Pass.
- **Event Pokémon** use the real event's OT, ID, level, moves, held item, ball, ribbons, fateful mark, and the personality and IVs where these were fixed. The facts were read from the Project Pokémon Events Gallery dumps, and each entry names its source.
  - Gen 4 Pokémon wait with the deliveryman.
  - Pokémon from other generations join the party, or the PC when the party is full.
  - HGSS Celebi, Arceus and Shaymin trigger their own ROM checks.
  - The BW Poké Transfer beasts and Celebi open Zoroark and Zorua.
- A purchase is queued in `save.walkerEvents.pending`. `WalkerEvents.apply` runs when the save loads, called from `WalkerInbox.apply`. `claimed` stops a second sale.
- Bought events don't use up the port's own Hall-of-Fame or game-clear picks.
- Check: `GAME=<v> "C:/Program Files/LOVE/lovec.exe" tools/walker_events_check`. It uses scratch saves only. For every event it checks the bag, flags, vars and the engine's port of the ROM check. It builds the PK3/PK4/PK5 record, checks the checksum and ribbons, and round-trips the whole save through export and import.

### Awards and Leaderboards

The **Awards** tile shows the streak, tomorrow's bonus, today's open-app watts with a bar, and every achievement with its progress. The **Leaderboards** button opens one board per minigame (top 10, with dates).

- `screen:openPage("leaderboard", gameId)` opens a board from anywhere. `openPage` also takes `"shop"` (with an optional shelf: `items`, `pokemon`, `gifts` or `cosmetics`) and any tile id.
- The game chips come from `WalkerMinigames.games()` (or `.GAMES`, entries with `id` and `title`/`name`), plus any board that has scores.

### Minigames button

The **Minigames** button sits beside Send presents home, or on its own row when three buttons won't fit. It is also on the page when nobody is walking. It calls `P:openMinigames()`, which does `pcall(require, "src.ui.WalkerMinigames")` and then `.open(screen, st)`. If the module is missing, it says "coming soon".

### Checks

`lovec tools/walker_econ_check` runs 68 checks in its own identity. They cover the passive credit and cap, the background gap, persistence, the streak, the rewards API, achievements, boards, every shelf item against five games' item tables, stock and gift rotation, delivery into a scratch Platinum save, cosmetics, bonus EXP going home, and the inbox's stack and "Poké Ball" fixes.

Screenshots use a scratch identity:

```
IDENTITY=Gen2Recomp_walkeconshot WALKER=1 WALKER_DEMO=1 WALKER_ECON=1 \
  WALKER_DATA=G:/Gen2Recomped WALKER_TAB=shop|awards|leaderboard \
  WALKER_SHOP=items|pokemon|gifts|cosmetics WALKER_CONFIRM=1 WALKER_BOARD=<id> \
  lovec tools/launcher_shot
```

### Needs a device

Background accrual on Android, meaning that the `focus(false)` / `focus(true)` pair arrives around a backgrounding and the process survives it. If Android kills the process in the background, the time away is lost (nothing is credited for time the app wasn't running). The sound sets haven't been heard on a phone either.

## Minigames (2026-10-17)

Five games for players without a step counter. They pay watts, a few items and the odd Pokémon from the current course. The hub is `src/ui/WalkerMinigames.lua`, opened with `WalkerMinigames.open(screen, st)` (the Minigames button). The games are in `src/pokewalker/minigames/`.

| File | What it is |
| --- | --- |
| `Rewards.lua` | Every payout goes through here. It holds the daily and per-run budgets (`Rewards.LIMITS`), the run's purse, the settle at the end, and the leaderboard. |
| `Context.lua` | What a run plays with: the walking Pokémon (Pikachu stands in when nobody is walking), the course's six wild Pokémon, swapped into the walker's own game's dex by `WalkerCourses.forGame`, the course's cheaper items plus basics, and a seeded RNG. |
| `Base.lua` | The shell: intro, play, pause, results; the header; one input vocabulary for every device. |
| `Gfx.lua` | The Pokéwalker look: cards, buttons, scaled fonts, the course scene from `PokewalkerScreen`, and sprites from `WalkerArt` with a drawn stand-in. |
| `JumpRunner.lua`, `CatchTiming.lua`, `TreasureHunt.lua`, `MemoryMatch.lua`, `RhythmTap.lua` | The games. Rules are headless; `draw` only paints. |

### The games

- **Jump Runner.** The walking Pokémon (its overworld sprite) runs the course. Tap, click, A or Space to jump, and again in the air to double jump.
  - Landing on a wild Pokémon bounces off it for 50 points, multiplied for several in one jump. There's a 4/6/8% chance (groups A/B/C) to catch it.
  - Hoops are worth 30, watt orbs 10 points and 1 W each (up to 10 W a run), and an item appears about every 260 tiles.
  - You can land on rocks and logs. Running into one, or into a Pokémon from the side, ends the run.
  - Speed rises from 6 to 14 tiles/s. You score 1 point a tile, and the run pays score/250 W plus the orbs.
- **Catch Timing.** A ring shrinks over a wild Pokémon from the course. Tap when it meets the gold circle.
  - Throws grade as Perfect, Great or Good (300/200/100 points), which multiplies the catch chance ×1.6/×1.25/×0.85 on a base of 25/40/55% (A/B/C). A catch adds 400/300/200.
  - You get 6 balls. A Pokémon left waiting 7 s wanders off with a ball. The ring speeds up after each throw.
  - Pays score/100 W.
- **Treasure Hunt.** A 6×6 field hides five watt caches (2–5 W), a big 8 W cache, and up to two course items while the item budget allows. You get 12 digs.
  - An empty hole says Hot, Warm, Cool or Cold for the nearest buried thing.
  - Finding everything ends early, with +40 per dig left. Pays score/30 W.
- **Memory Match.** Eight pairs from the walker, the course and some old friends. Only species an imported game has a picture of are used.
  - The timer is 90 s. Each pair is worth 100. A clear adds 4 per second left and 20 per turn under 30.
  - Pays score/60 W.
- **Rhythm Tap.** Notes slide to the walking Pokémon over a generated click track (kick, tick, a chime per hit). The tempo goes from 96 to 132 BPM over 80 s, with off-beats creeping in.
  - Perfect, Great and Good windows are 50, 100 and 150 ms (100/70/40 points).
  - A streak multiplies the score: ×2 at 10, ×3 at 20, ×4 at 30. A miss or a stray tap breaks it.
  - Pays score/1200 W.
  - It doesn't use the launcher's music. That's the backdrop game's title music, which has no tempo to tap to. The backdrop is held still and silent while the hub is up.

From `tools/walker_minigames_check` (bots and simulations):
- A good 2.5-minute runner run pays about 20–24 W.
- An all-Great catch run pays 13 W; an all-Perfect run 28 W.
- A hint-following treasure hunt averages 19 W.
- A near-perfect memory clear pays 26 W.
- A 90%-hit rhythm song pays 17 W.

### Rewards and budgets

A run collects into a purse. Nothing is paid until the run ends, and quitting from pause still pays. `Rewards.settle` then:
- calls `E.earn`, `E.grantItem`, `E.grantPokemon`, `E.recordScore` (its rank is shown), `E.achievement`, `E.friendship` and `E.save`, as the WalkerEconomy contract says;
- treats an economy `false` (its bag full) as a lost prize, and the results say so.

Without the economy module, watts go onto `st.watts`, items and Pokémon go into the walker's own 3-slot lists, and `Walker.save` saves.

The limits are in `Rewards.LIMITS`. They are per day across all five games, and the day turns at midnight UTC:

| Limit | Value |
| --- | --- |
| Watts per day | 300 |
| Items per day | 8 |
| Pokémon per day | 3 |
| Friendship per day | 10 |
| Watts per run | 40 |
| Items per run | 3 |
| Pokémon per run | 1 |
| Friendship per run | 2 (a run under 15 s gives none) |

Past a budget, the games still play and score. They stop spawning or burying that kind of prize, and a catch is scored but released.

These caps are the minigames' own. WalkerEconomy's `E.earn` doesn't cap minigame watts.

Achievement events:
- Shared, every run: `minigame_played`, `minigame_<id>_played`, `minigame_score_<id>` (the score), `minigame_watts`, `minigame_item`, `minigame_catch`, `minigame_new_best`.
- When Pokémon or items are actually granted: `catch`, and `dowse` for Treasure Hunt items. These feed the economy's catch and dowse achievements.
- Per game:
  - Jump Runner: `runner_stomp`, `runner_hoop`, `runner_orb`, `runner_catch`, `runner_distance`
  - Catch Timing: `catch_perfect`, `catch_caught`
  - Treasure Hunt: `treasure_watts`, `treasure_item`, `treasure_cleared`
  - Memory Match: `memory_pair`, `memory_cleared`
  - Rhythm Tap: `rhythm_perfect`, `rhythm_best_streak`, `rhythm_streak`

Persisted in `st.minigames`:
- `day` and `daily` (the day's counters);
- `games[id]`: best, plays, total watts, and the top ten `{ score, watts, t, rank }`.

The hub's Scores view shows the economy's board for the game when it has one, with each run's watts matched in, else this list.

### Taking over the screen

`open` covers the launcher instance's draw, update and input methods (`screen.host`) with instance fields that route to the hub, and removes them on close. With only a screen, it covers the screen's methods instead. The hub then draws the whole window inside `love.window.getSafeArea()`.
- The launcher's own update keeps running. It runs with `settingsOpen = true`, the pause its Settings page uses, so the background game holds still and silent. The previous value is restored on close.
- Taps arrive as `mousepressed`; Android forwards touches that way and iOS synthesizes them.
- Gamepad buttons arrive as `gamepadpressed`. The launcher's virtual cursor and its Start-to-play are bypassed while the hub is up. A face button maps through `GamepadMap`, so Switch layouts work.

| Device | Controls |
| --- | --- |
| Touch / mouse | Tap = action. |
| Keyboard | Space / Enter / Z / X = action; arrows / WASD to move; Esc / P / Backspace (Android Back) to pause or go back; Tab = scores in the hub. |
| Gamepad | A = action; d-pad or left stick to move; B / Start to pause or go back; X / Y = scores. |

Frames are clamped to 1/20 s, so a phone waking up doesn't teleport the runner. Closing the hub leaves a toast on the Pokéwalker screen ("Minigames: 2 runs, +31 W").

### Checks and screenshots

```
python tools/run_lua_check.py tools/walker_minigames_check.lua
```

The check runs 116 checks headless (no love), seeded. It covers:
- each game's scoring, physics and timing windows, and its watts;
- the economy present (a recording fake, the real `WalkerEconomy`), saying no, and absent;
- every daily and per-run budget, and the day turning over;
- save/load persistence;
- the hub's keyboard, gamepad and tap flow, pause, results and paying once;
- covering and uncovering a screen and a launcher-like host.

Screenshots come from `lovec tools/walker_minigames_shot`:
- Set `GAME=hub|scores|runner|catch|treasure|memory|rhythm|results`, with `W`, `H`, `FAKE_OS`, `SAFE`, `OUT`, `T` (seconds of scripted play), `PAUSE=1` and `INTRO=1`.
- It uses its own identity and reads art from `ART` (default `G:/Gen2Recomped`) through `WalkerArt._roots`.
- `LAUNCHER=1` builds the real launcher (identity Gen2Recomp, saves stubbed) and opens the hub on it through `open(screen, st)`.

Shots of the hub, the scores and each game mid-play are in `G:/Gen2Recomped/scratch_claude/walker_games/`, at 1280×800, Android 1080×2340 and 2340×1080 with safe areas, and 851×393 through the launcher.

### Not done

- None of this has been run on a phone: touch latency, and the rhythm game's audio offset (`RhythmTap.AUDIO_OFFSET`, 0 for now).
- The rhythm click track hasn't been heard. The harness runs without audio.
- Painted art for the games: they use the course backgrounds and drawn props.
