-- Voxel world mode: manual window coordinates for Gen2 tilesets.
--
-- The automatic glass scanner in GlassMask.lua looks for a specific pattern
-- (6-pixel wide panes with black borders) which doesn't match all window styles
-- in Gen2/Gen3. This module provides manual coordinate overrides for windows
-- that the scanner misses.
--
-- Coordinates are in pixels on the tileset image, formatted as:
--   {x, y, w, h} where x,y is top-left corner, w is width, h is height
--
-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local WindowCoords = {}

-- Manual window rectangles per tileset image name
-- Key: tileset image filename (e.g., "tileset 0.png")
-- Value: array of {x, y, w, h} rectangles
WindowCoords.manual = {
  ["tileset 0.png"] = {
    {49, 17, 6, 6},   -- 49,17 to 54,22
    {49, 56, 6, 4},   -- 49,56 to 54,59
    {51, 56, 6, 4},   -- 51,56 to 56,59
    {36, 56, 6, 4},   -- 36,56 to 41,59
    {36, 56, 3, 4},   -- 36,56 to 38,59
    {60, 28, 8, 4},   -- 60,28 to 67,31
    {59, 12, 2, 3},   -- 59,12 to 60,14
  },

  ["over forest.png"] = {
    {33, 1, 6, 5},    -- 33,1 to 38,5
    {60, 4, 8, 4},    -- 60,4 to 67,7
    {33, 49, 6, 5},   -- 33,49 to 38,53
    {60, 52, 8, 4},   -- 60,52 to 67,55
  },

  ["over johto.png"] = {
    {49, 17, 6, 6},   -- 49,17 to 54,22
    {49, 56, 6, 4},   -- 49,56 to 54,59
    {51, 56, 6, 4},   -- 51,56 to 56,59
    {36, 56, 6, 4},   -- 36,56 to 41,59
    {36, 56, 3, 4},   -- 36,56 to 38,59
    {60, 28, 8, 4},   -- 60,28 to 67,31
    {59, 12, 2, 3},   -- 59,12 to 60,14
  },

  ["kanto.png"] = {
    {81, 1, 6, 6},    -- 81,1 to 86,6
    {93, 4, 6, 4},    -- 93,4 to 98,7
    {101, 33, 6, 12}, -- 101,33 to 106,44
  },
}

-- Get manual window rectangles for a tileset
function WindowCoords.get(tileset)
  local path = tileset and tileset.image
  if not path then return {} end
  
  -- Extract just the filename from the path
  local filename = path:match("[^/\\]+$")
  if not filename then return {} end
  
  return WindowCoords.manual[filename] or {}
end

-- Add manual windows to existing glass rects
function WindowCoords.mergeWithAuto(tileset, autoRects)
  local manual = WindowCoords.get(tileset)
  if #manual == 0 then return autoRects end
  
  local merged = {}
  -- Copy auto rects
  for _, r in ipairs(autoRects) do
    merged[#merged + 1] = r
  end
  -- Add manual rects
  for _, r in ipairs(manual) do
    merged[#merged + 1] = r
  end
  
  return merged
end

return WindowCoords
