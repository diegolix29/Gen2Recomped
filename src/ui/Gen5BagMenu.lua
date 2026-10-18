-- BLACK AND WHITE'S BAG, over HGSS's (src/ui/HgssBagMenu.lua, itself over
-- Platinum's) for the item logic -- the action list, trash and its question,
-- register, the battle and "pick an item" bags. The art is /a/0/8/8's
-- (src/import/Gen5BagArt.lua); the words are bank 3 (numbered as HGSS's bank
-- 10) and the pocket names bank 55.
--
-- FIVE POCKETS, the items' own `bwPocket`: ITEMS, MEDICINE, TMs & HMs,
-- BERRIES, KEY ITEMS.
--
-- THE TOUCH SCREEN (Bulbapedia's capture, measured): the bag picture on the
-- left -- the bag and a piece for every pocket, the open pocket's piece
-- opened -- and the pocket's items as dark capsules down the right (x 120,
-- from y 13, 24 apart, seven to a page) beside the scrollbar; along the foot
-- << the pocket's name >> and back. THE TOP SCREEN: the chosen item's name,
-- its icon and count in the panel, its description below.
--
-- An item's actions are a column of capsules over the list (A or a tap),
-- CANCEL last; a count to throw away is the quantity window (screen 35) over
-- the list. Each row opens on its grey cap (cells 3-7 of 31): the TM and HM
-- discs in the TM pocket, the plain cap elsewhere (WHICH CAP FOR WHICH POCKET
-- IS BY EYE). The foot holds the registered-item box and the check box (key
-- items), the red (x) and the blue back. One screen: the touch screen; SELECT
-- shows the top.
--
-- MEASURED or ASSUMED, there being no symbols: every position above; the
-- inks; the boy's top palette.

local HgssBagMenu = require("src.ui.HgssBagMenu")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local Gen5BagMenu = setmetatable({}, { __index = HgssBagMenu })
Gen5BagMenu.__index = Gen5BagMenu
Gen5BagMenu.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local POCKETS = 5
local ROW_X, ROW_Y, ROW_PITCH, ROW_H, ROWS = 120, 13, 24, 23, 6
local CAP_W = 18
local CLOSE_RECT = { 168, 191, 188, 219 }
local TEXT_X = 140
local BAG_AT = { 4, 104 }
local PREV_RECT, NEXT_RECT, BACK_RECT = { 168, 191, 0, 24 }, { 168, 191, 120, 144 }, { 168, 191, 224, 255 }
local POCKET_NAME_CENTRE = 72
local LIGHT = { { 1, 1, 1 }, { 0.35, 0.35, 0.35 } }

function Gen5BagMenu.new(game, opts)
  local self = HgssBagMenu.new(game, opts)
  setmetatable(self, Gen5BagMenu)
  self.bw = (game.data or {}).gen5_bag_art or {}
  local text = (game.data or {}).text or {}
  self.pockets = {}
  for p = 0, POCKETS - 1 do
    self.pockets[#self.pockets + 1] = text[("TEXT_G5S_0055_%05d"):format(p)] or ({ "ITEMS", "MEDICINE", "TMs & HMs", "BERRIES", "KEY ITEMS" })[p + 1]
  end
  if self.pocket > POCKETS then self.pocket = 1 end
  self.top = 0
  self.cursor = 1
  self:rebuild()
  return self
end

-- the pocket's items: Platinum's rows, filtered by BW's own pocket number
function Gen5BagMenu:rebuild()
  local game = self.game
  local want = (self.pocket or 1) - 1
  local rows = {}
  local registered = (game.save or {}).registeredItem
  local Bag = require("src.inventory.Bag")
  for _, id in ipairs(Bag.order(game.save) or {}) do
    local def = game.data.items and game.data.items[id]
    if not def and type(id) == "string" then
      local n = tonumber(id:match("(%d+)$"))
      def = n and game.data.items and game.data.items[n]
    end
    if def and tonumber(def.bwPocket) == want and ((game.save.inventory or {})[id] or 0) > 0 then
      local label = def.name or tostring(id)
      -- the TM pocket lists the move (bank 3 #69: "No. NN  Move")
      local machine = def.machine
      if type(machine) == "table" and machine.move then
        local move = (game.data.moves or {})[machine.move]
        local n = tonumber(tostring(def.name or ""):match("(%d+)$"))
        local tmpl = (game.data.text or {})["TEXT_G5S_0003_00069"]
        if move and move.name and n then
          if type(tmpl) == "string" then
            label = tmpl:gsub("{CMD 0201 0}", ("%02d"):format(n)):gsub("{VAR2}", move.name):gsub("{[^}]*}", "")
          else
            label = ("No. %02d %s"):format(n, move.name)
          end
        end
      end
      rows[#rows + 1] = { id = id, label = label, hm = tostring(def.name or ""):match("^HM") ~= nil, qty = game.save.inventory[id],
                          iconId = tonumber(def.id), description = def.description,
                          registered = registered ~= nil and registered == id or nil }
    end
  end
  self.rows = rows
  self.cursor = math.max(1, math.min(self.cursor or 1, #rows))
  self.top = math.max(0, math.min(self.top or 0, math.max(0, #rows - ROWS)))
end

function Gen5BagMenu:items() return self.rows or {} end
function Gen5BagMenu:selected() return (self.rows or {})[self.cursor or 1] end

-- the field-use byte is BW's `fieldUse`, not Platinum's `fieldUseFunc`
function Gen5BagMenu:itemActions(id)
  local items = (self.game.data or {}).items or {}
  local def = items[id] or items[tonumber(tostring(id):match("(%d+)$") or "")] or {}
  local out = {}
  if (tonumber(def.fieldUse) or 0) ~= 0 then out[#out + 1] = "use" end
  if self.pocket ~= 5 then
    out[#out + 1] = "give"
    if self.pocket ~= 3 then out[#out + 1] = "trash" end
  end
  if self.pocket == 5 and (tonumber(def.fieldUse) or 0) ~= 0 then
    local registered = (self.game.save or {}).registeredItem
    out[#out + 1] = (registered ~= nil and registered == id) and "deselect" or "register"
  end
  out[#out + 1] = "cancel"
  return out
end

function Gen5BagMenu:text(index, fallback, ...)
  local Gen4Text = require("src.import.Gen4Text")
  if select("#", ...) > 0 then Gen4Text.buffer(self.game, ...) end
  local ENTRY = { [42] = 43, [45] = 46, [52] = 53, [53] = 54, [54] = 55 }
  local key = ("TEXT_G5S_0003_%05d"):format(ENTRY[index] or index)
  local s = ((self.game.data or {}).text or {})[key]
  if type(s) ~= "string" or not s:find("%S") then return fallback or "" end
  local args = { ... }
  s = s:gsub("{VAR1}", tostring(args[1] or "")):gsub("{VAR2}", tostring(args[2] or "")):gsub("{CMD 0202 1}", tostring(args[2] or "")):gsub("{[^}]*}", "")
  return s
end

function Gen5BagMenu:setPocket(p)
  if self.lockPocket or p == self.pocket then return end
  self.pocket = p
  self.cursor, self.top = 1, 0
  self:rebuild()
  self:sound("SEQ_SE_DP_BAG_030")
end

function Gen5BagMenu:moveCursor(delta)
  local n = #self.rows
  if n == 0 then return end
  local to = math.max(1, math.min(n, self.cursor + delta))
  if to == self.cursor then return end
  self.cursor = to
  if self.cursor <= self.top then self.top = self.cursor - 1 end
  if self.cursor > self.top + ROWS then self.top = self.cursor - ROWS end
  self:sound("SEQ_SE_DP_SELECT")
end

local function inRect(r, p) return p.y >= r[1] and p.y <= r[2] and p.x >= r[3] and p.x <= r[4] end

function Gen5BagMenu:update()
  local input = self.game.input
  local tap = self.tapAt
  self.tapAt = nil
  if self.message then
    if tap or (input and (input:wasPressed("a") or input:wasPressed("b"))) then self.message = nil end
    return
  end
  if self.trash and self.trash.stage == "count" then
    if input then
      if input:wasPressed("a") then return self:confirmTrash() end
      if input:wasPressed("b") then self.trash = nil; return end
      self:trashCount(input)
    end
    return
  end
  if self.menu then return self:menuInput(input, tap) end
  if tap then
    if inRect(BACK_RECT, tap) or inRect(CLOSE_RECT, tap) then self:sound("SEQ_SE_DP_SELECT"); return self:close() end
    if inRect(PREV_RECT, tap) then return self:setPocket((self.pocket - 2) % POCKETS + 1) end
    if inRect(NEXT_RECT, tap) then return self:setPocket(self.pocket % POCKETS + 1) end
    for k = 1, ROWS do
      local y = ROW_Y + (k - 1) * ROW_PITCH
      if tap.x >= ROW_X and tap.x < 240 and tap.y >= y and tap.y < y + ROW_H and self.rows[self.top + k] then
        self.cursor = self.top + k
        return self:choose()
      end
    end
    return
  end
  if not input then return end
  if input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("left") then self:setPocket((self.pocket - 2) % POCKETS + 1)
  elseif input:wasPressed("right") then self:setPocket(self.pocket % POCKETS + 1)
  elseif input:wasPressed("a") then
    if self:selected() then return self:choose() end
  elseif input:wasPressed("select") then
    self.showTop = not self.showTop
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:sound("SEQ_SE_DP_SELECT")
    return self:close()
  end
end

-- the action list as capsules over the list; tapping one runs it
function Gen5BagMenu:menuInput(input, tap)
  local m = self.menu
  if tap then
    for i = 1, #m.rows do
      local y = ROW_Y + (i - 1) * ROW_PITCH
      if tap.x >= ROW_X and tap.y >= y and tap.y < y + ROW_H then m.index = i; return self:runMenuRow() end
    end
    if inRect(BACK_RECT, tap) then
      if m.kind == "yesno" then return self:resolveTrash(false) end
      self.menu = nil
    end
    return
  end
  return HgssBagMenu.menuInput(self, input, nil)
end

-- ---------------------------------------------------------------- draw --

function Gen5BagMenu:bwImg(key)
  local rec = self.bw[key]
  if type(rec) ~= "table" then return nil end
  return self:imgAt(rec.path), rec
end

function Gen5BagMenu:bwSprite(key, x, y, sx)
  local img, rec = self:bwImg(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0), 0, sx or 1, 1)
  return true
end

-- a line squeezed (never stretched) into `width`
function Gen5BagMenu:fitted(text, x, y, width)
  local w = Font.width(text)
  if w <= width then return Font.draw(text, x, y) end
  local g = love.graphics
  g.push(); g.translate(x, y); g.scale(width / w, 1)
  Font.draw(text, 0, 0)
  g.pop()
end

function Gen5BagMenu:who() return self:female() and "f" or "m" end

-- WHICH PIECE IS WHICH POCKET, from Bulbapedia's per-pocket captures of the
-- cartridge: the bag itself is ITEMS, the green case MEDICINE, the disc case
-- TMs & HMs, the pouch BERRIES, the keyed box KEY ITEMS. At rest a piece wears
-- the bag's own colour (cells 0-4); the open pocket's piece is opened (10-14).
local PIECE = { [1] = 4, [2] = 2, [3] = 3, [4] = 1, [5] = 0 }

function Gen5BagMenu:drawBagPicture()
  local who = self:who()
  local open = PIECE[self.pocket]
  for piece = 0, 4 do
    local set = (piece == open) and 2 or 0
    self:bwSprite(("bag_%s_%d"):format(who, piece + set * 5), BAG_AT[1], BAG_AT[2])
  end
end

function Gen5BagMenu:capFor(row)
  if self.pocket == 3 and row and row.label then
    return row.hm and "tm_7" or "tm_6"
  end
  return "tm_3"
end

function Gen5BagMenu:drawCapsule(y, selected, cap)
  local g = love.graphics
  local img = self:bwImg("row_0")
  if img then
    -- the capsule (112 wide) runs from the cap to x 240
    g.setColor(1, 1, 1, 1)
    g.draw(img, ROW_X + CAP_W - 2, y + floor((ROW_H - img:getHeight()) / 2), 0, (120 - CAP_W + 2) / img:getWidth(), 1)
    local capImg = self:bwImg(cap or "tm_3")
    if capImg then g.draw(capImg, ROW_X - 3, y + floor((ROW_H - capImg:getHeight()) / 2)) end
  else
    g.setColor(0.18, 0.18, 0.18, 1)
    g.rectangle("fill", ROW_X, y, 120, ROW_H, 6, 6)
  end
  if selected then
    g.setColor(0.72, 0.72, 0.72, 1)
    g.rectangle("fill", ROW_X + 18, y + 3, 98, ROW_H - 6, 4, 4)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen5BagMenu:drawTouch()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local back = self:bwImg("touch_" .. self:who())
  if back then g.draw(back, 0, 0) else g.setColor(0.6, 0.1, 0.2, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  self:drawBagPicture()
  Font.pushStyle({ text = LIGHT[1], shadow = LIGHT[2] })
  if self.trash and self.trash.stage == "count" then
    local q = self:bwImg("quantity")
    local qx, qy = ROW_X - 8, 60
    g.setColor(1, 1, 1, 1)
    if q then g.draw(q, qx, qy) end
    Font.draw(("x%03d"):format(self.trash.n), qx + 68 - floor(Font.width(("x%03d"):format(self.trash.n)) / 2), qy + 16)
  elseif self.menu then
    local m = self.menu
    for i, action in ipairs(m.rows) do
      local y = ROW_Y + (i - 1) * ROW_PITCH
      self:drawCapsule(y, i == m.index)
      local label = m.kind == "yesno" and (action == "yes" and "YES" or "NO") or self:actionLabel(action)
      Font.draw(label, TEXT_X, y + 4)
    end
  else
    for k = 1, ROWS do
      local row = self.rows[self.top + k]
      if row then
        local y = ROW_Y + (k - 1) * ROW_PITCH
        self:drawCapsule(y, self.top + k == self.cursor, self:capFor(row))
        self:fitted(tostring(row.label or ""), TEXT_X, y + 4, 236 - TEXT_X)
      end
    end
    -- the scrollbar's thumb
    local n = #self.rows
    if n > ROWS then
      local span = 150 - 18
      local t = 18 + floor(span * self.top / (n - ROWS))
      g.setColor(0.88, 0.88, 0.88, 1)
      g.rectangle("fill", 245, t, 6, 14)
      g.setColor(1, 1, 1, 1)
    end
  end
  -- the foot: << the pocket >> and back (the shared touch buttons 18, 19, 1)
  -- over the black bar every BW touch screen ends in -- drawn here as the
  -- capture's gradient, its art not yet found (STAND-IN)
  Font.popStyle()
  for y = 168, 191 do
    local v = math.max(0, 96 - (y - 168) * 8) / 255
    g.setColor(v, v, v, 1)
    g.rectangle("fill", 0, y, W, 1)
  end
  g.setColor(1, 1, 1, 1)
  if not self:bwSprite("button_18", -4, 164) then Font.draw("<<", 6, 172) end
  if not self:bwSprite("button_19", 116, 164) then Font.draw(">>", 126, 172) end
  if self.pocket == 5 then
    self:bwSprite("register_0", 142, 172)
    self:bwSprite("tm_1", 169, 180)
  end
  self:bwSprite("button_0", 188, 164)
  self:bwSprite("button_1", 220, 164)
  Font.pushStyle({ text = LIGHT[1], shadow = LIGHT[2] })
  local name = tostring(self.pockets[self.pocket] or "")
  Font.draw(name, POCKET_NAME_CENTRE - floor(Font.width(name) / 2), 172)
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

function Gen5BagMenu:drawTop()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local under = self:bwImg("top_back_" .. self:who())
  if under then g.draw(under, 0, 0) end
  local back = self:bwImg("top_" .. self:who())
  if back then g.draw(back, 0, 0) else g.setColor(0.5, 0.1, 0.2, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  local row = self:selected()
  Font.pushStyle({ text = LIGHT[1], shadow = LIGHT[2] })
  local body = self.message
  if self.trash and self.trash.stage == "count" then
    body = self:text(52, ("Throw away how many %s?"):format(self:trashName()), self:trashName())
  elseif self.trash and self.trash.stage == "confirm" then
    body = self:text(54, ("Is it OK to throw away %s?"):format(self:trashName()), self:trashName(), tostring(self.trash.n))
  end
  if row then
    local name = tostring(row.label or "")
    Font.draw(name, 127 - floor(Font.width(name) / 2), 44)
    local icon = row.iconId and self:img(("items/icon_%03d"):format(row.iconId))
    g.setColor(1, 1, 1, 1)
    if icon then g.draw(icon, 116 - icon:getWidth() / 2, 76 - icon:getHeight() / 2) end
    if row.qty then Font.draw(("x%d"):format(row.qty), 160, 68) end
    body = body or row.description
  end
  if body then
    local y = 101
    for line in (tostring(body):gsub("[\v\f]", "\n") .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 16, y)
      y = y + 16
      if y > 160 then break end
    end
  end
  Font.popStyle()
end

function Gen5BagMenu:draw()
  if not self:bottomOnSecond() and self.showTop then
    self:drawTop()
  elseif self:bottomOnSecond() then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawTouch() end)
  else
    self:drawTouch()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen5BagMenu
