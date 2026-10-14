-- EMERALD'S BATTLE DOME (pokeemerald battle_dome.c, CallBattleDomeFunction =
-- special 236).
--
-- A sixteen-trainer knockout, four rounds. The player is seeded among fifteen
-- frontier trainers by a ranking score -- the six stats of the three
-- Pokemon summed, plus the number of distinct types times the level over
-- twenty -- and meets the bracket's opponents round by round, choosing two of
-- the three before each battle. Everyone else's matches are decided on paper
-- (DecideRoundWinners): type-effectiveness points for every move against
-- every foe, a tenth of the base stats, a random 0-31 and the seed. Tucker
-- takes a slot in the final's half when he is due (4th and 9th tournament
-- won, then every 5th) and wins every paper match.
--
-- KEPT, ON PURPOSE (the cartridge's bugs, which change what you meet):
--   * CreateDomeOpponentMon reads the IVs with the TOURNAMENT id, so every
--     opponent Pokemon has IVs of 3
--   * CalcDomeMonStats truncates the five non-HP stats to a byte and spreads
--     the EVs with a shifted-out bit mask
--   * DecideRoundWinners never clears its two point totals between matches
--   * a Levitate foe's Ground weakness is scored as neutral by the "good" pick
--   * Wonder Guard is never recognised (its test compares against a
--     multiplier the table does not contain)
--
-- The tourney tree and the opponent card are drawn as one plain screen
-- (src/ui/Gen3DomeScreen.lua).

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")

local D = {}

D.FACILITY = 1
D.TRAINERS = 16
D.ROUNDS = 4
D.PLAYER, D.BRAIN = 1023, 1022     -- TRAINER_PLAYER / TRAINER_FRONTIER_BRAIN
D.ROUND1, D.ROUND2, D.SEMIFINAL, D.FINAL = 0, 1, 2, 3
D.WON, D.LOST, D.RETIRED = 1, 2, 9    -- DOME_PLAYER_WON_MATCH, _LOST_MATCH, _RETIRED
D.GFX_TUCKER = 71
-- sBattlePointAwards' dome column, by tournaments won
D.BP = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15 }
-- sIdToOpponentId / sTourneyTreeTrainerOpponentIds / which seeds sit on the left
D.ID_TO_OPPONENT = {
  [0] = { 8, 0, 4, 8 }, { 9, 12, 8, 0 }, { 10, 8, 12, 0 }, { 11, 4, 0, 8 }, { 12, 0, 4, 8 }, { 13, 12, 8, 0 },
  { 14, 8, 12, 0 }, { 15, 4, 0, 8 }, { 0, 0, 4, 8 }, { 1, 12, 8, 0 }, { 2, 8, 12, 0 }, { 3, 4, 0, 8 },
  { 4, 0, 4, 8 }, { 5, 12, 8, 0 }, { 6, 8, 12, 0 }, { 7, 4, 0, 8 },
}
D.TREE_OPPONENTS = { [0] = 0, 8, 4, 12, 7, 15, 3, 11, 2, 10, 6, 14, 5, 13, 1, 9 }
D.LEFT = { [0] = true, [3] = true, [4] = true, [7] = true, [8] = true, [11] = true, [12] = true, [15] = true }
-- Tucker (sFrontierBrainsMons[FRONTIER_FACILITY_DOME])
D.TUCKER = {
  [0] = {
    { species = "SWAMPERT", item = "FOCUS_BAND", iv = 20, nature = 2, evs = { 152, 152, 106, 0, 100, 0 },
      moves = { "SURF", "EARTHQUAKE", "ICE_BEAM", "COUNTER" } },
    { species = "SALAMENCE", item = "LUM_BERRY", iv = 20, nature = 3, evs = { 152, 152, 106, 100, 0, 0 },
      moves = { "EARTHQUAKE", "BRICK_BREAK", "DRAGON_CLAW", "AERIAL_ACE" } },
    { species = "CHARIZARD", item = "WHITE_HERB", iv = 20, nature = 17, evs = { 100, 152, 106, 152, 0, 0 },
      moves = { "OVERHEAT", "ROCK_SLIDE", "AERIAL_ACE", "EARTHQUAKE" } },
  },
  [1] = {
    { species = "SWAMPERT", item = "LEFTOVERS", iv = 31, nature = 2, evs = { 252, 252, 6, 0, 0, 0 },
      moves = { "SURF", "EARTHQUAKE", "ICE_BEAM", "MIRROR_COAT" } },
    { species = "METAGROSS", item = "QUICK_CLAW", iv = 31, nature = 2, evs = { 252, 252, 6, 0, 0, 0 },
      moves = { "PSYCHIC", "METEOR_MASH", "EARTHQUAKE", "PROTECT" } },
    { species = "LATIAS", item = "CHESTO_BERRY", iv = 31, nature = 15, evs = { 252, 0, 252, 6, 0, 0 },
      moves = { "THUNDERBOLT", "PSYCHIC", "CALM_MIND", "REST" } },
  },
}

local function F() return require("src.script.Gen3BattleFrontier") end
local function G3() return require("src.script.Gen3Commands") end
local function getVar(ctx, id) return math.floor(tonumber(G3().getVar(ctx.save, id)) or 0) end
local function setVar(ctx, id, v) G3().setVar(ctx.save, id, math.floor(tonumber(v) or 0)) end
local function rand16() return love.math.random(0, 65535) end
local function key(mode, lvl) return ("%d:%d"):format(mode, lvl) end

function D.state(save)
  local s = F().state(save)
  s.dome = s.dome or {}
  local d = s.dome
  d.trainers = d.trainers or {}
  d.mons = d.mons or {}
  d.flags = d.flags or {}
  d.championships = d.championships or {}
  d.records = d.records or {}
  return s, d
end
local function lvlOf(s) return math.floor(tonumber(s.data[1]) or 0) end
local function modeOf(ctx) return getVar(ctx, F().VAR_MODE) end
function D.streak(s, mode) return F().streak(s, mode, lvlOf(s), D.FACILITY) end

-- the frontier sets (gFacilityTrainerMons = gBattleFrontierMons), one based
local function row(data, monId) local p = F().parties(data); return p and p.mons[monId] end
local function setOf(data, trainerId)
  local tr = F().trainerRecord(data, trainerId)
  return tr and tr.set or {}
end
-- GetRandomFrontierMonFromSet
local function randomMon(data, trainerId)
  local set = setOf(data, trainerId)
  if #set == 0 then return nil end
  return set[rand16() % #set + 1]
end

-- ------------------------------------------------------------- the numbers --

-- GetDomeTrainerMonIvs (GetFrontierTrainerFixedIvs's twin)
function D.ivs(trainerId)
  if trainerId <= 99 then return 3 elseif trainerId <= 119 then return 6 elseif trainerId <= 139 then return 9
  elseif trainerId <= 159 then return 12 elseif trainerId <= 179 then return 15 elseif trainerId <= 199 then return 18
  elseif trainerId <= 219 then return 21 end
  return 31
end

local STAT_BASE = { "attack", "defense", "speed", "spatk", "spdef" }
local NATURE_UP = { [0] = nil }
-- ModifyStatByNature: +10% / -10% on the stat the nature names (Atk, Def,
-- Spe, SpA, SpD order: natureStatOrder)
local function natureMod(data, nature, statIndex, value)
  local n = tonumber(nature) or 0
  local up, down = math.floor(n / 5), n % 5
  if up == down then return value end
  if statIndex - 1 == up then return math.floor(value * 110 / 100) end
  if statIndex - 1 == down then return math.floor(value * 90 / 100) end
  return value
end
local _ = NATURE_UP

-- CalcDomeMonStats, its bugs and all: { hp, atk, def, spe, spa, spd }
function D.stats(data, species, level, ivs, evBits, nature)
  local def = data.pokemon and data.pokemon[species]
  local base = def and def.baseStats or {}
  local count, bits = 0, evBits % 256
  for _ = 1, 6 do
    if bits % 2 == 1 then count = count + 1 end
    bits = math.floor(bits / 2)
  end
  local each = (count > 0) and math.floor(510 / count) or 0
  local evs = {}
  -- the second loop starts from the shifted-out `bits` and shifts LEFT
  for i = 0, 5 do
    evs[i] = 0
    if (require("bit").band(evBits, bits) ~= 0) then evs[i] = each end
    bits = (bits * 2) % 256
  end
  local out = {}
  if species == "SHEDINJA" then out.hp = 1
  else out.hp = math.floor(((2 * (base.hp or 0) + ivs + math.floor(evs[0] / 4)) * level) / 100) + level + 10 end
  -- CALC_STAT for Atk(1), Def(2), Spe(3), SpA(4), SpD(5), each through a u8
  local order = { { "attack", 1 }, { "defense", 2 }, { "speed", 3 }, { "spatk", 4 }, { "spdef", 5 } }
  for _, o in ipairs(order) do
    local v = math.floor(((2 * (base[o[1]] or 0) + ivs + math.floor(evs[o[2]] / 4)) * level) / 100) + 5
    out[o[1]] = natureMod(data, nature, o[2], v) % 256
  end
  local _2 = STAT_BASE
  return out
end

local function typeBits(data, species, into)
  local def = data.pokemon and data.pokemon[species]
  for _, t in ipairs(def and def.types or {}) do into[t] = true end
end
local function countTypes(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- GetTypeEffectivenessPoints (mode "good", "bad" or "ai")
function D.typePoints(data, move, targetSpecies, mode)
  local md = move and data.moves and data.moves[move]
  if not md or (tonumber(md.power) or 0) == 0 then return 0 end
  local def = data.pokemon and data.pokemon[targetSpecies]
  local types = def and def.types or {}
  local t1, t2 = types[1], types[2] or types[1]
  local ability = def and def.abilities and def.abilities[1]
  local power = 20
  if ability == "LEVITATE" and md.type == "GROUND" then
    if mode == "bad" then power = 8 end
  else
    local TC = require("src.battle.TypeChart")
    TC.load(data)
    -- Wonder Guard is tested against TYPE_x2 (40), which the table never holds
    if ability ~= "WONDER_GUARD" then
      if t1 then power = math.floor(power * TC.effectiveness(md.type, { t1 }) / 10) end
      if t2 and t2 ~= t1 then power = math.floor(power * TC.effectiveness(md.type, { t2 }) / 10) end
    end
  end
  if mode == "good" then
    return ({ [20] = 2, [40] = 4, [80] = 8 })[power] or 0
  elseif mode == "bad" then
    return ({ [0] = 8, [5] = 4, [10] = 2, [40] = -2, [80] = -4 })[power] or 0
  end
  return ({ [0] = -16, [5] = -8, [20] = 4, [40] = 12, [80] = 20 })[power] or 0
end

-- ----------------------------------------------------------- the trainers --

local function trainerMoves(data, d, t, i)
  if d.trainers[t].trainerId == D.BRAIN then
    local m = D.TUCKER[d.brainTeam or 0][i]
    return m and m.moves or {}
  end
  local r = row(data, d.mons[t][i])
  return r and r.moves or {}
end
local function trainerSpecies(data, d, t, i)
  if d.trainers[t].trainerId == D.BRAIN then
    local m = D.TUCKER[d.brainTeam or 0][i]
    return m and m.species
  end
  local r = row(data, d.mons[t][i])
  return r and r.species
end

-- three sets for trainer slot `t` (no set, no species of the last two picked,
-- no item twice -- the species check reads the PREVIOUS trainer's too)
local function pickMons(data, d, t, trainerId, species)
  d.mons[t] = {}
  for j = 1, 3 do
    local monId
    for _ = 1, 2000 do
      monId = randomMon(data, trainerId)
      local r = monId and row(data, monId)
      local ok = r ~= nil
      for k = 1, j - 1 do
        local prev = d.mons[t][k]
        local pr = row(data, prev)
        if prev == monId or species[1] == r.species or species[2] == r.species or (pr and pr.item == r.item) then
          ok = false
        end
      end
      if ok then break end
    end
    d.mons[t][j] = monId
    local r = row(data, monId)
    species[j] = r and r.species or 0
  end
end

local function rankScore(data, d, t, level)
  local sum, types = 0, {}
  local ivs = D.ivs(d.trainers[t].trainerId)
  for j = 1, 3 do
    local r = row(data, d.mons[t][j])
    if r then
      local st = D.stats(data, r.species, level, ivs, tonumber(r.ev) or 0, r.nature or 0)
      sum = sum + st.attack + st.defense + st.spatk + st.spdef + st.speed + st.hp
      typeBits(data, r.species, types)
    end
  end
  return sum + math.floor(countTypes(types) * level / 20)
end

local function swap(d, scores, i, j)
  scores[i], scores[j] = scores[j], scores[i]
  d.trainers[i], d.trainers[j] = d.trainers[j], d.trainers[i]
  d.mons[i], d.mons[j] = d.mons[j], d.mons[i]
end

-- InitDomeTrainers
function D.initTrainers(ctx)
  local data, save = ctx.game.data, ctx.save
  local s, d = D.state(save)
  local mode, lvl = modeOf(ctx), lvlOf(s)
  local streak = D.streak(s, mode)
  d.lvlMode, d.battleMode = lvl + 1, mode + 1
  d.trainers, d.mons, d.winningMoves = {}, {}, {}
  d.trainers[0] = { trainerId = D.PLAYER, eliminated = false, at = 0 }
  local party = save.party or {}
  d.playerMons = {}
  for i = 1, 3 do
    local slot = (s.selectedPartyMons or {})[i]
    d.playerMons[i] = slot and party[slot]
  end
  local species = { 0, 0, 0 }
  for i = 1, D.TRAINERS - 1 do
    local id
    for _ = 1, 1000 do
      id = F().trainerFor((i > 5) and streak or (streak + 1), 0)
      local dup = false
      for j = 1, i - 1 do if d.trainers[j].trainerId == id then dup = true end end
      if not dup then break end
    end
    d.trainers[i] = { trainerId = id, eliminated = false, at = 0 }
    pickMons(data, d, i, id, species)
  end
  local level = F().enemyLevel(save, lvl)
  local scores = {}
  -- the player's: the real stats
  local pTypes, psum = {}, 0
  for _, mon in ipairs(d.playerMons) do
    if mon and mon.stats then
      psum = psum + mon.stats.attack + mon.stats.defense + mon.stats.spatk + mon.stats.spdef + mon.stats.speed + mon.stats.hp
      typeBits(data, mon.species, pTypes)
    end
  end
  scores[0] = (psum + math.floor(countTypes(pTypes) * level / 20)) % 65536
  for i = 1, D.TRAINERS - 1 do scores[i] = rankScore(data, d, i, level) % 65536 end
  for i = 0, D.TRAINERS - 2 do
    for j = i + 1, D.TRAINERS - 1 do
      if scores[i] < scores[j] then swap(d, scores, i, j)
      elseif scores[i] == scores[j] then
        if d.trainers[j].trainerId == D.PLAYER or d.trainers[i].trainerId > d.trainers[j].trainerId then
          swap(d, scores, i, j)
        end
      end
    end
  end
  d.scores = scores
  -- Tucker, when he is due, in the slot across the final from the player
  if F().brainStatus(ctx) ~= 0 then
    local p = D.tournamentId(d, D.PLAYER)
    local j = D.LEFT[p] and 1 or 0
    d.trainers[j] = { trainerId = D.BRAIN, eliminated = false, at = 0 }
    d.mons[j] = {}
    d.brainTeam = F().brainTeam(ctx)
  end
end

function D.tournamentId(d, trainerId)
  for i = 0, D.TRAINERS - 1 do
    if d.trainers[i] and d.trainers[i].trainerId == trainerId then return i end
  end
  return D.TRAINERS
end

-- TournamentIdOfOpponent (0xFF when the bracket has nobody left there)
function D.opponentOf(d, round, trainerId)
  local i = D.tournamentId(d, trainerId)
  if i >= D.TRAINERS then return 0xFF end
  local base = D.ID_TO_OPPONENT[i][round + 1]
  if round ~= D.ROUND1 then
    local max = base + ((round == D.FINAL) and 8 or 4)
    for j = base, max - 1 do
      local t = D.TREE_OPPONENTS[j]
      if t ~= i and not d.trainers[t].eliminated then return t end
    end
    return 0xFF
  end
  if not d.trainers[base].eliminated then return base end
  return 0xFF
end

local function eliminate(d, t, round)
  d.trainers[t].eliminated, d.trainers[t].at = true, round
end

-- DecideRoundWinners (points1 / points2 carried over from match to match)
function D.decideRound(data, d, round)
  local p1, p2 = 0, 0
  local function baseTenth(sp)
    local def = data.pokemon and data.pokemon[sp]
    local b = def and def.baseStats or {}
    return math.floor(((b.hp or 0) + (b.attack or 0) + (b.defense or 0) + (b.speed or 0) + (b.spatk or 0) + (b.spdef or 0)) / 10)
  end
  for i = 0, D.TRAINERS - 1 do
    local tr = d.trainers[i]
    if not tr.eliminated and tr.trainerId ~= D.PLAYER then
      local t1, t2 = i, D.opponentOf(d, round, tr.trainerId)
      if tr.trainerId == D.BRAIN and t2 ~= 0xFF then
        eliminate(d, t2, round)
      elseif t2 ~= 0xFF and d.trainers[t2].trainerId == D.BRAIN then
        eliminate(d, t1, round)
      elseif t2 ~= 0xFF then
        for m1 = 1, 3 do
          for _, mv in ipairs(trainerMoves(data, d, t1, m1)) do
            for m2 = 1, 3 do p1 = p1 + D.typePoints(data, mv, trainerSpecies(data, d, t2, m2), "ai") end
          end
          p1 = p1 + baseTenth(trainerSpecies(data, d, t1, m1))
        end
        p1 = p1 + rand16() % 32 + t1
        for m1 = 1, 3 do
          for _, mv in ipairs(trainerMoves(data, d, t2, m1)) do
            for m2 = 1, 3 do p2 = p2 + D.typePoints(data, mv, trainerSpecies(data, d, t1, m2), "ai") end
          end
          p2 = p2 + baseTenth(trainerSpecies(data, d, t2, m1))
        end
        p2 = p2 + rand16() % 32 + t2
        if p1 > p2 then eliminate(d, t2, round)
        elseif p1 < p2 then eliminate(d, t1, round)
        elseif t1 > t2 then eliminate(d, t2, round)
        else eliminate(d, t1, round) end
      end
    end
  end
end

-- ResolveDomeRoundWinners
function D.resolve(ctx, outcome)
  local data = ctx.game.data
  local s, d = D.state(ctx.save)
  local round = math.floor(tonumber(s.data[2]) or 0)
  if outcome == D.WON then
    local t = D.tournamentId(d, d.opponentId)
    if t < D.TRAINERS then eliminate(d, t, round) end
    if round < D.FINAL then D.decideRound(data, d, round) end
  else
    local p = D.tournamentId(d, D.PLAYER)
    if p < D.TRAINERS then
      eliminate(d, p, round)
      if outcome == D.RETIRED or s.lastOutcome == 6 then d.trainers[p].forfeited = true end
    end
    for r = round, D.ROUNDS - 1 do D.decideRound(data, d, r) end
  end
end

-- ------------------------------------------------- choosing the two they send --

-- SelectOpponentMonsFromParty: the two best by points; a three-way tie is
-- random (or nothing, when not allowed)
local function selectFromPoints(points, allowRandom)
  local pos = { 0, 1, 2 }
  local bits = 0
  if points[1] == points[2] and points[1] == points[3] then
    if allowRandom then
      local n = 0
      while n ~= 2 do
        local r = rand16() % 4                                -- Random() & FRONTIER_PARTY_SIZE (3)
        r = r % 4
        if r ~= 3 and math.floor(bits / 2 ^ r) % 2 == 0 then bits = bits + 2 ^ r; n = n + 1 end
      end
    end
    return bits
  end
  for i = 1, 2 do
    for j = i + 1, 3 do
      if points[i] < points[j] then points[i], points[j] = points[j], points[i]; pos[i], pos[j] = pos[j], pos[i] end
      if points[i] == points[j] and rand16() % 2 == 1 then
        points[i], points[j] = points[j], points[i]; pos[i], pos[j] = pos[j], pos[i]
      end
    end
  end
  return 2 ^ pos[1] + 2 ^ pos[2]
end

local function monPoints(data, d, t, playerMons, mode)
  local pts = { 0, 0, 0 }
  for i = 1, 3 do
    for _, mv in ipairs(trainerMoves(data, d, t, i)) do
      for k = 1, 3 do
        local pm = playerMons[k]
        if pm then pts[i] = pts[i] + D.typePoints(data, mv, pm.species, mode) end
      end
    end
  end
  return pts
end

-- GetDomeTrainerSelectedMons: "good" or "bad" by a coin, the other on a tie
function D.selectedMons(data, d, t, playerMons)
  local bits
  if rand16() % 2 == 1 then
    bits = selectFromPoints(monPoints(data, d, t, playerMons, "good"), false)
    if bits == 0 then bits = selectFromPoints(monPoints(data, d, t, playerMons, "bad"), true) end
  else
    bits = selectFromPoints(monPoints(data, d, t, playerMons, "bad"), false)
    if bits == 0 then bits = selectFromPoints(monPoints(data, d, t, playerMons, "good"), true) end
  end
  return bits
end

-- CreateDomeOpponentMons: the two selected, from the front or the back
function D.opponentParty(ctx)
  local data = ctx.game.data
  local s, d = D.state(ctx.save)
  local t = D.tournamentId(d, d.opponentId)
  if t >= D.TRAINERS then return {} end
  local bits = D.selectedMons(data, d, t, ctx.save.party or {})
  local order = {}
  if rand16() % 10 > 5 then
    for i = 1, 3 do if math.floor(bits / 2 ^ (i - 1)) % 2 == 1 then order[#order + 1] = i end end
  else
    for i = 3, 1, -1 do if math.floor(bits / 2 ^ (i - 1)) % 2 == 1 then order[#order + 1] = i end end
  end
  local level = F().enemyLevel(ctx.save, lvlOf(s))
  local otId = rand16() * 65536 + rand16()
  local party = {}
  for _, i in ipairs(order) do
    local mon
    if d.trainers[t].trainerId == D.BRAIN then
      local b = D.TUCKER[d.brainTeam or 0][i]
      mon = F().makeMon(data, b.species, level, b.nature, b.iv, b.evs, b.item, b.moves, F().BRAIN_OTID)
    else
      local r = row(data, d.mons[t][i])
      -- the IVs read with the tournament id (0-15): always 3
      mon = r and F().makeMon(data, r.species, level, r.nature or 0, D.ivs(t), F().spread(r.ev or 0), r.item, r.moves, otId)
      if mon then
        mon.happiness = 255
        for _, m in ipairs(r.moves or {}) do if m == "FRUSTRATION" then mon.happiness = 0 end end
      end
    end
    if mon then party[#party + 1] = mon end
  end
  return party
end

-- SPECIAL_BATTLE_DOME (239 arm 3): the two they chose against the two you did
function D.battle(ctx)
  local Fr = F()
  local data = ctx.game.data
  local s, d = D.state(ctx.save)
  local party = d.enemyParty or D.opponentParty(ctx)
  d.enemyParty = nil
  local level = Fr.enemyLevel(ctx.save, lvlOf(s))
  local name, pic, class, className
  if d.opponentId == D.BRAIN then
    local a = data.trainers and data.trainers.TUCKER
    name, pic, class, className = "TUCKER", a and a.pic, a and a.class, a and a.className
  else
    local tr = Fr.trainerRecord(data, d.opponentId) or {}
    name, pic, class, className = tr.name, tr.pic, tr.class, tr.className
  end
  if not party[1] then
    Logger.warn("gen3 battle dome: no team for %s -- counted as a loss", tostring(d.opponentId))
    s.lastOutcome = 2
    setVar(ctx, 0x800D, 2)
    return
  end
  local slots = {}
  for i, mon in ipairs(party) do slots[i] = { species = mon.species, level = level, prebuilt = mon } end
  data.trainers[Fr.TRAINER_KEY] = { id = Fr.TRAINER_KEY, name = name or "TRAINER", pic = pic, class = class,
    className = className, party = slots, parties = { slots }, baseMoney = 0 }
  Commands.start_battle(ctx, "trainer", Fr.TRAINER_KEY, 1,
    { frontier = true, double = (modeOf(ctx) == Fr.DOUBLES) or nil, canLose = true, noExp = true, forfeit = true, noItems = true })
  s.lastOutcome = (ctx.lastBattleResult == "win") and 1 or 2
  setVar(ctx, 0x800D, s.lastOutcome)
end

-- InitRandomTourneyTreeResults: a tourney nobody played, for the lobby's
-- "previous results" -- only when the cartridge's own odd test lets it
-- (it returns unless the challenge status is SAVING)
function D.randomResults(ctx)
  local data = ctx.game.data
  local s, d = D.state(ctx.save)
  if (tonumber(s.data[0]) or 0) ~= F().STATUS_SAVING then return end
  d.lvlMode, d.battleMode = 1, 1
  d.trainers, d.mons = {}, {}
  local species = { 0, 0, 0 }
  for i = 0, D.TRAINERS - 1 do
    local id
    for _ = 1, 1000 do
      if i < 5 then id = rand16() % 10 elseif i < 15 then id = rand16() % 20 + 10 else id = rand16() % 10 + 30 end
      local dup = false
      for j = 0, i - 1 do if d.trainers[j].trainerId == id then dup = true end end
      if not dup then break end
    end
    d.trainers[i] = { trainerId = id, eliminated = false, at = 0 }
    pickMons(data, d, i, id, species)
  end
  local scores = {}
  for i = 0, D.TRAINERS - 1 do scores[i] = rankScore(data, d, i, 50) % 65536 end
  for i = 0, D.TRAINERS - 2 do
    for j = i + 1, D.TRAINERS - 1 do
      if scores[i] < scores[j] then swap(d, scores, i, j)
      elseif scores[i] == scores[j] and d.trainers[i].trainerId > d.trainers[j].trainerId then swap(d, scores, i, j) end
    end
  end
  for r = 0, D.ROUNDS - 1 do D.decideRound(data, d, r) end
end

function D.name(ctx, trainerId)
  if trainerId == D.PLAYER then return ctx.save.player and ctx.save.player.name or "PLAYER" end
  if trainerId == D.BRAIN then
    local a = ctx.game.data.trainers and ctx.game.data.trainers.TUCKER
    return a and a.name or "TUCKER"
  end
  local tr = F().trainerRecord(ctx.game.data, trainerId)
  return tr and tr.name or "?"
end

-- ---------------------------------------------- CallBattleDomeFunction (236) --

local ROUND_NAMES = { [0] = "1st round", "2nd round", "semifinal", "final" }   -- gRoundsStringTable

local function screen(ctx, mode)
  local runner = ctx.runner
  local Screen = require("src.ui.Gen3DomeScreen")
  ctx.game.stack:push(Screen.new(ctx.game, { mode = mode, ctx = ctx,
    onDone = function() if runner then runner:resume() end end }))
  if runner then runner:yield() end
end

function D.func(ctx, arg)
  local Fr = F()
  local s, d = D.state(ctx.save)
  local mode, lvl = modeOf(ctx), lvlOf(s)
  local a5, a6 = getVar(ctx, 0x8005), getVar(ctx, 0x8006)
  local act = Fr.actives(s, D.FACILITY)
  local k = key(mode, lvl)
  local flags = d.flags
  local function fl(name) return flags[name .. k] and 1 or 0 end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  if arg == 0 then               -- InitDomeChallenge
    s.data[0], s.data[2], s.data[3], s.data[6] = 0, 0, 0, 0
    if not act[k] then Fr.setStreak(s, mode, lvl, 0, D.FACILITY) end
    local ow = ctx.overworld
    if ow and ow.map and ow.player then s.continueAt = { map = ow.map.id, x = ow.player.cellX, y = ow.player.cellY } end
    s.opponent = nil
  elseif arg == 1 then           -- GetDomeData
    local v = 0
    if a5 == 0 then v = D.streak(s, mode)
    elseif a5 == 1 then v = act[k] and 1 or 0
    elseif a5 == 2 then v = flags["attempted0:0"] and 1 or 0
    elseif a5 == 3 then v = flags["attempted0:1"] and 1 or 0
    elseif a5 == 4 then v = flags["won0:0"] and 1 or 0
    elseif a5 == 5 then v = flags["won0:1"] and 1 or 0
    elseif a5 == 6 then v = fl("attempted")
    elseif a5 == 7 then v = fl("won")
    elseif a5 == 8 then
      ctx.save.gen3SelectedOrder = {}
      for i, x in ipairs(d.battleOrder or {}) do ctx.save.gen3SelectedOrder[i] = x end
    elseif a5 == 9 then v = ((d.lvlMode or 0) * 2) - 3 + (d.battleMode or 0) end
    setVar(ctx, 0x800D, v)
  elseif arg == 2 then           -- SetDomeData
    if a5 == 0 then Fr.setStreak(s, mode, lvl, a6, D.FACILITY)
    elseif a5 == 1 then act[k] = (a6 ~= 0) or nil
    elseif a5 == 2 then flags["attempted0:0"] = (a6 ~= 0) or nil
    elseif a5 == 3 then flags["attempted0:1"] = (a6 ~= 0) or nil
    elseif a5 == 4 then flags["won0:0"] = (a6 ~= 0) or nil
    elseif a5 == 5 then flags["won0:1"] = (a6 ~= 0) or nil
    elseif a5 == 6 then flags["attempted" .. k] = (a6 ~= 0) or nil
    elseif a5 == 7 then flags["won" .. k] = (a6 ~= 0) or nil
    elseif a5 == 8 then
      d.battleOrder = {}
      for i, x in ipairs(ctx.save.gen3SelectedOrder or {}) do d.battleOrder[i] = x end
    end
  elseif arg == 3 then           -- BufferDomeRoundText
    ctx.game.stringBuffers[1] = ROUND_NAMES[math.floor(tonumber(s.data[2]) or 0)] or ""
  elseif arg == 4 then           -- BufferDomeOpponentName
    ctx.game.stringBuffers[1] = ROUND_NAMES[math.floor(tonumber(s.data[2]) or 0)] or ""
    ctx.game.stringBuffers[2] = D.name(ctx, d.opponentId)
  elseif arg == 5 then           -- InitDomeOpponentParty
    d.enemyParty = D.opponentParty(ctx)
  elseif arg == 6 then screen(ctx, "opponent")
  elseif arg == 7 or arg == 8 or arg == 11 then screen(ctx, "tree")
  elseif arg == 9 then           -- SetDomeOpponentId
    local t = D.opponentOf(d, math.floor(tonumber(s.data[2]) or 0), D.PLAYER)
    d.opponentId = (t ~= 0xFF) and d.trainers[t].trainerId or nil
    if t == 0xFF then
      local dump = {}
      for i = 0, D.TRAINERS - 1 do
        local tr = d.trainers[i]
        dump[#dump + 1] = ("%d:%s%s"):format(i, tostring(tr and tr.trainerId), tr and tr.eliminated and ("x" .. tr.at) or "")
      end
      Logger.warn("gen3 battle dome: no opponent in round %s for the player -- %s", tostring(s.data[2]), table.concat(dump, " "))
    end
    s.opponent = (d.opponentId == D.BRAIN) and Fr.BRAIN or d.opponentId
  elseif arg == 10 then          -- SetDomeOpponentGraphicsId
    setVar(ctx, Fr.VAR_GFX0, (d.opponentId == D.BRAIN) and D.GFX_TUCKER
                               or Fr.trainerGfx(ctx.game.data, d.opponentId or 0, D.FACILITY))
  elseif arg == 12 then D.resolve(ctx, a5)
  elseif arg == 13 then          -- SaveDomeChallenge
    s.data[0] = a5
    setVar(ctx, Fr.VAR_STATUS, 0)
    s.data[3] = 1
    Fr.saveFrontier(ctx)
  elseif arg == 14 then          -- IncrementDomeStreaks
    if D.streak(s, mode) < 999 then Fr.setStreak(s, mode, lvl, D.streak(s, mode) + 1, D.FACILITY) end
    d.championships[k] = math.min(999, (d.championships[k] or 0) + 1)
    d.records[k] = math.max(d.records[k] or 0, D.streak(s, mode))
  elseif arg == 15 or arg == 16 then
    -- the frontier sets are this module's already; nothing was Sketched
  elseif arg == 17 then Fr.restoreHeldItems(ctx.save)
  elseif arg == 18 then G3().reduceToChosen(ctx, true)
  elseif arg == 19 then          -- GetPlayerSeededBeforeOpponent
    setVar(ctx, 0x800D, (D.tournamentId(d, d.opponentId) > D.tournamentId(d, D.PLAYER)) and 1 or 2)
  elseif arg == 20 then          -- BufferLastDomeWinnerName
    for i = 0, D.TRAINERS - 1 do
      if d.trainers[i] and not d.trainers[i].eliminated then
        ctx.game.stringBuffers[1] = D.name(ctx, d.trainers[i].trainerId)
        break
      end
    end
  elseif arg == 21 then D.randomResults(ctx)
  elseif arg == 22 then D.initTrainers(ctx)
  end
end

function D.install()
  local S = G3().SPECIALS
  local fallback = S[236]
  S[236] = function(ctx)
    if getVar(ctx, F().VAR_FACILITY) == D.FACILITY then
      D.func(ctx, getVar(ctx, 0x8004))
      return
    end
    return fallback and fallback(ctx)
  end
  -- DoDomeConfetti: the confetti over the winner, not drawn here
  S[490] = S[490] or function() end
  F().BRAIN_TEAMS[D.FACILITY] = D.TUCKER
end

return D
