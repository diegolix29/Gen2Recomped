-- ORASRuntime: the Pokemon actor runtime for ORAS models when the Colosseum
-- runtime is withheld (no Colosseum disc imported, or its build not ready).
--
-- main.lua only loads PokemonActors as part of the whole Colosseum stack, so
-- without the disc every 3D-actor surface fell back to sprites even with
-- ORAS models built.  This loads PokemonActors with just what it needs
-- (Mat4, GeneratedAssets, RuntimeMeshCache, WorkBudget, ShinySupport,
-- ColosseumDex) and publishes it where every consumer already looks:
--
--   mod.exports.pokemonActorsOverworld  ColosseumMon (overworld spawns,
--                                       followers, roamers) and
--                                       ColosseumBattleMon (COLOSSEUM A/B)
--   V.PokemonActors                     everything that reads it directly
--
-- In place of the Colosseum PokemonExtractor it hands PokemonActors a tiny
-- cache-path shim: it serves only species ORASActorCache built
-- (ColosseumDex.isOras) and never extracts anything -- there is no disc.
-- Installed only when oras/pokemon/index.lua lists at least one species.

local V = ...

local R = {}

local function log(mod, level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

-- `loadPackage(path, arg)` is main.lua's colosseumPackage
function R.install(mod, loadPackage)
  if R.actors then return R.actors end
  local okIdx, src = pcall(mod.cache.read, mod.cache, "oras/pokemon/index.lua")
  if not (okIdx and type(src) == "string" and src:find("%d")) then return nil, "no ORAS models built" end

  local ns = {
    mod = mod, engineRequire = require,
    PokemonHeights = V.PokemonHeights,
    voxelRequire = function(name) return V.require(name) end,
  }
  local function load(path, arg)
    local ok, m = pcall(loadPackage, path, arg)
    if not ok or not m then
      log(mod, "warn", "ORAS runtime: %s failed to load: %s", path, tostring(m))
      return nil
    end
    return m
  end
  local function module(name, arg)
    local m = load("lib/" .. name .. ".lua", arg == nil and ns or arg)
    if m then ns[name] = m end
    return m
  end

  ns.PayloadPreserver = load("extract/PayloadPreserver.lua")
  ns.Mat4 = load("lib/Mat4.lua")
  if not ns.PokemonHeights then ns.PokemonHeights = load("lib/PokemonHeights.lua") end
  for _, name in ipairs({ "GeneratedAssets", "RuntimeMeshCache", "WorkBudget", "ShinySupport", "ColosseumDex" }) do
    if not module(name) then return nil, name .. " unavailable" end
  end
  local Dex = ns.ColosseumDex
  pcall(Dex.loadOras, mod)

  local Actors = module("PokemonActors")
  if not Actors then return nil, "PokemonActors unavailable" end

  -- the cache-path half of PokemonExtractor's interface, for ORAS caches only
  local shim = {
    revision = 1,
    cachePath = function(dex, variant) return Dex.cacheRoot(dex, variant) .. "/model_cache.lua" end,
    revPath = function(dex, variant) return Dex.cacheRoot(dex, variant) .. "/rev.txt" end,
    stamp = function() return "oras-actor=1\n" end,
    isCached = function(m, dex, opts)
      if not Dex.isOras(dex, opts and opts.variant) then return false end
      local ok, info = pcall(m.cache.info, m.cache, Dex.cacheRoot(dex, opts and opts.variant) .. "/model_cache.lua")
      return ok and type(info) == "table"
    end,
    extractSpecies = function() return nil, "no Colosseum disc; ORAS models come from OPTIONS -> ORAS MODELS" end,
  }
  local okInstall, err = pcall(Actors.install, shim, nil, nil, nil)
  if not okInstall then return nil, tostring(err) end

  mod.exports.pokemonActorsOverworld = Actors.service
  V.PokemonActors = Actors
  V.ColosseumDex = V.ColosseumDex or Dex
  R.actors = Actors
  local n = 0
  for _ in pairs(Dex.orasDex or {}) do n = n + 1 end
  log(mod, "info", "ORAS actor runtime installed without the Colosseum runtime (%d species)", n)
  return Actors
end

return R
