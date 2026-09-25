-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's title screen.
--
-- Four pictures out of `/demo/title/titledemo.narc`, each composed by the
-- graphics stage and named by role in `gen4_menus.title`:
--
--   top_screen_border     the ragged white field the logo sits in
--   logo                  POKéMON PLATINUM VERSION
--   copyright             the four (c) lines, on black
--   bottom_screen_border  the dark field those lines sit on
--
-- ONE SCREEN OUT OF TWO, and deliberately.  A DS title is two panels: the logo
-- above, the copyright below.  This engine draws one surface, and the dual
-- screen work (the Poketch toggle and the corner overlay) is designed and not
-- built -- so the two are composed into one 256x192 screen here rather than the
-- copyright being dropped.  When the second screen exists, this file splits
-- along the seam the two borders already mark.
--
-- WHAT IS MISSING IS NAMED RATHER THAN FAKED.  The centrepiece of the real
-- title is Giratina, an NSBMD model turning behind the logo, and there is no 3D
-- path yet.  So the logo sits on the border field alone.  Nothing here draws a
-- substitute for it.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Music = require("src.core.Music")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")

local Gen4Title = {}
Gen4Title.__index = Gen4Title
Gen4Title.isOpaque = true

local W, H = 256, 192

-- WHERE THE TWO PANELS MEET IS MEASURED, NOT PICKED.
--
-- Every sheet in this archive is 256x192 or 256x256 and most of it is empty:
-- the logo's artwork occupies rows 27 to 148 of its own sheet and the
-- copyright's four lines rows 64 to 119.  Drawn at 0,0 on the sheet size the
-- logo lands forty rows low and "VERSION" is cut off at the seam -- which looks
-- like a layout choice rather than a measurement nobody took.
--
-- So the menus stage measures each picture's content box and this splits the
-- screen by what has to fit in each half: the logo's height above, the
-- copyright block's below, and the slack shared between them.  A cache with no
-- boxes falls back to the sheet drawn as it stands, which is the old behaviour
-- rather than a crash.
local FALLBACK_SPLIT = 129

-- Frames, engine step.  The cartridge fades the logo up out of the border
-- field; the beats here are that fade and nothing invented around it.
local T_FADE = 24
local T_READY = 40

function Gen4Title:uiSize() return W, H end
function Gen4Title:wantsFillScale() return true end
function Gen4Title:wantsEdgeBleed() return false end

function Gen4Title:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4Title.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4Title)
  self.game = game
  self.onNewGame, self.onContinue = opts.onNewGame, opts.onContinue
  local menus = game.data and game.data.gen4_menus
  self.art = (menus and menus.title) or {}
  self.cache = {}
  self.frame = 0
  self.blink = 0
  self.opened = false
  return self
end

-- The picture, and the record that says where its artwork sits inside it.
-- The record is `{ path, width, height, content = { x, y, w, h } }`; an older
-- cache wrote a bare path string, which still resolves and simply has no box.
function Gen4Title:img(key)
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

-- How tall the logo panel is.  Both halves are sized by what must fit in them,
-- and the rows neither needs are split between them.
function Gen4Title:split()
  local _, logoBox = self:img("logo")
  local _, copyBox = self:img("copyright")
  if not (logoBox and copyBox) then return FALLBACK_SPLIT end
  local slack = H - logoBox.h - copyBox.h
  if slack < 0 then return FALLBACK_SPLIT end
  return logoBox.h + math.floor(slack / 2)
end

-- The title theme, if the audio stage has run.  Gen 4 songs are not extracted
-- yet, so this is a no-op on every current cache -- written now so it starts
-- working the day they are, rather than being a thing to remember later.
function Gen4Title:enter()
  self.frame, self.opened = 0, false
  local data = self.game.data
  local songs = data and data.audio and data.audio.songs
  local id = data and data.gen4_menus and data.gen4_menus.titleSong
  if id and songs and songs[id] then pcall(Music.play, data, id) end
end

function Gen4Title:resume()
  self.opened = false
end

function Gen4Title:openMenu()
  if self.opened then return end
  self.opened = true
  Screens.push(self.game, "Gen4MainMenu", {
    onNewGame = self.onNewGame,
    onContinue = self.onContinue,
  })
end

function Gen4Title:update()
  -- updated again with the flag still set means the menu was backed out of
  if self.opened then self:resume() end
  self.frame = self.frame + 1
  self.blink = (self.blink + 1) % 90
  local input = self.game.input
  if not input then return end
  if input:wasPressed("start") or input:wasPressed("a") then
    if self.frame < T_READY then
      -- skip the fade rather than swallowing the press
      self.frame = T_READY
    else
      self:openMenu()
    end
  end
end

-- Draw a picture's content box into a band, centred vertically in it.  Where
-- no box was measured the sheet is drawn as it stands, clipped to the band.
local function drawInBand(img, box, top, height, alpha)
  local g = love.graphics
  g.setColor(1, 1, 1, alpha or 1)
  local iw, ih = img:getDimensions()
  if box then
    local quad = g.newQuad(0, box.y, math.min(W, iw), math.min(box.h, ih - box.y),
                           iw, ih)
    g.draw(img, quad, 0, top + math.floor((height - box.h) / 2))
  else
    local quad = g.newQuad(0, 0, math.min(W, iw), math.min(height, ih), iw, ih)
    g.draw(img, quad, 0, top)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4Title:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)

  local split = self:split()

  -- the logo panel: the border field first, clipped at the seam
  local border = self:img("topBorder")
  if border then
    g.setColor(1, 1, 1, 1)
    g.setScissor()
    local sx, sy = g.transformPoint(0, 0)
    local ex, ey = g.transformPoint(W, split)
    g.setScissor(math.floor(sx), math.floor(sy),
                 math.max(0, math.ceil(ex - sx)), math.max(0, math.ceil(ey - sy)))
    g.draw(border, 0, 0)
    g.setScissor()
  end

  local logo, logoBox = self:img("logo")
  if logo then
    drawInBand(logo, logoBox, 0, split, math.min(1, self.frame / T_FADE))
  end

  -- the copyright strip
  local bottom = self:img("bottomBorder")
  if bottom then
    g.setColor(1, 1, 1, 1)
    local iw, ih = bottom:getDimensions()
    local quad = g.newQuad(0, 0, math.min(W, iw), math.min(H - split, ih), iw, ih)
    g.draw(bottom, quad, 0, split)
  end
  local copyright, copyBox = self:img("copyright")
  if copyright then
    drawInBand(copyright, copyBox, split, H - split, 1)
  end

  -- PRESS START is this port's, not the cartridge's -- Platinum simply waits.
  -- A window with no hardware START button needs to say which key opens the
  -- menu, and it is drawn in the copyright strip where nothing else is.
  if self.frame >= T_READY and self.blink < 60 then
    g.setColor(1, 1, 1, 1)
    local text = Strings("PRESS START")
    local width = Font.width(text)
    Font.draw(text, math.floor((W - width) / 2), H - 20)
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4Title
