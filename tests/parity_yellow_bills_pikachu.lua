-- Yellow starts Bill's House with Pikachu's confused reaction.  The map
-- script owns that one-shot, while PikachuFollower owns the movement.

package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("parity Yellow Bill's Pikachu")
local check = S.check

local entered = 0
local originalFollower = package.loaded["src.world.PikachuFollower"]
package.loaded["src.world.PikachuFollower"] = {
  onBillsHouseEnter = function()
    entered = entered + 1
  end,
}

local story = dofile("data/scripts/story.lua")
local game = { save = { flags = {} } }
story.BILLS_HOUSE.onEnter(game, {})
check(entered == 1,
  "entering Bill's House before meeting Bill starts Pikachu's reaction")

entered = 0
game.save.flags.EVENT_MET_BILL_2 = true
story.BILLS_HOUSE.onEnter(game, {})
check(entered == 0,
  "Pikachu's Bill reaction does not replay after Bill is met")

package.loaded["src.world.PikachuFollower"] = originalFollower

local GameVersion = require("src.core.GameVersion")
local PikachuFollower = require("src.world.PikachuFollower")
GameVersion.set("yellow")

local npc = {
  pikachuFollower = true, cellX = 3, cellY = 8, px = 48, py = 128,
  facing = "up",
}
local moves = {}
local yellowGame = {
  save = { flags = {} },
  data = {
    pokemon = { PIKACHU = { spriteFront = "pikachu.png" } },
    field = { emotionBubbles = {
      bubbles = {
        { name = "QUESTION_BUBBLE" }, { name = "EXCLAMATION_BUBBLE" },
      },
    } },
  },
}
local ow = {
  map = { id = "BILLS_HOUSE" }, npcs = { npc }, entities = { npc },
  player = { cellX = 3, cellY = 7 },
  scriptMove = function(_, entity, dir, tiles, onDone)
    moves[#moves + 1] = { entity = entity, dir = dir, tiles = tiles,
                           onDone = onDone }
  end,
}

PikachuFollower.onBillsHouseEnter(yellowGame, ow)
check(ow.pikachuBillsScene and #moves == 1
      and moves[1].entity == npc and moves[1].dir == "right"
      and moves[1].tiles == 3,
  "Bill's House entry parks Pikachu and walks it to Bill")
moves[1].onDone()
check(#moves == 2 and moves[2].dir == "up" and moves[2].tiles == 1,
  "Pikachu finishes its cartridge entry route beside Bill")
moves[2].onDone()
check(ow.emote and ow.emote.bubble == 1,
  "Pikachu shows its confused reaction after reaching Bill")

-- BillsHouseScript3 seeds hl with ..._EnterCellSeparatorDown and only swaps
-- in ..._EnterCellSeparatorNotDown on the facing-down fallthrough, so the
-- table names are inverted relative to the branch that picks them: facing
-- down takes the five-step detour, every other facing walks straight up
-- (pokeyellow scripts/BillsHouse.asm:100-133) (#455).
ow.player.facing = "down"
PikachuFollower.onBillEnteredMachine(yellowGame, ow)
check(#moves == 3 and moves[3].dir == "up" and moves[3].tiles == 1,
  "facing down, Pikachu starts the long way round the cell separator")
moves[3].onDone()
check(#moves == 4 and moves[4].dir == "left" and moves[4].tiles == 1,
  "the detour steps aside before climbing")
moves[4].onDone()
check(#moves == 5 and moves[5].dir == "up" and moves[5].tiles == 2,
  "the detour climbs past the separator")
moves[5].onDone()
check(#moves == 6 and moves[6].dir == "right" and moves[6].tiles == 1,
  "the detour steps back in beside it")
moves[6].onDone()
check(ow.emote and ow.emote.bubble == 1 and npc.facing == "up",
  "Pikachu looks up and wonders at the cell separator")

-- the other branch: any non-down facing takes the straight three-step route
local before = #moves
ow.player.facing = "up"
PikachuFollower.onBillEnteredMachine(yellowGame, ow)
check(#moves == before + 1 and moves[before + 1].dir == "up"
      and moves[before + 1].tiles == 3,
  "facing up, Pikachu walks straight to the cell separator")
moves[before + 1].onDone()

npc.goalX, npc.goalY = 9, 9
PikachuFollower.update(yellowGame, ow)
check(npc.goalX == 9 and npc.goalY == 9,
  "Pikachu stays parked in Bill's House during the scene")

PikachuFollower.onBillExitedMachine(yellowGame, ow)
check(ow.emote and ow.emote.bubble == 2 and npc.facing == "left",
  "Pikachu reacts when Bill comes back out")

GameVersion.set("red")
S.finish()
