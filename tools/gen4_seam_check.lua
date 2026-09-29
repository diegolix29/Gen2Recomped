-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_seam_check.lua -- the seam ABOVE the commands.
--
-- Lower every block in the cartridge and check two things about every row the
-- lowering emits:
--
--   1. THE VERB RESOLVES. An emitted name with no handler logs
--      "unknown command 'x' (skipped)" and the row does nothing at all. 84,519
--      rows, 150 distinct verbs, and all 150 must answer.
--
--   2. THE ARGUMENT COUNT MATCHES. debug.getinfo(fn,"u").nparams gives a Lua
--      function's declared parameter count, so a lowering that hands over more
--      operands than the command takes is visible. Zero-parameter handlers
--      (stubs, waits, `label`) ignore their arguments on purpose and are not
--      faults; a command with a real signature being handed an extra operand is.
--
-- THIS IS HOW THE `fadescreen` BUG WAS FOUND. It reported
--
--     g4_fade  passes 2 arg(s), takes 1   x736 rows  [EXTRA DROPPED]
--
-- and the operand being dropped turned out to be beside the point: the DIRECTION
-- is operand 3, the command was reading operand 1, and operand 1 is the constant
-- 6 at every site in the game -- so no fade ever went to black. The chapter
-- walks had said `fadescreen` was lowered and the command audit had said it ran.
-- Only comparing the two signatures noticed they disagreed.
--
-- WHAT IT DOES NOT CHECK: operand ORDER. `g4_fade` would have passed happily
-- while reading a step count as a direction, because one operand is one operand.
--
-- ---------------------------------------------------------------------------
-- !! AND FOR MOST OF ITS LIFE IT GRADED A FILE THAT WAS NOT IN THE TREE.
--
-- This file used to open with
--
--     package.path = "/mnt/user-data/uploads/.../?.lua;/tmp/g4/?.lua;"
--                  .. "/tmp/g4/src/import/?.lua;" .. package.path
--
-- and a hard-coded ROM path beside it -- three absolutes from the machine it
-- was written on, PREPENDED, so `require` found whatever happened to be at
-- those paths before it ever looked at the tree the tool was run from. On any
-- other machine the check could not run at all; on the one it was written on
-- it silently graded a SNAPSHOT.
--
-- IT WAS CAUGHT BY ADDING A LOWERING AND WATCHING THE NUMBERS NOT MOVE. The
-- coverage check went 76,027 -> 76,032 and this one reported byte-identical
-- output, which is only possible if the two were reading different files.
--
-- THE COMMAND AUDIT WAS CAUGHT FOR THE SAME THING and fixed by self-locating
-- from arg[0]. That fix was never carried across to this file -- and it was
-- only half a fix anyway, because locating the tree does not PROVE the module
-- that loaded came from it. So there is a canary below that compares the file
-- `VM.lower` was actually loaded from against the one beside this tool, byte
-- for byte. A CHECK THAT CANNOT SAY WHAT IT GRADED IS NOT A CHECK.
-- ---------------------------------------------------------------------------
--
--   texlua tools/gen4_seam_check.lua <rom path>

local romPath = arg and arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_seam_check.lua <rom path>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path
local REAL = {
  ["src.script.Gen4ScriptVM"]=true, ["src.script.Gen4Commands"]=true,
  ["src.script.Commands"]=true, ["src.import.Gen4ScriptOps"]=true,
  ["src.import.Gen4ScriptBands"]=true, ["src.import.Gen4Text"]=true,
  ["src.pokemon.Boxes"]=true, ["src.core.GameVersion"]=true,
  ["src.pokemon.Contest"]=true,
  -- THESE THREE ARE NEW HERE AND THAT IS PART OF THE SAME FAULT. They used to
  -- be required by BARE NAME -- require("NdsRom") -- which does not begin with
  -- "src." and so slipped past this shim entirely, resolving through the
  -- `/tmp/g4/src/import/?.lua` entry the header describes. Requiring them
  -- properly meant the shim started answering for them, and an inert stub's
  -- `NdsRom.open` returns NOTHING, which is an assert with no arguments.
  ["src.import.Gen4Script"]=true, ["src.import.NdsRom"]=true,
  ["src.import.NarcArchive"]=true,
}
local inert = setmetatable({}, {
  __index=function(t,k) local v=rawget(t,k) if v~=nil then return v end
    return function() end end,
  __call=function() return nil end })
table.insert(package.searchers, 1, function(name)
  if REAL[name] then return nil end
  if name:sub(1,4) ~= "src." then return nil end
  return function() return inert end
end)

local okC, Commands = pcall(require, "src.script.Commands")
if not okC then
  io.write("could not load the real Commands module: ", tostring(Commands), "\n")
  os.exit(1)
end
require("src.script.Gen4Commands")
local VM = require("src.script.Gen4ScriptVM")
-- By full module path, because the bare names only resolved through one of the
-- absolutes this file used to carry.
local Script = require("src.import.Gen4Script")
local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")

-- THE CANARY THIS FILE DID NOT HAVE. `debug.getinfo(fn, "S").source` names the
-- file a function was loaded from; comparing its BYTES against the copy beside
-- this tool is what says the thing being graded is the thing in the tree. A
-- path comparison would not do: two paths can spell the same file and two
-- different files can both end in the right name.
local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
do
  local loadedFrom = (debug.getinfo(VM.lower, "S").source or ""):gsub("^@", "")
  local beside = (root ~= "" and root or "./") .. "../src/script/Gen4ScriptVM.lua"
  local a, b = readAll(loadedFrom), readAll(beside)
  if not a then
    io.write("cannot read the module that was loaded (" .. loadedFrom .. ")\n")
    os.exit(1)
  end
  if not b then
    io.write("cannot read " .. beside .. " -- run this from the repo\n")
    os.exit(1)
  end
  if a ~= b then
    io.write("!! the lowering that loaded is NOT the one beside this tool:\n")
    io.write("     loaded: " .. loadedFrom .. "\n")
    io.write("     beside: " .. beside .. "\n")
    io.write("   nothing below would be measuring the tree.\n")
    os.exit(1)
  end
end

-- CANARY: the check is only meaningful if the table really holds verbs.
assert(type(rawget(Commands,"g4_item_pocket"))=="function", "Gen4 verbs missing")
assert(type(rawget(Commands,"show_text"))=="function"
    or type(rawget(Commands,"jump"))=="function", "shared verbs missing")

local rom=assert(NdsRom.open(romPath))
local scr=assert(Narc.parse(assert(rom:read("/fielddata/script/scr_seq.narc"))))

local emitted, rows = {}, 0
for m=0,scr.count-1 do
  local b=scr:get(m)
  if b then
    local queue,seen={},{}
    for _,at in ipairs(Script.entries(b)) do
      if not seen[at] then seen[at]=true; queue[#queue+1]=at end
    end
    local i=1
    while i<=#queue do
      local at=queue[i]; i=i+1
      local ins=Script.decode(b,at) or {}
      for _,x in ipairs(ins) do
        local t=x.target
        if t and t>=1 and t<=#b and not seen[t] then seen[t]=true; queue[#queue+1]=t end
      end
      local ok, out = pcall(VM.lower, ins, nil)
      if ok and out then
        for _,row in ipairs(out) do
          local verb = row[1]
          if type(verb)=="string" then
            emitted[verb]=(emitted[verb] or 0)+1; rows=rows+1
          end
        end
      end
    end
  end
end

-- ARITY. debug.getinfo(fn,"u") gives a Lua function's DECLARED parameter count,
-- so the rows can be checked against the signatures they call. The dangerous
-- direction is TOO FEW: a command whose last parameter is a destination var,
-- called without it, writes nothing and the comparison behind it reads whatever
-- the previous command left. Too many is usually harmless (Lua drops extras) but
-- still means the lowering and the command disagree about the operand list.
local arity = {}
for verb in pairs(emitted) do
  local fn = rawget(Commands, verb)
  if type(fn)=="function" then
    local info = debug.getinfo(fn, "u")
    arity[verb] = { n = info.nparams, vararg = info.isvararg }
  end
end
local shapes = {}   -- verb -> { [argcount] = rows }
for m=0,scr.count-1 do
  local b=scr:get(m)
  if b then
    local queue,seen={},{}
    for _,at in ipairs(Script.entries(b)) do
      if not seen[at] then seen[at]=true; queue[#queue+1]=at end
    end
    local i=1
    while i<=#queue do
      local at=queue[i]; i=i+1
      local ins=Script.decode(b,at) or {}
      for _,x in ipairs(ins) do
        local t=x.target
        if t and t>=1 and t<=#b and not seen[t] then seen[t]=true; queue[#queue+1]=t end
      end
      local ok,out = pcall(VM.lower, ins, nil)
      if ok and out then
        for _,row in ipairs(out) do
          if type(row[1])=="string" then
            local n = 0
            for k=2,#row do if row[k] ~= nil then n = k-1 end end
            shapes[row[1]] = shapes[row[1]] or {}
            shapes[row[1]][n] = (shapes[row[1]][n] or 0) + 1
          end
        end
      end
    end
  end
end
io.write("\nARITY MISMATCHES (declared params exclude ctx, so budget = nparams-1):\n")
local flagged = 0
local vs={} for k in pairs(shapes) do vs[#vs+1]=k end table.sort(vs)
for _,v in ipairs(vs) do
  local a = arity[v]
  if a and not a.vararg then
    local budget = a.n - 1          -- first parameter is ctx
    for n, count in pairs(shapes[v]) do
      if n > budget then
        io.write(("  %-32s passes %d arg(s), takes %d   x%d rows  [EXTRA DROPPED]\n")
          :format(v, n, budget, count)); flagged = flagged + 1
      end
    end
  end
end
if flagged == 0 then io.write("  none\n") end

local names={} for k in pairs(emitted) do names[#names+1]=k end
table.sort(names)
local missing, present = {}, 0
for _,v in ipairs(names) do
  if type(rawget(Commands, v))=="function" then present=present+1
  else missing[#missing+1]=v end
end
io.write(("lowered the whole corpus: %d rows, %d distinct verbs\n"):format(rows,#names))
io.write(("%d verbs have a handler, %d DO NOT\n\n"):format(present,#missing))
if #missing>0 then
  io.write("VERBS WITH NO HANDLER (every row emitting one is silently skipped):\n")
  for _,v in ipairs(missing) do
    io.write(("  %-34s emitted %d time(s)\n"):format(v, emitted[v]))
  end
else
  io.write("every emitted verb resolves.\n")
end
