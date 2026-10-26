-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S GYM FIELD EFFECTS, DRAWN AS THE CARTRIDGE'S FIELD EFFECT
-- MANAGER DRAWS THEM: a fldeff.narc model at a world position, with a
-- rotation and a scale (Simple3D_DrawRenderObjRotationAngles), its own joint
-- and texture animations on their own frames, and -- for a model whose fog
-- flag the cartridge clears (NNS_G3dMdlSetMdlFogEnableFlagAll(.., 0)) -- out
-- of the map's fog.
--
--   * Hearthome Gym's flashlight cones (ov5_021F47B0.c), and its fog
--     (HearthomeGym_InitFog) with the gym's own player out of it
--     (gFogIgnoredModels = BILLBOARD_MODEL_HEARTHOME_GYM_PLAYER);
--   * Veilstone Gym's punching bags and tire stacks with their swing and
--     topple animations (veilstone_gym_object_renderer.c);
--   * Eterna Gym's fountains, running and stopping (ov5_021F4018.c);
--   * Canalave Gym's depth fog on the characters.
--
-- A gym module puts what is to be drawn on its map def:
--
--   def.gen4GymFx         = { effect, ... }      -- a fixed list
--   def.gen4GymFxProvider = function(ow, ground) -> { effect, ... }
--                                                 -- asked every draw
--   effect = { member,             -- fldeff.narc member (the model)
--              x, y, z,            -- world units, the map's own corner
--              rot = { a, b, g },  -- degrees, MTX_Rot33Angles (X, Y, Z)
--              scale = { sx, sy, sz },
--              anims = { { member = m, frame = f }, ... },
--              noFog = true,       -- drawn out of the depth fog
--              soft = true }       -- a translucent texture, blended
--
-- and the overworld's two 3D passes call drawLive / drawFree
-- (src/render/Gen4Ground.lua). Nothing is drawn on a map with neither.
--
-- `def.gen4DepthFog` is the map's own fog (src/render/Gen4DepthFog.lua) and
-- `spriteFog` turns it into a tint for the characters, which on the DS are
-- polygons the same fog covers.

local M = {}

M.TICKS_PER_FRAME = 2

local function Game() return package.loaded["src.core.Game"] end

local function fldeffSet()
  local G = Game()
  local data = G and G.data
  return data and data.gen4_models and data.gen4_models.sets and data.gen4_models.sets.fldeff or nil
end

-- the fldeff animation record by member
local animIndex, animIndexOf = nil, nil
function M.anim(member)
  local set = fldeffSet()
  if not set then return nil end
  if animIndexOf ~= set then
    animIndex, animIndexOf = {}, set
    for _, r in ipairs(set.animations or {}) do
      if r.member and animIndex[r.member] == nil then animIndex[r.member] = r end
    end
  end
  return animIndex[member]
end

function M.frames(member)
  local r = M.anim(member)
  return r and math.max(1, math.floor(tonumber(r.frames) or 1)) or 1
end

-- a model's flipbook pictures: its own, and what Gen4GymFxArt decoded for it
-- (`gen4_gym_fx`; absent on a cache imported before it, which then plays the
-- running fountain as its still model)
local imagesOf = {}
function M.images(member)
  local set = fldeffSet()
  local cached = imagesOf[member]
  if cached and cached.set == set then return cached.images end
  local at = set and set.byMember and set.byMember[member]
  local packed = at and set.models and set.models[at]
  local out = {}
  for k, v in pairs((packed and packed.patternImages) or {}) do out[k] = v end
  local G = Game()
  local extra = G and G.data and G.data.gen4_gym_fx
  local mine = extra and extra.models and extra.models[member]
  for k, v in pairs((mine and mine.patternImages) or {}) do
    if out[k] == nil or out[k] == false then out[k] = v end
  end
  imagesOf[member] = { set = set, images = out }
  return out
end

-- the frame of an animation at a field frame: looped or held on its last
function M.frameAt(member, f, loop)
  local n = M.frames(member)
  f = math.floor(f or 0)
  if loop then return f % n end
  if f < 0 then return 0 end
  if f > n - 1 then return n - 1 end
  return f
end

-- the pose and the materials an effect wears
local function poseAndMaterials(model, e)
  local pose, records, frame = nil, nil, nil
  local byJoint = nil
  local Anim = nil
  local mats = nil
  for _, a in ipairs(e.anims or {}) do
    local r = M.anim(a.member)
    if r then
      local f = math.max(0, math.min(M.frames(a.member) - 1, math.floor(a.frame or 0)))
      if r.kind == "BCA0" and r.tracks then
        Anim = Anim or require("src.import.Gen4Anim")
        byJoint = byJoint or {}
        for _, track in ipairs(r.tracks) do
          if byJoint[track.index] == nil then
            local at = f
            if track.frames and at >= track.frames then at = track.frames - 1 end
            byJoint[track.index] = Anim.unpackFrame(track.matrices, at)
          end
        end
      else
        local one = require("src.render.Gen4TexAnim").materials({ r }, f, M.images(e.member))
        if one then
          mats = mats or {}
          for name, state in pairs(one) do
            local into = mats[name] or {}
            for k, v in pairs(state) do into[k] = v end
            mats[name] = into
          end
        end
      end
    end
  end
  if byJoint then pose = model:posed(function(node) return byJoint[node] end) end
  return pose, mats
end

-- T * Rz(g) * Ry(b) * Rx(a) * S, row-major (MTX_Rot33Angles is X, then Y,
-- then Z; NNS_G3dGlbSetBaseScale applies the scale first)
function M.matrix(e, ox, oz)
  local r = e.rot or { 0, 0, 0 }
  local s = e.scale or { 1, 1, 1 }
  local function cs(d) local v = math.rad(d or 0) return math.cos(v), math.sin(v) end
  local ca, sa = cs(r[1])
  local cb, sb = cs(r[2])
  local cg, sg = cs(r[3])
  -- Rx, Ry, Rz (column-vector convention)
  local Rx = { 1, 0, 0, 0, ca, -sa, 0, sa, ca }
  local Ry = { cb, 0, sb, 0, 1, 0, -sb, 0, cb }
  local Rz = { cg, -sg, 0, sg, cg, 0, 0, 0, 1 }
  local function mul(A, B)
    local C = {}
    for i = 0, 2 do
      for j = 0, 2 do
        C[i * 3 + j + 1] = A[i * 3 + 1] * B[j + 1] + A[i * 3 + 2] * B[3 + j + 1] + A[i * 3 + 3] * B[6 + j + 1]
      end
    end
    return C
  end
  local R = mul(Rz, mul(Ry, Rx))
  return {
    R[1] * s[1], R[2] * s[2], R[3] * s[3], (e.x or 0) + (ox or 0),
    R[4] * s[1], R[5] * s[2], R[6] * s[3], e.y or 0,
    R[7] * s[1], R[8] * s[2], R[9] * s[3], (e.z or 0) + (oz or 0),
    0, 0, 0, 1,
  }
end

function M.effects(ow, ground)
  local def = ground and ground.def
  if not def then return nil end
  local list = def.gen4GymFx
  local fn = def.gen4GymFxProvider
  if not list and not fn then return nil end
  local out = {}
  for _, e in ipairs(type(list) == "table" and list or {}) do out[#out + 1] = e end
  if fn then
    local ok, more = pcall(fn, ow, ground)
    if ok then for _, e in ipairs(more or {}) do out[#out + 1] = e end end
  end
  return out
end

local function drawOne(ground, e, place)
  -- (an effect may bring its own model, pose and materials: Black / White's
  -- gym gimmicks, src/world/Gen5GymFx.lua)
  local model = e.model or ground:building(e.member, "fldeff")
  if not model then return end
  local Gen4Model = require("src.render.Gen4Model")
  local pose, mats
  if e.model then pose, mats = e.pose, e.mats else pose, mats = poseAndMaterials(model, e) end
  local fog = Gen4Model.depthFog
  if e.noFog then Gen4Model.depthFog = nil end
  -- a translucent picture (the cone's A3I5 light) keeps its alpha
  Gen4Model.softAlpha = e.soft or nil
  local ok, err = pcall(place, model, pose, mats)
  Gen4Model.depthFog = fog
  Gen4Model.softAlpha = nil
  if not ok then error(err) end
end

-- the field camera's live pass (Gen4Ground:livePass, beside the surf mount)
function M.drawLive(ground, left, top, vw, vh)
  local G = Game()
  local list = M.effects(G and G.overworld, ground)
  if not list or #list == 0 then return end
  local Gen4Ground = require("src.render.Gen4Ground")
  local Gen4Model = require("src.render.Gen4Model")
  local half = ground.half or 0
  for _, e in ipairs(list) do
    drawOne(ground, e, function(model, pose, mats)
      local base = ground:screenMatrix((ground.offsetX or 0) - left - half,
                                       (ground.offsetY or 0) - top - half, vw, vh)
      local m = Gen4Model.multiply(base, M.matrix(e))
      local spread = Gen4Ground.liftedSpread and Gen4Ground.liftedSpread(ground.spread, e.y or 0) or ground.spread
      model:draw(m, pose, mats, nil, spread)
    end)
  end
end

-- the 3D view's pass (Gen4Ground:drawFree), with the world's depth
function M.drawFree(ground, vp)
  local G = Game()
  local list = M.effects(G and G.overworld, ground)
  if not list or #list == 0 then return end
  local Gen4Model = require("src.render.Gen4Model")
  for _, e in ipairs(list) do
    drawOne(ground, e, function(model, pose, mats)
      model:draw(Gen4Model.multiply(vp, M.matrix(e, ground.offsetX or 0, ground.offsetY or 0)), pose, mats)
    end)
  end
end

-- THE MAP'S FOG ON THE CHARACTERS. On the DS a character is a billboard
-- polygon and the hardware fogs it by its depth like any other, unless its
-- model is one the field leaves out (gFogIgnoredModels: the Hearthome Gym
-- player). Answers nil, or a function(entity) -> the brightness left, 0..1
-- (the gyms' fogs are black), or nil for an entity the fog does not touch.
function M.spriteFog(ow)
  local def = ow and ow.map and ow.map.def
  local row = def and def.gen4DepthFog
  if not (row and row.sprites) then return nil end
  local F = require("src.render.Gen4DepthFog")
  local ground = ow.map.renderer and ow.map.renderer.gen4Ground
  return function(e)
    if row.exempt and row.exempt(e, ow) then return nil end
    local d = F.density(row, ground, row.depthOf and row.depthOf(e, ow, ground) or nil)
    if not d or d <= 0 then return nil end
    return 1 - d
  end
end

return M
