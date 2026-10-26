-- THE SHARD TUTORS' COST WINDOW (Platinum): ShowShardCost <x, y, move, dest>
-- -> FieldMenuManager_NewMoveTutorCostWindow (pokeplatinum
-- src/overlay005/field_menu.c 810), CloseShardCostWindow takes it down.
--
-- A framed window SHARD_COST_WINDOW_WIDTH x HEIGHT (10 x 16 tiles) at the
-- script's tile (x, y) on BG3, drawn over the field while the tutor waits
-- for A; four pairs of lines out of bank 361 (TEXT_BANK_MENU_ENTRIES):
-- "RED SHARDS" (#273) then "X {n}" (#277, the cost in three space-padded
-- digits), and the same for BLUE (#274), YELLOW (#275), GREEN (#276), one
-- glyph row (16 px) apart. The costs are the move's sTeachableMoves row
-- (Gen4MoveTutor). Kept on the overworld as `gen4ShardCostWindow`, drawn
-- beside the money window.

local W = {}

W.BANK = 361
W.WIDTH_TILES, W.HEIGHT_TILES = 10, 16
W.TITLES = { { "red", 273 }, { "blue", 274 }, { "yellow", 275 }, { "green", 276 } }
W.AMOUNT = 277
W.ROW = 16

function W.panelFor(game, left, top, move)
  local data = game and game.data or {}
  local T = require("src.import.Gen4MoveTutor")
  local row = T.row(data.gen4_move_tutor, tonumber(move) or 0) or {}
  local Text = require("src.import.Gen4Text")
  local saved = game.stringBuffers and game.stringBuffers[1]
  local lines = {}
  for _, t in ipairs(W.TITLES) do
    lines[#lines + 1] = Text.resolve(data, W.BANK, t[2], game) or t[1]:upper()
    local n = tostring(math.floor(tonumber(row[t[1]]) or 0))
    Text.buffer(game, (" "):rep(math.max(0, 3 - #n)) .. n)
    lines[#lines + 1] = Text.resolve(data, W.BANK, W.AMOUNT, game) or ("X " .. n)
  end
  if game.stringBuffers then game.stringBuffers[1] = saved end
  return { left = math.floor(tonumber(left) or 21), top = math.floor(tonumber(top) or 1), lines = lines }
end

function W.draw(panel)
  if type(panel) ~= "table" then return false end
  local Font = require("src.render.Font")
  Font.drawBox(panel.left - 1, panel.top - 1, W.WIDTH_TILES + 2, W.HEIGHT_TILES + 2)
  love.graphics.setColor(0, 0, 0, 1)
  for i, line in ipairs(panel.lines or {}) do
    Font.draw(line, panel.left * 8, panel.top * 8 + (i - 1) * W.ROW)
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return W
