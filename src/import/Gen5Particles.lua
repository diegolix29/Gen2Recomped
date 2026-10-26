-- NITRO PARTICLE RESOURCES (SPA, " APS12_1"), as the SPL library loads them
-- (pret pokeheartgold lib/spl: SPLManager_LoadResources, spl_resource.h).
--
-- A 32-byte file header -- magic, version, u16 resource count, u16 texture
-- count, then sizes and the texture offset -- and the resources one after
-- another: an 88-byte SPLResourceHeader, then by its flags a scale animation
-- (12), colour (12), alpha (8), texture animation (12) and child resource
-- (20), then the behaviours (gravity 8, random 8, magnet 16, spin 4,
-- collision plane 8, convergence 16). The textures follow at texOffset, each
-- a 32-byte SPLTextureResource, its texels, and its palette at paletteOffset.
--
-- parse(bytes) -> { emitters = { ... }, textures = { {format, width, height,
-- palColor0, image = {width, height, rgba}} } } with every field read as the
-- library names it, fixed-point already turned to numbers (fx32 / fx16 at
-- 1/4096; colours as RGB555 integers; angles in u16 turns).

local P = {}

local floor = math.floor

local function u8(s, at) return s:byte(at + 1) or 0 end
local function u16(s, at) return u8(s, at) + u8(s, at + 1) * 256 end
local function s16(s, at) local v = u16(s, at) if v >= 32768 then v = v - 65536 end return v end
local function u32(s, at) return u16(s, at) + u16(s, at + 2) * 65536 end
local function s32(s, at) local v = u32(s, at) if v >= 2147483648 then v = v - 4294967296 end return v end
local function bits(v, from, count) return floor(v / 2 ^ from) % 2 ^ count end
local FX = 4096

P.HEADER, P.RES_HEADER = 32, 88

local function readHeader(d, at)
  local f = u32(d, at)
  local h = {
    flags = f,
    emissionType = bits(f, 0, 4), drawType = bits(f, 4, 2), circleAxis = bits(f, 6, 2),
    hasScaleAnim = bits(f, 8, 1) == 1, hasColorAnim = bits(f, 9, 1) == 1,
    hasAlphaAnim = bits(f, 10, 1) == 1, hasTexAnim = bits(f, 11, 1) == 1,
    hasRotation = bits(f, 12, 1) == 1, randomInitAngle = bits(f, 13, 1) == 1,
    selfMaintaining = bits(f, 14, 1) == 1, followEmitter = bits(f, 15, 1) == 1,
    hasChild = bits(f, 16, 1) == 1, polygonRotAxis = bits(f, 17, 2),
    polygonReferencePlane = bits(f, 19, 1), randomizeLoopedAnim = bits(f, 20, 1) == 1,
    drawChildrenFirst = bits(f, 21, 1) == 1, hideParent = bits(f, 22, 1) == 1,
    useViewSpace = bits(f, 23, 1) == 1,
    hasGravity = bits(f, 24, 1) == 1, hasRandom = bits(f, 25, 1) == 1,
    hasMagnet = bits(f, 26, 1) == 1, hasSpin = bits(f, 27, 1) == 1,
    hasCollision = bits(f, 28, 1) == 1, hasConvergence = bits(f, 29, 1) == 1,
    basePos = { s32(d, at + 4) / FX, s32(d, at + 8) / FX, s32(d, at + 12) / FX },
    emissionCount = s32(d, at + 16) / FX,
    radius = s32(d, at + 20) / FX,
    length = s32(d, at + 24) / FX,
    axis = { s16(d, at + 28) / FX, s16(d, at + 30) / FX, s16(d, at + 32) / FX },
    color = u16(d, at + 34),
    initVelPos = s32(d, at + 36) / FX,
    initVelAxis = s32(d, at + 40) / FX,
    baseScale = s32(d, at + 44) / FX,
    aspect = s16(d, at + 48) / FX,
    startDelay = u16(d, at + 50),
    minRotation = s16(d, at + 52), maxRotation = s16(d, at + 54),
    initAngle = u16(d, at + 56),
    emitterLife = u16(d, at + 60),
    particleLife = u16(d, at + 62),
  }
  local ra = u32(d, at + 64)
  h.randBaseScale, h.randLife, h.randInitVel = bits(ra, 0, 8), bits(ra, 8, 8), bits(ra, 16, 8)
  local m1, m2, m3 = u32(d, at + 68), u32(d, at + 72), u32(d, at + 76)
  h.emissionInterval, h.baseAlpha = bits(m1, 0, 8), bits(m1, 8, 8)
  h.airResistance, h.textureIndex = bits(m1, 16, 8), bits(m1, 24, 8)
  h.loopFrames, h.dbbScale = bits(m2, 0, 8), bits(m2, 8, 16)
  h.tileS, h.tileT = bits(m2, 24, 2), bits(m2, 26, 2)
  h.scaleAnimDir, h.dpolFaceEmitter = bits(m2, 28, 3), bits(m2, 31, 1)
  h.flipS, h.flipT = bits(m3, 0, 1) == 1, bits(m3, 1, 1) == 1
  h.polygonX, h.polygonY = s16(d, at + 80) / FX, s16(d, at + 82) / FX
  return h
end

function P.parse(d)
  if type(d) ~= "string" or #d < P.HEADER or d:sub(1, 4) ~= " APS" then return nil, "not an SPA" end
  local resCount, texCount = u16(d, 8), u16(d, 10)
  local texOffset = u32(d, 24)
  local out = { emitters = {}, textures = {} }
  local at = P.HEADER
  for i = 1, resCount do
    local e = { header = readHeader(d, at) }
    local h = e.header
    at = at + P.RES_HEADER
    if h.hasScaleAnim then
      local c = u16(d, at + 6)
      e.scale = { start = s16(d, at) / FX, mid = s16(d, at + 2) / FX, ["end"] = s16(d, at + 4) / FX,
                  curveIn = c % 256, curveOut = floor(c / 256), loop = u16(d, at + 8) % 2 == 1 }
      at = at + 12
    end
    if h.hasColorAnim then
      local c = u32(d, at + 4)
      local fl = u16(d, at + 8)
      e.color = { start = u16(d, at), ["end"] = u16(d, at + 2),
                  curveIn = bits(c, 0, 8), curvePeak = bits(c, 8, 8), curveOut = bits(c, 16, 8),
                  randomStart = fl % 2 == 1, loop = bits(fl, 1, 1) == 1, interpolate = bits(fl, 2, 1) == 1 }
      at = at + 12
    end
    if h.hasAlphaAnim then
      local a, fl, c = u16(d, at), u16(d, at + 2), u16(d, at + 4)
      e.alpha = { start = bits(a, 0, 5), mid = bits(a, 5, 5), ["end"] = bits(a, 10, 5),
                  randomRange = fl % 256, loop = bits(fl, 8, 1) == 1,
                  curveIn = c % 256, curveOut = floor(c / 256) }
      at = at + 8
    end
    if h.hasTexAnim then
      local frames = {}
      for k = 0, 7 do frames[k + 1] = u8(d, at + k) end
      local pr = u32(d, at + 8)
      e.texAnim = { textures = frames, frameCount = bits(pr, 0, 8), step = bits(pr, 8, 8),
                    randomizeInit = bits(pr, 16, 1) == 1, loop = bits(pr, 17, 1) == 1 }
      at = at + 12
    end
    if h.hasChild then
      local fl = u16(d, at)
      local m = u32(d, at + 12)
      e.child = { usesBehaviors = bits(fl, 0, 1) == 1, hasScaleAnim = bits(fl, 1, 1) == 1,
                  hasAlphaAnim = bits(fl, 2, 1) == 1, rotationType = bits(fl, 3, 2),
                  followEmitter = bits(fl, 5, 1) == 1, useChildColor = bits(fl, 6, 1) == 1,
                  drawType = bits(fl, 7, 2), polygonRotAxis = bits(fl, 9, 2), polygonReferencePlane = bits(fl, 11, 1),
                  randomInitVelMag = s16(d, at + 2) / FX, endScale = s16(d, at + 4) / FX,
                  life = u16(d, at + 6), velocityRatio = u8(d, at + 8), scaleRatio = u8(d, at + 9),
                  color = u16(d, at + 10),
                  emissionCount = bits(m, 0, 8), emissionDelay = bits(m, 8, 8),
                  emissionInterval = bits(m, 16, 8), texture = bits(m, 24, 8) }
      -- the bitfield's second word: tiling, flips, facing the emitter
      local m2 = u32(d, at + 16)
      e.child.tileS, e.child.tileT = bits(m2, 0, 2), bits(m2, 2, 2)
      e.child.flipS, e.child.flipT = bits(m2, 4, 1) == 1, bits(m2, 5, 1) == 1
      at = at + 20
    end
    e.behaviors = {}
    if h.hasGravity then
      e.behaviors[#e.behaviors + 1] = { kind = "gravity", x = s16(d, at) / FX, y = s16(d, at + 2) / FX, z = s16(d, at + 4) / FX }
      at = at + 8
    end
    if h.hasRandom then
      e.behaviors[#e.behaviors + 1] = { kind = "random", x = s16(d, at) / FX, y = s16(d, at + 2) / FX,
                                        z = s16(d, at + 4) / FX, interval = u16(d, at + 6) }
      at = at + 8
    end
    if h.hasMagnet then
      e.behaviors[#e.behaviors + 1] = { kind = "magnet", x = s32(d, at) / FX, y = s32(d, at + 4) / FX,
                                        z = s32(d, at + 8) / FX, force = s16(d, at + 12) / FX }
      at = at + 16
    end
    if h.hasSpin then
      e.behaviors[#e.behaviors + 1] = { kind = "spin", angle = u16(d, at), axis = u16(d, at + 2) }
      at = at + 4
    end
    if h.hasCollision then
      e.behaviors[#e.behaviors + 1] = { kind = "collision", y = s32(d, at) / FX, elasticity = s16(d, at + 4) / FX,
                                        type = u16(d, at + 6) % 4 }
      at = at + 8
    end
    if h.hasConvergence then
      e.behaviors[#e.behaviors + 1] = { kind = "convergence", x = s32(d, at) / FX, y = s32(d, at + 4) / FX,
                                        z = s32(d, at + 8) / FX, force = s16(d, at + 12) / FX }
      at = at + 16
    end
    out.emitters[i] = e
  end
  -- the textures
  local Models = require("src.import.Gen4Models")
  at = texOffset
  for i = 1, texCount do
    if at + 32 > #d then break end
    local param = u32(d, at + 4)
    local fmt, s, t = bits(param, 0, 4), bits(param, 4, 4), bits(param, 8, 4)
    local w, h = 8 * 2 ^ s, 8 * 2 ^ t
    local palOff, palSize = u32(d, at + 12), u32(d, at + 16)
    local size = u32(d, at + 28)
    local tex = { format = fmt, width = w, height = h, palColor0 = bits(param, 16, 1) == 1,
                  repeatMode = bits(param, 12, 2), flip = bits(param, 14, 2) }
    local parsed = { textures = { { format = fmt, width = w, height = h, offset = 0,
                                    transparent0 = tex.palColor0 } },
                     texBase = at + 32, palBase = at + palOff, palettes = { { offset = 0 } } }
    local ok, image = pcall(Models.decode, parsed, d, 1, 1)
    if ok and image then tex.image = image end
    out.textures[i] = tex
    if size <= 0 then break end
    at = at + size
  end
  return out
end

return P
