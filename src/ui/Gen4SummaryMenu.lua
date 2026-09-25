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

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen4SummaryMenu = {}
Gen4SummaryMenu.__index = Gen4SummaryMenu
Gen4SummaryMenu.isOpaque = true

local W, H = 256, 192

local FALLBACK_LAYOUT = {
  label = { x = 112 }, value = { x = 180 },
  name = { x = 8, y = 42 }, picture = { x = 20, y = 70 },
  info = { first = 40, pitch = 16, rows = 7 },
  skills = { first = 40, pitch = 16, rows = 6, ability = 144, abilityText = 162 },
  moves = { first = 50, pitch = 32, rows = 4 },
}

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

function Gen4SummaryMenu:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
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
  return box.first + (i - 1) * box.pitch
end

function Gen4SummaryMenu:field(page, i, label, value)
  local y = self:row(page, i)
  Font.draw(label, self.layout.label.x, y)
  if value ~= nil then Font.draw(tostring(value), self.layout.value.x, y) end
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
  local max = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
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
      Font.draw(tostring((record and record.name) or id), self.layout.label.x, y)
      local pp = type(entry) == "table" and entry.pp or nil
      local maxPp = (record and record.pp) or nil
      if pp or maxPp then
        Font.draw(("%s%s%s"):format(tostring(pp or "-"), self:word("slash", "/"),
                                    tostring(maxPp or "-")),
                  self.layout.value.x, y + 14)
      end
      Font.draw(self:word("pp", "PP"), self.layout.value.x - 24, y + 14)
    else
      Font.draw(self:word("dashesLong", "---"), self.layout.label.x, y)
    end
  end
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

  -- The title, and the name and level in the bar the art leaves for them.
  if page and page.title then
    Font.draw(tostring(page.title), 8, 8)
  end
  local def = self:speciesDef()
  local name = self.mon.nickname or (def and def.name) or tostring(self.mon.species)
  Font.draw(Font.fit(tostring(name), 96), self.layout.name.x, self.layout.name.y)
  local level = tonumber(self.mon.level) or 1
  Font.draw(("Lv%d"):format(level), self.layout.name.x + 64, self.layout.name.y)

  local key = page and page.key or "info"
  if key == "info" then self:drawInfo()
  elseif key == "skills" then self:drawSkills()
  else self:drawMoves() end
  g.setColor(1, 1, 1, 1)
end

return Gen4SummaryMenu
