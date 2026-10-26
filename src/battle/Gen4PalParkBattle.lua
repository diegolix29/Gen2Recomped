-- A CATCHING SHOW BATTLE (BATTLE_TYPE_PAL_PARK; src/world/Gen4PalPark.lua).
--
-- The Safari Zone's battle with two of its four buttons gone: the bottom
-- screen is one big BALL and RUN (BattleSubscreen_SetupBackground 9 / 10), the
-- prompt is "What will <player> do?", and the thrown ball is the Pokemon's own
-- (MON_DATA_POKEBALL -- battle_lib.c), which always holds: the catch skips the
-- nickname and the Pokedex (SEQ_CATCH_MON_DONE) and the Pokemon is not added
-- to the party -- the lobby boxes all six afterwards.

local Strings = require("src.core.Strings")

local M = {}

M.SHAKES = 3

local function ballOf(battle)
  local mon = battle.enemy and battle.enemy.mon
  if mon and mon.ball then return mon.ball end
  for id, def in pairs(battle.data.items or {}) do
    if type(id) == "number" and def.name and def.name:upper():gsub("[^%w]", "") == "POKEBALL" then return id end
  end
  return 4
end

-- the menu walk: the middle row is not there, so up and down cross it
function M.skipRow(battle, dir)
  if battle.menuIndex == 2 or battle.menuIndex == 3 then
    battle.menuIndex = (dir == "up") and 1 or 4
  end
end

-- bank 368's own Pal Park strings (BattleStrings_Text_ParkBalls ...)
M.TEXT = { boxTitle = 1220, boxLeft = 1221, whatWill = 1222, ball = 1223, run = 1224 }

function M.text(battle, key, ...)
  return require("src.battle.Gen4Safari").text(battle.data, M.TEXT[key], ...)
end

function M.labels(battle)
  return { M.text(battle, "ball") or Strings("BALL"), "", "", M.text(battle, "run") or Strings("RUN") }
end

function M.action(battle, choice)
  if choice ~= "ball" and choice ~= "run" then return end
  local G = require("src.battle.Gen4Safari")
  local st = battle.safari
  local who = battle.game.save.player.name
  local foe = battle.enemy.name
  battle.phase = "messages"
  battle.afterQueue = "menu"
  if choice == "run" then
    require("src.core.Sound").play(battle.data, "Run")
    battle:say(G.text(battle.data, G.TEXT.gotAway) or Strings("Got away safely!"))
    battle.result = "run"
    battle.afterQueue = "finish"
    return
  end
  st.balls = math.max(0, (st.balls or 0) - 1)
  local ball = ballOf(battle)
  local def = battle:itemDef(ball)
  battle:say(Strings("%s threw a\n%s!", who, (def and def.name) or "BALL"))
  battle:act(function()
    require("src.core.Sound").play(battle.data, "Ball_Toss")
    battle.lastBall = ball
    battle:ballChain(battle:tossAnimFor(ball), true, M.SHAKES, ball)
    battle:actNext(function() require("src.core.Sound").play(battle.data, "Caught_Mon") end)
    battle:sayNext(Strings("Gotcha!\n%s was caught!", foe))
    battle:actNext(function()
      battle.result = "caught"
      battle.afterQueue = "finish"
    end)
  end)
end

return M
