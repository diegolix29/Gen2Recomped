-- tools/gen5_items_check/main.lua
--
-- BLACK / WHITE ITEMS IN BATTLE, THROUGH THE REAL ENGINE: the held items'
-- hold effects (src/battle/Gen5HoldItems.lua), the battle bag (src/battle/
-- Gen5BagUse.lua: balls, medicine, battle items, Poke Dolls, the refusals),
-- the item records (src/inventory/Gen5Items.lua) and the Gen V capture sum
-- (src/battle/Gen5Catching.lua). The sibling of tools/gen5_move_effects_check.
--
--   POKEPORT_DATA_DIR=G:/Gen2Recomped/black/data/generated VERSION=black \
--     lovec tools/gen5_items_check
--
-- Env: VERBOSE=1 prints every scenario.

local function env(k, d) local v = os.getenv(k) if v == nil or v == "" then return d end return v end

local results = { pass = 0, fail = 0, fails = {} }
local function check(cond, what, detail)
  if cond then results.pass = results.pass + 1
  else
    results.fail = results.fail + 1
    results.fails[#results.fails + 1] = what .. (detail and (" -- " .. tostring(detail)) or "")
  end
  if env("VERBOSE") then print((cond and "ok   " or "FAIL ") .. what .. (detail and (" -- " .. tostring(detail)) or "")) end
  return cond
end

local function main()
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(env("VERSION", "black"))
  local Data = require("src.core.Data")
  Data:load()
  local Pokemon = require("src.pokemon.Pokemon")
  local SaveData = require("src.core.SaveData")
  local BattleState = require("src.battle.BattleState")
  local Game = require("src.core.Game")
  local G5 = require("src.battle.Gen5MoveEffects")
  local T = require("src.battle.Gen5BattleText")
  local H = require("src.battle.Gen5HoldItems")
  local HoldItems = require("src.battle.HoldItems")
  local U = require("src.battle.Gen5BagUse")
  local Items = require("src.inventory.Gen5Items")
  local C = require("src.battle.Gen5Catching")
  local TurnOrder = require("src.battle.TurnOrder")
  Game.data = Data
  Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
  Game.input = { wasPressed = function() return false end, isDown = function() return false end,
                 wasReleased = function() return false end }
  Game.stack = require("src.core.StateStack")
  Game.stack:init()
  assert(G5.isBW(Data), "this cache is not Black / White's")
  G5.prepare(Data)
  require("src.battle.TypeChart").load(Data)
  Items.ensure(Data)

  local function fresh(playerSp, foeSp, kind)
    Game.save.party = { Pokemon.new(Data, playerSp or 495, 50), Pokemon.new(Data, 498, 50) }
    local b = BattleState.newWild(Game, foeSp or 506, 50)
    b.rng = function(a) return a end
    b.bwAutoSwitch = true
    b.queue, b.nextInsert = {}, 0
    for _, x in ipairs({ b.player, b.enemy }) do
      x.abilityOverride = false
      x.mon.item = nil
      x.mon.status = nil
      x.mon.stats.hp, x.mon.hp = 999, 999
      x.stages = x.stages or {}
    end
    b.turnCount = 1
    H.onSwitchIn(b, b.player)
    H.onSwitchIn(b, b.enemy)
    return b
  end
  local function lines(b)
    local out = {}
    for _, item in ipairs(b.queue) do
      if type(item.text) == "string" and item.text ~= "" then out[#out + 1] = T.translate(b, item.text) end
    end
    return out
  end
  local function said(b, want)
    for _, l in ipairs(lines(b)) do if l == want then return true end end
    return false
  end
  local function bank14(b, idx, battler, item)
    return T.set(b, idx, battler, { nil, item and Data.items[item].name })
  end
  local function dmg(b, user, target, moveId)
    local d = b:computeDamage(user, target, Data.moves[moveId], { rng = b.rng })
    return d
  end
  local function hit(b, user, target, moveId)
    b:performMove(user, target, { id = moveId, pp = 30 })
  end
  local function hold(x, id) x.mon.item = id end

  -- ---------------------------------------------------------------------
  -- 1. THE RECORDS
  -- ---------------------------------------------------------------------
  check(Items.battleKind(Data.items[4]) == "ball", "[items] Poke Ball is a ball")
  check(Items.battleKind(Data.items[576]) == "ball", "[items] Dream Ball is a ball")
  check(Items.battleKind(Data.items[17]) == "medicine", "[items] Potion is medicine")
  check(Items.battleKind(Data.items[18]) == "medicine", "[items] Antidote is medicine")
  check(Items.battleKind(Data.items[158]) == "medicine", "[items] Sitrus Berry is medicine")
  check(Items.battleKind(Data.items[57]) == "battle", "[items] X Attack is a battle item")
  check(Items.battleKind(Data.items[63]) == "escape", "[items] Poke Doll flees")
  check(Items.battleKind(Data.items[79]) == nil, "[items] Repel has no battle use")
  local rec = U.record(Data.items[17])
  check(rec and rec.heal and rec.amount == 20, "[items] Potion's block heals 20")
  rec = U.record(Data.items[28])
  check(rec and rec.revive and rec.amount == 254, "[items] Revive's block revives to half")
  check(require("src.inventory.ItemEffects").needsTarget(17, Data.items[17]) == true,
        "[items] the field bag's Potion asks for a Pokemon")
  do -- the field bag's medicine runs through ItemEffects with the party block
    local IE = require("src.inventory.ItemEffects")
    local mon = Pokemon.new(Data, 495, 50)
    mon.hp = 10
    local kind = IE.use(Data, Game.save, 17, mon, nil)
    check(kind == "consumed" and mon.hp == 30, "[items] a field Potion heals 20", tostring(kind) .. " " .. mon.hp)
    mon.hp = 10
    kind = IE.use(Data, Game.save, 158, mon, nil)
    check(kind == "consumed" and mon.hp == 10 + math.floor(mon.stats.hp / 4), "[items] a field Sitrus heals a quarter", mon.hp)
  end
  check(require("src.inventory.Gen4ItemUse").rowanLine(Data, Game.save):find("Juniper", 1, true) ~= nil,
        "[text] the refusal is Juniper's words, not bank 213 (Alder)")

  -- ---------------------------------------------------------------------
  -- 2. THE CAPTURE SUM
  -- ---------------------------------------------------------------------
  local low = function(a) return a end
  local ctx = { catchRate = 45, maxHP = 100, hp = 100, level = 30, turns = 0, caughtCount = 0 }
  check(select(1, C.attempt(1, ctx, low)) == true, "[catch] the Master Ball always catches")
  check(C.ballBonus(15, { turns = 0 }) == 5 * 4096, "[catch] Quick Ball x5 on the first turn")
  check(C.ballBonus(15, { turns = 1 }) == 4096, "[catch] ...x1 after it")
  check(C.ballBonus(10, { turns = 10 }) == 4 * 4096, "[catch] Timer Ball caps at x4")
  check(C.ballBonus(10, { turns = 2 }) == 4096 + 2458, "[catch] Timer Ball 1 + turns * 1229/4096")
  check(C.ballBonus(8, { level = 11 }) == 12288, "[catch] Nest Ball (41 - 11) / 10 = x3")
  check(C.ballBonus(8, { level = 50 }) == 4096, "[catch] Nest Ball x1 at level 50")
  check(C.ballBonus(6, { types = { "WATER" } }) == 12288, "[catch] Net Ball x3 on Water")
  check(C.ballBonus(13, { hour = 22 }) == 14336, "[catch] Dusk Ball x3.5 at night")
  check(C.ballBonus(13, { hour = 12 }) == 4096, "[catch] ...x1 at noon")
  check(C.ballBonus(9, { alreadyCaught = true }) == 12288, "[catch] Repeat Ball x3 when owned")
  check(C.ballBonus(7, { terrain = "water" }) == 14336, "[catch] Dive Ball x3.5 on water")
  check(C.ballBonus(2, {}) == 8192 and C.ballBonus(3, {}) == 6144, "[catch] Ultra x2, Great x1.5")
  local x = C.rate(4, { catchRate = 255, maxHP = 100, hp = 100 })
  check(math.abs(x - 85) < 0.01, "[catch] full HP Poke Ball on rate 255 = 85", x)
  x = C.rate(4, { catchRate = 255, maxHP = 100, hp = 100, status = "SLP" })
  check(math.abs(x - 212.5) < 0.01, "[catch] asleep x2.5", x)
  local caught, shakes, crit = C.attempt(4, { catchRate = 45, maxHP = 100, hp = 1, caughtCount = 700 }, low)
  check(caught and crit and shakes == 1, "[catch] a critical capture shakes once", tostring(caught) .. "/" .. tostring(shakes))
  caught, shakes = C.attempt(4, { catchRate = 3, maxHP = 100, hp = 100, caughtCount = 0 },
    function(a, b2) if b2 == 65535 then return 65535 end return a end)
  check(not caught and shakes == 0, "[catch] a first failed check breaks free at once")

  -- ---------------------------------------------------------------------
  -- 3. THE BATTLE BAG
  -- ---------------------------------------------------------------------
  do
    local b = fresh()
    local mon = Game.save.party[1]
    mon.hp = 100
    local ok, out = U.applyMedicine(Game, b, Data.items[17], mon)
    check(ok and mon.hp == 120, "[bag] Potion heals 20", mon.hp)
    check(ok and out[1] == T.fill(Data.text["TEXT_G5S_0157_00044"], { b.player.name, count = 20 }),
          "[bag] ...with the party bank's line 44", out and out[1])
    mon.hp = mon.stats.hp
    ok = U.applyMedicine(Game, b, Data.items[17], mon)
    check(not ok, "[bag] Potion at full HP has no effect")
    mon.status = "PSN"
    ok = U.applyMedicine(Game, b, Data.items[18], mon)
    check(ok and mon.status == nil, "[bag] Antidote cures poison")
    mon.status = "PAR"
    ok = U.applyMedicine(Game, b, Data.items[18], mon)
    check(not ok and mon.status == "PAR", "[bag] Antidote leaves paralysis alone")
    mon.hp = 50
    ok = U.applyMedicine(Game, b, Data.items[23], mon)
    check(ok and mon.hp == mon.stats.hp and mon.status == nil, "[bag] Full Restore heals and cures")
    local other = Game.save.party[2]
    other.hp = 0
    ok = U.applyMedicine(Game, b, Data.items[28], other)
    check(ok and other.hp == math.floor(other.stats.hp / 2), "[bag] Revive brings one back at half")
    other.moves[1].pp = 0
    ok = U.applyMedicine(Game, b, Data.items[38], other, 1)
    check(ok and other.moves[1].pp == math.min(10, Data.moves[other.moves[1].id].pp), "[bag] Ether restores 10 PP")
    mon.hp = 100
    ok = U.applyMedicine(Game, b, Data.items[158], mon)
    check(ok and mon.hp == 100 + math.floor(999 / 4), "[bag] Sitrus from the bag heals a quarter", mon.hp)
    -- battle items
    b.player.stages.attack = 0
    ok = U.applyBattleItem(b, Data.items[57], b.player)
    check(ok and b.player.stages.attack == 1, "[bag] X Attack raises Attack one stage")
    b.player.stages.attack = 6
    ok = U.applyBattleItem(b, Data.items[57], b.player)
    check(not ok, "[bag] X Attack at +6 has no effect")
    ok = U.applyBattleItem(b, Data.items[56], b.player)
    check(ok and b.player.focusEnergy, "[bag] Dire Hit pumps")
    ok = U.applyBattleItem(b, Data.items[55], b.player)
    check(ok and (b.bw.sides[1].mist or 0) > 0, "[bag] Guard Spec. raises Mist")
  end
  do -- the refusals
    local b = fresh()
    check(U.ballRefusal(Game, b) == nil, "[bag] a wild single may be thrown at")
    b.enemy.invulnerable = true
    check(U.ballRefusal(Game, b) == U.line(Data, 17, 47), "[bag] not at a Pokemon out of sight")
    b.enemy.invulnerable = nil
    local Boxes = require("src.pokemon.Boxes")
    while #Game.save.party < 6 do Game.save.party[#Game.save.party + 1] = Pokemon.new(Data, 506, 5) end
    local boxes = Boxes.ensure(Game.save)
    for i = 1, Boxes.count() do for s = 1, Boxes.capacity() do boxes[i][s] = boxes[i][s] or { species = 506 } end end
    check(U.ballRefusal(Game, b) == U.line(Data, 17, 45), "[bag] no room left in the PC")
    Game.save.boxes = nil
  end
  do -- the throw, run through the queue
    local b = fresh()
    b.queue, b.nextInsert = {}, 0
    U.throw(b, 1)
    local guard = 0
    while #b.queue > 0 and guard < 200 do
      local item = table.remove(b.queue, 1)
      b.nextInsert = 0
      if item.fn then item.fn() end
      guard = guard + 1
    end
    local last = Game.save.party[#Game.save.party]
    check(b.result == "caught", "[bag] a Master Ball catches the wild Pokemon", b.result)
    check(last and last.ball == 1, "[bag] ...and it is caught in the Master Ball", last and last.ball)
    local b2 = fresh(nil, nil)
    b2.kind = "trainer"
    b2.queue, b2.nextInsert = {}, 0
    U.throw(b2, 4)
    local first = table.remove(b2.queue, 1)
    local fn = table.remove(b2.queue, 1)
    if fn and fn.fn then fn.fn() end
    check(said(b2, U.line(Data, 15, 67)), "[bag] a trainer blocks the ball (bank 15 #67)")
  end

  -- ---------------------------------------------------------------------
  -- 4. THE HELD ITEMS
  -- ---------------------------------------------------------------------
  local function scenario(name, setup, run, ok)
    local b = fresh()
    local e = { b = b, p = b.player, f = b.enemy }
    if setup then setup(e) end
    H.onSwitchIn(b, b.player)
    H.onSwitchIn(b, b.enemy)
    local okRun, err = pcall(run, e)
    if not okRun then return check(false, "[held] " .. name, err) end
    local good, why = ok(e)
    return check(good, "[held] " .. name, why or table.concat(lines(b), " | "))
  end

  scenario("Leftovers heal a sixteenth", function(e) hold(e.p, 234); e.p.mon.hp = 500 end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.hp == 500 + math.floor(999 / 16) and said(e.b, bank14(e.b, 914, e.p, 234)) end)
  scenario("Black Sludge hurts a non-Poison holder", function(e) hold(e.p, 281) end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.hp == 999 - math.floor(999 / 8) end)
  scenario("Black Sludge heals a Poison type", function(e) hold(e.p, 281); e.p.curTypes = { "POISON" }; e.p.mon.hp = 500 end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.hp == 500 + math.floor(999 / 16) end)
  scenario("Sitrus Berry heals a quarter at half HP", function(e) hold(e.p, 158); e.p.mon.hp = 400 end,
    function(e) e.b:holdItemTrigger(e.p, "hit") end,
    function(e) return e.p.mon.hp == 400 + math.floor(999 / 4) and not e.p.mon.item end)
  scenario("Oran Berry heals 10", function(e) hold(e.p, 155); e.p.mon.hp = 400 end,
    function(e) e.b:holdItemTrigger(e.p, "hit") end,
    function(e) return e.p.mon.hp == 410 end)
  scenario("Sitrus waits above half", function(e) hold(e.p, 158); e.p.mon.hp = 600 end,
    function(e) e.b:holdItemTrigger(e.p, "hit") end,
    function(e) return e.p.mon.hp == 600 and e.p.mon.item == 158 end)
  scenario("Cheri Berry cures paralysis", function(e) hold(e.p, 149); e.p.mon.status = "PAR" end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.status == nil and said(e.b, bank14(e.b, 920, e.p, 149)) end)
  scenario("Lum Berry cures sleep", function(e) hold(e.p, 157); e.p.mon.status = "SLP" end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.status == nil end)
  scenario("Persim Berry cures confusion", function(e) hold(e.p, 156); e.p.confusedTurns = 3 end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.confusedTurns == nil end)
  scenario("Liechi Berry raises Attack at a quarter", function(e) hold(e.p, 201); e.p.mon.hp = 200 end,
    function(e) e.b:holdItemTrigger(e.p, "hit") end,
    function(e) return e.p.stages.attack == 1 end)
  scenario("Figy Berry heals an eighth", function(e) hold(e.p, 159); e.p.mon.hp = 400 end,
    function(e) e.b:holdItemTrigger(e.p, "hit") end,
    function(e) return e.p.mon.hp == 400 + math.floor(999 / 8) end)
  scenario("White Herb restores lowered stats", function(e) hold(e.p, 214); e.p.stages.attack = -2 end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.stages.attack == 0 and not e.p.mon.item end)
  scenario("Mental Herb cures infatuation", function(e) hold(e.p, 219); e.p.infatuated = true end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return not e.p.infatuated end)
  scenario("Toxic Orb badly poisons", function(e) hold(e.p, 272) end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.status == "PSN" and e.p.toxicCounter == 1 end)
  scenario("Flame Orb burns", function(e) hold(e.p, 273) end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.status == "BRN" end)
  scenario("Sticky Barb hurts an eighth", function(e) hold(e.p, 288) end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.p.mon.hp == 999 - math.floor(999 / 8) end)
  scenario("Light Clay makes a screen last 8 turns", function(e) hold(e.p, 269); e.b.bw.sides[1].reflect = 5 end,
    function(e) e.b:holdItemTrigger(e.p, "turn") end,
    function(e) return e.b.bw.sides[1].reflect == 8 end)

  -- damage
  local function compare(name, item, moveId, setup, want)
    local b = fresh()
    if setup then setup(b) end
    local base = dmg(b, b.player, b.enemy, moveId)
    hold(b.player, item)
    H.onSwitchIn(b, b.player)
    local with = dmg(b, b.player, b.enemy, moveId)
    local ratio = with / math.max(1, base)
    check(math.abs(ratio - want) < 0.1, "[held] " .. name, ("%d -> %d (x%.2f)"):format(base, with, ratio))
    return b
  end
  compare("Choice Band x1.5 on a physical move", 220, 33, nil, 1.5)
  compare("Choice Specs x1.5 on a special move", 297, 52, nil, 1.5)
  compare("Charcoal +20% on Fire", 249, 52, nil, 1.2)
  compare("Flame Plate +20% on Fire", 298, 52, nil, 1.2)
  compare("Muscle Band +10% physical", 266, 33, nil, 1.1)
  compare("Wise Glasses +10% special", 267, 52, nil, 1.1)
  compare("Life Orb x1.3", 270, 33, nil, 1.3)
  compare("Expert Belt +20% super effective", 268, 52, function(b) b.enemy.curTypes = { "GRASS" } end, 1.2)
  local gb = compare("Normal Gem x1.5", 564, 33, nil, 1.5)
  check(gb.player.mon.item == nil, "[held] the gem is spent")
  do
    local b = fresh()
    b.enemy.curTypes = { "GRASS" }
    local base = dmg(b, b.player, b.enemy, 52)
    hold(b.enemy, 184)
    local with = dmg(b, b.player, b.enemy, 52)
    check(math.abs(with / base - 0.5) < 0.05 and not b.enemy.mon.item, "[held] Occa Berry halves a super-effective Fire hit",
          ("%d -> %d"):format(base, with))
    check(said(b, bank14(b, 219, b.enemy, 184)), "[held] ...with bank 14 line 219")
  end
  do
    local b = fresh(495)
    local base = dmg(b, b.enemy, b.player, 33)
    hold(b.player, 538)
    local with = dmg(b, b.enemy, b.player, 33)
    check(with < base, "[held] Eviolite thickens a Pokemon that can still evolve", ("%d -> %d"):format(base, with))
  end
  -- after a hit
  scenario("Life Orb costs a tenth", function(e) hold(e.p, 270) end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) return e.p.mon.hp == 999 - math.floor(999 / 10), e.p.mon.hp end)
  scenario("Shell Bell heals an eighth of the damage", function(e) hold(e.p, 253); e.p.mon.hp = 500 end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) local d = 999 - e.f.mon.hp return e.p.mon.hp == 500 + math.max(1, math.floor(d / 8)), e.p.mon.hp end)
  scenario("Rocky Helmet hurts a contact attacker a sixth", function(e) hold(e.f, 540) end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) return e.p.mon.hp == 999 - math.floor(999 / 6) end)
  scenario("King's Rock flinches", function(e) hold(e.p, 221) end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) return e.f.flinched == true end)
  scenario("Air Balloon: Ground moves miss, then a hit pops it", function(e) hold(e.f, 541) end,
    function(e) hit(e.b, e.p, e.f, 89); e.hpAfterQuake = e.f.mon.hp; hit(e.b, e.p, e.f, 33) end,
    function(e) return e.hpAfterQuake == 999 and e.f.mon.item == nil and e.f.mon.hp < 999 end)
  scenario("Absorb Bulb raises Sp. Atk on a Water hit", function(e) hold(e.f, 545) end,
    function(e) hit(e.b, e.p, e.f, 55) end,
    function(e) return e.f.stages.spatk == 1 and not e.f.mon.item end)
  scenario("Cell Battery raises Attack on an Electric hit", function(e) hold(e.f, 546) end,
    function(e) hit(e.b, e.p, e.f, 84) end,
    function(e) return e.f.stages.attack == 1 end)
  scenario("Jaboca Berry hurts a physical attacker an eighth", function(e) hold(e.f, 211) end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) return e.p.mon.hp == 999 - math.floor(999 / 8) end)
  scenario("Eject Button switches the holder out", function(e) hold(e.p, 547) end,
    function(e) e.mon = e.p.mon; hit(e.b, e.f, e.p, 33) end,
    function(e) return e.b.player.mon ~= e.mon, tostring(e.b.player.mon and e.b.player.mon.species) end)
  scenario("Red Card sends the attacker away (a wild one flees)", function(e) hold(e.f, 542) end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) return e.b.result == "run" and not e.f.mon.item end)
  scenario("Focus Sash leaves one HP from full", function(e) hold(e.p, 275) end,
    function(e) e.b:applyDamage(e.p, 5000, true) end,
    function(e) return e.p.mon.hp == 1 and not e.p.mon.item end)
  scenario("Focus Band can leave one HP", function(e) hold(e.p, 230); e.p.mon.hp = 300 end,
    function(e) e.b:applyDamage(e.p, 5000, true) end,
    function(e) return e.p.mon.hp == 1 and e.p.mon.item == 230 end)
  -- the small hooks
  do
    local b = fresh()
    hold(b.player, 232)
    check(HoldItems.critStages(b.player) == 1, "[held] Scope Lens +1 crit stage")
    hold(b.player, 217)
    check(HoldItems.quickClawChance(b.player) == 20, "[held] Quick Claw 20%")
    hold(b.enemy, 213)
    hold(b.player, nil)
    check(HoldItems.accuracyMultiplier(b.player, b.enemy) == 90, "[held] BrightPowder -10% accuracy")
    hold(b.enemy, nil)
    hold(b.player, 265)
    check(HoldItems.accuracyMultiplier(b.player, b.enemy) == 110, "[held] Wide Lens +10% accuracy")
    local spd = TurnOrder.effectiveSpeed(b.player, b)
    hold(b.player, 287)
    check(TurnOrder.effectiveSpeed(b.player, b) == math.floor(spd * 3 / 2), "[held] Choice Scarf x1.5 speed")
    hold(b.player, 278)
    check(TurnOrder.effectiveSpeed(b.player, b) == math.floor(spd / 2), "[held] Iron Ball halves speed")
    hold(b.player, 279)
    check(TurnOrder.effectiveSpeed(b.player, b) == 0, "[held] Lagging Tail moves last")
    hold(b.player, 228)
    check(require("src.battle.HeldItems").canEscape(Data, b.player), "[held] Smoke Ball always escapes")
    hold(b.player, 221)
    check(HoldItems.flinchChance(b.player, Data.moves[33]) == 10, "[held] King's Rock 10%")
  end

  -- ---------------------------------------------------------------------
  -- 5. THE HELD ITEMS THE TURN ANSWERS (src/battle/Gen5MoveRules.lua and
  --    the bottom of Gen5HoldItems): Choice, the rocks, binding, Power Herb,
  --    Float Stone, Ring Target, Destiny Knot, Shed Shell, Custap, Micle,
  --    Quick Claw's line, Smoke Ball's
  -- ---------------------------------------------------------------------
  local R = require("src.battle.Gen5MoveRules")
  -- run the queue as the battle would, keeping every line it says (on
  -- b.spoken, which `said` reads after)
  local function drain(b)
    local guard = 0
    b.spoken = b.spoken or {}
    while #b.queue > 0 and guard < 400 do
      local item = table.remove(b.queue, 1)
      b.nextInsert = 0
      if type(item.text) == "string" and item.text ~= "" then b.spoken[#b.spoken + 1] = T.translate(b, item.text) end
      if item.fn then item.fn() end
      guard = guard + 1
    end
  end
  local realLines = lines
  lines = function(b)
    local out = {}
    for _, l in ipairs(b.spoken or {}) do out[#out + 1] = l end
    for _, l in ipairs(realLines(b)) do out[#out + 1] = l end
    return out
  end
  local function name(id) return Data.items[id].name end

  scenario("Choice Band: the menu refuses another move (bank 14 #905)",
    function(e) hold(e.p, 220); e.p.curMoves = { { id = 33, pp = 35 }, { id = 52, pp = 25 } } end,
    function(e)
      e.b:executeAction(e.p, e.f, e.p.curMoves[1])
      e.line = R.moveBlocked(e.b, e.p, Data.moves[52], true)
      e.same = R.moveBlocked(e.b, e.p, Data.moves[33], true)
    end,
    function(e) return e.p.bwChoiceLock == 33 and e.same == nil
                       and e.line == T.set(e.b, 905, e.p, { nil, Data.moves[52].name }), tostring(e.line) end)
  scenario("Choice Scarf: a trainer's other pick is bent back to the locked move",
    function(e) hold(e.f, 287); e.f.curMoves = { { id = 33, pp = 35 }, { id = 52, pp = 25 } }; e.f.bwChoiceLock = 33 end,
    function(e) e.b:executeAction(e.f, e.p, e.f.curMoves[2]) end,
    function(e) return e.f.curMoves[1].pp == 34 and e.f.curMoves[2].pp == 25 and said(e.b, T.used(e.b, e.f, 33)) end)
  scenario("the Choice lock ends with the item (Knock Off / Trick)",
    function(e) e.p.curMoves = { { id = 33, pp = 35 } }; e.p.bwChoiceLock = 52 end,
    function(e) e.line = R.moveBlocked(e.b, e.p, Data.moves[33], true) end,
    function(e) return e.line == nil end)
  scenario("Damp Rock: Rain Dance lasts eight turns",
    function(e) hold(e.p, 285) end,
    function(e) hit(e.b, e.p, e.f, 240) end,
    function(e) return e.b.field.weatherTurns == 8, e.b.field.weatherTurns end)
  scenario("Heat Rock / Smooth Rock / Icy Rock likewise", nil,
    function(e)
      e.got = {}
      for _, row in ipairs({ { 284, 241 }, { 283, 201 }, { 282, 258 } }) do
        local b = fresh()
        hold(b.player, row[1])
        hit(b, b.player, b.enemy, row[2])
        e.got[#e.got + 1] = b.field.weatherTurns
      end
    end,
    function(e) return e.got[1] == 8 and e.got[2] == 8 and e.got[3] == 8, table.concat(e.got, ",") end)
  scenario("...and without a rock, five", nil,
    function(e) hit(e.b, e.p, e.f, 240) end,
    function(e) return e.b.field.weatherTurns == 5 end)
  scenario("Grip Claw: Wrap holds for seven turns of damage",
    function(e) hold(e.p, 286) end,
    function(e) hit(e.b, e.p, e.f, 35) end,
    function(e) return e.f.bwBound and e.f.bwBound.turns == 8, e.f.bwBound and e.f.bwBound.turns end)
  scenario("Binding Band: an eighth a turn instead of a sixteenth",
    function(e) hold(e.p, 544) end,
    function(e)
      hit(e.b, e.p, e.f, 35)
      e.hp = e.f.mon.hp
      require("src.battle.Gen5MoveEffects").upkeep(e.b)
    end,
    function(e) return e.hp - e.f.mon.hp == math.floor(999 / 8), e.hp - e.f.mon.hp end)
  scenario("...and without it a sixteenth (4-5 turns of it)", nil,
    function(e)
      hit(e.b, e.p, e.f, 35)
      e.turns = e.f.bwBound and e.f.bwBound.turns
      e.hp = e.f.mon.hp
      require("src.battle.Gen5MoveEffects").upkeep(e.b)
    end,
    function(e) return e.hp - e.f.mon.hp == math.floor(999 / 16) and (e.turns == 5 or e.turns == 6), e.turns end)
  scenario("Power Herb: Solar Beam fires at once (bank 14 #1022), the herb spent",
    function(e) hold(e.p, 271) end,
    function(e) hit(e.b, e.p, e.f, 76) end,
    function(e) return e.f.mon.hp < 999 and not e.p.charging and not e.p.mon.item
                       and said(e.b, bank14(e.b, 1022, e.p, 271)) end)
  scenario("Power Herb: Fly too, without the turn in the air",
    function(e) hold(e.p, 271) end,
    function(e) hit(e.b, e.p, e.f, 19) end,
    function(e) return e.f.mon.hp < 999 and not e.p.invulnerable end)
  scenario("...and without it Solar Beam charges", nil,
    function(e) hit(e.b, e.p, e.f, 76) end,
    function(e) return e.f.mon.hp == 999 and e.p.charging ~= nil end)
  scenario("Float Stone halves the holder's weight (Low Kick hits it softer)", nil,
    function(e)
      e.before = R.weightOf(e.f)
      hold(e.f, 539)
      e.after = R.weightOf(e.f)
    end,
    function(e) return e.after == math.max(1, math.floor(e.before / 2)), e.before .. " -> " .. e.after end)
  scenario("Ring Target: a Normal move hits a Ghost holder",
    function(e) hold(e.f, 543); e.f.curTypes = { "GHOST" } end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) return e.f.mon.hp < 999 end)
  scenario("Ring Target: Earthquake hits a Flying holder",
    function(e) hold(e.f, 543); e.f.curTypes = { "FLYING" } end,
    function(e) hit(e.b, e.p, e.f, 89) end,
    function(e) return e.f.mon.hp < 999 end)
  scenario("...and without it the Ghost is untouched",
    function(e) e.f.curTypes = { "GHOST" } end,
    function(e) hit(e.b, e.p, e.f, 33) end,
    function(e) return e.f.mon.hp == 999 end)
  scenario("Destiny Knot: Attract on the holder infatuates the attacker (bank 14 #330)",
    function(e) hold(e.f, 280); e.p.mon.gender, e.f.mon.gender = "male", "female" end,
    function(e) hit(e.b, e.p, e.f, 213) end,
    function(e) return e.f.infatuated and e.p.infatuated == e.f
                       and said(e.b, T.set(e.b, 330, e.p, { nil, name(280) })) end)
  scenario("Shed Shell: a bound holder may still switch",
    function(e) hold(e.p, 295); e.p.bwBound = { turns = 4, by = e.f, name = "Wrap" } end,
    function(e) e.refused = R.switchRefused(e.b, Game.save.party[2]) end,
    function(e) return e.refused == false end)
  scenario("...and without it: \"can't be switched out!\" (bank 18 #88)",
    function(e) e.p.bwBound = { turns = 4, by = e.f, name = "Wrap" } end,
    function(e) e.refused = R.switchRefused(e.b, Game.save.party[2]) end,
    function(e) return e.refused == true and said(e.b, T.fill(Data.text["TEXT_G5S_0018_00088"], { e.p.name })) end)
  scenario("Shadow Tag keeps the player in; Mean Look too",
    function(e) e.f.abilityOverride = "SHADOW_TAG" end,
    function(e)
      e.a = R.switchRefused(e.b, Game.save.party[2])
      e.f.abilityOverride = false
      e.p.trapped = true
      e.c = R.switchRefused(e.b, Game.save.party[2])
    end,
    function(e) return e.a and e.c end)
  scenario("Custap Berry: at a quarter HP its holder moves first (bank 14 #1025)",
    function(e) hold(e.f, 210); e.f.mon.hp = 200 end,
    function(e)
      e.order = R.arrange(e.b, { { e.p, e.f, { id = 33, pp = 35 } }, { e.f, e.p, { id = 33, pp = 35 } } })
      drain(e.b)
    end,
    function(e) return e.order[1][1] == e.f and not e.f.mon.item and said(e.b, bank14(e.b, 1025, e.f, 210)) end)
  scenario("...but not ahead of a higher priority (Quick Attack)",
    function(e) hold(e.f, 210); e.f.mon.hp = 200 end,
    function(e) e.order = R.arrange(e.b, { { e.p, e.f, { id = 98, pp = 30 } }, { e.f, e.p, { id = 33, pp = 35 } } }) end,
    function(e) return e.order[1][1] == e.p end)
  scenario("...and not above a quarter",
    function(e) hold(e.f, 210); e.f.mon.hp = 600 end,
    function(e) e.order = R.arrange(e.b, { { e.p, e.f, { id = 33, pp = 35 } }, { e.f, e.p, { id = 33, pp = 35 } } }) end,
    function(e) return e.order[1][1] == e.p and e.f.mon.item == 210 end)
  scenario("Quick Claw: its 20% puts the holder first, with the line (bank 14 #1025)",
    function(e) hold(e.f, 217) end,
    function(e)
      e.order = R.arrange(e.b, { { e.p, e.f, { id = 33, pp = 35 } }, { e.f, e.p, { id = 33, pp = 35 } } })
      drain(e.b)
    end,
    function(e) return e.order[1][1] == e.f and e.f.mon.item == 217 and said(e.b, bank14(e.b, 1025, e.f, 217)) end)
  scenario("Quick Claw through a real turn: the line, then the holder's move first",
    function(e) hold(e.f, 217); e.f.curMoves = { { id = 33, pp = 35 } }; e.b.enemyAction = function() return e.f.curMoves[1] end end,
    function(e)
      e.b:resolveTurn({ id = 33, pp = 35 })
      drain(e.b)
    end,
    function(e)
      local ls = lines(e.b)
      local claw, foe, mine
      for i, l in ipairs(ls) do
        if l == bank14(e.b, 1025, e.f, 217) then claw = claw or i end
        if l == T.used(e.b, e.f, 33) then foe = foe or i end
        if l == T.used(e.b, e.p, 33) then mine = mine or i end
      end
      return claw and foe and mine and claw < foe and foe < mine, table.concat(ls, " | ")
    end)
  scenario("Micle Berry: at a quarter HP the next move is x1.2 accurate (bank 14 #1028)",
    function(e) hold(e.p, 209); e.p.mon.hp = 200 end,
    function(e)
      e.b:holdItemTrigger(e.p, "hit")
      -- Hypnosis (60%) rolls 160 of 0..255: 153 misses it, 183 hits it
      e.b.rng = function(a, z) if z == 255 then return 160 end return a end
      e.hit = e.b:accuracyRoll(Data.moves[95], e.p, e.f)
      e.again = e.b:accuracyRoll(Data.moves[95], e.p, e.f)
    end,
    function(e) return e.hit == true and e.again == false and said(e.b, bank14(e.b, 1028, e.p, 209)) end)
  scenario("Smoke Ball: \"fled using its Smoke Ball!\" (bank 14 #1004)",
    function(e) hold(e.p, 228) end,
    function(e) e.b:tryRun() end,
    function(e) return e.b.result == "run" and said(e.b, bank14(e.b, 1004, e.p, 228)) end)
  scenario("Leftovers through a real end of turn: the line is said once",
    function(e) hold(e.p, 234); e.p.mon.hp = 500 end,
    function(e) e.b:endOfTurn(); drain(e.b) end,
    function(e)
      local n = 0
      for _, l in ipairs(lines(e.b)) do if l == bank14(e.b, 914, e.p, 234) then n = n + 1 end end
      return n == 1 and e.p.mon.hp == 500 + math.floor(999 / 16), table.concat(lines(e.b), " | ")
    end)
  scenario("a foe's Leftovers likewise",
    function(e) hold(e.f, 234); e.f.mon.hp = 500 end,
    function(e) e.b:endOfTurn(); drain(e.b) end,
    function(e) return said(e.b, bank14(e.b, 914, e.f, 234)) end)
  scenario("Embargo: no medicine from the bag on that Pokemon (bank 18 #105)",
    function(e) e.p.bwEmbargo = 3 end,
    function(e) e.line = U.embargoLine(Game, e.b, e.p.mon) end,
    function(e) return e.line ~= nil and e.line:find(Data.moves[373].name, 1, true) ~= nil, tostring(e.line) end)

  -- ---------------------------------------------------------------------
  -- 6. THICK GRASS (src/world/Gen5WildTables.lua prepareBattle)
  -- ---------------------------------------------------------------------
  do
    local W = require("src.world.Gen5WildTables")
    local Encounter = require("src.world.Encounter")
    local function stateAt(behaviour)
      return { game = Game, map = { inBounds = function() return true end,
                                    cellBehaviour = function() return behaviour end },
               player = { cellX = 1, cellY = 1 } }
    end
    local slots = {}
    for i = 1, 12 do slots[i] = { species = 506 + (i % 3), level = 20, chance = ({ 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 })[i] } end
    local view = { darkGrass = Encounter.gen4Table(slots, 10) }
    Game.save.party = { Pokemon.new(Data, 495, 50), Pokemon.new(Data, 498, 50) }
    local b = BattleState.newWild(Game, 506, 20)
    W.prepareBattle(stateAt(0x06), b, view, true, false, function(a) return a end)
    check(b.gen5ThickGrass == true and b:isDouble() and b:wildFoesStanding() == 2,
          "[grass] dark grass: thick grass, and a double when the roll is under 40 with two able")
    check(U.ballRefusal(Game, b) == U.line(Data, 17, 44), "[grass] ...where no ball can be thrown (bank 17 #44)")
    check(C.context(b, b.enemy.mon, b.enemy.def).thickGrass == true, "[grass] ...and the capture reads the grass modifier")
    local b2 = BattleState.newWild(Game, 506, 20)
    W.prepareBattle(stateAt(0x06), b2, view, true, false, function(a, z) if z == 99 then return 40 end return a end)
    check(b2.gen5ThickGrass == true and not b2:isDouble(), "[grass] a roll of 40 stays a single")
    Game.save.party = { Pokemon.new(Data, 495, 50) }
    local b3 = BattleState.newWild(Game, 506, 20)
    W.prepareBattle(stateAt(0x06), b3, view, true, false, function(a) return a end)
    check(not b3:isDouble(), "[grass] one able Pokemon: never a double")
    local b4 = BattleState.newWild(Game, 506, 20)
    W.prepareBattle(stateAt(0x04), b4, view, false, false, function(a) return a end)
    check(not b4.gen5ThickGrass and not b4:isDouble() and b4.gen5Terrain == "grass", "[grass] ordinary grass: neither, terrain grass")
    local b5 = BattleState.newWild(Game, 506, 20)
    W.prepareBattle(stateAt(0x3D), b5, view, false, true, function(a) return a end)
    check(b5.gen5Terrain == "water", "[grass] surfing: terrain water (Nature Power's Hydro Pump)")
    check(require("src.world.Gen5FieldRules").isDarkGrass({ inBounds = function() return true end,
      cellBehaviour = function() return 0x22 end }, 1, 1), "[grass] behaviour 0x22 is dark grass")
  end

  -- ---------------------------------------------------------------------
  -- 7. THE BATTLE BAG SCREEN (src/ui/Gen5BattleBag.lua)
  -- ---------------------------------------------------------------------
  do
    local BB = require("src.ui.Gen5BattleBag")
    check(BB.available(Data), "[bagui] the cache carries the battle bag's art (gen5_battle_bag)")
    local Bag = require("src.inventory.Bag")
    Game.save.party = { Pokemon.new(Data, 495, 50), Pokemon.new(Data, 498, 50) }
    Game.save.inventory, Game.save.bagOrder = {}, nil
    for _, id in ipairs({ 17, 18, 4, 57, 23, 2 }) do Bag.add(Game.save, id, 3, Data) end
    local b = fresh()
    Game.stack:init()
    table.insert(Game.stack.states, b)
    check(require("src.battle.Gen4Battle").bagScreenId(b) == "Gen5BattleBag", "[bagui] BAG in a BW battle opens BW's own bag")
    local pressed = {}
    Game.input = { wasPressed = function(_, k) return pressed[k] end, isDown = function() return false end,
                   wasReleased = function() return false end }
    local bag = BB.new(Game, { battle = b })
    Game.stack:push(bag)
    local function ids(p)
      local out = {}
      for _, row in ipairs(bag.pockets[p]) do out[#out + 1] = tonumber(Data.items[row.id].id) end
      table.sort(out)
      return table.concat(out, ",")
    end
    check(ids("hp") == "17,23" and ids("status") == "18,23" and ids("balls") == "2,4" and ids("battle") == "57",
          "[bagui] the pockets by the battle-pocket mask", ("hp=%s st=%s balls=%s bt=%s"):format(ids("hp"), ids("status"), ids("balls"), ids("battle")))
    local function tick(n, key)
      for i = 1, n or 1 do
        pressed = {}
        if key and i == 1 then pressed[key] = true end
        Game.stack:update(1 / 60)
      end
    end
    -- the keys: the first press shows the cursor, then right, A -> Poke Balls
    tick(1, "a"); tick(1, "right"); tick(1, "a"); tick(10)
    check(bag.screen == "pocket" and bag.pocket == "balls", "[bagui] keys: right + A opens POKe BALLS", bag.screen .. "/" .. tostring(bag.pocket))
    tick(1, "b"); tick(10)
    check(bag.screen == "menu", "[bagui] keys: B goes back to the pockets")
    -- a touch on the HP/PP button (the screen's own pixels, at the swap layout's 1:1)
    local SecondScreen = require("src.ui.SecondScreen")
    local realLocal = SecondScreen.toLocal
    SecondScreen.toLocal = function(_, x, y) return x, y end
    bag:touchpressed("mouse", 40, 40); tick(10)
    check(bag.screen == "pocket" and bag.pocket == "hp", "[bagui] a tap on HP/PP RESTORE opens it")
    bag:touchpressed("mouse", 40, 30); tick(10)
    check(bag.screen == "use", "[bagui] a tap on the first item opens its USE screen")
    bag:touchpressed("mouse", 230, 170); tick(10)
    check(bag.screen == "pocket", "[bagui] the back button returns to the pocket")
    bag:touchpressed("mouse", 230, 170); tick(10)
    -- POKe BALLS, a Poke Ball: the throw takes the turn and closes the bag
    bag:touchpressed("mouse", 180, 40); tick(10)
    local ballRow
    for i = 1, 6 do local row = bag:itemAt(i) if row and tonumber(Data.items[row.id].id) == 4 then ballRow = i end end
    local r = bag.R.pocket[ballRow or 1]
    bag:touchpressed("mouse", r[1] + 20, r[2] + 20); tick(10)
    check(bag.screen == "use", "[bagui] the Poke Ball's USE screen")
    b.queue, b.nextInsert = {}, 0
    bag:touchpressed("mouse", 100, 170); tick(10)
    check(bag.closed and Game.stack:top() == b and (tonumber(Game.save.inventory[4] or Game.save.inventory["ITEM_004"]) or 0) == 2,
          "[bagui] USE throws it: the bag closes, one ball spent", Game.stack:describeAll())
    check(bag.mem.lastItem ~= nil, "[bagui] ...and it is the LAST USED ITEM now")
    -- a refusal stays in the bag: two wild foes
    local b2 = fresh()
    b2:makeWildDouble(Pokemon.new(Data, 504, 30))
    Game.stack:init(); table.insert(Game.stack.states, b2)
    local bag2 = BB.new(Game, { battle = b2 })
    Game.stack:push(bag2)
    bag2:touchpressed("mouse", 22, 170); tick(10)   -- LAST USED ITEM: the Poke Ball
    bag2:touchpressed("mouse", 100, 170); tick(10)  -- USE
    check(not bag2.closed and bag2.message == U.line(Data, 17, 44):gsub("[\v\f]", "\n"),
          "[bagui] two foes: the refusal is printed over the bag, which stays", tostring(bag2.message))
    tick(1, "a")
    check(bag2.message == nil, "[bagui] A clears the message")
    -- every screen draws
    for _, scr in ipairs({ "menu", "pocket", "use" }) do
      if scr == "pocket" or scr == "use" then bag2.pocket = "hp" end
      bag2:setScreen(scr)
      local c = love.graphics.newCanvas(256, 192)
      love.graphics.push("all"); love.graphics.setCanvas(c)
      local okD, errD = pcall(bag2.drawBottom, bag2)
      love.graphics.pop()
      check(okD, "[bagui] the " .. scr .. " screen draws", errD)
    end
    SecondScreen.toLocal = realLocal
  end

  for _, f in ipairs(results.fails) do print("FAIL " .. f) end
  print(("[result] %d passed, %d failed"):format(results.pass, results.fail))
  return results.fail == 0
end

function love.load()
  local ok, res = xpcall(main, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(res)) end
  love.event.quit((ok and res) and 0 or 1)
end

function love.draw() end
