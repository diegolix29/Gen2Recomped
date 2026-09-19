package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("FireRed V.S. Seeker")
local check, eq = S.check, S.eq
local VsSeeker = require("src.world.VsSeeker")

local data = { constants = { gen3TrainerFlagBase = 0x500,
  gen3VsSeeker = { rematches = { [10] = { parties = { 10, 11, 0xFFFF, 12 } } } } } }
local save = { inventory = { VS_SEEKER = 1 }, flags = { FLAG_G3_050A = true } }
local npc = { cellX = 12, cellY = 10, def = { localId = 3, gen3TrainerId = 10 } }
local ow = { map = { id = "MAP_ROUTE3" }, player = { cellX = 10, cellY = 10 }, npcs = { npc } }

for _ = 1, 99 do VsSeeker.step(save) end
eq(VsSeeker.remaining(save), 1, "charges one step at a time")
eq(VsSeeker.use(data, save, ow), "charging", "cannot use before full charge")
VsSeeker.step(save)
eq(VsSeeker.use(data, save, ow, function() return 99 end), "ready", "arms an eligible trainer")
eq(VsSeeker.rematchFor(save, ow, npc), 11, "stores first eligible rematch on the map object")
check(VsSeeker.isReady(save, ow, npc), "armed object is ready for a rematch")
check(VsSeeker.shouldTry(data, save, ow, npc, 10),
      "armed object takes the cartridge rematch dialogue branch")
VsSeeker.clear(save, ow, npc)
check(VsSeeker.rematchFor(save, ow, npc) == nil, "win clears only that trainer's rematch")
check(not VsSeeker.isReady(save, ow, npc), "cleared object is no longer ready")

-- ShouldTryRematchBattle stays true after at least one rematch party on this
-- row has been beaten, even though IsTrainerReadyForRematch is false until the
-- device arms the map object again.  This is what makes the type-5 record fall
-- through to post-battle talk rather than refighting the original trainer.
save.flags.FLAG_G3_050B = true
check(VsSeeker.shouldTry(data, save, ow, npc, 10),
      "previously beaten rematch keeps the rematch dialogue branch")

-- Using the device starts the cartridge's recharge window; a full recharge
-- restores readiness and does not resurrect the object-specific rematch.
for _ = 1, 100 do VsSeeker.step(save) end
check(VsSeeker.ready(save), "recharges after 100 walking steps")
check(VsSeeker.rematchFor(save, ow, npc) == nil, "recharge keeps cleared objects clear")

S:finish()
