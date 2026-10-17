-- PLATINUM'S STORY, AS BEATS (tools/gen4_playthrough/runner.lua).
--
-- Each beat names what the cartridge's own scripts must have done when it is
-- over -- the vars and flags pokeplatinum's scripts set -- so a beat fails
-- exactly where the port stops agreeing with the game. Run:
--
--   INSTALL=G:/Gen2Recomped/platinum VERSION=platinum MAP=T01R0202 X=4 Y=6 \
--     FACING=up PLAYTHROUGH=platinum TICKS=200000 love tools/gen4_hgss_overworld_harness

local B = {}

-- the bedroom's frame script: the TV's "Let's ask Prof. Rowan" notice
B[#B + 1] = { name = "bedroom",
  steps = { { "mash", 60 } },
  expect = function(r) return r:var(0x40F9) == 1 end, why = "0x40F9 = 1 (bedroom scene)" }

-- downstairs: Mom's scene (T01R0201 frame row 0x40A4 == 0 -> S0065)
B[#B + 1] = { name = "mom downstairs",
  steps = { { "warpto", "T01R0201" } },
  expect = function(r) return r:var(0x40A4) >= 1 end, why = "0x40A4 >= 1 (Mom's scene)" }

-- Barry's room (T01R0102 frame row 0x40A3 == 0 -> S000F): he rushes off to
-- the lake; flag 234, 0x40A3 = 1, 0x4070 = 2
B[#B + 1] = { name = "barry's room",
  steps = { { "warpto", "T01" }, { "warpto", "T01R0101" }, { "warpto", "T01R0102" } },
  expect = function(r) return r:var(0x40A3) == 1 and r:flag(234) end, why = "0x40A3 = 1, flag 234" }

-- Route 201: Barry stops the player (coord 1, 0x4086 == 0), then the lake
-- scene with Rowan and Dawn (S03DF: 0x4086 = 1)
B[#B + 1] = { name = "route 201 to the lake",
  steps = { { "warpto", "T01R0101" }, { "warpto", "T01" },
            { "teleport", "R201", 15, 28, "up" }, { "activecoord" },
            { "until", function(r) return r:var(0x4086) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4086) >= 1 end, why = "0x4086 >= 1 (the lake scene)" }

-- the briefcase (Route 201 person 12, S042F): the starter, the battle with Barry,
-- home to Mom (S0619: 0x4086 = 2, 0x40A4 = 3, warp), the Running Shoes
-- (T01R0201 frame row 0x40A4 == 3 -> S017D: 0x40A4 = 4)
B[#B + 1] = { name = "starter and running shoes",
  steps = { { "talkto", "briefcase" },
            { "until", function(r) return r:var(0x40A4) >= 4 end, 30000 } },
  expect = function(r) return #r:party() >= 1 and r:var(0x4086) >= 2 and r:var(0x40A4) >= 4 end,
  why = "a starter, 0x4086 >= 2, 0x40A4 >= 4 (shoes)" }

return B
