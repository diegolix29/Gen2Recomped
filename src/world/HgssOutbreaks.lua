-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S MASS OUTBREAKS, and the night fishing swap that
-- runs just before them.
--
-- pokeheartgold, piece by piece:
--
--   * ON: `EnableMassOutbreaks` (ScrCmd_EnableMassOutbreaks) sets the roamer
--     save's `outbreak` -- Oak's port scene and the Pokeathlon's, once.
--   * WHERE: `sSwarmMapLUT[rand % 20]` (src/unk_02097F6C.c), a map and a kind
--     -- 0 land, 1 surf, 2 fish -- with rand the roamer save's second word,
--     which `FieldSystem_HandleDailyEvents` reloads every day from the
--     record-mixed group RNG. The port keeps that RNG already, advanced once a
--     day for Platinum's swarms (`Gen4Swarms`, save.gen4Swarm.daily), and the
--     outbreak reads the same word; Platinum's own swarm stays off on these
--     cartridges because only Platinum's `enableswarms` turns it on.
--   * WHAT (src/field/encounter_check.c): the area's landSwarm into land slots
--     0 and 1; surfSwarm into surf slot 0; fishSwarm into the Old Rod's slot 2,
--     the Good Rod's 0, 2, 3 and all five of the Super Rod's.
--   * NIGHT FISHING first (EncSlotArray_Update_NightFishing): from 20:00 to
--     3:59 (RTC NITE / LATE) the Good Rod's slot 3 and the Super Rod's slot 1
--     are the area's nightFish.
--
-- Slots here are 1-based: the cartridge's slot n is index n + 1.

local HgssOutbreaks = {}

HgssOutbreaks.MAPS = {
  { "R01", "land" }, { "R03", "land" }, { "R09", "land" }, { "R12", "fish" },
  { "R13", "land" }, { "W19", "surf" }, { "R32", "fish" }, { "R25", "land" },
  { "R27", "surf" }, { "R34", "land" }, { "R35", "land" }, { "R38", "land" },
  { "R44", "fish" }, { "R45", "land" }, { "R47", "land" },
  { "D38R0101", "land" },   -- Mt. Mortar 1F entrance
  { "D42R0102", "land" },   -- Dark Cave, the Route 31 side
  { "D46R0101", "land" },   -- Viridian Forest
  { "T06", "surf" },        -- Vermilion City
  { "T22", "fish" },        -- Violet City
}

HgssOutbreaks.FISH_SLOTS = { oldRod = { 3 }, goodRod = { 1, 3, 4 }, superRod = { 1, 2, 3, 4, 5 } }
HgssOutbreaks.NIGHT_SLOT = { goodRod = 4, superRod = 2 }

function HgssOutbreaks.enable(save)
  if type(save) == "table" then save.hgssOutbreak = true end
end

function HgssOutbreaks.active(save)
  return type(save) == "table" and save.hgssOutbreak == true
end

-- today's entry of the table: { mapCode, kind }
function HgssOutbreaks.today(save)
  local Gen4Swarms = require("src.world.Gen4Swarms")
  pcall(Gen4Swarms.header, save)   -- creates the daily record on a new save
  local s = type(save) == "table" and save.gen4Swarm
  local daily = s and tonumber(s.daily) or 0
  return HgssOutbreaks.MAPS[(daily % #HgssOutbreaks.MAPS) + 1]
end

-- the kind of outbreak on this map today, or nil
function HgssOutbreaks.kindHere(save, mapId)
  if not HgssOutbreaks.active(save) then return nil end
  local entry = HgssOutbreaks.today(save)
  if entry and entry[1] == mapId then return entry[2] end
  return nil
end

-- RTC_TIMEOFDAY_NITE / LATE by the hour (GF_RTC_GetTimeOfDayByHour)
function HgssOutbreaks.isNight(hour)
  hour = tonumber(hour) or tonumber(os.date("%H")) or 12
  return hour >= 20 or hour < 4
end

local function copySlots(slots)
  local out = {}
  for i, slot in ipairs(slots or {}) do
    local c = {}
    for k, v in pairs(slot) do c[k] = v end
    out[i] = c
  end
  return out
end

-- The substituted slot arrays for one area, or nil where nothing changes.
-- `area.hgssSwarm` is { land, surf, fish, nightFish } (Gen4Encounters).
-- `grass` is the land table after the time-of-day swap (EncSlotArray_Init_Land
-- picks the hour's list first); it defaults to the area's own.
function HgssOutbreaks.apply(area, save, mapId, hour, grass)
  local sw = area and area.hgssSwarm
  if type(sw) ~= "table" then return nil end
  local kind = HgssOutbreaks.kindHere(save, mapId)
  local night = HgssOutbreaks.isNight(hour) and (tonumber(sw.nightFish) or 0) > 0
  if not kind and not night then return nil end
  local out = {}
  local function species(v) v = tonumber(v) return v and v > 0 and v or nil end
  grass = grass or area.grass
  if kind == "land" and species(sw.land) and type(grass) == "table" then
    out.grass = copySlots(grass)
    for n = 1, 2 do if out.grass[n] then out.grass[n].species = species(sw.land) end end
  end
  if kind == "surf" and species(sw.surf) and area.surf and area.surf.slots then
    out.surf = copySlots(area.surf.slots)
    if out.surf[1] then out.surf[1].species = species(sw.surf) end
  end
  for rod, idxs in pairs(HgssOutbreaks.FISH_SLOTS) do
    local base = area[rod] and area[rod].slots
    if base then
      local slots
      local ns = HgssOutbreaks.NIGHT_SLOT[rod]
      if night and ns and base[ns] then
        slots = slots or copySlots(base)
        slots[ns].species = species(sw.nightFish)
      end
      if kind == "fish" and species(sw.fish) then
        slots = slots or copySlots(base)
        for _, i in ipairs(idxs) do if slots[i] then slots[i].species = species(sw.fish) end end
      end
      out[rod] = slots
    end
  end
  return out
end

-- A key for the encounter-view cache.
function HgssOutbreaks.key(area, save, mapId, hour)
  if type(area) ~= "table" or type(area.hgssSwarm) ~= "table" then return "" end
  return ("|ob:%s:%s"):format(tostring(HgssOutbreaks.kindHere(save, mapId) or "-"),
                              HgssOutbreaks.isNight(hour) and "n" or "d")
end

return HgssOutbreaks
