-- PLATINUM'S BATTLE CASTLE (overlay104 battle_castle.c, battle_castle_helpers.c,
-- frscrcmd_battle_castle.c), the facility half of the Castle's frontier scene
-- script (fr_script member 0, scenes 11, 12 and 13).
--
-- Seven battles a round with three of your own Pokemon at level 50 (copies,
-- items taken away), their HP, PP and status carried from battle to battle.
-- Castle Points pay for everything: 10 on entering, then after each win
-- 3 a Pokemon standing, 3 a full-HP one (2 above half, 1 below), 1 with no
-- status, 8 / 6 / 4 for spending at most 5 / 10 / 15 PP, and 7 for each
-- opponent raised five levels -- at least 1. Spent in the two apps (healing,
-- rented Berries and items, the opponent's identity, level, stats and
-- moves), on the three ranks that unlock more of them, and on a Pass (50)
-- past a battle. The opponents come from the same ranges the Factory's do,
-- their teams from the Tower's sets; Darach, the Castle Valet, is the 21st
-- and 49th in singles. Everyone is level 50.
--
-- NOT PORTED: the multi challenges (link play), the apps' own screens (the
-- choices are src/ui/Gen4CastleScreen.lua's text menus), the AI mask by
-- round (BattleCastle_GetAIMask -- recorded on the trainer, nothing reads it
-- yet), the emblem frame and the particle twinkles.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local VM = require("src.script.Gen4FrontierVM")
local Fr = require("src.script.Gen4FrontierScrCmds")

local B = {}

B.SINGLE, B.DOUBLE, B.MULTI, B.MULTI_WFC = 0, 1, 2, 3
B.PER_ROUND = 7                  -- CASTLE_BATTLES_PER_ROUND
B.SILVER, B.GOLD = 21, 49        -- CASTLE_STREAK_SILVER_BATTLE / _GOLD_BATTLE
B.MAX_ROUNDS = 8                 -- CASTLE_MAX_DISTINCT_ROUNDS
B.LEVEL = 50                     -- CASTLE_MAX_LEVEL
B.DARACH_SILVER, B.DARACH_GOLD = 313, 314
B.BP_SOLO = { [0] = 0, 3, 3, 4, 4, 5, 5, 7, 7 }
B.BP_WIFI = { [0] = 0, 8, 9, 11, 12, 14, 15, 18, 18 }
B.CP_MAX, B.CP_START, B.PASS_COST = 9999, 10, 50

-- sBattleCastleOpponentPools: { normalMin, normalMax, finalMin, finalMax }
B.OPPONENT_POOLS = {
  { 0, 99, 100, 119 }, { 80, 119, 120, 139 }, { 100, 139, 140, 159 }, { 120, 159, 160, 179 },
  { 140, 179, 180, 199 }, { 160, 199, 200, 219 }, { 180, 219, 220, 239 }, { 200, 299, 200, 299 },
}

-- the ranks (BATTLE_CASTLE_RANK_*), each 1 to start
B.RANK_HEALING, B.RANK_RENTALS, B.RANK_SUMMARY = 0, 1, 2
B.RANK_MAX = { [0] = 3, 3, 2 }
B.RANK_UP_COST = { [0] = { 0, 100, 100 }, { 0, 100, 150 }, { 0, 50, 50 } }   -- sRankUpCosts[type][rank - 1]

-- the self app (self_app.c)
B.HEAL_HP, B.HEAL_PP, B.HEAL_ALL = 1, 2, 3
B.HEAL_COST = { 10, 8, 12 }                        -- sHealingCosts
B.HEAL_RANK = { 1, 2, 3 }                          -- sHealMenuEntries[][0]
B.ITEMS = { 221, 217, 271, 253, 277, 269, 286, 296, 272, 273, 236, 258, 214, 230, 275, 234, 213, 232,
  265, 276, 220, 297, 287, 266, 267, 268, 270 }    -- sItemsForRent
B.ITEM_PRICES = { 10, 15, 5, 15, 10, 10, 10, 10, 10, 10, 15, 15, 5, 15, 10, 20, 20, 20, 20, 20, 20, 20,
  20, 20, 20, 20, 20 }
B.BERRIES = { 149, 150, 151, 152, 153, 156, 157, 158, 201, 202, 203, 204, 205, 206, 207, 184, 185, 186,
  187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200 }   -- sBerriesForRent
B.BERRY_PRICES = { 2, 2, 2, 2, 2, 2, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
  5, 5, 5 }
B.ITEMS_BY_RANK = { 12, 12, #B.ITEMS }             -- sItemsAvailableByRank
B.BERRIES_BY_RANK = { 8, 8, #B.BERRIES }           -- sBerriesAvailableByRank
B.ITEMS_RANK = 2                                   -- sRentalMenuEntries[1][0]: items from rank 2

-- the opponent app (opponent_app.c's CP_COST_*)
B.COST_IDENTITY, B.COST_LEVEL_UP, B.COST_LEVEL_DOWN, B.COST_STATS, B.COST_MOVES = 1, 1, 15, 2, 5
B.ADJ_NONE, B.ADJ_UP, B.ADJ_DOWN = 0, 1, 2         -- LEVEL_ADJUSTMENT_*

local function rand16() return love.math.random(0, 65535) end
local function BT() return require("src.pokemon.Gen4BattleTower") end
local function C() return require("src.script.Gen4BattleTowerCommands") end

function B.isMulti(t) return t == B.MULTI or t == B.MULTI_WFC end
function B.partySize(t) return B.isMulti(t) and 2 or 3 end

-- ------------------------------------------------------------- the records --

-- the Castle's records: the persistent streak flags and Darach's intro, and
-- the frontier stats by challenge type -- latest streak, CP, CP spent, the
-- three ranks, the record streak and the CP held at it
function B.record(save)
  save.gen4Castle = save.gen4Castle or {}
  local r = save.gen4Castle
  for _, k in ipairs({ "streakActive", "latest", "cp", "spent", "ranks", "records", "recordCP" }) do
    r[k] = r[k] or {}
  end
  return r
end
function B.cp(save, t) return B.record(save).cp[t] or 0 end
function B.rank(save, t, kind)
  local r = B.record(save)
  r.ranks[t] = r.ranks[t] or {}
  return r.ranks[t][kind] or 1
end
function B.setRank(save, t, kind, v)
  local r = B.record(save)
  r.ranks[t] = r.ranks[t] or {}
  r.ranks[t][kind] = v
end
local function resetRanks(save, t) for k = 0, 2 do B.setRank(save, t, k, 1) end end

-- BattleCastle_ReceiveCastlePoints: capped at 9999
function B.receiveCP(save, t, n)
  local r = B.record(save)
  r.cp[t] = math.min(B.CP_MAX, (r.cp[t] or 0) + n)
  local R = require("src.pokemon.Gen4GameRecords")
  R.add(save, R.ID.CASTLE_POINTS_RECEIVED, n)
end
-- BattleCastle_SpendCastlePoints: the total spent, capped too
function B.spendCP(save, t, n)
  local r = B.record(save)
  r.cp[t] = math.max(0, (r.cp[t] or 0) - n)
  r.spent[t] = math.min(B.CP_MAX, (r.spent[t] or 0) + n)
end

-- BattleCastle_ClearActiveStreak (the lobby's DELETE_ACTIVE_STREAK)
function B.clearStreak(save, t)
  local r = B.record(save)
  r.streakActive[t] = nil
  r.latest[t], r.cp[t] = 0, 0
  resetRanks(save, t)
end

-- ------------------------------------------------------------- the Pokemon --

-- a mon at `level`, experience and stats recalculated the way
-- Pokemon_CalcLevelAndStats does: the HP moves by as much as the maximum
-- did, and a fainted one stays fainted
function B.setLevel(data, mon, level)
  local def = require("src.pokemon.Gen4Forms").definition(data, mon)
  if not def then return mon end
  local oldMax = mon.stats and mon.stats.hp or 0
  mon.level = level
  mon.exp = require("src.pokemon.Growth").expForLevel(def.growthRate, level)
  mon.stats = require("src.pokemon.Stats").calc(def, level, mon.ivs or mon.dvs, mon.statExp, mon.evs, mon.nature)
  if oldMax == 0 then mon.hp = mon.stats.hp
  elseif (mon.hp or 0) > 0 then mon.hp = math.max(1, math.min(mon.stats.hp, mon.hp + mon.stats.hp - oldMax)) end
  return mon
end

-- BattleCastle_Init's party: copies of the chosen, no held items, above 50
-- brought down to 50
function B.team(data, save, slots, n)
  local out = {}
  for i = 0, n - 1 do
    local src = (save.party or {})[(slots[i] or 0) + 1]
    if src then
      local mon = C().copy(src)
      mon.item = nil
      if (tonumber(mon.level) or 1) > B.LEVEL then B.setLevel(data, mon, B.LEVEL) end
      out[#out + 1] = mon
    end
  end
  return out
end

local function moveMaxPP(data, slot)
  local def = data.moves and data.moves[slot.id]
  return require("src.pokemon.Pokemon").maxPP(def, slot)
end
function B.missingPP(data, mon)
  for _, m in ipairs(mon.moves or {}) do
    if (m.pp or 0) < moveMaxPP(data, m) then return true end
  end
  return false
end
local function totalPP(mon)
  local n = 0
  for _, m in ipairs(mon.moves or {}) do n = n + (m.pp or 0) end
  return n
end

-- ---------------------------------------------------------------- the run --

-- BattleCastle_Init
function B.init(data, save, resuming, challengeType, s1, s2, s3)
  local r = B.record(save)
  local f = { save = save, data = data, trainerIDs = {}, slots = {}, identity = {}, levelAdj = {},
              statsUnlocked = {}, movesUnlocked = {}, startingPP = {}, selected = {} }
  if resuming == 0 then
    f.challengeType, f.currentBattle = challengeType, 0
    r.current = nil
    if r.streakActive[challengeType] then
      f.currentStreak = r.latest[challengeType] or 0
    else
      f.currentStreak = 0
      r.cp[challengeType], r.spent[challengeType] = 0, 0
      resetRanks(save, challengeType)
    end
    f.slots[0], f.slots[1], f.slots[2] = s1, s2, s3
    f.initialCP = r.cp[challengeType] or 0
    B.receiveCP(save, challengeType, B.CP_START)
    f.team = B.team(data, save, f.slots, B.partySize(challengeType))
  else
    local cur = r.current or {}
    f.challengeType, f.currentBattle = cur.challengeType or 0, cur.currentBattle or 0
    f.currentStreak = r.latest[f.challengeType] or 0
    for i = 0, 2 do f.slots[i] = (cur.slots or {})[i] or i end
    f.team = C().copy(cur.team or {})
    f.initialCP = r.cp[f.challengeType] or 0
  end
  f.currentRound = math.floor(f.currentStreak / B.PER_ROUND)
  return f
end

function B.round(f) return f.currentRound end

-- BattleCastle_GetOpponentTrainerID: Darach is checked before the round is
-- capped, against the streak this battle would make
function B.opponentTrainerID(challengeType, round, offset)
  if challengeType == B.SINGLE then
    local streak = round * B.PER_ROUND + offset + 1
    if streak == B.SILVER then return B.DARACH_SILVER elseif streak == B.GOLD then return B.DARACH_GOLD end
  end
  if round >= #B.OPPONENT_POOLS then round = #B.OPPONENT_POOLS - 1 end
  local p = B.OPPONENT_POOLS[round + 1]
  local min, spread
  if offset == B.PER_ROUND - 1 or offset == B.PER_ROUND * 2 - 1 then min, spread = p[3], p[4] - p[3]
  else min, spread = p[1], p[2] - p[1] end
  return min + rand16() % spread
end

-- BattleCastle_PickOpponentTrainers: none twice
function B.pickTrainers(challengeType, round, ids, n)
  local i = 0
  while i < n do
    ids[i] = B.opponentTrainerID(challengeType, round, i)
    local dup = false
    for j = 0, i - 1 do if ids[j] == ids[i] then dup = true break end end
    if not dup then i = i + 1 end
  end
end

-- SelectPokemonForTrainer: the trainer's sets, no species and no item twice
function B.pickSets(data, trainerID, n)
  local rec = data.gen4_battle_tower
  local tr = rec and rec.trainers and rec.trainers[trainerID]
  if not (tr and tr.sets and #tr.sets > 0) then return {} end
  local picked, guard = {}, 0
  while #picked < n and guard < 20000 do
    guard = guard + 1
    local id = tr.sets[rand16() % #tr.sets + 1]
    local s = rec.sets[id]
    local ok = s ~= nil
    for _, q in ipairs(picked) do
      local t = rec.sets[q]
      if ok and (t.species == s.species or t.item == s.item) then ok = false end
    end
    if ok then picked[#picked + 1] = id end
  end
  return picked
end

-- BattleFrontier_LoadFrontierPokemon: entries of the trainer's IVs
function B.entries(data, setIDs, ivs)
  local sets = data.gen4_battle_tower and data.gen4_battle_tower.sets or {}
  local out = {}
  for i, id in ipairs(setIDs) do
    local otId = rand16() + rand16() * 65536
    out[i] = BT().monFromSet(sets[id], id, ivs, otId, rand16)
  end
  return out
end

-- BattleFrontier_GetPokemonForTrainers for this battle's trainer
function B.opponentTeam(data, f)
  local id = f.trainerIDs[f.currentBattle]
  f.monSetIDs = B.pickSets(data, id, B.partySize(f.challengeType))
  f.opponentEntries = B.entries(data, f.monSetIDs, BT().ivsFor(id or 0))
end

-- BattleCastle_SetupOpponentsParty: the entries as level-50 Pokemon
function B.setupOpponentsParty(game, f)
  f.opponentParty = C().opponentMons(game, f.opponentEntries or {}, B.LEVEL)
end

local function recordStartingPP(f)
  f.startingPP = {}
  for i, mon in ipairs(f.team or {}) do f.startingPP[i] = totalPP(mon) end
end

-- SelectTrainersAndFirstBattlesMons / LoadTrainersAndMonsFromSave
function B.loadRound(data, f, resuming)
  if resuming == 0 then
    recordStartingPP(f)
    B.pickTrainers(f.challengeType, B.round(f), f.trainerIDs, B.PER_ROUND * 2)
    B.opponentTeam(data, f)
  else
    local cur = B.record(f.save).current or {}
    for k, v in pairs(cur.trainerIDs or {}) do f.trainerIDs[k] = v end
    f.monSetIDs = C().copy(cur.monSetIDs or {})
    f.opponentEntries = B.entries(data, f.monSetIDs, BT().ivsFor(f.trainerIDs[f.currentBattle] or 0))
  end
end

-- BattleCastle_RevivePokemon: the fainted at 1 HP, every status cleared
function B.revive(team)
  for _, mon in ipairs(team or {}) do
    if (mon.hp or 0) == 0 then mon.hp = 1 end
    mon.status = nil
  end
end

-- BattleCastle_PrepForNextBattle: this battle's PP noted, the team revived,
-- the opponent app's purchases forgotten
function B.prepForNextBattle(f)
  recordStartingPP(f)
  B.revive(f.team)
  f.identity, f.levelAdj, f.statsUnlocked, f.movesUnlocked = {}, {}, {}, {}
end

-- BattleCastle_CalcCPEarnedFromBattle (and whether one of the team fainted)
function B.cpFromBattle(f)
  local factors = {}
  for i = 0, 8 do factors[i] = 0 end
  f.monFainted = false
  local remaining = 0
  for _, mon in ipairs(f.team or {}) do
    local hp, max = mon.hp or 0, mon.stats and mon.stats.hp or 0
    if hp > 0 then
      factors[0] = factors[0] + 1
      if hp == max then factors[1] = factors[1] + 1
      elseif hp >= math.floor(max / 2) then factors[2] = factors[2] + 1
      else factors[3] = factors[3] + 1 end
      if not mon.status then factors[4] = factors[4] + 1 end
    else
      f.monFainted = true
    end
    remaining = remaining + totalPP(mon)
  end
  for i = 1, B.partySize(f.challengeType) do
    if f.levelAdj[i] == B.ADJ_UP then factors[8] = factors[8] + 1 end
  end
  local starting = 0
  for _, n in pairs(f.startingPP or {}) do starting = starting + n end
  local used = starting - remaining
  if used <= 5 then factors[5] = factors[5] + 1
  elseif used <= 10 then factors[6] = factors[6] + 1
  elseif used <= 15 then factors[7] = factors[7] + 1 end
  local cp = factors[0] * 3 + factors[1] * 3 + factors[2] * 2 + factors[3] + factors[4]
           + factors[5] * 8 + factors[6] * 6 + factors[7] * 4 + factors[8] * 7
  if cp <= 0 then cp = 1 end
  return cp
end

-- BattleCastle_GetEarnedBP
function B.earnedBP(f)
  local t = (f.challengeType == B.SINGLE or f.challengeType == B.DOUBLE) and B.BP_SOLO or B.BP_WIFI
  local bp = t[math.min(f.currentRound, B.MAX_ROUNDS)]
  if f.challengeType == B.SINGLE and (f.currentStreak == B.SILVER or f.currentStreak == B.GOLD) then bp = 20 end
  return bp
end

-- BattleCastle_Save (0 a round, 1 a loss, 2 a quick save)
function B.save(f, kind)
  local r = B.record(f.save)
  local t = f.challengeType
  r.current = { challengeType = t, currentBattle = f.currentBattle, saved = true, trainerIDs = {},
    slots = { [0] = f.slots[0], f.slots[1], f.slots[2] }, team = C().copy(f.team or {}),
    monSetIDs = C().copy(f.monSetIDs or {}) }
  for i, v in pairs(f.trainerIDs) do r.current.trainerIDs[i] = v end
  r.latest[t] = f.currentStreak
  if kind ~= 2 then
    local before = r.records[t] or 0
    if f.currentStreak > before then r.records[t] = f.currentStreak end
    local cp = r.cp[t] or 0
    if f.currentStreak == before then r.recordCP[t] = math.max(r.recordCP[t] or 0, cp)
    elseif before < (r.records[t] or 0) then r.recordCP[t] = cp end
    r.streakActive[t] = f.saveStreak and true or nil
  end
end

-- BattleCastle_SaveOnLoss: the ranks back to 1 first
function B.saveOnLoss(f)
  resetRanks(f.save, f.challengeType)
  B.save(f, 1)
end
function B.saveOnRound(f)
  f.saveStreak = true
  if f.currentRound < B.MAX_ROUNDS then f.currentRound = f.currentRound + 1 end
  f.currentBattle = 0
  B.save(f, 0)
end

-- ------------------------------------------------------------ the apps --
-- Each answers (ok, reason): reason the self / opponent app's message key
-- when nothing was bought.

local function canPay(f, cost) return B.cp(f.save, f.challengeType) >= cost end

-- MAIN_SUBSTATE_HEAL_YES_NO and HealPokemon (Max Potion / Max Elixir)
function B.heal(f, i, option)
  local mon = f.team[i]
  if not mon then return false end
  if B.rank(f.save, f.challengeType, B.RANK_HEALING) < B.HEAL_RANK[option] then return false, "rank" end
  if not canPay(f, B.HEAL_COST[option]) then return false, "cp" end
  local fullHP = (mon.hp or 0) == (mon.stats and mon.stats.hp)
  local missing = B.missingPP(f.data, mon)
  if (option == B.HEAL_HP and fullHP) or (option == B.HEAL_PP and not missing)
     or (option == B.HEAL_ALL and fullHP and not missing) then
    return false, "nobenefit"
  end
  B.spendCP(f.save, f.challengeType, B.HEAL_COST[option])
  if (option == B.HEAL_HP or option == B.HEAL_ALL) and (mon.hp or 0) > 0 then mon.hp = mon.stats.hp end
  if option == B.HEAL_PP or option == B.HEAL_ALL then
    for _, m in ipairs(mon.moves or {}) do m.pp = moveMaxPP(f.data, m) end
  end
  return true
end

-- the rental lists at the current rank: { item, price }
function B.rentals(f, kind)
  local rank = B.rank(f.save, f.challengeType, B.RANK_RENTALS)
  local ids, prices, n
  if kind == "berries" then ids, prices, n = B.BERRIES, B.BERRY_PRICES, B.BERRIES_BY_RANK[rank]
  else
    if rank < B.ITEMS_RANK then return {} end
    ids, prices, n = B.ITEMS, B.ITEM_PRICES, B.ITEMS_BY_RANK[rank]
  end
  local out = {}
  for k = 1, n do out[k] = { item = ids[k], price = prices[k] } end
  return out
end

-- RentItem: held from now on, whatever was held before gone
function B.rent(f, i, item, price)
  local mon = f.team[i]
  if not mon then return false end
  if not canPay(f, price) then return false, "cp" end
  B.spendCP(f.save, f.challengeType, price)
  mon.item = item
  return true
end

-- IncreaseRank (both apps): the cost by the rank held, none past the top
function B.rankUp(f, kind)
  local rank = B.rank(f.save, f.challengeType, kind)
  if rank >= B.RANK_MAX[kind] then return false, "max" end
  local cost = B.RANK_UP_COST[kind][rank + 1]
  if not canPay(f, cost) then return false, "cp" end
  B.spendCP(f.save, f.challengeType, cost)
  B.setRank(f.save, f.challengeType, kind, rank + 1)
  return true
end

-- RevealPokemonInSlot
function B.reveal(f, i)
  if f.identity[i] then return true end
  if not canPay(f, B.COST_IDENTITY) then return false, "cp" end
  B.spendCP(f.save, f.challengeType, B.COST_IDENTITY)
  f.identity[i] = true
  return true
end

-- UpdateLevelAdjustment: from 50 to 55 or 45, or back to 50 from the other
function B.adjustLevel(f, i, adj)
  local mon = f.opponentParty and f.opponentParty[i]
  if not mon then return false end
  local cur = f.levelAdj[i] or B.ADJ_NONE
  if cur == adj then return false, (adj == B.ADJ_UP) and "highest" or "lowest" end
  local cost = (adj == B.ADJ_UP) and B.COST_LEVEL_UP or B.COST_LEVEL_DOWN
  if not canPay(f, cost) then return false, "cp" end
  B.spendCP(f.save, f.challengeType, cost)
  f.levelAdj[i] = (cur == B.ADJ_NONE) and adj or B.ADJ_NONE
  local level = ({ [B.ADJ_NONE] = 50, [B.ADJ_UP] = 55, [B.ADJ_DOWN] = 45 })[f.levelAdj[i]]
  B.setLevel(f.data, mon, level)
  mon.hp = mon.stats.hp
  return true
end

-- TryToBuySummaryScreen: the stats (2), the moves (5, rank 2)
function B.unlockStats(f, i)
  if f.statsUnlocked[i] then return true end
  if not canPay(f, B.COST_STATS) then return false, "cp" end
  B.spendCP(f.save, f.challengeType, B.COST_STATS)
  f.statsUnlocked[i] = true
  return true
end
function B.unlockMoves(f, i)
  if f.movesUnlocked[i] then return true end
  if B.rank(f.save, f.challengeType, B.RANK_SUMMARY) < 2 then return false, "rank" end
  if not canPay(f, B.COST_MOVES) then return false, "cp" end
  B.spendCP(f.save, f.challengeType, B.COST_MOVES)
  f.movesUnlocked[i] = true
  return true
end

-- BattleCastle_GetAIMask: none for rounds 1-2, basic for 3-4, expert after
-- and against Darach
function B.aiMask(f)
  local id = f.trainerIDs[f.currentBattle]
  if f.challengeType == B.SINGLE and (id == B.DARACH_SILVER or id == B.DARACH_GOLD) then return 7 end
  local r = B.round(f) + 1
  if r <= 2 then return 0 elseif r <= 4 then return 1 end
  return 7
end

-- ------------------------------------------------------------ the lowering --

local F = VM.facility
local emit = VM.emit
F.initbattlecastle = function(ins, s)
  emit(s, { "fr_bc_init", ins.args[1], ins.args[2], ins.args[3], ins.args[4], ins.args[5] })
end
F.loadtrainersforround = function(ins, s) emit(s, { "fr_bc_load_round", ins.args[1] }) end
F.freebattlecastle = function(_, s) emit(s, { "fr_bc_free" }) end
F.openbattlecastleselfapp = function(_, s) emit(s, { "fr_bc_app", "self" }) end
F.openbattlecastleopponentapp = function(_, s) emit(s, { "fr_bc_app", "opponent" }) end
F.dummyopenbattlecastleapp = function() end
F.battlecastle_cleanupbattle = function() end
F.battlecastle_startbattle = function(_, s) emit(s, { "fr_bc_battle" }) end
F.battlecastle_checkwonbattle = function(ins, s) emit(s, { "fr_bc_won", ins.args[1] }) end
F.battlecastle_setupfirstopponent = function(_, s) emit(s, { "fr_bc_first_opponent" }) end
F.battlecastle_setupnextopponent = function(_, s) emit(s, { "fr_bc_next_opponent" }) end
F.callbattlecastlefunction = function(ins, s)
  emit(s, { "fr_bc_call", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
end
F.battlecastle_printrainerintro = function(ins, s) emit(s, { "fr_bc_intro", ins.args[1] }) end
F.showcastlepointswindows = function(_, s) emit(s, { "fr_bc_cp_window", 1 }) end
F.clearcastlepointswindows = function(_, s) emit(s, { "fr_bc_cp_window", 0 }) end
F.reprintcastlepointsinfo = function() end
F.getcurrentcastlepoints = function(ins, s) emit(s, { "fr_bc_get_cp", ins.args[1], ins.args[2] }) end
F.spendcastlepoints = function(ins, s) emit(s, { "fr_bc_spend_cp", ins.args[1], ins.args[2] }) end
F.receivecastlepoints = function(ins, s) emit(s, { "fr_bc_receive_cp", ins.args[1], ins.args[2] }) end
-- the link commands: alone, sent and answered at once
F.battlecastle_sendcommmessage = function(ins, s) emit(s, { "fr_set", ins.args[3], 1 }) end
F.battlecastle_waitforcommresponses = function() end

local function castle(ctx) return ctx.game.gen4BattleCastle end

function Commands.fr_bc_init(ctx, resuming, challengeType, s1, s2, s3)
  local v = Fr.value
  ctx.game.gen4BattleCastle = B.init(ctx.game.data, ctx.save, v(ctx, resuming), v(ctx, challengeType),
    v(ctx, s1), v(ctx, s2), v(ctx, s3))
end
function Commands.fr_bc_free(ctx) ctx.game.gen4BattleCastle = nil end
function Commands.fr_bc_load_round(ctx, resuming)
  local f = castle(ctx)
  if f then B.loadRound(ctx.game.data, f, Fr.value(ctx, resuming)) end
end
function Commands.fr_bc_first_opponent(ctx)
  local f = castle(ctx)
  if f then B.setupOpponentsParty(ctx.game, f) end
end
function Commands.fr_bc_next_opponent(ctx)
  local f = castle(ctx)
  if not f then return end
  B.opponentTeam(ctx.game.data, f)
  B.setupOpponentsParty(ctx.game, f)
end

-- the Castle Points window beside the menu (BattleCastle_ShowPlayerInfoWindows)
function Commands.fr_bc_cp_window(ctx, on)
  local sc = ctx.frontierScene
  if not sc then return end
  if tonumber(on) == 1 then
    local save = ctx.save
    sc.infoWindow = function()
      local f = ctx.game.gen4BattleCastle
      local Font = require("src.render.Font")
      Font.drawBox(0, 0, 12, 5)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw((save.player and save.player.name) or "", 8, 8)
      Font.draw(("%4d CP"):format(B.cp(save, f and f.challengeType or 0)), 24, 24)
      love.graphics.setColor(1, 1, 1, 1)
    end
  else
    sc.infoWindow = nil
  end
end

function Commands.fr_bc_get_cp(ctx, t, dest) Fr.store(ctx, dest, B.cp(ctx.save, Fr.value(ctx, t))) end
function Commands.fr_bc_spend_cp(ctx, t, n) B.spendCP(ctx.save, Fr.value(ctx, t), Fr.value(ctx, n)) end
function Commands.fr_bc_receive_cp(ctx, t, n) B.receiveCP(ctx.save, Fr.value(ctx, t), Fr.value(ctx, n)) end

-- the self and opponent apps
function Commands.fr_bc_app(ctx, which)
  local f = castle(ctx)
  if not f then return end
  local runner = ctx.runner
  ctx.game.stack:push(require("src.ui.Gen4CastleScreen").new(ctx.game, {
    mode = which, castle = f, onDone = function() if runner then runner:resume() end end }))
  if runner then runner:yield() end
end

local function trainer(data, id)
  local rec = id and data.gen4_battle_tower and data.gen4_battle_tower.trainers[id]
  return rec and { id = id, class = rec.class, party = {} } or nil
end

-- FrontierScrCmd_CallBattleCastleFunction: BC_FUNC_* in the order of
-- include/constants/battle_castle_functions.h
function Commands.fr_bc_call(ctx, cmd, a1, a2, dest)
  local f = castle(ctx)
  if not f then Logger.warn("gen4 battle castle: function %s with no castle", tostring(cmd)) return end
  cmd, a1, a2 = tonumber(cmd) or 0, tonumber(a1) or 0, tonumber(a2) or 0
  local game = ctx.game
  local v
  if cmd == 2 then f.challengeType = a1
  elseif cmd == 3 then v = f.selected[a1] or 0
  elseif cmd == 4 then v = f.currentStreak
  elseif cmd == 5 then if f.currentStreak < 9999 then f.currentStreak = f.currentStreak + 1 end
  elseif cmd == 7 then if game.returnToTitle then game:returnToTitle() end
  elseif cmd == 9 then v = (B.record(ctx.save).current or {}).saved and 1 or 0
  elseif cmd == 10 then B.save(f, 2)
  elseif cmd == 14 then f.currentBattle = f.currentBattle + 1; v = f.currentBattle
  elseif cmd == 15 then local e = (f.opponentEntries or {})[a1 + 1]; v = e and e.species or 0
  elseif cmd == 16 then local e = (f.opponentEntries or {})[a1 + 1]; v = e and e.moves[a2 + 1] or 0
  elseif cmd == 17 then v = f.challengeType
  elseif cmd == 18 then
    -- BC_FUNC_RESTORE_HELD_ITEMS: the team was always copies -- the party
    -- still holds its own
  elseif cmd == 19 then v = B.round(f)
  elseif cmd == 20 then
    local tr = trainer(game.data, f.trainerIDs[f.currentBattle + a1 * B.PER_ROUND])
    v = (tr and BT().CLASS_GFX[tr.class]) or BT().GFX_SCHOOL_KID_M
  elseif cmd == 21 then B.saveOnLoss(f)
  elseif cmd == 22 then B.saveOnRound(f)
  elseif cmd == 23 then v = f.currentBattle
  elseif cmd == 24 or cmd == 26 or cmd == 30 or cmd == 34 then v = 0
  elseif cmd == 25 then v = f.monFainted and 1 or 0
  elseif cmd == 27 then
    v = B.cpFromBattle(f)
    B.receiveCP(ctx.save, f.challengeType, v)
  elseif cmd == 28 then B.prepForNextBattle(f)
  elseif cmd == 35 then v = B.isMulti(f.challengeType) and 1 or 0
  elseif cmd == 37 then
    f.opponents = { [0] = trainer(game.data, f.trainerIDs[f.currentBattle]),
                    trainer(game.data, f.trainerIDs[f.currentBattle + B.PER_ROUND]) }
  elseif cmd == 38 then v = B.earnedBP(f)
  elseif cmd == 39 then
    local r = B.record(ctx.save)
    v = r.heardIntro and 1 or 0
    r.heardIntro = true
  elseif cmd == 40 then
    v = 0
    if f.challengeType == B.SINGLE then
      if f.currentStreak + 1 == B.SILVER then v = 1 elseif f.currentStreak + 1 == B.GOLD then v = 2 end
    end
  elseif cmd == 41 then
    f.opponentEntries = B.entries(game.data, f.monSetIDs or {}, BT().ivsFor(f.trainerIDs[f.currentBattle] or 0))
  elseif cmd == 42 then B.setupOpponentsParty(game, f)
  elseif cmd == 43 then
    v = f.seenValetIntro and 1 or 0
    f.seenValetIntro = true
  end
  -- 0, 1, 6, 8, 11-13 dummies; 29, 31-33 the link; 36 the emblem frame; 44 the Wi-Fi CP
  if v ~= nil then Fr.store(ctx, dest, v) end
end

-- BattleCastle_StartBattle / CleanupBattle: the team itself goes in (its
-- HP, PP, status and items come back out), against copies of the opponents
-- healed, at the levels the opponent app left them
function Commands.fr_bc_battle(ctx)
  local f = castle(ctx)
  local game = ctx.game
  game.gen4BattleCastleWon = 0
  if not f then return end
  local id = f.trainerIDs[f.currentBattle]
  local who = trainer(game.data, id)
  if not (who and f.opponentParty and f.opponentParty[1]) then
    Logger.warn("gen4 battle castle: no opponent to battle -- counted as a loss")
    return
  end
  local double = f.challengeType == B.DOUBLE
  local key = C().registerTrainer(game, "GEN4_BATTLE_CASTLE", who, double, B.LEVEL)
  local mons = {}
  for i, mon in ipairs(f.opponentParty) do
    local m = C().copy(mon)
    require("src.pokemon.Pokemon").heal(m)
    mons[i] = m
  end
  local rec = game.data.trainers[key]
  rec.parties = { C().prebuilt(mons, B.LEVEL) }
  for i, slot in ipairs(rec.parties[1]) do slot.level = mons[i].level end
  rec.aiMask = B.aiMask(f)
  local BattleState = require("src.battle.BattleState")
  local real = ctx.save.party
  require("src.pokemon.PartyAside").hold(ctx.save, real)  -- in the save too (PartyAside)
  ctx.save.party = f.team
  local ok, battle = pcall(BattleState.newTrainer, game, key, 1)
  if not ok or not battle then
    ctx.save.party = real
    require("src.pokemon.PartyAside").release(ctx.save)
    Logger.warn("gen4 battle castle: could not build the battle: %s", tostring(battle))
    return
  end
  battle.battleTower, battle.canLose, battle.noExp = true, true, true
  if double then
    battle.double = true
    if battle.sendOutSecondPair then battle:sendOutSecondPair() end
  end
  local runner = ctx.runner
  battle.onFinish = function(result)
    ctx.save.party = real
    require("src.pokemon.PartyAside").release(ctx.save)
    game.gen4BattleCastleWon = (result == "win") and 1 or 0
    if runner then runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if runner then runner:yield() end
end
function Commands.fr_bc_won(ctx, dest) Fr.store(ctx, dest, ctx.game.gen4BattleCastleWon or 0) end

function Commands.fr_bc_intro(ctx, n)
  local f = castle(ctx)
  local o = f and f.opponents and f.opponents[tonumber(n) or 0]
  if not o then return end
  local Gen4Text = require("src.import.Gen4Text")
  return Commands.show_text(ctx, Gen4Text.label(BT().TRAINER_MESSAGES, o.id * 3))
end

return B
