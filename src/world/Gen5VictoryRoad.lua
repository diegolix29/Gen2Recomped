-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- VICTORY ROAD'S OUTSIDE (Black / White, zone 214). No decomp: read off the
-- Black ROM's data.
--
-- The mountainside is a rail map (rail file /a/0/7/9 #9; Gen5Field rasterises
-- its rails into the grid, gen5NoGrid) and its rails are ELEVEN separate
-- networks -- no line joins one to another -- each flat at its own height:
-- 3, 8, 83, 90, 170, 245, 247, 327, 407, 409 and 483 units. Between them the
-- caves (Z215 .. Z228) are the only way. Rasterised onto one grid with no
-- height rule (rail maps have none: Gen4HeightRule.gen5Blocks), wherever two
-- of those paths' corridors touched they ran together, and the whole lower
-- mountainside was one floor: from the gate the player walked to the cave
-- that leads to the top (Z227's mouth at (52,17)) without setting foot in
-- the others. `gen5RailLayers` turns the height rule on for this map: each
-- path keeps its own height (the rasterised cell's), and a step between two
-- 20 units apart is a wall, as everywhere else in Unova.
--
-- AND ITS TOP. The topmost path (height 483) runs to z -48 and the lowest one
-- to x -191: past the grid's corner, which Gen5Field's raster cannot go below.
-- What stood there -- the League's gate trigger (coord 1 at (30..33, -3),
-- M0428 S0017: up to the League, Z136), the landing from the League's south
-- edge (warps 11, 28, 29 at (31..33, -3)), the arrival from Z228 (warps 19
-- and 35 at (36..37, -4)) and an item (person 4 at (-9, 42)) -- is moved to
-- the nearest open cell of the grid in the same column or row (row 0 of the
-- top path; column 0 of the lowest). INFERRED: those few cells of the paths'
-- far ends are not walked as the cartridge has them.

local M = {}

M.HEADER = 214

local function open(def, x, y)
  if x < 0 or y < 0 or x >= def.width or y >= def.height then return false end
  local i = y * def.width + x
  local b1, b2 = def.blocks:byte(i * 2 + 1, i * 2 + 2)
  return b1 ~= 255 and not (b2 and b2 >= 0x80)
end

local function inside(def, x, y, w)
  local nx, ny = math.max(x, 0), math.max(y, 0)
  for _ = 1, 8 do
    local ok = true
    for k = 0, (w or 1) - 1 do if not open(def, nx + k, ny) then ok = false end end
    if ok then return nx, ny end
    if y < 0 then ny = ny + 1 else nx = nx + 1 end
  end
  return math.max(x, 0), math.max(y, 0)
end

function M.attach(def)
  if not (def and def.gen5 and def.header == M.HEADER and def.gen5NoGrid) then return end
  def.gen5RailLayers = true
  if def.gen5VictoryRoadClamped or type(def.blocks) ~= "string" then return end
  def.gen5VictoryRoadClamped = true
  for _, list in ipairs({ def.warps or {}, def.coordEvents or {}, def.objects or {} }) do
    for _, e in ipairs(list) do
      if e.x and e.y and (e.x < 0 or e.y < 0) then
        e.gen5RawX, e.gen5RawY = e.x, e.y
        e.x, e.y = inside(def, e.x, e.y, list == def.coordEvents and e.width or 1)
      end
    end
  end
end

-- an arrival set down past the grid's corner (a warp record read before
-- `attach` moved it): the same nearest open cell
function M.arrival(def, x, y)
  if not (def and def.gen5 and def.header == M.HEADER and def.gen5NoGrid and x and y) then return x, y end
  if x >= 0 and y >= 0 then return x, y end
  return inside(def, x, y, 1)
end

return M
