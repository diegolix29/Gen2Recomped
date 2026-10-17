-- PLATINUM'S BATTLE HALL (overlay104 battle_hall.c, battle_hall_helpers.c,
-- frscrcmd_battle_hall.c), the facility half of the Hall's frontier scene
-- script.
--
-- One Pokemon (two in doubles) against a run of single opponents, a type at
-- a time: the type-select app (src/ui/Gen4HallTypeScreen.lua) picks the
-- type, BattleHall_SetupNextOpponent picks the trainer (a class from the
-- type's rank and the type itself, then a frontier trainer of that class
-- not met this round) and the Pokemon (from the rank's group of
-- sBattleHallPotentialOpponents, of the chosen type, never your own
-- species), and the battle is at a level worked out from yours, the type's
-- rank and how many types you have beaten. Ten battles a round; Argenta,
-- the Hall Matron, at the 50th and 170th in singles.
--
-- The tables come out of the source (src/import/Gen4BattleHallTables.lua,
-- tools/gen4_battle_hall_tables_gen.py), the sets out of pl_bsdpm (the
-- cache's gen4_battle_tower.hallSets).
--
-- NOT PORTED: the multi challenges (link play), so the Hall runs single and
-- double; and the Pokemon summary the app's two portrait cells open.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local VM = require("src.script.Gen4FrontierVM")
local Fr = require("src.script.Gen4FrontierScrCmds")
local T = require("src.import.Gen4BattleHallTables")

local H = {}

H.SINGLE, H.DOUBLE, H.MULTI, H.MULTI_WFC = 0, 1, 2, 3
H.TYPES = 18                -- NUM_POKEMON_TYPES (with ???)
H.MAX_RANK = 10             -- HALL_MAX_TYPE_RANK
H.PER_ROUND = 10            -- HALL_BATTLES_PER_ROUND
H.MAX_ROUNDS = 18           -- HALL_MAX_DISTINCT_ROUNDS
H.SILVER, H.GOLD = 50, 170  -- HALL_STREAK_SILVER_BATTLE / _GOLD_BATTLE
H.BP_SOLO = { [0] = 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 6, 6, 8, 8, 10, 10, 12 }
H.BP_WIFI = { [0] = 0, 6, 6, 6, 8, 8, 8, 10, 10, 10, 12, 12, 14, 15, 17, 17, 20, 20, 23 }

-- the Hall's records, in the save (BattleFrontierSave's hall stats and the
-- HALL_SAVE struct, kept as one table)
function H.record(save)
  save.gen4Hall = save.gen4Hall or { ranks = {}, streak = {}, streakActive = {}, latestSpecies = {} }
  local r = save.gen4Hall
  r.ranks = r.ranks or {}
  return r
end

-- BattleHall_LoadTypeRanks / SaveTypeRank: a nybble each, two types a byte
function H.rank(save, challenge, t)
  local r = H.record(save)
  local row = r.ranks[challenge] or {}
  local byte = row[math.floor(t / 2)] or 0
  return (t % 2 == 0) and (byte % 16) or math.floor(byte / 16)
end
function H.setRank(save, challenge, t, v)
  local r = H.record(save)
  r.ranks[challenge] = r.ranks[challenge] or {}
  local row = r.ranks[challenge]
  local i = math.floor(t / 2)
  local byte = row[i] or 0
  local lo, hi = byte % 16, math.floor(byte / 16)
  if t % 2 == 0 then lo = v % 16 else hi = v % 16 end
  row[i] = hi * 16 + lo
end

function H.partySize(challenge) return (challenge == H.DOUBLE) and 2 or 1 end

-- BattleHall_Init
function H.init(save, resuming, challenge, slot1, slot2)
  local r = H.record(save)
  local hall = { save = save, ranks = {}, trainerIDs = {}, monIndices = {}, heldItems = {} }
  local cur = r.current or {}
  if resuming == 0 then
    hall.challenge = challenge
    hall.battle = 0
    r.current = {}
    if r.streakActive[challenge] then
      hall.streak = r.latest and r.latest[challenge] or 0
    else
      hall.streak = 0
      for t = 0, H.TYPES - 1 do H.setRank(save, challenge, t, 0) end
    end
    hall.slots = { [0] = slot1, slot2 }
  else
    hall.challenge = cur.challenge or 0
    hall.battle = cur.battle or 0
    hall.streak = r.latest and r.latest[hall.challenge] or 0
    hall.slots = { [0] = cur.slots and cur.slots[0] or 0, cur.slots and cur.slots[1] or 1 }
    for k, v in pairs(cur.trainerIDs or {}) do hall.trainerIDs[k] = v end
    for k, v in pairs(cur.monIndices or {}) do hall.monIndices[k] = v end
  end
  for i = 0, H.partySize(hall.challenge) - 1 do
    local mon = save.party and save.party[(hall.slots[i] or 0) + 1]
    hall.heldItems[i] = mon and mon.item or false
  end
  hall.round = math.floor(hall.streak / H.PER_ROUND)
  for t = 0, H.TYPES - 1 do
    hall.ranks[t] = (hall.challenge == H.MULTI) and (H.MAX_RANK - 1) or H.rank(save, hall.challenge, t)
  end
  hall.selectedIdx, hall.selectedIdx2 = 0, 0
  return hall
end

-- BattleHall_GetEarnedBP
function H.earnedBP(hall)
  local solo = hall.challenge == H.SINGLE or hall.challenge == H.DOUBLE
  local t = solo and H.BP_SOLO or H.BP_WIFI
  local bp = t[math.min(hall.round, H.MAX_ROUNDS)] or 0
  if hall.challenge == H.SINGLE and (hall.streak == H.SILVER or hall.streak == H.GOLD) then bp = 20
  elseif hall.challenge == H.MULTI then bp = 12 end
  return bp
end

-- BattleHall_Save (saveType 0 a round won, 1 a loss, 2 a quick save)
function H.save(hall, kind)
  local r = H.record(hall.save)
  r.current = { challenge = hall.challenge, battle = hall.battle, slots = { [0] = hall.slots[0], hall.slots[1] },
                trainerIDs = {}, monIndices = {}, saved = true }
  for k, v in pairs(hall.trainerIDs) do r.current.trainerIDs[k] = v end
  for k, v in pairs(hall.monIndices) do r.current.monIndices[k] = v end
  r.latest = r.latest or {}
  r.latest[hall.challenge] = hall.streak
  if kind ~= 2 then
    r.streak[hall.challenge] = hall.streak
    r.streakActive[hall.challenge] = hall.saveStreak and true or nil
  end
  for t = 0, H.TYPES - 1 do H.setRank(hall.save, hall.challenge, t, hall.ranks[t] or 0) end
  local mon = hall.save.party and hall.save.party[(hall.slots[0] or 0) + 1]
  r.latestSpecies[hall.challenge] = mon and mon.species
end

-- ------------------------------------------------------------ the lowering --

local F = VM.facility
local emit = VM.emit
F.initbattlehall = function(ins, s) emit(s, { "fr_hall_init", ins.args[1], ins.args[2], ins.args[3], ins.args[4] }) end
F.callbattlehallfunction = function(ins, s)
  emit(s, { "fr_hall_call", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
end
F.freebattlehall = function(_, s) emit(s, { "fr_hall_free" }) end
F.openbattlehallapp = function(_, s) emit(s, { "fr_hall_app" }) end
F.battlehall_setup_next_opponent = function(ins, s) emit(s, { "fr_hall_next_opponent" }) end
F.battlehall_startbattle = function(_, s) emit(s, { "fr_hall_battle" }) end
F.battlehall_cleanupbattle = function() end
F.battlehall_checkwonbattle = function(ins, s) emit(s, { "fr_hall_won", ins.args[1] }) end
F.battlehall_printtrainerintro = function(ins, s) emit(s, { "fr_hall_intro", ins.args[1] }) end
F.battlehall_updatewinrecord = function(ins, s) emit(s, { "fr_hall_win_record", ins.args[1] }) end
F.battlehall_sendcommmessage = function(ins, s) emit(s, { "fr_set", ins.args[3], 1 }) end
F["94"] = function() end

local function hall(ctx) return ctx.game.gen4BattleHall end

function Commands.fr_hall_init(ctx, resuming, challenge, slot1, slot2)
  local v = Fr.value
  ctx.game.gen4BattleHall = H.init(ctx.save, v(ctx, resuming), v(ctx, challenge), v(ctx, slot1), v(ctx, slot2))
end
function Commands.fr_hall_free(ctx) ctx.game.gen4BattleHall = nil end

-- FrontierScrCmd_CallBattleHallFunction: BH_FUNC_* in the order of
-- include/constants/battle_hall_functions.h
H.FN_NAMES = {
  [0] = "UNK_0", [1] = "UNK_1", [2] = "SET_CHALLENGE_TYPE", [3] = "GET_SELECTED_TYPE_INDEX",
  [4] = "GET_CURRENT_STREAK", [5] = "INCREMENT_CURRENT_STREAK", [6] = "UNK_6", [7] = "RESET_SYSTEM",
  [8] = "UNK_8", [9] = "CHECK_HAS_SAVED", [10] = "QUICKSAVE", [11] = "UNK_11",
  [12] = "UNK_12", [13] = "UNK_13", [14] = "INCREMENT_CURRENT_BATTLE", [15] = "GET_PLAYERS_MONS_SPECIES",
  [16] = "UNK_16", [17] = "GET_CHALLENGE_TYPE", [18] = "UNK_18", [19] = "GET_CURRENT_ROUND",
  [20] = "GET_OPPONENT_OBJECT_ID", [21] = "SAVE_ON_LOSS", [22] = "SAVE_ON_COMPLETING_ROUND", [23] = "GET_CURRENT_BATTLE",
  [24] = "UNK_24", [25] = "UNK_25", [26] = "UNK_26", [27] = "RESTORE_HELD_ITEMS",
  [28] = "INCREMENT_RANK_OF_BEATEN_TYPE", [29] = "UNK_29", [30] = "IS_MULTIPLAYER_CHALLENGE", [31] = "TOGGLE_ENGINE_LAYER",
  [32] = "LOAD_TRAINERS", [33] = "GET_RANK_OF_BEATEN_TYPE", [34] = "GET_EARNED_BP", [35] = "CAP_TYPE_RANKS",
  [36] = "SET_BASE_LEVEL", [37] = "GET_NEXT_BATTLE_TYPE", [38] = "DUMMY",
}
function Commands.fr_hall_call(ctx, cmd, a1, a2, dest)
  local h = hall(ctx)
  cmd, a1 = tonumber(cmd) or 0, tonumber(a1) or 0
  local name = H.FN_NAMES and H.FN_NAMES[cmd]
  if not h then Logger.warn("gen4 battle hall: function %d with no hall", cmd) return end
  local v
  if name == "SET_CHALLENGE_TYPE" then h.challenge = a1
  elseif name == "GET_SELECTED_TYPE_INDEX" then v = h.selectedIdx2
  elseif name == "GET_CURRENT_STREAK" then v = h.streak
  elseif name == "INCREMENT_CURRENT_STREAK" then if h.streak < 9999 then h.streak = h.streak + 1 end
  elseif name == "RESET_SYSTEM" then if ctx.game.returnToTitle then ctx.game:returnToTitle() end
  elseif name == "CHECK_HAS_SAVED" then v = (H.record(ctx.save).current or {}).saved and 1 or 0
  elseif name == "QUICKSAVE" then H.save(h, 2)
  elseif name == "INCREMENT_CURRENT_BATTLE" then h.battle = h.battle + 1; v = h.battle
  elseif name == "GET_CURRENT_ROUND" then v = (h.challenge == H.MULTI) and 10 or h.round
  elseif name == "SAVE_ON_LOSS" then
    for t = 0, H.TYPES - 1 do h.ranks[t] = 0 end
    H.save(h, 1)
  elseif name == "SAVE_ON_COMPLETING_ROUND" then
    h.saveStreak = true
    if h.round < H.MAX_ROUNDS then h.round = h.round + 1 end
    h.battle = 0
    H.save(h, 0)
  elseif name == "GET_CURRENT_BATTLE" then v = h.battle
  elseif name == "RESTORE_HELD_ITEMS" then
    for i = 0, H.partySize(h.challenge) - 1 do
      local mon = ctx.save.party and ctx.save.party[(h.slots[i] or 0) + 1]
      if mon then mon.item = h.heldItems[i] or nil end
    end
  elseif name == "INCREMENT_RANK_OF_BEATEN_TYPE" then
    local r = h.ranks[h.selectedIdx] or 0
    if r < H.MAX_RANK then h.ranks[h.selectedIdx] = r + 1 end
  elseif name == "IS_MULTIPLAYER_CHALLENGE" then v = (h.challenge == H.MULTI or h.challenge == H.MULTI_WFC) and 1 or 0
  elseif name == "GET_CHALLENGE_TYPE" then v = h.challenge
  elseif name == "GET_RANK_OF_BEATEN_TYPE" then v = h.ranks[h.selectedIdx] or 0
  elseif name == "GET_EARNED_BP" then v = H.earnedBP(h)
  elseif name == "GET_PLAYERS_MONS_SPECIES" then
    local mon = ctx.save.party and ctx.save.party[(h.slots[0] or 0) + 1]
    v = mon and (tonumber(mon.species) or 0) or 0
  elseif name == "CAP_TYPE_RANKS" then
    if h.challenge ~= H.MULTI then
      local all = true
      for t = 0, H.TYPES - 2 do if (h.ranks[t] or 0) < H.MAX_RANK then all = false end end
      if all then for t = 0, H.TYPES - 2 do h.ranks[t] = H.MAX_RANK - 1 end end
    end
  elseif name == "GET_NEXT_BATTLE_TYPE" then
    v = 0
    if h.challenge == H.SINGLE then
      if h.streak + 1 == H.SILVER then v = 1 elseif h.streak + 1 == H.GOLD then v = 2 end
    end
  elseif name == "UNK_24" then v = 0
  elseif name == "SET_BASE_LEVEL" then h.levelSqrt = H.levelSqrt(H.highestLevel(h))
  elseif name == "LOAD_TRAINERS" then
    local off = h.battle * 2
    h.opponents = { [0] = H.trainer(ctx.game.data, h.trainerIDs[off]), H.trainer(ctx.game.data, h.trainerIDs[off + 1]) }
  elseif name == "GET_OPPONENT_OBJECT_ID" then
    local BT = require("src.pokemon.Gen4BattleTower")
    local tr = H.trainer(ctx.game.data, h.trainerIDs[h.battle * 2 + a1])
    v = (tr and BT.CLASS_GFX[tr.class]) or BT.GFX_SCHOOL_KID_M
  else
    -- the trainer load, the level's square root, the engine layer and the
    -- dummies: nothing for this file to answer yet
  end
  if v ~= nil then Fr.store(ctx, dest, v) end
end

-- ------------------------------------------------------ the next opponent --

H.ARGENTA_SILVER, H.ARGENTA_GOLD = 307, 308   -- FRONTIER_TRAINER_HALL_MATRON_ARGENTA_*
H.NEXT_NORMAL, H.NEXT_SILVER, H.NEXT_GOLD = 0, 1, 2
H.MYSTERY_CELL, H.SUMMARY = 19, 0xFE

local function rand(n) return love.math.random(0, n - 1) end
function H.checkRank(r) return math.min(r or 0, H.MAX_RANK - 1) end   -- BattleHall_CheckTypeRank

-- the party the Hall battles with: the chosen slot (or two), as they stand
function H.mon(h, i) return h.save.party and h.save.party[(h.slots[i or 0] or 0) + 1] end
function H.highestLevel(h)
  local a = H.mon(h, 0)
  local lv = tonumber(a and a.level) or 1
  if H.partySize(h.challenge) == 2 then
    local b = H.mon(h, 1)
    lv = math.max(lv, tonumber(b and b.level) or 1)
  end
  return lv
end
-- FX_Sqrt over fx32: the root to 1/4096
function H.levelSqrt(level) return math.floor(math.sqrt(level) * 4096) / 4096 end

-- BattleHall_CalcOpponentsLevel
function H.opponentsLevel(h)
  local rank = h.ranks[h.selectedIdx] or 0
  local lv = H.highestLevel(h)
  if h.challenge == H.MULTI then return lv end
  local root = h.levelSqrt or H.levelSqrt(lv)
  local base = lv - root * 3
  local rankFactor = root * 5
  if lv / rankFactor < 1 then rankFactor = rank
  else rankFactor = (rank * lv) / rankFactor end
  local battled = 0
  for t = 0, H.TYPES - 1 do
    if t == h.selectedIdx or (h.ranks[t] or 0) > 0 then battled = battled + 1 end
  end
  if battled ~= 0 then battled = battled - 1 end
  local f = base + rankFactor + battled * 0.5
  -- (int) truncates toward zero, then anything left over rounds up -- so a
  -- slightly negative sum (a party under level 10) still makes level 1
  local level = (f >= 0) and math.floor(f) or math.ceil(f)
  if f ~= level then level = level + 1 end
  return math.max(1, math.min(level, lv, 100))
end

-- BattleHall_PickOpponentTrainerClasses: a class from the rank's eight or the type's four
function H.pickClasses(selIdx, n, rank, battle, ids)
  local off = battle * 2
  rank = H.checkRank(rank)
  for i = 0, n - 1 do
    local r = rand(12)
    ids[off + i] = (r < 8) and T.CLASSES_BY_RANK[rank][r] or T.CLASSES_BY_TYPE[math.min(selIdx, 17)][r - 8]
  end
end

-- BattleHall_PickOpponentTrainers: a frontier trainer of that class not met
-- this round (Argenta at the 50th and 170th in singles); when a whole lap of
-- the trainers finds none, another class from the rank's eight
function H.pickTrainers(data, challenge, n, round, rank, battle, ids)
  local off = battle * 2
  local tr = H.checkRank(rank)
  if challenge == H.SINGLE then
    local streak = round * H.PER_ROUND + battle + 1
    if streak == H.SILVER then ids[off] = H.ARGENTA_SILVER return
    elseif streak == H.GOLD then ids[off] = H.ARGENTA_GOLD return end
  end
  local rec = data and data.gen4_battle_tower
  local classes, count = {}, 0
  for id, t in pairs(rec and rec.trainers or {}) do classes[id] = t.class; count = math.max(count, id + 1) end
  if count == 0 then return end
  local selected, guard = 0, 0
  repeat
    local id = rand(count)
    local start = id
    while guard < 100000 do
      guard = guard + 1
      local cls = ids[off + selected]
      if cls == classes[id] then
        local used = false
        for p = 0, off + selected - 1 do if ids[p] == id then used = true break end end
        if not used then
          ids[off + selected] = id
          selected = selected + 1
          break
        end
      end
      id = id + 1
      if id >= count then id = 0 end
      if id == start then
        repeat
          local k = rand(8)
          local other = T.CLASSES_BY_RANK[tr][k]
          if cls ~= other then ids[off + selected] = other end
        until cls ~= other
      end
    end
  until selected >= n or guard >= 100000
end

local function rangeByRank(rank)
  local G, N = T.GROUP, T.COUNT
  if rank <= 1 then return G[1], G[2] - 1
  elseif rank <= 4 then return G[1], G[3] - 1
  elseif rank <= 7 then return G[2], G[4] - 1 end
  return G[3], N
end
local function groupRange(g)
  local G, N = T.GROUP, T.COUNT
  if g < 4 then return G[g], G[g + 1] - 1 end
  return G[4], N
end
H.rangeByRank, H.groupRange = rangeByRank, groupRange

-- BattleHall_PickNextOpponentPokemon: the rank's group (Argenta: your
-- species' group, or group 4 for gold), of the chosen type, not your
-- species, not met this round -- or, once a lap finds none, just not the
-- last one. `mons` holds pl_bsdpm members (list position + 1).
function H.pickMon(selType, rank, battle, playersSpecies, mons, battleType)
  local off = battle * 2
  rank = H.checkRank(rank)
  local lo, hi
  if battleType ~= H.NEXT_NORMAL then
    local at
    for i = 0, T.COUNT - 1 do if T.SPECIES[i] == playersSpecies then at = i break end end
    at = at or T.GROUP[4]
    local g = 1
    while g <= 4 do
      local _, gmax = groupRange(g)
      if at < gmax then break end
      g = g + 1
    end
    if g > 4 then g = 4 end
    if battleType == H.NEXT_GOLD then lo, hi = groupRange(4) else lo, hi = groupRange(g) end
  else
    lo, hi = rangeByRank(rank)
  end
  local idx = lo + rand(hi - lo + 1) - 1
  local start, looped, guard = idx, false, 0
  while guard < 20000 do
    guard = guard + 1
    local fresh
    if not looped then
      fresh = true
      for p = 0, off - 1 do if mons[p] == idx + 1 then fresh = false break end end
    else
      fresh = mons[off - 2] ~= idx + 1
    end
    local ty = T.MON_TYPES[idx]
    local ok = fresh and T.SPECIES[idx] ~= playersSpecies
               and (battleType ~= H.NEXT_NORMAL or (ty ~= nil and (ty[1] == selType or ty[2] == selType)))
    if ok then mons[off] = idx + 1 return idx + 1 end
    idx = idx + 1
    if idx + 1 >= hi then idx = lo - 1 end
    if idx == start then looped = true end
  end
  Logger.warn("gen4 battle hall: no type-%s opponent in %d..%d", tostring(selType), lo, hi)
  mons[off] = lo
  return lo
end

-- BattleHall_SetupNextOpponent
function H.setupNext(h, data)
  local n = (h.challenge ~= H.SINGLE) and 2 or 1
  local rank = h.ranks[h.selectedIdx] or 0
  h.opponentsLevel = H.opponentsLevel(h)
  H.pickClasses(h.selectedIdx, n, rank, h.battle, h.trainerIDs)
  H.pickTrainers(data, h.challenge, n, h.round, rank, h.battle, h.trainerIDs)
  local off = h.battle * 2
  local kind = H.NEXT_NORMAL
  local first = h.trainerIDs[off]
  if first == H.ARGENTA_SILVER or first == H.ARGENTA_GOLD then
    -- BattleHall_GetHallMatronTypeRank: your Pokemon's level over ten
    local mon = H.mon(h, 0)
    rank = math.floor((tonumber(mon and mon.level) or 1) / 10)
    kind = (first == H.ARGENTA_SILVER) and H.NEXT_SILVER or H.NEXT_GOLD
  end
  local mine = H.mon(h, 0)
  H.pickMon(h.selectedType, rank, h.battle, tonumber(mine and mine.species) or 0, h.monIndices, kind)
end

function H.trainer(data, id)
  local rec = data and data.gen4_battle_tower
  local t = id and rec and rec.trainers and rec.trainers[id]
  return t and { id = id, class = t.class, party = {} } or nil
end

-- BattleHall_SetupBattle's opponent side: the set at the type's IVs (Argenta:
-- 31), the level from BattleHall_CalcOpponentsLevel (Argenta: your highest);
-- in doubles the SAME set twice -- the cartridge inits opponentMons[offset]
-- for both, flipping the personality by 25 * 10001 each time (the nature
-- stays, the ability bit flips)
function H.opponentParty(h, data)
  local BT = require("src.pokemon.Gen4BattleTower")
  local off = h.battle * 2
  local rec = data and data.gen4_battle_tower
  local setID = h.monIndices[off]
  local set = rec and rec.hallSets and rec.hallSets[setID]
  if not set then return nil end
  local first = h.trainerIDs[off]
  local matron = first == H.ARGENTA_SILVER or first == H.ARGENTA_GOLD
  local rank = (h.challenge == H.MULTI) and (H.MAX_RANK - 1) or (h.ranks[h.selectedIdx] or 0)
  local ivs = matron and 31 or T.IVS[H.checkRank(rank)]
  local otId = rand(65536) + rand(65536) * 65536
  local base = BT.monFromSet(set, setID, ivs, otId, function() return rand(65536) end)
  local level = matron and H.highestLevel(h) or h.opponentsLevel or H.opponentsLevel(h)
  local party = {}
  local pid = base.personality
  for i = 1, H.partySize(h.challenge) do
    repeat
      if pid > 25 * 10001 then pid = pid - 25 * 10001 else pid = pid + 25 * 10001 end
    until not BT.shiny(otId, pid)
    local m = BT.copyTable(base)
    m.personality, m.abilityBit = pid, pid % 2
    party[i] = m
  end
  return party, level
end

-- OpenBattleHallApp: the type grid; BattleHall_GetTypeSelectionAppResult
function Commands.fr_hall_app(ctx)
  local h = hall(ctx)
  if not h then return end
  local Screen = require("src.ui.Gen4HallTypeScreen")
  local runner = ctx.runner
  local cell
  ctx.game.stack:push(Screen.new(ctx.game, {
    hall = h, cursor = h.selectedIdx2 or 0,
    onDone = function(c) cell = c; if runner then runner:resume() end end,
  }))
  if runner then runner:yield() end
  H.select(h, cell or 0)
end

-- BattleHall_GetTypeSelectionAppResult
function H.select(h, cell)
  h.selectedIdx2 = cell
  h.selectedIdx = math.min(cell, 17)
  h.selectedType = T.GRID[cell]
end

function Commands.fr_hall_next_opponent(ctx)
  local h = hall(ctx)
  if h then H.setupNext(h, ctx.game.data) end
end

-- BattleHall_StartBattle: the party healed, the chosen slot(s) against the next one
function Commands.fr_hall_battle(ctx)
  local h = hall(ctx)
  local game = ctx.game
  game.gen4BattleHallWon = 0
  if not h then return end
  local BTC = require("src.script.Gen4BattleTowerCommands")
  pcall(require("src.script.Gen4Commands").healParty, ctx.save)
  local party, level = H.opponentParty(h, game.data)
  local who = H.trainer(game.data, h.trainerIDs[h.battle * 2])
  if not (party and who) then
    Logger.warn("gen4 battle hall: no opponent to battle -- counted as a loss")
    return
  end
  who.party = party
  local double = h.challenge == H.DOUBLE
  local key = BTC.registerTrainer(game, "GEN4_BATTLE_HALL", who, double, level)
  local team = {}
  for i = 0, H.partySize(h.challenge) - 1 do
    local mon = H.mon(h, i)
    if mon then team[#team + 1] = BTC.copy(mon) end
  end
  local BattleState = require("src.battle.BattleState")
  local real = ctx.save.party
  require("src.pokemon.PartyAside").hold(ctx.save, real)  -- in the save too (PartyAside)
  ctx.save.party = team
  local ok, battle = pcall(BattleState.newTrainer, game, key, 1)
  if not ok or not battle then
    ctx.save.party = real
    require("src.pokemon.PartyAside").release(ctx.save)
    Logger.warn("gen4 battle hall: could not build the battle: %s", tostring(battle))
    return
  end
  battle.battleTower = true
  battle.canLose = true
  battle.noExp = true
  if double then
    battle.double = true
    if battle.sendOutSecondPair then battle:sendOutSecondPair() end
  end
  local runner = ctx.runner
  battle.onFinish = function(result)
    ctx.save.party = real
    require("src.pokemon.PartyAside").release(ctx.save)
    game.gen4BattleHallWon = (result == "win") and 1 or 0
    if runner then runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if runner then runner:yield() end
end
-- BattleHall_UpdateWinRecordForCurrentMon: the streak just saved, as this
-- species' best (src/script/Gen4BattleHallLobby.lua keeps the records)
function Commands.fr_hall_win_record(ctx, dest)
  local h = hall(ctx)
  local updated = h and require("src.script.Gen4BattleHallLobby").updateWinRecord(ctx.save, h.challenge)
  Fr.store(ctx, dest, updated and 1 or 0)
end
function Commands.fr_hall_won(ctx, dest) Fr.store(ctx, dest, ctx.game.gen4BattleHallWon or 0) end

-- the opponent's intro, from the frontier trainers' message bank
function Commands.fr_hall_intro(ctx, n)
  local h = hall(ctx)
  local o = h and h.opponents and h.opponents[tonumber(n) or 0]
  if not o then return end
  local BT = require("src.pokemon.Gen4BattleTower")
  local Gen4Text = require("src.import.Gen4Text")
  return Commands.show_text(ctx, Gen4Text.label(BT.TRAINER_MESSAGES, o.id * 3))
end

return H
