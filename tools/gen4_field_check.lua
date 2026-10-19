-- tools/gen4_field_check.lua -- Platinum / HGSS field features against the
-- decomps: what the 2026-10-18 field audit fixed.
--
--   python tools/run_lua_check.py tools/gen4_field_check.lua
--
-- Pure-logic checks (no install needed):
--   * scripted NPC speed (scriptStepLen) and movement waits in field frames
--   * fishing: the cast and the bite run their next state in the same frame
--   * Headbutt / Rock Smash: Repel does not apply, lead abilities do
--   * the HGSS Dowsing MCHN's search, nearest item and reading tiers
--   * HGSS phone rematches (GetPhoneBookRematch's ladder)
--   * bike / surf music on any map (FieldBGM_GetEffective)
--   * Escape Rope's recorded point (main matrix -> elsewhere, +1 facing north)
--   * the rods' partner / Rocket-disguise refusals
--   * the Cycling Road roll (bridge bit, idle bike, road bit)
--   * HGSS's waterfall ride profile and the descent's trigger
--   * the Ruins of Alph chamber walls (Flash, Escape Rope, Water Stone)
--   * Headbutt on the border forest (land 0xD0)
--   * the obstacle animations' kinds and the Headbutt camera jolt
--   * "can I have your number?" (LoadPhoneDat and its kin)
--   * HGSS's Flash light (weather 12 keeps the dark, 4x the light)
--   * Platinum's Vs. Seeker spin and the honey tree's shake value
--   * Platinum's Cut / Rock Smash art, the HM cut-in's task, the Strength
--     push, Rock Climb, and FOG / Defog's thinning
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Gen 4 field features')
local Version = require('src.core.GameVersion')
Version.set('platinum')

-- ---------------------------------------------------------------- movement
do
  local X = require('src.script.Gen4MoveExec')
  T.eq(X.waitTicks(8, 1), 16, 'WAIT_8 lasts 16 engine ticks (8 field frames)')
  T.eq(X.waitTicks(1, 3), 6, 'three WAIT_1 last 6 ticks')
  T.eq(X.waitTicks(32, 1), 64, 'WAIT_32 lasts 64 ticks')
  local npc, player = { stepFrames = 16 }, {}
  local ow = { player = player }
  X.setStep(npc, ow, 0.5)
  T.eq(npc.scriptStepLen, 8, 'WALK_FAST NPC step is 8 ticks')
  X.setStep(npc, ow, 0.25)
  T.eq(npc.scriptStepLen, 4, 'WALK_FASTER NPC step is 4 ticks')
  X.setStep(npc, ow, 2.0)
  T.eq(npc.scriptStepLen, 32, 'WALK_SLOW NPC step is 32 ticks')
  X.setStep(npc, ow, 1.0)
  T.eq(npc.scriptStepLen, nil, 'a normal step clears the scripted length')
  X.setStep(player, ow, 0.5)
  T.eq(player.scriptStepLen, nil, 'the player keeps stepFramesCur, not scriptStepLen')
  -- the NPC walker reads it
  local NPC = require('src.world.NPC')
  T.check(NPC ~= nil, 'NPC module loads')
end

-- ----------------------------------------------------------------- fishing
do
  local Task = require('src.world.Gen4FishingTask')
  local function task(state)
    local t = setmetatable({ game = { data = {}, save = { party = {} } },
      ow = { player = { facing = 'down', cellX = 0, cellY = 0 } }, rod = 'old',
      enc = { species = 129, level = 5 }, state = state, counter = 0,
      rng = function(a) return a end }, Task)
    return t
  end
  local t = task('cast')
  t.counter = 33
  t:frame(false)
  T.eq(t.state, 'waitFish', 'cast frame 34 hands over to WaitForFish')
  T.eq(t.delay, 29, 'and the wait counts down in that same frame (30 -> 29)')
  T.eq(t.hook, 45, 'the Old Rod window is 45 frames')
  local n = task('cast'); n.enc = nil; n.counter = 33
  n:frame(false)
  T.eq(n.state, 'waitNoFish', 'no bite: WaitForNoFish')
  T.eq(n.counter, 119, 'the no-bite wait counts its first frame on the cast frame')
  local b = task('waitFish'); b.delay, b.hook = 1, 45
  b:frame(false)
  T.eq(b.state, 'checkReel', 'the bite hands over to CheckForReelInFish')
  T.eq(b.hook, 44, 'and the window spends its first frame on the bite (A on N-1 frames)')
end

-- ---------------------------------------------------- headbutt / rock smash
do
  local FE = require('src.script.Gen4FieldEncounters')
  local slots = {}
  for i = 1, 6 do slots[i] = { species = 165, minLevel = 3, maxLevel = 3 } end
  local save = { repelSteps = 100, party = { { species = 25, level = 50, abilitySlot = 1 } } }
  local data = { pokemon = { [25] = { abilities = { 'STATIC' }, types = { 'ELECTRIC' } },
                              [165] = { types = { 'BUG', 'FLYING' } } } }
  package.loaded['src.pokemon.Gen4Forms'] = { definition = function(d, mon) return d.pokemon[mon.species] end }
  local ctx = { game = { data = data }, save = save }
  local enc = FE.headbutt(ctx, slots)
  T.check(enc and enc.species == 165 and enc.level == 3,
    'Headbutt ignores Repel (a L3 Ledyba under a L50 lead with Repel on)')
  local smash = FE.rockSmash(ctx, { { species = 74, minLevel = 5, maxLevel = 5 }, { species = 74, minLevel = 5, maxLevel = 5 } })
  T.check(smash and smash.species == 74, 'Rock Smash ignores Repel')
  data.pokemon[25].abilities = { 'ILLUMINATE' }
  T.eq(FE.rockSmashRate(ctx, 30), 60, 'Illuminate doubles the Rock Smash rate')
  T.eq(FE.rockSmashRate(ctx, 80), 100, 'capped at 100')
  data.pokemon[25].abilities = { 'STENCH' }
  T.eq(FE.rockSmashRate(ctx, 30), 15, 'Stench halves it')
  -- Keen Eye turns away half of what is 5+ levels below a lead above 5
  data.pokemon[25].abilities = { 'KEEN_EYE' }
  local saved = love.math.random
  love.math.random = function(a) return a end   -- every coin lands on 0
  T.eq(FE.headbutt(ctx, slots), nil, 'Keen Eye turns a low-level Headbutt away')
  love.math.random = saved
  package.loaded['src.pokemon.Gen4Forms'] = nil
end

-- ------------------------------------------------------------ dowsing MCHN
do
  local D = require('src.world.HgssDowsing')
  local def = { signs = {
    { x = 10, y = 10, script = 8000, pickup = { kind = 'hidden' } },
    { x = 14, y = 10, script = 8001, pickup = { kind = 'hidden' } },
    { x = 40, y = 40, script = 8002, pickup = { kind = 'hidden' } },
    { x = 11, y = 10, script = 5 },                      -- a plain sign
  } }
  local save = { flags = {} }
  local it, dx, dy = D.nearest(def, 12, 10, save)
  T.check(it and it.sign.script == 8000, 'nearest by |dx|+|dz|, the first kept on a tie')
  T.eq(D.state(dx, dy), 4, 'within 8 on both axes: state 4')
  T.eq(D.state(10, 0), 3, 'within 12: state 3')
  T.eq(D.state(0, 17), 2, 'within 17: state 2')
  T.eq(D.state(nil), 0, 'nothing found: state 0')
  save.flags['FLAG_G4_0320'] = true                     -- 800 + 0: picked up
  it = D.nearest(def, 12, 10, save)
  T.check(it and it.sign.script == 8001, 'a picked-up item (flag 800 + n) is not found again')
  T.eq(D.nearest(def, 12, 10 - 18, save), nil, 'outside +-17 nothing is found')
  T.eq(D.flagKey({ script = 8005 }), 'FLAG_G4_0325', 'HiddenItemScriptNoToFlagId: 800 + script - 8000')
end

-- ---------------------------------------------------------- phone rematch
do
  local R = require('src.script.HgssPhoneRematch')
  local joey = 8                                          -- TRAINER_YOUNGSTER_JOEY
  local beaten = {}
  local function b(t) return beaten[t] end
  local unlocked = {}
  local function u(r) return unlocked[r] end
  T.eq(R.rematchFor(joey, b, u), 8, 'unbeaten base: the base trainer (rung 1 = base)')
  beaten[8] = true
  T.eq(R.rematchFor(joey, b, u), 8, 'rung 2 locked: back to the base')
  unlocked[2] = true
  T.eq(R.rematchFor(joey, b, u), 279, 'rung 2 unlocked: JOEY_2 (279)')
  T.eq(R.rematchFor(9999, b, u), 0, 'not a rematch trainer: 0')
  local save = { hgssPhoneState = { seeking = {} }, gen4TrainerFlags = {}, flags = {} }
  local game = { data = { gen4_hgss_phone_call = { book = { [3] = { trainerId = joey } } } } }
  T.eq(R.answer(game, save, 3), 0, 'a contact not seeking a rematch answers 0')
  save.hgssPhoneState.seeking[3] = true
  T.eq(R.answer(game, save, 3), 8, 'seeking: the rematch trainer')
end

-- ------------------------------------------------------------------- music
do
  local B = require('src.core.Gen4FieldBgm')
  local data = { isGen4Cache = true, gen4_version = { family = 'hgss' } }
  local special = function(_, k) return ({ bike = 'SEQ_GS_BICYCLE', surf = 'SEQ_GS_NAMINORI' })[k] end
  local def = function() return true end
  T.eq((B.effective(data, 'SEQ_GS_DUNGEON', true, false, special, def)), 'SEQ_GS_BICYCLE',
    'the bike song plays in a cave (the saved override)')
  T.eq((B.effective(data, 'SEQ_GS_DUNGEON', true, true, special, def)), 'SEQ_GS_NAMINORI',
    'surfing beats the override')
  T.eq((B.effective(data, 'SEQ_GS_DUNGEON', false, false, special, def)), 'SEQ_GS_DUNGEON',
    'on foot the map song')
  local _, handled = B.effective({ isGen3Cache = true }, 'X', true, false, special, def)
  T.eq(handled, false, 'other generations keep their outdoor rule')
end

-- ------------------------------------------------------------ escape rope
do
  local F = require('src.world.Gen4FieldMoves')
  T.eq(F.recordsEscape({ layout = 0 }, { layout = 70 }), true, 'main matrix -> a cave records')
  T.eq(F.recordsEscape({ layout = 0, allowFly = true }, { layout = 12, allowEscapeRope = false }), true,
    'main matrix -> a building records too, whatever its flags')
  T.eq(F.recordsEscape({ layout = 5 }, { layout = 70 }), false, 'a gate -> a cave records nothing')
  local x, y = F.escapeCell(4, 7, 'up')
  T.check(x == 4 and y == 8, 'facing north the stored row is one further south')
  x, y = F.escapeCell(4, 7, 'down')
  T.check(y == 7, 'facing south the tile itself')
end

-- ------------------------------------------------------------------- rods
do
  local C = require('src.inventory.Gen4FieldChecks')
  package.loaded['src.world.Gen4Follower'] = { hasPartner = function(s) return s.partner end }
  local pt = { isGen4Cache = true, gen4_version = { family = 'platinum' } }
  local hg = { isGen4Cache = true, gen4_version = { family = 'hgss' } }
  T.eq(C.rodRefusal(pt, {}), nil, 'Platinum: a rod may be cast alone')
  T.check(C.rodRefusal(pt, { partner = true }) ~= nil, 'Platinum: not with a partner')
  T.check(C.rodRefusal(hg, { partner = true }) ~= nil, 'HGSS: not with a follower')
  T.check(C.rodRefusal(hg, { hgssRocketCostumeFlag = true }) ~= nil, 'HGSS: not in the Rocket disguise')
  T.eq(C.inCostume(pt, { hgssRocketCostumeFlag = true }), false, 'Platinum has no disguise')
  package.loaded['src.world.Gen4Follower'] = nil
end

-- ------------------------------------------------------------ cycling road
do
  local R = require('src.world.Gen4CyclingRoad')
  -- HGSS: 0x70 starts the bridge, 0x71..0x73 keep it, anything else ends it
  T.eq(R.nextBridgeStatus(false, 0x70, true), true, 'HGSS: the BRIDGE_START tile sets the bridge bit')
  T.eq(R.nextBridgeStatus(true, 0x71, true), true, 'HGSS: a bridge tile keeps it')
  T.eq(R.nextBridgeStatus(false, 0x71, true), false, 'HGSS: a bridge tile does not set it (entered from the south)')
  T.eq(R.nextBridgeStatus(true, 0x00, true), false, 'HGSS: off the bridge clears it')
  local base = { dirHeld = false, cycling = true, roadBit = true, onBridge = true, behaviour = 0x71, hgss = true }
  T.eq(R.shouldRoll(base), true, 'idle, cycling, Cycling Road bit, on the bridge: roll south')
  local function with(k, v) local t = {} for a, b in pairs(base) do t[a] = b end t[k] = v return t end
  T.eq(R.shouldRoll(with('dirHeld', true)), false, 'a held direction stops the roll (A and B do not)')
  T.eq(R.shouldRoll(with('cycling', false)), false, 'on foot: no roll')
  T.eq(R.shouldRoll(with('roadBit', false)), false, 'without SetBikeStateLock / forcebicycling: no roll')
  T.eq(R.shouldRoll(with('onBridge', false)), false, 'without the bridge bit: no roll')
  T.eq(R.shouldRoll(with('behaviour', 0x70)), false, 'on the BRIDGE_START tile itself: no roll')
end

-- ----------------------------------------------------------- waterfall ride
do
  local W = require('src.world.Gen4WaterfallRide')
  local function pr(dir, f) local a, b = W.progress(dir, f) return ('%.3f/%.3f'):format(a, b) end
  T.eq(pr('up', 32), '0.000/0.500', 'up: 32 frames rising only (ov01_021F2AB8)')
  T.eq(pr('up', 64), '0.500/1.000', 'up: the rise ends at frame 64, half way forward')
  T.eq(pr('up', 96), '1.000/1.000', 'up: two tiles forward at frame 96')
  T.eq(pr('down', 32), '0.500/0.000', 'down: 32 frames forward only (ov01_021F2C88)')
  T.eq(pr('down', 64), '1.000/0.500', 'down: forward done at 64, half way down')
  T.eq(pr('down', 96), '1.000/1.000', 'down: at the foot at frame 96')
  T.eq(W.TOTAL * W.TICKS_PER_FRAME, 192, 'the ride is 96 field frames, 192 engine ticks')
  local Game = { data = { gen4_version = { family = 'hgss' } } }
  local saved = package.loaded['src.core.Game']
  package.loaded['src.core.Game'] = Game
  local map = { cellBehaviour = function(_, x, y) return (x == 5 and y == 6) and 0x13 or 0x15 end }
  local ow = { player = { cellX = 5, cellY = 5, facing = 'down', surfing = true }, map = map }
  T.eq(W.descentAhead(ow, 'down'), true, 'surfing south onto a waterfall: the ride down')
  ow.player.surfing = false
  T.eq(W.descentAhead(ow, 'down'), false, 'walking: no ride')
  ow.player.surfing = true
  T.eq(W.descentAhead(ow, 'up'), false, 'north is the HM, not the descent')
  ow.player.facing = 'left'
  T.eq(W.descentAhead(ow, 'down'), false, 'a press that only turns does not ride')
  Game.data.gen4_version.family = 'platinum'
  ow.player.facing = 'down'
  T.eq(W.descentAhead(ow, 'down'), false, 'Platinum has no automatic descent')
  package.loaded['src.core.Game'] = saved
end

-- ----------------------------------------------------- ruins of alph walls
do
  local A = require('src.world.HgssAlphChambers')
  local ow = { player = { cellX = 6, cellY = 3, facing = 'up' }, map = { id = 'D24R0204' } }
  T.eq(A.at(ow, A.FLASH), true, 'Flash: (6, 3) facing north in the southeast chamber')
  T.eq(A.at(ow, A.ESCAPE_ROPE), false, 'not the Escape Rope room')
  ow.player.facing = 'left'
  T.eq(A.at(ow, A.FLASH), false, 'facing anywhere but north: the ordinary Flash')
  ow.map.id, ow.player.facing = 'D24R0202', 'up'
  T.eq(A.at(ow, A.ESCAPE_ROPE), true, 'Escape Rope: the northeast chamber')
  T.eq(A.ESCAPE_ROPE.item, 78, 'ITEM_ESCAPE_ROPE')
  T.eq(A.WATER_STONE.item, 84, 'ITEM_WATER_STONE')
  T.eq(A.FLASH.script, 3, '_EV_scr_seq_D24R0204_003')
  T.eq(A.bagItem({ data = { gen4_version = { family = 'platinum' } }, overworld = ow }, 78), false,
    'Platinum: the bag is untouched')
end

-- ------------------------------------------------------- headbutt forest
do
  local H = require('src.world.HgssHeadbuttTrees')
  local land = {}
  for i = 1, 4 do land[i] = 1 end
  land[2] = 0xD0                                         -- chunk (1, 0) is forest
  local ground = { grid = { width = 2, height = 2, land = land }, terrain = {}, chunkPx = 512,
                   offsetX = 0, offsetY = 0 }
  local ow = { map = { renderer = { gen4Ground = ground } }, player = { cellX = 31, cellY = 5, facing = 'right' } }
  T.eq(H.landAt(ow, 32, 5), 0xD0, 'the matrix cell holding the tile')
  T.eq(H.facingTree(ow), true, 'facing a tile of a land-0xD0 chunk: a Headbutt tree')
  ow.player.facing = 'left'
  T.eq(H.facingTree(ow), false, "facing the route's own land: not one")
end

-- ---------------------------------------------------- obstacle animations
do
  local F = require('src.world.Gen4FieldFx')
  T.eq(F.KINDS[0].part, 'cut', 'ScrCmd_560 0: the cut')
  T.eq(F.KINDS[1].part, 'rockSmash', '1: the rock breaking')
  T.eq(F.KINDS[4].part, 'headbutt', '4: the tree shaking')
  T.eq(F.KINDS[5].part, 'headbutt', '5: the same when the walking Pokemon does it')
  local beats = {}
  for f = 0, 9 do beats[#beats + 1] = F.shakeOn(f) and '1' or '0' end
  T.eq(table.concat(beats), '1100110000', 'the jolt: two frames on, two off, twice (ov02_0224DB9C)')
  local x, y = F.shakeVector('left')
  T.check(x == -8 and y == 0, 'toward the facing, 8 units')
  T.eq(F.start({ player = { facingCell = function() return 0, 0 end } }, 4), false,
    'no art in the cache: nothing starts (the var is written at once)')
end

-- ------------------------------------------------- phone number offers
do
  local P = require('src.script.HgssPhoneNumbers')
  local bk = { count = 2, [0] = { id = 0, trainerId = 0 }, [1] = { id = 10, trainerId = 8, gift = 0 } }
  T.eq(P.entryForTrainer(bk, 8).id, 10, 'LoadPhoneBookEntryI: Joey (trainer 8) is contact 10')
  T.eq(P.entryForTrainer(bk, 99), nil, 'a trainer with no row: none (0xFF)')
  T.eq(P.messageLine(0), 1, 'GetPhoneContactMsgIds 0: line 1 (asks for the number)')
  T.eq(P.messageLine(3), 4, '3: line 4 (asks again)')
  T.eq(P.messageLine(7), 1, 'past 4 reads as 0')
  T.eq(P.giftBerry(149, function(a, b) return b end), 158, 'a Cheri Berry gift is any of ten')
  T.eq(P.giftBerry(72), 72, 'any other gift is itself')
  -- the lowering of an install imported with LoadPhoneDat aliased away
  local L = { gettrainerid = function(ins, s) s.out[#s.out + 1] = { 'g4_get_trainer_id', ins.args[1] } end,
              getapproachingtrainerid = function() end, setvarfromvar = function() end,
              setvarfromvalue = function(ins, s) s.out[#s.out + 1] = { 'g4_set_var', ins.args[1], ins.args[2] } end }
  P.install(L)
  local s = { out = {} }
  L.gettrainerid({ args = { 0x8004 } }, s)
  L.setvarfromvalue({ name = 'setvarfromvalue', hgssName = 'loadphonedat', args = { 0x4010, 255 } }, s)
  T.check(s.out[2][1] == 'g4_hgss_load_phone_dat' and s.out[2][2] == 0x8004 and s.out[2][3] == 0x4010,
    'an aliased LoadPhoneDat reads the trainer from the var written before it')
  L.setvarfromvalue({ name = 'setvarfromvalue', args = { 0x4000, 3 } }, s)
  T.eq(s.out[3][1], 'g4_set_var', 'an ordinary SetVar is untouched')
  local Commands = require('src.script.Commands')
  local save = { vars = {} }
  local G4 = require('src.script.Gen4Commands')
  G4.setVar(save, 0x8004, 8)
  local game = { data = { gen4_hgss_phone_call = { book = bk },
                          gen4_hgss_pokegear_art = { contacts = { [10] = { bank = 675 } } } } }
  local ctx = { save = save, game = game }
  Commands.g4_hgss_load_phone_dat(ctx, 0x8004, 0x4010)
  T.eq(G4.getVar(save, 0x4010), 10, 'LoadPhoneDat answers the contact id')
  Commands.g4_hgss_phone_contact_msg(ctx, 0, 0x8004, 0x8005)
  T.check(G4.getVar(save, 0x8004) == 675 and G4.getVar(save, 0x8005) == 1,
    "the contact's own bank (sPhoneMessageGmm 675 for Joey) and line 1")
end

-- ------------------------------------------------------------ hgss flash
do
  local D = require('src.render.Gen4FlashDark')
  D.state = nil
  D.update('D42R0102', true, 0)
  D.update('D42R0102', true, 40)
  T.eq(D.radius(), D.SMALL, 'the dark cave: the small light')
  D.update('D42R0102', false, 40, true)
  D.update('D42R0102', false, 52, true)
  T.check(D.radius() > D.SMALL and D.radius() < D.SMALL * 4, 'Flash: the light grows (24 frames)')
  D.update('D42R0102', false, 70, true)
  T.eq(D.radius(), D.SMALL * 4, 'weather 12: four times the light, still dark beyond it')
  T.eq(D.update('D42R0102', false, 300, true), true, 'and it stays drawn')
  D.state = nil
end

-- ---------------------------------------------- vs seeker spin, honey tree
do
  local V = require('src.world.Gen4VsSeeker')
  local f, ccw, seen = 'down', false, {}
  for _ = 1, 8 do f, ccw = V.spinNext(f, ccw, 'down'); seen[#seen + 1] = f:sub(1, 1) end
  T.eq(table.concat(seen), 'lurdruld', 'the spin: clockwise from the start, reversing at the initial facing')
  T.eq(V.SPIN_TICKS, 50, 'a turn, then 24 frames held: 50 engine ticks a quarter')
  local H = require('src.world.Gen4HoneyTrees')
  T.eq(H.shakeValue(3), 2, 'GetShakingValue: 3 shakes -> animation 2')
  T.eq(H.shakeValue(1), 0, '1 shake -> animation 0')
  T.eq(H.shakeValue(0), nil, 'no shakes: the tree stands still')
end

-- --------------------------------------- platinum: cut and rock smash art
do
  local A = require('src.import.Gen4PtFieldFx')
  T.eq(A.PATH, '/graphic/hiden_effect.narc', 'NARC_INDEX_GRAPHIC__HIDEN_EFFECT')
  T.check(A.PARTS.cut.model == 3 and table.concat(A.PARTS.cut.anims, ',') == '0,1,2',
    'ov6_0224825C: Cut is model 3 with animations 0..2')
  T.check(A.PARTS.rockSmash.model == 8 and table.concat(A.PARTS.rockSmash.anims, ',') == '4,5,6,7',
    'ov6_02248340: Rock Smash is model 8 with animations 4..7')
  T.eq(A.PARTS.headbutt, nil, 'no Headbutt in Platinum')
  local F = require('src.world.Gen4FieldFx')
  T.check(F.KINDS[0].part == 'cut' and F.KINDS[0].se == 'SEQ_SE_DP_FW015',
    'StartDestroyObstacleAnimation 0: the cut, SEQ_SE_DP_FW015')
  T.check(F.KINDS[1].part == 'rockSmash' and F.KINDS[2].part == 'rockSmash' and F.KINDS[1].se == 'SEQ_SE_DP_FW088',
    '1 and 2: the rock breaking, SEQ_SE_DP_FW088')
  local ow = { gen4FieldFx = { { tag = 'rockClimb' }, { tag = 'x' }, { tag = 'rockClimb' } } }
  F.clear(ow, 'rockClimb')
  T.eq(#ow.gen4FieldFx, 1, "clear takes only its owner's objects")
  F.clear(ow, 'x')
  T.eq(ow.gen4FieldFx, nil, 'and the list goes when empty')
end

-- ------------------------------------------------- platinum: the hm cut-in
do
  local C = require('src.world.Gen4HMCutIn')
  local s = C.new({}, nil, 'boy')
  local cryAt, cryX, fullAt, fullWin, xOpenAt
  while not s.finished and s.frame < 200 do
    local cries = s.cries
    s:step()
    if s.cries > cries then cryAt, cryX = s.frame, s.monX end
    if not xOpenAt and s.x1 == 0 and s.state >= 4 then xOpenAt = s.frame end
    if not fullAt and s.state == 5 then fullAt, fullWin = s.frame, s.y1 .. '..' .. s.y2 end
  end
  T.eq(s.frame, 59, 'sCutInTaskFuncs: done on the 59th field frame')
  T.eq(xOpenAt, 6, 'the window opens across in four frames of 64 (254 -> 0)')
  T.check(fullAt == 12 and fullWin == '56..136', 'and down to rows 56..136 six frames later')
  T.check(cryAt == 36 and cryX == 128, 'the cry as the Pokemon stops at the centre (x 128)')
  T.eq(s.y1 .. '..' .. s.y2, '88..104', 'WindowShrinkY ends at 88..104')
  T.eq(s.windowOn, false, 'and the window is gone at the end')
  local w = C.new({}, nil, 'girl')
  T.eq(w.female, true, "the girl's sprite set (field_cutin 16 / 17 / 18)")
  -- a streak is drawn only inside the window's rows
  w.state, w.frame = 0, 0
  for _ = 1, 6 do w:step() end
  local shown = 0
  for _, p in ipairs(w.wind) do if p.shown then shown = shown + 1 end end
  T.eq(shown, 0, 'no streak while the window is 2 rows tall')
end

-- ------------------------------------------ platinum: strength, rock climb
do
  local S = require('src.world.Gen4StrengthPush')
  T.check(S.SE == 'SEQ_SE_DP_UG_023' and S.RATE == 2,
    'ov5_021DFFBC: SEQ_SE_DP_UG_023 and WALK_SLOW (twice the step), no dust')
  local R = require('src.world.Gen4RockClimbRide')
  T.check(R.climbable(0x4B, 'up') and R.climbable(0x4B, 'down') and not R.climbable(0x4C, 'up'),
    'north / south climbs ROCK_CLIMB_NORTH_SOUTH (0x4B)')
  T.check(R.climbable(0x4C, 'left') and not R.climbable(0x4B, 'right'), 'east / west 0x4C')
  T.check(R.MODEL == 82 and R.ANGLE.up == 180 and R.ANGLE.left == 270,
    'ov5_021F28F4: rock_ride (fldeff 82), turned 180 north, 270 west')
  T.check(R.DEBRIS_EVERY == 5 and R.FAST_RATE == 0.5 and R.HOP_TICKS == 16,
    'debris every 5 frames; WALK_FAST 4 frames a tile; JUMP_NEAR_FAST 8')
end

-- ------------------------------------------------ platinum: fog and defog
do
  local W = require('src.world.Gen4FogWeather')
  local eva, shift = W.fade(0)
  T.check(eva == 9 and shift == 0, 'the fog at full: eva 9, the table full')
  eva = W.fade(15)
  T.eq(eva, 5, 'eva 9 - 9 * 15 / 30 (C division) halfway')
  eva = W.fade(30)
  T.eq(eva, 0, 'the layer gone after 30 frames')
  local _, s126, d126 = W.fade(126)
  local _, _, d127 = W.fade(127)
  T.check(s126 == 31 and not d126 and d127, 'the table thins over 127 frames, then the fog is off')
  W.state = { eva = 4, shift = 7 }
  local row = W.depthRow()
  T.check(row.slope == 6 and row.offset == 30037 and row.rgb[1] == 31 and row.shift == 7,
    'ov5_021DAEC0: slope 6, offset 30037, white, with the thinning shift')
  W.state = nil
  T.eq(W.depthRow(), nil, 'no fog: no row')
end

T.finish()
