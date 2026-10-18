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

-- THE GYM'S LEVELS. Its chunks carry two walking layers (GC, Gen5Field), and
-- they are not one floor: layer 2 differs from layer 1 on a DECK about 101
-- units up (6 tiles: the two trainers standing on it have gen5Level 6) that
-- runs over the floor's corridors -- row 34 lies on top of the floor's row
-- 34, row 41 over the entrance corridor -- and it is where the third
-- dragon's switches are, (21,27) and (33,27). The rails (the dragons' bodies,
-- necks and arms, and the spiral from the door to the trainer at (32,34))
-- run between the two at their own heights, 0 .. 192. The field picks, of
-- the surfaces under a step, the one nearest the walker's own height (ov21
-- 0x218DAEC: every candidate whose behaviour is not 0xFF, the least |dy|),
-- and refuses the step if that one is shut. Drayden's platform is layer 1's
-- rows 0..6 (height word 0x4E9) and is reached only up the third dragon's
-- neck (rail y 192, Drayden's gen5Level 12); the floor's (24,5) beside it,
-- and the slopes before it, are not a way up.
--
-- Here, the engine's elevation (Map:elevationBlocks / elevationAfter, the
-- Gen 3 rule) carries it: every surface is LOW (< 56 units: the floor, the
-- floor-level rails) or HIGH (the deck, the high rails, the platform); a
-- cell with one level gets it, a cell with both is 15 (kept: the bridge
-- rule), and where a rail climbs from one to the other its first high cell
-- is 0, the cell where the walker's level changes. Slope tiles (their plane
-- is not decoded) take the highest level of their known neighbours on the
-- same layer, and those before the platform are 3, a level no one walks at.
-- The deck's own cells are opened in the grid with layer 2's behaviour.
G.HIGH = 56

local function readLayers(def, rom)
  local Narc = require("src.import.NarcArchive")
  local M = require("src.import.Gen5Maps")
  local F = require("src.import.Gen5Field")
  local zones = M.zones(Narc.parse(rom:read(F.PATH.zones)):get(0))
  local z = zones[def.header]
  local mx = z and M.matrix(Narc.parse(rom:read(F.PATH.matrices)):get(z.matrix))
  if not mx then return nil end
  local chunkArc = Narc.parse(rom:read(F.PATH.chunks))
  local out = {}
  for my = 0, mx.height - 1 do
    for mxx = 0, mx.width - 1 do
      local c = mx.chunks[my * mx.width + mxx + 1]
      local ch = c and c ~= 0xFFFF and M.chunk(chunkArc:get(c)) or nil
      out[#out + 1] = { x0 = mxx * 32, y0 = my * 32, l1 = ch and ch.permissions, l2 = ch and ch.layer2 }
    end
  end
  return out
end

-- surfaces(def, data, rom) -> { deck = { ["x:y"] = true } } and writes
-- def.elevationCells; the deck cells opened in def.blocks
function G.surfaces(def, data, rom)
  local okR, recs = pcall(readLayers, def, rom)
  if not (okR and recs) then return nil end
  local w, h = def.width, def.height
  local function rec(layer, x, y)
    for _, r in ipairs(recs) do
      if x >= r.x0 and x < r.x0 + 32 and y >= r.y0 and y < r.y0 + 32 then
        local raw = (layer == 1) and r.l1 or r.l2
        if type(raw) ~= "string" then return nil end
        local at = 4 + ((y - r.y0) * 32 + (x - r.x0)) * 8
        return raw:sub(at + 1, at + 8)
      end
    end
  end
  local function parse(s)
    if not s or #s < 8 then return nil end
    local hh = s:byte(3) + s:byte(4) * 256
    if hh >= 0x8000 then hh = hh - 0x10000 end
    local flat = s:byte(1) == 0 and s:byte(2) == 0
    return { open = s:byte(7) % 2 == 0, h = flat and hh or nil, beh = s:byte(5) }
  end
  local surf, deck, deckBeh, platform = {}, {}, {}, {}
  local function add(x, y, s) local k = y * w + x; surf[k] = surf[k] or {}; table.insert(surf[k], s) end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r1, r2 = rec(1, x, y), rec(2, x, y)
      local a, b = parse(r1), parse(r2)
      if a and a.open then
        add(x, y, { kind = "floor", h = a.h })
        if a.h and a.h >= 0x100 then platform[y * w + x] = true end
      end
      if b and b.open and r1 ~= r2 then
        add(x, y, { kind = "deck", h = b.h })
        deckBeh[y * w + x] = b.beh
      end
    end
  end
  local seqs, corners = {}, {}
  for _, line in pairs(data.lines or {}) do
    local p, q = data.points[line.a], data.points[line.b]
    if p and q then
      local seq, last = {}, nil
      local steps = math.max(1, math.ceil(math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2) / 4))
      for i = 0, steps do
        local t = i / steps
        local cx = math.floor((p.x + (q.x - p.x) * t) / 16)
        local cz = math.floor((p.z + (q.z - p.z) * t) / 16)
        local y = (p.y or 0) + ((q.y or 0) - (p.y or 0)) * t
        local k = cz * w + cx
        if cx >= 0 and cz >= 0 and cx < w and cz < h and k ~= last then
          -- a diagonal sample step is walked through a corner: the one the
          -- grid already has open, else the one across
          if last and last % w ~= cx and math.floor(last / w) ~= cz then
            local lx, lz = last % w, math.floor(last / w)
            local c1, c2 = lz * w + cx, cz * w + lx
            local function isOpen(c) return def.blocks and def.blocks:sub(c * 2 + 1, c * 2 + 2) == "\0\0" end
            local corner = isOpen(c1) and c1 or (isOpen(c2) and c2) or c1
            seq[#seq + 1] = { k = corner, y = y }
            add(corner % w, math.floor(corner / w), { kind = "rail", h = y })
            corners[corner] = true
          end
          seq[#seq + 1] = { k = k, y = y }; last = k
          add(cx, cz, { kind = "rail", h = y })
        end
      end
      seqs[#seqs + 1] = seq
    end
  end
  local function levelOf(v) return (v >= G.HIGH) and 2 or 1 end
  local D4 = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
  local code = {}
  for k, list in pairs(surf) do
    local x, y = k % w, math.floor(k / w)
    local levels, n = {}, 0
    for _, s in ipairs(list) do
      local lv
      if s.h then
        lv = levelOf(s.h)
      else
        lv = 1
        for _, d in ipairs(D4) do
          local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and ny >= 0 and nx < w and ny < h then
            local nk = ny * w + nx
            if s.kind == "floor" and platform[nk] then lv = 3; break end
            for _, o in ipairs(surf[nk] or {}) do
              if o.kind == s.kind and o.h and levelOf(o.h) > lv then lv = levelOf(o.h) end
            end
          end
        end
      end
      if not levels[lv] then levels[lv] = true; n = n + 1 end
      -- a deck cell at the floor's height where layer 1 is shut is layer 1's
      -- (the nearest-height pick takes the first layer on a tie): only the
      -- raised deck is opened
      if s.kind == "deck" and lv == 2 then deck[x .. ":" .. y] = true else if s.kind == "deck" then deckBeh[k] = nil end end
    end
    if n > 1 then code[k] = 15 else code[k] = next(levels) end
  end
  -- where a rail climbs between the levels
  for _, seq in ipairs(seqs) do
    for i = 2, #seq do
      local a, b = seq[i - 1], seq[i]
      if levelOf(a.y) ~= levelOf(b.y) then
        local j = (levelOf(b.y) == 2) and b or a
        if code[j.k] == 1 or code[j.k] == 2 then code[j.k] = 0 end
      end
    end
  end
  local elev = {}
  for i = 0, w * h - 1 do elev[i + 1] = code[i] or 0 end
  def.elevationCells = elev
  -- the deck's cells, open
  if def.blocks then
    local blocks, behav = {}, {}
    for i = 1, #def.blocks, 2 do blocks[#blocks + 1] = def.blocks:sub(i, i + 1) end
    for i = 1, #(def.behaviorCells or "") do behav[i] = def.behaviorCells:sub(i, i) end
    for k, b in pairs(deckBeh) do
      if blocks[k + 1] ~= "\0\0" then
        blocks[k + 1] = "\0\0"
        if behav[k + 1] then behav[k + 1] = string.char(b) end
      end
    end
    for k in pairs(corners) do
      if blocks[k + 1] ~= "\0\0" then
        blocks[k + 1] = "\0\0"
        if behav[k + 1] then behav[k + 1] = "\0" end
      end
    end
    def.blocks = table.concat(blocks)
    if def.behaviorCells then def.behaviorCells = table.concat(behav) end
  end
  return { deck = deck }
end

-- import(def, data, rom, blocksBefore): the statues' lines and the cells they
-- open, read from the gym's overlay; the cells that were solid before the
-- rails opened them are the ones a closed neck shuts again (but not the
-- deck's: a neck that ends on the deck leaves the deck there)
function G.import(def, data, rom, blocksBefore)
  if def.header ~= G.HEADER or not (data and data.lines) then return nil end
  local levels = G.surfaces(def, data, rom)
  local onDeck = levels and levels.deck or {}
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
            if k <= 2 and solidBefore(cx, cz) and not onDeck[cx .. ":" .. cz] then neck[cx .. ":" .. cz] = true end
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
