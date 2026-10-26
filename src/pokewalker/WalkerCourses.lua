-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKEWALKER'S COURSES, FOR EVERY GAME.
--
-- The 27 courses are HeartGold / SoulSilver's (src/pokewalker/WalkerRoutes.lua:
-- names, unlock watts, the three advantageous types, the six encounters and
-- ten items). A walk returns to the game its Pokemon came from, so the course
-- is filled from THAT game's Pokedex: a species the game cannot hold (Kanto's
-- 151, Johto's 251, Hoenn's 386, Sinnoh's 493, Unova's 649) is swapped for one
-- it can -- same primary type, nearest base-stat total, never a legendary
-- (catch rate 3 or below), never the same species twice on one course. The
-- swap is deterministic, so a course always reads the same for a game.
--
-- Species facts come from the most complete imported game's own data
-- (pokemon.lua), boiled down once to `pokewalker_species.lua` in the save
-- directory.

local C = {}

C.MAX_DEX = { [1] = 151, [2] = 251, [3] = 386, [4] = 493, [5] = 649 }
C.INDEX_FILE = "pokewalker_species.lua"
-- the caches to read species facts from, most complete first
C.SOURCES = { "black", "white", "heartgold", "soulsilver", "platinum", "emerald", "firered", "crystal", "gold", "silver", "red" }

local index

local refresh=false
function C.forget() index=nil;refresh=true end

-- { [dex] = { name, types = {...}, bst, catchRate } }
function C.species()
  if index then return index end
  local Ser = require("src.core.SaveSerializer")
  if not refresh and love and love.filesystem and love.filesystem.getInfo(C.INDEX_FILE) then
    local ok, t = pcall(Ser.decode, love.filesystem.read(C.INDEX_FILE) or "")
    if ok and type(t) == "table" and next(t) then index = t return index end
  end
  index = {}
  local Art=require("src.pokewalker.WalkerArt")
  for _, v in ipairs(C.SOURCES) do
    local roster=Art.roster(v)
    for _,rec in ipairs(roster)do
      if not index[rec.dex] then
        index[rec.dex]={name=rec.name,types=rec.types,bst=rec.bst,catchRate=rec.catchRate,growthRate=rec.growthRate}
      end
    end
    if #roster>0 and (index[649] or (v~="black" and v~="white")) then break end
  end
  refresh=false
  if next(index) and love and love.filesystem then love.filesystem.write(C.INDEX_FILE, Ser.encode(index)) end
  return index
end

function C.maxDexFor(version)
  local GameVersion = require("src.core.GameVersion")
  local info = GameVersion.info(version)
  local gen = info and tonumber(info.generation) or 2
  return C.MAX_DEX[gen] or 251
end

function C.routes()
  local ok, R = pcall(require, "src.pokewalker.WalkerRoutes")
  return ok and R or {}
end

local function primaryType(sp) return sp and sp.types and tostring(sp.types[1] or ""):upper() end

-- the stand-in for `dex` in a game that ends at `max`
function C.substitute(dex, max, used)
  local sp = C.species()
  local want = sp[dex]
  if dex <= max then return dex end
  local t, bst = primaryType(want), want and want.bst or 300
  local best, bestD
  for d = 1, max do
    local s = sp[d]
    if s and not used[d] and (tonumber(s.catchRate) or 45) > 3 and primaryType(s) == t then
      local diff = math.abs((s.bst or 0) - bst)
      if not bestD or diff < bestD then best, bestD = d, diff end
    end
  end
  if not best then
    for d = 1, max do
      local s = sp[d]
      if s and not used[d] and (tonumber(s.catchRate) or 45) > 3 then
        local diff = math.abs((s.bst or 0) - bst)
        if not bestD or diff < bestD then best, bestD = d, diff end
      end
    end
  end
  return best or 19
end

-- a course's six encounters for a game: { group, species, name, level, steps }
-- `hgss` picks the HeartGold or SoulSilver row where they differ
function C.forGame(courseId, version)
  local route = C.routes()[courseId]
  if not route then return {}, nil end
  local max = C.maxDexFor(version)
  local soul = version == "soulsilver"
  local sp = C.species()
  local used, out = {}, {}
  for _, e in ipairs(route.pokemon or {}) do
    local dex = tonumber((soul and e.ss) or e.hg or e.species) or 0
    if type(e.ss) == "table" or type(e.hg) == "table" then
      local pick = soul and e.ss or e.hg
      dex = tonumber(pick.species) or dex
    end
    local d = C.substitute(dex, max, used)
    used[d] = true
    out[#out + 1] = { group = e.group, species = d, name = (sp[d] and sp[d].name) or (d == dex and e.name) or "?",
                      level = e.level, steps = e.steps, gender = e.gender, original = dex ~= d and dex or nil }
  end
  return out, route
end

return C
