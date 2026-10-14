-- Black and White's gift box: the starter choice in the player's room.
--
-- The bedroom script (Nuvema's zone, archive member 782) opens it with
-- command 0x153 <var> and reads 0, 1 or 2 back out of the var -- Snivy,
-- Tepig, Oshawott (495 / 498 / 501, the species the script sets for each
-- answer). See Gen5ScriptLink's 0x153.
--
-- THE WORDS are the cartridge's, story bank 430 (the room's own bank):
--   12  Professor Juniper's letter, shown when the box opens
--   16..18  "The Water/Fire/Grass-type Pokemon <species>"
--   19  "Choose a Pokemon."   20  "Is this the Pokemon you want?"
--   22 / 23  YES / NO
--
-- WHAT THIS FILE INVENTS: the layout. The cartridge's app (the box lid, the
-- three balls on their cushion) has its own graphics archive that is not
-- extracted yet; until it is, the three balls are drawn as a row of name
-- plates with the species' picture when the cache has one. The flow -- letter,
-- pick, confirm with YES / NO, no way out without a choice -- is the
-- cartridge's.

local Font = require("src.render.Font")
local Sprites = require("src.pokemon.Sprites")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
local BANK = 430
-- the script's answers, in its order
Screen.SPECIES = { 495, 498, 501 }
-- which type line names each: Grass 18, Fire 17, Water 16
local TYPE_LINE = { 18, 17, 16 }

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end
function Screen:wantsEdgeBleed() return false end

function Screen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Screen)
  self.game = game
  self.species = opts.species or Screen.SPECIES
  self.onChoose = opts.onChoose
  self.text = (game.data or {}).text or {}
  self.index = 1
  self.yes = true
  self.state = "letter"     -- letter, pick, confirm
  return self
end

function Screen:line(entry)
  local s = self.text[("TEXT_B%04d_%05d"):format(BANK, entry)] or ""
  local def = (self.game.data.pokemon or {})[self.species[self.index]]
  s = s:gsub("{CMD %x+}", ""):gsub("{VAR2}", def and def.name or "")
  return (s:gsub("%s+$", ""))
end

function Screen:update()
  local input = self.game.input
  if not input then return end
  if self.state == "letter" then
    if input:wasPressed("a") or input:wasPressed("b") then self.state = "pick" end
  elseif self.state == "pick" then
    local n = #self.species
    if input:wasPressed("right") then self.index = self.index % n + 1
    elseif input:wasPressed("left") then self.index = (self.index - 2) % n + 1
    elseif input:wasPressed("a") then self.state, self.yes = "confirm", true end
  else
    if input:wasPressed("up") or input:wasPressed("down") then
      self.yes = not self.yes
    elseif input:wasPressed("b") or (input:wasPressed("a") and not self.yes) then
      self.state = "pick"
    elseif input:wasPressed("a") then
      self.game.stack:pop()
      if self.onChoose then self.onChoose(self.index - 1, self.species[self.index]) end
    end
  end
end

function Screen:picture(species)
  self.pics = self.pics or {}
  if self.pics[species] == nil then
    local ok, img = pcall(function()
      local path = Sprites.path(self.game.data, species, "front")
      return path and require("src.render.Assets").image(path)
    end)
    self.pics[species] = ok and img or false
  end
  return self.pics[species] or nil
end

local function drawLines(text, x, y)
  for row in (text .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(row, x, y)
    y = y + 16
  end
end

function Screen:draw()
  local g = love.graphics
  g.setColor(0.93, 0.89, 0.80, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.state == "letter" then
    Font.drawBox(1, 1, 30, 16)
    g.setColor(0, 0, 0, 1)
    drawLines(self:line(12), 16, 16)
    g.setColor(1, 1, 1, 1)
    return
  end
  -- the three balls
  for i, species in ipairs(self.species) do
    local cx = 40 + (i - 1) * 88
    if i == self.index then
      g.setColor(1, 0.85, 0.3, 1)
      g.rectangle("fill", cx - 34, 20, 68, 84)
    end
    g.setColor(0.85, 0.15, 0.15, 1)
    g.circle("fill", cx, 90, 10)
    g.setColor(1, 1, 1, 1)
    g.arc("fill", cx, 90, 10, 0, math.pi)
    local pic = i == self.index and self:picture(species)
    if pic then
      local pw, ph = pic:getDimensions()
      local s = 64 / math.max(pw, ph)
      g.draw(pic, cx - pw * s / 2, 22, 0, s, s)
    end
  end
  Font.drawDialogueBox(1, 18, 30, 6)
  g.setColor(0, 0, 0, 1)
  if self.state == "pick" then
    drawLines(self:line(TYPE_LINE[self.index] or 19), 16, 152)
  else
    drawLines(self:line(20), 16, 152)
  end
  g.setColor(1, 1, 1, 1)
  if self.state == "confirm" then
    Font.drawBox(23, 10, 8, 6)
    g.setColor(0, 0, 0, 1)
    Font.draw(self:line(22), 26 * 8, 12 * 8)
    Font.draw(self:line(23), 26 * 8, 14 * 8)
    Font.draw(">", 24 * 8 + 4, (self.yes and 12 or 14) * 8)
    g.setColor(1, 1, 1, 1)
  end
end

return Screen
