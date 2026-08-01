-- Viridian School House's two readables (data/events/hidden_events.asm,
-- hidden_events_for VIRIDIAN_SCHOOL_HOUSE):
--   hidden_text_predef 3, 0  PrintBlackboardLinkCableText, ViridianSchoolBlackboard
--   hidden_text_predef 3, 4  PrintNotebookText, ViridianSchoolNotebook
-- tools/extract/field.py only parses `hidden_event` rows, so neither
-- hidden_text_predef row reaches data/generated/field.lua and both tiles
-- were dead A presses (#503).  Same hook shape, and the same sibling asm
-- file, as the Celadon roof house in data/scripts/celadon_eevee.lua (#391);
-- hidden_text_predef spends the facing byte on the tx_pre id, so neither
-- tile gates on facing.

local Menu = require("src.ui.Menu")
local TextBox = require("src.render.TextBox")

-- ViridianSchoolBlackboard (engine/events/hidden_events/school_blackboard.asm):
-- StatusAilmentText1/2 are the two columns of the 12x8 box at the top left
-- (hlcoord 0, 0 + `lb bc, 6, 10`); picking a status prints its
-- ViridianBlackboardStatusPointers entry and jumps back to .blackboardLoop,
-- QUIT or B falls through to .exitBlackboard.
local STATUS_LABELS = {
  { " SLP", "_ViridianBlackboardSleepText" },
  { " PSN", "_ViridianBlackboardPoisonText" },
  { " PAR", "_ViridianBlackboardPrlzText" },
  { " BRN", "_ViridianBlackboardBurnText" },
  { " FRZ", "_ViridianBlackboardFrozenText" },
}

local function blackboard(game)
  local text = game.data.text or {}
  local items, showMenu, askHeading
  function showMenu()
    game.stack:push(Menu.new(game, items,
      { tx = 0, ty = 0, tw = 12, th = 8, rowStep = 1 }))
  end
  -- ViridianSchoolBlackboardText2 is reprinted on every .blackboardLoop
  -- pass, immediately before HandleMenuInput
  function askHeading()
    game.stack:push(TextBox.new(game,
      text._ViridianSchoolBlackboardText2 or "Which heading do\nyou want to read?",
      showMenu))
  end
  items = {}
  for i, row in ipairs(STATUS_LABELS) do
    local label, key = row[1], row[2]
    items[i] = { label = label, onSelect = function()
      game.stack:push(TextBox.new(game, text[key] or label, askHeading))
    end }
  end
  -- no onSelect: Menu's own pop closes the box, matching .exitBlackboard
  items[#items + 1] = { label = " QUIT" }
  game.stack:push(TextBox.new(game,
    text._ViridianSchoolBlackboardText1
      or "The blackboard\ndescribes POKéMON\vSTATUS changes\vduring battles.",
    askHeading))
end

-- ViridianSchoolNotebook (engine/events/hidden_events/school_notebooks.asm):
-- pages 1-3 each end in TurnPageSchoolNotebook (TurnPageText + YesNoChoice)
-- and NO stops the read; page 4 turns without asking and runs straight into
-- page 5, the girl catching you at it.
local function notebook(game)
  local text = game.data.text or {}
  local function page(n, after)
    return TextBox.new(game, text["_ViridianSchoolNotebookText" .. n] or "", after)
  end
  local function turnPage(nextPage)
    return function()
      game.stack:push(TextBox.new(game, text._TurnPageText or "Turn the page?",
        nil, { choice = function(yes)
          if yes then game.stack:push(nextPage()) end
        end }))
    end
  end
  local function page5() return page(5) end
  local function page4() return page(4, function() game.stack:push(page5()) end) end
  local function page3() return page(3, turnPage(page4)) end
  local function page2() return page(2, turnPage(page3)) end
  game.stack:push(page(1, turnPage(page2)))
end

return {
  VIRIDIAN_SCHOOL_HOUSE = {
    onInteract = function(game, ow, fx, fy)
      if fx == 3 and fy == 0 then
        blackboard(game)
        return true
      end
      if fx == 3 and fy == 4 then
        notebook(game)
        return true
      end
      return false
    end,
  },
}
