-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S ICE (Icirrus Gym, zone 114; Cold Storage, zones 192/193).
-- No decomp: read off the Black ROM's overlay 21 (the field).
--
-- READ FROM CODE:
--   ov21 0x21A67A4 picks the player's forced-movement kind from the attribute
--   of the cell the player STANDS on (map object +0x74, written as each step
--   lands): 0x21AB348 answers 1 for behaviours 0x18 and 0x10 -- ice. (2..7
--   are the rail's own slide tiles, 0xA5 0xA4 0xA7 0xA6 0xA8 0xB0, which only
--   occur on rails: src/world/Gen5IcirrusGym.lua.)
--   Kind 1's handler (table 0x21D8AB8 -> 0x21A6908) asks the ordinary step
--   collision (0x21A5B6C -> 0x219E424, the walk's own test) for the facing
--   direction; blocked, it clears the forced movement (0x21A6870) and the
--   player stands; open, it keeps the facing and starts the next step at
--   movement code 0x2197E7C(dir, 0x10). Nothing else: no speed, no slopes --
--   the slide stops on the first cell that is not ice or the first step the
--   walk itself would refuse (a wall, a person, a height step).
-- INFERRED: the step's length (code 0x10) is taken as the Gen 4 ice step's,
-- half a walk.

local Collision = require("src.world.Collision")

local M = {}

M.BEHAVIOURS = { [0x18] = true, [0x10] = true }
M.RATE = 0.5

function M.isIce(behaviour) return behaviour ~= nil and M.BEHAVIOURS[behaviour] == true end

local function stop(ow)
  ow.iceSlide = nil
  return false
end

-- one forced step from the cell the player has just arrived on; true when a
-- step was started (OverworldState:checkGen2Ice's contract)
function M.step(ow)
  local p, map = ow.player, ow.map
  if not (p and map) or p.surfing or not ow:isIceCell(p.cellX, p.cellY) then return stop(ow) end
  local dir = ow.iceSlide or p.facing
  if not Collision.canMove(map, ow.cast or ow.entities, p, dir) then return stop(ow) end
  ow.iceSlide = dir
  p.facing = dir
  ow:scriptMove(p, dir, 1, function() ow:onStepComplete() end, false, M.RATE)
  return true
end

return M
