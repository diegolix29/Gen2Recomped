-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that every signpost in Sinnoh can be resolved to the model
-- the cartridge draws for it, and that the table which does it was found by a
-- rule strong enough to reject the two decoys sitting beside it.
--
-- Item 2 on the play-test list -- "signs are not rendered at all". Cedric, from
-- play: *"i cant walk through it but theres nothing rendered"*, with the sign's
-- TEXT reading correctly, so only the art was ever missing.
--
-- THIS FILE EXISTS BECAUSE THE PORT HAD A TRUE STATEMENT WITH A FALSE REASON.
-- `Gen4ObjectGfx.NO_SPRITE` said 91-96 have no sprite -- correct -- "because a
-- signpost is part of the map" -- wrong, and the wrongness is what stopped
-- anyone looking further for six passes. The map does not contain them: see
-- section 2, which measures Twinleaf's chunk rather than asserting it.
--
-- NOTE FOR ANYONE READING gen4_mapprops_check.lua: that file's header used to
-- say items 2 and 4 are "one fault" and that a signpost is a map prop. They are
-- TWO faults. Item 4 (placeholder art) really is the dummy box and the per-area
-- allow-list; item 2 is this file, and no signpost is a map prop at all.
--
-- Usage: texlua tools/gen4_signpost_check.lua <rom>

local romPath = arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_signpost_check.lua <rom>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Gen4ObjectGfx = require("src.import.Gen4ObjectGfx")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local rom = NdsRom.open(romPath)
if not rom then
  io.stderr:write("could not open " .. romPath .. "\n")
  os.exit(2)
end
local function archive(path)
  local bytes = rom:read(path)
  return bytes and Narc.parse(bytes)
end

-- ---------------------------------------------------------------------------
section("1. the sprite table genuinely has no row for a signpost")
-- ---------------------------------------------------------------------------
local overlay = rom:overlay(Gen4ObjectGfx.OVERLAY)
ok(overlay ~= nil, "overlay %d is unreadable", Gen4ObjectGfx.OVERLAY)

local mmodel = archive("/data/mmodel/mmodel.narc")
ok(mmodel ~= nil, "mmodel.narc is unreadable")
ok(mmodel and mmodel.count == 470, "mmodel.narc has %s members, expected 470",
   mmodel and tostring(mmodel.count))

local sprites, rows = Gen4ObjectGfx.read(overlay, mmodel and mmodel.count or 470)
ok(sprites ~= nil, "gObjectEventGfxTexturesTable was not found")
ok(rows == 440, "the sprite table has %s rows, expected 440", tostring(rows))

-- THE NEIGHBOURS ARE THE POINT. If 90 and 97 also had no row this would be a
-- broken reader rather than a gap in the cartridge.
ok(sprites and sprites[90] == 88, "gfx 90 -> %s, expected member 88",
   sprites and tostring(sprites[90]))
ok(sprites and sprites[97] == 91, "gfx 97 -> %s, expected member 91",
   sprites and tostring(sprites[97]))
for id = 91, 96 do
  ok(sprites and sprites[id] == nil,
     "gfx %d HAS a sprite row (member %s) -- the premise of this whole file is "
     .. "that it does not", id, sprites and tostring(sprites[id]))
end

-- ---------------------------------------------------------------------------
section("2. and the map does not contain them either (Twinleaf, measured)")
-- ---------------------------------------------------------------------------
-- Twinleaf's chunk is land 0 of matrix 0. Its props are four buildings each
-- paired with model 67, and 67 is `t1_door1` -- a DOOR. If this ever starts
-- naming a signpost model the "signs are map geometry" theory is back on the
-- table and this file should be re-read, not deleted.
local build = archive("/fielddata/build_model/build_model.narc")
ok(build ~= nil, "build_model.narc is unreadable")
local function modelName(arc, member)
  local bytes = arc and member and arc:get(member)
  -- The MDL0 dictionary's first name, which is the model's own.
  return bytes and bytes:match("MDL0.-([%a][%w_]+)")
end
ok(modelName(build, 67) == "t1_door1",
   "build_model 67 is %s, expected t1_door1 -- Twinleaf's four repeated props "
   .. "are doors, not signs", tostring(modelName(build, 67)))

-- ---------------------------------------------------------------------------
section("3. the model table, and the rule that finds it")
-- ---------------------------------------------------------------------------
local fldeff = archive(Gen4ObjectGfx.MODEL_ARCHIVE)
ok(fldeff ~= nil, "%s is unreadable", Gen4ObjectGfx.MODEL_ARCHIVE)
ok(fldeff and fldeff.count == Gen4ObjectGfx.MODEL_MEMBERS,
   "%s has %s members, expected %d", Gen4ObjectGfx.MODEL_ARCHIVE,
   fldeff and tostring(fldeff.count), Gen4ObjectGfx.MODEL_MEMBERS)

local models, modelRows = Gen4ObjectGfx.readModels(overlay, fldeff and fldeff.count)
ok(models ~= nil, "the object-model table was not found: %s", tostring(modelRows))
ok(modelRows == 9, "the model table decoded %s rows, expected 9", tostring(modelRows))

-- THE CONTROL. Three places in overlay 5 carry ids 91..96 at stride 8, so the
-- ids alone do not identify the table. Told the archive is smaller than it is,
-- the real table goes out of range and the reader must REFUSE -- not fall
-- through to one of the decoys, whose member columns are 35,631,104 and a
-- constant 2. A finder that cannot be made to fail has not been tested.
ok(Gen4ObjectGfx.readModels(overlay, 60) == nil,
   "with memberCount=60 the reader returned a table -- it is matching on the "
   .. "ids alone and would accept a decoy")

-- ...and that the rule is UNIQUE rather than first-past-the-post.
ok(Gen4ObjectGfx.findModels(overlay, fldeff and fldeff.count) ~= nil,
   "findModels refused the real overlay -- two offsets now satisfy the rule, "
   .. "so the rule has stopped identifying the table")

-- ---------------------------------------------------------------------------
section("4. every row lands on a model whose NAME agrees with pret's")
-- ---------------------------------------------------------------------------
-- This is the check that makes the table trustworthy. The left column is the
-- cartridge's; the names are pret's; the two were never joined before. A member
-- column of merely plausible numbers passes every bound check above and fails
-- here.
local EXPECTED = {
  [91] = { member = 69, model = "board_a" },
  [92] = { member = 70, model = "board_b" },
  [93] = { member = 71, model = "board_c" },
  [94] = { member = 72, model = "board_d" },
  [95] = { member = 73, model = "board_e" },
  [96] = { member = 74, model = "board_f" },
  [183] = { member = 79, model = "book" },
  [209] = { member = 110, model = "door2" },
  [262] = { member = 149, model = "rotomwall" },
}
for id, want in pairs(EXPECTED) do
  local member = models and models[id]
  ok(member == want.member, "gfx %d (%s) -> member %s, expected %d",
     id, tostring(Gen4ObjectGfx.name(id)), tostring(member), want.member)
  if member then
    local bytes = fldeff and fldeff:get(member)
    ok(bytes and bytes:sub(1, 4) == "BMD0",
       "fldeff %d is %s, expected a BMD0 model", member,
       bytes and tostring(bytes:sub(1, 4)))
    ok(modelName(fldeff, member) == want.model,
       "fldeff %d is model %s, expected %s", member,
       tostring(modelName(fldeff, member)), want.model)
  end
end

-- ...and that nothing outside those nine crept in.
local extra = 0
for id in pairs(models or {}) do if not EXPECTED[id] then extra = extra + 1 end end
ok(extra == 0, "%d ids decoded that are not in the expected nine", extra)

-- ---------------------------------------------------------------------------
section("5. and the port agrees with itself about all of them")
-- ---------------------------------------------------------------------------
-- An id the model table names must not also be marked as having no picture for
-- some other reason, and every one of the six signposts must still report that
-- it has no BILLBOARD -- both halves, or the renderer gets a contradiction.
for id in pairs(EXPECTED) do
  ok(Gen4ObjectGfx.reason(id) == "model",
     "gfx %d reports reason %q, expected \"model\"", id,
     tostring(Gen4ObjectGfx.reason(id)))
  ok(sprites and sprites[id] == nil,
     "gfx %d is in BOTH tables -- a sprite row and a model row", id)
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
