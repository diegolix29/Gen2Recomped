-- src/ui/Gen5TradeSequence.lua -- BLACK AND WHITE'S TRADE DEMO (an NPC trade).
--
-- Overlay 117 on overlay 119 (src/import/Gen5TradeArt.lua has the map and
-- the art): the infrared trade's scene /a/1/0/4, which an in-game trade
-- borrows. Three parts, as overlay 117's states run them:
--
--   INTRO   (0x021D449C .. 0x021D48F0) the field fades out (8 frames), your
--           Pokemon comes to the middle over 42 frames and "Sending {VAR1} to
--           {VAR2}. / Good-bye, {VAR1}!" (system bank 159 #129) is printed
--   DEMO    (0x021D4CE8) 616 frames of the 3D scene `ir_sean` on its own BCA
--           and BTA, seen from the baked camera (members 11 / 12), with the
--           frame table's sprite flights, white fades, particles and SEs
--   OUTRO   (ov119 0x021DFDA0 on) the Pokemon received in the middle, its
--           cry, "{VAR1} sent over / {VAR2}." (#156) and "Take good care of
--           {VAR2}!" (#49)
--
-- The 3D is drawn on the top screen; the sub screen shows the demo's own
-- background (members 0-2). With one screen, only the top.
--
-- APPROXIMATE, said where it is: the Pokemon sprites are the MCSS sprites of
-- the cartridge drawn as flat pictures, their units (the frame table's -500 ..
-- 300) taken as pixels from the screen's centre (the intro's (0, -23) is
-- the sprite standing on the scene's plate that way); the
-- camera's field of view (not found in the overlay) is FOV; the particle
-- emitters are drawn in screen space over the 3D, as the evolution scene's
-- are; the intro's slide is a straight 42-frame move.

local Assets = require("src.render.Assets")
local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
Screen.FOV = 30
Screen.NEAR, Screen.FAR = 1, 4000
Screen.FLIGHT_SCALE = 1
Screen.INTRO_SLIDE = 42
Screen.INTRO_HOLD = 90
Screen.OUTRO_HOLD = 60

local function image(path)
  if type(path) == "table" then path = path.path end
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter("nearest", "nearest") return img end
  return nil
end

local function se(self, id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe and self.data then pcall(Sound.playSe, self.data, id) end
end

local function cry(self, mon)
  if not mon or mon.isEgg then return end
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playCry then pcall(Sound.playCry, self.data, mon.species) end
end

local FALLBACK = {
  [129] = Strings.source("Sending {VAR1} to {VAR2}.\nGood-bye, {VAR1}!"),
  [156] = Strings.source("{VAR1} sent over\n{VAR2}."),
  [49] = "Take good care of {VAR2}!",
}
function Screen.text(data, bank, index, one, two)
  local key = ("TEXT_G5S_%04d_%05d"):format(bank or 159, index)
  local s = ((data or {}).text or {})[key] or Strings(FALLBACK[index] or "")
  local function safe(v) return (tostring(v or ""):gsub("%%", "%%%%")) end
  s = s:gsub("{VAR1}", safe(one)):gsub("{VAR2}", safe(two))
  return (s:gsub("{[^}]*}", ""))
end

local function nameOf(data, mon)
  if not mon then return "" end
  if mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local def = data and data.pokemon and data.pokemon[mon.species]
  return def and def.name or "?"
end

function Screen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({
    game = game, data = game.data, opts = opts,
    art = (game.data or {}).gen5_trade_art or {},
    sending = opts.sending, receiving = opts.receiving, otName = opts.otName or "",
    onDone = opts.onDone, phase = "intro", t = 0, f = 0, white = 0, systems = {},
    flights = {}, pics = {},
  }, Screen)
  return self
end

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end

function Screen:enter()
  local Music = require("src.core.Music")
  local audio = (self.data or {}).audio
  local def = audio and audio.songs and audio.songs[self.art.music or "SEQ_BGM_KOUKAN"]
  if def then pcall(Music.play, self.data, def.nds or def) end
end

-- --------------------------------------------------------------- model --

function Screen:scene()
  if self.sceneModel == nil then
    local rec = self.art.scene and self.art.scene.model
    local ok, m = false, nil
    if rec then ok, m = pcall(require("src.render.Gen4Model").new, rec) end
    self.sceneModel = ok and m or false
    if not ok and rec then Logger.warn("bw trade: scene model failed: %s", tostring(m)) end
  end
  return self.sceneModel or nil
end

local function vec(track, frame)
  if not track then return nil end
  local n = track.frames or 0
  if n <= 0 then return nil end
  local k = math.max(0, math.min(n - 1, frame)) * 3
  local d = track.data
  return { d[k + 1], d[k + 2], d[k + 3] }
end

function Screen:render3D(frame)
  local g = love.graphics
  local Model = require("src.render.Gen4Model")
  local m = self:scene()
  if not m then return end
  if not self.colour then self.colour, self.depth = Model.newTarget(W, H) end
  if not self.colour then return end
  -- push("all") saves and restores the bound canvas: handing getCanvas()'s
  -- answer back to setCanvas crashed when a mod had a depth set bound
  g.push("all")
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 0, true, true)
  g.origin(); g.setScissor(); g.setColor(1, 1, 1, 1)
  local env = os.getenv("G5TRADECAM")
  local fov, near, far = Screen.FOV, Screen.NEAR, Screen.FAR
  if env then
    local v = {}
    for n in env:gmatch("[-%d%.]+") do v[#v + 1] = tonumber(n) end
    fov, near, far = v[1] or fov, v[2] or near, v[3] or far
  end
  local eye = vec(self.art.eye, frame) or { 0, 10, 25 }
  local at = vec(self.art.target, frame) or { 0, 0, 0 }
  local flip = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
  local up
  if math.abs(eye[1] - at[1]) < 1e-6 and math.abs(eye[3] - at[3]) < 1e-6 then up = { 0, 0, -1 } end
  local vp = Model.multiply(flip, Model.multiply(Model.perspective(math.rad(fov), W / H, near, far),
                                                 Model.lookAt(eye, at, up)))
  local motion = self.art.scene.motion
  local Anim = require("src.import.Gen4Anim")
  local mf = math.min(frame, ((motion and motion.frames) or 1) - 1)
  local pose = motion and m:posed(function(node)
    local track = motion.tracks[node]
    return track and Anim.unpackFrame(track, mf) or nil
  end) or nil
  local mats = require("src.render.Gen4TexAnim").materials(self.art.scene.records or {}, mf,
                                                           self.art.scene.model.patternImages)
  local fog = Model.depthFog; Model.depthFog = nil
  local ok, err = pcall(m.draw, m, vp, pose, mats)
  if not ok then Logger.warn("bw trade: scene draw failed: %s", tostring(err)) end
  Model.depthFog = fog
  g.pop()
end

-- -------------------------------------------------------------- sprites --

function Screen:monImage(mon)
  if not mon then return nil end
  self.monPics = self.monPics or {}
  if self.monPics[mon] == nil then
    local ok, path = pcall(function()
      return require("src.pokemon.Sprites").path(self.data, mon.species, "front", { mon = mon })
    end)
    self.monPics[mon] = (ok and image(path)) or false
  end
  return self.monPics[mon] or nil
end

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

-- the first frame of the front sprite (BW's are 96 x 96 animation sheets),
-- centred on (x, y), paled `pale` sixteenths toward white
function Screen:drawMon(mon, x, y, scale, pale)
  local img = self:monImage(mon)
  if not img then return end
  local g = love.graphics
  local w, h = img:getDimensions()
  local size = math.min(w, h, 96)
  self.quads = self.quads or {}
  local q = self.quads[img]
  if not q then q = g.newQuad(0, 0, size, size, w, h); self.quads[img] = q end
  local sh = (pale or 0) > 0 and tint()
  local prev = g.getShader()
  if sh then sh:send("amount", math.min(1, pale / 16)); g.setShader(sh) end
  g.setColor(1, 1, 1, 1)
  scale = scale or 1
  g.draw(img, q, math.floor(x - size * scale / 2), math.floor(y - size * scale / 2), 0, scale, scale)
  g.setShader(prev)
end

-- ------------------------------------------------------------ particles --

function Screen:emit(id)
  local okP, P = pcall(require, "src.battle.Gen4ParticleSystem")
  local sys = okP and self.art.emitters and P.resource(self.art.emitters, id)
  if sys then
    sys:start(97 + id)
    sys.emitterX, sys.emitterY = 0, 0
    self.systems[#self.systems + 1] = sys
  end
end

function Screen:drawParticles()
  local g = love.graphics
  self.particleImages = self.particleImages or {}
  for _, sys in ipairs(self.systems) do
    sys:draw(W / 2, H / 2, function(texture, x, y, sx, sy, alpha, rotation, colour)
      local rec = self.art.images and self.art.images[("particle_%d"):format(texture)]
      local img = rec and self.particleImages[rec.path]
      if rec and img == nil then img = image(rec.path) or false; self.particleImages[rec.path] = img end
      if not img then return end
      local iw, ih = img:getDimensions()
      local c = colour or { 255, 255, 255 }
      g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, math.max(0, math.min(1, tonumber(alpha) or 1)))
      g.draw(img, x, y, rotation or 0, sx or 1, sy or 1, iw / 2, ih / 2)
    end)
  end
  g.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------ the text --

function Screen:say(index, one, two)
  local TextBox = require("src.render.TextBox")
  local text = Screen.text(self.data, self.art.bank, index, one, two)
  local ok, box = pcall(TextBox.new, self.game, text, nil, { stay = {} })
  if not ok then Logger.warn("bw trade: text box failed: %s", tostring(box)) self.box = nil return end
  for _ = 1, 600 do
    if box.done then break end
    pcall(box.update, box, 1 / 60)
  end
  self.box = box
end

-- ----------------------------------------------------------------- flow --

local function lerp(a, b, k) return a + (b - a) * k end

function Screen:demoTick()
  local f = self.f
  for _, row in ipairs(self.art.se or {}) do if row[2] == f then se(self, row[1]) end end
  for _, row in ipairs(self.art.emit or {}) do if row[1] == f then self:emit(row[2]) end end
  for _, row in ipairs(self.art.fades or {}) do
    if row[1] == f then self.fade = { from = self.white, to = row[2], over = row[3], t = 0 } end
  end
  for _, row in ipairs(self.art.flights or {}) do
    if row[1] == f then
      self.flights[row[2]] = { from = row[3], to = row[4], frames = row[5], scale = row[6], t = 0 }
    end
  end
  if f == 1 then self.introPale = 8 elseif f == 2 then self.introPale = 16 elseif f == 4 then self.introGone = true end
  if f == 616 then self.endPale = 8 end
end

function Screen:update()
  self.t = self.t + 1
  local live = {}
  for _, sys in ipairs(self.systems) do if sys:update() then live[#live + 1] = sys end end
  self.systems = live
  if self.fade then
    local fd = self.fade
    fd.t = fd.t + 1
    self.white = lerp(fd.from, fd.to, math.min(1, fd.t / math.max(1, fd.over)))
    if fd.t >= fd.over then self.fade = nil end
  end
  for _, fl in pairs(self.flights) do fl.t = math.min(fl.frames, fl.t + 1) end
  local input = self.game and self.game.input
  local pressed = input and input.wasPressed and (input:wasPressed("a") or input:wasPressed("b"))

  if self.phase == "intro" then
    if self.t == 1 then self:say(129, nameOf(self.data, self.sending), self.otName) end
    if self.t >= Screen.INTRO_SLIDE + Screen.INTRO_HOLD then
      self.box = nil
      self.phase, self.t, self.f = "demo", 0, 0
    end
  elseif self.phase == "demo" then
    self:demoTick()
    self.f = self.f + 1
    if self.f > (self.art.length or 616) then
      self.phase, self.t = "outro", 0
      self.white, self.fade, self.systems = 0, nil, {}
      cry(self, self.receiving)
    end
  elseif self.phase == "outro" then
    if self.t == 1 then self:say(156, self.otName, nameOf(self.data, self.receiving)) end
    if self.t == Screen.OUTRO_HOLD then self:say(49, self.otName, nameOf(self.data, self.receiving)) end
    if self.t >= Screen.OUTRO_HOLD * 2 and (pressed or self.t >= Screen.OUTRO_HOLD * 4) then
      self.phase = "done"
      self.box = nil
      if self.game and self.game.stack and self.game.stack.top and self.game.stack:top() == self then
        self.game.stack:pop()
      elseif self.game and self.game.stack then
        pcall(self.game.stack.pop, self.game.stack)
      end
      pcall(function()
        local Music = require("src.core.Music")
        if Music.restoreMap then Music.restoreMap(self.data) end
      end)
      if self.onDone then self.onDone() end
    end
  end
end

-- ----------------------------------------------------------------- draw --

function Screen:drawTop()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  if self.phase == "intro" then
    local k = math.min(1, self.t / Screen.INTRO_SLIDE)
    self:drawMon(self.sending, W / 2, lerp(H + 48, H / 2 + 23, k), 1, 0)
  elseif self.phase == "demo" then
    self:render3D(self.f)
    if self.colour then g.setColor(1, 1, 1, 1); g.draw(self.colour, 0, 0) end
    if not self.introGone then self:drawMon(self.sending, W / 2, H / 2 + 23, 1, self.introPale or 0) end
    for which, fl in pairs(self.flights) do
      if fl.t < fl.frames then
        local k = fl.t / math.max(1, fl.frames)
        local x = lerp(fl.from[1], fl.to[1], k) * Screen.FLIGHT_SCALE
        local y = lerp(fl.from[2], fl.to[2], k) * Screen.FLIGHT_SCALE
        local mon = which == "sending" and self.sending or self.receiving
        self:drawMon(mon, W / 2 + x, H / 2 - y, fl.scale or 1, self.endPale or 0)
      end
    end
    self:drawParticles()
    if self.white > 0 then
      g.setColor(1, 1, 1, math.min(1, self.white / 16))
      g.rectangle("fill", 0, 0, W, H)
    end
  elseif self.phase == "outro" or self.phase == "done" then
    self:drawMon(self.receiving, W / 2, H / 2 + 23 - 24, 1, 0)
  end
  g.setColor(1, 1, 1, 1)
  if self.box and self.box.draw then pcall(self.box.draw, self.box) end
end

function Screen:drawBottom()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  self.bg = self.bg == nil and (image(self.art.background) or false) or self.bg
  if self.bg then g.setColor(1, 1, 1, 1); g.draw(self.bg, 0, 0) end
end

function Screen:draw()
  self:drawTop()
  local SS = require("src.ui.SecondScreen")
  local dual = SS.separate and SS.separate(self.game)
  if dual and SS.draw then SS.draw(self.game, function() self:drawBottom() end) end
end

-- the harness: both screens, the top at (0, 0) and the bottom at (0, gap)
function Screen:drawScreens(_, bottomY)
  local g = love.graphics
  g.push("all")
  self:drawTop()
  g.translate(0, bottomY or 196)
  self:drawBottom()
  g.pop()
end

function Screen:describe()
  return ("%s particles=%d white=%d"):format(self.phase, #self.systems, math.floor(self.white))
end

return Screen
