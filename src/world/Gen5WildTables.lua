-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK AND WHITE'S WILD TABLES, AS THE FIELD READS THEM.
--
-- /a/1/2/6 (src/import/Gen5Encounters.lua) gives each zone seven lists --
-- grass, dark grass, the phenomenon list (shaking grass, dust clouds and
-- flying shadows all draw from it), surf, rippling surf, the Super Rod and
-- the rippling Super Rod -- and the 18 zones whose wild Pokemon change with
-- the season carry four copies, spring to winter. Encounter.forMap used to
-- hand back spring's grass, surf and rod and nothing else, all year.
--
-- Checked against PKHeX's encounter_b / encounter_w (built from the
-- cartridges): every Black table matches (261 of 261, all seasons and all
-- seven kinds); White matches except White Forest (location 51), whose
-- Pokemon are not in any zone's table (scratch bwfield/tools/cmpenc.py).

local Rules = require("src.world.Gen5FieldRules")

local W = {}

local cache = setmetatable({}, { __mode = "k" })

-- view(def, save) -> the Gen 4-shaped view Encounter.forMap returns, for
-- this month's season, with the Gen 5 kinds beside it
function W.view(def, save)
  local Encounter = require("src.world.Encounter")
  local season = Rules.seasonName(save)
  local t = def
  if def.seasons and season ~= "spring" and def.seasons[season] then t = def.seasons[season] end
  local hit = cache[def]
  if hit and hit.bwSeason == season then return hit end
  local function tbl(slots, rate) return slots and Encounter.gen4Table(slots, rate) or nil end
  local view = { family = "bw", id = def.id, bwSeason = season, raw = t }
  view.grassRate = t.grassRate
  view.grass = tbl(t.grass, t.grassRate)
  view.darkGrass = tbl(t.darkGrass, t.darkGrassRate)
  view.rustling = tbl(t.rustling, t.rustlingRate)
  view.water = t.surf and tbl(t.surf.slots, t.surf.rate) or nil
  view.ripplingWater = t.ripplingSurf and tbl(t.ripplingSurf.slots, t.ripplingSurf.rate) or nil
  view.superRod = t.superRod and tbl(t.superRod.slots, t.superRod.rate) or nil
  view.ripplingRod = t.ripplingFishing and tbl(t.ripplingFishing.slots, t.ripplingFishing.rate) or nil
  -- the shapes the rest of the engine asks for (surf as `surf`, rods by name)
  view.surf = t.surf
  cache[def] = view
  return view
end

-- landFor(view, map, cx, cy) -> the grass-shaped table for this tile: dark
-- grass rolls its own list (ov21 0x021AB250's behaviours)
function W.landFor(view, map, cx, cy)
  if not view then return nil end
  if view.darkGrass and Rules.isDarkGrass(map, cx, cy) then return view.darkGrass end
  return view.grass
end

return W
