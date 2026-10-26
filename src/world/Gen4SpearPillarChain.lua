-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE RED CHAIN AT SPEAR PILLAR: `ScrCmd_20D 0` / `ScrCmd_20D 1`, the field
-- effect the script starts right after Cyrus's "Everything is ready..." and
-- polls before ScrCmd_2FB launches the cinematic (src/ui/
-- Gen4SpearPillarCutscene.lua).
--
-- READ FROM CODE: pokeplatinum src/overlay006/ov6_02243004.c (the ten-mode
-- switch: mode 0 = ov6_0223E6EC starts this effect, mode 1 = ov6_0223E708
-- polls it, answering 1 and deleting it once its state is 11) and
-- src/overlay006/ov6_0223E140.c:
--   ov6_02240104   demo_tengan_gra 74 tiles / 76 screen on field BG2,
--                  palette 75 into BG palette row 6, BG2 at priority 1, and
--                  G2_SetBlendAlpha(BG2, BG0, eva 0, evb 31)
--   ov6_02240260   the chain model 6 with its tracks 4 (BCA) and 5 (BMA)
--   ov6_0223E574   state 2 places the model at local map object 1;
--                  state 3: twelve alpha steps, each after an 8-frame wait,
--                  stepping eva / evb by one a frame (ov6_02240364) while
--                  both tracks advance one frame a pass; when the steps and
--                  the tracks are both done, state 4 takes eva and evb down
--                  to 0, then state 11 (finished)
-- The field steps it once per field frame -- two engine ticks.
--
-- ON SCREEN: BG2 is solid red, so the field is shown as
--   (red * eva + field * evb) / 16
-- -- the field pulsing toward red twelve times, the troughs shallower each
-- time, then letting go.
--
-- AN OVERLAY ABOVE THE FIELD, and the field keeps running under it: this
-- state forwards every update to the state below, so the script that started
-- the effect carries on (WaitTime, the chain SE, the music) exactly as it
-- does on the cartridge while the effect plays; the mode-1 poll then waits
-- on `done`.
--
-- STAND-INS: the chain model itself (model 6) is not drawn -- it would need
-- the field's 3D pass; eva/evb above 16 (the first 15 frames start at evb
-- 31, an over-bright field) are clamped to 16; ov6_02240364's leftover
-- D-pad debug control of the two coefficients is not carried.

local Assets = require("src.render.Assets")

local C = {}
C.__index = C
C.isOpaque = false
C.TICKS_PER_FRAME = 2
C.STEPS = 12
C.ANIM_FRAMES = 201

C.current = nil

-- ov6_02240364: one alpha step; true when both coefficients reached theirs
local BOUNDS = {
  -- [step] = { troughEva, troughEvb } for the "down" half
  [1] = { 2, 14 }, [2] = { 2, 14 }, [3] = { 2, 14 }, [4] = { 2, 14 },
  [5] = { 3, 13 }, [6] = { 3, 13 }, [7] = { 3, 13 }, [8] = { 3, 13 },
  [9] = { 4, 12 }, [10] = { 4, 12 },
  [11] = { 5, 11 }, [12] = { 5, 11 },
  [13] = { 6, 10 }, [14] = { 6, 10 },
}
function C.pulse(st, up, step)
  local done1, done2 = false, false
  if step == 0 then
    if st.evb > 16 then st.evb = st.evb - 1 else done1, done2 = true, true end
  elseif BOUNDS[step] then
    if up ~= 0 then
      if st.eva < 8 then st.eva = st.eva + 1 else done1 = true end
      if st.evb > 8 then st.evb = st.evb - 1 else done2 = true end
    else
      local b = BOUNDS[step]
      if st.eva > b[1] then st.eva = st.eva - 1 else done1 = true end
      if st.evb < b[2] then st.evb = st.evb + 1 else done2 = true end
    end
  else
    if st.eva > 0 then st.eva = st.eva - 1 else done1 = true end
    if st.evb > 0 then st.evb = st.evb - 1 else done2 = true end
  end
  return done1 and done2
end

function C.new(game)
  local self = setmetatable({ game = game, tick = 0, state = 0, step = 0, timer = 0,
                              eva = 0, evb = 31, anim = 0, done = false }, C)
  local rec = game and game.data and game.data.gen4_spear_pillar
  self.bg2 = rec and rec.bg and rec.bg.chain and rec.bg.chain.bg2
  return self
end

-- ov6_0223E574, one field frame
function C:frame()
  local s = self.state
  if s == 0 or s == 1 or s == 2 then
    -- ov6_022401D0: the model placed and shown, its tracks at frame 0
    self.anim = 0
    self.step, self.timer = 0, 0
    self.state = 3
  elseif s == 3 then
    local v3 = false
    if self.step ~= C.STEPS then
      self.timer = self.timer + 1
      if self.timer >= 8 then
        v3 = C.pulse(self, self.step % 2, self.step)
        if v3 then
          self.timer = 0
          self.step = self.step + 1
        end
      end
    else
      v3 = true
    end
    -- ov6_022405D0: both tracks advance (Easy3DAnim_Update), the model
    -- hides once they are through
    local animDone = false
    if self.anim + 1 < C.ANIM_FRAMES then self.anim = self.anim + 1
    else self.anim = C.ANIM_FRAMES; animDone = true end
    if animDone and v3 then
      self.timer = 0
      self.state = 4
    end
  elseif s == 4 then
    if C.pulse(self, 0, 60) then self.state = 11 end
  end
  self.done = self.state == 11
end

function C:below()
  local stack = self.game and self.game.stack
  local states = stack and stack.states
  if not states then return nil end
  for i = #states, 1, -1 do
    if states[i] == self then return states[i - 1] end
  end
  return nil
end

function C:update(dt)
  self.tick = self.tick + 1
  if self.tick % C.TICKS_PER_FRAME == 0 then self:frame() end
  -- the field (and the script on it) keeps running underneath
  local under = self:below()
  if under and under.update then under:update(dt) end
  -- finished and nobody polling: ov5's effect list keeps it, invisible at
  -- eva 0; the overlay can go
  if self.done and not self.polled and self.game.stack:top() == self then self:close() end
end

function C:close()
  if self.closed then return end
  self.closed = true
  if C.current == self then C.current = nil end
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
end

function C:uiSize()
  local under = self:below()
  if under and under.uiSize then return under:uiSize() end
  return 256, 192
end

function C:draw()
  local g = love.graphics
  local w, h = self:uiSize()
  local evb = math.min(16, self.evb)
  local eva = math.min(16, self.eva)
  if evb < 16 then
    g.setColor(0, 0, 0, 1 - evb / 16)
    g.rectangle("fill", 0, 0, w, h)
  end
  if eva > 0 then
    local mode, alphaMode = g.getBlendMode()
    g.setBlendMode("add", "alphamultiply")
    local img
    if self.bg2 then
      local ok, i = pcall(Assets.image, type(self.bg2) == "table" and self.bg2.path or self.bg2)
      img = ok and i or nil
    end
    if img then
      g.setColor(1, 1, 1, eva / 16)
      -- the screen's 256 x 192 of the 32 x 32-tile map
      local iw, ih = img:getDimensions()
      self.quad = self.quad or g.newQuad(0, 0, math.min(iw, 256), math.min(ih, 192), iw, ih)
      g.draw(img, self.quad, 0, 0, 0, w / math.min(iw, 256), h / math.min(ih, 192))
    else
      g.setColor(0.86, 0, 0, eva / 16)
      g.rectangle("fill", 0, 0, w, h)
    end
    g.setBlendMode(mode, alphaMode)
  end
  g.setColor(1, 1, 1, 1)
end

-- ScrCmd_20D 0
function C.start(game)
  if C.current and not C.current.closed then return C.current end
  local fx = C.new(game)
  C.current = fx
  game.stack:push(fx)
  return fx
end

return C
