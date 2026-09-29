-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4Trades.lua -- THE FOUR PEOPLE IN SINNOH WHO WILL SWAP.
--
-- Five script commands stood unlowered on four maps, and the first of them is
-- OREBURGH CITY -- the third town. tools/gen4_map_reach.lua is what made that
-- visible: `finishnpctrade` occurs eleven times, which puts it far down a list
-- ranked by occurrence, and sits on FOUR MAPS, which puts it near the top of
-- one ranked by reach.
--
-- ---------------------------------------------------------------------------
-- THE TABLE
--
-- /fielddata/pokemon_trade/fld_trade.narc, one member per trade, and the
-- member is TWENTY u32 IN A ROW -- struct NPCTradeMon, which is all words and
-- no packing, so there is nothing to get wrong about the layout and the field
-- ORDER is the only thing that can be:
--
--   species hpIV atkIV defIV speedIV spAtkIV spDefIV unused1 otID
--   cool beauty cute smart tough personality heldItem otGender unused2
--   language requestedSpecies
--
-- IT READS AS ITSELF, which is the check: four members, each exactly 80 bytes,
-- and the species/requested pairs come out as Platinum's own four trades --
--
--   0  ABRA      (63)  for MACHOP   (66)   Oreburgh City
--   1  CHATOT   (441)  for BUIZEL  (418)   Eterna City
--   2  HAUNTER   (93)  for MEDICHAM (308)  Snowpoint City
--   3  MAGIKARP (129)  for FINNEON  (456)  Route 226
--
-- ...and the SCRIPTS AGREE WITHOUT BEING ASKED: the four sites pass
-- `initnpctrade 0/1/2/3` on exactly those four maps, in that order. Two
-- unrelated readings of the same pairing.
--
-- ---------------------------------------------------------------------------
-- THE NAMES ARE A BANK, AND THE OT NAME IS THE SAME BANK PLUS FOUR
--
-- `NPCTrade_GetOTName` is one line -- `NPCTrade_GetNickname(heapID,
-- MAX_NPC_TRADES + npcTradeID)` -- so the eight entries of bank 370 are four
-- nicknames then four trainer names, and the offset between them is the trade
-- COUNT rather than a separate table:
--
--   0 Kazza   1 Charap  2 Gaspar  3 Foppa      <- the Pokemon's nicknames
--   4 Hilary  5 Norton  6 Mindy   7 Meister    <- the trainers who owned them
--
-- Bank 370 is TEXT_BANK_NPC_TRADE_NAMES on line 371 of
-- pokeplatinum's generated/text_banks.txt, zero-based, the same rule every
-- other bank in this port came from; eight entries decoded is the confirmation.

local Gen4Trades = {}

Gen4Trades.PATH = "/fielddata/pokemon_trade/fld_trade.narc"
Gen4Trades.NAME_BANK = 370
Gen4Trades.COUNT = 4            -- MAX_NPC_TRADES
Gen4Trades.RECORD_BYTES = 80    -- 20 x u32, sizeof(NPCTradeMon)

-- struct NPCTradeMon in declaration order. `unused1` and `unused2` are the
-- cartridge's own names for them and are kept so the twenty are visibly
-- twenty -- a reader counting fields is the cheapest check there is on a
-- layout with no other landmarks.
Gen4Trades.FIELDS = {
  "species", "hpIV", "atkIV", "defIV", "speedIV", "spAtkIV", "spDefIV",
  "unused1", "otID", "cool", "beauty", "cute", "smart", "tough",
  "personality", "heldItem", "otGender", "unused2", "language",
  "requestedSpecies",
}

-- The IVs, in the order Pokemon_SetValue is called with them, which is the
-- order a stat table has to be filled in.
Gen4Trades.IV_FIELDS = { "hpIV", "atkIV", "defIV", "speedIV", "spAtkIV",
                         "spDefIV" }

local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- Decode one member. Returns nil plus a reason on a short record rather than
-- reading nils out of it -- a truncated member means the archive is not this
-- one, and the caller should say so instead of shipping a trade with no
-- species.
function Gen4Trades.parse(record)
  if type(record) ~= "string" or #record < Gen4Trades.RECORD_BYTES then
    return nil, ("trade record is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1,
              Gen4Trades.RECORD_BYTES)
  end
  local out = {}
  for i, name in ipairs(Gen4Trades.FIELDS) do
    out[name] = u32(record, (i - 1) * 4)
  end
  return out
end

-- Which bank entry holds this trade's nickname, and which its OT name.
function Gen4Trades.nicknameEntry(id) return id end
function Gen4Trades.otNameEntry(id) return Gen4Trades.COUNT + id end

-- THE ONE FIELD THAT IS NOT A NUMBER AT REST. `otGender` is 0 or 1 in the
-- record and this port spells gender "boy"/"girl" everywhere else, so the
-- conversion happens here rather than in four places later. 1 is FEMALE, the
-- same way TrainerInfo_SetGender takes it.
function Gen4Trades.otGender(value)
  return (tonumber(value) == 1) and "girl" or "boy"
end

-- Every trade, as rows the runtime reads. `names` is the decoded bank.
function Gen4Trades.all(narc, names)
  local out = {}
  for id = 0, Gen4Trades.COUNT - 1 do
    local parsed = narc and Gen4Trades.parse(narc:get(id))
    if parsed then
      local ivs = {}
      for i, field in ipairs(Gen4Trades.IV_FIELDS) do ivs[i] = parsed[field] end
      out[id + 1] = {
        id = id,
        species = parsed.species,
        request = parsed.requestedSpecies,
        nickname = names and names[Gen4Trades.nicknameEntry(id) + 1] or nil,
        otName = names and names[Gen4Trades.otNameEntry(id) + 1] or nil,
        otId = parsed.otID,
        otGender = Gen4Trades.otGender(parsed.otGender),
        item = parsed.heldItem,
        personality = parsed.personality,
        language = parsed.language,
        ivs = ivs,
        -- Contest stats, extracted and not modelled by this engine. Kept
        -- because they are in the record and dropping them would make the row
        -- a summary rather than the record.
        conditions = { parsed.cool, parsed.beauty, parsed.cute, parsed.smart,
                       parsed.tough },
      }
    end
  end
  return out
end

return Gen4Trades
