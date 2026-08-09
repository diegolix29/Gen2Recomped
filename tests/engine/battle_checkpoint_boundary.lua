-- Battle checkpoints are exposed only at a settled, reconstructable player
-- decision boundary. This suite is ROM-free and exercises the public engine
-- checkpoint capability against the fixture battle implementation.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("battle checkpoint boundary")
local Fixtures = require("tests.modkit").fixtures
local BattleState = require("src.battle.BattleState")
local Checkpoint = require("src.core.Checkpoint")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")

local Data = Fixtures.fresh()

local function makeGame()
  local save = SaveData.newGame()
  save.meta.playthroughId = "battle-playthrough"
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local overworld = {
    map = { id = save.player.map },
    player = {
      cellX = save.player.x, cellY = save.player.y,
      facing = save.player.facing, surfing = false,
    },
    runner = { isRunning = function() return false end },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {}, scriptMoves = {},
  }
  local game = { data = Data, save = save, stack = stack, overworld = overworld }
  stack.states[1] = overworld
  local battle = BattleState.newWild(game, "FIXMON_B", 12)
  battle.phase = "menu"
  battle.queue = {}
  battle.checkpointOrigin = { kind = "wild_encounter" }
  battle.onFinish = function() end
  stack.states[2] = battle
  return game, overworld, battle
end

local game, overworld, battle = makeGame()
T.same(Checkpoint.inspect(game), {
  canCapture = true, canRestore = true, kind = "battle",
}, "settled standard wild battle is a checkpoint boundary")

local function refused(mutator, code, label)
  local game2, ow2, battle2 = makeGame()
  mutator(game2, ow2, battle2)
  local capability = Checkpoint.inspect(game2)
  T.check(capability.canCapture == false and capability.reason == code,
    label .. ": " .. tostring(capability.reason))
end

refused(function(_, _, b) b.phase = "messages" end,
  "battle_phase_busy", "message phase is rejected")
refused(function(_, _, b) b.queue = { { text = "busy" } } end,
  "battle_phase_busy", "nonempty action queue is rejected")
refused(function(_, _, b) b.waitFrames = 1 end,
  "battle_phase_busy", "partial wait is rejected")
refused(function(_, _, b) b.enemy.mon.hp = b.enemy.mon.hp - 1 end,
  "battle_phase_busy", "unfinished HP display synchronization is rejected")
refused(function(_, _, b) b.player.mustRecharge = true end,
  "battle_phase_busy", "automatic locked action is rejected")
refused(function(_, ow) ow.runner = { isRunning = function() return true end } end,
  "script_busy", "suspended script beneath battle is rejected")
refused(function(_, _, b) b.checkpointOrigin = nil end,
  "battle_origin_unsupported", "unknown completion closure is rejected")
refused(function(_, _, b) b.safari = { balls = 30, steps = 10 } end,
  "battle_variant_unsupported", "Safari battle is rejected")
refused(function(_, _, b) b.ghost = true end,
  "battle_variant_unsupported", "ghost battle is rejected")
refused(function(_, _, b) b.demo = true end,
  "battle_variant_unsupported", "old-man demo is rejected")
refused(function(_, _, b) b.kind = "link" end,
  "link_battle_unsupported", "link battle is rejected")

-- Ordinary overworld behavior remains unchanged by the battle branch.
game.stack.states[2] = nil
T.same(Checkpoint.inspect(game), {
  canCapture = true, canRestore = true, kind = "overworld",
}, "settled overworld remains supported")

T.finish()
