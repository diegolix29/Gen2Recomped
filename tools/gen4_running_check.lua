-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that Sinnoh's running shoes work the way the cartridge's do,
-- and that the port's step timings are Platinum's rather than Gen 1/2's.
--
-- Reported from play as "running shoes don't work, need sprint animation". Three
-- separate things were wrong and each was invisible from inside the game:
--
--   * `OverworldState:runFrames` had no Gen 4 branch at all, so every Platinum
--     dataset fell into the `version ~= "prism"` refusal.
--   * opcode 0x159 `checkrunningshoesacquired` was in the table with NO lowering,
--     which for a command that writes a var means the `gotoif` after it read
--     whatever the last comparison left behind.
--   * `save.hasRunningShoes` was written by `g4_running_shoes` and read by
--     nothing -- the sixth write-and-never-read in this port.
--
-- Usage: texlua tools/gen4_running_check.lua <rom> <pokeplatinum dir>

local romPath, pretDir = arg[1], arg[2]
if not romPath or not pretDir then
  io.stderr:write("usage: texlua tools/gen4_running_check.lua <rom> <pokeplatinum dir>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Gen4MapHeaders = require("src.import.Gen4MapHeaders")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(rel)
  local f = io.open(pretDir .. "/" .. rel, "rb")
  if not f then return nil end
  local s = f:read("a"); f:close(); return s
end
-- COMMENTS STRIPPED BEFORE ANY OF THIS IS SEARCHED, and the reason is not
-- hypothetical: the Gen 4 branch carries a comment that spells out the
-- nil-global trap, and that comment CONTAINS the literal `elseif gen4 then`. The
-- first draft of this section matched inside it, decided the use came before the
-- declaration, and failed on correct code -- while the same slip would have let a
-- genuinely misplaced local through. A check that reads source text has to read
-- the code and not the prose about it.
local function stripComments(text)
  return (tostring(text):gsub("%-%-[^\r\n]*", ""))
end
local function port(rel)
  local f = io.open(root .. "../" .. rel, "rb") or io.open(rel, "rb")
  if not f then return nil end
  local s = f:read("a"); f:close(); return s
end

-- ---------------------------------------------------------------------------
section("1. the two gates, and only two")
-- ---------------------------------------------------------------------------
local moveC = slurp("src/player_move.c")
ok(moveC, "src/player_move.c not found under %s", tostring(pretDir))
moveC = moveC or ""

-- The test appears once per movement variant -- the plain one, the distortion
-- one and the gravity one -- and they all agree, which is what says this is the
-- rule and not one special case.
-- Counted by the two function NAMES rather than by the conjunction between them:
-- the three sites parenthesise it differently (one nests the tests instead of
-- &&-ing them), so a pattern tight enough to match one misses the others.
local shoeTests, buttonTests = 0, 0
for _ in moveC:gmatch("PlayerData_HasRunningShoes") do shoeTests = shoeTests + 1 end
for _ in moveC:gmatch("PlayerAvatar_IsRunButtonHeld") do buttonTests = buttonTests + 1 end
ok(shoeTests == 3,
   "PlayerData_HasRunningShoes is tested %d times in player_move.c, expected 3 "
   .. "-- the plain, distortion and gravity movement variants", shoeTests)
ok(buttonTests >= 4,
   "PlayerAvatar_IsRunButtonHeld appears %d times, expected at least 4 (three "
   .. "call sites plus its definition)", buttonTests)

-- ...and the button is B.
local held = moveC:match("BOOL PlayerAvatar_IsRunButtonHeld%b()%s*{(.-)\n}")
ok(held, "PlayerAvatar_IsRunButtonHeld could not be isolated")
ok(held and held:find("pad & PAD_BUTTON_B", 1, true),
   "the run button is no longer PAD_BUTTON_B: %q", tostring(held and held:sub(1, 60)))

-- THE RUN BRANCH TESTS NOTHING ABOUT THE TILE. Emerald has
-- `MetatileBehavior_IsRunningDisallowed`; Platinum has no such call anywhere, so a
-- ground gate in the port would be a rule the cartridge does not have.
local anyGround = 0
for _, rel in ipairs({ "src/player_move.c", "src/player_avatar.c" }) do
  local text = slurp(rel) or ""
  for _ in text:gmatch("IsRunningDisallowed") do anyGround = anyGround + 1 end
end
ok(anyGround == 0,
   "something now tests a running-disallowed behaviour (%d hits) -- Platinum had "
   .. "none, and the port's Gen 4 branch deliberately has no ground gate", anyGround)

-- ---------------------------------------------------------------------------
section("2. the map header's running bit is parsed and IGNORED")
-- ---------------------------------------------------------------------------
-- `isRunningAllowed` is a real bitfield in pret's MapHeader and is read NOWHERE
-- in the cartridge's code -- the only other mentions are the header data
-- declarations. That is why the port's Gen 4 branch has no map gate, so if the
-- cartridge ever starts reading it this has to fail.
local headerH = slurp("include/map_header.h") or ""
local body = headerH:match("u8 cameraType;(.-)}%s*MapHeader;")
ok(body, "the MapHeader bitfield tail could not be isolated")
local order = {}
for name in (body or ""):gmatch("u16%s+([%w_]+)%s*:%s*%d+%s*;") do order[#order + 1] = name end
ok(#order == 6, "%d bitfields after cameraType, expected 6", #order)
ok(order[1] == "mapType" and order[2] == "battleBG",
   "the flag word starts with %q, %q", tostring(order[1]), tostring(order[2]))
ok(order[3] == "isBikeAllowed", "field 3 is %q", tostring(order[3]))
ok(order[4] == "isRunningAllowed",
   "field 4 is %q -- the port reads bit 13 as allowRunning on the strength of "
   .. "this order", tostring(order[4]))
ok(order[5] == "isEscapeRopeAllowed" and order[6] == "isFlyAllowed",
   "the flag word ends with %q, %q", tostring(order[5]), tostring(order[6]))

-- Nothing in the code reads it.
local readers = 0
for _, rel in ipairs({ "src/player_move.c", "src/player_avatar.c", "src/map_header_data.c",
                      "src/overlay005/fieldmap.c", "src/field_system.c" }) do
  local text = slurp(rel)
  if text then
    for _ in text:gmatch("isRunningAllowed") do readers = readers + 1 end
  end
end
ok(readers == 0,
   "isRunningAllowed is now read in %d place(s) -- Platinum ignored it, and the "
   .. "port's Gen 4 branch has no map gate because of that", readers)

-- ...and that bit 13 is where the port reads it, tested on a synthetic record
-- rather than on whichever real header happens to have it set.
local function headerWithFlags(flags)
  local rec = {}
  for i = 1, Gen4MapHeaders.RECORD_BYTES do rec[i] = "\0" end
  rec[21] = string.char(0)              -- weather
  rec[22] = string.char(0)              -- cameraType
  rec[23] = string.char(flags % 256)
  rec[24] = string.char(math.floor(flags / 256) % 256)
  return table.concat(rec)
end
local bit13 = Gen4MapHeaders.parse(headerWithFlags(8192))
ok(bit13 and bit13.allowRunning == true,
   "bit 13 alone did not set allowRunning (got %s)",
   tostring(bit13 and bit13.allowRunning))
for _, other in ipairs({ 4096, 16384, 32768 }) do
  local h = Gen4MapHeaders.parse(headerWithFlags(other))
  ok(h and h.allowRunning == false,
     "flag bit %d set allowRunning too, so the bit is not isolated", other)
end

-- ---------------------------------------------------------------------------
section("3. the step ladder, read out of the cartridge's own action table")
-- ---------------------------------------------------------------------------
local actionsC = slurp("src/unk_020655F4.c")
ok(actionsC, "src/unk_020655F4.c not found")
actionsC = actionsC or ""

-- Every InitWalk for DIR_NORTH, in file order: distance, duration and the last
-- argument. The last one is what tells RUN apart from WALK_FAST.
local rows = {}
for dist, dur, tail in actionsC:gmatch(
    "MovementAction_InitWalk%(mapObj, DIR_NORTH, FX32_CONST%(([%d%.]+)%), (%d+), ([%w_]+)%)") do
  rows[#rows + 1] = { dist = tonumber(dist), dur = tonumber(dur), tail = tail }
end
ok(#rows == 7, "%d DIR_NORTH InitWalk rows, expected 7", #rows)

-- EVERY ROW IS ONE CELL. That is the invariant that makes a duration a speed:
-- distance x duration = 16 pixels, and a row that does not close is a row read
-- wrong.
for i, row in ipairs(rows) do
  ok(row.dist * row.dur == 16,
     "row %d is %s px over %d frames = %s, not one 16px cell",
     i, tostring(row.dist), row.dur, tostring(row.dist * row.dur))
end

local walkFast, run
for _, row in ipairs(rows) do
  if row.tail == "MAP_OBJ_UNK_A0_04" then walkFast = row end
  if row.tail == "MAP_OBJ_UNK_A0_09" then run = row end
end
local walkNormal
for _, row in ipairs(rows) do
  if row.tail == "MAP_OBJ_UNK_A0_03" then walkNormal = row end
end
ok(walkNormal, "no walk-normal row (MAP_OBJ_UNK_A0_03) in the ladder")
ok(walkFast, "no walk-fast row (MAP_OBJ_UNK_A0_04) in the ladder")
ok(run, "no run row (MAP_OBJ_UNK_A0_09) in the ladder")
ok(walkNormal and walkNormal.dur == 8,
   "walk normal is %s frames, expected 8", tostring(walkNormal and walkNormal.dur))
ok(run and run.dur == 4, "the run is %s frames, expected 4", tostring(run and run.dur))

-- THE RUN IS WALK-FAST'S SPEED WITH A DIFFERENT ANIMATION, which is the finding
-- that makes "the sprint animation is missing" a separate problem from "running
-- is refused". If these ever differ in distance or duration, the run has become a
-- speed of its own and the port's runStepFrames has to be rederived.
ok(run and walkFast and run.dist == walkFast.dist and run.dur == walkFast.dur,
   "run is %s px/%s frames and walk-fast is %s px/%s frames -- they were "
   .. "identical, which is why the run is an animation difference",
   tostring(run and run.dist), tostring(run and run.dur),
   tostring(walkFast and walkFast.dist), tostring(walkFast and walkFast.dur))
ok(run and walkFast and run.tail ~= walkFast.tail,
   "run and walk-fast now carry the same last argument (%s), so nothing in the "
   .. "table distinguishes them at all", tostring(run and run.tail))

-- ...and the run really is its own movement action rather than an alias.
ok(actionsC:find("gMovementActionFuncs_RunNorth[]", 1, true),
   "there is no gMovementActionFuncs_RunNorth any more")

-- ---------------------------------------------------------------------------
section("4. the port states Platinum's timings, not Gen 1/2's")
-- ---------------------------------------------------------------------------
local extractor = port("src/import/RomExtractorGen4.lua")
ok(extractor, "RomExtractorGen4.lua could not be read")
extractor = extractor or ""
local worldBlock = extractor:match("world = {(.-)},")
ok(worldBlock, "the Gen 4 constants.world block could not be isolated")
worldBlock = worldBlock or ""
local stated = tonumber(worldBlock:match("stepFrames = (%d+)"))
local statedRun = tonumber(worldBlock:match("runStepFrames = (%d+)"))
ok(stated == (walkNormal and walkNormal.dur),
   "the cache states stepFrames = %s but the cartridge walks in %s frames",
   tostring(stated), tostring(walkNormal and walkNormal.dur))
ok(statedRun == (run and run.dur),
   "the cache states runStepFrames = %s but the cartridge runs in %s frames",
   tostring(statedRun), tostring(run and run.dur))
-- The fallbacks are Gen 1/2's, so a Gen 4 cache that states nothing inherits
-- them silently -- which is what was happening.
local defaults = port("src/world/FieldDefaults.lua") or ""
local fallback = tonumber(defaults:match("stepFrames = (%d+)"))
ok(fallback and stated and fallback ~= stated,
   "the Gen 4 value (%s) and the engine fallback (%s) are the same, so this "
   .. "check cannot tell a stated timing from an inherited one",
   tostring(stated), tostring(fallback))

-- ---------------------------------------------------------------------------
section("5. the wiring: granted, lowered, and actually read")
-- ---------------------------------------------------------------------------
local ops = stripComments(port("src/import/Gen4ScriptOps.lua") or "")
ok(ops:find('[0x159] = { "checkrunningshoesacquired", "w" }', 1, true),
   "opcode 0x159 is no longer checkrunningshoesacquired with a var operand")
ok(ops:find('[0x15A] = { "giverunningshoes", "" }', 1, true),
   "opcode 0x15A is no longer giverunningshoes")

local vm = stripComments(port("src/script/Gen4ScriptVM.lua") or "")
-- THE WHOLE POINT: 0x159 was in the table with no lowering. A command that
-- writes a var and is not lowered is worse than one that is missing.
ok(vm:find("L.checkrunningshoesacquired", 1, true),
   "checkrunningshoesacquired has no lowering -- the gotoif after it reads "
   .. "whatever the last comparison left in the register")
ok(vm:find("L.giverunningshoes", 1, true), "giverunningshoes has no lowering")

local cmds = stripComments(port("src/script/Gen4Commands.lua") or "")
ok(cmds:find("function Commands.g4_has_running_shoes", 1, true),
   "there is no g4_has_running_shoes command for the lowering to call")
local reader = cmds:match("function Commands%.g4_has_running_shoes.-\nend")
ok(reader, "g4_has_running_shoes could not be isolated")
reader = reader or ""
ok(reader:find("setVar", 1, true),
   "g4_has_running_shoes does not write its destination var, so the script's "
   .. "branch still reads a stale register")
-- `PlayerData_HasRunningShoes` returns TRUE/FALSE and the comparisons after it
-- are numeric, so a Lua boolean in the var would be compared against 1 and lose.
ok(reader:find("and 1 or 0", 1, true),
   "g4_has_running_shoes does not normalise to 1/0 -- the cartridge's comparisons "
   .. "are numeric")
ok(reader:find("hasRunningShoes", 1, true) and reader:find("runningShoes", 1, true),
   "g4_has_running_shoes does not read both spellings that g4_running_shoes writes")

local ow = stripComments(port("src/world/OverworldController.lua") or "")
ok(ow:find("elseif gen4 then", 1, true),
   "runFrames has no Gen 4 branch, so every Platinum dataset falls through to "
   .. "the non-prism refusal")
-- A LOCAL DECLARED BELOW ITS USE RESOLVES AS A NIL GLOBAL, so the branch would
-- simply never be taken -- silently, which is exactly the failure mode this
-- whole file exists to catch. Positions, not presence.
local declAt = ow:find("local gen4 = ", 1, true)
local useAt = ow:find("elseif gen4 then", 1, true)
ok(declAt, "gen4 is never declared as a local in OverworldController")
ok(declAt and useAt and declAt < useAt,
   "`local gen4` is declared at %s but used at %s -- above its declaration the "
   .. "name is a nil global and the branch is never taken",
   tostring(declAt), tostring(useAt))
-- ...and that the branch reads the flag the grant writes.
local branch = ow:match("elseif gen4 then(.-)elseif version")
ok(branch, "the Gen 4 branch could not be isolated")
branch = branch or ""
ok(branch:find("hasRunningShoes", 1, true),
   "the Gen 4 branch does not read hasRunningShoes, so the flag stays "
   .. "write-and-never-read")
-- The two gates and no more: a map or ground gate here would be invented.
ok(not branch:find("allowRunning", 1, true),
   "the Gen 4 branch gates on allowRunning, which the cartridge never reads")
ok(not branch:find("runningBlockedAt", 1, true),
   "the Gen 4 branch gates on a ground behaviour, which Platinum's run branch "
   .. "does not test")

-- ---------------------------------------------------------------------------
section("6. the bit is real in the ROM, even though nothing uses it")
-- ---------------------------------------------------------------------------
-- If allowRunning came back the same on every map, the parse could be wrong and
-- nothing above would notice, because the cartridge ignores the field.
local rom = assert(NdsRom.open(romPath))
local arm9 = assert(rom:arm9())
local function arc(p)
  local b = rom:read(p)
  return b and Narc.parse(b)
end
local areaArc, matArc = arc("/fielddata/areadata/area_data.narc"), arc("/fielddata/mapmatrix/map_matrix.narc")
local encArc, evArc = arc("/fielddata/encountdata/pl_enc_data.narc"), arc("/fielddata/eventdata/zone_event.narc")
local scrArc, msgArc = arc("/fielddata/script/scr_seq.narc"), arc("/msgdata/pl_msg.narc")
local at, count = Gen4MapHeaders.find(arm9, {
  areaData = areaArc.count, matrix = matArc.count, scripts = scrArc.count,
  messages = msgArc.count, encounters = encArc.count, events = evArc.count,
  names = 1000,
})
ok(at, "the map header table was not found")
local headers = at and Gen4MapHeaders.all(arm9, at, count) or {}
local allow, deny, bike = 0, 0, 0
for _, h in pairs(headers) do
  if h.allowRunning then allow = allow + 1 else deny = deny + 1 end
  if h.allowBike then bike = bike + 1 end
end
ok(allow + deny == 593, "%d headers, expected 593", allow + deny)
ok(allow > 0 and deny > 0,
   "allowRunning is %d/%d across the region -- a field that never varies could "
   .. "be parsed from the wrong bit without this check noticing", allow, deny)
ok(allow ~= bike,
   "allowRunning and allowBike agree on all 593 maps, so bit 13 and bit 12 "
   .. "cannot be told apart on this cartridge")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
