-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- OPELUCID GYM (Black: zone 121, overlay 46): DRAYDEN'S DRAGONS.
--
-- Three dragon statues, each with a switch on either side of its base. The
-- gym's walkways are rail lines inside the 64 x 64 grid, and the overlay
-- turns six of them on or off per statue (its table at 0x21F4430, 0x60 bytes
-- a statue: lines 32/29/30/65/31/73, 10/13/11/70/12/71, 46/47/48/74/49/67):
--
--   * the save keeps, per statue, { head, switch 0, switch 1 } (12 bytes,
--     the gym block 0xA); 0x19A <statue, side> flips a switch, 0x199
--     <statue> recomputes the head from the two (0x21F3BC8: off/off 0,
--     on/on 1, on/off 2, off/on 3) and re-lists the lines
--   * 0x21F4078: every one of the six goes on the rail system's list of
--     opened lines, and the first two -- the NECK, rising from the head to
--     the floor above (16 -> 112 -> 96 units on the first dragon) -- come off
--     it again unless the head is 1, both switches pressed.  A listed line is
--     passable (0x21B9510 answers "open" for it before asking the line's own
--     default), so the head's arms and the floor ramps are always open and
--     the neck only with both switches down.
--   * 0x196 lists them as the save says when the gym loads; 0x197 / 0x198
--     are the switch's press and the player's step animations.
--
-- The lines run up the statues, which are gimmick models rather than
-- terrain, so their cells take the rail's height (gen4HeightEdits).

local G = {}

G.HEADER = 121
-- the overlay table's first row, which is how the import finds it
G.KEY = string.char(0x20, 0, 0, 0, 0x1D, 0, 0, 0, 0x1E, 0, 0, 0, 0x41, 0, 0, 0, 0x1F, 0, 0, 0, 0x49, 0, 0, 0)

-- ---------------------------------------------------------------- import

-- import(def, data, rom, blocksBefore): the statues' lines and the cells they
-- open, read from the gym's overlay; the cells that were solid before the
-- rails opened them are the ones a closed neck shuts again
function G.import(def, data, rom, blocksBefore)
  if def.header ~= G.HEADER or not (data and data.lines) then return nil end
  local tableAt, bin
  for o = 30, 70 do
    local ok, b = pcall(function() return rom:overlay(o) end)
    local at = ok and b and b:find(G.KEY, 1, true)
    if at then tableAt, bin = at - 1, b; break end
  end
  if not tableAt then return nil end
  local function u32(o) local a, b, c, d = bin:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
  local w = def.width
  local function solidBefore(cx, cz)
    local i = cz * w + cx
    return blocksBefore and blocksBefore:sub(i * 2 + 1, i * 2 + 2) ~= "\0\0"
  end
  local heights = def.gen4HeightEdits or {}
  local statues = {}
  for s = 0, 2 do
    local lines = {}
    for k = 0, 5 do lines[k + 1] = u32(tableAt + s * 0x60 + k * 4) end
    local neck, armCells = {}, {}
    for k, li in ipairs(lines) do
      local line = data.lines[li]
      local p, q = line and data.points[line.a], line and data.points[line.b]
      if p and q then
        local steps = math.max(1, math.ceil(math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2) / 4))
        for i = 0, steps do
          local t = i / steps
          local cx = math.floor((p.x + (q.x - p.x) * t) / 16)
          local cz = math.floor((p.z + (q.z - p.z) * t) / 16)
          local y = (p.y or 0) + ((q.y or 0) - (p.y or 0)) * t
          if cx >= 0 and cz >= 0 and cx < w and cz < def.height then
            if y ~= 0 then heights[cx .. "," .. cz] = math.floor(y + 0.5) end
            if k <= 2 and solidBefore(cx, cz) then neck[cx .. ":" .. cz] = true end
            -- a cell an always-open line also crosses (the head, where the
            -- arms meet the neck) stays open
            if k > 2 then armCells[cx .. ":" .. cz] = true end
          end
        end
      end
    end
    local cells = {}
    for c in pairs(neck) do if not armCells[c] then cells[#cells + 1] = c end end
    table.sort(cells)
    statues[s + 1] = { lines = lines, neck = cells }
  end
  def.gen4HeightEdits = heights
  def.gen5DragonGym = { statues = statues }
  return def.gen5DragonGym
end

-- ---------------------------------------------------------------- runtime

local function state(save)
  save.bwDragonGym = save.bwDragonGym or {}
  for s = 0, 2 do
    local k = tostring(s)
    save.bwDragonGym[k] = save.bwDragonGym[k] or { head = 0, [1] = 0, [2] = 0 }
  end
  return save.bwDragonGym
end
G.state = state

-- 0x21F3BC8
function G.headOf(rec)
  local a, b = rec[1] ~= 0, rec[2] ~= 0
  if not a and not b then return 0 end
  if not a and b then return 3 end
  if a and not b then return 2 end
  return 1
end

-- 0x196 / 0x199: shut every neck whose head is not 1 on the loaded map
function G.apply(ow, save)
  local map = ow and ow.map
  local gym = map and map.def and map.def.gen5DragonGym
  if not gym then return end
  local st = state(save)
  map.shutCells = map.shutCells or {}
  for s, statue in ipairs(gym.statues) do
    local open = (st[tostring(s - 1)].head == 1)
    for _, c in ipairs(statue.neck) do
      if open then map.shutCells[c] = nil else map.shutCells[c] = true end
    end
  end
end

-- 0x19A <statue, side>: flip switch `side` (0 or 1) of statue n
function G.flip(save, statue, side)
  local rec = state(save)[tostring(statue)]
  if not rec then return end
  local k = (side == 0) and 1 or 2
  rec[k] = (rec[k] ~= 0) and 0 or 1
end

-- 0x199 <statue>: the head from the switches, then the lines
function G.settle(ow, save, statue)
  local rec = state(save)[tostring(statue)]
  if not rec then return end
  rec.head = G.headOf(rec)
  G.apply(ow, save)
end

return G
