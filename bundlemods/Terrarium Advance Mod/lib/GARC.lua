-- GARC: Game Freak's archive format, which nearly every RomFS file under a/
-- in Omega Ruby / Alpha Sapphire is (a/0/0/8 and so on -- the path is the
-- archive's number, not a folder of loose files).
--
--   header  "CRAG", header size, BOM 0xFEFF, version (0x0400 in ORAS),
--           section count (4), data offset, file size, ...
--   FATO    "OTAF", size, entry count u16, padding u16, then one u32 per
--           entry: where its FATB record starts (after FATB's 12-byte head)
--   FATB    "BTAF", size, entry count u32, then per entry a u32 bit vector
--           and, for each set bit, start/end/length u32 relative to the
--           data offset.  One entry can hold several sub-files.
--   FIMB    "BMIF": the data itself.
--
-- Members are usually LZ11 compressed (lib/LZ11.lua); `member()` inflates
-- them, `peek()` inflates only the first few bytes.
--
-- `rom` is an N3DSRom and `file` one of its RomFS files.

local V = ...
local LZ11 = V.require("LZ11")

local G = {}

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

function G.open(rom, file)
  local head = rom:readFile(file, 0, math.min(file.size, 0x40))
  if #head < 0x1C or head:sub(1, 4) ~= "CRAG" then return nil, "not a GARC" end
  local headerSize = u32(head, 5)
  local dataOffset = u32(head, 0x11)
  if headerSize >= file.size or dataOffset > file.size then return nil, "truncated GARC" end

  -- FATO and FATB both sit between the header and the data
  local tables = rom:readFile(file, headerSize, dataOffset - headerSize)
  if tables:sub(1, 4) ~= "OTAF" then return nil, "GARC has no FATO" end
  local fatoSize = u32(tables, 5)
  local count = u16(tables, 9)
  local fatb = fatoSize + 1
  if tables:sub(fatb, fatb + 3) ~= "BTAF" then return nil, "GARC has no FATB" end

  local entries = {}
  for i = 0, count - 1 do
    local p = fatb + 12 + u32(tables, 13 + i * 4)
    local bits = u32(tables, p)
    local subs, q = {}, p + 4
    for b = 0, 31 do
      if math.floor(bits / 2 ^ b) % 2 == 1 then
        local start, stop = u32(tables, q), u32(tables, q + 4)
        subs[#subs + 1] = { index = b, start = start, size = stop - start }
        q = q + 12
      end
    end
    entries[i + 1] = subs
  end

  local self = { rom = rom, file = file, count = count, dataOffset = dataOffset,
                 entries = entries, version = u16(head, 0x0B) }

  -- raw bytes of entry `i` (0-based), sub-file `s` (1-based, default 1)
  function self:raw(i, s)
    local sub = self.entries[i + 1] and self.entries[i + 1][s or 1]
    if not sub then return nil, "no such GARC member" end
    return rom:readFile(file, self.dataOffset + sub.start, sub.size)
  end

  -- `maxOut` inflates only that many leading bytes (the probe reads headers)
  function self:member(i, s, maxOut)
    local raw, err = self:raw(i, s)
    if not raw then return nil, err end
    if LZ11.is(raw) then
      local out = LZ11.decompress(raw, maxOut)
      if out then return out end
    end
    return raw
  end

  -- the first `n` bytes of a member, inflating only as far as needed
  function self:peek(i, s, n)
    local sub = self.entries[i + 1] and self.entries[i + 1][s or 1]
    if not sub then return nil end
    -- a few KB of compressed input is plenty for a few dozen output bytes
    local raw = rom:readFile(file, self.dataOffset + sub.start, math.min(sub.size, 4096))
    if LZ11.is(raw) then
      return LZ11.decompress(raw, n), true, LZ11.size(raw)
    end
    return raw:sub(1, n), false, sub.size
  end

  return self
end

return G
