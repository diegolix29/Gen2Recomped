-- BLACK AND WHITE'S RECORD FORMATS: personal data, learnsets, evolutions,
-- moves, items and trainers, out of their NARCs.
--
-- pokeblack (squiddonaut/pokeblack, which builds this cartridge) has not yet
-- decompiled the code that reads these, so the layouts are the ones the Gen 5
-- research community documents -- and each is PROVEN against the cartridge
-- rather than trusted: tools/gen5_import_check.lua reads Bulbasaur's base
-- stats (45/49/49/45/65/65, Grass/Poison, Overgrow/Chlorophyll), Pound
-- (Normal, physical, 40 power, 100 accuracy, 35 PP), the Master Ball and a
-- Potion's prices, and the Striaton leaders' teams back out of them. An offset
-- that is wrong fails one of those.
--
-- Field names are the engine's own (what src/import/Gen4Species and friends
-- write), so Gen 5 data lands in the tables the battle and field code already
-- read.

local G = {}

local function u8(s, at) return s:byte(at + 1) or 0 end
local function u16(s, at) return u8(s, at) + u8(s, at + 1) * 256 end
local function s8(s, at) local v = u8(s, at); return v >= 128 and v - 256 or v end
local function u32(s, at) return u16(s, at) + u16(s, at + 2) * 65536 end

-- Gen 5's types: Gen 4's order with the ??? type taken out (17 of them)
G.TYPES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }
G.GROWTH = { [0] = "MEDIUM_FAST", "ERRATIC", "FLUCTUATING", "MEDIUM_SLOW", "FAST", "SLOW" }
G.CATEGORY = { [0] = "status", "physical", "special" }

-- PERSONAL (0x3C bytes)
--   00 hp atk def spe spa spd   06 type1 type2   08 catch   09 stage
--   0A u16 EV yields, two bits each: hp atk def spe spa spd
--   0C u16 item1 item2 item3   12 gender   13 hatch cycles   14 friendship
--   15 growth   16 egg groups x2   18 abilities x3 (the third the hidden one)
--   1B flee   1C u16 form stats offset   1E u16 form sprite offset   20 form count
--   21 colour (low six bits)   22 u16 base exp   24 u16 height   26 u16 weight
--   28 TM/HM bits (13 bytes)
function G.personal(s)
  if type(s) ~= "string" or #s < 0x28 then return nil end
  local ev = u16(s, 0x0A)
  local function evAt(k) return math.floor(ev / 4 ^ k) % 4 end
  local t1, t2 = u8(s, 6), u8(s, 7)
  local p = {
    baseStats = { hp = u8(s, 0), attack = u8(s, 1), defense = u8(s, 2), speed = u8(s, 3),
                  spatk = u8(s, 4), spdef = u8(s, 5) },
    typeIds = { t1, t2 },
    types = { G.TYPES[t1], G.TYPES[t2] },
    catchRate = u8(s, 8), stage = u8(s, 9),
    evYield = { hp = evAt(0), attack = evAt(1), defense = evAt(2), speed = evAt(3), spatk = evAt(4), spdef = evAt(5) },
    heldItems = { common = u16(s, 0x0C), rare = u16(s, 0x0E), dream = u16(s, 0x10) },
    genderRatio = u8(s, 0x12), hatchCycles = u8(s, 0x13), baseFriendship = u8(s, 0x14),
    expRate = u8(s, 0x15), growthRate = G.GROWTH[u8(s, 0x15)],
    eggGroups = { u8(s, 0x16), u8(s, 0x17) },
    abilityIds = { u8(s, 0x18), u8(s, 0x19), u8(s, 0x1A) },
    fleeRate = u8(s, 0x1B),
    formStatsIndex = u16(s, 0x1C), formSpriteIndex = u16(s, 0x1E), formCount = u8(s, 0x20),
    bodyColor = u8(s, 0x21) % 64,
    baseExp = u16(s, 0x22), height = u16(s, 0x24), weight = u16(s, 0x26),
  }
  -- the Gen 4 cache's spelling as well, so the engine's existing readers work
  p.baseStats.spAttack, p.baseStats.spDefense = p.baseStats.spatk, p.baseStats.spdef
  if t2 == t1 then p.types = { G.TYPES[t1] } end
  local tm = {}
  for b = 0, 12 do
    local byte = u8(s, 0x28 + b)
    for k = 0, 7 do if math.floor(byte / 2 ^ k) % 2 == 1 then tm[#tm + 1] = b * 8 + k end end
  end
  p.machineBits = tm
  return p
end

-- LEARNSET: { u16 move, u16 level } until 0xFFFF
function G.learnset(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for at = 0, #s - 4, 4 do
    local move, level = u16(s, at), u16(s, at + 2)
    if move == 0xFFFF then break end
    out[#out + 1] = { move = move, level = level }
  end
  return out
end

-- EVOLUTIONS: seven { u16 method, u16 parameter, u16 species }
function G.evolutions(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for at = 0, math.min(#s, 42) - 6, 6 do
    local method, param, target = u16(s, at), u16(s, at + 2), u16(s, at + 4)
    if method ~= 0 and target ~= 0 then out[#out + 1] = { method = method, param = param, species = target } end
  end
  return out
end

-- MOVE (0x24 bytes)
--   00 type   01 effect class   02 category   03 power   04 accuracy   05 pp
--   06 priority (signed)   07 hits (min low nibble, max high)
--   08 u16 condition   0A condition chance   0B condition kind   0C/0D turns min/max
--   0E crit stage   0F flinch   10 u16 effect   12 recoil/drain (signed)   13 heal
--   14 target   15-17 stats changed   18-1A by how much (signed)   1B-1D chances
--   20 u32 flags
function G.move(s)
  if type(s) ~= "string" or #s < 0x24 then return nil end
  local t = u8(s, 0)
  local cat = u8(s, 2)
  return {
    typeId = t, type = G.TYPES[t], class = G.CATEGORY[cat], category = G.CATEGORY[cat],
    effectClass = u8(s, 1), power = u8(s, 3), accuracy = u8(s, 4), pp = u8(s, 5),
    priority = s8(s, 6), hitsMin = u8(s, 7) % 16, hitsMax = math.floor(u8(s, 7) / 16),
    condition = u16(s, 8), conditionChance = u8(s, 0x0A), conditionKind = u8(s, 0x0B),
    turnsMin = u8(s, 0x0C), turnsMax = u8(s, 0x0D), critStage = u8(s, 0x0E), flinch = u8(s, 0x0F),
    effect = u16(s, 0x10), recoil = s8(s, 0x12), heal = u8(s, 0x13), target = u8(s, 0x14),
    statChanges = {
      { stat = u8(s, 0x15), amount = s8(s, 0x18), chance = u8(s, 0x1B) },
      { stat = u8(s, 0x16), amount = s8(s, 0x19), chance = u8(s, 0x1C) },
      { stat = u8(s, 0x17), amount = s8(s, 0x1A), chance = u8(s, 0x1D) },
    },
    flags = u32(s, 0x20),
  }
end

-- ITEM (0x24 bytes): the fields the bag, the shops and the battle read
--   00 u16 price / 10   02 hold effect   03 hold parameter   04 natural gift effect
--   05 fling effect   06 fling power   07 natural gift power
--   08 u16 natural gift type (low five bits), flags, and the POCKET in bits
--      7..10: Master Ball 0 (Items), Potion 1 (Medicine), TM01 2, Cheri 3
--      (Berries), Xtransceiver 4 (Key Items) -- what script 0xBB answers.
--      Kept as bwPocket: Platinum's fieldPocket counts eight pockets
--   0A field use   0B battle use   0C has battle stats   0D battle pocket
--   0E consumable   0F sort order
function G.item(s)
  if type(s) ~= "string" or #s < 0x10 then return nil end
  return {
    -- STORED IN TENS: an Ultra Ball's record says 120, a Potion's 30
    price = u16(s, 0) * 10, holdEffect = u8(s, 2), holdEffectParam = u8(s, 3),
    naturalGiftEffect = u8(s, 4), flingEffect = u8(s, 5), flingPower = u8(s, 6),
    naturalGiftPower = u8(s, 7), naturalGiftType = u16(s, 8) % 32,
    bwPocket = math.floor(u16(s, 8) / 128) % 16,
    fieldUse = u8(s, 0x0A), battleUse = u8(s, 0x0B), battlePocket = u8(s, 0x0D),
    consumable = u8(s, 0x0E), sortIndex = u8(s, 0x0F),
    -- the BATTLE POCKET MASK is bits 11..15 of +0x08 (Platinum's five bits:
    -- balls, battle items, HP / PP, status, PP); +0x0D above is the item's
    -- kind (0 medicine, 1 held, 2 general, 3 battle, 4 ball, 5 mail), kept
    -- under its first name. +0x0C partyUse and +0x10 the twenty-byte party
    -- block, Platinum's ItemPartyParam (src/inventory/Gen5Items.lua)
    battleMask = math.floor(u16(s, 8) / 2048) % 32, itemType = u8(s, 0x0D),
    partyUse = u8(s, 0x0C),
    partyUseParam = (u8(s, 0x0C) == 1 and #s >= 0x24) and s:sub(0x11, 0x24) or nil,
  }
end

-- TRAINER (trdata, 0x14 bytes)
--   00 format (bit 0 moves, bit 1 held items)   01 class   02 battle type
--   (0 single, 1 double, 2 triple, 3 rotation)   03 party size
--   04 u16 items x4   0C u32 AI flags   10 healer   11 money rate   12 u16 prize item
G.BATTLE_TYPES = { [0] = "single", "double", "triple", "rotation" }
function G.trainer(s)
  if type(s) ~= "string" or #s < 0x14 then return nil end
  local fmt = u8(s, 0)
  return {
    hasMoves = fmt % 2 == 1, hasItems = math.floor(fmt / 2) % 2 == 1,
    class = u8(s, 1), battleType = G.BATTLE_TYPES[u8(s, 2)] or "single",
    doubleBattle = u8(s, 2) == 1 or nil, partySize = u8(s, 3),
    items = { u16(s, 4), u16(s, 6), u16(s, 8), u16(s, 0x0A) },
    aiFlags = u32(s, 0x0C), healer = u8(s, 0x10) ~= 0, moneyRate = u8(s, 0x11), prizeItem = u16(s, 0x12),
  }
end

-- TRAINER PARTY (trpoke): per Pokemon { u8 IV difficulty, u8 gender/ability,
-- u8 level, u8 0, u16 species, u16 form } then u16 item if the trainer has
-- items, then four u16 moves if it has moves
function G.party(s, tr)
  local out = {}
  if type(s) ~= "string" or not tr then return out end
  local size = 8 + (tr.hasItems and 2 or 0) + (tr.hasMoves and 8 or 0)
  for i = 0, tr.partySize - 1 do
    local at = i * size
    if at + size > #s then break end
    local mon = { difficulty = u8(s, at), genderAbility = u8(s, at + 1), level = u8(s, at + 2),
                  species = u16(s, at + 4), form = u16(s, at + 6) }
    local o = at + 8
    if tr.hasItems then mon.item = u16(s, o); o = o + 2 end
    if tr.hasMoves then
      mon.moves = { u16(s, o), u16(s, o + 2), u16(s, o + 4), u16(s, o + 6) }
    end
    out[#out + 1] = mon
  end
  return out
end

return G
