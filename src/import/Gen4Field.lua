-- Where a new game starts, and where a blackout sends you.
--
-- THE BUG THIS EXISTS TO FIX, in the words of the comment that predicted it.
-- `field.lua` used to sit in Data.lua's CLASSIC_ONLY list for a stated reason:
-- "field.lua is where boot.startMap and boot.screens live, the overlay is
-- ADDITIVE, and a Gen 3 cache with no field of its own read RED'S -- which is
-- how NEW GAME on Emerald opened Red's intro in Red's house."  It was taken out
-- of that list when the Gen 3 extractor learned to write one.
--
-- Gen 4 does not write one.  So the first New Game on Platinum inherited Red's
-- field.lua, took `REDS_HOUSE_2F` as its start map, and died in MapLoader --
-- the same failure, one generation later, reintroduced by removing the guard
-- rather than by adding anything.  The fix is the one Gen 3 got: write a real
-- one.
--
-- WHERE THE ANSWER LIVES.  Not in a script: SCRIPT_ID(INIT_NEW_GAME, 0) is 119
-- instructions and every one of them is a `setflag` -- it arms the world, it
-- does not place the player.  The position is a pair of plain structs in the
-- ARM9, `sPlayerStartLocation` and `sPlayerFirstRespawnLocation`, which
-- FieldOverworldState hands to the new save before the field system starts.
--
--   Location = { s32 mapHeaderID, s32 warpId, s32 x, s32 z, s32 faceDirection }
--
-- FOUND BY SIGNATURE, NOT BY OFFSET.  The two structs are adjacent, and the
-- 40-byte pair occurs EXACTLY ONCE in the ARM9 -- so the search cannot pick the
-- wrong run, which is the failure mode three other finders in this project hit
-- before it.  At 0xEA12C in the USA Rev 1 binary; Rev 0 is a different build,
-- so the address is reported and never assumed.
--
-- THE FACE DIRECTION IS AN ENUM, NOT A STRING: FACE_UP = 0, then DOWN, LEFT,
-- RIGHT (FACE_NONE is -1).  The engine's saves carry "up"/"down"/"left"/
-- "right", so the mapping is here rather than at the call site.

local Gen4Field = {}

Gen4Field.OVERLAY = nil   -- ARM9, not an overlay

-- One Location is five signed 32-bit fields.
Gen4Field.LOCATION_BYTES = 20

Gen4Field.FACING = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
Gen4Field.WARP_ID_NONE = -1

local function s32(data, at)
  local a, b, c, d = data:byte(at + 1, at + 4)
  if not d then return nil end
  local value = a + b * 256 + c * 65536 + d * 16777216
  if value >= 2147483648 then value = value - 4294967296 end
  return value
end

local function location(data, at)
  local mapHeaderID = s32(data, at)
  local warpId = s32(data, at + 4)
  local x = s32(data, at + 8)
  local z = s32(data, at + 12)
  local facing = s32(data, at + 16)
  if not facing then return nil end
  return {
    mapHeaderID = mapHeaderID, warpId = warpId,
    x = x, z = z,
    facingId = facing,
    facing = Gen4Field.FACING[facing] or "down",
  }
end

-- plausible(loc, headerCount) -- the shape of a real Location.
local function plausible(loc, headerCount)
  if not loc then return false end
  if loc.mapHeaderID < 0 or loc.mapHeaderID >= headerCount then return false end
  if loc.warpId < -1 or loc.warpId > 255 then return false end
  if loc.x < 0 or loc.x > 4096 or loc.z < 0 or loc.z > 4096 then return false end
  if loc.facingId < -1 or loc.facingId > 3 then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- sSpawnLocations: every blackout and fly destination in Sinnoh
-- ---------------------------------------------------------------------------
--
--   u16 blackOutMapHeaderID, blackOutX, blackOutZ
--   u16 flyMapHeaderID, flyX, flyZ
--   u8  isWarpPos, unlockOnMapEntry
--   u16 firstArrival                                    -- 16 bytes
--
-- IDENTIFIED WITH TABLES THIS EXTRACTOR ALREADY HAS, not by shape alone, and
-- not by "longest run" either -- that picks a 26-row impostor at 0xEA548 whose
-- rows satisfy every loose constraint.  Two facts do the work, and both are
-- exact rather than statistical:
--
--   1. every blackout map is an INDOOR map in the map headers (20 of 20), and
--   2. a blackout position is a TILE IN THAT MAP, so it must fall inside that
--      map's own def.  The impostor's first row claims x = 513 in a 32x32
--      indoor map, which settles it immediately.
--
-- (2) is the one that matters: it is not a threshold that happened to fit, it
-- is the map's own width and height, read from the def this extractor built.
--
-- AND A THIRD CHECK THAT WAS WRITTEN HERE AND REMOVED, by the file that warns
-- about exactly this.  "firstArrival increases down the table" looks obvious --
-- rows 0..15 are 0,1,2,...,17 -- and it is FALSE: row 16 is 5.  The field is a
-- FIRST_ARRIVAL_* zone id, ordered by zone rather than by spawn order.  With it
-- in, the run stopped at 16 rows and four fly destinations vanished silently,
-- which is the same shape of loss as the 41 hidden items.  Checked against all
-- 20 rows before being deleted rather than tuned.
--
-- AND ONE INVARIANT DELIBERATELY NOT USED.  "Every fly map is a header with
-- allowFly" looks like the better check and is ALMOST true -- 18 of the 20
-- overlap, with R221 in the spawn table but not the header set, and D31/D32 the
-- other way.  This project has been bitten three times by an invariant that is
-- almost true (the type chart's first-match, the object-gfx ascending ids, the
-- hidden-item ceiling), so it is left out rather than tuned.
Gen4Field.SPAWN_BYTES = 16
Gen4Field.MIN_SPAWN_ROWS = 8

local function u16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end

local function spawnRow(data, at)
  local blackOut = u16(data, at)
  local blackOutX, blackOutZ = u16(data, at + 2), u16(data, at + 4)
  local fly = u16(data, at + 6)
  local flyX, flyZ = u16(data, at + 8), u16(data, at + 10)
  local isWarp, unlock = data:byte(at + 13), data:byte(at + 14)
  local firstArrival = u16(data, at + 14)
  if not firstArrival then return nil end
  return {
    blackOutMap = blackOut, blackOutX = blackOutX, blackOutZ = blackOutZ,
    flyMap = fly, flyX = flyX, flyZ = flyZ,
    isWarpPos = isWarp, unlockOnMapEntry = unlock,
    firstArrival = firstArrival,
  }
end

Gen4Field.INDOOR_MAP_TYPE = 4

-- indoor(headers, id) -> true when the map header says mapType 4.
local function indoor(headers, id)
  local header = headers and headers[id]
  return header ~= nil and header.mapType == Gen4Field.INDOOR_MAP_TYPE
end

-- inside(headers, maps, id, x, z) -> does this tile fall inside that map?
-- Returns false when the map is not known, because an unknown map cannot
-- vouch for a coordinate.
local function inside(headers, maps, id, x, z)
  local header = headers and headers[id]
  local def = header and maps and maps[header.internalName]
  if not (def and def.width and def.height) then return false end
  return x >= 0 and z >= 0 and x < def.width and z < def.height
end

-- spawnLocations(arm9, headers, headerCount) -> rows, offset
function Gen4Field.spawnLocations(arm9, headers, maps, headerCount)
  if type(arm9) ~= "string" then return nil end
  headerCount = headerCount or 600
  local size = Gen4Field.SPAWN_BYTES
  local bestAt, bestRows = nil, 0
  local at = 0
  while at <= #arm9 - size do
    local row = spawnRow(arm9, at)
    local valid = row and row.blackOutMap > 0 and row.blackOutMap < headerCount
      and row.flyMap > 0 and row.flyMap < headerCount
      and (row.isWarpPos or 2) <= 1 and (row.unlockOnMapEntry or 2) <= 1
      and indoor(headers, row.blackOutMap)
      and inside(headers, maps, row.blackOutMap, row.blackOutX, row.blackOutZ)
    if valid then
      local rows = 0
      while true do
        local each = spawnRow(arm9, at + rows * size)
        if not (each and each.blackOutMap > 0 and each.blackOutMap < headerCount
                and each.flyMap > 0 and each.flyMap < headerCount
                and (each.isWarpPos or 2) <= 1 and (each.unlockOnMapEntry or 2) <= 1
                and indoor(headers, each.blackOutMap)
                and inside(headers, maps, each.blackOutMap, each.blackOutX, each.blackOutZ)) then
          break
        end
        rows = rows + 1
      end
      if rows > bestRows then bestAt, bestRows = at, rows end
      at = at + math.max(rows, 1) * size
    else
      at = at + 4
    end
  end
  if not bestAt or bestRows < Gen4Field.MIN_SPAWN_ROWS then return nil end
  local out = {}
  for i = 0, bestRows - 1 do out[i + 1] = spawnRow(arm9, bestAt + i * size) end
  return out, bestAt
end

-- find(arm9, headers, headerCount) -> startLocation, respawnLocation, offset
--
-- WHY THIS NEEDS A SECOND TABLE.  Scanning for "two adjacent plausible
-- Locations, the second on a different map with larger coordinates" finds
-- THREE candidates in the ARM9, and narrowing by map type leaves TWO -- the
-- real pair and a perfectly shaped impostor at 0xEEA94 whose start is also an
-- indoor map and whose respawn is also outdoor and fly-enabled.  Stacking
-- another heuristic would be the same mistake this file warns about above.
--
-- What settles it is a fact rather than a shape: `sPlayerFirstRespawnLocation`
-- IS the fly target of the first spawn-location row, because the first respawn
-- in the game is the starting town.  So the spawn table is found first, and the
-- Location pair is required to agree with its row 0 on map, x and z.  Two
-- independent tables agreeing, which is the only thing that has held up.
function Gen4Field.find(arm9, headers, maps, headerCount)
  if type(arm9) ~= "string" then return nil, "no arm9" end
  headerCount = headerCount or 600
  local spawns, spawnAt = Gen4Field.spawnLocations(arm9, headers, maps, headerCount)
  if not spawns then return nil, "sSpawnLocations not found" end
  local first = spawns[1]

  local size = Gen4Field.LOCATION_BYTES
  local matches = {}
  for at = 0, #arm9 - size * 2, 4 do
    local start = location(arm9, at)
    if start and start.warpId == Gen4Field.WARP_ID_NONE and plausible(start, headerCount) then
      local respawn = location(arm9, at + size)
      if respawn and respawn.warpId == Gen4Field.WARP_ID_NONE
         and plausible(respawn, headerCount)
         and respawn.mapHeaderID == first.flyMap
         and respawn.x == first.flyX and respawn.z == first.flyZ then
        matches[#matches + 1] = { at = at, start = start, respawn = respawn }
      end
    end
  end
  if #matches ~= 1 then
    return nil, ("expected exactly one start/respawn pair, found %d"):format(#matches)
  end
  return matches[1].start, matches[1].respawn, matches[1].at, spawns, spawnAt
end

return Gen4Field
