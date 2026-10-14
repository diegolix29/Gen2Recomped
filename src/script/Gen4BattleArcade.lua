-- PLATINUM'S BATTLE ARCADE (overlay104 battle_arcade.c, battle_arcade_helpers.c,
-- frscrcmd_battle_arcade.c, and the roulette app's choices in
-- src/applications/frontier/battle_arcade/main.c), the facility half of the
-- Arcade's frontier scene script (fr_script member 2, scenes 15 and 16).
--
-- Seven battles a round with three of your own at level 50 (copies, no
-- items), each preceded by the Game Board: sixteen panels dealt from the
-- events this round allows, by category weights that follow how well the
-- last battle went, a cursor stepping round them at the board's speed, and
-- A to stop it (or thirty seconds). What it lands on happens to the foe's
-- team or yours (HP cut to about 80%, a status, a Berry or item for all
-- three, three levels), to the field (sun, rain, sand, hail, deep fog,
-- Trick Room), to the board (faster, slower, a random cursor), or swaps the
-- two teams, or pays 1 or 3 BP, or skips the battle. Everyone is healed
-- before each battle; an item given or won is kept, a level is not.
-- Dahlia, the Arcade Star, is the 21st and 49th in singles.
--
-- NOT PORTED: the multi challenges (link play), the board's own art (the
-- panels are src/ui/Gen4ArcadeScreen.lua's text grid), the AI mask by round,
-- the board sprites and particle bursts, and the field's "fog is deep" /
-- "dimensions became distorted" lines at the battle's start.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local VM = require("src.script.Gen4FrontierVM")
local Fr = require("src.script.Gen4FrontierScrCmds")

local A = {}

A.SINGLE, A.DOUBLE, A.MULTI, A.MULTI_WFC = 0, 1, 2, 3
A.PER_ROUND = 7                  -- ARCADE_BATTLES_PER_ROUND
A.SILVER, A.GOLD = 21, 49
A.MAX_ROUNDS = 8
A.LEVEL = 50
A.DAHLIA_SILVER, A.DAHLIA_GOLD = 311, 312
A.BP_SOLO = { [0] = 0, 2, 2, 2, 2, 4, 4, 5, 6 }
A.BP_WIFI = { [0] = 0, 7, 8, 9, 10, 13, 14, 16, 17 }
A.GRID = 16
A.NONE = 32                      -- NUM_ARCADE_EFFECTS: no effect yet

-- the effects (ARCADE_EFFECT_*)
A.E = {
  LOWER_FOE_HP = 0, POISON_FOE = 1, PARALYZE_FOE = 2, BURN_FOE = 3, SLEEP_FOE = 4, FREEZE_FOE = 5,
  FOE_GET_BERRY = 6, FOE_GET_ITEM = 7, FOE_LEVEL_UP = 8,
  LOWER_ALLY_HP = 9, POISON_ALLY = 10, PARALYZE_ALLY = 11, BURN_ALLY = 12, SLEEP_ALLY = 13, FREEZE_ALLY = 14,
  ALLY_GET_BERRY = 15, ALLY_GET_ITEM = 16, ALLY_LEVEL_UP = 17,
  SUNNY = 18, RAINY = 19, SANDY = 20, HAIL = 21, FOGGY = 22, TRICK_ROOM = 23,
  SPEED_UP = 24, SLOW_DOWN = 25, RANDOMIZE_CURSOR = 26, SWAP_MONS = 27, GET_1_BP = 28, NO_BATTLE = 29,
  NO_EVENT = 30, GET_3_BP = 31,
}
A.FOE, A.ALLY, A.ENV, A.BONUS = 0, 1, 2, 3   -- ARCADE_EFFECT_CATEGORY_*

-- sBattleArcadeOpponentPools (the Factory's and Castle's ranges)
A.OPPONENT_POOLS = {
  { 0, 99, 100, 119 }, { 80, 119, 120, 139 }, { 100, 139, 140, 159 }, { 120, 159, 160, 179 },
  { 140, 179, 180, 199 }, { 160, 199, 200, 219 }, { 180, 219, 220, 239 }, { 200, 299, 200, 299 },
}

-- sRouletteSpeedByRound: from round 8 speed 5, from round 5 speed 4, else 3
A.SPEED_BY_ROUND = { { 7, 5 }, { 4, 4 }, { 0, 3 } }
-- sCursorMoveFrames: frames per step (at the app's 30 fps) by speed 0-7
A.CURSOR_FRAMES = { [0] = 20, 16, 8, 4, 3, 2, 1, 0 }

-- sEffectAvailabilityByRound: the rounds (1-7; 7 and beyond) an effect is dealt in
local function rounds(s) local t = {} for i = 1, 7 do t[i] = s:sub(i, i) == "1" end return t end
A.BY_ROUND = {
  [0] = rounds("0111111"), rounds("1010001"), rounds("1010001"), rounds("1010001"), rounds("0000111"),
  rounds("0000111"), rounds("1110001"), rounds("0001111"), rounds("0111111"),
  rounds("0111111"), rounds("1010001"), rounds("1010001"), rounds("1010001"), rounds("0000111"),
  rounds("0000111"), rounds("1110001"), rounds("0001111"), rounds("0111111"),
  rounds("0110001"), rounds("0110001"), rounds("0110001"), rounds("0110001"), rounds("0001011"),
  rounds("0001011"), rounds("1111111"), rounds("1110001"), rounds("1111111"), rounds("0000111"),
  rounds("0001111"), rounds("0000111"), rounds("1111111"), rounds("0000001"),
}
-- sEffectAvailabilityByBattle: seven effects that also depend on the battle
-- of the round (1-7)
A.BY_BATTLE = {
  [27] = rounds("1111110"), [24] = rounds("1111110"), [25] = rounds("1111110"), [26] = rounds("1111110"),
  [28] = rounds("1010100"), [29] = rounds("0101010"), [31] = rounds("0101010"),
}
-- sCategoryWeights by tier (foe, ally, field, bonus), and the performance
-- each tier needs (sCategoryTierPerformanceThresholds)
A.WEIGHTS = { [0] = { 15, 15, 40, 30 }, { 35, 20, 30, 15 }, { 30, 30, 35, 5 }, { 25, 40, 30, 5 }, { 10, 75, 10, 5 } }
A.TIER_THRESHOLDS = { 21, 16, 10, 5 }

-- the performance (BattleArcade_GetPerformance)
A.BY_STATUS = { [0] = 8, 6, 4, 0, 0 }
A.BY_FAINTED = { [0] = 6, 4, 2, 0, 0 }
A.BY_TURNS = { { 3, 10 }, { 5, 6 }, { 7, 4 }, { 9, 2 }, { 10, 0 } }

-- the item and Berry pools by round (< 4, < 7, the rest)
A.ITEMS = {
  { 221, 217, 213, 277, 296, 230, 275, 234, 278, 279, 281 },
  { 214, 271, 266, 267, 253, 232, 265, 276, 268, 270, 278, 279, 281 },
  { 230, 275, 234, 232, 265, 276, 268, 270, 220, 297, 287 },
}
A.BERRIES = {
  { 149, 150, 151, 152, 153, 156, 158, 157 },
  { 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 156, 158, 157 },
  { 156, 158, 157, 201, 202, 203, 204, 205, 206, 207 },
}

local function rand16() return love.math.random(0, 65535) end
local function C() return require("src.script.Gen4BattleTowerCommands") end
local function BT() return require("src.pokemon.Gen4BattleTower") end
local function Castle() return require("src.script.Gen4BattleCastle") end

function A.isMulti(t) return t == A.MULTI or t == A.MULTI_WFC end
function A.partySize(t) return A.isMulti(t) and 2 or 3 end
function A.category(e)
  if e < A.E.LOWER_ALLY_HP then return A.FOE elseif e < A.E.SUNNY then return A.ALLY
  elseif e < A.E.SWAP_MONS then return A.ENV end
  return A.BONUS
end

-- ------------------------------------------------------------- the records --

function A.record(save)
  save.gen4Arcade = save.gen4Arcade or {}
  local r = save.gen4Arcade
  r.streakActive, r.latest, r.records = r.streakActive or {}, r.latest or {}, r.records or {}
  return r
end
function A.clearStreak(save, t)
  local r = A.record(save)
  r.streakActive[t] = nil
  r.latest[t] = 0
end

-- ---------------------------------------------------------------- the run --

-- BattleArcade_Init
function A.init(data, save, resuming, challengeType, s1, s2, s3)
  local r = A.record(save)
  local f = { save = save, data = data, trainerIDs = {}, slots = {}, activeEffect = A.NONE, performance = 0,
              appCursorPos = 0 }
  if resuming == 0 then
    f.challengeType, f.currentBattle, f.rouletteSpeed, f.cursorRandomized = challengeType, 0, 3, false
    r.current = nil
    f.currentStreak = r.streakActive[challengeType] and (r.latest[challengeType] or 0) or 0
    f.slots[0], f.slots[1], f.slots[2] = s1, s2, s3
    f.team = Castle().team(data, save, f.slots, A.partySize(challengeType))
  else
    local cur = r.current or {}
    f.challengeType, f.currentBattle = cur.challengeType or 0, cur.currentBattle or 0
    f.rouletteSpeed, f.cursorRandomized = cur.rouletteSpeed or 3, cur.cursorRandomized or false
    f.currentStreak = r.latest[f.challengeType] or 0
    for i = 0, 2 do f.slots[i] = (cur.slots or {})[i] or i end
    -- LoadPlayersPartyFromSave: the copies again, with the items they held
    f.team = Castle().team(data, save, f.slots, A.partySize(f.challengeType))
    for i, mon in ipairs(f.team) do mon.item = (cur.items or {})[i] end
  end
  f.currentRound = math.floor(f.currentStreak / A.PER_ROUND)
  return f
end

function A.round(f) return f.currentRound end

function A.opponentTrainerID(challengeType, round, offset)
  if challengeType == A.SINGLE then
    local streak = round * A.PER_ROUND + offset + 1
    if streak == A.SILVER then return A.DAHLIA_SILVER elseif streak == A.GOLD then return A.DAHLIA_GOLD end
  end
  if round >= #A.OPPONENT_POOLS then round = #A.OPPONENT_POOLS - 1 end
  local p = A.OPPONENT_POOLS[round + 1]
  local min, spread
  if offset == A.PER_ROUND - 1 or offset == A.PER_ROUND * 2 - 1 then min, spread = p[3], p[4] - p[3]
  else min, spread = p[1], p[2] - p[1] end
  return min + rand16() % spread
end
function A.pickTrainers(challengeType, round, ids, n)
  local i = 0
  while i < n do
    ids[i] = A.opponentTrainerID(challengeType, round, i)
    local dup = false
    for j = 0, i - 1 do if ids[j] == ids[i] then dup = true break end end
    if not dup then i = i + 1 end
  end
end

function A.opponentTeam(data, f)
  local id = f.trainerIDs[f.currentBattle]
  f.monSetIDs = Castle().pickSets(data, id, A.partySize(f.challengeType))
  f.opponentEntries = Castle().entries(data, f.monSetIDs, BT().ivsFor(id or 0))
end
-- BattleArcade_SetupOpponentsParty: level 50, and no items
function A.setupOpponentsParty(game, f)
  f.opponentParty = C().opponentMons(game, f.opponentEntries or {}, A.LEVEL)
  for _, mon in ipairs(f.opponentParty) do mon.item = nil end
end

-- SelectTrainersAndFirstBattlesMons / LoadTrainersAndMonsFromSave
function A.loadRound(data, f, resuming)
  if resuming == 0 then
    A.pickTrainers(f.challengeType, A.round(f), f.trainerIDs, A.PER_ROUND * 2)
    A.opponentTeam(data, f)
    for _, row in ipairs(A.SPEED_BY_ROUND) do
      if A.round(f) >= row[1] then f.rouletteSpeed = row[2] break end
    end
  else
    local cur = A.record(f.save).current or {}
    for k, v in pairs(cur.trainerIDs or {}) do f.trainerIDs[k] = v end
    f.monSetIDs = C().copy(cur.monSetIDs or {})
    f.opponentEntries = Castle().entries(data, f.monSetIDs, BT().ivsFor(f.trainerIDs[f.currentBattle] or 0))
  end
end

-- BattleArcade_Save (0 a round, 1 a loss, 2 a quick save)
function A.save(f, kind)
  local r = A.record(f.save)
  local t = f.challengeType
  r.current = { challengeType = t, currentBattle = f.currentBattle, saved = true, rouletteSpeed = f.rouletteSpeed,
    cursorRandomized = f.cursorRandomized, trainerIDs = {}, slots = { [0] = f.slots[0], f.slots[1], f.slots[2] },
    items = {}, monSetIDs = C().copy(f.monSetIDs or {}) }
  for i, v in pairs(f.trainerIDs) do r.current.trainerIDs[i] = v end
  for i, mon in ipairs(f.team or {}) do r.current.items[i] = mon.item end
  r.latest[t] = f.currentStreak
  if kind ~= 2 then
    if f.currentStreak > (r.records[t] or 0) then r.records[t] = f.currentStreak end
    r.streakActive[t] = f.saveStreak and true or nil
  end
end
function A.saveOnRound(f)
  f.saveStreak = true
  if f.currentRound < A.MAX_ROUNDS then f.currentRound = f.currentRound + 1 end
  f.currentBattle = 0
  A.save(f, 0)
end

function A.earnedBP(f)
  local t = (f.challengeType == A.SINGLE or f.challengeType == A.DOUBLE) and A.BP_SOLO or A.BP_WIFI
  local bp = t[math.min(f.currentRound, A.MAX_ROUNDS)]
  if f.challengeType == A.SINGLE and (f.currentStreak == A.SILVER or f.currentStreak == A.GOLD) then bp = 20 end
  return bp
end
-- BattleArcade_GetFreeBPFromEvent: sBonus1BP / sBonus3BP are 1 and 3 in every round
function A.freeBP(f) return (f.activeEffect == A.E.GET_1_BP) and 1 or 3 end

-- ---------------------------------------------------------- the board --

-- GetAvailableEffects: this round's events, in effect order
function A.available(round, streak)
  local col = math.min(round, 6) + 1
  local battle = streak % A.PER_ROUND
  if streak >= 9999 then battle = 6 end
  local out = {}
  for e = 0, 31 do
    local ok = A.BY_ROUND[e][col]
    if ok and A.BY_BATTLE[e] then ok = A.BY_BATTLE[e][battle + 1] end
    if ok then out[#out + 1] = e end
  end
  return out
end

-- GetEffectCategoryCounts' tier: the first threshold the performance meets
function A.tier(performance)
  for i, t in ipairs(A.TIER_THRESHOLDS) do if performance >= t then return i - 1 end end
  return #A.TIER_THRESHOLDS
end

-- GetRandomCategory
function A.randomCategory(tier, roll)
  roll = roll or (rand16() % 100)
  local sum = 0
  for c = 0, 3 do
    sum = sum + A.WEIGHTS[tier][c + 1]
    if roll < sum then return c end
  end
  return A.FOE
end

-- AssignEffectsToGrid: each panel a category by weight, then an event of it
-- from a random start (the next category round when one has none)
function A.deal(round, streak, performance)
  local avail = A.available(round, streak)
  local count = { [0] = 0, 0, 0, 0 }
  for _, e in ipairs(avail) do local c = A.category(e); count[c] = count[c] + 1 end
  local tier = A.tier(performance)
  local grid = {}
  for i = 1, A.GRID do
    local cat = A.randomCategory(tier)
    local offset = 0
    for c = 0, cat - 1 do offset = offset + count[c] end
    local start = (count[cat] > 0) and (rand16() % count[cat]) + offset or offset
    local idx, loops = start, 0
    while true do
      if loops >= 50 then grid[i] = A.E.LOWER_FOE_HP break end
      local e = avail[(idx % #avail) + 1]
      if A.category(e) == cat then grid[i] = e break end
      idx, loops = idx + 1, loops + 1
      if idx >= #avail then idx = 0 end
      if idx == start then cat = (cat + 1) % 4 end
    end
  end
  return grid
end

-- SetupBattleArcadeAppArgs: the board's inputs, and the team's stats as they
-- stand (put back after the battle)
function A.openBoard(f)
  f.weather, f.immuneToEffect = nil, false
  f.boardRandomized = f.cursorRandomized
  f.cursorRandomized = false
  f.snapshot = C().copy(f.team)
  f.randomIndex = rand16()
  f.grid = A.deal(A.round(f), f.currentStreak, f.performance or 0)
  f.startCursor = rand16() % A.GRID
end

-- ----------------------------------------------------------- the effects --

local function defOf(data, mon) return require("src.pokemon.Gen4Forms").definition(data, mon) end
local function hasType(data, mon, t)
  local def = defOf(data, mon)
  for _, x in ipairs(def and def.types or {}) do if x == t then return true end end
  return false
end
-- the mon's ability, as Abilities.of reads it (a NONE second slot is the first)
local function abilityOf(data, mon)
  local def = defOf(data, mon)
  local list = def and def.abilities or {}
  local a = list[tonumber(mon.abilitySlot) or 1]
  if a == nil or a == 0 or a == "NONE" then a = list[1] end
  return a
end

-- the four statuses: everyone not immune (all immune: immuneToEffect)
local STATUS = {
  { "PSN", function(d, m) return hasType(d, m, "POISON") or hasType(d, m, "STEEL") or abilityOf(d, m) == "IMMUNITY" end },
  { "PAR", function(d, m) return hasType(d, m, "GROUND") or abilityOf(d, m) == "LIMBER" end },
  { "BRN", function(d, m) return hasType(d, m, "FIRE") or abilityOf(d, m) == "WATER_VEIL" end },
}

local function poolFor(f, pools)
  local r = A.round(f)
  if r < 3 then return pools[1] elseif r < 6 then return pools[2] end
  return pools[3]
end

-- BattleArcade_ApplyEffect
function A.applyEffect(f, effect)
  effect = effect or f.activeEffect
  local data = f.data
  local foe = effect < A.E.LOWER_ALLY_HP
  local party = foe and (f.opponentParty or {}) or (f.team or {})
  local base = foe and effect or (effect - A.E.LOWER_ALLY_HP)
  local n = #party
  if effect >= A.E.SUNNY then
    if effect == A.E.SUNNY then f.weather = "SUN" elseif effect == A.E.RAINY then f.weather = "RAIN"
    elseif effect == A.E.SANDY then f.weather = "SANDSTORM" elseif effect == A.E.HAIL then f.weather = "HAIL"
    elseif effect == A.E.FOGGY then f.weather = "FOG" elseif effect == A.E.TRICK_ROOM then f.weather = "TRICK_ROOM"
    elseif effect == A.E.SPEED_UP then if f.rouletteSpeed < 7 then f.rouletteSpeed = f.rouletteSpeed + 1 end
    elseif effect == A.E.SLOW_DOWN then if f.rouletteSpeed > 0 then f.rouletteSpeed = f.rouletteSpeed - 1 end
    elseif effect == A.E.RANDOMIZE_CURSOR then f.cursorRandomized = true end
    return
  end
  if base == 0 then
    -- ArcadeEffect_LowerHP: maxHP - ((u32)(maxHP * 1.2) - maxHP)
    for _, mon in ipairs(party) do
      local max = mon.stats.hp
      mon.hp = max - (math.floor(max * 1.2) - max)
    end
  elseif base >= 1 and base <= 3 then
    local row = STATUS[base]
    local immune = 0
    for _, mon in ipairs(party) do
      if row[2](data, mon) then immune = immune + 1 else mon.status = row[1] end
    end
    if immune >= n then f.immuneToEffect = true end
  elseif base == 4 or base == 5 then
    -- one of them, from the random index on, the first who can be
    local immune, slot = 0, (f.randomIndex or 0) % math.max(1, n)
    for _ = 1, n do
      local mon = party[slot + 1]
      local blocked
      if base == 4 then
        local ab = abilityOf(data, mon)
        blocked = ab == "INSOMNIA" or ab == "VITAL_SPIRIT"
      else
        blocked = hasType(data, mon, "ICE") or abilityOf(data, mon) == "MAGMA_ARMOR"
      end
      if blocked then
        immune = immune + 1
        slot = (slot + 1) % n
      else
        if base == 4 then
          mon.status = "SLP"
          mon.sleepTurns = rand16() % 4 + 2
        else
          mon.status = "FRZ"
        end
        break
      end
    end
    if immune >= n then f.immuneToEffect = true end
  elseif base == 6 or base == 7 then
    local pool = poolFor(f, (base == 6) and A.BERRIES or A.ITEMS)
    local item = pool[(f.randomIndex or 0) % #pool + 1]
    for _, mon in ipairs(party) do mon.item = item end
  elseif base == 8 then
    for _, mon in ipairs(party) do
      local level = math.min(100, (mon.level or 1) + 3)
      Castle().setLevel(data, mon, level)
    end
  end
end

-- BattleArcade_GetPerformance: by the battle's own party (the player's side)
function A.performance(party, turns)
  local status, fainted = 0, 0
  for _, mon in ipairs(party or {}) do
    if (mon.hp or 0) == 0 then fainted = fainted + 1 end
    if mon.status then status = status + 1 end
  end
  local p = A.BY_STATUS[math.min(4, status)] + A.BY_FAINTED[math.min(4, fainted)]
  for _, row in ipairs(A.BY_TURNS) do
    if turns < row[1] then p = p + row[2] break end
  end
  return p
end

-- ------------------------------------------------------------ the lowering --

local F = VM.facility
local emit = VM.emit
F.initbattlearcade = function(ins, s)
  emit(s, { "fr_ba_init", ins.args[1], ins.args[2], ins.args[3], ins.args[4], ins.args[5] })
end
F.battlearcade_loadtrainersforround = function(ins, s) emit(s, { "fr_ba_load_round", ins.args[1] }) end
F.freebattlearcade = function(_, s) emit(s, { "fr_ba_free" }) end
F.openbattlearcadeapp = function(_, s) emit(s, { "fr_ba_app" }) end
F.battlearcade_cleanupbattle = function() end
F.battlearcade_startbattle = function(_, s) emit(s, { "fr_ba_battle" }) end
F.battlearcade_checkwonbattle = function(ins, s) emit(s, { "fr_ba_won", ins.args[1] }) end
F.battlearcade_setupfirstopponent = function(_, s) emit(s, { "fr_ba_first_opponent" }) end
F.battlearcade_setupnextopponent = function(_, s) emit(s, { "fr_ba_next_opponent" }) end
F.callbattlearcadefunction = function(ins, s)
  emit(s, { "fr_ba_call", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
end
F.battlearcade_printtrainerinfo = function(ins, s) emit(s, { "fr_ba_intro", ins.args[1] }) end
F.applyarcadeeffect = function(_, s) emit(s, { "fr_ba_apply" }) end
F.setitemdrawflag = function() end
F.battlearcade_sendcommmessage = function(ins, s) emit(s, { "fr_set", ins.args[3], 1 }) end
F.battlearcade_waitforcommresponses = function() end
-- the board's own sprites (FrontierScrCmd_2A-2D, 31) and a sound stopped
for _, n in ipairs({ "2a", "2b", "2c", "2d", "31", "stopsoundeffect" }) do F[n] = function() end end
F.bufferitemname = function(ins, s) emit(s, { "fr_buffer_kind", ins.args[1], "item", ins.args[2] }) end
F.addtorecordvalue = function(ins, s) emit(s, { "fr_record", ins.args[1], ins.args[2] }) end

local function arcade(ctx) return ctx.game.gen4BattleArcade end

function Commands.fr_ba_init(ctx, resuming, challengeType, s1, s2, s3)
  local v = Fr.value
  ctx.game.gen4BattleArcade = A.init(ctx.game.data, ctx.save, v(ctx, resuming), v(ctx, challengeType),
    v(ctx, s1), v(ctx, s2), v(ctx, s3))
end
function Commands.fr_ba_free(ctx) ctx.game.gen4BattleArcade = nil end
function Commands.fr_ba_load_round(ctx, resuming)
  local f = arcade(ctx)
  if f then A.loadRound(ctx.game.data, f, Fr.value(ctx, resuming)) end
end
function Commands.fr_ba_first_opponent(ctx)
  local f = arcade(ctx)
  if f then A.setupOpponentsParty(ctx.game, f) end
end
function Commands.fr_ba_next_opponent(ctx)
  local f = arcade(ctx)
  if not f then return end
  A.opponentTeam(ctx.game.data, f)
  A.setupOpponentsParty(ctx.game, f)
end
function Commands.fr_ba_apply(ctx)
  local f = arcade(ctx)
  if f and f.activeEffect ~= A.NONE then A.applyEffect(f) end
end

-- the Game Board
function Commands.fr_ba_app(ctx)
  local f = arcade(ctx)
  if not f then return end
  A.openBoard(f)
  local runner = ctx.runner
  ctx.game.stack:push(require("src.ui.Gen4ArcadeScreen").new(ctx.game, {
    arcade = f, onDone = function(effect, pos)
      f.activeEffect, f.appCursorPos = effect, pos or 0
      if runner then runner:resume() end
    end }))
  if runner then runner:yield() end
end

local function trainer(data, id)
  local rec = id and data.gen4_battle_tower and data.gen4_battle_tower.trainers[id]
  return rec and { id = id, class = rec.class, party = {} } or nil
end

-- FrontierScrCmd_CallBattleArcadeFunction (its two arguments are operands)
function Commands.fr_ba_call(ctx, cmd, a1, a2, dest)
  local f = arcade(ctx)
  if not f then Logger.warn("gen4 battle arcade: function %s with no arcade", tostring(cmd)) return end
  cmd = tonumber(cmd) or 0
  a1, a2 = Fr.value(ctx, a1), Fr.value(ctx, a2)
  local game = ctx.game
  local v
  if cmd == 2 then f.challengeType = a1
  elseif cmd == 3 then v = f.appCursorPos or 0
  elseif cmd == 4 then v = f.currentStreak
  elseif cmd == 5 then if f.currentStreak < 9999 then f.currentStreak = f.currentStreak + 1 end
  elseif cmd == 7 then if game.returnToTitle then game:returnToTitle() end
  elseif cmd == 9 then v = (A.record(ctx.save).current or {}).saved and 1 or 0
  elseif cmd == 10 then A.save(f, 2)
  elseif cmd == 12 then v = A.freeBP(f)
  elseif cmd == 14 then f.currentBattle = f.currentBattle + 1; v = f.currentBattle
  elseif cmd == 15 then
    local mon = (a1 == 0) and (f.team or {})[1] or (f.opponentParty or {})[1]
    v = mon and mon.item or 0
  elseif cmd == 16 then v = f.activeEffect
  elseif cmd == 17 then v = f.challengeType
  elseif cmd == 19 then v = A.round(f)
  elseif cmd == 20 then
    local tr = trainer(game.data, f.trainerIDs[f.currentBattle + a1 * A.PER_ROUND])
    v = (tr and BT().CLASS_GFX[tr.class]) or BT().GFX_SCHOOL_KID_M
  elseif cmd == 21 then A.save(f, 1)
  elseif cmd == 22 then A.saveOnRound(f)
  elseif cmd == 23 then v = f.currentBattle
  elseif cmd == 24 then v = 0
  elseif cmd == 28 then v = A.isMulti(f.challengeType) and 1 or 0
  elseif cmd == 38 then
    -- BA_FUNC_SET_NAME_OF_AFFECTED_TRAINER: the foe's name, or yours
    if A.category(f.activeEffect) == A.FOE then
      game.stringBuffers = game.stringBuffers or {}
      game.stringBuffers[a1 + 1] = C().trainerName(game, f.trainerIDs[f.currentBattle + a2 * A.PER_ROUND])
    else
      Commands.g4_buffer(ctx, a1, "player")
    end
  elseif cmd == 40 then
    f.opponents = { [0] = trainer(game.data, f.trainerIDs[f.currentBattle]),
                    trainer(game.data, f.trainerIDs[f.currentBattle + A.PER_ROUND]) }
  elseif cmd == 45 then v = A.earnedBP(f)
  elseif cmd == 47 then v = f.immuneToEffect and 1 or 0
  elseif cmd == 48 then
    v = 0
    if f.challengeType == A.SINGLE then
      if f.currentStreak + 1 == A.SILVER then v = 1 elseif f.currentStreak + 1 == A.GOLD then v = 2 end
    end
  elseif cmd == 49 then
    f.opponentEntries = Castle().entries(game.data, f.monSetIDs or {}, BT().ivsFor(f.trainerIDs[f.currentBattle] or 0))
  elseif cmd == 50 then A.setupOpponentsParty(game, f)
  elseif cmd == 51 then
    v = f.seenStarIntro and 1 or 0
    f.seenStarIntro = true
  end
  -- 0, 1, 8, 13 dummies; 6, 26, 27, 52 the link; 11, 25, 29-37, 39, 41-44,
  -- 46 the board's sprites, palettes, backgrounds and particles; 18 the held
  -- items, which the party never lost
  if v ~= nil then Fr.store(ctx, dest, v) end
end

-- BattleArcade_SetupBattle / CleanupBattle: the effects' teams go in (the
-- two swapped on SWAP_MONS), the weather and field with them; afterwards the
-- team is as it was before the board -- healed, levels back -- but for the
-- items the battle left it holding, and the performance is scored for the
-- next board
function Commands.fr_ba_battle(ctx)
  local f = arcade(ctx)
  local game = ctx.game
  game.gen4BattleArcadeWon = 0
  if not f then return end
  local id = f.trainerIDs[f.currentBattle]
  local who = trainer(game.data, id)
  if not (who and f.opponentParty and f.opponentParty[1]) then
    Logger.warn("gen4 battle arcade: no opponent to battle -- counted as a loss")
    return
  end
  local swap = f.activeEffect == A.E.SWAP_MONS
  local mine = C().copy(swap and f.opponentParty or f.team)
  local theirs = C().copy(swap and f.team or f.opponentParty)
  local double = f.challengeType == A.DOUBLE
  local key = C().registerTrainer(game, "GEN4_BATTLE_ARCADE", who, double, A.LEVEL)
  local rec = game.data.trainers[key]
  rec.parties = { C().prebuilt(theirs, A.LEVEL) }
  for i, slot in ipairs(rec.parties[1]) do slot.level = theirs[i].level end
  local BattleState = require("src.battle.BattleState")
  local real = ctx.save.party
  ctx.save.party = mine
  local ok, battle = pcall(BattleState.newTrainer, game, key, 1)
  if not ok or not battle then
    ctx.save.party = real
    Logger.warn("gen4 battle arcade: could not build the battle: %s", tostring(battle))
    return
  end
  battle.battleTower, battle.canLose, battle.noExp = true, true, true
  -- the board's field: weather for the whole battle, deep fog, Trick Room's five turns
  local Weather = require("src.battle.Weather")
  battle.field = battle.field or {}
  if f.weather == "FOG" then battle.field.deepFog = true
  elseif f.weather == "TRICK_ROOM" then battle.field.trickRoom = 5
  elseif f.weather then Weather.start(battle, f.weather, true) end
  if double then
    battle.double = true
    if battle.sendOutSecondPair then battle:sendOutSecondPair() end
  end
  local runner = ctx.runner
  battle.onFinish = function(result)
    ctx.save.party = real
    game.gen4BattleArcadeWon = (result == "win") and 1 or 0
    f.performance = A.performance(mine, battle.turnCount or 0)
    -- the team as the board found it, healed, holding what the battle left
    local after = swap and theirs or mine
    local snap = f.snapshot or f.team
    f.team = C().copy(snap)
    local P = require("src.pokemon.Pokemon")
    for i, mon in ipairs(f.team) do
      P.heal(mon)
      local b = after[i]
      mon.item = b and b.item or nil
    end
    if runner then runner:resume() end
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  if runner then runner:yield() end
end
function Commands.fr_ba_won(ctx, dest) Fr.store(ctx, dest, ctx.game.gen4BattleArcadeWon or 0) end

function Commands.fr_ba_intro(ctx, n)
  local f = arcade(ctx)
  local o = f and f.opponents and f.opponents[tonumber(n) or 0]
  if not o then return end
  local Gen4Text = require("src.import.Gen4Text")
  return Commands.show_text(ctx, Gen4Text.label(BT().TRAINER_MESSAGES, o.id * 3))
end

return A
