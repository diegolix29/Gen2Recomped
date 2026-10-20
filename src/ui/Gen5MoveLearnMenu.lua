-- LEARNING A MOVE OVER A FULL SET, in Black and White's words on Black and
-- White's screen.
--
-- The same flow as Emerald's (src/ui/Gen3MoveLearnMenu.lua, which this rides):
-- the question, then the summary's moves page in its move-learning form
-- (Gen5SummaryMenu's `choose`: the four capsules and a fifth holding the move
-- being taught) to pick the one to forget, then the "1, 2, and... Ta-da!".
-- The Game Boy screen it fell back to before was pokered's list and lines.
--
-- The words are the cartridge's: system bank 157 for the field (a TM, an HM,
-- a move tutor -- the party menu's bank) and bank 204 in a battle (the
-- level-up learn):
--
--   157: 32 wants to learn / 35 give up? / 38 did not learn / 39 which move
--        should be forgotten? / 40 1, 2, and... forgot / 41 learned
--   204:  4 wants to learn /  7 give up? /  8 did not learn /  5 forgot /
--         6 learned how to use
--   158: 156 "HM moves can't be forgotten now." (the summary's own refusal)
--
-- Reached through Screens' MoveLearnMenu on a Black / White cache.

local G3 = require("src.ui.Gen3MoveLearnMenu")
local Strings = require("src.core.Strings")

local M = setmetatable({}, { __index = G3 })
M.__index = M

M.FIELD = { bank = 157, tryingToLearn = 32, stopTeaching = 35, didNotLearn = 38,
            whichForget = 39, forgot = 40, learned = 41 }
M.BATTLE = { bank = 204, tryingToLearn = 4, stopTeaching = 7, didNotLearn = 8,
             whichForget = nil, forgot = 5, learned = 6 }
M.HM_LINE = { 158, 156 }

-- is a battle under this screen? (BattleState builds it with no onDone)
local function inBattle(game)
  local BS = package.loaded["src.battle.BattleState"]
  local states = game and game.stack and (game.stack.states or game.stack.stack)
  if not (BS and type(states) == "table") then return false end
  for _, s in ipairs(states) do
    if getmetatable(s) == BS or (type(BS) == "table" and getmetatable(s) and getmetatable(s).__index == BS) then
      return true
    end
  end
  return false
end

function M.new(game, mon, newMoveId, onDone)
  local self = G3.new(game, mon, newMoveId, onDone)
  setmetatable(self, M)
  self.lines = inBattle(game) and M.BATTLE or M.FIELD
  return self
end

function M:text(role, var2)
  local U = require("src.inventory.Gen5ItemUse")
  local n = self.lines[role] or M.FIELD[role]
  local bank = self.lines[role] and self.lines.bank or M.FIELD.bank
  local fallback = G3.fill(G3.line(self.game, role), self:monName(), var2 or self:moveName())
  if not n then return fallback end
  local text = U.line(self.game.data, ("TEXT_G5S_%04d_%05d"):format(bank, n),
                      { self:monName(), var2 or self:moveName() }, "")
  return text ~= "" and text or fallback
end

function M:say(role, onClose, opts)
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, self:text(role), onClose, opts))
end

function M:forget(index)
  local moves = self.mon.moves or {}
  local old = moves[index]
  if old and require("src.ui.MoveLearnMenu").hmMoves(self.game)[old.id] then
    local U = require("src.inventory.Gen5ItemUse")
    local line = U.line(self.game.data, ("TEXT_G5S_%04d_%05d"):format(M.HM_LINE[1], M.HM_LINE[2]), nil,
                        Strings("HM moves can't be\nforgotten now."))
    self.game.stack:push(require("src.render.TextBox").new(self.game, line))
    return false
  end
  return G3.forget(self, index)
end

function M:finish(learned)
  local TextBox = require("src.render.TextBox")
  local game = self.game
  self.selecting = false
  game.stack:pop()
  local text
  if learned then
    text = self:text("forgot", self.forgot) .. "\f" .. self:text("learned")
  else
    text = self:text("didNotLearn")
  end
  game.stack:push(TextBox.new(game, text, function()
    if self.onDone then self.onDone(learned) end
  end))
end

-- THE MOVE LEARNED INTO A FREE SLOT, in Black and White's words: the field's
-- (bank 157 line 41, a TM / HM, a Rare Candy, an evolution) or the battle's
-- (bank 14 line 688). nil off a Black / White cache, so a caller keeps its
-- own line; `battle` true for the battle's.
M.LEARNED_FIELD = { 157, 41 }
M.LEARNED_BATTLE = { 14, 688 }

function M.learnedLine(game, monName, moveName, battle)
  local okV, V = pcall(require, "src.core.GameVersion")
  if not (okV and V.isGen5 and V.isGen5()) then return nil end
  local at = battle and M.LEARNED_BATTLE or M.LEARNED_FIELD
  local U = require("src.inventory.Gen5ItemUse")
  local text = U.line(game and game.data, ("TEXT_G5S_%04d_%05d"):format(at[1], at[2]),
                      { tostring(monName), tostring(moveName) }, "")
  return text ~= "" and text or nil
end

return M
