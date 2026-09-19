-- FireRed port verification: interiors in the 3D view.
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
  local rooms = {
    { "MAP_G05_N04", 7, 6, "50_center" },
    { "MAP_G06_N03", 5, 5, "51_mart" },
    { "MAP_G04_N00", 5, 5, "52_house1f" },
    { "MAP_G04_N03", 6, 10, "53_oakslab" },
    { "MAP_G03_N00", 12, 10, "54_pallet" },
    { "MAP_G06_N02", 6, 9, "55_gym" },
  }
  for _, r in ipairs(rooms) do
    local ok, err = pcall(U.teleport, game, r[1], r[2], r[3], "up")
    if not ok then U.log("teleport failed", r[1], err) end
    U.wait(90)
    shot(r[4])
  end
  -- the OPTION screen: START, then down past BAG, name, SAVE
  U.tap(game, "start"); U.wait(15)
  for _ = 1, 3 do U.tap(game, "down"); U.wait(6) end
  U.tap(game, "a"); U.wait(30)
  shot("56_options")
  love.event.quit(0)
end
