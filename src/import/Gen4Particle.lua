-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) PARTICLE FILES -- the `SPA ` programs a move's animation
-- loads, and the textures inside them, which are the actual visible burst.
--
-- `Gen4MoveAnim` decodes the program that says WHICH effect to play;
-- `loadparticlesystem 0, 40` is Scratch's. This reads what is at index 40: a
-- particle file holding its emitters and the pictures they throw.
--
-- THREE CLAIMS, ALL ARITHMETIC, ALL CHECKED OVER ALL 608 PARTICLE FILES.
-- Nothing here is a guessed field. A header is only believed when a number in
-- it predicts another number exactly, and `tools/gen4_particle_check.lua`
-- asserts every one:
--
--   1. 0x20 + emitterDataSize == textureOffset      -- the emitter area ends
--                                                      where the textures begin
--   2. textureOffset + textureDataSize == file size -- and the textures end
--                                                      where the file does
--   3. width * height == textureDataSize            -- every texture is 8bpp,
--                                                      and its own header says
--                                                      what its shape is
--
-- All three hold for 608 of 608 files and 1,724 of 1,724 texture blocks.
--
-- !! THE MAGICS ARE STORED BACKWARDS, and reading them forwards costs an hour.
-- The file's is ' APS' and a texture block's is ' TPS' -- 'SPA ' and 'SPT ' as
-- little-endian words. Comparing against "TPS " instead of " TPS" found the
-- magic in 34 of 608 files and looked like a format that varied; it does not.

local Gen4Particle = {}

local floor = math.floor
local byte, sub = string.byte, string.sub

Gen4Particle.MAGIC = " APS"          -- 'SPA ' as a little-endian word
Gen4Particle.TEXTURE_MAGIC = " TPS"  -- 'SPT ', the same way
Gen4Particle.VERSION = "12_1"        -- '1_21', likewise
Gen4Particle.HEADER_BYTES = 0x20
Gen4Particle.TEXTURE_HEADER_BYTES = 0x20

-- The archives, and what is in them.
Gen4Particle.ARCHIVE_MOVES = "/wazaeffect/effectdata/waza_particle.narc"
Gen4Particle.ARCHIVE_BALLS = "/wazaeffect/effectdata/ball_particle.narc"
Gen4Particle.ARCHIVE_FIELD = "/particledata/particledata.narc"
Gen4Particle.MOVE_COUNT = 485
Gen4Particle.BALL_COUNT = 117

-- THE TWO PIXEL FORMATS, and there are only two: every particle texture in the
-- cartridge is EIGHT BITS PER PIXEL with the alpha packed in beside the index,
-- which is why claim 3 above is a plain multiplication rather than a table of
-- bits-per-pixel. 1,382 blocks are A5I3 and 342 are A3I5; nothing else occurs.
--   A3I5: 5-bit palette index, 3-bit alpha   (fine colour, coarse edge)
--   A5I3: 3-bit palette index, 5-bit alpha   (few colours, smooth edge)
-- A particle is mostly a soft-edged white shape, which is why the second is
-- four times as common.
Gen4Particle.FORMAT_A3I5 = 1
Gen4Particle.FORMAT_A5I3 = 6
Gen4Particle.FORMATS = { [1] = "a3i5", [6] = "a5i3" }

local function u16(data, at)
  local a, b = byte(data, at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end

local function u32(data, at)
  local a, b, c, d = byte(data, at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- header(data) -> { emitters, textures, emitterBytes, textureBytes,
--                   textureAt, version } or nil, why
function Gen4Particle.header(data)
  if type(data) ~= "string" or #data < Gen4Particle.HEADER_BYTES then
    return nil, "too short to be a particle file"
  end
  if sub(data, 1, 4) ~= Gen4Particle.MAGIC then
    return nil, "not an SPA file"
  end
  local out = {
    version = sub(data, 5, 8),
    emitters = u16(data, 8),
    textures = u16(data, 10),
    emitterBytes = u32(data, 0x10),
    textureBytes = u32(data, 0x14),
    textureAt = u32(data, 0x18),
    bytes = #data,
  }
  if not (out.emitters and out.textureAt and out.textureBytes) then
    return nil, "header is truncated"
  end
  return out
end

-- Does this file's own arithmetic hold? Separated from `header` so a caller can
-- read a file it already trusts without paying for the check, and so the check
-- tool asks the same question the extractor does rather than a similar one.
function Gen4Particle.consistent(head)
  if not head then return false, "no header" end
  if Gen4Particle.HEADER_BYTES + head.emitterBytes ~= head.textureAt then
    return false, ("emitters end at %d but textures begin at %d")
      :format(Gen4Particle.HEADER_BYTES + head.emitterBytes, head.textureAt)
  end
  if head.textureAt + head.textureBytes ~= head.bytes then
    return false, ("textures end at %d but the file is %d")
      :format(head.textureAt + head.textureBytes, head.bytes)
  end
  return true
end

-- WHERE A TEXTURE'S SHAPE IS WRITTEN. One word, and it took correlating 1,724
-- blocks against their own data sizes to read it rather than guessing at the
-- DS's TexImageParam layout, which this is NOT:
--   bits 0-2  format        (1 or 6, and only ever those)
--   bits 4-6  width  as an exponent, 8 << n
--   bits 8-10 height as an exponent, 8 << n
-- Everything above is flags this port does not need. The proof that the reading
-- is right is claim 3: width * height comes out EXACTLY equal to the texture's
-- own declared byte count on every block in the cartridge, and a wrong bit
-- offset does not do that once, let alone 1,724 times.
-- SPELLED AS A TABLE RATHER THAN `8 * 2 ^ n`, because that expression is FLOAT
-- division's cousin: in Lua 5.3 `2 ^ 2` is 4.0, so a width came out 32.0, the
-- shape key read "32.0x32.0", and everything downstream that expected an
-- integer -- a pixel loop, an image header, a table key -- quietly took a float.
-- The eight entries are every size the hardware has.
Gen4Particle.SIZES = { [0] = 8, 16, 32, 64, 128, 256, 512, 1024 }

function Gen4Particle.shape(param)
  if not param then return nil end
  local w = Gen4Particle.SIZES[floor(param / 16) % 8]
  local h = Gen4Particle.SIZES[floor(param / 256) % 8]
  if not (w and h) then return nil end
  return { format = param % 8, width = w, height = h }
end

-- textures(data) -> { { format, width, height, pixels, palette }, ... }
--
-- `palette` is a flat list of { r, g, b } 0-255, and it is TRIMMED: the
-- cartridge stores only the colours a texture uses, so most are two entries
-- long and an index past the end is the file saying "transparent", not a fault.
function Gen4Particle.textures(data)
  local head, why = Gen4Particle.header(data)
  if not head then return nil, why end
  local out, at, n = {}, head.textureAt, 0
  while n < head.textures do
    if at + Gen4Particle.TEXTURE_HEADER_BYTES > #data then
      return nil, ("texture %d runs past the end"):format(n)
    end
    if sub(data, at + 1, at + 4) ~= Gen4Particle.TEXTURE_MAGIC then
      return nil, ("texture %d has no SPT header"):format(n)
    end
    local param = u32(data, at + 4)
    local texBytes = u32(data, at + 8)
    local palAt = u32(data, at + 12)
    local palBytes = u32(data, at + 16)
    local total = u32(data, at + 28)
    local shape = Gen4Particle.shape(param)
    if not (shape and total and total > 0) then
      return nil, ("texture %d has a broken header"):format(n)
    end
    if shape.width * shape.height ~= texBytes then
      return nil, ("texture %d is %dx%d but carries %d bytes")
        :format(n, shape.width, shape.height, texBytes)
    end
    local palette = {}
    for i = 0, floor(palBytes / 2) - 1 do
      local v = u16(data, at + palAt + i * 2)
      if not v then break end
      -- BGR555, the hardware's own order, scaled to 0-255 the way every other
      -- palette in this port is.
      palette[i + 1] = {
        floor((v % 32) * 255 / 31),
        floor((floor(v / 32) % 32) * 255 / 31),
        floor((floor(v / 1024) % 32) * 255 / 31),
      }
    end
    out[#out + 1] = {
      format = shape.format,
      formatName = Gen4Particle.FORMATS[shape.format],
      width = shape.width,
      height = shape.height,
      pixels = sub(data, at + Gen4Particle.TEXTURE_HEADER_BYTES + 1,
                   at + Gen4Particle.TEXTURE_HEADER_BYTES + texBytes),
      palette = palette,
    }
    at = at + total
    n = n + 1
  end
  if at ~= head.textureAt + head.textureBytes then
    return nil, ("the texture blocks end at %d, not %d")
      :format(at, head.textureAt + head.textureBytes)
  end
  return out, head
end

-- rgba(texture) -> { width, height, rgba }
--
-- The alpha is IN the pixel byte, not in the palette, which is the whole point
-- of these two formats: a particle is a soft-edged shape and its edge is made
-- of alpha, not of more colours. Index 0 is a real colour here -- there is no
-- transparent-index convention -- so an all-zero pixel is a transparent BLACK
-- rather than a hole, and reading it as a hole loses the shape's core.
function Gen4Particle.rgba(texture)
  if not texture then return nil end
  local w, h = texture.width, texture.height
  local out, px, pal = {}, texture.pixels, texture.palette
  local a3i5 = texture.format == Gen4Particle.FORMAT_A3I5
  local char = string.char
  for i = 1, w * h do
    local v = byte(px, i) or 0
    local index, alpha
    if a3i5 then
      index = v % 32
      alpha = floor(floor(v / 32) % 8 * 255 / 7)
    else
      index = v % 8
      alpha = floor(floor(v / 8) % 32 * 255 / 31)
    end
    local c = pal[index + 1]
    if c then out[i] = char(c[1], c[2], c[3], alpha)
    else out[i] = char(0, 0, 0, 0) end
  end
  return { width = w, height = h, rgba = table.concat(out) }
end

-- ---------------------------------------------------------------------------
-- The emitters
-- ---------------------------------------------------------------------------

-- WHERE EACH EMITTER STARTS AND HOW LONG IT IS. The textures are what an effect
-- looks like; the emitters are how it moves, and until a walk could find their
-- boundaries there was no safe way to read them at all -- a mis-sized emitter
-- runs into the NEXT one's bytes and reads its parameters as its own, silently.
--
-- HOW THIS WAS DERIVED, because it matters that it was not fitted. A first
-- attempt regressed emitter length against the header's bits with least squares
-- and produced an EXACT fit whose coefficients were things like 0.333 -- an
-- underdetermined system satisfying itself. It was thrown away.
--
-- What replaced it needs no model. Take every file with ONE emitter, so the
-- emitter's length is simply the area size, and find pairs of headers that
-- DIFFER IN EXACTLY ONE BIT: that bit's cost is the difference in their
-- lengths. One subtraction, no fitting, and the answer is either consistent
-- across every such pair or it is wrong. It was consistent for every bit.
--
-- Then the same measurement was extended by subtraction: in any file whose
-- emitters are all known but the last, the last one's length is what remains.
-- That took 66 direct measurements to 106, which isolated three more bits --
-- including the one that had looked like a variable-length block and is not.
--
-- The result walks all 1,744 emitters in all 608 particle files to their exact
-- ends. `tools/gen4_particle_check.lua` asserts it.
Gen4Particle.EMITTER_BASE = 88

-- Each bit of the emitter's first word that adds an optional block, and what it
-- adds. Bits not listed are parameters, not selectors, and cost nothing.
--
-- !! BIT 28 OCCURS EXACTLY ONCE IN THE WHOLE CARTRIDGE -- one emitter of
-- waza_particle member 43 -- so its +8 rests on a single sample and is the only
-- entry here that a second example could still move. Bit 25 has thirteen. Every
-- other bit has dozens to hundreds, and the walk closes on all 608 files either
-- way; this note is here so nobody later mistakes "it closes" for "all eleven
-- are equally well evidenced".
Gen4Particle.EMITTER_BLOCKS = {
  [8] = 12, [9] = 12, [10] = 8, [11] = 12, [16] = 20,
  [24] = 8, [25] = 8, [26] = 16, [27] = 4, [28] = 8, [29] = 16,
}
Gen4Particle.EMITTER_SINGLE_SAMPLE = { [28] = true }

-- pret's names for the same eleven bits, so a caller can ask what an emitter
-- carries without knowing the numbers.
Gen4Particle.EMITTER_BLOCK_NAMES = {
  [8] = "scaleAnim", [9] = "colorAnim", [10] = "alphaAnim", [11] = "texAnim",
  [16] = "childResource", [24] = "gravity", [25] = "random", [26] = "magnet",
  [27] = "spin", [28] = "collisionPlane", [29] = "convergence",
}

-- emitterBytes(word) -> how many bytes the emitter whose header word this is
-- occupies, itself included.
function Gen4Particle.emitterBytes(word)
  if not word then return nil end
  local n = Gen4Particle.EMITTER_BASE
  for bit, size in pairs(Gen4Particle.EMITTER_BLOCKS) do
    if floor(word / 2 ^ bit) % 2 == 1 then n = n + size end
  end
  return n
end

-- emitters(data) -> { { at, bytes, flags, blocks = { [bit] = true } }, ... }
--
-- WHAT THIS DOES NOT DO: read the fields. An emitter says how many particles,
-- how fast, how long and which way, and none of that is decoded here -- the
-- structure is checkable by closure and the field semantics are not, so they
-- are the next derivation rather than this one's guess. What a caller gets is
-- where every emitter is and which optional blocks it carries, which is the
-- thing that had to exist before any of the rest could be read safely.
function Gen4Particle.emitters(data)
  local head, why = Gen4Particle.header(data)
  if not head then return nil, why end
  local out, at = {}, Gen4Particle.HEADER_BYTES
  for i = 1, head.emitters do
    if at + 4 > #data then
      return nil, ("emitter %d starts past the end"):format(i)
    end
    local word = u32(data, at)
    local bytes = Gen4Particle.emitterBytes(word)
    local blocks = {}
    for bit in pairs(Gen4Particle.EMITTER_BLOCKS) do
      if floor(word / 2 ^ bit) % 2 == 1 then blocks[bit] = true end
    end
    local parsed, consumed = Gen4Particle.emitterBlocks(data, at, word)
    -- THE BLOCK WALK MUST LAND WHERE THE BIT COSTS SAY IT WILL. `bytes` comes
    -- from summing the costs; `consumed` comes from decoding each block in
    -- turn. They are the same number by two routes, and a reader that got a
    -- size wrong would put every field of every later block one step out --
    -- silently, because the values would all still be numbers.
    if parsed and consumed ~= bytes then
      return nil, ("emitter %d decoded %d bytes of blocks, costed %d")
        :format(i, consumed, bytes)
    end
    out[i] = { at = at, bytes = bytes, flags = word, blocks = blocks,
               parsed = parsed or nil,
               fields = Gen4Particle.emitterFields(data, at) }
    at = at + bytes
  end
  if at ~= Gen4Particle.HEADER_BYTES + head.emitterBytes then
    return nil, ("the emitters end at %d, not %d")
      :format(at, Gen4Particle.HEADER_BYTES + head.emitterBytes)
  end
  return out, head
end

-- ---------------------------------------------------------------------------
-- The emitter's FIELDS
-- ---------------------------------------------------------------------------

-- !! AND THEN PRET TURNED OUT TO SHIP THE WHOLE LIBRARY.
--
-- The block table above was derived from byte arithmetic alone -- single-bit
-- header pairs and subtraction -- before anyone looked for a reference. pret
-- has `lib/spl/`, the Nitro particle library decompiled, and `spl_resource.h`
-- names every one of those bits:
--
--     bit  8  hasScaleAnim              +12   SPLScaleAnim   is 12 bytes
--     bit  9  hasColorAnim              +12   SPLColorAnim   is 12
--     bit 10  hasAlphaAnim              + 8   SPLAlphaAnim   is  8
--     bit 11  hasTexAnim                +12   SPLTexAnim     is 12
--     bit 16  hasChildResource          +20   SPLChildResource
--     bit 24  hasGravityBehavior        + 8
--     bit 25  hasRandomBehavior         + 8
--     bit 26  hasMagnetBehavior         +16
--     bit 27  hasSpinBehavior           + 4
--     bit 28  hasCollisionPlaneBehavior + 8
--     bit 29  hasConvergenceBehavior    +16
--
-- ...and the bits the derivation found to cost NOTHING are exactly the ones
-- pret declares as parameters rather than selectors: emissionType (0-3),
-- drawType (4-5), circleAxis (6-7), hasRotation (12), randomInitAngle (13),
-- drawChildrenFirst (21). Eleven selectors and eight parameters, agreed on by
-- two methods that share no assumption -- one counting bytes, one reading a
-- struct. And `SPLResourceHeader` lays out to 88 bytes, which is the base the
-- arithmetic found.
--
-- THAT AGREEMENT IS WHY THE FIELDS BELOW ARE NAMES AND NOT GUESSES. The offsets
-- are pret's declaration order at its own alignment, and the one independent
-- test of them -- `textureIndex` must be a texture this very file contains --
-- is asserted by the check over every emitter in the cartridge.

local function s16(data, at)
  local v = u16(data, at)
  if not v then return nil end
  if v >= 32768 then return v - 65536 end
  return v
end

-- fx32 is 1.19.12 fixed point and fx16 is 1.3.12; both are "divide by 4096".
local FX = 4096
local function fx32(data, at)
  local v = u32(data, at)
  if not v then return nil end
  if v >= 2147483648 then v = v - 4294967296 end
  return v / FX
end
local function fx16(data, at)
  local v = s16(data, at)
  if not v then return nil end
  return v / FX
end

-- BGR555 -> { r, g, b } 0-255, the same way the palettes are read.
local function rgb555(v)
  if not v then return nil end
  return {
    floor((v % 32) * 255 / 31),
    floor((floor(v / 32) % 32) * 255 / 31),
    floor((floor(v / 1024) % 32) * 255 / 31),
  }
end

-- emitterFields(data, at) -> the named contents of one emitter's base struct.
--
-- Offsets are SPLResourceHeader's declaration order; the struct is 88 bytes and
-- ends on `userData`, which is what makes `EMITTER_BASE` and this agree.
function Gen4Particle.emitterFields(data, at)
  if not data or not at or at + Gen4Particle.EMITTER_BASE > #data then
    return nil, "emitter runs past the end"
  end
  local misc1 = u32(data, at + 68)
  local misc2 = u32(data, at + 72)
  local atten = u32(data, at + 64)
  local function byteOf(word, n) return floor(word / 2 ^ (8 * n)) % 256 end
  return {
    flags = u32(data, at + 0),
    -- where the emitter sits, and the shape it emits into
    basePos = { fx32(data, at + 4), fx32(data, at + 8), fx32(data, at + 12) },
    emissionCount = fx32(data, at + 16),
    radius = fx32(data, at + 20),
    length = fx32(data, at + 24),
    axis = { fx16(data, at + 28), fx16(data, at + 30), fx16(data, at + 32) },
    colour = rgb555(u16(data, at + 34)),
    -- how hard it throws them
    initVelPos = fx32(data, at + 36),
    initVelAxis = fx32(data, at + 40),
    baseScale = fx32(data, at + 44),
    aspectRatio = fx16(data, at + 48),
    startDelay = u16(data, at + 50),
    minRotation = s16(data, at + 52),
    maxRotation = s16(data, at + 54),
    initAngle = u16(data, at + 56),
    -- and for how long. THESE TWO ARE THE ANSWER TO "how long does this effect
    -- last", which the move program never states -- it waits on the emitters.
    emitterLifeTime = u16(data, at + 60),
    particleLifeTime = u16(data, at + 62),
    randomAttenuation = {
      baseScale = byteOf(atten, 0),
      lifeTime = byteOf(atten, 1),
      initVel = byteOf(atten, 2),
    },
    emissionInterval = byteOf(misc1, 0),
    baseAlpha = byteOf(misc1, 1),
    airResistance = byteOf(misc1, 2),
    -- THE JOIN BACK TO THE ART: which of this file's own textures to throw.
    textureIndex = byteOf(misc1, 3),
    loopFrames = byteOf(misc2, 0),
    -- THE REST OF THE SECOND MISC WORD, and it is not spare. C packs
    -- `SPLResourceHeader.misc` into THREE u32s: loopFrames 0-7, dbbScale 8-23,
    -- textureTileCountS 24-25, textureTileCountT 26-27, scaleAnimDir 28-30,
    -- dpolFaceEmitter 31, then flipTextureS and flipTextureT as bits 0 and 1 of
    -- a third word. That third word is why `misc` spans 68..79 and the base
    -- struct reaches 88 with polygonX/Y at 80/82 and userData at 84 -- the
    -- arithmetic that closed on all 608 files is the same arithmetic as this
    -- packing, which is a quiet confirmation of both.
    dbbScale = floor(misc2 / 256) % 65536,
    textureTileCountS = floor(misc2 / 16777216) % 4,
    textureTileCountT = floor(misc2 / 67108864) % 4,
    -- WHICH AXES THE SCALE ANIMATION TOUCHES: 0 both, 1 X only, 2 Y only.
    -- `spl_draw.c` applies `animScale` to one, the other or both, so a port that
    -- multiplies a single scale stretches particles the cartridge squashes.
    scaleAnimDir = floor(misc2 / 268435456) % 8,
    dpolFaceEmitter = floor(misc2 / 2147483648) % 2 == 1,
    flipTextureS = (u32(data, at + 76) or 0) % 2 == 1,
    flipTextureT = floor((u32(data, at + 76) or 0) / 2) % 2 == 1,
    polygonX = fx16(data, at + 80),
    polygonY = fx16(data, at + 82),
  }
end

-- ---------------------------------------------------------------------------
-- THE OPTIONAL BLOCKS, DECODED -- and every one of the eleven sizes this port
-- MEASURED is now confirmed field by field against pret's own structs.
--
-- The block costs above were derived from byte arithmetic alone: single-bit-pair
-- subtraction over 144 single-emitter files, extended to 106 by closure. pret's
-- `lib/spl/` declares the same eleven structs, and they lay out to the same
-- eleven sizes:
--
--   bit  8  SPLScaleAnim              12    bit 24  SPLGravityBehavior         8
--   bit  9  SPLColorAnim              12    bit 25  SPLRandomBehavior          8
--   bit 10  SPLAlphaAnim               8    bit 26  SPLMagnetBehavior         16
--   bit 11  SPLTexAnim                12    bit 27  SPLSpinBehavior            4
--   bit 16  SPLChildResource          20    bit 28  SPLCollisionPlaneBehavior  8
--                                           bit 29  SPLConvergenceBehavior    16
--
-- !! BIT 28 IS NO LONGER A SINGLE SAMPLE. Its +8 rested on ONE emitter in the
-- whole cartridge (waza_particle[43], third emitter) and was flagged as the one
-- entry a second example could move. `SPLCollisionPlaneBehavior` is fx32 + fx16
-- + a 2-bit field in a u16 = 8 bytes BY DECLARATION. The sample and the struct
-- agree, so the weakest entry in the table is now the same strength as the rest.
--
-- THE ORDER IS ASCENDING BIT ORDER, which `SPLManager_LoadResources` walks in
-- exactly this sequence: the four animations, the child resource, then the six
-- behaviours. Nothing here chose that order; it is read off the loader.
Gen4Particle.BLOCK_SCALE_ANIM = 8
Gen4Particle.BLOCK_COLOR_ANIM = 9
Gen4Particle.BLOCK_ALPHA_ANIM = 10
Gen4Particle.BLOCK_TEX_ANIM = 11
Gen4Particle.BLOCK_CHILD = 16
Gen4Particle.BLOCK_GRAVITY = 24
Gen4Particle.BLOCK_RANDOM = 25
Gen4Particle.BLOCK_MAGNET = 26
Gen4Particle.BLOCK_SPIN = 27
Gen4Particle.BLOCK_COLLISION = 28
Gen4Particle.BLOCK_CONVERGENCE = 29

-- The blocks in the order the loader reads them, so a walk cannot drift.
Gen4Particle.BLOCK_ORDER = { 8, 9, 10, 11, 16, 24, 25, 26, 27, 28, 29 }

local function u8(data, at)
  return byte(data, at + 1)
end

-- SPLCurveInOut is one u16: `in` low byte, `out` high byte. Both are points on
-- the 0..255 life-rate scale, NOT frame counts -- which is what makes a curve
-- independent of how long the particle happens to live.
local function curveInOut(data, at)
  local v = u16(data, at) or 0
  return { inAt = v % 256, outAt = floor(v / 256) % 256 }
end

-- SPLCurveInPeakOut is a u32: in, peak, out, then a spare byte.
local function curveInPeakOut(data, at)
  local v = u32(data, at) or 0
  return { inAt = v % 256, peakAt = floor(v / 256) % 256,
           outAt = floor(v / 65536) % 256 }
end

local BLOCK_READERS = {
  [8] = function(data, at)                       -- SPLScaleAnim
    local flags = u16(data, at + 8) or 0
    return {
      start = fx16(data, at + 0), mid = fx16(data, at + 2),
      finish = fx16(data, at + 4),
      curve = curveInOut(data, at + 6),
      loop = flags % 2 == 1,
    }
  end,
  [9] = function(data, at)                       -- SPLColorAnim
    local flags = u16(data, at + 8) or 0
    return {
      start = rgb555(u16(data, at + 0)), finish = rgb555(u16(data, at + 2)),
      curve = curveInPeakOut(data, at + 4),
      randomStartColor = flags % 2 == 1,
      loop = floor(flags / 2) % 2 == 1,
      interpolate = floor(flags / 4) % 2 == 1,
    }
  end,
  [10] = function(data, at)                      -- SPLAlphaAnim
    -- THREE FIVE-BIT ALPHAS PACKED IN ONE u16, which is the DS's alpha range
    -- (0..31) three times over rather than three bytes.
    local a = u16(data, at + 0) or 0
    local flags = u16(data, at + 2) or 0
    return {
      start = a % 32, mid = floor(a / 32) % 32, finish = floor(a / 1024) % 32,
      randomRange = flags % 256,
      loop = floor(flags / 256) % 2 == 1,
      curve = curveInOut(data, at + 4),
    }
  end,
  [11] = function(data, at)                      -- SPLTexAnim
    local frames = {}
    for i = 0, 7 do frames[i + 1] = u8(data, at + i) or 0 end
    local param = u32(data, at + 8) or 0
    return {
      textures = frames,
      frameCount = param % 256,
      step = floor(param / 256) % 256,
      randomizeInit = floor(param / 65536) % 2 == 1,
      loop = floor(param / 131072) % 2 == 1,
    }
  end,
  [16] = function(data, at)                      -- SPLChildResource
    local flags = u16(data, at + 0) or 0
    local misc = u32(data, at + 12) or 0
    return {
      usesBehaviors = flags % 2 == 1,
      hasScaleAnim = floor(flags / 2) % 2 == 1,
      hasAlphaAnim = floor(flags / 4) % 2 == 1,
      rotationType = floor(flags / 8) % 4,
      followEmitter = floor(flags / 32) % 2 == 1,
      useChildColour = floor(flags / 64) % 2 == 1,
      randomInitVelMag = fx16(data, at + 2),
      endScale = fx16(data, at + 4),
      lifeTime = u16(data, at + 6),
      velocityRatio = u8(data, at + 8),
      scaleRatio = u8(data, at + 9),
      colour = rgb555(u16(data, at + 10)),
      emissionCount = misc % 256,
      emissionDelay = floor(misc / 256) % 256,
      emissionInterval = floor(misc / 65536) % 256,
      textureIndex = floor(misc / 16777216) % 256,
    }
  end,
  [24] = function(data, at)                      -- SPLGravityBehavior
    return { x = fx16(data, at + 0), y = fx16(data, at + 2),
             z = fx16(data, at + 4) }
  end,
  [25] = function(data, at)                      -- SPLRandomBehavior
    return { x = fx16(data, at + 0), y = fx16(data, at + 2),
             z = fx16(data, at + 4),
             -- A ZERO INTERVAL WOULD DIVIDE BY ZERO in `age % interval`; the
             -- cartridge never writes one, and clamping here is cheaper than
             -- finding out in a battle.
             interval = math.max(1, u16(data, at + 6) or 1) }
  end,
  [26] = function(data, at)                      -- SPLMagnetBehavior
    return { x = fx32(data, at + 0), y = fx32(data, at + 4),
             z = fx32(data, at + 8), force = fx16(data, at + 12) }
  end,
  [27] = function(data, at)                      -- SPLSpinBehavior
    -- The angle is in INDEX UNITS: 0x10000 is a full turn, and it is applied
    -- every frame rather than over the particle's life.
    return { angle = u16(data, at + 0), axis = (u16(data, at + 2) or 0) % 4 }
  end,
  [28] = function(data, at)                      -- SPLCollisionPlaneBehavior
    return { y = fx32(data, at + 0), elasticity = fx16(data, at + 4),
             kind = (u16(data, at + 6) or 0) % 4 }
  end,
  [29] = function(data, at)                      -- SPLConvergenceBehavior
    return { x = fx32(data, at + 0), y = fx32(data, at + 4),
             z = fx32(data, at + 8), force = fx16(data, at + 12) }
  end,
}
Gen4Particle.BLOCK_READERS = BLOCK_READERS

Gen4Particle.COLLISION_KILL = 0
Gen4Particle.COLLISION_BOUNCE = 1
Gen4Particle.SPIN_AXIS_X = 0
Gen4Particle.SPIN_AXIS_Y = 1
Gen4Particle.SPIN_AXIS_Z = 2

-- emitterBlocks(data, at, word) -> { <name> = <parsed>, ... }, bytesConsumed
--
-- Walks the blocks after an emitter's 88-byte base in the loader's own order.
-- Returns how many bytes it consumed so the caller can check that against the
-- length the bit costs predict -- two independent ways of arriving at the same
-- number, which is the only reason to return it.
function Gen4Particle.emitterBlocks(data, at, word)
  if not (data and at) then return nil, 0 end
  word = word or u32(data, at) or 0
  local out, cursor = {}, at + Gen4Particle.EMITTER_BASE
  for _, bit in ipairs(Gen4Particle.BLOCK_ORDER) do
    if floor(word / 2 ^ bit) % 2 == 1 then
      local size = Gen4Particle.EMITTER_BLOCKS[bit]
      local name = Gen4Particle.EMITTER_BLOCK_NAMES[bit]
      if size and name then
        if cursor + size > #data then return nil, cursor - at end
        out[name] = BLOCK_READERS[bit] and BLOCK_READERS[bit](data, cursor) or {}
        cursor = cursor + size
      end
    end
  end
  return out, cursor - at
end

-- check(data) -> true, textureCount   or   false, why
function Gen4Particle.check(data)
  local head, why = Gen4Particle.header(data)
  if not head then return false, why end
  local ok, reason = Gen4Particle.consistent(head)
  if not ok then return false, reason end
  local list, err = Gen4Particle.textures(data)
  if not list then return false, err end
  -- THE EMITTER WALK IS PART OF THE CHECK, not a separate question: a file
  -- whose emitters do not tile their own area is one this port cannot read,
  -- whatever its textures do.
  local ems, emErr = Gen4Particle.emitters(data)
  if not ems then return false, emErr end
  return true, #list, #ems
end

return Gen4Particle
