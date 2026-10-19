-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S OTHER HEADBUTT TREES: the forest around the map.
--
-- A Headbutt tree is either a TILE_BEHAVIOR_HEADBUTT (6) tile or a tile that
-- lies in a matrix cell whose land data is model 0xD0
-- (FieldSystem_FacingModelIsHeadbuttTree, field_control.c ->
-- MapModel_IsHeadbuttTree, unk_02054E00.c: `mapModelNo == 0xd0`, the number
-- GetMapModelNo reads out of the matrix for the facing tile). Land 208 is the
-- solid-forest filler chunk that rings the routes -- 100+ cells of the main
-- matrix -- so every tree of the border forest is one, not only the trees
-- drawn on the route's own land.
--
-- Both doors use it: pressing A at the forest (GetInteractedHeadbuttTreeScript,
-- after the bg events and the metatile scripts -> std_field_headbutt) and the
-- party menu's HEADBUTT (FieldMove_CheckHeadbutt's FIELD_MOVE_CHECK_HEADBUTT).

local M = {}

M.TREE_LAND = 0xD0

local function groundOf(ow)
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
end

-- the land data id of the matrix cell holding map cell (cx, cy), or nil
function M.landAt(ow, cx, cy)
  local ground = groundOf(ow)
  local grid = ground and ground.grid
  local terrain = ground and ground.terrain
  if not (grid and grid.land and terrain) then return nil end
  local chunkPx = ground.chunkPx or ((terrain.chunkUnits or 512) * (terrain.pixelsPerUnit or 1))
  local mx = cx * 16 + 8 + (ground.offsetX or 0)
  local my = cy * 16 + 8 + (ground.offsetY or 0)
  if mx < 0 or my < 0 then return nil end
  local gx, gy = math.floor(mx / chunkPx), math.floor(my / chunkPx)
  if gx >= (grid.width or 0) or gy >= (grid.height or 0) then return nil end
  return grid.land[gy * grid.width + gx + 1]
end

function M.isTreeLand(land) return land == M.TREE_LAND end

-- FieldSystem_FacingModelIsHeadbuttTree
function M.facingTree(ow)
  local p = ow and ow.player
  if not (p and p.cellX) then return false end
  local dx, dy = 0, 0
  if p.facing == "up" then dy = -1 elseif p.facing == "down" then dy = 1
  elseif p.facing == "left" then dx = -1 else dx = 1 end
  return M.isTreeLand(M.landAt(ow, p.cellX + dx, p.cellY + dy))
end

return M
