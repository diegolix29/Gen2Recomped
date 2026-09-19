-- FireRed port verification: does the 3D card show the facing the player has?
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
  pcall(U.teleport, game, "MAP_G05_N04", 7, 6, "down")
  U.wait(90)
  U.wait(20)
  for _, dir in ipairs({ "up", "left", "right", "down" }) do
    U.hold(game, dir, 3); U.wait(20)
    local p = game.stack:top().player
    U.log("facing", p.facing, p.cellX, p.cellY)
    shot("60_face_" .. dir)
  end
  love.event.quit(0)
end
