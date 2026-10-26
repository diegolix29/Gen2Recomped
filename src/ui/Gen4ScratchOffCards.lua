-- PLATINUM'S SCRATCH-OFF CARDS -- pokeplatinum
-- src/applications/scratch_off_cards/main.c, on its own clock.
--
-- The Fight Area stand (M0499, a Battle Point a go): pick three of four
-- cards; each card offers four prizes (a Nugget and three berries out of
-- sAvailableItems) shown on the top screen beside the Pokemon that stands for
-- each; scratch three of its nine cells; three of a kind -- Ditto, the
-- wildcard, counting as anything -- wins that prize (a Nugget, or three
-- berries). The art is the cartridge's (src/import/Gen4ScratchOffArt.lua).
--
-- THE STATES are main.c's: FadeInApp, BringInSelectableCards, SelectCard,
-- PullOutSelectedCard (x3), then SetupScratchCard / ScratchCard /
-- SlideAwayScratchCard for each card, FadeOutApp -- with their sub-states,
-- timers and sounds. The scratching is the cartridge's own bookkeeping: a
-- 240 x 160 mask of touched pixels (MarkScratchedPixelsAtPoint, a 6 x 6
-- square a sample), a cell counting as revealed at 380 of its 25 x 20 centre
-- pixels (CheckIfCellIsRevealed), and the scratch layer losing a 6 x 6 square
-- under every sample inside the touched cell (ScratchPixelsAtPosition) --
-- only three cells may be scratched at all.
--
-- SCREENS. With both screens on view (a real second panel, or the stacked /
-- side-by-side layouts) the top screen is the main one and the touch screen
-- is SecondScreen's, as on the cartridge. With ONE screen (swap / inset /
-- off) the touch screen is the play surface, and the top screen -- the
-- prize list -- comes to it: shown by itself whenever a new card is laid out
-- (until a tap, A or two seconds), and any time from the PRIZES tab in the
-- corner or with X / Y / SELECT.
--
-- THE PORT'S OWN CONTROLS, beside the touch the cartridge needs: the
-- d-pad picks a card (A takes it); while scratching, the d-pad moves a
-- stylus and holding A scratches under it; START presses NEXT CARD /
-- CANCEL; the YES / NO box takes up / down and A, B being NO.

local Assets = require("src.render.Assets")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")

local S = {}; S.__index = S
S.isOpaque = true

local W, H = 256, 192
local NUM_CELLS, PICK, PLAY, PRIZES, TO_SCRATCH = 9, 4, 3, 4, 3
local WILDCARD = 4
local UNSET = 176
local REGION_W, REGION_H = 240, 160
local BANK, BANK_HGSS = 540, 432
local NUGGET = 92
local ITEMS = { 169, 170, 171, 172, 173, 174, 184, 185, 186, 187, 188, 189,
                190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200 }

local MON_POS = { { 57, 18 }, { 124, 18 }, { 191, 18 }, { 57, 66 }, { 124, 66 }, { 191, 66 },
                  { 57, 114 }, { 124, 114 }, { 191, 114 } }
local WIN_MON_POS = { { 52, 68 }, { 108, 68 }, { 164, 68 } }
local WIN_POPUP_POS = { 38, 56 }
local CARD_POS = { { 0, 36 }, { 56, 36 }, { 112, 36 }, { 168, 36 } }
local NEXT_POS, CANCEL_POS, CENTER_POS = { 68, 160 }, { 88, 160 }, { 68, 68 }
local CARD_HIT = { { 0, 42, 80, 154 }, { 88, 42, 138, 154 }, { 144, 42, 195, 154 }, { 204, 42, 254, 154 } }
local NEXT_HIT, CANCEL_HIT = { 76, 164, 180, 191 }, { 94, 164, 164, 191 }
local CELL_HIT = { { 32, 21, 89, 54 }, { 102, 21, 157, 54 }, { 170, 21, 227, 54 },
                   { 32, 68, 89, 100 }, { 102, 68, 157, 100 }, { 170, 68, 227, 100 },
                   { 32, 114, 89, 148 }, { 102, 114, 157, 148 }, { 170, 114, 227, 148 } }
local CELL_PIXELS = { { 42, 27 }, { 117, 27 }, { 189, 27 }, { 42, 74 }, { 117, 74 }, { 189, 74 },
                      { 42, 120 }, { 117, 120 }, { 189, 120 } }
local X_CENTER = { { 9, 9, 9, 8, 7, 6, 5, 4 }, { 2, 2, 2, 1, 1, 1, 1, 1 },
                   { -8, -8, -8, -7, -7, -6, -5, -4 }, { -18, -16, -15, -14, -13, -12, -10, -8 } }
local ITEM_NAME_Y = { 10, 12, 6, 8 }
local ITEM_WIN_TOP = { 3, 8, 14, 19 }
local TAB = { 0, 168, 63, 191 }                     -- the single-screen PRIZES tab

local function rand(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end
local function inside(r, x, y) return x and x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then
    local okP, src = pcall(Sound.playSe, self.data, name)
    return okP and src or nil
  end
end

local function stopSource(src)
  if src and src.stop then pcall(src.stop, src) end
end

local function playing(src)
  if not (src and src.isPlaying) then return false end
  local ok, p = pcall(src.isPlaying, src)
  return ok and p
end

-- Is the art in this cache?
function S.available(game)
  local art = game and game.data and game.data.gen4_scratch_off_art
  return type(art) == "table" and art.scratch ~= nil and art.mon_0 ~= nil
end

-- onDone(results): results[1..3] = { item, count }
function S.new(game, onDone)
  local self = setmetatable({ game = game, data = game.data, onDone = onDone }, S)
  self.art = game.data.gen4_scratch_off_art or {}
  self.ink = game.data.gen4_scratch_off or {}
  self.images = {}
  self.won = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
  self.state, self.sub = 0, 0
  self.currentCard = 0
  self.selected = {}
  self.cards = {}
  for i = 1, PICK do
    self.cards[i] = { x = CARD_POS[i][1] - W, y = CARD_POS[i][2], prio = 20 + i - 1, scale = 1, shown = true }
  end
  self.cellValues, self.cellScratched, self.cellRevealed = {}, {}, {}
  self.winnable = {}
  self.mask = {}
  self.screenFade = 16
  self.bgOffset = 0
  self.monX = 0                                     -- the sprites' xOffset
  self.cursor = { x = 128, y = 96 }
  self.pickIndex = 1
  self.view = "bottom"
  -- the scratch layer's own pixels, a fresh copy for every card
  local rec = self.art.scratch
  local okD, data = pcall(Assets.imageData, type(rec) == "table" and rec.path or rec)
  self.scratchSource = okD and data or nil
  return self
end

function S:uiSize() return W, H end
function S:wantsFillScale() return true end

-- both screens visible at once (a real panel, or the stacked layouts)?
function S:twoScreens()
  local g = self.game
  return SecondScreen.combined(g) or SecondScreen.mode(g) == "display"
end

-- -------------------------------------------------------------- the text --

function S:line(n, number, itemName)
  local Text = require("src.import.Gen4Text")
  local bufs = self.game.stringBuffers
  local saved = bufs and bufs[1]
  Text.buffer(self.game, itemName or (number and tostring(number)) or "")
  local hgss = (self.data.gen4_version or {}).family == "hgss"
  local s = Text.resolve(self.data, hgss and BANK_HGSS or BANK, n, self.game) or ""
  if bufs then bufs[1] = saved end
  return (s:gsub("[\r\n\f\v]+$", ""))
end

function S:itemName(id)
  local items = self.data.items or {}
  local def = items[id] or items[("ITEM_%03d"):format(id)]
  return def and def.name or tostring(id)
end

-- ---------------------------------------------------------- the clocks --

local function changeState(self, n) self.state, self.sub = n, 0 end

-- PlaceDittosInCells / PlaceRemainingValuesInCells / SelectItemsWinnableOnCard
function S:dealCard()
  for i = 1, NUM_CELLS do self.cellValues[i] = UNSET end
  for _ = 1, 2 do
    while true do
      local i = rand(NUM_CELLS) + 1
      if self.cellValues[i] == UNSET then self.cellValues[i] = WILDCARD break end
    end
  end
  local value, retries = rand(PRIZES), 0
  for i = 0, NUM_CELLS - 1 do
    while true do
      local c = rand(NUM_CELLS) + 1
      if self.cellValues[c] == UNSET then
        retries = 0
        self.cellValues[c] = value
        if i == 2 or i == 4 or i == 6 then value = (value + 1) % PRIZES end
        break
      end
      retries = retries + 1
      if retries >= 30 then
        retries = 0
        for j = 1, NUM_CELLS do
          if self.cellValues[j] == UNSET then
            self.cellValues[j] = value
            if i == 2 or i == 4 or i == 6 then value = (value + 1) % PRIZES end
            break
          end
        end
        break
      end
    end
  end
  local nugget, picked = rand(PRIZES), {}
  for i = 0, PRIZES - 1 do
    if i == nugget then
      self.winnable[i + 1] = NUGGET
    else
      while true do
        local k = rand(#ITEMS) + 1
        local dup = false
        for _, p in pairs(picked) do if p == k then dup = true end end
        if not dup then picked[i] = k; self.winnable[i + 1] = ITEMS[k] break end
      end
    end
  end
end

function S:freshScratchLayer()
  if self.scratchSource then
    local ok, copy = pcall(self.scratchSource.clone, self.scratchSource)
    self.scratchData = ok and copy or nil
    if self.scratchData then
      if self.scratchImage then self.scratchImage:release() end
      self.scratchImage = love.graphics.newImage(self.scratchData)
      self.scratchImage:setFilter("nearest", "nearest")
    end
  end
end

-- MarkScratchedPixelsAtPoint
function S:markPixels(tx, ty)
  for y = -3, 2 do
    for x = -3, 2 do
      local px, py = tx + x, ty + y
      if px > 0 and px < REGION_W and py > 0 and py < REGION_H then self.mask[px + py * REGION_W] = true end
    end
  end
end

-- RemoveScratchedOffPixels / ScratchPixelsAtPosition
function S:removePixels(tx, ty)
  local d = self.scratchData
  if not d then return end
  local dw, dh = d:getDimensions()
  for y = -3, 2 do
    for x = -3, 2 do
      local px, py = tx + x, ty + y
      if px > 0 and px < W and py > 0 and py < H and px < dw and py < dh then d:setPixel(px, py, 0, 0, 0, 0) end
    end
  end
  self.scratchDirty = true
end

-- CheckIfCellIsRevealed
function S:checkRevealed(cell)
  local left, top = CELL_PIXELS[cell][1], CELL_PIXELS[cell][2]
  local n = 0
  for y = top, top + 19 do
    for x = left, left + 24 do
      if self.mask[y * REGION_W + x] then n = n + 1 end
    end
  end
  if n >= 380 then
    if not self.cellRevealed[cell] then
      se(self, "SEQ_SE_DP_PIRORIRO")
      self.numRevealed = self.numRevealed + 1
      self.scratchedIdx[self.numRevealed] = cell
    end
    self.cellRevealed[cell] = true
  end
end

-- CheckIfThreeOfAKindFound
function S:threeOfAKind()
  if self.numRevealed <= 1 then return false end
  local v = function(i) return self.cellValues[self.scratchedIdx[i]] end
  if v(1) == v(2) or v(1) == WILDCARD or v(2) == WILDCARD then self.pairFound = true end
  if self.numRevealed <= 2 then return false end
  local a, b, c = v(1), v(2), v(3)
  local hit = (a == b and a == c) or (a == WILDCARD and b == WILDCARD) or (a == WILDCARD and c == WILDCARD)
    or (b == WILDCARD and c == WILDCARD) or (a == WILDCARD and b == c) or (b == WILDCARD and a == c)
    or (c == WILDCARD and a == b)
  if hit then
    for i = 1, TO_SCRATCH do
      if v(i) ~= WILDCARD then self.winningValue = v(i) break end
    end
    return true
  end
  return false
end

-- --------------------------------------------------------------- input --

function S:localPoint(px, py)
  if self:twoScreens() then return SecondScreen.toLocal(self.game, px, py) end
  -- one screen: the touch screen is the main surface itself
  local renderer = package.loaded["src.render.Renderer"]
  local rect = renderer and renderer.uiPresentation
  if type(rect) == "table" then
    if px < rect.x or py < rect.y or px >= rect.x + rect.w or py >= rect.y + rect.h then return nil end
    px, py = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
  end
  if px < 0 or py < 0 or px >= W or py >= H then return nil end
  return px, py
end

function S:touchpressed(_, px, py)
  local x, y = self:localPoint(px, py)
  if not x then return false end
  x, y = math.floor(x), math.floor(y)
  self.touch = { x = x, y = y, px = x, py = y, fresh = true }
  return true
end

function S:touchmoved(_, px, py)
  if not self.touch then return true end
  local x, y = self:localPoint(px, py)
  if x then self.touch.x, self.touch.y = math.floor(x), math.floor(y) end
  return true
end

function S:touchreleased()
  self.touch = nil
  return true
end

-- where the stylus is this frame, its samples since the last one, and
-- whether it was just put down
function S:stylus()
  local input = self.game.input
  local t = self.touch
  if t then
    local samples = {}
    local dx, dy = t.x - t.px, t.y - t.py
    local steps = math.max(1, math.floor(math.max(math.abs(dx), math.abs(dy))))
    for i = 1, steps do
      samples[#samples + 1] = { math.floor(t.px + dx * i / steps + 0.5), math.floor(t.py + dy * i / steps + 0.5) }
    end
    t.px, t.py = t.x, t.y
    local fresh = t.fresh
    t.fresh = false
    return t.x, t.y, samples, fresh
  end
  -- the port's stylus: the d-pad moves it, A holds it down
  if input and self.padStylus then
    local c = self.cursor
    local speed = 3
    local ox, oy = c.x, c.y
    if input:isDown("left") then c.x = math.max(0, c.x - speed) end
    if input:isDown("right") then c.x = math.min(W - 1, c.x + speed) end
    if input:isDown("up") then c.y = math.max(0, c.y - speed) end
    if input:isDown("down") then c.y = math.min(H - 1, c.y + speed) end
    if input:isDown("a") then
      local samples = {}
      local dx, dy = c.x - ox, c.y - oy
      local steps = math.max(1, math.max(math.abs(dx), math.abs(dy)))
      for i = 1, steps do samples[#samples + 1] = { math.floor(ox + dx * i / steps), math.floor(oy + dy * i / steps) } end
      return c.x, c.y, samples, input:wasPressed("a")
    end
  end
  return nil
end

function S:toggleView()
  if self:twoScreens() then return end
  self.view = (self.view == "top") and "bottom" or "top"
  self.peekTimer = nil
  se(self, "SEQ_SE_DP_SELECT")
end

-- ---------------------------------------------------------------- states --

function S:update()
  local input = self.game.input
  self.frame = (self.frame or 0) + 1
  -- the screen fade (StartScreenFade: 6 steps, 3 or 1 frame each)
  if self.fadeTarget then
    self.screenFade = self.screenFade + (self.fadeTarget > self.screenFade and 16 / 6 / self.fadeWait or -16 / 6 / self.fadeWait)
    if (self.fadeTarget == 0 and self.screenFade <= 0) or (self.fadeTarget == 16 and self.screenFade >= 16) then
      self.screenFade = self.fadeTarget
      self.fadeTarget = nil
    end
  end
  -- one screen: the prize list's own time on view, and the ways to it
  if not self:twoScreens() then
    if self.peekTimer then
      self.peekTimer = self.peekTimer - 1
      local tapped = self.touch and self.touch.fresh
      if self.peekTimer <= 0 or tapped or (input and (input:wasPressed("a") or input:wasPressed("b"))) then
        self.peekTimer = nil
        self.view = "bottom"
        if tapped then self.touch.fresh = false end
        return self:tickPopup()
      end
    elseif input and (input:wasPressed("x") or input:wasPressed("y") or input:wasPressed("select")) then
      self:toggleView()
    elseif self.view == "top" and self.touch and self.touch.fresh then
      self.touch.fresh = false
      self:toggleView()
      return
    elseif self.view == "bottom" and self.touch and self.touch.fresh and inside(TAB, self.touch.x, self.touch.y)
           and self.state >= 4 and self.state <= 6 then
      self.touch = nil
      self:toggleView()
      return
    end
    if self.view == "top" and self.state == 5 and self.sub == 3 then return self:tickPopup() end
  end
  local st = self.state
  if st == 0 then self:stateFadeIn()
  elseif st == 1 then self:stateBringIn()
  elseif st == 2 then self:stateSelect()
  elseif st == 3 then self:statePullOut()
  elseif st == 4 then self:stateSetup()
  elseif st == 5 then self:stateScratch()
  elseif st == 6 then self:stateSlideAway()
  elseif st == 7 then self:stateFadeOut() end
  self:tickPopup()
end

function S:tickPopup()
  local p = self.popup
  if p then
    p.tick = p.tick + 1
    local total = 0
    for _, f in ipairs(p.frames) do total = total + f[2] end
    if p.tick >= total then p.done = true end
  end
  if self.buttonAnimating then self.buttonTick = (self.buttonTick or 0) + 1 end
end

-- State_FadeInApp
function S:stateFadeIn()
  if self.sub == 0 then
    self.fadeTarget, self.fadeWait = 0, 3
    self.sub = 1
  elseif not self.fadeTarget then
    self.currentCard = 0
    changeState(self, 1)
  end
end

-- State_BringInSelectableCards
function S:stateBringIn()
  if self.sub == 0 then
    self.xOffset = -W
    for i = 1, PICK do
      local c = self.cards[i]
      c.x, c.y, c.prio = CARD_POS[i][1] + self.xOffset, CARD_POS[i][2], 20 + i - 1
    end
    self.selectMessage = self:line(12, self.currentCard + 1):gsub("{[^}]*}", "")
    self.xOffset2 = PICK
    se(self, "SEQ_SE_PL_SYU03")
    self.sub = 1
  elseif self.sub == 1 then
    self.xOffset = self.xOffset + 32
    local c = self.cards[self.xOffset2]
    c.x = CARD_POS[self.xOffset2][1] + self.xOffset
    if self.xOffset >= 0 then
      if self.xOffset2 == 1 then
        self.sub = 2
      else
        se(self, "SEQ_SE_PL_SYU03")
        self.xOffset2 = self.xOffset2 - 1
        self.xOffset = -W
      end
    end
  else
    self.xOffset = 0
    changeState(self, 2)
  end
end

-- State_SelectCard
function S:stateSelect()
  local input = self.game.input
  if self.sub == 0 then
    self.subTimer = 30
    self.sub = 1
    return
  end
  if self.subTimer > 0 then self.subTimer = self.subTimer - 1 end
  local picked
  local t = self.touch
  if t then
    for i = 1, PICK do if inside(CARD_HIT[i], t.x, t.y) then picked = i end end
  end
  if input then
    if input:wasPressed("left") then self.pickIndex = math.max(1, self.pickIndex - 1); self.padPicking = true end
    if input:wasPressed("right") then self.pickIndex = math.min(PICK, self.pickIndex + 1); self.padPicking = true end
    if input:wasPressed("a") then picked = self.pickIndex end
  end
  if picked then
    se(self, "SEQ_SE_DP_BUTTON9")
    self.currentCard = self.currentCard + 1
    self.selected[self.currentCard] = picked
    self.selectMessage = nil
    self.touch = nil
    changeState(self, 3)
  end
end

-- State_PullOutSelectedCard
function S:statePullOut()
  local idx = self.selected[self.currentCard]
  local card = self.cards[idx]
  if self.sub == 0 then
    self.scaleFx = 0x1000
    self.xOffset = 0
    self.centering = 0
    card.prio = 0
    self.sub = 1
  elseif self.sub == 1 then
    if self.centering < 8 then
      self.centering = self.centering + 1
      card.x = card.x + X_CENTER[idx][self.centering]
      card.y = card.y - 4
    end
    self.scaleFx = self.scaleFx + 0x100
    card.scale = self.scaleFx / 0x1000
    if self.scaleFx == 0x1800 then
      self.xOffset = 0
      self.scaleFx = 0x1000
      se(self, "SEQ_SE_PL_SYU03")
      self.sub = 2
    end
  elseif self.sub == 2 then
    self.xOffset = self.xOffset + 16
    for i = 1, PICK do self.cards[i].x = self.cards[i].x + 16 end
    if self.xOffset >= W then
      card.scale = 1
      self.sub = 3
    end
  else
    self.xOffset = 0
    if self.currentCard >= PLAY then
      self.currentCard = 0
      self.cardsGone = true
      changeState(self, 4)
    else
      changeState(self, 1)
    end
  end
end

-- State_SetupScratchCard
function S:stateSetup()
  if self.sub == 0 then
    self:freshScratchLayer()
    self.xOffset2 = W
    self.bgOffset = self.xOffset2
    self.layersOn = true
    self.xOffset = -W
    self.mask = {}
    self.numRevealed = 0
    self:dealCard()
    for i = 1, NUM_CELLS do self.cellScratched[i], self.cellRevealed[i] = false, false end
    self.sub = 1
  elseif self.sub == 1 then
    self.monX = self.xOffset
    self.monsShown = true
    self.matchShown = false
    self.highlight = 0
    self.pairFound = false
    self.scratchedIdx = { 177, 178, 179 }
    self.cardColour = self.selected[self.currentCard + 1] - 1
    se(self, "SEQ_SE_PL_SYU03")
    -- one screen: the new card's prizes first
    if not self:twoScreens() then self.view, self.peekTimer = "top", 120 end
    self.sub = 2
  elseif self.sub == 2 then
    self.bgOffset = self.xOffset2
    self.xOffset2 = self.xOffset2 - 16
    if self.xOffset >= 0 then
      self.sub = 3
    else
      self.monX = self.xOffset
    end
    self.xOffset = self.xOffset + 16
  else
    self.xOffset, self.xOffset2 = 0, 0
    changeState(self, 5)
  end
end

local function pressButton(self, last)
  self.buttonAnimating = true
  self.stopAsk = { yes = false, index = 1, last = last }
  se(self, "SEQ_SE_DP_BUTTON9")
end

-- State_ScratchCard
function S:stateScratch()
  local input = self.game.input
  local s = self.sub
  if s == 0 then
    self.lastCard = self.currentCard == PLAY - 1
    self.subTimer = 30
    self.centerText = self:line(9, self.currentCard + 1):gsub("{[^}]*}", "")
    self.centerShown = true
    self.namesShown = true
    self.buttonShown, self.buttonAnimating = true, false
    se(self, "SEQ_SE_PL_UG_020")
    self.sub = 1
  elseif s == 1 then
    self.sub = 2
  elseif s == 2 then
    if self.subTimer == 0 then
      self.centerShown, self.centerText = false, nil
      self.sub = 3
    else
      self.subTimer = self.subTimer - 1
    end
  elseif s == 3 then
    self.padStylus = true
    local x, y, samples, fresh = self:stylus()
    local cell
    if x then for i = 1, NUM_CELLS do if inside(CELL_HIT[i], x, y) then cell = i end end end
    if cell then
      local n = 0
      for i = 1, NUM_CELLS do if self.cellScratched[i] then n = n + 1 end end
      if n < TO_SCRATCH then self.cellScratched[cell] = true end
      if self.cellScratched[cell] then
        for _, p in ipairs(samples) do self:markPixels(p[1], p[2]) end
        self:checkRevealed(cell)
        local r = CELL_HIT[cell]
        for _, p in ipairs(samples) do
          if p[1] >= r[1] and p[1] <= r[3] and p[2] >= r[2] and p[2] <= r[4] then self:removePixels(p[1], p[2]) end
        end
        if not playing(self.kezuri) then self.kezuri = se(self, "SEQ_SE_PL_KEZURI") end
      end
      if self:threeOfAKind() then
        stopSource(self.kezuri)
        self.centerShown = true
        local prize = self.winnable[self.winningValue + 1]
        self.won[self.currentCard + 1] = { prize, prize == NUGGET and 1 or 3 }
        self.dittoMosaic = 0
        local ditto = false
        for i = 1, TO_SCRATCH do if self.cellValues[self.scratchedIdx[i]] == WILDCARD then ditto = true end end
        self.dittoTransform = ditto
        self.subTimer = ditto and 30 or 0
        self.winMons = {}
        for i = 1, TO_SCRATCH do self.winMons[i] = self.cellValues[self.scratchedIdx[i]] end
        self.popup = { tick = 0, frames = ((self.ink.sequences or {}).popup or {})[0] or { { 8, 1 } } }
        se(self, "SEQ_SE_PL_CALL")
        self.padStylus = false
        self.sub = 4
        return
      end
      if self.numRevealed >= TO_SCRATCH then
        stopSource(self.kezuri)
        self.subTimer = 60
        self.centerShown = true
        se(self, "SEQ_SE_DP_BOX03")
        self.centerText = self:line(11)
        self.padStylus = false
        self.sub = 7
        return
      end
    else
      stopSource(self.kezuri)
    end
    if self.pairFound then self:highlightPair() end
    -- NEXT CARD / CANCEL, by touch or START
    local t = self.touch
    local hit = self.lastCard and CANCEL_HIT or NEXT_HIT
    if (t and fresh and inside(hit, t.x, t.y)) or (input and input:wasPressed("start")) then
      self.touch = nil
      stopSource(self.kezuri)
      self.padStylus = false
      pressButton(self, self.lastCard)
      self.sub = self.lastCard and 10 or 9
    end
  elseif s == 4 then
    if self.subTimer == 0 then
      if not self:transformDitto(false) then self.sub = 5 end
    else
      self.subTimer = self.subTimer - 1
    end
  elseif s == 5 then
    if not self:transformDitto(true) then self.subTimer = 0; self.sub = 6 end
  elseif s == 6 then
    if self.popup and not self.popup.done then return end
    if self.subTimer == 0 then
      self.winMons, self.popup = nil, nil
      self.currentCard = self.currentCard + 1
      self.centerShown, self.centerText = false, nil
      changeState(self, self.currentCard >= PLAY and 7 or 6)
    else
      self.subTimer = self.subTimer - 1
    end
  elseif s == 7 then
    if self.subTimer == 0 then
      self.layersOn = "card"                        -- BG0 (the scratch layer) off
      self.currentCard = self.currentCard + 1
      self.centerShown, self.centerText = false, nil
      self.subTimer = 30
      self.sub = 8
    else
      self.subTimer = self.subTimer - 1
    end
  elseif s == 8 then
    if self.subTimer == 0 then
      changeState(self, self.currentCard >= PLAY and 7 or 6)
    else
      self.subTimer = self.subTimer - 1
    end
  elseif s == 9 or s == 10 then
    local ask = self.stopAsk
    local answer
    local t = self.touch
    if t and t.fresh then
      t.fresh = false
      if inside({ 192, 64, 248, 88 }, t.x, t.y) then answer = "yes"
      elseif inside({ 192, 88, 248, 112 }, t.x, t.y) then answer = "no" end
    end
    if input then
      if input:wasPressed("up") or input:wasPressed("down") then ask.index = 3 - ask.index end
      if input:wasPressed("a") then answer = ask.index == 1 and "yes" or "no" end
      if input:wasPressed("b") then answer = "no" end
    end
    if answer then
      self.buttonAnimating = false
      self.stopAsk = nil
      se(self, "SEQ_SE_DP_BUTTON9")
      if answer == "yes" then
        self.currentCard = self.currentCard + 1
        changeState(self, self.currentCard >= PLAY and 7 or 6)
      else
        self.sub = 11
      end
    end
  elseif s == 11 then
    if not self.touch then self.sub = 3 end
  end
end

-- HighlightMatchingPair: the two boxes on row 3 of palette 22 + n, n
-- stepping every frame through eight
function S:highlightPair()
  self.highlight = (self.highlight + 1) % 8
  if self.numRevealed == 2 then self.matchShown = true end
end

-- UpdateTransformingDitto
function S:transformDitto(decrease)
  if not self.dittoTransform then return false end
  if not decrease then
    if self.dittoMosaic == 0 then se(self, "SEQ_SE_PL_W100") end
    if self.dittoMosaic < 4 then
      self.dittoMosaic = self.dittoMosaic + 1
    else
      for i = 1, TO_SCRATCH do
        if self.winMons[i] == WILDCARD then self.winMons[i] = self.winningValue end
      end
      return false
    end
  elseif self.dittoMosaic > 0 then
    self.dittoMosaic = self.dittoMosaic - 1
  else
    return false
  end
  return true
end

-- State_SlideAwayScratchCard
function S:stateSlideAway()
  if self.sub == 0 then
    self.buttonShown = false
    self.namesShown = false
    self.xOffset, self.xOffset2 = 0, 0
    se(self, "SEQ_SE_PL_SYU03")
    self.sub = 1
  elseif self.sub == 1 then
    self.bgOffset = self.xOffset2
    self.xOffset2 = self.xOffset2 - 16
    if self.xOffset >= W then
      self.sub = 2
    else
      self.monX = self.xOffset
      self.matchShown = false
    end
    self.xOffset = self.xOffset + 16
  else
    self.xOffset, self.xOffset2 = 0, 0
    changeState(self, 4)
  end
end

-- State_FadeOutApp
function S:stateFadeOut()
  if self.sub == 0 then
    self.fadeDelay = 10
    self.sub = 1
  elseif self.sub == 1 then
    self.fadeDelay = self.fadeDelay - 1
    if self.fadeDelay == 0 then
      self.fadeTarget, self.fadeWait = 16, 1
      self.sub = 2
    end
  elseif self.sub == 2 and not self.fadeTarget then
    self.sub = 3
    stopSource(self.kezuri)
    self.game.stack:pop()
    if self.onDone then self.onDone(self.won) end
  end
end

-- ------------------------------------------------------------------ draw --

function S:image(key)
  local rec = self.art[key]
  local path = type(rec) == "table" and rec.path or rec
  if not path then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.images[path] = ok and img or false
    if self.images[path] then self.images[path]:setFilter("nearest", "nearest") end
  end
  return self.images[path] or nil, rec
end

-- a cell picture with its origin (the cell's OAM extent)
function S:sprite(key, x, y, scale)
  local img, rec = self:image(key)
  if not img then return end
  local ox = type(rec) == "table" and rec.originX or 0
  local oy = type(rec) == "table" and rec.originY or 0
  if scale and scale ~= 1 then
    -- AFFINE_OVERWRITE_MODE_DOUBLE: scaled about the sprite's centre
    local w, h = img:getDimensions()
    love.graphics.draw(img, x + ox + w / 2, y + oy + h / 2, 0, scale, scale, w / 2, h / 2)
  else
    love.graphics.draw(img, x + ox, y + oy)
  end
end

local function frameAt(frames, tick)
  local t = 0
  for _, f in ipairs(frames or {}) do
    t = t + f[2]
    if tick < t then return f[1] end
  end
  local last = frames and frames[#frames]
  return last and last[1] or 0
end

local mosaicShader
local function mosaic(level, fn)
  if level <= 0 then return fn() end
  local g = love.graphics
  if mosaicShader == nil then
    local ok, sh = pcall(g.newShader, [[
      extern float block;
      extern vec2 size;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec2 px = floor(uv * size / block) * block + 0.5;
        return Texel(tex, px / size) * colour;
      }
    ]])
    mosaicShader = ok and sh or false
  end
  if not mosaicShader then return fn() end
  local prev = g.getShader()
  mosaicShader:send("block", level + 1)
  mosaicShader:send("size", { 40, 40 })
  g.setShader(mosaicShader)
  fn()
  g.setShader(prev)
end

local function backdrop(c)
  local g = love.graphics
  c = c or { 0, 0, 0 }
  g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
end

-- the TOP screen: the prize list
function S:drawTop()
  local g = love.graphics
  local Font = require("src.render.Font")
  backdrop(self.ink.backdropTop)
  local base = self:image("topBase")
  if base then g.draw(base, 0, 0) end
  if self.layersOn and self.cardColour then
    local card = self:image("topCard_" .. self.cardColour)
    if card then
      -- BG2's 512-wide map scrolled by bgOffset (screen = map - offset, wrapping)
      local x = -self.bgOffset
      g.draw(card, x, 0); g.draw(card, x + 512, 0); g.draw(card, x - 512, 0)
    end
  end
  if self.monsShown and self.winnable[1] then
    for i = 1, PRIZES do self:sprite("mon_" .. (i - 1), 60 + self.monX, 26 + (i - 1) * 42) end
  end
  if self.namesShown then
    g.setColor(0.16, 0.16, 0.16, 1)
    for i = 1, PRIZES do
      local name = self:itemName(self.winnable[i])
      local cx = 17 * 8 + 44
      Font.draw(name, cx - math.floor((Font.width(name) + 1) / 2), ITEM_WIN_TOP[i] * 8 + ITEM_NAME_Y[i])
    end
    g.setColor(1, 1, 1, 1)
  end
  if self.selectMessage then
    Font.drawBox(1, 18, 29, 6)
    g.setColor(0, 0, 0, 1)
    Font.draw(self.selectMessage, 2 * 8 + 1, 19 * 8 + 1)
    g.setColor(1, 1, 1, 1)
  end
end

-- the TOUCH screen: the cards and the scratching
function S:drawBottom(single)
  local g = love.graphics
  local Font = require("src.render.Font")
  backdrop(self.ink.backdropBottom)
  if self.layersOn then
    local card = self.cardColour and self:image("bottomCard_" .. self.cardColour)
    local x = -self.bgOffset
    if card then g.draw(card, x, 0); g.draw(card, x + 512, 0); g.draw(card, x - 512, 0) end
    -- priority 2 sprites: the matching boxes under the Pokemon
    if self.matchShown and self.numRevealed >= 2 then
      for i = 1, 2 do
        local p = MON_POS[self.scratchedIdx[i]]
        if p then self:sprite("box_6_hl" .. self.highlight, p[1] - 36, p[2] - 10) end
      end
    end
    if self.monsShown then
      for i = 1, NUM_CELLS do
        local v = self.cellValues[i]
        if v and v ~= UNSET then self:sprite("mon_" .. v, MON_POS[i][1] + self.monX, MON_POS[i][2]) end
      end
    end
    -- BG0, the scratch layer (off once a card is lost, State_ScratchCard 7)
    if self.layersOn ~= "card" and self.scratchImage then
      if self.scratchDirty then self.scratchImage:replacePixels(self.scratchData); self.scratchDirty = false end
      g.draw(self.scratchImage, x, 0); g.draw(self.scratchImage, x + 512, 0)
    end
  end
  -- priority 1 sprites: the cards while picking, the button, the centre box
  if not self.cardsGone then
    local order = {}
    for i = 1, PICK do order[i] = i end
    table.sort(order, function(a, b) return self.cards[a].prio > self.cards[b].prio end)
    for _, i in ipairs(order) do
      local c = self.cards[i]
      self:sprite("card_" .. (i - 1), c.x, c.y, c.scale)
    end
    if self.state == 2 and self.padPicking then
      local c = self.cards[self.pickIndex]
      g.setColor(1, 1, 1, 0.5 + 0.5 * math.abs(math.sin((self.frame or 0) / 8)))
      g.rectangle("line", c.x + 1, c.y + 1, 86, 118)
      g.setColor(1, 1, 1, 1)
    end
  end
  if self.buttonShown then
    local pos = self.lastCard and CANCEL_POS or NEXT_POS
    local seq = self.lastCard and 0 or 1
    local frames = ((self.ink.sequences or {}).box or {})[seq] or { { self.lastCard and 0 or 3, 1 } }
    local cell = self.buttonAnimating and frameAt(frames, (self.buttonTick or 0) % 4) or frames[1][1]
    self:sprite("box_" .. cell, pos[1], pos[2])
    local label = self:line(self.lastCard and 5 or 4)
    local left = self.lastCard and 13 * 8 or 10 * 8
    local half = self.lastCard and 24 or 48
    g.setColor(1, 1, 1, 1)
    Font.draw(label, left + half - math.floor((Font.width(label) + 1) / 2), 21 * 8 + 1)
  end
  if self.centerShown then
    self:sprite("box_7", CENTER_POS[1], CENTER_POS[2])
    if self.centerText then
      g.setColor(0.16, 0.16, 0.16, 1)
      Font.draw(self.centerText, 10 * 8 + 48 - math.floor((Font.width(self.centerText) + 1) / 2), 9 * 8 + 5)
      g.setColor(1, 1, 1, 1)
    end
  end
  -- priority 0: the win popup and its Pokemon
  if self.popup and not self.popup.done then
    local frames = self.popup.frames
    self:sprite("popup_" .. frameAt(frames, self.popup.tick), WIN_POPUP_POS[1], WIN_POPUP_POS[2])
    for i = 1, TO_SCRATCH do
      local v = self.winMons and self.winMons[i]
      if v then
        local wild = self.dittoTransform and self.cellValues[self.scratchedIdx[i]] == WILDCARD
        mosaic(wild and self.dittoMosaic or 0, function()
          self:sprite("mon_" .. v, WIN_MON_POS[i][1], WIN_MON_POS[i][2])
        end)
      end
    end
  end
  -- "Stop scratching this card?" and its YES / NO
  if self.stopAsk then
    Font.drawBox(1, 0, 29, 6)
    g.setColor(0, 0, 0, 1)
    Font.draw(self:line(6), 2 * 8 + 1, 1 * 8 + 1)
    g.setColor(1, 1, 1, 1)
    for i, label in ipairs({ Strings("YES"), Strings("NO") }) do
      local y = 64 + (i - 1) * 24
      Font.drawBox(24, (y / 8) - 1, 7, 3)
      g.setColor(0, 0, 0, 1)
      if self.stopAsk.index == i then Font.drawCode(require("src.ui.Theme").cursor, 24 * 8 + 4, y + 1) end
      Font.draw(label, 25 * 8 + 4, y + 1)
      g.setColor(1, 1, 1, 1)
    end
  end
  -- the port's stylus, when the d-pad is driving it
  if self.state == 5 and self.sub == 3 and not self.touch then
    local c = self.cursor
    g.setColor(1, 1, 1, 0.9)
    g.circle("line", c.x, c.y, 4)
    g.setColor(1, 1, 1, 1)
  end
  -- one screen: the tab back to the prizes
  if single and self.state >= 4 and self.state <= 6 then
    Font.drawBox(0, 21, 8, 3)
    g.setColor(0, 0, 0, 1)
    Font.draw(Strings("PRIZES"), 8, 176)
    g.setColor(1, 1, 1, 1)
  end
end

function S:drawFade()
  if self.screenFade > 0 then
    local g = love.graphics
    g.setColor(0, 0, 0, math.min(1, self.screenFade / 16))
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end
end

function S:draw()
  if self:twoScreens() then
    self:drawTop()
    self:drawFade()
    SecondScreen.draw(self.game, function()
      self:drawBottom(false)
      self:drawFade()
    end)
    return
  end
  if self.view == "top" then
    self:drawTop()
    -- the way back, said once on screen
    local Font = require("src.render.Font")
    local g = love.graphics
    if self.state >= 4 and self.state <= 6 then
      g.setColor(0, 0, 0, 0.55)
      g.rectangle("fill", 0, H - 14, W, 14)
      g.setColor(1, 1, 1, 1)
      Font.draw(Strings("Tap / A: back to the card"), 4, H - 13)
    end
  else
    self:drawBottom(true)
    -- picking a card: the top screen's "Please select card no. N." here
    if self.selectMessage then
      local Font = require("src.render.Font")
      local g = love.graphics
      Font.drawBox(1, 0, 29, 4)
      g.setColor(0, 0, 0, 1)
      Font.draw(self.selectMessage, 2 * 8 + 1, 8 + 1)
      g.setColor(1, 1, 1, 1)
    end
  end
  self:drawFade()
end

return S
