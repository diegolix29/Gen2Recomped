-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CHARGESTONE CAVE'S FLOATING STONES (Black / White, zones 195 / 196 / 197).
-- No decomp: read off the Black ROM. The three floors are field gimmicks 25,
-- 26 and 27 (/a/1/0/1's zone -> gimmick list), and ov21's table at 0x21D9D98
-- gives all three overlay 51 ("field_gimmick_d06.c").
--
-- READ FROM CODE (ov51, loaded at 0x21F36C0):
--   * the stones, per zone, at 0x21F3DB4 (zone, count, list of u32 x, level,
--     z): 12 on 1F, 5 on B1F, 3 on B2F. The gimmick's init (0x21F3730) puts
--     them out as objects of code 0xFD (0x21F3D38 -> 0x216CE6C) when its
--     save-block byte is 0 and sets it to 1; with it set (a continue: the
--     block is the save's) it takes back the 0xFD objects already there. A
--     warp clears the block (ov20 0x2185B9C), so every walk in puts every
--     stone back where the table has it.
--   * a push (0x21F38A4, called by ov21 0x218AF90 for gimmicks 25..27 with the
--     player's direction when they walk into what is ahead): the object ahead
--     with code 0xFD is pushed (0x21F3958) --
--       - not at all when it is STUCK (0x21F3C98): one step from it in any of
--         the four directions is terrain-blocked (the object collision
--         0x2163994, flag 2) on a cell of behaviour 0x32 (0x21AB3F8) -- the
--         cave's big crystals;
--       - otherwise it SLIDES the way it was pushed, up to 32 cells
--         (0x21F3C84 -> 0x21F3BC4), until the next step would be blocked for
--         it: terrain (2), another object or the player (4), a height step
--         of 20 units or more (8; 0x21638CC);
--       - a stone that cannot move a cell is only nudged (task 0x21F3AB4,
--         SE 0x55A) and the player stays put; one that can slides (task
--         0x21F39F8: the player's push, SE 0x6CE, the stone's run, SE 0x6A3
--         as it stops). The player never moves.
--   * the other table (0x21F3DFC) is effects at the cave's wall crystals that
--     a press against them sets off (0x21F3D04 -> 0x21C928C): scenery only.
--
-- Not drawn as the cartridge's floating model (it is a gimmick model, not an
-- overworld sprite): each stone is an object with the boulder sprite.

local M = {}

M.ZONES = {
  [195] = { { 15, 0, 39 }, { 24, 0, 46 }, { 9, 0, 26 }, { 20, 1, 27 }, { 21, 1, 26 }, { 24, 1, 16 },
            { 24, 1, 17 }, { 34, 0, 26 }, { 40, 1, 12 }, { 60, 0, 42 }, { 61, 0, 52 }, { 61, 0, 53 } },
  [196] = { { 43, 1, 49 }, { 47, 1, 45 }, { 45, 0, 14 }, { 43, 0, 12 }, { 36, 0, 18 } },
  [197] = { { 9, 0, 23 }, { 21, 0, 9 }, { 24, 0, 3 } },
}
M.CRYSTAL = 0x32
M.MAX_SLIDE = 32
M.SPRITE, M.SPRITE_NAME = "SPRITE_G4_181", "bw_181"
M.LOCAL_BASE = 0xF00
M.RATE = 0.5

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function stonesOf(def)
  local list = {}
  for _, o in ipairs(def and def.objects or {}) do
    if o.gen5Stone then list[o.gen5Stone] = o end
  end
  return list
end

-- the stones' records in the zone's object list, where the cartridge's table
-- (a walk in) or the save (a continue in the same zone) puts them
function M.attach(def, save, continuing)
  local zone = def and def.gen5 and M.ZONES[tonumber(def.header) or -1]
  if not zone then return end
  def.objects = def.objects or {}
  local kept = save and save.bwStones
  if not (continuing and kept and kept.zone == def.header) then kept = nil end
  local have = stonesOf(def)
  local maxIndex = 0
  for _, o in ipairs(def.objects) do maxIndex = math.max(maxIndex, tonumber(o.index) or 0) end
  local fresh = {}
  for i, s in ipairs(zone) do
    local o = have[i]
    if not o then
      maxIndex = maxIndex + 1
      o = { index = maxIndex, localId = M.LOCAL_BASE + i, graphicsId = 0xFD, sprite = M.SPRITE,
            spriteName = M.SPRITE_NAME, direction = 1, movementType = 0, movementRangeX = 0,
            movementRangeY = 0, script = 0, flag = 0, elevation = 0, gen5 = true, gen5Stone = i }
      def.objects[#def.objects + 1] = o
    end
    local at = kept and kept.pos and kept.pos[i]
    o.x, o.y = at and at[1] or s[1], at and at[2] or s[3]
    o.gen5Level = s[2]
    fresh[i] = { o.x, o.y }
  end
  if save then save.bwStones = { zone = def.header, pos = fresh } end
end

local function stoneAt(ow, x, y)
  for _, n in ipairs(ow.npcs or {}) do
    if n.def and n.def.gen5Stone and not n.hidden and n.cellX == x and n.cellY == y then return n end
  end
end
M.stoneAt = stoneAt

-- 0x21F3C98: a crystal (blocked 0x32) on any side
function M.stuck(map, x, y)
  for _, d in pairs(DIRS) do
    local cx, cy = x + d[1], y + d[2]
    if map:inBounds(cx, cy) and map:cellBehaviour(cx, cy) == M.CRYSTAL and not map:isWalkableCell(cx, cy) then
      return true
    end
  end
  return false
end

-- 0x21F3C84: how many cells the stone slides `dir`
function M.slideLength(ow, stone, dir)
  local Collision = require("src.world.Collision")
  local probe = { cellX = stone.cellX, cellY = stone.cellY, facing = dir, elevation = stone.elevation,
                  def = stone.def, gen5Level = stone.gen5Level }
  local ents = {}
  for _, e in ipairs(ow.cast or ow.entities or {}) do if e ~= stone then ents[#ents + 1] = e end end
  if ow.player then
    local seen = false
    for _, e in ipairs(ents) do if e == ow.player then seen = true end end
    if not seen then ents[#ents + 1] = ow.player end
  end
  local n = 0
  while n < M.MAX_SLIDE and Collision.canMove(ow.map, ents, probe, dir) do
    local d = DIRS[dir]
    probe.cellX, probe.cellY = probe.cellX + d[1], probe.cellY + d[2]
    n = n + 1
  end
  return n
end

local function sound(ow, id)
  pcall(function()
    local Game = package.loaded["src.core.Game"]
    require("src.script.Gen4Commands").play_sound({ game = Game, save = Game and Game.save, overworld = ow }, id)
  end)
end

-- a step into the cell ahead: true when a stone there took it
function M.press(ow, dir)
  local def = ow.map and ow.map.def
  if not (def and def.gen5 and M.ZONES[tonumber(def.header) or -1]) then return false end
  local p = ow.player
  if not p or p.moving or p.facing ~= dir or p.surfing then return false end
  local d = DIRS[dir]
  if not d then return false end
  local stone = stoneAt(ow, p.cellX + d[1], p.cellY + d[2])
  if not stone then return false end
  if M.stuck(ow.map, stone.cellX, stone.cellY) then return false end
  local n = M.slideLength(ow, stone, dir)
  if n == 0 then
    sound(ow, 0x55A)
    return false
  end
  sound(ow, 0x6CE)
  ow:scriptMove(stone, dir, n, function()
    sound(ow, 0x6A3)
    local Game = package.loaded["src.core.Game"]
    local save = Game and Game.save
    local i = stone.def.gen5Stone
    stone.def.x, stone.def.y = stone.cellX, stone.cellY
    if save then
      save.bwStones = save.bwStones or { zone = def.header, pos = {} }
      if save.bwStones.zone ~= def.header then save.bwStones = { zone = def.header, pos = {} } end
      save.bwStones.pos[i] = { stone.cellX, stone.cellY }
    end
  end, true, M.RATE)
  return true
end

return M
