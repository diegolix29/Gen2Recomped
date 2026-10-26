-- BLACK AND WHITE'S EGG HATCH -- overlay 215 (egg_demo_graphic.c /
-- egg_demo_view.c), its art from src/import/Gen5EggHatchArt.lua.
--
--   * the egg is the Pokemon picture entry 650 (the Manaphy Egg 651) played
--     on its NMAR sequence 1 -- the hatch, 381 frames for the Egg: the
--     wobbles and cracks are the picture's own animation;
--   * /a/1/8/9's SPA fired on the overlay's frame tables (the Egg: emitters
--     3 and 4 at frame 0, 0 / 1 / 2 at 300; the Manaphy Egg: 0 / 1 / 2 at 380),
--     at the picture's centre;
--   * black, with the 24 px letterbox over it (/a/1/8/9 3-5).
--
-- THE VIEW MODULE'S CLOCK (0x021F67E0), counted from the egg's start:
--   * the egg's phase is 380 frames (Manaphy's 300); the Egg's sounds:
--     SEQ_SE_EDEMO_05 (1968) at 10, 15, 85 and 90, EDEMO_01 (1954) at 20 and
--     109, W181_01 (1488) at 218, and from 150 on EDEMO_04 (1967) again and
--     again -- 20 frames apart until 309, back to back after; Manaphy's
--     EDEMO_02 (1955) at 10 and EDEMO_07 (1960) after it;
--   * at the end: TDEMO_011 (1935), the egg fading to white (0x2015F50,
--     0 -> 16, a step a frame), then gone; the Pokemon in its place, white;
--     120 frames; the Pokemon fading in (16 -> 0, delay 2); 65 frames; its
--     cry; then the main module's ME 1305 and "{VAR1} hatched from the
--     Egg!", the nickname question (bank 260, Gen45Hatch), the fade out.
--
-- NOT HERE: the light model demo_sinka02 (/a/1/8/9 6-9) and the main
-- module's opening (its six model animations before BGM 1010).

local Assets = require('src.render.Assets')
local State = {}; State.__index = State
State.isOpaque = true

local W, H = 256, 192
local MON_X, MON_Y = 128, 96

local function image(path)
  if not path then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter('nearest', 'nearest'); return img end
end

function State.available(game)
  local art = game and game.data and game.data.gen5_egg_hatch
  return type(art) == 'table' and type(art.egg) == 'table' and art.egg.path ~= nil
end

-- the egg's picture on one NMAR sequence (Gen5MonAnimPlayer's drawing, with
-- the sequence chosen)
local function eggPlayer(record, sequence)
  local Decoder = require('src.import.Gen5MonAnim')
  local okR, bytes = pcall(love.filesystem.read, Assets.resolve(record.path))
  local arc = okR and bytes and Decoder.unpack(bytes)
  if not arc then return nil end
  local set = Decoder.load(arc, record.species, 'front')
  local machine = set and Decoder.machine(set, sequence)
  if not machine then return nil end
  local rasters = {}
  local ox, oy = Decoder.align(set, machine.state(), rasters)
  local p = { set = set, machine = machine, cells = {}, ox = ox or Decoder.ORIGIN[1], oy = oy or Decoder.ORIGIN[2] }
  for id, cell in pairs(set.cells.cells) do
    local raster = rasters[id] or Decoder.rasterCell(cell, set.sheet, set.cells.mappingMode)
    if raster then
      local rgba = Decoder.rgba(raster.px, raster.w, raster.h, set.palette)
      local img = love.graphics.newImage(require('src.import.ImageWriter').fromRGBA8(raster.w, raster.h, rgba))
      img:setFilter('nearest', 'nearest')
      p.cells[id] = { image = img, x = raster.x0, y = raster.y0 }
    end
  end
  local length = 0
  for _, f in ipairs((set.mcAnim.sequences[sequence] or {}).frames or {}) do length = length + (f.duration or 0) end
  p.length = length
  return p
end

local function drawEgg(p, cx, cy)
  local g = love.graphics
  g.push()
  g.translate(cx - 48 + p.ox, cy - 48 + p.oy)
  for _, part in ipairs(p.machine.state()) do
    local cell = p.cells[part.cell]
    if cell then
      local top = part.top
      g.push(); g.translate(top.tx, top.ty); g.rotate(top.rot); g.scale(top.sx, top.sy)
      g.translate(part.tx, part.ty); g.rotate(part.rot); g.scale(part.sx, part.sy)
      g.draw(cell.image, cell.x, cell.y); g.pop()
    end
  end
  g.pop()
end

function State.new(game, mon, onDone)
  local self = setmetatable({ game = game, mon = mon, onDone = onDone }, State)
  local art = game.data.gen5_egg_hatch
  self.art = art
  self.manaphy = tonumber(mon.species) == 490
  local rec = (self.manaphy and art.manaphy) or art.egg
  local ok, p = pcall(eggPlayer, rec, 1)
  self.egg = ok and p or nil
  self.schedule = (art.schedule or {})[self.manaphy and 'manaphy' or 'egg'] or {}
  self.particleArt = art.images or {}
  self.textureBits = art.textures or {}
  self.systems = {}
  self.monSprite = image(require('src.pokemon.Sprites').path(game.data, mon.species, 'front', { mon = mon }))
  self.white, self.screen = 0, 16
  self.eggWhite, self.monWhite = 0, 16
  self.length = self.manaphy and 300 or 380
  self.phase, self.t = 'fadeIn', 0
  return self
end

function State:uiSize() return W, H end
function State:wantsFillScale() return true end

function State:emit(id)
  local P = require('src.battle.Gen4ParticleSystem')
  local sys = self.art.emitters and P.resource(self.art.emitters, id)
  if sys then
    sys:start(301 + id)
    sys.emitterX, sys.emitterY = 0, 0
    self.systems[#self.systems + 1] = sys
  end
end

local function se(self, id)
  local ok, Sound = pcall(require, 'src.core.Sound')
  if ok and Sound.playSe then return select(2, pcall(Sound.playSe, self.game.data, id)) end
end

-- the egg's sounds, frame by frame (0x021F682A..0x021F6946)
function State:eggSounds(t)
  if self.manaphy then
    if t == 10 then self.sfx = se(self, 1955); self.manaphyStep = 1
    elseif self.manaphyStep == 1 and not (self.sfx and self.sfx.isPlaying and self.sfx:isPlaying()) then
      se(self, 1960); self.manaphyStep = 2
    end
    return
  end
  if t == 20 or t == 109 then se(self, 1954) elseif t == 218 then se(self, 1488) end
  if t == 10 or t == 15 or t == 85 or t == 90 then se(self, 1968) end
  if t >= 150 and t < self.length then
    local playing = self.loopSfx and self.loopSfx.isPlaying and self.loopSfx:isPlaying()
    if self.loopOn and not playing then
      self.loopOn = false
      self.cooldown = (t < 309) and 20 or 0
    end
    if not self.loopOn then
      if (self.cooldown or 0) == 0 then self.loopSfx = se(self, 1967); self.loopOn = true
      else self.cooldown = self.cooldown - 1 end
    end
  end
end

function State:finishText()
  local Hatch = require('src.pokemon.Gen45Hatch')
  local def = self.game.data.pokemon and self.game.data.pokemon[self.mon.species]
  local name = def and def.name or tostring(self.mon.species)
  local _, hatched, ask = Hatch.lines(self.game, name)
  local TextBox = require('src.render.TextBox')
  self.phase = 'talking'
  local Music = require('src.core.Music')
  local fanfare = Music.special(self.game.data, 'evolved')
  if fanfare then pcall(Music.playOnce, self.game.data, fanfare) end
  self.game.stack:push(TextBox.new(self.game, hatched, function()
    self.game.stack:push(TextBox.new(self.game, ask, nil, { choice = function(yes)
      self.nickname = yes and true or false
      self.phase = 'fadeOut'
    end }))
  end))
end

function State:update()
  self.t = self.t + 1
  local live = {}
  for _, sys in ipairs(self.systems) do if sys:update() then live[#live + 1] = sys end end
  self.systems = live
  if self.picAnim then pcall(self.picAnim.update, self.picAnim, 1 / 60) end
  local p = self.phase
  if p == 'fadeIn' then
    self.screen = math.max(0, self.screen - 1)
    if self.screen == 0 then
      local Music = require('src.core.Music')
      pcall(Music.play, self.game.data, Music.special(self.game.data, 'evolution'))
      self.phase, self.t = 'egg', 0
    end
  elseif p == 'egg' then
    for _, row in ipairs(self.schedule) do
      if row[1] == self.t then for _, id in ipairs(row[2]) do self:emit(id) end end
    end
    self:eggSounds(self.t)
    if self.egg then self.egg.machine.tick() end
    if self.t >= self.length then
      if self.loopSfx and self.loopSfx.stop then pcall(self.loopSfx.stop, self.loopSfx) end
      se(self, 1935)
      self.phase, self.t = 'eggWhite', 0
    end
  elseif p == 'eggWhite' then                    -- 0x2015F50(egg, 0, 16, 0)
    self.eggWhite = math.min(16, self.eggWhite + 1)
    if self.eggWhite >= 16 then
      self.egg, self.monShown, self.monWhite = nil, true, 16
      local okA, anim = pcall(require('src.pokemon.PicAnim').forMon, self.game.data, self.mon, 'front')
      self.picAnim = okA and anim or nil
      self.phase, self.t = 'hold', 0
    end
  elseif p == 'hold' then                        -- view state 6: 0x78 frames
    if self.t >= 120 then self.phase, self.t, self.fadeCount = 'monIn', 0, 0 end
  elseif p == 'monIn' then                       -- 0x2015F50(mon, 16, 0, 2)
    self.fadeCount = self.fadeCount + 1
    if self.fadeCount >= 3 then self.fadeCount = 0; self.monWhite = math.max(0, self.monWhite - 1) end
    if self.monWhite == 0 then self.phase, self.t = 'wait', 0 end
  elseif p == 'wait' then                        -- view state 7: 0x41 frames
    if self.t >= 65 then
      pcall(function() require('src.core.Sound').playCry(self.game.data, self.mon.species) end)
      if self.picAnim then pcall(self.picAnim.start, self.picAnim) end
      self.phase, self.t = 'cry', 0
    end
  elseif p == 'cry' then
    if self.t >= 60 then self:finishText() end
  elseif p == 'fadeOut' then
    self.screen = math.min(16, self.screen + 1)
    if self.screen >= 16 then
      self.phase = 'done'
      self.game.stack:pop()
      if self.onDone then self.onDone(self.nickname) end
    end
  end
end

local tintShader
local function whitened(level, fn)
  local g = love.graphics
  if level <= 0 then return fn() end
  if tintShader == nil then
    local ok, sh = pcall(g.newShader, [[
      extern float amount;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        return vec4(mix(p.rgb, vec3(1.0), amount), p.a) * colour;
      }
    ]])
    tintShader = ok and sh or false
  end
  local prev = g.getShader()
  if tintShader then tintShader:send('amount', level / 16); g.setShader(tintShader) end
  fn()
  g.setShader(prev)
end

function State:drawParticles()
  local g = love.graphics
  self.particleImages = self.particleImages or {}
  for _, sys in ipairs(self.systems) do
    sys:draw(MON_X, MON_Y, function(texture, x, y, sx, sy, alpha, rotation, colour, tileS, tileT)
      local rec = self.particleArt[('particle_%d'):format(texture)]
      if not rec or not rec.path then return end
      local img = self.particleImages[rec.path]
      if img == nil then img = image(rec.path) or false; self.particleImages[rec.path] = img end
      if not img then return end
      local w, h = img:getDimensions()
      local c = colour or { 255, 255, 255 }
      g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, math.max(0, math.min(1, tonumber(alpha) or 1)))
      tileS = math.max(1, math.floor(tonumber(tileS) or 1))
      tileT = math.max(1, math.floor(tonumber(tileT) or 1))
      if tileS > 1 or tileT > 1 then
        local tex = self.textureBits[texture + 1] or {}
        img:setWrap(tex.flipS and 'mirroredrepeat' or 'repeat', tex.flipT and 'mirroredrepeat' or 'repeat')
        self.tileQuads = self.tileQuads or {}
        local key = w .. ':' .. h .. ':' .. tileS .. ':' .. tileT
        local q = self.tileQuads[key]
        if not q then q = g.newQuad(0, 0, w * tileS, h * tileT, w, h); self.tileQuads[key] = q end
        g.draw(img, q, x, y, rotation or 0, (sx or 1) / tileS, (sy or 1) / tileT, w * tileS / 2, h * tileT / 2)
      else
        g.draw(img, x, y, rotation or 0, sx or 1, sy or 1, w / 2, h / 2)
      end
    end)
  end
  g.setColor(1, 1, 1, 1)
end

function State:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1); g.rectangle('fill', 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.egg then
    -- the fade is the sprite's own (its palette toward white)
    whitened(self.eggWhite, function() drawEgg(self.egg, MON_X, MON_Y) end)
  end
  if self.monShown then
    local img = self.monSprite
    if self.picAnim then
      local okF, frame = pcall(self.picAnim.image, self.picAnim, self.mon)
      if okF and frame then img = frame end
    end
    if img then
      local w, h = img:getDimensions()
      whitened(self.monWhite, function() g.draw(img, MON_X, MON_Y, 0, 1, 1, w / 2, h / 2) end)
    end
  end
  self:drawParticles()
  if self.white > 0 then g.setColor(1, 1, 1, self.white / 16); g.rectangle('fill', 0, 0, W, H) end
  local bar = self.art.letterbox or 24
  g.setColor(0, 0, 0, 1)
  g.rectangle('fill', 0, 0, W, bar)
  g.rectangle('fill', 0, H - bar, W, bar)
  if self.screen > 0 then g.setColor(0, 0, 0, self.screen / 16); g.rectangle('fill', 0, 0, W, H) end
  g.setColor(1, 1, 1, 1)
end

return State
