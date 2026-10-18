-- THE POKeGEAR'S RADIO (overlay 101: pokegear_radio.c, overlay_101_021F49F8 /
-- 021F4F34 / 021F57B8 and radio/shows), the RADIO app of
-- src/ui/HgssPokegear.lua.
--
-- READ FROM CODE:
--   * the dial: pgradio NSCR 22 + skin on MAIN_2 over NSCR 28 + skin on
--     MAIN_3; the four channel buttons at tiles (2, 6) / (26, 6) / (2, 14) /
--     (26, 14), lit from the screen's atlas (4, 24), unlit (0, 24)
--     (Radio_ToggleChannelSelectionButtons)
--   * the tuning cursor (OBJ seq 0) inside the circle (128, 92) r 52
--     (sTuningAreaHitbox); its position kept in the save (the cartridge's
--     Pokegear_SetRadioCursorCoords, 128 / 128 on a new save)
--   * keys (Radio_HandleKeyInput): held directions move it 2 px a frame while
--     it stays in the circle; A steps the lit channel button (0..3) and snaps
--     the cursor to that station's centre; B puts the cursor on the bar
--   * touch (Radio_HandleTouchInput_Internal): the buttons y 48-76 / 112-140,
--     x 16-48 / 208-240 snap; a touch within 8 px of the cursor picks it up
--     and it follows the stylus inside the circle until released
--   * stations (Radio_GetTunedStationID): the circles of the set the map
--     allows -- Johto (112,76) (152,76) (96,108) (136,116), Kanto the first
--     three, Kanto + EXPN also (128,48); Alph / Rocket / Mahogany one at the
--     centre; no signal none -- each with an inner ring (clear) and an outer
--     one (static); the set by Radio_GetAvailableChannels: no radio signal on
--     the map -> none, the Ruins of Alph's halls -> Alph, Kanto (region) ->
--     none before FLAG_RESTORED_POWER (0x118), with EXPN after
--     FLAG_GOT_EXPN_CARD (0x11F), Mahogany's maps before
--     FLAG_ROCKET_HIDEOUT_CLEARED (0xCA) -> the signal, the Rocket takeover
--     (var 0x4077 2..4) -> Team Rocket, else Johto
--   * the show (RadioShow_TranslateStationID): 0 Pokemon Music, 1 Pokemon
--     Talk, 2 Trainer Profiles / That Town (hour % 2), 3 Search Party /
--     Serial Drama / Buena's Password (hour % 3), 4 Poke Flute, 5 Unown,
--     6 Team Rocket, 7 the Mahogany signal; each show's title (entry 0) and
--     host (1) from its bank (416, 414, 420, 415, 419, 413, 411, 417, 410,
--     418, 409); the title in MAIN_1's window (5, 1), the host in SUB_2's
--     (4, 16), the script in SUB_2's (2, 19), two lines
--   * POKeMON MUSIC (shows/pokemon_music.c): bank 416 2, then the day's line
--     (3 + weekday; 10 / 11 with the National Dex on Wednesday / Thursday; 12
--     on a Sunday without the GB Sounds) and its track -- March (Mon, Wed,
--     Fri, Sun), Lullaby (Tue, Thu, Sat), Hoenn / Sinnoh with the National Dex;
--     POKe FLUTE plays SEQ_GS_HUE, UNOWN SEQ_GS_RADIO_UNKNOWN
-- NOT DONE: the talk shows' scripts (Oak's Pokemon Talk, Trainer Profiles,
-- That Town, Search Party, the drama, Buena's Password, the commercials, the
-- Rocket broadcasts) -- the station's title and host show, the script window
-- stays empty; the static mixed into the text; the GB Sounds track list.

local Font = require("src.render.Font")

local Radio = {}
Radio.__index = Radio

local floor = math.floor
local CX, CY, CR = 128, 92, 52
local BUTTON_TILE = { [0] = { 2, 6 }, { 26, 6 }, { 2, 14 }, { 26, 14 } }
local BUTTON_RECT = { [0] = { 48, 76, 16, 48 }, { 48, 76, 208, 240 }, { 112, 140, 16, 48 }, { 112, 140, 208, 240 } }
-- sTuningHitboxes_*: {x, y, inner r, outer r} per station slot
local JOHTO = { { 112, 76, 4, 16 }, { 152, 76, 4, 20 }, { 96, 108, 4, 16 }, { 136, 116, 4, 20 } }
local SETS = {
  johto = JOHTO,
  kanto = { JOHTO[1], JOHTO[2], JOHTO[3] },
  expn = { JOHTO[1], JOHTO[2], JOHTO[3], JOHTO[4], { 128, 48, 4, 8 } },
  none = {},
  alph = { { 128, 92, 4, 16 } },
  rocket = { { 128, 92, 38, 52 } },
  mahogany = { { 128, 92, 38, 52 } },
}
local ALPH_MAPS = { [315] = true, [323] = true, [490] = true, [491] = true, [492] = true }
local MAHOGANY_MAPS = { [87] = true, [133] = true, [140] = true, [396] = true, [397] = true, [246] = true,
  [368] = true, [116] = true, [247] = true, [248] = true, [249] = true, [45] = true, [142] = true,
  [245] = true, [88] = true, [294] = true, [295] = true }
-- RADIO_STATION_*: bank, music
local SHOW = {
  [0] = { 416 }, { 414 }, { 419 }, { 413 }, { 411 }, { 420 }, { 415 },
  { 417, "SEQ_GS_HUE" }, { 410, "SEQ_GS_RADIO_UNKNOWN" }, { 418 }, { 409 }, { 412 },
}
local MUSIC = { [0] = "SEQ_GS_RADIO_MARCH", "SEQ_GS_RADIO_KOMORIUTA", "SEQ_GS_RADIO_R_101", "SEQ_GS_RADIO_R_201" }

local function flag(save, id) return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true end

function Radio.new(gear)
  local self = setmetatable({ gear = gear, game = gear.game, button = 0, lit = false, t = 0 }, Radio)
  local pg = gear:save()
  self.x, self.y = tonumber(pg.radioX) or 128, tonumber(pg.radioY) or 128
  if not self:inArea(self.x, self.y) then self.x, self.y = 128, 128 end
  self.set = self:availableSet()
  return self
end

function Radio:inArea(x, y)
  local dx, dy = x - CX, y - CY
  return dx * dx + dy * dy <= CR * CR
end

-- Radio_GetAvailableChannels
function Radio:availableSet()
  local header, id = self.gear:header()
  local save = self.game.save
  if header and header.radioSignal == false then return "none" end
  if id and ALPH_MAPS[id] then return "alph" end
  if header and (header.region or 0) ~= 0 then
    if not flag(save, 0x118) then return "none" end
    if flag(save, 0x11F) then return "expn" end
    return "kanto"
  end
  if id and MAHOGANY_MAPS[id] and not flag(save, 0xCA) then return "mahogany" end
  local ok, C = pcall(require, "src.script.Gen4Commands")
  local takeover = ok and C.getVar and tonumber(C.getVar(save, 0x4077)) or 0
  if takeover >= 2 and takeover <= 4 then return "rocket" end
  return "johto"
end

-- Radio_GetTunedStationID: station, signal (2 clear, 1 static) or nil
function Radio:tuned(x, y)
  for i, c in ipairs(SETS[self.set] or {}) do
    local dx, dy = x - c[1], y - c[2]
    local d2 = dx * dx + dy * dy
    if d2 <= c[3] * c[3] or d2 <= c[4] * c[4] then
      local station = i - 1
      if self.set == "rocket" then station = 6
      elseif self.set == "mahogany" then station = 7
      elseif self.set == "alph" then station = 5 end
      return station, d2 <= c[3] * c[3] and 2 or 1
    end
  end
  return nil, 0
end

-- RadioShow_TranslateStationID
function Radio:showFor(station)
  local hour = tonumber(os.date("%H")) or 0
  if station == 0 then return 0 end
  if station == 1 then return 1 end
  if station == 2 then return 5 + hour % 2 end
  if station == 3 then return 2 + hour % 3 end
  if station == 4 then return 7 end
  if station == 5 then return 8 end
  if station == 6 then return 9 end
  if station == 7 then return 10 end
  return 0
end

function Radio:music(song)
  local ok, Music = pcall(require, "src.core.Music")
  if not ok then return end
  if song then pcall(Music.play, self.game.data, song)
  else pcall(Music.stop) end
end

function Radio:open(station)
  local show = self:showFor(station)
  local def = SHOW[show] or {}
  self.show = show
  self.title = def[1] and self.gear:text(def[1], 0) or ""
  self.host = def[1] and (show ~= 7 and show ~= 8 and show ~= 10 and show ~= 11) and self.gear:text(def[1], 1) or ""
  self.lines = {}
  self.script = nil
  if show == 0 then
    -- Pokemon Music: the intro, then the day's line and track
    local wday = (tonumber(os.date("%w")) or 0)
    local national = ((self.game.save or {}).pokedex or {}).national and true or false
    local track, msg = 0, 3 + wday
    if wday == 0 then
      local inv = (self.game.save or {}).inventory or {}
      if (tonumber(inv.ITEM_GB_SOUNDS) or 0) > 0 then track = 0 else msg = 12 end
    elseif wday == 1 or wday == 5 then track = 0
    elseif wday == 3 then if national then track, msg = 2, 10 end
    elseif wday == 2 or wday == 6 then track = 1
    elseif wday == 4 then if national then track, msg = 3, 11 else track = 1 end end
    self.script = { self.gear:text(416, 2) or "", self.gear:text(416, msg) or "" }
    self:music(MUSIC[track])
  else
    self:music(def[2])
  end
  self.scriptAt, self.scriptT = 1, 0
end

function Radio:close()
  if self.station ~= nil then
    self.station, self.signal = nil, 0
    self.title, self.host, self.lines, self.script = nil, nil, {}, nil
    self:music(nil)
  end
end

-- Radio_CoordsToStation
function Radio:retune()
  local station, signal = self:tuned(self.x, self.y)
  if station == nil then return self:close() end
  if station == self.station then self.signal = signal; return end
  self:close()
  self.station, self.signal = station, signal
  self:open(station)
end

function Radio:enter()
  self.set = self:availableSet()
  -- Radio_Start (as the app fades in): the field's music stops
  self.station = nil
  self:music(nil)
  self:retune()
end

function Radio:leave()
  local pg = self.gear:save()
  pg.radioX, pg.radioY = self.x, self.y
  self:close()
  local ok, Music = pcall(require, "src.core.Music")
  if ok and Music.restoreMap then pcall(Music.restoreMap, self.game.data) end
end

function Radio:snap(i)
  local c = JOHTO[i + 1]
  self.x, self.y = c[1], c[2]
  self:retune()
end

function Radio:keys(input)
  if not self.entered then self.entered = true; self:enter() end
  if input:wasPressed("b") then return self.gear:toBar() end
  if input:wasPressed("a") then
    self.button = self.lit and (self.button + 1) % 4 or self.button
    self.lit = true
    self:snap(self.button)
    self.gear:se("SEQ_SE_GS_GEARCURSOR")
    return
  end
  local dx, dy = 0, 0
  if input:isDown("left") then dx = -2 elseif input:isDown("right") then dx = 2 end
  if input:isDown("up") then dy = -2 elseif input:isDown("down") then dy = 2 end
  if dx == 0 and dy == 0 then return end
  local moved = false
  if self:inArea(self.x + dx, self.y) then self.x = self.x + dx; moved = true end
  if self:inArea(self.x, self.y + dy) then self.y = self.y + dy; moved = true end
  self.lit = false
  if moved then self:retune() end
end

function Radio:touch(x, y)
  if not self.entered then self.entered = true; self:enter() end
  for i = 0, 3 do
    local r = BUTTON_RECT[i]
    if y >= r[1] and y < r[2] and x >= r[3] and x < r[4] then
      self.button, self.lit = i, true
      self:snap(i)
      self.gear:se("SEQ_SE_GS_GEARCURSOR")
      return true
    end
  end
  if not self:inArea(x, y) then return false end
  local dx, dy = x - self.x, y - self.y
  if dx * dx + dy * dy <= 64 then
    self.x, self.y = x, y
    self.dragging = true
    self.busy = true
    self.lit = false
    self:retune()
    return true
  end
  return false
end

function Radio:busyUpdate(input, tap)
  if not self.dragging or not self.gear.touchHeld then
    self.dragging, self.busy = false, false
  end
end

function Radio:touchMove(x, y)
  if self.dragging and self:inArea(x, y) then
    self.x, self.y = x, y
    self:retune()
  end
end

function Radio:touchUp() self.dragging, self.busy = false, false end

function Radio:reselect() end

function Radio:update()
  self.t = self.t + 1
  if not self.entered and not self.gear.fade then self.entered = true; self:enter() end
  -- the script window: a line at a time, 45 frames apart (RadioShow delay)
  if self.script then
    self.scriptT = self.scriptT + 1
    if self.scriptT == 1 or self.scriptT % 90 == 0 then
      local line = self.script[self.scriptAt]
      if line then
        self.lines = {}
        for l in (line .. "\n"):gmatch("([^\n]*)\n") do self.lines[#self.lines + 1] = l end
        self.scriptAt = self.scriptAt + 1
      end
    end
  end
end

function Radio:drawTouch()
  local gear = self.gear
  gear:picture("radio_back")
  gear:picture("radio_top")
  if self.lit then
    local full = gear:img("radio_full")
    local at = BUTTON_TILE[self.button]
    if full then gear:tiles(full, 4, 24, 4, 4, at[1], at[2]) end
  end
  -- the tuning cursor, its five frames cycling
  local frame = floor(self.t / 8) % 5
  if not gear:obj("radio", 0, frame, self.x, self.y) then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("line", self.x, self.y, 6)
  end
  if self.title and self.title ~= "" then
    Font.pushStyle({ text = gear:ink("radioMain", 1, { 1, 1, 1 }), shadow = gear:ink("radioMain", 2, { 0.3, 0.3, 0.3 }) })
    Font.draw(self.title, 40, 8)
    Font.popStyle()
  end
end

function Radio:drawTop()
  local gear = self.gear
  gear:picture("radio_bottom")
  Font.pushStyle({ text = gear:ink("radioSub", 1, { 1, 1, 1 }), shadow = gear:ink("radioSub", 2, { 0.3, 0.3, 0.3 }) })
  if self.host and self.host ~= "" then Font.draw(self.host, 32, 128) end
  for i = 1, 2 do
    local line = self.lines and self.lines[#self.lines - 2 + i]
    if line then Font.draw(line, 16, 152 + (i - 1) * 16) end
  end
  Font.popStyle()
end

return Radio
