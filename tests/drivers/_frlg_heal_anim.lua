-- FireRed port verification: the Pokemon Center healing machine, frame by frame.
return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  local function shot(name)
    game.capturePath = "frlg_" .. name .. ".png"
    for _ = 1, 120 do
      if not game.capturePath then break end
      coroutine.yield()
    end
  end
  U.wait(20)
  U.newGame(game)
  U.wait(30)
  -- undo the six zoom-out presses an earlier capture saved into the options
  -- (camera zoom is the player's own setting: never pressed here)
  for i = 1, 3 do
    local m = Pokemon.new(game.data, "PIDGEY", 5 + i)
    m.hp = 1
    table.insert(game.save.party, m)
  end
  pcall(U.teleport, game, "MAP_G05_N04", 7, 4, "up")
  U.wait(60)
  U.hold(game, "up", 6); U.wait(12)
  -- talk, then keep pressing A until the machine starts; capture densely
  local n = 0
  for i = 1, 1600 do
    if i % 30 == 1 and not (game.overworld and game.overworld.healAnim) then U.tap(game, "a") end
    coroutine.yield()
    local ow = game.overworld
    if ow and ow.healAnim and n < 12 then
      if i % 8 == 0 then
        n = n + 1
        shot(("70_machine_%02d"):format(n))
      end
    end
  end
  U.log("machine shots", n, "hp", game.save.party[1].hp)
  love.event.quit(0)
end
