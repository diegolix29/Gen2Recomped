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

function Cells.behaviour(map, cx, cy)
  if not map then return nil end
  -- cellBehaviour is the real behaviour byte on both Platinum outdoor
  -- (permission low byte via Gen4Ground) and B/W (behaviorCells). blockAt
  -- on B/W is 0/255 collision, so it must not be asked first.
  if map.inBounds and map:inBounds(cx, cy) then
    if type(map.cellBehaviour) == "function" then
      local okC, b = pcall(map.cellBehaviour, map, cx, cy)
      if okC and type(b) == "number" then return b end
    end
    if map.blockAt then
      local ok, b = pcall(map.blockAt, map, cx, cy)
      if ok and type(b) == "number" then return b end
    end
    return nil
  end
  local ground = map.renderer and map.renderer.gen4Ground
  if ground and type(ground.behaviourAt) == "function" then
    local okG, gb = pcall(ground.behaviourAt, ground, cx, cy)
    if okG and type(gb) == "number" then return gb end
  end
  local def = map.def
  if not def then return nil end
  local cells = def.behaviorCells
  if type(cells) == "string" then
    local w = tonumber(def.width) or 0
    local h = tonumber(def.height) or 0
    if w > 0 and cx >= 0 and cy >= 0 and cx < w and cy < h then
      local v = cells:byte(cy * w + cx + 1)
      if v then return v end
    end
  end
  -- B/W layout.blocks is collision (0/255), not behaviour.
  if def.gen5 then return nil end
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
