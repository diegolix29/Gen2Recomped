-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S MOVEMENT TYPES ARE PLATINUM'S, row for row.
--
-- BW is not decompiled; what follows was READ FROM THE ROM (Black, USA/EUR,
-- field overlay 21 loaded at 0x02187F00, decompressed; scratch dumps in
-- scratch_claude/bw_npc_move/ovl and the scans in scratch_claude/movetypes):
--
--   * THE TYPE TABLE is at 0x021D5E04: 85 pointers to the same five-word
--     rows Platinum's Unk_020EE3A8 points at ({ id, init, move, delete,
--     return }), entry 47 NULL. Rows 0..46 and 48..67 carry Platinum's ids
--     (0, 1, 2, 3 ... then 0x33..0x36 for the disguises, 0x37..0x42 for the
--     gym types) and Platinum's sharing of callbacks: one move callback for
--     2 / 6..13 / 45 / 46 (look), one for 3 / 4 / 5 / 67 (wander), one for
--     14..17 (fixed), one for 18 / 19 (rotate), one for 21..36 and another
--     for 37..44 (routes), 20 its own.
--   * THE INIT ARGUMENTS are Platinum's, every one: the wanders pass
--     (WALK_NORMAL 12, list 11 / 12 / 13, mode 0) and 67 (12, 13, 2); the
--     looks lists 0..10; the fixed directions 0..3; the rotations 2 / 3; the
--     routes (2, axis, list 14..37) with the same axis per type.
--   * THE DATA the callbacks read is Platinum's: the timer list
--     { 16, 32, 48, 64 } at 0x021D4FA4, the 24-frame rotate hold (cmp #24 in
--     the rotate callback at 0x0219A5E0), the direction lists by id at
--     0x021D50F8 (identical to Unk_020EEB08, terminated by 9 rather than -1),
--     the running-look type list { 2, 6..13, 45, 46, 18, 19 } at 0x021D4FE8.
--   * THE RANGES are the record's halfwords +20 / +22, as on Gen 4: over
--     Black's 2,269 NPCs every wanderer carries 1/1, 2/2, 3/3 ... there and the
--     routes their rectangles (4/4, 2/3 ...), while +14 is the trainers'
--     sight range. Gen5Events reads them since this module was written
--     (`gen5Range`); a cache imported before then has the sight pair in
--     movementRangeX / Y, which is not a range, so those objects keep 0 / 0
--     -- they turn on the spot -- until the version is imported again.
--
-- INFERRED, NOT READ: the bodies of the move callbacks were not disassembled
-- line by line. That they are Platinum's is inferred from the identical
-- table shape, init arguments, data tables and callback sharing above.
--
-- NOT RUN HERE: 69..84 are the RAIL types (0x45..0x54; every object using
-- one sits on a rail, record +24 == 1), 68 (0x44) is unidentified, and
-- 48 / 50 / 51..54 are the follower and disguise rows as on Gen 4.

local M = {}

-- the Gen 4 row a BW type runs as, or nil
function M.gen4Row(typeId)
  local t = tonumber(typeId)
  if not t or t < 0 or t > 67 or t == 47 then return nil end
  return t
end

-- the wander box, honest about an old cache
function M.ranges(def)
  if def and def.gen5Range then
    return def.movementRangeX or 0, def.movementRangeY or 0
  end
  return 0, 0
end

return M
