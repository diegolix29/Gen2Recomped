-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DRAWING THE PATCH OF DARK.  `Gen4Shadow` is where the cartridge's rules were
-- read out of the ROM; this is the twenty lines that put them on screen.
--
-- Nil for every other generation and for a Platinum cache imported before the
-- shadow stage, so the caller tests once and forgets about it.

-- `src.render.Assets`, not `src.core.Assets` -- the latter does not exist and
-- this crashed the first frame that drew a Gen 4 map.
local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Gen4Shadows = {}
Gen4Shadows.__index = Gen4Shadows

-- The texture is 16 pixels across and stands for however many WORLD UNITS the
-- size table says.  One unit is one pixel on this port's ground, so the scale
-- is the size over the texture.
local TEXTURE_PX = 16

-- How dark.  The cartridge draws the model with its own alpha; this is the
-- texture's own coverage multiplied down so a shadow reads as shade rather
-- than as a hole -- the one number here that is a judgement rather than a
-- measurement, and it is the only one.
local ALPHA = 0.45

function Gen4Shadows.forMap(data)
  local record = data and data.constants and data.constants.gen4Shadow
  if not (record and record.byGraphics and record.image) then return nil end
  local ok, image = pcall(Assets.image, record.image.path)
  if not (ok and image) then
    Logger.warn("gen4 shadow: the texture (%s) would not load; characters will "
                .. "cast none", tostring(record.image.path))
    return nil
  end
  local suppress = {}
  for _, behaviour in ipairs(record.suppress or {}) do suppress[behaviour] = true end
  return setmetatable({
    image = image,
    byGraphics = record.byGraphics,
    sizes = record.sizes or { 14 },
    scales = record.scales or { { x = 1, z = 1 } },
    suppress = suppress,
    ox = image:getWidth() / 2,
    oy = image:getHeight() / 2,
  }, Gen4Shadows)
end

-- Which of the five shadows this entity casts, or nil for none.
--
-- THE PLAYER HAS NO DEF, and is `OBJ_EVENT_GFX_PLAYER_M` -- graphics id 0 --
-- which the table says casts one.  An NPC carries its own id on its def.
local reported = {}

-- ONE LINE PER ENTITY PER REASON, and never again.
--
-- A shadow that does not appear is silent by nature: every gate below returns
-- the same `false` whether the row is missing, the cell is unknown or the
-- floor suppresses it.  Reported from play as *"im only seein the shadows
-- under the player and not for the object"*, and three rounds of reading code
-- could not separate those cases, because from outside they are one case.
local function report(entity, reason, detail)
  local def = entity and entity.def
  local id = def and (def.graphicsId or def.graphics or def.graphicsID)
  local key = reason .. ":" .. tostring(id) .. ":" .. tostring(entity and entity.id)
  if reported[key] then return end
  reported[key] = true
  Logger.info("gen4 shadow: %s for %s (graphics %s) -- %s",
              reason, tostring(entity and entity.id or "?"), tostring(id),
              tostring(detail))
end

function Gen4Shadows:variantFor(entity, isPlayer)
  local def = entity and entity.def
  -- THREE SPELLINGS, because the one the extractor writes is not the only one
  -- a def can reach this with: `objectHome` hands out a COPY of the record, a
  -- mod may build its own, and the map editor writes objects by hand.  Asking
  -- for all three costs a nil test and removes a whole class of "it works for
  -- the player and for nobody else".
  local id = def and (def.graphicsId or def.graphics or def.graphicsID)
  if id == nil and isPlayer then id = 0 end
  local row = id and self.byGraphics[tonumber(id) or -1]
  if not row then
    -- SAY WHICH ID MISSED, once each.  A shadow that silently does not appear
    -- is indistinguishable from one that is switched off, and that cost a
    -- round trip to find out.
    local key = "id:" .. tostring(id)
    if not reported[key] then
      reported[key] = true
      Logger.info("gen4 shadow: no row for graphics id %s (def fields: %s) -- "
                  .. "this object casts none",
                  tostring(id),
                  def and table.concat((function()
                    local out = {}
                    for k in pairs(def) do out[#out + 1] = tostring(k) end
                    table.sort(out)
                    return out
                  end)(), ",") or "no def")
    end
    return nil
  end
  if row.shadow == 0 then return nil end
  return row.shadow
end

-- draw(map, entity, camX, camY, isPlayer, rise)
--
-- `rise` is the camera offset the SPRITE is drawn with -- the terrain lift plus,
-- on a Gen 4 map, the ground's own compression.  Passing the sprite's number
-- rather than computing a second one is what keeps a shadow locked to the feet
-- it belongs to on a slope; deriving it separately would drift by however much
-- the two disagree about where the entity is.
function Gen4Shadows:draw(map, entity, camX, camY, isPlayer, rise)
  local variant = self:variantFor(entity, isPlayer)
  if not variant then return false end
  local cx, cy = entity.cellX, entity.cellY
  if not (cx and cy and map) then
    report(entity, "no cell", ("cellX=%s cellY=%s map=%s"):format(
      tostring(cx), tostring(cy), tostring(map ~= nil)))
    return false
  end
  -- THE NINE BEHAVIOURS THAT TURN IT OFF -- tall grass, water, puddles, snow,
  -- mud, a reflective floor.  A character in long grass has no shadow because
  -- the grass is over their feet; one on polished stone has a reflection
  -- instead.
  if map.cellTile then
    local behaviour = map:cellTile(cx, cy)
    if self.suppress[behaviour] then
      -- SAY WHICH BEHAVIOUR, once per entity.  "suppressed" and "no row" look
      -- identical from the outside -- no shadow either way -- and the whole
      -- reason this took several rounds to pin down is that nothing said which
      -- of the two had happened.
      report(entity, "suppressed", ("tile behaviour %s at cell %d,%d"):format(
        tostring(behaviour), cx, cy))
      return false
    end
  end

  local size = self.sizes[variant] or self.sizes[1] or 14
  local scale = self.scales[variant] or self.scales[1] or { x = 1, z = 1 }
  local sx = (size * (scale.x or 1)) / TEXTURE_PX
  local sy = (size * (scale.z or 1)) / TEXTURE_PX

  -- ON THE CELL'S CENTRE, which is where the cartridge puts the object itself:
  -- `MAP_OBJECT_COORD_CENTER_TO_FX32` is `(tile << 4) + 8`.  Taking the
  -- sprite's own top-left would put the shadow wherever the art happens to be
  -- padded to.
  -- THE PIXEL POSITION, NOT THE CELL.
  --
  -- Reported from play: *"the shadows under the player arent smooth theyre
  -- jumping per tile"*.  They were: this took `cellX * 16 + 8`, which is the
  -- tile the entity is CONSIDERED to be on and only changes when a step
  -- completes, so the shadow teleported a tile at a time while the sprite slid
  -- between them.  `px`/`py` are the interpolated position, and `shiftPx` is
  -- the sub-tile offset the walk animation carries -- the same three terms
  -- `riseOf` asks the terrain about, so the two agree by construction.
  --
  -- MINUS the rise, not plus: the sprite is drawn at `py - (camY + rise)`, so
  -- a positive rise moves it UP the screen and the shadow has to move with it.
  local ex = (entity.px or cx * 16) + (entity.shiftPx or 0) + 8
  local ey = (entity.py or cy * 16) + 8
  local px = ex - camX
  local py = ey - camY - (rise or 0)

  local g = love.graphics
  local r, gg, b, a = g.getColor()
  g.setColor(0, 0, 0, ALPHA)
  g.draw(self.image, px, py, 0, sx, sy, self.ox, self.oy)
  g.setColor(r, gg, b, a)
  return true
end

return Gen4Shadows
