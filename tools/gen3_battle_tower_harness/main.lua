-- tools/gen3_battle_tower_harness/main.lua
--
-- AN EMERALD BATTLE TOWER CHALLENGE, PLAYED HEADLESS ON THE REAL ENGINE:
-- stands before the single-battle attendant (MAP_G26_N05, (6,5)), talks,
-- takes the first answer at every menu (Challenge, Lv. 50, Yes), enters the
-- first three party members, and mashes A through the battles. Prints each
-- map change, each opponent, the tower and Frontier calls with TRACE, and at
-- the end the record.
--
--   POKEPORT_DATA_DIR=<emerald cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<emerald cache> love tools/gen3_battle_tower_harness
--
-- Env: TICKS (default 120000), TRACE, STREAK (start the streak there, to
--      meet Anabel: 34 -> the 35th battle is hers), MULTI=1 with X=14 Y=6
--      (the multi counter: in the partner room, talk to the candidate at
--      (6,9) and say yes)

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("emerald")
    local Data = require("src.core.Data")
    Data:load()
    local SaveData = require("src.core.SaveData")
    local Game = require("src.core.Game")
    Game.data = Data
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
    Game.save.player.name = "MAY"

    local Pokemon = require("src.pokemon.Pokemon")
    local Stats = require("src.pokemon.Stats")
    Game.save.party = {}
    for _, sp in ipairs({ "METAGROSS", "SALAMENCE", "TYRANITAR", "GARDEVOIR" }) do
      local mon = Pokemon.new(Data, sp, 50)
      mon.ivs = { hp = 31, attack = 31, defense = 31, speed = 31, spatk = 31, spdef = 31 }
      mon.evs = { hp = 252, attack = 252, defense = 0, speed = 4, spatk = 0, spdef = 0 }
      local def = require("src.pokemon.Gen4Forms").definition(Data, mon)
      mon.stats = Stats.calc(def, 50, mon.ivs, nil, mon.evs, mon.nature)
      -- attacks first, so mashing A hits something
      local sets = { METAGROSS = { "METEOR_MASH", "EARTHQUAKE", "PSYCHIC", "SHADOW_BALL" },
        SALAMENCE = { "DRAGON_CLAW", "EARTHQUAKE", "FLAMETHROWER", "AERIAL_ACE" },
        TYRANITAR = { "ROCK_SLIDE", "EARTHQUAKE", "CRUNCH", "ICE_BEAM" },
        GARDEVOIR = { "PSYCHIC", "THUNDERBOLT", "ICE_BEAM", "CALM_MIND" } }
      mon.moves = {}
      for _, m in ipairs(sets[sp]) do
        local md = Data.moves[m]
        mon.moves[#mon.moves + 1] = { id = m, pp = md and md.pp or 10 }
      end
      mon.hp = mon.stats.hp
      Game.save.party[#Game.save.party + 1] = mon
    end
    local startStreak = tonumber(os.getenv("STREAK") or "")
    if startStreak then
      local F = require("src.script.Gen3BattleFrontier")
      local s = F.state(Game.save)
      -- STREAKFAC=4: that facility's streak instead of the Tower's
      local fac = tonumber(os.getenv("STREAKFAC") or "")
      F.setStreak(s, 0, 0, startStreak, fac)
      F.actives(s, fac)["0:0"] = true
    end

    local pressed = {}
    Game.input = {
      wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end,
      isDown = function() return false end,
      wasReleased = function() return false end,
    }
    local G3 = require("src.script.Gen3Commands")
    if os.getenv("TRACE") then
      local Commands = require("src.script.Commands")
      local real = Commands.show_text
      Commands.show_text = function(ctx, id, ...)
        local t = Data.text and Data.text[id] or (type(id) == "string" and id or nil)
        if type(id) == "string" and id:find("RAM:wStringBuffer4") then t = (Game.stringBuffers or {})[4] end
        print(("  text %s: %s"):format(tostring(id), tostring(t):gsub("\n", " "):sub(1, 80)))
        return real(ctx, id, ...)
      end
      for _, sp in ipairs({ 234, 235, 237, 239, 240 }) do
        local fn = G3.SPECIALS[sp]
        G3.SPECIALS[sp] = function(ctx)
          local arg = G3.getVar(ctx.save, 0x8004)
          local r = fn(ctx)
          if sp == 234 and arg == 0 then _G.__pollAt = true end
          if (sp == 235 or sp == 237) and arg == 0 and os.getenv("BATTLENUM") then
            ctx.save.gen3Frontier.data[2] = tonumber(os.getenv("BATTLENUM"))
          end
          print(("  special %d arm %s -> result %s, status var %s"):format(sp, tostring(arg),
            tostring(G3.getVar(ctx.save, 0x800D)), tostring(G3.getVar(ctx.save, 0x4000))))
          return r
        end
      end
    end
    -- REST=n: at "facing opponent no. n", answer the GO ON / REST / RETIRE
    -- menu with REST (the script's own path from there: save, soft reset),
    -- then Continue the save it wrote
    local restAt = tonumber(os.getenv("REST") or "")
    local restDone, restored = false, false
    if restAt then
      local Commands = require("src.script.Commands")
      local realMulti = Commands.g3_multichoice
      Commands.g3_multichoice = function(ctx, listId, ...)
        local s = ctx.save.gen3Frontier
        if not restDone and tonumber(listId) == 104 and s and (s.data[2] or 0) + 1 == restAt then
          restDone = true
          print(("  multichoice %s: REST"):format(tostring(listId)))
          G3.setVar(ctx.save, 0x800D, 1)
          return
        end
        return realMulti(ctx, listId, ...)
      end
    end
    -- DOME=1: the pre-battle room's menu (MULTI_TOURNEY_WITH/NO_RECORD): the
    -- opponent's card, then the tree, then Continue, every round
    if os.getenv("DOME") then
      local Commands = require("src.script.Commands")
      local realMulti = Commands.g3_multichoice
      local asked = 0
      Commands.g3_multichoice = function(ctx, listId, ...)
        local id = tonumber(listId)
        if id == tonumber(os.getenv("DOME_MENU_A") or "-1") or id == tonumber(os.getenv("DOME_MENU_B") or "-1") then
          asked = asked + 1
          local pick = ({ 0, 1 })[(asked - 1) % 3 + 1] or 2
          print(("  dome menu: %d"):format(pick))
          G3.setVar(ctx.save, 0x800D, pick)
          return
        end
        return realMulti(ctx, listId, ...)
      end
    end
    -- PALACE=1: the tower's battles under Battle Palace rules, to watch them
    if os.getenv("PALACE") then
      local Commands = require("src.script.Commands")
      local realStart = Commands.start_battle
      Commands.start_battle = function(ctx, kind, a, b, opts)
        opts = opts or {}
        opts.palace = true
        return realStart(ctx, kind, a, b, opts)
      end
      local B = require("src.battle.BattleState")
      local realSay = B.say
      B.say = function(self, text, ...)
        if type(text) == "string" and (text:find("incapable") or text:find("eager") or text:find("growling")
          or text:find("glint") or text:find("position")) then print("  palace: " .. (text:gsub("\n", " "))) end
        return realSay(self, text, ...)
      end
      local realSayNext = B.sayNext
      B.sayNext = function(self, text, ...)
        if type(text) == "string" and text:find("incapable") then print("  palace: " .. (text:gsub("\n", " "))) end
        return realSayNext(self, text, ...)
      end
    end
    -- ARENA=1: print the referee's lines and the judgment's scores
    if os.getenv("ARENA") then
      local B = require("src.battle.BattleState")
      for _, name in ipairs({ "say", "sayNext" }) do
        local real = B[name]
        B[name] = function(self, text, ...)
          if type(text) == "string" and (text:find("REFEREE") or text:find("takes it") or text:find("even!")
             or text:find("forfeit")) then
            print("  arena: " .. (text:gsub("\n", " ")))
          end
          return real(self, text, ...)
        end
      end
      local Arena = require("src.battle.Gen3Arena")
      if os.getenv("ARENADBG") then
        local realEnd = Arena.endMove
        Arena.endMove = function(battle, user)
          local o = battle.arenaOutcome or {}
          print(("  move by %s: failed %s typeMult %s protecting %s ability %s"):format(tostring(user and user.name),
            tostring(o.failed), tostring(o.typeMult), tostring(o.targetProtecting), tostring(o.ability)))
          return realEnd(battle, user)
        end
        local B = require("src.battle.BattleState")
        local realCancel = B.cancelMoveAnim
        B.cancelMoveAnim = function(self, ...)
          if self.arenaOutcome then
            print("  cancelMoveAnim from " .. tostring(debug.traceback("", 2):match("\n%s*([^\n]+)")))
          end
          return realCancel(self, ...)
        end
      end
      local realJudge = Arena.judge
      Arena.judge = function(battle)
        local st = battle.arenaState
        local r, t1, t2 = realJudge(battle)
        print(("  arena judge: mind %d-%d skill %d-%d hp %d/%d vs %d/%d -> %s %d-%d"):format(
          st.mind[1], st.mind[2], st.skill[1], st.skill[2], battle.player.mon.hp, st.startHp[1],
          battle.enemy.mon.hp, st.startHp[2], r, t1, t2))
        return realJudge(battle)
      end
    end
    -- PIKEROOM=5,7,4: the rooms behind the doors, in that order, then as drawn
    if os.getenv("PIKEROOM") then
      local Pike = require("src.script.Gen3BattlePike")
      local forced = {}
      for n in os.getenv("PIKEROOM"):gmatch("%d+") do forced[#forced + 1] = tonumber(n) end
      local real = Pike.nextRoom
      Pike.nextRoom = function(ctx)
        local r = table.remove(forced, 1)
        if r then
          if r == Pike.STATUS then Pike.inflictStatus(ctx, select(2, Pike.state(ctx.save))) end
          return r
        end
        return real(ctx)
      end
    end
    local OW = require("src.world.OverworldController")
    local LOBBY = os.getenv("MAP") or "MAP_G26_N05"
    Game.stack:push(OW, LOBBY, tonumber(os.getenv("X") or "6"), tonumber(os.getenv("Y") or "6"), "up")
    Game.overworld = Game.overworld or OW

    local lastMap, lastTop, battles, talked = nil, nil, 0, false
    local ticks = tonumber(os.getenv("TICKS") or "120000")
    for i = 1, ticks do
      -- a press nobody read last tick is not carried into this one
      for k in pairs(pressed) do pressed[k] = nil end
      local top = Game.stack:top()
      local ow = Game.overworld
      local mapId = ow and ow.map and ow.map.id
      if mapId ~= lastMap then print(("[t%d] map %s"):format(i, tostring(mapId))); lastMap = mapId end
      if top ~= lastTop then
        if type(top) == "table" and top.kind and top.enemy and not top.trainer and os.getenv("PYRAMID") then
          local _, r3 = require("src.script.Gen3BattlePyramid").state(Game.save)
          print(("[t%d] wild %s Lv%s (light %d)"):format(i, tostring(top.enemy.mon and top.enemy.mon.species),
            tostring(top.enemy.mon and top.enemy.mon.level), r3.light))
        end
        if type(top) == "table" and top.kind and top.enemy and top.trainer then
          battles = battles + 1
          local s = Game.save.gen3Frontier or {}
          print(("[t%d] battle vs %s %s%s, levels %s -- battle no. %s"):format(i, tostring(top.trainer.className),
            tostring(top.trainer.name), top.trainerB and (" and " .. tostring(top.trainerB.name)) or "",
            tostring(top.enemy.mon and top.enemy.mon.level), tostring((s.data or {})[2])))
          if top.ally then
            local ap = {}
            for k, m in ipairs(top.ally.party or {}) do ap[k] = tostring(m.species) end
            print(("   partner %s with %s"):format(tostring(top.ally.name), table.concat(ap, " ")))
          end
          if os.getenv("PYRAMID") then
            local _, r3 = require("src.script.Gen3BattlePyramid").state(Game.save)
            local ps = {}
            for k, m in ipairs(Game.save.party or {}) do ps[k] = ("%s %d/%d"):format(tostring(m.species), m.hp or 0, m.stats and m.stats.hp or 0) end
            print(("   pyramid: trainer bits %d, enemy %s Lv%s, party %s"):format(r3.trainerFlags,
              tostring(top.enemy.mon and top.enemy.mon.species), tostring(top.enemy.mon and top.enemy.mon.level), table.concat(ps, ", ")))
          end
          if os.getenv("FACTORY_PARTY") then
            local ps = {}
            for k, m in ipairs(Game.save.party or {}) do ps[k] = tostring(m.species) end
            print("   party: " .. table.concat(ps, " "))
          end
        end
        lastTop = top
      end
      if type(top) == "table" and top.chooseOrder and top.onOrder then
        Game.stack:pop()
        top.onOrder(top.chooseOrder and top.chooseOrder.most == 4 and { 1, 2, 3, 4 } or { 1, 2, 3 })
        print(("[t%d] entered slots 1, 2, 3"):format(i))
      elseif type(top) == "table" and getmetatable(top) == require("src.ui.Gen3PartyMenu") then
        -- a fainted lead: walk down to someone standing, then send them out
        local party = Game.save.party or {}
        local at = top.cursor or top.index or top.selected
        if os.getenv("TRACE") and i % 81 == 0 then
          local hp = {}
          for k, m in ipairs(party) do hp[#hp + 1] = k .. "=" .. tostring(m.hp) end
          print(("  party menu: index %s, mode %s, hp %s"):format(tostring(at), tostring(top.mode or top.purpose), table.concat(hp, " ")))
        end
        local mon = at and party[at]
        if mon and (mon.hp or 0) > 0 then
          if i % 3 == 0 then pressed.a = true end
        elseif i % 3 == 0 then
          pressed.down = true
        end
      elseif type(top) == "table" and top.kind and top.phase == "moveSelect" and top.player
             and top.player.curMoves and i % 3 == 0 then
        -- a move with PP left (PP carries over in the Pyramid)
        local moves = top.player.curMoves
        local m = moves[top.moveIndex or 1]
        if m and (m.pp or 1) <= 0 then
          for k, mv in ipairs(moves) do if (mv.pp or 1) > 0 then top.moveIndex = k break end end
        end
        pressed.a = true
      elseif os.getenv("FORFEIT") and not _G.__forfeitAsked and type(top) == "table" and top.kind
             and top.phase == "menu" and top.menuActions then
        -- FORFEIT=1: RUN at the first battle menu, then YES
        for k, a in ipairs(top:menuActions()) do if a == "run" then top.menuIndex = k end end
        pressed.a = true
        _G.__forfeitAsked = true
        print(("[t%d] chose RUN"):format(i))
      elseif type(top) == "table" and getmetatable(top) == require("src.ui.Gen3FactoryScreen") then
        -- the Factory: the first three on offer; at a swap, keep (or FSWAP=1: first for first)
        if i % 3 == 0 and not top.asking then
          if top.mode == "select" then
            top.index = #top.picks + 1
            pressed.a = true
          elseif os.getenv("FSWAP") then
            top.index = 1
            pressed.a = true
          else
            pressed.b = true
          end
          if _G.__factoryLogged ~= top then
            _G.__factoryLogged = top
            local names = {}
            for k, m in ipairs(top.mons) do names[k] = tostring(m.species) .. ":" .. tostring(m.level) end
            local theirs = {}
            for k, m in ipairs(top.theirs or {}) do theirs[k] = tostring(m.species) end
            print(("[t%d] factory %s screen: %s | theirs %s"):format(i, top.mode, table.concat(names, " "), table.concat(theirs, " ")))
          end
        end
      elseif os.getenv("PYRAMID") and top == ow and talked and ow.map
             and (ow.map.id == "MAP_G26_N26" or ow.map.id == "MAP_G26_N27")
             and not (ow.runner and ow.runner:isRunning()) and not ow.transitioning
             and not ow.engaging and i > (_G.__pyrAct or 0) + 12 then
        -- PYRAMID=1: walk the floor to its exit a step at a time (breadth
        -- first, round walls and people), then talk to the summit attendant
        _G.__pyrAct = i
        local p = ow.player
        local Pyr = require("src.script.Gen3BattlePyramid")
        local s3, r3 = Pyr.state(Game.save)
        if ow.map.id == "MAP_G26_N27" then
          if G3.getVar(Game.save, 0x400D) ~= 0 and not _G.__pyrBrandon then
            -- the attendant has stepped aside: up the steps onto Brandon's trigger (17,9)
            _G.__pyrBrandon = true
            for _, y in ipairs({ 11, 10, 9 }) do
              p.cellX, p.cellY, p.facing = 17, y, "up"
              if p.x then p.x, p.y = 17 * 16, y * 16 end
              p.elevation = ow.map:cellElevation(17, y) or p.elevation
            end
            ow:onStepComplete()
            print(("[t%d] the summit: onto Brandon's trigger (elevation %s)"):format(i, tostring(p.elevation)))
          elseif (_G.__pyrTop or 0) < 5 and i % 60 < 13 and not _G.__pyrBrandon then
            _G.__pyrTop = (_G.__pyrTop or 0) + 1
            p.cellX, p.cellY, p.facing = 17, 12, "up"
            if p.x then p.x, p.y = 17 * 16, 12 * 16 end
            p.elevation = ow.map:cellElevation(17, 12) or p.elevation
            pressed.a = true
            print(("[t%d] the summit: talking to the attendant"):format(i))
            if _G.__pyrTop == 1 then
              for _, n in ipairs(ow.npcs or {}) do
                print(("   npc %s at (%s,%s) hidden %s text %s talk %s"):format(tostring(n.def and n.def.localId), tostring(n.cellX), tostring(n.cellY),
                  tostring(n.hidden), tostring(n.def and n.def.text),
                  tostring(require("src.script.MapScripts").talkScript(ow.map.id, n.def and n.def.text) ~= nil)))
              end
              print(("   player (%d,%d) px (%s,%s) facing %s"):format(p.cellX, p.cellY, tostring(p.x), tostring(p.y), tostring(p.facing)))
            end
          end
        else
          local exit = ow.map.def.pyramidExit
          local key = tostring(s3.data[2]) .. ":" .. tostring(r3.randoms[1])
          -- PYRSKIP=6: the first floor counts as the seventh (the summit is next)
          local skip = tonumber(os.getenv("PYRSKIP") or "")
          if skip and not _G.__pyrSkipped then
            _G.__pyrSkipped = true
            s3.data[2] = skip
            require("src.script.Gen3BattlePyramid").setStreak(s3, skip + (tonumber(os.getenv("PYRSTREAK") or "") or 0))
          end
          if os.getenv("PYRITEM") and (_G.__pyrItem or 0) < 3 and i > (_G.__pyrItemAt or 0) + 300 then
            -- PYRITEM=1: stand below (or beside) an item ball and pick it up, up to three
            _G.__pyrItemAt = i
            local bagNow = {}
            for k2, v in pairs(Game.save.inventory or {}) do bagNow[#bagNow + 1] = tostring(k2) .. "x" .. tostring(v) end
            print(("[t%d]   bag: %s"):format(i, table.concat(bagNow, ", ")))
            for _, n in ipairs(ow.npcs or {}) do
              if n.def and n.def.text == "PYRAMID_ITEM" and not n.hidden then
                for _, d in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }) do
                  local x, y = n.cellX + d[1], n.cellY + d[2]
                  if ow.map:isWalkableCell(x, y) then
                    _G.__pyrItem = (_G.__pyrItem or 0) + 1
                    p.cellX, p.cellY, p.facing = x, y, d[3]
                    if p.x then p.x, p.y = x * 16, y * 16 end
                    p.elevation = ow.map:cellElevation(x, y) or p.elevation
                    pressed.a = true
                    _G.__pyrHold = i + 90
                    print(("[t%d]   picking up the item ball %d at (%d,%d) -- its elevation %s, mine %s, talk %s"):format(i,
                      n.def.localId, n.cellX, n.cellY, tostring(n.elevation or n.def.elevation), tostring(p.elevation),
                      tostring(require("src.script.MapScripts").talkScript(ow.map.id, n.def.text) ~= nil)))
                    break
                  end
                end
                break
              end
            end
          end
          if os.getenv("PYRWEAK") and not _G.__pyrWeak then
            -- PYRWEAK=1: the team at 1 HP, so the floor's first battle is lost
            _G.__pyrWeak = true
            for _, m in ipairs(Game.save.party or {}) do
              m.hp = 1
              for _, mv in ipairs(m.moves or {}) do mv.pp = 0 end
            end
          end
          if _G.__pyrFloor ~= key then
            _G.__pyrFloor = key
            local t = Pyr.template(s3, r3)
            print(("[t%d] floor %d: template %d (%d trainers, %d items), player (%d,%d), exit (%s,%s), light %d -- %s"):format(i,
              s3.data[2] + 1, Pyr.templateId(s3, r3), t.numTrainers, t.numItems, p.cellX, p.cellY,
              tostring(exit and exit.x), tostring(exit and exit.y), r3.light, (function()
                local t2 = {}
                for _, m in ipairs(Game.save.party or {}) do t2[#t2 + 1] = ("%s %d/%d"):format(tostring(m.species), m.hp or 0, m.stats and m.stats.hp or 0) end
                return table.concat(t2, ", ") end)()))
          end
          if i % 600 < 13 then
            local okb, b = pcall(ow.map.blockAt, ow.map, p.cellX, p.cellY)
            print(("[t%d]   at (%d,%d), exit (%s,%s) block %s onExit %s runner %s"):format(i, p.cellX, p.cellY,
              tostring(exit and exit.x), tostring(exit and exit.y), tostring(b), tostring(Pyr.onExitTile(ow.map, p.cellX, p.cellY)),
              tostring(ow.runner:isRunning())))
          end
          if exit and i > (_G.__pyrHold or 0) then
            local busy = {}
            for _, n in ipairs(ow.npcs or {}) do if not n.hidden then busy[n.cellX .. "," .. n.cellY] = true end end
            local prev, q, head = { [p.cellX .. "," .. p.cellY] = false }, { { p.cellX, p.cellY } }, 1
            local goal = exit.x .. "," .. exit.y
            while q[head] and prev[goal] == nil do
              local c = q[head]; head = head + 1
              for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
                local nx, ny = c[1] + d[1], c[2] + d[2]
                local k = nx .. "," .. ny
                if prev[k] == nil and nx >= 0 and ny >= 0 and nx < 32 and ny < 32
                   and (k == goal or (ow.map:isWalkableCell(nx, ny) and not busy[k])) then
                  prev[k] = c[1] .. "," .. c[2]
                  q[#q + 1] = { nx, ny }
                end
              end
            end
            if prev[goal] ~= nil then
              local step = goal
              while prev[step] and prev[step] ~= (p.cellX .. "," .. p.cellY) do step = prev[step] end
              local sx, sy = step:match("(%-?%d+),(%-?%d+)")
              sx, sy = tonumber(sx), tonumber(sy)
              p.facing = (sx > p.cellX and "right") or (sx < p.cellX and "left") or (sy > p.cellY and "down") or "up"
              p.cellX, p.cellY = sx, sy
              if p.x then p.x, p.y = sx * 16, sy * 16 end
              p.elevation = ow.map:elevationAfter(p.elevation, sx, sy) or p.elevation
              ow:onStepComplete()
            elseif not _G.__pyrStuck then
              _G.__pyrStuck = true
              print(("[t%d] no path from (%d,%d) to the exit"):format(i, p.cellX, p.cellY))
            end
          end
        end
      elseif os.getenv("PIKE") and top == ow and talked and ow.map
             and (ow.map.id == "MAP_G26_N36" or ow.map.id == "MAP_G26_N37" or ow.map.id == "MAP_G26_N39")
             and not (ow.runner and ow.runner:isRunning()) and not ow.transitioning
             and i > (_G.__pikeAct or 0) + 150 then
        -- PIKE=1: a door in the three-path room, the exit once a room is done,
        -- and a walk in the wild room's grass first
        _G.__pikeAct = i
        local ms = Game.data.map_scripts
        local ms = ms and (ms[ow.map.id] or (ms.maps and ms.maps[ow.map.id]))
        local ev = (ms and ms.coords) or {}
        local Pike = require("src.script.Gen3BattlePike")
        local _, pk = Pike.state(Game.save)
        local function hp()
          local t = {}
          for _, m in ipairs(Game.save.party or {}) do
            t[#t + 1] = ("%s %d/%d%s"):format(tostring(m.species), m.hp or 0, m.stats and m.stats.hp or 0,
              m.status and (" " .. tostring(m.status)) or "")
          end
          return table.concat(t, ", ")
        end
        if ow.map.id == "MAP_G26_N36" then
          local door = tonumber(os.getenv("DOOR") or "") or love.math.random(1, 3)
          print(("[t%d] room %s: door %d (hint: door %s is type %s) -- %s"):format(i,
            tostring(Game.save.gen3Frontier.data[2]), door, tostring(pk.hintIndex and pk.hintIndex + 1),
            tostring(pk.hintType), hp()))
          ow:gen3RunFieldScript(ev[door].script, "harness door")
        else
          if ow.map.id == "MAP_G26_N37" and (pk.room == 2 or pk.room == 4)
             and _G.__pikeTalkedRoom ~= Game.save.gen3Frontier.data[2] then
            -- talk to the room's NPC: (5,5) for a talker, (4,4) for the heal
            _G.__pikeTalkedRoom = Game.save.gen3Frontier.data[2]
            local p = ow.player
            if pk.room == 2 then p.cellX, p.cellY = 5, 6 else p.cellX, p.cellY = 4, 5 end
            p.facing = "up"
            pressed.a = true
            print(("[t%d] talking to the room's NPC (type %d)"):format(i, pk.room))
          elseif ow.map.id == "MAP_G26_N39" and not _G.__pikeGrassDone then
            _G.__pikeGrassDone = true
            local p = ow.player
            for y = 0, (ow.map.heightCells or 24) - 1 do for x = 0, (ow.map.widthCells or 12) - 1 do
              if not _G.__pikeCell and ow.map:isEncounterCell(x, y) then _G.__pikeCell = { x, y } end
            end end
            print(("  wild room: grass at %s"):format(_G.__pikeCell and (_G.__pikeCell[1] .. "," .. _G.__pikeCell[2]) or "none"))
            if not _G.__pikeCell then
              local seen, list = {}, {}
              for y = 0, (ow.map.heightCells or 24) - 1 do for x = 0, (ow.map.widthCells or 12) - 1 do
                local t = ow.map:cellTile(x, y)
                if t and not seen[t] then seen[t] = true; list[#list + 1] = tostring(t) end
              end end
              local enc = {}
              for k in pairs(ow.map.encounterTiles or {}) do enc[#enc + 1] = tostring(k) end
              print(("  wild room tiles %s; tileset %s encounter tiles %s"):format(table.concat(list, " "),
                tostring(ow.map.def.tileset), table.concat(enc, " ")))
            end
            _G.__pikeCell = _G.__pikeCell or { 4, 12 }
            if _G.__pikeCell then
              p.cellX, p.cellY = _G.__pikeCell[1], _G.__pikeCell[2]
              for _ = 1, 300 do
                ow:onStepComplete()
                if Game.stack:top() ~= ow or ow.transitioning or ow.pendingBattle then break end
              end
            end
          else
            _G.__pikeGrassDone = nil
            _G.__pikeCell = nil
            print(("[t%d] leaving room type %s -- %s"):format(i, tostring(pk.room), hp()))
            ow:gen3RunFieldScript(ev[1].script, "harness exit")
          end
        end
      elseif os.getenv("MULTI") and mapId == "MAP_G26_N15" and top == ow and not _G.__multiTalked
             and not (ow.runner and ow.runner:isRunning()) and i % 30 == 0 and ow.player then
        -- the partner room: below the candidate at (6,9), facing up, and talk
        ow.player.cellX, ow.player.cellY, ow.player.facing = 6, 10, "up"
        if ow.player.syncPosition then pcall(ow.player.syncPosition, ow.player) end
        pressed.a = true
        _G.__multiTalked = true
        print(("[t%d] talking to the candidate at (6,9)"):format(i))
      elseif os.getenv("MULTI") and mapId == "MAP_G26_N15" and type(top) == "table" and top ~= ow
             and top.items and top.index and #top.items == 2 then
        -- "form a tag team?": YES (the default is NO)
        if i % 3 == 0 then top.index = 1; pressed.a = true end
      elseif top == ow and not talked and i > 30 then
        pressed.a = true; talked = true
      elseif i % 3 == 0 then
        pressed.a = true
      end
      if os.getenv("TRACE") and i % 2000 == 0 and type(top) == "table" then
        local fields = {}
        for _, k in ipairs({ "phase", "state", "mode", "screenId", "menu", "waiting", "queue" }) do
          if top[k] ~= nil then fields[#fields + 1] = k .. "=" .. (type(top[k]) == "table" and ("#" .. #top[k]) or tostring(top[k])) end
        end
        if top.turnCount then fields[#fields + 1] = "turn=" .. tostring(top.turnCount) .. " pmon=" .. tostring(top.player and top.player.mon and top.player.mon.hp) .. " emon=" .. tostring(top.enemy and top.enemy.mon and top.enemy.mon.hp) end
        print(("[t%d] top: %s"):format(i, table.concat(fields, " ")))
        if os.getenv("DUMP") and i == tonumber(os.getenv("DUMP")) then
          local keys = {}
          for k, v in pairs(top) do
            if type(v) ~= "table" and type(v) ~= "function" and type(v) ~= "userdata" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v):gsub("%s", "_") end
          end
          table.sort(keys)
          print("  dump: " .. table.concat(keys, " "))
          if top.current then print("  current: " .. tostring(top.current.kind or top.current[1])) end
        end
      end
      if _G.__pollAt and os.getenv("FRAMEDEBUG") then
        _G.__pollTicks = (_G.__pollTicks or 0) + 1
        if _G.__pollTicks <= 12 then
          local owx = Game.overworld
          print(("  tick %d: running=%s transitioning=%s pending=%s top=%s var=%s pressA=%s"):format(i,
            tostring(owx.runner:isRunning()), tostring(owx.transitioning), tostring(owx.pendingScripts and #owx.pendingScripts),
            tostring(top == owx), tostring(G3.getVar(Game.save, 0x4000)), tostring(pressed.a)))
        end
      end
      Game.stack:update(1 / 60)
      if restDone and not restored and Game.stack:top() and Game.stack:top().screenId == "TitleState" then
        restored = true
        local loaded = SaveData.load()
        print(("[t%d] title screen -- continuing (saved on %s, party %d)"):format(i, tostring(loaded and loaded.player and loaded.player.map),
          #((loaded and loaded.party) or {})))
        Game:restoreSave(loaded)
      end
      local s = Game.save.gen3Frontier
      if s and s.data and (tonumber(Game.save.gen3BattlePoints) or 0) > (_G.__bpBefore or 0) and mapId == LOBBY then
        local runner = Game.overworld and Game.overworld.runner
        if (not runner or not runner:isRunning()) and G3.getVar(Game.save, 0x4000) == 255 then
          print(("[t%d] back in the lobby, done"):format(i))
          break
        end
      end
    end
    local s = Game.save.gen3Frontier or {}
    do
      local GS = require("src.pokemon.Gen3GameStats")
      print(("game stats: steps %d, battles %d (wild %d, trainer %d), frontier battles %s, saved %d"):format(
        GS.get(Game.save, GS.STEPS), GS.get(Game.save, GS.TOTAL_BATTLES), GS.get(Game.save, GS.WILD_BATTLES),
        GS.get(Game.save, GS.TRAINER_BATTLES), tostring(Game.save.gen3FrontierBattles), GS.get(Game.save, GS.SAVED_GAME)))
    end
    print(("record: status %s, BP %s, streak %s, active %s, symbols silver=%s gold=%s"):format(
      tostring((s.data or {})[0]), tostring(Game.save.gen3BattlePoints),
      tostring((s.towerStreaks or {})["0:0"]), tostring((s.streakActive or {})["0:0"]),
      tostring((Game.save.flags or {})["FLAG_G3_08C4"]), tostring((Game.save.flags or {})["FLAG_G3_08C5"])))
    local lv = {}
    for _, m in ipairs(Game.save.party) do lv[#lv + 1] = tostring(m.species) .. ":" .. tostring(m.level) .. "/" .. tostring(m.item) end
    print("party after: " .. table.concat(lv, ", "))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
