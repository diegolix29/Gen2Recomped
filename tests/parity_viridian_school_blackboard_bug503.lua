-- Regression (#503): the Viridian School House blackboard and notebook
-- were both dead A presses -- data/events/hidden_events.asm's two
-- hidden_text_predef rows for this map never reached data/generated/
-- field.lua (tools/extract/field.py only parses `hidden_event` rows), and
-- there was no onInteract hook for this map at all. Same shape as the
-- Celadon Mansion roof house fix (#391, tests/parity_celadon_roof_
-- readables.lua): ViridianSchoolBlackboard (engine/events/hidden_events/
-- school_blackboard.asm) prints the intro, then loops a "which heading"
-- prompt and a 5-status menu (SLP/PSN/PAR/BRN/FRZ) plus QUIT until B/QUIT
-- closes it; ViridianSchoolNotebook (school_notebooks.asm) is a 5-page
-- book that asks to turn pages 1-3, auto-turns 4, and the girl catches you
-- on page 5.
--
-- Self-contained; run via
-- `luajit tests/parity_viridian_school_blackboard_bug503.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.VIRIDIAN_SCHOOL_HOUSE) then Data:load() end
local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end
require("data.scripts.init")
local MapScripts = require("src.script.MapScripts")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local S = require("tests.harness").suite("parity Viridian School blackboard/notebook (#503)")
local check, eq = S.check, S.eq

local MAP = "VIRIDIAN_SCHOOL_HOUSE"

for _, key in ipairs({
    "_ViridianSchoolBlackboardText1", "_ViridianSchoolBlackboardText2",
    "_ViridianBlackboardSleepText", "_ViridianBlackboardPoisonText",
    "_ViridianBlackboardPrlzText", "_ViridianBlackboardBurnText",
    "_ViridianBlackboardFrozenText",
    "_ViridianSchoolNotebookText1", "_ViridianSchoolNotebookText5",
    "_TurnPageText" }) do
  check(type(Data.text[key]) == "string" and Data.text[key] ~= "",
        key .. " is extracted")
end

local hooks = MapScripts.get(MAP)
check(hooks and type(hooks.onInteract) == "function",
      MAP .. " registers onInteract for the two readables")

local stack = {}
local game = {
  data = Data,
  save = { player = { name = "RED" } },
  stack = {
    push = function(_, state) stack[#stack + 1] = state end,
    pop = function() return table.remove(stack) end,
    top = function() return stack[#stack] end,
  },
}
local ow = { player = { facing = "up" } }

local function pages(box)
  local out = {}
  for _, page in ipairs(box.pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return table.concat(out, "\n")
end

-- cells that are neither the blackboard (3,0) nor the notebook (3,4) stay silent
for _, cell in ipairs({ { 4, 0 }, { 3, 1 }, { 4, 4 }, { 3, 3 }, { 2, 0 } }) do
  eq(hooks.onInteract(game, ow, cell[1], cell[2]), false,
     ("(%d,%d) is not one of the readables"):format(cell[1], cell[2]))
end

-- === the blackboard: intro -> prompt -> 6-item menu (5 statuses + QUIT) ===
stack = {}
eq(hooks.onInteract(game, ow, 3, 0), true, "the blackboard at (3,0) is claimed")
local intro = stack[#stack]
check(getmetatable(intro) == TextBox, "the blackboard opens a TextBox")
check(pages(intro):find("STATUS", 1, true) ~= nil,
      "the intro is _ViridianSchoolBlackboardText1 (describes STATUS changes)")
check(type(intro.onDone) == "function", "the intro has a continuation")
intro.onDone()

local prompt = stack[#stack]
check(getmetatable(prompt) == TextBox
        and pages(prompt):find("heading", 1, true) ~= nil,
      "the intro leads into the which-heading prompt")
prompt.onDone()

local menu = stack[#stack]
check(getmetatable(menu) == Menu, "the prompt opens the status menu")
eq(#menu.items, 6, "five statuses plus QUIT")
local labels = {}
for i, item in ipairs(menu.items) do labels[i] = (item.label or ""):gsub("^%s+", "") end
eq(table.concat(labels, "/"), "SLP/PSN/PAR/BRN/FRZ/QUIT",
   "the statuses read SLP/PSN/PAR/BRN/FRZ, QUIT last")
eq(menu.items[6].onSelect, nil, "QUIT has no onSelect; Menu's own B/pop closes it")

local STATUS_KEYS = {
  "_ViridianBlackboardSleepText", "_ViridianBlackboardPoisonText",
  "_ViridianBlackboardPrlzText", "_ViridianBlackboardBurnText",
  "_ViridianBlackboardFrozenText",
}
for i, key in ipairs(STATUS_KEYS) do
  stack = {}
  menu.items[i].onSelect()
  local blurb = stack[#stack]
  check(getmetatable(blurb) == TextBox, labels[i] .. " prints a text box")
  local want = Data.text[key]:match("^[^\n\011\012]+")
  check(pages(blurb):find(want, 1, true) ~= nil,
        labels[i] .. " prints " .. key)
  check(type(blurb.onDone) == "function",
        labels[i] .. " returns to the prompt instead of dropping out (loops)")
  blurb.onDone()
  check(getmetatable(stack[#stack]) == TextBox,
        "the prompt comes back after " .. labels[i])
  stack[#stack].onDone()
  check(getmetatable(stack[#stack]) == Menu,
        "the menu comes back after " .. labels[i] .. " (loop, not exit)")
end

-- === the notebook: five pages, three yes/no turns, then the girl catches you ==
stack = {}
eq(hooks.onInteract(game, ow, 3, 4), true, "the notebook at (3,4) is claimed")
local page1 = stack[#stack]
check(getmetatable(page1) == TextBox, "the notebook opens on page 1")
check(pages(page1):find("POKé BALL", 1, true) ~= nil,
      "page 1 is _ViridianSchoolNotebookText1")

-- pages 1-3 ask "Turn the page?" and only turn on yes.  The real ChoiceBox
-- pops the asking TextBox itself before invoking .choice (TextBox.lua:228-
-- 235); mirror that pop-then-call order here.
local function resolveChoice(box, yes)
  table.remove(stack) -- the ChoiceBox pops the asking TextBox first
  box.choice(yes)
end

page1.onDone()
local ask1 = stack[#stack]
check(getmetatable(ask1) == TextBox and ask1.choice ~= nil,
      "page 1 asks _TurnPageText with a yes/no choice")
resolveChoice(ask1, true)
local page2 = stack[#stack]
check(pages(page2):find("weaken", 1, true) ~= nil, "yes turns to page 2")

page2.onDone()
resolveChoice(stack[#stack], true)
local page3 = stack[#stack]
check(pages(page3):find("engage", 1, true) ~= nil, "page 3 follows page 2")

page3.onDone()
resolveChoice(stack[#stack], true)
local page4 = stack[#stack]
check(pages(page4):find("ELITE FOUR", 1, true) ~= nil, "page 4 follows page 3")

-- page 4 turns automatically into page 5, no prompt
page4.onDone()
local page5 = stack[#stack]
check(getmetatable(page5) == TextBox, "page 4 auto-turns")
check(pages(page5):find("GIRL", 1, true) ~= nil,
      "page 5 is the girl catching you reading her notes")

-- saying no on page 1 stops the read right there: no further page pushed
stack = {}
hooks.onInteract(game, ow, 3, 4)
stack[#stack].onDone()
local askAgain = stack[#stack]
local before = #stack
resolveChoice(askAgain, false)
eq(#stack, before - 1,
   "saying no to the first turn pops the ask box and pushes nothing else")

S.finish()
