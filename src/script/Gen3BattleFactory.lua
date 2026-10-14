-- EMERALD'S BATTLE FACTORY (pokeemerald battle_factory.c, CallBattleFactoryFunction
-- = special 241, and battle_tower.c's FillFactoryTrainerParty).
--
-- You battle with Pokemon you rent: six are offered, you take three, and
-- after every win you may give one of yours for one of the team you just
-- beat. Your own party waits in the lobby (SavePlayerParty / LoadPlayerParty).
-- Seven trainers a challenge; Noland, the Factory Head, at the 21st and 42nd.
--
-- THE POOL: gBattleFrontierMons (the cache's gen3FrontierParties.mons), drawn
-- by streak tier (sInitialRentalMonRanges) -- the more you have rented this
-- streak, the more of the six come from the next tier up. Rentals and
-- opponents alike take the tier's fixed IVs (sFixedIVTable), the set's own
-- nature and EV spread, friendship 0, and FRUSTRATION wherever the set says
-- RETURN (SetMonMoveAvoidReturn).
--
-- KEPT, ON PURPOSE: the cartridge picks the OPPONENTS' IVs from the Battle
-- Tower's level-50 streak, not the Factory's (the BUGFIX comment in
-- FillFactoryFrontierTrainerParty); so does this.
--
-- The hints before each battle -- the next team's most common type and its
-- "style" -- are GetOpponentMostCommonMonType and GetOpponentBattleStyle over
-- the same seven move lists.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")

local P = {}

P.FACILITY = 4
P.PARTY = 3
-- sInitialRentalMonRanges: level 50 rows 1-8, open level rows 9-16 (0-based monIds)
P.RANGES = {
  { 110, 199 }, { 162, 266 }, { 267, 371 }, { 372, 467 }, { 468, 563 }, { 564, 659 }, { 660, 755 }, { 372, 849 },
  { 372, 467 }, { 468, 563 }, { 564, 659 }, { 660, 755 }, { 372, 881 }, { 372, 881 }, { 372, 881 }, { 372, 881 },
}
-- sFixedIVTable: { regular, the challenge's seventh }
P.IVS = { { 3, 6 }, { 6, 9 }, { 9, 12 }, { 12, 15 }, { 15, 18 }, { 21, 31 }, { 31, 31 }, { 31, 31 } }
P.HIGH_TIER = 849
-- sBattlePointAwards' factory columns (singles, doubles)
P.BP = {
  [0] = { 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 15, 15, 15, 15 },
  [1] = { 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 15, 15, 15, 15, 15, 15 },
}
-- TYPE_* (Emerald's order; TYPE_MYSTERY at 9)
P.TYPES = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6, GHOST = 7,
  STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15,
  DRAGON = 16, DARK = 17 }
P.NUM_TYPES = 18
-- sRequiredMoveCounts and sMoveStyles (FACTORY_STYLE_PREPARATION .. _WEATHER)
P.STYLE_NEED = { 3, 3, 3, 2, 2, 2, 2 }
P.STYLES = {
  { "SWORDS_DANCE", "GROWTH", "MEDITATE", "AGILITY", "DOUBLE_TEAM", "HARDEN", "MINIMIZE", "WITHDRAW",
    "DEFENSE_CURL", "BARRIER", "FOCUS_ENERGY", "AMNESIA", "ACID_ARMOR", "SHARPEN", "CONVERSION",
    "CONVERSION_2", "BELLY_DRUM", "PSYCH_UP", "CHARGE", "SNATCH", "TAIL_GLOW", "COSMIC_POWER",
    "IRON_DEFENSE", "HOWL", "BULK_UP", "CALM_MIND", "DRAGON_DANCE" },
  { "SING", "SUPERSONIC", "DISABLE", "LEECH_SEED", "POISON_POWDER", "STUN_SPORE", "SLEEP_POWDER",
    "THUNDER_WAVE", "TOXIC", "HYPNOSIS", "CONFUSE_RAY", "GLARE", "POISON_GAS", "LOVELY_KISS", "SPORE",
    "SPIDER_WEB", "SWEET_KISS", "SPIKES", "SWAGGER", "MEAN_LOOK", "ATTRACT", "ENCORE", "TORMENT",
    "FLATTER", "WILL_O_WISP", "TAUNT", "YAWN", "IMPRISON", "SNATCH", "TEETER_DANCE", "GRASS_WHISTLE", "BLOCK" },
  { "MIST", "RECOVER", "LIGHT_SCREEN", "HAZE", "REFLECT", "SOFT_BOILED", "REST", "PROTECT", "DETECT",
    "ENDURE", "MILK_DRINK", "HEAL_BELL", "SAFEGUARD", "BATON_PASS", "MORNING_SUN", "SYNTHESIS",
    "MOONLIGHT", "SWALLOW", "WISH", "INGRAIN", "MAGIC_COAT", "RECYCLE", "REFRESH", "MUD_SPORT",
    "SLACK_OFF", "AROMATHERAPY", "WATER_SPORT" },
  { "GUILLOTINE", "HORN_DRILL", "DOUBLE_EDGE", "HYPER_BEAM", "COUNTER", "FISSURE", "BIDE",
    "SELF_DESTRUCT", "SKY_ATTACK", "EXPLOSION", "FLAIL", "REVERSAL", "DESTINY_BOND", "PERISH_SONG",
    "PAIN_SPLIT", "MIRROR_COAT", "MEMENTO", "GRUDGE", "FACADE", "FOCUS_PUNCH", "BLAST_BURN",
    "HYDRO_CANNON", "OVERHEAT", "FRENZY_PLANT", "PSYCHO_BOOST", "VOLT_TACKLE" },
  { "SAND_ATTACK", "TAIL_WHIP", "LEER", "GROWL", "STRING_SHOT", "SCREECH", "SMOKESCREEN", "KINESIS",
    "FLASH", "COTTON_SPORE", "SPITE", "SCARY_FACE", "CHARM", "KNOCK_OFF", "SWEET_SCENT", "FEATHER_DANCE",
    "FAKE_TEARS", "METAL_SOUND", "TICKLE" },
  { "MIMIC", "METRONOME", "MIRROR_MOVE", "TRANSFORM", "SUBSTITUTE", "SKETCH", "CURSE", "PRESENT",
    "FOLLOW_ME", "TRICK", "ROLE_PLAY", "ASSIST", "SKILL_SWAP", "CAMOUFLAGE" },
  { "SANDSTORM", "RAIN_DANCE", "SUNNY_DAY", "HAIL", "WEATHER_BALL" },
}

local function F() return require("src.script.Gen3BattleFrontier") end
local function G3() return require("src.script.Gen3Commands") end
local function getVar(ctx, id) return math.floor(tonumber(G3().getVar(ctx.save, id)) or 0) end
local function setVar(ctx, id, v) G3().setVar(ctx.save, id, math.floor(tonumber(v) or 0)) end
local function rand(n) return love.math.random(0, n - 1) end
local function key(mode, lvl) return ("%d:%d"):format(mode, lvl) end
local function norm(id) return (tostring(id or ""):gsub("_", "")) end

function P.state(save)
  local s = F().state(save)
  s.factory = s.factory or { rentals = {}, temp = {}, rents = {} }
  return s, s.factory
end
local function lvlOf(s) return math.floor(tonumber(s.data[1]) or 0) end
local function modeOf(ctx) return getVar(ctx, F().VAR_MODE) end
function P.streak(s, mode, lvl) return F().streak(s, mode, lvl, P.FACILITY) end
function P.challengeNum(s, mode, lvl) return math.floor(P.streak(s, mode, lvl) / 7) end
function P.row(data, monId) local p = F().parties(data); return p and p.mons[monId + 1] end

-- GetFactoryMonId
function P.monIdFor(lvlMode, challengeNum, better)
  local adder = (lvlMode == 0) and 0 or 8
  local i
  if challengeNum < 7 then i = adder + challengeNum + (better and 1 or 0) else i = adder + 7 end
  local r = P.RANGES[i + 1]
  return r[1] + rand(r[2] - r[1] + 1)
end
-- GetFactoryMonFixedIV (the cartridge's `>` bound: challenge 8 reads past the table, which lands on random IVs)
function P.fixedIV(challengeNum, last)
  local set = (challengeNum > #P.IVS) and #P.IVS or (challengeNum + 1)
  local row = P.IVS[set] or P.IVS[#P.IVS]
  return row[last and 2 or 1]
end
-- GetNumPastRentalsRank
function P.rentalRank(rents)
  rents = rents or 0
  if rents < 15 then return 0 elseif rents < 22 then return 1 elseif rents < 29 then return 2
  elseif rents < 36 then return 3 elseif rents < 43 then return 4 end
  return 5
end

-- a rental or a Factory opponent: the set, the IVs, friendship 0, Return made Frustration
function P.makeMon(data, monId, level, iv, personality, otId)
  local row = P.row(data, monId)
  if not row then return nil end
  local moves = {}
  for i, m in ipairs(row.moves or {}) do moves[i] = (m == "RETURN") and "FRUSTRATION" or m end
  local mon = F().makeMon(data, row.species, level, row.nature or 0, iv, F().spread(row.ev or 0),
                          row.item, moves, otId)
  if not mon then return nil end
  mon.happiness = 0
  if personality then
    mon.personality = personality
    local def = require("src.pokemon.Gen4Forms").definition(data, mon)
    if def and type(def.abilities) == "table" then
      mon.abilitySlot = def.abilities[2] and (personality % 2) + 1 or 1
    end
  end
  mon.factoryId = monId
  return mon
end

local function levelFor(ctx, s)
  return (lvlOf(s) == 0) and 50 or 100
end
local function otId(save)
  local id = save.player and tonumber(save.player.id)
  return id or 0
end

-- the six offered (CreateFrontierFactorySelectableMons): rank-many from the next tier's IVs
function P.offered(ctx)
  local s, fk = P.state(ctx.save)
  local mode, lvl = modeOf(ctx), lvlOf(s)
  local c = P.challengeNum(s, mode, lvl)
  local rank = P.rentalRank(fk.rents[key(mode, lvl)])
  local out = {}
  for i = 1, 6 do
    local rec = fk.rentals[i]
    if rec then
      local iv = P.fixedIV(c + ((i - 1) < rank and 1 or 0), false)
      out[i] = P.makeMon(ctx.game.data, rec.monId, levelFor(ctx, s), iv, nil, otId(ctx.save))
    end
  end
  return out
end

-- GenerateInitialRentalMons: six, no species twice (but for one pair the
-- cartridge's own loop lets through), no held item twice
function P.generateRentals(ctx)
  local s, fk = P.state(ctx.save)
  local mode, lvl = modeOf(ctx), lvlOf(s)
  local c = P.challengeNum(s, mode, lvl)
  local factoryLvl = (lvl ~= 0) and 1 or 0
  local rank = P.rentalRank(fk.rents[key(mode, lvl)])
  local data = ctx.game.data
  local species, items, ids = {}, {}, {}
  local cur
  local i, guard = 0, 0
  fk.rentals = {}
  while i < 6 and guard < 20000 do
    guard = guard + 1
    local monId = P.monIdFor(factoryLvl, c, i < rank)
    local row = P.row(data, monId)
    local ok = row ~= nil and row.species ~= "UNOWN"
    if ok then
      for j = 1, i do
        if ids[j] == monId then ok = false break end
        if species[j] == row.species then
          if cur == nil then cur = row.species else ok = false break end
        end
      end
    end
    if ok then
      for j = 1, i do
        if items[j] and items[j] == row.item then
          if row.species == cur then cur = nil end
          ok = false
          break
        end
      end
    end
    if ok then
      i = i + 1
      fk.rentals[i] = { monId = monId }
      species[i], items[i], ids[i] = row.species, row.item, monId
    end
  end
end

-- GenerateOpponentMons: the trainer (no repeats this challenge) and three
-- sets, none the species of anything on offer to you
function P.generateOpponent(ctx)
  local Fr = F()
  local s, fk = P.state(ctx.save)
  local mode, lvl = modeOf(ctx), lvlOf(s)
  local c = P.challengeNum(s, mode, lvl)
  local battleNum = math.floor(tonumber(s.data[2]) or 0)
  s.trainerIds = s.trainerIds or {}
  local id
  repeat
    id = Fr.trainerFor(c, battleNum)
    local seen = false
    for i = 0, battleNum - 1 do if s.trainerIds[i] == id then seen = true end end
  until not seen
  s.opponent = id
  if battleNum < 6 then s.trainerIds[battleNum] = id end
  local data = ctx.game.data
  local offered = {}
  for _, rec in pairs(fk.rentals) do
    local row = rec and P.row(data, rec.monId)
    if row then offered[row.species] = true end
  end
  fk.temp = {}
  local species, items = {}, {}
  local i, guard = 0, 0
  while i < P.PARTY and guard < 20000 do
    guard = guard + 1
    local monId = P.monIdFor(lvl, c, false)
    local row = P.row(data, monId)
    local ok = row ~= nil and row.species ~= "UNOWN" and not offered[row.species]
    if ok and lvl == 0 and monId > P.HIGH_TIER then ok = false end
    if ok then for k = 1, i do if species[k] == row.species then ok = false end end end
    if ok then for k = 1, i do if items[k] and items[k] == row.item then ok = false end end end
    if ok then
      i = i + 1
      species[i], items[i] = row.species, row.item
      fk.temp[i] = monId
    end
  end
end

-- GetOpponentMostCommonMonType
function P.commonType(ctx)
  local _, fk = P.state(ctx.save)
  local data = ctx.game.data
  local counts = {}
  for t = 0, P.NUM_TYPES - 1 do counts[t] = 0 end
  for _, monId in ipairs(fk.temp) do
    local row = P.row(data, monId)
    local def = row and data.pokemon and data.pokemon[row.species]
    local types = def and def.types or {}
    local a, b = P.TYPES[types[1] or ""], P.TYPES[types[2] or types[1] or ""]
    if a then counts[a] = counts[a] + 1 end
    if b and b ~= a then counts[b] = counts[b] + 1 end
  end
  local top, second = 0, 0
  for t = 1, P.NUM_TYPES - 1 do
    if counts[top] < counts[t] then top = t
    elseif counts[top] == counts[t] then second = t end
  end
  if counts[top] == 0 then return P.NUM_TYPES end
  if counts[top] > counts[second] or top == second then return top end
  return P.NUM_TYPES
end

-- GetOpponentBattleStyle
function P.style(ctx)
  local _, fk = P.state(ctx.save)
  local data = ctx.game.data
  local points = { 0, 0, 0, 0, 0, 0, 0 }
  local lookup = {}
  for i, list in ipairs(P.STYLES) do
    for _, m in ipairs(list) do lookup[norm(m)] = lookup[norm(m)] or i end
  end
  for _, monId in ipairs(fk.temp) do
    local row = P.row(data, monId)
    for _, m in ipairs(row and row.moves or {}) do
      local st = lookup[norm(m)]
      if st then points[st] = points[st] + 1 end
    end
  end
  local result, count = 0, 0
  for i = 1, 7 do
    if points[i] >= P.STYLE_NEED[i] then result = i; count = count + 1 end
  end
  if count > 2 then result = 8 end
  return result
end

-- the player's three from their records (SetPlayerAndOpponentParties)
function P.rebuildParty(ctx)
  local s, fk = P.state(ctx.save)
  local party = {}
  for i = 1, P.PARTY do
    local rec = fk.rentals[i]
    local mon = rec and P.makeMon(ctx.game.data, rec.monId, levelFor(ctx, s), rec.ivs or 0, rec.personality,
                                  otId(ctx.save))
    if mon then party[#party + 1] = mon end
  end
  ctx.save.party = party
end

-- -------------------------------------------------------------- the screens --

local function runScreen(ctx, opts)
  local Screen = require("src.ui.Gen3FactoryScreen")
  local runner = ctx.runner
  local result
  opts.onDone = function(r) result = r; if runner then runner:resume() end end
  ctx.game.stack:push(Screen.new(ctx.game, opts))
  if runner then runner:yield() end
  return result
end

-- SelectInitialRentalMons: three of the six, in the order chosen
function P.select(ctx)
  local _, fk = P.state(ctx.save)
  local mons = P.offered(ctx)
  local picks = runScreen(ctx, { mode = "select", mons = mons })
  if not picks or #picks < P.PARTY then picks = { 1, 2, 3 } end
  local chosen, party = {}, {}
  for i, idx in ipairs(picks) do
    local mon = mons[idx]
    party[i] = mon
    chosen[i] = { monId = fk.rentals[idx].monId, ivs = mon and mon.ivs and mon.ivs.attack or 0,
                  personality = mon and mon.personality }
  end
  for i = 1, P.PARTY do fk.rentals[i] = chosen[i] end
  for i = P.PARTY + 1, 6 do fk.rentals[i] = nil end
  ctx.save.party = party
end

-- SwapRentalMons: one of yours for one of theirs, or keep; VAR_RESULT TRUE when kept
function P.swap(ctx)
  local _, fk = P.state(ctx.save)
  local theirs = fk.beaten or {}
  local r = runScreen(ctx, { mode = "swap", mons = ctx.save.party, theirs = theirs })
  if not (r and r.give and r.take and theirs[r.take]) then
    setVar(ctx, 0x800D, 1)
    return
  end
  -- CopySwappedMonData
  local mon = theirs[r.take]
  mon.happiness = 0
  ctx.save.party[r.give] = mon
  fk.rentals[r.give] = { monId = fk.rentals[P.PARTY + r.take].monId, ivs = fk.rentals[P.PARTY + r.take].ivs,
                         personality = mon.personality }
  setVar(ctx, 0x800D, 0)
end

-- ----------------------------------------------------------------- the battle --

-- SPECIAL_BATTLE_FACTORY: the next team (or Noland's), against your rentals
function P.battle(ctx)
  local Fr = F()
  local data = ctx.game.data
  local s, fk = P.state(ctx.save)
  local mode, lvl = modeOf(ctx), lvlOf(s)
  local level = Fr.enemyLevel(ctx.save, lvl)
  local party = {}
  local name, pic, class, className
  if s.opponent == Fr.BRAIN then
    -- FillFactoryBrainParty: three at random, IVs two challenges ahead
    local c = P.challengeNum(s, mode, lvl)
    local iv = P.fixedIV(c + 2, false)
    local taken, species, items, guard = {}, {}, {}, 0
    for _, rec in pairs(fk.rentals) do if rec then taken[rec.monId] = true end end
    while #party < P.PARTY and guard < 20000 do
      guard = guard + 1
      local monId = P.monIdFor(lvl, c, false)
      local row = P.row(data, monId)
      local ok = row and row.species ~= "UNOWN" and not taken[monId]
                 and not (level == 50 and monId > P.HIGH_TIER) and not species[row.species]
                 and not (row.item and items[row.item])
      if ok then
        local mon = P.makeMon(data, monId, level, iv, nil, otId(ctx.save))
        if mon then
          party[#party + 1] = mon
          species[row.species], items[row.item or false] = true, true
        end
      end
    end
    local a = data.trainers and data.trainers.NOLAND
    name, pic, class, className = "NOLAND", a and a.pic, a and a.class, a and a.className
  else
    -- FillFactoryFrontierTrainerParty: the Battle Tower's level-50 streak picks the IVs
    local towerC = math.floor(Fr.streak(s, mode, 0) / 7)
    local last = (math.floor(tonumber(s.data[2]) or 0) >= 6)
    local iv = P.fixedIV(towerC, last)
    for _, monId in ipairs(fk.temp) do
      local mon = P.makeMon(data, monId, level, iv, nil, otId(ctx.save))
      if mon then party[#party + 1] = mon end
    end
    local tr = Fr.trainerRecord(data, s.opponent) or {}
    name, pic, class, className = tr.name, tr.pic, tr.class, tr.className
  end
  if not party[1] then
    Logger.warn("gen3 battle factory: no team for opponent %s -- counted as a loss", tostring(s.opponent))
    s.lastOutcome = 2
    setVar(ctx, 0x800D, 2)
    return
  end
  fk.enemy = party
  local slots = {}
  for i, mon in ipairs(party) do slots[i] = { species = mon.species, level = level, prebuilt = mon } end
  data.trainers[Fr.TRAINER_KEY] = { id = Fr.TRAINER_KEY, name = name or "TRAINER", pic = pic, class = class,
    className = className, party = slots, parties = { slots }, baseMoney = 0 }
  Commands.start_battle(ctx, "trainer", Fr.TRAINER_KEY, 1,
    { frontier = true, double = (mode == Fr.DOUBLES) or nil, canLose = true, noExp = true, forfeit = true, noItems = true })
  s.lastOutcome = (ctx.lastBattleResult == "win") and 1 or 2
  setVar(ctx, 0x800D, s.lastOutcome)
end

-- ------------------------------------------------ CallBattleFactoryFunction --

function P.func(ctx, arg)
  local Fr = F()
  local s, fk = P.state(ctx.save)
  local mode, lvl = modeOf(ctx), lvlOf(s)
  local a5, a6 = getVar(ctx, 0x8005), getVar(ctx, 0x8006)
  local act = Fr.actives(s, P.FACILITY)
  local k = key(mode, lvl)
  if arg == 0 then              -- InitFactoryChallenge
    s.data[0], s.data[2], s.data[3], s.data[6] = 0, 0, 0, 1
    if not act[k] then
      Fr.setStreak(s, mode, lvl, 0, P.FACILITY)
      fk.rents[k] = 0
    end
    fk.swapped = nil
    fk.rentals, fk.temp = {}, {}
    s.trainerIds = {}
    local ow = ctx.overworld
    if ow and ow.map and ow.player then
      s.continueAt = { map = ow.map.id, x = ow.player.cellX, y = ow.player.cellY }
    end
    s.opponent = nil
  elseif arg == 1 then          -- GetBattleFactoryData
    local v = 0
    if a5 == 1 then v = P.streak(s, mode, lvl)
    elseif a5 == 2 then v = act[k] and 1 or 0
    elseif a5 == 3 then v = fk.rents[k] or 0 end
    setVar(ctx, 0x800D, v)
  elseif arg == 2 then          -- SetBattleFactoryData
    if a5 == 1 then Fr.setStreak(s, mode, lvl, a6, P.FACILITY)
    elseif a5 == 2 then act[k] = (a6 ~= 0) or nil
    elseif a5 == 3 then
      if fk.swapped then fk.rents[k] = a6; fk.swapped = nil end
    end
  elseif arg == 3 then          -- SaveFactoryChallenge
    s.data[0] = a5
    setVar(ctx, Fr.VAR_STATUS, 0)
    s.data[3] = 1
    Fr.saveFrontier(ctx)
  elseif arg == 4 or arg == 5 then
  elseif arg == 6 then P.select(ctx)
  elseif arg == 7 then P.swap(ctx)
  elseif arg == 8 then fk.swapped = true
  elseif arg == 9 then          -- SetRentalsToOpponentParty: the team just beaten, for the swap
    fk.beaten = {}
    for i = 1, P.PARTY do
      local mon = fk.enemy and fk.enemy[i]
      fk.rentals[P.PARTY + i] = { monId = fk.temp[i], ivs = mon and mon.ivs and mon.ivs.attack or 0,
                                  personality = mon and mon.personality }
      if mon then
        -- fresh for the trade: full HP, its set's item back
        local copy = P.makeMon(ctx.game.data, fk.temp[i], mon.level, mon.ivs and mon.ivs.attack or 0,
                               mon.personality, otId(ctx.save))
        fk.beaten[i] = copy
      end
    end
  elseif arg == 10 then         -- SetPlayerAndOpponentParties
    if a5 < 2 then P.rebuildParty(ctx) end
  elseif arg == 11 then         -- SetOpponentGfxVar
    setVar(ctx, Fr.VAR_GFX0, Fr.trainerGfx(ctx.game.data, s.opponent, P.FACILITY))
  elseif arg == 12 then P.generateOpponent(ctx)
  elseif arg == 13 then P.generateRentals(ctx)
  elseif arg == 14 then setVar(ctx, 0x800D, P.commonType(ctx))
  elseif arg == 15 then setVar(ctx, 0x800D, P.style(ctx))
  elseif arg == 16 then         -- RestorePlayerPartyHeldItems
    for i, mon in ipairs(ctx.save.party or {}) do
      local rec = fk.rentals[i]
      local row = rec and P.row(ctx.game.data, rec.monId)
      if row then mon.item = row.item end
    end
  end
end

return P
