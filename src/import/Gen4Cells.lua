-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- NCER: cell banks, which is how a Gen 4 sprite knows its own shape.
--
-- A tilemap says where every 8x8 cell of a BACKGROUND goes.  A sprite has no
-- tilemap.  It is drawn by the hardware's object engine from a handful of OAM
-- entries, each one a rectangle of tiles placed at a signed offset from the
-- sprite's centre -- and the NCGR that holds those tiles records no width at
-- all.  Its tilesX and tilesY are 0xFFFF.
--
-- That is why a sheet laid out at a guessed width looks like the right picture
-- cut into strips and stacked in the wrong order: the pixels were never wrong,
-- the arrangement simply was not in the file being read.  It is in this one.
--
-- WHAT IS IN AN NCER.  One KBEC section (the tag is stored reversed, as
-- everywhere else in Nitro), holding:
--
--   u16 cellCount
--   u16 bankAttributes   -- bit 0: every cell carries a bounding rectangle
--   u32 cellDataOffset   -- relative to the section's fields
--   u32 mappingMode      -- the tile-boundary exponent; see BOUNDARY below
--
-- then one record per cell -- OAM count, cell attributes, an offset into the
-- shared OAM block -- and then the OAM entries themselves, three u16 each,
-- in the same layout the DS object engine takes them.
--
-- THE MAPPING MODE IS NOT DECORATION.  A tile index in OAM is counted in
-- units of `32 << mappingMode` bytes, not in tiles.  Platinum's banks use
-- mode 1, so a 4bpp index steps two tiles at a time, and reading it as tiles
-- halves every offset -- which draws a real sprite assembled out of the wrong
-- halves of itself.  It is the single easiest thing here to get wrong and the
-- hardest to spot, because the result is plausible.
--
-- POSITIONS ARE SIGNED AND CENTRED.  OAM Y is 8 bits and X is 9, both two's
-- complement, measured from the sprite's origin.  Treating them as unsigned
-- puts every piece that should sit above or left of centre at the far side of
-- a 256-pixel field instead.

local Gen4Cells = {}

local byte, floor = string.byte, math.floor

local function u16(s, at)
  local a, b = byte(s, at, at + 1)
  if not b then return nil end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = byte(s, at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- OAM shape and size together pick one of twelve rectangles.  Sizes are in
-- PIXELS.  Shape 3 does not exist on the hardware and is left nil so a bad
-- read fails rather than silently becoming 8x8.
Gen4Cells.DIMENSIONS = {
  [0] = { [0] = { 8, 8 },  [1] = { 16, 16 }, [2] = { 32, 32 }, [3] = { 64, 64 } },
  [1] = { [0] = { 16, 8 }, [1] = { 32, 8 },  [2] = { 32, 16 }, [3] = { 64, 32 } },
  [2] = { [0] = { 8, 16 }, [1] = { 8, 32 },  [2] = { 16, 32 }, [3] = { 32, 64 } },
}

-- parse(data) -> { count, boundary, cells = { { oam = {...}, bounds } } }
function Gen4Cells.parse(data, Gen4Graphics)
  local container = Gen4Graphics.container(data)
  if not container then return nil, "not a cell bank" end
  local section = container.sections.KBEC
  if not section then return nil, "NCER has no KBEC section" end

  local body = section.body
  local d = container.data
  local count = u16(d, body)
  local attributes = u16(d, body + 2) or 0
  local cellDataOffset = u32(d, body + 4) or 24
  local mappingMode = u32(d, body + 8) or 0
  if not count then return nil, "NCER header is truncated" end

  -- Tile indices are counted in units of this many bytes.
  local boundary = 32 * 2 ^ mappingMode

  local hasBounds = (attributes % 2) == 1
  local stride = hasBounds and 16 or 8
  local recordsAt = body + cellDataOffset
  local oamAt = recordsAt + count * stride

  local cells = {}
  for i = 0, count - 1 do
    local at = recordsAt + i * stride
    local oamCount = u16(d, at)
    local oamOffset = u32(d, at + 4)
    if not (oamCount and oamOffset) then break end

    local cell = { oam = {}, index = i }
    if hasBounds then
      local function s16(v) return v and (v >= 32768 and v - 65536 or v) or nil end
      cell.bounds = {
        maxX = s16(u16(d, at + 8)), maxY = s16(u16(d, at + 10)),
        minX = s16(u16(d, at + 12)), minY = s16(u16(d, at + 14)),
      }
    end

    for j = 0, oamCount - 1 do
      local entry = oamAt + oamOffset + j * 6
      local a0, a1, a2 = u16(d, entry), u16(d, entry + 2), u16(d, entry + 4)
      if not a2 then break end

      local y = a0 % 256
      if y >= 128 then y = y - 256 end          -- 8-bit signed
      local shape = floor(a0 / 16384) % 4
      local depth8 = floor(a0 / 8192) % 2 == 1
      local disabled = floor(a0 / 512) % 2 == 1 and floor(a0 / 256) % 2 == 0

      local x = a1 % 512
      if x >= 256 then x = x - 512 end          -- 9-bit signed
      local size = floor(a1 / 16384) % 4
      local flipX = floor(a1 / 4096) % 2 == 1
      local flipY = floor(a1 / 8192) % 2 == 1

      local tile = a2 % 1024
      local palette = floor(a2 / 4096) % 16

      local dimension = Gen4Cells.DIMENSIONS[shape]
      dimension = dimension and dimension[size]
      if dimension and not disabled then
        cell.oam[#cell.oam + 1] = {
          x = x, y = y,
          width = dimension[1], height = dimension[2],
          tile = tile, palette = palette,
          flipX = flipX, flipY = flipY,
          depth8 = depth8,
        }
      end
    end
    cells[#cells + 1] = cell
  end

  return {
    count = count,
    cells = cells,
    boundary = boundary,
    mappingMode = mappingMode,
    hasBounds = hasBounds,
  }
end

-- extent(cell) -> minX, minY, width, height, in pixels.
--
-- Computed from the OAM entries rather than from the stored bounding
-- rectangle.  The stored one is what the game uses for collision and is
-- sometimes larger than the art; the drawn extent is what an image should be
-- cropped to.
function Gen4Cells.extent(cell)
  if not cell or #cell.oam == 0 then return nil end
  local minX, minY, maxX, maxY
  for _, o in ipairs(cell.oam) do
    local x2, y2 = o.x + o.width, o.y + o.height
    minX = (minX == nil or o.x < minX) and o.x or minX
    minY = (minY == nil or o.y < minY) and o.y or minY
    maxX = (maxX == nil or x2 > maxX) and x2 or maxX
    maxY = (maxY == nil or y2 > maxY) and y2 or maxY
  end
  return minX, minY, maxX - minX, maxY - minY
end

-- assemble(cell, sheet, palette, bank, Gen4Graphics) -> { width, height, rgba }
--
-- Draws one cell: every OAM entry, in reverse order so that entry 0 ends up on
-- top, which is the hardware's priority rule.
function Gen4Cells.assemble(cell, sheet, palette, bank, Gen4Graphics)
  if not (cell and sheet and palette) then return nil end
  local minX, minY, width, height = Gen4Cells.extent(cell)
  if not width or width <= 0 or height <= 0 then return nil end

  -- Rebuild the cell as a tilemap over the same sheet, so that composition
  -- stays in one place.  Every OAM entry is a run of tiles in reading order
  -- within its own rectangle; that is what 1D mapping means.
  local cols = floor(width / 8)
  local rows = floor(height / 8)
  local cells = {}
  for i = 1, cols * rows do
    cells[i] = { tile = 0, flipX = false, flipY = false, palette = 0, blank = true }
  end

  local perTile = sheet.perTile or (sheet.bpp == 8 and 64 or 32)
  local step = floor((bank and bank.boundary or 32) / perTile)
  if step < 1 then step = 1 end

  for i = #cell.oam, 1, -1 do
    local o = cell.oam[i]
    local wide, high = floor(o.width / 8), floor(o.height / 8)
    local base = o.tile * step
    for ty = 0, high - 1 do
      for tx = 0, wide - 1 do
        -- Flipping a multi-tile OAM entry mirrors the whole rectangle, so the
        -- tile that lands here comes from the opposite corner AND is itself
        -- drawn mirrored.  Flipping only the tiles, or only their order,
        -- produces a sprite that is subtly scrambled rather than mirrored.
        local sx = o.flipX and (wide - 1 - tx) or tx
        local sy = o.flipY and (high - 1 - ty) or ty
        local gx = floor((o.x - minX) / 8) + tx
        local gy = floor((o.y - minY) / 8) + ty
        if gx >= 0 and gx < cols and gy >= 0 and gy < rows then
          cells[gy * cols + gx + 1] = {
            tile = base + sy * wide + sx,
            flipX = o.flipX, flipY = o.flipY,
            palette = o.palette,
          }
        end
      end
    end
  end

  return Gen4Graphics.compose(
    { width = cols * 8, height = rows * 8, cells = cells }, sheet, palette)
end

return Gen4Cells
