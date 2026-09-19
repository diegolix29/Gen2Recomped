-- FireRed port verification, part 2: party + a wild battle, captured.
return function(game)
  local U = require("tests.drivers.util")
  local function shot(name)
    game.capturePath = "frlg_" .. name .. ".png"
    for _ = 1, 120 do
      if not game.capturePath then break end
      coroutine.yield()
    end
    U.wait(2)
  end
  local function try(label, fn)
    local ok, err = pcall(fn)
    if not ok then U.log("FAIL " .. label .. ": " .. tostring(err)) end
    return ok
  end

  U.wait(20)
  U.newGame(game)
  U.wait(30)

  local Pokemon = require("src.pokemon.Pokemon")
  try("give CHARMANDER", function()
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 12))
  end)

  U.tap(game, "start"); U.wait(12)
  shot("10_start_with_party")
  U.tap(game, "a"); U.wait(20)
  shot("11_party")
  U.tap(game, "a"); U.wait(10)
  shot("12_party_submenu")
  U.tap(game, "b"); U.wait(8)
  U.tap(game, "b"); U.wait(10)
  U.tap(game, "b"); U.wait(10)

  try("teleport ROUTE_1", function() U.teleport(game, "MAP_G03_N19", 5, 5, "down") end)
  U.wait(20)
  shot("13_route")

  local started = try("start wild battle", function()
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(game, "PIDGEY", 3)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
  end)
  if started then
    for i = 1, 16 do
      U.wait(45)
      shot(("14_battle_t%d"):format(i))
      U.log("battle top:", tostring(game.stack:top() and (game.stack:top().name or game.stack:top().__name or game.stack:top())))
      U.tap(game, "a")
    end
    shot("15_battle_menu")
    U.tap(game, "a"); U.wait(12)
    shot("16_battle_moves")
    U.tap(game, "b"); U.wait(8)
    U.tap(game, "right"); U.wait(6)
    U.tap(game, "a"); U.wait(15)
    shot("17_battle_bag")
    U.tap(game, "b"); U.wait(10)
    U.tap(game, "down"); U.wait(6)
    U.tap(game, "a"); U.wait(15)
    shot("18_battle_party")
  end
  U.log("FRLG battle shots done")
  love.event.quit(0)
end
