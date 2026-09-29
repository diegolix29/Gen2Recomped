-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SECOND SCRIPT A MAP HAS, AND THE ONE THAT MAKES ITS SCENES HAPPEN.
--
-- Reported from play, all three at once: *"theres a woman thats part of a
-- script blocking the door and mom does nothing as i come down stairs and my
-- rival doesnt talk to me as i approach the stairs."*  One cause.
--
-- A Gen 4 map header names TWO members of `scr_seq`.  `scriptsArchiveID` is
-- the one everything has always read -- the scripts an object or a sign runs
-- when you talk to it.  `initScriptsArchiveID` is the other one, and the port
-- parsed the field in `Gen4MapHeaders` and then never looked at it.  It is the
-- map's own entry conditions: what runs when you walk in, and what is watched
-- every frame while you stand there.  **291 of the 594 headers have one**, and
-- none of them has ever run.
--
-- THE TABLE is a list of five-byte records terminated by a zero type byte
-- (`FieldSystem_GetFixedInitScriptID`, script_manager.c):
--
--     u8 type; u8 payload[4];
--
-- and the four payload bytes are read according to the type:
--
--     2  INIT_SCRIPT_ON_TRANSITION   u16 scriptID   -- walking in
--     3  INIT_SCRIPT_ON_RESUME       u16 scriptID   -- coming back to the field
--     4  INIT_SCRIPT_ON_LOAD         u16 scriptID   -- the map being built
--     1  INIT_SCRIPT_ON_FRAME_TABLE  u32 offset     -- a table, see below
--
-- Types 2, 3 and 4 are run at once by `FieldSystem_RunScript`.  Type 1 points
-- at a second list, reached from the byte AFTER its own u32, of
--
--     u16 a; u16 b; u16 scriptID
--
-- terminated by a zero `a`, and it is asked EVERY IDLE FIELD FRAME
-- (`field_control.c` calls `FieldSystem_RunInitScript(ON_FRAME_TABLE)` from
-- three places).  The first row whose two sides are equal starts its script.
--
-- BOTH SIDES GO THROUGH `FieldSystem_TryGetVar`, which returns the VALUE when
-- the id names a var and THE ID ITSELF when it does not.  So a row is not
-- "var == var": it is "whatever these two resolve to, compared" -- which in
-- practice is a var against a literal, and reading it as two vars would
-- compare a var against whatever happened to be in var 0.
--
-- MEASURED over all 594 headers: 291 carry a table, 236 ON_TRANSITION, 46
-- ON_LOAD, 36 ON_RESUME and 105 frame tables with 207 rows between them.  One
-- record has a type byte of 14, which is not one of the four; it is reported
-- and skipped rather than guessed at.
--
-- THE PLAYER'S HOUSE IN TWINLEAF is the report above, exactly.  Header 414
-- (T01R0201) has `on_transition -> script 1` and a three-row frame table:
--
--     var 0x40A4 == 0      -> script 2
--     var 0x410F == 1      -> script 11
--     var 0x40A4 == 3      -> script 3
--
-- and entry 2 of its script member is `lockall / applymovement 0xFF /
-- applymovement 0 / waitmovement / setflag / bufferplayername /
-- bufferrivalname / message / ... / setvarfromvalue 0x40A4 1 / releaseall`.
-- That is Mom's scene.  Entry 3 ends with `giverunningshoes`.  With nothing
-- reading the table, 0x40A4 stays 0 for ever: Mom never moves, the scene that
-- would clear the doorway never runs, and the actor standing in it stays
-- standing in it.

local Gen4InitScripts = {}

Gen4InitScripts.RECORD_BYTES = 5

Gen4InitScripts.ON_FRAME_TABLE = 1
Gen4InitScripts.ON_TRANSITION = 2
Gen4InitScripts.ON_RESUME = 3
Gen4InitScripts.ON_LOAD = 4

Gen4InitScripts.TYPE_NAME = {
  [1] = "frame_table", [2] = "on_transition", [3] = "on_resume", [4] = "on_load",
}

local function u8(s, at) return s:byte(at + 1) end
local function u16(s, at)
  local a, b = s:byte(at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end
local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- parse(bytes) -> { callbacks = { { type, name, script } }, tables = { { type,
-- name, rows = { { a, b, script } } } } }, plus a count of records whose type
-- is not one of the four.
--
-- Offsets are ZERO-BASED inside this function because the cartridge's own
-- arithmetic is, and every read goes through the helpers above, which add the
-- one back for Lua.
function Gen4InitScripts.parse(bytes)
  if type(bytes) ~= "string" or #bytes < Gen4InitScripts.RECORD_BYTES then
    return nil
  end
  local callbacks, tables, unknown = {}, {}, 0
  local at = 0
  while at + Gen4InitScripts.RECORD_BYTES <= #bytes do
    local kind = u8(bytes, at)
    if kind == 0 then break end
    if kind == Gen4InitScripts.ON_FRAME_TABLE then
      local offset = u32(bytes, at + 1)
      local rows = {}
      -- "the byte after the u32", which is this record's end.
      local p = offset and (at + Gen4InitScripts.RECORD_BYTES + offset)
      while p and p + 6 <= #bytes do
        local a = u16(bytes, p)
        -- A zero first halfword ends the list, and so does a zero type byte at
        -- the same place -- the cartridge tests both, and they are the same
        -- byte, so one test is the whole of it here.
        if not a or a == 0 then break end
        rows[#rows + 1] = { a = a, b = u16(bytes, p + 2), script = u16(bytes, p + 4) }
        p = p + 6
      end
      tables[#tables + 1] = {
        type = kind, name = Gen4InitScripts.TYPE_NAME[kind], rows = rows,
      }
    elseif Gen4InitScripts.TYPE_NAME[kind] then
      callbacks[#callbacks + 1] = {
        type = kind, name = Gen4InitScripts.TYPE_NAME[kind],
        script = u16(bytes, at + 1),
      }
    else
      unknown = unknown + 1
    end
    at = at + Gen4InitScripts.RECORD_BYTES
  end
  if #callbacks == 0 and #tables == 0 then return nil, unknown end
  return { callbacks = callbacks, tables = tables }, unknown
end

return Gen4InitScripts
