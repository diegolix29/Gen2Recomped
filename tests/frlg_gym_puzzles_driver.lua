-- Entrance-to-leader FireRed gym puzzle verification.  This deliberately
-- drives the real overworld: switches, Cut, collision walls, warp pads,
-- quiz machines, and spinner tiles must all work before a route can finish.
-- Set GYM_ONLY to one gym name to run a single case.
return function(game)
  local U = require("tests.drivers.util")
  local G = require("src.script.Gen3Commands")
  local Pokemon = require("src.pokemon.Pokemon")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local Collision = require("src.world.Collision")

  local DIRS = {
    { 0, -1, "up" }, { 0, 1, "down" },
    { -1, 0, "left" }, { 1, 0, "right" },
  }

  local function busy()
    local ow = game.overworld
    return game.stack:top() ~= ow
      or (ow.runner and ow.runner:isRunning())
      or #(ow.scriptMoves or {}) > 0
      or ow.engaging or ow.emote ~= nil or ow.transitioning
      or ow.player.moving or ow.player.spinning
  end

  local function service(answer)
    local top = game.stack:top()
    if getmetatable(top) == ChoiceBox and answer ~= nil then
      U.tap(game, answer and "a" or "b")
      return true
    end
    U.tap(game, "a")
    return false
  end

  local function settle(answer, limit)
    local chose = false
    for frame = 1, limit or 5000 do
      if not busy() then return chose, frame end
      if frame % 10 == 1 then
        chose = service(chose and nil or answer) or chose
      else
        U.wait(1)
      end
    end
    error("overworld did not become idle")
  end

  local function bfs(tx, ty)
    local ow, map, p = game.overworld, game.overworld.map, game.overworld.player
    if p.cellX == tx and p.cellY == ty then return nil, true end
    local w, h = map.widthCells, map.heightCells
    local function id(x, y) return y * w + x end
    local blocked = {}
    for _, npc in ipairs(ow.npcs or {}) do
      blocked[id(npc.cellX, npc.cellY)] = true
      if npc.targetX then blocked[id(npc.targetX, npc.targetY)] = true end
    end
    local start, goal = id(p.cellX, p.cellY), id(tx, ty)
    local prev, how, queue, head = {[start] = -1}, {}, {start}, 1
    while head <= #queue do
      local cur = queue[head]; head = head + 1
      if cur == goal then break end
      local cx, cy = cur % w, math.floor(cur / w)
      for _, d in ipairs(DIRS) do
        local nx, ny = cx + d[1], cy + d[2]
        local nid = id(nx, ny)
        local mover = {
          cellX = cx, cellY = cy,
          elevation = map.cellElevation and map:cellElevation(cx, cy) or nil,
        }
        if nx >= 0 and ny >= 0 and nx < w and ny < h
           and prev[nid] == nil and not blocked[nid]
           and Collision.canMove(map, ow.entities, mover, d[3]) then
          prev[nid], how[nid] = cur, d[3]
          queue[#queue + 1] = nid
        end
      end
    end
    if prev[goal] == nil then return nil, false end
    local cur = goal
    while prev[cur] ~= start do cur = prev[cur] end
    return how[cur], true
  end

  local function walkTo(tx, ty, limit)
    for frame = 1, limit or 12000 do
      local ow, p = game.overworld, game.overworld.player
      if frame % 2000 == 0 then
        U.log("ROUTE wait", ow.map.id, p.cellX, p.cellY, "to", tx, ty,
          "top", game.stack:top() == ow, "runner", ow.runner and ow.runner:isRunning(),
          "moves", #(ow.scriptMoves or {}), "engaging", ow.engaging,
          "emote", ow.emote ~= nil, "transition", ow.transitioning,
          "moving", p.moving, "spinning", p.spinning)
      end
      if p.cellX == tx and p.cellY == ty and not p.moving then
        return frame
      end
      if busy() then
        if frame % 10 == 1 then service(nil) else U.wait(1) end
      else
        local key, reachable = bfs(tx, ty)
        if not reachable then
          error(("no route from (%d,%d) to (%d,%d) in %s"):format(
            p.cellX, p.cellY, tx, ty, ow.map.id))
        end
        if key then U.tap(game, key) else U.wait(1) end
      end
    end
    error(("route timed out heading to (%d,%d)"):format(tx, ty))
  end

  local function face(dir) U.tap(game, dir); U.wait(3) end

  local function adjacent(tx, ty)
    local candidates = {
      {tx, ty + 1, "up"}, {tx, ty - 1, "down"},
      {tx + 1, ty, "left"}, {tx - 1, ty, "right"},
    }
    for _, c in ipairs(candidates) do
      local _, ok = bfs(c[1], c[2])
      if ok then return c end
    end
    error(("no reachable interaction cell beside (%d,%d)"):format(tx, ty))
  end

  local function interact(tx, ty, answer)
    local candidates = {
      {tx, ty + 1, "up"}, {tx, ty - 1, "down"},
      {tx + 1, ty, "left"}, {tx - 1, ty, "right"},
    }
    local c
    for _, candidate in ipairs(candidates) do
      local _, ok = bfs(candidate[1], candidate[2])
      if ok then
        local reached = pcall(walkTo, candidate[1], candidate[2], 5000)
        if reached then c = candidate; break end
      end
    end
    assert(c, ("could not reach an interaction cell beside (%d,%d)"):format(tx, ty))
    face(c[3])
    U.tap(game, "a")
    local chose = settle(answer)
    if answer ~= nil then assert(chose, "expected a YES/NO choice") end
  end

  local function prepare(mapId, x, y)
    local save = U.freshSave(game)
    local mon = Pokemon.new(game.data, "MEWTWO", 100)
    mon.moves = {
      {id="PSYCHIC", pp=99, maxPp=99},
      {id="CUT", pp=99, maxPp=99},
    }
    save.party = {mon}
    -- Field Cut and late gyms require the preceding badge permissions.
    for i = 0, 7 do save.flags[G.flagKey(0x820 + i)] = true end
    U.teleport(game, mapId, x, y, "up")
    U.wait(20)
    return save
  end

  local gyms = {}
  local function gym(name, fn) gyms[#gyms + 1] = {name, fn} end

  gym("Brock", function()
    prepare("MAP_G06_N02", 6, 13)
    walkTo(6, 6)
  end)

  gym("Misty", function()
    prepare("MAP_G07_N05", 8, 17)
    walkTo(8, 7)
  end)

  gym("Surge", function()
    local save = prepare("MAP_G09_N06", 5, 18)
    local coords = {}
    for y = 10, 14, 2 do
      for x = 1, 9, 2 do coords[#coords + 1] = {x, y} end
    end
    local first = tonumber(G.getVar(save, 0x8004))
    local second = tonumber(G.getVar(save, 0x8005))
    assert(first and coords[first], "Vermilion first switch was not initialized")
    assert(second and coords[second], "Vermilion second switch was not initialized")
    interact(coords[first][1], coords[first][2])
    interact(coords[second][1], coords[second][2])
    walkTo(5, 5)
  end)

  gym("Erika", function()
    prepare("MAP_G10_N16", 6, 17)
    walkTo(6, 9)
    face("up")
    U.tap(game, "a")
    settle(true)
    walkTo(6, 5)
  end)

  gym("Koga", function()
    prepare("MAP_G11_N03", 7, 20)
    walkTo(7, 14)
  end)

  gym("Sabrina", function()
    prepare("MAP_G14_N03", 14, 22)
    local function pad(x, y)
      walkTo(x, y)
      U.wait(30)
      settle(nil, 2000)
    end
    -- Entrance -> southeast.  Within each room, use explicit ordinary-floor
    -- waypoints so shortest-path planning cannot step on a different pad.
    pad(18,20)                         -- arrive southeast (28,23)
    walkTo(27,23); walkTo(21,23); walkTo(21,20)
    pad(20,20)                         -- arrive northeast (28,4)
    walkTo(28,5); walkTo(21,5); walkTo(21,7)
    pad(20,7)                          -- arrive northwest (0,4)
    walkTo(0,5); walkTo(1,5); walkTo(1,7)
    pad(0,7)                           -- arrive in Sabrina's room (18,15)
    walkTo(14, 12)
  end)

  gym("Blaine", function()
    prepare("MAP_G12_N00", 25, 22)
    -- The six correct FireRed answers are YES, NO, NO, NO, YES, NO.
    local machines = {
      {22,10,true}, {15,2,false}, {13,10,false},
      {13,17,false}, {1,18,true}, {1,10,false},
    }
    for _, m in ipairs(machines) do interact(m[1], m[2], m[3]) end
    walkTo(5, 5)
  end)

  gym("Giovanni", function()
    prepare("MAP_G05_N01", 17, 21)
    -- Plan in player-input moves: one d-pad step may cross several cells as
    -- arrow tiles redirect the active forced movement before a stop tile.
    local function spinNext(tx, ty)
      local ow, map, p = game.overworld, game.overworld.map, game.overworld.player
      local B = ow:frlgBehaviours()
      local w = map.widthCells
      local function id(x, y) return y * w + x end
      local function advance(x, y, dir)
        local d
        for _, row in ipairs(DIRS) do if row[3] == dir then d = row break end end
        local mover = {cellX=x, cellY=y,
          elevation=map.cellElevation and map:cellElevation(x,y) or nil}
        if not (d and Collision.canMove(map, ow.entities, mover, dir)) then return nil end
        local nx, ny, forced = x + d[1], y + d[2], nil
        for _ = 1, 100 do
          local b = ow:frlgBehaviourAt(nx, ny)
          if b == B.stopSpinning then return nx, ny end
          if B.spin[b] then forced = B.spin[b] end
          if not forced then return nx, ny end
          local fd
          for _, row in ipairs(DIRS) do if row[3] == forced then fd = row break end end
          local fm = {cellX=nx, cellY=ny,
            elevation=map.cellElevation and map:cellElevation(nx,ny) or nil}
          if not (fd and Collision.canMove(map, ow.entities, fm, forced)) then return nx, ny end
          nx, ny = nx + fd[1], ny + fd[2]
        end
        error("spinner simulation cycled")
      end
      local start, goal = id(p.cellX,p.cellY), id(tx,ty)
      local prev, how, queue, head = {[start]=-1}, {}, {start}, 1
      while head <= #queue do
        local cur = queue[head]; head = head + 1
        if cur == goal then break end
        local x, y = cur % w, math.floor(cur / w)
        for _, d in ipairs(DIRS) do
          local nx, ny = advance(x, y, d[3])
          if nx then
            local nid = id(nx,ny)
            if prev[nid] == nil then
              prev[nid], how[nid] = cur, d[3]
              queue[#queue+1] = nid
            end
          end
        end
      end
      if prev[goal] == nil then return nil, false end
      local cur = goal
      while prev[cur] ~= start do cur = prev[cur] end
      return how[cur], true
    end
    for frame = 1, 24000 do
      local p = game.overworld.player
      if p.cellX == 2 and p.cellY == 3 and not busy() then break end
      if busy() then
        if frame % 10 == 1 then service(nil) else U.wait(1) end
      else
        local key, ok = spinNext(2,3)
        assert(ok and key, "no spinner-aware route to Giovanni")
        U.tap(game, key)
      end
    end
    assert(game.overworld.player.cellX == 2 and game.overworld.player.cellY == 3,
      "spinner-aware route timed out")
  end)

  U.wait(20)
  local ran = 0
  for _, entry in ipairs(gyms) do
    if not os.getenv("GYM_ONLY") or os.getenv("GYM_ONLY") == entry[1] then
      entry[2]()
      local ow = game.overworld
      assert(U.shot(game, "ngshots/gym_puzzle_" .. entry[1] .. ".png"))
      U.log("PASS puzzle", entry[1], "reached leader at",
            ow.player.cellX, ow.player.cellY)
      ran = ran + 1
    end
  end
  assert(ran > 0, "GYM_ONLY did not name a gym")
  U.log("PASS all requested gym puzzles", ran)
  love.event.quit(0)
end
