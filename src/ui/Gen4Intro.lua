-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Copyright and native studio layers precede Gen4Title's portal/model sequence.
-- GameOpening uses its extracted backgrounds, cells and textured map models.

local Assets = require("src.render.Assets")

local Gen4Intro = {}
Gen4Intro.__index = Gen4Intro
Gen4Intro.isOpaque = true

local W, H = 256, 192

-- Card timings are reconstructed at the engine's fixed step.
local T_IN = 20       -- the card fades up
local T_HOLD = 80     -- and sits
local T_OUT = 100     -- then fades to black
local T_DONE = 120
local COPYRIGHT_FRAMES = 120

function Gen4Intro:uiSize() return W, H end
function Gen4Intro:wantsFillScale() return true end
function Gen4Intro:wantsEdgeBleed() return false end

function Gen4Intro:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4Intro.new(game, onDone)
  local self = setmetatable({}, Gen4Intro)
  self.game = game
  self.onDone = onDone
  self.frame = 0
  self.done = false
  local menus = game.data and game.data.gen4_menus
  self.art = (menus and menus.title) or {}
  self.cache = {}
  return self
end

-- The menus stage writes `{ path, width, height, content }` per picture; an
-- older cache wrote a bare path string, and both resolve here.
function Gen4Intro:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  local img = self.cache[path] or nil
  if not img then return nil end
  return img, (type(rec) == "table" and rec.content) or nil
end

function Gen4Intro:finish()
  if self.done then return end
  self.done = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen4Intro:enter()
  require('src.core.Music').stop()
end

function Gen4Intro:update(dt)
  self.frame = self.frame + 1
  if self.frame>=COPYRIGHT_FRAMES then
    local speed=self.game.logicSpeed and self.game:logicSpeed() or 1
    self.openingRemainder=(self.openingRemainder or 0)+(dt or 1/60)*30/math.max(1,speed)
    local ticks=math.floor(self.openingRemainder+1e-9)
    self.openingRemainder=self.openingRemainder-ticks
    self.openingFrame=(self.openingFrame or 0)+ticks
    if self.openingFrame>=508 then require('src.ui.Gen4Opening').update(self,self.openingFrame) end
    if not self.openingMusic then
      self.openingMusic=true
      local data=self.game.data
      local song=data and data.audio and data.audio.special and data.audio.special.opening
      if song then require('src.core.Music').play(data,song,false) end
    end
  end
  local input = self.game.input
  -- Skippable from the first frame.  A card the player has seen once should
  -- never be something they have to sit through, and the cartridge lets START
  -- past its own opening too.
  if input and (input:wasPressed("a") or input:wasPressed("b")
                or input:wasPressed("start")) then
    return self:finish()
  end
  -- NO ART, NO WAIT.  A cache extracted before the graphics stage existed has
  -- no card to draw, and holding a black screen for two seconds to show it
  -- would read as a hang.
  if not self:img("presents") and not self:img('copyright') then return self:finish() end
  if self:openingImage('first_top') then
    if (self.openingFrame or 0)>=(self:openingImage('sky') and 2430 or 508) then self:finish() end
  elseif self.frame >= COPYRIGHT_FRAMES + T_DONE then self:finish() end
end

function Gen4Intro:openingImage(key)
  local screens=self.game.data and self.game.data.gen4_graphics and self.game.data.gen4_graphics.screens
  local rec=screens and screens['opening/'..key]
  if not rec or not rec.path then return nil end
  if self.cache[rec.path]==nil then
    local ok,img=pcall(Assets.image,rec.path)
    self.cache[rec.path]=ok and img or false
  end
  return self.cache[rec.path] or nil
end

function Gen4Intro:drawStudio(bottom,merged)
  local g=love.graphics
  g.setColor(0,0,0,1);g.rectangle('fill',0,0,W,H)
  local f=self.openingFrame or 0
  local fade=math.max(0,math.min(1,(508-f)/18))
  -- Native tasks step the studio credit up every six frames and down every
  -- four, then reveal the top emblem and bottom wordmark in sequence.
  local creditAlpha=f<115 and math.min(1,math.floor(f/6)/16) or math.max(0,1-math.floor((f-115)/4)/16)
  if not bottom and creditAlpha>0 then
    local card=self:img('presents')
    if card then g.setColor(1,1,1,creditAlpha*fade);g.draw(card,0,0) end
  end
  local function layer(key,delay,y)
    local img=self:openingImage(key)
    local alpha=math.max(0,math.min(1,math.floor((f-delay)/4)/16))*fade
    if img and alpha>0 then g.setColor(1,1,1,alpha);g.draw(img,0,y or 0) end
  end
  if merged then
    layer('first_top',265,-32);layer('first_bottom',329,32)
  else
    layer(bottom and 'first_bottom' or 'first_top',bottom and 329 or 265)
  end
  if (bottom or merged) and creditAlpha>0 then
    local overlay=self:openingImage('first_overlay')
    if overlay then g.setColor(1,1,1,creditAlpha*fade);g.draw(overlay,0,0) end
  end
  g.setColor(1,1,1,1)
end

function Gen4Intro:draw()
  local g = love.graphics
  if self.frame>=COPYRIGHT_FRAMES and self:openingImage('first_top') then
    local S=require('src.ui.SecondScreen')
    local mode=S.mode(self.game)
    local dual=mode=='display' or mode=='inset'
    if (self.openingFrame or 0)>=508 and self:openingImage('sky') then
      local movie=require('src.ui.Gen4Opening')
      if dual then
        movie.draw(self,false)
        S.draw(self.game,function() movie.draw(self,true) end)
      else movie.drawPair(self) end
      return
    end
    self:drawStudio(false,not dual)
    if dual then S.draw(self.game,function() self:drawStudio(true,false) end) end
    return
  end
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)

  local key = self.frame < COPYRIGHT_FRAMES and 'copyright' or 'presents'
  local card, box = self:img(key)
  if not card then return end

  local f = self.frame < COPYRIGHT_FRAMES and self.frame or self.frame - COPYRIGHT_FRAMES
  local a = 1
  if f < T_IN then
    a = f / T_IN
  elseif f > T_OUT then
    a = math.max(0, 1 - (f - T_OUT) / (T_DONE - T_OUT))
  elseif f > T_HOLD then
    a = 1
  end
  g.setColor(1, 1, 1, a)
  -- CENTRED, NOT AS IT SITS IN ITS SHEET.
  --
  -- "Developed by GAME FREAK inc." occupies rows 181 to 189 of a 256x192 sheet
  -- -- the bottom-left corner -- because on the hardware it is the BOTTOM
  -- screen and the credit sits under the picture on the top one.  Drawn as it
  -- stands on one screen it is a black field with a line of type in the
  -- corner, which reads as a screen that failed to load rather than as a card.
  -- The content box the menus stage measured is what lets it be placed.
  if box then
    local quad = g.newQuad(box.x, box.y, box.w, box.h, card:getDimensions())
    g.draw(card, quad,
           math.floor((W - box.w) / 2), math.floor((H - box.h) / 2))
  else
    g.draw(card, 0, 0)
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4Intro

