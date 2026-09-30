-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the Underground's mining art extracts at the size the
-- cartridge states, that those sizes agree with a completely separate source,
-- and -- the part that matters most -- that inviting the extractor to believe a
-- sheet's own header changes NOTHING for any archive that did not ask for it.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: `preferDeclaredSize` looks like a
-- harmless improvement that should simply be the default. It is not. Of the 258
-- sheets laid out by a chosen width, 65 declare their own tilesX/tilesY, and
-- TWENTY-SIX of those are currently drawn at a width the file contradicts --
-- pl_winframe's message boxes are declared 6x3 and laid out at 8. Switching it on
-- globally redraws twenty-six existing pictures, several of them visible UI. So
-- section 3 asserts the opposite of the usual thing: that the change is inert
-- everywhere except where it was asked for, and section 4 pins the twenty-six so
-- the number cannot move unnoticed.
--
-- It calls the extractor's real `composeJob` rather than restating its three-line
-- precedence: the function touches no `self` (checked -- zero references in its
-- 75 lines), so a dummy receiver exercises the shipped decision itself.
--
-- Usage: texlua tools/gen4_mining_art_check.lua <rom>

local romPath = arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_mining_art_check.lua <rom>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom   = require("src.import.NdsRom")
local Narc     = require("src.import.NarcArchive")
local Graphics = require("src.import.Gen4Graphics")
local Screens  = require("src.import.Gen4Screens")
local Archives = require("src.import.Gen4Archives")
local Mining   = require("src.import.Gen4Mining")
local Extractor = require("src.import.RomExtractorGen4")

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

local UG = { ["/data/ug_parts.narc"] = true, ["/data/ug_fossil.narc"] = true }

-- ---------------------------------------------------------------------------
section("1. the archives are in the plan, and the ROM has them")
-- ---------------------------------------------------------------------------
local entries = {}
for _, a in ipairs(Screens.ARCHIVES) do
  if UG[a.path] then entries[a.path] = a end
end
for path in pairs(UG) do
  ok(entries[path] ~= nil, "%s is not in Gen4Screens.ARCHIVES", path)
  local raw = rom:read(path)
  ok(raw ~= nil, "%s is not in this ROM", path)
  if raw and entries[path] then
    local narc = Narc.parse(raw)
    local names = Archives.names(path)
    io.write(("  %-24s %3d members, %3d names, out=%s, preferDeclaredSize=%s\n")
             :format(path, narc.count, names and #names or -1,
                     tostring(entries[path].out),
                     tostring(entries[path].preferDeclaredSize)))
    -- A NARC has no directory, so the only thing tying a name to an index is
    -- the count agreeing. If it does not, every name is off by something.
    ok(names ~= nil and #names == narc.count,
       "%s: %d members but %s names -- the name table does not fit this archive",
       path, narc.count, names and #names or "no")
    ok(entries[path].preferDeclaredSize == true,
       "%s must set preferDeclaredSize; its sheets state their own sizes", path)
  end
end

-- ---------------------------------------------------------------------------
section("2. every ug_parts sheet states its own size, and the sizes are right")
-- ---------------------------------------------------------------------------
-- The other source: Gen4Mining.OBJECTS, whose sizes come from sMiningObjects,
-- compiled into an ARM9 overlay -- nothing to do with the NCGR headers. Two tiles
-- per mining cell, because Mining_DrawBuriedObject indexes the tilemap in tiles
-- and strides by the record's stored width, which is cells * 2.
local want = {}
for _, o in ipairs(Mining.OBJECTS) do
  local n = o.sprite:gsub("_NCGR$", ".NCGR")
  want[n] = want[n] or {}
  want[n][(o.w * 2) .. "x" .. (o.h * 2)] = true
end
local narc = Narc.parse(rom:read("/data/ug_parts.narc"))
local names = Archives.names("/data/ug_parts.narc")
local sheets, declared, agreed, notInTable = 0, 0, 0, {}
for i, n in ipairs(names or {}) do
  if n:match("%.NCGR$") then
    sheets = sheets + 1
    local data = narc:get(i - 1)
    if data and Graphics.isCompressed(data) then data = Graphics.decompress(data) end
    local sheet = data and Graphics.tiles(data)
    ok(sheet ~= nil, "%s did not decode as a tile sheet", n)
    if sheet then
      if sheet.tilesX and sheet.tilesY then declared = declared + 1 end
      ok(sheet.tilesX ~= nil and sheet.tilesY ~= nil,
         "%s declares no tilesX/tilesY, so preferDeclaredSize cannot help it "
         .. "and it needs a width written down", n)
      local w = want[n]
      if not w then notInTable[#notInTable + 1] = n
      elseif sheet.tilesX then
        local hit = false
        for s in pairs(w) do
          local ww, hh = s:match("(%d+)x(%d+)")
          if tonumber(ww) == sheet.tilesX and tonumber(hh) == sheet.tilesY then hit = true end
        end
        if hit then agreed = agreed + 1 end
        local list = {}
        for s in pairs(w) do list[#list + 1] = s end
        table.sort(list)
        ok(hit, "%s declares %dx%d but the mining table says %s",
           n, sheet.tilesX, sheet.tilesY, table.concat(list, " or "))
      end
    end
  end
end
io.write(("  %d NCGR members, %d declare a size, %d agree with the mining table\n")
         :format(sheets, declared, agreed))
io.write(("  not in the mining table: %s\n"):format(
  #notInTable > 0 and table.concat(notInTable, ", ") or "none"))
ok(sheets == 71, "expected 71 NCGR members in ug_parts, found %d", sheets)
ok(declared == sheets, "%d of %d sheets declare a size", declared, sheets)
ok(agreed == 70, "expected 70 of 71 to match the mining table, got %d", agreed)
-- dirt_tiles is the seven layers of earth, not a buried object, so it is right
-- that the mining table has no size for it.
ok(#notInTable == 1 and notInTable[1] == "dirt_tiles.NCGR",
   "expected only dirt_tiles.NCGR to be absent from the mining table, got %s",
   table.concat(notInTable, ", "))

-- ---------------------------------------------------------------------------
section("3. the change is inert for every archive that did not ask")
-- ---------------------------------------------------------------------------
-- composeJob returns the layout's provenance. Anything other than "fallback" or
-- "stated" on an archive without the flag would mean the new branch reached it.
local touched, sheetsSeen, byProvenance = {}, 0, {}
for _, a in ipairs(Screens.ARCHIVES) do
  local raw = rom:read(a.path)
  if raw then
    local arc = Narc.parse(raw)
    for _, job in ipairs(Screens.plan(a.path, a) or {}) do
      if not job.tilemap then
        sheetsSeen = sheetsSeen + 1
        local _, layout = Extractor.composeJob({}, arc, job)
        if layout then
          byProvenance[layout] = (byProvenance[layout] or 0) + 1
          if layout == "declared" and not UG[a.path] then
            touched[#touched + 1] = a.path .. " / " .. tostring(job.name)
          end
        end
      end
    end
  end
end
local parts = {}
for k, v in pairs(byProvenance) do parts[#parts + 1] = ("%s=%d"):format(k, v) end
table.sort(parts)
io.write(("  %d sheets: %s\n"):format(sheetsSeen, table.concat(parts, " ")))
ok(#touched == 0,
   "%d sheets outside the Underground archives took the declared-size branch, "
   .. "so this change is NOT inert: %s", #touched,
   table.concat(touched, "; ", 1, math.min(#touched, 4)))
ok((byProvenance.declared or 0) > 0,
   "no sheet anywhere took the declared-size branch, so section 3 is asserting "
   .. "that an unreachable branch was not reached, which says nothing")
ok((byProvenance.stated or 0) > 0 and (byProvenance.fallback or 0) > 0,
   "the stated and fallback branches are not both exercised (stated=%d fallback=%d)",
   byProvenance.stated or 0, byProvenance.fallback or 0)

-- ---------------------------------------------------------------------------
section("4. the twenty-six sheets this could fix, pinned")
-- ---------------------------------------------------------------------------
-- Not fixed here, deliberately. Pinned so the number cannot drift quietly, and
-- so whoever turns preferDeclaredSize on for pl_winframe knows what they are
-- signing up to redraw.
local declaresElsewhere, contradicted, examples = 0, 0, {}
for _, a in ipairs(Screens.ARCHIVES) do
  if not UG[a.path] then
    local raw = rom:read(a.path)
    if raw then
      local arc = Narc.parse(raw)
      for _, job in ipairs(Screens.plan(a.path, a) or {}) do
        if not job.tilemap then
          local data = job.tiles and arc:get(job.tiles)
          if data and Graphics.isCompressed(data) then data = Graphics.decompress(data) end
          local sheet = data and Graphics.tiles(data)
          if sheet and sheet.tilesX then
            declaresElsewhere = declaresElsewhere + 1
            if sheet.tilesX ~= (job.tilesWide or 8) then
              contradicted = contradicted + 1
              if #examples < 4 then
                examples[#examples + 1] = ("%s/%s laid out at %d, declares %dx%d")
                  :format(a.path:match("([^/]+)%.narc$") or a.path,
                          tostring(job.name), job.tilesWide or 8,
                          sheet.tilesX, sheet.tilesY)
              end
            end
          end
        end
      end
    end
  end
end
io.write(("  outside the Underground: %d sheets declare a size, %d are drawn at "
          .. "a width the file contradicts\n"):format(declaresElsewhere, contradicted))
for _, e in ipairs(examples) do io.write("    " .. e .. "\n") end
ok(declaresElsewhere == 65, "expected 65 declaring sheets elsewhere, found %d",
   declaresElsewhere)
ok(contradicted == 26,
   "expected 26 contradicted widths, found %d -- if this moved, either the "
   .. "widths changed or preferDeclaredSize was turned on somewhere new",
   contradicted)

-- ---------------------------------------------------------------------------
section("5. tilesWideStated marks exactly the written-down widths")
-- ---------------------------------------------------------------------------
-- The whole precedence rests on telling a measured 8 from the archive default 8.
for _, a in ipairs(Screens.ARCHIVES) do
  for _, job in ipairs(Screens.plan(a.path, a) or {}) do
    local named = (a.tilesWideFor and a.tilesWideFor[job.name]) ~= nil
    ok((job.tilesWideStated == true) == named,
       "%s/%s: tilesWideStated=%s but tilesWideFor %s it",
       a.path, tostring(job.name), tostring(job.tilesWideStated),
       named and "names" or "does not name")
  end
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)