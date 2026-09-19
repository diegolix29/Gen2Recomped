-- FireRed port verification: the SELL flow, in isolation.
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
  U.wait(20)
  U.newGame(game)
  U.wait(30)
  game.save.money = 3000
  local Bag = require("src.inventory.Bag")
  pcall(Bag.add, game.save, "POTION", 5, game.data)
  pcall(Bag.add, game.save, "ANTIDOTE", 2, game.data)

  pcall(U.teleport, game, "MAP_G06_N03", 4, 3, "left")
  U.wait(60)
  U.hold(game, "left", 6); U.wait(12)
  for i = 1, 4 do U.tap(game, "a"); U.wait(30) end
  shot("88_menu")
  U.tap(game, "down"); U.wait(15)
  shot("89_sell_selected")
  U.tap(game, "a"); U.wait(50)
  shot("8a_sell_screen")
  U.tap(game, "a"); U.wait(30)   -- pick POTION (first sellable row)
  shot("8b_sell_qty")
  U.tap(game, "a"); U.wait(30)   -- confirm quantity (1)
  shot("8c_sell_confirm")
  U.tap(game, "a"); U.wait(60)   -- YES
  shot("8d_sell_done")
  U.tap(game, "a"); U.wait(40)
  shot("8e_sell_done2")
  love.event.quit(0)
end
