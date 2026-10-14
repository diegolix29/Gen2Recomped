-- THE GAME STATS OF EMERALD AND FIRERED (overworld.c IncrementGameStat /
-- GetGameStat, include/constants/game_stat.h): 52 counters, each stopping
-- at 0xFFFFFF, kept as `save.gen3Stats[id]` -- the same table the scripts'
-- `incrementgamestat` and the save converter use.
--
-- The scripts count most of them (the Pokemon Center, the TV, the cable
-- car...). The engine's own are counted here at the cartridge's moments: a
-- step, a battle begun (all, wild, trainer -- and every 60th wild or 20th
-- trainer battle a chance at a Gym Leader rematch), a capture, an
-- evolution, a hatch, a fish on the line, a purchase, a save, the Pokedex
-- opened, a ledge, Cut and Rock Smash, and the Hall of Fame (with the play
-- time of the first). The Frontier's battles count `battlesCount` instead,
-- with the same rematch chance every 20th.
--
-- Read by the Mauville Storyteller, the Trainer Card, Match Call and the
-- rematch checks below.

local S = {}

S.SAVED_GAME, S.FIRST_HOF_PLAY_TIME, S.STARTED_TRENDS, S.PLANTED_BERRIES, S.TRADED_BIKES = 0, 1, 2, 3, 4
S.STEPS, S.GOT_INTERVIEWED, S.TOTAL_BATTLES, S.WILD_BATTLES, S.TRAINER_BATTLES = 5, 6, 7, 8, 9
S.ENTERED_HOF, S.POKEMON_CAPTURES, S.FISHING_ENCOUNTERS, S.HATCHED_EGGS, S.EVOLVED_POKEMON = 10, 11, 12, 13, 14
S.USED_POKECENTER, S.RESTED_AT_HOME, S.ENTERED_SAFARI_ZONE, S.USED_CUT, S.USED_ROCK_SMASH = 15, 16, 17, 18, 19
S.MOVED_SECRET_BASE, S.POKEMON_TRADES, S.LINK_BATTLE_WINS, S.LINK_BATTLE_LOSSES, S.LINK_BATTLE_DRAWS = 20, 21, 23, 24, 25
S.USED_SPLASH, S.USED_STRUGGLE, S.SLOT_JACKPOTS, S.CONSECUTIVE_ROULETTE_WINS = 26, 27, 28, 29
S.ENTERED_BATTLE_TOWER, S.BATTLE_TOWER_SINGLES_STREAK, S.POKEBLOCKS, S.POKEBLOCKS_WITH_FRIENDS = 30, 32, 33, 34
S.WON_LINK_CONTEST, S.ENTERED_CONTEST, S.WON_CONTEST, S.SHOPPED, S.USED_ITEMFINDER = 35, 36, 37, 38, 39
S.GOT_RAINED_ON, S.CHECKED_POKEDEX, S.RECEIVED_RIBBONS, S.JUMPED_DOWN_LEDGES, S.WATCHED_TV = 40, 41, 42, 43, 44
S.CHECKED_CLOCK, S.WON_POKEMON_LOTTERY, S.USED_DAYCARE, S.RODE_CABLE_CAR, S.ENTERED_HOT_SPRINGS = 45, 46, 47, 48, 49
S.NUM_UNION_ROOM_BATTLES, S.PLAYED_BERRY_CRUSH = 50, 51
S.NUM_USED = 52
S.MAX = 0xFFFFFF

local function stats(save)
  save.gen3Stats = save.gen3Stats or {}
  return save.gen3Stats
end

-- GetGameStat: nothing past the used ones
function S.get(save, id)
  id = tonumber(id)
  if not (save and id) or id < 0 or id >= S.NUM_USED then return 0 end
  return math.floor(tonumber(stats(save)[id]) or 0)
end
function S.set(save, id, v)
  id = tonumber(id)
  if not (save and id) or id < 0 or id >= S.NUM_USED then return end
  stats(save)[id] = math.max(0, math.floor(tonumber(v) or 0))
end
-- IncrementGameStat: one more, stopping at 0xFFFFFF
function S.increment(save, id)
  id = tonumber(id)
  if not (save and id) or id < 0 or id >= S.NUM_USED then return 0 end
  local v = math.min(S.MAX, S.get(save, id) + 1)
  stats(save)[id] = v
  return v
end

-- ------------------------------------------------- the Gym Leader rematch --

-- gym_leader_rematch.c: Roxanne to Juan in the rematch table (REMATCH_ROXANNE
-- 65 .. REMATCH_JUAN 72); Wattson only once New Mauville is done
S.LEADERS_AFTER = { 65, 66, 67, 68, 69, 70, 71, 72 }
S.LEADERS_BEFORE = { 65, 66, 68, 69, 70, 71, 72 }
S.FLAG_GAME_CLEAR = 0x860 + 0x4               -- FLAG_SYS_GAME_CLEAR
S.FLAG_WATTSON_REMATCH = 0x5B                 -- FLAG_WATTSON_REMATCH_AVAILABLE

local function flagSet(save, n)
  local key = require("src.script.Gen3Commands").flagKey(n)
  return (save.flags or {})[key] == true
end

-- GetRematchIndex: the first of the row's five not yet fought (5 if all)
function S.rematchIndex(data, save, index)
  local MC = require("src.script.MatchCall")
  local row = MC.rematchRows(data)[index + 1]
  if not row then return 5 end
  for i = 1, 5 do
    local id = row.trainers[i]
    if id and not MC.beaten(save, id) then return i - 1 end
  end
  return 5
end

-- UpdateGymLeaderRematchFromArray: of the leaders not already waiting, the
-- ones furthest behind (no further than `max`) -- one of them, at random,
-- is armed at that step of the ladder
function S.armLeader(data, save, list, max, rng)
  rng = rng or love.math.random
  local MC = require("src.script.MatchCall")
  local armed = MC.armed(save)
  local lowest, waiting = 5, 0
  for _, i in ipairs(list) do
    if (armed[i] or 0) == 0 then
      lowest = math.min(lowest, S.rematchIndex(data, save, i))
      waiting = waiting + 1
    end
  end
  if waiting == 0 or lowest > max then return nil end
  local pool = {}
  for _, i in ipairs(list) do
    if (armed[i] or 0) == 0 and S.rematchIndex(data, save, i) == lowest then pool[#pool + 1] = i end
  end
  if #pool == 0 then return nil end
  local pick = pool[(rng(0, 65535) % #pool) + 1]
  armed[pick] = lowest
  return pick
end

-- UpdateGymLeaderRematch: after the game is cleared, 31 in 100
function S.updateGymLeaderRematch(data, save, rng)
  rng = rng or love.math.random
  -- Emerald's alone: FireRed's leaders do not come back
  if require("src.core.GameVersion").get() ~= "emerald" then return nil end
  if not flagSet(save, S.FLAG_GAME_CLEAR) then return nil end
  if (rng(0, 65535) % 100) > 30 then return nil end
  if flagSet(save, S.FLAG_WATTSON_REMATCH) then
    return S.armLeader(data, save, S.LEADERS_AFTER, 5, rng)
  end
  return S.armLeader(data, save, S.LEADERS_BEFORE, 1, rng)
end

-- ------------------------------------------------- the engine's moments --

-- battle_setup.c, as a battle begins: all battles, and wild or trainer --
-- with TryUpdateGymLeaderRematchFromWild / FromTrainer after each. A
-- Frontier battle counts frontier.battlesCount instead (HandleSpecialTrainer
-- BattleEnd: every 20th, the same chance), and a link battle nothing.
function S.battleBegun(data, save, battle, rng)
  if not (save and battle) or battle.linkBattle then return end
  if battle.gen3Frontier then
    save.gen3FrontierBattles = math.min(0xFFFFFF, (save.gen3FrontierBattles or 0) + 1)
    if save.gen3FrontierBattles % 20 == 0 then S.updateGymLeaderRematch(data, save, rng) end
    return
  end
  S.increment(save, S.TOTAL_BATTLES)
  if battle.kind == "wild" then
    if S.increment(save, S.WILD_BATTLES) % 60 == 0 then S.updateGymLeaderRematch(data, save, rng) end
    if battle.hooked then S.increment(save, S.FISHING_ENCOUNTERS) end
  elseif battle.kind == "trainer" then
    if S.increment(save, S.TRAINER_BATTLES) % 20 == 0 then S.updateGymLeaderRematch(data, save, rng) end
  end
end

-- battle_scripts_2.s's catch: `incrementgamestat GAME_STAT_POKEMON_CAPTURES`
function S.afterBattle(save, battle, result)
  if save and battle and not battle.gen3Frontier and result == "caught" then
    S.increment(save, S.POKEMON_CAPTURES)
  end
end

-- save.c: entering the Hall of Fame, and post_battle_event_funcs.c: the play
-- time of the first, hours << 16 | minutes << 8 | seconds
function S.enteredHallOfFame(save)
  if S.get(save, S.ENTERED_HOF) < 999 then S.increment(save, S.ENTERED_HOF) end
  if S.get(save, S.FIRST_HOF_PLAY_TIME) == 0 then
    local ok, secs = pcall(function() return require("src.core.SaveData").playSeconds(save) end)
    secs = ok and math.floor(tonumber(secs) or 0) or 0
    local h, m, s = math.min(999, math.floor(secs / 3600)), math.floor(secs / 60) % 60, secs % 60
    S.set(save, S.FIRST_HOF_PLAY_TIME, h * 65536 + m * 256 + s)
  end
end

return S
