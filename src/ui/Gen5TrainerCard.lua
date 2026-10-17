-- BLACK AND WHITE'S TRAINER CARD, over HGSS's screen (src/ui/HgssTrainerCard.lua,
-- itself over Platinum's): the flip, the faces by level, the live clock and
-- the signature are shared; the art is /a/0/4/0's (src/import/Gen5TrainerCardArt.lua)
-- and the words are bank 187's.
--
--   card     the face (front 41 / back 36) in the level's colours: Black's
--            Normal, Purple, Red, Silver, Gold, Black, White's ending in
--            White; Hilbert or Hilda in the photo box
--   board    the badge strip (33) with each won badge in its socket
--
-- MEASURED OFF THE ART, there being no symbols, and said so: the front's four
-- ruled rows (tick marks at y 40 / 56 / 72 / 88, rules ending at x 152), its
-- fifth tick (y 112) and the wide box under it (y 120..151); the back's
-- records box (y 12..83) and its signature box at tile (4, 11). WHICH WORD
-- SITS ON WHICH ROW is assumed: ID No., NAME, MONEY, POKeDEX on the rules,
-- TIME on the fifth, ADVENTURE STARTED in the box. The text ink is assumed
-- dark. Touch: a tap on the card flips it; B leaves.

local HgssTrainerCard = require("src.ui.HgssTrainerCard")
local Gen4TrainerCard = require("src.ui.Gen4TrainerCard")
local Badges = require("src.inventory.Badges")
local Font = require("src.render.Font")

local Gen5TrainerCard = setmetatable({}, { __index = HgssTrainerCard })
Gen5TrainerCard.__index = Gen5TrainerCard
Gen5TrainerCard.isOpaque = true

local floor = math.floor
local BANK = 187
local WORD = { name = 0, dex = 3, money = 4, id = 5, time = 6, started = 7, hof = 8, linked = 9,
               battles = 10, wins = 11, losses = 12, trades = 13, blank = 24 }

local LABEL_X, RULE_RIGHT, WIDE_RIGHT = 24, 152, 232
local FRONT = { id = 32, name = 48, money = 64, dex = 80, time = 104, started = 122 }
local STARTED_VALUE_Y = 136
local BACK_X, BACK_RIGHT = 24, 232
local BACK = { hof = 16, linked = 32, battles = 48, trades = 64 }
local SIG_X, SIG_Y = 4 * 8, 11 * 8
local INK = { { 0.16, 0.16, 0.16 }, { 0.62, 0.62, 0.62 } }
local COLON_FROM_RIGHT = 19

local PAGE_FRONT, PAGE_BACK, PAGE_CASE = Gen4TrainerCard.PAGE_FRONT, Gen4TrainerCard.PAGE_BACK, Gen4TrainerCard.PAGE_CASE

function Gen5TrainerCard.new(game, opts)
  local self = HgssTrainerCard.new(game, opts)
  setmetatable(self, Gen5TrainerCard)
  self.inkPair = INK
  return self
end

function Gen5TrainerCard:word(key, fallback)
  local T = require("src.import.Gen4Text")
  local s = T.resolve(self.game.data, BANK, WORD[key], self.game)
  if type(s) ~= "string" or s == "" then
    local data = self.game.data
    s = data and data.text and data.text[("TEXT_G5S_%04d_%05d"):format(BANK, WORD[key] or 0)]
  end
  if type(s) ~= "string" or s == "" then return fallback end
  return (s:gsub("{[^}]*}", ""))
end

function Gen5TrainerCard:update()
  self.t = (self.t or 0) + 1
  if self.state == "flip" then
    if self:flipStep() then self.state = "main" end
    return
  end
  local tap = self.tapAt
  self.tapAt = nil
  if tap and self.page ~= PAGE_CASE then return self:startFlip() end
  local input = self.game.input
  if not input then return end
  local shown = self:subscreenShown()
  if input:wasPressed("a") then
    if shown or self.page == PAGE_FRONT then
      if self.page == PAGE_CASE then self.page = PAGE_FRONT end
      self:startFlip()
    else
      self.page = self.page % PAGE_CASE + 1
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if not shown and self.page ~= PAGE_FRONT then self.page = PAGE_FRONT
    else self:leave() end
  end
end

function Gen5TrainerCard:drawCase()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

function Gen5TrainerCard:drawBar() end

local function line(label, value, y, labelX, right)
  if label then Font.draw(label, labelX, y) end
  if value then Font.draw(value, right - Font.width(value), y) end
end

function Gen5TrainerCard:drawCardLayer(side)
  local g = love.graphics
  local face = self:faceImage(side)
  if not face then return false end
  g.setColor(1, 1, 1, 1)
  g.draw(face, 0, 0)
  local blank = self:word("blank", "-- --, ---- --:--")
  self:ink()
  if side == "front" then
    local portrait = self:cardImg(self:female() and "hilda" or "hilbert")
    if portrait then g.draw(portrait, 0, 0) end
    -- Platinum's values, Platinum's order: ID, NAME, MONEY, [DEX], SCORE, TIME, STARTED
    local base = Gen4TrainerCard.frontRows(self)
    local values = {}
    local i = 1
    for _, key in ipairs({ "id", "name", "money", "dex", "score", "time", "started" }) do
      if key ~= "dex" or self:hasPokedex() then values[key] = base[i] and base[i][2]; i = i + 1 end
    end
    line(self:word("id", "ID No."), values.id, FRONT.id, LABEL_X, RULE_RIGHT)
    line(self:word("name", "NAME"), values.name, FRONT.name, LABEL_X, RULE_RIGHT)
    -- bank 187 #57 is "${CMD 0206 0}": BW prints a dollar sign
    values.money = "$" .. tostring(floor((self.game.save or {}).money or 0))
    line(self:word("money", "MONEY"), values.money, FRONT.money, LABEL_X, RULE_RIGHT)
    if values.dex then line(self:word("dex", "POKéDEX"), values.dex, FRONT.dex, LABEL_X, RULE_RIGHT) end
    line(self:word("time", "TIME"), values.time, FRONT.time, LABEL_X, WIDE_RIGHT)
    if self:colonShown() then Font.draw(":", WIDE_RIGHT - COLON_FROM_RIGHT, FRONT.time) end
    line(self:word("started", "ADVENTURE STARTED"), nil, FRONT.started, LABEL_X, WIDE_RIGHT)
    line(nil, blank, STARTED_VALUE_Y, LABEL_X, WIDE_RIGHT)
  else
    line(self:word("hof", "HALL OF FAME DEBUT"), nil, BACK.hof, BACK_X, BACK_RIGHT)
    line(nil, blank, BACK.hof + 0, BACK_X, BACK_RIGHT)
    line(self:word("linked", "TIMES LINKED"), "0", BACK.linked, BACK_X, BACK_RIGHT)
    line(self:word("battles", "LINK BATTLES"), "0 - 0", BACK.battles, BACK_X, BACK_RIGHT)
    line(self:word("trades", "LINK TRADES"), "0", BACK.trades, BACK_X, BACK_RIGHT)
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
  if side == "back" then
    local sig = self:signatureImage()
    if sig then g.draw(sig, SIG_X, SIG_Y) end
  end
  return true
end

function Gen5TrainerCard:earned()
  local out = {}
  for i, entry in ipairs(Badges.list(self.game.data) or {}) do
    if i <= 8 then out[i] = Badges.has(self.game.save or {}, entry) and true or false end
  end
  return out
end

function Gen5TrainerCard:drawBadges()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  local board = self:cardImg("badge_board")
  if board then g.draw(board, 0, 0) end
  local at = self.cardArt.badgeAt or {}
  for i, has in ipairs(self:earned()) do
    local p = at[i]
    if has and p then self:drawSprite("badge_" .. (i - 1), p[1], p[2]) end
  end
  g.setColor(1, 1, 1, 1)
end

return Gen5TrainerCard
