-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- tools/gen4_distworld_check.lua -- the seventh standing check.
--
-- The other six ask whether a SCRIPT is right.  This one asks whether the
-- Distortion World's runtime floor was read right, and it exists because every
-- number in that read is found by searching rather than by indexing: four
-- overlay tables located by their map-id fingerprints, one located by a
-- self-indexing run, and ten map files whose section widths are confirmed by
-- arithmetic.  A search that silently lands on the wrong run returns a table of
-- plausible nonsense, which is exactly the failure a coverage figure cannot see.
--
-- Every expectation below is a MEASURED value from this project's cartridge,
-- and each one is a different kind of claim:
--
--   * lengths that must be EXACT (4 + 12 * 10 == the map-info member) --
--     arithmetic, so a wrong record width cannot pass;
--   * table sites found by FINGERPRINT, checked by row counts that no other
--     run in the overlay produces;
--   * the shuttle PAIRING, which is the only structural claim here: 18 of 34
--     moving platforms pair across floors at identical (x, z), they form 9
--     symmetric pairs, and all 16 that do not pair are on B2F;
--   * and the one that makes the whole thing usable -- all 18 shuttle ends
--     land on a WALKABLE cell of their own map's permission grid.
--
-- Run:  texlua tools/gen4_distworld_check.lua <rom path>

local romPath = arg and arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_distworld_check.lua <rom path>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local DW = require("src.import.Gen4DistWorld")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then
    io.write(("  ok    %-52s %s\n"):format(what, tostring(got)))
  else
    fails = fails + 1
    io.write(("  FAIL  %-52s got %s, expected %s\n")
      :format(what, tostring(got), tostring(want)))
  end
end

local rom = assert(NdsRom.open(romPath))

-- ------------------------------------------------------------------ the NARC
io.write("tw_arc.narc / tw_arc_attr.narc\n")
local mainArc = assert(Narc.parse(assert(rom:read(DW.MAIN_PATH))), "tw_arc.narc")
local attrArc = assert(Narc.parse(assert(rom:read(DW.ATTR_PATH))), "tw_arc_attr.narc")
ok(mainArc.count == 11, "tw_arc members", mainArc.count, 11)
ok(attrArc.count == 12, "tw_arc_attr members", attrArc.count, 12)

local infos, why = DW.mapInfo(mainArc:get(0))
ok(infos ~= nil, "map-info member parses", infos and #infos or why, "10 records")
if not infos then os.exit(1) end
ok(#infos == 10, "Distortion World maps", #infos, 10)

-- 578 is a map header in the same run and appears in NO Distortion World
-- table.  Indexing this file by `header - 573` would land one floor out from
-- B5F on, so the absence is checked rather than assumed.
local seen = {}
for _, i in ipairs(infos) do seen[i.header] = true end
ok(not seen[578], "map 578 absent (it is a spare, not a floor)", seen[578] and "present" or "absent", "absent")

local platforms, jumps, cameras, files = 0, 0, 0, 0
local byHeader = {}
for _, info in ipairs(infos) do
  local f, err = DW.mapFile(mainArc:get(info.fileIndex + 1))
  if f then
    files = files + 1
    byHeader[info.header] = { info = info, file = f }
    platforms = platforms + #f.platforms
    jumps = jumps + #f.jumps
    cameras = cameras + #f.cameras
  else
    io.write(("  FAIL  map %d: %s\n"):format(info.header, tostring(err)))
    fails = fails + 1
  end
  checks = checks + 1
end
ok(files == 10, "map files whose sections account for the member", files, 10)
ok(platforms == 10, "floating platforms", platforms, 10)
ok(jumps == 20, "floating-platform jump points", jumps, 20)
ok(cameras == 26, "camera-angle templates", cameras, 26)

-- Only four of the ten floors carry platforms at all; five carry none.  A
-- reader that treats an absent section as an error refuses half the dungeon.
local withPlatforms, withNone = 0, 0
for _, e in pairs(byHeader) do
  if #e.file.platforms > 0 then withPlatforms = withPlatforms + 1 end
  if #e.file.platforms == 0 and #e.file.jumps == 0 then withNone = withNone + 1 end
end
ok(withPlatforms == 5, "floors with at least one platform", withPlatforms, 5)
ok(withNone == 5, "floors with no platforms and no jump points", withNone, 5)

-- Every platform's kind must be one the attribute lookup can serve, and its
-- attribute id must exist.  A kind of 4 (INVALID) is a jump TARGET, never a
-- platform, so finding one here would mean the section is misaligned.
local grids, badKind, badAttr = {}, 0, 0
for i = 0, attrArc.count - 1 do
  local g, err = DW.attrGrid(attrArc:get(i))
  if not g then
    io.write(("  FAIL  attr %d: %s\n"):format(i, tostring(err)))
    fails = fails + 1
  end
  checks = checks + 1
  grids[i] = g
end
for _, e in pairs(byHeader) do
  for _, pl in ipairs(e.file.platforms) do
    if pl.kind < 0 or pl.kind >= DW.KIND_INVALID then badKind = badKind + 1 end
    if not grids[pl.attr] then badAttr = badAttr + 1 end
  end
end
ok(badKind == 0, "platforms with an unusable kind", badKind, 0)
ok(badAttr == 0, "platforms naming an absent attribute grid", badAttr, 0)

-- The attribute lookup, exercised over every platform's whole bounding box.
-- This is what catches a wrong `vertical`/`horizontal` formula: a transposed
-- lookup still returns words, just the wrong ones, and the count moves.
local passable = 0
for _, e in pairs(byHeader) do
  for _, pl in ipairs(e.file.platforms) do
    local b, g = pl.bounds, grids[pl.attr]
    for x = b.x, b.x + b.sizeX do
      for y = b.y, b.y + b.sizeY do
        for z = b.z, b.z + b.sizeZ do
          if DW.passable(DW.attrAt(pl, g, x, y, z)) then passable = passable + 1 end
        end
      end
    end
  end
end
ok(passable == 441, "passable cells over all ten platforms", passable, 441)

-- ---------------------------------------------------------------- overlay 9
io.write("overlay 9\n")
local bin, meta = rom:overlay(DW.OVERLAY)
ok(bin ~= nil, "overlay 9 readable", bin and #bin or "nil", 41856)
if not bin then os.exit(1) end
ok(#bin == 41856, "overlay 9 bytes", #bin, 41856)
ok(meta.ram == 0x02249960, "overlay 9 load address", ("0x%08X"):format(meta.ram), "0x02249960")

local EXPECT = {
  cast = { rows = 45, maps = 10 },
  events = { rows = 45, maps = 8 },
  movingPlatforms = { rows = 34, maps = 8 },
  simpleProps = { rows = 4, maps = 4 },
}
local tables = {}
for _, t in ipairs(DW.TABLES) do
  local at = DW.findTable(bin, meta.ram, t.maps)
  checks = checks + 1
  if not at then
    io.write(("  FAIL  table %-16s not found by fingerprint\n"):format(t.key))
    fails = fails + 1
  else
    tables[t.key] = DW.readTable(bin, meta.ram, at, t.maps, t.key)
    local n = 0
    for _, rows in pairs(tables[t.key]) do n = n + #rows end
    local want = EXPECT[t.key]
    ok(n == want.rows, ("%s rows"):format(t.key), n, want.rows)
    io.write(("        %-16s at +0x%05X over %d maps\n"):format(t.key, at, #t.maps))
  end
end

-- The four fingerprints must be DISTINCT sites.  Two tables resolving to the
-- same offset is the failure mode a prefix match produces, and it would leave
-- every row count plausible.
local sites, distinct = {}, 0
for _, t in ipairs(DW.TABLES) do
  local at = DW.findTable(bin, meta.ram, t.maps)
  if at and not sites[at] then sites[at] = true; distinct = distinct + 1 end
end
ok(distinct == 4, "distinct table sites", distinct, 4)

local eat, paths = DW.findElevatorPaths(bin)
ok(paths ~= nil, "elevator path table found", eat and ("+0x%05X"):format(eat) or "nil", "+0x09ED0")

-- Every command kind in every event must be a NAMED kind.  An unnamed number
-- here means the command list walked off its array, which is what a wrong
-- terminator looks like.
local totalCmds, unnamed = 0, 0
if tables.events then
  for _, rows in pairs(tables.events) do
    for _, ev in ipairs(rows) do
      for _, c in ipairs(ev.commands) do
        totalCmds = totalCmds + 1
        if type(c) ~= "string" then unnamed = unnamed + 1 end
      end
    end
  end
end
ok(totalCmds == 111, "event commands", totalCmds, 111)
ok(unnamed == 0, "event commands with an unnamed kind", unnamed, 0)

-- ------------------------------------------------------------- the shuttles
io.write("moving platforms\n")
if tables.movingPlatforms and paths then
  local shuttles, horizontal = DW.classify(tables.movingPlatforms, paths)
  ok(#shuttles == 18, "shuttle ends that pair across floors", #shuttles, 18)
  ok(#horizontal == 16, "platforms that do not pair", #horizontal, 16)

  -- All sixteen non-pairing platforms are on B2F.  That is the claim that says
  -- the two groups are real and not an artefact of the pairing test: if the
  -- test were merely failing, the failures would be spread.
  local offB2F = 0
  for _, h in ipairs(horizontal) do if h.map ~= 575 then offB2F = offB2F + 1 end end
  ok(offB2F == 0, "non-pairing platforms outside B2F", offB2F, 0)

  -- The 18 ends must form 9 SYMMETRIC pairs: for every A->B at (x,z) there is
  -- a B->A at the same (x,z).  A one-way lift would be a softlock, so this is
  -- checked rather than inferred from the count being even.
  local key = {}
  for _, s in ipairs(shuttles) do
    key[("%d|%d|%d|%d"):format(s.from, s.to, s.x, s.z)] = true
  end
  local unpaired = 0
  for _, s in ipairs(shuttles) do
    if not key[("%d|%d|%d|%d"):format(s.to, s.from, s.x, s.z)] then
      unpaired = unpaired + 1
      io.write(("        one-way: %s -> %s at (%d,%d)\n")
        :format(DW.FLOOR_NAMES[s.from] or s.from, DW.FLOOR_NAMES[s.to] or s.to, s.x, s.z))
    end
  end
  ok(unpaired == 0, "one-way shuttles", unpaired, 0)

  -- AND THE ONE THAT MAKES IT USABLE.  Each shuttle end is a world coordinate;
  -- subtract its floor's offsets and the result must be a walkable cell of
  -- that floor's own permission grid.  If it were not, the pairing would be a
  -- correct reading of a table the port still could not stand a player on.
  local matrices = Narc.parse(assert(rom:read("/fielddata/mapmatrix/map_matrix.narc")))
  local land = Narc.parse(assert(rom:read("/fielddata/land_data/land_data.narc")))
  local MATRIX = {
    [573] = 269, [574] = 270, [575] = 271, [576] = 272, [577] = 273,
    [579] = 275, [580] = 276, [581] = 277, [582] = 278, [583] = 279,
  }
  local gridCache = {}
  local function permission(header, lx, lz)
    local g = gridCache[header]
    if not g then
      local b = matrices:get(MATRIX[header])
      if not b then return nil end
      local w, h, hasHeaders, hasAltitude, nameLen = b:byte(1), b:byte(2), b:byte(3), b:byte(4), b:byte(5)
      local o = 5 + nameLen
      if hasHeaders ~= 0 then o = o + 2 * w * h end
      if hasAltitude ~= 0 then o = o + w * h end
      g = { w = w * 32, h = h * 32, cells = {} }
      for cy = 0, h - 1 do
        for cx = 0, w - 1 do
          local id = DW.u16(b, o + (cy * w + cx) * 2)
          local chunk = land:get(id)
          for ty = 0, 31 do
            for tx = 0, 31 do
              g.cells[(cy * 32 + ty) * g.w + (cx * 32 + tx)] = DW.u16(chunk, 16 + (ty * 32 + tx) * 2)
            end
          end
        end
      end
      gridCache[header] = g
    end
    if lx < 0 or lz < 0 or lx >= g.w or lz >= g.h then return nil end
    return g.cells[lz * g.w + lx]
  end

  local walkable, pads = 0, 0
  for _, s in ipairs(shuttles) do
    local e = byHeader[s.from]
    if e then
      local v = permission(s.from, s.x - e.info.offsetX, s.z - e.info.offsetZ)
      if v and v < DW.COLLISION_BIT then
        walkable = walkable + 1
        if v % 0x100 == 8 then pads = pads + 1 end
      end
    end
  end
  ok(walkable == 18, "shuttle ends on a walkable map cell", walkable, 18)
  ok(pads == 14, "shuttle ends marked CAVE_FLOOR (a lift pad)", pads, 14)
else
  io.write("  FAIL  moving platforms or elevator paths missing\n")
  fails = fails + 1
end

rom:close()
io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
