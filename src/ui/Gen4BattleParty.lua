-- src/ui/Gen4BattleParty.lua
--
-- PLATINUM'S BATTLE PARTY LIST -- the BOTTOM-SCREEN screen POKeMON opens in a
-- battle (src/battle_sub_menus/battle_party*.c), drawn while the battle stays
-- on the top screen.  Its screens (enum BattlePartyScreen):
--
--   party      six panels and CANCEL                (POKEMON_PARTY)
--   select     SHIFT / SUMMARY / CHECK MOVES / CANCEL (SELECT_POKEMON)
--   summary    level, EXP, stats, ability, held item (POKEMON_SUMMARY)
--   moves      the four moves as buttons              (POKEMON_MOVES)
--   movesum    one move's power, accuracy, category   (MOVE_SUMMARY)
--   restore    RESTORE WHICH MOVE?, an ETHER's target (RESTORE_MOVE_PP)
--   learn      the four moves and the one to learn    (LEARN_MOVE)
--   confirm    the move to forget, FORGET / CANCEL    (CONFIRM_LEARN_MOVE)
--
-- and three modes (enum BattlePartyMode):
--
--   switch     (default) pick a Pokemon to SHIFT in
--   useItem    "Use on which Pokemon?" -- the bag's target; an ETHER-type
--              item then asks RESTORE WHICH MOVE?  (opts.itemId, opts.onMove)
--   learnMove  which move to forget for opts.moveId on opts.mon; the answer
--              (1..4, or nil for "don't learn") goes to opts.onChoose
--
-- Everything placed here is the cartridge's number, all out of the decomp:
--   panels       sButtonDimensions, tile (0,0) (16,1) (0,6) (16,7) (0,12)
--                (16,13), 16x6; CANCEL (27,19) 5x5; SHIFT (1,1) 30x17;
--                SUMMARY (0,19), CHECK MOVES (13,19), 13x5; the detail pages'
--                prev (0,19) next (5,19), their SUMMARY / CHECK MOVES at
--                (12,19); move buttons (0,6) (16,6) (0,12) (16,12) 16x6; the
--                move to learn (8,18); FORGET (0,19) 26x5; the move summary's
--                four small move buttons (11|16, 19|21) 5x2
--   panel art    RetrieveButtonData: the Pokemon IN battle on the primary
--                panel, the rest on the ALT one, an empty slot on ALT
--                DISABLED, a fainted one forced onto palette 2, an egg with
--                its HP-bar columns blanked
--   page art     ScreenBackgroundDataMemberIndexes (Gen4BattleArt b*_bg/_fg)
--   slot text    sPartyPokemonScreenWindowTemplates (15x5 at the panel's
--                tile): name at (32, 8) FONT_SUBSCREEN TEXT_COLOR(7, 8, 9),
--                gender FONT_SYSTEM right-aligned at y 8 in (10, 11) / (12,
--                13); HP "cur/max" in special chars at (56, 32); the HP bar
--                at (64, 24), 48 px, colour 1/3/5 with +1 on its top and
--                bottom rows; "Lv" + level at (8, 32) unless a status icon
--                is up
--   page text    sPokemonSummaryScreenWindowTemplates and the rest, palette
--                13 (pl_font 6 with row 9's 10..13 copied in) for the labels
--                and values, palette 9 for the buttons' words
--   sprites      icon centres (16,16) (144,24) (16,64) (144,72) (16,112)
--                (144,120); status icons (28,40) .. (156,144); held item at
--                icon + (8, 8), mail at icon + (16, 8); the select screen's
--                icon at (128, 72); the detail pages' icon (24,12), status
--                (198,20), types (130,16) (164,16), move types (24|152,
--                80|128), the move summary's type (136,48) and class (24,88)
--   cursor       the sScreenCursorPositions tables, through the shared
--                sub-menu cursor (hidden until a key is pressed, hidden again
--                by a tap -- src/ui/Gen4SubMenuCursor.lua)
--   words        bank 3 (battle_party.json)
--
-- Art: gen4_battle_art's bparty_* / b*_bg / b*_fg (src/import/Gen4BattleArt.lua);
-- colours: gen4_battle_anims.partyInk (row 9) and partyInk13 (palette 13);
-- type and category icons: gen4_summary_art type_* / category_*.

local Strings = require("src.core.Strings")
local Cursor = require("src.ui.Gen4SubMenuCursor")

local Gen4BattleParty = {}
Gen4BattleParty.__index = Gen4BattleParty

-- Not opaque: the battle is the top screen and keeps drawing underneath.
Gen4BattleParty.isOpaque = false

Gen4BattleParty.BANK = 3
Gen4BattleParty.TEXT = {
  choose = 6, useOn = 7, pp = 14, shift = 15, male = 16, female = 17, summary = 18,
  checkMoves = 19, noItem = 20, lv = 23, nextLv = 25, hp = 28, slash = 31,
  attack = 32, defense = 34, spAtk = 36, spDef = 38, speed = 40, movePP = 43,
  power = 48, none = 50, accuracy = 51, category = 53, physical = 54,
  status = 55, special = 56, forget = 58, cancel = 59, hm = 60,
  restoreWhich = 94,
}

Gen4BattleParty.PANEL_TILES = {
  { 0, 0 }, { 16, 1 }, { 0, 6 }, { 16, 7 }, { 0, 12 }, { 16, 13 },
}
Gen4BattleParty.ICON = {
  { 16, 16 }, { 144, 24 }, { 16, 64 }, { 144, 72 }, { 16, 112 }, { 144, 120 },
}
Gen4BattleParty.STATUS_AT = {
  { 28, 40 }, { 156, 48 }, { 28, 88 }, { 156, 96 }, { 28, 136 }, { 156, 144 },
}
Gen4BattleParty.CANCEL_AT = { 216, 152 }
Gen4BattleParty.SHIFT_AT = { 8, 8 }
Gen4BattleParty.SUMMARY_AT = { 0, 152 }
Gen4BattleParty.CHECK_AT = { 104, 152 }
Gen4BattleParty.SELECT_ICON = { 128, 72 }
Gen4BattleParty.HP_BAR = 48
Gen4BattleParty.PAGE_ICON = { 24, 12 }
Gen4BattleParty.PAGE_STATUS = { 198, 20 }
Gen4BattleParty.PAGE_TYPES = { { 130, 16 }, { 164, 16 } }
Gen4BattleParty.MOVE_BTN_AT = { { 0, 48 }, { 128, 48 }, { 0, 96 }, { 128, 96 } }
Gen4BattleParty.MOVE_TYPE_AT = { { 24, 80 }, { 152, 80 }, { 24, 128 }, { 152, 128 }, { 88, 176 } }
Gen4BattleParty.LEARN_BTN_AT = { 64, 144 }
Gen4BattleParty.MS_BTN_AT = { { 88, 152 }, { 128, 152 }, { 88, 168 }, { 128, 168 } }

local P = function(n) return { prev = n } end

-- the cursor tables (1-based; party: 7 = CANCEL; select: 1 SHIFT, 2 SUMMARY,
-- 3 CHECK MOVES, 4 CANCEL)
Gen4BattleParty.PARTY_CURSOR = {
  { 8, 8, 120, 40,     up = 7, down = 3, left = 7, right = 2 },
  { 136, 16, 248, 48,  up = 5, down = 4, left = 1, right = 3 },
  { 8, 56, 120, 88,    up = 1, down = 5, left = 2, right = 4 },
  { 136, 64, 248, 96,  up = 2, down = 6, left = 3, right = 5 },
  { 8, 104, 120, 136,  up = 3, down = 2, left = 4, right = 6 },
  { 136, 112, 248, 144, up = 4, down = 7, left = 5, right = 7 },
  { 224, 160, 248, 184, up = 6, down = 1, left = 6, right = 1 },
}
Gen4BattleParty.SELECT_CURSOR = {
  { 16, 16, 240, 136, up = 1, down = P(2), left = 1, right = 1 },
  { 8, 160, 96, 184,  up = 1, down = 2, left = 2, right = 3 },
  { 112, 160, 200, 184, up = 1, down = 3, left = 2, right = 4 },
  { 224, 160, 248, 184, up = 1, down = 4, left = 3, right = 4 },
}
Gen4BattleParty.SUMMARY_CURSOR = {
  { 8, 160, 32, 184,    up = 1, down = 1, left = 1, right = 2 },
  { 48, 160, 72, 184,   up = 2, down = 2, left = 1, right = 3 },
  { 104, 160, 192, 184, up = 3, down = 3, left = 2, right = 4 },
  { 224, 160, 248, 184, up = 4, down = 4, left = 3, right = 4 },
}
Gen4BattleParty.MOVES_CURSOR = {
  { 8, 56, 120, 88,     up = 1, down = 3, left = 1, right = 2 },
  { 136, 56, 248, 88,   up = 2, down = 4, left = 1, right = 2 },
  { 8, 104, 120, 136,   up = 1, down = P(5), left = 3, right = 4 },
  { 136, 104, 248, 136, up = 2, down = P(8), left = 3, right = 4 },
  { 8, 160, 32, 184,    up = 3, down = 5, left = 5, right = 6 },
  { 48, 160, 72, 184,   up = 3, down = 6, left = 5, right = 7 },
  { 104, 160, 192, 184, up = 4, down = 7, left = 6, right = 8 },
  { 224, 160, 248, 184, up = 4, down = 8, left = 7, right = 8 },
}
Gen4BattleParty.MOVESUM_CURSOR = {
  { 92, 157, 124, 165,  up = 1, down = 3, left = 1, right = 2 },
  { 132, 157, 164, 165, up = 2, down = 4, left = 1, right = 5 },
  { 92, 173, 124, 181,  up = 1, down = 3, left = 3, right = 4 },
  { 132, 173, 164, 181, up = 2, down = 4, left = 3, right = 5 },
  { 224, 160, 248, 184, up = 5, down = 5, left = P(4), right = 5 },
}
Gen4BattleParty.RESTORE_CURSOR = {
  { 8, 56, 120, 88,     up = 1, down = 3, left = 1, right = 2 },
  { 136, 56, 248, 88,   up = 2, down = 4, left = 1, right = 2 },
  { 8, 104, 120, 136,   up = 1, down = 5, left = 3, right = 4 },
  { 136, 104, 248, 136, up = 2, down = 5, left = 3, right = 4 },
  { 224, 160, 248, 184, up = P(4), down = 5, left = 5, right = 5 },
}
Gen4BattleParty.LEARN_CURSOR = {
  { 8, 56, 120, 88,     up = 6, down = 3, left = 1, right = 2 },
  { 136, 56, 248, 88,   up = 6, down = 4, left = 1, right = 2 },
  { 8, 104, 120, 136,   up = 1, down = 5, left = 3, right = 4 },
  { 136, 104, 248, 136, up = 2, down = 7, left = 3, right = 4 },
  { 72, 152, 184, 184,  up = 3, down = 5, left = 5, right = 7 },
  { 192, 8, 248, 24,    up = 6, down = P(2), left = 1, right = 6 },
  { 224, 160, 248, 184, up = 4, down = 7, left = 5, right = 7 },
}
Gen4BattleParty.CONFIRM_CURSOR = {
  { 8, 160, 200, 184,   up = 2, down = 1, left = 1, right = 3 },
  { 192, 8, 248, 24,    up = 2, down = P(3), left = 1, right = 2 },
  { 224, 160, 248, 184, up = 2, down = 3, left = 1, right = 3 },
}

-- the touch rects { top, bottom, left, right } (s*ScreenTouchRects)
Gen4BattleParty.PARTY_TOUCH = {
  { 0, 47, 0, 127 }, { 8, 55, 128, 255 }, { 48, 95, 0, 127 },
  { 56, 103, 128, 255 }, { 96, 143, 0, 127 }, { 104, 151, 128, 255 },
  { 152, 191, 216, 255 },
}
Gen4BattleParty.SELECT_TOUCH = {
  { 8, 143, 8, 247 }, { 152, 191, 0, 103 }, { 152, 191, 104, 207 }, { 152, 191, 216, 255 },
}
Gen4BattleParty.SUMMARY_TOUCH = {
  { 152, 191, 0, 39 }, { 152, 191, 40, 79 }, { 152, 191, 96, 199 }, { 152, 191, 216, 255 },
}
Gen4BattleParty.MOVES_TOUCH = {
  { 48, 95, 0, 127 }, { 48, 95, 128, 255 }, { 96, 143, 0, 127 }, { 96, 143, 128, 255 },
  { 152, 191, 0, 39 }, { 152, 191, 40, 79 }, { 152, 191, 96, 199 }, { 152, 191, 216, 255 },
}
Gen4BattleParty.MOVESUM_TOUCH = {
  { 152, 167, 88, 127 }, { 152, 167, 128, 167 }, { 168, 183, 88, 127 }, { 168, 183, 128, 167 },
  { 152, 191, 216, 255 },
}
Gen4BattleParty.RESTORE_TOUCH = {
  { 48, 95, 0, 127 }, { 48, 95, 128, 255 }, { 96, 143, 0, 127 }, { 96, 143, 128, 255 },
  { 152, 191, 216, 255 },
}
Gen4BattleParty.LEARN_TOUCH = {
  { 48, 95, 0, 127 }, { 48, 95, 128, 255 }, { 96, 143, 0, 127 }, { 96, 143, 128, 255 },
  { 144, 191, 64, 191 }, { 0, 39, 184, 255 }, { 152, 191, 216, 255 },
}
Gen4BattleParty.CONFIRM_TOUCH = {
  { 152, 191, 0, 207 }, { 0, 39, 184, 255 }, { 152, 191, 216, 255 },
}

local SCREENS = {
  party = { "PARTY_CURSOR", "PARTY_TOUCH", back = 7 },
  select = { "SELECT_CURSOR", "SELECT_TOUCH", back = 4 },
  summary = { "SUMMARY_CURSOR", "SUMMARY_TOUCH", back = 4 },
  moves = { "MOVES_CURSOR", "MOVES_TOUCH", back = 8 },
  movesum = { "MOVESUM_CURSOR", "MOVESUM_TOUCH", back = 5 },
  restore = { "RESTORE_CURSOR", "RESTORE_TOUCH", back = 5 },
  learn = { "LEARN_CURSOR", "LEARN_TOUCH", back = 7 },
  confirm = { "CONFIRM_CURSOR", "CONFIRM_TOUCH", back = 3 },
}
Gen4BattleParty.SCREENS = SCREENS

function Gen4BattleParty.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4BattleParty)
  self.game = game
  self.battle = opts.battle
  self.onSwitch = opts.onSwitch
  self.onCancel = opts.onCancel
  self.onMove = opts.onMove
  self.onChoose = opts.onChoose
  self.forceSwitch = opts.forceSwitch
  self.mode = opts.mode or "switch"
  self.itemId = opts.itemId
  self.moveId = opts.moveId
  self.index = 1
  self.selectIndex = 1
  self.moveSlot = 1
  self.t = 0
  self.images = {}
  local data = game and game.data or {}
  self.art = data.gen4_battle_art or {}
  self.typeArt = data.gen4_summary_art or {}
  local anims = data.gen4_battle_anims or {}
  self.ink = anims.partyInk or {}
  self.ink13 = anims.partyInk13 or self.ink
  self.cursor = Cursor.new(self.battle or game, Gen4BattleParty.PARTY_CURSOR, 1)
  if self.mode == "learnMove" and opts.mon then
    for i, m in ipairs(self:party()) do if m == opts.mon then self.index = i end end
    self.learner = opts.mon
    self:setScreen("learn")
  else
    self:setScreen("party")
  end
  return self
end

-- Does this cache carry the screen?  BattleState asks before choosing it.
function Gen4BattleParty.available(data)
  local art = data and data.gen4_battle_art
  return art and art.bparty_bg and art.bparty_panel_0_0 and true or false
end

-- ...and its detail pages (an older cache has the list but not these)
function Gen4BattleParty.pagesAvailable(data)
  local art = data and data.gen4_battle_art
  return art and art.bsummary_bg and art.bmoves_bg and art.bparty_movebtn_0 and true or false
end

-- The battle's own surface, so the screen draws in it untranslated.
function Gen4BattleParty:uiSize()
  if self.battle and self.battle.uiSize then return self.battle:uiSize() end
  return 256, 192
end

function Gen4BattleParty:party() return (self.game.save and self.game.save.party) or {} end
function Gen4BattleParty:mon() return self.learner or self:party()[self.index] end

local function isEgg(mon) return require("src.pokemon.Party").isEgg(mon) end

function Gen4BattleParty:text(id, fallback)
  local data = self.game and self.game.data
  local s = data and data.text and data.text[("TEXT_B%04d_%05d"):format(Gen4BattleParty.BANK, id)]
  if type(s) ~= "string" or s == "" then return Strings(fallback) end
  return (s:gsub("{[^}]*}", ""))
end

local function loadImage(self, path)
  if type(path) ~= "string" then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
  end
  return self.images[path] or nil
end

function Gen4BattleParty:image(key)
  local rec = self.art[key]
  local path = type(rec) == "table" and rec.path or rec
  return loadImage(self, path), rec
end

local function rgb(c, fallback)
  c = c or fallback or { 0, 0, 0 }
  return { c[1] / 255, c[2] / 255, c[3] / 255, 1 }
end

function Gen4BattleParty:drawArt(key, x, y)
  local img, rec = self:image(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, math.floor(x + (type(rec) == "table" and rec.originX or 0)),
                     math.floor(y + (type(rec) == "table" and rec.originY or 0)))
  return true
end

-- a gen4_summary_art type_<name> / category_<name> sprite at its position
function Gen4BattleParty:drawTypeArt(key, x, y)
  local rec = self.typeArt[key]
  local img = loadImage(self, type(rec) == "table" and rec.path or rec)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, math.floor(x + (rec.originX or 0)), math.floor(y + (rec.originY or 0)))
  return true
end

-- Is this member the one standing in the battle (or its partner)?
function Gen4BattleParty:inBattle(mon)
  local b = self.battle
  if not (b and mon) then return false end
  if b.player and b.player.mon == mon then return true end
  local partner = b.partnerOf and b.player and b:partnerOf(b.player)
  return partner and partner.mon == mon and true or false
end

function Gen4BattleParty:panelKey(slot)
  local mon = self:party()[slot]
  if not mon then return "bparty_panel_1_3" end
  local a = self:inBattle(mon) and 0 or 1
  local key = ("bparty_panel_%d_0"):format(a)
  if isEgg(mon) then return key .. "_egg" end
  if (tonumber(mon.hp) or 0) <= 0 then return key .. "_fnt" end
  return key
end

-- ---------------------------------------------------------------- words --

local function tone(ink, a, s)
  local Font = require("src.render.Font")
  if ink[a] and ink[s] and Font.beginTwoTone then
    return Font.beginTwoTone(rgb(ink[a]), rgb(ink[s]))
  end
  love.graphics.setColor(0, 0, 0, 1)
  return false
end

function Gen4BattleParty:drawWords(text, x, y, face, a, s, ink)
  local Font = require("src.render.Font")
  local faced = face and Font.pushFace(face)
  local t = tone(ink or self.ink, a, s)
  Font.draw(text, math.floor(x), math.floor(y))
  if t then Font.endTwoTone() end
  if faced then Font.popFace() end
  love.graphics.setColor(1, 1, 1, 1)
end

local function widthIn(face, text)
  local Font = require("src.render.Font")
  local faced = face and Font.pushFace(face)
  local w = Font.width and Font.width(text) or #text * 8
  if faced then Font.popFace() end
  return w
end

-- palette 13 words (labels TEXT_COLOR(15,14,0), values (1,2,0))
function Gen4BattleParty:label(text, x, y) self:drawWords(text, x, y, "system", 15, 14, self.ink13) end
function Gen4BattleParty:value(text, x, y) self:drawWords(text, x, y, "system", 1, 2, self.ink13) end
function Gen4BattleParty:valueRight(text, x, y, w)
  self:value(text, x + w - widthIn("system", text), y)
end
function Gen4BattleParty:labelCentred(text, x, y, w)
  self:label(text, x + math.floor((w - widthIn("system", text)) / 2), y)
end

-- the special-character strip: 0..9, "/" at 10, "Lv" at 11-12
function Gen4BattleParty:glyph(n, x, y, w)
  local img = self:image("bparty_digits")
  if not img then return end
  local iw, ih = img:getDimensions()
  self.quads = self.quads or {}
  local k = n .. ":" .. (w or 8)
  if not self.quads[k] then self.quads[k] = love.graphics.newQuad(n * 8, 0, w or 8, 8, iw, ih) end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, self.quads[k], x, y)
end

function Gen4BattleParty:number(value, cells, pad, x, y)
  local cellsOut = require("src.battle.Gen4Battle").numberCells(value, cells, pad)
  for i, d in ipairs(cellsOut) do
    if d then self:glyph(d, x + (i - 1) * 8, y) end
  end
end

function Gen4BattleParty:genderOf(mon)
  local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
  if okP and Pokemon.genderOf then return Pokemon.genderOf(self.game.data, mon) end
  return mon and mon.gender
end

function Gen4BattleParty:nameOf(mon)
  if isEgg(mon) then return mon.nickname or "EGG" end
  if mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
  return def and def.name or tostring(mon.species)
end

-- SummaryStatus: 1 PAR, 2 FRZ, 3 SLP, 4 PSN, 5 BRN, 6 FNT (0 is Pokerus)
local STATUS_SEQ = { PAR = 1, FRZ = 2, SLP = 3, PSN = 4, TOX = 4, BRN = 5 }
function Gen4BattleParty.statusSeq(mon)
  if not mon or isEgg(mon) then return nil end
  if (tonumber(mon.hp) or 0) <= 0 then return 6 end
  local s = type(mon.status) == "string" and mon.status:upper():sub(1, 3)
  return s and STATUS_SEQ[s] or nil
end

local function maxHPOf(mon) return math.max(1, (mon.stats and mon.stats.hp) or mon.maxHp or 1) end

-- the bar's three rows in palette 9 colour c (1 green, 3 yellow, 5 red)
function Gen4BattleParty:hpBar(mon, x, y)
  local max = maxHPOf(mon)
  local cur = math.max(0, math.min(max, tonumber(mon.hp) or 0))
  local px = math.floor(cur * Gen4BattleParty.HP_BAR / max)
  if px == 0 and cur > 0 then px = 1 end
  if px <= 0 then return end
  local colour = (px > Gen4BattleParty.HP_BAR / 2 and 1) or (px > Gen4BattleParty.HP_BAR / 5 and 3) or 5
  local ink = self.ink
  local edge, body = rgb(ink[colour + 1]), rgb(ink[colour])
  local g = love.graphics
  g.setColor(edge); g.rectangle("fill", x, y + 1, px, 1)
  g.setColor(body); g.rectangle("fill", x, y + 2, px, 2)
  g.setColor(edge); g.rectangle("fill", x, y + 4, px, 1)
  g.setColor(1, 1, 1, 1)
end

-- ----------------------------------------------------------------- icons --

local ICON_TICK = 0.32
function Gen4BattleParty:drawIcon(mon, cx, cy, still)
  local data = self.game.data
  local icons = data.icons
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[mon.species]) or (def and def.icon)
  if isEgg(mon) and icons and icons.bySpecies then
    entry = icons.bySpecies[mon.species == 490 and 495 or 494] or entry
  end
  local path = type(entry) == "table" and entry.image or entry
  local img = loadImage(self, path)
  if not img then return end
  local iw, ih = img:getDimensions()
  local fh = math.min(ih, tonumber(type(entry) == "table" and entry.frameHeight) or 32)
  local frames = math.max(1, math.floor(ih / fh))
  local f = 0
  if not still and (tonumber(mon.hp) or 0) > 0 and frames > 1 then f = math.floor(self.t / ICON_TICK) % frames end
  local q = love.graphics.newQuad(0, f * fh, iw, fh, iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, math.floor(cx - iw / 2), math.floor(cy - fh / 2))
end

function Gen4BattleParty:drawHeld(mon, cx, cy)
  if not mon.item or mon.item == 0 then return end
  local item = self.game.data.items and self.game.data.items[mon.item]
  local mail = item and (item.pocket == "MAIL")
  self:drawArt(mail and "bparty_held_mail" or "bparty_held_item", cx + 8, cy + 8)
end

-- ----------------------------------------------------------- party list --

function Gen4BattleParty:drawSlot(slot)
  local mon = self:party()[slot]
  local tx, ty = Gen4BattleParty.PANEL_TILES[slot][1] * 8, Gen4BattleParty.PANEL_TILES[slot][2] * 8
  self:drawArt(self:panelKey(slot), tx, ty)
  if not mon then return end
  local name = self:nameOf(mon)
  self:drawWords(name, tx + 32, ty + 8, "subscreen", 7, 8)
  if not isEgg(mon) then
    local g = self:genderOf(mon)
    if g == "male" or g == "female" then
      local sym = self:text(g == "male" and Gen4BattleParty.TEXT.male or Gen4BattleParty.TEXT.female,
                            g == "male" and "♂" or "♀")
      local w = widthIn("system", sym)
      self:drawWords(sym, tx + 120 - w, ty + 8, "system",
                     g == "male" and 10 or 12, g == "male" and 11 or 13)
    end
    local max = maxHPOf(mon)
    local cur = math.max(0, math.min(max, tonumber(mon.hp) or 0))
    self:number(cur, 3, "spaces", tx + 56, ty + 32)
    self:glyph(10, tx + 80, ty + 32)
    self:number(max, 3, "none", tx + 88, ty + 32)
    self:hpBar(mon, tx + 64, ty + 24)
    local status = Gen4BattleParty.statusSeq(mon)
    if status then
      local at = Gen4BattleParty.STATUS_AT[slot]
      self:drawArt("bparty_status_" .. status, at[1], at[2])
    else
      self:glyph(11, tx + 8, ty + 32, 16)
      self:number(tonumber(mon.level) or 1, 3, "none", tx + 24, ty + 32)
    end
  end
  local ic = Gen4BattleParty.ICON[slot]
  self:drawIcon(mon, ic[1], ic[2])
  self:drawHeld(mon, ic[1], ic[2])
end

-- the options frame at window (2, 21) 22x2: "Choose a Pokemon." / "Use on
-- which Pokemon?" / "Restore which move?"
function Gen4BattleParty:drawPrompt(text)
  local Font = require("src.render.Font")
  Font.drawDialogueBox(1, 20, 24, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(text, 16, 168)
  love.graphics.setColor(1, 1, 1, 1)
end

-- the error box at window (2, 19) 27x4 (BattlePartyText_DisplayErrorMessage)
function Gen4BattleParty:drawMessage()
  if not self.message then return end
  local Font = require("src.render.Font")
  Font.drawDialogueBox(1, 18, 29, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local y = 152
  for line in (self.message .. "\n"):gmatch("(.-)\n") do
    Font.draw(line, 16, y); y = y + 16
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4BattleParty:drawParty()
  self:drawArt("bparty_bg", 0, 0)
  self:drawArt("bparty_fg", 0, 0)
  for slot = 1, 6 do self:drawSlot(slot) end
  self:drawArt(self.forceSwitch and "bparty_cancel_3" or "bparty_cancel_0",
               Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  if self.mode == "useItem" then
    self:drawPrompt(self:text(Gen4BattleParty.TEXT.useOn, "Use on which POKéMON?"))
  else
    self:drawPrompt(self:text(Gen4BattleParty.TEXT.choose, "Choose a POKéMON."))
  end
end

function Gen4BattleParty:drawSelect()
  local mon = self:mon()
  self:drawArt("bselect_bg", 0, 0)
  self:drawArt("bselect_fg", 0, 0)
  self:drawArt("bparty_shift", Gen4BattleParty.SHIFT_AT[1], Gen4BattleParty.SHIFT_AT[2])
  local egg = mon and isEgg(mon)
  self:drawArt(egg and "bparty_small_3" or "bparty_small_0", Gen4BattleParty.SUMMARY_AT[1], Gen4BattleParty.SUMMARY_AT[2])
  self:drawArt(egg and "bparty_small_3" or "bparty_small_0", Gen4BattleParty.CHECK_AT[1], Gen4BattleParty.CHECK_AT[2])
  self:drawArt("bparty_cancel_0", Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  if mon then
    local name = self:nameOf(mon)
    local g = not egg and self:genderOf(mon)
    local sym = (g == "male" or g == "female")
                and self:text(g == "male" and Gen4BattleParty.TEXT.male or Gen4BattleParty.TEXT.female,
                              g == "male" and "♂" or "♀") or nil
    local sw = widthIn("subscreen", name)
    local gw = sym and widthIn("system", sym) or 0
    local x0 = 80 + math.floor((96 - sw - gw - (sym and 8 or 0)) / 2)
    self:drawWords(name, x0, 32 + 8, "subscreen", 7, 8)
    if sym then
      self:drawWords(sym, x0 + sw + 8, 32 + 8, "system", g == "male" and 10 or 12, g == "male" and 11 or 13)
    end
    local ic = Gen4BattleParty.SELECT_ICON
    self:drawIcon(mon, ic[1], ic[2])
    self:drawHeld(mon, ic[1], ic[2])
  end
  self:buttonWords(self:text(Gen4BattleParty.TEXT.shift, "SHIFT"), 88, 96, 80)
  if not egg then
    self:buttonWords(self:text(Gen4BattleParty.TEXT.summary, "SUMMARY"), 8, 160, 88)
    self:buttonWords(self:text(Gen4BattleParty.TEXT.checkMoves, "CHECK MOVES"), 112, 160, 88)
  end
end

-- PrintButtonText: FONT_SUBSCREEN TEXT_COLOR(7, 8, 9) centred at y + 6
function Gen4BattleParty:buttonWords(text, wx, wy, ww)
  local w = widthIn("subscreen", text)
  self:drawWords(text, wx + math.floor((ww - w) / 2), wy + 6, "subscreen", 7, 8)
end

-- ---------------------------------------------------------- detail pages --

-- PrintPokemonNameHeader in FONT_SYSTEM: the name at (40, 8) in palette 13's
-- (15, 14), the symbol right-aligned in the 72-wide window in (7, 8) / (3, 4);
-- then the icon, the status and the types (BattlePartySprites)
function Gen4BattleParty:drawHeader(mon)
  if not mon then return end
  self:label(self:nameOf(mon), 40, 8)
  if not isEgg(mon) then
    local g = self:genderOf(mon)
    if g == "male" or g == "female" then
      local sym = self:text(g == "male" and Gen4BattleParty.TEXT.male or Gen4BattleParty.TEXT.female,
                            g == "male" and "♂" or "♀")
      self:drawWords(sym, 40 + 72 - widthIn("system", sym), 8, "system",
                     g == "male" and 7 or 3, g == "male" and 8 or 4, self.ink13)
    end
  end
  local ic = Gen4BattleParty.PAGE_ICON
  self:drawIcon(mon, ic[1], ic[2])
  local status = Gen4BattleParty.statusSeq(mon)
  if status then
    local at = Gen4BattleParty.PAGE_STATUS
    self:drawArt("bparty_status_" .. status, at[1], at[2])
  end
  local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
  local types = def and def.types or {}
  local t1, t2 = types[1], types[2]
  if t2 == t1 then t2 = nil end
  local at = Gen4BattleParty.PAGE_TYPES
  if t1 then self:drawTypeArt("type_" .. tostring(t1):lower(), at[1][1], at[1][2]) end
  if t2 then self:drawTypeArt("type_" .. tostring(t2):lower(), at[2][1], at[2][2]) end
end

function Gen4BattleParty:drawPageButtons(middleKey, middleText)
  local many = self:selectableCount() >= 2
  self:drawArt(many and "bparty_prev_0" or "bparty_prev_3", 0, 152)
  self:drawArt(many and "bparty_next_0" or "bparty_next_3", 40, 152)
  self:drawArt(middleKey, 96, 152)
  self:buttonWords(middleText, 104, 160, 88)
  self:drawArt("bparty_cancel_0", Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
end

function Gen4BattleParty:abilityRecord(mon)
  local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
  local ability = mon.ability
  if not ability and def and def.abilities then
    ability = def.abilities[mon.abilitySlot or 1] or def.abilities[1]
  end
  if not ability then return nil end
  local list = self.game.data.abilities
  local record = list and list[ability]
  if record then return record end
  local id = tonumber(ability)
  if not id then
    local okA, A = pcall(require, "src.import.Gen4Abilities")
    for number, name in pairs(okA and A.NAMES or {}) do
      if name == ability then id = number; break end
    end
  end
  local text = self.game.data.text or {}
  if id then
    return { name = text[("TEXT_B0610_%05d"):format(id)] or tostring(ability),
             description = text[("TEXT_B0612_%05d"):format(id)] }
  end
  return { name = tostring(ability) }
end

local function lines(text)
  local out = {}
  for line in (tostring(text or ""):gsub("\r", "") .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return out
end

-- the EXP bar: eight 8-px tiles at map (10..17, 8), each tile 22 + its fill
function Gen4BattleParty:expBar(mon, x, y)
  local img = self:image("bsummary_exp")
  if not img then return end
  local Growth = require("src.pokemon.Growth")
  local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
  local level = tonumber(mon.level) or 1
  local px = 0
  if level < 100 and def then
    local base = Growth.expForLevel(def.growthRate, level)
    local nxt = Growth.expForLevel(def.growthRate, level + 1)
    local exp = tonumber(mon.exp) or base
    if nxt > base then px = math.floor(math.max(0, exp - base) * 64 / (nxt - base)) end
  end
  local iw, ih = img:getDimensions()
  for i = 0, 7 do
    local fill = math.max(0, math.min(8, px - i * 8))
    local q = love.graphics.newQuad(fill * 8, 0, 8, 8, iw, ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, q, x + i * 8, y)
  end
end

function Gen4BattleParty:drawSummary()
  local mon = self:mon()
  local T = Gen4BattleParty.TEXT
  self:drawArt("bsummary_bg", 0, 0)
  self:drawArt("bsummary_fg", 0, 0)
  self:drawPageButtons("bparty_small_0", self:text(T.checkMoves, "CHECK MOVES"))
  if not mon then return end
  self:drawHeader(mon)
  local stats = mon.stats or {}
  local level = tonumber(mon.level) or 1
  -- Lv. (1,4) / value (5,4); NEXT LV (1,6) / value right-aligned in (13,6) 6 wide
  self:label(self:text(T.lv, "Lv."), 8, 32)
  self:label(tostring(level), 40, 32)
  self:label(self:text(T.nextLv, "NEXT LV"), 8, 48)
  local Growth = require("src.pokemon.Growth")
  local def = self.game.data.pokemon and self.game.data.pokemon[mon.species]
  local toNext = 0
  if level < 100 and def then
    toNext = math.max(0, Growth.expForLevel(def.growthRate, level + 1) - (tonumber(mon.exp) or 0))
  end
  self:valueRight(tostring(toNext), 104, 48, 48)
  self:expBar(mon, 80, 64)
  -- HP (21,4) / "cur/max" around a centred slash in (24,4) 7 wide; the bar
  -- in (25,6) 6 wide
  self:label(self:text(T.hp, "HP"), 168, 32)
  local slash = self:text(T.slash, "/")
  local sw = widthIn("system", slash)
  local sx = 192 + math.floor((56 - sw) / 2)
  self:value(slash, sx, 32)
  local cur = tostring(math.max(0, tonumber(mon.hp) or 0))
  self:value(cur, sx - widthIn("system", cur), 32)
  self:value(tostring(maxHPOf(mon)), sx + sw, 32)
  self:hpBar(mon, 200, 48)
  local rows = {
    { T.attack, "ATTACK", stats.attack or stats.atk, 56 },
    { T.defense, "DEFENSE", stats.defense or stats.def, 72 },
    { T.spAtk, "SP. ATK", stats.spAttack or stats.spatk or stats.specialAttack, 88 },
    { T.spDef, "SP. DEF", stats.spDefense or stats.spdef or stats.specialDefense, 104 },
    { T.speed, "SPEED", stats.speed or stats.spe, 120 },
  }
  for _, r in ipairs(rows) do
    self:label(self:text(r[1], r[2]), 168, r[4])
    self:valueRight(tostring(r[3] or "-"), 224, r[4], 24)
  end
  -- ability (1,9), its description (1,11) 18x4, held item (4,16)
  local ab = self:abilityRecord(mon)
  if ab then
    self:label(tostring(ab.name or ""), 8, 72)
    local y = 88
    for _, line in ipairs(lines(ab.description or ab.desc)) do
      if y < 120 then self:value(line, 8, y) end
      y = y + 16
    end
  end
  local item = mon.item and mon.item ~= 0 and self.game.data.items and self.game.data.items[mon.item]
  self:label(item and item.name or self:text(T.noItem, "No item held"), 32, 128)
end

function Gen4BattleParty:moveRecord(entry)
  local id = type(entry) == "table" and entry.id or entry
  local rec = id and self.game.data.moves and self.game.data.moves[id]
  return rec, id
end

function Gen4BattleParty:maxPP(entry, rec)
  local base = rec and tonumber(rec.pp) or 0
  local ups = type(entry) == "table" and tonumber(entry.ppUps) or 0
  return base + math.min(3, math.max(0, ups)) * math.floor(base / 5)
end

-- a move's window (14x5 at the button's tile + 1): the name centred at y 8 in
-- FONT_SUBSCREEN (7,8,9), "PP" at (40,24), "/" at 80, the max after it and
-- the current PP right-aligned against the slash, FONT_SYSTEM (15,14) on 9
function Gen4BattleParty:moveWindow(entry, wx, wy, overridePP)
  local rec = self:moveRecord(entry)
  if not rec then return end
  local name = rec.name or "?"
  self:drawWords(name, wx + math.floor((112 - widthIn("subscreen", name)) / 2), wy + 8, "subscreen", 7, 8)
  local T = Gen4BattleParty.TEXT
  self:drawWords(self:text(T.movePP, "PP"), wx + 40, wy + 24, "system", 15, 14)
  local slash = "/"
  self:drawWords(slash, wx + 80, wy + 24, "system", 15, 14)
  local max = self:maxPP(entry, rec)
  self:drawWords(tostring(max), wx + 80 + widthIn("system", slash), wy + 24, "system", 15, 14)
  local cur = tostring(overridePP or (type(entry) == "table" and entry.pp) or max)
  self:drawWords(cur, wx + 80 - widthIn("system", cur), wy + 24, "system", 15, 14)
end

function Gen4BattleParty:drawMoveButtons(mon, lift)
  local moves = mon and mon.moves or {}
  for i = 1, 4 do
    local at = Gen4BattleParty.MOVE_BTN_AT[i]
    local entry = moves[i]
    local rec = self:moveRecord(entry)
    self:drawArt(rec and "bparty_movebtn_0" or "bparty_movebtn_3", at[1], at[2])
    if rec then
      self:moveWindow(entry, at[1] + 8, at[2])
      local ta = Gen4BattleParty.MOVE_TYPE_AT[i]
      self:drawTypeArt("type_" .. tostring(rec.type or "normal"):lower(), ta[1], ta[2])
    end
  end
end

function Gen4BattleParty:drawMoves()
  local mon = self:mon()
  self:drawArt("bmoves_bg", 0, 0)
  self:drawArt("bmoves_fg", 0, 0)
  self:drawPageButtons("bparty_small_0", self:text(Gen4BattleParty.TEXT.summary, "SUMMARY"))
  if not mon then return end
  self:drawHeader(mon)
  self:drawMoveButtons(mon)
end

-- the move's numbers (RenderMoveSummaryScreen / RenderConfirmLearnMoveScreen)
function Gen4BattleParty:drawMoveDetail(entry, cleared)
  local rec = self:moveRecord(entry)
  local T = Gen4BattleParty.TEXT
  self:label(self:text(T.pp, "PP"), 160, 40)
  self:label(self:text(T.accuracy, "ACCURACY"), 8, 128)
  self:label(self:text(T.power, "POWER"), 8, 104)
  self:labelCentred(self:text(T.category, "CATEGORY"), 8, 64, 96)
  if not rec then return end
  self:label(rec.name or "?", 32, 40)
  if cleared then return end
  -- PP: "cur/max" round a centred slash in (23,5) 5 wide
  local slash = "/"
  local sw = widthIn("system", slash)
  local sx = 184 + math.floor((40 - sw) / 2)
  local max = self:maxPP(entry, rec)
  local cur = tostring(type(entry) == "table" and entry.pp or max)
  self:label(slash, sx, 40)
  self:label(cur, sx - widthIn("system", cur), 40)
  self:label(tostring(max), sx + sw, 40)
  local acc = tonumber(rec.accuracy) or 0
  self:valueRight(acc == 0 and self:text(T.none, "---") or tostring(acc), 80, 128, 24)
  local pow = tonumber(rec.power) or 0
  self:valueRight(pow <= 1 and self:text(T.none, "---") or tostring(pow), 80, 104, 24)
  local class = tostring(rec.class or "physical"):lower()
  local cid = class == "special" and T.special or class == "status" and T.status or T.physical
  local cname = self:text(cid, class:upper())
  self:value(cname, 48 + math.floor((56 - widthIn("system", cname)) / 2), 80)
  local y = 64
  for _, line in ipairs(lines(rec.description)) do
    if y < 144 then self:value(line, 128, y) end
    y = y + 16
  end
  self:drawTypeArt("type_" .. tostring(rec.type or "normal"):lower(), 136, 48)
  self:drawTypeArt("category_" .. class, 24, 88)
end

function Gen4BattleParty:drawMoveSummary()
  local mon = self:mon()
  self:drawArt("bmovesum_bg", 0, 0)
  self:drawArt("bmovesum_fg", 0, 0)
  self:drawArt("bparty_cancel_0", Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  local moves = mon and mon.moves or {}
  for i = 1, 4 do
    local at = Gen4BattleParty.MS_BTN_AT[i]
    self:drawArt(self.moveSlot == i and "bparty_msbtn_2" or "bparty_msbtn_0", at[1], at[2])
  end
  if not mon then return end
  self:drawHeader(mon)
  self:drawMoveDetail(moves[self.moveSlot])
end

function Gen4BattleParty:drawRestore()
  local mon = self:mon()
  self:drawArt("brestore_bg", 0, 0)
  self:drawArt("brestore_fg", 0, 0)
  self:drawArt("bparty_cancel_0", Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  if not mon then return end
  self:drawHeader(mon)
  self:drawMoveButtons(mon)
  self:drawPrompt(self:text(Gen4BattleParty.TEXT.restoreWhich, "Restore which move?"))
end

function Gen4BattleParty:drawLearn()
  local mon = self:mon()
  self:drawArt("blearn_bg", 0, 0)
  self:drawArt("blearn_fg", 0, 0)
  self:drawArt("bparty_cancel_0", Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  if not mon then return end
  self:drawHeader(mon)
  self:drawMoveButtons(mon)
  local at = Gen4BattleParty.LEARN_BTN_AT
  self:drawArt("bparty_learnbtn_0", at[1], at[2])
  local rec = self:moveRecord(self.moveId)
  if rec then
    local pp = tonumber(rec.pp) or 0
    self:moveWindow({ id = self.moveId, pp = pp }, at[1] + 8, at[2], pp)
    local ta = Gen4BattleParty.MOVE_TYPE_AT[5]
    self:drawTypeArt("type_" .. tostring(rec.type or "normal"):lower(), ta[1], ta[2])
  end
end

function Gen4BattleParty:drawConfirm()
  local mon = self:mon()
  local T = Gen4BattleParty.TEXT
  self:drawArt("bconfirm_bg", 0, 0)
  self:drawArt("bconfirm_fg", 0, 0)
  self:drawArt("bparty_confirm_0", 0, 152)
  self:drawArt("bparty_cancel_0", Gen4BattleParty.CANCEL_AT[1], Gen4BattleParty.CANCEL_AT[2])
  local learning = self.moveSlot == 5
  local word = learning and self:text(T.cancel, "CANCEL") or self:text(T.forget, "FORGET")
  self:drawWords(word, 56 + math.floor((96 - widthIn("subscreen", word)) / 2), 160 + 6, "subscreen", 7, 8)
  if not mon then return end
  self:drawHeader(mon)
  local entry = learning and { id = self.moveId } or (mon.moves or {})[self.moveSlot]
  self:drawMoveDetail(entry, self.hmRefused)
  if self.hmRefused then
    local y = 64
    for _, line in ipairs(lines((self:text(T.hm, "HM moves can't be\nforgotten now.")):gsub("[\v\f]", "\n"))) do
      self:value(line, 128, y); y = y + 16
    end
  end
end

function Gen4BattleParty:drawBottom()
  local s = self.screen
  if s == "select" then self:drawSelect()
  elseif s == "summary" then self:drawSummary()
  elseif s == "moves" then self:drawMoves()
  elseif s == "movesum" then self:drawMoveSummary()
  elseif s == "restore" then self:drawRestore()
  elseif s == "learn" then self:drawLearn()
  elseif s == "confirm" then self:drawConfirm()
  else self:drawParty() end
  self:drawMessage()
  if not self.message then self.cursor:draw(self.battle, self.game, self.t) end
end

-- kept for callers that drew the cursor themselves
function Gen4BattleParty:drawCursor(c)
  if not c then return end
  local Gen4Battle = require("src.battle.Gen4Battle")
  local i = Gen4Battle.CURSOR_INSET
  Gen4Battle.drawCursorCorners(self.battle or { game = self.game, data = self.game.data, frame = math.floor(self.t * 60) },
    { left = c[1] - i, top = c[2] - i, right = c[3] + i, bottom = c[4] + i })
end

function Gen4BattleParty:draw()
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return end
  SecondScreen.draw(self.game, function() self:drawBottom() end)
  if SecondScreen.drawFrame then SecondScreen.drawFrame(self.game) end
end

-- ---------------------------------------------------------------- input --

function Gen4BattleParty:pop()
  if self.closed then return false end
  self.closed = true
  local stack = self.game.stack
  if stack and stack.top and stack:top() ~= self then return true end
  if stack then stack:pop() end
  return true
end

function Gen4BattleParty:close()
  if not self:pop() then return end
  if self.mode == "learnMove" then
    if self.onChoose then self.onChoose(nil) end
    return
  end
  if self.onCancel then self.onCancel() end
end

function Gen4BattleParty:handOff(mon)
  if not self:pop() then return end
  if self.onSwitch then self.onSwitch(mon, self) end
end

function Gen4BattleParty:selectableCount()
  local n = 0
  for _, m in ipairs(self:party()) do if m and not isEgg(m) then n = n + 1 end end
  return n
end

-- UpdateSelectedPartyIndex: the next / previous member that is not an egg
function Gen4BattleParty:stepMon(delta)
  local party = self:party()
  local i = self.index
  for _ = 1, 6 do
    i = i + delta
    if i < 1 then i = 6 elseif i > 6 then i = 1 end
    if i == self.index then return false end
    if party[i] and not isEgg(party[i]) then self.index = i; return true end
  end
  return false
end

function Gen4BattleParty:setScreen(name, start)
  self.screen = name
  self.hmRefused = nil
  local sc = SCREENS[name]
  local mon = self:mon()
  local moves = mon and mon.moves or {}
  local enabled
  if name == "party" then
    enabled = function(i)
      if i == 7 then return true end
      return self:party()[i] ~= nil
    end
    start = start or self.index
  elseif name == "select" then
    start = start or self.selectIndex or 1
  elseif name == "moves" or name == "restore" then
    enabled = function(i) return i > 4 or moves[i] ~= nil end
    start = start or (name == "moves" and self.moveSlot) or 1
  elseif name == "movesum" then
    enabled = function(i) return i > 4 or moves[i] ~= nil end
    start = self.moveSlot
  elseif name == "learn" then
    enabled = function(i) return i ~= 6 end
    start = start or self.learnSlot or 1
  elseif name == "confirm" then
    enabled = function(i) return i ~= 2 end
    start = 1
  end
  self.cursor:set(Gen4BattleParty[sc[1]], start or 1, enabled)
end

-- A slot that cannot be selected (CheckCanPartySlotBeSelected: empty) is not
-- a place the cursor or a tap goes.
function Gen4BattleParty:pickSlot(slot)
  if slot == 7 then
    if not self.forceSwitch then Cursor.sound("decide", self.game.data); self:close() end
    return
  end
  local mon = self:party()[slot]
  if not mon then return end
  Cursor.sound("decide", self.game.data)
  self.index = slot
  if self.mode == "useItem" then return self:useOn(mon) end
  self.selectIndex = 1
  self:setScreen("select", 1)
end

-- PartyUseItemScreen: an ETHER-type item asks which move; everything else is
-- the item flow's (BagMenu useOn) answer, which closes the bag behind it
function Gen4BattleParty:useOn(mon)
  if self.onMove and not isEgg(mon) then
    self:setScreen("restore", 1)
    return
  end
  self:handOff(mon)
end

function Gen4BattleParty:pickSelect(i)
  local mon = self:mon()
  if i == 1 then Cursor.sound("decide", self.game.data); return self:handOff(mon) end
  if i == 4 then Cursor.sound("decide", self.game.data); self:setScreen("party"); return end
  if mon and isEgg(mon) then return end
  Cursor.sound("decide", self.game.data)
  if not Gen4BattleParty.pagesAvailable(self.game.data) then
    -- an older cache: the port's own summary screen, as before
    return require("src.ui.Screens").push(self.game, "SummaryMenu", {
      mon = mon, readOnlyMoves = true, page = (i == 3) and "moves" or nil,
    })
  end
  self.lastSelect = i
  if i == 2 then return self:setScreen("summary", 3) end
  if i == 3 then self.moveSlot = 1; return self:setScreen("moves", 1) end
end

function Gen4BattleParty:pickSummary(i)
  if i == 1 or i == 2 then
    if self:stepMon(i == 1 and -1 or 1) then Cursor.sound("decide", self.game.data) end
    return
  end
  Cursor.sound("decide", self.game.data)
  if i == 3 then self.moveSlot = 1; return self:setScreen("moves", 7) end
  if i == 4 then return self:setScreen("select", 2) end
end

function Gen4BattleParty:pickMoves(i)
  local moves = (self:mon() or {}).moves or {}
  if i <= 4 then
    if not moves[i] then return end
    Cursor.sound("decide", self.game.data)
    self.moveSlot = i
    return self:setScreen("movesum")
  end
  if i == 5 or i == 6 then
    if self:stepMon(i == 5 and -1 or 1) then Cursor.sound("decide", self.game.data); self.moveSlot = 1 end
    return
  end
  Cursor.sound("decide", self.game.data)
  if i == 7 then return self:setScreen("summary", 3) end
  if i == 8 then return self:setScreen("select", 3) end
end

function Gen4BattleParty:pickMoveSummary(i)
  local moves = (self:mon() or {}).moves or {}
  if i <= 4 then
    if i ~= self.moveSlot and not moves[i] then return end
    Cursor.sound("decide", self.game.data)
    self.moveSlot = i
    self.cursor.index = i
    return
  end
  Cursor.sound("decide", self.game.data)
  return self:setScreen("moves", self.moveSlot)
end

function Gen4BattleParty:pickRestore(i)
  local mon = self:mon()
  local moves = mon and mon.moves or {}
  if i <= 4 then
    if not moves[i] then return end
    Cursor.sound("decide", self.game.data)
    if not self:pop() then return end
    if self.onMove then self.onMove(mon, i) end
    return
  end
  Cursor.sound("decide", self.game.data)
  return self:setScreen("party")
end

function Gen4BattleParty:pickLearn(i)
  if i == 6 then return end
  Cursor.sound("decide", self.game.data)
  if i == 7 then return self:close() end
  self.learnSlot = i
  self.moveSlot = i
  return self:setScreen("confirm")
end

-- the move-learn helpers' own list of HMs, so a refusal here is the same
-- rule the rest of the port applies
function Gen4BattleParty:isHM(moveId)
  local ok, M = pcall(require, "src.ui.MoveLearnMenu")
  local hm = ok and M.hmMoves and M.hmMoves(self.game) or {}
  return hm[moveId] and true or false
end

function Gen4BattleParty:pickConfirm(i)
  if i == 2 then return end
  Cursor.sound("decide", self.game.data)
  if i == 3 then return self:setScreen("learn", self.learnSlot) end
  local slot = self.moveSlot
  local mon = self:mon()
  local entry = slot <= 4 and mon and (mon.moves or {})[slot]
  if entry and self:isHM(entry.id) then
    self.hmRefused = true
    return
  end
  if not self:pop() then return end
  if self.onChoose then self.onChoose(slot <= 4 and slot or nil) end
end

function Gen4BattleParty:pick(i)
  local s = self.screen
  if s == "party" then return self:pickSlot(i)
  elseif s == "select" then return self:pickSelect(i)
  elseif s == "summary" then return self:pickSummary(i)
  elseif s == "moves" then return self:pickMoves(i)
  elseif s == "movesum" then return self:pickMoveSummary(i)
  elseif s == "restore" then return self:pickRestore(i)
  elseif s == "learn" then return self:pickLearn(i)
  elseif s == "confirm" then return self:pickConfirm(i) end
end

function Gen4BattleParty:update(dt)
  self.t = (self.t or 0) + (dt or 1 / 60)
  local input = self.game.input
  if not input then return end
  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then self.message = nil end
    return
  end
  -- on the list the cursor IS `index` (a caller may have moved it)
  if self.screen == "party" and self:party()[self.index] ~= nil then self.cursor.index = self.index end
  local r = self.cursor:tick(input)
  if self.screen == "party" and self.cursor.index <= 6 then self.index = self.cursor.index end
  if r == "back" then
    if self.screen == "party" and self.forceSwitch then return end
    return self:pick(SCREENS[self.screen].back)
  elseif r then
    if self.screen == "select" then self.selectIndex = r end
    return self:pick(r)
  end
end

function Gen4BattleParty:touchpressed(_, px, py)
  local ok, SecondScreen = pcall(require, "src.ui.SecondScreen")
  if not ok then return false end
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x then return false end
  if self.message then self.message = nil; return true end
  local rects = Gen4BattleParty[SCREENS[self.screen][2]]
  local i = Cursor.hit(rects, x, y)
  if i then
    self.cursor:hide()
    self:pick(i)
  end
  return true
end

return Gen4BattleParty
