-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that a map prop's model id resolves the way the cartridge
-- resolves it, and that the port can tell a real prop from the dummy box.
--
-- THIS HEADER USED TO SAY items 2 and 4 on the play-test list -- "signs are not
-- rendered at all" and "some areas draw placeholder tile art" -- were ONE fault,
-- because a signpost was a map prop. THEY ARE TWO, and the signpost half was
-- wrong: no signpost is a map prop at all. Twinleaf's chunk carries four
-- buildings each paired with `t1_door1` -- doors -- its 19 mesh shapes are all
-- terrain materials, and its prop allow-list holds no signpost and no mailbox.
-- Signs are object events drawn from `fldeff.narc`; see
-- tools/gen4_signpost_check.lua, which measures that and nothing here does.
--
-- What is left for THIS file, and what it still proves, is item 4 alone: the
-- prop's model id is a GLOBAL build_model.narc member, each area loads only a
-- SUBSET of that archive, and an id outside the subset draws `dmybox00` rather
-- than nothing. That is the placeholder art, and it is a real fault with a real
-- mechanism -- it just never had a sign in it.
--
-- `Gen4Maps.areaBuildings` decoded the subset lists correctly for as long as it
-- has existed and NOTHING EVER CALLED IT. This file exists so that cannot recur
-- quietly: a decoder with no caller is a table with no reader, one step earlier.
--
-- Usage: texlua tools/gen4_mapprops_check.lua <rom> <pokeplatinum dir>

local romPath, pretDir = arg[1], arg[2]
if not romPath or not pretDir then
  io.stderr:write("usage: texlua tools/gen4_mapprops_check.lua <rom> <pokeplatinum dir>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Gen4Maps = require("src.import.Gen4Maps")
local Gen4Terrain = require("src.import.Gen4Terrain")
local Gen4MapHeaders = require("src.import.Gen4MapHeaders")
local Gen4PropShapes = require("src.import.Gen4PropShapes")

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

local AREA_BUILD = "/fielddata/areadata/area_build_model/area_build.narc"
local AREA_TEXSET = "/fielddata/areadata/area_build_model/areabm_texset.narc"
local BUILD_MODEL = "/fielddata/build_model/build_model.narc"

-- ---------------------------------------------------------------------------
section("1. the cartridge's rules, read out of pret")
-- ---------------------------------------------------------------------------
local areaDataC = slurp("src/overlay005/area_data.c") or ""
local areaDataH = slurp("include/overlay005/area_data.h") or ""
local mapPropC = slurp("src/overlay005/map_prop.c") or ""
ok(#areaDataC > 0, "src/overlay005/area_data.c not found under %s", tostring(pretDir))
ok(#mapPropC > 0, "src/overlay005/map_prop.c not found")

local maxFiles = tonumber(areaDataH:match("#define%s+MAX_MAP_PROP_MODEL_FILES%s+(%d+)"))
ok(maxFiles == 768, "MAX_MAP_PROP_MODEL_FILES is %s, expected 768", tostring(maxFiles))

-- THE COUNT IS THE FIRST ELEMENT, which is what makes the list shape decodable.
ok(areaDataC:find("mapPropModelIDsCount = areaDataManager->mapPropModelIDs[0]", 1, true),
   "the count is no longer mapPropModelIDs[0] -- areaBuildings' shape assumption "
   .. "is built on it")
ok(areaDataC:find("GF_ASSERT(loadData->mapPropModelIDsCount < MAX_MAP_PROP_MODEL_FILES)", 1, true),
   "the count is no longer asserted against MAX_MAP_PROP_MODEL_FILES")

-- THE IDS ARE GLOBAL AND THE ARRAY IS SPARSE: `mapPropModelFiles[id]` is indexed
-- by the id itself, never by the position in the list. A port that treated the
-- list as a dense remapping would draw the wrong prop everywhere.
ok(areaDataC:find("u16 mapPropModelID = areaDataManager->mapPropModelIDs[i + 1]", 1, true),
   "the per-area loop no longer reads mapPropModelIDs[i + 1]")
ok(areaDataC:match("mapPropModelFiles%[mapPropModelID%]%s*=%s*NARC_AllocAndReadWholeMember%(narc, mapPropModelID"),
   "the model is no longer loaded from build_model by its OWN id -- the ids may "
   .. "no longer be global members")

-- AND THE FALLBACK IS A VISIBLE BOX, NOT AN ABSENCE. This is the whole reason
-- items 2 and 4 are one fault.
ok(areaDataC:find("// Return the dummy box model if the requested one is not loaded", 1, true),
   "the dummy-box fallback comment is gone from GetMapPropModelFile")
local fallback = areaDataC:match(
  "AreaDataManager_GetMapPropModelFile.-\n}")
ok(fallback and fallback:find("mapPropModelFiles[mapPropModelID] == NULL", 1, true)
   and fallback:find("return &areaDataManager->mapPropModelFiles[0];", 1, true),
   "GetMapPropModelFile no longer falls back to member 0")
ok(mapPropC:match("if %(AreaDataManager_HasMapPropModelFile%(areaDataManager, loadedProp%->modelID%) == FALSE%)%s*{%s*"
   .. "loadedProp%->modelID = 0;"),
   "map_prop.c no longer forces an unloaded prop's modelID to 0")
-- ...and that member 0 is guaranteed resident, which is what makes the fallback
-- safe on the cartridge and a guaranteed VISIBLE artefact in the port.
ok(areaDataC:find('// Make sure the dummy box ("dmybox00") model is always loaded', 1, true),
   "the guarantee that member 0 is always loaded is gone")

-- The prop texture is bound per area, so a prop without its area's texture set is
-- untextured rather than merely mis-tinted.
ok(areaDataC:find("Easy3D_BindTextureToResource(areaDataManager->mapPropModelFiles[mapPropModelID], areaDataManager->mapPropTexture)", 1, true),
   "props are no longer bound to their area's prop texture")
ok(areaDataC:find("AREA_BUILD_MODEL__AREABM_TEXSET", 1, true),
   "the prop texture set no longer comes from areabm_texset")
-- ...and it is read with the SAME member index as the prop list.
ok(areaDataC:match("AREABM_TEXSET,%s*areaDataManager%->areaData%.mapPropArchivesID"),
   "the prop texture set is no longer selected by mapPropArchivesID, so pairing "
   .. "area_build and areabm_texset by index is no longer right")

-- ---------------------------------------------------------------------------
section("2. the archives, and the list shape on every member")
-- ---------------------------------------------------------------------------
local rom = assert(NdsRom.open(romPath))
local function arc(p)
  local b = rom:read(p)
  return b and Narc.parse(b)
end
local buildArc, texArc, modelArc = arc(AREA_BUILD), arc(AREA_TEXSET), arc(BUILD_MODEL)
ok(buildArc, "%s is not in the ROM", AREA_BUILD)
ok(texArc, "%s is not in the ROM", AREA_TEXSET)
ok(modelArc, "%s is not in the ROM", BUILD_MODEL)
buildArc = buildArc or { count = 0 }
ok(buildArc.count == 71, "area_build has %d members, expected 71", buildArc.count)
ok(texArc and texArc.count == buildArc.count,
   "areabm_texset has %s members and area_build has %d -- they are indexed "
   .. "together, so a length mismatch breaks the pairing",
   tostring(texArc and texArc.count), buildArc.count)
ok(modelArc and modelArc.count == 590,
   "build_model has %s members, expected 590", tostring(modelArc and modelArc.count))

local lists, distinct, highest, largest, refused = {}, {}, -1, 0, 0
for m = 0, buildArc.count - 1 do
  local bytes = buildArc:get(m)
  local list, err = Gen4Maps.areaBuildings(bytes)
  ok(list, "area_build member %d refused: %s", m, tostring(err))
  if list then
    lists[m] = list
    if #list > largest then largest = #list end
    -- The shape is exact, not merely sufficient: the member is the count and
    -- then that many u16s with nothing left over. `areaBuildings` enforces it,
    -- and this re-derives the count here so both would have to be wrong together.
    local count = bytes:byte(1) + bytes:byte(2) * 256
    ok(count == #list,
       "member %d: the leading u16 says %d but the list has %d", m, count, #list)
    ok(2 + count * 2 == #bytes,
       "member %d: %d ids is %d bytes but the member is %d", m, count, 2 + count * 2, #bytes)
    ok(count < maxFiles,
       "member %d holds %d ids, past MAX_MAP_PROP_MODEL_FILES %s",
       m, count, tostring(maxFiles))
    for _, id in ipairs(list) do
      distinct[id] = true
      if id > highest then highest = id end
      ok(modelArc and id < modelArc.count,
         "member %d names prop %d, past build_model's %s members",
         m, id, tostring(modelArc and modelArc.count))
    end
  else
    refused = refused + 1
  end
end
ok(refused == 0, "%d members refused to decode", refused)
ok(largest == 138, "the largest list is %d, expected 138", largest)
local n = 0
for _ in pairs(distinct) do n = n + 1 end
ok(n == 527, "%d distinct prop ids across the areas, expected 527", n)
ok(highest == 589, "the highest prop id is %d, expected 589", highest)

-- ...and that the texture sets are genuinely distinct members, so pairing them by
-- index says something. If they were all byte-identical, "member m" and "member
-- 0" would be the same picture and the pairing would be untestable either way.
local texSeen, texDistinct = {}, 0
for m = 0, (texArc and texArc.count or 0) - 1 do
  local bytes = texArc:get(m) or ""
  ok(bytes:sub(1, 4) == "BTX0",
     "areabm_texset member %d is not an NSBTX (magic %q)", m, bytes:sub(1, 4))
  if not texSeen[bytes] then
    texSeen[bytes] = true
    texDistinct = texDistinct + 1
  end
end
ok(texDistinct > 1,
   "all %d prop texture sets are byte-identical, so pairing by index cannot be "
   .. "distinguished from always reading member 0", texDistinct)

-- THE IDS ARE NOT POSITIONS. If every list were 0,1,2,... then indexing by
-- position and indexing by id would agree and nothing above could tell them
-- apart -- so the gaps are what make the sparse rule testable.
local sparse = 0
for m, list in pairs(lists) do
  for i, id in ipairs(list) do
    if id ~= i - 1 then sparse = sparse + 1 end
  end
end
ok(sparse > 0,
   "every prop id equals its position in its list, so this check cannot tell a "
   .. "global id from a list index")

-- ---------------------------------------------------------------------------
section("3. the dummy box is really the dummy box")
-- ---------------------------------------------------------------------------
-- pret names it in a comment; the ROM has to agree, or "an unresolved prop draws
-- a grey box" is a story rather than a finding.
local member0 = modelArc and modelArc:get(0)
ok(member0, "build_model member 0 could not be read")
ok(member0 and member0:find("dmybox", 1, true),
   "build_model member 0 does not contain the string dmybox -- the model the "
   .. "cartridge falls back to is not the one pret names")
ok(member0 and member0:sub(1, 4) == "BMD0",
   "build_model member 0 is not an NSBMD (magic %q)",
   tostring(member0 and member0:sub(1, 4)))

-- ---------------------------------------------------------------------------
section("4. every placement resolves through its own area")
-- ---------------------------------------------------------------------------
-- THE MEASUREMENT THE WHOLE READING RESTS ON. If a map's chunks named props its
-- own area does not load, then either the association is wrong or the cartridge
-- draws boxes there. Walking it settles which.
local areaArc, matArc, landArc = arc("/fielddata/areadata/area_data.narc"),
  arc("/fielddata/mapmatrix/map_matrix.narc"), arc("/fielddata/land_data/land_data.narc")
local encArc, evArc = arc("/fielddata/encountdata/pl_enc_data.narc"),
  arc("/fielddata/eventdata/zone_event.narc")
local scrArc, msgArc = arc("/fielddata/script/scr_seq.narc"), arc("/msgdata/pl_msg.narc")
ok(areaArc and matArc and landArc, "the field archives did not all parse")

local arm9 = assert(rom:arm9())
local at, headerCount = Gen4MapHeaders.find(arm9, {
  areaData = areaArc.count, matrix = matArc.count, scripts = scrArc.count,
  messages = msgArc.count, encounters = encArc.count, events = evArc.count,
  names = 1000,
})
ok(at, "the map header table was not found in the ARM9")
local headers = at and Gen4MapHeaders.all(arm9, at, headerCount) or {}

-- Every chunk parsed ONCE: land_data is 16 MB and re-parsing it per map turns
-- this section into minutes.
local chunkObjects = {}
for cid = 0, landArc.count - 1 do
  local ch = Gen4Terrain.chunk(landArc:get(cid))
  chunkObjects[cid] = (ch and ch.objects) or {}
end

local allow = {}
for m, list in pairs(lists) do
  local set = {}
  for _, id in ipairs(list) do set[id] = true end
  allow[m] = set
end

-- Grouped by MATRIX, because a matrix is the map's geometry and several maps
-- share one -- 270 matrices serve the 593 headers, so counting per map weights
-- the shared ones by however many maps point at them.
local byMatrix = {}
for _, h in pairs(headers) do
  byMatrix[h.matrix] = byMatrix[h.matrix] or h.areaData
end
local covered, uncovered, propless, totalPlacements = 0, 0, 0, 0
local worst = { miss = -1 }
for mx, areaId in pairs(byMatrix) do
  local grid = Gen4Terrain.grid(Gen4Maps.matrix(matArc:get(mx)))
  local ids, placements, seen = {}, 0, {}
  for _, cid in ipairs((grid and grid.land) or {}) do
    if cid and chunkObjects[cid] and not seen[cid] then
      seen[cid] = true
      for _, o in ipairs(chunkObjects[cid]) do
        ids[o.model] = true
        placements = placements + 1
      end
    end
  end
  totalPlacements = totalPlacements + placements
  if placements == 0 then
    propless = propless + 1
  else
    local area = Gen4Maps.areaData(areaArc:get(areaId))
    local set = (area and allow[area.buildings]) or {}
    local miss = 0
    for id in pairs(ids) do if not set[id] then miss = miss + 1 end end
    if miss == 0 then covered = covered + 1
    else
      uncovered = uncovered + 1
      if miss > worst.miss then worst = { miss = miss, mx = mx, placements = placements } end
    end
  end
end
ok(covered == 201,
   "%d matrices are fully covered by their own area's prop list, expected 201",
   covered)
ok(uncovered == 3,
   "%d matrices name props their own area does not load, expected 3 -- on the "
   .. "cartridge those draw dmybox00", uncovered)
ok(propless == 66, "%d matrices carry no props, expected 66", propless)
ok(covered + uncovered + propless == 270,
   "%d matrices accounted for, expected 270", covered + uncovered + propless)
-- A bound that can only be met by everything passing is not a bound: the three
-- uncovered matrices are what makes "covered" a measurement rather than a
-- tautology, so the worst one is pinned too.
ok(worst.miss == 101,
   "the worst-covered matrix misses %d prop ids, expected 101", worst.miss)
ok(worst.mx == 0,
   "the worst-covered matrix is %s, expected 0", tostring(worst.mx))
-- 2,967 IS THE DISTINCT TOTAL, and the number is worth pinning because the
-- obvious way to count gives a much bigger one. Counting per MAP instead of per
-- matrix reports 47,029: 593 headers share 270 matrices, so every chunk of a
-- shared matrix is counted once per map pointing at it. The cartridge draws each
-- placement once, so the per-matrix figure is the real one.
ok(totalPlacements == 2967,
   "%d prop placements across the cartridge, expected 2967", totalPlacements)

-- ---------------------------------------------------------------------------
section("5. the port carries the index that chooses the list")
-- ---------------------------------------------------------------------------
-- `mapPropArchivesID` is AreaDataFile offset 0. Without it on the map record, a
-- prop id cannot be resolved at all -- and this is the field the terrain stage
-- did not carry until the prop stage was added.
local synth = string.char(0x07, 0x00, 0x22, 0x00, 0x33, 0x00, 0x01, 0x00)
local dec = Gen4Maps.areaData(synth)
ok(dec and dec.buildings == 0x07,
   "areaData's `buildings` is %s, but mapPropArchivesID is offset 0",
   tostring(dec and dec.buildings))
local extractor = io.open(root .. "../src/import/RomExtractorGen4.lua", "rb")
  or io.open("src/import/RomExtractorGen4.lua", "rb")
ok(extractor, "RomExtractorGen4.lua could not be read")
if extractor then
  local text = extractor:read("a"); extractor:close()
  ok(text:find("props = area.buildings", 1, true),
     "the terrain stage does not carry `props` onto its map records, so nothing "
     .. "downstream can choose a prop list")
  ok(text:find('self:write("gen4_mapprops"', 1, true),
     "nothing writes gen4_mapprops")
  ok(text:find("self:mapProps()", 1, true), "the mapProps stage is never called")
  -- THE POINT OF THIS FILE: areaBuildings had no caller for as long as it
  -- existed. One is now required to remain.
  -- THE TEXTURE SET MUST BE PAIRED BY THE LOOP VARIABLE, NOT BY A CONSTANT.
  -- A planted `texture = 0` passed everything else in this file: the archives are
  -- the same length and every member is a real NSBTX, so nothing in the DATA
  -- distinguishes "paired by index" from "always member 0". The pairing lives in
  -- the code, so this is where it has to be asserted.
  -- Anchored inside `mapProps`: the extractor has other `texture =` assignments
  -- (the terrain texture sets), and a match from the top of the file finds one of
  -- those instead. Matching the wrong line made this assertion fail on correct
  -- code and pass on a planted fault at the same time.
  local propsFn = text:match("function RomExtractorGen4:mapProps.-\n" .. "end\r?\n")
    or text:match("function RomExtractorGen4:mapProps.-[\r\n]end[\r\n]")
  ok(propsFn, "the mapProps function could not be isolated from the extractor")
  local texLine = (propsFn or ""):match("texture = ([^\r\n]-),")
  ok(texLine and texLine:find("m", 1, true) and not texLine:match("^%s*%d+%s*$"),
     "the prop texture set is assigned as %q -- it must be derived from the "
     .. "member index, since areabm_texset is read with the same index as "
     .. "area_build", tostring(texLine))
  -- AND THE DRAW LISTS MUST ACTUALLY REACH THE TABLE.
  -- Section 6 parses `build_model_matshp.dat` itself, so it passes whether or not
  -- the extractor keeps what it read -- a planted `out.draw = nil` sailed straight
  -- through it. That is the write-and-never-read family in reverse: data decoded
  -- correctly and then dropped on the floor.
  ok(propsFn and propsFn:find("out.draw = shapes.lists", 1, true),
     "the mapProps stage parses the prop draw lists but does not put them in the "
     .. "table it writes")
  ok(propsFn and propsFn:find("Gen4PropShapes.parse", 1, true),
     "nothing in mapProps parses the material shape file")
  ok(text:find('require("src.import.Gen4PropShapes")', 1, true),
     "the extractor no longer requires Gen4PropShapes")
  ok(text:find("Gen4Maps.areaBuildings", 1, true),
     "nothing calls Gen4Maps.areaBuildings any more -- it is a decoder with no "
     .. "caller again, which is how the prop lists went unread in the first place")
end
local data = io.open(root .. "../src/core/Data.lua", "rb") or io.open("src/core/Data.lua", "rb")
if data then
  local text = data:read("a"); data:close()
  ok(text:find('"gen4_mapprops"', 1, true),
     "gen4_mapprops is not in Data.lua's GEN4_PREFIXED, so it would be written "
     .. "and never loaded")
end

-- ---------------------------------------------------------------------------
section("6. the draw list, which is the order and not an enumeration")
-- ---------------------------------------------------------------------------
-- `MapProp_Draw` issues one `NNS_G3dDraw1Mat1Shp` per (material, shape) pair out
-- of `build_model_matshp.dat`, so that file is the prop's draw ORDER. Read the
-- loop out of pret rather than restating it.
local drawLoop = mapPropC:match("MapProp_GetMaterialShapeIDsLocator.-\n}")
ok(drawLoop, "the MapProp draw loop could not be isolated from map_prop.c")
drawLoop = drawLoop or ""
ok(drawLoop:find("NNS_G3dDraw1Mat1Shp(model, materialID, propMatShpIDs[i].shapeID, sendMaterial)", 1, true),
   "the draw call is no longer one Draw1Mat1Shp per pair")
-- `u8 materialID = 0xFF` before the loop is what makes the FIRST pair always send
-- its material: no prop uses material 255.
ok(drawLoop:find("u8 materialID = 0xFF;", 1, true),
   "the draw loop no longer seeds materialID with 0xFF, so the first pair's "
   .. "sendMaterial is no longer guaranteed true")
ok(drawLoop:find("if (materialID != propMatShpIDs[i].materialID)", 1, true),
   "sendMaterial is no longer decided by comparing against the previous material")
-- And the loader's four reads, in order, which is the whole file format.
local matShpC = slurp("src/overlay005/map_prop_material_shape.c") or ""
ok(matShpC:find("FS_ReadFile(&file, &idsLocatorsCount, 2)", 1, true),
   "the locator count is no longer the first u16 of the file")
ok(matShpC:find("FS_ReadFile(&file, &idsCount, 2)", 1, true),
   "the pair count is no longer the second u16 of the file")
ok(matShpC:find("idsLocators[modelID].idsCount", 1, true),
   "the locator array is no longer indexed by prop model id")

local shapeBytes = rom:read(Gen4PropShapes.PATH)
ok(shapeBytes, "%s is not in the ROM", Gen4PropShapes.PATH)
ok(shapeBytes and #shapeBytes == 6400,
   "the material shape file is %s bytes, expected 6400",
   tostring(shapeBytes and #shapeBytes))
local shapes, shapeErr = Gen4PropShapes.parse(shapeBytes)
ok(shapes, "the material shape file did not parse: %s", tostring(shapeErr))
shapes = shapes or { lists = {}, models = 0, pairs = 0 }

-- THE LOCATOR ARRAY COVERS THE WHOLE PROP ARCHIVE, exactly. 590 and 590 is what
-- says the locators are indexed by prop model id rather than by something else
-- that happens to be about the same size.
ok(shapes.models == (modelArc and modelArc.count),
   "%d locators against %s build_model members -- the locator array is indexed "
   .. "by prop model id, so these must be equal",
   shapes.models, tostring(modelArc and modelArc.count))
ok(shapes.pairs == 1009, "%d pairs, expected 1009", shapes.pairs)

local nonEmpty, totalPairs, sends, holds = 0, 0, 0, 0
local permuted, matNotAscending, maxList = 0, 0, 0
for m = 0, shapes.models - 1 do
  local list = shapes.lists[m]
  if list then
    nonEmpty = nonEmpty + 1
    if #list > maxList then maxList = #list end
    local lastMat, lastShape, ascMat, ascShape = -1, -1, true, true
    for i, pair in ipairs(list) do
      totalPairs = totalPairs + 1
      if pair.sendMaterial then sends = sends + 1 else holds = holds + 1 end
      -- The rule is decided against the PREVIOUS pair, so it can be re-derived
      -- here independently of how `parse` computed it.
      local expect = (pair.material ~= lastMat)
      ok(pair.sendMaterial == expect,
         "model %d pair %d: sendMaterial is %s but the material went %d -> %d",
         m, i, tostring(pair.sendMaterial), lastMat, pair.material)
      if pair.material < lastMat then ascMat = false end
      if pair.shape < lastShape then ascShape = false end
      lastMat, lastShape = pair.material, pair.shape
    end
    if not ascShape then permuted = permuted + 1 end
    if not ascMat then matNotAscending = matNotAscending + 1 end
  end
end
ok(nonEmpty == 478, "%d models have a draw list, expected 478", nonEmpty)
ok(shapes.models - nonEmpty == 112,
   "%d models have none, expected 112", shapes.models - nonEmpty)
ok(totalPairs == shapes.pairs,
   "the lists hold %d pairs but the header says %d", totalPairs, shapes.pairs)
ok(maxList == 9, "the longest draw list is %d, expected 9", maxList)

-- THE ORDER IS THE POINT, AND THIS IS WHERE THAT IS PROVED.
-- If every list ran materials and shapes in ascending order, the file would carry
-- no information a renderer could not get from the model itself, and extracting it
-- would be pointless. It does not.
ok(permuted == 160,
   "%d lists have a non-ascending shape order, expected 160 -- if this were 0 "
   .. "the draw list would be an enumeration and not an order", permuted)
ok(matNotAscending == 3,
   "%d lists draw their materials out of ascending order, expected 3", matNotAscending)
-- Those three are models 22, 23 and 236, and each draws MATERIAL 0 LAST after
-- 1..4, which is what translucency ordering looks like.
for _, m in ipairs({ 22, 23, 236 }) do
  local list = shapes.lists[m]
  ok(list, "model %d has no draw list", m)
  if list then
    ok(list[1].material == 1,
       "model %d starts on material %d, expected 1", m, list[1].material)
    ok(list[#list].material == 0,
       "model %d ends on material %d, expected 0 -- material 0 is drawn last here",
       m, list[#list].material)
  end
end

-- THE sendMaterial OPTIMISATION FIRES EXACTLY ONCE IN THE WHOLE CARTRIDGE.
-- 1008 of the 1009 pairs change material. Pinning the count is what stops a
-- renderer from "simplifying" the rule away: it would be right 1008 times and
-- wrong on model 175, which is precisely the kind of fault that never gets found.
ok(sends == 1008, "%d pairs send their material, expected 1008", sends)
ok(holds == 1,
   "%d pairs reuse the previous material, expected exactly 1 -- if this were 0 "
   .. "the sendMaterial rule would be untestable on this cartridge", holds)
local m175 = shapes.lists[175]
ok(m175 and #m175 == 2, "model 175 has %s pairs, expected 2",
   tostring(m175 and #m175))
if m175 then
  ok(m175[1].material == 0 and m175[1].shape == 0 and m175[1].sendMaterial,
     "model 175's first pair is (m%d,s%d) send=%s, expected (m0,s0) send=true",
     m175[1].material, m175[1].shape, tostring(m175[1].sendMaterial))
  ok(m175[2].material == 0 and m175[2].shape == 1 and not m175[2].sendMaterial,
     "model 175's second pair is (m%d,s%d) send=%s -- it is the ONE pair in the "
     .. "cartridge that reuses its material",
     m175[2].material, m175[2].shape, tostring(m175[2].sendMaterial))
end

-- AN EMPTY LOCATOR CARRIES 0xFFFF, AND THE TWO FIELDS NEVER DISAGREE.
-- On the cartridge the sentinel is harmless because the loop runs zero times, but
-- a reader that resolves the index before checking the count indexes 65535 into a
-- 1009-entry array. Checked straight off the bytes, since `parse` deliberately
-- stores nothing for an empty list.
local sentinels, wrongSentinel, countedEmpty = 0, 0, 0
for m = 0, shapes.models - 1 do
  local at = Gen4PropShapes.HEADER_BYTES + m * Gen4PropShapes.RECORD_BYTES
  local count = shapeBytes:byte(at + 1) + shapeBytes:byte(at + 2) * 256
  local index = shapeBytes:byte(at + 3) + shapeBytes:byte(at + 4) * 256
  if count == 0 then
    countedEmpty = countedEmpty + 1
    if index == Gen4PropShapes.NO_INDEX then sentinels = sentinels + 1
    else wrongSentinel = wrongSentinel + 1 end
  else
    ok(index ~= Gen4PropShapes.NO_INDEX,
       "model %d has %d pairs and the sentinel as its index", m, count)
    ok(index + count <= shapes.pairs,
       "model %d runs from %d for %d, past %d pairs", m, index, count, shapes.pairs)
  end
end
ok(countedEmpty == 112, "%d empty locators, expected 112", countedEmpty)
ok(sentinels == 112 and wrongSentinel == 0,
   "%d of %d empty locators carry 0xFFFF -- the count and the sentinel must "
   .. "always agree", sentinels, countedEmpty)
-- ...and that `parse` refuses a file whose length does not close exactly, since
-- the two counts and the size determine each other.
ok(Gen4PropShapes.parse(shapeBytes .. "\0\0\0\0") == nil,
   "parse accepted a file with four bytes of slack on the end")
ok(Gen4PropShapes.parse(shapeBytes:sub(1, #shapeBytes - 4)) == nil,
   "parse accepted a file four bytes short")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
