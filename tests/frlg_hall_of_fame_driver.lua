-- Visible FireRed Hall of Fame handoff. Save writes are vetoed so this can
-- exercise the ceremony without changing the player's real save file.
return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  game.writeSave = function() return false end
  local save = U.freshSave(game)
  save.party = { Pokemon.new(game.data, "MEWTWO", 100) }
  save.pendingHallOfFame = true
  U.teleport(game, "MAP_G01_N80", 4, 7, "up")
  local room = assert(require("data.scripts.init").get("HALL_OF_FAME"))
  room.onEnter(game, game.overworld)
  for frame = 1, 6000 do
    if frame % 8 == 1 then U.tap(game, "a") else U.wait(1) end
    if save.pendingHallOfFame == false and #(save.hallOfFame or {}) == 1 then
      U.log("PASS Hall of Fame induction")
      love.event.quit(0)
      return
    end
  end
  error("Hall of Fame induction did not start")
end
