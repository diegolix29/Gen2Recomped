-- src/ui/Gen4SubMenuCursor.lua
--
-- THE BATTLE SUB-MENUS' KEYPAD CURSOR (src/battle_sub_menus/
-- battle_sub_menu_cursor.c), shared by the battle bag and the battle party
-- list.  A grid of GridMenuCursorPositions -- { x1, y1, x2, y2, up, down,
-- left, right } -- walked with the d-pad:
--
--   * a neighbour written { prev = n } is
--     BATTLE_SUB_MENU_CURSOR_GO_TO_PREVIOUS_POSITION_INDEX_MASK + n: go back
--     to the position the cursor came from, or n if there is none;
--   * a disabled position is skipped by stepping on in the same direction
--     (the `enabled` mask), and the cursor stays put if that loops;
--   * the previous position is remembered only when the new one's opposite
--     neighbour is a { prev } link (CheckShouldStorePreviousPosition).
--
-- THE CURSOR STARTS HIDDEN (IsCursorVisible): the first d-pad, A or B press
-- only shows it and is otherwise swallowed.  A tap hides it again
-- (BattleBagSprites_DisableCursor / BattlePartySprites_DisableCursor).  The
-- visible flag is the battle's (`battle.gen4CursorActive`), which is how the
-- cartridge carries `isCursorEnabled` from the battle's own menu into the bag
-- or the party list and back.
--
-- Positions are 1-based here; the cartridge's are 0-based.

local Cursor = {}
Cursor.__index = Cursor

function Cursor.new(holder, positions, start)
  local self = setmetatable({}, Cursor)
  self.holder = holder or {}
  self:set(positions, start)
  return self
end

function Cursor:visible() return self.holder.gen4CursorActive == true end
function Cursor:show() self.holder.gen4CursorActive = true end
function Cursor:hide() self.holder.gen4CursorActive = false end

function Cursor:set(positions, start, enabled)
  self.positions = positions or {}
  self.index = start or 1
  self.previous = nil
  self.enabled = enabled
end

function Cursor:isEnabled(i)
  if not self.enabled then return true end
  return self.enabled(i) and true or false
end

local DIRS = { up = "up", down = "down", left = "left", right = "right" }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

local function target(link)
  if type(link) == "table" then return link.prev, true end
  return link, false
end

function Cursor:move(dir)
  local here = self.positions[self.index]
  if not here then return false end
  local n, isPrev = target(here[dir])
  if not n then return false end
  if isPrev and self.previous then n = self.previous end
  local enabledHere = true
  local guard = 0
  while not self:isEnabled(n) do
    enabledHere = false
    guard = guard + 1
    local p = self.positions[n]
    local nxt = p and select(1, target(p[dir]))
    if not nxt or nxt == n or nxt == self.index or guard > 16 then n = self.index; break end
    n = nxt
  end
  if n == self.index then return false end
  local new = self.positions[n]
  local back = new and new[OPPOSITE[dir]]
  if type(back) == "table" and enabledHere then
    self.previous = self.index
  else
    self.previous = nil
  end
  self.index = n
  return true
end

-- One frame of keys.  Returns nil, the chosen index (A), or "back" (B).
function Cursor:tick(input)
  if not input then return nil end
  local any = input:wasPressed("a") or input:wasPressed("b")
  for d in pairs(DIRS) do any = any or input:wasPressed(d) end
  if not self:visible() then
    if any then self:show(); Cursor.sound("cursor", self.holder.data) end
    return nil
  end
  for d in pairs(DIRS) do
    if input:wasPressed(d) then
      if self:move(d) then Cursor.sound("cursor", self.holder.data) end
      return nil
    end
  end
  if input:wasPressed("a") then return self.index end
  if input:wasPressed("b") then Cursor.sound("decide", self.holder.data); return "back" end
  return nil
end

-- The four corners at the position's rectangle (drawCursorCorners insets by
-- eight, so the GridMenu rect is widened by eight first).
function Cursor:draw(battle, game, t)
  if not self:visible() then return false end
  local c = self.positions[self.index]
  if not c then return false end
  local Gen4Battle = require("src.battle.Gen4Battle")
  local i = Gen4Battle.CURSOR_INSET
  return Gen4Battle.drawCursorCorners(battle or { game = game, data = game and game.data,
                                                  frame = math.floor((t or 0) * 60) },
    { left = c[1] - i, top = c[2] - i, right = c[3] + i, bottom = c[4] + i })
end

-- SE_CONFIRM / SEQ_SE_DP_DECIDE, through whatever the sound module offers;
-- silence is the answer when it offers nothing.
function Cursor.sound(which, data)
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and type(Sound) == "table" and type(Sound.playSe) == "function") then return end
  if not data then
    local okG, Game = pcall(require, "src.core.Game")
    data = okG and type(Game) == "table" and Game.data or nil
  end
  if not data then return end
  local name = which == "cursor" and "SE_CONFIRM_sseq_3"
               or which == "heal" and "SEQ_SE_DP_KAIFUKU_sseq" or "SEQ_SE_DP_DECIDE_sseq"
  pcall(Sound.playSe, data, name)
end

-- { top, bottom, left, right } rects (TouchScreenRect, inclusive): the index
-- hit, or nil
function Cursor.hit(rects, x, y)
  for i, r in ipairs(rects) do
    if y >= r[1] and y <= r[2] and x >= r[3] and x <= r[4] then return i end
  end
  return nil
end

return Cursor
