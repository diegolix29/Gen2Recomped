-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Distortion World: the one dungeon whose floor is not in the map.
--
-- Every other Sinnoh map answers "can I stand here" out of its land_data
-- permission grid.  The Distortion World's grids are nearly empty -- 1F has
-- 92 non-void cells of 4,096 -- and that is not corruption, it is the design:
-- the floor you walk on is assembled at runtime from two sources that live
-- nowhere near the map.
--
--   1. /fielddata/tornworld/tw_arc.narc         -- per-map FLOATING PLATFORMS,
--      /fielddata/tornworld/tw_arc_attr.narc       their JUMP POINTS, the
--                                                  camera angles, and one
--                                                  32x32 terrain-attribute
--                                                  grid per platform.
--   2. ARM9 OVERLAY 9 -- the cast, the coordinate events, the moving
--      platforms and the elevator paths, as C tables.
--
-- Both are read from the user's own cartridge.  pret (pokeplatinum,
-- src/overlay009/ov9_02249960.c) supplies the STRUCTURE only.
--
-- ------------------------------------------------------------------ THE NARC
--
-- tw_arc member 0 is the map-info file: `int count` then `count` records of
--
--     u32 mapHeaderID   u16 mapFileIndex
--     s16 offsetTileX   s16 offsetAltitude   s16 offsetTileZ
--
-- 10 records, and the count is exact: 4 + 12 * 10 == 124 == the member's
-- length.  THE TEN ARE NOT CONSECUTIVE.  Map headers 573..583 are eleven maps
-- and 578 appears in no Distortion World table anywhere -- not the info file,
-- not the connection list, not the events -- so it is a spare.  Indexing this
-- file by `mapHeaderID - 573` therefore lands one floor out from B5F onward,
-- which is why every lookup here searches.
--
-- Member `mapFileIndex + 1` is that map's own file: a 5-int header of SECTION
-- SIZES, then the sections in that order.
--
--     int dummy00, floatingPlatformSectionSize, jumpPointSectionSize,
--         cameraAngleSectionSize, ghostPropSectionSize
--
-- and 20 + the four sizes == the member length for all ten files, which is
-- the check that the section order is right.  Each section is `int count`
-- followed by the records, and 4 + recordBytes * count == the section size in
-- every one of the thirty non-empty sections -- so the record widths below are
-- confirmed by arithmetic rather than by reading one sample.
--
-- A PLATFORM IS A 32x32 GRID GLUED TO A PLANE.  Its `kind` says which plane:
--
--     0 FLOOR       size(dx, 0,  dz)   the grid lies in X/Z
--     1 WEST_WALL   size(0,  dy, dz)   the grid lies in Y/Z, seen from +X
--     2 EAST_WALL   size(0,  dy, dz)   the grid lies in Y/Z, seen from -X
--     3 CEILING     size(dx, 0,  dz)   the grid lies in X/Z, upside down
--     4 INVALID     "not a platform" -- what a jump point targets to send the
--                   player back to the ordinary map
--
-- and the attribute lookup is `attr[vertical + horizontal * 32]` with
--
--     FLOOR      vertical = x - startX          horizontal = z - startZ
--     WEST_WALL  vertical = sizeY - (y - startY) horizontal = z - startZ
--     EAST_WALL  vertical = y - startY           horizontal = z - startZ
--     CEILING    vertical = sizeX - (x - startX) horizontal = z - startZ
--
-- ALL FOUR SHARE `horizontal = z - startZ`, which is the detail that makes
-- one grid serve four orientations, and the two inverted ones are inverted in
-- the VERTICAL axis only.
--
-- The attribute words have the SAME layout as a land_data permission word:
-- bit 15 is collision, the low byte is a tile behaviour.  That is worth
-- stating because it means the Distortion World needs no bespoke behaviour
-- table: the values that occur are 0 NONE, 8 CAVE_FLOOR, 21 WATER_SEA and
-- 90..93 JUMP_{NORTH,SOUTH,WEST,EAST}_TWICE, all ordinary Gen 4 behaviours.
--
-- --------------------------------------------------------------- OVERLAY 9
--
-- Overlay 9 is 41,856 bytes loaded at 0x02249960 and NOT compressed, so its
-- tables can be read straight out of the file.  Four of them are keyed by map
-- header id, and none of them is at a knowable offset -- so each is found by
-- its FINGERPRINT: the exact set of Distortion World maps it mentions.  The
-- four sets are distinct, which is what makes this identification rather than
-- guessing:
--
--     cast           all ten                          {573..577,579..583}
--     events         eight, and GiratinaRoom is 582   {573..577,579,581,582}
--     movingPlatforms eight, B6F is 580, no 582       {573..577,579,580,581}
--     simpleProps    four                             {573,579,582,583}
--
-- A candidate run is a sequence of 8-byte {u32 mapHeaderID, u32 pointer}
-- records whose pointers all land inside the overlay's own RAM range.  There
-- are 37 individual pairs in the overlay that pass that test and only four
-- runs, one per set above.
--
-- THE ELEVATOR TABLE IS FOUND A DIFFERENT WAY because it is an array of
-- values rather than pointers: `sElevatorPlatformPaths[22]`, 32 bytes each,
-- whose first field is the record's own index.  A run of 22 records where
-- `index == position` is the signature.
--
-- WHAT THE MOVING PLATFORMS ARE, WHICH IS THE POINT OF ALL OF THIS.  34
-- platforms over eight floors, and they fall into exactly two groups:
--
--   * 18 ELEVATOR SHUTTLES.  Each names an `elevatorPathIndex`, and following
--     that path's `finalTileYOffset` chain from the platform's own altitude
--     lands on ANOTHER FLOOR'S altitude, where there is a platform at the
--     SAME (x, z) whose index equals this platform's `destIndex`.  That holds
--     for 18 of 18 -- so every shuttle is a pair, and in a port with no
--     vertical axis a shuttle pair is simply a WARP between two floors at
--     identical map coordinates.
--   * 16 B2F HORIZONTAL PLATFORMS.  propKind 5 MEDIUM_MOVING_PLATFORM_1,
--     `persistedFlag` INVALID, and `elevatorPathIndex` 0 -- which is the
--     1F->B1F elevator and is meaningless for them.  They are driven by B2F's
--     own 24 coordinate events (48 of the world's 113 event commands are
--     MOVE_PLATFORM, and all 48 are B2F's), each carrying a +/-8 Z offset.
--
-- READING `elevatorPathIndex` AS MEANINGFUL FOR ALL 34 IS THE TRAP: it is a
-- valid-looking 0 on the sixteen platforms that do not use it, and following
-- it sends every B2F platform to a 1F elevator.  The three fields that
-- separate the groups are propKind, persistedFlag and whether the followed
-- path lands on a real floor altitude.

local Gen4DistWorld = {}

Gen4DistWorld.MAIN_PATH = "/fielddata/tornworld/tw_arc.narc"
Gen4DistWorld.ATTR_PATH = "/fielddata/tornworld/tw_arc_attr.narc"
Gen4DistWorld.OVERLAY = 9

Gen4DistWorld.GRID = 32                -- one attribute grid is 32 x 32
Gen4DistWorld.COLLISION_BIT = 0x8000
Gen4DistWorld.BEHAVIOUR_MASK = 0xFF

Gen4DistWorld.KIND_FLOOR = 0
Gen4DistWorld.KIND_WEST_WALL = 1
Gen4DistWorld.KIND_EAST_WALL = 2
Gen4DistWorld.KIND_CEILING = 3
Gen4DistWorld.KIND_INVALID = 4

Gen4DistWorld.KIND_NAMES = {
  [0] = "floor", [1] = "westWall", [2] = "eastWall", [3] = "ceiling",
  [4] = "none",
}

-- PROP_KIND_INVALID == PROP_KIND_COUNT == 25 terminates a simple-prop list.
Gen4DistWorld.PROP_KIND_INVALID = 25
-- ELEVATOR_PLATFORM_PATH_INVALID == ELEVATOR_PLATFORM_PATH_COUNT == 22.
Gen4DistWorld.ELEVATOR_PATH_COUNT = 22
Gen4DistWorld.ELEVATOR_PATH_INVALID = 22
-- DIST_WORLD_PLATFORM_FLAG_INVALID == DIST_WORLD_PLATFORM_FLAG_COUNT == 11.
Gen4DistWorld.PLATFORM_FLAG_INVALID = 11
-- Local ids of the cast start here; they are NOT map object indices.
Gen4DistWorld.BASE_LOCAL_ID = 128

Gen4DistWorld.MAP_FIRST = 573
Gen4DistWorld.MAP_LAST = 583

-- The names the decompilation gives the floors, keyed by map header id.  Only
-- names; every byte still comes from the cartridge.
Gen4DistWorld.FLOOR_NAMES = {
  [573] = "1F", [574] = "B1F", [575] = "B2F", [576] = "B3F", [577] = "B4F",
  [579] = "B5F", [580] = "B6F", [581] = "B7F", [582] = "giratinaRoom",
  [583] = "turnbackCaveRoom",
}

-- The four overlay tables, each identified by the exact set of maps it names.
Gen4DistWorld.TABLES = {
  { key = "cast",            maps = { 573, 574, 575, 576, 577, 579, 580, 581, 582, 583 } },
  { key = "events",          maps = { 573, 574, 575, 576, 577, 579, 581, 582 } },
  { key = "movingPlatforms", maps = { 573, 574, 575, 576, 577, 579, 580, 581 } },
  { key = "simpleProps",     maps = { 573, 579, 582, 583 } },
}

local floor = math.floor

local function u8(s, o) return s:byte(o + 1) or 0 end
local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end
local function s16(s, o)
  local v = u16(s, o)
  if not v then return nil end
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end
local function u32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end
local function s32(s, o)
  local v = u32(s, o)
  if not v then return nil end
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end

Gen4DistWorld.u16 = u16
Gen4DistWorld.u32 = u32

-- ------------------------------------------------------------------- the NARC

-- Member 0 of tw_arc: `int count` then 12-byte records.  The length check is
-- the whole validation, and it is exact rather than a bound.
function Gen4DistWorld.mapInfo(member)
  if type(member) ~= "string" or #member < 4 then
    return nil, "map-info member too short"
  end
  local count = s32(member, 0)
  if not count or count <= 0 or count > 64 then
    return nil, ("map-info count %s out of range"):format(tostring(count))
  end
  if 4 + count * 12 ~= #member then
    return nil, ("map-info is %d bytes, but 4 + 12 * %d = %d")
      :format(#member, count, 4 + count * 12)
  end
  local out = {}
  for i = 0, count - 1 do
    local o = 4 + i * 12
    out[#out + 1] = {
      header = u32(member, o),
      fileIndex = u16(member, o + 4),
      offsetX = s16(member, o + 6),
      offsetAltitude = s16(member, o + 8),
      offsetZ = s16(member, o + 10),
    }
  end
  return out
end

local function section(member, at, recordBytes, sectionSize, what)
  -- An absent section is zero records, not an error: five of the ten map
  -- files have no platforms and no jump points at all.
  if sectionSize == 0 then return 0, at end
  local count = s32(member, at)
  if not count or count < 0 then
    return nil, ("%s: unreadable count at %d"):format(what, at)
  end
  if 4 + recordBytes * count ~= sectionSize then
    return nil, ("%s: %d records of %d is %d bytes, section says %d")
      :format(what, count, recordBytes, 4 + recordBytes * count, sectionSize)
  end
  return count, at + 4
end

local function bounds(member, o)
  return {
    x = s16(member, o), y = s16(member, o + 2), z = s16(member, o + 4),
    sizeX = s16(member, o + 6), sizeY = s16(member, o + 8),
    sizeZ = s16(member, o + 10),
  }
end

Gen4DistWorld.PLATFORM_BYTES = 20
Gen4DistWorld.JUMP_BYTES = 40
Gen4DistWorld.CAMERA_BYTES = 24

-- One map's own file.  The five section sizes must account for the member
-- exactly; a reader that trusts the order without checking the total reads
-- the ghost props as platforms, which is a table of plausible nonsense.
function Gen4DistWorld.mapFile(member)
  if type(member) ~= "string" or #member < 20 then
    return nil, "map file shorter than its header"
  end
  local sizes = {}
  for i = 0, 4 do sizes[i] = s32(member, i * 4) end
  local total = 20 + sizes[1] + sizes[2] + sizes[3] + sizes[4]
  if total ~= #member then
    return nil, ("map file is %d bytes, sections account for %d")
      :format(#member, total)
  end

  local out = { platforms = {}, jumps = {}, cameras = {}, ghostPropBytes = sizes[4] }
  local at = 20

  local count, base = section(member, at, Gen4DistWorld.PLATFORM_BYTES, sizes[1], "platforms")
  if count == nil then return nil, base end
  for i = 0, count - 1 do
    local o = base + i * Gen4DistWorld.PLATFORM_BYTES
    out.platforms[#out.platforms + 1] = {
      kind = s16(member, o),
      attr = u16(member, o + 2),
      bounds = bounds(member, o + 4),
      tilesVertical = u16(member, o + 16),
      tilesHorizontal = u16(member, o + 18),
    }
  end
  at = at + sizes[1]

  count, base = section(member, at, Gen4DistWorld.JUMP_BYTES, sizes[2], "jump points")
  if count == nil then return nil, base end
  for i = 0, count - 1 do
    local o = base + i * Gen4DistWorld.JUMP_BYTES
    out.jumps[#out.jumps + 1] = {
      handler = u16(member, o),
      playerDir = s16(member, o + 2),
      bounds = bounds(member, o + 8),
      displaceX = s16(member, o + 20),
      displaceY = s16(member, o + 22),
      displaceZ = s16(member, o + 24),
      spriteAngle = s16(member, o + 26),
      steps = s16(member, o + 28),
      axis = u16(member, o + 30),
      inverted = u16(member, o + 32),
      finalDir = s16(member, o + 34),
      targetKind = s16(member, o + 36),
      targetIndex = u16(member, o + 38),
    }
  end
  at = at + sizes[2]

  count, base = section(member, at, Gen4DistWorld.CAMERA_BYTES, sizes[3], "camera angles")
  if count == nil then return nil, base end
  for i = 0, count - 1 do
    local o = base + i * Gen4DistWorld.CAMERA_BYTES
    out.cameras[#out.cameras + 1] = {
      bounds = bounds(member, o),
      angleX = u16(member, o + 12),
      angleY = u16(member, o + 14),
      angleZ = u16(member, o + 16),
      playerDir = s16(member, o + 18),
      steps = s32(member, o + 20),
    }
  end

  return out
end

-- One 32 x 32 attribute grid, as a flat array indexed 1..1024 in the
-- cartridge's own `vertical + horizontal * 32` order -- NOT transposed into
-- rows, because the four platform kinds each read the two axes differently
-- and a helpful transpose here would be wrong for three of them.
function Gen4DistWorld.attrGrid(member)
  local n = Gen4DistWorld.GRID * Gen4DistWorld.GRID
  if type(member) ~= "string" or #member ~= n * 2 then
    return nil, ("attribute grid is %s bytes, expected %d")
      :format(member and #member or "nil", n * 2)
  end
  local out = {}
  for i = 0, n - 1 do out[i + 1] = u16(member, i * 2) end
  return out
end

-- The attribute word for a world coordinate on a given platform, or nil when
-- the coordinate is outside the platform's bounds.  This is the lookup the
-- runtime needs and the one place the four kinds differ.
function Gen4DistWorld.attrAt(platform, grid, x, y, z)
  local b = platform.bounds
  if x < b.x or x > b.x + b.sizeX then return nil end
  if y < b.y or y > b.y + b.sizeY then return nil end
  if z < b.z or z > b.z + b.sizeZ then return nil end
  local vertical
  local kind = platform.kind
  if kind == Gen4DistWorld.KIND_FLOOR then
    vertical = x - b.x
  elseif kind == Gen4DistWorld.KIND_WEST_WALL then
    vertical = b.sizeY - (y - b.y)
  elseif kind == Gen4DistWorld.KIND_EAST_WALL then
    vertical = y - b.y
  elseif kind == Gen4DistWorld.KIND_CEILING then
    vertical = b.sizeX - (x - b.x)
  else
    return nil
  end
  local horizontal = z - b.z
  local idx = vertical + horizontal * (platform.tilesVertical or Gen4DistWorld.GRID)
  if idx < 0 or idx >= #grid then return nil end
  return grid[idx + 1]
end

function Gen4DistWorld.passable(attr)
  return attr ~= nil and (attr % 0x10000) < Gen4DistWorld.COLLISION_BIT
end

function Gen4DistWorld.behaviour(attr)
  if not attr then return nil end
  return attr % 0x100
end

-- ---------------------------------------------------------------- overlay 9

local function inOverlay(ram, size, p)
  return p ~= nil and p >= ram and p < ram + size
end

-- Find the four map-keyed tables by fingerprint.  `maps` must match EXACTLY:
-- a prefix match would let the ten-entry cast table answer for the eight-entry
-- events table, since the first five ids are the same.
function Gen4DistWorld.findTable(bin, ram, maps)
  local want = #maps
  for at = 0, #bin - want * 8, 4 do
    local ok = true
    for i = 1, want do
      local hid = u32(bin, at + (i - 1) * 8)
      local ptr = u32(bin, at + (i - 1) * 8 + 4)
      if hid ~= maps[i] or not inOverlay(ram, #bin, ptr) then ok = false; break end
    end
    if ok then
      -- and the record AFTER the run must not continue it, or this is a
      -- longer table that merely starts the same way.
      local nextHid = u32(bin, at + want * 8)
      local nextPtr = u32(bin, at + want * 8 + 4)
      local continues = nextHid ~= nil
        and nextHid >= Gen4DistWorld.MAP_FIRST and nextHid <= Gen4DistWorld.MAP_LAST
        and inOverlay(ram, #bin, nextPtr)
      if not continues then return at end
    end
  end
  return nil
end

-- sElevatorPlatformPaths[22], 32 bytes each, first field == own index.
Gen4DistWorld.ELEVATOR_BYTES = 32

function Gen4DistWorld.findElevatorPaths(bin)
  local n = Gen4DistWorld.ELEVATOR_PATH_COUNT
  local w = Gen4DistWorld.ELEVATOR_BYTES
  for at = 0, #bin - n * w, 4 do
    local ok = true
    for k = 0, n - 1 do
      if u16(bin, at + k * w) ~= k then ok = false; break end
    end
    if ok then
      local rows = {}
      for k = 0, n - 1 do
        local o = at + k * w
        rows[k] = {
          index = u16(bin, o),
          nextIndex = u16(bin, o + 2),
          finalX = s16(bin, o + 4),
          finalY = s16(bin, o + 6),
          finalZ = s16(bin, o + 8),
          changeMapsX = s16(bin, o + 10),
          changeMapsY = s16(bin, o + 12),
          changeMapsZ = s16(bin, o + 14),
          deltaX = s32(bin, o + 16),
          deltaY = s32(bin, o + 20),
          deltaZ = s32(bin, o + 24),
          flagToSet = u16(bin, o + 28),
          flagToClear = u16(bin, o + 30),
        }
      end
      -- every nextIndex is a real path or the INVALID sentinel, and every
      -- flag is a real flag or ITS sentinel.  A run that passes the index
      -- test but fails this is not the table.
      local sane = true
      for k = 0, n - 1 do
        local r = rows[k]
        if not (r.nextIndex == Gen4DistWorld.ELEVATOR_PATH_INVALID
                or (r.nextIndex >= 0 and r.nextIndex < n)) then sane = false end
        if r.flagToSet > Gen4DistWorld.PLATFORM_FLAG_INVALID then sane = false end
        if r.flagToClear > Gen4DistWorld.PLATFORM_FLAG_INVALID then sane = false end
      end
      if sane then return at, rows end
    end
  end
  return nil
end

-- A NULL-terminated array of pointers to records, each read by `reader`.
local function pointerList(bin, ram, ptr, reader)
  local out = {}
  local base = ptr - ram
  local k = 0
  while true do
    local p = u32(bin, base + k * 4)
    if not p or p == 0 or not inOverlay(ram, #bin, p) then break end
    local row = reader(bin, p - ram)
    if not row then break end
    out[#out + 1] = row
    k = k + 1
    if k > 512 then break end
  end
  return out
end

-- DistWorldObjectEvent: 4 u16 then an ObjectEvent.  ObjectEvent is 13 u16
-- followed by an fx32 that the compiler aligns to 4, so x and z sit at +24
-- and +26 INSIDE the ObjectEvent and y at +28 -- that is +32, +34 and +36
-- from the record's own start.  Reading x two bytes early gives
-- movementRangeZ, which is zero almost everywhere and therefore looks like a
-- column of plausible zeroes rather than an error.
local function readCast(bin, o)
  local lid = u16(bin, o + 8)
  if not lid then return nil end
  return {
    flagCond = u16(bin, o),
    flagCondVal = u16(bin, o + 2),
    rotated = u16(bin, o + 4),
    rotationAngle = u16(bin, o + 6),
    localId = lid,
    graphicsId = u16(bin, o + 10),
    movementType = u16(bin, o + 12),
    trainerType = u16(bin, o + 14),
    hiddenFlag = u16(bin, o + 16),
    script = u16(bin, o + 18),
    x = u16(bin, o + 32),
    z = u16(bin, o + 34),
    -- fx32, and the Distortion World's altitudes are whole tiles of 16, so
    -- the tile altitude is (y >> 12) / 16.
    y = floor((s32(bin, o + 36) or 0) / 4096 / 16),
  }
end

local function readMovingPlatform(bin, o)
  local idx = u16(bin, o)
  if not idx then return nil end
  return {
    index = idx,
    x = s16(bin, o + 2),
    y = s16(bin, o + 4),
    z = s16(bin, o + 6),
    elevatorPath = u16(bin, o + 8),
    elevatorDir = u16(bin, o + 10),
    destIndex = u32(bin, o + 12),
    propKind = u32(bin, o + 16),
    persistedFlag = u32(bin, o + 20),
  }
end

Gen4DistWorld.EVENT_BYTES = 16
Gen4DistWorld.EVENT_CMD_BYTES = 8
Gen4DistWorld.EVENT_CMD_END = 18

Gen4DistWorld.EVENT_CMD_NAMES = {
  [0] = "setMapObjectAnimation", "movePlatform", "addMapObjectWithLocalId",
  "deleteMapObjectWithLocalId", "cascadeUp", "startScript",
  "setDistortionWorldProgress", "showGiratinaShadow",
  "setGiratinaAnimationFlag", "setPuzzleFlag", "cascadeDown",
  "playGiratinaArrival", "showUxieBoulderTuto", "showAzelfBoulderTuto",
  "showMespritBoulderTuto", "showGiratinaRoomPlatforms",
  "hideGiratinaRoomPlatforms", "clearPuzzleFlag",
}

-- A coordinate event: position, a flag condition, and a NULL-terminated
-- command list.  The command PARAMETERS are a union behind a pointer and are
-- not decoded here -- only the kinds, which is what says what the event does.
local function readEvents(bin, ram, ptr)
  local out = {}
  local base = ptr - ram
  local k = 0
  while true do
    local o = base + k * Gen4DistWorld.EVENT_BYTES
    local cmds = u32(bin, o + 12)
    if not cmds or cmds == 0 then break end
    if not inOverlay(ram, #bin, cmds) then break end
    local list = {}
    local co = cmds - ram
    local j = 0
    while true do
      local kind = u32(bin, co + j * Gen4DistWorld.EVENT_CMD_BYTES)
      if not kind or kind >= Gen4DistWorld.EVENT_CMD_END then break end
      list[#list + 1] = Gen4DistWorld.EVENT_CMD_NAMES[kind] or kind
      j = j + 1
      if j > 64 then break end
    end
    out[#out + 1] = {
      x = s16(bin, o),
      y = s16(bin, o + 2),
      z = s32(bin, o + 4),
      flagCond = u16(bin, o + 8),
      flagCondVal = u16(bin, o + 10),
      commands = list,
    }
    k = k + 1
    if k > 256 then break end
  end
  return out
end

-- DistWorldSimplePropTemplate is a VALUE array, not a pointer array, and it
-- ends at PROP_KIND_INVALID.  Terminating on "all zero" instead reads past
-- the end into the next map's list, because a legitimate row can be zero in
-- every field the test looks at.
local function readSimpleProps(bin, ram, ptr)
  local out = {}
  local base = ptr - ram
  local k = 0
  while true do
    local o = base + k * 16
    local kind = u16(bin, o + 4)
    if not kind or kind >= Gen4DistWorld.PROP_KIND_INVALID then break end
    out[#out + 1] = {
      propKind = kind,
      x = s16(bin, o + 6),
      y = s16(bin, o + 8),
      z = s16(bin, o + 10),
      flagCond = u16(bin, o + 12),
      flagCondVal = u16(bin, o + 14),
    }
    k = k + 1
    if k > 64 then break end
  end
  return out
end

-- Read one map-keyed table into `{ [mapHeaderID] = rows }`.
function Gen4DistWorld.readTable(bin, ram, at, maps, key)
  local out = {}
  for i = 1, #maps do
    local hid = u32(bin, at + (i - 1) * 8)
    local ptr = u32(bin, at + (i - 1) * 8 + 4)
    if key == "cast" then
      out[hid] = pointerList(bin, ram, ptr, readCast)
    elseif key == "movingPlatforms" then
      out[hid] = pointerList(bin, ram, ptr, readMovingPlatform)
    elseif key == "events" then
      out[hid] = readEvents(bin, ram, ptr)
    elseif key == "simpleProps" then
      out[hid] = readSimpleProps(bin, ram, ptr)
    end
  end
  return out
end

-- ------------------------------------------------------------- the whole lot

-- Split the moving platforms into the two groups the data actually contains,
-- and PROVE the shuttle half rather than asserting it: follow each platform's
-- elevator-path chain, and require a platform at the same (x, z) on the
-- altitude it lands on whose index is this platform's destIndex.  A platform
-- that fails is classified as horizontal, not silently kept as a shuttle.
function Gen4DistWorld.classify(movingPlatforms, elevatorPaths)
  local byAltitude = {}
  for hid, rows in pairs(movingPlatforms) do
    if rows[1] then byAltitude[rows[1].y] = hid end
  end
  local shuttles, horizontal = {}, {}
  for hid, rows in pairs(movingPlatforms) do
    for _, pl in ipairs(rows) do
      local dy, p, guard = 0, pl.elevatorPath, 0
      while elevatorPaths[p] and guard < #elevatorPaths + 2 do
        dy = dy + (elevatorPaths[p].finalY or 0)
        local n = elevatorPaths[p].nextIndex
        if n == Gen4DistWorld.ELEVATOR_PATH_INVALID or not elevatorPaths[n] then break end
        p = n; guard = guard + 1
      end
      local target = byAltitude[pl.y + dy]
      local match
      if target then
        for _, q in ipairs(movingPlatforms[target]) do
          if q.x == pl.x and q.z == pl.z then match = q end
        end
      end
      -- The test is the PAIRING, not the flag.  `persistedFlag` records that
      -- a platform has been moved and only ONE END of each pair owns it: the
      -- other end carries DIST_WORLD_PLATFORM_FLAG_INVALID.  Requiring a real
      -- flag therefore drops exactly one end of every shuttle -- 18 pairs
      -- become 11 -- and calls half a working lift a horizontal platform.
      if match and match.index == pl.destIndex then
        shuttles[#shuttles + 1] = {
          from = hid, to = target, index = pl.index, destIndex = pl.destIndex,
          x = pl.x, z = pl.z, fromAltitude = pl.y, toAltitude = pl.y + dy,
          propKind = pl.propKind, persistedFlag = pl.persistedFlag,
          elevatorPath = pl.elevatorPath, elevatorDir = pl.elevatorDir,
        }
      else
        horizontal[#horizontal + 1] = {
          map = hid, index = pl.index, x = pl.x, y = pl.y, z = pl.z,
          destIndex = pl.destIndex, propKind = pl.propKind,
        }
      end
    end
  end
  table.sort(shuttles, function(a, b)
    if a.from ~= b.from then return a.from < b.from end
    return a.index < b.index
  end)
  table.sort(horizontal, function(a, b)
    if a.map ~= b.map then return a.map < b.map end
    return a.index < b.index
  end)
  return shuttles, horizontal
end

return Gen4DistWorld
