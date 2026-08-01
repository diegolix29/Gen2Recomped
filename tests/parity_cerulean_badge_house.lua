-- Parity: leaving the Cerulean Badge House badge-description menu must
-- return control to the overworld after viewing a badge (#454).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity Cerulean Badge House")
local eq = S.eq
local script = require("data.scripts.flavor.cerulean_badge_house")
  .CERULEAN_BADGE_HOUSE.talk.TEXT_CERULEANBADGEHOUSE_MIDDLE_AGED_MAN

local states = {}
local game = {
  data = {
    items = {
      BOULDERBADGE = { name = "BOULDERBADGE" },
      CASCADEBADGE = { name = "CASCADEBADGE" },
      THUNDERBADGE = { name = "THUNDERBADGE" },
      RAINBOWBADGE = { name = "RAINBOWBADGE" },
      SOULBADGE = { name = "SOULBADGE" },
      MARSHBADGE = { name = "MARSHBADGE" },
      VOLCANOBADGE = { name = "VOLCANOBADGE" },
      EARTHBADGE = { name = "EARTHBADGE" },
    },
    text = {
      _CeruleanBadgeHouseMiddleAgedManText = "",
      _CeruleanBadgeHouseMiddleAgedManWhichBadgeText = "",
      _CeruleanBadgeHouseBoulderBadgeText = "",
      _CeruleanBadgeHouseMiddleAgedManVisitAnyTimeText = "",
    },
  },
  save = { player = { name = "RED" } },
  input = { wasPressed = function(_, key) return key == "b" end },
  stack = {
    push = function(_, state) states[#states + 1] = state end,
    pop = function() return table.remove(states) end,
    top = function() return states[#states] end,
  },
}

local done = false
script(game, nil, nil, function() done = true end)

local function dismissText()
  local text = game.stack:pop()
  text.onDone()
end

-- Greeting -> prompt -> first menu -> badge description -> prompt -> second menu.
dismissText()
dismissText()
local firstMenu = game.stack:top()
firstMenu.onChoose(firstMenu.items[1])
dismissText()
dismissText()

-- B follows ListMenu's real cancellation path: pop menu, then show goodbye.
game.stack:top():update(0)
dismissText()

eq(#states, 0, "backing out after viewing a badge leaves no menu behind")
eq(done, true, "backing out after viewing a badge completes the NPC script")

S.finish()
