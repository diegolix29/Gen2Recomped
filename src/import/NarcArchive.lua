-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- NARC: the archive Gen 4 keeps almost everything in.
--
-- NdsRom hands back the bytes of a named file; in Platinum that file is
-- nearly always a NARC, and the thing actually wanted is one member inside
-- it.  /poketool/personal/pl_personal.narc is 26,468 bytes holding one
-- fixed-size record per species; /fielddata/script/scr_seq.narc is 1,124
-- script files.  So this is the second half of the floor: archive bytes in,
-- member bytes out.
--
-- The format is Nitro's standard three-chunk container:
--
--   "NARC" 0xFFFE bom, version, file size, header size, chunk count
--   "BTAF"  the file allocation table -- count, then start/end u32 PAIRS
--   "BTNF"  the file name table, almost always empty (members are numbered)
--   "GMIF"  the bytes themselves; BTAF offsets are relative to its data
--
-- TWO THINGS THAT LOOK SAFE TO ASSUME AND ARE NOT.
--
-- The chunks are found by WALKING them, not by adding fixed offsets: the
-- header size is a field precisely because it varies, and BTNF's size varies
-- with whether the archive names its members.
--
-- And the chunk magics are stored REVERSED on disk -- "BTAF" is the tag
-- "FATB" little-endian, "GMIF" is "FIMG".  Both spellings are in circulation
-- in format notes, so the tags are compared as the four bytes that are
-- actually there.

local NarcArchive = {}
NarcArchive.__index = NarcArchive

local byte, sub = string.byte, string.sub

local function u16(s, at)
  local a, b = byte(s, at, at + 1)
  if not b then return nil end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = byte(s, at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- `data` is the whole archive, as NdsRom:read returned it.
function NarcArchive.parse(data)
  if type(data) ~= "string" or #data < 16 then
    return nil, "not a NARC: too short"
  end
  if sub(data, 1, 4) ~= "NARC" then
    return nil, ("not a NARC: magic is %q"):format(sub(data, 1, 4))
  end
  local headerSize = u16(data, 13)
  local chunkCount = u16(data, 15)
  if not (headerSize and chunkCount) or headerSize < 16 then
    return nil, "NARC header is malformed"
  end

  local chunks, at = {}, headerSize + 1
  for _ = 1, chunkCount do
    if at + 8 > #data + 1 then break end
    local tag = sub(data, at, at + 3)
    local size = u32(data, at + 4)
    if not size or size < 8 then
      return nil, ("NARC chunk %q has an impossible size"):format(tag)
    end
    chunks[tag] = at
    at = at + size
  end

  local btaf, gmif = chunks.BTAF, chunks.GMIF
  if not btaf then return nil, "NARC has no BTAF (file allocation) chunk" end
  if not gmif then return nil, "NARC has no GMIF (file image) chunk" end

  local count = u16(data, btaf + 8)
  if not count then return nil, "NARC BTAF is truncated" end

  local self = setmetatable({
    data = data,
    count = count,
    -- +8 tag/size, +4 count/reserved, then the pairs; and GMIF's own 8-byte
    -- tag/size header is not part of the data the offsets are relative to.
    _entries = btaf + 12,
    _base = gmif + 8,
  }, NarcArchive)
  return self
end

-- Where member `i` (0-based, as the game numbers them) lives, or nil.
function NarcArchive:range(i)
  if not (i and i >= 0 and i < self.count) then return nil end
  local at = self._entries + i * 8
  local from = u32(self.data, at)
  local to = u32(self.data, at + 4)
  if not (from and to) or to < from then return nil end
  return self._base + from, to - from
end

-- Member `i`'s bytes.  Returns nil plus a reason rather than a short string,
-- because a member that runs past the archive means the archive is damaged
-- and a caller should say so rather than parse whatever came back.
function NarcArchive:get(i)
  local from, size = self:range(i)
  if not from then
    return nil, ("no member %s in a %d-member archive"):format(tostring(i), self.count)
  end
  if from + size - 1 > #self.data then
    return nil, ("member %d runs past the end of the archive"):format(i)
  end
  return sub(self.data, from, from + size - 1)
end

-- Every member, in order.  Convenient for the extraction stages, which
-- almost always want the whole archive; avoid it for the large ones
-- (pl_pokegra.narc is 11 MB) where one member at a time is the point.
function NarcArchive:all()
  local out = {}
  for i = 0, self.count - 1 do out[i + 1] = self:get(i) end
  return out
end

return NarcArchive
