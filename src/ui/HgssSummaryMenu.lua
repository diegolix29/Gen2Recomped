-- HEARTGOLD / SOULSILVER'S POKEMON SUMMARY, over Platinum's
-- (src/ui/Gen4SummaryMenu.lua) for what does not change -- the species, the
-- dex number, the types, the memo's lines (bank 302 is numbered as Platinum's
-- bank 455 is), the HP and EXP arithmetic, the picture and its mirroring.
--
-- THE PAGES ARE HGSS's (`_021039B8`): three, not eight, each over both screens.
--
--   page     top screen (/a/1/6/2)           touch screen
--   INFO     13: trainer memo + the Pokemon  12: dex no. .. to next lv., EXP
--   MOVES    19: stats + ability             17: the four battle moves
--   RIBBONS  10                              9  (only with a ribbon)
--
-- The right-hand column is the same on every page: on top the ball, name,
-- gender, level, picture and held item; below, the party's six icons in their
-- boxes (tap one to switch) and Cancel. Tabs and Cancel are touch rectangles
-- from the art; the pad does what Platinum's does (left / right pages, up /
-- down the party, B leaves). The words are bank 302; abilities 720 / 722.
--
-- One screen: the touch page is shown, SELECT swaps to the top one.
--
-- MEASURED off the art and Bulbapedia's captures of the cartridge, not read
-- from code (the summary is still assembly): every text position.
--
-- MOVES: A, or a tap on a move, opens its details where the party was
-- (category, power, accuracy, description, the Pokemon's icon and the move's
-- type), the chosen move in a red frame; A on a move then another SWITCHES
-- them (the Switch button under the list starts the same). B goes back.
--
-- LEARNING A MOVE (`choose`, as Gen3MoveLearnMenu asks): the moves page with
-- its fifth row (screen 18) holding the move being offered; A or a tap on one
-- of the four forgets it, on the fifth -- or B -- refuses.
--
-- STAND-IN, said so: the details panel is drawn in the page's own colours
-- after the capture; its art (one of the small screens 69-75 or the 512 x 512
-- layer 21) has not been paired yet.

local Gen4SummaryMenu = require("src.ui.Gen4SummaryMenu")
local Font = require("src.render.Font")
local Party = require("src.pokemon.Party")
local SecondScreen = require("src.ui.SecondScreen")

local HgssSummaryMenu = setmetatable({}, { __index = Gen4SummaryMenu })
HgssSummaryMenu.__index = HgssSummaryMenu
HgssSummaryMenu.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local BANK = 302
local B = { item = 4, none = 6, info = 7, dexNo = 8, name = 10, type = 12, ot = 13, idNo = 15,
            exp = 17, toNext = 19, unknown = 22, memo = 23, skills = 109, hp = 110, attack = 111,
            defense = 112, spAtk = 113, spDef = 114, speed = 115, ability = 116, slash = 117,
            moves = 128, pp = 135, cancel = 146, dashes = 153, ribbons = 179, male = 1, female = 2 }

local PAGES = {
  { key = "info", top = "top_info", touch = "touch_info", touchTwo = "touch_info_two", title = B.memo, sub = B.info },
  { key = "skills", top = "top_skills", touch = "touch_moves", touchTwo = "touch_moves_two", title = B.skills, sub = B.moves },
  { key = "ribbons", top = "top_ribbons", touch = "touch_ribbons", title = B.ribbons, sub = B.ribbons },
}

-- the right-hand column, top screen
local BALL_AT, NAME_AT, GENDER_RIGHT, LV_AT = { 168, 39 }, { 176, 32 }, 249, { 165, 50 }
local PICTURE_AT, ITEM_LABEL, ITEM_VALUE = { 211, 102 }, { 160, 159 }, { 160, 176 }
local HEADER_AT = { 160, 8 }
-- the touch screen's right-hand column: the party (`ov` icon templates)
local PARTY_AT = { { 184, 50 }, { 224, 58 }, { 184, 82 }, { 224, 90 }, { 184, 114 }, { 224, 122 } }
local BOX_W, BOX_H = 36, 28
local CANCEL = { 165, 188, 190, 249 }
local TABS = { { 166, 190, 4, 44 }, { 166, 190, 52, 92 }, { 166, 190, 100, 140 } }
-- info grid (touch): labels x 4, values centred on 66..143
local INFO_ROW = { 9, 25, 41, 57, 73 }
local VALUE_L, VALUE_R = 66, 143
local EXP_LABEL_Y, EXP_VALUE_Y, NEXT_LABEL_Y, NEXT_VALUE_Y = 89, 105, 121, 137
local EXP_BAR = { 72, 154, 64, 3 }
-- skills (top)
local STAT_ROW = { 24, 49, 65, 81, 97, 113 }
local STAT_LABEL_X, STAT_RIGHT, HP_RIGHT = 22, 141, 141
local HP_BAR = { 80, 42, 48, 3 }
local ABILITY_Y, ABILITY_VALUE_X, ABILITY_DESC_Y = 136, 72, 153
-- moves (touch)
local MOVE_Y = { 11, 43, 75, 107 }
local MOVE_NAME_X, PP_LABEL_X, PP_RIGHT = 40, 59, 110
local MEMO_SHIFT = -14
local MOVE_ROWS = { { 8, 39 }, { 40, 71 }, { 72, 103 }, { 104, 135 }, { 152, 184 } }
local MOVE_X = { 8, 127 }
local SWITCH_RECT = { 138, 150, 10, 86 }
-- the details panel (touch, right column), after the capture
local PANEL = { 130, 8, 126, 152 }
local DETAIL_ROWS = { 32, 48, 64 }
local DETAIL_LABEL_X, DETAIL_RIGHT, DETAIL_DESC_Y = 143, 248, 84

local function inRect(r, p) return p.y >= r[1] and p.y <= r[2] and p.x >= r[3] and p.x <= r[4] end

function HgssSummaryMenu.new(game, arg)
  local self = Gen4SummaryMenu.new(game, arg)
  setmetatable(self, HgssSummaryMenu)
  self.hg = (game.data or {}).gen4_hgss_summary_art or {}
  self.hgPage = 1
  self.showTop = false
  if type(arg) == "table" and arg.species == nil and type(arg.choose) == "table" then
    self.choose = arg.choose
    self.hgPage = 2
    self.moveMode, self.moveIndex = true, 1
  end
  return self
end

function HgssSummaryMenu:w(index, fallback)
  local text = ((self.game.data or {}).text or {})[("TEXT_B%04d_%05d"):format(BANK, index)]
  if type(text) ~= "string" or text == "" then return fallback end
  return (text:gsub("{[^}]*}", ""))
end

function HgssSummaryMenu:hgImg(key)
  local rec = self.hg[key]
  if type(rec) ~= "table" then return nil end
  return self:image(rec.path), rec
end

function HgssSummaryMenu:pagesShown()
  local out = { 1, 2 }
  if not Party.isEgg(self.mon) and #self:ribbonList() > 0 then out[#out + 1] = 3 end
  if Party.isEgg(self.mon) then out = { 1 } end
  return out
end

function HgssSummaryMenu:setPage(p)
  for _, q in ipairs(self:pagesShown()) do
    if q == p and p ~= self.hgPage then
      self.hgPage = p
      local ok, Sound = pcall(require, "src.core.Sound")
      if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, "SEQ_SE_DP_SELECT5") end
      return
    end
  end
end

function HgssSummaryMenu:stepPage(delta)
  local shown = self:pagesShown()
  for i, q in ipairs(shown) do
    if q == self.hgPage then return self:setPage(shown[(i - 1 + delta) % #shown + 1]) end
  end
  self.hgPage = shown[1]
end

function HgssSummaryMenu:switchTo(mon)
  local party = (self.game.save or {}).party or {}
  for _, m in ipairs(party) do
    if m == mon and m ~= self.mon then
      self.mon = mon
      self.ribbonIndex = 1
      if self.cry and self.cry.stop then self.cry:stop() end
      if not Party.isEgg(mon) then self.cry = require("src.core.Sound").playCry(self.game.data, mon.species) end
    end
  end
  local ok = false
  for _, q in ipairs(self:pagesShown()) do if q == self.hgPage then ok = true end end
  if not ok then self.hgPage = 1 end
end

-- --------------------------------------------------------------- input --

function HgssSummaryMenu:sfx(name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

function HgssSummaryMenu:moveCount()
  return self.choose and 5 or 4
end

-- the summary's answer to a move-learning ask: a slot, or nil to refuse
function HgssSummaryMenu:answer(index)
  local choose = self.choose
  self.choose = nil
  if self.cry and self.cry.stop then self.cry:stop() end
  self.game.stack:pop()
  if choose and choose.onChoose then choose.onChoose(index) end
end

function HgssSummaryMenu:pickMove(index)
  local moves = self.mon.moves or {}
  if self.choose then
    self:sfx("SEQ_SE_DP_DECIDE")
    return self:answer(index <= 4 and moves[index] and index or nil)
  end
  if index > 4 or not moves[index] then return end
  if self.readOnlyMoves then return end
  self:sfx("SEQ_SE_DP_DECIDE")
  if self.swapMove then
    moves[index], moves[self.swapMove] = moves[self.swapMove], moves[index]
    self.swapMove = nil
  else
    self.swapMove = index
  end
end

function HgssSummaryMenu:moveInput(input, tap)
  local count = self:moveCount()
  if tap then
    for i = 1, count do
      local r = MOVE_ROWS[i]
      if tap.y >= r[1] and tap.y <= r[2] and tap.x >= MOVE_X[1] and tap.x <= MOVE_X[2] then
        if i == self.moveIndex or self.choose or self.swapMove then return self:pickMove(i) end
        self.moveIndex = i
        return self:sfx("SEQ_SE_DP_SELECT")
      end
    end
    if not self.choose and inRect(SWITCH_RECT, tap) then return self:pickMove(self.moveIndex) end
    if inRect(CANCEL, tap) then
      if self.choose then return self:answer(nil) end
      self.moveMode, self.swapMove = nil, nil
      return self:sfx("SEQ_SE_DP_SYU01")
    end
    return
  end
  if not input then return end
  if input:wasPressed("up") then self.moveIndex = (self.moveIndex - 2) % count + 1; self:sfx("SEQ_SE_DP_SELECT")
  elseif input:wasPressed("down") then self.moveIndex = self.moveIndex % count + 1; self:sfx("SEQ_SE_DP_SELECT")
  elseif input:wasPressed("a") then self:pickMove(self.moveIndex)
  elseif input:wasPressed("b") then
    if self.choose then return self:answer(nil) end
    if self.swapMove then self.swapMove = nil; return self:sfx("SEQ_SE_DP_DECIDE") end
    self.moveMode = nil
    self:sfx("SEQ_SE_DP_SYU01")
  elseif input:wasPressed("select") then self.showTop = not self.showTop
  end
end

function HgssSummaryMenu:update()
  self.t = (self.t or 0) + 1
  local tap = self.tapAt
  self.tapAt = nil
  if self.moveMode then return self:moveInput(self.game.input, tap) end
  if tap then
    -- a move on the moves page opens its details
    if self.hgPage == 2 and not Party.isEgg(self.mon) then
      for i = 1, 4 do
        local r = MOVE_ROWS[i]
        if tap.y >= r[1] and tap.y <= r[2] and tap.x >= MOVE_X[1] and tap.x <= MOVE_X[2] and (self.mon.moves or {})[i] then
          self.moveMode, self.moveIndex = true, i
          return self:sfx("SEQ_SE_DP_SYU01")
        end
      end
    end
    if inRect(CANCEL, tap) then return self:close() end
    for i, r in ipairs(TABS) do if inRect(r, tap) then return self:setPage(i) end end
    local party = (self.game.save or {}).party or {}
    for i, at in ipairs(PARTY_AT) do
      if party[i] and math.abs(tap.x - at[1]) <= BOX_W / 2 and math.abs(tap.y - at[2]) <= BOX_H / 2 then
        return self:switchTo(party[i])
      end
    end
    return
  end
  local input = self.game.input
  if not input then return end
  if input:wasPressed("right") then self:stepPage(1)
  elseif input:wasPressed("left") then self:stepPage(-1)
  elseif input:wasPressed("up") then self:changePokemon(-1); self:switchTo(self.mon)
  elseif input:wasPressed("down") then self:changePokemon(1); self:switchTo(self.mon)
  elseif input:wasPressed("select") then self.showTop = not self.showTop
  elseif input:wasPressed("a") and self.hgPage == 2 and not Party.isEgg(self.mon) then
    self.moveMode, self.moveIndex = true, 1
    self:sfx("SEQ_SE_DP_SYU01")
  elseif input:wasPressed("b") then
    local ok, Sound = pcall(require, "src.core.Sound")
    if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, "SEQ_SE_DP_DECIDE") end
    self:close()
  end
end

function HgssSummaryMenu:bottomOnSecond()
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

function HgssSummaryMenu:touchpressed(id, px, py)
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
function HgssSummaryMenu:touchmoved() return false end
function HgssSummaryMenu:touchreleased() return false end

-- ---------------------------------------------------------------- draw --

function HgssSummaryMenu:put(style, s, x, y)
  Font.pushStyle(self.ink[style] or self.ink.black)
  Font.draw(tostring(s), x, y)
  Font.popStyle()
end

function HgssSummaryMenu:putRight(style, s, right, y)
  s = tostring(s)
  self:put(style, s, right - Font.width(s), y)
end

function HgssSummaryMenu:putCentre(style, s, l, r, y)
  s = tostring(s)
  self:put(style, s, l + floor((r - l - Font.width(s)) / 2), y)
end

function HgssSummaryMenu:fill(rect, cur, max, colour)
  local px = 0
  if max and max > 0 then px = math.max(cur > 0 and 1 or 0, floor(cur * rect[3] / max)) end
  px = math.min(rect[3], px)
  love.graphics.setColor(colour)
  love.graphics.rectangle("fill", rect[1], rect[2], px, rect[4])
  love.graphics.setColor(1, 1, 1, 1)
end

function HgssSummaryMenu:ability()
  local mon, def = self.mon, self:speciesDef()
  local ability = mon.ability or (def and def.abilities and def.abilities[1])
  if not ability then return nil end
  local id = tonumber(ability)
  if not id then
    for number, name in pairs(require("src.import.Gen4Abilities").NAMES) do
      if name == ability then id = number; break end
    end
  end
  local text = self.game.data.text or {}
  if id then return text[("TEXT_B0720_%05d"):format(id)] or ability, text[("TEXT_B0722_%05d"):format(id)] end
  return tostring(ability), nil
end

-- the right-hand column on top: ball, name, gender, level, picture, item
function HgssSummaryMenu:drawMonColumn()
  local mon = self.mon
  local egg = Party.isEgg(mon)
  local ball = self:caughtBall()
  local img, rec = self:hgImg("ball_" .. ball)
  love.graphics.setColor(1, 1, 1, 1)
  if img then love.graphics.draw(img, BALL_AT[1] + (rec.originX or 0), BALL_AT[2] + (rec.originY or 0)) end
  local def = self:speciesDef()
  local name = egg and "Egg" or mon.nickname or (def and def.name) or tostring(mon.species)
  self:put("white", name, NAME_AT[1], NAME_AT[2])
  if not egg and not mon.hideGender then
    local gender = require("src.pokemon.DayCare").gender(self.game.data, mon)
    if gender == "male" or gender == "female" then
      self:putRight(gender == "male" and "blue" or "red", self:w(gender == "male" and B.male or B.female, gender == "male" and "♂" or "♀"), GENDER_RIGHT, NAME_AT[2])
    end
    self:put("black", "Lv." .. tostring(tonumber(mon.level) or 1), LV_AT[1], LV_AT[2])
  end
  local image, flip = self:pictureArt()
  if image then
    local w, h = image:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, PICTURE_AT[1], PICTURE_AT[2], 0, flip and -1 or 1, 1, w / 2, h / 2)
  end
  if not egg then
    self:put("white", self:w(B.item, "Item"), ITEM_LABEL[1], ITEM_LABEL[2])
    local held = mon.item or mon.heldItem
    local item = held and self.game.data.items and self.game.data.items[held]
    self:put("black", (item and item.name) or self:w(B.none, "None"), ITEM_VALUE[1], ITEM_VALUE[2])
  end
end

function HgssSummaryMenu:drawMemoPage()
  -- Platinum's memo, read out of bank 302 (the same numbering as bank 455)
  local data = self.game.data
  local text = data.text or {}
  local proxyText = setmetatable({}, { __index = function(_, k)
    if type(k) == "string" then return text[(k:gsub("B0455", "B0302"))] end
    return text[k]
  end })
  local proxyData = setmetatable({ text = proxyText }, { __index = data })
  local probe = setmetatable({ game = { data = proxyData, save = self.game.save } },
                             { __index = self })
  local ok, lines = pcall(Gen4SummaryMenu.memoLines, probe)
  if not ok or type(lines) ~= "table" then return end
  for _, line in ipairs(lines) do
    local y = line.y + MEMO_SHIFT
    if y < 120 then self:put("black", (tostring(line.text):gsub("{[^}]*}", "")), 6, y) end
  end
end

function HgssSummaryMenu:drawSkillsPage()
  local stats = self.mon.stats or {}
  local hp, max = self:hpValues()
  self:put("white", self:w(B.hp, "HP"), STAT_LABEL_X, STAT_ROW[1])
  self:putRight("black", ("%d/%d"):format(hp, max), HP_RIGHT, STAT_ROW[1])
  local px = max > 0 and hp * 48 / max or 0
  local colour = (px > 24) and { 0.36, 0.86, 0.36, 1 } or (px >= 10) and { 0.94, 0.80, 0.16, 1 } or { 0.94, 0.30, 0.25, 1 }
  self:fill(HP_BAR, hp, max, colour)
  local rows = {
    { B.attack, "Attack", stats.attack or stats.atk },
    { B.defense, "Defense", stats.defense or stats.def },
    { B.spAtk, "Sp. Atk", stats.spAttack or stats.spatk or stats.specialAttack },
    { B.spDef, "Sp. Def", stats.spDefense or stats.spdef or stats.specialDefense },
    { B.speed, "Speed", stats.speed or stats.spe },
  }
  for i, r in ipairs(rows) do
    self:put("white", self:w(r[1], r[2]), STAT_LABEL_X, STAT_ROW[i + 1])
    self:putRight("black", tostring(r[3] or "-"), STAT_RIGHT, STAT_ROW[i + 1])
  end
  self:put("white", self:w(B.ability, "Ability"), 2, ABILITY_Y)
  local name, desc = self:ability()
  if name then self:put("black", name, ABILITY_VALUE_X, ABILITY_Y) end
  if type(desc) == "string" then
    local y = ABILITY_DESC_Y
    for line in (desc:gsub("[\v\f]", "\n") .. "\n"):gmatch("([^\n]*)\n") do
      if y < 186 then self:put("black", line, 2, y) end
      y = y + 16
    end
  end
end

function HgssSummaryMenu:drawInfoTouch()
  local mon, def = self.mon, self:speciesDef()
  if Party.isEgg(mon) then return end
  local number = self:dexNumber()
  local shiny = require("src.pokemon.Pokemon").isShiny(mon)
  local player = (self.game.save or {}).player or {}
  local otFemale = mon.otGender == 1 or mon.otGender == "female"
    or (mon.otGender == nil and (player.gender == 1 or player.gender == "female"))
  local labels = { { B.dexNo, "Dex No." }, { B.name, "Name" }, { B.type, "Type" }, { B.ot, "OT" }, { B.idNo, "ID No." } }
  local values = {
    { shiny and "red" or "black", number and ("%03d"):format(number) or self:w(B.unknown, "???") },
    { "black", (def and def.name) or tostring(mon.species) },
    nil,
    { otFemale and "red" or "blue", tostring(mon.otName or mon.ot or player.name or "") },
    { "black", ("%05d"):format((tonumber(mon.otId or player.id) or 0) % 65536) },
  }
  for i, l in ipairs(labels) do
    self:put("white", self:w(l[1], l[2]), 4, INFO_ROW[i])
    local v = values[i]
    if v then self:putCentre(v[1], v[2], VALUE_L, VALUE_R, INFO_ROW[i]) end
  end
  local t1, t2 = self:monTypes()
  local centre, typeY = floor((VALUE_L + VALUE_R) / 2), INFO_ROW[3] + 7
  if t1 and t2 then self:drawType(t1, centre - 17, typeY); self:drawType(t2, centre + 17, typeY)
  elseif t1 then self:drawType(t1, centre, typeY) end
  local Growth = require("src.pokemon.Growth")
  local level, exp = tonumber(mon.level) or 1, tonumber(mon.exp) or 0
  local rate = def and def.growthRate
  local base = Growth.expForLevel(rate, level) or 0
  local nextExp = level < 100 and (Growth.expForLevel(rate, level + 1) or exp) or exp
  self:put("white", self:w(B.exp, "Exp. Points"), 4, EXP_LABEL_Y)
  self:putRight("black", tostring(floor(exp)), VALUE_R - 2, EXP_VALUE_Y)
  self:put("white", self:w(B.toNext, "To Next Lv."), 4, NEXT_LABEL_Y)
  self:putRight("black", tostring(math.max(0, level >= 100 and 0 or nextExp - exp)), VALUE_R - 2, NEXT_VALUE_Y)
  if level < 100 then self:fill(EXP_BAR, math.max(0, exp - base), math.max(1, nextExp - base), { 0.25, 0.70, 0.95, 1 }) end
end

function HgssSummaryMenu:drawMovesTouch()
  local moves = self.mon.moves or {}
  for i = 1, 4 do
    local y = MOVE_Y[i]
    local entry = moves[i]
    local record, id = self:moveRecord(entry)
    if entry and id and id ~= 0 then
      if record then self:drawType(record.type, 24, y + 7) end
      self:put("black", (record and record.name) or tostring(id), MOVE_NAME_X, y)
      local pp = type(entry) == "table" and entry.pp or nil
      local maxPp = record and record.pp
      if maxPp and type(entry) == "table" then
        maxPp = maxPp + math.min(3, math.max(0, tonumber(entry.ppUps) or 0)) * floor(maxPp / 5)
      end
      self:put("black", self:w(B.pp, "PP"), PP_LABEL_X, y + 16)
      self:putRight("black", ("%s/%s"):format(tostring(pp or maxPp or "-"), tostring(maxPp or "-")), PP_RIGHT, y + 16)
    else
      self:put("black", self:w(B.dashes, "--"), MOVE_NAME_X, y)
    end
  end
end

function HgssSummaryMenu:drawPartyColumn()
  local party = (self.game.save or {}).party or {}
  local current = self.mon
  for i, at in ipairs(PARTY_AT) do
    local mon = party[i]
    if mon then
      local saved = self.mon
      self.mon = mon
      self:drawMonIcon(at[1], at[2] - 2)
      self.mon = saved
      if mon == current then
        love.graphics.setColor(0.93, 0.13, 0.13, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", at[1] - BOX_W / 2, at[2] - BOX_H / 2, BOX_W, BOX_H, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end
  self:putCentre("white", self:w(B.cancel, "Cancel"), CANCEL[3], CANCEL[4], CANCEL[1] + 5)
end

function HgssSummaryMenu:drawTop()
  local page = PAGES[self.hgPage] or PAGES[1]
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local back = self:hgImg(page.top)
  if back then g.draw(back, 0, 0) else g.setColor(0.9, 0.9, 0.95, 1); g.rectangle("fill", 0, 0, W, H) end
  if not self.mon then return end
  self:put("white", self:w(page.title, ""), HEADER_AT[1], HEADER_AT[2])
  if page.key == "info" then self:drawMemoPage()
  elseif page.key == "skills" and not Party.isEgg(self.mon) then self:drawSkillsPage() end
  self:drawMonColumn()
end

function HgssSummaryMenu:drawMoveRow(y, entry)
  local record, id = self:moveRecord(entry)
  if entry and id and id ~= 0 then
    if record then self:drawType(record.type, 24, y + 7) end
    self:put("black", (record and record.name) or tostring(id), MOVE_NAME_X, y)
    local pp = type(entry) == "table" and entry.pp or nil
    local maxPp = record and record.pp
    if maxPp and type(entry) == "table" then
      maxPp = maxPp + math.min(3, math.max(0, tonumber(entry.ppUps) or 0)) * floor(maxPp / 5)
    end
    self:put("black", self:w(B.pp, "PP"), PP_LABEL_X, y + 16)
    self:putRight("black", ("%s/%s"):format(tostring(pp or maxPp or "-"), tostring(maxPp or "-")), PP_RIGHT, y + 16)
  else
    self:put("black", self:w(B.dashes, "--"), MOVE_NAME_X, y)
  end
end

-- the details of the move under the cursor, where the party was
function HgssSummaryMenu:drawMoveDetails()
  local g = love.graphics
  local entry = self.moveIndex == 5 and self.choose and self.choose.move or (self.mon.moves or {})[self.moveIndex]
  local record = self:moveRecord(entry)
  local x, y, w, h = PANEL[1], PANEL[2], PANEL[3], PANEL[4]
  g.setColor(0.90, 0.94, 0.94, 1); g.rectangle("fill", x, y, w, h)
  g.setColor(0.26, 0.26, 0.26, 1); g.setLineWidth(1); g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  for i, ry in ipairs(DETAIL_ROWS) do
    g.setColor(0.55, 0.61, 0.68, 1); g.rectangle("fill", x + 1, ry - 2, 78, 16)
    g.setColor(0.81, 0.84, 0.87, 1); g.rectangle("fill", x + 80, ry - 2, w - 81, 16)
  end
  for ly = DETAIL_DESC_Y + 14, y + h - 4, 16 do
    g.setColor(0.78, 0.80, 0.84, 1); g.rectangle("fill", x + 2, ly, w - 4, 1)
  end
  g.setColor(1, 1, 1, 1)
  self:drawMonIcon(x + 30, y + 12)
  if not record then return end
  self:drawType(record.type, x + 84, y + 12)
  self:put("white", self:w(149, "CATEGORY"), DETAIL_LABEL_X, DETAIL_ROWS[1])
  self:drawType(record.class or "status", DETAIL_RIGHT - 18, DETAIL_ROWS[1] + 6)
  self:put("white", self:w(147, "POWER"), DETAIL_LABEL_X, DETAIL_ROWS[2])
  local power = tonumber(record.power) or 0
  self:putRight("black", power > 1 and power or self:w(B.dashes, "---"), DETAIL_RIGHT, DETAIL_ROWS[2])
  self:put("white", self:w(148, "ACCURACY"), DETAIL_LABEL_X, DETAIL_ROWS[3])
  local acc = tonumber(record.accuracy) or 0
  self:putRight("black", acc > 0 and acc or self:w(B.dashes, "---"), DETAIL_RIGHT, DETAIL_ROWS[3])
  local desc = tostring(record.description or ""):gsub("[\v\f]", "\n"):gsub("\n+$", "")
  local ly = DETAIL_DESC_Y
  for line in (desc .. "\n"):gmatch("([^\n]*)\n") do
    if ly < y + h - 12 then self:put("black", line, x + 4, ly) end
    ly = ly + 16
  end
end

function HgssSummaryMenu:drawMoveCursor()
  local r = MOVE_ROWS[self.moveIndex or 1]
  local g = love.graphics
  if self.swapMove then
    local s = MOVE_ROWS[self.swapMove]
    g.setColor(0.25, 0.55, 0.95, 1); g.setLineWidth(2)
    g.rectangle("line", MOVE_X[1] + 1, s[1] + 1, MOVE_X[2] - MOVE_X[1] - 1, s[2] - s[1] - 1, 3, 3)
  end
  g.setColor(0.93, 0.13, 0.13, 1); g.setLineWidth(2)
  g.rectangle("line", MOVE_X[1] + 1, r[1] + 1, MOVE_X[2] - MOVE_X[1] - 1, r[2] - r[1] - 1, 3, 3)
  g.setColor(1, 1, 1, 1)
end

function HgssSummaryMenu:drawTouch()
  local page = PAGES[self.hgPage] or PAGES[1]
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local two = #self:pagesShown() < 3 and page.touchTwo
  local key = self.choose and "touch_moves_learn" or (two or page.touch)
  local back = self:hgImg(key) or self:hgImg(page.touch)
  if back then g.draw(back, 0, 0) else g.setColor(0.9, 0.9, 0.95, 1); g.rectangle("fill", 0, 0, W, H) end
  if not self.mon then return end
  self:put("white", self:w(page.sub, ""), HEADER_AT[1], HEADER_AT[2])
  if page.key == "info" then self:drawInfoTouch()
  elseif page.key == "skills" then
    self:drawMovesTouch()
    if self.choose then self:drawMoveRow(MOVE_ROWS[5][1] + 3, self.choose.move) end
  end
  if self.moveMode then
    self:drawMoveCursor()
    self:drawMoveDetails()
    if not self.choose and not self.readOnlyMoves then
      self:putCentre("white", self:w(194, "Switch"), SWITCH_RECT[3], SWITCH_RECT[4], SWITCH_RECT[1] - 1)
    end
    self:putCentre("white", self:w(B.cancel, "Cancel"), CANCEL[3], CANCEL[4], CANCEL[1] + 5)
  else
    self:drawPartyColumn()
  end
end

function HgssSummaryMenu:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
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

return HgssSummaryMenu
