-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FEEDING A POKeBLOCK, which on the cartridge is a SCREEN.
--
-- Reported from play: "the menu for feeding pokemon pokeblocks needs to be
-- worked on and look like it does in the actual rom as well".  What the port
-- had was the case, the party menu, and a line of text -- the block vanished,
-- a sentence appeared, and the five numbers that had just changed were
-- nowhere on screen.  Emerald spends a whole screen on it: the Pokemon on the
-- left, the CONDITION pentagon on the right, and the pentagon GROWS as the
-- block goes down, which is the entire point of feeding one.
--
-- WHAT IS DERIVED.  The pentagon is the cartridge's: its centre, its five
-- directions and the non-linear radius table all come from the same
-- constants.gen3Pokenav.condition record the Pokenav's condition page reads,
-- through src/pokemon/Contest.lua, so the shape here and the shape there
-- cannot drift apart.  The three reactions are the cartridge's own sentences
-- (constants.gen3Pokeblocks.text), and what the block is worth is
-- Contest.feed -- the nature table, not a guess.
--
-- WHAT IS RECONSTRUCTED: the LAYOUT and the timing.  The block itself is
-- drawn as its own colour rather than as art, because the import does not
-- lift the fourteen Pokeblock sprites; a coloured block that says which of
-- the fourteen it is beats a placeholder that says nothing.

local Contest = require("src.pokemon.Contest")
local Font = require("src.render.Font")
local Pokeblocks = require("src.inventory.Pokeblocks")
local Strings = require("src.core.Strings")

local Gen3PokeblockFeed = {}
Gen3PokeblockFeed.__index = Gen3PokeblockFeed
Gen3PokeblockFeed.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED: where the two halves of the screen sit, and how long the
-- block takes to go down.
local CENTRE = { x = 168, y = 74 }
local MON_X, MON_FLOOR = 62, 116
local THROW_FRAMES = 26
local EAT_FRAMES = 44

-- The fourteen block colours, in Pokeblocks.COLOUR_FALLBACK's order.  These
-- are the words' own colours rather than the sprites': RED is red.
local SWATCH = {
  { 0.85, 0.26, 0.24 }, { 0.26, 0.40, 0.85 }, { 0.93, 0.55, 0.72 },
  { 0.32, 0.70, 0.34 }, { 0.94, 0.84, 0.30 }, { 0.60, 0.35, 0.78 },
  { 0.35, 0.30, 0.72 }, { 0.55, 0.40, 0.24 }, { 0.50, 0.78, 0.92 },
  { 0.56, 0.60, 0.24 }, { 0.62, 0.62, 0.62 }, { 0.18, 0.18, 0.20 },
  { 0.95, 0.95, 0.95 }, { 0.88, 0.74, 0.28 },
}

function Gen3PokeblockFeed:uiSize() return GBA_W, GBA_H end
function Gen3PokeblockFeed:wantsFillScale() return true end

function Gen3PokeblockFeed:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

local function words(game)
  local r = (game and game.data and game.data.constants or {}).gen3Pokeblocks
  return (r and r.text) or {}
end

local function fill(text, vars)
  if type(text) ~= "string" then return nil end
  return (text:gsub("{VAR(%d)}", function(n)
    return tostring(vars[tonumber(n)] or "")
  end))
end

-- The pentagon's own record, with this screen's centre in place of the
-- Pokenav's: everything else about it -- the five directions, the radius
-- table -- stays the cartridge's.
local function record(game, centre)
  local r = (game.data.constants or {}).gen3Pokenav
  local cond = r and r.condition
  local out = { centre = centre }
  if type(cond) == "table" then
    for k, v in pairs(cond) do
      if k ~= "centre" then out[k] = v end
    end
  end
  return out
end

local function frontSprite(game, mon)
  local path = require("src.pokemon.Sprites").path(
    game.data, mon.species, "front", { mon = mon })
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

function Gen3PokeblockFeed.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3PokeblockFeed)
  self.game = game
  self.mon = opts.mon
  self.block = opts.block
  self.slot = opts.slot
  self.onDone = opts.onDone
  self.sprite = self.mon and frontSprite(game, self.mon) or nil
  self.record = record(game, CENTRE)
  self.t = 0

  -- BEFORE, and then the block goes down.  The pentagon is drawn between the
  -- two, so what the screen shows growing is the change this block made.
  self.before = {}
  for _, key in ipairs(Contest.ORDER) do
    self.before[key] = Contest.graph(self.mon, key)
  end
  self.beforeSheen = Contest.sheenLevel(self.mon, self.record)

  self.deltas = Pokeblocks.feed(game.data, self.mon, self.block)
  self.after = {}
  for _, key in ipairs(Contest.ORDER) do
    self.after[key] = Contest.graph(self.mon, key)
  end

  if not self.deltas then
    -- SHEEN IS A HARD GATE: at 255 the Pokemon refuses the block outright and
    -- nothing changes, the block included.  There is nothing to animate.
    self.phase = "say"
    self:say(words(game).wontEat or Strings("It won't eat any more."))
  else
    if self.slot then Pokeblocks.remove(game.save, self.slot) end
    self.phase = "throw"
  end
  return self
end

function Gen3PokeblockFeed:say(text)
  local game = self.game
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, function()
    game.stack:pop()                      -- this screen
    if self.onDone then self.onDone(self.deltas) end
  end))
end

-- THE CARTRIDGE HAS THREE LINES FOR THIS, one per reaction, and each is a
-- whole sentence rather than a verb to slot into one.
function Gen3PokeblockFeed:reaction()
  local w = words(self.game)
  local liked = (self.deltas and self.deltas.liked) or 0
  local text = (liked > 0 and w.ateHappily)
               or (liked < 0 and w.ateDisdainfully)
               or w.ate
  local who = self.mon.nickname
              or (self.game.data.pokemon[self.mon.species] or {}).name
              or tostring(self.mon.species)
  local name = Pokeblocks.name(self.game.data, self.block)
  return fill(text, { who, name }) or Strings("%s ate the %s.", who, name)
end

function Gen3PokeblockFeed:update()
  self.t = self.t + 1
  if self.phase == "throw" and self.t >= THROW_FRAMES then
    self.phase, self.t = "eat", 0
  elseif self.phase == "eat" and self.t >= EAT_FRAMES then
    self.phase = "say"
    self:say(self:reaction())
  end
end

-- How far through the change the pentagon is drawn: nothing until the block
-- is eaten, then all of it.
function Gen3PokeblockFeed:progress()
  if self.phase == "throw" then return 0 end
  if self.phase == "eat" then return math.min(1, self.t / EAT_FRAMES) end
  return 1
end

function Gen3PokeblockFeed:drawPentagon()
  local rec = self.record
  local centre = rec.centre
  local dirs = Contest.directions(rec)
  local full = Contest.radius(rec, Contest.MAX)
  local p = self:progress()

  love.graphics.setColor(0.10, 0.14, 0.24, 0.85)
  love.graphics.circle("fill", centre.x, centre.y, full + 6)

  love.graphics.setColor(0.42, 0.48, 0.60, 1)
  local outer = {}
  for i in ipairs(Contest.ORDER) do
    outer[#outer + 1] = centre.x + dirs[i].cos * full / 256
    outer[#outer + 1] = centre.y - dirs[i].sin * full / 256
  end
  love.graphics.polygon("line", outer)

  local poly = {}
  for i, key in ipairs(Contest.ORDER) do
    local a, b = self.before[key] or 0, self.after[key] or 0
    local r = Contest.radius(rec, a + (b - a) * p)
    poly[#poly + 1] = centre.x + math.floor(dirs[i].cos * r / 256)
    poly[#poly + 1] = centre.y - math.floor(dirs[i].sin * r / 256)
  end
  love.graphics.setColor(0.98, 0.78, 0.30, 0.75)
  if #poly >= 6 then love.graphics.polygon("fill", poly) end
  love.graphics.setColor(1, 0.94, 0.62, 1)
  if #poly >= 6 then love.graphics.polygon("line", poly) end

  love.graphics.setColor(1, 1, 1, 1)
  for i, key in ipairs(Contest.ORDER) do
    local word = key:upper()
    local w = Font.width(word)
    local x = centre.x + dirs[i].cos * (full + 22) / 256
    local y = centre.y - dirs[i].sin * (full + 22) / 256
    if dirs[i].cos > 0.25 * 256 then x = x + 2
    elseif dirs[i].cos < -0.25 * 256 then x = x - w - 2
    else x = x - w / 2 end
    Font.draw(word, math.floor(x), math.floor(y - Font.glyphHeight() / 2))
  end
end

function Gen3PokeblockFeed:draw()
  love.graphics.setColor(0.24, 0.30, 0.20, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)

  self:drawPentagon()

  -- the Pokemon, bobbing once while it eats
  if self.sprite then
    local w, h = self.sprite:getDimensions()
    local bob = 0
    if self.phase == "eat" then
      bob = -3 * math.abs(math.sin(self.t * math.pi / 11))
    end
    local x = math.floor(MON_X - w / 2)
    local y = math.floor(MON_FLOOR - h + bob)
    love.graphics.draw(self.sprite, x, y)
    require("src.render.PaletteFX").markTrueColor(x, y, w, h)
  end

  -- the block on its way in
  if self.phase == "throw" and self.block then
    local p = self.t / THROW_FRAMES
    local x = GBA_W - 24 - (GBA_W - 24 - MON_X) * p
    local y = GBA_H - 24 - 56 * math.sin(p * math.pi)
    local colour = math.floor(tonumber(self.block.colour) or 0)
    local rgb = SWATCH[colour] or { 0.8, 0.8, 0.8 }
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", x - 6, y - 6, 13, 13)
    love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
    love.graphics.rectangle("fill", x - 5, y - 5, 11, 11)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- SHEEN, which is what a block SPENDS, next to what it buys
  Font.drawBox(0, 0, 13, 4)
  love.graphics.setColor(0, 0, 0, 1)
  local who = self.mon and (self.mon.nickname
    or (self.game.data.pokemon[self.mon.species] or {}).name) or ""
  Font.draw(tostring(who), 8, 8)
  Font.draw(Strings("SHEEN %d", Contest.sheenLevel(self.mon, self.record)),
            8, 20)
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3PokeblockFeed
