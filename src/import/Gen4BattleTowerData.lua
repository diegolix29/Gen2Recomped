-- PLATINUM'S BATTLE TOWER TRAINERS AND THEIR POKEMON
-- (/battle/b_pl_tower/pl_btdtr.narc and pl_btdpm.narc).
--
-- pl_btdtr, one member per frontier trainer (generated/frontier_trainers.txt,
-- 0 Youngster Jim ... 305/306 Tower Tycoon Palmer), FrontierTrainerBase:
--
--   u16 trainerType      the trainer class
--   u16 numSets
--   u16 setIDs[numSets]  rows of pl_btdpm the trainer draws from
--
-- pl_btdpm, one member per set, FrontierPokemonBase (16 bytes):
--
--   u16 species, u16 moves[4], u8 evFlags, u8 nature, u16 item, u16 form
--
-- and the Battle Hall's own sets, /battle/b_pl_stage/pl_bsdpm.narc ("stage"
-- is the Hall's name in the source), in the same 16-byte layout: member k
-- is the Hall opponent at position k of sBattleHallPotentialOpponents
-- (1-based; member 0 is a blank).
--
-- Written to the cache module `gen4_battle_tower` as
--   { trainers = { [id] = { class, sets = {...} } }, sets = { [id] = {...} },
--     hallSets = { [k] = {...} } }

local Gen4BattleTowerData = {}

Gen4BattleTowerData.TRAINERS = "/battle/b_pl_tower/pl_btdtr.narc"
Gen4BattleTowerData.SETS = "/battle/b_pl_tower/pl_btdpm.narc"
Gen4BattleTowerData.HALL_SETS = "/battle/b_pl_stage/pl_bsdpm.narc"
Gen4BattleTowerData.HGSS_TRAINERS = "/a/2/0/2"
Gen4BattleTowerData.HGSS_SETS = "/a/2/0/3"
-- the Hall's sets: /a/2/0/4, pl_bsdpm's 478 16-byte members
Gen4BattleTowerData.HGSS_HALL_SETS = "/a/2/0/4"

local function u16(s, at) return s:byte(at) + s:byte(at + 1) * 256 end

function Gen4BattleTowerData.read(rom)
  local N = require("src.import.NarcArchive")
  local function read(path) local ok, b = pcall(rom.read, rom, path) return ok and b or nil end
  local tb, sb = read(Gen4BattleTowerData.TRAINERS), read(Gen4BattleTowerData.SETS)
  -- HEARTGOLD / SOULSILVER keep the same two tables at /a/2/0/2 (trainers) and
  -- /a/2/0/3 (sets) -- pokeheartgold GetFrontierTrainerData / GetFrontierMonNarcData
  if not (tb and sb) then
    tb, sb = read(Gen4BattleTowerData.HGSS_TRAINERS), read(Gen4BattleTowerData.HGSS_SETS)
  end
  if not (tb and sb) then return nil, "pl_btdtr / pl_btdpm missing" end
  local tn, sn = N.parse(tb), N.parse(sb)
  -- NOT LZ77, though a member can start with 0x10 like one: trainer 126's
  -- class is 16. Read raw, to the archive's own count.
  local function member(narc, i) return (narc:get(i)) end
  local out = { trainers = {}, sets = {} }
  for i = 0, tn.count - 1 do
    local b = member(tn, i)
    if b and #b >= 4 then
      local sets = {}
      for k = 0, u16(b, 3) - 1 do
        if 5 + k * 2 + 1 <= #b then sets[#sets + 1] = u16(b, 5 + k * 2) end
      end
      out.trainers[i] = { class = u16(b, 1), sets = sets }
    end
  end
  local function sets(narc, into)
    for i = 0, narc.count - 1 do
      local b = member(narc, i)
      if b and #b >= 16 then
        into[i] = {
          species = u16(b, 1),
          moves = { u16(b, 3), u16(b, 5), u16(b, 7), u16(b, 9) },
          evFlags = b:byte(11), nature = b:byte(12),
          item = u16(b, 13), form = u16(b, 15),
        }
      end
    end
  end
  sets(sn, out.sets)
  local hb = read(Gen4BattleTowerData.HALL_SETS) or read(Gen4BattleTowerData.HGSS_HALL_SETS)
  if hb then
    out.hallSets = {}
    sets(N.parse(hb), out.hallSets)
  end
  return out
end

return Gen4BattleTowerData
