-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK AND WHITE'S TILE BEHAVIOURS, as the field overlay (ov21) reads them.
--
-- A BW permission tile is 8 bytes; bytes 4-5 are the behaviour and bytes 6-7
-- its attribute flags. The flags are the same for every tile of a behaviour
-- (all 649 chunks of /a/0/0/8 tabulated: scratch bwfield/tools/permflags.py),
-- so the importer's behaviour byte is enough to know them:
--
--   bit 0x01 blocked   0x02 water   0x04 ENCOUNTER   0x10 surfable
--   0x20 grass         0x40 / 0x80 / 0x08 (footprints, reflections: not read)
--
-- The encounter bit is on 0x04-0x09 and 0x21/0x22 (grass), 0x0A and 0x30
-- (cave floor), 0x0C and 0x23 (sand), 0x16, 0x1C, and the water 0x3D / 0x3F /
-- 0x43. Before this the engine read BW behaviours as PLATINUM's numbers: the
-- dirt path (0x03, Platinum's very tall grass) rolled grass encounters and the
-- grass itself (0x04) never did.
--
-- The predicates are ov21's own (0x021AB23C..0x021AB2D6):
--   grass       4, 0x21, 5      (021AB23C)    tall grass   8 (021AB264)
--   dark grass  6, 0x22, 7      (021AB250)    dark tall    9 (021AB270)
-- and 0x021AB504 sorts a tile into its PHENOMENON kind (the "!" spots):
--   4 -> 0, 5 -> 1, 0x21 -> 2, 8 -> 3 (shaking grass), 0x0A -> 4 (dust
--   cloud), 0x3D -> 5, 0x3F / 0x43 -> 6 (rippling water), 0x20 -> 7 (a flying
--   shadow on a bridge), anything else 8 (none) -- and only on an encounter
--   tile, except the bridge.

local R = {}

R.ENCOUNTER = {}
for _, b in ipairs({ 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0C, 0x16, 0x1C,
                     0x21, 0x22, 0x23, 0x30, 0x3D, 0x3F, 0x43 }) do R.ENCOUNTER[b] = true end
R.GRASS = { [0x04] = true, [0x05] = true, [0x21] = true, [0x08] = true,
            [0x06] = true, [0x07] = true, [0x22] = true, [0x09] = true }
R.DARK_GRASS = { [0x06] = true, [0x07] = true, [0x22] = true, [0x09] = true }
R.WATER_ENCOUNTER = { [0x3D] = true, [0x3F] = true, [0x43] = true }
R.BRIDGE = 0x20
R.WATERFALL = 0x40
R.CAVE_FLOOR = { [0x0A] = true, [0x30] = true }

-- 0x021AB504: the phenomenon kind of a behaviour, or nil
local PHENOMENON = { [0x04] = "grass", [0x05] = "grass", [0x21] = "grass", [0x08] = "grass",
                     [0x0A] = "dust", [0x3D] = "water", [0x3F] = "water", [0x43] = "water",
                     [0x20] = "shadow" }
function R.phenomenonKind(b) return b and PHENOMENON[b] or nil end

local function behaviour(map, cx, cy)
  if not (map and map.inBounds and map:inBounds(cx, cy)) then return nil end
  return map:cellBehaviour(cx, cy)
end
R.behaviour = behaviour

function R.isGen5(map) return map and map.def and map.def.gen5 and true or false end
function R.isGrass(map, cx, cy) return R.GRASS[behaviour(map, cx, cy) or -1] or false end
function R.isDarkGrass(map, cx, cy) return R.DARK_GRASS[behaviour(map, cx, cy) or -1] or false end
-- land encounters: the encounter bit, minus the water (a surfer's roll)
function R.isLandEncounter(map, cx, cy)
  local b = behaviour(map, cx, cy)
  return b ~= nil and R.ENCOUNTER[b] and not R.WATER_ENCOUNTER[b] or false
end
function R.isWaterfall(map, cx, cy) return behaviour(map, cx, cy) == R.WATERFALL end

-- THE SEASON: the month's place in a four-month cycle (scripts' 0x0D2 and the
-- battle backgrounds read it the same way). `save.gen5Season` (0..3) or the
-- harness's BW_SEASON pins it.
R.SEASONS = { [0] = "spring", "summer", "autumn", "winter" }
function R.season(save)
  local pinned = save and tonumber(save.gen5Season)
  if pinned then return pinned % 4 end
  local env = os.getenv and tonumber(os.getenv("BW_SEASON") or "")
  if env then return env % 4 end
  return ((tonumber(os.date("%m")) or 1) - 1) % 4
end
function R.seasonName(save) return R.SEASONS[R.season(save)] end

return R
