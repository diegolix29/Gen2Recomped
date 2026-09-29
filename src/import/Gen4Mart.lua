-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT THE POKE MART SELLS, AND WHY IT IS NOT IN AN ARCHIVE.
--
-- `pokemartcommon` is the clerk in every ordinary Poke Mart in Sinnoh -- 19
-- sites -- and until now it was a `pending()` no-op: the clerk said hello and
-- sold nothing.  `ScrCmd_PokeMartCommon` (scrcmd_shop.c) counts the player's
-- badges, turns that into a TIER, and hands `Shop_Start` every row of
-- `PokeMartCommonItems` whose own `requiredBadges` is at or below it.
--
-- That table is a C array, so it is in the ARM9 binary rather than in a NARC,
-- which is why nothing found it before.  It is 19 records of
-- `{ u16 itemID, u16 requiredBadges }` -- 76 bytes -- and searching the WHOLE
-- 128 MB cartridge for that byte sequence returns **exactly one hit, at ROM
-- offset 0xEFAFC**, which is ARM9 offset 0xEBAFC (RAM 0x020EBAFC).  One hit in
-- 128 MB is not a coincidence, and it is what turns "pret prints this table"
-- into "this cartridge contains this table".
--
-- FOUND BY SHAPE RATHER THAN BY OFFSET, the same way `Gen4TypeChart` finds its
-- own table: the first three rows are the three Poke Balls and their tiers
-- (4/1, 3/3, 2/4), twelve bytes that appear nowhere else, and everything after
-- the anchor is validated rather than trusted.  A hardcoded offset would be a
-- silent wrong answer on any other build; a shape that fails to match is a
-- loud one.

local Gen4Mart = {}

Gen4Mart.ROWS = 19
Gen4Mart.ROW_BYTES = 4
Gen4Mart.BYTES = Gen4Mart.ROWS * Gen4Mart.ROW_BYTES

-- Poke Ball (item 4, from badge tier 1), Great Ball (3, tier 3), Ultra Ball
-- (2, tier 4).  Little-endian u16 pairs.
Gen4Mart.ANCHOR = "\4\0\1\0\3\0\3\0\2\0\4\0"

-- The highest tier any row asks for.  `ScrCmd_PokeMartCommon`'s switch tops out
-- at 6, and the table's own rows never exceed it -- which is the cross-check
-- that says the two were read consistently.
Gen4Mart.MAX_TIER = 6

local function u16(s, at)
  local a, b = s:byte(at), s:byte(at + 1)
  if not b then return nil end
  return a + b * 256
end

-- parse(bytes, at) -> { { item, badges }, ... } or nil plus a reason.
-- `at` is one-based.
function Gen4Mart.parse(bytes, at)
  if type(bytes) ~= "string" or type(at) ~= "number" then
    return nil, "bad arguments"
  end
  if at < 1 or at + Gen4Mart.BYTES - 1 > #bytes then return nil, "out of range" end
  local rows = {}
  for i = 0, Gen4Mart.ROWS - 1 do
    local p = at + i * Gen4Mart.ROW_BYTES
    local item, badges = u16(bytes, p), u16(bytes, p + 2)
    if not badges then return nil, "truncated" end
    -- A tier outside 1..6 is not a mart row, and neither is item 0.  Both are
    -- cheap to check and both would turn a wrong anchor into plausible stock.
    if item == 0 then return nil, ("row %d has no item"):format(i) end
    if badges < 1 or badges > Gen4Mart.MAX_TIER then
      return nil, ("row %d wants tier %d"):format(i, badges)
    end
    rows[i + 1] = { item = item, badges = badges }
  end
  return rows
end

-- Where the table is in a binary, or nil.  Reports a SECOND match rather than
-- taking the first: the anchor is unique in this cartridge, and if it ever is
-- not, that is something to be told about.
function Gen4Mart.find(bytes)
  if type(bytes) ~= "string" then return nil end
  local at, first, hits = 1, nil, 0
  while true do
    local found = bytes:find(Gen4Mart.ANCHOR, at, true)
    if not found then break end
    if Gen4Mart.parse(bytes, found) then
      hits = hits + 1
      first = first or found
    end
    at = found + 1
  end
  return first, hits
end

-- THE TIER A BADGE COUNT BUYS, transcribed from `ScrCmd_PokeMartCommon`'s own
-- switch.  Not a formula: the cartridge pairs badges up (1 and 2 both buy tier
-- 2, 3 and 4 both buy 3) and then stops pairing at seven, so `(n + 3) / 2` and
-- every other tidy arithmetic gets the last two wrong.
local TIER = { [0] = 1, 2, 2, 3, 3, 4, 4, 5, 6 }

function Gen4Mart.tierFor(badgeCount)
  local n = tonumber(badgeCount) or 0
  -- `default: requiredBadges = 1` -- a count the switch does not name buys the
  -- starting stock, not the best.
  return TIER[n] or 1
end

-- The stock list, in the table's own order, for a player with this many badges.
function Gen4Mart.stock(rows, badgeCount)
  local tier = Gen4Mart.tierFor(badgeCount)
  local out = {}
  for _, row in ipairs(rows or {}) do
    if tier >= row.badges then out[#out + 1] = row.item end
  end
  return out
end

return Gen4Mart
