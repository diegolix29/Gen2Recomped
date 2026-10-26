-- HEARTGOLD / SOULSILVER APRIJUICE: the juice record, its label and what it
-- does to a Pokemon's Pokeathlon performance. Transcribed from pokeheartgold
-- asm/unk_02031B0C.s (the Apricorn Box save), field/scrcmd_pokemon_misc.c
-- ScrCmd_741 and asm/overlay_58.s ov58_022379C0.
--
-- READ FROM CODE:
--   * a juice is 8 bytes (UnkStruct_02031CEC): u16 `pop` (unk0 -- the label's
--     "owner's comment" grade and a tenth of the price), u8 smoothness, and
--     five flavour amounts, one per performance stat in the summary's order
--     POWER STAMINA SKILL JUMP SPEED (bank 21's juice names #20-#24 are
--     Power / Stam. / Skill / Jump / Speed Juice in that order)
--   * richness (sub_02031D80) = the five amounts summed, capped at 100
--   * sub_02031CEC(box, idx): 0-4 the stand's five built-in juices
--     (_020F6902), 5-7 the three shelves of other players' juices (box +0x38,
--     0x20 apart; empty unless record mixing filled them), 8 the player's own
--     Apriblender (+0xC, only while it holds one)
--   * the label (ScrCmd_741): shelf s shows juice s + 5 or, when that is
--     empty, built-in (weekday + 2 s) % 5; owner = bank 21 #14 + idx for a
--     built-in juice, the stored trainer name otherwise; name = bank 21
--     #19 + (strongest flavour + 1), #19 "NoFlav Juice" when it has none
--     (sub_02032004); price = pop / 10 + 2 x richness, kept in 100..5000
--   * the analysis (sub_02031DA0): the flavours sorted by amount (ties by
--     flavour), up to three ranked "slots" (flavour, amount, level from
--     sub_02032504's thresholds), and the weakest flavour
--   * DRINKING (ov58_022379C0, called by the drinking app with the party
--     slot): the strongest flavour's stat gets floor(1.5 x amount) + 10, the
--     second's floor(1.5 x amount) (written over the first when they are the
--     same stat), the weakest flavour's stat loses floor(sum x k) where sum is
--     the two amounts and k is 0.1 at smoothness 255, 0.2 at 200+, else
--     1 - 0.1 x floor(smoothness / 25) (single-precision float, truncated);
--     each value is clamped to -127..127 and REPLACES the slot's five
--     modifiers (the previous juice is gone); then the Pokemon's mood + 30
--     (ApplyMonMoodModifier 7, sMoodModifiers[7], clamped -127..127)
--   * stars use base + PokeathlonStatScoreToStars(daily + modifier)
--     (src/pokemon/HgssPokeathlonPerformance.lua, `mon.aprijuice`)
--
-- STAND-INS, said so:
--   * the modifiers live on the Pokemon (`mon.aprijuice[0..4]`), not in the
--     party's per-slot extra (PartyExtraSub), so they follow it when the
--     party is reordered; the cartridge also clears a slot when its Pokemon
--     leaves it (Party_SafeCopyMonToSlot_ResetAprijuiceModifiers)
--   * shelves 5-7 hold nothing without record mixing (this port has none),
--     so every shelf shows a built-in juice

local M = {}

M.POWER, M.STAMINA, M.SKILL, M.JUMP, M.SPEED = 0, 1, 2, 3, 4
M.NAME_BANK = 21
M.OWNER_FIRST, M.JUICE_FIRST = 14, 19
M.MOOD_JUICE = 30                      -- sMoodModifiers[MON_MOOD_MODIFIER_7]

-- _020F6902: the stand's five juices { pop, smooth, flavours[0..4] }
M.BUILT_IN = {
  [0] = { pop = 0,   smooth = 0x74, flavour = { [0] = 0x16, 0x0A, 0, 0, 0 } },
  [1] = { pop = 150, smooth = 0x78, flavour = { [0] = 0, 0x14, 0x0E, 0, 0 } },
  [2] = { pop = 540, smooth = 0x7D, flavour = { [0] = 0, 0, 0x1C, 0x14, 0 } },
  [3] = { pop = 200, smooth = 0x88, flavour = { [0] = 0, 0, 0, 0x18, 0x0E } },
  [4] = { pop = 150, smooth = 0x68, flavour = { [0] = 0x0C, 0, 0, 0, 0x14 } },
}

local floor = math.floor

-- single precision, round to nearest (the ARM soft-float the overlay calls)
local function f32(x)
  if x == 0 then return 0 end
  local m, e = math.frexp(x)
  return math.ldexp(floor(m * 16777216 + 0.5) / 16777216, e)
end
M.f32 = f32

-- sub_02031D80
function M.richness(juice)
  local n = 0
  for i = 0, 4 do n = n + (juice.flavour[i] or 0) end
  return math.min(100, n)
end

-- sub_02032504: a ranked slot's level by its rank and amount
function M.level(rank, amount)
  if amount == 0 then return 0 end
  if rank == 0 then
    if amount > 62 then return 6 elseif amount > 50 then return 5 elseif amount > 40 then return 4
    elseif amount > 30 then return 3 elseif amount > 20 then return 2 end
    return 1
  elseif rank == 1 then
    if amount > 40 then return 4 elseif amount > 30 then return 3 elseif amount > 20 then return 2 end
    return 1
  elseif rank == 2 then
    if amount > 20 then return 3 elseif amount > 10 then return 2 end
    return 1
  end
  return 0
end

-- sub_02031DA0: { slots = {[0..2] = {flavour, amount, level}}, order[0..4],
-- count (flavours present), ties (how many share the lowest amount) }.
-- A slot's flavour 5 is "balanced" and 6 "none", as the cartridge marks them.
function M.analyse(juice)
  local pairs_ = {}
  local count = 0
  for i = 0, 4 do
    local a = juice.flavour[i] or 0
    pairs_[i] = { idx = i, amount = a }
    if a ~= 0 then count = count + 1 end
  end
  if count ~= 0 then
    for i = 0, 4 do
      for j = i + 1, 4 do
        local pi, pj = pairs_[i], pairs_[j]
        if not (pi.amount > pj.amount or (pi.amount == pj.amount and pi.idx < pj.idx)) then
          pairs_[i], pairs_[j] = pj, pi
        end
      end
    end
  end
  local out = { slots = { [0] = { flavour = 0, amount = 0, level = 0 }, { flavour = 0, amount = 0, level = 0 },
    { flavour = 0, amount = 0, level = 0 } }, order = {}, count = count, ties = 0 }
  local low = pairs_[4].amount
  for i = 0, 4 do
    out.order[i] = pairs_[i].idx
    if pairs_[i].amount == low then out.ties = out.ties + 1 end
  end
  local function put(k, p, rank)
    out.slots[k] = { flavour = p.idx, amount = p.amount, level = M.level(rank, p.amount) }
  end
  if count == 0 then
    out.slots[0].flavour = 6
    return out
  elseif count == 1 then
    put(0, pairs_[0], 0); out.slots[1].flavour = 6
  elseif count == 2 then
    put(0, pairs_[0], 0); put(1, pairs_[1], 1); out.slots[2].flavour = 6
  elseif count == 3 then
    put(0, pairs_[0], 0); put(1, pairs_[1], 1); put(2, pairs_[2], 2)
  else
    if pairs_[0].amount - pairs_[3].amount <= 12 then
      -- balanced: the first slot is "all of them"
      local a0 = pairs_[0].amount
      out.slots[0] = { flavour = 5, amount = a0, level = a0 > 20 and 3 or (a0 > 7 and 2 or 1) }
      out.slots[1] = { flavour = 6, amount = pairs_[1].amount, level = 0 }
      out.slots[2] = { flavour = 6, amount = pairs_[2].amount, level = 0 }
    else
      put(0, pairs_[0], 0); put(1, pairs_[1], 1)
      if count == 4 then
        -- the cartridge reads the fifth pair here (amount 0 for four flavours)
        put(2, pairs_[4], 2)
      else
        out.slots[2] = { flavour = 5, amount = pairs_[2].amount, level = 1 }
      end
    end
  end
  return out
end

-- sub_02032004: the juice's name entry offset (0 none, 1 + strongest)
function M.nameIndex(juice)
  local a = M.analyse(juice)
  if a.count == 0 then return 0 end
  return a.order[0] + 1
end

-- the shelf's juice index (ScrCmd_741): the stored juice, else a built-in
-- one by the weekday (0 = Sunday)
function M.shelfJuice(save, shelf, week)
  local idx = shelf + 5
  local j = M.juice(save, idx)
  if j then return idx, j end
  idx = (week + 2 * shelf) % 5
  return idx, M.juice(save, idx)
end

-- sub_02031CEC: nil when that slot holds nothing (richness 0)
function M.juice(save, idx)
  idx = tonumber(idx) or 0
  if idx >= 9 then idx = 0 end
  if idx <= 4 then return M.BUILT_IN[idx] end
  local box = save and save.hgssApricorns
  if idx <= 7 then
    local shelf = box and box.shelves and box.shelves[idx - 5]
    if shelf and shelf.juice and M.richness(shelf.juice) ~= 0 then return shelf.juice end
    return nil
  end
  local own = box and box.blender
  if own and (own.uses or 0) ~= 0 and own.juice then return own.juice end
  return nil
end

-- the label: owner, name entry, price, richness, smoothness
function M.label(save, idx, juice)
  local rich = M.richness(juice)
  local price = floor((juice.pop or 0) / 10) + 2 * rich
  if price < 100 then price = 100 elseif price > 5000 then price = 5000 end
  local owner
  if idx < 5 then owner = { bank = M.NAME_BANK, entry = M.OWNER_FIRST + idx }
  elseif idx < 8 then
    local shelf = save and save.hgssApricorns and save.hgssApricorns.shelves and save.hgssApricorns.shelves[idx - 5]
    owner = { text = shelf and shelf.name or "" }
  else owner = { text = "" } end
  return { owner = owner, nameEntry = M.JUICE_FIRST + M.nameIndex(juice), price = price,
    richness = rich, smoothness = juice.smooth or 0, pop = juice.pop or 0 }
end

-- ov58_022379C0: the five modifiers this juice leaves
function M.modifiers(juice)
  local a = M.analyse(juice)
  local delta = { [0] = 0, 0, 0, 0, 0 }
  local s0, s1 = a.slots[0], a.slots[1]
  local r5 = s0.flavour < 5 and s0.flavour or a.order[0]
  local r7 = s1.flavour < 5 and s1.flavour or a.order[1]
  local A, B = s0.amount, s1.amount
  local function s8(v) v = v % 256; return v >= 128 and v - 256 or v end
  delta[r5] = s8(floor(A * 1.5))
  if A ~= 0 then delta[r5] = s8(delta[r5] + 10) end
  delta[r7] = s8(floor(B * 1.5))
  local sum = (A + B) % 256
  local smooth = juice.smooth or 0
  local pen
  if smooth == 255 then pen = floor(f32(sum * f32(0.1)))
  elseif smooth >= 200 then pen = floor(f32(sum * f32(0.2)))
  else
    local k = f32(1.0 - f32(floor(smooth / 25) * f32(0.1)))
    pen = math.max(0, floor(f32(sum * k)))
  end
  pen = pen % 256
  local weak = a.order[4]
  delta[weak] = s8(delta[weak] - pen)
  local mods = {}
  for i = 0, 4 do
    local v = delta[i]
    if v < -127 then v = -127 elseif v > 127 then v = 127 end
    mods[i] = v
  end
  return mods
end

-- give `juice` to `mon`: its modifiers replaced, its mood up
function M.drink(mon, juice)
  if not mon then return nil end
  local mods = M.modifiers(juice)
  mon.aprijuice = mods
  if not mon.isEgg and not mon.egg then
    local m = (tonumber(mon.hgssMood) or 0) + M.MOOD_JUICE
    if m > 127 then m = 127 elseif m < -127 then m = -127 end
    mon.hgssMood = m
  end
  return mods
end

return M
