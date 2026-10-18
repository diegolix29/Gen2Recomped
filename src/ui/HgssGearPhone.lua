-- THE POKeGEAR'S PHONE (overlay 101: pokegear_phone.c and
-- overlay_101_021EFD20 / 021F017C / 021F0880 / 021F0F48), the PHONE app of
-- src/ui/HgssPokegear.lua.
--
-- READ FROM CODE:
--   * the list: six rows of 24 px from y 8 (the window at tile (1, 2) on
--     MAIN_3, scrolled), each a name plate x 16-98 and a class plate x 98-224
--     on a 24-px band, the two colour sets alternating row by row and
--     swapping as the list scrolls (PhoneContactListUI_DrawNameSlotBG); the
--     name at (24, +2) in font 4, the class at (102, +2) in font 0; colours
--     from MAIN palette row 2 (textColors: band 11 / 14, name plate 9 / 12,
--     class plate 10 / 13, name 1 on 2 (3 on 4 selected), class 5 on 6 (7 on
--     8 selected))
--   * the class: nothing for Mom (class 200), bank 271 38 + (class - 201) for
--     the phone-only classes, else the trainer class's name (bank 730)
--     (PhoneContact_GetClass)
--   * the cursor's corners (OBJ seqs 2-5) at x 16 / 224, y 24 pos + 8 / + 30;
--     the up arrow (seq 0) at (124, 8) while the list can go up, the down
--     arrow (seq 1) at (124, 156) while it can go down
--   * keys (PhoneContactListUI_HandleKeyInput): UP / DOWN move the cursor,
--     scrolling one row at the ends (no wrap), LEFT / RIGHT scroll a page,
--     A opens the contact's menu, B puts the cursor on the bar; a row scrolls
--     8 px a frame over 3 frames, a page up to six rows
--   * touch (ov101_021F8634): rows y 8 + 24 i (x 8-224) open the menu; the
--     arrows' strip x 224-248, y 8-80 / 80-152 page up / down
--   * the contact's menu, Call / Sort / Quit (bank 271 0-2) at tile (13, 9)
--     16 wide; Sort's Title / Alphabet / Location / Move / Quit (271 3-7) at
--     (13, 3); the tooltip strip (phone screen rows 24-27) at row 20 with
--     bank 271 22 "What will you do?" (Sort: 23-27 by the cursor; Move: 21)
--   * SORT: by the phonebook's sortParam[0 / 1 / 2] (PokegearPhone_SortList,
--     a stable-ish exchange sort); MOVE: the move arrows (seq 6, seq 7 on the
--     cursor's row) at (12, 16 + 24 i); A or a tap drops the picked contact
--     there (PokegearPhone_ContactList_InsertNode), B puts it back
--   * Call: src/ui/HgssPhoneCall.lua with the call outgoing (the touch screen
--     dimmed under it, PokegearPhone_SetTouchscreenDimState)
--
-- The phonebook ORDER is kept in save.hgssPokegear.order (the cartridge
-- keeps its phonebook in registration order; numbers the port registered
-- before this was kept go in by id).

local Font = require("src.render.Font")
local TouchList = require("src.ui.HgssTouchList")

local Phone = {}
Phone.__index = Phone

local floor = math.floor
local ROWS = 6
local ROW_H = 24
local TOP = 8

function Phone.new(gear)
  local self = setmetatable({ gear = gear, game = gear.game, first = 0, cursor = 0, firstBg = 0 }, Phone)
  self:sync()
  return self
end

-- -------------------------------------------------------------- the book

function Phone:sync()
  local pg = self.gear:save()
  local numbers = pg.numbers or {}
  local order, seen = {}, {}
  for _, id in ipairs(pg.order or {}) do
    id = tonumber(id)
    if id and numbers[id] and not seen[id] then order[#order + 1] = id; seen[id] = true end
  end
  local extra = {}
  for id, yes in pairs(numbers) do
    id = tonumber(id)
    if yes and id and not seen[id] then extra[#extra + 1] = id end
  end
  table.sort(extra)
  for _, id in ipairs(extra) do order[#order + 1] = id end
  pg.order = order
  self.order = order
  if self.first >= #order then self.first = 0 end
  if self.first + self.cursor >= #order then self.cursor = math.max(0, math.min(ROWS - 1, #order - 1 - self.first)) end
end

function Phone:count() return #self.order end

function Phone:contact(index) return self.order[index + 1] end

function Phone:name(id)
  local rec = ((self.gear:art().contacts) or {})[id]
  if not rec then return "" end
  return (rec.bank and self.gear:text(rec.bank, 0)) or rec.name or ""
end

function Phone:class(id)
  local entry = (((self.game.data or {}).gen4_hgss_phone_call or {}).book or {})[id]
  local cls = entry and entry.trainerClass
  if not cls or cls == 200 then return "" end
  if cls >= 201 then return self.gear:text(271, cls - 201 + 38) or "" end
  return self.gear:text(730, cls) or ""
end

-- ----------------------------------------------------------- the scroll

function Phone:scroll(dir, rows)
  -- dir -1 up (earlier contacts), +1 down
  local n = self:count()
  local moved = 0
  for _ = 1, rows do
    if dir < 0 and self.first > 0 then
      self.first, moved = self.first - 1, moved + 1
    elseif dir > 0 and self.first + ROWS < n then
      self.first, moved = self.first + 1, moved + 1
    end
  end
  if moved > 0 then
    self.firstBg = (self.firstBg + moved) % 2
    -- each row slides 24 px over 3 frames
    self.slide = { dir = dir, px = ROW_H * moved, step = 8 }
  end
  return moved > 0
end

function Phone:update()
  if self.slide then
    self.slide.px = self.slide.px - self.slide.step
    if self.slide.px <= 0 then self.slide = nil end
  end
  if self.call and self.game.stack:top() == self.gear then
    -- PhoneCall_Exit: back to the list
    self.call = nil
    self.busy = false
  end
end

-- ------------------------------------------------------------- the menus

function Phone:tooltip(id) self.tip = id end

function Phone:openMenu()
  local id = self:contact(self.first + self.cursor)
  if not id then return end
  self.selected = self.first + self.cursor
  self.gear:se("SEQ_SE_GS_GEARDECIDE")
  local items = {}
  for i = 0, 2 do items[#items + 1] = self.gear:text(271, i) or ({ "Call", "Sort", "Quit" })[i + 1] end
  self.menu = TouchList.new(self.gear, items, 13, 9, 16)
  self.menuKind = "main"
  self:tooltip(22)
  self.busy = true
end

function Phone:openSort()
  local items = {}
  for i = 3, 7 do items[#items + 1] = self.gear:text(271, i) or "" end
  self.menu = TouchList.new(self.gear, items, 13, 3, 16, { onMove = function(c) self:tooltip(23 + c) end })
  self.menuKind = "sort"
  self:tooltip(23)
end

function Phone:closeMenu()
  self.menu, self.menuKind, self.tip = nil, nil, nil
  self.selected = nil
  self.busy = false
end

function Phone:sortBy(k)
  local params = self.gear:art().sortParams or {}
  local order = self.order
  -- PokegearPhone_SortList: for i, for j from the end down to i + 1, swap
  -- when sortParam[k] of j is below i's
  local function key(id) local p = params[id]; return p and p[k + 1] or 255 end
  for i = 1, #order - 1 do
    for j = #order, i + 1, -1 do
      if key(order[j]) < key(order[i]) then order[i], order[j] = order[j], order[i] end
    end
  end
  self.gear:save().order = order
  self.first, self.cursor = 0, 0
end

function Phone:startCall()
  local id = self:contact(self.selected or (self.first + self.cursor))
  self:closeMenu()
  if not id then return end
  local UI = require("src.ui.HgssPhoneCall")
  if not UI.available(self.game) then
    print("[pokegear] phone call data is not in this cache (re-import HeartGold / SoulSilver)")
    return
  end
  local header, headerId = self.gear:header()
  self.call = { caller = id, kind = 0, id = 0, outgoing = true, gear = self.gear, header = header, headerId = headerId }
  self.busy = true
  self.game.stack:push(UI.new(self.game, self.call, nil, { save = self.game.save, game = self.game }))
end

function Phone:busyUpdate(input, tap)
  if self.call then return end
  if self.moving then return self:movingUpdate(input, tap) end
  if not self.menu then self.busy = false; return end
  local r = self.menu:update(input, tap)
  if r == nil then return end
  local kind = self.menuKind
  if kind == "main" then
    if r == 0 then return self:startCall() end
    if r == 1 then self.menu = nil; return self:openSort() end
    return self:closeMenu()
  elseif kind == "sort" then
    if r == 0 or r == 1 or r == 2 then
      self:sortBy(r)
      return self:closeMenu()
    end
    if r == 3 then
      -- Move: the arrows, the picked contact held
      self.menu, self.menuKind = nil, nil
      self.moving = true
      self:tooltip(21)
      return
    end
    return self:closeMenu()
  end
end

-- PhoneContactListUI_HandleKeyInput2 / _HandleTouchInput2
function Phone:movingUpdate(input, tap)
  if self.slide then return end
  local n = self:count()
  local dest
  if tap then
    for i = 0, ROWS - 1 do
      local y0 = 8 + 24 * i
      if tap.y >= y0 and tap.y < y0 + 16 and tap.x >= 4 and tap.x < 36 and self.first + i < n then
        self.cursor = i
        self.gear:se("SEQ_SE_GS_GEARDECIDE")
        dest = self.first + i
      end
    end
    if not dest and tap.x >= 224 and tap.x < 248 then
      if tap.y >= 8 and tap.y < 80 and self.first > 0 then self.gear:se("SEQ_SE_GS_GEARCURSOR"); self:scroll(-1, ROWS)
      elseif tap.y >= 80 and tap.y < 152 and self.first + ROWS < n then self.gear:se("SEQ_SE_GS_GEARCURSOR"); self:scroll(1, ROWS) end
    end
  elseif input then
    if input:wasPressed("a") then dest = self.first + self.cursor
    elseif input:wasPressed("b") then dest = self.selected
    else self:moveKeys(input) end
  end
  if dest == nil then return end
  local from = self.selected
  if from and dest ~= from then
    local id = table.remove(self.order, from + 1)
    table.insert(self.order, dest + 1, id)
    self.gear:save().order = self.order
  end
  self.moving = false
  self:closeMenu()
end

-- ------------------------------------------------------------- the list

function Phone:moveKeys(input)
  local n = self:count()
  local index = self.first + self.cursor
  if input:wasPressed("up") then
    if index == 0 then return end
    self.gear:se("SEQ_SE_GS_GEARCURSOR")
    if self.cursor == 0 then self:scroll(-1, 1) else self.cursor = self.cursor - 1 end
  elseif input:wasPressed("down") then
    if index >= n - 1 then return end
    self.gear:se("SEQ_SE_GS_GEARCURSOR")
    if self.cursor == ROWS - 1 then self:scroll(1, 1) else self.cursor = self.cursor + 1 end
  elseif input:wasPressed("left") then
    if self.first ~= 0 then self.gear:se("SEQ_SE_GS_GEARCURSOR"); self:scroll(-1, ROWS) end
  elseif input:wasPressed("right") then
    if self.first + ROWS < n then self.gear:se("SEQ_SE_GS_GEARCURSOR"); self:scroll(1, ROWS) end
  end
  local last = math.min(ROWS, n - self.first) - 1
  if self.cursor > last then self.cursor = math.max(0, last) end
end

function Phone:keys(input)
  if self.slide then return end
  if input:wasPressed("b") then return self.gear:toBar() end
  if input:wasPressed("a") then
    if self:count() > 0 then self:openMenu() end
    return
  end
  self:moveKeys(input)
end

function Phone:touch(x, y)
  if self.slide then return false end
  local n = self:count()
  for i = 0, ROWS - 1 do
    local y0 = TOP + ROW_H * i
    if y >= y0 and y < y0 + ROW_H and x >= 8 and x < 224 then
      if self.first + i >= n then return false end
      self.cursor = i
      self:openMenu()
      return true
    end
  end
  if x >= 224 and x < 248 then
    if y >= 8 and y < 80 and self.first ~= 0 then
      self:scroll(-1, ROWS); self.gear:se("SEQ_SE_GS_GEARCURSOR"); return true
    end
    if y >= 80 and y < 152 and self.first + ROWS < n then
      self:scroll(1, ROWS); self.gear:se("SEQ_SE_GS_GEARCURSOR"); return true
    end
  end
  return false
end

function Phone:reselect() end
function Phone:enter() self:sync() end

-- ------------------------------------------------------------------ draw

local function setc(c) love.graphics.setColor(c[1], c[2], c[3], 1) end

function Phone:drawRow(slot, index, y)
  local g = love.graphics
  local gear = self.gear
  local id = self:contact(index)
  local alt = ((slot + self.firstBg) % 2) == 1
  local function ink(i, fb) return gear:ink("phoneList", i, fb) end
  local fill1 = ink(alt and 14 or 11, { 0.85, 0.85, 0.85 })
  local bg1 = ink(alt and 12 or 9, { 1, 1, 1 })
  local bg2 = ink(alt and 13 or 10, { 0.9, 0.9, 0.95 })
  local x = 8
  setc(fill1); g.rectangle("fill", x, y, 216, 24)
  setc(bg1); g.rectangle("fill", x + 8, y, 82, 20)
  setc(bg2); g.rectangle("fill", x + 90, y, 126, 20)
  setc(bg2); g.rectangle("fill", x + 1, y + 1, 2, 2)
  setc(fill1)
  g.rectangle("fill", x + 8, y, 2, 7)
  g.rectangle("fill", x + 9, y + 9, 2, 2)
  g.rectangle("fill", x + 9, y + 13, 2, 2)
  g.rectangle("fill", x + 9, y + 17, 2, 2)
  if not id then return end
  local sel = self.selected == index
  Font.pushStyle({ text = ink(sel and 3 or 1, { 0.2, 0.2, 0.2 }), shadow = ink(sel and 4 or 2, { 0.7, 0.7, 0.7 }) })
  Font.draw(self:name(id), x + 16, y + 2)
  Font.popStyle()
  Font.pushStyle({ text = ink(sel and 7 or 5, { 0.2, 0.2, 0.2 }), shadow = ink(sel and 8 or 6, { 0.7, 0.7, 0.7 }) })
  Font.draw(self:class(id), x + 94, y + 2)
  Font.popStyle()
end

function Phone:drawTouch()
  local g = love.graphics
  local gear = self.gear
  local n = self:count()
  -- MAIN_3: the list, a row above / below while it slides
  local off = 0
  if self.slide then off = (self.slide.dir > 0) and self.slide.px or -self.slide.px end
  for slot = -1, ROWS do
    local index = self.first + slot
    if index >= 0 and index < n or (slot >= 0 and slot < ROWS) then
      self:drawRow(slot, index, TOP + ROW_H * slot + off)
    end
  end
  g.setColor(1, 1, 1, 1)
  -- MAIN_2: the frame over it (the list area is open)
  gear:picture("phone_top")
  -- OBJ: the cursor, the arrows, the move arrows
  if not self.slide then
    if self.first > 0 then gear:obj("phone", 0, 0, 124, 8) end
    if self.first + ROWS < n then gear:obj("phone", 1, 0, 124, 156) end
  end
  if self.moving then
    for i = 0, math.min(ROWS, n - self.first) - 1 do
      gear:obj("phone", i == self.cursor and 7 or 6, 0, 12, 16 + 24 * i)
    end
  elseif not gear.zone and not self.menu and not self.call and n > 0 and not gear.fade then
    local y = self.cursor * 24
    gear:corners(0, 0, 16, 224, y + 8, y + 30, "phone", 2)
  end
end

-- over the bar: the context menu and the tooltip's words (MAIN_1)
function Phone:drawTouchOver()
  if self.tip then
    -- the tooltip strip over the bar at row 20 (the phone screen's rows
    -- 24-27, PokegearPhone_PrintContextMenuTooltip)
    local full = self.gear:img("phone_full")
    if full then self.gear:tiles(full, 0, 24, 32, 4, 0, 20) end
    local s = self.gear:text(271, self.tip) or ""
    -- windows[3], MAIN_1 palette 10, MAKE_TEXT_COLOR(3, 2, 5)
    Font.pushStyle({ text = self.gear:ink("phoneTip", 3, { 1, 1, 1 }), shadow = self.gear:ink("phoneTip", 2, { 0.3, 0.3, 0.3 }) })
    Font.draw(s, floor((256 - Font.width(s)) / 2), 168)
    Font.popStyle()
  end
  if self.menu then self.menu:draw() end
end

-- SUB_3: the call window's panel (empty until a call prints in it)
function Phone:drawTop()
  self.gear:picture("phone_bottom")
end

return Phone
