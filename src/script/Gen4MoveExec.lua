-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM / HGSS `applymovement`: TWO TIMING RULES THE EXECUTOR SHARES WITH
-- BLACK AND WHITE (src/script/Gen5MoveExec.lua), used from
-- Commands.g4_move.
--
--   * SCRIPTED SPEED FOR NPCs. A WALK_FAST / WALK_FASTER action carries its
--     speed as `rate` (Gen4Movement), and `scriptMove` applies it to
--     `stepFramesCur` -- which Player reads and NPC:update never did. An NPC
--     walks on `scriptStepLen` (the field the BW executor introduced), so a
--     Sinnoh or Johto rush walked at the stroll's 16 ticks a tile while the
--     player beside them hurried. Set per walking step; a normal-speed step
--     clears it, and so does the end of the list.
--   * WAITS IN FIELD FRAMES. The Delay1..Delay32 actions (pokeheartgold
--     asm/macros/movement.inc; Platinum's MOVEMENT_ACTION_DELAY_*) count the
--     map-object task's frames, and the field runs at 30 frames a second:
--     one frame is two of this engine's
--     60 Hz ticks, the same rate Gen4Emotes / Gen4Jump use for HGSS and
--     Gen5Movement.TICKS_PER_FRAME for BW. Counted as ticks, every wait in a
--     cutscene was half as long as the cartridge's.

local M = {}

M.TICKS_PER_FRAME = 2
M.NORMAL_TICKS = 16

-- the engine ticks of `count` repetitions of a wait of `frames` field frames
function M.waitTicks(frames, count)
  local f = math.max(1, tonumber(frames) or 1)
  local n = math.max(1, tonumber(count) or 1)
  return f * n * M.TICKS_PER_FRAME
end

-- the step length an NPC walks a step of `rate` at (nil = its own pace)
function M.stepLen(entity, rate)
  rate = tonumber(rate)
  if not rate or rate == 1 then return nil end
  local base = (entity and tonumber(entity.stepFrames)) or M.NORMAL_TICKS
  return math.max(1, math.floor(base * rate + 0.5))
end

-- stamp (or clear) the NPC's scripted step length for the step about to run;
-- the player keeps scriptMove's own `stepFramesCur` path
function M.setStep(entity, ow, rate)
  if not entity or (ow and entity == ow.player) then return end
  entity.scriptStepLen = M.stepLen(entity, rate)
end

return M
