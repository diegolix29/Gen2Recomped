-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S DEPTH-FOG WEATHERS, 26..30: the 3D engine's own fog.
--
-- Stark Mountain's caves are weather 28 (D16R0101..R0103), and this port drew
-- nothing for it ("WEATHER_28 has no look").  The cartridge's task for it,
-- ov5_021DB438 (pokeplatinum src/overlay005/ov5_021D5EB8.c), and its four
-- siblings are one call each to ov5_021D9DFC with a slope, an offset and a
-- colour, which turns on the DS's hardware fog:
--
--     26  ov5_021DB3E0   slope 3  offset 26095  GX_RGB(2, 2, 6)
--     27  ov5_021DB40C   slope 2  offset 26415  GX_RGB(13, 25, 30)
--     28  ov5_021DB438   slope 2  offset 26415  GX_RGB(20, 0, 0)   (Stark)
--     29  ov5_021DB460   slope 2  offset 26415  GX_RGB(0, 0, 20)
--     30  ov5_021DB48C   slope 1  offset 19311  GX_RGB(1, 1, 1)
--
-- ov5_021D7384: FogManager_ApplyParameters(enabled, COLOR_ALPHA, slope,
-- offset) and the colour at alpha 31.  On a map loaded with the weather the
-- density table is set at once (ov5_021D74D4 -> ov5_021D7534 with step 1):
-- entry i is 4 * i, so the fog thickens linearly over the 32 entries to
-- 124 / 127.  The hardware reads the entry for a pixel from its depth (the
-- 15-bit z-buffer value) as (depth - offset) >> (10 - slope)... that is, each
-- entry covers 0x400 >> slope depth units, and blends colour and fog by it.
--
-- Here: the pass tells Gen4Model how to turn a fragment's depth back into a
-- distance from the eye, and the shader puts that distance through the
-- cartridge camera's own near / far to get the depth the DS would have
-- fogged by.

local F = {}

F.WEATHERS = {
  [26] = { slope = 3, offset = 26095, rgb = { 2, 2, 6 } },
  [27] = { slope = 2, offset = 26415, rgb = { 13, 25, 30 } },
  [28] = { slope = 2, offset = 26415, rgb = { 20, 0, 0 } },
  [29] = { slope = 2, offset = 26415, rgb = { 0, 0, 20 } },
  [30] = { slope = 1, offset = 19311, rgb = { 1, 1, 1 } },
  -- ...and the particle weathers' own fog (ov5_021D7308 in their init):
  -- snow 0x6F6F + 0x300, heavy snow - 0x200, blizzard - 0x400, the unnamed
  -- heavy snow 21 at 0x6F6F itself, and SLOW_ASHFALL's yellowish haze
  [5]  = { slope = 3, offset = 0x726F, rgb = { 26, 26, 26 } },
  [6]  = { slope = 3, offset = 0x6D6F, rgb = { 24, 24, 24 } },
  [7]  = { slope = 3, offset = 0x6B6F, rgb = { 24, 24, 24 } },
  [21] = { slope = 3, offset = 0x6F6F, rgb = { 24, 24, 24 } },
  [9]  = { slope = 3, offset = 0x6F6F - 0x40, rgb = { 20, 20, 14 } },
}

local function game() return package.loaded["src.core.Game"] end

local function platinum()
  local G = game()
  local data = G and G.data
  local v = data and data.gen4_version
  local ok, GV = pcall(require, "src.core.GameVersion")
  return data and data.isGen4Cache and not (ok and GV.isGen5()) and not (v and v.family == "hgss")
end

-- the fog row the live weather calls for, or nil
function F.current()
  local force = os.getenv and tonumber(os.getenv("G4FOG") or "")
  if force then return F.WEATHERS[force] end
  if not platinum() then return nil end
  -- FOG (14), steady or thinning after Defog (src/world/Gen4FogWeather.lua)
  local FW = package.loaded["src.world.Gen4FogWeather"]
  local fogRow = FW and FW.depthRow and FW.depthRow()
  if fogRow then return fogRow end
  local G = game()
  local raw = G and G.save and tonumber(G.save.gen4WeatherActive)
  return raw and F.WEATHERS[raw] or nil
end

-- begin(ground, mode, a, b): fog the draws that follow.  `mode` says how the
-- pass's depth turns back into eye distance:
--   1  linear:       D = a + ndcZ * b          (the live field pass)
--   2  perspective:  near a, far b             (the free camera)
--   3  orthographic: near a, far b
function F.begin(ground, mode, a, b)
  local Gen4Model = require("src.render.Gen4Model")
  local row = F.current()
  local cam = ground and ground.camera
  if not (row and cam) then Gen4Model.depthFog = nil; return end
  local near, far = tonumber(cam.near) or 150, tonumber(cam.far) or 900
  Gen4Model.depthFog = {
    a = { mode, a, b, cam.projection == "orthographic" and 1 or 0 },
    b = { near, far, row.offset, 1024 / 2 ^ row.slope },
    c = { row.rgb[1] / 31, row.rgb[2] / 31, row.rgb[3] / 31 },
    shift = row.shift,
  }
end

function F.finish()
  local Gen4Model = package.loaded["src.render.Gen4Model"]
  if Gen4Model then Gen4Model.depthFog = nil end
end

return F
