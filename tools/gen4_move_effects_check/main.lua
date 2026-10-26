-- tools/gen4_move_effects_check/main.lua
--
-- SINNOH'S FIFTY-THREE MOVE EFFECTS (ids 214..276), THROUGH THE REAL BATTLE
-- ENGINE.  src/battle/Gen4MoveEffects.lua is what made them run; before it,
-- every one of these moves logged "move effect N not implemented; treated as
-- plain damage" (or said "But, it failed!") and did nothing else.
--
-- Part 1 builds a wild 1v1 for every Platinum / HeartGold move whose effect is
-- one of these, once with the player's Pokemon using it and once with the
-- foe's, runs `BattleState:performMove` exactly as a turn does, and asserts the
-- outcome the effect script says it has.  The battle's RNG answers its lowest
-- value, so every chance lands (a 10% burn burns) and nothing misses.
-- Abilities are off except where a check is about one.
--
-- Part 2 plays the effects that only show over a turn or across a switch:
-- end-of-turn countdowns, entry hazards, the Healing Wish heal, Gravity's
-- grounding, Magnet Rise, Lucky Chant, Heal Block, Embargo, Roost's type, the
-- Payback / Assurance / Trump Card arithmetic, Struggle through a Ghost.
--
-- Part 3 asserts no "not implemented" warning was logged by any of it.
--
--   cd <repo>
--   POKEPORT_DATA_DIR=G:/Gen2Recomped/platinum/data/generated VERSION=platinum \
--     lovec tools/gen4_move_effects_check
--   (VERSION=heartgold with the HeartGold cache runs the same checks there)
--
-- Env: VERBOSE=1 prints every battle's lines.

local function env(k, d) local v = os.getenv(k) if v == nil or v == "" then return d end return v end

local results = { pass = 0, fail = 0, fails = {} }
local function check(cond, what, detail)
  if cond then
    results.pass = results.pass + 1
  else
    results.fail = results.fail + 1
    results.fails[#results.fails + 1] = what .. (detail and (" -- " .. tostring(detail)) or "")
  end
  return cond
end

local function main()
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(env("VERSION", "platinum"))
  local Logger = require("src.core.Logger")
  local warnings = {}
  local realWarn = Logger.warn
  Logger.warn = function(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    if ok and msg:find("not implemented", 1, true) then warnings[#warnings + 1] = msg end
    return realWarn(fmt, ...)
  end
  local Data = require("src.core.Data")
  Data:load()
  local Pokemon = require("src.pokemon.Pokemon")
  local SaveData = require("src.core.SaveData")
  local BattleState = require("src.battle.BattleState")
  local Game = require("src.core.Game")
  local G4 = require("src.battle.Gen4MoveEffects")
  local TypeChart = require("src.battle.TypeChart")
  local HoldItems = require("src.battle.HoldItems")
  Game.data = Data
  Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
  Game.input = { wasPressed = function() return false end, isDown = function() return false end,
                 wasReleased = function() return false end }
  TypeChart.load(Data)
  local verbose = env("VERBOSE") ~= nil

  local SNORLAX, PIDGEOT, GENGAR, CHATOT, ARCEUS, CHARIZARD, MUK, SKARMORY =
    143, 18, 94, 441, 493, 6, 89, 227
  local TACKLE, RECOVER = 33, 105

  local function fresh(playerSp, foeSp, bench)
    -- the damage roll's 85..100 variation is love.math.random's, not the
    -- battle's rng: one seed per battle, so two battles that differ only in
    -- the thing under test draw the same variation (Assurance's "doubles"
    -- otherwise compared two different rolls and failed one run in three)
    love.math.setRandomSeed(1)
    Game.save.party = { Pokemon.new(Data, playerSp, 50) }
    if bench ~= false then Game.save.party[2] = Pokemon.new(Data, SNORLAX, 50) end
    local b = BattleState.newWild(Game, foeSp, 50)
    b.rng = function(a) return a end
    b.bwAutoSwitch = true
    -- the battle's start puts the two on their slots (syncSides); a switch
    -- reads the outgoing battler from the slot, so do it here too
    b:syncSides()
    for _, x in ipairs({ b.player, b.enemy }) do
      x.abilityOverride = false
      x.mon.item = nil
      x.mon.status = nil
      x.mon.stats.hp = 999
      x.mon.hp = 999
    end
    b.turnCount = 1
    b.queue, b.nextInsert = {}, 0
    return b
  end
  local function linesOf(b)
    local out = {}
    for _, item in ipairs(b.queue) do
      if type(item.text) == "string" and item.text ~= "" then out[#out + 1] = item.text:gsub("\n", " ") end
    end
    return out
  end
  local function said(b, needle)
    for _, l in ipairs(linesOf(b)) do if l:find(needle, 1, true) then return true end end
    return false
  end
  local function failed(b) return said(b, "But, it failed!") end
  local function use(b, u, t, id, pp)
    b.queue, b.nextInsert = {}, 0
    local ok, err = pcall(b.performMove, b, u, t, { id = id, pp = pp or 10 })
    if not ok then error(err) end
    if verbose then print(("  [%s] %s"):format(tostring(id), table.concat(linesOf(b), " | "))) end
  end

  -- -------------------------------------------------------------------------
  -- 1. EVERY MOVE
  -- -------------------------------------------------------------------------
  local S = {}
  local function flag(get) return function(e) return get(e) ~= nil and get(e) ~= false end end
  local function hurt(e) return e.t.mon.hp < 999 end
  local function side(e, who) return e.b.g4fx and e.b.g4fx.sides[who.isPlayer and true or false] or {} end
  S[214] = { atk = PIDGEOT, setup = function(e) e.u.mon.hp = 300 end,
             check = function(e) return e.u.mon.hp > 300 and e.u.g4Roost ~= nil end }
  S[215] = { check = function(e) return e.b.g4fx.field.gravity == 5 end }
  S[216] = { check = flag(function(e) return e.t.g4MiracleEye end) }
  S[218] = { check = function(e) return hurt(e) and e.u.stages.speed == -1 end }
  S[220] = { check = function(e)
    if e.u.isPlayer then return e.u.mon.hp == 0 and side(e, e.u).healingWish == "wish" end
    return failed(e.b) -- a wild foe has nobody to send in
  end }
  S[270] = { check = function(e)
    if e.u.isPlayer then return e.u.mon.hp == 0 and side(e, e.u).healingWish == "lunar" end
    return failed(e.b)
  end }
  S[222] = { setup = function(e) e.u.mon.item = 155 end,
             check = function(e) return hurt(e) and not e.u.mon.item end }
  S[223] = { setup = function(e) e.t.protecting = true end,
             check = function(e) return hurt(e) and not e.t.protecting and said(e.b, "fell for the feint") end }
  S[224] = { setup = function(e) e.t.mon.item = 158; e.u.mon.hp = 300 end,
             check = function(e) return not e.t.mon.item and e.u.mon.hp > 300 end }
  S[225] = { check = function(e) return side(e, e.u).tailwind == 3 and e.u.bwSpeedMultiplier == 2 end }
  S[226] = { check = function(e) for _, v in pairs(e.u.stages) do if v == 2 then return true end end return false end }
  S[227] = { setup = function(e) e.u.g4HitTurn, e.u.g4HitDamage, e.u.g4HitBy = 1, 20, e.t end,
             check = function(e) return e.t.mon.hp == 999 - 30 end }
  S[228] = { check = function(e) if e.u.isPlayer then return e.b.player ~= e.u and hurt(e) end return hurt(e) end }
  S[229] = { check = function(e) return hurt(e) and e.u.stages.defense == -1 and e.u.stages.spdef == -1 end }
  S[232] = { check = function(e) return e.t.g4Embargo == 5 end }
  S[233] = { setup = function(e) e.u.mon.item = 273 end,       -- Flame Orb: 30 power, burns
             check = function(e) return hurt(e) and not e.u.mon.item and e.t.mon.status == "BRN" end }
  S[234] = { setup = function(e) e.u.mon.status = "BRN" end,
             check = function(e) return e.t.mon.status == "BRN" and not e.u.mon.status end }
  S[236] = { check = function(e) return e.t.g4HealBlock == 5 end }
  S[238] = { setup = function(e) e.before.atk, e.before.def = e.u.curStats.attack, e.u.curStats.defense end,
             check = function(e) return e.u.curStats.attack == e.before.def and e.u.curStats.defense == e.before.atk
                                       and e.u.mon.stats.attack == e.before.atk end }
  S[239] = { check = function(e) return e.t.abilityOverride == false and e.t.g4Suppressed end }
  S[240] = { check = function(e) return side(e, e.u).luckyChant == 5 end }
  S[241] = { setup = function(e) e.b.turnActions = { turn = 1, [e.t] = { id = TACKLE, pp = 35 } } end,
             check = hurt }
  S[242] = { setup = function(e) e.b.g4fx = e.b.g4fx or { field = {}, sides = { [true] = {}, [false] = {} } }; e.b.g4PrevMove = TACKLE end,
             check = hurt }
  S[243] = { setup = function(e) e.t.stages.attack = 2 end, check = function(e) return e.u.stages.attack == 2 end }
  S[244] = { setup = function(e) e.t.stages.defense = 2 end, check = function(e) return e.u.stages.defense == 2 end }
  S[250] = { setup = function(e) e.t.stages.speed = 2 end, check = function(e) return e.u.stages.speed == 2 end }
  S[245] = { setup = function(e) e.t.stages.attack = 2 end, check = hurt }
  S[246] = { setup = function(e)
               e.u.mon.moves = { { id = e.m.id, pp = 5 }, { id = TACKLE, pp = 5 } }
               e.u.g4MovesUsed = { [TACKLE] = true }
             end, check = hurt }
  S[247] = { setup = function(e) e.t.abilityOverride = "BLAZE" end,
             check = function(e) return e.t.abilityOverride == "INSOMNIA" end }
  S[248] = { setup = function(e) e.b.turnActions = { turn = 1, [e.t] = { id = TACKLE, pp = 35 } } end,
             check = hurt }
  S[249] = { check = function(e) return side(e, e.t).toxicSpikes == 1 end }
  S[251] = { check = flag(function(e) return e.u.g4AquaRing end) }
  S[252] = { check = function(e) return e.u.g4MagnetRise == 5 end }
  S[253] = { check = function(e) return hurt(e) and e.u.mon.hp < 999 and e.t.mon.status == "BRN" end }
  S[262] = { check = function(e) return hurt(e) and e.u.mon.hp < 999 and e.t.mon.status == "PAR" end }
  S[269] = { check = function(e) return hurt(e) and e.u.mon.hp < 999 end }
  S[254] = { foe = GENGAR, check = function(e) return hurt(e) and e.u.mon.hp == 999 - 249 end }
  S[257] = { check = hurt }
  S[258] = { setup = function(e) e.t.reflect = true end,
             check = function(e) return e.t.stages.evasion == -1 and not e.t.reflect end }
  S[259] = { check = function(e) return e.b.field.trickRoom == 5 end }
  S[260] = { check = function(e) return hurt(e) and e.t.mon.status == "FRZ" end }
  S[265] = { setup = function(e) e.u.mon.gender, e.t.mon.gender = "male", "female" end,
             check = function(e) return e.t.stages.spatk == -2 end }
  S[266] = { check = function(e) return side(e, e.t).stealthRock == true end }
  S[267] = { atk = CHATOT, check = function(e) return hurt(e) and e.t.confusedTurns ~= nil end }
  S[268] = { atk = ARCEUS, setup = function(e) e.u.mon.item = 298 end, check = hurt }   -- Flame Plate
  S[271] = { check = function(e) return hurt(e) and e.t.stages.spdef == -2 end }
  S[273] = { check = function(e) return hurt(e) and e.t.mon.status == "BRN" and e.t.flinched == true end }
  S[274] = { check = function(e) return hurt(e) and e.t.mon.status == "FRZ" and e.t.flinched == true end }
  S[275] = { check = function(e) return hurt(e) and e.t.mon.status == "PAR" and e.t.flinched == true end }
  S[276] = { check = function(e) return hurt(e) and e.u.stages.spatk == 1 end }
  S[230] = { check = hurt }
  S[231] = { check = hurt }
  S[235] = { check = hurt }

  local tested, covered = 0, {}
  for id = 1, 600 do
    local m = Data.moves[id]
    local fx = m and tonumber(m.gen4Effect)
    if fx and S[fx] then
      covered[fx] = true
      for _, playerSide in ipairs({ true, false }) do
        local spec = S[fx]
        local atk, foe = spec.atk or SNORLAX, spec.foe or SNORLAX
        local b = playerSide and fresh(atk, foe) or fresh(foe, atk)
        local u, t = (playerSide and b.player or b.enemy), (playerSide and b.enemy or b.player)
        local e = { b = b, u = u, t = t, m = m, before = {} }
        if spec.setup then spec.setup(e) end
        local ok, err = pcall(use, b, u, t, id)
        local what = ("%3d %-14s effect %d %s"):format(id, m.name, fx, playerSide and "player" or "foe")
        if not ok then
          check(false, what, "raised: " .. tostring(err):sub(1, 300))
        else
          local good = spec.check(e)
          if verbose or not good then print(("  %s %s: %s"):format(good and "ok  " or "FAIL", what, table.concat(linesOf(b), " | "))) end
          check(good, what)
        end
        tested = tested + 1
      end
    end
  end
  local all = 0
  for fx in pairs(S) do
    all = all + 1
    check(covered[fx], "a move with effect " .. fx .. " exists in this cache")
  end
  print(("[moves] %d battles over %d effects"):format(tested, all))

  -- -------------------------------------------------------------------------
  -- 2. OVER A TURN, ACROSS A SWITCH
  -- -------------------------------------------------------------------------
  local function moveWith(fx)
    for id = 1, 600 do
      local m = Data.moves[id]
      if m and tonumber(m.gen4Effect) == fx then return id end
    end
  end
  local function dmgOf(setup, fx, pp)
    local b = fresh(SNORLAX, SNORLAX)
    local id = moveWith(fx)
    if setup then setup(b) end
    use(b, b.player, b.enemy, id, pp)
    return 999 - b.enemy.mon.hp, b
  end

  -- Payback / Assurance double; Trump Card is 40 at 9 PP left and 200 at 0
  -- (the power is what doubles -- POWER_MULTI 20 -- and the formula's +2 and
  -- its floors keep the damage itself a little under twice)
  local EffectRegistry = require("src.battle.EffectRegistry")
  local MoveEffects = require("src.battle.MoveEffects")
  local function multiplier(fx, setup)
    local b = fresh(SNORLAX, SNORLAX)
    if setup then setup(b) end
    local id = moveWith(fx)
    local rec = MoveEffects.RECORDS[require("src.import.Gen4Moves").EFFECTS[fx][1]]
    return rec.powerMultiplier(EffectRegistry.makeCtx(b, b.player, b.enemy, Data.moves[id], { id = id, pp = 10 }))
  end
  do
    local plain = dmgOf(nil, 230)
    local twice = dmgOf(function(b) b.enemy.actedTurn = 1 end, 230)
    check(multiplier(230, function(b) b.enemy.actedTurn = 1 end) == 2 and multiplier(230) == 1
          and twice >= plain * 1.6, "Payback doubles once the target has moved", plain .. " -> " .. twice)
    plain = dmgOf(nil, 231)
    twice = dmgOf(function(b) b.enemy.g4DamagedTurn = 1 end, 231)
    check(multiplier(231, function(b) b.enemy.g4DamagedTurn = 1 end) == 2 and multiplier(231) == 1
          and twice >= plain * 1.6, "Assurance doubles on a target hurt this turn", plain .. " -> " .. twice)
    local high = dmgOf(nil, 235, 10)
    local last = dmgOf(nil, 235, 1)
    check(last >= 4 * high, "Trump Card's last PP hits five times as hard (200 vs 40)", high .. " -> " .. last)
    local base = dmgOf(nil, 245)
    local boosted = dmgOf(function(b) b.enemy.stages.attack = 3 b.enemy.stages.speed = 1 end, 245)
    check(boosted >= 2 * base, "Punishment: 60 + 20 per raised stage (140 vs 60)", base .. " -> " .. boosted)
  end

  -- Surf finds a diving target and doubles on it
  do
    local b = fresh(SNORLAX, SNORLAX)
    local dive = moveWith(255)
    use(b, b.enemy, b.player, dive)
    check(b.enemy.invulnerable == true, "Dive takes the foe under")
    local surf = moveWith(257)
    use(b, b.player, b.enemy, surf)
    local d1 = 999 - b.enemy.mon.hp
    check(d1 > 0, "Surf reaches a Pokemon underwater", d1)
    local plain = dmgOf(nil, 257)
    check(d1 >= plain * 1.6, "...for double the power", plain .. " -> " .. d1)
  end

  -- Feint fails on a target that is not protecting
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(223))
    check(b.enemy.mon.hp == 999 and failed(b), "Feint fails without a Protect to break")
  end

  -- Sucker Punch fails against a status move, and once the target has moved
  do
    local b = fresh(SNORLAX, SNORLAX)
    b.turnActions = { turn = 1, [b.enemy] = { id = RECOVER, pp = 10 } }
    use(b, b.player, b.enemy, moveWith(248))
    check(b.enemy.mon.hp == 999 and failed(b), "Sucker Punch fails against a status move")
    b = fresh(SNORLAX, SNORLAX)
    b.turnActions = { turn = 1, [b.enemy] = { id = TACKLE, pp = 10 } }
    b.enemy.actedTurn = 1
    use(b, b.player, b.enemy, moveWith(248))
    check(b.enemy.mon.hp == 999 and failed(b), "...and against a target that already moved")
  end

  -- Metal Burst with nothing taken fails
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(227))
    check(b.enemy.mon.hp == 999 and failed(b), "Metal Burst fails with no damage taken this turn")
  end

  -- Last Resort before the other moves were used
  do
    local b = fresh(SNORLAX, SNORLAX)
    local lr = moveWith(246)
    b.player.mon.moves = { { id = lr, pp = 5 }, { id = TACKLE, pp = 5 } }
    use(b, b.player, b.enemy, lr)
    check(b.enemy.mon.hp == 999 and failed(b), "Last Resort fails until every other move was used")
  end

  -- Captivate on the same gender; Oblivious
  do
    local b = fresh(SNORLAX, SNORLAX)
    b.player.mon.gender, b.enemy.mon.gender = "male", "male"
    use(b, b.player, b.enemy, moveWith(265))
    check((b.enemy.stages.spatk or 0) == 0 and said(b, "failed to affect"), "Captivate: same gender fails to affect")
    b = fresh(SNORLAX, SNORLAX)
    b.player.mon.gender, b.enemy.mon.gender = "male", "female"
    b.enemy.abilityOverride = "OBLIVIOUS"
    use(b, b.player, b.enemy, moveWith(265))
    check((b.enemy.stages.spatk or 0) == 0 and said(b, "OBLIVIOUS"), "Captivate: Oblivious has its own line")
  end

  -- Roost: Flying is lost for the turn (a Ground move lands) and back after it
  do
    local b = fresh(PIDGEOT, SNORLAX)
    b.player.mon.hp = 300
    use(b, b.player, b.enemy, moveWith(214))
    local eq = 89
    use(b, b.enemy, b.player, eq)
    check(b.player.mon.hp < 300 + 499, "Earthquake hits a roosting Pidgeot", b.player.mon.hp)
    b:endOfTurn()
    local flying = false
    for _, t in ipairs(b.player.curTypes or {}) do if t == "FLYING" then flying = true end end
    check(flying and not b.player.g4Roost, "...and Flying is back at the end of the turn")
    b = fresh(PIDGEOT, SNORLAX)
    use(b, b.player, b.enemy, moveWith(214))
    check(said(b, "HP is full"), "Roost at full HP: 'HP is full!'")
  end

  -- Gravity: a Flying Pokemon is grounded, Fly is refused, five turns
  do
    local b = fresh(SNORLAX, PIDGEOT)
    use(b, b.player, b.enemy, moveWith(215))
    check(said(b, "couldn't stay airborne"), "Gravity brings a Flying Pokemon down")
    use(b, b.player, b.enemy, 89)
    check(b.enemy.mon.hp < 999, "Earthquake hits a Flying type under Gravity", b.enemy.mon.hp)
    b.queue, b.nextInsert = {}, 0
    local refused = G4.beforeMove(b, b.enemy, b.player, { id = 19, pp = 10 })
    check(refused and said(b, "because of gravity"), "Fly is refused under Gravity")
    for _ = 1, 4 do b:endOfTurn() end
    check(b.g4fx.field.gravity == 1, "four turns later one is left", b.g4fx.field.gravity)
    b.queue, b.nextInsert = {}, 0
    b:endOfTurn()
    check(b.g4fx.field.gravity == nil and said(b, "Gravity returned to normal"), "...and the fifth ends it")
  end

  -- Magnet Rise: Ground moves do nothing, five turns, Levitate fails
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(252))
    use(b, b.enemy, b.player, 89)
    check(b.player.mon.hp == 999, "Earthquake does nothing to a Magnet Rise user")
    for _ = 1, 5 do b:endOfTurn() end
    check(b.player.g4MagnetRise == nil and said(b, "electromagnetism"), "Magnet Rise wears off after five turns")
    b = fresh(SNORLAX, SNORLAX)
    b.player.abilityOverride = "LEVITATE"
    use(b, b.player, b.enemy, moveWith(252))
    check(failed(b), "Magnet Rise fails on Levitate")
  end

  -- Lucky Chant: a forced crit does not land on the chanting side
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(240))
    local opts = G4.damageOpts(b, b.enemy, b.player, Data.moves[TACKLE], {})
    check(opts.forceCrit == false, "Lucky Chant refuses the crit roll")
    for _ = 1, 5 do b:endOfTurn() end
    check(G4.state(b).sides[true].luckyChant == nil and said(b, "Lucky Chant"), "...for five turns")
  end

  -- Tailwind: the slower side moves first, three turns
  do
    local b = fresh(SNORLAX, SNORLAX)
    b.player.curStats = { attack = 100, defense = 100, spatk = 100, spdef = 100, speed = 60, hp = 999 }
    b.enemy.curStats = { attack = 100, defense = 100, spatk = 100, spdef = 100, speed = 100, hp = 999 }
    use(b, b.player, b.enemy, moveWith(225))
    local TurnOrder = require("src.battle.TurnOrder")
    check(TurnOrder.firstMover(b.player, Data.moves[TACKLE], b.enemy, Data.moves[TACKLE], b.rng, nil, b, Data),
          "Tailwind doubles 60 past 100")
    for _ = 1, 3 do b:endOfTurn() end
    check(b.player.bwSpeedMultiplier == nil and said(b, "petered out"), "...and peters out after three turns")
  end

  -- Trick Room toggles
  do
    local b = fresh(SNORLAX, SNORLAX)
    local tr = moveWith(259)
    use(b, b.player, b.enemy, tr)
    use(b, b.player, b.enemy, tr)
    check((b.field.trickRoom or 0) == 0 and said(b, "restored the twisted"), "Trick Room used again puts it back")
  end

  -- Heal Block refuses Recover; Embargo silences the held item
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(236))
    b.queue, b.nextInsert = {}, 0
    check(G4.beforeMove(b, b.enemy, b.player, { id = RECOVER, pp = 10 }) and said(b, "HEAL BLOCK"),
          "Heal Block refuses Recover")
    b = fresh(SNORLAX, SNORLAX)
    b.enemy.mon.item = 234 -- Leftovers
    check(HoldItems.effectOf(b.enemy) == "LEFTOVERS", "Leftovers before Embargo")
    use(b, b.player, b.enemy, moveWith(232))
    check(HoldItems.effectOf(b.enemy) == nil, "...and nothing under it")
    for _ = 1, 5 do b:endOfTurn() end
    check(HoldItems.effectOf(b.enemy) == "LEFTOVERS" and said(b, "can use items again"), "...for five turns")
  end

  -- Aqua Ring heals a sixteenth at the end of the turn
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(251))
    b.player.mon.hp = 500
    b:endOfTurn()
    check(b.player.mon.hp == 500 + math.floor(999 / 16), "Aqua Ring: 999/16 back", b.player.mon.hp)
    use(b, b.player, b.enemy, moveWith(251))
    check(failed(b), "...and a second Aqua Ring fails")
  end

  -- Stealth Rock: a 4x-weak Charizard loses half; Toxic Spikes poison, and a
  -- grounded Poison type absorbs them
  do
    local b = fresh(SNORLAX, CHARIZARD)
    use(b, b.player, b.enemy, moveWith(266))
    b.enemy.mon.hp = 999
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.hp == 999 - math.floor(999 / 2), "Stealth Rock takes half from Charizard", b.enemy.mon.hp)
    use(b, b.player, b.enemy, moveWith(266))
    check(failed(b), "...and a second layer fails")
    b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(249))
    use(b, b.player, b.enemy, moveWith(249))
    use(b, b.player, b.enemy, moveWith(249))
    check(failed(b), "a third layer of Toxic Spikes fails")
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.status == "PSN" and b.enemy.toxicCounter ~= nil, "two layers badly poison", tostring(b.enemy.toxicCounter))
    b = fresh(SNORLAX, MUK)
    use(b, b.player, b.enemy, moveWith(249))
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.status == nil and G4.state(b).sides[false].toxicSpikes == nil, "a Poison type absorbs them")
    b = fresh(SNORLAX, SKARMORY)
    use(b, b.player, b.enemy, moveWith(249))
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.status == nil and G4.state(b).sides[false].toxicSpikes == 1, "a Flying type is not touched")
  end

  -- Healing Wish: the replacement is fully healed
  do
    local b = fresh(SNORLAX, SNORLAX)
    G4.state(b).sides[false].healingWish = "wish"
    b.enemy.mon.hp, b.enemy.mon.status = 100, "BRN"
    b.queue, b.nextInsert = {}, 0
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.hp == 999 and b.enemy.mon.status == nil and said(b, "healing wish came true"),
          "Healing Wish heals the Pokemon sent in")
  end

  -- Struggle: the cartridge's move 165, typeless, a quarter back
  do
    local b = fresh(SNORLAX, GENGAR)
    b.queue, b.nextInsert = {}, 0
    b:performMove(b.player, b.enemy, { id = "STRUGGLE", pp = 1, struggle = true })
    check(b.enemy.mon.hp < 999 and b.player.mon.hp == 999 - 249, "Struggle hits a Ghost and costs a quarter",
          b.enemy.mon.hp .. "/" .. b.player.mon.hp)
  end

  -- Chatter from anything but Chatot never confuses
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(267))
    check(b.enemy.confusedTurns == nil, "Chatter from a non-Chatot does not confuse")
  end

  -- Psycho Shift onto a statused target fails
  do
    local b = fresh(SNORLAX, SNORLAX)
    b.player.mon.status, b.enemy.mon.status = "BRN", "PAR"
    use(b, b.player, b.enemy, moveWith(234))
    check(failed(b) and b.player.mon.status == "BRN", "Psycho Shift fails on a statused target")
  end

  -- Pluck: Sticky Hold keeps the berry
  do
    local b = fresh(SNORLAX, SNORLAX)
    b.enemy.mon.item = 158
    b.enemy.abilityOverride = "STICKY_HOLD"
    use(b, b.player, b.enemy, moveWith(224))
    check(b.enemy.mon.item == 158 and said(b, "STICKY HOLD"), "Pluck: Sticky Hold keeps the berry")
  end

  -- -------------------------------------------------------------------------
  -- 2b. THE LEFTOVERS: U-turn through a knockout, Trick Room's resort, Baton
  -- Pass's full carry, hazard grounding, Embargo in the bag, Heal Block at
  -- the menu, the escort and the two trainer ids
  -- -------------------------------------------------------------------------
  local function indexOf(b, needle)
    for i, l in ipairs(linesOf(b)) do if l:find(needle, 1, true) then return i end end
    return nil
  end
  local UTURN, BATON, SPIKES = moveWith(228), moveWith(127), moveWith(112)
  local IRON_BALL, POTION, X_ATTACK, GUARD_SPEC, POKE_DOLL, POKE_BALL = 278, 17, 57, 55, 63, 4

  -- U-TURN THROUGH A KNOCKOUT (subscript_attack_then_switch_out): the user
  -- still goes when the foe has someone to send in, and goes FIRST -- its
  -- switch is the hit's side effect, the "fainted!" line and the foe's refill
  -- come after
  do
    local b = fresh(SNORLAX, SNORLAX)
    local spare = Pokemon.new(Data, SNORLAX, 50)
    b.enemyParty = { b.enemy.mon, spare }
    b.enemy.mon.hp = 1
    local user, foe = b.player, b.enemy
    use(b, b.player, b.enemy, UTURN)
    local back, down = indexOf(b, "went back"), indexOf(b, "fainted")
    check(b.player ~= user and b.player.mon == Game.save.party[2], "U-turn KO: the user still switches out",
          table.concat(linesOf(b), " | "))
    check(back and down and back < down, "...before the foe's 'fainted!'", tostring(back) .. " / " .. tostring(down))
    check(b.enemy == foe and foe.mon.hp == 0, "...and the foe's slot is not refilled yet (that is the turn's end)")
    -- a knockout that ends the battle (a wild foe, nobody behind it): stays
    b = fresh(SNORLAX, SNORLAX)
    b.enemy.mon.hp = 1
    user = b.player
    use(b, b.player, b.enemy, UTURN)
    check(b.player == user and not said(b, "went back"), "U-turn KO of the last foe: the user stays (CheckBlackOut)")
    -- the foe's U-turn knocking out the player's Pokemon: the foe switches
    b = fresh(SNORLAX, SNORLAX)
    b.enemyParty = { b.enemy.mon, Pokemon.new(Data, SNORLAX, 50) }
    b.player.mon.hp = 1
    local was = b.enemy
    use(b, b.enemy, b.player, UTURN)
    check(b.enemy ~= was and b.enemy.mon == b.enemyParty[2], "the foe's U-turn KO still switches the foe out")
  end

  -- TRICK ROOM RESORTS THE REST OF THE TURN (MoveEnd ->
  -- BattleSystem_SortMonActionOrder): the move sets the flag, and the rows
  -- still waiting are re-bubbled by speed -- now slowest first -- while a
  -- switch keeps its slot and a Quick Claw winner stays in front
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(259))
    check(b.g4TrickRoomResort == true, "Trick Room marks the turn for a resort")
    local function mk(speed, isPlayer)
      local x = {}
      for k, v in pairs(b.player) do x[k] = v end
      x.isPlayer = isPlayer
      x.curStats = { attack = 100, defense = 100, spatk = 100, spdef = 100, speed = speed, hp = 999 }
      x.stages = {}
      return x
    end
    local A, F, M, S, W = mk(200, true), mk(150, false), mk(100, true), mk(50, false), mk(10, true)
    local function rows()
      return { { A, nil, { id = moveWith(259) } }, { F, nil, { id = TACKLE } },
               { M, nil, { id = TACKLE } }, { W, nil, { special = "aiSwitch" } },
               { S, nil, { id = TACKLE } } }
    end
    local order = rows()
    G4.reorderRest(b, order, 2)
    check(order[2][1] == S and order[3][1] == M and order[5][1] == F and order[4][1] == W,
          "...the waiting moves now go slowest first; the switch keeps its slot")
    check(b.g4TrickRoomResort == nil, "...once")
    order = rows()
    G4.reorderRest(b, order, 2)
    check(order[2][1] == F, "no Trick Room this action: the order stands")
    b.g4TrickRoomResort = true
    order = rows()
    order.claw = F
    G4.reorderRest(b, order, 2)
    check(order[2][1] == F and order[3][1] == S, "a Quick Claw that won this turn keeps the front")
    -- Trick Room used again (back to normal) resorts as well: fastest first
    b.field.trickRoom = 0
    b.g4TrickRoomResort = true
    order = { { A, nil, { id = TACKLE } }, { S, nil, { id = TACKLE } }, { F, nil, { id = TACKLE } } }
    G4.reorderRest(b, order, 2)
    check(order[2][1] == F and order[3][1] == S, "restoring the dimensions resorts too (fastest first again)")
  end

  -- BATON PASS (subscript_baton_pass, BattleSystem_UpdateAfterSwitch): the user
  -- leaves, and the newcomer keeps Aqua Ring, Magnet Rise, Embargo, Heal
  -- Block, Ingrain, Focus Energy, Curse, Mean Look, Gastro Acid, Power Trick,
  -- Lock-On, Perish Song, the stages, confusion and the substitute
  do
    local b = fresh(SNORLAX, SNORLAX)
    local u = b.player
    u.g4AquaRing, u.g4MagnetRise, u.g4Embargo, u.g4HealBlock = true, 3, 2, 4
    u.ingrained, u.focusEnergy, u.cursed, u.trapped = true, true, true, true
    u.g4Suppressed, u.abilityOverride, u.g4PowerTrick = true, false, true
    u.lockedOn, u.perishTurns, u.confusedTurns, u.substituteHP = b.enemy, 2, 3, 50
    u.stages.attack = 2
    b.enemy.lockedOn = u
    use(b, b.player, b.enemy, BATON)
    local n = b.player
    check(n ~= u and n.mon == Game.save.party[2], "Baton Pass switches the user out", table.concat(linesOf(b), " | "))
    check(n.g4AquaRing and n.g4MagnetRise == 3 and n.g4Embargo == 2 and n.g4HealBlock == 4,
          "...Aqua Ring, Magnet Rise, Embargo and Heal Block go across with their turns")
    check(n.ingrained and n.focusEnergy and n.cursed and n.trapped, "...Ingrain, Focus Energy, Curse and Mean Look too")
    check(n.g4Suppressed and n.abilityOverride == false, "...and Gastro Acid")
    check(n.curStats.attack == n.mon.stats.defense and n.curStats.defense == n.mon.stats.attack
          and n.mon.stats.attack ~= n.mon.stats.defense, "...a passed Power Trick swaps the newcomer's own stats")
    check(n.stages.attack == 2 and n.confusedTurns == 3 and n.substituteHP == 50 and n.perishTurns == 2
          and n.lockedOn == b.enemy, "...the stages, confusion, substitute, Perish Song and its Lock-On")
    check(b.enemy.lockedOn == n, "...and the foe's Lock-On now points at the newcomer")
    check(not said(b, "passed the baton"), "no 'passed the baton' line (the cartridge has none)")
    -- the foe's
    b = fresh(SNORLAX, SNORLAX)
    b.enemyParty = { b.enemy.mon, Pokemon.new(Data, SNORLAX, 50) }
    b.enemy.g4AquaRing, b.enemy.g4MagnetRise = true, 4
    local was = b.enemy
    use(b, b.enemy, b.player, BATON)
    check(b.enemy ~= was and b.enemy.g4AquaRing and b.enemy.g4MagnetRise == 4, "the foe's Baton Pass carries them too")
    -- nobody to send in
    b = fresh(SNORLAX, SNORLAX, false)
    u = b.player
    use(b, b.player, b.enemy, BATON)
    check(b.player == u and failed(b), "Baton Pass with an empty bench fails")
  end

  -- SPIKES / TOXIC SPIKES / STEALTH ROCK GROUNDING (subscript_hazards_check)
  do
    local function spikesOn(foeSp, setup)
      local b = fresh(SNORLAX, foeSp)
      use(b, b.player, b.enemy, SPIKES)
      b.enemy.mon.hp = 999
      if setup then setup(b, b.enemy) end
      b.queue, b.nextInsert = {}, 0
      b:abilitySwitchIn(b.enemy)
      return 999 - b.enemy.mon.hp, b
    end
    local eighth = math.floor(999 / 8)
    check(spikesOn(SNORLAX) == eighth, "Spikes: an eighth on a grounded Pokemon", spikesOn(SNORLAX))
    check(spikesOn(PIDGEOT) == 0, "Spikes: a Flying type floats over them")
    check(spikesOn(PIDGEOT, function(b) G4.state(b).field.gravity = 5 end) == eighth,
          "Spikes under Gravity: the Flying type comes down onto them")
    check(spikesOn(SNORLAX, function(b, x) x.abilityOverride = "LEVITATE"; G4.state(b).field.gravity = 5 end) == eighth,
          "...and so does a Levitate Pokemon")
    check(spikesOn(SNORLAX, function(b, x) G4.state(b); x.g4MagnetRise = 3 end) == 0, "Spikes: Magnet Rise lifts it off")
    check(spikesOn(SNORLAX, function(b, x) x.abilityOverride = "MAGIC_GUARD" end) == 0, "Spikes: Magic Guard takes nothing")
    check(spikesOn(PIDGEOT, function(b, x) x.mon.item = IRON_BALL end) == eighth,
          "Spikes: an Iron Ball grounds a Flying type")
    check(spikesOn(PIDGEOT, function(b, x) x.mon.item = IRON_BALL; x.abilityOverride = "KLUTZ" end) == 0,
          "...but not under Klutz")
    check(spikesOn(PIDGEOT, function(b, x) G4.state(b); x.mon.item = IRON_BALL; x.g4Embargo = 3 end) == 0,
          "...nor under Embargo")
    -- Toxic Spikes and Stealth Rock agree
    local b = fresh(SNORLAX, PIDGEOT)
    use(b, b.player, b.enemy, moveWith(249))
    G4.state(b).field.gravity = 5
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.status == "PSN", "Toxic Spikes under Gravity poison a Flying type")
    b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(249))
    b.enemy.g4MagnetRise = 3
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.status == nil, "Toxic Spikes miss a Magnet Rise user")
    b = fresh(SNORLAX, SNORLAX)
    use(b, b.player, b.enemy, moveWith(266))
    b.enemy.g4MagnetRise = 3
    b.enemy.mon.hp = 999
    b:abilitySwitchIn(b.enemy)
    check(b.enemy.mon.hp == 999 - math.floor(999 / 8), "Stealth Rock still hits a Magnet Rise user")
  end

  -- EMBARGO IN THE BAG (battle_bag.c TryUseItem, battle_party.c
  -- PartyUseItemScreen)
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.enemy, b.player, moveWith(232))
    check(b.player.g4Embargo == 5, "Embargo on the player's Pokemon")
    local why = G4.embargoRefusal(b, b.player.mon, POTION)
    check(why and why:find("EMBARGO", 1, true) and why:find(b.player.name, 1, true),
          "a Potion on the Pokemon under Embargo is refused", why)
    check(G4.embargoRefusal(b, Game.save.party[2], POTION) == nil, "...one on the bench is not")
    check(G4.embargoRefusal(b, nil, X_ATTACK) ~= nil, "an X Attack (battle items) is refused")
    check(G4.embargoRefusal(b, nil, GUARD_SPEC) == nil, "...Guard Spec. is not")
    check(G4.embargoRefusal(b, nil, POKE_DOLL) == nil, "...nor a Poke Doll (battle use 3)")
    check(G4.embargoRefusal(b, nil, POKE_BALL) == nil, "...nor a Poke Ball")
    -- through the bag itself: refused, the item kept, the turn not spent
    local Bag = require("src.inventory.Bag")
    Bag.add(Game.save, X_ATTACK, 1)
    local before = (Game.save.inventory or {})[X_ATTACK]
    local pushed, spent = {}, false
    local realStack, realUsed = Game.stack, b.itemUsed
    Game.stack = { push = function(_, s) pushed[#pushed + 1] = s end, top = function() return pushed[#pushed] end,
                   pop = function() table.remove(pushed) end }
    b.itemUsed = function() spent = true end
    local ok, err = pcall(require("src.ui.BagMenu").useItem, Game, b, X_ATTACK,
                          { items = {}, close = function() end })
    Game.stack, b.itemUsed = realStack, realUsed
    local after = (Game.save.inventory or {})[X_ATTACK]
    check(ok and #pushed == 1 and not spent and before ~= nil and after == before
          and (b.player.stages.attack or 0) == 0,
          "the bag refuses the X Attack: one message, item kept, no turn",
          tostring(err) .. " pushed=" .. #pushed .. " " .. tostring(before) .. "->" .. tostring(after))
  end

  -- HEAL BLOCK AT THE MENU (BattleSystem_CanUseMove: CHECK_INVALID_HEAL_BLOCK)
  do
    local b = fresh(SNORLAX, SNORLAX)
    use(b, b.enemy, b.player, moveWith(236))
    local who = b.player
    who.curMoves = { { id = RECOVER, pp = 5 }, { id = TACKLE, pp = 5 } }
    local line = G4.menuRefusal(b, who, Data.moves[RECOVER])
    check(line and line:find("HEAL BLOCK", 1, true), "Heal Block refuses Recover at the menu", line)
    check(G4.menuRefusal(b, who, Data.moves[TACKLE]) == nil, "...not Tackle")
    -- the menu itself: A on Recover says why and asks again; no turn runs
    local turn = b.turnCount
    b.queue, b.nextInsert = {}, 0
    b.phase, b.moveIndex, b.gen4CursorActive = "moveSelect", 1, true
    local realInput = Game.input
    Game.input = { wasPressed = function(_, k) return k == "a" end, isDown = function() return false end,
                   wasReleased = function() return false end }
    b.game.input = Game.input
    local ok, err = pcall(b.update, b, 1 / 60)
    Game.input = realInput
    b.game.input = realInput
    check(ok and said(b, "HEAL BLOCK") and b.turnCount == turn and b.afterQueue == "menu",
          "A on Recover under Heal Block: the line, the menu again, no turn", tostring(err))
    -- only blocked moves left: Struggle, for the player and the AI
    who.curMoves = { { id = RECOVER, pp = 5 } }
    check(not b:playerHasPP(who), "...a Pokemon whose only move is blocked has none to choose (Struggle)")
    b.enemy.g4HealBlock = 3
    b.enemy.curMoves = { { id = RECOVER, pp = 5 }, { id = TACKLE, pp = 5 } }
    local TrainerAI = require("src.battle.TrainerAI")
    local never = true
    for i = 1, 20 do
      local pick = TrainerAI.chooseMove(b.enemy, function(lo, hi) return lo + (i % (hi - lo + 1)) end, b)
      if pick and pick.id == RECOVER then never = false end
    end
    check(never, "the AI never picks a heal-blocked move")
    b.enemy.curMoves = { { id = RECOVER, pp = 5 } }
    local pick = TrainerAI.chooseMove(b.enemy, b.rng, b)
    check(pick and pick.struggle, "...and Struggles when that is all it has")
    b.g4fx.field.gravity = 5
    check(G4.menuRefusal(b, b.player, Data.moves[19]) ~= nil, "Gravity refuses Fly at the menu as well")
  end

  -- THE TWO TRAINER IDS AND THE ESCORT (Encounter_NewVsTrainer): only two
  -- DIFFERENT trainers put the partner on the field
  do
    local C = require("src.script.Commands")
    local G4C = require("src.script.Gen4Commands")
    local Follower = require("src.world.Gen4Follower")
    local seen
    local real = C.start_battle
    C.start_battle = function(_, kind, id, lvl, opts) seen = { kind = kind, id = id, opts = opts or {} } end
    local ctx = { game = Game, save = Game.save }
    -- any three trainers with a team in this cache (Platinum's and HGSS's
    -- numbering differ); the escort is the third
    local withTeam = {}
    for id = 1, 900 do
      local rec = Data.trainers and Data.trainers[id]
      if rec and type(rec.parties) == "table" and type(rec.parties[1]) == "table" and rec.parties[1][1] then
        withTeam[#withTeam + 1] = id
      end
      if #withTeam >= 3 then break end
    end
    local twin, a, b2, escortId = withTeam[1], withTeam[1], withTeam[2], withTeam[3]
    local function withPartner(on)
      Follower.setPartner(Game.save, on)
      Game.save.vars = Game.save.vars or {}
      G4C.setVar(Game.save, G4C.VAR_PARTNER_TRAINER_ID, on and escortId or 0)
    end
    withPartner(true)
    local okE, err = pcall(function()
      seen = nil; C.g4_start_battle(ctx, twin, twin)
      check(seen and seen.opts.double and seen.opts.ally == nil and seen.opts.trainerBKey == nil,
            "a same-id double with an escort along: a double, the escort NOT fielded, no second party")
      seen = nil; C.g4_start_battle(ctx, a, 0)
      check(seen and seen.opts.ally == nil, "a lone trainer with an escort along: the escort not fielded")
      seen = nil; C.g4_start_battle(ctx, a, b2)
      check(seen and seen.opts.ally and seen.opts.ally.escort and seen.opts.trainerBKey == b2,
            "two different trainers with an escort along: she fights beside you")
    end)
    check(okE, "the escort cases ran", tostring(err))
    withPartner(false)
    C.start_battle = real
  end

  -- -------------------------------------------------------------------------
  -- 2c. SWITCHING IN A DOUBLE (U-turn, Baton Pass, Roar / Whirlwind --
  -- src/battle/Gen4SwitchOut.lua) AND SPIKES' THREE LAYERS
  -- -------------------------------------------------------------------------
  do
    local POS = BattleState.POS
    local ROAR = moveWith(28)
    local BS_make = BattleState.makeBattler
    -- a trainer double: the player's party of `nOwn`, the foe's of `nFoe`
    local function freshDouble(nOwn, nFoe)
      local b = fresh(SNORLAX, SNORLAX)
      for i = 2, nOwn do Game.save.party[i] = Pokemon.new(Data, i == 3 and PIDGEOT or SNORLAX, 50) end
      for i = nOwn + 1, 6 do Game.save.party[i] = nil end
      b.kind, b.trainerLabel, b.double = "trainer", "FOE", true
      b.enemyParty = { b.enemy.mon }
      for i = 2, nFoe do b.enemyParty[i] = Pokemon.new(Data, i == 3 and GENGAR or SNORLAX, 50) end
      if Game.save.party[2] then b:placeBattler(POS.PLAYER_RIGHT, BS_make(Data, Game.save.party[2], true, Game.save)) end
      if b.enemyParty[2] then b:placeBattler(POS.OPPONENT_RIGHT, BS_make(Data, b.enemyParty[2], false)) end
      b:syncSides()
      for p = 0, 3 do
        local x = b:battlerAt(p) or { mon = { stats = {} } }
        x.abilityOverride = false
        x.mon.item, x.mon.status = nil, nil
        x.mon.stats.hp, x.mon.hp = 999, 999
      end
      for _, m in ipairs(Game.save.party) do m.stats.hp, m.hp = 999, 999 end
      for _, m in ipairs(b.enemyParty) do m.stats.hp, m.hp = 999, 999 end
      b.queue, b.nextInsert = {}, 0
      return b
    end
    local okD, errD = pcall(function()
      -- the player's U-turn from the RIGHT slot: that slot is refilled, the
      -- left one is not touched (TryReplaceFaintedMon / ShowParty for the
      -- attacker's own slot)
      local b = freshDouble(3, 3)
      local left, user = b:battlerAt(POS.PLAYER_LEFT), b:battlerAt(POS.PLAYER_RIGHT)
      use(b, user, b:battlerAt(POS.OPPONENT_LEFT), UTURN)
      local n = b:battlerAt(POS.PLAYER_RIGHT)
      check(n ~= user and n.mon == Game.save.party[3] and b:battlerAt(POS.PLAYER_LEFT) == left,
            "double: the right-hand U-turn user goes and the bench refills ITS slot", table.concat(linesOf(b), " | "))
      check(said(b, "went back"), "...'went back' is said")
      -- ...and its chosen action is gone with it
      local hp = b.enemy.mon.hp
      b.queue, b.nextInsert = {}, 0
      b:executeAction(user, b.enemy, { id = TACKLE, pp = 10 })
      check(b.enemy.mon.hp == hp and #linesOf(b) == 0, "...the withdrawn battler's row does not run")

      -- the player's Baton Pass from the LEFT slot carries into the left slot
      b = freshDouble(3, 3)
      user = b:battlerAt(POS.PLAYER_LEFT)
      user.stages.attack, user.g4AquaRing, user.confusedTurns = 2, true, 3
      use(b, user, b.enemy, BATON)
      n = b:battlerAt(POS.PLAYER_LEFT)
      check(n ~= user and n.mon == Game.save.party[3] and n.stages.attack == 2 and n.g4AquaRing and n.confusedTurns == 3,
            "double: Baton Pass switches and carries into the user's slot", table.concat(linesOf(b), " | "))
      check(b:battlerAt(POS.PLAYER_RIGHT).mon == Game.save.party[2], "...the partner stays")
      -- nobody left who is not already out: it fails
      b = freshDouble(2, 3)
      user = b:battlerAt(POS.PLAYER_LEFT)
      use(b, user, b.enemy, BATON)
      check(b:battlerAt(POS.PLAYER_LEFT) == user and failed(b), "double: Baton Pass with only the partner left fails")

      -- the foe's side: U-turn from the right, Baton Pass from the left
      b = freshDouble(3, 3)
      user = b:battlerAt(POS.OPPONENT_RIGHT)
      local foeLeft = b.enemy
      use(b, user, b.player, UTURN)
      n = b:battlerAt(POS.OPPONENT_RIGHT)
      check(n ~= user and n.mon == b.enemyParty[3] and b.enemy == foeLeft,
            "double: the foe's right-hand U-turn brings its third Pokemon into that slot", table.concat(linesOf(b), " | "))
      b = freshDouble(3, 3)
      user = b.enemy
      user.stages.defense, user.g4MagnetRise = -1, 4
      use(b, user, b.player, BATON)
      n = b:battlerAt(POS.OPPONENT_LEFT)
      check(n ~= user and b.enemy == n and n.mon == b.enemyParty[3] and n.stages.defense == -1 and n.g4MagnetRise == 4,
            "double: the foe's Baton Pass carries into its left slot", table.concat(linesOf(b), " | "))

      -- the player's party list: an on-field pick is refused and the list
      -- opens again; a bench pick goes into the user's slot
      b = freshDouble(3, 3)
      b.bwAutoSwitch = nil
      local realStack = Game.stack
      Game.stack = Game.stack or {}
      b.game = Game
      b.buildScreen = function(_, id, opts) return opts end
      user = b:battlerAt(POS.PLAYER_RIGHT)
      use(b, user, b.enemy, UTURN)
      local function nextUi()
        for i, item in ipairs(b.queue) do
          if item.ui then table.remove(b.queue, i) return item.ui() end
        end
      end
      local function runActs()
        local guard = 0
        while guard < 20 do
          guard = guard + 1
          local found
          for i, item in ipairs(b.queue) do
            if item.fn then found = i break end
          end
          if not found then return end
          local item = table.remove(b.queue, found)
          b.nextInsert = 0
          item.fn()
          if nextUi then
            for _, it in ipairs(b.queue) do if it.ui then return end end
          end
        end
      end
      local opts = nextUi()
      check(opts and opts.forceSwitch, "double, player's U-turn: the party list opens (no cancel)")
      if opts then
        b.queue, b.nextInsert = {}, 0
        opts.onSwitch(Game.save.party[1])
        check(said(b, "already") and b:battlerAt(POS.PLAYER_RIGHT) == user,
              "...the left slot's Pokemon is refused", table.concat(linesOf(b), " | "))
        b.queue = { { fn = function() end } }
        -- the re-ask act queued behind the list
      end
      b = freshDouble(3, 3)
      b.bwAutoSwitch = nil
      b.game = Game
      b.buildScreen = function(_, id, o) return o end
      user = b:battlerAt(POS.PLAYER_RIGHT)
      use(b, user, b.enemy, UTURN)
      opts = nextUi()
      if opts then
        opts.onSwitch(Game.save.party[1])
        runActs()
        local again = nextUi()
        check(again and again ~= opts, "...and the list opens again")
        if again then again.onSwitch(Game.save.party[3]) end
      end
      check(b:battlerAt(POS.PLAYER_RIGHT).mon == Game.save.party[3], "...a bench pick goes into the user's slot")
      Game.stack = realStack

      -- ROAR / WHIRLWIND in a trainer double: a random one that is not on
      -- the field, into the target's slot; "was dragged out!"
      b = freshDouble(3, 3)
      local target = b:battlerAt(POS.OPPONENT_RIGHT)
      use(b, b.player, target, ROAR)
      n = b:battlerAt(POS.OPPONENT_RIGHT)
      check(n ~= target and n.mon == b.enemyParty[3] and said(b, "dragged out") and not said(b, "with-"),
            "double: Whirlwind drags the foe's third Pokemon into the right slot", table.concat(linesOf(b), " | "))
      -- cntMax 2: a fainted partner still counts as one of the two out
      b = freshDouble(3, 3)
      b.enemyParty[2].hp = 0
      target = b.enemy
      use(b, b.player, target, ROAR)
      check(b.enemy == target and failed(b), "double: with only two able (the partner fainted) it fails (cnt <= 2)")
      -- on the player's side
      b = freshDouble(3, 3)
      target = b:battlerAt(POS.PLAYER_LEFT)
      use(b, b.enemy, target, ROAR)
      n = b:battlerAt(POS.PLAYER_LEFT)
      check(n ~= target and n.mon == Game.save.party[3] and said(b, "dragged out") and not said(b, "Go!"),
            "double: the foe's Whirlwind drags the player's third Pokemon in", table.concat(linesOf(b), " | "))
      -- a trainer single
      b = freshDouble(1, 2)
      b.double = nil
      b.sides[1].battlers[2], b.sides[2].battlers[2] = nil, nil
      b:syncSides()
      target = b.enemy
      use(b, b.player, target, ROAR)
      check(b.enemy ~= target and b.enemy.mon == b.enemyParty[2] and said(b, "dragged out"),
            "single: a trainer's Pokemon is dragged out (not 'unaffected')", table.concat(linesOf(b), " | "))
      local hp2 = b.player.mon.hp
      b.queue, b.nextInsert = {}, 0
      b:executeAction(target, b.player, { id = TACKLE, pp = 10 })
      check(b.player.mon.hp == hp2, "...and the dragged-off Pokemon's chosen move does not run")
      b = freshDouble(1, 1)
      b.double = nil
      b.sides[1].battlers[2], b.sides[2].battlers[2] = nil, nil
      b:syncSides()
      target = b.enemy
      use(b, b.player, target, ROAR)
      check(b.enemy == target and failed(b), "single: nobody behind it -- fails")
      -- Ingrain and Suction Cups hold it
      b = freshDouble(3, 3)
      b.enemy.ingrained = true
      target = b.enemy
      use(b, b.player, target, ROAR)
      check(b.enemy == target and said(b, "roots"), "Ingrain anchors it")
      b = freshDouble(3, 3)
      b.enemy.abilityOverride = "SUCTION_CUPS"
      target = b.enemy
      use(b, b.player, target, ROAR)
      check(b.enemy == target and said(b, "SUCTION CUPS"), "Suction Cups anchors it")
      -- a wild battle: WhirlwindCheck, then the battle ends with no line
      b = fresh(SNORLAX, SNORLAX)
      use(b, b.player, b.enemy, ROAR)
      check(b.result == "run", "wild: Whirlwind ends the battle")
      b = fresh(SNORLAX, SNORLAX)
      b.player.mon.level, b.enemy.mon.level = 5, 100
      b.rng = function(a) return a end
      use(b, b.player, b.enemy, ROAR)
      check(b.result == nil and failed(b), "wild: a low roll against a higher level fails (WhirlwindCheck)")
    end)
    check(okD, "the double-switch cases ran", tostring(errD))

    -- SPIKES' LAYERS (BtlCmd_TrySpikes / BtlCmd_CheckSpikes): three, then
    -- "But it failed!"; the arrival takes maxHP / ((5 - layers) * 2)
    local function layered(n)
      local b = fresh(SNORLAX, SNORLAX)
      for _ = 1, n do use(b, b.player, b.enemy, SPIKES) end
      b.enemy.mon.hp = 999
      b.queue, b.nextInsert = {}, 0
      b:abilitySwitchIn(b.enemy)
      return 999 - b.enemy.mon.hp, b
    end
    check(layered(1) == math.floor(999 / 8), "Spikes x1: an eighth", layered(1))
    check(layered(2) == math.floor(999 / 6), "Spikes x2: a sixth", layered(2))
    check(layered(3) == math.floor(999 / 4), "Spikes x3: a quarter", layered(3))
    local b = fresh(SNORLAX, SNORLAX)
    for _ = 1, 3 do use(b, b.player, b.enemy, SPIKES) end
    check(not failed(b), "...the third layer lands")
    use(b, b.player, b.enemy, SPIKES)
    check(failed(b) and b:sideOf(b.enemy).spikes == 3, "...a fourth fails")
  end

  -- -------------------------------------------------------------------------
  -- 3. NOTHING SAID IT WAS NOT IMPLEMENTED
  -- -------------------------------------------------------------------------
  check(#warnings == 0, "no 'not implemented' warning", table.concat(warnings, "; "))

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
