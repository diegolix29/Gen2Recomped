-- Run:  python tools/run_lua_check.py tools/gen4_hm_check.lua
--
-- PLATINUM'S HMs FROM THE OVERWORLD: Surf, Waterfall and Rock Climb (an HM
-- sweep found all three dead) and Strength's Gen 4 boulders.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local Map = require('src.world.Map')
-- sTileBehaviorFlags' SURFABLE rows (pokeplatinum src/map_tile_behavior.c)
check(Map.G4_SURFABLE[0x10] and Map.G4_SURFABLE[0x15] and Map.G4_SURFABLE[0x13], 'river, sea and waterfall are surfable')
check(not Map.G4_SURFABLE[0x17] and not Map.G4_SURFABLE[0x16], 'shallow water and puddles are walked through')
check(Map.G4_BRIDGE_OVER_WATER[0x73] and not Map.G4_SURFABLE[0x73], 'a bridge over water is walkable on top, surfable under')

-- a Platinum map stops a walker at the water and lets a surfer on
local function fakeMap(behaviour, hgss)
  return setmetatable({ def = { generation = 4, cameraFamily = hgss and 'hgss' or nil, width = 4, height = 4 } }, { __index = {
    inBounds = function() return true end,
    cellBehaviour = function() return behaviour end,
    gen4WaterAt = Map.gen4WaterAt,
    isWaterCell = Map.isWaterCell,
  } })
end
local sea = fakeMap(0x15)
check(sea:gen4WaterAt(1, 1) and sea:isWaterCell(1, 1), 'the sea is water to a surfer')
check(not fakeMap(0x15, true):gen4WaterAt(1, 1), 'HeartGold/SoulSilver keep their own water rule')

-- the press rules below Field_TileBehaviorToScript's table
package.loaded['src.core.Game'] = { data = { gen4_version = { family = 'platinum' } }, save = { party = {} } }
local TS = require('src.world.Gen4TileScripts')
local row = TS.fieldMoveRow({ player = {} }, 0x4B, 'up')
check(row and row.index == 3, 'ROCK_CLIMB_N_S facing north runs FIELD_MOVES 3')
check(TS.fieldMoveRow({ player = {} }, 0x4B, 'left') == nil, '...but not facing west')
check(TS.fieldMoveRow({ player = {} }, 0x15, 'up') == nil, 'no Surf prompt without a Surfer and the badge')
package.loaded['src.core.Game'] = nil

-- the commands are real now
local Commands = require('src.script.Commands')
require('src.script.Gen4Commands')
local src = io.open('src/script/Gen4Commands.lua'):read('a')
check(type(Commands.g4_use_rock_climb) == 'function' and not src:find('\npending%("g4_use_rock_climb"'), 'UseRockClimb climbs')
check(src:find('gen4Climb(ctx, function(b) return b == 0x13 end)', 1, true), 'UseWaterfall climbs the 0x13 run')
check(src:find('stepForwardOrCrossEdge', 1, true) and src:find('function Commands.g4_use_surf', 1, true), 'UseSurf hops onto the water')

-- Strength's Gen 4 boulders
check(Map.isPushable({ spriteName = 'strength_boulder' }), "Platinum's boulder is pushable")

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
