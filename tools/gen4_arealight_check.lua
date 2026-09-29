-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the area lights this port extracts are the cartridge's
-- own, and that the u16 selecting them is the u16 the cartridge selects on.
--
-- The second half is the reason this file exists. `Gen4Maps.areaData` used to
-- name `AreaDataFile`'s offset 4 `lighting` and offset 6 `flags`, which is
-- backwards -- pret calls offset 4 `dummy04` and documents it as unused, and
-- offset 6 is `areaLightArchiveID`. The terrain stage carried the dead one onto
-- all 593 maps, and because nothing read it there was no consumer to be wrong.
--
-- So every constant here is looked up BY NAME in pret rather than written down:
-- AREA_LIGHT_FILE_COUNT, INVALID_LIGHT_COLOR, SCRATCH_BUFFER_SIZE and the field
-- ORDER of the AreaDataFile struct all come out of the source text. A check that
-- hard-codes 4 cannot notice pret saying 5.
--
-- Usage: texlua tools/gen4_arealight_check.lua <rom> <pokeplatinum dir>

local romPath, pretDir = arg[1], arg[2]
if not romPath or not pretDir then
  io.stderr:write("usage: texlua tools/gen4_arealight_check.lua <rom> <pokeplatinum dir>\n")
  os.exit(2)
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc   = require("src.import.NarcArchive")
local AL     = require("src.import.Gen4AreaLight")
local Gen4Maps = require("src.import.Gen4Maps")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(name) io.write(("\n-- %s\n"):format(name)) end

local function slurp(rel)
  local f = io.open(pretDir .. "/" .. rel, "rb")
  if not f then return nil end
  local s = f:read("a"); f:close(); return s
end

-- ---------------------------------------------------------------------------
section("1. the cartridge's own constants, read out of pret by name")
-- ---------------------------------------------------------------------------
local areaLightC = slurp("src/overlay005/area_light.c")
ok(areaLightC, "src/overlay005/area_light.c not found under %s", tostring(pretDir))
areaLightC = areaLightC or ""

local function define(name, text)
  return tonumber((text or ""):match("#define%s+" .. name .. "%s+(0?x?%x+)")) or
         tonumber((text or ""):match("#define%s+" .. name .. "%s+(%d+)"))
end

local fileCount = define("AREA_LIGHT_FILE_COUNT", areaLightC)
ok(fileCount, "AREA_LIGHT_FILE_COUNT not found in area_light.c")
ok(fileCount == AL.FILE_COUNT,
   "AREA_LIGHT_FILE_COUNT is %s in pret but FILE_COUNT is %d here",
   tostring(fileCount), AL.FILE_COUNT)

local invalid = define("INVALID_LIGHT_COLOR", areaLightC)
ok(invalid == AL.INVALID_COLOUR,
   "INVALID_LIGHT_COLOR is %s in pret but INVALID_COLOUR is 0x%X here",
   tostring(invalid), AL.INVALID_COLOUR)

local scratch = define("SCRATCH_BUFFER_SIZE", areaLightC)
ok(scratch == 256, "SCRATCH_BUFFER_SIZE is %s, expected 256", tostring(scratch))

-- GX_LIGHTS_COUNT bounds the light loop in ApplyToModelAttributes, so the loop
-- text is where its value has to agree with ours.
ok(areaLightC:find("for %(int i = 0; i < GX_LIGHTS_COUNT; i%+%+%)"),
   "the GX_LIGHTS_COUNT loop is not in ApplyToModelAttributes any more")
ok(AL.LIGHTS == 4, "LIGHTS is %d, but the DS has four light slots", AL.LIGHTS)

-- The archive path, from the NARC constant rather than from memory.
ok(areaLightC:find("NARC_INDEX_DATA__AREALIGHT", 1, true),
   "area_light.c no longer loads NARC_INDEX_DATA__AREALIGHT")
ok(AL.PATH == "/data/arealight.narc", "PATH is %q", AL.PATH)

-- ---------------------------------------------------------------------------
section("2. AreaDataFile's field order, out of pret's struct")
-- ---------------------------------------------------------------------------
-- THE CHECK THAT WOULD HAVE CAUGHT THE SWAP. Read the struct body and take the
-- u16 names in declared order; the third is the dead one and the fourth selects
-- the light.
local areaDataH = slurp("include/overlay005/area_data.h")
ok(areaDataH, "include/overlay005/area_data.h not found")
local body = (areaDataH or ""):match("typedef struct AreaDataFile%s*{(.-)}%s*AreaDataFile;")
ok(body, "the AreaDataFile struct is not in area_data.h any more")
local order = {}
for name in (body or ""):gmatch("u16%s+([%w_]+)%s*;") do order[#order + 1] = name end
ok(#order == 4, "AreaDataFile declares %d u16 fields, expected 4", #order)
ok(order[1] == "mapPropArchivesID", "field 0 is %q", tostring(order[1]))
ok(order[2] == "mapTextureArchiveID", "field 1 is %q", tostring(order[2]))
ok(order[3] == "dummy04", "field 2 is %q, expected the unused dummy04", tostring(order[3]))
ok(order[4] == "areaLightArchiveID",
   "field 3 is %q -- if pret moved areaLightArchiveID, Gen4Maps.areaData's "
   .. "offset 6 is now the wrong u16", tostring(order[4]))

-- ...and that our decoder puts them at the offsets that order implies. A
-- synthetic record with a distinct value per slot is the only way to tell an
-- offset apart from its neighbour.
local synth = string.char(0x11,0x00, 0x22,0x00, 0x33,0x00, 0x02,0x00)
local dec = Gen4Maps.areaData(synth)
ok(dec, "areaData refused an 8-byte record")
if dec then
  ok(dec.buildings == 0x11, "offset 0 decoded as %s", tostring(dec.buildings))
  ok(dec.mapTexture == 0x22, "offset 2 decoded as %s", tostring(dec.mapTexture))
  ok(dec.dummy04 == 0x33, "dummy04 decoded as %s, should be offset 4",
     tostring(dec.dummy04))
  ok(dec.areaLight == 0x02, "areaLight decoded as %s, should be offset 6",
     tostring(dec.areaLight))
end

-- `AreaDataManager_IsOutdoorsLighting` is (id == 0 || id == 3), and it is read
-- out of pret rather than restated, because it is the cartridge's own reading of
-- this field and not an inference about it.
local areaDataC = slurp("src/overlay005/area_data.c") or ""
-- Anchored on the DEFINITION, not the name: the prototype appears earlier in
-- the file, and a lazy match from there runs into some other function's `if`.
local outCond = areaDataC:match(
  "BOOL AreaDataManager_IsOutdoorsLighting%b()%s*{%s*if %((.-)%)%s*{")
ok(outCond and outCond:find("== 0") and outCond:find("== 3"),
   "IsOutdoorsLighting no longer tests 0 and 3: %q", tostring(outCond))
for id = 0, 5 do
  local r = string.char(0,0, 0,0, 0,0, id, 0)
  local d = Gen4Maps.areaData(r)
  local want = (id == 0 or id == 3)
  ok(d and d.outdoors == want,
     "areaLight %d: outdoors is %s, IsOutdoorsLighting says %s",
     id, tostring(d and d.outdoors), tostring(want))
end

-- ---------------------------------------------------------------------------
section("3. the archive parses, and every member does")
-- ---------------------------------------------------------------------------
local rom = assert(NdsRom.open(romPath))
local raw = rom:read(AL.PATH)
ok(raw, "%s is not in the ROM", AL.PATH)
local arc = raw and Narc.parse(raw)
ok(arc, "%s did not parse as a NARC", AL.PATH)
arc = arc or { count = 0, get = function() return nil end }
ok(arc.count == fileCount,
   "the archive has %d members but AREA_LIGHT_FILE_COUNT is %s",
   arc.count, tostring(fileCount))

local templates, parsed = AL.all(arc)
ok(parsed == arc.count, "only %d of %d members parsed", parsed, arc.count)

-- THE CRLF REGRESSION GUARD, AND IT IS A REAL BUG THIS FILE WATCHES FOR.
-- `Ascii_CopyToTerminator` swallows the LF after each CR (`src[i+1] == '\n'` ->
-- `+2`), so the cartridge's line buffers never carry one. Splitting on CR alone
-- leaves that LF on the front of every line but the first, which `tonumber`
-- tolerates and the `EOF` test does not: `("\nEOF"):sub(1, 3)` is not "EOF", the
-- terminator is read as one more template, and the member is rejected. Members 1
-- and 3 end with a CR after their EOF and members 0 and 2 do not, so this fails
-- on exactly half the archive if the LF is ever left on again.
local reader = slurp("src/ascii_util.c") or ""
ok(reader:find("src%[i %+ 1%] == '\\n'"),
   "Ascii_CopyToTerminator no longer consumes the LF after a CR -- the line "
   .. "split in Gen4AreaLight assumes it does")
local withTrailingCr = 0
for m = 0, arc.count - 1 do
  local bytes = arc:get(m) or ""
  local lines = 0
  for _ in bytes:gmatch("\r") do lines = lines + 1 end
  if bytes:match("EOF[^\r]*\r") then withTrailingCr = withTrailingCr + 1 end
  ok(templates[m], "member %d did not parse", m)
  ok(#(templates[m] or {}) == 15,
     "member %d has %d templates, expected 15", m, #(templates[m] or {}))
end
ok(withTrailingCr == 2,
   "%d members end with a CR after EOF, expected 2 -- the asymmetry is what "
   .. "makes the LF bug show up on half the archive", withTrailingCr)

-- ---------------------------------------------------------------------------
section("4. every value is inside the hardware's range")
-- ---------------------------------------------------------------------------
local totalTemplates, totalLights = 0, 0
for m = 0, arc.count - 1 do
  local ts = templates[m] or {}
  local prev = -1
  for i, t in ipairs(ts) do
    totalTemplates = totalTemplates + 1
    -- endTime rises through the member, because `AreaLightManager_New` takes the
    -- FIRST template past the clock and a member out of order would make later
    -- bands unreachable.
    ok(t.endTime > prev or i == 1,
       "member %d template %d: endTime %d is not past %d", m, i, t.endTime, prev)
    prev = t.endTime
    ok(t.endTime >= 0 and t.endTime <= AL.DAY_TICKS,
       "member %d template %d: endTime %d is outside a day", m, i, t.endTime)

    local mask = 0
    for slot = 1, AL.LIGHTS do
      local L = t.lights[slot]
      if L then
        totalLights = totalLights + 1
        mask = mask + 2 ^ (slot - 1)
        ok(L.index == slot - 1,
           "member %d template %d slot %d: index is %d", m, i, slot, L.index)
        for c = 1, 3 do
          local v = L.colour[c]
          ok(v >= 0 and v <= AL.CHANNEL_MAX,
             "member %d template %d light %d channel %d is %d, off the five-bit scale",
             m, i, slot, c, v)
        end
        for axis = 1, 3 do
          local v = L.vector[axis]
          ok(v >= -AL.FX16_ONE and v <= AL.FX16_ONE,
             "member %d template %d light %d axis %d is %d, past FX16_ONE",
             m, i, slot, axis, v)
        end
        -- A valid light's packed colour is never the invalid sentinel: GX_RGB
        -- has no bit 15, so even full white is 0x7FFF.
        ok(L.packed ~= AL.INVALID_COLOUR,
           "member %d template %d light %d packed to the invalid sentinel",
           m, i, slot)
        ok(L.packed == AL.packRgb(L.colour[1], L.colour[2], L.colour[3]),
           "member %d template %d light %d: packed %d disagrees with its channels",
           m, i, slot, L.packed)
      end
    end
    ok(t.validMask == mask,
       "member %d template %d: validMask is %d but the table holds %d",
       m, i, t.validMask, mask)

    for _, row in ipairs({ "diffuse", "ambient", "specular", "emission" }) do
      local c = t[row]
      ok(c and #c == 3, "member %d template %d has no %s row", m, i, row)
      for k = 1, 3 do
        ok(c and c[k] >= 0 and c[k] <= AL.CHANNEL_MAX,
           "member %d template %d %s channel %d is %s",
           m, i, row, k, tostring(c and c[k]))
      end
    end
  end
  -- The last band closes the day, or the clock falls off the end of the member.
  local last = ts[#ts]
  ok(last and last.endTime == AL.DAY_TICKS,
     "member %d ends at %s, not the day's %d",
     m, tostring(last and last.endTime), AL.DAY_TICKS)
end
ok(totalTemplates == 60, "%d templates across the archive, expected 60", totalTemplates)
ok(AL.packRgb(31, 31, 31) == 0x7FFF, "GX_RGB(31,31,31) packed to 0x%X", AL.packRgb(31,31,31))
ok(AL.packRgb(31, 31, 31) ~= AL.INVALID_COLOUR, "full white packs to the invalid sentinel")
ok(AL.packRgb(1, 0, 0) == 1 and AL.packRgb(0, 1, 0) == 32 and AL.packRgb(0, 0, 1) == 1024,
   "GX_RGB channel order is wrong: r=%d g=%d b=%d",
   AL.packRgb(1,0,0), AL.packRgb(0,1,0), AL.packRgb(0,0,1))

-- ---------------------------------------------------------------------------
section("5. which template is live, the cartridge's rule")
-- ---------------------------------------------------------------------------
-- `for i ... if (templates[i].endTime > currentTime) { active = i; break; }`,
-- starting from an active index of 0 -- so a clock past every band keeps the
-- FIRST template rather than the last, which is what wraps midnight.
local m0 = templates[0] or {}
local first, firstIdx = AL.activeAt(m0, -1)
ok(firstIdx == 1, "a clock before every band chose template %s", tostring(firstIdx))
for i, t in ipairs(m0) do
  -- one tick inside this band must select it
  local _, idx = AL.activeAt(m0, t.endTime - 1)
  ok(idx <= i, "a clock inside band %d selected band %s", i, tostring(idx))
end
local _, wrapped = AL.activeAt(m0, AL.DAY_TICKS + 1)
ok(wrapped == 1, "a clock past every band selected %s, not the first",
   tostring(wrapped))
-- ...and the half-second scale, which is `GetSecondsSinceMidnight() / 2`.
ok(select(2, AL.activeAtClock(m0, 0, 0)) == select(2, AL.activeAt(m0, 0)),
   "activeAtClock(0,0) disagrees with activeAt(0)")
local _, noonIdx = AL.activeAtClock(m0, 12, 0)
local _, rawIdx = AL.activeAt(m0, 21600)
ok(noonIdx == rawIdx,
   "12:00 is %d half-seconds, but activeAtClock chose %s and activeAt %s",
   21600, tostring(noonIdx), tostring(rawIdx))

-- ---------------------------------------------------------------------------
section("6. the index and the archive actually meet")
-- ---------------------------------------------------------------------------
local areaArc = Narc.parse(assert(rom:read("/fielddata/areadata/area_data.narc")))
ok(areaArc, "the area data archive did not parse")
local seen, offFour = {}, {}
local records = 0
for m = 0, (areaArc and areaArc.count or 0) - 1 do
  local d = Gen4Maps.areaData(areaArc:get(m))
  if d then
    records = records + 1
    seen[d.areaLight] = (seen[d.areaLight] or 0) + 1
    offFour[d.dummy04] = (offFour[d.dummy04] or 0) + 1
    -- GF_ASSERT(archiveID < AREA_LIGHT_FILE_COUNT), on every record.
    ok(d.areaLight < fileCount,
       "area record %d selects light member %d, past AREA_LIGHT_FILE_COUNT %s",
       m, d.areaLight, tostring(fileCount))
    ok(templates[d.areaLight],
       "area record %d selects member %d, which did not parse", m, d.areaLight)
  end
end
ok(records == 75, "%d area records, expected 75", records)

-- THE MEASUREMENT THAT SETTLED WHICH U16 IT IS, kept so it keeps settling it.
-- Offset 4 must break the cartridge's bound and offset 6 must respect it; if
-- both fit, this check can no longer tell the two fields apart and the swap
-- could come back unnoticed.
local offFourMax = 0
for v in pairs(offFour) do if v > offFourMax then offFourMax = v end end
ok(offFourMax >= fileCount,
   "pret's dummy04 tops out at %d, inside AREA_LIGHT_FILE_COUNT %s -- this "
   .. "check can no longer tell the two u16s apart by their range",
   offFourMax, tostring(fileCount))

-- Member 3 is reachable only from ov6_0223E140.c's literal 3, never from an
-- area record, so an area record selecting it means the field moved again.
ok(not seen[3], "an area record selects member 3, which only ov6 asks for")
local ov6 = slurp("src/overlay006/ov6_0223E140.c") or ""
local literals = 0
for _ in ov6:gmatch("AreaLightManager_New%(fieldSystem%->areaModelAttrs, 3%)") do
  literals = literals + 1
end
ok(literals == 2,
   "ov6_0223E140.c asks for member 3 %d times, expected 2 -- if it stopped, "
   .. "member 3 is now unreachable and its absence from the records is no "
   .. "longer explained", literals)

-- ...and that the outdoor members are the ones with a day in them. Member 0 is
-- the only one whose light 0 actually moves across its templates, which is what
-- an outdoor sun does and what the two comparison screenshots differ on.
local function moves(ts)
  local firstVec = ts[1] and ts[1].lights[1] and ts[1].lights[1].vector
  if not firstVec then return false end
  for _, t in ipairs(ts) do
    local v = t.lights[1] and t.lights[1].vector
    if v and (v[1] ~= firstVec[1] or v[2] ~= firstVec[2] or v[3] ~= firstVec[3]) then
      return true
    end
  end
  return false
end
ok(moves(templates[0] or {}), "member 0's sun never moves across its day")
for m = 1, arc.count - 1 do
  ok(not moves(templates[m] or {}),
     "member %d's light 0 moves too, so 'the member with a moving sun' no "
     .. "longer identifies member 0", m)
end

-- ---------------------------------------------------------------------------
section("7. the geometry term")
-- ---------------------------------------------------------------------------
-- `max(0, -N . L)`, and nothing beyond it -- see Gen4AreaLight.lambert for why
-- the terms are deliberately not combined here.
local t8 = (templates[0] or {})[8]
ok(t8, "member 0 has no eighth template")
if t8 then
  local w = AL.lambert(t8, 0, 1, 0)
  -- Light 0 points down (y is -3548 of 4096 here), so the ground is lit.
  ok(w[1] and w[1] > 0.8, "light 0 on the ground is %s, expected the sun's ~0.87",
     tostring(w[1]))
  -- Lights 2 and 3 are flat along +Z, so a Y-up ground gets nothing from them.
  for slot = 3, 4 do
    if t8.lights[slot] then
      ok(w[slot] == 0,
         "light %d gives the ground %s, but its vector is flat along +Z",
         slot, tostring(w[slot]))
    end
  end
  -- A surface facing the sun head-on takes the full term; its back takes none.
  local u = t8.lights[1].unit
  local facing = AL.lambert(t8, -u[1], -u[2], -u[3])
  ok(facing[1] > 0.999, "a surface facing the sun takes %s", tostring(facing[1]))
  local away = AL.lambert(t8, u[1], u[2], u[3])
  ok(away[1] == 0, "a surface facing away takes %s, not zero", tostring(away[1]))
end

-- ---------------------------------------------------------------------------
section("8. an independent second parse, field by field")
-- ---------------------------------------------------------------------------
-- WHY THIS SECTION EXISTS: the range checks above passed a planted fault that
-- read all four reflection rows ONE LINE LATE. Nothing noticed, because every
-- row it landed on held legal five-bit values -- and the tenth line of a
-- template is BLANK, which parses to 0,0,0 and is legal too. Bounds cannot catch
-- a shift that stays inside them.
--
-- So this splits each member a second time, deliberately differently (on the
-- CRLF pair rather than on the CR, with the row offsets written out here rather
-- than shared with the module) and compares every field. A one-line slip in
-- either parse now disagrees with the other.
local rows = { diffuse = 5, ambient = 6, specular = 7, emission = 8 }
for m = 0, arc.count - 1 do
  local bytes = arc:get(m) or ""
  local ls = {}
  for piece in (bytes .. "\r\n"):gmatch("(.-)\r\n") do ls[#ls + 1] = piece end
  local ts = templates[m] or {}
  for i, t in ipairs(ts) do
    local base = (i - 1) * 10 + 1
    local function nums(line)
      local out = {}
      for v in tostring(ls[line] or ""):gmatch("(-?%d+)") do out[#out + 1] = tonumber(v) end
      return out
    end
    ok(nums(base)[1] == t.endTime,
       "member %d template %d: endTime is %d, the file's line %d says %s",
       m, i, t.endTime, base, tostring(nums(base)[1]))
    for slot = 1, AL.LIGHTS do
      local f = nums(base + slot)
      local L = t.lights[slot]
      if f[1] == 1 then
        ok(L, "member %d template %d slot %d is valid in the file but absent", m, i, slot)
        if L then
          for c = 1, 3 do
            ok(L.colour[c] == f[1 + c],
               "member %d template %d light %d channel %d: %d, file says %s",
               m, i, slot, c, L.colour[c], tostring(f[1 + c]))
          end
          for a = 1, 3 do
            local want = f[4 + a]
            if want and want > AL.FX16_ONE then want = AL.FX16_ONE end
            if want and want < -AL.FX16_ONE then want = -AL.FX16_ONE end
            ok(L.vector[a] == want,
               "member %d template %d light %d axis %d: %d, file says %s",
               m, i, slot, a, L.vector[a], tostring(want))
          end
        end
      else
        ok(not L, "member %d template %d slot %d is invalid in the file but present",
           m, i, slot)
      end
    end
    for row, offset in pairs(rows) do
      local f = nums(base + offset)
      for c = 1, 3 do
        ok(t[row] and t[row][c] == f[c],
           "member %d template %d %s channel %d: %s, file line %d says %s",
           m, i, row, c, tostring(t[row] and t[row][c]), base + offset, tostring(f[c]))
      end
    end
    -- The tenth line is the blank one, and it has to stay blank: it is the only
    -- thing separating one template's emission row from the next one's endTime,
    -- and a row read off the end of a template lands here and looks legal.
    ok((ls[base + 9] or ""):match("^%s*$"),
       "member %d template %d: line %d should be the blank separator, it is %q",
       m, i, base + 9, tostring(ls[base + 9]))
  end
end

-- ...and that the emission row is never all-zero in practice, so "the row I read
-- happened to be the blank line" is a state this data can actually distinguish.
local zeroEmission = 0
for m = 0, arc.count - 1 do
  for _, t in ipairs(templates[m] or {}) do
    if t.emission[1] == 0 and t.emission[2] == 0 and t.emission[3] == 0 then
      zeroEmission = zeroEmission + 1
    end
  end
end
ok(zeroEmission == 0,
   "%d templates have an all-zero emission row, so an off-by-one onto the blank "
   .. "separator would be indistinguishable from real data", zeroEmission)

-- ---------------------------------------------------------------------------
section("9. the exact boundary, and the exact scale")
-- ---------------------------------------------------------------------------
-- `if (templates[i].endTime > currentTime)` is a STRICT test, so a clock sitting
-- exactly on a band's endTime belongs to the NEXT band. A `>=` here is invisible
-- everywhere except on that one tick, which is why the earlier band loop passed a
-- planted `>=` without noticing.
for i = 1, #m0 - 1 do
  local _, idx = AL.activeAt(m0, m0[i].endTime)
  ok(idx > i,
     "a clock exactly on band %d's endTime %d selected band %s -- the "
     .. "cartridge's test is strictly greater, so it belongs to the next band",
     i, m0[i].endTime, tostring(idx))
  local _, inside = AL.activeAt(m0, m0[i].endTime - 1)
  ok(inside == i,
     "a clock one tick inside band %d selected band %s", i, tostring(inside))
end

-- FX16_ONE IS THE DIVISOR, AND 4096 IS NOT 4095. A vector axis at exactly
-- FX16_ONE has to come out as exactly 1.0; anything near-but-not-one means the
-- scale is off, and near-one passes every threshold a lambert check would set.
local pinned = 0
for m = 0, arc.count - 1 do
  for _, t in ipairs(templates[m] or {}) do
    for slot = 1, AL.LIGHTS do
      local L = t.lights[slot]
      if L then
        for a = 1, 3 do
          if L.vector[a] == AL.FX16_ONE then
            pinned = pinned + 1
            ok(L.unit[a] == 1,
               "an axis at FX16_ONE became %.6f, so the divisor is not %d",
               L.unit[a], AL.FX16_ONE)
          elseif L.vector[a] == 0 then
            ok(L.unit[a] == 0, "a zero axis became %s", tostring(L.unit[a]))
          end
        end
      end
    end
  end
end
ok(pinned > 0,
   "no vector axis sits at FX16_ONE, so nothing above pins the divisor")

-- ...and the validity field's domain, which is the one thing here the ROM cannot
-- settle. `ParseLightAttrs` tests `lightValid == TRUE`, so a 2 would be INVALID,
-- but no member holds anything but 0 or 1 -- a planted `~= 0` is therefore
-- indistinguishable on this cartridge. This records that rather than implying the
-- stricter test was proved, and fires if a member ever holds something else.
local domain = {}
for m = 0, arc.count - 1 do
  local bytes = arc:get(m) or ""
  local n = 0
  for piece in (bytes .. "\r\n"):gmatch("(.-)\r\n") do
    n = n + 1
    if n % 10 >= 2 and n % 10 <= 5 then
      local first = piece:match("^(-?%d+),")
      if first then domain[tonumber(first)] = true end
    end
  end
end
for v in pairs(domain) do
  ok(v == 0 or v == 1,
     "a light line's validity field is %d; `lightValid == TRUE` makes that "
     .. "INVALID, and the `== 1` test in Gen4AreaLight is now load-bearing", v)
end
ok(domain[0] and domain[1],
   "the validity field does not take both 0 and 1 across the archive")

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
