-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/ui/Gen5BattleBag.lua
--
-- BLACK AND WHITE'S BATTLE BAG, on the touch screen while the battle stays on
-- the top one (BAG in BW's command screen). Before this the FIELD bag opened
-- in a battle. Three screens on the cartridge's own art (`gen5_battle_bag`,
-- src/import/Gen5BattleBagArt.lua, /a/0/9/9) and words (system bank 17):
--
--   MENU     the four battle pockets -- HP/PP RESTORE (#0 / #1), POKe BALLS
--            (#7), STATUS RESTORE (#2 / #3), BATTLE ITEMS (#6) -- the LAST
--            USED ITEM bar (#8) and the back button
--   POCKET   six items a page (name, icon, "xN" #10), the page arrows, the
--            pocket's name (#22..#27) and "page/pages" (#28) in the box
--   USE      one item: icon, name, count, description; USE (#31) and back
--
-- Pockets are filled the way Platinum's battle bag does it (BattleBag_Init:
-- every carried item filed under each pocket its battle-pocket mask names --
-- bit 0 balls, 1 battle items, 2 HP / 4 PP restore, 3 status restore),
-- the mask being BW's own (src/inventory/Gen5Items.lua). USE goes through
-- src/battle/Gen5BagUse.lua, the same flows the bag had: balls (and their
-- refusals, bank 17 #44 / #45 / #47), medicine on the party list, battle
-- items, Poke Dolls, Embargo. A refusal is printed over the bag and the bag
-- stays open; a use that spends the turn closes it.
--
-- Mouse, touch (touchpressed, in the touch screen's pixels) and the keys
-- (the shared sub-menu cursor: d-pad, A, B) all work. The cursor's look is
-- the port's (a frame on the button): BW's own cursor OBJ (/a/0/1/1 119-121)
-- is not imported.

local Strings = require("src.core.Strings")
local Cursor = require("src.ui.Gen4SubMenuCursor")

local Bag = {}
Bag.__index = Bag
Bag.isOpaque = false

Bag.BANK = 17
Bag.TEXT = { hpPP = 0, restore = 1, status = 2, statusRestore = 3, battleItems = 6,
             pokeBalls = 7, lastUsed = 8, count = 10, pocketHP = 22, pocketRestore = 23,
             pocketStatus = 24, pocketStatusRestore = 25, pocketBalls = 26,
             pocketBattle = 27, slash = 28, use = 31 }

-- the pockets, in the menu's order (1 top left, 2 top right, 3 bottom
-- left, 4 bottom right)
Bag.POCKETS = { "hp", "balls", "status", "battle" }
-- mask bit -> pocket (Platinum's sBattlePocketIndexes, by name)
Bag.MASK_POCKET = { [0] = "balls", "battle", "hp", "status", "hp" }
Bag.PRESS = { hp = "press_pocket_hp", balls = "press_pocket_balls",
              status = "press_pocket_status", battle = "press_pocket_battle" }
Bag.PER_PAGE = 6
Bag.PRESS_FRAMES = 6

-- the keypad's walk over each screen's buttons (Gen4SubMenuCursor's shape)
local function pos(r, links)
  links[1], links[2], links[3], links[4] = r[1], r[2], r[1] + r[3], r[2] + r[4]
  return links
end

function Bag.rects(data)
  local art = data and data.gen5_battle_bag
  return (art and art.rects) or require("src.import.Gen5BattleBagArt").RECTS
end

local function cursors(R)
  local m, p, u = R.menu, R.pocket, R.use
  return {
    menu = {
      pos(m[1], { up = 1, down = 3, left = 1, right = 2 }),
      pos(m[2], { up = 2, down = 4, left = 1, right = 2 }),
      pos(m[3], { up = 1, down = 5, left = 3, right = 4 }),
      pos(m[4], { up = 2, down = 6, left = 3, right = 4 }),
      pos(m[5], { up = 3, down = 5, left = 5, right = 6 }),
      pos(m[6], { up = 4, down = 6, left = 5, right = 6 }),
    },
    pocket = {
      pos(p[1], { up = 1, down = 3, left = 1, right = 2 }),
      pos(p[2], { up = 2, down = 4, left = 1, right = 2 }),
      pos(p[3], { up = 1, down = 5, left = 3, right = 4 }),
      pos(p[4], { up = 2, down = 6, left = 3, right = 4 }),
      pos(p[5], { up = 3, down = 7, left = 5, right = 6 }),
      pos(p[6], { up = 4, down = 9, left = 5, right = 6 }),
      pos(p[7], { up = 5, down = 7, left = 7, right = 8 }),
      pos(p[8], { up = 5, down = 8, left = 7, right = 9 }),
      pos(p[9], { up = 6, down = 9, left = 8, right = 9 }),
    },
    use = {
      pos(u[1], { up = 1, down = 1, left = 1, right = 2 }),
      pos(u[2], { up = 2, down = 2, left = 1, right = 2 }),
    },
  }
end

function Bag.available(data)
  local art = data and data.gen5_battle_bag
  local im = art and art.images
  return im and im.base and im.menu and im.pocket and im.use and true or false
end

-- the bag's memory (pocket, page and position per pocket, the last item
-- used) lives on the game, so it outlives the battle as the cartridge's does
local function memory(game)
  game.gen5BattleBagCursor = game.gen5BattleBagCursor or {
    pocket = "hp", pages = {}, positions = {}, lastItem = nil, lastPocket = "hp",
  }
  return game.gen5BattleBagCursor
end
Bag.memory = memory

function Bag.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Bag)
  self.game = game
  self.battle = opts.battle
  self.onCancel = opts.onCancel
  self.t = 0
  self.images = {}
  self.art = (game.data or {}).gen5_battle_bag or {}
  self.R = Bag.rects(game.data)
  self.CUR = cursors(self.R)
  self.mem = memory(game)
  pcall(require("src.inventory.Gen5Items").ensure, game.data)
  self:build()
  self.cursor = Cursor.new(self.battle or game, self.CUR.menu, 1)
  self:setScreen("menu")
  return self
end

function Bag:uiSize()
  if self.battle and self.battle.uiSize then return self.battle:uiSize() end
  return 256, 192
end

-- every carried item, filed by its battle-pocket mask, in bag order
function Bag:build()
  local game = self.game
  local items = game.data.items or {}
  local Items = require("src.inventory.Gen5Items")
  local inv = game.save.inventory or {}
  local order = require("src.inventory.Bag").order(game.save) or {}
  self.pockets = { hp = {}, balls = {}, status = {}, battle = {} }
  local seen = { hp = {}, balls = {}, status = {}, battle = {} }
  for _, key in ipairs(order) do
    local def = items[key]
    local qty = tonumber(inv[key]) or 0
    local mask = def and tonumber(Items.mask(def)) or 0
    if qty > 0 and mask > 0 then
      local num = tonumber(def.id) or key
      for bit = 0, 4 do
        if math.floor(mask / 2 ^ bit) % 2 == 1 then
          local p = Bag.MASK_POCKET[bit]
          if not seen[p][num] then
            seen[p][num] = true
            local list = self.pockets[p]
            list[#list + 1] = { id = key, qty = qty, def = def }
          end
        end
      end
    end
  end
  self.pageCount = {}
  for _, p in ipairs(Bag.POCKETS) do
    local n = #self.pockets[p]
    self.pageCount[p] = n == 0 and 0 or math.floor((n - 1) / Bag.PER_PAGE)
    if (self.mem.pages[p] or 0) > self.pageCount[p] then self.mem.pages[p] = self.pageCount[p] end
  end
  -- the last item used, while there is still one of it
  local last = self.mem.lastItem
  if last and (tonumber(inv[last]) or 0) <= 0 then self.mem.lastItem = nil end
end

function Bag:itemAt(i, pocket)
  pocket = pocket or self.pocket or "hp"
  local row = self.pockets[pocket][(self.mem.pages[pocket] or 0) * Bag.PER_PAGE + i]
  if row and row.qty > 0 then return row end
  return nil
end

function Bag:enabledFor(screen)
  if screen == "menu" then
    return function(i) return i ~= 5 or self.mem.lastItem ~= nil end
  elseif screen == "pocket" then
    return function(i)
      if i <= 6 then return self:itemAt(i) ~= nil end
      if i == 7 or i == 8 then return (self.pageCount[self.pocket] or 0) > 0 end
      return true
    end
  end
  return nil
end

function Bag:setScreen(name)
  self.screen = name
  self.press = nil
  local start = 1
  if name == "menu" then
    for i, p in ipairs(Bag.POCKETS) do if p == self.mem.pocket then start = i end end
  elseif name == "pocket" then
    start = (self.mem.positions[self.pocket] or 0) + 1
    if not self:itemAt(start) then start = self:itemAt(1) and 1 or 9 end
  end
  self.cursor:set(self.CUR[name], start, self:enabledFor(name))
end

-- ---------------------------------------------------------------- words --

function Bag:text(id, fallback)
  local data = self.game and self.game.data
  local s = data and data.text and data.text[("TEXT_G5S_%04d_%05d"):format(Bag.BANK, id)]
  if type(s) ~= "string" or s == "" then return Strings(fallback or "") end
  return s
end

function Bag:image(key)
  local rec = (self.art.images or {})[key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
    if self.images[path] then self.images[path]:setFilter("nearest", "nearest") end
  end
  return self.images[path] or nil
end

function Bag:drawArt(key, x, y)
  local img = self:image(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, math.floor(x), math.floor(y))
  return true
end

-- white on the dark buttons, with the grey shadow BW's battle words carry
local INK = { text = { 0.97, 0.97, 0.97, 1 }, shadow = { 0.25, 0.25, 0.3, 1 } }
local DIM = { text = { 0.55, 0.55, 0.58, 1 }, shadow = { 0.2, 0.2, 0.22, 1 } }

function Bag:words(text, x, y, ink)
  local Font = require("src.render.Font")
  local faced = Font.pushFace and Font.pushFace("system")
  if Font.pushStyle then Font.pushStyle(ink or INK) end
  love.graphics.setColor(1, 1, 1, 1)
  Font.draw(text, math.floor(x), math.floor(y))
  if Font.popStyle then Font.popStyle() end
  if faced then Font.popFace() end
end

function Bag:width(text)
  local Font = require("src.render.Font")
  local faced = Font.pushFace and Font.pushFace("system")
  local w = Font.width and Font.width(text) or #text * 8
  if faced then Font.popFace() end
  return w
end

function Bag:centred(text, x, y, w, ink)
  self:words(text, x + math.floor((w - self:width(text)) / 2), y, ink)
end

function Bag:countText(qty)
  local s = self:text(Bag.TEXT.count, "x{CMD 0202 0}")
  return (s:gsub("{CMD[^}]*}", tostring(qty)))
end

function Bag:itemName(row)
  local def = row and (row.def or (self.game.data.items or {})[row.id])
  return def and def.name or tostring(row and row.id or "")
end

function Bag:drawItemIcon(id, cx, cy)
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

function Bag:pressed(name)
  return self.press ~= nil and self.press.name == name
end

-- a pressed button: the screen's backdrop over the button, its pressed
-- patch at the button's place (the patches are the button squashed down)
-- (each patch goes at its button's tile origin; the long bar's starts a row
-- of tiles above the bar)
function Bag:drawPressed(rect, patch)
  local base = self:image("base")
  local g = love.graphics
  if base then
    local q = g.newQuad(rect[1], rect[2], rect[3], rect[4], base:getDimensions())
    g.setColor(1, 1, 1, 1)
    g.draw(base, q, rect[1], rect[2])
  end
  local ox, oy = rect[1] - rect[1] % 8, rect[2] - rect[2] % 8
  if patch == "press_bar" then oy = oy - 8 end
  self:drawArt(patch, ox, oy)
end

-- how far a pressed button's words drop with it
local function drop(self, name) return self:pressed(name) and 2 or 0 end

function Bag:drawMenu()
  local R, T = self.R.menu, Bag.TEXT
  self:drawArt("menu", 0, 0)
  local labels = {
    hp = { { T.hpPP, "HP/PP" }, { T.restore, "RESTORE" } },
    balls = { { T.pokeBalls, "POKé BALLS" } },
    status = { { T.status, "STATUS" }, { T.statusRestore, "RESTORE" } },
    battle = { { T.battleItems, "BATTLE ITEMS" } },
  }
  for i, p in ipairs(Bag.POCKETS) do
    local r = R[i]
    if self:pressed(p) then self:drawPressed(r, Bag.PRESS[p]) end
    local lines = labels[p]
    local dy = drop(self, p)
    if #lines == 2 then
      self:centred(self:text(lines[1][1], lines[1][2]), r[1], r[2] + 22 + dy, r[3])
      self:centred(self:text(lines[2][1], lines[2][2]), r[1], r[2] + 36 + dy, r[3])
    else
      self:centred(self:text(lines[1][1], lines[1][2]), r[1], r[2] + 30 + dy, r[3])
    end
  end
  local bar = R[5]
  if self:pressed("last") then self:drawPressed(bar, "press_bar") end
  local last = self.mem.lastItem
  if last then
    local dy = drop(self, "last")
    self:drawItemIcon(last, bar[1] + 22, bar[2] + 15 + dy)
    local def = (self.game.data.items or {})[last]
    self:words(def and def.name or tostring(last), bar[1] + 44, bar[2] + 8 + dy)
  else
    self:centred(self:text(T.lastUsed, "LAST USED ITEM"), bar[1], bar[2] + 8, bar[3], DIM)
  end
  if self:pressed("back") then self:drawPressed(R[6], "press_back") end
end

function Bag:pocketNameLines(p)
  local T = Bag.TEXT
  local names = {
    hp = { { T.pocketHP, "HP/PP" }, { T.pocketRestore, "RESTORE" } },
    status = { { T.pocketStatus, "STATUS" }, { T.pocketStatusRestore, "RESTORE" } },
    balls = { { T.pocketBalls, "POKé BALLS" } },
    battle = { { T.pocketBattle, "BATTLE ITEMS" } },
  }
  local out = {}
  for _, l in ipairs(names[p] or {}) do out[#out + 1] = self:text(l[1], l[2]) end
  return out
end

function Bag:drawPocket()
  local p = self.pocket or "hp"
  local R = self.R.pocket
  self:drawArt("pocket", 0, 0)
  for i = 1, 6 do
    local r = R[i]
    local row = self:itemAt(i)
    if self:pressed("item" .. i) then self:drawPressed(r, "press_item") end
    if row then
      local dy = drop(self, "item" .. i)
      self:drawItemIcon(row.id, r[1] + 20, r[2] + 24 + dy)
      self:words(self:itemName(row), r[1] + 38, r[2] + 7 + dy)
      local c = self:countText(row.qty)
      self:words(c, r[1] + r[3] - 12 - self:width(c), r[2] + 25 + dy)
    end
  end
  local paged = (self.pageCount[p] or 0) > 0
  if self:pressed("prev") then self:drawPressed(R[7], "press_prev") end
  if self:pressed("next") then self:drawPressed(R[8], "press_next") end
  if not paged then
    -- one page: the arrows are there but do nothing (drawn dimmed)
    love.graphics.setColor(0, 0, 0, 0.45)
    for _, k in ipairs({ 7, 8 }) do love.graphics.rectangle("fill", R[k][1], R[k][2], R[k][3], R[k][4]) end
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self:pressed("back") then self:drawPressed(R[9], "press_back") end
  -- the box: the pocket's name over "page/pages"
  local box = self.R.pageBox
  local lines = self:pocketNameLines(p)
  self:centred(table.concat(lines, " "), box[1], box[2] + 4, box[3])
  local slash = self:text(Bag.TEXT.slash, "/")
  local page = ("%d%s%d"):format((self.mem.pages[p] or 0) + 1, slash, (self.pageCount[p] or 0) + 1)
  self:centred(page, box[1], box[2] + 19, box[3])
end

function Bag:drawUse()
  local p = self.pocket or "hp"
  local R = self.R.use
  local row = self:itemAt((self.mem.positions[p] or 0) + 1)
  self:drawArt("use", 0, 0)
  if self:pressed("use") then self:drawPressed(R[1], "press_bar") end
  self:centred(self:text(Bag.TEXT.use, "USE"), R[1][1], R[1][2] + 8 + drop(self, "use"), R[1][3])
  if self:pressed("back") then self:drawPressed(R[2], "press_back") end
  if not row then return end
  local panel = self.R.panel
  self:drawItemIcon(row.id, panel[1] + 22, panel[2] + 18)
  self:words(self:itemName(row), panel[1] + 42, panel[2] + 10)
  local c = self:countText(row.qty)
  self:words(c, panel[1] + panel[3] - 14 - self:width(c), panel[2] + 10)
  local Font = require("src.render.Font")
  local desc = ((row.def or {}).description or ""):gsub("\r", "")
  local y = panel[2] + 34
  for line in (desc .. "\n"):gmatch("(.-)\n") do
    if y > panel[2] + panel[4] - 14 then break end
    self:words(line, panel[1] + 10, y)
    y = y + ((Font.lineHeight and Font.lineHeight()) or 16)
  end
end

-- a refusal, in a window over the bottom of the screen
function Bag:drawMessage()
  if not self.message then return end
  local Font = require("src.render.Font")
  if Font.drawDialogueBox then Font.drawDialogueBox(1, 18, 29, 6)
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 8, 144, 240, 44)
  end
  love.graphics.setColor(0, 0, 0, 1)
  local y = 152
  for line in (self.message .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, 16, y)
    y = y + 16
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Bag:drawCursor()
  if self.message or not self.cursor:visible() then return end
  local c = self.cursor.positions[self.cursor.index]
  if not c then return end
  local g = love.graphics
  local x1, y1, x2, y2 = c[1], c[2], c[3], c[4]
  local blink = 0.6 + 0.4 * math.abs(math.sin((self.t or 0) * 4))
  g.setColor(1, 0.45, 0.6, blink)
  g.setLineWidth(2)
  local L = 10
  for _, k in ipairs({ { x1, y1, 1, 1 }, { x2, y1, -1, 1 }, { x1, y2, 1, -1 }, { x2, y2, -1, -1 } }) do
    g.line(k[1], k[2] + k[4] * L, k[1], k[2], k[1] + k[3] * L, k[2])
  end
  g.setLineWidth(1)
  g.setColor(1, 1, 1, 1)
end

function Bag:drawBottom()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  self:drawArt("base", 0, 0)
  if self.screen == "pocket" then self:drawPocket()
  elseif self.screen == "use" then self:drawUse()
  else self:drawMenu() end
  self:drawMessage()
  self:drawCursor()
end

function Bag:draw()
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return self:drawBottom() end
  SecondScreen.draw(self.game, function() self:drawBottom() end)
  if SecondScreen.drawFrame then SecondScreen.drawFrame(self.game) end
end

-- ---------------------------------------------------------------- input --

function Bag:close()
  if self.closed then return end
  self.closed = true
  local stack = self.game.stack
  if stack and stack.top and stack:top() == self then
    stack:pop()
  elseif stack and stack.states then
    -- a screen pushed over the bag (the party list) closed it from above
    for i = #stack.states, 1, -1 do
      if stack.states[i] == self then table.remove(stack.states, i) break end
    end
  end
  if self.onCancel then self.onCancel() end
end

function Bag:pressThen(name, fn)
  Cursor.sound("decide", self.game.data)
  self.press = { name = name, ticks = 0, fn = fn }
end

function Bag:say(text)
  self.message = (tostring(text):gsub("[\v\f]", "\n"))
end

function Bag:pickMenu(i)
  if i >= 1 and i <= 4 then
    local p = Bag.POCKETS[i]
    return self:pressThen(p, function()
      self.pocket = p
      self.mem.pocket = p
      self:setScreen("pocket")
    end)
  end
  if i == 5 then
    local last = self.mem.lastItem
    if not last then return end
    return self:pressThen("last", function()
      local p = self.mem.lastPocket or "hp"
      self.pocket = p
      for n, row in ipairs(self.pockets[p] or {}) do
        if row.id == last then
          self.mem.positions[p] = (n - 1) % Bag.PER_PAGE
          self.mem.pages[p] = math.floor((n - 1) / Bag.PER_PAGE)
          break
        end
      end
      if not self:itemAt((self.mem.positions[p] or 0) + 1) then return self:setScreen("menu") end
      self:setScreen("use")
    end)
  end
  if i == 6 then
    return self:pressThen("back", function() self:close() end)
  end
end

function Bag:pickPocket(i)
  local p = self.pocket or "hp"
  if i >= 1 and i <= 6 then
    if not self:itemAt(i) then return end
    return self:pressThen("item" .. i, function()
      self.mem.positions[p] = i - 1
      self:setScreen("use")
    end)
  end
  if i == 7 or i == 8 then
    if (self.pageCount[p] or 0) == 0 then return end
    local delta = i == 7 and -1 or 1
    return self:pressThen(i == 7 and "prev" or "next", function()
      local page = (self.mem.pages[p] or 0) + delta
      if page > self.pageCount[p] then page = 0 elseif page < 0 then page = self.pageCount[p] end
      self.mem.pages[p] = page
      self.mem.positions[p] = 0
      self.cursor:set(self.CUR.pocket, i, self:enabledFor("pocket"))
    end)
  end
  if i == 9 then
    return self:pressThen("back", function() self:setScreen("menu") end)
  end
end

function Bag:use()
  local p = self.pocket or "hp"
  local row = self:itemAt((self.mem.positions[p] or 0) + 1)
  if not row then return end
  self:pressThen("use", function()
    self.mem.pocket = p
    self.mem.lastItem, self.mem.lastPocket = row.id, p
    local bag = self
    local list = {
      items = {}, index = 1,
      close = function() bag:close() end,
      rebuild = function() bag:build() end,
    }
    local function showMessages(_, msgs)
      if bag.closed then return end
      bag:say(table.concat(msgs or {}, "\n"))
    end
    local ok, err = pcall(require("src.battle.Gen5BagUse").use, self.game, self.battle, row.id, list, showMessages)
    if not ok then
      local okL, Logger = pcall(require, "src.core.Logger")
      if okL and Logger.warn then Logger.warn("bw battle bag: %s could not be used: %s", tostring(row.id), tostring(err)) end
    end
    if not self.closed then self:build() end
  end)
end

function Bag:pickUse(i)
  if i == 1 then return self:use() end
  if i == 2 then return self:pressThen("back", function() self:setScreen("pocket") end) end
end

function Bag:pick(i)
  if self.screen == "menu" then return self:pickMenu(i)
  elseif self.screen == "pocket" then return self:pickPocket(i)
  else return self:pickUse(i) end
end

Bag.BACK = { menu = 6, pocket = 9, use = 2 }

function Bag:update(dt)
  self.t = (self.t or 0) + (dt or 1 / 60)
  local input = self.game.input
  local p = self.press
  if p then
    p.ticks = p.ticks + 1
    if p.ticks >= Bag.PRESS_FRAMES then
      self.press = nil
      if p.fn then p.fn() end
    end
    return
  end
  if self.message then
    if input and (input:wasPressed("a") or input:wasPressed("b")) then self.message = nil end
    return
  end
  local r = self.cursor:tick(input)
  if r == "back" then return self:pick(Bag.BACK[self.screen])
  elseif r then return self:pick(r) end
end

-- the touch screen's own pixels, or nil when the press is off it
function Bag:toLocal(px, py)
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if ok then
    local x, y = SecondScreen.toLocal(self.game, px, py)
    return x, y
  end
  return px, py
end

local function hit(rects, x, y)
  for i, r in ipairs(rects) do
    if x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then return i end
  end
  return nil
end

function Bag:touchpressed(_, px, py)
  local x, y = self:toLocal(px, py)
  if not x then return false end
  if self.press then return true end
  if self.message then self.message = nil; return true end
  local i = hit(self.R[self.screen] or {}, x, y)
  if i then
    self.cursor:hide()
    self:pick(i)
  end
  return true
end

return Bag
