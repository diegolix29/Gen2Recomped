-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) tile behaviours: what kind of ground a map cell is.
--
-- A Platinum permission cell is one u16 -- bit 15 says the cell is not part
-- of the map, and the LOW BYTE is this.  Nothing else in the cartridge says
-- what those 256 values mean, and only 75 of them appear in the overworld, so
-- a colour-per-value stand-in would have been guesswork dressed as data.
--
-- These are pokeplatinum's names and its own flag table -- 108 of the 256 are
-- real names and the rest are recorded as UNUSED_xNN rather than renumbered,
-- because the gaps are part of the numbering.  No cartridge bytes are stored
-- here; these are names for values the player's own ROM supplies.
--
-- WHY THE FLAGS MATTER MORE THAN THE NAMES.  Whether a cell can start a wild
-- battle and whether it can be surfed are not derivable from the name -- the
-- cartridge marks six UNUSED behaviours as encounter tiles and eight as
-- surfable -- so both come from sTileBehaviorFlags rather than from reading
-- the names and guessing.

local Gen4Behaviors = {}

-- One name per value 0..255, in order, delimited.  Split lazily.
Gen4Behaviors.PACKED =
	"NONE|UNUSED_x01|TALL_GRASS|VERY_TALL_GRASS|UNUSED_x04|UNUSED_x05|UNUSED_x06|UNUSED_x07|CAVE_FLOOR|UNUSED_x09" ..
	"|UNUSED_x0A|OLD_CHATEAU_FLOOR|MOUNTAIN_FLOOR|UNUSED_x0D|UNUSED_x0E|UNUSED_x0F|WATER_RIVER|UNUSED_x11" ..
	"|UNUSED_x12|WATERFALL|UNUSED_x14|WATER_SEA|PUDDLE|SHALLOW_WATER|UNUSED_x18|UNUSED_x19|UNUSED_x1A|UNUSED_x1B" ..
	"|UNUSED_x1C|PUDDLE_NO_SPLASHING|UNUSED_x1E|UNUSED_x1F|ICE|SAND|UNUSED_x22|UNUSED_x23|UNUSED_x24|UNUSED_x25" ..
	"|UNUSED_x26|UNUSED_x27|UNUSED_x28|UNUSED_x29|UNUSED_x2A|UNUSED_x2B|REFLECTIVE|FORBIDS_EXPLORATION_KIT" ..
	"|UNUSED_x2E|UNUSED_x2F|BLOCK_EASTWARD|BLOCK_WESTWARD|BLOCK_NORTHWARD|BLOCK_SOUTHWARD|BLOCK_NORTH_AND_EAST" ..
	"|BLOCK_NORTH_AND_WEST|BLOCK_SOUTH_AND_EAST|BLOCK_SOUTH_AND_WEST|JUMP_EAST|JUMP_WEST|JUMP_NORTH|JUMP_SOUTH" ..
	"|UNKNOWN_x3C|UNKNOWN_x3D|UNKNOWN_x3E|UNKNOWN_x3F|SLIDE_EASTWARD|SLIDE_WESTWARD|SLIDE_NORTHWARD" ..
	"|SLIDE_SOUTHWARD|UNUSED_x44|UNUSED_x45|UNUSED_x46|UNUSED_x47|UNUSED_x48|BLOCK_NORTH_AND_SOUTH" ..
	"|BLOCK_EAST_AND_WEST|ROCK_CLIMB_N_S|ROCK_CLIMB_E_W|UNUSED_x4D|UNUSED_x4E|UNUSED_x4F|UNUSED_x50|UNUSED_x51" ..
	"|UNUSED_x52|UNUSED_x53|UNUSED_x54|UNUSED_x55|PASTORIA_GYM_H_GROUND|PASTORIA_GYM_M_GROUND" ..
	"|PASTORIA_GYM_L_GROUND|DYNAMIC_HEIGHT_COLLISION|JUMP_NORTH_TWICE|JUMP_SOUTH_TWICE|JUMP_WEST_TWICE" ..
	"|JUMP_EAST_TWICE|WARP_STAIRS_EAST|WARP_STAIRS_WEST|UNKNOWN_x60|UNUSED_x61|WARP_ENTRANCE_EAST" ..
	"|WARP_ENTRANCE_WEST|WARP_ENTRANCE_NORTH|WARP_ENTRANCE_SOUTH|UNUSED_x66|WARP_PANEL|UNUSED_x68|DOOR" ..
	"|ESCALATOR_FLIP_FACE|ESCALATOR|WARP_EAST|WARP_WEST|WARP_NORTH|WARP_SOUTH|BRIDGE_START|BRIDGE|BRIDGE_OVER_CAVE" ..
	"|BRIDGE_OVER_WATER|BRIDGE_OVER_SAND|BRIDGE_OVER_SNOW|BIKE_BRIDGE_N_S|BIKE_BRIDGE_N_S_OVER_ENCS" ..
	"|BIKE_BRIDGE_N_S_OVER_WATER|BIKE_BRIDGE_N_S_OVER_SAND|BIKE_BRIDGE_E_W|BIKE_BRIDGE_E_W_OVER_ENCS" ..
	"|BIKE_BRIDGE_E_W_OVER_WATER|BIKE_BRIDGE_E_W_OVER_SAND|UNUSED_x7E|UNUSED_x7F|TABLE|UNUSED_x81|UNUSED_x82|PC" ..
	"|UNUSED_x84|TOWN_MAP|TV|UNUSED_x87|UNKNOWN_x88|UNUSED_x89|UNUSED_x8A|UNUSED_x8B|UNUSED_x8C|UNUSED_x8D" ..
	"|UNKNOWN_x8E|UNKNOWN_x8F|UNUSED_x90|UNUSED_x91|UNUSED_x92|UNUSED_x93|UNUSED_x94|UNUSED_x95|UNUSED_x96" ..
	"|UNUSED_x97|UNUSED_x98|UNUSED_x99|UNUSED_x9A|UNUSED_x9B|UNUSED_x9C|UNUSED_x9D|UNUSED_x9E|UNUSED_x9F" ..
	"|BERRY_PATCH|SNOW_DEEP|SNOW_DEEPER|SNOW_DEEPEST|MUD|MUD_DEEP|MUD_WITH_GRASS|MUD_DEEP_WITH_GRASS|SNOW_SHALLOW" ..
	"|SNOW_WITH_SHADOWS|UNUSED_xAA|UNUSED_xAB|UNUSED_xAC|UNUSED_xAD|UNUSED_xAE|UNUSED_xAF|UNUSED_xB0|UNUSED_xB1" ..
	"|UNUSED_xB2|UNUSED_xB3|UNUSED_xB4|UNUSED_xB5|UNUSED_xB6|UNUSED_xB7|UNUSED_xB8|UNUSED_xB9|UNUSED_xBA" ..
	"|UNUSED_xBB|UNUSED_xBC|UNUSED_xBD|UNUSED_xBE|UNUSED_xBF|UNUSED_xC0|UNUSED_xC1|UNUSED_xC2|UNUSED_xC3" ..
	"|UNUSED_xC4|UNUSED_xC5|UNUSED_xC6|UNUSED_xC7|UNUSED_xC8|UNUSED_xC9|UNUSED_xCA|UNUSED_xCB|UNUSED_xCC" ..
	"|UNUSED_xCD|UNUSED_xCE|UNUSED_xCF|UNUSED_xD0|UNUSED_xD1|UNUSED_xD2|UNUSED_xD3|UNUSED_xD4|UNUSED_xD5" ..
	"|UNUSED_xD6|BIKE_RAMP_EASTWARD|BIKE_RAMP_WESTWARD|BIKE_SLOPE_TOP|BIKE_SLOPE_BOTTOM|BIKE_PARKING|UNUSED_xDC" ..
	"|UNUSED_xDD|UNUSED_xDE|UNUSED_xDF|SMALL_BOOKSHELF_1|BOOKSHELF_1|BOOKSHELF_2|UNUSED_xE3|TRASH_CAN|MART_SHELF_1" ..
	"|UNUSED_xE6|UNUSED_xE7|UNUSED_xE8|UNUSED_xE9|SMALL_BOOKSHELF_2|MART_SHELF_2|MART_SHELF_3|UNUSED_xED" ..
	"|UNUSED_xEE|UNUSED_xEF|UNUSED_xF0|UNUSED_xF1|UNUSED_xF2|UNUSED_xF3|UNUSED_xF4|UNUSED_xF5|UNUSED_xF6" ..
	"|UNUSED_xF7|UNUSED_xF8|UNUSED_xF9|UNUSED_xFA|UNUSED_xFB|UNUSED_xFC|UNUSED_xFD|UNUSED_xFE|MAX"

-- Flags per value, one digit each: bit 0 surfable, bit 1 encounter.
Gen4Behaviors.FLAGS =
	"0022022020020000333113000100000000302200003000000000000000000000" ..
	"0000000000000000111100000000000000000000000000000021000210021000" ..
	"0000000000000000000000000000000000000022000000000000000000000000" ..
	"0000000000000000000000000000000000000000000000000000000000000000"

Gen4Behaviors.SURFABLE_BIT = 1
Gen4Behaviors.ENCOUNTER_BIT = 2

Gen4Behaviors.cache = nil

-- names() -> array of 256 names, index = value + 1.
function Gen4Behaviors.names()
	if Gen4Behaviors.cache then return Gen4Behaviors.cache end
	local out, n = {}, 0
	for piece in Gen4Behaviors.PACKED:gmatch("[^|]+") do
		n = n + 1
		out[n] = piece
	end
	Gen4Behaviors.cache = out
	return out
end

-- name(value) -> "TALL_GRASS", or nil outside 0..255.
function Gen4Behaviors.name(value)
	if type(value) ~= "number" or value < 0 or value > 255 then return nil end
	return Gen4Behaviors.names()[value + 1]
end

-- flags(value) -> the flag byte for this behaviour.
function Gen4Behaviors.flags(value)
	if type(value) ~= "number" or value < 0 or value > 255 then return 0 end
	return tonumber(Gen4Behaviors.FLAGS:sub(value + 1, value + 1)) or 0
end

function Gen4Behaviors.isEncounter(value)
	return Gen4Behaviors.flags(value) % 4 >= Gen4Behaviors.ENCOUNTER_BIT
end

function Gen4Behaviors.isSurfable(value)
	return Gen4Behaviors.flags(value) % 2 == 1
end

-- named(value) -> true when the cartridge gives this value a real name.
-- An UNUSED value still occurs and still carries flags; this only says
-- whether anything is known about what it IS.
function Gen4Behaviors.named(value)
	local n = Gen4Behaviors.name(value)
	return n ~= nil and n:sub(1, 7) ~= "UNUSED_"
end

-- matching(pattern) -> sorted array of values whose name matches.
function Gen4Behaviors.matching(pattern)
	local out = {}
	local list = Gen4Behaviors.names()
	for i = 1, #list do
		if list[i]:match(pattern) then out[#out + 1] = i - 1 end
	end
	return out
end

-- set(name) -> one of the derived groups below, as a sorted value array.
--
-- These are derived from the names rather than restated, so a value cannot
-- appear in a list and be missing from the table it came from.  Each is
-- computed once.
Gen4Behaviors.GROUPS = {
	encounter = function() 
		local out = {}
		for v = 0, 255 do if Gen4Behaviors.isEncounter(v) then out[#out + 1] = v end end
		return out
	end,
	surfable = function()
		local out = {}
		for v = 0, 255 do if Gen4Behaviors.isSurfable(v) then out[#out + 1] = v end end
		return out
	end,
	-- What RUSTLES and what the player is drawn waist-deep in -- a narrower
	-- question than where a battle can start, exactly as it is in Gen 3.
	grass = function() return Gen4Behaviors.matching("GRASS") end,
	jump = function() return Gen4Behaviors.matching("^JUMP_") end,
	door = function() return Gen4Behaviors.matching("^DOOR") end,
	warp = function() return Gen4Behaviors.matching("^WARP") end,
	stairs = function() return Gen4Behaviors.matching("STAIRS") end,
	ice = function() return Gen4Behaviors.matching("^ICE") end,
	sand = function() return Gen4Behaviors.matching("SAND") end,
	snow = function() return Gen4Behaviors.matching("^SNOW") end,
	mud = function() return Gen4Behaviors.matching("^MUD") end,
	water = function() return Gen4Behaviors.matching("WATER") end,
}

Gen4Behaviors.groupCache = {}

function Gen4Behaviors.group(name)
	if Gen4Behaviors.groupCache[name] then return Gen4Behaviors.groupCache[name] end
	local build = Gen4Behaviors.GROUPS[name]
	if not build then return nil end
	local out = build()
	Gen4Behaviors.groupCache[name] = out
	return out
end

-- jumpDirection(value) -> "north" | "south" | "east" | "west", or nil.
-- The doubles (JUMP_*_TWICE) report the same direction; how far is the
-- caller's business.
function Gen4Behaviors.jumpDirection(value)
	local n = Gen4Behaviors.name(value)
	if not n then return nil end
	local dir = n:match("^JUMP_(%a+)")
	return dir and dir:lower() or nil
end

return Gen4Behaviors
