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

ow.player.facing = "down"
PikachuFollower.onBillEnteredMachine(yellowGame, ow)
check(#moves == 3 and moves[3].dir == "up" and moves[3].tiles == 3,
  "Pikachu walks to the cell separator after Bill enters it")
moves[3].onDone()
check(ow.emote and ow.emote.bubble == 1,
  "Pikachu wonders at the cell separator")

npc.goalX, npc.goalY = 9, 9
PikachuFollower.update(yellowGame, ow)
check(npc.goalX == 9 and npc.goalY == 9,
  "Pikachu stays parked in Bill's House during the scene")

PikachuFollower.onBillExitedMachine(yellowGame, ow)
check(ow.emote and ow.emote.bubble == 2 and npc.facing == "left",
  "Pikachu reacts when Bill comes back out")

GameVersion.set("red")
S.finish()
