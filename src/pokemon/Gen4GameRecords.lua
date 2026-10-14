-- PLATINUM'S GAME RECORDS (src/game_records.c): 71 u32 counters and 77 u16
-- ones, each capped -- 999,999,999 or 999,999 for the first 71, 65,535 or
-- 9,999 for the rest, by sUsesHighLimit -- and the trainer score, record 1,
-- which the score events add to by sTrainerScoreIncrements (capped at
-- 99,999,999). The save keeps them as `save.gen4GameRecords[id]`; the
-- cartridge's encoding of all but the step count is a storage detail.
--
-- Who writes them is spread over the game as on the cartridge: the scripts
-- (`incrementgamerecord`, `addtogamerecord`, `incrementtrainerscore`), the
-- frontier scenes (`IncrementRecordValue` / `AddToRecordValue`), and the
-- engine's own moments -- a step, a battle fought and won, a capture, a new
-- species, a hatch, an evolution, a fish, money spent, the Hall of Fame.

local R = {}

-- generated from pokeplatinum generated/game_records.txt, trainer_score_events.txt and
-- src/game_records.c (sUsesHighLimit, sTrainerScoreIncrements)
R.ID = {
  STEPS = 0,
  TRAINER_SCORE = 1,
  UNK_002 = 2,
  UNK_003 = 3,
  BERRIES_PLANTED = 4,
  UNK_005 = 5,
  UNK_006 = 6,
  WILD_BATTLES_FOUGHT = 7,
  TRAINER_BATTLES_FOUGHT = 8,
  CAUGHT_POKEMON = 9,
  CAUGHT_FISH = 10,
  EGGS_HATCHED = 11,
  POKEMON_EVOLVED = 12,
  UNK_013 = 13,
  UNK_014 = 14,
  BATTLE_TOWER_CHALLENGES = 15,
  UNK_016 = 16,
  UNK_017 = 17,
  UNK_018 = 18,
  LOCAL_LINK_TRADES = 19,
  UNK_020 = 20,
  LOCAL_LINK_BATTLE_WINS = 21,
  LOCAL_LINK_BATTLE_LOSSES = 22,
  UNK_023 = 23,
  WIFI_TRADES = 24,
  UNK_025 = 25,
  WIFI_BATTLE_WINS = 26,
  WIFI_BATTLE_LOSSES = 27,
  UNK_028 = 28,
  BATTLE_TOWER_VICTORIES = 29,
  UNK_030 = 30,
  UNK_031 = 31,
  UNK_032 = 32,
  UNK_033 = 33,
  UNK_034 = 34,
  MONEY_SPENT = 35,
  UNK_036 = 36,
  UNK_037 = 37,
  UNK_038 = 38,
  UNK_039 = 39,
  DEPOSITED_IN_DAYCARE = 40,
  FAINTED_IN_BATTLE = 41,
  UNK_042 = 42,
  UNK_043 = 43,
  UNK_044 = 44,
  TIMES_MAIL_WRITTEN = 45,
  UNK_046 = 46,
  SPHERES_BURIED = 47,
  WATCHED_TV = 48,
  POKEMON_NICKNAMED = 49,
  UNK_050 = 50,
  UNK_051 = 51,
  UNK_052 = 52,
  UNK_053 = 53,
  TIMES_DRESSED_UP_POKEMON = 54,
  UNK_055 = 55,
  TIMES_STUCK_IN_DEEP_MUD = 56,
  TIMES_BATTLED_AT_BATTLEGROUND = 57,
  TIMES_STARTED_BATTLE_FRONTIER_CHALLENGE = 58,
  UNK_059 = 59,
  BATTLE_FACTORY_VICTORIES = 60,
  BATTLE_CASTLE_VICTORIES = 61,
  BATTLE_HALL_VICTORIES = 62,
  BATTLE_ARCADE_VICTORIES = 63,
  BATTLE_FACTORY_TRADES = 64,
  CASTLE_POINTS_RECEIVED = 65,
  UNK_066 = 66,
  UNK_067 = 67,
  BATTLE_POINTS_RECEIVED = 68,
  BATTLE_POINTS_SPENT = 69,
  STAR_PIECES_TRADED = 70,
  UNK_071 = 71,
  UNK_072 = 72,
  TIMES_ENTERED_HALL_OF_FAME = 73,
  UNK_074 = 74,
  UNK_075 = 75,
  USED_SPLASH = 76,
  UNK_077 = 77,
  USED_SELFDESTRUCT = 78,
  USED_EXPLOSION = 79,
  UNK_080 = 80,
  UNK_081 = 81,
  UNK_082 = 82,
  UNK_083 = 83,
  UNK_084 = 84,
  UNK_085 = 85,
  UNK_086 = 86,
  UNK_087 = 87,
  UNK_088 = 88,
  UNK_089 = 89,
  SUPER_CONTEST_PARTICIPATIONS = 90,
  LINK_CONTEST_PARTICIPATIONS = 91,
  OFFICIAL_CONTEST_WINS = 92,
  LINK_CONTEST_WINS = 93,
  RIBBONS_WON = 94,
  USED_INEFFECTIVE_MOVE = 95,
  FAINTED_ENEMY_MON = 96,
  ATTACKED_ALLY = 97,
  FAILED_ESCAPE = 98,
  WILD_MON_FLED = 99,
  FISH_GOT_AWAY = 100,
  UNK_101 = 101,
  UNK_102 = 102,
  UNK_103 = 103,
  UNK_104 = 104,
  UNK_105 = 105,
  UNK_106 = 106,
  UNK_107 = 107,
  UNK_108 = 108,
  UNK_109 = 109,
  UNK_110 = 110,
  UNK_111 = 111,
  UNK_112 = 112,
  UNK_113 = 113,
  TIMES_SIGNED_TRAINER_CARD = 114,
  POKEMON_RECEIVED_FROM_FOSSIL_REVIVAL = 115,
  CHECKED_FOOTPRINTS = 116,
  HONEY_TREE_POKEMON_ENCOUNTERED = 117,
  UNK_118 = 118,
  UNK_119 = 119,
  UNK_120 = 120,
  UNK_121 = 121,
  UNK_122 = 122,
  UNK_123 = 123,
  UNK_124 = 124,
  UNK_125 = 125,
  UNK_126 = 126,
  UNK_127 = 127,
  UNK_128 = 128,
  UNK_129 = 129,
  UNK_130 = 130,
  UNK_131 = 131,
  UNK_132 = 132,
  UNK_133 = 133,
  UNK_134 = 134,
  UNK_135 = 135,
  UNK_136 = 136,
  UNK_137 = 137,
  UNK_138 = 138,
  UNK_139 = 139,
  UNK_140 = 140,
  UNK_141 = 141,
  UNK_142 = 142,
  UNK_143 = 143,
  UNK_144 = 144,
  UNK_145 = 145,
  UNK_146 = 146,
  UNK_147 = 147,
  ORDS = 148,
}
R.HIGH = { [0] = true, [1] = true, [2] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [12] = true, [13] = true, [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true, [20] = true, [21] = true, [22] = true, [23] = true, [24] = true, [25] = true, [26] = true, [27] = true, [28] = true, [29] = true, [30] = true, [31] = true, [32] = true, [33] = true, [34] = true, [35] = true, [36] = true, [37] = true, [38] = true, [39] = true, [40] = true, [57] = true, [58] = true, [59] = true, [60] = true, [61] = true, [62] = true, [63] = true, [64] = true, [65] = true, [66] = true, [67] = true, [68] = true, [69] = true, [71] = true, [72] = true, [74] = true, [75] = true, [94] = true, [112] = true }
R.EVENT = {
  BERRY_HARVESTED = 0,
  HONEY_USED = 1,
  MAIL_WRITTEN = 2,
  TV_INTERVIEW_GIVEN = 3,
  SIGNED_TRAINER_CARD = 4,
  UNK_05 = 5,
  UNK_06 = 6,
  UNK_07 = 7,
  WON_WILD_BATTLE = 8,
  CAPTURED_REGIONAL_MON = 9,
  CAPTURED_NATIONAL_MON = 10,
  WON_TRAINER_BATTLE = 11,
  UNK_12 = 12,
  WIN_OFFICIAL_CONTEST = 13,
  UNK_14 = 14,
  UNK_15 = 15,
  UNK_16 = 16,
  FINISHED_CATCHING_SHOW = 17,
  UNK_18 = 18,
  WIN_LINK_CONTEST = 19,
  UNK_20 = 20,
  FOUGHT_LINK_BATTLE = 21,
  CAUGHT_SPECIES = 22,
  BADGE_EARNED = 23,
  HALL_OF_FAME_ENTRY = 24,
  GTS_TRADE_COMPLETE = 25,
  LOCAL_DEX_DIPLOMA_RECEIVED = 26,
  NATIONAL_DEX_DIPLOMA_RECEIVED = 27,
  UNDERGROUND_CAPTURE_FLAG = 28,
  UNDERGROUND_UNUSED = 29,
  UNDERGROUND_UNCOVER_FOSSIL = 30,
  UNDERGROUND_GIVE_PLAYER_GOODS = 31,
  UNDERGROUND_GREET_PLAYER = 32,
  UNDERGROUND_ASK_PLAYER_QUESTION = 33,
  UNDERGROUND_HELP_TRAPPED_PLAYER = 34,
  UNDERGROUND_NEW_SECRET_BASE = 35,
  UNDERGROUND_ENTERED = 36,
  UNDERGROUND_100_STEPS = 37,
  BATTLE_FACTORY_ROUND_COMPLETED = 38,
  BATTLE_CASTLE_ROUND_COMPLETED = 39,
  BATTLE_HALL_ROUND_COMPLETED = 40,
  BATTLE_ARCADE_ROUND_COMPLETED = 41,
  ALL_BATTLE_FRONTIER_GOLD_PRINTS = 42,
  UNK_43 = 43,
  UNK_44 = 44,
  UNK_45 = 45,
  UNK_46 = 46,
  UNK_47 = 47,
  UNK_48 = 48,
  BOUGHT_ALL_VILLA_FURNITURE = 49,
  UNK_50 = 50,
  ENTS = 51,
}
R.SCORE = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 2, [7] = 2, [8] = 2, [9] = 2, [10] = 3, [11] = 3, [12] = 3, [13] = 7, [14] = 7, [15] = 7, [16] = 10, [17] = 10, [18] = 11, [19] = 11, [20] = 11, [21] = 11, [22] = 20, [23] = 30, [24] = 35, [25] = 40, [26] = 500, [27] = 10000, [28] = 30, [29] = 30, [30] = 2, [31] = 5, [32] = 1, [33] = 1, [34] = 5, [35] = 3, [36] = 1, [37] = 1, [38] = 7, [39] = 7, [40] = 7, [41] = 7, [42] = 1000, [43] = 11, [44] = 20, [45] = 10, [46] = 15, [47] = 11, [48] = 11, [49] = 10, [50] = 10, [51] = 0 }

R.TRAINER_SCORE_LIMIT = 99999999

-- GetRecordLimit
function R.limit(id)
  if id < 71 then return R.HIGH[id] and 999999999 or 999999 end
  return R.HIGH[id] and 65535 or 9999
end

local function store(save)
  save.gen4GameRecords = save.gen4GameRecords or {}
  return save.gen4GameRecords
end

-- GameRecords_GetRecordValue: never past the limit
function R.get(save, id)
  if not (save and id) then return 0 end
  local v = tonumber(store(save)[id]) or 0
  return math.min(v, R.limit(id))
end

-- GameRecords_SetRecordValue
function R.set(save, id, v)
  if not (save and id and id >= 0 and id < 148) then return 0 end
  v = math.min(math.max(0, math.floor(tonumber(v) or 0)), R.limit(id))
  store(save)[id] = v
  return v
end

-- GameRecords_AddToRecordValue / IncrementRecordValue (cur + n, capped)
function R.add(save, id, n)
  if not (save and id) then return 0 end
  local cur = tonumber(store(save)[id]) or 0
  return R.set(save, id, cur + math.max(0, math.floor(tonumber(n) or 0)))
end
function R.increment(save, id) return R.add(save, id, 1) end

-- GameRecords_SetAndLimitRecordValue: only ever upward
function R.raise(save, id, v)
  if (tonumber(store(save)[id]) or 0) < (tonumber(v) or 0) then return R.set(save, id, v) end
  return R.get(save, id)
end

-- GameRecords_IncrementTrainerScore
function R.score(save, event)
  local inc = R.SCORE[tonumber(event) or -1]
  if not (save and inc) then return 0 end
  local cur = R.get(save, R.ID.TRAINER_SCORE)
  if cur + inc > R.TRAINER_SCORE_LIMIT then
    store(save)[R.ID.TRAINER_SCORE] = R.TRAINER_SCORE_LIMIT
    return R.TRAINER_SCORE_LIMIT
  end
  return R.add(save, R.ID.TRAINER_SCORE, inc)
end
function R.trainerScore(save) return R.get(save, R.ID.TRAINER_SCORE) end

-- the Frontier scenes' `IncrementRecordValue` (fr_record)
function R.incrementRecord(save, id) return R.increment(save, id) end

-- ------------------------------------------------- the engine's moments --

-- encounter.c's battle-end bookkeeping (the fought counts are taken as the
-- battle starts on the cartridge, so a battle abandoned to a reset counts
-- there and not here -- the totals are otherwise the same), and the score
-- (UpdateGameRecords): a wild win 2, a capture 2 in the Sinnoh dex or 3
-- outside it, a trainer win 3. Never for a link or a Frontier battle.
function R.afterBattle(data, save, battle, result)
  if not (save and battle) or battle.linkBattle or battle.battleTower then return end
  local kind = battle.kind
  if kind == "wild" then
    R.increment(save, R.ID.WILD_BATTLES_FOUGHT)
    if battle.gen4Safari then
      if result == "caught" then R.scoreCapture(data, save, battle) end
    elseif result == "win" then
      R.score(save, R.EVENT.WON_WILD_BATTLE)
    elseif result == "caught" then
      R.scoreCapture(data, save, battle)
    end
  elseif kind == "trainer" then
    R.increment(save, R.ID.TRAINER_BATTLES_FOUGHT)
    if result == "win" then R.score(save, R.EVENT.WON_TRAINER_BATTLE) end
  end
  if result == "caught" then R.increment(save, R.ID.CAUGHT_POKEMON) end
  if battle.hooked then R.increment(save, R.ID.CAUGHT_FISH) end
end

-- a new page in the Pokedex at a catch (battle_script.c,
-- BattleSystem_TryIncrementTrainerScoreCaughtSpecies): 20 points
function R.newSpecies(save) return R.score(save, R.EVENT.CAUGHT_SPECIES) end

-- evolution.c: every evolution counts, and scores as a caught species
-- whether the species was new or not
function R.evolved(save)
  R.increment(save, R.ID.POKEMON_EVOLVED)
  R.score(save, R.EVENT.CAUGHT_SPECIES)
end

-- field_control.c Field_UpdateDaycare: a hatch, and 7 points (event 15)
function R.hatched(save)
  R.increment(save, R.ID.EGGS_HATCHED)
  R.score(save, R.EVENT.UNK_15)
end

-- GetDexNumber(0, species): in the Sinnoh dex, or not. The cartridge reads the
-- first enemy slot even when the partner's double caught the second (its bug).
function R.inSinnohDex(data, species)
  local orders = data and data.gen4_dex and data.gen4_dex.orders and data.gen4_dex.orders.sinnoh
  local n = tonumber(species)
  for _, id in ipairs(orders or {}) do if tonumber(id) == n then return true end end
  return false
end
function R.scoreCapture(data, save, battle)
  local mon = battle.enemyParty and battle.enemyParty[1] or (battle.enemy and battle.enemy.mon)
  local regional = mon and R.inSinnohDex(data, mon.species)
  R.score(save, regional and R.EVENT.CAPTURED_REGIONAL_MON or R.EVENT.CAPTURED_NATIONAL_MON)
end

-- ------------------------------------------------------------- the Villa --

-- VAR_BATTLE_*_PRINT_STATE: Tower, Factory, Hall, Castle, Arcade (2 = the
-- silver print taken)
R.PRINT_STATE_VARS = { 0x404F, 0x4050, 0x4051, 0x4052, 0x4053 }

-- ScrCmd_CheckMetFurnitureRequirements: `piece` is the furniture id + 1, as
-- the scripts pass it; anything not listed needs nothing
function R.villa(save, piece, getVar)
  local id = R.ID
  piece = tonumber(piece) or 0
  if piece == 13 then          -- VILLA_FURNITURE_POKEMON_BUST: a win in every facility
    for _, rec in ipairs({ id.BATTLE_TOWER_VICTORIES, id.BATTLE_FACTORY_VICTORIES, id.BATTLE_CASTLE_VICTORIES,
                           id.BATTLE_HALL_VICTORIES, id.BATTLE_ARCADE_VICTORIES }) do
      if R.get(save, rec) < 1 then return false end
    end
    return true
  elseif piece == 14 then      -- _SILVER: one facility's silver print
    for _, v in ipairs(R.PRINT_STATE_VARS) do
      if (tonumber(getVar and getVar(v)) or 0) >= 2 then return true end
    end
    return false
  elseif piece == 15 then return R.get(save, id.TIMES_ENTERED_HALL_OF_FAME) >= 10   -- PIANO
  elseif piece == 16 then return R.get(save, id.TIMES_BATTLED_AT_BATTLEGROUND) >= 50 -- GUEST_SET
  elseif piece == 17 then return R.get(save, id.BERRIES_PLANTED) >= 50              -- WALL_CLOCK
  elseif piece == 18 then return R.get(save, id.EGGS_HATCHED) >= 30                 -- MASTERPIECE
  elseif piece == 20 then return R.get(save, id.STEPS) >= 300000                    -- CHANDELIER
  end
  return true
end

return R
