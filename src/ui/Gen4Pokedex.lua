-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's POKEDEX, which was the last screen on the reported fault list
-- still falling back to Kanto's: "neither is the pokedex, or the pokemon party
-- menu or the bag theyre looking like gen1 still".  The party menu and the bag
-- were fixed by the module list; this one was not, and was deliberately left
-- alone afterwards, because THE ART COMPOSED BLANK and a Gen 4 Pokedex drawn
-- on it would have been a black screen where Kanto's at least showed something.
--
-- The composition is fixed now -- see `Gen4Dex`, and `Gen4Graphics.stamp` for
-- the thing the planner could not express -- so this is the screen.
--
-- The list and entry use the cartridge's backgrounds. The full DS scroll
-- wheel, habitat, size, search and form pages still need their own screens.
--
-- WHAT THE PAGE SAYS IS THE CARTRIDGE'S TOO, including the three things the
-- species table does not carry: Platinum stores height, weight and the
-- category line as pre-formatted STRINGS, one per species, and the `dex` stage
-- now carries all three.  Nothing on this page is computed from a number this
-- port chose how to round.

local Assets = require("src.render.Assets")

-- `NATIONAL_DEX_COUNT (MAX_SPECIES - 2)` from pokeplatinum's
-- `include/constants/species.h`; `MAX_SPECIES` is `SPECIES_BAD_EGG` = 495.
local NATIONAL_DEX_COUNT = 493
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Sprites = require("src.pokemon.Sprites")
local Strings = require("src.core.Strings")

local Gen4Pokedex = {}
Gen4Pokedex.__index = Gen4Pokedex
Gen4Pokedex.isOpaque = true

local W, H = 256, 192

-- The list page, which is this port's and says so.
local LIST = { x = 24, y = 48, pitch = 16, rows = 5 }

-- Where the entry page's words go, when the cache has no layout of its own.
-- Every number is `Gen4Dex.LAYOUT`'s; they are repeated here only so a cache
-- imported before the `dex` stage still lands its text somewhere sensible.
local FALLBACK_LAYOUT = {
  sprite = { x = 48, y = 72 },
  nameNumber = { x = 172, y = 32 },
  category = { x = 114, y = 44 },
  heightLabel = { x = 152, y = 88 },
  heightValue = { x = 184, y = 88 },
  weightLabel = { x = 152, y = 104 },
  weightValue = { x = 184, y = 104 },
  entry = { centre = 128, y = 136, maxWidth = 240, overflowX = 8 },
  footprint = { x = 96, y = 64, size = 48 },
}

-- The sprite's position is the CENTRE on hardware -- `PokemonSprite` is an
-- OAM object and its x/y are its middle -- so an 80x80 picture drawn from its
-- top-left has to be offset by half of itself.
local SPRITE_SIZE = 80

function Gen4Pokedex:uiSize() return W, H end
function Gen4Pokedex:wantsFillScale() return true end
function Gen4Pokedex:wantsEdgeBleed() return false end

function Gen4Pokedex:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4Pokedex.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4Pokedex)
  self.game = game
  self.onCancel = opts.onCancel
  self.cache = {}
  self.art = (game.data or {}).gen4_dex or nil
  if not self.art then
    Logger.warn("gen4 pokedex: this cache carries no `gen4_dex` record -- the "
                .. "entry page is drawn in the engine's own frame")
  end

  self.entries = self:listing()
  self.index = 1
  self.top = 1
  self.tab = 1
  self.page = "list"
  self.scroll = 0
  return self
end

-- ------------------------------------------------------------------ data --

-- Prefer the ROM's Sinnoh order until the National Dex is granted. Old
-- caches without the ordered lists retain their previous national fallback.
function Gen4Pokedex:listing()
  local data = self.game.data or {}
  local mons = data.pokemon or {}
  local out = {}
  local orders=self.art and self.art.orders
  local dex=self.game.save.pokedex or {}
  local order=orders and orders[dex.national and 'national' or 'sinnoh']
  if order then
    self.numbers={}
    for number,id in ipairs(order) do
      if mons[id] then out[#out+1]=id;self.numbers[id]=number end
    end
    return out
  end
  -- `x or 493` CANNOT CATCH A ZERO, and the zero is what arrives.
  --
  -- `Data.lua` derives `dexSize` as the highest `def.dex` across the species
  -- table.  A GEN 4 CACHE CARRIES NO `dex` FIELD AT ALL -- measured, 0 of
  -- 508 species have one, which is the same fact the comment above this
  -- function states from the other side: Platinum numbers its species in
  -- national order, so there is nothing separate to read.  So `highest`
  -- stays 0 and `dexSize` is written as 0.
  --
  -- In Lua only `nil` and `false` are falsy, so `0 or 493` is 0, the loop
  -- `for id = 1, 0` runs no times, and `entries` is EMPTY.  The screen then
  -- draws a correct listing of nothing and refuses to open any entry page,
  -- because `status(species())` is asked about a nil species.  Measured:
  -- `index=1 species=nil` on every tick with the whole dex marked seen.
  --
  -- 493 is the cartridge's own number, not a guess: `species.h` has
  -- `NATIONAL_DEX_COUNT (MAX_SPECIES - 2)` with `MAX_SPECIES SPECIES_BAD_EGG`
  -- = 495, and Arceus -- the last species with a dex number -- is 493.  The
  -- cache's ids run to 507 because the 14 rows above 493 are alternate
  -- FORMS, which is why the highest id is the wrong upper bound here.
  local size = tonumber((data.constants or {}).dexSize)
  if not size or size < 1 then size = NATIONAL_DEX_COUNT end
  for id = 1, size do
    if mons[id] then out[#out + 1] = id end
  end
  return out
end

function Gen4Pokedex:species()
  return self.entries[self.index]
end

function Gen4Pokedex:def(species)
  return (self.game.data.pokemon or {})[species or self:species()]
end

-- Seen and caught, from the save the rest of the engine already keeps.
function Gen4Pokedex:status(species)
  local dex = (self.game.save or {}).pokedex or {}
  local owned = (dex.owned or {})[species]
  if owned then return "owned" end
  if (dex.seen or {})[species] then return "seen" end
  return nil
end

-- ---------------------------------------------------------------- pictures --

function Gen4Pokedex:img(entry)
  local path = (type(entry) == "table" and entry.path) or entry
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4Pokedex:layout()
  return (self.art and self.art.layout) or FALLBACK_LAYOUT
end

-- ------------------------------------------------------------------ input --

function Gen4Pokedex:stopCry()
  if self.cry and self.cry.stop then self.cry:stop() end
  self.cry=nil
end

function Gen4Pokedex:close()
  self:stopCry()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4Pokedex:move(delta)
  local count = #self.entries
  if count == 0 then return end
  self:stopCry()
  self.form=0
  self.index = (self.index - 1 + delta) % count + 1
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + LIST.rows - 1 then
    self.top = self.index - LIST.rows + 1
  end
end

function Gen4Pokedex:update()
  local input = self.game.input
  if not input then return end

  if self.page == "entry" then
    if input:wasPressed("l") then self.tab = (self.tab - 2) % 5 + 1
    elseif input:wasPressed("r") or input:wasPressed("select") then self.tab = self.tab % 5 + 1
    elseif input:wasPressed("up") then self.scroll = math.max(0, self.scroll - 1)
    elseif input:wasPressed("down") then self.scroll = self.scroll + 1
    elseif input:wasPressed("left") then self:move(-1); self.scroll = 0
    elseif input:wasPressed("right") then self:move(1); self.scroll = 0
    elseif input:wasPressed("a") then
      if self.tab == 3 or self.tab == 1 then self:playCry()
      elseif self.tab == 4 then self.sizeWeight=not self.sizeWeight
      elseif self.tab == 5 then self.form = ((self.form or 0) + 1) % #self:forms() end
    elseif input:wasPressed("b") or input:wasPressed("start") then self:stopCry(); self.page, self.scroll = "list", 0 end
    return
  end

  if input:wasPressed("up") then self:move(-1)
  elseif input:wasPressed("down") then self:move(1)
  elseif input:wasPressed("left") then self:move(-LIST.rows)
  elseif input:wasPressed("right") then self:move(LIST.rows)
  elseif input:wasPressed("a") then
    -- ONLY A SEEN SPECIES HAS A PAGE.  The cartridge draws the entry for an
    -- unseen one as an empty frame rather than refusing to open it, but it
    -- also never lets the cursor rest on one that is not in the listing; this
    -- port lists everything, so the refusal is here instead of a page with
    -- nothing on it.
    if self:status(self:species()) then self.page = "entry"; self.tab = 1; self:playCry() end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
end

function Gen4Pokedex:touchpressed(_,px,py)
  local r=require('src.render.Renderer').uiPresentation
  if not r or px<r.x or py<r.y or px>=r.x+r.w or py>=r.y+r.h then return false end
  local x,y=(px-r.x)/r.scaleX,(py-r.y)/r.scaleY
  if self.page=='entry' then
    if y >= 176 then self.tab = math.min(5, math.floor(x / (W / 5)) + 1)
    elseif self.tab == 5 and y >= 128 then self.form = ((self.form or 0) + 1) % #self:forms()
    elseif self.tab == 4 and y >= 128 then self.sizeWeight=not self.sizeWeight
    elseif self.tab == 3 or x < 96 then self:playCry() end
  elseif y>=LIST.y and y<LIST.y+LIST.rows*LIST.pitch then
    local index=self.top+math.floor((y-LIST.y)/LIST.pitch)
    if self.entries[index] then
      self.index=index
      if self:status(self:species()) then self.page='entry';self.tab=1;self.form=0;self:playCry() end
    end
  elseif y>=160 then
    if x<64 then self:move(-LIST.rows)
    elseif x>=192 then self:move(LIST.rows)
    else self:close() end
  end
  return true
end

-- ------------------------------------------------------------------- draw --

function Gen4Pokedex:drawList()
  local g = love.graphics
  g.setColor(0.08, 0.14, 0.24, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local back=self:img(self.art and self.art.list)
  if back then g.draw(back,0,0) end

  local words = (self.art or {}).words or {}
  local seen, owned = 0, 0
  for _, id in ipairs(self.entries) do
    local state = self:status(id)
    if state then seen = seen + 1 end
    if state == "owned" then owned = owned + 1 end
  end
  Font.draw(("%s %d   %s %d"):format(words.seen or Strings("SEEN"), seen,
                                     words.obtained or Strings("OWN"), owned),
            16, 10)

  for row = 0, LIST.rows - 1 do
    local at = self.top + row
    local id = self.entries[at]
    if id then
      local y = LIST.y + row * LIST.pitch
      local def = self:def(id)
      local state = self:status(id)
      local name = state and (def and def.name or tostring(id))
        or ("-"):rep(8)
      if at == self.index then
        g.setColor(0.98, 0.83, 0.30, 0.85)
        g.rectangle("fill", LIST.x - 6, y - 2, W - 2 * LIST.x + 12,
                    LIST.pitch - 2)
        g.setColor(1, 1, 1, 1)
      end
      Font.draw(("%03d"):format(self.numbers and self.numbers[id] or id), LIST.x, y)
      Font.draw(tostring(name), LIST.x + 40, y)
      if state == "owned" then Font.draw("*", LIST.x - 14, y) end
    end
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4Pokedex:drawEntry()
  local g = love.graphics
  local art = self.art or {}
  local L = self:layout()
  local species = self:species()
  local def = self:def(species)

  local page = self:img(art.entry)
  if page then
    g.setColor(1, 1, 1, 1)
    g.draw(page, 0, 0)
  else
    g.setColor(0.10, 0.16, 0.26, 1)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end

  -- The Pokemon, centred on the position the app gives its sprite.
  local path = species and Sprites.path(self.game.data, species, "front",
                                        { kind = "dex" })
  local image = path and self:img(path)
  if image then
    local iw, ih = image:getDimensions()
    g.setColor(1, 1, 1, 1)
    g.draw(image, L.sprite.x - SPRITE_SIZE / 2, L.sprite.y - SPRITE_SIZE / 2,
           0, SPRITE_SIZE / iw, SPRITE_SIZE / ih)
  end

  local words = art.words or {}
  local heading=Font.fit(("%03d  %s"):format((self.numbers and self.numbers[species]) or species or 0,(def and def.name) or "?"),136)
  Font.draw(heading,L.nameNumber.x-math.floor(Font.width(heading)/2),L.nameNumber.y)

  local category = (art.category or {})[species]
  if category then Font.draw(category, L.category.x, L.category.y) end

  Font.draw(words.height or "HT", L.heightLabel.x, L.heightLabel.y)
  Font.draw((art.height or {})[species] or "???",
            L.heightValue.x, L.heightValue.y)
  Font.draw(words.weight or "WT", L.weightLabel.x, L.weightLabel.y)
  Font.draw((art.weight or {})[species] or "???",
            L.weightValue.x, L.weightValue.y)

  -- The entry text.  The cartridge centres it on x = 128 and drops to x = 8
  -- when it is wider than 240 -- its own overflow rule, kept rather than
  -- replaced by a clamp.
  local entry = (def and def.dexEntry) or ""
  local lines = {}
  for line in (tostring(entry) .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  local maxLines = 3
  if self.scroll > math.max(0, #lines - maxLines) then
    self.scroll = math.max(0, #lines - maxLines)
  end
  for i = 1, maxLines do
    local line = lines[self.scroll + i]
    if line then
      local width = Font.width(line)
      local x = (width < L.entry.maxWidth)
        and (L.entry.centre - math.floor(width / 2)) or L.entry.overflowX
      Font.draw(line, x, L.entry.y + (i - 1) * 10)
    end
  end

  -- The banner, on its own layer over the page, exactly as the app draws it.
  local banner = self:img(art.banner)
  if banner then
    g.setColor(1, 1, 1, 1)
    g.draw(banner, 0, 0)
  end
  g.setColor(1, 1, 1, 1)
end

local TABS = { 'INFO', 'AREA', 'CRY', 'SIZE', 'FORMS' }
function Gen4Pokedex:playCry()
  self:stopCry()
  self.cry = require('src.core.Sound').playCry(self.game.data, self:species())
end
function Gen4Pokedex:forms()
  local species = self:species()
  local out = { false }
  for name, record in pairs((self:def() or {}).forms or {}) do
    if record.spriteFront then out[#out+1] = name end
  end
  table.sort(out,function(a,b) if a==false then return true elseif b==false then return false end return tostring(a)<tostring(b) end)
  return out
end
function Gen4Pokedex:areas()
  local out, seen = {}, {}
  local species = self:species()
  local function contains(t)
    if type(t) ~= 'table' then return false end
    for _,v in pairs(t) do
      if type(v) == 'table' and (v.species == species or contains(v)) then return true end
    end
    return false
  end
  for id,map in pairs(self.game.data.maps or {}) do
    local area = (self.game.data.encounters or {})[map.encounters]
    local found = area and (tonumber(area.grassRate) or 0) > 0 and contains(area.grass)
    if area then
      for _, method in ipairs({'surf','oldRod','goodRod','superRod'}) do
        local block = area[method]
        if block and (tonumber(block.rate) or 0) > 0 and contains(block.slots) then found = true end
      end
      if (tonumber(area.grassRate) or 0) > 0 then
        for _, method in ipairs({'day','night','swarm','radar'}) do
          for _, id in ipairs(area[method] or {}) do if id == species then found = true end end
        end
        for _, slots in pairs(area.dualSlot or {}) do
          for _, id in ipairs(slots) do if id == species then found = true end end
        end
      end
    end
    if found then
      local label = map.label or id
      if not seen[label] then seen[label]=true;out[#out+1]=label end
    end
  end
  table.sort(out);return out
end
function Gen4Pokedex:screenArt(key)
  local screens = ((self.game.data.gen4_graphics or {}).screens or {})
  return self:img(screens[key])
end
function Gen4Pokedex:drawDetails()
  if self.tab == 1 then
    self:drawEntry()
    local footprint = self:screenArt(('dex/footprint_%03d'):format(self:species()))
    if footprint then
      local at = self:layout().footprint
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(footprint, at.x + 16, at.y + 16)
    end
    return
  end
  local g=love.graphics
  g.setColor(0.85,0.9,0.95,1);g.rectangle('fill',0,0,W,H);g.setColor(1,1,1,1)
  local key = self.tab==2 and 'pokedex/area_map' or self.tab==3 and 'pokedex/cry_button'
    or self.tab==4 and (self.sizeWeight and 'pokedex/weight_check_main' or 'pokedex/height_check_main') or 'pokedex/forms_sub'
  local bg=self:screenArt(key);if bg then g.draw(bg,0,0) end
  local def=self:def();Font.draw((def and def.name) or '?',8,8)
  if self.tab==2 then
    local locations=self:areas()
    self.scroll=math.min(self.scroll,math.max(0,#locations-8))
    if #locations==0 then Font.draw('AREA UNKNOWN',48,80) end
    for i=1,8 do if locations[self.scroll+i] then Font.draw(Font.fit(locations[self.scroll+i],232),12,28+(i-1)*17) end end
  elseif self.tab==3 then
    Font.draw('A: PLAY CRY',72,144)
    local bar=self:screenArt('pokedex/cry_bar_00');if bar then g.draw(bar,112-bar:getWidth()/2,88-bar:getHeight()/2) end
  elseif self.tab==4 then
    if self:status(self:species())=='owned' then
      Font.draw('HEIGHT '..((self.art.height or {})[self:species()] or '?'),24,120)
      Font.draw('WEIGHT '..((self.art.weight or {})[self:species()] or '?'),24,144)
    end
  elseif self.tab==5 then
    local forms=self:forms();local form=forms[(self.form or 0)%#forms+1]
    local path=form and def.forms[form].spriteFront or Sprites.path(self.game.data,self:species(),'front',{kind='dex'})
    local image=path and self:img(path)
    if image then g.draw(image,88,48,0,80/image:getWidth(),80/image:getHeight()) end
    Font.draw('A: NEXT FORM',64,144)
  end
end
function Gen4Pokedex:drawTabs()
  local g=love.graphics
  for i,label in ipairs(TABS) do
    g.setColor(i==self.tab and 0.7 or 0.9,0.8,0.85,1)
    g.rectangle('fill',(i-1)*W/5,176,W/5,16);g.setColor(1,1,1,1)
    Font.draw(label,(i-1)*W/5+4,178)
  end
end
function Gen4Pokedex:draw()
  if self.page == "entry" then self:drawDetails();self:drawTabs();return end
  self:drawList()
end

return Gen4Pokedex
