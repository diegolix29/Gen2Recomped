-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- VEILSTONE GYM'S PUNCHING BAGS AND TIRE STACKS (pokeplatinum
-- src/overlay008/gym_features.c, VeilstoneGym_*).
--
-- The port had neither: Maylene's gym was an open floor. Read from code:
--
--   * VeilstoneGym_InitMapObjects (on a fresh slot -- the gym's init script
--     runs InitPersistedMapFeaturesForVeilstoneGym on every entry): eleven
--     tire stacks and nine punching bags, each an invisible map object at
--     its table position minus 2 in z, drawn by the gym's own renderer
--     (fldeff veilstone_gym_tire_stack / _sandbag; the toppled stack is
--     _tire_stack_toppled). They block like any object.
--   * Field_CheckMapTransition -> VeilstoneGym_HitPunchingBag: the player
--     pushing against a bag (the cell ahead in the facing direction) hits it.
--     VeilstoneGym_CalculateDistanceBagWillTravel walks sVeilstoneTileBehaviors
--     (by the object's own coordinates): 1 is a wall, 3 no east-west, 5 no
--     west, 4 a PAUSE POINT (the bag stops there), and a tire stack on the
--     next tile stops it too. Nothing to travel: the bag only rocks.
--   * the travel: 30 field frames of wind-up (the speed from 1/60 a frame up
--     by 1/60 each), then the speed doubles each frame below 1 and is 2 from
--     frame 36; each 16 units is a tile, and the tile flags are asked again
--     there. Stopped with a tire stack ahead: 4 frames, the stack topples
--     (SEQ_SE_DP_UG_026) and is deleted once its animation ends.
--   * drawn as the gym's renderer draws them (veilstone_gym_object_renderer.c,
--     through src/world/Gen4GymFx.lua): each at its tile's centre, 6 up. A hit
--     plays the bag's swing (VeilstoneGymObjectRenderer_StartPunchingBag-
--     Animation): the animation for the side it was hit from
--     (Direction_GetOpposite: 182 + from-above/below/left/right), the "far"
--     one (+4) when it travels, a frame a field frame -- slowed to
--     13 / (tiles * 8) a frame while it slides, back to one once it stops --
--     and the task waits for it to end. A stack it stops against plays the
--     toppled model's four animations (nsbca 190, nsbma 195, nsbta 196,
--     nsbtp 168: 45 frames) and is deleted when all four have ended.
--   * the camera (VeilstoneGym_InitCameraManager and on): a push that will
--     carry the bag further than 3 tiles north or 4 any other way puts the
--     view on an invisible object at the player's tile; while the bag moves
--     at 1 unit a frame or more the object walks a tile at a time after it
--     (WALK_NORMAL, 8 frames a tile, up to 2 units a frame; WALK_FAST, 4,
--     above), as many tiles as the bag will travel; once the bag has stopped
--     (and its swing ended) it walks back the same way at WALK_FAST and the
--     view is the player's again.

local M = {}

M.MAP = "C07GYM0101"
M.MODEL_TOPPLED, M.MODEL_BAG, M.MODEL_TIRES = 112, 113, 114     -- fldeff.narc members
M.TICKS_PER_FRAME = 2
M.TOPPLE_FRAMES = 45          -- the toppled model's animations (the stack goes when they end)
M.KICK_FASTER, M.KICK_SLOW = 2, 16   -- WALK_ON_SPOT_FASTER / _SLOW, field frames

-- sTireStackPositions / sPunchingBagPositions (the objects stand 2 north)
M.TIRES = { { 3, 23 }, { 8, 12 }, { 8, 14 }, { 8, 16 }, { 12, 9 }, { 12, 12 }, { 19, 12 }, { 20, 13 },
            { 20, 28 }, { 22, 9 }, { 23, 30 } }
M.BAGS = { { 3, 12 }, { 4, 24 }, { 8, 9 }, { 8, 22 }, { 15, 28 }, { 16, 12 }, { 20, 19 }, { 21, 26 }, { 23, 13 } }

-- sVeilstoneTileBehaviors (32 x 32, by object coordinates)
local B = {}
do
  local rows = {
    [7]  = "11111111000400000000001111111111",
    [10] = "11101111100004004001111111111111",
    [11] = "11101111111111111111111011111111",
    [12] = "11135000111111111111011011111111",
    [13] = "11130111111111111111011011111111",
    [14] = "11100000111111111111011011111111",
    [15] = "11110111111111111111011011111111",
    [16] = "11110111111111111111301011111111",
    [17] = "11100000011111111111301011111111",
    [18] = "11100111011111111111101011111111",
    [19] = "11100111011111111111101011111111",
    [20] = "11100000011111111111141011111111",
    [21] = "11110111111111111111101011111111",
    [22] = "11110111111111111111101011111111",
    [23] = "11111111111111111111101011111111",
    [24] = "11111111111111111111101011111111",
    [25] = "11111111111111111111111011111111",
    [26] = "11111111111111100000111011111111",
    [27] = "11111111111111111111111011111111",
  }
  for z = 0, 31 do
    local row = rows[z] or ("1"):rep(32)
    for x = 0, 31 do B[z * 32 + x] = tonumber(row:sub(x + 1, x + 1)) end
  end
end
function M.tileBehaviour(x, z)
  if x < 0 or z < 0 or x > 31 or z > 31 then return 1 end
  return B[z * 32 + x]
end

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
M.CANT, M.TIRE, M.PAUSE = 1, 2, 4

local function DMF() return require("src.world.Gen4DynamicMapFeatures") end
local function game() return package.loaded["src.core.Game"] end

function M.isGym(def) return def ~= nil and (def.id == M.MAP or def.sourceId == M.MAP) end

local function state(save)
  local b = save and DMF().buffer(save, DMF().VEILSTONE_GYM)
  return b
end

local function tireAt(b, x, z)
  for i, t in ipairs(b.tires or {}) do
    if t.exists and t.x == x and t.z == z then return t, i end
  end
end
local function bagAt(b, x, z)
  for i, g in ipairs(b.bags or {}) do
    if g.x == x and g.z == z then return g, i end
  end
end

-- VeilstoneGym_GetTileFlags
function M.tileFlags(b, x, z, dir)
  local flags = 0
  local beh = M.tileBehaviour(x, z)
  if beh == 4 then flags = flags + M.PAUSE
  elseif beh == 2 and (dir == "up" or dir == "down") then flags = flags + M.CANT
  elseif beh == 3 and (dir == "left" or dir == "right") then flags = flags + M.CANT
  elseif beh == 5 and dir == "left" then flags = flags + M.CANT end
  local d = DIRS[dir]
  local nx, nz = x + d[1], z + d[2]
  if M.tileBehaviour(nx, nz) == 1 and flags % 2 == 0 then flags = flags + M.CANT end
  if tireAt(b, nx, nz) then flags = flags + M.TIRE end
  return flags
end

-- VeilstoneGym_CalculateDistanceBagWillTravel
function M.travel(b, x, z, dir)
  local flags = M.tileFlags(b, x, z, dir)
  if flags ~= 0 and flags ~= M.PAUSE then return 0, flags end
  local d, n = DIRS[dir], 0
  repeat
    x, z = x + d[1], z + d[2]
    n = n + 1
    flags = M.tileFlags(b, x, z, dir)
  until flags ~= 0
  return n, flags
end

-- what each bag and stack is playing now (not kept on the save)
local live = setmetatable({}, { __mode = "k" })
M.live = live
M.BAG_ANIM = 182                   -- veilstone_gym_sandbag_push_from_above
M.TIRE_ANIMS = { 190, 195, 196, 168 }   -- toppled: nsbca, nsbma, nsbta, nsbtp
M.Y_OFFSET = 6                     -- InitPunchingBagRenderer / TireStackAnim_Init
-- Direction_GetOpposite(dir) as the animation index (N 0, S 1, W 2, E 3)
local OPP_INDEX = { up = 1, down = 0, left = 3, right = 2 }
-- sVeilstoneTravelDistanceRequiringCameraMovement
M.CAMERA_AFTER = { up = 3, down = 4, left = 4, right = 4 }

-- the gym's renderer: bags, standing (or toppling) stacks (Gen4GymFx)
function M.draw(def, b, ground)
  if not (def and b) then return end
  local HR = require("src.world.Gen4HeightRule")
  local function y(x, z)
    local map = ground
    local list = map and HR.surfaces(map, x, z) or {}
    return ((#list > 0) and HR.nearest(list, 0) or 0) + M.Y_OFFSET
  end
  -- (the runtime props this module used to lay are taken back off)
  if type(def.gen4RuntimeProps) == "table" then
    local keep, had = {}, false
    for _, p in ipairs(def.gen4RuntimeProps) do
      if p.veilstone then had = true else keep[#keep + 1] = p end
    end
    if had then def.gen4RuntimeProps = keep end
  end
  local fx = {}
  for _, t in ipairs(b.tires or {}) do
    local l = live[t]
    if t.exists or t.toppling then
      local e = { member = t.toppling and M.MODEL_TOPPLED or M.MODEL_TIRES,
                  x = t.x * 16 + 8, y = y(t.x, t.z), z = t.z * 16 + 8 }
      if t.toppling and l and l.frame then
        e.anims = {}
        for i, m in ipairs(M.TIRE_ANIMS) do e.anims[i] = { member = m, frame = l.frame } end
      end
      fx[#fx + 1] = e
    end
  end
  for _, g in ipairs(b.bags or {}) do
    local l = live[g]
    local e = { member = M.MODEL_BAG, x = (g.px or g.x * 16 + 8), y = y(g.x, g.z), z = (g.pz or g.z * 16 + 8) }
    if l and l.anim then e.anims = { { member = l.anim, frame = l.frame } } end
    fx[#fx + 1] = e
  end
  def.gen4GymFx = fx
end

-- the objects block the way the invisible map objects do
local function hook(def)
  local prior = def.gen4VeilstonePriorHook
  return function(map, tx, ty)
    local G = game()
    local b = G and state(G.save)
    if b and b.initialized and (bagAt(b, tx, ty) or tireAt(b, tx, ty)) then return true end
    if prior then return prior(map, tx, ty) end
    return nil
  end
end

-- VeilstoneGym_DynamicMapFeaturesInit: a fresh slot gets the tables' layout
function M.apply(ow, save)
  local def = ow and ow.map and ow.map.def
  if not M.isGym(def) then return nil end
  local b = state(save)
  if not b then return nil end
  if not b.initialized then
    b.tires, b.bags = {}, {}
    for i, p in ipairs(M.TIRES) do b.tires[i] = { x = p[1], z = p[2] - 2, exists = true } end
    for i, p in ipairs(M.BAGS) do b.bags[i] = { x = p[1], z = p[2] - 2 } end
    b.initialized = true
  end
  if not def.gen4VeilstoneHooked then
    def.gen4VeilstonePriorHook = def.gen4CollisionHook
    def.gen4CollisionHook = hook(def)
    def.gen4VeilstoneHooked = true
  end
  M.draw(def, b, ow.map)
  return b
end

-- is there a bag for the player to hit, pushing `dir`?
function M.bagAhead(ow, dir)
  local def = ow and ow.map and ow.map.def
  local G = game()
  local b = G and state(G.save)
  local d = DIRS[dir]
  if not (M.isGym(def) and b and b.initialized and d) then return false end
  return bagAt(b, ow.player.cellX + d[1], ow.player.cellY + d[2]) ~= nil
end

-- Field_CheckMapTransition's call: the player pushing `dir` against a bag.
-- Answers a step function for the script runner (true when done), or nil
function M.hit(ow, dir)
  local def = ow and ow.map and ow.map.def
  local G = game()
  local b = G and state(G.save)
  if not (M.isGym(def) and b and b.initialized) then return nil end
  local p = ow.player
  local d = DIRS[dir]
  local bag = d and bagAt(b, p.cellX + d[1], p.cellY + d[2])
  if not bag then return nil end
  local dist = M.travel(b, bag.x, bag.z, dir)
  local function se(name) pcall(function() require("src.core.Sound").playSe(G.data, name) end) end
  se("SEQ_SE_PL_SUTYA2")
  local tick, frame = 0, 0
  -- VeilstoneGymObjectRenderer_StartPunchingBagAnimation: the swing for the
  -- side it was hit from, the far one when it travels
  local GymFx = require("src.world.Gen4GymFx")
  local swing = { anim = M.BAG_ANIM + OPP_INDEX[dir] + (dist > 0 and 4 or 0), frame = 0, delta = 1 }
  local swingFrames = GymFx.frames(swing.anim)
  live[bag] = swing
  -- PunchingBagAnim_Update, once a field frame: true once it has ended
  local function swingStep()
    if swing.done then return true end
    swing.frame = swing.frame + swing.delta
    if swing.frame >= swingFrames then swing.frame, swing.done = swingFrames - 1, true end
    return swing.done
  end
  -- THE PLAYER'S OWN KICK: LocalMapObj_SetAnimationCode(playerObj,
  -- MovementAction_TurnActionTowardsDir(dir, ...)) as the swing starts --
  -- MOVEMENT_ACTION_WALK_ON_SPOT_FASTER (2 field frames) when the bag only
  -- rocks, _SLOW (16) when it travels (pokeplatinum src/unk_020655F4.c,
  -- MovementAction_InitWalkOnSpot durations) -- and both tasks end only once
  -- LocalMapObj_CheckAnimationFinished(playerObj). The walk cycle on the
  -- spot is the engine's march; its clock starts a quarter-cycle in so even
  -- the two-frame kick lands on the stepping pose.
  local kick = { ticks = (dist == 0 and M.KICK_FASTER or M.KICK_SLOW) * M.TICKS_PER_FRAME }
  if p and ow.marchInPlace then
    kick.prev = p.stepFramesCur
    p.facing = dir
    p.stepFramesCur = kick.ticks
    p.animClock = 4
    pcall(ow.marchInPlace, ow, p)
    kick.on = true
  end
  local function kickDone()
    if not kick.on then return true end
    if p.marching then return false end
    p.stepFramesCur = kick.prev
    kick.on = false
    return true
  end
  M.lastKick = kick
  if dist == 0 then
    -- FieldTask_VeilstoneGym_HitPunchingBagNoMovement: the bag only rocks,
    -- and the task waits for the swing and the player's kick
    local over = false
    return function()
      tick = tick + 1
      if tick % M.TICKS_PER_FRAME ~= 0 then return false end
      if not over then
        over = swingStep()
        if over then live[bag] = nil end
        M.draw(def, b, ow.map)
      end
      return kickDone() and over
    end
  end
  local px, pz = bag.x * 16 + 8, bag.z * 16 + 8
  local speed, traveled, tiles = 1 / 60, 0, 0
  local phase, tire, wait = "windup", nil, 0
  -- the camera object (VeilstoneGym_InitCameraManager), for a long push
  local cam, camState, camTraveled, camDir = nil, 0, 0, dir
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local function camStepTicks(fast) return (fast and 4 or 8) * M.TICKS_PER_FRAME end
  -- VeilstoneGym_MoveCamera: a walk a tile at a time, `fast` the action
  local function moveCamera(fast)
    if not cam then return end
    if cam.walk then
      cam.walk.t = cam.walk.t + M.TICKS_PER_FRAME
      local k = math.min(1, cam.walk.t / cam.walk.n)
      cam.px = cam.walk.fx + (cam.walk.tx - cam.walk.fx) * k
      cam.py = cam.walk.fy + (cam.walk.ty - cam.walk.fy) * k
      if cam.walk.t >= cam.walk.n then
        cam.cellX, cam.cellY = cam.walk.cx, cam.walk.cy
        cam.px, cam.py = cam.cellX * 16, cam.cellY * 16
        cam.walk = nil
      end
      return
    end
    if camState ~= 1 then return end
    if camTraveled >= dist then camState = 2 return end
    local v = DIRS[camDir]
    cam.walk = { t = 0, n = camStepTicks(fast), fx = cam.px, fy = cam.py,
                 tx = (cam.cellX + v[1]) * 16, ty = (cam.cellY + v[2]) * 16,
                 cx = cam.cellX + v[1], cy = cam.cellY + v[2] }
    camTraveled = camTraveled + 1
  end
  local function camFinished()
    return camState == 2 and not (cam and cam.walk)
  end
  -- VeilstoneGym_UpdateCamera(speed): a walk once the bag moves a unit a frame
  local function updateCamera(spd)
    if not cam then return end
    local c = math.floor(spd)
    if c >= 1 or cam.walk then moveCamera(c > 2) end
  end
  if dist > M.CAMERA_AFTER[dir] then
    local p = ow.player
    cam = { cellX = p.cellX, cellY = p.cellY, px = p.cellX * 16, py = p.cellY * 16, hidden = true, veilstoneCamera = true }
    ow.gen4Camera = cam
    camState = 1
  end
  local function freeCamera()
    if cam and ow.gen4Camera == cam then ow.gen4Camera = nil end
    cam = nil
  end
  return function()
    tick = tick + 1
    if tick % M.TICKS_PER_FRAME ~= 0 then return false end
    frame = frame + 1
    swingStep()
    if phase == "windup" then
      px, pz = px + d[1] * speed, pz + d[2] * speed
      speed = speed + 1 / 60
      traveled = traveled + speed
      if frame >= 30 then
        phase = "move" se("SEQ_SE_PL_GYM01")
        -- VeilstoneGymObjectRenderer_UpdateBagFrameDelta(13 / (tiles * 8))
        swing.delta = 13 / (dist * 16 / 2)
      end
    elseif phase == "move" then
      px, pz = px + d[1] * speed, pz + d[2] * speed
      traveled = traveled + speed
      if frame < 36 then
        if speed < 1 then speed = speed + speed end
      elseif frame == 36 and speed <= 2 then
        speed = 2
      end
      updateCamera(speed)
      if math.floor(traveled / 16) > tiles then
        tiles = math.floor(traveled / 16)
        bag.x, bag.z = bag.x + d[1], bag.z + d[2]
        local flags = M.tileFlags(b, bag.x, bag.z, dir)
        if flags ~= 0 then
          px, pz = bag.x * 16 + 8, bag.z * 16 + 8
          swing.delta = 1
          pcall(function() require("src.core.Sound").stopSe(G.data, "SEQ_SE_PL_GYM01") end)
          se("SEQ_SE_PL_SUTYA2") se("SEQ_SE_PL_GYM02")
          if math.floor(flags / M.TIRE) % 2 == 1 then
            tire = tireAt(b, bag.x + d[1], bag.z + d[2])
            phase, wait = "topple", 0
          else
            phase = cam and "camprep" or "finish"
          end
        end
      end
    elseif phase == "topple" then
      -- VeilstoneGym_AnimationState_ToppleTireStack / _RemoveTireStack
      updateCamera(speed)
      wait = wait + 1
      if wait == 4 then
        tire.toppling = true
        live[tire] = { frame = 0 }
        se("SEQ_SE_DP_UG_026")
      elseif wait > 4 then
        local l = live[tire]
        l.frame = l.frame + 1
        -- TireStackAnim_Update: all four ended (45 frames each)
        local n = 0
        for _, m in ipairs(M.TIRE_ANIMS) do n = math.max(n, GymFx.frames(m)) end
        if l.frame >= n then
          tire.toppling, tire.exists = nil, false
          live[tire] = nil
          phase = cam and "camprep" or "finish"
        end
      end
    elseif phase == "camprep" then
      -- PrepCameraReturnToPlayer: the camera's walk and the swing over
      updateCamera(speed)
      if camFinished() and swing.done then
        camDir, camState, camTraveled = OPPOSITE[dir], 1, 0
        phase = "camback"
      end
    elseif phase == "camback" then
      -- MoveCameraToPlayer, WALK_FAST
      moveCamera(true)
      if camFinished() then freeCamera() phase = "done" end
    elseif phase == "finish" then
      -- FinishBagAnimation: the swing over
      if swing.done then phase = "done" end
    end
    bag.px, bag.pz = px, pz
    if phase == "done" then bag.px, bag.pz = nil, nil live[bag] = nil end
    M.draw(def, b, ow.map)
    -- VeilstoneGym_AnimationState_WaitForAnimationFinished: the kick too
    return phase == "done" and kickDone()
  end
end

return M
