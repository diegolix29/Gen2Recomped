-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S ICE: THE SLOPES AND THE SNOWBALLS (Snowpoint Gym).
--
-- The port slid a Gen 4 player the way it slides one in the Ice Path: one
-- step at a time in the facing direction until something is in the way. That
-- is the flat half of the rule. Snowpoint Gym is built on the other half --
-- icy ramps that can only be climbed with the speed a descent gives, and the
-- big snowballs that only that speed breaks -- and without it the gym was a
-- floor you walked up and down at will, with the snowballs as plain walls.
--
-- READ FROM CODE (pokeplatinum src/player_move.c):
--
--   PlayerAvatar_TileMove_Ice (the tile move for TILE_BEHAVIOR_ICE underfoot):
--     moveDir      the direction the player is moving
--     heightChange PlayerAvatar_CheckIceHeightChange: the height a quarter
--                  tile ahead ((16 << 12 >> 1) / 2 = 4 units) against the
--                  player's own -- NONE (no plate there, or the same y),
--                  DECREASE (downhill) or INCREASE (uphill)
--     collision    PlayerAvatar_CheckCollision(moveDir)
--     * blocked: forced movement cleared (and with it the speed); unless the
--       way was uphill the player just stops. Uphill and blocked, they slide
--       BACK one step (WALK_SLOW, facing locked) if that way is open.
--     * open: PlayerAvatar_UpdateIceSpeedFromHeightChange -- uphill speed-1,
--       and below 0 the same slow slide back; downhill speed+1, capped at 3
--       -- then PlayerAvatar_SetIceMovement: speed 0 WALK_FAST, 1
--       WALK_SLIGHTLY_FASTER, 2 and 3 WALK_FASTER, facing locked.
--   The speed starts at 0 (a walk sets none).
--   Both slide-backs also set the IGNORE-TILE-BEHAVIOUR flag
--   (PlayerAvatar_SetIgnoreTileBehavior(1)), which only a WALKED step clears
--   (PlayerAvatar_EnableTileBehaviorCheck needs PlayerAvatar_CheckStep, and
--   no ice step calls StartStep): so the slide back is ONE tile, and the
--   player then stands there, on the ice, until they walk. Without that the
--   floor of the bowl is a pendulum -- Snowpoint's (9,16) is a cell you can
--   only leave sideways, between two ramps, and a slide that kept bouncing
--   there never stopped (an offline search of the gym found no way to
--   Candice that way; with it, one).
--
-- READ FROM CODE (src/overlay005/ov5_021DFB54.c, ov5_021E067C/ov5_021E06A8),
-- run every frame of a forced movement while a step is under way: with the
-- speed at 1 or more, the object one tile ahead of the player's (already
-- advanced) grid position in the moving direction, if its graphics are 0x76
-- (OBJ_EVENT_GFX_SNOWBALL), is broken -- the effect ov5_021EC7F0,
-- MapObject_Delete, SEQ_SE_DP_FW291. Deleted, not flagged: it is back the
-- next time the gym is loaded. So a snowball ahead stops a slide that has not
-- picked up speed and is smashed by one that has.
--
-- Step lengths (src/unk_020655F4.c MovementAction_InitWalk): NORMAL 8 field
-- frames, FAST 4, SLIGHTLY_FASTER 3 (uneven), FASTER 2, SLOW 16 -- as rates
-- of the player's 8-frame walk, 0.5, 0.375, 0.25 and 2.
--
-- Platinum only: HGSS's ice floors (the Ice Path, Mahogany Gym) keep the
-- slide they had.

local Collision = require("src.world.Collision")

local M = {}

M.NONE, M.DECREASE, M.INCREASE = 0, 1, 2
M.RATE = { [0] = 0.5, [1] = 0.375, [2] = 0.25, [3] = 0.25 }
M.SLOW = 2
M.MAX_SPEED = 3
M.AHEAD = 0.25            -- a quarter tile, in tiles
M.SNOWBALL = "snowball"
M.BREAK_SE = "SEQ_SE_DP_FW291"

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local BACK = { up = "down", down = "up", left = "right", right = "left" }

local function game() return package.loaded["src.core.Game"] end

function M.applies(ow)
  local def = ow and ow.map and ow.map.def
  if not (def and def.generation == 4) or def.gen5 then return false end
  local G = game()
  local v = G and G.data and G.data.gen4_version
  return G and G.data and G.data.isGen4Cache and not (v and v.family == "hgss") or false
end

-- every plate under a point given in TILES (fractions allowed), the way
-- Gen4HeightRule samples a tile centre; nil when the map has no height source
function M.surfacesAt(map, fx, fy)
  local def = map and map.def or {}
  local tx, ty = math.floor(fx), math.floor(fy)
  local edits = def.gen4HeightEdits
  local over = type(edits) == "table" and edits[tx .. "," .. ty]
  if type(over) == "number" then return { over } end
  if map.gen4HeightsAt then return map.gen4HeightsAt(tx, ty) end
  local ground = map.renderer and map.renderer.gen4Ground
  local grid, terrain = ground and ground.grid, ground and ground.terrain
  if not (ground and ground.bdhcFor and grid and grid.land and terrain) then return nil end
  local tiles, unit = terrain.chunkTiles or 32, terrain.tileUnits or 16
  local half = (terrain.chunkUnits or 512) / 2
  local mx, my = tx + (def.originX or 0), ty + (def.originY or 0)
  if mx < 0 or my < 0 then return {} end
  local cx, cy = math.floor(mx / tiles), math.floor(my / tiles)
  if cx >= grid.width or cy >= (grid.height or 0) then return {} end
  local land = grid.land[cy * grid.width + cx + 1]
  local ok, bdhc = pcall(ground.bdhcFor, ground, land)
  if not (ok and bdhc) then return {} end
  local recs = require("src.import.Gen4Bdhc").heightsVia(bdhc,
    ((mx % tiles) + (fx - tx)) * unit - half, ((my % tiles) + (fy - ty)) * unit - half)
  local list = {}
  for i = 1, #recs do list[i] = recs[i].height end
  return list
end

-- PlayerAvatar_CheckIceHeightChange
function M.heightChange(map, p, dir)
  local d = DIRS[dir]
  local HR = require("src.world.Gen4HeightRule")
  local here = d and HR.standingY(map, p)
  if not here then return M.NONE end
  local list = M.surfacesAt(map, p.cellX + 0.5 + d[1] * M.AHEAD, p.cellY + 0.5 + d[2] * M.AHEAD)
  if not list or #list == 0 then return M.NONE end
  local there = HR.nearest(list, here)
  if math.abs(there - here) < 0.01 then return M.NONE end
  return there < here and M.DECREASE or M.INCREASE
end

-- ov5_021E06A8: the snowball one tile past (x, y) going `dir`
function M.breakSnowball(ow, x, y, dir)
  local d = DIRS[dir]
  local sx, sy = x + d[1], y + d[2]
  for _, n in ipairs(ow.npcs or {}) do
    local spr = n.def and (n.def.spriteName or n.def.sprite)
    if spr == M.SNOWBALL and not n.hidden and n.cellX == sx and n.cellY == sy then
      n.hidden = true
      pcall(function() require("src.core.Sound").playSe(game().data, M.BREAK_SE) end)
      return n
    end
  end
end

local function stop(ow)
  ow.iceSlide, ow.iceSpeed = nil, nil
  return false
end

-- one forced step from the ice tile the player has just arrived on; true when
-- a step was started (OverworldState:checkGen2Ice's contract)
function M.step(ow)
  local p, map = ow.player, ow.map
  -- the slide back has just ended: the ignore flag holds the player on that
  -- cell (asked by place, not spent once: a step completion can be reported
  -- twice, and a one-shot flag let the second one start the slide again)
  local held = ow.iceBack
  if held and held.map == map and held.x == p.cellX and held.y == p.cellY then return stop(ow) end
  ow.iceBack = nil
  if p.surfing or not ow:isIceCell(p.cellX, p.cellY) then return stop(ow) end
  local ents = ow.cast or ow.entities
  local dir = ow.iceSlide or p.facing
  if not DIRS[dir] then return stop(ow) end
  local change = M.heightChange(map, p, dir)
  local function slideBack()
    -- WALK_SLOW the other way, facing locked; the speed starts again at 0
    local back = BACK[dir]
    if not Collision.canMove(map, ents, p, back) then return stop(ow) end
    local bx, by = Collision.target(p.cellX, p.cellY, back)
    ow.iceSlide, ow.iceSpeed, ow.iceBack = back, 0, { map = map, x = bx, y = by }
    ow:scriptMove(p, back, 1, function() ow:onStepComplete() end, true, M.SLOW)
    return true
  end
  if not Collision.canMove(map, ents, p, dir) then
    if change ~= M.INCREASE then return stop(ow) end
    return slideBack()
  end
  local speed = ow.iceSpeed or 0
  if change == M.INCREASE then speed = speed - 1
  elseif change == M.DECREASE then speed = math.min(M.MAX_SPEED, speed + 1) end
  if speed < 0 then return slideBack() end
  ow.iceSlide, ow.iceSpeed = dir, speed
  if speed >= 1 then
    local tx, ty = Collision.target(p.cellX, p.cellY, dir)
    M.breakSnowball(ow, tx, ty, dir)
  end
  ow:scriptMove(p, dir, 1, function() ow:onStepComplete() end, true, M.RATE[speed])
  return true
end

return M
