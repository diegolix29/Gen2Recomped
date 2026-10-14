# Emerald: game stats and the Gym Leader rematches

**Before this:**
- `save.gen3Stats` held only what scripts wrote with `incrementgamestat`:
  the Pokémon Center, the TV, the cable car and the like.
- Steps, battles, captures, evolutions, hatches, fishing, shopping, saving,
  the Pokédex, ledges, Cut, Rock Smash and the Hall of Fame were never
  counted.
- So the Mauville Storyteller's tales about them never came true.
- Emerald's Gym Leader rematches, which `battle_setup.c` rolls off the
  battle counts, never happened.

**Now** (`src/pokemon/Gen3GameStats.lua`, from `overworld.c`,
`battle_setup.c` and `gym_leader_rematch.c`):
- **The counters:** the 52 used `GAME_STAT_*` ids, each stopping at
  0xFFFFFF, in the same `save.gen3Stats` table the scripts and the save
  converter use.
- **Counted by the engine, at the cartridge's moments:**
  - a step (`field_control_avatar.c`)
  - a battle: all battles, plus wild or trainer (`battle_setup.c`)
  - a fishing encounter (`wild_encounter.c`)
  - a capture (`battle_scripts_2.s`)
  - an evolution and a hatch
  - a purchase (`shop.c`)
  - a save and opening the Pokédex (`start_menu.c`)
  - a ledge jump (`field_player_avatar.c`)
  - Cut and Rock Smash (`fldeff_cut.c`, `fldeff_rocksmash.c`)
  - entering the Hall of Fame (`save.c`), and the play time of the first
    entry as hours << 16 | minutes << 8 | seconds
    (`post_battle_event_funcs.c`)
- **Frontier battles** don't touch these. They count
  `frontier.battlesCount` instead (`HandleSpecialTrainerBattleEnd`). Every
  Frontier battle is now marked `frontier = true` (tower, Palace, Arena,
  Dome, Factory, Pike, Pyramid). Link battles count nothing.
- **The Gym Leader rematch** (`UpdateGymLeaderRematch`):
  - It is rolled on every 60th wild battle, every 20th trainer battle, and
    every 20th Frontier battle.
  - Once the game is cleared, 31 in 100 rolls arm one leader.
  - Only leaders not already waiting are candidates. Of those, the ones
    furthest behind on their rematch ladder (`GetRematchIndex`: the first
    of their five not yet fought) are eligible, and one is picked at random
    and armed at that step.
  - Wattson only joins once his New Mauville flag is set. Before that, no
    leader goes past their first rematch.
  - The armed slot is the same `save.rematches` that Match Call and the
    gyms' `ShouldTryRematchBattle` read, so the leader offers the rematch
    when you walk in.
  - FireRed has no leader rematches, so the roll is Emerald's alone; the
    stats are counted for both.

**Checks:**
- `tools/emerald_game_stats_check.lua`: 22 checks, or 24 with a pokeemerald
  checkout, which compares `game_stat.h` and the leaders' rematch indices.
- `tools/gen3_battle_tower_harness` prints the stats at the end. A Battle
  Pyramid run counted 168 steps, the floor's wild battle, and its trainer
  battle as a Frontier battle.
