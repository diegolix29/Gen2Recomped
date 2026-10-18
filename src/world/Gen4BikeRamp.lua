-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S BIKE RAMPS: the east- and westward jumps (behaviours 0xD7 /
-- 0xD8, TILE_BEHAVIOR_BIKE_RAMP_EASTWARD / _WESTWARD).
--
-- Reported from play: "Bike is missing the code to make bike ramps
-- crossable".  None of it reached the port.  pokeplatinum src/player_move.c:
--
--   * PlayerAvatar_WillHitBikeRamp: stepping EAST into an eastward ramp (or
--     west into a westward one) is PLAYER_COLLISION_BIKE_RAMP.
--       - on foot that is a collision like any other: a bump
--       - third gear rides onto it (WALK_SLIGHTLY_FASTER, forced)
--       - fourth gear rides onto it only at AVATAR_MOVE_SPEED_3; slower is a
--         bump with SEQ_SE_DP_WALL_HIT and the speed cleared
--   * PlayerAvatar_TileMove_BikeRampEast / _West, standing on it: fourth gear
--     launches JUMP_FARTHER (4 units a frame for 12 frames: three tiles) with
--     SEQ_SE_DP_DANSA4, third gear JUMP_NEAR_SLOW (1 x 16: one tile), and the
--     speed is kept (SetForceMovementRetainSpeed)
--   * PlayerAvatar_TryCyclingGearChange: no gear change on a ramp
--
-- Measured over land_data: 0xD7 / 0xD8 in chunks 171, 413, 414, 442, 443
-- and 489..491.

local R = {}

R.EAST, R.WEST = 0xD7, 0xD8
R.TOP_SPEED = 3

-- Platinum's: HGSS leaves behaviours 0xD7..0xDA unnamed (TILE_BEHAVIOR_215..)
local function gen4(map)
  return map and map.def and map.def.generation == 4
    and require("src.core.GameVersion").family() ~= "hgss"
end

local function behaviourAt(map, x, y)
  if not (map and map.cellBehaviour) then return nil end
  local ok, b = pcall(map.cellBehaviour, map, x, y)
  return ok and b or nil
end

-- whether (x, y) is a ramp at all
function R.isRamp(map, x, y)
  local b = behaviourAt(map, x, y)
  return b == R.EAST or b == R.WEST
end

local function sound(name)
  local G = package.loaded["src.core.Game"]
  pcall(function() require("src.core.Sound").play(G.data, name) end)
end

-- blocks(ow, dir) -> true when the press must not become a step (it has
-- already turned the player and bumped)
function R.blocks(ow, dir)
  local map, p = ow and ow.map, ow and ow.player
  if not (gen4(map) and p) or p.surfing then return false end
  -- G4GEAR=0|1: a harness switch, that gear whatever B last chose
  local force = os.getenv and tonumber(os.getenv("G4GEAR") or "")
  if force and p.gen4Gear ~= nil then p.gen4Gear = force end
  if dir ~= "left" and dir ~= "right" then return false end
  local dx = (dir == "right") and 1 or -1
  local b = behaviourAt(map, p.cellX + dx, p.cellY)
  local hit = (dir == "right" and b == R.EAST) or (dir == "left" and b == R.WEST)
  if not hit then return false end
  if os.getenv and os.getenv("G4RAMPDBG") then
    print(("[ramp] press %s gear %s speed %s at %d,%d"):format(dir, tostring(p.gen4Gear), tostring(p.gen4Speed), p.cellX, p.cellY))
  end
  local G = package.loaded["src.core.Game"]
  local onBike = G and G.save and G.save.onBike
  -- THE RAMP'S OWN TILE IS SOLID to everything else (its permission says
  -- so), and the bike gets onto it the way the cartridge does -- a forced
  -- step taken before the collision is asked (SetForceMovement): third gear
  -- WALK_SLIGHTLY_FASTER (3 field frames), fourth at full speed FASTER (2)
  local ride = onBike and ((p.gen4Gear or 0) == 0 or (p.gen4Speed or 0) >= R.TOP_SPEED)
  if ride then
    p.facing = dir
    local frames = ((p.gen4Gear or 0) == 1) and 4 or 6
    ow.gen4RampJump = true
    ow:scriptMove(p, dir, 1, function()
      ow.gen4RampJump = nil
      ow:onStepComplete()
    end, false, frames / (p.stepFrames or 16))
    return true
  end
  -- a bump: the turn, the wall's sound, and the run is lost
  p.facing = dir
  if onBike then p.gen4Speed = 0 end
  -- once per press, not once per frame it is held
  local now = love and love.timer and love.timer.getTime() or 0
  if not (R.lastBump and now - R.lastBump < 0.27) then sound("SEQ_SE_DP_WALL_HIT") end
  R.lastBump = now
  return true
end

-- arrive(ow) -> true when standing on a ramp launched the player
function R.arrive(ow)
  local map, p = ow and ow.map, ow and ow.player
  if not (gen4(map) and p) or p.surfing then return false end
  local b = behaviourAt(map, p.cellX, p.cellY)
  if b ~= R.EAST and b ~= R.WEST then return false end
  local dir = (b == R.EAST) and "right" or "left"
  local fourth = (p.gen4Gear or 0) == 1
  local tiles = fourth and 3 or 1
  -- engine frames are the cartridge's field frames twice over
  local frames = fourth and 24 or 32
  if fourth then sound("SEQ_SE_DP_DANSA4") end
  p.hopFrames, p.hopTotal = frames, frames
  ow.gen4RampJump = true
  ow:scriptMove(p, dir, tiles, function()
    ow.gen4RampJump = nil
    ow:onStepComplete()
  end, true, (frames / tiles) / ((p.stepFrames or 16)))
  return true
end

return R
