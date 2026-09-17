-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHICH SPRITES THE MAP'S TOP LAYER COVERS.
--
-- Reported from play: "when walking on bridges it makes my character go under
-- them rather than walking on top of them".  It did, because the port drew
-- every metatile's top layer over every sprite: a bridge deck's rail covers
-- whoever is under the bridge, and it was covering whoever was ON it too.
--
-- The cartridge settles this per sprite, every frame, and it takes three
-- pieces to do it:
--
--   * the field draws its map on three backgrounds, and only ONE of them
--     covers sprites -- the one at priority 1 (sOverworldBgTemplates);
--   * an object's OAM priority is a table lookup on its elevation
--     (UpdateObjectEventZCoordAndPriority, 08096D14): elevation 3, ordinary
--     ground, gives priority 2, and elevation 4, a bridge deck, gives 1;
--   * and the hardware draws a sprite in FRONT of a background when the
--     sprite's priority is less than or equal to the background's.
--
-- So the deck's walkers tie with the covering layer and are drawn on top of
-- it, and everyone else loses to it.  The import reads the first two off the
-- cartridge (extractSpritePriority); the third is the GBA's rule and is
-- written down here rather than derived, because there is nothing in the ROM
-- to derive it from.
--
-- THE ELEVATION IS STICKY, and that is the cartridge's own rule too
-- (ObjectEventUpdateElevation, 08096DB8): the value the priority is looked up
-- with only changes when the cell stepped on names a real level.  0 means
-- "any level" and 15 means "under a bridge", and neither replaces what the
-- object was standing at -- which is exactly what keeps a player who has
-- walked UNDER a bridge (over its 15-marked cells) drawn beneath it.

local Gen3Elevation = {}

-- The cartridge's own table, repeated so a dataset extracted before this rip
-- still draws bridges right.  The record wins wherever it exists.
local FALLBACK = {
  -- elevation 0..15, indexed +1
  priority = { 2, 2, 2, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 0, 0, 2 },
  aboveWhen = 1,
}

local ELEVATION_ANY, ELEVATION_UNDER_BRIDGE = 0, 15

function Gen3Elevation.record(data)
  return (data and data.constants or {}).gen3SpritePriority
end

-- What an object's looked-up elevation becomes after standing on a cell whose
-- elevation is `at`.  Neither wildcard replaces what is held.
function Gen3Elevation.sticky(held, at)
  at = tonumber(at)
  if at == nil or at == ELEVATION_ANY or at == ELEVATION_UNDER_BRIDGE then
    return held
  end
  return math.floor(at)
end

function Gen3Elevation.priorityOf(data, elevation)
  elevation = tonumber(elevation)
  if elevation == nil then return nil end
  local record = Gen3Elevation.record(data)
  local list = (record and record.priority) or FALLBACK.priority
  return list[math.floor(elevation) + 1]
end

-- HOW HIGH A LEVEL IS, and why the priority table is allowed to answer that.
--
-- Asked for directly, of a mod that draws the field in 3D: "it doesnt
-- recognize height of the terrain or character, which places me underground
-- in some areas where the ground is raised".  The elevation nibble alone
-- cannot be used as a height -- it is a level ID, not a measurement.  Reading
-- it as one puts every cell of ordinary ground (elevation 3) three units up
-- and every wildcard cell (elevation 0) on the floor, which is the reported
-- symptom exactly: the raised parts of the map rise and the character does
-- not come with them.
--
-- The cartridge never draws a height, but it does RANK the levels, and that
-- ranking is in the table above rather than invented here.  An object's OAM
-- priority is looked up by elevation, and a smaller priority draws in front:
-- ordinary ground and water are 2, a bridge deck is 1, and 13 and 14 -- the
-- levels that pass over a deck -- are 0.  Flipping the table around its own
-- largest value therefore turns "drawn in front of" into "stands above", with
-- no number in it that the ROM did not supply.
--
-- Both wildcards land on the bottom layer, which is right for each: 0 is the
-- ordinary ground most of Hoenn is made of, and 15 marks the cells that run
-- UNDER a bridge.  A caller meshing terrain has to treat 15 as the level the
-- BRIDGE's neighbours are at rather than as a hole; Map:isUnderBridgeCell is
-- there to tell it apart from ordinary ground.
local layerCache = setmetatable({}, { __mode = "k" })

-- the whole 0..15 mapping in one table, indexed +1, built once per dataset --
-- a mesh builder asks this for every cell of an 80x80 route
function Gen3Elevation.layerTable(data)
  local record = Gen3Elevation.record(data)
  local list = (record and record.priority) or FALLBACK.priority
  local hit = layerCache[list]
  if hit then return hit end
  local top = 0
  for i = 1, #list do
    local v = tonumber(list[i])
    if v and v > top then top = v end
  end
  local out = {}
  for i = 1, 16 do
    local v = tonumber(list[i])
    local layer = v and (top - v) or 0
    out[i] = layer >= 0 and layer or 0
  end
  out.count = top + 1
  return out
end

-- how many distinct levels the ranking has: layerOf returns 0..count-1
function Gen3Elevation.layerCount(data)
  return Gen3Elevation.layerTable(data).count
end

function Gen3Elevation.layerOf(data, elevation)
  elevation = tonumber(elevation)
  if elevation == nil then return nil end
  return Gen3Elevation.layerTable(data)[math.floor(elevation) + 1]
end

-- HOW HIGH, IN WORLD PIXELS, AND WHY THIS IS A SEPARATE QUESTION FROM layerOf.
--
-- layerOf ranks a level against the cartridge's own draw order, which has
-- three rungs and is the same on every map.  A renderer building terrain needs
-- something else: a HEIGHT, on THIS map, for the levels this map actually
-- uses.  Route 119 uses three of them and Victory Road uses six, and a fixed
-- three-rung table cannot separate the six.
--
-- The derivation is the map's own data and nothing else.  Collect the real
-- levels present -- which is every value except the three that are not levels:
-- 0 (any), 15 (under a bridge / a deck) and 1 (surf, which is the water
-- surface rather than a floor) -- sort them, and space them one metatile
-- apart.  Ordinary ground is elevation 3 on this cartridge, so that is the
-- datum and comes out at 0; everything above it is positive and anything
-- below is negative.  A map with no cell at 3 at all (an all-terrace interior,
-- Pacifidlog's rafts) pins the datum to its lowest level instead, so the map
-- still lands on the floor rather than floating.
--
-- Returns heights (a lookup from elevation to world pixels), the number of
-- levels, and the course height.  nil when the map carries no elevation.
--
-- WHAT THIS DOES NOT ANSWER, deliberately.  0 and 15 get no height, because
-- neither is a level: a 0 cell is a transition and takes the height of what it
-- joins (a ramp between two levels, or the lowest level touching it), and a 15
-- cell is a deck whose height depends on WHO IS ASKING -- the walker on it and
-- the walker under it are at different heights on the same cell, which is the
-- whole mechanism of Fortree's span and Route 110's cycling road.  A caller
-- that guesses at those two puts somebody underground; the answer is nil so
-- that the guess has to be made on purpose.
local COURSE = 16       -- one elevation step, in world pixels: a metatile
local ELEV_ANY, ELEV_SURF, ELEV_GROUND, ELEV_MULTI = 0, 1, 3, 15

function Gen3Elevation.ranks(elevationCells)
  if type(elevationCells) ~= "table" then return nil end
  local seen, list = {}, {}
  for i = 1, #elevationCells do
    local e = tonumber(elevationCells[i])
    if e and e ~= ELEV_ANY and e ~= ELEV_MULTI and e ~= ELEV_SURF
       and not seen[e] then
      seen[e] = true
      list[#list + 1] = e
    end
  end
  if not list[1] then return nil end
  table.sort(list)
  local datum
  for i, e in ipairs(list) do
    if e == ELEV_GROUND then datum = i break end
  end
  datum = datum or 1
  local heights = {}
  for i, e in ipairs(list) do heights[e] = (i - datum) * COURSE end
  return heights, #list, COURSE
end

Gen3Elevation.COURSE = COURSE
Gen3Elevation.ANY = ELEV_ANY
Gen3Elevation.SURF = ELEV_SURF
Gen3Elevation.GROUND = ELEV_GROUND
Gen3Elevation.MULTI = ELEV_MULTI

-- Is a sprite at this elevation drawn ON TOP of the covering layer?
function Gen3Elevation.aboveTop(data, elevation)
  local priority = Gen3Elevation.priorityOf(data, elevation)
  if priority == nil then return false end
  local record = Gen3Elevation.record(data)
  local when = tonumber(record and record.aboveWhen) or FALLBACK.aboveWhen
  return priority <= when
end

return Gen3Elevation
