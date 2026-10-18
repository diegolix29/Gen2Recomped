-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE WARP INTO THE DISTORTION WORLD (`DoDWWarp`, Spear Pillar's last
-- script before the Distortion World), which this port answered with nothing.
--
-- pokeplatinum src/dw_warp/dw_warp.c, transcribed.  It is its own application
-- on the cartridge and it draws ONE MODEL: titledemo.narc member 16 --
-- `op_ana`, the swirling portal the opening flies through -- animated by its
-- texture scroll (member 17) and joint animation (member 18), both looped.
-- The camera sits 160 units straight above it (angle 0x10000 - 0x3FEF) with a
-- 22-degree field of view that NARROWS every frame (Camera_AdjustFOV by
-- -perspective, perspective falling 0x80 a frame from 60 << 8 to 16 << 8): a
-- dive into the middle of the vortex.  SEQ_SE_PL_SYUWA2 at frame 15, 85
-- frames in all, then a 20-frame fade to black, and the script resumes.

local Gen4Anim = require("src.import.Gen4Anim")
local Gen4Model = require("src.render.Gen4Model")

local Warp = {}
Warp.__index = Warp
Warp.isOpaque = true

local W, H = 256, 192
Warp.DURATION, Warp.FADE, Warp.SOUND_AT = 85, 20, 15

local FLIP_Y = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }

function Warp:uiSize() return W, H end
function Warp:wantsFillScale() return true end

function Warp.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, frame = 0 }, Warp)
  self.fovUnits = 22 * 0xFFFF / 360         -- Camera_InitWithTarget's fov
  self.perspective = 60 * 256               -- warp->cameraPerspective
  local set = ((game.data or {}).gen4_models or {}).sets
  set = set and set.title
  for _, record in ipairs((set and set.models) or {}) do
    if record.name == "op_ana" then self.model = Gen4Model.new(record) end
  end
  self.materials, self.tracks = {}, nil
  for _, anim in ipairs((set and set.animations) or {}) do
    if anim.name == "op_ana" then
      if anim.tracks then
        self.tracks, self.frames = {}, anim.frames or 240
        for _, t in ipairs(anim.tracks) do self.tracks[t.index] = t end
      else
        self.materials[#self.materials + 1] = anim
      end
    end
  end
  return self
end

function Warp:update()
  self.frame = self.frame + 1
  if self.frame == Warp.SOUND_AT then
    pcall(function() require("src.core.Sound").play(self.game.data, "Warp") end)
  end
  -- DWWarp_CameraMove: the fov narrows by the falling perspective each frame
  self.fovUnits = math.max(64, self.fovUnits - self.perspective / 256)
  self.perspective = math.max(16 * 256, self.perspective - 0x80)
  if self.frame >= Warp.DURATION + Warp.FADE and not self.finished then
    self.finished = true
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function Warp:draw()
  local g = love.graphics
  g.clear(0, 0, 0, 1)
  if self.model then
    if not self.colour then self.colour, self.depth = Gen4Model.newTarget(W, H) end
    if self.colour then
      -- push("all") / pop() saves and restores the whole render target (and
      -- its depth): handing getCanvas()'s answer back to setCanvas raised
      -- "Canvas expected" when a mod's renderer had bound its own target.
      g.push("all")
      g.setCanvas({ self.colour, depthstencil = self.depth })
      g.clear(0, 0, 0, 1, true, true)
      local at = self.frame % (self.frames or 240)
      local fov = math.rad(self.fovUnits * 360 / 65536) * 2
      -- 160 units above, looking straight down (a hair off vertical, as the
      -- cartridge's 0x3FEF is a hair short of a quarter turn)
      local pitch = (0x3FEF / 65536) * 2 * math.pi
      local eye = { 0, math.sin(pitch) * 160, math.cos(pitch) * 160 }
      local vp = Gen4Model.multiply(FLIP_Y, Gen4Model.multiply(
        Gen4Model.perspective(fov, W / H, 1, 300), Gen4Model.lookAt(eye, { 0, 0, 0 })))
      local tracks = self.tracks
      local pose = self.model:posed(function(node)
        local track = tracks and tracks[node]
        return track and Gen4Anim.unpackFrame(track.matrices, at) or nil
      end)
      self.model:draw(vp, pose, require("src.render.Gen4TexAnim").materials(self.materials, at))
      g.pop()
      g.setColor(1, 1, 1, 1)
      g.draw(self.colour, 0, 0)
    end
  end
  -- the fade to black after the 85 frames
  local fade = (self.frame - Warp.DURATION) / Warp.FADE
  if fade > 0 then
    g.setColor(0, 0, 0, math.min(1, fade))
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end
end

return Warp
