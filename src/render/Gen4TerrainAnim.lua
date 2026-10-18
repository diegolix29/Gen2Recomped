-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE TERRAIN'S OWN TEXTURE ANIMATION, played: HeartGold / SoulSilver's sea,
-- ponds, rivers and shorelines (src/import/Gen4HgssTexAnim.lua for the
-- cartridge's side).
--
-- `forMap` answers nil for every map whose area names no animation -- all of
-- Platinum, whose water is props, and HGSS's rooms -- so nothing changes for
-- them. Otherwise `materials(land, clock)` is the material table
-- `Gen4Model:draw` takes, built the way the DS binds it: the animation's
-- entry i drives the chunk's material i.
--
-- AT THE FIELD'S RATE: the DS advances it once per field frame
-- (MapPropAnimation_AdvanceFrame from ov01_02204350), and the field runs at
-- half this engine's tick -- the ledge hop's 16 field frames are 32 here, the
-- bike ramp says the same -- so `materials` takes the engine clock and halves
-- it. 360 field frames is a twelve-second swell.

local Gen4TexAnim = require("src.render.Gen4TexAnim")

local A = {}
A.__index = A
A.TICKS_PER_FRAME = 2

function A.forMap(terrain, record)
  local id = record and record.texAnim
  local anim = id and terrain and terrain.texAnims and terrain.texAnims[id]
  if not (anim and anim.srt) then return nil end
  return setmetatable({
    anim = anim,
    order = terrain.texAnimLand or {},
    skip = terrain.texAnimSkip or {},
    frame = nil, byLand = {},
  }, A)
end

-- The states at `frame`, keyed by the animation's own entry names, cached for
-- the frame: every chunk on screen asks.
function A:states(frame)
  if self.frame ~= frame then
    self.frame = frame
    self.base = Gen4TexAnim.materials({ self.anim }, frame) or {}
    self.byLand = {}
  end
  return self.base
end

function A:materials(land, clock)
  if land == nil or self.skip[land] then return nil end
  local frame = math.floor((tonumber(clock) or 0) / A.TICKS_PER_FRAME)
  local order = self.order[land]
  if not order then return nil end
  local base = self:states(frame)
  local hit = self.byLand[land]
  if hit ~= nil then return hit or nil end
  local out, any = {}, false
  for i, target in ipairs(self.anim.srt) do
    local material = order[i]
    local state = material and base[target.name]
    if state then out[material] = state; any = true end
  end
  self.byLand[land] = any and out or false
  return any and out or nil
end

return A
