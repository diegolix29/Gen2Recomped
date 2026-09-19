-- FireRed port verification: a gym leader, the badge and the TM.
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
  local ok, err = pcall(function()
    local m = Pokemon.new(game.data, "MEWTWO", 80)
    -- one damaging move so mashing A wins
    m.moves = { { id = "PSYCHIC", pp = 10, maxPp = 10 } }
    table.insert(game.save.party, m)
  end)
  if not ok then U.log("party failed", err) end
  -- PEWTER GYM (group 6, map 2): Brock at (6,5)
  pcall(U.teleport, game, "MAP_G06_N02", 6, 6, "up")
  U.wait(60)
  U.hold(game, "up", 6); U.wait(12)
  shot("90_gym")
  local flags = game.save.flags or {}
  local battled, n = false, 0
  for i = 1, 6000 do
    if i % 20 == 1 then U.tap(game, "a") end
    coroutine.yield()
    local top = game.stack:top()
    local isBattle = top and (top.enemy or top.battleType or top.isBattle)
    if isBattle and not battled then
      battled = true
      U.wait(200); shot("91_brock_battle")
    end
    if battled and i % 90 == 0 and n < 20 then
      n = n + 1
      shot(("92_after_%02d"):format(n))
    end
    if (game.save.flags or {})["FLAG_G3_0820"] and (game.save.inventory or {}).TM39 then
      U.wait(120); shot("93_badge_tm")
      break
    end
  end
  local f = game.save.flags or {}
  U.log("battled", battled, "BADGE01", tostring(f["FLAG_G3_0820"]),
        "TM39", tostring((game.save.inventory or {}).TM39))
  local set = {}
  for k, v in pairs(f) do if v and k:find("FLAG_G3_08") then set[#set + 1] = k end end
  table.sort(set)
  U.log("system flags", table.concat(set, " "))
  love.event.quit(0)
end
