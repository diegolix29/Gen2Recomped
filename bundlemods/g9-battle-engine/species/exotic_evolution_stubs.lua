-- Exotic evolution-method stubs: schema plumbing only, no real trigger
-- logic yet -- explicit user-deferred future scope ("hooks for exotic
-- evolution methods").
--
-- Without a REGISTERED evolution_methods entry for a given id, the mod
-- fails to load entirely -- confirmed live, not assumed: Schemas.lua's
-- crossValidate (a static pass that runs after every mod's data merges)
-- treats an evo.method with no matching evolution_methods registration as
-- a dangling reference ("unresolved reference to evolution_methods
-- %q"), surfaced as a blocking Mod Manager error, same severity as the
-- evolutions record's own field-shape check. This is NOT the same as
-- Evolution.pendingFor's own runtime dispatch loop, which genuinely does
-- skip an unrecognized method gracefully (`if method and method.check
-- then`) -- that forgiving behavior never gets reached if crossValidate
-- has already failed the whole mod load first.
--
-- So every method species_evolutions.lua's data uses beyond this
-- engine's own native LEVEL/ITEM/TRADE and this mod's own HAPPINESS
-- (installHappinessEvolution, main.lua) needs SOME registration to be
-- loadable at all. Registering a check that always returns false
-- satisfies that validation while keeping every one of these evolutions
-- functionally inert -- "not built yet", not "built wrong, misfiring" --
-- until real trigger logic (day/night tracking, gender, location flags,
-- move-known checks, and the rest) replaces a given stub one at a time.
return function(mod)
  local EXOTIC_METHODS = {
    "ATTACK_DEFENSE_EQUAL", "ATTACK_GREATER", "BEAUTY", "CABLELINKITEM",
    "CASCOON", "DAYHOLDITEM", "DEFENSE_GREATER", "HAPPINESSDAY",
    "HAPPINESSMOVETYPE", "HAPPINESSNIGHT", "HASINPARTY", "HASMOVERANDFORM",
    "HAS_MOVE", "ITEMFEMALE", "ITEMMALE", "ITEMNIGHT", "LEVELCOINS",
    "LEVELDARKINPARTY", "LEVELDAY", "LEVELDEFEATITSKINDWITHITEM",
    "LEVELFEMALE", "LEVELMALE", "LEVELNIGHT", "LEVELRAIN", "LEVELRANDFORM",
    "LEVELRECOILDAMAGEFORM0", "LEVELUSEMOVECOUNT", "LEVELWALK",
    "LOCATIONFLAG", "NIGHTHOLDITEM", "NINJASK", "NONE", "SHEDINJA",
    "SILCOON", "TRADESPECIES",
  }
  for _, id in ipairs(EXOTIC_METHODS) do
    mod.content.evolution_methods:register(id, {
      check = function() return false end,
      describe = function() return "Not yet implemented" end,
    })
  end
  mod.log:info("galar_gmax_dex: registered %d exotic evolution-method stubs (inert, future scope)",
    #EXOTIC_METHODS)
end
