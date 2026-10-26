-- src/ui/HgssPokeathlonTrophies.lua -- HEARTGOLD / SOULSILVER POKeATHLON
-- DOME: THE TROPHIES SCREEN behind "It's your statue!" (ScrCmd_712 3 ->
-- PokeathlonUnk_LaunchApp, { pokeathlon save, player profile }; pokeheartgold
-- asm/overlay_99.s ov99_021E677C / 021E6888 / 021E6840, overlay 98 its
-- library). The Friendship room's (D49R0107) bg event #0 at (7, 8), the
-- player's own statue (scr_seq_0128 #1): SE, "It's your statue!", fade, this,
-- fade back. Not 3D and not the statue: a two-screen page of the player's
-- four trophy rows and the points behind the fourth.
--
-- READ FROM CODE:
--   * the art (ov99_021E69D8, NARC 0xB1 = /a/1/7/7): touch screen 56 / 57 /
--     58 (main BG0, priority 3), top 59 / 60 / 61 (sub BG0); the words on BG1
--     of each, font palette row 12
--   * the numbers (ov99_021E6FD0): A = the five single courses' best totals
--     (PokeathlonSave + 0x2C c + 6) summed; B = unk_AEC[0..9] summed (the
--     Athlete Points each event record was set with, ov99_021E6F70); M = every
--     species' medal bits counted (ov99_021E6FA0); G = A + B + M; Medalists =
--     species with all five (u8, ov98_0221F024); Potential = events whose best
--     solo record meets ov98_0221F1F8's second column (ov98_0221F058: Hurdle
--     Dash <= 2400, else >= 50 60 130 70 500 0x4000 100 55 9)
--   * the trophies: Collective (ov99_021E7124) = per course 2 at >= 450, 1 at
--     >= 420; Trust (ov98_0221EF80) = how many of 1 2 5 10 25 50 75 100 150
--     200 the Medalists reach; Potential = that count; Friendship
--     (ov99_021E7100) = how many of 3000 3100 3200 3300 3400 3600 3800 4000
--     4200 4500 G reaches; T = their sum
--   * the touch screen: bank 314 #11 "{player}'s Trophies" in (0, 0) at x 1;
--     #12-#15 the rows' names in (8, 16 / 48 / 80 / 112); each row ten crowns
--     (OBJ set 0, seq 1 lit for the first `count`, seq 0 the rest) at x 16 +
--     16 k, y 40 / 72 / 104 / 136 (ov98_0221E6F0); the player (set 16, seq 0,
--     a girl seq 1 on palette 1) at (216, 40); T in big digits (set 8) at
--     x 200 / 232, y 112, no leading zeros; #32 "Earned" in (192, 144) at x 2;
--     the title #(33 + T / 2) in (8, 144) 22 x 6, centred lines; #0 "Return"
--     centred in (200, 168) 6 tiles
--   * the top: #16 in (8, 0); #(17 + F) the next Friendship mark in (8, 16);
--     #28 / #29 / #30 with A / B / M (4 digits, right-aligned) in (8, 40 / 64
--     / 88); #31 "Total" in (24, 112); F crowns at x 96 + 16 k, y 120; G in
--     big digits at x 80 / 112 / 144 / 176, y 160; #1 "Points" in (192, 176)
--   * input (ov99_021E6888): only B or a touch on the Return plate; SE 1500
--     and the fade out
--
-- STAND-INS, said so: the shared ones in src/ui/HgssPokeathlonRoomView.lua.

local V = require("src.ui.HgssPokeathlonRoomView")

local M = {}
M.__index = M
V.mixin(M)

M.COURSE_MARKS = { 450, 420 }                          -- ov98_0221EF64
M.TRUST = { 1, 2, 5, 10, 25, 50, 75, 100, 150, 200 }   -- ov98_0221F1CC
M.FRIENDSHIP = { 3000, 3100, 3200, 3300, 3400, 3600, 3800, 4000, 4200, 4500 }
-- ov98_0221F1F8: {first mark (flag 0xF1), Potential Trophy mark}
M.MARKS = { [0] = { 3000, 2400 }, { 35, 50 }, { 40, 60 }, { 80, 130 }, { 40, 70 },
  { 350, 500 }, { 0x3000, 0x4000 }, { 70, 100 }, { 30, 55 }, { 3, 9 } }
M.ROWS_Y = { 40, 72, 104, 136 }

local function popcount(v)
  v = math.floor(tonumber(v) or 0)
  local n = 0
  while v > 0 do n = n + v % 2; v = math.floor(v / 2) end
  return n
end
M.popcount = popcount

-- ov98_0221EFE8 / 0221EFB4: `score` meets event `ev`'s mark `k` (1 or 2)
function M.meets(ev, k, score)
  score = tonumber(score) or 0xFFFF
  if score == 0xFFFF then return false end
  local mark = M.MARKS[ev][k]
  if ev == 0 then
    if k == 1 then return score < mark end
    return score <= mark
  end
  if k == 1 then return score > mark end
  return score >= mark
end

-- the medal byte of every species (save.hgssPokeathlonMedals)
function M.medalists(save)
  local n, bits = 0, 0
  local t = save and save.hgssPokeathlonMedals
  for sp = 1, 493 do
    local c = popcount(V.at(t, sp))
    bits = bits + c
    if c == 5 then n = n + 1 end
  end
  return n % 256, bits
end

function M.trustRank(medalists)
  local r = 0
  for _, v in ipairs(M.TRUST) do if medalists >= v then r = r + 1 end end
  return r
end

-- ov99_021E6FD0
function M.stats(save)
  save = save or {}
  local s = { courses = {} }
  local best = save.hgssPokeathlonCourseBest
  local a, c = 0, 0
  for k = 0, 4 do
    local e = V.at(best, k)
    local total = math.min(999, math.floor(tonumber(e and e.total) or 0))
    s.courses[k] = total
    a = a + total
    if total >= M.COURSE_MARKS[1] then c = c + 2 elseif total >= M.COURSE_MARKS[2] then c = c + 1 end
  end
  local b = 0
  for ev = 0, 9 do b = b + math.floor(tonumber(V.at(save.hgssPokeathlonEventPoints, ev)) or 0) end
  local medalists, bits = M.medalists(save)
  local R = require("src.pokemon.HgssPokeathlonRecords")
  local p = 0
  for ev = 0, 9 do if M.meets(ev, 2, R.best(save, ev)) then p = p + 1 end end
  s.A, s.B, s.M = a % 65536, b % 65536, bits % 65536
  s.G = (s.A + s.B + s.M) % 65536
  s.medalists = medalists
  local f = 0
  for _, v in ipairs(M.FRIENDSHIP) do if s.G >= v then f = f + 1 end end
  s.counts = { c, M.trustRank(medalists), p, f }
  s.T = (c + s.counts[2] + p + f) % 256
  return s
end

function M.available(game) return game and game.save ~= nil end

function M.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, tick = 0 }, M)
  self.s = M.stats(game.save)
  local p = game.save and game.save.player or {}
  self.playerName = p.name or "PLAYER"
  local g = p.gender
  self.girl = (g == 1 or g == "female" or g == "girl")
  return self
end

function M:step()
  local px, py = V.takeTouch(self)
  return V.leaving(self, px, py)
end

local function bigNumber(self, v, places, xs, y)
  local n = V.digits(v)
  for k = 1, places do
    if k <= n then V.sprite(self.game, 8, V.digit(v, k), xs[places - k + 1], y, self.tick) end
  end
end

function M:drawBottom()
  local game, s = self.game, self.s
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  V.layer(game, "t_b0")
  for r = 1, 4 do
    for k = 0, 9 do V.sprite(game, 0, k < s.counts[r] and 1 or 0, 16 + 16 * k, M.ROWS_Y[r], self.tick) end
  end
  V.sprite(game, 16, self.girl and 1 or 0, 216, 40, self.tick)
  bigNumber(self, s.T, 2, { 200, 232 }, 112)
  V.print(game, V.BANK, 11, 0, 0, 24, { x = 1, args = { self.playerName }, fallback = self.playerName .. "'s Trophies" })
  for r = 1, 4 do V.print(game, V.BANK, 11 + r, 8, 16 + 32 * (r - 1), 16) end
  V.print(game, V.BANK, 32, 192, 144, 8, { x = 2, fallback = "Earned" })
  V.print(game, V.BANK, 33 + math.floor(s.T / 2), 8, 144, 22, { center = true })
  V.print(game, V.BANK, 0, 200, 168, 6, { center = true, fallback = "Return" })
end

function M:drawTop()
  local game, s = self.game, self.s
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 256, 192)
  V.layer(game, "t_t0")
  V.print(game, V.BANK, 16, 8, 0, 20)
  V.print(game, V.BANK, 17 + s.counts[4], 8, 16, 30)
  V.print(game, V.BANK, 28, 8, 40, 31, { args = { V.num(s.A, 4) } })
  V.print(game, V.BANK, 29, 8, 64, 31, { args = { V.num(s.B, 4) } })
  V.print(game, V.BANK, 30, 8, 88, 30, { args = { V.num(s.M, 4) } })
  V.print(game, V.BANK, 31, 24, 112, 10, { fallback = "Total" })
  for k = 0, 9 do V.sprite(game, 0, k < s.counts[4] and 1 or 0, 96 + 16 * k, 120, self.tick) end
  bigNumber(self, s.G, 4, { 80, 112, 144, 176 }, 160)
  V.print(game, V.BANK, 1, 192, 176, 8, { fallback = "Points" })
end

return M
