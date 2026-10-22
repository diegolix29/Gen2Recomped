-- Voxel world mode: which tile ids wear which texture instead of their own art.
--
-- Read by lib/TileOverrides.lua and applied to the voxel atlas copy by
-- lib/TerrainAtlas.lua.  Gen 1-2 tilesets only.  Nothing here touches the 2D
-- view, collision or scripts -- an entry only changes how a tile LOOKS in
-- voxel mode.
--
-- Keys under `tilesets` are tileset ids, the same ones data/voxel_heights.lua
-- uses.  Tile ids are indices into that tileset's own 8x8 atlas (16 to a row).
--
--   tiles  = { [0x05] = "sand.png" }     a fixed pick
--   random = { seed = 1, ids = {...},    these ids each get a seeded-random
--              pool = {...} }            texture (own pool optional)
--
-- `tiles` wins over `random` for the same id.  Change a seed to re-roll.  The
-- mod logs the resolved assignment once per tileset ("TileOverrides: ...") so
-- you can see exactly which id got which file.
--
-- Pictures are shrunk to the atlas's 8x8 tile -- good for telling ids apart,
-- not for fine detail.  Set `enabled = false` to switch it all off.

return {
  enabled = true,

  -- where the PNGs live, relative to the mod root
  dir = "assets/ground/grass/",

  -- the default pool for `random`: the ground textures that read clearly at
  -- 8x8.  (Left out on purpose: light.png, a glow; metal aged.png, near
  -- black; shadow.png; the probe_*.png squares; transparent.png; the grass
  -- mesh files.  Add them to a pool to use them.)
  pool = {
    "dark sand.png", "edges.png", "flagstone.png", "floor.png",
    "flowers.png", "grass.png", "ground.png", "highgrass.png",
    "lamp.png", "mulch.png", "object.png", "pavers.png",
    "road.png", "rock.png", "sand.png", "snow.png",
    "trees.png", "waterp.png", "wild.png",
  },

  tilesets = {
    -- Gen 2 Johto.  $05/$06 are the plain grass every outdoor map is made of
    -- (voxel_heights pins them as `ground`), $3C the dirt on top of a cliff
    -- and $2C its lip.
    TilesetJohto = {
      random = { seed = 12, ids = { 0x05, 0x06, 0x3C, 0x2C } },
    },

    -- Gen 1 overworld.  44 ($2C) is plain grass (voxel_heights: "the very
    -- tile Cut leaves behind"); 82 ($52) is, from memory of the Red/Blue
    -- tileset and not checked against this build's atlas, the tall grass.
    OVERWORLD = {
      random = { seed = 12, ids = { 44, 82 } },
    },
  },
}
