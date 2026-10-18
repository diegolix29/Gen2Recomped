-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A GEN 4 HOP'S HEIGHT, IN THE WORLD AND THEN ON THE SCREEN.
--
-- The cartridge (pokeplatinum src/unk_020655F4.c, MovementAction_Jump_Step1;
-- HGSS's movement table plays the same actions): a ledge is JumpFar -- two
-- units a frame for sixteen field frames -- and each frame the object's
-- sprite JUMP OFFSET is set to `sJumpHeights_High[frame]`, in world units
-- straight up, while its own height is recalculated from the terrain under
-- it (MapObject_RecalculateObjectHeight). On the last frame the offset goes
-- back to zero.
--
-- This engine had drawn every hop as ten FLAT PIXELS of sine, the Game Boy
-- ledge's. On the cartridge camera that is near enough; on a tilted rung it is
-- too much (the world's heights shrink with cos(pitch) and the arc did not),
-- and in the free cameras a flat pixel is not a height at all. So the arc is
-- the cartridge's table, and `flatLift` turns it into the flat pixels the
-- sprite is drawn up by FOR THE CAMERA NOW DRAWING: x heightScale on the
-- cartridge and tilt rungs (the same lean every terrain height gets), and the
-- projected rise of that many units above the ground under the player in the
-- free cameras, divided by the scale `Gen4Ground:freeEntity` draws the sprite
-- at.

local J = {}

-- sJumpHeights_High, FX32_CONST units
J.HIGH = { 4, 6, 8, 10, 11, 12, 12, 12, 11, 10, 9, 8, 6, 4, 0, 0 }

-- The world-unit height `remaining` engine frames before a hop of `total`
-- lands. The table is indexed by field frame (unk_0A / 0x100, one step a
-- frame starting at 1), and an engine hop is the same sixteen field frames
-- however many engine frames it spans.
function J.units(remaining, total)
  remaining, total = tonumber(remaining) or 0, tonumber(total) or 0
  if remaining <= 0 or total <= 0 then return 0 end
  local f = math.ceil((total - remaining) / total * 16)
  if f < 1 then f = 1 end
  if f > 15 then return 0 end
  return J.HIGH[f + 1] or 0
end

-- The Gen 4 ground the overworld is drawing, or nil off Gen 4.
local function groundOf()
  local ow = package.loaded["src.core.Game"] and package.loaded["src.core.Game"].overworld
  local map = ow and ow.map
  if not (map and map.def and map.def.generation == 4) then return nil end
  return map.renderer and map.renderer.gen4Ground or nil
end
J.groundOf = groundOf

-- flatLift(entity [, ground]) -> flat pixels to draw the sprite up by, or nil
-- when this is not a Gen 4 map (the caller keeps its own arc).
function J.flatLift(e, ground)
  ground = ground or groundOf()
  if not (ground and e) then return nil end
  local units = J.units(e.hopFrames, e.hopTotal)
  if units == 0 then return 0 end
  local free = ground.freeMode and ground:freeMode()
  local view = free and ground.view3d
  if view and ground.freeW and ground.freeH then
    local fx, fz = (e.px or 0) + 8, (e.py or 0) + 8
    local y = ground:groundY(fx, fz) or 0
    local gx, gz = fx + (ground.offsetX or 0), fz + (ground.offsetY or 0)
    local _, y0, s0 = view:project(gx, y, gz, ground.freeW, ground.freeH)
    local _, y1 = view:project(gx, y + units, gz, ground.freeW, ground.freeH)
    if y0 and y1 and s0 and s0 > 0 then
      return math.floor((y0 - y1) / s0 + 0.5)
    end
    return units
  end
  return math.floor(units * (ground.heightScale or 1) + 0.5)
end

return J
