-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S STRENGTH PUSH (pokeplatinum src/overlay005/ov5_021DFB54.c,
-- ov5_021DFF1C -> ov5_021DFF88 -> the task ov5_021DFFBC).
--
-- Walking into OBJ_EVENT_GFX_STRENGTH_BOULDER (0x54) with Strength active and
-- the cell beyond it free:
--   the boulder   MOVEMENT_ACTION_WALK_SLOW_<dir>      (16 field frames a tile)
--   the player    MOVEMENT_ACTION_WALK_ON_SPOT_NORMAL_<dir>
--   one sound     SEQ_SE_DP_UG_023, as the two start
-- and that is all: the task waits for both to finish (or hands a Distortion
-- World pit to DistWorldFallingBoulder) and ends. There is NO dust and no
-- second sound -- the puff and SFX_CUT the port drew after every push are
-- Gold / Silver / Crystal's DoBoulderDustAnimation, which Sinnoh does not have.

local M = {}

M.SE = "SEQ_SE_DP_UG_023"
-- WALK_SLOW against the walker's normal step (OverworldState:scriptMove's rate)
M.RATE = 2

-- Platinum (not HGSS, whose push is not checked against pokeheartgold here,
-- and not Black / White)
function M.platinum()
  local G = package.loaded["src.core.Game"]
  local data = G and G.data
  if not (data and data.isGen4Cache) then return false end
  local okV, GV = pcall(require, "src.core.GameVersion")
  if okV and GV.isGen5 and GV.isGen5() then return false end
  local v = data.gen4_version
  return not (v and v.family == "hgss")
end

-- the sound and the player's step on the spot, as the push starts
function M.start(ow, dir)
  local G = package.loaded["src.core.Game"]
  pcall(function() require("src.core.Sound").playSe(G.data, M.SE) end)
  local p = ow and ow.player
  if p and ow.marchInPlace then
    p.facing = dir or p.facing
    pcall(ow.marchInPlace, ow, p)
  end
end

return M
