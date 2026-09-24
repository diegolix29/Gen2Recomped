-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's opening card, and the reason it is only a card.
--
-- The cartridge's boot is GAME FREAK's credit, then Giratina turning through a
-- portal, then the title.  The middle one is `giratina.nsbmd` -- a 3D model
-- with its own animation and texture tracks -- and this engine has no 3D path
-- for Gen 4 yet, so there is nothing to play it with.  Two honest options: draw
-- the card and move on, or draw nothing.  This draws the card.
--
-- WHAT IT IS NOT is a stand-in for the movie.  No invented swirl, no Giratina
-- redrawn from stills that do not exist as stills -- the sequence that IS in
-- the cartridge as flat art is `gf_presents`, and that is what plays.  When the
-- mesh pipeline lands, the portal belongs here, between this card and the
-- title, and nothing else about this file has to change.
--
-- The boot record names this screen (field.boot.screens.splash), which is what
-- keeps a Platinum boot off IntroMovie -- everything after the studio card in
-- that one is Kanto art out of a manifest a Gen 4 cache does not have.

local Assets = require("src.render.Assets")

local Gen4Intro = {}
Gen4Intro.__index = Gen4Intro
Gen4Intro.isOpaque = true

local W, H = 256, 192

-- Frames, at the engine's fixed step.  Held short on purpose: this is the one
-- screen between pressing PLAY and seeing the game, and the cartridge fills the
-- same stretch with a movie this cannot show.
local T_IN = 20       -- the card fades up
local T_HOLD = 80     -- and sits
local T_OUT = 100     -- then fades to black
local T_DONE = 120

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

function Gen4Intro:update()
  self.frame = self.frame + 1
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
  if not self:img("presents") then return self:finish() end
  if self.frame >= T_DONE then self:finish() end
end

function Gen4Intro:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)

  local card, box = self:img("presents")
  if not card then return end

  local f = self.frame
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
