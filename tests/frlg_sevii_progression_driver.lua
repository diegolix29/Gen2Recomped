-- FireRed Sevii special-event and Trainer Tower regression.
return function(game)
  local U = require("tests.drivers.util")
  local G = require("src.script.Gen3Commands")
  local Pokemon = require("src.pokemon.Pokemon")
  local S, base = G.SPECIALS, 0x1000
  local save = U.freshSave(game)
  local function special(n) return assert(S[base + n], "missing FireRed special " .. n) end
  local blastoise = Pokemon.new(game.data, "BLASTOISE", 100)
  blastoise.friendship, blastoise.happiness = 255, 255
  save.party = { blastoise }
  assert(special(419)({ game = game, save = save, overworld = game.overworld }) == 1)
  assert(G.getVar(save, 0x8005) == 17, "Cape Brink selected the wrong tutor")
  special(420)({ game = game, save = save, overworld = game.overworld })
  assert(save.flags[G.flagKey(0x2E0)], "Cape Brink reward flag was not set")
  save.pokedex = { seen = { PIKACHU = true } }
  special(349)({ game = game, save = save, overworld = game.overworld })
  assert(G.getVar(save, 0x4036) ~= 0 and G.getVar(save, 0x403B) ~= 0,
    "Resort Gorgeous did not select a request and reward")
  for _ = 1, 11 do
    G.setVar(save, 0x4026, 0)
    special(427)({ game = game, save = save, overworld = game.overworld })
  end
  assert(save.flags[G.flagKey(0x848)], "Birth Island did not awaken Deoxys")
  U.teleport(game, "MAP_G01_N111", 8, 3, "down")
  save.flags[G.flagKey(1)], save.flags[G.flagKey(2)] = true, true
  special(309)({ game = game, save = save, overworld = game.overworld })
  G.setVar(save, 0x8005, 0)
  G.setVar(save, 0x8004, 6)
  special(404)({ game = game, save = save, overworld = game.overworld })
  for n = 1, 8 do
    U.teleport(game, ("MAP_G02_N0%d"):format(n), 4, 8, "up")
    G.setVar(save, 0x8004, 0)
    special(404)({ game = game, save = save, overworld = game.overworld })
    assert(G.getVar(save, G.VAR_RESULT) <= 2, "Trainer Tower floor did not initialize")
    G.setVar(save, 0x8004, 4)
    special(404)({ game = game, save = save, overworld = game.overworld })
  end
  G.setVar(save, 0x8004, 9)
  special(404)({ game = game, save = save, overworld = game.overworld })
  G.setVar(save, 0x8004, 8)
  special(404)({ game = game, save = save, overworld = game.overworld })
  assert(save.frlgTrainerTower and save.frlgTrainerTower.receivedPrize[1],
    "Trainer Tower did not award its prize")
  U.log("PASS Sevii events and Trainer Tower")
  love.event.quit(0)
end
