-- The metatile atlas: one composite texture per tileset pair.
--
-- Emerald 3DS composes every metatile's two layers into one 16x16 slot
-- (voxel_atlas.c).  This engine already bakes the two layers as two sheets
-- (TileRenderer.gen3SheetsFor: `bottom`, opaque, colour 0 the backdrop; and
-- `top`, colour 0 clear), slot = metatile id, with every animated metatile's
-- other frames in extra slots past the statics.  So the atlas here is a
-- canvas the size of the static grid plus one slot per ground variant:
--
--   slot id            the metatile (0..511 primary, 512.. secondary)
--   statics + v        ground variant v of buildings.bin, drawn only when
--                      its layout's tileset is this pair's (atlas id 1024+v)
--
-- and each frame the animated metatiles (and the variants made from them)
-- are redrawn into their slots from the frame the engine is showing, which
-- is how the sea keeps moving under a rock modelled in it.

local V = ...
local Data = V.require("Data")

local Atlas = {}

local atlases = setmetatable({}, { __mode = "k" })

local function cols()
  return require("src.render.Gen3Tiles").SHEET_COLS
end

-- The engine's sheet record for a map: the one its own renderer draws with.
local function recordOf(map)
  local r = map and map.renderer
  return r and r.gen3 or nil
end

local function quadFor(record, slot, qx, qy, size)
  local c = cols()
  return love.graphics.newQuad((slot % c) * 16 + (qx or 0), math.floor(slot / c) * 16 + (qy or 0),
                               size or 16, size or 16, record.width, record.height)
end

-- Draw metatile `from` (a sheet slot) into the canvas at slot `to`, hiding
-- the upper-layer quadrants set in `hidden` (bit 2*row + col).
local function compose(atlas, from, to, hidden)
  local record, c = atlas.record, atlas.cols
  local tx, ty = (to % c) * 16, math.floor(to / c) * 16
  love.graphics.draw(record.bottom, quadFor(record, from), tx, ty)
  if not hidden or hidden == 0 then
    love.graphics.draw(record.top, quadFor(record, from), tx, ty)
    return
  end
  for q = 0, 3 do
    if math.floor(hidden / 2 ^ q) % 2 == 0 then
      local qx, qy = (q % 2) * 8, math.floor(q / 2) * 8
      love.graphics.draw(record.top, quadFor(record, from, qx, qy, 8), tx + qx, ty + qy)
    end
  end
end

-- A cut tile: metatile `from` composed at `slot`, then every background
-- pixel (bit x of rows[y] set) cleared to transparent.  Drawn into the
-- canvas that is already bound.
function Atlas.composeCut(atlas, from, slot, rows)
  compose(atlas, from, slot, 0)
  local c = atlas.cols
  local tx, ty = (slot % c) * 16, math.floor(slot / c) * 16
  local pts = {}
  for y = 0, 15 do
    local r = rows[y]
    for x = 0, 15 do
      if math.floor(r / 2 ^ x) % 2 == 1 then
        pts[#pts + 1] = tx + x + 0.5
        pts[#pts + 1] = ty + y + 0.5
      end
    end
  end
  if #pts > 0 then
    love.graphics.push("all")
    love.graphics.setBlendMode("replace")
    love.graphics.setColor(0, 0, 0, 0)
    love.graphics.points(pts)
    love.graphics.pop()
  end
end

-- Does ground variant `var` belong to the pair `layout` draws with?  The
-- variant's own layout names the tileset it was made from: its primary for a
-- metatile < 512, else its secondary.
function Atlas.variantFits(var, layout)
  local L = Data.layouts
  local mine, theirs = L and L[layout], L and L[var.layout]
  if not (mine and theirs) then return false end
  if var.metatile < 512 then return mine.primary == theirs.primary end
  return mine.secondary == theirs.secondary
end

function Atlas.forMap(map)
  local record = recordOf(map)
  if not (record and record.bottom and record.top) then return nil end
  local layout = map.def and map.def.layoutId
  local key = record
  local hit = atlases[key]
  if hit then return hit end

  local c = cols()
  local statics = record.metatiles or 0
  local atlas = { record = record, cols = c, statics = statics, variantSlot = {}, layout = layout,
                  byMetatile = {} }
  local slots = statics
  for v, var in pairs((Data.buildings and Data.buildings.variants) or {}) do
    if v < 128 and var.metatile < statics and Atlas.variantFits(var, layout) then
      atlas.variantSlot[v] = slots
      local list = atlas.byMetatile[var.metatile] or {}
      list[#list + 1] = v
      atlas.byMetatile[var.metatile] = list
      slots = slots + 1
    end
  end
  -- the relief's cut tiles: the metatile with its background made clear
  atlas.cutSlot, atlas.cutsByMetatile = {}, {}
  for k, var in pairs((Data.relief and Data.relief.cutVariants) or {}) do
    if var.metatile < statics and Atlas.variantFits(var, layout) then
      atlas.cutSlot[k] = slots
      local list = atlas.cutsByMetatile[var.metatile] or {}
      list[#list + 1] = k
      atlas.cutsByMetatile[var.metatile] = list
      slots = slots + 1
    end
  end
  -- one slot of flat colours for the parts Emerald 3DS draws untextured
  -- (voxel_atlas.c sSolidColors): a television's grey stand and black body
  atlas.solidSlot = slots
  slots = slots + 1
  atlas.width = c * 16
  atlas.height = math.max(16, math.ceil(slots / c) * 16)
  local ok, canvas = pcall(love.graphics.newCanvas, atlas.width, atlas.height)
  if not ok then return nil end
  canvas:setFilter("nearest", "nearest")
  canvas:setWrap("clamp", "clamp")
  atlas.canvas = canvas

  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("alpha", "alphamultiply")
  -- the static grid in one go: bottom, then top over it, same layout
  local sheetW, sheetH = record.width, record.height
  local staticH = math.ceil(statics / c) * 16
  local q = love.graphics.newQuad(0, 0, sheetW, math.min(staticH, sheetH), sheetW, sheetH)
  love.graphics.draw(record.bottom, q, 0, 0)
  love.graphics.draw(record.top, q, 0, 0)
  do
    local sx, sy = (atlas.solidSlot % c) * 16, math.floor(atlas.solidSlot / c) * 16
    for k, rgb in ipairs(Atlas.SOLIDS) do
      love.graphics.setColor(rgb[1] / 31, rgb[2] / 31, rgb[3] / 31, 1)
      love.graphics.rectangle("fill", sx + ((k - 1) % 4) * 4, sy + math.floor((k - 1) / 4) * 4, 4, 4)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  for v, slot in pairs(atlas.variantSlot) do
    local var = Data.buildings.variants[v]
    compose(atlas, var.metatile, slot, var.quarters)
  end
  for k, slot in pairs(atlas.cutSlot) do
    Atlas.composeCut(atlas, Data.relief.cutVariants[k].metatile, slot, Data.relief.cutVariants[k].rows)
  end
  love.graphics.pop()

  atlases[key] = atlas
  return atlas
end

-- Bring the animated slots to the frame the map's own renderer shows.
function Atlas.animate(atlas, map)
  local record = atlas.record
  if not (record.animSlots and map and map.renderer and map.renderer.gen3AnimFrame) then return end
  local ok, frame = pcall(map.renderer.gen3AnimFrame, map.renderer)
  if not ok or frame == nil or frame == atlas.frame then return end
  if not (pcall(record.bottom.getWidth, record.bottom) and pcall(record.top.getWidth, record.top)) then return end
  atlas.frame = frame
  love.graphics.push("all")
  local okDraw, err = pcall(Atlas.redrawAnimated, atlas, record)
  love.graphics.pop()
  if not okDraw then error(err, 0) end
end

function Atlas.redrawAnimated(atlas, record)
  love.graphics.setCanvas(atlas.canvas)
  love.graphics.setColor(1, 1, 1, 1)
  for id, slots in pairs(record.animSlots) do
    if id < atlas.statics then
      local from = slots[atlas.frame + 1] or id
      local c = atlas.cols
      local tx, ty = (id % c) * 16, math.floor(id / c) * 16
      love.graphics.setScissor(tx, ty, 16, 16)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setScissor()
      compose(atlas, from, id, 0)
      for _, v in ipairs(atlas.byMetatile[id] or {}) do
        local slot = atlas.variantSlot[v]
        local sx, sy = (slot % c) * 16, math.floor(slot / c) * 16
        love.graphics.setScissor(sx, sy, 16, 16)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setScissor()
        compose(atlas, from, slot, Data.buildings.variants[v].quarters)
      end
      for _, k in ipairs(atlas.cutsByMetatile[id] or {}) do
        local slot = atlas.cutSlot[k]
        local sx, sy = (slot % c) * 16, math.floor(slot / c) * 16
        love.graphics.setScissor(sx, sy, 16, 16)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setScissor()
        Atlas.composeCut(atlas, from, slot, Data.relief.cutVariants[k].rows)
      end
    end
  end
end

-- the flat colours, 5-bit as voxel_atlas.c gives them
Atlas.SOLIDS = { { 18, 13, 8 }, { 13, 9, 6 }, { 14, 14, 15 }, { 8, 8, 9 }, { 26, 24, 22 } }
Atlas.SOLID = { WOOD = 1, WOOD_DARK = 2, GREY = 3, BLACK = 4, SHEET = 5 }

-- A flat colour's UVs: the middle of its 4x4 patch.
function Atlas.solidUV(atlas, k)
  local c = atlas.cols
  local x = (atlas.solidSlot % c) * 16 + ((k - 1) % 4) * 4 + 1
  local y = math.floor(atlas.solidSlot / c) * 16 + math.floor((k - 1) / 4) * 4 + 1
  return x / atlas.width, y / atlas.height, (x + 2) / atlas.width, (y + 2) / atlas.height
end

-- Atlas id -> slot UVs, LOVE's way up: (u0, v0) the slot's north-west texel.
-- nil when the id has no slot on this pair.
function Atlas.uv(atlas, id)
  local slot
  if id < 1024 then
    if id >= atlas.statics then return nil end
    slot = id
  elseif id < 1152 then
    slot = atlas.variantSlot[id - 1024]
    if not slot then return nil end
  else
    slot = atlas.cutSlot and atlas.cutSlot[id - 1152]
    if not slot then return nil end
  end
  local c = atlas.cols
  local x, y = (slot % c) * 16, math.floor(slot / c) * 16
  return x / atlas.width, y / atlas.height, (x + 16) / atlas.width, (y + 16) / atlas.height
end

return Atlas
