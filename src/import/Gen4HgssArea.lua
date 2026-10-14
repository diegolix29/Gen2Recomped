-- HEARTGOLD AND SOULSILVER'S AREA RECORD (/a/0/4/2, 106 x 8 bytes).
--
-- The same eight bytes as Platinum's AreaDataFile with the last two meaning
-- something else. Read from pokeheartgold's overlay 1, which loads the record
-- into AreaDataManager+0x8B0 and then reads it field by field
-- (asm/overlay_01_021FB878.s):
--
--   +0 u16 buildings   the area_build list, NARC 0x2B (/a/0/4/3), and the
--                      building texture set, NARC 0x46 (/a/0/7/0)
--   +2 u16 mapTexture  the map texture set, NARC 0x2C (/a/0/4/4)
--   +4 u16             (0, 1 or 0xFFFF; not read by the loader)
--   +6 u8  outdoors    AreaDataManager_Alloc: nonzero opens the OUTDOOR
--                      building models NARC 0x28 (/a/0/4/0), zero the indoor
--                      ones NARC 0x94 (/a/1/4/8)
--   +7 u8  light       AreaDataManager_GetAreaLightArchiveID: 0 -> 1,
--                      1 -> 0, 2 -> 3, anything else -> 0
--
-- MEASURED against the map headers that use each record: every record whose
-- maps are towns, routes or caves has +6 = 1, every one whose maps are rooms
-- has 0 (New Bark's houses, the gyms, the Pokemon Centers).

local A = {}

A.RECORD_BYTES = 8
A.LIGHT_ARCHIVE = { [0] = 1, [1] = 0, [2] = 3 }
A.OUTDOOR_MODELS = "/a/0/4/0"
A.INDOOR_MODELS = "/a/1/4/8"

-- parse(record) -> Platinum's field names (Gen4Maps.areaData), so the terrain
-- stage reads one shape for both games
function A.parse(record)
  if type(record) ~= "string" or #record < A.RECORD_BYTES then return nil end
  local b = { record:byte(1, A.RECORD_BYTES) }
  local function u16(o) return b[o + 1] + b[o + 2] * 256 end
  local outdoors = b[7] ~= 0
  return {
    buildings = u16(0),
    mapTexture = u16(2),
    unused04 = u16(4),
    outdoors = outdoors,
    lightType = b[8],
    areaLight = A.LIGHT_ARCHIVE[b[8]] or 0,
    buildingModels = outdoors and A.OUTDOOR_MODELS or A.INDOOR_MODELS,
  }
end

return A
