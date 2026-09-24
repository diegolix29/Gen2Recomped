-- The height field: what makes a Gen 4 map three-dimensional to walk on.
--
-- A Gen 3 map is flat and its one elevation byte per tile is the whole story.
-- A Gen 4 map is a MESH, and the tile grid alone cannot say how high the ground
-- is at a point -- a bridge crosses over a path, a slope rises between two
-- tiles, a ledge has a top and a bottom at the same (x, z).  The BDHC block in
-- each land chunk is the cartridge's own answer: a set of sloped PLATES, and a
-- scanline index for finding the ones under a given point quickly.
--
-- LAYOUT, from BDHC_LoadHeader and BDHC_PrepareBuffers, which read the file
-- strictly in order:
--
--   "BDHC"                      4 bytes
--   u16 pointsCount, normalsCount, constantsCount,
--       platesCount, stripsCount, accessListCount
--   -- then the blocks, back to back, in exactly this order:
--   point    { fx32 x, z }                       8 bytes each
--   normal   { fx32 x, y, z }                   12 bytes each
--   constant   fx32                              4 bytes each
--   plate    { u16 firstPoint, secondPoint,
--              normalIndex, constantIndex }      8 bytes each
--   strip    { fx32 scanline, u16 count,
--              u16 startIndex }                  8 bytes each
--   accessList u16                               2 bytes each
--
-- THE IDENTITY TEST, because "BDHC" is four bytes and four bytes is a weak
-- promise: 16 + 8p + 12n + 4c + 8P + 8s + 2a must equal the block's declared
-- size EXACTLY.  A layout that is right for most files and wrong for some is
-- the failure mode this catches, and it catches it per chunk rather than on
-- average.
--
-- fx32 IS 1:19:12 FIXED POINT.  Divide by 4096 for world units.  Reading it as
-- an integer gives coordinates in the tens of thousands, which looks like a
-- different unit rather than like a bug, so the conversion is done here and
-- once.
--
-- A PLATE IS A BOUNDING BOX PLUS A PLANE.  Its two points are opposite corners
-- (in either order -- the engine sorts them), and its normal and constant give
-- the plane: y = -(normal.x * x + normal.z * z + constant) / normal.y.  A
-- point can be inside several plates, which is exactly the bridge case, and
-- choosing between them is the engine's job rather than the extractor's.

local Gen4Bdhc = {}

local floor = math.floor

Gen4Bdhc.MAGIC = "BDHC"
Gen4Bdhc.HEADER_BYTES = 16
Gen4Bdhc.FX32_ONE = 4096

-- A land chunk is 32x32 tiles and a flat one's single plate spans -256..256,
-- so a tile is 16 world units and the chunk is CENTRED on the origin.
-- Measured, not assumed: 49 of the 54 single-plate chunks cover all 1,024 of
-- their tiles under exactly this mapping.
Gen4Bdhc.TILE_UNITS = 16
Gen4Bdhc.CHUNK_UNITS = 512

Gen4Bdhc.SIZES = {
  point = 8, normal = 12, constant = 4, plate = 8, strip = 8, access = 2,
}

local function u16(s, at)
  local a, b = s:byte(at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end

-- Signed 32-bit, because a coordinate west or north of the origin is negative
-- and an unsigned read turns it into four billion.
local function s32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return nil end
  local value = a + b * 256 + c * 65536 + d * 16777216
  if value >= 2147483648 then value = value - 4294967296 end
  return value
end

local function fx(s, at)
  local raw = s32(s, at)
  if not raw then return nil end
  return raw / Gen4Bdhc.FX32_ONE
end

-- header(data) -> counts, expectedBytes
function Gen4Bdhc.header(data)
  if type(data) ~= "string" or #data < Gen4Bdhc.HEADER_BYTES then return nil, "too short" end
  if data:sub(1, 4) ~= Gen4Bdhc.MAGIC then return nil, "not a BDHC" end
  local counts = {
    points = u16(data, 4), normals = u16(data, 6), constants = u16(data, 8),
    plates = u16(data, 10), strips = u16(data, 12), access = u16(data, 14),
  }
  local S = Gen4Bdhc.SIZES
  local expected = Gen4Bdhc.HEADER_BYTES
    + counts.points * S.point + counts.normals * S.normal
    + counts.constants * S.constant + counts.plates * S.plate
    + counts.strips * S.strip + counts.access * S.access
  return counts, expected
end

-- parse(data) -> { counts, points, normals, constants, plates, strips, access }
-- Returns nil and a reason when the identity test fails, rather than a
-- half-read structure that looks usable.
function Gen4Bdhc.parse(data)
  local counts, expected = Gen4Bdhc.header(data)
  if not counts then return nil, expected end
  if expected ~= #data then
    return nil, ("BDHC declares %d bytes of blocks, block is %d"):format(expected, #data)
  end

  local at = Gen4Bdhc.HEADER_BYTES
  local points = {}
  for i = 1, counts.points do
    points[i] = { x = fx(data, at), z = fx(data, at + 4) }
    at = at + 8
  end
  local normals = {}
  for i = 1, counts.normals do
    normals[i] = { x = fx(data, at), y = fx(data, at + 4), z = fx(data, at + 8) }
    at = at + 12
  end
  local constants = {}
  for i = 1, counts.constants do
    constants[i] = fx(data, at)
    at = at + 4
  end
  local plates = {}
  for i = 1, counts.plates do
    plates[i] = {
      first = u16(data, at), second = u16(data, at + 2),
      normal = u16(data, at + 4), constant = u16(data, at + 6),
    }
    at = at + 8
  end
  local strips = {}
  for i = 1, counts.strips do
    strips[i] = {
      scanline = fx(data, at),
      count = u16(data, at + 4), start = u16(data, at + 6),
    }
    at = at + 8
  end
  local access = {}
  for i = 1, counts.access do
    access[i] = u16(data, at)
    at = at + 2
  end

  return {
    counts = counts, points = points, normals = normals,
    constants = constants, plates = plates, strips = strips, access = access,
  }
end

-- plateBox(bdhc, index) -> left, top, right, bottom in world units
function Gen4Bdhc.plateBox(bdhc, index)
  local plate = bdhc and bdhc.plates[index]
  if not plate then return nil end
  local a = bdhc.points[plate.first + 1]
  local b = bdhc.points[plate.second + 1]
  if not (a and b) then return nil end
  local left, right = a.x, b.x
  if left > right then left, right = right, left end
  local top, bottom = a.z, b.z
  if top > bottom then top, bottom = bottom, top end
  return left, top, right, bottom
end

-- heightOn(bdhc, index, x, z) -> the plane's y at (x, z), or nil when the
-- plate is vertical (normal.y == 0), which would be a divide by zero rather
-- than a height.
function Gen4Bdhc.heightOn(bdhc, index, x, z)
  local plate = bdhc and bdhc.plates[index]
  if not plate then return nil end
  local normal = bdhc.normals[plate.normal + 1]
  local constant = bdhc.constants[plate.constant + 1]
  if not (normal and constant) or normal.y == 0 then return nil end
  return -(normal.x * x + normal.z * z + constant) / normal.y
end

-- heightsAt(bdhc, x, z) -> every plate under this point, as
-- { index, height }, nearest-first is NOT imposed -- a bridge legitimately has
-- two and which one applies depends on where the walker already is.
function Gen4Bdhc.heightsAt(bdhc, x, z)
  if not bdhc then return {} end
  local out = {}
  for index = 1, #bdhc.plates do
    local left, top, right, bottom = Gen4Bdhc.plateBox(bdhc, index)
    if left and x >= left and x <= right and z >= top and z <= bottom then
      local y = Gen4Bdhc.heightOn(bdhc, index, x, z)
      if y then out[#out + 1] = { index = index, height = y } end
    end
  end
  return out
end

-- THE CARTRIDGE DOES NOT TEST EVERY PLATE, and the index it uses instead is
-- the part most worth reproducing, because it is the part a wrong read of the
-- strip or access-list blocks would silently corrupt.
--
-- BDHC_FindStripIndexByScanline binary-searches the strips by their `scanline`
-- (a z coordinate), and then only the plates named in that strip's slice of
-- the access list are tested.  `stripFor` is that search, transcribed
-- including its off-by-one shape: on the "go higher" branch it answers
-- mid + 1, which means the strip returned can be one past what a textbook
-- binary search would give.  Reproducing the SEARCH rather than the intent is
-- the point -- if the cartridge picks strip n, an extractor that picks n-1
-- disagrees with the game about where the ground is.
function Gen4Bdhc.stripFor(bdhc, z)
  local strips = bdhc and bdhc.strips
  local count = strips and #strips or 0
  if count == 0 then return nil end
  if count == 1 then return 1 end
  local low, high = 0, count - 1
  local mid = floor(high / 2)
  while true do
    if strips[mid + 1].scanline > z then
      if high - 1 > low then
        high = mid
        mid = floor((low + high) / 2)
      else
        return mid + 1
      end
    else
      if low + 1 < high then
        low = mid
        mid = floor((low + high) / 2)
      else
        return mid + 2
      end
    end
  end
end

-- heightsVia(bdhc, x, z) -> the same shape as heightsAt, but reached the way
-- the game reaches it.  Kept alongside the brute-force version specifically so
-- the two can be compared: they must agree on every point, and if they do not,
-- the strip or access-list read is wrong.
function Gen4Bdhc.heightsVia(bdhc, x, z)
  local strip = Gen4Bdhc.stripFor(bdhc, z)
  local row = strip and bdhc.strips[strip]
  if not row then return {} end
  local out = {}
  for i = 0, row.count - 1 do
    local index = bdhc.access[row.start + i + 1]
    if index then
      local left, top, right, bottom = Gen4Bdhc.plateBox(bdhc, index + 1)
      if left and x >= left and x <= right and z >= top and z <= bottom then
        local y = Gen4Bdhc.heightOn(bdhc, index + 1, x, z)
        if y then out[#out + 1] = { index = index + 1, height = y } end
      end
    end
  end
  return out
end

return Gen4Bdhc
