-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S DOWSING MCHN.
--
-- Using it from the bag (fieldUseFunc 26, ItemMenuUseFunc_DowsingMchn ->
-- Task_ActivateDowsingMchnUI, pokeheartgold src/field_use_item.c) switches the
-- touch-screen field app to mode 4 (ov01_021F6A9C(fieldSystem, 4, NULL),
-- overlay 28). It is not a Pokegear app. Until now the bag answered
-- "hgss_dowsing" and nothing caught it, so the item did nothing at all.
--
-- THE SEARCH (AllocAndFetchNearbyHiddenItems, src/script_manager.c): every
-- background event of type 2 whose flag (HiddenItemScriptNoToFlagId: script
-- - 8000 + 800) is clear, inside x -17..+17 and z -17..+17 of the player
-- (the low edges clamped to 0), each as an offset from the player.
--
-- THE NEAREST (ov28_0225DD58): smallest |dx| + |dz|, the first one kept on a
-- tie.
--
-- THE READING (ov28_0225E1A4), on the nearest one's |dx| and |dz| both
-- within a bound: 8 -> state 4, 12 -> 3, 17 -> 2, else 1; no item -> 0. The
-- machine re-polls every frame while the mode is on.
--
-- The touch screen's own art is not decoded; the reading is drawn over the
-- field, as Gen5Dowsing does for Black / White: a lamp whose blink speeds up
-- with the state, and the two rods leaning toward the item.

local D = {}

D.FLAG_BASE = 800
D.SCRIPT_BASE, D.SCRIPT_LAST = 8000, 8799
D.RADIUS = 17
D.TIERS = { { 8, 4 }, { 12, 3 }, { 17, 2 } }

local function Game() return package.loaded["src.core.Game"] end

function D.flagKey(sign)
  local sc = tonumber(sign and sign.script)
  if not (sc and sc >= D.SCRIPT_BASE and sc <= D.SCRIPT_LAST) then return nil end
  return ("FLAG_G4_%04X"):format(D.FLAG_BASE + sc - D.SCRIPT_BASE)
end

local function flagsOf(save)
  if save then return save.flags end
  local G = Game()
  return G and G.save and G.save.flags
end

-- the map's unpicked hidden items (bg events of type 2), { x, y, sign }
function D.items(def, save)
  local out = {}
  if not def then return out end
  local flags = flagsOf(save) or {}
  for _, s in ipairs(def.signs or {}) do
    local hidden = (s.pickup and s.pickup.kind == "hidden") or s.kind == 2
    local key = hidden and D.flagKey(s)
    if key and not flags[key] then out[#out + 1] = { x = s.x, y = s.y, sign = s } end
  end
  return out
end

-- nearest(def, px, py, save) -> item, dx, dy (item - player), or nil
function D.nearest(def, px, py, save)
  local R = D.RADIUS
  local left, top = math.max(0, px - R), math.max(0, py - R)
  local best, bd, bx, by
  for _, it in ipairs(D.items(def, save)) do
    if it.x >= left and it.x <= px + R and it.y >= top and it.y <= py + R then
      local dx, dy = it.x - px, it.y - py
      local d = math.abs(dx) + math.abs(dy)
      if not bd or d < bd then best, bd, bx, by = it, d, dx, dy end
    end
  end
  return best, bx, by
end

-- the machine's state for an offset (0 = nothing found)
function D.state(dx, dy)
  if not dx then return 0 end
  local ax, ay = math.abs(dx), math.abs(dy)
  for _, t in ipairs(D.TIERS) do
    if ax <= t[1] and ay <= t[1] then return t[2] end
  end
  return 1
end

function D.reading(ow)
  local p = ow and ow.player
  local def = ow and ow.map and ow.map.def
  if not (p and def) then return 0 end
  local it, dx, dy = D.nearest(def, p.cellX, p.cellY)
  return D.state(dx, dy), it, dx, dy
end

function D.toggle(game, ow)
  ow.hgssDowsing = (not ow.hgssDowsing) or nil
  if ow.hgssDowsing then
    pcall(function() require("src.core.Sound").play(game and game.data, "SEQ_SE_DP_DECIDE") end)
  end
end

-- the reading over the field while the machine is on
function D.draw(ow, w, h)
  if not (ow and ow.hgssDowsing) then return end
  local state, it, dx, dy = D.reading(ow)
  local g = love.graphics
  g.push("all")
  local cx, cy, r = w - 40, 40, 30
  g.setColor(0.05, 0.1, 0.08, 0.7)
  g.circle("fill", cx, cy, r + 4)
  g.setLineWidth(3)
  if it and state > 0 then
    local a = math.atan2(dy, dx)
    local spread = ({ 0.9, 0.6, 0.35, 0.12 })[state] or 0.9
    g.setColor(0.95, 0.85, 0.2, 1)
    for _, s in ipairs({ -spread, spread }) do
      g.line(cx, cy, cx + math.cos(a + s) * r, cy + math.sin(a + s) * r)
    end
    local t = love.timer and love.timer.getTime() or 0
    local on = (dx == 0 and dy == 0) or math.floor(t * state * 2) % 2 == 0
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
