-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HOW WIDE A FULL-SCREEN GEN 3 PICTURE ASKS TO BE.
--
-- Asked for directly: "ensure that the main menu and intro animations extend
-- to wide screen and fill the screen without black borders".
--
-- Emerald draws on 240x160 and almost no window is 3:2, so a screen that fills
-- the window with its aspect kept sits between two black bars.  The two ways
-- out of that are both wrong: stretching the edge smears it (which is what the
-- bleed did, and what got turned off), and zooming until the width fills crops
-- the top and bottom off art the cartridge composed to fit.
--
-- The third way is to ask for a WIDER SURFACE and put the cartridge's own
-- scenery in it.  That is only honest where the extra width can be filled with
-- something the cartridge actually has, and on the title screen it can: the
-- backdrop is a vertical gradient, one flat colour per row, so the sky beside
-- the picture is the same colour the row already is (Gen3Scene.skyColumn), and
-- the cloud field is a background the cartridge itself scrolls and wraps.
--
-- Height never changes.  A GBA screen is 160 rows and every layout on it is
-- measured from the top and the bottom; only the horizontal slack is new.

local Gen3Wide = {}

local BASE_W, BASE_H = 240, 160

-- Never narrower than the cartridge's own screen, and capped so a very wide
-- or very short window cannot ask for a surface with more slack than there is
-- scenery to put in it.  352 is 240 plus two 56-pixel margins, which covers
-- 21:9 at this height.
local MIN_W, MAX_W = BASE_W, 352

function Gen3Wide.baseSize() return BASE_W, BASE_H end

-- The surface width for the window as it is now, quantised to whole tiles so
-- that dragging a window edge does not reallocate the canvas on every pixel.
function Gen3Wide.uiSize()
  local g = love and love.graphics
  if not (g and g.getDimensions) then return BASE_W, BASE_H end
  local ok, ww, wh = pcall(g.getDimensions)
  if not ok or not (ww and wh) or wh <= 0 then return BASE_W, BASE_H end
  -- quantised to four pixels: enough that dragging a window edge does not
  -- reallocate the canvas every pixel, fine enough that the residual bar is
  -- never more than two, and always even so the picture's inset is a whole
  -- number of pixels
  local want = BASE_H * (ww / wh)
  want = math.floor(want / 4 + 0.5) * 4
  if want < MIN_W then want = MIN_W end
  if want > MAX_W then want = MAX_W end
  return want, BASE_H
end

-- Where the cartridge's own 240 columns sit inside that surface.
function Gen3Wide.inset(width)
  return math.floor(((width or BASE_W) - BASE_W) / 2)
end

-- Paint the slack either side of the picture with the backdrop's own sky.
--
-- `column` is a 1 x 160 image of each row's colour; stretching one pixel
-- sideways can only ever repeat a colour that is already the whole row, so
-- this fills the margin exactly rather than smearing anything.  With no column
-- to draw (a dataset with no title scene) nothing is painted and the margin
-- stays the window's own background, which is what it was before.
function Gen3Wide.fillSides(column, width, height)
  if not column then return false end
  local inset = Gen3Wide.inset(width)
  if inset <= 0 then return true end
  local _, ch = column:getDimensions()
  local sy = (height or BASE_H) / ch
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(column, 0, 0, 0, inset, sy)
  love.graphics.draw(column, inset + BASE_W, 0, 0, inset + 1, sy)
  return true
end

return Gen3Wide
