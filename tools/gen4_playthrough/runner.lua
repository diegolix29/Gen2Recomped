-- tools/gen4_playthrough/runner.lua
--
-- THE AUTOMATED PLAYTHROUGH: a game's story as a list of BEATS, played with
-- the real input on the real state stack (tools/gen4_overworld_harness ticks
-- it; PLAYTHROUGH=<game> hands each tick's input to this runner).
--
-- A beat is { name, steps = { ... }, expect = function(r) ... end }. Each step
-- is one of
--
--   { "walkto", x, y }          walk to a cell (breadth-first over the engine's
--                               own Collision.canMove, re-planned every step)
--   { "warpto", "MAP" }         walk onto the warp in this map that leads there
--   { "coord", n }              walk onto the map's coordinate trigger n (1-based)
--   { "talk", localId }         walk next to that person, face them, press A
--   { "talkany", { ids } }      the same for the first of them who is shown
--   { "sign", n }               walk in front of sign n, face it, press A
--   { "step", "dir", n }        hold a direction until n cells are walked
--   { "face", "dir" }           turn without walking
--   { "press", "key" }          one press
--   { "mash", ticks }           press A every few ticks for that long
--   { "until", fn, ticks }      press A until fn(r) is true (or fail)
--   { "teleport", "MAP", x, y, facing }   travel between beats
--   { "do", fn }                run fn(r) once (a cheat, a log line)
--   { "answers", { n, ... } }   the next menus are answered with these rows
--
-- While the game is BUSY -- a script running, a text box, a menu, a battle --
-- the runner presses A on a rhythm (START on a naming screen, B for "give it
-- a nickname?"), which is how a player gets through dialogue. After the steps
-- the beat's `expect` must come true (A still pressed) within its budget;
-- the cartridge's own story vars and flags are what it reads. The first beat
-- that fails stops the run with where it stood and what was on screen.

local R = {}
R.__index = R

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

function R.new(game, beats, opts)
  opts = opts or {}
  return setmetatable({ game = game, beats = beats, opts = opts, beat = 0, stepAt = 1,
    t = 0, beatT = 0, log = {}, done = false, failed = nil,
    startAt = opts.startAt, mashEvery = opts.mashEvery or 8 }, R)
end

-- ------------------------------------------------------------ state reads --
function R:var(id) return tonumber(((self.game.save or {}).gen4Vars or {})[id]) or 0 end
function R:flag(id) return ((self.game.save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true end
function R:map() local ow = self.ow return ow and ow.map and ow.map.id end
function R:pos() local p = self.ow and self.ow.player return p and p.cellX, p and p.cellY end
function R:party() return (self.game.save or {}).party or {} end
-- "(x,y) facing f shown|hidden" for a person on the map, for log lines
function R:personAt(localId)
  for _, n in ipairs((self.ow and self.ow.npcs) or {}) do
    local lid = n.localId or (n.def and n.def.localId)
    if lid == localId then
      return ("(%s,%s) facing %s %s"):format(tostring(n.cellX), tostring(n.cellY), tostring(n.facing), n.hidden and "hidden" or "shown")
    end
  end
  return "absent"
end
function R:top()
  local st = self.game.stack and self.game.stack.states
  return st and st[#st]
end
function R:busy()
  local ow = self.ow
  if not ow then return true, "no field" end
  if self:top() ~= ow then return true, "top" end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return true, "script" end
  if #(ow.scriptMoves or {}) > 0 then return true, "moves" end
  if ow.player and ow.player.moving then return true, "moving" end
  -- a trainer's "!" and walk-up freeze the player (HGSS's emote now runs the
  -- cartridge's 74 ticks): standing still then is not being blocked
  if ow.emote or ow.engaging or (ow.extraEmotes and #ow.extraEmotes > 0) then return true, "engage" end
  return false
end
local function stateName(st)
  if not st then return "nil" end
  if st.battle or st.phase then return "battle(" .. tostring(st.phase) .. ")" end
  local mt = getmetatable(st)
  for name, mod in pairs(package.loaded) do
    if type(mod) == "table" and (mod == st or mod == mt or (mt and mod == mt.__index)) and name:match("^src%.") then
      return name:gsub("^src%.%w+%.", "")
    end
  end
  return tostring(st.name or st.kind or "?")
end
function R:screenText()
  local top = self:top()
  if not top then return "" end
  local t = top.text or top.message or (top.pages and top.pages[top.page or 1]) or top.current
  if type(t) == "table" then t = t[1] end
  return tostring(t or ""):gsub("\n", " "):sub(1, 90)
end

function R:say(fmt, ...)
  local line = ("[pt %6d] " .. fmt):format(self.t, ...)
  print(line)
  self.log[#self.log + 1] = line
end

-- --------------------------------------------------------------- the beat --
function R:currentBeat() return self.beats[self.beat] end

function R:nextBeat()
  self.beat = self.beat + 1
  self.stepAt, self.beatT, self.stepT, self.stuck = 1, 0, 0, 0
  self.expectT = nil
  local b = self.beats[self.beat]
  if not b then
    self.done = true
    self:say("ALL %d BEATS PASSED", #self.beats)
    return
  end
  -- START_AT=<name>: skip ahead (the beat's own `setup` puts the story there)
  if self.startAt and b.name ~= self.startAt and not self.started then
    return self:nextBeat()
  end
  if self.startAt and b.name == self.startAt and b.setup then b.setup(self) end
  self.started = true
  self:say("BEAT %d %s", self.beat, b.name)
end

function R:fail(why)
  local x, y = self:pos()
  self.failed = why
  self.done = true
  local b = self:currentBeat()
  self:say("FAIL beat %d %s: %s", self.beat, b and b.name or "?", why)
  self:say("  at %s (%s,%s) top=%s text=%q", tostring(self:map()), tostring(x), tostring(y),
    stateName(self:top()), self:screenText())
  for _, n in ipairs((self.ow and self.ow.npcs) or {}) do
    if not n.hidden and x and math.abs((n.cellX or -99) - x) <= 2 and math.abs((n.cellY or -99) - y) <= 2 then
      self:say("  near: person %s at (%s,%s)%s moving=%s", tostring(n.localId or (n.def and n.def.localId)),
        tostring(n.cellX), tostring(n.cellY), n.passable and " passable" or "", tostring(n.moving))
    end
  end
end

-- { "answers", {...} } queued: the next menus get their cursor put on these
-- rows, one each, and A pressed (a quiz, a choice that matters). Asked every
-- tick, whatever step is running -- `until` presses A on its own rhythm.
function R:answerMenu()
  if not (self.answers and #self.answers > 0) then return nil end
  local top = self:top()
  if stateName(top) ~= "Menu" or top == self.answeredMenu
     or type(top.items) ~= "table" or not top.index then return nil end
  top.index = math.max(1, math.min(#top.items, table.remove(self.answers, 1)))
  self.answeredMenu = top
  local labels = {}
  for i, it in ipairs(top.items) do labels[i] = tostring(it.label) end
  self:say("  answered row %d of [%s]", top.index, table.concat(labels, " | "))
  return "a"
end

-- A FORCED SWITCH (the lead fainted): the party menu opens on the fainted
-- one, and A on it is "There's no will to fight!" and the menu again --
-- forever. A player moves the cursor; so does this. Answers whether the
-- cursor is on a fainted one, and the key to press this tick.
function R:forcedSwitchKey()
  local top = self:top()
  if type(top) == "table" and top.forceSwitch and type(top.index) == "number" and top.party then
    local okP, party = pcall(top.party, top)
    local mon = okP and type(party) == "table" and party[top.index]
    if mon and (tonumber(mon.hp) or 0) > 0 then return false end
    -- on a fainted one or on CANCEL (the menu is a two-column grid, so with
    -- two members "down" from the first is CANCEL): try each way in turn
    local dirs = { "right", "down", "left", "up" }
    return true, (self.t % 12 == 0) and dirs[math.floor(self.t / 12) % 4 + 1] or nil
  end
  return false
end

-- the A rhythm while the game talks
function R:busyInput()
  local top = self:top()
  local name = stateName(top)
  local onFainted, key = self:forcedSwitchKey()
  if onFainted then return nil, key end
  if name:find("NamingScreen") then
    -- START puts the cursor on OK (ns.c 2568) and A presses it
    local k = self.t % 24
    return nil, (k == 0 and "start") or (k == 12 and "a") or nil
  end
  -- the Pokegear a scripted phone call leaves open (HGSS RunPhoneCall): B closes it
  if name:find("HgssPokegear") then
    return nil, ((self.t % self.mashEvery) == 0) and "b" or nil
  end
  if (self.t % self.mashEvery) == 0 then return nil, "a" end
  return nil, nil
end

-- --------------------------------------------------------------- the steps --
local function adjacentFree(r, tx, ty)
  local best, bestD
  local px, py = r:pos()
  local map = r.ow and r.ow.map
  for dname, d in pairs(DIRS) do
    local cx, cy = tx - d[1], ty - d[2]     -- stand here, face dname
    local dist = math.abs(cx - (px or 0)) + math.abs(cy - (py or 0))
    -- a wall beside the target is no place to stand (the Ilex Farfetch'd's
    -- west side): ranked after every open side
    local open = not (map and map.isWalkableCell) or map:isWalkableCell(cx, cy)
    -- ...nor a cell someone is standing on (Amphy beside Jasmine)
    for _, n in ipairs((r.ow and r.ow.npcs) or {}) do
      if not n.hidden and n.cellX == cx and n.cellY == cy then open = false end
    end
    -- ...nor under an invisible blocker (Lenora's bookcase covers the floor
    -- beside its last book until the book moves it)
    local okC, Collision = pcall(require, "src.world.Collision")
    if open and okC and Collision.occupied and r.ow and r.ow.entities
       and Collision.occupied(r.ow.entities, cx, cy, r.ow.player) then open = false end
    if not open then dist = dist + 10000 end
    -- ...and one that can be walked to before one that cannot (Cold
    -- Storage's grunt with an open cell boxed in behind the crowd)
    if open and r.planStep and dist > 0 and not r.planStep(r.ow, cx, cy) then dist = dist + 5000 end
    if not bestD or dist < bestD then best, bestD = { cx, cy, dname }, dist end
  end
  return best
end

function R:walkTo(tx, ty)
  local x, y = self:pos()
  if x == tx and y == ty then return true end
  -- NOT MOVING: the planner keeps pointing into a cell the player cannot
  -- enter (a door, a warp at the map's edge) -- say so ("blocked")
  local cell = tostring(self:map()) .. ":" .. tostring(x) .. "," .. tostring(y)
  if cell == self.walkCell then self.walkSame = (self.walkSame or 0) + 1 else self.walkSame = 0 end
  self.walkCell = cell
  if self.walkSame > 45 then
    self.walkSame = 0
    return "blocked"
  end
  local d = self.planStep(self.ow, tx, ty, self.avoid)
  -- the other warps are only avoided where a way round them exists
  -- ...but not at the first tick there is none: a wandering person can stand
  -- in the only way round for a moment (Castelia's gym street), and the way
  -- over a warp leads off the map
  if d then self.avoidWait = 0 elseif self.avoid then self.avoidWait = (self.avoidWait or 0) + 1 end
  if not d and self.avoid and self.avoidWait > 90 then d = self.planStep(self.ow, tx, ty) end
  if os.getenv("PT_WALKLOG") and self.t % 4 == 0 then
    self:say("  walk %s (%s,%s) -> (%d,%d) %s", tostring(self:map()), tostring(x), tostring(y), tx, ty, tostring(d))
  end
  if d == "here" then return true end
  if not d then
    -- and stand still: a direction left held from the step before (leaning
    -- into the door just come through) walked the player off somewhere else
    self.held = nil
    self.stuck = (self.stuck or 0) + 1
    if self.stuck > 240 then return nil, ("no path to %d,%d"):format(tx, ty) end
    return false
  end
  self.held = d
  return false
end

function R:runStep(s)
  local kind = s[1]
  if kind ~= "warpto" then self.avoid = nil end
  if kind == "do" then s[2](self) return true end
  if kind == "answers" then
    self.answers = {}
    for i, v in ipairs(s[2] or {}) do self.answers[i] = v end
    return true
  end
  if kind == "teleport" then
    local ok, err = pcall(self.ow.setMap, self.ow, s[2], s[3], s[4], s[5] or "down")
    if not ok then return nil, "teleport failed: " .. tostring(err) end
    return true
  end
  if kind == "press" then self.key = s[2] return true end
  if kind == "mash" then
    if self.stepT >= s[2] then return true end
    if self.stepT % self.mashEvery == 0 then
      self.key = stateName(self:top()):find("HgssPokegear") and "b" or "a"
    end
    return false
  end
  if kind == "until" then
    if s[2](self) then return true end
    if self.stepT > (s[3] or 12000) then return nil, "condition never came true" end
    local onFainted, key = self:forcedSwitchKey()
    if onFainted then self.key = key return false end
    -- (the Pokegear a scripted HGSS phone call leaves open closes on B)
    local gear = stateName(self:top()):find("HgssPokegear")
    if self.stepT % self.mashEvery == 0 then self.key = gear and "b" or s[4] or "a" end
    return false
  end
  if kind == "face" then
    if self.stepT == 1 then self.held = s[2] return false end
    return true
  end
  if kind == "step" then
    self.stepMoved = self.stepMoved or 0
    local x, y = self:pos()
    local cell = tostring(self:map()) .. x .. "," .. y
    if self.stepCell and cell ~= self.stepCell then self.stepMoved = self.stepMoved + 1 end
    self.stepCell = cell
    if self.stepMoved >= s[3] then self.stepMoved, self.stepCell = nil, nil return true end
    if self.stepT > 120 * s[3] then return nil, "could not walk " .. s[2] end
    self.held = s[2]
    return false
  end
  local def = self.ow.map and self.ow.map.def or {}
  if kind == "walkto" then
    local ok, why = self:walkTo(s[2], s[3])
    if ok == "blocked" then
      self.blockedN = (self.blockedN or 0) + 1
      if self.blockedN > 12 then self.blockedN = 0 return nil, ("blocked short of %d,%d"):format(s[2], s[3]) end
      return false
    end
    if ok then self.blockedN = 0 end
    return ok, why
  end
  if kind == "warpto" then
    if self:map() == s[2] then self.onWarpT, self.leaning = 0, nil return true end
    -- `done = fn`: the warp's own scene has already carried the player on
    -- (Striaton's frame table warps straight on to Fennel's house)
    if s.done and s.done(self) then self.onWarpT, self.leaning = 0, nil return true end
    -- every OTHER warp is a wall on the way: a cabin corridor's doors sit
    -- beside the one wanted, and walking over one goes somewhere else
    self.avoid = {}
    -- { "warpto", map, x, y }: that one warp, when two lead to the same map
    -- by different ways (the S.S. Aqua's two stairs between 1F and B1F)
    local function wanted(w)
      return w.destMap == s[2] and (s[3] == nil or (w.x == s[3] and w.y == s[4]))
    end
    for _, w in ipairs(def.warps or {}) do
      if not wanted(w) then self.avoid[w.x * 4096 + w.y] = true end
    end
    -- ...and so is an armed trigger, where a way round it exists (Relic
    -- Castle's quicksand pits lie between the way in and the stairs)
    if s.avoidTriggers then
      for _, c in ipairs(def.coordEvents or {}) do
        if c.var and self:var(c.var) == (c.value or 0) then
          for yy = c.y, c.y + (c.height or 1) - 1 do
            for xx = c.x, c.x + (c.width or 1) - 1 do self.avoid[xx * 4096 + yy] = true end
          end
        end
      end
    end
    -- of several cells leading there, one the planner can reach without
    -- crossing another warp (Celestial Tower 2F: the stairs up are (13,8),
    -- (13,9) and (14,10), and only (14,10) has floor in front of it)
    local reach
    for _, w in ipairs(def.warps or {}) do
      if not reach and wanted(w) then
        local px, py = self:pos()
        if (px == w.x and py == w.y) or self.planStep(self.ow, w.x, w.y, self.avoid) then reach = w end
      end
    end
    for _, w in ipairs(def.warps or {}) do
      if wanted(w) and (not reach or w == reach) then
        -- NEXT TO IT: push into it rather than re-plan (a door or an edge
        -- warp cannot be entered the way the planner would like)
        local px, py = self:pos()
        local dx, dy = w.x - (px or 0), w.y - (py or 0)
        if math.abs(dx) + math.abs(dy) == 1 then
          self.held = dx == 1 and "right" or dx == -1 and "left" or dy == 1 and "down" or "up"
          self.lastDir = self.held
          self.pushT = (self.pushT or 0) + 1
          if self.pushT < 90 then return false end
          self.pushT = 0
          self.leaning = true
        end
        local ok, why = self:walkTo(w.x, w.y)
        if ok == nil then return nil, why end
        if ok == "blocked" then self.leaning = true end
        if ok == true or self.leaning then
          -- on the warp (or against a door): stairs and doors fire on a
          -- particular direction, so lean each way in turn until it does
          self.onWarpT = (self.onWarpT or 0) + 1
          local order = { self.lastDir or "up", "up", "right", "left", "down" }
          self.held = order[math.floor(self.onWarpT / 20) % #order + 1]
          if self.onWarpT > 400 then return nil, "the warp to " .. s[2] .. " never fired" end
        else
          self.onWarpT = 0
        end
        return false
      end
    end
    return nil, "no warp to " .. tostring(s[2]) .. " from " .. tostring(self:map())
  end
  if kind == "activecoord" then
    -- the first coordinate trigger whose own condition (var == value) holds
    -- now: the story's next scene on this map
    if self.acTarget == nil then
      for _, c in ipairs(def.coordEvents or {}) do
        if c.var and self:var(c.var) == (c.value or 0) then
          self.acTarget = { c.x + math.floor(((c.width or 1) - 1) / 2), c.y, c.var, c.value }
          break
        end
      end
      if not self.acTarget then return nil, "no armed coordinate trigger on " .. tostring(self:map()) end
    end
    -- the scene ran once the var moved off its value (or a script started)
    if self:var(self.acTarget[3]) ~= self.acTarget[4] then self.acTarget = nil return true end
    local ok, why = self:walkTo(self.acTarget[1], self.acTarget[2])
    if ok == nil then self.acTarget = nil return nil, why end
    if ok == true then self.acTarget = nil return true end
    return false
  end
  if kind == "walkedge" then
    self.edgeFrom = self.edgeFrom or self:map()
    if self:map() ~= self.edgeFrom then self.edgeFrom = nil return true end
    if self.stepT > 3000 then return nil, "never left " .. tostring(self.edgeFrom) .. " going " .. s[2] end
    self.held = s[2]
    return false
  end
  -- { "talkany", { id, id, ... } }: talk to the first of these people who is
  -- on the map and shown (a chase: the Ilex Farfetch'd stands at one of two)
  if kind == "talkany" then
    local function shown(want)
      for _, n in ipairs(self.ow.npcs or {}) do
        local lid = n.localId or (n.def and n.def.localId)
        if lid == want and not n.hidden then return true end
      end
      return false
    end
    -- the person chosen when the step began, while they stay on the map
    if s.chosen and not shown(s.chosen[2]) then s.chosen = nil return true end
    if not s.chosen then
      for _, want in ipairs(s[2] or {}) do
        if shown(want) then
          s.chosen = { "talk", want, behind = s.behind, retarget = s.retarget }
          for _, n in ipairs(self.ow.npcs or {}) do
            local lid = n.localId or (n.def and n.def.localId)
            if lid == want then self:say("  talkany -> %s at (%s,%s) facing %s", tostring(want), tostring(n.cellX), tostring(n.cellY), tostring(n.facing)) end
          end
          break
        end
      end
      -- nobody shown: wait a little (the second Farfetch'd appears once the
      -- first is home), then call the chase over
      if not s.chosen then
        s.waited = (s.waited or 0) + 1
        return s.waited > 600
      end
      s.waited = nil
    end
    local ok, why = self:runStep(s.chosen)
    if ok then s.chosen = nil end
    return ok, why
  end
  if kind == "talkto" then
    for _, n in ipairs(self.ow.npcs or {}) do
      local d = n.def or {}
      if (d.spriteName == s[2] or d.sprite == s[2]) and not n.hidden then
        s[1], s[2] = "talk", d.localId or n.localId
        return self:runStep(s)
      end
    end
    return nil, "nobody wearing " .. tostring(s[2]) .. " on " .. tostring(self:map())
  end
  if kind == "coord" then
    -- a trigger whose scene takes the player off the map (Relic Castle's
    -- quicksand drops them a floor) has done its work once the map changed
    if self.stepT == 1 then self.coordFrom, self.coordCell = self:map(), nil end
    if self.coordFrom and self:map() ~= self.coordFrom then return true end
    local c = (def.coordEvents or {})[s[2]]
    if not c then return nil, "no coordinate trigger " .. tostring(s[2]) end
    -- ...or once its own condition no longer holds: its scene has run (it
    -- fired on the way in, from a cell of its strip the runner was not
    -- making for). Temp-var triggers (switches, pits) are left to the cell.
    if self.stepT == 1 then self.coordArmed = c.var and self:var(c.var) == (c.value or 0) end
    if self.coordArmed and c.var and c.var >= 0x4020 and self:var(c.var) ~= (c.value or 0) then return true end
    -- a trigger wider than one cell: its nearest open cell (Castelia Gate's
    -- 7 x 1 strip starts in the wall at (1,9))
    local tx, ty = c.x, c.y
    if (c.width or 1) > 1 or (c.height or 1) > 1 then
      local px, py = self:pos()
      local map, bestD = self.ow and self.ow.map, nil
      for yy = c.y, c.y + (c.height or 1) - 1 do
        for xx = c.x, c.x + (c.width or 1) - 1 do
          local open = not (map and map.isWalkableCell) or map:isWalkableCell(xx, yy)
          -- ...and nobody standing on it (Dragonspiral's grunts line up
          -- across Z212's 1 x 5 trigger)
          for _, n in ipairs((self.ow and self.ow.npcs) or {}) do
            if not n.hidden and n.cellX == xx and n.cellY == yy then open = false end
          end
          local d = math.abs(xx - (px or 0)) + math.abs(yy - (py or 0))
          -- ...that can be walked to (a pit's far side lies past its own
          -- quicksand), asked once a step and then kept
          if open and self.coordCell == nil and self.planStep and d > 0
             and not self.planStep(self.ow, xx, yy) then open = false end
          if open and (not bestD or d < bestD) then tx, ty, bestD = xx, yy, d end
        end
      end
      if self.stepT == 1 or self.coordCell == nil then self.coordCell = { tx, ty } end
      tx, ty = self.coordCell[1], self.coordCell[2]
    end
    local ok, why = self:walkTo(tx, ty)
    if ok == nil then return nil, why end
    -- "blocked" is a string, not arrival: keep pushing, as walkto does (a
    -- trigger behind somebody who steps aside), then give up with a reason
    if ok == "blocked" then
      self.blockedN = (self.blockedN or 0) + 1
      if self.blockedN > 12 then self.blockedN = 0 return nil, ("blocked short of %d,%d"):format(c.x, c.y) end
      return false
    end
    if ok then self.blockedN = 0 end
    return ok
  end
  if kind == "talk" or kind == "sign" then
    local tx, ty, facing
    if kind == "talk" then
      for _, n in ipairs(self.ow.npcs or {}) do
        local lid = n.localId or (n.def and n.def.localId)
        if lid == s[2] and not n.hidden then tx, ty, facing = n.cellX, n.cellY, n.facing end
      end
      if not tx then return nil, "no person " .. tostring(s[2]) .. " on " .. tostring(self:map()) end
    else
      local sg = (def.signs or def.bgEvents or {})[s[2]]
      if not sg then return nil, "no sign " .. tostring(s[2]) end
      tx, ty = sg.x, sg.y
    end
    -- `behind = true`: come up from the side the person has its back to (a
    -- Farfetch'd notices whoever walks up in front of it)
    if not self.talkSpot and s.behind and facing and DIRS[facing] then
      local d = DIRS[facing]
      local bx, by = tx - d[1], ty - d[2]
      local map = self.ow and self.ow.map
      if not (map and map.isWalkableCell) or map:isWalkableCell(bx, by) then
        self.talkSpot = { bx, by, facing }
      end
    end
    self.talkSpot = self.talkSpot or adjacentFree(self, tx, ty)
    local spot = self.talkSpot
    if self.talkPhase == nil then
      local ok, why = self:walkTo(spot[1], spot[2])
      if ok == "blocked" then ok, why = nil, "blocked" end
      if ok == nil then
        -- that side is blocked: try the next one round
        self.talkTries = (self.talkTries or 0) + 1
        -- `retarget = true`: the people round this one keep moving (Cold
        -- Storage's grunts after their battles), so ask again where to stand
        -- rather than walk the four sides once
        if s.retarget and self.talkTries <= 40 then
          self.talkSpot, self.stuck = nil, 0
          return false
        end
        if self.talkTries > 3 then return nil, why end
        local order = { "up", "down", "left", "right" }
        local d = DIRS[order[self.talkTries + 1]]
        self.talkSpot = { tx - d[1], ty - d[2], order[self.talkTries + 1] }
        self.stuck = 0
        return false
      end
      if not ok then return false end
      self.talkPhase = 1
      self.held = spot[3]
      return false
    end
    if self.talkPhase == 1 then self.talkPhase = 2 return false end
    self.key = "a"
    self.talkSpot, self.talkPhase, self.talkTries = nil, nil, nil
    return true
  end
  return nil, "unknown step " .. tostring(kind)
end

-- ------------------------------------------------------------- snapshots --
-- after each passed beat the save and where the player stands are written
-- to <snapshotDir>/<game>_<n>.lua; RESUME=<n> starts from that one
function R:snapshotPath(n)
  local dir = self.opts.snapshotDir
  return dir and ("%s/%s_%02d.lua"):format(dir, self.opts.game or "game", n)
end
function R:snapshot()
  local path = self:snapshotPath(self.beat)
  if not path then return end
  local okE, body = pcall(require("src.core.SaveData").encode, self.game.save)
  if not okE then self:say("  (snapshot failed: %s)", tostring(body)) return end
  local x, y = self:pos()
  local p = self.ow and self.ow.player
  local f = io.open(path, "wb")
  if not f then return end
  f:write(("return { map = %q, x = %d, y = %d, facing = %q, save = %q }"):format(
    tostring(self:map()), x or 0, y or 0, tostring(p and p.facing or "down"), body))
  f:close()
end
function R:resume(n)
  local path = self:snapshotPath(n)
  local okL, snap = pcall(dofile, path)
  if not (okL and type(snap) == "table") then self:fail("no snapshot " .. tostring(path)) return end
  local okD, save = pcall(require("src.core.SaveData").decode, snap.save)
  if not (okD and type(save) == "table") then self:fail("snapshot did not decode") return end
  local live = self.game.save
  for k in pairs(live) do live[k] = nil end
  for k, v in pairs(save) do live[k] = v end
  local okM, err = pcall(self.ow.setMap, self.ow, snap.map, snap.x, snap.y, snap.facing)
  if not okM then self:fail("resume setMap: " .. tostring(err)) return end
  self.beat = n
  self:say("RESUMED after beat %d at %s (%d,%d)", n, snap.map, snap.x, snap.y)
  self:nextBeat()
end

-- --------------------------------------------------------------- one tick --
-- returns held direction, key pressed this tick
function R:tick(i, game, ow, planStep)
  self.game, self.ow, self.planStep = game, ow, planStep
  self.t = i
  self.held, self.key = nil, nil
  if self.done then return nil, nil end
  if self.beat == 0 then
    if self.opts.resume then self:resume(self.opts.resume) else self:nextBeat() end
    if self.done then return nil, nil end
  end
  local b = self:currentBeat()
  self.beatT = self.beatT + 1
  if os.getenv("PT_DEBUG") and i % 500 == 0 then
    local x, y = self:pos()
    local busy, why = self:busy()
    self:say("  .. step %d %s at %s (%s,%s) busy=%s %s top=%s", self.stepAt,
      tostring((b.steps and b.steps[self.stepAt] or {})[1]), tostring(self:map()), tostring(x), tostring(y),
      tostring(busy), tostring(why), stateName(self:top()))
  end
  if self.beatT > (b.budget or 30000) then self:fail("beat ran out of time") return nil, nil end
  local answer = self:answerMenu()
  if answer then return nil, answer end
  local s = b.steps and b.steps[self.stepAt]
  if s then
    local walking = s[1] == "walkto" or s[1] == "warpto" or s[1] == "coord" or s[1] == "talk"
      or s[1] == "sign" or s[1] == "step" or s[1] == "activecoord" or s[1] == "walkedge" or s[1] == "talkto"
      or s[1] == "talkany"
    if self:busy() and (walking or s[1] == "face") then
      return self:busyInput()
    end
    self.stepT = (self.stepT or 0) + 1
    local ok, why = self:runStep(s)
    if self.held then self.lastDir = self.held end
    -- PT_TRACE=1: every tick's step, place and input (a beat that wanders)
    if os.getenv("PT_TRACE") then
      local x, y = self:pos()
      self:say("  . step %d %s at %s (%s,%s) held=%s key=%s ok=%s", self.stepAt, tostring(s[1]),
        tostring(self:map()), tostring(x), tostring(y), tostring(self.held), tostring(self.key), tostring(ok))
    end
    if ok == nil then self:fail(("step %d (%s): %s"):format(self.stepAt, s[1], why)) return nil, nil end
    if ok then self.stepAt, self.stepT, self.stuck = self.stepAt + 1, 0, 0 end
    return self.held, self.key
  end
  -- the steps are done: the story must say so
  self.expectT = (self.expectT or 0) + 1
  if b.expect == nil or b.expect(self) then
    if not self:busy() or b.passBusy then
      local x, y = self:pos()
      self:say("PASS %s (%d ticks) at %s (%s,%s)", b.name, self.beatT, tostring(self:map()), tostring(x), tostring(y))
      self:snapshot()
      self:nextBeat()
      return nil, nil
    end
  end
  if self.expectT > (b.expectBudget or 2400) then self:fail("expected story state never came: " .. (b.why or "?")) return nil, nil end
  return self:busyInput()
end

return R
