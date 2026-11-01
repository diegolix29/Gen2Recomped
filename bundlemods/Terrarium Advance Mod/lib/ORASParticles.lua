-- ORAS particle effects: NintendoWare CGFX files in GARC a/0/3/1 of the
-- player's dump (one per member; move timelines name them with SESD opcode
-- 0x2B, see lib/ORASWazaSeq.lua).
--
-- A file holds (DATA section, 16 name dictionaries; pointers are relative
-- to the field that holds them):
--   Models[0]   CMDL particle model: meshes, materials (MTOB), particle
--               shapes, and one particle set per effect layer (CNOD,
--               type 0x40000001)
--   Textures    TXOB image textures (PICA formats, IMAG pixel block)
--   Emitters    PEMT: which particle set to emit, rate, interval, duration,
--               start delay, spawn shape
--
-- Particle set: initializers (a particle's starting values) and updaters
-- (changes over its life).  Each entry is u32 type flag, u32 0x100, s32
-- attribute, then its values.  Attributes (from data, not yet confirmed in
-- game): 0 position, 1 scale, 2 rotation, 3 colour, 4 alpha, 5 texture
-- pattern, 8 scale over life, 11 life, 12 velocity.
--
-- Keyed curves (updater 0x100000 = vec3, 0x200000 = float in 16.16):
-- u32 tIn, u32 tOut (16-bit fractions of life), value v0, value v1,
-- slope sIn, slope sOut:  t < tIn: v0 + sIn*t;  tIn..tOut: v1;
-- t > tOut: v1 + sOut*(t - tOut).

local V = ...

local P = {}
P.GARC_PATH = "a/0/3/1"

P.ATTR = {
  [0] = "position", [1] = "scale", [2] = "rotation", [3] = "color", [4] = "alpha",
  [5] = "pattern", [6] = "attr6", [7] = "attr7", [8] = "scaleLife", [11] = "life",
  [12] = "velocity",
}

-- Spawn shapes of an emitter (type flag of the shape object).
P.SHAPE = {
  [0x10000000] = "point", [0x20000000] = "disc", [0x04000000] = "sphere",
  [0x40000000] = "cylinder", [0x80000000] = "rect", [0x08000000] = "rect2",
}

local function u16(s, p) local a, b = s:byte(p + 1, p + 2); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p + 1, p + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function s32(s, p) local v = u32(s, p); return v >= 0x80000000 and v - 0x100000000 or v end
local function f32(s, p)
  local v = u32(s, p)
  local sign = v >= 0x80000000 and -1 or 1
  local exp = math.floor(v / 0x800000) % 256
  local man = v % 0x800000
  if exp == 0 then return man == 0 and 0 or sign * man * 2 ^ -149 end
  if exp == 255 then return man == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + man / 0x800000) * 2 ^ (exp - 127)
end
local function fx16(s, p) return s32(s, p) / 65536 end

-- All offsets below are 0-based byte positions in the file.
local function rel(s, p)
  local v = s32(s, p)
  if v == 0 then return nil end
  return p + v
end
local function cstr(s, p)
  if not p or p < 0 or p >= #s then return nil end
  local e = s:find("\0", p + 1, true)
  return s:sub(p + 1, (e or #s + 1) - 1)
end

local function readDict(s, at)
  if not at or s:sub(at + 1, at + 4) ~= "DICT" then return {} end
  local out = {}
  for k = 0, u32(s, at + 8) - 1 do
    local e = at + 28 + k * 16
    out[#out + 1] = { name = cstr(s, rel(s, e + 8)), at = rel(s, e + 12) }
  end
  return out
end

local function vec3(s, p) return { f32(s, p), f32(s, p + 4), f32(s, p + 8) } end
local function floats(s, p, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = f32(s, p + i * 4) end
  return t
end

-- ------------------------------------------------------------ particle sets

local function curveVec3(s, p)
  return {
    tIn = u32(s, p + 16) / 65536, tOut = u32(s, p + 20) / 65536,
    v0 = vec3(s, p + 24), v1 = vec3(s, p + 36),
    sIn = vec3(s, p + 48), sOut = vec3(s, p + 60),
  }
end
local function curveFloat(s, p)
  return {
    tIn = u32(s, p + 16) / 65536, tOut = u32(s, p + 20) / 65536,
    v0 = fx16(s, p + 24), v1 = fx16(s, p + 28),
    sIn = fx16(s, p + 32), sOut = fx16(s, p + 36),
  }
end

-- One initializer or updater.  `size` is the distance to the next object
-- (raw values beyond the known fields are kept in .raw).
local function readEntry(s, p, size, isUpdater)
  local e = { flag = u32(s, p), attr = s32(s, p + 8) }
  e.attrName = P.ATTR[e.attr]
  local n = math.max(0, math.floor(((size or 16) - 12) / 4))
  e.raw = floats(s, p + 12, math.min(n, 64))
  if isUpdater then
    if e.flag == 0x100000 then e.curve = curveVec3(s, p)
    elseif e.flag == 0x200000 then e.curve = curveFloat(s, p) end
  else
    -- initializers are short: value(s) then random spread
    if e.flag == 0x200000 then e.value = vec3(s, p + 12); e.random = f32(s, p + 24)
    elseif e.flag == 0x4000000 then e.value = vec3(s, p + 12)
    elseif e.flag == 0x2000000 then e.value = f32(s, p + 12); e.random = f32(s, p + 16)
    elseif e.flag == 0x1000000 then e.value = f32(s, p + 12); e.random = f32(s, p + 16)
    elseif e.flag == 0x100000 then e.value = vec3(s, p + 12); e.random = vec3(s, p + 24)
    end
  end
  return e
end

-- Attribute layout of a particle set (pointer at +0x30): u32 1, u32 count,
-- pointer to a list of entries {u32 flag, u32 attr, ...}.  flag 0x80000000:
-- stored per particle; 0x40000000: constant for the set, followed by u32
-- count, u32 components, u32 component size and the value(s).  Ember's fire:
-- life 15, rotation (-pi/2, 0, 0), texcoord scale (0.125, 1) for its 8-frame
-- flipbook.
local function readAttributes(s, at)
  local out = { perParticle = {}, constant = {} }
  if not at then return out end
  local n, list = u32(s, at + 4), rel(s, at + 8)
  if not list or n > 32 then return out end
  for k = 0, n - 1 do
    local q = rel(s, list + 4 * k)
    if q then
      local flag, attr = u32(s, q), u32(s, q + 4)
      if flag == 0x40000000 then
        local comps = u32(s, q + 12)
        if comps >= 1 and comps <= 4 then
          local v = floats(s, q + 20, comps)
          out.constant[attr] = comps == 1 and v[1] or v
        end
      else
        out.perParticle[attr] = true
      end
    end
  end
  return out
end

local function readSet(s, o)
  local set = { at = o, name = cstr(s, rel(s, o + 0x0C)), initializers = {}, updaters = {} }
  set.attributes = readAttributes(s, rel(s, o + 0x30))
  -- orientation object (+0x44): 0x80000000 camera billboard, 0x20000000
  -- upright (Y axis) billboard, 0x10000000 flat quad turned by the particle
  -- rotation (default plane XZ); then u32 1 and a pivot (x, y): y = -1 puts
  -- the pivot at the quad's bottom so flames grow up.
  local ob = rel(s, o + 0x44)
  if ob then
    local f = u32(s, ob)
    set.orient = (f == 0x80000000 and "billboard") or (f == 0x20000000 and "upright")
      or (f == 0x10000000 and "oriented") or ("0x%X"):format(f)
    set.pivot = { f32(s, ob + 8), f32(s, ob + 12) }
  end
  local ptrs, coll = {}, ob
  for _, spec in ipairs({ { "initializers", 0x34, 0x38 }, { "updaters", 0x3C, 0x40 } }) do
    local n, t = u32(s, o + spec[2]), rel(s, o + spec[3])
    if t and n < 64 then
      for k = 0, n - 1 do
        local q = rel(s, t + 4 * k)
        if q then ptrs[#ptrs + 1] = { list = spec[1], at = q } end
      end
    end
  end
  local addrs = {}
  for _, x in ipairs(ptrs) do addrs[#addrs + 1] = x.at end
  if coll then addrs[#addrs + 1] = coll end
  table.sort(addrs)
  for _, x in ipairs(ptrs) do
    local size
    for _, a in ipairs(addrs) do if a > x.at then size = a - x.at; break end end
    local list = set[x.list]
    list[#list + 1] = readEntry(s, x.at, size, x.list == "updaters")
  end
  return set
end

-- ------------------------------------------------------------------ emitters

local function readEmitter(s, o, name)
  local em = {
    at = o, name = name,
    set = cstr(s, rel(s, o + 0xB8)),
    flagA = u32(s, o + 0xC0),
    ratio = f32(s, o + 0xC4), ratioRandom = f32(s, o + 0xC8),
    interval = u32(s, o + 0xCC), intervalRandom = f32(s, o + 0xD0),
    flagB = u32(s, o + 0xD4),
    duration = u32(s, o + 0xD8), delay = u32(s, o + 0xDC),
    scale = vec3(s, o + 0x30), rotate = vec3(s, o + 0x3C), translate = vec3(s, o + 0x48),
  }
  local sh = rel(s, o + 0xBC)
  if sh then
    local flag = u32(s, sh)
    em.shape = { flag = flag, kind = P.SHAPE[flag] or ("0x%X"):format(flag),
                 raw = floats(s, sh + 4, 8) }
  end
  return em
end

-- ------------------------------------------------------------------ textures

local function readTexture(s, o, name)
  local t = {
    name = name, height = u32(s, o + 0x18), width = u32(s, o + 0x1C),
    mipmaps = u32(s, o + 0x28), format = u32(s, o + 0x34),
  }
  local img = rel(s, o + 0x38)
  if img then
    t.length = u32(s, img + 8)
    t.dataAt = rel(s, img + 12)
  end
  return t
end

-- ----------------------------------------------------------------- materials

-- PICA blend function register (MTOB +0x148): bits 16-19 source RGB factor,
-- 20-23 destination RGB factor.  0x16160000 = additive (src alpha, one),
-- 0x76760000 = normal (src alpha, 1 - src alpha).
local FACTOR = { [0] = "zero", "one", "srcColor", "oneMinusSrcColor", "dstColor",
  "oneMinusDstColor", "srcAlpha", "oneMinusSrcAlpha", "dstAlpha", "oneMinusDstAlpha" }

local function readMaterial(s, o, limit)
  local m = { name = cstr(s, rel(s, o + 0x0C)) }
  local bf = u32(s, o + 0x148)
  m.blendSrc = FACTOR[math.floor(bf / 0x10000) % 16]
  m.blendDst = FACTOR[math.floor(bf / 0x100000) % 16]
  m.blend = (m.blendDst == "one" and "add")
    or (m.blendDst == "oneMinusSrcAlpha" and "alpha")
    or (m.blendSrc == "dstColor" and "multiply")
    or (m.blendDst == "zero" and "replace") or "alpha"
  -- texture: the first texture reference (TXOB type 0x20000004) after it
  local a = s:find("\4\0\0\32TXOB", o + 1, true)
  if a and (not limit or a - 1 < limit) then
    local q = a - 1
    m.texture = cstr(s, rel(s, q + 0x18))   -- +0x18: referenced texture name
  end
  return m
end

-- ---------------------------------------------------------------------- API

-- bytes -> { textures, sets, emitters, setByName }  or nil, why
function P.parse(bytes)
  if type(bytes) ~= "string" or bytes:sub(1, 4) ~= "CGFX" then return nil, "not a CGFX file" end
  local data = u16(bytes, 6)
  if bytes:sub(data + 1, data + 4) ~= "DATA" then return nil, "CGFX has no DATA section" end
  local function dictAt(k)
    if u32(bytes, data + 8 + k * 8) == 0 then return {} end
    return readDict(bytes, rel(bytes, data + 12 + k * 8))
  end
  local out = { textures = {}, sets = {}, emitters = {}, setByName = {}, textureByName = {} }
  for _, e in ipairs(dictAt(1)) do
    if e.at then
      local t = readTexture(bytes, e.at, e.name)
      out.textures[#out.textures + 1] = t
      out.textureByName[t.name] = t
    end
  end
  for _, e in ipairs(dictAt(15)) do
    if e.at and bytes:sub(e.at + 5, e.at + 8) == "PEMT" then
      out.emitters[#out.emitters + 1] = readEmitter(bytes, e.at, e.name)
    end
  end
  -- materials (MTOB) inside the model, keyed by name ("<set>Material")
  out.materials, out.materialByName = {}, {}
  local starts, from = {}, 1
  while true do
    local a = bytes:find("\0\0\0\8MTOB", from, true)
    if not a then break end
    starts[#starts + 1] = a - 1
    from = a + 8
  end
  for i, o in ipairs(starts) do
    local m = readMaterial(bytes, o, starts[i + 1])
    if m.name then
      out.materials[#out.materials + 1] = m
      out.materialByName[m.name] = m
    end
  end

  -- particle sets live inside the model; find them by tag and keep the ones
  -- whose name resolves
  from = 1
  while true do
    local a = bytes:find("\1\0\0\64CNOD", from, true)
    if not a then break end
    local o = a - 1
    local set = readSet(bytes, o)
    if set.name then
      set.material = out.materialByName[set.name .. "Material"]
      out.sets[#out.sets + 1] = set
      out.setByName[set.name] = set
    end
    from = a + 8
  end
  return out
end

-- RGBA ImageData for one parsed texture (needs love.image).
function P.texturePixels(bytes, tex)
  if not tex.dataAt then return nil, "texture has no pixels" end
  local PICA = V and V.require and V.require("PICA")
  if not PICA then return nil, "PICA decoder unavailable" end
  return PICA.decodeTexture(bytes, tex.dataAt, tex.width, tex.height, tex.format)
end

-- Value of a keyed curve at life fraction t (0..1); vec3 curves return a table.
function P.curveAt(c, t)
  local function at(v0, v1, sIn, sOut)
    if t < c.tIn then return v0 + sIn * t end
    if t <= c.tOut then return v1 end
    return v1 + sOut * (t - c.tOut)
  end
  if type(c.v0) == "table" then
    return { at(c.v0[1], c.v1[1], c.sIn[1], c.sOut[1]),
             at(c.v0[2], c.v1[2], c.sIn[2], c.sOut[2]),
             at(c.v0[3], c.v1[3], c.sIn[3], c.sOut[3]) }
  end
  return at(c.v0, c.v1, c.sIn, c.sOut)
end

-- rom: an N3DSRom, G: the GARC module.
function P.loadMember(rom, G, member)
  local file = rom:file(P.GARC_PATH)
  if not file then return nil, "dump has no " .. P.GARC_PATH end
  local g, err = G.open(rom, file)
  if not g then return nil, err end
  local bytes, why = g:member(member)
  if not bytes then return nil, why end
  local fx, perr = P.parse(bytes)
  if not fx then return nil, perr end
  fx.bytes = bytes
  return fx
end

return P
