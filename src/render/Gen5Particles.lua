-- THE NITRO PARTICLE LIBRARY (SPL), run: a port of pret pokeheartgold
-- lib/spl -- spl_emitter.c (SPLEmitter_Init / _Update), spl_emit.c
-- (SPLEmitter_EmitParticles), spl_anim.c, spl_behavior.c and spl_manager.c's
-- start / terminate rules -- over the resources src/import/Gen5Particles.lua
-- reads. One `step` is one SPLManager_Update; positions are the resource's
-- own units.
--
-- The animation curves keep the library's integer arithmetic (the life rate
-- is a u8, the curves divide with C's truncation), and the random numbers are
-- its LCG (state * 0x5EEDF715 + 0x1B0CB173), so a burst comes out the way the
-- cartridge's does for the same seed.
--
-- DRAWN AS BILLBOARDS. The scenes here view along -z with no turn, so a
-- billboard is a screen-aligned quad at the particle's depth. The polygon and
-- directional draw types (none of the cut-ins' resources use them) are drawn
-- the same way rather than left out.

local S = {}
S.__index = S

local floor, sqrt, sin, cos, pi, max, min = math.floor, math.sqrt, math.sin, math.cos, math.pi, math.max, math.min

local function trunc(x) if x >= 0 then return floor(x) end return -floor(-x) end

-- the LCG, exact in doubles: the product split into 16-bit halves
local function mul32(a, b)
  local ah, al = floor(a / 65536), a % 65536
  local lo = al * b
  local hi = (ah * b) % 65536
  return (lo + hi * 65536) % 4294967296
end

function S.newRandom(seed)
  local R = { state = (seed or 0) % 4294967296 }
  function R.next()
    R.state = (mul32(R.state, 0x5EEDF715) + 0x1B0CB173) % 4294967296
    return R.state
  end
  function R.u32(bits) return floor(R.next() / 2 ^ (32 - bits)) end
  -- (fx32)Next >> (32 - bits): the signed reading, shifted
  function R.fx(bits)
    local v = R.next()
    if v >= 2147483648 then v = v - 4294967296 end
    return floor(v / 2 ^ (32 - bits))
  end
  -- [num * (1 - range), num)
  function R.scaled(num, range) return num * (255 - floor(range * R.u32(8) / 256)) / 256 end
  -- [num * (1 - range), num * 2 * (1 - range))
  function R.doubleScaled(num, range) return num * (255 + range - floor(range * R.u32(8) / 128)) / 256 end
  -- [-num, num)
  function R.range(num) return (num * R.u32(9) - num * 256) / 256 end
  function R.vec(xyOnly)
    local x, y, z = R.fx(24), R.fx(24), xyOnly and 0 or R.fx(24)
    local l = sqrt(x * x + y * y + z * z)
    if l == 0 then return 0, 0, 0 end
    return x / l, y / l, z / l
  end
  return R
end

-- new(resource, position, random) -> an emitter (SPLEmitter_Init)
function S.new(res, pos, R)
  local h = res.header
  local e = setmetatable({ res = res, h = h, R = R or S.newRandom(0),
    x = (pos and pos[1] or 0) + h.basePos[1], y = (pos and pos[2] or 0) + h.basePos[2],
    z = (pos and pos[3] or 0) + h.basePos[3],
    age = 0, fraction = 0, started = false, particles = {}, terminated = false }, S)
  return e
end

local function normal(x, y, z)
  local l = sqrt(x * x + y * y + z * z)
  if l == 0 then return 0, 0, 1 end
  return x / l, y / l, z / l
end

-- the two axes a circle or a cylinder lies across (SPLEmitter_ComputeOrthogonalAxes)
local function crossAxes(e)
  local h = e.h
  local ax, ay, az
  if h.circleAxis == 2 then ax, ay, az = 1, 0, 0
  elseif h.circleAxis == 1 then ax, ay, az = 0, 1, 0
  elseif h.circleAxis == 0 then ax, ay, az = 0, 0, 1
  else ax, ay, az = normal(h.axis[1], h.axis[2], h.axis[3]) end
  local vx, vy, vz = 0, 1, 0
  local dot = ay
  if dot == 1 or dot == -1 then vx, vy, vz = 1, 0, 0 end
  local c1x, c1y, c1z = ay * vz - az * vy, az * vx - ax * vz, ax * vy - ay * vx
  local c2x, c2y, c2z = ay * c1z - az * c1y, az * c1x - ax * c1z, ax * c1y - ay * c1x
  e.c1 = { normal(c1x, c1y, c1z) }
  e.c2 = { normal(c2x, c2y, c2z) }
end

local function tilt(e, x, y, z)
  local a, b = e.c1, e.c2
  local nx, ny, nz = normal(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
  return x * a[1] + y * b[1] + z * nx, x * a[2] + y * b[2] + z * ny, x * a[3] + y * b[3] + z * nz
end

-- SPLEmitter_EmitParticles
function S:emit()
  local h, R, res = self.h, self.R, self.res
  local total = self.fraction + h.emissionCount
  local n = floor(total)
  self.fraction = total - n
  local t = h.emissionType
  if t == 2 or t == 3 or t == 5 or t == 6 or t == 7 or t == 8 or t == 9 then crossAxes(self) end
  for i = 0, n - 1 do
    local p = {}
    local px, py, pz = 0, 0, 0
    local cylX, cylY
    if t == 1 then
      px, py, pz = R.vec(); px, py, pz = px * h.radius, py * h.radius, pz * h.radius
    elseif t == 2 then
      local x, y = R.vec(true)
      px, py, pz = tilt(self, x * h.radius, y * h.radius, 0)
    elseif t == 3 then
      local a = (i * 16 * 4096 / n) / 65536 * 2 * pi
      px, py, pz = tilt(self, sin(a) * h.radius, cos(a) * h.radius, 0)
    elseif t == 4 then
      px, py, pz = R.vec()
      px = px * h.radius * R.range(1); py = py * h.radius * R.range(1); pz = pz * h.radius * R.range(1)
    elseif t == 5 then
      local x, y = R.vec(true)
      px, py, pz = tilt(self, x * h.radius * R.range(1), y * h.radius * R.range(1), 0)
    elseif t == 6 or t == 7 then
      cylX, cylY = R.vec(true)
      local k = (t == 7) and R.range(1) or 1
      local k2 = (t == 7) and R.range(1) or 1
      px, py, pz = tilt(self, cylX * h.radius * k, cylY * h.radius * k2, R.range(h.length))
    elseif t == 8 or t == 9 then
      px, py, pz = R.vec()
      local ux, uy, uz = normal(self.c1[2] * self.c2[3] - self.c1[3] * self.c2[2],
                                self.c1[3] * self.c2[1] - self.c1[1] * self.c2[3],
                                self.c1[1] * self.c2[2] - self.c1[2] * self.c2[1])
      local d = ux * px + uy * py + uz * pz
      if (t == 8 and d <= 0) or (t == 9 and d < 0) then px, py, pz = -px, -py, -pz end
      local k = (t == 9) and (R.range(1) / 2 + 0.5) or 1
      px, py, pz = px * h.radius * k, py * h.radius * k, pz * h.radius * k
    end
    local magPos = R.doubleScaled(h.initVelPos, h.randInitVel)
    local magAxis = R.doubleScaled(h.initVelAxis, h.randInitVel)
    local nx, ny, nz
    if t == 6 then
      nx, ny, nz = normal(cylX * self.c1[1] + cylY * self.c2[1], cylX * self.c1[2] + cylY * self.c2[2],
                          cylX * self.c1[3] + cylY * self.c2[3])
    elseif px == 0 and py == 0 and pz == 0 then
      nx, ny, nz = R.vec()
    else
      nx, ny, nz = normal(px, py, pz)
    end
    p.x, p.y, p.z = px, py, pz
    p.vx = nx * magPos + h.axis[1] * magAxis
    p.vy = ny * magPos + h.axis[2] * magAxis
    p.vz = nz * magPos + h.axis[3] * magAxis
    p.ex, p.ey, p.ez = self.x, self.y, self.z
    p.baseScale = R.doubleScaled(h.baseScale, h.randBaseScale)
    p.animScale = 1
    if res.color and res.color.randomStart then
      local idx = R.u32(12) % 3
      p.color = ({ res.color.start, h.color, res.color["end"] })[idx + 1]
    else
      p.color = h.color
    end
    p.baseAlpha, p.animAlpha = h.baseAlpha, 31
    p.rotation = h.randomInitAngle and R.u32(32) % 65536 or h.initAngle
    p.angularVelocity = h.hasRotation
      and floor(((h.maxRotation - h.minRotation) * R.u32(12) + h.minRotation * 4096) / 4096) or 0
    p.life = floor(R.scaled(h.particleLife, h.randLife)) + 1
    p.age = 0
    if res.texAnim and res.texAnim.randomizeInit then
      p.texture = res.texAnim.textures[R.u32(12) % res.texAnim.frameCount + 1]
    elseif res.texAnim then
      p.texture = res.texAnim.textures[1]
    else
      p.texture = h.textureIndex
    end
    p.loopFactor = floor(0xFFFF / max(1, h.loopFrames))
    p.lifeFactor = floor(0xFFFF / p.life)
    p.rateOffset = h.randomizeLoopedAnim and R.u32(8) or 0
    table.insert(self.particles, 1, p)
  end
end

-- spl_anim.c, at a life rate 0..255
local function animScale(a, rate)
  local s, m, e = a.start * 4096, a.mid * 4096, a["end"] * 4096
  local v
  if rate < a.curveIn then v = s + trunc(rate * (m - s) / a.curveIn)
  elseif rate < a.curveOut then v = m
  else v = e + trunc((rate - 255) * (e - m) / (255 - a.curveOut)) end
  return v / 4096
end

local function rgb(c) return c % 32, floor(c / 32) % 32, floor(c / 1024) % 32 end
local function pack(r, g, b) return r + g * 32 + b * 1024 end

local function animColor(c, base, rate)
  if rate < c.curveIn then return c.start end
  if rate < c.curvePeak then
    local pr, pg, pb = rgb(base)
    if not c.interpolate then return base end
    local sr, sg, sb = rgb(c.start)
    local a, b = rate - c.curveIn, c.curvePeak - c.curveIn
    return pack(sr + trunc(a * (pr - sr) / b), sg + trunc(a * (pg - sg) / b), sb + trunc(a * (pb - sb) / b))
  end
  if rate < c.curveOut then
    local er, eg, eb = rgb(c["end"])
    if not c.interpolate then return c["end"] end
    local pr, pg, pb = rgb(base)
    local a, b = rate - c.curvePeak, c.curveOut - c.curvePeak
    return pack(pr + trunc(a * (er - pr) / b), pg + trunc(a * (eg - pg) / b), pb + trunc(a * (eb - pb) / b))
  end
  return c["end"]
end

local function animAlpha(a, rate, R)
  local v
  if rate < a.curveIn then v = trunc(rate * (a.mid - a.start) / a.curveIn) + a.start
  elseif rate < a.curveOut then v = a.mid
  else v = trunc((rate - 255) * (a["end"] - a.mid) / (255 - a.curveOut)) + a["end"] end
  return floor(R.scaled(v, a.randomRange)) % 32
end

local function animTexture(t, rate)
  for i = 0, t.frameCount - 1 do
    if rate < t.step * (i + 1) then return t.textures[i + 1] end
  end
end

local function behave(e, p, b, acc)
  if b.kind == "gravity" then
    acc[1], acc[2], acc[3] = acc[1] + b.x, acc[2] + b.y, acc[3] + b.z
  elseif b.kind == "random" then
    if b.interval > 0 and p.age % b.interval == 0 then
      acc[1] = acc[1] + e.R.range(b.x); acc[2] = acc[2] + e.R.range(b.y); acc[3] = acc[3] + e.R.range(b.z)
    end
  elseif b.kind == "magnet" then
    acc[1] = acc[1] + b.force * ((b.x - p.x) - p.vx)
    acc[2] = acc[2] + b.force * ((b.y - p.y) - p.vy)
    acc[3] = acc[3] + b.force * ((b.z - p.z) - p.vz)
  elseif b.kind == "spin" then
    local a = b.angle / 65536 * 2 * pi
    local c, s = cos(a), sin(a)
    if b.axis == 0 then p.y, p.z = p.y * c - p.z * s, p.y * s + p.z * c
    elseif b.axis == 1 then p.x, p.z = p.x * c + p.z * s, -p.x * s + p.z * c
    else p.x, p.y = p.x * c - p.y * s, p.x * s + p.y * c end
  elseif b.kind == "collision" then
    local y, ey = b.y, p.ey
    local crossed = (ey < y and ey + p.y > y) or (ey >= y and ey + p.y < y)
    if crossed then
      p.y = y - ey
      if b.type == 0 then p.age = p.life else p.vy = -(p.vy * b.elasticity) end
    end
  elseif b.kind == "convergence" then
    p.x = p.x + b.force * (b.x - p.x); p.y = p.y + b.force * (b.y - p.y); p.z = p.z + b.force * (b.z - p.z)
  end
end

-- one SPLManager_Update for this emitter: the start delay, SPLEmitter_Update,
-- and the self-maintaining end
function S:step()
  local h, res = self.h, self.res
  if not self.started and self.age >= h.startDelay then self.started, self.age = true, 0 end
  if (h.emitterLife == 0 or self.age < h.emitterLife) and h.emissionInterval > 0
     and self.age % h.emissionInterval == 0 and self.started and not self.terminated then
    self:emit()
  end
  local air = (h.airResistance + 384) / 512
  local keep = {}
  for _, p in ipairs(self.particles) do
    local rate = floor(p.lifeFactor * p.age / 256) % 256
    local loopRate = (p.rateOffset + floor(p.loopFactor * p.age / 256)) % 256
    if res.scale then p.animScale = animScale(res.scale, res.scale.loop and loopRate or rate) end
    if res.color and not res.color.randomStart then
      p.color = animColor(res.color, h.color, res.color.loop and loopRate or rate)
    end
    if res.alpha then p.animAlpha = animAlpha(res.alpha, res.alpha.loop and loopRate or rate, self.R) end
    if res.texAnim and not res.texAnim.randomizeInit then
      p.texture = animTexture(res.texAnim, res.texAnim.loop and loopRate or rate) or p.texture
    end
    if h.followEmitter then p.ex, p.ey, p.ez = self.x, self.y, self.z end
    local acc = { 0, 0, 0 }
    for _, b in ipairs(res.behaviors or {}) do behave(self, p, b, acc) end
    p.rotation = (p.rotation + p.angularVelocity) % 65536
    p.vx, p.vy, p.vz = p.vx * air + acc[1], p.vy * air + acc[2], p.vz * air + acc[3]
    p.x, p.y, p.z = p.x + p.vx, p.y + p.vy, p.z + p.vz
    p.age = p.age + 1
    if p.age <= p.life then keep[#keep + 1] = p end
  end
  self.particles = keep
  self.age = self.age + 1
end

function S:done()
  local h = self.h
  return h.selfMaintaining and h.emitterLife ~= 0 and self.started and self.age > h.emitterLife
         and #self.particles == 0
end

local meshFormat = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 },
                     { "VertexColor", "byte", 4 } }

-- draw(images, project): images[textureIndex] an Image (0-based keys);
-- project(x, y, z) -> screen x, y and pixels per unit at that depth (nil
-- behind the eye)
function S:draw(images, project)
  local h = self.h
  local verts = {}
  local byTex = {}
  for i = #self.particles, 1, -1 do
    local p = self.particles[i]
    local alpha = floor(p.baseAlpha * (p.animAlpha + 1) / 32)
    if alpha > 0 then
      local sy = p.baseScale
      local sx = sy * h.aspect
      if h.scaleAnimDir == 0 then sx, sy = sx * p.animScale, sy * p.animScale
      elseif h.scaleAnimDir == 1 then sx = sx * p.animScale
      else sy = sy * p.animScale end
      local X, Y, k = project(p.x + p.ex, p.y + p.ey, p.z + p.ez)
      if X then
        local a = p.rotation / 65536 * 2 * pi
        local c, s = cos(a), sin(a)
        local r, g, b = rgb(p.color)
        local col = { r / 31 * 255, g / 31 * 255, b / 31 * 255, alpha / 31 * 255 }
        local function corner(lx, ly, u, v)
          lx, ly = lx + h.polygonX, ly + h.polygonY
          local wx = (lx * sx) * c + (ly * sy) * -s
          local wy = (lx * sx) * s + (ly * sy) * c
          return { X + wx * k, Y - wy * k, u, v, col[1], col[2], col[3], col[4] }
        end
        local tS, tT = 2 ^ h.tileS * (h.flipS and -1 or 1), 2 ^ h.tileT * (h.flipT and -1 or 1)
        local q1, q2, q3, q4 = corner(-1, 1, 0, 0), corner(1, 1, tS, 0), corner(1, -1, tS, tT), corner(-1, -1, 0, tT)
        local key = p.texture or h.textureIndex
        local list = byTex[key] or {}
        byTex[key] = list
        list[#list + 1] = q1; list[#list + 1] = q2; list[#list + 1] = q3
        list[#list + 1] = q1; list[#list + 1] = q3; list[#list + 1] = q4
      end
    end
  end
  for key, list in pairs(byTex) do
    local mesh = love.graphics.newMesh(meshFormat, list, "triangles", "stream")
    local img = images and images[key]
    if img then mesh:setTexture(img) end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
    mesh:release()
  end
end

return S
