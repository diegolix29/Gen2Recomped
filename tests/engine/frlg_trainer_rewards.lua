-- FireRed trainer-loss/reward regressions.  A whiteout must not resume the
-- map script, Route 22's early rival must remain available after a loss, and
-- the first TM/HM must create the TM CASE just like AddBagItem does in FRLG.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Commands = require("src.script.Commands")
local G3 = require("src.script.Gen3Commands")
local Bag = require("src.inventory.Bag")
local ItemEffects = require("src.inventory.ItemEffects")
local TeachyTV = require("src.ui.Gen3TeachyTV")
local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")

local savedVersion = GameVersion.get()
GameVersion.set("firered")

local data = {
  constants = {
    trainerOrder = { [1] = "TEST_TRAINER" },
    gen3TrainerFlagBase = 0x500,
    gen3Bag = { pockets = { ITEM = 42, KEY_ITEM = 30, BALL = 13,
                             TM_HM = 58, BERRIES = 43 } },
  },
  items = {
    TM39 = { pocket = "TM_HM", machine = { kind = "TM", move = "ROCK_TOMB" } },
    TM03 = { pocket = "TM_HM", machine = { kind = "TM", move = "WATER_PULSE" } },
    TM_CASE = { pocket = "KEY_ITEM", keyItem = true },
  },
}

local originalStartBattle = Commands.start_battle
local forcedResult = "lose"
Commands.start_battle = function(ctx)
  ctx.lastBattleResult = forcedResult
end

local function context()
  return {
    save = { flags = {}, inventory = {}, bagOrder = {}, party = {}, gen3Vars = {} },
    game = { data = data },
  }
end

-- Ordinary trainer/gym loss: CB2_EndTrainerBattle whites out instead of
-- returning to the bytes after trainerbattle.
local normal = context()
local result = Commands.g3_trainer_battle(normal, 0, 1, "WIN_SCRIPT", nil, nil, "DEFEAT")
T.eq(result, "end", "ordinary trainer loss ends the event script")
T.eq(normal.save.flags.FLAG_G3_0501, nil,
  "ordinary trainer loss does not set the trainer-beaten flag")

-- No-intro rival fights (Cerulean/Tower/Anne/Silph/late Route 22) are kind 3.
local noIntro = context()
T.eq(Commands.g3_trainer_battle(noIntro, 3, 1, nil, nil, nil, "DEFEAT"), "end",
  "no-intro rival loss ends the event script instead of running the exit scene")

-- Early Route 22 rival has flags=0.  Retail whites out and does NOT mark him
-- fought, so the player can challenge him again.
local route22 = context()
Commands.g3_trainer_battle(route22, 9, 1, nil, nil, 0, "DEFEAT")
T.eq(route22.save.flags.FLAG_G3_0501, nil,
  "Route 22 early-rival loss leaves the trainer flag clear")

-- Oak's Lab uses RIVAL_BATTLE_TUTORIAL (3), whose low bit is HEAL_AFTER.
-- That special loss continues the script and *does* mark the rival fought.
local oak = context()
Commands.g3_trainer_battle(oak, 9, 1, nil, nil, 3, "DEFEAT")
T.eq(oak.save.flags.FLAG_G3_0501, true,
  "Oak tutorial-rival loss marks the trainer fought")

Commands.start_battle = originalStartBattle

-- FireRed AddBagItem creates the case as part of adding the first TM/HM.
local save = { inventory = {}, bagOrder = {} }
T.eq(Bag.add(save, "TM39", 1, data), true, "first FireRed TM can be added")
T.eq(save.inventory.TM39, 1, "the first TM is actually stored")
T.eq(save.inventory.TM_CASE, 1, "the first TM automatically creates the TM CASE")
T.eq(Bag.add(save, "TM03", 1, data), true, "later FireRed TM can be added")
T.eq(save.inventory.TM_CASE, 1, "later TMs do not duplicate the TM CASE")

local legacy = { inventory = { TM39 = 1 }, bagOrder = { "TM39" } }
T.eq(Bag.repairFireRedTMCase(legacy, data), true,
  "legacy FireRed save with a TM repairs the missing TM CASE")
T.eq(legacy.inventory.TM_CASE, 1,
  "legacy FireRed repair actually stores the TM CASE")
local caseRows = 0
for _, id in ipairs(legacy.bagOrder) do if id == "TM_CASE" then caseRows = caseRows + 1 end end
T.eq(caseRows, 1, "legacy FireRed repair adds TM CASE to bag order once")
T.eq(Bag.repairFireRedTMCase(legacy, data), false,
  "legacy FireRed TM CASE repair is idempotent")

local noMachine = { inventory = { POTION = 1 }, bagOrder = { "POTION" } }
T.eq(Bag.repairFireRedTMCase(noMachine, data), false,
  "FireRed save without a machine is not changed by the repair")
T.eq(noMachine.inventory.TM_CASE, nil,
  "FireRed save without a machine does not gain a TM CASE")

local persisted = {
  inventory = { TM_CASE = 1, TM39 = 1 },
  flags = { FLAG_G3_0820 = true },
  bagOrder = { "TM_CASE", "TM39" },
}
local roundTrip = assert(SaveData.decode(assert(SaveData.encode(persisted))))
T.eq(roundTrip.inventory.TM_CASE, 1,
  "TM CASE survives save serialization and reload")
T.eq(roundTrip.flags.FLAG_G3_0820, true,
  "FireRed badge flag survives save serialization and reload")

-- The Teachy TV is an active field key item.  Retail hides the two TM/REGISTER
-- lessons until the TM CASE exists.
data.items.TEACHY_TV = { pocket = "KEY_ITEM", keyItem = true, name = "TEACHY TV" }
local tvSave = { inventory = {}, bagOrder = {}, player = { name = "RED" } }
local tvResult = ItemEffects.use(data, tvSave, "TEACHY_TV", nil, nil, nil, nil)
T.eq(tvResult, "teachy_tv", "Teachy TV use opens its field screen")
T.eq(#TeachyTV.entries(tvSave), 5,
  "Teachy TV has four lessons plus cancel before the TM CASE")
tvSave.inventory.TM_CASE = 1
T.eq(#TeachyTV.entries(tvSave), 7,
  "Teachy TV adds TM and REGISTER lessons after the TM CASE exists")
local battleResult = ItemEffects.use(data, tvSave, "TEACHY_TV", nil, {}, nil, nil)
T.eq(battleResult, "failed", "Teachy TV still refuses use during battle")

GameVersion.set(savedVersion)
T.finish("frlg trainer rewards")
