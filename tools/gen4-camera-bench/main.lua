-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE CAMERA BENCH. Run it with LOVE and look at the picture:
--
--     love tools/gen4-camera-bench
--
-- and headless, which is how it was used:
--
--     xvfb-run -a -s "-screen 0 800x600x24" love tools/gen4-camera-bench
--
-- It writes `drift.png` into LOVE's save directory and prints the numbers.
--
-- It needs no ROM and no cache -- it draws the tile rows twice, once through the
-- projection `Gen4Ground` uses (the cartridge's z*sin - y*cos) and once through
-- the flat 16px grid the sprite path uses, and puts a post on each row so the two
-- can be compared by eye as well as by number. The posts walk off the compressed
-- ground, which is the fault this bench exists to show.

-- THE GROUND AND THE THINGS STANDING ON IT DISAGREE.
-- Gen4Ground projects with the cartridge's z*sin - y*cos. The sprite path does
-- not project at all: it places everything on the flat 16px tile grid. This
-- draws both and measures how far apart they end up.
-- Run from the repo root, or from the bench folder.
package.path = "./?.lua;../../?.lua;" .. package.path
local Cam = require("src.render.Gen4Camera")
local W, H = 256, 256
local cfg = Cam.forType(0)
local s, c = Cam.scales(cfg)

local function groundY(z) return z * s end   -- what Gen4Ground's matrix does
local function spriteY(z) return z end       -- what the sprite path does

local shot, reported = false, false
function love.load() love.window.setMode(W * 2 + 30, H + 70) end

local function scene(ox, mode)
  love.graphics.push(); love.graphics.translate(ox, 24)
  for row = 0, 13 do
    local z = row * 16
    local y = (mode == "ground") and groundY(z) or spriteY(z)
    love.graphics.setColor(row % 2 == 0 and 0.30 or 0.37, row % 2 == 0 and 0.46 or 0.53, 0.28)
    local y2 = (mode == "ground") and groundY(z + 16) or spriteY(z + 16)
    love.graphics.rectangle("fill", 0, y, 220, y2 - y)
    -- a "post" standing on this tile: where the SPRITE path would put it
    love.graphics.setColor(0.95, 0.75, 0.2)
    love.graphics.rectangle("fill", 20 + row * 14, spriteY(z) - 10, 6, 12)
    -- ...and where the GROUND actually is for that same tile
    love.graphics.setColor(0.9, 0.25, 0.25)
    love.graphics.rectangle("fill", 20 + row * 14, groundY(z) - 2, 6, 3)
  end
  love.graphics.pop()
end

function love.draw()
  love.graphics.clear(0.07,0.07,0.09)
  scene(10, "ground")
  scene(W + 25, "sprite")
  love.graphics.setColor(1,1,1)
  love.graphics.print("LEFT: ground rows (sin-compressed) with sprite posts on top", 8, 4)
  love.graphics.print("RIGHT: the flat grid the sprite path uses", W + 25, 4)
  local drift = spriteY(13 * 16) - groundY(13 * 16)
  love.graphics.print(("drift at tile 13: %.1f px (%.1f tiles)"):format(drift, drift / 16), 8, H + 30)
  love.graphics.print(("sin(pitch) = %.4f -- ground keeps %.1f%% of its depth"):format(s, s * 100), 8, H + 46)
  if not reported then
    reported = true
    io.write(("sin=%.4f cos=%.4f\n"):format(s, c))
    for _, tiles in ipairs({1, 4, 8, 12, 16}) do
      local z = tiles * 16
      io.write(("tile %2d (z=%3d): ground %.1f px, sprite %.1f px, drift %.1f px (%.2f tiles)\n")
        :format(tiles, z, groundY(z), spriteY(z), spriteY(z) - groundY(z), (spriteY(z) - groundY(z)) / 16))
    end
    io.write(("a 192px screen shows %.1f world units of ground, %.1f of sprite grid\n")
      :format(192 / s, 192))
  end
end
function love.update()
  if reported and not shot then
    shot = true
    love.graphics.captureScreenshot(function(img) img:encode("png","drift.png"); love.event.quit() end)
  end
end
