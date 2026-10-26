-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S SPECIAL MARTS (scrcmd_mart.c ScrCmd_SpecialMartBuy).
--
-- `SpecialMartBuy VAR_SPECIAL_x8004` (std_special_mart) is every counter that
-- is not the badge-tiered Poke Mart: Goldenrod's department store floors, the
-- Underground's herb shop, Blackthorn's mart, Mahogany's souvenir shop (28,
-- the shady salesman; 29, the old woman after the hideout)... It indexes
-- `_0210FA3C`, thirty pointers to 0xFFFF-terminated item lists in the ARM9.
-- Platinum's `Gen4Mart.specialties` looks for Sinnoh's twenty lists and its
-- checks (Veilstone's stock) never match here, so the HGSS cache carried no
-- `martSpecialties` at all and each of those clerks greeted the player and
-- opened nothing ("stock is absent for this counter").
--
-- FOUND BY SHAPE, as Gen4Mart finds its tables: a pointer whose list is Air
-- Mail, Heal Ball (146, 14) followed by one to Tunnel Mail, Heal Ball, Net
-- Ball (141, 14, 6) -- lists 0 and 1 -- and then every one of the thirty
-- validated. In the USA HeartGold ARM9 this is offset 0x10FA3C, exactly the
-- symbol's address (RAM base 0x02000000).

local M = {}

M.COUNT = 30

local function u16(bytes, at)
  local a, b = bytes:byte(at, at + 1)
  return b and a + b * 256
end

local function u32(bytes, at)
  local a, b = u16(bytes, at), u16(bytes, at + 2)
  return a and b and a + b * 65536
end

-- the item list a pointer names, or nil when it is not one
local function list(bytes, ramBase, p)
  local at = p and p - ramBase + 1
  if not at or at < 1 or at > #bytes or at % 2 ~= 1 then return nil end
  local out = {}
  for i = 0, 63 do
    local item = u16(bytes, at + i * 2)
    if item == 0xFFFF then return #out > 0 and out or nil end
    if not item or item < 1 or item > 536 then return nil end
    out[#out + 1] = item
  end
  return nil
end

-- find(arm9, ramBase) -> { [0] = { item, ... }, ..., [29] = {...} } or nil, why
function M.find(bytes, ramBase)
  if type(bytes) ~= "string" then return nil, "no arm9" end
  ramBase = ramBase or 0x02000000
  local found, hits = nil, 0
  for at = 1, #bytes - M.COUNT * 4, 4 do
    local first = list(bytes, ramBase, u32(bytes, at))
    if first and #first == 2 and first[1] == 146 and first[2] == 14 then
      local second = list(bytes, ramBase, u32(bytes, at + 4))
      if second and #second == 3 and second[1] == 141 and second[2] == 14 and second[3] == 6 then
        local lists, valid = {}, true
        for id = 0, M.COUNT - 1 do
          lists[id] = list(bytes, ramBase, u32(bytes, at + id * 4))
          if not lists[id] then valid = false break end
        end
        -- independent checks: 7 is the TM counter opening with TM70 (397),
        -- 8 the herb shop (Heal Powder 36 first), 28 Mahogany's three
        -- (TinyMushroom 86, Poke Ball 4, Potion 17)
        if valid and lists[7][1] == 397 and lists[8][1] == 36
           and lists[28][1] == 86 and lists[28][2] == 4 and lists[28][3] == 17 then
          found, hits = lists, hits + 1
        end
      end
    end
  end
  if hits == 1 then return found end
  return nil, "hgss special mart table matches: " .. hits
end

return M
