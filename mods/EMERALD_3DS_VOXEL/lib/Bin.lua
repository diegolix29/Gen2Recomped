-- Little-endian reads over a byte string, 0-based offsets.
--
-- The four baked files are read the way the 3DS reads them: whole into
-- memory, then addressed by offset.  On LuaJIT (every platform the game
-- ships on) the bulk arrays -- 290k vertices, 3M page texels -- are read
-- through FFI pointers into the string itself; the byte-by-byte path is the
-- fallback for a plain Lua run and is only ever used for the small tables.

local Bin = {}

local byte = string.byte
local okFfi, ffi = pcall(require, "ffi")
if not okFfi then ffi = nil end
Bin.ffi = ffi

function Bin.u8(s, o) return byte(s, o + 1) end

function Bin.s8(s, o)
  local v = byte(s, o + 1)
  return v >= 128 and v - 256 or v
end

function Bin.u16(s, o)
  local a, b = byte(s, o + 1, o + 2)
  return a + b * 256
end

function Bin.s16(s, o)
  local v = Bin.u16(s, o)
  return v >= 32768 and v - 65536 or v
end

function Bin.u32(s, o)
  local a, b, c, d = byte(s, o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

function Bin.tag(s, o) return s:sub(o + 1, o + 4) end

-- A view of `count` little-endian float32s at byte offset `o`, indexed from
-- 0.  Holds `s` so the pointer stays valid as long as the view does.
function Bin.floats(s, o)
  if ffi then
    local base = ffi.cast("const uint8_t *", s)
    return { s = s, p = ffi.cast("const float *", base + o) }
  end
  return { s = s, o = o }
end

function Bin.float(view, i)
  if view.p then return view.p[i] end
  return (love.data.unpack("<f", view.s, view.o + i * 4 + 1))
end

-- u16 array view, the same arrangement
function Bin.u16s(s, o)
  if ffi then
    local base = ffi.cast("const uint8_t *", s)
    return { s = s, p = ffi.cast("const uint16_t *", base + o), o = o }
  end
  return { s = s, o = o }
end

function Bin.u16at(view, i)
  if view.p then return view.p[i] end
  return Bin.u16(view.s, view.o + i * 2)
end

-- The 8x8 Morton order inside a PICA block: x in the even bits, y in the odd.
local MORTON = {}
for y = 0, 7 do
  for x = 0, 7 do
    local m = 0
    for bit = 0, 2 do
      local xb = math.floor(x / 2 ^ bit) % 2
      local yb = math.floor(y / 2 ^ bit) % 2
      m = m + xb * 2 ^ (2 * bit) + yb * 2 ^ (2 * bit + 1)
    end
    MORTON[y * 8 + x] = m
  end
end
Bin.MORTON = MORTON

-- RGBA5551 (R 15-11, G 10-6, B 5-1, A bit 0) -> 0..255 channels
local EXPAND = {}
for c = 0, 31 do EXPAND[c] = (c * 8) + math.floor(c / 4) end
Bin.EXPAND = EXPAND

-- A PICA-ordered RGBA5551 picture, `w` x `h` (multiples of 8), as an
-- ImageData the right way up.  `texels` is a u16 view.
function Bin.decodePica(texels, w, h)
  local data = love.image.newImageData(w, h)
  local blocksPerRow = w / 8
  if ffi and texels.p then
    local px = ffi.cast("uint8_t *", data:getFFIPointer())
    local src = texels.p
    for y = 0, h - 1 do
      local by, my = math.floor(y / 8), (y % 8) * 8
      local row = y * w * 4
      for x = 0, w - 1 do
        local t = src[(by * blocksPerRow + math.floor(x / 8)) * 64 + MORTON[my + x % 8]]
        local o = row + x * 4
        px[o] = EXPAND[math.floor(t / 2048) % 32]
        px[o + 1] = EXPAND[math.floor(t / 64) % 32]
        px[o + 2] = EXPAND[math.floor(t / 2) % 32]
        px[o + 3] = (t % 2) * 255
      end
    end
    return data
  end
  data:mapPixel(function(x, y)
    local t = Bin.u16at(texels, (math.floor(y / 8) * blocksPerRow + math.floor(x / 8)) * 64
                                + MORTON[(y % 8) * 8 + x % 8])
    return EXPAND[math.floor(t / 2048) % 32] / 255, EXPAND[math.floor(t / 64) % 32] / 255,
           EXPAND[math.floor(t / 2) % 32] / 255, t % 2
  end)
  return data
end

return Bin
