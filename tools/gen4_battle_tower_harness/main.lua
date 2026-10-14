-- tools/gen4_battle_tower_harness/main.lua
--
-- A BATTLE TOWER CHALLENGE, PLAYED HEADLESS ON THE REAL ENGINE: stands in
-- front of the single-battle attendant (D31R0201, (15,5)), talks, takes the
-- first answer at every menu, enters the first three party members through
-- the party menu's team choice, and mashes A through the battles. Prints
-- each map change, each battle, and at the end the tower record.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_battle_tower_harness
--
-- Env: TICKS (default 60000), LEVEL (the party's, default 100),
--      MODE ("double" for the doubles counter, "multi" for the multi
--      counter: no to the link question, two members, Cheryl from the
--      Battle Salon), REST=n (choose Rest before opponent n, then Continue
--      the save it makes), HALL=1 (the Battle Hall's lobby instead: one
--      Pokemon in, the frontier scene's type grid and battles), FACTORY=1
--      (the Battle Factory's lobby: rentals, seven battles, the trades kept),
--      CASTLE=1 (the Battle Castle's lobby: three in, the apps closed, BATTLE
--      every time), ARCADE=1 (the Battle Arcade's lobby: three in, the Game
--      Board stopped wherever it is)

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("platinum")
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage, held = Assets.image, {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not held[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); held[path] = img end
          end
        end
        return held[path] or realImage(path, ...)
      end
    end
    local Data = require("src.core.Data")
    Data:load()
    local SaveData = require("src.core.SaveData")
    local Game = require("src.core.Game")
    Game.data = Data
    -- Game:boot's order (see tools/gen4_overworld_harness)
    local ModLoader = require("src.mods.Loader")
    Game.mods = ModLoader.new()
    Game.mods:load(Data)
    Game.modStatus = Game.mods:status()
    require("src.render.Pipelines").install(Data)
    local Renderer = require("src.render.Renderer")
    Game.renderer = Renderer
    Renderer:init()
    require("src.render.Font").load(Data)
    require("src.ui.Theme").load(Data)
    require("src.core.Strings").load(Data)
    local StateStack = require("src.core.StateStack")
    StateStack:init()
    Game.stack = StateStack
    Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
    if Game.adoptSave then pcall(Game.adoptSave, Game, Game.save, true) end
    Game.save.player.name = "LUCAS"

    -- a strong team, maxed out so seven in a row is likely
    local Pokemon = require("src.pokemon.Pokemon")
    local Stats = require("src.pokemon.Stats")
    local level = tonumber(os.getenv("LEVEL") or "100")
    Game.save.party = {}
    for _, sp in ipairs({ 445, 448, 376, 248 }) do   -- Garchomp, Lucario, Metagross, Tyranitar
      local mon = Pokemon.new(Data, sp, level)
      mon.ivs = { hp = 31, attack = 31, defense = 31, speed = 31, spatk = 31, spdef = 31 }
      mon.evs = { hp = 252, attack = 252, defense = 0, speed = 4, spatk = 0, spdef = 0 }
      local def = require("src.pokemon.Gen4Forms").definition(Data, mon)
      mon.stats = Stats.calc(def, level, mon.ivs, nil, mon.evs, mon.nature)
      mon.hp = mon.stats.hp
      Game.save.party[#Game.save.party + 1] = mon
    end

    local pressed = {}
    Game.input = {
      wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end,
      isDown = function() return false end,
      wasReleased = function() return false end,
    }
    local OW = require("src.world.OverworldController")
    local double = os.getenv("MODE") == "double"
    local multi = os.getenv("MODE") == "multi"
    if os.getenv("HALL") then
      -- the Battle Hall's lobby (D32R0401): the singles attendant at (6,9)
      Game.stack:push(OW, "D32R0401", 7, 9, "left")
    elseif os.getenv("ARCADE") then
      -- the Battle Arcade's lobby (D32R0601): the singles attendant at (14,5)
      Game.stack:push(OW, "D32R0601", 14, 6, "up")
    elseif os.getenv("CASTLE") then
      -- the Battle Castle's lobby (D32R0501): the singles attendant at (5,9)
      Game.stack:push(OW, "D32R0501", 6, 9, "left")
    elseif os.getenv("FACTORY") then
      -- the Battle Factory's lobby (D32R0301): the singles attendant at (21,6)
      Game.stack:push(OW, "D32R0301", 21, 7, "up")
    elseif multi then
      -- FLAG_TRAVELED_WITH_CHERYL (0xE3): she waits in the Salon
      Game.save.flags = Game.save.flags or {}
      Game.save.flags["FLAG_G4_00E3"] = true
      Game.stack:push(OW, "D31R0201", 11, 6, "up")
    else
      Game.stack:push(OW, "D31R0201", 15, 6, "up")
    end
    Game.overworld = Game.overworld or OW

    if os.getenv("TRACE") then
      local Commands = require("src.script.Commands")
      local real = Commands.show_text
      Commands.show_text = function(ctx, id, ...)
        local t = Data.text and Data.text[id]
        if os.getenv("SNAP") and tostring(id):find("B0614") and not _G.__btSnapAt then _G.__btSnapAt = true end
        print(("  text %s: %s"):format(tostring(id), tostring(t):gsub("\n", " "):sub(1, 80)))
        return real(ctx, id, ...)
      end
      if os.getenv("ROWS") then
        local realResolve = Commands.resolve
        Commands.resolve = function(data, name)
          local fn, meta = realResolve(data, name)
          if name ~= "label" then print("    row " .. tostring(name) .. (fn and "" or " (UNKNOWN)")) end
          return fn, meta
        end
      end
      local realCall = Commands.g4_bt_call
      Commands.g4_bt_call = function(ctx, fn, arg, dest)
        local r = realCall(ctx, fn, arg, dest)
        local G4 = require("src.script.Gen4Commands")
        local d = tonumber(dest)
        print(("  bt fn %s arg %s -> %s"):format(tostring(fn), tostring(G4.valueOf(ctx, arg)),
          (d and d >= 0x4000) and tostring(G4.getVar(ctx.save, d)) or "-"))
        return r
      end
    end
    local PM = require("src.ui.Gen4PartyMenu")
    local MenuMT = require("src.ui.Menu")
    local restAt = tonumber(os.getenv("REST") or "")
    local restArmed, restDown, restored = false, false, false
    do
      local Commands = require("src.script.Commands")
      local realText = Commands.show_text
      Commands.show_text = function(ctx, id, ...)
        local bt = Game.gen4BattleTower
        if restAt and not restored and (id == "TEXT_B0305_00001" or id == "TEXT_B0306_00003") and bt and bt.next == restAt then restArmed = true end
        if id ~= nil then _G.__btLastText = id end
        return realText(ctx, id, ...)
      end
    end
    local lastMap, battles, lastTop = nil, 0, nil
    local ticks = tonumber(os.getenv("TICKS") or "60000")
    local talked = false
    local menuCount = 0
    local salonTalked, linkDeclined = false, false
    for i = 1, ticks do
      local top = Game.stack:top()
      local ow = Game.overworld
      local mapId = ow and ow.map and ow.map.id
      if mapId ~= lastMap then
        print(("[t%d] map %s"):format(i, tostring(mapId)))
        lastMap = mapId
      end
      if top ~= lastTop then
        local name = type(top) == "table" and (top.screenId or (getmetatable(top) and getmetatable(top).__name)) or tostring(top)
        if type(top) == "table" and top.kind and top.enemy then
          battles = battles + 1
          local bt = Game.gen4BattleTower
          print(("[t%d] battle %d vs %s (%s) -- opponent no. %s"):format(i, battles,
            tostring(top.trainer and top.trainer.name), tostring(top.trainer and top.trainer.className),
            tostring(bt and bt.next)))
        end
        lastTop = top
        if os.getenv("TRACE") and type(top) == "table" then
          local t = top.text or top.message or (top.pages and top.pages[1])
          print(("[t%d] top %s %s"):format(i, tostring(name), type(t) == "string" and (t:gsub("\n", " "):sub(1, 70)) or ""))
        end
      end
      -- the Factory's rentals: the first three; at a trade, keep
      if type(top) == "table" and getmetatable(top) == require("src.ui.Gen3FactoryScreen") then
        if i % 4 == 0 and not top.asking then
          if top.mode == "select" then top.index = #top.picks + 1; pressed.a = true else pressed.b = true end
        end
        if os.getenv("TRACE") and i % 500 == 0 then
          print(("[t%d] factory screen %s: picks %d, index %d, asking %s, mons %d, input same %s, stack top same %s"):format(i, top.mode, #top.picks, top.index,
            tostring(top.asking), #top.mons, tostring(top.game.input == Game.input), tostring(top.game.stack:top() == top)))
        end
      end
      -- a fainted lead in battle: the cursor onto someone standing
      if type(top) == "table" and getmetatable(top) == require("src.ui.Gen4BattleParty") and top.party then
        local party = top:party()
        local cur = party[top.index or 1]
        if cur and (cur.hp or 0) <= 0 then
          for k, m in ipairs(party) do if (m.hp or 0) > 0 then top.index = k break end end
        end
      end
      if type(top) == "table" and top.phase == "moveSelect" and top.player and top.player.curMoves then
        local moves = top.player.curMoves
        local m = moves[top.moveIndex or 1]
        if m and (m.pp or 1) <= 0 then
          for k, mv in ipairs(moves) do if (mv.pp or 1) > 0 then top.moveIndex = k break end end
        end
      end
      -- the team choice: the first three, then CONFIRM
      if type(top) == "table" and top.select and getmetatable(top) == PM then
        if #top.select.order < top.select.count then
          top.index = #top.select.order + 1
          top:runAction("enter")
        else
          top.index = #Game.save.party + 1
          top:choose()
          print(("[t%d] entered slots 1..%d"):format(i, top.select.count))
        end
      elseif os.getenv("CASTLE") and type(top) == "table" and getmetatable(top) == require("src.ui.Gen4CastleScreen") then
        if i % 3 == 0 then pressed.b = true end
      elseif os.getenv("CASTLE") and type(top) == "table" and getmetatable(top) == MenuMT and top.items
             and top.items[3] and tostring(top.items[3].label):find("BATTLE") then
        if i % 3 == 0 then top.index = 3; pressed.a = true end
      elseif restArmed and type(top) == "table" and getmetatable(top) == MenuMT then
        -- "Keep going / Rest / Retire": Rest
        if not restDown then pressed.down = true; restDown = true
        elseif i % 3 == 0 then pressed.a = true; restArmed = false; print(("[t%d] chose Rest"):format(i)) end
      elseif top == ow and not talked and i > 30 then
        pressed.a = true
        talked = true
      elseif multi and not salonTalked and top == ow and mapId == "D31R0207"
             and not (ow.runner and ow.runner:isRunning()) and i % 30 == 0
             and (ow.player and ow.player.cellY == 4) then
        -- the Salon: stand below Cheryl (13,10) and talk
        local Commands = require("src.script.Commands")
        local ctx = { overworld = ow, game = Game, save = Game.save }
        Commands.g4_place_object(ctx, 255, 13, 11, 0, 0)
        if ow.player then ow.player.facing = "up" end
        pressed.a = true
        salonTalked = true
        print(("[t%d] talking to Cheryl"):format(i))
      elseif i % 3 == 0 and not (multi and top == ow)
             and not (type(top) == "table" and getmetatable(top) == require("src.ui.Gen3FactoryScreen")) then
        -- the doubles counter is the second row of "Single or Double"
        if double and type(top) == "table" and not top.doubleChosen
           and getmetatable(top) == MenuMT and _G.__btLastText == "TEXT_B0304_00004" then
          -- "Single or Double?": Double
          pressed.down = true; top.doubleChosen = true
        elseif multi and not linkDeclined and type(top) == "table"
               and getmetatable(top) == require("src.ui.ChoiceBox")
               and _G.__btLastText == "TEXT_B0304_00026" then
          -- "Communicate with a friend?": No
          pressed.down = true; linkDeclined = true
        else
          pressed.a = true
        end
      end
      if type(top) == "table" and top.choices and top ~= lastChoice then menuCount = menuCount + 1; lastChoice = top end
      Game.stack:update(1 / 60)
      -- after Rest's soft reset: Continue the save it wrote
      if restAt and not restored and Game.stack:top() and getmetatable(Game.stack:top()) ~= nil
         and Game.stack:top().screenId == "TitleState" then
        restored = true
        local loaded = SaveData.load()
        print(("[t%d] title screen -- continuing (save on %s)"):format(i, tostring(loaded and loaded.player and loaded.player.map)))
        Game:restoreSave(loaded)
        local function dumpReport(t, ind)
          for k, v in pairs(t or {}) do
            if type(v) == "table" then print(ind .. tostring(k) .. ":"); dumpReport(v, ind .. "  ")
            else print(ind .. tostring(k) .. " = " .. tostring(v)) end
          end
        end
        if Game.saveReport and not SaveData.emptyReport(Game.saveReport) then
          print("save report:"); dumpReport(Game.saveReport, "  ")
        end
        ow = Game.overworld
        talked = true
      end
      if _G.__btSnapAt == true then _G.__btSnapAt = i + 40 end
      if type(_G.__btSnapAt) == "number" and i >= _G.__btSnapAt then
        _G.__btHarness = Game
        print(("[t%d] capturing"):format(i))
        return
      end
      if os.getenv("FACTORY") and i % 3000 == 0 then
        local f = Game.gen4BattleFactory
        local rec = Game.save.gen4Factory
        print(("[t%d] factory: %s, BP %d, latest %s"):format(i,
          f and ("battle " .. f.currentBattle .. " streak " .. f.currentStreak .. " trades " .. f.tradeCount) or "none",
          require("src.pokemon.Gen4BattleTower").bp(Game.save), rec and rec.latest and tostring(rec.latest[0]) or "-"))
      end
      if os.getenv("ARCADE") and i % 3000 == 0 then
        local f = Game.gen4BattleArcade
        local BA = require("src.script.Gen4BattleArcade")
        local rec = BA.record(Game.save)
        print(("[t%d] arcade: %s, BP %d, latest %s, map %s"):format(i,
          f and ("battle " .. f.currentBattle .. " streak " .. f.currentStreak .. " effect " .. tostring(f.activeEffect)) or "none",
          require("src.pokemon.Gen4BattleTower").bp(Game.save), tostring(rec.latest[0]), tostring(mapId)))
      end
      if os.getenv("CASTLE") and i % 3000 == 0 then
        local f = Game.gen4BattleCastle
        local BC = require("src.script.Gen4BattleCastle")
        local rec = BC.record(Game.save)
        print(("[t%d] castle: %s, BP %d, CP %d, latest %s, map %s"):format(i,
          f and ("battle " .. f.currentBattle .. " streak " .. f.currentStreak) or "none",
          require("src.pokemon.Gen4BattleTower").bp(Game.save), BC.cp(Game.save, 0), tostring(rec.latest[0]), tostring(mapId)))
      end
      if os.getenv("HALL") and i % 2000 == 0 then
        local h = Game.gen4BattleHall
        local rec = Game.save.gen4Hall
        local Lobby = require("src.script.Gen4BattleHallLobby")
        print(("[t%d] hall: %s, record %s, singles total %d, species %d"):format(i, h and ("battle " .. h.battle .. " streak " .. h.streak) or "none",
          rec and rec.latest and tostring(rec.latest[0]) or "-", Lobby.totalSingles(Game.save), Lobby.speciesWithRecords(Game.save)))
      end
      local r = Game.save.gen4Frontier
      if os.getenv("WATCH") and mapId == "D31R0206" and i % 20 == 0 and battles == 0 then
        for _, n in ipairs(ow.npcs or {}) do
          local lid = n.localId or (n.def and n.def.localId)
          if lid == 4 or lid == 5 then
            print(("[t%d] obj %s cell %s,%s tgt %s,%s moving %s prog %s hidden %s frozen %s"):format(i, tostring(lid),
              tostring(n.cellX), tostring(n.cellY), tostring(n.targetX), tostring(n.targetY), tostring(n.moving),
              tostring(n.progress), tostring(n.hidden), tostring(n.frozen)))
          end
        end
      end
      if multi and i % 600 == 0 and os.getenv("TRACE") then
        print(("[t%d] tick: map %s top %s"):format(i, tostring(mapId), tostring(type(top) == "table" and (top.screenId or top.kind) or top)))
      end
      if r and r.challenges and r.challenges > 0 and mapId == "D31R0201" and not Game.gen4BattleTower and i > 600 then
        if not ow.runner or not ow.runner:isRunning() then
          print(("[t%d] back in the lobby"):format(i))
          break
        end
      end
    end
    local r = Game.save.gen4Frontier or {}
    local mi = multi and 2 or double and 1 or 0
    print(("record: bp %s, challenges %s, victories %s, room %s, streak best %s / current %s, alive %s"):format(
      tostring(r.bp), tostring(r.challenges), tostring(r.victories),
      tostring(r.rooms and r.rooms[mi]), tostring(r.stats and r.stats[mi * 2]),
      tostring(r.stats and r.stats[mi * 2 + 1]),
      tostring(require("src.pokemon.Gen4BattleTower").flag(r.flags and r or { flags = 0 }, 8 + mi, 0))))
    local lv = {}
    for _, m in ipairs(Game.save.party) do lv[#lv + 1] = tostring(m.level) end
    print("party levels after: " .. table.concat(lv, ","))
    local R = require("src.pokemon.Gen4GameRecords")
    print(("records: steps %d, castle victories %d, CP received %d, BP received %d, trainer score %d"):format(
      R.get(Game.save, R.ID.STEPS), R.get(Game.save, R.ID.BATTLE_CASTLE_VICTORIES),
      R.get(Game.save, R.ID.CASTLE_POINTS_RECEIVED), R.get(Game.save, R.ID.BATTLE_POINTS_RECEIVED), R.trainerScore(Game.save)))
  end, debug.traceback)
  if not ok then print(err) end
  if not _G.__btHarness then love.event.quit() end
end

-- SNAP=1: one real frame of the battle room as the first opponent speaks
function love.draw()
  local game = _G.__btHarness
  if not game then return end
  pcall(game.draw, game)
  if not _G.__btShot then
    _G.__btShot = true
    love.graphics.captureScreenshot(function(img)
      img:encode("png", "bt_room.png")
      print("wrote bt_room.png to " .. love.filesystem.getSaveDirectory())
      love.event.quit()
    end)
  end
end
