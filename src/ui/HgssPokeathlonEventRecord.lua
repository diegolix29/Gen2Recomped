-- src/ui/HgssPokeathlonEventRecord.lua -- HEARTGOLD / SOULSILVER POKeATHLON
-- DOME: THE EVENT RECORDS (ScrCmd_712 2 -> PokeathlonEventRecord_LaunchApp,
-- the Potential room D49R0106; pokeheartgold asm/overlay_99.s
-- PokeathlonEventRecord_Init / Main / Exit = ov99_021E8304 / 83F4 / 83AC,
-- overlay 98 its library). The ten events on the touch screen; the chosen
-- one's top five on the top, Single or Link.
--
-- READ FROM CODE:
--   * the records (ov99_021E93DC / 92EC): a copy of recordsSolo (port
--     save.hgssPokeathlonEventRecords, src/pokemon/HgssPokeathlonRecords.lua)
--     where each event's leading entries that beat its first mark
--     (ov98_0221F1F8 column 0, strictly: Hurdle Dash < 3000, else > 35 40 80
--     40 350 0x3000 70 30 3) are kept and a stand-in record follows them --
--     the mark itself by Chikorita, Cyndaquil and Totodile -- the fifth
--     dropping off; an event none of whose entries beat it "has no record"
--     (its icon grey, no AP, "Surpass the no. 1 record!"). The plays are
--     +0x28 untouched; link records are shown as they are
--   * the art (ov99_021E8590, /a/1/7/7, palette 51 on both): touch screen
--     BG0 52/53 (priority 3), BG2 the event icons from char 55 (6 x 6 tiles,
--     grey set 0 / coloured set 1 = link or has a record, ov99_021E86D4) at
--     (8 + 48 k, 48 + 64 g) for event 5 g + k; text BG1. Top BG0 52/54, BG2
--     the shown event's icon at (208, 0), text BG1. Link mode reloads palette
--     row 1 from the file's row 2 (ov99_021E87D0)
--   * the sprites (ov99_021E8C88): the cursor (set 0) at (32 + 48 c, 72 + 64 r)
--     seq 10 by keys / 11 by touch, on the Link button (224, 16) and on Return
--     (224, 176) seq 12 (13 when the button is touched); on each icon (solo
--     only) the "has a record" ribbon (seq 16) and, when the top record meets
--     the Potential Trophy mark (ov98_0221F1F8 column 1: Hurdle Dash <= 2400,
--     else >= 50 60 130 70 500 0x4000 100 55 9), the crown (seq 4); top: the
--     "1ST" ribbon (set 12) at (232, 48) (solo, has a record); each entry's
--     three icons at (60 + 24 k + 8 e, 44 + 32 e), the right one in front,
--     the first place's running half again as fast
--   * the words, bank 314 (ov99_021EA45C): touch #55 / #56 "Event Record
--     Single / Link Mode" (0,8) x 1; #110 "Link" / #111 "Single" centred in
--     (200,8) 6 tiles; #62 the event's name (bank 313 #20 + ev) at (0,160)
--     + (1,1); #54 "Times Joined: {n}" (7 digits) at (0,176) x 1; #0 "Return"
--     centred in (200,168). Top #65 + ev the record's name at (8, 1); the
--     status at (8,16): link #75, else (args unk10 = flags 0xEF 0xF0 0xF1)
--     #108 "New Record {player}" when the top record meets the Potential mark,
--     else #76 + ev the mark; without unk10, #109 "Surpass the no. 1 record!"
--     for no record, else #108; the AP the record was set with (unk_AEC, port
--     save.hgssPokeathlonEventPoints) as #107 (3 digits) at (136,48) and #106
--     "Total" at (160,48), solo with a record only; entry e's score at x
--     8 (16 + e), y 8 {4, 9, 13, 17, 21}[e] (+1 for the first, solo) or
--     {6, 10, 14, 18, 22} (link, names at 8 (4 + 4 e)): #86 + ev
--     (ov99_021E88EC: Hurdle Dash "{s / 30 (u8)}.{(s % 30) 10 / 30} Sec",
--     Relay Run "{s >> 10}.{(s & 0x3FF) 10 >> 10} Laps", else 3 digits),
--     #96 + ev ("---") for an empty one
--   * a mode toggle (ov99_021E8828): the new mode's palette, grid and labels;
--     the top emptied to #64 "Event Record" and the touch line to #63 "Please
--     select event" until an event is chosen again
--   * input (ov99_021E90F4, ov99_021EA3C4): a new touch on the button (y 0..31,
--     x >= 192) toggles, on an icon picks it; else pad newAndRepeat RIGHT /
--     LEFT +- 1, DOWN / UP +- 5 (one a frame, -1..10, no wrap, the rows join
--     end to end), from the button only DOWN (to the last column), from Return
--     only UP; A on the button toggles, on Return leaves; B or the Return
--     plate leave. SE 1500 on each
--
-- STAND-INS, said so: the shared ones (src/ui/HgssPokeathlonRoomView.lua);
-- the port has no link Pokeathlon, so Link mode reads
-- save.hgssPokeathlonLinkRecords[ev] = { plays, [1..5] = { score, mons,
-- name } }, which nothing writes yet (every entry "---").

local V = require("src.ui.HgssPokeathlonRoomView")
local Tr = require("src.ui.HgssPokeathlonTrophies")

local M = {}
M.__index = M
V.mixin(M)

M.STAND_IN = { 152, 155, 158 }                -- ov99_021EA350 + 4
M.SOLO_Y = { 4, 9, 13, 17, 21 }
M.LINK_Y = { 6, 10, 14, 18, 22 }

function M.available(game) return game and game.save ~= nil end

local function entries(rec)
  local out = {}
  for k = 1, 5 do
    local s = type(rec) == "table" and V.at(rec, k)
    if type(s) == "table" and s.score ~= nil then
      local mons = {}
      for i = 1, 3 do mons[i] = math.floor(tonumber(V.at(s.mons, i)) or 0) end
      out[k] = { score = math.floor(tonumber(s.score) or 0xFFFF) % 65536, mons = mons, name = s.name }
    else
      out[k] = { score = 0xFFFF, mons = { 0, 0, 0 } }
    end
  end
  return out
end

-- ov99_021E92EC: event ev's solo list with the stand-in record, and whether
-- it has a record of its own
function M.solo(save, ev)
  local rec = V.at(save and save.hgssPokeathlonEventRecords, ev)
  local list = entries(rec)
  local n = 0
  while n < 5 and Tr.meets(ev, 1, list[n + 1].score) do n = n + 1 end
  table.insert(list, n + 1, { score = Tr.MARKS[ev][1], mons = { M.STAND_IN[1], M.STAND_IN[2], M.STAND_IN[3] } })
  list[6] = nil
  list.plays = math.floor(tonumber(type(rec) == "table" and rec.plays) or 0)
  return list, n > 0
end

function M.link(save, ev)
  local rec = V.at(save and save.hgssPokeathlonLinkRecords, ev)
  local list = entries(rec)
  list.plays = math.floor(tonumber(type(rec) == "table" and rec.plays) or 0)
  return list
end

function M.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, tick = 0 }, M)
  local save = game.save or {}
  local S = require("src.pokemon.HgssPokeathlonStats")
  self.unk10 = S.flag(save, S.FLAG_SOLIDARITY) and S.flag(save, S.FLAG_TRUST) and S.flag(save, S.FLAG_POTENTIAL)
  self.soloList, self.has = {}, {}
  for ev = 0, 9 do self.soloList[ev], self.has[ev] = M.solo(save, ev) end
  self.playerName = (save.player and save.player.name) or "PLAYER"
  self.sel, self.lastCol, self.linkMode = 0, 0, false
  self.cursorSeq, self.seqStart = 10, 0
  self.ev, self.blank = 0, false
  return self
end

function M:list(ev)
  if self.linkMode then return M.link(self.game.save, ev) end
  return self.soloList[ev]
end

-- the top record meets the Potential mark (ov99_021E8518 -> ov98_0221EFE8)
function M:potential(ev) return Tr.meets(ev, 2, self.soloList[ev][1].score) end

function M:setSeq(seq)
  if self.cursorSeq ~= seq then self.cursorSeq, self.seqStart = seq, self.tick end
end

function M:cursorAt()
  if self.sel == -1 then return 224, 16 end
  if self.sel == 10 then return 224, 176 end
  return 32 + 48 * (self.sel % 5), 72 + 64 * math.floor(self.sel / 5)
end

function M:step()
  local game = self.game
  -- the requests the last frame's input left
  if self.toggle then
    self.toggle = false
    self.linkMode = not self.linkMode
    self.blank = true
  end
  if self.refresh then
    self.refresh = false
    self.ev, self.blank, self.pageStart = self.sel, false, self.tick
  end
  local px, py = V.takeTouch(self)
  if V.leaving(self, px, py) then return true end
  local old = self.sel
  if px then
    local hit
    if py < 32 and px >= 192 then hit = 0
    else
      for g = 0, 1 do
        for k = 0, 4 do
          if py >= 48 + 64 * g and py < 96 + 64 * g and px >= 8 + 48 * k and px < 56 + 48 * k then hit = 1 + 5 * g + k end
        end
      end
    end
    if hit then
      self.sel = hit - 1
      self:setSeq(11)
      V.playSe(game)
      if self.sel == -1 then self.toggle = true; self:setSeq(13); V.playSe(game) end
    end
  else
    if V.pressed(game, "a") then
      if self.sel == 10 then return true end
      if self.sel == -1 then self.toggle = true; V.playSe(game) end
    end
    local r, l = V.repeating(self, "right", 8, 4), V.repeating(self, "left", 8, 4)
    local d, u = V.repeating(self, "down", 8, 4), V.repeating(self, "up", 8, 4)
    if self.sel == -1 then
      if d then self.sel = self.lastCol end
    elseif self.sel == 10 then
      if u then self.sel = self.lastCol + 5 end
    else
      local s = self.sel
      if r then s = s + 1 elseif l then s = s - 1 elseif d then s = s + 5 elseif u then s = s - 5 end
      s = math.max(-1, math.min(10, s))
      if s >= 0 and s <= 9 then self.lastCol = s % 5 end
      self.sel = s
    end
  end
  if self.sel ~= old then
    V.playSe(game)
    if self.sel == -1 or self.sel == 10 then
      if self.cursorSeq ~= 13 then self:setSeq(12) end
    else
      if self.cursorSeq ~= 11 then self:setSeq(10) end
      if not (old == 10 and self.sel == 9) then self.refresh = true end
    end
  end
  return false
end

function M:drawBottom()
  local game, t = self.game, self.tick
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  if not (self.linkMode and V.layer(game, "e_b0_link")) then V.layer(game, "e_b0") end
  for ev = 0, 9 do
    local g, k = math.floor(ev / 5), ev % 5
    local act = (self.linkMode or self.has[ev]) and 1 or 0
    V.layer(game, ("e_icon_%d_%d"):format(ev, act), 8 + 48 * k, 48 + 64 * g)
  end
  V.print(game, V.BANK, self.linkMode and 56 or 55, 0, 8, 21, { x = 1 })
  V.print(game, V.BANK, self.linkMode and 111 or 110, 200, 8, 6, { center = true })
  if self.blank then
    V.print(game, V.BANK, 63, 0, 160, 24, { x = 1, y = 1, fallback = "Please select event" })
  else
    V.print(game, V.BANK, 62, 0, 160, 24, { x = 1, y = 1, args = { V.name(game, V.NAMES, 20 + self.ev, "") } })
    V.print(game, V.BANK, 54, 0, 176, 24, { x = 1, args = { V.num(self:list(self.ev).plays, 7) } })
  end
  V.print(game, V.BANK, 0, 200, 168, 6, { center = true, fallback = "Return" })
  if not self.linkMode then
    for ev = 0, 9 do
      if self.has[ev] then
        local x, y = 32 + 48 * (ev % 5), 72 + 64 * math.floor(ev / 5)
        V.sprite(game, 0, 16, x, y, t)
        if self:potential(ev) then V.sprite(game, 0, 4, x, y, t) end
      end
    end
  end
  local cx, cy = self:cursorAt()
  V.sprite(game, 0, self.cursorSeq, cx, cy, t - self.seqStart)
end

-- ov99_021E88EC
function M:scoreLine(ev, score, x, y)
  local game = self.game
  if score == 0xFFFF then
    V.print(game, V.BANK, 96 + ev, x, y, 11, { fallback = "---" })
    return
  end
  local args
  if ev == 0 then
    args = { V.num(math.floor(score / 30) % 256, 3), V.num(math.floor((score % 30) * 10 / 30) % 256, 1) }
  elseif ev == 6 then
    args = { V.num(math.floor(score / 1024), 3), V.num(math.floor((score % 1024) * 10 / 1024), 1) }
  else
    args = { V.num(score, 3) }
  end
  V.print(game, V.BANK, 86 + ev, x, y, 11, { args = args })
end

function M:drawTop()
  local game, t = self.game, self.tick
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  if not (self.linkMode and V.layer(game, "e_t0_link")) then V.layer(game, "e_t0") end
  if self.blank then
    V.print(game, V.BANK, 64, 8, 0, 26, { y = 1, fallback = "Event Record" })
    return
  end
  local ev = self.ev
  local list = self:list(ev)
  V.layer(game, ("e_icon_%d_%d"):format(ev, (self.linkMode or self.has[ev]) and 1 or 0), 208, 0)
  V.print(game, V.BANK, 65 + ev, 8, 0, 26, { y = 1 })
  -- the entries' icons (OBJ), the right one in front
  for e = 0, 4 do
    local en = list[e + 1]
    if en.score ~= 0xFFFF then
      local speed = e == 0 and 1.5 or 1
      for k = 0, 2 do
        local m = en.mons[k + 1]
        local sp, form = m % 1024, math.floor(m / 1024) % 32
        if sp ~= 0 then
          V.icon(game, sp, form, 60 + 24 * k + 8 * e, 44 + 32 * e, math.floor((t - (self.pageStart or 0)) * speed / 8))
        end
      end
    end
  end
  if self.linkMode then
    V.print(game, V.BANK, 75, 8, 16, 22, { fallback = "Link Mode" })
    for e = 0, 4 do
      local en = list[e + 1]
      local x = 8 * (16 + e)
      if en.score ~= 0xFFFF and en.name then V.say(game, tostring(en.name), x, 8 * (4 + 4 * e) + 1) end
      self:scoreLine(ev, en.score, x, 8 * M.LINK_Y[e + 1])
    end
    return
  end
  local has = self.has[ev]
  local status
  if self.unk10 then status = self:potential(ev) and 108 or (76 + ev)
  else status = has and 108 or 109 end
  V.print(game, V.BANK, status, 8, 16, 22, { args = { self.playerName } })
  if has then
    V.print(game, V.BANK, 107, 136, 48, 3, { args = { V.num(V.at(game.save.hgssPokeathlonEventPoints, ev) or 0, 3) } })
    V.print(game, V.BANK, 106, 160, 48, 6, { fallback = "Total" })
    V.sprite(game, 12, 0, 232, 48, t)
  end
  for e = 0, 4 do
    local en = list[e + 1]
    self:scoreLine(ev, en.score, 8 * (16 + e), 8 * M.SOLO_Y[e + 1] + (e == 0 and 1 or 0))
  end
end

return M
