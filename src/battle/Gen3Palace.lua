-- BATTLE PALACE RULES (pokeemerald battle_gfx_sfx_util.c
-- ChooseMoveAndTargetInBattlePalace, battle_script_commands.c's
-- gBattlePalaceNatureToMoveGroupLikelihood and VARIOUS_PALACE_FLAVOR_TEXT).
--
-- Nobody gives orders. Each turn each Pokemon's NATURE picks a move group --
-- Attack, Defense or Support -- with its own odds, and a second set of odds
-- once it is at half HP or below and awake. A move from that group is used.
-- If it knows none, a move from some other group is drawn instead, and half
-- the time it "appears incapable of using its power" and does nothing.
-- When a Pokemon first drops to half, its nature shows: "is eager for
-- more!", "began growling deeply!", a glint in its eyes, or "is getting into
-- position!". Fainted Pokemon are replaced by the next in the party, unasked.
--
-- Verdanturf's Battle Tent fights under these rules, and the Frontier's
-- Battle Palace does.
--
-- WHAT IS NOT THE CARTRIDGE'S: inside the chosen group the cartridge lets its
-- battle AI score the moves (BattleAI_SetupAIData(selectedMoves)); here the
-- pick within the group is random.

local Strings = require("src.core.Strings")

local Palace = {}

Palace.ATTACK, Palace.DEFENSE, Palace.SUPPORT = 0, 1, 2

-- PALACE_STYLE(atk, def, atkLow, defLow) = {atk, atk + def, atkLow, atkLow + defLow},
-- natures in the cartridge's order (Hardy 0 ... Quirky 24)
local function style(a, d, al, dl) return { a, a + d, al, al + dl } end
Palace.LIKELIHOOD = {
  [0] = style(61, 7, 61, 7), style(20, 25, 84, 8), style(70, 15, 32, 60), style(38, 31, 70, 15),
  style(20, 70, 70, 22), style(30, 20, 32, 58), style(56, 22, 56, 22), style(25, 15, 75, 15),
  style(69, 6, 28, 55), style(35, 10, 29, 6), style(62, 10, 30, 20), style(58, 37, 88, 6),
  style(34, 11, 29, 11), style(35, 5, 35, 60), style(56, 22, 56, 22), style(35, 45, 34, 60),
  style(44, 50, 34, 6), style(56, 22, 56, 22), style(30, 58, 30, 58), style(30, 13, 27, 6),
  style(40, 50, 25, 62), style(18, 70, 90, 5), style(88, 6, 22, 20), style(42, 50, 42, 5),
  style(56, 22, 56, 22),
}

-- sBattlePalaceNatureToFlavorTextId: 0 eager for more, 1 glint in its eyes,
-- 2 getting into position, 3 growling deeply
Palace.FLAVOR = { [0] = 0, 1, 2, 1, 1, 2, 0, 1, 2, 3, 3, 1, 0, 2, 0, 2, 3, 0, 0, 3, 2, 1, 3, 3, 0 }
Palace.FLAVOR_TEXT = { [0] = "TEXT_5CCEF7", [2] = "TEXT_5CCEC0", [3] = "TEXT_5CCEDD" }
Palace.FLAVOR_FALLBACK = { [0] = "is eager for more!", [1] = "A glint appears in\n%s's eyes!",
  [2] = "is getting into\nposition!", [3] = "began growling deeply!" }
Palace.INCAPABLE_TEXT = "TEXT_5CCE79"

-- move target bits (Emerald's MOVE_TARGET_*)
local SELECTED, DEPENDS, USER_OR_SELECTED, RANDOM, BOTH, USER, FOES_AND_ALLY, OPPONENTS_FIELD =
  0, 1, 2, 4, 8, 16, 32, 64

-- GetBattlePalaceMoveGroup
function Palace.group(def)
  local t = tonumber(def and def.target) or SELECTED
  local power = tonumber(def and def.power) or 0
  if t == SELECTED or t == USER_OR_SELECTED or t == RANDOM or t == BOTH or t == FOES_AND_ALLY then
    return power == 0 and Palace.SUPPORT or Palace.ATTACK
  elseif t == DEPENDS or t == OPPONENTS_FIELD then
    return Palace.SUPPORT
  elseif t == USER then
    return Palace.DEFENSE
  end
  return Palace.ATTACK
end

function Palace.nature(mon)
  return math.floor(tonumber(mon and mon.personality) or 0) % 25
end

local function asleep(mon)
  local s = mon and mon.status
  return s == "SLP" or (type(s) == "string" and s:find("SLP") ~= nil)
end

-- the half-HP flag: set without a word on switch-in, with the flavor line at
-- the end of a turn
function Palace.isLow(mon)
  local max = mon and mon.stats and mon.stats.hp or 0
  return mon and mon.hp > 0 and math.floor(max / 2) >= mon.hp and not asleep(mon)
end

-- the battler's usable move slots (CheckMoveLimitations: PP, Disable, Taunt,
-- Torment)
function Palace.usable(battle, battler)
  local out = {}
  for i, m in ipairs(battler.curMoves or {}) do
    local ok = m and m.id and (m.pp or 0) > 0
    if ok and battler.disabledSlot == i then ok = false end
    if ok and battle.tauntBlocks and battle:tauntBlocks(battler, m) then ok = false end
    if ok and battle.tormentBlocks and battle:tormentBlocks(battler, m) then ok = false end
    out[i] = ok or nil
  end
  return out
end

-- ChooseMoveAndTargetInBattlePalace: a move entry, or { special = "palaceFail" }
function Palace.choose(battle, battler, rand)
  rand = rand or function(n) return math.random(0, n - 1) end
  local data = battle.data
  local moves = battler.curMoves or {}
  local usable = Palace.usable(battle, battler)
  local percent = rand(100)
  local base = battler.palaceLow and 2 or 0
  local odds = Palace.LIKELIHOOD[Palace.nature(battler.mon)] or Palace.LIKELIHOOD[0]
  local selected = Palace.SUPPORT
  if percent < odds[base + 1] then selected = Palace.ATTACK
  elseif percent < odds[base + 2] then selected = Palace.DEFENSE end
  local groupOf = {}
  for i, m in ipairs(moves) do groupOf[i] = Palace.group(data.moves and data.moves[m.id]) end
  -- the group's moves with PP left (the cartridge checks PP here, not the
  -- other limitations)
  local pool = {}
  for i, m in ipairs(moves) do
    if groupOf[i] == selected and (m.pp or 0) > 0 then pool[#pool + 1] = i end
  end
  if #pool > 0 then return moves[pool[rand(#pool) + 1]] end
  -- none of that group: any usable move, preferring a group with two or more
  local anyUsable = false
  for _ in pairs(usable) do anyUsable = true break end
  if not anyUsable then return { special = "palaceFail" } end
  local counts = { [0] = 0, 0, 0 }
  for i in pairs(usable) do counts[groupOf[i]] = counts[groupOf[i]] + 1 end
  -- the cartridge's own slip: its "two or more Support moves" test reads the
  -- Defense count against a Support threshold and is never true
  local multi, prefer = 0, nil
  if counts[0] >= 2 then multi = multi + 1; prefer = 0 end
  if counts[1] >= 2 then multi = multi + 1; prefer = 1 end
  local slots = {}
  for i in pairs(usable) do
    if multi ~= 1 or groupOf[i] == prefer then slots[#slots + 1] = i end
  end
  table.sort(slots)
  local pick = slots[rand(#slots) + 1]
  -- a move off the nature's group: half the time, nothing
  if rand(100) >= 50 then return { special = "palaceFail" } end
  return moves[pick]
end

function Palace.flavorLine(battle, battler, name)
  local id = Palace.FLAVOR[Palace.nature(battler.mon)] or 0
  if id == 1 then return Strings("A glint appears in\n%s's eyes!", name) end
  local key = Palace.FLAVOR_TEXT[id]
  local tail = key and battle.data.text and battle.data.text[key]
  return name .. " " .. (tail or Strings(Palace.FLAVOR_FALLBACK[id]))
end

function Palace.incapableLine(battle, name)
  local tail = battle.data.text and battle.data.text[Palace.INCAPABLE_TEXT]
  return name .. " " .. (tail or Strings("appears incapable\nof using its power!"))
end

return Palace
