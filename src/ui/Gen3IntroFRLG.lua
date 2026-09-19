-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FIRERED'S OWN BOOT INTRO, run as the cartridge runs it: a frame-by-frame
-- simulation of pret's intro.c state machines, sprite callbacks and tasks,
-- drawing the art RomExtractorGen3:extractFireRedIntro pulls out of the ROM.
--
-- An earlier version drew each scene as a function of elapsed time with
-- hand-tuned motion. Reported from play: the logo looked broken, Gengar was a
-- cropped corner of his own layer, and Nidorino smeared across the screen.
-- Every one of those was a reconstruction that was wrong in its details, so
-- the reconstruction is gone: positions, speeds, sine arcs and random seeds
-- below are the source's own numbers, and each block names the function it
-- mirrors.
--
-- TWO GBA WINDOWS SHAPE THE PICTURE and are easy to miss. IntroCB_GF_OpenWindow
-- turns on WIN1 over rows 32..128 and nothing ever turns it off, so the whole
-- intro after the logo opens is letterboxed -- sprites included. During
-- Scene 3's entrance WIN0 additionally hides the Gengar layer on the left
-- half of that strip until he has scrolled halfway in.
--
-- START, A or B skips it (Task_CallIntroCallback).

local Assets = require("src.render.Assets")
local Music = require("src.core.Music")

local Gen3IntroFRLG = {}
Gen3IntroFRLG.__index = Gen3IntroFRLG
Gen3IntroFRLG.isOpaque = true

local W, H = 240, 160
local FIRE_RED_INTRO = "SONG_144" -- MUS_NEW_GAME_INTRO (0x0144)
local WIN_TOP, WIN_BOTTOM = 32, 128

-- gSineTable: sin(i * pi / 128) in 8.8 fixed point
local SIN = {}
for i = 0, 255 do
  local v = math.sin(i * math.pi / 128) * 256
  SIN[i] = v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)
end
local function sine(i) return SIN[i % 256] end

-- C integer helpers
local function asr(v, n) return math.floor(v / 2 ^ n) end        -- >> on signed
local function cdiv(a, b)                                            -- truncating /
  local q = a / b
  return q >= 0 and math.floor(q) or -math.floor(-q)
end
local function cmod(a, b) return a - cdiv(a, b) * b end
local function s16(v)
  v = v % 65536
  return v >= 32768 and v - 65536 or v
end
-- u32 multiply, exact (a double cannot hold 1103515245 * 2^32)
local function mul32(a, b)
  local alo, ahi = a % 65536, math.floor(a / 65536) % 65536
  local blo, bhi = b % 65536, math.floor(b / 65536) % 65536
  local lo = alo * blo
  local mid = (alo * bhi + ahi * blo) % 65536
  return (lo + mid * 65536) % 4294967296
end
local RAND_MULT = 1103515245
local function isoRandomize(v) return (mul32(RAND_MULT, v) + 24691) % 4294967296 end

-- ---------------------------------------------------------------------------
-- sprite animations: ANIMCMD_FRAME lists as { frame, duration } rows
-- ---------------------------------------------------------------------------

local ANIM = {
  sparkleLoop = { loop = true, { 0, 4 }, { 1, 4 }, { 2, 4 }, { 3, 4 } },
  sparkleOnce = { { 0, 4 }, { 1, 4 }, { 2, 4 }, { 3, 4 } },
  sparkleBig  = { { 0, 8 }, { 1, 8 }, { 2, 8 }, { 3, 8 } },
  dust        = { { 0, 10 }, { 1, 10 }, { 2, 10 }, { 3, 8 } },
  swipe       = { { 0, 8 }, { 1, 4 } },
}

local function startAnim(s, name)
  s.anim, s.animIdx, s.animTime, s.animEnded = ANIM[name], 1, 0, false
  s.frame = s.anim[1][1]
end

local function stepAnim(s)
  local a = s.anim
  if not a or s.animEnded then return end
  s.animTime = s.animTime + 1
  if s.animTime >= math.max(1, a[s.animIdx][2]) then
    s.animTime = 0
    if s.animIdx < #a then
      s.animIdx = s.animIdx + 1
    elseif a.loop then
      s.animIdx = 1
    else
      s.animEnded = true
      return
    end
    s.frame = a[s.animIdx][1]
  end
end

-- ---------------------------------------------------------------------------
-- construction / lifecycle
-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:uiSize() return W, H end
function Gen3IntroFRLG:wantsFillScale() return true end

function Gen3IntroFRLG:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen3IntroFRLG:enter()
  local data = self.game and self.game.data
  local song = data and Music.special(data, "intro")
  local songs = data and data.audio and data.audio.songs
  -- The generic Gen 3 role table uses Emerald's song numbers; FireRed's
  -- intro is MUS_NEW_GAME_INTRO (0x0144). Keep a valid role override, but
  -- fall back to FireRed's own ID when that Emerald mapping is absent/stale.
  if not (song and songs and songs[song]) then song = FIRE_RED_INTRO end
  if songs and songs[song] then
    pcall(Music.play, data, song)
  end
end

function Gen3IntroFRLG.new(game, onDone)
  local self = setmetatable({}, Gen3IntroFRLG)
  self.game = game
  self.onDone = onDone
  self.finished = false
  self.assets = ((game.data.constants or {}).gen3FRLGIntro or {}).images or {}
  self.imageCache = {}
  self:startCard()
  return self
end

-- ---------------------------------------------------------------------------
-- THE PORT'S OWN CARD, before the cartridge's GAME FREAK logo.
--
-- Emerald opens on this engine's studio card; FireRed opens on one that also
-- says who ported it.  It names the engine and the port and says it is a fan
-- project -- it does not borrow any GAME FREAK or Nintendo mark, and every
-- word is overridable (data.field.boot.studio: credit / author / portAuthor /
-- year / notice) so a mod can put its own name here.
-- ---------------------------------------------------------------------------
local CARD_IN, CARD_HOLD, CARD_OUT = 20, 110, 20

function Gen3IntroFRLG:startCard()
  self.phase = "card"
  self.cardFrame = 0
end

function Gen3IntroFRLG:stepCard()
  self.cardFrame = self.cardFrame + 1
  if self.cardFrame >= CARD_IN + CARD_HOLD + CARD_OUT then self:startGameFreak() end
end

function Gen3IntroFRLG:drawCard()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  local f = self.cardFrame or 0
  local alpha = 1
  if f < CARD_IN then alpha = f / CARD_IN
  elseif f > CARD_IN + CARD_HOLD then alpha = 1 - (f - CARD_IN - CARD_HOLD) / CARD_OUT end
  local boot = (self.game.data.field or {}).boot or {}
  local studio = boot.studio or {}
  local Font = require("src.render.Font")
  local function centre(text, y, r, gg, b)
    g.setColor(1, 1, 1, math.max(0, alpha))
    Font.pushStyle({ text = { r or 1, gg or 1, b or 1 }, shadow = { 0.25, 0.25, 0.3 } })
    Font.draw(text, math.floor((W - Font.width(text)) / 2), y)
    Font.popStyle()
  end
  centre(studio.year or "2026", 36, 0.72, 0.72, 0.72)
  centre(studio.credit or "Gen2Recomped", 56, 1, 0.42, 0.30)
  centre("engine by " .. (studio.author or "UNDERdecodedHD"), 72)
  centre("FireRed port by " .. (studio.portAuthor or "Tranzue"), 92)
  local faced = Font.pushFace and Font.pushFace("small")
  centre(studio.notice or "A fan project. Not affiliated with", 124, 0.6, 0.6, 0.6)
  centre(studio.notice2 or "Nintendo, GAME FREAK or The Pokemon Company.", 136, 0.6, 0.6, 0.6)
  if faced and Font.popFace then Font.popFace() end
  g.setColor(1, 1, 1, 1)
end

function Gen3IntroFRLG:finish()
  if self.finished then return end
  self.finished = true
  pcall(Music.stop)
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen3IntroFRLG:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b")
     or input:wasPressed("start") then
    self:finish()
    return
  end
  if self.phase == "card" then self:stepCard()
  elseif self.phase == "gf" then self:stepGameFreak()
  elseif self.phase == "scene1" then self:stepScene1()
  elseif self.phase == "scene2" then self:stepScene2()
  elseif self.phase == "scene3" then self:stepScene3()
  end
  if self.phase == "done" then self:finish() end
end

-- ---------------------------------------------------------------------------
-- drawing helpers
-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:piece(key)
  local rec = self.assets[key]
  if type(rec) ~= "table" or type(rec.path) ~= "string" then return nil end
  local image = self.imageCache[rec.path]
  if image == nil then
    local ok, img = pcall(Assets.image, rec.path)
    image = ok and img or false
    if image then image:setFilter("nearest", "nearest") end
    self.imageCache[rec.path] = image
  end
  if not image then return nil end
  return image, rec
end

-- A wrapping background layer: screen (x, y) inside the rect shows source
-- ((x + scrollX) mod width, (y + scrollY) mod height), like a GBA BG with its
-- scroll registers set.
function Gen3IntroFRLG:drawLayer(key, scrollX, scrollY, rx, ry, rw, rh)
  local image = self:piece(key)
  if not image then return end
  local iw, ih = image:getDimensions()
  rx, ry = rx or 0, ry or 0
  rw, rh = rw or W, rh or H
  local sx0 = math.floor(scrollX or 0)
  local sy0 = math.floor(scrollY or 0)
  local y = ry
  while y < ry + rh do
    local srcY = (y + sy0) % ih
    local hChunk = math.min(ih - srcY, ry + rh - y)
    local x = rx
    while x < rx + rw do
      local srcX = (x + sx0) % iw
      local wChunk = math.min(iw - srcX, rx + rw - x)
      local quad = love.graphics.newQuad(srcX, srcY, wChunk, hChunk, iw, ih)
      love.graphics.draw(image, quad, x, y)
      x = x + wChunk
    end
    y = y + hChunk
  end
end

-- One frame of a sprite sheet, positioned by its CENTRE the way an OAM sprite
-- is, optionally scaled about an anchor given relative to its top-left.
function Gen3IntroFRLG:drawSprite(key, frame, cx, cy, scale, ax, ay)
  local image, rec = self:piece(key)
  if not image or not rec.cols then return end
  local fw, fh = rec.cols * 8, rec.rows * 8
  local n = math.max(1, rec.frames or 1)
  local iw, ih = image:getDimensions()
  local quad = love.graphics.newQuad((math.floor(frame or 0) % n) * fw, 0,
                                     fw, fh, iw, ih)
  local left, top = math.floor(cx) - fw / 2, math.floor(cy) - fh / 2
  scale = scale or 1
  if scale == 1 then
    love.graphics.draw(image, quad, left, top)
  else
    ax, ay = ax or fw / 2, ay or fh / 2
    love.graphics.draw(image, quad, left + ax, top + ay, 0, scale, scale, ax, ay)
  end
end

local function letterbox()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, W, WIN_TOP)
  love.graphics.rectangle("fill", 0, WIN_BOTTOM, W, H - WIN_BOTTOM)
  love.graphics.setColor(1, 1, 1, 1)
end

local function overlay(r, g, b, a)
  if a <= 0 then return end
  love.graphics.setColor(r, g, b, math.min(1, a))
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1, 1)
end

-- BeginNormalPaletteFade's length: a negative delay adds to the step size,
-- a positive one waits that many extra frames between steps of 2.
local function fadeFrames(delay)
  if delay < 0 then return math.ceil(16 / (2 - delay)) end
  return 8 * (delay + 1)
end

-- ===========================================================================
-- THE GAME FREAK SCENE (IntroCB_GF_OpenWindow .. IntroCB_GF_RevealLogo)
-- ===========================================================================

local TEXT_SPARKLE_COORDS = {
  { 72, 80 }, { 136, 74 }, { 168, 80 }, { 120, 80 }, { 104, 86 },
  { 88, 74 }, { 184, 74 }, { 56, 86 }, { 152, 86 },
}

function Gen3IntroFRLG:startGameFreak()
  self.phase = "gf"
  self.gf = { cb = "open", state = 0, timer = 0, winHalf = 0,
              textAlpha = 0, textShown = false, logoBlitted = false,
              sprites = {}, tasks = {}, blend = nil, yMod = 0 }
end

-- StartBlendTask: EVA/EVB walk to their targets over 2*step frames
local function startBlend(g, from, to, step, target)
  g.blend = { from = from, to = to, frames = step * 2, t = 0, target = target }
end

local function blendValue(g)
  local b = g.blend
  if not b then return nil end
  return b.from + (b.to - b.from) * math.min(1, b.t / b.frames)
end

function Gen3IntroFRLG:gfCreateStarSparkle(x, y, random)
  local g = self.gf
  local xMod = (random % 8) + 2            -- sStarSparklesXmodMask = 7
  local yMod = g.yMod
  g.yMod = g.yMod + 1
  if g.yMod > 3 then g.yMod = -3 end
  x, y = x + xMod, y + yMod
  if x > 0 and x < W then
    local s = { kind = "starSparkle", x = x, y = y, baseX = x * 32, baseY = y * 32,
                speedX = xMod, speedY = yMod, timer = 0 }
    startAnim(s, "sparkleLoop")
    g.sprites[#g.sprites + 1] = s
  end
end

function Gen3IntroFRLG:stepGameFreakSprites()
  local g = self.gf
  -- tasks first, as the task loop runs before the sprite callbacks
  for _, t in ipairs(g.tasks) do
    if not t.dead then
      if t.kind == "nameSmall" then
        t.timer = t.timer + 1
        if t.timer > 6 then
          t.timer = 0
          local c = TEXT_SPARKLE_COORDS[t.idx + 1]
          local s = { kind = "nameSparkle", x = c[1], y = c[2], baseY = c[2] * 16,
                      animTimer = 120, numLoops = t.loops, state = 0, destroy = 0 }
          startAnim(s, "sparkleOnce")
          g.sprites[#g.sprites + 1] = s
          t.idx = t.idx + 1
          if t.idx >= #TEXT_SPARKLE_COORDS then
            t.loops = t.loops + 1
            if t.loops > 1 then t.dead = true else t.idx = 0 end
          end
        end
      elseif t.kind == "nameBig" then
        if t.timer == 0 then
          local c = TEXT_SPARKLE_COORDS[t.idx + 1]
          t.idx = t.idx + 4
          if t.idx >= #TEXT_SPARKLE_COORDS then t.idx = t.idx - #TEXT_SPARKLE_COORDS end
          local s = { kind = "bigSparkle", x = c[1], y = c[2] }
          startAnim(s, "sparkleBig")
          g.sprites[#g.sprites + 1] = s
          t.count = t.count + 1
          if t.count >= #TEXT_SPARKLE_COORDS then t.dead = true end
        end
        t.timer = t.timer + 1
        if t.timer > 9 then t.timer = 0 end
      end
    end
  end

  local keep = {}
  for _, s in ipairs(g.sprites) do
    stepAnim(s)
    if s.kind == "star" then                                   -- SpriteCB_Star
      s.baseX, s.baseY = s.baseX - 96, s.baseY + 16
      s.sinIdx = s.sinIdx + 48
      s.x, s.y = asr(s.baseX, 4), asr(s.baseY, 4)
      s.y2 = asr(sine(asr(s.sinIdx, 4) + 64), 5)
      s.timer = s.timer + 1
      if s.timer % 8 ~= 0 then
        s.seed = isoRandomize(s.seed)
        self:gfCreateStarSparkle(s.x, s.y + s.y2, math.floor(s.seed / 65536))
      end
      if s.x < -8 then s.dead = true end
    elseif s.kind == "starSparkle" then                        -- SpriteCB_SparklesSmall_Star
      s.baseX, s.baseY = s.baseX + s.speedX, s.baseY + s.speedY
      s.timer = s.timer + 1
      s.x = math.floor((s.baseX % 65536) / 32)
      s.y = asr(s.baseY, 5)
      if s.timer > 90 then
        s.invisible = not s.invisible
        if s.timer > 120 then s.dead = true end
      end
      if s.y < 0 or s.y > H then s.dead = true end
    elseif s.kind == "nameSparkle" then                        -- SpriteCB_SparklesSmall_Name
      if s.animTimer > 0 then
        s.animTimer = s.animTimer - 1
        s.baseY = s.baseY + 1
        s.y = asr(s.baseY, 4)
        if s.y > 86 then s.y, s.baseY = 74, 74 * 16 end
        if s.animEnded then
          if s.state == 0 then
            s.x = s.x + 26
            if s.x > 188 then s.x, s.state = 376 - s.x, 1 end
          else
            s.x = s.x - 26
            if s.x < 52 then s.x, s.state = 104 - s.x, 0 end
          end
          startAnim(s, "sparkleOnce")
        end
      else
        if s.numLoops ~= 0 then s.dead = true end
        if s.animEnded then startAnim(s, "sparkleLoop") end
        s.baseY = s.baseY + 4
        s.y = asr(s.baseY, 4)
        s.destroy = s.destroy + 1
        if s.destroy > 50 then s.dead = true end
      end
    elseif s.kind == "bigSparkle" then                         -- SpriteCB_SparklesBig
      if s.animEnded then s.dead = true end
    end
    if not s.dead then keep[#keep + 1] = s end
  end
  g.sprites = keep
end

function Gen3IntroFRLG:stepGameFreak()
  local g = self.gf
  if g.blend then g.blend.t = g.blend.t + 1 end
  local blendActive = g.blend and g.blend.t < g.blend.frames
  local function go(cb) g.cb, g.state, g.timer = cb, 0, 0 end

  if g.cb == "open" then                                       -- IntroCB_GF_OpenWindow
    if g.state < 2 then
      g.state = g.state + 1
    else
      g.winHalf = math.min(48, g.winHalf + 8)
      if g.winHalf == 48 then go("star") end
    end
  elseif g.cb == "star" then                                   -- IntroCB_GF_Star
    if g.state == 0 then
      g.sprites[#g.sprites + 1] = { kind = "star", baseX = 248 * 16, baseY = 55 * 16,
                                    x = 248, y = 55, y2 = 0, sinIdx = 0, timer = 0,
                                    seed = 354128453 }
      g.state, g.timer = 1, 0
    elseif g.state == 1 then
      g.timer = g.timer + 1
      if g.timer == 30 then
        g.tasks[#g.tasks + 1] = { kind = "nameSmall", timer = 0, idx = 0, loops = 0 }
        g.timer, g.state = 0, 2
      end
    else
      g.timer = g.timer + 1
      if g.timer == 90 then go("name") end
    end
  elseif g.cb == "name" then                                   -- IntroCB_GF_RevealName
    if g.state == 0 then
      g.tasks[#g.tasks + 1] = { kind = "nameBig", timer = 0, idx = 0, count = 0 }
      g.timer, g.state = 0, 1
    elseif g.state == 1 then
      g.timer = g.timer + 1
      if g.timer >= 40 then g.state = 2 end
    elseif g.state == 2 then
      startBlend(g, 0, 16, 48, "text")
      g.state = 3
    elseif g.state == 3 then
      g.textShown = true
      g.state = 4
    elseif g.state == 4 then
      if not blendActive then g.blend, g.timer, g.state = nil, 0, 5 end
    else
      g.timer = g.timer + 1
      if g.timer > 50 then go("logo") end
    end
  elseif g.cb == "logo" then                                   -- IntroCB_GF_RevealLogo
    if g.state == 0 then
      startBlend(g, 0, 16, 16, "logo")
      g.state = 1
    elseif g.state == 1 then
      g.logoSprite = true
      g.state = 2
    elseif g.state == 2 then
      if not blendActive then g.logoBlitted, g.state = true, 3 end
    elseif g.state == 3 then
      g.logoSprite = false
      g.presents = true                                        -- REVISION >= 1
      g.blend, g.timer, g.state = nil, 0, 4
    elseif g.state == 4 then
      g.timer = g.timer + 1
      if g.timer > 90 then
        startBlend(g, 16, 0, 20, "out")
        g.state = 5
      end
    elseif g.state == 5 then
      if not blendActive then g.textShown, g.state = false, 6 end
    elseif g.state == 6 then
      g.sprites, g.presents = {}, false                        -- ResetSpriteData
      g.blend, g.timer, g.state = nil, 0, 7
    else
      g.timer = g.timer + 1
      if g.timer > 20 then self:startScene1() end
    end
  end
  if self.phase == "gf" then self:stepGameFreakSprites() end
end

function Gen3IntroFRLG:drawGameFreak()
  local g = self.gf
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local top, bottom = 80 - g.winHalf, 80 + g.winHalf
  if bottom <= top then return end
  -- everything below is inside WIN1; draw it, then black out the rest
  love.graphics.setColor(1, 1, 1, 1)
  self:drawLayer("gfBg", 0, 0, 0, 0, W, H)

  local bv = blendValue(g)
  local textA = 0
  if g.textShown then
    textA = 1
    if g.blend and (g.blend.target == "text" or g.blend.target == "out") then
      textA = bv / 16
    end
  end
  if textA > 0 then
    love.graphics.setColor(1, 1, 1, textA)
    self:drawSprite("gfText", 0, 48 + 72, 72 + 8)
    if g.logoBlitted then self:drawSprite("gfArt", 0, 120, 70) end
  end
  if g.logoSprite then
    love.graphics.setColor(1, 1, 1, g.blend and g.blend.target == "logo" and bv / 16 or 1)
    self:drawSprite("gfArt", 0, 120, 70)
  end
  if g.presents then
    local a = (g.blend and g.blend.target == "out") and bv / 16 or 1
    love.graphics.setColor(1, 1, 1, a)
    self:drawSprite("presents", 0, 104, 108)
    self:drawSprite("presents", 1, 136, 108)
  end
  love.graphics.setColor(1, 1, 1, 1)
  for _, s in ipairs(g.sprites) do
    if not s.invisible then
      if s.kind == "star" then
        self:drawSprite("star", 0, s.x, s.y + s.y2)
      elseif s.kind == "bigSparkle" then
        self:drawSprite("sparkleBig", s.frame, s.x, s.y)
      else
        self:drawSprite("sparkleSmall", s.frame, s.x, s.y)
      end
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, W, top)
  love.graphics.rectangle("fill", 0, bottom, W, H - bottom)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ===========================================================================
-- SCENE 1: the grass (IntroCB_Scene1)
-- ===========================================================================

function Gen3IntroFRLG:startScene1()
  self.phase = "scene1"
  self.s1 = { state = 0, timer = 0, grassTimer = 0, grassFrame = 0,
              zoomTimer = 0, zoomFrame = 0, zooming = false, fade = 1, fadeStep = 0 }
end

function Gen3IntroFRLG:stepScene1()
  local s = self.s1
  -- Scene1_Task_AnimateGrass: a new pose every 6 frames
  s.grassTimer = s.grassTimer + 1
  if s.grassTimer > 5 then
    s.grassTimer = 0
    s.grassFrame = (s.grassFrame + 1) % 3
  end
  if s.zooming then                                            -- Scene1_Task_BgZoom
    s.zoomTimer = s.zoomTimer + 1
    if s.zoomTimer > 3 then
      s.zoomTimer = 0
      if s.zoomFrame < 2 then s.zoomFrame = s.zoomFrame + 1 end
    end
  end
  if s.state < 3 then
    s.state = s.state + 1                                      -- load + fade start
    if s.state == 3 then s.fadeStep = 1 / fadeFrames(-2) end
  elseif s.state == 3 then
    s.fade = math.max(0, s.fade - s.fadeStep)
    if s.fade <= 0 then s.timer, s.state = 0, 4 end
  else
    s.timer = s.timer + 1
    if s.timer == 20 then s.zooming = true end
    if s.timer >= 30 then self:startScene2() end
  end
end

function Gen3IntroFRLG:drawScene1()
  local s = self.s1
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1, 1)
  self:drawLayer("scene1Bg", 0, s.zoomFrame * 128, 0, 0, W, H)
  self:drawLayer("scene1Grass", 0, s.grassFrame * 128, 0, 0, W, H)
  overlay(1, 1, 1, s.fade)
  letterbox()
end

-- ===========================================================================
-- SCENE 2: the forest pan, then the close-up (IntroCB_Scene2)
-- ===========================================================================

function Gen3IntroFRLG:startScene2()
  self.phase = "scene2"
  self.s2 = { state = 0, timer = 0, bgX = 0, plantsX = 0, close = false,
              gengarY = 0x1CE00 / 256, nidoY = 0x2800 / 256, fade = 1 }
end

function Gen3IntroFRLG:stepScene2()
  local s = self.s2
  if not s.close and s.state >= 2 then                         -- Scene2_Task_PanForest
    s.bgX = s.bgX - 0xE0 / 256
    s.plantsX = s.plantsX + 0x110 / 256
  end
  if s.close then                                              -- Scene2_Task_PanMons
    s.gengarY = s.gengarY + 0x20 / 256
    s.nidoY = s.nidoY - 0x24 / 256
  end
  if s.state < 2 then
    s.state = s.state + 1
  elseif s.state == 2 then
    s.fade = math.max(0, s.fade - 1 / fadeFrames(-2))
    if s.fade <= 0 then s.timer, s.state = 0, 3 end
  elseif s.state == 3 then
    s.timer = s.timer + 1
    if s.timer >= 60 then s.close, s.timer, s.state = true, 0, 4 end
  else
    s.timer = s.timer + 1
    if s.timer >= 61 then self:startScene3() end
  end
end

function Gen3IntroFRLG:drawScene2()
  local s = self.s2
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1, 1)
  if not s.close then
    -- back to front: forest (prio 3), the two OAM mons (prio 1), plants (prio 0)
    self:drawLayer("scene2Bg", s.bgX, 0)
    self:drawSprite("scene2Gengar", 0, 72, 80)
    self:drawSprite("scene2Nidorino", 0, 168, 80)
    self:drawLayer("scene2Plants", s.plantsX, 0)
  else
    self:drawLayer("scene2Bg", 0, 256)
    self:drawLayer("scene2GengarClose", 0, s.gengarY)
    self:drawLayer("scene2NidorinoClose", 0, s.nidoY)
  end
  overlay(1, 1, 1, s.fade)
  letterbox()
end

-- ===========================================================================
-- SCENE 3: the entrance and the fight
-- (IntroCB_Scene3_Entrance / IntroCB_Scene3_Fight and their tasks)
-- ===========================================================================

local NIDO = { normal = 0, cry = 1, crouch = 2, hop = 3, attack = 4 }

function Gen3IntroFRLG:startScene3()
  self.phase = "scene3"
  self.s3 = {
    cb = "entrance", state = 0, timer = 0,
    bgX = 0, bgSlow = false, bgScrolling = false,
    gengarShown = false, gengarX = 0x1800, gengarY = 496, win0 = true,
    bounce = nil, enter = nil, attack = nil, attackLanded = false,
    nido = nil, grass = nil, fx = {}, backPieces = false,
    white = 0, whiteStep = 0, bgSolidWhite = false, black = 0, blackStep = 0,
    zoom = nil,
  }
end

-- Scene3_StartNidorinoEntrance(sprite, 0, 180, 52)
local function nidoEnter(n)
  n.cb = "enter"
  n.sX, n.speed, n.target, n.timer = 0, math.floor((180 * 16) / 52), 180, 0
  n.x, n.y = 0, 100
end

local function nidoHop(n, time, targetX, heightShift)
  n.cb, n.state = "hop", 0
  n.airTime = time
  n.offX = n.x2 * 16
  n.speedX = cdiv(targetX * 16, time)
  n.sinIdx = 0
  n.speedY = math.floor(0x800 / time)
  n.timer = 0
  n.heightShift = heightShift
  n.anim = NIDO.crouch
end

function Gen3IntroFRLG:createDust(x, y, seed)                  -- CreateNidorinoRecoilDustSprites
  local s3 = self.s3
  for i = 0, 1 do
    local d = { kind = "dust", x = x - 22, y = y + 24, state = 0,
                speedX = cmod(seed, 13) + 8, speedY = cmod(seed, 3), invTimer = i }
    startAnim(d, "dust")
    s3.fx[#s3.fx + 1] = d
    seed = s16(mul32(seed % 65536, RAND_MULT) % 65536)
  end
end

function Gen3IntroFRLG:stepNidorino()
  local n = self.s3.nido
  if not n then return end
  if n.cb == "enter" then                                      -- Scene3_SpriteCB_NidorinoEnter
    n.timer = n.timer + 1
    if n.timer >= 40 and n.speed > 1 then n.speed = n.speed - 1 end
    n.sX = n.sX + n.speed
    n.x = asr(n.sX, 4)
    if n.x >= n.target then n.x, n.cb = n.target, nil end
  elseif n.cb == "cry" then                                    -- SpriteCB_NidorinoCry
    if n.state == 0 then
      n.timer = n.timer + 1
      if n.timer > 8 then n.anim, n.y2, n.state = NIDO.cry, 0, 1 end
    elseif n.state == 1 then
      pcall(function()
        require("src.core.Sound").playCry(self.game.data, "NIDORINO")
      end)
      n.timer, n.state = 0, 2
    else
      n.bounce = n.bounce + 1
      if n.bounce > 1 then
        n.bounce = 0
        n.y2 = (n.y2 == 0) and 1 or 0
      end
      n.timer = n.timer + 1
      if n.timer > 48 then n.anim, n.y2, n.cb = NIDO.normal, 0, nil end
    end
  elseif n.cb == "recoil" then                                 -- SpriteCB_NidorinoRecoil
    if n.state == 0 then
      n.timer = n.timer + 1
      if n.timer > 4 then n.anim, n.state = NIDO.hop, 1 end
    elseif n.state == 1 then
      n.offX = n.offX + n.speedX
      n.sinIdx = n.sinIdx + 8
      n.x2 = asr(n.offX, 4)
      n.y2 = -asr(sine(n.sinIdx) * 3, 5)
      n.slow = n.slow + 1
      if n.slow > 0 then n.slow, n.speedX = 0, n.speedX - 1 end
      n.land = n.land + 1
      if n.land > 15 then
        n.anim, n.timer, n.seed, n.speedX, n.state = NIDO.crouch, 0, 0x4757, 28, 2
      end
    elseif n.state == 2 then
      n.offX = n.offX + n.speedX
      n.x2 = asr(n.offX, 4)
      n.timer = n.timer + 1
      if n.timer > 6 then
        self:createDust(n.x + n.x2, n.y + n.y2, n.seed)
        n.seed = s16(mul32(n.seed % 65536, RAND_MULT) % 65536)
      end
      if n.timer > 12 then n.anim, n.timer, n.state = NIDO.normal, 0, 3 end
    else
      n.timer = n.timer + 1
      if n.timer > 16 then nidoHop(n, 16, -n.x2, 4) end
    end
  elseif n.cb == "hop" then                                    -- SpriteCB_NidorinoHop
    if n.state == 0 then
      n.timer = n.timer + 1
      if n.timer > 4 then n.anim, n.timer, n.state = NIDO.hop, 0, 1 end
    elseif n.state == 1 then
      n.airTime = n.airTime - 1
      if n.airTime ~= 0 then
        n.offX = n.offX + n.speedX
        n.sinIdx = n.sinIdx + n.speedY
        n.x2 = asr(n.offX, 4)
        n.y2 = -asr(sine(asr(n.sinIdx, 4)), n.heightShift)
      else
        n.x2 = s16(math.floor((n.offX % 65536) / 16))
        n.y2 = 0
        n.anim = NIDO.crouch
        if n.heightShift == 5 then n.cb = nil
        else n.timer, n.state = 0, 2 end
      end
    else
      n.timer = n.timer + 1
      if n.timer > 4 then n.anim, n.cb = NIDO.normal, nil end
    end
  elseif n.cb == "attack" then                                 -- SpriteCB_NidorinoAttack
    if n.state == 0 then
      n.timer = n.timer + 1
      if n.timer % 2 == 1 then
        n.shake = n.shake + 1
        n.x2 = n.x2 + ((n.shake % 2 == 1) and 1 or -1)
      end
      if n.timer > 17 then n.timer, n.state = 0, 1 end
    elseif n.state == 1 then
      n.timer = n.timer + 1
      if n.timer >= 40 then n.anim, n.timer, n.shake, n.state = NIDO.attack, 0, 0, 2 end
    else
      n.timer = n.timer + n.speed
      n.x2 = -asr(n.timer, 4)
      n.y2 = -asr(sine(asr(n.timer, 4)) * 3, 4)
      if n.speed > 12 then n.speed = n.speed - 1 end
      if asr(n.timer, 4) > 63 then n.cb = nil end
    end
  end
end

function Gen3IntroFRLG:stepScene3Tasks()
  local s3 = self.s3
  local b = s3.bounce                                          -- Scene3_Task_GengarBounce
  if b and not b.paused then
    b.timer = b.timer + 1
    if b.timer >= 30 then
      b.timer = 0
      b.state = 1 - b.state
      s3.gengarY = b.state * 128 + 496
    end
  end
  local e = s3.enter                                           -- Scene3_Task_GengarEnter
  if e then
    e.moves = e.moves + 1
    if e.moves >= 40 and e.speed > 16 then e.speed = e.speed - 16 end
    s3.gengarX = s3.gengarX + e.speed
    if s3.gengarX >= 0x8000 then s3.win0 = false end
    if s3.gengarX >= 0xEF00 then s3.gengarX, s3.enter = 0xEF00, nil end
  end
  if s3.bgScrolling then                                       -- Scene3_Task_BgScroll
    s3.bgX = s3.bgX - (s3.bgSlow and 0x20 or 0x400) / 256
  end
  local a = s3.attack                                          -- Scene3_Task_GengarAttack
  if a then
    local done = false
    if a.state == 0 then
      a.frame, a.timer, a.multY, a.multX, a.state = 2, 0, 6, 32, 1
    elseif a.state == 1 then
      a.sinIdx = a.sinIdx - 2
      a.timer = a.timer + 1
      if a.timer > 15 then a.timer, a.state = 0, 2 end
    elseif a.state == 2 then
      a.timer = a.timer + 1
      if a.timer == 14 then s3.attackLanded = true end
      if a.timer > 15 then a.timer, a.state = 0, 3 end
    elseif a.state == 3 then
      a.sinIdx = a.sinIdx + 8
      a.timer = a.timer + 1
      if a.timer == 4 then
        -- Scene3_CreateGengarSwipeSprites
        local top = { kind = "swipe", key = "scene3Swipe", x = 132, y = 78 }
        startAnim(top, "swipe")
        local bottom = { kind = "swipe", bottom = true, x = 132, y = 118 }
        startAnim(bottom, "swipe")
        s3.fx[#s3.fx + 1] = top
        s3.fx[#s3.fx + 1] = bottom
        a.multY, a.multX, a.frame = 32, 48, 3
      end
      if a.timer > 7 then a.timer, a.state = 0, 4 end
    elseif a.state == 4 then
      a.sinIdx = a.sinIdx - 8
      a.timer = a.timer + 1
      if a.timer > 3 then a.frame, a.sinIdx, a.timer, a.state = 0, 64, 0, 5 end
    else
      s3.attack, done = nil, true
    end
    if not done then                                           -- Scene3_ApplyGengarAnim
      local xSub = -asr(sine(a.sinIdx + 64) * a.multX, 8)
      local ySub = a.multY - asr(sine(a.sinIdx) * a.multY, 8)
      s3.gengarY = a.frame * 128 + 496 - ySub
      s3.gengarX = a.baseX - xSub * 256
    end
  end
end

function Gen3IntroFRLG:stepScene3Sprites()
  local s3 = self.s3
  self:stepNidorino()
  local g = s3.grass                                           -- SpriteCB_Grass
  if g then
    if g.state == 1 then
      g.baseX = g.baseX - 160
      g.x = asr(g.baseX, 5)
      if g.x <= 52 then s3.bgSlow, g.state = true, 2 end
    else
      g.baseX = g.baseX - 32
      g.x = asr(g.baseX, 5)
      if g.x <= -32 then s3.grass = nil end
    end
  end
  local keep = {}
  for _, s in ipairs(s3.fx) do
    stepAnim(s)
    if s.kind == "swipe" then                                  -- SpriteCB_GengarSwipe
      s.invisible = not s.invisible
      if s.animEnded then s.dead = true end
    elseif s.kind == "dust" then                               -- SpriteCB_RecoilDust
      if s.state == 0 then s.sX, s.sY, s.state = s.x * 16, s.y * 16, 1 end
      s.sX, s.sY = s.sX - s.speedX, s.sY + s.speedY
      s.x, s.y = asr(s.sX, 4), asr(s.sY, 4)
      if s.animEnded then s.dead = true end
      s.invTimer = s.invTimer + 1
      if s.invTimer > 1 then s.invTimer, s.invisible = 0, not s.invisible end
    end
    if not s.dead then keep[#keep + 1] = s end
  end
  s3.fx = keep
  if s3.zoom and s3.zoom.t < 8 then s3.zoom.t = s3.zoom.t + 1 end
end

function Gen3IntroFRLG:stepScene3()
  local s3 = self.s3
  local n = s3.nido
  if s3.cb == "entrance" then
    if s3.state == 0 then
      s3.white, s3.state = 1, 1
    elseif s3.state == 1 then
      s3.gengarX, s3.gengarY, s3.state = 0x1800, 496, 2
    elseif s3.state == 2 then
      s3.white = 0
      s3.gengarShown = true
      s3.bounce = { paused = false, timer = 0, state = 0 }
      s3.nido = { x = 0, y = 100, x2 = 0, y2 = 0, anim = NIDO.normal }
      nidoEnter(s3.nido)
      s3.enter = { speed = 0x400, moves = 0 }
      s3.bgScrolling = true
      s3.timer, s3.state = 0, 3
    else
      s3.timer = s3.timer + 1
      if s3.timer == 16 then
        s3.grass = { x = 296, y = 112, baseX = 296 * 32, state = 1 }
      end
      if s3.nido.cb ~= "enter" and not s3.enter then
        s3.cb, s3.state, s3.timer = "fight", 0, 0
      end
    end
  else                                                         -- IntroCB_Scene3_Fight
    local st = s3.state
    local idle = n.cb == nil
    if st == 0 then
      s3.timer, s3.state = 0, 1
    elseif st == 1 then
      s3.timer = s3.timer + 1
      if s3.timer > 30 then
        n.cb, n.state, n.timer, n.bounce, n.y2 = "cry", 0, 0, 0, 3
        n.anim = NIDO.crouch
        s3.state = 2
      end
    elseif st == 2 then
      if idle then s3.timer, s3.state = 0, 3 end
    elseif st == 3 then
      s3.timer = s3.timer + 1
      if s3.timer > 30 then
        s3.bounce.paused = true
        s3.attackLanded = false
        s3.attack = { state = 0, timer = 0, sinIdx = 64, baseX = s3.gengarX,
                      frame = 0, multX = 0, multY = 0 }
        s3.timer, s3.state = 0, 4
      end
    elseif st == 4 then
      if s3.attackLanded then
        n.anim, n.state, n.timer, n.offX, n.sinIdx, n.land = NIDO.crouch, 0, 0, 0, 0, 0
        n.speedX, n.slow, n.cb = 40, 0, "recoil"
        s3.state = 5
      end
    elseif st == 5 then
      if idle then s3.bounce.paused, s3.timer, s3.state = false, 0, 6 end
    elseif st == 6 then
      s3.timer = s3.timer + 1
      if s3.timer > 16 then nidoHop(n, 8, 12, 5); s3.state = 7 end
    elseif st == 7 then
      if idle then nidoHop(n, 8, 12, 5); s3.state = 8 end
    elseif st == 8 then
      if idle then s3.timer, s3.state = 0, 9 end
    elseif st == 9 then
      s3.timer = s3.timer + 1
      if s3.timer > 20 then
        n.state, n.timer, n.shake = 0, 0, 0
        n.x, n.x2 = n.x + n.x2, 0
        n.speed, n.anim, n.cb = 36, NIDO.crouch, "attack"
        s3.timer, s3.state = 0, 10
      end
    elseif st == 10 then
      if s3.bounce.state == 0 then
        s3.bounce.paused = true
        s3.backPieces = true
        s3.state = 11
      end
    elseif st == 11 then
      s3.gengarShown = false
      s3.timer, s3.state = 0, 12
    elseif st == 12 then
      s3.timer = s3.timer + 1
      if s3.timer == 48 then s3.whiteStep = 1 / fadeFrames(2) end
      if s3.timer > 120 then
        n.x, n.y, n.x2, n.y2, n.cb = n.x + n.x2, n.y + n.y2, 0, 0, nil
        s3.zoom = { t = 0 }
        s3.state, s3.timer = 13, 0
      end
    elseif st == 13 then
      s3.timer = s3.timer + 1
      if s3.timer > 8 then
        s3.bgSolidWhite = true
        s3.blackStep = 1 / fadeFrames(-2)
        s3.state = 14
      end
    elseif st == 14 then
      if s3.black >= 1 then s3.timer, s3.state = 0, 15 end
    else
      s3.timer = s3.timer + 1
      if s3.timer > 60 then self.phase = "done" return end
    end
  end
  if s3.whiteStep > 0 then s3.white = math.min(1, s3.white + s3.whiteStep) end
  if s3.blackStep > 0 then s3.black = math.min(1, s3.black + s3.blackStep) end
  self:stepScene3Tasks()
  self:stepScene3Sprites()
end

function Gen3IntroFRLG:drawScene3()
  local s3 = self.s3
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1, 1)

  -- BG1, the forest (priority 1); its own palettes whiten and then fill white
  if s3.bgSolidWhite then
    love.graphics.rectangle("fill", 0, WIN_TOP, W, WIN_BOTTOM - WIN_TOP)
  else
    self:drawLayer("scene3Bg", s3.bgX, 0)
    overlay(1, 1, 1, s3.white)
  end

  -- OBJ priority 1: Nidorino, Gengar's back pieces, the swipe and the dust
  local zoom = s3.zoom and (1 + s3.zoom.t * 32 / 256) or 1
  local n = s3.nido
  if n then
    local cx, cy = n.x + n.x2, n.y + n.y2
    self:drawSprite("scene3Nidorino", n.anim, cx, cy, zoom, 0, 42)
  end
  if s3.backPieces then
    -- Scene3_CreateGengarSprite: centres (49,72) (97,72) (49,136) (97,136),
    -- zoomed about the corner they share (sGengarZoomMatrixAnchors)
    self:drawSprite("gengarPiece_tl", 0, 49, 72, zoom, 63, 63)
    self:drawSprite("gengarPiece_tr", 0, 97, 72, zoom, 0, 63)
    self:drawSprite("gengarPiece_bl", 0, 49, 136, zoom, 63, 0)
    self:drawSprite("gengarPiece_br", 0, 97, 136, zoom, 0, 0)
  end
  for _, s in ipairs(s3.fx) do
    if not s.invisible then
      if s.kind == "swipe" then
        if s.bottom then
          self:drawSprite(s.frame == 0 and "swipeBottom_a" or "swipeBottom_b", 0, s.x, s.y)
        else
          self:drawSprite("scene3Swipe", s.frame, s.x, s.y)
        end
      else
        self:drawSprite("scene3Dust", s.frame, s.x, s.y)
      end
    end
  end

  -- BG0, the Gengar layer (priority 0): hidden on WIN0's left half while it
  -- is up
  if s3.gengarShown then
    local sx, sy = s3.gengarX / 256, s3.gengarY
    if s3.win0 then
      self:drawLayer("scene3GengarBounce", sx, sy,
                     120, WIN_TOP, W - 120, WIN_BOTTOM - WIN_TOP)
    else
      self:drawLayer("scene3GengarBounce", sx, sy)
    end
  end

  -- OBJ priority 0: the grass clump crossing the foreground
  if s3.grass then self:drawSprite("scene3Grass", 0, s3.grass.x, s3.grass.y) end

  letterbox()
  overlay(0, 0, 0, s3.black)
end

-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:draw()
  love.graphics.setColor(1, 1, 1, 1)
  if self.phase == "card" then self:drawCard()
  elseif self.phase == "gf" then self:drawGameFreak()
  elseif self.phase == "scene1" then self:drawScene1()
  elseif self.phase == "scene2" then self:drawScene2()
  elseif self.phase == "scene3" then self:drawScene3()
  else
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Gen3IntroFRLG
