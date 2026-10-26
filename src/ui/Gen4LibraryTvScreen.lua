-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S CANALAVE LIBRARY TELEVISION, the app StartLibraryTV runs
-- (art: src/import/Gen4LibraryTv.lua, cache key gen4_library_tv).
--
-- READ FROM CODE: pokeplatinum src/library_tv/library_tv.c, LibraryTV_Main.
--   STATE_INIT        both screens black, the layers loaded       (1 frame)
--   STATE_BGM_START   waitTiming is 0: straight through           (1 frame)
--   STATE_FADE_START  StartScreenFade(both, BRIGHTNESS_IN, black,
--                     6 steps, 1 frame each)                      (1 frame)
--   STATE_FADE_WAIT   scan lines scroll until the fade is done    (6 frames)
--   STATE_MAIN        LIBRARY_TV_DURATION = 90 + 150 = 240 frames
--   STATE_EXIT        the same fade out, then the app returns     (6 frames)
-- LibraryTV_UpdateScanLines runs in the last three: scanLinePos += 4 and BG1's
-- Y offset = scanLinePos >> 4, so the lines climb one pixel every fourth
-- frame.  The blend is G2_SetBlendAlpha(BG1, BG2|BG3, 4, 12): the scan lines
-- at 4/16 over the picture at 12/16 -- ordinary alpha 0.25 -- and BG0, the
-- bezel, opaque on top.
--
-- An application, not the field: it steps once per ENGINE tick (60 Hz), the
-- rate the cartridge's apps run at.  The script (ScrCmd_StartLibraryTV +
-- ScriptContext_WaitForApplicationExit) waits for it to return.
--
-- STAND-INS: the bottom screen is left as the port draws it (the app blanks
-- the sub screen: no layers, black brightness).

local Assets = require("src.render.Assets")

local S = {}
S.__index = S
S.isOpaque = true

local W, H = 256, 192
S.FADE = 6
S.DURATION = 90 + 150

function S:uiSize() return W, H end
function S:wantsFillScale() return true end

function S.available(game)
  local rec = game and game.data and game.data.gen4_library_tv
  return rec ~= nil and rec.layers ~= nil and rec.layers.picture ~= nil
end

function S.new(game, onDone)
  return setmetatable({ game = game, onDone = onDone, images = {},
                        rec = (game.data or {}).gen4_library_tv or {},
                        state = "init", frame = 0, scanLinePos = 0 }, S)
end

function S:img(entry)
  if not (entry and entry.path) then return nil end
  local hit = self.images[entry.path]
  if hit == nil then
    local ok, i = pcall(Assets.image, entry.path)
    if ok and i then i:setFilter("nearest", "nearest"); i:setWrap("repeat", "repeat") end
    hit = (ok and i) or false
    self.images[entry.path] = hit
  end
  return hit or nil
end

function S:update()
  local st = self.state
  if st == "init" then self.state = "bgm"
  elseif st == "bgm" then self.state = "fadeStart"
  elseif st == "fadeStart" then self.state, self.frame = "fadeIn", 0
  else
    -- LibraryTV_UpdateScanLines, in FADE_WAIT, MAIN and EXIT alike
    self.scanLinePos = self.scanLinePos + 4
    self.frame = self.frame + 1
    if st == "fadeIn" and self.frame >= S.FADE then self.state, self.frame = "main", 0
    elseif st == "main" and self.frame >= S.DURATION then self.state, self.frame = "fadeOut", 0
    elseif st == "fadeOut" and self.frame >= S.FADE then
      self.state = "done"
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

function S:brightness()
  if self.state == "fadeIn" then return math.min(1, self.frame / S.FADE) end
  if self.state == "main" then return 1 end
  if self.state == "fadeOut" then return math.max(0, 1 - self.frame / S.FADE) end
  return 0
end

function S:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  local layers = self.rec.layers or {}
  local pic, lines, bezel = self:img(layers.picture), self:img(layers.scanlines), self:img(layers.bezel)
  g.setColor(1, 1, 1, 1)
  if pic then g.draw(pic, g.newQuad(0, 0, W, H, pic:getDimensions()), 0, 0) end
  if lines then
    -- BG1's Y offset scrolls the map up; the 256-row map wraps
    local oy = math.floor(self.scanLinePos / 16) % 256
    g.setColor(1, 1, 1, 4 / 16)
    g.draw(lines, g.newQuad(0, oy, W, H, lines:getDimensions()), 0, 0)
    g.setColor(1, 1, 1, 1)
  end
  if bezel then g.draw(bezel, g.newQuad(0, 0, W, H, bezel:getDimensions()), 0, 0) end
  local b = self:brightness()
  if b < 1 then
    g.setColor(0, 0, 0, 1 - b)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

return S
