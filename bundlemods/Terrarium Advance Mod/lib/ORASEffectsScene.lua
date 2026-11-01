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
      if p and tonumber(p[1]) then return { p[1], p[2], p[3] } end
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
  }
  local ok, id = pcall(Player().start, moveIndex, host, "scene")
  if ok and id then S.lastSide = attacker end
  return ok and id or false
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
