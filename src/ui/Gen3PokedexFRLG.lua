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
local ROW_H = 16
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

function Dex.new(game, opts)
  local self = base(game, opts)
  self.onCancel = self.opts.onCancel
  self.mode = "list"
  self.list, self.count = listing(game)
  self.index, self.scroll = 1, 0
  local dex = game.save and game.save.pokedex or {}
  for n = 1, self.count do
    if self.list[n] and (dex.seen or {})[self.list[n]] then self.index = n break end
  end
  self:clampScroll()
  return self
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

function Dex:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Dex:update()
  local input = self.game.input
  if self.mode == "entry" then
    if self.registered then
      if input:wasPressed("a") or input:wasPressed("b") then self.game.stack:pop() end
      return
    end
    if input:wasPressed("a") or input:wasPressed("start") then
      pcall(Sound.playCry, self.game.data, self.species)
    elseif input:wasPressed("b") then
      self.mode = "list"
    end
    return
  end
  local moved = false
  if input:wasPressed("down") then self.index = self.index + 1 moved = true
  elseif input:wasPressed("up") then self.index = self.index - 1 moved = true
  elseif input:wasPressed("right") then self.index = self.index + ROWS moved = true
  elseif input:wasPressed("left") then self.index = self.index - ROWS moved = true
  elseif input:wasPressed("a") then
    local id = self.list[self.index]
    local dex = self.game.save.pokedex or {}
    if id and (dex.seen or {})[id] then self:openEntry(id) end
  elseif input:wasPressed("b") then
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
  local bars = self:img(self.prefix .. "bars")
  if bars then g.draw(bars, 0, 0) end
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

function Dex:drawList()
  local g = love.graphics
  local field = self:img(self.prefix .. "listField")
  if field then g.draw(field, 0, 0) end
  local ink, shadow = self:colors()
  local dex = self.game.save.pokedex or {}
  local caught = self:img("caught")
  local ox, oy = 2 * 8, 2 * 8 -- sWindowTemplate_OrderedListMenu (2,2)
  for row = 1, ROWS do
    local n = self.scroll + row
    if n > self.count then break end
    local id = self.list[n]
    local y = oy + 2 + (row - 1) * ROW_H
    text(("No%03d"):format(n), ox + 12, y + 1, ink, shadow, true)
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
  text(("No%03d"):format(tonumber(def.dex) or 0), sx, sy + 9, ink, shadow, true)
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
    self:drawBars(nil, { { "A", "NEXT DATA" }, { "B", "CANCEL" } }, "START " .. ((t.cry or "CRY"):gsub("^%W+", "")))
  end
end

function Dex:draw()
  love.graphics.setColor(1, 1, 1, 1)
  if self.mode == "entry" then self:drawEntry() else self:drawList() end
end

return Dex
