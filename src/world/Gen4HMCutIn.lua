-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S HM CUT-IN: "<MON> used CUT!" and every other field move.
--
-- HMCutIn_StartTask(fieldSystem, FALSE, mon, gender) (pokeplatinum
-- src/overlay006/hm_cut_in.c), from ScrCmd_PlayHMCutIn (the field-move
-- scripts' PlayHMCutIn: Cut, Rock Smash, Strength, Defog, Flash) and from
-- NewMonRideCutIn (Surf, Rock Climb, Waterfall). The pictures are
-- /data/field_cutin.narc, imported into `gen4_pt_field_fx.cutIn`
-- (src/import/Gen4PtFieldFx.lua).
--
-- WHAT IS ON SCREEN. A hardware window W0 opens over the field: inside it
-- only BG3 (the gold Poke Ball band, field_cutin 0/1/2 on palette 12) and the
-- OBJs are drawn; outside it the field is untouched (CutIn_InitPlaneMasks).
-- Inside run the player holding up a Poke Ball (anim 6 of the trainer's cell
-- bank), the Pokemon's front picture, and 26 white wind streaks.
--
-- THE TASK, one state a field frame (sCutInTaskFuncs; a state returning TRUE
-- runs the next in the same frame):
--   0  CutIn_Init                     the window is set to (0,192)-(1,192): empty
--   1  InitSprites                    once the vblank transfer is done (the next
--                                     frame): player at (128,96), mon at
--                                     (296,96), the streaks; then at once
--   2  InitWindowAndPlayerSprite      window x 254..255, y 95..97, delta -64
--   3  WindowExpandX                  x1 += delta until <= 0; delta = 2
--   4  WindowExpandY                  y1 -= d, y2 += d, d += 2 (max 32), to
--                                     56..136; then the player's anim starts
--   5  SlideInSpeedUp                 15 frames
--   6  SlideMonIn                     x -= 64 until <= 160, then x = 192
--   7  SlideMonToCenter               d /= 2 (from -64), until d > -2: d = -2
--                                     and the cry
--   8  SlideOutSpeedUp                8 frames
--   9  SlideMonOut                    d = -1, doubled each frame (max -64),
--                                     until x <= -40; delta = 1
--   10 WindowShrinkY                  y1 += d, y2 -= d, d += 4 (max 32), to
--                                     88..104
--   11 DeleteSprites, 12 WindowTaskDone, 13 Done (isFinished)
--
-- A streak (WindParticleAnim_AnimateParticle) moves +16 or +24 a frame mod
-- 512 and is drawn only while y +- 2 lies inside the window's rows; the player
-- only while y +- 8 does (ShowHidePlayerSprite_ShowOrHide).
--
-- Frames are field frames: TICKS_PER_FRAME engine ticks each, as
-- src/world/Gen4FieldFx.lua counts them.

local M = {}
M.__index = M

M.TICKS_PER_FRAME = 2
M.SCREEN_W, M.SCREEN_H = 256, 192

-- sWindParticleAnimConfigs: x, y, dx, list priority, animation
M.WIND = {
  { 15, 63, 16, 0x85, 0 }, { 76, 67, 16, 0x85, 0 }, { 128, 61, 24, 0x80, 1 },
  { 240, 69, 16, 0x85, 0 }, { 40, 78, 24, 0x80, 1 }, { 72, 91, 16, 0x85, 0 },
  { 208, 86, 24, 0x80, 1 }, { 56, 116, 16, 0x85, 0 }, { 95, 109, 24, 0x80, 1 },
  { 159, 100, 16, 0x85, 0 }, { 24, 126, 24, 0x80, 1 }, { 140, 125, 24, 0x80, 1 },
  { 221, 124, 24, 0x80, 1 },
}

local function Game() return package.loaded["src.core.Game"] end

function M.art(data)
  local G = Game()
  data = data or (G and G.data)
  local t = data and data.gen4_pt_field_fx
  return t and t.cutIn or nil
end

-- the Pokemon's front picture (Sprites.path), as Gen3FieldMove finds it
local function frontSprite(game, mon)
  if not (mon and mon.species) then return nil end
  local ok, path = pcall(function()
    return require("src.pokemon.Sprites").path(game.data, mon.species, "front", { mon = mon })
  end)
  if not (ok and type(path) == "string") then return nil end
  local okImg, img = pcall(love.graphics.newImage, path)
  return okImg and img or nil
end

local images = {}
local function image(path)
  if not path then return nil end
  if images[path] ~= nil then return images[path] or nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  images[path] = ok and img or false
  return ok and img or nil
end

-- a fresh cut-in's state, without pushing anything (the check drives this)
function M.new(art, mon, gender)
  local self = setmetatable({}, M)
  self.art, self.mon = art, mon
  self.female = gender == "girl" or gender == 1 or gender == "female"
  self.state, self.subState, self.frame, self.tick = 0, 0, 0, 0
  -- CutIn_InitSpriteResources: CutIn_SetWindowSize(0, 192, 1, 192)
  self.x1, self.y1, self.x2, self.y2 = 0, 192, 1, 192
  self.windowOn = true
  self.sprites = false
  self.monX, self.monY = 296, 96
  self.playerX, self.playerY = 128, 96
  self.playerAnimating, self.playerAge = false, 0
  self.forceDrawPlayer, self.playerShown = false, false
  self.playerTask = false
  self.wind = {}
  self.cries = 0
  return self
end

local STATES = {}

STATES[0] = function(s) s.state = 1 return false end
STATES[1] = function(s)
  -- resourceSourcesFreed: the transfer is the vblank after state 0's frame
  if s.frame < 1 then return false end
  s.sprites = true
  s.wind = {}
  for _, w in ipairs(M.WIND) do
    for copy = 0, 1 do
      s.wind[#s.wind + 1] = { x = w[1] + copy * 256, y = w[2], dx = w[3], priority = w[4], anim = w[5], shown = false }
    end
  end
  s.state = 2
  return true
end
STATES[2] = function(s)
  s.playerTask = true
  s.delta = -64
  s.x1, s.x2, s.y1, s.y2 = 254, 255, 95, 97
  s.state = 3
  return false
end
STATES[3] = function(s)
  s.x1 = s.x1 + s.delta
  if s.x1 <= 0 then s.x1, s.delta, s.state = 0, 2, 4 end
  return false
end
STATES[4] = function(s)
  s.y1, s.y2 = s.y1 - s.delta, s.y2 + s.delta
  s.delta = math.min(s.delta + 2, 32)
  if s.y1 < 56 then s.y1 = 56 end
  if s.y2 > 136 then s.y2 = 136 end
  if s.y1 == 56 and s.y2 == 136 then
    s.playerAnimating = true
    s.state = 5
  end
  return false
end
STATES[5] = function(s)
  s.subState = s.subState + 1
  if s.subState >= 15 then s.subState, s.monDelta, s.state = 0, -64, 6 end
  return false
end
STATES[6] = function(s)
  local x = s.monX + s.monDelta
  if x <= 160 then x, s.state = 192, 7 end
  s.monX = x
  return false
end
STATES[7] = function(s)
  s.monDelta = s.monDelta / 2
  if s.monDelta > -2 then
    s.monDelta, s.state = -2, 8
    s.cries = s.cries + 1
    if s.onCry then pcall(s.onCry) end
  end
  s.monX = s.monX + s.monDelta
  return false
end
STATES[8] = function(s)
  s.subState = s.subState + 1
  if s.subState >= 8 then s.subState, s.monDelta, s.state = 0, -1, 9 end
  return false
end
STATES[9] = function(s)
  s.monDelta = math.max(s.monDelta * 2, -64)
  s.monX = s.monX + s.monDelta
  if s.monX <= -40 then s.delta, s.state = 1, 10 end
  return false
end
STATES[10] = function(s)
  s.y1, s.y2 = s.y1 + s.delta, s.y2 - s.delta
  s.delta = math.min(s.delta + 4, 32)
  if s.y1 >= 88 then s.y1 = 88 end
  if s.y2 <= 104 then s.y2 = 104 end
  if s.y1 == 88 and s.y2 == 104 then
    s.playerTask = false -- CutIn_SetTaskUnk_254Done: the draw flag stays as it was
    s.state = 11
  end
  return false
end
STATES[11] = function(s) s.sprites = false s.state = 12 return false end
STATES[12] = function(s) s.windowOn = false s.state = 13 return false end
STATES[13] = function(s) s.finished = true return false end

-- one field frame (SysTask_CutIn)
function M:step()
  repeat local again = STATES[self.state](self) until not again
  if self.sprites then
    -- the OverworldAnimManagers: the streaks and the player's show / hide
    for _, w in ipairs(self.wind) do
      w.x = (w.x + w.dx) % 512
      w.shown = (w.y - 2) >= self.y1 and (w.y - 2) <= self.y2 and (w.y + 2) >= self.y1 and (w.y + 2) <= self.y2
    end
    if self.playerTask then
      self.playerShown = self.forceDrawPlayer
        or ((self.playerY - 8) >= self.y1 and (self.playerY + 8) <= self.y2)
    end
    -- SpriteList_Update: the player's animation, one unit a frame
    if self.playerAnimating then self.playerAge = self.playerAge + 1 end
  end
  self.frame = self.frame + 1
end

-- the field frames the whole cut-in takes (for the check)
function M.length(art)
  local s = M.new(art, nil, nil)
  local n = 0
  while not s.finished and n < 1000 do s:step() n = n + 1 end
  return n, s
end

-- push it over the field; onDone when the script may go on. False when there
-- is no art in this cache, or no picture of the Pokemon.
function M.show(game, mon, onDone, gender)
  if not (game and game.stack) then return false end
  local art = M.art(game.data)
  if not (art and art.bg and art.male) then return false end
  local sprite = frontSprite(game, mon)
  if not sprite then return false end
  if gender == nil then
    gender = game.save and game.save.player and game.save.player.gender
  end
  local self = M.new(art, mon, gender)
  self.game, self.sprite, self.onDone = game, sprite, onDone
  self.onCry = function()
    local species = mon and mon.species
    if species then require("src.core.Sound").playCry(game.data, species) end
  end
  game.stack:push(self)
  return true
end

function M:update()
  self.tick = self.tick + 1
  if self.tick % M.TICKS_PER_FRAME == 0 then self:step() end
  if self.finished and not self.popped then
    self.popped = true
    if self.game and self.game.stack then self.game.stack:pop() end
    if self.onDone then self.onDone() end
  end
end

function M:keypressed() end

-- THE FIELD'S SURFACE, ASKED FOR. Game:_draw centres any state without a
-- uiSize as Game Boy coordinates (160 x 144) inside the field's 256 x 192, so
-- the cut-in drew at (+48, +24): the band started a fifth of the way across
-- and its bottom rows hung below the window. Gen3FieldMove asks the same way.
function M:uiSize()
  return require("src.ui.Theme").uiSize()
end

local function drawCell(rec, index, x, y)
  local c = rec and rec.cells and rec.cells[index]
  local img = c and image(c.path)
  if not img then return end
  -- OAM x is nine bits: 256..511 is the left edge's negative side
  local oamX = math.floor(x + c.x) % 512
  if oamX >= 256 then oamX = oamX - 512 end
  love.graphics.draw(img, oamX, math.floor(y + c.y))
end

function M:playerCell()
  local rec = self.female and self.art.female or self.art.male
  local anim = rec and rec.anims and rec.anims[6]
  local frames = anim and anim.frames
  if not frames then return rec, 6 end
  local cell = require("src.import.Gen4CellAnim").at(frames, self.playerAge)
  return rec, cell
end

function M:draw()
  if not self.windowOn then return end
  local g = love.graphics
  -- the field's own 256 x 192 frame (the area sign and the text box are
  -- drawn in it too), not Theme.uiSize's surface
  local ox = 0
  local x1, y1, x2, y2 = math.floor(self.x1), math.floor(self.y1), math.floor(self.x2), math.floor(self.y2)
  if x2 <= x1 or y2 <= y1 then return end
  g.push()
  g.translate(ox, 0)
  local sx, sy = g.transformPoint(x1, y1)
  local ex, ey = g.transformPoint(x2, y2)
  local prev = { g.getScissor() }
  g.intersectScissor(math.floor(sx), math.floor(sy), math.max(0, math.floor(ex - sx)), math.max(0, math.floor(ey - sy)))
  -- inside W0: BG3 (and the backdrop behind its colour 0), then the OBJs
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", x1, y1, x2 - x1, y2 - y1)
  g.setColor(1, 1, 1, 1)
  local bg = image(self.art.bg)
  if bg then g.draw(bg, 0, 0) end
  if self.sprites then
    -- back to front by list priority: streaks 0x85, player 131, mon 129, streaks 0x80
    for _, w in ipairs(self.wind) do
      if w.shown and w.priority == 0x85 then drawCell(self.art.wind, w.anim, w.x, w.y) end
    end
    if self.playerShown then
      local rec, cell = self:playerCell()
      drawCell(rec, cell, self.playerX, self.playerY)
    end
    if self.sprite then
      local mc = self.art.monCell or { x = -40, y = -40 }
      g.draw(self.sprite, math.floor(self.monX + mc.x), math.floor(self.monY + mc.y))
    end
    for _, w in ipairs(self.wind) do
      if w.shown and w.priority == 0x80 then drawCell(self.art.wind, w.anim, w.x, w.y) end
    end
  end
  if prev[1] then g.setScissor(prev[1], prev[2], prev[3], prev[4]) else g.setScissor() end
  g.pop()
  pcall(function()
    require("src.render.PaletteFX").markTrueColor(ox + x1, y1, x2 - x1, y2 - y1)
  end)
  g.setColor(1, 1, 1, 1)
end

return M
