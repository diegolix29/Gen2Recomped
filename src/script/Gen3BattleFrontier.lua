-- EMERALD'S BATTLE FRONTIER: THE BATTLE TOWER (pokeemerald battle_tower.c,
-- frontier_util.c, field_specials.c's BufferBattleTowerElevatorFloors).
--
-- The lobby, elevator, corridor and battle room are ordinary maps with
-- ordinary scripts, and everything they ask goes through three specials:
--
--   234 CallFrontierUtilFunc   the Frontier's shared bookkeeping (VAR_0x8004
--                              picks one of 23 functions)
--   235 CallBattleTowerFunc    the tower's own (16 functions)
--   239 DoSpecialTrainerBattle arm 0, SPECIAL_BATTLE_TOWER: the battle
--
-- The Battle Tents answer to the same three, and src/script/Gen3Commands.lua
-- already serves them; this installs OVER that and hands anything that is a
-- tent's (FRONTIER_LVL_TENT) or not the tower's back to it.
--
-- STATE is the cartridge's frontier struct, on save.gen3Frontier -- the same
-- table the tents keep their run in, because on the cartridge it is the same
-- struct (challengeStatus, lvlMode, curChallengeBattleNum ... are shared):
--
--   data[0..7]     FRONTIER_DATA_*: status, lvlMode, battle number, paused,
--                  (selected order is save.gen3SelectedOrder), outcome,
--                  record disabled
--   towerStreaks   ["mode:lvl"] = towerWinStreaks[battleMode][lvlMode]
--   streakActive   ["mode:lvl"] = winStreakActiveFlags' tower bits
--   trainerIds     this challenge's opponents, so nobody is met twice
--   brainFlags     battledBrainFlags (heard Anabel's speech, silver / gold)
--   opponent       gTrainerBattleOpponent_A: a frontier trainer id (0-299)
--                  or "brain"
--
-- Battle Points are save.gen3BattlePoints (Gen3Commands.setBattlePoints), the
-- symbols FLAG_SYS_TOWER_SILVER / _GOLD.
--
-- THE BATTLE PALACE rides the same plumbing: its own 237
-- (CallBattlePalaceFunction), the tower's SetNextFacilityOpponent for its
-- opponents, 239 arm 4 for its battle -- fought under Palace rules
-- (src/battle/Gen3Palace.lua) -- and Spenser where the tower has Anabel.
--
-- THE MULTI BATTLE ROOMS (FRONTIER_MODE_MULTIS): the partner room's six
-- candidates (LoadMultiPartnerCandidatesData, arm 10), what each says when
-- talked to (ShowPartnerCandidateMessage, arm 11, in the class's own five
-- lines out of sPartnerTrainerTextTables), the fourteen opponents drawn when
-- one is chosen, two at a time with their own sprites (SetNextFacilityOpponent's
-- multi branch), and the battle: your two, the partner's two beside them, two
-- trainers of two across (BATTLE_TYPE_INGAME_PARTNER | TWO_OPPONENTS).
--
-- NOT HERE: link play, the e-Reader and record-mixed trainers and apprentices
-- (ChooseSpecialBattleTowerTrainer finds none without record mixing, and the
-- partner room's two extra candidates never appear), the results windows and
-- battle recording.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")

local F = {}

F.TOWER, F.DOME, F.PALACE, F.ARENA, F.FACTORY, F.PIKE, F.PYRAMID = 0, 1, 2, 3, 4, 5, 6
F.SINGLES, F.DOUBLES, F.MULTIS, F.LINK_MULTIS = 0, 1, 2, 3
F.LVL_50, F.LVL_OPEN, F.LVL_TENT = 0, 1, 2
F.VAR_MODE, F.VAR_FACILITY, F.VAR_STATUS, F.VAR_GFX0 = 0x40CE, 0x40CF, 0x4000, 0x4010
F.VAR_RESULT = 0x800D
F.STATUS_SAVING, F.STATUS_PAUSED, F.STATUS_WON, F.STATUS_LOST = 1, 2, 3, 4
F.STAGES = 7
F.MAX_STREAK = 9999
F.BRAIN = "brain"
F.FLAG_TOWER_SILVER = 0x860 + 0x64        -- FLAG_SYS_TOWER_SILVER; gold is + 1
F.TRAINER_KEY = "TRAINER_G3_FRONTIER"
F.TRAINER_KEY_B = "TRAINER_G3_FRONTIER_B"
F.PARTNER_KEY = "TRAINER_G3_FRONTIER_PARTNER"
F.VAR_GFX_E = 0x401E                      -- VAR_OBJ_GFX_ID_E: the chosen partner's sprite
F.PARTNER_INTRO, F.PARTNER_MON1, F.PARTNER_MON2_ASK, F.PARTNER_ACCEPT, F.PARTNER_REJECT = 0, 1, 2, 3, 4

-- sFrontierTrainerIdRanges / sFrontierTrainerIdRangesHard (0-based ids)
F.RANGES = { { 0, 99 }, { 80, 119 }, { 100, 139 }, { 120, 159 }, { 140, 179 }, { 160, 199 },
             { 180, 219 }, { 200, 299 } }
F.RANGES_HARD = { { 100, 119 }, { 120, 139 }, { 140, 159 }, { 160, 179 }, { 180, 199 },
                  { 200, 219 }, { 220, 239 }, { 200, 299 } }
F.HIGH_TIER = 849          -- FRONTIER_MONS_HIGH_TIER: above it, open level only

-- gTowerMale/FemaleFacilityClasses -> gTowerMale/FemaleTrainerGfxIds, numbered
F.CLASS_GFX = { [14] = 55, [17] = 54, [3] = 33, [21] = 15, [23] = 39, [7] = 51, [10] = 44,
  [25] = 66, [26] = 66, [27] = 31, [29] = 39, [30] = 37, [32] = 48, [38] = 38, [41] = 25,
  [9] = 21, [43] = 35, [45] = 50, [46] = 56, [48] = 51, [50] = 51, [52] = 33, [4] = 66,
  [53] = 5, [58] = 49, [5] = 39, [66] = 65, [68] = 31, [67] = 36, [0] = 55, [13] = 20,
  [16] = 53, [18] = 34, [12] = 40, [19] = 20, [20] = 45, [31] = 47, [39] = 14, [42] = 18,
  [22] = 22, [47] = 57, [49] = 52, [51] = 52, [54] = 14, [55] = 34, [56] = 52, [28] = 32,
  [2] = 20, [69] = 32, [71] = 47 }
F.GFX_ANABEL = 70

-- gFrontierBannedSpecies
F.BANNED = { MEW = true, MEWTWO = true, HO_OH = true, LUGIA = true, CELEBI = true,
             KYOGRE = true, GROUDON = true, RAYQUAZA = true, JIRACHI = true, DEOXYS = true }

-- sFrontierBrainStreakAppearances: silver, gold, every, offset
F.BRAIN_AT = { 35, 70, 35, 1 }
F.BRAIN_AT_BY = { [0] = F.BRAIN_AT, [2] = { 21, 42, 21, 1 }, [3] = { 28, 56, 28, 1 }, [4] = { 21, 42, 21, 1 },
                  [5] = { 28, 140, 56, 1 }, [6] = { 21, 70, 35, 0 }, [1] = { 4, 9, 5, 0 } }
-- OBJ_EVENT_GFX_ANABEL, _SPENSER, _GRETA, _NOLAND, _LUCY
F.BRAIN_GFX = { [0] = 70, [1] = 71, [2] = 73, [3] = 72, [4] = 74, [5] = 75, [6] = 234 }
F.BRAIN_TRAINER = { [0] = "ANABEL", [1] = "TUCKER", [2] = "SPENSER", [3] = "GRETA", [4] = "NOLAND", [5] = "LUCY", [6] = "BRANDON" }

-- sFrontierBrainsMons[TOWER]: Anabel's two teams. EVs in the save's order
-- (HP, Attack, Defense, Speed, Sp. Atk, Sp. Def).
F.ANABEL = {
  [0] = {
    { species = "ALAKAZAM", item = "BRIGHT_POWDER", iv = 24, nature = 15, evs = { 106, 0, 152, 152, 100, 0 },
      moves = { "THUNDER_PUNCH", "FIRE_PUNCH", "ICE_PUNCH", "DISABLE" } },
    { species = "ENTEI", item = "LUM_BERRY", iv = 24, nature = 1, evs = { 100, 152, 152, 0, 100, 6 },
      moves = { "FIRE_BLAST", "CALM_MIND", "RETURN", "ROAR" } },
    { species = "SNORLAX", item = "QUICK_CLAW", iv = 24, nature = 3, evs = { 152, 152, 0, 0, 106, 100 },
      moves = { "BODY_SLAM", "BELLY_DRUM", "YAWN", "SHADOW_BALL" } },
  },
  [1] = {
    { species = "RAIKOU", item = "LUM_BERRY", iv = 31, nature = 15, evs = { 158, 0, 252, 100, 0, 0 },
      moves = { "THUNDERBOLT", "CALM_MIND", "REFLECT", "REST" } },
    { species = "LATIOS", item = "BRIGHT_POWDER", iv = 31, nature = 15, evs = { 252, 0, 252, 6, 0, 0 },
      moves = { "PSYCHIC", "CALM_MIND", "RECOVER", "DRAGON_CLAW" } },
    { species = "SNORLAX", item = "CHESTO_BERRY", iv = 31, nature = 3, evs = { 252, 252, 0, 0, 6, 0 },
      moves = { "CURSE", "RETURN", "REST", "SHADOW_BALL" } },
  },
}
-- ...and Spenser's (sFrontierBrainsMons[FRONTIER_FACILITY_PALACE])
F.SPENSER = {
  [0] = {
    { species = "CROBAT", item = "BRIGHT_POWDER", iv = 16, nature = 3, evs = { 152, 0, 0, 152, 100, 106 },
      moves = { "CONFUSE_RAY", "DOUBLE_TEAM", "TOXIC", "FLY" } },
    { species = "SLAKING", item = "SCOPE_LENS", iv = 16, nature = 0, evs = { 152, 152, 0, 106, 100, 0 },
      moves = { "EARTHQUAKE", "SWAGGER", "SHADOW_BALL", "BRICK_BREAK" } },
    { species = "LAPRAS", item = "QUICK_CLAW", iv = 16, nature = 17, evs = { 0, 0, 252, 0, 106, 152 },
      moves = { "ICE_BEAM", "HORN_DRILL", "CONFUSE_RAY", "PROTECT" } },
  },
  [1] = {
    { species = "ARCANINE", item = "WHITE_HERB", iv = 31, nature = 11, evs = { 6, 252, 252, 0, 0, 0 },
      moves = { "OVERHEAT", "EXTREME_SPEED", "ROAR", "PROTECT" } },
    { species = "SLAKING", item = "SCOPE_LENS", iv = 31, nature = 0, evs = { 6, 252, 0, 252, 0, 0 },
      moves = { "HYPER_BEAM", "EARTHQUAKE", "SHADOW_BALL", "YAWN" } },
    { species = "SUICUNE", item = "KINGS_ROCK", iv = 31, nature = 11, evs = { 252, 0, 252, 6, 0, 0 },
      moves = { "BLIZZARD", "SURF", "BITE", "CALM_MIND" } },
  },
}
-- ...and Greta's (sFrontierBrainsMons[FRONTIER_FACILITY_ARENA])
F.GRETA = {
  [0] = {
    { species = "HERACROSS", item = "SALAC_BERRY", iv = 20, nature = 13, evs = { 106, 152, 0, 152, 0, 100 },
      moves = { "MEGAHORN", "ROCK_TOMB", "ENDURE", "REVERSAL" } },
    { species = "UMBREON", item = "LEFTOVERS", iv = 20, nature = 20, evs = { 152, 0, 100, 0, 152, 106 },
      moves = { "BODY_SLAM", "CONFUSE_RAY", "PSYCHIC", "FAINT_ATTACK" } },
    { species = "SHEDINJA", item = "BRIGHT_POWDER", iv = 20, nature = 3, evs = { 0, 252, 6, 252, 0, 0 },
      moves = { "SHADOW_BALL", "RETURN", "CONFUSE_RAY", "AERIAL_ACE" } },
  },
  [1] = {
    { species = "UMBREON", item = "CHESTO_BERRY", iv = 31, nature = 20, evs = { 252, 0, 0, 0, 252, 6 },
      moves = { "DOUBLE_EDGE", "CONFUSE_RAY", "REST", "PSYCHIC" } },
    { species = "GENGAR", item = "LEFTOVERS", iv = 31, nature = 15, evs = { 252, 0, 252, 0, 6, 0 },
      moves = { "PSYCHIC", "HYPNOSIS", "DREAM_EATER", "DESTINY_BOND" } },
    { species = "BRELOOM", item = "LUM_BERRY", iv = 31, nature = 13, evs = { 6, 252, 0, 252, 0, 0 },
      moves = { "SPORE", "FOCUS_PUNCH", "GIGA_DRAIN", "HEADBUTT" } },
  },
}
-- ...and Lucy's (sFrontierBrainsMons[FRONTIER_FACILITY_PIKE])
F.LUCY = {
  [0] = {
    { species = "SEVIPER", item = "QUICK_CLAW", iv = 16, nature = 2, evs = { 252, 0, 252, 0, 6, 0 },
      moves = { "SWAGGER", "CRUNCH", "POISON_FANG", "GIGA_DRAIN" } },
    { species = "SHUCKLE", item = "CHESTO_BERRY", iv = 16, nature = 5, evs = { 252, 0, 0, 0, 106, 252 },
      moves = { "TOXIC", "SANDSTORM", "PROTECT", "REST" } },
    { species = "MILOTIC", item = "LEFTOVERS", iv = 16, nature = 15, evs = { 152, 0, 100, 0, 152, 106 },
      moves = { "ICE_BEAM", "MIRROR_COAT", "SURF", "RECOVER" } },
  },
  [1] = {
    { species = "SEVIPER", item = "FOCUS_BAND", iv = 31, nature = 5, evs = { 252, 0, 0, 0, 252, 6 },
      moves = { "SWAGGER", "CRUNCH", "SLUDGE_BOMB", "GIGA_DRAIN" } },
    { species = "STEELIX", item = "BRIGHT_POWDER", iv = 31, nature = 2, evs = { 252, 0, 0, 0, 6, 252 },
      moves = { "EARTHQUAKE", "ROCK_SLIDE", "EXPLOSION", "SCREECH" } },
    { species = "GYARADOS", item = "CHESTO_BERRY", iv = 31, nature = 3, evs = { 252, 6, 0, 0, 0, 252 },
      moves = { "DRAGON_DANCE", "RETURN", "ROAR", "REST" } },
  },
}
F.BRAIN_TEAMS = { [0] = F.ANABEL, [2] = F.SPENSER, [3] = F.GRETA, [5] = F.LUCY }
-- sBattlePointAwards' arena column, challenge by challenge
F.ARENA_BP = { 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
               15, 15, 15, 15, 15, 15, 15, 15, 15, 15 }
-- sShortStreakPrizeItems / sLongStreakPrizeItems (battle_arena.c)
F.ARENA_EARLY = { "HP_UP", "PROTEIN", "IRON", "CALCIUM", "CARBOS", "ZINC" }
F.ARENA_LATE = { "BRIGHT_POWDER", "WHITE_HERB", "QUICK_CLAW", "LEFTOVERS", "MENTAL_HERB", "KINGS_ROCK",
                 "FOCUS_BAND", "SCOPE_LENS", "CHOICE_BAND" }
F.BRAIN_OTID = 61226

-- the Battle Palace's prizes (sBattlePalaceEarlyPrizes / LatePrizes)
F.PALACE_EARLY = { "HP_UP", "PROTEIN", "IRON", "CALCIUM", "CARBOS", "ZINC" }
F.PALACE_LATE = { "BRIGHT_POWDER", "WHITE_HERB", "QUICK_CLAW", "LEFTOVERS", "MENTAL_HERB", "KINGS_ROCK",
  "FOCUS_BAND", "SCOPE_LENS", "CHOICE_BAND" }

-- --------------------------------------------------------------- helpers --

local G3
local function g3() G3 = G3 or require("src.script.Gen3Commands") return G3 end
local function getVar(ctx, id) return math.floor(tonumber(g3().getVar(ctx.save, id)) or 0) end
local function setVar(ctx, id, v) g3().setVar(ctx.save, id, math.floor(tonumber(v) or 0)) end

function F.state(save)
  local G = g3()
  local s = G.tentState({ save = save })
  s.towerStreaks = s.towerStreaks or {}
  s.streakActive = s.streakActive or {}
  s.trainerIds = s.trainerIds or {}
  s.brainFlags = s.brainFlags or 0
  return s
end

local function key(mode, lvl) return ("%d:%d"):format(mode, lvl) end
function F.mode(ctx) return getVar(ctx, F.VAR_MODE) end
function F.lvl(s) return math.floor(tonumber(s.data[1]) or 0) end

-- towerWinStreaks / palaceWinStreaks / ...: the tower keeps its table,
-- every other facility gets one of its own
local function streaks(s, fac)
  fac = fac or F.TOWER
  if fac == F.TOWER then return s.towerStreaks end
  s.facStreaks = s.facStreaks or {}
  s.facStreaks[fac] = s.facStreaks[fac] or {}
  return s.facStreaks[fac]
end
local function actives(s, fac)
  fac = fac or F.TOWER
  if fac == F.TOWER then return s.streakActive end
  s.facActive = s.facActive or {}
  s.facActive[fac] = s.facActive[fac] or {}
  return s.facActive[fac]
end
F.actives = actives
function F.streak(s, mode, lvl, fac)
  return math.min(F.MAX_STREAK, math.floor(tonumber(streaks(s, fac)[key(mode, lvl)]) or 0))
end
function F.setStreak(s, mode, lvl, n, fac) streaks(s, fac)[key(mode, lvl)] = math.max(0, math.floor(n)) end
function F.facility(ctx) return getVar(ctx, F.VAR_FACILITY) end

local function flagOn(ctx, n)
  local name = g3().flagKey(n)
  local flags = ctx.save and ctx.save.flags
  if type(flags) == "table" and flags[name] ~= nil then return flags[name] and true or false end
  local ok = pcall(Commands.check_flag, ctx, name)
  return ok and ctx.lastCheck and true or false
end

-- GetPlayerSymbolCountForFacility
function F.symbols(ctx, facility)
  facility = facility or getVar(ctx, F.VAR_FACILITY)
  return (flagOn(ctx, F.FLAG_TOWER_SILVER + facility * 2) and 1 or 0)
       + (flagOn(ctx, F.FLAG_TOWER_SILVER + facility * 2 + 1) and 1 or 0)
end

-- GetFrontierBrainStatus (the tower's row of the appearances table)
function F.brainStatus(ctx)
  if F.mode(ctx) ~= F.SINGLES then return 0 end
  local fac = F.facility(ctx)
  local at = F.BRAIN_AT_BY[fac]
  if not at then return 0 end
  local s = F.state(ctx.save)
  local win = F.streak(s, F.SINGLES, F.lvl(s), fac) + at[4]
  local sym = F.symbols(ctx, fac)
  if sym < 2 then
    return (win == at[sym + 1]) and (sym + 1) or 0
  end
  if win == at[1] then return 3 end
  if win == at[2] then return 4 end
  if win > at[2] and (win - at[2]) % at[3] == 0 then return 4 end
  return 0
end

-- GetFronterBrainSymbol: which of her two teams
function F.brainTeam(ctx)
  local fac = F.facility(ctx)
  local at = F.BRAIN_AT_BY[fac] or F.BRAIN_AT
  local s = F.state(ctx.save)
  local sym = F.symbols(ctx, fac)
  if sym < 2 then return sym end
  local win = F.streak(s, F.SINGLES, F.lvl(s), fac) + at[4]
  if win == at[1] then return 0 end
  return 1
end

-- GetRandomScaledFrontierTrainerId
function F.trainerFor(challengeNum, battleNum, rand)
  rand = rand or love.math.random
  local range
  if challengeNum <= 7 then
    range = (battleNum == F.STAGES - 1) and F.RANGES_HARD[challengeNum + 1] or F.RANGES[challengeNum + 1]
  else
    range = F.RANGES[8]
  end
  return range[1] + (rand(0, 65535) % (range[2] - range[1] + 1))
end

-- GetFrontierTrainerFixedIvs
function F.ivsFor(id)
  if id <= 99 then return 3 elseif id <= 119 then return 6 elseif id <= 139 then return 9
  elseif id <= 159 then return 12 elseif id <= 179 then return 15 elseif id <= 199 then return 18
  elseif id <= 219 then return 21 end
  return 31
end

-- GetFrontierEnemyMonLevel
function F.enemyLevel(save, lvlMode)
  if lvlMode == F.LVL_OPEN then
    local top = 0
    for _, mon in ipairs(save.party or {}) do top = math.max(top, math.floor(tonumber(mon.level) or 0)) end
    return math.max(60, top)
  end
  return 50
end

-- SetBattleFacilityTrainerGfxId
function F.trainerGfx(data, id, fac)
  if id == F.BRAIN then return F.BRAIN_GFX[fac or F.TOWER] or F.GFX_ANABEL end
  local tr = F.trainerRecord(data, id)
  return (tr and F.CLASS_GFX[tonumber(tr.facilityClass) or -1]) or F.CLASS_GFX[16]
end

function F.parties(data) return (data and data.constants or {}).gen3FrontierParties end
function F.trainerRecord(data, id)
  local p = F.parties(data)
  return p and p.trainers and p.trainers[(tonumber(id) or -1) + 1]
end

-- ------------------------------------------------------------- the teams --

-- one Pokemon at `level`, the way CreateMonWithEVSpreadNatureOTID makes it:
-- a personality of the nature, the fixed IVs in every stat, the spread's
-- 510 shared by the flagged stats, friendship 255 (0 with Frustration)
function F.makeMon(data, species, level, nature, iv, evs, item, moves, otId, rand)
  rand = rand or love.math.random
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  local ok, mon = pcall(Pokemon.new, data, species, level)
  if not ok or not mon then return nil end
  local pid
  for _ = 1, 4000 do
    pid = rand(0, 65535) * 65536 + rand(0, 65535)
    if pid % 25 == nature then break end
  end
  local order = data.constants and data.constants.natureOrder
  mon.personality = pid
  mon.otId = otId
  mon.shiny = nil
  mon.nature = order and order[(pid % 25) + 1] or mon.nature
  mon.ivs = { hp = iv, attack = iv, defense = iv, speed = iv, spatk = iv, spdef = iv }
  mon.evs = { hp = evs[1], attack = evs[2], defense = evs[3], speed = evs[4], spatk = evs[5], spdef = evs[6] }
  local def = require("src.pokemon.Gen4Forms").definition(data, mon)
  if def and type(def.abilities) == "table" then
    mon.abilitySlot = def.abilities[2] and (pid % 2) + 1 or 1
  end
  mon.item = item
  mon.moves = {}
  mon.happiness = 255
  for _, m in ipairs(moves or {}) do
    if m and m ~= 0 then
      local md = data.moves and data.moves[m]
      mon.moves[#mon.moves + 1] = { id = m, pp = md and md.pp or 0 }
      if m == "FRUSTRATION" then mon.happiness = 0 end
    end
  end
  if def then
    mon.stats = Stats.calc(def, level, mon.ivs, nil, mon.evs, mon.nature)
    mon.hp = mon.stats.hp
  end
  return mon
end

-- the spread mask as six EVs: MAX_TOTAL_EVS / the number of flagged stats
function F.spread(mask)
  local n = 0
  for k = 0, 5 do if math.floor(mask / 2 ^ k) % 2 == 1 then n = n + 1 end end
  local each = n > 0 and math.floor(510 / n) or 0
  local out = {}
  for k = 0, 5 do out[k + 1] = (math.floor(mask / 2 ^ k) % 2 == 1) and each or 0 end
  return out
end

-- FillTrainerParty: `count` of the trainer's set, no species or held item
-- twice, the high tier left out at level 50
function F.trainerParty(data, id, count, level, rand, avoid)
  rand = rand or love.math.random
  local p = F.parties(data)
  local tr = F.trainerRecord(data, id)
  local set = tr and tr.set
  if not (p and set and #set > 0) then return {} end
  local ivs = F.ivsFor(id)
  local otId = rand(0, 65535) * 65536 + rand(0, 65535)
  local chosen, species, items, out = {}, {}, {}, {}
  -- the second multi trainer fills slots 3-4 behind the first: none of the
  -- first's species or items either
  for _, mon in ipairs(avoid or {}) do
    species[mon.species] = true
    if mon.item then items[mon.item] = true end
  end
  local guard = 0
  while #out < count and guard < 5000 do
    guard = guard + 1
    local monId = set[rand(1, #set)]
    local row = p.mons[monId]
    local ok = row ~= nil
    if ok and level == 50 and (monId - 1) > F.HIGH_TIER then ok = false end
    if ok and species[row.species] then ok = false end
    if ok and row.item and items[row.item] then ok = false end
    if ok and chosen[monId] then ok = false end
    if ok then
      local mon = F.makeMon(data, row.species, level, row.nature or 0, ivs, F.spread(row.ev or 0),
        row.item, row.moves, otId, rand)
      if mon then
        out[#out + 1] = mon
        species[row.species] = true
        if row.item then items[row.item] = true end
        chosen[monId] = true
      end
    end
  end
  return out
end

-- CreateFrontierBrainPokemon
function F.brainParty(data, team, level, rand, fac)
  local out = {}
  for _, b in ipairs((F.BRAIN_TEAMS[fac or F.TOWER] or F.ANABEL)[team] or {}) do
    local mon = F.makeMon(data, b.species, level, b.nature, b.iv, b.evs, b.item, b.moves, F.BRAIN_OTID, rand)
    if mon then out[#out + 1] = mon end
  end
  return out
end

-- ------------------------------------------------------- CallBattleTowerFunc --

function F.towerFunc(ctx, arg)
  local s = F.state(ctx.save)
  local data = ctx.game and ctx.game.data
  local mode, lvl = F.mode(ctx), F.lvl(s)
  local a5 = getVar(ctx, 0x8005)
  local a6 = getVar(ctx, 0x8006)
  if arg == 0 then              -- InitTowerChallenge
    s.data[0], s.data[2], s.data[3], s.data[6] = F.STATUS_SAVING, 0, 0, 0
    s.trainerIds = {}
    if not s.streakActive[key(mode, lvl)] then F.setStreak(s, mode, lvl, 0) end
    -- SetDynamicWarp(0, here): where a frontier save puts the player back
    local ow = ctx.overworld
    if ow and ow.map and ow.player then
      s.continueAt = { map = ow.map.id, x = ow.player.cellX, y = ow.player.cellY }
    end
    s.opponent = nil
  elseif arg == 1 then          -- GetTowerData
    if a5 == 1 then setVar(ctx, F.VAR_RESULT, F.streak(s, mode, lvl))
    elseif a5 == 2 then setVar(ctx, F.VAR_RESULT, s.streakActive[key(mode, lvl)] and 1 or 0)
    elseif a5 == 3 then s.towerLvlMode = lvl end
  elseif arg == 2 then          -- SetTowerData
    if a5 == 1 then F.setStreak(s, mode, lvl, a6)
    elseif a5 == 2 then s.streakActive[key(mode, lvl)] = (a6 ~= 0) or nil
    elseif a5 == 3 then s.towerLvlMode = lvl end
  elseif arg == 3 and mode == F.MULTIS then
    -- SetNextFacilityOpponent's multi branch: the pair drawn on accepting
    local battleNum = math.floor(tonumber(s.data[2]) or 0)
    s.opponent, s.opponentB = s.trainerIds[battleNum * 2], s.trainerIds[battleNum * 2 + 1]
    setVar(ctx, F.VAR_GFX0, F.trainerGfx(data, s.opponent))
    setVar(ctx, F.VAR_GFX0 + 1, F.trainerGfx(data, s.opponentB))
  elseif arg == 3 then          -- SetNextFacilityOpponent
    local battleNum = math.floor(tonumber(s.data[2]) or 0)
    local fac = F.facility(ctx)
    local challengeNum = math.floor(F.streak(s, mode, lvl, fac) / F.STAGES)
    local id
    for _ = 1, 500 do
      id = F.trainerFor(challengeNum, battleNum)
      local met = false
      for i = 0, battleNum - 1 do if s.trainerIds[i] == id then met = true end end
      if not met then break end
    end
    s.opponent = id
    setVar(ctx, F.VAR_GFX0, F.trainerGfx(data, id, fac))
    if battleNum + 1 < F.STAGES then s.trainerIds[battleNum] = id end
  elseif arg == 4 then          -- SetTowerBattleWon
    s.towerNumWins = math.min(F.MAX_STREAK, (s.towerNumWins or 0) + 1)
    s.data[2] = math.floor(tonumber(s.data[2]) or 0) + 1
    setVar(ctx, F.VAR_RESULT, s.data[2])
  elseif arg == 5 then          -- AwardBattleTowerRibbons
    setVar(ctx, F.VAR_RESULT, F.giveRibbons(ctx, s, mode, lvl) and 1 or 0)
  elseif arg == 6 then          -- SaveTowerChallenge
    s.data[0] = a5
    setVar(ctx, F.VAR_STATUS, 0)
    s.data[3] = 1
    F.saveFrontier(ctx)
  elseif arg == 7 then          -- GetOpponentIntroSpeech (0x8005: the second of a pair)
    F.bufferSpeech(ctx, (a5 ~= 0) and s.opponentB or s.opponent, "before")
  elseif arg == 10 then         -- LoadMultiPartnerCandidatesData
    F.loadPartners(ctx, s, mode, lvl)
  elseif arg == 11 then         -- ShowPartnerCandidateMessage
    F.partnerMessage(ctx, s, mode, lvl, a5)
  elseif arg == 14 then         -- SetMultiPartnerGfx
    setVar(ctx, F.VAR_GFX_E, F.trainerGfx(data, s.trainerIds[17]))
  elseif arg == 12 then         -- LoadLinkMultiOpponentsData: not linked, done
    setVar(ctx, F.VAR_RESULT, 6)
  else
    -- 8, 9 are nops on the cartridge; 13 the link; 15 the TV interview
    Logger.debug("gen3 battle tower: function %d has nothing to do here", arg)
  end
end

-- GetRandomFrontierMonFromSet: any of the trainer's set, the high tier only at open level
function F.randomSetMon(data, id, lvl, rand)
  rand = rand or love.math.random
  local tr = F.trainerRecord(data, id)
  local set = tr and tr.set
  if not (set and #set > 0) then return nil end
  for _ = 1, 1000 do
    local monId = set[rand(1, #set)]
    if not (lvl == F.LVL_50 and (monId - 1) > F.HIGH_TIER) then return monId end
  end
  return set[1]
end

-- LoadMultiPartnerCandidatesData: six candidates, none twice and no two of
-- one class (trainerIds 0-5), two Pokemon each (8-19). A second Pokemon
-- never holds its first's item, and none is a species already drawn or one
-- of your two -- except the very first, which the cartridge's loop (k from
-- 8 to r10, empty when r10 is 8) never checks at all.
function F.loadPartners(ctx, s, mode, lvl, rand)
  rand = rand or love.math.random
  local data = ctx.game.data
  local p = F.parties(data)
  local challengeNum = math.floor(F.streak(s, mode, lvl) / F.STAGES)
  local party = ctx.save.party or {}
  local sp1, sp2 = party[1] and party[1].species, party[2] and party[2].species
  s.trainerIds = s.trainerIds or {}
  local ids = s.trainerIds
  for j = 0, 5 do
    local id
    for _ = 1, 1000 do
      id = F.trainerFor(challengeNum, 0, rand)
      local clash = false
      for i = 0, j - 1 do
        local a, b = F.trainerRecord(data, ids[i]), F.trainerRecord(data, id)
        if ids[i] == id or (a and b and a.facilityClass == b.facilityClass) then clash = true break end
      end
      if not clash then break end
    end
    ids[j] = id
  end
  local r10 = 8
  for i = 0, 5 do
    setVar(ctx, F.VAR_GFX0 + i, F.trainerGfx(data, ids[i]))
    for j = 0, 1 do
      local monId
      for _ = 1, 1000 do
        monId = F.randomSetMon(data, ids[i], lvl, rand)
        local row = p and p.mons[monId]
        local ok = row ~= nil
        if ok and j % 2 ~= 0 then
          local prev = p.mons[ids[r10 - 1]]
          if prev and prev.item == row.item then ok = false end
        end
        if ok then
          for k = 8, r10 - 1 do
            local other = p.mons[ids[k]]
            if (other and other.species == row.species) or sp1 == row.species or sp2 == row.species then
              ok = false
              break
            end
          end
        end
        if ok then break end
      end
      ids[r10] = monId
      r10 = r10 + 1
    end
  end
end

-- the class's five lines (sPartnerTrainerTextTables)
function F.partnerLine(data, id, msg)
  local speech = data.gen3_frontier_speech
  local tr = F.trainerRecord(data, id)
  local lines = speech and speech.partnerTexts and tr and speech.partnerTexts[tonumber(tr.facilityClass) or -1]
  return lines and lines[msg]
end

-- ShowPartnerCandidateMessage: k = VAR_LAST_TALKED - 2 (the six are local ids 2-7)
function F.partnerMessage(ctx, s, mode, lvl, msg, rand)
  rand = rand or love.math.random
  local data = ctx.game.data
  local game = ctx.game
  local p = F.parties(data)
  local k = getVar(ctx, 0x800F) - 2
  local ids = s.trainerIds or {}
  local id = ids[k]
  if id == nil then return end
  local var1, var2
  if msg == F.PARTNER_INTRO then
    local tr = F.trainerRecord(data, id)
    var1 = tr and tr.name or ""
  elseif msg == F.PARTNER_MON1 or msg == F.PARTNER_MON2_ASK then
    -- GetPotentialPartnerMoveAndSpecies: its first move, its species
    local row = p and p.mons[ids[8 + k * 2 + (msg == F.PARTNER_MON2_ASK and 1 or 0)]]
    local move = row and row.moves and row.moves[1]
    local md = move and data.moves and data.moves[move]
    local def = row and data.pokemon and data.pokemon[row.species]
    var1 = md and md.name or tostring(move or "")
    var2 = def and def.name or tostring(row and row.species or "")
  elseif msg == F.PARTNER_ACCEPT then
    -- the partner and their two kept (17, 18-19), and fourteen opponents
    -- drawn two to a battle, the partner never among them
    ids[18], ids[19] = ids[8 + k * 2], ids[9 + k * 2]
    local challengeNum = math.floor(F.streak(s, mode, lvl) / F.STAGES)
    for kk = 0, F.STAGES * 2 - 1 do
      local i
      for _ = 1, 1000 do
        i = F.trainerFor(challengeNum, math.floor(kk / 2), rand)
        local ok = i ~= id
        for j = 0, kk - 1 do if ids[j] == i then ok = false break end end
        if ok then break end
      end
      ids[kk] = i
    end
    ids[17] = id
  end
  game.stringBuffers = game.stringBuffers or {}
  if var1 then game.stringBuffers[1] = var1 end
  if var2 then game.stringBuffers[2] = var2 end
  local line = F.partnerLine(data, id, msg)
  if not line then return end
  line = line:gsub("{VAR1}", function() return game.stringBuffers[1] or "" end)
             :gsub("{VAR2}", function() return game.stringBuffers[2] or "" end)
  game.stringBuffers[4] = line
  Commands.show_text(ctx, "{RAM:wStringBuffer4}")
end

-- FillPartnerParty: the chosen partner's two, at the challenge's level
-- with the partner's fixed IVs and full friendship (none with Frustration)
function F.partnerParty(data, s, level, rand)
  rand = rand or love.math.random
  local p = F.parties(data)
  local id = s.trainerIds[17]
  if not (p and id) then return {} end
  local ivs = F.ivsFor(id)
  local otId = rand(0, 65535) * 65536 + rand(0, 65535)
  local out = {}
  for i = 0, 1 do
    local row = p.mons[s.trainerIds[18 + i]]
    if row then
      local mon = F.makeMon(data, row.species, level, row.nature or 0, ivs, F.spread(row.ev or 0),
        row.item, row.moves, otId, rand)
      if mon then out[#out + 1] = mon end
    end
  end
  return out
end

-- FrontierSpeechToString into gStringVar4
function F.bufferSpeech(ctx, id, which)
  local game = ctx.game
  game.stringBuffers = game.stringBuffers or {}
  if id == F.BRAIN or id == nil then game.stringBuffers[4] = "" return end
  local speech = game.data.gen3_frontier_speech
  local words = speech and speech[id + 1] and speech[id + 1][which]
  local line = ""
  if words then
    local ok, text = pcall(require("src.script.EasyChat").phrase, game.data, words, 3)
    if ok and type(text) == "string" then line = text end
  end
  if line == "" then
    local tr = F.trainerRecord(game.data, id)
    line = (tr and tr.name or "") .. ": ..."
  end
  game.stringBuffers[4] = line
end

-- the stashed party (LoadPlayerParty's) and the chosen members' places in it
local function chosenMons(ctx)
  local save = ctx.save
  local party = save.gen3PartyStash or save.party or {}
  local out = {}
  for _, slot in ipairs(save.gen3SelectedOrder or {}) do
    local mon = party[math.floor(tonumber(slot) or 0)]
    if mon then out[#out + 1] = mon end
  end
  return out
end

-- AwardBattleTowerRibbons: past 55 in a row, each chosen member gets the
-- Winning (level 50) or Victory (open) Ribbon if it has none
function F.giveRibbons(ctx, s, mode, lvl)
  if F.streak(s, mode, lvl) <= 55 then return false end
  local key = (lvl ~= F.LVL_50) and "victory" or "winning"
  local count = (mode == F.DOUBLES) and 4 or ((mode >= F.MULTIS) and 2 or 3)
  local any = false
  for i, mon in ipairs(chosenMons(ctx)) do
    if i <= count then
      mon.ribbons = mon.ribbons or {}
      if not mon.ribbons[key] then mon.ribbons[key] = true; any = true end
    end
  end
  return any
end

-- SaveGameFrontier: written with the whole party back (LoadPlayerParty) and
-- the continue point at the lobby spot InitTowerChallenge marked
function F.saveFrontier(ctx)
  local save = ctx.save
  local s = F.state(save)
  local party, stash = save.party, save.gen3PartyStash
  if stash then
    local full = {}
    for i, mon in ipairs(stash) do full[i] = mon end
    save.party, save.gen3PartyStash = full, nil
  end
  save.gen3ContinueAt = s.continueAt
  local special = g3().SPECIALS[96]
  if special then pcall(special, ctx) end
  save.gen3ContinueAt = nil
  save.party, save.gen3PartyStash = party, stash
end

-- ------------------------------------------------ stranded party recovery --
--
-- Reported from play: a Battle Dome entry of three, two of them after the
-- first round, and the rest of the team gone for good once the challenge was
-- over and saved. LoadPlayerParty (special 41) used to delete the stash it
-- restored from, and the Dome restores before EVERY round -- so round 2 had
-- nothing to restore and cut the team down from round 1's two. Fixed in
-- Gen3Commands; this gives back what such a save still holds.
--
-- Two places in a save still carry copies of the player's own Pokemon: the
-- stash (save.gen3PartyStash, SavePlayerParty's) and the Dome's entered three
-- (gen3Frontier.dome.playerMons, InitDomeTrainers). Anything there that is in
-- neither the party nor a box nor the stash is stranded: it goes back to the
-- party when there is room and the save is not mid-challenge, else to the PC.
-- Matched by personality, OT id and species -- a loaded save shares no table
-- references. ONCE PER SAVE (gen3FrontierRecovery), so a Pokemon released or
-- traded away later can never come back from an old copy.
F.RECOVERY_VERSION = 1

local function monKey(mon)
  if type(mon) ~= "table" or not mon.species then return nil end
  return ("%s:%s:%s"):format(tostring(mon.personality or "?"), tostring(mon.otId or "?"), tostring(mon.species))
end

function F.recoverStranded(save)
  if type(save) ~= "table" then return 0 end
  if (tonumber(save.gen3FrontierRecovery) or 0) >= F.RECOVERY_VERSION then return 0 end
  save.gen3FrontierRecovery = F.RECOVERY_VERSION
  local present = {}
  local function mark(mon) local k = monKey(mon); if k then present[k] = true end end
  for _, mon in pairs(save.party or {}) do mark(mon) end
  for _, box in pairs(save.boxes or {}) do
    if type(box) == "table" then for _, mon in pairs(box) do mark(mon) end end
  end
  local candidates = {}
  for _, mon in pairs(save.gen3PartyStash or {}) do candidates[#candidates + 1] = mon end
  local fr = save.gen3Frontier
  local dome = type(fr) == "table" and fr.dome
  for _, mon in pairs(type(dome) == "table" and dome.playerMons or {}) do candidates[#candidates + 1] = mon end
  -- the stash itself is a place the party legitimately sits mid-challenge
  for _, mon in pairs(save.gen3PartyStash or {}) do mark(mon) end
  local stranded = {}
  for _, mon in ipairs(candidates) do
    local k = monKey(mon)
    if k and not present[k] then
      present[k] = true
      stranded[#stranded + 1] = mon
    end
  end
  if #stranded == 0 then return 0 end
  local midChallenge = save.gen3ContinueAt ~= nil
  save.party = save.party or {}
  local Boxes = require("src.pokemon.Boxes")
  local back, toPc = 0, 0
  for _, mon in ipairs(stranded) do
    if not midChallenge and #save.party < 6 then
      save.party[#save.party + 1] = mon
      back = back + 1
    else
      local boxes = Boxes.ensure(save)
      local placed = false
      for i = 1, Boxes.count() do
        local slot = Boxes.firstFree(boxes[i])
        if slot then boxes[i][slot] = mon; placed = true; break end
      end
      if placed then toPc = toPc + 1 end
    end
  end
  require("src.core.Logger").info("gen3 frontier: returned %d stranded Pokemon (%d to the party, %d to the PC)",
    back + toPc, back, toPc)
  save.gen3FrontierRecovered = { party = back, pc = toPc }
  return back + toPc
end

-- ...and on Continue (Game:restoreSave): stand there, once
function F.applyContinue(save)
  local at = type(save) == "table" and save.gen3ContinueAt
  if not (at and at.map and save.player) then return false end
  save.player.map, save.player.x, save.player.y = at.map, at.x, at.y
  save.player.facing = "up"
  save.gen3ContinueAt = nil
  return true
end

-- ------------------------------------------------------ CallFrontierUtilFunc --

-- AppendIfValid / CheckPartyIneligibility
function F.checkIneligible(ctx)
  local save = ctx.save
  local lvlMode = getVar(ctx, F.VAR_RESULT)
  local mode = F.mode(ctx)
  local need = (mode == F.SINGLES) and 3 or ((mode == F.DOUBLES and getVar(ctx, F.VAR_FACILITY) == F.TOWER) and 4
    or ((mode == F.DOUBLES) and 3 or 2))
  local species, items, n = {}, {}, 0
  local Party = require("src.pokemon.Party")
  for _, mon in ipairs(save.party or {}) do
    local sp, item, level = mon.species, mon.item, math.floor(tonumber(mon.level) or 0)
    local ok = sp and not Party.isEgg(mon) and not F.BANNED[sp]
    if ok and lvlMode == F.LVL_50 and level > 50 then ok = false end
    if ok and species[sp] then ok = false end
    if ok and item and items[item] then ok = false end
    if ok then
      species[sp] = true
      if item then items[item] = true end
      n = n + 1
    end
  end
  if n < need then
    -- the caught banned species, buffered for "...{STR_VAR_1} are not allowed"
    local names = {}
    local caught = save.pokedex and (save.pokedex.caught or save.pokedex.owned) or {}
    for _, sp in ipairs({ "MEW", "MEWTWO", "HO_OH", "LUGIA", "CELEBI", "KYOGRE", "GROUDON", "RAYQUAZA", "JIRACHI", "DEOXYS" }) do
      local def = ctx.game.data.pokemon and ctx.game.data.pokemon[sp]
      if caught[sp] or (def and def.dex and caught[def.dex]) then names[#names + 1] = def and def.name or sp end
    end
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[1] = (#names > 0) and (" " .. table.concat(names, ", ") .. " are") or " are"
    setVar(ctx, 0x8004, 1)
  else
    setVar(ctx, 0x8004, 0)
    F.state(save).data[1] = lvlMode
  end
end

-- the tower's row of sBattlePointAwards: min(15, row + 1 + (0, 1, 2, 2))
function F.battlePoints(challengeNum, mode, fac)
  if challengeNum ~= 0 then challengeNum = challengeNum - 1 end
  challengeNum = math.min(29, challengeNum)
  if fac == F.ARENA then return F.ARENA_BP[challengeNum + 1] end
  if fac == F.PIKE then return require("src.script.Gen3BattlePike").BP[challengeNum + 1] end
  if fac == F.PYRAMID then return require("src.script.Gen3BattlePyramid").BP[challengeNum + 1] end
  if fac == F.DOME then return require("src.script.Gen3BattleDome").BP[challengeNum + 1] end
  if fac == F.FACTORY then
    local col = require("src.script.Gen3BattleFactory").BP[(mode == F.DOUBLES) and 1 or 0]
    return col[challengeNum + 1]
  end
  if fac == F.PALACE then
    -- the palace column: 4, 4, 5, 5, 6, 6 ... to 15; doubles one more
    return math.min(15, 4 + math.floor(challengeNum / 2) + ((mode == F.DOUBLES) and 1 or 0))
  end
  local add = ({ [0] = 0, 1, 2, 2 })[mode] or 0
  return math.min(15, challengeNum + 1 + add)
end

function F.utilFunc(ctx, arg)
  local save = ctx.save
  local s = F.state(save)
  local mode, lvl = F.mode(ctx), F.lvl(s)
  local a5, a6 = getVar(ctx, 0x8005), getVar(ctx, 0x8006)
  if arg == 0 then              -- GetChallengeStatus
    local status = math.floor(tonumber(s.data[0]) or 0)
    setVar(ctx, F.VAR_STATUS, (status >= 1 and status <= 4) and status or 255)
  elseif arg == 1 then          -- GetFrontierData
    local v
    if a5 == 5 then v = s.lastOutcome or 0; s.lastOutcome = 0
    elseif a5 == 7 then
      local bit = 2 ^ (getVar(ctx, F.VAR_FACILITY) * 2 + math.min(1, F.symbols(ctx)))
      v = (math.floor(s.brainFlags / bit) % 2 == 1) and 1 or 0
    elseif a5 == 6 then v = 1
    else v = math.floor(tonumber(s.data[a5]) or 0) end
    setVar(ctx, F.VAR_RESULT, v)
  elseif arg == 2 then          -- SetFrontierData
    if a5 == 4 then
      -- gSelectedOrderFromParty is save.gen3SelectedOrder already
      s.selectedPartyMons = {}
      for i, v in ipairs(save.gen3SelectedOrder or {}) do s.selectedPartyMons[i] = v end
    elseif a5 == 7 then
      local bit = 2 ^ (getVar(ctx, F.VAR_FACILITY) * 2 + math.min(1, F.symbols(ctx)))
      if math.floor(s.brainFlags / bit) % 2 == 0 then s.brainFlags = s.brainFlags + bit end
    elseif a5 == 6 then
      -- RECORD_DISABLED stays TRUE: this port has no battle recorder, so the
      -- "Record" choices are not offered rather than offered and failed
      s.data[6] = 1
    else
      s.data[a5] = a6
    end
  elseif arg == 3 then          -- SetSelectedPartyOrder
    if (save.gen3SelectedOrder == nil or #save.gen3SelectedOrder == 0) and s.selectedPartyMons then
      save.gen3SelectedOrder = {}
      for i, v in ipairs(s.selectedPartyMons) do save.gen3SelectedOrder[i] = v end
    end
    g3().reduceToChosen(ctx, true)
  elseif arg == 4 then          -- DoSoftReset
    if ctx.game and ctx.game.returnToTitle then ctx.game:returnToTitle() end
  elseif arg == 9 then          -- GetFrontierBrainStatus
    setVar(ctx, F.VAR_RESULT, F.brainStatus(ctx))
  elseif arg == 10 then         -- IsTrainerFrontierBrain
    setVar(ctx, F.VAR_RESULT, s.opponent == F.BRAIN and 1 or 0)
  elseif arg == 11 then         -- GiveBattlePoints
    local fac = F.facility(ctx)
    -- the Pike counts rooms, fourteen to a challenge (pikeWinStreaks / NUM_PIKE_ROOMS)
    -- (the Dome counts tournaments won, and pays by that count itself)
    local per = (fac == F.PIKE) and 14 or ((fac == F.DOME) and 1 or F.STAGES)
    local pts = F.battlePoints(math.floor(F.streak(s, mode, lvl, fac) / per), mode, fac)
    if s.opponent == F.BRAIN then pts = pts + 10 end
    local G = g3()
    G.setBattlePoints(ctx, G.battlePoints(ctx) + pts)
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[1] = tostring(pts)
  elseif arg == 12 then         -- GetFacilitySymbolCount
    setVar(ctx, F.VAR_RESULT, F.symbols(ctx))
  elseif arg == 13 then         -- GiveFacilitySymbol
    local facility = getVar(ctx, F.VAR_FACILITY)
    local n = (F.symbols(ctx, facility) == 0) and 0 or 1
    Commands.set_flag(ctx, g3().flagKey(F.FLAG_TOWER_SILVER + facility * 2 + n))
  elseif arg == 14 then         -- IsBattleType: was the last battle a trainer's?
    setVar(ctx, F.VAR_RESULT, (s.lastOutcomeKind == "trainer" and a5 ~= 0) and 1 or 0)
  elseif arg == 15 then         -- CheckPartyIneligibility
    F.checkIneligible(ctx)
  elseif arg == 17 then         -- IncrementWinStreak
    local fac = F.facility(ctx)
    F.setStreak(s, mode, lvl, math.min(F.MAX_STREAK, F.streak(s, mode, lvl, fac) + 1), fac)
  elseif arg == 18 then         -- RestoreHeldItems
    F.restoreHeldItems(save)
  elseif arg == 19 then         -- SaveRecordBattle: no recorder, and it says so
    setVar(ctx, F.VAR_RESULT, 0)
    s.data[6] = 1
  elseif arg == 20 then         -- BufferFrontierTrainerName: the opponent's, into STR_VAR_(a5+1)
    local name
    if s.opponent == F.BRAIN then
      local key2 = F.BRAIN_TRAINER[F.facility(ctx)]
      local a = key2 and ctx.game.data.trainers and ctx.game.data.trainers[key2]
      name = a and a.name or key2
    else
      local tr = F.trainerRecord(ctx.game.data, s.opponent)
      name = tr and tr.name
    end
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[a5 + 1] = name or ""
  elseif arg == 22 then         -- SetFacilityBrainObjectEvent
    s.opponent = F.BRAIN
    setVar(ctx, F.VAR_GFX0, F.BRAIN_GFX[F.facility(ctx)] or F.GFX_ANABEL)
  else
    -- 5 SetFrontierTrainers, 6 SaveSelectedParty (the same tables here), 7
    -- the results window, 8 the TV, 14 battle type, 16 e-Reader, 20 name, 21
    -- Sketch
    Logger.debug("gen3 frontier: function %d has nothing to do here", arg)
  end
end

-- the items the chosen members held when the party was stashed, put back
function F.restoreHeldItems(save)
  local stash, items = save.gen3PartyStash, save.gen3StashItems
  if not (stash and items) then return end
  for _, mon in ipairs(save.party or {}) do
    for i, m in ipairs(stash) do
      if m == mon then mon.item = items[i] or nil end
    end
  end
end

-- ------------------------------------------------- the battle (239 arm 0) --

function F.battle(ctx)
  local data = ctx.game and ctx.game.data
  local s = F.state(ctx.save)
  local mode, lvl = F.mode(ctx), F.lvl(s)
  local fac = F.facility(ctx)
  local level = F.enemyLevel(ctx.save, lvl)
  -- the tower's doubles bring four; the palace brings three either way
  local count = (mode == F.DOUBLES and fac == F.TOWER) and 4 or ((mode == F.MULTIS) and 2 or 3)
  local party, name, pic, class, className
  if s.opponent == F.BRAIN then
    party = F.brainParty(data, F.brainTeam(ctx), level, nil, fac)
    local key = F.BRAIN_TRAINER[fac] or "ANABEL"
    local a = data.trainers and data.trainers[key]
    name, pic, class, className = key, a and a.pic, a and a.class, a and a.className
  else
    party = F.trainerParty(data, s.opponent, count, level)
    local tr = F.trainerRecord(data, s.opponent) or {}
    name, pic, class, className = tr.name, tr.pic, tr.class, tr.className
  end
  if not party[1] then
    Logger.warn("gen3 battle tower: no team for opponent %s -- counted as a loss", tostring(s.opponent))
    s.lastOutcome = 2
    return
  end
  local slots = {}
  for i, mon in ipairs(party) do slots[i] = { species = mon.species, level = level, prebuilt = mon } end
  data.trainers[F.TRAINER_KEY] = {
    id = F.TRAINER_KEY, name = name or "TRAINER", pic = pic, class = class, className = className,
    party = slots, parties = { slots }, baseMoney = 0,
  }
  -- the multi rooms: the second trainer's two (none of the first's species
  -- or items) and the partner's two beside yours
  local keyB, ally
  if mode == F.MULTIS and s.opponentB then
    local partyB = F.trainerParty(data, s.opponentB, 2, level, nil, party)
    local trB = F.trainerRecord(data, s.opponentB) or {}
    local slotsB = {}
    for i, mon in ipairs(partyB) do slotsB[i] = { species = mon.species, level = level, prebuilt = mon } end
    if slotsB[1] then
      data.trainers[F.TRAINER_KEY_B] = {
        id = F.TRAINER_KEY_B, name = trB.name or "TRAINER", pic = trB.pic, class = trB.class,
        className = trB.className, party = slotsB, parties = { slotsB }, baseMoney = 0,
      }
      keyB = F.TRAINER_KEY_B
    end
    local pt = F.trainerRecord(data, s.trainerIds[17]) or {}
    local partnerMons = F.partnerParty(data, s, level)
    if partnerMons[1] then
      ally = { party = partnerMons, name = pt.name, pic = pt.pic, trainer = F.PARTNER_KEY }
    end
  end
  -- the held items as they are now, for frontier_restorehelditems
  Commands.start_battle(ctx, "trainer", F.TRAINER_KEY, 1,
    { double = (mode == F.DOUBLES or mode == F.MULTIS) or nil, ally = ally, trainerBKey = keyB,
      canLose = true, frontier = true, noExp = true,
      palace = (fac == F.PALACE) or nil, arena = (fac == F.ARENA) or nil, forfeit = true,
      noItems = (fac ~= F.PYRAMID) or nil })
  -- gBattleOutcome: B_OUTCOME_WON 1, B_OUTCOME_LOST 2 -- and, as every
  -- battle does on its way back to the field (battle_main.c), into
  -- VAR_RESULT, which the arena's battle room switches on directly
  s.lastOutcome = (ctx.lastBattleResult == "win") and 1 or 2
  setVar(ctx, F.VAR_RESULT, s.lastOutcome)
end

-- -------------------------------------------------- CallBattlePalaceFunction --

function F.palaceFunc(ctx, arg)
  local s = F.state(ctx.save)
  local mode, lvl = F.mode(ctx), F.lvl(s)
  local fac = F.PALACE
  local a5, a6 = getVar(ctx, 0x8005), getVar(ctx, 0x8006)
  local act = actives(s, fac)
  if arg == 0 then              -- InitPalaceChallenge
    s.data[0], s.data[2], s.data[3], s.data[6] = 0, 0, 0, 1
    s.trainerIds = {}
    if not act[key(mode, lvl)] then F.setStreak(s, mode, lvl, 0, fac) end
    local ow = ctx.overworld
    if ow and ow.map and ow.player then
      s.continueAt = { map = ow.map.id, x = ow.player.cellX, y = ow.player.cellY }
    end
    s.opponent = nil
  elseif arg == 1 then          -- GetPalaceData
    local v = 0
    if a5 == 0 then v = s.palacePrizeId or 0
    elseif a5 == 1 then v = F.streak(s, mode, lvl, fac)
    elseif a5 == 2 then v = act[key(mode, lvl)] and 1 or 0 end
    setVar(ctx, F.VAR_RESULT, v)
  elseif arg == 2 then          -- SetPalaceData
    if a5 == 0 then s.palacePrizeId = a6
    elseif a5 == 1 then F.setStreak(s, mode, lvl, a6, fac)
    elseif a5 == 2 then act[key(mode, lvl)] = (a6 ~= 0) or nil end
  elseif arg == 3 then          -- GetPalaceCommentId
    local w = F.streak(s, mode, lvl, fac)
    setVar(ctx, F.VAR_RESULT, (w < 50) and love.math.random(0, 2) or ((w < 99) and 3 or 4))
  elseif arg == 4 then          -- SetPalaceOpponent (scripts use tower_setopponent)
    s.opponent = math.floor(5 * love.math.random(0, 254) / 64)
    setVar(ctx, F.VAR_GFX0, F.trainerGfx(ctx.game.data, s.opponent, fac))
  elseif arg == 5 then          -- BufferOpponentIntroSpeech
    F.bufferSpeech(ctx, s.opponent, "before")
  elseif arg == 6 then          -- IncrementPalaceStreak
    F.setStreak(s, mode, lvl, math.min(F.MAX_STREAK, F.streak(s, mode, lvl, fac) + 1), fac)
  elseif arg == 7 then          -- SavePalaceChallenge
    s.data[0] = a5
    setVar(ctx, F.VAR_STATUS, 0)
    s.data[3] = 1
    F.saveFrontier(ctx)
  elseif arg == 8 then          -- SetRandomPalacePrize
    local list = (F.streak(s, mode, lvl, fac) > 41) and F.PALACE_LATE or F.PALACE_EARLY
    s.palacePrize = list[love.math.random(1, #list)]
    s.palacePrizeId = F.itemNumber(ctx.game.data, s.palacePrize)
  elseif arg == 9 then          -- GivePalacePrize
    local item = s.palacePrize
    local ok = item and require("src.inventory.Bag").add(ctx.save, item, 1, ctx.game.data)
    if ok then
      local def = ctx.game.data.items and ctx.game.data.items[item]
      ctx.game.stringBuffers = ctx.game.stringBuffers or {}
      ctx.game.stringBuffers[1] = def and def.name or tostring(item)
      s.palacePrize, s.palacePrizeId = nil, 0
    end
    setVar(ctx, F.VAR_RESULT, ok and 1 or 0)
  end
end

-- -------------------------------------------------- CallBattleArenaFunction --

-- the arena keeps one streak per level mode (arenaWinStreaks[lvlMode]); its
-- battle mode is always singles, so the shared (mode, level) key holds it
function F.arenaFunc(ctx, arg)
  local s = F.state(ctx.save)
  local mode, lvl = F.mode(ctx), F.lvl(s)
  local fac = F.ARENA
  local a5, a6 = getVar(ctx, 0x8005), getVar(ctx, 0x8006)
  local act = actives(s, fac)
  if arg == 0 then              -- InitArenaChallenge
    s.data[0], s.data[2], s.data[3], s.data[6] = 0, 0, 0, 1
    s.trainerIds = {}
    if not act[key(mode, lvl)] then F.setStreak(s, mode, lvl, 0, fac) end
    local ow = ctx.overworld
    if ow and ow.map and ow.player then
      s.continueAt = { map = ow.map.id, x = ow.player.cellX, y = ow.player.cellY }
    end
    s.opponent = nil
  elseif arg == 1 then          -- GetArenaData
    local v = 0
    if a5 == 0 then v = s.arenaPrizeId or 0
    elseif a5 == 1 then v = F.streak(s, mode, lvl, fac)
    elseif a5 == 2 then v = act[key(mode, lvl)] and 1 or 0 end
    setVar(ctx, F.VAR_RESULT, v)
  elseif arg == 2 then          -- SetArenaData
    if a5 == 0 then s.arenaPrizeId = a6
    elseif a5 == 1 then F.setStreak(s, mode, lvl, a6, fac)
    elseif a5 == 2 then act[key(mode, lvl)] = (a6 ~= 0) or nil end
  elseif arg == 3 then          -- SaveArenaChallenge
    s.data[0] = a5
    setVar(ctx, F.VAR_STATUS, 0)
    s.data[3] = 1
    F.saveFrontier(ctx)
  elseif arg == 4 then          -- SetArenaPrize
    local list = (F.streak(s, mode, lvl, fac) > 41) and F.ARENA_LATE or F.ARENA_EARLY
    s.arenaPrize = list[love.math.random(1, #list)]
    s.arenaPrizeId = F.itemNumber(ctx.game.data, s.arenaPrize)
  elseif arg == 5 then          -- GiveArenaPrize
    local item = s.arenaPrize
    local ok = item and require("src.inventory.Bag").add(ctx.save, item, 1, ctx.game.data)
    if ok then
      local def = ctx.game.data.items and ctx.game.data.items[item]
      ctx.game.stringBuffers = ctx.game.stringBuffers or {}
      ctx.game.stringBuffers[1] = def and def.name or tostring(item)
      s.arenaPrize, s.arenaPrizeId = nil, 0
    end
    setVar(ctx, F.VAR_RESULT, ok and 1 or 0)
  elseif arg == 6 then          -- BufferArenaOpponentName
    local name
    if s.opponent == F.BRAIN then name = "GRETA"
    else
      local tr = F.trainerRecord(ctx.game.data, s.opponent)
      name = tr and tr.name
    end
    ctx.game.stringBuffers = ctx.game.stringBuffers or {}
    ctx.game.stringBuffers[1] = name or ""
  end
end

-- an item key's cartridge number (the scripts compare the prize to zero)
function F.itemNumber(data, item)
  local def = data and data.items and data.items[item]
  return math.floor(tonumber(def and (def.index or def.id_num or def.num)) or 1)
end

-- ------------------------------------------------------------- install --

function F.install()
  local G = g3()
  local S = G.SPECIALS
  local tentUtil, tentTower, tentBattle, stash = S[234], S[235], S[239], S[40]
  -- A TENT CHALLENGE IS ITS LEVEL MODE, not its facility number: Verdanturf's
  -- tent and the Battle Palace are both FRONTIER_FACILITY_PALACE, and the tent
  -- lobby sets FRONTIER_LVL_TENT as it starts one
  local function inTent(ctx)
    return F.lvl(F.state(ctx.save)) == F.LVL_TENT
  end
  local function towerHere(ctx) return getVar(ctx, F.VAR_FACILITY) == F.TOWER and not inTent(ctx) end
  local function frontierHere(ctx)
    local fac = getVar(ctx, F.VAR_FACILITY)
    return (fac == F.TOWER or fac == F.PALACE or fac == F.ARENA or fac == F.FACTORY or fac == F.PIKE
            or fac == F.PYRAMID or fac == F.DOME)
           and not inTent(ctx)
  end
  -- 5, 7, 8 and 21 are answered here with nothing (see utilFunc's last arm)
  -- rather than left to the generic stub, which zeroes VAR_RESULT -- and the
  -- arena's battle room reads VAR_RESULT after `frontier_resetsketch`
  local UTIL_ARMS = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [14] = true, [15] = true, [17] = true,
    [20] = true,
    [18] = true, [19] = true, [21] = true, [22] = true }
  S[234] = function(ctx)
    local arg = getVar(ctx, 0x8004)
    if frontierHere(ctx) and UTIL_ARMS[arg] then F.utilFunc(ctx, arg) return end
    return tentUtil and tentUtil(ctx)
  end
  -- Verdanturf's tent (245): arm 3 SetVerdanturfTentTrainerGfx and arm 4
  -- BufferVerdanturfTentTrainerIntro, which the tent handlers leave alone
  local verdanturf = S[245]
  S[245] = function(ctx)
    local arg = getVar(ctx, 0x8004)
    local tent = G.tentRecord and G.tentRecord(ctx)
    local s = F.state(ctx.save)
    local pick = s.opponent
    local tr = tent and type(pick) == "number" and tent.trainers and tent.trainers[pick]
    if tr and arg == 3 then
      setVar(ctx, F.VAR_GFX0, F.CLASS_GFX[tonumber(tr.facilityClass) or -1] or F.CLASS_GFX[16])
      return
    elseif tr and arg == 4 then
      local speech = ctx.game.data.gen3_frontier_speech
      local words = speech and speech.tents and speech.tents[getVar(ctx, F.VAR_FACILITY)]
      words = words and words[pick] and words[pick].before
      local line = ""
      if words then
        local ok, text = pcall(require("src.script.EasyChat").phrase, ctx.game.data, words, 3)
        if ok and type(text) == "string" then line = text end
      end
      ctx.game.stringBuffers = ctx.game.stringBuffers or {}
      ctx.game.stringBuffers[4] = line
      return
    end
    return verdanturf and verdanturf(ctx)
  end
  S[235] = function(ctx)
    local arg = getVar(ctx, 0x8004)
    if towerHere(ctx) or (frontierHere(ctx) and arg == 3) then F.towerFunc(ctx, arg) return end
    -- the Dome's battle room borrows tower_getopponentintro (arm 7)
    if frontierHere(ctx) and arg == 7 and getVar(ctx, F.VAR_FACILITY) == F.DOME then F.towerFunc(ctx, arg) return end
    return tentTower and tentTower(ctx)
  end
  S[239] = function(ctx)
    local arg = getVar(ctx, 0x8004)
    if arg == 0 and towerHere(ctx) then F.battle(ctx) return end
    -- SPECIAL_BATTLE_PALACE (4): the Battle Palace's, when not a tent
    if arg == 4 and frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.PALACE then F.battle(ctx) return end
    -- SPECIAL_BATTLE_ARENA (5)
    if arg == 5 and frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.ARENA then F.battle(ctx) return end
    -- SPECIAL_BATTLE_FACTORY (6): your rentals
    if arg == 6 and frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.FACTORY then
      require("src.script.Gen3BattleFactory").battle(ctx)
      return
    end
    -- SPECIAL_BATTLE_PIKE_SINGLE (7) and _DOUBLE (9): the team as it stands
    -- SPECIAL_BATTLE_DOME (3): the two each side chose
    if arg == 3 and frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.DOME then
      require("src.script.Gen3BattleDome").battle(ctx)
      return
    end
    -- SPECIAL_BATTLE_PYRAMID (10): Brandon at the summit
    if arg == 10 and frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.PYRAMID then F.battle(ctx) return end
    if frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.PIKE then
      if arg == 7 then F.battle(ctx) return end
      if arg == 9 then require("src.script.Gen3BattlePike").doubleBattle(ctx) return end
    end
    return tentBattle and tentBattle(ctx)
  end
  local palaceFallback = S[237]
  S[237] = function(ctx)
    if frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.PALACE then
      F.palaceFunc(ctx, getVar(ctx, 0x8004))
      return
    end
    -- the arena's and the factory's battle rooms borrow `palace_getopponentintro` (arm 5)
    local fac = getVar(ctx, F.VAR_FACILITY)
    if frontierHere(ctx) and (fac == F.ARENA or fac == F.FACTORY) and getVar(ctx, 0x8004) == 5 then
      F.bufferSpeech(ctx, F.state(ctx.save).opponent, "before")
      return
    end
    return palaceFallback and palaceFallback(ctx)
  end
  -- 241 CallBattleFactoryFunction
  local factoryFallback = S[241]
  S[241] = function(ctx)
    if frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.FACTORY then
      require("src.script.Gen3BattleFactory").func(ctx, getVar(ctx, 0x8004))
      return
    end
    return factoryFallback and factoryFallback(ctx)
  end
  -- 242 CallBattlePikeFunction
  require("src.script.Gen3BattlePike").install()
  require("src.script.Gen3BattlePyramid").install()
  require("src.script.Gen3BattleDome").install()
  -- 240 CallBattleArenaFunction
  local arenaFallback = S[240]
  S[240] = function(ctx)
    if frontierHere(ctx) and getVar(ctx, F.VAR_FACILITY) == F.ARENA then
      F.arenaFunc(ctx, getVar(ctx, 0x8004))
      return
    end
    return arenaFallback and arenaFallback(ctx)
  end
  -- SavePlayerParty, and what each member held then
  S[40] = function(ctx)
    if stash then stash(ctx) end
    local items = {}
    for i, mon in ipairs(ctx.save.gen3PartyStash or {}) do items[i] = mon.item or false end
    ctx.save.gen3StashItems = items
  end
  -- 448 BufferBattleTowerElevatorFloors: where MoveElevator goes
  S[448] = function(ctx)
    local s = F.state(ctx.save)
    local w = F.streak(s, F.mode(ctx), F.lvl(s))
    local floor = 12
    for i, t in ipairs({ 7, 14, 21, 28, 35, 49, 63, 77, 91 }) do
      if t > w then floor = i + 4 break end
    end
    setVar(ctx, 0x8005, 4)
    setVar(ctx, 0x8006, floor)
  end
  -- 524 RemoveRecordsWindow: the window it removes is not drawn here
  S[524] = function() end
end

return F
