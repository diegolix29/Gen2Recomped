-- BLACK / WHITE'S XTRANSCEIVER CALL SCREEN (script 0x155, overlay 174).
--
-- The call's people stand in panels over their backgrounds -- two in
-- 128-pixel halves, three or four in 128 x 96 quarters (the app's layout
-- screens, /a/1/3/1 37 / 38) -- and the call's steps say their lines in
-- turn: each line is system bank 191 + call, the speaker's panel lit and
-- its mouth frames alternating while it talks. Everything is the ROM's
-- (src/import/Gen5XtransceiverArt.lua, `gen5_xtransceiver`); the
-- background's palette follows the clock as the cartridge's does.
--
-- Not the cartridge's yet: the Xtransceiver's own lower screen, and the
-- D-pad's picture filters.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
local FADE = 16

function M:uiSize() return W, H end
function M:wantsFillScale() return true end
function M:wantsEdgeBleed() return false end

local function record(game) return game and game.data and game.data.gen5_xtransceiver end

function M.available(game, call)
  local r = record(game)
  return r ~= nil and r.calls ~= nil and r.calls[tonumber(call) or -1] ~= nil
end

-- participant id (0 the player .. 4 Mom) -> picture index (1 Juniper ..)
local function pictureOf(game, id)
  if id == 0 or id == 5 then
    local g = game.save and game.save.player and game.save.player.gender
    return g == "girl" and 2 or 3
  end
  return ({ [1] = 4, [2] = 5, [3] = 1, [4] = 6 })[id] or 1
end

-- the time of day's background palette (1 morning / evening, 2 night, day 4
-- on the hills and 3 on the dunes)
local function backgroundPalette(index)
  local h = tonumber(os.date("*t").hour) or 12
  if h >= 20 or h < 4 then return 2 end
  if h < 10 or h >= 17 then return 1 end
  return index <= 3 and 4 or 3
end

local function textOf(game, bank, line)
  local U = require("src.inventory.Gen5ItemUse")
  local name = game.save and game.save.player and game.save.player.name or ""
  return U.line(game.data, ("TEXT_G5S_%04d_%05d"):format(bank, line), { name }, "")
end

function M.new(game, call, onDone)
  local r = record(game)
  local c = r and r.calls and r.calls[tonumber(call) or -1]
  local self = setmetatable({ game = game, call = c, onDone = onDone, frame = 0, step = 0,
                              speaking = nil, record = r }, M)
  self.panels = {}
  local n = c and #c.people or 0
  for i, id in ipairs(c and c.people or {}) do
    local pic = pictureOf(game, id)
    local x, y, w, h
    if n <= 2 then
      x, y, w, h = (i - 1) * 128, 0, 128, 192
    else
      x, y, w, h = ((i - 1) % 2) * 128, math.floor((i - 1) / 2) * 96, 128, 96
    end
    self.panels[i] = { id = id, picture = pic, x = x, y = y, w = w, h = h,
                       name = textOf(game, r.namesBank or 198, id) }
  end
  return self
end

function M:finish()
  if self.done then return end
  self.done = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function M:nextStep()
  self.speaking = nil
  self.step = self.step + 1
  local s = self.call and self.call.steps[self.step]
  if not s then self.closing = 0 return end
  if s.op ~= 1 then return self:nextStep() end
  self.speaking = s.panel + 1
  local text = textOf(self.game, self.call.textBank, s.line)
  if text == "" then return self:nextStep() end
  self.game.stack:push(require("src.render.TextBox").new(self.game, text, function() self:nextStep() end))
end

function M:update()
  self.frame = self.frame + 1
  if not self.call then return self:finish() end
  if self.closing then
    self.closing = self.closing + 1
    if self.closing >= FADE then self:finish() end
    return
  end
  if self.step == 0 and self.frame >= FADE then self:nextStep() end
end

local function drawCropped(img, x, y, w, h, oy)
  local g = love.graphics
  local iw, ih = img:getDimensions()
  g.draw(img, love.graphics.newQuad(0, oy, w, h, iw, ih), x, y)
end

function M:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  local r = self.record
  local t = love.timer and love.timer.getTime() or self.frame / 60
  for i, p in ipairs(self.panels) do
    local person = r.people and r.people[p.picture]
    local bgSet = r.backgrounds and r.backgrounds[p.picture]
    local bgPath = bgSet and (bgSet[backgroundPalette(p.picture)] or bgSet[1])
    -- a quarter shows the head and shoulders: the picture's top, a little in
    local oy = p.h < 192 and 40 or 0
    g.setColor(1, 1, 1, 1)
    local bg = bgPath and Assets.image(bgPath)
    if bg then drawCropped(bg, p.x, p.y, p.w, p.h, oy) end
    local talking = self.speaking == i
    local f = (talking and math.floor(t * 8) % 2 == 1) and 2 or 1
    local pic = person and person.frames and person.frames[f] and Assets.image(person.frames[f])
    if pic then drawCropped(pic, p.x, p.y, p.w, p.h, oy) end
    -- the name tag, and the speaker's panel lit
    if p.name ~= "" then
      g.setColor(0, 0, 0, 0.55)
      g.rectangle("fill", p.x + 2, p.y + 2, Font.width(p.name) + 6, 12)
      g.setColor(1, 1, 1, 1)
      Font.draw(p.name, p.x + 5, p.y + 4)
    end
    g.setLineWidth(talking and 2 or 1)
    if talking then g.setColor(1, 0.75, 0.2, 1) else g.setColor(0.1, 0.12, 0.16, 1) end
    g.rectangle("line", p.x + 0.5, p.y + 0.5, p.w - 1, p.h - 1)
    g.setLineWidth(1)
  end
  -- the picture comes up out of black and goes back to it
  local a
  if self.closing then a = self.closing / FADE
  elseif self.frame < FADE then a = 1 - self.frame / FADE end
  if a and a > 0 then
    g.setColor(0, 0, 0, a)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

return M
