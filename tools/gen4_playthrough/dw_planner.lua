-- tools/gen4_playthrough/dw_planner.lua
--
-- THE DISTORTION WORLD'S PLANNER, for the playthrough runner's `dwwalk` step.
--
-- The runner's own planner (the harness's planStep) is a breadth-first search
-- over Collision.canMove, one map cell to the next.  A Distortion World floor
-- is more than that, and the cartridge's way across it is three other moves
-- (src/world/Gen4DistSurface.lua and OverworldController:checkLedgeHop):
--
--   * the DOUBLE JUMPS, behaviours 0x5A..0x5D (JUMP_*_TWICE): pressing into
--     one hops the player three tiles -- the stepping stones between islands;
--   * the JUMP POINTS (FindFloatingPlatformJumpPointAt): pressing a record's
--     direction inside its bounds jumps onto a wall or ceiling platform, or
--     off one back to the floor;
--   * the FLOATING PLATFORMS themselves: a key is a step along the plane
--     (sDistortionStepDirection*), answered by the platform's 32x32 grid.
--
-- So the search here is over both kinds of place -- a map cell, or a tile on
-- a platform -- with those moves as its edges, asked the same questions in
-- the same order as Gen4DistSurface.input asks them.  What it returns is the
-- KEY to hold: on the ground the world direction is turned back through the
-- camera (OverworldState:walkDirection), on a wall or ceiling the key is the
-- plane's own.  The rafts, lifts and story scripts are not searched: a beat
-- walks to the tile that starts them and lets them run.

local DWI = require("src.import.Gen4DistWorld")
local S = require("src.world.Gen4DistSurface")
local Collision = require("src.world.Collision")

local D = {}

local KEYS = { "up", "down", "left", "right" }
local CELL = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local DIR_NAME = { [0] = "up", "down", "left", "right" }
local LEDGE = { north = "up", south = "down", west = "left", east = "right",
                up = "up", down = "down", left = "left", right = "right" }

local function inBounds(b, x, y, z)
  return x >= b.x and x <= b.x + b.sizeX and y >= b.y and y <= b.y + b.sizeY
     and z >= b.z and z <= b.z + b.sizeZ
end

-- the same first-match rule as Gen4DistSurface's `match`
local function match(list, x, y, z, dir, loose)
  for _, t in ipairs(list or {}) do
    if DIR_NAME[t.playerDir] == dir and inBounds(t.bounds, x, y, z) then return t, 0 end
  end
  if loose then
    for _, dy in ipairs({ -1, 1 }) do
      for _, t in ipairs(list or {}) do
        if DIR_NAME[t.playerDir] == dir and inBounds(t.bounds, x, y + dy, z) then return t, dy end
      end
    end
  end
end

local function platformAt(m, x, y, z, kind)
  for i, p in ipairs(m.platforms or {}) do
    if (kind == nil or p.kind == kind) and inBounds(p.bounds, x, y, z) then return i, p end
  end
end

local function attrOn(dw, p, x, y, z)
  local grid = dw.attrs and (dw.attrs[p.attr] or dw.attrs[tostring(p.attr)])
  if not grid then return nil end
  return DWI.attrAt(p, grid, x, y, z)
end

local function surfable(attr)
  local b = attr and (attr % 0x100)
  return b ~= nil and require("src.world.Map").G4_SURFABLE[b] == true
end

-- the world altitude of a map cell, the plate nearest `near` (a bridge has two)
local function cellY(ow, m, cx, cy, near)
  local g = ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local ok, list = false, nil
  if g and g.heightsAtPixel then ok, list = pcall(g.heightsAtPixel, g, cx * 16 + 8, cy * 16 + 8) end
  if not (ok and type(list) == "table" and #list > 0) then return near end
  local best = list[1]
  if near then
    local want = (near - (m.offsetAltitude or 0)) * 16
    for _, h in ipairs(list) do if math.abs(h - want) < math.abs(best - want) then best = h end end
  end
  return (m.offsetAltitude or 0) + math.floor(best / 16 + 0.5)
end

local function mapNode(m, cx, cy, y)
  return { map = true, cx = cx, cy = cy, x = cx + (m.offsetX or 0), y = y, z = cy + (m.offsetZ or 0),
           key = "m" .. cx .. "," .. cy }
end
local function surfNode(i, kind, x, y, z)
  return { index = i, kind = kind, x = x, y = y, z = z, key = "s" .. i .. ":" .. x .. "," .. y .. "," .. z }
end

-- where a jump record lands
local function jumpTarget(m, j, x, y, z)
  local tx, ty, tz = x + (j.displaceX or 0), y + (j.displaceY or 0), z + (j.displaceZ or 0)
  if j.targetKind == 4 or not (j.targetIndex and j.targetIndex < 0xFFFF) then
    return mapNode(m, tx - (m.offsetX or 0), tz - (m.offsetZ or 0), ty)
  end
  return surfNode(j.targetIndex + 1, j.targetKind, tx, ty, tz)
end

-- the moves out of a place, as { key, node }
local function edges(ow, m, dw, n, ledges, avoid)
  local out = {}
  local def = ow.map.def
  local P = require("src.world.Gen4DistPlatforms")
  if n.map then
    local map = ow.map
    for _, dir in ipairs(KEYS) do
      local j, dy = match(m.jumps, n.x, n.y, n.z, dir, true)
      if j then
        out[#out + 1] = { dir, jumpTarget(m, j, n.x, n.y + (dy or 0), n.z) }
      else
        local d = CELL[dir]
        local fx, fy = n.cx + d[1], n.cy + d[2]
        local hop
        if ledges and map:inBounds(fx, fy) then
          local b = map:cellBehaviour(fx, fy)
          if b and LEDGE[ledges[b] or ""] == dir then
            local tiles = (b >= 0x5A and b <= 0x5D) and 3 or 2
            local lx, ly = n.cx + d[1] * tiles, n.cy + d[2] * tiles
            if map:inBounds(lx, ly) and map:isWalkableCell(lx, ly) then
              hop = mapNode(m, lx, ly, cellY(ow, m, lx, ly, n.y))
            end
          end
        end
        if hop and avoid[hop.key] then hop = nil end
        if hop then
          out[#out + 1] = { dir, hop, "hop" }
        elseif not P.blocked(def, m, fx, fy) and not avoid["m" .. fx .. "," .. fy] then
          local mover = { cellX = n.cx, cellY = n.cy, elevation = ow.player.elevation, facing = dir,
                          surfing = ow.player.surfing }
          if Collision.canMove(map, ow.cast or ow.entities or ow.npcs or {}, mover, dir) then
            out[#out + 1] = { dir, mapNode(m, fx, fy, cellY(ow, m, fx, fy, n.y)) }
          end
        end
      end
    end
  else
    local plat = m.platforms[n.index]
    for _, dir in ipairs(KEYS) do
      local j = match(m.jumps, n.x, n.y, n.z, dir, false)
      if j then
        out[#out + 1] = { dir, jumpTarget(m, j, n.x, n.y, n.z) }
      else
        local d = S.STEP[n.kind][dir]
        local nx, ny, nz = n.x + d[1], n.y + d[2], n.z + d[3]
        local idx = n.index
        local attr = plat and attrOn(dw, plat, nx, ny, nz)
        if attr == nil and n.kind == 0 then
          local i, q = platformAt(m, nx, ny, nz, 0)
          if i then
            local a2 = attrOn(dw, q, nx, ny, nz)
            if DWI.passable(a2) then idx, attr = i, a2 end
          end
        end
        if DWI.passable(attr) and (ow.player.surfing or not surfable(attr)) then
          out[#out + 1] = { dir, surfNode(idx, n.kind, nx, ny, nz) }
        end
      end
    end
  end
  return out
end

-- (the moves out of a place, for a beat that has to see why there is no way)
D.edges, D.mapNode = edges, mapNode

-- where the player is now, as a node
function D.here(ow)
  local m = S.floorFor(ow.map and ow.map.def)
  if not m then return nil end
  local st = ow.dwSurface
  if st then return surfNode(st.index, st.kind, st.x, st.y, st.z), m end
  local p = ow.player
  local _, y = S.position(ow, m)
  return mapNode(m, p.cellX, p.cellY, y), m
end

-- does node n satisfy goal g ({ cell = {cx, cy} } or { tile = {x, y, z} })
local function reached(n, g)
  if g.cell then return n.map and n.cx == g.cell[1] and n.cy == g.cell[2] end
  local t = g.tile
  if n.x ~= t[1] or n.z ~= t[3] then return false end
  if n.map then return math.abs(n.y - t[2]) <= 1 end
  return n.y == t[2]
end
D.reached = reached

-- The first key of the shortest way to `goal`, "here" when standing on it, or
-- nil when there is none.  Then the length of the way, the start node and
-- "hop" when the first move is a double jump (with no way: every node that
-- could be reached, in place of that last).
function D.plan(ow, goal)
  local start, m = D.here(ow)
  if not start then return nil end
  local _, dw = S.floorFor(ow.map.def)
  if reached(start, goal) then return "here", 0 end
  local ledges = ow.map.tileset and ow.map.tileset.ledgeBehaviours
  local G = package.loaded["src.core.Game"]
  ledges = ledges or (G and G.data and G.data.field and G.data.field.ledgeBehaviours)
  -- every OTHER warp is a wall on the way: a lift's cell rides it, and the
  -- way to one lift passes the pocket of another
  local avoid = {}
  for _, w in ipairs(ow.map.def.warps or {}) do
    if not (goal.cell and goal.cell[1] == w.x and goal.cell[2] == w.y) then
      avoid["m" .. w.x .. "," .. w.y] = true
    end
  end
  local prev = { [start.key] = false }
  local q, head = { start }, 1
  while head <= #q and head < 60000 do
    local n = q[head]; head = head + 1
    for _, e in ipairs(edges(ow, m, dw, n, ledges, avoid)) do
      local nn = e[2]
      if prev[nn.key] == nil then
        prev[nn.key] = { n, e[1], e[3] }
        if reached(nn, goal) then
          local cur, first, len, how = nn, e[1], 0, e[3]
          while prev[cur.key] do
            first, how = prev[cur.key][2], prev[cur.key][3]
            cur = prev[cur.key][1]; len = len + 1
          end
          return first, len, start, how
        end
        q[#q + 1] = nn
      end
    end
  end
  -- no way: the places that were reachable, for a beat's diagnosis
  return nil, nil, start, q
end

-- The key that makes the step `dir` from `node`: on the ground the camera
-- turns the pad (walkDirection), so the key whose turn is `dir`.
function D.keyFor(ow, node, dir)
  if node and not node.map and node.kind ~= 0 then return dir end
  if not ow.walkDirection then return dir end
  for _, k in ipairs(KEYS) do
    if ow:walkDirection(k) == dir then return k end
  end
  return dir
end

return D
