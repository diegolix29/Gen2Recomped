-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE WARP MOVEMENT ACTIONS, 67 WarpOut and 68 WarpIn: a map object rising
-- out of the picture or dropping into it.
--
-- READ FROM CODE: pokeplatinum src/unk_020655F4.c (HGSS runs the same two
-- step tables; its movement code is not yet decompiled):
--
--   WarpOut  step 0: data->dy = FX32_CONST(16); then step 1 every frame:
--            y += dy; MapObject_SetSpriteJumpOffset(0, y, 0); done when
--            y / FX32_CONST(8) >= 40, i.e. y = 320 -- twenty frames.
--   WarpIn   step 0: y = FX32_CONST(8) * 40 = 320, dy = -16; step 1 every
--            frame: y += dy, clamped at 0, offset set; done at 0 -- twenty
--            frames, the first one drawn at 304.
--
-- Step 0 returns TRUE, so step 1 runs in the same frame; the action ends on
-- the frame the offset reaches its end.  A field frame is two engine ticks.
--
-- Users: HGSS Olivine Lighthouse's ledge (D27R0103, the drop from 4F's
-- window, with ScrCmd_374 showing the player one frame in), the Bell / Burned
-- Tower basements and the other WarpIn arrivals (D24R02xx, D39R0103,
-- D43R0102); Platinum's Distortion World B6F lake guardians
-- (DistortionWorldB6F_Movement_LakeGuardianWarpOut, then
-- DeleteDistortionWorldMapObject).
--
-- The offset is `entity.spriteOffset.lift`: world units up, the way the
-- legendary birds and the surf mount already ride (OverworldController
-- riseOf / Gen4SurfMount.poseFor).
--
-- STAND-IN: a WarpOut leaves the object lifted, as the cartridge does (the
-- object is deleted or the map changes next) -- except the PLAYER, whose
-- entity this port carries across maps where the cartridge rebuilds it: the
-- player's lift is cleared when the action ends.  The only player WarpOuts
-- are the Wi-Fi Plaza's and the Underground's.

local M = {}

M.STEP = 16
M.TOP = 320
M.TICKS_PER_FRAME = 2

local function setLift(entity, y)
  local so = entity.spriteOffset
  if y == nil or y == 0 then
    if so and so.g4Warp then entity.spriteOffset = nil end
    return
  end
  if not (so and so.g4Warp) then
    so = { g4Warp = true }
    entity.spriteOffset = so
  end
  so.lift = y
end

-- run(ow, entity, dir, done): plays the action, calls done when it ends
function M.run(ow, entity, dir, done)
  local out = dir == "out"
  local y = out and 0 or M.TOP
  local function frame()
    if out then
      y = y + M.STEP
      setLift(entity, y)
      if y >= M.TOP then
        if entity == ow.player then setLift(entity, nil) end
        return done()
      end
    else
      y = math.max(0, y - M.STEP)
      setLift(entity, y)
      if y <= 0 then return done() end
    end
    -- ONE MORE THAN THE FRAME: OverworldState:updateScriptMoves counts a
    -- pause queued from inside its own pass (this chain's onDone) down once
    -- in that same pass, so `TICKS_PER_FRAME + 1` is two ticks of standing
    -- still -- measured, see the field_fx lighthouse run
    ow:scriptPause(entity, M.TICKS_PER_FRAME + 1, frame)
  end
  frame()
end

return M
