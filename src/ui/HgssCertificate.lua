-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S CERTIFICATES (`ShowCertificate <id>`,
-- pokeheartgold src/certificates_app.c): 0 the Johto Pokedex diploma (the
-- Goldenrod Game Freak office), 1 the National Pokedex diploma, 2 the Shiny
-- Leaf crown's certificate. Art: src/import/Gen4HgssCertificates.lua.
--
-- The text is msg_0004 in MAKE_TEXT_COLOR(1, 2, 0) on the standard font
-- palette (ov78_021E6068):
--   diplomas  #0 "PLAYER: <name>" at (48, 32), the body (#1 / #2) at (64, 64),
--             #3 "GAME FREAK" at (138, 144)
--   leaves    #4 "<player> and <first party mon>" at y 36, #5 at y 56, both
--             centred ({ALN_CENTER})
-- The run (CertificatesApp_Main): fade in, a second's pause, the sheet scrolls
-- from the top screen down to the bottom one, then A / B / a touch fades out.
-- One screen: fade in, wait for the press, fade out.
--
-- Not drawn: the Shiny Leaf certificate's 3D model of the Pokemon
-- (data/mmodel), which stands at its foot on the cartridge.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")

local C = {}
C.__index = C
C.isOpaque = true

local W, H = 256, 192
local FADE = 16          -- frames: FADE_TYPE 0, 6-step brightness ramp
local PAUSE = 60         -- CERTIFICATES_EXECSTATE_WAIT_ONE_SECOND
local SCROLL = 8         -- pixels a frame, top screen to bottom
C.TEXT_BANK = 4

function C:uiSize() return W, H end
function C:wantsFillScale() return true end

function C.available(game, id)
  local rec = game and game.data and game.data.gen4_hgss_certificates
  local certs = rec and rec.certificates
  return certs ~= nil and certs[id or 0] ~= nil
end

local function firstMon(save)
  for _, mon in ipairs(save and save.party or {}) do
    if mon and not mon.isEgg then return mon end
  end
end

function C.new(game, id, onDone)
  id = math.floor(tonumber(id) or 0)
  if id < 0 or id > 2 then id = 0 end
  local data = game.data or {}
  local self = setmetatable({
    game = game, id = id, onDone = onDone, images = {},
    rec = data.gen4_hgss_certificates or {},
    frame = 0, state = "in", scroll = 0,
  }, C)
  self.cert = self.rec.certificates and self.rec.certificates[id] or {}
  local save = game.save or {}
  local player = save.player and save.player.name or "PLAYER"
  local mon = firstMon(save)
  local def = mon and data.pokemon and data.pokemon[mon.species]
  local nick = mon and (mon.nickname or (def and def.name)) or ""
  -- the certificate's own template: slot 0 the player, slot 1 the first
  -- party Pokemon (the bank's {STRVAR_1 3 0 0} / {STRVAR_1 1 1 0}); the
  -- shared Gen 4 markup expands them line by line in printBlock, after the
  -- line's {ALN_CENTER} has been read
  self.buffers = {}
  require("src.import.Gen4Text").buffer(self.buffers, player, nick)
  local function line(n)
    local t = data.text and data.text[("TEXT_B%04d_%05d"):format(C.TEXT_BANK, n)]
    return type(t) == "string" and t or ""
  end
  if id == 2 then
    self.lines = { { line(4), 0, 36 }, { line(5), 0, 56 } }
  else
    self.lines = { { line(0), 48, 32 }, { line(id == 1 and 2 or 1), 64, 64 }, { line(3), 138, 144 } }
  end
  return self
end

function C:img(entry)
  if not (entry and entry.path) then return nil end
  local hit = self.images[entry.path]
  if hit == nil then
    local ok, i = pcall(Assets.image, entry.path)
    if ok and i then i:setFilter("nearest", "nearest") end
    hit = (ok and i) or false
    self.images[entry.path] = hit
  end
  return hit or nil
end

local function pressed(game)
  local input = game.input
  if not input then return false end
  if input:wasPressed("a") or input:wasPressed("b") then return true end
  return input.wasTouched and input:wasTouched() or false
end

function C:dualScreen()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return false end
  return SS.separateMode(SS.mode(self.game)) and not (SS.stowed and SS.stowed(self.game)), SS
end

function C:update()
  self.frame = self.frame + 1
  if self.state == "in" then
    if self.frame >= FADE then self.state, self.frame = "pause", 0 end
  elseif self.state == "pause" then
    if self.frame >= PAUSE then
      self.state, self.frame = (self:dualScreen() and "scroll" or "wait"), 0
    end
  elseif self.state == "scroll" then
    self.scroll = math.min(H, self.scroll + SCROLL)
    if self.scroll >= H then self.state, self.frame = "wait", 0 end
  elseif self.state == "wait" then
    if pressed(self.game) then
      pcall(function() require("src.core.Sound").playSe(self.game.data, "SEQ_SE_DP_SELECT") end)
      self.state, self.frame = "out", 0
    end
  elseif self.state == "out" then
    if self.frame >= FADE then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

local function setInk(c)
  if c then love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
  else love.graphics.setColor(0.29, 0.29, 0.29, 1) end
end

-- the DS prints the shadow right, down and diagonally under the letter
local function shadowed(s, x, y, ink)
  if ink and ink[2] then
    setInk(ink[2]); Font.draw(s, x + 1, y); Font.draw(s, x, y + 1); Font.draw(s, x + 1, y + 1)
  end
  setInk(ink and ink[1]); Font.draw(s, x, y)
end

-- one text block: lines 16 px apart, {ALN_CENTER} lines centred in the screen
function C:printBlock(text, x, y)
  local ink = self.rec.ink
  for raw in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    local centre = raw:find("{ALN_CENTER}", 1, true) ~= nil
    local ok, plain = pcall(require("src.script.Commands").gen4Markup, raw, self.buffers)
    local s = ((ok and type(plain) == "string") and plain or raw):gsub("{[^}]*}", "")
    local px = centre and math.floor((W - Font.width(s)) / 2) or x
    shadowed(s, px, y, ink)
    y = y + 16
  end
end

function C:drawSheet(oy)
  local g = love.graphics
  local bd = self.cert.backdrop
  g.setColor(bd and bd[1] / 255 or 1, bd and bd[2] / 255 or 1, bd and bd[3] / 255 or 1, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local back, front = self:img(self.cert.back), self:img(self.cert.front)
  if back then g.draw(back, 0, 0) end
  if front then g.draw(front, 0, oy) end
  for _, l in ipairs(self.lines) do self:printBlock(l[1], l[2], l[3] + oy) end
  g.setColor(1, 1, 1, 1)
end

function C:veil()
  local f = 0
  if self.state == "in" then f = 1 - self.frame / FADE
  elseif self.state == "out" then f = self.frame / FADE end
  if f > 0 then
    love.graphics.setColor(0, 0, 0, math.min(1, f))
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- BOTH SCREENS hold the sheet; the BG1 frame and the text scroll together
-- (ov78_021E5E54: main BG Y = s, sub = s + 192, s running 0 -> -192 over a
-- 512-row map whose sheet is rows 0..191), so it slides down off the top
-- screen as it arrives on the bottom one. The BG3 back stays put on each.
function C:draw()
  local dual, SS = self:dualScreen()
  if dual then
    love.graphics.push("all")
    love.graphics.setScissor()
    self:drawSheet(self.scroll)
    self:veil()
    love.graphics.pop()
    SS.draw(self.game, function() self:drawSheet(self.scroll - H); self:veil() end)
  else
    self:drawSheet(0)
    self:veil()
  end
end

return C
