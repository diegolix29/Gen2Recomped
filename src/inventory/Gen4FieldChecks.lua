-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- SMALL GEN 4 FIELD-USE REFUSALS the bag and party menu share.
--
--   * THE ROCKET DISGUISE (HGSS). Save_VarsFlags_CheckRocketCostumeFlag
--     answers FIELD_MOVE_RESPONSE_NOT_NOW in FieldMove_CheckFly / _Surf /
--     _RockClimb / _Teleport / _Dig (pokeheartgold src/field_move.c), after
--     the badge, place and partner checks; the party menu prints
--     msg_0300_00181 for it (party_menu_list_items.c). The bag's rods,
--     Bicycle and Escape Rope give ITEMUSEERROR_NOTNOW, msg_0010_00119.
--   * THE RODS. Platinum's CanUseFishingRod refuses with a partner
--     (ITEM_USE_CANNOT_USE_WITH_PARTNER, bag line 111); HGSS's
--     ItemCheckUseFunc_FishingRod with an NPC follower (ITEMUSEERROR_
--     NOFOLLOWER, msg_0010_00118) and in the disguise (_NOTNOW, 00119).

local M = {}

M.HGSS_PARTY_BANK, M.HGSS_PARTY_NOT_NOW = 300, 181
M.HGSS_BAG_BANK, M.HGSS_BAG_FOLLOWER, M.HGSS_BAG_NOT_NOW = 10, 118, 119
M.PT_BAG_PARTNER = 111

local function isHgss(data)
  local v = data and data.gen4_version
  return v and v.family == "hgss" or false
end
M.isHgss = isHgss

local function game() return package.loaded["src.core.Game"] end

local function line(data, bank, index, fallback)
  local G = game()
  local ok, s = pcall(function()
    return require("src.import.Gen4Text").resolve(data, bank, index, G)
  end)
  if ok and type(s) == "string" and s:find("%S") then return s end
  return fallback
end

-- the disguise flag the field checks read (SetRocketCostumeFlag's)
function M.inCostume(data, save)
  return isHgss(data) and save ~= nil
    and (save.hgssRocketCostumeFlag or save.hgssRocketCostume) and true or false
end

function M.partyNotNow(data)
  return line(data, M.HGSS_PARTY_BANK, M.HGSS_PARTY_NOT_NOW, "You can't do that now!")
end

-- the refusal line for a rod, or nil when it may be cast
function M.rodRefusal(data, save)
  if not (data and data.isGen4Cache) then return nil end
  local okF, F = pcall(require, "src.world.Gen4Follower")
  local partner = okF and F.hasPartner and F.hasPartner(save)
  if isHgss(data) then
    if partner then
      return line(data, M.HGSS_BAG_BANK, M.HGSS_BAG_FOLLOWER, "Can't be used when you have someone with you!")
    end
    if M.inCostume(data, save) then
      return line(data, M.HGSS_BAG_BANK, M.HGSS_BAG_NOT_NOW, "You can't be doing that now!")
    end
    return nil
  end
  if partner then
    return line(data, 7, M.PT_BAG_PARTNER, "It can't be used when you have someone with you.")
  end
  return nil
end

return M
