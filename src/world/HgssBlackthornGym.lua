-- Clair's gym in Blackthorn City: the platforms over the magma
-- (HeartGold / SoulSilver).
--
-- pokeheartgold src/field/gymmick/blackthorn.c and gymmick_init.c,
-- transcribed. Three platforms (build models 120, 121, 120 at height 48),
-- each a 3 x 6 floor the player can stand on with three buttons on it: the
-- centre ROTATES the platform a quarter turn about the player, the cell
-- either side of it MOVES the platform its own width along its rotated axis.
-- A move steps one tile every 2 frames (8 units a frame) while the tiles in
-- front of its leading wall are magma that nothing solid stands on; meeting
-- anything else it bonks and slides back to where it started. A rotation is
-- 16 frames (a quarter of 16 units of the prop's angle); if a wall is in the
-- way it turns only as far as the extent tables allow and swings back.
--
-- Points here are tables {x = , z = } in map tiles.

local G = {}

G.MODELS = { 120, 121, 120 }
G.HEIGHT = 48
G.MAGMA = 0x2C              -- TILE_BEHAVIOR_MAGMA
G.QUARTER = 0x4000          -- FX_DEG_TO_IDX(90)

-- InitBlackthornGym
function G.initialState()
  return { kind = "blackthorn", x = { 13, 9, 14 }, z = { 75, 58, 32 }, rot = { 0, 1, 0 } }
end

local MAIN_EXTENTS = {
  [0] = { 10, 10, 13, 18, 25, 38, 51, 64, 64, 23, 28, 35, 45, 55 },
  [1] = { 8, 9, 10, 14, 19, 26, 37, 51, 64, 17, 19, 23, 28, 35, 46, 55,
          64, 64, 64, 30, 35, 41, 49, 57 },
}
local EDGE_EXTENTS = { [0] = { 64, 64, 64, 64, 42 }, [1] = { 64, 20, 30, 46 } }

local function pt(x, z) return { x = x, z = z } end

-- BlackthornGymmick_ApplyRotationToPoints, in place
local function rotatePoint(rot, x, z, p)
  local dx, dz = p.x - x, p.z - z
  if rot == 1 then p.x, p.z = -dz, dx
  elseif rot == 2 then p.x, p.z = -dx, -dz
  elseif rot == 3 then p.x, p.z = dz, -dx
  else return end
  p.x, p.z = p.x + x, p.z + z
end

-- BlackthornPlatform_ApplyRotation (the rotate button and the unused pair
-- stay where they are)
function G.applyRotation(rot, x, z, pf)
  local area = pf.shape == 0 and 14 or 24
  rotatePoint(rot, x, z, pf.moveLeftButton)
  rotatePoint(rot, x, z, pf.moveRightButton)
  for i = 1, pf.height do rotatePoint(rot, x, z, pf.rightWall[i]) end
  for i = 1, pf.height do rotatePoint(rot, x, z, pf.leftWall[i]) end
  for i = 1, pf.width do rotatePoint(rot, x, z, pf.bottomWall[i]) end
  for i = 1, pf.width do rotatePoint(rot, x, z, pf.topWall[i]) end
  for i = 1, area do rotatePoint(rot, x, z, pf.rotateCheck[i]) end
  for i = 1, pf.width do rotatePoint(rot, x, z, pf.rightEdgeOuter[i]) end
  for i = 1, 18 do rotatePoint(rot, x, z, pf.floor[i]) end
end

-- BlackthornPlatform_Init: index 0-based (1 is the long one)
function G.platform(index, rot, x, z)
  local pf = {
    rotateButton = pt(x, z), moveLeftButton = pt(x + 1, z), moveRightButton = pt(x - 1, z),
    rightWall = {}, leftWall = {}, bottomWall = {}, topWall = {}, rotateCheck = {},
    rightEdgeOuter = {}, floor = {},
  }
  if index ~= 1 then
    pf.shape, pf.width, pf.height = 0, 5, 7
    for i = 0, 6 do pf.rightWall[i + 1] = pt(x + 3, z - 2 + i) end
    for i = 0, 6 do pf.leftWall[i + 1] = pt(x - 3, z - 2 + i) end
    for i = 0, 4 do pf.bottomWall[i + 1] = pt(x - 2 + i, z + 5) end
    for i = 0, 4 do pf.topWall[i + 1] = pt(x - 2 + i, z - 3) end
    for i = 0, 1 do
      for j = 0, 6 do pf.rotateCheck[i * 7 + j + 1] = pt(x - 4 - i, z + 4 - j) end
    end
  else
    pf.shape, pf.width, pf.height = 1, 4, 8
    for i = 0, 7 do pf.rightWall[i + 1] = pt(x + 2, z - 2 + i) end
    for i = 0, 7 do pf.leftWall[i + 1] = pt(x - 3, z - 2 + i) end
    for i = 0, 3 do pf.bottomWall[i + 1] = pt(x - 2 + i, z + 6) end
    for i = 0, 3 do pf.topWall[i + 1] = pt(x - 2 + i, z - 3) end
    for i = 0, 2 do
      for j = 0, 7 do pf.rotateCheck[i * 8 + j + 1] = pt(x - 4 - i, z + 5 - j) end
    end
  end
  for i = 0, pf.width - 1 do pf.rightEdgeOuter[i + 1] = pt(x + 3, z - 2 + i) end
  for i = 0, 5 do
    for j = 0, 2 do pf.floor[i * 3 + j + 1] = pt(x - 1 + j, z - 1 + i) end
  end
  pf.rotation = rot
  G.applyRotation(rot, x, z, pf)
  return pf
end

function G.platforms(state)
  local out = {}
  for i = 1, 3 do out[i] = G.platform(i - 1, state.rot[i], state.x[i], state.z[i]) end
  return out
end

-- BlackthornGymmick_GetButtonAction -> platform index (1-based), action
function G.buttonAt(pfs, x, z)
  for i, pf in ipairs(pfs) do
    if x == pf.rotateButton.x and z == pf.rotateButton.z then return i, "rotate" end
    if x == pf.moveLeftButton.x and z == pf.moveLeftButton.z then return i, "right" end
    if x == pf.moveRightButton.x and z == pf.moveRightButton.z then return i, "left" end
  end
  return nil
end

-- (rotation + 0 or 2) % 4: 0 +x, 1 +z, 2 -x, 3 -z
G.DIR = { [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 } }
function G.moveDirection(rotation, action)
  return ((action == "right" and 0 or 2) + rotation) % 4
end

-- BlackthornGymmick_CheckWallCollision: the first point that is solid or
-- not magma, or nil. `blocked(x, z)` answers the first half, `behaviour(x,
-- z)` the second.
function G.wallHit(points, count, blocked, behaviour)
  for i = 1, count do
    local p = points[i]
    if blocked(p.x, p.z) or behaviour(p.x, p.z) ~= G.MAGMA then return i end
  end
  return nil
end

local function maxExtent(points, count, extents, blocked, behaviour)
  for i = 1, count do
    local p = points[i]
    if blocked(p.x, p.z) or behaviour(p.x, p.z) ~= G.MAGMA then
      local v = (extents[i] or 64) * 256
      if v < G.QUARTER then return v end
    end
  end
  return G.QUARTER
end

-- ov04_02255CBC -> "no", "partial" (with the extent, 0..0x4000) or "ok"
function G.rotationCheck(pf, blocked, behaviour)
  if G.wallHit(pf.bottomWall, pf.width, blocked, behaviour) then return "no" end
  if G.wallHit(pf.topWall, pf.width, blocked, behaviour) then return "no" end
  if G.wallHit(pf.leftWall, pf.height, blocked, behaviour) then return "no" end
  if G.wallHit(pf.rightWall, pf.width - 1, blocked, behaviour) then return "no" end
  local area = pf.shape == 0 and 14 or 24
  local main = maxExtent(pf.rotateCheck, area, MAIN_EXTENTS[pf.shape], blocked, behaviour)
  local edge = maxExtent(pf.rightEdgeOuter, pf.width, EDGE_EXTENTS[pf.shape], blocked, behaviour)
  local e = math.min(main, edge)
  if e < G.QUARTER then return "partial", e end
  return "ok"
end

-- the leading wall a move starts from, copied
function G.leadingWall(pf, action)
  local src = action == "right" and pf.rightWall or pf.leftWall
  local out = {}
  for i = 1, pf.height do out[i] = pt(src[i].x, src[i].z) end
  return out
end

-- GymmickCheckCollision_Blackthorn: false (walkable) on a platform's floor,
-- true (blocked) on bare magma, nil (ask the map) elsewhere
function G.collides(pfs, x, z, behaviour)
  for _, pf in ipairs(pfs) do
    for i = 1, 18 do
      if pf.floor[i].x == x and pf.floor[i].z == z then return false end
    end
  end
  if behaviour(x, z) == G.MAGMA then return true end
  return nil
end

-- ---------------------------------------------------------------- runtime --
-- The overworld side: `G.attach(ow, save)` (from BlackthornGymInit) hangs
-- four hooks on the map def -- the per-frame driver (`gen4PropFollow`), the
-- button check on each step (`gen4StepHook`), the collision rule
-- (`gen4CollisionHook`) and the floor heights (`gen4HeightEdits`).

local function mapQueries(ow)
  local map = ow.map
  local function behaviour(x, z) return map and map.cellBehaviour and map:cellBehaviour(x, z) or 0 end
  local function blocked(x, z) return map and map.cellCollision and (map:cellCollision(x, z) or 0) ~= 0 or false end
  return blocked, behaviour
end

local function publish(ow, run)
  local def = ow.map and ow.map.def
  if not def then return end
  local g = run.state
  local props, edits = {}, {}
  for i = 1, 3 do
    local ox, oz, turn = 0, 0, 0
    if run.anim and run.anim.index == i then
      ox, oz, turn = run.anim.ox or 0, run.anim.oz or 0, run.anim.turn or 0
    end
    props[i] = { model = G.MODELS[i], x = 16 * g.x[i] + 8 + ox, y = G.HEIGHT, z = 16 * g.z[i] + 8 + oz,
                 rotY = -90 * g.rot[i] - turn, ground = true }
    for _, f in ipairs(run.pfs[i].floor) do edits[f.x .. "," .. f.z] = G.HEIGHT end
  end
  def.gen4RuntimeProps = props
  def.gen4HeightEdits = edits
end

local function finish(ow, run)
  local p = ow.player
  run.anim = nil
  if p then p.inputLocked = run.wasLocked end
  run.pfs = G.platforms(run.state)
  publish(ow, run)
end

local STEP_UNITS = 8   -- a frame; a tile is 2 frames

local function tick(ow, run)
  local a = run.anim
  if not a then return end
  local p = ow.player
  local blocked, behaviour = mapQueries(ow)
  if a.kind == "move" then
    local pf = run.pfs[a.index]
    local d = G.DIR[a.dir]
    if a.phase == "check" then
      if G.wallHit(a.wall, pf.height, blocked, behaviour) then
        if a.steps == 0 then finish(ow, run) return end
        a.phase, a.timer = "back", 0
      else
        a.phase, a.timer = "run", 0
      end
    end
    if a.phase == "run" then
      a.timer = a.timer + 1
      a.ox, a.oz = a.ox + d[1] * STEP_UNITS, a.oz + d[2] * STEP_UNITS
      if p then p.px, p.py = p.px + d[1] * STEP_UNITS, p.py + d[2] * STEP_UNITS end
      if a.timer >= 2 then
        for _, w in ipairs(a.wall) do w.x, w.z = w.x + d[1], w.z + d[2] end
        a.steps = a.steps + 1
        if a.steps >= a.distance then
          local g = run.state
          g.x[a.index], g.z[a.index] = g.x[a.index] + d[1] * a.distance, g.z[a.index] + d[2] * a.distance
          if p then
            p.cellX, p.cellY = p.cellX + d[1] * a.distance, p.cellY + d[2] * a.distance
            p.px, p.py = p.cellX * 16, p.cellY * 16
          end
          finish(ow, run)
          return
        end
        a.phase = "check"
      end
    elseif a.phase == "back" then
      a.timer = a.timer + 1
      a.ox, a.oz = a.ox - d[1] * STEP_UNITS, a.oz - d[2] * STEP_UNITS
      if p then p.px, p.py = p.px - d[1] * STEP_UNITS, p.py - d[2] * STEP_UNITS end
      if a.timer >= 2 then
        a.timer = 0
        a.steps = a.steps - 1
        if a.steps <= 0 then
          if p then p.px, p.py = p.cellX * 16, p.cellY * 16 end
          finish(ow, run)
          return
        end
      end
    end
  else -- rotate: 90 degrees over 16 frames, or out to the extent and back
    local per = 90 / 16
    if a.phase == "run" then
      a.turn = a.turn + per
      a.timer = a.timer + 1
      if a.timer >= 16 then
        local g = run.state
        g.rot[a.index] = (g.rot[a.index] + 1) % 4
        finish(ow, run)
        return
      end
    elseif a.phase == "bonk" then
      a.turn = math.min(a.turn + per, a.limit)
      if a.turn >= a.limit then a.phase = "return" end
    elseif a.phase == "return" then
      a.turn = a.turn - per
      if a.turn <= 0 then finish(ow, run) return end
    end
  end
  publish(ow, run)
end

-- a button underfoot starts its action (FieldSystem_ProcessStep's first test)
local function step(ow, run, x, z)
  if run.anim then return true end
  local i, action = G.buttonAt(run.pfs, x, z)
  if not i then return false end
  local pf = run.pfs[i]
  local p = ow.player
  run.wasLocked = p and p.inputLocked
  local Logger = require("src.core.Logger")
  if action == "rotate" then
    local verdict, extent = G.rotationCheck(pf, mapQueries(ow))
    Logger.debug("gen4 blackthorn gym: platform %d rotate -- %s%s", i, verdict,
                extent and (" to %d / 16384"):format(extent) or "")
    if verdict == "no" then return false end
    run.anim = { kind = "rotate", index = i, timer = 0, turn = 0,
                 phase = verdict == "ok" and "run" or "bonk",
                 limit = extent and (extent / G.QUARTER * 90) or 90 }
  else
    Logger.debug("gen4 blackthorn gym: platform %d moves %s (direction %d)", i, action,
                G.moveDirection(pf.rotation, action))
    run.anim = { kind = "move", index = i, steps = 0, distance = pf.width, timer = 0,
                 dir = G.moveDirection(pf.rotation, action), wall = G.leadingWall(pf, action),
                 phase = "check", ox = 0, oz = 0 }
  end
  if p then p.inputLocked = true end
  return true
end

function G.attach(ow, save)
  local def = ow and ow.map and ow.map.def
  if not (def and save) then return nil end
  save.hgssGymmick = G.initialState()
  local run = { state = save.hgssGymmick }
  run.pfs = G.platforms(run.state)
  def.gen4PropFollow = function(o) tick(o, run) end
  def.gen4StepHook = function(o, x, z) return step(o, run, x, z) end
  def.gen4CollisionHook = function(map, x, z)
    local _, behaviour = mapQueries({ map = map })
    return G.collides(run.pfs, x, z, behaviour)
  end
  publish(ow, run)
  return run
end

return G
