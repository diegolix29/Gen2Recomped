-- BLACK AND WHITE'S FIELD: zones, matrices and map chunks.
--
-- pokeblack has not decompiled the field, so every layout here was IDENTIFIED
-- IN THE CARTRIDGE and is checked against it by tools/gen5_import_check.lua:
--
-- ZONES, /a/0/1/2 (one file, 427 x 48 bytes) -- each field's range was
-- measured against the archive it indexes:
--   00 u8  map type             01 u8 (flags)
--   02 u16 area                 -- < 282: /a/0/1/4 texture sets, /a/1/0/8
--   04 u16 matrix               -- < 255: /a/0/0/9
--   06 u16 scripts  08 u16 init scripts   -- /a/0/5/7, always a pair
--   0A u16 story text bank      -- < 472: /a/0/0/3
--   0C..12 u16 music: spring, summer, autumn, winter
--   14 u16 wild encounters      -- /a/1/2/6, 0xFFFF none
--   16 u16 the zone's own id    -- its events, /a/1/2/5
--   18 u16 parent zone
--   1A u8  place name           -- system bank 89 ("Striaton City" for 6..15)
--   20 u16 the matrix again (the town map's)
--
-- MATRICES, /a/0/0/9: u32 hasZones, u16 width, u16 height, then width*height
-- u32 chunk ids (0xFFFFFFFF none) and, when hasZones, as many u32 zone ids.
-- Matrix 0 is Unova, 29 x 27: 8 + 29*27*4*2 = 6,272 bytes, the member's size.
--
-- CHUNKS, /a/0/0/8 (649): a two-letter magic, a u16 section count and the
-- section offsets (u32 each, then the end). 572 are "WB" with three sections
-- -- the NSBMD model, the permissions (u16 width 32, u16 height 32, then
-- 8 bytes a tile), the building placements (u32 count, 16 bytes each) -- and
-- the rest are "GC" (4 sections), "NG" (2) and "RD" (3). The model is always
-- the first section.

local M = {}

M.ZONE_BYTES = 48
M.NONE = 0xFFFFFFFF

local function u8(s, o) return s:byte(o + 1) or 0 end
local function u16(s, o) return u8(s, o) + u8(s, o + 1) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

function M.zones(bytes)
  local out = {}
  if type(bytes) ~= "string" then return out end
  for i = 0, math.floor(#bytes / M.ZONE_BYTES) - 1 do
    local o = i * M.ZONE_BYTES
    local wild = u16(bytes, o + 0x14)
    out[i] = {
      id = i, mapType = u8(bytes, o), flags = u8(bytes, o + 1),
      area = u16(bytes, o + 2), matrix = u16(bytes, o + 4),
      scripts = u16(bytes, o + 6), initScripts = u16(bytes, o + 8),
      messages = u16(bytes, o + 0x0A),
      music = { u16(bytes, o + 0x0C), u16(bytes, o + 0x0E), u16(bytes, o + 0x10), u16(bytes, o + 0x12) },
      encounters = wild ~= 0xFFFF and wild or nil,
      events = u16(bytes, o + 0x16), parent = u16(bytes, o + 0x18),
      nameIndex = u8(bytes, o + 0x1A),
      townMapMatrix = u16(bytes, o + 0x20),
      -- bits 9..15 of +0x1C: the camera, a record of /a/0/6/0 (the field
      -- camera set-up at 0x0218E018 reads it through 0x02013BBC)
      camera = math.floor(u16(bytes, o + 0x1C) / 512) % 128,
      -- THE ZONE'S DEFAULT STANDING SPOT: +0x24 x, +0x28 y, +0x2C z, u32 each.
      -- The new-game location setter (ARM9 0x2014204, called with zone 391,
      -- the player's room) copies these three into the start location when
      -- the zone has them (0x2013b90 reads them off this record).
      spawnX = u32(bytes, o + 0x24), spawnY = u32(bytes, o + 0x28), spawnZ = u32(bytes, o + 0x2C),
    }
  end
  return out
end

function M.matrix(bytes)
  if type(bytes) ~= "string" or #bytes < 8 then return nil end
  local hasZones, w, h = u32(bytes, 0), u16(bytes, 4), u16(bytes, 6)
  local cells = w * h
  if #bytes < 8 + cells * 4 * (hasZones ~= 0 and 2 or 1) then return nil end
  local chunks, zones = {}, nil
  for i = 0, cells - 1 do
    local v = u32(bytes, 8 + i * 4)
    chunks[i + 1] = v ~= M.NONE and v or nil
  end
  if hasZones ~= 0 then
    zones = {}
    for i = 0, cells - 1 do
      local v = u32(bytes, 8 + cells * 4 + i * 4)
      zones[i + 1] = v ~= M.NONE and v or nil
    end
  end
  return { width = w, height = h, chunks = chunks, zones = zones }
end

-- chunk(bytes) -> { kind, model, permissions (raw), buildings (raw) }
function M.chunk(bytes)
  if type(bytes) ~= "string" or #bytes < 8 then return nil, "too short" end
  local kind, n = bytes:sub(1, 2), u16(bytes, 2)
  if n < 1 or n > 8 then return nil, "no section table" end
  local offs = {}
  for i = 0, n do offs[i + 1] = u32(bytes, 4 + i * 4) end
  offs[n + 1] = offs[n + 1] ~= 0 and offs[n + 1] or #bytes
  local sections = {}
  for i = 1, n do
    local a, e = offs[i], offs[i + 1]
    if a > #bytes or e > #bytes or e < a then return nil, "section out of range" end
    sections[i] = bytes:sub(a + 1, e)
  end
  local out = { kind = kind, sections = sections, model = sections[1] }
  if kind == "WB" then out.permissions, out.buildings = sections[2], sections[3] end
  -- "GC" chunks (the Dreamyard's four, 279..282, and others with a second
  -- walking layer) carry FOUR sections: the model, the permissions in WB's
  -- 4 + 1024 x 8 bytes, a second 8,204-byte layer (not read yet), and the
  -- buildings (u32 count + 16 each). Read as WB, every tile fell back to
  -- "blocked" and the player could not take a step.
  if kind == "GC" then out.permissions, out.layer2, out.buildings = sections[2], sections[3], sections[4] end
  return out
end

return M
