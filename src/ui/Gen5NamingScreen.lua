-- BLACK AND WHITE'S NAMING KEYBOARD, which was Platinum's.
--
-- Reported from play: "the keyboard for black and white still doesnt have rom
-- parity". BW has its own app (overlay 194, namein_graphic.c / namein_data.c)
-- with its own boards, pages, cursor and sounds; `Gen5NamingArt` decodes them
-- into `gen5_naming_art` and this screen lays them out where the overlay does.
-- Same options and callbacks as Gen4NamingScreen (title, presets, maxLen,
-- default, onDone, kind, species, mon, female), so every caller is unchanged.
--
-- THE TWO SCREENS: the upper one is the fading grid with a message window at
-- tile (1, 19), 30 x 4 (ov194 0x021F3D10) showing the prompt (bank 81); the
-- touch screen is everything else -- the green tab with the icon, the band the
-- name is typed into (window tile (8, 2), 24 x 2, ov194 0x021F1E62; places
-- 14 px apart, centred on x 128 -- 0x021F1F04) and the keyboard. With one
-- screen the keyboard is the screen and the prompt goes in the band.
--
-- THE MODES (ov194 0x021F256C): UPPER, lower, Others -- 13 x 5 keys plus a
-- row of six buttons (the four mode tabs, DELETE, OK) -- and qwerty: 10 / 9 /
-- 8 keys staggered (0x021F5544: x 5 / 6 / 7, y 8 / 12 / 16 tiles) with Delete,
-- Enter, two Shifts, the tabs and Space. The cursor's moves are 0x021F2A88
-- (ABC: the button row remembers the column it was entered from) and its
-- rectangles 0x021F28FC / 0x021F299C.
--
-- THE KEYS ARE PAINTED: everything in row 1 (dark), the current mode tab (and
-- both Shifts while shift is held) in row 4 = row 2 (light), and a key that is
-- pressed flashes between the two for ten frames (0x021F1A1C / 0x021F1BFC /
-- 0x021F1D58: a sine blend, 0x1999 of a turn a frame). The cursor is two
-- brackets (OBJ sequences 3 and 4) at the key's sides.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local S = {}
S.__index = S
S.isOpaque = true

local W, H = 256, 192
local lg = love and love.graphics

-- the six buttons of an ABC page's bottom row (kind ids as ov194's: 2-5 the
-- tabs, 6 DELETE, 7 OK) and where the cursor goes back up to from each
-- (ov194 0x021F555C: tab 0 -> column 0, 1 -> 2, 2 -> 3, 3 -> 5, DELETE 6, OK 10)
local ABC_UP = { [0] = 0, 2, 3, 5, 6, 10 }

-- the sound effects (ov194 0x021F558C): SEQ_SE_SELECT1, CANCEL3, DECIDE1,
-- SYS_12, DECIDE2, BEEP
local SE = { move = "SEQ_SE_SELECT1", delete = "SEQ_SE_CANCEL3", input = "SEQ_SE_DECIDE1",
             mode = "SEQ_SE_SYS_12", ok = "SEQ_SE_DECIDE2", beep = "SEQ_SE_BEEP" }

local function se(self, name)
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then pcall(Sound.playSe, data, SE[name] or name) end
end

function S:uiSize() return W, H end
function S:wantsFillScale() return true end
function S:wantsEdgeBleed() return false end
function S:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function S.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, S)
  self.game = game
  self.art = (game.data or {}).gen5_naming_art or {}
  self.kind = opts.kind
  self.female = opts.female
  self.mon = opts.mon
  self.species = opts.species or (opts.mon and opts.mon.species)
  self.title = opts.title or self:defaultTitle()
  self.maxLen = opts.maxLen or 7
  self.onDone = opts.onDone
  self.presets = opts.presets
  self.choice = self.presets and #self.presets > 0 and 1 or nil
  self.glyphs = {}
  for ch in tostring(opts.default or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #self.glyphs < self.maxLen then self.glyphs[#self.glyphs + 1] = ch end
  end
  self.mode = 1          -- 1 UPPER, 2 lower, 3 Others, 4 qwerty
  self.shift = false     -- qwerty's Shift
  self.col, self.row = 0, 0
  self.up = {}
  for k, v in pairs(ABC_UP) do self.up[k] = v end
  self.cursorShown = true
  self.ticks = 0
  self.cache = {}
  return self
end

-- the prompt from bank 81 when the caller gave none: 0 your name, 1 a
-- Pokemon's nickname ({VAR1} the species), 2 a box, 3 the rival
function S:defaultTitle()
  local text = self.art.text or {}
  local k = self.kind
  local index = (k == "mon" or k == "pokemon") and 1 or k == "box" and 2 or k == "rival" and 3 or 0
  local s = text[index] or Strings("YOUR NAME?")
  if s:find("{VAR1}", 1, true) then
    local data = self.game.data or {}
    local def = data.pokemon and data.pokemon[self.species]
    local name = (self.mon and self.mon.nickname) or (def and (def.name or def.displayName)) or ""
    s = s:gsub("{VAR1}", function() return name end)
  end
  return s
end

function S:img(entry)
  local path = (type(entry) == "table" and entry.path) or entry
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function S:typed() return table.concat(self.glyphs) end

function S:close(name)
  self.game.stack:pop()
  if self.onDone then self.onDone(name) end
end

-- ------------------------------------------------------------- the board --

-- the qwerty page in force
function S:qwertyPage()
  local q = self.art.qwerty or {}
  return self.shift and q.upper or q.lower
end

-- what the cursor is on: { kind = "char", value } | { kind = "tab", mode } |
-- { kind = "delete" | "ok" | "shift" | "space" }
function S:keyAt(col, row)
  if self.mode <= 3 then
    if row <= 4 then
      local page = (self.art.pages or {})[self.mode]
      local line = page and page.rows[row + 1]
      return { kind = "char", value = line and line[col + 1] or "" }
    end
    if col <= 3 then return { kind = "tab", mode = col + 1 } end
    return { kind = col == 4 and "delete" or "ok" }
  end
  local page = self:qwertyPage()
  local rows = page and page.rows or {}
  if row == 0 then
    if col == 10 then return { kind = "delete" } end
    return { kind = "char", value = rows[1] and rows[1][col + 1] or "" }
  elseif row == 1 then
    if col == 9 then return { kind = "ok" } end
    return { kind = "char", value = rows[2] and rows[2][col + 1] or "" }
  elseif row == 2 then
    if col == 0 or col == 9 then return { kind = "shift" } end
    return { kind = "char", value = rows[3] and rows[3][col] or "" }
  end
  if col == 4 then return { kind = "space" } end
  return { kind = "tab", mode = col + 1 }
end

-- the key's rectangle in TILES, x1 y1 x2 y2 (ov194 0x021F28FC / 0x021F299C)
local QX, QY = { [0] = 5, 6, 7 }, { [0] = 8, 12, 16 }
function S:rect(col, row)
  if self.mode <= 3 then
    if row <= 4 then local x, y = col * 2 + 3, row * 3 + 5; return x, y, x + 2, y + 3 end
    if col <= 3 then local x = (col + 1) * 3; return x, 20, x + 3, 23 end
    if col == 4 then return 15, 20, 22, 23 end
    return 22, 20, 29, 23
  end
  if row == 0 then
    if col == 10 then return 25, 8, 29, 11 end
    local x = QX[0] + col * 2; return x, QY[0], x + 2, QY[0] + 3
  elseif row == 1 then
    if col == 9 then return 24, 12, 29, 15 end
    local x = QX[1] + col * 2; return x, QY[1], x + 2, QY[1] + 3
  elseif row == 2 then
    if col == 0 then return 3, 16, 7, 19 end
    if col == 9 then return 23, 16, 27, 19 end
    local x = QX[2] + (col - 1) * 2; return x, QY[2], x + 2, QY[2] + 3
  end
  if col == 4 then return 15, 20, 27, 23 end
  local x = (col + 1) * 3; return x, 20, x + 3, 23
end

local QCOLS = { [0] = 11, 10, 10, 5 }

-- THE MOVE. ABC is ov194 0x021F2A88 to the letter: 13 columns wrap, six rows
-- wrap, the button row is entered at column*2/3 (6-9 DELETE, 10-12 OK) and
-- left back to the column it remembers. qwerty keeps its rows and goes up or
-- down to the key under the cursor's centre.
function S:move(dx, dy)
  if self.mode <= 3 then
    if self.row == 5 then
      if dx ~= 0 then self.col = (self.col + dx) % 6 end
      if dy ~= 0 then
        local back = self.up[self.col] or 0
        self.row = (self.row + dy) % 6
        self.col = back
      end
      return
    end
    self.col = (self.col + dx) % 13
    self.row = (self.row + dy) % 6
    if self.row == 5 then
      local c = self.col
      local button
      if c >= 6 and c <= 9 then button = 4 elseif c >= 10 then button = 5 else button = math.floor(c * 2 / 3) end
      self.up[button] = c
      self.col = button
    end
    return
  end
  if dx ~= 0 then
    self.col = (self.col + dx) % QCOLS[self.row]
  end
  if dy ~= 0 then
    local x1, _, x2 = self:rect(self.col, self.row)
    local centre = (x1 + x2) / 2
    self.row = (self.row + dy) % 4
    local best, bestD = 0, math.huge
    for c = 0, QCOLS[self.row] - 1 do
      local a, _, b = self:rect(c, self.row)
      local d = math.abs((a + b) / 2 - centre)
      if d < bestD then best, bestD = c, d end
    end
    self.col = best
  end
end

-- where OK is in this mode
function S:okPlace()
  if self.mode <= 3 then return 5, 5 end
  return 9, 1
end

function S:setMode(mode)
  if mode == self.mode then return false end
  local wasQwerty, isQwerty = self.mode == 4, mode == 4
  self.mode = mode
  if wasQwerty ~= isQwerty then
    -- the tab stays under the cursor in the new board's bottom row
    if isQwerty then self.col, self.row = mode - 1, 3 else self.col, self.row = mode - 1, 5 end
  end
  return true
end

function S:flash(col, row)
  self.flashKey = { col = col, row = row, mode = self.mode, tick = 0 }
end

function S:say(index)
  local text = (self.art.text or {})[index]
  if text then self.notice = { text = text, tick = 0 } end
end

function S:finish()
  local name = self:typed()
  local digits = select(2, name:gsub("%d", ""))
  if digits > 4 then se(self, "beep"); self:say(9); return end
  local k = self.kind
  if name:gsub(" ", "") == "" and (k == nil or k == "player" or k == "rival" or k == "friend") then
    se(self, "beep"); self:say(8); return
  end
  se(self, "ok")
  self:close(name)
end

function S:press(col, row)
  local key = self:keyAt(col, row)
  if not key then return end
  self:flash(col, row)
  if key.kind == "char" then
    if key.value == "" then return end
    if #self.glyphs >= self.maxLen then se(self, "beep"); return end
    self.glyphs[#self.glyphs + 1] = key.value
    se(self, "input")
    self:fullToOk()
  elseif key.kind == "space" then
    if #self.glyphs >= self.maxLen then se(self, "beep"); return end
    self.glyphs[#self.glyphs + 1] = " "
    se(self, "input")
    self:fullToOk()
  elseif key.kind == "delete" then
    self:deleteOne()
  elseif key.kind == "tab" then
    if self:setMode(key.mode) then se(self, "mode") end
  elseif key.kind == "shift" then
    self.shift = not self.shift
    se(self, "input")
  elseif key.kind == "ok" then
    self:finish()
  end
end

-- a full name sends the cursor to OK (ov194 0x021F328A: length == max ->
-- 0x021F2828 finds kind 7)
function S:fullToOk()
  if #self.glyphs >= self.maxLen then self.col, self.row = self:okPlace() end
end

function S:deleteOne()
  if #self.glyphs > 0 then
    self.glyphs[#self.glyphs] = nil
    se(self, "delete")
  end
end

function S:tick(dt)
  self.clock = (self.clock or 0) + (dt or 1 / 60) * 60
  while self.clock >= 1 do
    self.clock = self.clock - 1
    self.ticks = self.ticks + 1
    if self.flashKey then
      self.flashKey.tick = self.flashKey.tick + 1
      if self.flashKey.tick > 10 then self.flashKey = nil end
    end
    if self.notice then
      self.notice.tick = self.notice.tick + 1
      if self.notice.tick > 120 then self.notice = nil end
    end
  end
end

function S:update(dt)
  self:tick(dt)
  local input = self.game.input
  if not input then return end
  if self.choice then
    local count = #self.presets + 1
    if input:wasPressed("up") then self.choice = (self.choice - 2) % count + 1 end
    if input:wasPressed("down") then self.choice = self.choice % count + 1 end
    if input:wasPressed("a") or input:wasPressed("start") then
      if self.choice == 1 then self.choice = nil
      else self:close(self.presets[self.choice - 1]) end
    end
    return
  end
  -- after a touch the cursor is hidden; the next key only shows it again
  if not self.cursorShown then
    for _, k in ipairs({ "left", "right", "up", "down", "a" }) do
      if input:wasPressed(k) then se(self, "move"); self.cursorShown = true; return end
    end
  end
  for _, step in ipairs({ { "left", -1, 0 }, { "right", 1, 0 }, { "up", 0, -1 }, { "down", 0, 1 } }) do
    if input:wasPressed(step[1]) then se(self, "move"); self:move(step[2], step[3]) end
  end
  if input:wasPressed("a") then self:press(self.col, self.row) end
  if input:wasPressed("b") then self:deleteOne() end
  if input:wasPressed("select") then
    if self:setMode(self.mode % 4 + 1) then se(self, "mode") end
  end
  if input:wasPressed("start") then
    se(self, "move")
    self.cursorShown = true
    self.col, self.row = self:okPlace()
  end
end

-- --------------------------------------------------------------- touch --

function S:keyboardOnSecond()
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  return ok and SS.separateMode(SS.mode(self.game)) and not SS.stowed(self.game)
end

function S:touchpressed(_, px, py)
  local x, y
  if self:keyboardOnSecond() then
    x, y = require("src.ui.SecondScreen").toLocal(self.game, px, py)
  else
    local r = require("src.render.Renderer").uiPresentation
    x, y = px, py
    if r then x, y = (px - r.x) / r.scaleX, (py - r.y) / r.scaleY end
  end
  if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
  if self.choice then
    local index = math.floor((y - 48) / 22) + 1
    if x >= 24 and x < 232 and index >= 1 and index <= #self.presets + 1 then
      if index == 1 then self.choice = nil else self:close(self.presets[index - 1]) end
    end
    return true
  end
  local tx, ty = x / 8, y / 8
  local rows = self.mode <= 3 and 6 or 4
  for row = 0, rows - 1 do
    local cols = self.mode <= 3 and (row == 5 and 6 or 13) or QCOLS[row]
    for col = 0, cols - 1 do
      local x1, y1, x2, y2 = self:rect(col, row)
      if tx >= x1 and tx < x2 and ty >= y1 and ty < y2 then
        self.cursorShown = false
        self.col, self.row = col, row
        self:press(col, row)
        return true
      end
    end
  end
  return true
end
function S:touchmoved() return false end
function S:touchreleased() return false end

-- ---------------------------------------------------------------- draw --

local function blit(img, x, y, quad)
  if not img then return end
  if quad then lg.draw(img, quad, x, y) else lg.draw(img, x, y) end
end

function S:sprite(key, x, y)
  local rec = self.art["obj_" .. key]
  local img = rec and self:img(rec)
  if not img then return false end
  lg.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

-- a rectangle of the lit board over the dark one, at `alpha`
function S:light(boardKey, x1, y1, x2, y2, alpha)
  local img = self:img(self.art[boardKey .. "_lit"])
  if not img then return end
  local iw, ih = img:getDimensions()
  local quad = lg.newQuad(x1 * 8, y1 * 8, (x2 - x1) * 8, (y2 - y1) * 8, iw, ih)
  lg.setColor(1, 1, 1, alpha or 1)
  lg.draw(img, quad, x1 * 8, y1 * 8)
  lg.setColor(1, 1, 1, 1)
end

function S:drawBoard()
  local qwerty = self.mode == 4
  local board = qwerty and "qwerty" or "keys"
  lg.setColor(1, 1, 1, 1)
  blit(self:img(self.art[board .. "_dark"]), 0, 0)
  if not qwerty then blit(self:img(self.art.frame_dark), 0, 0) end
  local tabBoard = qwerty and "qwerty" or "frame"
  -- the mode's tab in row 4 (light)
  local tx = self.mode * 3
  self:light(tabBoard, tx, 20, tx + 3, 23, 1)
  if qwerty and self.shift then
    self:light("qwerty", 3, 16, 7, 19, 1)
    self:light("qwerty", 23, 16, 27, 19, 1)
  end
  -- the pressed key, in row 3: sin blend, a sixth of a turn... 0x1999 a frame
  local f = self.flashKey
  if f and f.mode == self.mode then
    local x1, y1, x2, y2 = self:rect(f.col, f.row)
    local phase = (f.tick * 0x1999) % 0x10000 / 0x10000
    local a = (math.sin(phase * 2 * math.pi) + 1) / 2
    local key = (y1 >= 20 and not qwerty) and "frame" or board
    self:light(key, x1, y1, x2, y2, a)
  end
  -- the labels, centred in their keys (ov194 0x021F26F0), in row 15's ink
  local ink = self.art.ink or {}
  local function c(rgb, fb) rgb = rgb or fb return { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255 } end
  Font.pushStyle({ text = c(ink.text, { 247, 247, 247 }), shadow = c(ink.shadow, { 123, 123, 123 }) })
  local rows = qwerty and 3 or 5
  for row = 0, rows - 1 do
    local cols = qwerty and QCOLS[row] or 13
    for col = 0, cols - 1 do
      local key = self:keyAt(col, row)
      if key and key.kind == "char" and key.value ~= "" then
        local x1, y1, x2, y2 = self:rect(col, row)
        local cx, cy = (x1 + x2) * 4, (y1 + y2) * 4
        Font.draw(key.value, math.floor(cx - Font.width(key.value) / 2) - 1, cy - 8)
      end
    end
  end
  Font.popStyle()
end

-- the brackets (sequences 3 / 4: cells 5 6 7 6 and 8 9 10 9, 6 6 32 6
-- frames) at x1*8+7 and x2*8-7, y y1*8 + h*4 - 3 (ov194 0x021F1B46)
local BRACKET = { { 0, 6 }, { 1, 6 }, { 2, 32 }, { 1, 6 } }
local function seqFrame(seq, t)
  local total = 0
  for _, f in ipairs(seq) do total = total + f[2] end
  t = t % total
  for _, f in ipairs(seq) do
    if t < f[2] then return f[1] end
    t = t - f[2]
  end
  return seq[1][1]
end
function S:drawCursor()
  if not self.cursorShown then return end
  local x1, y1, x2, y2 = self:rect(self.col, self.row)
  local y = y1 * 8 + (y2 - y1) * 4 - 3
  local n = seqFrame(BRACKET, self.ticks)
  self:sprite("cursor_l_" .. n, x1 * 8 + 7, y)
  self:sprite("cursor_r_" .. n, x2 * 8 - 7, y)
end

-- sequence 0, the next place: cells 3 2 1 0 1 2 for 32 6 6 6 6 6 frames
local UNDERSCORE = { { 3, 32 }, { 2, 6 }, { 1, 6 }, { 0, 6 }, { 1, 6 }, { 2, 6 } }
function S:drawEntry()
  local n = self.maxLen
  local base = math.max(0, 64 - math.floor(n * 14 / 2)) + 64
  for i = 0, math.min(n, 16) - 1 do
    local cell = (i == #self.glyphs) and seqFrame(UNDERSCORE, self.ticks) or 0
    self:sprite("underscore_" .. cell, base + 14 * i, 37)
  end
  local ink = self.art.ink or {}
  local function c(rgb, fb) rgb = rgb or fb return { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255 } end
  Font.pushStyle({ text = c(ink.text, { 247, 247, 247 }), shadow = c(ink.shadow, { 123, 123, 123 }) })
  for i, ch in ipairs(self.glyphs) do
    Font.draw(ch, base + 14 * (i - 1) + 7 - math.floor(Font.width(ch) / 2), 16)
  end
  Font.popStyle()
  self:drawIcon()
end

-- the icon in the green tab: the player's own overworld picture (ov194
-- 0x021F3FBC converts the field texture), a Pokemon's party icon, the PC
-- for a box, otherwise the "?"
function S:drawIcon()
  local k = self.kind
  local data = self.game.data or {}
  if k == "mon" or k == "pokemon" then
    local species = self.species
    local icons = data.icons
    local def = data.pokemon and data.pokemon[species]
    local entry = (icons and icons.bySpecies and icons.bySpecies[species]) or (def and def.icon)
    local path = type(entry) == "table" and entry.image or entry
    local img = type(path) == "string" and self:img(path)
    if not img then return end
    local frameH = (type(entry) == "table" and tonumber(entry.frameHeight)) or 32
    local iw, ih = img:getDimensions()
    local frame = math.floor(self.ticks / 10) % 2
    if (frame + 1) * frameH > ih then frame = 0 end
    local quad = lg.newQuad(0, frame * frameH, iw, math.min(frameH, ih), iw, ih)
    lg.draw(img, quad, 30 - math.floor(iw / 2), 20 - math.floor(frameH / 2))
    return
  end
  if k == "box" then self:sprite("icon_box", 34, 20); return end
  if k ~= nil and k ~= "player" and k ~= "rival" then self:sprite("icon_unknown", 34, 20); return end
  local female = self.female
  if female == nil then
    local p = self.game.save and self.game.save.player
    female = p and (p.gender == 1 or p.gender == "girl" or p.gender == "female")
  end
  local forms = (data.field or {}).playerForms or {}
  local form = forms[female and "girl" or "boy"] or {}
  local def = data.sprites and data.sprites[form.walk or ""]
  local img = def and self:img(def.image)
  if not img then self:sprite("icon_unknown", 34, 20); return end
  local fw, fh = tonumber(def.frameWidth) or 32, tonumber(def.frameHeight) or 32
  local iw, ih = img:getDimensions()
  local index = (def.facings and def.facings.down and def.facings.down[1]) or 0
  local perRow = math.max(1, math.floor(iw / fw))
  local qx, qy = (index % perRow) * fw, math.floor(index / perRow) * fh
  if qy + fh > ih then qx, qy = 0, 0 end
  lg.draw(img, lg.newQuad(qx, qy, fw, fh, iw, ih), 34 - fw / 2, 20 - fh / 2)
end

function S:promptText()
  return self.notice and self.notice.text or self.title
end

-- the touch screen
function S:drawTouch(withPrompt)
  lg.setColor(1, 1, 1, 1)
  local base = self:img(self.art.base)
  if base then lg.draw(base, 0, 0) else lg.clear(0.03, 0.10, 0.16, 1) end
  self:drawBoard()
  self:drawEntry()
  self:drawCursor()
  if withPrompt then
    -- no upper screen: the prompt in the band, above the name
    local text = (self:promptText() or ""):gsub("\n", " ")
    Font.pushStyle({ text = { 0.97, 0.97, 0.97 }, shadow = { 0.32, 0.32, 0.32 } })
    Font.draw(text, 68, 2)
    Font.popStyle()
  end
end

-- the upper screen: the grid and the message window at (1, 19), 30 x 4
function S:drawTop()
  lg.setColor(1, 1, 1, 1)
  local top = self:img(self.art.top)
  if top then lg.draw(top, 0, 0) else lg.clear(0.03, 0.10, 0.16, 1) end
  if Font.hasDialogueFrame and Font.hasDialogueFrame() then Font.drawDialogueBox(0, 18, 32, 6)
  else Font.drawBox(0, 18, 32, 6) end
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
  Font.draw(self:promptText() or "", 12, 154)
  Font.popStyle()
end

function S:drawChoice()
  lg.setColor(0.03, 0.10, 0.16, 1)
  lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(1, 1, 1, 1)
  Font.draw(self.title, 24, 24)
  for i = 1, #self.presets + 1 do
    local label = i == 1 and Strings("NEW NAME") or self.presets[i - 1]
    local y = 48 + (i - 1) * 22
    if self.choice == i then
      lg.setColor(0.55, 0.71, 0.84, 1)
      lg.rectangle("fill", 24, y - 2, 208, 20)
      lg.setColor(1, 1, 1, 1)
    end
    Font.draw(label, 32, y)
  end
end

function S:draw()
  if self.choice then self:drawChoice(); return end
  if self:keyboardOnSecond() then
    self:drawTop()
    local SS = require("src.ui.SecondScreen")
    SS.draw(self.game, function() self:drawTouch(false) end)
  else
    self:drawTouch(true)
  end
  lg.setColor(1, 1, 1, 1)
end

return S
