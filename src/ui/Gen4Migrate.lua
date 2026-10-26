-- MIGRATE FROM <GAME>: six Pokemon from a Generation III save into this DS
-- save's Pal Park (src/world/Gen4PalPark.lua does the moving).
--
-- The main menu's row, when this save has the National Pokedex, names the
-- Game Pak the way the cartridge does (bank 550 / HGSS 442, lines 4-8); the
-- "Game Pak" here is one of this port's own Ruby / Sapphire / Emerald /
-- FireRed / LeafGreen saves. Every message is the cartridge's (bank 454 /
-- HGSS 301): the question, the refusals (a stocked Game Card, a Game Pak that
-- migrated today, fewer than six in its PC, an Egg, an HM move), "CANNOT be
-- returned", the save, and "Six Pokemon safely migrated".

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local M = {}
M.__index = M
M.isOpaque = true

local W, H = 256, 192
M.BANKS = { platinum = { menu = 550, text = 454 }, hgss = { menu = 442, text = 301 } }
M.MENU_LINE = { ruby = 4, sapphire = 5, leafgreen = 6, firered = 7, emerald = 8 }
M.ASK_LINE = { ruby = 0, sapphire = 1, emerald = 2, firered = 3, leafgreen = 4 }
M.SAVING_LINE = { ruby = 18, sapphire = 20, emerald = 22, firered = 24, leafgreen = 26 }
M.LINE = { fewer = 5, choose = 6, stocked = 7, egg = 8, hm = 9, chosen = 10,
           done = 29, today = 31, confirm = 34, failed = 36, unreadable = 37 }
M.ROWS = 9

function M:uiSize() return W, H end
function M:wantsFillScale() return true end

local function family()
  return require("src.import.Gen4ScriptBands").family == "hgss" and "hgss" or "platinum"
end

-- a line of the cartridge's own, its {STRVAR}s filled in order
function M.text(data, kind, line, ...)
  local bank = M.BANKS[family()][kind]
  local s = data and data.text and data.text[("TEXT_B%04d_%05d"):format(bank, line)]
  if type(s) ~= "string" then return nil end
  local args, i = { ... }, 0
  s = s:gsub("{STRVAR_1[^}]*}", function()
    i = i + 1
    return args[i] ~= nil and tostring(args[i]) or ""
  end):gsub("{YESNO[^}]*}", "")
  return s
end

-- the main menu's MIGRATE FROM rows: one per Gen III game with a save, when
-- this save has the National Pokedex
function M.menuItems(game)
  local GameVersion = require("src.core.GameVersion")
  if not GameVersion.isGen4() then return {} end
  local okS, save = pcall(require("src.core.SaveData").load)
  if not (okS and type(save) == "table" and save.pokedex and save.pokedex.national) then return {} end
  local PalPark = require("src.world.Gen4PalPark")
  local seen, rows = {}, {}
  for _, src in ipairs(PalPark.sources()) do
    if not seen[src.version] then
      seen[src.version] = true
      local label = M.text(game.data, "menu", M.MENU_LINE[src.version] or 4)
                    or Strings("MIGRATE FROM %s", src.version:upper())
      rows[#rows + 1] = { key = "migrate_" .. src.version, label = label, lines = 1,
        onSelect = function() game.stack:push(M.new(game, src.version, src.slot)) end }
    end
  end
  return rows
end

function M.new(game, version, slot)
  local self = setmetatable({ game = game, version = version, slot = slot,
                              box = 1, index = 1, scroll = 0, picks = {} }, M)
  local okS, save = pcall(require("src.core.SaveData").load)
  self.save = (okS and type(save) == "table" and save) or game.save
  self.started = false
  return self
end

function M:say(line, after, ...)
  local s = M.text(self.game.data, "text", line, ...) or Strings("...")
  self.game.stack:push(TextBox.new(self.game, s, after))
end

function M:ask(line, onYes, onNo, ...)
  local s = M.text(self.game.data, "text", line, ...) or Strings("OK?")
  self.game.stack:push(TextBox.new(self.game, s, nil, { choice = function(yes)
    if yes then onYes() elseif onNo then onNo() end
  end }))
end

function M:close()
  for i = #self.game.stack.states, 1, -1 do
    if self.game.stack.states[i] == self then table.remove(self.game.stack.states, i) break end
  end
end

-- the Game Pak's PC, grouped by box
function M:load()
  local Link = require("src.pokewalker.WalkerLink")
  local mons, why = Link.boxMons(self.version, self.slot)
  if not mons then return nil, why end
  local PalPark = require("src.world.Gen4PalPark")
  self.src = PalPark.sourceData(self.version)
  self.boxes = {}
  for _, e in ipairs(mons) do
    local b = e.source.box
    self.boxes[b] = self.boxes[b] or {}
    local list = self.boxes[b]
    local def = self.game.data.pokemon[e.species]
    e.label = (e.raw.nickname and e.raw.nickname ~= "" and e.raw.nickname) or (def and def.name) or e.name
    if not e.raw.level and e.raw.exp and def then
      e.level = require("src.pokemon.Growth").levelForExp(def.growthRate, e.raw.exp)
    end
    list[#list + 1] = e
  end
  self.boxOrder = {}
  for b in pairs(self.boxes) do self.boxOrder[#self.boxOrder + 1] = b end
  table.sort(self.boxOrder)
  -- the Monster Walker's catches, one more box (src/pokemon/CrossGen.lua)
  local walker = require("src.pokemon.CrossGen").walkerEntries(self.game, 493)
  if #walker > 0 then
    self.boxes.walker = walker
    self.boxOrder[#self.boxOrder + 1] = "walker"
  end
  return #mons + #walker
end

function M:begin()
  self.started = true
  local PalPark = require("src.world.Gen4PalPark")
  -- the Game Pak's own trainer: "migrate from MAY's Emerald Game Pak?"
  local okG, gba = pcall(function()
    local p = require("src.core.SaveData").slotDiskPath(self.version, self.slot)
    local f = io.open(p, "rb"); local b = f:read("*a"); f:close()
    return require("src.core.SaveSerializer").decode(b)
  end)
  local trainer = okG and type(gba) == "table" and gba.player and gba.player.name or ""
  self:ask(M.ASK_LINE[self.version] or 0, function()
    if PalPark.count(self.save) > 0 then return self:say(M.LINE.stocked, function() self:close() end) end
    local n = self:load()
    if not n then return self:say(M.LINE.unreadable, function() self:close() end) end
    if okG and gba and PalPark.wait(self.save, PalPark.sourceKey(self.version, gba)) > 0 then
      return self:say(M.LINE.today, function() self:close() end)
    end
    if n < PalPark.MONS then return self:say(M.LINE.fewer, function() self:close() end) end
    self:say(M.LINE.choose)
  end, function() self:close() end, trainer)
end

function M:current()
  local b = self.boxOrder and self.boxOrder[self.box]
  return b and self.boxes[b] or {}, b
end

function M:picked(e)
  for i, p in ipairs(self.picks) do if p == e then return i end end
  return nil
end

function M:toggle(e)
  local at = self:picked(e)
  if at then table.remove(self.picks, at) return end
  local PalPark = require("src.world.Gen4PalPark")
  local why = not e.walker and PalPark.refusal(self.src, e.raw) or nil
  if why == "egg" then return self:say(M.LINE.egg) end
  if why == "hm" then return self:say(M.LINE.hm) end
  if #self.picks >= PalPark.MONS then return end
  self.picks[#self.picks + 1] = e
  if #self.picks == PalPark.MONS then
    self:say(M.LINE.chosen, function()
      self:ask(M.LINE.confirm, function() self:commit() end, function() table.remove(self.picks) end)
    end)
  end
end

function M:commit()
  local PalPark = require("src.world.Gen4PalPark")
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")
  local picks = {}
  for i, e in ipairs(self.picks) do
    picks[i] = e.walker and { walker = e.walker, entry = e.entry }
               or { box = e.source.box, index = e.source.index }
  end
  local ok, why = PalPark.migrate({ save = self.save, data = self.game.data }, self.version, self.slot, picks)
  if not ok then
    local line = (why == "today" and M.LINE.today) or (why == "egg" and M.LINE.egg)
                 or (why == "hm" and M.LINE.hm) or (why == "parkFull" and M.LINE.stocked) or M.LINE.failed
    return self:say(line, function() self:close() end)
  end
  local written = SaveData.writeSlot(GameVersion.get(), SaveData.activeSlot(), self.save)
  if not written then return self:say(M.LINE.failed, function() self:close() end) end
  self:say(M.LINE.done, function() self:close() end)
end

function M:update()
  if not self.started then return self:begin() end
  local input = self.game.input
  if not (input and self.boxOrder) then return end
  local list = self:current()
  if input:wasPressed("left") and self.box > 1 then self.box, self.index, self.scroll = self.box - 1, 1, 0 end
  if input:wasPressed("right") and self.box < #self.boxOrder then self.box, self.index, self.scroll = self.box + 1, 1, 0 end
  if input:wasPressed("up") and self.index > 1 then self.index = self.index - 1 end
  if input:wasPressed("down") and self.index < #list then self.index = self.index + 1 end
  if self.index < self.scroll + 1 then self.scroll = self.index - 1 end
  if self.index > self.scroll + M.ROWS then self.scroll = self.index - M.ROWS end
  if input:wasPressed("a") and list[self.index] then self:toggle(list[self.index]) end
  if input:wasPressed("b") then
    if #self.picks > 0 then table.remove(self.picks) else self:close() end
  end
end

local function window(x, y, w, h)
  local g = love.graphics
  g.setColor(0.97, 0.97, 0.97, 1); g.rectangle("fill", x, y, w, h, 3, 3)
  g.setColor(0.29, 0.33, 0.42, 1); g.setLineWidth(2); g.rectangle("line", x + 1, y + 1, w - 2, h - 2, 3, 3)
  g.setLineWidth(1)
end

function M:draw()
  local g = love.graphics
  g.setColor(0.39, 0.39, 1, 1)
  g.rectangle("fill", 0, 0, W, H)
  if not self.boxOrder then g.setColor(1, 1, 1, 1) return end
  local list, b = self:current()
  window(8, 6, 240, 22)
  g.setColor(0.2, 0.2, 0.2, 1)
  Font.draw(b == "walker" and Strings("MONSTER WALKER") or Strings("BOX %d", b or 0), 16, 11)
  local count = ("%d/6"):format(#self.picks)
  Font.draw(count, 240 - (Font.width and Font.width(count) or 24), 11)
  if self.box > 1 then Font.draw("<", 90, 11) end
  if self.box < #self.boxOrder then Font.draw(">", 160, 11) end
  window(8, 32, 240, 154)
  for row = 1, M.ROWS do
    local i = self.scroll + row
    local e = list[i]
    if not e then break end
    local y = 38 + (row - 1) * 16
    if i == self.index then
      g.setColor(0.55, 0.75, 1, 0.6); g.rectangle("fill", 12, y - 2, 232, 15)
    end
    g.setColor(0.2, 0.2, 0.2, 1)
    if self:picked(e) then Font.draw("*", 18, y) end
    Font.draw(tostring(e.label or "?"), 30, y)
    Font.draw(Strings("Lv.%d", tonumber(e.level) or 1), 196, y)
  end
  g.setColor(1, 1, 1, 1)
end

return M
