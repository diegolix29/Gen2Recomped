-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CASTELIA GYM'S HONEY WALLS (Black / White, zone 29; overlay 38, with
-- overlay 37 for its set-up). No decomp: read off the Black ROM.
--
-- Seven walls of wax cross the hive, each three cells wide. Overlay 38's
-- table at 0x21F4694 places them (fx32 centres): (32,17) (26,21) (38,21)
-- (20,25) (26,29) (38,29) (32,33). A step into one is the field's to judge
-- (ov21 0x218AF90 hands the cell ahead to ov38 0x21F3A88 when its attribute
-- says honey), and ov38 0x21F3A08 sorts the cell:
--   * the wall's CENTRE, with the wall's state 1 -- the player pushes
--     through (task 0x21F3B3C: one walk into the wax, one out of it);
--   * the centre with state 0, or either cell beside it -- the player bounces
--     off (tasks 0x21F407C / 0x21F3F40) and stays where they were.
-- (Only a player facing up or down is handed on at all, ov21 0x21A3050: the
-- walls lie across the hive.)
--
-- THE STATES. Ten switch "presses" sit in the gym's work (+0x20); 0x18D <n>
-- (the floor switches' scripts) sets press n, and a wall turns to 1 when both
-- of its presses are down (ov38 0x21F42BC: partner table 0x21F4628, wall
-- table 0x21F4632). The eight floor switches are coord events on the temp
-- vars 0x4000..0x4007, and each switch's script ends by setting its var, so
-- the vars stand for the presses: overlay 37 (0x21F3768, run by 0x18F with
-- those eight vars as the zone comes up) rebuilds the presses switch by
-- switch (var i -> presses at 0x21F3840) and opens every wall whose two
-- presses are down (0x21F3834); it sets the seventh wall, the entrance's, to
-- 1 outright.
--
-- THEY OUTLAST THE VISIT. The temp vars are wiped on every zone change (ov10
-- 0x21589F4), and so is the gym's save block (ov20 0x2185B9C clears +4 ..
-- +0x83 for the zone it enters) -- but a switch's own animation task (ov38
-- 0x21F4200, 0x18C) also writes 1 to switch i's u16 at +0x84 + 2i, which
-- nothing clears, and overlay 37 reads those eight words back on entry and
-- sets each pressed switch's var to 1 again. So a wall once opened stays open
-- through leaving the hive and coming back, and a pressed switch stays down.
-- Here that record is `save.bwCasteliaSwitches`, kept in step with the vars.
--
-- Before this the walls were made passable at import (Gen5Field), and every
-- wall's centre let the player through with no switch pressed: Burgh could
-- be walked to straight from the door.

local G = {}

G.HEADER = 29

-- ov38 0x21F4694, wall i's centre cell
G.WALLS = { [0] = { 32, 17 }, { 26, 21 }, { 38, 21 }, { 20, 25 }, { 26, 29 }, { 38, 29 }, { 32, 33 } }
-- ov37 0x21F3840: switch var 0x4000 + i -> the presses it makes
G.VAR_PRESSES = { [0] = { 0 }, { 1 }, { 2 }, { 3, 4 }, { 5 }, { 6 }, { 7, 8 }, { 9 } }
-- ov37 0x21F3834: wall w's two presses (one switch twice: a single)
G.WALL_PRESSES = { [0] = { 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 6 }, { 7, 7 }, { 8, 9 } }
-- ov37 0x21F37F2: the entrance wall is always soft
G.ALWAYS_OPEN = 6

local function vars(save) return (save and save.gen4Vars) or {} end

-- the +0x84 record and the vars, each made to hold what the other does: a
-- switch's script sets its var (recorded), a fresh visit finds the record
-- (its var set again, as overlay 37 does on entry)
function G.sync(save)
  if not save then return end
  save.gen4Vars = save.gen4Vars or {}
  local v = save.gen4Vars
  local rec = save.bwCasteliaSwitches
  for i = 0, 7 do
    local k = tostring(i)
    if (tonumber(v[0x4000 + i]) or 0) ~= 0 then
      save.bwCasteliaSwitches = save.bwCasteliaSwitches or {}
      rec = save.bwCasteliaSwitches
      rec[k] = 1
    elseif rec and rec[k] == 1 then
      v[0x4000 + i] = 1
    end
  end
end

function G.presses(save)
  G.sync(save)
  local v, pressed = vars(save), {}
  for i = 0, 7 do
    if (tonumber(v[0x4000 + i]) or 0) ~= 0 then
      for _, p in ipairs(G.VAR_PRESSES[i]) do pressed[p] = true end
    end
  end
  return pressed
end

function G.wallOpen(save, w)
  if w == G.ALWAYS_OPEN then return true end
  local need = G.WALL_PRESSES[w]
  if not need then return false end
  local pressed = G.presses(save)
  return pressed[need[1]] == true and pressed[need[2]] == true
end

-- the collision rule: a shut wall's centre is wax (true); an open one, and
-- every other cell, is the grid's to say (nil). The cells beside a centre
-- are solid in the grid already.
function G.collides(save, x, z)
  for w = 0, 6 do
    local c = G.WALLS[w]
    if c[1] == x and c[2] == z then
      if G.wallOpen(save, w) then return nil end
      return true
    end
  end
  return nil
end

function G.attach(def)
  if not (def and def.gen5 and def.header == G.HEADER) then return end
  -- (the save is read at the step: a continue replaces it)
  def.gen4CollisionHook = function(_, x, z)
    local Game = package.loaded["src.core.Game"]
    return G.collides(Game and Game.save, x, z)
  end
end

-- on the hive's entry, after the zone change has wiped the temps (the
-- transition script's 0x18F: overlay 37 sets the pressed switches' vars)
function G.onEntered(save, def)
  if def and def.gen5 and def.header == G.HEADER then G.sync(save) end
end

return G
