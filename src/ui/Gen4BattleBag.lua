-- src/ui/Gen4BattleBag.lua
--
-- PLATINUM'S BATTLE BAG -- the BOTTOM-SCREEN bag BAG opens in a battle
-- (src/battle_sub_menus/battle_bag*.c), drawn while the battle stays on the
-- top screen.  Three screens, all on b_bag_gra's art (Gen4BattleArt bbag_*):
--
--   MENU     the four battle pockets -- HP/PP RESTORE, STATUS HEALERS,
--            POKe BALLS, BATTLE ITEMS -- the "Item used last" bar and CANCEL
--   POCKET   six items a page, the page arrows and "n/m", the pocket's name
--   USE      one item: name, "xN", description, USE / CANCEL
--
-- Everything placed here is the cartridge's number, out of the decomp:
--   buttons    sButtonDimensions (pocket buttons (0,1) (0,10) (16,1) (16,10)
--              16x9; Item used last (0,19) 26x5; CANCEL (27,19); items (0,1)
--              (16,1) (0,7) (16,7) (0,13) (16,13) 16x6; prev (0,19) next
--              (5,19); USE (0,19)), in tiles after SetupBackgroundScroll
--   windows    sMenuScreenWindowTemplates / sPocketMenuScreenWindowTemplates /
--              useItemScreenWindowTemplates, FONT_SUBSCREEN TEXT_COLOR(3,2,1)
--              on palette 0, FONT_SYSTEM TEXT_COLOR(1,2,0) on palette 4
--   sprites    item icons at (44|172, 45|93|141), the last used item's at
--              (24, 178), the chosen item's at (40, 44)
--   touch      sMenuTouchRects / sPocketMenuTouchRects / sUseItemMenuTouchRects
--   cursor     menuScreenCursorPositions / pocketMenuScreenCursorPositions /
--              useItemScreenCursorPositions (src/ui/Gen4SubMenuCursor.lua)
--   pockets    BattleBag_Init: every bag slot, field pocket by field pocket, is
--              filed in each battle pocket its ITEM_PARAM_BATTLE_POCKET mask
--              names (bit 0 balls, 1 battle items, 2 HP, 3 status, 4 PP)
--   paging     six a page, pages wrap (BattleBagTask_ChangePocketPage)
--   presses    BattleBagButtons_Tick: PRESSING then PRESSED (the button's
--              words and icon 4 then 2 px up), then the next screen
--   errors     TryUseItem's: two foes, a foe out of sight, a foe behind a
--              substitute, no room in the PC -- battle_bag bank 2 lines 44..48
--              -- in the message box at window (2,19) 27x4
--
-- The bag cursor (pocket, page and position per pocket, the last item used)
-- lives on the game like the cartridge's BagCursor, which outlives a battle.
--
-- USING an item is the port's own item flow (src/ui/BagMenu.lua useItem), so
-- a POTION here does exactly what it does from the field bag; the target is
-- picked on the battle party list's USE ON WHICH POKeMON? page.

local Strings = require("src.core.Strings")
local Cursor = require("src.ui.Gen4SubMenuCursor")

local Gen4BattleBag = {}
Gen4BattleBag.__index = Gen4BattleBag
Gen4BattleBag.isOpaque = false

Gen4BattleBag.BANK = 2
Gen4BattleBag.TEXT = {
  hpPP = 0, restore = 1, status = 2, healers = 3, battleItems = 6, pokeBalls = 7,
  usedLast = 8, pocketHPPP = 22, pocketRestore = 23, pocketStatus = 24,
  pocketHealers = 25, pocketBalls = 26, pocketBattleItems = 27, use = 31,
  noUse = 34, twoPokemon = 44, noRoom = 45, hidden = 47, substitute = 48,
}

-- battle pocket indices (ITEM_BATTLE_CATEGORY_*), 0-based as the cartridge's
Gen4BattleBag.POCKET = { HP = 0, STATUS = 1, BALLS = 2, BATTLE = 3 }
-- the mask bit -> pocket (sBattlePocketIndexes)
Gen4BattleBag.MASK_POCKET = { [0] = 2, 3, 0, 1, 0 }
Gen4BattleBag.PER_PAGE = 6

Gen4BattleBag.MENU_TOUCH = {
  { 8, 79, 0, 127 }, { 80, 151, 0, 127 }, { 8, 79, 128, 255 },
  { 80, 151, 128, 255 }, { 152, 191, 0, 207 }, { 152, 191, 216, 255 },
}
Gen4BattleBag.POCKET_TOUCH = {
  { 8, 55, 0, 127 }, { 8, 55, 128, 255 }, { 56, 103, 0, 127 },
  { 56, 103, 128, 255 }, { 104, 151, 0, 127 }, { 104, 151, 128, 255 },
  { 152, 191, 0, 39 }, { 152, 191, 40, 79 }, { 152, 191, 216, 255 },
}
Gen4BattleBag.USE_TOUCH = { { 152, 191, 0, 207 }, { 152, 191, 216, 255 } }

local P = function(n) return { prev = n } end
Gen4BattleBag.MENU_CURSOR = {
  { 8, 16, 120, 72,    up = 1, down = 2, left = 1, right = 3 },
  { 8, 88, 120, 144,   up = 1, down = 5, left = 2, right = 4 },
  { 136, 16, 248, 72,  up = 3, down = 4, left = 1, right = 3 },
  { 136, 88, 248, 144, up = 3, down = 6, left = 2, right = 4 },
  { 8, 160, 200, 184,  up = 2, down = 5, left = 5, right = 6 },
  { 224, 160, 248, 184, up = P(4), down = 6, left = 5, right = 6 },
}
Gen4BattleBag.POCKET_CURSOR = {
  { 8, 16, 120, 48,    up = 1, down = 3, left = 1, right = 2 },
  { 136, 16, 248, 48,  up = 2, down = 4, left = 1, right = 2 },
  { 8, 64, 120, 96,    up = 1, down = 5, left = 3, right = 4 },
  { 136, 64, 248, 96,  up = 2, down = 6, left = 3, right = 4 },
  { 8, 112, 120, 144,  up = 3, down = P(7), left = 5, right = 6 },
  { 136, 112, 248, 144, up = 4, down = 9, left = 5, right = 6 },
  { 8, 160, 32, 184,   up = 5, down = 7, left = 7, right = 8 },
  { 48, 160, 72, 184,  up = 5, down = 8, left = 7, right = 9 },
  { 224, 160, 248, 184, up = 6, down = 9, left = 8, right = 9 },
}
Gen4BattleBag.USE_CURSOR = {
  { 8, 160, 200, 184,  up = 1, down = 1, left = 1, right = 2 },
  { 224, 160, 248, 184, up = 2, down = 2, left = 1, right = 2 },
}

-- where each button is drawn (pixels) on its screen
Gen4BattleBag.POCKET_BTN_AT = { [0] = { 0, 8 }, { 0, 80 }, { 128, 8 }, { 128, 80 } }
Gen4BattleBag.ITEM_BTN_AT = { { 0, 8 }, { 128, 8 }, { 0, 56 }, { 128, 56 }, { 0, 104 }, { 128, 104 } }
Gen4BattleBag.ITEM_ICON_AT = { { 44, 45 }, { 172, 45 }, { 44, 93 }, { 172, 93 }, { 44, 141 }, { 172, 141 } }
Gen4BattleBag.LAST_ICON_AT = { 24, 178 }
Gen4BattleBag.USE_ICON_AT = { 40, 44 }

function Gen4BattleBag.available(data)
  local art = data and data.gen4_battle_art
  return art and art.bbag_menu and art.bbag_pocketbtn_0_0 and art.bbag_item_0_0 and true or false
end

-- the cartridge's BagCursor: survives the battle, as the field system's does
local function bagCursor(game)
  game.gen4BattleBagCursor = game.gen4BattleBagCursor or {
    pocket = 0, pages = { [0] = 0, 0, 0, 0 }, positions = { [0] = 0, 0, 0, 0 },
    lastItem = nil, lastPocket = 0,
  }
  return game.gen4BattleBagCursor
end
Gen4BattleBag.bagCursor = bagCursor

function Gen4BattleBag.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4BattleBag)
  self.game = game
  self.battle = opts.battle
  self.onCancel = opts.onCancel
  self.t = 0
  self.images = {}
  local data = game and game.data or {}
  self.art = data.gen4_battle_art or {}
  local anims = data.gen4_battle_anims or {}
  self.ink = anims.bagInk or {}
  self.cur = bagCursor(game)
  self:build()
  -- BattleBag_CanUseLastUsedItem: forget an item no longer carried
  if self.cur.lastItem and (tonumber((game.save.inventory or {})[self.cur.lastItem]) or 0) <= 0 then
    self.cur.lastItem, self.cur.lastPocket = nil, 0
  end
  self.cursor = Cursor.new(self.battle or game, Gen4BattleBag.MENU_CURSOR, (self.cur.pocket or 0) + 1)
  self:setScreen("menu")
  return self
end

function Gen4BattleBag:uiSize()
  if self.battle and self.battle.uiSize then return self.battle:uiSize() end
  return 256, 192
end

-- BattleBag_Init: the four battle pockets out of the bag, in field-pocket
-- order and bag order within a pocket.
function Gen4BattleBag:build()
  local game = self.game
  local Bag = require("src.inventory.Bag")
  local items = game.data.items or {}
  local order = Bag.order(game.save) or {}
  local rank = {}
  for i, id in ipairs(order) do rank[id] = i end
  local sorted = {}
  for _, id in ipairs(order) do sorted[#sorted + 1] = id end
  table.sort(sorted, function(a, b)
    local da, db = items[a] or {}, items[b] or {}
    local pa, pb = tonumber(da.fieldPocket) or 99, tonumber(db.fieldPocket) or 99
    if pa ~= pb then return pa < pb end
    return rank[a] < rank[b]
  end)
  self.pockets = { [0] = {}, {}, {}, {} }
  for _, id in ipairs(sorted) do
    local def = items[id]
    local qty = tonumber((game.save.inventory or {})[id]) or 0
    local mask = def and tonumber(def.battlePocket) or 0
    if qty > 0 and mask > 0 then
      for bit = 0, 4 do
        if math.floor(mask / 2 ^ bit) % 2 == 1 then
          local p = Gen4BattleBag.MASK_POCKET[bit]
          local list = self.pockets[p]
          local seen = false
          for _, row in ipairs(list) do if row.id == id then seen = true end end
          if not seen then list[#list + 1] = { id = id, qty = qty, def = def } end
        end
      end
    end
  end
  self.pageCount = {}
  for p = 0, 3 do
    local n = #self.pockets[p]
    self.pageCount[p] = n == 0 and 0 or math.floor((n - 1) / Gen4BattleBag.PER_PAGE)
    if (self.cur.pages[p] or 0) > self.pageCount[p] then self.cur.pages[p] = self.pageCount[p] end
  end
end

-- BattleBag_GetItem: the row at a page position of the current pocket
function Gen4BattleBag:itemAt(pos, pocket)
  pocket = pocket or self.pocket or 0
  local row = self.pockets[pocket][(self.cur.pages[pocket] or 0) * Gen4BattleBag.PER_PAGE + pos]
  if row and row.qty > 0 then return row end
  return nil
end

function Gen4BattleBag:setScreen(name)
  self.screen = name
  self.press = nil
  if name == "menu" then
    self.cursor:set(Gen4BattleBag.MENU_CURSOR, (self.cur.pocket or 0) + 1)
  elseif name == "pocket" then
    self.cursor:set(Gen4BattleBag.POCKET_CURSOR, (self.cur.positions[self.pocket] or 0) + 1)
  else
    self.cursor:set(Gen4BattleBag.USE_CURSOR, 1)
  end
end

-- ---------------------------------------------------------------- words --

function Gen4BattleBag:text(id, fallback)
  local data = self.game and self.game.data
  local s = data and data.text and data.text[("TEXT_B%04d_%05d"):format(Gen4BattleBag.BANK, id)]
  if type(s) ~= "string" or s == "" then return Strings(fallback or "") end
  return (s:gsub("{[^}]*}", ""))
end

local function rgb(c)
  c = c or { 0, 0, 0 }
  return { c[1] / 255, c[2] / 255, c[3] / 255, 1 }
end

function Gen4BattleBag:image(key)
  local rec = self.art[key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
  end
  return self.images[path] or nil, rec
end

function Gen4BattleBag:drawArt(key, x, y)
  local img = self:image(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, math.floor(x), math.floor(y))
  return true
end

-- palette 0 TEXT_COLOR(3, 2, 1) or palette 4 TEXT_COLOR(1, 2, 0)
function Gen4BattleBag:words(text, x, y, face, row, a, s)
  local Font = require("src.render.Font")
  local faced = face and Font.pushFace(face)
  local ink = self.ink[row] or {}
  local tone = ink[a] and ink[s] and Font.beginTwoTone and Font.beginTwoTone(rgb(ink[a]), rgb(ink[s]))
  if not tone then love.graphics.setColor(0, 0, 0, 1) end
  Font.draw(text, math.floor(x), math.floor(y))
  if tone then Font.endTwoTone() end
  if faced then Font.popFace() end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4BattleBag:width(text, face)
  local Font = require("src.render.Font")
  local faced = face and Font.pushFace(face)
  local w = Font.width and Font.width(text) or #text * 8
  if faced then Font.popFace() end
  return w
end

-- PrintTextToWindow: centred in the window
function Gen4BattleBag:centred(text, wx, wy, ww, face, row, a, s)
  local w = self:width(text, face)
  self:words(text, wx + math.floor((ww - w) / 2), wy, face, row, a, s)
end

function Gen4BattleBag:itemName(row)
  local def = row and (row.def or (self.game.data.items or {})[row.id])
  return def and def.name or tostring(row and row.id or "")
end

function Gen4BattleBag:drawItemIcon(id, cx, cy)
  local def = (self.game.data.items or {})[id]
  local n = def and tonumber(def.id) or tonumber(id)
  local screens = (self.game.data.gen4_graphics or {}).screens or {}
  local rec = n and screens[("items/icon_%03d"):format(n)]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
  end
  local img = self.images[path]
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, math.floor(cx - img:getWidth() / 2), math.floor(cy - img:getHeight() / 2))
end

-- ----------------------------------------------------------------- draw --

-- the face a button shows: PRESSING 1, PRESSED 2 for the frames after a press
function Gen4BattleBag:stateOf(name)
  local p = self.press
  if p and p.name == name then return p.state end
  return 0
end

-- how far a pressed button's words and icon rise (UpdateWindowScroll /
-- UpdateSpritePositions: -4 pressing, -2 pressed)
local LIFT = { [0] = 0, -4, -2 }

function Gen4BattleBag:drawMenu()
  self:drawArt("bbag_menu", 0, 0)
  local T = Gen4BattleBag.TEXT
  for p = 0, 3 do
    local s = self:stateOf("pocket" .. p)
    local at = Gen4BattleBag.POCKET_BTN_AT[p]
    self:drawArt(("bbag_pocketbtn_%d_%d"):format(p, s), at[1], at[2])
  end
  local function title(p, a, b, x, y)
    local dy = LIFT[self:stateOf("pocket" .. p)]
    if b then
      self:centred(self:text(a[1], a[2]), x, y + 8 + dy, 96, "subscreen", "row0", 3, 2)
      self:centred(self:text(b[1], b[2]), x, y + 24 + dy, 96, "subscreen", "row0", 3, 2)
    else
      self:centred(self:text(a[1], a[2]), x, y + 8 + dy, 96, "subscreen", "row0", 3, 2)
    end
  end
  title(0, { T.hpPP, "HP/PP" }, { T.restore, "RESTORE" }, 16, 32)
  title(1, { T.status, "STATUS" }, { T.healers, "HEALERS" }, 16, 104)
  title(2, { T.pokeBalls, "POKé BALLS" }, nil, 144, 40)
  title(3, { T.battleItems, "BATTLE ITEMS" }, nil, 144, 112)
  local last = self.cur.lastItem
  local ls = last and self:stateOf("last") or 3
  self:drawArt("bbag_last_" .. ls, 0, 152)
  if last then
    self:words(self:text(T.usedLast, "Item used last"), 40, 160 + 6 + LIFT[self:stateOf("last")],
               "subscreen", "row0", 3, 2)
    local at = Gen4BattleBag.LAST_ICON_AT
    self:drawItemIcon(last, at[1], at[2] + LIFT[self:stateOf("last")])
  end
  self:drawArt("bbag_cancel_" .. self:stateOf("cancel"), 216, 152)
end

function Gen4BattleBag:drawPocket()
  local p = self.pocket or 0
  local T = Gen4BattleBag.TEXT
  self:drawArt("bbag_pocket", 0, 0)
  for i = 1, 6 do
    local row = self:itemAt(i)
    local at = Gen4BattleBag.ITEM_BTN_AT[i]
    local s = self:stateOf("item" .. i)
    self:drawArt(row and ("bbag_item_%d_%d"):format(p, s) or "bbag_item_off", at[1], at[2])
    if row then
      local dy = LIFT[s]
      -- the name window (1|17, 1|7|13) 14x3, centred at y 8; the amount
      -- window (8|24, 4|10|16) 4x3, "x" + count at (0, 4)
      local wx, wy = at[1] + 8, at[2]
      self:centred(self:itemName(row), wx, wy + 8 + dy, 112, "subscreen", "row0", 3, 2)
      self:words("x" .. tostring(row.qty), at[1] + 64, at[2] + 24 + 4 + dy, "system", "row4", 1, 2)
      local ic = Gen4BattleBag.ITEM_ICON_AT[i]
      self:drawItemIcon(row.id, ic[1], ic[2] + dy)
    end
  end
  local paged = self.pageCount[p] > 0
  self:drawArt("bbag_prev_" .. (paged and self:stateOf("prev") or 3), 0, 152)
  self:drawArt("bbag_next_" .. (paged and self:stateOf("next") or 3), 40, 152)
  self:drawArt("bbag_cancel_" .. self:stateOf("cancel"), 216, 152)
  -- the pocket's name, window (11,19) 10x5, FONT_SYSTEM
  local names = {
    [0] = { { T.pocketHPPP, "HP/PP" }, { T.pocketRestore, "RESTORE" } },
    { { T.pocketStatus, "STATUS" }, { T.pocketHealers, "HEALERS" } },
    { { T.pocketBalls, "POKé BALLS" } },
    { { T.pocketBattleItems, "BATTLE ITEMS" } },
  }
  local lines = names[p]
  if #lines == 2 then
    self:centred(self:text(lines[1][1], lines[1][2]), 88, 152 + 4, 80, "system", "row4", 1, 2)
    self:centred(self:text(lines[2][1], lines[2][2]), 88, 152 + 20, 80, "system", "row4", 1, 2)
  else
    self:centred(self:text(lines[1][1], lines[1][2]), 88, 152 + 12, 80, "system", "row4", 1, 2)
  end
  -- "page/pages" (BattleBagText_PrintPocketPageNums): the slash centred in
  -- the 32-wide window at (176, 160), the page to its left, the count right
  local slash = "/"
  local sw = self:width(slash, "system")
  local x0 = 176 + math.floor((32 - sw) / 2)
  local cur = tostring((self.cur.pages[p] or 0) + 1)
  self:words(slash, x0, 164, "system", "row4", 1, 2)
  self:words(tostring(self.pageCount[p] + 1), x0 + sw, 164, "system", "row4", 1, 2)
  self:words(cur, x0 - self:width(cur, "system"), 164, "system", "row4", 1, 2)
end

function Gen4BattleBag:drawUse()
  local p = self.pocket or 0
  local row = self:itemAt((self.cur.positions[p] or 0) + 1)
  self:drawArt("bbag_use_" .. p, 0, 0)
  local s = self:stateOf("use")
  self:drawArt(("bbag_usebtn_%d_%d"):format(p, s), 0, 152)
  self:drawArt("bbag_cancel_" .. self:stateOf("cancel"), 216, 152)
  self:centred(self:text(Gen4BattleBag.TEXT.use, "USE"), 80, 160 + 6 + LIFT[s], 48, "subscreen", "row0", 3, 2)
  if row then
    self:words(self:itemName(row), 56, 32, "system", "row4", 1, 2)
    self:words("x" .. tostring(row.qty), 160, 32, "system", "row4", 1, 2)
    local def = row.def or {}
    local desc = def.description or ""
    local Font = require("src.render.Font")
    local y = 72
    for line in (desc:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
      self:words(line, 16 + 4, y, "system", "row4", 1, 2)
      y = y + (Font.lineHeight and Font.lineHeight() or 16)
    end
    local at = Gen4BattleBag.USE_ICON_AT
    self:drawItemIcon(row.id, at[1], at[2])
  end
end

function Gen4BattleBag:drawMessage()
  if not self.message then return end
  local Font = require("src.render.Font")
  Font.drawDialogueBox(1, 18, 29, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local y = 152
  for line in (self.message .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, 16, y)
    y = y + 16
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4BattleBag:drawBottom()
  -- the backdrop is the sub palette's colour 0
  local back = (self.ink.row0 or {})[0]
  if back then
    love.graphics.setColor(back[1] / 255, back[2] / 255, back[3] / 255, 1)
    love.graphics.rectangle("fill", 0, 0, 256, 192)
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self.screen == "pocket" then self:drawPocket()
  elseif self.screen == "use" then self:drawUse()
  else self:drawMenu() end
  self:drawMessage()
  if not self.message then self.cursor:draw(self.battle, self.game, self.t) end
end

function Gen4BattleBag:draw()
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return end
  SecondScreen.draw(self.game, function() self:drawBottom() end)
  if SecondScreen.drawFrame then SecondScreen.drawFrame(self.game) end
end

-- ---------------------------------------------------------------- input --

function Gen4BattleBag:close()
  if self.closed then return end
  self.closed = true
  local stack = self.game.stack
  if stack and stack.top and stack:top() == self then stack:pop()
  elseif stack and not stack.top then stack:pop() end
  if self.onCancel then self.onCancel() end
end

-- BattleBagButtons_PressButton: the button shows PRESSING, then PRESSED, and
-- the queued step runs once it is PRESSED (BattleBagTask_ScreenTransition)
function Gen4BattleBag:pressThen(name, fn)
  Cursor.sound("decide", self.game.data)
  self.press = { name = name, state = 1, ticks = 0, fn = fn }
end

function Gen4BattleBag:say(text)
  self.message = text
end

function Gen4BattleBag:pickMenu(i)
  if i >= 1 and i <= 4 then
    local p = i - 1
    return self:pressThen("pocket" .. p, function()
      self.pocket = p
      self.cur.pocket = p
      self:setScreen("pocket")
    end)
  end
  if i == 5 then
    local last = self.cur.lastItem
    if not last then return end
    return self:pressThen("last", function()
      -- BattleBag_SetLastUsedPocket: the item's page and position
      local p = self.cur.lastPocket or 0
      self.pocket = p
      for n, row in ipairs(self.pockets[p]) do
        if row.id == last then
          self.cur.positions[p] = (n - 1) % Gen4BattleBag.PER_PAGE
          self.cur.pages[p] = math.floor((n - 1) / Gen4BattleBag.PER_PAGE)
          break
        end
      end
      self:setScreen("use")
    end)
  end
  if i == 6 then
    return self:pressThen("cancel", function() self:close() end)
  end
end

function Gen4BattleBag:pickPocket(i)
  local p = self.pocket or 0
  if i >= 1 and i <= 6 then
    if not self:itemAt(i) then return end
    return self:pressThen("item" .. i, function()
      self.cur.positions[p] = i - 1
      self:setScreen("use")
    end)
  end
  if i == 7 or i == 8 then
    if self.pageCount[p] == 0 then return end
    local delta = i == 7 and -1 or 1
    return self:pressThen(i == 7 and "prev" or "next", function()
      local page = (self.cur.pages[p] or 0) + delta
      if page > self.pageCount[p] then page = 0 elseif page < 0 then page = self.pageCount[p] end
      self.cur.pages[p] = page
      self.cur.positions[p] = 0
      self.press = nil
    end)
  end
  if i == 9 then
    return self:pressThen("cancel", function() self:setScreen("menu") end)
  end
end

-- TryUseItem's refusals, then the port's own item flow
function Gen4BattleBag:refusal(row)
  local b = self.battle
  local T = Gen4BattleBag.TEXT
  if not b then return nil end
  if (self.pocket or 0) == Gen4BattleBag.POCKET.BALLS then
    local foes = 0
    if b.foesOf and b.player then
      local ok, list = pcall(b.foesOf, b, b.player or (b.activeOn and b:activeOn(1)))
      foes = ok and #list or 0
    end
    if foes > 1 then return self:text(T.twoPokemon, "It's no good! It's impossible to aim\nwhen there are two Pokémon!") end
    local foe = b.enemy
    if foe and foe.invulnerable then
      return self:text(T.hidden, "It's no good! It's impossible to aim\nat a Pokémon that's not in sight!")
    end
    if foe and (tonumber(foe.substituteHP) or 0) > 0 then
      return self:text(T.substitute, "It's no good! It's impossible to aim\nat a Pokémon that's not in sight!")
    end
  end
  return nil
end

function Gen4BattleBag:use()
  local p = self.pocket or 0
  local row = self:itemAt((self.cur.positions[p] or 0) + 1)
  if not row then return end
  self:pressThen("use", function()
    self.press = nil
    local why = self:refusal(row)
    if why then return self:say((why:gsub("[\v\f]", "\n"))) end
    -- BagCursor_SetBattleCurrentCategory / Bag_SetLastBattleItemUsed
    self.cur.pocket = p
    self.cur.lastItem, self.cur.lastPocket = row.id, p
    local shim = {
      items = {}, index = 1,
      close = function() self:close() end,
      rebuild = function() self:build() end,
    }
    local ok, err = pcall(require("src.ui.BagMenu").useItem, self.game, self.battle, row.id, shim)
    if not ok then
      local okL, Logger = pcall(require, "src.core.Logger")
      if okL and Logger.warn then Logger.warn("gen4 battle bag: %s could not be used: %s", tostring(row.id), tostring(err)) end
    end
    if not self.closed then self:build() end
  end)
end

function Gen4BattleBag:pickUse(i)
  if i == 1 then return self:use() end
  if i == 2 then
    return self:pressThen("cancel", function() self:setScreen("pocket") end)
  end
end

function Gen4BattleBag:pick(i)
  if self.screen == "menu" then return self:pickMenu(i)
  elseif self.screen == "pocket" then return self:pickPocket(i)
  else return self:pickUse(i) end
end

function Gen4BattleBag:update(dt)
  self.t = (self.t or 0) + (dt or 1 / 60)
  local input = self.game.input
  local p = self.press
  if p then
    p.ticks = p.ticks + 1
    if p.state == 1 then p.state = 2
    else
      local fn = p.fn
      self.press = nil
      if fn then fn() end
    end
    return
  end
  if self.message then
    if input and (input:wasPressed("a") or input:wasPressed("b")) then self.message = nil end
    return
  end
  local r = self.cursor:tick(input)
  if r == "back" then
    local back = { menu = 6, pocket = 9, use = 2 }
    return self:pick(back[self.screen])
  elseif r then
    return self:pick(r)
  end
end

function Gen4BattleBag:touchpressed(_, px, py)
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return false end
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x then return false end
  if self.press then return true end
  if self.message then self.message = nil; return true end
  local rects = self.screen == "menu" and Gen4BattleBag.MENU_TOUCH
                or self.screen == "pocket" and Gen4BattleBag.POCKET_TOUCH or Gen4BattleBag.USE_TOUCH
  local i = Cursor.hit(rects, x, y)
  if i then
    self.cursor:hide()
    self:pick(i)
  end
  return true
end

return Gen4BattleBag
