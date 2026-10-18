-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE WATT SHOP'S SHELVES: what the Monster Walker sells, as data. No drawing
-- (src/ui/WalkerEconomyPages.lua) and no spending (src/pokewalker/WalkerEconomy.lua).
--
--   ITEMS      per generation: only an item the target game has is offered,
--              by the name its own items.lua uses (WalkerInbox matches names
--              with case, spaces and punctuation ignored, and "é" read as E)
--   POKEMON    a rotating stock of six, drawn each day for the target game
--              from its own Pokedex range, never a legendary (catch rate 3 or
--              below -- the same rule the courses use)
--   GIFTS      the week's Mystery Gifts: four specials, each claimable once
--              a week, into the target game's PC or bag
--   COSMETICS  the walker's own look and sound, and the event courses
--
-- Prices are this port's own (the original Pokewalker had no shop).

local S = {}

-- { name, count, price, gen (first generation that has it), cat }
S.ITEMS = {
  -- medicine
  { name = "Potion",        count = 5, price = 40,  gen = 1, cat = "Medicine" },
  { name = "Super Potion",  count = 3, price = 60,  gen = 1, cat = "Medicine" },
  { name = "Hyper Potion",  count = 3, price = 120, gen = 1, cat = "Medicine" },
  { name = "Max Potion",    count = 1, price = 90,  gen = 1, cat = "Medicine" },
  { name = "Full Restore",  count = 1, price = 120, gen = 1, cat = "Medicine" },
  { name = "Full Heal",     count = 3, price = 60,  gen = 1, cat = "Medicine" },
  { name = "Revive",        count = 2, price = 100, gen = 1, cat = "Medicine" },
  { name = "Max Revive",    count = 1, price = 150, gen = 1, cat = "Medicine" },
  { name = "Ether",         count = 2, price = 80,  gen = 1, cat = "Medicine" },
  -- balls
  { name = "Poke Ball",     count = 10, price = 40, gen = 1, cat = "Balls" },
  { name = "Great Ball",    count = 5, price = 60,  gen = 1, cat = "Balls" },
  { name = "Ultra Ball",    count = 5, price = 110, gen = 1, cat = "Balls" },
  { name = "Timer Ball",    count = 3, price = 70,  gen = 3, cat = "Balls" },
  { name = "Net Ball",      count = 3, price = 60,  gen = 3, cat = "Balls" },
  { name = "Luxury Ball",   count = 3, price = 60,  gen = 3, cat = "Balls" },
  { name = "Quick Ball",    count = 3, price = 90,  gen = 4, cat = "Balls" },
  { name = "Dusk Ball",     count = 3, price = 70,  gen = 4, cat = "Balls" },
  { name = "Heal Ball",     count = 3, price = 40,  gen = 4, cat = "Balls" },
  -- evolution
  { name = "Fire Stone",    count = 1, price = 150, gen = 1, cat = "Evolution" },
  { name = "Water Stone",   count = 1, price = 150, gen = 1, cat = "Evolution" },
  { name = "Thunder Stone", count = 1, price = 150, gen = 1, cat = "Evolution" },
  { name = "Leaf Stone",    count = 1, price = 150, gen = 1, cat = "Evolution" },
  { name = "Moon Stone",    count = 1, price = 150, gen = 1, cat = "Evolution" },
  { name = "Sun Stone",     count = 1, price = 150, gen = 2, cat = "Evolution" },
  { name = "Shiny Stone",   count = 1, price = 200, gen = 4, cat = "Evolution" },
  { name = "Dusk Stone",    count = 1, price = 200, gen = 4, cat = "Evolution" },
  { name = "Dawn Stone",    count = 1, price = 200, gen = 4, cat = "Evolution" },
  { name = "Oval Stone",    count = 1, price = 120, gen = 4, cat = "Evolution" },
  { name = "King's Rock",   count = 1, price = 250, gen = 2, cat = "Evolution" },
  { name = "Metal Coat",    count = 1, price = 250, gen = 2, cat = "Evolution" },
  { name = "Dragon Scale",  count = 1, price = 250, gen = 2, cat = "Evolution" },
  { name = "Up-Grade",      count = 1, price = 250, gen = 2, cat = "Evolution" },
  { name = "Deep Sea Tooth", count = 1, price = 250, gen = 3, cat = "Evolution" },
  { name = "Deep Sea Scale", count = 1, price = 250, gen = 3, cat = "Evolution" },
  { name = "Electirizer",   count = 1, price = 300, gen = 4, cat = "Evolution" },
  { name = "Magmarizer",    count = 1, price = 300, gen = 4, cat = "Evolution" },
  { name = "Protector",     count = 1, price = 300, gen = 4, cat = "Evolution" },
  { name = "Reaper Cloth",  count = 1, price = 300, gen = 4, cat = "Evolution" },
  { name = "Dubious Disc",  count = 1, price = 300, gen = 4, cat = "Evolution" },
  { name = "Razor Claw",    count = 1, price = 300, gen = 4, cat = "Evolution" },
  { name = "Razor Fang",    count = 1, price = 300, gen = 4, cat = "Evolution" },
  { name = "Prism Scale",   count = 1, price = 300, gen = 5, cat = "Evolution" },
  -- held items
  { name = "Leftovers",     count = 1, price = 400, gen = 2, cat = "Held items" },
  { name = "Lucky Egg",     count = 1, price = 400, gen = 2, cat = "Held items" },
  { name = "Amulet Coin",   count = 1, price = 300, gen = 2, cat = "Held items" },
  { name = "Exp. Share",    count = 1, price = 400, gen = 2, cat = "Held items" },
  { name = "Quick Claw",    count = 1, price = 200, gen = 2, cat = "Held items" },
  { name = "Scope Lens",    count = 1, price = 250, gen = 2, cat = "Held items" },
  { name = "Focus Band",    count = 1, price = 250, gen = 2, cat = "Held items" },
  { name = "Soothe Bell",   count = 1, price = 250, gen = 3, cat = "Held items" },
  { name = "Choice Band",   count = 1, price = 400, gen = 3, cat = "Held items" },
  { name = "Life Orb",      count = 1, price = 400, gen = 4, cat = "Held items" },
  -- training and the rest
  { name = "Rare Candy",    count = 1, price = 200, gen = 1, cat = "Training" },
  { name = "PP Up",         count = 1, price = 200, gen = 1, cat = "Training" },
  { name = "HP Up",         count = 1, price = 250, gen = 1, cat = "Training" },
  { name = "Protein",       count = 1, price = 250, gen = 1, cat = "Training" },
  { name = "Iron",          count = 1, price = 250, gen = 1, cat = "Training" },
  { name = "Calcium",       count = 1, price = 250, gen = 1, cat = "Training" },
  { name = "Carbos",        count = 1, price = 250, gen = 1, cat = "Training" },
  { name = "Heart Scale",   count = 1, price = 80,  gen = 3, cat = "Training" },
  { name = "Escape Rope",   count = 3, price = 30,  gen = 1, cat = "Other" },
  { name = "Max Repel",     count = 3, price = 60,  gen = 1, cat = "Other" },
  { name = "Nugget",        count = 1, price = 150, gen = 1, cat = "Other" },
}
S.CATEGORIES = { "Medicine", "Balls", "Evolution", "Held items", "Training", "Other" }

-- the week's specials: each { id, kind = "item" | "mon", ... , gen, price }
S.GIFTS = {
  { id = "masterball", kind = "item", name = "Master Ball", count = 1, gen = 1, price = 400 },
  { id = "candy5",     kind = "item", name = "Rare Candy", count = 5, gen = 1, price = 600 },
  { id = "ppmax",      kind = "item", name = "PP Max", count = 2, gen = 3, price = 400 },
  { id = "luckyegg",   kind = "item", name = "Lucky Egg", count = 1, gen = 2, price = 300 },
  { id = "nugget3",    kind = "item", name = "Nugget", count = 3, gen = 1, price = 250 },
  { id = "maxrevive3", kind = "item", name = "Max Revive", count = 3, gen = 1, price = 300 },
  { id = "bignugget",  kind = "item", name = "Big Nugget", count = 1, gen = 5, price = 300 },
  { id = "mew",        kind = "mon", dex = 151, level = 5,  gen = 1, price = 800 },
  { id = "celebi",     kind = "mon", dex = 251, level = 5,  gen = 2, price = 800 },
  { id = "jirachi",    kind = "mon", dex = 385, level = 5,  gen = 3, price = 900 },
  { id = "shaymin",    kind = "mon", dex = 492, level = 10, gen = 4, price = 900 },
  { id = "victini",    kind = "mon", dex = 494, level = 15, gen = 5, price = 900 },
  { id = "dratini",    kind = "mon", dex = 147, level = 10, gen = 1, price = 300 },
  { id = "eevee",      kind = "mon", dex = 133, level = 10, gen = 1, price = 250 },
  { id = "lapras",     kind = "mon", dex = 131, level = 20, gen = 1, price = 350 },
  { id = "togepi",     kind = "mon", dex = 175, level = 5,  gen = 2, price = 250 },
  { id = "larvitar",   kind = "mon", dex = 246, level = 10, gen = 2, price = 350 },
  { id = "beldum",     kind = "mon", dex = 374, level = 10, gen = 3, price = 400 },
  { id = "riolu",      kind = "mon", dex = 447, level = 10, gen = 4, price = 400 },
  { id = "zorua",      kind = "mon", dex = 570, level = 10, gen = 5, price = 400 },
}
S.GIFTS_PER_WEEK = 4

-- the walker's look: { kind, id, name, price, ... }; price 0 = always owned
S.COSMETICS = {
  theme = {
    { id = "auto",    name = "Course scene", price = 0 },
    { id = "field",   name = "Meadow",   scene = "Field",   price = 80 },
    { id = "forest",  name = "Forest",   scene = "Forest",  price = 80 },
    { id = "beach",   name = "Beach",    scene = "Beach",   price = 80 },
    { id = "lake",    name = "Lakeside", scene = "Lake",    price = 80 },
    { id = "cave",    name = "Cave",     scene = "Cave",    price = 100 },
    { id = "volcano", name = "Volcano",  scene = "Volcano", price = 100 },
    { id = "snow",    name = "Snowfield", scene = "Icy",    price = 100 },
    { id = "night",   name = "Starry night", scene = "Night", price = 120 },
    { id = "town",    name = "Town",     scene = "Town",    price = 80 },
  },
  shell = {
    { id = "classic", name = "Classic green", color = { 0.20, 0.48, 0.38 }, price = 0 },
    { id = "red",     name = "Cherry red",    color = { 0.62, 0.18, 0.22 }, price = 60 },
    { id = "blue",    name = "Ocean blue",    color = { 0.18, 0.36, 0.66 }, price = 60 },
    { id = "gold",    name = "Gold",          color = { 0.66, 0.50, 0.14 }, price = 90 },
    { id = "pink",    name = "Petal pink",    color = { 0.70, 0.32, 0.52 }, price = 60 },
    { id = "purple",  name = "Ghost purple",  color = { 0.40, 0.26, 0.60 }, price = 60 },
    { id = "silver",  name = "Silver",        color = { 0.42, 0.46, 0.52 }, price = 90 },
  },
  sound = {
    { id = "classic", name = "Classic beep", wave = "square", notes = { 1320 }, price = 0 },
    { id = "soft",    name = "Soft chime",   wave = "sine",   notes = { 880, 1320 }, price = 50 },
    { id = "retro",   name = "8-bit chirp",  wave = "square", notes = { 660, 990, 1320 }, price = 50 },
    { id = "bubble",  name = "Bubbles",      wave = "sine",   notes = { 520, 780 }, price = 50 },
  },
}
S.COSMETIC_KINDS = { { id = "theme", label = "Backgrounds" }, { id = "shell", label = "Shell colours" },
                     { id = "sound", label = "Sound sets" }, { id = "course", label = "Event courses" } }
S.COURSE_PRICE = 500         -- an event course, +100 for each further one

local function norm(s)
  s = tostring(s or ""):gsub("\195\169", "E"):gsub("\195\137", "E")
  return (s:upper():gsub("[^%w]", ""))
end
S.norm = norm

local function genOf(version)
  local ok, V = pcall(require, "src.core.GameVersion")
  return ok and V.generation and tonumber(V.generation(version)) or 2
end
S.genOf = genOf

-- a small deterministic generator (Park-Miller): the same seed, the same shelf
local function rng(seed)
  local s = math.floor(math.abs(seed)) % 2147483646 + 1
  return function(n)
    s = (s * 16807) % 2147483647
    return (s % n) + 1
  end
end
S.rng = rng

local function hash(str)
  local h = 0
  for i = 1, #tostring(str) do h = (h * 31 + tostring(str):byte(i)) % 1000003 end
  return h
end

-- the items a game of generation `gen` can take
function S.items(gen)
  local out = {}
  for _, it in ipairs(S.ITEMS) do
    if (gen or 2) >= it.gen then out[#out + 1] = it end
  end
  return out
end

-- the day's six Pokemon for a game: { dex, name, level, price, types }
function S.stock(version, day, n)
  local Courses = require("src.pokewalker.WalkerCourses")
  local sp = Courses.species()
  local max = Courses.maxDexFor(version)
  local pool = {}
  for d = 1, max do
    local s = sp[d]
    if s and (tonumber(s.catchRate) or 45) > 3 then pool[#pool + 1] = d end
  end
  local out = {}
  if #pool == 0 then return out end
  local r = rng(day * 7919 + hash(version))
  local seen = {}
  for _ = 1, 200 do
    if #out >= (n or 6) then break end
    local d = pool[r(#pool)]
    if not seen[d] then
      seen[d] = true
      local s = sp[d]
      local bst = tonumber(s.bst) or 300
      local level = math.max(5, math.min(25, 5 + math.floor((bst - 250) / 25)))
      local price = 40 + math.floor(bst / 4)
      if bst >= 580 then price = price * 2 end
      out[#out + 1] = { dex = d, name = s.name or ("#" .. d), level = level, price = price, types = s.types }
    end
  end
  return out
end

-- the week's Mystery Gifts (the same four for every game; one a game cannot
-- take is shown, marked, and cannot be bought for it)
function S.gifts(week)
  local r = rng(week * 104729 + 17)
  local items, mons = {}, {}
  for _, g in ipairs(S.GIFTS) do if g.kind == "mon" then mons[#mons + 1] = g else items[#items + 1] = g end end
  local out, used = {}, {}
  local function take(list)
    for _ = 1, 50 do
      local g = list[r(#list)]
      if not used[g.id] then used[g.id] = true; out[#out + 1] = g; return end
    end
  end
  -- two Pokemon and two items a week
  take(mons); take(items); take(mons); take(items)
  return out
end

function S.cosmetic(kind, id)
  for _, c in ipairs(S.COSMETICS[kind] or {}) do if c.id == id then return c end end
  return nil
end

-- the event courses, priced in order
function S.eventCourses(courses)
  local out, k = {}, 0
  for id = 0, 26 do
    local c = courses and courses[id]
    if c and c.event then
      out[#out + 1] = { id = id, name = c.name, price = S.COURSE_PRICE + 100 * k }
      k = k + 1
    end
  end
  return out
end

return S
