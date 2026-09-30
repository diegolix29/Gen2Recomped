-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MINING GAME'S SCREEN.
--
-- Everything under it is already built and measured: `Gen4Mining` is what can be
-- buried, `Gen4MiningWall` puts it in a wall, `Gen4MiningSpots` says which walls
-- may be dug and `Gen4MiningDig` is the rules.  This draws it and takes the taps.
--
-- IT IS PLAYED WITH A FINGER AND NOTHING ELSE, which is why `Game:touchpressed`
-- had to learn to offer a pointer to the top state first.  Platinum has no button
-- binding for this to copy: the whole game is the bottom screen.  The d-pad
-- selects nothing here, and B is the port's own way out rather than the
-- cartridge's -- see `close` below.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")
local Bag = require("src.inventory.Bag")
local Mining = require("src.import.Gen4Mining")
local MiningWall = require("src.world.Gen4MiningWall")
local Dig = require("src.world.Gen4MiningDig")

local Gen4MiningScreen = {}
Gen4MiningScreen.__index = Gen4MiningScreen
Gen4MiningScreen.name = "Gen4MiningScreen"

local W, H = 256, 192

-- A mining cell is 2x2 tiles and the grid starts four tile rows down, which is
-- the cartridge's own arithmetic read backwards:
--
--     x = touchX / (TILE_WIDTH_PIXELS * 2);
--     y = touchY / (TILE_HEIGHT_PIXELS * 2) - 2;
--
-- so a cell is 16px and the grid's top edge is at 2 cells = 32px.  The grid is
-- 13x10, which puts its right edge at 208 -- and 208 is exactly the sidebar
-- test, `touchX >= MINING_GAME_WIDTH * 2 * TILE_WIDTH_PIXELS`.
local CELL = 16
local GRID_X, GRID_Y = 0, 32
local SIDEBAR_X = 208

-- sHammerButtonRectangle and sPickaxeButtonRectangle, in TILES, converted once.
-- Both are `for y = startY; y < endY`, so the ends are exclusive.
local HAMMER  = { x = 26 * 8, y = 6 * 8,  w = (32 - 26) * 8, h = (14 - 6) * 8 }
local PICKAXE = { x = 26 * 8, y = 15 * 8, w = (32 - 26) * 8, h = (23 - 15) * 8 }

-- WHICH 2x2 QUAD OF `dirt_tiles` EACH LAYER USES.  The sheet is 32 tiles in a
-- 16x2 grid (the NCGR says so), and Mining_DrawDirt names the four tile indices
-- per layer:
--
--   layer 0 { 14, 15, 30, 31 }   layer 4 { 4, 5, 20, 21 }
--   layer 1 { 10, 11, 26, 27 }   layer 5 { 2, 3, 18, 19 }
--   layer 2 {  8,  9, 24, 25 }   layer 6 { 0, 1, 16, 17 }
--   layer 3 {  6,  7, 22, 23 }
--
-- Index 14 and 15 are row 0 columns 14 and 15; 30 and 31 are row 1 of the same
-- columns.  So each layer is a column PAIR, and the pairs are 14, 10, 8, 6, 4, 2,
-- 0 -- which skips 12.  COLUMNS 12 AND 13 ARE NEVER DRAWN: the sheet holds eight
-- quads and the game uses seven, and the unused one is in the middle rather than
-- at the end.  Worth writing down because a reader deriving the column as
-- `14 - 2 * layer` gets the right answer for layer 0 and is wrong from layer 1 on.
local DIRT_COLUMN = { [0] = 14, [1] = 10, [2] = 8, [3] = 6, [4] = 4, [5] = 2, [6] = 0 }

-- The crack across the top.  Four tile rows at screen tile column 25, growing
-- LEFTWARD as the wall weakens (`tilemapBuffer[CRACK_START... - i]`), with the
-- art taken from the interface sheet at column 11 - (i % 3) of rows 0..3 --
-- the sheet is 54 tiles wide, which is what the base tiles 11, 65, 119 and 173
-- are: column 11 of each of the first four rows.
local CRACK_END_TILE = 25
local CRACK_ROWS = 4
local CRACK_SHEET_COLUMN = 11
local CRACK_SHEET_WIDTH = 54

-- PUBLISHED so a check can exercise the decisions this screen actually makes
-- rather than a second copy of them. Pass 134 was a lesson in that: assertions
-- written against a constant table and a model rebuilt inside the test passed
-- happily while the shipped function did something else.
Gen4MiningScreen.LAYOUT = {
  CELL = CELL, GRID_X = GRID_X, GRID_Y = GRID_Y, SIDEBAR_X = SIDEBAR_X,
  HAMMER = HAMMER, PICKAXE = PICKAXE, DIRT_COLUMN = DIRT_COLUMN,
  CRACK_END_TILE = CRACK_END_TILE, CRACK_ROWS = CRACK_ROWS,
  CRACK_SHEET_COLUMN = CRACK_SHEET_COLUMN, CRACK_SHEET_WIDTH = CRACK_SHEET_WIDTH,
}

-- Which cell a bottom-screen point is, or nil and why not. The inverse of the
-- cartridge's `touchX / 16` and `touchY / 16 - 2`.
function Gen4MiningScreen.cellAt(x, y)
  if x >= SIDEBAR_X then return nil, "sidebar" end
  if y < GRID_Y then return nil, "crack" end
  local cx = math.floor((x - GRID_X) / CELL)
  local cy = math.floor((y - GRID_Y) / CELL)
  if cx < 0 or cy < 0 or cx >= Mining.GRID_WIDTH or cy >= Mining.GRID_HEIGHT then
    return nil, "off the grid"
  end
  return cx, cy
end

-- Which tool a sidebar point picks, or nil between the two buttons.
function Gen4MiningScreen.toolAt(y)
  if y >= HAMMER.y and y < HAMMER.y + HAMMER.h then return "hammer" end
  if y >= PICKAXE.y and y < PICKAXE.y + PICKAXE.h then return "pickaxe" end
  return nil
end

-- Mining_CalcWallCrackEndPos and the length beside it.
local function crackLengthFor(integrity)
  local rounded = math.floor(integrity / 4) * 4 + 8
  local px = Mining.GRID_WIDTH * 2 * 8 - rounded
  return math.max(0, math.floor(px / 8))
end
Gen4MiningScreen.crackLengthFor = crackLengthFor

-- ---------------------------------------------------------------------- new --

-- `MATH_Rand32(rand, n)` is a uniform integer in 0 .. n-1.  love.math.random is
-- the engine's generator everywhere else, so it is the one used here rather than
-- a second source seeded some other way.
local function engineRand(n)
  if n <= 0 then return 0 end
  return love.math.random(0, n - 1)
end

function Gen4MiningScreen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4MiningScreen)
  self.game = game
  self.onDone = opts.onDone
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  self.rand = opts.rand or engineRand

  local save = game.save or {}
  local ug = save.underground or {}
  save.underground = ug

  -- The two questions the weights turn on.  `trainerId` is the player's public
  -- id and the cartridge takes its LOW BIT, so this is `% 2` and not a compare.
  local tid = tonumber(save.player and save.player.id) or 0
  local wall, why = MiningWall.generate({
    rand = self.rand,
    oddTID = (tid % 2) == 1,
    nationalDex = ug.nationalDex or save.nationalDex or false,
    neverMined = not ug.hasMined,
    plateMined = function(id) return (ug.minedPlates or {})[id] == true end,
  })
  if not wall then
    Logger.warn("gen4 mining: could not lay out a wall -- %s", tostring(why))
    return nil
  end
  self.wall = wall
  self.state = Dig.new(wall, self.rand)
  self.pickaxe = true            -- Mining_InitGameState starts on the pickaxe
  self.phase = "digging"
  self.timer = 0
  self.found = {}
  self.flash = 0
  return self
end

function Gen4MiningScreen:uiSize() return W, H end
function Gen4MiningScreen:wantsFillScale() return true end

-- ------------------------------------------------------------------ art --

function Gen4MiningScreen:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local got, image = pcall(Assets.image, path)
    self.cache[path] = got and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- The art lands under `underground/` once the two UG archives have been
-- extracted.  A cache imported before that has none of it, and the screen still
-- has to be playable -- so every picture is optional and the fallbacks below are
-- flat colour.  Saying so once beats a screen that is silently blank.
function Gen4MiningScreen:warnOnce()
  if self.warned then return end
  self.warned = true
  Logger.info("gen4 mining: no underground art in this cache -- re-import to "
              .. "get ug_parts and ug_fossil; drawing placeholders")
end

-- ---------------------------------------------------------------- input --

function Gen4MiningScreen:close(result)
  if self.closed then return end
  self.closed = true
  self.game.stack:pop()
  if self.onDone then self.onDone(result) end
end

-- What the player walks away with.  `Gen4Mining.bagItem` gives the cartridge's
-- own ITEM_* constant; this dataset keys items by number, so the two are joined
-- on the display name -- checked to resolve for all forty-nine.
function Gen4MiningScreen:itemIdFor(constant)
  if not constant then return nil end
  if not self.itemsByName then
    local out = {}
    for id, def in pairs((self.game.data or {}).items or {}) do
      if type(def) == "table" and type(def.name) == "string" then
        out[def.name:upper()] = id
      end
    end
    self.itemsByName = out
  end
  return self.itemsByName[(constant:gsub("^ITEM_", ""):gsub("_", " "))]
end

function Gen4MiningScreen:award()
  local save = self.game.save
  if not save then return end
  local ug = save.underground or {}
  save.underground = ug
  ug.hasMined = true                       -- Underground_SetHasMined
  for _, placed in ipairs(MiningWall.treasures(self.wall)) do
    local constant = Mining.bagItem(placed.obj)
    local id = constant and self:itemIdFor(constant)
    if id then
      Bag.add(save, id, 1, self.game.data)
      self.found[#self.found + 1] = constant
    end
    -- A plate is once per save (Underground_HasPlateNeverBeenMined), so the bit
    -- is set here rather than when it is buried -- burying one you then fail to
    -- dig out must not lock it away.
    if Mining.isPlate(placed.obj.id) then
      ug.minedPlates = ug.minedPlates or {}
      ug.minedPlates[placed.obj.id] = true
    end
  end
end

-- Returns true when the press was ours, which is what stops it reaching the
-- d-pad underneath.
function Gen4MiningScreen:touchpressed(_, px, py)
  if self.phase ~= "digging" then return true end
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x then return false end

  if x >= SIDEBAR_X then
    -- Mining_ButtonTouchCheck: the sidebar picks the tool and never digs.
    local tool = Gen4MiningScreen.toolAt(y)
    if tool == "hammer" then self.pickaxe = false
    elseif tool == "pickaxe" then self.pickaxe = true end
    return true
  end

  -- `touchY >= 4 * TILE_HEIGHT_PIXELS` -- the crack strip is not diggable, and a
  -- press there is still ours: it must not fall through to the d-pad.
  local cx, cy = Gen4MiningScreen.cellAt(x, y)
  if not cx then return true end
  local hit = Dig.dig(self.state, cx, cy, self.pickaxe)
  if hit then self.lastHit = { x = cx, y = cy, rock = hit.hitRock, time = 12 } end

  local done = Dig.finished(self.state)
  if done == "won" then
    self:award()
    self.phase = "won"
    self.timer = 25                        -- ctx->timer = 25
  elseif done == "collapsed" then
    local ug = self.game.save and self.game.save.underground
    if ug then ug.hasMined = true end
    self.phase = "collapsed"
    self.timer = 45                        -- ctx->timer = 45
  end
  return true
end

function Gen4MiningScreen:update()
  self.flash = (self.flash + 1) % 60
  if self.lastHit and self.lastHit.time > 0 then
    self.lastHit.time = self.lastHit.time - 1
  end
  if self.phase ~= "digging" then
    self.timer = self.timer - 1
    if self.timer <= 0 then return self:close(self.phase) end
    return
  end
  -- THE PORT'S OWN WAY OUT.  The cartridge has none: once the game starts you
  -- play it to a win or a collapse.  A player here may have no touch device at
  -- all, or a stuck screen, and leaving them in a state with no exit is worse
  -- than allowing one the cartridge does not -- so B gives up the wall, which is
  -- the same outcome as a collapse without the animation.
  local input = self.game.input
  if input and input:wasPressed("b") then
    local ug = self.game.save and self.game.save.underground
    if ug then ug.hasMined = true end
    return self:close("quit")
  end
end

-- ----------------------------------------------------------------- draw --

function Gen4MiningScreen:drawCrack()
  local sheet = self:img("underground/interface_tiles")
  local length = crackLengthFor(self.state.integrity)
  if not sheet then
    love.graphics.setColor(0.45, 0.32, 0.22, 1)
    love.graphics.rectangle("fill", (CRACK_END_TILE + 1 - length) * 8, 0,
                            length * 8, CRACK_ROWS * 8)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local sw, sh = sheet:getDimensions()
  for i = 0, length - 1 do
    local column = CRACK_SHEET_COLUMN - (i % 3)
    for row = 0, CRACK_ROWS - 1 do
      local quad = love.graphics.newQuad(column * 8, row * 8, 8, 8, sw, sh)
      love.graphics.draw(sheet, quad, (CRACK_END_TILE - i) * 8, row * 8)
    end
  end
end

function Gen4MiningScreen:drawObjects()
  for _, placed in ipairs(self.wall.objects) do
    local base = placed.obj.sprite:gsub("_NCGR$", "")
    local image = self:img("underground/" .. base)
    local px, py = GRID_X + placed.x * CELL, GRID_Y + placed.y * CELL
    if image then
      love.graphics.draw(image, px, py)
    else
      self:warnOnce()
      love.graphics.setColor(0.55, 0.5, 0.42, 1)
      love.graphics.rectangle("fill", px, py, placed.obj.w * CELL, placed.obj.h * CELL)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

function Gen4MiningScreen:drawDirt()
  local sheet = self:img("underground/dirt_tiles")
  local sw, sh = nil, nil
  if sheet then sw, sh = sheet:getDimensions() end
  for y = 0, Mining.GRID_HEIGHT - 1 do
    for x = 0, Mining.GRID_WIDTH - 1 do
      local level = self.state.dirt[y + 1][x + 1]
      if level > 0 then
        local px, py = GRID_X + x * CELL, GRID_Y + y * CELL
        if sheet then
          local column = DIRT_COLUMN[level] or 0
          local quad = love.graphics.newQuad(column * 8, 0, CELL, CELL, sw, sh)
          love.graphics.draw(sheet, quad, px, py)
        else
          self:warnOnce()
          local shade = 0.22 + level * 0.06
          love.graphics.setColor(shade, shade * 0.78, shade * 0.55, 1)
          love.graphics.rectangle("fill", px, py, CELL, CELL)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
    end
  end
end

function Gen4MiningScreen:drawSidebar()
  local function button(rect, selected, label)
    if selected then
      love.graphics.setColor(1, 1, 1, 0.32)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    end
    love.graphics.setColor(1, 1, 1, selected and 1 or 0.55)
    love.graphics.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1)
    love.graphics.setColor(1, 1, 1, 1)
    Font.print(label, rect.x + 6, rect.y + rect.h / 2 - 4)
  end
  button(HAMMER, not self.pickaxe, Strings("HAM"))
  button(PICKAXE, self.pickaxe, Strings("PIC"))
end

function Gen4MiningScreen:drawBody()
  local bg = self:img("underground/interface")
  if bg then
    love.graphics.draw(bg, 0, 0)
  else
    self:warnOnce()
    love.graphics.setColor(0.12, 0.10, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(1, 1, 1, 1)
  end
  self:drawCrack()
  self:drawObjects()
  self:drawDirt()
  self:drawSidebar()

  if self.phase == "won" then
    Font.print(Strings("Everything was dug up!"), 8, 8)
  elseif self.phase == "collapsed" then
    Font.print(Strings("The wall collapsed!"), 8, 8)
  end
end

function Gen4MiningScreen:draw()
  SecondScreen.drawFrame(self.game)
  SecondScreen.draw(self.game, function() self:drawBody() end)
end

return Gen4MiningScreen