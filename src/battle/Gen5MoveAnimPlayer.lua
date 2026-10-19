-- BLACK AND WHITE MOVE ANIMATIONS: the cartridge's effect VM (btlv_effvm.c in
-- overlay 94), played over this port's battle screen.
--
-- The programs come from `gen5_move_anims` (src/import/Gen5MoveAnimData.lua),
-- the particles from `gen5_particles` -- SPA files in Platinum's own format, so
-- `Gen4ParticleSystem` simulates them unchanged. What is new is the VM and the
-- world it runs in: BW's battle is a real 3D scene, every emitter and every
-- Pokemon (an MCSS polygon) has a position in WORLD units under a perspective
-- camera that the script moves. The operand semantics are the research in
-- G:/Gen2Recomped/scratch_claude/bwanim/ (FINDINGS2.txt, bwanim_semantics.lua),
-- read off the handlers; every number below that is the cartridge's is named
-- there with its address.
--
-- THE SHAPE IS Gen4MoveAnimPlayer's ON PURPOSE. BattleState and Gen4Battle
-- already ask a Sinnoh player for monOffset / monAffine / monRotate / monTint /
-- monSpecial / monHidden / groupTint / particles, and BW battles ride Gen4's
-- screen; so this player answers the same questions and sits in the same slot
-- (`battle.gen4Anim`), and the screen needs only two extra hooks: particles
-- drawn by projection (`drawParticles`) and the effect background (`drawEffectLayer`),
-- plus the camera (`screenTransform`).
--
-- WHERE THE CARTRIDGE'S WORLD MEETS THIS PORT'S SCREEN. The port's BW field is
-- drawn by src/render/Gen5BattleSceneView.lua under a camera set by eye, with
-- the Pokemon as billboards at its own two stand points; the cartridge's
-- camera (pos (6.7, 6.7, 17.3) looking at (0, 2.6, 0), fovy 26, aspect 1.35)
-- puts the player's Pokemon mostly under the touch menu. So effects are
-- projected through the CARTRIDGE's camera and its MCSS home positions, and
-- then carried onto the port's screen by a map that is exact at the two
-- battlers: at each battler a ROM pixel becomes `s` port pixels, where `s` is
-- the ratio of the two screens' sprite scales there, and between them the two
-- local maps are blended along the attacker-defender line. A flame on the
-- defender lands on the defender at the defender's size; a projectile flies
-- from one Pokemon to the other.
--
-- THE CAMERA's moves are drawn as a zoom of the field: the screen point under
-- the camera's target is carried to where the moved camera puts it, scaled by
-- the change in pixels-per-unit there. That keeps the zoom-to-the-defender
-- every damaging move opens with, and the shakes, without re-rendering the
-- by-eye field from the cartridge's camera; the parallax of a real 3D camera
-- move is the part that is approximated.

local Gen4ParticleSystem = require("src.battle.Gen4ParticleSystem")

local M = {}
local Player = {}
Player.__index = Player

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt
local sin, cos, pi = math.sin, math.cos, math.pi
local FX = 4096

Player.FRAME_BUDGET = 900

-- btlv_camera.c
M.CAMERA = {
  fovy = math.rad(26), aspect = 1.35, near = 1, far = 512,
  pos = { 6.7, 6.7, 17.3 }, target = { 0.0, 2.6, 0.0 },
}
M.VIEWS = {
  [0] = { pos = { 5.791, 5.950, 19.798 }, target = { -0.909, 1.850, 2.498 } },
  [1] = { pos = { 6.599, 6.950, 6.905 }, target = { -0.101, 2.850, -10.396 } },
  [18] = { pos = { 9.7, 6.7, 17.3 }, target = { 3.0, 2.6, 0.0 } },
  [19] = { pos = { 6.7, 7.7, 30.8 }, target = { 0.0, 3.6, 13.5 } },
}
-- MCSS home positions, singles (0x0220A050); slot 0 is the player's
M.HOME = { [0] = { 0.5, 0.4, 7.0 }, [1] = { 0.3, 0.4, -10.0 } }
-- a double's slots 2..5 and the rest (src/battle/Gen5BattleLayout.lua)
local Layout = require("src.battle.Gen5BattleLayout")
-- the doubles views 2..5 (0x0220AD78 / 0x0220ADA8) and the wide view 14
M.VIEWS_DOUBLE = {
  [2] = { pos = { 2.7, 5.2, 17.3 }, target = { -4.0, 1.1, 0.0 } },
  [3] = { pos = { 8.599, 6.950, 6.905 }, target = { 2.101, 2.850, -10.396 } },
  [4] = { pos = { 6.7, 5.2, 17.3 }, target = { 0.0, 1.1, 0.0 } },
  [5] = { pos = { 4.599, 6.950, 6.905 }, target = { -2.101, 2.850, -10.396 } },
  [14] = { pos = { 8.7, 7.7, 23.8 }, target = { 2.0, 3.6, 6.5 } },
}
M.EMITTER_Z = 0.3125   -- added to an emitter's origin and target z
M.LCD_W, M.LCD_H = 256, 192
-- the ortho particle system of the SCREEN ops: x -4..4, y -3..3
M.SCREEN_UNITS = 32

-- ---------------------------------------------------------------------------
-- small vector / projection helpers
-- ---------------------------------------------------------------------------

local function copy3(v) return { v[1], v[2], v[3] } end

local function lookAt(eye, target)
  local fx, fy, fz = target[1] - eye[1], target[2] - eye[2], target[3] - eye[3]
  local fl = sqrt(fx * fx + fy * fy + fz * fz); if fl < 1e-6 then fl = 1 end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  -- side = f x up(0,1,0)
  local sx, sy, sz = -fz, 0, fx
  local sl = sqrt(sx * sx + sz * sz); if sl < 1e-6 then sx, sl = 1, 1 end
  sx, sz = sx / sl, sz / sl
  local ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
  return { sx = sx, sy = sy, sz = sz, ux = ux, uy = uy, uz = uz, fx = fx, fy = fy, fz = fz,
           ex = eye[1], ey = eye[2], ez = eye[3] }
end

-- project(cam, p) -> screen x, y, depth (DS pixels of the cartridge's view)
function M.project(cam, p)
  local v = cam.view
  local dx, dy, dz = p[1] - v.ex, p[2] - v.ey, p[3] - v.ez
  local x = dx * v.sx + dy * v.sy + dz * v.sz
  local y = dx * v.ux + dy * v.uy + dz * v.uz
  local d = dx * v.fx + dy * v.fy + dz * v.fz
  if d < 0.05 then d = 0.05 end
  local f = 1 / math.tan(M.CAMERA.fovy / 2)
  local nx = x * f / M.CAMERA.aspect / d
  local ny = y * f / d
  return (nx + 1) * 0.5 * M.LCD_W, (1 - ny) * 0.5 * M.LCD_H, d
end

-- pixels one world unit covers at depth d
function M.pixelsPerUnit(d)
  local f = 1 / math.tan(M.CAMERA.fovy / 2)
  return 0.5 * M.LCD_H * f / max(0.05, d)
end

local function camera(pos, target)
  return { pos = pos, target = target, view = lookAt(pos, target) }
end

M.DEFAULT_CAM = camera(M.CAMERA.pos, M.CAMERA.target)

-- ---------------------------------------------------------------------------
-- The generic stepper (0x021F9260): camera shake, every MCSS task, BG scroll
-- ---------------------------------------------------------------------------

local Stepper = {}
Stepper.__index = Stepper

-- kind: 0 set, 1/4 linear to dest, 2 swing out and back, 3 swing both ways
function M.stepper(kind, start, dest, frames, wait, count, mirror)
  local s = setmetatable({ kind = kind, start = {}, value = {}, dest = {}, speed = {},
    frames = max(1, frames or 1), wait = max(0, wait or 0), count = max(1, count or 1) }, Stepper)
  s.reload, s.waitReload = s.frames, s.wait
  s.wait = 0
  for i = 1, #start do
    s.start[i], s.value[i] = start[i], start[i]
    local d = dest[i] or 0
    if kind == 1 or kind == 4 then
      s.dest[i] = d
      s.speed[i] = (d - start[i]) / s.frames
    elseif kind == 2 or kind == 3 then
      s.speed[i] = d / s.frames
    else
      s.dest[i] = d
      s.speed[i] = 0
    end
    if mirror and mirror[i] then s.speed[i] = -s.speed[i] end
  end
  if kind == 2 then s.count = s.count * 2 elseif kind == 3 then s.count = s.count * 4 end
  return s
end

-- tick() -> true while busy
function Stepper:tick()
  if self.done then return false end
  if self.wait > 0 then self.wait = self.wait - 1; return true end
  self.wait = self.waitReload
  local k = self.kind
  if k == 1 or k == 4 then
    local all = true
    for i = 1, #self.value do
      local v, d, sp = self.value[i] + self.speed[i], self.dest[i], self.speed[i]
      -- reached, overshot, or (rounding) no longer moving toward it
      if (sp >= 0 and v >= d) or (sp < 0 and v <= d) or abs(d - v) < 1e-6 or abs(sp) < 1e-9 then
        v = d
      else
        all = false
      end
      self.value[i] = v
    end
    if all then self.done = true end
  elseif k == 2 or k == 3 then
    for i = 1, #self.value do self.value[i] = self.value[i] + self.speed[i] end
    self.frames = self.frames - 1
    if self.frames <= 0 then
      self.count = self.count - 1
      self.frames = self.reload
      if k == 2 or (self.count % 2 == 1) then
        for i = 1, #self.speed do self.speed[i] = -self.speed[i] end
      end
    end
    if self.count <= 0 then
      for i = 1, #self.value do self.value[i] = self.start[i] end
      self.done = true
    end
  else
    for i = 1, #self.value do self.value[i] = self.dest[i] end
    self.done = true
  end
  return not self.done
end

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------

function M.new(data)
  local rec = data and data.gen5_move_anims
  if not (rec and rec.programs) then return nil end
  local self = setmetatable({}, Player)
  self.programs = rec.programs
  self.backgrounds = rec.backgrounds or {}
  local fx = (data and data.gen5_particles) or rec.particles
  self.effects = fx and fx.effects or {}
  self.unsupported = {}
  self.playing = false
  self.state = { [true] = {}, [false] = {} }
  self.gen5 = true
  return self
end

function Player:note(what)
  self.unsupported[what] = (self.unsupported[what] or 0) + 1
end

function Player:missing()
  local out = {}
  for what, n in pairs(self.unsupported) do out[#out + 1] = { what = what, count = n } end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.what < b.what
  end)
  return out
end

local function freshState(isPlayer, slot, rule)
  slot = slot or (isPlayer and 0 or 1)
  return {
    slot = slot, pos = copy3(Layout.home(rule, slot)), offset = { 0, 0, 0 },
    sx = 1, sy = 1, rot = 0, alpha = 31, mosaic = 0, evy = 0, colour = 0,
    hidden = false, tasks = {},
  }
end

-- setLayout(rule, attackerPos, targetPos): a double's BattleState positions
-- (0..3) for the next start(), so the attacker and the defender stand on
-- their own MCSS slots (p + 2) rather than on the singles pair. Kept until
-- the next call; any other rule clears it.
function Player:setLayout(rule, attackerPos, targetPos)
  if rule ~= "double" or attackerPos == nil then self.pendingLayout = nil; return end
  local a = (tonumber(attackerPos) or 0) + 2
  local d = targetPos ~= nil and (tonumber(targetPos) or 0) + 2 or nil
  -- the defender must stand on the other side for the side-keyed channels; a
  -- move at the partner (or with no target) faces the foe's left flank
  if d == nil or d % 2 == a % 2 then d = (a % 2 == 0) and 3 or 2 end
  self.pendingLayout = { rule = rule, attacker = a, defender = d }
end

function Player:reset()
  local L = self.layout
  if L then
    local atk = self.attackerIsPlayer and true or false
    self.state = { [atk] = freshState(atk, L.attacker, L.rule),
                   [not atk] = freshState(not atk, L.defender, L.rule) }
  else
    self.state = { [true] = freshState(true), [false] = freshState(false) }
  end
  self.cam = camera(copy3(M.CAMERA.pos), copy3(M.CAMERA.target))
  self.camTask, self.shakeTask = nil, nil
  self.shake = { 0, 0, 0 }
  self.savedCam = nil
  self.emitters = {}
  self.slots = {}
  self.vars = {}
  self.typeSource, self.gaugesHidden = nil, false
  for k, v in pairs(self.presetVars or {}) do self.vars[k] = v end
  self.objs = {}
  self.work = 0
  self.waitFrames = 0
  self.waitKind = nil
  self.yield = 1
  self.stack = {}
  self.fades = {}
  self.bg = nil
  self.fieldHidden, self.platformsHidden = false, false
  self.sounds = {}
  self.frame = 0
end

-- start(effectId, attackerIsPlayer) -> true when a program was found
function Player:start(effectId, attackerIsPlayer)
  local id = tonumber(effectId)
  local prog = id and self.programs[id]
  if not prog then self.playing = false; return false end
  self.moveId = id
  self.attackerIsPlayer = attackerIsPlayer and true or false
  -- the layout setLayout() last named (BattleState names one before every
  -- move: nil in a single)
  self.layout = self.pendingLayout
  self:reset()
  self.code, self.to = prog.code, prog.to
  self.pc = (prog.seq and prog.seq[0]) or 1
  self.playing = true
  self.unsupported = self.unsupported or {}
  return true
end

-- duration() runs the program to measure it, then starts it again
function Player:duration(effectId, attackerIsPlayer)
  if not self:start(effectId, attackerIsPlayer) then return 0 end
  self.quiet = true
  local frames = 0
  while self:update() do
    frames = frames + 1
    if frames > Player.FRAME_BUDGET then break end
  end
  local saved = self.unsupported
  self:start(effectId, attackerIsPlayer)
  self.unsupported = saved
  self.quiet = false
  return frames
end

-- ---------------------------------------------------------------------------
-- who is where
-- ---------------------------------------------------------------------------

-- side(true = player's) for a single-position code; nil when nobody is there
function Player:sideOf(code)
  code = tonumber(code) or 0
  if code == 14 then return self.attackerIsPlayer end
  if code == 16 then return not self.attackerIsPlayer end
  if code == 0 then return true end
  if code == 1 then return false end
  -- a double's slots 2..7: whoever of the two stands there
  if code >= 2 and code <= 7 and self.layout then
    for _, side in ipairs({ true, false }) do
      local s = self.state[side]
      if s and s.slot == code then return side end
    end
  end
  return nil   -- partners, the other doubles slots, the trainer slots
end

-- the battlers an MCSS-family code names
function Player:targets(code)
  code = tonumber(code) or 0
  if code == 18 then return { true, false } end
  local s = self:sideOf(code)
  if s == nil then return {} end
  return { s }
end

function Player:homeOf(side)
  local s = self.state and self.state[side and true or false]
  if s and s.slot and s.slot > 1 and self.layout then return Layout.home(self.layout.rule, s.slot) end
  return M.HOME[side and 0 or 1]
end

-- emitter position codes (0x021FD1CC)
function Player:emitterPoint(code, explicit)
  code = tonumber(code) or 8
  local side, flip
  if code == 8 then return explicit and copy3(explicit) or nil, false end
  if code == 9 then side = self.attackerIsPlayer
  elseif code == 10 then side, flip = self.attackerIsPlayer, true
  elseif code == 11 then side = not self.attackerIsPlayer
  elseif code == 12 then side, flip = not self.attackerIsPlayer, true
  elseif code == 0 then side = true
  elseif code == 1 then side = false
  elseif code >= 2 and code <= 7 and self.layout then
    -- a double's slot by number, standing or not
    return copy3(Layout.home(self.layout.rule, code)), false
  else return nil, false end
  return copy3(self:homeOf(side)), flip
end

-- ---------------------------------------------------------------------------
-- the VM
-- ---------------------------------------------------------------------------

local function fxv(v) return (tonumber(v) or 0) / FX end

function Player:var(id)
  id = tonumber(id) or 0
  if id == 16 then return self.work or 0 end
  if id == 17 then return self.attackerIsPlayer and 0 or 1 end
  if id == 19 then return self.attackerIsPlayer and 0 or 1 end
  if id == 39 then return 0 end   -- battle rule: singles
  return self.vars[id] or 0
end

local function compare(a, cmp, b)
  if cmp == 0 then return a == b end
  if cmp == 1 then return a ~= b end
  if cmp == 2 then return a < b end
  if cmp == 3 then return a > b end
  if cmp == 4 then return a <= b end
  if cmp == 5 then return a >= b end
  return false
end

-- busy(kind) -> is WAIT_FOR `kind` still waiting (0x021FC744)
function Player:busy(kind)
  kind = tonumber(kind) or 0
  local function camera() return self.camTask ~= nil or self.shakeTask ~= nil end
  local function mcss()
    for _, side in ipairs({ true, false }) do
      for _, t in pairs(self.state[side].tasks) do if t then return true end end
    end
    return false
  end
  local function particles()
    for _, e in ipairs(self.emitters) do if not e.done then return true end end
    return false
  end
  local function bg() return self.bgTask ~= nil end
  local function fades(which)
    for k, f in pairs(self.fades) do
      if f.task and (which == nil or which[k]) then return true end
    end
    return false
  end
  local function objs()
    for _, o in pairs(self.objs or {}) do if next(o.tasks) then return true end end
    return false
  end
  if kind == 0 then return camera() or mcss() or particles() or bg() or fades(nil) or objs() end
  if kind == 1 then return camera() end
  if kind == 2 then return particles() end
  if kind == 3 or kind == 4 then return mcss() end
  if kind == 5 then return bg() end
  if kind == 6 then return fades({ [0] = true }) end
  if kind == 7 then return fades({ [1] = true }) end
  if kind == 8 then return fades({ [0] = true, [1] = true, [2] = true }) end
  if kind == 9 then return fades({ [3] = true }) end
  return false   -- sound and cries are not tracked; never hold the battle on them
end

function Player:jump(i)
  local target = self.to and self.to[i]
  if target then self.pc = target end
end

function Player:enter(effectId)
  local prog = self.programs[tonumber(effectId) or -1]
  if not prog then self:note("effect " .. tostring(effectId)); return false end
  self.code, self.to = prog.code, prog.to
  self.pc = (prog.seq and prog.seq[0]) or 1
  return true
end

-- one instruction; returns "stop" when the script ended
function Player:exec()
  local i = self.pc
  local ins = self.code and self.code[i]
  if not ins then return "stop" end
  self.pc = i + 1
  local op = ins[1]
  local a = function(k) return ins[k + 1] or 0 end
  local h = Player.OPS[op]
  if h then return h(self, a, i, ins) end
  self:note("op" .. tostring(op))
end

function Player:update()
  if self.playing then
    self.frame = self.frame + 1
    -- the script: run until something waits, one command per frame unless
    -- SET_YIELD 0 says to keep going
    local guard = 0
    while self.playing do
      if self.waitFrames > 0 then self.waitFrames = self.waitFrames - 1; break end
      if self.waitKind ~= nil then
        if self:busy(self.waitKind) then break end
        self.waitKind = nil
      end
      local r = self:exec()
      if r == "stop" then self.playing = false; break end
      guard = guard + 1
      if guard > 4000 then self.playing = false; break end
      if self.yield ~= 0 and self.waitFrames == 0 and self.waitKind == nil then break end
    end
    if self.frame > Player.FRAME_BUDGET then self.playing = false end
  end
  self:stepTasks()
  return self:alive()
end

function Player:alive()
  if self.playing then return true end
  for _, e in ipairs(self.emitters or {}) do if not e.done then return true end end
  return false
end

-- ---------------------------------------------------------------------------
-- the tasks
-- ---------------------------------------------------------------------------

function Player:stepTasks()
  -- the OBJs: their move / scale / fade tasks and their cell animation
  for _, o in pairs(self.objs or {}) do
    for k, t in pairs(o.tasks) do
      if t.stepper then
        local live = t.stepper:tick()
        t.apply(t.stepper)
        if not live then o.tasks[k] = nil end
      elseif not t.tick() then o.tasks[k] = nil end
    end
    o.seqT = (o.seqT or 0) + 1
  end
  -- camera move
  local ct = self.camTask
  if ct then
    local busy = ct.stepper:tick()
    if ct.brake and ct.brake > 0 and not ct.braked then
      ct.steps = (ct.steps or 0) + 1
      if ct.steps >= ct.brake then
        ct.braked = true
        for k = 1, #ct.stepper.speed do ct.stepper.speed[k] = ct.stepper.speed[k] / 2 end
      end
    end
    local v = ct.stepper.value
    if ct.orbit then
      self.cam = camera(M.orbitPos(ct.orbit.target, ct.orbit.d, v[1], v[2]), copy3(ct.orbit.target))
    else
      self.cam = camera({ v[1], v[2], v[3] }, { v[4], v[5], v[6] })
    end
    if not busy then self.camTask = nil end
  end
  local st = self.shakeTask
  if st then
    local busy = st.stepper:tick()
    self.shake = { 0, 0, 0 }
    self.shake[st.axis] = st.stepper.value[1]
    if not busy then self.shakeTask = nil; self.shake = { 0, 0, 0 } end
  end
  -- MCSS
  for _, side in ipairs({ true, false }) do
    local s = self.state[side]
    for attr, t in pairs(s.tasks) do
      if t then
        local busy = t:tick()
        if t.apply then t.apply(s, t) end
        if not busy then s.tasks[attr] = false end
      end
    end
  end
  -- BG scroll
  local bt = self.bgTask
  if bt then
    local busy
    if bt.velocity then
      bt.frames = bt.frames - 1
      self.bgScroll[1] = self.bgScroll[1] + bt.velocity[1]
      self.bgScroll[2] = self.bgScroll[2] + bt.velocity[2]
      busy = bt.frames > 0
    else
      busy = bt.stepper:tick()
      self.bgScroll[1], self.bgScroll[2] = bt.stepper.value[1], bt.stepper.value[2]
    end
    if not busy then self.bgTask = nil end
  end
  -- scene fades
  for _, f in pairs(self.fades) do
    local t = f.task
    if t then
      if t.wait > 0 then t.wait = t.wait - 1
      else
        t.wait = t.waitReload
        local step = t.perFrame or 1
        if f.evy < t.to then f.evy = min(t.to, f.evy + step)
        elseif f.evy > t.to then f.evy = max(t.to, f.evy - step) end
        if f.evy == t.to then f.task = nil end
      end
    end
  end
  -- particles
  for _, e in ipairs(self.emitters) do
    if not e.done then self:stepEmitter(e) end
  end
  -- delayed sounds
  local keep = {}
  for _, snd in ipairs(self.sounds) do
    snd.delay = snd.delay - 1
    if snd.delay <= 0 then self:sound(snd.event) else keep[#keep + 1] = snd end
  end
  self.sounds = keep
end

function Player:sound(event)
  if self.quiet or not self.onSound then return end
  pcall(self.onSound, event)
end

-- ---------------------------------------------------------------------------
-- MCSS (the Pokemon)
-- ---------------------------------------------------------------------------

-- a new task on the same battler and attribute replaces the older one
local function setTask(s, attr, stepper, apply)
  stepper.apply = apply
  s.tasks[attr] = stepper
  if apply then apply(s, stepper) end
end

local function evyFade(s, from, to, wait, colour)
  local t = { from = from, to = to, colour = colour }
  if wait < 0 then t.perFrame, t.waitReload = abs(wait) + 1, 0
  else t.perFrame, t.waitReload = 1, wait end
  t.wait = 0
  s.evy, s.colour = from, colour
  t.tick = function(self_)
    if self_.wait > 0 then self_.wait = self_.wait - 1; return true end
    self_.wait = self_.waitReload
    if s.evy < self_.to then s.evy = min(self_.to, s.evy + self_.perFrame)
    elseif s.evy > self_.to then s.evy = max(self_.to, s.evy - self_.perFrame) end
    return s.evy ~= self_.to
  end
  return t
end

Player.OPS = {}
local OPS = Player.OPS

-- 0 CAMERA_MOVE(type, camPosCode, frames, wait, brake)
OPS[0] = function(self, a)
  local code = a(2)
  local view
  if code == 8 or code == 17 then view = M.CAMERA
  elseif code == 0 or code == 1 then view = M.VIEWS[code]
  elseif code == 9 or code == 10 or code == 21 then view = M.VIEWS[self.attackerIsPlayer and 0 or 1]
  elseif code == 11 or code == 12 then view = M.VIEWS[self.attackerIsPlayer and 1 or 0]
  elseif code == 13 then view = self.savedCam
  elseif code == 18 or code == 19 then view = M.VIEWS[code]
  else view = nil end   -- 14/15/16/20: no move in singles
  -- A DOUBLE looks at the slots' own views (0x021F9AB8): 2..5 by number,
  -- the attacker's / defender's slot, the wide view 14 for 14 and 20, and
  -- 21 the attacker's slot only when the attacker is a foe
  local L = self.layout
  if L and L.rule == "double" then
    local slotView = function(p) return M.VIEWS_DOUBLE[p] end
    local atk, def = self.state[self.attackerIsPlayer] or {}, self.state[not self.attackerIsPlayer] or {}
    if code >= 2 and code <= 5 then view = slotView(code)
    elseif code == 9 or code == 10 then view = slotView(atk.slot)
    elseif code == 11 or code == 12 then view = slotView(def.slot)
    elseif code == 14 or code == 20 then view = M.VIEWS_DOUBLE[14]
    elseif code == 21 then view = (atk.slot or 0) % 2 == 1 and slotView(atk.slot) or M.VIEWS_DOUBLE[14]
    end
  end
  if not view then return end   -- 15/16 (the side views): not read yet
  if not view then return end
  self:moveCamera(a(1), view.pos, view.target, a(3), a(4), a(5))
end

function Player:moveCamera(kind, pos, target, frames, wait, brake)
  local start = { self.cam.pos[1], self.cam.pos[2], self.cam.pos[3],
                  self.cam.target[1], self.cam.target[2], self.cam.target[3] }
  local dest = { pos[1], pos[2], pos[3], target[1], target[2], target[3] }
  if kind == 0 or (tonumber(frames) or 0) <= 0 then
    self.cam = camera(copy3(pos), copy3(target))
    self.camTask = nil
    return
  end
  self.camTask = { stepper = M.stepper(1, start, dest, frames, wait, 1), brake = brake }
end

-- 1 CAMERA_MOVE_COORD(mode 0 snap / 1 abs / 2 relative, pos xyz, target xyz, frames, wait, brake)
OPS[1] = function(self, a)
  local mode = a(1)
  local pos = { fxv(a(2)), fxv(a(3)), fxv(a(4)) }
  local tgt = { fxv(a(5)), fxv(a(6)), fxv(a(7)) }
  if mode == 2 then
    for k = 1, 3 do pos[k] = pos[k] + self.cam.pos[k]; tgt[k] = tgt[k] + self.cam.target[k] end
  end
  self:moveCamera(mode == 0 and 0 or 1, pos, tgt, a(8), a(9), a(10))
end

-- 2 CAMERA_ORBIT(mode 0 snap / else move, dPitch, dYaw, frames, wait, brake):
-- the camera's spherical angles about its target are added to, its distance
-- kept (0x021F7108: pos = target + d (cos p cos y, sin p, cos p sin y));
-- angles in 65536ths of a turn. The move steps the ANGLES, so the camera
-- swings round the target rather than cutting across.
local function sphere(pos, tgt)
  local dx, dy, dz = pos[1] - tgt[1], pos[2] - tgt[2], pos[3] - tgt[3]
  local d = sqrt(dx * dx + dy * dy + dz * dz)
  if d < 1e-6 then return 0, 0, 0 end
  return d, math.asin(max(-1, min(1, dy / d))), math.atan2(dz, dx)
end
function M.orbitPos(tgt, d, p, y)
  return { tgt[1] + d * cos(p) * cos(y), tgt[2] + d * sin(p), tgt[3] + d * cos(p) * sin(y) }
end
OPS[2] = function(self, a)
  local tgt = copy3(self.cam.target)
  local d, p0, y0 = sphere(self.cam.pos, tgt)
  if d == 0 then return end
  local turn = 2 * pi / 65536
  local p1, y1 = p0 + a(2) * turn, y0 + a(3) * turn
  if a(1) == 0 or a(4) <= 0 then
    self.cam = camera(M.orbitPos(tgt, d, p1, y1), tgt)
    self.camTask = nil
    return
  end
  self.camTask = { stepper = M.stepper(1, { p0, y0 }, { p1, y1 }, a(4), a(5), 1), brake = a(6),
                   orbit = { target = tgt, d = d } }
end

-- 3 CAMERA_SHAKE(axis 1 = x / else y, amplitude fx, unused, framesPerSwing, wait, cycles)
OPS[3] = function(self, a)
  self.shakeTask = { axis = (a(1) == 1) and 1 or 2,
    stepper = M.stepper(3, { 0 }, { fxv(a(2)) }, a(4), a(5), a(6)) }
end

OPS[4] = function() end   -- MCSS projection mode; no visible effect here
OPS[5] = function(self) self.savedCam = { pos = copy3(self.cam.pos), target = copy3(self.cam.target) } end

-- 6 PARTICLE_LOAD(spa)
-- The ids PARTICLE_LOAD remaps (0x021FE38C): 46-49 by the BALL -- 4 files a
-- ball, (ball - 1) * 4 on -- and 3 / 29 by a 0..24 value of the battler op68
-- names (a type; not modelled, they load as named). The slot keeps the id
-- the program wrote, which is the id its emitters name.
function M.remapParticle(id, ballId, typeSource)
  id = tonumber(id) or 0
  local b = tonumber(ballId) or 4
  if b < 1 or b > 25 then b = 4 end
  if id >= 46 and id <= 49 then
    return id + (b - 1) * 4
  end
  -- 3 / 29 read the same value when no battler was named (op68 unset or 8:
  -- the item, i.e. the ball): 3 + v, and 29 + v folded (v + 1 = 25 -> 16,
  -- v + 1 >= 16 -> 3)
  if (id == 3 or id == 29) and (typeSource == nil or typeSource == 8) and ballId then
    local v = b - 1
    if id == 3 then return 3 + v end
    if v + 1 == 25 then v = 16 elseif v + 1 >= 16 then v = 3 end
    return 29 + v
  end
  return id
end

-- the item id of a ball -> its ball id (1..25): 1..16 are their own items,
-- the Apricorn balls 492..500 are 17..25 (Gen 4's numbering) and BW's Dream
-- Ball (576) is 25; anything else throws as a Poke Ball (4)
function M.ballIdFor(itemId)
  local n = tonumber(itemId)
  if not n then return 4 end
  if n >= 1 and n <= 16 then return n end
  if n >= 492 and n <= 499 then return n - 475 end
  if n == 576 or n == 500 then return 25 end
  return 4
end

OPS[6] = function(self, a)
  local id = a(1)
  local entry = self.effects["spa_" .. tostring(M.remapParticle(id, self.ballId, self.typeSource))]
  if not entry then self:note("spa " .. tostring(id)) end
  self.slots[id] = entry or false
end

-- the emitter commands
OPS[7] = function(self, a)
  self:createEmitter({ spa = a(1), index = a(2), origin = a(3), target = a(4),
    yOffset = fxv(a(5)), scales = { a(8), a(9), a(10), a(11) } })
end
OPS[8] = function(self, a)
  self:createEmitter({ spa = a(1), index = a(2), origin = 8, target = 8,
    originXYZ = { fxv(a(3)), fxv(a(4)), fxv(a(5)) }, targetXYZ = { fxv(a(6)), fxv(a(7)), fxv(a(8)) },
    yOffset = fxv(a(9)), scales = { a(12), a(13), a(14), a(15) } })
end
OPS[9] = function(self, a)
  self:createEmitter({ spa = a(1), index = a(2), origin = a(3), target = a(4), screen = true,
    offset = { fxv(a(5)), fxv(a(6)), fxv(a(7)) }, scales = { a(8), a(9), a(10), a(11) } })
end
OPS[10] = function(self, a)
  local entry = self.slots[a(1)]
  local n = entry and entry.emitters and #entry.emitters or 0
  for k = 0, n - 1 do
    self:createEmitter({ spa = a(1), index = k, origin = a(2), target = a(3), screen = true,
      yOffset = fxv(a(4)), scales = { a(7), a(8), a(9), a(10) } })
  end
end
OPS[11] = function(self, a)
  for _, e in ipairs(self.emitters) do if e.spa == a(1) then e.stopEmit = true end end
end
local function moving(self, a, xyz, screen)
  local o = 0
  local spec = { spa = a(1), index = a(2), moveType = a(3), screen = screen }
  if xyz then
    spec.origin, spec.originXYZ = 8, { fxv(a(4)), fxv(a(5)), fxv(a(6)) }
    o = 2
  else
    spec.origin = a(4)
  end
  spec.target = a(5 + o)
  spec.yOffset = fxv(a(6 + o))
  spec.frames = max(1, fxv(a(7 + o)))
  spec.arc = fxv(a(8 + o))
  spec.scales = { FX, a(9 + o), FX, a(10 + o) }
  spec.waves = fxv(a(11 + o))
  self:createEmitter(spec)
end
OPS[12] = function(self, a) moving(self, a, false, false) end
OPS[13] = function(self, a) moving(self, a, true, false) end
OPS[14] = function(self, a) moving(self, a, false, true) end
OPS[15] = function(self, a) moving(self, a, true, true) end
-- 16 / 17 EMITTER_ORBIT(spa, idx, center, rx, rz, yOfs, framesPerRev, wait, ?, pause)
local function orbit(self, a, screen)
  local c = a(3)
  local centre
  if c == 0 or c == 1 then centre = copy3(self:homeOf(self.attackerIsPlayer))
  elseif c == 2 or c == 3 then centre = copy3(self:homeOf(not self.attackerIsPlayer))
  else centre = { 0, 0, 0 } end
  self:createEmitter({ spa = a(1), index = a(2), origin = 8, target = 8, originXYZ = centre,
    screen = screen, orbit = { centre = centre, rx = fxv(a(4)), rz = fxv(a(5)), y = fxv(a(6)),
      frames = max(1, a(7)), wait = max(0, a(8)), pause = max(0, a(10)),
      reverse = (c % 2) == 1, start = (centre[3] < 0) and 0.5 or 0 } })
end
OPS[16] = function(self, a) orbit(self, a, false) end
OPS[17] = function(self, a) orbit(self, a, true) end

-- 18 MCSS_MOVE(target, type, x, y, frames, wait, count)
OPS[18] = function(self, a)
  local kind, x, y = a(2), fxv(a(3)), fxv(a(4))
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local foe = s.slot % 2 == 1
    local home = self:homeOf(side)
    local apply = function(st, t) st.pos[1], st.pos[2] = t.value[1], t.value[2] end
    local start = { s.pos[1], s.pos[2] }
    if kind == 0 then s.pos[1], s.pos[2] = x, y
    elseif kind == 6 then s.pos[1], s.pos[2] = home[1], home[2]
    elseif kind == 1 then
      setTask(s, "pos", M.stepper(1, start, { s.pos[1] + (foe and -x or x), s.pos[2] + y }, a(5), a(6), 1), apply)
    elseif kind == 2 or kind == 3 then
      setTask(s, "pos", M.stepper(kind, start, { x, y }, a(5), a(6), a(7), { foe, false }), apply)
    elseif kind == 4 then
      setTask(s, "pos", M.stepper(1, start, { x, y }, a(5), a(6), 1), apply)
    elseif kind == 5 then
      setTask(s, "pos", M.stepper(1, start, { home[1], home[2] }, a(5), a(6), 1), apply)
    end
  end
end

-- 19 MCSS_ORBIT_OFFSET(target, flags, phase, radA, radB, framesPerRev fx, wait fx, revs fx, pause)
OPS[19] = function(self, a)
  local flags, phase0 = a(2), a(3)
  local ra, rb = fxv(a(4)), fxv(a(5))
  local per, wait, revs, pause = max(1, floor(fxv(a(6)))), max(0, floor(fxv(a(7)))), floor(fxv(a(8))), a(9)
  if revs <= 0 then return end
  local plane = floor(flags / 2) % 4
  local reverse = flags % 2 == 1
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local phase = phase0
    if s.slot % 2 == 1 and not ((plane == 0 or plane == 2) and phase >= 2) then
      phase = (phase % 2 == 0) and phase + 1 or phase - 1
    end
    local t = { step = 0, wait = 0, revs = revs, pausing = 0 }
    t.tick = function(tt)
      if tt.pausing > 0 then tt.pausing = tt.pausing - 1; return tt.revs > 0 or tt.pausing > 0 end
      if tt.wait > 0 then tt.wait = tt.wait - 1; return true end
      tt.wait = wait
      tt.step = tt.step + 1
      local ang = 2 * pi * tt.step / per * (reverse and -1 or 1)
      local c, sn = cos(ang), sin(ang)
      local u, v
      if phase == 0 then u, v = ra * (1 - c), rb * sn
      elseif phase == 1 then u, v = ra * (c - 1), -rb * sn
      elseif phase == 2 then u, v = -ra * sn, rb * (1 - c)
      else u, v = ra * sn, rb * (c - 1) end
      local o = { 0, 0, 0 }
      if plane == 0 then o[2], o[3] = u, v
      elseif plane == 1 then o[1], o[3] = u, v
      else o[1], o[2] = u, v end
      s.offset = o
      if tt.step >= per then
        tt.step = 0
        tt.revs = tt.revs - 1
        tt.pausing = pause
        if tt.revs <= 0 and pause <= 0 then return false end
      end
      return true
    end
    s.tasks.offset = t
  end
end

-- 20 MCSS_SINE_OFFSET(target, axis, startAngle fx, endAngle fx, amp fx, frames)
OPS[20] = function(self, a)
  local axis = (a(2) == 1) and 2 or 1
  local a0, a1 = fxv(a(3)) / 65536 * 2 * pi, fxv(a(4)) / 65536 * 2 * pi
  local amp, frames = fxv(a(5)), max(1, a(6))
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local t = { n = 0 }
    t.tick = function(tt)
      tt.n = tt.n + 1
      local ang = a0 + (a1 - a0) * min(1, tt.n / frames)
      s.offset = { 0, 0, 0 }
      s.offset[axis] = amp * sin(ang)
      return tt.n < frames
    end
    s.tasks.offset = t
  end
end

-- 21 MCSS_SCALE(target, type, sx fx, sy fx, frames, wait, count)
OPS[21] = function(self, a)
  local kind, sx, sy = a(2), fxv(a(3)), fxv(a(4))
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local apply = function(st, t) st.sx, st.sy = t.value[1], t.value[2] end
    local start = { s.sx, s.sy }
    if kind == 0 then s.sx, s.sy = sx, sy
    elseif kind == 2 or kind == 3 then setTask(s, "scale", M.stepper(kind, start, { sx, sy }, a(5), a(6), a(7)), apply)
    else setTask(s, "scale", M.stepper(1, start, { sx, sy }, a(5), a(6), 1), apply) end
  end
end

-- 22 MCSS_ROTATE(target, type, angle fx (65536.0 = 360deg), frames, wait, count)
OPS[22] = function(self, a)
  local kind, ang = a(2), fxv(a(3)) / 65536 * 2 * pi
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local foe = s.slot % 2 == 1
    local apply = function(st, t) st.rot = t.value[1] end
    if kind == 0 then s.rot = foe and -ang or ang
    elseif kind == 2 or kind == 3 then setTask(s, "rot", M.stepper(kind, { s.rot }, { ang }, a(4), a(5), a(6), { foe }), apply)
    else setTask(s, "rot", M.stepper(1, { s.rot }, { foe and -ang or ang }, a(4), a(5), 1), apply) end
  end
end

-- 23 MCSS_ALPHA / 24 MCSS_MOSAIC (target, type, value, frames, wait, count)
local function scalarTask(self, a, attr)
  local kind, v = a(2), a(3)
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local apply = function(st, t) st[attr] = t.value[1] end
    if kind == 0 then s[attr] = v
    elseif kind == 2 or kind == 3 then setTask(s, attr, M.stepper(kind, { s[attr] }, { v }, a(4), a(5), a(6)), apply)
    else setTask(s, attr, M.stepper(1, { s[attr] }, { v }, a(4), a(5), 1), apply) end
  end
end
OPS[23] = function(self, a) scalarTask(self, a, "alpha") end
OPS[24] = function(self, a) scalarTask(self, a, "mosaic") end
OPS[25] = function(self) self:note("MCSS op25") end
OPS[26] = function(self, a)  -- animation stop: the idle animation freezes on the hit
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local m = a(2)
    if m == 1 then s.stopA = true elseif m == 0 then s.stopA = false
    elseif m == 2 then s.stopB = true elseif m == 3 then s.stopB = false end
  end
end
-- 27 MCSS_PAL_FADE(target, startEvy, endEvy, wait, colour)
OPS[27] = function(self, a)
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    s.tasks.fade = evyFade(s, a(2), a(3), a(4), a(5))
  end
end
-- 28 MCSS_VANISH(target, 0 show / 1 hide / 2 toggle / 3 hide+remember / 4 restore)
OPS[28] = function(self, a)
  for _, side in ipairs(self:targets(a(1))) do
    local s = self.state[side]
    local m = a(2)
    if m == 0 then s.hidden = false
    elseif m == 1 then s.hidden = true
    elseif m == 2 then s.hidden = not s.hidden
    elseif m == 3 then s.remember = s.hidden; s.hidden = true
    elseif m == 4 then s.hidden = s.remember or false end
  end
end
OPS[29] = function() end   -- the shadow polygon: this port draws no shadow under a billboard
OPS[30] = function(self) self:note("MCSS op30") end
OPS[31] = function() end
OPS[32] = function(self) self:note("trainer op32") end
OPS[33] = function(self) self:note("trainer move") end
OPS[34] = function() end
OPS[35] = function() end

-- 36 BG_LOAD(nscr) onto BG3, hidden until SCENE_VANISH(2, 0)
OPS[36] = function(self, a)
  local id = a(1)
  self.bg = { id = id, art = self.backgrounds[id], shown = false }
  if not self.bg.art then self:note("bg " .. tostring(id)) end
  self.bgScroll = { 0, 0 }
end
-- 37 BG_SCROLL(type, dx, dy, frames, wait, count)
OPS[37] = function(self, a)
  self.bgScroll = self.bgScroll or { 0, 0 }
  local kind, dx, dy = a(1), a(2), a(3)
  if kind == 4 then
    if not self.attackerIsPlayer then dx = -dx end
    self.bgTask = { velocity = { dx, dy }, frames = max(1, a(4)) }
  elseif kind == 0 then
    self.bgScroll = { dx, dy }
  elseif kind == 1 then
    self.bgTask = { stepper = M.stepper(1, { self.bgScroll[1], self.bgScroll[2] },
      { self.bgScroll[1] + dx, self.bgScroll[2] + dy }, a(4), a(5), 1) }
  else
    self.bgTask = { stepper = M.stepper(kind, { self.bgScroll[1], self.bgScroll[2] }, { dx, dy }, a(4), a(5), a(6)) }
  end
end
OPS[38] = function() end
OPS[39] = function() end
OPS[40] = function() end
OPS[41] = function(self) self:note("blend op41") end
-- 42 SCENE_PAL_FADE(kind, startEvy, endEvy, wait, colour)
OPS[42] = function(self, a)
  local kind, wait = a(1), a(4)
  local f = { evy = a(2), colour = a(5) }
  f.task = { to = a(3), wait = 0, waitReload = (wait < 0) and 0 or wait,
             perFrame = (wait < 0) and (abs(wait) + 1) or 1 }
  if f.evy == f.task.to then f.task = nil end
  self.fades[kind] = f
end
-- 43 SCENE_VANISH(kind, hide)
OPS[43] = function(self, a)
  local kind, hide = a(1), a(2) == 1
  if kind == 2 then
    if self.bg then self.bg.shown = not hide end
  elseif kind == 1 then self.fieldHidden = hide
  else self.platformsHidden = hide end
end
OPS[44] = function(self) self:note("bg op44") end
-- THE OBJ COMMANDS (0x021FB6F4..0x021FB8F4, the CLACT unit at 0x02201AF8):
-- a 2D sprite created at a battler's projected spot, then moved, scaled,
-- animated and palette-faded in screen pixels. Only the ball OBJ's art is
-- imported (op 69 below); op 45's resource sets are noted and skipped.
-- An OBJ keeps its WORLD anchor and a pixel offset, so it rides the port's
-- map from the cartridge's screen like everything else.
OPS[45] = function(self) self:note("OBJ op45") end
-- 46 OBJ_MOVE(slot, type, dx, dy, frames, wait, count): the stepper's kinds
OPS[46] = function(self, a)
  local o = self.objs and self.objs[a(1)]
  if not o then return end
  local kind, x, y = a(2), a(3), a(4)
  local apply = function(t) o.dx, o.dy = t.value[1], t.value[2] end
  local start = { o.dx, o.dy }
  if kind == 0 then o.dx, o.dy = x, y; o.tasks.move = nil
  elseif kind == 2 or kind == 3 then
    o.tasks.move = { stepper = M.stepper(kind, start, { x, y }, a(5), a(6), a(7)), apply = apply }
  elseif kind == 4 then
    o.tasks.move = { stepper = M.stepper(1, start, { x, y }, a(5), a(6), 1), apply = apply }
  else
    o.tasks.move = { stepper = M.stepper(1, start, { o.dx + x, o.dy + y }, a(5), a(6), 1), apply = apply }
  end
end
-- 47 OBJ_SCALE(slot, type, sx fx, sy fx, frames, wait, count)
OPS[47] = function(self, a)
  local o = self.objs and self.objs[a(1)]
  if not o then return end
  local kind, sx, sy = a(2), fxv(a(3)), fxv(a(4))
  local apply = function(t) o.sx, o.sy = t.value[1], t.value[2] end
  if kind == 0 then o.sx, o.sy = sx, sy; o.tasks.scale = nil
  else
    local k = (kind == 2 or kind == 3) and kind or 1
    o.tasks.scale = { stepper = M.stepper(k, { o.sx, o.sy }, { sx, sy }, a(5), a(6), (k == 1) and 1 or a(7)), apply = apply }
  end
end
-- 48 OBJ_ANIM(slot, sequence)
OPS[48] = function(self, a)
  local o = self.objs and self.objs[a(1)]
  if o then o.seq, o.seqT = a(2), 0 end
end
-- 49 OBJ_PAL_FADE(slot, startEvy, endEvy, wait, colour)
OPS[49] = function(self, a)
  local o = self.objs and self.objs[a(1)]
  if not o then return end
  o.evy, o.colour = a(2), a(5)
  local to, wait = a(3), a(4)
  if o.evy == to then o.tasks.fade = nil; return end
  local f = { to = to, n = 0, waitReload = (wait < 0) and 0 or wait,
              per = (wait < 0) and (abs(wait) + 1) or 1 }
  o.tasks.fade = { tick = function()
    if f.n > 0 then f.n = f.n - 1; return true end
    f.n = f.waitReload
    if o.evy < f.to then o.evy = min(f.to, o.evy + f.per) else o.evy = max(f.to, o.evy - f.per) end
    return o.evy ~= f.to
  end }
end
-- 50 OBJ_DELETE(slot)
OPS[50] = function(self, a) if self.objs then self.objs[a(1)] = nil end end
-- 51 GAUGE_VANISH(show, ?): 0 hides the HP gauges (0x022079C0) -- the
-- capture hides them for the throw; Gen5BattleHud asks `gaugesHidden`
OPS[51] = function(self, a) self.gaugesHidden = (a(1) == 0) end
-- 52 SE_PLAY(seq, player, pan, delay, pitch, volume, ...)
OPS[52] = function(self, a)
  local event = { kind = "play", id = a(1), gen5 = true, pitch = a(5), volume = a(6) }
  local delay = a(4)
  if delay > 0 then self.sounds[#self.sounds + 1] = { delay = delay, event = event }
  else self:sound(event) end
end
OPS[53] = function(self) self:sound({ kind = "stop", gen5 = true }) end
OPS[54] = function() end
OPS[55] = function() end
-- 56 WAIT_FOR(kind) / 57 WAIT(frames) / 58 SET_YIELD
OPS[56] = function(self, a) self.waitKind = a(1) end
OPS[57] = function(self, a) self.waitFrames = max(0, a(1)) end
OPS[58] = function(self, a) self.yield = a(1) end
OPS[59] = function(self, a, i) if compare(self:var(a(1)), a(2), a(3)) then self:jump(i) end end
OPS[60] = function(self, a, i) if compare(self:var(a(1)), a(2), self:var(a(3))) then self:jump(i) end end
OPS[61] = function(self, a, i)
  local exists = (self:sideOf(a(1)) ~= nil) and 1 or 0
  if a(1) > 1 and a(1) ~= 14 and a(1) ~= 16 then exists = 0 end
  if exists == a(2) then self:jump(i) end
end
OPS[62] = function(self, a) self.work = a(1) end
OPS[63] = function(self, a) self.work = self:var(a(1)) end
OPS[64] = function(self, a) self.vars[a(1)] = a(2) end
OPS[65] = function(self) self:note("MCSS op65") end
-- 66 MCSS_COPY (0x02200140): Transform -- the defender's sprite copied onto
-- the attacker. The battle owns the pictures, so it is handed the moment
-- (src/battle/Gen5Transform.lua); not while duration() measures the program.
OPS[66] = function(self)
  if self.quiet then return end
  if self.onTransform then
    pcall(self.onTransform, self.attackerIsPlayer, self.layout)
  else
    self:note("Transform copy")
  end
end
-- 67 CRY_PLAY(target, ...)
OPS[67] = function(self, a)
  local side = self:sideOf(a(1))
  local delay = a(7)
  local event = { kind = "cry", gen5 = true, isPlayer = side }
  if delay > 0 then self.sounds[#self.sounds + 1] = { delay = delay, event = event }
  else self:sound(event) end
end
OPS[68] = function(self, a) self.typeSource = a(1) end
-- 69 OBJ_CREATE_BALL(slot, posCode, dx fx, dy fx, sx fx, sy fx): the ball the
-- item names (0x021FC148): the battler's world position plus (dx, dy),
-- projected; the art is /a/0/9/5's ball OBJ (Gen5MoveAnimData.ballObjects)
OPS[69] = function(self, a)
  local code = a(2)
  local side = self:sideOf(code)
  local home
  if side ~= nil then home = self:homeOf(side)
  elseif code >= 0 and code <= 7 then home = Layout.home(self.layout and self.layout.rule, code) end
  if not home then self:note("OBJ ball at " .. tostring(code)); return end
  self.objs = self.objs or {}
  self.objs[a(1)] = { anchor = { home[1] + fxv(a(3)), home[2] + fxv(a(4)), home[3] },
    dx = 0, dy = 0, sx = fxv(a(5)), sy = fxv(a(6)), seq = 0, seqT = 0,
    evy = 0, colour = 0, ball = self.ballId or 4, tasks = {} }
end
-- 70 CALL_EFFECT / 71 RETURN / 72 JUMP / 74 GOTO_EFFECT / 77 END
OPS[70] = function(self, a)
  if #self.stack >= 8 then return end
  self.stack[#self.stack + 1] = { code = self.code, to = self.to, pc = self.pc }
  if not self:enter(a(1)) then
    local fr = table.remove(self.stack)
    self.code, self.to, self.pc = fr.code, fr.to, fr.pc
  end
end
OPS[71] = function(self)
  local fr = table.remove(self.stack)
  if not fr then return "stop" end
  self.code, self.to, self.pc = fr.code, fr.to, fr.pc
end
OPS[72] = function(self, a, i) self:jump(i) end
OPS[73] = function() end
OPS[74] = function(self, a) if not self:enter(a(1)) then return "stop" end end
OPS[75] = function() end
OPS[76] = function() end
OPS[77] = function() return "stop" end

-- ---------------------------------------------------------------------------
-- emitters
-- ---------------------------------------------------------------------------

local function deepCopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do out[k] = deepCopy(v, seen) end
  return out
end

function Player:createEmitter(spec)
  local entry = self.slots[spec.spa]
  if entry == nil then entry = self.effects["spa_" .. tostring(spec.spa)] end
  if not (entry and entry.emitters) then
    self:note("emitter without spa " .. tostring(spec.spa))
    return
  end
  local src = entry.emitters[(tonumber(spec.index) or 0) + 1]
  if not src then self:note("spa " .. tostring(spec.spa) .. " emitter " .. tostring(spec.index)); return end
  local origin, flip = self:emitterPoint(spec.origin, spec.originXYZ)
  local targetCode = spec.target
  if targetCode == 8 and not spec.targetXYZ then targetCode = spec.origin end
  local target, tflip = self:emitterPoint(targetCode, spec.targetXYZ or spec.originXYZ)
  if not origin then self:note("emitter origin " .. tostring(spec.origin)); return end
  target = target or copy3(origin)
  flip = flip or tflip
  origin[3] = origin[3] + M.EMITTER_Z
  target[3] = target[3] + M.EMITTER_Z
  local y = spec.yOffset or 0
  origin[2], target[2] = origin[2] + y, target[2] + y
  if spec.offset then
    for k = 1, 3 do origin[k] = origin[k] + spec.offset[k]; target[k] = target[k] + spec.offset[k] end
  end

  local e = deepCopy(src)
  local f = e.fields or {}
  local sc = spec.scales or {}
  local function mul(v) return (tonumber(v) or FX) / FX end
  f.radius = (f.radius or 0) * mul(sc[1]); f.length = (f.length or 0) * mul(sc[1])
  f.particleLifeTime = max(1, floor((f.particleLifeTime or 1) * mul(sc[2]) + 0.5))
  f.baseScale = (f.baseScale or 0) * mul(sc[3])
  f.initVelPos = (f.initVelPos or 0) * mul(sc[4]); f.initVelAxis = (f.initVelAxis or 0) * mul(sc[4])
  -- toward the target: the axis turns to face it and the magnet/convergence
  -- aim at it (relative to the emitter)
  local dx, dy, dz = target[1] - origin[1], target[2] - origin[2], target[3] - origin[3]
  local len = sqrt(dx * dx + dy * dy + dz * dz)
  if len > 1e-4 then
    local ax = { dx / len, dy / len, dz / len }
    if flip then ax[1], ax[3] = -ax[1], -ax[3] end
    f.axis = ax
    local p = e.parsed
    if p then
      if p.magnet then p.magnet.x, p.magnet.y, p.magnet.z = dx, dy, dz end
      if p.convergence then p.convergence.x, p.convergence.y, p.convergence.z = dx, dy, dz end
    end
  end
  local sys = Gen4ParticleSystem.fromEmitters({ e })
  if not sys then return end
  self.seq = (self.seq or 0) + 1
  sys:start((self.moveId or 0) * 8191 + self.seq * 131 + 7)
  local inst = { sys = sys, art = entry.textures or {}, spa = spec.spa, screen = spec.screen,
                 pos = copy3(origin), origin = origin, target = target, age = 0 }
  if spec.frames then
    inst.path = { kind = spec.moveType or 1, frames = spec.frames, arc = spec.arc or 0,
                  waves = spec.waves or 0, n = 0 }
    if inst.path.kind == 4 then
      inst.target = { origin[1] + target[1], origin[2] + target[2], origin[3] + target[3] }
    end
  end
  if spec.orbit then inst.orbit = spec.orbit; inst.orbit.t = spec.orbit.start; inst.orbit.w = 0; inst.orbit.p = 0 end
  self.emitters[#self.emitters + 1] = inst
end

function Player:stepEmitter(e)
  e.age = e.age + 1
  local path = e.path
  if path and path.n < path.frames then
    path.n = path.n + 1
    local o, t = e.origin, e.target
    local u = path.n / path.frames
    local ang = pi * u
    local k = (1 - cos(ang)) / 2
    if path.kind == 3 then ang = 0.75 * pi * u; k = (1 - cos(ang)) / (1 - cos(0.75 * pi)) end
    local pos = { o[1] + (t[1] - o[1]) * k, o[2] + (t[2] - o[2]) * k, o[3] + (t[3] - o[3]) * k }
    if path.kind == 2 or path.kind == 3 then
      pos[2] = pos[2] + path.arc * sin(ang)
    elseif path.kind == 5 then
      pos[2] = pos[2] + path.arc * sin(2 * pi * path.waves * u)
    elseif path.kind == 6 then
      pos[3] = pos[3] + path.arc * sin(2 * pi * path.waves * u)
    end
    e.pos = pos
  end
  local ob = e.orbit
  if ob then
    if ob.p > 0 then ob.p = ob.p - 1
    elseif ob.w > 0 then ob.w = ob.w - 1
    else
      ob.w = ob.wait
      local before = floor(ob.t)
      ob.t = ob.t + (ob.reverse and -1 or 1) / ob.frames
      if floor(ob.t) ~= before then ob.p = ob.pause end
    end
    local a = ob.t * 2 * pi
    e.pos = { ob.centre[1] + ob.rx * sin(a), ob.centre[2] + ob.y, ob.centre[3] + M.EMITTER_Z + ob.rz * cos(a) }
  end
  if e.stopEmit then
    for _, em in ipairs(e.sys.emitters) do if em.fields then em.fields.emitterLifeTime = 1; em.fields.startDelay = 0 end end
  end
  local alive = e.sys:update()
  if not alive or e.age > Player.FRAME_BUDGET then e.done = true end
end

-- ---------------------------------------------------------------------------
-- the screen side: the cartridge's view onto the port's
-- ---------------------------------------------------------------------------

local function view(battle)
  local okV, V = pcall(require, "src.render.Gen5BattleSceneView")
  if okV and V and V.available and V.available(battle) then return V end
  return nil
end

-- the two anchors: where each battler's feet are in the cartridge's default
-- view and on the port's screen, and how many port pixels a ROM pixel is there
function Player:anchors(battle)
  battle = battle or self.battleRef
  if battle then self.battleRef = battle end
  return M.anchorsFor(battle)
end

-- the same, for a battle with no player running (src/battle/Gen5BattleLayout
-- stands the doubles slots through it)
function M.anchorsFor(battle)
  local V = battle and view(battle)
  local romP = { M.project(M.DEFAULT_CAM, M.HOME[0]) }
  local romF = { M.project(M.DEFAULT_CAM, M.HOME[1]) }
  local eyeP, eyeF, kP
  if V then
    eyeP = { V.standPoint("player") }
    eyeF = { V.standPoint("enemy") }
    kP = V.depthScale("player")
  end
  if not (eyeP and eyeP[1] and eyeF and eyeF[1]) then
    eyeP, eyeF, kP = { 64, 136 }, { 192, 88 }, 1
  end
  -- DRAMATIC_SHAPE's in-world battle stands the pair somewhere else on
  -- screen (Gen4EffectProjection's `dramaticNativePositions`, battler centres)
  local native = battle and battle.dramaticNativePositions
  if type(native) == "table" and native[0] and native[1] and native[0].x and native[1].x then
    eyeP = { native[0].x, native[0].y + 40 }
    eyeF = { native[1].x, native[1].y + 40 }
    kP = 1
  end
  -- the cartridge draws the foe's sprite at its native size; the player's is
  -- the perspective of the nearer platform (2.2x)
  local romScaleP = M.pixelsPerUnit(romP[3]) / M.pixelsPerUnit(romF[3])
  return { romP = romP, romF = romF, eyeP = eyeP, eyeF = eyeF,
           sP = (kP or 1) / romScaleP, sF = 1 }
end

-- toScreen(anchors, x, y) -> port screen x, y, local scale
function M.toScreen(A, x, y)
  local ax, ay = A.romP[1], A.romP[2]
  local bx, by = A.romF[1], A.romF[2]
  local vx, vy = bx - ax, by - ay
  local t = ((x - ax) * vx + (y - ay) * vy) / max(1e-6, vx * vx + vy * vy)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local px = A.eyeP[1] + A.sP * (x - ax)
  local py = A.eyeP[2] + A.sP * (y - ay)
  local fx_ = A.eyeF[1] + A.sF * (x - bx)
  local fy_ = A.eyeF[2] + A.sF * (y - by)
  return px + (fx_ - px) * t, py + (fy_ - py) * t, A.sP + (A.sF - A.sP) * t
end

-- the world point -> port screen, through the DEFAULT camera (the camera's
-- own moves are the zoom of `screenTransform`, applied to everything at once)
function Player:worldToScreen(A, p)
  local x, y, d = M.project(M.DEFAULT_CAM, p)
  local sx, sy, s = M.toScreen(A, x, y)
  return sx, sy, s * M.pixelsPerUnit(d)
end

-- screenTransform(battle) -> k, tx, ty (screen = k * point + t) or nil
function Player:screenTransform(battle)
  if battle then self.battleRef = battle end
  if not self:alive() then return nil end
  -- the in-world (DRAMATIC_SHAPE) battle has a camera of its own
  if battle and battle.dramaticNativePositions then return nil end
  local cam = self.cam
  if not cam then return nil end
  local sh = self.shake or { 0, 0, 0 }
  local p, t, d = cam.pos, cam.target, M.CAMERA
  if sh[1] == 0 and sh[2] == 0 and sh[3] == 0
     and p[1] == d.pos[1] and p[2] == d.pos[2] and p[3] == d.pos[3]
     and t[1] == d.target[1] and t[2] == d.target[2] and t[3] == d.target[3] then
    return nil
  end
  local pos = { cam.pos[1] + sh[1], cam.pos[2] + sh[2], cam.pos[3] + sh[3] }
  local tgt = { cam.target[1] + sh[1], cam.target[2] + sh[2], cam.target[3] + sh[3] }
  local cur = camera(pos, tgt)
  local A = self:anchors(battle)
  -- the point the camera looks at, under both cameras
  local T = cam.target
  local dx, dy, dd = M.project(M.DEFAULT_CAM, T)
  local cx, cy, cd = M.project(cur, T)
  local k = M.pixelsPerUnit(cd) / M.pixelsPerUnit(dd)
  if k > 4 then k = 4 elseif k < 0.5 then k = 0.5 end
  local ex, ey = M.toScreen(A, dx, dy)
  local nx, ny = M.toScreen(A, cx, cy)
  -- screen = k * (q - e) + n; the field is one screen's worth of picture, so
  -- the zoom never shows past its edges (k >= 1, translation clamped)
  if k < 1 then k = 1 end
  local tx, ty = nx - k * ex, ny - k * ey
  tx = min(0, max(M.LCD_W - k * M.LCD_W, tx))
  ty = min(0, max(M.LCD_H - k * M.LCD_H, ty))
  return k, tx, ty
end

-- ---------------------------------------------------------------------------
-- the channels BattleState / Gen4Battle read (Gen4MoveAnimPlayer's names)
-- ---------------------------------------------------------------------------

local function stateOf(self, isPlayer, battler)
  if not self:alive() then return nil end
  -- A DOUBLE: the channel follows the battler's own slot, so the partner
  -- standing beside the attacker (or the defender) is left alone
  if self.layout and type(battler) == "table" and battler.position ~= nil then
    local slot = (tonumber(battler.position) or 0) + 2
    for _, side in ipairs({ true, false }) do
      local s = self.state[side]
      if s and s.slot == slot then return s, side end
    end
    return nil
  end
  return self.state[isPlayer and true or false]
end

-- the battler's displacement in port pixels: its world position and draw
-- offset carried through the projection, relative to home
function Player:monOffset(isPlayer, battler)
  local s, side = stateOf(self, isPlayer, battler)
  if not s then return 0, 0 end
  if side == nil then side = isPlayer and true or false end
  local home = self:homeOf(side)
  local o = s.offset
  local p = { s.pos[1] + o[1], s.pos[2] + o[2], s.pos[3] + o[3] }
  if p[1] == home[1] and p[2] == home[2] and p[3] == home[3] then return 0, 0 end
  local A = self:anchors(self.battleRef)
  local hx, hy = self:worldToScreen(A, home)
  local px, py = self:worldToScreen(A, p)
  return floor(px - hx + 0.5), floor(py - hy + 0.5)
end

function Player:monAffine(isPlayer, battler)
  local s = stateOf(self, isPlayer, battler)
  if not s then return 1, 1 end
  return s.sx or 1, s.sy or 1
end

function Player:monRotate(isPlayer, battler)
  local s = stateOf(self, isPlayer, battler)
  if not s or not s.rot or s.rot == 0 then return nil end
  -- the cartridge's +z angle turns counter-clockwise on screen
  return -s.rot, 0
end

function Player:monTint(isPlayer, battler)
  local s = stateOf(self, isPlayer, battler)
  if not s or (s.evy or 0) <= 0 then return nil end
  local c = s.colour or 0
  return (c % 32) / 31, (floor(c / 32) % 32) / 31, (floor(c / 1024) % 32) / 31, min(1, s.evy / 16)
end

function Player:monSpecial(isPlayer, battler)
  local s = stateOf(self, isPlayer, battler)
  if not s then return nil end
  local alpha = (s.alpha or 31) / 31
  local mosaic = (s.mosaic or 0) + 1
  if alpha >= 1 and mosaic <= 1 then return nil end
  return { alpha = alpha, mosaic = mosaic, brightness = 1, white = 0 }
end

function Player:monHidden(isPlayer, battler)
  local s = stateOf(self, isPlayer, battler)
  return s ~= nil and s.hidden == true
end

function Player:monGhosts() return nil end
function Player:monWindow() return nil end
function Player:monSpriteFor() return nil end
function Player:monSpritesRendered() return false end
function Player:bgGrayscale() return false end
function Player:screenWash() return nil end
function Player:cells() return {} end
function Player:particles() return {} end
function Player:emitterCount()
  local n = 0
  for _, e in ipairs(self.emitters or {}) do if not e.done then n = n + 1 end end
  return n
end
function Player:spriteCount() return 0 end
-- is the idle (cell) animation of this side frozen by MCSS_ANIM_STOP
function Player:monAnimStopped(isPlayer, battler)
  local s = stateOf(self, isPlayer, battler)
  return s ~= nil and (s.stopA or s.stopB) and true or false
end

-- the field's palette fade (SCENE_PAL_FADE stage/field/all), drawn by
-- Gen4Battle between the field and the battlers; a hidden field is black
function Player:groupTint(name)
  if name ~= "base" or not self:alive() then return nil end
  if self.fieldHidden then return 0, 0, 0, 1 end
  local best
  for kind, f in pairs(self.fades) do
    if kind ~= 3 and (f.evy or 0) > 0 and (not best or f.evy > best.evy) then best = f end
  end
  if not best then return nil end
  local c = best.colour or 0
  return (c % 32) / 31, (floor(c / 32) % 32) / 31, (floor(c / 1024) % 32) / 31, min(1, best.evy / 16)
end

function Player:bgLayerState() return nil end

-- ---------------------------------------------------------------------------
-- drawing (called by Gen4Battle's hooks)
-- ---------------------------------------------------------------------------

local function imageOf(art)
  if not art then return nil end
  if art.image then return art.image end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not (okA and Assets and art.path) then return nil end
  local okI, img = pcall(Assets.image, art.path)
  return okI and img or nil
end

-- the effect background (BG3): 2D, so it is NOT zoomed by the camera
function Player:drawEffectLayer(battle)
  local bg = self.bg
  if not (self:alive() and bg and bg.shown) then return false end
  local img = imageOf(bg.art)
  if not img then return false end
  local g = love.graphics
  g.push()
  local k, tx, ty = self:screenTransform(battle)
  if k then g.scale(1 / k); g.translate(-tx, -ty) end
  local w, h = img:getWidth(), img:getHeight()
  local sx, sy = self.bgScroll and self.bgScroll[1] or 0, self.bgScroll and self.bgScroll[2] or 0
  local ox, oy = -(sx % w), -(sy % h)
  g.setColor(1, 1, 1, 1)
  for _, ddx in ipairs({ 0, w }) do
    for _, ddy in ipairs({ 0, h }) do
      if ox + ddx < M.LCD_W and oy + ddy < M.LCD_H then g.draw(img, ox + ddx, oy + ddy) end
    end
  end
  local f = self.fades[3]
  if f and (f.evy or 0) > 0 then
    local c = f.colour or 0
    g.setColor((c % 32) / 31, (floor(c / 32) % 32) / 31, (floor(c / 1024) % 32) / 31, min(1, f.evy / 16))
    g.rectangle("fill", 0, 0, M.LCD_W, M.LCD_H)
  end
  g.setColor(1, 1, 1, 1)
  g.pop()
  return true
end

-- every live particle, projected; farthest first
function Player:drawParticles(battle)
  if not self:alive() then return 0 end
  local A = self:anchors(battle)
  local list = {}
  for _, e in ipairs(self.emitters) do
    if not e.done then
      local sys = e.sys
      local function add(p, layer)
        if p.hidden and layer == 0 then return end
        -- SPL draws a particle at its EMITTER's current position plus its own
        -- (emitter-relative) one, so a moving emitter carries its particles:
        -- that is what turns Water Gun's per-frame emitters into a stream
        local wx, wy, wz = e.pos[1], e.pos[2], e.pos[3]
        local x, y, size
        if e.screen then
          local ax, ay = self:worldToScreen(A, { wx, wy, wz })
          x = ax + p.x * M.SCREEN_UNITS
          y = ay - p.y * M.SCREEN_UNITS
          size = M.SCREEN_UNITS
          list[#list + 1] = { p = p, e = e, x = x, y = y, size = size, depth = -1e9 + (p.z or 0), layer = p.layer or 0 }
        else
          local w = { wx + p.x, wy + p.y, wz + p.z }
          local _, _, d = M.project(M.DEFAULT_CAM, w)
          x, y, size = self:worldToScreen(A, w)
          list[#list + 1] = { p = p, e = e, x = x, y = y, size = size, depth = d, layer = p.layer or 0 }
        end
      end
      for _, p in ipairs(sys.particles or {}) do add(p, 0) end
      for _, p in ipairs(sys.children or {}) do add(p, 1) end
    end
  end
  table.sort(list, function(a, b)
    if a.depth ~= b.depth then return a.depth > b.depth end
    return a.layer < b.layer
  end)
  local g = love.graphics
  local drawn = 0
  for _, q in ipairs(list) do
    local p = q.p
    local art = q.e.art[(tonumber(p.texture) or 0) + 1]
    local img = imageOf(art)
    if img then
      local a = p.alpha or 1
      if a > 0 then
        -- the particle's own colour (born with the emitter's, then the colour
        -- curve's); the runtime emitter colour it is multiplied by stays white
        local c = p.colour
        local r, gg, b = 1, 1, 1
        if c then r, gg, b = (c[1] or 255) / 255, (c[2] or 255) / 255, (c[3] or 255) / 255 end
        g.setColor(r, gg, b, min(1, a))
        local w, h = img:getWidth(), img:getHeight()
        -- a billboard is a quad of +-scale world units
        local sx = 2 * (p.scaleX or p.scale or 1) * q.size / w
        local sy = 2 * (p.scaleY or p.scale or 1) * q.size / h
        local rot = ((p.rotation or 0) % 65536) * 2 * pi / 65536
        g.draw(img, q.x, q.y, rot, sx, sy, w / 2, h / 2)
        drawn = drawn + 1
      end
    end
  end
  g.setColor(1, 1, 1, 1)
  return drawn
end

-- a one-line state dump for the harness's TRACE
-- THE OBJs (op 69's ball), drawn in screen pixels at their anchor's
-- projected spot plus their offset, at the size the cartridge's OAM gives
-- them (a 32 x 32 cell times its affine scale; the foe's side is native),
-- recoloured by their palette fade. Drawn whether or not the program is
-- still running: a caught ball stays where it settled.
-- (the camera's zoom moves the anchor, not the OAM's size or its offsets:
-- `xf` is screenTransform's k, tx, ty)
function Player:objectAt(o, A, xf)
  local x, y = self:worldToScreen(A, o.anchor)
  if xf then x, y = xf[1] * x + xf[2], xf[1] * y + xf[3] end
  return x + o.dx, y + o.dy
end

function Player:drawObjects(battle, data, xf)
  local objs = self.objs
  if not (objs and next(objs)) then return 0 end
  local rec = data and data.gen5_move_anims
  local art = (rec and rec.ballObj) or self.ballObj
  if not art then return 0 end
  local A = self:anchors(battle)
  local g = love.graphics
  local drawn = 0
  for slot = 7, 0, -1 do   -- the shadow (slot 1) under the ball (slot 0)
    local o = objs[slot]
    if o then
      local b = (o.ball == 25) and 17 or o.ball
      local cells = art.balls and (art.balls[b] or art.balls[4])
      local frames = art.sequences and art.sequences[o.seq or 0]
      local cell = 0
      if frames then
        local t, elapsed = o.seqT or 0, 0
        cell = frames[#frames] and frames[#frames].cell or 0
        for _, f in ipairs(frames) do
          elapsed = elapsed + (f.duration or 0)
          if t < elapsed then cell = f.cell; break end
        end
      end
      local img = cells and imageOf(cells[cell] or cells[0])
      if img then
        local x, y = self:objectAt(o, A, xf)
        local w, h = img:getDimensions()
        local evy = min(16, max(0, o.evy or 0)) / 16
        local c = o.colour or 0
        local cr, cg, cb = (c % 32) / 31, (floor(c / 32) % 32) / 31, (floor(c / 1024) % 32) / 31
        g.setColor(1, 1, 1, 1)
        g.draw(img, x, y, 0, o.sx or 1, o.sy or 1, w / 2, h / 2)
        if evy > 0 then
          -- the fade blends every colour toward `colour`: drawn as the cell's
          -- own shape in that colour over it
          local okS, shader = pcall(function() return M.solidShader() end)
          if okS and shader then
            g.setShader(shader)
            g.setColor(cr, cg, cb, evy)
            g.draw(img, x, y, 0, o.sx or 1, o.sy or 1, w / 2, h / 2)
            g.setShader()
          end
        end
        drawn = drawn + 1
      end
    end
  end
  g.setColor(1, 1, 1, 1)
  return drawn
end

local solid
function M.solidShader()
  if solid == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 px) {
        float a = Texel(tex, uv).a;
        return vec4(colour.rgb, colour.a * a);
      }
    ]])
    solid = ok and sh or false
  end
  return solid or nil
end

function Player:traceLine()
  local s1, s2 = self.state[true], self.state[false]
  local function st(s)
    return ("pos=%.2f,%.2f off=%.2f,%.2f,%.2f s=%.2f,%.2f r=%.2f a=%d evy=%d%s"):format(
      s.pos[1], s.pos[2], s.offset[1], s.offset[2], s.offset[3], s.sx, s.sy, s.rot, s.alpha, s.evy,
      s.hidden and " HID" or "")
  end
  local busy = ""
  for k = 1, 9 do if self:busy(k) then busy = busy .. k end end
  return ("pc=%s busy=%s pl[%s] en[%s] em=%d cam=%.2f,%.2f,%.2f bg=%s"):format(tostring(self.pc), busy, st(s1), st(s2),
    self:emitterCount(), self.cam.pos[1], self.cam.pos[2], self.cam.pos[3],
    self.bg and (tostring(self.bg.id) .. (self.bg.shown and "+" or "-")) or "nil")
end

M.Player = Player
return M
