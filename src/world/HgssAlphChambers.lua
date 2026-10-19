-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE RUINS OF ALPH'S THREE HIDDEN WALLS (HeartGold / SoulSilver).
--
-- Three of the chambers' first rooms answer a field action at their back
-- wall, standing on (6, 3) and facing north (pokeheartgold src/alph_checks.c):
--
--   CheckUseEscapeRopeInAlphChamber  MAP_RUINS_OF_ALPH_NORTHEAST_ENTRANCE_FIRST_ROOM (D24R0202)
--   CheckUseFlashInAlphChamber       MAP_RUINS_OF_ALPH_SOUTHEAST_ENTRANCE_FIRST_ROOM (D24R0204)
--   CheckUseWaterStoneInAlphChamber  MAP_RUINS_OF_ALPH_SOUTHWEST_ENTRANCE_FIRST_ROOM (D24R0206)
--
-- and each runs that map's script 3 instead of the ordinary action:
--
--   FLASH (field_move.c FieldMove_CheckFlash / Task_UseFlashInField): offered
--     there whatever the weather; _EV_scr_seq_D24R0204_003 with VAR 0x8000 the
--     party slot (FieldMove_SetArgs)
--   ESCAPE ROPE (field_use_item.c ItemCheckUseFunc_EscapeRope ->
--     ExitMenuAndJumpToAlphChamberReaction(_EV_scr_seq_D24R0202_002 + 1)):
--     the rope is NOT used up (Bag_TakeItem is on the ordinary path only)
--   WATER STONE (ItemMenuUseFunc_EvoItem, before the party menu opens):
--     _EV_scr_seq_D24R0206_002 + 1
--   the two items through Task_UseItemInAlphChamber: VAR 0x8000 the item,
--   0x8001..0x8003 zero.
--
-- The scripts shake the screen, "!" the player, hide the wall object and set
-- FLAG_OPENED_ALPH_*_SECRET_ROOM; a second try prints the room's line.

local A = {}

A.X, A.Y, A.FACING = 6, 3, "up"
A.ESCAPE_ROPE = { map = "D24R0202", script = 3, item = 78 }
A.FLASH       = { map = "D24R0204", script = 3 }
A.WATER_STONE = { map = "D24R0206", script = 3, item = 84 }

local function Game() return package.loaded["src.core.Game"] end

local function isHgss(data)
  local v = data and data.gen4_version
  return v and v.family == "hgss" or false
end

-- the cartridge's position test (LocalFieldData_GetCurrentPosition)
function A.at(ow, spot)
  local p = ow and ow.player
  local map = ow and ow.map
  if not (p and map and spot) then return false end
  return map.id == spot.map and p.cellX == A.X and p.cellY == A.Y and p.facing == A.FACING
end

-- the map's own script `spot.script` (1-based, as `_EV_` ids are), started
-- with VAR 0x8000..0x8003 set as the cartridge sets them
function A.run(game, ow, spot, vars)
  local data = game and game.data
  local ms = data and data.map_scripts
  local entry = ms and ((ms.maps and ms.maps[spot.map]) or ms[spot.map])
  local label = entry and entry.entries and entry.entries[spot.script]
  local rows = label and require("src.script.Gen4ScriptVM").compile(data, label)
  if not rows then
    require("src.core.Logger").warn("hgss alph: %s has no script %d in this cache", spot.map, spot.script)
    return false
  end
  local C = require("src.script.Gen4Commands")
  for i = 0, 3 do C.setVar(game.save, 0x8000 + i, (vars and vars[i]) or 0) end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() and ow.queueScript then
    ow:queueScript(rows, { mapId = spot.map })
  else
    ow.runner:run(rows, { mapId = spot.map })
  end
  return true
end

-- the party menu's FLASH (FieldMove_CheckFlash's first test): true when the
-- chamber took it; `close` shuts the menu first
function A.flash(game, slot, close)
  local ow = game and game.overworld
  if not (isHgss(game and game.data) and A.at(ow, A.FLASH)) then return false end
  if close then close() end
  return A.run(game, ow, A.FLASH, { [0] = slot or 0 })
end

local function itemNumber(id)
  local ok, n = pcall(function() return require("src.inventory.Gen4ItemUse").numeric(id) end)
  if ok and n then return n end
  return tonumber(id) or tonumber(tostring(id):match("(%d+)$"))
end

-- the bag's USE, before anything else: true when the chamber took the item
function A.bagItem(game, id, list, battle)
  if battle then return false end
  local ow = game and game.overworld
  if not (ow and isHgss(game and game.data)) then return false end
  local n = itemNumber(id)
  local spot
  if n == A.ESCAPE_ROPE.item and A.at(ow, A.ESCAPE_ROPE) then spot = A.ESCAPE_ROPE
  elseif n == A.WATER_STONE.item and A.at(ow, A.WATER_STONE) then spot = A.WATER_STONE end
  if not spot then return false end
  if list and list.close then list:close() end
  return A.run(game, ow, spot, { [0] = n })
end

return A
