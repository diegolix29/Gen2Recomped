-- NINTENDO LZ77, BOTH VARIANTS (Black and White mostly use 0x11).
--
-- Gen 4's graphics are LZ10 (Gen4Graphics.decompress); Gen 5's sprites are
-- LZ11 -- the same flag-byte scheme with longer back-references:
--
--   header: u8 type (0x10 / 0x11), u24 decompressed size (0 => a u32 follows)
--   then groups of one flag byte (most significant bit first) and eight tokens:
--     0 -> one literal byte
--     1 -> a back-reference. LZ10: 2 bytes, length (b0 >> 4) + 3,
--          distance ((b0 & 0xF) << 8 | b1) + 1.
--          LZ11: the top nibble of the first byte picks the form --
--            0:  3 bytes, length ((b0 & 0xF) << 4 | b1 >> 4) + 0x11
--            1:  4 bytes, length ((b0 & 0xF) << 12 | b1 << 4 | b2 >> 4) + 0x111
--            2+: 2 bytes, length (b0 >> 4) + 1
--          and the distance is the last 12 bits + 1 in every form.

local Lz = {}

function Lz.isCompressed(data)
  if type(data) ~= "string" or #data < 4 then return false end
  local t = data:byte(1)
  return t == 0x10 or t == 0x11
end

function Lz.decompress(data)
  if not Lz.isCompressed(data) then return data end
  local kind = data:byte(1)
  local size = data:byte(2) + data:byte(3) * 256 + data:byte(4) * 65536
  local p = 5
  if size == 0 and #data >= 8 then
    size = data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216
    p = 9
  end
  local out, n = {}, 0
  local function byte() local b = data:byte(p); p = p + 1; return b end
  while n < size and p <= #data do
    local flags = byte()
    for bit = 7, 0, -1 do
      if n >= size or p > #data then break end
      if math.floor(flags / 2 ^ bit) % 2 == 0 then
        n = n + 1; out[n] = byte()
      else
        local length, dist
        local b0 = byte()
        if kind == 0x10 then
          local b1 = byte()
          length = math.floor(b0 / 16) + 3
          dist = (b0 % 16) * 256 + b1 + 1
        else
          local hi = math.floor(b0 / 16)
          if hi == 0 then
            local b1, b2 = byte(), byte()
            length = ((b0 % 16) * 16 + math.floor(b1 / 16)) + 0x11
            dist = (b1 % 16) * 256 + b2 + 1
          elseif hi == 1 then
            local b1, b2, b3 = byte(), byte(), byte()
            length = ((b0 % 16) * 4096 + b1 * 16 + math.floor(b2 / 16)) + 0x111
            dist = (b2 % 16) * 256 + b3 + 1
          else
            local b1 = byte()
            length = hi + 1
            dist = (b0 % 16) * 256 + b1 + 1
          end
        end
        for _ = 1, length do
          n = n + 1
          out[n] = out[n - dist] or 0
          if n >= size then break end
        end
      end
    end
  end
  local parts = {}
  for i = 1, n, 4096 do parts[#parts + 1] = string.char(unpack(out, i, math.min(i + 4095, n))) end
  return table.concat(parts)
end

return Lz
