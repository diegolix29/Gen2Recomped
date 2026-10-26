-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S GYM GIMMICKS, DRAWN AS THE GYM OVERLAYS DRAW THEM.
--
-- Each gym's overlay registers a resource list and a unit list with the
-- field's 3D object system (ov21 0x21BE760; Nacrene's 0x21BE310), places
-- every object (0x21BE480 <unit, object> -> its fx32 position, read from the
-- overlay's own tables below), and drives its animations by hand:
--   0x21BE700 <obj, anim, on>   attach / detach an animation
--   0x21BE674 <obj, anim>       the animation's control block:
--     +0 stop flag (0x21BE6B0), +1 loop flag (0x21BE6B8), +8 still running
--     (0x21BE6BC answers "finished" when it is 0)
--   0x21BE6CC <obj, anim, f>    set the frame; 0x21BE748 the animation's end
--   0x21BE4A4 / 0x21BE4B4       an object shown / hidden
-- and the field ticks every attached, unstopped animation one frame a field
-- frame (ov21 0x21BE580), once or looping by the loop flag. A script command
-- that starts one of these tasks (0x20122C0) also parks the script on it
-- (0x215897C) until the task says it is done.
--
-- The models are `gen5_gym_fx` (src/import/Gen5GymFxArt.lua). What follows
-- is per gym; READ FROM CODE marks a value taken from the overlay, INFERRED
-- one chosen without it.
--
-- TIMING: one animation frame a field frame, M.TICKS_PER_FRAME engine ticks
-- (the port's DS field runs its 30 Hz frames as two ticks -- INFERRED for BW,
-- matched to Gen 4's). The clock is the overworld's own update counter
-- (`ow.weatherFrame`), so animations stand still while a menu covers the field.
--
-- Drawn through Gen4GymFx's provider hook (def.gen4GymFxProvider), which the
-- overworld's two 3D passes already call.

local M = {}

M.TICKS_PER_FRAME = 2

local function Game() return package.loaded["src.core.Game"] end
local function art()
  local G = Game()
  return G and G.data and G.data.gen5_gym_fx or nil
end
local function arcOf(n)
  local a = art()
  return a and a.arcs and (a.arcs[n] or a.arcs[tostring(n)]) or nil
end

-- ------------------------------------------------------------ the models --
local modelCache, cacheOf = {}, nil
function M.model(arc, member)
  local a = art()
  if cacheOf ~= a then modelCache, cacheOf = {}, a end
  local key = arc .. ":" .. member
  local hit = modelCache[key]
  if hit ~= nil then return hit or nil end
  local rec = arcOf(arc)
  local packed = rec and rec.models and (rec.models[member] or rec.models[tostring(member)])
  local ok, m = false, nil
  if packed then ok, m = pcall(require("src.render.Gen4Model").new, packed) end
  modelCache[key] = (ok and m) or false
  return (ok and m) or nil
end

function M.anim(arc, member)
  local rec = arcOf(arc)
  return rec and rec.anims and (rec.anims[member] or rec.anims[tostring(member)]) or nil
end

function M.frames(arc, member)
  local r = M.anim(arc, member)
  return r and math.max(1, math.floor(tonumber(r.frames) or 1)) or 1
end

-- the last frame -- what 0x21BE748 hands back for a pose to rest on (INFERRED
-- from its use: an object "already done" is set there on load)
function M.lastFrame(arc, member) return M.frames(arc, member) - 1 end

local function unpackAt(track, f)
  local Anim = require("src.import.Gen4Anim")
  local m = Anim.unpackFrame(track, f)
  if m or type(track) ~= "string" then return m end
  local n = math.floor(#track / Anim.TRACK_BYTES)
  return n > 0 and Anim.unpackFrame(track, n - 1) or nil
end

-- pose and materials for { { member, frame }, ... } on one model
function M.look(arc, model, list)
  local byJoint, mats
  for _, a in ipairs(list or {}) do
    local r = M.anim(arc, a[1])
    if r then
      local f = math.max(0, math.min(M.frames(arc, a[1]) - 1, math.floor(a[2] or 0)))
      if r.kind == "BCA0" and r.tracks then
        byJoint = byJoint or {}
        for j, track in pairs(r.tracks) do
          local k = tonumber(j)
          if k and byJoint[k] == nil then byJoint[k] = unpackAt(track, f) end
        end
      elseif r.kind ~= "BCA0" then
        local one = require("src.render.Gen4TexAnim").materials({ r }, f, r.images)
        if one then
          mats = mats or {}
          for name, st in pairs(one) do
            local into = mats[name] or {}
            for k, v in pairs(st) do into[k] = v end
            mats[name] = into
          end
        end
      end
    end
  end
  local pose = byJoint and model:posed(function(node) return byJoint[node] end) or nil
  return pose, mats
end

-- -------------------------------------------------------------- the clock --
local function overworld()
  local G = Game()
  return G and G.overworld
end
function M.now(ow)
  ow = ow or overworld()
  return (ow and ow.weatherFrame) or 0
end
-- the field frame an animation started at `start` (a tick) is on
local function frameSince(start, now)
  return math.floor(math.max(0, (now or M.now()) - (start or 0)) / M.TICKS_PER_FRAME)
end

local function var(save, id)
  local v = save and save.gen4Vars and save.gen4Vars[id]
  return tonumber(v) or 0
end

-- ---------------------------------------------------- per-map play state --
-- st.play[key] = { member, start, reverse, hold } for an animation a command
-- started; everything else rests on the pose the save describes
local state = { map = nil, play = {} }
local function stateFor(def)
  if state.def ~= def then state = { def = def, play = {}, seen = {} } end
  return state
end
M._state = function() return state end

-- the frame a played animation is on, or nil when none is playing
local function playing(st, key, arc, now)
  local p = st.play[key]
  if not p then return nil end
  local n = M.frames(arc, p.member)
  local f = frameSince(p.start, now)
  if p.loop then return p.member, f % n end
  if f > n - 1 then f = n - 1 end
  if p.reverse then f = (n - 1) - f end
  return p.member, f
end

function M.play(def, key, member, opts)
  local st = stateFor(def)
  opts = opts or {}
  local gym = M.GYMS[tonumber(def and def.header) or -1]
  local n = gym and M.frames(gym.arc, member) or 1
  local now = M.now()
  st.play[key] = { member = member, start = now, reverse = opts.reverse, loop = opts.loop,
                   stop = now + n * M.TICKS_PER_FRAME }
end

-- world position of an overlay table entry (tiles, fx32 / 16), on the map
local function at(def, tx, ty, tz)
  return tx * 16 - (def.originX or 0) * 16, ty * 16, tz * 16 - (def.originY or 0) * 16
end

local function effect(def, arc, member, pos, rotY, anims)
  local model = M.model(arc, member)
  if not model then return nil end
  local x, y, z = at(def, pos[1], pos[2], pos[3])
  local pose, mats = M.look(arc, model, anims)
  return { model = model, pose = pose, mats = mats, x = x, y = y, z = z,
           rot = rotY and { 0, rotY, 0 } or nil }
end

-- ================================================================== GYMS ==

M.GYMS = {}

-- ------------------------------------------------------------- STRIATON --
-- Zone 7, overlay 42, arc 122 (READ FROM CODE: ov42 0x21F36C0).
--   nine floor switches, units 0..8, at the table 0x21F3AD4; unit k wears
--     model m0 / m3 / m6 (k % 3: fire, water, leaf) and its 2-frame BCA
--     m1 / m4 / m7 -- 0x187 <k> (task 0x21F38D4) runs it to its end (down),
--     0x189 <k> sets it back to frame 0, stopped
--   three curtains, units 9..11, at 0x21F3A68: m9 / m11 / m13, BCA m10 /
--     m12 / m14 (81 frames) -- 0x188 <row> (task 0x21F3980) plays it once and
--     parks the script until it ends, then marks the row open in the gym's
--     block; on load an open row's curtain is set to its end
-- The port's record of a row being open is the gym's var 0x4082 (2 after
-- the first curtain, 3, 4): row r is open at 0x4082 >= r + 2.
local STRIATON = {
  arc = 122, var = 0x4082,
  switches = { { 12.5, 0, 16.5 }, { 15.5, 0, 36.5 }, { 9.5, 0, 26.5 }, { 12.5, 0, 36.5 }, { 15.5, 0, 26.5 },
               { 9.5, 0, 36.5 }, { 12.5, 0, 26.5 }, { 15.5, 0, 16.5 }, { 9.5, 0, 16.5 } },
  switchModel = { [0] = 0, 3, 6 }, switchAnim = { [0] = 1, 4, 7 },
  curtains = { { 12.5, 0, 34.5 }, { 12.5, 0, 24.5 }, { 12.5, 0, 14.5 } },
  curtainModel = { 9, 11, 13 }, curtainAnim = { 10, 12, 14 },
}
M.GYMS[7] = STRIATON
function STRIATON.effects(def, save, st, now)
  local out = {}
  for k, pos in ipairs(STRIATON.switches) do
    local i = k - 1
    local member = STRIATON.switchAnim[i % 3]
    local down = st.switchDown and st.switchDown[i]
    local f = down and M.lastFrame(STRIATON.arc, member) or 0
    out[#out + 1] = effect(def, STRIATON.arc, STRIATON.switchModel[i % 3], pos, nil, { { member, f } })
  end
  local row = var(save, STRIATON.var)
  for r, pos in ipairs(STRIATON.curtains) do
    local member = STRIATON.curtainAnim[r]
    local _, f = playing(st, "curtain" .. r, STRIATON.arc, now)
    if not f then f = (row >= r + 1) and M.lastFrame(STRIATON.arc, member) or 0 end
    out[#out + 1] = effect(def, STRIATON.arc, STRIATON.curtainModel[r], pos, nil, { { member, f } })
  end
  return out
end
-- the commands: 0x187 / 0x189 <switch>, 0x188 <row> (frames to wait back)
function STRIATON.op(def, st, op, n)
  if op == 0x187 or op == 0x189 then
    st.switchDown = st.switchDown or {}
    st.switchDown[n] = (op == 0x187) or nil
    return 1
  elseif op == 0x188 and n >= 0 and n <= 2 then
    M.play(def, "curtain" .. (n + 1), STRIATON.curtainAnim[n + 1])
    return M.frames(STRIATON.arc, STRIATON.curtainAnim[n + 1])
  end
end

-- -------------------------------------------------------------- NACRENE --
-- Zone 18, overlay 40, arc 110 (READ FROM CODE: ov40 0x21F36C0, registered
-- through 0x21BE310 with the table 0x21F38EC): one object, the bookcase m0
-- at (13.0, 0, 9.5) (0x21F38D4), its BCA m1 (360 frames) attached stopped;
-- 0x185 <0> (task 0x21F381C) plays it once and parks the script until it
-- ends, then sets the block's byte 4 -- on load a set byte puts it on its
-- last frame. Here the open record is the gym var 0x408A at 7.
local NACRENE = { arc = 110, var = 0x408A, pos = { 13.0, 0, 9.5 }, model = 0, anim = 1 }
M.GYMS[18] = NACRENE
function NACRENE.effects(def, save, st, now)
  local _, f = playing(st, "bookcase", NACRENE.arc, now)
  if not f then f = (var(save, NACRENE.var) >= 7) and M.lastFrame(NACRENE.arc, NACRENE.anim) or 0 end
  return { effect(def, NACRENE.arc, NACRENE.model, NACRENE.pos, nil, { { NACRENE.anim, f } }) }
end
function NACRENE.op(def, st, op, n)
  if op == 0x185 and n == 0 then
    M.play(def, "bookcase", NACRENE.anim)
    return M.frames(NACRENE.arc, NACRENE.anim)
  end
end

-- ------------------------------------------------------------- CASTELIA --
-- Zone 29, overlay 38, arc 135 (READ FROM CODE: ov38 0x21F36C0):
--   units 0..7, the floor switches (m3, BTA m12 + BTP m13) at 0x21F46E8,
--     both attached stopped; a pressed one (its saved word) on its end
--   units 8..17, the ten presses' posts at 0x21F4748: m0 (BCA m7, BTA m6)
--     or m1 (BCA m9, BTA m8) by the unit table, on their end when pressed
--   units 18..24 (m26 c03_wall1s) and 25..31 (m27 c03_wall2s), both at each
--     wall's centre 0x21F4694: state 0 hides the second, 1 the first -- the
--     wax and the honey it turns to
-- (src/world/Gen5CasteliaGym.lua holds the switch / press / wall rules.)
-- A press's posts and a wall turning are watched for here and played from
-- frame 0 when they change (INFERRED: 0x18C / 0x18D run those tasks at the
-- moment the switch script fires; the wall's swap is immediate).
local CASTELIA = {
  arc = 135,
  switches = { { 26.5, 0, 17.5 }, { 38.5, 0, 17.5 }, { 20.5, 0, 21.5 }, { 32.5, 0, 21.5 },
               { 44.5, 0, 21.5 }, { 26.5, 0, 25.5 }, { 32.5, 0, 29.5 }, { 44.5, 0, 29.5 } },
  posts = { { 30.5, 0, 17.5 }, { 34.5, 0, 17.5 }, { 24.5, 0, 21.5 }, { 28.5, 0, 21.5 }, { 36.5, 0, 21.5 },
            { 40.5, 0, 21.5 }, { 22.5, 0, 25.5 }, { 28.5, 0, 29.5 }, { 36.5, 0, 29.5 }, { 40.5, 0, 29.5 } },
  -- unit 8 + i's model (ov38 unit table): 0 = m0, 1 = m1
  postKind = { [0] = 0, 1, 0, 1, 0, 1, 1, 1, 0, 1 },
  walls = { { 32.5, 0, 17.5 }, { 26.5, 0, 21.5 }, { 38.5, 0, 21.5 }, { 20.5, 0, 25.5 },
            { 26.5, 0, 29.5 }, { 38.5, 0, 29.5 }, { 32.5, 0, 33.5 } },
}
M.GYMS[29] = CASTELIA
local POST = { [0] = { model = 0, anims = { 7, 6 } }, { model = 1, anims = { 9, 8 } } }
function CASTELIA.effects(def, save, st, now)
  local CG = require("src.world.Gen5CasteliaGym")
  local out = {}
  local presses = CG.presses(save)
  st.seen = st.seen or {}
  local first = not st.seen.castelia
  st.seen.castelia = true
  local v = (save and save.gen4Vars) or {}
  for k, pos in ipairs(CASTELIA.switches) do
    local i = k - 1
    local on = (tonumber(v[0x4000 + i]) or 0) ~= 0
    local key = "switch" .. i
    if on and not first and not st.seen[key] then M.play(def, key, 12) end
    st.seen[key] = on
    local list = {}
    for _, m in ipairs({ 12, 13 }) do
      local _, f = playing(st, key, CASTELIA.arc, now)
      if f then f = math.min(f, M.lastFrame(CASTELIA.arc, m)) else f = on and M.lastFrame(CASTELIA.arc, m) or 0 end
      list[#list + 1] = { m, f }
    end
    out[#out + 1] = effect(def, CASTELIA.arc, 3, pos, nil, list)
  end
  for k, pos in ipairs(CASTELIA.posts) do
    local i = k - 1
    local kind = POST[CASTELIA.postKind[i]]
    local on = presses[i] == true
    local key = "post" .. i
    if on and not first and not st.seen[key] then M.play(def, key, kind.anims[1]) end
    st.seen[key] = on
    local list = {}
    for _, m in ipairs(kind.anims) do
      local _, f = playing(st, key, CASTELIA.arc, now)
      if f then f = math.min(f, M.lastFrame(CASTELIA.arc, m)) else f = on and M.lastFrame(CASTELIA.arc, m) or 0 end
      list[#list + 1] = { m, f }
    end
    out[#out + 1] = effect(def, CASTELIA.arc, kind.model, pos, nil, list)
  end
  for k, pos in ipairs(CASTELIA.walls) do
    local open = CG.wallOpen(save, k - 1)
    out[#out + 1] = effect(def, CASTELIA.arc, open and 27 or 26, pos, nil, {})
  end
  return out
end

-- ------------------------------------------------------------- OPELUCID --
-- Zone 121, overlay 46, arc 162 (READ FROM CODE: ov46 0x21F36C0):
--   per dragon i (0..2), five units 5i..5i+4:
--     the body m0 at 0x21F4194 + 12i, turned 0x21F4108[i] (0x8000, 0, 0),
--       eight BCAs m4..m11 (81 frames);
--     its arms m1 / m2 at 0x21F4170 + 12i, the same turn, BCAs m14 / m15
--       and m12 / m13 (41 frames: up, pressed);
--     two lamps m16 (BTP m17) at 0x21F4204 + 24i and + 12, unturned
--   unit 15: the floor's glow m3 (BTA m18, 121 frames) at (32, 0, 32),
--     attached and running
--   0x21F38D4 poses a dragon from the save: the head (0x21F3BC8: off/off 0,
--   on/on 1, on/off 2, off/on 3) picks body animation 1 / 5 / 2 / 0 and sets
--   it to its end; each arm its animation 1 (pressed) or 0 on its end.
-- A head or an arm changing is played from frame 0 (INFERRED: the 0x197 /
-- 0x199 tasks; the arms' and the body's animations end on the pose the load
-- sets).
local OPELUCID = {
  arc = 162,
  bodies = { { 12.5, 0, 31.0 }, { 42.5, 0, 21.0 }, { 27.5, 6.0, 26.0 } },
  turns = { [0] = 0x8000, 0, 0 },
  arms = { { 12.5, 0, 29.0 }, { 42.5, 0, 23.0 }, { 27.5, 6.0, 28.0 } },
  lamps = { { 17.5, 0, 29.5 }, { 7.5, 0, 29.5 }, { 37.5, 0, 22.5 }, { 47.5, 0, 22.5 },
            { 22.5, 6.0, 27.5 }, { 32.5, 6.0, 27.5 } },
  glow = { 32.0, 0, 32.0 },
  -- body animation (0..7 -> m4..m11) by head
  bodyAnim = { [0] = 1, 5, 2, 0 },
  -- arm unit -> model, { up, pressed } animations
  armL = { model = 1, anims = { [0] = 14, 15 } }, armR = { model = 2, anims = { [0] = 12, 13 } },
}
M.GYMS[121] = OPELUCID
function OPELUCID.effects(def, save, st, now)
  local out = {}
  local rec = save and save.bwDragonGym or {}
  st.seen = st.seen or {}
  local first = not st.seen.opelucid
  st.seen.opelucid = true
  for s = 0, 2 do
    local r = rec[tostring(s)] or { head = 0, [1] = 0, [2] = 0 }
    local turn = OPELUCID.turns[s] * 360 / 65536
    local head = tonumber(r.head) or 0
    local member = 4 + (OPELUCID.bodyAnim[head] or 1)
    local key = "body" .. s
    if not first and st.seen[key] ~= nil and st.seen[key] ~= head then M.play(def, key, member) end
    st.seen[key] = head
    local m, f = playing(st, key, OPELUCID.arc, now)
    if m ~= member then f = M.lastFrame(OPELUCID.arc, member) end
    out[#out + 1] = effect(def, OPELUCID.arc, 0, OPELUCID.bodies[s + 1], turn, { { member, f } })
    for side, arm in ipairs({ OPELUCID.armL, OPELUCID.armR }) do
      local on = (tonumber(r[side] or r[tostring(side)]) or 0) ~= 0
      local am = arm.anims[on and 1 or 0]
      local akey = "arm" .. s .. ":" .. side
      if not first and st.seen[akey] ~= nil and st.seen[akey] ~= on then M.play(def, akey, am) end
      st.seen[akey] = on
      local pm, pf = playing(st, akey, OPELUCID.arc, now)
      if pm ~= am then pf = M.lastFrame(OPELUCID.arc, am) end
      out[#out + 1] = effect(def, OPELUCID.arc, arm.model, OPELUCID.arms[s + 1], turn, { { am, pf } })
    end
    for l = 1, 2 do
      out[#out + 1] = effect(def, OPELUCID.arc, 16, OPELUCID.lamps[s * 2 + l], nil, { { 17, 0 } })
    end
  end
  local n = M.frames(OPELUCID.arc, 18)
  out[#out + 1] = effect(def, OPELUCID.arc, 3, OPELUCID.glow, nil, { { 18, frameSince(0, now) % n } })
  return out
end

-- ------------------------------------------------------------ DRIFTVEIL --
-- Zone 97, overlay 43, arc 138 (READ FROM CODE: ov43 0x21F36C0):
--   units 0..5, the six lifts (0..4 m0 rif_anim01, 5 m1 mainrif_anim01),
--     x / z from 0x21F4358, the height the lift's own record gives for the
--     state it is in (0x21F4480 + 24i: +0x10 one height, +0x14 the other);
--     their BTAs (m3 / m4, m5 / m6) attached stopped
--   unit 7, the arrival lift m0 at (15.5, 50, 25.5); unit 6, m2 (BCA m7) at
--     (15.5, -40, 24.5)
-- The heights are Gen5DriftveilGym's (flag 0x0A + i). A lift's move (0x190)
-- is eased from one height to the other at LIFT_SPEED units a field frame
-- (INFERRED: the overlay's own move task is not decoded), carrying the
-- player standing on it; the script waits for it.
local DRIFTVEIL = {
  arc = 138,
  lifts = { { 20.5, 25.5 }, { 20.5, 21.5 }, { 10.5, 25.5 }, { 15.5, 25.5 }, { 10.5, 21.5 }, { 15.5, 21.5 } },
  liftModel = { 0, 0, 0, 0, 0, 1 }, liftAnim = { 3, 3, 3, 3, 3, 5 },
  arrival = { 15.5, 50, 25.5 }, wall = { 15.5, -40, 24.5 },
}
M.LIFT_SPEED = 6
M.GYMS[97] = DRIFTVEIL
local function liftY(st, def, save, i, now)
  local gl = def.gen5Lifts
  local lift = gl and gl.lifts and gl.lifts[i]
  if not lift then return nil end
  local h = require("src.world.Gen5DriftveilGym").liftHeight(save, lift) * 16
  local mv = st.liftMove and st.liftMove[i]
  if mv then
    local f = frameSince(mv.start, now)
    local span = math.abs(mv.to - mv.from) * 16
    local d = math.min(span, f * M.LIFT_SPEED)
    -- (held at its new height until the panel's script flips its flag)
    if d >= span then
      if h == mv.to * 16 then st.liftMove[i] = nil end
      return mv.to * 16
    end
    return mv.from * 16 + (mv.to > mv.from and d or -d)
  end
  return h
end
function DRIFTVEIL.effects(def, save, st, now)
  local out = {}
  for i, xz in ipairs(DRIFTVEIL.lifts) do
    local y = liftY(st, def, save, i, now)
    if y then
      out[#out + 1] = effect(def, DRIFTVEIL.arc, DRIFTVEIL.liftModel[i], { xz[1], y / 16, xz[2] }, nil,
                             { { DRIFTVEIL.liftAnim[i], 0 } })
    end
  end
  out[#out + 1] = effect(def, DRIFTVEIL.arc, 0, DRIFTVEIL.arrival, nil, { { 3, 0 } })
  out[#out + 1] = effect(def, DRIFTVEIL.arc, 2, DRIFTVEIL.wall, nil, { { 7, 0 } })
  -- the player rides a moving lift: the sprite at the lift's height over
  -- the level the rule already put them on
  local ow = overworld()
  local ride = st.liftRide
  local p = ow and ow.player
  if ride and p then
    local y = liftY(st, def, save, ride.lift, now)
    local mv = st.liftMove and st.liftMove[ride.lift]
    if mv and y and not ride.landed then
      ride.offset.lift = y - ride.level * 16
      p.spriteOffset = ride.offset
    else
      if p.spriteOffset == ride.offset then p.spriteOffset = nil end
      st.liftRide = nil
    end
  end
  return out
end
-- the move's rule has run (the player's level is the new one): the sprite
-- goes back to standing on it
function M.liftLanded(ow)
  local def = ow and ow.map and ow.map.def
  local st = def and stateFor(def)
  local ride = st and st.liftRide
  local p = ow and ow.player
  if ride then
    ride.landed = true
    if p and p.spriteOffset == ride.offset then p.spriteOffset = nil end
    st.liftRide = nil
  end
end
-- 0x190 <n>: called around Gen5DriftveilGym.move (Gen5GymFxCommands)
function M.liftMoving(ow, save, n)
  local def = ow and ow.map and ow.map.def
  local gl = def and def.gen5Lifts
  local lift = gl and gl.lifts and gl.lifts[n + 1]
  if not lift then return 0 end
  local st = stateFor(def)
  local from = require("src.world.Gen5DriftveilGym").liftHeight(save, lift)
  local to = (from == lift.a) and lift.b or lift.a
  st.liftMove = st.liftMove or {}
  st.liftMove[n + 1] = { from = from, to = to, start = M.now(ow) }
  local p = ow.player
  local inside = p and p.cellX >= lift.x and p.cellX < lift.x + lift.w and p.cellY >= lift.z and p.cellY < lift.z + lift.h
  local run = ow.gen5LiftRun
  if inside and run and run.level == from then
    st.liftRide = { lift = n + 1, offset = { lift = 0 }, level = from }
  end
  return math.ceil(math.abs(to - from) * 16 / M.LIFT_SPEED)
end

-- -------------------------------------------------------------- NIMBASA --
-- Zone 63, overlay 39, arc 107 (READ FROM CODE: ov39 0x21F36FC):
--   units 0..3, the four cars m0 at their stations 0x21F4D60 / D0C / D6C /
--     D18 ((22.5,2,37.5) (41.5,2,38.5) (34.5,2,6.5) (5.5,2,37.5)); car t
--     wears its BTA m1 (stopped) and the ride BCA the track's switch picks,
--     unit animation 2t + 1 + switch (m13 m14 / m15 m16 / m17 m18 / m11 m12),
--     set to the frame the gym block keeps for it -- each BCA is one lap of
--     its track from the station and back
--   units 4..7, the switches m2 at (29.5,2,33.5) (13.5,2,16.5) (46.5,2,41.5)
--     (25.5,2,9.5), and 8..11 the tracks m20 m21 m22 m19 at the stations:
--     each wears its animation [switch] on its end (m3/m4 .. m9/m10 and
--     m25/m26, m27/m28, m29/m30, m23/m24)
-- A RIDE (OverworldController's dock step, Gen5Field's gen5Coaster): the car
-- runs its lap from where it rests to the frame nearest the boarding dock,
-- the player gets in, and it runs on to the frame nearest the other dock,
-- the player carried at the car's root (INFERRED: the lap's stop frames are
-- found from the path, not read from ov39's ride task). Then the step's own
-- landing (setMap) happens exactly as before.
local NIMBASA = {
  arc = 107,
  stations = { { 22.5, 2, 37.5 }, { 41.5, 2, 38.5 }, { 34.5, 2, 6.5 }, { 5.5, 2, 37.5 } },
  laps = { [0] = { 13, 14 }, { 15, 16 }, { 17, 18 }, { 11, 12 } },
  switches = { { 29.5, 2, 33.5 }, { 13.5, 2, 16.5 }, { 46.5, 2, 41.5 }, { 25.5, 2, 9.5 } },
  switchAnims = { [0] = { 3, 4 }, { 5, 6 }, { 7, 8 }, { 9, 10 } },
  rails = { [0] = 20, 21, 22, 19 },
  railAnims = { [0] = { 25, 26 }, { 27, 28 }, { 29, 30 }, { 23, 24 } },
}
M.GYMS[63] = NIMBASA
local function switchOf(save, t)
  local v = save and save.bwCoaster and save.bwCoaster[tostring(t)]
  return (tonumber(v) or 0) ~= 0 and 1 or 0
end
-- the car's root on lap `member` at frame f, world units on the map
local function carAt(def, t, member, f)
  local r = M.anim(NIMBASA.arc, member)
  local track = r and r.tracks and (r.tracks[0] or r.tracks["0"])
  local m = track and unpackAt(track, math.max(0, math.floor(f)))
  local x, y, z = at(def, NIMBASA.stations[t + 1][1], NIMBASA.stations[t + 1][2], NIMBASA.stations[t + 1][3])
  if m then x, y, z = x + m[4], y + m[8], z + m[12] end
  return x, y, z
end
function NIMBASA.effects(def, save, st, now)
  local out = {}
  st.carFrame = st.carFrame or {}
  for t = 0, 3 do
    local s = switchOf(save, t)
    local member = NIMBASA.laps[t][s + 1]
    local f = st.carFrame[t] or 0
    local ride = st.ride
    if ride and ride.track == t then member, f = ride.member, ride.frame end
    out[#out + 1] = effect(def, NIMBASA.arc, 0, NIMBASA.stations[t + 1], nil, { { member, f }, { 1, 0 } })
    local sa = NIMBASA.switchAnims[t]
    out[#out + 1] = effect(def, NIMBASA.arc, 2, NIMBASA.switches[t + 1], nil,
                           { { sa[s + 1], M.lastFrame(NIMBASA.arc, sa[s + 1]) } })
    local ra = NIMBASA.railAnims[t]
    out[#out + 1] = effect(def, NIMBASA.arc, NIMBASA.rails[t], NIMBASA.stations[t + 1], nil,
                           { { ra[s + 1], M.lastFrame(NIMBASA.arc, ra[s + 1]) } })
  end
  return out
end

-- -------------------------------------------------------------- MISTRALTON --
-- Zone 108, overlay 41, arc 121 (READ FROM CODE: ov41 0x21F36C0):
--   units 0..9, the cannons m0 at 0x21F4208 (Gen5Field's gen5Cannons),
--     turned a quarter per their byte at 0x21F4660 (1 3 0 0 1 2 3 0 1 2,
--     via the sine table, MTX_RotY33), each wearing BCA / BMA pairs m1/m2,
--     m3/m4 (114 frames), m5/m6, m7/m8 (144)
--   a shot (task 0x21F3884): the landing record's arc row (0x21F4198, 8
--     bytes: ..., u8 +5 = 50 frames of flight, u8 +6 = 25 of landing)
-- Here the shot plays the cannon's first pair for FIRE_FRAMES, then flies
-- the player on a parabola from the cannon's mouth to the landing over
-- FLIGHT_FRAMES (READ FROM CODE: 50), PEAK units over the higher end
-- (INFERRED), then the press's own landing (setMap) as before.
local MISTRALTON = { arc = 121, turns = { 1, 3, 0, 0, 1, 2, 3, 0, 1, 2 } }
M.FIRE_FRAMES, M.FLIGHT_FRAMES, M.PEAK = 20, 50, 96
M.GYMS[108] = MISTRALTON
function MISTRALTON.effects(def, save, st, now)
  local out = {}
  for i, c in ipairs(def.gen5Cannons or {}) do
    local turn = (MISTRALTON.turns[i] or 0) * 90
    local f = 0
    local shot = st.ride
    if shot and shot.cannon == i then f = shot.fire or 0 end
    out[#out + 1] = effect(def, MISTRALTON.arc, 0, { c.x, c.height, c.z }, turn, { { 1, f }, { 2, f } })
  end
  return out
end

-- ============================================================= THE RIDES ==
-- A ride owns the player: a state over the field (isOpaque false, so the
-- field still draws under it) that moves the sprite each tick and, when
-- done, pops and runs the move the step would have made at once.
local function rideState(ow, def, st, step, finish)
  local p = ow.player
  local S = { name = "Gen5GymFx ride", isOpaque = false, tick = 0, offset = {} }
  local saved = { px = p.px, py = p.py }
  function S:update()
    self.tick = self.tick + 1
    local done = step(self, math.floor(self.tick / M.TICKS_PER_FRAME))
    if done then
      local G = Game()
      if p.spriteOffset == self.offset then p.spriteOffset = nil end
      st.ride = nil
      if G and G.stack and G.stack:top() == self then G.stack:pop() end
      finish()
    end
  end
  function S:draw() end
  -- the sprite at world (x, y, z): its cell corner and its lift over the
  -- ground there
  function S:place(x, y, z)
    p.px, p.py = x - 8, z - 8
    local ground = ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
    local under = ground and ground.groundY and ground:groundY(x, z) or 0
    self.offset.lift = y - under
    p.spriteOffset = self.offset
  end
  S.saved = saved
  return S
end

local function push(S)
  local G = Game()
  if not (G and G.stack) then return false end
  G.stack:push(S)
  return true
end

-- the frame of lap `member` (car t) nearest a dock's cell
local function nearestFrame(def, t, member, dock)
  local n = M.frames(NIMBASA.arc, member)
  local bx, bz = (dock.x + 0.5) * 16, (dock.y + 0.5) * 16
  local best, bestD = 0, math.huge
  for f = 0, n - 1 do
    local x, _, z = carAt(def, t, member, f)
    local d = (x - bx) ^ 2 + (z - bz) ^ 2
    if d < bestD then best, bestD = f, d end
  end
  return best
end

-- Nimbasa: true when a ride was started (finish runs at its end)
function M.coasterRide(ow, fromDock, toDock, finish)
  local def = ow and ow.map and ow.map.def
  local coaster = def and def.gen5Coaster
  if not (coaster and art() and M.model(NIMBASA.arc, 0)) then return false end
  local G = Game()
  local save = G and G.save
  local t = tonumber(coaster.track[fromDock] or coaster.track[tostring(fromDock)])
  local a = coaster.docks[fromDock] or coaster.docks[tostring(fromDock)]
  local b = coaster.docks[toDock] or coaster.docks[tostring(toDock)]
  if not (t and a and b) then return false end
  local st = stateFor(def)
  st.carFrame = st.carFrame or {}
  local member = NIMBASA.laps[t][switchOf(save, t) + 1]
  local n = M.frames(NIMBASA.arc, member)
  local rest = (st.carFrame[t] or 0) % n
  local board = nearestFrame(def, t, member, a)
  local land = nearestFrame(def, t, member, b)
  local toBoard = (board - rest) % n
  local ride = (land - board) % n
  if ride == 0 then return false end
  st.ride = { track = t, member = member, frame = rest }
  local S = rideState(ow, def, st, function(self, f)
    local r = st.ride
    if not r then return true end
    if f <= toBoard then
      r.frame = (rest + f) % n
      return false
    end
    local k = f - toBoard
    r.frame = (board + math.min(k, ride)) % n
    local x, y, z = carAt(def, t, member, r.frame)
    self:place(x, y + 4, z)
    if k >= ride then
      st.carFrame[t] = r.frame
      return true
    end
    return false
  end, finish)
  return push(S)
end

-- Mistralton: true when a shot was started
function M.cannonShot(ow, cannon, landing, finish)
  local def = ow and ow.map and ow.map.def
  if not (def and def.gen5Cannons and art() and M.model(MISTRALTON.arc, 0)) then return false end
  local st = stateFor(def)
  local index
  for i, c in ipairs(def.gen5Cannons) do if c == cannon then index = i end end
  if not index then return false end
  local x0, y0, z0 = at(def, cannon.x, cannon.height, cannon.z)
  local x1, y1, z1 = at(def, landing.x + 0.5, landing.height, landing.z + 0.5)
  local peak = math.max(y0, y1) + M.PEAK
  st.ride = { cannon = index, fire = 0 }
  local p = ow.player
  local S = rideState(ow, def, st, function(self, f)
    local r = st.ride
    if not r then return true end
    if f < M.FIRE_FRAMES then
      r.fire = f
      -- in the barrel
      self:place(x0, y0, z0)
      self.offset.hidden = true
      p.hidden = true
      return false
    end
    p.hidden = nil
    r.fire = math.min(f, M.FIRE_FRAMES)
    local k = math.min(1, (f - M.FIRE_FRAMES) / M.FLIGHT_FRAMES)
    -- the parabola through (0, y0), (1, y1) with its top at `peak`
    local a = math.sqrt(math.max(0, peak - y0))
    local b = math.sqrt(math.max(0, peak - y1))
    local tTop = a / (a + b)
    local y
    if k <= tTop then
      local u = (tTop - k) / tTop
      y = peak - (peak - y0) * u * u
    else
      local u = (k - tTop) / (1 - tTop)
      y = peak - (peak - y1) * u * u
    end
    self:place(x0 + (x1 - x0) * k, y, z0 + (z1 - z0) * k)
    return k >= 1
  end, function() p.hidden = nil; finish() end)
  return push(S)
end

-- ============================================================ THE HOOKS ==

local function gymOf(def)
  return def and def.gen5 and M.GYMS[tonumber(def.header) or -1] or nil
end

function M.effects(ow, ground)
  local def = ground and ground.def
  local gym = gymOf(def)
  if not (gym and art()) then return {} end
  local G = Game()
  local st = stateFor(def)
  local ok, list = pcall(gym.effects, def, G and G.save, st, M.now(ow))
  if not ok then
    if not st.warned then
      st.warned = true
      pcall(function() require("src.core.Logger").warn("gen5 gym fx: %s", tostring(list)) end)
    end
    return {}
  end
  local out = {}
  for _, e in ipairs(list or {}) do if e then out[#out + 1] = e end end
  if gym.extra then
    local okE, more = pcall(gym.extra, def, G and G.save, st, M.now(ow), ow)
    if okE then for _, e in ipairs(more or {}) do if e then out[#out + 1] = e end end end
  end
  return out
end

-- the map's def is handed the provider when the overworld loads it
function M.attach(def)
  if not gymOf(def) then return end
  if def.gen4GymFxProvider == nil then
    def.gen4GymFxProvider = function(ow, ground) return M.effects(ow, ground) end
  end
end

-- a gym command (Gen5GymFxCommands): the frames the script waits, or nil
function M.op(ctx, op, n)
  local ow = ctx and ctx.overworld or overworld()
  local def = ow and ow.map and ow.map.def
  local gym = gymOf(def)
  if not (gym and gym.op) then return nil end
  local st = stateFor(def)
  local ok, frames = pcall(gym.op, def, st, op, math.floor(tonumber(n) or 0), ctx)
  if ok then return frames end
  return nil
end

return M
