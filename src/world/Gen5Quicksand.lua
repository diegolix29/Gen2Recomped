-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- RELIC CASTLE'S QUICKSAND (Black / White, behaviour 0x7C).
--
-- The castle's pits are 5 x 5 coord events laid over funnel cells of
-- behaviour 0x7C; each pit's script is `lockall; 0x0C1 <zone, x, z>` (the
-- fall). Overlay 21 asks for behaviour 0x7C in exactly two places, both in
-- the field's coord-event check (no decomp; read off the ROM's ov21):
--
--   * 0x218A784, the ORDINARY coord check (direction 9 = "standing here"):
--     the cell under the player is read (0x21A3038 -> 0x21AB0D4) and if it is
--     0x7C (0x21AB188) the check answers "nothing" before any event is
--     looked up. No coord event fires on a quicksand cell the ordinary way.
--   * 0x218A8BC, the PIT check, asked first (0x218A76C): only on a 0x7C cell,
--     it looks up the coord event there (0x216282C, var condition included)
--     and runs its script when
--       - the player is on the rectangle's CENTRE, x + (w >> 1), z + (h >> 1)
--         (the event's u16s at +0x0A/+0x0C/+0x0E/+0x10), or
--       - the player object is not walking (its word at +0x40, 0x2012B28,
--         is 0), or
--       - its current action (MapObject +0x26, 0x216D7C4) is 0x58..0x5B or
--         0xA3..0xA6 -- the walk-in-place a blocked step plays (ov21
--         0x21A4DC0 picks 0x58 when the step is refused, 0xA3 running).
--     A walker passing over the sand is in none of those, so it crosses.
--
-- The pull towards the centre is the fall's own: 0x0C1's handler (ov21
-- 0x21AFDAC) looks the same pit up again and hands its rectangle to the
-- sinking task (ov20 0x2184E40) with the landing cell, so the drag is part
-- of the fall's animation, not of walking. It is not drawn here; the fall
-- is the map warp it ends in.
--
-- Here: Gen4ScriptVM's coord hook asks `pitFires` for a coord whose cell is
-- sand, and OverworldController calls `tick` every idle field frame, which
-- re-asks the cell once the player has stood still on it.

local Q = {}

Q.BEHAVIOUR = 0x7C

-- frames the player must be still on the sand before it counts as standing:
-- the first idle frame after a step lands is the one a held direction starts
-- the next step on (the idle hook runs before handleInput)
Q.STILL_FRAMES = 2

function Q.onSand(overworld, x, y)
  local map = overworld and overworld.map
  if not (map and map.def and map.def.gen5 and map.cellBehaviour and x and y) then return false end
  return map:cellBehaviour(x, y) == Q.BEHAVIOUR
end

-- whether the pit `coord` (x, y, width, height) runs for a player on (x, y)
function Q.pitFires(overworld, coord, x, y)
  local cx = coord.x + math.floor((coord.width or 1) / 2)
  local cy = coord.y + math.floor((coord.height or 1) / 2)
  if x == cx and y == cy then return true end
  return overworld.gen5SandStill == true
end

-- every idle field frame (runner idle, no fade)
function Q.tick(overworld)
  local p = overworld and overworld.player
  if not (p and p.cellX) or p.moving or not Q.onSand(overworld, p.cellX, p.cellY) then
    overworld.gen5SandFrames = nil
    return false
  end
  if overworld.gen5SandSerial ~= overworld.cellSerial then
    overworld.gen5SandSerial, overworld.gen5SandFrames = overworld.cellSerial, 0
  end
  local n = (overworld.gen5SandFrames or 0) + 1
  overworld.gen5SandFrames = n
  if n < Q.STILL_FRAMES then return false end
  overworld.gen5SandStill = true
  local ok, fired = pcall(overworld.checkCoordEventHere, overworld, true)
  overworld.gen5SandStill = nil
  return ok and fired or false
end

return Q
