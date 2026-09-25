-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) wild encounter tables.
--
-- /fielddata/encountdata/pl_enc_data.narc: 183 areas of exactly 424 bytes.
-- That 424 is the check: pokeplatinum's WildEncounters struct sums to 424 to
-- the byte, so a layout that reads right also adds up right.
--
--   000 i32  grass encounter rate
--   004 GrassEncounter[12]   -- s8 level, 3 padding, i32 species  (8 each)
--   100 i32  swarm[2]        108 i32 day[2]        116 i32 night[2]
--   124 i32  radar[4]        140 i32 formRates[5]  160 i32 unownTable
--   164 i32  dualSlot Ruby[2] / Sapphire / Emerald / FireRed / LeafGreen
--   204 WaterEncounters surf      -- i32 rate, then 5 x { s8 maxLevel,
--   248 WaterEncounters unused        s8 minLevel, 2 padding, i32 species }
--   292 WaterEncounters oldRod
--   336 WaterEncounters goodRod
--   380 WaterEncounters superRod
--
-- TWO THINGS THAT LOOK LIKE MISTAKES AND ARE NOT.
--
-- Species ids are FOUR BYTES here, not the two they are everywhere else in
-- the cartridge, and each grass slot spends three bytes on padding after a
-- one-byte level.  Reading them as u16 halves the stride and walks the table
-- into itself.
--
-- A water slot stores MAXIMUM level FIRST, then minimum.  The reversed order
-- is not a typo in this comment -- the cartridge really does put the larger
-- number first, and reading it the other way round yields ranges like
-- "Lv30-55" printed as "Lv55-30", which is the sort of thing that reads as a
-- display bug rather than a parse one.
--
-- Twelve of the 183 areas have a grass rate of 0 with the whole grass table
-- zeroed: those are water-only routes, and their level-0 slots are correct
-- data, not corruption.  Validated on that basis: 2,196 grass slots across
-- every area, zero species out of range, and zero out-of-range levels in any
-- area whose rate is non-zero.  The first land area comes out Geodude, Zubat
-- and Onix at levels 4-8, which is Oreburgh Gate.

local Gen4Encounters = {}

Gen4Encounters.RECORD_BYTES = 424
Gen4Encounters.GRASS_SLOTS = 12
Gen4Encounters.WATER_SLOTS = 5

-- The chance of each grass slot, in twelfths of a percent of the roll, as the
-- series has used since Gen 3.  Kept here because the cartridge stores it in
-- code rather than in this file, so a reader of the table alone cannot tell
-- that slot 0 is twenty times likelier than slot 11.
Gen4Encounters.GRASS_RATES = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
Gen4Encounters.WATER_RATES = { 60, 30, 5, 4, 1 }

local floor = math.floor

local function u8(s, o) return s:byte(o + 1) end
local function i32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  if not d then return nil end
  local v = a + b * 256 + c * 65536 + d * 16777216
  return v < 2147483648 and v or v - 4294967296
end

local function waterBlock(record, at)
  local out = { rate = i32(record, at), slots = {} }
  for i = 0, Gen4Encounters.WATER_SLOTS - 1 do
    local o = at + 4 + i * 8
    -- maxLevel first, then minLevel -- see the header note.
    out.slots[i + 1] = {
      maxLevel = u8(record, o),
      minLevel = u8(record, o + 1),
      species = i32(record, o + 4),
      chance = Gen4Encounters.WATER_RATES[i + 1],
    }
  end
  return out
end

function Gen4Encounters.parse(record)
  if type(record) ~= "string" or #record < Gen4Encounters.RECORD_BYTES then
    return nil, ("encounter record is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1, Gen4Encounters.RECORD_BYTES)
  end
  local grass = {}
  for i = 0, Gen4Encounters.GRASS_SLOTS - 1 do
    local o = 4 + i * 8
    grass[i + 1] = {
      level = u8(record, o),
      species = i32(record, o + 4),
      chance = Gen4Encounters.GRASS_RATES[i + 1],
    }
  end
  local function ints(at, n)
    local t = {}
    for i = 0, n - 1 do t[i + 1] = i32(record, at + i * 4) end
    return t
  end
  return {
    grassRate = i32(record, 0),
    grass = grass,
    swarm = ints(100, 2),
    day = ints(108, 2),
    night = ints(116, 2),
    radar = ints(124, 4),
    formRates = ints(140, 5),
    unownTable = i32(record, 160),
    dualSlot = {
      ruby = ints(164, 2), sapphire = ints(172, 2), emerald = ints(180, 2),
      firered = ints(188, 2), leafgreen = ints(196, 2),
    },
    surf = waterBlock(record, 204),
    unused = waterBlock(record, 248),
    oldRod = waterBlock(record, 292),
    goodRod = waterBlock(record, 336),
    superRod = waterBlock(record, 380),
  }
end

-- A rate of 0 means the method does not happen here at all, and its slots are
-- zeroed rather than absent -- so ask this rather than looking for empty data.
function Gen4Encounters.hasGrass(area) return area and area.grassRate > 0 end

function Gen4Encounters.all(archive)
  local out = {}
  for i = 0, archive.count - 1 do
    local a = Gen4Encounters.parse(archive:get(i))
    if a then a.id = i; out[i] = a end
  end
  return out
end

return Gen4Encounters
