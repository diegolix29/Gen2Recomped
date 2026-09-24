-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- What a NEW GAME on Platinum actually opens with: a television broadcast,
-- then Professor Rowan.
--
-- Until now NEW GAME went straight to the bedroom, because `boot.screens.
-- newGame` was `false` -- OakSpeech replays a professor's intro out of text
-- Platinum does not have, and there was nothing else to put there.  There is
-- now: the `intro` stage extracts both scenes and both scripts, and this plays
-- them.
--
-- THE TELEVISION FIRST.  `RowanIntroTv` is its own application on the
-- cartridge and it runs before Rowan's: a news report about the professor
-- returning to Sinnoh, drawn as three background layers -- the broadcast, a
-- scanline overlay and the set's bezel -- with one line of text under it.
--
-- THEN ROWAN, over five backdrops and ten figures, of which this plays the
-- main line: the greeting, who you are, your name, your friend's name, and the
-- send-off.  The CONTROL INFO and ADVENTURE INFO lectures are extracted and
-- NOT offered here -- they are a menu of tutorials about a touch screen and a
-- +Control Pad this port does not have, and a lecture that describes hardware
-- the player is not holding is worse than one they never saw.  `gen4_intro`
-- carries both so a mod can put them back.
--
-- PAGE BREAKS ARE IN THE TEXT ALREADY.  Gen 4 writes 0x25BC for "wait, then
-- clear" and 0x25BD for "wait, then scroll", and the decoder renders them as
-- CR and FF -- so a page is a split on those characters rather than something
-- this file has to count.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")

local Gen4RowanIntro = {}
Gen4RowanIntro.__index = Gen4RowanIntro
Gen4RowanIntro.isOpaque = true

local W, H = 256, 192

-- The dialogue box, in tiles.  Full width, eight tiles tall at the bottom,
-- which is where every Gen 4 message sits.
local BOX = { tx = 0, ty = 16, tw = 32, th = 8 }
local TEXT_X = (BOX.tx + 2) * 8
local TEXT_Y = (BOX.ty + 1) * 8 + 4
local LINE_H = 14

function Gen4RowanIntro:uiSize() return W, H end
function Gen4RowanIntro:wantsFillScale() return true end
function Gen4RowanIntro:wantsEdgeBleed() return false end

function Gen4RowanIntro:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4RowanIntro.new(game, onDone)
  local self = setmetatable({}, Gen4RowanIntro)
  self.game = game
  self.onDone = onDone
  self.cache = {}
  self.rec = (game.data and game.data.gen4_intro) or nil
  self.answers = { gender = "boy" }
  self.blink = 0

  if not self.rec then
    -- A cache from before the intro stage.  Finishing immediately is the same
    -- behaviour NEW GAME had before this screen existed, which is a playable
    -- game rather than a blank screen nobody can get out of.
    Logger.warn("gen4 intro: this cache carries no `gen4_intro` record; "
                .. "skipping the opening")
    self.finished = true
    return self
  end

  self.phase = "tv"
  self.pages = self:pagesOf(self.rec.text and self.rec.text.tv)
  self.page = 1
  self.step = 0
  return self
end

-- ------------------------------------------------------------------ text --

-- Split a decoded Gen 4 string into pages.  CR is the cartridge's "wait, then
-- clear" and FF its "wait, then scroll"; both end a page as far as a reader is
-- concerned, and neither is a character to draw.
function Gen4RowanIntro:pagesOf(text)
  if type(text) ~= "string" or text == "" then return { "" } end
  text = self:fill(text)
  local pages = {}
  for page in (text .. "\r"):gmatch("([^\r\f]*)[\r\f]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then pages[#pages + 1] = page end
  end
  if #pages == 0 then pages[1] = "" end
  return pages
end

-- Substitute the two names the script asks for and drop the control codes
-- this screen does not act on.  `{STRVAR_1 3 0 0}` is the player and
-- `{STRVAR_1 3 1 0}` the rival -- the middle number is the variable slot, and
-- it is the only part that distinguishes them.
function Gen4RowanIntro:fill(text)
  local player = self.answers.name or Strings("PLAYER")
  local rival = self.answers.rival or Strings("RIVAL")
  text = text:gsub("{STRVAR_1 %d+ (%d+) %d+}", function(slot)
    return (slot == "1") and rival or player
  end)
  -- {YESNO 0} arms the cartridge's own yes/no box; this screen puts its
  -- question up itself, so the marker is not a word to print.
  text = text:gsub("{YESNO %d+}", "")
  text = text:gsub("{COLOR %d+}", "")
  return text
end

-- ---------------------------------------------------------------- pictures --

function Gen4RowanIntro:img(entry)
  local path = type(entry) == "table" and entry.path or entry
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then
      self.cache[path]:setFilter("nearest", "nearest")
    end
  end
  return self.cache[path] or nil
end

function Gen4RowanIntro:backdrop(role)
  return self:img((self.rec.backdrops or {})[role])
end

function Gen4RowanIntro:figure(name)
  return self:img((self.rec.figures or {})[name])
end

-- ------------------------------------------------------------------ flow --

function Gen4RowanIntro:currentStep()
  return (self.rec.script or {})[self.step]
end

function Gen4RowanIntro:beginStep(n)
  self.step = n
  local step = self:currentStep()
  if not step then return self:finish() end
  self.pages = self:pagesOf((self.rec.text or {})[step.text])
  self.page = 1
end

-- A page turned, or the step's question asked once its last page is read.
function Gen4RowanIntro:advance()
  if self.phase == "tv" then
    if self.page < #self.pages then
      self.page = self.page + 1
      return
    end
    self.phase = "rowan"
    return self:beginStep(1)
  end

  if self.page < #self.pages then
    self.page = self.page + 1
    return
  end
  local step = self:currentStep()
  if step and step.ask == "gender" and not self.answers.genderPicked then
    self.phase = "gender"
    return
  end
  if step and step.ask == "name" and not self.answers.name then
    return self:askName()
  end
  if step and step.ask == "rivalName" and not self.answers.rival then
    return self:askRivalName()
  end
  self:beginStep(self.step + 1)
end

function Gen4RowanIntro:askName()
  local boot = self.game.data.field and self.game.data.field.boot
  local presets = (boot and boot.namePresets and boot.namePresets.player) or nil
  local maxLen = (self.game.data.constants or {}).playerNameLength or 7
  Screens.push(self.game, "NamingScreen", {
    title = self:fill((self.rec.text or {}).name or Strings("YOUR NAME?")),
    presets = presets,
    maxLen = maxLen,
    onDone = function(name)
      self.answers.name = name
      local save = self.game.save
      if save and save.player then save.player.name = name end
      -- The confirmation line has the placeholder in it, so it only reads
      -- correctly once the name is set -- which it now is.
      self:say(self.answers.gender == "girl" and "confirmNameFemale"
               or "confirmNameMale")
    end,
  })
end

function Gen4RowanIntro:askRivalName()
  local presets = {}
  for _, row in ipairs(self.rec.rivalNames or {}) do
    -- The first entry is "New name!", the prompt to type one rather than a
    -- name to offer; the naming screen already has that as its own path.
    if not row.custom and row.label then presets[#presets + 1] = row.label end
  end
  local maxLen = (self.game.data.constants or {}).playerNameLength or 7
  Screens.push(self.game, "NamingScreen", {
    title = self:fill((self.rec.text or {}).rivalName or Strings("RIVAL")),
    presets = presets,
    maxLen = maxLen,
    onDone = function(name)
      self.answers.rival = name
      local save = self.game.save
      if save and save.player then save.player.rival = name end
      self:say("confirmRivalName")
    end,
  })
end

-- Put one line up out of turn -- a confirmation the script does not have a
-- step for -- and carry on from the step after the current one when it is read.
function Gen4RowanIntro:say(key)
  self.pages = self:pagesOf((self.rec.text or {})[key])
  self.page = 1
  self.sayThenAdvance = true
end

function Gen4RowanIntro:chooseGender(which)
  self.answers.gender = which
  self.answers.genderPicked = true
  local save = self.game.save
  if save and save.player then save.player.gender = which end
  -- ...AND THE CHARACTER ALREADY STANDING ON THE MAP.  New Game pushes the
  -- overworld first and this screen on top of it, so the Player object exists
  -- and has already chosen its sheets.  Writing the answer to the save changes
  -- what the NEXT one would wear and nothing about this one, which is how a
  -- player who picked the girl walked out of the bedroom as the boy.
  local overworld = self.game.overworld
  local avatar = overworld and overworld.player
  if avatar and avatar.refreshForm then
    pcall(function() avatar:refreshForm(self.game.data) end)
  end
  self.phase = "rowan"
  self:say(which == "girl" and "confirmGirl" or "confirmBoy")
end

function Gen4RowanIntro:finish()
  if self.done then return end
  self.done = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen4RowanIntro:update()
  self.blink = (self.blink + 1) % 60
  if self.finished then return self:finish() end
  local input = self.game.input
  if not input then return end

  if self.phase == "gender" then
    if input:wasPressed("left") or input:wasPressed("right") then
      self.answers.gender = (self.answers.gender == "boy") and "girl" or "boy"
    elseif input:wasPressed("a") then
      self:chooseGender(self.answers.gender)
    end
    return
  end

  if input:wasPressed("a") or input:wasPressed("b")
     or input:wasPressed("start") then
    if self.sayThenAdvance and self.page >= #self.pages then
      self.sayThenAdvance = nil
      return self:beginStep(self.step + 1)
    end
    self:advance()
  end
end

-- ------------------------------------------------------------------ draw --

function Gen4RowanIntro:drawScene()
  local g = love.graphics
  if self.phase == "tv" then
    local tv = self.rec.tv or {}
    for _, key in ipairs({ "broadcast", "scanlines", "bezel" }) do
      local image = self:img(tv[key])
      if image then
        g.setColor(1, 1, 1, 1)
        local iw, ih = image:getDimensions()
        -- The three layers are 256x256 because that is the background size the
        -- hardware uses; the screen is the top 192 rows of it.
        local quad = g.newQuad(0, 0, math.min(W, iw), math.min(H, ih), iw, ih)
        g.draw(image, quad, 0, 0)
      end
    end
    return
  end

  local step = self:currentStep()
  local backdrop = self:backdrop((step and step.backdrop) or "speech")
    or self:backdrop("plain")
  if backdrop then
    g.setColor(1, 1, 1, 1)
    g.draw(backdrop, 0, 0)
  end

  if self.phase == "gender" then
    -- Both characters, the chosen one lit and the other dimmed.  They are
    -- full-screen pictures rather than sprites, so they cannot sit side by
    -- side without cutting one of them up; showing one at a time with LEFT
    -- and RIGHT to swap is the honest version of the cartridge's two buttons.
    local role = self.rec.role or {}
    local key = (self.answers.gender == "girl") and (role.girl or "girl_1")
                or (role.boy or "boy_1")
    local figure = self:figure(key)
    if figure then
      g.setColor(1, 1, 1, 1)
      g.draw(figure, 0, 0)
    end
    return
  end

  if step and step.figure then
    local role = self.rec.role or {}
    local key = step.figure
    if key == "boy" or key == "girl" then key = role[key] or (key .. "_1") end
    local figure = self:figure(key)
    if figure then
      g.setColor(1, 1, 1, 1)
      g.draw(figure, 0, 0)
    end
  end
end

function Gen4RowanIntro:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if not self.rec then return end

  self:drawScene()

  -- Platinum's own message box, which Font.drawDialogueBox draws from the
  -- eighteen-tile strip the graphics stage wrote.
  Font.drawDialogueBox(BOX.tx, BOX.ty, BOX.tw, BOX.th)

  -- Drawn at white: the Gen 4 font page is pre-tinted (dark letter, light
  -- shadow) and multiplying it by black paints the shadow black too.
  local page = self.pages and self.pages[self.page] or ""
  local y = TEXT_Y
  for line in (tostring(page) .. "\n"):gmatch("([^\n]*)\n") do
    if y > (BOX.ty + BOX.th - 1) * 8 then break end
    Font.draw(line, TEXT_X, y)
    y = y + LINE_H
  end

  if self.phase == "gender" then
    local label = (self.answers.gender == "girl") and Strings("GIRL")
                  or Strings("BOY")
    Font.draw(label, W - 64, (BOX.ty - 3) * 8)
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4RowanIntro
