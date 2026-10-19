-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK AND WHITE'S FISHING LURE, the float the Super Rod puts on the water.
--
-- ov21's fishing task (0x21C5DF4, set up by 0x21C5D10):
--   * the lure's tile is the one in front of the player, or one further when
--     that tile's behaviour is 0x41 or 0x44 (0x21C5C64); it has to be water
--     (0x21AB3B0: 0x3D, 0x3E, 0x3F, 0x42, 0x43)
--   * 16 frames after the cast animation it is spawned (effect 0x21ADF94,
--     /a/0/7/5 member 84 `fishing_lure`), at the tile's centre, +3 units in z
--     when the player faces left or right (0x21D92E0)
--   * its BTP is not played: frame 1 idle, frame 3 once a fish bites --
--     both `fishing_lure.1`
--   * reeled in (A in the window) or a failure removes it; a failure with the
--     lure on a phenomenon spot also clears the spot (0x21AA8EC)

local L = {}

L.SKIP = { [0x41] = true, [0x44] = true }
L.TEXTURE = "84/fishing_lure.1"

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

function L.tile(ow)
  local p = ow and ow.player
  if not p then return nil end
  local d = DIRS[p.facing or "down"] or DIRS.down
  local x, y = p.cellX + d[1], p.cellY + d[2]
  local map = ow.map
  local b = map and map.inBounds and map:inBounds(x, y) and map:cellBehaviour(x, y)
  if b and L.SKIP[b] then x, y = x + d[1], y + d[2] end
  return x, y
end

function L.cast(ow)
  local x, y = L.tile(ow)
  if x then ow.gen5Lure = { x = x, y = y, facing = ow.player.facing } end
end

function L.remove(ow) if ow then ow.gen5Lure = nil end end

-- the rod put away: a miss at a phenomenon spot ends the spot
function L.reel(ow, caught)
  if not ow then return end
  if not caught and ow.gen5FishOnSpot then require("src.world.Gen5Phenomena").clear(ow) end
  ow.gen5FishOnSpot = nil
  ow.gen5Lure = nil
end

local img
function L.draw(ow, ground, cam)
  local lure = ow and ow.gen5Lure
  if not (lure and ground) then return end
  local Game = package.loaded["src.core.Game"]
  local fx = Game and Game.data and Game.data.gen5_field_effects
  if img == nil then
    local rec = fx and fx.textures and fx.textures[L.TEXTURE]
    img = false
    if rec and rec.rgba then
      local ok, made = pcall(function()
        local i = love.graphics.newImage(love.image.newImageData(rec.width, rec.height, "rgba8", rec.rgba))
        i:setFilter("nearest", "nearest")
        return i
      end)
      img = ok and made or false
    end
  end
  if not img then return end
  local g = love.graphics
  local px, py = lure.x * 16, lure.y * 16
  local side = (lure.facing == "left" or lure.facing == "right") and 3 or 0
  local w, h = img:getWidth(), img:getHeight()
  g.push("all")
  g.setColor(1, 1, 1, 1)
  local free = ground.freeMode and ground:freeMode()
  if free then
    ground:freeEntity(px, py, cam.x, cam.y, 0, function()
      g.draw(img, px + 8 - cam.x - w / 2, py + 12 + side - cam.y - h)
    end, 4)
  else
    local cx, cy = require("src.world.Gen4EmoteDraw").groundSpot(ground, px, py, cam)
    g.draw(img, math.floor(cx - w / 2), math.floor(cy - 4 + side * (ground.groundScale or 1) - h / 2))
  end
  g.pop()
end

return L
