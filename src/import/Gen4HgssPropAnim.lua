-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER MAP PROP ANIMATIONS -- the windmill, the fountains,
-- the lighthouse lamp, the flags.
--
-- Platinum's chain is area_build -> `bm_anime_list` -> `bm_anime`
-- (Gen4PropAnim).  HGSS keeps the same chain under anonymous paths, found in
-- pokeheartgold's own code rather than by guessing at member contents:
--
--   AreaDataManager_Alloc (asm/overlay_01_021FB878.s) opens, by the area
--   record's outdoor byte,
--       outdoor: models NARC 40  (/a/0/4/0), anim list NARC 107 (/a/1/0/7)
--       rooms:   models NARC 148 (/a/1/4/8), anim list NARC 108 (/a/1/0/8)
--   and MapPropAnimationManager_Init (src/field/map_prop_animation.c) opens
--   NARC_a_1_0_6 (/a/1/0/6) as the animations, for BOTH lists.
--
-- /a/1/0/6 is 273 plain (uncompressed) BCA0/BTA0/BTP0/BMA0 files, each named
-- after its model: member 5 is `wk_sp1`, 240 frames over 3 joints -- New
-- Bark's windmill -- and list member 27 (`wk_sp1` in /a/0/4/0) names it.
--
-- THE LIST RECORD is 24 bytes, not Platinum's 20 (`MapPropAnimListFile`,
-- include/field/map_prop_animation.h):
--
--     hasAnimations   0x00  u8     1 = yes (0xFF when not, as in Platinum)
--     flags           0x01  u8
--     isBicycleSlope  0x02  u8
--     pad             0x03  u8
--     unk4            0x04  u32
--     animArchiveIDs  0x08  u32[4] 0xFFFFFFFF = none
--
-- WHAT THE CARTRIDGE DOES WITH IT is ov01_021E8F3C, run as each prop is
-- placed, and it is the whole of the "is this on the clock" rule:
--
--   * flags & 1 (and flags ~= 8): DEFERRED LOAD -- doors, escalators; a script
--     loads and plays them as one-shots.  Not on the clock.
--   * flags & 2 (or flags == 8):  loaded but NOT attached; a script attaches
--     it (gym gimmicks).  Drawn at rest.
--   * flags == 8:                 TIME OF DAY -- four animations, the one for
--     the current visual state attached (morning 0, day 1, evening 2, night
--     and late night 3).  The lighthouse lamp, Goldenrod's radio tower sky.
--   * isBicycleSlope:             attached, but initialised paused.  At rest.
--   * otherwise:                  attached with loop count -1 -- the clock.
--   * the id loop RETURNS at the first 0xFFFFFFFF, so ids after a hole are
--     never loaded.
--
-- Place at: src/import/Gen4HgssPropAnim.lua

local Gen4HgssPropAnim = {}

Gen4HgssPropAnim.ANIMATIONS = "/a/1/0/6"
-- by building set: which list claims its models
Gen4HgssPropAnim.LISTS = {
  buildings = "/a/1/0/7",
  interiorBuildings = "/a/1/0/8",
}
Gen4HgssPropAnim.RECORD_BYTES = 24
Gen4HgssPropAnim.IDS_AT = 8
Gen4HgssPropAnim.MAX_ANIMATIONS = 4
Gen4HgssPropAnim.NONE = 0xFFFFFFFF
Gen4HgssPropAnim.TIME_OF_DAY = 8

local function u32(s, at)
  local a, b, c, d = s:byte(at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- parse(record) -> { has, flags, slope, ids = {...} } | nil
-- `ids` stops at the first hole, as the cartridge's loader does.
function Gen4HgssPropAnim.parse(record)
  if type(record) ~= "string" or #record < Gen4HgssPropAnim.RECORD_BYTES then
    return nil
  end
  local out = {
    has = record:byte(1) == 1,
    flags = record:byte(2),
    slope = record:byte(3) == 1,
    ids = {},
  }
  if not out.has then return out end
  for k = 0, Gen4HgssPropAnim.MAX_ANIMATIONS - 1 do
    local v = u32(record, Gen4HgssPropAnim.IDS_AT + 1 + k * 4)
    if not v or v == Gen4HgssPropAnim.NONE then break end
    out.ids[#out.ids + 1] = v
  end
  return out
end

-- classify(entry) -> "clock" | "timeOfDay" | "script" | "held" | nil
function Gen4HgssPropAnim.classify(entry)
  if not (entry and entry.has and #entry.ids > 0) then return nil end
  local flags = entry.flags or 0
  if flags == Gen4HgssPropAnim.TIME_OF_DAY then return "timeOfDay" end
  if flags % 2 == 1 then return "script" end
  if math.floor(flags / 2) % 2 == 1 then return "held" end
  if entry.slope then return "held" end
  return "clock"
end

-- claims(listArc) -> { [anim member] = { clock = {model...}, timeOfDay =
--   {[model] = slot}, script = {model...}, held = {model...} } }, props
function Gen4HgssPropAnim.claims(list)
  local out, props = {}, 0
  if not list then return out, props end
  for model = 0, list.count - 1 do
    local entry = Gen4HgssPropAnim.parse(list:get(model))
    local kind = Gen4HgssPropAnim.classify(entry)
    if kind then
      props = props + 1
      for slot, id in ipairs(entry.ids) do
        local c = out[id]
        if not c then
          c = { clock = {}, timeOfDay = {}, script = {}, held = {} }
          out[id] = c
        end
        if kind == "timeOfDay" then
          c.timeOfDay[model] = slot - 1
        else
          c[kind][#c[kind] + 1] = model
        end
      end
    end
  end
  return out, props
end

-- The visual state the cartridge picks a time-of-day animation by
-- (sTimeOfDayVisualState over GF_RTC_GetTimeOfDayByHour).
function Gen4HgssPropAnim.timeOfDayState(hour)
  hour = math.floor(tonumber(hour) or 12) % 24
  if hour >= 4 and hour <= 9 then return 0 end
  if hour >= 10 and hour <= 16 then return 1 end
  if hour >= 17 and hour <= 19 then return 2 end
  return 3
end

-- One animation set for one list, in the shape Platinum's `field` set has
-- (RomExtractorGen4:extractModels writes the same record fields for
-- `bm_anime`), so Gen4Ground plays it through the same paths:
--
--   props      the models that wear it on the clock (or by time of day)
--   timeOfDay  { [model] = visual state } for the time-of-day ones
--   loop       true -- the cartridge attaches it with loop count -1, so a
--              JOINT animation loops on the frame clock too (the windmill)
--   bca        the BCA0 file itself (and `bcaIndex`), for a joint animation
--              some model wears; Gen4PropClock.inflate turns it into the
--              `tracks` Gen4Ground reads, once, at run time
--   scriptProps / heldProps  models that own it but do not play it on load
--
-- and the set carries the runtime rules: `claimsOnly` (the cartridge joins by
-- list, never by name) and `scripted` (members no model plays on the clock --
-- doors, escalators, gym gimmicks -- which Platinum's door-id set would
-- otherwise misname, since its member numbers mean other animations here).
--
-- Records no model in this list claims are left out: a room never needs the
-- outdoor animations, and an unclaimed BCA0 would be 0 KB of use.
local function buildSet(anim, claims, label, path)
  local Gen4Anim = require("src.import.Gen4Anim")
  local Gen4Graphics = require("src.import.Gen4Graphics")
  local set = { label = label, path = path, models = {}, animations = {},
                claimsOnly = true, scripted = {} }
  local failed = 0
  for member = 0, anim.count - 1 do
    local c = claims[member]
    if c then
      local bytes = anim:get(member)
      if bytes and Gen4Graphics.isCompressed(bytes) then
        bytes = Gen4Graphics.decompress(bytes)
      end
      local magic = bytes and bytes:sub(1, 4)
      local parsed = magic and Gen4Anim.KINDS[magic] and Gen4Anim.parse(bytes)
      local owners, tod = {}, nil
      for _, m in ipairs(c.clock) do owners[#owners + 1] = m end
      for m, state in pairs(c.timeOfDay) do
        owners[#owners + 1] = m
        tod = tod or {}
        tod[m] = state
      end
      table.sort(owners)
      for ai, a in ipairs(parsed and parsed.animations or {}) do
        local record = {
          name = a.name, member = member, kind = parsed.kind,
          what = parsed.what, frames = a.frames,
          joints = a.nodes, targets = a.targets,
        }
        if parsed.kind == "BTA0" then
          record.targets = nil
          record.srt = Gen4Anim.textureSrt(bytes, a)
        elseif parsed.kind == "BTP0" then
          record.targets = nil
          record.pattern = Gen4Anim.texturePattern(bytes, a)
        elseif parsed.kind == "BMA0" then
          record.targets = nil
          record.colour = Gen4Anim.materialColour(bytes, a)
        elseif parsed.kind == "BVA0" then
          record.visibility = Gen4Anim.visibility(bytes, a)
        end
        if #owners > 0 then
          record.props = owners
          record.timeOfDay = tod
          record.loop = true
          if parsed.kind == "BCA0" then
            -- THE FILE, NOT THE MATRICES.  Packed per frame (as Platinum's
            -- `bm_anime` tracks are) these came to 14.7 MB of cache -- the
            -- Dragon's Den / Radio Tower roof skies are 960 frames over 7-9
            -- joints, four of each by time of day -- against ~150 KB of
            -- BCA0.  Gen4PropClock.inflate decodes them once at run time
            -- with this same Gen4Anim path; the round trip is checked here.
            record.bca = bytes
            record.bcaIndex = ai
            for _, joint in ipairs(Gen4Anim.jointMatrices(bytes, a) or {}) do
              local blob = Gen4Anim.packTrack(joint.track)
              if not Gen4Anim.verifyTrack(joint.track, blob) then failed = failed + 1 end
            end
          end
        else
          set.scripted[member] = true
          if parsed.kind == "BCA0" then record.unworn = true end
        end
        if #c.script > 0 then record.scriptProps = c.script end
        if #c.held > 0 then record.heldProps = c.held end
        set.animations[#set.animations + 1] = record
      end
    end
  end
  return set, failed
end

-- extractInto(extractor, out) -> report | nil, why
--
-- Writes `out.sets.field` (outdoor, claimed by /a/1/0/7 against /a/0/4/0)
-- and `out.sets.interiorField` (rooms, /a/1/0/8 against /a/1/4/8).  Run
-- BEFORE the building archives are read: the extractor decodes a model's
-- flipbook frames from the claims in these sets.
function Gen4HgssPropAnim.extractInto(extractor, out)
  local anim = extractor:archiveAt(Gen4HgssPropAnim.ANIMATIONS)
  if not anim then return nil, "no " .. Gen4HgssPropAnim.ANIMATIONS end
  out.sets = out.sets or {}
  local report = { animations = anim.count }
  for _, row in ipairs({
    { key = "field", list = Gen4HgssPropAnim.LISTS.buildings, label = "map prop animations (outdoor)" },
    { key = "interiorField", list = Gen4HgssPropAnim.LISTS.interiorBuildings, label = "map prop animations (rooms)" },
  }) do
    local list = extractor:archiveAt(row.list)
    if list then
      local claims, props = Gen4HgssPropAnim.claims(list)
      local set, failed = buildSet(anim, claims, row.label, Gen4HgssPropAnim.ANIMATIONS)
      set.claimList = row.list
      set.claimedProps = props
      out.sets[row.key] = set
      report[row.key] = { props = props, records = #set.animations, failedTracks = failed }
    end
  end
  return report
end

return Gen4HgssPropAnim
