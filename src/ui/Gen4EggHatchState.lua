-- PLATINUM'S EGG HATCH CUTSCENE -- src/cutscenes/egg_hatch/main.c
-- (EggHatchCutscene_Normal), run on its own clock. HeartGold / SoulSilver
-- carry the same art byte for byte (Gen4EggHatchArt) and play it here too.
--
--   * BG3 is egg_data.narc 0/1/8; the egg is a 32x32 cell sprite at
--     (128, 120) with six frames (whole .. ready to shatter); two black bars
--     letterbox the screen (y = -16 and 192 - 48); the mon is its front
--     sprite at the screen centre, hidden until the egg is gone;
--   * the timeline: fade in from black (6 steps); SEQ_SHINKA; 25 frames, then
--     SEQ_SE_DP_EGG01; one crack and a minor shake, SE, two cracks and a
--     minor shake; a big shake -- halfway SE, big cracks, emitter 0 (the
--     first shards); when they are gone a bigger shake -- halfway SE, the
--     gaping hole, emitter 1; when those are gone the message window off and
--     the explosive shake -- halfway the last frame, SEQ_SE_DP_BOWA3,
--     emitters 2 (explosion) and 3 (sparkles); the egg hidden; 10 frames;
--     BG, sprites and the mon fading to white while the bars slide off 4 px
--     a frame; then the mon shown, 25 frames, everything fading back; the
--     cry, "{name} hatched from the Egg!", SEQ_FANFA5, the nickname
--     question with YES / NO, fade out.
--   * EggHatch_ShakeEgg's four tables (graphics.c sXOffsets .. sYScales):
--     ten steps of position nudges and affine scale, "half over" after the
--     sixth.
--   * the particles are egg_demo_particle.narc member 0 (normal.spa),
--     simulated by Gen4ParticleSystem with the emitter at the origin --
--     the orthographic camera's target, the screen centre.
--
-- MANAPHY (EggHatchCutscene_Manaphy, species 490): no egg sprite and no
-- shaking -- manaphy.spa's four emitters at once (glow 0, sparkles 1, ring 2,
-- the glowing egg 3) with the message window off; SEQ_SE_DP_W278 at frame
-- 25, W080C at 80, W361 at 142; at 160 the same white fade, bars and reveal
-- as the normal scene's ending.
--
-- THE MON'S OWN ANIMATION: EggHatch_PlayMonAnim with the cry -- the species'
-- frame script from pl_poke_data (def.picAnim, src/pokemon/PicAnim.lua) and
-- its motion program after the species' start delay (PokemonSprite_LoadAnim:
-- def.picAnim.motion / startDelay, run by src/pokemon/Gen4MonMotion.lua).

local Assets = require('src.render.Assets')
local State = {}; State.__index = State
State.isOpaque = true

local W, H = 256, 192
local EGG_X, EGG_Y = 128, 120
local MON_X, MON_Y = 128, 96

-- graphics.c: EGG_MINOR_SHAKE, EGG_BIG_SHAKE, EGG_BIGGER_SHAKE,
-- EGG_EXPLOSIVE_SHAKE; 0xFF ends a list, missing entries are 0 (C zero fill)
local FF = 0xFF
local SHAKE = {
  minor = { x = { -1, 1, 1, -1, -1, 1, 1, -1, FF, FF }, y = { 0, FF },
            sx = { 1.0 }, sy = { 1.0 } },
  big = { x = { -2, 2, 2, -2, -2, 2, 2, -2, FF, FF }, y = { 0, 0, 1, 1, 0, -1, -1, 0, 0, FF },
          sx = { 1.0, 1.0, 1.1, 1.1, 1.1, 1.1, 1.1, 1.0, 1.0 }, sy = { 1.0, 1.0, 0.9, 0.9, 0.9, 0.9, 0.9, 1.0, 1.0 } },
  bigger = { x = { -3, 3, 3, -3, -3, 3, FF, FF }, y = { 0, 0, 1, 1, 1, -1, -1, -1, 0, 0 },
             sx = { 1.0, 1.1, 1.1, 1.2, 1.2, 1.2, 1.1, 1.1, 1.0 }, sy = { 1.0, 1.0, 0.9, 0.8, 0.7, 0.7, 0.8, 0.9, 1.0, 1.0 } },
}
SHAKE.explosive = SHAKE.bigger

local function image(path)
  if not path then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter('nearest', 'nearest'); return img end
end

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

-- Is the cutscene's art in this cache?
function State.available(game)
  local art = game and game.data and game.data.gen4_egg_hatch_art
  local ink = game and game.data and game.data.gen4_egg_hatch_ink
  return type(art) == 'table' and art.egg_0 ~= nil and type(ink) == 'table' and ink.normal ~= nil
end

-- onDone(nickname): nickname is true when YES was picked.
function State.new(game, mon, onDone)
  local self = setmetatable({ game = game, mon = mon, onDone = onDone }, State)
  local art = game.data.gen4_egg_hatch_art or {}
  local function img(key) local r = art[key]; return image(type(r) == 'table' and r.path or r) end
  local function origin(key) local r = art[key]; return type(r) == 'table' and r.originX or 0, type(r) == 'table' and r.originY or 0 end
  self.background = img('background')
  self.eggFrames = {}
  for i = 0, 5 do self.eggFrames[i] = img(('egg_%d'):format(i)) end
  self.eggOX, self.eggOY = origin('egg_0')
  self.bar = img('bar')
  self.barOX, self.barOY = origin('bar')
  self.manaphy = tonumber(mon.species) == 490 or mon.species == 'SPECIES_490'
  local set = self.manaphy and 'manaphy' or 'normal'
  local ink = game.data.gen4_egg_hatch_ink[set] or {}
  self.emitters, self.textureBits = ink.emitters, ink.textures or {}
  self.particleArt = {}
  for i = 0, 15 do
    local r = art[('%s_%d'):format(set, i)]
    if r then self.particleArt[i + 1] = r end
  end
  self.monSprite = image(require('src.pokemon.Sprites').path(game.data, mon.species, 'front', { mon = mon }))
  local okA, anim = pcall(require('src.pokemon.PicAnim').forMon, game.data, mon, 'front')
  self.picAnim = okA and anim or nil
  self.systems = {}
  self.frame = 0
  self.eggX, self.eggY, self.scaleX, self.scaleY = EGG_X, EGG_Y, 1, 1
  self.eggFrame = 0
  self.eggShown, self.monShown, self.barsShown = true, false, true
  self.topY, self.bottomY = -16, H - 48
  self.screen = { level = 16, target = 0, step = 16 / 6 }   -- StartScreenFade 6 steps, black
  self.white = { level = 0, target = 0, wait = 0, count = 0 } -- BG / OBJ palette fade
  self.monWhite = { level = 0, target = 0 }
  self.phase, self.t = 'fadeIn', 0
  self.shake = { progress = 0 }
  return self
end

function State:uiSize() return W, H end
function State:wantsFillScale() return true end
function State:sgbPalettes() return { require('src.render.PaletteFX').trueColorZone(0, 0, 31, 23) } end

-- ------------------------------------------------------------ the clocks --

-- IncrementShakeAnimation / EggHatch_ShakeEgg: 'finished', 'half' (after the
-- sixth step) or 'started'
function State:shakeStep(kind)
  local s, tab = self.shake, SHAKE[kind]
  if s.progress >= 10 then s.progress = 0; return 'finished' end
  local i = s.progress + 1
  local x, y = tab.x[i] or 0, tab.y[i] or 0
  local sx, sy = tab.sx[i] or 0, tab.sy[i] or 0
  local pieces = 0
  if x == FF then x = 0; pieces = pieces + 1 end
  if y == FF then y = 0; pieces = pieces + 1 end
  self.eggX, self.eggY = self.eggX + x, self.eggY + y
  if sx ~= 0 then self.scaleX, self.scaleY = sx, sy else pieces = pieces + 1 end
  if pieces == 3 then s.progress = 0; return 'finished' end
  s.progress = s.progress + 1
  return s.progress == 6 and 'half' or 'started'
end

-- PaletteData_StartFade: two sixteenths a step, a step every wait + 1 frames
function State:tickWhite()
  local f = self.white
  if f.level == f.target then return end
  if f.count < f.wait then f.count = f.count + 1; return end
  f.count = 0
  f.level = f.level < f.target and math.min(f.target, f.level + 2) or math.max(f.target, f.level - 2)
end

-- PokemonSprite_StartFade(.., delay 0): a sixteenth a frame
function State:tickMonWhite()
  local f = self.monWhite
  if f.level ~= f.target then f.level = f.level + (f.level < f.target and 1 or -1) end
end

function State:tickScreen()
  local s = self.screen
  if s.level == s.target then return end
  s.level = s.level < s.target and math.min(s.target, s.level + s.step) or math.max(s.target, s.level - s.step)
end

function State:emit(id)
  local P = require('src.battle.Gen4ParticleSystem')
  local sys = self.emitters and P.resource(self.emitters, id)
  if sys then
    sys:start(211 + id)
    sys.emitterX, sys.emitterY = 0, 0
    self.systems[#self.systems + 1] = sys
  end
end

function State:particlesActive() return #self.systems > 0 end

-- ----------------------------------------------------------------- flow --

function State:say(text, opts, onDone)
  local TextBox = require('src.render.TextBox')
  self.game.stack:push(TextBox.new(self.game, text, onDone, opts))
end

function State:finishText()
  local Hatch = require('src.pokemon.Gen45Hatch')
  local def = self.game.data.pokemon and self.game.data.pokemon[self.mon.species]
  local name = def and def.name or tostring(self.mon.species)
  local _, hatched, ask = Hatch.lines(self.game, name)
  pcall(function() require('src.core.Sound').playCry(self.game.data, self.mon.species) end)
  if self.picAnim then pcall(self.picAnim.start, self.picAnim) end
  local def2 = self.game.data.pokemon and self.game.data.pokemon[self.mon.species]
  local pa = def2 and def2.picAnim
  if pa and pa.motion then
    self.motion = require('src.pokemon.Gen4MonMotion').new(self.game.data, pa.motion, pa.startDelay or 0)
  end
  self.phase = 'talking'
  self:say(hatched, nil, function()
    local Music = require('src.core.Music')
    local fanfare = Music.special(self.game.data, 'evolved')
    if fanfare then pcall(Music.playOnce, self.game.data, fanfare) end
    self:say(ask, { choice = function(yes)
      self.nickname = yes and true or false
      self.phase, self.t = 'fadeOut', 0
      self.screen.target = 16
    end })
  end)
end

function State:update()
  self.frame = self.frame + 1
  self.t = self.t + 1
  self:tickScreen(); self:tickWhite(); self:tickMonWhite()
  if self.picAnim then pcall(self.picAnim.update, self.picAnim, 1 / 60) end
  if self.motion and not self.motion:update() and self.motion:done() then self.motionOver = true end
  local live = {}
  for _, sys in ipairs(self.systems) do if sys:update() then live[#live + 1] = sys end end
  self.systems = live
  local p = self.phase
  if p == 'fadeIn' then
    if self.screen.level == 0 then
      local Music = require('src.core.Music')
      pcall(Music.play, self.game.data, Music.special(self.game.data, 'evolution'))
      self.eggFrame = 0
      self.phase, self.t = 'init', 0
      if self.manaphy then
        self.eggShown = false
        for id = 0, 3 do self:emit(id) end
        self.phase, self.t = 'manaphy', 0
      end
    end
  elseif p == 'manaphy' then                      -- ManaphyEggAnimation
    if self.t == 25 then se(self, 'SEQ_SE_DP_W278')
    elseif self.t == 80 then se(self, 'SEQ_SE_DP_W080C')
    elseif self.t == 142 then se(self, 'SEQ_SE_DP_W361') end
    if self.t >= 160 then
      self.white = { level = 0, target = 16, wait = 0, count = 0 }
      self.monWhite = { level = 0, target = 16 }
      self.phase, self.sub = 'complete', 3
    end
  elseif p == 'init' then                         -- InitializeEggAnimation
    if self.t >= 25 then se(self, 'SEQ_SE_DP_EGG01'); self.phase, self.sub = 'start', 0 end
  elseif p == 'start' then                        -- StartBreakingEgg
    if self.sub == 0 then
      if not self:particlesActive() then self.eggFrame = 1; self.sub = 1 end
    elseif self:shakeStep('minor') == 'finished' then
      if self.sub == 1 then se(self, 'SEQ_SE_DP_EGG01'); self.eggFrame = 2; self.sub = 2
      else self.eggFrame = 2; self.phase = 'first' end
    end
  elseif p == 'first' then                        -- FirstEggShardsBreakOff
    local r = self:shakeStep('big')
    if r == 'half' then se(self, 'SEQ_SE_DP_EGG01'); self.eggFrame = 3; self:emit(0) end
    if r == 'finished' then self.phase, self.sub = 'more', 0 end
  elseif p == 'more' then                         -- MoreEggShardsBreakAway
    if self.sub == 0 then
      if not self:particlesActive() then self.sub = 1 end
    else
      local r = self:shakeStep('bigger')
      if r == 'half' then se(self, 'SEQ_SE_DP_EGG01'); self.eggFrame = 4; self:emit(1) end
      if r == 'finished' then self.phase, self.sub = 'complete', 0 end
    end
  elseif p == 'complete' then                     -- CompleteEggAnimation
    if self.sub == 0 then
      if not self:particlesActive() then self.eggFrame = 4; self.sub = 1 end
    elseif self.sub == 1 then
      local r = self:shakeStep('explosive')
      if r == 'half' then
        self.eggFrame = 5; se(self, 'SEQ_SE_DP_BOWA3'); self:emit(2); self:emit(3)
      end
      if r == 'finished' then self.eggShown = false; self.sub, self.t = 2, 0 end
    elseif self.sub == 2 then
      if self.t >= 10 then
        self.white = { level = 0, target = 16, wait = 0, count = 0 }
        self.monWhite = { level = 0, target = 16 }
        self.sub = 3
      end
    elseif self.sub == 3 then
      local off = 0
      if self.topY > -48 then self.topY = self.topY - 4 else off = off + 1 end
      if self.bottomY < H then self.bottomY = self.bottomY + 4 else off = off + 1 end
      if self.white.level == self.white.target and off == 2 and self.monWhite.level == self.monWhite.target then
        self.monShown, self.eggShown, self.barsShown = true, false, false
        self.sub, self.t = 4, 0
      end
    elseif self.sub == 4 then
      if self.t >= 25 then
        self.monWhite.target = 0
        self.white = { level = 16, target = 0, wait = 0, count = 0 }
        self.sub = 5
      end
    elseif self.sub == 5 then
      if self.white.level == 0 and self.monWhite.level == 0 then self.sub = 6 end
    elseif self.manaphy or not self:particlesActive() then
      self:finishText()
    end
  elseif p == 'fadeOut' then
    if self.screen.level >= 16 then
      self.phase = 'done'
      self.game.stack:pop()
      if self.onDone then self.onDone(self.nickname) end
    end
  end
end

-- ------------------------------------------------------------------ draw --

local tintShader
local function tint()
  if tintShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern float amount;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        return vec4(mix(p.rgb, vec3(1.0), amount), p.a) * colour;
      }
    ]])
    tintShader = ok and sh or false
  end
  return tintShader or nil
end

local function whitened(level, fn)
  local g = love.graphics
  local sh = level > 0 and tint()
  local prev = g.getShader()
  if sh then sh:send('amount', level / 16); g.setShader(sh) end
  fn()
  g.setShader(prev)
end

function State:drawParticles()
  local g = love.graphics
  self.particleImages = self.particleImages or {}
  for _, sys in ipairs(self.systems) do
    sys:draw(W / 2, H / 2, function(texture, x, y, sx, sy, alpha, rotation, colour, tileS, tileT)
      local rec = self.particleArt[texture + 1]
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
  local white = self.white.level
  g.setColor(1, 1, 1, 1)
  if self.background then g.draw(self.background, 0, 0) end
  if white > 0 then g.setColor(1, 1, 1, white / 16); g.rectangle('fill', 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  if self.monShown and self.monSprite then
    whitened(self.monWhite.level, function()
      local okF, frame = false, nil
      if self.picAnim then okF, frame = pcall(self.picAnim.image, self.picAnim, self.mon) end
      local pic = (okF and frame) or self.monSprite
      local w, h = pic:getDimensions()
      self.monQuads = self.monQuads or {}
      local q = self.monQuads[pic]
      if not q then q = g.newQuad(0, 0, math.min(w, 80), math.min(h, 80), w, h); self.monQuads[pic] = q end
      if self.motion then self.motion:draw(pic, q, MON_X, MON_Y, math.min(w, 80), math.min(h, 80))
      else g.draw(pic, q, MON_X, MON_Y, 0, 1, 1, math.min(w, 80) / 2, math.min(h, 80) / 2) end
    end)
  end
  local egg = self.eggShown and self.eggFrame and self.eggFrames[self.eggFrame]
  if egg then
    whitened(white, function()
      -- AFFINE_OVERWRITE_MODE_DOUBLE: scaled about the cell's own centre
      g.draw(egg, self.eggX, self.eggY, 0, self.scaleX, self.scaleY, -self.eggOX, -self.eggOY)
    end)
  end
  self:drawParticles()
  -- the bars keep their own palette through the white fade
  if self.barsShown and self.bar then
    g.draw(self.bar, 0 + self.barOX, self.topY + self.barOY)
    g.draw(self.bar, 0 + self.barOX, self.bottomY + self.barOY)
  end
  if self.screen.level > 0 then
    g.setColor(0, 0, 0, math.min(1, self.screen.level / 16)); g.rectangle('fill', 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

return State
