-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ICIRRUS GYM (Black / White, zone 114; Brycen). No decomp: read off the
-- Black ROM (White's grid, rails and scripts are byte-identical).
--
-- The rink is ice (src/world/Gen5Ice.lua) on three floors -- the door's at
-- height 0, the east one at 48, the west one at 96, Brycen's dais at 112 --
-- and its curved chutes and bridges are RAILS (rail file /a/0/7/9 #2, its
-- attribute file #19), a second movement system laid over the grid:
--
-- READ FROM CODE (ov21):
--   * a rail's cells carry their own attributes (0x21BB13C: per line, a
--     width x length grid of u32s). Here every chute and bridge is ice --
--     0x18, and the slide tiles 0xA5 / 0xA4 (the chutes' bends) and 0xA7 /
--     0xA6 / 0xA8 (dips) whose handlers (table 0x21D8AB8) all end in the ice
--     slide 0x21A6908 -- with 0xA3 at each end and a blocked cell beyond, and
--     the chutes one lane wide (the side lanes blocked). So a rail is ridden
--     to its far 0xA3 in one slide, and there the player stands.
--   * grid -> rail (0x21A6F5C): standing on a grid 0xA3 cell, a press whose
--     grid cell ahead is blocked enters the rail found there (0x21A71E4) --
--     the bridges' and the rim's ends.
--   * rail -> grid (0x21A7010 / 0x21A7198): on a rail 0xA3 whose rail cell
--     ahead is blocked, a press steps off onto the grid cell one tile that way
--     (0x2164208 adds 0x10000) when it is open; the other way along the rail
--     slides back.
--   * the CHUTES are entered by the gym: each one's start is a coordinate
--     trigger whose script runs 0x195 <n> (ov45 0x21F38C4), which switches the
--     player onto the rail under them (0x21A6DC4 -> 0x21A71E4 / 0x21A70D0)
--     only while ride n's gate holds -- switch group a at state b (ov45's
--     table 0x21F3B60: (0,0) (0,1) (1,0) (1,1) (2,0) (2,0) (2,1) (2,1), a
--     group's state in the gym save block, kept here as its var 0x4001 + a,
--     which the switch scripts flip with it). A shut gate leaves the cell
--     plain floor.
--   * the GRID under the rails (chunks 527 / 605 / 606 / 607): the bridges'
--     ends are walls (x 30 and 44 on rows 47..49, x 26 and 40 on rows
--     37..39) with rail-only ice between, the rim down the west side is wall,
--     and row 61 west of the door is ice. Gen5Field opened every rail that
--     does not start at a trigger as plain ground (a walkway), which put a
--     floor down the rim and across the bridges and took row 61's ice away;
--     `restore` puts the cartridge's cells back.
--
-- With the grid, the ice and the chutes as the cartridge has them the gym
-- has one way up (an offline search: all three switches and all eight
-- chutes, both bridges); with the walkways it had none, and without the ice
-- it was a floor Brycen could be walked to from the door.

local M = {}

M.HEADER = 114

-- the chutes, from their trigger cell (0xA3 at the rail's start, where the
-- coordinate trigger sits) to their far 0xA3: the direction that rides it,
-- the far cell, the direction of travel there, and the cells between as
-- steps (the rail's lines and bends, rasterised)
M.RIDES = {
  [0] = { x = 17, y = 60, go = "up", toX = 11, toY = 58, arrive = "down", path = "UUUUULULLLLDLDDD" },
  [1] = { x = 22, y = 53, go = "left", toX = 22, toY = 47, arrive = "right", path = "LLLULUUURURURR" },
  [2] = { x = 60, y = 44, go = "left", toX = 59, toY = 49, arrive = "right", path = "LLLLDDDDRDRR" },
  [3] = { x = 54, y = 39, go = "down", toX = 48, toY = 39, arrive = "up", path = "DDDLDLLLULULUU" },
  [4] = { x = 12, y = 34, go = "right", toX = 13, toY = 40, arrive = "left", path = "RRRRDRDDDDLDLLL" },
  [5] = { x = 16, y = 38, go = "up", toX = 10, toY = 37, arrive = "down", path = "UUUUULLLLLDLDDD" },
  [6] = { x = 18, y = 29, go = "down", toX = 24, toY = 29, arrive = "up", path = "DDDRRURRRURU" },
  [7] = { x = 22, y = 32, go = "left", toX = 21, toY = 26, arrive = "right", path = "LLLLULUUURURURR" },
}
-- the rails entered from a grid 0xA3: the bridges (three lanes each, both
-- ways) and the rim from Brycen's floor down to the door (one way: its foot
-- has no 0xA3 on the grid)
M.ENTRIES = {}
for _, r in ipairs({ 47, 48, 49 }) do
  M.ENTRIES["29," .. r] = { go = "right", toX = 45, toY = r, path = ("R"):rep(16) }
  M.ENTRIES["45," .. r] = { go = "left", toX = 29, toY = r, path = ("L"):rep(16) }
end
for _, r in ipairs({ 37, 38, 39 }) do
  M.ENTRIES["25," .. r] = { go = "right", toX = 41, toY = r, path = ("R"):rep(16) }
  M.ENTRIES["41," .. r] = { go = "left", toX = 25, toY = r, path = ("L"):rep(16) }
end
M.RIM = { go = "left", toX = 15, toY = 61, arrive = "right",
  path = "LLLDLDLDDDLDDDDLDDDDDDLDDDDDDDDDDRDDDDDRDDDDRDDRDDRRRDRRRRRRR" }
M.ENTRIES["9,22"] = M.RIM

local LETTER = { U = "up", D = "down", L = "left", R = "right" }
local BACK = { U = "D", D = "U", L = "R", R = "L", up = "down", down = "up", left = "right", right = "left" }

local function reversed(path)
  local t = {}
  for i = #path, 1, -1 do t[#t + 1] = BACK[path:sub(i, i)] end
  return table.concat(t)
end

-- the grid's own cells under the rails (see the header): true = a wall
function M.walled(x, y)
  if x <= 8 then return true end
  if y >= 47 and y <= 49 and x >= 30 and x <= 44 then return true end
  if y >= 37 and y <= 39 and x >= 26 and x <= 40 then return true end
  return nil
end

function M.restore(def)
  if not (def and def.gen5 and def.header == M.HEADER) then return end
  def.gen4CollisionHook = function(_, x, y) return M.walled(x, y) end
  local cells = def.behaviorCells
  local w = def.width or 64
  if type(cells) == "string" and not def.gen5IcirrusIce then
    local t = {}
    for i = 1, #cells do t[i] = cells:sub(i, i) end
    for x = 9, 14 do
      local i = 61 * w + x + 1
      if t[i] then t[i] = string.char(0x18) end
    end
    def.behaviorCells = table.concat(t)
    def.gen5IcirrusIce = true
  end
end

-- the gate of ride n: its switch group's state (var 0x4001 + group)
function M.gateOpen(def, save, n)
  local gates = def and def.gen5RailGates or {}
  local gate = gates[n] or gates[tostring(n)]
  if not gate then return true end
  local vars = save and save.gen4Vars or {}
  local v = vars[0x4001 + gate.group] or vars[tostring(0x4001 + gate.group)] or 0
  return ((v ~= 0) and 1 or 0) == gate.state
end

local function here(ow)
  local def = ow and ow.map and ow.map.def
  return def and def.gen5 and def.header == M.HEADER
end

-- the rail state the player is left in at (x, y): which press rides on
local function railAt(ow, x, y, go, path, toX, toY, after)
  ow.gen5Rail = { map = ow.map, x = x, y = y, go = go, path = path, toX = toX, toY = toY, after = after }
end

local function startRide(ow, n)
  local r = M.RIDES[n]
  railAt(ow, r.x, r.y, r.go, r.path, r.toX, r.toY, function()
    railAt(ow, r.toX, r.toY, BACK[r.arrive], reversed(r.path), r.x, r.y, function() startRide(ow, n) end)
  end)
end

-- 0x195 <n>, run by the chute's trigger: onto the rail under the player
function M.force(ow, save, n)
  if not here(ow) then return false end
  local r = M.RIDES[n]
  local p = ow.player
  if not (r and p and p.cellX == r.x and p.cellY == r.y) then return false end
  if not M.gateOpen(ow.map.def, save, n) then return false end
  startRide(ow, n)
  return true
end

-- carried along `path` from where the player stands; `after` once there
function M.slide(ow, path, after)
  local p = ow.player
  ow.iceSlide = nil
  for i = 1, #path do
    local last = i == #path
    ow:scriptMove(p, LETTER[path:sub(i, i)], 1, last and function()
      if after then after() end
    end or nil, false, require("src.world.Gen5Ice").RATE)
  end
end

-- a press while standing still: true when the rail took it
function M.press(ow, dir)
  if not here(ow) then ow.gen5Rail = nil return false end
  local p = ow.player
  if not p or p.moving or #(ow.scriptMoves or {}) > 0 then return false end
  local r = ow.gen5Rail
  if r and (r.map ~= ow.map or r.x ~= p.cellX or r.y ~= p.cellY) then r, ow.gen5Rail = nil, nil end
  if r then
    -- on a rail's 0xA3: along it slides; any other way is the grid's step
    -- off (taken by the ordinary walk when the cell is open)
    if dir ~= r.go then return false end
    ow.gen5Rail = nil
    M.slide(ow, r.path, r.after)
    return true
  end
  local e = M.ENTRIES[p.cellX .. "," .. p.cellY]
  if e and e.go == dir and p.facing == dir then
    -- (a bridge's far end is a grid 0xA3 of its own; the rim's foot is not,
    -- so the player is left on the rail there, and back up it slides)
    local sx, sy = p.cellX, p.cellY
    M.slide(ow, e.path, e.arrive and function()
      railAt(ow, e.toX, e.toY, BACK[e.arrive], reversed(e.path), sx, sy, nil)
    end or nil)
    return true
  end
  return false
end

return M
