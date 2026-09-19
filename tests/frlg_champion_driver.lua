-- Visible FireRed Champion regression. The player enters from Lance's room,
-- fights the starter-appropriate imported rival party, and earns the flag.
return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  local save = U.freshSave(game)
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "PSYCHIC", pp = 99, maxPp = 99 } }
  mon.hp, mon.maxHp = 322, 322
  save.party = { mon }
  save.flags.EVENT_BEAT_LORELEIS_ROOM_TRAINER_0 = true
  save.flags.EVENT_BEAT_BRUNOS_ROOM_TRAINER_0 = true
  save.flags.EVENT_BEAT_AGATHAS_ROOM_TRAINER_0 = true
  save.flags.EVENT_BEAT_LANCE = true
  U.teleport(game, "MAP_G01_N79", 3, 7, "up")
  local room = assert(require("data.scripts.init").get("CHAMPIONS_ROOM"))
  room.onEnter(game, game.overworld)
  for frame = 1, 10000 do
    if frame % 8 == 1 then U.tap(game, "a") else U.wait(1) end
    if save.flags.EVENT_BEAT_CHAMPION_RIVAL then
      U.log("PASS Champion battle and victory flag")
      love.event.quit(0)
      return
    end
  end
  error("Champion battle did not settle")
end
