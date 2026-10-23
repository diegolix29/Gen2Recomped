-- Gen4Cells: what a Gen 4 cell IS, for any cell of the world -- not just the
-- ones inside the map you are standing in.
--
-- WHY THIS EXISTS
--
-- A Gen 4 "map" is not a world. It is a rectangle cropped out of one shared
-- grid (MapLoader.resolveBlocks: `def.blocks` is the layout's rows from
-- `originX/originY`, `width x height` cells). The engine's ground draws every
-- chunk of that shared grid around you -- neighbouring towns and routes
-- included -- but `Map:blockAt` only knows the crop: outside it, it answers the
-- border block and `Map:inBounds` says no.
--
-- Grass and sand asked the Map, so they grew only inside the current map and
-- stopped dead at its edge while the neighbour's ground carried on without
-- them. The neighbour's cells are not missing, though: the whole grid is still
-- in `Data.map_layouts[def.layout].blocks`, two bytes a cell, row-major, the
-- same bytes the crop was cut from.
--
-- WHAT IT ANSWERS
--
--   Cells.behaviour(map, cx, cy) -> the number Map:blockAt would give for the
--   cell, in the MAP's own cell coordinates (negative and past-the-edge allowed),
--   or nil when the cell is off the shared grid altogether.
--
-- Inside the crop it asks the live Map, so edits (a cut tree, a stamped door)
-- still show; outside it reads the layout, decoded exactly the way
-- Map.blockArray does it: little-endian u16, modulo 1024.

local V = ...

local Cells = {}

local function layoutFor(map)
  local def = map and map.def
  if not (def and def.layout) then return nil end
  local okG, Game = pcall(require, "src.core.Game")
  local data = okG and Game and Game.data
  local layouts = data and data.map_layouts
  local layout = layouts and layouts[def.layout]
  if layout and type(layout.blocks) == "string" then return layout end
  return nil
end

-- The layout lookup is per call to behaviour(); it is a few table reads, but a
-- chunk build asks 16 times, so remember the last answer for the same def.
local lastDef, lastLayout

-- ---------------------------------------------------------------- Black / White --
--
-- B/W keep their tile behaviour in `def.behaviorCells` (one byte a cell, read by
-- `Map:cellBehaviour`) -- NOT in `def.blocks`, which Gen5Field fills with "\0\0" /
-- "\255\0" (open / blocked) for the rails. So `Map:blockAt` is useless for B/W
-- and the numbers are B/W's own, not Platinum's: 0x04 / 0x05 / 0x21 are grass,
-- 0x06 / 0x07 / 0x22 dark grass, 0x08 / 0x09 tall (rustling) grass, 0x0C / 0x23
-- sand, and 0x03 is a dirt path (Platinum's "very tall grass"). Read as Platinum's
-- they plant 3D grass on dirt paths and miss every real meadow.
-- The sets come from the engine's own table (src/world/Gen5FieldRules.lua) when it
-- loads, so they cannot drift from what the game rolls encounters on.
local BW_GRASS = { [0x04] = true, [0x05] = true, [0x21] = true, [0x08] = true,
                   [0x06] = true, [0x07] = true, [0x22] = true, [0x09] = true }
local BW_SAND = { [0x0C] = true, [0x23] = true }
do
  local ok, R = pcall(require, "src.world.Gen5FieldRules")
  if ok and type(R) == "table" and type(R.GRASS) == "table" then BW_GRASS = R.GRASS end
end
Cells.BW_GRASS, Cells.BW_SAND = BW_GRASS, BW_SAND

function Cells.isBW(map)
  local def = map and map.def
  return def ~= nil and def.gen5 and true or false
end

-- Does behaviour number `b` mean wild-Pokemon grass on this map's cartridge?
-- Platinum: TALL_GRASS 2 / VERY_TALL_GRASS 3. Black / White: BW_GRASS.
function Cells.isGrassValue(map, b)
  if b == nil then return false end
  if Cells.isBW(map) then return BW_GRASS[b] == true end
  return b == 2 or b == 3
end

-- ...and beach sand. `platinumSet` is the caller's own list (Gen4Sand.BEHAVIOURS).
function Cells.isSandValue(map, b, platinumSet)
  if b == nil then return false end
  if Cells.isBW(map) then return BW_SAND[b] == true end
  return platinumSet ~= nil and platinumSet[b] == true
end

-- a B/W layout's behaviour byte for a cell of the shared grid (outside the crop)
local function bwBehaviour(map, cx, cy)
  if map.inBounds and map:inBounds(cx, cy) then
    if type(map.cellBehaviour) ~= "function" then return nil end
    local ok, b = pcall(map.cellBehaviour, map, cx, cy)
    if ok and type(b) == "number" then return b end
    return nil
  end
  local def = map.def
  local layout = layoutFor(map)
  local cells = layout and layout.behaviorCells
  if type(cells) ~= "string" then return nil end
  local stride = layout.width or def.width
  local rows = layout.height or def.height
  if not (stride and rows) then return nil end
  local gx, gy = (def.originX or 0) + cx, (def.originY or 0) + cy
  if gx < 0 or gy < 0 or gx >= stride or gy >= rows then return nil end
  return cells:byte(gy * stride + gx + 1)
end

function Cells.behaviour(map, cx, cy)
  if not map then return nil end
  if Cells.isBW(map) then return bwBehaviour(map, cx, cy) end
  if map.inBounds and map.blockAt and map:inBounds(cx, cy) then
    local ok, b = pcall(map.blockAt, map, cx, cy)
    if ok and type(b) == "number" then return b end
    return nil
  end
  local def = map.def
  if not def then return nil end
  local layout
  if lastDef == def and lastLayout then
    layout = lastLayout
  else
    layout = layoutFor(map)
    lastDef, lastLayout = def, layout
  end
  if not layout then return nil end
  local stride = layout.width or def.width
  local rows = layout.height or def.height
  if not (stride and rows) then return nil end
  local gx, gy = (def.originX or 0) + cx, (def.originY or 0) + cy
  if gx < 0 or gy < 0 or gx >= stride or gy >= rows then return nil end
  local at = (gy * stride + gx) * 2
  local lo, hi = layout.blocks:byte(at + 1, at + 2)
  if not hi then return nil end
  return (lo + hi * 256) % 1024
end

-- True when the cell is inside the map's own crop (so the live Map answers).
function Cells.inMap(map, cx, cy)
  return map and map.inBounds and map:inBounds(cx, cy) and true or false
end

function Cells.reset() lastDef, lastLayout = nil, nil end

return Cells
