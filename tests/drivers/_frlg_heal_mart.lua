-- FireRed port verification: a Pokemon Center heal and a Poke Mart purchase.
return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  local function shot(name)
    game.capturePath = "frlg_" .. name .. ".png"
    for _ = 1, 120 do
      if not game.capturePath then break end
      coroutine.yield()
    end
    U.wait(2)
  end
  local function mon() return game.save.party[1] end
  U.wait(20)
  U.newGame(game)
  U.wait(30)
  local okP, errP = pcall(function()
    local m = Pokemon.new(game.data, "CHARMANDER", 12)
    m.hp = 3
    table.insert(game.save.party, m)
  end)
  if not okP then U.log("party failed", errP) end
  game.save.money = 3000

  -- VIRIDIAN POKEMON CENTER 1F (group 5, map 4): nurse at (7,2), counter row 3
  local ok, err = pcall(U.teleport, game, "MAP_G05_N04", 7, 4, "up")
  if not ok then U.log("teleport center failed", err) end
  U.wait(30)
  local function where(tag)
    local ow = game.stack:top()
    local pl = ow and ow.player
    U.log(tag, "top", ow and (ow.map and ow.map.id), "player", pl and pl.facing,
          pl and (pl.cellX or pl.x), pl and (pl.cellY or pl.y),
          "runner", ow and ow.runner and ow.runner:isRunning(),
          "input", pl and pl.inputLocked, "trans", ow and ow.transitioning)
  end
  where("after teleport")
  U.hold(game, "up", 6); U.wait(12)
  where("after hold up")
  U.hold(game, "left", 20); U.wait(20)
  where("after hold left")
  U.hold(game, "right", 20); U.wait(20)
  U.hold(game, "up", 6); U.wait(12)
  where("back")
  do
    local ow = game.stack:top()
    local m = ow.map
    U.log("counter(7,3)", m:isCounterCell(7, 3), "beh", m.cellBehaviour and m:cellBehaviour(7, 3),
          "tiles", m.tileset.counterTiles and table.concat(m.tileset.counterTiles, ","),
          "bb", tostring(m.tileset.behaviourBytes))
    for y = 1, 3 do
      local n = ow:npcAtCell(7, y)
      U.log("npc at 7," .. y, n and (n.id or n.name or n.sprite or "npc"), n and n.script)
    end
    for _, n in ipairs(ow.npcs or {}) do
      U.log("npc", n.cellX, n.cellY, n.sprite or n.graphics, n.script, n.hidden)
    end
  end
  shot("30_center")
  U.log("before heal hp", mon() and mon().hp)
  for i = 1, 30 do
    U.tap(game, "a"); U.wait(40)
    shot(("31_heal_%02d"):format(i))
  end
  U.log("after heal hp", mon() and mon().hp, "/", mon() and mon().stats and mon().stats.hp)
  for _ = 1, 6 do U.tap(game, "b"); U.wait(10) end

  -- PEWTER MART (group 6, map 3): clerk at (2,3) behind the counter
  ok, err = pcall(U.teleport, game, "MAP_G06_N03", 4, 3, "left")
  if not ok then U.log("teleport mart failed", err) end
  U.wait(30)
  U.hold(game, "left", 6); U.wait(12)
  do
    local ow = game.stack:top()
    U.log("mart counter(3,3)", ow.map:isCounterCell(3, 3), "npc(2,3)", ow:npcAtCell(2, 3) ~= nil,
          "player", ow.player.facing, ow.player.cellX, ow.player.cellY)
  end
  shot("40_mart")
  local moneyBefore = game.save.money
  for i = 1, 12 do
    U.tap(game, "a"); U.wait(30)
    shot(("41_mart_%02d"):format(i))
  end
  -- BUY is the first choice; the first item; quantity 1; confirm
  for i = 1, 12 do
    U.tap(game, "a"); U.wait(30)
    shot(("42_buy_%02d"):format(i))
  end
  U.log("money", moneyBefore, "->", game.save.money)
  U.log("FRLG heal/mart shots done")
  love.event.quit(0)
end
