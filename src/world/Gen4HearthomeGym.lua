-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTHOME GYM'S DOORS AND THE CLUE ON THE FLOOR (pokeplatinum
-- src/overlay008/gym_features.c, HearthomeGym_DynamicMapFeaturesInit).
--
-- Each of the two trainer rooms has a row of doors in its north wall, three
-- in the first (circle, square, triangle) and five in the second (sun,
-- donut, moon, star, heart), and only one leads on. The port had every door
-- leading on: the puzzle was absent. Read from code:
--
--   * entering a trainer room runs its init script (`SetVar VAR_MAP_LOCAL_0x00,
--     0; InitPersistedMapFeaturesForHearthomeGym`), which empties the slot --
--     so the room is dealt afresh on every entry;
--   * HearthomeGym_DynamicMapFeaturesInit, with the slot not yet
--     `initialized`: correctDoorID = firstDoorID + MTRNG % numExitDoors; the
--     clue at a random (x, z) of the room's box (offset (1,3), 15 x 8 or
--     27 x 20) where sTrainerRoom{1,2}CluePositions says 0 and no object
--     stands, plus the offset;
--   * every OTHER door's warp is pointed at MAP_HEADER_HEARTHOME_CITY_GYM_
--     ENTRANCE_ROOM, warp 1 (MapHeaderData_SetWarpEventDest*) -- the wrong
--     door puts you back at the entrance;
--   * the clue is a field effect (ov5_021F4CEC): the model
--     hearthome_gym_hint_<shape> for the right door (fldeff.narc members
--     116..123 by door id), at the clue tile's centre and terrain height,
--     plus (0, -3, -4).
--
-- The darkness, the flashlights, the gym's own player picture and the beaten
-- trainers are the second half of this file (M.dark and below).

local M = {}

M.ENTRANCE = "C05GYM0101"
-- the cartridge's warp 1 of the entrance room, as this port numbers warps
-- (1-based): (4,2), the door to the first trainer room
M.ENTRANCE_WARP = 2
M.HINT_MEMBER = 116          -- fldeff.narc: hearthome_gym_hint_circle .. _heart
-- ov5_021F4CEC's offset is (0, -3, -4). The -3 put the flat hint under this
-- port's floor, where it was never seen (measured: invisible at -3, drawn at
-- +5); it is laid just on the floor instead -- a stand-in for however the
-- cartridge's field-effect pass gets it over the floor, which is not known
M.HINT_OFFSET = { 0, 0.5, -4 }

-- sTrainerRoomValidCluePositions: 0 = a clue can lie there
local ROOM1_CLUES = {
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
  0, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0,
  0, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0,
  0, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0,
  0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
}
local ROOM2_CLUES = {
  0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
  0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
  0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0,
  0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0,
  0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0,
  0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0,
  0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0,
  1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0,
  1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1,
  0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
}

-- sTrainerRoomLayouts + sTrainerRoom{1,2}Doors: { door id, x, z }
M.ROOMS = {
  C05GYM0102 = { first = 0, n = 3, ox = 1, oz = 3, sx = 15, sz = 8, clues = ROOM1_CLUES,
                 doors = { { 0, 4, 2 }, { 1, 8, 2 }, { 2, 12, 2 } } },
  C05GYM0103 = { first = 3, n = 5, ox = 1, oz = 3, sx = 27, sz = 20, clues = ROOM2_CLUES,
                 doors = { { 3, 4, 2 }, { 4, 9, 2 }, { 5, 14, 2 }, { 6, 19, 2 }, { 7, 24, 2 } } },
}

local function DMF() return require("src.world.Gen4DynamicMapFeatures") end

function M.room(def)
  return def and (M.ROOMS[def.id] or M.ROOMS[def.sourceId or ""]) or nil
end

-- the doors' own destinations, kept the first time so a room dealt again
-- starts from them (the cartridge re-reads the header on every load)
local function restoreWarps(def)
  if not def.gen4HearthomeWarps then
    def.gen4HearthomeWarps = {}
    for i, w in ipairs(def.warps or {}) do
      def.gen4HearthomeWarps[i] = { destMap = w.destMap, destWarp = w.destWarp }
    end
  end
  for i, w in ipairs(def.warps or {}) do
    local o = def.gen4HearthomeWarps[i]
    if o then w.destMap, w.destWarp = o.destMap, o.destWarp end
  end
end

local function occupied(ow, x, z)
  for _, n in ipairs((ow and ow.npcs) or {}) do
    if not n.hidden and n.cellX == x and n.cellY == z then return true end
  end
  return false
end

-- deal the room (when the slot is fresh) and set its doors and clue
function M.apply(ow, save, rng)
  local def = ow and ow.map and ow.map.def
  local room = M.room(def)
  local b = room and DMF().buffer(save, DMF().HEARTHOME_GYM)
  if not b then return nil end
  rng = rng or love.math.random
  restoreWarps(def)
  if not b.initialized then
    b.initialized = true
    b.correctDoorID = room.first + (rng(room.n) - 1)
    local x, z
    repeat
      repeat
        x, z = rng(room.sx) - 1, rng(room.sz) - 1
      until room.clues[z * room.sx + x + 1] == 0
      x, z = x + room.ox, z + room.oz
    until not occupied(ow, x, z)
    b.clueX, b.clueZ = x, z
  end
  for _, d in ipairs(room.doors) do
    if d[1] ~= b.correctDoorID then
      for _, w in ipairs(def.warps or {}) do
        if w.x == d[2] and w.y == d[3] then w.destMap, w.destWarp = M.ENTRANCE, M.ENTRANCE_WARP end
      end
    end
  end
  -- the clue, where ov5_021F4CEC draws it
  local keep = {}
  for _, p in ipairs(type(def.gen4RuntimeProps) == "table" and def.gen4RuntimeProps or {}) do
    if not p.hearthomeClue then keep[#keep + 1] = p end
  end
  local HR = require("src.world.Gen4HeightRule")
  local list = HR.surfaces(ow.map, b.clueX, b.clueZ) or {}
  local y = (#list > 0) and HR.nearest(list, 0) or 0
  keep[#keep + 1] = { model = M.HINT_MEMBER + b.correctDoorID, archive = "fldeff", hearthomeClue = true,
                      x = b.clueX * 16 + 8 + M.HINT_OFFSET[1], y = y + M.HINT_OFFSET[2],
                      z = b.clueZ * 16 + 8 + M.HINT_OFFSET[3] }
  def.gen4RuntimeProps = keep
  M.dark(ow, save)
  return b.correctDoorID
end

-- ---------------------------------------------------------------------------
-- THE DARK. HearthomeGym_DynamicMapFeaturesInit, besides the doors:
--
--   * HearthomeGym_InitFog: the hardware fog on, COLOR_ALPHA, in GX_RGB(1,1,1)
--     at alpha 1, and a FLAT density table -- every one of the 32 entries the
--     same, so the whole 3D picture is that dark however far away: 109 / 127,
--     119 in the second trainer room, 91 once the Relic Badge is won.
--   * sub_02061AD4(player, OBJ_EVENT_GFX_PLAYER_{M,F}_HEARTHOME_GYM): the
--     player's own picture (player_m / player_f.nsbtx) on the billboard model
--     BILLBOARD_MODEL_HEARTHOME_GYM_PLAYER, which is the one entry in
--     gFogIgnoredModels -- the player is the one thing the fog leaves bright.
--   * HearthomeGym_InitTrainers -> ov5_021F4840 (src/overlay005/
--     ov5_021F47B0.c): a flashlight cone (fldeff 115, hearthome_gym_
--     flashlight_cone, its fog flag cleared, nsbta 199 looping a field frame
--     at a time) for the player, two tiles long, and for every
--     TRAINER_TYPE_NORMAL object whose data[0] (its sight range) is not 0,
--     that long. Each frame (ov5_021F4908) the beam is walked from the
--     object's tile along its facing until a tile its owner could not step
--     on, or another object; unblocked it takes the table row for its full
--     length (ov5_021F4A24), blocked it is stretched between rows by how far
--     away the block is (ov5_021F4B6C). Drawn at the owner's position plus
--     the row's offset, 16 up, scaled and turned by the facing's angles.
--   * beaten trainers (HearthomeGym_SetTrainerPostBattleMovement): instead of
--     standing still they wander, two tiles either way of where they were
--     beaten; and HearthomeGym_CheckIfPlayerSeesTrainer -- the player's own
--     beam catching a beaten trainer, two tiles ahead, in the way the
--     trainer would see -- starts the approach script
--     (SCRIPT_ID(SINGLE_BATTLES, MAX_TRAINERS), Battles_ApproachingTrainer)
--     for that trainer, walking towards the player: they battle again.
-- ---------------------------------------------------------------------------

M.FOG_ROOM1, M.FOG_ROOM2, M.FOG_RELIC = 109, 119, 91
M.CONE_MEMBER, M.CONE_ANIM = 115, 199
M.PLAYER_BEAM = 2
M.RELIC_BADGE = 4                -- BADGE_ID_RELIC
M.WANDER_TYPE, M.WANDER_RANGE = 3, 2

-- Unk_ov5_0220077C: the angles (alpha, beta, gamma) by facing
M.CONE_ANGLES = { up = { 270, 180, 0 }, down = { 90, 180, 180 }, left = { 0, 270, 270 }, right = { 0, 90, 90 } }
-- Unk_ov5_022007C0: the scale, by facing and beam length 0..5
local function vs(t) local o = {} for i, v in ipairs(t) do o[i] = { v[1] / 4096, v[2] / 4096, v[3] / 4096 } end return o end
local SCALE_NS = vs({ { 0xC00, 0x100, 0x1000 }, { 0x1000, 0x500, 0x1000 }, { 0x1000, 0x800, 0x1000 },
                      { 0x1000, 0xC00, 0x1000 }, { 0x1000, 0x1000, 0x1000 }, { 0x1000, 0x1400, 0x1000 } })
local SCALE_WE = vs({ { 0x1000, 0x200, 0x1000 }, { 0x1000, 0x600, 0x1000 }, { 0x1000, 0xA00, 0x1000 },
                      { 0x1000, 0xE00, 0x1000 }, { 0x1000, 0x1200, 0x1000 }, { 0x1000, 0x1400, 0x1000 } })
M.CONE_SCALE = { up = SCALE_NS, down = SCALE_NS, left = SCALE_WE, right = SCALE_WE }
-- Unk_ov5_022008E0: the offset from the owner, by facing and beam length
M.CONE_OFFSET = {
  up = { { 0, -15, -15 }, { 0, -15, -31 }, { 0, -15, -47 }, { 0, -15, -63 }, { 0, -15, -79 }, { 0, -15, -95 } },
  down = { { 0, 0, 13 }, { 0, 0, 27 }, { 0, 0, 44 }, { 0, 0, 60 }, { 0, 0, 78 }, { 0, 0, 93 } },
  left = { { -13, 0, 6 }, { -29, 0, 9 }, { -45, 0, 10 }, { -61, 0, 10 }, { -78, 0, 10 }, { -85, 0, 10 } },
  right = { { 13, 0, 6 }, { 29, 0, 9 }, { 45, 0, 10 }, { 61, 0, 10 }, { 78, 0, 10 }, { 85, 0, 10 } },
}
local DV = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

local function game() return package.loaded["src.core.Game"] end

local function hasRelic(save)
  local G = game()
  local Badges = require("src.inventory.Badges")
  local list = Badges.list(G and G.data) or {}
  local entry = list[M.RELIC_BADGE + 1]
  return entry and Badges.has(save, entry) or false
end

-- the cone's owners: the player (2) and every normal trainer with a range
local function owners(ow)
  local out = { { e = ow.player, len = M.PLAYER_BEAM } }
  for _, n in ipairs(ow.npcs or {}) do
    local d = n.def
    local len = d and tonumber(d.sightRange) or 0
    if not n.hidden and d and tonumber(d.trainerType) == 1 and len > 0 then
      out[#out + 1] = { e = n, len = math.min(5, len) }
    end
  end
  return out
end

-- an entity's world position: its drawn cell, the tile centre
local function worldPos(e, ground)
  local x, z = (e.px or (e.cellX or 0) * 16) + 8, (e.py or (e.cellY or 0) * 16) + 8
  local y = 0
  if ground and ground.groundY then
    local ok, h = pcall(ground.groundY, ground, x, z)
    if ok and h then y = h end
  end
  return x, y, z
end

-- ov5_021F4AB4: how many tiles of the beam are free, and where the block is
local function beam(ow, owner, len, dir)
  local d = DV[dir]
  local x = owner.moving and owner.targetX or owner.cellX
  local z = owner.moving and owner.targetY or owner.cellY
  local map = ow.map
  local Collision = require("src.world.Collision")
  for i = 0, len - 1 do
    x, z = x + d[1], z + d[2]
    local wall = not map:inBounds(x, z) or not map:isWalkableCell(x, z)
    local gymHook = map.def and map.def.gen4CollisionHook
    if not wall and gymHook and gymHook(map, x, z, owner) == true then wall = true end
    local hit
    for _, other in ipairs(ow.entities or {}) do
      if other ~= owner and not other.hidden then
        local ox = other.moving and other.targetX or other.cellX
        local oz = other.moving and other.targetY or other.cellY
        if (ox == x and oz == z) or (other.cellX == x and other.cellY == z) then hit = other break end
      end
    end
    if hit then return i, { (hit.px or hit.cellX * 16) + 8, (hit.py or hit.cellY * 16) + 8 } end
    if wall then return i, { x * 16 + 8, z * 16 + 8 } end
  end
  return len, nil
end

-- ov5_021F4B6C: the row stretched to a block at `at`
local function stretched(dir, len, at, ox, oz)
  local v0
  if dir == "up" then v0 = oz - at[2]
  elseif dir == "down" then v0 = at[2] - oz
  elseif dir == "left" then v0 = ox - at[1]
  else v0 = at[1] - ox end
  local function trunc(v) return v < 0 and math.ceil(v) or math.floor(v) end
  local v1 = math.abs(trunc(v0 / 16))
  if v1 > len then v1 = len end
  v1 = v1 - 1
  if v1 < 0 then v1 = 0 end
  local v2 = v1
  local rem = math.fmod(v0, 16)
  if rem < 0 then v2 = v2 - 1 elseif rem > 0 then v2 = v2 + 1 end
  if v2 < 0 then v2 = 0 elseif v2 > len then v2 = len end
  local v3 = math.abs(trunc(rem / 1.6))
  local offA, offB = M.CONE_OFFSET[dir][v1 + 1], M.CONE_OFFSET[dir][v2 + 1]
  local scA, scB = M.CONE_SCALE[dir][v1 + 1], M.CONE_SCALE[dir][v2 + 1]
  local off, sc = {}, {}
  for k = 1, 3 do
    off[k] = offA[k] + (offB[k] - offA[k]) / 10 * v3
    sc[k] = scA[k] + (scB[k] - scA[k]) / 10 * v3
  end
  return off, sc
end

-- every cone, where ov5_021F4908 puts it this frame
function M.cones(ow, ground)
  if not (ow and ow.map and ow.player) then return {} end
  local frame = require("src.render.Gen4PropClock").fieldFrame(ground and ground.clock or 0)
  local GymFx = require("src.world.Gen4GymFx")
  local animFrame = GymFx.frameAt(M.CONE_ANIM, frame, true)
  local out = {}
  for _, o in ipairs(owners(ow)) do
    local e = o.e
    local dir = e.facing or "down"
    if DV[dir] then
      local x, y, z = worldPos(e, ground)
      local free, at = beam(ow, e, o.len, dir)
      local off, sc
      if free == o.len or not at then
        off, sc = M.CONE_OFFSET[dir][o.len + 1], M.CONE_SCALE[dir][o.len + 1]
      else
        off, sc = stretched(dir, o.len, at, x, z)
      end
      out[#out + 1] = { member = M.CONE_MEMBER, noFog = true, soft = true, hearthomeCone = true,
                        x = x + off[1], y = y + off[2] + 16, z = z + off[3],
                        rot = M.CONE_ANGLES[dir], scale = sc,
                        anims = { { member = M.CONE_ANIM, frame = animFrame } } }
    end
  end
  return out
end

-- the fog row (src/render/Gen4DepthFog.lua), the cones, the player's picture
function M.dark(ow, save)
  local def = ow and ow.map and ow.map.def
  local room = M.room(def)
  if not room then return nil end
  local density = M.FOG_ROOM1
  if hasRelic(save) then density = M.FOG_RELIC
  elseif room.first == 3 then density = M.FOG_ROOM2 end
  def.gen4DepthFog = {
    -- a flat table: every depth past the offset takes the last entry, and
    -- that entry is `density`
    flat = density, offset = -1e9, slope = 5, step = density / 31, rgb = { 1, 1, 1 },
    sprites = true,
    -- gFogIgnoredModels: the gym's player model
    exempt = function(e, o) return o and e == o.player end,
  }
  def.gen4GymFxProvider = function(o, ground) return M.cones(o, ground) end
  -- the trainers already beaten when the room was entered stand as their
  -- events made them; one beaten from now on wanders (fieldCheck)
  local G = game()
  local seen = {}
  for _, n in ipairs(ow.npcs or {}) do
    if G and G.overworld and G.overworld.trainerDefeated and G.overworld == ow and ow:trainerDefeated(n) then seen[n] = true end
  end
  def.gen4HearthomeBeaten = seen
  return density
end

-- HearthomeGym_SetTrainerPostBattleMovement: two tiles either way of here
function M.wander(npc)
  if not (npc and npc.g4Move) then return false end
  local T = require("src.world.Gen4MovementTypes")
  T.switch(npc, M.WANDER_TYPE)
  local st = npc.g4Move
  if not st then return false end
  st.originX, st.originY = npc.cellX, npc.cellY
  st.rangeX, st.rangeY = M.WANDER_RANGE, M.WANDER_RANGE
  npc.gen4HearthomeWander = true
  return true
end

-- the player's beam on a beaten trainer (HearthomeGym_CheckIfPlayerSeesTrainer):
-- the trainer, its distance and the way it walks, or nil
function M.seenTrainer(ow)
  local def = ow and ow.map and ow.map.def
  if not (M.room(def) and def.gen4DepthFog) then return nil end
  local p = ow.player
  local look = OPPOSITE[p.facing or "down"]
  local Collision = require("src.world.Collision")
  for _, n in ipairs(ow.npcs or {}) do
    local d = n.def
    if not n.hidden and not n.moving and type(d and d.trainer) == "table" and ow:trainerDefeated(n) then
      -- GetDistanceToPlayerFromDir(trainer, opposite of the player's facing, 2)
      local dist
      local v = DV[look]
      if v[1] ~= 0 and n.cellY == p.cellY then dist = (p.cellX - n.cellX) * v[1]
      elseif v[2] ~= 0 and n.cellX == p.cellX then dist = (p.cellY - n.cellY) * v[2] end
      if dist and dist >= 1 and dist <= M.PLAYER_BEAM
         and Collision.sightPathClear(ow.map, ow.cast or ow.entities, n, look, dist) then
        return n, dist, look
      end
    end
  end
  return nil
end

-- once a field frame the player stands free (OverworldState:checkTrainerSight,
-- after the cartridge's own scan found nobody): beaten trainers set wandering,
-- then the beam. Answers true when an approach was started.
function M.fieldCheck(ow)
  local def = ow and ow.map and ow.map.def
  if not (M.room(def) and def.gen4DepthFog) then return false end
  local seen = def.gen4HearthomeBeaten or {}
  for _, n in ipairs(ow.npcs or {}) do
    if not n.gen4HearthomeWander and not seen[n] and not n.frozen and not n.moving
       and type(n.def and n.def.trainer) == "table" and ow:trainerDefeated(n) then
      M.wander(n)
    end
  end
  local n, dist, look = M.seenTrainer(ow)
  if not n then return false end
  local hush = ow.spotHush
  if hush and hush[n] and hush.cellX == ow.player.cellX and hush.cellY == ow.player.cellY then return false end
  local TT = require("src.world.Gen4TwoTrainers")
  local G = game()
  local eye = TT.eyeLabel(G and G.data)
  local rows = eye and require("src.script.Gen4ScriptVM").compile(G.data, eye)
  if not rows then return false end
  n.facing = look
  -- the approach script, singles (APPROACH_TYPE_SINGLES); the second slot is
  -- the same trainer, never walked
  ow:startTrainerApproach(n, dist, nil, { npc = n, dist = dist, rows = rows, kind = 0 })
  -- once it is over, not again from this tile (the cartridge's check runs
  -- every field frame; this port releases the player where they stood, and
  -- the same beam would start the same battle on the next frame)
  ow.spotHush = { cellX = ow.player.cellX, cellY = ow.player.cellY, [n] = true }
  return true
end

-- which door leads on, by its (x, z) -- for a check, and for a player who has
-- read the clue
function M.correctDoor(def, save)
  local room = M.room(def)
  local b = room and DMF().buffer(save, DMF().HEARTHOME_GYM)
  if not (b and b.initialized) then return nil end
  for _, d in ipairs(room.doors) do
    if d[1] == b.correctDoorID then return d[2], d[3], d[1] end
  end
end

return M
