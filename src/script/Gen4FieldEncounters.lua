-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HGSS HEADBUTT AND ROCK SMASH ENCOUNTERS, through the cartridge's regular
-- generator (pokeheartgold src/field/encounter_check.c):
--
--   FieldSystem_PerformHeadbuttEncounterCheck / ..RockSmashEncounterCheck
--   -> FieldSystem_GenerateRegularEncounter(ENCOUNTER_TYPE_HEADBUTT / _ROCK_SMASH)
--
-- which, like every other kind, lets the lead's MAGNET PULL / STATIC force a
-- Steel / Electric slot (`!a && !b`, both kept in HGSS), rolls the level in
-- the slot's range with HUSTLE / VITAL SPIRIT / PRESSURE taking the top half
-- the time, and lets KEEN EYE / INTIMIDATE turn away anything 5 levels below
-- a lead above level 5. REPEL DOES NOT APPLY: `isRepel` is cleared by
-- EncounterGenState_Init and set only by FieldSystem_PerformLandOrSurf-
-- EncounterCheck. These had been rolled bare and checked against Repel.
--
-- Rock Smash's rate also passes ApplyAbilityEffectToEncounterRate(FALSE):
-- Arena Trap / No Guard / Illuminate double it, White Smoke / Quick Feet /
-- Stench halve it, Snow Cloak halves it in snow; capped at 100.

local M = {}

M.HEADBUTT_ODDS = { 50, 15, 15, 10, 5, 5 }     -- EncounterSlot_WildMonSlotRoll_Headbutt
M.ROCK_SMASH_ODDS = { 80, 20 }                 -- EncounterSlot_WildMonSlotRoll_RockSmash

local function data(ctx) return ctx and ctx.game and ctx.game.data end

local function generate(ctx, slots, odds)
  if type(slots) ~= "table" or #slots == 0 then return nil end
  local list = {}
  for i = 1, #odds do
    local s = slots[i]
    if not s then break end
    list[i] = s
  end
  local WildLead = require("src.world.Gen4WildLead")
  local enc = WildLead.choose(data(ctx), ctx.save, list, "rod", odds)
  if not (enc and (tonumber(enc.species) or 0) > 0) then return nil end
  return enc
end

function M.headbutt(ctx, slots)
  return generate(ctx, slots, M.HEADBUTT_ODDS)
end

function M.rockSmash(ctx, slots)
  return generate(ctx, slots, M.ROCK_SMASH_ODDS)
end

local DOUBLE = { ARENA_TRAP = true, NO_GUARD = true, ILLUMINATE = true }
local HALVE = { WHITE_SMOKE = true, QUICK_FEET = true, STENCH = true }

function M.rockSmashRate(ctx, rate, weather)
  rate = tonumber(rate) or 0
  if rate <= 0 then return 0 end
  local lead = require("src.world.Gen4WildLead").lead(data(ctx), ctx and ctx.save)
  if lead.egg then return rate end
  local a = lead.ability or ""
  if DOUBLE[a] then rate = rate * 2
  elseif a == "SNOW_CLOAK" then
    if weather == "snow" then rate = math.floor(rate / 2) end
  elseif HALVE[a] then rate = math.floor(rate / 2) end
  if rate > 100 then rate = 100 end
  return rate
end

return M
