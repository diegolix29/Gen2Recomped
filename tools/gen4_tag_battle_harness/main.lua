-- tools/gen4_tag_battle_harness/main.lua
--
-- A PLATINUM TAG BATTLE ON THE REAL ENGINE: Jubilife's two Galactic Grunts
-- (414, 415) against the player and a partner (ALLY, default 613 Lucas),
-- through g4_start_tag_battle; prints every move the partner picks.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \n--   POKEPORT_ASSET_ROOT=<platinum cache> love tools/gen4_tag_battle_harness

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
    Game.save.player.name = "DAWN"

    -- a strong team, maxed out so seven in a row is likely
    local Pokemon = require("src.pokemon.Pokemon")
    local Stats = require("src.pokemon.Stats")
    local level = tonumber(os.getenv("LEVEL") or "9")
    Game.save.party = {}
    for _, sp in ipairs({ 393, 396 }) do   -- Piplup, Starly (the Jubilife scene's level)
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
    local AllyAI = require("src.battle.AllyAI")
    local realChoose = AllyAI.choose
    AllyAI.choose = function(battle, battler, rng)
      local mv = realChoose(battle, battler, rng)
      local t = battle.chosenTargets and battle.chosenTargets[battler.position]
      print(("  ally %s (lv %s, hp %s) uses %s on %s"):format(tostring(battler.name), tostring(battler.mon.level),
        tostring(battler.mon.hp), tostring(mv and mv.id), tostring(t and t.name)))
      return mv
    end
    local OW = require("src.world.OverworldController")
    Game.stack:push(OW, os.getenv("MAP") or "C01", 20, 20, "down")
    Game.overworld = Game.overworld or OW
    local partner = tonumber(os.getenv("ALLY") or "613")
    local started, result = false, nil
    for i = 1, tonumber(os.getenv("TICKS") or "30000") do
      for k in pairs(pressed) do pressed[k] = nil end
      local ow = Game.overworld
      if not started and i > 30 and not ow.runner:isRunning() then
        started = true
        if os.getenv("WILD") then
          -- WILD=1: a step in the grass with Cheryl (608) walking beside you
          require("src.world.Gen4Follower").setPartner(Game.save, true)
          require("src.script.Gen4Commands").setVar(Game.save, 0x403F, 608)
          local Encounter = require("src.world.Encounter")
          Encounter.gen4StepAllowed = function() return true end
          local p = ow.player
          local found
          for y = 0, (ow.map.heightCells or 64) - 1 do
            for x = 0, (ow.map.widthCells or 64) - 1 do
              if not found and ow.map:isEncounterCell(x, y) then found = { x, y } end
            end
          end
          if found then p.cellX, p.cellY = found[1], found[2] end
          print(("  stepping at %s,%s (map %s w=%s h=%s grass@here=%s enc=%s)"):format(tostring(p.cellX), tostring(p.cellY), tostring(ow.map.id), tostring(ow.map.width), tostring(ow.map.height), tostring(ow.map:isGrassCell(p.cellX, p.cellY)), tostring(require("src.world.Encounter").forMap(Game.data, ow.map.def, ow.map.id, nil, Game.save) ~= nil)))
          Game.save.party[1].hp = 1
          local pushed = false
          local realPush = ow.pushBattle
          ow.pushBattle = function(self, b, ...)
            pushed = true
            _G.__wildBattle = b
            return realPush(self, b, ...)
          end
          for _ = 1, 400 do
            ow:onStepComplete()
            if pushed then break end
          end
          ow.pushBattle = realPush
        elseif os.getenv("ESCORT") then
          -- an escort (FLAG_HAS_PARTNER + VAR_PARTNER_TRAINER_ID) and an
          -- ordinary `starttrainerbattle` against one grunt
          require("src.world.Gen4Follower").setPartner(Game.save, true)
          require("src.script.Gen4Commands").setVar(Game.save, 0x403F, tonumber(os.getenv("ESCORT")))
          ow.runner:run({ { "g4_start_battle", 414, 0 }, { "g4_check_won_battle", 0x8000 } }, {})
        else
          ow.runner:run({ { "g4_start_tag_battle", partner, 414, 415 }, { "g4_check_won_battle", 0x8000 } }, {})
        end
      end
      local top = Game.stack:top()
      if type(top) == "table" and top.kind and top.enemy and not top.__seen then
        top.__seen = true
        local b = top.battlerAt and top:battlerAt(2)
        print(("[t%d] battle: double=%s, right slot %s (ally=%s), foes %s and %s"):format(i, tostring(top.double),
          tostring(b and b.name), tostring(b and b.ally), tostring(top.enemy and top.enemy.name),
          tostring(top:battlerAt(3) and top:battlerAt(3).name)))
      end
      if i % 3 == 0 then pressed.a = true end
      Game.stack:update(1 / 60)
      if os.getenv("WILD") and started and top == ow and i > 300 then
        local b = _G.__wildBattle
        print(("[t%d] wild battle over: %s"):format(i, tostring(b and b.result)))
        break
      end
      if not os.getenv("WILD") and started and not ow.runner:isRunning() and top == ow then
        result = require("src.script.Gen4Commands").getVar(Game.save, 0x8000)
        print(("[t%d] battle over -- won=%s"):format(i, tostring(result)))
        break
      end
    end
    do
      local t = Game.stack:top()
      local function nm(x) return x and (x.name .. ":" .. tostring(x.mon and x.mon.hp)) or "-" end
      if type(t) == "table" and t.kind then
        print(("end state: phase %s queue %d result %s afterQueue %s slots %s %s %s %s"):format(tostring(t.phase),
          #(t.queue or {}), tostring(t.result), tostring(t.afterQueue), nm(t:battlerAt(0)), nm(t:battlerAt(1)),
          nm(t:battlerAt(2)), nm(t:battlerAt(3))))
      else
        print("end state: top " .. tostring(type(t) == "table" and (t.screenId or getmetatable(t)) or t))
      end
    end
    local lv = {}
    for _, m in ipairs(Game.save.party) do lv[#lv + 1] = tostring(m.species) .. ":" .. tostring(m.level) .. "/" .. tostring(m.hp) end
    print("party after: " .. table.concat(lv, ", "))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
