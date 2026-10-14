-- tools/gen3_double_scenario/main.lua
--
-- A DOUBLE BATTLE, SCRIPTED: Marshtomp and Hariyama against a two-Pokemon
-- trainer on the real engine, every message printed.
--
--   turn 1: both hit the left foe (it faints, nothing on the bench)
--   turn 2: both hit the right foe; Marshtomp is faster and knocks it out --
--           Hariyama must not move after that (the battle is won)
--
--   POKEPORT_DATA_DIR=<emerald cache>/data/generated \
--   POKEPORT_ASSET_ROOT=<emerald cache> love tools/gen3_double_scenario

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set("emerald")
    local Data = require("src.core.Data")
    Data:load()
    local SaveData = require("src.core.SaveData")
    local Game = require("src.core.Game")
    Game.data = Data
    require("src.render.Font").load(Data)
    require("src.ui.Theme").load(Data)
    require("src.core.Strings").load(Data)
    local StateStack = require("src.core.StateStack")
    StateStack:init()
    Game.stack = StateStack
    Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
    Game.save.player.name = "MAY"
    local pressed = {}
    Game.input = {
      wasPressed = function(_, k) local v = pressed[k]; pressed[k] = nil; return v end,
      isDown = function() return false end,
      wasReleased = function() return false end,
    }

    local Pokemon = require("src.pokemon.Pokemon")
    local function mon(sp, level, moves)
      local m = Pokemon.new(Data, sp, level)
      m.moves = {}
      for _, id in ipairs(moves) do m.moves[#m.moves + 1] = { id = id, pp = 20 } end
      return m
    end
    local marshtomp = mon("MARSHTOMP", 40, { "MUD_SHOT", "WATER_GUN" })
    local hariyama = mon("HARIYAMA", 30, { "ARM_THRUST", "FAKE_OUT" })
    marshtomp.stats.speed, hariyama.stats.speed = 200, 10
    Game.save.party = { marshtomp, hariyama }

    local foeL, foeR = mon("ZIGZAGOON", 10, { "TACKLE" }), mon("POOCHYENA", 10, { "TACKLE" })
    foeL.hp = 1
    foeR.stats.hp, foeR.hp = 500, 500
    Data.trainers.SCENARIO_DOUBLE = { id = "SCENARIO_DOUBLE", name = "TWINS", baseMoney = 0, doubleBattle = true,
      party = { { species = "ZIGZAGOON", level = 10, prebuilt = foeL }, { species = "POOCHYENA", level = 10, prebuilt = foeR } } }
    Data.trainers.SCENARIO_DOUBLE.parties = { Data.trainers.SCENARIO_DOUBLE.party }

    local BattleState = require("src.battle.BattleState")
    BattleState.DOUBLES_READY = true
    for _, name in ipairs({ "say", "sayNext" }) do
      local real = BattleState[name]
      BattleState[name] = function(self, text, ...)
        print(("  msg: %s"):format(tostring(text):gsub("\n", " ")))
        return real(self, text, ...)
      end
    end
    local realExec = BattleState.executeAction
    BattleState.executeAction = function(self, user, target, action)
      print(("  exec: %s -> %s (hp %s, player %s, same as user %s) result %s"):format(tostring(user and user.name),
        tostring(target and target.name), tostring(target and target.mon and target.mon.hp), tostring(target and target.isPlayer),
        tostring(target == user), tostring(self.result)))
      return realExec(self, user, target, action)
    end
    local realPerform = BattleState.performMove
    BattleState.performMove = function(self, user, target, ...)
      print(("  perform: %s -> %s (hp %s)"):format(tostring(user and user.name), tostring(target and target.name),
        tostring(target and target.mon and target.mon.hp)))
      return realPerform(self, user, target, ...)
    end
    local Targeting = require("src.battle.Targeting")
    local realRedirect = Targeting.redirect
    Targeting.redirect = function(battle, user, move, target)
      local out = realRedirect(battle, user, move, target)
      local foes = {}
      for _, f in ipairs(battle:foesOf(user)) do foes[#foes + 1] = f.name end
      print(("  redirect(%s, chosen %s isPlayer %s) -> %s; user.isPlayer %s; foes {%s}; enemy %s/%s"):format(tostring(user and user.name), tostring(target and target.name or target),
        tostring(target and target.isPlayer), tostring(out[1] and out[1].name), tostring(user and user.isPlayer), table.concat(foes, ","),
        tostring(battle.enemy and battle.enemy.name), tostring(battle.enemy and battle.enemy.mon.hp)))
      return out
    end
    local realDefault = BattleState.defaultTargetFor
    BattleState.defaultTargetFor = function(self, user)
      local t = realDefault(self, user)
      print(("  default(%s) -> %s"):format(tostring(user and user.name), tostring(t and t.name)))
      return t
    end
    local b = BattleState.newTrainer(Game, "SCENARIO_DOUBLE", 1)
    if b.sendOutSecondPair then b:sendOutSecondPair() end
    b.double = true
    b.onFinish = function(r) print("battle over: " .. tostring(r)); _G.__done = true end
    Game.stack:push(b)
    print(("double %s; foes %s / %s"):format(tostring(b:isDouble()), tostring(b:battlerAt(1) and b:battlerAt(1).name),
      tostring(b:battlerAt(3) and b:battlerAt(3).name)))

    local turn = 0
    for i = 1, 6000 do
      if _G.__done then break end
      local top = Game.stack:top()
      if top == b and b.phase == "menu" and not b.choosingSlot and turn < 2 then
        turn = turn + 1
        local left, right = b:battlerAt(0), b:battlerAt(2)
        local aim = (turn == 1) and b:battlerAt(1) or b:battlerAt(3)
        print(("turn %d: both at %s (hp %s)"):format(turn, tostring(aim and aim.name), tostring(aim and aim.mon.hp)))
        if turn == 2 then aim.mon.hp = 1 end
        b.chosenTargets = { [0] = aim, [2] = aim }
        b:chooseAction(left.curMoves[1])
        -- turn 1: FAKE OUT (the second move); turn 2: ARM THRUST
        b:chooseAction(right.curMoves[(turn == 1) and 2 or 1])
      elseif i % 3 == 0 then
        pressed.a = true
      end
      Game.stack:update(1 / 60)
    end
    print(("hariyama hp %d/%d, marshtomp hp %d/%d"):format(hariyama.hp, hariyama.stats.hp, marshtomp.hp, marshtomp.stats.hp))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
