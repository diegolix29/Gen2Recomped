-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) map events: who stands on a map, where its exits go, and
-- what watches the player.
--
-- /fielddata/eventdata/zone_event.narc, 534 members.  Four blocks, and the
-- COUNTS ARE INTERLEAVED -- each block is a u32 count immediately followed by
-- its own records, rather than four counts up front:
--
--   u32 n; Sign[n]     20 bytes each
--   u32 n; Npc[n]      32 bytes each
--   u32 n; Warp[n]     12 bytes each
--   u32 n; Trigger[n]  16 bytes each
--
-- Reading four counts first looks right on member 0 -- sixteen zero bytes,
-- which is a map with no events either way -- and then falls apart on every
-- populated map.  The interleaved layout with these four strides accounts for
-- all 534 members EXACTLY, and it is the only combination in a search over
-- every stride from 8 to 40 that does: the next best fits fewer than 15.
--
-- WHICH BLOCK IS WHICH was settled by measurement, not by the order they
-- happen to appear in:
--
--   NPCs     every one of the 3,555 records has a model id at +2 below 470,
--            which is exactly the member count of /data/mmodel/mmodel.narc,
--            the overworld model archive.
--   Warps    1,207 of 1,213 have a destination at +4 below 593, which is the
--            number of map names in /fielddata/maptable/mapname.bin; the
--            other six are 4095, a "nowhere" sentinel.  The fields at +0/+2
--            reach 909, so they cannot be map ids and are coordinates.
--   Triggers ALL 186 records carry a value at +14 of 0x4000 or above, which
--            is Gen 4's variable space -- a trigger is a variable, a value to
--            match and a script.
--
--   BgEvents the remaining block.  This one was first identified by shape
--            alone -- a script id, a position, a small type field -- and then
--            CONFIRMED: pokeplatinum's MapHeaderData lists its four event
--            arrays as bgEvents, objectEvents, warpEvents, coordEvents, in
--            exactly the order the file stores them.
--
-- AND THE STRUCTS CORRECTED A MISTAKE WORTH KEEPING IN MIND.  Reading these
-- blocks by measurement alone produced the right fields with the wrong AXES:
-- Gen 4 is three-dimensional, so the two horizontal axes are X and Z and Y is
-- HEIGHT.  The field after x is z, not y.  Measuring found the height fields
-- sitting at zero on almost every event and filed them as padding; they are
-- not padding, and an ObjectEvent's height is a 20.12 fixed-point value at
-- +28 rather than the u16 at +30 that a byte census suggested.  A census
-- tells you which bytes vary.  It cannot tell you what they mean.

local Gen4Events = {}

Gen4Events.STRIDES = {
  bgEvents = 20, objectEvents = 32, warpEvents = 12, coordEvents = 16,
}

-- A warp whose destination is this goes nowhere; six in the cartridge do.
Gen4Events.NO_DESTINATION = 4095

-- Gen 4 variables start here, which is what identified the trigger block.
Gen4Events.VARIABLE_BASE = 0x4000

local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end
local function u32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function s16(r, o)
  local v = u16(r, o)
  if not v then return nil end
  return v < 32768 and v or v - 65536
end

-- fx32: the DS's 20.12 fixed point, so the value is the integer over 4096.
local function fx32(r, o)
  local v = u32(r, o)
  if not v then return nil end
  if v >= 2147483648 then v = v - 4294967296 end
  return v / 4096
end

local function bgEvent(r)
  return {
    script = u16(r, 0),
    kind = u16(r, 2),
    x = u32(r, 4),
    z = u32(r, 8),          -- the second HORIZONTAL axis, not height
    y = u32(r, 12),         -- height
    playerFacing = u16(r, 16),
  }
end

local function objectEvent(r)
  return {
    localId = u16(r, 0),
    graphics = u16(r, 2),       -- indexes mmodel.narc
    movementType = u16(r, 4),
    trainerType = u16(r, 6),
    hiddenFlag = u16(r, 8),
    script = u16(r, 10),
    direction = s16(r, 12),
    data = { u16(r, 14), u16(r, 16), u16(r, 18) },
    rangeX = s16(r, 20),
    rangeZ = s16(r, 22),
    x = u16(r, 24),
    z = u16(r, 26),
    y = fx32(r, 28),            -- height, 20.12 fixed point across 4 bytes
  }
end

local function warpEvent(r)
  return {
    x = u16(r, 0),
    z = u16(r, 2),
    destination = u16(r, 4),   -- a map header id, or NO_DESTINATION
    anchor = u16(r, 6),        -- which warp on the destination map
  }
end

local function coordEvent(r)
  return {
    script = u16(r, 0),
    x = u16(r, 2),
    z = u16(r, 4),
    width = u16(r, 6),
    length = u16(r, 8),
    y = u16(r, 10),            -- height
    value = u16(r, 12),
    variable = u16(r, 14),     -- always >= VARIABLE_BASE
  }
end

-- Named as pokeplatinum names them.  The friendlier aliases below exist
-- because "bgEvent" and "coordEvent" say what the cartridge calls them, not
-- what they do.
local ORDER = {
  { "bgEvents", 20, bgEvent },
  { "objectEvents", 32, objectEvent },
  { "warpEvents", 12, warpEvent },
  { "coordEvents", 16, coordEvent },
}

-- One zone_event member.  Returns the four lists, plus `exact` saying whether
-- the record consumed the member to the byte -- which it does for all 534.
function Gen4Events.parse(data)
  if type(data) ~= "string" or #data < 16 then
    return nil, "zone event record is too short"
  end
  local out, at = {}, 0
  for _, spec in ipairs(ORDER) do
    local key, stride, build = spec[1], spec[2], spec[3]
    local n = u32(data, at)
    if not n then return nil, ("zone event truncated before %s"):format(key) end
    at = at + 4
    if at + n * stride > #data then
      return nil, ("zone event declares %d %s but has room for fewer"):format(n, key)
    end
    local list = {}
    for i = 0, n - 1 do
      list[i + 1] = build(data:sub(at + i * stride + 1, at + (i + 1) * stride))
    end
    out[key] = list
    at = at + n * stride
  end
  out.exact = (at == #data)
  -- Aliases in the words the rest of this engine uses: an object event is an
  -- NPC, a coord event is a trigger, a bg event is a sign or other thing you
  -- press A at.  Same tables, not copies.
  out.npcs = out.objectEvents
  out.warps = out.warpEvents
  out.signs = out.bgEvents
  out.triggers = out.coordEvents
  return out
end

function Gen4Events.all(archive)
  local out = {}
  for i = 0, archive.count - 1 do
    local e = Gen4Events.parse(archive:get(i))
    if e then e.id = i; out[i] = e end
  end
  return out
end

return Gen4Events
