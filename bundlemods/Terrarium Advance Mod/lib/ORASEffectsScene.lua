-- ORAS move effects on the 3D-BTL rungs (2D-3D A/B, COLOSSEUM A/B): battles
-- staged on the map by lib/OverworldBattle.lua and drawn by lib/BattleScene.lua.
--
-- Independent of the Colosseum runtime: it hooks the engine's own
-- BattleState.performMove (the seam lib/Stadium.lua uses for the models'
-- attack animation), positions effects from whatever stands on each tile,
-- and draws into BattleScene's 3D canvas with its camera (Voxel3D.vp):
--
--   3D model with a body map (ORAS / Colosseum actor)   actor:attachment(slot)
--   other 3D model (Stadium)                            model origin + height
--   2D pic card                                          the cell + card height
--
-- Size: effects are authored in centimetres.  An ORAS actor gives the exact
-- scale (worldScale * posed height / nativeHeight); otherwise the target's
-- drawn height is taken as a metre.
--
-- While an ORAS effect plays here, the engine's own GB move animation layer
-- is not drawn (it would play the same move a second time over the 3D one).

local V = ...

local S = {}

local CARD_H = 16          -- a 2D pic card is one cell tall (BattleBillboard)
local GENERIC_CM = 100     -- a mon with no known size: its drawn height = 1 m

local function Effects() return V.require("ORASEffects") end
local function Player() return V.require("ORASEffectsPlayer") end

local function staged()
  local okO, OB = pcall(V.require, "OverworldBattle")
  if not okO or not OB then return nil end
  local okA, arena, groundY = pcall(OB.arenaInfo)
  if okA and arena then return arena, groundY or 0 end
  return nil
end

local function monOf(side)
  local okS, St = pcall(V.require, "Stadium")
  if not (okS and St and St.sideMon) then return nil end
  local ok, mon, gy = pcall(St.sideMon, side)
  if ok then return mon, gy end
end

local function cellOf(arena, side)
  local c = side == "player" and arena.player or arena.enemy
  if type(c) == "table" and tonumber(c[1]) and tonumber(c[2]) then return c end
end

local function heightOf(mon)
  if mon and mon.model_matrix and type(mon.worldHeight) == "function" then
    local ok, h = pcall(mon.worldHeight, mon)
    if ok and tonumber(h) and h > 0 then return h end
  end
  return CARD_H
end

local function oraScale(actor)
  local sc = actor and actor.scene
  if not (sc and sc.source == "ORAS") then return nil end
  local b, nh = sc.bounds, tonumber(sc.nativeHeight)
  local h = b and b.max and b.min and (tonumber(b.max[2]) or 0) - (tonumber(b.min[2]) or 0) or 0
  if nh and nh > 1e-6 and h > 1e-6 then return (tonumber(actor.worldScale) or 1) * h / nh end
end

local function point(arena, groundY, side, slot)
  local mon = monOf(side)
  local actor = mon and mon.visible ~= false and mon.actor
  if actor and actor.worldMatrix and type(actor.attachment) == "function" then
    for _, name in ipairs({ slot, "center", "chest" }) do
      local ok, a = pcall(actor.attachment, actor, name)
      local p = ok and type(a) == "table" and a.position
      if p and tonumber(p[1]) then return { p[1], p[2], p[3] }, true end
    end
  end
  local m = mon and mon.model_matrix
  local h = heightOf(mon)
  local k = (slot == "origin" and 0) or ((slot == "mouth" or slot == "eye_left") and 0.7) or 0.5
  if type(m) == "table" and tonumber(m[4]) then
    return { m[4], m[8] + h * k, m[12] }
  end
  local c = cellOf(arena, side)
  if not c then return nil end
  return { c[1], groundY + h * k, c[2] }
end

local function unit(attacker, defender)
  for _, side in ipairs({ attacker, defender }) do
    local mon = monOf(side)
    local u = oraScale(mon and mon.actor)
    if u then return u end
  end
  return heightOf((monOf(defender))) / GENERIC_CM
end

-- Start the move's ORAS effect on the staged fight; returns the run id.
function S.start(battle, user, moveIndex)
  local E = Effects()
  if not E.active() then return false end
  local arena, groundY = staged()
  if not arena then return false end
  local attacker = (battle and user == battle.player) and "player"
    or ((battle and user == battle.enemy) and "enemy" or nil)
  if not attacker then
    Player().note("3D-BTL move %s: user is neither battle.player nor battle.enemy", tostring(moveIndex))
    return false
  end
  local okSt, St = pcall(V.require, "Stadium")
  Player().note("3D-BTL move %s by %s (rung %s)", tostring(moveIndex), attacker,
    tostring(okSt and St and St.mode and St.mode() or "2D-3D"))
  local defender = attacker == "player" and "enemy" or "player"
  local host = {
    point = function(role, slot)
      return point(arena, groundY, role == "attacker" and attacker or defender, slot)
    end,
    forward = function()
      local a, b = cellOf(arena, attacker), cellOf(arena, defender)
      if not (a and b) then return { 0, 0, 1 } end
      local dx, dz = b[1] - a[1], b[2] - a[2]
      local l = math.sqrt(dx * dx + dz * dz)
      if l < 1e-6 then return { 0, 0, 1 } end
      return { dx / l, 0, dz / l }
    end,
    unit = function() return unit(attacker, defender) end,
    attackerSide = attacker,
  }
  local ok, id = pcall(Player().start, moveIndex, host, "scene")
  if ok and id then S.lastSide = attacker end
  return ok and id or false
end

-- ------------------------------------------------------------------ stage
--
-- Timeline records that move the fight itself (lib/ORASStage.lua): the
-- Pokemon's own position and size, afterimage ghosts, the stage dimming and
-- the camera.  Asked by lib/Stadium.lua (3D models), BattleScene's 2D cards
-- and BattleScene's camera, every frame; nil whenever no such move runs.

local function Stage() return V.require("ORASStage") end

-- the running stage move: run, frame, attacker side
local function stageNow()
  if not Effects().active() then return nil end
  local ok, run, f = pcall(Player().stageRun, "scene")
  if ok and run and run.host and run.host.attackerSide then return run, f, run.host.attackerSide end
end

-- a side's frame on the map: right, forward (unit vectors, y = 0)
local function sideBasis(arena, side)
  local a = cellOf(arena, side)
  local b = cellOf(arena, side == "player" and "enemy" or "player")
  local fx, fz = 0, 1
  if a and b then
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local l = math.sqrt(dx * dx + dz * dz)
    if l > 1e-6 then fx, fz = dx / l, dz / l end
  end
  return { fz, 0, -fx }, { fx, 0, fz }   -- right = up x forward, as ORASEffectsPlayer
end

local function toWorld(arena, side, v, u)
  local r, f = sideBasis(arena, side)
  return (r[1] * v[1] + f[1] * v[3]) * u, v[2] * u, (r[3] * v[1] + f[3] * v[3]) * u
end

-- Where `side` stands this frame relative to its own place: { dx, dy, dz
-- (world), sx, sy, sz, ghosts = { {dx, dy, dz, alpha} } } or nil.
function S.actorPose(side)
  local run, f, attacker = stageNow()
  if not run then return nil end
  local arena = staged()
  if not arena then return nil end
  local who = (side == attacker) and 0 or 1
  local p = Stage().actor(run.entry, who, f)
  local o, sc = p.offset, p.scale
  if o[1] == 0 and o[2] == 0 and o[3] == 0 and sc[1] == 1 and sc[2] == 1 and sc[3] == 1
      and #p.ghosts == 0 then
    return nil
  end
  local okU, u = pcall(run.host.unit)
  u = okU and tonumber(u) or nil
  if not u or u <= 0 then return nil end
  local dx, dy, dz = toWorld(arena, side, o, u)
  local out = { dx, dy, dz, sc[1], sc[2], sc[3], ghosts = {} }
  for _, g in ipairs(p.ghosts) do
    local gx, gy, gz = toWorld(arena, side, g, u)
    out.ghosts[#out.ghosts + 1] = { gx, gy, gz, g[4] }
  end
  run.stageNote = ("%s off (%.0f,%.0f,%.0f)cm scale (%.2f,%.2f,%.2f) ghosts %d"):format(
    side, o[1], o[2], o[3], sc[1], sc[2], sc[3], #out.ghosts)
  return out
end

-- A model matrix moved by this frame's pose: scaled about its feet
-- (fx, fy, fz) and shifted.  Mat4 is lib/Mat4.lua.
function S.adjustMatrix(side, m, fx, fy, fz)
  local pose = S.actorPose(side)
  if not (pose and m) then return m, nil end
  local Mat4 = V.require("Mat4")
  if pose[4] ~= 1 or pose[5] ~= 1 or pose[6] ~= 1 then
    m = Mat4.mul(Mat4.translate(fx, fy, fz),
      Mat4.mul(Mat4.scale(pose[4], pose[5], pose[6]), Mat4.mul(Mat4.translate(-fx, -fy, -fz), m)))
  end
  if pose[1] ~= 0 or pose[2] ~= 0 or pose[3] ~= 0 then
    m = Mat4.mul(Mat4.translate(pose[1], pose[2], pose[3]), m)
  end
  return m, pose
end

-- Stage colour {r, g, b, a}: the arena fades to it (the Pokemon do not).
function S.tint()
  local run, f = stageNow()
  if not run then return nil end
  return Stage().tint(run.entry, f)
end

-- a move camera keeps this share of the gap between the two cells away from
-- either Pokemon (horizontally), and never comes in closer than MIN_PULL of
-- its own distance
local CLEAR_FRACTION = 0.4
local MIN_PULL = 0.25
local MAX_FOV = 80        -- degrees; ORAS CAM ZOOM 25% on a pulled-in eye reaches it

-- BattleScene's camera, moved by the move's camera records (op 0x17).
-- cam = { eye, focus, fov }, changed in place; true when it moved.
function S.camera(cam)
  local run, f, attacker = stageNow()
  if not (run and cam and cam.eye and cam.focus) then return false end
  -- OPTIONS -> ORAS CAMERA
  local okE, on = pcall(function() return Effects().cameraEnabled() end)
  if okE and on == false then
    run.camNote = "off (ORAS CAMERA)"
    return false
  end
  local arena, groundY = staged()
  if not arena then return false end
  local okU, u = pcall(run.host.unit)
  u = okU and tonumber(u) or nil
  if not u or u <= 0 then return false end
  local defender = attacker == "player" and "enemy" or "player"
  local POINT = { [0] = "origin", [2] = "mouth", [3] = "center", [5] = "center", [6] = "chest" }
  -- the side's own spot (its cell, at the body point's height without the
  -- move's hops): the camera must not shake along with Double Team
  local function spot(side, slot)
    local p, onActor = point(arena, groundY, side, slot)
    local c = cellOf(arena, side)
    if not (p and c) then return p end
    -- only an actor's body point carries the hop (a card's point is its cell)
    local dy = 0
    if onActor then
      local okP, pose = pcall(S.actorPose, side)
      dy = okP and pose and pose[2] or 0
    end
    return { c[1], math.max(groundY, p[2] - dy), c[2] }
  end
  local function place(op)
    local side = (op.w == 1) and defender or attacker
    local slot = POINT[op.point] or "center"
    local base = spot(side, slot)
    if op.w == 2 then
      -- both: halfway between the two
      local p, q = spot(attacker, slot), spot(defender, slot)
      if p and q then base = { (p[1] + q[1]) / 2, (p[2] + q[2]) / 2, (p[3] + q[3]) / 2 } end
    end
    if not base then return nil end
    local ex, ey, ez = toWorld(arena, side, op.eye, u)
    local lx, ly, lz = toWorld(arena, side, op.look, u)
    return { base[1] + ex, base[2] + ey, base[3] + ez }, { base[1] + lx, base[2] + ly, base[3] + lz }
  end
  local c = Stage().camera(run.entry, f,
    { eye = cam.eye, look = cam.focus }, place)
  if not c then return false end
  -- a broken camera (eye on its target, NaN) would throw in the projection,
  -- and one render error retires the 3D scene for the rest of the battle
  local d2 = 0
  for i = 1, 3 do
    local e, l = c.eye[i], c.look[i]
    if e ~= e or l ~= l or math.abs(e) > 1e6 or math.abs(l) > 1e6 then return false end
    d2 = d2 + (e - l) ^ 2
  end
  if d2 < 1e-4 then return false end
  -- ORAS stands the two Pokemon much further apart than our cells do: its
  -- close-ups (Double Team: 3 m in front of the user) put the eye INSIDE the
  -- other Pokemon here.  Slide the eye toward its target until it is clear
  -- of both cells, and open the lens by the same ratio so the subject keeps
  -- the size ORAS gives it.
  local far = math.sqrt(d2)
  local pa, pd = cellOf(arena, attacker), cellOf(arena, defender)
  local keep = CLEAR_FRACTION * (pa and pd and math.sqrt((pa[1] - pd[1]) ^ 2 + (pa[2] - pd[2]) ^ 2) or 32)
  -- horizontal room between the eye (at t of its way out from the target)
  -- and the nearer of the two cells
  local function room(t)
    local x = c.look[1] + (c.eye[1] - c.look[1]) * t
    local z = c.look[3] + (c.eye[3] - c.look[3]) * t
    local r = math.huge
    for _, p in ipairs({ pa, pd }) do
      if p then r = math.min(r, math.sqrt((x - p[1]) ^ 2 + (z - p[2]) ^ 2)) end
    end
    return r
  end
  local t = 1
  if room(1) < keep then
    -- the farthest clear spot on the way in, else the roomiest one
    local best, bestRoom = 1, room(1)
    local found = false
    for k = 1, 60 do
      local tk = 1 - (1 - MIN_PULL) * k / 60
      local r = room(tk)
      if r >= keep then best, found = tk, true; break end
      if r > bestRoom then best, bestRoom = tk, r end
    end
    t = best
    for i = 1, 3 do c.eye[i] = c.look[i] + (c.eye[i] - c.look[i]) * t end
  end
  -- never under the ground (Fly's low shots, a sunk arena floor)
  c.eye[2] = math.max(c.eye[2], (groundY or 0) + 2)
  run.camNote = ("eye (%.1f, %.1f, %.1f) look (%.1f, %.1f, %.1f) weight %.2f pulled in x%.2f"):format(
    c.eye[1], c.eye[2], c.eye[3], c.look[1], c.look[2], c.look[3], c.weight, t)
  cam.eye, cam.focus = c.eye, c.look
  -- ORAS frames every move with an 11.3 degree lens (op 0x63, all moves),
  -- opened up when the eye was pulled in
  -- OPTIONS -> ORAS CAM ZOOM: how big the subject is against ORAS's own
  -- framing (50% = half as big); a wider lens, so the eye stays where it is
  -- clear of both Pokemon
  local okZ, zoom = pcall(function() return Effects().cameraZoom() end)
  zoom = (okZ and tonumber(zoom) or 100) / 100
  local orasFov = 2 * math.atan(math.tan(math.rad(11.3) / 2) / (math.max(t, 1e-3) * math.max(zoom, 0.05)))
  orasFov = math.min(orasFov, math.rad(MAX_FOV))
  run.camNote = run.camNote .. (" zoom %d%% fov %.1f"):format(zoom * 100, math.deg(orasFov))
  if cam.fov then cam.fov = cam.fov + (orasFov - cam.fov) * c.weight end
  return true
end

function S.busy()
  local ok, b = pcall(Player().busy, "scene")
  return ok and b == true
end

-- BattleScene.render, after the 3D pass resolved into `canvas` (pw x ph)
function S.draw(canvas, pw, ph, vp)
  if not (canvas and vp and S.busy()) then return false end
  local g = love.graphics
  local project = function(x, y, z)
    local cx = vp[1] * x + vp[2] * y + vp[3] * z + vp[4]
    local cy = vp[5] * x + vp[6] * y + vp[7] * z + vp[8]
    local cw = vp[13] * x + vp[14] * y + vp[15] * z + vp[16]
    if cw <= 1e-6 then return nil end
    return (cx / cw * 0.5 + 0.5) * pw, (cy / cw * 0.5 + 0.5) * ph
  end
  local P = Player()
  local okC, prev = pcall(g.getCanvas)
  local okS, err = pcall(g.setCanvas, canvas)
  if not okS then
    if not S.warned then S.warned = true; P.note("3D-BTL draw: cannot target the scene canvas: %s", tostring(err)) end
    return false
  end
  P.drawingVia = "3D-BTL scene"
  local ok, drew = pcall(P.draw, project, "scene")
  P.drawingVia = nil
  pcall(g.setCanvas, okC and prev or nil)
  if not ok and not S.warned then S.warned = true; P.note("3D-BTL draw failed: %s", tostring(drew)) end
  return ok and drew
end

function S.install()
  local okB, BattleState = pcall(require, "src.battle.BattleState")
  if not okB or type(BattleState) ~= "table" or BattleState.orasEffectsSceneHook then return end
  local innerMove = BattleState.performMove
  if type(innerMove) == "function" then
    function BattleState:performMove(user, target, moveInst, isCalled)
      pcall(function()
        if not Effects().active() then return end
        local okDef, def = pcall(self.moveDef, self, moveInst)
        local index = okDef and def and tonumber(def.index) or nil
        if index then S.start(self, user, index) end
      end)
      return innerMove(self, user, target, moveInst, isCalled)
    end
  end
  -- the GB move animation would replay the move over the ORAS one
  local innerAnim = BattleState.drawAnimLayer
  if type(innerAnim) == "function" then
    function BattleState:drawAnimLayer(...)
      if self.dramaticShapeShot and S.busy() then return end
      return innerAnim(self, ...)
    end
  end
  BattleState.orasEffectsSceneHook = true
end

return S
