-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) species records.
--
-- The first stage that produces something the rest of the engine recognises,
-- and the one that proves the floor underneath it: cartridge -> NdsRom ->
-- NarcArchive -> a fixed-size record, with the name coming from Gen4Text.
-- Four modules and no special cases, which is what the filesystem reader was
-- for.
--
-- /poketool/personal/pl_personal.narc holds 508 members of 44 bytes: 493
-- species and the alternate forms that need their own stats (Deoxys,
-- Giratina Origin, Shaymin Sky, Rotom's five appliances, Wormadam's cloaks).
-- Member index IS the National Dex number for 1..493; the forms follow.
--
-- Layout, from pokeplatinum include/struct_defs/species.h.  It sums to
-- exactly 44 bytes, which is the independent check that it is being read
-- right -- and the values come out correct against the published tables
-- (Pikachu 35/55/30/90/50/40 with Static, Giratina 150/100/120/90/100/120).
--
--   00 u8   hp            06 u8   types[0]      10 u16  evYields (2 bits each)
--   01 u8   attack        07 u8   types[1]      12 u16  wildHeldItem common
--   02 u8   defense       08 u8   catchRate     14 u16  wildHeldItem rare
--   03 u8   speed         09 u8   baseExpReward 16 u8   genderRatio
--   04 u8   spAttack                            17 u8   hatchCycles
--   05 u8   spDefense                           18 u8   baseFriendship
--                                               19 u8   expRate
--   20 u8   eggGroups[0]  22 u8   abilities[0]  24 u8   safariFleeRate
--   21 u8   eggGroups[1]  23 u8   abilities[1]  25 u8   bodyColor:7 flip:1
--   26 u16  padding       28 u32  tmLearnsetMasks[4]
--
-- NOTE THE STAT ORDER: hp, attack, defense, SPEED, spAttack, spDefense.
-- Speed is fourth, not last.  Reading it in the display order every stat
-- screen uses swaps Speed with Special Attack, which produces a table that
-- looks entirely plausible and is wrong for every species in the game.

local Gen4Species = {}

Gen4Species.RECORD_BYTES = 44

-- Gen 4 type ids.  9 is the unused slot left between Steel and Fire where
-- Gen 2's "bird" type sat; nothing in the cartridge uses it.
Gen4Species.TYPES = {
  [0] = "normal", "fighting", "flying", "poison", "ground", "rock", "bug",
  "ghost", "steel", "unused", "fire", "water", "grass", "electric",
  "psychic", "ice", "dragon", "dark",
}

-- The message bank inside /msgdata/pl_msg.narc that holds species names,
-- indexed by dex number.  Found by looking rather than assumed: bank 412
-- entry 1 is BULBASAUR and entry 25 is PIKACHU.
Gen4Species.NAME_BANK = 412
Gen4Species.DEX_ENTRY_BANK = 706

local floor = math.floor

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end

-- Two bits per stat, in the same order as the base stats.
local function evYields(word)
  local out, v = {}, word
  for _, key in ipairs({ "hp", "attack", "defense", "speed", "spAttack", "spDefense" }) do
    out[key] = v % 4
    v = math.floor(v / 4)
  end
  return out
end

-- Decode one 44-byte record.  Returns nil plus a reason on a short record
-- rather than reading nils out of it, because a truncated member means the
-- archive is wrong and the caller should say so.
function Gen4Species.parse(record)
  if type(record) ~= "string" or #record < Gen4Species.RECORD_BYTES then
    return nil, ("species record is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1, Gen4Species.RECORD_BYTES)
  end
  local t1, t2 = u8(record, 6), u8(record, 7)
  local colour = u8(record, 25)
  return {
    baseStats = {
      hp = u8(record, 0), attack = u8(record, 1), defense = u8(record, 2),
      speed = u8(record, 3), spAttack = u8(record, 4), spDefense = u8(record, 5),
    },
    -- A single-type species stores the same id twice, so the second is
    -- reported only when it differs -- callers should not have to know that.
    types = { Gen4Species.TYPES[t1], t2 ~= t1 and Gen4Species.TYPES[t2] or nil },
    typeIds = { t1, t2 },
    catchRate = u8(record, 8),
    baseExp = u8(record, 9),
    evYields = evYields(u16(record, 10)),
    heldItems = { common = u16(record, 12), rare = u16(record, 14) },
    genderRatio = u8(record, 16),
    hatchCycles = u8(record, 17),
    baseFriendship = u8(record, 18),
    expRate = u8(record, 19),
    eggGroups = { u8(record, 20), u8(record, 21) },
    abilities = { u8(record, 22), u8(record, 23) },
    safariFleeRate = u8(record, 24),
    bodyColor = colour % 128,
    flipSprite = colour >= 128,
    tmLearnset = {
      u16(record, 28) + u16(record, 30) * 65536,
      u16(record, 32) + u16(record, 34) * 65536,
      u16(record, 36) + u16(record, 38) * 65536,
      u16(record, 40) + u16(record, 42) * 65536,
    },
  }
end

-- ---------------------------------------------------------------------------
-- Learnsets
-- ---------------------------------------------------------------------------

-- /poketool/personal/wotbl.narc, one member per species, VARIABLE length --
-- 24 to 36 bytes across Platinum -- because the list simply ends.  Each entry
-- is one u16 packing the move in the low 9 bits and the level in the high 7,
-- and 0xFFFF terminates.
--
-- The 9/7 split is not arbitrary and not swappable: Gen 4 has 467 moves,
-- which needs 9 bits, and levels reach 100, which needs 7.  Reading it the
-- other way round yields levels in the hundreds and move ids under 128, and
-- every species appears to learn low-numbered moves at impossible levels --
-- wrong in a way that still produces a plausible-looking table.
--
-- Verified: Bulbasaur comes out Tackle 1, Growl 3, Leech Seed 7, Vine Whip 9,
-- PoisonPowder and Sleep Powder both at 13, ... Seed Bomb 37, which is
-- Platinum's list exactly.
Gen4Species.LEARNSET_SENTINEL = 0xFFFF

function Gen4Species.parseLearnset(record)
  if type(record) ~= "string" then return nil, "no learnset record" end
  local out = {}
  for i = 0, floor(#record / 2) - 1 do
    local v = u16(record, i * 2)
    if not v or v == Gen4Species.LEARNSET_SENTINEL then break end
    out[#out + 1] = { move = v % 512, level = floor(v / 512) }
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Evolutions
-- ---------------------------------------------------------------------------

-- /poketool/personal/evo.narc, one member per species, 44 bytes: seven slots
-- of { u16 method, u16 param, u16 target } and two bytes of padding.  Method
-- 0 means the slot is empty.
--
-- EVERY METHOD NUMBER BELOW WAS DERIVED FROM THE CARTRIDGE AND CHECKED
-- AGAINST A SPECIES THAT CAN BE NAMED, rather than copied from a table.  The
-- enum lives in a generated header pokeplatinum builds and does not ship, so
-- there was nothing to copy; instead every evolution in the game was grouped
-- by method and the groups identified:
--
--   1  Golbat, Chansey, Pichu            -- friendship
--   2  Espeon, Budew, Riolu              -- friendship by day
--   3  Umbreon, Chingling                -- friendship by night
--   4  162 of them, Bulbasaur at 16      -- level
--   5  Kadabra, Machoke, Graveler        -- trade
--   6  Poliwhirl and Slowpoke with King's Rock, Onix with Metal Coat
--   7  Pikachu with a Thunder Stone      -- use item
--   8/9/10  Tyrogue at 20, atk >/=/< def -- the three Hitmons
--   11/12   Wurmple                      -- personality value low/high
--   13/14   Nincada                      -- Ninjask, and Shedinja
--   15 Feebas at beauty 170
--   16/17   Kirlia and Snorunt with a Dawn Stone -- use item male/female
--   18 Happiny with an Oval Stone by DAY
--   19 Gligar with a Razor Fang and Sneasel with a Razor Claw, by NIGHT
--   20 Lickitung knowing Rollout, Aipom knowing Double Hit -- knows move
--   21 Mantyke with a Remoraid in the party -- species in party
--   22 Burmy -> Mothim (male)            23 Burmy -> Wormadam, Combee (female)
--   24 Magneton and Nosepass             -- magnetic field
--   25 Leafeon (mossy rock)              26 Glaceon (icy rock)
--
-- What `param` means depends on the method: a level for 4 and 8-15 and 20-24,
-- an ITEM for 6, 7, 16-19, a MOVE for 20, a SPECIES for 21, and nothing at
-- all for the friendship and rock methods.  A caller that treats it as one
-- thing gets Pikachu evolving at level 83.
Gen4Species.EVOLUTION_SLOTS = 7

Gen4Species.EVOLUTION_METHODS = {
  [1] = "friendship", [2] = "friendshipDay", [3] = "friendshipNight",
  [4] = "level", [5] = "trade", [6] = "tradeWithItem", [7] = "useItem",
  [8] = "levelAtkGreater", [9] = "levelAtkEqual", [10] = "levelAtkLess",
  [11] = "levelPidLow", [12] = "levelPidHigh",
  [13] = "levelNinjask", [14] = "levelShedinja",
  [15] = "beauty",
  [16] = "useItemMale", [17] = "useItemFemale",
  [18] = "levelHoldingItemDay", [19] = "levelHoldingItemNight",
  [20] = "levelKnowsMove", [21] = "levelSpeciesInParty",
  [22] = "levelMale", [23] = "levelFemale",
  [24] = "magneticField", [25] = "mossRock", [26] = "iceRock",
}

-- What the `param` field carries, per method, so a caller never has to guess.
Gen4Species.EVOLUTION_PARAM = {
  level = { [4]=true, [8]=true, [9]=true, [10]=true, [11]=true, [12]=true,
            [13]=true, [14]=true, [22]=true, [23]=true },
  item = { [6]=true, [7]=true, [16]=true, [17]=true, [18]=true, [19]=true },
  move = { [20]=true },
  species = { [21]=true },
  beauty = { [15]=true },
}

function Gen4Species.parseEvolutions(record)
  if type(record) ~= "string" or #record < Gen4Species.EVOLUTION_SLOTS * 6 then
    return nil, "evolution record is too short"
  end
  local out = {}
  for i = 0, Gen4Species.EVOLUTION_SLOTS - 1 do
    local method = u16(record, i * 6)
    if method and method ~= 0 then
      local param = u16(record, i * 6 + 2)
      local paramKind
      for kind, set in pairs(Gen4Species.EVOLUTION_PARAM) do
        if set[method] then paramKind = kind break end
      end
      out[#out + 1] = {
        method = Gen4Species.EVOLUTION_METHODS[method] or ("unknown_" .. method),
        methodId = method,
        param = param,
        paramKind = paramKind,
        target = u16(record, i * 6 + 4),
      }
    end
  end
  return out
end

-- Every species in one pass.  `personal` is a parsed NarcArchive over
-- pl_personal.narc; `nameBank` is Gen4Text.bank(msg:get(NAME_BANK)) and may
-- be omitted when only the numbers are wanted.
function Gen4Species.all(personal, nameBank, Gen4Text)
  local out = {}
  for i = 0, personal.count - 1 do
    local parsed = Gen4Species.parse(personal:get(i))
    if parsed then
      parsed.id = i
      if nameBank and Gen4Text and i < nameBank.count then
        parsed.name = Gen4Text.render(Gen4Text.codes(nameBank, i))
      end
      out[i] = parsed
    end
  end
  return out
end

return Gen4Species
