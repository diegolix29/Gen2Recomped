-- THE DS's BACKWARD LZ ("BLZ"), the compression a cartridge's ARM9 binary and
-- its overlays may be stored in.
--
-- HeartGold and SoulSilver ship their ARM9 compressed; this project's Platinum
-- does not, which is why Platinum's map header table could be found in the raw
-- binary and HGSS's could not -- its 540 headers are there, packed.
--
-- WHETHER A BINARY IS COMPRESSED IS THE CARTRIDGE'S OWN ANSWER, not a guess
-- from the bytes: the ARM9 carries the SDK's module parameters (found by the
-- magic 0xDEC00621 0x2106C0DE), whose sixth word is `compressedStaticEnd` --
-- zero for a plain binary, the end address of the packed data otherwise.
--
-- The format (the SDK's, as ndstool's blz.c reads it): the last eight bytes
-- are { u32 header length << 24 | compressed length, u32 bytes gained }. The
-- data decodes from the end backwards: a flag byte, then eight tokens, most
-- significant flag first -- a 0 copies one byte, a 1 reads a u16 (high byte at
-- the higher address) whose top four bits plus 3 are a length and whose low
-- twelve plus 3 are how far ABOVE the write point to copy from. Everything
-- below the compressed region is stored as it is.

local B = {}

local MAGIC1, MAGIC2 = 0xDEC00621, 0x2106C0DE

local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- compressedEnd(arm9, ramBase) -> the file offset the packed data ends at, or nil
function B.compressedEnd(bin, ramBase)
  if type(bin) ~= "string" then return nil end
  local limit = math.min(#bin - 8, 0x4000)
  for at = 0, limit, 4 do
    if u32(bin, at) == MAGIC1 and u32(bin, at + 4) == MAGIC2 then
      local endAddr = u32(bin, at - 0x1C + 0x14)
      if not endAddr or endAddr == 0 then return nil end
      return endAddr - (ramBase or 0x02000000)
    end
  end
  return nil
end

-- decompress(bytes) -> the decoded bytes, or nil plus a reason
function B.decompress(data)
  local len = #data
  if len < 8 then return nil, "too short for a BLZ footer" end
  local word, inc = u32(data, len - 8), u32(data, len - 4)
  local hdrLen = math.floor(word / 16777216)
  local encLen = word % 16777216
  if hdrLen < 8 or hdrLen > 11 or encLen > len or inc == 0 then
    return nil, "no BLZ footer"
  end
  local out = {}
  for i = 1, len do out[i] = data:byte(i) end
  local total = len + inc
  for i = len + 1, total do out[i] = 0 end
  -- 1-based positions: `src` and `dst` point one past the next byte
  local src, dst = len - hdrLen + 1, total + 1
  local srcEnd = len - encLen + 1
  while src > srcEnd do
    src = src - 1
    local flags = out[src]
    for _ = 1, 8 do
      if src <= srcEnd then break end
      if flags >= 128 then
        local hi = out[src - 1]
        local lo = out[src - 2]
        src = src - 2
        local pos = hi * 256 + lo
        local n = math.floor(pos / 4096) + 3
        local disp = pos % 4096 + 3
        for _ = 1, n do
          dst = dst - 1
          if dst < 1 then break end
          out[dst] = out[dst + disp]
        end
      else
        src = src - 1
        dst = dst - 1
        out[dst] = out[src]
      end
      flags = (flags * 2) % 256
    end
  end
  local parts = {}
  local CHUNK = 4096
  for i = 1, total, CHUNK do
    parts[#parts + 1] = string.char(unpack(out, i, math.min(i + CHUNK - 1, total)))
  end
  return table.concat(parts)
end

-- The ARM9 as the game runs it: decompressed when the module parameters say
-- it is packed, as stored otherwise.
function B.arm9(bin, ramBase)
  local endAt = B.compressedEnd(bin, ramBase)
  if not endAt or endAt > #bin or endAt < 8 then return bin end
  local packed = bin:sub(1, endAt)
  local out = B.decompress(packed)
  if not out then return bin end
  return out .. bin:sub(endAt + 1)
end

return B
