-- Real leader interactions and battles, with a strong party to keep runs short.
-- GYM_ONLY=Brock (optional). POKEPORT_SPEED=8 is suitable for this driver.
return function(game)
  local U = require("tests.drivers.util")
  local G = require("src.script.Gen3Commands")
  local Pokemon = require("src.pokemon.Pokemon")
  local gyms = {
    {"Brock", "MAP_G06_N02", 6,5, "TM39", 0x254},
    {"Misty", "MAP_G07_N05", 8,6, "TM03", 0x297},
    {"Surge", "MAP_G09_N06", 5,2, "TM34", 0x231},
    {"Erika", "MAP_G10_N16", 6,4, "TM19", 0x293},
    {"Koga", "MAP_G11_N03", 7,13, "TM06", 0x259},
    {"Sabrina", "MAP_G14_N03", 14,11, "TM04", 0x29A},
    {"Blaine", "MAP_G12_N00", 5,4, "TM38", 0x24E},
    {"Giovanni", "MAP_G05_N01", 2,2, "TM26", 0x298},
  }
  U.wait(20)
  for index, gym in ipairs(gyms) do
    if not os.getenv("GYM_ONLY") or os.getenv("GYM_ONLY") == gym[1] then
      local save = U.freshSave(game)
      local mon = Pokemon.new(game.data, "MEWTWO", 100)
      mon.moves = {{id="PSYCHIC", pp=99, maxPp=99}}
      save.party = {mon}
      U.teleport(game, gym[2], gym[3], gym[4]+1, "up")
      U.wait(30)
      assert(U.shot(game, "ngshots/gym_" .. gym[1] .. "_before.png"))
      local battled, completed = false, false
      for frame=1,14000 do
        if frame % 12 == 1 then U.tap(game, "a") else U.wait(1) end
        local top = game.stack:top()
        -- A nearby trainer can spot the teleported player first (Diana in
        -- Cerulean). Only count and capture the requested leader's battle.
        local name = top and top.trainer and tostring(top.trainer.name):upper()
        if top and top.enemy and name and name:find(gym[1]:upper(), 1, true) and not battled then
          battled = true
          U.wait(180)
          assert(U.shot(game, "ngshots/gym_" .. gym[1] .. "_battle.png"))
        end
        if battled and save.flags[G.flagKey(gym[6])]
           and top == game.overworld and not game.overworld.runner:isRunning() then
          assert(save.flags[G.flagKey(0x81F + index)], gym[1] .. " badge missing")
          assert(save.flags[G.flagKey(0x4AF + index)], gym[1] .. " defeated flag missing")
          assert((save.inventory[gym[5]] or 0) == 1, gym[1] .. " TM missing or duplicated")
          assert((save.inventory.TM_CASE or 0) == 1, gym[1] .. " TM CASE missing or duplicated")
          assert(U.shot(game, "ngshots/gym_" .. gym[1] .. "_reward.png"))
          U.log("PASS gym", gym[1], "battle, badge, defeated flag, reward flag, TM CASE,", gym[5], frame)
          completed = true
          break
        end
      end
      assert(completed, gym[1] .. " battle/reward chain did not complete")
    end
  end
  U.log("PASS all requested gyms")
  love.event.quit(0)
end
