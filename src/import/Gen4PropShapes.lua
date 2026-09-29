-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A MAP PROP IS NOT DRAWN AS A MODEL. IT IS DRAWN AS A LIST.
--
-- `MapProp_Draw` does not hand the prop's NSBMD to the renderer and let it walk
-- its own shapes. It walks a list that comes from a separate file:
--
--     MapProp_GetMaterialShapeIDsLocator(modelID, propMatShp, &count, &index);
--     propMatShpIDs = MapPropMaterialShape_GetMaterialShapeIDsAt(index, propMatShp);
--     u8 materialID = 0xFF;
--     for (i = 0; i < count; i++) {
--         if (materialID != propMatShpIDs[i].materialID) {
--             materialID = propMatShpIDs[i].materialID;
--             sendMaterial = TRUE;
--         } else {
--             sendMaterial = FALSE;
--         }
--         NNS_G3dDraw1Mat1Shp(model, materialID, propMatShpIDs[i].shapeID, sendMaterial);
--     }
--
-- so the ORDER in the file is the draw order, and it cannot be reconstructed by
-- iterating a model's shapes. THE ORDER IS NOT THE SHAPES' OWN ORDER: 160 of the
-- 478 non-empty lists put their shape ids out of ascending sequence, and models
-- 22, 23 and 236 draw MATERIAL 0 LAST after materials 1..4 -- which is what you do
-- with a translucent material, and what comes out wrong if you draw the model the
-- obvious way.
--
-- THE FILE IS `fielddata/build_model/build_model_matshp.dat`, a plain ROM file and
-- not a NARC, loaded by `MapPropMaterialShape_Load` with four bare `FS_ReadFile`
-- calls in this order:
--
--     u16 idsLocatorsCount
--     u16 idsCount
--     { u16 idsCount; u16 idsIndex; }     x idsLocatorsCount   -- per PROP MODEL
--     { u16 materialID; u16 shapeID; }    x idsCount           -- the pairs
--
-- and it closes with no slack at all: 590 locators, 1009 pairs,
-- 4 + 590*4 + 1009*4 = 6400 = the file's exact size. 590 is also exactly
-- `build_model.narc`'s member count, so the locator array is indexed by prop model
-- id over the whole archive, and the per-locator counts sum to 1009 exactly --
-- the pair array is partitioned by the locators with no overlap and no gap.
--
-- AN EMPTY LOCATOR CARRIES 0xFFFF, NOT 0. All 112 models with no pairs have
-- `idsIndex == 0xFFFF`, with no exceptions either way, so the two fields agree
-- perfectly. On the cartridge that is harmless because `count` is 0 and the loop
-- body never runs, but a reader that resolves the index BEFORE checking the count
-- indexes 65535 into a 1009-entry array. That is why `parse` never stores an
-- index for an empty list.

local Gen4PropShapes = {}

Gen4PropShapes.PATH = "/fielddata/build_model/build_model_matshp.dat"
-- The sentinel an empty locator carries in place of an index.
Gen4PropShapes.NO_INDEX = 0xFFFF
-- The four bytes of header, then two u32-sized records per entry.
Gen4PropShapes.HEADER_BYTES = 4
Gen4PropShapes.RECORD_BYTES = 4

local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end

-- parse(bytes) -> { lists = { [modelId] = { {material, shape, sendMaterial}, ... } },
--                   models, pairs }, or nil plus a reason.
function Gen4PropShapes.parse(bytes)
  if type(bytes) ~= "string" or #bytes < Gen4PropShapes.HEADER_BYTES then
    return nil, "the material shape file is too short for its header"
  end
  local models, pairs_ = u16(bytes, 0), u16(bytes, 2)
  local header = Gen4PropShapes.HEADER_BYTES
  local rec = Gen4PropShapes.RECORD_BYTES
  local want = header + models * rec + pairs_ * rec
  -- THE LENGTH IS EXACT, NOT A MINIMUM. The two counts and the file size
  -- determine each other, so a file that merely fits is a file that is wrong.
  if #bytes ~= want then
    return nil, ("%d locators and %d pairs is %d bytes but the file is %d")
      :format(models, pairs_, want, #bytes)
  end

  local idsAt = header + models * rec
  local out = { lists = {}, models = models, pairs = pairs_ }
  local used = 0
  for m = 0, models - 1 do
    local at = header + m * rec
    local count, index = u16(bytes, at), u16(bytes, at + 2)
    if count and count > 0 then
      if index == Gen4PropShapes.NO_INDEX then
        return nil, ("model %d has %d pairs but the empty-list sentinel as its index")
          :format(m, count)
      end
      if index + count > pairs_ then
        return nil, ("model %d runs from %d for %d, past the %d pairs")
          :format(m, index, count, pairs_)
      end
      local list = {}
      -- `u8 materialID = 0xFF` before the loop, so the FIRST pair always sends its
      -- material: 0xFF is not a material any prop uses.
      local previous = 0xFF
      for i = 0, count - 1 do
        local o = idsAt + (index + i) * rec
        local material, shape = u16(bytes, o), u16(bytes, o + 2)
        list[i + 1] = {
          material = material,
          shape = shape,
          -- Precomputed here so a renderer does not have to rediscover the rule,
          -- and so it can be asserted: across the whole cartridge this is false
          -- exactly ONCE, on model 175's second pair.
          sendMaterial = material ~= previous,
        }
        previous = material
      end
      out.lists[m] = list
      used = used + count
    end
  end
  -- The locators partition the pair array, so anything left over means a locator
  -- was misread rather than that the file has spare rows.
  if used ~= pairs_ then
    return nil, ("the locators account for %d of %d pairs"):format(used, pairs_)
  end
  return out
end

return Gen4PropShapes
