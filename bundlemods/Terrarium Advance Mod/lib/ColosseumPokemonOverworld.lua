-- COLOSSEUM POKEMON OVERWORLD: Colosseum models for player, followers, wild life, and roamers
--
-- This module handles loading and rendering Colosseum Pokemon models for overworld use,
-- similar to how Stadium models work but using the Colosseum Pokemon cache with 386 Pokemon support.

local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local PokemonActors = V.PokemonActors
local GeneratedAssets = V.GeneratedAssets
local ModSetting = V.require("ModSetting")

local ColosseumPokemonOverworld = {}

-- Cache for loaded Colosseum Pokemon models
local modelCache = {}

-- Cache for loaded Colosseum Pokemon actors
local actorCache = {}

-- Current loaded model data
local currentActor = nil
local currentDex = nil
local currentShiny = nil

-- Settings
local wildPokemonModel
if ModSetting then
  wildPokemonModel = ModSetting.new("wildPokemonModel", "WILD POKEMON MODEL",
    { "colosseum", "stadium", "sprite" }, { "COLOSSEUM", "STADIUM", "SPRITE" })
end

-- Check if Pokemon-only mode is active
local function isPokemonOnlyMode()
  if not ModSetting then return false end
  local ok, mode = pcall(function()
    local setting = ModSetting.new("colosseumExtractionMode", "COLOSSEUM EXTRACTION",
      { "full", "pokemon-only", "ui-only" }, { "FULL", "POKEMON ONLY", "UI ONLY" })
    return setting:get()
  end)
  return ok and mode == "pokemon-only"
end

-- Get model preference for a specific role
local function getModelPreference(role)
  if not ModSetting then return "colosseum" end
  
  local settingName = nil
  if role == "player" then
    settingName = "playerPokemonModel"
  elseif role == "follower" then
    settingName = "followerPokemonModel"
  elseif role == "wild" then
    settingName = "wildPokemonModel"
  elseif role == "roamer" then
    settingName = "wildPokemonModel" -- Use same setting for roamers as wild
  end
  
  if not settingName then return "colosseum" end
  
  local ok, value = pcall(function()
    local setting = ModSetting.new(settingName, string.upper(settingName:gsub("(%l)(%u*%l)", "%1 %2")),
      { "colosseum", "stadium", "sprite" }, { "COLOSSEUM", "STADIUM", "SPRITE" })
    return setting:get()
  end)
  
  return ok and value or "colosseum"
end

-- Check if Colosseum cache should be used for a role
function ColosseumPokemonOverworld.shouldUseColosseum(role)
  -- In Pokemon-only mode, always use Colosseum cache
  if isPokemonOnlyMode() then
    return true
  end
  
  -- Otherwise, check role-specific setting
  local preference = getModelPreference(role)
  return preference == "colosseum"
end

-- Load a Colosseum Pokemon model by dex number
function ColosseumPokemonOverworld.loadModel(dex, shiny, role)
  if not dex then return false, "no dex number" end
  
  -- Check if we should use Colosseum cache
  if not ColosseumPokemonOverworld.shouldUseColosseum(role) then
    return false, "colosseum not preferred for this role"
  end
  
  -- Check cache first
  local cacheKey = string.format("%d_%s_%s", dex, tostring(shiny or false), role or "default")
  if actorCache[cacheKey] then
    currentActor = actorCache[cacheKey]
    currentDex = dex
    currentShiny = shiny
    return true
  end
  
  -- Try to load from Colosseum Pokemon cache using PokemonActors
  if not (PokemonActors and PokemonActors.acquire) then
    return false, "PokemonActors not available"
  end
  
  local variant = shiny and "shiny" or "normal"
  local actor, err = pcall(PokemonActors.acquire, PokemonActors, "colosseum-overworld", dex, variant, {
    context = { 
      services = { 
        colosseumOverworld = true,
        overworldRole = role or "default"
      }
    }
  })
  
  if not ok or not actor then
    return false, err or "failed to acquire Colosseum actor"
  end
  
  -- Cache the actor
  actorCache[cacheKey] = actor
  currentActor = actor
  currentDex = dex
  currentShiny = shiny
  
  return true
end

-- Get current loaded actor
function ColosseumPokemonOverworld.getCurrentActor()
  return currentActor
end

-- Clear cache
function ColosseumPokemonOverworld.clearCache()
  actorCache = {}
  currentActor = nil
  currentDex = nil
  currentShiny = nil
end

-- Export settings
if wildPokemonModel then
  ColosseumPokemonOverworld.wildPokemonModel = wildPokemonModel
end

return ColosseumPokemonOverworld