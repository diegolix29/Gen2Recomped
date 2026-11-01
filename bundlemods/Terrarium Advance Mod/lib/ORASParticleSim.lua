-- Plays one ORAS particle file (lib/ORASParticles.lua parse result) frame by
-- frame, without drawing.  Effects run at 30 frames per second like the
-- move timelines (lib/ORASWazaSeq.lua).
--
--   local e = Sim.new(fx, { seed = 1 })
--   Sim.step(e)            -- one frame
--   for _, q in ipairs(Sim.quads(e)) do ... end
--
-- A quad: x, y, z (effect space, emitter origin = 0), w, h (full size),
-- rot {x, y, z} radians, orient ("billboard" camera-facing, "upright" turns
-- about Y only, "oriented" flat quad in the XZ plane turned by rot), pivot
-- {x, y} (-1 = pivot at the left / bottom edge), r, g, b, a, u0, v0, u1, v1,
-- texture name, blend ("add", "alpha", "multiply", "replace").
--
-- Behaviour coverage: see context.md "ORAS move effects".  Unknown
-- initializers / updaters are skipped, so a layer may move less than in the
-- game, but it still draws.

local V = ...

local Sim = {}

local A_POS, A_SCALE, A_ROT, A_COLOR, A_ALPHA, A_PAT, A_UV, A_SCALELIFE, A_LIFE, A_VEL =
  0, 1, 2, 3, 4, 5, 6, 8, 11, 12

-- small deterministic RNG (xorshift) so previews and replays match
local function rng(seed)
  local s = (seed or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function()
    s = (s * 16807) % 2147483647
    return (s - 1) / 2147483646
  end
end

local function randomDir(rand)
  local z = rand() * 2 - 1
  local t = rand() * math.pi * 2
  local r = math.sqrt(math.max(0, 1 - z * z))
  return r * math.cos(t), z, r * math.sin(t)
end

local function curveAt(c, t)
  local function at(v0, v1, sIn, sOut)
    if t < c.tIn then return v0 + sIn * t end
    if t <= c.tOut then return v1 end
    return v1 + sOut * (t - c.tOut)
  end
  if type(c.v0) == "table" then
    return at(c.v0[1], c.v1[1], c.sIn[1], c.sOut[1]),
           at(c.v0[2], c.v1[2], c.sIn[2], c.sOut[2]),
           at(c.v0[3], c.v1[3], c.sIn[3], c.sOut[3])
  end
  return at(c.v0, c.v1, c.sIn, c.sOut)
end

-- texture pattern table (updater 0x40000): u32 count at payload word 7, the
-- frame numbers are floats from payload word 16 on
local function patternFrames(u)
  local raw = u.raw
  local n = raw[7] and math.floor(raw[7] * 2 ^ 149 + 0.5) or 0   -- stored as int
  if n <= 0 or n > 256 then return nil end
  local t = {}
  for i = 1, n do
    local v = raw[15 + i]
    if v == nil then return nil end
    t[i] = v
  end
  return t
end

Sim.patternFrames = patternFrames

local function asVec(v, d)
  if type(v) == "table" then return v[1] or d, v[2] or d, v[3] or d end
  if type(v) == "number" then return v, v, v end
  return d, d, d
end

-- Prepare per-set behaviour once.
local function compileSet(set)
  local c = set.attributes and set.attributes.constant or {}
  local b = {
    set = set, name = set.name,
    orient = set.orient or "billboard", pivot = set.pivot or { 0, 0 },
    texture = set.material and set.material.texture,
    blend = set.material and set.material.blend or "add",
    life = type(c[A_LIFE]) == "number" and c[A_LIFE] or 30,
    init = {}, upd = {},
  }
  b.scale = { asVec(c[A_SCALE], 1) }
  b.rot = { asVec(c[A_ROT], 0) }
  b.color = { asVec(c[A_COLOR], 1) }
  b.alpha = type(c[A_ALPHA]) == "number" and c[A_ALPHA] or 1
  b.pattern = type(c[A_PAT]) == "table" and c[A_PAT][1] or (type(c[A_PAT]) == "number" and c[A_PAT]) or 0
  local uv = c[A_UV]
  b.uvScale = type(uv) == "table" and { uv[1], uv[2] } or { 1, 1 }
  for _, it in ipairs(set.initializers or {}) do b.init[#b.init + 1] = it end
  for _, u in ipairs(set.updaters or {}) do
    if u.flag == 0x40000 and u.attr == A_PAT and not u.frames then u.frames = patternFrames(u) end
    b.upd[#b.upd + 1] = u
  end
  return b
end

-- Shape values (raw): [2] inner fraction (emit between inner*size and size;
-- 1 = surface only), [3] arc in radians, [6..8] size x, y, z.  Ember's target
-- side: flames on a cylinder radius 10 height 15 (inner 1), sparks in a
-- sphere radius 15 (inner 0.75).
local function spawnOffset(shape, rand)
  if not shape then return 0, 0, 0 end
  local r = shape.raw or {}
  local inner = math.max(0, math.min(1, r[2] or 0))
  local arc = (r[3] and r[3] > 0) and r[3] or math.pi * 2
  local function radial() return inner + (1 - inner) * math.sqrt(rand()) end
  if shape.kind == "disc" then
    local a, d = rand() * arc, radial()
    return math.cos(a) * d * (r[6] or 1), 0, math.sin(a) * d * (r[7] or r[6] or 1)
  elseif shape.kind == "sphere" then
    local x, y, z = randomDir(rand)
    local d = radial()
    return x * d * (r[6] or 1), y * d * (r[7] or 1), z * d * (r[8] or 1)
  elseif shape.kind == "cylinder" then
    local a, d = rand() * arc, radial()
    return math.cos(a) * d * (r[6] or 1), (rand() - 0.5) * (r[7] or 0), math.sin(a) * d * (r[8] or 1)
  end
  return 0, 0, 0
end

-- R = Rz * Ry * Rx (the emitter's own rotation)
local function rotXYZ(r, x, y, z)
  if not r or (r[1] == 0 and r[2] == 0 and r[3] == 0) then return x, y, z end
  local cx, sx = math.cos(r[1]), math.sin(r[1])
  y, z = y * cx - z * sx, y * sx + z * cx
  local cy, sy = math.cos(r[2]), math.sin(r[2])
  x, z = x * cy + z * sy, -x * sy + z * cy
  local cz, sz = math.cos(r[3]), math.sin(r[3])
  x, y = x * cz - y * sz, x * sz + y * cz
  return x, y, z
end

local function newParticle(e, em, b, rand)
  local ox, oy, oz = spawnOffset(em.shape, rand)
  local t = em.translate or { 0, 0, 0 }
  local p = {
    b = b, age = 0, life = b.life,
    x = ox, y = oy, z = oz,
    vx = 0, vy = 0, vz = 0,
    sx = b.scale[1], sy = b.scale[2], sz = b.scale[3],
    rx = b.rot[1], ry = b.rot[2], rz = b.rot[3],
    r = b.color[1], g = b.color[2], bl = b.color[3], a = b.alpha,
    lsx = 1, lsy = 1, lsz = 1,
    pat = b.pattern,
  }
  for _, it in ipairs(b.init) do
    local f, at, raw = it.flag, it.attr, it.raw
    if at == A_SCALE and it.value then
      local k = 1 + (rand() * 2 - 1) * (it.random or 0)
      p.sx, p.sy, p.sz = it.value[1] * k, it.value[2] * k, it.value[3] * k
    elseif at == A_COLOR and it.value then
      p.r, p.g, p.bl = it.value[1], it.value[2], it.value[3]
    elseif at == A_ALPHA and type(it.value) == "number" then
      p.a = it.value * (1 - (it.random or 0) * rand())
    elseif at == A_ROT and type(it.value) == "table" then
      local rr = it.random or { 0, 0, 0 }
      p.rx = it.value[1] * (1 - rr[1] * rand())
      p.ry = it.value[2] * (1 - rr[2] * rand())
      p.rz = it.value[3] * (1 - rr[3] * rand())
    elseif at == A_PAT and raw[1] then
      p.pat = raw[1]
    elseif at == A_LIFE and type(it.value) == "number" then
      p.life = math.max(1, it.value + (rand() * 2 - 1) * (it.random or 0))
    elseif at == A_VEL then
      local speed = raw[1] or 0
      if f == 0x20000000 then                      -- random direction
        local x, y, z = randomDir(rand)
        p.vx, p.vy, p.vz = x * speed, y * speed, z * speed
      elseif f == 0x80000000 then                  -- fixed direction
        p.vx, p.vy, p.vz = (raw[2] or 0) * speed, (raw[3] or 0) * speed, (raw[4] or 0) * speed
      elseif f == 0x40000000 then                  -- direction with cone
        local cone = raw[5] or 0
        local x, y, z = randomDir(rand)
        local dx, dy, dz = raw[2] or 0, raw[3] or 1, raw[4] or 0
        local k = math.sin(cone)
        local vx, vy, vz = dx + x * k, dy + y * k, dz + z * k
        local len = math.sqrt(vx * vx + vy * vy + vz * vz)
        if len > 0 then p.vx, p.vy, p.vz = vx / len * speed, vy / len * speed, vz / len * speed end
      elseif f == 0x80000 or f == 0x10000000 or f == 0x8000000 then  -- away from origin
        local len = math.sqrt(ox * ox + oy * oy + oz * oz)
        if len < 1e-6 then ox, oy, oz = randomDir(rand); len = 1 end
        if f == 0x8000000 then                     -- outward from the Y axis
          oy = 0; len = math.sqrt(ox * ox + oz * oz)
          if len < 1e-6 then local a = rand() * math.pi * 2; ox, oz, len = math.cos(a), math.sin(a), 1 end
        end
        p.vx, p.vy, p.vz = ox / len * speed, oy / len * speed, oz / len * speed
      end
    end
  end
  -- spawn point and starting velocity are in the emitter's frame: turn them
  -- by its rotation (Thundershock's hit emitter is turned -90 deg on Z), then
  -- place it
  local rot = em.rotate
  p.x, p.y, p.z = rotXYZ(rot, p.x, p.y, p.z)
  p.vx, p.vy, p.vz = rotXYZ(rot, p.vx, p.vy, p.vz)
  p.x, p.y, p.z = p.x + t[1], p.y + t[2], p.z + t[3]
  return p
end

local function updateParticle(p, rand)
  local b = p.b
  local t = p.age / p.life
  for _, u in ipairs(b.upd) do
    local f, at = u.flag, u.attr
    if u.curve then
      if at == A_COLOR then p.r, p.g, p.bl = curveAt(u.curve, t)
      elseif at == A_ALPHA then p.a = curveAt(u.curve, t)
      elseif at == A_SCALELIFE then p.lsx, p.lsy, p.lsz = curveAt(u.curve, t)
      elseif at == A_SCALE then p.sx, p.sy, p.sz = curveAt(u.curve, t) end
    elseif f == 0x40000 and at == A_PAT and u.frames then
      local n = #u.frames
      p.pat = u.frames[math.min(n, math.floor(t * n) + 1)]
    elseif at == A_VEL and f == 0x80000000 then          -- drag
      local k = u.raw[2] or 1
      p.vx, p.vy, p.vz = p.vx * k, p.vy * k, p.vz * k
    elseif at == A_VEL and f == 0x20000000 then          -- gravity / wind
      local k = u.raw[2] or 0
      p.vx = p.vx + (u.raw[3] or 0) * k
      p.vy = p.vy + (u.raw[4] or 0) * k
      p.vz = p.vz + (u.raw[5] or 0) * k
    elseif at == A_ROT and f == 0x80000 then             -- spin
      p.rx = p.rx + (u.raw[2] or 0)
      p.ry = p.ry + (u.raw[3] or 0)
      p.rz = p.rz + (u.raw[4] or 0)
    end
  end
  p.x, p.y, p.z = p.x + p.vx, p.y + p.vy, p.z + p.vz
end

function Sim.new(fx, opts)
  opts = opts or {}
  local e = { frame = 0, particles = {}, emitters = {}, rand = rng(opts.seed or 1) }
  local compiled = {}
  for _, set in ipairs(fx.sets or {}) do compiled[set.name] = compileSet(set) end
  for _, em in ipairs(fx.emitters or {}) do
    local b = compiled[em.set]
    if b then
      e.emitters[#e.emitters + 1] = { em = em, b = b, carry = 0 }
    end
  end
  return e
end

-- No more particles from now on; the live ones finish their lives.
function Sim.stopEmitting(e) e.stopped = true end

-- Has every emitter finished and every particle died?
function Sim.done(e)
  if #e.particles > 0 then return false end
  if e.stopped then return true end
  for _, x in ipairs(e.emitters) do
    local em = x.em
    if em.duration >= 360 or e.frame < (em.delay or 0) + (em.duration or 1) then return false end
  end
  return true
end

function Sim.step(e)
  local rand = e.rand
  for _, x in ipairs(e.emitters) do
    local em = x.em
    local local_ = e.frame - (em.delay or 0)
    local dur = em.duration or 1
    local interval = math.max(1, em.interval or 1)
    if not e.stopped and local_ >= 0 and (dur >= 360 or local_ < dur) and local_ % interval == 0 then
      local n = (em.ratio or 1) + (rand() * 2 - 1) * (em.ratioRandom or 0) * (em.ratio or 1) + x.carry
      local whole = math.floor(n)
      x.carry = n - whole
      for _ = 1, whole do
        e.particles[#e.particles + 1] = newParticle(e, em, x.b, rand)
      end
    end
  end
  local keep = {}
  for _, p in ipairs(e.particles) do
    updateParticle(p, rand)
    p.age = p.age + 1
    if p.age < p.life then keep[#keep + 1] = p end
  end
  e.particles = keep
  e.frame = e.frame + 1
end

function Sim.quads(e)
  local out = {}
  for _, p in ipairs(e.particles) do
    local b = p.b
    local su, sv = b.uvScale[1], b.uvScale[2]
    local frame = math.floor((p.pat or 0) + 0.5)
    local cols = su > 0 and math.max(1, math.floor(1 / su + 0.5)) or 1
    local u0 = (frame % cols) * su
    local v0 = math.floor(frame / cols) * sv
    out[#out + 1] = {
      x = p.x, y = p.y, z = p.z, vx = p.vx, vy = p.vy, vz = p.vz,
      w = p.sx * p.lsx, h = p.sy * p.lsy,
      rot = { p.rx, p.ry, p.rz }, orient = b.orient, pivot = b.pivot,
      r = p.r, g = p.g, b = p.bl, a = math.max(0, math.min(1, p.a)),
      u0 = u0, v0 = v0, u1 = u0 + su, v1 = v0 + sv,
      texture = b.texture, blend = b.blend, layer = b.name,
    }
  end
  return out
end

return Sim
