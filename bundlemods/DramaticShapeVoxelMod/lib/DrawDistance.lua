-- Voxel world mode: draw distance control for performance.
--
-- Controls how many adjacent maps (neighbors) are rendered, which significantly
-- affects performance on low-end PCs and mobile devices by reducing the amount
-- of world geometry that needs to be processed and displayed.
--
--   OFF:   No limit (original behavior, all neighbors rendered)
--   NEAR:  0 neighbors (current map only, best performance)
--   MILD:  2 neighbors (balanced quality/performance)
--   FAR:   4 neighbors (moderate quality/performance balance)

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local DrawDistance = {}

DrawDistance.KEY = "drawDistance"
DrawDistance.LABEL = "DRAW DIST"

-- Neighbor limits: how many adjacent maps to render based on distance setting
-- OFF uses nil to indicate no limiting (original behavior)
DrawDistance.NEIGHBOR_LIMITS = { nil, 0, 2, 4 }  -- OFF: no limit, Near: 0, Mild: 2, Far: 4

DrawDistance.setting = ModSetting.new(DrawDistance.KEY, DrawDistance.LABEL,
                                       { 0, 1, 2, 3 },
                                       { "OFF", "NEAR", "MILD", "FAR" })

function DrawDistance.level()
  return DrawDistance.setting:get() or 0  -- Default to OFF (index 0)
end

-- Get the neighbor limit for the current setting (how many adjacent maps to render)
-- Returns nil if OFF (no limiting), otherwise returns the limit
function DrawDistance.neighborLimit()
  return DrawDistance.NEIGHBOR_LIMITS[DrawDistance.level() + 1]
end

-- Check if draw distance limiting is enabled
function DrawDistance.isEnabled()
  return DrawDistance.neighborLimit() ~= nil
end

function DrawDistance.row()
  return DrawDistance.setting:row()
end

function DrawDistance.sync(value)
  DrawDistance.setting:sync(value)
end

return DrawDistance
