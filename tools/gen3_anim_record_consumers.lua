-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- EVERY FIELD THE EXTRACTOR WRITES INTO A MOVE'S `anim`, AND WHO READS IT.
--
-- The import decodes an effect out of the ROM, writes it into the move's
-- record under a name, and the battle player reads that name. Those are two
-- files that never meet, and the port has been bitten by that shape over and
-- over -- the type chart, the abilities, the move effects, the ball pocket,
-- the party icons. An effect written under a name nobody reads is extracted,
-- shipped, and invisible: the move plays without it and nothing anywhere
-- reports a problem.
--
-- This asks the question directly. It reads the DATASET rather than the
-- extractor, because the dataset is what actually shipped, and it greps the
-- ENGINE rather than reasoning about it.
--
-- IT IS ALSO A GUARD AGAINST BEING FOOLED. This file exists because a stale
-- copy of `src/` made seven live fields look dead, and a census that takes two
-- seconds would have said so at once. A claim about what the engine reads is
-- cheap to check and expensive to get wrong.
--
-- Usage: texlua tools/gen3_anim_record_consumers.lua <data/generated> [src dir]

local DIR = arg[1]
local SRC = arg[2] or "src"
if not DIR then
  io.write("Pass the generated data root as the first argument.\n")
  os.exit(2)
end

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

-- THE ONE MATCHER, used by the census below and by the controls at the end.
-- Word-bounded, because this dataset carries BOTH `shake` and `shakes`: a
-- substring search would let the longer name vouch for the shorter one, and
-- a field with a namesake would read as live for ever. Defined once so the
-- controls test the code the census actually runs, not a copy of it.
local function reads(hay, name)
  return hay:find("[^%w_]" .. name .. "[^%w_]") ~= nil
end

-- ---------------------------------------------------------------------------
section("1. the dataset's own anim fields")
-- ---------------------------------------------------------------------------
local chunk = loadfile(DIR .. "/moves.lua")
ok(chunk ~= nil, "moves.lua did not load from %s", DIR)
if not chunk then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end
local okc, moves = pcall(chunk)
ok(okc and type(moves) == "table", "moves.lua did not return a table")
if not (okc and type(moves) == "table") then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local fields, withAnim, total = {}, 0, 0
for _, def in pairs(moves) do
  total = total + 1
  local anim = type(def) == "table" and def.anim
  if type(anim) == "table" then
    withAnim = withAnim + 1
    for k, v in pairs(anim) do
      if type(k) == "string" then
        fields[k] = fields[k] or { moves = 0 }
        fields[k].moves = fields[k].moves + 1
        fields[k].sample = fields[k].sample or type(v)
      end
    end
  end
end
io.write(("  %d moves, %d with an anim record\n"):format(total, withAnim))
ok(withAnim > 100, "only %d move(s) carry an anim record -- this dataset "
   .. "cannot measure anything", withAnim)
local names = {}
for k in pairs(fields) do names[#names + 1] = k end
table.sort(names)
ok(#names > 5, "only %d distinct anim field(s) found", #names)

-- ---------------------------------------------------------------------------
section("2. ...and whether the engine reads each one")
-- ---------------------------------------------------------------------------
-- The extractor is deliberately EXCLUDED from the search: it is the writer, and
-- a field that only it mentions is exactly the dead one being looked for.
local WRITERS = {
  ["RomExtractorGen3.lua"] = true,
  ["RomExtractorGen2.lua"] = true,
  ["RomExtractorGen4.lua"] = true,
}

-- Every .lua under SRC, minus the writers.
local readers = {}
do
  local pipe = io.popen('find "' .. SRC .. '" -name "*.lua" -type f 2>/dev/null')
  if pipe then
    for line in pipe:lines() do
      local base = line:match("[^/\\]+$") or line
      if not WRITERS[base] then readers[#readers + 1] = line end
    end
    pipe:close()
  end
end
ok(#readers > 20, "only %d engine file(s) found under %s -- the search is "
   .. "not looking at the engine", #readers, SRC)

-- Read them once. A field is READ when its name appears anywhere outside the
-- extractor; that is deliberately generous, because the question here is
-- "does anything even mention this", and a false PASS is far less costly than
-- a false FAIL that sends somebody rewriting working code.
local haystack = {}
for _, path in ipairs(readers) do
  local f = io.open(path, "rb")
  if f then haystack[#haystack + 1] = f:read("*a"); f:close() end
end
local blob = table.concat(haystack, "\n")
ok(#blob > 100000, "the engine source came back %d bytes; nothing was read",
   #blob)

local dead, live = {}, 0
for _, name in ipairs(names) do
  if reads(blob, name) then live = live + 1 else dead[#dead + 1] = name end
end
io.write(("  %d field(s): %d read by the engine, %d not\n")
         :format(#names, live, #dead))
for _, name in ipairs(names) do
  local mark = " "
  for _, d in ipairs(dead) do if d == name then mark = "!" end end
  io.write(("   %s %-18s %4d move(s)\n"):format(mark, name, fields[name].moves))
end

-- THE ASSERTION. A field the dataset carries and the engine never mentions is
-- an effect that was decoded out of the cartridge and then thrown away.
local lost = 0
for _, name in ipairs(dead) do lost = lost + fields[name].moves end
ok(#dead == 0,
   "%d anim field(s) are written by the import and read by nothing -- %s -- "
   .. "affecting %d move-effect(s)", #dead, table.concat(dead, " "), lost)

-- ---------------------------------------------------------------------------
section("3. the search can fail")
-- ---------------------------------------------------------------------------
-- A census that says "all clear" is worth nothing unless a missing consumer
-- would actually be seen. A name the engine cannot contain is the control.
-- THE WORD BOUNDARY IS LOAD-BEARING, and nothing in today's dataset proves it:
-- every field happens to be mentioned in its own right, so a substring search
-- would pass too. It stops mattering the moment one field's name is a prefix
-- of another's -- and this dataset carries BOTH `shake` and `shakes`. Tested
-- on a synthetic blob, because the property is about the matcher.
do
  local onlyPlural = " local x = anim.shakes or {} "
  ok(reads(onlyPlural, "shakes"),
     "the matcher cannot find `shakes` where it plainly is")
  ok(not reads(onlyPlural, "shake"),
     "`shake` was satisfied by `shakes` -- a field with a longer namesake "
     .. "would read as live for ever")
  local suffixed = " thing.scaleX = 2 "
  ok(not reads(suffixed, "scale"), "`scale` was satisfied by `scaleX`")
  ok(reads(" a.scale = 1 ", "scale"), "the matcher cannot find a plain `scale`")
end

-- ...AND THE WRITER MUST NOT COUNT AS A READER. The extractor mentions every
-- one of these names -- it is what writes them -- so a search that included it
-- would report every field live, permanently and uselessly.
do
  local sawExtractor = false
  for _, path in ipairs(readers) do
    if path:find("RomExtractorGen3", 1, true) then sawExtractor = true end
  end
  ok(not sawExtractor,
     "the Gen 3 extractor is in the search set, so it vouches for its own "
     .. "fields and this whole census answers yes to everything")
  -- and prove it WOULD have: the extractor names a field the engine may not
  local f = io.open(SRC .. "/import/RomExtractorGen3.lua", "rb")
  if f then
    local writer = f:read("*a"); f:close()
    local mentions = 0
    for _, name in ipairs(names) do
      if reads(writer, name) then mentions = mentions + 1 end
    end
    ok(mentions > #names / 2,
       "the extractor mentions only %d of %d field(s); it is supposed to be "
       .. "the writer, so either the wrong file was read or the fields have "
       .. "moved", mentions, #names)
  end
end

do
  local invented = "zzNoSuchAnimFieldzz"
  ok(not reads(blob, invented),
     "the engine appears to mention %q, so this search matches anything",
     invented)
  -- ...and a name it certainly does contain
  ok(reads(blob, "events"),
     "the engine does not mention `events`, so the search is finding nothing")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
