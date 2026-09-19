-- FireRed port verification: the buy screen, and where a whiteout lands.
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
  local function where(tag)
    local ow = game.overworld
    U.log(tag, ow and ow.map and ow.map.id, ow and ow.player.cellX, ow and ow.player.cellY)
  end
  U.wait(20)
  U.newGame(game)
  U.wait(30)
  game.save.money = 3000

  -- a fresh save whites out at home
  game.overworld:warpToHealPoint(nil, { whiteout = true })
  U.wait(120)
  where("whiteout fresh")
  shot("80_whiteout_home")

  -- the Center sets the respawn on entry; a whiteout then lands at its nurse
  pcall(U.teleport, game, "MAP_G05_N04", 7, 6, "up")
  U.wait(60)
  U.log("respawn index", game.save.gen3RespawnIndex)
  pcall(U.teleport, game, "MAP_G03_N01", 20, 20, "down")
  U.wait(60)
  game.overworld:warpToHealPoint(nil, { whiteout = true })
  U.wait(120)
  where("whiteout after center")
  shot("81_whiteout_center")

  -- Pewter Mart: talk, BUY, browse
  pcall(U.teleport, game, "MAP_G06_N03", 4, 3, "left")
  U.wait(60)
  U.hold(game, "left", 6); U.wait(12)
  for i = 1, 5 do U.tap(game, "a"); U.wait(30) end
  shot("82_shop_menu")
  U.tap(game, "a"); U.wait(40)
  shot("83_buy_screen")
  U.tap(game, "down"); U.wait(15)
  shot("84_buy_potion")
  U.tap(game, "a"); U.wait(30)
  shot("85_buy_quantity")
  love.event.quit(0)
end
