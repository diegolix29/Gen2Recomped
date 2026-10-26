-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE PLAYER'S THROW, Platinum's and HeartGold / SoulSilver's.
--
-- The back the battle draws is not the linear sheet's first 80 x 80 frame
-- (member +4, all the import used): it is the cell sprite of +0 (800 tiles,
-- 1D), its cell bank +2 and its animation +3, and the animation's first
-- sequence IS the send-out -- HeartGold's hero: cells 0..7 held 8 / 16 / 6 /
-- 2 / 4 / 2 / 2 / 52 frames, the wind-up, the step, the throw and the follow-
-- through, then back to cell 0. Without it the picture stood still while the
-- ball came out of nowhere.
--
-- Every frame is assembled on ONE canvas, the union of the cells' boxes, so
-- the frames stay registered; a cell's coordinates are from the sprite's
-- centre, which is the battle position the still was centred on, so the
-- canvas's top left is that union's corner (`dx`, `dy`).
--
-- build(narc, class, Gen4Graphics) -> { image, width, height, count, play,
--   dx, dy } or nil

local M = {}

M.STRIDE = 5

function M.build(narc, class, G)
  local C = require("src.import.Gen4Cells")
  local CA = require("src.import.Gen4CellAnim")
  local function m(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local base = class * M.STRIDE
  local sheet = G.tiles(m(base))
  local bank = C.parse(m(base + 2), G)
  local anim = CA.parse(m(base + 3), G)
  local pal = G.palette(m(base + 1))
  if not (sheet and bank and anim and pal) then return nil end
  local frames = CA.frames(anim, 1)
  if not (frames and #frames > 1) then return nil end
  -- the union of the frames' cells
  local u0, v0, u1, v1
  local pics = {}
  for i, fr in ipairs(frames) do
    local cell = bank.cells[(fr.cell or fr.index or 0) + 1]
    local pic = cell and C.assemble(cell, sheet, pal, bank, G)
    local x, y = C.extent(cell)
    if pic and x then
      pics[i] = { pic = pic, x = x, y = y, dur = math.max(1, tonumber(fr.duration) or 1) }
      u0 = math.min(u0 or x, x); v0 = math.min(v0 or y, y)
      u1 = math.max(u1 or x + pic.width, x + pic.width); v1 = math.max(v1 or y + pic.height, y + pic.height)
    end
  end
  if not u0 then return nil end
  local W, H = u1 - u0, v1 - v0
  -- de-duplicated pictures, side by side, and the play list over them
  local order, byCell, strip = {}, {}, {}
  local play = {}
  for i, fr in ipairs(frames) do
    local p = pics[i]
    if p then
      local key = tostring(fr.cell or fr.index or 0)
      local k = byCell[key]
      if not k then
        local canvas = {}
        for j = 1, W * H do canvas[j] = "\0\0\0\0" end
        for y = 0, p.pic.height - 1 do
          for x = 0, p.pic.width - 1 do
            local o = (y * p.pic.width + x) * 4
            local px = p.pic.rgba:sub(o + 1, o + 4)
            if px:byte(4) > 0 then canvas[(p.y - v0 + y) * W + (p.x - u0 + x) + 1] = px end
          end
        end
        order[#order + 1] = canvas
        k = #order
        byCell[key] = k
      end
      play[#play + 1] = { frame = k, dur = p.dur }
    end
  end
  local n = #order
  for y = 0, H - 1 do
    local row = {}
    for f = 1, n do
      row[f] = table.concat(order[f], "", y * W + 1, (y + 1) * W)
    end
    strip[y + 1] = table.concat(row)
  end
  return { image = { width = W * n, height = H, rgba = table.concat(strip) },
           width = W, height = H, count = n, play = play, dx = u0, dy = v0 }
end

return M
