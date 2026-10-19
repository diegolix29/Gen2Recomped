-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S WATERFALL RIDE: up a fall with the HM, and down
-- one on its own.
--
-- pokeheartgold overlay 1 (asm/overlay_01_021F1AFC.s):
--
--   DESCENT. ov01_021F24F4, asked by the player's movement check
--   (ov01_021F1DF4) when a step is about to be taken: the step is SOUTH, it is
--   a real step (not a turn), the player is SURFING (state 2) and the tile in
--   front is TILE_BEHAVIOR_WATERFALL (0x13) -> ov01_021F28EC starts the ride
--   task with no cut-in. Nothing asks the player first: surfing south off the
--   top of a fall carries them down it.
--
--   ASCENT. ScrCmd_Waterfall (std_field_waterfall / std_menu_waterfall) ->
--   CallFieldTask_Waterfall(facing, partySlot): the same task, with the HM
--   cut-in first (states 0 and 1, ov01_021F3054 / ov01_021F3068) and then
--   SEQ_SE_DP_FW463.
--
-- The task (ov01_021F2944) runs one of two five-state tables, picked by the
-- direction: ov01_022069A8 north, ov01_022069BC otherwise. Both go TWO tiles
-- (GetDelta*ByFacingDirection << 1) to a destination whose height is the
-- ground's there (sub_020611C8), moving the map object's position vector by
-- 1/64 of the whole distance a field frame on each axis:
--
--   north  32 frames rising only (ov01_021F2AB8), then 64 frames rising and
--          going forward (ov01_021F2AF8) -- the rise is clamped, so it is done
--          by frame 64 and the last 32 frames are level
--   south  32 frames going forward only (ov01_021F2C88), then 64 frames
--          dropping and going forward (ov01_021F2CD4) -- the forward part is
--          clamped, so it ends at frame 64 and the drop takes frames 32..95
--
-- then sets the object's tile coordinates to the destination. 96 field frames
-- either way, two engine ticks each.

local M = {}

M.WATERFALL = 0x13
M.TILES = 2
M.PHASE1, M.TOTAL = 32, 96          -- field frames
M.TICKS_PER_FRAME = 2
M.SE = { "SEQ_SE_DP_FW463", "SEQ_SE_PL_FW463" }

local function Game() return package.loaded["src.core.Game"] end

local function isHgss()
  local G = Game()
  local v = G and G.data and G.data.gen4_version
  return v and v.family == "hgss" or false
end

local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end

-- (forward, rise) progress, each 0..1, at field frame `f` of a ride
function M.progress(dir, f)
  f = math.max(0, math.min(M.TOTAL, f))
  if dir == "up" then
    return clamp01((f - M.PHASE1) / 64), clamp01(f / 64)
  end
  return clamp01(f / 64), clamp01((f - M.PHASE1) / 64)
end

local function delta(dir)
  if dir == "up" then return 0, -1 elseif dir == "down" then return 0, 1
  elseif dir == "left" then return -1, 0 end
  return 1, 0
end

local function groundOf(ow)
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
end

local function playSe()
  local G = Game()
  for _, key in ipairs(M.SE) do
    local ok, src = pcall(function() return require("src.core.Sound").playSe(G.data, key) end)
    if ok and src then return src end
  end
end

-- the descent's question (ov01_021F24F4): would this step carry a surfer
-- down a fall?
function M.descentAhead(ow, dir)
  if dir ~= "down" or not isHgss() then return false end
  local p, map = ow and ow.player, ow and ow.map
  if not (p and map and map.cellBehaviour and p.surfing) or p.moving then return false end
  if ow.gen4Waterfall then return false end
  if p.facing ~= "down" then return false end   -- a turn first, not a step
  local dx, dy = delta(dir)
  return map:cellBehaviour(p.cellX + dx, p.cellY + dy) == M.WATERFALL
end

-- start a ride `dir` from where the player is; `mon` (optional) is the HM
-- user whose cut-in plays first
function M.start(ow, dir, mon)
  local p = ow and ow.player
  if not p or ow.gen4Waterfall then return false end
  local dx, dy = delta(dir)
  local ground = groundOf(ow)
  local fromX, fromY = p.cellX * 16, p.cellY * 16
  local toCellX, toCellY = p.cellX + dx * M.TILES, p.cellY + dy * M.TILES
  local y0 = ground and ground:groundY(fromX + 8, fromY + 8) or 0
  local y1 = ground and ground:groundY(toCellX * 16 + 8, toCellY * 16 + 8) or y0
  ow.gen4Waterfall = {
    dir = dir, tick = 0, fromX = fromX, fromY = fromY, toCellX = toCellX, toCellY = toCellY,
    y0 = y0, y1 = y1, mon = mon, phase = mon and "cutin" or "ride", offset = {},
  }
  p.facing = dir
  if not mon then playSe() end
  return true
end

-- the ride's current world height (Gen4SurfMount.where reads it)
function M.currentY(ow)
  local r = ow and ow.gen4Waterfall
  if not (r and r.phase == "ride") then return nil end
  local _, rise = M.progress(r.dir, r.tick / M.TICKS_PER_FRAME)
  return r.y0 + (r.y1 - r.y0) * rise
end

local function finish(ow)
  local r = ow.gen4Waterfall
  local p = ow.player
  ow.gen4Waterfall = nil
  if p.spriteOffset == r.offset then p.spriteOffset = nil end
  p.cellX, p.cellY = r.toCellX, r.toCellY
  p.px, p.py = p.cellX * 16, p.cellY * 16
  p.moving = false
  if ow.noteCellChange then pcall(ow.noteCellChange, ow) end
end

-- every engine tick (OverworldState:update); true while the ride owns the
-- player
function M.tick(ow)
  local r = ow and ow.gen4Waterfall
  if not r then return false end
  local p = ow.player
  if not p then ow.gen4Waterfall = nil return false end
  local G = Game()
  if r.phase == "cutin" then
    if not r.cutinPushed then
      r.cutinPushed = true
      local okShow, shown = pcall(function()
        return require("src.world.Gen3FieldMove").show(G, r.mon, function() r.cutinDone = true end)
      end)
      if not (okShow and shown) then r.cutinDone = true end
    end
    if r.cutinDone then
      r.phase = "ride"
      playSe()
    end
    return true
  end
  r.tick = r.tick + 1
  local f = r.tick / M.TICKS_PER_FRAME
  local fwd, rise = M.progress(r.dir, f)
  local dx, dy = delta(r.dir)
  p.px = r.fromX + dx * 16 * M.TILES * fwd
  p.py = r.fromY + dy * 16 * M.TILES * fwd
  p.facing = r.dir
  -- the sprite at the ride's height, over the ground under it now, on top of
  -- the surf mount's own lift (Gen4SurfMount keeps it while we own the offset)
  local ground = groundOf(ow)
  if ground then
    local y = r.y0 + (r.y1 - r.y0) * rise
    local under = ground:groundY(p.px + 8, p.py + 8) or 0
    local SM = require("src.world.Gen4SurfMount")
    local bob = (ow.surfMount and ow.surfMount.y) or SM.MIN_Y
    r.offset.lift = (y - under) + (isHgss() and SM.HGSS_SPRITE_Y or SM.SPRITE_Y) + bob
    r.offset.oz = SM.SPRITE_Z
    p.spriteOffset = r.offset
  end
  if f >= M.TOTAL then finish(ow) end
  return true
end

return M
