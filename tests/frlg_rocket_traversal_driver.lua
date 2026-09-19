-- Visible FireRed verification for the remaining Team Rocket traversal:
-- Mt. Moon's four grunts/fossil choice, the Celadon slot machine, a real
-- Silph Card Key barrier, and the Hideout's B1F -> B4F stair route.
return function(game)
  local U = require("tests.drivers.util")
  local G = require("src.script.Gen3Commands")
  local Pokemon = require("src.pokemon.Pokemon")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local Collision = require("src.world.Collision")
  local Gen3Slots = require("src.ui.Gen3Slots")

  local DIRS = {
    {0,-1,"up"}, {0,1,"down"}, {-1,0,"left"}, {1,0,"right"},
  }

  local function busy()
    local ow = game.overworld
    return game.stack:top() ~= ow
      or (ow.runner and ow.runner:isRunning())
      or #(ow.scriptMoves or {}) > 0 or ow.engaging or ow.emote ~= nil
      or ow.transitioning or ow.player.moving or ow.player.spinning
  end

  local function settle(answer, limit)
    local chose = false
    for frame = 1, limit or 18000 do
      if not busy() then return chose end
      if frame % 10 == 1 then
        local top = game.stack:top()
        if getmetatable(top) == ChoiceBox and answer ~= nil and not chose then
          U.tap(game, answer and "a" or "b")
          chose = true
        else
          U.tap(game, getmetatable(top) == ChoiceBox and "b" or "a")
        end
      else
        U.wait(1)
      end
    end
    error("Rocket traversal action did not settle")
  end

  local function script(label, tag)
    assert(game.overworld:gen3RunFieldScript(label, tag), "could not start " .. label)
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

  local function face(dir) U.tap(game, dir); U.wait(3) end

  local function interactAt(mapId, tx, ty, px, py, facing, answer)
    U.teleport(game, mapId, px, py, facing)
    face(facing)
    U.tap(game, "a")
    local chose = settle(answer)
    if answer ~= nil then assert(chose, "expected a YES/NO choice") end
  end

  -- Plan one player input, including the complete forced movement produced by
  -- the Hideout's arrow tiles.  This is the same constraint the player sees:
  -- a route consists of d-pad presses, not teleports between spinner stops.
  local function nextInput(tx, ty)
    local ow, map, p = game.overworld, game.overworld.map, game.overworld.player
    local B = ow:frlgBehaviours()
    local w, h = map.widthCells, map.heightCells
    local function id(x,y) return y*w+x end
    local function advance(x,y,dir)
      local d
      for _, row in ipairs(DIRS) do if row[3] == dir then d = row break end end
      local mover = {cellX=x, cellY=y,
        elevation=map.cellElevation and map:cellElevation(x,y) or nil}
      if not (d and Collision.canMove(map, ow.entities, mover, dir)) then return nil end
      local nx, ny, forced = x+d[1], y+d[2], nil
      for _ = 1, 100 do
        if nx < 0 or ny < 0 or nx >= w or ny >= h then return nil end
        local b = ow:frlgBehaviourAt(nx,ny)
        if b == B.stopSpinning then return nx,ny end
        if B.spin[b] then forced = B.spin[b] end
        if not forced then return nx,ny end
        local fd
        for _, row in ipairs(DIRS) do if row[3] == forced then fd = row break end end
        local fm = {cellX=nx, cellY=ny,
          elevation=map.cellElevation and map:cellElevation(nx,ny) or nil}
        if not (fd and Collision.canMove(map, ow.entities, fm, forced)) then return nx,ny end
        nx,ny = nx+fd[1],ny+fd[2]
      end
      error("Hideout spinner simulation cycled")
    end
    local start, goal = id(p.cellX,p.cellY), id(tx,ty)
    if start == goal then return nil,true end
    local prev, how, queue, head = {[start]=-1}, {}, {start}, 1
    while head <= #queue do
      local cur=queue[head]; head=head+1
      if cur == goal then break end
      local x,y=cur%w,math.floor(cur/w)
      for _,d in ipairs(DIRS) do
        local nx,ny=advance(x,y,d[3])
        if nx then
          local nid=id(nx,ny)
          if prev[nid] == nil then
            prev[nid],how[nid]=cur,d[3]
            queue[#queue+1]=nid
          end
        end
      end
    end
    if prev[goal] == nil then return nil,false end
    local cur=goal
    while prev[cur] ~= start do cur=prev[cur] end
    return how[cur],true
  end

  local function walkTo(tx,ty,limit)
    for frame=1,limit or 24000 do
      local p=game.overworld.player
      if p.cellX == tx and p.cellY == ty and not p.moving and not p.spinning then return end
      if busy() then
        if frame % 10 == 1 then U.tap(game,"a") else U.wait(1) end
      else
        local key,ok=nextInput(tx,ty)
        assert(ok and key, ("no physical route in %s from (%d,%d) to (%d,%d)"):format(
          game.overworld.map.id,p.cellX,p.cellY,tx,ty))
        U.tap(game,key)
      end
    end
    error("physical route timed out")
  end

  local function walkWarp(tx,ty,destination)
    local source=game.overworld.map.id
    for frame=1,30000 do
      if game.overworld.map.id == destination then
        U.log("PASS Rocket floor transition", source, "to", destination)
        return
      end
      assert(game.overworld.map.id == source,
        "unexpected warp destination " .. tostring(game.overworld.map.id))
      if busy() then
        if frame % 10 == 1 then U.tap(game,"a") else U.wait(1) end
      else
        local p=game.overworld.player
        if p.cellX == tx and p.cellY == ty then U.wait(1)
        else
          local key,ok=nextInput(tx,ty)
          assert(ok and key, "no spinner-aware route to floor warp")
          U.tap(game,key)
        end
      end
    end
    error("floor warp timed out")
  end

  U.wait(20)
  local save=strongSave()

  -- All four Mt. Moon Rocket object scripts, followed by Miguel and an actual
  -- YES choice on the Dome Fossil object.
  local moonGrunts = {
    {37,21,37,22,"up"}, {12,20,12,21,"up"},
    {35,12,35,13,"up"}, {18,27,18,28,"up"},
  }
  for i,g in ipairs(moonGrunts) do
    interactAt("MAP_G01_N03",g[1],g[2],g[3],g[4],g[5])
    U.log("PASS Mt. Moon Rocket grunt",i)
  end
  interactAt("MAP_G01_N03",13,11,13,12,"up")
  interactAt("MAP_G01_N03",13,7,13,8,"up",true)
  assert((save.inventory.DOME_FOSSIL or 0) == 1,"Dome Fossil missing")
  assert(save.flags[G.flagKey(0x232)],"Mt. Moon fossil completion flag missing")
  assert(save.flags[G.flagKey(0x272)],"Dome Fossil choice flag missing")
  assert(U.shot(game,"ngshots/rocket_mt_moon_complete.png"))
  U.log("PASS Rocket Mt. Moon and fossil choice")

  -- Use a real machine sign, accept its prompt, bet three coins, spin, stop
  -- all reels, acknowledge the result, and stand back up.
  save.flags[G.flagKey(0x243)]=true
  save.coins=100
  U.teleport(game,"MAP_G10_N14",1,7,"left")
  face("left"); U.tap(game,"a")
  for frame=1,5000 do
    local top=game.stack:top()
    if getmetatable(top) == Gen3Slots then break end
    if frame % 10 == 1 then U.tap(game,"a") else U.wait(1) end
  end
  local slots=game.stack:top()
  assert(getmetatable(slots) == Gen3Slots,"Game Corner machine did not open")
  assert(slots:matchOf(4,2,1) == 1,"FireRed two-cherry rule missing")
  assert(slots:matchOf(4,4,6) == 2,"FireRed three-cherry rule missing")
  assert(slots:matchOf(5,5,5) == 3,"FireRed Magnemite/Shellder payout missing")
  assert(slots:matchOf(2,2,2) == 4,"FireRed Pikachu/Psyduck payout missing")
  assert(slots:matchOf(1,1,1) == 5,"FireRed Rocket payout missing")
  assert(slots:matchOf(0,0,0) == 6,"FireRed seven payout missing")
  assert(U.shot(game,"ngshots/rocket_game_corner_slots.png"))
  U.tap(game,"a"); U.tap(game,"a"); U.tap(game,"a")
  assert(slots.bet == 3 and save.coins == 97,"slot machine did not accept three coins")
  U.tap(game,"start"); U.wait(12)
  assert(slots.stage == "spin","slot machine did not start")
  U.tap(game,"a"); U.wait(5); U.tap(game,"a"); U.wait(5); U.tap(game,"a"); U.wait(5)
  assert(slots.stage == "result","slot machine did not settle all reels")
  assert(U.shot(game,"ngshots/rocket_game_corner_slot_result.png"))
  U.tap(game,"a"); U.wait(2); U.tap(game,"b"); settle()
  U.log("PASS Rocket Game Corner slot machine")

  -- The actual 5F item ball sets the cartridge flag checked by every Silph
  -- door.  Interact with a 2F barrier sign, then physically cross its former
  -- blocked cells after the script redraws the map.
  U.teleport(game,"MAP_G01_N51",22,20,"down")
  U.tap(game,"a"); settle()
  assert((save.inventory.CARD_KEY or 0) == 1,"Silph Card Key missing")
  assert(save.flags[G.flagKey(0x192)],"Card Key item flag missing")
  U.teleport(game,"MAP_G01_N48",5,10,"up")
  face("up"); U.tap(game,"a"); settle()
  assert(save.flags[G.flagKey(0x27A)],"Silph 2F door flag missing")
  walkTo(5,8)
  assert(game.overworld.player.cellX == 5 and game.overworld.player.cellY == 8,
    "player did not cross the opened Card Key barrier")
  assert(U.shot(game,"ngshots/rocket_silph_card_key_crossed.png"))
  U.log("PASS Rocket physical Card Key door traversal")

  -- Open the poster, walk onto its real warp, then navigate every Hideout
  -- floor in order using collision and forced-arrow movement.
  save=strongSave()
  U.teleport(game,"MAP_G10_N14",11,3,"up")
  script("S016CAF5","game-corner-grunt-traversal")
  U.teleport(game,"MAP_G10_N14",11,2,"up")
  U.tap(game,"a"); settle()
  walkWarp(15,2,"MAP_G01_N42")
  walkWarp(17,2,"MAP_G01_N43")
  walkWarp(21,2,"MAP_G01_N44")
  walkWarp(15,18,"MAP_G01_N45")
  assert(U.shot(game,"ngshots/rocket_hideout_b1_to_b4_complete.png"))
  U.log("PASS Rocket Hideout B1F-to-B4F physical traversal")
  U.log("PASS Team Rocket traversal remainder")
  love.event.quit(0)
end
