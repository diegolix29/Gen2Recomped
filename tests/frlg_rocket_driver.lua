-- FireRed Team Rocket progression smoke: Game Corner entrance, Rocket
-- Hideout key/barrier/boss rewards, and Silph Co card key/rival/boss rewards.
return function(game)
  local U = require("tests.drivers.util")
  local G = require("src.script.Gen3Commands")
  local Pokemon = require("src.pokemon.Pokemon")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local function busy()
    local ow = game.overworld
    return game.stack:top() ~= ow
      or (ow.runner and ow.runner:isRunning())
      or #(ow.scriptMoves or {}) > 0 or ow.engaging or ow.emote ~= nil
      or ow.transitioning or ow.player.moving
  end

  local function settle(limit)
    for frame = 1, limit or 18000 do
      if not busy() then return frame end
      if frame % 10 == 1 then
        local top = game.stack:top()
        -- Gift nickname prompts default to NO; battle/menu A presses continue.
        U.tap(game, getmetatable(top) == ChoiceBox and "b" or "a")
      else
        U.wait(1)
      end
    end
    error("Team Rocket script did not settle")
  end

  local function script(label, tag)
    assert(game.overworld:gen3RunFieldScript(label, tag), "could not start " .. label)
    -- Field scripts start on the next overworld update.
    U.wait(2)
    settle()
  end

  local function strongSave()
    local save = U.freshSave(game)
    local mon = Pokemon.new(game.data, "MEWTWO", 100)
    mon.moves = {{id="PSYCHIC", pp=99, maxPp=99}}
    save.party = {mon}
    return save
  end

  U.wait(20)
  local save = strongSave()

  -- The poster grunt leaves, then the actual poster interaction opens and
  -- redraws the staircase into the Hideout.
  U.teleport(game, "MAP_G10_N14", 11, 3, "up")
  script("S016CAF5", "game-corner-grunt")
  U.teleport(game, "MAP_G10_N14", 11, 2, "up")
  U.tap(game, "a"); settle()
  assert(save.flags[G.flagKey(0x26D)], "Game Corner poster did not open Hideout")
  assert(U.shot(game, "ngshots/rocket_game_corner_open.png"))
  U.log("PASS Rocket", "Game Corner entrance")

  -- B4F: defeat the key holder and collect the dropped Lift Key.
  U.teleport(game, "MAP_G01_N45", 4, 3, "up")
  script("S0161381", "lift-key-grunt")
  script("S01613AD", "lift-key")
  assert(save.flags[G.flagKey(0x2A5)], "Lift Key permission flag missing")
  assert((save.inventory.LIFT_KEY or 0) == 1, "Lift Key missing")

  -- Exercise both B4F guard continuations before Giovanni.
  script("S01613CE", "door-grunt-left")
  script("S0161418", "door-grunt-right")
  local beaten = {}
  for key, value in pairs(save.flags or {}) do
    if value and tostring(key):match("^FLAG_G3_0[56]") then beaten[#beaten + 1] = key end
  end
  table.sort(beaten)
  U.log("trainer flags near hideout", table.concat(beaten, ","))
  U.log("barrier cells", game.overworld.map:isWalkableCell(17,12),
    game.overworld.map:isWalkableCell(18,12), game.overworld.map:isWalkableCell(17,13),
    game.overworld.map:isWalkableCell(18,13), game.overworld.map:isWalkableCell(17,14),
    game.overworld.map:isWalkableCell(18,14))
  assert(U.shot(game, "ngshots/rocket_hideout_guards_done.png"))

  script("S0161317", "hideout-giovanni")
  script("S0161363", "silph-scope")
  assert((save.inventory.SILPH_SCOPE or 0) == 1, "Silph Scope missing")
  U.log("PASS Rocket", "Hideout key, guards, Giovanni, Silph Scope")

  -- Silph 5F's real item-ball script grants the Card Key.
  U.teleport(game, "MAP_G01_N51", 22, 20, "down")
  U.tap(game, "a"); settle()
  assert((save.inventory.CARD_KEY or 0) == 1, "Silph Card Key missing")
  U.log("PASS Rocket", "Silph Card Key")

  -- Landing on the real 7F trigger runs the rival scene. The employee then
  -- grants Lapras and the driver declines only the nickname prompt.
  U.teleport(game, "MAP_G01_N53", 2, 4, "down")
  settle()
  assert(G.getVar(save, 0x405C) == 1, "Silph rival scene did not complete")
  script("S0161AC8", "silph-lapras")
  assert(save.flags[G.flagKey(0x246)], "Lapras gift flag missing")
  local foundLapras = false
  for _, mon in ipairs(save.party or {}) do if mon.species == "LAPRAS" then foundLapras = true end end
  assert(foundLapras, "Lapras was not added to the party")

  -- The 11F trigger runs Giovanni's full approach/battle/departure. After it,
  -- the president awards the one-time Master Ball.
  U.teleport(game, "MAP_G01_N57", 5, 15, "up")
  settle()
  assert(G.getVar(save, 0x4060) == 1, "Silph Giovanni scene did not complete")
  U.teleport(game, "MAP_G01_N57", 9, 10, "up")
  U.tap(game, "a"); settle()
  assert((save.inventory.MASTER_BALL or 0) == 1, "Master Ball missing")
  assert(save.flags[G.flagKey(0x250)], "Master Ball reward flag missing")
  assert(U.shot(game, "ngshots/rocket_silph_complete.png"))
  U.log("PASS Rocket", "Silph rival, Lapras, Giovanni, Master Ball")
  U.log("PASS Team Rocket progression")
  love.event.quit(0)
end
