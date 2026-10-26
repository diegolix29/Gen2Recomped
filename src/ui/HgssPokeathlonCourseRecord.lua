-- src/ui/HgssPokeathlonCourseRecord.lua -- HEARTGOLD / SOULSILVER POKeATHLON
-- DOME: THE COURSE RECORDS (ScrCmd_712 0 -> PokeathlonCourseRecord_LaunchApp,
-- the Solidarity room D49R0104; pokeheartgold asm/overlay_99.s
-- PokeathlonCourseRecord_Init / Main / Exit = ov99_021E5900 / 5A38 / 5A04,
-- overlay 98 its library). One page per single course: its best team, the
-- three events' Athlete Points, the bonus and the total.
--
-- READ FROM CODE:
--   * the record (ov99_021E5B90 / 5BB4 / 5BD8): PokeathlonSave + 0x2C c --
--     u16 AP[3], u16 total, 3 x {species | form << 9 | gender << 14 | shiny
--     << 16, pid}; a course has a record when its total is not 0; the bonus is
--     total - AP0 - AP1 - AP2 (port: save.hgssPokeathlonCourseBest[c],
--     src/pokemon/HgssPokeathlonStats.lua)
--   * args unk4 (sub_0203EE54) = flags 0xEF, 0xF0 and 0xF1 all set (the
--     three trophy rooms): only then the top's line 4 says the next mark
--   * the art (ov99_021E5C88 / 5D58, /a/1/7/7): touch screen BG1 31/32
--     (priority 3), BG2 62/63 + c (2, the course's panel, 512 wide), BG3 37/38
--     (1), text on BG0; top BG0 34/35 (3), BG1 68/69 + c (2), BG3 40/41 (1),
--     text on BG2 (0)
--   * a page change (ov99_021E5FE8 / 5EB4 / 5F74): the panels and sprites
--     11-16 start 256 px to the side the cursor came from and close in by
--     X >> 2 a frame (256 64 16 4 1 0); the course with no record has no
--     panels. The first frame redraws page 0, so it slides in with the fade
--   * the sprites (ov99_021E9840): the cursor (set 0, seq 8; 9 when touched,
--     12 on Return) at ov99_021E9574 (208,16) (240,48) (208,80) (240,112)
--     (208,144) (224,176); the Medal buttons (set 4, seq c) on the first five,
--     hidden without a record; the crowns beside them (ov99_021E6438: total
--     >= 450 seq 5 / 6 two crowns, >= 420 seq 2 / 3 one, even / odd course);
--     the team's front pictures at (96,64) (56,104) (136,104); the total in
--     small digits (set 20) at x 88 / 104 / 120, y 152 and in big ones (set 8,
--     top) at x 144 / 176 / 208, y 149, leading zeros shown; three sparkles
--     (set 20 seqs 10-12) at (128,56) (40,96) (128,152); the team's icons
--     (top) at (16,128) (24,152) (32,176)
--   * the words, bank 314 (ov99_021E96D8): touch #2 "Course record" (0,0)
--     x 1, #4 the course's Medal (bank 313 #15 + c) at (0,176) x 1, #0
--     "Return" centred in (200,168); top #3 the course's name (313 #c)
--     centred in (56,0) 18 tiles, [unk4] #5 / #6 / nothing in (16,16) by
--     total < 420 / < 450, #10 "{n}:{event}" at (24, 48 + 16 i) for the
--     course's events ov99_021E9600, #8 "{AP} Points" (3 digits) / #9 "---
--     Points" at (176, 48 + 16 i), #7 "Bonus Points" (56,96), the bonus at
--     (176,96), #1 "Points" at (208,176) with a record, the three species'
--     names at (32,128) (40,152) (48,176)
--   * input (ov99_021E6638): B leaves; a new touch on a Medal circle (r 16)
--     picks that course, on the Return plate leaves; else RIGHT / DOWN and
--     LEFT / UP move 0..5 (no wrap), A on 5 leaves; key repeat 4 then every 2
--     (SetKeyRepeatTimers(2, 4)); SE 1500 on every move. Leaving is ignored
--     while a page slides. Moving between Return and course 4 keeps the page
--
-- STAND-INS, said so: the shared ones (src/ui/HgssPokeathlonRoomView.lua);
-- the BG blend (BG3 over BG2 at 15/16) is not drawn.

local V = require("src.ui.HgssPokeathlonRoomView")

local M = {}
M.__index = M
V.mixin(M)

M.CURSOR = { [0] = { 208, 16 }, { 240, 48 }, { 208, 80 }, { 240, 112 }, { 208, 144 }, { 224, 176 } }
M.EVENTS = { [0] = { 0, 1, 6 }, { 3, 2, 9 }, { 8, 9, 1 }, { 7, 6, 3 }, { 5, 4, 0 } }  -- ov99_021E9600
M.PICS = { { 96, 64 }, { 56, 104 }, { 136, 104 } }
M.SMALL = { 120, 104, 88 }        -- ones, tens, hundreds
M.BIG = { 208, 176, 144 }
M.SPARKS = { { 128, 56, 10 }, { 40, 96, 11 }, { 128, 152, 12 } }
M.ICONS = { { 16, 128 }, { 24, 152 }, { 32, 176 } }

function M.available(game) return game and game.save ~= nil end

function M.record(save, c)
  local e = V.at(save and save.hgssPokeathlonCourseBest, c)
  local total = math.min(999, math.floor(tonumber(e and e.total) or 0))
  if total == 0 then return nil end
  local r = { total = total, points = {}, mons = {} }
  local sum = 0
  for i = 1, 3 do
    r.points[i] = math.min(999, math.floor(tonumber(V.at(e.points, i)) or 0))
    sum = sum + r.points[i]
    local m = V.at(e.mons, i) or {}
    r.mons[i] = { species = tonumber(m.species) or 0, form = tonumber(m.form) or 0, gender = m.gender,
      shiny = m.shiny and true or false, personality = tonumber(m.personality) or 0 }
  end
  r.bonus = (total - sum) % 65536
  return r
end

function M.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, tick = 0 }, M)
  local S = require("src.pokemon.HgssPokeathlonStats")
  local save = game.save or {}
  self.hint = S.flag(save, S.FLAG_SOLIDARITY) and S.flag(save, S.FLAG_TRUST) and S.flag(save, S.FLAG_POTENTIAL)
  self.records = {}
  for c = 0, 4 do self.records[c] = M.record(save, c) end
  self.cursor, self.course, self.dir = 0, 0, 1
  self.cursorSeq, self.seqStart = 8, 0
  self.scrollX, self.dirty = 0, true
  return self
end

function M:setSeq(seq)
  if self.cursorSeq ~= seq then self.cursorSeq, self.seqStart = seq, self.tick end
end

-- every frame, before the state (Main 021E5A38): the slide, then a pending page
function M:everyFrame()
  if self.scrolling then
    local r = math.floor(self.scrollX / 4)   -- an arithmetic shift: -1 stays -1
    if r == self.scrollX then r = 0 end
    self.scrollX = r
    if r == 0 then self.scrolling = false end
  end
  if self.dirty then
    self.dirty = false
    self.pageStart = self.tick
    if self.records[self.course] then self.scrollX = self.dir == 1 and -256 or 256 else self.scrollX = 0 end
    self.scrolling = true
  end
end

local function hitCircle(px, py)
  for c = 0, 4 do
    local p = M.CURSOR[c]
    local dx, dy = px - p[1], py - p[2]
    if dx * dx + dy * dy <= 16 * 16 then return c end
  end
  return nil
end

-- ov99_021E6638; true = leave
function M:step()
  local game = self.game
  local old = self.cursor
  local leave = false
  local px, py = V.takeTouch(self)
  if V.pressed(game, "b") then
    leave = true
  elseif px then
    if V.inRect(px, py, V.RETURN) then
      self.cursor, leave = 5, true
    else
      local c = hitCircle(px, py)
      if c then
        self.dir = c > old and 1 or 0
        self:setSeq(9)
        V.playSe(game)
        self.cursor = c
      end
    end
  else
    if V.repeating(self, "right", 4, 2) or V.repeating(self, "down", 4, 2) then
      if self.cursor < 5 then self.cursor, self.dir = self.cursor + 1, 1; V.playSe(game) end
    elseif V.repeating(self, "left", 4, 2) or V.repeating(self, "up", 4, 2) then
      if self.cursor > 0 then self.cursor, self.dir = self.cursor - 1, 0; V.playSe(game) end
    elseif V.pressed(game, "a") and self.cursor == 5 then
      leave = true
    end
  end
  if self.cursor ~= old then
    if self.cursor == 5 then
      self:setSeq(12)
    else
      if self.cursorSeq ~= 9 then self:setSeq(8) end
      if not (old == 5 and self.cursor == 4) then
        self.course = self.cursor
        self.dirty = true
      end
    end
  end
  return leave and not self.scrolling
end

function M:drawBottom()
  local game, t = self.game, self.tick
  local rec = self.records[self.course]
  local off = -self.scrollX
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  V.layer(game, "c_b1")
  -- OBJ priority 3: the Medal buttons, their crowns, the cursor
  for c = 0, 4 do
    local r, p = self.records[c], M.CURSOR[c]
    if r then
      V.sprite(game, 4, c, p[1], p[2], t)
      local even = c % 2 == 0
      if r.total >= 450 then V.sprite(game, 0, even and 5 or 6, p[1], p[2], t)
      elseif r.total >= 420 then V.sprite(game, 0, even and 2 or 3, p[1], p[2], t) end
    end
  end
  local cp = M.CURSOR[self.cursor]
  V.sprite(game, 0, self.cursorSeq, cp[1], cp[2], t - self.seqStart)
  if rec then V.layer(game, "c_b2_" .. self.course, off, 0) end
  V.layer(game, "c_b3")
  -- BG0's words
  V.print(game, V.BANK, 2, 0, 0, 14, { x = 1, fallback = "Course record" })
  V.print(game, V.BANK, 4, 0, 176, 14, { x = 1, args = { V.name(game, V.NAMES, 15 + self.course, "") } })
  V.print(game, V.BANK, 0, 200, 168, 6, { center = true, fallback = "Return" })
  -- OBJ priority 0: the team, the total, the sparkles
  if rec then
    for i = 1, 3 do V.front(game, rec.mons[i], M.PICS[i][1] + off, M.PICS[i][2]) end
    for k = 1, 3 do V.sprite(game, 20, V.digit(rec.total, k), M.SMALL[k] + off, 152, t) end
    for _, s in ipairs(M.SPARKS) do V.sprite(game, 20, s[3], s[1], s[2], t - (self.pageStart or 0)) end
  end
end

function M:drawTop()
  local game, t = self.game, self.tick
  local c = self.course
  local rec = self.records[c]
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  V.layer(game, "c_t0")
  if rec then V.layer(game, "c_t1_" .. c, -self.scrollX, 0) end
  V.layer(game, "c_t3")
  -- OBJ priority 1: the big total and the icons
  if rec then
    for k = 1, 3 do V.sprite(game, 8, V.digit(rec.total, k), M.BIG[k], 149, t) end
    for i = 1, 3 do
      local m = rec.mons[i]
      if m.species ~= 0 then V.icon(game, m.species, m.form, M.ICONS[i][1], M.ICONS[i][2], math.floor(t / 8)) end
    end
  end
  -- BG2's words
  V.print(game, V.BANK, 3, 56, 0, 18, { center = true, args = { V.name(game, V.NAMES, c, "") } })
  if self.hint then
    local total = rec and rec.total or 0
    if total < 420 then V.print(game, V.BANK, 5, 16, 16, 28, { center = true })
    elseif total < 450 then V.print(game, V.BANK, 6, 16, 16, 28, { center = true }) end
  end
  for i = 1, 3 do
    local ev = M.EVENTS[c][i]
    local y = 48 + 16 * (i - 1)
    V.print(game, V.BANK, 10, 24, y, 14, { args = { V.num(i, 1), V.name(game, V.NAMES, 20 + ev, "") } })
    if rec then V.print(game, V.BANK, 8, 176, y, 8, { args = { V.num(rec.points[i], 3) } })
    else V.print(game, V.BANK, 9, 176, y, 8, { fallback = "--- Points" }) end
  end
  V.print(game, V.BANK, 7, 56, 96, 14, { fallback = "Bonus Points" })
  if rec then V.print(game, V.BANK, 8, 176, 96, 8, { args = { V.num(rec.bonus, 3) } })
  else V.print(game, V.BANK, 9, 176, 96, 8, { fallback = "--- Points" }) end
  if rec then
    V.print(game, V.BANK, 1, 208, 176, 6, { fallback = "Points" })
    for i = 1, 3 do
      local m = rec.mons[i]
      if m.species ~= 0 then V.say(game, V.species(game, m.species), M.ICONS[i][1] + 16, M.ICONS[i][2]) end
    end
  end
end

return M
