-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CANALAVE GYM'S PLATFORMS AND LIFTS (pokeplatinum src/overlay008/
-- gym_features.c, CanalaveGym_*; src/overlay005/field_control.c,
-- Field_ProcessStep).
--
-- The port kept the slot's bitfield (src/world/Gen4DynamicMapFeatures.lua)
-- and the planner walked to Byron across the gaps. READ FROM CODE:
--
--   * four floors, 10 tiles (160 units) apart. The ground floor is the map;
--     floors 2-4 are props loaded by hand at (256, 160 / 320 / 480, 256)
--     (canalave_gym_second/third/fourth_floor), and the room's BDHC has a
--     plate at each of the four heights on every tile.
--   * CanalaveGym_DynamicMapFeaturesCheckCollision: the floor is
--     height / 16 / 10, and sCanalaveGymCollisionMaps[floor] decides EVERY
--     tile -- the function always answers, the map's own collision is never
--     asked.
--   * 24 platforms (sCanalavePlatformPaths): a model, a position A and B,
--     the floor at each, and the slot bit saying which one it is at
--     (PersistedMapFeatures_InitForCanalaveGym: 6, 7, 8, 10, 11, 16, 18, 19,
--     21, 23 start at B). Each is loaded at (x*16+8, y*16, z*16+8).
--   * Field_ProcessStep -> CanalaveGym_CheckIfPlayerOnPlatform: a step that
--     ENDS on a platform's tile at its height moves that platform (before the
--     coord events, which it then skips): the bit flips and
--       - x_direction: the player is walked WALK_FASTER (2 field frames a
--         tile) east to B or west to A, the platform under them;
--       - z_direction: the same, south to B or north to A;
--       - y_direction and the two red ones: a lift, 8 units a field frame up
--         to B or down to A, the player's height with it, SEQ_SE_DP_ELEBETA
--         then SEQ_SE_DP_KI_GASYAN.
--   * CanalaveGym_UpdateVisibleProps, at entry and each lift frame: floor 2
--     is drawn once the lift's (or the player's) height is >= 16, floor 3 at
--     >= 176, floor 4 at >= 336; a platform standing on a hidden floor is
--     hidden with it.
--
-- HOW THE HEIGHTS ARE DRAWN: the ground answers a tile's TOP plate for a
-- character's feet, and here that is the fourth floor's on every tile; so
-- the player and the trainers carry a sprite offset (`spriteOffset.lift`,
-- marked `gen4Stand`) down to the floor they are on, and the camera follows
-- it (OverworldState:followCamera).
--
-- THE FOG AND THE CLIPPING, the end of CanalaveGym_DynamicMapFeaturesInit:
-- Camera_SetClipping(100, 1700) -- the lower floors stay in view from the
-- top one -- and the hardware fog, COLOR_ALPHA, slope 0x200, offset 0x76A0,
-- black at alpha 0, density table 2 * i: the further a floor lies below the
-- camera the darker it is drawn, characters included (src/render/
-- Gen4DepthFog.lua through `def.gen4DepthFog`; the characters by
-- src/world/Gen4GymFx.lua spriteFog). The port draws nothing at a far plane,
-- so the clipping is the fog's own depth arithmetic here.
--
-- A SLIDE PAUSES THE PLAYER'S WALK (FieldTask_CanalaveGym_MovePlatformEast-
-- West / NorthSouth): MOVEMENT_ACTION_PAUSE_ANIMATION before the first
-- WALK_FASTER and RESUME_ANIMATION after the last, so the player glides on
-- the platform on the frame they stepped on with.

local M = {}

M.MAP = "C02GYM0101"
M.TICKS_PER_FRAME = 2
M.FLOOR_UNITS = 160
M.LIFT_SPEED = 8                      -- units a field frame
M.SLIDE_RATE = 0.25                   -- WALK_FASTER: 2 field frames of 8
M.FLOOR_MODELS = { 300, 301, 302 }    -- canalave_gym_second/third/fourth_floor
M.X_MODEL, M.Y_MODEL, M.Z_MODEL, M.RED_MODEL = 295, 296, 294, 297

local X, Y, Z, R = 295, 296, 294, 297
-- sCanalavePlatformPaths: { model, {A x,y,z}, {B x,y,z}, floorA, floorB }
M.PATHS = {
  { R, { 16, 0, 9 }, { 16, 30, 9 }, 0, 3 },
  { Y, { 11, 0, 13 }, { 11, 10, 13 }, 0, 1 },
  { Y, { 15, 0, 13 }, { 15, 10, 13 }, 0, 1 },
  { Y, { 19, 0, 13 }, { 19, 10, 13 }, 0, 1 },
  { Y, { 24, 0, 13 }, { 24, 10, 13 }, 0, 1 },
  { Y, { 21, 0, 22 }, { 21, 10, 22 }, 0, 1 },
  { Y, { 25, 0, 9 }, { 25, 10, 9 }, 0, 1 },
  { Y, { 25, 0, 22 }, { 25, 10, 22 }, 0, 1 },
  { Y, { 29, 0, 22 }, { 29, 10, 22 }, 0, 1 },
  { Y, { 5, 10, 26 }, { 5, 20, 26 }, 1, 2 },
  { X, { 11, 10, 22 }, { 18, 10, 22 }, 1, 1 },
  { Y, { 29, 10, 9 }, { 29, 20, 9 }, 1, 2 },
  { X, { 10, 20, 4 }, { 14, 20, 4 }, 2, 2 },
  { X, { 19, 20, 4 }, { 22, 20, 4 }, 2, 2 },
  { X, { 7, 20, 12 }, { 22, 20, 12 }, 2, 2 },
  { X, { 9, 20, 26 }, { 21, 20, 26 }, 2, 2 },
  { Z, { 2, 20, 19 }, { 2, 20, 22 }, 2, 2 },
  { Z, { 26, 20, 16 }, { 26, 20, 22 }, 2, 2 },
  { Z, { 29, 20, 16 }, { 29, 20, 22 }, 2, 2 },
  { R, { 7, 0, 9 }, { 7, 30, 9 }, 0, 3 },
  { X, { 19, 30, 4 }, { 26, 30, 4 }, 3, 3 },
  { X, { 5, 30, 26 }, { 26, 30, 26 }, 3, 3 },
  { Z, { 29, 30, 7 }, { 29, 30, 23 }, 3, 3 },
  { Z, { 2, 30, 12 }, { 2, 30, 23 }, 3, 3 },
}

-- sCanalaveGymCollisionMaps, by floor, row by row (1 = wall)
local MAPS = {
  [0] = {
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
    "11111100010000000000000000011111", "11111100010000000000000000011111", "11111100010000000000000000011111", "11111100011111111111111111111111",
    "11111100000000000100000000011111", "11111100000000000100000000011111", "11111100000000000100000000011111", "11111100000000000100000000011111",
    "11111100000000000000000000011111", "11111100000000000000000000011111", "11111100011111111111000000011111", "11111100000000000001000000011111",
    "11111100000000000001111100011111", "11111100000000000001000100010001", "11111100000000000001000100010001", "11111100000000000001000100010001",
    "11111100000000000001000111110001", "11111100000000100011000000000001", "11111100000000000001000000000001", "11111100000000000001000000000001",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
  },
  [1] = {
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111100010000000000001000000001",
    "11111100010000000000001000000001", "11111100010000000000001000000001", "11111100010001111111001011110001", "11111100010001000001001000010001",
    "11111111110001011101001000010001", "11111111110001011101001000010001", "11111111110001011101001000010001", "11111100010001111111111111111111",
    "11111111110001000100001000000001", "11111111110001000100001000000001", "11111111110001000100001000000001", "11111111111111111111001000000001",
    "11111111111111111111001111111001", "11111111111111111111000000010001", "11111111111111111111000000010001", "11111111111111111111000000010001",
    "10000000001111111111111100010001", "10000000001111111111000100010001", "10011111000011111100000100010001", "10000001001111111111000100010001",
    "10000001001111111111111111111111", "10000001001111111111111111111111", "10000001001111111111111111111111", "10000001001111111111111111111111",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
  },
  [2] = {
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "10010000011111110011111100000001",
    "10010000000111000000110000000001", "10010000011111110011111100000001", "10010000011111000000111100000001", "10010011111111000000111111011111",
    "10010011111111011100111101010001", "10010011111111011100111101010001", "10010011111111011100111101010001", "11110011111111111111111101010001",
    "10000000111111111111110001010001", "10000011111111111111111101010001", "10000011111111111111111101010001", "10000011111111111111111111011011",
    "10000011111111111111111111011011", "10000011111111111111111111111111", "11011111111111111111111111111111", "11011111111111111111111111111111",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11011111111111111111111111011011", "11011111111111111111111111011011",
    "10000000111111111111111010000001", "10000000111111111111111010000001", "10000000001111111111100010000001", "10000000111111111111111010000001",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
  },
  [3] = {
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111110111111111110001",
    "11111111111111100000111111000001", "11111111111111100011111111110001", "11111111111111000001111111111011", "11111111111111000001111111111011",
    "10000000011111000001111111111111", "10000000011111000001111111111111", "10000000011111000001111111111111", "11011111111111111111111111111111",
    "11011111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11011111111111111111111111111011",
    "11011111111111111111111111111011", "10001111111111111111111111110001", "10000011111111111111111111000001", "10001111111111111111111111110001",
    "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111", "11111111111111111111111111111111",
  },
}

function M.isGym(def)
  return def ~= nil and (def.id == M.MAP or def.sourceId == M.MAP)
end

-- the gym's fog (FogManager_ApplyParameters(.., GX_FOGSLOPE_0x0200, 0x76a0),
-- COLOR_BLACK, the table 2 * i) and its camera's clipping
M.FOG = { slope = 1, offset = 0x76A0, rgb = { 0, 0, 0 }, step = 2, near = 100, far = 1700 }

local function DMF() return require("src.world.Gen4DynamicMapFeatures") end
local function game() return package.loaded["src.core.Game"] end

local function slot(save)
  return save and DMF().buffer(save, DMF().CANALAVE_GYM)
end

local function inB(states, i)
  return math.floor((tonumber(states) or 0) / 2 ^ i) % 2 == 1
end
M.inB = inB

-- CanalaveGym_DynamicMapFeaturesCheckCollision
function M.collides(height, x, z)
  local floor = math.floor((tonumber(height) or 0) / 16 / 10)
  if floor < 0 then floor = 0 end
  if floor > 3 then floor = 3 end
  if x < 0 or z < 0 or x > 31 or z > 31 then return true end
  local row = MAPS[floor][z + 1]
  return row:sub(x + 1, x + 1) == "1"
end

-- the height a body stands at here: a lift rider's, the tracked one, a
-- trainer's own (its event y), else the ground floor
local function heightOf(mover, map)
  if not mover then return 0 end
  if mover.gen4CanalaveY then return mover.gen4CanalaveY end
  if mover.gen4Height and (map == nil or mover.gen4HeightMap == map) then return mover.gen4Height end
  local d = mover.def
  -- (the event's y in world units, which the importer keeps as `elevation`)
  return d and tonumber(d.height or d.elevation) or 0
end
M.heightOf = heightOf

local function topAt(map, x, z)
  local HR = require("src.world.Gen4HeightRule")
  local list = HR.surfaces(map, x, z) or {}
  local top
  for _, h in ipairs(list) do if not top or h > top then top = h end end
  return top or 0
end

-- the sprite offset that puts a body on its own floor
local function stand(map, e, y)
  if not (e and e.cellX) then return end
  if e.spriteOffset and not e.spriteOffset.gen4Stand then return end
  e.spriteOffset = { lift = y - topAt(map, e.cellX, e.cellY), gen4Stand = true }
end

local function system(b)
  local sys = { pos = {}, floor = {}, px = {} }
  for i, p in ipairs(M.PATHS) do
    local atB = inB(b.platformStates, i - 1)
    local at = atB and p[3] or p[2]
    sys.pos[i] = { at[1], at[2], at[3] }
    sys.floor[i] = atB and p[5] or p[4]
  end
  return sys
end

-- CanalaveGym_UpdateVisibleProps
local function setVisible(sys, y)
  sys.shown = { y >= 16, y >= 16 * 11, y >= 16 * 21 }
end

local function draw(def, sys)
  local keep = {}
  for _, p in ipairs(type(def.gen4RuntimeProps) == "table" and def.gen4RuntimeProps or {}) do
    if not p.canalave then keep[#keep + 1] = p end
  end
  for f = 1, 3 do
    if sys.shown[f] then
      keep[#keep + 1] = { model = M.FLOOR_MODELS[f], x = 256, y = f * M.FLOOR_UNITS, z = 256, canalave = true }
    end
  end
  for i, p in ipairs(M.PATHS) do
    local f = sys.floor[i]
    if f == 0 or sys.shown[f] then
      local live = sys.px[i]
      local at = sys.pos[i]
      keep[#keep + 1] = { model = p[1], canalave = true,
                          x = live and live.x or at[1] * 16 + 8,
                          y = live and live.y or at[2] * 16,
                          z = live and live.z or at[3] * 16 + 8 }
    end
  end
  -- a fresh list each time, so Gen4Ground re-reads it
  def.gen4RuntimeProps = keep
end

local function hook(def)
  local prior = def.gen4CanalavePriorHook
  return function(map, tx, ty, mover)
    local G = game()
    if G and slot(G.save) then
      return M.collides(heightOf(mover or (G.overworld and G.overworld.player), map), tx, ty)
    end
    if prior then return prior(map, tx, ty, mover) end
    return nil
  end
end

-- every body on its floor (the player at its tracked height)
function M.stand(ow)
  local def = ow and ow.map and ow.map.def
  if not M.isGym(def) then return end
  local p = ow.player
  if p then
    local y = p.gen4CanalaveY or (p.gen4HeightMap == ow.map and p.gen4Height) or 0
    stand(ow.map, p, y)
  end
  for _, n in ipairs(ow.npcs or {}) do
    local h = n.def and tonumber(n.def.height or n.def.elevation) or 0
    -- the height the object was created at, which the height rule then
    -- keeps (the nearest plate to it)
    if n.gen4HeightMap ~= ow.map then n.gen4Height, n.gen4HeightMap = h, ow.map end
    stand(ow.map, n, h)
  end
end

-- CanalaveGym_DynamicMapFeaturesInit
function M.apply(ow, save)
  local def = ow and ow.map and ow.map.def
  if not M.isGym(def) then return nil end
  local b = slot(save)
  if not b then return nil end
  if b.platformStates == nil then b.platformStates = DMF().canalavePlatformStates() end
  local sys = system(b)
  def.gen4Canalave = sys
  if not def.gen4CanalaveHooked then
    def.gen4CanalavePriorHook = def.gen4CollisionHook
    def.gen4CollisionHook = hook(def)
    def.gen4CanalaveHooked = true
  end
  local p = ow.player
  -- A CONTINUE brings the player's map object back at its saved height
  -- (PlayerAvatar_NewLoad); this port keeps no height on the save, so the
  -- slot carries it (`playerY`, written after each lift) -- a fresh entry's
  -- slot has none and the player stands at the door's floor
  if p and b.playerY and p.gen4HeightMap ~= ow.map then
    p.gen4Height, p.gen4HeightMap = b.playerY, ow.map
  end
  local y = (p and p.gen4HeightMap == ow.map and p.gen4Height) or 0
  b.playerY = y
  setVisible(sys, y)
  draw(def, sys)
  M.stand(ow)
  M.fog(def)
  return b.platformStates
end

-- the fog row, with the characters' depth: how far a body's feet are from
-- the camera, by the live pass's own arithmetic (src/render/Gen4Ground.lua
-- livePass: the eye distance at the camera's target, less what a point
-- stands above it and lies south of it along the camera's axis)
function M.fog(def)
  local row = {}
  for k, v in pairs(M.FOG) do row[k] = v end
  row.sprites = true
  row.depthOf = function(e, ow, ground)
    if not (ground and ow and ow.player) then return nil end
    local sinP = ground.groundScale or 1
    local cosP = ground.heightScale or 0
    local dist = (ground.camera and tonumber(ground.camera.distance)) or 667
    local target = ow.cameraTarget and ow:cameraTarget() or ow.player
    local ty = heightOf(target == ow.player and ow.player or target, ow.map)
    local tz = ground.cameraFeetZ or ((target.py or 0) + 8)
    local ey = heightOf(e, ow.map)
    local ez = (e.py or (e.cellY or 0) * 16) + 8
    return dist - sinP * (ey - ty) - cosP * (ez - tz)
  end
  def.gen4DepthFog = row
  return row
end

-- on every map load: the offsets set here are dropped anywhere else
function M.onMapEntered(G, ow)
  local def = ow and ow.map and ow.map.def
  local p = ow and ow.player
  if p then p.gen4CanalaveY = nil end
  if M.isGym(def) then return M.stand(ow) end
  if p and p.spriteOffset and p.spriteOffset.gen4Stand then p.spriteOffset = nil end
end

-- CanalaveGym_GetPlaformPlayerIsOn
function M.platformUnder(ow)
  local def = ow and ow.map and ow.map.def
  local sys = def and def.gen4Canalave
  local G = game()
  if not (M.isGym(def) and sys and G and slot(G.save)) then return nil end
  local p = ow.player
  local HR = require("src.world.Gen4HeightRule")
  local h = HR.standingY(ow.map, p) or 0
  local y = math.floor(h / 16 + 0.001)
  for i, at in ipairs(sys.pos) do
    if at[2] == y and at[1] == p.cellX and at[3] == p.cellY then return i end
  end
  return nil
end

-- CanalaveGym_MovePlatform: the bit flips now; answers a step function the
-- script runner polls (true when the ride is over), or nil
function M.ride(ow, save)
  local i = M.platformUnder(ow)
  if not i then return nil end
  local def = ow.map.def
  local sys = def.gen4Canalave
  local b = slot(save)
  local path = M.PATHS[i]
  local atB = inB(b.platformStates, i - 1)
  b.platformStates = atB and (b.platformStates - 2 ^ (i - 1)) or (b.platformStates + 2 ^ (i - 1))
  local dest = atB and path[2] or path[3]
  local p = ow.player
  local G = game()
  local function se(name) pcall(function() require("src.core.Sound").playSe(G.data, name) end) end
  local function stopSe(name) pcall(function() require("src.core.Sound").stopSe(G.data, name) end) end
  local model = path[1]
  if model == M.X_MODEL or model == M.Z_MODEL then
    -- FieldTask_CanalaveGym_MovePlatformEastWest / NorthSouth
    sys.pos[i] = { dest[1], dest[2], dest[3] }
    local dir, n
    if model == M.X_MODEL then
      dir, n = atB and "left" or "right", math.abs(dest[1] - p.cellX)
    else
      dir, n = atB and "up" or "down", math.abs(dest[3] - p.cellY)
    end
    se("SEQ_SE_DP_ELEBETA")
    local done = false
    local y = dest[2] * 16
    ow:scriptMove(p, dir, n, function() done = true end, false, M.SLIDE_RATE)
    local finished = false
    -- MOVEMENT_ACTION_PAUSE_ANIMATION: the walk cycle held where the step
    -- that ended here left it -- its standing frame, the stride's side kept
    local held = p.animClock and (p.animClock - p.animClock % 16) or nil
    return function()
      if not done then
        p.animClock = held
        -- MapProp_SetPosition: the platform under the player's feet
        sys.px[i] = { x = (p.px or p.cellX * 16) + 8, y = y, z = (p.py or p.cellY * 16) + 8 }
        draw(def, sys)
        return false
      end
      if not finished then
        finished = true
        sys.px[i] = nil
        draw(def, sys)
        stopSe("SEQ_SE_DP_ELEBETA")
        se("SEQ_SE_DP_KI_GASYAN")
      end
      return true
    end
  end
  -- FieldTask_CanalaveGym_MovePlatformUpDown
  local up = not atB
  local target = dest[2] * 16
  local y = sys.pos[i][2] * 16
  if not up then sys.floor[i] = path[4] end
  sys.pos[i] = { dest[1], dest[2], dest[3] }
  local tick, phase = 0, 0
  return function()
    tick = tick + 1
    if tick % M.TICKS_PER_FRAME ~= 0 then return false end
    if phase == 0 then
      -- PlayerAvatar_SetHeightCalculationEnabled(FALSE)
      se("SEQ_SE_DP_ELEBETA")
      phase = 1
      return false
    end
    if phase == 1 then
      if up then
        y = y + M.LIFT_SPEED
        if y >= target then y = target sys.floor[i] = path[5] stopSe("SEQ_SE_DP_ELEBETA") phase = 2 end
      else
        y = y - M.LIFT_SPEED
        if y <= target then y = target stopSe("SEQ_SE_DP_ELEBETA") phase = 2 end
      end
      -- Player_SetYPos, MapProp_SetPosition, CanalaveGym_UpdateVisibleProps
      p.gen4CanalaveY = y
      sys.px[i] = { x = dest[1] * 16 + 8, y = y, z = dest[3] * 16 + 8 }
      setVisible(sys, y)
      draw(def, sys)
      stand(ow.map, p, y)
      return false
    end
    if phase == 2 then
      -- PlayerAvatar_SetHeightCalculationEnabledAndUpdate(TRUE): the plate
      -- nearest the lift's height
      sys.px[i] = nil
      p.gen4CanalaveY = nil
      p.gen4Height, p.gen4HeightMap = y, ow.map
      require("src.world.Gen4HeightRule").standingY(ow.map, p)
      stand(ow.map, p, p.gen4Height or y)
      b.playerY = p.gen4Height or y
      draw(def, sys)
      se("SEQ_SE_DP_KI_GASYAN")
      phase = 3
      return false
    end
    return true
  end
end

return M
