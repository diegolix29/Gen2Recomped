-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A SCRIPT'S HAND ON A MAP PROP'S ANIMATION: attach one the list holds back,
-- pause one on a frame, play one once from now.
--
-- The cartridge's MapPropAnimationManager keeps a MapPropAnimation per loaded
-- animation (loop count, paused, frame) and a handful of field commands reach
-- in and change those -- which this port's frame clock (Gen4PropClock: every
-- attached animation looping on ground.clock) had no way to say.  The cases:
--
--   * HGSS ScrCmd_710 (pokeheartgold src/overlay_03/shop_menu.c): for the
--     Mahogany hideout's three generators (room props 149, 152, 153,
--     aji_mech01..03, list /a/1/0/8 flags 2 = loaded, held back) attach
--     animation sub_020669B4(i) -- FLAG_UNK_96B + i, 0 running
--     (/a/1/0/6 member 86 aji_mech) or 1 stopped (87 aji_mech_stop) -- with
--     the loop count the loader gave them (-1): they then run on the clock.
--   * Platinum's lake guardian containment units (src/overlay006/
--     lake_guardian_containment_units.c, prop 496, bm_anime 48 BTA0 glow and
--     49 BCA0 the unit): paused on a frame, then the glow run out to its last
--     frame and the unit played once.
--   * Platinum's Hall of Fame machine (hall_of_fame.c): the mini balls'
--     one-shot flipbook (prop 517, bm_anime 31) played once from a tick.
--
-- STATE IS PER GROUND, as the cartridge's is per field: a map load builds a
-- fresh manager with every animation back at its loader's defaults, and the
-- map's OnResume script is what puts the script's choices back.  So a control
-- set here dies with the ground, exactly when the cartridge's would.
--
-- A control:  { attach = true }            -- worn though the list holds it
--             { hold = n | "last" }        -- paused on frame n / the last
--             { from = clock, once = true } -- from frame 0 at `clock`,
--                                             held on the last when `once`
--             { from = clock, once = true, reverse = true } -- the same,
--                                             last frame to first
-- keyed ground.propControl[model][member].  Frames are FIELD frames
-- (Gen4PropClock.fieldFrame), the rate the cartridge advances them.

local M = {}

local function clock() return require("src.render.Gen4PropClock") end

function M.set(ground, model, member, control)
  if not (ground and model and member) then return end
  ground.propControl = ground.propControl or {}
  local byModel = ground.propControl[model]
  if not byModel then byModel = {} ground.propControl[model] = byModel end
  byModel[member] = control
  -- attaching or detaching changes what moves; a held frame changes the
  -- picture -- either way the cached bakes are stale
  if ground.dropBakes then pcall(ground.dropBakes, ground) end
end

function M.get(ground, model, member)
  local byModel = ground and ground.propControl and ground.propControl[model]
  return byModel and byModel[member] or nil
end

function M.any(ground, model)
  return ground and ground.propControl and ground.propControl[model] ~= nil or false
end

-- the records a script has attached to `model` (in member order), which the
-- clock would otherwise leave alone
function M.attached(ground, model)
  local byModel = ground and ground.propControl and ground.propControl[model]
  if not byModel then return nil end
  local members = {}
  for member, c in pairs(byModel) do
    if c and c.attach then members[#members + 1] = member end
  end
  if #members == 0 then return nil end
  table.sort(members)
  local out = {}
  for _, member in ipairs(members) do
    local record = ground.animsByMember and ground.animsByMember[member]
    if record then out[#out + 1] = record end
  end
  return #out > 0 and out or nil
end

-- frameFor(ground, model, record) -> the field frame this record shows on
-- this model, or nil when no script has a hand on it (the clock decides)
function M.frameFor(ground, model, record)
  local c = record and record.member and M.get(ground, model, record.member)
  if not c then return nil end
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  if c.hold == "last" then return frames - 1 end
  if c.hold then return math.max(0, math.min(frames - 1, math.floor(c.hold))) end
  if c.from then
    local f = clock().fieldFrame(ground.clock or 0) - clock().fieldFrame(c.from)
    if f < 0 then f = 0 end
    if c.once then f = math.min(f, frames - 1) else f = f % frames end
    -- played backwards (MapPropAnimation_SetReversed: from the last frame
    -- down to 0 -- Pastoria Gym's buttons coming back up)
    if c.reverse then f = frames - 1 - f end
    return f
  end
  return nil
end

-- whether a `from`/`once` control has reached its last frame
function M.finished(ground, model, member)
  local c = M.get(ground, model, member)
  if not c then return true end
  local record = ground.animsByMember and ground.animsByMember[member]
  if not record then return true end
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local f = M.frameFor(ground, model, record)
  return f == nil or f >= frames - 1
end

-- materials(ground, model, records, clockFrame, images) -> mats | nil
-- The texture animations of `records` with each controlled one on its own
-- frame; nil when none is controlled (the caller's own path stands).
function M.materials(ground, model, records, clockFrame, images)
  if not (records and M.any(ground, model)) then return nil end
  local TexAnim = require("src.render.Gen4TexAnim")
  local plain, out = {}, nil
  for _, record in ipairs(records) do
    local f = M.frameFor(ground, model, record)
    if f then
      local one = TexAnim.materials({ record }, f, images)
      if one then
        out = out or {}
        for name, state in pairs(one) do
          local into = out[name] or {}
          for k, v in pairs(state) do into[k] = v end
          out[name] = into
        end
      end
    else
      plain[#plain + 1] = record
    end
  end
  if #plain > 0 then
    local rest = TexAnim.materials(plain, clockFrame, images)
    if rest then
      out = out or {}
      for name, state in pairs(rest) do
        if out[name] == nil then out[name] = state end
      end
    end
  end
  return out or {}
end

-- A MAP DEF'S OWN CONTROLS (`def.gen4PropControl[model][member]`), for a
-- gym whose init runs before its ground exists (PastoriaGym_DynamicMapFeatures-
-- Init poses the buttons): copied onto the ground whenever the def's table
-- is a new one. Gen4Ground:propMaterials asks this.
function M.sync(ground)
  local want = ground and ground.def and ground.def.gen4PropControl
  if not ground or ground.propControlFrom == want then return end
  local was = ground.propControlFrom
  ground.propControlFrom = want
  for model, members in pairs(type(was) == "table" and was or {}) do
    for member in pairs(members) do M.set(ground, model, member, nil) end
  end
  for model, members in pairs(type(want) == "table" and want or {}) do
    for member, c in pairs(members) do M.set(ground, model, member, c) end
  end
end

return M
