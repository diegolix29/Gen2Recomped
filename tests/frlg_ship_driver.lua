-- POKEPORT_DRIVER=tests/frlg_ship_driver.lua, mods off, FireRed imported.
return function(game)
  local U = require("tests.drivers.util")
  local G = require("src.script.Gen3Commands")
  U.wait(20)
  local save = U.freshSave(game)
  save.party = {require("src.pokemon.Pokemon").new(game.data, "CHARIZARD", 60)}
  G.setVar(save, 0x407E, 1)
  U.teleport(game, "MAP_G01_N04", 33, 6, "down")
  local shots = {[180]=true, [480]=true, [900]=true, [1200]=true}
  local sawWake, sawSmoke = false, false
  for i=1,2200 do
    U.wait(1)
    if shots[i] then
      assert(U.shot(game, "ngshots/ship_fx_verify_" .. i .. ".png"))
    end
    local fx = game.overworld.ssAnneDepartureFx
    if fx and not sawWake and (fx.wakeAge or 0) >= 12 then
      assert(U.shot(game, "ngshots/ship_fx_wake.png"))
      sawWake = true
    end
    if fx and not sawSmoke then
      for _, puff in ipairs(fx.smoke or {}) do
        if (puff.age or 0) >= 30 then
          assert(U.shot(game, "ngshots/ship_fx_smoke.png"))
          sawSmoke = true
          break
        end
      end
    end
    if game.overworld.map.id == "MAP_G03_N05" and not game.overworld.runner:isRunning() then
      assert(G.getVar(save, 0x407E) == 2, "departure story state did not advance")
      assert(sawWake, "departure never rendered its wake")
      assert(sawSmoke, "departure never rendered a smoke puff")
      assert(U.shot(game, "ngshots/ship_fx_verify_return.png"))
      U.log("PASS departure completed and returned to Vermilion", i)
      love.event.quit(0)
      return
    end
  end
  error("departure did not finish within 2200 frames")
end
