-- tools/gen4_frontier_harness/main.lua
--
-- A BATTLE FRONTIER SCENE, PLAYED HEADLESS ON THE REAL ENGINE: launches a
-- frontier scene (src/ui/Gen4FrontierScene.lua) straight from the field, with
-- the field variables the facility's lobby would have set, mashes A, and
-- prints every message, menu, object and movement until the scene leaves.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_frontier_harness
--
-- Env: SCENE (default 9, the Battle Hall corridor), TICKS (default 6000),
--      SNAP=n (save a screenshot at tick n to the save directory),
--      HALLTYPE=1 (a doubles challenge), LEVEL=n (the party's level),
--      FACTORY=1 (the Battle Factory instead; OPENLEVEL=1, FSWAP=1 to trade),
--      CASTLE=1 (the Battle Castle: the self app, then the opponent app, are
--      each opened once a battle and a purchase made in each; PASS=n passes
--      the n-th battle; LOSE=n loses it),
--      ARCADE=1 (the Battle Arcade: the Game Board stopped at once, and what it
--      landed on printed; ARCADESTREAK=n carries on a streak).

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
    local ModLoader = require("src.mods.Loader")
    Game.mods = ModLoader.new()
    Game.mods:load(Data)
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
    Game.save = SaveData.newGame(Game:bootConfig())
    if Game.adoptSave then pcall(Game.adoptSave, Game, Game.save, true) end
    Game.save.player.name = "LUCAS"
    local Pokemon = require("src.pokemon.Pokemon")
    Game.save.party = { Pokemon.new(Data, 445, 50) }

    local pressed = {}
    Game.input = {
      wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end,
      isDown = function() return false end,
      wasReleased = function() return false end,
    }
    local Commands = require("src.script.Commands")
    local realText = Commands.show_text
    Commands.show_text = function(ctx, id, ...)
      local t = Data.text and Data.text[id]
      print(("  text %s: %s"):format(tostring(id), tostring(t):gsub("\n", " "):sub(1, 90)))
      return realText(ctx, id, ...)
    end
    local OW = require("src.world.OverworldController")
    Game.stack:push(OW, "D32R0401", 8, 8, "up")
    Game.overworld = Game.overworld or OW

    local Scene = require("src.ui.Gen4FrontierScene")
    local realAdd, realMove = Scene.addObject, Scene.move
    Scene.addObject = function(self, row, gfx)
      local o = realAdd(self, row, gfx)
      print(("  object %d: gfx %d at (%d,%d)%s%s"):format(row.id, gfx, row.x, row.y,
        o.sprite and "" or " (no sprite)", o.hidden and " hidden" or ""))
      return o
    end
    Scene.move = function(self, id, list)
      print(("  move %d: %d step(s)"):format(id, #(list or {})))
      return realMove(self, id, list)
    end
    local G4 = require("src.script.Gen4Commands")
    -- what the Hall's lobby sets before the scene (VAR_BATTLE_HALL_CHALLENGE_TYPE
    -- 0x40BB, VAR_MAP_LOCAL_0x02..0x05)
    -- HALLTYPE=1: a doubles challenge, with a second Pokemon in slot 2;
    -- LEVEL=n: the party's level (a low one loses)
    local hallType = tonumber(os.getenv("HALLTYPE") or "0")
    local level = tonumber(os.getenv("LEVEL") or "50")
    Game.save.party = { Pokemon.new(Data, 445, level), Pokemon.new(Data, 448, level) }
    -- HALLSTREAK=40: a live streak to carry on (40: Argenta is the round's tenth)
    local hs = tonumber(os.getenv("HALLSTREAK") or "")
    if hs then
      local rec = require("src.script.Gen4BattleHall").record(Game.save)
      rec.streakActive[hallType] = true
      rec.latest = { [hallType] = hs }
    end
    G4.setVar(Game.save, 0x40BB, hallType)
    G4.setVar(Game.save, 0x4003, 0)
    G4.setVar(Game.save, 0x4002, 0)
    G4.setVar(Game.save, 0x4005, hallType == 1 and 1 or 0)
    -- the Battle Hall: who comes out, and how each battle went
    local H = require("src.script.Gen4BattleHall")
    local realBattle = Commands.fr_hall_battle
    Commands.fr_hall_battle = function(ctx, ...)
      local h = ctx.game.gen4BattleHall
      if h then
        local off = h.battle * 2
        local set = Data.gen4_battle_tower and Data.gen4_battle_tower.hallSets[h.monIndices[off] or -1]
        print(("  hall battle %d (streak %d): type cell %s, rank %d, trainer %s, species %s at level %s"):format(
          h.battle + 1, h.streak, tostring(h.selectedIdx2), h.ranks[h.selectedIdx] or 0,
          tostring(h.trainerIDs[off]), tostring(set and set.species), tostring(h.opponentsLevel)))
      end
      -- LOSE=n: the n-th battle is lost without being fought (the loss branch)
      local r
      if h and tonumber(os.getenv("LOSE") or "") == h.battle + 1 then
        ctx.game.gen4BattleHallWon = 0
      else
        r = realBattle(ctx, ...)
      end
      local rec = Data.trainers.GEN4_BATTLE_HALL
      local foes = {}
      for k, slot in ipairs(rec and rec.parties[1] or {}) do
        local m = slot.prebuilt or {}
        foes[k] = ("%s Lv%s pid %s"):format(tostring(m.species), tostring(m.level), tostring(m.personality))
      end
      print("  hall battle result: " .. tostring(ctx.game.gen4BattleHallWon) .. " -- foes " .. table.concat(foes, ", "))
      return r
    end
    local _ = H
    -- FACTORY=1: the Battle Factory's corridor (scene 3) with its lobby's vars
    -- (VAR_BATTLE_FACTORY_CHALLENGE_TYPE 0x40B8, _LEVEL 0x40B9); OPENLEVEL=1
    if os.getenv("FACTORY") then
      G4.setVar(Game.save, 0x40B8, hallType)
      G4.setVar(Game.save, 0x40B9, tonumber(os.getenv("OPENLEVEL") or "0"))
      local Commands2 = require("src.script.Commands")
      require("src.script.Gen4FrontierScrCmds")
      require("src.script.Gen4BattleFactory")
      local realBf = Commands2.fr_bf_battle
      Commands2.fr_bf_battle = function(ctx, ...)
        local f = ctx.game.gen4BattleFactory
        local names = {}
        for k, e in ipairs(f and f.playerEntries or {}) do names[k] = tostring(e.species) end
        local theirs = {}
        for k, e in ipairs(f and f.opponentParty or {}) do theirs[k] = tostring(e.species) end
        print(("  factory battle %d (streak %d, trades %d): mine %s vs trainer %s's %s"):format((f and f.currentBattle or 0) + 1,
          f and f.currentStreak or 0, f and f.tradeCount or 0, table.concat(names, " "),
          tostring(f and f.trainerIDs[f.currentBattle]), table.concat(theirs, " ")))
        local r = realBf(ctx, ...)
        print("  factory battle result: " .. tostring(ctx.game.gen4BattleFactoryWon))
        return r
      end
    end
    -- CASTLE=1: the Battle Castle's corridor (scene 11) with its lobby's vars
    -- (VAR_BATTLE_CASTLE_CHALLENGE_TYPE 0x40BD; the three slots in
    -- VAR_MAP_LOCAL_0x02 / 0x05 / 0x06)
    local castleMenuStep = 0
    if os.getenv("CASTLE") then
      G4.setVar(Game.save, 0x40BD, hallType)
      G4.setVar(Game.save, 0x4002, 0)
      G4.setVar(Game.save, 0x4005, 1)
      G4.setVar(Game.save, 0x4006, 2)
      Game.save.party = { Pokemon.new(Data, 445, level), Pokemon.new(Data, 448, level), Pokemon.new(Data, 392, level + 20) }
      Game.save.party[1].item = 234
      require("src.script.Gen4FrontierScrCmds")
      local BC = require("src.script.Gen4BattleCastle")
      -- CASTLESTREAK=n: a live streak of n (a multiple of 7) to carry on, with 100 CP
      local cs = tonumber(os.getenv("CASTLESTREAK") or "")
      if cs then
        local rec = BC.record(Game.save)
        rec.streakActive[hallType], rec.latest[hallType], rec.cp[hallType] = true, cs, 100
      end
      local realBc = Commands.fr_bc_battle
      Commands.fr_bc_battle = function(ctx, ...)
        local f = ctx.game.gen4BattleCastle
        local mine, theirs = {}, {}
        for k, m in ipairs(f and f.team or {}) do mine[k] = ("%s Lv%d %d/%d%s"):format(tostring(m.species), m.level or 0,
          m.hp or 0, m.stats and m.stats.hp or 0, m.item and (" @" .. m.item) or "") end
        for k, m in ipairs(f and f.opponentParty or {}) do theirs[k] = ("%s Lv%d"):format(tostring(m.species), m.level or 0) end
        print(("  castle battle %d (streak %d, %d CP): mine %s vs trainer %s's %s"):format((f and f.currentBattle or 0) + 1,
          f and f.currentStreak or 0, BC.cp(Game.save, f and f.challengeType or 0), table.concat(mine, ", "),
          tostring(f and f.trainerIDs[f.currentBattle]), table.concat(theirs, ", ")))
        local r
        if f and tonumber(os.getenv("LOSE") or "") == f.currentBattle + 1 then ctx.game.gen4BattleCastleWon = 0
        else r = realBc(ctx, ...) end
        print("  castle battle result: " .. tostring(ctx.game.gen4BattleCastleWon))
        return r
      end
      local realCall = Commands.fr_bc_call
      Commands.fr_bc_call = function(ctx, cmd, ...)
        local r = realCall(ctx, cmd, ...)
        local f = ctx.game.gen4BattleCastle
        if tonumber(cmd) == 27 and f then
          print(("  castle CP earned -> now %d"):format(BC.cp(Game.save, f.challengeType)))
        end
        return r
      end
    end
    -- ARCADE=1: the Battle Arcade's corridor (scene 15); VAR_BATTLE_ARCADE_CHALLENGE_TYPE 0x40BE
    if os.getenv("ARCADE") then
      G4.setVar(Game.save, 0x40BE, hallType)
      G4.setVar(Game.save, 0x4002, 0)
      G4.setVar(Game.save, 0x4005, 1)
      G4.setVar(Game.save, 0x4006, 2)
      Game.save.party = { Pokemon.new(Data, 445, level), Pokemon.new(Data, 448, level), Pokemon.new(Data, 392, level + 20) }
      Game.save.party[1].item = 234
      require("src.script.Gen4FrontierScrCmds")
      local BA = require("src.script.Gen4BattleArcade")
      local as = tonumber(os.getenv("ARCADESTREAK") or "")
      if as then
        local rec = BA.record(Game.save)
        rec.streakActive[hallType], rec.latest[hallType] = true, as
      end
      -- ARCADEFX=23,22,27,...: the board lands on these, battle by battle
      local fx = {}
      for n in (os.getenv("ARCADEFX") or ""):gmatch("%d+") do fx[#fx + 1] = tonumber(n) end
      local realApp = Commands.fr_ba_app
      Commands.fr_ba_app = function(ctx, ...)
        local r = realApp(ctx, ...)
        local f = ctx.game.gen4BattleArcade
        if f and #fx > 0 then f.activeEffect = table.remove(fx, 1) end
        return r
      end
      local realApply = Commands.fr_ba_apply
      Commands.fr_ba_apply = function(ctx, ...)
        local f = ctx.game.gen4BattleArcade
        local r = realApply(ctx, ...)
        if f then
          local names = {}
          for k, e in ipairs(f.grid or {}) do names[k] = tostring(e) end
          local mine, theirs = {}, {}
          for k, m in ipairs(f.team or {}) do mine[k] = ("%s Lv%d %d/%d %s @%s"):format(tostring(m.species), m.level or 0,
            m.hp or 0, m.stats and m.stats.hp or 0, tostring(m.status or "-"), tostring(m.item)) end
          for k, m in ipairs(f.opponentParty or {}) do theirs[k] = ("%s Lv%d %d/%d %s @%s"):format(tostring(m.species), m.level or 0,
            m.hp or 0, m.stats and m.stats.hp or 0, tostring(m.status or "-"), tostring(m.item)) end
          print(("  arcade board (round %d, perf %d, speed %d): [%s] -> effect %s (%s), weather %s, immune %s"):format(BA.round(f),
            f.performance or 0, f.rouletteSpeed or 0, table.concat(names, " "), tostring(f.activeEffect),
            require("src.ui.Gen4ArcadeScreen").LABELS[f.activeEffect] or "?", tostring(f.weather), tostring(f.immuneToEffect)))
          print("    mine: " .. table.concat(mine, ", ") .. " | theirs: " .. table.concat(theirs, ", "))
        end
        return r
      end
      local realBa = Commands.fr_ba_battle
      Commands.fr_ba_battle = function(ctx, ...)
        local f = ctx.game.gen4BattleArcade
        print(("  arcade battle %d (streak %d) vs trainer %s"):format((f and f.currentBattle or 0) + 1, f and f.currentStreak or 0,
          tostring(f and f.trainerIDs[f.currentBattle])))
        local r
        if f and tonumber(os.getenv("LOSE") or "") == f.currentBattle + 1 then ctx.game.gen4BattleArcadeWon = 0
        elseif f and os.getenv("ARCADEWIN") then
          -- the fight skipped as a win: the team put back as the battle would leave it
          ctx.game.gen4BattleArcadeWon = 1
          f.performance = BA.performance(f.team, 5)
          local items = {}
          for k, m in ipairs(f.team) do items[k] = m.item end
          f.team = require("src.script.Gen4BattleTowerCommands").copy(f.snapshot or f.team)
          for k, m in ipairs(f.team) do require("src.pokemon.Pokemon").heal(m); m.item = items[k] end
        else r = realBa(ctx, ...) end
        print(("  arcade battle result: %s, performance %s; team %s"):format(tostring(ctx.game.gen4BattleArcadeWon),
          tostring(f and f.performance), f and f.team and f.team[1] and ("Lv" .. f.team[1].level .. " @" .. tostring(f.team[1].item)) or "?"))
        return r
      end
    end
    local sceneId = tonumber(os.getenv("SCENE") or (os.getenv("FACTORY") and "3" or os.getenv("CASTLE") and "11" or os.getenv("ARCADE") and "15" or "9"))
    local done = false
    Game.stack:push(Scene.new(Game, { scene = sceneId, onExit = function() done = true end }))
    local snapAt = tonumber(os.getenv("SNAP") or "")
    for i = 1, tonumber(os.getenv("TICKS") or "6000") do
      for k in pairs(pressed) do pressed[k] = nil end
      local top = Game.stack:top()
      if i % 2000 == 0 and type(top) == "table" then
        print(("[t%d] top %s phase %s turn %s pmon %s/%s emon %s/%s"):format(i, tostring(top.screenId or (getmetatable(top) and getmetatable(top).__name) or "?"),
          tostring(top.phase), tostring(top.turn), tostring(top.player and top.player.mon and top.player.mon.species),
          tostring(top.player and top.player.mon and top.player.mon.hp), tostring(top.enemy and top.enemy.mon and top.enemy.mon.species),
          tostring(top.enemy and top.enemy.mon and top.enemy.mon.hp)))
        if top.phase == "messages" then
          local q = top.queue or top.messages or {}
          local m = q[1]
          print(("   queue %d, head %s, waiting %s, pendingSwitch %s, stack depth %d"):format(#q,
            type(m) == "table" and tostring(m.text or m.kind or m[1]) or tostring(m), tostring(top.waiting or top.waitingFor),
            tostring(top.afterQueue), #(Game.stack.states or Game.stack.stack or {})))
          print(("   current %s waitFrames %s anim4 %s ui %s slide %s ballPlaying %s switching %s"):format(tostring(top.current and (top.current.text or top.current.kind or top.current.type)),
            tostring(top.waitFrames), tostring(top.gen4AnimPlaying), tostring(top.waitingUI), tostring(top.introSlide),
            tostring(top.gen3BallPlaying or top.gen4BallPlaying), tostring(top.switching or top.sendingOut)))
        end
      end
      if type(top) == "table" and top.phase == "moveSelect" and top.player and top.player.curMoves then
        -- a move with PP left
        local moves = top.player.curMoves
        local m = moves[top.moveIndex or 1]
        if m and (m.pp or 1) <= 0 then
          for k, mv in ipairs(moves) do if (mv.pp or 1) > 0 then top.moveIndex = k break end end
        end
      end
      if type(top) == "table" and getmetatable(top) == require("src.ui.Gen4BattleParty") and top.party then
        -- a fainted lead: the cursor onto someone still standing before A
        local party = top:party()
        local cur = party[top.index or 1]
        if cur and (cur.hp or 0) <= 0 then
          for k, m in ipairs(party) do if (m.hp or 0) > 0 then top.index = k break end end
        end
      end
      local Menu = require("src.ui.Menu")
      if os.getenv("CASTLE") and type(top) == "table" and getmetatable(top) == require("src.ui.Gen4CastleScreen") then
        -- the apps: one purchase each, then out
        if not top.harnessed then
          top.harnessed = true
          local BC = require("src.script.Gen4BattleCastle")
          local f = top.castle
          if top.mode == "self" then
            local okH, why = BC.heal(f, 1, BC.HEAL_HP)
            local okR = BC.rent(f, 1, BC.BERRIES[8], BC.BERRY_PRICES[8])
            print(("  self app: heal %s (%s), Sitrus rented %s -> %d CP"):format(tostring(okH), tostring(why), tostring(okR),
              BC.cp(Game.save, f.challengeType)))
          else
            local okI = BC.reveal(f, 1)
            local okL = BC.adjustLevel(f, 2, BC.ADJ_UP)
            print(("  opponent app: identity %s, level +5 %s (now Lv%s) -> %d CP"):format(tostring(okI), tostring(okL),
              tostring(f.opponentParty[2] and f.opponentParty[2].level), BC.cp(Game.save, f.challengeType)))
          end
        elseif i % 4 == 0 then pressed.b = true end
      elseif os.getenv("CASTLE") and type(top) == "table" and getmetatable(top) == Menu and top.items
             and #top.items >= 3 and tostring(top.items[3].label):find("BATTLE") then
        -- SELF / OPPONENT / BATTLE / PASS: the self app, the opponent app, then
        -- battle (or pass, PASS=n)
        if i % 4 == 0 then
          castleMenuStep = castleMenuStep + 1
          local f = Game.gen4BattleCastle
          local want = (castleMenuStep % 3 == 1) and 1 or (castleMenuStep % 3 == 2) and 2 or 3
          if want == 3 and f and tonumber(os.getenv("PASS") or "") == f.currentBattle + 1 and top.items[4] then want = 4 end
          top.index = want
          print(("  castle menu: %s"):format(tostring(top.items[want].label)))
          pressed.a = true
        end
      elseif type(top) == "table" and getmetatable(top) == require("src.ui.Gen3FactoryScreen") then
        -- the rental screen: the first three; at a trade, keep (FSWAP=1: first for first)
        if i % 4 == 0 and not top.asking then
          if top.mode == "select" then top.index = #top.picks + 1; pressed.a = true
          elseif os.getenv("FSWAP") then top.index = 1; pressed.a = true
          else pressed.b = true end
        end
      elseif i % 4 == 0 then pressed.a = true end
      Game.stack:update(1 / 60)
      if snapAt and i == snapAt then
        _G.__frontierSnap = Game
        print(("[t%d] capturing"):format(i))
        return
      end
      if done and os.getenv("ARCADE") then
        local BA = require("src.script.Gen4BattleArcade")
        local rec = BA.record(Game.save)
        print(("[t%d] arcade: BP %d, streak %s (record %s, active %s); party %s Lv%d @%s"):format(i,
          require("src.pokemon.Gen4BattleTower").bp(Game.save), tostring(rec.latest[hallType]), tostring(rec.records[hallType]),
          tostring(rec.streakActive[hallType]), tostring(Game.save.party[3].species), Game.save.party[3].level, tostring(Game.save.party[1].item)))
      end
      if done then
        local R = require("src.pokemon.Gen4GameRecords")
        print(("[t%d] records: castle victories %d, CP received %d, BP received %d, score %d"):format(i,
          R.get(Game.save, R.ID.BATTLE_CASTLE_VICTORIES), R.get(Game.save, R.ID.CASTLE_POINTS_RECEIVED),
          R.get(Game.save, R.ID.BATTLE_POINTS_RECEIVED), R.trainerScore(Game.save)))
      end
      if done and os.getenv("CASTLE") then
        local BC = require("src.script.Gen4BattleCastle")
        local rec = BC.record(Game.save)
        print(("[t%d] castle: BP %d, streak %s (record %s, active %s), %d CP, lobby action %s; party %s Lv%d @%s"):format(i,
          require("src.pokemon.Gen4BattleTower").bp(Game.save), tostring(rec.latest[hallType]), tostring(rec.records[hallType]),
          tostring(rec.streakActive[hallType]), BC.cp(Game.save, hallType), tostring(G4.getVar(Game.save, 0x40BC)),
          tostring(Game.save.party[3].species), Game.save.party[3].level, tostring(Game.save.party[1].item)))
      end
      if done then
        local Lobby = require("src.script.Gen4BattleHallLobby")
        print(("[t%d] the scene left the frontier (Hall singles record total %d over %d species)"):format(i,
          Lobby.totalSingles(Game.save), Lobby.speciesWithRecords(Game.save)))
        break
      end
    end
  end, debug.traceback)
  if not ok then print(err) end
  if not _G.__frontierSnap then love.event.quit() end
end

function love.draw()
  local game = _G.__frontierSnap
  if not game then return end
  love.graphics.push()
  pcall(game.stack.draw, game.stack)
  love.graphics.pop()
  if not _G.__frontierShot then
    _G.__frontierShot = true
    love.graphics.captureScreenshot(function(img)
      img:encode("png", "frontier_scene.png")
      print("wrote frontier_scene.png to " .. love.filesystem.getSaveDirectory())
      love.event.quit()
    end)
  end
end
