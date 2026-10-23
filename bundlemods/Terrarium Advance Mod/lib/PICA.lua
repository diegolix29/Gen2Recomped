-- PICA: the 3DS GPU's command lists and texture formats, as far as reading
-- Omega Ruby / Alpha Sapphire Pokemon models needs them (lib/H3D.lua).
-- Layouts follow SPICA (gdkchan/SPICA, SPICA/PICA): PICACommandReader,
-- PICAVectorFloat24, TextureConverter, TextureCompression.
--
-- COMMANDS.  A list of u32 words: parameter, header, extra parameters, padded
-- to an even word count.  Header bits 0-15 register, 16-19 byte mask, 20-30
-- extra parameter count, 31 "consecutive" (each parameter goes to the next
-- register up).  `PICA.commands(words)` returns { {reg, params}, ... } and
-- the vertex-shader float uniforms the list uploaded.
--
-- TEXTURES.  8x8 tiles, left to right then top to bottom, pixels inside a
-- tile in the Morton order SWIZZLE lists; ETC1/ETC1A4 in 4x4 blocks, four per
-- tile.  `PICA.decodeTexture` returns an RGBA ImageData whose row 0 is the
-- first row in memory, which is the TOP of the texture: PICA's t runs up from
-- the bottom, so LOVE (v down from the top) samples it with v = 1 - t, and an
-- OBJ (vt up from the bottom) uses t as it is.

local PICA = {}

local okBit, bit = pcall(require, "bit")
assert(okBit and bit, "PICA needs LuaJIT's bit library")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function f32(bits)
  if bits == 0 then return 0 end
  local sign = bits >= 0x80000000 and -1 or 1
  local exp = math.floor(bits / 0x800000) % 256
  local man = bits % 0x800000
  if exp == 0 then return sign * man * 2 ^ -149 end
  if exp == 255 then return 0 end
  return sign * (1 + man / 0x800000) * 2 ^ (exp - 127)
end
PICA.f32 = f32

-- float24: 16-bit mantissa, 7-bit exponent (bias 63), sign at bit 23
local function f24(v)
  local man = v % 0x10000
  local exp = math.floor(v / 0x10000) % 128
  local sign = math.floor(v / 0x800000) % 2 == 1 and -1 or 1
  if exp == 0 and man == 0 then return 0 end
  return sign * (1 + man / 0x10000) * 2 ^ (exp - 63)
end

-- three words -> x, y, z, w (PICAVectorFloat24)
function PICA.vec24(w0, w1, w2)
  local x = w2 % 0x1000000
  local y = math.floor(w2 / 0x1000000) + (w1 % 0x10000) * 256
  local z = math.floor(w1 / 0x10000) + (w0 % 256) * 65536
  local w = math.floor(w0 / 256)
  return f24(x), f24(y), f24(z), f24(w)
end

PICA.REG = {
  TEXUNIT_CONFIG = 0x080, TEX0_DIM = 0x082, TEX0_LOD = 0x084, TEX0_ADDR1 = 0x085,
  TEX0_TYPE = 0x08E,
  ATTR_LOC = 0x200, ATTR_FORMAT_LO = 0x201, ATTR_FORMAT_HI = 0x202,
  ATTR0_OFFSET = 0x203, ATTR0_CONFIG1 = 0x204, ATTR0_CONFIG2 = 0x205,
  INDEX_CONFIG = 0x227, NUM_VERTICES = 0x228,
  FIXED_INDEX = 0x232, FIXED_DATA0 = 0x233, FIXED_DATA1 = 0x234, FIXED_DATA2 = 0x235,
  VSH_NUM_ATTR = 0x242, PRIMITIVE_CONFIG = 0x25E,
  VSH_PERM_LO = 0x2BB, VSH_PERM_HI = 0x2BC,
  VSH_UNIFORM_INDEX = 0x2C0, VSH_UNIFORM_DATA0 = 0x2C1, VSH_UNIFORM_DATA7 = 0x2C8,
}
local REG = PICA.REG

-- `data` and the absolute offset/count of a u32 list (as BCH stores them)
function PICA.words(data, at, count)
  local out = {}
  for i = 0, count - 1 do out[i + 1] = u32(data, at + i * 4 + 1) end
  return out
end

function PICA.commands(words)
  local cmds = {}
  local uniforms = {}          -- [index] = { x, y, z, w }
  local uIndex, u32mode, f24words = 0, false, {}

  local function upload(p)
    local v = band(rshift(uIndex, 2), 0x5F)
    local slot = uIndex % 4
    local u = uniforms[v] or { 0, 0, 0, 0 }
    uniforms[v] = u
    if u32mode then
      -- word 0 -> w, 1 -> z, 2 -> y, 3 -> x
      u[4 - slot] = f32(p)
    else
      f24words[slot + 1] = p
      if slot == 2 then
        u[1], u[2], u[3], u[4] = PICA.vec24(f24words[1], f24words[2], f24words[3])
        uIndex = uIndex + 1
      end
    end
    uIndex = uIndex + 1
  end

  local function emit(reg, params)
    cmds[#cmds + 1] = { reg = reg, params = params }
    if reg == REG.VSH_UNIFORM_INDEX then
      uIndex = band(params[1], 0xFF) * 4
      u32mode = rshift(params[1], 31) ~= 0
    elseif reg >= REG.VSH_UNIFORM_DATA0 and reg <= REG.VSH_UNIFORM_DATA7 then
      for _, p in ipairs(params) do upload(p) end
    end
  end

  local i, n = 1, #words
  while i < n do
    local param, header = words[i], words[i + 1]
    i = i + 2
    local reg = header % 0x10000
    local extra = math.floor(header / 0x100000) % 0x800
    local consecutive = header >= 0x80000000
    if consecutive then
      for k = 0, extra do
        emit(reg, { param })
        reg = reg + 1
        if k < extra then param = words[i]; i = i + 1 end
      end
    else
      local params = { param }
      for _ = 1, extra do params[#params + 1] = words[i]; i = i + 1 end
      emit(reg, params)
    end
    if (i - 1) % 2 == 1 then i = i + 1 end
  end
  return cmds, uniforms
end

-- ------------------------------------------------------------- textures

PICA.FORMAT = {
  RGBA8 = 0, RGB8 = 1, RGBA5551 = 2, RGB565 = 3, RGBA4 = 4, LA8 = 5, HiLo8 = 6,
  L8 = 7, A8 = 8, LA4 = 9, L4 = 10, A4 = 11, ETC1 = 12, ETC1A4 = 13,
}
local BPP = { [0] = 32, 24, 16, 16, 16, 16, 16, 8, 8, 8, 4, 4, 4, 8 }

function PICA.textureLength(w, h, fmt)
  return math.floor(w * h * (BPP[fmt] or 32) / 8)
end

local SWIZZLE = {
   0,  1,  8,  9,  2,  3, 10, 11, 16, 17, 24, 25, 18, 19, 26, 27,
   4,  5, 12, 13,  6,  7, 14, 15, 20, 21, 28, 29, 22, 23, 30, 31,
  32, 33, 40, 41, 34, 35, 42, 43, 48, 49, 56, 57, 50, 51, 58, 59,
  36, 37, 44, 45, 38, 39, 46, 47, 52, 53, 60, 61, 54, 55, 62, 63,
}

local ETC_MOD = {
  [0] = { 2, 8, -2, -8 }, { 5, 17, -5, -17 }, { 9, 29, -9, -29 }, { 13, 42, -13, -42 },
  { 18, 60, -18, -60 }, { 24, 80, -24, -80 }, { 33, 106, -33, -106 }, { 47, 183, -47, -183 },
}

local function clamp8(v) return v < 0 and 0 or (v > 255 and 255 or v) end

-- one ETC1 4x4 block; `put(x, y, r, g, b)` with x, y in 0..3
local function etcBlock(s, p, put)
  local c1, c2, c3, c4, c5, c6, c7, c8 = s:byte(p, p + 7)
  -- read little endian then byte-swapped (SPICA): the first four bytes are
  -- the pixel indices, the last four the control word
  local idx = ((c1 * 256 + c2) * 256 + c3) * 256 + c4
  local ctl = ((c5 * 256 + c6) * 256 + c7) * 256 + c8
  local flip = band(rshift(ctl, 24), 1) == 1
  local diff = band(rshift(ctl, 25), 1) == 1
  local r1, g1, b1, r2, g2, b2
  if diff then
    local function ex5(v) return bor(lshift(v, 3), rshift(v, 2)) end
    local function sx3(v) return v >= 4 and v - 8 or v end
    local R, G, B = band(rshift(ctl, 19), 31), band(rshift(ctl, 11), 31), band(rshift(ctl, 3), 31)
    r1, g1, b1 = ex5(R), ex5(G), ex5(B)
    r2 = ex5(band(R + sx3(band(rshift(ctl, 16), 7)), 31))
    g2 = ex5(band(G + sx3(band(rshift(ctl, 8), 7)), 31))
    b2 = ex5(band(B + sx3(band(ctl, 7)), 31))
  else
    r1, g1, b1 = band(rshift(ctl, 20), 15) * 17, band(rshift(ctl, 12), 15) * 17, band(rshift(ctl, 4), 15) * 17
    r2, g2, b2 = band(rshift(ctl, 16), 15) * 17, band(rshift(ctl, 8), 15) * 17, band(ctl, 15) * 17
  end
  local t1, t2 = ETC_MOD[band(rshift(ctl, 29), 7)], ETC_MOD[band(rshift(ctl, 26), 7)]
  for x = 0, 3 do
    for y = 0, 3 do
      local i = x * 4 + y
      local lsb = band(rshift(idx, i < 8 and 24 + i or 16 + i - 8), 1)
      local msb = band(rshift(idx, i < 8 and 8 + i or i - 8), 1)
      local sel = msb * 2 + lsb + 1
      local second = (flip and y >= 2) or (not flip and x >= 2)
      local m = second and t2[sel] or t1[sel]
      if second then
        put(x, y, clamp8(r2 + m), clamp8(g2 + m), clamp8(b2 + m))
      else
        put(x, y, clamp8(r1 + m), clamp8(g1 + m), clamp8(b1 + m))
      end
    end
  end
end

-- RGBA ImageData from `len` bytes of `data` at absolute offset `at`
function PICA.decodeTexture(data, at, w, h, fmt)
  local img = love.image.newImageData(w, h)
  local p = at + 1                                  -- 1-based read position

  if fmt == PICA.FORMAT.ETC1 or fmt == PICA.FORMAT.ETC1A4 then
    local withAlpha = fmt == PICA.FORMAT.ETC1A4
    local XT, YT = { 0, 4, 0, 4 }, { 0, 0, 4, 4 }
    for ty = 0, h - 1, 8 do
      for tx = 0, w - 1, 8 do
        for b = 1, 4 do
          local alpha = nil
          if withAlpha then alpha = p; p = p + 8 end
          local bx, by = tx + XT[b], ty + YT[b]
          etcBlock(data, p, function(x, y, r, g, bl)
            local a = 255
            if alpha then
              local k = x * 4 + y
              local byte = data:byte(alpha + math.floor(k / 2))
              local nib = (k % 2 == 0) and (byte % 16) or math.floor(byte / 16)
              a = nib * 17
            end
            local px, py = bx + x, by + y
            if px < w and py < h then img:setPixel(px, py, r / 255, g / 255, bl / 255, a / 255) end
          end)
          p = p + 8
        end
      end
    end
    return img
  end

  local bpp = BPP[fmt]
  if not bpp then error("unsupported PICA texture format " .. tostring(fmt)) end
  local nibble = 0                                    -- for 4-bit formats
  for ty = 0, h - 1, 8 do
    for tx = 0, w - 1, 8 do
      for px = 1, 64 do
        local sw = SWIZZLE[px]
        local x, y = tx + sw % 8, ty + math.floor(sw / 8)
        local r, g, b, a = 255, 255, 255, 255
        if fmt == 0 then
          local i0, i1, i2, i3 = data:byte(p, p + 3); p = p + 4
          r, g, b, a = i3, i2, i1, i0
        elseif fmt == 1 then
          local i0, i1, i2 = data:byte(p, p + 2); p = p + 3
          r, g, b = i2, i1, i0
        elseif fmt <= 6 then
          local lo, hi = data:byte(p, p + 1); p = p + 2
          local v = lo + hi * 256
          if fmt == 2 then
            r = math.floor(v / 2048) % 32 * 255 / 31
            g = math.floor(v / 64) % 32 * 255 / 31
            b = math.floor(v / 2) % 32 * 255 / 31
            a = (v % 2) * 255
          elseif fmt == 3 then
            r = math.floor(v / 2048) % 32 * 255 / 31
            g = math.floor(v / 32) % 64 * 255 / 63
            b = v % 32 * 255 / 31
          elseif fmt == 4 then
            r = math.floor(v / 4096) % 16 * 17
            g = math.floor(v / 256) % 16 * 17
            b = math.floor(v / 16) % 16 * 17
            a = v % 16 * 17
          elseif fmt == 5 then
            r, g, b, a = hi, hi, hi, lo
          else
            r, g, b = hi, lo, 0
          end
        elseif fmt <= 9 then
          local v = data:byte(p); p = p + 1
          if fmt == 7 then r, g, b = v, v, v
          elseif fmt == 8 then a = v
          else
            local l = math.floor(v / 16) * 17
            r, g, b, a = l, l, l, (v % 16) * 17
          end
        else
          local byte = data:byte(p)
          local v = (nibble == 0) and (byte % 16) or math.floor(byte / 16)
          if nibble == 1 then p = p + 1 end
          nibble = 1 - nibble
          v = v * 17
          if fmt == 10 then r, g, b = v, v, v else a = v end
        end
        if x < w and y < h then img:setPixel(x, y, r / 255, g / 255, b / 255, a / 255) end
      end
    end
  end
  return img
end

return PICA
