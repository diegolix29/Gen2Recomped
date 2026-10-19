-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S ROCK CLIMB: FieldTask_UseRockClimb (pokeplatinum
-- src/overlay005/ov5_021DFB54.c), started by the field-move script's
-- UseRockClimb (FieldTask_StartUseRockClimb). Its states:
--
--   PlayCutIn / WaitCutIn   the HM cut-in (NewMonRideCutIn -> HMCutIn_StartTask,
--                           src/world/Gen4HMCutIn.lua)
--   CreateMount             the `rock_ride` model (fldeff member 82,
--                           ov5_021F28F4) on the facing tile at that tile's
--                           height, turned with the facing (0 south, 180 north,
--                           270 west, 90 east); the debris task
--                           (ov6_0224892C); SEQ_SE_DP_UG_023
--   HopOn / WaitHop         MOVEMENT_ACTION_JUMP_NEAR_FAST: one tile, 2 units a
--                           frame for 8 frames, sJumpHeights_High stepped by
--                           0x200, SEQ_SE_DP_DANSA at the take-off and
--                           SEQ_SE_PL_SUTYA2 at the landing; then the mount
--                           follows the player (ov5_021F2974(.., 1))
--   Move / LoopOrHopOff     MOVEMENT_ACTION_WALK_FAST (4 units a frame, 4
--                           frames a tile) while the tile ahead is a rock-climb
--                           tile for the direction (PlayerAvatar_CanUseRockClimb:
--                           0x4B north / south, 0x4C east / west); then
--                           JUMP_NEAR_FAST off, the mount left where it is and
--                           the debris task ended (every piece goes with it)
--   WaitFinished            the mount is deleted when the hop lands
--
-- THE DEBRIS (ov6_022487F8 .. ov6_02248914): hiden_effect model 8 with its four
-- Rock Smash animations, sixteen instances. One is placed every fifth field
-- frame (the countdown starts at 0, so the first goes at once), at the
-- player's position raised 32 units and 16 toward the camera -- or 32 toward
-- the camera and not raised, when the player has moved straight south and
-- down since the last one (ov6_02248728) -- plays its animations once with
-- SEQ_SE_DP_UG_023, and hides. Drawn here as Gen4FieldFx entries of the
-- `rockSmash` part (gen4_pt_field_fx).

local M = {}

M.MODEL = 82
M.SE_MOUNT = "SEQ_SE_DP_UG_023"
M.SE_JUMP, M.SE_LAND = "SEQ_SE_DP_DANSA", "SEQ_SE_PL_SUTYA2"
M.DEBRIS_EVERY = 5            -- field frames
M.TICKS_PER_FRAME = 2
M.HOP_TICKS = 16              -- 8 field frames
M.FAST_RATE = 0.5             -- WALK_FAST: half the 8-frame step
M.ANGLE = { down = 0, up = 180, left = 270, right = 90 }

local function Game() return package.loaded["src.core.Game"] end

local function playSe(key)
  local G = Game()
  pcall(function() require("src.core.Sound").playSe(G.data, key) end)
end

local function groundOf(ow)
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
end

-- Platinum only: HGSS's own task is not this one
function M.platinum()
  local G = Game()
  local data = G and G.data
  if not (data and data.isGen4Cache) then return false end
  local okV, GV = pcall(require, "src.core.GameVersion")
  if okV and GV.isGen5 and GV.isGen5() then return false end
  local v = data.gen4_version
  return not (v and v.family == "hgss")
end

function M.climbable(behaviour, dir)
  if dir == "up" or dir == "down" then return behaviour == 0x4B end
  return behaviour == 0x4C
end

local function delta(dir)
  if dir == "up" then return 0, -1 elseif dir == "down" then return 0, 1
  elseif dir == "left" then return -1, 0 end
  return 1, 0
end

local function aheadClimbable(ow, x, y, dir)
  local map = ow.map
  local dx, dy = delta(dir)
  local nx, ny = x + dx, y + dy
  if not (map and map.inBounds and map:inBounds(nx, ny) and map.cellBehaviour) then return false end
  return M.climbable(map:cellBehaviour(nx, ny), dir)
end

-- the debris piece's place (ov6_02248728), from the player's position now
local function debrisAt(ow, r)
  local p = ow.player
  local ground = groundOf(ow)
  local x, z = (p.px or 0) + 8, (p.py or 0) + 8
  local y = ground and ground:groundY(x, z) or 0
  local last = r.lastPos
  local dy, dz = 32, 16
  if last and x == last[1] and y < last[2] and z > last[3] then dy, dz = 0, 32 end
  r.lastPos = { x, y, z }
  return x, z + dz, y + dy
end

local function spawnDebris(ow, r)
  local FX = require("src.world.Gen4FieldFx")
  local x, z, y = debrisAt(ow, r)
  FX.spawn(ow, "rockSmash", x, z, y, M.SE_MOUNT, "rockClimb")
end

-- every engine tick, from Gen4FieldFx.tick (the debris keeps that running)
function M.tick(ow)
  local r = ow and ow.gen4RockClimb
  if not (r and r.debris) then return end
  r.tick = (r.tick or 0) + 1
  if r.tick % M.TICKS_PER_FRAME ~= 0 then return end
  r.countdown = r.countdown - 1
  if r.countdown < 0 then
    r.countdown = M.DEBRIS_EVERY - 1
    spawnDebris(ow, r)
  end
end

local function hop(ow, r, dir, onLand)
  local p = ow.player
  playSe(M.SE_JUMP)
  p.hopFrames, p.hopTotal = M.HOP_TICKS, M.HOP_TICKS
  ow:scriptMove(p, dir, 1, function()
    playSe(M.SE_LAND)
    onLand()
  end)
end

local function finish(ow, r)
  ow.gen4RockClimb = nil
  if r.onDone then pcall(r.onDone) end
end

-- the ride proper: from CreateMount on
local function ride(ow, r)
  local p = ow.player
  local dir = r.dir
  local dx, dy = delta(dir)
  local ground = groundOf(ow)
  -- CreateMount: on the facing tile, at its height
  local mx, mz = (p.cellX + dx) * 16 + 8, (p.cellY + dy) * 16 + 8
  r.mount = { x = mx, z = mz, y = ground and ground:groundY(mx, mz) or 0, sync = false, facing = dir }
  r.debris, r.countdown, r.tick = true, 0, 0
  playSe(M.SE_MOUNT)
  -- the debris task's first frame
  r.countdown = M.DEBRIS_EVERY - 1
  spawnDebris(ow, r)
  local function hopOff()
    r.mount.sync = false
    local pxNow, pzNow = (p.px or 0) + 8, (p.py or 0) + 8
    r.mount.x, r.mount.z = pxNow, pzNow
    r.mount.y = ground and ground:groundY(pxNow, pzNow) or r.mount.y
    -- ov6_02248940: the debris effect is deleted, every piece with it
    r.debris = false
    require("src.world.Gen4FieldFx").clear(ow, "rockClimb")
    hop(ow, r, dir, function()
      r.mount = nil
      finish(ow, r)
    end)
  end
  local function move()
    if aheadClimbable(ow, p.cellX, p.cellY, dir) then
      ow:scriptMove(p, dir, 1, move, nil, M.FAST_RATE)
    else
      hopOff()
    end
  end
  hop(ow, r, dir, function()
    r.mount.sync = true
    move()
  end)
end

-- UseRockClimb: true when the ride started (the tile ahead is climbable)
function M.start(ow, dir, mon, onDone)
  local p = ow and ow.player
  if not (p and ow.map and ow.scriptMove) or ow.gen4RockClimb then return false end
  dir = dir or p.facing
  if not aheadClimbable(ow, p.cellX, p.cellY, dir) then return false end
  local r = { dir = dir, onDone = onDone }
  ow.gen4RockClimb = r
  p.facing = dir
  local G = Game()
  local shown = false
  if mon and G then
    local okC, c = pcall(require("src.world.Gen4HMCutIn").show, G, mon, function() ride(ow, r) end)
    shown = okC and c
  end
  if not shown then ride(ow, r) end
  return true
end

-- the mount's place now: synced to the player's position (not its hop)
local function mountPlace(ow, m)
  if not m.sync then return m.x, m.z, m.y end
  local p = ow.player
  local ground = groundOf(ow)
  local x, z = (p.px or 0) + 8, (p.py or 0) + 8
  return x, z, ground and ground:groundY(x, z) or m.y
end

local function rotY(deg)
  local rad = math.rad(deg)
  local c, s = math.cos(rad), math.sin(rad)
  return { c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1 }
end

local function current()
  local G = Game()
  local ow = G and G.overworld
  local r = ow and ow.gen4RockClimb
  return r and r.mount and ow, r
end

function M.drawLive(ground, left, top, vw, vh)
  local ow, r = current()
  if not ow then return end
  local mdl = ground:building(M.MODEL, "fldeff")
  if not mdl then return end
  local Gen4Model = require("src.render.Gen4Model")
  local Gen4Ground = require("src.render.Gen4Ground")
  local x, z, y = mountPlace(ow, r.mount)
  local half = ground.half or 0
  local base = ground:screenMatrix(x + (ground.offsetX or 0) - left - half,
                                   z + (ground.offsetY or 0) - top - half, vw, vh)
  local m = Gen4Ground.liftMatrix(base, y)
  local spread = Gen4Ground.liftedSpread and Gen4Ground.liftedSpread(ground.spread, y) or ground.spread
  mdl:draw(Gen4Model.multiply(m, rotY(M.ANGLE[r.mount.facing] or 0)), nil, nil, nil, spread)
end

function M.drawFree(ground, vp)
  local ow, r = current()
  if not ow then return end
  local mdl = ground:building(M.MODEL, "fldeff")
  if not mdl then return end
  local Gen4Model = require("src.render.Gen4Model")
  local x, z, y = mountPlace(ow, r.mount)
  local m = Gen4Model.multiply(vp, { 1, 0, 0, x + (ground.offsetX or 0),
                                     0, 1, 0, y,
                                     0, 0, 1, z + (ground.offsetY or 0),
                                     0, 0, 0, 1 })
  mdl:draw(Gen4Model.multiply(m, rotY(M.ANGLE[r.mount.facing] or 0)))
end

return M
