-- FIRERED'S HALL OF FAME, beat for beat from pokefirered hall_of_fame.c.
--
--   each team member flies in from off screen (sHallOfFame_Mon*Positions:
--     15px a step across, 10px down) to its place in a 3+3 or 1x3 layout,
--     cries, and its line is printed at the bottom -- 120 frames each; the
--     ones already standing dim toward the backdrop
--   "Welcome to the HALL OF FAME!", applause, and 400 frames in which confetti
--     is thrown every fourth frame until 110 are left
--   the team dims, the player's own pic steps in at (120,72), waits 120
--     frames and walks right to x=192; the NAME / IDNo. / TIME window opens at
--     tile (2,2) and "LEAGUE CHAMPION! CONGRATULATIONS!" sits in the dialogue
--     box until A
--
-- The art is the ROM's: the band backdrop (constants.gen3HallOfFame), the
-- confetti sheet (constants.gen3FRLGArt.confetti) and the pics the battle
-- screens already use.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local Sprites = require("src.pokemon.Sprites")

local W, H = 240, 160
local HOF = {}
HOF.__index = HOF
HOF.isOpaque = true
function HOF:uiSize() return W, H end
function HOF:wantsFillScale() return true end
function HOF:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

local FULL = { { 120, 210, 120, 40 }, { 326, 220, 56, 40 }, { -86, 220, 184, 40 },
               { 120, -62, 120, 88 }, { -70, -92, 200, 88 }, { 310, -92, 40, 88 } }
local HALF = { { 120, 234, 120, 64 }, { 326, 244, 56, 64 }, { -86, 244, 184, 64 } }

local function image(path)
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  return ok and img or nil
end

function HOF.new(game, record, onDone)
  local self = setmetatable({ game = game, record = record, text = record.text or {},
                              onDone = onDone, mons = {}, confetti = {}, frame = 0 }, HOF)
  self.party = {}
  for _, mon in ipairs((game.save and game.save.party) or {}) do
    if mon and mon.species then self.party[#self.party + 1] = mon end
  end
  local layout = #self.party > 3 and FULL or HALF
  for i, mon in ipairs(self.party) do
    local p = layout[i] or layout[#layout]
    local ok, path = pcall(Sprites.path, game.data, mon.species, "front", { mon = mon })
    self.mons[i] = { mon = mon, x = p[1], y = p[2], dx = p[3], dy = p[4],
                     img = ok and image(path) or nil, dim = 0 }
  end
  local c = game.data.constants or {}
  local art = c.gen3FRLGArt
  self.confettiImg = art and art.confetti and image(art.confetti.image)
  local save = game.save or {}
  local who = ((save.player or {}).gender == "girl" or (save.player or {}).female) and "girl" or "boy"
  local forms = ((game.data.field or {}).playerForms or {})[who]
  self.playerImg = forms and image(forms.card)
  self.bg = image(record.background)
  self.phase, self.index, self.timer = "fly", 1, 0
  return self
end

function HOF:enter()
  pcall(Music.play, self.game.data, "Music_HallOfFame")
end

function HOF:finish()
  if self.done then return end
  self.done = true
  self.game.stack:pop()
  local okC, Credits = pcall(require, "src.ui.Gen3Credits")
  local credits = okC and Credits.new(self.game, self.onDone) or nil
  if credits then self.game.stack:push(credits)
  elseif self.onDone then self.onDone() end
end

local function approach(v, target, step)
  if v < target then return math.min(target, v + step) end
  if v > target then return math.max(target, v - step) end
  return v
end

function HOF:update()
  self.frame = self.frame + 1
  local input = self.game.input
  for _, m in ipairs(self.mons) do
    if m.dimTarget then m.dim = approach(m.dim, m.dimTarget, 1 / 16) end
  end
  if self.phase == "fly" then
    local m = self.mons[self.index]
    if not m then self.phase, self.timer = "welcome", 400
      pcall(Sound.play, self.game.data, "SE_APPLAUSE")
      for _, o in ipairs(self.mons) do o.dimTarget = 0 end
      return
    end
    m.shown = true
    if m.x ~= m.dx or m.y ~= m.dy then
      m.x, m.y = approach(m.x, m.dx, 15), approach(m.y, m.dy, 10)
    else
      pcall(Sound.playCry, self.game.data, m.mon.species)
      self.phase, self.timer = "hold", 120
    end
  elseif self.phase == "hold" then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.mons[self.index].dimTarget = 12 / 16
      self.index = self.index + 1
      self.phase = "fly"
    end
  elseif self.phase == "welcome" then
    self.timer = self.timer - 1
    if self.timer % 4 == 0 and self.timer > 110 and self.confettiImg then
      self.confetti[#self.confetti + 1] = { x = math.random(0, 239), y = -math.random(0, 7), y2 = 0,
                                            frame = math.random(0, 16), fast = math.random(0, 3) == 0,
                                            sine = 0 }
    end
    if self.timer <= 0 then
      for _, o in ipairs(self.mons) do o.dimTarget = 12 / 16 end
      self.phase, self.timer = "player", 120
      self.playerX = 120
    end
  elseif self.phase == "player" then
    if self.timer > 0 then self.timer = self.timer - 1
    elseif self.playerX < 192 then self.playerX = self.playerX + 1
    else self.phase = "champion" end
  elseif self.phase == "champion" then
    if input:wasPressed("a") then
      self.phase, self.timer = "exit", 16
    end
  elseif self.phase == "exit" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self:finish() end
  end
  for i = #self.confetti, 1, -1 do
    local c = self.confetti[i]
    c.y2 = c.y2 + 1 + (c.fast and 1 or 0)
    c.sine = (c.sine + 4) % 256
    c.x2 = math.floor((math.random(0, 3) + 8) * math.sin(c.sine / 256 * 2 * math.pi))
    if c.y2 > 120 then table.remove(self.confetti, i) end
  end
end

local function monLine(self, m)
  local def = (self.game.data.pokemon or {})[m.mon.species] or {}
  local number = tonumber(def.dex)
  local dexNo = (self.text.dexNo or "No. ") .. (number and ("%03d"):format(number) or "???")
  local nick = m.mon.nickname or def.name or ""
  local gender = ""
  if m.mon.gender == "male" then gender = "♂" elseif m.mon.gender == "female" then gender = "♀" end
  return dexNo, nick, "/" .. tostring(def.name or "") .. gender,
         (self.text.level or "Lv. ") .. tostring(m.mon.level or 0),
         (self.text.idNo or "IDNo.") .. ("%05d"):format((tonumber(m.mon.otId) or tonumber(((self.game.save or {}).player or {}).id) or 0) % 65536 % 100000)
end

function HOF:drawText(s, x, y)
  love.graphics.setColor(1, 1, 1, 1)
  Font.draw(s, x, y)
end

function HOF:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.bg then g.draw(self.bg, 0, 0) end
  for _, m in ipairs(self.mons) do
    if m.shown and m.img then
      local w, h = m.img:getDimensions()
      local v = 1 - (m.dim or 0) * 0.55
      g.setColor(v, v, v * 1.02, 1)
      g.draw(m.img, math.floor(m.x - w / 2), math.floor(m.y - h / 2))
    end
  end
  g.setColor(1, 1, 1, 1)
  if self.confettiImg then
    local iw, ih = self.confettiImg:getDimensions()
    for _, c in ipairs(self.confetti) do
      local q = g.newQuad(c.frame * 8, 0, 8, 8, iw, ih)
      g.draw(self.confettiImg, q, c.x + (c.x2 or 0) - 4, c.y + c.y2 - 4)
    end
  end
  local faced = Font.pushFace and Font.pushFace("small")
  if self.phase == "hold" then
    local m = self.mons[self.index]
    local dexNo, nick, species, level, id = monLine(self, m)
    local by = 14 * 8
    Font.draw(dexNo, 16 + 16, by + 1 + 4)
    Font.draw(nick, 16 + 128 - Font.width(nick), by + 1 + 4)
    Font.draw(species, 16 + 128, by + 1 + 4)
    Font.draw(level, 16 + 32, by + 17 + 4)
    Font.draw(id, 16 + 96, by + 17 + 4)
  elseif self.phase == "welcome" then
    local s = tostring(self.text.welcome or "")
    Font.draw(s, math.floor(16 + (208 - Font.width(s)) / 2), 15 * 8 + 1 + 4)
  elseif self.phase == "player" or self.phase == "champion" or self.phase == "exit" then
    if self.playerImg then
      local w, h = self.playerImg:getDimensions()
      g.draw(self.playerImg, math.floor((self.playerX or 120) - w / 2), math.floor(72 - h / 2))
    end
    if self.phase ~= "player" then
      Font.drawBox(2, 2, 17, 6)
      local save = self.game.save or {}
      local p = save.player or {}
      local inner = 17 * 8 - 6
      local x0, y0 = 2 * 8 + 8, 2 * 8 + 8
      Font.draw(tostring(self.text.name or "NAME"), x0 + 4, y0 + 3 - 8)
      local name = tostring(p.name or "")
      Font.draw(name, x0 + inner - Font.width(name) - 8, y0 + 3 - 8)
      Font.draw(tostring(self.text.idNo or "IDNo."), x0 + 4, y0 + 18 - 8)
      Font.draw(("%05d"):format((tonumber(p.id) or 0) % 100000), x0 + inner - 38, y0 + 18 - 8)
      Font.draw(tostring(self.text.time or "TIME"), x0 + 4, y0 + 32 - 8)
      local secs = tonumber(save.playTime or save.playSeconds) or 0
      local hours = math.floor(secs / 3600)
      Font.draw(("%3d:%02d"):format(hours, math.floor(secs / 60) % 60), x0 + inner - 44, y0 + 32 - 8)
      Font.drawBox(0, 14, 30, 6)
      local champ = tostring(self.text.champion or "")
      local line = 0
      for piece in (champ .. "\n"):gmatch("([^\n]*)\n") do
        if piece ~= "" then
          Font.draw(piece, 16, 15 * 8 + 4 + line * 16)
          line = line + 1
        end
      end
    end
  end
  if faced and Font.popFace then Font.popFace() end
  if self.phase == "exit" then
    g.setColor(0, 0, 0, 1 - self.timer / 16)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

function HOF:keypressed() end

return HOF
