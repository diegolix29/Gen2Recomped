-- Damage calculation, ported from engine/battle/core.asm (Gen 1) 
-- and engine/battle/effect_commands.asm (Gen 2).
--
-- Battlers carry curStats/curTypes (Transform/Conversion can override the
-- species values) plus reflect/lightScreen/focusEnergy volatile flags.
-- Battlers built by makeBattler also carry the merged badgeBoosts rows and
-- statuses records; hand-built battlers fall back to the vanilla tables.

local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Stats = require("src.pokemon.Stats")
local Status = require("src.battle.Status")
local TypeChart = require("src.battle.TypeChart")
local Weather = require("src.battle.Weather")
local HeldItems = require("src.battle.HeldItems")
local HoldItems = require("src.battle.HoldItems")
local Abilities = require("src.battle.Abilities")
local GameVersion = require("src.core.GameVersion")

local Damage = {}

--------------------------------------------------------------------------------
-- SHARED / CONSTANTS
--------------------------------------------------------------------------------

-- Moves with a boosted critical-hit rate (engine/battle/core.asm
-- CriticalHitTest checks these move ids explicitly).  The move-record
-- highCrit field wins; this list covers pre-existing imported caches.
local HIGH_CRIT = {
  KARATE_CHOP = true, RAZOR_LEAF = true, CRABHAMMER = true, SLASH = true,
}

-- ApplyBadgeStatBoosts (engine/battle/core.asm): x9/8 per badge on the
-- named battle stat.  Data.constants.badgeBoosts replaces this via the
-- battler's badgeBoosts field; these rows are the vanilla values.
Damage.BADGE_BOOSTS = {
  { badge = "BOULDERBADGE", stat = "attack", num = 9, den = 8 },
  { badge = "THUNDERBADGE", stat = "defense", num = 9, den = 8 },
  { badge = "SOULBADGE", stat = "speed", num = 9, den = 8 },
  { badge = "VOLCANOBADGE", stat = "special", num = 9, den = 8 },
}

-- ../pokecrystal/constants/battle_constants.asm:78
Damage.MAX_STAT_VALUE = 999

-- data/battle/critical_hit_chances.asm, as "1 in N".
Damage.CRITICAL_CHANCES = { [0] = 15, 8, 4, 3, 2, 2, 2 }

-- Gen 2's damage spread: 85% to 100% inclusive.
Damage.MIN_VARIATION = 85
Damage.MAX_VARIATION = 100

-- The cart caps a single hit at 999 (DAMAGE_CAP + MIN_DAMAGE).
Damage.MAX_DAMAGE = 999
Damage.MIN_DAMAGE = 2

-- Stat stage multipliers (numerator, denominator), -6..+6.
local STAGE = {
  [-6] = { 25, 100 }, [-5] = { 28, 100 }, [-4] = { 33, 100 },
  [-3] = { 40, 100 }, [-2] = { 50, 100 }, [-1] = { 66, 100 },
  [0] = { 1, 1 },
  [1] = { 15, 10 }, [2] = { 2, 1 }, [3] = { 25, 10 },
  [4] = { 3, 1 }, [5] = { 35, 10 }, [6] = { 4, 1 },
}

--------------------------------------------------------------------------------
-- GEN 1 HELPERS & COMPUTE
--------------------------------------------------------------------------------

-- the boost a battler's badge set applies to one battle stat, or nil
local function badgeBoost(battler, stat)
  local badges = battler.badges
  if not badges then return nil end
  for _, row in ipairs(battler.badgeBoosts or Damage.BADGE_BOOSTS) do
    if badges[row.badge]
       and (row.stat == stat
            or (row.stat == "special" and (stat == "spatk" or stat == "spdef")))
    then
      return row
    end
  end
  return nil
end

-- the merged status record for a battler's persistent condition, or nil
local function statusRecord(battler)
  return Status.recordFor(battler.statuses, battler.mon.status)
end

-- Stat stage for one battle stat.  A cache imported before the Sp.Atk /
-- Sp.Def split still names both halves "special", so the split keys fall
-- back to it rather than silently reading stage 0.
local SPECIAL_HALF = { spatk = true, spdef = true }
local function stageOf(battler, stat)
  local stages = battler.stages
  if not stages then return 0 end
  if stages[stat] then return stages[stat] end
  if SPECIAL_HALF[stat] then return stages.special or 0 end
  return 0
end
Damage.stageOf = stageOf

local CRIT_STAGE_DEN = { [0] = 16, 8, 4, 3, 2 }

function Damage.critRoll(ruleset, attacker, moveId, rng, highCrit, data)
  rng = rng or love.math.random
  if highCrit == nil then highCrit = HIGH_CRIT[moveId] end

  if data and data.constants and data.constants.generation == 2
     and not ruleset.critMultiplier then
    local stage = 0
    if highCrit then stage = stage + 2 end
    if attacker.focusEnergy then stage = stage + 1 end
    stage = stage + HeldItems.criticalStageBonus(data, attacker)
    local chance = ({ [0] = 17, 32, 64, 85, 128, 255 })[math.max(0, math.min(5, stage))]
    return rng(0, 255) < chance
  end

  if ruleset.critStages then
    local stage = 0
    if highCrit then stage = stage + 1 end
    if attacker.focusEnergy then stage = stage + 2 end
    if attacker.critStage then stage = stage + attacker.critStage end
    stage = stage + HoldItems.critStages(attacker)
    local den = CRIT_STAGE_DEN[math.max(0, math.min(4, stage))] or 16
    return rng(1, den) == 1
  end
  local function shl(x) return math.min(255, x * 2) end
  local speed
  if ruleset.critUsesBaseSpeed == false then
    speed = Stats.applyStage(attacker.curStats.speed,
              attacker.stages and attacker.stages.speed or 0)
  else
    speed = attacker.def.baseStats.speed
  end
  local b = math.floor(speed / 2)
  if attacker.focusEnergy then
    if ruleset.focusEnergyBug then
      b = math.floor(b / 2)      -- srl instead of sla
    else
      b = shl(shl(shl(b)))       -- intended: x4 the usual rate
    end
  else
    b = shl(b)
  end
  if highCrit then
    b = shl(shl(b))
  else
    b = math.floor(b / 2)
  end
  return rng(0, 255) < b
end

function Damage.accuracyRoll(ruleset, move, attacker, defender, rng,
                             accuracyRaw, data, weather)
  rng = rng or love.math.random
  if attacker.xAccuracy then return true end
  local acc = accuracyRaw or math.floor(move.accuracy * 255 / 100)
  local basePct = accuracyRaw and (accuracyRaw * 100 / 255) or move.accuracy
  acc = math.min(255, Stats.applyStage(acc,
          attacker.stages and attacker.stages.accuracy or 0))
  acc = math.min(255, Stats.applyStage(acc,
          -(defender.stages and defender.stages.evasion or 0)))
  do
    local pct = Abilities.accuracyMultiplier(attacker, defender, move,
                                             Damage.isSpecial(move.type),
                                             weather)
    pct = math.floor(pct * HoldItems.accuracyMultiplier(attacker, defender)
                     / 100)
    if pct ~= 100 then acc = math.min(255, math.floor(acc * pct / 100)) end
  end
  acc = math.max(0, acc - HeldItems.accuracyPenalty(data, defender))
  if not ruleset.oneIn256Miss and basePct >= 100
     and (attacker.stages.accuracy or 0) >= (defender.stages.evasion or 0) then
    return true
  end
  return rng(0, 255) < acc
end

local warnedTypes = {}
local function categoryOf(move)
  local category = move.category or TypeChart.category(move.type)
  if category == nil then
    if move.type ~= nil and not warnedTypes[move.type] then
      warnedTypes[move.type] = true
      Logger.warn("move type %s has no category; treated as physical",
                  tostring(move.type))
    end
    category = "physical"
  end
  return category
end

function Damage.isSpecial(moveType)
  return TypeChart.category(moveType) == "special"
end

function Damage.compute(ruleset, attacker, defender, move, opts)
  opts = opts or {}
  local rng = opts.rng or love.math.random
  if move.power == 0 or move.category == "status" then
    return 0, { crit = false, typeMult = 10 }
  end

  if not opts.typeless and Abilities.blocks(defender, move) then
    return 0, { crit = false, typeMult = 0, ability = Abilities.of(defender) }
  end

  local crit = opts.forceCrit
  if Abilities.refusesCrit(defender) then
    crit = false
  end
  if crit == nil then
    if Runtime.wantsHook("battle.crit") then
      crit = Runtime.call("battle.crit", function(c)
        return Damage.critRoll(c.ruleset, c.attacker, c.moveId, c.rng, c.highCrit, c.data)
      end, { ruleset = ruleset, attacker = attacker, moveId = move.id,
             rng = rng,
             highCrit = opts.highCrit ~= nil and opts.highCrit
                        or move.highCrit,
             data = opts.data })
    else
      local high = move.highCrit
      if opts.highCrit ~= nil then high = opts.highCrit end
      crit = Damage.critRoll(ruleset, attacker, move.id, rng, high, opts.data)
    end
  end

  local special = categoryOf(move) == "special"
  local split = special and attacker.curStats.spatk and defender.curStats.spdef
  local atkStat = special and (split and "spatk" or "special") or "attack"
  local defStat = special and (split and "spdef" or "special") or "defense"

  local atk, dfn
  if crit and ruleset.critIgnoresStages then
    atk = attacker.curStats[atkStat]
    dfn = defender.curStats[defStat]
  else
    atk = Stats.applyStage(attacker.curStats[atkStat],
                           stageOf(attacker, atkStat))
    dfn = Stats.applyStage(defender.curStats[defStat],
                           stageOf(defender, defStat))
    local atkBoost = badgeBoost(attacker, atkStat)
    if atkBoost then
      atk = math.floor(atk * (atkBoost.num or 9) / (atkBoost.den or 8))
    end
    local defBoost = badgeBoost(defender, defStat)
    if defBoost then
      dfn = math.floor(dfn * (defBoost.num or 9) / (defBoost.den or 8))
    end
    local record = statusRecord(attacker)
    local penalty = record and record.statPenalty
    if penalty and penalty.stat == atkStat and not attacker.hazeStatReset
       and not Abilities.ignoresBurnDrop(attacker) then
      atk = math.max(1, math.floor(atk / penalty.div))
    end
    if not crit then
      local screens = opts.screens
      if screens == nil and not opts.typeless then screens = defender end
      if screens then
        local up = (special and screens.lightScreen)
                   or (not special and screens.reflect)
        if up then
          local num = opts.doublesScreens and ruleset.screenDoublesDen or nil
          local den = opts.doublesScreens and ruleset.screenDoublesNum or nil
          if num and den then
            dfn = math.floor(dfn * num / den)
          else
            dfn = dfn * 2
          end
        end
      end
    end
  end

  atk, dfn = HeldItems.modifyBattleStats(opts.data, attacker, defender,
                                         atkStat, defStat, atk, dfn)

  do
    local an, ad = Abilities.attackMultiplier(attacker, move, special)
    if an ~= 1 or ad ~= 1 then atk = math.max(1, math.floor(atk * an / ad)) end
    local dn, dd = Abilities.defenceMultiplier(defender, move, special)
    if dn ~= 1 or dd ~= 1 then dfn = math.max(1, math.floor(dfn * dn / dd)) end
  end

  do
    local an, ad = HoldItems.attackMultiplier(attacker, move, special)
    if an ~= 1 or ad ~= 1 then atk = math.max(1, math.floor(atk * an / ad)) end
    local dn, dd = HoldItems.defenceMultiplier(defender, move, special)
    if dn ~= 1 or dd ~= 1 then dfn = math.max(1, math.floor(dfn * dn / dd)) end
  end

  if atk > 255 or dfn > 255 then
    atk = math.max(1, math.floor(atk / 4))
    dfn = math.max(1, math.floor(dfn / 4))
  end
  if opts.explode then
    dfn = math.max(1, math.floor(dfn / 2))
  end

  local level = attacker.mon.level
  if crit and not ruleset.critMultiplier then level = level * 2 end

  local d = math.floor(math.floor(2 * level / 5) + 2)
  local power = move.power
  if opts.powerMultiplier and opts.powerMultiplier ~= 1 then
    power = math.max(1, math.floor(power * opts.powerMultiplier))
  end
  d = math.floor(math.floor(d * power * atk / math.max(1, dfn)) / 50)

  if opts.spread and ruleset.spreadNum and ruleset.spreadDen then
    d = math.floor(d * ruleset.spreadNum / ruleset.spreadDen)
  end

  d = math.min(d, 997) + 2

  if not opts.typeless then
    d = HeldItems.applyTypeBoost(opts.data, attacker, move.type, d)
  end

  if not opts.typeless and opts.weather then
    d = Weather.applyModifier(d, opts.weather, move.type, move.effect)
  end

  local mult = 10
  if not opts.typeless then
    local stab = false
    for _, t in ipairs(attacker.curTypes) do
      if t == move.type then stab = true break end
    end
    if stab then
      d = math.floor(d * 3 / 2)
    end

    mult = TypeChart.effectiveness(move.type, defender.curTypes)
    local foresight = defender.identified
      and (Abilities.normalizeType(move.type) == "NORMAL"
           or Abilities.normalizeType(move.type) == "FIGHTING")
    if mult == 0 and foresight then mult = 10 end
    if mult == 0 then
      return 0, { crit = false, typeMult = 0 }
    end
    if Abilities.blocks(defender, move, mult) then
      return 0, { crit = false, typeMult = 0,
                  ability = Abilities.of(defender) }
    end
    for _, m in ipairs(TypeChart.rows(move.type, defender.curTypes)) do
      if not (foresight and m == 0) then d = math.floor(d * m / 10) end
    end
    if d == 0 then
      return 0, { crit = false, typeMult = mult, missed = true }
    end
    local pn, pd = Abilities.damageMultiplier(attacker, move)
    if pn ~= 1 or pd ~= 1 then d = math.floor(d * pn / pd) end
    local fn, fd = Abilities.flashFireBoost(attacker, move)
    if fn ~= 1 or fd ~= 1 then d = math.floor(d * fn / fd) end
    local tn, td = HoldItems.damageMultiplier(attacker, move)
    if tn ~= 1 or td ~= 1 then d = math.floor(d * tn / td) end

    local moveType = Abilities.normalizeType(move.type)
    if attacker.charged and moveType == "ELECTRIC" then
      d = d * 2
    end
    for _, muted in pairs(opts.sports or {}) do
      if muted == moveType then d = math.floor(d / 2) end
    end
  end

  if crit and ruleset.critMultiplier then
    d = math.floor(d * ruleset.critMultiplier)
  end
  if d > 1 and not opts.typeless then
    local r = rng(ruleset.randMin, ruleset.randMax)
    d = math.floor(d * r / (ruleset.randDiv or 255))
  end
  return math.max(d, 1), { crit = crit, typeMult = mult }
end

--------------------------------------------------------------------------------
-- GEN 2 / SHARED NEW HELPERS
--------------------------------------------------------------------------------

function Damage.stageMultiplier(stage)
  local entry = STAGE[math.max(-6, math.min(6, stage or 0))]
  return entry[1], entry[2]
end

-- Apply a stat stage, flooring like the cart's Multiply/Divide pair
function Damage.applyStage(value, stage)
  local numerator, denominator = Damage.stageMultiplier(stage)
  local out = math.floor(value * numerator / denominator)
  return math.max(1, math.min(Damage.MAX_STAT_VALUE, out))
end

-- TruncateHL_BC
function Damage.truncateStats(attack, defense, fixed)
  local a = math.max(0, math.floor(attack or 0))
  local d = math.max(0, math.floor(defense or 0))
  while a > 255 or d > 255 do
    d = math.floor(d / 4)
    if d == 0 then d = 1 end
    a = math.floor(a / 4)
    if a == 0 then a = 1 end
    if not fixed then break end
  end
  return a % 256, d % 256
end

function Damage.applyStage(value, stage)
  local numerator, denominator = Damage.stageMultiplier(stage)
  local out = math.floor(value * numerator / denominator)
  -- ../pokecrystal/engine/battle/core.asm:6739
  return math.max(1, math.min(Damage.MAX_STAT_VALUE, out))
end

-- Is this move physical?
function Damage.isPhysical(moveType, types)
  local record = types and types[moveType]
  if record and record.category then return record.category == "physical" end
  local PHYSICAL = {
    NORMAL = true, FIGHTING = true, FLYING = true, POISON = true,
    GROUND = true, ROCK = true, BUG = true, GHOST = true, STEEL = true,
  }
  return PHYSICAL[moveType] == true
end

-- The 1-in-N chance for a critical level.
function Damage.criticalChance(level)
  local capped = math.max(0, math.min(6, level or 0))
  return Damage.CRITICAL_CHANCES[capped]
end

-- BattleCommand_Critical, as a level rather than a roll
function Damage.criticalLevel(opts)
  local level = 0
  if opts.focusEnergy then level = level + 1 end
  if opts.highCritMove then level = level + 2 end
  if opts.scopeLens then level = level + 1 end
  if opts.speciesItemBonus then level = level + 2 end
  return math.min(6, level)
end

-- Roll a critical hit.
function Damage.rollCritical(criticalLevel, random)
  local chance = Damage.criticalChance(criticalLevel)
  local roll
  if random then
    roll = random(chance)
  elseif love and love.math then
    roll = love.math.random(chance) - 1
  else
    roll = math.random(chance) - 1
  end
  return roll == 0
end

-- The x10 type multiplier of a move against a defender (Gen 2 explicit)
function Damage.typeMultiplier(moveType, defenderTypes, matchups)
  local multiplier = 10
  for _, row in ipairs(matchups or {}) do
    if row.attacker == moveType then
      for _, defenderType in ipairs(defenderTypes or {}) do
        if row.defender == defenderType then
          multiplier = math.floor(multiplier * row.multiplier / 10)
          break
        end
      end
    end
  end
  return multiplier
end

-- The core formula (BattleCommand_DamageCalc):
function Damage.base(level, power, attack, defense)
  if (power or 0) <= 0 then return 0 end
  defense = math.max(1, defense or 1)
  local value = math.floor(level * 2 / 5) + 2
  value = value * power
  value = value * attack
  value = math.floor(value / defense)
  value = math.floor(value / 50)
  return value
end

local function withGen1Names(info)
  info.crit = info.critical
  info.typeMult = info.effectiveness
  return info
end

-- Gen 2 Damage `calc` structure
function Damage.calc(opts)
  local physical = Damage.isPhysical(opts.moveType, opts.types)
  local attacker = opts.attacker or {}
  local defender = opts.defender or {}
  local stagesA = attacker.stages or {}
  local stagesD = defender.stages or {}

  local rawAttack = physical and (attacker.attack or 1)
    or (attacker.specialAttack or attacker.special or 1)
  local rawDefense = physical and (defender.defense or 1)
    or (defender.specialDefense or defender.special or 1)
  local stageA = physical and (stagesA.attack or 0)
    or (stagesA.specialAttack or 0)
  local stageD = physical and (stagesD.defense or 0)
    or (stagesD.specialDefense or 0)

  if opts.critical then
    if stageA < 0 then stageA = 0 end
    if stageD > 0 then stageD = 0 end
  end

  local attack = Damage.applyStage(rawAttack, stageA)
  local defense = Damage.applyStage(rawDefense, stageD)

  if opts.screen and not opts.critical then
    defense = defense * 2
  end

  local fixed = opts.reflectOverflowFixed
  if fixed == nil then
    if GameVersion.fixes and type(GameVersion.fixes) == "function" then
      fixed = GameVersion.fixes().reflectOverflow == true
    else
      fixed = false
    end
  end
  attack, defense = Damage.truncateStats(attack, defense, fixed)

  if opts.defenseHalved then defense = math.max(1, math.floor(defense / 2)) end

  if (opts.power or 0) <= 0 then
    return 0, withGen1Names({ effectiveness = 10, critical = false,
      physical = physical })
  end
  local damage = Damage.base(opts.level or 1, opts.power or 0, attack, defense)

  if opts.itemBoostPercent and opts.itemBoostPercent > 0 then
    damage = math.floor(damage * (100 + opts.itemBoostPercent) / 100)
  end

  if opts.critical then damage = damage * 2 end

  damage = math.min(damage, Damage.MAX_DAMAGE - Damage.MIN_DAMAGE)
    + Damage.MIN_DAMAGE

  if opts.weatherPercent and opts.weatherPercent ~= 10 then
    damage = math.max(1, math.floor(damage * opts.weatherPercent / 10))
  end

  if opts.badgeTypeBoost then
    damage = damage + math.max(1, math.floor(damage / 8))
  end

  local stab = false
  for _, attackerType in ipairs(attacker.types or {}) do
    if attackerType == opts.moveType then stab = true break end
  end
  if stab then damage = math.floor(damage * 15 / 10) end

  local effectiveness = Damage.typeMultiplier(
    opts.moveType, defender.types, opts.matchups)
  for _, row in ipairs(opts.matchups or {}) do
    if row.attacker == opts.moveType then
      for _, defenderType in ipairs(defender.types or {}) do
        if row.defender == defenderType then
          damage = math.floor(damage * row.multiplier / 10)
          if damage == 0 and row.multiplier > 0 then damage = 1 end
          break
        end
      end
    end
  end

  if effectiveness <= 0 or damage <= 0 then
    return 0, withGen1Names({
      effectiveness = effectiveness, critical = opts.critical or false,
      physical = physical, stab = stab,
    })
  end

  local variation = opts.variation
  if not variation then
    if opts.random then
      variation = Damage.MIN_VARIATION
        + opts.random(Damage.MAX_VARIATION - Damage.MIN_VARIATION + 1)
    elseif love and love.math then
      variation = love.math.random(Damage.MIN_VARIATION, Damage.MAX_VARIATION)
    else
      variation = math.random(Damage.MIN_VARIATION, Damage.MAX_VARIATION)
    end
  end
  if damage >= 2 then
    damage = math.floor(damage * variation / 100)
  end

  damage = math.max(1, math.min(Damage.MAX_DAMAGE, damage))
  return damage, withGen1Names({
    effectiveness = effectiveness,
    critical = opts.critical or false,
    physical = physical,
    stab = stab,
    variation = variation,
  })
end

-- Accuracy check
function Damage.rollHit(accuracy, accuracyStage, evasionStage, random)
  if not accuracy or accuracy <= 0 then return true end
  local numerator, denominator = Damage.stageMultiplier(accuracyStage or 0)
  local value = math.floor(accuracy * numerator / denominator)
  numerator, denominator = Damage.stageMultiplier(-(evasionStage or 0))
  value = math.floor(value * numerator / denominator)
  value = math.max(1, math.min(100, value))
  local roll
  if random then
    roll = random(100)
  elseif love and love.math then
    roll = love.math.random(100) - 1
  else
    roll = math.random(100) - 1
  end
  return roll < value
end

return Damage