-- FireRed port verification: the bag, its three pockets, icons and TM CASE.
return function(game)
  local U = require("tests.drivers.util")
  local Bag = require("src.inventory.Bag")
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
  for id, n in pairs({ POTION = 3, ANTIDOTE = 1, POKE_BALL = 5, GREAT_BALL = 2,
                       TM_CASE = 1, BERRY_POUCH = 1, TOWN_MAP = 1,
                       ORAN_BERRY = 4, TM01 = 1, HM01 = 1 }) do
    local ok, err = pcall(Bag.add, game.save, id, n, game.data)
    if not ok then U.log("add failed", id, err) end
  end
  U.tap(game, "start"); U.wait(12)
  U.tap(game, "a"); U.wait(20)
  shot("20_bag_items")
  U.tap(game, "down"); U.wait(8)
  shot("21_bag_items_row2")
  U.tap(game, "right"); U.wait(15)
  shot("22_bag_key")
  U.tap(game, "right"); U.wait(15)
  shot("23_bag_balls")
  U.tap(game, "left"); U.wait(15)
  -- TM CASE is the second key item (TOWN MAP was added first)
  U.tap(game, "down"); U.wait(6)
  U.tap(game, "a"); U.wait(20)
  shot("24_tm_case")
  U.log("FRLG bag shots done")
  love.event.quit(0)
end
