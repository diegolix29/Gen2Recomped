-- ICIRRUS GYM PLANNER (Black / White, zone 114): a breadth-first search over
-- (cell, switch groups, rail) with the engine's own step test
-- (Collision.canMove, so the gym's restored walls, heights and people), its
-- ice (OverworldState:isIceCell) and its rails (src/world/Gen5IcirrusGym.lua),
-- the way the field moves the player: a press steps once and the ice carries
-- on; a chute's trigger with its gate open leaves the player on the rail, and
-- the next press along it rides to the far end; a bridge's 0xA3 end takes a
-- press into the bridge across. Used by the Black playthrough's Brycen beat
-- and by scratch scenarios: plan(ow, save, goal) -> list of { dir, x, y } (the
-- cell each press should end on) or nil.
local P = {}

-- M0228's switch scripts (S02D7 / S0340 / S03A9): the floor switch of each
-- group, and where its two arm blockers (persons 3,4 / 6,7 / 9,10) stand at
-- state 0 and at 1 (setposition rows); the pivots (2, 5, 8) never move
P.SWITCH = { ["23,53"] = 0, ["59,41"] = 1, ["15,29"] = 2 }
P.ARM_LIDS = { [3] = true, [4] = true, [6] = true, [7] = true, [9] = true, [10] = true }
P.ARMS = {
  [0] = { [0] = { { 18, 55 }, { 17, 54 } }, [1] = { { 19, 54 }, { 18, 53 } } },
  [1] = { [0] = { { 55, 44 }, { 56, 43 } }, [1] = { { 55, 42 }, { 54, 43 } } },
  [2] = { [0] = { { 16, 33 }, { 17, 34 } }, [1] = { { 17, 32 }, { 18, 33 } } },
}
local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local ORDER = { "up", "down", "left", "right" }
local BACK = { up = "down", down = "up", left = "right", right = "left" }

local function stateOf(save)
  local v = save and save.gen4Vars or {}
  return { (v[0x4001] or 0) ~= 0 and 1 or 0, (v[0x4002] or 0) ~= 0 and 1 or 0, (v[0x4003] or 0) ~= 0 and 1 or 0 }
end
P.stateOf = stateOf

function P.plan(ow, save, goal, opts)
  opts = opts or {}
  local Collision = require("src.world.Collision")
  local G = require("src.world.Gen5IcirrusGym")
  local map, def = ow.map, ow.map.def
  -- (any other map: the ice alone -- Cold Storage)
  local gym = def.gen5 and def.header == G.HEADER
  local ents = {}
  for _, e in ipairs(ow.cast or ow.entities or {}) do
    local lid = e.localId or (e.def and e.def.localId)
    if e ~= ow.player and not (gym and e.def and e.def.gen5Gimmick and P.ARM_LIDS[lid]) then ents[#ents + 1] = e end
  end
  local p = ow.player
  local function armAt(x, y, st)
    if not gym then return false end
    for g = 0, 2 do
      for _, a in ipairs(P.ARMS[g][st[g + 1]]) do if a[1] == x and a[2] == y then return true end end
    end
  end
  local function can(x, y, dir, st)
    local d = D[dir]
    if armAt(x + d[1], y + d[2], st) then return false end
    local mover = { cellX = x, cellY = y, facing = dir, elevation = p.elevation, gen5Level = p.gen5Level }
    return Collision.canMove(map, ents, mover, dir) and true or false
  end
  local trig = {}
  if gym then for n, r in pairs(G.RIDES) do trig[r.x .. "," .. r.y] = n end end
  local function key(x, y, st, rail) return x .. "," .. y .. ":" .. st[1] .. st[2] .. st[3] .. ":" .. tostring(rail) end
  -- a press on the grid from (x, y): step, then the ice
  local function grid(x, y, st, dir)
    if not can(x, y, dir, st) then return nil end
    local d = D[dir]
    x, y = x + d[1], y + d[2]
    local guard = 0
    while guard < 128 do
      guard = guard + 1
      local k = x .. "," .. y
      if gym and P.SWITCH[k] then
        st = { st[1], st[2], st[3] }
        local g = P.SWITCH[k]
        st[g + 1] = 1 - st[g + 1]
      end
      local n = trig[k]
      if n then
        local gate = def.gen5RailGates and (def.gen5RailGates[n] or def.gen5RailGates[tostring(n)])
        if not gate or st[gate.group + 1] == gate.state then return x, y, st, "s" .. n end
      end
      if not ow:isIceCell(x, y) or not can(x, y, dir, st) then return x, y, st, nil end
      x, y = x + d[1], y + d[2]
    end
    return x, y, st, nil
  end
  local function moves(s)
    local x, y, st, rail = s[1], s[2], s[3], s[4]
    local out = {}
    for _, dir in ipairs(ORDER) do
      local done = false
      if rail then
        local kind, n = rail:sub(1, 1), tonumber(rail:sub(2))
        local r = G.RIDES[n]
        if kind == "s" and dir == r.go then out[#out + 1] = { dir, r.toX, r.toY, st, "e" .. n } done = true end
        if kind == "e" and dir == BACK[r.arrive] then out[#out + 1] = { dir, r.x, r.y, st, "s" .. n } done = true end
      else
        local e = gym and G.ENTRIES[x .. "," .. y]
        if e and e.go == dir then out[#out + 1] = { dir, e.toX, e.toY, st, nil } done = true end
      end
      if not done then
        local nx, ny, nst, nrail = grid(x, y, st, dir)
        if nx then out[#out + 1] = { dir, nx, ny, nst, nrail } end
      end
    end
    return out
  end
  local rail0
  local gr = ow.gen5Rail
  if gym and gr and gr.x == p.cellX and gr.y == p.cellY then
    for n, r in pairs(G.RIDES) do
      if r.x == gr.x and r.y == gr.y and gr.go == r.go then rail0 = "s" .. n end
      if r.toX == gr.x and r.toY == gr.y and gr.go == BACK[r.arrive] then rail0 = "e" .. n end
    end
  end
  local start = { p.cellX, p.cellY, stateOf(save), rail0 }
  local prev = { [key(start[1], start[2], start[3], start[4])] = false }
  local q, head, found = { start }, 1, nil
  while head <= #q and head < 100000 do
    local s = q[head]; head = head + 1
    if s[1] == goal[1] and s[2] == goal[2] then found = s break end
    for _, m in ipairs(moves(s)) do
      local k = key(m[2], m[3], m[4], m[5])
      if prev[k] == nil then
        prev[k] = { s, m[1] }
        q[#q + 1] = { m[2], m[3], m[4], m[5] }
      end
    end
  end
  if not found then return nil, head end
  local route, s = {}, found
  while true do
    local pr = prev[key(s[1], s[2], s[3], s[4])]
    if not pr then break end
    table.insert(route, 1, { pr[2], s[1], s[2], rail = s[4] })
    s = pr[1]
  end
  return route, head
end

-- a runner step kind: { "icewalk", x, y } presses its way to (x, y) on the
-- plan, re-planned after every move (a trainer's battle may stop a slide)
function P.install(r)
  if r.icewalkInstalled then return end
  r.icewalkInstalled = true
  local orig = r.runStep
  r.runStep = function(self, s)
    if s[1] ~= "icewalk" then return orig(self, s) end
    local ow = self.ow
    local busy = self:busy() or ow.iceSlide ~= nil
    if busy then
      self.held = nil
      local h, k = self:busyInput()
      self.key = k
      s.pressing = nil
      return false
    end
    local x, y = self:pos()
    if x == s[2] and y == s[3] then return true end
    s.tries = (s.tries or 0) + 1
    if s.tries > 4000 then return nil, ("icewalk never reached %d,%d"):format(s[2], s[3]) end
    local here = ("%d,%d:%s:%s"):format(x, y, tostring(ow.player.facing), tostring(ow.gen5Rail and ow.gen5Rail.go))
    if s.pressing and s.pressing.at == here then
      -- the press has not taken yet (a turn on the spot first): keep it
      s.pressing.t = s.pressing.t + 1
      if s.pressing.t < 24 then self.held = s.pressing.dir return false end
    end
    -- `each = fn(r)`: run before every move (the playthrough heals there)
    if s.each then s.each(self) end
    local route, n = P.plan(ow, self.game.save, { s[2], s[3] })
    if not route or #route == 0 then return nil, ("icewalk: no plan to %d,%d (%s states)"):format(s[2], s[3], tostring(n)) end
    local m = route[1]
    if not s.said then
      s.said = true
      local t = {}
      for _, e in ipairs(route) do t[#t + 1] = ("%s>%d,%d"):format(e[1]:sub(1, 1), e[2], e[3]) end
      self:say("  icewalk to %d,%d: %s", s[2], s[3], table.concat(t, " "))
    end
    s.pressing = { at = here, dir = m[1], t = 0 }
    self.held = m[1]
    return false
  end
end

return P
