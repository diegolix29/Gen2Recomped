-- src/battle/Gen4SwitchOut.lua
--
-- PLATINUM / HEARTGOLD / SOULSILVER: A POKEMON LEAVES ITS SLOT MID-MOVE.
--
-- Three move scripts take a battler off the field before the turn is over:
--
--   U-TURN      subscript_attack_then_switch_out (effect 228)
--   BATON PASS  subscript_baton_pass (effect 127)
--   ROAR / WHIRLWIND  subscript_force_switch_or_flee (effect 28, BtlCmd_TryWhirlwind)
--
-- The single-battle U-turn / Baton Pass already ride the shared switch path
-- (Gen5MoveEffects.switchOut), which refuses a double.  On the cartridge
-- nothing about these scripts is single-only: `TryReplaceFaintedMon
-- BTLSCR_ATTACKER, TRUE` (CanSwitchMon) asks whether the battler's OWN party
-- -- the trainer's whole team in a double, that trainer's own team when the
-- side is two trainers -- holds someone who is not already on the field,
-- sets the battler's bit in unk_13C, and BATTLE_SUBSCRIPT_SHOW_PARTY_LIST
-- (BtlCmd_ShowParty) opens the party list FOR THAT BATTLER: the player's
-- touch-screen list (the user's slot is the one being refilled), or the AI's
-- pick.  SwitchAndUpdateMon puts the choice into the very slot the user left,
-- with BATTLE_STATUS_BATON_PASS carrying what Baton Pass carries.
--
-- ROAR / WHIRLWIND in a trainer battle (BtlCmd_TryWhirlwind): count the
-- target's party members that can fight; with that count <= cntMax -- 2 in a
-- double whose side is one trainer's team (the target AND its partner are
-- assumed to be two of them, even a partner that has already fainted), 1
-- otherwise -- the move fails.  Otherwise WhirlwindCheck (attacker level >=
-- target level, or ((rand & 0xFF) * (Lu + Lt) >> 8) + 1 > Lt / 4) and a
-- uniformly random party member that is not the target's or its partner's
-- slot.  "{0} was dragged out!" is the only line.  In a WILD battle the same
-- WhirlwindCheck ends the battle (FadeOutBattle, no line); the AI-tag wild
-- double (BATTLE_TYPE_DOUBLES|MULTI|AI) refuses it outright.  Suction Cups and
-- Ingrain hold the target down with their own lines; a semi-invulnerable
-- target makes it fail.
--
-- The replaced battler is marked `g4Gone`: its row in this turn's order is
-- skipped (BattleState:executeAction), which is the cartridge's "a Pokemon
-- that was dragged out does not get the move its predecessor chose".

local Strings = require("src.core.Strings")

local M = {}

local FAILED = "But, it failed!"

local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end

local function isEgg(mon)
  return mon and (mon.isEgg or mon.egg) and true or false
end

local function able(mon)
  return mon and (mon.species or 0) ~= 0 and (mon.hp or 0) > 0 and not isEgg(mon)
end

local function posOf(battle, b)
  local POS = battle.POS or require("src.battle.BattleState").POS
  return tonumber(b.position) or (b.isPlayer and POS.PLAYER_LEFT or POS.OPPONENT_LEFT)
end

local function isDouble(battle)
  return battle.isDouble and battle:isDouble() or false
end

-- the party this battler's slot draws from (BattleSystem_GetParty)
local function partyOf(battle, b)
  if battle.benchFor then return battle:benchFor(b.isPlayer, posOf(battle, b)) or {} end
  if b.isPlayer then return (battle.game and battle.game.save and battle.game.save.party) or {} end
  return battle.enemyParty or {}
end
M.partyOf = partyOf

local function onField(battle)
  local taken = {}
  if battle.battlerAt then
    for p = 0, 3 do
      local x = battle:battlerAt(p)
      if x and x.mon then taken[x.mon] = true end
    end
  end
  for _, x in ipairs({ battle.player, battle.enemy }) do
    if x and x.mon then taken[x.mon] = true end
  end
  return taken
end

-- CanSwitchMon: who could take this battler's place -- {mon=, index=} in
-- party order
function M.bench(battle, b)
  local out, taken = {}, onField(battle)
  for i, mon in ipairs(partyOf(battle, b)) do
    if mon ~= b.mon and able(mon) and not taken[mon] then
      out[#out + 1] = { mon = mon, index = i }
    end
  end
  return out
end

-- CheckBlackOut for a double: the side is beaten only when nobody on the
-- field AND nobody on either bench can fight
function M.sideBeaten(battle, b)
  if battle.sideCanContinue then return not battle:sideCanContinue(b.isPlayer) end
  return #M.bench(battle, b) == 0 and not (b.mon and (b.mon.hp or 0) > 0)
end

-- -------------------------------------------------------------------------
-- placing the newcomer
-- -------------------------------------------------------------------------

local function clearTrapping(x)
  if not x then return end
  x.trappingTurns, x.trapMove, x.trapDamage = nil, nil, nil
end

local function applyCarry(battle, incoming, carry)
  if not (carry and incoming) then return end
  incoming.stages = carry.stages or incoming.stages
  incoming.confusedTurns = carry.confusedTurns
  incoming.substituteHP = carry.substituteHP
  incoming.leechSeeded = carry.leechSeeded
  incoming.perishTurns = carry.perishTurns
  if carry.g4 then
    require("src.battle.Gen4MoveEffects").applyBaton(battle, incoming, carry.g4)
  end
end

-- rewrite the send-out line switchPlayerInto queued since `mark` (the first
-- new line naming the newcomer) as `line`
local function rewriteSendOut(battle, mark, name, line)
  for _, item in ipairs(battle.queue) do
    if not mark[item] and type(item.text) == "string" and item.text:find(name, 1, true) then
      item.text = line
      return true
    end
  end
  return false
end

local function queueMark(battle)
  local mark = {}
  for _, item in ipairs(battle.queue or {}) do mark[item] = true end
  return mark
end

-- the foe's side: `entry` ({mon, index}) into `user`'s slot, through the
-- same steps as the trainer's own switch (BattleState aiSwitch)
local function placeFoe(battle, user, entry, how, carry)
  local BS = require("src.battle.BattleState")
  local pos = posOf(battle, user)
  local previous = user
  local oldName = previous.name
  local incoming = BS.makeBattler(battle.data, entry.mon, false)
  previous.g4Gone = true
  if battle.restoreMimicked then battle:restoreMimicked(previous) end
  if battle.placeBattler and battle.sides then
    battle:placeBattler(pos, incoming)
  else
    battle.enemy = incoming
  end
  if pos == BS.POS.OPPONENT_LEFT and partyOf(battle, incoming) == battle.enemyParty then
    battle.enemyIndex = entry.index
  end
  for _, foe in ipairs(battle.foesOf and battle:foesOf(incoming) or { battle.player }) do clearTrapping(foe) end
  if battle.syncSides then battle:syncSides() end
  applyCarry(battle, incoming, carry)
  require("src.mods.Runtime").emit("battle.battler_switched", {
    battle = battle, side = battle.sides and battle.sides[2], battler = incoming,
    previous = previous,
  })
  if battle.abilitySwitchOut then battle:abilitySwitchOut(previous) end
  if BS.markSeen then BS.markSeen(battle.game, incoming.mon.species, incoming.mon) end
  local label = battle.trainerLabel_ and battle:trainerLabel_() or "?"
  if how == "dragged" then
    battle:sayNext(Strings("%s was\ndragged out!", displayName(incoming)))
  else
    battle:sayNext(Strings("%s with-\ndrew %s!", label, oldName))
    battle:sayNext(Strings("%s sent\nout %s!", label, incoming.name))
  end
  require("src.battle.HeldItems").onEntry(battle, incoming)
  battle:actNext(function() battle:abilitySwitchIn(incoming) end)
  return incoming
end

-- the player's side: through BattleState:switchPlayerInto (the slot's own
-- send-out, Baton Pass carry, grow-in, hazards); an AI partner's slot keeps
-- the partner's flag and name
local function placeOwn(battle, user, mon, how, carry)
  local pos = posOf(battle, user)
  if carry then
    user.batonPass = {
      stages = carry.stages, confusedTurns = carry.confusedTurns,
      substituteHP = carry.substituteHP, leechSeeded = carry.leechSeeded,
      perishTurns = carry.perishTurns,
    }
    user.g4Baton = carry.g4
  end
  local mark = queueMark(battle)
  local incoming = battle:switchPlayerInto(pos, mon)
  if not incoming then return nil end
  user.g4Gone = true
  if user.ally then
    incoming.ally = true
    local name = battle.ally and battle.ally.name or ""
    rewriteSendOut(battle, mark, incoming.name, Strings("%s sent\nout %s!", name, incoming.name))
  end
  if how == "dragged" then
    rewriteSendOut(battle, mark, incoming.name, Strings("%s was\ndragged out!", displayName(incoming)))
  end
  return incoming
end

-- -------------------------------------------------------------------------
-- U-TURN / BATON PASS IN A DOUBLE
-- -------------------------------------------------------------------------

local function refusal(battle, mon, user)
  if not mon then return "" end
  if isEgg(mon) then return Strings("An EGG can't\nbattle!") end
  if (mon.hp or 0) <= 0 then return Strings("There's no will\nto fight!") end
  if mon == user.mon or onField(battle)[mon] then
    return Strings("%s is already\nin battle!", mon.nickname or mon.name or "")
  end
  return nil
end

-- the player's party list for `user`'s slot (BtlCmd_ShowParty, no cancel);
-- a member that cannot go says why and the list opens again
local function askPlayer(battle, user, bench, carry)
  local done = false
  battle:uiNext(function()
    local Gen4Battle = require("src.battle.Gen4Battle")
    return battle:buildScreen(Gen4Battle.partyScreenId and Gen4Battle.partyScreenId(battle) or "PartyMenu", {
      battle = battle, forceSwitch = true,
      onSwitch = function(mon)
        if done then return end
        battle.nextInsert = 0
        local why = refusal(battle, mon, user)
        if why then
          if why ~= "" then battle:sayNext(why) end
          return
        end
        done = true
        placeOwn(battle, user, mon, "switch", carry)
      end,
    })
  end)
  battle:actNext(function()
    if not done then
      battle.nextInsert = 0
      askPlayer(battle, user, M.bench(battle, user), carry)
    end
  end)
end

-- the user leaves its slot; `carry` (Baton Pass) goes to the newcomer.
-- false when nobody can come in.
function M.switchOut(battle, user, carry)
  local bench = M.bench(battle, user)
  if #bench == 0 then return false end
  if user.isPlayer and not user.ally then
    if battle.bwAutoSwitch or not (battle.game and battle.game.stack) then
      placeOwn(battle, user, bench[1].mon, "switch", carry)
      return true
    end
    askPlayer(battle, user, bench, carry)
    return true
  end
  -- the AI (the foe, or the player's AI partner) takes the first able one in
  -- party order -- the singles' rule (Gen5MoveEffects.switchOut)
  if user.isPlayer then
    placeOwn(battle, user, bench[1].mon, "switch", carry)
  else
    placeFoe(battle, user, bench[1], "switch", carry)
  end
  return true
end

-- the Baton Pass carry: the switch path's five plus Sinnoh's own
-- (Gen4MoveEffects.batonCarry)
function M.batonCarry(user)
  return {
    stages = user.stages, confusedTurns = user.confusedTurns,
    substituteHP = user.substituteHP, leechSeeded = user.leechSeeded,
    perishTurns = user.perishTurns,
    g4 = require("src.battle.Gen4MoveEffects").batonCarry(user),
  }
end

-- -------------------------------------------------------------------------
-- ROAR / WHIRLWIND (subscript_force_switch_or_flee, BtlCmd_TryWhirlwind)
-- -------------------------------------------------------------------------

-- WhirlwindCheck
local function whirlwindCheck(battle, user, target)
  local lu, lt = user.mon.level or 1, target.mon.level or 1
  if lu >= lt then return true end
  local r = battle.rng(0, 255)
  local level = math.floor(r * (lu + lt) / 256) + 1
  return level > math.floor(lt / 4)
end
M.whirlwindCheck = whirlwindCheck

-- is this effect-28 move one Gen 4 runs here? (Teleport shares the record)
function M.isForceSwitch(move)
  if not move then return false end
  local e = tonumber(move.gen4Effect)
  if e then return e == 28 end
  return move.id == 46 or move.id == 18
end

function M.forceOut(ctx)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  local function fail(line)
    if battle.cancelMoveAnim then battle:cancelMoveAnim() end
    ctx.say(line or Strings(FAILED))
  end
  if not (target and target.mon and (target.mon.hp or 0) > 0) then return fail() end
  if target.invulnerable then return fail() end
  if require("src.battle.Abilities").refusesPhasing(target) then
    return fail(Strings("%s anchors\nitself with SUCTION CUPS!", displayName(target)))
  end
  if target.ingrained then
    return fail(Strings("%s anchored\nitself with its\nroots!", displayName(target)))
  end
  local double = isDouble(battle)
  if battle.kind == "wild" then
    -- BATTLE_TYPE_DOUBLES|MULTI|AI: the AI-partner wild double
    if double and battle.ally then return fail() end
    if not whirlwindCheck(battle, user, target) then return fail() end
    -- _067: FadeOutBattle, BATTLE_RESULT_PLAYER_FLED -- no line
    battle.result = "run"
    battle.afterQueue = "finish"
    return
  end
  local party = partyOf(battle, target)
  local separate = (target.isPlayer and battle.ally ~= nil) or (not target.isPlayer and battle.enemyPartyB ~= nil)
  local cntMax = (double and not separate) and 2 or 1
  local cnt = 0
  for _, mon in ipairs(party) do if able(mon) then cnt = cnt + 1 end end
  if cnt <= cntMax then return fail() end
  if not whirlwindCheck(battle, user, target) then return fail() end
  -- monIndexA / monIndexB: the target's slot and, sharing the party, its
  -- partner's; the draw is uniform over everyone else who can fight
  local excluded = { [target.mon] = true }
  if double and not separate then
    local partner = battle.partnerOf and battle:partnerOf(target)
    if partner and partner.mon then excluded[partner.mon] = true end
  end
  local pool = {}
  for i, mon in ipairs(party) do
    if able(mon) and not excluded[mon] then pool[#pool + 1] = { mon = mon, index = i } end
  end
  if #pool == 0 then return fail() end
  local pick = pool[battle.rng(1, #pool)]
  if target.isPlayer then
    placeOwn(battle, target, pick.mon, "dragged")
  else
    placeFoe(battle, target, pick, "dragged")
  end
end

return M
