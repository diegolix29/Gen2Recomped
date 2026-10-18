-- HEARTGOLD / SOULSILVER POKEDEX: SEARCH (overlay 18 states 21-56, the
-- search screen and its seven sub-pages), opened from the lid's SEARCH (Y)
-- or the list's SEARCH (Y). Owned by src/ui/HgssPokedex.lua (`dex`), which
-- draws the art and owns the list; this module is the state, the input and
-- the layout. The filtering itself is src/ui/HgssDexData.lua.
--
-- READ FROM CODE (pokeheartgold asm/overlay_18.s; src/application/pokedex/
-- ov18_021E8BF4.c PokedexApp_MainSeq_22-56):
--   * every touch rectangle (TouchscreenHitbox tables, top/bottom/left/right)
--     and every d-pad grid (GridInputHandler DpadMenuBox: x, y, up, down,
--     left, right) of the main page (ov18_021FB878 / FB9F0) and the sub-pages
--     ORDER (FB828 / FB968), NAME (FBA94 / FBC34), TYPE (FBA40 / FBB94),
--     HT and WT (FB6C8 / FB780, FB6DC / FB7A0, arrows FB718), AREA (FB744 /
--     FB8D4), FORM i.e. body style (FB9A8 / FBB0C)
--   * the main page's actions (MainSeq_22: 0 ORDER .. 6 FORM, 7 RESET,
--     8 START, 9 CANCEL; B = CANCEL; START = START, ov18_021F6E2C), each
--     sub-page backing its criteria up and B / CANCEL restoring them
--     (MainSeq_28-56), START = OK in every sub-page, the two type slots
--     (MainSeq_35: the first pick fills type 1, the next type 2, a third
--     shifts them; ALL clears type 2 then type 1; OK with two equal types
--     drops type 2), the sliders (MainSeq_38-50: LEFT/RIGHT on the selected
--     bound with the acceleration of ov18_021EAD74 -- step 1, then 8 after 8
--     repeats, 16 after 16, 32 after 24 -- the bounds never cross), NAME's
--     letter -> cell table (ov18_021F9C20: ALL is cell 27)
--   * RESET (MainSeq_24) puts the defaults back; START (MainSeq_23) runs the
--     search, shows "Searching..." (msg 25, 32 frames) and either the results
--     list or "No matching Pokemon were found." / "Not found..." (msgs 23/24)
--     for 60 frames or until A / B / a touch, back to the search page
--   * the windows (ov18_021F9FDC, tiles): the main page's labels (20)-(26),
--     values (27)-(35), the bar's RESET / START / CANCEL (17)-(19); ORDER
--     (36)-(43), TYPE (44)-(64), NAME (65)-(67), HT (68)-(70), WT (71)-(73),
--     AREA (74)-(79), FORM (80); the top screen's message box (0) and its
--     copy of the summary (1)-(16)
--   * the words: bank 802 (12-25 messages, 26-32 the field names, 35-37
--     RESET / START / CANCEL, 39-40 OK / CANCEL, 41-46 the orders, 47-63 the
--     types through ov18_021F9DC0, 64 "----", 65-67 JOHTO / KANTO / UNKNOWN,
--     69-94 A-Z)
--   * the cursor is the list's cursor sprite with a per-field animation
--     (ov18_021FBD1C / FB628 / FB620 / FB618) at the d-pad box's x, y
-- APPROXIMATED: the slider thumbs (OBJ, drawn as a bar) and their x scale,
-- the highlight of a chosen cell (a palette swap on the cartridge, a tint
-- here), the top screen's slide-up animation while searching (a progress
-- bar from the search OBJ instead), the text colours.

local D = require("src.ui.HgssDexData")

local S = {}
S.__index = S

local floor = math.floor

-- {top, bottom, left, right}
local function R(t, b, l, r) return { t = t, b = b, l = l, r = r } end
-- {x, y, up, down, left, right} (0x80 flag dropped)
local function P(x, y, u, d, l, r) return { x = x, y = y, u = u % 128, d = d % 128, l = l % 128, r = r % 128 } end

local PAGES = {
  main = {
    rects = { R(8, 23, 128, 215), R(32, 47, 56, 127), R(56, 71, 56, 177), R(80, 95, 56, 183), R(104, 119, 56, 239),
      R(128, 143, 56, 111), R(56, 87, 208, 239), R(164, 187, 4, 75), R(164, 187, 92, 163), R(164, 187, 180, 251) },
    pad = { P(172, 16, 0, 1, 0, 0), P(92, 40, 0, 2, 1, 6), P(116, 64, 1, 3, 2, 6), P(112, 88, 2, 4, 3, 6),
      P(136, 112, 3, 5, 4, 4), P(84, 136, 4, 136, 5, 5), P(224, 72, 0, 4, 129, 6), P(40, 176, 5, 7, 7, 8),
      P(128, 176, 5, 8, 7, 9), P(216, 176, 5, 9, 8, 9) },
    anims = { [0] = 39, 35, 36, 59, 60, 38, 34, 35, 35, 35 },
  },
  order = {
    rects = { R(48, 63, 24, 111), R(48, 63, 144, 231), R(80, 95, 24, 111), R(80, 95, 144, 231), R(112, 127, 24, 111),
      R(112, 127, 144, 231), R(164, 187, 4, 75), R(164, 187, 180, 251) },
    pad = { P(68, 56, 6, 2, 1, 1), P(188, 56, 7, 3, 0, 0), P(68, 88, 0, 4, 3, 3), P(188, 88, 1, 5, 2, 2),
      P(68, 120, 2, 6, 5, 5), P(188, 120, 3, 7, 4, 4), P(40, 176, 4, 0, 7, 7), P(216, 176, 5, 1, 6, 6) },
    anims = { [0] = 39, 39, 39, 39, 39, 39, 35, 35 },
    ok = 6, cancel = 7,
  },
  name = { rects = {}, pad = {}, anims = {}, ok = 27, cancel = 28 },
  type = { rects = {}, pad = {}, anims = {}, ok = 18, cancel = 19 },
  height = {
    rects = { R(46, 73, 26, 229), R(118, 145, 26, 229), R(164, 187, 4, 75), R(164, 187, 180, 251) },
    pad = { P(52, 60, 2, 1, 0, 0), P(204, 132, 0, 130, 1, 1), P(40, 176, 1, 0, 3, 3), P(216, 176, 1, 0, 2, 2) },
    anims = { [0] = 62, 62, 35, 35 },
    ok = 2, cancel = 3,
  },
  area = {
    rects = { R(64, 79, 48, 103), R(64, 79, 152, 207), R(120, 135, 48, 103), R(120, 135, 152, 207),
      R(164, 187, 4, 75), R(164, 187, 180, 251) },
    pad = { P(76, 72, 4, 2, 1, 1), P(180, 72, 5, 3, 0, 0), P(76, 128, 0, 4, 3, 3), P(180, 128, 1, 5, 2, 2),
      P(40, 176, 2, 0, 5, 5), P(216, 176, 3, 1, 4, 4) },
    anims = { [0] = 38, 38, 38, 38, 35, 35 },
    ok = 4, cancel = 5,
  },
  body = { rects = {}, pad = {}, anims = {}, ok = 15, cancel = 16 },
}
PAGES.weight = PAGES.height
-- NAME: 7 x 4 letter cells (ov18_021FBA94 / FBC34), cell 26 = ALL
do
  local p = PAGES.name
  local xs = { 24, 56, 88, 120, 152, 184, 216 }
  for i = 0, 26 do
    local col, row = i % 7, floor(i / 7)
    if i == 26 then col, row = 6, 3 end
    p.rects[i + 1] = R(40 + 32 * row, 55 + 32 * row, xs[col + 1], xs[col + 1] + 15)
    p.anims[i] = 40
  end
  p.rects[28] = R(164, 187, 4, 75); p.rects[29] = R(164, 187, 180, 251)
  p.anims[27], p.anims[28] = 35, 35
  local raw = { { 32, 48, 27, 7, 6, 1 }, { 64, 48, 27, 8, 0, 2 }, { 96, 48, 27, 9, 1, 3 }, { 128, 48, 27, 10, 2, 4 },
    { 160, 48, 28, 11, 3, 5 }, { 192, 48, 28, 12, 4, 6 }, { 224, 48, 28, 13, 5, 0 }, { 32, 80, 0, 14, 13, 8 },
    { 64, 80, 1, 15, 7, 9 }, { 96, 80, 2, 16, 8, 10 }, { 128, 80, 3, 17, 9, 11 }, { 160, 80, 4, 18, 10, 12 },
    { 192, 80, 5, 19, 11, 13 }, { 224, 80, 6, 20, 12, 7 }, { 32, 112, 7, 21, 20, 15 }, { 64, 112, 8, 22, 14, 16 },
    { 96, 112, 9, 23, 15, 17 }, { 128, 112, 10, 24, 16, 18 }, { 160, 112, 11, 25, 17, 19 }, { 192, 112, 12, 28, 18, 20 },
    { 224, 112, 13, 26, 19, 14 }, { 32, 144, 14, 27, 26, 22 }, { 64, 144, 15, 27, 21, 23 }, { 96, 144, 16, 27, 22, 24 },
    { 128, 144, 17, 27, 23, 25 }, { 160, 144, 18, 28, 24, 26 }, { 224, 144, 20, 28, 25, 21 }, { 40, 176, 21, 0, 28, 28 },
    { 216, 176, 26, 6, 27, 27 } }
  for i, e in ipairs(raw) do p.pad[i] = P(e[1], e[2], e[3], e[4], e[5], e[6]) end
end
-- TYPE: 4 x 5 cells (ov18_021FBA40 / FBB94), 17 types + ALL
do
  local p = PAGES.type
  local xs = { { 3, 60 }, { 67, 124 }, { 131, 188 }, { 195, 252 } }
  local ys = { { 40, 55 }, { 64, 79 }, { 88, 104 }, { 112, 127 }, { 136, 151 } }
  for i = 0, 17 do
    local c, r = xs[i % 4 + 1], ys[floor(i / 4) + 1]
    p.rects[i + 1] = R(r[1], r[2], c[1], c[2])
    p.anims[i] = 38
  end
  p.rects[19] = R(164, 187, 4, 75); p.rects[20] = R(164, 187, 180, 251)
  p.anims[18], p.anims[19] = 35, 35
  local raw = { { 32, 48, 18, 4, 3, 1 }, { 96, 48, 18, 5, 0, 2 }, { 160, 48, 19, 6, 1, 3 }, { 224, 48, 19, 7, 2, 0 },
    { 32, 72, 0, 8, 7, 5 }, { 96, 72, 1, 9, 4, 6 }, { 160, 72, 2, 10, 5, 7 }, { 224, 72, 3, 11, 6, 4 },
    { 32, 96, 4, 12, 11, 9 }, { 96, 96, 5, 13, 8, 10 }, { 160, 96, 6, 14, 9, 11 }, { 224, 96, 7, 15, 10, 8 },
    { 32, 120, 8, 16, 15, 13 }, { 96, 120, 9, 17, 12, 14 }, { 160, 120, 10, 19, 13, 15 }, { 224, 120, 11, 19, 14, 12 },
    { 32, 144, 12, 18, 17, 17 }, { 96, 144, 13, 18, 16, 16 }, { 40, 176, 16, 0, 19, 19 }, { 216, 176, 15, 3, 18, 18 } }
  for i, e in ipairs(raw) do p.pad[i] = P(e[1], e[2], e[3], e[4], e[5], e[6]) end
end
-- FORM (body style): 5 x 3 cells (ov18_021FB9A8 / FBB0C), cell 14 = ALL
do
  local p = PAGES.body
  for i = 0, 14 do
    local c, r = i % 5, floor(i / 5)
    p.rects[i + 1] = R(40 + 40 * r, 71 + 40 * r, 16 + 48 * c, 47 + 48 * c)
    p.anims[i] = 34
  end
  p.rects[16] = R(164, 187, 4, 75); p.rects[17] = R(164, 187, 180, 251)
  p.anims[15], p.anims[16] = 35, 35
  local raw = { { 32, 56, 15, 5, 4, 1 }, { 80, 56, 15, 6, 0, 2 }, { 128, 56, 15, 7, 1, 3 }, { 176, 56, 16, 8, 2, 4 },
    { 224, 56, 16, 9, 3, 0 }, { 32, 96, 0, 10, 9, 6 }, { 80, 96, 1, 11, 5, 7 }, { 128, 96, 2, 12, 6, 8 },
    { 176, 96, 3, 13, 7, 9 }, { 224, 96, 4, 14, 8, 5 }, { 32, 136, 5, 15, 14, 11 }, { 80, 136, 6, 15, 10, 12 },
    { 128, 136, 7, 15, 11, 13 }, { 176, 136, 8, 16, 12, 14 }, { 224, 136, 9, 16, 13, 10 }, { 40, 176, 10, 0, 16, 16 },
    { 216, 176, 14, 4, 15, 15 } }
  for i, e in ipairs(raw) do p.pad[i] = P(e[1], e[2], e[3], e[4], e[5], e[6]) end
end
-- the slider arrows (ov18_021FB718): max+ / max- / min+ / min-
local ARROWS = { { R(49, 70, 230, 245), "hmax", 1 }, { R(49, 70, 10, 25), "hmax", -1 },
  { R(121, 142, 230, 245), "hmin", 1 }, { R(121, 142, 10, 25), "hmin", -1 } }

-- ov18_021F9DC0: type -> bank 802 message
local TYPE_MSG = { [0] = 58, 50, 60, 56, 54, 48, 63, 53, 59, 61, 62, 51, 55, 49, 52, 57, 47, 64 }
S.TYPE_MSG = TYPE_MSG
-- the page's message pair (ov18_021EEED0)
local MESSAGE = { main = 13, order = 16, name = 17, type = 18, height = 20, weight = 19, area = 22, body = 21 }
local FIELD = { [0] = "order", "name", "type", "height", "weight", "area", "body" }
local LABEL = { order = 26, name = 27, type = 28, height = 29, weight = 30, area = 31, body = 32 }
S.SLIDER = { top = 60, bottom = 132, left = 28, width = 200 }

local function inRect(r, x, y) return r and x >= r.l and x <= r.r and y >= r.t and y <= r.b end

function S.new(dex, criteria)
  local self = setmetatable({}, S)
  self.dex = dex
  self.c = criteria or D.copyDefaults()
  self.page = "main"
  self.cursor = 0
  self.cursors = {}
  self.t = 0
  return self
end

function S:words(i, fallback) return D.text(self.dex.game, 802, i) or fallback end
function S:se(name) self.dex:se(name) end

-- ------------------------------------------------------------- values --

function S:valueText(field)
  local c = self.c
  if field == "order" then return self:words(41 + c.order, ({ "Numerical", "A to Z", "Heaviest", "Lightest", "Tallest", "Smallest" })[c.order + 1]) end
  if field == "name" then return c.letter >= 26 and self:words(64, "----") or self:words(69 + c.letter, string.char(65 + c.letter)) end
  if field == "type1" then return self:words(TYPE_MSG[c.type1], "----") end
  if field == "type2" then return self:words(TYPE_MSG[c.type2], "----") end
  local stops = D.stops((self.dex.art or {}).search)
  if field == "hmin" or field == "hmax" then return D.fmtHeight(stops[c[field]][1]) end
  if field == "wmin" or field == "wmax" then return (D.fmtWeight(stops[c[field]][2]):gsub(" lbs%.", "")) end
  if field == "area" then return self:words(({ [0] = 65, 66, 67, 64 })[c.area], ({ [0] = "JOHTO", "KANTO", "UNKNOWN", "----" })[c.area]) end
  return ""
end

-- -------------------------------------------------------------- pages --

function S:open(page)
  self.cursors[self.page] = self.cursor
  self.page = page
  self.cursor = 0
  if page == "main" then self.cursor = self.cursors.main or 0 end
  if page == "order" then self.backup = { order = self.c.order }; self.cursor = self.c.order
  elseif page == "name" then self.backup = { letter = self.c.letter }; self.cursor = self.c.letter
  elseif page == "type" then self.backup = { type1 = self.c.type1, type2 = self.c.type2 }
  elseif page == "height" then self.backup = { hmin = self.c.hmin, hmax = self.c.hmax }
  elseif page == "weight" then self.backup = { wmin = self.c.wmin, wmax = self.c.wmax }
  elseif page == "area" then self.backup = { area = self.c.area }; self.cursor = math.min(self.c.area, 3)
  elseif page == "body" then self.backup = { body = self.c.body }; self.cursor = self.c.body end
  self.hold = nil
end

function S:closePage(ok)
  if ok then
    if self.page == "type" and self.c.type1 == self.c.type2 then self.c.type2 = 17 end
    self:se("SEQ_SE_GS_ZKN04")
  else
    for k, v in pairs(self.backup or {}) do self.c[k] = v end
    self:se("SEQ_SE_GS_GEARCANCEL")
  end
  self.backup = nil
  self:open("main")
end

function S:start()
  self:se("SEQ_SE_DP_Z_SEARCH")
  self.page, self.timer = "searching", 0
  local results = D.results(self.dex, self.c)
  self.found = results
end

-- the slider bounds (min / max for height or weight) and their step
-- (ov18_021EAD74)
function S:nudge(key, dir)
  local c = self.c
  local isMax = key:sub(2) == "max"
  local lo = isMax and c[key:sub(1, 1) .. "min"] or 0
  local hi = isMax and D.STOPS or c[key:sub(1, 1) .. "max"]
  self.repeats = (self.repeats or 0)
  if self.repeats ~= 24 then self.repeats = self.repeats + 1 end
  local step = self.repeats >= 24 and 32 or self.repeats >= 16 and 16 or self.repeats >= 8 and 8 or 1
  local v = math.max(lo, math.min(hi, c[key] + step * dir))
  if v ~= c[key] then c[key] = v; self:se("SEQ_SE_GS_ZKN03") end
end

function S:sliderKey(row)
  local prefix = self.page == "height" and "h" or "w"
  return prefix .. (row == 0 and "max" or "min")
end

function S:sliderSet(row, x)
  local key = self:sliderKey(row)
  local v = floor((x - S.SLIDER.left) * D.STOPS / S.SLIDER.width + 0.5)
  local c = self.c
  local isMax = row == 0
  local lo = isMax and c[key:sub(1, 1) .. "min"] or 0
  local hi = isMax and D.STOPS or c[key:sub(1, 1) .. "max"]
  v = math.max(lo, math.min(hi, v))
  if v ~= c[key] then c[key] = v; self:se("SEQ_SE_GS_ZKN03") end
end

-- choose item i of the current page (touch or A)
function S:choose(i)
  local page = self.page
  local p = PAGES[page]
  if page == "main" then
    if i <= 6 then
      self:se("SEQ_SE_GS_ZKN04")
      self.cursors.main = i
      return self:open(FIELD[i])
    elseif i == 7 then
      self:se("SEQ_SE_GS_ZKN04")
      self.c = D.copyDefaults()
    elseif i == 8 then
      self:se("SEQ_SE_GS_ZKN04")
      return self:start()
    elseif i == 9 then
      self:se("SEQ_SE_GS_GEARCANCEL")
      return self.dex:closeSearch()
    end
    return
  end
  if i == p.ok then return self:closePage(true) end
  if i == p.cancel then return self:closePage(false) end
  local c = self.c
  if page == "order" then c.order = i
  elseif page == "name" then c.letter = i
  elseif page == "area" then
    if i == 1 and not self.dex.hasNational then return end
    c.area = i
  elseif page == "body" then c.body = i
  elseif page == "type" then
    if i == 17 then
      if c.type2 ~= 17 then c.type2 = 17 else c.type1 = 17 end
    elseif c.type1 == 17 then c.type1 = i
    elseif c.type2 == 17 then
      if c.type1 == i then return end
      c.type2 = i
    else
      if c.type2 == i then return end
      c.type1, c.type2 = c.type2, i
    end
  elseif page == "height" or page == "weight" then
    return -- the slider rows take LEFT / RIGHT
  end
  self:se("SEQ_SE_GS_ZKN04")
end

-- -------------------------------------------------------------- input --

function S:tap(x, y)
  if self.page == "searching" then return end
  if self.page == "notfound" then return self:dismiss() end
  local p = PAGES[self.page]
  if self.page == "height" or self.page == "weight" then
    for k, a in ipairs(ARROWS) do
      if inRect(a[1], x, y) then
        local row = k <= 2 and 0 or 1
        self.cursor = row
        self.repeats = 0
        self.hold = { kind = "arrow", row = row, dir = a[3] }
        return self:nudge(self:sliderKey(row), a[3])
      end
    end
    for row = 0, 1 do
      if inRect(p.rects[row + 1], x, y) then
        self.cursor = row
        self.hold = { kind = "drag", row = row }
        return self:sliderSet(row, x)
      end
    end
  end
  for i, r in ipairs(p.rects) do
    if inRect(r, x, y) and not (self.page == "area" and i == 2 and not self.dex.hasNational) then
      self.cursor = i - 1
      return self:choose(i - 1)
    end
  end
end

function S:drag(x, y)
  local h = self.hold
  if h and h.kind == "drag" then self:sliderSet(h.row, x) end
end
function S:release() self.hold = nil end

function S:dismiss()
  self.page = "main"
  self.cursor = self.cursors.main or 0
end

function S:update(pressed, rep, held)
  self.t = self.t + 1
  if self.page == "searching" then
    self.timer = self.timer + 1
    if self.timer >= 32 then
      if #self.found > 0 then
        self.dex:showResults(self.found, self.c)
      else
        self:se("SEQ_SE_DP_CUSTOM06")
        self.page, self.timer = "notfound", 0
      end
    end
    return
  end
  if self.page == "notfound" then
    self.timer = self.timer + 1
    if pressed("a") or pressed("b") or self.timer >= 60 then self:dismiss() end
    return
  end
  -- a held slider arrow keeps stepping (MainSeq_42 / 43 / 49 / 50)
  if self.hold and self.hold.kind == "arrow" then
    if held("touch") then
      self.hold.frames = (self.hold.frames or 0) + 1
      if self.hold.frames >= 8 and self.hold.frames % 4 == 0 then self:nudge(self:sliderKey(self.hold.row), self.hold.dir) end
    else self.hold = nil end
  end
  local p = PAGES[self.page]
  if pressed("start") then
    if self.page == "main" then return self:choose(8) end
    return self:closePage(true)
  end
  if pressed("b") then
    if self.page == "main" then return self:choose(9) end
    return self:closePage(false)
  end
  if (self.page == "height" or self.page == "weight") and self.cursor <= 1 then
    if rep("left") then return self:nudge(self:sliderKey(self.cursor), -1) end
    if rep("right") then return self:nudge(self:sliderKey(self.cursor), 1) end
    if not (held("left") or held("right")) then self.repeats = 0 end
  end
  local box = p.pad[self.cursor + 1]
  if not box then return end
  local nextIndex
  if rep("up") then nextIndex = box.u
  elseif rep("down") then nextIndex = box.d
  elseif rep("left") then nextIndex = box.l
  elseif rep("right") then nextIndex = box.r end
  if nextIndex and self.page == "area" and nextIndex == 1 and not self.dex.hasNational then
    nextIndex = (self.cursor == 0) and 0 or 3
  end
  if nextIndex and nextIndex ~= self.cursor then
    self.cursor = nextIndex
    self:se("SEQ_SE_GS_ZKN03")
    return
  end
  if pressed("a") then return self:choose(self.cursor) end
end

-- --------------------------------------------------------------- draw --

local function tint(r, color)
  local g = love.graphics
  g.setColor(color[1], color[2], color[3], color[4] or 0.45)
  g.rectangle("fill", r.l, r.t, r.r - r.l + 1, r.b - r.t + 1)
  g.setColor(1, 1, 1, 1)
end
local CHOSEN = { 0.95, 0.45, 0.25, 0.45 }
local CYAN = { 0.19, 0.75, 0.88 }

-- a fallback button (no art in the cache): a rounded white box
local function button(dex, r, label, style)
  local g = love.graphics
  g.setColor(0.35, 0.4, 0.45, 1)
  g.rectangle("fill", r.l, r.t, r.r - r.l + 1, r.b - r.t + 1, 3, 3)
  g.setColor(style == "dark" and 0.75 or 0.97, style == "dark" and 0.82 or 0.98, style == "dark" and 0.86 or 0.99, 1)
  g.rectangle("fill", r.l + 1, r.t + 1, r.r - r.l - 1, r.b - r.t - 1, 3, 3)
  g.setColor(1, 1, 1, 1)
  if label then dex.ui.putCentre("dark", label, r.l, r.r + 1, r.t + floor((r.b - r.t + 1 - 16) / 2)) end
end

function S:drawBar(ok)
  local dex = self.dex
  local key = ok and "search_okbar" or "search_bar"
  if not dex:bg(key, 0, 160) then
    local g = love.graphics
    g.setColor(CYAN[1], CYAN[2], CYAN[3], 1); g.rectangle("fill", 0, 160, 256, 32); g.setColor(1, 1, 1, 1)
    local rs = ok and { R(164, 187, 4, 75), R(164, 187, 180, 251) } or { R(164, 187, 4, 75), R(164, 187, 92, 163), R(164, 187, 180, 251) }
    for _, r in ipairs(rs) do button(dex, r) end
  end
  local labels = ok and { { 39, "OK", 40 }, { 40, "CANCEL", 216 } }
    or { { 35, "RESET", 40 }, { 36, "START", 128 }, { 37, "CANCEL", 216 } }
  for _, l in ipairs(labels) do dex.ui.putCentre("dark", self:words(l[1], l[2]), l[3] - 32, l[3] + 32, 168) end
end

-- the page's background, or a plain fallback with the touch boxes
function S:drawBase(key, rects, count)
  local dex = self.dex
  local g = love.graphics
  if dex:bg(key, 0, 0) then return true end
  g.setColor(1, 1, 1, 1); g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(0.86, 0.88, 0.9, 1)
  for x = 0, 256, 16 do g.rectangle("fill", x, 0, 1, 192) end
  for y = 0, 192, 16 do g.rectangle("fill", 0, y, 256, 1) end
  g.setColor(CYAN[1], CYAN[2], CYAN[3], 1)
  g.rectangle("fill", 8, 4, 240, 24, 6, 6)
  g.setColor(1, 1, 1, 1)
  for i = 1, count or #rects do if rects[i] then button(dex, rects[i]) end end
  return false
end

function S:drawCursor()
  local p = PAGES[self.page]
  local box = p and p.pad[self.cursor + 1]
  if not box then return end
  local a = p.anims[self.cursor]
  if not (a and self.dex:anim(a, box.x, box.y)) then
    local r = p.rects[self.cursor + 1]
    if r then
      local g = love.graphics
      g.setColor(0.9, 0.15, 0.15, 1)
      g.setLineWidth(2)
      g.rectangle("line", r.l - 1, r.t - 1, r.r - r.l + 3, r.b - r.t + 3, 3, 3)
      g.setLineWidth(1)
      g.setColor(1, 1, 1, 1)
    end
  end
end

function S:drawMain()
  local dex, ui = self.dex, self.dex.ui
  local p = PAGES.main
  local art = self:drawBase("search_bg", p.rects, 7)
  if not art then
    -- the field rows of screen 57, roughly: a cyan tab per label
    local g = love.graphics
    g.setColor(CYAN[1], CYAN[2], CYAN[3], 1)
    for _, y in ipairs({ 8, 32, 56, 80, 104, 128 }) do g.rectangle("fill", 0, y - 2, 52, 20, 4, 4) end
    g.rectangle("fill", 196, 30, 56, 60, 4, 4)
    g.setColor(1, 1, 1, 1)
    button(dex, p.rects[7])
  end
  -- (20)-(26) the labels, (27)-(35) the values
  ui.put("white", self:words(26, "ORDER"), 32, 8)
  local labelY = { 32, 56, 80, 104, 128 }
  for k, id in ipairs({ 27, 28, 29, 30, 31 }) do ui.put("white", self:words(id, ""), 8, labelY[k]) end
  ui.put("white", self:words(32, "FORM"), 200, 32)
  ui.putCentre("dark", self:valueText("order"), 128, 216, 8)
  ui.putCentre("dark", self:valueText("name"), 56, 128, 32)
  ui.putCentre("dark", self:valueText("type1"), 56, 120, 56)
  ui.putCentre("dark", self:valueText("type2"), 120, 184, 56)
  ui.putCentre("dark", self:valueText("hmin"), 56, 104, 80)
  ui.putCentre("dark", self:valueText("hmax"), 120, 168, 80)
  ui.putCentre("dark", self:valueText("wmin"), 56, 128, 104)
  ui.putCentre("dark", self:valueText("wmax"), 144, 216, 104)
  ui.putCentre("dark", self:valueText("area"), 56, 112, 128)
  if self.c.body < 14 then dex:obj("srch_" .. self.c.body, 224, 72) end
  self:drawBar(false)
end

function S:drawPage()
  local dex, ui = self.dex, self.dex.ui
  local page = self.page
  local p = PAGES[page]
  local c = self.c
  local count = p.ok
  local art = self:drawBase("search_" .. page, p.rects, count)
  local label = self:words(LABEL[page], "")
  if page == "order" then
    ui.put("white", label, 24, 8)
    ui.putCentre("dark", self:valueText("order"), 144, 232, 8)
    for i = 0, 5 do
      local r = p.rects[i + 1]
      if c.order == i then tint(r, CHOSEN) end
      ui.putCentre("dark", self:words(41 + i, ""), r.l, r.r + 1, r.t)
    end
  elseif page == "name" then
    ui.put("white", label, 56, 8)
    ui.putCentre("dark", self:valueText("name"), 120, 192, 8)
    for i = 0, 26 do
      local r = p.rects[i + 1]
      if c.letter == i then tint(r, CHOSEN) end
      ui.putCentre("dark", i == 26 and "-" or self:words(69 + i, string.char(65 + i)), r.l, r.r + 1, r.t)
    end
  elseif page == "type" then
    ui.put("white", label, 24, 8)
    ui.putCentre("dark", self:valueText("type1"), 104, 168, 8)
    ui.putCentre("dark", self:valueText("type2"), 168, 232, 8)
    for i = 0, 17 do
      local r = p.rects[i + 1]
      if c.type1 == i or c.type2 == i then tint(r, CHOSEN) end
      ui.putCentre("dark", self:words(TYPE_MSG[i], D.TYPE_NAMES[i + 1] or "----"), r.l, r.r + 1, r.t)
    end
  elseif page == "height" or page == "weight" then
    local h = page == "height"
    ui.put("white", label, h and 24 or 8, 8)
    ui.putCentre("dark", self:valueText(h and "hmin" or "wmin"), h and 80 or 64, h and 136 or 136, 8)
    ui.putCentre("dark", self:valueText(h and "hmax" or "wmax"), 152, h and 208 or 224, 8)
    local g = love.graphics
    if not art then
      g.setColor(0.25, 0.3, 0.4, 1)
      for _, y in ipairs({ 58, 62, 130, 134 }) do g.rectangle("fill", 16, y, 224, 1) end
    end
    -- the arrows and the thumbs (OBJ on the cartridge)
    for k, a in ipairs(ARROWS) do
      local r = a[1]
      local cx, cy = floor((r.l + r.r) / 2), floor((r.t + r.b) / 2)
      g.setColor(0.2, 0.45, 0.7, 1)
      if a[3] > 0 then g.polygon("fill", cx - 4, cy - 6, cx + 4, cy, cx - 4, cy + 6)
      else g.polygon("fill", cx + 4, cy - 6, cx - 4, cy, cx + 4, cy + 6) end
    end
    for row = 0, 1 do
      local v = c[self:sliderKey(row)]
      local x = S.SLIDER.left + floor(v * S.SLIDER.width / D.STOPS)
      local y = row == 0 and S.SLIDER.top or S.SLIDER.bottom
      g.setColor(0.2, 0.3, 0.45, 1); g.rectangle("fill", x - 4, y - 10, 9, 21, 2, 2)
      g.setColor(row == self.cursor and 0.95 or 0.75, row == self.cursor and 0.5 or 0.85, row == self.cursor and 0.3 or 0.95, 1)
      g.rectangle("fill", x - 3, y - 9, 7, 19, 2, 2)
    end
    g.setColor(1, 1, 1, 1)
  elseif page == "area" then
    ui.put("white", label, 56, 8)
    ui.putCentre("dark", self:valueText("area"), 128, 184, 8)
    for i = 0, 3 do
      local r = p.rects[i + 1]
      if i == 1 and not dex.hasNational then
        -- ov18_021E7564 blanks the KANTO box without the National Dex
        -- (copies the grid rows over it); a white cover here
        local g = love.graphics
        g.setColor(1, 1, 1, 1); g.rectangle("fill", r.l - 2, r.t - 2, r.r - r.l + 6, r.b - r.t + 6)
      else
        if c.area == i then tint(r, CHOSEN) end
        ui.putCentre("dark", self:words(({ [0] = 65, 66, 67, 64 })[i], ""), r.l, r.r + 1, r.t)
      end
    end
  elseif page == "body" then
    ui.put("white", label, 64, 8)
    if c.body < 14 then dex:obj("srch_" .. c.body, 176, 16) end
    for i = 0, 14 do
      local r = p.rects[i + 1]
      if c.body == i then tint(r, CHOSEN) end
      if i < 14 then dex:obj("srch_" .. i, floor((r.l + r.r + 1) / 2), floor((r.t + r.b + 1) / 2)) end
    end
  end
  self:drawBar(true)
end

function S:drawTouch()
  love.graphics.setColor(1, 1, 1, 1)
  if self.page == "main" or self.page == "searching" or self.page == "notfound" then self:drawMain()
  else self:drawPage() end
  if self.page ~= "searching" and self.page ~= "notfound" then self:drawCursor() end
end

-- the top screen: the grid (59), the message box (60, window 0) and the
-- criteria summary (windows 1-16)
function S:drawTop()
  local dex, ui = self.dex, self.dex.ui
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if not dex:bg("search_top3", 0, 0) then
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(0.86, 0.88, 0.9, 1)
    for x = 0, 256, 16 do g.rectangle("fill", x, 0, 1, 192) end
    for y = 0, 192, 16 do g.rectangle("fill", 0, y, 256, 1) end
    g.setColor(1, 1, 1, 1)
  end
  if not dex:bg("search_top2", 0, 0) then
    g.setColor(CYAN[1], CYAN[2], CYAN[3], 1); g.rectangle("fill", 0, 152, 256, 40); g.setColor(1, 1, 1, 1)
  end
  ui.put("dark", self:words(26, "ORDER"), 32, 8)
  ui.put("dark", self:valueText("order"), 128, 8)
  local rows = { { 27, "name" }, { 28, "type1", "type2" }, { 29, "hmin", "hmax" }, { 30, "wmin", "wmax" }, { 31, "area" } }
  for k, row in ipairs(rows) do
    local y = 8 + 24 * k
    ui.put("dark", self:words(row[1], ""), 8, y)
    ui.put("dark", self:valueText(row[2]), 56, y)
    if row[3] then ui.put("dark", self:valueText(row[3]), row[1] == 30 and 144 or 120, y) end
  end
  ui.put("dark", self:words(32, "FORM"), 200, 32)
  if self.c.body < 14 then dex:obj("srch_" .. self.c.body, 224, 64) end
  -- the message (window 0 at (16,152) 224 x 40: two centred lines)
  local first, second = self:words(12, "Search Mode"), self:words(MESSAGE[self.page] or 13, "")
  if self.page == "searching" then first, second = self:words(25, "Searching..."), "" end
  if self.page == "notfound" then first, second = self:words(24, "Not found..."), self:words(23, "") end
  ui.putCentre("white", first, 16, 240, 158)
  ui.putCentre("white", second, 16, 240, 174)
  if self.page == "searching" then
    -- the search OBJ: the ball and the bar filling over the 32 frames
    dex:obj("srch2_0", 128, 72)
    local frame = 2 + math.min(8, floor(self.timer / 4))
    if not dex:obj("srch2_" .. frame, 128, 128) then
      g.setColor(0.3, 0.6, 0.9, 1); g.rectangle("fill", 64, 124, floor(128 * self.timer / 32), 8); g.setColor(1, 1, 1, 1)
    end
  end
end

S.PAGES = PAGES
return S
