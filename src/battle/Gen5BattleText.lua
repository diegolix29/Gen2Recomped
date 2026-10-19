-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S BATTLE LINES, from the cartridge's own banks.
--
-- The system text archive (/a/0/0/2) carries the battle's words in three
-- banks, imported as TEXT_G5S_<bank>_<line>:
--
--   13  "X used Move!"            three lines per move: 3 * move + side
--   14  btl_set, the lines about a Pokemon. Most come as THREE: the player's
--       Pokemon, "The wild X", "The foe's X" (line, line + 1, line + 2).
--       A few name two Pokemon and come as SEVEN: (player, player),
--       (player, wild), (player, foe), (wild, player), (wild, wild),
--       (foe, player), (foe, foe) -- 644 "transformed into", 651 "took aim".
--   15  btl_std, the lines about nobody in particular ("But it failed!",
--       "It's super effective!", the weather, the screens).
--
-- Every index below was read off an imported Black cache and is named by the
-- player's line it starts with, so a reader can grep the cache for it.
--
-- TWO WAYS IN. The BW move effects (src/battle/Gen5MoveEffects.lua) ask for
-- their lines here by name. Everything else the engine prints -- its own
-- English, written for Kanto with "Enemy " in front of a foe's name -- is
-- translated at the one place a battle message starts (BattleState:
-- startMessage), by the pattern table at the bottom. A line no pattern knows
-- is left as it was.

local T = {}

T.BANK_USED, T.BANK_SET, T.BANK_STD = 13, 14, 15

-- btl_set lines (the player's variant; +1 wild, +2 foe)
T.SET = {
  fainted = 0, failedToAffect = 24,
  -- stat lines: base + 3 * stat, stats in the order below
  rose = 27, roseSharply = 48, roseDrastically = 69,
  fell = 90, fellHarshly = 111, fellSeverely = 132,
  noHigher = 153, noLower = 174,
  statsRemoved = 195, statsNotLowered = 198,
  notAffected = 210, avoided = 213, unaffected = 216, transformed = 222,
  poisoned = 234, badlyPoisoned = 237, hurtByPoison = 243, alreadyPoisoned = 249,
  burned = 255, hurtByBurn = 261, alreadyBurned = 267,
  paralyzed = 273, fullyParalyzed = 276, alreadyParalyzed = 282,
  frozen = 288, isFrozen = 291, thawed = 294, alreadyFrozen = 297,
  fellAsleep = 306, fastAsleep = 309, wokeUp = 312, alreadyAsleep = 315,
  nightmare = 321, fellInLove = 327, inLoveWith = 333, immobilizedByLove = 336,
  statusNormal = 342, confused = 345, isConfused = 348, snappedOut = 351,
  alreadyConfused = 354, confusedFatigue = 360, flinched = 363,
  lostFocus = 366, identified = 369, hurtBy = 372, freedFrom = 375,
  recoil = 378, hpRestored = 387, endured = 514, braced = 511,
  protected = 523, brokeProtection = 520, fellForFeint = 526,
  flewUp = 529, rageBuilding = 532, hidUnderwater = 535, burrowed = 538,
  vanished = 541, sprangUp = 544, whirlwind = 547, harshLight = 550,
  absorbedLight = 553, tuckedHead = 556, encore = 559, encoreEnded = 562,
  abilitySuppressed = 565, taunt = 568, tauntEnded = 574, torment = 577,
  sealed = 586, disabled = 592, disableEnded = 598, aquaRing = 601,
  aquaRingHeal = 604, seeded = 607, sapped = 610, bellyDrum = 613,
  focusing = 616, destinyBond = 626, grudge = 632, rested = 638,
  spite = 641, magnetRise = 658, magnetRiseEnded = 661, charging = 664,
  drowsy = 667, centerOfAttention = 670, heartSwap = 673, powerSwap = 676,
  guardSwap = 679, trick = 682, obtained = 685, sketched = 691,
  moonlight = 694, healingWish = 697, wish = 700, uproar = 703,
  stockpiled = 721, embargo = 727, embargoEnded = 730, found = 733,
  ingrain = 736, ingrainHeal = 739, anchoredRoots = 742, storingEnergy = 745,
  unleashedEnergy = 748, magicCoat = 761, fled = 767, powerTrick = 773,
  ateBerry = 776, flung = 779, substitute = 785, alreadySubstitute = 788,
  subTookDamage = 791, subFaded = 794, wideGuard = 797, quickGuard = 800,
  trappedVortex = 824, trappedFire = 827, trappedMagma = 830,
  trappedSandTomb = 833, safeguarded = 839, mist = 842, draggedOut = 845,
  mustRecharge = 848, spikes = 851, stealthRock = 854, trickRoom = 857,
  perish = 860, freezingLight = 863, freezingAir = 866, cantEscape = 872,
  healBlock = 881, healBlockEnded = 884, hpFull = 893, typeChange = 896,
  crashed = 902, pumped = 1041, psychUp = 1047, curseHurt = 1071,
  foresaw = 1074, doomDesire = 1077, tookAttack = 1080, gravityFall = 1083,
  powerSplit = 1096, guardSplit = 1099, nimble = 1102, burntUp = 1108,
  freedSkyDrop = 1125, fellDown = 1128, postponed = 1131, kindOffer = 1134,
  hurled = 1140, telekinesisEnded = 1143,
}

-- the SEVEN-way lines (two Pokemon named)
T.PAIR = {
  transformedInto = 644, tookAim = 651, squeezed = 803, wrapped = 810,
  clamped = 817, hurtByAbility = 1031, knockedOff = 1050, stole = 1057,
  cursed = 1064, typeMatch = 1089, received = 1111, skyDrop = 1118,
  waiting = 1146,
}

-- btl_std lines
T.STD = {
  usedItem = 33, hitTimes = 32, noEffect = 68, failed = 71,
  superEffective = 78, notVeryEffective = 79, hurtItself = 80, critical = 81,
  noPP = 82, sun = 84, rain = 85, sandstorm = 86, hail = 87,
  sunFaded = 89, rainStopped = 90, sandSubsided = 91, hailStopped = 92,
  sandRages = 95, hailCrashes = 96, ohko = 97, statsEliminated = 101,
  nothingHappened = 102, magnitude = 104, bell = 111, aroma = 112,
  painSplit = 113, mudSport = 115, waterSport = 114, trickRoomEnded = 116,
  gravity = 117, gravityEnded = 118, perishSong = 119, metronome = 120,
  naturePower = 121, payDay = 122, tooWeakSub = 123,
  reflect = 124, reflectEnded = 126, lightScreen = 128, lightScreenEnded = 130,
  safeguard = 132, safeguardEnded = 134, mist = 136, mistEnded = 138,
  tailwind = 140, tailwindEnded = 142, luckyChant = 144, luckyChantEnded = 146,
  spikes = 148, spikesGone = 150, toxicSpikes = 152, toxicSpikesGone = 154,
  stealthRock = 156, stealthRockGone = 158, wideGuard = 160, quickGuard = 162,
  wonderRoom = 178, wonderRoomEnded = 179, magicRoom = 180, magicRoomEnded = 181,
}

-- the stat order the stat lines are laid out in
T.STAT_ORDER = { attack = 0, defense = 1, spatk = 2, spdef = 3, speed = 4,
                 accuracy = 5, evasion = 6 }

local function rawLine(data, bank, index)
  local text = data and data.text
             and data.text[("TEXT_G5S_%04d_%05d"):format(bank, index)]
  if type(text) ~= "string" or text == "" then return nil end
  return text
end

-- fill {VARn}, drop the control codes ({CMD BE09 60} is a pause; the counts
-- {CMD 0200 n} arrive as vars.count), and turn a page break into the
-- battle box's continue code
local function fill(text, vars)
  vars = vars or {}
  text = text:gsub("{VAR(%d+)}", function(n)
    local v = vars[tonumber(n)]
    return v ~= nil and tostring(v) or ""
  end)
  text = text:gsub("{CMD 020%d %d}", function()
    return vars.count ~= nil and tostring(vars.count) or ""
  end)
  text = text:gsub("{CMD[^}]*}", "")
  text = text:gsub("\n\n\n", "\v")
  return text
end

T.fill = fill

-- which of the three a battler is: the player's, the wild one, a trainer's
function T.side(battle, battler)
  if not battler or battler.isPlayer then return 0 end
  if battle and battle.kind == "wild" then return 1 end
  return 2
end

function T.nameOf(battler)
  return battler and (battler.name or (battler.mon and battler.mon.nickname)) or "?"
end

-- a btl_set line about one Pokemon; `fallback` (English, %s = the name)
-- answers for a cache without the bank
function T.set(battle, key, battler, vars, fallback)
  local base = type(key) == "number" and key or T.SET[key]
  vars = vars or {}
  vars[1] = vars[1] or T.nameOf(battler)
  local text = base and rawLine(battle and battle.data, T.BANK_SET,
                                base + T.side(battle, battler))
  if text then return fill(text, vars) end
  return fallback and fallback:format(vars[1], vars[2], vars[3])
         or tostring(vars[1])
end

-- a btl_set line naming two Pokemon (the seven-way layout)
local PAIR_SLOT = { ["00"] = 0, ["01"] = 1, ["02"] = 2, ["10"] = 3,
                    ["11"] = 4, ["20"] = 5, ["22"] = 6, ["21"] = 4, ["12"] = 2 }
function T.pair(battle, key, a, b, vars, fallback)
  local base = type(key) == "number" and key or T.PAIR[key]
  vars = vars or {}
  vars[1] = vars[1] or T.nameOf(a)
  vars[2] = vars[2] or T.nameOf(b)
  local slot = PAIR_SLOT[T.side(battle, a) .. T.side(battle, b)] or 0
  local text = base and rawLine(battle and battle.data, T.BANK_SET, base + slot)
  if text then return fill(text, vars) end
  return fallback and fallback:format(vars[1], vars[2], vars[3]) or vars[1]
end

-- a btl_std line
function T.std(battle, key, vars, fallback)
  local index = type(key) == "number" and key or T.STD[key]
  local text = index and rawLine(battle and battle.data, T.BANK_STD, index)
  if text then return fill(text, vars) end
  return fallback or ""
end

-- the screens / side lines come in pairs: your team, then the foe's
function T.team(battle, key, battler, fallback)
  local index = T.STD[key]
  if not index then return fallback or "" end
  if battler and not battler.isPlayer then index = index + 1 end
  return T.std(battle, index, nil, fallback)
end

-- "X's Attack rose sharply!" and its kin. `applied` is the stages actually
-- moved (signed); `wanted` the stages asked for, for the "won't go any
-- higher" lines when nothing moved.
function T.stat(battle, battler, stat, applied, wanted)
  local order = T.STAT_ORDER[stat]
  if not order then return nil end
  local key
  if applied == 0 or applied == nil then
    key = (wanted or 0) > 0 and "noHigher" or "noLower"
  elseif applied >= 3 then key = "roseDrastically"
  elseif applied == 2 then key = "roseSharply"
  elseif applied >= 1 then key = "rose"
  elseif applied <= -3 then key = "fellSeverely"
  elseif applied == -2 then key = "fellHarshly"
  else key = "fell" end
  return T.set(battle, T.SET[key] + 3 * order, battler)
end

-- "X used Move!"
function T.used(battle, battler, moveId, moveName)
  local id = tonumber(moveId)
  local text = id and rawLine(battle and battle.data, T.BANK_USED,
                              3 * id + T.side(battle, battler))
  if text then return fill(text, { T.nameOf(battler) }) end
  return nil
end

-- ---------------------------------------------------------------------------
-- THE ENGINE'S OWN ENGLISH, TRANSLATED.
--
-- Each row: a Lua pattern over the whole message (names captured as "(.-)"),
-- and what to print instead. A captured name beginning "Enemy " is a foe's;
-- the rest is the player's. Rows are tried in order; the first match wins.
-- ---------------------------------------------------------------------------

local STAT_WORD = {
  ATTACK = "attack", DEFENSE = "defense", SPEED = "speed",
  ["SPCL.ATK"] = "spatk", ["SPCL.DEF"] = "spdef", ACCURACY = "accuracy",
  EVADE = "evasion", EVASION = "evasion", SPECIAL = "spatk",
}

-- a battler-shaped stand-in for a name the engine printed
local function who(battle, printed)
  local name = printed
  local foe = false
  if name:sub(1, 6) == "Enemy " then foe, name = true, name:sub(7) end
  return { name = name, isPlayer = not foe }
end

local function one(key)
  return function(battle, a) return T.set(battle, key, who(battle, a)) end
end

local function std(key)
  return function(battle) return T.std(battle, key) end
end

local function statLine(delta)
  return function(battle, a, label)
    local stat = STAT_WORD[label]
    if not stat then return nil end
    return T.stat(battle, who(battle, a), stat, delta, delta)
  end
end

T.PATTERNS = {
  -- the stat lines (MoveEffects.changeStage, Gen3MoveEffects)
  { "^(.-)'s\n([%u%.]+)\ngreatly rose!$", statLine(2) },
  { "^(.-)'s\n([%u%.]+) rose!$", statLine(1) },
  { "^(.-)'s\n([%u%.]+)\ngreatly fell!$", statLine(-2) },
  { "^(.-)'s\n([%u%.]+) fell!$", statLine(-1) },
  { "^(.-)'s ([%u%.]+) sharply rose!$", statLine(2) },
  { "^(.-)'s ([%u%.]+) rose!$", statLine(1) },
  { "^(.-)'s ([%u%.]+) sharply fell!$", statLine(-2) },
  { "^(.-)'s ([%u%.]+) fell!$", statLine(-1) },
  { "^(.-)'s\n([%u%.]+)\nwon't go lower!$", function(battle, a, label)
      local stat = STAT_WORD[label]
      return stat and T.stat(battle, who(battle, a), stat, 0, -1) end },
  { "^(.-) is\nprotected by MIST!$", one("mist") },
  -- the statuses (Status.RECORDS)
  { "^(.-)\nfell asleep!$", one("fellAsleep") },
  { "^(.-)\nis fast asleep!$", one("fastAsleep") },
  { "^(.-)\nwoke up!$", one("wokeUp") },
  { "^(.-) woke up!$", one("wokeUp") },
  { "^(.-)\nwas frozen solid!$", one("frozen") },
  { "^(.-)\nis frozen solid!$", one("isFrozen") },
  { "^(.-)\nwas defrosted!$", one("thawed") },
  { "^Fire defrosted\n(.-)!$", one("thawed") },
  { "^(.-)'s\nbadly poisoned!$", one("badlyPoisoned") },
  { "^(.-)\nwas poisoned!$", one("poisoned") },
  { "^(.-)\nwas burned!$", one("burned") },
  { "^(.-)'s\nparalyzed! It may\nnot attack!$", one("paralyzed") },
  { "^(.-)'s\nfully paralyzed!$", one("fullyParalyzed") },
  { "^(.-)'s\nhurt by poison!$", one("hurtByPoison") },
  { "^(.-)'s\nhurt by the burn!$", one("hurtByBurn") },
  { "^(.-)\nflinched!$", one("flinched") },
  { "^(.-)\nbecame confused!$", one("confused") },
  { "^(.-)\nis confused!$", one("isConfused") },
  { "^(.-)'s\nconfused no more!$", one("snappedOut") },
  { "^(.-)\nfell in love!$", one("fellInLove") },
  { "^(.-) is\nimmobilized by love!$", one("immobilizedByLove") },
  { "^(.-)\nwas seeded!$", one("seeded") },
  { "^(.-)\nbecame drowsy!$", one("drowsy") },
  { "^(.-) fell for\nthe taunt!$", one("taunt") },
  { "^(.-)'s taunt\nwore off!$", one("tauntEnded") },
  { "^(.-) was\nsubjected to\nTORMENT!$", one("torment") },
  { "^(.-) got\nan ENCORE!$", one("encore") },
  { "^(.-)'s ENCORE\nended!$", one("encoreEnded") },
  { "^(.-) was\nidentified!$", one("identified") },
  { "^(.-) is trying\nto take its foe\nwith it!$", one("destinyBond") },
  { "^(.-) wants the foe\nto bear a grudge!$", one("grudge") },
  { "^(.-) planted its\nroots!$", one("ingrain") },
  { "^(.-) absorbed\nnutrients with its\nroots!$", one("ingrainHeal") },
  { "^(.-)'s wish\ncame true!$", one("wish") },
  { "^(.-) cut its HP and\nmaximized ATTACK!$", one("bellyDrum") },
  { "^(.-)\nis storing energy!$", one("storingEnergy") },
  { "^(.-)\nunleashed energy!$", one("unleashedEnergy") },
  { "^(.-)\nmust recharge!$", one("mustRecharge") },
  { "^(.-)'s\nhit with recoil!$", one("recoil") },
  { "^(.-)\nprotected itself!$", one("protected") },
  { "^(.-) braced\nitself!$", one("braced") },
  { "^(.-) endured\nthe hit!$", one("endured") },
  { "^(.-)'s\nRAGE is building!$", one("rageBuilding") },
  { "^(.-)'s\nSUBSTITUTE broke!$", one("subFaded") },
  { "^The SUBSTITUTE\ntook damage for\n(.-)!$", one("subTookDamage") },
  { "^(.-)\nregained health!$", one("hpRestored") },
  { "^(.-)'s\nHP is full!$", one("hpFull") },
  { "^(.-)\nkept going and\ncrashed!$", one("crashed") },
  { "^(.-) can't\nrun away!$", one("cantEscape") },
  { "^(.-) is hurt\nby SPIKES!$", one("spikes") },
  { "^(.-)\nfainted!$", one("fainted") },
  { "^It doesn't affect\n(.-)!$", one("notAffected") },
  { "^It didn't affect\n(.-)!$", one("notAffected") },
  { "^(.-)\nis unaffected!$", one("unaffected") },
  { "^(.-)\ntransformed into\n(.-)!$", function(battle, a, b)
      return T.pair(battle, "transformedInto", who(battle, a), who(battle, b)) end },
  { "^(.-) took aim\nat (.-)!$", function(battle, a, b)
      return T.pair(battle, "tookAim", who(battle, a), who(battle, b)) end },
  { "^(.-) took the\n(.-) attack!$", function(battle, a, m)
      return T.set(battle, "tookAttack", who(battle, a), { nil, m }) end },
  { "^(.-) foresaw\nan attack!$", one("foresaw") },
  { "^(.-)\nused (.-)!$", function(battle, a, m)
      local id = battle and battle.bwMoveIdByName and battle.bwMoveIdByName[m]
      return id and T.used(battle, who(battle, a), id) end },
  -- the lines about nobody
  { "^But, it failed!$", std("failed") },
  { "^Nothing happened!$", std("nothingHappened") },
  { "^No effect!$", std("nothingHappened") },
  { "^It's super\neffective!$", std("superEffective") },
  { "^It's not very\neffective%.%.%.$", std("notVeryEffective") },
  { "^Critical hit!$", std("critical") },
  { "^One%-hit KO!$", std("ohko") },
  { "^Coins scattered\neverywhere!$", std("payDay") },
  { "^A bell chimed!$", std("bell") },
  { "^The battlers shared\ntheir pain!$", std("painSplit") },
  { "^All STATUS changes\nare eliminated!$", std("statsEliminated") },
  { "^Magnitude (%d+)!$", function(battle, n)
      n = tonumber(n)
      return n and n >= 4 and n <= 10 and T.std(battle, T.STD.magnitude + n - 4) end },
  { "^Hit the enemy\n(%d+) times!$", function(battle, n)
      return T.std(battle, "hitTimes", { count = n }) end },
  { "^Hit (%d+) times!$", function(battle, n)
      return T.std(battle, "hitTimes", { count = n }) end },
  { "^Too weak to make\na SUBSTITUTE!$", std("tooWeakSub") },
  -- the weather (Weather.STARTED_TEXT / ENDED_TEXT / the upkeep lines)
  { "^A downpour\nstarted!$", std("rain") },
  { "^The sunlight got\nbright!$", std("sun") },
  { "^A SANDSTORM\nbrewed!$", std("sandstorm") },
  { "^It started to hail!$", std("hail") },
  { "^The rain stopped%.$", std("rainStopped") },
  { "^The sunlight\nfaded%.$", std("sunFaded") },
  { "^The SANDSTORM\nsubsided%.$", std("sandSubsided") },
  { "^The hail stopped%.$", std("hailStopped") },
  { "^The SANDSTORM\nrages%.$", std("sandRages") },
  { "^Hail continues to\nfall%.$", std("hailCrashes") },
  { "^(.-) is buffeted\nby the sandstorm!$", one(396) },
  { "^(.-) is buffeted\nby the hail!$", one(399) },
  { "^The twisted dimensions\nreturned to normal!$", std("trickRoomEnded") },
  -- the charge turns (Gen5MoveEffects.CHARGE's templates)
  { "^(.-)\nwhipped up a whirlwind!$", one("whirlwind") },
  { "^(.-) became\ncloaked in a harsh light!$", one("harshLight") },
  { "^(.-) tucked\nin its head!$", one("tuckedHead") },
  { "^(.-)\nabsorbed light!$", one("absorbedLight") },
  { "^(.-)\nflew up high!$", one("flewUp") },
  { "^(.-) hid\nunderwater!$", one("hidUnderwater") },
  { "^(.-) burrowed\nits way under the ground!$", one("burrowed") },
  { "^(.-)\nsprang up!$", one("sprangUp") },
  { "^(.-) vanished\ninstantly!$", one("vanished") },
  { "^(.-) became cloaked\nin a freezing light!$", one("freezingLight") },
  { "^(.-) became cloaked\nin freezing air!$", one("freezingAir") },
  -- a miss names the one that avoided it; in a single battle that is the
  -- user's opponent
  { "^(.-)'s\nattack missed!$", function(battle, a)
      local user = who(battle, a)
      local target = user.isPlayer and battle and battle.enemy or (battle and battle.player)
      return target and T.set(battle, "avoided", target) end },
  { "^(.-)'s PERISH count\nfell to (%d+)!$", function(battle, a, n)
      return T.set(battle, "perish", who(battle, a), { count = n }) end },
  { "^(.-)'s party is\ncovered by a veil!$", function(battle, a)
      return T.team(battle, "safeguard", who(battle, a)) end },
  { "^(.-)'s party is no\nlonger protected!$", function(battle, a)
      return T.team(battle, "safeguardEnded", who(battle, a)) end },
  { "^(.-)\nweakened ELECTRIC's\npower!$", std("mudSport") },
  { "^(.-)\nweakened FIRE's\npower!$", std("waterSport") },
  -- the engine's records BW reuses (Mimic, Sketch, Skill Swap, Role Play,
  -- Refresh, Wish)
  { "^(.-)\nlearned\n(.-)!$", function(battle, a, m)
      return T.set(battle, 688, who(battle, a), { nil, m }) end },
  { "^(.-) SKETCHED\n(.-)!$", function(battle, a, m)
      return T.set(battle, "sketched", who(battle, a), { nil, m }) end },
  { "^(.-) swapped\nabilities with its\nopponent!$", one(508) },
  { "^(.-)'s ability\nbecame (.-)!$", function(battle, a, name)
      local label = name:lower():gsub("(%a)([%w']*)", function(x, y) return x:upper() .. y end)
      return T.set(battle, 405, who(battle, a), { nil, label }) end },
  { "^(.-)'s\nstatus returned to\nnormal!$", one("statusNormal") },
  -- (BW has no line for a wish being made; the name is given its side)
  { "^(.-) made a wish!$", function(battle, a)
      local b = who(battle, a)
      local prefix = ({ [0] = "", "The wild ", "The foe's " })[T.side(battle, b)]
      return prefix .. b.name .. " made a wish!" end },
}

-- the engine's line in, the cartridge's out (or the engine's, unchanged)
function T.translate(battle, text)
  if type(text) ~= "string" or text == "" then return text end
  for _, row in ipairs(T.PATTERNS) do
    local fn = row[2]
    if fn then
      local caps = { text:match(row[1]) }
      if caps[1] ~= nil then
        local ok, out = pcall(fn, battle, caps[1], caps[2], caps[3])
        if ok and type(out) == "string" and out ~= "" then return out end
        return text
      end
    end
  end
  return text
end

return T
