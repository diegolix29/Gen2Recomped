-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S BATTLE BAG: what USE does to an item in a battle.
--
-- !! Reported from play: "when using items like pokeballs in black and white
-- they play a weird message and don't let you throw the balls". A BW item
-- carried neither its battle pocket nor its party block (src/inventory/
-- Gen5Items.lua), so a Poke Ball was not a ball, a Potion not a medicine,
-- and every item fell to the engine's refusal -- printed as Platinum's
-- common_strings line, which in Black's bank 213 is Alder's speech.
--
-- The cartridge's battle bag, by the item's battle pocket mask / battle use:
--   BALL (use 1)    thrown at the foe -- unless two foes stand (bank 17 #44),
--                   the foe is out of sight (#47: Fly, Dig...), the party and
--                   every box are full (#45); at a trainer's Pokemon the
--                   trainer blocks it (bank 15 #67) and the turn is spent
--   ESCAPE (use 3)  Poke Doll / Fluffy Tail / Poke Toy: a wild battle ends
--                   ("Got away safely!", bank 15 #72)
--   BATTLE (mask 2) X items, Dire Hit, Guard Spec. on the Pokemon choosing
--   MEDICINE        (mask 4 / 8 / 16) picks a party member, then the party
--                   block: revive, HP (255 all, 254 half, 253 a quarter),
--                   the status bits, PP (one move / all; 127 all)
--   anything else   Juniper's words (bank 17 #50)
-- A use that does nothing keeps the item: "It won't have any effect."
-- (bank 157 #81). A use that works spends the turn: "{player} used the
-- {item}." (bank 15 #33) and the party screen's line (bank 157).
--
-- THE THROW is Unova's: Gen V's sum (src/battle/Gen5Catching.lua, with the
-- critical capture), shared effect 570 through BattleState:gen4BallChain
-- (src/battle/Gen5BallAnim.lua), the breakout lines 61..64 and "Gotcha!"
-- 65 of bank 15, the ball written on the caught Pokemon (a Heal Ball heals
-- it, a Friend Ball sets its friendship to 200).

local Items = require("src.inventory.Gen5Items")
local T = require("src.battle.Gen5BattleText")
local Strings = require("src.core.Strings")

local U = {}

U.BANK_BAG, U.BANK_STD, U.BANK_PARTY, U.BANK_DEX = 17, 15, 157, 234
U.BAG = { twoPokemon = 44, noRoom = 45, notInSight = 47, juniper = 50 }
U.STD = { used = 33, usedOne = 35, brokeFree = 61, appeared = 62, almost = 63,
          soClose = 64, gotcha = 65, dexAdded = 66, blocked = 67, gotAway = 72 }
U.PARTY = { hp = 44, psn = 45, par = 46, brn = 47, frz = 48, pp = 49, revive = 50,
            healthy = 51, slp = 71, noEffect = 81 }
U.DEX = { nickname = 175, transferred = 176 }

U.HEAL_BALL, U.FRIEND_BALL = 14, 497

local function isGen5()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.isGen5 and GV.isGen5() or false
end

-- does this battle's bag go through here?
function U.handles(game, battle)
  return battle ~= nil and isGen5() and game and game.data and game.data.items ~= nil
end

local function line(data, bank, index, vars, fallback)
  local text = data and data.text and data.text[("TEXT_G5S_%04d_%05d"):format(bank, index)]
  if type(text) ~= "string" or text == "" then
    text = fallback or ""
    for i, v in ipairs(vars or {}) do text = text:gsub("{VAR" .. i .. "}", tostring(v)) end
    return text
  end
  return T.fill(text, vars)
end
U.line = line

local function playerName(game)
  return (game.save and game.save.player and game.save.player.name) or "PLAYER"
end

local function itemName(def, id)
  return (def and def.name) or tostring(id)
end

local function monName(game, mon)
  if not mon then return "?" end
  local d = game.data.pokemon and game.data.pokemon[mon.species]
  return mon.nickname or (d and d.name) or tostring(mon.species)
end

local function maxHP(mon) return (mon and mon.stats and mon.stats.hp) or (mon and mon.maxHp) or 1 end

-- the battle-box text used for the bag's own refusals (over the bag)
local function refuse(game, showMessages, text)
  showMessages(game, { (tostring(text):gsub("\v", "\f")) })
end

function U.juniper(data)
  return line(data, U.BANK_BAG, U.BAG.juniper, nil,
    Strings("Juniper's words echoed...\nThere's a time and\vplace for everything! But not now."))
end

function U.noEffect(data)
  return line(data, U.BANK_PARTY, U.PARTY.noEffect, nil, Strings("It won't have any effect."))
end

local function consume(game, id)
  require("src.inventory.Bag").remove(game.save, id, 1)
end

local function chooser(battle)
  return (battle.menuBattler and battle:menuBattler()) or battle.player
end

-- ---------------------------------------------------------------------------
-- BALLS
-- ---------------------------------------------------------------------------

-- every box full and no room in the party
local function noRoom(game)
  local save = game.save
  if #(save.party or {}) < 6 then return false end
  local Boxes = require("src.pokemon.Boxes")
  local boxes = Boxes.ensure(save)
  for i = 1, Boxes.count() do
    if Boxes.firstFree(boxes[i]) then return false end
  end
  return true
end

-- the refusal for a ball, or nil when it may be thrown
function U.ballRefusal(game, battle)
  local data = game.data
  if battle.kind == "wild" then
    if battle.wildFoesStanding and battle:wildFoesStanding() > 1 then
      return line(data, U.BANK_BAG, U.BAG.twoPokemon, nil,
        Strings("It's no good! It's impossible to aim\nwhen there are two Pokémon!"))
    end
    local foe = battle.enemy
    if foe and foe.invulnerable then
      return line(data, U.BANK_BAG, U.BAG.notInSight, nil,
        Strings("It's no good! It's impossible to aim\nat a Pokémon that's not in sight!"))
    end
    if noRoom(game) then
      return line(data, U.BANK_BAG, U.BAG.noRoom, nil, Strings("There is no room left in the PC!"))
    end
  end
  return nil
end

-- what the caught Pokemon's ball does to it
local function ballOnCatch(mon, ball)
  if not mon then return end
  if ball == U.HEAL_BALL then
    mon.hp = maxHP(mon)
    mon.status = nil
  elseif ball == U.FRIEND_BALL then
    mon.happiness = 200
  end
end

-- the throw itself, on the battle's queue (the bag is already closed)
function U.throw(battle, id)
  local game = battle.game
  local data = battle.data
  local def = data.items[id]
  local Runtime = require("src.mods.Runtime")
  local text = line(data, U.BANK_STD, U.STD.usedOne, { playerName(game), "", itemName(def, id) },
    Strings("{VAR1} used one {VAR3}!"))
  text = text:gsub("^(%S+) +\n", "%1\n"):gsub("  +", " ")
  battle:say(text)
  battle:act(function()
    if battle.kind ~= "wild" then
      -- the trainer swats it away; the turn is spent
      battle:sayNext(line(data, U.BANK_STD, U.STD.blocked, nil,
        Strings("The Trainer blocked the ball!\vDon't be a thief!")))
      battle:act(function() battle:executeAction(battle.enemy, battle.player, battle:enemyAction()) end)
      battle:act(function() battle:endOfTurn() end)
      return
    end
    local G = require("src.battle.Gen5Catching")
    local foe = battle.enemy
    local caught, shakes, critical
    if battle.noCatch or battle.ghost then
      caught, shakes, critical = false, 0, false
    else
      local ctx = G.context(battle, foe.mon, foe.def)
      caught, shakes, critical = G.attempt(id, ctx, battle.rng)
    end
    battle.lastBall = id
    battle.gen5CriticalCapture = critical or nil
    Runtime.emit("battle.ball_thrown", {
      battle = battle, ball = id, caught = caught, shakes = shakes, critical = critical,
    })
    local chained = battle.gen4BallChain and battle:gen4BallChain(caught, shakes, id)
    if not chained and battle.ballChain then
      battle:ballChain(battle:tossAnimFor(id), caught, shakes, id)
    end
    -- the critical capture's own wobble (effect 570 var 14)
    local anim = battle.gen4Ball
    if critical and anim and anim.player and anim.player.presetVars then
      anim.player.presetVars[14] = 1
    end
    if caught then
      battle:actNext(function()
        require("src.core.Sound").play(data, "Caught_Mon")
        ballOnCatch(foe.mon, id)
      end)
      battle:sayNext(line(data, U.BANK_STD, U.STD.gotcha, { foe.name or monName(game, foe.mon) },
        Strings("Gotcha!\n{VAR1} was caught!")))
      battle:act(function() battle:storeCaughtMon() end)
    else
      local key = ({ [0] = "brokeFree", "appeared", "almost", "soClose" })[math.max(0, math.min(3, shakes or 0))]
      battle:sayNext(line(data, U.BANK_STD, U.STD[key], nil, Strings("Oh, no!\nThe Pokémon broke free!")))
      battle:act(function() battle:executeAction(battle.enemy, battle.player, battle:enemyAction()) end)
      battle:act(function() battle:endOfTurn() end)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- MEDICINE: the party block, applied to one party member
-- ---------------------------------------------------------------------------

local function bitOf(v, b) return math.floor((v or 0) / 2 ^ b) % 2 == 1 end

-- the decoded block
function U.record(def)
  local b = Items.param(def)
  if not b then return nil end
  local r = { cures = {} }
  local CURE = { [0] = "SLP", "PSN", "BRN", "FRZ", "PAR" }
  for s = 0, 4 do if bitOf(b[0], s) then r.cures[#r.cures + 1] = CURE[s] end end
  r.confusion = bitOf(b[0], 5)
  r.attract = bitOf(b[0], 6)
  r.guardSpec = bitOf(b[0], 7)
  r.revive = bitOf(b[1], 0) and not bitOf(b[1], 1)
  r.heal = bitOf(b[5], 2)
  r.amount = b[13]
  r.ppOne, r.ppAll, r.ppAmount = bitOf(b[5], 0), bitOf(b[5], 1), b[14]
  r.stages = {
    attack = math.floor(b[1] / 16), defense = b[2] % 16, spatk = math.floor(b[2] / 16),
    spdef = b[3] % 16, speed = math.floor(b[3] / 16), accuracy = b[4] % 16,
  }
  r.crit = math.floor(b[4] / 16) % 4
  r.friendship = bitOf(b[6], 2) and { b[15], b[16], b[17] } or nil
  return r
end

local function hpAmount(r, mon)
  local max = maxHP(mon)
  if r.amount == 255 then return max end
  if r.amount == 254 then return math.max(1, math.floor(max / 2)) end
  if r.amount == 253 then return math.max(1, math.floor(max / 4)) end
  return r.amount or 0
end

local function battlerOf(battle, mon)
  for _, b in ipairs({ battle.player, battle.enemy }) do
    if b and b.mon == mon then return b end
  end
  if battle.activeBattlers then
    for _, b in battle:activeBattlers() do if b and b.mon == mon then return b end end
  end
  return nil
end

local function signed(v) return v >= 128 and v - 256 or v end

local function friendship(mon, steps)
  if not (mon and steps) then return end
  local now = math.floor(tonumber(mon.happiness) or 0)
  local d = signed(steps[now < 100 and 1 or (now < 200 and 2 or 3)] or 0)
  mon.happiness = math.max(0, math.min(255, now + d))
end

-- apply(game, battle, def, mon, moveIndex) -> true, line | false
function U.applyMedicine(game, battle, def, mon, moveIndex)
  local data = game.data
  local r = U.record(def)
  if not (r and mon) then return false end
  local name = monName(game, mon)
  local fainted = (tonumber(mon.hp) or 0) <= 0
  local b = battle and battlerOf(battle, mon)
  if r.revive then
    if not fainted then return false end
    mon.hp = r.amount == 254 and math.max(1, math.floor(maxHP(mon) / 2)) or maxHP(mon)
    mon.status = nil
    friendship(mon, r.friendship)
    return true, line(data, U.BANK_PARTY, U.PARTY.revive, { name }, Strings("{VAR1} recovered from\nfainting!"))
  end
  if fainted then return false end
  local out = {}
  local healed = 0
  if r.heal and mon.hp < maxHP(mon) then
    local before = mon.hp
    mon.hp = math.min(maxHP(mon), mon.hp + hpAmount(r, mon))
    healed = mon.hp - before
  end
  -- statuses
  local cured = {}
  if mon.status then
    local s = tostring(mon.status):upper()
    if s == "TOX" then s = "PSN" end
    for _, c in ipairs(r.cures) do
      if c == s then cured[#cured + 1] = s end
    end
    if #cured > 0 then
      mon.status = nil
      if b then b.toxicCounter = nil end
    end
  end
  local confusionCured = false
  if r.confusion and b and b.confusedTurns then
    b.confusedTurns = nil
    confusionCured = true
  end
  local attractCured = false
  if r.attract and b and b.infatuated then
    b.infatuated = nil
    attractCured = true
  end
  -- PP
  local ppMoved = false
  if r.ppOne or r.ppAll then
    local list = {}
    if r.ppOne then list[1] = (mon.moves or {})[moveIndex or 1]
    else for _, mv in ipairs(mon.moves or {}) do list[#list + 1] = mv end end
    for _, mv in ipairs(list) do
      local md = mv and data.moves and data.moves[mv.id]
      local max = md and tonumber(md.pp)
      if max then
        max = max + math.floor(max / 5) * (tonumber(mv.ppUps) or 0)
        if (tonumber(mv.pp) or 0) < max then
          mv.pp = (r.ppAmount == 127) and max or math.min(max, (tonumber(mv.pp) or 0) + (r.ppAmount or 0))
          ppMoved = true
        end
      end
    end
    -- the battler's own copy of the moves, when it has one
    if ppMoved and b and b.curMoves and b.curMoves ~= mon.moves then
      for i, mv in ipairs(b.curMoves) do
        local src = (mon.moves or {})[i]
        if src and mv.id == src.id then mv.pp = src.pp end
      end
    end
  end
  if healed == 0 and #cured == 0 and not confusionCured and not attractCured and not ppMoved then
    return false
  end
  friendship(mon, r.friendship)
  if healed > 0 then
    out[#out + 1] = line(data, U.BANK_PARTY, U.PARTY.hp, { name, count = healed },
      Strings("{VAR1}'s HP was restored\nby %d point(s).", healed))
  end
  if #r.cures >= 5 and #cured > 0 then
    out[#out + 1] = line(data, U.BANK_PARTY, U.PARTY.healthy, { name }, Strings("{VAR1} became healthy."))
  elseif #cured > 0 then
    local key = ({ SLP = "slp", PSN = "psn", BRN = "brn", FRZ = "frz", PAR = "par" })[cured[1]]
    out[#out + 1] = line(data, U.BANK_PARTY, U.PARTY[key], { name }, Strings("{VAR1} became healthy."))
  end
  if confusionCured and b then out[#out + 1] = T.set(battle, "snappedOut", b) end
  if attractCured and b then out[#out + 1] = T.set(battle, 339, b) end
  if ppMoved then out[#out + 1] = line(data, U.BANK_PARTY, U.PARTY.pp, nil, Strings("PP was restored.")) end
  return true, out
end

-- ---------------------------------------------------------------------------
-- BATTLE ITEMS: on the Pokemon choosing
-- ---------------------------------------------------------------------------

function U.applyBattleItem(battle, def, b)
  local r = U.record(def)
  if not (r and b and b.mon) then return false end
  local G5 = require("src.battle.Gen5MoveEffects")
  local msgs = {}
  b.stages = b.stages or {}
  for _, stat in ipairs({ "attack", "defense", "spatk", "spdef", "speed", "accuracy" }) do
    local n = r.stages[stat] or 0
    if n > 0 then
      local cur = b.stages[stat] or 0
      local applied = math.min(6, cur + n) - cur
      if applied > 0 then
        b.stages[stat] = cur + applied
        msgs[#msgs + 1] = T.stat(battle, b, stat, applied, n)
      end
    end
  end
  if r.crit > 0 and not b.focusEnergy then
    b.focusEnergy = true
    msgs[#msgs + 1] = T.set(battle, "pumped", b)
  end
  if r.guardSpec and battle.bw then
    local side = battle.bw.sides[b.isPlayer and 1 or 2]
    if side and (side.mist or 0) <= 0 then
      side.mist = 5
      G5.sync(battle)
      msgs[#msgs + 1] = T.team(battle, "mist", b)
    end
  end
  if #msgs == 0 then return false end
  return true, msgs
end

-- EMBARGO: no item from the bag on a Pokemon under it -- "Embargo's effect
-- prevents the item's use on X!" (bank 18 #105, the battle party list's)
function U.embargoLine(game, battle, mon)
  local b = battle and mon and battlerOf(battle, mon)
  if not (b and b.bwEmbargo) then return nil end
  local move = game.data.moves and game.data.moves[373]
  return line(game.data, 18, 105, { monName(game, mon), move and move.name or "Embargo" },
    Strings("{VAR2}'s effect prevents\nthe item's use on {VAR1}!"))
end

-- ---------------------------------------------------------------------------
-- THE BAG'S USE
-- ---------------------------------------------------------------------------

local function usedLine(game, def, id)
  return line(game.data, U.BANK_STD, U.STD.used, { playerName(game), itemName(def, id) },
    Strings("{VAR1} used the\n{VAR2}."))
end

-- the turn is spent: the bag closes, the lines print, the foe moves
local function spend(game, battle, id, list, msgs)
  consume(game, id)
  if list and list.close then list:close() end
  battle:itemUsed(msgs)
end

local function pickTarget(game, battle, id, def, list, showMessages)
  local r = U.record(def)
  local wantsMove = r and r.ppOne
  local function useOn(mon, moveIndex)
    local barred = U.embargoLine(game, battle, mon)
    if barred then return refuse(game, showMessages, barred) end
    local ok, out = U.applyMedicine(game, battle, def, mon, moveIndex)
    if not ok then
      refuse(game, showMessages, U.noEffect(game.data))
      return
    end
    pcall(function() require("src.core.Sound").play(game.data, "Heal_HP") end)
    local msgs = { usedLine(game, def, id) }
    for _, m in ipairs(out) do msgs[#msgs + 1] = m end
    spend(game, battle, id, list, msgs)
  end
  local opts = {
    pickOnly = true,
    onSwitch = function(mon)
      if not mon then return end
      if not wantsMove then return useOn(mon) end
      local rows = {}
      for mi, mv in ipairs(mon.moves or {}) do
        local md = game.data.moves[mv.id]
        rows[#rows + 1] = { value = mi, label = md and md.name or tostring(mv.id), right = ("%d"):format(mv.pp or 0) }
      end
      game.stack:push(require("src.ui.ListMenu").new(game, "Which move?", rows, {
        onChoose = function(row, l) l:close(); useOn(mon, row.value) end,
      }))
    end,
  }
  local screenId = "PartyMenu"
  if type(battle.gen4ItemTargetScreen) == "function" then
    local okS, sid = pcall(battle.gen4ItemTargetScreen, battle)
    if okS and sid then
      screenId = sid
      opts.mode, opts.itemId = "useItem", id
      if wantsMove then opts.onMove = function(mon, mi) useOn(mon, mi) end end
    end
  end
  require("src.ui.Screens").push(game, screenId, opts)
end

-- use(game, battle, id, list, showMessages): the whole of USE in a BW battle
function U.use(game, battle, id, list, showMessages)
  local data = game.data
  Items.ensure(data)
  U.installText(data)
  local def = data.items[id]
  local kind = Items.battleKind(def)
  if kind == "ball" then
    local why = U.ballRefusal(game, battle)
    if why then return refuse(game, showMessages, why) end
    consume(game, id)
    if list and list.close then list:close() end
    U.throw(battle, id)
    return
  end
  if kind == "escape" then
    if battle.kind ~= "wild" then return refuse(game, showMessages, U.juniper(data)) end
    consume(game, id)
    if list and list.close then list:close() end
    battle:say(usedLine(game, def, id))
    battle:say(line(data, U.BANK_STD, U.STD.gotAway, nil, Strings("Got away safely!")))
    battle.result = "run"
    battle.afterQueue = "finish"
    return
  end
  if kind == "battle" then
    local b = chooser(battle)
    local barred = b and U.embargoLine(game, battle, b.mon)
    if barred then return refuse(game, showMessages, barred) end
    local ok, msgs = U.applyBattleItem(battle, def, b)
    if not ok then return refuse(game, showMessages, U.noEffect(data)) end
    local out = { usedLine(game, def, id) }
    for _, m in ipairs(msgs) do out[#out + 1] = m end
    return spend(game, battle, id, list, out)
  end
  if kind == "medicine" then
    return pickTarget(game, battle, id, def, list, showMessages)
  end
  return refuse(game, showMessages, U.juniper(data))
end

-- ---------------------------------------------------------------------------
-- THE CATCH'S OTHER LINES, which BattleState:storeCaughtMon prints in the
-- engine's English: the Pokedex line and the PC line are translated at
-- startMessage like the rest (Gen5BattleText.PATTERNS); the nickname
-- question is a text box of its own, so its label is given BW's words.
-- ---------------------------------------------------------------------------

local function boxName(save)
  local n = save and save.currentBox or 1
  local names = save and (save.boxNames or save.gen5BoxNames)
  return (type(names) == "table" and names[n]) or ("Box " .. tostring(n))
end

function U.installText(data)
  if U._patterns ~= T.PATTERNS then
    U._patterns = T.PATTERNS
    table.insert(T.PATTERNS, 1, { (("^New POKéDEX data|will be added for|(.-)!$"):gsub("|", "\n")), function(battle, a)
      return line(battle.data, U.BANK_STD, U.STD.dexAdded, { a }, Strings("{VAR1}'s data was\nadded to the Pokédex."))
    end })
    table.insert(T.PATTERNS, 1, { (("^(.-) was|transferred to|(.-)!$"):gsub("|", "\n")), function(battle, a)
      return line(battle.data, U.BANK_DEX, U.DEX.transferred, { a, boxName(battle.game and battle.game.save) },
        Strings("{VAR1} was transferred to\n{VAR2} in someone's PC!"))
    end })
  end
  local text = data and data.text
  if type(text) == "table" and rawget(text, "_DoYouWantToNicknameText") == nil then
    local q = text[("TEXT_G5S_%04d_%05d"):format(U.BANK_DEX, U.DEX.nickname)]
    if type(q) == "string" and q ~= "" then
      rawset(text, "_DoYouWantToNicknameText", (q:gsub("{VAR1}", "{RAM}")))
    end
  end
end

return U
