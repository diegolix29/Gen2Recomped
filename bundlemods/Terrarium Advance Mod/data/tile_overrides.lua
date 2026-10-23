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
    [0x01] = "edges.png",

    [0x39] = "road.png",
    [0x50] = "highgrass.png",
    [0x30] = "highgrass.png",
    [0x00] = "highgrass.png",
    [0x20] = "highgrass.png",
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
  idOverlay = true,

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
  classes = { "ground", "grass", "terrace", "ledge", "cliff", "slope", "wall", "cave", "tree" },

  tilesets = {
    -- the outdoor sets: Gen 2 Johto and the Gen 1 overworld
    TilesetJohto = TEST,
    OVERWORLD = TEST,
  },
}
