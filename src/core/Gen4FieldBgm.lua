-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- PLATINUM / HGSS: WHICH SONG A MAP PLAYS WHILE RIDING OR SURFING.
--
-- FieldBGM_GetEffective (pokeheartgold src/field_bgm.c; pokeplatinum
-- src/field_bgm.c):
--
--   1. surfing -> SEQ_GS_NAMINORI / SEQ_NAMINORI, on every map. HGSS skips
--      it while flag 0x99A is set (CheckFlag99A); Platinum skips it in the
--      Distortion World (headers 573..583, the CanUseFishingRod list).
--   2. otherwise the map header's day / night song,
--   3. replaced by the saved override when one is stored -- which is what
--      mounting the Bicycle does (FieldBGM_SetOverride(SEQ_GS_BICYCLE) in
--      HGSS field_use_item.c / scrcmd SetBikeState; MountOrUnmountBicycle
--      in Platinum), so the bike song plays in caves and every other
--      bike-allowed map, not only where Fly is allowed.
--
-- Black / White keep their own outdoor-song rule (Gen5ItemUse marks it from
-- the zone flags), so this answers nil there and on every other generation.

local M = {}

M.HGSS_NO_SURF_FLAG = "FLAG_G4_099A"

local function game() return package.loaded["src.core.Game"] end

function M.applies(data)
  if not (data and data.isGen4Cache) then return false end
  local okV, GV = pcall(require, "src.core.GameVersion")
  if okV and GV.isGen5 and GV.isGen5() then return false end
  return true
end

local function isHgss(data)
  local v = data and data.gen4_version
  return v and v.family == "hgss" or false
end

function M.surfSongAllowed(data)
  local G = game()
  if isHgss(data) then
    local flags = G and G.save and G.save.flags
    return not (flags and flags[M.HGSS_NO_SURF_FLAG])
  end
  local def = G and G.overworld and G.overworld.map and G.overworld.map.def
  local header = def and tonumber(def.header)
  if header and require("src.world.Gen4Fishing").NO_FISHING[header] then return false end
  return true
end

-- (song, true) when this rule applies; (nil, false) when it does not
function M.effective(data, song, onBike, surfing, special, songDef)
  if not M.applies(data) then return nil, false end
  if surfing and M.surfSongAllowed(data) then
    local surf = special(data, "surf")
    if surf and songDef(data, surf) then return surf, true end
  end
  if onBike then
    local bike = special(data, "bike")
    if bike and songDef(data, bike) then return bike, true end
  end
  return song, true
end

return M
