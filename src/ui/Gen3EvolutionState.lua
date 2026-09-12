-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EVOLVING, IN HOENN.
--
-- Reported from play: "also need the evolution screen for emerald to work
-- properly currently its using the gen1 evolution screen".  It was:
-- src/ui/EvolutionState.lua is engine/movie/evolution.asm end to end -- a
-- 160x144 canvas, pokered's sentences, and its animation, which is the two
-- forms swapped back and forth at an accelerating rate.  Emerald does none of
-- those things.
--
-- WHAT THE CARTRIDGE DOES, and what this follows:
--
--   * the scene is its own screen, black, with the Pokemon high and the
--     message window at the bottom -- 240x160, like every other Gen 3 screen
--     here;
--   * the two forms are never shown side by side and never alternate in
--     colour.  The old one whitens and shrinks, the new one grows out of the
--     white, and only the settled form is ever coloured;
--   * the song is the scene's own (audio.special.evolution) and the
--     congratulation lands on the FANFARE (audio.special.evolved), which the
--     Game Boy screen never played;
--   * B stops it, and a traded or stone-forced evolution cannot be stopped.
--
-- WHAT IS DERIVED AND WHAT IS NOT.  The three sentences are the cartridge's,
-- read by RomExtractorGen3:extractEvolutionText out of the one contiguous run
-- the scene speaks them from, and both songs are roles the song-role stage
-- already resolves.  The TIMING and the sparkles are RECONSTRUCTED -- measured
-- off the scene rather than read out of it -- and are named as such here
-- rather than dressed up as constants.

local Music = require("src.core.Music")

local Gen3EvolutionState = {}
Gen3EvolutionState.__index = Gen3EvolutionState
Gen3EvolutionState.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED, not derived: how long each beat of the scene runs, in frames.
local MORPH_FRAMES = 150     -- whiten, shrink, grow
local FLASH_FRAMES = 12      -- the white-out the new form arrives through
local SPARKS = 14

function Gen3EvolutionState:uiSize()
  return require("src.ui.Theme").uiSize()
end

-- The whole screen is a photograph rather than four shades, exactly as the
-- bag and the mart are.
function Gen3EvolutionState:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- The cartridge's own line, with the port's as the fallback for a cache
-- imported before extractEvolutionText existed.
local FALLBACK = {
  evolving = "What?\n{VAR1} is evolving!",
  congratulations = "Congratulations! Your {VAR1}\nevolved into {VAR2}!",
  stopped = "Huh? {VAR1}\nstopped evolving!",
}

local function line(game, role)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3Evolution
  local text = (type(r) == "table" and r[role]) or FALLBACK[role]
  return text or ""
end

-- gsub's replacement is escaped because a nickname may hold a percent sign.
local function fill(text, one, two)
  local function safe(s) return (tostring(s):gsub("%%", "%%%%")) end
  return (text:gsub("{VAR1}", safe(one or "")):gsub("{VAR2}", safe(two or "")))
end

local function frontSprite(game, species, mon)
  local path = require("src.pokemon.Sprites").path(
    game.data, species, "front", { mon = mon, kind = "evolution" })
  if not path then return nil, nil end
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok or not img then return nil, nil end
  -- ...and the same picture as a white shape.  Emerald shows BOTH forms as
  -- white while they trade places -- the colour is what arrives at the end --
  -- so the silhouette is built once here rather than tinted every frame,
  -- which would flood the interior of a sprite whose own pixels are pale.
  local white
  if love.image and love.image.newImageData then
    local okData, imgData = pcall(love.image.newImageData, path)
    if okData and imgData then
      imgData:mapPixel(function(_, _, _, _, _, a)
        if a > 0 then return 1, 1, 1, a end
        return 0, 0, 0, 0
      end)
      local okWhite, w = pcall(love.graphics.newImage, imgData)
      if okWhite then white = w end
    end
  end
  return img, white
end

function Gen3EvolutionState.new(game, mon, newSpecies, onDone, via, evo)
  local self = setmetatable({}, Gen3EvolutionState)
  self.game = game
  self.mon = mon
  self.newSpecies = newSpecies
  self.onDone = onDone
  self.via = via
  self.evo = evo
  -- the same rule the Game Boy screen follows and the cartridge's own: a
  -- trade evolution and a stone-forced one are not offered the way out
  self.cancelable = (via ~= "TRADE" and via ~= "ITEM")
  self.oldName = mon.nickname or game.data.pokemon[mon.species].name
  self.newName = (game.data.pokemon[newSpecies] or {}).name or newSpecies
  self.oldSprite, self.oldWhite = frontSprite(game, mon.species, mon)
  self.newSprite, self.newWhite = frontSprite(game, newSpecies, mon)
  self.t = 0
  self.phase = "asking"
  self.canceled = false
  Music.play(game.data, Music.special(game.data, "evolution"))
  -- "What? MON is evolving!" first, and the morph starts when it is read.
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, fill(line(game, "evolving"), self.oldName),
    function() self.phase = "morph" self.t = 0 end))
  return self
end

-- The white form's scale at this point in the morph: the old one closes and
-- the new one opens, crossing at the halfway mark.
function Gen3EvolutionState:scales()
  local p = math.min(1, self.t / MORPH_FRAMES)
  -- eased so the two ends are slow and the exchange itself is quick, which is
  -- what the scene reads like
  local e = p * p * (3 - 2 * p)
  return 1 - e, e
end

function Gen3EvolutionState:stop()
  local game = self.game
  self.phase = "done"
  self.canceled = true
  Music.restoreMap(game.data)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, fill(line(game, "stopped"), self.oldName),
    function()
      game.stack:pop()                    -- the evolution screen itself
      if self.onDone then self.onDone() end
    end))
end

function Gen3EvolutionState:finish()
  local game = self.game
  local Evolution = require("src.pokemon.Evolution")
  Evolution.apply(game, self.mon, self.newSpecies, self.via, self.evo)
  require("src.core.Sound").playCry(game.data, self.newSpecies)
  -- THE CONGRATULATION IS A FANFARE, which is the part the Game Boy screen
  -- never had: the scene's song stops and MUS_EVOLVED plays over the text.
  local fanfare = Music.special(game.data, "evolved")
  if fanfare then Music.playOnce(game.data, fanfare) end
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game,
    fill(line(game, "congratulations"), self.oldName, self.newName),
    function()
      Music.restoreMap(game.data)
      game.stack:pop()                    -- the evolution screen itself
      -- the evolved species may know moves this one did not; the screen has
      -- to be off the stack before that text pushes
      Evolution.learnEvolutionMoves(game, self.mon, self.onDone)
    end))
end

function Gen3EvolutionState:update()
  self.t = self.t + 1
  if self.phase == "asking" or self.phase == "done" then return end
  if self.phase == "morph" then
    if self.cancelable and self.game.input
       and self.game.input:wasPressed("b") then
      return self:stop()
    end
    if self.t >= MORPH_FRAMES then
      self.phase = "flash"
      self.t = 0
    end
    return
  end
  if self.phase == "flash" and self.t >= FLASH_FRAMES then
    self.phase = "done"
    self:finish()
  end
end

-- Where a front sprite stands: centred, and sitting on the same line whatever
-- its height, so the two forms do not jump when they change places.
local FLOOR_Y = 104

local function drawMon(image, scale)
  if not image or scale <= 0.01 then return end
  local w, h = image:getDimensions()
  local x = GBA_W / 2
  local y = FLOOR_Y
  love.graphics.draw(image, x, y, 0, scale, scale, w / 2, h)
  -- the zone is the drawn size, not the sheet's: a half-scale form that
  -- claimed a full-size zone would hand the palette pass the black behind it
  require("src.render.PaletteFX").markTrueColor(
    math.floor(x - w * scale / 2), math.floor(y - h * scale),
    math.ceil(w * scale), math.ceil(h * scale))
end

function Gen3EvolutionState:draw()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)

  if self.phase == "asking" then
    drawMon(self.oldSprite, 1)
  elseif self.phase == "morph" then
    local oldScale, newScale = self:scales()
    drawMon(self.oldWhite or self.oldSprite, oldScale)
    drawMon(self.newWhite or self.newSprite, newScale)
    -- RECONSTRUCTED: the ring of sparks that closes on the mon as it changes
    local p = math.min(1, self.t / MORPH_FRAMES)
    local radius = 96 * (1 - p) + 12
    love.graphics.setColor(1, 1, 1, 0.65)
    for i = 1, SPARKS do
      local a = (i / SPARKS) * 2 * math.pi + self.t * 0.05
      love.graphics.rectangle("fill",
        GBA_W / 2 + math.cos(a) * radius - 1,
        FLOOR_Y - 32 + math.sin(a) * radius * 0.6 - 1, 2, 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
  elseif self.phase == "flash" then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  else
    drawMon(self.canceled and self.oldSprite or self.newSprite, 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3EvolutionState
