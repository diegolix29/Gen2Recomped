-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A STAND-IN TILESET for Gen 4, so a Platinum map can be loaded and walked
-- before anything can draw its actual scenery.
--
-- Gen 4's world is 3D: every chunk carries an NSBMD mesh and a texture set,
-- and there is no tileset in the Gen 1-3 sense anywhere in the cartridge.
-- MapLoader, though, pairs every map def with an entry in `data.tilesets`, so
-- a Gen 4 map cannot be built at all until something answers that question.
--
-- WHAT THIS IS NOT.  It is not an attempt at Platinum's art, and nothing here
-- should be mistaken for it later: it draws one flat colour per TERRAIN CLASS,
-- so a map reads as a legible plan -- grass green, water blue, ledges yellow,
-- doors orange -- rather than as Sinnoh.  The value is that the map, its
-- collision, its warps and its NPCs can all be exercised while the mesh
-- pipeline is still missing.
--
-- WHY IT IS SHAPED LIKE A GEN 3 TILESET.  Because then it needs no renderer
-- changes at all.  TileRenderer.gen3SheetsFor takes any tileset whose
-- `blockTiles` is 2, looks up its `primaryKey` in the dataset and hands the
-- record to Gen3Tiles, which reads four plain binaries: 4bpp `tiles`, 16-byte
-- `metatiles`, 2-byte `attributes` and a `palettes` array.  Producing those
-- four is cheaper than teaching the renderer a fifth kind of map, and it means
-- a Gen 4 map takes the same code path Hoenn already does.
--
-- THE COLOURS ARE NOT ARBITRARY.  A cell's behaviour byte is named by
-- pokeplatinum -- TALL_GRASS, WATER_SEA, DOOR, JUMP_EAST -- and all 75
-- behaviours that occur in this cartridge have a real name, so the class a
-- colour stands for is read rather than invented.  Anything that fails to
-- classify draws MAGENTA on purpose: an unclassified behaviour should be
-- obvious on screen, not quietly green.

local Gen4Behaviors = require("src.import.Gen4Behaviors")

local Gen4Tileset = {}

Gen4Tileset.ID = "TILESET_GEN4_STANDIN"
Gen4Tileset.PRIMARY_ID = "GEN4_STANDIN"
Gen4Tileset.IMAGE = "assets/generated/gen4/tileset/standin.png"

-- One colour index per terrain class.  Index 0 is transparent on the hardware
-- and stays the backdrop, so the classes start at 1 and there are fifteen of
-- them -- which is exactly the room a 4bpp palette leaves.
Gen4Tileset.CLASSES = {
  { index = 1,  name = "ground",  color = { 126, 172, 104 } },
  { index = 2,  name = "grass",   color = { 74, 134, 72 } },
  { index = 3,  name = "water",   color = { 64, 116, 196 } },
  { index = 4,  name = "shallow", color = { 116, 172, 220 } },
  { index = 5,  name = "sand",    color = { 216, 196, 140 } },
  { index = 6,  name = "snow",    color = { 234, 238, 244 } },
  { index = 7,  name = "mud",     color = { 140, 108, 74 } },
  { index = 8,  name = "ice",     color = { 176, 220, 232 } },
  { index = 9,  name = "cave",    color = { 128, 116, 104 } },
  { index = 10, name = "door",    color = { 224, 148, 62 } },
  { index = 11, name = "ledge",   color = { 226, 202, 78 } },
  { index = 12, name = "bridge",  color = { 176, 140, 96 } },
  { index = 13, name = "stairs",  color = { 158, 122, 196 } },
  { index = 14, name = "blocked", color = { 62, 62, 76 } },
  { index = 15, name = "unknown", color = { 226, 64, 200 } },
}

-- Name patterns to class, tried IN ORDER -- the first match wins, so the
-- specific patterns come before the general ones.  MUD_WITH_GRASS is mud that
-- starts wild battles, not grass, and it has to be decided before "GRASS"
-- catches it.
Gen4Tileset.RULES = {
  { "^MUD", "mud" },
  { "GRASS", "grass" },
  { "^WATER", "water" },
  { "WATERFALL", "water" },
  { "SHALLOW_WATER", "shallow" },
  { "^PUDDLE", "shallow" },
  { "^SAND", "sand" },
  { "^SNOW", "snow" },
  { "^ICE", "ice" },
  -- A SLIDE tile takes the player's next step away from them, which is what
  -- ice does; it is grouped with ice because that is what it BEHAVES like,
  -- not because the cartridge calls it ice.
  { "^SLIDE_", "ice" },
  { "CAVE", "cave" },
  { "^DOOR", "door" },
  { "^WARP", "door" },
  { "^JUMP_", "ledge" },
  { "BRIDGE", "bridge" },
  { "STAIRS", "stairs" },
  { "ESCALATOR", "stairs" },
  { "^BIKE_SLOPE", "stairs" },
  { "^BLOCK_", "blocked" },
  { "^WALL", "blocked" },
  { "SHELF", "blocked" },
  { "BOOKSHELF", "blocked" },
  { "^TRASH", "blocked" },
  { "^TABLE", "blocked" },
  { "FLOOR", "ground" },
  { "^NONE$", "ground" },
  -- Named ground that carries a rule rather than a look: a floor that
  -- reflects, one whose height is resolved at run time, the three tiers of
  -- Pastoria's gym, the soil a berry grows in.  All of them are walked on, so
  -- they are ground; the rule they carry is not this module's business.
  { "^REFLECTIVE$", "ground" },
  { "^DYNAMIC_HEIGHT", "ground" },
  { "^PASTORIA_GYM", "ground" },
  { "^BERRY_PATCH$", "ground" },
  { "^FORBIDS_", "ground" },
}

-- classOf(behaviour) -> the class entry, never nil.
function Gen4Tileset.classOf(behaviour)
  local name = Gen4Behaviors.name(behaviour) or ""
  local byName = {}
  for _, class in ipairs(Gen4Tileset.CLASSES) do byName[class.name] = class end

  for _, rule in ipairs(Gen4Tileset.RULES) do
    if name:match(rule[1]) then return byName[rule[2]] end
  end

  -- Nothing matched by name.  The flags still say something useful, and they
  -- are the cartridge's own answer rather than a reading of the name.
  if Gen4Behaviors.isSurfable(behaviour) then return byName.water end
  if Gen4Behaviors.isEncounter(behaviour) then return byName.grass end
  -- An UNUSED behaviour that occurs anyway is ordinary ground far more often
  -- than it is anything else, but saying so would hide it.  Magenta.
  return byName.unknown
end

-- ---------------------------------------------------------------------------
-- The four binaries
-- ---------------------------------------------------------------------------

-- Sixteen 8x8 tiles, 4bpp, 32 bytes each.  Tile 0 is transparent; tile c is
-- solid colour index c.  4bpp packs TWO pixels per byte with the LOW nibble
-- first, and both nibbles hold the same index here, so the packing order
-- cannot be got wrong in a way that shows.
function Gen4Tileset.tiles()
  local out = {}
  for index = 0, 15 do
    local byteValue = index + index * 16
    out[#out + 1] = string.rep(string.char(byteValue), 32)
  end
  return table.concat(out)
end

-- Two palettes of sixteen colours: the class colours, and the same colours
-- darkened.  The second is what makes the 16-pixel grid visible -- a map drawn
-- in one flat colour per class reads as a silhouette with no sense of scale.
function Gen4Tileset.palettes()
  local base, shade = {}, {}
  base[1] = { 24, 26, 34 }            -- colour 0: the backdrop
  shade[1] = { 24, 26, 34 }
  for _, class in ipairs(Gen4Tileset.CLASSES) do
    local c = class.color
    base[class.index + 1] = { c[1], c[2], c[3] }
    shade[class.index + 1] = {
      math.floor(c[1] * 0.86), math.floor(c[2] * 0.86), math.floor(c[3] * 0.86),
    }
  end
  return { base, shade }
end

-- 256 metatiles of 16 bytes: eight u16 entries, four bottom then four top.
-- Each entry is { tile:10, flipX, flipY, palette:4 }.
--
-- The top layer is left transparent.  It is what the player walks BEHIND, and
-- a stand-in that put anything there would hide the player behind a flat
-- colour for no reason.
function Gen4Tileset.metatiles()
  local out = {}
  for behaviour = 0, 255 do
    local class = Gen4Tileset.classOf(behaviour)
    local tile = class.index
    local words = {}
    -- Bottom layer, as a two-by-two checker of the base and shaded palettes,
    -- so every 16-pixel cell has a visible edge against its neighbour.
    for k = 0, 3 do
      local palette = ((k == 1) or (k == 2)) and 1 or 0
      words[#words + 1] = tile + palette * 4096
    end
    for _ = 0, 3 do words[#words + 1] = 0 end
    for _, word in ipairs(words) do
      out[#out + 1] = string.char(word % 256, math.floor(word / 256) % 256)
    end
  end
  return table.concat(out)
end

-- 256 attribute words: the behaviour byte in the low byte, layer type zero.
--
-- The behaviour a metatile reports is ITS OWN INDEX, because there is exactly
-- one metatile per behaviour.  That is what makes `behaviourBytes` true for
-- this tileset and lets everything that asks a cell what kind of ground it is
-- keep working unchanged.
function Gen4Tileset.attributes()
  local out = {}
  for behaviour = 0, 255 do
    out[#out + 1] = string.char(behaviour, 0)
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- The two records
-- ---------------------------------------------------------------------------

-- The raw tileset the renderer composites from.
function Gen4Tileset.primary()
  return {
    id = Gen4Tileset.PRIMARY_ID,
    tiles = Gen4Tileset.tiles(),
    tileCount = 16,
    metatiles = Gen4Tileset.metatiles(),
    metatileCount = 256,
    attributes = Gen4Tileset.attributes(),
    palettes = Gen4Tileset.palettes(),
    image = Gen4Tileset.IMAGE,
    secondary = false,
    source = "synthesised: one metatile per Gen 4 tile behaviour",
  }
end

-- The pair record a map def names.  Gen 4 has no primary/secondary split, so
-- there is no secondary key -- Gen3Tiles handles that case already, because a
-- Gen 3 map with no secondary tileset is ordinary.
function Gen4Tileset.pair()
  local encounter = Gen4Behaviors.group("encounter")
  local walkable = {}
  for b = 0, 254 do walkable[b + 1] = b end

  return {
    id = Gen4Tileset.ID,
    primaryKey = Gen4Tileset.PRIMARY_ID,
    secondaryKey = nil,
    image = Gen4Tileset.IMAGE,
    -- 2x2 tiles per metatile, and the metatile IS the collision cell, exactly
    -- as in Gen 3.  A Gen 4 permission cell is 16 pixels and carries one
    -- behaviour, so the two line up without adjustment.
    blockTiles = 2,
    blockCells = 1,
    metatileCount = 256,
    -- `collision` here is a BEHAVIOUR byte per metatile, not a Gen 2
    -- passability class -- the same thing a Gen 3 pair carries, and the flag
    -- below is what tells the two number spaces apart.
    collision = (function()
      local out = {}
      for b = 0, 255 do out[b + 1] = b end
      return out
    end)(),
    behaviourBytes = true,
    -- EVERY behaviour is walkable here, and that is not a shortcut: in Gen 4,
    -- as in Gen 3, passability is the CELL's business.  The map grid's
    -- collision bit is set from the cartridge's void flag, and Map:cellTile
    -- already blocks on it; listing behaviours here would block terrain a
    -- second time and for the wrong reason.
    walkable = walkable,
    grassTiles = Gen4Behaviors.group("grass"),
    encounterTiles = encounter,
    waterTiles = Gen4Behaviors.group("surfable"),
    doorTiles = Gen4Behaviors.group("door"),
    warpTiles = Gen4Behaviors.group("warp"),
    -- A Gen 4 warp fires from its EVENT, not from the tile under it -- the
    -- behaviour only says what kind of opening it is.  Same rule as Gen 3.
    warpsAreEvents = true,
    ledgeBehaviours = (function()
      local out = {}
      for _, b in ipairs(Gen4Behaviors.group("jump")) do
        out[b] = Gen4Behaviors.jumpDirection(b)
      end
      return out
    end)(),
    source = "synthesised stand-in; Gen 4 has no 2D tileset in the cartridge",
    standIn = true,
  }
end

-- The atlas the renderer loads: sixteen 8x8 tiles in a row, in the palette's
-- base colours.  Returned as { width, height, rgba } for ImageWriter.
--
-- Gen3Tiles composites from `tiles` and `palettes` rather than from this
-- image, so it exists for the paths that want a picture and as something to
-- look at when the colours need checking.
function Gen4Tileset.atlas()
  local palettes = Gen4Tileset.palettes()
  local base = palettes[1]
  local width, height = 16 * 8, 8
  local out = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = math.floor(x / 8)
      local colour = base[index + 1] or { 0, 0, 0 }
      local alpha = (index == 0) and 0 or 255
      out[y * width + x + 1] =
        string.char(colour[1], colour[2], colour[3], alpha)
    end
  end
  return { width = width, height = height, rgba = table.concat(out) }
end

return Gen4Tileset
