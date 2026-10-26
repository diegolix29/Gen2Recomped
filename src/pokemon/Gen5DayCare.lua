-- BLACK / WHITE'S DAY CARE STEP, read from the cartridge (ov21).
--
-- The pens, the compatibility and the egg itself are Platinum's
-- (src/pokemon/Gen4DayCare.lua: ov21 0x21C36EC returns the same 0/20/50/70);
-- what Black / White changed is the step that drives them, 0x218AB50:
--
--   * the pens (0x200BD48) bank one EXP point per mon per step;
--   * the egg roll (0x21C385C) keeps its own counter, +16 a step, and rolls
--     once the OLD value is past 0xFF -- every 17th step -- and only with two
--     mons in: Random(1600) < compatibility makes the egg;
--   * the egg cycles (0x218AAD0) keep a saved counter, +256 a step (the
--     Hatching Pass Power scales that 256; none is ever on here), and when it
--     passes 0x10000 -- 257 steps -- every egg loses one cycle (two with
--     Flame Body / Magma Armor in the party, 0x218AA2C), down to zero;
--   * then (0x218AB0C) the first egg at zero cycles hatches, the same step.

local Gen5DayCare = {}

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end

Gen5DayCare.ROLL_STEP, Gen5DayCare.ROLL_AT, Gen5DayCare.ROLL_RANGE = 16, 0xFF, 1600
Gen5DayCare.CYCLE_STEP, Gen5DayCare.CYCLE_AT = 256, 0x10000

-- Once a step. Returns the egg that hatches, if one does.
function Gen5DayCare.update(data, save)
  local DC = require("src.pokemon.Gen4DayCare")
  local dc = DC.store(save, true)
  local n = 0
  for i = 1, 2 do
    local slot = dc.mons[i]
    if slot and slot.mon then slot.steps = (tonumber(slot.steps) or 0) + 1; n = n + 1 end
  end
  local roll = tonumber(dc.bwRollCounter) or 0
  dc.bwRollCounter = roll + Gen5DayCare.ROLL_STEP
  if roll > Gen5DayCare.ROLL_AT then
    dc.bwRollCounter = 0
    if n == 2 and rand(Gen5DayCare.ROLL_RANGE) < DC.compatibility(data, save) then
      DC.rollPersonality(data, save)
    end
  end
  local party = save.party or {}
  local counter = (tonumber(dc.bwEggCounter) or 0) + Gen5DayCare.CYCLE_STEP
  if counter > Gen5DayCare.CYCLE_AT then
    counter = 0
    local subtract = DC.cyclesToSubtract(data, party)
    for _, mon in ipairs(party) do
      if mon.isEgg and not (mon.isBadEgg or mon.badEgg) then
        local cycles = DC.cyclesOf(data, mon)
        cycles = cycles >= subtract and cycles - subtract or 0
        mon.eggCycles = cycles
        mon.eggSteps = math.max(1, cycles * 256)
      end
    end
  end
  dc.bwEggCounter = counter
  for _, mon in ipairs(party) do
    if mon.isEgg and not (mon.isBadEgg or mon.badEgg) and DC.cyclesOf(data, mon) == 0 then return mon end
  end
  return nil
end

return Gen5DayCare
