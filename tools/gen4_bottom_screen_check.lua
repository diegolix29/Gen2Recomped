-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that every button on the battle's bottom screen can be
-- tapped and lands on the button it looks like, that the labels go inside the
-- buttons they name, and that `SecondScreen.toLocal` agrees with where
-- `SecondScreen.draw` actually puts the picture in all three modes.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: `toLocal` used to refuse unless
-- `raised(game)`, while `draw` never asks that -- and the battle's bottom screen
-- is drawn on `stowed`, a different question entirely. The picture was on screen
-- and every tap on it was refused. Two ends of one pipeline disagreeing about
-- when the surface exists, which is not visible from either end alone. Section 3
-- sweeps the window in each mode and requires the hit test to match the draw.
--
-- Usage: texlua tools/gen4_bottom_screen_check.lua

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local Gen4Battle = require("src.battle.Gen4Battle")
local SecondScreen = require("src.ui.SecondScreen")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local W, H = 256, 192

-- ---------------------------------------------------------------------------
section("1. the rectangles are the cartridge's, and they fit the screen")
-- ---------------------------------------------------------------------------
-- sBattleMenuTouchRects, read as { top, bottom, left, right }.
local ACTION = { fight = { 24, 144, 0, 255 }, item = { 144, 192, 0, 80 },
                 party = { 144, 192, 176, 255 }, run = { 152, 192, 88, 168 } }
for name, r in pairs(ACTION) do
  local got = Gen4Battle.ACTION_RECTS[name]
  ok(got ~= nil, "no action rect for %s", name)
  if got then
    ok(got.top == r[1] and got.bottom == r[2] and got.left == r[3] and got.right == r[4],
       "%s is %d,%d..%d,%d; the cartridge says %d,%d..%d,%d", name,
       got.top, got.left, got.bottom, got.right, r[1], r[3], r[2], r[4])
    ok(got.left >= 0 and got.right <= W and got.top >= 0 and got.bottom <= H,
       "%s runs off the 256x192 screen", name)
  end
end
-- sMoveSelectMenuTouchRects, and sMoveMenuButtonLayout's 2x2 over a cancel bar.
local MOVES = { { 24, 80, 0, 128 }, { 24, 80, 128, 255 },
                { 88, 144, 0, 128 }, { 88, 144, 128, 255 } }
for i, r in ipairs(MOVES) do
  local got = Gen4Battle.MOVE_RECTS[i]
  ok(got and got.top == r[1] and got.bottom == r[2]
     and got.left == r[3] and got.right == r[4],
     "move rect %d does not match the cartridge", i)
end
ok(Gen4Battle.MOVE_CANCEL.top == 152 and Gen4Battle.MOVE_CANCEL.bottom == 192
   and Gen4Battle.MOVE_CANCEL.left == 8 and Gen4Battle.MOVE_CANCEL.right == 248,
   "the cancel bar does not match the cartridge")
-- the four action buttons must not overlap, or a tap is ambiguous
local names = { "fight", "item", "party", "run" }
for i = 1, #names do
  for j = i + 1, #names do
    local a, b = Gen4Battle.ACTION_RECTS[names[i]], Gen4Battle.ACTION_RECTS[names[j]]
    -- half-open, matching CheckRectangleTouch's unsigned compare: touching at
    -- an edge (FIGHT ends at 144, ITEM begins at 144) is NOT an overlap
    local overlap = not (a.right <= b.left or b.right <= a.left
                      or a.bottom <= b.top or b.bottom <= a.top)
    ok(not overlap, "the %s and %s buttons overlap", names[i], names[j])
  end
end

section("2. every pixel of each layer lands on the button it looks like")
-- ORDERED, because two rects that touch at an edge must resolve the same way
-- here as in bottomHit, and `pairs` over a table has no order at all. The first
-- draft computed an expectation and then never compared it -- so an inclusive
-- hit test, which is what this file exists to catch, sailed through.
local function expected(over, x, y)
  local function inside(r)
    return r and x >= r.left and x < r.right and y >= r.top and y < r.bottom
  end
  if over == "action" then
    for i = 1, 4 do
      local slot = Gen4Battle.COMPACT_SLOTS[i]
      if inside(slot and Gen4Battle.ACTION_RECTS[slot.art]) then return "action", i end
    end
  elseif over == "moves" then
    if inside(Gen4Battle.MOVE_CANCEL) then return "cancel" end
    for i = 1, 4 do
      if inside(Gen4Battle.MOVE_RECTS[i]) then return "move", i end
    end
  end
  return nil
end

local function sweep(over)
  local hits, misses, per, wrong, firstBad = 0, 0, {}, 0, nil
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local kind, index = Gen4Battle.bottomHit(x, y, over)
      local wantKind, wantIndex = expected(over, x, y)
      if kind ~= wantKind or index ~= wantIndex then
        wrong = wrong + 1
        firstBad = firstBad or ("%d,%d: got %s/%s, the cartridge's rects give %s/%s")
          :format(x, y, tostring(kind), tostring(index),
                  tostring(wantKind), tostring(wantIndex))
      end
      if kind then hits = hits + 1 else misses = misses + 1 end
      per[kind and (kind .. ":" .. tostring(index)) or "none"] =
        (per[kind and (kind .. ":" .. tostring(index)) or "none"] or 0) + 1
    end
  end
  ok(wrong == 0, "%s layer: %d of %d pixels disagree -- %s",
     over, wrong, W * H, tostring(firstBad))
  return hits, misses, per
end
local aHits, aMiss, aPer = sweep("action")
io.write(("  action layer: %d pixels hit a button, %d hit nothing\n"):format(aHits, aMiss))
ok(aHits > 0 and aMiss > 0,
   "the action sweep found %d hits and %d misses; one of them being zero means "
   .. "the hit test answers the same thing everywhere", aHits, aMiss)
-- all four buttons must be reachable
for i = 1, 4 do
  ok((aPer["action:" .. i] or 0) > 0,
     "action button %d (%s) cannot be tapped anywhere on the screen",
     i, Gen4Battle.COMPACT_SLOTS[i].art)
end
local mHits, mMiss, mPer = sweep("moves")
io.write(("  moves layer: %d pixels hit a button, %d hit nothing\n"):format(mHits, mMiss))
for i = 1, 4 do
  ok((mPer["move:" .. i] or 0) > 0, "move button %d cannot be tapped", i)
end
ok((mPer["cancel:nil"] or 0) > 0, "the cancel bar cannot be tapped")
-- a layer name nobody draws must answer nothing at all
local bogus = 0
for y = 0, H - 1, 7 do
  for x = 0, W - 1, 7 do
    if Gen4Battle.bottomHit(x, y, "nonsense") then bogus = bogus + 1 end
  end
end
ok(bogus == 0, "%d points hit a button on a layer that does not exist", bogus)

section("3. the hit test agrees with where the picture is drawn")
-- rect() is what draw() transforms by, so mapping a point back through toLocal
-- has to return the same point in surface space -- in every mode, including the
-- one where rect() answers nil and draw() runs the body untransformed.
local function fakeGame(mode, scaleIndex)
  return {
    data = { isGen4Cache = true },
    save = { options = { secondScreenMode = mode, secondScreenScale = scaleIndex } },
    secondScreenUp = false,          -- deliberately DOWN: draw does not ask, so
  }                                  -- neither may the hit test
end
for _, mode in ipairs({ "swap", "inset", "off" }) do
  local game = fakeGame(mode, 2)
  local rx, ry, scale = SecondScreen.rect(game)
  if not rx then rx, ry, scale = 0, 0, 1 end
  local checked, wrong, outside = 0, 0, 0
  for sy = 0, H - 1, 3 do
    for sx = 0, W - 1, 3 do
      -- a point in surface space -> where draw puts it -> back again
      local px, py = rx + sx * scale, ry + sy * scale
      local lx, ly = SecondScreen.toLocal(game, px, py)
      checked = checked + 1
      if not lx then outside = outside + 1
      elseif math.abs(lx - sx) > 0.001 or math.abs(ly - sy) > 0.001 then
        wrong = wrong + 1
      end
    end
  end
  io.write(("  %-5s rect %s,%s scale %s: %d points, %d misplaced, %d refused\n")
           :format(mode, tostring(rx), tostring(ry), tostring(scale),
                   checked, wrong, outside))
  ok(wrong == 0, "%s: %d points map to the wrong place", mode, wrong)
  ok(outside == 0,
     "%s: %d points inside the drawn picture were refused by the hit test -- "
     .. "this is the raised/stowed disagreement coming back", mode, outside)
end
-- and a point clearly off the surface is still refused
do
  local game = fakeGame("inset", 1)
  local rx, ry, scale = SecondScreen.rect(game)
  ok(SecondScreen.toLocal(game, rx - 10, ry - 10) == nil,
     "a point above and left of the panel was accepted")
  ok(SecondScreen.toLocal(game, rx + W * scale + 5, ry) == nil,
     "a point right of the panel was accepted")
end

section("4. the labels sit inside the buttons they name")
-- The port draws these because the cartridge's art carries no text: action.png
-- is four blank coloured panels and moves_00.png is four blank ones and a bar.
-- A label centred in its rect is inside it as long as the rect is wider than the
-- word, which for a proportional face is only true if somebody checks.
local LONGEST = { "POKeMON", "FIGHT", "BAG", "RUN" }
for _, word in ipairs(LONGEST) do
  local widest = #word * 8            -- the fallback width Gen4Battle uses
  local fits = false
  for _, r in pairs(Gen4Battle.ACTION_RECTS) do
    if (r.right - r.left) >= widest then fits = true end
  end
  ok(fits, "no action button is wide enough for %q at the fallback 8px a glyph", word)
end
-- every move rect must hold a 12-character move name at that fallback
for i = 1, 4 do
  local r = Gen4Battle.MOVE_RECTS[i]
  ok((r.right - r.left) >= 12 * 8,
     "move button %d is %dpx wide; a twelve-glyph name needs %d",
     i, r.right - r.left, 12 * 8)
end

section("5. the words are actually drawn, and the taps actually taken")
-- Everything above is a library nobody runs unless the battle calls it. Same
-- shape as pass 136's section 10, and pinned for the same reason.
local function slurp(rel)
  local f = io.open(root .. "../" .. rel, "rb") or io.open(rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return (s:gsub("\r\n", "\n"))
end
local gb = slurp("src/battle/Gen4Battle.lua")
ok(gb ~= nil, "could not open Gen4Battle.lua")
if gb then
  -- NOT a bare find for the call text: `function Gen4Battle.drawBottomLabels(
  -- battle, over)` contains it, so the definition alone satisfied it and the
  -- planted fault that deleted the CALL passed. Count instead -- the definition
  -- is one, the call makes two -- and require the call's own indentation.
  local mentions = select(2, gb:gsub("Gen4Battle%.drawBottomLabels%(battle, over%)", ""))
  ok(mentions >= 2,
     "drawBottomLabels appears %d time(s): it is defined and never called, so "
     .. "the buttons are blank -- which is the bug this pass exists to fix",
     mentions)
  ok(gb:find("\n    Gen4Battle.drawBottomLabels(battle, over)\n", 1, true) ~= nil,
     "drawBottomLabels is not called from inside the SecondScreen.draw body")
  ok(gb:find("function Gen4Battle.bottomHit(", 1, true) ~= nil,
     "the bottom-screen hit test is gone")
end
local bs = slurp("src/battle/BattleState.lua")
ok(bs ~= nil, "could not open BattleState.lua")
if bs then
  ok(bs:find("function BattleState:touchpressed(", 1, true) ~= nil,
     "the battle takes no pointer input, so the bottom screen cannot be tapped")
  ok(bs:find("Gen4B.bottomHit(x, y, over)", 1, true) ~= nil,
     "the battle's touch handler does not use the cartridge's hit test")
  -- The tap must go through a real button press, not a second copy of the menu
  -- logic: the ghost check, the Bug Contest ball and the forced-replacement
  -- branch all sit behind `wasPressed("a")`.
  -- BOTH branches, counted: an action tap and a move tap each raise their own A,
  -- and a fault that removed one of the two slipped past a single find.
  local presses = select(2, bs:gsub('input:overlayPressed%("a"%)', ""))
  ok(presses >= 2,
     'input:overlayPressed("a") appears %d time(s) in BattleState; the action '
     .. "tap and the move tap each need one, or that branch is doing its own "
     .. "thing and will drift from the button path", presses)
  ok(bs:find('input:overlayPressed("b")', 1, true) ~= nil,
     "the cancel bar does not raise a B press")
  ok(bs:find("if not GameVersion.isGen4() then return false end", 1, true) ~= nil,
     "the battle touch handler is not gated to Gen 4")
end
local ss = slurp("src/ui/SecondScreen.lua")
if ss then
  ok(ss:find("SecondScreen.raised(game) then return nil", 1, true) == nil,
     "toLocal refuses again unless the panel is `raised`, which `draw` never "
     .. "asks -- the battle draws on `stowed` and every tap would be swallowed")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)