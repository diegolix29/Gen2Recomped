# Emerald: the Battle Tower

The Battle Tower's Single and Double Battle Rooms now work from start to
finish: Level 50 and Open Level, Anabel and her two symbols, Battle Points,
ribbons, and Rest and Continue. This follows pret's pokeemerald
(`battle_tower.c`, `frontier_util.c`).

- **Code:** `src/script/Gen3BattleFrontier.lua`.
- **Data:** the trainers and sets already in `gen3FrontierParties`, plus
  `gen3_frontier_speech`.

## How it runs

The lobby, elevator, corridor and battle room are ordinary maps running
their own scripts. Everything they ask goes through three specials:

- **234 `CallFrontierUtilFunc`:** the Frontier's shared bookkeeping.
- **235 `CallBattleTowerFunc`:** the tower's own functions.
- **239 `DoSpecialTrainerBattle` arm 0:** the battle.

These are installed over the Battle Tents' handlers. A tent call
(`FRONTIER_LVL_TENT`, or a facility other than the tower) still goes to the
tent code.

**The challenge:**
- **Opponents:**
  - They're drawn from the cartridge's ranges for the current set of seven
    (the hard range for the seventh), with nobody met twice in a challenge.
  - Each opponent's sprite comes from the facility-class tables
    (`VAR_OBJ_GFX_ID_0`), and their intro is their easy chat phrase
    (`msgbox gStringVar4`).
- **Teams:** `FillTrainerParty`.
  - The trainer's own set, with no species or held item twice.
  - The high tier is left out at level 50.
  - IVs are fixed by trainer id; the EV spread shares 510; each personality
    carries the set's nature.
  - Level 50, or for Open Level the party's highest level (at least 60).
- **Your team:** the chosen members, with no experience paid. The items they
  held are put back after each battle (`frontier_restorehelditems`, from a
  snapshot taken when the party is stashed).
- **Anabel:**
  - She appears as the 35th opponent (silver), the 70th (gold), and every
  35 after that once both symbols are held.
  - Her two teams are transcribed from `sFrontierBrainsMons`.
  - Her symbols are `FLAG_SYS_TOWER_SILVER` / `_GOLD`.
- **Battle Points:** the tower column of `sBattlePointAwards`, plus 10 for
  Anabel.
- **Ribbons:** past 55 wins in a row, the Winning (Lv. 50) or Victory (Open
  Level) Ribbon.
- **Rest:**
  - `tower_save` writes the save with the whole party restored, and with the
    continue point at the lobby spot `InitTowerChallenge` marked
    (`SaveGameFrontier`).
  - `frontier_reset` returns to the title screen.
  - Continue resumes at the lobby, where "We've been waiting for you!" picks
    the challenge up.
- **Battle recording:** there is no recorder, so `RECORD_DISABLED` stays on.
  The Record choices aren't offered at all, rather than offered and then
  failing.

**Not here yet:** link play, the e-Reader and record-mixed trainers, and the
results windows. The multi rooms are below; the other six facilities have
sections of their own.

## Fixes this needed, which help more than the tower

- **Emerald's `gStringVar4` is at `0x02021FC4`,** not beside the other
  three string vars. Every `msgbox gStringVar4` in Emerald (18 sites) lowered
  to nothing. A buffer that a not-ported function never filled now shows no
  box at all, rather than a stale one.
- **A frame-table script takes its frame's input:**
  - On the cartridge, `TryRunOnFrameMapScript` runs before any interaction.
  - Here, a one-row status poll finished inside the frame check, and an A
    press in the same frame talked to the attendant. The tower lobby's
    "you've beaten all seven" never played.
  - The same applies to a script that finishes during that frame's runner
    update.
- **Battle Tents now show their trainers:** Verdanturf's tent arms 3 and 4
  set the opponent's sprite and buffer their intro.
- **No experience in Frontier battles:** `noExp` on the battle (it's also used
  by Platinum's tower).

## Checks

- `tools/emerald_battle_tower_check.lua` (32).
- `tools/gen3_battle_tower_harness` plays a challenge on the real engine:
  - `BATTLENUM=6` starts at the seventh battle.
  - `STREAK=33 BATTLENUM=5` meets Anabel.
  - `REST=3` chooses Rest and then Continues.
- For an existing cache, run `tools/gen3_frontier_speech_extract.lua`.

# Battle Palace rules, and the Battle Palace

## The rules (`src/battle/Gen3Palace.lua`)

This follows `ChooseMoveAndTargetInBattlePalace` and the nature table.

- **Nobody gives orders.** Each turn, each Pokémon's nature picks a move
  group using its own odds:
  - **Attack:** damaging moves.
  - **Defense:** moves aimed at the user.
  - **Support:** no-power moves aimed at a foe, plus field and "depends"
    moves.
  - At half HP or below (and awake), the nature uses a second set of odds.
- **A move from the chosen group is used.**
- **If it knows none in that group:**
  - A usable move is drawn instead, keeping the cartridge's slip in its
    "two or more Support moves" test.
  - Half the time, the Pokémon "appears incapable of using its power!" and
    does nothing.
- **The nature shows** the first time a Pokémon is at half HP: "is eager for
  more!", "began growling deeply!", "A glint appears in …'s eyes!", or "is
  getting into position!".
- **A fainted Pokémon is replaced** by the next in the party, unasked.
- **One difference from the cartridge:** within the chosen group the cartridge
  lets its battle AI score the moves; here the pick is random.

**Where these rules apply:**
- **Verdanturf's Battle Tent** now fights under them. Every tent battle is
  also a Frontier battle now: no EXP, and a loss ends the challenge instead
  of causing a whiteout.
- **The Battle Palace** (below).

## The Battle Palace

It uses the same plumbing as the tower:
- **Special 237 `CallBattlePalaceFunction`:** streak, comments, intro, save
  and prize.
- **The tower's `SetNextFacilityOpponent`** picks its opponents.
- **`DoSpecialTrainerBattle` arm 4** runs its battles, three Pokémon a side
  in both modes, under Palace rules.
- **Spenser** appears at 21 and 42 with his two teams.
- **Battle Points** come from the Palace's own column, and the Spirits Symbol
  works.

**Streaks per facility:** each facility now keeps its own streak; the tower's
table is unchanged.

**Telling the tent and the Palace apart:** Verdanturf's tent shares the
Palace's facility number. A tent challenge is recognized by its level mode
(`FRONTIER_LVL_TENT`) instead.

**Checks:**
- `tools/emerald_battle_palace_check.lua` (25).
- The harness plays the Palace with `MAP=MAP_G26_N22 X=5 Y=7`.
- `PALACE=1` runs the tower's battles under Palace rules.

## The Battle Arena (`src/battle/Gen3Arena.lua`)

**The rules:**
- One Pokémon against one, for three turns. If neither has fainted by the end
  of the third turn, the referee judges and the loser counts as fainted.
- **Mind** is what each one tried, scored as the move is chosen (even if it
  then doesn't happen):
  - A move with power scores 1. Counter, Mirror Coat and Bide score 0, and
    Fake Out scores −1.
  - A move without power scores 0. Protect, Detect and Endure score −1.
  - This is the rule the cartridge's `sMindRatings` comment states. The check
    compares it with every row of the table.
- **Skill** is how the move went:
  - Super effective +2, ordinary +1, not very effective −1.
  - A miss, no effect, or a failure −2.
  - A move stopped by Protect, or the user's own Protect, scores nothing.
  - An ability that makes the move do nothing costs a further −3.
- **Body** is the HP left, as a percentage of the HP each had when the pair
  met.
- **Scoring:** each category is worth 2 to the better side, or 1 each for a
  tie. A 3–3 total is a draw, and both go down.
- **No switching:**
  - The party menu refuses a switch.
  - The trainer's AI never tries one.
  - A fainted Pokémon is replaced by the next one in the party, without
    asking.
- **Each new pair:** you see "REFEREE: X VS Y! Commence battling!", and the
  pair's points and turn count start over.

**The facility:**
- **Special 240 `CallBattleArenaFunction`:** init, get and set data, save,
  prize and the opponent's name.
- **`DoSpecialTrainerBattle` arm 5** runs the battles.
- **Greta** appears at 28 and 56 with her two teams.
- **Battle Points** come from the arena's own column: 1, 1, 1, 2, 2, 2, 3, 3,
  4, 4, 5, 6, … up to 15.
- **Prizes:** a vitamin before a 42-win streak, a held item after.
- **Fallarbor's Battle Tent** fights under the same rules.

**Every Frontier battle can now be forfeited.** Run asks "Would you like to
forfeit the match and quit now?", and Yes loses the battle
(`BattleScript_AskIfWantsToForfeitMatch`). This applies to the Tower,
Palace, Arena and the tents. Before, Run said "No running from a trainer
battle!".

**Fixes this needed:**
- **The battle's outcome now reaches `VAR_RESULT`**, as it does after every
  battle on the cartridge. The arena's battle room reads the result straight
  from there.
- **Frontier utility arms 5, 7, 8 and 21 are now harmless no-ops** (the
  trainer tables, the results window, the TV check and resetting Sketch).
  Before, they fell through to the generic stub, which zeroes `VAR_RESULT`.
  The arena calls `frontier_resetsketch` between its battle and the check on
  its result.

**Not the cartridge's:**
- **The judgment window:** the window's circle, triangle and cross marks
  aren't drawn. Each category's line is followed by who took it, in words.
- **The −3 skill deduction:** the cartridge also takes −3 for an ability or
  held item that speaks up against a move (Own Tempo, Lum Berry and the
  like). Here it's taken only when an ability makes a move do nothing.

**Checks:**
- `tools/emerald_battle_arena_check.lua` (73). Pass the pokeemerald checkout
  as the second argument to compare the Mind rule with the table.
- The harness plays the arena with `MAP=MAP_G26_N28 X=7 Y=8`.
  - `ARENA=1` prints the referee's lines and each judgment's scores.
  - `ARENADBG=1` prints every move's outcome.
  - `FORFEIT=1` runs at the first menu.

## The Battle Pike (`src/script/Gen3BattlePike.lua`)

**The challenge:**
- Fourteen rooms. In each three-door room you pick a door, and behind it is
  one of nine room types:
  - a trainer
  - a tougher trainer, then a full heal
  - two trainers at once, one Pokémon each
  - a full heal
  - a heal for one or two Pokémon
  - a talker
  - a Kirlia or Dusclops that inflicts a status on part of the team
  - a room of wild Pokémon
  - from the 28th room on, Lucy the Pike Queen
- **The team carries its damage:** nothing heals between rooms unless a room
  does it.
- **The maps' own scripts run all of it.** This module answers their 29
  functions (special 242 `CallBattlePikeFunction`), runs
  `DoSpecialTrainerBattle` arms 7 (single) and 9 (two trainers), and builds
  the wild room's encounters.

**The rooms, as `battle_pike.c` draws them:**
- **The hint:** the woman in the three-door room names one door's room type.
  - That door is what she said.
  - The other two never share her hint's group (people, whispering,
    nostalgia, Pokémon).
  - Rooms that would do nothing are left out: a double battle with fewer
    than two standing, or a status room with nobody to hit.
  - Heal rooms are left out after a room left the team at full health.
- **Status rooms:**
  - The status is drawn as toxic 35%, freeze 25%, paralysis 20%, sleep 10%
    and burn 10%.
  - It hits one Pokémon by room 4, two by room 9, three after.
  - Types and abilities that prevent it are respected, and sleep is the full
    seven turns.
- **Heals:** a heal only goes to a Pokémon that needs one, in a shuffled
  order.
- **Before Lucy:** the heal (0, 1 or 2 Pokémon) depends on which door you
  took and where the hint pointed.
- **Talkers:** their lines are read from the ROM (`sNPCSpeeches`, 42 Easy
  Chat phrases at 086123E4, checked row by row against the decomp). The
  speech extract stage writes them as `gen3_frontier_speech.pikeNpc`.
- **The wild room:**
  - It rolls its own tables (`gBattlePikeWildMonHeaders`) on every tile, not
    just grass.
  - Seviper and Milotic share the room with Dusclops, Electrode, Breloom or
    Wobbuffet, depending on the streak.
  - The level is 4–5 below the cap, or below the team's best at open level,
    and each species has a fixed set of four moves.
  - The lead's Keen Eye or Intimidate can turn one away.
  - There is no held item and no experience.
  - A loss ends the challenge rather than whiting out.
- **Lucy:** her two teams; she appears at 28 and 140 rooms, then every 56.
- **Battle Points:** the Pike's own column, by challenges of fourteen rooms.

**Every Frontier battle now keeps the bag shut:** "Items can't be used now."
(`BattleScript_ActionSelectionItemsCantBeUsed`). This applies to every
facility except the Pyramid.

**Not drawn:**
- The curtain closing between rooms (`CloseBattlePikeCurtain`).
- The screen flash when a status lands.

**Checks:**
- `tools/emerald_battle_pike_check.lua` (31).
- The harness plays the Pike with `PIKE=1 MAP=MAP_G26_N34 X=5 Y=6`.
  - It picks doors, talks to the room's NPC, and walks the wild room.
  - `PIKEROOM=7,5,3` forces the first rooms' types.

## The Battle Factory (`src/script/Gen3BattleFactory.lua`)

`CallBattleFactoryFunction` (special 241) is ported in full (arms 0–16), as is
`DoSpecialTrainerBattle`'s Factory arm (239, arm 6). The lobby, the pre-battle
room and the battle room (`MAP_G26_N31`–`N33`) run on their own map scripts.

- **Rentals:**
  - Six are offered from `gBattleFrontierMons`, by streak tier
    (`sInitialRentalMonRanges`).
  - Past rentals raise a rank (15/22/29/36/43). Each rank point draws one of
    the six from the next tier up, with that tier's IVs.
  - No set or held item appears twice.
  - Every rental and opponent takes the tier's fixed IVs (`sFixedIVTable`),
    friendship 0, and FRUSTRATION wherever its set says RETURN.
- **The screens (`src/ui/Gen3FactoryScreen.lua`):**
  - Select: pick three of the six, in party order, then confirm.
  - Swap: choose which of yours to give, then which of the beaten team's to
    take, or press B to keep your team.
  - The cartridge's ball rack and summary are drawn as a list plus a panel
    showing the item and moves.
- **Opponents:**
  - Three sets, none of them a species that is on offer to you.
  - The hints are the team's most common type and its style (seven move lists,
    with "flexible" when more than two qualify).
  - Opponents' IVs follow the Battle Tower's level-50 streak, as on the
    cartridge, bug included.
- **Swap count:** written back only after a swap was made
  (`factory_setswapped`).
- **Noland:** the Factory Head, at the 21st and 42nd wins. He uses three random
  sets with IVs from two challenges ahead.
- **Battle Points:** the Factory's own column, which pays more in doubles.

**Checks:**
- `tools/emerald_battle_factory_check.lua` (29, or 32 with a pokeemerald
  checkout).
- The harness plays the Factory with `MAP=MAP_G26_N31 X=4 Y=8`:
  - It rents the first three on offer, and keeps its team at each swap.
  - `FSWAP=1` trades first for first instead.
  - `FACTORY_PARTY=1` prints the party at each battle.
  - `STREAK=20 STREAKFAC=4` presets the Factory streak. Noland then comes on
    the challenge's first battle, because the harness doesn't preset the
    battle number.

## The Battle Pyramid (`src/script/Gen3BattlePyramid.lua`)

`CallBattlePyramidFunction` (special 243) is ported in full (arms 0–17), along
with the Pyramid's other specials:
- 449 `TryStoreHeldItemsInPyramidBag`
- 451 `DoBattlePyramidMonsHaveHeldItem`
- 516 `GetBattlePyramidHint`
- the summit battle (239, arm 10)

Its tables are generated from the source (`tools/gen3_pyramid_tables_gen.py`
→ `src/import/Gen3PyramidTables.lua`).

- **The floor:**
  - It is built from the four saved randoms each time it loads: a floor
    template (by floor and a roll), 4×4 squares drawn from
    `BattlePyramidSquare01..16`, and every exit tile turned to floor except
    the exit square's.
  - The player lands on the entrance square's tile.
  - The Floor map's def (`MAP_G26_N26`) is rewritten in place as that 32×32
    floor before each load (`MapLoader`).
- **Objects:**
  - Trainers and item balls go where the squares' own objects stand, by the
    template's rule (uniformly, or in/near the entrance or exit square). The
    same randoms always give the same places.
  - They talk through `BattlePyramid_TrainerBattle` and
    `BattlePyramid_FindItemBall`, filed under the floor map.
- **Items:** a ball's contents come from `SeedRng2(randoms[index / 2])` and the
  round's pickup slots. A taken ball stays gone for the rest of the floor.
- **Trainers:**
  - Frontier trainers picked for the challenge and floor, one Pokémon each,
    with their easy-chat line.
  - Each has its own battled bit, since every square object names the same
    placeholder trainer.
  - Beating one gets a hint from the ROM's `sPostBattleTexts`: six manners ×
    (exit direction, items left, trainers left), found by pointer-chasing in
    the frontier speech extract.
- **Wild Pokémon:**
  - They appear on every tile. The floor's header slots are indexes into the
    round's level-50 or open-level list, with that entry's level (±5), moves
    and ability.
  - Keen Eye / Intimidate apply against the slot's placeholder level 5.
  - 31-IV-range Pokémon from 140 wins use the UBFIX reading; the cartridge
    reads past the array there.
- **The dark:** the light radius (32 on a new floor, 200 at the summit) is
  drawn as the Gen 3 Flash circle. It widens 4 after every battle won, since
  the floor's ON_RESUME re-runs after each battle.
- **The bag:** inside the Pyramid it is the Battle Bag, with ten slots and
  starting with a Hyper Potion and an Ether. The real bag is set aside and
  returned when you leave.
  - Battles in the Pyramid take items; it's the only facility that allows
    them.
  - HP, PP and fainting carry from battle to battle.
- **The exit tile:** `BattlePyramid_WarpToNextFloor` (only C names it) is
  ported as a command. On the seventh floor it leads to the summit.
- **Losing:** a loss on a floor or at the summit sends you back to the lobby
  with the challenge over.
- **Brandon:** at the 21st and 70th floors, then every 35th.
  - Silver team: Regirock, Registeel, Regice.
  - Gold team: Articuno, Zapdos, Moltres.
- **Battle Points:** the Pyramid's own column, 5 for the first round.

**Not ported:**
- two trainers spotting you at once (each comes alone)
- the floor palettes
- the run multiplier
- the Battle Bag's own screen (the ordinary bag shows its items)
- the toss screens a full bag opens at the end (450 / 452): the items that
  don't fit stay held

**Checks:**
- `tools/emerald_battle_pyramid_check.lua`: 39 checks, or 40 with a
  pokeemerald checkout, which also regenerates the tables and compares them.
- The harness plays the Pyramid with
  `PYRAMID=1 MAP=MAP_G26_N25 X=7 Y=13`. It walks each floor to the exit
  (breadth-first round walls and people) and talks to the summit attendant.
  - `PYRSKIP=6` starts on the seventh floor.
  - `PYRSTREAK=14` with it meets Brandon.
  - `PYRITEM=1` picks up item balls.
  - `PYRWEAK=1` loses the first battle.

## The Battle Dome (`src/script/Gen3BattleDome.lua`)

`CallBattleDomeFunction` (special 236) is ported in full (arms 0–22), as is
`DoSpecialTrainerBattle`'s Dome arm (239, arm 3). The lobby, corridor,
pre-battle room and battle room (`MAP_G26_N18`–`N21`) run on their own map
scripts.

- **The field:**
  - Fifteen frontier trainers are drawn for the streak, the first five a
    step harder. Each brings three sets, with no species or item twice.
  - The species check carries over from the previous trainer, as on the
    cartridge.
- **Seeding:** everyone is ranked by the six stats of their three Pokémon,
  plus the number of distinct types × level / 20.
  - Opponents' stats come from `CalcDomeMonStats`, bugs kept: the five
    non-HP stats are truncated to a byte, and the EV mask is shifted out
    before it's read.
  - Ties go to the player, then to the lower trainer id.
- **Each round:**
  - You choose two of your three.
  - The opponent picks its two by type-effectiveness points, using the
    "good" or "bad" mode by coin flip.
  - Opponents' IVs are always 3: the cartridge reads them with the
    tournament id.
- **Other matches** are decided on paper (`DecideRoundWinners`): move
  effectiveness points against each foe, a tenth of the base stats, a random
  0–31, and the seed.
  - The point totals are never reset between matches.
  - Levitate is scored as neutral by the "good" pick, and Wonder Guard is
    never recognised (both cartridge quirks).
- **Tucker** is in the final when he's due: the 4th and 9th championship,
  then every 5th. He wins every paper match and brings two of his three.
- **The streak** counts championships, and Battle Points are paid by that
  count.
- **The tourney tree and opponent card** are one plain text screen
  (`src/ui/Gen3DomeScreen.lua`).

**Not ported:**
- the "winning move" shown on the tree for each match
- the confetti (`DoDomeConfetti`)
- the battle recorder

**Checks:**
- `tools/emerald_battle_dome_check.lua`: 22 checks, or 24 with a
  pokeemerald checkout, which also compares the bracket tables against the
  source.
- The harness plays the Dome with
  `DOME=1 DOME_MENU_A=73 DOME_MENU_B=107 MAP=MAP_G26_N18 X=5 Y=11`. At each
  round's menu it opens the opponent card, then the tree, then continues.
- `STREAK=4 STREAKFAC=1` meets Tucker in the final.

## The Battle Tower's Multi Battle Rooms

The multis counter (`MAP_G26_N05`, attendant at (14,5)) now leads all the
way through. The partner room (`MAP_G26_N15`) has its candidates, one can be
chosen, and the seven battles are two against two with an AI partner. This
follows `battle_tower.c`.

- **The candidates** (`LoadMultiPartnerCandidatesData`, special 235 arm 10):
  - Six frontier trainers from the current challenge's range, none twice and
    no two of one facility class. Their sprites go in `VAR_OBJ_GFX_ID_0`–`5`.
  - Each has two Pokémon from its set, with the high tier only at Open Level.
    A second Pokémon never holds its first's item. None is a species already
    drawn or one of your two.
  - A quirk is kept: the very first candidate Pokémon is never checked
    against your two, because the cartridge's loop starts at the slot it is
    filling.
- **Talking to one** (`ShowPartnerCandidateMessage`, arm 11): their class's
  five lines from `sPartnerTrainerTextTables`, read out of the ROM.
  - The intro gives their name.
  - Two lines give each Pokémon's species and first move; the second ends
    "…be my tag team partner?"
  - Then yes or no.
- **Accepting:**
  - The partner and their two are kept.
  - Fourteen opponents are drawn, two per battle (the seventh pair from the
    hard range), never the partner.
  - Their slots overwrite the candidates', as on the cartridge.
- **Each battle:**
  - `SetNextFacilityOpponent` sets up the pair, each on their own sprite.
  - Both say their intro; `0x8005` picks the second.
  - `SetMultiPartnerGfx` (arm 14) dresses the partner (`VAR_OBJ_GFX_ID_E`).
- **The battle:**
  - Your two are on the left, and the partner's two beside them
    (`FillPartnerParty`: the challenge's level, the partner's fixed IVs).
  - The partner picks its own moves (`AllyAI`).
  - Across are the two trainers' two each. The second avoids the first's
    species and items, as `FillTrainerParty` does over the shared enemy
    party.
- **Battle Points:** the tower's table. Seven wins pay 3 BP.
- **The extractor** (`RomExtractorGen3:multiPartnerTexts`) finds the table from
  the LASS's intro and writes `partnerTexts` into `gen3_frontier_speech`
  (found at `5DD500`). Re-run `tools/gen3_frontier_speech_extract.lua` on an
  existing cache.

**Not ported:**
- the two extra candidates (a record-mixed apprentice and a friend's
  record)
- link multis

**Checks:**
- `tools/emerald_battle_tower_multi_check.lua`: 21 checks, or 22 with a
  pokeemerald checkout, which also checks every class in the table has
  lines.
- `tools/gen3_battle_tower_harness` with `MULTI=1 X=14 Y=6` plays the
  challenge: it talks to the candidate at (6,9), says yes, and plays seven
  pairs.

