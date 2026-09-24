-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) item records.
--
-- /itemtool/itemdata/pl_item_data.narc: 446 members of 34 bytes.  The first 14 bytes
-- are pokeplatinum's ItemData; the remaining 20 are the party-use parameter
-- block, which only matters for items a Pokemon can be given and is left as
-- raw bytes here rather than half-decoded.
--
--   00 u16 price          07 u8  naturalGiftPower   0A u8 fieldUseFunc
--   02 u8  holdEffect     08 u16 packed bitfield    0B u8 battleUseCategory
--   03 u8  effectParam           (see below)        0C u8 partyUse
--   04 u8  pluckEffect                              0D u8 padding
--   05 u8  flingEffect                              0E .. partyUseParam
--   06 u8  flingPower
--
-- The u16 at 08 packs six fields, low bits first: naturalGiftType (5),
-- preventToss (1), canRegister (1), fieldPocket (4), battlePocket (5).
-- Bit order matters and is not guessable from the struct alone -- a C
-- bitfield's layout is implementation-defined in general, but the ARM ABI
-- the DS uses allocates from the least significant bit up, which is what is
-- assumed here and what makes the pocket numbers come out in range.
--
-- Verified against the published tables: Master Ball 0, Ultra Ball 1200,
-- Poke Ball 200, Potion 300, HP Up 9800.
--
-- A MEMBER INDEX IS NOT AN ITEM ID, and this file used to say it was.
--
-- The name bank has **468** entries and the data archive has **446**.  The
-- difference is the twenty-two unused ids 113..134, which the names keep as
-- "???" placeholders and the data archive simply does not have.  So member i
-- is item i up to 112 and item i + 22 after that, and reading it the easy way
-- gave every item from Adamant Orb onward -- 333 of the 446 -- the price,
-- pocket, hold effect, fling power and party-use block of an item twenty-two
-- places further on.
--
-- IT LOOKED RIGHT, which is why it survived.  Master Ball, Ultra Ball, Potion
-- and HP Up are all below the gap, so every spot check in the note above
-- passed; the balls, the medicines and the battle items came out in the right
-- pockets for the same reason.  What gave it away was asking a question that
-- covers the WHOLE table rather than the start of it: group every item by the
-- pocket its record claims and print the id runs.  The eight runs came out
-- exactly the right SIZES -- 16 balls, 38 medicines, 13 battle items, 12 mail,
-- 64 berries, 100 TMs and HMs, 40 key items -- and sitting twenty-two ids too
-- low from the mail onward.  Eight independent counts agreeing while eight
-- independent positions disagree is one offset, not eight coincidences.
--
-- The check now runs as `Gen4Items.checkPockets`, against the cartridge's own
-- id ranges rather than against itself.

local Gen4Items = {}

Gen4Items.RECORD_BYTES = 34

-- Bank 392 in /msgdata/pl_msg.narc, indexed by item id: entry 1 is "Master
-- Ball".  Found by looking rather than assumed.
Gen4Items.NAME_BANK = 392
Gen4Items.DESCRIPTION_BANK = 391

local floor = math.floor

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end

function Gen4Items.parse(record)
  if type(record) ~= "string" or #record < 14 then
    return nil, ("item record is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1, Gen4Items.RECORD_BYTES)
  end
  local packed = u16(record, 8)
  return {
    price = u16(record, 0),
    holdEffect = u8(record, 2),
    effectParam = u8(record, 3),
    pluckEffect = u8(record, 4),
    flingEffect = u8(record, 5),
    flingPower = u8(record, 6),
    naturalGiftPower = u8(record, 7),
    naturalGiftType = packed % 32,
    preventToss = floor(packed / 32) % 2 == 1,
    canRegister = floor(packed / 64) % 2 == 1,
    fieldPocket = floor(packed / 128) % 16,
    battlePocket = floor(packed / 2048) % 32,
    fieldUseFunc = u8(record, 10),
    battleUseCategory = u8(record, 11),
    partyUse = u8(record, 12),
    partyUseParam = record:sub(15, 34),
  }
end

-- The gap in the id space that the data archive skips and the names keep.
Gen4Items.GAP_FIRST = 113
Gen4Items.GAP_SIZE = 22

-- itemId(member) -> the id this data record belongs to.
function Gen4Items.itemId(member)
  if member < Gen4Items.GAP_FIRST then return member end
  return member + Gen4Items.GAP_SIZE
end

-- THE POCKETS, as the cartridge's own id ranges.  Not used to decode anything
-- -- `fieldPocket` is read from the record either way -- so this is a second
-- table to disagree with rather than the same one twice.
Gen4Items.POCKETS = {
  [0] = "ITEMS", [1] = "MEDICINE", [2] = "POKE_BALLS", [3] = "TM_HM",
  [4] = "BERRIES", [5] = "MAIL", [6] = "BATTLE_ITEMS", [7] = "KEY_ITEMS",
}

Gen4Items.POCKET_RANGES = {
  { first = 1,   last = 16,  pocket = 2 },   -- Master Ball .. Cherish Ball
  { first = 17,  last = 54,  pocket = 1 },   -- Potion .. Old Gateau
  { first = 55,  last = 67,  pocket = 6 },   -- Guard Spec. .. Red Flute
  { first = 137, last = 148, pocket = 5 },   -- Grass Mail .. Brick Mail
  { first = 149, last = 212, pocket = 4 },   -- Cheri Berry .. Rowap Berry
  { first = 328, last = 427, pocket = 3 },   -- TM01 .. HM08
  { first = 428, last = 467, pocket = 7 },   -- Explorer Kit .. Old Rod
}

-- checkPockets(items) -> ok, total, failures
--
-- Every item in a named range must claim that range's pocket, and every item
-- outside all of them must claim ITEMS.  Under the old member-is-the-id
-- reading this fails 333 times; under the mapping above it fails none.
function Gen4Items.checkPockets(items)
  local wanted = {}
  for _, range in ipairs(Gen4Items.POCKET_RANGES) do
    for id = range.first, range.last do wanted[id] = range.pocket end
  end
  local ok, total, failures = 0, 0, {}
  for id, item in pairs(items or {}) do
    if id > 0 then
      total = total + 1
      local want = wanted[id] or 0
      if item.fieldPocket == want then
        ok = ok + 1
      elseif #failures < 8 then
        failures[#failures + 1] = ("%d %q: pocket %s, expected %s")
          :format(id, tostring(item.name), tostring(item.fieldPocket), tostring(want))
      end
    end
  end
  return ok, total, failures
end

function Gen4Items.all(archive, nameBank, Gen4Text)
  local out = {}
  for member = 0, archive.count - 1 do
    local it = Gen4Items.parse(archive:get(member))
    if it then
      local id = Gen4Items.itemId(member)
      it.id = id
      it.pocket = Gen4Items.POCKETS[it.fieldPocket]
      if nameBank and Gen4Text and id < nameBank.count then
        it.name = Gen4Text.render(Gen4Text.codes(nameBank, id))
      end
      out[id] = it
    end
  end
  return out
end

return Gen4Items
