-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S RUINS OF ALPH PUZZLES (`AlphPuzzle <n>`), pokeheartgold
-- src/alph_puzzle.c, state for state:
--
--   * A 6 x 6 board on the bottom screen; its cell (x, y) spans pixels
--     (32 + 32x, 32y). Sixteen 32 x 32 tiles start where the cartridge's
--     layout puts them (overlay 110; later cells win, which matters for the
--     Ho-Oh board's doubled tile 5). Immovable tiles never pick up.
--   * TOUCH ONLY, as on the cartridge. Touch a tile: held for more than two
--     frames it is PICKED UP -- it follows the stylus (clamped to 48..208 x
--     16..176), the translucent origin frame follows too, and the board marks
--     the cell it would land in (BG2 marks: 1 target, 2 origin while away,
--     3 origin under the stylus). Released on an empty, non-corner cell it
--     lands there; anywhere else it goes home. Released sooner, it ROTATES a
--     quarter turn, animated over eight frames of 0x800.
--   * SOLVED when tile i (0-based) sits at ((i % 4) + 1, (i // 4) + 1) at
--     rotation 0 -- the inner 4 x 4. Then the glow (OBJ colours 0x2B..0x2F
--     toward white, up sixteen steps and back), the fade, and the room's flag
--     (Save_VarsFlags_SetAlphPuzzleFlag: 0x977 + puzzle).
--   * QUIT (bottom right, its button's press animation first) asks "Are you
--     sure you would like to quit?" with YES / NO; YES leaves unsolved.
--   * The top screen is the tablet and the puzzle's hint (msg_0002 1..4).

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")

local P = {}
P.__index = P
P.isOpaque = true

local W, H = 256, 192
function P:uiSize() return W, H end
function P:wantsFillScale() return true end

P.FLAG_BASE = 0x977
P.TEXT_BANK = 2
local CORNERS = { { 0, 0 }, { 5, 0 }, { 0, 5 }, { 5, 5 } }

local function se(self, name)
  local data = self.game and self.game.data
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end

local function text(self, n)
  local t = self.game.data and self.game.data.text
  return t and t[("TEXT_B%04d_%05d"):format(P.TEXT_BANK, n)] or ""
end

function P.available(game)
  local rec = game and game.data and game.data.gen4_alph_puzzle
  return rec ~= nil and rec.board ~= nil and rec.layouts ~= nil and rec.puzzles ~= nil
end

function P.new(game, puzzle, onDone)
  puzzle = math.floor(tonumber(puzzle) or 0)
  if puzzle < 0 or puzzle > 3 then puzzle = 0 end   -- ScrCmd_AlphPuzzle: > 4 -> 0
  local rec = game.data.gen4_alph_puzzle
  local self = setmetatable({ game = game, rec = rec, puzzle = puzzle, onDone = onDone,
                              state = "fadein", timer = 0, sub = 0, fade = 1,
                              marks = {}, images = {}, quads = {} }, P)
  -- AlphPuzzle_InitTileData
  self.tiles = {}
  for pos, cell in ipairs(rec.layouts[puzzle + 1] or {}) do
    local i = tonumber(cell.index) or 0
    if i >= 1 and i <= 16 then
      self.tiles[i] = { x = (pos - 1) % 6, y = math.floor((pos - 1) / 6),
                        rotation = cell.rotation or 0, fixed = cell.fixed and true or false }
    end
  end
  self.buttonAnim, self.buttonT = 0, 0
  return self
end

function P:img(entry)
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

-- --------------------------------------------------------------- the rules

local function cellOfPixel(x, y)
  if x < 32 or x >= 224 then return nil end
  return math.floor((x - 32) / 32), math.floor(y / 32)
end

-- AlphPuzzle_TrySelectTileTouchScreen
function P:tileAt(px, py)
  local x, y = cellOfPixel(px, py)
  if not x then return nil end
  for i = 1, 16 do
    local t = self.tiles[i]
    if t and t.x == x and t.y == y then
      if t.fixed then return nil end
      return i
    end
  end
  return nil
end

-- AlphPuzzle_GetTileDropCoords: (0, 0) when it cannot land
function P:dropCell()
  local x, y = cellOfPixel(self.hoverPX, self.hoverPY)
  if not x then return 0, 0 end
  for _, c in ipairs(CORNERS) do
    if x == c[1] and y == c[2] then return 0, 0 end
  end
  for i = 1, 16 do
    local t = self.tiles[i]
    if i ~= self.held and t and t.x == x and t.y == y then return 0, 0 end
  end
  return x, y
end

-- AlphPuzzle_CheckComplete
function P:solved()
  for i = 1, 16 do
    local t = self.tiles[i]
    if not (t and t.rotation == 0 and t.x == (i - 1) % 4 + 1 and t.y == math.floor((i - 1) / 4) + 1) then
      return false
    end
  end
  return true
end

local function key(x, y) return y * 6 + x end
function P:mark(x, y, v) self.marks[key(x, y)] = (v ~= 0) and v or nil end

-- AlphPuzzle_UpdateHoverGraphicOnBg
function P:updateHover(x, y)
  local t = self.tiles[self.held]
  if t.x == self.hoverTX and t.y == self.hoverTY then
    self:mark(self.hoverTX, self.hoverTY, 2)
  else
    self:mark(self.hoverTX, self.hoverTY, 0)
  end
  if x ~= 0 or y ~= 0 then
    self:mark(x, y, (t.x == x and t.y == y) and 3 or 1)
  end
end

-- AlphPuzzle_UpdateSelectedTile
function P:select(i)
  if i then
    self.held = i
    self.lift = true
    local t = self.tiles[i]
    self.originCursor = { x = t.x * 32 + 48, y = t.y * 32 + 16 }
    self:button(2)
  else
    self.held, self.lift, self.originCursor, self.drag = nil, nil, nil, nil
    self:button(0)
    self.hoverTX, self.hoverTY = 0, 0
  end
end

-- AlphPuzzle_ToggleDropCursorSprite: the QUIT button's look (0 idle,
-- 1 pressed -- its animation -- and 2 while a tile is in hand)
function P:button(n)
  self.buttonAnim, self.buttonT = n, 0
end

function P:buttonAnimDone()
  local an = self.rec.cursors and self.rec.cursors.anims and self.rec.cursors.anims[self.buttonAnim + 1]
  if not an then return true end
  local total = 0
  for _, f in ipairs(an.frames) do total = total + math.max(1, f.duration) end
  return self.buttonT >= total
end

-- ------------------------------------------------------------------ input

function P:point(px, py)
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if okS then
    local mode = SS.mode(self.game)
    if SS.separateMode(mode) and not SS.stowed(self.game) then
      return SS.toLocal(self.game, px, py)
    end
  end
  local r = require("src.render.Renderer").uiPresentation
  if not r or px < r.x or py < r.y or px >= r.x + r.w or py >= r.y + r.h then return nil end
  return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY
end

function P:touchpressed(id, px, py)
  local x, y = self:point(px, py)
  if not x then return false end
  self.touchNew = { x = x, y = y }
  self.touchId = id
  self.touchX, self.touchY = x, y
  self.touchHeld = true
  return true
end
function P:touchmoved(id, px, py)
  if id ~= self.touchId then return end
  local x, y = self:point(px, py)
  if x then self.touchX, self.touchY = x, y end
end
function P:touchreleased(id)
  if id == self.touchId then self.touchHeld = false end
end
function P:mousepressed(x, y, button)
  if button == 1 then return self:touchpressed("mouse", x, y) end
end
function P:mousemoved(x, y)
  if self.touchId == "mouse" then self:touchmoved("mouse", x, y) end
end
function P:mousereleased(_, _, button)
  if button == 1 then self:touchreleased("mouse") end
end

-- --------------------------------------------------------- the main loop

function P:update()
  self.buttonT = self.buttonT + 1
  local tap = self.touchNew
  self.touchNew = nil
  -- a release the window never reported (focus lost) still lets go
  if self.touchId == "mouse" and self.touchHeld and love.mouse and love.mouse.isDown
     and not love.mouse.isDown(1) then
    self.touchHeld = false
  end
  local s = self.state
  if s == "fadein" then
    self.fade = math.max(0, self.fade - 1 / 8)
    if self.fade <= 0 then self.state = "input" end
  elseif s == "input" then
    -- AlphPuzzle_CheckInput
    if tap then
      if tap.x >= 209 and tap.y >= 169 then          -- sButtonHitboxes: QUIT
        self:button(1)
        se(self, "SEQ_SE_DP_SELECT")
        self.state, self.sub = "quit", 0
      else
        local i = self:tileAt(tap.x, tap.y)
        if i then
          self:select(i)
          se(self, "SEQ_SE_GS_SEKIBAN_SENTAKU")
          self.state, self.timer = "pickup", 0
        end
      end
    end
  elseif s == "pickup" then
    if not self.touchHeld then
      self.timer, self.sub = 0, 0
      self.state = "rotate"
    else
      self.timer = self.timer + 1
      if self.timer >= 3 then
        self.timer = 0
        local t = self.tiles[self.held]
        self.hoverPX, self.hoverPY = t.x * 32 + 64, t.y * 32 + 32
        self.hoverTX, self.hoverTY = t.x, t.y
        self:mark(t.x, t.y, 3)
        self.state = "holding"
      end
    end
  elseif s == "holding" then
    local t = self.tiles[self.held]
    if not self.touchHeld then
      self:mark(t.x, t.y, 0)
      self:mark(self.hoverTX, self.hoverTY, 0)
      if self.hoverTX == 0 and self.hoverTY == 0 then
        se(self, "SEQ_SE_DP_BOX01")
      else
        se(self, "SEQ_SE_GS_SEKIBAN_SENTAKU")
        t.x, t.y = self.hoverTX, self.hoverTY
      end
      self:select(nil)
      self.state = self:solved() and "clear" or "input"
      self.sub, self.timer = 0, 0
    else
      local x = math.max(48, math.min(208, math.floor(self.touchX or 0)))
      local y = math.max(16, math.min(176, math.floor(self.touchY or 0)))
      self.originCursor = { x = x, y = y }
      self.drag = { x = x - 2, y = y - 2 }
      self.hoverPX, self.hoverPY = x, y
      local dx, dy = self:dropCell()
      if self.hoverTX ~= dx or self.hoverTY ~= dy then
        self:updateHover(dx, dy)
        self.hoverTX, self.hoverTY = dx, dy
      end
    end
  elseif s == "rotate" then
    local t = self.tiles[self.held]
    if self.sub == 0 then
      se(self, "SEQ_SE_GS_SEKIBAN_KAITEN")
      self.sub = 1
    elseif self.sub == 1 then
      self.spin = self.timer * 0x800
      self.timer = self.timer + 1
      if self.timer >= 8 then self.sub = 2 end
    else
      t.rotation = (t.rotation + 1) % 4
      self.spin = nil
      self:select(nil)
      self.timer, self.sub = 0, 0
      self.state = self:solved() and "clear" or "input"
    end
  elseif s == "quit" then
    -- the button's press animation, then the question, then YES / NO
    if self.sub == 0 then
      if self:buttonAnimDone() then
        self:button(0)
        self.sub = 1
        self.yes = 2                                  -- initialCursorPos 1: NO
      end
    else
      local input = self.game.input
      local function pressed(k) return input and input.wasPressed and input:wasPressed(k) end
      local pick
      if pressed("up") or pressed("down") then
        self.yes = 3 - self.yes
        se(self, "SEQ_SE_DP_SELECT")
      end
      if pressed("a") then pick = self.yes end
      if pressed("b") then pick = 2 end
      -- the YES / NO box at tile (25, 10), two 16-pixel rows
      if tap and tap.x >= 200 and tap.y >= 80 and tap.y < 112 then
        pick = (tap.y < 96) and 1 or 2
      end
      if pick then
        se(self, "SEQ_SE_DP_SELECT")
        self.sub = 0
        if pick == 1 then self.state = "fadeout" else self.state = "input" end
      end
    end
  elseif s == "clear" then
    -- AlphPuzzleMainSeq_Clear_impl
    if self.sub == 0 then
      se(self, "SEQ_SE_GS_PUZZLETOKU")
      self.sub, self.timer = 1, 0
    elseif self.sub == 1 then
      self.glow = self.timer
      self.timer = self.timer + 1
      if self.timer > 15 then self.sub = 2 end
    elseif self.sub == 2 then
      self.glow = self.timer
      if self.timer == 0 then self.sub = 3 end
      self.timer = self.timer - 1
    else
      self.glow, self.sub, self.timer = nil, 0, 0
      self.solvedFlag = true
      self.state = "fadeout"
    end
  elseif s == "fadeout" then
    self.fade = math.min(1, self.fade + 1 / 8)
    if self.fade >= 1 then self:finish() end
  end
end

-- AlphPuzzle_Finish
function P:finish()
  if self.finished then return end
  self.finished = true
  if self.solvedFlag and self.game.save then
    require("src.script.Flags").set(self.game.save, ("FLAG_G4_%04X"):format(P.FLAG_BASE + self.puzzle))
  end
  local stack = self.game.stack
  if stack and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone(self.solvedFlag and true or false) end
end

-- ----------------------------------------------------------------- drawing

function P:drawCell(set, cell, x, y, angle)
  local entry = set and set[cell + 1]
  local image = entry and self:img(entry)
  if not image then return end
  if angle and angle ~= 0 then
    love.graphics.draw(image, x, y, angle, 1, 1, entry.ox or 0, entry.oy or 0)
  else
    love.graphics.draw(image, x - (entry.ox or 0), y - (entry.oy or 0))
  end
end

function P:drawButton()
  local cur = self.rec.cursors
  local an = cur and cur.anims and cur.anims[self.buttonAnim + 1]
  if not an or #an.frames == 0 then return end
  local t, cell = self.buttonT, an.frames[#an.frames].cell
  for _, f in ipairs(an.frames) do
    if t < math.max(1, f.duration) then cell = f.cell break end
    t = t - math.max(1, f.duration)
  end
  self:drawCell(cur.cells, cell, 208, 168)
end

local function setInk(c, alpha)
  if c then love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1)
  else love.graphics.setColor(0.13, 0.13, 0.13, alpha or 1) end
end

-- a line with the cartridge's shadow: one pixel right, one down and both
local function shadowed(s, x, y, ink)
  if ink and ink[2] then
    setInk(ink[2]); Font.draw(s, x + 1, y); Font.draw(s, x, y + 1); Font.draw(s, x + 1, y + 1)
  end
  setInk(ink and ink[1]); Font.draw(s, x, y)
end

function P:drawBoard()
  local g = love.graphics
  local rec = self.rec
  local bd = rec.backdrop
  g.clear(bd and bd[1] / 255 or 0, bd and bd[2] / 255 or 0, bd and bd[3] / 255 or 0, 1)
  g.setColor(1, 1, 1, 1)
  local board = self:img(rec.board)
  if board then g.draw(board, 0, 0) end
  -- the QUIT button sprite (priority 3, under BG2)
  self:drawButton()
  -- BG2: the hover marks and the QUIT label
  local marks = self:img(rec.marks)
  if marks then
    for k, v in pairs(self.marks) do
      local x, y = k % 6, math.floor(k / 6)
      local q = self.quads[v]
      if not q then
        q = g.newQuad((v - 1) * 32, 0, 32, 32, marks:getDimensions())
        self.quads[v] = q
      end
      g.draw(marks, q, 32 + x * 32, y * 32)
    end
  end
  local quit = text(self, 0)
  local inks = rec.inks and rec.inks.quit or {}
  local look = (self.buttonAnim == 1 and 2) or (self.buttonAnim == 2 and 3) or 1
  shadowed(quit, 208 + math.floor((48 - Font.width(quit)) / 2), 172, inks[look])
  g.setColor(1, 1, 1, 1)
  -- the tiles (priority 2), the held one last (priority 0)
  local set = rec.puzzles[self.puzzle + 1]
  local function drawTile(i, t, x, y)
    local angle = (t.rotation % 4) * math.pi / 2
    if i == self.held and self.spin then angle = angle + self.spin / 0x10000 * 2 * math.pi end
    self:drawCell(set and set.cells, i - 1, x, y, angle)
    if self.glow and self.glow > 0 and set and set.glow then
      g.setColor(1, 1, 1, math.min(16, self.glow) / 16)
      self:drawCell(set.glow, i - 1, x, y, angle)
      g.setColor(1, 1, 1, 1)
    end
  end
  for i = 1, 16 do
    local t = self.tiles[i]
    if t and i ~= self.held then drawTile(i, t, t.x * 32 + 48, t.y * 32 + 16) end
  end
  -- the origin frame (priority 1, translucent)
  if self.originCursor then
    g.setColor(1, 1, 1, 0.5)
    self:drawCell(rec.cursors and rec.cursors.cells, 3, self.originCursor.x, self.originCursor.y)
    g.setColor(1, 1, 1, 1)
  end
  if self.held then
    local t = self.tiles[self.held]
    local at = self.drag or { x = t.x * 32 + 46, y = t.y * 32 + 14 }
    drawTile(self.held, t, at.x, at.y)
  end
  -- the question (window 1 at tile (2, 19), 27 x 4) and YES / NO at (25, 10)
  if self.state == "quit" and self.sub == 1 then
    Font.drawBox(1, 18, 29, 6)
    g.setColor(0.13, 0.13, 0.13, 1)
    local y = 152
    for line in (text(self, 5) .. "\n"):gmatch("(.-)\n") do Font.draw(line, 16, y); y = y + 16 end
    Font.drawBox(24, 9, 8, 6)
    g.setColor(0.13, 0.13, 0.13, 1)
    local Theme = require("src.ui.Theme")
    for i, word in ipairs({ "YES", "NO" }) do
      local yy = 80 + (i - 1) * 16
      if i == self.yes and Theme.cursor then Font.drawCode(Theme.cursor, 200, yy) end
      Font.draw(word, 210, yy)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function P:drawTop()
  local g = love.graphics
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  local back, front = self:img(self.rec.topBack), self:img(self.rec.topFront)
  if back then g.draw(back, 0, 0) end
  if front then g.draw(front, 0, 0) end
  -- window 2: tile (4, 15), 24 x 6, MAKE_TEXT_COLOR(2, 1, 0)
  local ink = self.rec.inks and self.rec.inks.hint
  local y = 120
  for line in (text(self, 1 + self.puzzle) .. "\n"):gmatch("(.-)\n") do
    shadowed(line, 32, y, ink)
    y = y + 16
  end
  g.setColor(1, 1, 1, 1)
end

local function veil(f)
  if f and f > 0 then
    love.graphics.setColor(0, 0, 0, f)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function P:dualScreen()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return false end
  local mode = SS.mode(self.game)
  return SS.separateMode(mode) and not SS.stowed(self.game), SS
end

function P:draw()
  local dual, SS = self:dualScreen()
  if dual then
    self:drawTop()
    veil(self.fade)
    SS.draw(self.game, function() self:drawBoard(); veil(self.fade) end)
  else
    self:drawBoard()
    veil(self.fade)
  end
end

return P
