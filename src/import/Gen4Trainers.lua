-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) trainers.
--
-- Two archives that must be read together and share an index:
--
--   /poketool/trainer/trdata.narc   928 members of exactly 20 bytes -- the
--                                   header: who they are and how big the party
--   /poketool/trainer/trpoke.narc   928 members, VARIABLE -- the party itself
--
-- Header (20 bytes, pokeplatinum's TrainerHeader):
--   00 u8  monDataType   02 u8  sprite      04 u16 items[4]
--   01 u8  trainerType   03 u8  partySize   12 u32 aiMask   16 u32 battleType
--
-- THE HEADER'S `monDataType` IS WHAT SETS THE PARTY STRIDE, and it must be
-- read from the header rather than inferred by dividing the party file by the
-- party size.  Dividing works for 887 of the 928 and then quietly does not:
-- 39 party files carry trailing padding, so the division lands on 12 or 20
-- where the real stride is 10 or 18, and every mon after the first comes out
-- shifted.  Reading `partySize` entries at the type's own stride and ignoring
-- whatever follows is correct for all 928.
--
--   0  base                 8 bytes:  ivScale, level, species, cbSeal
--   1  with moves          16 bytes:  ivScale, level, species, 4 moves, cbSeal
--   2  with item           10 bytes:  ivScale, level, species, item, cbSeal
--   3  with moves and item 18 bytes:  ivScale, level, species, item,
--                                     4 moves, cbSeal
--
-- `species` also carries the FORM in its high bits (>> 10), so the id is the
-- low 10 bits -- which matters for the handful of trainers using a Wormadam
-- cloak or a Rotom appliance, and silently gives a nonsense species id if the
-- whole halfword is used.
--
-- Validated across the entire archive: 1,878 party members read, with zero
-- species, level, move or item values out of range, and no file too short for
-- the party its header declares.

local Gen4Trainers = {}

Gen4Trainers.HEADER_BYTES = 20

Gen4Trainers.DATA_TYPES = {
  [0] = "base", "withMoves", "withItem", "withMovesAndItem",
}

-- Bytes per party member, by monDataType.
Gen4Trainers.STRIDE = { [0] = 8, [1] = 16, [2] = 10, [3] = 18 }

-- Bank 618 of /msgdata/pl_msg.narc holds trainer names, indexed the same way:
-- it has exactly 928 entries, which is how it was identified. Most of them are
-- bit-packed (see Gen4Text.unpackTrainerName) rather than plain charcodes.
Gen4Trainers.NAME_BANK = 618

local floor = math.floor

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end
local function u32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

function Gen4Trainers.parseHeader(record)
  if type(record) ~= "string" or #record < Gen4Trainers.HEADER_BYTES then
    return nil, ("trainer header is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1, Gen4Trainers.HEADER_BYTES)
  end
  local dataType = u8(record, 0)
  local items = {}
  for i = 0, 3 do items[i + 1] = u16(record, 4 + i * 2) end
  return {
    dataTypeId = dataType,
    dataType = Gen4Trainers.DATA_TYPES[dataType],
    trainerType = u8(record, 1),
    sprite = u8(record, 2),
    partySize = u8(record, 3),
    items = items,
    aiMask = u32(record, 12),
    battleType = u32(record, 16),
  }
end

-- `header` is what parseHeader returned; `party` is the matching trpoke
-- member.  Returns one entry per declared party slot.
function Gen4Trainers.parseParty(header, party)
  if not header or type(party) ~= "string" then return nil, "no party data" end
  local stride = Gen4Trainers.STRIDE[header.dataTypeId]
  if not stride then
    return nil, ("unknown trainer mon data type %s"):format(tostring(header.dataTypeId))
  end
  if #party < header.partySize * stride then
    return nil, ("party file holds %d bytes, needs %d for %d mon(s)")
      :format(#party, header.partySize * stride, header.partySize)
  end

  local withItem = header.dataTypeId == 2 or header.dataTypeId == 3
  local withMoves = header.dataTypeId == 1 or header.dataTypeId == 3
  local out = {}
  for i = 0, header.partySize - 1 do
    local o = i * stride
    local packed = u16(party, o + 4)
    local mon = {
      ivScale = u16(party, o),
      level = u16(party, o + 2),
      -- low 10 bits are the species; the rest is the form index
      species = packed % 1024,
      form = floor(packed / 1024),
    }
    local at = o + 6
    if withItem then mon.item = u16(party, at); at = at + 2 end
    if withMoves then
      mon.moves = {}
      for m = 0, 3 do mon.moves[m + 1] = u16(party, at + m * 2) end
      at = at + 8
    end
    mon.cbSeal = u16(party, at)
    out[i + 1] = mon
  end
  return out
end

-- Both archives at once, since neither is meaningful alone.
function Gen4Trainers.all(dataArchive, partyArchive, nameBank, Gen4Text)
  local out = {}
  for i = 0, dataArchive.count - 1 do
    local header = Gen4Trainers.parseHeader(dataArchive:get(i))
    if header then
      header.id = i
      header.party = Gen4Trainers.parseParty(header, partyArchive:get(i) or "")
      if nameBank and Gen4Text and i < nameBank.count then
        header.name = Gen4Text.render(Gen4Text.codes(nameBank, i))
      end
      out[i] = header
    end
  end
  return out
end

return Gen4Trainers
