-- tools/gen4_blackout_sweep_harness/main.lua
--
-- The overworld harness (tools/gen4_overworld_harness) with four things added,
-- for the whiteout and the "froze after a wild Pidgey" reports. Run it through
-- the HGSS wrapper so an installed version folder is mounted:
--
--   INSTALL=G:/Gen2Recomped/heartgold VERSION=heartgold \
--   HARNESS=gen4_blackout_sweep_harness MAP=R29 X=.. Y=.. WALK=left ENC_FORCE=1 \
--   SWEEP_SPECIES=16 SWEEP_LEVEL=3 SWEEP_ENEMY_MOVES=33,28,16 \
--   SWEEP_PLAN="m1,m2,m3,m4*|run|ball*" TICKS=20000 OUT_DIR=... \
--     lovec tools/gen4_hgss_overworld_harness
--
--   SNAP=<playthrough snapshot .lua>   the game starts on that snapshot's save
--                                      (MAP / X / Y still pick where)
--   SWEEP_SPECIES=16[,19,...]          every wild battle is against these, in turn
--   SWEEP_LEVEL=n                      ...at this level
--   SWEEP_ENEMY_MOVES=33,28,16         the foe knows these and uses them in turn
--   SWEEP_PLAN="seg|seg|..."           one segment per battle: m1..m4 a move
--                                      slot, run, ball (a Poke Ball), wait (do
--                                      nothing this turn is not possible, so
--                                      m1); a trailing * repeats the last
--   SWEEP_LEAD_HP=n                    the lead starts each battle on n HP
--   TRACE_POS=1                        every change of map / cell / facing /
--                                      top state, printed
--   STALL=<ticks>                      a "stall" line (with the battle's gates)
--                                      when nothing has moved for that long
--   DRAW_EVERY=n                       draw the whole stack every n ticks (a
--                                      draw that raises is printed)
--   SHOT_ON_STALL=1                    a PNG (OUT_DIR) at each stall

io.stdout:setvbuf("line")
local getenv = os.getenv

-- ------------------------------------------------------------ the snapshot --
if getenv("SNAP") then
  local SaveData = require("src.core.SaveData")
  local newGame = SaveData.newGame
  SaveData.newGame = function(...)
    local okL, snap = pcall(dofile, getenv("SNAP"))
    if okL and type(snap) == "table" then
      local okD, save = pcall(SaveData.decode, snap.save)
      if okD and type(save) == "table" then
        print(("[sweep] save from %s (was at %s %d,%d)"):format(getenv("SNAP"), tostring(snap.map), snap.x or 0, snap.y or 0))
        -- a playthrough snapshot carries the run's REPEL; wild battles are the point here
        if getenv("SWEEP_ENC") or getenv("SWEEP_SPECIES") then save.repelSteps = nil end
        return save
      end
    end
    print("[sweep] SNAP did not load; new game")
    return newGame(...)
  end
end

-- ------------------------------------------------------------- the battles --
local function list(s, num)
  local out = {}
  for v in tostring(s or ""):gmatch("[^,]+") do out[#out + 1] = num and tonumber(v) or v end
  return out
end
local species = list(getenv("SWEEP_SPECIES"), true)
local enemyMoves = list(getenv("SWEEP_ENEMY_MOVES"), true)
local segments = {}
for seg in tostring(getenv("SWEEP_PLAN") or ""):gmatch("[^|]+") do segments[#segments + 1] = seg end
local battleNo = 0
_G.__sweep = { battles = {}, stalls = 0 }

local BattleState = require("src.battle.BattleState")
local newWild = BattleState.newWild
BattleState.newWild = function(game, sp, level, ...)
  battleNo = battleNo + 1
  if #species > 0 then sp = species[(battleNo - 1) % #species + 1] end
  if getenv("SWEEP_LEVEL") then level = tonumber(getenv("SWEEP_LEVEL")) end
  local b = newWild(game, sp, level, ...)
  if b then
    b.__sweepNo = battleNo
    b.__plan = list(segments[(battleNo - 1) % math.max(1, #segments) + 1] or "m1*")
    b.__planAt = 1
    b.__enemyTurn = 0
    print(("[sweep] battle %d: wild %s Lv%s, plan %s"):format(battleNo, tostring(sp), tostring(level),
      table.concat(b.__plan, ",")))
    _G.__sweep.battles[battleNo] = { species = sp, result = nil }
  end
  return b
end

local enter = BattleState.enter
BattleState.enter = function(self, ...)
  local r = { enter(self, ...) }
  if self.__sweepNo then
    if #enemyMoves > 0 and self.enemy and self.enemy.curMoves then
      local cur = {}
      for i, id in ipairs(enemyMoves) do
        if i > 4 then break end
        local d = self.data.moves[id]
        cur[i] = { id = id, pp = (d and d.pp) or 30, maxPP = (d and d.pp) or 30 }
      end
      self.enemy.curMoves = cur
      if self.enemy.mon then self.enemy.mon.moves = cur end
    end
  end
  -- SWEEP_HEAL=1: the party starts every battle healthy
  if getenv("SWEEP_HEAL") and self.player and self.player.mon then
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(self.game.save.party or {}) do Pokemon.heal(mon) end
    self.player.shownHP = self.player.mon.hp
  end
  -- every battle, wild or trainer: the lead starts on this much HP
  if getenv("SWEEP_LEAD_HP") and self.player and self.player.mon then
    self.player.mon.hp = math.min(self.player.mon.hp, tonumber(getenv("SWEEP_LEAD_HP")))
    self.player.shownHP = self.player.mon.hp
    for i, mon in ipairs(self.game.save.party or {}) do
      if i > 1 then mon.hp = 0 end
    end
  end
  return (table.unpack or unpack)(r)
end

-- SWEEP_ENC=1: every step on an encounter tile meets something (Black and
-- White roll their own rate, which ENC_FORCE does not reach)
if getenv("SWEEP_ENC") then
  local OW = require("src.world.OverworldController")
  local Encounter = require("src.world.Encounter")
  local roll = OW.rollEncounter
  OW.rollEncounter = function(self, encDef, terrain)
    local e = roll(self, encDef, terrain)
    if not e and encDef and encDef.grass then e = Encounter.roll(encDef, nil, nil, 255) end
    return e
  end
end

-- TEXT_TRACE=1: every field text box, as it opens
if getenv("TEXT_TRACE") then
  local TextBox = require("src.render.TextBox")
  local tbNew = TextBox.new
  TextBox.new = function(game, text, ...)
    print("[text] " .. (tostring(text):sub(1, 90):gsub("%c", " / ")))
    return tbNew(game, text, ...)
  end
end

-- every message a battle types, in order
local startMessage = BattleState.startMessage
BattleState.startMessage = function(self, item)
  if item and item.text then print("[msg] " .. (tostring(item.text):gsub("%c", " / "))) end
  return startMessage(self, item)
end

local enemyAction = BattleState.enemyAction
BattleState.enemyAction = function(self, battler)
  if self.__sweepNo and #enemyMoves > 0 and (battler == nil or battler == self.enemy) then
    local cur = self.enemy and self.enemy.curMoves
    if cur and #cur > 0 then
      self.__enemyTurn = self.__enemyTurn + 1
      local mv = cur[(self.__enemyTurn - 1) % #cur + 1]
      print(("[sweep]   foe uses %s"):format(tostring(self.data.moves[mv.id] and self.data.moves[mv.id].name or mv.id)))
      return mv
    end
  end
  return enemyAction(self, battler)
end

local finish = BattleState.finish
BattleState.finish = function(self, ...)
  if self.__sweepNo and not self.__finished then
    self.__finished = true
    print(("[sweep] battle %d finished: %s"):format(self.__sweepNo, tostring(self.result)))
    _G.__sweep.battles[self.__sweepNo].result = self.result
  end
  return finish(self, ...)
end

local update = BattleState.update
BattleState.update = function(self, dt)
  if self.__sweepNo and self.phase == "menu" and self.game.stack:top() == self then
    local plan = self.__plan
    local step = plan[math.min(self.__planAt, #plan)] or "m1"
    local rep = step:sub(-1) == "*"
    if rep then step = step:sub(1, -2) else self.__planAt = self.__planAt + 1 end
    local slot = tonumber(step:match("^m(%d)$"))
    if slot then
      local cur = self.player and self.player.curMoves or {}
      local mv = cur[slot] or cur[1]
      if mv and (tonumber(mv.pp) or 1) <= 0 then mv.pp = 5 end
      print(("[sweep]   turn: %s"):format(tostring(mv and self.data.moves[mv.id] and self.data.moves[mv.id].name)))
      self.phase = "messages"
      self.afterQueue = "menu"
      local ok, err = pcall(self.chooseAction, self, mv)
      if not ok then print("[sweep]   chooseAction raised: " .. tostring(err)) end
      return
    elseif step == "run" then
      print("[sweep]   turn: run")
      local ok, err = pcall(self.tryRun, self)
      if not ok then print("[sweep]   tryRun raised: " .. tostring(err)) end
      return
    elseif step == "ball" then
      print("[sweep]   turn: Poke Ball")
      local ItemEffects = require("src.inventory.ItemEffects")
      local id = 4
      self.phase = "messages"
      self.afterQueue = "menu"
      local ok, err = pcall(self.throwBall, self, ItemEffects.alias(id, self.data.items[id]))
      if not ok then print("[sweep]   throwBall raised: " .. tostring(err)) end
      return
    end
  end
  return update(self, dt)
end

-- ------------------------------------------------------ tracing and stalls --
local StateStack = require("src.core.StateStack")
local stackUpdate = StateStack.update
local tick, lastSig, sameFor, lastPos = 0, nil, 0, nil
local stallAt = tonumber(getenv("STALL") or "900")
local drawEvery = tonumber(getenv("DRAW_EVERY") or "0")
local function describe(st)
  if not st then return "nil" end
  if st.battle or st.phase then return "battle(" .. tostring(st.phase) .. ")" end
  return StateStack.describe(st)
end
local function shot(game, tag)
  local w, h = love.graphics.getDimensions()
  local canvas = love.graphics.newCanvas(w, h)
  love.graphics.push("all")
  -- the game's own passes end with setCanvas(): keep them on this canvas
  -- (the same trick as the overworld harness's SHOTS)
  local setCanvas = love.graphics.setCanvas
  local target = { canvas, depth = true }
  love.graphics.setCanvas = function(c, ...)
    if c == nil then return setCanvas(target) end
    return setCanvas(c, ...)
  end
  setCanvas(target)
  love.graphics.clear(0, 0, 0, 1)
  local ok, err = pcall(game.draw, game)
  love.graphics.setCanvas = setCanvas
  setCanvas()
  love.graphics.pop()
  if not ok then print("[sweep] draw raised: " .. tostring(err)) return end
  if getenv("OUT_DIR") then
    pcall(function() canvas:newImageData():encode("png", ("sweep_%s_%s.png"):format(getenv("TAG") or "run", tag)) end)
  end
end
_G.__sweepShot = shot
StateStack.update = function(self, dt)
  tick = tick + 1
  local r = { stackUpdate(self, dt) }
  local G = package.loaded["src.core.Game"]
  if not (G and G.stack == self) then return (table.unpack or unpack)(r) end
  local top = self:top()
  local ow
  for _, st in ipairs(self.states) do if st.player and st.map then ow = st end end
  local p = ow and ow.player
  local pos = ow and ("%s %s,%s %s"):format(tostring(ow.map.id), tostring(p.cellX), tostring(p.cellY), tostring(p.facing)) or "-"
  local b = top and top.phase and top
  local sig = table.concat({ describe(top), pos, b and tostring(#(b.queue or {})) or "",
    b and tostring(b.current) or "", b and tostring(b.waitFrames) or "", b and tostring(b.phase) or "",
    tostring(top and top.t), tostring(top and top.frame), tostring(top and top.index), tostring(p and p.moving),
    tostring(ow and ow.runner and ow.runner.pc), tostring(top and top.timer), tostring(top and top.shown),
    tostring(top and top.charIndex), tostring(top and top.chars) }, "|")
  if getenv("TRACE_POS") and pos .. describe(top) ~= lastPos then
    lastPos = pos .. describe(top)
    local beh = ow and ow.map and ow.map.cellBehaviour and p and p.cellX and ow.map:cellBehaviour(p.cellX, p.cellY)
    print(("[pos] t=%d %s beh=%s top=%s money=%s lastHeal=%s"):format(tick, pos, tostring(beh), describe(top),
      tostring(G.save and G.save.money),
      G.save and G.save.lastHeal and ("%s %s,%s"):format(G.save.lastHeal.map, G.save.lastHeal.x, G.save.lastHeal.y) or "nil"))
  end
  if sig == lastSig then sameFor = sameFor + 1 else sameFor, lastSig = 0, sig end
  if sameFor == stallAt then
    _G.__sweep.stalls = _G.__sweep.stalls + 1
    print(("[sweep] STALL t=%d: nothing moved for %d ticks; top=%s pos=%s stack=%s"):format(tick, stallAt,
      describe(top), pos, self:describeAll()))
    if b then
      print(("[sweep]   gates: ui=%s anim4=%s wait=%s sound=%s drain=%s exp=%s anim=%s current=%s queue=%d after=%s intro=%s"):format(
        tostring(b.waitingUI), tostring(b.gen4AnimPlaying), tostring(b.waitFrames), tostring(b.waitingSound),
        tostring(b.draining), tostring(b.expFilling), tostring(b.animPlaying),
        tostring(b.current and (b.current.text or "item")), #(b.queue or {}), tostring(b.afterQueue), tostring(b.introSlide)))
    end
    if ow then
      local rn = ow.runner
      print(("[sweep]   field: script running=%s lastRow=%s waitingFrames=%s waitingCheck=%s pending=%d transitioning=%s locked=%s moving=%s scriptMoves=%d"):format(
        tostring(rn and rn:isRunning()), tostring(rn and rn.lastRow), tostring(rn and rn.waitingFrames),
        tostring(rn and rn.waitingCheck ~= nil), #(ow.pendingScripts or {}), tostring(ow.transitioning),
        tostring(p and p.inputLocked), tostring(p and p.moving), #(ow.scriptMoves or {})))
    end
    if getenv("SHOT_ON_STALL") then shot(G, ("stall%d"):format(tick)) end
  end
  if drawEvery > 0 and tick % drawEvery == 0 then
    local w, h = love.graphics.getDimensions()
    _G.__sweepCanvas = _G.__sweepCanvas or love.graphics.newCanvas(w, h)
    love.graphics.push("all")
    love.graphics.setCanvas({ _G.__sweepCanvas, depth = true })
    local ok, err = pcall(G.draw, G)
    love.graphics.setCanvas()
    love.graphics.pop()
    if not ok then print(("[sweep] draw raised on tick %d: %s"):format(tick, tostring(err))) end
  end
  -- SWEEP_TELEPORT="900:T22GYM0101,15,26,up;...": at that tick (or the first
  -- tick after it with the field on top) the player is put there
  _G.__sweepTp = _G.__sweepTp or {}
  for t, m, x, y, f in tostring(getenv("SWEEP_TELEPORT") or ""):gmatch("(%d+):([%w_]+),(%d+),(%d+),?(%a*)") do
    local key = t .. m
    if tick >= tonumber(t) and not _G.__sweepTp[key] and ow and top == ow and not ow.transitioning
       and not (ow.runner and ow.runner:isRunning()) then
      _G.__sweepTp[key] = true
      local ok, err = pcall(ow.setMap, ow, m, tonumber(x), tonumber(y), f ~= "" and f or "up")
      print(("[sweep] teleport t=%d to %s %s,%s: %s"):format(tick, m, x, y, ok and "ok" or tostring(err)))
      -- SWEEP_GOAL="MAP:x,y": once on that map, walk there (breadth-first
      -- over Collision.canMove, people included)
      for gm, gx, gy, gf in tostring(getenv("SWEEP_GOAL") or ""):gmatch("([%w_]+):(%d+),(%d+),?(%a*)") do
        if gm == m then _G.__sweepGoal = { map = gm, x = tonumber(gx), y = tonumber(gy), face = gf ~= "" and gf or nil } end
      end
    end
  end
  -- SWEEP_GOALS="T20R0202:3,4,left:40;T20R0201:..." : a walk in order; each
  -- goal starts when the player is on its map, and may end by holding a
  -- direction for n ticks (into stairs, a door)
  if not _G.__sweepGoals then
    _G.__sweepGoals = {}
    for gm, gx, gy, gf, gh, gn in tostring(getenv("SWEEP_GOALS") or ""):gmatch("([%w_]+):(%d+),(%d+),?(%a*):?(%a*):?(%d*)") do
      _G.__sweepGoals[#_G.__sweepGoals + 1] = { map = gm, x = tonumber(gx), y = tonumber(gy),
        face = gf ~= "" and gf or nil, hold = gh ~= "" and gh or nil, holdN = tonumber(gn) or 30 }
    end
    _G.__sweepGi = 1
  end
  if not _G.__sweepGoal and not _G.__sweepHold and ow then
    local g = _G.__sweepGoals[_G.__sweepGi]
    if g and ow.map.id == g.map then
      _G.__sweepGoal = g
      g.deadline = tick + tonumber(getenv("SWEEP_GOAL_TICKS") or "1500")
      _G.__sweepGi = _G.__sweepGi + 1
      print(("[sweep] goal %d: %s %d,%d"):format(_G.__sweepGi - 1, g.map, g.x, g.y))
    end
  end
  local goal = _G.__sweepGoal
  if (goal or _G.__sweepGoals[1]) and ow and G.input and not G.input.__sweepWrapped then
    local inner = G.input.isDown
    G.input.isDown = function(selfI, k)
      local gl = _G.__sweepGoal
      local o = _G.__sweepOw
      if o and o.player and _G.__sweepDir then
        return k == _G.__sweepDir
      end
      return inner(selfI, k)
    end
    G.input.__sweepWrapped = true
  end
  _G.__sweepOw = ow
  _G.__sweepDir = nil
  local hold = _G.__sweepHold
  if hold then
    hold.n = hold.n - 1
    _G.__sweepDir = hold.dir
    if hold.n <= 0 then
      _G.__sweepHold = nil
      print(("[sweep] held %s; now %s"):format(hold.dir, pos))
    end
  elseif goal and goal.deadline and tick > goal.deadline then
    print(("[sweep] GAVE UP on goal %s %d,%d at t=%d, standing at %s"):format(goal.map, goal.x, goal.y, tick, pos))
    _G.__sweepGoal = nil
  elseif goal and ow and ow.map.id ~= goal.map then
    print(("[sweep] left %s for %s before reaching the goal"):format(goal.map, pos))
    _G.__sweepGoal = nil
  elseif goal and ow and ow.map.id == goal.map and top == ow and p and not p.moving then
    if p.cellX == goal.x and p.cellY == goal.y then
      if goal.face and p.facing ~= goal.face then
        _G.__sweepDir = goal.face
      else
        print(("[sweep] reached goal %s %d,%d at t=%d"):format(goal.map, goal.x, goal.y, tick))
        _G.__sweepGoal = nil
        if goal.hold then _G.__sweepHold = { dir = goal.hold, n = goal.holdN } end
      end
    else
      local Collision = require("src.world.Collision")
      local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
      local ents = ow.cast or ow.entities or ow.npcs or {}
      local prev, q, head = { [p.cellX * 4096 + p.cellY] = false }, { { p.cellX, p.cellY } }, 1
      local found
      while head <= #q and head < 20000 and not found do
        local c = q[head]; head = head + 1
        for dname, d in pairs(DIRS) do
          local nx, ny = c[1] + d[1], c[2] + d[2]
          local k = nx * 4096 + ny
          if prev[k] == nil then
            local mover = { cellX = c[1], cellY = c[2], elevation = p.elevation, facing = dname }
            local okM = Collision.canMove(ow.map, ents, mover, dname)
            if okM or (nx == goal.x and ny == goal.y) then
              prev[k] = { c[1], c[2], dname }
              if nx == goal.x and ny == goal.y then found = k break end
              if okM then q[#q + 1] = { nx, ny } end
            end
          end
        end
      end
      if found then
        local k, first = found, nil
        while prev[k] do
          first = prev[k][3]
          if prev[k][1] == p.cellX and prev[k][2] == p.cellY then break end
          k = prev[k][1] * 4096 + prev[k][2]
        end
        _G.__sweepDir = first
      end
    end
  elseif goal and ow and top == ow and p and p.moving then
    _G.__sweepDir = _G.__sweepLastDir
  end
  _G.__sweepLastDir = _G.__sweepDir or _G.__sweepLastDir
  for t in tostring(getenv("SWEEP_SHOTS") or ""):gmatch("%d+") do
    if tonumber(t) == tick then shot(G, ("%05d"):format(tick)) end
  end
  return (table.unpack or unpack)(r)
end

dofile("tools/gen4_overworld_harness/main.lua")

-- the summary, after the harness's own love.load has run every tick
local load = love.load
love.load = function(...)
  local r = { load(...) }
  local n, results = 0, {}
  for i, rec in pairs(_G.__sweep.battles) do n = n + 1; results[#results + 1] = ("%d=%s"):format(i, tostring(rec.result)) end
  table.sort(results)
  print(("[sweep] SUMMARY battles=%d stalls=%d results: %s"):format(n, _G.__sweep.stalls, table.concat(results, " ")))
  return (table.unpack or unpack)(r)
end
