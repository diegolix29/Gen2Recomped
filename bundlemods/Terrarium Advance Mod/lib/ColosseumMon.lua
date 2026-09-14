-- lib/ColosseumMon.lua
--
-- Overworld adapter for the Colosseum (GC6E01) 3D Pokemon model cache.
--
-- StadiumPack / Stadium2Pack only cover Pokemon Stadium's roster (national
-- dex 1-151) and Pokemon Stadium 2's roster (1-251). Neither game ever
-- shipped a Gen III model, so PlayerModel / StadiumFollower / StadiumWilds /
-- RoamerStadium3D have never been able to show a 3D Hoenn Pokemon, and a
-- Gen III game has NO Stadium-sourced model to fall back to at all.
--
-- Pokemon Colosseum ships battle models for the complete 386-species
-- Gen I-III roster (see lib/ColosseumDex.lua), and the extraction/runtime
-- pipeline that decodes them already exists: extract/PokemonExtractor.lua
-- builds the on-disk cache, lib/PokemonActors.lua ("CBE") turns a cached
-- species into a live, drawable Actor. This module is a thin, defensive
-- bridge so the existing overworld consumers can fall back to a
-- Colosseum-sourced model wherever a Stadium-sourced one is not available --
-- every Gen III species, and every species at all when the player has only
-- imported the Colosseum disc and no Stadium ROM.
--
-- CBE is wired into this mod through a *different* internal loader
-- (main.lua's colosseumPackage/loadColosseumModule, not V.require), so its
-- PokemonActors singleton is reached indirectly, published cross-module via
-- mod.exports.pokemonActorsOverworld (see main.lua's
-- initializeColosseumIntegration). Everything here is therefore defensive:
-- the export may not exist yet (Colosseum disc not imported, or CBE failed
-- to initialize), or a given species may still be mid-extraction. Every
-- entry point degrades to "no model this frame" rather than erroring, so a
-- caller can always fall through to its existing 2D sprite path.

local V = ...
local Dex = V.require("ColosseumDex")
local Voxel3D = V.require("Voxel3D")

local M = {}

-- cacheKey(dex,variant) -> Actor, memoized so repeated overworld draws
-- (several wild Pokemon on screen, one follower, one player model) don't
-- repeatedly walk PokemonActors' own acquire path every frame. A miss is
-- never cached -- PokemonActors already backs off failed extractions
-- internally (see pendingExtract in PokemonActors.lua), so retrying a miss
-- here is cheap and picks up a species the moment it finishes extracting.
local actors = {}

local function service()
  local mod = V.mod
  return mod and mod.exports and mod.exports.pokemonActorsOverworld
end

-- Mirrors the enabled()/roamerStadiumModels pattern used by RoamerStadium3D
-- and the rest of this overworld family. Off means "never substitute a
-- Colosseum model", not "hide Pokemon that have no model" -- callers keep
-- falling through to their normal sprite/Stadium path either way.
function M.enabled()
  local opts = V.mod and V.mod.options
  if not (opts and type(opts.get) == "function") then return true end
  local ok, value = pcall(opts.get, opts, "colosseumOverworldModels")
  if not ok or value == nil then return true end
  return not (value == false or value == 0 or value == "0" or value == "false" or value == "off")
end

local function cacheKey(dex, variant)
  return (variant == "shiny") and (tostring(dex) .. ":shiny") or dex
end

-- Returns a live Actor for dex/variant, or nil. Never forces synchronous
-- source extraction beyond what PokemonActors.acquire already does on its
-- own (disk-cache read if extracted, background-friendly retry/backoff if
-- not); this is the same cost a battle send-out already pays.
local function actorFor(dex, variant)
  dex = tonumber(dex)
  if not (dex and Dex.supported(dex)) then return nil end
  local svc = service()
  if not (svc and type(svc.acquire) == "function") then return nil end
  local key = cacheKey(dex, variant)
  local cached = actors[key]
  if cached then return cached end
  local ok, actor = pcall(svc.acquire, "overworld", dex, variant,
    { context = { services = { informationSurface = false } } })
  if not ok or not actor then return nil end
  actors[key] = actor
  return actor
end

-- Whether a Colosseum model is available (already resident, or reachable
-- from the imported disc) for this dex right now. Cheap: does not force
-- extraction merely to answer.
function M.available(dex, variant)
  if not M.enabled() then return false end
  dex = tonumber(dex)
  if not (dex and Dex.supported(dex)) then return false end
  if actors[cacheKey(dex, variant)] then return true end
  local svc = service()
  if not (svc and type(svc.available) == "function") then return false end
  local ok, value = pcall(svc.available, "overworld", dex)
  return ok and value == true
end

function M.update(dex, variant, dt)
  local actor = actorFor(dex, variant)
  if not actor then return false end
  pcall(actor.idle, actor)
  local ok = pcall(actor.update, actor, dt or 0)
  return ok
end

-- x, groundY, z: world position. towardX/towardZ: facing vector, same
-- convention as Actor:matrix / StadiumMon:matrix (see M.towardFor below for
-- the up/down/left/right helper the Stadium consumers already use).
function M.matrix(dex, variant, x, groundY, z, towardX, towardZ)
  local actor = actorFor(dex, variant)
  if not actor then return nil end
  local ok, m = pcall(actor.matrix, actor, x, groundY, z, towardX, towardZ)
  if not ok then return nil end
  return m
end

-- Draws the actor previously resolved by matrix()/update() for this
-- dex/variant. Must be called with a matrix from M.matrix() in the same
-- frame -- mirrors the StadiumMon/StadiumRig two-step (matrix, then draw)
-- pattern the existing overworld consumers already use.
function M.draw(dex, variant, matrix)
  if not matrix then return false end
  local actor = actors[cacheKey(dex, variant)]
  local svc = service()
  if not (actor and svc and type(svc.withRenderer) == "function") then return false end
  local vp = Voxel3D.vp
  if not vp then return false end
  local ok, accepted = pcall(svc.withRenderer, vp, function()
    local drew = actor:draw(matrix)
    if drew == false then error("colosseum overworld draw declined") end
    return true
  end, { eye = Voxel3D.eye })
  return ok and accepted ~= false
end

-- Facing string ("up"/"down"/"left"/"right") -> toward vector, matching the
-- convention already used by StadiumWilds/RoamerStadium3D.
local TOWARD_BY_FACING = {
  down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 },
}
function M.towardFor(facing)
  local t = TOWARD_BY_FACING[facing] or TOWARD_BY_FACING.down
  return t[1], t[2]
end

function M.release(dex, variant)
  local key = cacheKey(dex, variant)
  local actor = actors[key]
  if actor then pcall(actor.release, actor) end
  actors[key] = nil
end

-- Release every pooled actor. Call on ROM/pack change, option toggle, or mod
-- teardown, same contract as StadiumFollower.clearCache/StadiumWilds.clearCache.
function M.clearCache()
  for _, actor in pairs(actors) do
    pcall(actor.release, actor)
  end
  actors = {}
end

return M
