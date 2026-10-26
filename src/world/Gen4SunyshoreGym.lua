-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SUNYSHORE GYM'S GEARS (pokeplatinum src/overlay008/gym_features.c,
-- SunyshoreGym_*; res/field/scripts/scripts_sunyshore_city_gym_room_*.s).
--
-- The port kept the slot (src/world/Gen4DynamicMapFeatures.lua: the room, the
-- rotation each room starts at, the entrance-z override) and the planner
-- walked over the gear gaps to Volkner. READ FROM CODE:
--
--   * SunyshoreGym_DynamicMapFeaturesInit: the room's gears (3, 6 and 13,
--     sSunyshoreRoom{1,2,3}Gears) loaded by hand at (x*16+8, y*16, z*16+8),
--     an upright gear 8 higher, each turned 90 degrees x initialRotation and
--     then +-90 x the slot's rotationState (minus for turnsClockwise), about
--     y -- or about x for an upright one (SunyshoreGym_SetGearRotation).
--   * SunyshoreGym_DynamicMapFeaturesCheckCollision: the room's collision
--     REGIONS (12 / 18 / 40 rectangles) of which the rotation state's list
--     (sSunyshoreCollisionLists: 6 / 11 / 14 of them -- room 2's lists 1 and 3
--     are padded with repeats, kept as they are) are walls. A tile in one is
--     a collision; outside them the map's own collision answers (the
--     function returns FALSE and TerrainCollisionManager asks the tile).
--   * SunyshoreGym_PressButton, from the coord events on the gear hubs
--     (PressSunyshoreGymButton NORMAL 0 / REVERSE 1 / DOUBLE 2): the state
--     moves +1, -1 or +2 (mod 4) AT ONCE -- the collision follows the press,
--     not the picture -- SEQ_SE_DP_GAGAGA plays and the gears turn
--     F32_DEG_TO_IDX(5.625) (0x400) a field frame, 16 frames for a quarter
--     turn and 32 for a half (FieldTask_SunyshoreGym_RotateGears, a
--     FieldTask_InitCall the script waits on).
--
-- STAND-INS: none for the mechanics. The gears are drawn as runtime props
-- through Gen4Ground (`def.gen4RuntimeProps`, rotY / rotX); their own
-- texture animations, if any, run on the prop clock.

local M = {}

M.MAPS = { C08GYM0101 = 0, C08GYM0102 = 1, C08GYM0103 = 2 }
M.TICKS_PER_FRAME = 2
M.STEP = 0x400                -- F32_DEG_TO_IDX(5.625)
M.QUARTER = 0x4000            -- F32_DEG_TO_IDX(90)
M.SE = "SEQ_SE_DP_GAGAGA"
M.BUTTON_NORMAL, M.BUTTON_REVERSE, M.BUTTON_DOUBLE = 0, 1, 2

-- build_model members (sunyshore_gear_*.nsbmd)
local L, LA, T, TA, DEAD, V, VA = 459, 460, 461, 462, 458, 463, 464

-- { model, x, y, z, initialRotation, turnsClockwise, isVertical }
M.GEARS = {
  [0] = {
    { L, 3, 0, 8, 1, false, false }, { LA, 8, 0, 8, 2, true, false }, { L, 13, 0, 8, 0, false, false },
  },
  [1] = {
    { L, 6, 0, 8, 1, false, false }, { DEAD, 11, 0, 8, 3, true, false }, { V, 15, 3, 8, 1, true, true },
    { V, 2, 3, 13, 1, false, true }, { DEAD, 6, 0, 13, 2, true, false }, { T, 11, 0, 13, 2, false, false },
  },
  [2] = {
    { T, 6, 6, 8, 1, false, false }, { LA, 11, 6, 8, 0, true, false }, { TA, 16, 6, 8, 0, false, false },
    { V, 2, 3, 13, 0, true, true }, { LA, 6, 6, 13, 1, true, false }, { T, 11, 6, 13, 3, false, false },
    { TA, 16, 6, 13, 3, true, false }, { V, 20, 3, 13, 1, false, true }, { VA, 2, 3, 18, 0, false, true },
    { L, 6, 0, 18, 1, true, false }, { TA, 11, 0, 18, 3, false, false }, { T, 16, 0, 18, 0, true, false },
    { VA, 20, 3, 18, 1, true, true },
  },
}

-- sSunyshoreRoom{1,2,3}CollisionRegions: { x, z, sizeX, sizeZ }
M.REGIONS = {
  [0] = { { 1, 8, 2, 1 }, { 3, 6, 1, 2 }, { 4, 8, 2, 1 }, { 3, 9, 1, 2 }, { 6, 8, 2, 1 }, { 8, 6, 1, 2 },
          { 9, 8, 2, 1 }, { 8, 9, 1, 2 }, { 11, 8, 2, 1 }, { 13, 6, 1, 2 }, { 14, 8, 2, 1 }, { 13, 9, 1, 2 } },
  [1] = { { 4, 8, 2, 1 }, { 6, 6, 1, 2 }, { 7, 8, 2, 1 }, { 6, 9, 1, 2 }, { 9, 8, 2, 1 }, { 11, 6, 1, 2 },
          { 12, 8, 2, 1 }, { 11, 9, 1, 2 }, { 15, 6, 1, 5 }, { 2, 11, 1, 5 }, { 4, 13, 2, 1 }, { 6, 11, 1, 2 },
          { 7, 13, 2, 1 }, { 6, 14, 1, 2 }, { 9, 13, 2, 1 }, { 11, 11, 1, 2 }, { 12, 13, 2, 1 }, { 11, 14, 1, 2 } },
  [2] = { { 4, 8, 2, 1 }, { 6, 6, 1, 2 }, { 7, 8, 2, 1 }, { 6, 9, 1, 2 }, { 9, 8, 2, 1 }, { 11, 6, 1, 2 },
          { 12, 8, 2, 1 }, { 11, 9, 1, 2 }, { 14, 8, 2, 1 }, { 16, 6, 1, 2 }, { 17, 8, 2, 1 }, { 16, 9, 1, 2 },
          { 2, 11, 1, 5 }, { 4, 13, 2, 1 }, { 6, 11, 1, 2 }, { 7, 13, 2, 1 }, { 6, 14, 1, 2 }, { 9, 13, 2, 1 },
          { 11, 11, 1, 2 }, { 12, 13, 2, 1 }, { 11, 14, 1, 2 }, { 14, 13, 2, 1 }, { 16, 11, 1, 2 }, { 17, 13, 2, 1 },
          { 16, 14, 1, 2 }, { 20, 11, 1, 5 }, { 2, 16, 1, 5 }, { 4, 18, 2, 1 }, { 6, 16, 1, 2 }, { 7, 18, 2, 1 },
          { 6, 19, 1, 2 }, { 9, 18, 2, 1 }, { 11, 16, 1, 2 }, { 12, 18, 2, 1 }, { 11, 19, 1, 2 }, { 14, 18, 2, 1 },
          { 16, 16, 1, 2 }, { 17, 18, 2, 1 }, { 16, 19, 1, 2 }, { 20, 16, 1, 5 } },
}

-- sSunyshoreCollisionLists: the regions that are walls, by rotation state
-- (region indices, 0-based, exactly as the tables have them)
M.WALLS = {
  [0] = { [0] = { 1, 2, 4, 5, 10, 11 }, { 0, 1, 5, 6, 9, 10 }, { 0, 3, 6, 7, 8, 9 }, { 2, 3, 4, 7, 8, 11 } },
  [1] = { [0] = { 1, 2, 4, 5, 7, 8, 9, 10, 11, 12, 15 }, { 0, 1, 4, 5, 6, 11, 12, 13, 14, 0, 0 },
          { 0, 3, 5, 6, 7, 8, 9, 10, 12, 13, 17 }, { 2, 3, 4, 6, 7, 10, 11, 13, 16, 2, 2 } },
  [2] = { [0] = { 2, 6, 7, 11, 14, 15, 17, 21, 25, 28, 29, 31, 38, 39 },
          { 1, 4, 7, 10, 12, 15, 16, 20, 22, 26, 29, 30, 34, 35 },
          { 0, 4, 5, 9, 13, 16, 19, 23, 25, 27, 30, 33, 36, 39 },
          { 3, 5, 6, 8, 12, 13, 14, 18, 24, 26, 27, 28, 32, 37 } },
}

local function DMF() return require("src.world.Gen4DynamicMapFeatures") end
local function game() return package.loaded["src.core.Game"] end

function M.roomOf(def)
  if not def then return nil end
  return M.MAPS[def.id] or M.MAPS[def.sourceId or ""]
end

local function slot(save)
  return save and DMF().buffer(save, DMF().SUNYSHORE_GYM)
end

-- SunyshoreGym_DynamicMapFeaturesCheckCollision
function M.collides(room, state, x, z)
  local regions, walls = M.REGIONS[room], M.WALLS[room] and M.WALLS[room][state]
  if not (regions and walls) then return false end
  for _, i in ipairs(walls) do
    local r = regions[i + 1]
    if r[1] <= x and x < r[1] + r[3] and r[2] <= z and z < r[2] + r[4] then return true end
  end
  return false
end

-- SunyshoreGym_SetGearRotation, as a u16 angle index
function M.angle(gear, state)
  local a = M.QUARTER * gear[5]
  if gear[6] then a = a - M.QUARTER * state else a = a + M.QUARTER * state end
  return a % 0x10000
end

-- the gears as runtime props, each at its own angle index
local function draw(def, room, angles)
  local keep = {}
  for _, p in ipairs(type(def.gen4RuntimeProps) == "table" and def.gen4RuntimeProps or {}) do
    if not p.sunyshoreGear then keep[#keep + 1] = p end
  end
  for i, g in ipairs(M.GEARS[room] or {}) do
    local deg = (angles[i] % 0x10000) * 360 / 0x10000
    keep[#keep + 1] = { model = g[1], x = g[2] * 16 + 8, y = g[3] * 16 + (g[7] and 8 or 0), z = g[4] * 16 + 8,
                        rotY = (not g[7]) and deg or nil, rotX = g[7] and deg or nil, sunyshoreGear = true }
  end
  -- a fresh list each time, so Gen4Ground re-reads it
  def.gen4RuntimeProps = keep
end

local function hook(def)
  local prior = def.gen4SunyshorePriorHook
  return function(map, tx, ty, mover)
    local G = game()
    local b = G and slot(G.save)
    local room = M.roomOf(map.def)
    if b and room and tonumber(b.roomID) == room
       and M.collides(room, tonumber(b.rotationState) or 0, tx, ty) then
      return true
    end
    if prior then return prior(map, tx, ty, mover) end
    return nil
  end
end

-- SunyshoreGym_DynamicMapFeaturesInit, from the slot
function M.apply(ow, save)
  local def = ow and ow.map and ow.map.def
  local room = M.roomOf(def)
  local b = slot(save)
  if not (room and b) or tonumber(b.roomID) ~= room then return nil end
  local state = tonumber(b.rotationState) or 0
  local angles = {}
  for i, g in ipairs(M.GEARS[room]) do angles[i] = M.angle(g, state) end
  def.gen4SunyshoreAngles = angles
  if not def.gen4SunyshoreHooked then
    def.gen4SunyshorePriorHook = def.gen4CollisionHook
    def.gen4CollisionHook = hook(def)
    def.gen4SunyshoreHooked = true
  end
  draw(def, room, angles)
  return state
end

-- SunyshoreGym_PressButton: the state moves now; answers a step function the
-- script runner polls (true once the gears have turned), or nil
function M.press(ow, save, buttonType)
  local def = ow and ow.map and ow.map.def
  local room = M.roomOf(def)
  local b = slot(save)
  if not (room and b) then return nil end
  buttonType = math.floor(tonumber(buttonType) or 0)
  local state = tonumber(b.rotationState) or 0
  local goal
  if buttonType == M.BUTTON_NORMAL then
    goal, state = M.QUARTER, (state + 1) % 4
  elseif buttonType == M.BUTTON_REVERSE then
    goal, state = M.QUARTER, state - 1
    if state < 0 then state = 3 end
  elseif buttonType == M.BUTTON_DOUBLE then
    goal, state = 2 * M.QUARTER, (state + 2) % 4
  else
    return nil
  end
  b.rotationState = state
  b.pressedButton = buttonType
  local angles = def.gen4SunyshoreAngles
  if not angles then M.apply(ow, save) return nil end
  local G = game()
  pcall(function() require("src.core.Sound").playSe(G.data, M.SE) end)
  local progress, tick = 0, 0
  return function()
    tick = tick + 1
    if tick % M.TICKS_PER_FRAME ~= 0 then return false end
    -- FieldTask_SunyshoreGym_RotateGears: 0x400 a frame (the remainder arm
    -- never runs: 0x400 divides both goals)
    local step = M.STEP
    if progress + step > goal then step = progress + step - goal end
    progress = progress + step
    if buttonType == M.BUTTON_REVERSE then step = -step end
    for i, g in ipairs(M.GEARS[room]) do
      angles[i] = (angles[i] + (g[6] and -step or step)) % 0x10000
    end
    draw(def, room, angles)
    return progress >= goal
  end
end

return M
