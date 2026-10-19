-- PLATINUM'S JOURNAL (src/applications/journal_display/journal_controller.c
-- and journal_printer.c), over the pages kept by src/pokemon/Gen4Journal.lua.
--
-- The notebook (f_note_gra.narc, the boy's or the girl's) fills the top
-- screen in palette `page`, so every page has its own paper. Two windows sit
-- on it, in the system font in TEXT_COLOR(1, 2, 0):
--
--   the title    tile (2, 2), 24 x 2:  "<Month> <day>"  then the weekday 12 px on
--   the events   tile (4, 4), 27 x 18: "Started from ...", then 16 px rows --
--                four location events, the Pokemon, the trainer, two online
--
-- Input (JournalController_HandleInput):
--   LEFT            the newer page, if there is one
--   A or RIGHT      the older page, if there is one
--   B               the newer page; on the first page, close
--   START           close
--
-- A page turn (ov81_021D1450 with Unk_ov81_021D33E8): nine steps, a frame
-- each, in which the turning page shows only the tile columns its step lists
-- -- folding away to the right when going back (LEFT), unfolding from the
-- left over the old one when going on (RIGHT). SEQ_SE_DP_MEKURU3 plays.
-- Opening and closing fade through black.

local Font = require("src.render.Font")
local J = require("src.pokemon.Gen4Journal")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

-- Unk_ov81_021D33E8: for each step, the source tile column shown at each of
-- the 32 screen columns (false = blank)
local X = false
Screen.FOLD = {
  { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 },
  { 0, 1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26, 27, 28, 29, 30, 31, X, X, X, X },
  { 0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 25, 26, 27, 28, 29, 30, 31, X, X, X, X, X, X, X, X },
  { 0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 28, 29, 30, 31, X, X, X, X, X, X, X, X, X, X, X, X },
  { 0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X },
  { 0, 1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X },
  { 14, 15, 16, 17, 18, 19, 20, 21, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X },
  { 28, 29, 30, 31, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X },
  { X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X },
}

Screen.TITLE_X, Screen.TITLE_Y = 16, 16
Screen.EVENTS_X, Screen.EVENTS_Y = 32, 32
Screen.ROW = 16

function Screen:uiSize() return 256, 192 end
function Screen:wantsFillScale() return true end

-- opts = { save, pages (default: the save's own), onClose }
function Screen.new(game, opts)
  opts = opts or {}
  local save = opts.save or game.save
  local s = J.state(save)
  local self = setmetatable({ game = game, data = game.data, save = save, onClose = opts.onClose,
    pages = opts.pages or (s and s.pages) or {}, page = 0, fade = 1, fading = "in", images = {}, canvases = {} }, Screen)
  return self
end

-- JournalController_PageExists: a page whose title has been written
function Screen:exists(page)
  local p = self.pages[page + 1]
  return p ~= nil and p.title ~= nil
end

function Screen:canTurn(dir)
  if dir > 0 then return self.page ~= J.PAGES - 1 and self:exists(self.page + 1) end
  return self.page ~= 0 and self:exists(self.page - 1)
end

local function sfx(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.play and self.data then pcall(Sound.play, self.data, name) end
end

function Screen:turn(dir)
  self.turning = { dir = dir, from = self.page, to = self.page + dir, step = 0 }
  self.page = self.page + dir
  sfx(self, "SEQ_SE_DP_MEKURU3")
end

function Screen:close()
  self.fading = "out"
end

function Screen:update()
  if self.fading == "in" then
    self.fade = math.max(0, self.fade - 1 / 8)
    if self.fade == 0 then self.fading = nil end
    return
  elseif self.fading == "out" then
    self.fade = math.min(1, self.fade + 1 / 8)
    if self.fade == 1 and not self.closed then
      self.closed = true
      self.game.stack:pop()
      if self.onClose then self.onClose() end
    end
    return
  end
  if self.turning then
    self.turning.step = self.turning.step + 1
    if self.turning.step >= 9 then self.turning = nil end
    return
  end
  local input = self.game.input
  if not input then return end
  local function hit(k) return input:wasPressed(k) end
  if hit("left") then
    if self:canTurn(-1) then self:turn(-1) end
  elseif hit("a") or hit("right") then
    if self:canTurn(1) then self:turn(1) end
  elseif hit("b") then
    if self.page ~= 0 then
      if self:canTurn(-1) then self:turn(-1) end
    else
      self:close()
    end
  elseif hit("start") then
    self:close()
  end
end

-- ------------------------------------------------------------ drawing --

function Screen:gender()
  local p = self.save and self.save.player
  local g = p and (p.gender or p.sex)
  return (g == 1 or g == "female" or g == "f") and "f" or "m"
end

function Screen:paper(page)
  local index = self.data and self.data.gen4_journal_art
  local rec = index and index["journal_" .. self:gender() .. "_" .. page]
  if not rec then return nil end
  if self.images[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    self.images[rec.path] = ok and img or false
  end
  return self.images[rec.path] or nil
end

-- One whole page, paper and writing, as it sits in its BG pair
function Screen:drawPage(page)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local img = self:paper(page)
  if img then
    g.draw(img, 0, 0)
  else
    g.setColor(0.96, 0.93, 0.82, 1); g.rectangle("fill", 0, 0, 256, 192); g.setColor(1, 1, 1, 1)
  end
  local r = self.pages[page + 1] and J.render(self.game, self.pages[page + 1])
  if not r then return end
  g.setColor(1, 1, 1, 1)
  Font.draw(r.date or "", Screen.TITLE_X, Screen.TITLE_Y)
  Font.draw(r.weekday or "", Screen.TITLE_X + Font.width(r.date or "") + 12, Screen.TITLE_Y)
  -- "Started from" at the window's top, then the rows from ROW down
  for i, l in ipairs(r.lines) do
    if l ~= "" then Font.draw(l, Screen.EVENTS_X, Screen.EVENTS_Y + (i - 1) * Screen.ROW) end
  end
end

function Screen:pageCanvas(page)
  local cv = self.canvases[page]
  if not cv then
    cv = love.graphics.newCanvas(256, 192)
    self.canvases[page] = cv
  end
  local g = love.graphics
  g.push("all")   -- the pop restores the bound canvas, a mod's depth set included
  g.setCanvas(cv)
  g.clear(0, 0, 0, 0)
  g.origin()
  self:drawPage(page)
  g.pop()
  return cv
end

-- the turning page through one step of FOLD
function Screen:drawFolded(page, step)
  local cv = self:pageCanvas(page)
  local row = Screen.FOLD[step + 1]
  local g = love.graphics
  self.quad = self.quad or love.graphics.newQuad(0, 0, 8, 192, 256, 192)
  g.setColor(1, 1, 1, 1)
  for col = 0, 31 do
    local src = row[col + 1]
    if src then
      self.quad:setViewport(src * 8, 0, 8, 192)
      g.draw(cv, self.quad, col * 8, 0)
    end
  end
end

function Screen:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  local t = self.turning
  if t and t.dir < 0 then
    -- back: the new page beneath, the old folding away step by step
    self:drawPage(t.to)
    self:drawFolded(t.from, t.step)
  elseif t then
    -- on: the old page beneath, the new one unfolding (FOLD read backwards)
    self:drawPage(t.from)
    self:drawFolded(t.to, 8 - t.step)
  else
    self:drawPage(self.page)
  end
  if self.fade > 0 then
    g.setColor(0, 0, 0, self.fade)
    g.rectangle("fill", 0, 0, 256, 192)
  end
  g.setColor(1, 1, 1, 1)
end

return Screen
