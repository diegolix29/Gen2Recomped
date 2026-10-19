-- BLACK AND WHITE'S EVOLUTION SCENE (overlay 195: shinka_demo.c and its
-- _view / _effect modules; scratch_claude/evolution_map.md), on the shared
-- transaction in Gen3EvolutionState.
--
-- What is BW's here is the picture and its clock:
--   * black letterbox bars 24 px deep (BG2, /a/1/8/2 members 3-5), the
--     cylinder of white light streaks round the Pokemon (member 8, turning),
--     and its particle set (member 10) fired on the frame table _02208ED0 --
--     emitters 0-4 at frame 0, 5-6 at 500, 7 at 755, 8 at 783;
--   * "What? X is evolving!" (system bank 172 #0), the old form's cry; the
--     picture fading to white one sixteenth a frame; 8 frames; the effect
--     starts (SE SHDEMO_01) and the frame counter with it -- SHDEMO_02 at
--     90, SHDEMO_03 on the beats 530 / 585 / 640 / 695, SHDEMO_05 at 740;
--   * between the beats the two silhouettes trade places TILE BY TILE over
--     an 18 x 18 grid (the view module's morph); at 740 the climax (SE
--     SHDEMO_04) leaves the new form; 30 frames; the fade back from white,
--     two frames a step; 30 more; the new cry and "Congratulations! Your X
--     evolved into Y!" (#2);
--   * B while the forms trade (when it may be stopped): the effect is cut,
--     the old form fades back, its cry, "Huh? X stopped evolving!" (#1).
--
-- APPROXIMATE, and said so: the morph's exact tile order and its glow quad
-- (thresholds 100 / 200 / 240, the radius tables) are only partly read out of
-- the overlay, so the tiles here swap in a random order on each beat; the
-- cylinder turns rather than scrolling its texture; the camera is the
-- effect module's (0, 0, 13) with a 30-degree view, by eye beyond that.

local Base = require("src.ui.Gen3EvolutionState")
local State = {}; State.__index = State
setmetatable(State, { __index = Base }); State.isOpaque = true

local W, H = 256, 192
local MON_X, MON_Y = 128, 96
local GRID = 18
local BEATS = { 530, 585, 640, 695 }
local CLIMAX = 740
local START = 0

local function image(path)
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  if ok and img then img:setFilter("nearest", "nearest"); return img end
end

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

local TEXT = { evolving = 0, stopped = 1, congratulations = 2 }
local FALLBACK = {
  evolving = "What?\n{VAR1} is evolving!",
  stopped = "Huh? {VAR1}\nstopped evolving!",
  congratulations = "Congratulations! Your {VAR1}\nevolved into {VAR2}!",
}

function State.text(game, role, one, two)
  local key = ("TEXT_G5S_0172_%05d"):format(TEXT[role])
  local s = ((game.data or {}).text or {})[key] or FALLBACK[role]
  local function safe(v) return (tostring(v or ""):gsub("%%", "%%%%")) end
  s = s:gsub("{VAR1}", safe(one)):gsub("{VAR2}", safe(two))
  return (s:gsub("{[^}]*}", ""))
end

function State.new(game, mon, species, onDone, via, evo)
  local self = Base.new(game, mon, species, onDone, via, evo)
  setmetatable(self, State)
  local Sprites = require("src.pokemon.Sprites")
  local function front(id)
    return image(Sprites.path(game.data, id, "front", { mon = mon, kind = "evolution" }))
  end
  self.oldSprite, self.newSprite = front(mon.species), front(species)
  self.art = (game.data or {}).gen5_evolution or {}
  self.systems = {}
  self.white = 0                  -- the picture's fade toward white, 0..16
  self.flip = {}                  -- which tiles show the new form
  self.order = {}
  for i = 1, GRID * GRID do self.order[i] = i end
  self.t, self.f = 0, 0
  return self
end

function State:uiSize() return W, H end
function State:wantsFillScale() return true end

-- -------------------------------------------------------------- the effect

function State:emit(ids)
  local P = require("src.battle.Gen4ParticleSystem")
  for _, id in ipairs(ids) do
    local sys = self.art.emitters and P.resource(self.art.emitters, id)
    if sys then
      sys:start(97 + id)
      sys.emitterX, sys.emitterY = 0, 0
      self.systems[#self.systems + 1] = sys
    end
  end
end

-- a beat: every tile not yet on the other form goes over, in a fresh random
-- order spread across 20 frames
function State:beat()
  self.toNew = not self.toNew
  for i = #self.order, 2, -1 do
    local j = love.math.random(1, i)
    self.order[i], self.order[j] = self.order[j], self.order[i]
  end
  self.sweep = 0
end

function State:tickSweep()
  if not self.sweep then return end
  self.sweep = self.sweep + 1
  local upto = math.floor(#self.order * math.min(1, self.sweep / 20))
  for k = 1, upto do self.flip[self.order[k]] = self.toNew or nil end
  if self.sweep >= 20 then self.sweep = nil end
end

-- ------------------------------------------------------------------- flow

function State:say(role, onDone)
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, State.text(self.game, role, self.oldName, self.newName), onDone))
end

function State:begin()
  if self.began then return end
  self.began = true
  self.phase = "opening"
  require("src.core.Sound").playCry(self.game.data, self.mon.species)
  self:say("evolving", function()
    local Music = require("src.core.Music")
    pcall(Music.play, self.game.data, Music.special(self.game.data, "evolution"))
    self.phase, self.t = "whiten", 0
  end)
end

function State:stop()
  self.phase, self.t, self.canceled = "cancel", 0, true
  self.systems = {}
  self.flip = {}
  self.sweep = nil
end

function State:finish()
  local game = self.game
  local Evolution = require("src.pokemon.Evolution")
  local Music = require("src.core.Music")
  Evolution.apply(game, self.mon, self.newSpecies, self.via, self.evo)
  local fanfare = Music.special(game.data, "evolved")
  if fanfare then pcall(Music.playOnce, game.data, fanfare) end
  self:say("congratulations", function()
    pcall(Music.restoreMap, game.data)
    game.stack:pop()
    Evolution.learnEvolutionMoves(game, self.mon, self.onDone)
  end)
end

function State:update()
  if not self.began then return self:begin() end
  self.f = self.f + 1
  self.t = self.t + 1
  local live = {}
  for _, sys in ipairs(self.systems) do if sys:update() then live[#live + 1] = sys end end
  self.systems = live
  self:tickSweep()

  local p = self.phase
  if p == "whiten" then
    -- one sixteenth a frame, then 8 frames
    if self.white < 16 then self.white = self.white + 1 ; self.t = 0
    elseif self.t >= 8 then
      self.phase, self.clock = "effect", START
      se(self, "SEQ_SE_SHDEMO_01")
    end
  elseif p == "effect" then
    local c = self.clock
    for _, row in ipairs(self.art.schedule or {}) do
      if row[1] == c then self:emit(row[2]) end
    end
    if c == 90 then se(self, "SEQ_SE_SHDEMO_02") end
    for _, b in ipairs(BEATS) do
      if c == b then self:beat(); se(self, "SEQ_SE_SHDEMO_03") end
    end
    if c == CLIMAX then
      se(self, "SEQ_SE_SHDEMO_05")
      se(self, "SEQ_SE_SHDEMO_04")
      for i = 1, GRID * GRID do self.flip[i] = true end
      self.sweep = nil
      self.phase, self.t = "settle", 0
    end
    if self.cancelable and self.game.input and self.game.input:wasPressed("b") then return self:stop() end
    self.clock = c + 1
  elseif p == "settle" then
    if self.t >= 30 then self.phase, self.t = "unwhite", 0 end
  elseif p == "unwhite" then
    -- two frames a step back from white
    if self.t % 2 == 0 and self.white > 0 then self.white = self.white - 1 end
    if self.white == 0 then self.phase, self.t = "hold", 0 end
  elseif p == "hold" then
    if self.t >= 30 then
      require("src.core.Sound").playCry(self.game.data, self.newSpecies)
      self.phase = "done"
      self:finish()
    end
  elseif p == "cancel" then
    if self.white > 0 then
      if self.t % 2 == 0 then self.white = self.white - 1 end
    elseif not self.stoppedSaid then
      self.stoppedSaid = true
      pcall(require("src.core.Music").restoreMap, self.game.data)
      require("src.core.Sound").playCry(self.game.data, self.mon.species)
      self.phase = "done"
      self:say("stopped", function()
        self.game.stack:pop()
        if self.onDone then self.onDone() end
      end)
    end
  end
end

-- -------------------------------------------------------------------- draw

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

-- THE CYLINDER OF LIGHT, seen from inside: its texture (demo_sinka01, white
-- streaks carried in the alpha of an A5I3 picture) scrolling past at the
-- BTA's +1 a frame. Drawn flat, wrapped round the field, because the model
-- path draws A5I3 opaque and the cylinder is only ever seen from its axis.
function State:drawCylinder()
  local rec = self.art.model
  local path
  for _, shape in ipairs(rec and rec.shapes or {}) do
    if shape.texture == "demo_sinka01" then path = shape.image end
  end
  if not path then return end
  self.streaks = self.streaks or image(path)
  local img = self.streaks
  if not img then return end
  img:setWrap("repeat", "repeat")
  local g = love.graphics
  local iw, ih = img:getDimensions()
  local bar = self.art.letterbox or 24
  local band = H - 2 * bar
  local k = band / ih
  local scroll = (self.f % iw)
  self.streakQuad = self.streakQuad or g.newQuad(0, 0, W / k, ih, iw, ih)
  self.streakQuad:setViewport(scroll, 0, W / k, ih, iw, ih)
  g.setColor(1, 1, 1, 0.85)
  g.draw(img, self.streakQuad, 0, bar, 0, k, k)
  g.setColor(1, 1, 1, 1)
end

-- the two forms, tile by tile: a tile shows the new form once it has flipped
function State:drawMorph()
  local g = love.graphics
  local old, new = self.oldSprite, self.newSprite
  if not old then return end
  local w, h = old:getDimensions()
  local size = math.min(w, h)
  local cell = size / GRID
  local x0, y0 = MON_X - size / 2, MON_Y - size / 2
  local sh = self.white > 0 and tint()
  local prevShader = g.getShader()
  if sh then sh:send("amount", self.white / 16); g.setShader(sh) end
  g.setColor(1, 1, 1, 1)
  self.cellQuads = self.cellQuads or {}
  for ty = 0, GRID - 1 do
    for tx = 0, GRID - 1 do
      local i = ty * GRID + tx + 1
      local img = (self.flip[i] and new) or old
      local iw, ih = img:getDimensions()
      local key = tostring(img) .. i
      local q = self.cellQuads[key]
      if not q then
        q = g.newQuad(tx * cell, ty * cell, cell, cell, iw, ih)
        self.cellQuads[key] = q
      end
      g.draw(img, q, x0 + tx * cell, y0 + ty * cell)
    end
  end
  g.setShader(prevShader)
end

function State:drawParticles()
  local g = love.graphics
  self.particleImages = self.particleImages or {}
  for _, sys in ipairs(self.systems) do
    sys:draw(MON_X, MON_Y, function(texture, x, y, sx, sy, alpha, rotation, colour, tileS, tileT)
      local rec = self.art.images and self.art.images[("particle_%d"):format(texture)]
      if not (rec and rec.path) then return end
      local img = self.particleImages[rec.path]
      if img == nil then img = image(rec.path) or false; self.particleImages[rec.path] = img end
      if not img then return end
      local iw, ih = img:getDimensions()
      local c = colour or { 255, 255, 255 }
      g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, math.max(0, math.min(1, tonumber(alpha) or 1)))
      -- a quarter-circle texture repeated 2 x 2 with the flip bits set is a
      -- whole glow or ring (the DS texture's flipS / flipT), as Platinum's
      -- scene draws them
      tileS = math.max(1, math.floor(tonumber(tileS) or 1))
      tileT = math.max(1, math.floor(tonumber(tileT) or 1))
      if tileS > 1 or tileT > 1 then
        local bits = (self.art.textures or {})[texture + 1] or {}
        img:setWrap(bits.flipS and "mirroredrepeat" or "repeat", bits.flipT and "mirroredrepeat" or "repeat")
        local key = iw .. ":" .. ih .. ":" .. tileS .. ":" .. tileT
        self.tileQuads = self.tileQuads or {}
        local q = self.tileQuads[key]
        if not q then q = g.newQuad(0, 0, iw * tileS, ih * tileT, iw, ih); self.tileQuads[key] = q end
        g.draw(img, q, x, y, rotation or 0, (sx or 1) / tileS, (sy or 1) / tileT, iw * tileS / 2, ih * tileT / 2)
      else
        g.draw(img, x, y, rotation or 0, sx or 1, sy or 1, iw / 2, ih / 2)
      end
    end)
  end
  g.setColor(1, 1, 1, 1)
end

function State:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  if self.phase == "effect" or self.phase == "settle" then self:drawCylinder() end
  self:drawMorph()
  self:drawParticles()
  -- the letterbox, over everything but the text
  local bar = self.art.letterbox or 24
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, bar)
  g.rectangle("fill", 0, H - bar, W, bar)
  g.setColor(1, 1, 1, 1)
end

return State
