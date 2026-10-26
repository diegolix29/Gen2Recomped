-- A POKEMON'S MOTION PROGRAM, RUN -- pokeplatinum src/pokemon_anim.c.
--
-- The hops, squashes, sways and spins a Platinum / HGSS front sprite does
-- when it appears (the cry, a hatch, a send-out). The program is one of
-- pl_poke_anm.narc's 143 scripts (gen4_poke_motion, Gen4PokeMotion); the
-- species picks it and a start delay (def.picAnim.motion / startDelay).
--
-- Task_RunPokemonAnim once a frame: the start delay, then up to four live
-- transforms (curve / linear tweens of an offset, a scale or the rotation),
-- then commands until one waits (WaitFrame, WaitTransform, WaitFade,
-- SetStartDelay) or ends. What it drives is the sprite's own transform --
-- read here as `sprite`:
--   x, y          the centre, relative to where the sprite was (0, 0)
--   scaleX/Y      256 = 1 (MON_AFFINE_SCALE), about the centre
--   rotation      u16 angle about (x + pivotX, y)
--   pivotX        MON_SPRITE_X_PIVOT
--   fade          { level, target, delay, colour } (PokemonSprite_StartFade,
--                 a 0..16 blend toward an RGB555 colour)
--
-- Integer maths as the cartridge does it: FX_SinIdx from a 4096-entry table
-- (rounded), FX_Whole an arithmetic shift, C division truncating to zero.

local Motion = {}; Motion.__index = Motion

local NUM_ANIMS, MAX_COMMANDS = 143, 256

-- generated/pokemon_anim_constants.txt
local C = {
  TRANSLATE_X = 8, TRANSLATE_Y = 9, OFFSET_X = 10, OFFSET_Y = 11, SCALE_X = 12, SCALE_Y = 13, ROTATION_Z = 14,
  LT = 15, GT = 16, EQ = 17,
  VALUE = 18, VAR = 19, VALUE2 = 20, VAR2 = 21,
  ATTR_SET = 22, ATTR_ADD = 23,
  CALC_SET = 24, CALC_ADD = 25, CALC_INCREMENT = 26,
  YN_NEGATIVE = 27, YN_OFF = 28, YN_ON = 29,
  SIN = 30, COS = 31, NEG_SIN = 32, NEG_COS = 33,
  T_OFFSET_X = 35, T_OFFSET_Y = 36, T_SCALE_X = 37, T_SCALE_Y = 38, T_ROTATION_Z = 39,
}
Motion.C = C

-- enum PokemonSpriteAttribute values the scripts touch (only X_PIVOT in the
-- shipped programs)
local SPRITE_ATTR = { [0] = "x", [1] = "y", [6] = "rotation", [9] = "pivotX", [12] = "scaleX", [13] = "scaleY" }

local function trunc(a, b)
  if b == 0 then return 0 end
  local q = a / b
  return q >= 0 and math.floor(q) or math.ceil(q)
end
local function cmod(a, b)
  if b == 0 then return 0 end
  return a - trunc(a, b) * b
end
local function u16(v) return v % 65536 end

local SIN = {}
local function fxSinIdx(idx)
  local i = math.floor(u16(idx) / 16)
  local v = SIN[i]
  if not v then v = math.floor(math.sin(i / 4096 * 2 * math.pi) * 4096 + 0.5); SIN[i] = v end
  return v
end
local function fxCosIdx(idx) return fxSinIdx(u16(idx) + 16384) end
local function fxWhole(v) return math.floor(v / 4096) end

-- new(data, animNum, startDelay, flip) -> a motion, or nil without the cache
function Motion.new(data, animNum, startDelay, flip)
  local scripts = data and data.gen4_poke_motion
  if type(scripts) ~= "table" then return nil end
  animNum = tonumber(animNum) or 0
  if animNum >= NUM_ANIMS then animNum, startDelay = 0, 0 end
  local script = scripts[animNum]
  if type(script) ~= "table" then return nil end
  local self = setmetatable({
    script = script, pc = 1, vars = { [0] = 0, 0, 0, 0, 0, 0, 0, 0 },
    startDelay = tonumber(startDelay) or 0, flip = flip and true or false,
    translateX = 0, translateY = 0, offsetX = 0, offsetY = 0,
    scaleX = 0, scaleY = 0, rotationZ = 0,
    transforms = {}, yNormalization = C.YN_OFF,
    sprite = { x = 0, y = 0, scaleX = 256, scaleY = 256, rotation = 0, pivotX = 0 },
  }, Motion)
  return self
end

-- ---------------------------------------------------------------- reading --

function Motion:word()
  self.pc = self.pc + 1
  return self.script[self.pc] or 0
end

function Motion:var(i) return self.vars[i] or 0 end

-- ReadScript_VarAndIntOrVar
function Motion:varAndIntOrVar()
  local dest, kind = self:word(), self:word()
  if kind == C.VALUE then
    local a = self:var(self:word()); return dest, a, self:word()
  end
  local a, b = self:word(), self:word()
  return dest, self:var(a), self:var(b)
end

-- ReadScript_TwoIntOrVar
function Motion:twoIntOrVar()
  local dest, k1, k2 = self:word(), self:word(), self:word()
  local a = (k1 == C.VALUE) and self:word() or self:var(self:word())
  local b = (k2 == C.VALUE) and self:word() or self:var(self:word())
  return dest, a, b
end

-- an operand that is a literal (VALUE2) or a var (VAR2)
function Motion:valueOrVar2()
  local kind = self:word()
  if kind == C.VALUE2 or kind == C.VALUE then return self:word() end
  return self:var(self:word())
end

-- ReadScript_TrigOperands
function Motion:trig()
  local dest, radiansIndex = self:word(), self:word()
  local radians = self:var(radiansIndex)
  local amplitude = self:valueOrVar2()
  local offset = self:valueOrVar2()
  return dest, cmod(radians + offset, 0x10000), amplitude
end

-- --------------------------------------------------------------- sprite --

function Motion:setOriginal()
  local s = self.sprite
  s.x, s.y, s.rotation, s.pivotX, s.scaleX, s.scaleY = 0, 0, 0, 0, 256, 256
end

function Motion:applyTranslation()
  local s = self.sprite
  if self.flip then s.x = -(self.translateX + self.offsetX) else s.x = self.translateX + self.offsetX end
  s.y = self.translateY + self.offsetY
end

function Motion:applyScaleAndRotation()
  local s = self.sprite
  s.scaleX, s.scaleY = 256 + self.scaleX, 256 + self.scaleY
  s.rotation = u16(self.rotationZ)
  local yn = self.yNormalization
  if (yn == C.YN_NEGATIVE and self.scaleY < 0) or (yn == C.YN_ON and self.scaleY ~= 0) then
    s.y = s.y + trunc(-self.scaleY, 8)
  end
end

function Motion:startFade(init, target, delay, colour)
  self.sprite.fade = { level = init, target = target, delay = delay, count = delay, colour = colour }
end

function Motion:fadeActive()
  local f = self.sprite.fade
  return f ~= nil and f.level ~= f.target
end

function Motion:tickFade()
  local f = self.sprite.fade
  if not f or f.level == f.target then return end
  if f.count > 0 then f.count = f.count - 1; return end
  f.count = f.delay
  f.level = f.level + (f.level < f.target and 1 or -1)
end

-- ------------------------------------------------------------ transforms --

local MEMBER = {
  [C.T_OFFSET_X] = "offsetX", [C.T_OFFSET_Y] = "offsetY", [C.T_SCALE_X] = "scaleX",
  [C.T_SCALE_Y] = "scaleY", [C.T_ROTATION_Z] = "rotationZ",
}

-- CalcNextTransformValue
function Motion:calc(t)
  local cur = t.value
  if t.calcType == C.CALC_SET then self[t.member] = cur
  elseif t.calcType == C.CALC_ADD then self[t.member] = t.original + cur
  else self[t.member] = self[t.member] + cur end
end

local function curveValue(kind, radians, amplitude)
  if kind == C.SIN then return fxWhole(fxSinIdx(radians) * amplitude)
  elseif kind == C.COS then return fxWhole(fxCosIdx(radians) * amplitude)
  elseif kind == C.NEG_SIN then return -fxWhole(fxSinIdx(radians) * amplitude)
  else return -fxWhole(fxCosIdx(radians) * amplitude) end
end

local FUNCS = {
  -- TransformFunc_Curve: vars curve, type, amplitude, step, phase, frames, i
  curve = function(self, t)
    local v = t.vars
    t.value = curveValue(v[0], u16(v[3] * (v[6] + 1) + v[4]), v[2])
    self:calc(t)
    v[6] = v[6] + 1
    if v[6] >= v[5] then t.active = false end
  end,
  curveEven = function(self, t)
    local v = t.vars
    t.value = curveValue(v[0], u16(trunc(v[3] * (v[6] + 1), v[5]) + v[4]), v[2])
    self:calc(t)
    v[6] = v[6] + 1
    if v[6] >= v[5] then t.active = false end
  end,
  -- TransformFunc_Linear: vars type, start, accel, frames, i
  linear = function(self, t)
    local v = t.vars
    t.value = t.value + v[1] + v[2] * v[4]
    self:calc(t)
    v[4] = v[4] + 1
    if v[4] >= v[3] then t.active = false end
  end,
  -- TransformFunc_LinearEven: vars type, distance, frames, i
  linearEven = function(self, t)
    local v = t.vars
    t.value = trunc((v[3] + 1) * v[1], v[2])
    self:calc(t)
    v[3] = v[3] + 1
    if v[3] >= v[2] then t.active = false end
  end,
  -- TransformFunc_LinearBounded: vars type, start, accel, bound, i
  linearBounded = function(self, t)
    local v = t.vars
    local distance = v[1] + v[2] * v[4]
    t.value = t.value + distance
    if t.calcType == C.CALC_SET or t.calcType == C.CALC_INCREMENT then
      if (distance < 0 and t.value <= v[3]) or (distance >= 0 and t.value >= v[3]) then
        t.value = v[3]; t.active = false
      end
    else
      local sum = t.original + t.value
      if distance < 0 then
        if sum <= v[3] then t.value = t.value + (v[3] - sum); t.active = false end
      elseif sum >= v[3] then
        t.value = t.value - (sum - v[3]); t.active = false
      end
    end
    self:calc(t)
    v[4] = v[4] + 1
  end,
}

-- sTransformFuncToParams: { func, paramCount, transformTypeIndex }
local PARAMS = {
  [26] = { "curve", 6, 1 }, [27] = { "curveEven", 6, 1 }, [28] = { "linear", 4, 0 },
  [29] = { "linearEven", 3, 0 }, [30] = { "linearBounded", 4, 0 },
}

function Motion:newTransform(op)
  local p = PARAMS[op]
  local t = { active = true, fn = FUNCS[p[1]], vars = {}, value = 0 }
  for i = 0, 7 do t.vars[i] = 0 end
  t.calcType, t.startDelay = self:word(), self:word()
  for i = 0, p[2] - 1 do t.vars[i] = self:word() end
  t.member = MEMBER[t.vars[p[3]]] or "offsetY"
  t.original = self[t.member]
  -- a free slot of four (TransformFuncData_New)
  local slot
  for i = 1, 4 do if not (self.transforms[i] and self.transforms[i].active) then slot = i; break end end
  if not slot then return end
  self.transforms[slot] = t
  if t.startDelay == 0 then t.fn(self, t) else t.startDelay = t.startDelay - 1 end
end

-- -------------------------------------------------------------- commands --

local OPS = {}
OPS[0] = function(self) self:setOriginal(); self.waitFrame = true; self.ended = true end
OPS[1] = function(self) self.waitFrame = true end
OPS[2] = function(self) self:setOriginal() end
OPS[3] = function(self)                                  -- SetVarIf
  local kind = self:word()
  local a, b
  if kind == C.VALUE2 or kind == C.VALUE then a = self:var(self:word()); b = self:word()
  else a = self:var(self:word()); b = self:var(self:word()) end
  local condition = self:word()
  local result = (a - b < 0) and C.LT or ((a - b > 0) and C.GT or C.EQ)
  local k2 = self:word()
  local dest, value = self:word(), nil
  if k2 == C.VALUE2 or k2 == C.VALUE then value = self:word() else value = self:var(self:word()) end
  if condition == result then self.vars[dest] = value end
end
OPS[4] = function(self) local i = self:word(); self.vars[i] = self:word() end
OPS[5] = function(self) local d, o = self:word(), self:word(); self.vars[d] = self:var(o) end
OPS[6] = function(self) local d, a, b = self:varAndIntOrVar(); self.vars[d] = a + b end
OPS[7] = function(self) local d, a, b = self:varAndIntOrVar(); self.vars[d] = a * b end
OPS[8] = function(self) local d, a, b = self:twoIntOrVar(); self.vars[d] = a - b end
OPS[9] = function(self) local d, a, b = self:twoIntOrVar(); self.vars[d] = trunc(a, b) end
OPS[10] = function(self) local d, a, b = self:twoIntOrVar(); self.vars[d] = cmod(a, b) end
OPS[11] = function(self)                                 -- Loop
  self.pc = self.pc + 1
  self.loopStart, self.loopMax, self.loopCounter = self.pc, self.script[self.pc] or 0, 0
end
OPS[12] = function(self)                                 -- LoopEnd
  self.loopCounter = (self.loopCounter or 0) + 1
  if self.loopCounter >= (self.loopMax or 0) then self.loopStart, self.loopCounter, self.loopMax = nil, 0, 0
  else self.pc = self.loopStart end
end
OPS[13] = function(self)
  local attr, i = self:word(), self:word()
  local key = SPRITE_ATTR[attr]; if key then self.sprite[key] = self:var(i) end
end
OPS[14] = function(self)
  local attr, i = self:word(), self:word()
  local key = SPRITE_ATTR[attr]; if key then self.sprite[key] = self.sprite[key] + self:var(i) end
end
OPS[15] = function(self)                                 -- UpdateSpriteAttribute
  local attr = self:word()
  local value = self:valueOrVar2()
  local how = self:word()
  local key = SPRITE_ATTR[attr]
  if key then self.sprite[key] = (how == C.ATTR_ADD) and self.sprite[key] + value or value end
end
OPS[16] = function(self) local d, r, a = self:trig(); self.vars[d] = fxWhole(fxSinIdx(r) * a) end
OPS[17] = function(self) local d, r, a = self:trig(); self.vars[d] = fxWhole(fxCosIdx(r) * a) end
OPS[18] = function(self)                                 -- SetTranslation
  local i, kind = self:word(), self:word()
  if kind == C.TRANSLATE_X then self.translateX = self:var(i) else self.translateY = self:var(i) end
end
OPS[19] = function(self)
  local i, kind = self:word(), self:word()
  if kind == C.TRANSLATE_X then self.translateX = self.translateX + self:var(i)
  else self.translateY = self.translateY + self:var(i) end
end
local ATTR_MEMBER = { [8] = "translateX", [9] = "translateY", [10] = "offsetX", [11] = "offsetY",
  [12] = "scaleX", [13] = "scaleY", [14] = "rotationZ" }
OPS[20] = function(self)                                 -- UpdateAttribute
  local member = ATTR_MEMBER[self:word()] or "offsetY"
  local value = self:valueOrVar2()
  local how = self:word()
  self[member] = (how == C.ATTR_ADD) and self[member] + value or value
end
OPS[21] = function(self) self:applyTranslation() end
OPS[22] = function(self) self:applyScaleAndRotation() end
OPS[23] = function(self)                                 -- SetOffset
  local i, attr = self:word(), self:word()
  if attr == C.TRANSLATE_X or attr == C.OFFSET_X then self.offsetX = self:var(i) else self.offsetY = self:var(i) end
end
OPS[24] = function(self) self.waitForTransform = true end
OPS[25] = function(self) self.yNormalization = self:word() end
for op = 26, 30 do OPS[op] = function(self) self:newTransform(op) end end
OPS[31] = function(self) self.startDelay = self:word(); self.waitFrame = true end
OPS[32] = function(self)
  local init, target, delay, colour = self:word(), self:word(), self:word(), self:word()
  self:startFade(init, target, delay, colour)
end
OPS[33] = function(self) if self:fadeActive() then self.fadeWait = true; self.waitFrame = true end end

-- RunPokemonAnimScript
function Motion:run()
  self.waitFrame = false
  local inactive = 0
  for i = 1, 4 do
    local t = self.transforms[i]
    if t and t.active then
      if t.startDelay == 0 then t.fn(self, t) else t.startDelay = t.startDelay - 1 end
    else
      inactive = inactive + 1
    end
  end
  if inactive == 4 then self.waitForTransform = false end
  if self.waitForTransform then
    self:applyTranslation(); self:applyScaleAndRotation()
    return
  end
  if self.fadeWait then
    if not self:fadeActive() then self.fadeWait = false else return end
  end
  for _ = 1, MAX_COMMANDS do
    local op = OPS[self.script[self.pc]]
    if not op then self.ended = true; return end
    op(self)
    if self.ended then return end
    self.pc = self.pc + 1
    if self.waitFrame then return end
    if self.waitForTransform then
      self:applyTranslation(); self:applyScaleAndRotation()
      return
    end
  end
  self.ended = true
end

-- Task_RunPokemonAnim: one frame. Returns false once the program has ended.
function Motion:update()
  self:tickFade()
  if self.ended then return false end
  if self.startDelay == 0 then self:run() else self.startDelay = self.startDelay - 1 end
  return not self.ended
end

function Motion:done() return self.ended == true end

-- Draw `img` (or a quad of it) as the motion places it: centre (cx, cy),
-- scaled about the centre, rotated about (centre + pivotX).
function Motion:draw(img, quad, cx, cy, w, h)
  local g = love.graphics
  local s = self.sprite
  local x, y = cx + s.x, cy + s.y
  local px = x + s.pivotX
  g.push()
  g.translate(px, y)
  g.rotate((s.rotation or 0) / 65536 * 2 * math.pi)
  g.translate(-px, -y)
  local sx, sy = (s.scaleX or 256) / 256, (s.scaleY or 256) / 256
  if quad then g.draw(img, quad, x, y, 0, sx, sy, w / 2, h / 2)
  else g.draw(img, x, y, 0, sx, sy, w / 2, h / 2) end
  g.pop()
end

-- The fade as { r, g, b, amount } (amount 0..1), or nil.
function Motion:fadeColour()
  local f = self.sprite.fade
  if not f or f.level <= 0 then return nil end
  local c = tonumber(f.colour) or 0
  return { (c % 32) / 31, (math.floor(c / 32) % 32) / 31, (math.floor(c / 1024) % 32) / 31, f.level / 16 }
end

return Motion
