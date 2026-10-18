-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SNOW, out of /data/weather_sys.narc (NARC_INDEX_DATA__WEATHER_SYS).
--
-- Reported from play: "the snow animation/weather isnt properly rendering like
-- it should in the rom for platinum".  The art the weather task draws with
-- (pokeplatinum src/overlay005/ov5_021D5EB8.c):
--
--   * OAM set 3 (SNOWING) and 9 (BLIZZARD): char 28, palette 21 -- four
--     8x8 flakes, anim 26 showing tile 3 - f for frame f
--   * OAM set 1 (HEAVY_SNOW): char 20, palette 21 -- tile f for frame f
--   * BG set 0 (BLIZZARD's layer, Unk_ov5_021F8D90[0]): palette 21, char 36,
--     screen 38 -- a 128x128 snow texture, repeated 2x2 on the 256x256 BG2
--
-- Each flake set is written as a 32x8 strip of its four tiles, in tile order.

local Gen4Graphics = require("src.import.Gen4Graphics")

local W = {}

W.PATH = "/data/weather_sys.narc"
W.PALETTE, W.SNOW_CHAR, W.HEAVY_CHAR = 21, 28, 20
W.BG_CHAR, W.BG_SCREEN = 36, 38
W.ASH_PALETTE, W.ASH_CHAR, W.ASH_BG_CHAR, W.ASH_BG_SCREEN = 42, 41, 44, 43

local function member(arc, i)
  local b = arc and arc:get(i)
  if b and Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
end

local function strip(sheet, palette)
  local cells = {}
  for k = 0, 3 do cells[#cells + 1] = { tile = k, palette = 0 } end
  return Gen4Graphics.compose({ width = 32, height = 8, cells = cells }, sheet, palette)
end

-- extract(ex) -> the gen4_weather_sys record, or nil, why
function W.extract(ex)
  local arc = ex:archiveAt(W.PATH)
  if not arc then return nil, W.PATH .. " missing" end
  local palette = Gen4Graphics.palette(member(arc, W.PALETTE))
  if not palette then return nil, "palette member 21 did not decode" end
  local out = { source = "ROM:weather_sys.narc (overlay 5 weather task, OAM sets 1/3/9, BG set 0)" }
  local snow = strip(Gen4Graphics.tiles(member(arc, W.SNOW_CHAR)), palette)
  out.snowFlakes = snow and ex:saveImage("weather/snow_flakes", snow) or nil
  local heavy = strip(Gen4Graphics.tiles(member(arc, W.HEAVY_CHAR)), palette)
  out.heavyFlakes = heavy and ex:saveImage("weather/heavy_snow_flakes", heavy) or nil
  local map = Gen4Graphics.tilemap(member(arc, W.BG_SCREEN))
  if map then
    -- Bg_ChangeTilemapRectPalette(..., 6): every entry on the one palette,
    -- whose first sixteen colours are palette member 21's
    for _, c in ipairs(map.cells or {}) do c.palette = 0 end
    local bg = Gen4Graphics.compose(map, Gen4Graphics.tiles(member(arc, W.BG_CHAR)), palette)
    out.blizzardLayer = bg and ex:saveImage("weather/blizzard_layer", bg) or nil
  end
  -- SLOW_ASHFALL (9, ov5_021DA244): OAM set 6 -- char 41, palette 42, anim
  -- 39 showing tile f for frame f -- and BG set 3, Unk_ov5_021F8D90[3]:
  -- palette 42, char 44, screen 43, the drifting ash on BG2
  local ashPal = Gen4Graphics.palette(member(arc, W.ASH_PALETTE))
  if ashPal then
    local ash = strip(Gen4Graphics.tiles(member(arc, W.ASH_CHAR)), ashPal)
    out.ashFlakes = ash and ex:saveImage("weather/ash_flakes", ash) or nil
    local amap = Gen4Graphics.tilemap(member(arc, W.ASH_BG_SCREEN))
    if amap then
      for _, c in ipairs(amap.cells or {}) do c.palette = 0 end
      local bg = Gen4Graphics.compose(amap, Gen4Graphics.tiles(member(arc, W.ASH_BG_CHAR)), ashPal)
      out.ashLayer = bg and ex:saveImage("weather/ash_layer", bg) or nil
    end
  end
  return out
end

return W
