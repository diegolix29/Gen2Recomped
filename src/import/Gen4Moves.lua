-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) move records.
--
-- /poketool/waza/pl_waza_tbl.narc: 471 members of exactly 16 bytes, which is
-- the size of pokeplatinum's MoveTable and therefore the check that the
-- layout below is being read right.  Member index is the move id, so member 1
-- is Pound.
--
--   00 u16 effect        06 u8  pp             10 s8  priority
--   02 u8  class         07 u8  effectChance   11 u8  flags
--   03 u8  power         08 u16 range          12 u8  contestEffect
--   04 u8  type                                13 u8  contestType
--   05 u8  accuracy                            14 u16 padding
--
-- PRIORITY IS SIGNED.  Quick Attack is +1 and Roar is -6, and reading the
-- byte unsigned turns every negative-priority move into a move that goes
-- first -- which is not a crash, not a visual glitch, and not something a
-- battle looks obviously wrong for; it just quietly plays the wrong game.
--
-- Verified against the published tables rather than eyeballed: Pound
-- 40/100/35 normal physical, Thunderbolt 95/100/15 electric special, Hyper
-- Beam 150/90/5, Struggle 50 power with 0 accuracy and 1 PP, and Hidden Power
-- listed at power 1 because the cartridge computes it at run time.

local Gen4Moves = {}

Gen4Moves.RECORD_BYTES = 16

-- The message bank in /msgdata/pl_msg.narc holding move names, indexed by
-- move id.  Found by looking: bank 647 entry 1 is "Pound" and entry 85 is
-- "Thunderbolt".  648 is the same list in capitals, which the battle screens
-- use.
Gen4Moves.NAME_BANK = 647
Gen4Moves.NAME_BANK_UPPER = 648
Gen4Moves.DESCRIPTION_BANK = 646

Gen4Moves.CLASSES = { [0] = "physical", "special", "status" }

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end
local function s8(s, o)
  local v = s:byte(o + 1)
  if not v then return nil end
  return v < 128 and v or v - 256
end

function Gen4Moves.parse(record)
  if type(record) ~= "string" or #record < Gen4Moves.RECORD_BYTES then
    return nil, ("move record is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1, Gen4Moves.RECORD_BYTES)
  end
  return {
    effect = u16(record, 0),
    class = Gen4Moves.CLASSES[u8(record, 2)],
    classId = u8(record, 2),
    power = u8(record, 3),
    typeId = u8(record, 4),
    accuracy = u8(record, 5),
    pp = u8(record, 6),
    effectChance = u8(record, 7),
    range = u16(record, 8),
    priority = s8(record, 10),
    flags = u8(record, 11),
    contestEffect = u8(record, 12),
    contestType = u8(record, 13),
  }
end

-- `archive` is a parsed NarcArchive over pl_waza_tbl.narc.  `nameBank` and
-- `Gen4Text` are optional; without them the numbers still come back.
function Gen4Moves.all(archive, nameBank, Gen4Text)
  local out = {}
  for i = 0, archive.count - 1 do
    local m = Gen4Moves.parse(archive:get(i))
    if m then
      m.id = i
      if nameBank and Gen4Text and i < nameBank.count then
        m.name = Gen4Text.render(Gen4Text.codes(nameBank, i))
      end
      out[i] = m
    end
  end
  return out
end

return Gen4Moves
