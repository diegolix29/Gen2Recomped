-- PLATINUM'S BATTLE TOWER AND BATTLE POINTS: the script commands
-- (unk_020494DC.c's ScrCmd_*BattleTower* and the BP commands, overlay104's
-- FrontierScrCmd_CallBattleTowerFunction for the battle room's half) over
-- src/pokemon/Gen4BattleTower.lua.
--
-- The struct the cartridge keeps at fieldSystem->battleTower lives at
-- game.gen4BattleTower: made by `initbattletower`, dropped by
-- `freebattletower`, read by every `callbattletowerfunction`.
--
-- THE BATTLE ROOM RUNS ON THE FIELD MAP. On the cartridge the elevator's
-- `LaunchBattleFrontierScene FRONTIER_SCENE_TOWER_CORRIDOR` hands over to
-- overlay104's own scene and script engine, and Platinum's field corridor and
-- battle room scripts are Diamond and Pearl's, left in. The battle room's is
-- complete -- the opponents, the heal, Rest and Retire, Palmer -- so the scene
-- is run as that map: the launch warps into the battle room and the room's
-- own OnFrame script takes over. The frontier script adds one thing the
-- field one does not have, the Battle Points for seven wins, and that is
-- added behind BT_FUNC_UPDATE_GAME_RECORDS_AND_JOURNAL (`g4_bt_reward`).
-- The corridor walk (a scene with no field script) is not shown.

local Commands = require("src.script.Commands")
-- loaded from the end of Gen4Commands, so that module is asked for lazily
local function G4() return require("src.script.Gen4Commands") end
local BT = require("src.pokemon.Gen4BattleTower")
local Logger = require("src.core.Logger")

local M = {}

local function valueOf(ctx, n) return G4().valueOf(ctx, n) end
local function store(ctx, dest, value)
  dest = tonumber(dest)
  if dest and dest >= 0x4000 then G4().setVar(ctx.save, dest, math.floor(tonumber(value) or 0) % 65536) end
end
local function tower(ctx) return ctx.game and ctx.game.gen4BattleTower end

M.BATTLE_ROOM_HEADER, M.LOBBY_HEADER = 330, 326
M.MULTI_BATTLE_ROOM_HEADER = 331
M.SCENE_TOWER_CORRIDOR, M.SCENE_TOWER_MULTI_CORRIDOR = 5, 6

-- `initbattletower <resume> <mode>`
function Commands.g4_bt_init(ctx, resume, mode)
  ctx.game.gen4BattleTower = BT.init(ctx.save, valueOf(ctx, resume), valueOf(ctx, mode))
end
-- `setbattletowernull` / `freebattletower`
function Commands.g4_bt_null(ctx) ctx.game.gen4BattleTower = nil end
function Commands.g4_bt_free(ctx) ctx.game.gen4BattleTower = nil end

-- BT_FUNC_UNK_30: the party menu, choosing the team (sub_0204A358 ->
-- PARTY_MENU_MODE_BATTLE_TOWER, level cap 100)
function Commands.g4_bt_select(ctx)
  local bt = tower(ctx)
  if not bt then return end
  bt.chosen = nil
  local runner = ctx.runner
  local PM = require("src.ui.Gen4PartyMenu")
  ctx.game.stack:push(PM.new(ctx.game, { select = {
    count = bt.size, maxLevel = 100, banlist = true, unique = true,
    onDone = function(slots) bt.chosen = slots or false; runner:resume() end,
  } }))
  runner:yield()
end

-- BT_FUNC_UNK_42 / FrontierScrCmd_BattleTower_StartBattle: the chosen team
-- at level 50 (copies -- the party itself is never touched) against the
-- opponent BT_FUNC_SET_OPPONENT_TEAMS made
function Commands.g4_bt_battle(ctx)
  local bt = tower(ctx)
  local game = ctx.game
  if not (bt and bt.opponent and #bt.opponent.party > 0) then
    Logger.warn("gen4 battle tower: no opponent to battle -- counted as a loss")
    ctx.lastBattleResult = "lose"
    return
  end
  local BattleState = require("src.battle.BattleState")
  local team = M.playerTeam(game, bt)
  local multi = BT.isMulti(bt.mode)
  local key = M.registerTrainer(game, "GEN4_BATTLE_TOWER", bt.opponent, bt.mode == BT.DOUBLE or multi)
  local keyB = multi and bt.opponents and bt.opponents[1]
               and M.registerTrainer(game, "GEN4_BATTLE_TOWER_B", bt.opponents[1], true) or nil
  -- BATTLE_TYPE_FRONTIER_WITH_AI_PARTNER: the Salon partner's team
  -- (partnersDataDTO[partnerID]) stands at BATTLER_PLAYER_2
  local ally
  local partner = multi and BT.partner(bt)
  if partner and #partner.party > 0 then
    local pkey = M.registerTrainer(game, "GEN4_BATTLE_TOWER_PARTNER", partner, true)
    local ok, party = pcall(BattleState.buildTrainerParty, game, pkey, 1, game.data.trainers[pkey].parties[1])
    if ok and type(party) == "table" and party[1] then
      ally = { party = party, name = game.data.trainers[pkey].name, trainer = pkey,
               pic = game.data.trainers[pkey].pic }
    end
  end
  local real = ctx.save.party
  require("src.pokemon.PartyAside").hold(ctx.save, real)  -- in the save too (PartyAside)
  ctx.save.party = team
  local ok, battle = pcall(BattleState.newTrainer, game, key, 1)
  ctx.save.party = real
  require("src.pokemon.PartyAside").release(ctx.save)
  if not ok or not battle then
    Logger.warn("gen4 battle tower: could not build the battle: %s", tostring(battle))
    ctx.lastBattleResult = "lose"
    return
  end
  battle.battleTower = true
  battle.canLose = true
  battle.noExp = true
  if bt.mode == BT.DOUBLE or multi then
    battle.double = true
    if ally then battle:setAlly(ally) end
    if keyB then battle:addOpponentTrainer(keyB) end
    if battle.sendOutSecondPair then battle:sendOutSecondPair() end
  end
  local runner = ctx.runner
  -- the battle reads the party it was given; for its length the save's party
  -- IS the copies, so experience, PP and fainting land on them alone
  require("src.pokemon.PartyAside").hold(ctx.save, real)  -- in the save too (PartyAside)
  ctx.save.party = team
  battle.onFinish = function(result)
    ctx.save.party = real
    require("src.pokemon.PartyAside").release(ctx.save)
    ctx.lastBattleResult = result
    ctx.lastBattleCanLose = true
    runner:resume()
  end
  if ctx.overworld and ctx.overworld.pushBattle then ctx.overworld:pushBattle(battle)
  else game.stack:push(battle) end
  runner:yield()
end

-- the chosen members, as level-50 copies (FieldBattleDTO_NewBattleTower:
-- above 50 the experience is set to level 50's and the stats recalculated)
function M.playerTeam(game, bt)
  local data, out = game.data, {}
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  for i = 0, bt.size - 1 do
    local src = (game.save.party or {})[(bt.slots[i] or 0) + 1]
    if src then
      local mon = M.copy(src)
      if (tonumber(mon.level) or 1) > 50 then
        local def = require("src.pokemon.Gen4Forms").definition(data, mon)
        mon.level = 50
        if def then
          mon.exp = require("src.pokemon.Growth").expForLevel(def.growthRate, 50)
          mon.stats = Stats.calc(def, 50, mon.ivs or mon.dvs, mon.statExp, mon.evs, mon.nature)
        end
      end
      mon.hp = mon.stats and mon.stats.hp or mon.hp
      mon.status = nil
      for _, m in ipairs(mon.moves or {}) do
        local def = data.moves and data.moves[m.id]
        if def then m.pp = def.pp end
      end
      out[#out + 1] = mon
    end
  end
  local _ = Pokemon
  return out
end

function M.copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = M.copy(v) end
  return c
end

-- a frontier trainer (an opponent or the Salon partner) as a trainer record
-- the battle builder reads, under `key` (at `level`: 50 unless the facility
-- sets its own, as the Battle Hall does)
function M.registerTrainer(game, key, who, double, level)
  local name = M.trainerName(game, who.id)
  game.data.trainers[key] = {
    id = key, index = who.class, class = who.class, name = name,
    className = M.className(game, who.class), source = "ROM:pl_btdtr",
    parties = { M.prebuilt(M.opponentMons(game, who.party, level), level) }, partyNames = { name }, baseMoney = 0,
    doubleBattle = double or nil, pic = M.trainerPic(game, who.class),
  }
  return key
end

-- FrontierPokemon_InitPokemon at setLevel 120: level 50 (or `level`), the
-- set's moves, item, IVs, EVs, personality (so nature and ability)
function M.opponentMons(game, party, level)
  level = level or 50
  local data, out = game.data, {}
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  local order = data.constants and data.constants.natureOrder
  for i, p in ipairs(party or {}) do
    local ok, mon = pcall(Pokemon.new, data, p.species, level, nil, p.form)
    if ok and mon then
      mon.personality = p.personality
      mon.otId = p.otId
      mon.shiny = false
      mon.item = (p.item ~= 0) and p.item or nil
      mon.ivs = { hp = p.ivs, attack = p.ivs, defense = p.ivs, speed = p.ivs, spatk = p.ivs, spdef = p.ivs }
      mon.evs = { hp = p.evs[1], attack = p.evs[2], defense = p.evs[3], speed = p.evs[4],
                  spatk = p.evs[5], spdef = p.evs[6] }
      mon.nature = order and order[(p.personality % 25) + 1] or mon.nature
      mon.abilitySlot = p.abilityBit + 1
      mon.happiness = p.friendship
      local def = require("src.pokemon.Gen4Forms").definition(data, mon)
      if def then
        if not (def.abilities and def.abilities[2]) then mon.abilitySlot = 1 end
        mon.stats = Stats.calc(def, level, mon.ivs, nil, mon.evs, mon.nature)
        mon.hp = mon.stats.hp
      end
      mon.moves = {}
      for _, id in ipairs(p.moves) do
        if id ~= 0 then
          local md = data.moves and data.moves[id]
          mon.moves[#mon.moves + 1] = { id = id, pp = md and md.pp or 0 }
        end
      end
      out[#out + 1] = mon
    end
    local _ = i
  end
  return out
end

-- party slots the battle builder hands over whole (BattleState's
-- buildTrainerParty `prebuilt`)
function M.prebuilt(mons, level)
  local slots = {}
  for i, mon in ipairs(mons) do
    slots[i] = { species = mon.species, level = level or 50, form = mon.form, prebuilt = mon }
  end
  return slots
end

function M.trainerName(game, id)
  local T = require("src.import.Gen4Text")
  return T.resolve(game.data, BT.TRAINER_NAMES, id, game) or "?"
end

function M.className(game, class)
  for _, rec in pairs(game.data.trainers or {}) do
    if type(rec) == "table" and tonumber(rec.class) == class and rec.className then return rec.className end
  end
  return nil
end

function M.trainerPic(game, class)
  for _, rec in pairs(game.data.trainers or {}) do
    if type(rec) == "table" and tonumber(rec.class) == class and rec.pic then return rec.pic end
  end
  return nil
end

-- `printbattletowerintromessage <n>` / FrontierScrCmd_85: the opponent's
-- line, bank 614's entry trainer * 3
function Commands.g4_bt_intro(ctx, n)
  local bt = tower(ctx)
  local o = bt and ((bt.opponents and bt.opponents[tonumber(n) or 0]) or bt.opponent)
  if not o then return end
  local Gen4Text = require("src.import.Gen4Text")
  return Commands.show_text(ctx, Gen4Text.label(BT.TRAINER_MESSAGES, o.id * 3))
end

-- `getbattletowerpartnerspeciesandmove <partner> <mon> <speciesVar> <moveVar>`
-- (ScrCmd_GetBattleTowerPartnerSpeciesAndMove): what the Salon partner
-- offers -- partnersDataDTO[partner].pokemon[mon]'s species and first move
function Commands.g4_bt_partner_species_move(ctx, partner, mon, speciesDest, moveDest)
  local bt = tower(ctx)
  local team = bt and bt.partners and bt.partners[math.floor(valueOf(ctx, partner) or 0)]
  local p = team and team.party[math.floor(valueOf(ctx, mon) or 0) + 1]
  store(ctx, speciesDest, p and p.species or 0)
  store(ctx, moveDest, p and p.moves[1] or 0)
end

-- after BT_FUNC_UPDATE_GAME_RECORDS_AND_JOURNAL, the frontier battle room's
-- _0273 / _0227: "cleared your seventh match" (or the Tycoon's line), then
-- _0330: BT_FUNC_UNK_46, "<player> received <n> BP!", SEQ_PL_POINTGET3
function Commands.g4_bt_reward(ctx)
  local bt = tower(ctx)
  if not bt or bt.mode == BT.MODE_5 then return end
  local Gen4Text = require("src.import.Gen4Text")
  Commands.show_text(ctx, Gen4Text.label(BT.BATTLE_ROOM_TEXT, bt.beatPalmer ~= 0 and 20 or 19))
  local bp = BT.reward(bt)
  Commands.g4_buffer(ctx, 0, "player")
  local game = ctx.game
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[2] = tostring(bp)
  Commands.show_text(ctx, Gen4Text.label(BT.BATTLE_ROOM_TEXT, 21))
  Commands.play_once(ctx, 1221)   -- SEQ_PL_POINTGET3
end

-- `messageseenbanlistspecies <first> <count> ...`: the line that names the
-- banned species the player has SEEN, `first + how many`
function Commands.g4_bt_banlist_message(ctx, first, count)
  local game = ctx.game
  local seen = (ctx.save.pokedex and ctx.save.pokedex.seen) or {}
  local names = { tostring(valueOf(ctx, count)) }
  for _, sp in ipairs({ 150, 151, 249, 250, 251, 382, 383, 384, 385, 386, 483, 484, 487, 489, 490, 491, 492, 493 }) do
    if seen[sp] then
      local def = game.data.pokemon and game.data.pokemon[sp]
      names[#names + 1] = def and def.name or "?"
    end
  end
  game.stringBuffers = {}
  for i, v in ipairs(names) do game.stringBuffers[i] = v end
  return Commands.g4_message_bank(ctx, 304, (tonumber(first) or 91) + #names - 1)
end

-- `launchbattlefrontierscene <scene>`: the tower corridor is the field
-- battle room (see the top of this file); the elevator's own warp back to the
-- lobby is the room script's job, so this one ends here
function Commands.g4_frontier_scene(ctx, scene)
  scene = tonumber(valueOf(ctx, scene)) or -1
  -- THE SCENES THE FRONTIER ENGINE RUNS (src/ui/Gen4FrontierScene.lua): the
  -- field script waits here until the scene leaves the frontier
  local Scene = require("src.ui.Gen4FrontierScene")
  if Scene.SCENES[scene] then
    local runner = ctx.runner
    ctx.game.stack:push(Scene.new(ctx.game, { scene = scene, onExit = function() runner:resume() end }))
    runner:yield()
    return
  end
  if scene == M.SCENE_TOWER_MULTI_CORRIDOR then
    -- the field multi corridor's `Warp MAP_HEADER_BATTLE_TOWER_MULTI_BATTLE_ROOM,
    -- 7, 5, DIR_NORTH`; the room's OnFrame (Enter, or Continue after a Rest)
    -- runs the pairs
    Commands.g4_warp(ctx, M.MULTI_BATTLE_ROOM_HEADER, 7, 5, 0)
    return "end"
  end
  if scene ~= M.SCENE_TOWER_CORRIDOR then
    Logger.warn("gen4 frontier: scene %d is not ported -- the script carries on", scene)
    return
  end
  -- the field corridor's own `Warp MAP_HEADER_BATTLE_TOWER_BATTLE_ROOM, 7, 6, DIR_NORTH`
  Commands.g4_warp(ctx, M.BATTLE_ROOM_HEADER, 7, 6, 0)
  return "end"
end

-- ScrCmd_1DF: Teala's trophies (sub_0206BDBC) -- 1 bronze, 2 silver, 3 gold,
-- 4 no room in the Underground PC, 0 nothing
function Commands.g4_bt_trophy(ctx, dest)
  local r = BT.record(ctx.save)
  local best = BT.stat(r, 0)
  local function F(b, op) return BT.flag(r, b, op) end
  local UG = require("src.world.Gen4Underground")
  local result = 0
  if best >= 20 then
    local b13, b0, b1, b14, b2, b3 = F(13, 0), F(0, 0), F(1, 0), F(14, 0), F(2, 0), F(3, 0)
    if not (b13 and b0 and b1) then
      local room = UG.roomInGoodsPC(ctx.save)
      if not b13 then
        if room then F(13, 1); result = 1 else if not b14 then F(14, 1) end; result = 4 end
      elseif best >= 50 then
        if not b0 then
          if room then F(0, 1); result = 2 else if not b2 then F(2, 1) end; result = 4 end
        elseif best >= 100 then
          if room then F(1, 1); result = 3 else if not b3 then F(3, 1) end; result = 4 end
        end
      end
    end
  end
  store(ctx, dest, result)
end

-- ScrCmd_1E0 (sub_0206BF04): whether Teala stands in the lobby
function Commands.g4_bt_teala(ctx, dest)
  local r = BT.record(ctx.save)
  local best = BT.stat(r, 0)
  local function F(b) return BT.flag(r, b, 0) end
  local v = 0
  if best >= 20 and not (F(13) and F(0) and F(1)) then
    if not F(13) then v = F(14) and 4 or 1
    elseif best >= 50 then
      if not F(0) then v = F(2) and 5 or 2
      elseif best >= 100 and not F(1) then v = F(3) and 6 or 3 end
    end
  end
  store(ctx, dest, v)
end

-- ------------------------------------------------------------ the switch --

local FN = BT.FN

function Commands.g4_bt_call(ctx, fn, arg, dest)
  fn = tonumber(fn) or 0
  local a = valueOf(ctx, arg)
  local bt = tower(ctx)
  local save = ctx.save
  local v
  if fn == FN.CHECK_IS_NULL then v = bt and 0 or 1
  elseif fn == FN.CHECK_ENOUGH_VALID_POKEMON then
    v = BT.enoughValid(save, (a ~= 0 and a) or (bt and bt.size) or 3) and 1 or 0
  elseif fn == FN.RESET_SYSTEM then
    -- OS_ResetSystem: the Rest save ends at the title screen
    if ctx.game.returnToTitle then ctx.game:returnToTitle() end
    return "end"
  elseif fn == FN.UNK_03 then BT.record(save).tower = {}
  elseif fn == FN.UNK_04 then v = BT.record(save).tower.inProgress and 1 or 0
  elseif fn == FN.SET_COMMUNICATION_CLUB_ACCESSIBLE then M.setSpecialLocation(ctx)
  elseif fn == FN.CLEAR_COMMUNICATION_CLUB_ACCESSIBLE then save.gen4SpecialLocation = nil
  elseif fn == FN.UNK_08 then v = BT.currentStreak(save, a)
  elseif fn == FN.UNK_09 or fn == FN.UNK_10 or fn == FN.UNK_12 or fn == FN.UNK_15 then v = 0   -- Wi-Fi rank
  elseif fn == FN.UNK_11 or fn == FN.UNK_16 then v = nil                                     -- Wi-Fi upload
  elseif fn == FN.UNK_14 then v = BT.forfeitUnsaved(save)
  elseif not bt then
    Logger.warn("gen4 battle tower: function %d with no tower struct", fn)
    v = 0
  elseif fn == FN.UNK_30 then
    return Commands.g4_bt_select(ctx)
  elseif fn == FN.UNK_31 then
    if bt.chosen then
      -- sub_0204A378: the slots, and their species and items (unk_2E /
      -- unk_36), which the Salon partners' teams then keep clear of
      bt.chosenSpecies, bt.chosenItems = {}, {}
      local party = save.party or {}
      for i, slot in ipairs(bt.chosen) do
        bt.slots[i - 1] = slot - 1
        local mon = party[slot] or {}
        bt.chosenSpecies[i], bt.chosenItems[i] = tonumber(mon.species) or 0, tonumber(mon.item) or 0
      end
      v = 1
    else v = 0 end
  elseif fn == FN.CHECK_DUPLICATE_SPECIES_AND_HELD_ITEMS then v = BT.checkDuplicates(bt)
  elseif fn == FN.GET_NEXT_OPPONENT_NUM then v = bt.next
  elseif fn == FN.UNK_34 then v = BT.advance(bt)
  elseif fn == FN.HAS_DEFEATED_SEVEN_TRAINERS then v = BT.hasDefeatedSeven(bt) and 1 or 0
  elseif fn == FN.UNK_36 then v = BT.streak(bt)
  elseif fn == FN.UPDATE_GAME_RECORDS then BT.endStreak(bt)
  elseif fn == FN.UPDATE_GAME_RECORDS_AND_JOURNAL then BT.winRound(bt)
  elseif fn == FN.UNK_39 then BT.suspend(bt)
  elseif fn == FN.SET_OPPONENT_TEAMS then BT.setOpponent(bt, ctx.game.data)
  elseif fn == FN.GET_OPPONENT_OBJECT_ID then v = BT.opponentGfx(bt, a)
  elseif fn == FN.UNK_42 then return Commands.g4_bt_battle(ctx)
  elseif fn == FN.GET_CHALLENGE_MODE then v = bt.mode
  elseif fn == FN.SET_BEAT_PALMER then bt.beatPalmer = a
  elseif fn == FN.GET_BEAT_PALMER then v = bt.beatPalmer
  elseif fn == FN.UNK_46 then v = BT.reward(bt)
  elseif fn == FN.UNK_47 then
    local cur = BT.currentStreak(save, bt.mode)
    v = (cur >= 50 and not BT.flag(bt.rec, cur >= 100 and 1 or 0, 0)) and 1 or 0
  elseif fn == FN.UNK_48 then v = (bt.mode == BT.SINGLE) and BT.giveRibbon(bt, BT.ribbonFor(bt)) or 0
  elseif fn == FN.UNK_49 then v = (bt.mode ~= BT.SINGLE) and BT.giveRibbon(bt, BT.ribbonFor(bt)) or 0
  elseif fn == FN.SET_PARTNER_ID then bt.partnerID = a
  elseif fn == FN.GET_PARTNER_ID then v = bt.partnerID
  elseif fn == FN.UNK_52 then BT.chooseTrainers(bt)
  elseif fn == FN.GET_SLOT_INDEX then v = bt.slots[a] or 0xFF
  elseif fn == FN.UNK_54 then v = 0
  elseif fn == FN.GET_PARTNER_PARAM then v = BT.partnerParam(bt, a)
  elseif fn == FN.UNK_56 then BT.partnerTeams(bt, ctx.game.data)
  elseif fn == FN.UNK_58 or fn == FN.UNK_59 then v = nil
  elseif fn == FN.UNK_57 then v = BT.seedFromRecord(bt)
  else
    Logger.warn("gen4 battle tower: function %d is not ported", fn)
    v = 0
  end
  if v ~= nil then store(ctx, dest, v) end
end

-- BattleTower_SetCommunicationClubAccessible: where a save made inside the
-- challenge puts the player back (FieldTask_LoadSavedGameMap)
function M.setSpecialLocation(ctx)
  local ow = ctx.overworld
  local p = ow and ow.player
  if not (ow and ow.map and p) then return end
  ctx.save.gen4SpecialLocation = { map = ow.map.id, x = p.cellX, y = p.cellY }
end

-- ...and on Continue: the flag is spent, the player stands there
function M.applySpecialLocation(save)
  local loc = type(save) == "table" and save.gen4SpecialLocation
  if not (loc and loc.map and save.player) then return false end
  save.player.map, save.player.x, save.player.y = loc.map, loc.x, loc.y
  save.player.facing = save.player.facing or "up"
  save.gen4SpecialLocation = nil
  return true
end

-- ------------------------------------------------------- Battle Points --

function Commands.g4_bp_window(ctx, which, left, top)
  local ow = ctx.overworld
  if not ow then return end
  if which == "hide" then ow.gen4CoinWindow = nil return end
  local MW = require("src.ui.Gen4MoneyWindow")
  if which == "show" then
    ow.gen4CoinWindow = MW.bpPanelFor(ctx.game, valueOf(ctx, left), valueOf(ctx, top))
  elseif ow.gen4CoinWindow then
    ow.gen4CoinWindow = MW.bpPanelFor(ctx.game, ow.gen4CoinWindow.left, ow.gen4CoinWindow.top)
  end
end
function Commands.g4_get_bp(ctx, dest) store(ctx, dest, BT.bp(ctx.save)) end
function Commands.g4_give_bp(ctx, n) BT.addBP(ctx.save, valueOf(ctx, n)) end
function Commands.g4_remove_bp(ctx, n) BT.addBP(ctx.save, -valueOf(ctx, n)) end
function Commands.g4_check_bp(ctx, n, dest)
  store(ctx, dest, BT.bp(ctx.save) >= valueOf(ctx, n) and 1 or 0)
end

-- ScrCmd_GetExchangeServiceCornerItemAndCost: prizeList, items from row 0
-- and TMs from row 26 (FRONTIER_MART_TMS_START_ID). A plain list, one-based:
-- an `[0] =` / `[26] =` constructor lets the positional rows after each run
-- over the keyed one.
M.EXCHANGE = {
  { 46, 1 }, { 49, 1 }, { 47, 1 }, { 52, 1 }, { 48, 1 }, { 45, 1 }, { 289, 16 }, { 290, 16 },
  { 291, 16 }, { 292, 16 }, { 293, 16 }, { 294, 16 }, { 272, 16 }, { 273, 16 }, { 214, 32 },
  { 271, 32 }, { 213, 48 }, { 220, 48 }, { 230, 48 }, { 232, 48 }, { 266, 48 }, { 275, 48 },
  { 287, 48 }, { 326, 48 }, { 327, 48 }, { 50, 48 },
  { 333, 32 }, { 400, 32 }, { 388, 32 }, { 372, 32 }, { 367, 40 }, { 358, 40 }, { 335, 48 },
  { 331, 48 }, { 408, 64 }, { 357, 64 }, { 380, 64 }, { 363, 80 }, { 386, 80 }, { 398, 80 }, { 353, 80 },
}
M.EXCHANGE_TMS = 26
function Commands.g4_exchange_item(ctx, mart, prize, itemDest, costDest)
  local start = (valueOf(ctx, mart) == 1) and M.EXCHANGE_TMS or 0
  local row = M.EXCHANGE[start + valueOf(ctx, prize) + 1] or { 0, 0 }
  store(ctx, itemDest, row[1])
  store(ctx, costDest, row[2])
end

-- `pokemartfrontier <id>` (ScrCmd_PokeMartFrontier): the Exchange Service
-- Corner, MART_TYPE_FRONTIER -- 0 the right counter's TMs, 1 the left's items,
-- each at Shop_GetItemBPPrice's price (the table above)
function M.frontierStock(martID)
  local from, to = M.EXCHANGE_TMS + 1, #M.EXCHANGE
  if martID == 1 then from, to = 1, M.EXCHANGE_TMS end
  local stock, price = {}, {}
  for i = from, to do
    local row = M.EXCHANGE[i]
    stock[#stock + 1] = row[1]
    price[row[1]] = row[2]
  end
  return stock, price
end

function Commands.g4_pokemart_frontier(ctx, martID)
  local stock, price = M.frontierStock(valueOf(ctx, martID))
  local runner = ctx.runner
  require("src.ui.Screens").push(ctx.game, "ShopMenu", stock, function() if runner then runner:resume() end end, nil,
    { frontier = { price = function(id) return price[id] or 0 end } })
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_pokemart_frontier = { foreground = true, blocking = true }

return M
