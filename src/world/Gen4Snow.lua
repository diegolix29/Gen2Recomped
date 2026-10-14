-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHICH SNOW, AND WHEN: the live weather into Gen4SnowView.
--
-- The field's weather manager (ov5_021D5F24 / ov5_021D5F7C): a map that loads
-- with snow starts it already in full swing (cmd 3); a weather that changes
-- while you stand there fades the old one out and the new one in (cmd 5, then
-- cmd 2).  Platinum only -- HeartGold and SoulSilver's weather is their own.

local M = {}

-- OVERWORLD_WEATHER_* ids, and the unnamed 21 that is heavy snow with a
-- different fog offset (ov5_021D823C)
M.IDS = { SNOWING = 5, HEAVY_SNOW = 6, BLIZZARD = 7 }
M.UNNAMED_HEAVY = 21
M.ASHFALL = 9

local function Game() return package.loaded["src.core.Game"] end

local function platinum()
  local G = Game()
  local data = G and G.data
  local v = data and data.gen4_version
  local GV = require("src.core.GameVersion")
  return data and data.isGen4Cache and not GV.isGen5() and not (v and v.family == "hgss")
end

-- the snow weather the save says is falling, as 5, 6 or 7 (or nil)
function M.wanted()
  if not platinum() then return nil end
  -- G4SNOW=5|6|7: a harness switch, that snow whatever the map says
  local force = os.getenv and tonumber(os.getenv("G4SNOW") or "")
  if force then return force end
  local G = Game()
  local raw = G and G.save and G.save.gen4WeatherActive
  if raw == nil then return nil end
  local W = require("src.import.Gen4Weather")
  local _, name = W.lookFor(raw)
  if name and M.IDS[name] then return M.IDS[name] end
  if tonumber(raw) == M.UNNAMED_HEAVY then return 6 end
  -- SLOW_ASHFALL, Stark Mountain's ash (Gen4SnowView's weather 9)
  if tonumber(raw) == M.ASHFALL then return M.ASHFALL end
  return nil
end

-- every engine frame; the weather ticks on the field's 30
function M.update(ow)
  if not platinum() then return end
  local V = require("src.render.Gen4SnowView")
  local want = M.wanted()
  local mapId = ow.map and ow.map.id
  local fresh = ow.snowMap ~= mapId
  ow.snowMap = mapId
  local cur = V.state
  if want and (not cur or (cur.id ~= want and not cur.stopping)) then
    if fresh or not cur then
      V.start(want, fresh)
    else
      -- a change of snow mid-scene: the old one fades out first
      V.stop()
    end
  elseif cur and not want and fresh then
    -- a map without it: the cartridge unloads the weather with the map
    V.state = nil
  elseif cur and not want then
    V.stop()
  end
  ow.snowHalf = not ow.snowHalf
  if not ow.snowHalf then return end
  -- the camera target's movement since the last tick, in world units
  local p = ow.player
  local px, py = p and p.px or 0, p and p.py or 0
  local last = ow.snowCam
  local dx, dy = 0, 0
  if last and not fresh then dx, dy = px - last[1], py - last[2] end
  ow.snowCam = { px, py }
  V.tick(dx, dy)
  if os.getenv and os.getenv("SNOWDEBUG") then
    M.n = (M.n or 0) + 1
    local st = V.state
    if M.n % 50 == 0 and st then
      print(("[snow] tick %d weather %d state %d flakes %d layer %s count %s interval %s"):format(M.n, st.id,
        st.state, #st.list, tostring(st.layer), tostring(st.sp and st.sp.count), tostring(st.sp and st.sp.interval)))
    end
  end
end

return M
