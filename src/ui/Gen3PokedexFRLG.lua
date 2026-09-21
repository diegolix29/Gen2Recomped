-- FireRed's POKeDEX (pokefirered src/pokedex_screen.c): the numerical-order
-- list and the entry page, including the page the battle opens when a new
-- species is registered.
--
-- Everything drawn comes out of constants.gen3FRLGPokedex
-- (RomExtractorGen3:extractFireRedPokedex); every position below is the
-- window template or print call named beside it.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Sound = require("src.core.Sound")

local Dex = {}
Dex.__index = Dex
Dex.isOpaque = true

local W, H = 240, 160
local ROWS = 9          -- sListMenuTemplate_OrderedListMenu.maxShowed
-- THE ROW PITCH IS THE FONT'S OWN HEIGHT, and it is not 16.
--
-- Every list on this screen shows nine rows (maxShowed = 9) inside a window
-- sixteen tiles tall, and the ListMenu prints row i at
-- upText_Y + i * (maxLetterHeight + itemVerticalPadding) -- upText_Y is 2
-- and the padding is 0, so nine rows and their last glyph have to fit in
-- 128 pixels: 2 + 9h <= 128, which pins h at 14.  At 16 the ninth row
-- started at 146 and ran off the bottom of the screen, through the control
-- bar.
local ROW_H = 14
local KANTO_COUNT = 151

function Dex:uiSize() return W, H end
function Dex:wantsFillScale() return true end
function Dex:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, 29, 19) }
end

function Dex.record(game)
  local r = ((game and game.data and game.data.constants) or {}).gen3FRLGPokedex
  return type(r) == "table" and type(r.images) == "table" and r.images.kanto_field and r or nil
end

local function listing(game)
  local national = game.save and game.save.nationalDex
  local out, last = {}, 0
  for id, def in pairs(game.data.pokemon or {}) do
    local n = tonumber(def.dex)
    if n and n >= 1 and (national or n <= KANTO_COUNT) then
      out[n] = id
      if n > last then last = n end
    end
  end
  return out, last
end

local function base(game, opts)
  local self = setmetatable({ game = game, opts = opts or {} }, Dex)
  self.rec = Dex.record(game)
  self.prefix = (game.save and game.save.nationalDex) and "national_" or "kanto_"
  self.cache = {}
  return self
end

-- THE SIX ORDERS THE MODE MENU OFFERS (pokedex_screen.h DEX_ORDER_*), and
-- what each one lists.
--
-- The two NUMERICAL orders are the whole run of dex numbers, gaps included --
-- an unseen number is a row of dashes, which is what makes the list read as
-- a dex rather than a collection.  The other three are SEARCHES: the
-- cartridge only ever sorts what you have met, so a species you have not
-- seen is not in them at all.
local ORDER = { NUMERICAL_KANTO = 0, ATOZ = 1, TYPE = 2,
                LIGHTEST = 3, SMALLEST = 4, NUMERICAL_NATIONAL = 5 }

local function seenRows(game, national)
  local dex = (game.save or {}).pokedex or {}
  local rows = {}
  for id, def in pairs(game.data.pokemon or {}) do
    local n = tonumber(def.dex)
    if n and n >= 1 and (national or n <= KANTO_COUNT)
       and (dex.seen or {})[id] then
      rows[#rows + 1] = { n = n, id = id, def = def }
    end
  end
  return rows
end

function Dex:buildRows(order, filter)
  local national = (self.game.save and self.game.save.nationalDex) and true or false
  if order == ORDER.NUMERICAL_KANTO or order == ORDER.NUMERICAL_NATIONAL
     or order == nil then
    local wide = order == ORDER.NUMERICAL_NATIONAL
                 or (order == nil and national)
    local list, count = listing(self.game)
    if not wide then count = math.min(count, KANTO_COUNT) end
    local rows = {}
    for n = 1, count do rows[n] = { n = n, id = list[n] } end
    return rows
  end
  local rows = seenRows(self.game, national)
  if order == ORDER.TYPE and filter then
    local kept = {}
    for _, row in ipairs(rows) do
      local def = row.def or {}
      local t1 = def.type1 or (def.types and def.types[1])
      local t2 = def.type2 or (def.types and def.types[2])
      if tostring(t1):upper() == filter or tostring(t2):upper() == filter then
        kept[#kept + 1] = row
      end
    end
    rows = kept
  end
  local function key(row)
    local def = row.def or {}
    if order == ORDER.ATOZ then return tostring(def.name or row.id):upper() end
    if order == ORDER.LIGHTEST then return tonumber(def.weight) or math.huge end
    if order == ORDER.SMALLEST then return tonumber(def.height) or math.huge end
    return row.n
  end
  table.sort(rows, function(a, b)
    local ka, kb = key(a), key(b)
    if ka ~= kb then return ka < kb end
    return a.n < b.n
  end)
  return rows
end

-- open the list in one of the orders, with the cursor on the first row that
-- has anything to show
function Dex:openList(order, filter)
  self.order = order
  self.filter = filter
  self.rows = self:buildRows(order, filter)
  self.count = #self.rows
  self.index, self.scroll = 1, 0
  local dex = (self.game.save or {}).pokedex or {}
  for n = 1, self.count do
    local id = self.rows[n] and self.rows[n].id
    if id and (dex.seen or {})[id] then self.index = n break end
  end
  self:clampScroll()
  self.mode = "list"
end

-- the mode rows this save sees: the National list once it is earned
function Dex:modeRows()
  local m = self.rec and self.rec.modes
  if type(m) ~= "table" then return nil end
  local national = (self.game.save and self.game.save.nationalDex) and true or false
  local rows = (national and m.national) or m.kanto
  return type(rows) == "table" and #rows > 0 and rows or nil
end

function Dex.new(game, opts)
  local self = base(game, opts)
  self.onCancel = self.opts.onCancel
  -- THE FRONT PAGE, when the cache carries it.
  --
  -- FireRed's dex does not open on the numerical list; it opens on the mode
  -- menu and the list is its first row.  A cache imported before that menu
  -- was extracted has no rows to draw, so it opens where it always did.
  self:openList(nil)
  if self:modeRows() then
    self.mode = "top"
    self.topIndex = self:firstMode(1)
    self.topScroll = 0
    self:clampTop()
  end
  return self
end

local TOP_ROWS = 9      -- sListMenuTemplate_KantoDexModeSelect.maxShowed

-- headings are not landing places: the cursor steps over them
function Dex:firstMode(from, step)
  local rows = self:modeRows() or {}
  step = step or 1
  local i = from
  for _ = 1, #rows do
    if i < 1 then i = #rows elseif i > #rows then i = 1 end
    if rows[i] and rows[i].kind ~= "header" then return i end
    i = i + step
  end
  return from
end

function Dex:clampTop()
  local rows = self:modeRows() or {}
  if self.topIndex <= self.topScroll then self.topScroll = self.topIndex - 1 end
  if self.topIndex > self.topScroll + TOP_ROWS then
    self.topScroll = self.topIndex - TOP_ROWS
  end
  self.topScroll = math.max(0, math.min(self.topScroll,
                                        math.max(0, #rows - TOP_ROWS)))
end

-- the page a battle opens for a newly caught species (Task_DexScreen_RegisterMonToPokedex)
function Dex.newEntry(game, species, registered)
  local self = base(game, {})
  self.mode = "entry"
  self.registered = registered
  self.species = species
  self:openEntry(species)
  return self
end

function Dex:img(key)
  local rec = self.rec.images[key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
  end
  return self.cache[path] or nil, rec
end

-- the pale pair a locked habitat is printed in
function Dex:dimColors()
  local c = (self.rec.colors or {})[self.prefix]
            or (self.rec.colors or {}).kanto_ or {}
  local function norm(t, d) t = t or d return { t[1] / 255, t[2] / 255, t[3] / 255, 1 } end
  return norm(c.dimInk, { 232, 232, 224 }), norm(c.dimShadow, { 208, 208, 208 })
end

function Dex:colors()
  local c = (self.rec.colors or {})[self.prefix] or (self.rec.colors or {}).kanto_ or {}
  local function norm(t, d) t = t or d return { t[1] / 255, t[2] / 255, t[3] / 255, 1 } end
  return norm(c.ink, { 74, 74, 74 }), norm(c.shadow, { 206, 206, 206 }),
         norm(c.barInk, { 255, 255, 255 }), norm(c.barShadow, { 90, 90, 90 })
end

local function text(s, x, y, ink, shadow, small)
  local pushed = small and Font.hasFace and Font.hasFace("small")
  if pushed then Font.pushFace("small") end
  local two = Font.beginTwoTone(ink, shadow)
  if not two then love.graphics.setColor(ink) end
  Font.draw(s, x, y)
  if two then Font.endTwoTone() end
  if pushed then Font.popFace() end
  love.graphics.setColor(1, 1, 1, 1)
end

-- "No" AND THE DIGITS ARE TWO PRINTS, NOT ONE STRING.
--
-- DexScreen_PrintMonDexNo puts gText_PokedexNo at x and then the three
-- zero-padded digits at x + 9, every time it is called -- the entry page,
-- the list and a habitat page all go through it.  Printing "No000" as one
-- run instead lets the digits start wherever the two letters happen to end,
-- which is not nine pixels on this font, so every number on the screen sat
-- a little off from where the cartridge puts it.
local function dexNo(x, y, n, ink, shadow)
  text("No", x, y, ink, shadow, true)
  text(("%03d"):format(tonumber(n) or 0), x + 9, y, ink, shadow, true)
end

local function smallWidth(s)
  local pushed = Font.hasFace and Font.hasFace("small")
  if pushed then Font.pushFace("small") end
  local w = Font.width(s)
  if pushed then Font.popFace() end
  return w
end

function Dex:clampScroll()
  if self.index < 1 then self.index = 1 end
  if self.index > self.count then self.index = self.count end
  if self.index <= self.scroll then self.scroll = self.index - 1 end
  if self.index > self.scroll + ROWS then self.scroll = self.index - ROWS end
  self.scroll = math.max(0, math.min(self.scroll, math.max(0, self.count - ROWS)))
end

function Dex:openEntry(species)
  self.mode = "entry"
  self.species = species
  self.def = (self.game.data.pokemon or {})[species]
  self.pic = nil
  local ok, path = pcall(require("src.pokemon.Sprites").path, self.game.data, species, "front", { kind = "dex" })
  if ok and path then
    local okImg, image = pcall(love.graphics.newImage, path)
    self.pic = okImg and image or nil
  end
  pcall(Sound.playCry, self.game.data, species)
end

-- THE AREA PAGE, which this dex did not have -- and which the cartridge
-- builds as ONE page carrying both AREA and SIZE.
--
-- Reported from play: "the pokedex is also missing some stuff like the area
-- to find pokemon in etc ensure it matchs the rom".  It was missing because
-- this screen had no second page at all: A played the cry and B left.
--
-- DexScreen_DrawMonAreaPage is explicit about what the second page is, and
-- every number below is one of its window templates or print calls:
--   the party icon at (8,16), the number and name at (40,16), the two type
--   badges at (40,40), SIZE centred over 80px at (16,56) with the Pokemon
--   and the trainer posed beneath it at (40,104) and (80,104), AREA centred
--   over 80px at (144,16) and the 96x72 Kanto picture at (136,32) -- both of
--   those last two pushed down by voff, which is 4 tiles until an island map
--   needs the room.  The bar is the cartridge's own: the cry on the left,
--   {A}CANCEL {B}PREVIOUS DATA on the right.
--
-- The places themselves are markers, not tinted cells: pokedex_area_markers
-- lays one subsprite per DEX_AREA over the map at a position sAreaMarkers
-- keeps for it, and wild_pokemon_area turns a MAPSEC into that DEX_AREA.
-- Both tables are ripped now, so a marker lands where the cartridge puts it
-- rather than where a projection would guess.
--
-- A species with nowhere to find it gets the cartridge's own answer, printed
-- across the map where it prints it: AREA UNKNOWN, centred over 96px at 29.
local function areaRecord(self)
  local a = self.rec and self.rec.area
  if type(a) ~= "table" or type(a.layout) ~= "table" then return nil end
  return a
end

-- GetUnlockedSeviiAreas, as the two flags the town map already reads
function Dex:seviiUnlocked()
  local flags = (self.game.save or {}).flags or {}
  if flags["FLAG_G3_0846"] then return 7 end
  if flags["FLAG_G3_0845"] then return 3 end
  return 0
end

function Dex:areaVoff()
  -- the Kanto map goes flush with the top only once an island map below it
  -- needs the room (islands 4-7)
  return (self:seviiUnlocked() > 3) and 0 or ((areaRecord(self) or {}).layout or {}).voff or 4
end

function Dex:openArea()
  if not areaRecord(self) then return end
  self.mode = "area"
  self.areaMarkers = self:areaMarkersFor(self.species)
end

-- every marker this species earns: its habitat sections, each turned into a
-- DEX_AREA by the cartridge's own MAPSEC table, then into a shape and a
-- place by sAreaMarkers
function Dex:areaMarkersFor(species)
  local a = areaRecord(self)
  if not a then return {} end
  local ok, Gen3RegionMap = pcall(require, "src.ui.Gen3RegionMap")
  if not ok then return {} end
  local sections = Gen3RegionMap.habitat(self.game, species)
  local isles = self:seviiUnlocked()
  local out = {}
  for sec in pairs(sections or {}) do
    local dexArea = (a.kanto or {})[sec]
    if not dexArea then
      for j = 1, 7 do
        if math.floor(isles / 2 ^ (j - 1)) % 2 == 1 then
          dexArea = dexArea or ((a.sevii or {})[j] or {})[sec]
        end
      end
    end
    local marker = dexArea and (a.markers or {})[dexArea]
    if marker then out[#out + 1] = marker end
  end
  return out
end

function Dex:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- WHERE EACH SLOT GOES (sPageIconCoords_1Mon .. _4Mons), in tiles: the
-- circular window that holds the picture, then the rectangular one that
-- holds the number and the name.  The layout is different for every page
-- SIZE -- one mon sits centred, four sit in a ring -- which is why the table
-- is indexed by how many are on the page before it is indexed by the slot.
local CAT_COORDS = {
  [1] = { { 11, 3, 11, 11 } },
  [2] = { { 3, 3, 11, 3 }, { 18, 9, 10, 11 } },
  [3] = { { 1, 2, 9, 2 }, { 11, 9, 3, 11 }, { 21, 3, 21, 11 } },
  [4] = { { 0, 2, 6, 3 }, { 7, 10, 0, 12 }, { 15, 10, 22, 11 }, { 22, 2, 15, 4 } },
}

-- A PAGE SHOWS WHAT YOU HAVE SEEN, AND NOTHING ELSE.
--
-- DexScreen_CreateCategoryPageSpeciesList walks the page's four slots and
-- keeps only the species the save has seen, packing them from slot 0 -- so an
-- unseen Pokemon is not a row of dashes here, it is simply not on the page,
-- and a page with nothing seen on it is locked and never turned to at all
-- (DexScreen_IsPageUnlocked).  Listing the locked ones would hand the player
-- a habitat full of blanks and a page count that does not match what they can
-- reach.
function Dex:categoryPages(index)
  local cats = (self.rec or {}).categories
  local cat = type(cats) == "table" and cats[index]
  if type(cat) ~= "table" or type(cat.pages) ~= "table" then return nil end
  local dex = (self.game.save or {}).pokedex or {}
  local mons = self.game.data.pokemon or {}
  local pages = {}
  for _, page in ipairs(cat.pages) do
    local seen = {}
    for _, id in ipairs(page) do
      if mons[id] and (dex.seen or {})[id] then seen[#seen + 1] = id end
    end
    if #seen > 0 then pages[#pages + 1] = seen end
  end
  return cat, pages
end

-- asked once per row per frame while the menu is up, so the answer is kept:
-- it can only change when the dex does, and the dex does not change while
-- the player is looking at this screen
function Dex:categoryUnlocked(index)
  self.unlocked = self.unlocked or {}
  if self.unlocked[index] == nil then
    local _, pages = self:categoryPages(index)
    self.unlocked[index] = (pages ~= nil and #pages > 0)
  end
  return self.unlocked[index]
end

-- open a habitat: the cartridge pages it four at a time and never scrolls
function Dex:openCategory(index)
  local cat, pages = self:categoryPages(index)
  if not (cat and pages and #pages > 0) then return end
  self.cat = cat
  self.catPages = pages
  self.catPage = 1
  self.catIndex = 1
  self.mode = "category"
end

function Dex:update()
  local input = self.game.input
  -- ---- the front page ------------------------------------------------
  if self.mode == "top" then
    local rows = self:modeRows()
    if not rows then self.mode = "list" return end
    if input:wasPressed("down") then
      self.topIndex = self:firstMode(self.topIndex + 1, 1)
      self:clampTop()
    elseif input:wasPressed("up") then
      self.topIndex = self:firstMode(self.topIndex - 1, -1)
      self:clampTop()
    elseif input:wasPressed("a") then
      local row = rows[self.topIndex]
      if row then
        if row.kind == "close" then return self:close()
        elseif row.kind == "category" then
          -- a habitat with nothing seen in it is not a place you can go
          if self:categoryUnlocked(row.category) then
            self:openCategory(row.category)
          end
        elseif row.kind == "order" then
          -- TYPE MODE asks WHICH type first, the way the cartridge does
          if row.order == ORDER.TYPE then
            local seen = {}
            for _, r in ipairs(seenRows(self.game,
                (self.game.save or {}).nationalDex)) do
              local def = r.def or {}
              for _, ty in ipairs({ def.type1 or (def.types and def.types[1]),
                                    def.type2 or (def.types and def.types[2]) }) do
                if ty then seen[tostring(ty):upper()] = true end
              end
            end
            local names = {}
            for ty in pairs(seen) do names[#names + 1] = ty end
            table.sort(names)
            local items = {}
            for _, ty in ipairs(names) do
              items[#items + 1] = { label = ty, onSelect = function()
                self:openList(ORDER.TYPE, ty)
              end }
            end
            if #items > 0 then
              local Menu = require("src.ui.Menu")
              self.game.stack:push(Menu.new(self.game, items,
                { tx = 1, ty = 1, maxVisible = 8 }))
            end
          else
            self:openList(row.order)
          end
        end
      end
    elseif input:wasPressed("b") then
      return self:close()
    end
    return
  end
  -- ---- a habitat's pages ---------------------------------------------
  if self.mode == "category" then
    local pages = self.catPages or {}
    local page = pages[self.catPage]
    local n = page and #page or 0
    if input:wasPressed("b") then
      self.mode = "top"
    elseif input:wasPressed("right") and #pages > 0 then
      self.catPage = (self.catPage % #pages) + 1
      self.catIndex = 1
    elseif input:wasPressed("left") and #pages > 0 then
      self.catPage = ((self.catPage - 2) % #pages) + 1
      self.catIndex = 1
    elseif input:wasPressed("down") and n > 0 then
      self.catIndex = (self.catIndex % n) + 1
    elseif input:wasPressed("up") and n > 0 then
      self.catIndex = ((self.catIndex - 2) % n) + 1
    elseif input:wasPressed("a") and page then
      local id = page[self.catIndex]
      if id then self:openEntry(id) end
    end
    return
  end
  -- THE SECOND PAGE'S OWN CONTROLS, which are not the first page's.
  -- Task_DexScreen_ShowMonPage prints {A}CANCEL {B}PREVIOUS DATA here: A
  -- leaves the entry outright and B goes back a page.
  if self.mode == "area" then
    if input:wasPressed("start") then
      pcall(Sound.playCry, self.game.data, self.species)
    elseif input:wasPressed("a") then
      if self.registered or not self.rows then
        return self.game.stack:pop()
      end
      self.mode = "list"
    elseif input:wasPressed("b") then
      self.mode = "entry"
    end
    return
  end
  if self.mode == "entry" then
    if self.registered then
      if input:wasPressed("a") or input:wasPressed("b") then self.game.stack:pop() end
      return
    end
    -- {START}CRY, {A}NEXT DATA, {B}CANCEL -- the three the cartridge prints
    -- on this page, and nothing else
    if input:wasPressed("start") then
      pcall(Sound.playCry, self.game.data, self.species)
    elseif input:wasPressed("a") then
      self:openArea()
    elseif input:wasPressed("b") then
      -- THE PAGE A BATTLE OPENED HAS NO LIST BEHIND IT.  Dex.newEntry builds
      -- the entry on its own, so there is nothing to fall back to and
      -- falling back anyway drew a list with no rows in it.
      if not self.rows then return self.game.stack:pop() end
      self.mode = self:modeRows() and "top" or "list"
    end
    return
  end
  local moved = false
  if input:wasPressed("down") then self.index = self.index + 1 moved = true
  elseif input:wasPressed("up") then self.index = self.index - 1 moved = true
  elseif input:wasPressed("right") then self.index = self.index + ROWS moved = true
  elseif input:wasPressed("left") then self.index = self.index - ROWS moved = true
  elseif input:wasPressed("a") then
    local row = self.rows[self.index]
    local id = row and row.id
    local dex = self.game.save.pokedex or {}
    if id and (dex.seen or {})[id] then self:openEntry(id) end
  elseif input:wasPressed("b") then
    -- B goes back to the front page when there is one to go back to
    if self:modeRows() then self.mode = "top" return end
    return self:close()
  end
  if moved then self:clampScroll() end
end

function Dex:owned(id)
  local dex = self.game.save and self.game.save.pokedex or {}
  return self.registered or ((dex.owned or {})[id] and true or false)
end

-- The control strings open each word with a keypad glyph ({A_BUTTON} and
-- friends) the text reader drops, so the hints are drawn as small button
-- icons beside the words, right-aligned at x 236 (DexScreen_PrintControlInfo).
function Dex:drawBars(title, controls, cryHint)
  local g = love.graphics
  -- THE TWO BARS ARE A FLAT WASH, not a picture.
  --
  -- sWindowTemplates[0] and [1] are 30x2 windows filled with
  -- PIXEL_FILL(15) out of palette bank 15 and then written into; the cache
  -- carries that colour beside the bar's own ink.  Drawing it here rather
  -- than leaning on the ripped image means a bar that is the cartridge's
  -- colour even when the picture did not load -- and the picture was the
  -- part that was wrong, drawn from a tile instead of the wash.
  local wash = ((self.rec.colors or {})[self.prefix]
                or (self.rec.colors or {}).kanto_ or {}).bar
  if wash then
    g.setColor(wash[1] / 255, wash[2] / 255, wash[3] / 255, 1)
    g.rectangle("fill", 0, 0, W, 16)
    g.rectangle("fill", 0, 18 * 8, W, 16)
    g.setColor(1, 1, 1, 1)
  else
    local bars = self:img(self.prefix .. "bars")
    if bars then g.draw(bars, 0, 0) end
  end
  local _, _, barInk, barShadow = self:colors()
  if title then text(title, math.floor((W - Font.width(title)) / 2), 2, barInk, barShadow) end
  local y = 18 * 8 + 2
  if controls then
    local width = 0
    for _, p in ipairs(controls) do width = width + 12 + Font.width(p[2]) + 6 end
    local x = 236 - width + 6
    for _, p in ipairs(controls) do
      g.setColor(barInk)
      g.rectangle("line", x + 0.5, y + 2.5, 10, 9, 3, 3)
      text(p[1], x + 2, y, barInk, barShadow)
      x = x + 12
      text(p[2], x, y, barInk, barShadow)
      x = x + Font.width(p[2]) + 6
    end
  end
  if cryHint then text(cryHint, 8, y, barInk, barShadow) end
end

-- the two type badges, off the summary screen's own icon sheet
-- (BlitMenuInfoIcon, sMenuInfoIcons)
function Dex:drawTypes(id, x, y)
  local sum = (self.game.data.constants or {}).gen3FRLGSummary
  local sheetPath = sum and sum.images and sum.images.menu_info
  if not sheetPath then return end
  local okS, sheet = pcall(Assets.image, sheetPath)
  if not (okS and sheet) then return end
  local def = (self.game.data.pokemon or {})[id] or {}
  local t1 = def.type1 or (def.types and def.types[1])
  local t2 = def.type2 or (def.types and def.types[2])
  local iw, ih = sheet:getDimensions()
  for k, tname in ipairs({ t1, (t2 ~= t1) and t2 or nil }) do
    local off = tname and (sum.typeIcons or {})[tostring(tname):upper()]
    if off then
      love.graphics.draw(sheet,
        love.graphics.newQuad((off % 16) * 8, math.floor(off / 16) * 8, 32, 12, iw, ih),
        x + (k == 1 and 0 or 32), y)
    end
  end
end

function Dex:drawList()
  local g = love.graphics
  local field = self:img(self.prefix .. "listField")
  if field then g.draw(field, 0, 0) end
  local ink, shadow = self:colors()
  local dex = self.game.save.pokedex or {}
  local caught = self:img("caught")
  local ox, oy = 2 * 8, 2 * 8 -- sWindowTemplate_OrderedListMenu (2,2)
  for slot = 1, ROWS do
    local n = self.scroll + slot
    if n > self.count then break end
    -- THE ROW BEING DRAWN AND THE SLOT IT IS DRAWN IN ARE NOT THE SAME THING.
    -- They were called the same thing for one revision, and the shadowed name
    -- took the y out of the row table rather than out of the slot number.
    local entry = self.rows[n]
    local id = entry and entry.id
    local y = oy + 2 + (slot - 1) * ROW_H
    -- ItemPrintFunc_OrderedListMenu prints the number at the row's own y,
    -- the same y the ListMenu prints the name at
    dexNo(ox + 12, y, (entry and entry.n) or n, ink, shadow)
    local name = "----------"
    if id and (dex.seen or {})[id] then
      local def = (self.game.data.pokemon or {})[id]
      name = (def and def.name) or id
    end
    if id and (dex.owned or {})[id] and caught then g.draw(caught, ox + 40, y + 3) end
    text(name, ox + 56, y, ink, shadow)
    -- ItemPrintFunc_OrderedListMenu: a caught species' type badges at 120/152
    if id and (dex.owned or {})[id] then
      local sum = (self.game.data.constants or {}).gen3FRLGSummary
      local sheetPath = sum and sum.images and sum.images.menu_info
      local okS, sheet = false, nil
      if sheetPath then okS, sheet = pcall(Assets.image, sheetPath) end
      local def = (self.game.data.pokemon or {})[id] or {}
      local t1 = def.type1 or (def.types and def.types[1])
      local t2 = def.type2 or (def.types and def.types[2])
      if okS and sheet then
        local iw, ih = sheet:getDimensions()
        for k, tname in ipairs({ t1, (t2 ~= t1) and t2 or nil }) do
          local off = tname and (sum.typeIcons or {})[tostring(tname):upper()]
          if off then
            g.draw(sheet, g.newQuad((off % 16) * 8, math.floor(off / 16) * 8, 32, 12, iw, ih),
                   ox + (k == 1 and 120 or 152), y + 2)
          end
        end
      end
    end
    if n == self.index then Font.drawCode(require("src.ui.Theme").cursor, ox + 4 - 2, y) end
  end
  local t = self.rec.text or {}
  self:drawBars(t.listTitle or "POKéMON LIST", { { "+", "PICK" }, { "A", "OK" }, { "B", "EXIT" } })
end

function Dex:drawEntry()
  local g = love.graphics
  local field = self:img(self.prefix .. "field")
  if field then g.draw(field, 0, 0) end
  local frame = self:img(self.prefix .. "pageFrame")
  if frame then g.draw(frame, 0, 0) end
  local ink, shadow = self:colors()
  local t = self.rec.text or {}
  local def = self.def or {}
  local owned = self:owned(self.species)

  -- mon pic window (19,3) 8x8
  if self.pic then g.draw(self.pic, 19 * 8, 3 * 8) end

  -- stats window (2,3)
  local sx, sy = 2 * 8, 3 * 8
  dexNo(sx, sy + 8, def.dex, ink, shadow)
  text(def.name or tostring(self.species), sx + 28, sy + 8, ink, shadow)
  local category = owned and (def.category or "") or "???????????"
  category = category:gsub("%s+$", "")
  text(category .. " " .. (t.pokemon or "POKéMON"), sx, sy + 24, ink, shadow, true)
  local htText, wtText = "??'??", "????.? " .. (t.lbs or "lbs.")
  if owned and def.height then
    local dm = math.floor(def.height * 10 + 0.5)
    local inches = math.floor(dm * 10000 / 254)
    if inches % 10 >= 5 then inches = inches + 10 end
    local feet = math.floor(inches / 120)
    htText = ("%d'%02d"):format(feet, math.floor((inches - feet * 120) / 10))
  end
  if owned and def.weight then
    local hg = math.floor(def.weight * 10 + 0.5)
    local lbs = math.floor(hg * 100000 / 4536)
    if lbs % 10 >= 5 then lbs = lbs + 10 end
    wtText = ("%d.%d %s"):format(math.floor(lbs / 100), math.floor(lbs / 10) % 10, t.lbs or "lbs.")
  end
  text(t.ht or "HT", sx, sy + 36, ink, shadow, true)
  text(htText, sx + 30, sy + 36, ink, shadow, true)
  -- the inch mark is CHAR_DBL_QUOTE_RIGHT ($B2), which the charmap has no
  -- ASCII spelling for
  do
    local two = Font.beginTwoTone(ink, shadow)
    local pushed = Font.hasFace and Font.hasFace("small")
    if pushed then Font.pushFace("small") end
    Font.drawCode(0xB2, sx + 30 + smallWidth(htText), sy + 36)
    if pushed then Font.popFace() end
    if two then Font.endTwoTone() end
    love.graphics.setColor(1, 1, 1, 1)
  end
  text(t.wt or "WT", sx, sy + 48, ink, shadow, true)
  text(wtText, sx + 30, sy + 48, ink, shadow, true)
  -- footprint at (88,40) in the stats window
  local prints, rec = self:img("footprints")
  if owned and prints and def.index then
    local cols = (type(rec) == "table" and rec.cols) or 32
    local i = tonumber(def.index) or 0
    local iw, ih = prints:getDimensions()
    g.draw(prints, g.newQuad((i % cols) * 16, math.floor(i / cols) * 16, 16, 16, iw, ih),
           sx + 88, sy + 40)
  end

  -- flavour text window (0,11), centred, from y 8
  if owned and type(def.dexEntry) == "string" then
    local lines = {}
    for line in (def.dexEntry:gsub("\f", "\n") .. "\n"):gmatch("([^\n]*)\n") do
      lines[#lines + 1] = line
    end
    local widest = 0
    for _, line in ipairs(lines) do widest = math.max(widest, Font.width(line)) end
    local x = math.max(0, math.floor((W - widest) / 2))
    for i, line in ipairs(lines) do text(line, x, 11 * 8 + 8 + (i - 1) * 16, ink, shadow) end
  end

  if self.registered then
    self:drawBars(nil, { { "A", "NEXT" } })
  else
    -- the bar this page actually prints: the cry on the left, then
    -- {A}NEXT DATA {B}CANCEL -- and A really does turn to the next page
    -- rather than replaying the cry, which is what it used to do here.
    local hint = "START " .. ((t.cry or "CRY"):gsub("^%W+", ""))
    self:drawBars(nil, { { "A", "NEXT DATA" }, { "B", "CANCEL" } }, hint)
  end
end

-- ONE COLOUR FOR EVERY INDEX, which is what sPalette_Silhouette is: the
-- SIZE half draws the Pokemon and the trainer as flat shapes, so the picture
-- goes through a shader that keeps its alpha and throws its colours away.
local silhouette
local function silhouetteShader()
  if silhouette ~= nil then return silhouette or nil end
  silhouette = false
  local ok, sh = pcall(love.graphics.newShader, [[
    extern vec4 tint;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      return vec4(tint.rgb, Texel(tex, tc).a * tint.a);
    }
  ]])
  if ok and sh then silhouette = sh end
  return silhouette or nil
end

function Dex:drawArea()
  local g = love.graphics
  local a = areaRecord(self)
  local L = a.layout
  local voff = self:areaVoff() * 8
  local field = self:img(self.prefix .. "field")
  if field then g.draw(field, 0, 0) end
  local ink, shadow = self:colors()
  local t = self.rec.text or {}
  local def = self.def or {}
  local owned = self:owned(self.species)

  -- the maps: Kanto always, an island once the save has earned it
  local map = self:img(self.prefix .. "areaMap")
  if map then g.draw(map, L.kantoMap.x, L.kantoMap.y + voff) end
  local isles = self:seviiUnlocked()
  for j, box in ipairs(L.seviiMaps or {}) do
    if math.floor(isles / 2 ^ (j - 1)) % 2 == 1 then
      local isle = self:img(self.prefix .. "areaSevii" .. j)
      if isle then g.draw(isle, box.x, box.y + voff) end
    end
  end

  -- the markers, at the cartridge's own offsets from the marker sprite
  local markers = self.areaMarkers or {}
  for _, m in ipairs(markers) do
    local shape = (a.shapes or {})[m.shape]
    local path = type(shape) == "table" and shape.path
    if path then
      if self.cache[path] == nil then
        local okI, image = pcall(Assets.image, path)
        self.cache[path] = okI and image or false
      end
      local image = self.cache[path]
      if image then
        -- BLDALPHA(12, 8): the markers are blended over the map rather than
        -- painted on it
        g.setColor(1, 1, 1, 12 / 16)
        g.draw(image, L.sprite.x + m.x, L.sprite.y + voff + m.y)
        g.setColor(1, 1, 1, 1)
      end
    end
  end
  if #markers == 0 then
    local label = t.areaUnknown or "AREA UNKNOWN"
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", L.kantoMap.x + 4, L.kantoMap.y + voff + 28, 88, 16, 8, 8)
    g.setColor(1, 1, 1, 1)
    text(label, L.kantoMap.x + math.floor((L.kantoMap.w - smallWidth(label)) / 2),
         L.kantoMap.y + voff + 29, { 1, 1, 1, 1 }, { 0.2, 0.2, 0.2, 1 }, true)
  end

  -- the party icon, the number and the name, the type badges
  local icon = def.icon
  local iconPath = type(icon) == "table" and icon.image or icon
  if type(iconPath) == "string" then
    if self.cache[iconPath] == nil then
      local okI, image = pcall(Assets.image, iconPath)
      self.cache[iconPath] = okI and image or false
    end
    local image = self.cache[iconPath]
    if image then
      local iw, ih = image:getDimensions()
      local fh = (type(icon) == "table" and icon.frameHeight) or ih
      g.draw(image, g.newQuad(0, 0, iw, fh, iw, ih), L.monIcon.x, L.monIcon.y)
    end
  end
  dexNo(L.name.x, L.name.y, def.dex, ink, shadow)
  text(def.name or tostring(self.species), L.name.x + 3, L.name.y + 12, ink, shadow)
  if owned then self:drawTypes(self.species, L.types.x, L.types.y + 1) end

  -- SIZE and AREA, each centred over its own window
  local sizeLabel, areaLabel = t.size or "SIZE", t.area or "AREA"
  text(sizeLabel, L.sizeLabel.x + math.floor((L.sizeLabel.w - smallWidth(sizeLabel)) / 2),
       L.sizeLabel.y + 4, ink, shadow, true)
  text(areaLabel, L.areaLabel.x + math.floor((L.areaLabel.w - smallWidth(areaLabel)) / 2),
       L.areaLabel.y + voff + 4, ink, shadow, true)

  -- HOW BIG IT IS NEXT TO YOU.  A GBA affine scale is a DIVISOR, so 256 is
  -- life size and a bigger number draws smaller -- the same pose fields the
  -- Hoenn dex uses, read out of this cartridge's own gPokedexEntries.
  if owned then
    local sh = silhouetteShader()
    local c = a.silhouette or { 80, 80, 80 }
    local pose = def.dexPose or {}
    local function posed(image, place, scale, offset)
      if not image then return end
      local w, h = image:getDimensions()
      local s = (L.lifeSize or 256) / math.max(1, tonumber(scale) or 256)
      if sh then
        g.setShader(sh)
        pcall(sh.send, sh, "tint", { c[1] / 255, c[2] / 255, c[3] / 255, 1 })
      else
        g.setColor(0, 0, 0, 1)
      end
      g.draw(image, place.x - w * s / 2, place.y - h * s / 2 + (tonumber(offset) or 0),
             0, s, s)
      if sh then g.setShader() end
      g.setColor(1, 1, 1, 1)
    end
    posed(self.pic, L.mon, pose.monScale, pose.monOffset)
    posed(self:trainerPic(), L.trainer, pose.trainerScale, pose.trainerOffset)
  end

  local hint = "START " .. ((t.cry or "CRY"):gsub("^%W+", ""))
  self:drawBars(nil, { { "A", "CANCEL" }, { "B", "PREVIOUS DATA" } }, hint)
end

-- the player's own front picture, which is what the cartridge stands beside
-- the Pokemon (CreateTrainerPicSprite of PlayerGenderToFrontTrainerPicId)
function Dex:trainerPic()
  if self.sizeTrainer ~= nil then return self.sizeTrainer or nil end
  self.sizeTrainer = false
  local record = (self.game.data.constants or {}).gen3TrainerBack
  local which = record and record.playerFront
  if type(which) ~= "table" then return nil end
  local player = (self.game.save or {}).player or {}
  local index = (player.gender == "girl" and which.girl) or which.boy
  if not index then return nil end
  local ok, img = pcall(Assets.image,
                        ("assets/generated/battle/trainers/%03d.png"):format(index))
  if ok and img then self.sizeTrainer = img end
  return self.sizeTrainer or nil
end

-- THE MODE MENU (sListMenuTemplate_KantoDexModeSelect): nine rows showing,
-- headings flush left at 0 and the rows themselves indented to 12, with the
-- cursor at 4.  A heading is not a landing place, which is why the cursor
-- steps over them rather than sitting on one.
function Dex:drawTop()
  local g = love.graphics
  -- the mode menu stands on tile 1, the flat white, not on the list's
  -- patterned ground (DexScreen_LoadResources fills BG3 with 0x001)
  local field = self:img(self.prefix .. "field")
  if field then g.draw(field, 0, 0) end
  local ink, shadow = self:colors()
  local rows = self:modeRows() or {}
  -- sWindowTemplate_ModeSelect is at (1,2), not the list's (2,2), and
  -- sListMenuTemplate_KantoDexModeSelect places a heading at header_X 0, a
  -- row at item_X 12 and the cursor at cursor_X 4 -- all measured from the
  -- window's own left edge.
  local ox, oy = 1 * 8, 2 * 8
  for i = 1, TOP_ROWS do
    local n = self.topScroll + i
    local row = rows[n]
    if not row then break end
    local y = oy + 2 + (i - 1) * ROW_H
    if row.kind == "header" then
      text(row.label, ox, y, ink, shadow)
    else
      local dim = row.kind == "category"
                  and not self:categoryUnlocked(row.category)
      if dim then
        local dimInk, dimShadow = self:dimColors()
        text(row.label, ox + 12, y, dimInk, dimShadow)
      else
        text(row.label, ox + 12, y, ink, shadow)
      end
      if n == self.topIndex then
        Font.drawCode(require("src.ui.Theme").cursor, ox + 4 - 2, y)
      end
    end
  end
  -- SEEN and OWN, which the cartridge keeps in a window of its own on the
  -- right (sWindowTemplate_DexCounts at (21,2))
  local dex = (self.game.save or {}).pokedex or {}
  local seen, owned = 0, 0
  for _ in pairs(dex.seen or {}) do seen = seen + 1 end
  for _ in pairs(dex.owned or {}) do owned = owned + 1 end
  text("SEEN", 21 * 8, 3 * 8, ink, shadow, true)
  text(tostring(seen), 21 * 8 + 8, 4 * 8 + 4, ink, shadow, true)
  text("OWN", 21 * 8, 6 * 8, ink, shadow, true)
  text(tostring(owned), 21 * 8 + 8, 7 * 8 + 4, ink, shadow, true)
  local t = self.rec.text or {}
  self:drawBars(t.listTitle or "POKéMON", { { "A", "OK" }, { "B", "EXIT" } })
end

-- A HABITAT, FOUR AT A TIME, laid out the way the cartridge lays it out.
--
-- Each slot is two windows, not a row: an 8x8-tile circular one holding the
-- Pokemon's own front picture, and an 8x5 rectangular one beside it with the
-- number over the name and the caught marker in its corner.  Where the two
-- go depends on how many are on the page -- see CAT_COORDS -- so a page of
-- one centres it and a page of four rings them.
--
-- The counter is the cartridge's own too: PAGE, then this page and the total
-- as two digits around a slash, and both numbers count only the pages that
-- can actually be reached (DexScreen_PageNumberToRenderablePages).
function Dex:monPic(id)
  self.pics = self.pics or {}
  if self.pics[id] ~= nil then return self.pics[id] or nil end
  self.pics[id] = false
  local ok, path = pcall(require("src.pokemon.Sprites").path, self.game.data,
                         id, "front", { kind = "dex" })
  if ok and path then
    local okImg, image = pcall(Assets.image, path)
    if okImg and image then self.pics[id] = image end
  end
  return self.pics[id] or nil
end

function Dex:drawCategory()
  local g = love.graphics
  -- a habitat page has a ground of its own: BG3 tile 2, the flat cream
  -- (DexScreen_CreateCategoryListGfx).  The white field is the fallback for
  -- a cache imported before that tile was ripped.
  local field = self:img(self.prefix .. "catField")
                or self:img(self.prefix .. "field")
  if field then g.draw(field, 0, 0) end
  local ink, shadow = self:colors()
  local dex = (self.game.save or {}).pokedex or {}
  local pages = self.catPages or {}
  local page = pages[self.catPage] or {}
  local coords = CAT_COORDS[#page] or CAT_COORDS[4]
  local caught = self:img("caught")
  for i, id in ipairs(page) do
    local place = coords[i]
    if place then
      local def = (self.game.data.pokemon or {})[id] or {}
      local px, py = place[1] * 8, place[2] * 8
      local ix, iy = place[3] * 8, place[4] * 8
      local pic = self:monPic(id)
      if pic then
        local w, h = pic:getDimensions()
        g.setColor(1, 1, 1, 1)
        g.draw(pic, px + math.floor((64 - w) / 2),
               py + math.floor((64 - h) / 2))
      end
      -- the info window: DexScreen_PrintMonDexNo at (12,0), the name at
      -- (2,13), the caught marker at (2,3)
      dexNo(ix + 12, iy, def.dex, ink, shadow)
      text(def.name or id, ix + 2, iy + 13, ink, shadow)
      if (dex.owned or {})[id] and caught then g.draw(caught, ix + 2, iy + 3) end
      if i == self.catIndex then
        g.setColor(ink)
        g.rectangle("line", px + 0.5, py + 0.5, 63, 63, 6, 6)
        g.setColor(1, 1, 1, 1)
      end
    end
  end
  local t = self.rec.text or {}
  local counter = ("%s%2d/%2d"):format(t.page or "PAGE", self.catPage, #pages)
  self:drawBars((self.cat and self.cat.name) or "",
                { { "+", counter }, { "A", "OK" }, { "B", "BACK" } })
end

function Dex:draw()
  love.graphics.setColor(1, 1, 1, 1)
  if self.mode == "top" then self:drawTop()
  elseif self.mode == "category" then self:drawCategory()
  elseif self.mode == "area" and areaRecord(self) then self:drawArea()
  elseif self.mode == "entry" or self.mode == "area" then self:drawEntry()
  else self:drawList() end
end

return Dex
