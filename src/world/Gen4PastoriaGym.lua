-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PASTORIA GYM'S WATER FLOOR, RISEN AND LOWERED (pokeplatinum
-- src/overlay008/gym_features.c, PastoriaGym_*).
--
-- The port kept the state (src/world/Gen4DynamicMapFeatures.lua: the slot,
-- the pressed button, the three heights) and had switched the height rule
-- off in this room, so the player walked straight over the water to Wake.
-- This is the floor itself:
--
--   * PastoriaGym_DynamicMapFeaturesInit: the water-floor prop
--     (pastoria_gym_water_floor) loaded by hand at (256, y, 256), and
--     DynamicTerrainHeightManager_SetPlate(0, 1, 2, 25, 38, 0) -- tiles
--     (1,2) to (25,39) -- at the height the save's button gives: orange LOW
--     0, green MIDDLE 32, blue HIGH 64. Here `def.gen4DynamicPlate`, which
--     src/world/Gen4HeightRule.lua resolves the way GetHeight does, and
--     `def.gen4PastoriaGates`, its H/M/L gate tiles.
--   * PastoriaGym_Press{Orange,Green,Blue}Button: once the buttons'
--     animations are over, the water prop moves FX32_ONE a field frame
--     towards its height (green from either side), and only then is the
--     plate set (DynamicTerrainHeightManager_SetHeight) and SEQ_SE_DP_FW056
--     stopped -- the collision changes when the water has arrived. The
--     command is a FieldTask_InitCall on the script's task: the script waits.
--
--   * the buttons (pastoria_gym_blue/green/orange_button, build_model 239 /
--     240 / 241, each claiming one 15-frame BTP0, r04_b1..b3): at init
--     (PastoriaGym_DynamicMapFeaturesInit) each animation is set to play once,
--     paused, and sent to its last frame -- the pressed colour forwards (its
--     last frame is the button down), the other two reversed (their "last"
--     frame is frame 0, up). A press (PastoriaGym_UpdateButtonAnimations):
--     the pressed group plays forwards from frame 0 and the other two
--     reversed from their last frame, one frame a field frame, each stopping
--     on its last -- so a button already up still drops and rises again --
--     and the water waits until all three are over (MapPropAnimation_
--     IsLoopFinished). Played through Gen4PropControl (`def.gen4PropControl`).

local M = {}

M.MAP = "C06GYM0101"
M.WATER_MODEL = "pastoria_gym_water_floor.nsbmd"
M.WATER_X, M.WATER_Z = 256, 256
M.TICKS_PER_FRAME = 2       -- a field frame is two engine ticks
M.SE = "SEQ_SE_DP_FW056"

local function DMF() return require("src.world.Gen4DynamicMapFeatures") end
local function game() return package.loaded["src.core.Game"] end

local waterId
function M.waterModel()
  if waterId == nil then
    local ok, A = pcall(require, "src.import.Gen4Archives")
    waterId = ok and A and A.find and A.find("/fielddata/build_model/build_model.narc", M.WATER_MODEL) or false
  end
  return waterId or nil
end

function M.isGym(def)
  return def ~= nil and (def.id == M.MAP or def.sourceId == M.MAP)
end

-- the buttons by the save's value: { model, pressed value }
M.BUTTONS = { { model = 239, value = 2 }, { model = 240, value = 1 }, { model = 241, value = 0 } }
M.BUTTON_FALLBACK_ANIM = { [239] = 11, [240] = 12, [241] = 13 }

-- the animation each button's list names first (MapPropAnimationManager_
-- GetAnimation(model, 0)): the bm_anime record that claims the model
local function buttonAnim(model)
  local G = game()
  local field = G and G.data and G.data.gen4_models and G.data.gen4_models.sets
                and G.data.gen4_models.sets.field
  for _, r in ipairs((field and field.animations) or {}) do
    for _, owner in ipairs(r.props or {}) do
      if owner == model then return r.member, tonumber(r.frames) or 15 end
    end
  end
  return M.BUTTON_FALLBACK_ANIM[model], 15
end
M.buttonAnim = buttonAnim

-- the buttons' poses: `from` nil holds each on its last frame (the init);
-- a clock plays the press from that clock
local function buttonControls(def, pressed, from)
  local out = {}
  for _, b in ipairs(M.BUTTONS) do
    local member = buttonAnim(b.model)
    if member then
      local down = (b.value == pressed)
      local c
      if from then c = { from = from, once = true, reverse = not down or nil }
      else c = { hold = down and "last" or 0 } end
      out[b.model] = { [member] = c }
    end
  end
  -- a fresh table, so the ground re-reads it (Gen4PropControl.sync)
  def.gen4PropControl = out
end

-- the water prop at height `propY` (the runtime props are this gym's alone)
local function setProp(def, propY)
  local id = M.waterModel()
  local keep = {}
  for _, p in ipairs(type(def.gen4RuntimeProps) == "table" and def.gen4RuntimeProps or {}) do
    if not p.pastoriaWater then keep[#keep + 1] = p end
  end
  if id then
    keep[#keep + 1] = { model = id, x = M.WATER_X, z = M.WATER_Z, y = propY, pastoriaWater = true }
  end
  -- a fresh list each time, so Gen4Ground re-reads it
  def.gen4RuntimeProps = keep
end

-- the floor as the save's button has it: the prop, the plate, the gates
function M.apply(def, save)
  if not M.isGym(def) then return nil end
  local height = DMF().pastoriaWaterHeight(save)
  if not height then return nil end
  def.gen4DynamicPlate = { x = DMF().PASTORIA_PLATE_X, y = DMF().PASTORIA_PLATE_Z,
                           w = DMF().PASTORIA_PLATE_W, h = DMF().PASTORIA_PLATE_H, height = height }
  def.gen4PastoriaGates = DMF().PASTORIA_GATE_OPENS_AT
  setProp(def, height)
  local b = DMF().buffer(save, DMF().PASTORIA_GYM)
  buttonControls(def, b and b.pressedButton)
  return height
end

-- the button just pressed (the save already holds it): a step function the
-- script runner polls each tick, true once the water has arrived
function M.pressStep(def, save)
  local target = DMF().pastoriaWaterHeight(save)
  local plate = def and def.gen4DynamicPlate
  if not (target and plate) then return nil end
  local y = tonumber(plate.propY or plate.height) or 0
  local tick = 0
  pcall(function() require("src.core.Sound").playSe(game().data, M.SE) end)
  -- PastoriaGym_UpdateButtonAnimations, then state 1 waits for all three
  -- (the last frame of a 15-frame animation is 14 frames on)
  local b = DMF().buffer(save, DMF().PASTORIA_GYM)
  local G = game()
  local ow = G and G.overworld
  local ground = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  buttonControls(def, b and b.pressedButton, ground and ground.clock or 0)
  local _, frames = buttonAnim(M.BUTTONS[1].model)
  local wait = (math.max(1, frames or 15) - 1) * M.TICKS_PER_FRAME
  return function()
    tick = tick + 1
    if tick <= wait then return false end
    if y ~= target and tick % M.TICKS_PER_FRAME == 0 then
      y = y < target and math.min(target, y + 1) or math.max(target, y - 1)
      plate.propY = y
      setProp(def, y)
    end
    if y ~= target then return false end
    -- DynamicTerrainHeightManager_SetHeight: the collision follows now
    plate.height, plate.propY = target, nil
    pcall(function() require("src.core.Sound").stopSe(game().data, M.SE) end)
    return true
  end
end

return M
