-- THE BATTLE HALL'S LOBBY, the field half (scrcmd_battle_hall.c and
-- ScrCmd_GetBattleHallSelectedSlots): who may enter, the streak waiting to be
-- carried on, choosing the challenger, and the record keeper's sums over the
-- per-species win records the Hall's scene writes (battle_hall_win_records.c).
--
-- Loaded from the end of Gen4Commands, so everything it leans on is asked
-- for lazily.

local Commands = require("src.script.Commands")

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function H() return require("src.script.Gen4BattleHall") end
local function valueOf(ctx, n) return G4().valueOf(ctx, n) end
local function store(ctx, dest, value)
  dest = tonumber(dest)
  if dest and dest >= 0x4000 then G4().setVar(ctx.save, dest, math.floor(tonumber(value) or 0) % 65536) end
end

M.ELIGIBLE, M.STREAK_ACTIVE, M.STREAK_SPECIES, M.DELETE_STREAK, M.SELECT = 0, 1, 2, 3, 4
M.MIN_LEVEL = 30
M.SLOT_NONE = 0xFF
M.MSG_SAME_KIND = 201                      -- PartyMenu_Text_MustUseSameKindOfMon
-- sBattleHallRecordMilestones: { total singles record, BP }
M.MILESTONES = {
  { 10, 1 }, { 30, 3 }, { 50, 5 }, { 100, 5 }, { 150, 5 }, { 200, 5 }, { 250, 5 }, { 300, 5 }, { 350, 5 },
  { 400, 5 }, { 450, 5 }, { 500, 10 }, { 600, 10 }, { 700, 10 }, { 800, 10 }, { 900, 10 }, { 1000, 10 },
  { 1200, 30 }, { 1400, 30 }, { 1600, 30 }, { 1800, 30 }, { 2000, 50 }, { 2500, 50 }, { 3000, 50 },
  { 3500, 50 }, { 4000, 50 }, { 4500, 50 }, { 5000, 50 }, { 5500, 50 }, { 6000, 50 }, { 6500, 50 },
  { 7000, 50 }, { 7500, 50 }, { 8000, 50 }, { 8500, 50 }, { 9000, 50 }, { 9500, 50 }, { 10000, 100 },
  { 20000, 200 }, { 30000, 300 }, { 40000, 400 }, { 50000, 500 }, { 60000, 600 }, { 70000, 700 },
  { 80000, 800 }, { 90000, 900 }, { 100000, 1000 },
}

-- CheckPartyIsBattleHallEligible: `need` Pokemon of level 30+, off the
-- banlist, not eggs; for two, the cartridge asks only that two of them are
-- the SAME species (doubles is one kind twice)
function M.eligible(save, need)
  local party = save.party or {}
  if #party < need then return false end
  local banned = require("src.ui.Gen4PartyMenu").FRONTIER_BANLIST
  local species, count = {}, 0
  for i, mon in ipairs(party) do
    local isEgg = require("src.pokemon.Party").isEgg(mon)
    local sp = tonumber(mon.species) or 0
    if not isEgg and (tonumber(mon.level) or 1) >= M.MIN_LEVEL and not banned[sp] then
      count = count + 1
      species[i] = sp
    end
  end
  if need == 2 then
    for a = 1, #party do
      for b = 1, #party do
        if a ~= b and species[a] and species[a] == species[b] then return true end
      end
    end
    return false
  end
  return count >= need
end

-- BattleHall_ClearActiveStreak
function M.clearStreak(save, challenge)
  local r = H().record(save)
  r.streakActive[challenge] = nil
  r.latest = r.latest or {}
  r.latest[challenge] = 0
end

-- the per-species records, all challenges or one
function M.records(save, challenge)
  local r = H().record(save)
  r.winRecords = r.winRecords or {}
  if challenge then
    r.winRecords[challenge] = r.winRecords[challenge] or {}
    return r.winRecords[challenge]
  end
  return r.winRecords
end
function M.totalSingles(save)
  local n = 0
  for _, v in pairs(M.records(save, 0)) do n = n + v end
  return n
end
function M.speciesWithRecords(save)
  local seen, n = {}, 0
  for c = 0, 2 do
    for sp, v in pairs(M.records(save, c)) do
      if v > 0 and not seen[sp] then seen[sp] = true; n = n + 1 end
    end
  end
  return n
end

-- BattleHallWinRecords_UpdateRecord: the streak just saved, against the best
-- this species has (capped at 9999); TRUE when it changed
function M.updateWinRecord(save, challenge)
  if challenge == 3 then return false end                 -- the Wi-Fi multi keeps none
  local r = H().record(save)
  local species = r.latestSpecies and r.latestSpecies[challenge]
  if not species then return false end
  local newRecord = (r.latest and r.latest[challenge]) or 0
  local recs = M.records(save, challenge)
  local cur = recs[species] or 0
  if cur < newRecord then recs[species] = newRecord
  elseif cur > 9999 then recs[species] = 9999 end
  return newRecord ~= cur
end

-- ScrCmd_GetBattleHallRecordKeeperStats: the total, every milestone passed
-- since `nextMilestone` paid in BP, and the keeper's line (0 nothing yet,
-- 1 a reward, 2 the next goal, 3 every goal met)
function M.recordKeeper(save, nextMilestone)
  local total = M.totalSingles(save)
  local earned, reached, n0 = 0, 0, nextMilestone
  local next = nextMilestone
  for i = nextMilestone, #M.MILESTONES - 1 do
    if M.MILESTONES[i + 1][1] <= total then
      earned = earned + M.MILESTONES[i + 1][2]
      next = next + 1
      reached = i
    end
  end
  local response
  if total == 0 then response = 0
  else
    response = (n0 ~= next) and 1 or 2
    if n0 >= #M.MILESTONES then response = 3 end
  end
  return { total = total, earned = earned, next = next, response = response,
           passed = M.MILESTONES[reached + 1][1], goal = (M.MILESTONES[next + 1] or M.MILESTONES[#M.MILESTONES])[1] }
end

-- ------------------------------------------------------------- the rows --

-- `callbattlehalllobbyfunction <action> <arg> <dest>`
function Commands.g4_hall_lobby(ctx, action, arg, dest)
  action, arg = tonumber(action) or 0, math.floor(valueOf(ctx, arg) or 0)
  local save = ctx.save
  if action == M.ELIGIBLE then store(ctx, dest, M.eligible(save, arg) and 1 or 0)
  elseif action == M.STREAK_ACTIVE then store(ctx, dest, H().record(save).streakActive[arg] and 1 or 0)
  elseif action == M.STREAK_SPECIES then store(ctx, dest, (H().record(save).latestSpecies or {})[arg] or 0)
  elseif action == M.DELETE_STREAK then M.clearStreak(save, arg)
  elseif action == M.SELECT then
    -- SelectBattleHallChallengers: PARTY_MENU_MODE_BATTLE_HALL, level 30+,
    -- one (two for doubles, of one kind)
    ctx.gen4HallChosen = nil
    local runner = ctx.runner
    local two = arg == 1
    local PM = require("src.ui.Gen4PartyMenu")
    ctx.game.stack:push(PM.new(ctx.game, { select = {
      count = two and 2 or 1, minLevel = M.MIN_LEVEL, banlist = true, sameKind = two or nil,
      sameKindMessage = M.MSG_SAME_KIND,
      onDone = function(slots) ctx.gen4HallChosen = slots or false; if runner then runner:resume() end end,
    } }))
    if runner then runner:yield() end
  end
end

-- `getbattlehallselectedslots <slot1> <slot2>`: 0-based, 0xFF when backed out
function Commands.g4_hall_selected_slots(ctx, var1, var2)
  local chosen = ctx.gen4HallChosen
  if not chosen or not chosen[1] then
    store(ctx, var1, M.SLOT_NONE)
  else
    store(ctx, var1, chosen[1] - 1)
    store(ctx, var2, chosen[2] and (chosen[2] - 1) or 0)
  end
  ctx.gen4HallChosen = nil
end

function Commands.g4_hall_delete_streak(ctx, challenge)
  M.clearStreak(ctx.save, math.floor(valueOf(ctx, challenge) or 0))
end

-- the reporter waits outside only on a 50-win singles streak
function Commands.g4_hall_streak50(ctx, dest)
  local r = H().record(ctx.save)
  store(ctx, dest, ((r.latest or {})[0] == 50) and 1 or 0)
end

function Commands.g4_hall_num_species(ctx, dest) store(ctx, dest, M.speciesWithRecords(ctx.save)) end
function Commands.g4_hall_total_singles(ctx, dest) store(ctx, dest, math.min(10000, M.totalSingles(ctx.save))) end

function Commands.g4_hall_record_keeper(ctx, s1, s2, s3, s4, nextVar, respVar)
  local nextMilestone = math.floor(valueOf(ctx, nextVar) or 0)
  local k = M.recordKeeper(ctx.save, nextMilestone)
  local game = ctx.game
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[(tonumber(s1) or 1) + 1] = tostring(k.total)
  store(ctx, nextVar, k.next)
  store(ctx, respVar, k.response)
  if k.earned > 0 then require("src.pokemon.Gen4BattleTower").addBP(ctx.save, k.earned) end
  if k.response == 3 then return end
  game.stringBuffers[(tonumber(s2) or 2) + 1] = tostring(k.passed)
  game.stringBuffers[(tonumber(s3) or 3) + 1] = tostring(k.goal)
  game.stringBuffers[(tonumber(s4) or 4) + 1] = tostring(k.earned)
end

-- `deleteactivebattlefactorystreak <type> <open level>` (the Factory lobby's
-- one command; src/script/Gen4BattleFactory.lua keeps the records)
function Commands.g4_bf_delete_streak(ctx, challengeType, isOpenLevel)
  local r = require("src.script.Gen4BattleFactory").record(ctx.save)
  r.streakActive[math.floor(valueOf(ctx, isOpenLevel) or 0) * 4 + math.floor(valueOf(ctx, challengeType) or 0)] = nil
end

-- ------------------------------------------------- the Battle Castle's lobby --
-- (scrcmd_battle_castle.c; src/script/Gen4BattleCastle.lua keeps the records)

local function Castle() return require("src.script.Gen4BattleCastle") end

-- `callbattlecastlelobbyfunction <action> <arg> <dest>`: BC_LOBBY_FUNC_*
function Commands.g4_castle_lobby(ctx, action, arg, dest)
  action, arg = tonumber(action) or 0, math.floor(valueOf(ctx, arg) or 0)
  local save = ctx.save
  if action == 0 then
    -- sub_02049EC4: `arg` of them, no species or item repeated, off the banlist
    store(ctx, dest, require("src.pokemon.Gen4BattleTower").enoughValid(save, arg) and 1 or 0)
  elseif action == 1 then store(ctx, dest, Castle().record(save).streakActive[arg] and 1 or 0)
  elseif action == 3 then Castle().clearStreak(save, arg)
  elseif action == 4 then
    -- SelectBattleCastleChallengers: PARTY_MENU_MODE_BATTLE_CASTLE, three (two
    -- for the multi), level cap 100
    ctx.gen4CastleChosen = nil
    local runner = ctx.runner
    local PM = require("src.ui.Gen4PartyMenu")
    ctx.game.stack:push(PM.new(ctx.game, { select = {
      count = (arg == 2 or arg == 3) and 2 or 3, maxLevel = 100, banlist = true, unique = true,
      onDone = function(slots) ctx.gen4CastleChosen = slots or false; if runner then runner:resume() end end,
    } }))
    if runner then runner:yield() end
  end
end

-- `getbattlecastleselectedslots <s1> <s2> <s3>`: 0-based, 0xFF when backed out
function Commands.g4_castle_selected_slots(ctx, v1, v2, v3)
  local chosen = ctx.gen4CastleChosen
  if not chosen or not chosen[1] then
    store(ctx, v1, M.SLOT_NONE)
  else
    store(ctx, v1, chosen[1] - 1)
    store(ctx, v2, chosen[2] and (chosen[2] - 1) or 0)
    store(ctx, v3, chosen[3] and (chosen[3] - 1) or 0)
  end
  ctx.gen4CastleChosen = nil
end

function Commands.g4_castle_delete_streak(ctx, challenge)
  Castle().clearStreak(ctx.save, math.floor(valueOf(ctx, challenge) or 0))
end

-- ------------------------------------------------- the Battle Arcade's lobby --
-- (scrcmd_battle_arcade.c; src/script/Gen4BattleArcade.lua keeps the records)

local function Arcade() return require("src.script.Gen4BattleArcade") end

-- `callbattlearcadelobbyfunction <action> <arg> <dest>`: BA_LOBBY_FUNC_*, the
-- Castle's four in the same order
function Commands.g4_arcade_lobby(ctx, action, arg, dest)
  action, arg = tonumber(action) or 0, math.floor(valueOf(ctx, arg) or 0)
  if action == 1 then store(ctx, dest, Arcade().record(ctx.save).streakActive[arg] and 1 or 0)
  elseif action == 3 then Arcade().clearStreak(ctx.save, arg)
  else return Commands.g4_castle_lobby(ctx, action, arg, dest) end
end
function Commands.g4_arcade_delete_streak(ctx, challenge)
  Arcade().clearStreak(ctx.save, math.floor(valueOf(ctx, challenge) or 0))
end

return M
