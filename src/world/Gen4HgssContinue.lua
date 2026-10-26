-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A HEARTGOLD / SOULSILVER CONTINUE WITH THE COMMUNICATION-CLUB FLAG SET.
--
-- THE RULE, READ FROM CODE (pokeheartgold src/field_warp_tasks.c,
-- FieldTask_ContinueGame_Normal, case 0):
--
--   if (CheckFlag966(varsFlags)) {                    // FLAG_UNK_966, 0x966
--       if (_IsPlayerStandingInFrontOfUnionRoomReception(fieldSystem))
--           _SetDynamicWarpToUnionRoomExit(fieldSystem);
--       ClearFlag966(varsFlags);
--       sub_02052F94(fieldSystem, LocalFieldData_GetDynamicWarp(...));
--       sub_02053284; sub_02053038(fieldSystem, FALSE); sub_0205316C;
--   } else {
--       sub_02052F94(fieldSystem, NULL); sub_02053284;
--       FieldSystem_StartBugContestTimer; sub_0205323C;   // the continue
--   }
--
-- So with the flag the player is put at the DYNAMIC WARP and the map is
-- entered the way a warp enters it (sub_02053038 = the game-data update:
-- temp flags and vars cleared, ON_TRANSITION, objects built fresh) -- the
-- same walk-in Platinum's Battle Tower "Rest" save takes. The flag is spent.
--
--   _IsPlayerStandingInFrontOfUnionRoomReception: a Pokemon Center 1F
--   (map_header.c sPokemonCenterMaps) at (6,6), or the Pokemon League lobby
--   (MAP_POKEMON_LEAGUE_ENTRANCE, T10R0101) at (3,15).
--   _SetDynamicWarpToUnionRoomExit: the same map, warp -1, at (4,11) in the
--   lobby or (7,2) in a Center, facing south.
--
-- WHO SETS THE FLAG:
--   * the communication club's reception (scr_seq_0004: `SetFlag
--     FLAG_UNK_966` before its std_prompt_save, cleared again if you say no
--     or come back), standing at the desk -- the case above.
--   * the Battle Tower (ScrCmd_412 case 5, sub_0204A6A8): the dynamic warp =
--     where the player stands, facing north, and the flag; case 6
--     (sub_0204A6E8) clears the flag only.
--   * the Hall of Fame (game_clear.c): dynamic warp = the player's room,
--     the flag, then the save.
--
-- THE PORT keeps the dynamic warp in `save.gen4SpecialLocation` (HGSS's
-- setdynamicwarp is lowered onto Platinum's setspeciallocation). The Battle
-- Tower and Hall of Fame writers mark the slot they write with `club = true`;
-- a slot without the mark may be a lift's from long ago (a save the port made
-- before those writers set it), and is NOT trusted: the player then walks in
-- where the save stands, which is where those old saves already put them.

local M = {}

M.FLAG = "FLAG_G4_0966"

-- map_header.c sPokemonCenterMaps (MAP_EVERYWHERE, 0, is never a location)
M.CENTERS = {
  T02PC0101 = true, T03PC0101 = true, T04PC0101 = true, T05PC0101 = true,
  T06PC0101 = true, T07PC0101 = true, T08PC0101 = true, T09PC0101 = true,
  T11PC0101 = true, T21PC0101 = true, T22PC0101 = true, T23PC0101 = true,
  T24PC0101 = true, T25PC0101 = true, T26PC0101 = true, T27PC0101 = true,
  T28PC0101 = true, T30PC0101 = true, T31PC0101 = true, R03PC0101 = true,
  R10PC0101 = true, R32PC0101 = true, D32PC0101 = true, D47PC0101 = true,
}
M.LEAGUE_LOBBY = "T10R0101"

function M.isHgss()
  local v = require("src.core.GameVersion").get()
  return v == "heartgold" or v == "soulsilver"
end

function M.flagSet(save)
  return type(save) == "table" and type(save.flags) == "table" and save.flags[M.FLAG] == true
end

-- the Battle Tower's / Hall of Fame's write: the dynamic warp and the flag
function M.mark(save, map, x, y, facing)
  if type(save) ~= "table" or not map then return end
  save.gen4SpecialLocation = { map = map, x = x, y = y, facing = facing or "up", club = true }
  save.flags = save.flags or {}
  save.flags[M.FLAG] = true
end

-- Game:restoreSave, before the overworld is pushed. Answers true when this
-- continue is a walk-in (the flag was set); moves save.player to the
-- dynamic warp when there is one to trust.
function M.apply(save)
  if not (M.isHgss() and M.flagSet(save) and type(save.player) == "table") then return false end
  local p = save.player
  local loc = save.gen4SpecialLocation
  if (M.CENTERS[p.map] and p.x == 6 and p.y == 6)
     or (p.map == M.LEAGUE_LOBBY and p.x == 3 and p.y == 15) then
    local lobby = p.map == M.LEAGUE_LOBBY
    loc = { map = p.map, x = lobby and 4 or 7, y = lobby and 11 or 2, facing = "down", club = true }
    save.gen4SpecialLocation = loc
  end
  -- ClearFlag966 (false, not nil: a nil flag can be re-set by the load's
  -- opening-flag repair)
  save.flags[M.FLAG] = false
  if type(loc) == "table" and loc.club and loc.map then
    p.map, p.x, p.y = loc.map, loc.x or p.x, loc.y or p.y
    p.facing = loc.facing or p.facing or "down"
  end
  return true
end

return M
