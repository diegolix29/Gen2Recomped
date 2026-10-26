-- PLATINUM'S ACCESSORY SHOP -- the Floaroma flower shop's Beauty, who trades
-- Berries for contest Accessories (pokeplatinum
-- src/overlay007/accessory_shop.c, ShowAccessoryShop). Drawn over the field.
--
-- The windows are the cartridge's, in tiles: the message box (2, 19) 27 x 4,
-- the list (17, 1) 14 x 16 -- seven rows of the twenty-two Accessories and
-- EXIT, a row 16 pixels from 8 down, the scroll arrows at x 192, y 8 / 136
-- -- the description (1, 11) 14 x 6 -- the Berry, "Needed:" and "In Bag:"
-- (bank 572 #16-18) -- and YES / NO at (24, 13) 7 x 4.
--
-- The flow is AccessoryShop_Main's: "Hello! ... exchange your Berries" (#4);
-- with every Accessory already as many as the case holds, "Thank you so
-- much" (#5) and out; else "Which Accessory would you like?" (#6) over the
-- list; a pick asks #7 (the list hidden), YES checks the Berries (#9), the
-- case's room (#10, FashionCase_CanFitAccessoryCount: 9 of ids below 61, 1
-- of the rest) and trades (#8, then #12); the last one traded says #13 and
-- #5. EXIT or B: "Please come again!" (#11).

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local S = {}; S.__index = S
S.isOpaque = false

function S:uiSize() return 256, 192 end

S.BANK = 572
S.ACCESSORY_BANK = 386
S.ITEM_BANK, S.ITEM_PLURAL_BANK = 392, 394
S.FIRST_BERRY = 149                                -- ITEM_CHERI_BERRY
S.SHOWN = 7

-- sAccessoryShop_ItemLists: accessory id, berry (from Cheri), how many
S.ITEMS = {
  { 50, 0, 1 }, { 51, 1, 1 }, { 52, 2, 1 }, { 53, 6, 1 }, { 54, 3, 1 }, { 55, 4, 1 },
  { 56, 5, 1 }, { 57, 7, 1 }, { 58, 15, 10 }, { 59, 16, 10 }, { 60, 17, 10 },
  { 61, 18, 10 }, { 62, 19, 10 }, { 63, 26, 50 }, { 64, 31, 100 }, { 65, 27, 50 },
  { 66, 32, 100 }, { 67, 28, 50 }, { 68, 29, 50 }, { 69, 33, 100 }, { 70, 30, 100 },
  { 71, 34, 100 },
}

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

local function capOf(id) return id < 61 and 9 or 1 end

function S.new(game, onDone)
  local self = setmetatable({ game = game, data = game.data, onDone = onDone }, S)
  self.cursor, self.top = 1, 1
  self.listShown = false
  self.yes = 1
  self:say(4, "list")
  return self
end

-- ------------------------------------------------------------- the save --

function S:key(id)
  local k = ("ITEM_%03d"):format(id)
  if self.data.items and self.data.items[k] then return k end
  return id
end

function S:held(id)
  local inv = self.game.save and self.game.save.inventory or {}
  local k = self:key(id)
  return tonumber(inv[k]) or tonumber(inv[id]) or 0
end

function S:owned(acc)
  local a = self.game.save and self.game.save.gen4Accessories
  return tonumber(a and a[acc]) or 0
end

function S:canFit(acc) return self:owned(acc) + 1 <= capOf(acc) end

function S:hasAll()
  for _, it in ipairs(S.ITEMS) do if self:canFit(it[1]) then return false end end
  return true
end

-- AccessoryShop_DoPurchase
function S:trade(it)
  local save = self.game.save
  save.gen4Accessories = save.gen4Accessories or {}
  save.gen4Accessories[it[1]] = math.min(capOf(it[1]), self:owned(it[1]) + 1)
  local inv = save.inventory
  local k = self:key(S.FIRST_BERRY + it[2])
  if inv[k] == nil and inv[S.FIRST_BERRY + it[2]] ~= nil then k = S.FIRST_BERRY + it[2] end
  local left = (tonumber(inv[k]) or 0) - it[3]
  inv[k] = left > 0 and left or nil
end

-- --------------------------------------------------------------- the text --

function S:text(bank, n, ...)
  local T = require("src.import.Gen4Text")
  local bufs = self.game.stringBuffers
  local saved = {}
  if bufs then for i = 1, 3 do saved[i] = bufs[i] end end
  if select("#", ...) > 0 then T.buffer(self.game, ...) end
  local s = T.resolve(self.data, bank, n, self.game) or ""
  bufs = self.game.stringBuffers
  if bufs then for i = 1, 3 do bufs[i] = saved[i] end end
  return s
end

function S:berryName(it, plural)
  local id = S.FIRST_BERRY + it[2]
  local s = self:text(plural and S.ITEM_PLURAL_BANK or S.ITEM_BANK, id)
  if s == "" then
    local def = self.data.items and (self.data.items[self:key(id)] or self.data.items[id])
    s = def and def.name or tostring(id)
  end
  return s
end

function S:accessoryName(it) return self:text(S.ACCESSORY_BANK, it[1]) end

-- a message, page by page, then `nextState`; "wait" ones end on A / B
function S:say(n, nextState, ...)
  local s = self:text(S.BANK, n, ...)
  local pages = {}
  for p in (s .. "\f"):gmatch("([^\f\v\r]*)[\f\v\r]") do
    p = p:gsub("^\n+", ""):gsub("\n+$", "")
    if p ~= "" then pages[#pages + 1] = p end
  end
  if #pages == 0 then pages[1] = "" end
  self.msg = { pages = pages, page = 1, shown = 0, waitAB = nextState ~= "select" }
  self.nextState = nextState
  self.state = "message"
end

-- ----------------------------------------------------------------- update --

function S:update()
  local input = self.game.input
  local a = input and input:wasPressed("a")
  local b = input and input:wasPressed("b")
  local st = self.state
  if st == "message" then
    local m = self.msg
    local page = m.pages[m.page]
    if m.shown < #page then
      m.shown = (a or b) and #page or m.shown + 1
      return
    end
    if m.page < #m.pages then
      if a or b then m.page, m.shown = m.page + 1, 0 end
      return
    end
    if m.waitAB and not (a or b) then return end
    local nxt = self.nextState
    if nxt == "list" then
      if self:hasAll() then return self:say(5, "exit") end
      self.listShown = true
      return self:say(6, "select")
    elseif nxt == "buy" then
      self.listShown = true
      return self:say(6, "select")
    elseif nxt == "trade" then
      local it = S.ITEMS[self.cursor]
      self:trade(it)
      local plural = it[3] ~= 1
      self:say(12, self:hasAll() and "allTraded" or "buy", self:berryName(it, plural), tostring(it[3]), self:accessoryName(it))
      return
    elseif nxt == "allTraded" then
      return self:say(13, "thanks")
    elseif nxt == "thanks" then
      return self:say(5, "exit")
    elseif nxt == "exit" then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
      return
    end
    self.state = nxt
  elseif st == "select" then
    self:updateList(input, a, b)
  elseif st == "yesno" then
    if input:wasPressed("up") or input:wasPressed("down") then self.yes = 3 - self.yes; se(self, "SEQ_SE_DP_SELECT") end
    if a and self.yes == 1 then
      se(self, "SEQ_SE_DP_SELECT")
      local it = S.ITEMS[self.cursor]
      if self:held(S.FIRST_BERRY + it[2]) < it[3] then return self:say(9, "buy") end
      if not self:canFit(it[1]) then return self:say(10, "buy") end
      return self:say(8, "trade")
    elseif b or a then
      se(self, "SEQ_SE_DP_SELECT")
      self.listShown = true
      return self:say(6, "select")
    end
  end
end

function S:updateList(input, a, b)
  local count = #S.ITEMS + 1
  local was = self.cursor
  if input:wasPressed("up") and self.cursor > 1 then self.cursor = self.cursor - 1 end
  if input:wasPressed("down") and self.cursor < count then self.cursor = self.cursor + 1 end
  if input:wasPressed("left") then self.cursor = math.max(1, self.cursor - S.SHOWN) end
  if input:wasPressed("right") then self.cursor = math.min(count, self.cursor + S.SHOWN) end
  if self.cursor < self.top then self.top = self.cursor end
  if self.cursor >= self.top + S.SHOWN then self.top = self.cursor - S.SHOWN + 1 end
  if self.cursor ~= was then se(self, "SEQ_SE_DP_SELECT") end
  if b or (a and self.cursor == count) then
    se(self, "SEQ_SE_DP_SELECT")
    self.listShown = false
    return self:say(11, "exit")
  end
  if a then
    se(self, "SEQ_SE_DP_SELECT")
    self.listShown = false
    local it = S.ITEMS[self.cursor]
    self.yes = 1
    self:say(7, "yesno", self:berryName(it, it[3] ~= 1), tostring(it[3]), self:accessoryName(it))
  end
end

-- ------------------------------------------------------------------- draw --

local function ink() love.graphics.setColor(0.31, 0.31, 0.31, 1) end
local function white() love.graphics.setColor(1, 1, 1, 1) end

local function arrow(x, y, up)
  local g = love.graphics
  ink()
  if up then g.polygon("fill", x - 4, y + 4, x + 4, y + 4, x, y - 1)
  else g.polygon("fill", x - 4, y - 4, x + 4, y - 4, x, y + 1) end
  white()
end

function S:draw()
  local g = love.graphics
  if self.listShown then
    -- the list (17, 1) 14 x 16
    Font.drawStandardBox(16, 0, 16, 18)
    ink()
    for row = 0, S.SHOWN - 1 do
      local i = self.top + row
      local it = S.ITEMS[i]
      local label = it and self:accessoryName(it) or (i == #S.ITEMS + 1 and self:text(S.BANK, 19)) or nil
      if label then
        local y = 8 + 8 + row * 16
        Font.draw(label, 17 * 8 + 16, y)
        if i == self.cursor then Font.drawCode(require("src.ui.Theme").cursor, 17 * 8, y) end
      end
    end
    white()
    local blink = math.floor(love.timer.getTime() * 3) % 2 == 0
    if blink and self.top > 1 then arrow(192, 8, true) end
    if blink and self.top + S.SHOWN <= #S.ITEMS + 1 then arrow(192, 136, false) end
    -- the description (1, 11) 14 x 6
    local it = S.ITEMS[self.cursor]
    if it then
      Font.drawStandardBox(0, 10, 16, 8)
      ink()
      local berry = self:berryName(it, false)
      Font.draw(self:text(S.BANK, 16, berry), 8, 88)
      Font.draw(self:text(S.BANK, 17, berry, ("%3d"):format(it[3])), 8, 104)
      Font.draw(self:text(S.BANK, 18, berry, "", ("%3d"):format(self:held(S.FIRST_BERRY + it[2]))), 8, 120)
      white()
    end
  end
  if self.state == "yesno" then
    Font.drawStandardBox(23, 12, 9, 6)
    ink()
    local labels = { self:text(S.BANK, 14), self:text(S.BANK, 15) }
    for i = 1, 2 do
      local y = 13 * 8 + (i - 1) * 16
      Font.draw((labels[i] ~= "" and labels[i]) or Strings(i == 1 and "YES" or "NO"), 24 * 8 + 12, y)
      if self.yes == i then Font.drawCode(require("src.ui.Theme").cursor, 24 * 8, y) end
    end
    white()
  end
  -- the message box (2, 19) 27 x 4
  local m = self.msg
  if m then
    Font.drawDialogueBox(1, 18, 29, 6)
    ink()
    local text = m.pages[m.page]:sub(1, m.shown)
    local y = 19 * 8
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    white()
  end
end

return S
