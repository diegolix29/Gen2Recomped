-- WHICH MACHINES EACH GEN 4 SPECIES CAN LEARN, unpacked at load time from the
-- personal record's 128-bit mask (`tmLearnset`, four u32) against
-- `constants.tmhmMoves` (sTMHMMoves) -- the same reading the extractor does
-- (RomExtractorGen4, "WHICH SPECIES CAN LEARN WHICH OF THEM"): bit b of word w
-- is machine w * 32 + b, zero-based, TM01..TM92 then HM01..HM08.
--
-- HERE BECAUSE A HEARTGOLD / SOULSILVER CACHE HAS NO `tmhm` AT ALL.  The
-- extractor finds sTMHMMoves in arm9 by its HM tail, and that tail was
-- Platinum's (HM05 Defog); HGSS's HM05 is Whirlpool, so the search found
-- nothing, the per-species lists were never written, and every TM and HM
-- answered "can't learn that move!" (Gen4HgssConstants writes the right
-- `tmhmMoves` later, which is why the bag still knew what each machine was).
-- Deriving it here fixes an existing cache without a re-import; a species
-- that already carries a list keeps it.

local M = {}

local floor = math.floor

function M.unpack(mask, moves)
  local list = {}
  for word = 1, 4 do
    local v = tonumber(mask[word]) or 0
    if v < 0 then v = v + 4294967296 end
    for bit = 0, 31 do
      if v % 2 == 1 then
        local id = (word - 1) * 32 + bit
        if id < #moves then list[#list + 1] = moves[id + 1] end
      end
      v = floor(v / 2)
    end
  end
  return list
end

-- BLACK / WHITE keep a different pair: `machineBits` on the species (the
-- personal record's 13 compatibility bytes as zero-based bit numbers, written
-- by src/import/Gen5Data.lua) and `machine = { move, index, hm }` on the
-- items, `index` being the ARM9 table's order -- TM01..TM92, HM01..HM06,
-- TM93..TM95 (RomExtractorGen5). THE PERSONAL BITS ARE IN ANOTHER ORDER:
-- TM01..TM95 first, then HM01..HM06. Pikachu shows it -- bits 92, 93 and 98
-- are TM93 Wild Charge, TM94 Rock Smash and HM04 Strength, all of which it
-- learns; read as the ARM9 order they would be Cut, Fly and TM93.
function M.gen5Index(bit)
  if bit < 92 then return bit end
  if bit < 95 then return bit + 6 end        -- TM93..TM95 -> 98..100
  if bit < 101 then return bit - 3 end       -- HM01..HM06 -> 92..97
  return nil
end

-- fills `def.tmhm` where it is missing; returns how many species were filled
function M.fill(data)
  local moves = data and data.constants and data.constants.tmhmMoves
  local registry = data and data.pokemon
  if type(registry) ~= "table" then return 0 end
  local byIndex
  if type(data.items) == "table" then
    for _, it in pairs(data.items) do
      local m = type(it) == "table" and it.machine
      if type(m) == "table" and m.index and m.move then
        byIndex = byIndex or {}
        byIndex[m.index] = m.move
        -- the bag and ItemEffects tell an HM (kept) from a TM (used up) by
        -- `kind`, which the Gen 5 record spells `hm`
        if m.kind == nil then m.kind = m.hm and "HM" or "TM" end
      end
    end
  end
  local n = 0
  for _, def in pairs(registry) do
    if type(def) == "table" and def.tmhm == nil then
      if type(def.tmLearnset) == "table" and type(moves) == "table" and #moves > 0 then
        def.tmhm = M.unpack(def.tmLearnset, moves)
        n = n + 1
      elseif type(def.machineBits) == "table" and byIndex then
        local list = {}
        for _, bit in ipairs(def.machineBits) do
          local idx = M.gen5Index(bit)
          if idx and byIndex[idx] then list[#list + 1] = byIndex[idx] end
        end
        def.tmhm = list
        n = n + 1
      end
    end
  end
  return n
end

return M
