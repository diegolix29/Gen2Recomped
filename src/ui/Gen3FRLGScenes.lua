-- FIRERED'S SMALL ONE-OFF SCREENS, drawn from the art extractFireRedExtraArt
-- took out of the ROM (constants.gen3FRLGArt):
--
--   Diploma    diploma.c -- the Kanto or national certificate and its words
--   Seagallop  seagallop.c -- the ferry crossing the scrolling sea
--
-- Each is a plain stack state that calls onDone once when it leaves.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Sound = require("src.core.Sound")

local W, H = 240, 160
local Scenes = {}

local function art(game)
  local c = game and game.data and game.data.constants
  return c and c.gen3FRLGArt or nil
end
Scenes.art = art

local function image(path)
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  return ok and img or nil
end

-- ---------------------------------------------------------------------------
-- DIPLOMA (ShowDiploma).  HasAllMons picks the national sheet -- the same
-- 64-tile-wide background scrolled by BG1HOFS 0x100 -- and the national line.
-- ---------------------------------------------------------------------------
local Diploma = {}
Diploma.__index = Diploma
Diploma.isOpaque = true
function Diploma:uiSize() return W, H end
function Diploma:wantsFillScale() return true end
function Diploma:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Diploma.new(game, opts)
  local a = art(game)
  if not (a and a.diploma) then return nil end
  local self = setmetatable({ game = game, onDone = opts and opts.onDone,
                              national = opts and opts.national, rec = a.diploma,
                              frame = 0 }, Diploma)
  return self
end

function Diploma:update()
  self.frame = self.frame + 1
  local input = self.game.input
  if self.frame > 8 and (input:wasPressed("a") or input:wasPressed("b")) then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function Diploma:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, math.min(1, self.frame / 16))
  local img = image(self.national and self.rec.national or self.rec.kanto)
  if img then g.draw(img, 0, 0) end
  local t = self.rec.text or {}
  local player = ((self.game.save or {}).player or {}).name or ""
  local dex = self.national and (t.national or "NATIONAL") or (t.kanto or "KANTO")
  local function fill(s)
    s = tostring(s or "")
    s = s:gsub("{DYNAMIC 0}", player):gsub("{DYNAMIC 1}", dex)
    s = s:gsub("{STR_VAR_1}", player):gsub("{STR_VAR_2}", dex)
    return s
  end
  local function centred(s, y)
    local line = 0
    for piece in (s .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(piece, math.floor(120 - Font.width(piece) / 2), y + line * 14)
      line = line + 1
    end
  end
  centred(fill(t.player), 16 + 4)
  centred(fill(t.document), 16 + 30)
  Font.draw(fill(t.gameFreak), 120, 16 + 105)
  g.setColor(1, 1, 1, 1)
end

function Diploma:keypressed() end
Scenes.Diploma = Diploma

-- ---------------------------------------------------------------------------
-- SEAGALLOP (DoSeagallopFerryScene).  The sea scrolls 6px a frame the way
-- the ferry is heading, the ferry crosses at 3px a frame from one edge, a
-- wake puff drops behind it every fifth frame, and after 140 frames the
-- screen fades out and the warp is taken.  Only rows 24..136 are drawn
-- (WIN0V 0x1888); the rest is black.
-- ---------------------------------------------------------------------------
local Seagallop = {}
Seagallop.__index = Seagallop
Seagallop.isOpaque = true
function Seagallop:uiSize() return W, H end
function Seagallop:wantsFillScale() return true end
Seagallop.sgbPalettes = Diploma.sgbPalettes

function Seagallop.new(game, opts)
  local a = art(game)
  if not (a and a.seagallop) then return nil end
  local rec = a.seagallop
  local origin, dest = opts.origin or 0, opts.dest or 0
  local bits = (rec.matrix or {})[origin + 1] or 0
  local east = math.floor(bits / 2 ^ dest) % 2 == 1
  local self = setmetatable({ game = game, onDone = opts.onDone, rec = rec, east = east,
                              frame = 0, bgX = 0, ferryX = east and 0 or 240, wakes = {},
                              fade = 0 }, Seagallop)
  pcall(Sound.play, game.data, "SE_SHIP")
  return self
end

function Seagallop:update()
  self.frame = self.frame + 1
  self.bgX = (self.bgX + (self.east and 6 or -6)) % 256
  local dx = self.east and 3 or -3
  self.ferryX = self.ferryX + dx
  if self.frame % 5 == 1 then
    self.wakes[#self.wakes + 1] = { x = self.ferryX, age = 0 }
  end
  for i = #self.wakes, 1, -1 do
    local w = self.wakes[i]
    w.age = w.age + 1
    if w.age >= 55 then table.remove(self.wakes, i) end
  end
  if self.frame >= 140 then
    self.fade = math.min(1, self.fade + 1 / 16)
    if self.fade >= 1 and not self.done then
      self.done = true
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

function Seagallop:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  local bg = image(self.east and self.rec.east or self.rec.west)
  if bg then
    g.setColor(1, 1, 1, 1)
    local x = -self.bgX
    for k = -1, 1 do g.draw(bg, x + k * 256, 0) end
    local wake = image(self.rec.wake)
    local ferry = image(self.rec.ferry)
    local flip = self.east and -1 or 1
    if wake then
      for _, w in ipairs(self.wakes) do
        local f = w.age < 20 and 0 or (w.age < 40 and 1 or 2)
        local quad = love.graphics.newQuad(f * 32, 0, 32, 32, wake:getDimensions())
        g.draw(wake, quad, w.x, 92, 0, flip, 1, 16, 16)
      end
    end
    if ferry then g.draw(ferry, self.ferryX, 92, 0, flip, 1, 32, 32) end
    -- the window: only rows 24..136 show the sea
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, W, 24)
    g.rectangle("fill", 0, 136, W, H - 136)
  end
  if self.fade > 0 then
    g.setColor(0, 0, 0, self.fade)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

function Seagallop:keypressed() end
Scenes.Seagallop = Seagallop

return Scenes
