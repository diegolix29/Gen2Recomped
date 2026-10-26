-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT A MINIGAME PLAYS WITH: the walking Pokemon, the current course's wild
-- Pokemon and items, and a seeded random number generator. No drawing and no
-- love.* at load, so the games' rules run headless (tools/walker_minigames_check).
--
--   ctx.walker   { dex, name, level, friendship } -- the walking Pokemon, or
--                Pikachu standing in when nobody is out (ctx.standIn = true)
--   ctx.course   { id, name, types }
--   ctx.wild     { { dex, name, level, group = "A"|"B"|"C" }, ... } the
--                course's six, already swapped into the walker's own game's
--                dex by WalkerCourses.forGame when a Pokemon is walking
--   ctx.items    item names the course can give (cheap ones first)
--   ctx.rng(n)   1..n;  ctx.rand() [0, 1)

local C = {}

-- Park-Miller: deterministic, and every product stays exact in a double
function C.newRng(seed)
  local s = math.floor(tonumber(seed) or os.time()) % 2147483646 + 1
  local function nextv()
    s = (s * 16807) % 2147483647
    return s
  end
  local rand = function() return (nextv() - 1) / 2147483646 end
  local rng = function(n)
    n = math.max(1, math.floor(n or 1))
    return math.floor(rand() * n) + 1
  end
  return rng, rand
end

-- always handy: given to every run on top of the course's own items
C.BASIC_ITEMS = { "Poke Ball", "Oran Berry", "Pecha Berry", "Potion", "Great Ball" }

-- a stand-in roster for a course-less walker (the routes failed to load)
C.FALLBACK_WILD = {
  { dex = 16, name = "Pidgey", level = 5, group = "C" }, { dex = 161, name = "Sentret", level = 5, group = "C" },
  { dex = 29, name = "Nidoran", level = 5, group = "B" }, { dex = 43, name = "Oddish", level = 6, group = "B" },
  { dex = 84, name = "Doduo", level = 8, group = "A" }, { dex = 115, name = "Kangaskhan", level = 8, group = "A" },
}

local function routes()
  local ok, Courses = pcall(require, "src.pokewalker.WalkerCourses")
  if not ok then return nil end
  local okR, r = pcall(Courses.routes)
  return okR and r or nil, Courses
end

function C.build(st, seed, preferredVersion)
  local ctx = {}
  ctx.rng, ctx.rand = C.newRng(seed)
  local wk = st and st.walking
  if wk and wk.species then
    ctx.walker = { dex = wk.species, name = wk.name or "Your Pokemon", level = wk.level or 5,
                   friendship = wk.friendship }
  else
    ctx.walker = { dex = 25, name = "Pikachu", level = 5 }
    ctx.standIn = true
  end
  local all, Courses = routes()
  local id = st and st.course or 0
  local route = all and all[id]
  ctx.course = { id = id, name = route and route.name or "Refreshing Field", types = route and route.types or {} }
  -- the six: from the walker's own game when one is walking (so a catch can
  -- go home), else the course's published list
  local wild = {}
  local version = wk and wk.source and wk.source.version
  if version and Courses then
    local ok, entries = pcall(Courses.forGame, id, version)
    if ok and type(entries) == "table" then
      for _, e in ipairs(entries) do
        wild[#wild + 1] = { dex = e.species, name = e.name, level = e.level or 5, group = e.group or "C" }
      end
    end
  end
  if #wild == 0 and route then
    for _, e in ipairs(route.pokemon or {}) do
      wild[#wild + 1] = { dex = tonumber(e.species), name = e.name, level = e.level or 5, group = e.group or "C" }
    end
  end
  if #wild == 0 then for _, e in ipairs(C.FALLBACK_WILD) do wild[#wild + 1] = e end end
  -- Use the complete imported source roster for minigames, rather than
  -- repeating just the course's six encounters. Keep course radar unchanged.
  local okArt, Art=pcall(require,"src.pokewalker.WalkerArt")
  local selected=version or preferredVersion
  if not selected then
    local okGV, GV=pcall(require,"src.core.GameVersion")
    if okGV then selected=GV.get() end
  end
  local roster
  if okArt and Art.roster then
    local ok,list=pcall(Art.roster,selected)
    if ok and #list>0 then roster=list end
    -- With no walking Pokemon, use a real import if the last game is absent.
    if not roster and not version and not preferredVersion then
      for _,v in ipairs({"black","white","heartgold","soulsilver","platinum","emerald","firered","crystal","polishedcrystal","prism","gold","silver","yellow","blue","red"}) do
        ok,list=pcall(Art.roster,v)
        if ok and #list>0 then selected=v;roster=list;break end
      end
    end
  end
  if roster then
    wild={}
    for i,e in ipairs(roster)do wild[i]=e end
    for i=#wild,2,-1 do local j=ctx.rng(i);wild[i],wild[j]=wild[j],wild[i] end
    ctx.version=selected
    -- THE GAME'S OWN POKEMON FIRST: the species its encounter tables name
    -- (WalkerArt.wildSpecies) are `native`, weighted by how many slots name
    -- them, and lead the list -- so a Black run is Unova's, a Crystal run
    -- Johto's -- while the rest of the roster can still turn up, rarely
    local okW, natives = pcall(Art.wildSpecies, selected)
    if okW and type(natives) == "table" and next(natives) then
      local front, back = {}, {}
      for _, e in ipairs(wild) do
        local n = natives[e.dex]
        if n then
          e.native, e.weight = true, math.min(C.NATIVE_CAP, n)
          front[#front + 1] = e
        else
          back[#back + 1] = e
        end
      end
      if #front > 0 then
        wild = front
        for _, e in ipairs(back) do wild[#wild + 1] = e end
        ctx.natives = #front
      end
    end
    local present={}
    for _,e in ipairs(wild)do present[e.dex]=true end
    if ctx.standIn and not present[ctx.walker.dex] then
      ctx.walker={dex=wild[1].dex,name=wild[1].name,level=5}
    end
  elseif version or preferredVersion then
    -- Never award a Pokemon borrowed from a different game when its import
    -- is unavailable. The walking Pokemon is still known to belong there.
    wild=wk and wk.species and {{dex=wk.species,name=wk.name or "Your Pokemon",level=wk.level or 5,group="C"}} or {}
    ctx.version=selected
  end
  if #wild==0 then error("Import this game before playing its minigames",0) end
  ctx.speciesSet={}
  for _,e in ipairs(wild)do ctx.speciesSet[e.dex]=true end
  ctx.wild = wild
  -- items: the course's cheaper half, then the basics
  local items, seen = {}, {}
  local function add(n) if n and not seen[n] then seen[n] = true; items[#items + 1] = n end end
  for _, it in ipairs((route and route.items) or {}) do
    if (tonumber(it.steps) or 0) <= 1000 then add(it.name) end
  end
  for _, n in ipairs(C.BASIC_ITEMS) do add(n) end
  ctx.items = items
  return ctx
end

-- a wild Pokemon, weighted C common / B less / A rare (the radar's 6 / 3 / 1),
-- and the game's own (`native`, Context.build) far ahead of the rest of its
-- roster: NATIVE_BASE plus the slots that name it (to NATIVE_CAP), against
-- STRAY for a species its wild never holds
C.GROUP_WEIGHT = { A = 1, B = 3, C = 6 }
C.NATIVE_BASE, C.NATIVE_CAP, C.STRAY = 4, 12, 0.25
function C.weightOf(ctx, e)
  local g = C.GROUP_WEIGHT[e.group] or 1
  -- no natives marked (the game's encounters not imported): rarity only
  if not (ctx.natives and ctx.natives > 0) then return g end
  if e.native then return g * (C.NATIVE_BASE + (e.weight or 1)) end
  return g * C.STRAY
end

function C.pickWild(ctx)
  local sum = 0
  for _, e in ipairs(ctx.wild) do sum = sum + C.weightOf(ctx, e) end
  local roll = ctx.rand() * sum
  for _, e in ipairs(ctx.wild) do
    roll = roll - C.weightOf(ctx, e)
    if roll <= 0 then return e end
  end
  return ctx.wild[1]
end

-- n different wild Pokemon, by the same weights (natives first when drawn)
function C.pickSeveral(ctx, n, exclude)
  local out, seen = {}, {}
  for k in pairs(exclude or {}) do seen[k] = true end
  for _ = 1, n * 8 do
    if #out >= n then break end
    local e = C.pickWild(ctx)
    if e and not seen[e.dex] then seen[e.dex] = true; out[#out + 1] = e end
  end
  return out
end

function C.pickItem(ctx)
  return ctx.items[ctx.rng(#ctx.items)]
end

return C
