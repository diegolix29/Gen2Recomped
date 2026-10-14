-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- VOLTORB FLIP'S RULES (HeartGold / SoulSilver's Game Corner), from
-- pokeheartgold src/voltorb_flip/voltorb_flip_game.c. No drawing here --
-- src/ui/HgssVoltorbFlip.lua is the screen.
--
--   * a board is one of 80 (eight levels, ten variants a level): all 25 cards
--     start as 1, then the Voltorbs, the 2s and the 3s go on random cards that
--     are still 1 (a placement gives up after 100 collisions), and a board with
--     too many "free" multipliers -- an x2 / x3 whose row or column has no
--     Voltorb -- is drawn again, up to 1000 times (GenerateBoard / RetryBoardGen)
--   * the first number flipped is the payout and every later one multiplies
--     it (capped at 50000); a Voltorb pays nothing; finding every x2 and x3 wins
--   * the next level is max(min(level, cards flipped), won and level + 1 or 1)
--     kept to 1..7; Lv. 8 is a win at Lv. 8, or five rounds in a row of eight
--     or more cards flipped and none lost from Lv. 5 up (CalcNextLevel)
--   * nothing persists: every visit to the machine starts at Lv. 1

local G = {}

G.ONE, G.TWO, G.THREE, G.VOLTORB = 1, 2, 3, 4
G.QUIT, G.WON, G.LOST = 1, 2, 3
G.MAX_COINS = 50000

-- sBoardConfigs: per level, five card mixes { voltorbs, twos, threes, max },
-- and per mix the free limits { perRowCol, total } for variant k and k + 5
G.BOARDS = {
  { { 6, 3, 1, 24, 3, 3, 3, 3 }, { 6, 0, 3, 27, 2, 2, 2, 2 }, { 6, 5, 0, 32, 3, 4, 3, 4 },
    { 6, 2, 2, 36, 3, 3, 3, 3 }, { 6, 4, 1, 48, 3, 4, 3, 4 } },
  { { 7, 1, 3, 54, 2, 3, 2, 2 }, { 7, 6, 0, 64, 3, 4, 3, 3 }, { 7, 3, 2, 72, 2, 3, 2, 2 },
    { 7, 0, 4, 81, 2, 3, 2, 2 }, { 7, 5, 1, 96, 3, 4, 3, 3 } },
  { { 8, 2, 3, 108, 2, 3, 2, 2 }, { 8, 7, 0, 128, 3, 4, 3, 3 }, { 8, 4, 2, 144, 3, 4, 3, 3 },
    { 8, 1, 4, 162, 2, 3, 2, 2 }, { 8, 6, 1, 192, 4, 3, 3, 3 } },
  { { 8, 3, 3, 216, 4, 3, 3, 3 }, { 8, 0, 5, 243, 2, 3, 2, 2 }, { 10, 8, 0, 256, 4, 5, 4, 4 },
    { 10, 5, 2, 288, 3, 4, 3, 3 }, { 10, 2, 4, 324, 3, 4, 3, 3 } },
  { { 10, 7, 1, 384, 4, 5, 4, 4 }, { 10, 4, 3, 432, 3, 4, 3, 3 }, { 10, 1, 5, 486, 3, 4, 3, 3 },
    { 10, 9, 0, 512, 4, 5, 4, 4 }, { 10, 6, 2, 576, 4, 5, 4, 4 } },
  { { 10, 3, 4, 648, 3, 4, 3, 3 }, { 10, 0, 6, 729, 3, 4, 3, 3 }, { 10, 8, 1, 768, 4, 5, 4, 4 },
    { 10, 5, 3, 864, 4, 5, 4, 4 }, { 10, 2, 5, 972, 3, 4, 3, 3 } },
  { { 10, 7, 2, 1152, 4, 5, 4, 4 }, { 10, 4, 4, 1296, 4, 5, 4, 4 }, { 13, 1, 6, 1458, 3, 4, 3, 3 },
    { 13, 9, 1, 1536, 5, 6, 5, 5 }, { 10, 6, 3, 1728, 4, 5, 4, 4 } },
  { { 10, 0, 7, 2187, 3, 4, 3, 3 }, { 10, 8, 2, 2304, 5, 6, 5, 5 }, { 10, 5, 4, 2592, 4, 5, 4, 4 },
    { 10, 2, 6, 2916, 4, 5, 4, 4 }, { 10, 7, 3, 3456, 5, 6, 5, 5 } },
}

local function rand(n) return love.math.random(0, n - 1) end
G.rand = rand

function G.new()
  return { history = {}, level = 1, boardId = 0, cards = {}, flipped = {}, memo = {},
           payout = 0, cardsFlipped = 0, outcome = 0, firstLevelUp = false, rounds = 0 }
end

-- the board's mix for boardId 0..79
function G.config(boardId)
  local lv = math.floor(boardId / 10) + 1
  local k = boardId % 10
  local row = G.BOARDS[lv][(k % 5) + 1]
  local alt = k >= 5
  return { voltorbs = row[1], twos = row[2], threes = row[3], max = row[4],
           perRowCol = alt and row[7] or row[5], total = alt and row[8] or row[6], level = lv }
end

-- CalcNextLevel, from the round just ended
function G.nextLevel(st)
  local prev = st.history[1]
  if not prev then return 1 end
  local P = math.floor(prev.boardId / 10) + 1
  local n = prev.cardsFlipped
  local won = prev.outcome == G.WON
  if won and P == 8 then return 8 end
  if P >= 5 and #st.history >= 5 then
    local all = true
    for i = 1, 5 do
      local h = st.history[i]
      if not h or h.cardsFlipped < 8 or h.outcome == G.LOST then all = false end
    end
    if all then return 8 end
  end
  for k = 7, 2, -1 do
    if (P >= k and n >= k) or (P >= k - 1 and won) then return k end
  end
  return 1
end

local function place(cards, kind, count)
  local tries = 0
  local placed = 0
  while placed < count do
    local id = rand(25) + 1
    if cards[id] == G.ONE then
      cards[id] = kind
      placed = placed + 1
    else
      tries = tries + 1
      if tries >= 100 then break end
    end
  end
end

local function lineOf(id) return math.floor((id - 1) / 5), (id - 1) % 5 end

-- RetryBoardGen: true when the board has too many free multipliers
local function retry(cards, cfg)
  local rowV, colV = {}, {}
  for r = 0, 4 do rowV[r], colV[r] = 0, 0 end
  for id = 1, 25 do
    if cards[id] == G.VOLTORB then
      local r, c = lineOf(id)
      rowV[r], colV[c] = rowV[r] + 1, colV[c] + 1
    end
  end
  local total = 0
  local perRow, perCol = {}, {}
  for r = 0, 4 do perRow[r], perCol[r] = 0, 0 end
  for id = 1, 25 do
    local v = cards[id]
    if v == G.TWO or v == G.THREE then
      local r, c = lineOf(id)
      if rowV[r] == 0 or colV[c] == 0 then
        total = total + 1
        perRow[r], perCol[c] = perRow[r] + 1, perCol[c] + 1
      end
    end
  end
  if total >= cfg.total then return true end
  for r = 0, 4 do
    if perRow[r] >= cfg.perRowCol or perCol[r] >= cfg.perRowCol then return true end
  end
  return false
end

-- SelectBoardId + GenerateBoard + the totals NewBoard keeps
function G.newBoard(st)
  local r = rand(100)
  local prevLevel = st.level
  st.level = G.nextLevel(st)
  st.levelChange = st.rounds > 0 and (st.level - prevLevel) or 0
  st.boardId = 10 * (st.level - 1) + math.floor(r / 10)
  local cfg = G.config(st.boardId)
  local cards
  for _ = 1, 1000 do
    cards = {}
    for id = 1, 25 do cards[id] = G.ONE end
    place(cards, G.VOLTORB, cfg.voltorbs)
    place(cards, G.TWO, cfg.twos)
    place(cards, G.THREE, cfg.threes)
    if not retry(cards, cfg) then break end
  end
  st.cards, st.flipped, st.memo = cards, {}, {}
  st.payout, st.cardsFlipped, st.outcome = 0, 0, 0
  st.rowPoints, st.colPoints, st.rowV, st.colV = {}, {}, {}, {}
  for i = 0, 4 do st.rowPoints[i], st.colPoints[i], st.rowV[i], st.colV[i] = 0, 0, 0, 0 end
  local max, mult = 1, 0
  for id = 1, 25 do
    local v = cards[id]
    local row, col = lineOf(id)
    if v == G.VOLTORB then
      st.rowV[row], st.colV[col] = st.rowV[row] + 1, st.colV[col] + 1
    else
      st.rowPoints[row] = st.rowPoints[row] + v
      st.colPoints[col] = st.colPoints[col] + v
      max = max * v
      if v > 1 then mult = mult + 1 end
    end
  end
  st.maxPayout = math.min(max, G.MAX_COINS)
  st.multiplierCards = mult
  return st
end

-- flip(st, id) -> card value; the payout and win are updated
function G.flip(st, id)
  if st.flipped[id] then return nil end
  st.flipped[id] = true
  st.memo[id] = nil
  local v = st.cards[id]
  if v == G.VOLTORB then
    st.outcome = G.LOST
    return v
  end
  st.cardsFlipped = st.cardsFlipped + 1
  if st.payout == 0 then st.payout = v
  else st.payout = math.min(st.payout * v, G.MAX_COINS) end
  if st.payout == st.maxPayout then st.outcome = G.WON end
  return v
end

-- the suspense line: a column or row that is 75% Voltorbs among what is left
function G.risky(st, id)
  local row, col = lineOf(id)
  local function share(isRow)
    local v, left = 0, 0
    for i = 0, 4 do
      local cid = isRow and (row * 5 + i + 1) or (i * 5 + col + 1)
      if not st.flipped[cid] then
        left = left + 1
        if st.cards[cid] == G.VOLTORB then v = v + 1 end
      end
    end
    return left > 0 and math.floor(100 * v / left) or 0
  end
  return share(false) >= 75 or share(true) >= 75
end

-- UpdateHistoryAndReset: the round goes on the front of the five
function G.endRound(st, outcome)
  if outcome then st.outcome = outcome end
  table.insert(st.history, 1, { outcome = st.outcome, cardsFlipped = st.cardsFlipped,
                                boardId = st.boardId, level = st.level })
  while #st.history > 5 do table.remove(st.history) end
  st.rounds = st.rounds + 1
end

function G.toggleMemo(st, id, bit)
  if st.flipped[id] then return false end
  local m = st.memo[id] or 0
  if math.floor(m / bit) % 2 == 1 then m = m - bit else m = m + bit end
  st.memo[id] = m ~= 0 and m or nil
  return true
end

function G.hasMemo(st, id, bit)
  return math.floor((st.memo[id] or 0) / bit) % 2 == 1
end

return G
