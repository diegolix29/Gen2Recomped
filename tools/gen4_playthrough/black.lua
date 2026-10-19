-- BLACK / WHITE'S STORY, AS BEATS (tools/gen4_playthrough/runner.lua).
--
-- pokeblack has not decompiled the scripts, so every var and flag below is
-- read off the cartridge's own script files (the map_scripts pool the import
-- writes: `setvarfromvalue(0x4081, 1)` in M0782's frame-table script, and so
-- on). Zones are the header numbers (Z391 the bedroom).
--
-- Run:
--
--   INSTALL=G:/Gen2Recomped/black VERSION=black MAP=Z391 X=5 Y=6 FACING=down \
--     PLAYTHROUGH=black REPEL=99999 TICKS=2000000 \
--     OUT_DIR=G:/Gen2Recomped/scratch_claude/pt_bw love tools/gen4_hgss_overworld_harness

local B = {}

-- the bedroom's frame table (M0782 S003B, run while 0x4081 == 0): Bianca and
-- Cheren arrive, then 0x4081 -> 1
B[#B + 1] = { name = "bedroom: bianca and cheren arrive",
  steps = { { "until", function(r) return r:var(0x4081) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4081) >= 1 end, why = "0x4081 >= 1" }

-- the gift box (person 2 at (5,8), M0782 S01E9): Juniper's letter, the
-- starter (0x153), then Bianca's and Cheren's battles; 0x4081 -> 2
B[#B + 1] = { name = "the gift box and the first battles",
  steps = { { "talk", 2 },
            { "until", function(r) return r:var(0x4081) >= 2 end, 60000 } },
  expect = function(r) return r:var(0x4081) >= 2 and #r:party() >= 1 end,
  why = "0x4081 >= 2, a starter", expectBudget = 8000 }

-- A CHEAT, said as one (as heartgold.lua's): the lead is rebuilt at a high
-- level with one strong move first, so the runner's A-mashing (the first
-- move, every turn) wins. The story is under test here, not the battles.
local function trainUpWith(move, level, species)
  return function(r)
    local party = r:party()
    local lead = party[1]
    if not lead then return end
    local Pokemon = require("src.pokemon.Pokemon")
    local mon = Pokemon.new(r.game.data, species or lead.species, level or 60)
    mon.nickname, mon.otName, mon.otId = lead.nickname, lead.otName, lead.otId
    mon.moves = mon.moves or {}
    table.insert(mon.moves, 1, { id = move or 94, pp = 64 })
    while #mon.moves > 4 do table.remove(mon.moves) end
    party[1] = mon
  end
end
-- at 100, not 60: since BW move effects, abilities and held items work
-- (foes' status moves, Heat Crash, Sturdy...), a lone 60 lost about half its
-- runs at Twist Mountain (Cheren's Pignite) and Dragonspiral
local trainUp = trainUpWith(58, 100)   -- Ice Beam: nothing is immune (N's Purrloin is to Psychic)
-- ...and, on the long dungeons, the party healed between maps (a Pokemon
-- Center visit, said as a cheat: a run of trainers wore the lead down)
-- (HP and status only: the cheat's first move keeps its 64 PP)
local function heal(r)
  for _, mon in ipairs(r:party()) do
    if mon.stats and mon.stats.hp then mon.hp, mon.status = mon.stats.hp, nil end
    for _, mv in ipairs(mon.moves or {}) do mv.pp = math.max(mv.pp or 0, 30) end
  end
end

-- the dialogue still up after a scene's var is set, closed with B: an A
-- here talks to the person in front again (Cheren in the Trainers' School
-- repeats his Berry line for ever)
-- (in a battle B does nothing at the command menu: there it is A, which is
-- what a flag set as a battle starts -- the Elite Four's -- leaves running)
local settle
settle = { "until", function(r)
  local top = r:top()
  settle[4] = (top and (top.battle or top.phase)) and "a" or "b"
  return not r:busy()
end, 20000, "b" }

-- downstairs (Z390): Mom's frame table (0x4085 == 0, M0780 S005D) -> 1, and
-- 0x407F -> 1 (go and see Bianca)
B[#B + 1] = { name = "mom downstairs",
  steps = { { "warpto", "Z390" },
            { "until", function(r) return r:var(0x4085) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4085) >= 1 and r:var(0x407F) >= 1 end, why = "0x4085 >= 1, 0x407F >= 1" }

-- outside (Z389): Cheren leaves (frame 0x407F == 1 -> 2); Bianca's house
-- (Z392): her father's scene (frame 0x4078 == 0 -> 1)
B[#B + 1] = { name = "bianca's house",
  steps = { { "warpto", "Z389" },
            { "until", function(r) return r:var(0x407F) >= 2 end, 20000 },
            { "warpto", "Z392" },
            { "until", function(r) return r:var(0x4078) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4078) >= 1 end, why = "0x4078 >= 1" }

-- Juniper's lab (Z396, frame 0x4079 == 0, M0792 S011A): the Pokedex
-- (flag 0x962), 0x4079 -> 1, 0x4080 -> 1
B[#B + 1] = { name = "juniper's lab",
  -- Bianca (person 4) waits at the lab door: talking to her takes the
  -- three of them in (M0778 S01B9, warp to Z396)
  steps = { { "warpto", "Z389" }, { "talk", 4 },
            { "until", function(r) return r:var(0x4080) >= 1 end, 30000 } },
  expect = function(r) return r:var(0x4079) >= 1 and r:var(0x4080) >= 1 and r:flag(0x962) end,
  why = "0x4079 >= 1, 0x4080 >= 1, flag 0x962 (Pokedex)", expectBudget = 8000 }

-- outside again: the frame table (0x4080 == 1, S02D9) has Bianca and Cheren
-- plan the trip (-> 2); the north edge's trigger (0x4080 == 2, S06C4)
-- sends the player home first (-> 3)
B[#B + 1] = { name = "nuvema: the journey begins",
  steps = { { "warpto", "Z389" },
            { "until", function(r) return r:var(0x4080) >= 2 end, 30000 },
            { "activecoord" },
            { "until", function(r) return r:var(0x4080) >= 3 end, 30000 } },
  -- the scene runs on into Route 1 and Juniper's demonstration
  expect = function(r) return r:var(0x4080) >= 3 end, why = "0x4080 >= 3", passBusy = true }

-- ROUTE 1 (Z317): Juniper's catching demonstration (person 2, M0634 S0027:
-- 0x17D, then five Poke Balls), 0x407C -> 1
B[#B + 1] = { name = "route 1: juniper's demonstration",
  steps = { { "until", function(r) return r:var(0x407C) >= 1 end, 40000 } },
  expect = function(r) return r:var(0x407C) >= 1 end, why = "0x407C >= 1", expectBudget = 8000 }

-- Route 1's north end (coord 1 at (52,6), 0x407C == 1, S042D): Bianca and
-- Cheren see the player off, 0x407C -> 2
B[#B + 1] = { name = "route 1: the north end",
  steps = { { "activecoord" },
            { "until", function(r) return r:var(0x407C) >= 2 end, 30000 } },
  expect = function(r) return r:var(0x407C) >= 2 end, why = "0x407C >= 2" }

-- ACCUMULA (Z397): Juniper (person 6 at (28,18), M0794 S0265) takes the
-- player into the Pokemon Center (0x407A -> 1); inside (Z398) her frame
-- table (0x407B == 0, S0069) -> 1, the counter (coord 1, S012D), the nurse
-- (M0855: 0x407B -> 2), then the frame table (0x407B == 2, S0195) -> 3
B[#B + 1] = { name = "accumula: juniper's pokemon center tour",
  steps = { { "teleport", "Z397", 26, 22, "up" }, { "talk", 6 },
            { "until", function(r) return r:var(0x407B) >= 1 end, 30000 },
            { "activecoord" },
            { "until", function(r) return not r:busy() end, 6000 },
            { "walkto", 7, 12 }, { "face", "up" }, { "press", "a" },
            { "until", function(r) return r:var(0x407B) >= 3 end, 30000 } },
  expect = function(r) return r:var(0x407A) >= 1 and r:var(0x407B) >= 3 end, why = "0x407A >= 1, 0x407B >= 3" }

-- back outside: the frame table (0x407A == 1, S0390) -> 2; then the square's
-- trigger (0x407A == 2, S0421/S055C): Ghetsis's speech and N's battle -> 3
B[#B + 1] = { name = "accumula: ghetsis's speech and n",
  steps = { { "do", trainUp }, { "warpto", "Z397" },
            { "until", function(r) return r:var(0x407A) >= 2 end, 20000 },
            { "activecoord" },
            { "until", function(r) return r:var(0x407A) >= 3 end, 60000 } },
  expect = function(r) return r:var(0x407A) >= 3 end, why = "0x407A >= 3", expectBudget = 8000 }

-- ROUTE 2 (Z319): Mom's call with the Running Shoes (coord 1, 0x407D == 0,
-- -> 1), then Bianca's battle at the north end (coord 2, 0x407D == 1, -> 2)
B[#B + 1] = { name = "route 2: mom's call",
  steps = { { "teleport", "Z319", 16, 40, "left" }, { "activecoord" },
            { "until", function(r) return r:var(0x407D) >= 1 end, 30000 } },
  expect = function(r) return r:var(0x407D) >= 1 end, why = "0x407D >= 1 (Running Shoes)" }

B[#B + 1] = { name = "route 2: bianca's battle",
  steps = { { "do", trainUp }, { "activecoord" },
            { "until", function(r) return r:var(0x407D) >= 2 end, 60000 } },
  expect = function(r) return r:var(0x407D) >= 2 end, why = "0x407D >= 2", expectBudget = 8000 }

-- STRIATON GYM (Z007, M0014). The entrance trigger (coord 11, 0x4082 == 0,
-- S039A) -> 1; the curtains (invisible 7 x 1 blockers): only one doorway a
-- row draws its curtain aside -- (15,36) (coord 7, S0FFB) -> 2, (9,26)
-- (coord 2, S1055) -> 3, (12,16) (coord 6, S1143) -> 4; the leader's
-- trigger (coord 1, 0x4082 == 4, S058D): the battle, the Trio Badge -> 5
-- STRIATON (Z006): Cheren (person 7, flag 0x21A) stands in the gym's door
-- until the Trainers' School (Z015) -- Bianca there (person 5, M0030
-- S03A2) ends in S05CD, which sets 0x21A
B[#B + 1] = { name = "striaton: the trainers' school",
  steps = { { "teleport", "Z006", 38, 12, "up" }, { "warpto", "Z015" }, { "talk", 5 },
            { "until", function(r) return r:flag(0x21A) end, 20000 }, settle },
  expect = function(r) return r:flag(0x21A) end, why = "flag 0x21A (Cheren leaves the gym door)" }

B[#B + 1] = { name = "striaton gym: the entrance",
  -- the man now at the door (person 8, flag 0x21B cleared by the school,
  -- M0012 S03B9) greets the player and goes in (flag 0x21B)
  steps = { { "warpto", "Z006" }, { "talk", 8 },
            { "until", function(r) return r:flag(0x21B) end, 8000 }, { "warpto", "Z007" },
            { "activecoord" }, { "until", function(r) return r:var(0x4082) >= 1 end, 20000 } },
  expect = function(r) return r:var(0x4082) >= 1 end, why = "0x4082 >= 1" }

B[#B + 1] = { name = "striaton gym: the curtains",
  steps = { { "coord", 7 }, { "until", function(r) return r:var(0x4082) >= 2 end, 8000 },
            { "coord", 2 }, { "until", function(r) return r:var(0x4082) >= 3 end, 8000 },
            { "coord", 6 }, { "until", function(r) return r:var(0x4082) >= 4 end, 8000 } },
  expect = function(r) return r:var(0x4082) >= 4 end, why = "0x4082 >= 4" }

-- ...then the leader whose type beats the starter (0x4030: 0 Snivy -> person
-- 1, S0B25, Chili; 1 Tepig -> 2; 2 Oshawott -> 3): the battle, the Trio
-- Badge, TM83 and 0x4088 -> 1
local leaderTalk = { "talk", 1 }
B[#B + 1] = { name = "striaton gym: the trio badge",
  steps = { { "do", trainUp }, { "coord", 1 },
            { "until", function(r) return r:var(0x4082) >= 5 end, 60000 },
            { "do", function(r) leaderTalk[2] = r:var(0x4030) + 1 end }, leaderTalk,
            { "until", function(r) return r:var(0x4088) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x4082) >= 5 and r:var(0x4088) >= 1 end,
  why = "0x4082 >= 5, 0x4088 >= 1 (Trio Badge)", expectBudget = 8000 }

-- out of the gym: Striaton's frame table (0x4088 == 1, M0012 S04A9) -> 2 and
-- warps into Fennel's house (Z009, frame 0x4087 == 1, S00DD -> 2, upstairs);
-- Fennel's lab (Z010, frame 0x4086 == 0, M0020 S001B): HM01 (item 420),
-- 0x4086 -> 1, 0x4094 -> 1
B[#B + 1] = { name = "fennel",
  steps = { { "warpto", "Z006", done = function(r) return r:var(0x4087) >= 1 end },
            { "until", function(r) return r:var(0x4094) >= 1 end, 40000 } },
  expect = function(r) return r:var(0x4088) >= 2 and r:var(0x4087) >= 2 and r:var(0x4086) >= 1 and r:var(0x4094) >= 1 end,
  why = "0x4088 >= 2, 0x4087 >= 2, 0x4086 >= 1, 0x4094 >= 1 (HM01)" }

-- THE DREAMYARD (Z152, M0304). A CHEAT, said as one: Cut (15) is put in the
-- lead's second slot -- the HM is in the bag (item 420, Fennel's), and the
-- party screen's TEACH is not what is under test. The tree (person 8, shared
-- script 10004) is cut; then the triggers: (23,26) (coord 1, 0x4094 == 1,
-- S034A) -> 2; (25,22) (coord 2, S0469: Munna, the grunts) -> 3; (26,14)
-- (coord 3, S0505) -> 4
local function teachCut(r)
  local lead = r:party()[1]
  if not lead then return end
  local has = false
  for _, mv in ipairs(lead.moves or {}) do if mv.id == 15 then has = true end end
  if not has then table.insert(lead.moves, 2, { id = 15, pp = 30 }) end
  while #lead.moves > 4 do table.remove(lead.moves) end
end
B[#B + 1] = { name = "the dreamyard",
  steps = { { "do", teachCut }, { "do", trainUp }, { "do", teachCut },
            { "teleport", "Z152", 10, 27, "right" }, { "talk", 8 },
            { "until", function(r) return not r:busy() end, 6000 },
            { "activecoord" }, { "until", function(r) return r:var(0x4094) >= 2 end, 30000 },
            { "activecoord" }, { "until", function(r) return r:var(0x4094) >= 3 end, 60000 },
            { "activecoord" }, { "until", function(r) return r:var(0x4094) >= 4 end, 60000 } },
  expect = function(r) return r:var(0x4094) >= 4 end, why = "0x4094 >= 4", budget = 160000 }

-- back to Fennel (Z010, person 0, M0020 S00C1 -> S041E): the Dream Mist,
-- 0x4094 -> 5, 0x4086 -> 2, 0x4088 -> 3
B[#B + 1] = { name = "fennel's dream mist",
  steps = { { "teleport", "Z010", 10, 4, "down" }, { "talk", 0 },
            { "until", function(r) return r:var(0x4094) >= 5 end, 30000 }, settle },
  expect = function(r) return r:var(0x4094) >= 5 and r:var(0x4086) >= 2 and r:var(0x4088) >= 3 end,
  why = "0x4094 >= 5, 0x4086 >= 2, 0x4088 >= 3" }

-- the Dreamyard's girl (Z152 person 0, M0304 S00C9): the elemental monkey
-- that beats the starter's leader's type (Pansage / Pansear / Panpour by
-- 0x4030), 0x4083 -> 2. Route 3's preschool trigger wants two Pokemon.
B[#B + 1] = { name = "the dreamyard's monkey",
  steps = { { "teleport", "Z152", 30, 28, "up" }, { "talk", 0 },
            { "until", function(r) return r:var(0x4083) >= 2 end, 30000 }, settle },
  expect = function(r) return r:var(0x4083) >= 2 and #r:party() >= 2 end, why = "0x4083 >= 2, two Pokemon" }

-- ROUTE 3 (Z321, M0642). Cheren at the preschool (coord 9 at (69,19),
-- 0x407E == 0, S0101): his battle, 0x407E -> 1
B[#B + 1] = { name = "route 3: cheren",
  steps = { { "do", trainUp }, { "teleport", "Z321", 76, 20, "left" }, { "coord", 9 },
            { "until", function(r) return r:var(0x407E) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x407E) >= 1 end, why = "0x407E >= 1" }

-- the stolen Pokemon: the girl's cry (coord 3 at (45,18), 0x4095 == 0,
-- S03E5) -> 1; the chase to Wellspring Cave's mouth, Bianca there (coord 6 at
-- (8,11), 0x4095 == 1, S0A8A) -> 3
B[#B + 1] = { name = "route 3: the stolen pokemon",
  steps = { { "coord", 3 }, { "until", function(r) return r:var(0x4095) >= 1 end, 30000 }, settle,
            { "coord", 6 }, { "until", function(r) return r:var(0x4095) >= 3 end, 30000 } },
  expect = function(r) return r:var(0x4095) >= 3 end, why = "0x4095 >= 3" }

-- WELLSPRING CAVE (Z324, M0648): the grunts (coord 1 at (25,4), 0x4095 == 3,
-- S0007; a tag battle with Cheren) -> 4
B[#B + 1] = { name = "wellspring cave: the grunts",
  steps = { { "do", trainUp }, { "warpto", "Z324" }, { "coord", 1 },
            { "until", function(r) return r:var(0x4095) >= 4 end, 60000 }, settle },
  expect = function(r) return r:var(0x4095) >= 4 end, why = "0x4095 >= 4" }

-- back on Route 3: the Pokemon returned to the girl (coord 4 at (43,21),
-- 0x4095 == 4, S0BBE) -> 5
B[#B + 1] = { name = "route 3: the pokemon returned",
  steps = { { "warpto", "Z321" }, { "coord", 4 },
            { "until", function(r) return r:var(0x4095) >= 5 end, 30000 }, settle },
  expect = function(r) return r:var(0x4095) >= 5 end, why = "0x4095 >= 5" }

-- Route 3's south half (coord 1 at (47,37), 0x407E == 1, S0E81): Bianca's
-- battle at the Day Care, 0x407E -> 2
B[#B + 1] = { name = "route 3: bianca's battle",
  steps = { { "do", trainUp }, { "coord", 1 },
            { "until", function(r) return r:var(0x407E) >= 2 end, 60000 }, settle },
  expect = function(r) return r:var(0x407E) >= 2 end, why = "0x407E >= 2" }

-- NACRENE (Z016, M0032): the arrival (coord 1 at (57,22), 0x4092 == 0,
-- S010E) -> 1; at the museum door (coord 2 at (36,6), 0x4092 == 1, S02BD)
-- Lenora takes the player in -> 2; inside (Z017, M0034) the welcome (coord
-- 1 at (11,23), 0x4084 == 0, S0208) -> 1
B[#B + 1] = { name = "nacrene: the arrival",
  steps = { { "teleport", "Z016", 61, 23, "left" }, { "coord", 1 },
            { "until", function(r) return r:var(0x4092) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x4092) >= 1 end, why = "0x4092 >= 1" }

B[#B + 1] = { name = "nacrene: the museum",
  steps = { { "do", trainUp }, { "coord", 2 }, { "until", function(r) return r:var(0x4092) >= 2 end, 30000 },
            settle, { "warpto", "Z017" }, { "activecoord" }, { "until", function(r) return r:var(0x4084) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x4092) >= 2 and r:var(0x4084) >= 1 end, why = "0x4092 >= 2, 0x4084 >= 1" }

-- LENORA'S GYM (Z018, M0036): the library's books. The entrance (coord 1,
-- 0x408A == 0, S0129 -> S0273) -> 1; a book on the bottom shelf row (sign
-- 12 at (6,18), S0F17) -> 2; the middle row (sign 6 at (4,10), S0C07): its
-- quiz shows the hidden switch -> 4, or, until the trainer behind (person 0,
-- S0881 -> S09BF, flag 128) is beaten, -> 3; the top row (sign 4 at (6,2),
-- S0AF6) -> 5; (13,18) (sign 21, S13B9 -> S1416) -> 6; (13,10) (sign 25,
-- S1203: the bookcase, object 3, slides off the stairs) -> 7. The librarian
-- (person 2) stands in front of that book until her battle (S06E9, flag 129)
B[#B + 1] = { name = "lenora's gym: the books",
  steps = { { "do", trainUp }, { "warpto", "Z018" }, { "coord", 1 },
            { "until", function(r) return r:var(0x408A) >= 1 end, 20000 }, settle,
            { "sign", 12 }, { "until", function(r) return r:var(0x408A) >= 2 end, 20000 }, settle,
            { "sign", 6 }, { "until", function(r) return r:var(0x408A) >= 3 end, 20000 }, settle,
            { "talk", 0 }, { "until", function(r) return r:var(0x408A) >= 4 end, 40000 }, settle,
            { "sign", 4 }, { "until", function(r) return r:var(0x408A) >= 5 end, 20000 }, settle,
            { "sign", 21 }, { "until", function(r) return r:var(0x408A) >= 6 end, 20000 }, settle,
            { "talk", 2 }, { "until", function(r) return r:flag(129) end, 40000 }, settle,
            -- (she wanders: the book is read once she is out of its way)
            { "until", function(r)
                for _, n in ipairs(r.ow.npcs or {}) do
                  if not n.hidden and n.cellX == 13 and n.cellY == 11 then return false end
                end
                return true
              end, 6000, "b" },
            { "sign", 25 }, { "until", function(r) return r:var(0x408A) >= 7 end, 20000 }, settle },
  expect = function(r) return r:var(0x408A) >= 7 end, why = "0x408A >= 7 (the stairs)", budget = 120000 }

-- downstairs (Z019, M0038): Lenora (person 0, S0015): the Basic Badge;
-- 0x4092 -> 3, 0x4084 -> 2, 0x408C -> 1 (the museum's alarm)
B[#B + 1] = { name = "lenora",
  steps = { { "do", trainUp }, { "warpto", "Z019" }, { "talk", 0 },
            { "until", function(r) return r:var(0x4092) >= 3 end, 60000 }, settle },
  expect = function(r) return r:var(0x4092) >= 3 and r:var(0x4084) >= 2 and r:var(0x408C) >= 1 end,
  why = "0x4092 >= 3, 0x4084 >= 2, 0x408C >= 1 (Basic Badge)" }

-- the museum's alarm: upstairs again (Z017), the Dragon Skull taken (coord 2
-- at (10,9), 0x4084 == 2, M0034 S0555) -> 3; outside, Nacrene's frame table
-- (0x4092 == 3, M0032 S0485: Burgh, the chase begins) -> 4
B[#B + 1] = { name = "nacrene: the dragon skull stolen",
  steps = { { "warpto", "Z018" }, { "warpto", "Z017" }, { "coord", 2 },
            { "until", function(r) return r:var(0x4084) >= 3 end, 30000 }, settle,
            { "warpto", "Z016" }, { "until", function(r) return r:var(0x4092) >= 4 end, 30000 }, settle },
  expect = function(r) return r:var(0x4084) >= 3 and r:var(0x4092) >= 4 end, why = "0x4084 >= 3, 0x4092 >= 4" }

-- PINWHEEL FOREST. The outside (Z154, M0308): Burgh's split (coord 1 at
-- (16,7), 0x408C == 1, S0033) -> 0x408C 2, 0x408D 1. Inside (Z155, M0310):
-- the grunts' wall (coord 2 at (71,71), 0x408D == 1, S0191) -> 2; the three
-- grunts in the chase (coords 3, 5, 6, 7 on 0x40AA 0 -> 4): the Dragon Skull
-- back (0x4092 -> 5, 0x408D -> 3)
B[#B + 1] = { name = "pinwheel forest: burgh",
  steps = { { "teleport", "Z154", 20, 8, "left" }, { "coord", 1 },
            { "until", function(r) return r:var(0x408C) >= 2 end, 30000 }, settle },
  expect = function(r) return r:var(0x408C) >= 2 and r:var(0x408D) >= 1 end, why = "0x408C >= 2, 0x408D >= 1" }

B[#B + 1] = { name = "pinwheel forest: the plasma grunts",
  steps = { { "do", trainUp }, { "warpto", "Z155" },
            { "coord", 2 }, { "until", function(r) return r:var(0x408D) >= 2 end, 60000 }, settle,
            { "coord", 3 }, { "until", function(r) return r:var(0x40AA) >= 1 end, 60000 }, settle,
            { "coord", 5 }, { "until", function(r) return r:var(0x40AA) >= 2 end, 60000 }, settle,
            { "coord", 6 }, { "until", function(r) return r:var(0x40AA) >= 3 end, 60000 }, settle,
            { "coord", 7 }, { "until", function(r) return r:var(0x40AA) >= 4 end, 60000 }, settle },
  expect = function(r) return r:var(0x40AA) >= 4 and r:var(0x4092) >= 5 and r:var(0x408D) >= 3 end,
  why = "0x40AA >= 4, 0x4092 >= 5, 0x408D >= 3 (the Dragon Skull)", budget = 200000 }

-- CASTELIA, on foot: out of Pinwheel Forest by its east gate (Z250 ->
-- Z251), over Skyarrow Bridge (Z249, a rail map: its east warp at
-- (111,15)) to the Castelia gate (Z252) and into the city (Z028, a rail map,
-- warp 8 -> Z031). The gym's street (Z031, M0062): Cheren at the door,
-- Burgh is out (coord 1 at (24,48), 0x40AF == 0, S00B0) -> 0x40AF 1,
-- 0x40D3 1
B[#B + 1] = { name = "castelia: the gym door",
  steps = { { "warpto", "Z250" }, { "warpto", "Z251" }, { "warpto", "Z249" }, { "warpto", "Z252" },
            { "warpto", "Z028" }, { "warpto", "Z031" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40AF) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x40AF) >= 1 and r:var(0x40D3) >= 1 end, why = "0x40AF >= 1, 0x40D3 >= 1" }

-- the pier building (Z038, frame 0x40D3 == 1, M0076 S01FC): Bianca's Munna
-- is taken -> 0x40D3 2, 0x40AD 1
B[#B + 1] = { name = "castelia: bianca's munna",
  steps = { { "teleport", "Z038", 13, 3, "down" },
            { "until", function(r) return r:var(0x40AD) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x40D3) >= 2 and r:var(0x40AD) >= 1 end, why = "0x40D3 >= 2, 0x40AD >= 1" }

-- the plaza (Z030, M0060): Burgh sends the player after the thief (coord 1
-- at (3,20), 0x40AD == 1, S001F) -> 0x40AD 2, 0x40AF 2
B[#B + 1] = { name = "castelia: burgh in the plaza",
  steps = { { "teleport", "Z030", 6, 24, "up" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40AF) >= 2 end, 30000 }, settle },
  expect = function(r) return r:var(0x40AD) >= 2 and r:var(0x40AF) >= 2 end, why = "0x40AD >= 2, 0x40AF >= 2" }

-- the Plasma door on the gym's street (Z031 coords 2-4 round (9..12,31..35),
-- 0x40AF == 2, S0261): Burgh and the player against two grunts -> 0x40AF
-- 3, 0x40D9 1; inside (Z056, M0112) the Sages (coord 1 at (6,10), 0x40D9 ==
-- 1): Munna back, 0x40D7 -> 1
B[#B + 1] = { name = "castelia: the plasma hideout",
  steps = { { "do", trainUp }, { "teleport", "Z031", 11, 40, "up" }, { "coord", 2 },
            { "until", function(r) return r:var(0x40AF) >= 3 end, 60000 }, settle,
            { "warpto", "Z056" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40D7) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x40AF) >= 3 and r:var(0x40D9) >= 2 and r:var(0x40D7) >= 1 end,
  why = "0x40AF >= 3, 0x40D9 >= 2, 0x40D7 >= 1 (the Sages, Munna back)" }

-- BURGH'S GYM (Z029, M0058): the honey walls are walked through (overlay
-- 38's sprite-0 objects) and the floor switches only animate; Burgh (person
-- 9, S01D2): the Insect Badge, TM76 (item 403), 0x40AF -> 4; then the street
-- (Z031, frame 0x40AF == 4, S007B) -> 5
B[#B + 1] = { name = "burgh: the insect badge",
  steps = { { "do", trainUp }, { "warpto", "Z031" }, { "warpto", "Z029" }, { "talk", 9 },
            { "until", function(r) return r:var(0x40AF) >= 4 end, 60000 }, settle,
            { "warpto", "Z031" }, { "until", function(r) return r:var(0x40AF) >= 5 end, 30000 }, settle },
  expect = function(r) return r:var(0x40AF) >= 5 and r:var(0x409C) >= 1 end, why = "0x40AF >= 5, 0x409C >= 1 (Insect Badge)" }

-- CASTELIA GATE (Z051, M0102): Bianca on the way out (coord 1 at (1,9),
-- 0x40AC == 1, S0084) -> 2
B[#B + 1] = { name = "castelia gate: bianca",
  steps = { { "teleport", "Z051", 4, 12, "up" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40AC) >= 2 end, 30000 }, settle },
  expect = function(r) return r:var(0x40AC) >= 2 end, why = "0x40AC >= 2" }

-- ROUTE 4 (Z326, M0652): Cheren's battle in the sand (coord 2 at (43,105),
-- 0x409C == 1, S0201) -> 2
B[#B + 1] = { name = "route 4: cheren",
  steps = { { "do", trainUp }, { "warpto", "Z326" }, { "coord", 2 },
            { "until", function(r) return r:var(0x409C) >= 2 end, 60000 }, settle },
  expect = function(r) return r:var(0x409C) >= 2 end, why = "0x409C >= 2" }

-- NIMBASA. The gate (Z090, M0180, coord 1 at (2,10), 0x40C2 == 0, S0057)
-- -> 1; the arrival with Bianca (Z062, M0124, coord 2 at (43,55), 0x4089 ==
-- 0, S00E1) -> 1
B[#B + 1] = { name = "nimbasa: the arrival",
  steps = { { "teleport", "Z090", 4, 12, "up" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40C2) >= 1 end, 30000 }, settle,
            { "warpto", "Z062" }, { "coord", 2 },
            { "until", function(r) return r:var(0x4089) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x40C2) >= 1 and r:var(0x4089) >= 1 end, why = "0x40C2 >= 1, 0x4089 >= 1" }

-- the Musical theater (Z077, M0154, frame 0x40B3 == 0, S006E -> S0158: the
-- dress-up, 0x16B, is a side facility not lowered) -> 0x4089 2; back in the
-- city the frame table (0x4089 == 2, M0124 S0915: Bianca's father) -> 3
B[#B + 1] = { name = "nimbasa: the musical and bianca's father",
  -- the person at the theater's door (person 11, S080D) leads the player in
  steps = { { "talk", 11 }, { "until", function(r) return r:var(0x4089) >= 2 end, 30000 }, settle,
            { "warpto", "Z062" }, { "until", function(r) return r:var(0x4089) >= 3 end, 30000 }, settle },
  expect = function(r) return r:var(0x40B3) >= 1 and r:var(0x4089) >= 3 end, why = "0x40B3 >= 1, 0x4089 >= 3" }

-- the amusement park: the grunts at its gate (Z062 coord 3 at (37,44),
-- 0x40D6 == 0, S0D01) -> 1; inside (Z064, M0128) the chase to the Ferris
-- wheel, N's battle (coord 1 at (22,12), 0x408E == 0, S0114) -> 1
B[#B + 1] = { name = "nimbasa: the ferris wheel",
  steps = { { "do", trainUp }, { "coord", 3 },
            { "until", function(r) return r:var(0x40D6) >= 1 end, 30000 }, settle,
            { "warpto", "Z064" }, { "coord", 1 },
            { "until", function(r) return r:var(0x408E) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x40D6) >= 1 and r:var(0x408E) >= 1 end, why = "0x40D6 >= 1, 0x408E >= 1" }

-- ELESA'S GYM (Z063, M0126): the roller coaster. Docks (overlay 39's table,
-- def.gen5Coaster) ride their track to the dock its switch joins; the floor
-- switches (coords on 0x400B..0x400E, 0x180 <n>) turn track n over. Entrance
-- island -> dock 0 (14,39) -> dock 1 (22,39), the middle; switch 0 (29,33);
-- dock 1 -> dock 2 (16,27), the west; switch 1 (13,16); dock 3 (16,15) ->
-- dock 4 (41,40), the east; switch 2 (46,41); dock 5 (49,40) -> dock 6
-- (34,8), Elesa's (person 5, S0100): the Bolt Badge, 0x4093 -> 1. A switch
-- turns its track over at every step onto it (its trigger's var is a temp
-- that nothing sets), so each is stepped on once, from the side away from
-- the route on.
-- the track a floor switch turned over (OverworldController's coaster:
-- save.bwCoaster[track] is 1 once the switch has run)
local function switched(t)
  return { "until", function(r) return ((r.game.save or {}).bwCoaster or {})[tostring(t)] == 1 end, 3000 }
end
B[#B + 1] = { name = "elesa: the bolt badge",
  steps = { { "do", trainUp }, { "warpto", "Z064" }, { "warpto", "Z063" },
            { "walkto", 14, 40 }, { "step", "up", 1 },
            { "walkto", 29, 34 }, { "walkto", 29, 33 }, switched(0), settle,
            { "walkto", 22, 40 }, { "step", "up", 1 },
            { "walkto", 13, 17 }, { "walkto", 13, 16 }, switched(1), settle,
            { "walkto", 16, 16 }, { "step", "up", 1 },
            { "walkto", 45, 41 }, { "step", "right", 1 }, switched(2), settle,
            { "walkto", 49, 41 }, { "step", "up", 1 },
            { "talk", 5 }, { "until", function(r) return r:var(0x4093) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x4093) >= 1 end, why = "0x4093 >= 1 (Bolt Badge)", budget = 120000 }

-- ROUTE 5 (Z329, M0658): Elesa and Cheren (coord 1 at (52,21), 0x4093 ==
-- 1, S0070: his battle) -> 2; the drawbridge raised (coord 3 at (19,15),
-- 0x4093 == 2, S0759) -> 3
B[#B + 1] = { name = "route 5: cheren and the drawbridge",
  steps = { { "do", trainUp }, { "teleport", "Z329", 55, 22, "left" }, { "coord", 1 },
            { "until", function(r) return r:var(0x4093) >= 2 end, 60000 }, settle,
            { "coord", 3 }, { "until", function(r) return r:var(0x4093) >= 3 end, 30000 }, settle },
  expect = function(r) return r:var(0x4093) >= 3 end, why = "0x4093 >= 3" }

-- DRIFTVEIL (Z096, M0192): over the drawbridge (Z253) by teleport; the
-- arrival, Clay and the Plasma trial (coord 2 at (44,46), 0x408F == 0,
-- S0057) -> 1
B[#B + 1] = { name = "driftveil: the arrival",
  steps = { { "teleport", "Z096", 47, 47, "left" }, { "coord", 2 },
            { "until", function(r) return r:var(0x408F) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x408F) >= 1 end, why = "0x408F >= 1" }

-- COLD STORAGE. Outside (Z191, M0382): the approach (coord 1 at (7,26),
-- 0x4090 == 0, S0040) -> 1; the first warehouse (Z192, M0384): its frame
-- table (0x408B == 0, S0061) -> 1, the grunts' maze to the hatch (coord 1
-- at (6,8), 0x408B == 1, S00B7) -> 2; the storehouse (Z193, M0386): its frame
-- table (0x408B == 2, S00C4) -> 3, then the four grunts in the crowd round
-- the Sages (persons 5, 7, 9 and 10; each battle adds 1), and at 7 the
-- Sages' scene (S06F6): 0x408B -> 8, 0x408F -> 2
-- the four grunts (persons 5, 7, 9, 10) are fought in whichever order they
-- can be reached: after each battle the crowd shuffles, and the runner talks
-- to one it can walk up to (a "talkany" whose list is the ones not yet fought)
local fought = {}
local function grunt(n)
  local st = { "talkany", {}, retarget = true }
  return { "do", function(r)
    local list = {}
    for _, id in ipairs({ 5, 7, 9, 10 }) do
      local n0 = nil
      for _, npc in ipairs(r.ow.npcs or {}) do if (npc.def and npc.def.localId) == id then n0 = npc end end
      if n0 and not fought[id] then
        for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
          if r.planStep(r.ow, n0.cellX + d[1], n0.cellY + d[2]) or (r:pos() == n0.cellX + d[1] and select(2, r:pos()) == n0.cellY + d[2]) then
            list[#list + 1] = id
            break
          end
        end
      end
    end
    st[2] = { list[1] or 5 }
    fought[list[1] or 5] = true
    r:say("  grunt %d of 4: person %s", n - 3, tostring(list[1]))
  end }, st
end
local g1, g2, g3, g4 = { grunt(4) }, { grunt(5) }, { grunt(6) }, { grunt(7) }
B[#B + 1] = { name = "cold storage",
  steps = { { "do", trainUp }, { "teleport", "Z191", 10, 27, "left" }, { "coord", 1 },
            { "until", function(r) return r:var(0x4090) >= 1 end, 30000 }, settle,
            { "warpto", "Z192" }, { "until", function(r) return r:var(0x408B) >= 1 end, 30000 }, settle,
            { "coord", 1 }, { "until", function(r) return r:var(0x408B) >= 2 end, 30000 }, settle,
            { "warpto", "Z193" }, { "until", function(r) return r:var(0x408B) >= 3 end, 30000 }, settle,
            -- (the scene can leave the player on Bianca's cell (3,11), from
            -- which the planner finds no way out: one step aside first)
            { "step", "right", 1 },
            g1[1], g1[2], { "until", function(r) return r:var(0x408B) >= 4 end, 30000 }, settle,
            g2[1], g2[2], { "until", function(r) return r:var(0x408B) >= 5 end, 30000 }, settle,
            g3[1], g3[2], { "until", function(r) return r:var(0x408B) >= 6 end, 30000 }, settle,
            g4[1], g4[2], { "until", function(r) return r:var(0x408F) >= 2 end, 60000 }, settle },
  expect = function(r) return r:var(0x408B) >= 8 and r:var(0x408F) >= 2 end, why = "0x408B >= 8, 0x408F >= 2 (the Sages)",
  budget = 160000 }

-- back in Driftveil: Clay's challenge (coord 1 at (46,20), 0x408F == 2,
-- S0281) -> 3
B[#B + 1] = { name = "driftveil: clay's challenge",
  steps = { { "teleport", "Z096", 49, 21, "left" }, { "coord", 1 },
            { "until", function(r) return r:var(0x408F) >= 3 end, 30000 }, settle },
  expect = function(r) return r:var(0x408F) >= 3 end, why = "0x408F >= 3" }

-- CLAY'S GYM. The lobby (Z098, M0196): the lift into the mine is the
-- sprite-0 object at (9,3) (S002D: faced from below) -> Z097 (17,25), level
-- 50. The mine (Z097, M0194; Gen5DriftveilGym): each lift's panels stand on
-- its own top row, "up" (checkflag, move, clearflag) and "down" (setflag);
-- lift 0 (18..22, 24..26) down 50 -> 40 from (22,24); lift 2 (8..12,
-- 24..26) down 40 -> 30 from (12,24); lift 4 (8..12, 20..22) up 30 -> 50
-- from (8,20); lift 5 (14..16, 20..22) down 50 -> -59 from (16,20), Clay's
-- floor; Clay (person 0, S0071): the Quake Badge, 0x408F -> 4
local function panel(x, y)
  return { "walkto", x, y + 1 }, { "face", "up" }, { "press", "a" }, settle
end
local clay = { { "do", trainUp }, { "teleport", "Z098", 7, 12, "up" }, { "walkto", 9, 4 }, { "face", "up" }, { "press", "a" },
               { "until", function(r) return r:map() == "Z097" end, 6000 }, settle }
for _, p in ipairs({ { 22, 24 }, { 12, 24 }, { 8, 20 }, { 16, 20 } }) do
  for _, s in ipairs({ panel(p[1], p[2]) }) do clay[#clay + 1] = s end
end
for _, s in ipairs({ { "talk", 0 }, { "until", function(r) return r:var(0x408F) >= 4 end, 60000 }, settle }) do clay[#clay + 1] = s end
B[#B + 1] = { name = "clay: the quake badge", steps = clay,
  expect = function(r) return r:var(0x408F) >= 4 end, why = "0x408F >= 4 (Quake Badge)", budget = 120000 }

-- Driftveil's west edge after the badge (coord 3 at (4,19), 0x408F == 4,
-- M0192 S04AD) -> 5
B[#B + 1] = { name = "driftveil: leaving for route 6",
  steps = { { "teleport", "Z096", 8, 21, "left" }, { "coord", 3 },
            { "until", function(r) return r:var(0x408F) >= 5 end, 30000 }, settle },
  expect = function(r) return r:var(0x408F) >= 5 end, why = "0x408F >= 5" }

-- CHARGESTONE CAVE. The mouth (Z194, M0388): the person at the way in
-- (person 0 at (11,19), S0074) -> 0x409A 2; inside (Z195, M0390) the five
-- triggers on 0x409B: (6,54) 0 -> 1, (15,41) -> 2, (33,24) -> 3, (38,41) -> 4,
-- (66,12) -> 5 (coords 4, 1, 2, 5, 3)
B[#B + 1] = { name = "chargestone cave",
  steps = { { "do", trainUp }, { "teleport", "Z194", 11, 23, "up" }, { "talk", 0 },
            { "until", function(r) return r:var(0x409A) >= 2 end, 30000 }, settle,
            { "warpto", "Z195" },
            { "coord", 4 }, { "until", function(r) return r:var(0x409B) >= 1 end, 40000 }, settle,
            { "coord", 1 }, { "until", function(r) return r:var(0x409B) >= 2 end, 40000 }, settle,
            { "coord", 2 }, { "until", function(r) return r:var(0x409B) >= 3 end, 40000 }, settle,
            { "coord", 5 }, { "until", function(r) return r:var(0x409B) >= 4 end, 40000 }, settle,
            { "coord", 3 }, { "until", function(r) return r:var(0x409B) >= 5 end, 40000 }, settle },
  expect = function(r) return r:var(0x409A) >= 2 and r:var(0x409B) >= 5 end, why = "0x409A >= 2, 0x409B >= 5",
  budget = 200000 }

-- MISTRALTON (Z107, M0214): out of the cave, Cedric Juniper's Pokedex check
-- (coord 1 at (36,46), 0x4099 == 0, S028D) -> 1
B[#B + 1] = { name = "mistralton: cedric juniper",
  steps = { { "warpto", "Z107" }, { "coord", 1 },
            { "until", function(r) return r:var(0x4099) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x4099) >= 1 end, why = "0x4099 >= 1" }

-- ROUTE 7 (Z337, M0674): the scene where it leaves Mistralton (coord 2 at
-- (40,19), 0x40E7 == 0, S0062) -> 1. CELESTIAL TOWER (Z338..Z342): up its
-- floors to the roof (Z342, M0684), Skyla (coord 1 at (15,17), 0x40BA == 0,
-- S0013) -> 1; the bell (sign 1 at (16,10), S00D1 .. S01F6) rung: 0x40BA ->
-- 2, and the person in Mistralton's gym door stands aside (flag 0x2AE)
B[#B + 1] = { name = "celestial tower: skyla at the bell",
  steps = { { "do", trainUp }, { "teleport", "Z337", 43, 20, "left" }, { "coord", 2 },
            { "until", function(r) return r:var(0x40E7) >= 1 end, 30000 }, settle,
            { "warpto", "Z338" }, { "warpto", "Z339" }, { "warpto", "Z340" }, { "warpto", "Z341" }, { "warpto", "Z342" },
            { "coord", 1 }, { "until", function(r) return r:var(0x40BA) >= 1 end, 30000 }, settle,
            { "sign", 1 }, { "until", function(r) return r:var(0x40BA) >= 2 end, 30000 }, settle },
  expect = function(r) return r:var(0x40E7) >= 1 and r:var(0x40BA) >= 2 and r:flag(0x2AE) end,
  why = "0x40E7 >= 1, 0x40BA >= 2, flag 0x2AE", budget = 160000 }

-- SKYLA'S GYM (Z108, M0216): the cannons (overlay 41, def.gen5Cannons) fire
-- the way the player presses into the wall within a tile of one. The route:
-- (15,30) up -> (15,19); (12,19) left -> (3,19); (8,19) right -> (21,19);
-- (22,29) left -> (10,29); (10,27) up -> (10,13); (13,13) right -> (25,13);
-- (17,13) left -> (5,13); (5,6) down -> (5,34); (5,36) right -> (26,36);
-- (26,36) up -> (26,4); (26,6) left -> (15,6); Skyla (person 1, S01C4): the
-- Jet Badge, 0x4099 -> 2; Mistralton's frame table (0x4099 == 2, S003B) -> 3
local skyla = { { "do", trainUp }, { "teleport", "Z107", 14, 15, "up" }, { "warpto", "Z108" } }
for _, c in ipairs({ { 15, 30, "up" }, { 12, 19, "left" }, { 8, 19, "right" }, { 22, 29, "left" },
                     { 10, 27, "up" }, { 13, 13, "right" }, { 17, 13, "left" }, { 5, 6, "down" },
                     { 5, 36, "right" }, { 26, 36, "up" }, { 26, 6, "left" } }) do
  skyla[#skyla + 1] = { "walkto", c[1], c[2] }
  skyla[#skyla + 1] = { "step", c[3], 1 }
  skyla[#skyla + 1] = settle
end
-- ...and back down by the cannon behind her: (15,1) down -> (15,32)
for _, s in ipairs({ { "talk", 1 }, { "until", function(r) return r:var(0x4099) >= 2 end, 60000 }, settle,
                     { "walkto", 15, 1 }, { "step", "down", 1 }, settle,
                     { "warpto", "Z107" }, { "until", function(r) return r:var(0x4099) >= 3 end, 30000 }, settle }) do
  skyla[#skyla + 1] = s
end
B[#B + 1] = { name = "skyla: the jet badge", steps = skyla,
  expect = function(r) return r:var(0x4099) >= 3 end, why = "0x4099 >= 3 (Jet Badge)", budget = 160000 }

-- TWIST MOUNTAIN. The entrance (Z198, M0396): the scene at the mouth (coord
-- 1 at (16,14), 0x40B4 == 1, S0042) -> 2; inside (Z200, M0400) the trigger
-- by the entry (coord 1 at (3,52), 0x4096 == 0, S0007) -> 1; then across the
-- mountain's four maps by the warps a breadth-first plan over them names
-- (scratch_claude/plan.py: Z200 -> Z199 -> Z200 -> Z199 -> Z200 -> Z201 ->
-- Z199 -> Z201 -> Z199 -> Z201 -> Z202 -> Z199 -> Z202), to the exit scene
-- (Z202, M0404, coord 1 at (52,13), 0x40BB == 0, S0040): 0x40BB 1, 0x4097 1
local twist = { { "do", trainUp }, { "teleport", "Z198", 18, 15, "left" }, { "coord", 1 },
  { "until", function(r) return r:var(0x40B4) >= 2 end, 30000 }, settle,
  { "warpto", "Z200" }, { "coord", 1 }, { "until", function(r) return r:var(0x4096) >= 1 end, 30000 }, settle }
for _, w in ipairs({ { "Z199", 17, 48 }, { "Z200", 33, 54 }, { "Z199", 53, 36 }, { "Z200", 49, 18 },
                     { "Z201", 48, 18 }, { "Z199", 46, 53 }, { "Z201", 17, 42 }, { "Z199", 26, 42 },
                     { "Z201", 22, 15 }, { "Z202", 7, 5 }, { "Z199", 7, 26 }, { "Z202", 40, 22 } }) do
  twist[#twist + 1] = { "warpto", w[1], w[2], w[3] }
  twist[#twist + 1] = { "do", heal }
end
for _, s in ipairs({ { "coord", 1 }, { "until", function(r) return r:var(0x40BB) >= 1 end, 30000 }, settle }) do
  twist[#twist + 1] = s
end
B[#B + 1] = { name = "twist mountain", steps = twist,
  expect = function(r) return r:var(0x40B4) >= 2 and r:var(0x4096) >= 1 and r:var(0x40BB) >= 1 and r:var(0x4097) >= 1 end,
  why = "0x40B4 >= 2, 0x4096 >= 1, 0x40BB >= 1, 0x4097 >= 1", budget = 200000 }

-- ICIRRUS (Z113, M0226): Cedric Juniper reads the party (frame 0x4097 == 1,
-- S003F) -> 2. BRYCEN'S GYM (Z114, M0228; overlay 45's gated rail rides):
-- the entrance ride (coord 4 at (17,60), 0x195 0); the switch at (15,29)
-- (coord 3, S03A9: the block arms turn); the ride at (18,29) (coord 11,
-- 0x195 6) up to Brycen (person 11, S003B): the Freeze Badge, 0x4097 -> 3,
-- 0x40A7 -> 1; outside the frame table (0x4097 == 3, M0226 S0175) -> 4
B[#B + 1] = { name = "icirrus: brycen",
  -- Flamethrower (53): the gym's Ice types resist Ice Beam, and a run of them
  -- wore a level-60 lead out
  steps = { { "do", trainUpWith(53, 75) }, { "warpto", "Z113" }, { "until", function(r) return r:var(0x4097) >= 2 end, 30000 }, settle,
            { "warpto", "Z114" }, { "walkto", 17, 61 }, { "step", "up", 1 }, settle,
            { "coord", 3 }, settle, { "do", heal }, { "walkto", 17, 29 }, { "step", "right", 1 }, settle, { "do", heal },
            { "talk", 11 }, { "until", function(r) return r:var(0x4097) >= 3 end, 60000 }, settle,
            { "warpto", "Z113" }, { "until", function(r) return r:var(0x4097) >= 4 end, 30000 }, settle },
  expect = function(r) return r:var(0x4097) >= 4 and r:var(0x40A7) >= 1 end, why = "0x4097 >= 4, 0x40A7 >= 1 (Freeze Badge)",
  budget = 160000 }

-- DRAGONSPIRAL TOWER. The approach (Z205, M0410): Cheren and the Plasma
-- (coord 1 at (17,18), 0x40A7 == 1, S0369 -> S0454) -> 0x40A7 2, 0x4097 5
B[#B + 1] = { name = "dragonspiral: the approach",
  steps = { { "do", trainUp }, { "teleport", "Z205", 20, 21, "up" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40A7) >= 2 end, 60000 }, settle },
  expect = function(r) return r:var(0x40A7) >= 2 and r:var(0x4097) >= 5 end, why = "0x40A7 >= 2, 0x4097 >= 5" }

-- A CHEAT, said as one: Surf (57) in the lead's second slot (BW gives no
-- HM Surf on the story path before here; the bag's TEACH is not under test).
-- The lake at the tower's foot (Z206 rows 36..43): surf from (21,44); the
-- door (Z207, kind 2) is one solid cell past the far bank, taken by pressing
-- into the wall from the water. Up the floors: Z207 (coord 1 at (24,2),
-- 0x40A7 == 2) -> 3; Z208 (coord 1 at (14,24)) -> 4; Z209 (the spiral
-- rails) to Z210 (coord 2 at (22,14)) -> 5, (coord 1 at (21,14)) -> 6; Z211
-- to Z212 (coord 1 at (14,25)) -> 7, (coord 2 at (13,10)) -> 8; the summit
-- (Z213, M0426, coord 1 at (16,21), 0x40A7 == 8): N and the dragon -> 9
local function teachSurf(r)
  local lead = r:party()[1]
  if not lead then return end
  for _, mv in ipairs(lead.moves or {}) do if mv.id == 57 then return end end
  table.insert(lead.moves, 2, { id = 57, pp = 30 })
  while #lead.moves > 4 do table.remove(lead.moves) end
end
local function onFloor(map, n, v)
  return { { "warpto", map }, { "do", heal }, { "coord", n },
           { "until", function(r) return r:var(0x40A7) >= v end, 60000 }, settle }
end
local tower = { { "do", trainUp }, { "do", teachSurf },
  { "warpto", "Z206" }, { "walkto", 21, 44 }, { "face", "up" }, { "press", "a" },
  { "until", function(r) return r.ow.player and r.ow.player.surfing end, 6000 },
  { "walkto", 21, 36 }, { "step", "up", 1 },
  { "coord", 1 }, { "until", function(r) return r:var(0x40A7) >= 3 end, 60000 }, settle }
for _, part in ipairs({ onFloor("Z208", 1, 4), { { "warpto", "Z209" } }, onFloor("Z210", 2, 5),
                        { { "coord", 1 }, { "until", function(r) return r:var(0x40A7) >= 6 end, 60000 }, settle },
                        { { "warpto", "Z211" } }, onFloor("Z212", 1, 7),
                        { { "coord", 2 }, { "until", function(r) return r:var(0x40A7) >= 8 end, 60000 }, settle },
                        onFloor("Z213", 1, 9) }) do
  for _, st in ipairs(part) do tower[#tower + 1] = st end
end
B[#B + 1] = { name = "dragonspiral: the summit", steps = tower,
  expect = function(r) return r:var(0x40A7) >= 9 end, why = "0x40A7 >= 9 (N and the dragon)", budget = 240000 }

-- after the summit, the queued scene at the tower's foot (Z205 entry 4,
-- S007D): Alder and Cedric Juniper -> 0x409D 1
B[#B + 1] = { name = "dragonspiral: alder at the foot",
  steps = { { "until", function(r) return r:var(0x409D) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x409D) >= 1 end, why = "0x409D >= 1" }

-- DESERT RESORT (Z158, M0316): the meeting at the castle's door (coord 1 at
-- (61,30), 0x409D == 1, S011F) -> 2. RELIC CASTLE, walked: its floors are
-- quicksand pits (behaviour 0x7C) whose 5 x 5 triggers drop the player a
-- floor through 0x0C1 -- a walker crosses the sand, one who stands on it or
-- reaches the centre sinks (src/world/Gen5Quicksand.lua). The bottom pit
-- (Z164 coord 1, M0328 S0007) queues Z165's entry 1, whose scene queues
-- Z158's entry 5: back in the desert, 0x4092 -> 6
local relic = { { "do", trainUp }, { "teleport", "Z158", 61, 33, "up" }, { "coord", 1 },
  { "until", function(r) return r:var(0x409D) >= 2 end, 30000 }, settle,
  -- down on foot (the castle's way down is its pits and the stairs behind
  -- them; the sandfalls 0x72 / 0x75 beside each stair are one-way ledges):
  -- in at the door (Z158 warp 2 -> Z160); across the west pit's edge (Z160
  -- (9,15) .. (8,16), off its centre (7,14)) to the stairs down at (7,20) ->
  -- B1F's south room (Z161); its pit (coord 1) -> B2F (Z162) (22,17); along
  -- the east pit's south row (y 15) to the south pit (coord 2) -> B3F (Z163)
  -- (21,19); west along y 21 over pit 3 into pit 1 and stand -> B4F (Z164)
  -- (15,21), the side of the sandfall (x 18) its own pit is on
  { "warpto", "Z160" }, { "do", heal },
  -- (one walk over the sand: a turn from a standstill there costs the turn
  -- window, and that is standing still; (9,17) is a person's)
  { "walkto", 13, 18 }, { "walkto", 8, 17 }, { "warpto", "Z161" },
  { "coord", 1 }, { "until", function(r) return r:map() == "Z162" end, 20000 }, settle,
  { "walkto", 19, 15 }, { "walkto", 13, 15 }, { "coord", 2 },
  { "until", function(r) return r:map() == "Z163" end, 20000 }, settle,
  { "do", heal }, { "walkto", 16, 21 }, { "walkto", 10, 21 },
  { "until", function(r) return r:map() == "Z164" end, 20000 }, settle,
  { "do", heal }, { "coord", 1 },
  { "until", function(r) return r:map() == "Z165" or r:var(0x4092) >= 6 end, 30000 },
  { "until", function(r) return r:var(0x4092) >= 6 end, 60000 }, settle }
B[#B + 1] = { name = "relic castle", steps = relic,
  expect = function(r) return r:var(0x409D) >= 2 and r:var(0x4092) >= 6 end, why = "0x409D >= 2, 0x4092 >= 6",
  budget = 160000 }

-- NACRENE again (Z016, M0032): Lenora with the stone at the museum (coord 3
-- at (32,10), 0x4092 == 6, S0839) -> 7
B[#B + 1] = { name = "nacrene: the stone",
  steps = { { "teleport", "Z016", 36, 13, "up" }, { "coord", 3 },
            { "until", function(r) return r:var(0x4092) >= 7 end, 30000 }, settle },
  expect = function(r) return r:var(0x4092) >= 7 end, why = "0x4092 >= 7" }

-- OPELUCID (Z120, M0240), reached by teleport past Route 8, the Moor and
-- Tubeline Bridge: the arrival (coord 1 at (11,45), 0x40A8 == 0, S0161) -> 1;
-- (coord 2 at (31,39), S0DC1) -> 2; (coord 3 at (31,34), S0DF5) -> 3
B[#B + 1] = { name = "opelucid: the arrival",
  steps = { { "do", trainUp }, { "teleport", "Z120", 3, 46, "right" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40A8) >= 1 end, 30000 }, settle,
            { "coord", 2 }, { "until", function(r) return r:var(0x40A8) >= 2 end, 30000 }, settle,
            { "coord", 3 }, { "until", function(r) return r:var(0x40A8) >= 3 end, 30000 }, settle },
  expect = function(r) return r:var(0x40A8) >= 3 end, why = "0x40A8 >= 3" }

-- Drayden's house (Z123, M0246, frame 0x40A8 == 3, S000F): Drayden and
-- Alder -> 4, and the person in the gym's door goes (flag 0x26C)
B[#B + 1] = { name = "opelucid: drayden's house",
  steps = { { "warpto", "Z123" }, { "until", function(r) return r:var(0x40A8) >= 4 end, 30000 }, settle },
  expect = function(r) return r:var(0x40A8) >= 4 and r:flag(0x26C) end, why = "0x40A8 >= 4, flag 0x26C" }

-- DRAYDEN'S GYM (Z121, M0242; Gen5DragonGym), climbed: a floor, a deck six
-- tiles up and the dragons' rails between them (Gen5DragonGym.surfaces).
-- The dragons' switches are coords on a temp var (0x19A <statue, side>,
-- 0x199 settles the head; both down opens the neck), so each is stepped on
-- once. The second dragon's, on the floor's row 22 (coord 3 at (36,22),
-- coord 4 at (48,22)), open its neck from its head (42,12) up to the deck;
-- along the deck to its row 27 and the third dragon's (coord 5 at (33,27),
-- coord 6 at (21,27)), which open its neck up to Drayden's platform; on the
-- way, down its body to the trainer at (32,34) (coord 7, 0x40A9 == 0, S039E)
-- -> 1. (The first dragon's neck, from row 29's switches, reaches the deck
-- too, but by the spiral the rail trainer, person 9, stands on.) Drayden
-- (person 4 at (27,2), S0072): the Legend Badge, 0x40B8 -> 1
B[#B + 1] = { name = "drayden: the legend badge",
  steps = { { "do", trainUpWith(58, 100, 150) }, { "warpto", "Z120" }, { "warpto", "Z121" },
            { "coord", 3 }, settle, { "coord", 4 }, settle,
            { "coord", 5 }, settle, { "coord", 6 }, settle,
            { "coord", 7 }, { "until", function(r) return r:var(0x40A9) >= 1 end, 60000 }, settle,
            { "walkto", 27, 3 }, { "face", "up" }, { "press", "a" },
            { "until", function(r) return r:var(0x40B8) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x40B8) >= 1 end, why = "0x40B8 >= 1 (Legend Badge)", budget = 200000 }

-- OPELUCID after the badge: the frame table (Z120, 0x40B8 == 1, M0240
-- S0E7D: the Plasma) -> 2; the gate to Route 10 (Z132, M0264, coord 1 at
-- (2,11), 0x40B8 == 2, S008D) -> 3; Route 10 (Z355, M0710): the battle on the
-- way (coord 1 at (61,21), 0x40B8 == 3, S0013) -> 4
B[#B + 1] = { name = "opelucid to route 10",
  -- (Route 10's battle is two full teams in the forties: a level-100
  -- Mewtwo, as for the League)
  steps = { { "do", trainUpWith(58, 100, 150) }, { "warpto", "Z120" }, { "until", function(r) return r:var(0x40B8) >= 2 end, 60000 }, settle,
            { "teleport", "Z132", 5, 13, "up" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40B8) >= 3 end, 30000 }, settle,
            { "warpto", "Z355" }, { "do", heal }, { "coord", 1 },
            { "until", function(r) return r:var(0x40B8) >= 4 end, 60000 }, settle },
  expect = function(r) return r:var(0x40B8) >= 4 and r:map() ~= "Z390" end, why = "0x40B8 >= 4, not blacked out" }

-- THE BADGE CHECK GATES (Z356 .. Z363, one trigger each that lets a holder of
-- the badges through): Route 10's door (82,11) and through all eight; then
-- VICTORY ROAD (Z214, M0428): the scene at its foot (coord 2 at (34,44),
-- 0x40CF == 0, S0069) -> 1
local gates = { { "do", heal }, { "warpto", "Z356" } }
for z = 357, 364 do gates[#gates + 1] = { "warpto", ("Z%03d"):format(z) } end
for _, st in ipairs({ { "teleport", "Z214", 37, 44, "left" }, { "coord", 2 },
                      { "until", function(r) return r:var(0x40CF) >= 1 end, 30000 }, settle }) do
  gates[#gates + 1] = st
end
B[#B + 1] = { name = "the badge gates and victory road", steps = gates,
  expect = function(r) return r:var(0x40CF) >= 1 end, why = "0x40CF >= 1", budget = 120000 }

-- THE POKEMON LEAGUE (Z136, M0272): the arrival (coord 1 at (31,48),
-- 0x40A1 == 0, S0188) -> 1, reached by teleport past Victory Road's caves
B[#B + 1] = { name = "the pokemon league",
  steps = { { "teleport", "Z136", 32, 51, "up" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40A1) >= 1 end, 30000 }, settle },
  expect = function(r) return r:var(0x40A1) >= 1 end, why = "0x40A1 >= 1" }

-- THE ELITE FOUR (Z140..Z143 round Z137): in each room the platform at
-- (15,25) lifts the player to the member (coord 1, 0x1A2 <n>); the member
-- (person 0) battles and sets their flag (Shauntal 0x969, Grimsley 0x96A,
-- Caitlin 0x96B, Marshal 0x96C); the platform's other trigger takes the
-- player down, and out
local E4 = { { "Z140", 0x969, 58 }, { "Z141", 0x96A, 58 }, { "Z142", 0x96B, 58 }, { "Z143", 0x96C, 58 } }
for _, e in ipairs(E4) do
  local room, flag = e[1], e[2]
  B[#B + 1] = { name = "elite four " .. room,
    -- (as heartgold.lua's Lance: one Pokemon, one move, against full teams
    -- with items -- the cheat's lead is a level-100 Mewtwo)
    steps = { { "do", trainUpWith(e[3], 100, 150) }, { "teleport", "Z137", 31, 46, "up" }, { "warpto", room },
              { "walkto", 15, 26 }, { "step", "up", 1 }, settle, { "talk", 0 },
              { "until", function(r) return r:flag(flag) end, 60000 }, settle },
    expect = function(r) return r:flag(flag) end, why = ("flag 0x%X"):format(flag) }
end

-- the statue (Z137 sign 1 at (31,44), M0274 S007A: all four flags) -> 0x1BB:
-- the stair to the Champion (Z138); the Champion's room (Z144, M0288): N has
-- beaten Alder (coord 1 at (15,12), 0x40A2 == 0, S0050 -> S00C7) -> 1
B[#B + 1] = { name = "the champion's room",
  steps = { { "teleport", "Z137", 31, 46, "up" }, { "sign", 1 },
            { "until", function(r) return r:map() == "Z138" end, 20000 }, settle,
            { "warpto", "Z144" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40A2) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x40A2) >= 1 end, why = "0x40A2 >= 1" }

-- INTO N'S CASTLE: the Champion's room's way on (Z144's kind-2 warp at
-- (14,0), in the corner above a corridor that runs 15..17: taken by pressing
-- up from (15,1)) to Z139, whose own door (30,11) is the castle (Z264, M0528):
-- the Sages (frame 0x40A5 == 0, S0100) -> 1
B[#B + 1] = { name = "n's castle: the sages",
  steps = { { "do", trainUpWith(58, 100, 150) }, { "walkto", 15, 1 }, { "step", "up", 1 },
            { "until", function(r) return r:map() == "Z139" end, 6000 }, settle,
            { "warpto", "Z264" }, { "until", function(r) return r:var(0x40A5) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x40A5) >= 1 end, why = "0x40A5 >= 1" }

-- up the castle: Z265 (M0530: the gym leaders hold the Sages, coord 1 at
-- (16,13), 0x40A6 == 0) -> 1; Z269 (M0538, coord 1 at (3,13), 0x40D4 == 0);
-- Z273 (M0546, frame 0x40D5 == 0); Z277 (M0554, coord 1 at (23,9), 0x40DC
-- == 0: the last Sage) -> 1
B[#B + 1] = { name = "n's castle: the floors",
  steps = { { "do", heal }, { "warpto", "Z265" }, { "coord", 1 },
            { "until", function(r) return r:var(0x40A6) >= 1 end, 60000 }, settle,
            { "warpto", "Z269" }, { "do", heal }, { "coord", 1 },
            { "until", function(r) return r:var(0x40D4) >= 1 end, 60000 }, settle,
            { "warpto", "Z273" }, { "do", heal }, { "until", function(r) return r:var(0x40D5) >= 1 end, 60000 }, settle,
            { "warpto", "Z277" }, { "do", heal }, { "coord", 1 },
            { "until", function(r) return r:var(0x40DC) >= 1 end, 60000 }, settle },
  expect = function(r) return r:var(0x40A6) >= 1 and r:var(0x40DC) >= 1 end, why = "0x40A6 >= 1, 0x40DC >= 1",
  budget = 200000 }

-- THE THRONE ROOM (Z278, M0556): N (coord 1 at (14,47), 0x40B6 0 -> 1;
-- coord 2 at (14,42) -> 2), the dragon (person 4, S0AB2: a scripted wild
-- battle, 0x178) -> 3, then on without a step from the player: N's battle
-- -> 5 (0x40A2 -> 2), Ghetsis (coord 4 at (14,42), 0x40B6 == 5, where the
-- scene leaves the player) -> 6 and the game clear (0x156: home, Z391). A CHEAT, said as
-- one: the runner cannot throw a ball, so the dragon's battle answers
-- "caught" (as the harness's AUTO_BATTLE_WILD does); 0x245 then adds the
-- dragon itself, as the script says.
local function catchNextWild(r)
  local Commands = require("src.script.Commands")
  local real = Commands.start_battle
  Commands.start_battle = function(ctx, kind, ...)
    if kind ~= "wild" then return real(ctx, kind, ...) end
    Commands.start_battle = real
    ctx.lastBattleResult = "caught"
    r:say("  (the dragon's battle answered caught)")
  end
end
local function famed(r)
  return r:var(0x40B6) >= 6 and (r.game.save or {}).gen5GameClear == true
end
B[#B + 1] = { name = "n's castle: the throne room",
  steps = { { "do", trainUpWith(58, 100, 150) }, { "warpto", "Z278" },
            { "coord", 1 }, { "until", function(r) return r:var(0x40B6) >= 1 end, 60000 }, settle,
            { "coord", 2 }, { "until", function(r) return r:var(0x40B6) >= 2 end, 60000 }, settle,
            { "do", catchNextWild }, { "talk", 4 },
            { "until", function(r) return r:var(0x40B6) >= 3 end, 60000 },
            { "until", famed, 200000 } },
  expect = famed, why = "0x40B6 >= 6 and the game clear (0x156)", budget = 400000, passBusy = true }

-- BW's scenes talk on long after the var they set: every beat may wait out
-- its dialogue (the expect is checked once the field is idle)
for _, b in ipairs(B) do b.expectBudget = math.max(b.expectBudget or 0, 12000) end
-- ...and a beat lost to a black-out is not passed, whatever var its script
-- set before the battle (from Accumula on, home is never where a beat ends)
for i = 10, #B - 1 do
  local b, expect = B[i], B[i].expect
  b.expect = function(r) return expect(r) and r:map() ~= "Z390" end
end

return B
