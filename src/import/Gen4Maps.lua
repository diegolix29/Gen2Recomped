-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) maps: the matrix that lays the world out, and the land
-- chunks it lays out.
--
-- THIS IS WHERE GEN 4 STOPS RESEMBLING EVERY GENERATION ABOVE IT.  Gen 1-3
-- give you a map: a grid of metatile ids with a tileset, and the renderer
-- draws it.  Gen 4 gives you a MATRIX of fixed 32x32 chunks, and each chunk
-- carries a movement-permission grid, a list of placed building models, a 3D
-- MESH, and a separate height/collision structure.  The picture is a mesh,
-- not a tilemap, so nothing in the Gen 1-3 map pipeline applies to drawing
-- it -- but the permission grid is a plain 32x32 array of u16, and that is
-- enough to know where the player may walk.
--
-- TWO ARCHIVES.
--
-- /fielddata/mapmatrix/map_matrix.narc -- 289 matrices.  A matrix is the
-- world's layout: width x height chunks, each naming a land_data member.
--
--   u8 width, u8 height, u8 hasHeaders, u8 hasAltitude, u8 nameLength,
--   char name[nameLength]
--   u16 headers[w*h]     -- only when hasHeaders
--   u8  altitudes[w*h]   -- only when hasAltitude
--   u16 mapIds[w*h]      -- always; indexes land_data.narc
--
-- The two optional blocks are why this is parsed rather than indexed: a
-- reader that assumes they are present reads the map ids out of the header
-- table and lays the world out of the wrong chunks.  All 289 members account
-- for their length exactly under this layout, which is the check.  Matrix 0
-- is 30x30 and named "map" -- the Sinnoh overworld.
--
-- /fielddata/land_data/land_data.narc -- 666 chunks.  Four u32 sizes, then
-- four blocks in that order:
--
--   00 u32 permissionSize   (always 2048 = 32 * 32 * 2)
--   04 u32 objectSize
--   08 u32 modelSize
--   12 u32 bdhcSize
--   16 .. permissions, objects, model ("BMD0" NSBMD), bdhc ("BDHC")
--
-- All 666 members satisfy 16 + the four sizes == the file length, and the
-- permission block is 2048 in every single one.  Sizes are read, never
-- assumed: three of the four blocks are routinely empty on indoor chunks.
--
-- PERMISSIONS.  One u16 per tile, 32 x 32, row-major.  Bit 15 marks a tile
-- that is not part of the map at all -- the void around the land -- and the
-- low byte is the terrain behaviour.  Across the whole overworld only 54
-- distinct values occur and only TWO distinct high bytes (0x00 and 0x80),
-- which is what says bit 15 is a flag rather than part of a number.
--
-- VALIDATED BY LOOKING.  The 30x30 matrix was assembled into a 960x960
-- permission image and it is recognisably Sinnoh: Mt. Coronet running north
-- to south through the middle, the three lakes as enclosed pockets, the
-- Great Marsh's grid at Pastoria, and Route 223's water column up the east
-- coast to the Battle Zone.  A layout error anywhere in the matrix or the
-- chunk header would have scrambled that beyond recognition.
--
-- OBJECTS are 48 bytes each.  The field offsets below were not read off one
-- sample -- every field of all 3,476 placed objects in the cartridge was
-- tabulated, which is what pins the three scale components at +28/+32/+36
-- rather than the +24/+28/+32 that one hand-read hex dump suggested:
--
--   +00 u32 model id      360 distinct, every one inside build_model.narc
--   +04 i32 x             216 distinct    +28 i32 scaleX   ALWAYS 4096
--   +08 i32 y             121 distinct    +32 i32 scaleY   ALWAYS 4096
--   +12 i32 z             248 distinct    +36 i32 scaleZ   ALWAYS 4096
--   +16 +20 +24           ALWAYS 0        +40              0, except 1 on 16
--                                         +44              ALWAYS 0
--
-- The three constant zeros at +16..+24 are left unnamed on purpose.  They are
-- almost certainly a rotation, and every object in the game has none, so
-- there is nothing here to tell a rotation from a reserved field and naming
-- one would be a guess dressed as a fact.
--
-- 386 of the 387 non-empty object blocks are an exact multiple of 48; one
-- (member 506) has two bytes of padding after its three objects, so the count
-- comes from dividing and the remainder is ignored -- the same shape as the
-- trainer party files.
--
-- NOT PARSED HERE: the NSBMD mesh and the BDHC.  Those are the 3D half of
-- the problem and each deserves its own pass; the permission grid is what a
-- walkable world needs first.

local Gen4Maps = {}

Gen4Maps.CHUNK = 32                  -- tiles per side of a land chunk
Gen4Maps.PERMISSION_BYTES = 2048     -- 32 * 32 * 2
Gen4Maps.OBJECT_BYTES = 48
Gen4Maps.VOID = 0x8000               -- bit 15: this tile is not part of the map

-- 20.12 fixed point: the DS's usual coordinate format.
Gen4Maps.FIXED_ONE = 4096

local floor = math.floor

local function u8(s, o) return s:byte(o + 1) end
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
local function i32(s, o)
  local v = u32(s, o)
  if not v then return nil end
  return v < 2147483648 and v or v - 4294967296
end

-- ---------------------------------------------------------------------------
-- The matrix
-- ---------------------------------------------------------------------------

function Gen4Maps.matrix(data)
  if type(data) ~= "string" or #data < 5 then
    return nil, "map matrix is too short"
  end
  local w, h = u8(data, 0), u8(data, 1)
  local hasHeaders, hasAltitude, nameLength = u8(data, 2), u8(data, 3), u8(data, 4)
  local at = 5 + nameLength
  local n = w * h
  if w == 0 or h == 0 then return nil, "map matrix has no extent" end

  local out = { width = w, height = h, name = data:sub(6, 5 + nameLength) }
  local function take(count, wide)
    local t = {}
    for i = 0, count - 1 do
      t[i + 1] = wide and u16(data, at + i * 2) or u8(data, at + i)
    end
    at = at + count * (wide and 2 or 1)
    return t
  end
  if hasHeaders == 1 then out.headers = take(n, true) end
  if hasAltitude == 1 then out.altitudes = take(n, false) end
  out.maps = take(n, true)

  -- The length check that makes this trustworthy: every one of the
  -- cartridge's 289 matrices ends exactly here.
  out.exact = (at == #data)
  return out
end

-- The land_data index for the chunk at (x, y), 0-based.
function Gen4Maps.chunkAt(matrix, x, y)
  if not matrix or x < 0 or y < 0 or x >= matrix.width or y >= matrix.height then
    return nil
  end
  return matrix.maps[y * matrix.width + x + 1]
end

-- ---------------------------------------------------------------------------
-- Land chunks
-- ---------------------------------------------------------------------------

function Gen4Maps.land(data)
  if type(data) ~= "string" or #data < 16 then
    return nil, "land chunk is too short for its header"
  end
  local permSize, objSize = u32(data, 0), u32(data, 4)
  local modelSize, bdhcSize = u32(data, 8), u32(data, 12)
  if not bdhcSize then return nil, "land chunk header is truncated" end
  if 16 + permSize + objSize + modelSize + bdhcSize ~= #data then
    return nil, ("land chunk sizes (%d+%d+%d+%d+16) do not add up to %d bytes")
      :format(permSize, objSize, modelSize, bdhcSize, #data)
  end
  local at = 16
  local out = {}
  out.permissions = data:sub(at + 1, at + permSize); at = at + permSize
  out.objectData = data:sub(at + 1, at + objSize); at = at + objSize
  out.model = data:sub(at + 1, at + modelSize); at = at + modelSize
  out.bdhc = data:sub(at + 1, at + bdhcSize)
  return out
end

-- One tile's permission word, 0-based, or nil outside the chunk.
function Gen4Maps.permissionAt(land, x, y)
  if not land or x < 0 or y < 0 or x >= Gen4Maps.CHUNK or y >= Gen4Maps.CHUNK then
    return nil
  end
  return u16(land.permissions, (y * Gen4Maps.CHUNK + x) * 2)
end

-- Is this tile part of the map at all?  Bit 15 says no, and a chunk is mostly
-- this at the edges of the land.
function Gen4Maps.isVoid(word)
  return word == nil or word >= Gen4Maps.VOID
end

-- The terrain behaviour, which is the low byte -- the high byte carries only
-- the void flag.
function Gen4Maps.behaviour(word)
  return word and word % 256 or nil
end

-- The whole 32x32 grid as a flat array, row-major, for a caller that wants to
-- walk it rather than sample it.
function Gen4Maps.permissionGrid(land)
  if not land then return nil end
  local out = {}
  for i = 0, Gen4Maps.CHUNK * Gen4Maps.CHUNK - 1 do
    out[i + 1] = u16(land.permissions, i * 2)
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Placed building models
-- ---------------------------------------------------------------------------

-- Coordinates and scales are 20.12 fixed point; returned as numbers already
-- divided, because every caller wants the value and none wants the raw.
function Gen4Maps.objects(land)
  if not land then return nil end
  local data = land.objectData
  local n = floor(#data / Gen4Maps.OBJECT_BYTES)
  local out = {}
  for i = 0, n - 1 do
    local o = i * Gen4Maps.OBJECT_BYTES
    out[i + 1] = {
      model = u32(data, o),
      x = i32(data, o + 4) / Gen4Maps.FIXED_ONE,
      y = i32(data, o + 8) / Gen4Maps.FIXED_ONE,
      z = i32(data, o + 12) / Gen4Maps.FIXED_ONE,
      scaleX = i32(data, o + 28) / Gen4Maps.FIXED_ONE,
      scaleY = i32(data, o + 32) / Gen4Maps.FIXED_ONE,
      scaleZ = i32(data, o + 36) / Gen4Maps.FIXED_ONE,
      flag = u32(data, o + 40),
    }
  end
  return out
end

-- ---------------------------------------------------------------------------
-- A map definition the existing engine can load
-- ---------------------------------------------------------------------------

-- Assemble a matrix and its chunks into the SAME def shape Gen 3 produces, so
-- that the overworld, the collision walk and the minimap load a Platinum map
-- without a single new branch.  Gen3's own notes describe that shape:
--
--   blocks   a BINARY STRING, two bytes per cell, little endian, with
--            metatile in bits 0-9, collision in 10-11, elevation in 12-15
--   width    in CELLS, and a Gen 3 metatile IS one cell
--
-- Gen 4 has no metatiles -- the picture is a mesh -- so the metatile field
-- carries the tile's BEHAVIOUR byte instead.  That is the same trick Gen 3's
-- voxel work used when it needed a mesher to keep working on data it was not
-- written for: put a synthetic id in the field the consumer already reads
-- rather than teaching every consumer a second format.  A renderer that knows
-- Gen 4 can map behaviour to appearance; one that does not still gets a grid
-- of the right size with the right holes in it.
--
-- WHAT THIS DOES NOT CLAIM.  Collision is set from the VOID BIT ONLY, which is
-- certain: bit 15 means the tile is not part of the map.  Which of the 54
-- behaviour values are walls is NOT established, so no other tile is marked
-- impassable here.  A player dropped into one of these maps would walk
-- through fences.  Filling that in needs the behaviour bytes classified
-- against the cartridge, and inventing it now would put a wrong wall in the
-- cache that later looks like a map bug rather than a missing stage.
--
-- Elevation is left 0 for the same reason: Gen 4 keeps height in the BDHC
-- block, which is not parsed.

Gen4Maps.CELL_BYTES = 2

function Gen4Maps.mapDef(matrix, chunkFor)
  if not matrix or type(chunkFor) ~= "function" then return nil end
  local W = matrix.width * Gen4Maps.CHUNK
  local H = matrix.height * Gen4Maps.CHUNK

  -- Built as a flat array of two-character strings and concatenated once:
  -- a 960x960 overworld is 921,600 cells, and appending to a string in a loop
  -- that long is the difference between an import and a hang.
  local cells = {}
  for cy = 0, matrix.height - 1 do
    for ty = 0, Gen4Maps.CHUNK - 1 do
      local row = cy * Gen4Maps.CHUNK + ty
      for cx = 0, matrix.width - 1 do
        local land = chunkFor(Gen4Maps.chunkAt(matrix, cx, cy))
        local base = row * W + cx * Gen4Maps.CHUNK
        for tx = 0, Gen4Maps.CHUNK - 1 do
          local word = land and u16(land.permissions, (ty * Gen4Maps.CHUNK + tx) * 2)
          local behaviour, collision
          if Gen4Maps.isVoid(word) then
            behaviour, collision = 0, 1
          else
            behaviour, collision = word % 256, 0
          end
          local v = behaviour + collision * 1024
          cells[base + tx + 1] = string.char(v % 256, floor(v / 256))
        end
      end
    end
  end

  return {
    width = W,
    height = H,
    blocks = table.concat(cells),
    -- Every cell outside the map reads as void, which is what the border is.
    borderBlock = 0,
    generation = 4,
  }
end

-- ---------------------------------------------------------------------------
-- Map names
-- ---------------------------------------------------------------------------

-- /fielddata/maptable/mapname.bin is a flat table of 16-byte, zero-padded
-- ASCII names -- 9,488 bytes, so 593 entries, one per MAP HEADER and indexed
-- by header id.  These are the developers' INTERNAL identifiers, not what a
-- player sees: "C01" is Jubilife City, "C05GYM0113" its gym, "D25R0106" the
-- Old Chateau.  The player-facing names live in message bank 433, which a
-- header reaches through its own `labelText` field -- see Gen4MapHeaders,
-- where confusing the two is written up, because both joins succeed and only
-- one is right.
Gen4Maps.NAME_BYTES = 16

function Gen4Maps.mapNames(data)
  if type(data) ~= "string" then return nil end
  local out = {}
  for i = 0, floor(#data / Gen4Maps.NAME_BYTES) - 1 do
    local raw = data:sub(i * Gen4Maps.NAME_BYTES + 1, (i + 1) * Gen4Maps.NAME_BYTES)
    out[i] = (raw:gsub("%z.*$", ""))
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Regions: turning a shared grid back into maps
-- ---------------------------------------------------------------------------

-- WHICH HEADER OWNS WHICH CHUNK, from the matrix's own per-cell header array.
--
-- This is the structural break from Gen 1-3 that the rest of the pipeline has
-- to absorb.  A Gen 1-3 map IS a grid.  A Gen 4 overworld map is a REGION OF
-- ONE SEAMLESS GRID: 84 of the 593 headers name matrix 0, the 960x960 Sinnoh
-- overworld, and each contributes its own NPCs and warps at coordinates
-- measured from the matrix's corner rather than from its own.
--
-- Only TWO of the 289 matrices carry a header array -- the overworld and the
-- Underground.  For the other 287 the matrix is the map and this returns
-- nothing, which is the correct answer rather than a failure.
--
-- Header 0 is left out.  It owns 731 of the overworld's 900 chunks, which is
-- every cell no real map claims -- ocean, border, the space between routes --
-- and giving it a bounding box would produce one "map" the size of Sinnoh that
-- overlaps all the others.
function Gen4Maps.extents(matrix)
  if not matrix or not matrix.headers then return nil end

  local boxes = {}
  for cy = 0, matrix.height - 1 do
    for cx = 0, matrix.width - 1 do
      local header = matrix.headers[cy * matrix.width + cx + 1]
      if header and header ~= 0 then
        local box = boxes[header]
        if not box then
          box = { minX = cx, maxX = cx, minY = cy, maxY = cy, chunks = 0 }
          boxes[header] = box
        end
        if cx < box.minX then box.minX = cx end
        if cx > box.maxX then box.maxX = cx end
        if cy < box.minY then box.minY = cy end
        if cy > box.maxY then box.maxY = cy end
        box.chunks = box.chunks + 1
      end
    end
  end

  local out = {}
  for header, box in pairs(boxes) do
    out[header] = {
      chunkX = box.minX, chunkY = box.minY,
      chunkWidth = box.maxX - box.minX + 1,
      chunkHeight = box.maxY - box.minY + 1,
      chunks = box.chunks,
      x = box.minX * Gen4Maps.CHUNK,
      y = box.minY * Gen4Maps.CHUNK,
      width = (box.maxX - box.minX + 1) * Gen4Maps.CHUNK,
      height = (box.maxY - box.minY + 1) * Gen4Maps.CHUNK,
      -- A region is the BOUNDING BOX of the chunks a header owns, so a map
      -- with an L-shaped footprint gets a rectangle that includes chunks
      -- belonging to its neighbours.  Recorded rather than hidden: when
      -- `chunks` is less than chunkWidth * chunkHeight the box is not solid.
      solid = box.chunks == (box.maxX - box.minX + 1) * (box.maxY - box.minY + 1),
    }
  end
  return out
end

-- Cut a sub-rectangle out of a def built by mapDef, in TILES.
--
-- The grid is two bytes per cell and row-major, so a crop is a per-row slice
-- rather than a reshape; doing it any other way means rebuilding 921,600 cells
-- to keep 4,096 of them.
function Gen4Maps.crop(def, x, y, width, height)
  if not def or not def.blocks then return nil end
  if width <= 0 or height <= 0 then return nil end
  if x < 0 or y < 0 or x + width > def.width or y + height > def.height then
    return nil, "crop falls outside the layout"
  end

  local rows = {}
  for row = 0, height - 1 do
    local from = ((y + row) * def.width + x) * 2 + 1
    rows[row + 1] = def.blocks:sub(from, from + width * 2 - 1)
  end

  return {
    width = width,
    height = height,
    blocks = table.concat(rows),
    borderBlock = def.borderBlock,
    generation = 4,
    -- Where this sat in the layout it came from, so a seamless renderer can
    -- put it back and a warp landing on the shared grid can be translated.
    originX = x,
    originY = y,
  }
end

-- ---------------------------------------------------------------------------
-- Area data: which textures a map's ground and buildings wear
-- ---------------------------------------------------------------------------

-- A land chunk's mesh carries NO textures of its own -- all 666 of them -- so
-- the pictures come from somewhere else, and `areaDataArchiveID` in the map
-- header is what says where.  The record is eight bytes, four u16:
--
--   +0 buildings   -> /fielddata/areadata/area_build_model/area_build.narc
--                     AND .../areabm_texset.narc, which are the same length
--                     (71 each) and indexed together: one names the building
--                     models an area uses, the other holds their textures
--   +2 mapTexture  -> /fielddata/areadata/area_map_tex/map_tex_set.narc
--   +4 lighting    0..9
--   +6 flags       0..2
--
-- THE RANGES ARE WHAT PIN THE FIELDS.  Over all 75 areas +2 reaches 73 against
-- a 74-member archive and +0 reaches 70 against two 71-member ones, so +2 can
-- only be the map textures; +4 never passes 9 and +6 never passes 2, so
-- neither indexes anything here.  What +4 and +6 mean is not established and
-- they are named for what they are not.
Gen4Maps.AREA_RECORD_BYTES = 8

function Gen4Maps.areaData(record)
  if type(record) ~= "string" or #record < Gen4Maps.AREA_RECORD_BYTES then
    return nil, "area data record is too short"
  end
  return {
    buildings = u16(record, 0),
    mapTexture = u16(record, 2),
    lighting = u16(record, 4),
    flags = u16(record, 6),
  }
end

-- The building models an area uses: a count and then that many ids into
-- build_model.narc.  Every one of the 71 members ends exactly on its own
-- count, which is what says the leading u16 is a count rather than a first id.
function Gen4Maps.areaBuildings(data)
  if type(data) ~= "string" or #data < 2 then return nil end
  local count = u16(data, 0)
  if 2 + count * 2 ~= #data then
    return nil, ("area build list says %d models but is %d bytes"):format(count, #data)
  end
  local out = {}
  for i = 0, count - 1 do out[i + 1] = u16(data, 2 + i * 2) end
  return out
end

-- ---------------------------------------------------------------------------
-- The terrain mesh
-- ---------------------------------------------------------------------------

-- A land chunk's mesh is the fourth block of the chunk, an ordinary NSBMD, and
-- all 666 of them decode exactly against their own headers' counts.
--
-- IT SITS WHERE THE HEIGHT FIELD SAYS IT DOES.  The mesh spans -256..256 in
-- both horizontal axes, which is the same 512 units over 32 tiles that
-- `Gen4Bdhc` measured from the height plates -- two blocks of the same file,
-- neither read from the other, agreeing that a tile is sixteen units and the
-- chunk is centred on the origin.
--
-- AND THEY AGREE ABOUT THE GROUND, mostly.  Sampling every fourth tile of
-- every chunk, at tiles the permission grid calls land rather than void, and
-- asking the mesh how high its surface is under that point:
--
--   331 of 666 chunks agree with the BDHC at every point sampled
--   8,505 of 11,356 points agree to within 0.1 units -- not close, exact
--   1,655 more are within four units, and 55 are further than sixty-four
--
-- The agreement being EXACT where it happens is what makes this a check rather
-- than a correlation: a wrong scale or a wrong axis would produce a cloud of
-- near-misses, not three quarters of the points landing on the answer.
--
-- WHAT THE TAIL IS: 9,497 walkable tiles have no land-mesh triangle beneath
-- them at all.  The land mesh is not the whole floor -- indoor chunks are a
-- shell and their floors are building models -- so those points are the next
-- thing to establish rather than a disagreement about this one.
Gen4Maps.TERRAIN_TILE_UNITS = 16
Gen4Maps.TERRAIN_CHUNK_UNITS = 512

-- Where chunk (x, y) of a matrix stands, in world units, given that each
-- chunk's own mesh is centred on its origin.
function Gen4Maps.chunkOrigin(x, y)
  return x * Gen4Maps.TERRAIN_CHUNK_UNITS + Gen4Maps.TERRAIN_CHUNK_UNITS / 2,
         y * Gen4Maps.TERRAIN_CHUNK_UNITS + Gen4Maps.TERRAIN_CHUNK_UNITS / 2
end

return Gen4Maps
