-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4HgssFloorNo.lua -- WHICH FLOOR A JOHTO / KANTO LIFT GOT ON AT.
--
-- HGSS's `GetDynamicWarpFloorNo` (scrcmd 241) is NOT Platinum's
-- `getfloorsabove`, although the alias table lowers it onto that op:
--
--     BOOL ScrCmd_GetDynamicWarpFloorNo(ScriptContext *ctx) {
--         u16 *p_ret = ScriptGetVarPointer(ctx);
--         Location *warp = LocalFieldData_GetDynamicWarp(...);
--         *p_ret = MapNumToFloorNo(warp->mapId);
--     }
--
-- -- the same slot (the floor the car was boarded from), but a different
-- question: Platinum's `FieldMenu_GetFloorsAbove` counts the floors ABOVE it
-- and defaults to 1, HGSS's `MapNumToFloorNo` (overlay_01, 0x021EE81C) gives
-- the floor's own NUMBER and its default is an assert that returns 0.
--
-- Answered from Platinum's table, the Olivine Lighthouse car got the default
-- 1 from both ends, so scr_seq_D27R0108 took its "going down" branch every
-- time: boarded at 1F it said "Going down to the first floor", warped the
-- player back out onto 1F, and the light room could never be reached by lift.
-- The Platinum table also MISREADS two HGSS maps outright, because internal
-- names repeat across the families: T07R0101/T07R0102 are the Resort Area's
-- Ribbon Syndicate there and Celadon's department store here.
--
-- TRANSCRIBED from the switch (it is code, there is no table to extract);
-- the header id beside each row is pret's MAP_ constant, which is how the
-- internal name was looked up in include/constants/maps.h.

local M = {}

M.FLOOR_NO = {
  D27R0101 = { floor = 0, header = 115 },  -- Olivine Lighthouse 1F
  D27R0107 = { floor = 1, header = 225 },  -- Olivine Lighthouse light room
  D23R0105 = { floor = 0, header = 189 },  -- Radio Tower 5F
  D23R0106 = { floor = 1, header = 190 },  -- Radio Tower observation deck
  D37R0103 = { floor = 0, header = 200 },  -- Goldenrod Dept. Store basement
  T25R1001 = { floor = 1, header = 191 },  -- Goldenrod Dept. Store 1F
  T25R1002 = { floor = 2, header = 192 },  -- 2F
  T25R1003 = { floor = 3, header = 193 },  -- 3F
  T25R1004 = { floor = 4, header = 194 },  -- 4F
  T25R1005 = { floor = 5, header = 195 },  -- 5F
  T25R1006 = { floor = 6, header = 196 },  -- 6F
  T07R0101 = { floor = 0, header = 370 },  -- Celadon Dept. Store 1F
  T07R0102 = { floor = 1, header = 371 },  -- 2F
  T07R0103 = { floor = 2, header = 372 },  -- 3F
  T07R0104 = { floor = 3, header = 373 },  -- 4F
  T07R0105 = { floor = 4, header = 374 },  -- 5F
  T07R0106 = { floor = 5, header = 375 },  -- roof
  T07R0201 = { floor = 0, header = 376 },  -- Celadon Condominiums 1F
  T07R0202 = { floor = 1, header = 377 },  -- 2F
  T07R0203 = { floor = 2, header = 378 },  -- 3F
  T07R0204 = { floor = 3, header = 379 },  -- roof
  T11R0701 = { floor = 0, header = 402 },  -- Silph Co. HQ
  T11R0702 = { floor = 1, header = 403 },  -- Silph Co. Rotom room
}

-- `GF_AssertFail(); return 0;`
M.DEFAULT = 0

function M.floorNo(mapId)
  local row = mapId and M.FLOOR_NO[mapId]
  if row then return row.floor end
  return M.DEFAULT
end

return M
