-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's SUMMARY PAGES.
--
-- THE WORDS ARE ALL BANK 455's, and finding that bank is the part worth
-- recording: "To Next Lv." occurs exactly once in all 1,127 message banks, and
-- around it sit the six page titles, every field label, the twenty-five nature
-- lines and the twenty-five characteristic lines.  Two other banks looked like
-- this one -- 326 and 336 both carry "Exp. Points", "Nature" and "Item" -- and
-- both are DEBUG menus, full of "Random value", "HP rnd" and "msg location".
-- Three common words in common is not an identification; a phrase that occurs
-- once is.
--
-- THE ROWS ARE MEASURED off the pages themselves.  Each page is a panel of
-- stripes and a stripe boundary is a row: on `page_info` the colour changes at
-- y = 40, 56, 72, 88, 104, 120, 136 -- a sixteen-pixel pitch, one row per
-- label -- and on `page_battle_moves` at 50, 82, 114, 146, which is the four
-- move rows at a pitch of thirty-two.  The white value boxes sit at x = 180.
--
-- THREE PAGES, NOT SIX.  CONDITION, CONTEST MOVES and RIBBONS are named in the
-- bank and are not drawn: contest stats and ribbons are not modelled by this
-- engine, and an empty page carrying the cartridge's own title on it would
-- claim they were.
--
-- THE POKEMON'S PICTURE is drawn from `PICTURE` below.  The screen had declared
-- a slot for it since it was written and never drawn into it, so every summary
-- page in Sinnoh was a page of numbers with an empty plate beside them.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Party = require("src.pokemon.Party")
local Sprites = require("src.pokemon.Sprites")
local Strings = require("src.core.Strings")

local Gen4SummaryMenu = {}
Gen4SummaryMenu.__index = Gen4SummaryMenu
Gen4SummaryMenu.isOpaque = true

local W, H = 256, 192

local FALLBACK_LAYOUT = {
  label = { x = 112 }, value = { x = 180 },
  name = { x = 8, y = 42 }, picture = { x = 52, y = 104, plate = 64 },
  info = { first = 40, pitch = 16, rows = 7 },
  skills = { first = 40, pitch = 16, rows = 6, ability = 144, abilityText = 162 },
  moves = { first = 50, pitch = 32, rows = 4 },
}

-- WHERE THE POKEMON GOES.  Both numbers are the cartridge's and both are
-- stated twice; the derivation is written out in `Gen4Menus.SUMMARY_LAYOUT`,
-- which is where an import gets them from.  Repeated here so a cache that
-- predates the picture being drawn at all still puts it in the right place.
Gen4SummaryMenu.PICTURE = { x = 52, y = 104, plate = 64 }

-- THE SPRITE IS 80 SQUARE AND THE PLATE UNDER IT IS 64, so the Pokemon
-- overhangs its plate on every side.  Not a scale: the cartridge draws the
-- pokegra cell at 1:1 (MON_AFFINE_SCALE(1)) and lets it overflow.
Gen4SummaryMenu.PICTURE_SIZE = 80

-- AN EGG IS NOT A SPECIES ROW.  pl_otherpoke files the two eggs under species
-- 0, so they land in `gen4_species_sprites.forms` rather than on any
-- `data.pokemon` row.  The key is `Gen4Otherpoke.key`'s own format,
-- ("%03d_%s_%s"):format(species, name, form), and tools/gen4_summary_check.lua
-- asserts this string against that function so the spelling cannot drift.
-- The Manaphy egg is extracted under `000_egg_manaphy` and is deliberately NOT
-- named here: nothing in this port marks an egg as Manaphy's yet, so a
-- constant for it would be a key nothing could ever choose.
Gen4SummaryMenu.EGG_KEY = "000_egg_base"

function Gen4SummaryMenu:uiSize() return W, H end
function Gen4SummaryMenu:wantsFillScale() return true end
function Gen4SummaryMenu:wantsEdgeBleed() return false end

function Gen4SummaryMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

-- The caller hands over the Pokemon itself, which is the shape every other
-- summary screen in this port is pushed with.
function Gen4SummaryMenu.new(game, arg)
  local self = setmetatable({}, Gen4SummaryMenu)
  self.game = game
  if arg and arg.species ~= nil then
    self.mon = arg
  else
    self.mon = arg and arg.mon
    self.onCancel = arg and arg.onCancel
    self.choose = arg and arg.choose
  end
  self.page = 1
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  local record = ((game.data or {}).gen4_menus or {}).summary
  if not record then
    Logger.warn("gen4 summary: this cache carries no summary text -- "
                .. "falling back to the engine's own words")
  end
  self.text = (record and record.text) or {}
  self.pages = (record and record.pages) or {
    { key = "info", art = "summary/page_info" },
    { key = "skills", art = "summary/page_skills" },
    { key = "moves", art = "summary/page_battle_moves" },
  }
  self.layout = (record and record.layout) or FALLBACK_LAYOUT
  self.natures = (record and record.natures) or {}
  return self
end

function Gen4SummaryMenu:word(key, fallback)
  local text = self.text[key]
  if type(text) ~= "string" or text == "" then return fallback or "" end
  -- The cartridge's colour codes pick a palette row this port has no text
  -- style for yet; dropped rather than printed as `{COLOR 2}`.
  return (text:gsub("{COLOR %d+}", ""))
end

-- One loader, by PATH.  The page art arrives as an art key and the Pokemon's
-- picture as a path off the species row, so the key lookup is the wrapper and
-- this is the part both share.
function Gen4SummaryMenu:image(path)
  if type(path) ~= "string" or path == "" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4SummaryMenu:img(key)
  local rec = self.art[key]
  return self:image((type(rec) == "table" and rec.path) or rec)
end

function Gen4SummaryMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4SummaryMenu:update()
  local input = self.game.input
  if not input then return end
  local n = #self.pages
  if input:wasPressed("right") then
    self.page = self.page % n + 1
  elseif input:wasPressed("left") then
    self.page = (self.page - 2) % n + 1
  elseif input:wasPressed("b") or input:wasPressed("a")
         or input:wasPressed("start") then
    self:close()
  end
end

-- ------------------------------------------------------------------- draw --

function Gen4SummaryMenu:speciesDef()
  local mon = self.mon
  local data = self.game.data
  if not (mon and data and data.pokemon) then return nil end
  return data.pokemon[mon.species]
end

function Gen4SummaryMenu:row(page, i)
  local box = self.layout[page] or FALLBACK_LAYOUT[page]
  return box.first + (i - 1) * box.pitch + 4
end

local function fitted(text,x,y,width,align)
  text=tostring(text)
  local pixels=Font.width(text)
  local scale=math.min(1,width/math.max(1,pixels))
  local g=love.graphics
  local offset=align=='centre' and (width-pixels*scale)/2 or align=='right' and width-pixels*scale or 0
  g.push();g.translate(x+offset,y);g.scale(scale,1)
  Font.draw(text,0,0);g.pop()
end

function Gen4SummaryMenu:field(page, i, label, value)
  local y = self:row(page, i)
  fitted(label,self.layout.label.x,y,self.layout.value.x-self.layout.label.x-4)
  if value ~= nil then
    local vx=page=='skills' and 188 or 180
    local vy=page=='skills' and i==1 and 30 or y
    fitted(value,vx,vy,248-vx,'centre')
  end
end

function Gen4SummaryMenu:drawInfo()
  local mon, def = self.mon, self:speciesDef()
  local number = (def and (def.dexNumber or def.number)) or mon.species
  self:field("info", 1, self:word("dexNo", Strings("Pokédex No.")),
             ("%03d"):format(tonumber(number) or 0))
  self:field("info", 2, self:word("name", Strings("Name")),
             (def and def.name) or tostring(mon.species))
  local types = def and def.types
  local typeText = "?"
  if type(types) == "table" then
    typeText = tostring(types[1] or "?")
    if types[2] and types[2] ~= types[1] then
      typeText = typeText .. "/" .. tostring(types[2])
    end
  end
  self:field("info", 3, self:word("types", Strings("Type")), typeText)
  local player = (self.game.save or {}).player or {}
  self:field("info", 4, self:word("ot", "OT"),
             tostring(mon.otName or player.name or ""))
  self:field("info", 5, self:word("idNo", Strings("ID No.")),
             ("%05d"):format((tonumber(mon.otId or player.id) or 0) % 100000))
  self:field("info", 6, self:word("expPoints", Strings("Exp. Points")),
             tostring(math.floor(tonumber(mon.exp) or 0)))
  self:field("info", 7, self:word("toNextLv", Strings("To Next Lv.")),
             tostring(math.floor(tonumber(mon.expToNext) or 0)))
end

function Gen4SummaryMenu:drawSkills()
  local mon = self.mon
  local stats = mon.stats or {}
  local hp = tonumber(mon.hp) or 0
  local max = tonumber(mon.maxHp) or tonumber(mon.maxhp) or tonumber(stats.hp) or 0
  self:field("skills", 1, self:word("hp", "HP"),
             ("%d%s%d"):format(hp, self:word("slash", "/"), max))
  self:field("skills", 2, self:word("attack", Strings("Attack")),
             tostring(stats.attack or stats.atk or "-"))
  self:field("skills", 3, self:word("defense", Strings("Defense")),
             tostring(stats.defense or stats.def or "-"))
  self:field("skills", 4, self:word("spAtk", "Sp. Atk"),
             tostring(stats.spAttack or stats.spatk or stats.specialAttack or "-"))
  self:field("skills", 5, self:word("spDef", "Sp. Def"),
             tostring(stats.spDefense or stats.spdef or stats.specialDefense or "-"))
  self:field("skills", 6, self:word("speed", Strings("Speed")),
             tostring(stats.speed or stats.spe or "-"))

  local box = self.layout.skills or FALLBACK_LAYOUT.skills
  Font.draw(self:word("ability", Strings("Ability")), self.layout.label.x, box.ability)
  local def = self:speciesDef()
  local ability = mon.ability or (def and def.abilities and def.abilities[1])
  if ability then
    local list = self.game.data.abilities
    local record = list and list[ability]
    Font.draw(tostring((record and record.name) or ability), 8, box.abilityText)
  end
end

function Gen4SummaryMenu:drawMoves()
  local mon = self.mon
  local moves = mon.moves or {}
  local box = self.layout.moves or FALLBACK_LAYOUT.moves
  for i = 1, box.rows do
    local y = box.first + (i - 1) * box.pitch
    local entry = moves[i]
    if entry then
      local id = (type(entry) == "table" and (entry.id or entry.move)) or entry
      local record = self.game.data.moves and self.game.data.moves[id]
      fitted((record and record.name) or id,180,y+4,68,'centre')
      local pp = type(entry) == "table" and entry.pp or nil
      local maxPp = (record and record.pp) or nil
      if pp or maxPp then
        fitted(("%s%s%s"):format(tostring(pp or "-"), self:word("slash", "/"),
                                    tostring(maxPp or "-")),
                  180,y+18,68,'centre')
      end
      Font.draw(self:word("pp", "PP"), self.layout.value.x - 24, y + 14)
    else
      Font.draw(self:word("dashesLong", "---"), self.layout.label.x, y)
    end
  end
end

-- A cache imported before any of this carries the PLATE'S TOP-LEFT under
-- `picture` rather than the sprite's centre, and the two cannot be told apart
-- by their values.  `plate` is what marks the new shape -- and the fallback is
-- the cartridge's own pair, so an old cache lands in the right place anyway
-- rather than eight pixels up and to the left of it.
function Gen4SummaryMenu:pictureSpot()
  local spot = self.layout.picture
  if type(spot) == "table" and tonumber(spot.plate) then return spot end
  return Gen4SummaryMenu.PICTURE
end

-- The picture, and whether it is mirrored.
--
-- IT IS MIRRORED, AND THAT IS THE CARTRIDGE'S DOING:
-- `monSprite.flip = SpeciesData_GetFormValue(.., SPECIES_DATA_FLIP_SPRITE) ^ 1`
-- (3d_anim.c 337), so the summary reverses every species whose flag is CLEAR
-- -- 480 of the 508 personal records -- and leaves the twenty-eight that are
-- set alone.
--
-- WHAT THE FLAG IS NOT is a facing: the pictures say so outright.  Torterra
-- has it SET and Bulbasaur CLEAR, and both are drawn facing left, so it cannot
-- mean "this art happens to point the other way".
--
-- WHAT IT READS AS is "do not reverse this one", and the members that settle
-- it are the ones a mirror would FALSIFY: UNOWN, whose sprite is a LETTER;
-- SPINDA, whose spots are the whole point of it; the Poliwag line's spiral;
-- Teddiursa's crescent.  Stated as a reading and not a derivation, because the
-- twenty-eight are not all obvious from outside the art team -- Torterra and
-- Chimchar are in the set and I cannot say why.  The CONSEQUENCE is what
-- matters here and it is not in doubt: those species come up facing the other
-- way from the rest of the party, on the cartridge as well as here.
--
-- The byte has been in the cache the whole time: Gen4Species.parse reads it as
-- `flipSprite` off the top bit of the byte that carries bodyColor, and nothing
-- had ever read it back.  On a Gen 1-3 cache there is no such field, and
-- `not nil` is true -- which would mirror Kanto -- so the mirror is asked for
-- only where the field EXISTS, and the caller says which.
function Gen4SummaryMenu:pictureArt()
  local mon, data = self.mon, self.game.data
  if not (mon and data) then return nil, false end
  if Party.isEgg(mon) then
    -- No flip: an egg has no personal record to read a flag out of, and it is
    -- drawn facing nowhere.
    local forms = (data.gen4_species_sprites or {}).forms or {}
    local rec = forms[Gen4SummaryMenu.EGG_KEY]
    return self:image(type(rec) == "table" and rec.front or nil), false
  end
  local path = Sprites.path(data, mon.species, "front",
                            { mon = mon, kind = "summary" })
  local def = data.pokemon and data.pokemon[mon.species]
  local flip = def ~= nil and def.flipSprite ~= nil and not def.flipSprite
  return self:image(path), flip
end

function Gen4SummaryMenu:drawPicture()
  local image, flip = self:pictureArt()
  if not image then return end
  local spot = self:pictureSpot()
  local w, h = image:getDimensions()
  love.graphics.setColor(1, 1, 1, 1)
  -- Drawn from its own centre so the mirror turns it about the middle of the
  -- plate rather than sliding it a picture's width to the left.
  love.graphics.draw(image, spot.x, spot.y, 0, flip and -1 or 1, 1, w / 2, h / 2)
end

function Gen4SummaryMenu:draw()
  local g = love.graphics
  g.setColor(0.08, 0.09, 0.14, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local page = self.pages[self.page] or self.pages[1]
  local back = page and self:img(page.art)
  if back then g.draw(back, 0, 0) else Font.drawBox(0, 0, 32, 24) end

  if not self.mon then
    Font.draw(self:word("unknown", "???"), 100, 90)
    return
  end

  -- The Pokemon itself, on every page: the cartridge only ever takes it down
  -- for the move-info sub-mode, which scrolls the whole left column away and
  -- is not a page this port draws.
  self:drawPicture()

  -- The title, and the name and level in the bar the art leaves for them.
  if page and page.title then
    Font.draw(tostring(page.title), 8, 8)
  end
  local def = self:speciesDef()
  local name = self.mon.nickname or (def and def.name) or tostring(self.mon.species)
  fitted(name,self.layout.name.x,self.layout.name.y,60)
  local level = tonumber(self.mon.level) or 1
  Font.draw(("Lv%d"):format(level), self.layout.name.x + 64, self.layout.name.y)

  local key = page and page.key or "info"
  if key == "info" then self:drawInfo()
  elseif key == "skills" then self:drawSkills()
  else self:drawMoves() end
  g.setColor(1, 1, 1, 1)
end

return Gen4SummaryMenu
