-- Shared by tools/test_spritesolid.lua and tools/preview_spritesolid.lua.
-- Builds a 32x32-cell sheet that looks like a Platinum walker: 4 sides x
-- (stand, step, step) frames stacked vertically, 12 cells. Every side uses a
-- DIFFERENT shirt colour so a projection mistake is visible at a glance.
local F = {}

F.W, F.H = 32, 32
F.COLORS = {
  front = { 200, 40, 40 }, back = { 40, 70, 200 },
  right = { 40, 170, 60 }, left = { 220, 190, 40 },
}
local SKIN, HAIR, PANTS, SHOE = { 240, 200, 160 }, { 90, 55, 30 }, { 60, 60, 80 }, { 25, 25, 25 }

-- facings in the engine's shape: { stand, step1, step2 } per side
F.facings = {
  down = { 0, 1, 2 }, up = { 3, 4, 5 }, left = { 6, 7, 8 }, right = { 9, 10, 11 },
}
F.frames = 12

local function newSheet()
  local px = {}
  for i = 1, F.W * F.H * F.frames do px[i] = false end
  return px
end

local function put(px, frame, x, y, c)
  if x < 0 or x >= F.W or y < 0 or y >= F.H then return end
  px[(frame * F.H + y) * F.W + x + 1] = c
end

local function rect(px, f, x0, y0, x1, y1, c)
  for y = y0, y1 do for x = x0, x1 do put(px, f, x, y, c) end end
end

local function disc(px, f, cx, cy, r, c)
  for y = cy - r, cy + r do
    for x = cx - r, cx + r do
      if (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r + 0.5 then put(px, f, x, y, c) end
    end
  end
end

-- step = 0 stand, -1 / 1: which leg is forward (side views) / lifted (front)
local function front(px, f, shirt, face, step)
  disc(px, f, 16, 9, 5, face and SKIN or HAIR)
  if face then
    rect(px, f, 11, 4, 21, 6, HAIR)
    put(px, f, 14, 10, { 20, 20, 20 }); put(px, f, 18, 10, { 20, 20, 20 })
  end
  rect(px, f, 14, 14, 17, 14, SKIN)
  rect(px, f, 11, 15, 20, 23, shirt)
  rect(px, f, 8, 15, 10, 22, shirt); rect(px, f, 21, 15, 23, 22, shirt)
  rect(px, f, 8, 23, 10, 24, SKIN); rect(px, f, 21, 23, 23, 24, SKIN)
  local lift = (step ~= 0) and 1 or 0
  rect(px, f, 12, 24, 15, 29 - (step == -1 and lift or 0), PANTS)
  rect(px, f, 17, 24, 20, 29 - (step == 1 and lift or 0), PANTS)
  rect(px, f, 12, 30 - (step == -1 and lift or 0), 15, 31 - (step == -1 and lift or 0), SHOE)
  rect(px, f, 17, 30 - (step == 1 and lift or 0), 20, 31 - (step == 1 and lift or 0), SHOE)
end

-- facing = +1: the character faces screen-right (east sprite); -1 screen-left
local function side(px, f, shirt, facing, step)
  local function X(x) return facing == 1 and x or (31 - x) end
  local function r(x0, y0, x1, y1, c)
    local a, b = X(x0), X(x1)
    rect(px, f, math.min(a, b), y0, math.max(a, b), y1, c)
  end
  disc(px, f, X(16), 9, 5, SKIN)
  r(12, 4, 20, 6, HAIR); r(11, 7, 13, 11, HAIR)       -- hair, ponytail side
  put(px, f, X(22), 10, SKIN); put(px, f, X(22), 9, SKIN)   -- nose
  r(14, 14, 17, 14, SKIN)
  r(13, 15, 19, 23, shirt)
  r(14, 16, 18, 22, { shirt[1] // 2, shirt[2] // 2, shirt[3] // 2 })   -- arm
  r(14, 23, 18, 24, SKIN)
  -- legs: stride moves one forward, one back
  local fwd, back = 15 + step * 3, 15 - step * 3
  r(fwd - 1, 24, fwd + 2, 29, PANTS); r(back - 1, 24, back + 2, 29, PANTS)
  r(fwd - 1, 30, fwd + 3, 31, SHOE); r(back - 2, 30, back + 2, 31, SHOE)
end

function F.makeSheet()
  local px = newSheet()
  for slot = 1, 3 do
    local step = ({ 0, -1, 1 })[slot]
    front(px, F.facings.down[slot], F.COLORS.front, true, step)
    front(px, F.facings.up[slot], F.COLORS.back, false, step)
    side(px, F.facings.right[slot], F.COLORS.right, 1, step)
    side(px, F.facings.left[slot], F.COLORS.left, -1, step)
  end
  local out = {}
  for i = 1, #px do
    local c = px[i]
    out[i] = c and string.char(c[1], c[2], c[3], 255) or "\0\0\0\0"
  end
  return table.concat(out), F.W, F.H * F.frames
end

-- views + layout for one slot, in SpriteSolid's shape
function F.viewsFor(S, rgba, imgW, imgH, slot)
  local views, cellY = {}, {}
  for key, dir in pairs({ front = "down", back = "up", left = "left", right = "right" }) do
    local y0 = F.facings[dir][slot] * F.H
    views[key] = S.maskFromRGBA(rgba, imgW, imgH, 0, y0, F.W, F.H)
    cellY[key] = y0
  end
  return views, { imgW = imgW, imgH = imgH, cellW = F.W, cellH = F.H, cellX = 0, cellY = cellY }
end

return F
