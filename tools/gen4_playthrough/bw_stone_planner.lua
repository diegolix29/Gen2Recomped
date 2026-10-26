-- CHARGESTONE CAVE PLANNER (Black / White, zones 195..197): the floating
-- stones (src/world/Gen5ChargestoneStones.lua) are pushed and slide until
-- something stops them, and a stone beside a crystal stays put -- a little
-- Sokoban, searched over push states (the player's reachable region and the
-- stones) with the engine's own step test for the terrain and its heights.
-- plan(ow, goal) -> the presses that reach `goal` (a direction each: a step,
-- or a push of the stone ahead), or nil. The runner step kind
-- { "stonewalk", x, y } presses its way there, re-planning after every press.
local P = {}

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local ORDER = { "up", "down", "left", "right" }

function P.plan(ow, goal, maxStates)
  local Collision = require("src.world.Collision")
  local S = require("src.world.Gen5ChargestoneStones")
  local map, p = ow.map, ow.player
  local W, H = map.widthCells, map.heightCells
  local function id(x, y) return y * 4096 + x end
  -- the terrain's own answer per cell and direction (no people)
  local passC = {}
  local function pass(x, y, dir)
    local k = id(x, y) * 4 + (dir == "up" and 0 or dir == "down" and 1 or dir == "left" and 2 or 3)
    local v = passC[k]
    if v == nil then
      v = Collision.canMove(map, {}, { cellX = x, cellY = y, facing = dir, elevation = p.elevation }, dir) and true or false
      passC[k] = v
    end
    return v
  end
  local fixed, stones0 = {}, {}
  for _, e in ipairs(ow.npcs or {}) do
    if e.cellX and not Collision.entityAbsent(e) and not e.passable and not (e.def and e.def.passable) then
      if e.def and e.def.gen5Stone then stones0[#stones0 + 1] = id(e.cellX, e.cellY)
      else fixed[id(e.cellX, e.cellY)] = true end
    end
  end
  table.sort(stones0)
  local stuckC = {}
  local function stuck(c)
    if stuckC[c] == nil then stuckC[c] = S.stuck(map, c % 4096, math.floor(c / 4096)) end
    return stuckC[c]
  end
  local function reach(px, py, sset)
    local seen, q, h = { [id(px, py)] = false }, { id(px, py) }, 1
    while h <= #q do
      local c = q[h]; h = h + 1
      local x, y = c % 4096, math.floor(c / 4096)
      for _, dir in ipairs(ORDER) do
        local d = DIRS[dir]
        local n = id(x + d[1], y + d[2])
        if seen[n] == nil and not sset[n] and not fixed[n] and pass(x, y, dir) then
          seen[n] = { c, dir }; q[#q + 1] = n
        end
      end
    end
    return seen
  end
  local function walk(seen, t)
    local out = {}
    while seen[t] do out[#out + 1] = seen[t][2]; t = seen[t][1] end
    local r = {}
    for i = #out, 1, -1 do r[#r + 1] = out[i] end
    return r
  end
  local gid = id(goal[1], goal[2])
  local function keyOf(seen, stones)
    local m
    for c in pairs(seen) do if not m or c < m then m = c end end
    return m .. "|" .. table.concat(stones, ",")
  end
  local start = { id(p.cellX, p.cellY), stones0 }
  local sset0 = {}
  for _, c in ipairs(stones0) do sset0[c] = true end
  local seen0 = reach(p.cellX, p.cellY, sset0)
  local prev = { [keyOf(seen0, stones0)] = false }
  local q, h, found = { { start[1], stones0, seen0, keyOf(seen0, stones0) } }, 1, nil
  maxStates = maxStates or 20000
  while h <= #q and h <= maxStates do
    local s = q[h]; h = h + 1
    local seen = s[3]
    if seen[gid] ~= nil then found = s break end
    local sset = {}
    for _, c in ipairs(s[2]) do sset[c] = true end
    for si, c in ipairs(s[2]) do
      if not stuck(c) then
        local cx, cy = c % 4096, math.floor(c / 4096)
        for _, dir in ipairs(ORDER) do
          local d = DIRS[dir]
          local stand = id(cx - d[1], cy - d[2])
          if seen[stand] ~= nil then
            local x, y, n = cx, cy, 0
            while n < S.MAX_SLIDE do
              local nx = id(x + d[1], y + d[2])
              if not pass(x, y, dir) or (sset[nx] and nx ~= c) or fixed[nx] or nx == stand then break end
              x, y, n = x + d[1], y + d[2], n + 1
            end
            if n > 0 then
              local ns = {}
              for j, o in ipairs(s[2]) do ns[j] = (j == si) and id(x, y) or o end
              table.sort(ns)
              local nset = {}
              for _, o in ipairs(ns) do nset[o] = true end
              local sx, sy = stand % 4096, math.floor(stand / 4096)
              local nseen = reach(sx, sy, nset)
              local k = keyOf(nseen, ns)
              if prev[k] == nil then
                local moves = walk(seen, stand)
                moves[#moves + 1] = dir
                prev[k] = { s[4], moves }
                q[#q + 1] = { stand, ns, nseen, k }
              end
            end
          end
        end
      end
    end
  end
  if not found then return nil, h end
  local tail = walk(found[3], gid)
  local chunks, k = { tail }, found[4]
  while prev[k] do chunks[#chunks + 1] = prev[k][2]; k = prev[k][1] end
  local route = {}
  for i = #chunks, 1, -1 do for _, m in ipairs(chunks[i]) do route[#route + 1] = m end end
  return route, h
end

-- { "stonewalk", x, y }
function P.install(r)
  if r.stonewalkInstalled then return end
  r.stonewalkInstalled = true
  local orig = r.runStep
  r.runStep = function(self, s)
    if s[1] ~= "stonewalk" then return orig(self, s) end
    local ow = self.ow
    if self:busy() then
      self.held = nil
      local _, k = self:busyInput()
      self.key = k
      s.pressing = nil
      return false
    end
    local x, y = self:pos()
    if x == s[2] and y == s[3] then return true end
    s.tries = (s.tries or 0) + 1
    if s.tries > 6000 then return nil, ("stonewalk never reached %d,%d"):format(s[2], s[3]) end
    local here = ("%d,%d:%s"):format(x, y, tostring(ow.player.facing))
    if s.pressing and s.pressing.at == here then
      s.pressing.t = s.pressing.t + 1
      if s.pressing.t < 24 then self.held = s.pressing.dir return false end
    end
    local route, n = P.plan(ow, { s[2], s[3] })
    if not route or #route == 0 then return nil, ("stonewalk: no plan to %d,%d (%s states)"):format(s[2], s[3], tostring(n)) end
    if not s.said then
      s.said = true
      self:say("  stonewalk to %d,%d: %d presses (%s push states): %s", s[2], s[3], #route, tostring(n),
        table.concat((function() local t = {} for _, m in ipairs(route) do t[#t + 1] = m:sub(1, 1) end return t end)(), ""))
    end
    s.pressing = { at = here, dir = route[1], t = 0 }
    self.held = route[1]
    return false
  end
end

return P
