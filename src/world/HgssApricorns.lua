-- HeartGold / SoulSilver's Apricorns: the trees, the Apricorn Box and Kurt.
--
-- pokeheartgold, transcribed:
--
--   * apricorn_tree_sys.c -- 31 trees, each one colour (sTreeApricorns,
--     APRICORN_RED 1 .. APRICORN_BLK 7; the script sees colour - 1); a tree
--     has one Apricorn, shaking it off empties the tree, and every tree that
--     is empty grows one back when a day passes (sub_0202AE74 from the
--     new-day handler).
--   * unk_02031B0C.s -- the box: seven counts capped at 99; Kurt's bytes (+7
--     quantity, +8 colour), set by taking that many from the box; and
--     ApricornBox_GetKurtBall, colour -> Level, Moon, Lure, Friend, Love,
--     Fast, Heavy Ball (Poke Ball past the end).
--
-- The state lives on the save (`save.hgssApricorns`).

local A = {}

A.RED, A.YLW, A.BLU, A.GRN, A.PNK, A.WHT, A.BLK = 1, 2, 3, 4, 5, 6, 7

A.TREES = {
  A.BLK, A.PNK, A.YLW, A.GRN, A.BLU, A.GRN, A.GRN, A.PNK, A.BLK, A.PNK,
  A.BLK, A.GRN, A.BLU, A.RED, A.BLU, A.BLK, A.WHT, A.GRN, A.PNK, A.GRN,
  A.YLW, A.BLK, A.RED, A.GRN, A.GRN, A.YLW, A.BLU, A.WHT, A.RED, A.YLW,
  A.WHT,
}

-- _020F68D0: Level 493, Moon 498, Lure 494, Friend 497, Love 496, Fast 492,
-- Heavy 495 (constants/items.h)
A.BALLS = { 493, 498, 494, 497, 496, 492, 495 }
A.POKE_BALL = 4

A.MAX = 99
A.NAME_BANK, A.NAME_FIRST = 21, 7   -- BufferApricornName: msg_0021_00007 + id

-- the day number the trees count in (local midnight to midnight)
function A.today(now)
  local t = os.date("*t", now or os.time())
  return math.floor(os.time({ year = t.year, month = t.month, day = t.day, hour = 12 }) / 86400)
end

function A.state(save)
  local s = save.hgssApricorns
  if not s then
    s = { box = { 0, 0, 0, 0, 0, 0, 0 }, kurtColour = 0, kurtQuantity = 0, picked = {} }
    save.hgssApricorns = s
  end
  return s
end

-- a tree has its Apricorn unless it was shaken today
function A.treeHasFruit(save, idx, now)
  local day = A.state(save).picked[tostring(idx)]
  return day == nil or day < A.today(now)
end
function A.pick(save, idx, now)
  A.state(save).picked[tostring(idx)] = A.today(now)
end
-- ApricornTrees_GetApricorn: the colour, zero-based
function A.treeColour(idx)
  local c = A.TREES[(tonumber(idx) or 0) + 1]
  return c and (c - 1) or 0
end

function A.count(save, colour) return A.state(save).box[(colour or 0) + 1] or 0 end
function A.total(save)
  local n = 0
  for i = 1, 7 do n = n + (A.state(save).box[i] or 0) end
  return n
end
-- GiveApricornFromTree: refused (false) when it would pass 99
function A.give(save, colour, n)
  local box = A.state(save).box
  local i = (colour or 0) + 1
  if not box[i] or box[i] + n > A.MAX then return false end
  box[i] = box[i] + n
  return true
end

-- ApricornBox_SetKurtApricorn: colour and quantity, taken from the box
function A.setKurt(save, colour, n)
  local s = A.state(save)
  s.kurtColour, s.kurtQuantity = colour, n
  local i = colour + 1
  if s.box[i] and s.box[i] >= n then s.box[i] = s.box[i] - n end
end
function A.kurtQuantity(save) return A.state(save).kurtQuantity or 0 end
function A.kurtBall(save)
  local c = A.state(save).kurtColour or 0
  return A.BALLS[c + 1] or A.POKE_BALL
end

return A
