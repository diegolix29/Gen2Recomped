-- LZ11: the Nintendo LZ77 variant (type byte 0x11) that GARC members in
-- Omega Ruby / Alpha Sapphire are stored with. See lib/GARC.lua.
--
--   byte 0      0x11
--   bytes 1-3   decompressed size, little endian; 0 means the real size is
--               the u32 at bytes 4-7 and the stream starts at byte 8
--   then        a flag byte per 8 tokens, most significant bit first:
--               0 = one literal byte, 1 = a back-reference whose first
--               nibble says how its length is encoded
--
-- `maxOut` stops early once that many bytes are out, which is what lets the
-- probe read a member's magic without inflating a whole model.

local LZ11 = {}

local floor = math.floor
local unpack = unpack or table.unpack

function LZ11.is(data)
  return type(data) == "string" and #data >= 4 and data:byte(1) == 0x11
end

-- Declared output size, or nil when `data` is not LZ11.
function LZ11.size(data)
  if not LZ11.is(data) then return nil end
  local a, b, c = data:byte(2, 4)
  local n = a + b * 256 + c * 65536
  if n == 0 and #data >= 8 then
    local d, e, f, g = data:byte(5, 8)
    n = d + e * 256 + f * 65536 + g * 16777216
  end
  return n
end

function LZ11.decompress(data, maxOut)
  local total = LZ11.size(data)
  if not total then return nil, "not an LZ11 stream" end
  local a, b, c = data:byte(2, 4)
  local p = (a + b * 256 + c * 65536 == 0) and 9 or 5
  local want = (maxOut and maxOut < total) and maxOut or total
  local out, n = {}, 0
  local len = #data

  while n < want and p <= len do
    local flags = data:byte(p); p = p + 1
    for bitN = 7, 0, -1 do
      if n >= want then break end
      if floor(flags / 2 ^ bitN) % 2 == 0 then
        if p > len then break end
        n = n + 1; out[n] = data:byte(p); p = p + 1
      else
        local b1 = data:byte(p)
        if not b1 then break end
        local ind = floor(b1 / 16)
        local count, disp
        if ind == 0 then
          local b2, b3 = data:byte(p + 1, p + 2)
          count = (b1 % 16) * 16 + floor(b2 / 16) + 0x11
          disp = (b2 % 16) * 256 + b3 + 1
          p = p + 3
        elseif ind == 1 then
          local b2, b3, b4 = data:byte(p + 1, p + 3)
          count = (b1 % 16) * 4096 + b2 * 16 + floor(b3 / 16) + 0x111
          disp = (b3 % 16) * 256 + b4 + 1
          p = p + 4
        else
          local b2 = data:byte(p + 1)
          count = ind + 1
          disp = (b1 % 16) * 256 + b2 + 1
          p = p + 2
        end
        if disp > n then return nil, "LZ11 back-reference before start" end
        for _ = 1, count do
          if n >= want then break end
          n = n + 1; out[n] = out[n - disp]
        end
      end
    end
  end

  -- string.char takes a bounded argument list; build the result in slices
  local parts = {}
  for i = 1, n, 4096 do
    parts[#parts + 1] = string.char(unpack(out, i, math.min(n, i + 4095)))
  end
  return table.concat(parts)
end

return LZ11
