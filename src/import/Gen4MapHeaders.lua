-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) map headers: the join that connects everything else.
--
-- Every other Gen 4 table lives in the filesystem and can be opened by name.
-- This one does not: the map header table is compiled into the ARM9 binary,
-- and it is the record that ties a map to its matrix, its area data, its
-- script file, its text bank, its wild encounters, its events and its music.
-- Without it the other modules each read correctly and none of them know
-- which map they belong to.
--
-- 593 records of 24 bytes, matching pokeplatinum's MapHeader:
--
--   00 u8  areaDataArchiveID       10 u16 dayMusicID
--   01 u8  preloadedMapObjectsID   12 u16 nightMusicID
--   02 u16 mapMatrixID             14 u16 wildEncountersArchiveID
--   04 u16 scriptsArchiveID        16 u16 eventsArchiveID
--   06 u16 initScriptsArchiveID    18 u16 mapLabelTextID:8 | windowID:8
--   08 u16 msgArchiveID            20 u8  weather   21 u8 cameraType
--                                  22 u16 mapType:7 battleBG:5 bike:1
--                                         running:1 escapeRope:1 fly:1
--
-- THE TABLE IS FOUND BY SEARCHING, NOT BY A HARDCODED OFFSET.  In this
-- project's Rev 1 cartridge it sits at ARM9 file offset 0x0E601C, but that
-- number is a fact about one build: Rev 0 is a different binary, and a
-- hardcoded offset there would read whatever happens to be at that address
-- and hand back 593 confident, wrong records.  So `find` scans for a run of
-- 24-byte records whose fields all index INSIDE the archives they name --
-- matrix < the matrix count, events < the event count, script < the script
-- count, and so on.  That signature is strong enough that the run either
-- appears or it does not.
--
-- WHY 593 AND NOT 594.  The scan finds 594 consecutive records that pass a
-- loose filter, and the 594th is not a map: tightened against the area-data
-- archive it fails immediately, while all of 0..592 pass EVERY cross-check
-- against six separate archives.  593 is also exactly the number of names in
-- /fielddata/maptable/mapname.bin.  Taking the loose answer would have added
-- one phantom map at the end -- the kind of off-by-one that only shows up
-- when something walks the whole table.
--
-- The strongest confirmation is coverage rather than shape: the 593 headers
-- between them reference all 534 members of zone_event.narc, highest index
-- 533, with none left over and none out of range.

local Gen4MapHeaders = {}

Gen4MapHeaders.RECORD_BYTES = 24
Gen4MapHeaders.NO_ENCOUNTERS = 0xFFFF

-- `labelText` indexes MESSAGE BANK 433, which holds 126 display names --
-- "Jubilife City", "Old Chateau", "Rock Peak Ruins".  It does NOT index
-- /fielddata/maptable/mapname.bin, which is a separate table of 593 INTERNAL
-- identifiers keyed by the map header id itself ("C01", "C05GYM0113",
-- "D25R0106").
--
-- Both tables have entries for every map and both were plausible, which is
-- exactly why this was checked rather than assumed: joining `labelText` to
-- mapname.bin succeeds on every record, never errors, and quietly reports
-- that Jubilife City is called "C01PC0101".  The bound that made it look
-- right -- labelText < 593 -- holds trivially, because labelText never
-- exceeds 125.
Gen4MapHeaders.LABEL_BANK = 433

-- The ARM9 is loaded at this address, so add it to a file offset to get the
-- address the game itself would use.
Gen4MapHeaders.ARM9_RAM_BASE = 0x02000000

-- Where the table sits in this project's cartridge.  A HINT for the search to
-- try first, never a value to trust on its own.
Gen4MapHeaders.KNOWN_OFFSET = 0x0E601C
Gen4MapHeaders.KNOWN_COUNT = 593

local floor = math.floor

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end

function Gen4MapHeaders.parse(record)
  if type(record) ~= "string" or #record < Gen4MapHeaders.RECORD_BYTES then
    return nil, "map header record is too short"
  end
  local label = u16(record, 18)
  local flags = u16(record, 22)
  local wild = u16(record, 14)
  return {
    areaData = u8(record, 0),
    preloadedObjects = u8(record, 1),
    matrix = u16(record, 2),
    scripts = u16(record, 4),
    initScripts = u16(record, 6),
    messages = u16(record, 8),
    dayMusic = u16(record, 10),
    nightMusic = u16(record, 12),
    -- 0xFFFF means this map has no wild Pokemon at all, which is not the same
    -- as encounter table 0 -- table 0 is a real water route.
    encounters = (wild ~= Gen4MapHeaders.NO_ENCOUNTERS) and wild or nil,
    events = u16(record, 16),
    labelText = label % 256,
    labelWindow = floor(label / 256),
    weather = u8(record, 20),
    camera = u8(record, 21),
    mapType = flags % 128,
    battleBackground = floor(flags / 128) % 32,
    allowBike = floor(flags / 4096) % 2 == 1,
    allowRunning = floor(flags / 8192) % 2 == 1,
    allowEscapeRope = floor(flags / 16384) % 2 == 1,
    allowFly = floor(flags / 32768) % 2 == 1,
  }
end

-- `limits` names how many members each referenced archive actually has, and
-- is what makes the search trustworthy.  Every field is required, because the
-- signature is only as strong as its weakest constraint.
--   { areaData, matrix, scripts, messages, encounters, events, names }
local function looksLikeHeader(arm9, at, limits)
  local h = Gen4MapHeaders.parse(arm9:sub(at + 1, at + Gen4MapHeaders.RECORD_BYTES))
  if not h then return false end
  return h.areaData < limits.areaData
     and h.matrix < limits.matrix
     and h.scripts < limits.scripts
     and h.initScripts < limits.scripts
     and h.messages < limits.messages
     and (h.encounters == nil or h.encounters < limits.encounters)
     and h.events < limits.events
     and h.labelText < limits.names
end

-- Returns the file offset and the record count, or nil plus a reason.
function Gen4MapHeaders.find(arm9, limits)
  if type(arm9) ~= "string" or type(limits) ~= "table" then
    return nil, "need the ARM9 bytes and the archive limits"
  end
  local function runAt(at)
    local n = 0
    while at + (n + 1) * Gen4MapHeaders.RECORD_BYTES <= #arm9 do
      if not looksLikeHeader(arm9, at + n * Gen4MapHeaders.RECORD_BYTES, limits) then break end
      n = n + 1
    end
    return n
  end

  -- Try the known offset first, so the usual case costs one check.
  local hinted = runAt(Gen4MapHeaders.KNOWN_OFFSET)
  if hinted >= 500 then return Gen4MapHeaders.KNOWN_OFFSET, hinted end

  -- Otherwise scan.  Word-aligned: the table is a compiled array and the
  -- compiler will not have placed it on an odd byte.
  local bestAt, bestN = nil, 0
  local at = 0
  while at + Gen4MapHeaders.RECORD_BYTES <= #arm9 do
    if looksLikeHeader(arm9, at, limits) then
      local n = runAt(at)
      if n > bestN then bestAt, bestN = at, n end
      -- Skip the run; every offset inside it would report a shorter version
      -- of the same table.
      at = at + math.max(n, 1) * Gen4MapHeaders.RECORD_BYTES
    else
      at = at + 4
    end
  end
  if bestN < 100 then
    return nil, ("no map header table found (longest plausible run was %d)"):format(bestN)
  end
  return bestAt, bestN
end

-- All the headers, given the ARM9 and the offset/count `find` returned.
function Gen4MapHeaders.all(arm9, at, count)
  local out = {}
  for i = 0, count - 1 do
    local o = at + i * Gen4MapHeaders.RECORD_BYTES
    local h = Gen4MapHeaders.parse(arm9:sub(o + 1, o + Gen4MapHeaders.RECORD_BYTES))
    if h then h.id = i; out[i] = h end
  end
  return out
end

return Gen4MapHeaders
