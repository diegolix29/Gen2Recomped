-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ETERNA GYM'S FLOWER CLOCK (pokeplatinum src/overlay008/gym_features.c,
-- EternaGym_*; src/overlay005/ov5_021F4018.c, the fountains;
-- src/dynamic_map_features.c, the jump; res/field/scripts/
-- scripts_eterna_city_gym.s).
--
-- The port kept the state (Gen4DynamicMapFeatures.advanceEternaClock and
-- VAR_ETERNA_GYM_FLOWER_CLOCK_STATE 0x404B) and the planner walked from the
-- door to Gardenia. READ FROM CODE:
--
--   * the clock is a STATE, 0..4: initial, then one more for each of Lass
--     Caroline, Aroma Lady Jenna, Aroma Lady Angela and Gardenia beaten -- each
--     of their scripts ends `AdvanceEternaGymClock` (nothing else turns it;
--     there are no switch tiles in Platinum's gym).
--   * EternaGym_DynamicMapFeaturesInit: the state is read back from the var;
--     the hour hand (eterna_gym_model_clock_hour_hand, y 12) and the minute
--     hand (..._minute_hand, y 13) are loaded at the clock's centre, tile
--     (11, 13), posed at sEternaGymClockTimes[state] (7:25, 6:15, 9:15, 0:45,
--     0:30) by EternaGym_UpdateClockHandPositions; while the state is below
--     DEFEATED_THIRD_TRAINER the fountains are laid (ov5_021F4098: four
--     fldeff eterna_gym_fountain models on (1..4, 19) and (18..21, 19); the
--     right four only in states 0 and 1).
--   * EternaGym_DynamicMapFeaturesCheckCollision: inside the 13 x 13 clock
--     ((5,7)-(17,19)) sEternaGymClockCollision[state]; on row 19
--     sEternaGymFountainCollision[state]. A 1 is a wall; a 0 lets the map's
--     own collision answer (the function returns isColliding, and FALSE sends
--     TerrainCollisionManager on to the tile).
--   * EternaGym_IsHourHandJumpTile (PlayerAvatar_WillJump): the hour hand's
--     tile for the state -- (11,18) N/S, (6,13) W/E, (11,8) N/S, (11,8) N/S --
--     is a ledge in either direction along its axis: the player jumps it.
--   * EternaGym_AdvanceClockState (a FieldTask_InitCall the script waits on):
--     a camera object walks (WALK_NORMAL, 8 field frames a tile) from the
--     player to the clock's centre, 8 frames, SEQ_SE_PL_TOKEI21, the time
--     moves 2 minutes a field frame to the new state's (with the leader's
--     state holding the hour hand at 0 and sweeping only the minute hand),
--     SEQ_SE_DP_PIRORIRO2, 8 frames; after the 2nd and 3rd trainers the
--     camera goes on to (11,19) and the right / left fountain (20 / 2, 19),
--     4 frames, that fountain stops (SEQ_SE_DP_T_AME), 60 frames, "The
--     fountain's water level dropped!" until A or B; then the camera walks
--     back to the player.
--
-- THE FOUNTAINS, as ov5_021F4018.c draws them (src/world/Gen4GymFx.lua):
-- each of the four tiles of a side is the fldeff model at the tile's centre
-- and terrain height wearing its own copy of eterna_gym_fountain.nsbtp (166,
-- gym04_hunsui_a, 18 frames) looped a frame a field frame; ov5_021F416C
-- swaps a side's four to eterna_gym_fountain_stopping.nsbtp (167,
-- gym04_hunsui_b, 27 frames) played once, and each is finished
-- (FieldEffectManager_FinishAnimManager) the frame after it reaches its end --
-- the 60-frame wait before the message runs on beside it. The pictures are
-- the ones Gen4GymFxArt decodes (`gen4_gym_fx`); on a cache without them the
-- fountain is its still model.

local M = {}

M.MAP = "C04GYM0101"
M.TICKS_PER_FRAME = 2
M.HOUR_MODEL, M.MINUTE_MODEL = 537, 536          -- build_model members
M.FOUNTAIN_MODEL = 111                           -- fldeff eterna_gym_fountain
M.CENTER_X, M.CENTER_Z = 11, 13
M.LEFT, M.TOP, M.SIZE = 5, 7, 13
M.FOUNTAIN_Z = 19
M.LEFT_FOUNTAIN_X, M.RIGHT_FOUNTAIN_X = 2, 20
M.VAR = 0x404B
M.TEXT_DROPPED = 12                              -- EternaGym_Text_FountainWaterLevelDropped

-- sEternaGymClockTimes
M.TIMES = { [0] = { 7, 25 }, { 6, 15 }, { 9, 15 }, { 0, 45 }, { 0, 30 } }
-- sEternaGymHourHandJumpTiles: { x, z, axis north-south }
M.JUMP = { [1] = { 11, 18, true }, [2] = { 6, 13, false }, [3] = { 11, 8, true }, [4] = { 11, 8, true } }

-- sEternaGymClockCollision, row by row (z = 7..19)
local CLOCK = {
  [0] = {
    "1111111111111", "1111111111111", "1111111111111", "1111111111111", "1111111111111",
    "1111111111111", "1111111111111", "1111111111111", "1111111111111", "1111111111111",
    "1111111111111", "1111111111111", "0110000000110" },
  [1] = {
    "1111111111110", "1111111111111", "1111111111111", "1111111111110", "1111111111110",
    "1111110111110", "1111100000000", "1111110111110", "1111110111110", "1111110111110",
    "1111110111111", "1111110111111", "0110000000110" },
  [2] = {
    "0111111111110", "1111111111111", "1111111111111", "0111111111110", "0111111111110",
    "0111110111110", "0000000000000", "0111110111110", "0111111111110", "0111111111110",
    "1111111111111", "1111111111111", "0110000000110" },
  [3] = {
    "0110000000110", "1111110111111", "1111110111111", "0111110111110", "0111110111110",
    "0111110111110", "0000000011110", "0111110111110", "0111111111110", "0111111111110",
    "1111111111111", "1111111111111", "0110000000110" },
  [4] = {
    "0110000000110", "1111110111111", "1111110111111", "0111110111110", "0111110111110",
    "0111110111110", "0111100011110", "0111110111110", "0111110111110", "0111110111110",
    "1111110111111", "1111110111111", "0110000000110" },
}
-- sEternaGymFountainCollision (x 1..21 on row 19)
local FOUNTAIN = {
  [0] = "111100000000000001111", [1] = "111100000000000001111", [2] = "111100000000000000000",
  [3] = "000000000000000000000", [4] = "000000000000000000000",
}

local ROT = { [0] = 0, 0x1559, 0x1559 * 2, 0x4000, 0x1559 * 4, 0x1559 * 5, 0x8000, 0x1559 * 7,
              0x1559 * 8, 0xC000, 0x1559 * 10, 0x1559 * 11 }     -- sEternaGymRotationForHour
local DEG6 = 1092                                                  -- DEG_TO_IDX(6)

local function game() return package.loaded["src.core.Game"] end
local function DMF() return require("src.world.Gen4DynamicMapFeatures") end

function M.isGym(def)
  return def ~= nil and (def.id == M.MAP or def.sourceId == M.MAP)
end

local function slot(save)
  return save and DMF().buffer(save, DMF().ETERNA_GYM)
end

local function stateOf(save)
  local b = slot(save)
  local s = b and tonumber(b.state) or 0
  if s < 0 then s = 0 end
  if s > 4 then s = 4 end
  return s
end

-- EternaGym_DynamicMapFeaturesCheckCollision
function M.collides(state, x, z)
  local hit = false
  if z >= M.TOP and z <= M.TOP + M.SIZE - 1 and x >= M.LEFT and x <= M.LEFT + M.SIZE - 1 then
    local row = CLOCK[state][z - M.TOP + 1]
    hit = row:sub(x - M.LEFT + 1, x - M.LEFT + 1) == "1"
  end
  if not hit and z == M.FOUNTAIN_Z and x >= 1 and x <= 21 then
    hit = FOUNTAIN[state]:sub(x, x) == "1"
  end
  return hit
end

-- EternaGym_IsHourHandJumpTile
function M.isJumpTile(state, x, z, dir)
  local j = M.JUMP[state]
  if not (j and j[1] == x and j[2] == z) then return false end
  if j[3] then return dir == "up" or dir == "down" end
  return dir == "left" or dir == "right"
end

-- EternaGym_UpdateClockHandPositions: the two props' y rotations, as u16
-- indices (MapProp rotation = 0x10000 - the hand's own)
function M.handAngles(sys)
  local minute, hour = sys.minute, sys.hour
  local m
  if minute % 15 == 0 then m = ROT[math.floor(minute / 5)] else m = minute * (DEG6 + 1) end
  m = (m - 0x4000) % 0x10000
  local h = ROT[hour]
  if sys.rotateHourHand then h = h + math.floor((5 * (DEG6 + 1)) / 60) * minute end
  h = (h + 0x8000) % 0x10000
  return (0x10000 - h) % 0x10000, (0x10000 - m) % 0x10000
end

local function groundY(map, x, z)
  local HR = require("src.world.Gen4HeightRule")
  local list = map and HR.surfaces(map, x, z) or {}
  return (#list > 0) and HR.nearest(list, 0) or 0
end

M.FOUNTAIN_RUN, M.FOUNTAIN_STOP = 166, 167     -- fldeff eterna_gym_fountain(_stopping).nsbtp

-- the fountains (Gen4GymFx): the running loop on the frame clock, a stopping
-- side on its own frame (sys.stopFrame)
local function fountains(ow, def, sys, ground)
  local out = {}
  local GymFx = require("src.world.Gen4GymFx")
  local run = GymFx.frameAt(M.FOUNTAIN_RUN,
    require("src.render.Gen4PropClock").fieldFrame(ground and ground.clock or 0), true)
  for side, on in pairs(sys.fountains or {}) do
    if on then
      local anim = { member = M.FOUNTAIN_RUN, frame = run }
      if sys.stopping == side then anim = { member = M.FOUNTAIN_STOP, frame = sys.stopFrame or 0 } end
      local x0 = side == "left" and 1 or 18
      for x = x0, x0 + 3 do
        out[#out + 1] = { member = M.FOUNTAIN_MODEL, anims = { anim },
                          x = x * 16 + 8, y = groundY(ow and ow.map, x, M.FOUNTAIN_Z), z = M.FOUNTAIN_Z * 16 + 8 }
      end
    end
  end
  return out
end
M.fountains = fountains

-- the hands as runtime props, the fountains as field effects
local function draw(ow, def, sys)
  local keep = {}
  for _, p in ipairs(type(def.gen4RuntimeProps) == "table" and def.gen4RuntimeProps or {}) do
    if not p.eternaClock then keep[#keep + 1] = p end
  end
  local hourIdx, minIdx = M.handAngles(sys)
  local cx, cz = M.CENTER_X * 16 + 8, M.CENTER_Z * 16 + 8
  keep[#keep + 1] = { model = M.HOUR_MODEL, x = cx, y = 12, z = cz, rotY = hourIdx * 360 / 0x10000, eternaClock = true }
  keep[#keep + 1] = { model = M.MINUTE_MODEL, x = cx, y = 13, z = cz, rotY = minIdx * 360 / 0x10000, eternaClock = true }
  def.gen4GymFxProvider = function(o, ground) return fountains(o or ow, def, sys, ground) end
  -- a fresh list each time, so Gen4Ground re-reads it
  def.gen4RuntimeProps = keep
end

local function hook(def)
  local prior = def.gen4EternaPriorHook
  return function(map, tx, ty, mover)
    local G = game()
    if G and slot(G.save) and M.collides(stateOf(G.save), tx, ty) then return true end
    if prior then return prior(map, tx, ty, mover) end
    return nil
  end
end

-- EternaGym_DynamicMapFeaturesInit
function M.apply(ow, save)
  local def = ow and ow.map and ow.map.def
  if not M.isGym(def) then return nil end
  local b = slot(save)
  if not b then return nil end
  -- the state comes back from VAR_ETERNA_GYM_FLOWER_CLOCK_STATE
  local vars = save.gen4Vars or {}
  local s = tonumber(vars[M.VAR]) or 0
  if s < 0 or s > 4 then s = 0 end
  b.state = s
  local t = M.TIMES[s]
  local sys = { hour = t[1], minute = t[2], rotateHourHand = false, fountains = {} }
  -- ov5_021F4098(fieldSystem, {2, 2, 0}[state]): both, both, the left only
  if s < 3 then
    sys.fountains.left = true
    if s < 2 then sys.fountains.right = true end
  end
  def.gen4EternaClock = sys
  if not def.gen4EternaHooked then
    def.gen4EternaPriorHook = def.gen4CollisionHook
    def.gen4CollisionHook = hook(def)
    def.gen4EternaHooked = true
  end
  draw(ow, def, sys)
  return s
end

-- PlayerAvatar_WillJump's first question, from OverworldState:checkLedgeHop
function M.jumpAhead(ow, fx, fy, dir)
  local def = ow and ow.map and ow.map.def
  local G = game()
  if not (M.isGym(def) and G and slot(G.save)) then return false end
  return M.isJumpTile(stateOf(G.save), fx, fy, dir)
end

-- EternaGym_UpdateClockHandTimes
local function increment(sys, step)
  sys.minute = sys.minute + step
  while sys.minute >= 60 do sys.minute = sys.minute - 60 sys.hour = sys.hour + 1 end
  while sys.minute < 0 do sys.minute = sys.minute + 60 sys.hour = sys.hour + 1 end
  sys.hour = sys.hour % 12
end

function M.updateTimes(sys, destH, destM)
  local oldH, oldM = sys.hour, sys.minute
  if oldH ~= destH or oldM ~= destM then
    increment(sys, 2)
    local newH, newM = sys.hour, sys.minute
    if newH == destH then
      if oldM > newM then
        if oldM < destM + 60 and newM + 60 > destM + 60 then newM = destM end
      elseif oldM < destM and newM > destM then
        newM = destM
      end
    end
    sys.hour, sys.minute = newH, newM
  end
  return sys.hour == destH and sys.minute == destM
end

-- one frame of FieldTask_EternaGym_AdvanceClockState's hand sweep
function M.sweepFrame(sys, state)
  local t = M.TIMES[state]
  local destH, destM = t[1], t[2]
  if state == 4 and sys.hour == destH and sys.minute > destM then sys.hour = 11 end
  local done = M.updateTimes(sys, destH, destM)
  if state == 4 then sys.hour = t[1] end
  if sys.hour == destH then
    if sys.minute <= destM or state == 4 then sys.rotateHourHand = false end
  else
    sys.rotateHourHand = true
  end
  return done
end

-- the camera object: an invisible body the view tracks (cameraTarget)
local function cameraMan(ow)
  return { moveXFirst = false }
end

local function setupFrom(cm, sx, sz, dx, dz)
  cm.startX, cm.startZ, cm.destX, cm.destZ = sx, sz, dx, dz
  cm.dirX = (dx - sx < 0) and -1 or 1
  cm.dirZ = (dz - sz < 0) and -1 or 1
  if math.abs(dx - sx) < math.abs(dz - sz) then cm.moveXFirst = true end
end

-- EternaGym_MoveCamera, a tick at a time: true once at the destination
local function moveCamera(cm, cam)
  if cam.walk then
    cam.walk.t = cam.walk.t + 1
    local k = cam.walk.t / cam.walk.n
    cam.px = cam.walk.fx + (cam.walk.tx - cam.walk.fx) * k
    cam.py = cam.walk.fy + (cam.walk.ty - cam.walk.fy) * k
    if cam.walk.t >= cam.walk.n then
      cam.cellX, cam.cellY = cam.walk.cx, cam.walk.cy
      cam.px, cam.py = cam.cellX * 16, cam.cellY * 16
      cam.walk = nil
    end
    return false
  end
  local x, z = cam.cellX, cam.cellY
  if x == cm.destX and z == cm.destZ then return true end
  local dx, dz = 0, 0
  if cm.moveXFirst then
    if x ~= cm.destX then dx = cm.dirX elseif z ~= cm.destZ then dz = cm.dirZ end
  else
    if z ~= cm.destZ then dz = cm.dirZ elseif x ~= cm.destX then dx = cm.dirX end
  end
  -- MOVEMENT_ACTION_WALK_NORMAL_*: 8 field frames a tile
  cam.walk = { t = 0, n = 8 * M.TICKS_PER_FRAME, fx = cam.px, fy = cam.py,
               tx = (x + dx) * 16, ty = (z + dz) * 16, cx = x + dx, cy = z + dz }
  return false
end

-- EternaGym_AdvanceClockState, after the state has moved: the phases as
-- step functions the script runner polls. Answers (sweep, afterMessage) --
-- the second is nil when no fountain stops (no message) -- or nil.
function M.advance(ow, save)
  local def = ow and ow.map and ow.map.def
  if not M.isGym(def) then return nil end
  local sys = def.gen4EternaClock
  if not sys then M.apply(ow, save) return nil end
  local state = stateOf(save)
  local G = game()
  local function se(name) pcall(function() require("src.core.Sound").playSe(G.data, name) end) end
  local function stopSe(name) pcall(function() require("src.core.Sound").stopSe(G.data, name) end) end
  local p = ow.player
  local cam = { cellX = p.cellX, cellY = p.cellY, px = p.cellX * 16, py = p.cellY * 16, hidden = true }
  local cm = cameraMan(ow)
  setupFrom(cm, p.cellX, p.cellY, M.CENTER_X, M.CENTER_Z)
  ow.gen4Camera = cam
  local phase, tick, delay = 1, 0, 0
  local fountainsStop = (state == 2 or state == 3)
  local function back()
    -- EternaGym_FreeCameraObject: the view tracks the player again
    if ow.gen4Camera == cam then ow.gen4Camera = nil end
  end
  local first = function()
    tick = tick + 1
    if phase == 1 then
      if moveCamera(cm, cam) then phase = 2 end
      return false
    end
    if tick % M.TICKS_PER_FRAME ~= 0 then return false end
    if phase == 2 then
      delay = delay + 1
      if delay < 8 then return false end
      delay = 0
      se("SEQ_SE_PL_TOKEI21")
      phase = 3
    end
    if phase == 3 then
      local done = M.sweepFrame(sys, state)
      draw(ow, def, sys)
      if done then
        stopSe("SEQ_SE_PL_TOKEI21")
        se("SEQ_SE_DP_PIRORIRO2")
        phase = 4
      end
      return false
    end
    if phase == 4 then
      delay = delay + 1
      if delay < 8 then return false end
      delay = 0
      if fountainsStop then
        -- EternaGym_SetupCameraMoveToNewPosition(FALSE, 11, 19, W, S)
        cm.moveXFirst, cm.destX, cm.destZ, cm.dirX, cm.dirZ = false, M.CENTER_X, M.FOUNTAIN_Z, -1, 1
        phase = 7
      else
        -- EternaGym_SetupCameraMoveReverseOfLast
        cm.moveXFirst = not cm.moveXFirst
        cm.destX, cm.destZ = cm.startX, cm.startZ
        cm.dirX, cm.dirZ = -cm.dirX, -cm.dirZ
        phase = 5
      end
      return false
    end
    return false
  end
  -- the camera's walks run per tick, the rest per field frame
  local sweep = function()
    if phase == 7 or phase == 8 then
      if moveCamera(cm, cam) then
        if phase == 7 then
          local destX, dirX = M.RIGHT_FOUNTAIN_X, 1
          if state == 3 then destX, dirX = M.LEFT_FOUNTAIN_X, -1 end
          cm.moveXFirst, cm.destX, cm.destZ, cm.dirX, cm.dirZ = true, destX, M.FOUNTAIN_Z, dirX, 1
          phase = 8
        else
          phase, delay = 9, 0
        end
      end
      return false
    end
    if phase == 9 or phase == 10 then
      tick = tick + 1
      if tick % M.TICKS_PER_FRAME ~= 0 then return false end
      delay = delay + 1
      if phase == 9 and delay >= 4 then
        delay = 0
        -- ov5_021F416C: that fountain's stopping animation
        sys.stopping = (state == 2) and "right" or "left"
        sys.stopFrame = 0
        se("SEQ_SE_DP_T_AME")
        phase = 10
      elseif phase == 10 then
        -- ov5_021F4240: the stop played once; the frame after its end the
        -- side is finished
        if sys.stopping and sys.fountains[sys.stopping] then
          local GymFx = require("src.world.Gen4GymFx")
          if sys.stopFrame >= GymFx.frames(M.FOUNTAIN_STOP) - 1 then
            sys.fountains[sys.stopping] = nil
          else
            sys.stopFrame = sys.stopFrame + 1
          end
        end
        if delay >= 60 then
          stopSe("SEQ_SE_DP_T_AME")
          sys.fountains[sys.stopping] = nil
          sys.stopping, sys.stopFrame = nil, nil
          draw(ow, def, sys)
          return true                    -- the message comes next
        end
      end
      return false
    end
    if phase == 5 then
      if moveCamera(cm, cam) then back() return true end
      return false
    end
    return first()
  end
  -- after the message: the camera from where it is back to the player
  local after = fountainsStop and function()
    if not cm.returning then
      cm.returning = true
      setupFrom(cm, cm.destX, cm.destZ, p.cellX, p.cellY)
    end
    if moveCamera(cm, cam) then back() return true end
    return false
  end or nil
  return sweep, after
end

return M
