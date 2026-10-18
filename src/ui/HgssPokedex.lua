-- HEARTGOLD / SOULSILVER'S POKEDEX (overlay 18), over the art
-- src/import/Gen4HgssDexArt.lua writes as `gen4_hgss_dex_art`. Screens routes
-- "PokedexMenu" / "Gen4Pokedex" here when that record exists.
--
-- THE CARTRIDGE'S SHAPE: the touch screen (HG's MAIN engine) is a red lid,
-- "JOHTO POKeDEX" / "NATIONAL POKeDEX", SEEN / OBTAINED counts and the
-- SEARCH / OPEN / QUIT bar; OPEN slides the lid off to the left (leaving its
-- START/INFO edge) over a 5 x 3 grid of 40 x 40 cells, a red cursor, a
-- scroll bar on the right, the name plate and SEARCH / CRY / DETAILS / QUIT.
-- The top screen shows the ring while the lid is shut, then the selected
-- entry: number, name, category, types, footprint, height, weight, flavour.
--
-- READ FROM CODE (pokeheartgold src/application/pokedex/ov18_021E5C40.c,
-- asm/overlay_18.s):
--   * the list is pages of 15 (`ov18_021F8824`: index = page * 15 + cursor),
--     the count is the dex number of the last seen entry, the last page is
--     (count - 1) / 15 (`ov18_021F891C`, `ov18_021F8950`); the grid's rows
--     carry ten rows from page * 15 (ov18_021E6AEC), so the part-visible
--     fourth and fifth rows already show the next page
--   * cell numbers: ball tile at col 4 + 5j, three digit tiles after it,
--     caught digits / ball vs seen digits (ov18_021E6AEC); x = 32 + 40j,
--     y = 8 + 40i
--   * cursor sprite anim 1 at (48 + 40 col, 24 + 40 row) (ov18_021F2BB0);
--     arrows anims 5/7 (up, at (242,12)) and 8/10 (down, (242,140)), grey at
--     the ends (ov18_021F2C10); the track anim 4 at (242,76); the thumb anim
--     11 + k, k the first `ov18_021FA398` bound >= count, height
--     `ov18_021FA310`[anim + 1], its centre from 21 + h/2 to 131 - h/2 in
--     proportion to the page (ov18_021F2DD4); sprite templates ov18_021FA984
--   * window templates ov18_021F9F3C (left, top in tiles): INFO (2,0), number
--     (15,3), name (19,3), category (13,5) w18, flavour (2,17) 28 x 6, HT
--     (18,11) w5, height (23,11), WT (18,13), weight (23,13); cover SEEN /
--     OBTAINED (2,9) / (18,9), counts (11,11) / (27,11) w3; plate (10,16) w11
--   * picture at (48,72), caught ball (112,32), types (168,72) / +48,
--     footprint (120,80) (templates ov18_021FAB8C / FAB58 / FA41C / FA450)
--   * touch rectangles (asm 23465-23700): cover OPEN x 64-191 / SEARCH 0-63 /
--     QUIT 192-255 at y 152-187, the NATIONAL/JOHTO switch y 112-143 x
--     96-160; list cells y 4-123 x 27-226, arrows / bar x 231-252 (y 5-20,
--     131-146, 21-130), the four buttons 64 px wide at y 152-187; details
--     AREA/SIZE/FORMS/BACK y 168-183
--   * words: bank 802 (0 SEEN, 1 OBTAINED, 8 INFO, 10 HT, 11 WT); flavour
--     803 (HeartGold) / 804 (SoulSilver) (ov18_021E590C.c:9-13); weight 812,
--     height 814, category 816 -- entry 0 of each for an uncaught species
--
-- MEASURED off Bulbapedia's capture (Pokedex_HGSS.png, pixel-sampled) and
-- checked against this screen's own harness render: text colours (88 grey
-- on white with a 176 shadow; the header number/name and the category are
-- 208 ringed by 88, one pixel wider a glyph -- see putOutline; 248 on 104 on
-- the plate), the glyph tops 3 px under each window's top, HT / WT centred
-- in their windows, the height/weight strings (which carry their own leading
-- spaces, 5 px each) starting at x 189, the category right-aligned to x 247,
-- the flavour block centred on 128, icon centres (48 + 40j, 28 + 40i) and
-- the seen-but-not-caught icon drawn half transparent. Guessed: the lid's
-- slide speed, CRY/DETAILS greyed (screen 71) when the cell is unseen, the
-- cover's SEEN/OBTAINED text colour (no capture of the cover was found).
--
-- NOT DONE: SEARCH (state 5), AREA / SIZE / FORMS (states 1-3; DETAILS shows
-- their button bar and BACK only), the foreign-language entries, the confirm
-- dialog, the scroll animation between pages (pages change at once), the
-- cartridge's own sound ids (DP ones stand in).

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")
local Sprites = require("src.pokemon.Sprites")
local Forms = require("src.pokemon.Gen4Forms")

local HgssPokedex = {}
HgssPokedex.__index = HgssPokedex
HgssPokedex.isOpaque = true

local W, H = 256, 192
local floor = math.floor

local TYPE_ID = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6,
  GHOST = 7, STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13,
  PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17 }
-- `ov18_021FA398`: list sizes that pick the thumb (anim 11 + k)
local THUMB_BOUNDS = { 15, 45, 90, 135, 180, 225, 270, 315, 360, 405, 450, 495 }
-- `ov18_021FA310` + 1, by anim
local THUMB_H = {}
for a = 11, 22 do THUMB_H[a] = 110 - 8 * (a - 11) end

local INK = {
  dark = { text = { 88 / 255, 88 / 255, 88 / 255 }, shadow = { 176 / 255, 176 / 255, 176 / 255 } },
  darkLight = { text = { 88 / 255, 88 / 255, 88 / 255 }, shadow = { 208 / 255, 216 / 255, 216 / 255 } },
  header = { text = { 208 / 255, 216 / 255, 216 / 255 }, shadow = { 88 / 255, 88 / 255, 88 / 255 } },
  white = { text = { 248 / 255, 248 / 255, 248 / 255 }, shadow = { 88 / 255, 88 / 255, 88 / 255 } },
  plate = { text = { 248 / 255, 248 / 255, 248 / 255 }, shadow = { 104 / 255, 104 / 255, 104 / 255 } },
}
-- the Font draws a glyph cell from its y; the cartridge's glyphs sit 3 px
-- under the window top (measured: one more for the light-on-dark inks)
local TEXT_DY = { header = 1, white = 1, plate = 1 }

local function inRect(x, y, l, t, r, b) return x >= l and x <= r and y >= t and y <= b end

function HgssPokedex:uiSize() return W, H end
function HgssPokedex:wantsFillScale() return true end
function HgssPokedex:wantsEdgeBleed() return false end

function HgssPokedex.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, HgssPokedex)
  self.game = game
  self.onCancel = opts.onCancel
  self.art = (game.data or {}).gen4_hgss_dex_art or {}
  self.cache = {}
  local dex = (game.save or {}).pokedex or {}
  self.hasNational = dex.national and true or false
  self.mode = (self.hasNational and dex.hgssDexMode == 1) and 1 or 0
  self.state = "cover"
  self.lid = 0
  self.page, self.cursor = 0, 0
  self.t = 0
  self.showTop = false
  self:rebuild()
  return self
end

-- ------------------------------------------------------------------ data --

function HgssPokedex:status(species)
  if not species then return nil end
  local dex = (self.game.save or {}).pokedex or {}
  local id = Forms.species(species)
  local function known(t)
    t = t or {}
    return t[species] or (id and (t[id] or t["SPECIES_" .. id]))
  end
  if known(dex.owned) then return "owned" end
  if known(dex.seen) then return "seen" end
  return nil
end

function HgssPokedex:rebuild()
  local orders = self.art.orders or {}
  local order = orders[self.mode == 1 and "national" or "johto"]
  if not order then
    order = {}
    for id = 1, self.mode == 1 and 493 or 251 do order[id] = id end
  end
  self.order = order
  local count, seen, owned = 0, 0, 0
  for i, sp in ipairs(order) do
    local s = self:status(sp)
    if s then count = i; seen = seen + 1 end
    if s == "owned" then owned = owned + 1 end
  end
  self.count, self.seenCount, self.ownedCount = count, seen, owned
  local last = math.max(0, floor((count - 1) / 15))
  if self.page > last then self.page = last end
  if count > 0 and self:index() > count then self.cursor = (count - 1) % 15 end
end

function HgssPokedex:index() return self.page * 15 + self.cursor + 1 end
function HgssPokedex:lastPage() return math.max(0, floor((self.count - 1) / 15)) end

-- the species at list position i, when it has been seen
function HgssPokedex:entry(i)
  local sp = self.order[i]
  if i > self.count or not sp then return nil, nil end
  local s = self:status(sp)
  if not s then return nil, nil end
  return sp, s
end

function HgssPokedex:text(bank, index)
  local t = ((self.game.data or {}).text or {})[("TEXT_B%04d_%05d"):format(bank, index)]
  if type(t) ~= "string" then return nil end
  return (t:gsub("{[^}]*}", ""))
end

function HgssPokedex:flavourBank()
  local v = ((self.game.data or {}).gen4_version or {}).version
  if v == nil then v = require("src.core.GameVersion").current and require("src.core.GameVersion").current() end
  return tostring(v):lower():find("soul") and 804 or 803
end

-- ------------------------------------------------------------- pictures --

function HgssPokedex:image(path)
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function HgssPokedex:pic(key)
  local rec = self.art[key]
  if type(rec) ~= "table" then return nil, nil end
  return self:image(rec.path), rec
end

function HgssPokedex:bg(key, x, y)
  local img = self:pic(key)
  if img then love.graphics.draw(img, x or 0, y or 0) end
  return img
end

-- an OBJ cell at its sprite position (the cell's own extent added)
function HgssPokedex:obj(key, x, y)
  local img, rec = self:pic(key)
  if img then love.graphics.draw(img, x + (tonumber(rec.originX) or 0), y + (tonumber(rec.originY) or 0)) end
  return img
end

function HgssPokedex:anim(a, x, y)
  local cell = (self.art.listAnims or {})[a]
  if cell then return self:obj("list_" .. cell, x, y) end
end

function HgssPokedex:icon(species, cx, cy, alpha, frame)
  local data = self.game.data or {}
  local icons = data.icons or (data.gen4_species_sprites or {}).icons
  local entry = icons and icons.bySpecies and icons.bySpecies[species]
  local def = (data.pokemon or {})[species]
  entry = entry or (def and def.icon)
  local path, frameH
  if type(entry) == "table" then path, frameH = entry.image, tonumber(entry.frameHeight)
  elseif type(entry) == "string" then path = entry end
  local img = self:image(path)
  if not img then return end
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH or 32, ih)
  local frames = math.max(1, floor(ih / frameH))
  local q = love.graphics.newQuad(0, ((frame or 0) % frames) * frameH, iw, frameH, iw, ih)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(img, q, cx - floor(iw / 2), cy - floor(frameH / 2))
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------------ text --

local function put(ink, s, x, y)
  Font.pushStyle(INK[ink])
  Font.draw(s, x, y + (TEXT_DY[ink] or 0))
  Font.popStyle()
end
local function putRight(ink, s, right, y) put(ink, s, right - Font.width(s), y) end

-- THE OUTLINED WORDS (the header's number and name, the category): the
-- cartridge's glyphs there are ringed on every side by the dark colour and
-- advance one pixel wider (measured: "Tiny Bird Pokemon" 110 px against the
-- plain face's 90). Drawn as the glyph's silhouette in the outline colour up,
-- left and up-left of it, then the two-tone glyph (whose shadow already rings
-- the right and bottom), one pixel of extra advance per character.
local function chars(s)
  local out = {}
  for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end
local function outlineWidth(s)
  local w = 0
  for _, ch in ipairs(chars(s)) do w = w + Font.width(ch) + 1 end
  return w
end
local function putOutline(fill, line, s, x, y)
  y = y + 1
  local pen = x
  for _, ch in ipairs(chars(s)) do
    Font.pushStyle({ text = line })
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { -1, -1 } }) do Font.draw(ch, pen + d[1], y + d[2]) end
    Font.popStyle()
    Font.pushStyle({ text = fill, shadow = line })
    Font.draw(ch, pen, y)
    Font.popStyle()
    pen = pen + Font.width(ch) + 1
  end
end
local OUTLINE_FILL, OUTLINE_LINE = { 208 / 255, 216 / 255, 216 / 255 }, { 88 / 255, 88 / 255, 88 / 255 }
local function putCentre(ink, s, l, r, y) put(ink, s, l + floor((r - l - Font.width(s)) / 2), y) end

-- ----------------------------------------------------------------- sound --

function HgssPokedex:se(name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

function HgssPokedex:cry()
  local sp = self:entry(self:index())
  if not sp then return end
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playCry then
    if self.cryHandle and self.cryHandle.stop then pcall(self.cryHandle.stop, self.cryHandle) end
    local okC, h = pcall(Sound.playCry, self.game.data, sp, { isolated = true })
    self.cryHandle = okC and h or nil
  end
end

-- ----------------------------------------------------------------- input --

function HgssPokedex:close()
  if self.cryHandle and self.cryHandle.stop then pcall(self.cryHandle.stop, self.cryHandle) end
  self:se("SEQ_SE_DP_DECIDE")
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function HgssPokedex:open()
  if self.state ~= "cover" then return end
  self:se("SEQ_SE_DP_DECIDE")
  self.state = "opening"
end

function HgssPokedex:shut()
  self:se("SEQ_SE_DP_DECIDE")
  self.state = "closing"
end

function HgssPokedex:toggleMode()
  if not self.hasNational then return end
  self.mode = 1 - self.mode
  local dex = (self.game.save or {}).pokedex
  if dex then dex.hgssDexMode = self.mode end
  self.page, self.cursor = 0, 0
  self:rebuild()
  self:se("SEQ_SE_DP_SELECT")
end

function HgssPokedex:select(page, cursor)
  if self.count == 0 then return end
  local last = self:lastPage()
  page = math.max(0, math.min(last, page))
  local maxIndex = self.count - page * 15
  cursor = math.max(0, math.min(14, math.min(maxIndex - 1, cursor)))
  if page ~= self.page or cursor ~= self.cursor then
    self.page, self.cursor = page, cursor
    self:se("SEQ_SE_DP_SELECT")
  end
end

function HgssPokedex:move(dx, dy)
  local col, row = self.cursor % 5, floor(self.cursor / 5)
  local page = self.page
  col = col + dx
  if col < 0 then col = 4; row = row - 1 elseif col > 4 then col = 0; row = row + 1 end
  row = row + dy
  if row < 0 then
    if page == 0 then return end
    page, row = page - 1, 2
  elseif row > 2 then
    if page >= self:lastPage() then return end
    page, row = page + 1, 0
  end
  self:select(page, row * 5 + col)
end

function HgssPokedex:tapCover(x, y)
  if y >= 152 and y <= 187 then
    if x <= 63 then return self:se("SEQ_SE_DP_SELECT") end -- SEARCH: not done
    if x <= 191 then return self:open() end
    return self:close()
  end
  if self.hasNational and inRect(x, y, 96, 112, 160, 143) then return self:toggleMode() end
  if y < 152 then return self:open() end
end

function HgssPokedex:tapList(x, y)
  if self.details then
    if y >= 168 and y <= 183 and x >= 199 and x <= 249 then self.details = false; return self:se("SEQ_SE_DP_DECIDE") end
    return
  end
  if y >= 152 and y <= 187 then
    local b = floor(x / 64)
    if b == 1 then return self:cry()
    elseif b == 2 then if self:entry(self:index()) then self.details = true; self:se("SEQ_SE_DP_DECIDE") end; return
    elseif b == 3 then return self:close() end
    return
  end
  if x < 24 and y < 152 then return self:shut() end
  if inRect(x, y, 27, 4, 226, 123) then
    local col, row = math.min(4, floor((x - 28) / 40)), math.min(2, floor((y - 4) / 40))
    return self:select(self.page, row * 5 + math.max(0, col))
  end
  if x >= 231 and x <= 252 then
    if y >= 5 and y <= 20 then return self:select(self.page - 1, self.cursor) end
    if y >= 131 and y <= 146 then return self:select(self.page + 1, self.cursor) end
    if y >= 21 and y <= 130 then
      local last = self:lastPage()
      return self:select(floor((y - 21) / 110 * (last + 1)), self.cursor)
    end
  end
end

function HgssPokedex:bottomOnSecond()
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

function HgssPokedex:touchpressed(id, px, py)
  local x, y
  if self:bottomOnSecond() then
    x, y = SecondScreen.toLocal(self.game, px, py)
  elseif not self.showTop then
    local rect = require("src.render.Renderer").uiPresentation
    x, y = px, py
    if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
  end
  if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
  self.tapAt = { x = floor(x), y = floor(y) }
  return true
end
function HgssPokedex:touchmoved() return false end
function HgssPokedex:touchreleased() return false end

function HgssPokedex:update(dt)
  self.t = self.t + 1
  if self.state == "opening" then
    self.lid = math.min(256, self.lid + 32)
    if self.lid >= 256 then self.state = "list" end
    return
  elseif self.state == "closing" then
    self.lid = math.max(0, self.lid - 32)
    if self.lid <= 0 then self.state = "cover"; self.details = false end
    return
  end
  local tap = self.tapAt
  self.tapAt = nil
  if tap then
    if self.state == "cover" then return self:tapCover(tap.x, tap.y) end
    return self:tapList(tap.x, tap.y)
  end
  local input = self.game.input
  if not input then return end
  local function pressed(k) return input:wasPressed(k) end
  if pressed("select") then self.showTop = not self.showTop; return end
  if self.state == "cover" then
    if pressed("a") then self:open()
    elseif pressed("b") then self:close()
    elseif pressed("left") or pressed("right") then self:toggleMode() end
    return
  end
  if self.details then
    if pressed("b") then self.details = false; self:se("SEQ_SE_DP_DECIDE") end
    return
  end
  if pressed("up") then self:move(0, -1)
  elseif pressed("down") then self:move(0, 1)
  elseif pressed("left") then self:move(-1, 0)
  elseif pressed("right") then self:move(1, 0)
  elseif pressed("x") then self:cry()
  elseif pressed("a") then
    if self:entry(self:index()) then self.details = true; self:se("SEQ_SE_DP_DECIDE") end
  elseif pressed("b") then self:close()
  end
end

-- ------------------------------------------------------------------ draw --

function HgssPokedex:drawDigits(n, x, y, caught)
  local img = self:pic("digits")
  if not img then return end
  local iw, ih = img:getDimensions()
  if caught then
    love.graphics.draw(img, love.graphics.newQuad(0, 0, 8, 8, iw, ih), x - 8, y)
  end
  local s = ("%03d"):format(n % 1000)
  for k = 1, 3 do
    local d = tonumber(s:sub(k, k))
    local src = (caught and 1 or 11) + d
    love.graphics.draw(img, love.graphics.newQuad(src * 8, 0, 8, 8, iw, ih), x + (k - 1) * 8, y)
  end
end

function HgssPokedex:number(i)
  if self.mode == 1 then return self.order[i] or i end
  return i
end

function HgssPokedex:drawList()
  local g = love.graphics
  -- BG3: ten rows of cells from page * 15; five fit on the screen
  local first = self.page * 15
  for r = 0, 4 do
    local y = 40 * r
    self:bg("grid", 0, y)
    for j = 0, 4 do
      local i = first + r * 5 + j + 1
      if i <= self.count then
        local _, s = self:entry(i)
        self:drawDigits(self:number(i), 40 + 40 * j, y + 8, s == "owned")
      end
    end
  end
  -- the icons (OBJ)
  for r = 0, 3 do
    for j = 0, 4 do
      local i = first + r * 5 + j + 1
      local sp, s = self:entry(i)
      if sp then
        local selected = (r * 5 + j) == self.cursor
        self:icon(sp, 48 + 40 * j, 28 + 40 * r, s == "owned" and 1 or 0.5,
                  selected and floor(self.t / 8) or 0)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
  if self.count > 0 then
    self:anim(1, 48 + 40 * (self.cursor % 5), 24 + 40 * floor(self.cursor / 5))
  end
  -- the scroll bar
  local last = self:lastPage()
  self:anim(4, 242, 76)
  self:anim(self.page == 0 and 7 or 5, 242, 12)
  self:anim(self.page >= last and 10 or 8, 242, 140)
  local k = #THUMB_BOUNDS - 1
  for n, bound in ipairs(THUMB_BOUNDS) do if self.count <= bound then k = n - 1; break end end
  local a = 11 + k
  local h = THUMB_H[a] or 22
  local lo, hi = 21 + floor(h / 2), 131 - floor(h / 2)
  local ty = (last > 0) and (lo + floor((hi - lo) * self.page / last)) or lo
  self:anim(a, 242, ty)
end

-- BG2: the name plate and the button bar (over the lid's BG0)
function HgssPokedex:drawListFront()
  self:bg("plate", 0, 120)
  local sp = self:entry(self:index())
  local def = sp and ((self.game.data or {}).pokemon or {})[sp]
  if def and def.name then putCentre("plate", def.name, 80, 168, 128) end
  if self.details then self:bg("bar_details", 0, 160)
  else self:bg(sp and "bar_list" or "bar_list2", 0, 152) end
end

function HgssPokedex:drawCover(x)
  local key = "cover_" .. self.mode .. (self.hasNational and "" or "_lock")
  self:bg(key, x, 0)
  put("white", self:text(802, 0) or "SEEN", x + 16, 72)
  put("white", self:text(802, 1) or "OBTAINED", x + 144, 72)
  putCentre("white", tostring(self.seenCount), x + 88, x + 112, 88)
  putCentre("white", tostring(self.ownedCount), x + 216, x + 240, 88)
end

function HgssPokedex:drawTouch()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", 0, 0, W, H)
  if self.state ~= "cover" then self:drawList() end
  -- BG0, the lid and its edge, slides left over the list...
  if self.state ~= "list" then self:drawCover(-self.lid) end
  self:bg("edge", 256 - self.lid, 0)
  -- ...under BG2's bars
  if self.state == "list" then self:drawListFront()
  else self:bg("bar_cover", 0, 152) end
end

function HgssPokedex:drawTop()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if self.state == "cover" or self.state == "opening" then
    g.setColor(0, 0, 0, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1)
    self:bg("top_cover")
    return
  end
  local i = self:index()
  if self.count == 0 or i > self.count then self:bg("top_blank"); return end
  self:bg("top_entry")
  put("header", self:text(802, 8) or "INFO", 16, 0)
  local sp, s = self:entry(i)
  local caught = s == "owned"
  putOutline(OUTLINE_FILL, OUTLINE_LINE, ("%03d"):format(self:number(i) % 1000), 122, 24)
  if not sp then
    self:obj("unknown_pic", 48, 72)
    return
  end
  local data = self.game.data or {}
  local def = (data.pokemon or {})[sp] or {}
  putOutline(OUTLINE_FILL, OUTLINE_LINE, def.name or "?", 153, 24)
  if caught then self:obj("caught_ball", 112, 32) end
  -- the picture, centred on its sprite position
  local path = Sprites.path(data, sp, "front", { kind = "dex" })
  local img = path and self:image(path)
  if img then
    local iw, ih = img:getDimensions()
    g.draw(img, 48 - floor(iw / 2), 72 - floor(ih / 2))
  else
    self:obj("unknown_pic", 48, 72)
  end
  local textId = caught and sp or 0
  local category = self:text(816, textId) or ""
  putOutline(OUTLINE_FILL, OUTLINE_LINE, category, 247 - outlineWidth(category), 40)
  putCentre("dark", self:text(802, 10) or "HT", 144, 184, 88)
  putCentre("dark", self:text(802, 11) or "WT", 144, 184, 104)
  local function value(s, y)
    s = s or ""
    local lead = s:match("^( *)") or ""
    put("dark", s:sub(#lead + 1), 189 + #lead * 5, y)
  end
  value(self:text(814, textId), 88)
  value(self:text(812, textId), 104)
  if not caught then return end
  local types = (Forms.definition(data, { species = sp, form = 0 }) or def).types or def.types or {}
  for k = 1, 2 do
    local t = types[k] and TYPE_ID[tostring(types[k]):upper()]
    if t and (k == 1 or types[2] ~= types[1]) then self:obj("type_" .. t, 168 + (k - 1) * 48, 72) end
  end
  self:obj(("foot_%03d"):format(Forms.species(sp) or sp), 120, 80)
  local entry = self:text(self:flavourBank(), Forms.species(sp) or sp) or def.dexEntry or ""
  local lines, width = {}, 0
  for line in (entry .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
    width = math.max(width, Font.width(line))
  end
  local x = math.max(16, 128 - floor(width / 2))
  for k = 1, math.min(3, #lines) do put("dark", lines[k], x, 136 + (k - 1) * 16) end
end

function HgssPokedex:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self:bottomOnSecond() then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawTouch() end)
  elseif self.showTop then
    self:drawTop()
  else
    self:drawTouch()
  end
  g.setColor(1, 1, 1, 1)
end

return HgssPokedex
