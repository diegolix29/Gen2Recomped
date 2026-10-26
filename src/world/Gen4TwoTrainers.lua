-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- TWO SEPARATE TRAINERS SPOTTING YOU AT ONCE (Platinum, HGSS, Black / White).
--
-- THE RULE, READ FROM CODE:
--
--   Platinum (pokeplatinum src/trainer_encounter.c,
--   FieldSystem_CheckForTrainersWantingBattle): FindUndefeatedTrainerInSight
--   takes the first object, in object order, that sees the player and is not
--   beaten. When THAT trainer's battle type is single and the party has two
--   Pokemon that are not eggs and not fainted, it runs the same search again
--   from the start of the object list with the first one excluded; a hit
--   makes both APPROACH_TYPE_VS2 (2), slots 0 and 1, each with its OWN
--   distance and direction. The second must see the player and be undefeated
--   (same function); its own battle type is not asked.
--
--   Black / White (ov21 0x21AE0CC): the same shape. 0x21AE1FC is the search
--   (r1 = the object to skip: 0 the first time, the first trainer's object
--   the second), 0x218B6AC the usable count (>= 2), and 0x21AE12A stores 2 as
--   the approach type of both slots (+0x14 of each eye record) before
--   0x215A438 files them as slots 0 and 1. 0x21AE930 starts script 0xE20
--   (3616): band 3000's entry 616, member 863's S0D51.
--
--   HGSS: scr_seq_0953_739 is the eye script and its type-2 branch (_107D)
--   is the same VS2 walk (pokeheartgold files/fielddata/script/scr_seq/
--   scr_seq_0953.s). The field-side pick (TryGetSeenByNpcTrainers, called
--   with HasEnoughAlivePokemonForDoubleBattle from field_control.c) is not
--   decompiled; it is ASSUMED to be Platinum's.
--
-- HOW THEY COME, READ FROM THE SCRIPTS: ONE AFTER THE OTHER. Platinum's
-- Battles_ApproachingTrainerVS2, HGSS's _107D and Black's S0EF0 all walk
-- trainer 0 (StartApproachingTrainerTask 0 / BW 0x080 0, wait), print its
-- line, THEN walk trainer 1 and print its line, then
-- StartTrainerBattle(trainer0, trainer1) and set BOTH defeat flags. The lines
-- differ: Platinum and HGSS print each trainer's PRE_BATTLE (type 0); Black
-- prints type 3 for trainer 0 and type 7 for trainer 1 (member 863 @3870 /
-- @3896: `087 802C 3`, `087 802D 7`), which a single trainer does not carry
-- in this cartridge's table -- 0x202A310 then clears the string (no fallback
-- in that loader), so on Black / White both lines are empty boxes and the
-- port, which skips a missing line, shows none.
--
-- HOW THE PORT DOES IT: the overworld still walks trainer 0 itself (the "!"
-- and the walk in OverworldState:startTrainerApproach), then runs the eye
-- script with the pair on the context. `startapproachingtrainertask n`
-- (Platinum 0x0B6, HGSS GetTrainerPathToPlayer, BW 0x080) walks slot n when
-- it has not walked yet and blocks until it stands beside the player; slot 0
-- is already there, so its call does nothing. Each walk is the approach
-- task's own order (Platinum ApproachingTrainerTask_*): face the direction,
-- the "!" bubble, then step until next to the player. Only the VS2 case runs
-- the eye script; a lone trainer and a same-id double keep the talk path the
-- port has always used for them -- except a same-id double that spots you
-- while an escort is along (APPROACH_TYPE_DOUBLES, OverworldController
-- checkTrainerSight), whose slot 1 walks the spotter's distance and `dir`.

local M = {}

-- BW starts 0xE20 (ov21 0x21AE938: `movs r1, #0xe2; lsls r1, r1, #4`).
M.BW_EYE_SCRIPT = 3616

-- Does this compiled block start the eye script's dispatch? Every family's
-- eye script asks the approach type before anything else it branches on
-- (Platinum GetApproachingTrainerType, HGSS GetTrainerEyeType, BW 0x083);
-- an old Black cache (imported before 0x083 was named) keeps it as `bw_083`.
local function asksApproachType(pool, label)
  local s = pool.scripts and pool.scripts[label]
  for i, ins in ipairs((s and s.instructions) or {}) do
    if i > 8 then break end
    if ins.name == "getapproachingtrainertype" or ins.name == "bw_083" then return true end
  end
  return false
end

-- The label of the shared eye-contact script, or nil when this cache has
-- none we can trust (the caller then falls back to one trainer).
--   BW: script 3616 (READ FROM CODE, above).
--   Platinum / HGSS: SCRIPT_ID(SINGLE_BATTLES, MAX_TRAINERS) -- the band's
--   entry after the last trainer, which is the band's LAST entry in both
--   files (Platinum's scripts_battles, HGSS's scr_seq_0953_739). Taken as
--   the last entry and then checked for the approach-type ask (INFERRED: the
--   ordering, not the id, is what was read).
function M.eyeLabel(data)
  local VM = require("src.script.Gen4ScriptVM")
  local pool = VM.store(data)
  local bands = pool and pool.bands
  if not bands then return nil end
  local Bands = require("src.import.Gen4ScriptBands")
  local label
  if Bands.family == "bw" then
    local kind, name, index = Bands.classify(M.BW_EYE_SCRIPT)
    local band = kind == "band" and bands[name]
    label = band and band.entries and band.entries[index + 1]
  else
    local band = bands.single_battles
    local entries = band and band.entries
    label = entries and entries[#entries]
  end
  if type(label) ~= "string" or not asksApproachType(pool, label) then return nil end
  return label
end

-- Is this trainer id a single battle on its own record? (Platinum
-- Script_IsTrainerDoubleBattle; BW 0x215A4C8, the record's byte 2.)
function M.isSingle(data, trainerId)
  local rec = trainerId and data and data.trainers and data.trainers[trainerId]
  if not rec then return true end
  local kind = rec.battleType
  if type(kind) == "string" then return kind == "single" end
  if rec.doubleBattle then return false end
  return (tonumber(kind) or 0) == 0
end

-- One approach task: the "!" bubble, then the walk to the cell beside the
-- player. `onDone` runs when they are there. The bubble and its sound are
-- the ones OverworldState:startTrainerApproach uses for the first trainer.
function M.walk(ow, npc, dist, onDone)
  local def = ow.map and ow.map.def
  local frames = 60
  if (def and def.generation) == 4 then
    frames = require("src.import.Gen4Emotes").framesFor(def)
    local bw = def.gen5
    pcall(function()
      require("src.core.Sound").play(Game.data, bw and "SEQ_SE_FLD_07" or "SEQ_SE_DP_DECIDE")
    end)
  end
  if npc.buried then npc.buried, npc.hidden = nil, nil end
  local bubble = {
    npc = npc, frames = frames, totalFrames = frames,
    onDone = function()
      if dist > 1 then
        ow:scriptMove(npc, npc.facing, dist - 1, onDone)
      else
        onDone()
      end
    end,
  }
  if ow.emote then
    ow.extraEmotes = ow.extraEmotes or {}
    ow.extraEmotes[#ow.extraEmotes + 1] = bubble
  else
    ow.emote = bubble
  end
end

-- `startapproachingtrainertask <n>` for the VS2 script. `ctx.gen4Approachers`
-- is { [0] = { npc, dist, done }, [1] = ... }, put there by the overworld.
-- A call with no slot (an old Black cache that dropped 0x080's operand)
-- takes the slots in call order, which is the order the cartridge's own
-- operands give in every path of member 863 (`080 0` then `080 1`).
function M.startApproach(ctx, approachNum)
  local slots = ctx.gen4Approachers
  if not slots then return end
  local slot
  if approachNum ~= nil then
    local C = require("src.script.Gen4Commands")
    slot = (C.valueOf(ctx, approachNum) or 0) == 0 and 0 or 1
  else
    slot = ctx.gen4ApproachCalls or 0
    ctx.gen4ApproachCalls = slot + 1
  end
  local entry = slots[slot]
  local ow = ctx.overworld
  if not entry or entry.done or not ow then return end
  entry.done = true
  -- a same-id double's other half walks the SPOTTER's direction
  -- (ApproachingTrainer_Init(&trainerTwo, partner, distance, direction))
  if entry.dir then entry.npc.facing = entry.dir end
  local runner = ctx.runner
  local waiting, finished = false, false
  M.walk(ow, entry.npc, entry.dist or 1, function()
    finished = true
    if waiting and runner then runner:resume() end
  end)
  if not finished and runner then
    waiting = true
    runner:yield()
  end
end

return M
