-- lib/ChainBattleMon.lua
--
-- 3D-3D A/B battles (lib/OverworldBattle.lua's ladder): one side's Pokemon,
-- played by the best 3D model the player has for THAT species:
--
--   1. ORAS        } the PokemonActors service (ColosseumBattleMon): an ORAS
--   2. Colosseum   } build wins over the Colosseum disc per species already
--                    (ColosseumDex.isOras routes the dex to oras/pokemon)
--   3. Stadium 2   } StadiumPack (StadiumMon): PREFER_STADIUM2 reads the
--   4. Stadium 1   } Stadium 2 pack first, then Stadium 1
--
-- A species none of them has declines (setSpecies -> false) and Stadium
-- leaves that side on its pic, exactly as each rung did before.
--
-- Stadium.lua drives session.player / session.enemy through one surface
-- (methods + plain fields, see StadiumMon / ColosseumBattleMon headers). This
-- object holds one of each class and FORWARDS that surface to whichever one
-- the current species picked: field reads and writes go to it, and methods
-- are called with it as `self`, so neither class needs to know it is wrapped.
-- The pick is redone only when the species or shininess changes, so the
-- per-frame setSpecies call stays as cheap as the wrapped class's own.
--
-- ORAS move effects (lib/ORASEffectsScene.lua) read mon.actor (exact body
-- attachments) or mon.model_matrix + worldHeight (Stadium models): both
-- answer through the forwarding.

local V = ...

local StadiumMon = V.require("StadiumMon")
local ColosseumBattleMon = V.require("ColosseumBattleMon")

local ChainBattleMon = {}

-- set false to skip the Stadium fallback (actors only), for testing
ChainBattleMon.STADIUM_FALLBACK = true

local function service()
  local mod = V.mod
  return mod and mod.exports and mod.exports.pokemonActorsOverworld
end

-- Can the actor service show `dex` now (ORAS or Colosseum cache, or a
-- Colosseum disc to build it from)?
local function actorAvailable(dex)
  local svc = service()
  if not (svc and type(svc.available) == "function") then return false end
  local ok, yes = pcall(svc.available, "battle", dex)
  return ok and yes == true
end

-- Which source a side ended up on, for the F12 dump and the log.
local function sourceOf(inner)
  local a = inner.actor
  local sc = a and a.scene
  if sc and sc.source == "ORAS" then return "oras" end
  if a then return "colosseum" end
  return nil
end

local methodCache = setmetatable({}, { __mode = "k" })

-- the forwarder: `chain` keeps its own state in a hidden table
local function forward(chain, cur, key)
  local value = cur[key]
  if type(value) ~= "function" then return value end
  local byFn = methodCache[cur]
  if not byFn then byFn = {}; methodCache[cur] = byFn end
  local wrapped = byFn[value]
  if not wrapped then
    wrapped = function(self, ...)
      -- called as chain:method(...): run it on the delegate itself
      if self == chain then return value(cur, ...) end
      return value(self, ...)
    end
    byFn[value] = wrapped
  end
  return wrapped
end

function ChainBattleMon.new(side)
  local st = {
    side = side,
    colosseum = ColosseumBattleMon.new(side),
    stadium = StadiumMon.new(side),
    dex = nil, shiny = nil,   -- the request the current pick answers
    source = nil,             -- "oras" / "colosseum" / "stadium" / nil
  }
  st.cur = st.colosseum
  local chain = {}
  local own = {}

  -- the chain's own surface; everything else forwards to st.cur
  function own.setSpecies(_, dex, shiny, battler, gameObj)
    shiny = shiny and true or false
    if dex == st.dex and shiny == st.shiny then
      return st.cur:setSpecies(dex, shiny, battler, gameObj)
    end
    st.dex, st.shiny, st.source = dex, shiny, nil
    -- drop whatever the last species loaded on either half
    st.colosseum:release()
    st.stadium:release()
    st.cur = st.colosseum
    if not dex then
      st.colosseum:setSpecies(nil, shiny)
      return false
    end
    if actorAvailable(dex) and st.colosseum:setSpecies(dex, shiny, battler, gameObj) then
      st.cur = st.colosseum
      st.source = sourceOf(st.colosseum)
      return true
    end
    if ChainBattleMon.STADIUM_FALLBACK and st.stadium:setSpecies(dex, shiny, battler, gameObj) then
      -- the actor half may hold a half-made attempt
      st.colosseum:release()
      st.cur = st.stadium
      st.source = "stadium"
      return true
    end
    -- nobody has it: park on a half whose species is set and rig nil, so
    -- the repeat call above keeps answering false cheaply (no retry, as
    -- each class did on its own rung)
    st.colosseum:release()
    if ChainBattleMon.STADIUM_FALLBACK then
      st.cur = st.stadium
    else
      st.cur = st.colosseum
      st.colosseum.species, st.colosseum.shiny = dex, shiny
    end
    return false
  end

  function own.release(_)
    st.colosseum:release()
    st.stadium:release()
    st.cur = st.colosseum
    st.dex, st.shiny, st.source = nil, nil, nil
  end

  -- "oras" / "colosseum" / "stadium" / nil: where this side's model came from
  function own.modelSource(_) return st.source end

  return setmetatable(chain, {
    __index = function(_, key)
      local f = own[key]
      if f then return f end
      if key == "chain" then return st end
      return forward(chain, st.cur, key)
    end,
    __newindex = function(_, key, value)
      st.cur[key] = value
    end,
  })
end

return ChainBattleMon
