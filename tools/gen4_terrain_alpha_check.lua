-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that Platinum's TERRAIN states a polygon alpha below 31 on
-- 155 of its materials, that the value survives every stage of the import from
-- the cartridge to the chunk index, and that the name fallback which covers a
-- cache written before it existed tests both of the two names the cartridge
-- splits `kage` across.
--
-- THIS FILE EXISTS BECAUSE THE SAME QUESTION WAS MEASURED WRONG TWICE.
--
-- First: "0 of 7,547 terrain chunk shapes carry an alpha field at all", taken
-- on the CACHE, and read as licence to drop alpha.  The cache is DOWNSTREAM of
-- the field being dropped, so that count would have returned zero whatever the
-- cartridge said -- a measurement that can only fail says nothing either.
--
-- Second: `shapeAlpha`'s own comment, "`h_kage` is 9/31 on every material that
-- wears it".  True of the 590 building models it was measured on.  On terrain
-- `h_kage` is 6/31 on three materials and `m_dun06_kage` is 15/31.
--
-- So every number here is read from the ROM, and the round trip is checked
-- through the real importer rather than by reading the importer's source.
--
-- Usage: texlua tools/gen4_terrain_alpha_check.lua <rom>

local romPath = arg[1]
if not romPath then
  io.stderr:write("usage: texlua tools/gen4_terrain_alpha_check.lua <rom>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Gen4Maps = require("src.import.Gen4Maps")
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")
local Gen4Terrain = require("src.import.Gen4Terrain")

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
local landNarc = Narc.parse(assert(rom:read("/fielddata/land_data/land_data.narc")))

-- ---------------------------------------------------------------------------
section("1. the cartridge states a sub-31 alpha on terrain at all")
-- ---------------------------------------------------------------------------
-- The whole bug was that this was never asked.  If a future change to
-- `Gen4Nsbmd`'s polygon-attribute read silently stops producing alpha, every
-- count below goes to zero and section 1 is what says so.

local mats, translucent, chunks, chunksWithAlpha = 0, 0, 0, 0
local byTexture, byMaterialName = {}, {}
local textureless, texturelessNames = 0, {}
local kageBoth, kageTexOnly, kageMatOnly = 0, 0, 0

for i = 0, landNarc.count - 1 do
  local bytes = landNarc:get(i)
  if bytes and #bytes > 0 then
    local land = Gen4Maps.land(bytes)
    if land and land.model and #land.model > 0 then
      local set = Gen4Nsbmd.parse(land.model)
      local model = set and set.models and set.models[1]
      if model and model.materials then
        chunks = chunks + 1
        local any = false
        for _, m in ipairs(model.materials) do
          mats = mats + 1
          if m.alpha and m.alpha < 31 then
            translucent = translucent + 1
            any = true
            local tex = tostring(m.texture or "<none>")
            byTexture[tex] = byTexture[tex] or {}
            byTexture[tex][m.alpha] = (byTexture[tex][m.alpha] or 0) + 1
            byMaterialName[tostring(m.name or "?")] = m.alpha
            if m.texture == nil then
              textureless = textureless + 1
              texturelessNames[tostring(m.name or "?")] = true
            end
            local t = tostring(m.texture or ""):lower():find("kage", 1, true)
            local n = tostring(m.name or ""):lower():find("kage", 1, true)
            if t and n then kageBoth = kageBoth + 1
            elseif t then kageTexOnly = kageTexOnly + 1
            elseif n then kageMatOnly = kageMatOnly + 1 end
          end
        end
        if any then chunksWithAlpha = chunksWithAlpha + 1 end
      end
    end
  end
end

io.write(("  chunks parsed %d, materials %d, alpha<31 %d, chunks affected %d\n")
  :format(chunks, mats, translucent, chunksWithAlpha))
io.write(("  of those, %d carry no texture at all\n"):format(textureless))

ok(chunks == 666, "expected 666 land chunks to parse, got %d", chunks)
ok(mats == 7346, "expected 7,346 terrain materials, got %d", mats)
ok(translucent == 155, "expected 155 materials with alpha<31, got %d", translucent)
ok(chunksWithAlpha == 107, "expected 107 chunks to carry one, got %d", chunksWithAlpha)

-- ---------------------------------------------------------------------------
section("2. the named surfaces that must not be opaque")
-- ---------------------------------------------------------------------------
-- The visible half of the bug.  Water as opaque as the cliffs it runs against,
-- and the ground shadow decals as solid patches -- the same complaint Cedric
-- made about the houses, one file over.

local function statesAlpha(tex, want, count)
  local seen = byTexture[tex]
  if not seen then
    ok(false, "%s states no alpha at all; it should state %d/31", tex, want)
    return
  end
  ok(seen[want] ~= nil, "%s should state %d/31 somewhere; it states %s",
     tex, want, (function()
       local t = {}
       for a, n in pairs(seen) do t[#t + 1] = ("%d/31 x%d"):format(a, n) end
       table.sort(t)
       return table.concat(t, ", ")
     end)())
  if count then
    ok(seen[want] == count, "%s at %d/31 should cover %d shapes, covers %d",
       tex, want, count, seen[want] or 0)
  end
end

statesAlpha("sea", 13, 12)
statesAlpha("sea", 21, 12)
statesAlpha("shadowchip", 12, 27)
statesAlpha("water01", 13)
statesAlpha("water02", 15)
statesAlpha("dun_shadow", 12)
-- ...and the ones with NO TEXTURE AT ALL, which is the subset no texture-name
-- rule could ever have rescued: untextured, vertex-lit shadow quads that drew
-- as solid black patches.  `stair_d01_shade`, `shade`, `table01_1_shade` and
-- `table_l01:shade` all state 12/31 with `texture` nil.
for _, name in ipairs({ "stair_d01_shade", "shade", "table01_1_shade", "table_l01:shade" }) do
  ok(byMaterialName[name] == 12,
     "%s should be a translucent terrain material at 12/31, is %s",
     name, tostring(byMaterialName[name]))
  ok(texturelessNames[name] == true,
     "%s should carry NO texture; the whole point of it is that no texture-name "
     .. "rule can reach it", name)
end
ok(textureless >= 10,
   "expected at least 10 translucent terrain materials with no texture, got %d",
   textureless)
-- `garasu` is glass: a window, and windows are the other thing alpha is for.
statesAlpha("wtk_kabe_garasu3", 16)

-- And the claim that used to sit in `shapeAlpha`'s comment, kept here as the
-- counter-example rather than as a belief: `h_kage` is NOT 9/31 everywhere.
ok(byTexture["h_kage"] and byTexture["h_kage"][6] ~= nil,
   "h_kage should state 6/31 on at least one terrain material, not 9/31 alone")
ok(byTexture["m_dun06_kage"] and byTexture["m_dun06_kage"][15] ~= nil,
   "m_dun06_kage should state 15/31")

-- ---------------------------------------------------------------------------
section("3. `kage` is split across BOTH names, which is why the fallback tests both")
-- ---------------------------------------------------------------------------
-- `shapeAlpha` read `shape.material or shape.texture`: an `or` where the
-- question is an either.  Which of the shadow materials it caught therefore
-- depended on which field the caller happened to carry, and terrain started
-- carrying `material` in the same pass that fixed this.

io.write(("  kage in both names %d, texture only %d, material only %d\n")
  :format(kageBoth, kageTexOnly, kageMatOnly))

ok(kageBoth == 17, "expected 17 materials saying kage in both names, got %d", kageBoth)
ok(kageTexOnly == 11, "expected 11 saying kage in the TEXTURE only, got %d", kageTexOnly)
ok(kageMatOnly == 2, "expected 2 saying kage in the MATERIAL only, got %d", kageMatOnly)
-- Both counts being non-zero is the point: either field alone is wrong.
ok(kageTexOnly > 0 and kageMatOnly > 0,
   "if either count is zero the fallback could read one field; it cannot")

-- A few of the eleven by name, so a rename cannot quietly empty the set.
for _, name in ipairs({ "chair4", "counter2", "shelf2", "lambert7" }) do
  ok(byMaterialName[name] ~= nil,
     "%s should be a translucent terrain material wearing a kage texture", name)
end

-- ---------------------------------------------------------------------------
section("4. the alpha survives the import -- the round trip that was broken")
-- ---------------------------------------------------------------------------
-- THE REGRESSION GUARD.  Sections 1-3 measure the cartridge; this one runs the
-- real `Gen4Terrain.chunk` and `Gen4Terrain.append` and looks in the index they
-- produce, because the bug was not in the cartridge or in the parser -- it was
-- one missing line in `append`, and only reading its output can catch that.

local CHUNKS_WITH_ALPHA = { 26, 28, 34 }   -- shadowchip 12/31, h_kage 9/31, shadowchip 12/31
for _, index in ipairs(CHUNKS_WITH_ALPHA) do
  local bytes = landNarc:get(index)
  local chunk = bytes and Gen4Terrain.chunk(bytes)
  if not chunk then
    ok(false, "chunk %d would not build", index)
  else
    -- the packer's own output first, so a failure says WHICH stage lost it
    local packedAlpha = 0
    for _, s in ipairs(chunk.packed.shapes) do
      if s.alpha then packedAlpha = packedAlpha + 1 end
    end
    ok(packedAlpha > 0,
       "Gen4ModelPack lost the alpha for chunk %d: 0 of %d packed shapes carry one",
       index, #chunk.packed.shapes)

    -- ...then the index, which is where it actually went missing
    local state = Gen4Terrain.newBlob()
    local entry = Gen4Terrain.append(state, chunk)
    local indexAlpha, lowest = 0, nil
    for _, s in ipairs(entry.shapes) do
      if s.alpha then
        indexAlpha = indexAlpha + 1
        lowest = (not lowest or s.alpha < lowest) and s.alpha or lowest
      end
    end
    ok(indexAlpha > 0,
       "Gen4Terrain.append dropped the alpha for chunk %d: %d packed shapes carry one, "
       .. "0 of %d index entries do", index, packedAlpha, #entry.shapes)
    ok(indexAlpha == packedAlpha,
       "chunk %d: %d packed shapes carry an alpha but %d index entries do",
       index, packedAlpha, indexAlpha)
    ok(lowest == nil or lowest < 31,
       "chunk %d: an alpha of %s was carried, which is not translucent",
       index, tostring(lowest))
    -- `material` too, since `Gen4Ground:modelFor` now forwards it and the
    -- fallback reads it.
    local withMaterial = 0
    for _, s in ipairs(entry.shapes) do
      if s.material then withMaterial = withMaterial + 1 end
    end
    ok(withMaterial > 0, "chunk %d: no index entry carries a material name", index)
  end
end

-- And a chunk the cartridge says is fully opaque must NOT acquire one, so that
-- section 4 cannot pass by having `append` stamp a constant on everything.
local opaqueFound = false
for i = 0, landNarc.count - 1 do
  local bytes = landNarc:get(i)
  if bytes and #bytes > 0 then
    local land = Gen4Maps.land(bytes)
    if land and land.model and #land.model > 0 then
      local set = Gen4Nsbmd.parse(land.model)
      local model = set and set.models and set.models[1]
      if model and model.materials and #model.materials > 0 then
        local any = false
        for _, m in ipairs(model.materials) do
          if m.alpha and m.alpha < 31 then any = true break end
        end
        if not any then
          local chunk = Gen4Terrain.chunk(bytes)
          if chunk then
            local state = Gen4Terrain.newBlob()
            local entry = Gen4Terrain.append(state, chunk)
            local stamped = 0
            for _, s in ipairs(entry.shapes) do
              if s.alpha then stamped = stamped + 1 end
            end
            ok(stamped == 0,
               "chunk %d states no alpha, yet %d of its %d index entries carry one",
               i, stamped, #entry.shapes)
            opaqueFound = true
            break
          end
        end
      end
    end
  end
end
ok(opaqueFound, "no fully opaque chunk was found to use as the control")

-- ---------------------------------------------------------------------------
io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
