-- Voxel world mode: which tile ids wear which texture instead of their own art.
--
-- Read by lib/TileOverrides.lua and applied to the voxel atlas copy by
-- lib/TerrainAtlas.lua.  Gen 1-2 tilesets only.  Nothing here touches the 2D
-- view, collision or scripts -- an entry only changes how a tile LOOKS in
-- voxel mode.  There is no randomness in this file: a pick is a pick.
--
-- Tile ids are the hex numbers `idOverlay` prints on the world (0x01 = "01").
-- Keys under `tilesets` are tileset ids; the key "*" is the entry for EVERY
-- tileset that has none of its own, so the test below applies wherever you
-- are.  (The mod logs "TileOverrides: tileset <id> seen on map ..." once per
-- tileset if you want the exact spelling to give one its own entry.)
-- Pictures are shrunk to the atlas's 8x8 tile.

-- ===========================================================================
-- THE TEST LIST.  One flat colour per id, so you can tell at a glance which
-- id is which (the probe_*.png files are 16x16 solid colours).
--
--   ID   what it is (from your screenshot)   PNG                 you should see
--   --   ---------------------------------   ------------------  --------------
--   01   mountain body                       probe_red.png       red
--   11   mountain body                       probe_orange.png    orange
--   34   edge                                probe_green.png     green
--   37   edge                                probe_cyan.png      cyan
--   27   mountain ramp                       probe_magenta.png   magenta
--   5B   the purple floor                    probe_blue.png      blue
--   24   the blue block                      probe_white.png     white
--
-- Anything NOT in this list keeps showing its id number (idOverlay is on), so
-- the picture tells you everything: a coloured tile is an override that
-- worked, and a numbered tile is untouched.  If 01 still shows "01" the pick
-- did not apply -- see the log.
-- ===========================================================================
local TEST = {
  tiles = {
    [0x01] = "edges.png",
    [0x03] = "edges.png",
    [0x11] = "edges.png",
    [0x34] = "edges.png",
    [0x37] = "edges.png",
    [0x5B] = "flagstone.png",
    [0x34] = "edges.png",
    [0x35] = "edges.png",
    [0x36] = "edges.png",
    [0x13] = "edges.png",
    [0x02] = "edges.png",
    [0x1E] = "edges.png",
    [0x2C] = "grass.png",

    [0x39] = "road.png",
    [0x50] = "highgrass.png",
    [0x30] = "highgrass.png",
    [0x00] = "highgrass.png",
    [0x20] = "highgrass.png",
  },
}

return {
  enabled = true,

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

  tilesets = {
    ["*"] = TEST,
  },
}
