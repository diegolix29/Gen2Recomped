-- Gym leader / Elite Four / Champion / Red team replacement -- explicit
-- user spec, generated roster data in overworld/gym_trainer_teams.lua
-- (tools/generate_gym_trainer_teams.ps1, real PBS type/BST/evolution-stage
-- data, not hand-picked). Gen 2 (Gold) only -- every one of these 22
-- trainer classes (FALKNER..RED) only exists in Gold's own roster, so
-- there is nothing for this file to do on a Gen 1 boot.
--
-- Two genuinely separate integration points, confirmed by direct research
-- into this exact question (both Trainer_Rematches and Dynamic_Scaling,
-- the two locally-installed mods that sound relevant, turned out to be
-- Gen-1-only and completely INERT under a Gold boot -- Gen 2's own world/
-- battle modules have no handleInput/trainerDefeated/engageTrainer or
-- BattleState.newTrainer for them to hook at all, confirmed by grep
-- turning up zero matches and by Gen2Compat.lua's own facade explicitly
-- listing newTrainer as absent):
--
-- 1. Roster swap: the "trainer.party" hook. Confirmed identical NAME and
--    argument order on both generations (src/battle/BattleState.lua:
--    715-719 Gen 1, src/battle/gen2/Battle.lua:263-269 Gen 2, both
--    Runtime.call("trainer.party", fn, classId, memberId, party)) --
--    Gen 1's fn's "oppClass" and Gen 2's trainer.classId are the same
--    string id space this file's own ROUND2_CLASSES/team keys use.
--    Documented as generation-matched in docs/mod-api-gen2-compat.md:534.
--
--    CRITICAL, confirmed by reading Battle.lua:254-268 directly, not
--    assumed from the hook's name alone: the 3rd argument on Gen 2 is
--    self.enemyParty, which by that point is ALREADY the fully
--    Trainers.party()-built list of real Mon objects (stats, hp, moves-
--    as-pp-tracked-objects, dvs, everything) -- NOT the raw {species,
--    level, item, moves} definition rows Trainers.party itself consumes
--    one step earlier. A wrapper returning a replacement roster has to
--    hand back the SAME shape: real Mon objects, built the exact same
--    way Trainers.lua's own Trainers.party does (src/world/gen2/
--    Trainers.lua:70-93, Mon.new(data, species, level, {dvs = {attack=9,
--    defense=8, speed=8, special=8}}), no explicit moves so LearnLevelMoves
--    auto-derives the standard level-up moveset, matching every other
--    trainer mon nobody hand-authored a custom moveset for) -- returning
--    bare {level, species} tables here would silently hand the battle
--    engine "mons" with no .stats/.hp/.moves at all.
--
-- 2. Ivs/evs/nature: the EXISTING registerTrainerStatsProvider API
--    (trainer_modern_stats.lua/gen2_modern_stats.lua's shared
--    mod.exports.resolveTrainerSpec) -- already generation-agnostic, no
--    new hook needed. Round-agnostic on purpose: IV 31/EV 85 apply to
--    every one of these trainers' mons regardless of which roster is
--    active, and nature is a pure function of species (gym_trainer_teams
--    .lua's own natures table), so the provider never needs to know which
--    round produced the mon it's looking at -- only ctx.species.
return function(mod, teamsData)
  local ok, Mon = pcall(require, "src.battle.gen2.Mon")
  if not ok or type(Mon) ~= "table" then return end

  local teams = teamsData.teams
  local natures = teamsData.natures

  -- Classes with a round-two roster (Elite Four + Champion only, per
  -- explicit user spec -- the 8 Johto gyms, the 8 Kanto gym-leader
  -- rematch trainers, and Red are each a single always-active roster).
  local ROUND2_CLASSES = {
    WILL = true, KOGA = true, BRUNO = true, KAREN = true, CHAMPION = true,
  }

  -- Every trainer class this file owns -- gates the stats provider below.
  -- Deliberately not species-only: several of these 137 generated-roster
  -- species (e.g. a common Gengar/Toxtricity/Flygon pick) could easily
  -- also appear on some UNRELATED trainer's own team elsewhere in the
  -- game, and "all trainers: IV maxed, EV 85..." was scoped to these 22
  -- named trainers specifically, not every trainer who happens to own the
  -- same species -- so the provider only ever fires inside one of these
  -- classes' own battles.
  local TARGET_CLASSES = {
    FALKNER = true, BUGSY = true, WHITNEY = true, MORTY = true, CHUCK = true,
    JASMINE = true, PRYCE = true, CLAIR = true,
    WILL = true, KOGA = true, BRUNO = true, KAREN = true, CHAMPION = true,
    LT_SURGE = true, SABRINA = true, ERIKA = true, JANINE = true,
    MISTY = true, BROCK = true, BLAINE = true, BLUE = true,
    RED = true,
  }

  -- Real badge-name order, confirmed directly from src/battle/gen2/
  -- Battle.lua's own Battle.JOHTO_BADGE_ORDER/KANTO_BADGE_ORDER (8 each,
  -- 16 total -- matches the user's own "16 badges" threshold exactly).
  -- Counting logic mirrors src/world/gen2/FieldMoves.lua's own
  -- FieldMoves.hasBadge exactly (checked both by name-key and by
  -- positional index, since "a save may key player.badges by name or by
  -- bit position" per that file's own comment) rather than assuming one
  -- shape -- reimplemented here (not required directly) since that module
  -- is Gen-2-only and this needs to answer the same question generically.
  local JOHTO_BADGES = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING" }
  local KANTO_BADGES = { "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }
  local function countOwned(owned, names)
    if type(owned) ~= "table" then return 0 end
    local n = 0
    for i, name in ipairs(names) do
      if owned[name] or owned[i] then n = n + 1 end
    end
    return n
  end

  -- require("src.core.Game") is the Gen2Compat-provided facade specifically
  -- so mod code can reach the live save/data without caring which
  -- generation is running (Gen2Compat.lua's own header: "handed to a
  -- mod's own require... the proxy resolves every key against the live
  -- instance at read time" -- neither .save nor .data is one of the
  -- deliberately-unbacked/translated members, so both resolve straight
  -- through to whichever game is actually live). pcall-guarded: no live
  -- game yet (very early boot) degrades to safe defaults, never an error.
  local function liveGame()
    local reqOk, Game = pcall(require, "src.core.Game")
    if not reqOk or not Game then return nil end
    return Game
  end

  local function badgeCount()
    local game = liveGame()
    local player = game and game.save and game.save.player
    if not player then return 0 end
    return countOwned(player.badges, JOHTO_BADGES) + countOwned(player.kantoBadges, KANTO_BADGES)
  end

  local TRAINER_DVS = { attack = 9, defense = 8, speed = 8, special = 8 }

  local function rosterFor(classId)
    local key = classId .. "_R1"
    if ROUND2_CLASSES[classId] and badgeCount() >= 16 then
      key = classId .. "_R2"
    end
    local team = teams[key]
    if not team then return nil end
    local data = (liveGame() or {}).data
    local roster = {}
    for _, slot in ipairs(team) do
      -- Same construction call Trainers.lua's own Trainers.party uses
      -- (src/world/gen2/Trainers.lua:85-89) -- no explicit moves, so
      -- Mon.new's own LearnLevelMoves derives the standard learnset at
      -- this level, same as every trainer mon nobody hand-authored a
      -- custom moveset for. Fixed DVs match every other trainer mon's
      -- own convention (Trainers.lua's own comment: "the cart gives
      -- every one of them 9/8/8/8/8").
      local mon = Mon.new(data, slot.species, slot.level, { dvs = TRAINER_DVS })
      if mon then roster[#roster + 1] = mon end
    end
    if #roster == 0 then return nil end
    return roster
  end

  mod.hooks:wrap("trainer.party", function(next, classId, memberId, party)
    local pcOk, override = pcall(rosterFor, classId)
    if pcOk and override then return override end
    if not pcOk then
      mod.log:warn("galar_gmax_dex: gym_trainer_teams: roster swap failed for %s: %s",
        tostring(classId), tostring(override))
    end
    return next(classId, memberId, party)
  end)

  -- Ivs/evs/nature provider -- species-keyed, round-agnostic (see header).
  -- Priority above 0 (the implicit default for any other provider) so a
  -- generic/lower-priority provider never silently wins for these species
  -- when both happen to be registered; still defers entirely (returns
  -- nil) for any species not one of this file's own picks, so it can
  -- never affect an unrelated trainer's own party.
  local MAX_IV = 31
  local EV_ALL = 85
  local function statsProvider(ctx)
    local classId = ctx and ctx.oppClass
    if not (classId and TARGET_CLASSES[classId]) then return nil end
    local nature = ctx.species and natures[ctx.species]
    if not nature then return nil end
    -- Separate table literals per stat, not one shared reference -- if
    -- ModernStats.applySpec ever wrote back into a spec's own sub-tables
    -- (it doesn't appear to, but this costs nothing to rule out), sharing
    -- one object across all six would silently cross-contaminate them.
    return {
      nature = nature,
      hp = { iv = MAX_IV, ev = EV_ALL }, atk = { iv = MAX_IV, ev = EV_ALL },
      def = { iv = MAX_IV, ev = EV_ALL }, spa = { iv = MAX_IV, ev = EV_ALL },
      spd = { iv = MAX_IV, ev = EV_ALL }, spe = { iv = MAX_IV, ev = EV_ALL },
    }
  end
  mod.exports.registerTrainerStatsProvider(statsProvider, 50)

  mod.log:info("galar_gmax_dex: gym/E4/champion/red team replacement installed (%d rosters, %d species)",
    (function() local n = 0 for _ in pairs(teams) do n = n + 1 end return n end)(),
    (function() local n = 0 for _ in pairs(natures) do n = n + 1 end return n end)())
end
