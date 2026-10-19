-- BLACK / WHITE: WHICH WARPS A STEP TAKES.
--
-- A BW warp record (/a/1/2/5, src/import/Gen5Events.lua) carries two bytes the
-- field reads to decide how it is taken:
--
--   +4  the CONTACT DIRECTION -- ov10 0x21626B8 compares it with the facing
--       (2 up, 1 down, 4 left, 3 right; 0 none)
--   +5  the TRANSITION type   -- ov10 0x21626E8
--
-- After a completed step the field asks the warp under the player
-- (ov21 0x218ACD0, run from the step handler 0x2189C56 once the coord events
-- have had their turn) and takes it when its transition type is 0, 5 or 6
-- (0x218AEAC: `1 << type & 0x61`). Every other warp waits for a press whose
-- facing matches its contact direction (0x218AED4) -- the doors, gates and
-- mats the engine already takes.
--
-- The step-onto kinds are rare: the Entralink's copies of Unova (type 6,
-- zones 289..316 -- the Marvelous Bridge copy Z303 is left only by its two
-- deck warps, (14,33) west to Route 16 and (161,33) east to Route 15) and the
-- sand that drops the player a floor (type 5: Relic Castle Z081..Z087, and
-- Opelucid Gym Z121's).
--
-- A landing never takes the warp it lands on: the check runs on a step's end,
-- and a warp arrival is not a step.

local W = {}

W.STEP_TYPES = { [0] = true, [5] = true, [6] = true }

-- the warp def a step onto (cx, cy) takes on this BW map, or nil
function W.stepWarpAt(map, cx, cy)
  local def = map and map.def
  if not (def and def.gen5 and map.warpAtCell) then return nil end
  local w = map:warpAtCell(cx, cy)
  local wd = w and (w.def or w)
  local t = wd and tonumber(wd.transition)
  -- A RECORD WITH NO DESTINATION (zone 0xFFFF) IS ONLY A LANDING SPOT: Opelucid
  -- Gym Z121's warp 3 at (26,45), where warp 2's lift sets the player down,
  -- is type 5 with zone 0xFFFF. Taken, it sent the player to "Z65535" (the
  -- resolver's fallback: home); a walk across that tile must stay a walk.
  if wd and tonumber(wd.destHeader) == 0xFFFF then return nil end
  if t and W.STEP_TYPES[t] then return wd end
  return nil
end

return W
