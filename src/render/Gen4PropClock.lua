-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MAP PROPS THAT MOVE ON THE FRAME CLOCK BY JOINT -- the New Bark windmill.
--
-- Gen4Ground plays a prop's texture animations on its frame clock and its
-- joint animations only as script one-shots (doors).  HeartGold and
-- SoulSilver attach every non-deferred prop animation with loop count -1
-- (ov01_021E8F3C, see src/import/Gen4HgssPropAnim.lua), joints included, so
-- the windmill's sails, the Ecruteak/Violet fountains' spray rigs and the
-- lighthouse lamp turn without any script asking.
--
-- ONLY RECORDS STAMPED `loop` ARE PLAYED HERE.  Gen4HgssPropAnim writes it;
-- Platinum's `bm_anime` records never carry it, so a Platinum map draws
-- exactly as it did.
--
-- And the cartridge's TIME-OF-DAY rule (list flags == 8): of four animations
-- the one for the current visual state is attached.  `record.timeOfDay`
-- names, per claiming model, which state the record belongs to.
--
-- Place at: src/render/Gen4PropClock.lua

local Gen4PropClock = {}

local cachedAt, cachedState = nil, 1

-- The visual state now (morning 0, day 1, evening 2, night 3), by the same
-- wall clock Gen4Ground:applyLight reads.  Re-read at most once a second.
function Gen4PropClock.state()
  local now = os.time()
  if now ~= cachedAt then
    cachedAt = now
    local t = os.date("*t", now)
    cachedState = require("src.import.Gen4HgssPropAnim").timeOfDayState(t and t.hour)
  end
  return cachedState
end

-- wears(record, index) -> whether the prop model `index` plays `record` now.
-- A record with no time-of-day table is worn always (its claim decided that).
function Gen4PropClock.wears(record, index)
  local tod = record and record.timeOfDay
  if not tod then return true end
  local state = tod[index]
  if state == nil then return true end
  return state == Gen4PropClock.state()
end

-- inflate(record) -- `record.tracks` from `record.bca`, once.
--
-- HGSS records carry the BCA0 file rather than its per-frame matrices (see
-- Gen4HgssPropAnim: 14.7 MB packed against ~150 KB raw).  Decoded with the
-- same Gen4Anim path the extractor uses for Platinum's tracks and packed the
-- same way, so `jointMatricesAt`, `oneShotProps` and `pose` below read one
-- shape.  The record is shared by every map, so this runs once a session.
function Gen4PropClock.inflate(record)
  if not (record and record.bca) or record.tracks then return end
  local okA, Anim = pcall(require, "src.import.Gen4Anim")
  if not okA then return end
  local ok, tracks = pcall(function()
    local parsed = Anim.parse(record.bca)
    local anim = parsed and parsed.animations and parsed.animations[record.bcaIndex or 1]
    if not anim then return nil end
    local out = {}
    for _, joint in ipairs(Anim.jointMatrices(record.bca, anim) or {}) do
      out[#out + 1] = { index = joint.index, frames = joint.frames,
                        matrices = Anim.packTrack(joint.track) }
    end
    return out
  end)
  if ok and tracks then record.tracks = tracks end
end

-- pose(ground, object, building) -> pose | nil
--
-- The looping joint pose for a placed prop at `ground.clock`, or nil (the rest
-- pose) when nothing it owns loops by joint.  Joint animations of the same
-- prop are merged by joint index, first record wins, as the hardware's anim
-- object list blends equal-priority entries in list order.
function Gen4PropClock.pose(ground, object, building)
  if not (ground and object and building) then return nil end
  if object.archive == "fldeff" then return nil end
  local owned = ground.animsByProp and ground.animsByProp[object.model]
  if not owned then return nil end
  local scripted = ground.scriptedMembers
  local byJoint, Anim = nil, nil
  for _, record in ipairs(owned) do
    if record.loop and record.bca and not record.tracks then Gen4PropClock.inflate(record) end
    if record.loop and record.tracks
       and not (scripted and record.member and scripted[record.member])
       and Gen4PropClock.wears(record, object.model) then
      if not Anim then
        local okA, A = pcall(require, "src.import.Gen4Anim")
        if not (okA and A and A.unpackFrame) then return nil end
        Anim = A
      end
      local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
      local frame = math.floor(tonumber(ground.clock) or 0) % frames
      for _, track in ipairs(record.tracks) do
        byJoint = byJoint or {}
        if byJoint[track.index] == nil then
          local at = frame
          if track.frames and at >= track.frames then at = track.frames - 1 end
          if at < 0 then at = 0 end
          byJoint[track.index] = Anim.unpackFrame(track.matrices, at)
        end
      end
    end
  end
  if not byJoint then return nil end
  return building:posed(function(node) return byJoint[node] end)
end

return Gen4PropClock
