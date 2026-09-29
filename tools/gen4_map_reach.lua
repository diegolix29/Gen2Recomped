-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_map_reach.lua -- WHERE the unlowered opcodes are, not how many.
--
-- tools/gen4_coverage_check.lua ranks the unlowered tail by how often each
-- opcode OCCURS, and that ranking is dominated by one room: 146 of the top
-- entries are `callbattletowerfunction`, which is one building behind one door
-- nobody has to open. A player walking from Twinleaf to the Elite Four never
-- meets it.
--
-- THE USEFUL QUESTION IS HOW MANY MAPS AN OPCODE REACHES, and it produces a
-- different order. `finishnpctrade` occurs eleven times -- far down the
-- occurrence list -- and sits on FOUR maps, one of which is OREBURGH CITY, the
-- third town. An occurrence count says "rare"; a map count says "on the road".
--
-- It also reports the other way round: which maps have gaps at all, worst
-- first, with the opcodes each one is missing. That is the list to read when a
-- player says a scene did nothing.
--
-- WHAT IT IS NOT: a pass/fail check. There is no floor to hold here -- the
-- tail is work that has not been done, and a number that only goes down is not
-- something to assert. It prints; the checks assert.
--
-- A MAP'S SCRIPT FILE IS NOT ONLY ITS OWN. Several maps share a member of
-- scr_seq, and a member holds every block in it whether that map runs it or
-- not -- so a gap listed against a map is a gap in the file that map's scripts
-- live in. That is the honest reading and it is still the right one for the
-- question: an opcode in that file is one the game can reach from there.
--
-- Run:  texlua tools/gen4_map_reach.lua <rom path> <cache dir>

local romPath, cacheDir = arg and arg[1], arg and arg[2]
if not (romPath and cacheDir) then
  io.stderr:write("usage: texlua tools/gen4_map_reach.lua <rom path> <cache dir>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local KEEP = {
  ["src.script.Gen4ScriptVM"] = true, ["src.script.Gen4Commands"] = true,
  ["src.import.Gen4ScriptOps"] = true, ["src.import.Gen4ScriptBands"] = true,
  ["src.import.Gen4Movement"] = true, ["src.import.Gen4Script"] = true,
  ["src.import.NdsRom"] = true, ["src.import.NarcArchive"] = true,
}
local shared = { meta = {} }
local quiet = setmetatable({}, { __index = function() return function() end end })
local inert = setmetatable({}, { __index = function() return function() end end })
table.insert(package.searchers, 1, function(name)
  if KEEP[name] then return nil end
  if name == "src.script.Commands" then return function() return shared end end
  if name == "src.core.Logger" then return function() return quiet end end
  if name:sub(1, 4) ~= "src." then return nil end
  return function() return inert end
end)

local VM = require("src.script.Gen4ScriptVM")
local Script = require("src.import.Gen4Script")
local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")

-- THE SAME CANARY gen4_seam_check.lua CARRIES, and for the same reason: that
-- one spent its whole life grading a snapshot of the lowering at an absolute
-- path, and nothing in its output could have said so. Comparing the bytes of
-- the file `VM.lower` loaded from against the copy beside this tool is what
-- makes the report a report about THIS tree.
local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
do
  local loadedFrom = (debug.getinfo(VM.lower, "S").source or ""):gsub("^@", "")
  local beside = (root ~= "" and root or "./") .. "../src/script/Gen4ScriptVM.lua"
  local a, b = readAll(loadedFrom), readAll(beside)
  if not (a and b and a == b) then
    io.write("!! the lowering that loaded is not the one beside this tool\n")
    io.write("     loaded: " .. loadedFrom .. "\n     beside: " .. beside .. "\n")
    os.exit(1)
  end
end
assert(VM.lowered("gotoif"), "canary: gotoif must be lowered")
assert(not VM.lowered("gen2recomped_no_such_command"),
       "canary: VM.lowered must be able to answer NO")

local headers = assert(loadfile(cacheDir .. "/gen4_map_headers.lua"))()
local rom = assert(NdsRom.open(romPath))
local arc = assert(Narc.parse(assert(rom:read("/fielddata/script/scr_seq.narc"))))

-- One script member, walked the way the extractor builds its pool: every entry
-- point plus every block a jump reaches.
local cache = {}
local function member(m)
  if cache[m] then return cache[m] end
  local r = { total = 0, missing = 0, ops = {} }
  local bytes = arc:get(m)
  if bytes and #bytes >= 6 then
    local queue, seen = {}, {}
    for _, at in ipairs(Script.entries(bytes)) do
      if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
    end
    local i = 1
    while i <= #queue do
      local at = queue[i]; i = i + 1
      for _, op in ipairs(Script.decode(bytes, at) or {}) do
        r.total = r.total + 1
        local name = op.name or ("?%03X"):format(op.op or 0)
        if not VM.lowered(name) then
          r.missing = r.missing + 1
          r.ops[name] = (r.ops[name] or 0) + 1
        end
        local t = op.target
        if t and t >= 1 and t <= #bytes and not seen[t] then
          seen[t] = true; queue[#queue + 1] = t
        end
      end
    end
  end
  cache[m] = r
  return r
end

local maps, where, occurs = {}, {}, {}
local rows, walked, withGaps = {}, 0, 0
for id = 0, 600 do
  local h = headers[id]
  if h and h.scripts then
    walked = walked + 1
    local r = member(h.scripts)
    if r.missing > 0 then withGaps = withGaps + 1 end
    rows[#rows + 1] = { id = id, name = h.internalName, label = h.label,
                        total = r.total, missing = r.missing, ops = r.ops }
    for name, n in pairs(r.ops) do
      maps[name] = maps[name] or {}
      maps[name][id] = true
      occurs[name] = (occurs[name] or 0) + n
      where[name] = where[name] or {}
      where[name][h.label or "?"] = true
    end
  end
end
rom:close()

io.write(("\n%d maps walked, %d have at least one unlowered instruction\n\n")
         :format(walked, withGaps))

local ranked = {}
for name, set in pairs(maps) do
  local c, ls = 0, {}
  for _ in pairs(set) do c = c + 1 end
  for l in pairs(where[name]) do ls[#ls + 1] = l end
  table.sort(ls)
  ranked[#ranked + 1] = { name = name, maps = c, n = occurs[name], where = ls }
end
table.sort(ranked, function(a, b)
  if a.maps ~= b.maps then return a.maps > b.maps end
  if a.n ~= b.n then return a.n > b.n end
  return a.name < b.name
end)

io.write("unlowered opcodes, ranked by HOW MANY MAPS THEY REACH:\n")
for i = 1, math.min(30, #ranked) do
  local r = ranked[i]
  local w = table.concat(r.where, "; ")
  if #w > 74 then w = w:sub(1, 71) .. "..." end
  io.write(("  %-42s %3d maps  x%-4d %s\n"):format(r.name, r.maps, r.n, w))
end

table.sort(rows, function(a, b)
  if a.missing ~= b.missing then return a.missing > b.missing end
  return a.id < b.id
end)
io.write("\nmaps with the most unlowered instructions:\n")
for i = 1, math.min(20, #rows) do
  local r = rows[i]
  if r.missing == 0 then break end
  local list = {}
  for name, n in pairs(r.ops) do list[#list + 1] = name .. " x" .. n end
  table.sort(list)
  local w = table.concat(list, ", ")
  if #w > 96 then w = w:sub(1, 93) .. "..." end
  io.write(("  %-10s %-22s %4d/%-5d %s\n"):format(r.name, r.label or "?",
           r.missing, r.total, w))
end
io.write("\n")
