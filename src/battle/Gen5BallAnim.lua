-- BLACK AND WHITE'S CAPTURE THROW, played from the cartridge's own effect.
--
-- Platinum and HeartGold throw from code (`Gen4BallAnim`, ov12's BallThrow);
-- Black and White throw from the EFFECT VM. Shared effect 570 (/a/0/6/7
-- member 9) is the whole capture, and this module runs it on a private
-- Gen5MoveAnimPlayer and stands in the battle's `gen4Ball` slot with
-- Gen4BallAnim's interface (estimate / isDone / update / hidesMon /
-- absorbFor / x, y, visible), so BattleState's catch flow and Gen4Battle's
-- draw seams carry it unchanged. What effect 570 does, read off its
-- instructions (operands in the player's units):
--
--   PARTICLE_LOAD 48 (the ball's spin set, remapped by the ball: 48 + 4(b-1))
--   CAMERA to the defender over 200 frames
--   EMITTER_MOVE from (0, -2, 10) to the defender, 2.4 up, 35 frames, arc 5:
--     the throw, its spin the SPA's eight-frame texture loop
--   (var 14, a critical capture: SE 1404 and a wobble before it lands)
--   WAIT 40; the camera eases in; the open burst (49 + 29) at the defender;
--   the Pokemon whitens, rises 2.5 and shrinks to nothing in 20 frames, gone
--   OBJ_CREATE_BALL 0 (the ball as a 2D OBJ, /a/0/9/5 129 / 130 / 129 + 2b)
--   and 1 (the same cell flattened and faded dark: its shadow), at the
--   defender 2.47 up; the ball falls 40 pixels in 12 frames and bounces
--   (-8 / -2 / +2 / +8, then -3 / -1 / +1 / +3, SE 1387 at 127, 96, 64)
--   WAIT 40, then var 12 rocks: OBJ animations 1, 2, 3 (33 / 31 / 30 frames)
--   with SE 1384, 65 / 70 / 75 frames apart
--   var 13 (caught): SE 1396, the ball darkens (evy 8), the stars (28)
--   otherwise: the open burst again, the OBJs deleted, the Pokemon back
--
-- The battle sets vars 12 / 13 / 14 (shakes, caught, critical); this port
-- has no critical capture, so 14 is 0. The camera zoom of the effect is the
-- player's `screenTransform`, offered to Gen4Battle.pushMoveCamera.

local P = require("src.battle.Gen5MoveAnimPlayer")

local M = {}
M.__index = M

M.EFFECT = 570          -- the capture
M.FRAME_CAP = 1200

-- wants(battle) -> true on a Black / White cache that carries effect 570
function M.wants(battle)
  local data = battle and (battle.data or (battle.game and battle.game.data))
  local rec = data and data.gen5_move_anims
  return rec ~= nil and rec.programs ~= nil and rec.programs[M.EFFECT] ~= nil
end

-- new(opts) -> anim, or nil (the caller keeps Gen4BallAnim)
--   battle, itemId, caught, shakes, critical, targetPosition
function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local battle = opts.battle
  if (opts.mode or "catch") ~= "catch" or not M.wants(battle) then return nil end
  local data = battle.data or battle.game.data
  local player = P.new(data)
  if not player then return nil end
  player.quiet = false
  player.battleRef = battle
  player.ballId = P.ballIdFor(opts.itemId)
  local shakes = math.max(0, math.min(3, math.floor(tonumber(opts.shakes) or 0)))
  player.presetVars = { [12] = shakes, [13] = opts.caught and 1 or 0, [14] = opts.critical and 1 or 0 }
  local okL, L = pcall(require, "src.battle.Gen5BattleLayout")
  local rule = okL and L.rule(battle) or "single"
  if rule == "double" then
    -- the thrower stands on the player's left; the ball flies at the foe
    player:setLayout("double", 0, tonumber(opts.targetPosition) or 1)
  end
  -- the effect's sounds and the defender's cry
  player.onSound = function(event)
    local okS, Sound = pcall(require, "src.core.Sound")
    if not (okS and Sound and type(event) == "table") then return end
    if event.kind == "cry" then
      local foe = battle.enemy
      local species = foe and foe.mon and foe.mon.species
      if species and Sound.playCry then pcall(Sound.playCry, data, species) end
    elseif event.kind == "play" and event.id and Sound.playId then
      pcall(Sound.playId, data, event.id)
    end
  end
  local self = setmetatable({
    battle = battle, player = player, gen5 = true,
    ball = opts.ball or "poke_ball",
    caught = opts.caught and true or false,
    shakes = shakes, side = "enemy", mode = "catch",
    t = 0, done = false, visible = true, cell = 0, angle = 0,
    x = 192, y = 48,
  }, M)
  local total = player:duration(M.EFFECT, true)
  if total <= 0 then return nil end
  self.total = math.min(total, M.FRAME_CAP)
  self:locate()
  return self
end

function M:estimate() return self.total end
function M:isDone() return self.done end

-- where the ball is on the port's screen (for the absorb's centre)
function M:locate()
  local p = self.player
  local okA, A = pcall(p.anchors, p, self.battle)
  if not okA then return end
  local o = p.objs and p.objs[0]
  if o then
    self.x, self.y = p:objectAt(o, A)
    return
  end
  for _, e in ipairs(p.emitters or {}) do
    if not e.done and e.pos then
      self.x, self.y = p:worldToScreen(A, e.pos)
      return
    end
  end
end

function M:update()
  if self.done then return end
  self.t = self.t + 1
  pcall(self.player.update, self.player)
  self:locate()
  if self.t >= self.total then self.done = true end
end

local function defender(self)
  local st = self.player.state
  return st and st[false]
end

function M:hidesMon(isPlayer)
  if isPlayer then return false end
  local s = defender(self)
  return s ~= nil and s.hidden == true
end

function M:absorbFor(isPlayer)
  if isPlayer then return nil end
  local s = defender(self)
  if not s then return nil end
  local k = math.min(s.sx or 1, s.sy or 1)
  if k >= 1 then return nil end
  return math.max(0, k), 0
end

function M:screenTransform(battle)
  if self.done then return nil end
  local ok, k, tx, ty = pcall(self.player.screenTransform, self.player, battle or self.battle)
  if ok and k then return k, tx, ty end
  return nil
end

-- draw(battle) -> true: the throw's particles (under the effect's zoom) and
-- the ball OBJs
function M:draw(battle)
  local p = self.player
  local g = love.graphics
  local k, tx, ty = self:screenTransform(battle)
  if k then g.push(); g.translate(tx, ty); g.scale(k) end
  local okP = pcall(p.drawParticles, p, battle)
  if k then g.pop() end
  local data = battle.data or (battle.game and battle.game.data)
  pcall(p.drawObjects, p, battle, data, k and { k, tx, ty } or nil)
  return okP
end

return M
