-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CYCLING ROAD'S DOWNHILL ROLL, Platinum's Route 206 and HeartGold /
-- SoulSilver's Route 17 alike.
--
-- Neither game marks a slope on the map. The roll is three conditions on an
-- idle frame, asked before any other tile movement (pokeplatinum
-- player_move.c PlayerAvatar_GetTileMovement -> PlayerAvatar_IsOnCyclingRoadBridge;
-- pokeheartgold unk_0205CB48.s sub_0205D01C -> sub_0205E078, the same test):
--
--   * no direction held (dir == DIR_NONE: A and B do not brake)
--   * the player is cycling (PLAYER_STATE_CYCLING)
--   * the avatar's Cycling Road bit is set -- Platinum's
--     AVATAR_MOVE_ON_CYCLING_ROAD, HGSS's AVATAR_FLAG_LOCK_BIKE_STATE, both
--     bit 3, set by the road's own map scripts (`forcebicycling 1`, HGSS
--     R17's `SetBikeStateLock 1` on transition and on resume). This port
--     keeps that bit in `save.forcedBike` (Commands.g4_force_bike).
--   * and the map object is ON THE ELEVATED BRIDGE: its bridge status bit
--     (flag 28) is set and the tile underfoot is a bridge tile
--     (MapObject_IsOnElevatedBridge; HGSS sub_02060EEC).
--
-- The bridge bit is set by stepping onto a BRIDGE_START tile and cleared by
-- standing on anything that is not a bridge tile (Platinum
-- MapObject_DetermineElevatedBridgeStatus; HGSS sub_02060AB8). On Route 17
-- the deck's top row is BRIDGE_START (0x70) and the rest of it BRIDGE (0x71).
--
-- The roll itself (PlayerAvatar_TileMove_CyclingRoadDown; HGSS sub_0205D190)
-- is one step SOUTH at the bike's speed -- MOVEMENT_ACTION_WALK_FASTER_SOUTH,
-- HGSS movement 0x14 + DIR_SOUTH -- or, when south is blocked, a turn to face
-- south and a stop.

local M = {}

-- HGSS sub_0205BA24 (112) and sub_0205BA30 (113, 114, 115)
M.HGSS_START = 0x70
M.HGSS_BRIDGE = { [0x71] = true, [0x72] = true, [0x73] = true }
-- Platinum TileBehavior_IsBridgeStart / TileBehavior_IsBridge (by name)
M.PT_START_NAME = "BRIDGE_START"
M.PT_BRIDGE_NAMES = { "BRIDGE", "BRIDGE_OVER_CAVE", "BRIDGE_OVER_WATER", "BRIDGE_OVER_SAND",
  "BRIDGE_OVER_SNOW", "BIKE_BRIDGE_N_S", "BIKE_BRIDGE_N_S_OVER_ENCS", "BIKE_BRIDGE_N_S_OVER_WATER",
  "BIKE_BRIDGE_N_S_OVER_SAND", "BIKE_BRIDGE_E_W", "BIKE_BRIDGE_E_W_OVER_ENCS",
  "BIKE_BRIDGE_E_W_OVER_WATER", "BIKE_BRIDGE_E_W_OVER_SAND" }

local ptTables
local function platinumTables()
  if ptTables then return ptTables end
  local B = require("src.import.Gen4Behaviors")
  local start = (B.matching("^" .. M.PT_START_NAME .. "$") or {})[1]
  local bridge = {}
  for _, name in ipairs(M.PT_BRIDGE_NAMES) do
    local v = (B.matching("^" .. name .. "$") or {})[1]
    if v then bridge[v] = true end
  end
  ptTables = { start = start, bridge = bridge }
  return ptTables
end

local function isHgss(data)
  local v = data and data.gen4_version
  return v and v.family == "hgss" or false
end

-- the family's start / bridge tests: (behaviour) -> bool
function M.tables(hgss)
  if hgss then return M.HGSS_START, M.HGSS_BRIDGE end
  local t = platinumTables()
  return t.start, t.bridge
end

-- the bridge bit after standing on `behaviour` with the bit at `was`
-- (MapObject_DetermineElevatedBridgeStatus)
function M.nextBridgeStatus(was, behaviour, hgss)
  local start, bridge = M.tables(hgss)
  if behaviour ~= nil and behaviour == start then return true end
  if was and not (behaviour ~= nil and bridge[behaviour]) then return false end
  return was and true or false
end

-- PlayerAvatar_IsOnCyclingRoadBridge, with the inputs spelled out
function M.shouldRoll(opts)
  if opts.dirHeld then return false end
  if not opts.cycling then return false end
  if not opts.roadBit then return false end
  local _, bridge = M.tables(opts.hgss)
  return opts.onBridge and opts.behaviour ~= nil and bridge[opts.behaviour] == true or false
end

local function Game() return package.loaded["src.core.Game"] end

local function gen4(ow)
  local def = ow and ow.map and ow.map.def
  return def and def.generation == 4 and not (def.gen5 or def.gen4DistWorld)
end

-- called where a step lands (OverworldState:onStepComplete): the bridge bit
-- follows the tile the player now stands on
function M.stepEnded(ow)
  if not gen4(ow) then return end
  local p, map = ow.player, ow.map
  if not (p and map and map.cellBehaviour) then return end
  local G = Game()
  local hgss = isHgss(G and G.data)
  local b = map:cellBehaviour(p.cellX, p.cellY)
  p.gen4OnBridge = M.nextBridgeStatus(p.gen4OnBridge, b, hgss)
end

-- the idle frame (OverworldState:handleInput, no direction held): true when
-- the road rolled the bike (a step started, or a turn south against a wall)
function M.tryRoll(ow)
  if not gen4(ow) then return false end
  local G = Game()
  local save = G and G.save
  local p, map = ow.player, ow.map
  if not (save and p and map and map.cellBehaviour) or p.moving or p.surfing then return false end
  local hgss = isHgss(G.data)
  local b = map:cellBehaviour(p.cellX, p.cellY)
  -- a map entered on the deck (a warp, a load) has had no step yet
  if p.gen4OnBridge == nil then p.gen4OnBridge = M.nextBridgeStatus(false, b, hgss) end
  if not M.shouldRoll({ dirHeld = false, cycling = save.onBike and true or false,
                        roadBit = save.forcedBike and true or false,
                        onBridge = p.gen4OnBridge, behaviour = b, hgss = hgss }) then
    return false
  end
  p.facing = "down"
  local result = p:tryMove("down", map, ow.cast or ow.entities)
  if result == "blocked" then
    -- PLAYER_ACTION_SPEED_NOT_MOVING: faced south, the speed cleared
    p.facing = "down"
  end
  return true
end

return M
