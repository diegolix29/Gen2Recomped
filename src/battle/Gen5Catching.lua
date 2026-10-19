-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S CAPTURE SUM (Gen V), beside Sinnoh's (Gen4Catching).
--
--   X = (3M - 2H) * G * C * B / (3M) * S          (fixed point, 1/4096)
--       G  thick (dark) grass only: by Pokemon caught -- >600 1, 451-600
--          3686/4096, 301-450 3277, 151-300 2867, 31-150 2048, else 1229
--       B  the ball (below), S 2.5 asleep / frozen, 1.5 poisoned / burned /
--          paralysed
--   X >= 255: caught.
--   CRITICAL CAPTURE: floor(min(255, X) * P / 6) out of 256, P by Pokemon
--   caught: >600 2.5, 451-600 2, 301-450 1.5, 151-300 1, 31-150 0.5, else 0.
--   Y = floor(65536 / sqrt(sqrt(255 / X))); a check passes on a draw 0..65535
--   below Y. THREE checks (one on a critical capture). The ball breaks open
--   at once when the first fails, after one shake when the second does,
--   after three when the third does -- and the critical ball shakes once.
--
-- Balls, by item id (ids 1..16 are Platinum's, 492..499 the Apricorn balls
-- Unova cannot use as anything but a Poke Ball, 576 the Dream Ball):
--   Great 1.5, Ultra 2, Safari 1.5, Net 3 on Water / Bug, Dive 3.5 on water,
--   Nest (41 - level) / 10 in 1..4, Repeat 3 when owned, Timer 1 + turns *
--   1229/4096 up to 4, Dusk 3.5 at night or in a cave, Quick 5 on the first
--   turn; Master always; the rest 1.

local G = {}

G.MASTER, G.ULTRA, G.GREAT, G.POKE, G.SAFARI = 1, 2, 3, 4, 5
G.NET, G.DIVE, G.NEST, G.REPEAT, G.TIMER = 6, 7, 8, 9, 10
G.LUXURY, G.PREMIER, G.DUSK, G.HEAL, G.QUICK, G.CHERISH = 11, 12, 13, 14, 15, 16
G.FRIEND, G.DREAM = 497, 576

local FX = 4096
local floor = math.floor

local function hasType(ctx, want)
  for _, t in ipairs((ctx.targetDef and ctx.targetDef.types) or {}) do
    if tostring(t):upper() == want then return true end
  end
  for _, t in ipairs(ctx.types or {}) do
    if tostring(t):upper() == want then return true end
  end
  return false
end

-- the ball's bonus in 1/4096
function G.ballBonus(ball, ctx)
  ball = tonumber(ball)
  ctx = ctx or {}
  if ball == G.GREAT or ball == G.SAFARI then return 6144 end
  if ball == G.ULTRA then return 8192 end
  if ball == G.NET then return (hasType(ctx, "WATER") or hasType(ctx, "BUG")) and 12288 or FX end
  if ball == G.DIVE then return ctx.terrain == "water" and 14336 or FX end
  if ball == G.NEST then
    local lv = floor(tonumber(ctx.level) or 100)
    return math.max(FX, math.min(4 * FX, floor((41 - lv) * FX / 10)))
  end
  if ball == G.REPEAT then return ctx.alreadyCaught and 12288 or FX end
  if ball == G.TIMER then
    return math.min(4 * FX, FX + floor(tonumber(ctx.turns) or 0) * 1229)
  end
  if ball == G.DUSK then
    local h = tonumber(ctx.hour)
    local night = h and (h >= 20 or h < 4)
    return ((night and not ctx.indoors) or ctx.terrain == "cave") and 14336 or FX
  end
  if ball == G.QUICK then return (tonumber(ctx.turns) or 0) < 1 and 5 * FX or FX end
  return FX
end

local function band(caught, rows)
  for _, r in ipairs(rows) do if caught > r[1] then return r[2] end end
  return rows[#rows][2]
end
G.GRASS = { { 600, 4096 }, { 450, 3686 }, { 300, 3277 }, { 150, 2867 }, { 30, 2048 }, { -1, 1229 } }
G.CRIT = { { 600, 10 }, { 450, 8 }, { 300, 6 }, { 150, 4 }, { 30, 2 }, { -1, 0 } } -- quarters

local SLEEPY = { SLP = true, FRZ = true }
local SOUR = { PSN = true, BRN = true, PAR = true, TOX = true }

-- X, the number compared with 255
function G.rate(ball, ctx)
  local M = math.max(1, floor(tonumber(ctx.maxHP) or 1))
  local H = math.max(0, floor(tonumber(ctx.hp) or M))
  local C = math.max(0, floor(tonumber(ctx.catchRate) or 0))
  local grass = ctx.thickGrass and band(tonumber(ctx.caughtCount) or 0, G.GRASS) or FX
  local x = floor((3 * M - 2 * H) * grass / FX)
  x = floor(x * C * G.ballBonus(ball, ctx) / FX)
  x = x / (3 * M)
  local s = tostring(ctx.status or ""):upper()
  if SLEEPY[s] then x = x * 2.5 elseif SOUR[s] then x = x * 1.5 end
  return floor(x * FX) / FX
end

-- attempt(ball, ctx, rng) -> caught, shakes (0..3), critical
function G.attempt(ball, ctx, rng)
  rng = rng or function(a, b) return love.math.random(a, b) end
  if tonumber(ball) == G.MASTER then return true, 3, false end
  local x = G.rate(ball, ctx)
  if x >= 255 then return true, 3, false end
  if x <= 0 then return false, 0, false end
  local critQ = band(tonumber(ctx.caughtCount) or 0, G.CRIT)
  local cc = floor(math.min(255, x) * critQ / 4 / 6)
  local critical = cc > 0 and rng(0, 255) < cc
  local y = floor(65536 / math.sqrt(math.sqrt(255 / x)))
  if critical then
    if rng(0, 65535) < y then return true, 1, true end
    return false, 0, true
  end
  local SHAKES = { 0, 1, 3 }
  for i = 1, 3 do
    if rng(0, 65535) >= y then return false, SHAKES[i], false end
  end
  return true, 3, false
end

-- how many species the save has caught
function G.caughtCount(save)
  local owned = save and save.pokedex and save.pokedex.owned
  local n = 0
  for _, v in pairs(owned or {}) do if v then n = n + 1 end end
  return n
end

-- the battle's context for a throw (Gen4Catching's, plus the dex count and
-- thick grass)
function G.context(battle, mon, def)
  local ctx = require("src.battle.Gen4Catching").context(battle, mon, def)
  local save = battle and battle.game and battle.game.save
  ctx.caughtCount = G.caughtCount(save)
  ctx.thickGrass = battle and (battle.gen5ThickGrass or battle.darkGrass) or false
  local b = battle and battle.enemy
  ctx.types = b and b.curTypes or nil
  return ctx
end

return G
