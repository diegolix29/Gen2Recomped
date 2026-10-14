-- EMERALD'S BATTLE PIKE (pokeemerald battle_pike.c, CallBattlePikeFunction =
-- special 242, and its wild-room half in wild_encounter.c).
--
-- Fourteen rooms, three doors at a time. Behind each door is one of nine
-- things: a trainer, a tougher trainer and a heal, two trainers at once, a
-- full heal, a partial heal, a talker, a Kirlia or Dusclops that inflicts a
-- status on part of the team, a grass room of wild Pokemon, or -- on the
-- 28th room and every so often after -- Lucy, the Pike Queen. A woman in the
-- three-door room will hint at what one of the doors hides, and that door's
-- hint group (people, whispering, nostalgia, Pokemon) is kept off the other
-- two. Nothing heals between rooms unless a room does it; the team that
-- enters room one is the team, damage and all, that reaches the last.
--
-- The maps' own scripts run the whole challenge; this file answers the 29
-- functions they call, prepares the trainers and runs the battles
-- (DoSpecialTrainerBattle arms 7 and 9), and builds the wild room's
-- encounters (TryGenerateBattlePikeWildMon).

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")

local P = {}

P.FACILITY = 5
P.ROOMS = 14
P.SINGLE, P.HEAL_FULL, P.NPC, P.STATUS, P.HEAL_PART, P.WILD, P.HARD, P.DOUBLE, P.BRAIN = 0, 1, 2, 3, 4, 5, 6, 7, 8
P.ROOM_TYPES = 9
P.HINT_NOSTALGIA, P.HINT_WHISPERING, P.HINT_POKEMON, P.HINT_PEOPLE, P.HINT_BRAIN = 0, 1, 2, 3, 4
P.STATUSMON_KIRLIA, P.STATUSMON_DUSCLOPS = 0, 1
P.ST_FREEZE, P.ST_BURN, P.ST_TOXIC, P.ST_PARALYSIS, P.ST_SLEEP = 0, 1, 2, 3, 4
P.MAPS = { MAP_G26_N36 = true, MAP_G26_N37 = true, MAP_G26_N39 = true }   -- InBattlePike's layouts
P.WILD_ROOM = "MAP_G26_N39"
P.VAR_GFX0, P.VAR_GFX1, P.VAR_ROOM = 0x4010, 0x4011, 0x8007
P.GFX = { RECEPTIONIST = 28, DUSCLOPS = 226, KIRLIA = 225, GENTLEMAN = 48 }

-- sRoomTypeHints
P.HINTS = { [0] = P.HINT_PEOPLE, P.HINT_PEOPLE, P.HINT_WHISPERING, P.HINT_NOSTALGIA, P.HINT_NOSTALGIA,
            P.HINT_POKEMON, P.HINT_POKEMON, P.HINT_WHISPERING, P.HINT_BRAIN }
-- sNumMonsToHealBeforePikeQueen[hintedRoomIndex][room chosen]
P.QUEEN_HEALS = { [0] = { [0] = 2, 1, 0 }, { [0] = 2, 0, 1 }, { [0] = 1, 2, 0 }, { [0] = 1, 0, 2 },
                  { [0] = 0, 2, 1 }, { [0] = 0, 1, 2 } }
-- sNPCTable: { graphicsId, speech for rooms 1-4, 5-10, 11+ }
P.NPCS = {
  { 18, 3, 5, 6 }, { 5, 13, 32, 37 }, { 17, 8, 11, 12 }, { 36, 34, 30, 33 }, { 21, 0, 0, 0 },
  { 30, 1, 1, 1 }, { 44, 22, 23, 27 }, { 55, 8, 22, 31 }, { 14, 13, 39, 21 }, { 20, 2, 4, 17 },
  { 56, 30, 20, 36 }, { 66, 28, 34, 25 }, { 38, 23, 38, 26 }, { 50, 23, 30, 11 }, { 47, 15, 19, 14 },
  { 39, 2, 29, 26 }, { 51, 37, 12, 32 }, { 33, 24, 23, 38 }, { 24, 5, 22, 4 }, { 11, 41, 37, 35 },
  { 53, 39, 14, 13 }, { 48, 10, 7, 9 }, { 12, 40, 20, 16 }, { 52, 18, 13, 21 }, { 19, 22, 31, 27 },
}
-- sBattlePointAwards' pike column
P.BP = { 1, 1, 2, 2, 2, 4, 4, 4, 8, 8, 8, 8, 10, 10, 10, 10, 12, 12, 12, 12, 12, 14, 14, 14, 14,
         15, 15, 15, 15, 15 }

-- the wild room: gBattlePikeWildMonHeaders (four tiers by streak; Seviper and
-- Milotic in slots 1, 2, 7, 8, 11, 12 and the tier's third everywhere else)
-- and sWildMons (the level below the cap, and the moves, per level mode)
P.WILD_THIRD = { "DUSCLOPS", "ELECTRODE", "BRELOOM", "WOBBUFFET" }
P.WILD_SETS = {
  [0] = {   -- level 50
    SEVIPER = { 4, { "TOXIC", "GLARE", "BODY_SLAM", "SLUDGE_BOMB" } },
    MILOTIC = { 4, { "TOXIC", "HYPNOSIS", "BODY_SLAM", "SURF" } },
    DUSCLOPS = { 5, { "WILL_O_WISP", "MEAN_LOOK", "TOXIC", "SHADOW_PUNCH" } },
    ELECTRODE = { 5, { "EXPLOSION", "SELF_DESTRUCT", "THUNDER", "TOXIC" } },
    BRELOOM = { 5, { "SPORE", "STUN_SPORE", "POISON_POWDER", "HIDDEN_POWER" } },
    WOBBUFFET = { 5, { "COUNTER", "MIRROR_COAT", "SAFEGUARD", "DESTINY_BOND" } },
  },
  [1] = {   -- open level
    SEVIPER = { 4, { "TOXIC", "GLARE", "POISON_FANG", "SLUDGE_BOMB" } },
    MILOTIC = { 4, { "TOXIC", "HYPNOSIS", "BODY_SLAM", "ICE_BEAM" } },
    DUSCLOPS = { 5, { "WILL_O_WISP", "MEAN_LOOK", "TOXIC", "ICE_BEAM" } },
    ELECTRODE = { 5, { "EXPLOSION", "SELF_DESTRUCT", "THUNDER", "TOXIC" } },
    BRELOOM = { 5, { "SPORE", "STUN_SPORE", "POISON_POWDER", "HIDDEN_POWER" } },
    WOBBUFFET = { 5, { "COUNTER", "MIRROR_COAT", "SAFEGUARD", "ENCORE" } },
  },
}

local function F() return require("src.script.Gen3BattleFrontier") end
local function G3() return require("src.script.Gen3Commands") end
local function getVar(ctx, id) return math.floor(tonumber(G3().getVar(ctx.save, id)) or 0) end
local function setVar(ctx, id, v) G3().setVar(ctx.save, id, math.floor(tonumber(v) or 0)) end
local function result(ctx, v) setVar(ctx, 0x800D, v) end
local function rand(n) return love.math.random(0, n - 1) end
local function key(lvl) return ("0:%d"):format(lvl) end

function P.state(save)
  local s = F().state(save)
  s.pike = s.pike or { trainers = {}, record = {}, total = {} }
  return s, s.pike
end
local function lvlOf(s) return math.floor(tonumber(s.data[1]) or 0) end
local function roomNum(s) return math.floor(tonumber(s.data[2]) or 0) end
function P.streak(s) return F().streak(s, 0, lvlOf(s), P.FACILITY) end
function P.setStreak(s, n) F().setStreak(s, 0, lvlOf(s), math.min(F().MAX_STREAK, n), P.FACILITY) end

-- the three the challenge carries (gPlayerParty after the party order is set)
local function team(save)
  local out = {}
  for i = 1, 3 do if save.party and save.party[i] then out[#out + 1] = save.party[i] end end
  return out
end
local function ailing(mon) return mon.status ~= nil and mon.status ~= "" and mon.status ~= 0 end
local function moveMaxPP(data, mon, slot)
  local m = mon.moves and mon.moves[slot]
  local def = m and data and data.moves and data.moves[m.id]
  local base = def and def.pp or (m and m.maxPP) or 0
  local ups = (m and (m.ppUps or m.ppUp)) or 0
  return base + math.floor(base * ups / 5)
end

-- HealMon: HP, PP and status
function P.healMon(data, mon)
  mon.hp = mon.stats and mon.stats.hp or mon.hp
  mon.status = nil
  mon.badlyPoisoned = nil
  mon.sleepTurns = nil
  for i, m in ipairs(mon.moves or {}) do m.pp = moveMaxPP(data, mon, i) end
end
local function needsHeal(data, mon)
  if (mon.hp or 0) < (mon.stats and mon.stats.hp or 0) then return true end
  if ailing(mon) then return true end
  for i, m in ipairs(mon.moves or {}) do
    if (m.pp or 0) < moveMaxPP(data, mon, i) then return true end
  end
  return false
end

-- the order the cartridge walks the team in: ten random swaps
local function shuffled()
  local idx = { 1, 2, 3 }
  for _ = 1, 10 do
    local a, b = rand(3) + 1, rand(3) + 1
    idx[a], idx[b] = idx[b], idx[a]
  end
  return idx
end

-- TryHealMons: up to n, in that shuffled order, of those that need it
function P.tryHeal(ctx, n)
  if n <= 0 then return end
  local t = team(ctx.save)
  for _, i in ipairs(shuffled()) do
    local mon = t[i]
    if mon and needsHeal(ctx.game.data, mon) then
      P.healMon(ctx.game.data, mon)
      n = n - 1
      if n == 0 then return end
    end
  end
end

local function aliveCount(save)
  local dead = 0
  for _, mon in ipairs(team(save)) do if (mon.hp or 0) == 0 then dead = dead + 1 end end
  return dead < 2
end
-- AtLeastOneHealthyMon: among the first `count` checked (1 by room 4, 2 by
-- room 9, 3 after) is one with no status and some HP
local function statusCount(s) local r = roomNum(s) return r <= 4 and 1 or r <= 9 and 2 or 3 end
local function oneHealthy(save, s)
  local count, n = statusCount(s), 0
  for _, mon in ipairs(team(save)) do
    if not ailing(mon) and (mon.hp or 0) > 0 then n = n + 1 end
    if n == count then break end
  end
  return n > 0
end

-- -------------------------------------------------- the status rooms --

-- the port's status codes (src/battle/Status.lua). STATUS1_TOXIC_POISON is
-- carried as PSN: a party Pokemon's bad poison restarts its count on entry
-- either way, and this engine keeps that count on the battler
P.STATUS_OF = { [P.ST_TOXIC] = "PSN", [P.ST_FREEZE] = "FRZ", [P.ST_PARALYSIS] = "PAR",
                [P.ST_SLEEP] = "SLP", [P.ST_BURN] = "BRN" }
local function typesOf(data, mon)
  local def = data and data.pokemon and data.pokemon[mon.species]
  return def and def.types or {}
end
local function hasType(data, mon, list)
  for _, t in ipairs(typesOf(data, mon)) do for _, w in ipairs(list) do if t == w then return true end end end
  return false
end
-- DoesTypePreventStatus
function P.typeBlocks(data, mon, st)
  if st == P.ST_TOXIC then return hasType(data, mon, { "STEEL", "POISON" }) end
  if st == P.ST_FREEZE then return hasType(data, mon, { "ICE" }) end
  if st == P.ST_PARALYSIS then return hasType(data, mon, { "GROUND", "ELECTRIC" }) end
  if st == P.ST_BURN then return hasType(data, mon, { "FIRE" }) end
  return false
end
-- DoesAbilityPreventStatus
P.ABILITY_BLOCKS = { [P.ST_FREEZE] = { MAGMA_ARMOR = true }, [P.ST_BURN] = { WATER_VEIL = true },
  [P.ST_PARALYSIS] = { LIMBER = true }, [P.ST_SLEEP] = { INSOMNIA = true, VITAL_SPIRIT = true },
  [P.ST_TOXIC] = { IMMUNITY = true } }
local function abilityOf(data, mon)
  local ok, a = pcall(function() return require("src.battle.Abilities").ofMon(data, mon) end)
  if ok and a then return a end
  local def = data and data.pokemon and data.pokemon[mon.species]
  local list = def and def.abilities
  return list and (list[(mon.abilitySlot or 1)] or list[1])
end

-- TryInflictRandomStatus
function P.inflictStatus(ctx, pk)
  local data, save, s = ctx.game.data, ctx.save, P.state(ctx.save)
  local t, order, count = team(save), shuffled(), statusCount(s)
  local chosen, last
  repeat
    local r = rand(100)
    local st = (r < 35 and P.ST_TOXIC) or (r < 60 and P.ST_FREEZE) or (r < 80 and P.ST_PARALYSIS)
      or (r < 90 and P.ST_SLEEP) or P.ST_BURN
    pk.statusFlag = st
    if st ~= last then
      last = st
      local j = 0
      for _, i in ipairs(order) do
        local mon = t[i]
        if mon and not ailing(mon) and (mon.hp or 0) > 0 then
          j = j + 1
          if not P.typeBlocks(data, mon, st) then chosen = true break end
        end
        if j == count then break end
      end
      if j == 0 then return false end
    end
  until chosen
  local st = pk.statusFlag
  pk.statusMon = (st == P.ST_FREEZE or (st == P.ST_BURN and rand(2) ~= 0)) and P.STATUSMON_DUSCLOPS
                 or P.STATUSMON_KIRLIA
  local j = 0
  for _, i in ipairs(order) do
    local mon = t[i]
    if mon and not ailing(mon) and (mon.hp or 0) > 0 then
      j = j + 1
      local blocks = P.ABILITY_BLOCKS[st] or {}
      if not blocks[abilityOf(data, mon) or ""] and not P.typeBlocks(data, mon, st) then
        mon.status = P.STATUS_OF[st]
        -- STATUS1_SLEEP is the whole three-bit counter: seven turns
        if st == P.ST_SLEEP then mon.sleepTurns = 7 end
        if st == P.ST_TOXIC then mon.badlyPoisoned = true end
      end
    end
    if j == count then break end
  end
  return true
end

-- ---------------------------------------------------- which room is next --

-- GetNextRoomType: the hinted door is the hinted room; the others are drawn
-- from every type outside the hint's group, less those that would do
-- nothing (doubles with fewer than two standing, a status room with nobody
-- to hit) and the heals while healing is switched off
function P.nextRoom(ctx)
  local s, pk = P.state(ctx.save)
  if pk.hintType == P.BRAIN then return P.BRAIN end
  if getVar(ctx, P.VAR_ROOM) == pk.hintIndex then
    if pk.hintType == P.STATUS then P.inflictStatus(ctx, pk) end
    return pk.hintType or P.NPC
  end
  local off = {}
  local hint = P.HINTS[pk.hintType or P.NPC]
  for i = 0, P.ROOM_TYPES - 2 do if P.HINTS[i] == hint then off[i] = true end end
  if not aliveCount(ctx.save) then off[P.DOUBLE] = true end
  if not oneHealthy(ctx.save, s) then off[P.STATUS] = true end
  if pk.healDisabled then off[P.HEAL_FULL], off[P.HEAL_PART] = true, true end
  local list = {}
  for i = 0, P.ROOM_TYPES - 2 do if not off[i] then list[#list + 1] = i end end
  local room = list[rand(#list) + 1] or P.NPC
  if room == P.STATUS then P.inflictStatus(ctx, pk) end
  return room
end

-- GetPikeQueenFightType (FRONTIER_BRAIN_* 0..4)
function P.queenFight(ctx, nextRoom)
  local s = P.state(ctx.save)
  local at = F().BRAIN_AT_BY[P.FACILITY]
  local win = P.streak(s) + nextRoom
  local sym = F().symbols(ctx, P.FACILITY)
  if sym < 2 then
    return (win == at[sym + 1] - at[4]) and (sym + 1) or 0
  end
  if win == at[1] - at[4] then return 3 end
  if win == at[2] - at[4] or (win > at[2] and (win - at[2] + at[4]) % at[3] == 0) then return 4 end
  return 0
end

-- SetHintedRoom
function P.setHint(ctx)
  local s, pk = P.state(ctx.save)
  if P.queenFight(ctx, 1) ~= 0 then
    pk.hintIndex, pk.hintType = rand(6), P.BRAIN
    return 1
  end
  pk.hintIndex = rand(3)
  local list = {}
  for i = 0, P.ROOM_TYPES - 2 do
    if not (pk.healDisabled and (i == P.HEAL_FULL or i == P.HEAL_PART)) then list[#list + 1] = i end
  end
  pk.hintType = list[rand(#list) + 1]
  if pk.hintType == P.STATUS and not oneHealthy(ctx.save, s) then pk.hintType = P.NPC end
  if pk.hintType == P.DOUBLE and not aliveCount(ctx.save) then pk.hintType = P.NPC end
  return 0
end

-- PrepareOneTrainer / PrepareTwoTrainers: from the scaled ranges (the
-- seventh battle's for the hard room), none met before this challenge
local function drawTrainer(s, pk, battleNum, upto)
  local challenge = math.floor(P.streak(s) / P.ROOMS)
  local id
  repeat
    id = F().trainerFor(challenge, battleNum)
    local seen = false
    for i = 1, upto do if pk.trainers[i] == id then seen = true end end
  until not seen
  return id
end
function P.prepareTrainers(ctx, room)
  local s, pk = P.state(ctx.save)
  local r = roomNum(s)
  local data = ctx.game.data
  if room == P.DOUBLE then
    s.opponent = drawTrainer(s, pk, 1, r - 1)
    if r <= P.ROOMS then pk.trainers[r] = s.opponent end
    s.opponentB = drawTrainer(s, pk, 1, r)
    if r < P.ROOMS and r >= 2 then pk.trainers[r - 1] = s.opponentB end
    setVar(ctx, P.VAR_GFX0, F().trainerGfx(data, s.opponent, P.FACILITY))
    setVar(ctx, P.VAR_GFX1, F().trainerGfx(data, s.opponentB, P.FACILITY))
  else
    s.opponent = drawTrainer(s, pk, room == P.HARD and 6 or 1, r - 1)
    s.opponentB = nil
    if r < P.ROOMS then pk.trainers[r] = s.opponent end
    setVar(ctx, P.VAR_GFX0, F().trainerGfx(data, s.opponent, P.FACILITY))
  end
end

-- SetupRoomObjectEvents
function P.setupRoom(ctx)
  local s, pk = P.state(ctx.save)
  local room = pk.room
  setVar(ctx, P.VAR_GFX0, P.GFX.RECEPTIONIST)
  setVar(ctx, P.VAR_GFX1, P.GFX.DUSCLOPS)
  if room == P.SINGLE then P.prepareTrainers(ctx, P.SINGLE)
  elseif room == P.HEAL_FULL then setVar(ctx, P.VAR_GFX0, P.GFX.RECEPTIONIST)
  elseif room == P.NPC then
    pk.npc = rand(#P.NPCS)
    setVar(ctx, P.VAR_GFX0, P.NPCS[pk.npc + 1][1])
  elseif room == P.STATUS then
    setVar(ctx, P.VAR_GFX0, P.GFX.GENTLEMAN)
    setVar(ctx, P.VAR_GFX1, pk.statusMon == P.STATUSMON_DUSCLOPS and P.GFX.DUSCLOPS or P.GFX.KIRLIA)
  elseif room == P.HEAL_PART then setVar(ctx, P.VAR_GFX0, P.GFX.GENTLEMAN)
  elseif room == P.HARD then
    P.prepareTrainers(ctx, P.HARD)
    setVar(ctx, P.VAR_GFX1, P.GFX.RECEPTIONIST)
  elseif room == P.DOUBLE then P.prepareTrainers(ctx, P.DOUBLE)
  elseif room == P.BRAIN then
    s.opponent = F().BRAIN
    setVar(ctx, P.VAR_GFX0, F().BRAIN_GFX[P.FACILITY])
    setVar(ctx, P.VAR_GFX1, P.GFX.RECEPTIONIST)
  end
end

-- ------------------------------------------------- CallBattlePikeFunction --

function P.func(ctx, arg)
  local save = ctx.save
  local s, pk = P.state(save)
  local lvl = lvlOf(s)
  local a5, a6 = getVar(ctx, 0x8005), getVar(ctx, 0x8006)
  local act = F().actives(s, P.FACILITY)
  if arg == 0 then pk.room = P.nextRoom(ctx)
  elseif arg == 1 then
    local v = 0
    if a5 == 0 then v = pk.prize or 0
    elseif a5 == 1 then v = P.streak(s)
    elseif a5 == 2 then v = pk.record[lvl] or 0
    elseif a5 == 3 then v = pk.total[lvl] or 0
    elseif a5 == 4 then v = act[key(lvl)] and 1 or 0 end
    result(ctx, v)
  elseif arg == 2 then
    if a5 == 0 then pk.prize = a6
    elseif a5 == 1 then if a6 <= F().MAX_STREAK then P.setStreak(s, a6) end
    elseif a5 == 2 then if a6 <= F().MAX_STREAK and (pk.record[lvl] or 0) < a6 then pk.record[lvl] = a6 end
    elseif a5 == 3 then if a6 <= F().MAX_STREAK then pk.total[lvl] = a6 end
    elseif a5 == 4 then act[key(lvl)] = (a6 ~= 0) or nil end
  elseif arg == 3 then result(ctx, roomNum(s) > P.ROOMS and 1 or 0)
  elseif arg == 4 then P.setupRoom(ctx)
  elseif arg == 5 then result(ctx, pk.room or 0)
  elseif arg == 6 then pk.inWild = true
  elseif arg == 7 then pk.inWild = nil
  elseif arg == 8 then          -- SavePikeChallenge
    s.data[0] = a5
    setVar(ctx, F().VAR_STATUS, 0)
    s.data[3] = 1
    F().saveFrontier(ctx)
  elseif arg == 9 or arg == 10 then -- dummies
  elseif arg == 11 then result(ctx, pk.statusFlag or 0)
  elseif arg == 12 then result(ctx, pk.statusMon or 0)
  elseif arg == 13 then
    local n = rand(2) + 1
    P.tryHeal(ctx, n)
    result(ctx, n)
  elseif arg == 14 then P.bufferNpc(ctx, pk, s)
  elseif arg == 15 then         -- the status flash: a beat, nothing drawn
  elseif arg == 16 then
    local ow = ctx.overworld
    result(ctx, (ow and ow.map and P.MAPS[ow.map.id]) and 1 or 0)
  elseif arg == 17 then result(ctx, P.setHint(ctx))
  elseif arg == 18 then result(ctx, pk.hintIndex or 0)
  elseif arg == 19 then result(ctx, P.HINTS[pk.hintType or P.NPC])
  elseif arg == 20 then pk.trainers = {}
  elseif arg == 21 then
    local id = (a5 == 1) and s.opponentB or s.opponent
    F().bufferSpeech(ctx, id, "before")
  elseif arg == 22 then result(ctx, P.queenFight(ctx, 0))
  elseif arg == 23 then
    local row = P.QUEEN_HEALS[pk.hintIndex or 0] or P.QUEEN_HEALS[0]
    local n = row[getVar(ctx, P.VAR_ROOM)] or 0
    P.tryHeal(ctx, n)
    result(ctx, n)
  elseif arg == 24 then pk.healDisabled = (a5 ~= 0) or nil
  elseif arg == 25 then
    local full = true
    for _, mon in ipairs(team(save)) do if needsHeal(ctx.game.data, mon) then full = false end end
    result(ctx, full and 1 or 0)
  elseif arg == 26 then
    pk.items = {}
    for i, mon in ipairs(team(save)) do pk.items[i] = mon.item or false end
  elseif arg == 27 then
    for i, mon in ipairs(team(save)) do
      if pk.items and pk.items[i] ~= nil then mon.item = pk.items[i] or nil end
    end
  elseif arg == 28 then         -- InitPikeChallenge
    s.data[0], s.data[2], s.data[3] = 0, 0, 0
    if not act[key(lvl)] then P.setStreak(s, 0) end
    s.opponent, s.opponentB = nil, nil
    local ow = ctx.overworld
    if ow and ow.map and ow.player then
      s.continueAt = { map = ow.map.id, x = ow.player.cellX, y = ow.player.cellY }
    end
  else
    Logger.debug("gen3 battle pike: function %d is not ported", arg)
  end
end

-- BufferNPCMessage: the talker's line for this stretch of the challenge
function P.bufferNpc(ctx, pk, s)
  local row = P.NPCS[(pk.npc or 0) + 1] or P.NPCS[1]
  local r = roomNum(s)
  local id = (r <= 4 and row[2]) or (r <= 10 and row[3]) or row[4]
  local speech = ctx.game.data.gen3_frontier_speech
  local words = speech and speech.pikeNpc and speech.pikeNpc[id]
  local line = ""
  if words then
    local ok, text = pcall(require("src.script.EasyChat").phrase, ctx.game.data, words, 3)
    if ok and type(text) == "string" then line = text end
  end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[4] = line
end

-- ---------------------------------------------------------- the battles --

-- SPECIAL_BATTLE_PIKE_DOUBLE: two trainers, one Pokemon each
function P.doubleBattle(ctx)
  local Fr = F()
  local data = ctx.game.data
  local s = P.state(ctx.save)
  local level = Fr.enemyLevel(ctx.save, lvlOf(s))
  local keys = {}
  for i, id in ipairs({ s.opponent, s.opponentB }) do
    local party = Fr.trainerParty(data, id, 1, level)
    local tr = Fr.trainerRecord(data, id) or {}
    local slots = {}
    for k, mon in ipairs(party) do slots[k] = { species = mon.species, level = level, prebuilt = mon } end
    local key = Fr.TRAINER_KEY .. (i == 1 and "" or "_B")
    data.trainers[key] = { id = key, name = tr.name or "TRAINER", pic = tr.pic, class = tr.class,
      className = tr.className, party = slots, parties = { slots }, baseMoney = 0 }
    keys[i] = key
  end
  Commands.start_battle(ctx, "trainer", keys[1], 1,
    { frontier = true, double = true, trainerBKey = keys[2], canLose = true, noExp = true, forfeit = true, noItems = true })
  s.lastOutcome = (ctx.lastBattleResult == "win") and 1 or 2
  setVar(ctx, 0x800D, s.lastOutcome)
end

-- ------------------------------------------------------- the wild room --

function P.inWildRoom(mapId) return mapId == P.WILD_ROOM end

-- GetBattlePikeWildMonHeaderId: the tier, by the streak
function P.wildTier(s)
  local w = P.streak(s)
  if w <= 20 * P.ROOMS then return 1 elseif w <= 40 * P.ROOMS then return 2
  elseif w <= 60 * P.ROOMS then return 3 end
  return 4
end

-- the room's table, in the shape Encounter.roll reads
function P.wildTable(save)
  local s = P.state(save)
  local third = P.WILD_THIRD[P.wildTier(s)]
  local names = { "SEVIPER", "MILOTIC", third, third, third, third, "SEVIPER", "MILOTIC", third, third,
                  "SEVIPER", "MILOTIC" }
  local slots = {}
  for i, sp in ipairs(names) do slots[i] = { species = sp, min = 5, max = 5 } end
  return { grass = { bucketSpan = 100, buckets = { 20, 40, 50, 60, 70, 80, 85, 90, 94, 98, 99, 100 },
                     rate = 10, rateMax = 180, slots = slots } }
end

-- TryGenerateBattlePikeWildMon: the level below the cap (or the party's
-- best, open level), the moves, and Keen Eye / Intimidate on the lead.
-- nil when the lead turned it away.
function P.wildFor(data, save, enc)
  local s = P.state(save)
  local lvlMode = lvlOf(s)
  local sets = P.WILD_SETS[lvlMode == 1 and 1 or 0]
  local set = sets[enc.species] or sets.SEVIPER
  local level
  if lvlMode == 1 then
    local top = 0
    for _, mon in ipairs(save.party or {}) do top = math.max(top, tonumber(mon.level) or 0) end
    level = (top < 60) and 60 or math.max(60, top - set[1])
  else
    level = 50 - set[1]
  end
  local lead = save.party and save.party[1]
  if lead then
    local a = abilityOf(data, lead)
    local ll = tonumber(lead.level) or 0
    if (a == "KEEN_EYE" or a == "INTIMIDATE") and ll > 5 and level <= ll - 5 and rand(2) == 0 then
      return nil
    end
  end
  return { species = enc.species, level = level, pikeMoves = set[2] }
end

-- after newWild: the set's moves, no held item, either ability, and the
-- Frontier's rules (no experience, no items, a loss is not a whiteout)
function P.prepareWild(battle, enc)
  local mon = battle.enemy and battle.enemy.mon
  if not mon then return end
  local data = battle.data or (battle.game and battle.game.data)
  mon.item = nil
  mon.moves = {}
  for _, id in ipairs(enc.pikeMoves or {}) do
    local def = data and data.moves and data.moves[id]
    mon.moves[#mon.moves + 1] = { id = id, pp = def and def.pp or 5 }
  end
  local def = data and data.pokemon and data.pokemon[mon.species]
  mon.abilitySlot = (def and def.abilities and def.abilities[2]) and (rand(2) + 1) or 1
  if battle.enemy.refreshFromMon then battle.enemy:refreshFromMon() end
  battle.enemy.curMoves = mon.moves
  battle.noExp, battle.noItems, battle.canLose, battle.pikeWild = true, true, true, true
end

-- after the wild battle: the outcome the room's ON_RESUME reads
-- (B_OUTCOME_WON 1, LOST 2, DREW 3, RAN 4)
function P.afterWild(save, res)
  local s = P.state(save)
  s.lastOutcome = (res == "win" and 1) or (res == "run" and 4) or (res == "lose" and 2) or 1
end

function P.install()
  local S = G3().SPECIALS
  local fallback = S[242]
  S[242] = function(ctx)
    if getVar(ctx, F().VAR_FACILITY) == P.FACILITY then
      P.func(ctx, getVar(ctx, 0x8004))
      return
    end
    return fallback and fallback(ctx)
  end
  -- 406 CloseBattlePikeCurtain, 145 DrawWholeMapView, 278 SpawnCameraObject:
  -- the curtain is drawn by the map's own metatile swaps around it; nothing
  -- else is left for these to do here
  S[406] = S[406] or function() end
end

return P
