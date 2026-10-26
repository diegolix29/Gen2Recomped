-- PLATINUM'S EVOLUTION SCENE -- src/evolution.c, run on its own clock.
--
-- The base (Gen3EvolutionState) keeps the shared transaction: the species
-- change, the congratulation fanfare and the move learning after it. What is
-- Platinum's here is everything on screen and when:
--
--   * BG3 is egg_data.narc 0/1/8 (Gen4EvolutionArt `background`); the mon is
--     its front sprite centred at (128, 80); the bottom screen is the
--     Poketch's "unavailable" picture (poketch.narc 10/11/12);
--   * window 0 is the only thing BG3 and the 3D layer (sprites, particles)
--     show through -- 0..160 at first, closing two lines a frame to 40..120
--     while the forms change and opening again after -- with the backdrop
--     (BG palette 0 colour 0) and the message box outside it;
--   * the timeline: fade in from black (PaletteData_StartFade wait 1, sprites
--     16->0 at once); "What? X is evolving!" (battle_strings 915) and the cry;
--     20 frames; particle emitter 0 and both forms fading to white (16 steps,
--     a step every 5 frames); 40 frames of the window closing, then emitters
--     1, 2, 7, 8, 9 and 11 and the forms trading places -- the old one's
--     scale falling 8/256 a frame as the new one's rises, then back, the step
--     doubling each round up to 64 -- for as long as any emitter lives; then
--     emitters 3, 4, 5, 6 and 10, the new form alone, the BG fading to white
--     (wait 2), the window opening; 8 frames after the fade emitter 12, the BG
--     fading back (wait 4) and the sprite (a step every 4 frames); the new
--     cry, and "Congratulations! Your X evolved into Y!" (918).
--   * B while the forms trade places (when the evolution may be stopped):
--     a fade to white and back, the old form, its cry, "Huh? X stopped
--     evolving!" (919).
--   * the particles are shinka_demo_particle.narc member 0 (Gen4EvolutionArt),
--     simulated by Gen4ParticleSystem, each emitter at (0, 8 * 172) fx32 --
--     10.75 pixels above the screen centre at the port's 32 px a unit.
--
-- SOUND: Evolution_Main's four effects, each on the frame its state fires --
-- SEQ_SE_DP_W025 with emitter 0 (EVOLUTION_STATE_START_FADE), SEQ_SE_DP_W060C
-- with emitters 1/2/7/8/9/11 (CLAMP_IN), SEQ_SE_DP_W062 with 3/4/5/6/10
-- (ANIMATION_ALTERNATE_POKEMON), SEQ_SE_DP_W080 with 12 (CLAMP_OUT_AND_FADE).
-- The text callback's SEQ_SE_DP_KON (move forgetting's "Poof!") belongs to
-- the base's move learning, not here.
--
-- THE SPRITES' OWN ANIMATION (PokemonSprite_LoadAnim + InitAnim at
-- PRINT_POKEMON_IS_EVOLVING, PLAY_EVOLVED_POKEMON_ANIMATION_AND_CRY and
-- CANCEL_EVOLUTION_ANIMATION): the species' frame script (PicAnim) and its
-- motion program (src/pokemon/Gen4MonMotion.lua), with each of those cries.
--
-- NOT HERE: the cry/anim waits, which are fixed frame counts rather than the
-- cry's real length.

local Base = require('src.ui.Gen3EvolutionState')
local Assets = require('src.render.Assets')
local Strings = require('src.core.Strings')
local State = {}; State.__index = State
setmetatable(State, { __index = Base }); State.isOpaque = true

local W, H = 256, 192
local MON_X, MON_Y = 128, 80
local PARTICLE_Y = -(8 * 172) / 4096 * 32

local function se(self, name, opts)
  local data = self.game and self.game.data or self.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then return Sound.playSe(data, name, opts) end
end

local TEXT = {
  evolving = { 915, Strings.source("What?\n{STRVAR_1 1 0 0} is evolving!") },
  congratulations = { 918, Strings.source("Congratulations! Your {STRVAR_1 1 0 0}\nevolved into {STRVAR_1 1 1 0}!") },
  stopped = { 919, Strings.source("Huh? {STRVAR_1 1 0 0}\nstopped evolving!") },
}

function State.text(game, role, one, two)
  local t = TEXT[role]
  local bank=((game.data or {}).gen4_evolution_ink or {}).bank or 368
  local s = (((game.data or {}).text or {})[("TEXT_B%04d_%05d"):format(bank,t[1])]) or Strings(t[2])
  local function safe(v) return (tostring(v or ""):gsub("%%", "%%%%")) end
  s = s:gsub("{STRVAR_1 1,? ?0,? ?0}", safe(one)):gsub("{STRVAR_1 1,? ?1,? ?0}", safe(two))
  s = s:gsub("{WAIT %d+}", ""):gsub("{[^}]*}", ""):gsub("[\r\011]", "")
  return s
end

local function image(path)
  if not path then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter('nearest', 'nearest'); return img end
end

function State.new(game, mon, species, onDone, via, evo)
  local self = Base.new(game, mon, species, onDone, via, evo)
  setmetatable(self, State)
  local function front(id)
    return image(require('src.pokemon.Sprites').path(game.data, id, 'front', { mon = mon, kind = 'evolution' }))
  end
  self.oldSprite, self.newSprite = front(mon.species), front(species)
  local art = (game.data or {}).gen4_evolution_art or {}
  local rec = art.background or (((game.data.gen4_graphics or {}).screens) or {})['evolution/background']
  self.background = image(type(rec) == 'table' and rec.path or rec)
  local ink = (game.data or {}).gen4_evolution_ink or {}
  self.emitters = ink.emitters
  self.backdrop = ink.backdrop or { 0, 0, 0 }
  self.textureBits = ink.textures or {}
  self.particleArt = {}
  for i = 0, 15 do
    local r = art[('particle_%d'):format(i)]
    if r then self.particleArt[i + 1] = r end
  end
  local blank = art.bottom or (((game.data.gen4_graphics or {}).screens) or {})['poketch/unavailable']
  self.bottom = image(type(blank) == 'table' and blank.path or blank)
  self.systems = {}
  self.scale = { 256, 0 }
  self.white = { 0, 0 }           -- sprite fade levels, 0..16, toward white
  self.spriteBlack = 16           -- the opening fade from black
  self.bgFade = { level = 16, target = 0, wait = 1, colour = 'black', count = 0 }
  self.win = { top = 0, bottom = 160 }
  self.f = 0
  return self
end

-- start the frame script and motion program of `which` ('old' / 'new')
function State:playAnim(which)
  local mon = self.mon
  local species = which == 'new' and self.newSpecies or mon.species
  local okA, anim = pcall(require('src.pokemon.PicAnim').new, self.game.data, species, mon, 'front')
  if okA and anim then pcall(anim.start, anim) end
  local def = self.game.data.pokemon and self.game.data.pokemon[species]
  local pa = def and def.picAnim
  local motion = pa and pa.motion and require('src.pokemon.Gen4MonMotion').new(self.game.data, pa.motion, pa.startDelay or 0)
  self.anims = self.anims or {}
  self.anims[which] = { pic = okA and anim or nil, motion = motion }
end

function State:tickAnims()
  for _, a in pairs(self.anims or {}) do
    if a.pic then pcall(a.pic.update, a.pic, 1 / 60) end
    if a.motion then a.motion:update() end
  end
end

function State:uiSize() return W, H end
function State:wantsFillScale() return true end
function State:sgbPalettes() return { require('src.render.PaletteFX').trueColorZone(0, 0, 31, 23) } end

-- ------------------------------------------------------------ the clocks --

-- PaletteData_StartFade: two sixteenths a step, a step every wait + 1 frames.
function State:fade(target, wait, colour)
  self.bgFade = { level = self.bgFade.level, target = target, wait = wait, colour = colour or self.bgFade.colour, count = wait }
end

function State:fadeBusy() return self.bgFade.level ~= self.bgFade.target end

function State:tickFade()
  local f = self.bgFade
  if f.level == f.target then return end
  if f.count < f.wait then f.count = f.count + 1; return end
  f.count = 0
  if f.level < f.target then f.level = math.min(f.target, f.level + 2) else f.level = math.max(f.target, f.level - 2) end
end

-- PokemonSprite_StartFade: one sixteenth a step, a step every delay + 1.
function State:spriteFade(from, to, delay)
  self.sprite = { level = from, target = to, delay = delay, count = 0 }
end

function State:tickSpriteFade()
  local s = self.sprite
  if not s or s.level == s.target then return end
  if s.count > 0 then s.count = s.count - 1; return end
  s.count = s.delay
  s.level = s.level + (s.level < s.target and 1 or -1)
end

function State:emit(...)
  local P = require('src.battle.Gen4ParticleSystem')
  for _, id in ipairs({ ... }) do
    local sys = self.emitters and P.resource(self.emitters, id)
    if sys then
      sys:start(97 + id)
      sys.emitterX, sys.emitterY = 0, PARTICLE_Y
      self.systems[#self.systems + 1] = sys
    end
  end
end

function State:particlesActive()
  return #self.systems > 0
end

-- ----------------------------------------------------------------- flow --

-- The scene's own lines stay in the message window while it runs (they are
-- printed to BG1 and never cleared), so the opening line is a TextBox this
-- screen owns and steps itself; the closing lines wait for a button on top.
function State:say(role, onDone, owned)
  local TextBox = require('src.render.TextBox')
  local text = State.text(self.game, role, self.oldName, self.newName)
  if owned then
    self.box = TextBox.new(self.game, text, nil, { stay = {} })
    self.boxDone, self.boxWait = onDone, 0
    return
  end
  self.box = nil
  self.game.stack:push(TextBox.new(self.game, text, onDone))
end

function State:begin()
  if self.began then return end
  self.began = true
  self.phase = 'opening'
  self.t = 0
  self:spriteFade(16, 0, 0)
  self.spriteColour = 'black'
  require('src.core.Sound').playCry(self.game.data, self.mon.species)
  self:playAnim('old')
  self:say('evolving', function() self.phase, self.t = 'delay', 0
    local Music = require('src.core.Music')
    Music.play(self.game.data, Music.special(self.game.data, 'evolution'))
  end, true)
end

function State:stop()
  self.phase, self.t = 'cancel', 0
  self.canceled = true
  self:fade(16, 0, 'white')
  self.spriteColour = 'white'
end

function State:finish()
  local game = self.game
  local Evolution = require('src.pokemon.Evolution')
  local Music = require('src.core.Music')
  Evolution.apply(game, self.mon, self.newSpecies, self.via, self.evo)
  local fanfare = Music.special(game.data, 'evolved')
  if fanfare then Music.playOnce(game.data, fanfare) end
  self:say('congratulations', function()
    Music.restoreMap(game.data)
    game.stack:pop()
    Evolution.learnEvolutionMoves(game, self.mon, self.onDone)
  end)
end

-- Evolution_Main's shrinkAndGrowState: even, the old form shrinks as the new
-- grows; odd, the reverse; a full round doubles the step (to 64).
function State:shrinkGrow()
  local d = self.delta
  if self.growState % 2 == 0 then
    self.scale[1] = math.max(0, self.scale[1] - d); self.scale[2] = self.scale[2] + d
    if self.scale[1] == 0 then self.growState = self.growState + 1 end
  else
    self.scale[1] = self.scale[1] + d; self.scale[2] = math.max(0, self.scale[2] - d)
    if self.scale[2] == 0 then
      self.growState = self.growState + 1
      if self.delta < 64 then self.delta = self.delta * 2 end
    end
  end
end

function State:update()
  if not self.began then return self:begin() end
  self.f = self.f + 1
  if self.box then
    pcall(self.box.update, self.box, 1 / 60)
    -- printed, the cry and the opening animation over (fixed: one second)
    if self.box.done and self.boxDone then
      self.boxWait = self.boxWait + 1
      if self.boxWait >= 60 then local fn = self.boxDone; self.boxDone = nil; fn() end
    end
  end
  self.t = self.t + 1
  self:tickAnims()
  self:tickFade()
  self:tickSpriteFade()
  if self.growState then self:shrinkGrow() end
  local live = {}
  for _, sys in ipairs(self.systems) do if sys:update() then live[#live + 1] = sys end end
  self.systems = live

  local p = self.phase
  if p == 'delay' then
    if self.t >= 20 then
      self:emit(0)
      self:spriteFade(0, 16, 4); self.spriteColour = 'white'
      se(self, "SEQ_SE_DP_W025")            -- evolution.c:361
      self.phase, self.t = 'clampIn', 0
    end
  elseif p == 'clampIn' then
    if self.win.top < 40 then self.win.top = self.win.top + 2; self.win.bottom = self.win.bottom - 2 end
    if self.t >= 40 then
      self:emit(1, 2, 7, 8, 9, 11)
      se(self, "SEQ_SE_DP_W060C")           -- evolution.c:380
      self.growState, self.delta = 0x10, 8
      self.phase, self.t = 'alternate', 0
    end
  elseif p == 'alternate' then
    if self.cancelable and self.game.input and self.game.input:wasPressed('b') then return self:stop() end
    if not self:particlesActive() then
      self:emit(3, 4, 5, 6, 10)
      self:fade(16, 2, 'white')
      self.scale = { 0, 256 }
      se(self, "SEQ_SE_DP_W062")            -- evolution.c:398
      self.growState = nil
      self.phase, self.t, self.delay = 'clampOut', 0, 8
    end
  elseif p == 'clampOut' then
    if self.win.top > 0 then self.win.top = self.win.top - 2; self.win.bottom = self.win.bottom + 2 end
    if not self:fadeBusy() then
      self.delay = self.delay - 1
      if self.delay <= 0 then
        self:emit(12)
        self:fade(0, 4, 'white')
        self:spriteFade(16, 0, 3)
        se(self, "SEQ_SE_DP_W080")          -- evolution.c:415
        self.phase, self.t = 'reveal', 0
      end
    end
  elseif p == 'reveal' then
    if not self:fadeBusy() and not self:particlesActive() then
      require('src.core.Sound').playCry(self.game.data, self.newSpecies)
      self:playAnim('new')
      self.phase = 'done'
      self:finish()
    end
  elseif p == 'cancel' then
    if not self:fadeBusy() and self.t > 1 and not self.canceledBack then
      self.canceledBack = true
      self.scale = { 256, 0 }
      self.growState = nil
      self.systems = {}
      self.win = { top = 0, bottom = 160 }
      self:fade(0, 0, 'white')
      self:spriteFade(16, 0, 0)
      require('src.core.Music').restoreMap(self.game.data)
    elseif self.canceledBack and not self:fadeBusy() and not self.stoppedSaid then
      self.stoppedSaid = true
      require('src.core.Sound').playCry(self.game.data, self.mon.species)
      self:playAnim('old')
      self.phase = 'done'
      self:say('stopped', function()
        self.game.stack:pop()
        if self.onDone then self.onDone() end
      end)
    end
  end
end

-- ------------------------------------------------------------------ draw --

local tintShader
local function tint()
  if tintShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern vec3 target;
      extern float amount;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        return vec4(mix(p.rgb, target, amount), p.a) * colour;
      }
    ]])
    tintShader = ok and sh or false
  end
  return tintShader or nil
end

function State:drawMon(img, scale256, level, colour, which)
  if not img or scale256 <= 0 then return end
  local live = which and self.anims and self.anims[which]
  if live and live.pic then
    local okF, frame = pcall(live.pic.image, live.pic, self.mon)
    if okF and frame then img = frame end
  end
  local g = love.graphics
  local w, h = img:getDimensions()
  local fw = math.min(w, 80)
  self.quads = self.quads or {}
  local q = self.quads[img]
  if not q then q = g.newQuad(0, 0, fw, math.min(h, 80), w, h); self.quads[img] = q end
  local s = scale256 / 256
  local sh = level > 0 and tint()
  local prev = g.getShader()
  if sh then
    sh:send('target', colour == 'black' and { 0, 0, 0 } or { 1, 1, 1 })
    sh:send('amount', level / 16)
    g.setShader(sh)
  end
  g.setColor(1, 1, 1, 1)
  if live and live.motion and s == 1 then live.motion:draw(img, q, MON_X, MON_Y, fw, math.min(h, 80))
  else g.draw(img, q, MON_X, MON_Y, 0, s, s, fw / 2, math.min(h, 80) / 2) end
  g.setShader(prev)
end

function State:drawParticles()
  local g = love.graphics
  self.particleImages = self.particleImages or {}
  for _, sys in ipairs(self.systems) do
    -- drawn as Gen4Battle.drawParticles draws a move's: the texture at its own
    -- size times the particle's two scales, from its centre, tiled when the
    -- emitter repeats it, modulated by the particle's colour
    sys:draw(128, 96, function(texture, x, y, sx, sy, alpha, rotation, colour, tileS, tileT)
      local rec = self.particleArt[texture + 1]
      if not rec or not rec.path then return end
      local img = self.particleImages[rec.path]
      if img == nil then img = image(rec.path) or false; self.particleImages[rec.path] = img end
      if not img then return end
      local w, h = img:getDimensions()
      local c = colour or { 255, 255, 255 }
      local a = math.max(0, math.min(1, tonumber(alpha) or 1))
      g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a)
      tileS = math.max(1, math.floor(tonumber(tileS) or 1))
      tileT = math.max(1, math.floor(tonumber(tileT) or 1))
      if tileS > 1 or tileT > 1 then
        -- a flipped repeat mirrors every other copy (the DS texture's
        -- flipS/flipT), which is how a quarter-arc texture becomes a ring
        local tex = self.textureBits[texture + 1] or {}
        img:setWrap(tex.flipS and 'mirroredrepeat' or 'repeat', tex.flipT and 'mirroredrepeat' or 'repeat')
        local key = w .. ':' .. h .. ':' .. tileS .. ':' .. tileT
        self.tileQuads = self.tileQuads or {}
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
  local f = self.bgFade
  local amount = f.level / 16
  local fc = f.colour == 'black' and { 0, 0, 0 } or { 1, 1, 1 }
  local b = self.backdrop
  local function mixed(c) return c[1] / 255 * (1 - amount) + fc[1] * amount, c[2] / 255 * (1 - amount) + fc[2] * amount,
    c[3] / 255 * (1 - amount) + fc[3] * amount end
  -- the backdrop (outside window 0 and under everything)
  g.setColor(mixed(b)); g.rectangle('fill', 0, 0, W, H)
  -- window 0: BG3 and the 3D layer
  local top, bottom = self.win.top, self.win.bottom
  local sx, sy = g.transformPoint(0, top)
  local ex, ey = g.transformPoint(W, bottom)
  local old = { g.getScissor() }
  g.intersectScissor(sx, sy, math.max(0, ex - sx), math.max(0, ey - sy))
  if self.background then g.setColor(1, 1, 1, 1); g.draw(self.background, 0, 0) end
  if amount > 0 then g.setColor(fc[1], fc[2], fc[3], amount); g.rectangle('fill', 0, 0, W, H) end
  local s = self.sprite or { level = 0 }
  local colour = self.spriteColour or 'white'
  if self.canceled or self.phase == 'opening' or self.phase == 'delay' then
    self:drawMon(self.oldSprite, self.scale[1], s.level, colour, 'old')
  else
    self:drawMon(self.oldSprite, self.scale[1], s.level, colour, 'old')
    self:drawMon(self.newSprite, self.scale[2], s.level, colour, 'new')
  end
  self:drawParticles()
  if #old > 0 then g.setScissor(unpack(old)) else g.setScissor() end
  -- the message window stays up under the scene's text (BG1, outside the
  -- window's reach and outside the fade's palettes)
  if self.box then pcall(self.box.draw, self.box) end
  g.setColor(1, 1, 1, 1)
  local SS = require('src.ui.SecondScreen')
  if self.bottom and SS.mode and SS.mode(self.game) ~= 'off' and SS.draw then
    SS.draw(self.game, function()
      g.setColor(1, 1, 1, 1)
      g.draw(self.bottom, 0, 0)
    end)
  end
end

return State
