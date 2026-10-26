-- src/ui/HgssPokeathlonMedalList.lua -- HEARTGOLD / SOULSILVER POKeATHLON
-- DOME: THE MEDALS LIST, "Pokemon Record" (ScrCmd_712 1 ->
-- PokeathlonMedals_LaunchApp, the Trust room D49R0105; pokeheartgold
-- asm/overlay_99.s PokeathlonMedals_Init / Main / Exit = ov99_021E7818 /
-- 794C / 78E8, helpers from ov99_021E714C; overlay 98 its library). Every
-- species with a Medal, thirty icons a page; the top screen shows the one
-- under the cursor with its five Medals.
--
-- READ FROM CODE:
--   * the list (ov99_021E72C0): zukan_data (/a/0/7/4) member 11, the
--     national order 1..493 (ov99_021E714C always picks it), keeping each
--     species whose medal byte (args unk4 = PokeathlonSave_GetUnkDC, port
--     save.hgssPokeathlonMedals[species]) is not 0; natDexEnabled is never
--     read. 30 a page, 6 x 5; last page = count / 30 (one less when count is
--     a non-zero multiple of 30); the last page shows count % 30 (or 30)
--   * Medalists (ov98_0221F024) = species with all five bits; the Trust rank
--     (ov98_0221EF80) = how many of 1 2 5 10 25 50 75 100 150 200 they reach
--   * the art (ov99_021E7D30 / 7DA4, /a/1/7/7): touch screen BG0 44/46
--     (priority 3), BG2 44/47 (2, 512 wide, slides), BG3 char 48 (0, slides):
--     the Medalist mark 2 x 2 at (48 + 32 c, 32 + 24 r) over each full
--     species' icon (ov99_021E73E0); text BG1. Top BG0 45/49 (3), BG2 45/50
--     (0) the "Medalist Pokemon" banner with window 11, shown only for a
--     Medalist (ov99_021E7198)
--   * the sprites: the icons (frame 0, not animated, OBJ priority 1) at
--     (48 + 32 c, 32 + 24 r); the cursor (set 0) at (48 + 32 c, 36 + 24 r),
--     seq 0xE by keys / 0xF by touch, on Return (224, 176) seq 0xC / 0xD;
--     the page arrows (set 24) seq 0 at (16, 84) when not on the first page,
--     seq 1 at (240, 84) when not on the last; ten crowns (set 0 seq 1 below
--     the rank, else 0) at x 8 + 16 j, y 152; top: the front picture at
--     (48, 112), Medal i (set 4 seq i) at (104 + 8 {0,2,3,2,0}[i], 48 + 32 i)
--     when bit i is set
--   * the words, bank 314 (ov99_021E9FDC): #127 "Pokemon Record" (0,0) x 1;
--     #128 "Medalist Pokemon: {n}" (0,160) x 1, 3 digits; #(113 + rank)
--     (0,176) x 1 only when args unkC (flags 0xEF 0xF0 0xF1); #129
--     "{page}/{pages}" centred in (120,0) 5 tiles; #0 "Return" centred in
--     (200,168); top #124 "{species}'s Medals" (56,8); #4 Medal i's name
--     (bank 313 #15 + i) at (120,40) (136,72) (144,104) (136,136) (120,168);
--     #126 "Medalist\nPokemon" centred in (16,144) 8 x 4 on BG2's palette 1,
--     ink 1 / 2, filled with colour 3
--   * input (ov99_021E7BC8 / 7AD4, GridInputHandler, ov99_021EA250 /
--     021EA03C): pad newAndRepeat (8 then 4), no wrap, the bottom row's DOWN
--     goes to Return, Return's UP back to the cell it came from (29 if none);
--     touch cells y 28 + 24 r .. 51 + 24 r, x 32 + 32 c .. 63 + 32 c. When
--     the cursor could not move, LEFT / RIGHT alone turn the page (the
--     cursor + 5 / - 5); the arrows' touch boxes (y 68..98, x 0..30 /
--     224..254) too (the cursor to 0, or stays on Return). A page turn:
--     8 frames, 64 px each (ov99_021E7598) -- the icons leave by 256, jump
--     to the far side at frame 4 with the new page, come back; BG2 / BG3
--     scroll 512 and wrap; the cursor hides, the arrows / page number / top
--     update at frame 0. The top follows the cursor one frame late (bit 29).
--     A on Return, B, or the Return plate leave; SE 1500 on every move
--
-- STAND-INS, said so: the shared ones (src/ui/HgssPokeathlonRoomView.lua);
-- the front picture is the species' plain one (the cartridge asks the
-- Pokedex for the last-seen gender / form, and Spinda's seen personality).

local V = require("src.ui.HgssPokeathlonRoomView")
local Tr = require("src.ui.HgssPokeathlonTrophies")

local M = {}
M.__index = M
V.mixin(M)

M.PER_PAGE = 30
M.MEDAL_X = { [0] = 0, 2, 3, 2, 0 }
M.NAME_AT = { [0] = { 120, 40 }, { 136, 72 }, { 144, 104 }, { 136, 136 }, { 120, 168 } }

function M.available(game) return game and game.save ~= nil end

function M.list(save)
  local out = {}
  local t = save and save.hgssPokeathlonMedals
  for sp = 1, 493 do
    local b = math.floor(tonumber(V.at(t, sp)) or 0)
    if b ~= 0 then out[#out + 1] = { species = sp, bits = b } end
  end
  return out
end

function M.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, tick = 0 }, M)
  local save = game.save or {}
  local S = require("src.pokemon.HgssPokeathlonStats")
  self.showRank = S.flag(save, S.FLAG_SOLIDARITY) and S.flag(save, S.FLAG_TRUST) and S.flag(save, S.FLAG_POTENTIAL)
  self.entries = M.list(save)
  local n = #self.entries
  self.lastPage = math.floor(n / 30) - ((n % 30 == 0 and n > 0) and 1 or 0)
  self.medalists = Tr.medalists(save)
  self.rank = Tr.trustRank(self.medalists)
  self.page, self.cursor, self.from = 0, 0, nil
  self.cursorSeq, self.seqStart = 0xE, 0
  self.shownPage, self.iconX, self.bgX = 0, 0, 0
  self:refreshTop()
  return self
end

-- slots on page `p` (ov99_021E7158)
function M:slots(p)
  if p == self.lastPage then
    local n = #self.entries % 30
    return n == 0 and 30 or n
  end
  return 30
end

function M:entryAt(p, i)
  if i >= self:slots(p) then return nil end
  return self.entries[p * 30 + i + 1]
end

-- ov99_021E7794 / 77D8
function M:refreshTop()
  local e = self.cursor < 30 and self:entryAt(self.page, self.cursor) or nil
  self.top = e
end

function M:setSeq(seq)
  if self.cursorSeq ~= seq then self.cursorSeq, self.seqStart = seq, self.tick end
end

function M:everyFrame()
  if self.topLate then self.topLate = false; self:refreshTop() end
end

-- the grid's moves (ov99_021EA250): the new cell or nil when it cannot move
local function move(cur, from, dir)
  if cur == 30 then
    if dir == "up" then return from or 29 end
    return nil
  end
  local r, c = math.floor(cur / 6), cur % 6
  if dir == "up" then return r > 0 and cur - 6 or nil end
  if dir == "down" then return r < 4 and cur + 6 or 30 end
  if dir == "left" then return c > 0 and cur - 1 or nil end
  if dir == "right" then return c < 5 and cur + 1 or nil end
end

-- ov99_021E7CE4
function M:moveCursor(to, touched)
  if to == self.cursor and not touched then return end
  if to == 30 and self.cursor ~= 30 then self.from = self.cursor end
  self.cursor = to
  V.playSe(self.game)
  if to < 30 then self.topLate = true else self.top = nil end
  if to < 30 then self:setSeq(touched and 0xF or 0xE) else self:setSeq(touched and 0xD or 0xC) end
end

function M:turn(delta, touched)
  local p = math.max(0, math.min(self.lastPage, self.page + delta))
  if p == self.page then return end
  V.playSe(self.game)
  self.page = p
  self.slideDir = delta
  self.slide = 0
  local to
  if touched then to = self.cursor == 30 and 30 or 0
  elseif delta > 0 then to = self.cursor - 5 else to = self.cursor + 5 end
  to = math.max(0, math.min(30, to))
  self.cursor = to
  V.playSe(self.game)
end

-- ov99_021E7598, one frame; true when done
function M:slideStep()
  local c = self.slide
  local s = self.slideDir < 0 and 64 or -64
  if c == 0 then
    if self.cursor == 30 then self.top = nil else self:refreshTop() end
  end
  if c == 4 then
    self.shownPage = self.page
    self.iconX = self.iconX - 8 * s
  end
  if c < 8 then
    self.bgX = self.bgX + s
    self.iconX = self.iconX + s
    self.slide = c + 1
    return false
  end
  self.bgX, self.iconX, self.slide = 0, 0, nil
  return true
end

function M:step()
  local game = self.game
  if self.slide then
    self:slideStep()
    return false
  end
  local px, py = V.takeTouch(self)
  local leave = false
  if px then
    if V.inRect(px, py, V.RETURN) then
      self:moveCursor(30, true)
      leave = true
    elseif py >= 68 and py < 98 and px >= 0 and px < 30 then
      self:turn(-1, true)
    elseif py >= 68 and py < 98 and px >= 224 and px < 254 then
      self:turn(1, true)
    else
      for i = 0, 29 do
        local r, c = math.floor(i / 6), i % 6
        if py >= 28 + 24 * r and py < 51 + 24 * r and px >= 32 + 32 * c and px < 63 + 32 * c then
          self:moveCursor(i, true)
          break
        end
      end
    end
  else
    local moved, tried = false, nil
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      if V.repeating(self, d, 8, 4) and not moved then
        tried = d
        local to = move(self.cursor, self.from, d)
        if to and to ~= self.cursor then self:moveCursor(to, false); moved = true end
      end
    end
    if not moved and tried and self.cursor < 30 then
      if tried == "left" then self:turn(-1, false) elseif tried == "right" then self:turn(1, false) end
    end
    if V.pressed(game, "a") and self.cursor == 30 then leave = true end
  end
  if V.leaving(self, nil, nil) then leave = true end
  return leave
end

local function wrapDraw(game, key, x, y)
  x = ((x % 512) + 512) % 512
  V.layer(game, key, x, y)
  V.layer(game, key, x - 512, y)
end

function M:drawBottom()
  local game, t = self.game, self.tick
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  V.layer(game, "m_b0")
  wrapDraw(game, "m_b2", self.bgX, 0)
  -- the page's icons (OBJ priority 1) and BG3's Medalist marks over them
  local p = self.shownPage
  for i = 0, 29 do
    local e = self:entryAt(p, i)
    if e then
      local r, c = math.floor(i / 6), i % 6
      V.icon(game, e.species, 0, 48 + 32 * c + self.iconX, 32 + 24 * r, 0)
    end
  end
  for i = 0, 29 do
    local e = self:entryAt(p, i)
    if e and Tr.popcount(e.bits) == 5 then
      local r, c = math.floor(i / 6), i % 6
      local x = 48 + 32 * c + self.bgX
      for _, dx in ipairs({ -512, 0, 512 }) do
        if x + dx > -16 and x + dx < 256 then V.layer(game, "m_star", x + dx, 32 + 24 * r) end
      end
    end
  end
  -- BG1's words
  V.print(game, V.BANK, 127, 0, 0, 12, { x = 1, fallback = "Pokemon Record" })
  V.print(game, V.BANK, 128, 0, 160, 18, { x = 1, args = { V.num(self.medalists, 3) } })
  if self.showRank then V.print(game, V.BANK, 113 + self.rank, 0, 176, 24, { x = 1 }) end
  V.print(game, V.BANK, 129, 120, 0, 5, { center = true,
    args = { V.num(self.page + 1, 2), V.num(self.lastPage + 1, 2) } })
  V.print(game, V.BANK, 0, 200, 168, 6, { center = true, fallback = "Return" })
  -- the arrows, the crowns, the cursor
  if self.lastPage ~= 0 and self.page ~= 0 then V.sprite(game, 24, 0, 16, 84, t) end
  if self.lastPage ~= 0 and self.page < self.lastPage then V.sprite(game, 24, 1, 240, 84, t) end
  for j = 0, 9 do V.sprite(game, 0, j < self.rank and 1 or 0, 8 + 16 * j, 152, t) end
  if not self.slide then
    local x, y = 224, 176
    if self.cursor < 30 then x, y = 48 + 32 * (self.cursor % 6), 36 + 24 * math.floor(self.cursor / 6) end
    V.sprite(game, 0, self.cursorSeq, x, y, t - self.seqStart)
  end
end

function M:drawTop()
  local game, t = self.game, self.tick
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  V.layer(game, "m_t0")
  local e = self.top
  for i = 0, 4 do
    local at = M.NAME_AT[i]
    V.print(game, V.BANK, 4, at[1], at[2], 11, { args = { V.name(game, V.NAMES, 15 + i, "") } })
  end
  if e then
    V.front(game, { species = e.species, form = 0 }, 48, 112)
    for i = 0, 4 do
      if math.floor(e.bits / 2 ^ i) % 2 == 1 then V.sprite(game, 4, i, 104 + 8 * M.MEDAL_X[i], 48 + 32 * i, t) end
    end
    local sp = V.species(game, e.species)
    V.print(game, V.BANK, 124, 56, 8, 20, { args = { sp }, fallback = sp .. "'s Medals" })
    if Tr.popcount(e.bits) == 5 then
      V.layer(game, "m_t2")
      local bi = V.art(game).banner_ink
      local fg, sh, fill
      if bi and bi[1] then
        fg = { bi[1][1] / 255, bi[1][2] / 255, bi[1][3] / 255, 1 }
        sh = { bi[2][1] / 255, bi[2][2] / 255, bi[2][3] / 255, 1 }
        fill = bi[3]
      end
      if fill then
        love.graphics.setColor(fill[1] / 255, fill[2] / 255, fill[3] / 255, 1)
        love.graphics.rectangle("fill", 16, 144, 64, 32)
        love.graphics.setColor(1, 1, 1, 1)
      end
      V.print(game, V.BANK, 126, 16, 144, 8, { center = true, fg = fg, sh = sh, fallback = "Medalist" })
    end
  end
end

return M
