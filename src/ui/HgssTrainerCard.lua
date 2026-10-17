-- HEARTGOLD / SOULSILVER'S TRAINER CARD (overlay 51, `ov51_*`; the map is
-- scratch_claude/hgss_ui_screens_map.md "Trainer card"), over Platinum's
-- screen (src/ui/Gen4TrainerCard.lua): the flip, the faces by level, the
-- live clock and the signature are Platinum's code, unchanged; what HGSS does
-- differently is here.
--
-- THE SCREENS ARE THE OTHER WAY ROUND.  The CARD is the touch screen -- the
-- one this port draws as the game screen, since it is the one played -- and
-- the BADGE BOARD the other.  No case, no lid, no polishing:
--
--   card     the blue-diamond frame (42 / 49) behind the card (41 + 47 / 48,
--            the level's face), the trainer (Ethan 54 / Lyra 55) and the text;
--            along the bottom, y 168, the flip bar (anim 4 at x 0, "Touch
--            Card to flip.") and the back button (anim 0 at x 192)
--   board    the backdrop (50) and the board -- 51, Johto's eight leaders, or
--            52 once Kanto is open, sixteen -- with each won badge over its
--            leader's corner at `ov51_021E801C`'s {96..240} x {48..176}
--            (centres); on the Johto board the eight sit 40 lower.  A band's
--            emblem (53) covers its empty ring once all eight are won.
--
-- TOUCH (asm:4252-4259, top/bottom/left/right): the card {0,168,0,255} and
-- the flip bar {168,191,0,112} flip; the back button {168,191,191,255} leaves.
-- Keys: A flips, B leaves.  Without the second screen the board is a page:
-- A walks front -> back -> board -> front, B steps back to the front first.
--
-- THE ROWS, `ov51_021E7F48`, tile units, labels at the window's x 0 and every
-- value right-aligned: front y 3 (IDNo. x 2 w 12, NAME x 17 w 13), 6 MONEY,
-- 9 POKeDEX, 13 SCORE (w 17), 16 TIME, 18 ADVENTURE STARTED (w 28); back y 1
-- (four tiles: the Hall of Fame date, its time 16 below), 6 TIMES LINKED,
-- 8 LINK BATTLES, 10 LINK TRADES (w 28).  The words are bank 727's.
--
-- BY ASSUMPTION, said so: the Kanto board is shown once any Kanto badge is
-- won (the cartridge's flag is bit 0 at 0x343A, which the port does not keep);
-- the back button's word is bank 727's "Cancel"; the signature box is at tile
-- (4, 12), measured off the back's art.

local Gen4TrainerCard = require("src.ui.Gen4TrainerCard")
local Badges = require("src.inventory.Badges")
local Font = require("src.render.Font")

local HgssTrainerCard = setmetatable({}, { __index = Gen4TrainerCard })
HgssTrainerCard.__index = HgssTrainerCard
HgssTrainerCard.isOpaque = true

local W, H = 256, 192
local floor = math.floor

local BANK = 727
local WORD = { id = 0, name = 1, money = 2, dex = 3, score = 4, time = 5, started = 6,
               hof = 7, linked = 8, battles = 9, trades = 10, cancel = 14, flip = 15,
               w = 23, l = 24, blankDate = 25 }

local function tx(t) return t * 8 end
-- { label x, value right edge, y }
local FRONT = {
  id = { tx(2), tx(2 + 12), tx(3) }, name = { tx(17), tx(17 + 13), tx(3) },
  money = { tx(2), tx(2 + 17), tx(6) }, dex = { tx(2), tx(2 + 17), tx(9) },
  score = { tx(2), tx(2 + 17), tx(13) },
  time = { tx(2), tx(2 + 28), tx(16) }, started = { tx(2), tx(2 + 28), tx(18) },
}
local BACK = {
  hof = { tx(2), tx(2 + 28), tx(1) }, hofTime = { tx(2), tx(2 + 28), tx(1) + 16 },
  linked = { tx(2), tx(2 + 28), tx(6) }, battles = { tx(2), tx(2 + 28), tx(8) },
  trades = { tx(2), tx(2 + 28), tx(10) },
}
-- the colon blinks where Platinum's does, against the TIME row's right edge
local COLON_FROM_RIGHT = 3 * 8 - 5
local SIG_X, SIG_Y = 4 * 8, 12 * 8

-- the bottom bar: the sprites, and BG4's two label windows (x1 y21 w16, x25 y21 w6)
local BUTTON_Y = 168
local FLIP_BUTTON = { key = "button_4_0", x = 0 }
local BACK_BUTTON = { key = "button_0_0", x = 192 }
local FLIP_LABEL = { x = tx(1), w = tx(16) }
local BACK_LABEL = { x = tx(25), w = tx(6) }
local BAR_INK = { { 1, 1, 1 }, { 0.38, 0.38, 0.45 } }
local FLIP_INK = { { 0.29, 0.29, 0.29 }, { 0.67, 0.67, 0.67 } }

-- top, bottom, left, right
local RECT_BACK = { 168, 191, 191, 255 }
local RECT_FLIP = { 168, 191, 0, 112 }
local RECT_CARD = { 0, 167, 0, 255 }

local BADGE_X = { 96, 144, 192, 240 }
local BADGE_Y = { 48, 88, 136, 176 }
local JOHTO_DROP = 40
local EMBLEM_AT = { johto = { 0, 7 * 8 }, kanto = { 0, 14 * 8 } }

local PAGE_FRONT, PAGE_BACK, PAGE_CASE = Gen4TrainerCard.PAGE_FRONT, Gen4TrainerCard.PAGE_BACK, Gen4TrainerCard.PAGE_CASE

function HgssTrainerCard.new(game, opts)
  local self = Gen4TrainerCard.new(game, opts)
  setmetatable(self, HgssTrainerCard)
  local ink = (self.cardArt.ink or {})[self.face]
  if ink then self.inkPair = ink end
  return self
end

function HgssTrainerCard:word(key, fallback)
  local T = require("src.import.Gen4Text")
  local s = T.resolve(self.game.data, BANK, WORD[key], self.game)
  if type(s) ~= "string" or s == "" then return fallback end
  return s
end

-- ----------------------------------------------------------------- input --

function HgssTrainerCard:update()
  self.t = (self.t or 0) + 1
  if not self.openSfx then self.openSfx = true; self:sound("SEQ_SE_DP_CARD3") end
  if self.state == "flip" then
    if self:flipStep() then self.state = "main" end
    return
  end
  local input = self.game.input
  local tap = self.tapAt
  self.tapAt = nil
  if tap then
    if self:inRect(tap, RECT_BACK) then return self:leave() end
    if self:inRect(tap, RECT_FLIP) or (self.page ~= PAGE_CASE and self:inRect(tap, RECT_CARD)) then
      if self.page == PAGE_CASE then self.page = PAGE_FRONT end
      return self:startFlip()
    end
  end
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

function HgssTrainerCard:sound(name)
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if data and ok and type(Sound) == "table" and Sound.playSe then pcall(Sound.playSe, data, name) end
end

function HgssTrainerCard:leave()
  self:sound("SEQ_SE_DP_SELECT")
  self:close()
end

function HgssTrainerCard:inRect(p, r)
  return p.y >= r[1] and p.y <= r[2] and p.x >= r[3] and p.x <= r[4]
end

-- the card is the game screen here; the board takes no touches
function HgssTrainerCard:touchpressed(id, px, py)
  local shown, SS = self:subscreenShown()
  if shown and SS.toLocal then
    local lx = SS.toLocal(self.game, px, py)
    if lx then return true end
  end
  local rect = require("src.render.Renderer").uiPresentation
  local x, y = px, py
  if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
  if x < 0 or y < 0 or x >= W or y >= H then return false end
  self.tapAt = { x = floor(x), y = floor(y) }
  return true
end

function HgssTrainerCard:touchmoved() return false end
function HgssTrainerCard:touchreleased() return false end

-- ------------------------------------------------------------------ card --

function HgssTrainerCard:frontRows()
  local base = Gen4TrainerCard.frontRows(self)
  -- Platinum's values, in Platinum's order: ID, NAME, MONEY, [DEX], SCORE, TIME, STARTED
  local keys = { "id", "name", "money" }
  if self:hasPokedex() then keys[#keys + 1] = "dex" end
  keys[#keys + 1] = "score"; keys[#keys + 1] = "time"; keys[#keys + 1] = "started"
  local rows = {}
  for i, key in ipairs(keys) do
    local at, value = FRONT[key], base[i] and base[i][2]
    if key == "started" then value = self:word("blankDate", value) end
    rows[#rows + 1] = { self:word(key, base[i] and base[i][1]), value, at[3], at[2], at[1] }
  end
  return rows
end

function HgssTrainerCard:backRows()
  local blank = self:word("blankDate", "--- --, ----")
  return {
    { self:word("hof", "HALL OF FAME DEBUT"), blank, BACK.hof[3], BACK.hof[2], BACK.hof[1] },
    { false, "--:--", BACK.hofTime[3], BACK.hofTime[2], BACK.hofTime[1] },
    { self:word("linked", "TIMES LINKED"), "0", BACK.linked[3], BACK.linked[2], BACK.linked[1] },
    { self:word("trades", "LINK TRADES"), "0", BACK.trades[3], BACK.trades[2], BACK.trades[1] },
  }
end

local function row(r)
  if r[1] then Font.draw(r[1], r[5], r[3]) end
  if r[2] then Font.draw(r[2], r[4] - Font.width(r[2]), r[3]) end
end

-- the frame behind the card (BG5's diamonds; the card covers all but the bar)
function HgssTrainerCard:drawCase()
  local frame = self:cardImg("card_frame")
  love.graphics.setColor(1, 1, 1, 1)
  if frame then love.graphics.draw(frame, 0, 0) end
  return frame ~= nil
end

function HgssTrainerCard:drawCardLayer(side)
  local g = love.graphics
  local face = self:faceImage(side)
  if not face then return false end
  g.setColor(1, 1, 1, 1)
  g.draw(face, 0, 0)
  self:ink()
  if side == "front" then
    local portrait = self:cardImg(self:female() and "lyra" or "ethan")
    if portrait then g.draw(portrait, 0, 0) end
    for _, r in ipairs(self:frontRows()) do row(r) end
    if self:colonShown() then Font.draw(":", FRONT.time[2] - COLON_FROM_RIGHT, FRONT.time[3]) end
  else
    for _, r in ipairs(self:backRows()) do row(r) end
    local b = BACK.battles
    Font.draw(self:word("battles", "LINK BATTLES"), b[1], b[3])
    local winsRight = b[2] - 8 * 8
    Font.draw(self:word("w", "W"), b[1] + 14 * 8, b[3])
    Font.draw("0", winsRight - Font.width("0"), b[3])
    Font.draw(self:word("l", "L"), b[1] + 22 * 8, b[3])
    Font.draw("0", b[2] - Font.width("0"), b[3])
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
  if side == "back" then
    local sig = self:signatureImage()
    if sig then g.draw(sig, SIG_X, SIG_Y) end
  end
  return true
end

-- the bottom bar, over the frame and not flipped with the card
function HgssTrainerCard:drawBar()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  for _, b in ipairs({ FLIP_BUTTON, BACK_BUTTON }) do self:drawSprite(b.key, b.x, BUTTON_Y) end
  Font.pushStyle({ text = FLIP_INK[1], shadow = FLIP_INK[2] })
  local flip = self:word("flip")
  if flip then Font.draw(flip, FLIP_LABEL.x, BUTTON_Y + 8) end
  Font.popStyle()
  Font.pushStyle({ text = BAR_INK[1], shadow = BAR_INK[2] })
  local cancel = self:word("cancel")
  if cancel then Font.draw(cancel, BACK_LABEL.x + floor((BACK_LABEL.w - Font.width(cancel)) / 2), BUTTON_Y + 8) end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

-- ----------------------------------------------------------------- board --

function HgssTrainerCard:earned()
  local out = {}
  for i, entry in ipairs(Badges.list(self.game.data) or {}) do
    if i <= 16 then out[i] = Badges.has(self.game.save or {}, entry) and true or false end
  end
  return out
end

function HgssTrainerCard:kantoOpen(earned)
  for i = 9, 16 do if earned[i] then return true end end
  return false
end

function HgssTrainerCard:drawBadges()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local back = self:cardImg("badge_backdrop")
  if back then g.draw(back, 0, 0) end
  local earned = self:earned()
  local kanto = self:kantoOpen(earned)
  local board = self:cardImg(kanto and "badge_board_kanto" or "badge_board_johto")
  if board then g.draw(board, 0, 0) end
  -- the emblems over their bands' empty rings
  local function all(from) for i = from, from + 7 do if not earned[i] then return false end end return true end
  if not kanto and all(1) then
    local e = self:cardImg("emblem_johto")
    if e then g.draw(e, EMBLEM_AT.johto[1], EMBLEM_AT.johto[2]) end
  elseif kanto and all(9) then
    local e = self:cardImg("emblem_kanto")
    if e then g.draw(e, EMBLEM_AT.kanto[1], EMBLEM_AT.kanto[2]) end
  end
  for i = 1, kanto and 16 or 8 do
    if earned[i] then
      local x = BADGE_X[(i - 1) % 4 + 1]
      local y = BADGE_Y[floor((i - 1) / 4) + 1] + (kanto and 0 or JOHTO_DROP)
      self:drawSprite("badge_" .. (i - 1), x, y)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function HgssTrainerCard:draw()
  local g = love.graphics
  local shown, SS = self:subscreenShown()
  g.setColor(0.10, 0.12, 0.18, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.page == PAGE_CASE and not shown then
    self:drawBadges()
  else
    self:drawSide(self.page == PAGE_BACK and "back" or "front")
    self:drawBar()
  end
  if shown then
    SS.draw(self.game, function()
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 0, 0, W, H)
      self:drawBadges()
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end
  g.setColor(1, 1, 1, 1)
end

return HgssTrainerCard
