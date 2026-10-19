-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK AND WHITE'S HIDDEN ITEMS AND THE DOWSING MCHN.
--
-- A hidden item is a background event of kind 2 in the zone's event file,
-- its script 8000..8799 (script file 865); ov10's table at 0x2171534 (177
-- records of 10 bytes) gives each its flag, 900 + the record's index, and the
-- A-press loop (ov10 0x2162980) skips a record whose flag is set. The index
-- is the script id less 8000 (0x21646E8). The script gives the item and sets
-- that flag through a var (0x8002), which Gen4ScriptVM's BW setflag reads.
--
-- THE MACHINE (overlay 33): it looks at unpicked hidden items in a 32 x 24
-- window round the player -- x -15..+16, z -11..+12 (0x21F024A), the touch
-- screen's own grid -- picks the nearest by squared distance, and shows which
-- way it lies; zones 0x121..0x13C are left out (0x2013D74). This port draws
-- that reading over the field: the direction and how near.

local D = {}

D.FLAG_BASE = 900
D.SCRIPT_BASE, D.SCRIPT_LAST = 8000, 8799
D.WINDOW = { -15, 16, -11, 12 }
D.EXCLUDED = { 0x121, 0x13C }

local function Game() return package.loaded["src.core.Game"] end

function D.flagKey(sign)
  local sc = tonumber(sign and sign.script)
  if not (sc and sc >= D.SCRIPT_BASE and sc <= D.SCRIPT_LAST) then return nil end
  return ("FLAG_G4_%04X"):format(D.FLAG_BASE + sc - D.SCRIPT_BASE)
end

function D.taken(sign)
  local key = D.flagKey(sign)
  local G = Game()
  local flags = G and G.save and G.save.flags
  return key ~= nil and flags ~= nil and flags[key] == true
end

-- the map's unpicked hidden items: { x, y, sign }
function D.items(ow)
  local def = ow and ow.map and ow.map.def
  local out = {}
  if not (def and def.gen5) then return out end
  local zone = tonumber(def.header)
  if zone and zone >= D.EXCLUDED[1] and zone <= D.EXCLUDED[2] then return out end
  for _, s in ipairs(def.signs or {}) do
    if s.kind == 2 and D.flagKey(s) and not D.taken(s) then out[#out + 1] = { x = s.x, y = s.y, sign = s } end
  end
  return out
end

-- nearest(ow) -> item, dx, dy, or nil
function D.nearest(ow)
  local p = ow and ow.player
  if not p then return nil end
  local w = D.WINDOW
  local best, bd, bx, by
  for _, it in ipairs(D.items(ow)) do
    local dx, dy = it.x - p.cellX, it.y - p.cellY
    if dx >= w[1] and dx <= w[2] and dy >= w[3] and dy <= w[4] then
      local d = dx * dx + dy * dy
      if not bd or d < bd then best, bd, bx, by = it, d, dx, dy end
    end
  end
  return best, bx, by
end

function D.toggle(game, ow)
  ow.gen5Dowsing = (not ow.gen5Dowsing) or nil
  if ow.gen5Dowsing then
    pcall(function() require("src.core.Sound").playSe(game.data, "SEQ_SE_DECIDE1") end)
  end
end

-- the reading over the field while the machine is on (OverworldController's
-- HUD pass): two rods that swing toward the item and close as it nears,
-- and a lamp that blinks faster the closer it is
function D.draw(ow, w, h)
  if not (ow and ow.gen5Dowsing) then return end
  local it, dx, dy = D.nearest(ow)
  local g = love.graphics
  g.push("all")
  local cx, cy, r = w - 40, 40, 30
  g.setColor(0.05, 0.08, 0.12, 0.7)
  g.circle("fill", cx, cy, r + 4)
  g.setLineWidth(3)
  if it then
    local d = math.sqrt(dx * dx + dy * dy)
    local a = math.atan2(dy, dx)
    local spread = math.min(0.9, 0.12 + d / 18)
    g.setColor(0.95, 0.85, 0.2, 1)
    for _, s in ipairs({ -spread, spread }) do
      g.line(cx, cy, cx + math.cos(a + s) * r, cy + math.sin(a + s) * r)
    end
    local t = love.timer and love.timer.getTime() or 0
    local on = d < 1 or math.floor(t * (8 - math.min(7, d / 2))) % 2 == 0
    g.setColor(on and 1 or 0.35, on and 0.3 or 0.1, 0.1, 1)
    g.circle("fill", cx, cy, 5)
  else
    g.setColor(0.5, 0.5, 0.5, 1)
    g.line(cx - r * 0.6, cy + r * 0.2, cx, cy - r * 0.6)
    g.line(cx + r * 0.6, cy + r * 0.2, cx, cy - r * 0.6)
    g.circle("fill", cx, cy, 4)
  end
  g.pop()
end

return D
