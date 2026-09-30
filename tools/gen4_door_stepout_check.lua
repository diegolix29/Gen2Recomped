-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the tile under a Platinum warp arrival is NOT what
-- decides whether the player steps out of the doorway, and that the engine no
-- longer asks it.
--
-- Reported from play: "ive noticed when walking out of doors in platinum it
-- doesnt make me walk one block out of the door i exit and im standing in the
-- doorway".  Third appearance of one bug: a Game Boy-era question asked of Gen 4
-- data.  `isDoorTileCell` compared the arrival cell against the tileset's door
-- list, which on this cartridge is Gen4Behaviors.group("door") = { 0x69 DOOR }.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: the count below is ZERO, and a count
-- that can only come out zero is not a measurement.  Section 2 is the control --
-- the same join, the same code path, one behaviour swapped into the door list --
-- and it must come out non-zero or section 1 proved nothing.  Run it and watch
-- both numbers, not just the first.
--
-- It reads the arrival cell through MapLoader.resolveBlocks rather than
-- reimplementing the origin carve, because 84 of Sinnoh's maps share layout 0 --
-- the 960x960 region grid -- and indexing that by a map-local coordinate is how
-- the first draft of this measurement produced 293 "blocked" arrivals that were
-- nothing but a wrong origin.
--
-- Usage: texlua tools/gen4_door_stepout_check.lua [<dataset dir>]
--   dataset dir defaults to G:/Gen2Recomped/platinum/data/generated

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local dir = arg[1] or "G:/Gen2Recomped/platinum/data/generated"
dir = dir:gsub("[/\\]*$", "") .. "/"

local Gen4Behaviors = require("src.import.Gen4Behaviors")
local Gen4Maps      = require("src.import.Gen4Maps")
local MapLoader     = require("src.world.MapLoader")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local function load_(name)
  local chunk, err = loadfile(dir .. name)
  if not chunk then
    io.stderr:write(("could not load %s%s: %s\n"):format(dir, name, tostring(err)))
    os.exit(2)
  end
  return chunk()
end

local maps    = load_("maps.lua")
local layouts = load_("map_layouts.lua")
local data    = { map_layouts = layouts }

local byId, nGen4 = {}, 0
for _, m in pairs(maps) do
  if type(m) == "table" and m.generation == 4 and m.id then
    byId[m.id] = m
    nGen4 = nGen4 + 1
  end
end

-- The arrival cell, read exactly as Map:blockAt would read it: the engine's own
-- carve first, then the low byte of the two-byte cell.
local function behaviourAt(m, x, y)
  MapLoader.resolveBlocks(data, m)
  if type(m.blocks) ~= "string" then return nil end
  local w, h = m.width, m.height
  if not (w and h) or x < 0 or y < 0 or x >= w or y >= h then return nil end
  return m.blocks:byte((y * w + x) * 2 + 1)
end

-- Every warp in the cartridge, joined destMap/destWarp to the cell it lands on.
local arrivals, unresolved = {}, 0
local nWarps = 0
for _, m in pairs(byId) do
  for _, w in ipairs(m.warps or {}) do
    nWarps = nWarps + 1
    local d = w.destMap and byId[w.destMap]
    local dw = d and d.warps and d.warps[w.destWarp]
    local b = dw and behaviourAt(d, dw.x, dw.y)
    if b then arrivals[#arrivals + 1] = b else unresolved = unresolved + 1 end
  end
end

local function countAgainst(list)
  local want, n = {}, 0
  for _, v in ipairs(list) do want[v] = true end
  for _, b in ipairs(arrivals) do if want[b] then n = n + 1 end end
  return n
end

-- ---------------------------------------------------------------------------
section("0. the join itself")
-- ---------------------------------------------------------------------------
io.write(("  gen4 maps %d, warps %d, arrival cells read %d, unresolved %d\n")
         :format(nGen4, nWarps, #arrivals, unresolved))
ok(nGen4 == 593, "expected 593 Gen 4 map headers, found %d", nGen4)
ok(nWarps == 1213, "expected 1,213 warps in Sinnoh, found %d", nWarps)
-- Six warps name a destination this dataset has no map for; that is a separate
-- gap and is asserted as a ceiling so it cannot quietly grow.
ok(unresolved <= 6, "%d warps could not be joined to an arrival cell (was 6)",
   unresolved)
ok(#arrivals > 1000, "only %d arrival cells read; the join is not working",
   #arrivals)

-- ---------------------------------------------------------------------------
section("1. the door list matches nothing")
-- ---------------------------------------------------------------------------
local doorList = Gen4Behaviors.group("door")
local names = {}
for _, v in ipairs(doorList) do
  names[#names + 1] = ("0x%02X %s"):format(v, Gen4Behaviors.name(v) or "?")
end
io.write(("  doorTiles = { %s }\n"):format(table.concat(names, ", ")))
local hits = countAgainst(doorList)
io.write(("  arrival cells that list would call a door: %d of %d\n")
         :format(hits, #arrivals))
ok(hits == 0,
   "%d arrival cells carry a door behaviour -- if this is no longer zero the "
   .. "Gen 4 gate in OverworldController may be able to use the tile after all",
   hits)

-- ---------------------------------------------------------------------------
section("2. THE CONTROL -- the same join, with a behaviour that does occur")
-- ---------------------------------------------------------------------------
-- WARP_ENTRANCE_SOUTH is the exit mat inside a building: walk south onto it and
-- you leave.  If swapping it into the list does not move the count, section 1
-- was reading nothing and its zero meant nothing.
local mat = nil
for v = 0, 255 do
  if Gen4Behaviors.name(v) == "WARP_ENTRANCE_SOUTH" then mat = v break end
end
ok(mat ~= nil, "WARP_ENTRANCE_SOUTH is not in the behaviour table")
if mat then
  local planted = countAgainst({ mat })
  io.write(("  planting 0x%02X WARP_ENTRANCE_SOUTH in the list: %d of %d\n")
           :format(mat, planted, #arrivals))
  ok(planted > 0,
     "the control found 0 arrivals on WARP_ENTRANCE_SOUTH, so the join reads "
     .. "no behaviours and section 1 proved nothing")
end

-- ---------------------------------------------------------------------------
section("3. why the tile could not answer even if the list were right")
-- ---------------------------------------------------------------------------
-- Map:cellBehaviour opens `if not self.def.collisionCells then return nil end`.
-- Gen4Maps.mapDef is where a Sinnoh map def is made, and it carries the
-- behaviour in `blocks` instead, so that guard closes on every Gen 4 cell.
local chunk = { permissions = string.rep("\0\0", Gen4Maps.CHUNK * Gen4Maps.CHUNK) }
local def = Gen4Maps.mapDef({ width = 1, height = 1, maps = { 0 } },
                            function() return chunk end)
ok(def ~= nil, "Gen4Maps.mapDef returned nil for a one-chunk matrix")
if def then
  ok(def.collisionCells == nil,
     "Gen4Maps.mapDef now emits collisionCells -- cellBehaviour can answer for "
     .. "Gen 4, so the fourteen behaviour branches in Map.lua are live and each "
     .. "wants a look")
  ok(type(def.blocks) == "string",
     "Gen4Maps.mapDef emitted no blocks string")
end

-- ---------------------------------------------------------------------------
section("4. the engine asks the facing instead")
-- ---------------------------------------------------------------------------
-- ov5_021D5020 / ov5_021D5150 gate the step on PlayerAvatar_GetFacingDir == 1
-- (DIR_SOUTH) and read no tile at all.  Pinned here so a later edit that puts
-- the tile back in charge for Gen 4 fails this file rather than the play-test.
local f = io.open(root .. "../src/world/OverworldController.lua", "rb")
      or io.open("src/world/OverworldController.lua", "rb")
ok(f ~= nil, "could not open src/world/OverworldController.lua")
if f then
  local text = f:read("*a")
  f:close()
  ok(text:find('stepsOut = self.player.facing == "down"', 1, true) ~= nil,
     "the Gen 4 step-out gate is gone: no facing test in OverworldController")
  -- NOT `find("if GameVersion.isGen4() then")`: that line appears eight other
  -- times in this file, so the assertion could not fail and would have said
  -- nothing.  Pin the whole construct instead, in order, with the tile arm as
  -- its alternative -- and pin it with a PLAIN find, because `isGen4()` inside
  -- a Lua pattern is a position capture, not a literal, and the first draft of
  -- this line failed against the correct file for that reason alone.
  local flat = text:gsub("\r\n", "\n")
  local gate = table.concat({
    'if GameVersion.isGen4() then',
    '        stepsOut = self.player.facing == "down"',
    '      else',
    '        stepsOut = self.map:isDoorTileCell(self.player.cellX, self.player.cellY)',
    '      end',
  }, "\n")
  ok(flat:find(gate, 1, true) ~= nil,
     "the step-out gate is no longer the two-armed Gen 4 / tile construct")
  -- the older generations must still ask the tile
  ok(text:find("stepsOut = self.map:isDoorTileCell(", 1, true) ~= nil,
     "the pre-Gen 4 arm no longer calls isDoorTileCell -- Gen 1, 2 and 3 lost "
     .. "their step-out")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
