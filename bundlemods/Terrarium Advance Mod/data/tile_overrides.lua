-- Voxel world mode: which tile ids wear which texture instead of their own art.
--
-- Read by lib/TileOverrides.lua and applied to the voxel atlas copy by
-- lib/TerrainAtlas.lua.  Gen 1-2 tilesets only.  Nothing here touches the 2D
-- view, collision or scripts -- an entry only changes how a tile LOOKS in
-- voxel mode.  There is no randomness in this file: a pick is a pick.
--
-- Tile ids are the hex numbers `idOverlay` prints on the world (0x01 = "01").
-- Keys under `tilesets` are tileset ids.  Ids are PER TILESET (0x01 in a
-- house tileset is not 0x01 outdoors), so give each tileset its own entry
-- rather than "*" (every tileset), which re-textured walls and trees in
-- towns, caves and interiors.  (The mod logs "TileOverrides: tileset <id>
-- seen on map ..." once per tileset for the exact spelling of a new one.)
--
-- Only faces of the shape classes in `classes` change (default: ground,
-- grass, terrace, ledge, cliff, slope).  Buildings, roofs, trees and props
-- keep their art even where they share an 8x8 tile with the ground.
--
-- mode = "mesh" (default): those tiles' faces are taken out of the terrain and
--   rebuilt as their own meshes wearing the PNG at FULL RESOLUTION, tiled in
--   world space -- tops, cliff faces and ramps alike.  Textures are capped to
--   `maxTexture` px (power of two) and tile once per `repeatTiles` tiles.
-- mode = "atlas": the PNG is shrunk into the tile's 8x8 atlas slot.  Pixelated
--   by construction; kept as the cheap fallback.

-- ===========================================================================
-- THE TEST LIST.  One real texture per id, each different, so you can tell
-- at a glance which id is which.
--
--   ID   what it is (from your screenshot)   PNG              you should see
--   --   ---------------------------------   ---------------  ---------------
--   01   mountain body                       flagstone.png    grey flagstones
--   11   mountain body                       pavers.png       grey paving
--   34   edge                                mulch.png        wood chips
--   37   edge                                sand.png         cream sand
--   27   mountain ramp                       ground.png       brown earth
--   5B   the purple floor                    road.png         asphalt
--   24   the blue block                      waterp.png       cyan
--
-- Anything NOT in this list keeps showing its id number (idOverlay is on), so
-- the picture tells you everything: a textured tile is an override that
-- worked, and a numbered tile is untouched.
-- ===========================================================================
local TEST = {
  tiles = {
    [0x01] = "edges.png",
    [0x03] = "edges.png",
    [0x11] = "edges.png",
    [0x34] = "edges.png",
    [0x37] = "edges.png",
    [0x5B] = "flagstone.png",
    [0x35] = "edges.png",
    [0x36] = "edges.png",
    [0x13] = "edges.png",
    [0x02] = "edges.png",
    [0x1E] = "edges.png",
    [0x2C] = "edges.png",
    [0x23] = "road.png",
    [0x62] = "edges.png",

    [0x39] = "road.png",
    [0x50] = "highgrass.png",
    [0x30] = "highgrass.png",
    [0x00] = "highgrass.png",
    [0x20] = "highgrass.png",
  },
}

-- ===========================================================================
-- CAVES AND FORESTS.  Each has its own tileset, so its own ids.  Ids come
-- from the pins in data/voxel_heights.lua.  Swap the PNG names freely.
-- ===========================================================================
local CAVE_FLOOR = "edges.png"
local CAVE_WALL  = "edges.png"
local FOREST_FLOOR = "grass.png"

-- Gen 1 caves (Mt Moon, Rock Tunnel, Seafoam, Victory Road, Cerulean Cave)
local CAVERN = {
  tiles = {
    -- ground: the dark lower floor
    [0x20] = CAVE_FLOOR, [0x21] = CAVE_FLOOR, [0x2A] = CAVE_FLOOR,
    -- ground: the lit raised shelf and its shadow row
    [0x05] = "sand.png", [0x29] = "sand.png",
    -- walls: speckled mass, boulder mass, cobbles, faces, caps, corners,
    -- barred shelf, ceiling mass
    [0x02] = CAVE_WALL, [0x03] = CAVE_WALL, [0x12] = CAVE_WALL, [0x13] = CAVE_WALL,
    [0x0C] = CAVE_WALL, [0x0D] = CAVE_WALL, [0x1C] = CAVE_WALL, [0x1D] = CAVE_WALL,
    [0x10] = CAVE_WALL, [0x11] = CAVE_WALL,
    [0x31] = CAVE_WALL, [0x17] = CAVE_WALL,
    [0x04] = CAVE_WALL, [0x07] = CAVE_WALL, [0x28] = CAVE_WALL,
    [0x25] = CAVE_WALL, [0x26] = CAVE_WALL,
    [0x0E] = CAVE_WALL, [0x0F] = CAVE_WALL, [0x1E] = CAVE_WALL, [0x1F] = CAVE_WALL,
    [0x06] = CAVE_WALL, [0x27] = CAVE_WALL, [0x24] = CAVE_WALL, [0x01] = CAVE_WALL,
  },
}

-- Gen 2 caves (Union Cave, Mt Mortar, Dark Cave, Slowpoke Well, ...)
local CAVE2 = {
  tiles = {
    -- ground: low floor, and the raised floor + its edge band
    [0x01] = CAVE_FLOOR,
    [0x16] = "edges.png", [0x24] = "edges.png",
    -- walls: the one rock family every cave wall is drawn from
    [0x05] = CAVE_WALL, [0x07] = CAVE_WALL, [0x0A] = CAVE_WALL, [0x0B] = CAVE_WALL,
    [0x10] = CAVE_WALL, [0x15] = CAVE_WALL, [0x17] = CAVE_WALL,
    [0x25] = CAVE_WALL, [0x26] = "flagstone.png", [0x27] = CAVE_WALL,
  },
}

-- Gen 2 Ilex Forest
local FOREST2 = {
  tiles = {
    [0x05] = FOREST_FLOOR,   -- the forest floor
  },
}

-- Gen 1 Viridian Forest (+ Safari Zone).  Its floor id isn't known yet:
-- the id overlay is on for this tileset (`overlay = true`), so walk in,
-- read the number on the floor, add it below, then set overlay to false.
local FOREST1 = {
  overlay = true,
  tiles = {
    -- [0x??] = FOREST_FLOOR,
  },
}

return {
  enabled = true,

  -- "mesh" = full-resolution PNGs on their own meshes (default);
  -- "atlas" = shrunk into the 8x8 atlas slot.  Can also be set per tileset.
  mode = "mesh",

  -- mesh mode: tiles per repeat of the texture (1 = the whole PNG on each
  -- 8x8 tile; 2 = one PNG across two tiles; 0.5 = twice per tile), and the
  -- biggest texture kept, in pixels (it is made a power of two)
  repeatTiles = 1,
  maxTexture = 512,
  filter = "linear",    -- or "nearest" for a crisp, blocky look

  -- stamp every OTHER tile slot with its own id (two hex digits on a coloured
  -- square).  true = every Gen 1-2 tileset, or a list: { "TilesetKanto" }.
  -- Picks under `tilesets` still win.  false = off.
  idOverlay = false,

  -- where the PNGs live, relative to the mod root
  dir = "assets/ground/grass/",

  -- only used by `random = {...}` entries, none of which are in use
  pool = {
    "dark sand.png", "edges.png", "flagstone.png", "floor.png",
    "flowers.png", "grass.png", "ground.png", "highgrass.png",
    "lamp.png", "mulch.png", "object.png", "pavers.png",
    "road.png", "rock.png", "sand.png", "snow.png",
    "trees.png", "waterp.png", "wild.png",
  },

  -- shape classes mesh mode may re-texture (see the note at the top)
  classes = { "ground", "grass", "terrace", "ledge", "cliff", "slope", "wall", "cave" },

  tilesets = {
    -- the outdoor sets: Gen 2 Johto and the Gen 1 overworld
    TilesetJohto = TEST,
    OVERWORLD = TEST,

    -- caves
    CAVERN = CAVERN,
    TilesetCave = CAVE2,
    TilesetDarkCave = CAVE2,

    -- forests
    TilesetForest = FOREST2,
    FOREST = FOREST1,
  },
}
