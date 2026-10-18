-- THE PC'S HALL OF FAME (Platinum and HeartGold / SoulSilver): the browser
-- for the recorded teams, opened from the PC once the game is beaten.
--
-- pokeplatinum src/applications/pc_hall_of_fame (display.c, manager.c):
--   * BG2 is dendou_pc.narc (tiles 1, tilemap 0, palette 2), composed by
--     Gen4EndingArt as `hof_pc`; without it the screen is a plain dark fill.
--   * Two standard windows at tiles (1, 1) 30 x 2, the title -- "HALL OF FAME
--     No. n Month d, yyyy" -- and (1, 19) 30 x 4, the Pokemon.
--   * The team at (120, 56) (40, 56) (200, 56) (136, 112) (216, 112)
--     (56, 112), sprite centres; the chosen one solid, the rest
--     half-transparent (OAM XLU), and its cry plays.
--   * The text: nickname at 0, "/" at 72, species at 94, the gender sign at
--     174, "Lv. n" at 194; "OT/" and the trainer on the next line. A swaps
--     to the moves, two to a row 96 apart.
--   * Up / Down step through the team and over into the next entry; Left /
--     Right step entries (wrapping); B leaves.
-- Text: Platinum bank 352, HGSS bank 181 (the same six rows).

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local P = {}
P.__index = P
P.isOpaque = true

P.SPOTS = { { 120, 56 }, { 40, 56 }, { 200, 56 }, { 136, 112 }, { 216, 112 }, { 56, 112 } }

function P:uiSize() return 256, 192 end
function P:wantsFillScale() return true end

local function hgss()
  local ok, GV = pcall(require, "src.core.GameVersion")
  local info = ok and GV.info and GV.info()
  return info and info.family == "hgss"
end

function P.available(game)
  local hof = game and game.save and game.save.hallOfFame
  return type(hof) == "table" and #hof > 0
end

function P.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, data = game.data, save = game.save, onDone = opts.onDone,
    images = {}, bank = hgss() and 181 or 352, moves = false, frame = 0 }, P)
  self.entries = type(game.save.hallOfFame) == "table" and game.save.hallOfFame or {}
  self.entry = #self.entries -- the newest first (the cartridge's entry 0)
  self.index = 1
  self:cry()
  return self
end

function P:image(path)
  if not path then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
  end
  return self.images[path] or nil
end

function P:team() return self.entries[self.entry] or {} end

function P:mon() return self:team()[self.index] end

function P:line(n, ...)
  T.buffer(self.game, ...)
  local s = T.resolve(self.data, self.bank, n, self.game) or ""
  return (s:gsub("[\n\r]", " "))
end

function P:cry()
  local mon = self:mon()
  if mon then pcall(function() require("src.core.Sound").playCry(self.data, mon.species) end) end
end

function P:se(name)
  pcall(function() require("src.core.Sound").playSe(self.data, name) end)
end

-- Left is the next OLDER entry (the cartridge's ++entryIndex), Right newer
function P:stepEntry(dir)
  local n = #self.entries
  if n == 0 then return end
  self.entry = ((self.entry - 1 + dir) % n) + 1
  self.index = 1
end

function P:update()
  self.frame = self.frame + 1
  local input = self.game.input
  if not input then return end
  if input:wasPressed("b") then
    self:se("SEQ_SE_DP_PC_LOGOFF")
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  elseif input:wasPressed("a") then
    self.moves = not self.moves
    self:se("SEQ_SE_CONFIRM")
  elseif input:wasPressed("left") then
    self:stepEntry(-1); self:cry()
  elseif input:wasPressed("right") then
    self:stepEntry(1); self:cry()
  elseif input:wasPressed("up") then
    self.index = self.index - 1
    if self.index < 1 then self:stepEntry(-1); self.index = math.max(1, #self:team()) end
    self:cry()
  elseif input:wasPressed("down") then
    self.index = self.index + 1
    if self.index > #self:team() then self:stepEntry(1) end
    self:cry()
  end
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December" }

function P:title()
  local date = self:team().date or {}
  local month = MONTHS[tonumber(date.month) or 0] or ""
  return self:line(0, tostring(self.entry), tostring(date.year or ""), month, tostring(date.day or ""))
end

local function speciesName(data, species)
  local def = data.pokemon and data.pokemon[species]
  return def and def.name or tostring(species or "")
end

local function moveName(data, id)
  local def = data.moves and data.moves[id]
  return def and def.name or tostring(id)
end

function P:drawText()
  local mon = self:mon()
  -- the title window (tiles 1, 1) and the Pokemon's (1, 19)
  Font.drawBox(0, 0, 32, 4)
  Font.drawBox(0, 18, 32, 6)
  Font.draw(self:title(), 8, 8)
  if not mon then return end
  local x, y = 8, 152
  if self.moves then
    local n = 0
    for _, mv in ipairs(mon.moves or {}) do
      if mv and mv ~= 0 then
        Font.draw(moveName(self.data, mv), x + (n % 2) * 96, y + math.floor(n / 2) * 16)
        n = n + 1
      end
    end
    return
  end
  local species = speciesName(self.data, mon.species)
  Font.draw(mon.nickname or species, x, y)
  Font.draw(self:line(5), x + 72, y)
  Font.draw(species, x + 94, y)
  local sign = mon.gender == "male" and self:line(3) or mon.gender == "female" and self:line(4) or ""
  if sign ~= "" then Font.draw(sign, x + 174, y) end
  Font.draw(self:line(1, tostring(mon.level or "")), x + 194, y)
  local ot = self:line(2)
  Font.draw(ot, x, y + 16)
  Font.draw(mon.otName or (self.save.player or {}).name or "", x + Font.width(ot), y + 16)
end

function P:draw()
  local g = love.graphics
  local art = self.data.gen4_ending_art and self.data.gen4_ending_art.hof_pc
  local bg = art and self:image(art.path)
  if bg then
    g.setColor(1, 1, 1, 1)
    g.draw(bg, 0, 0)
  else
    g.setColor(0.10, 0.12, 0.22, 1)
    g.rectangle("fill", 0, 0, 256, 192)
  end
  local Sprites = require("src.pokemon.Sprites")
  local team = self:team()
  -- the others first, half-transparent, then the chosen one over them
  for pass = 1, 2 do
    for i, mon in ipairs(team) do
      local spot = P.SPOTS[i]
      if spot and ((pass == 2) == (i == self.index)) then
        local okP, path = pcall(Sprites.path, self.data, mon.species, "front", { mon = mon })
        local img = okP and self:image(path)
        if img then
          local w, h = img:getDimensions()
          g.setColor(1, 1, 1, i == self.index and 1 or 0.5)
          g.draw(img, spot[1], spot[2], 0, 1, 1, math.floor(w / 2), math.floor(h / 2))
        end
      end
    end
  end
  g.setColor(1, 1, 1, 1)
  self:drawText()
  g.setColor(1, 1, 1, 1)
end

return P
