-- Stadium models for overworld wild Pokemon.
--
-- This module handles the rendering of stadium models for wild Pokemon
-- spawned by the overworld_wild_spawns mod, replacing their sprites with
-- 3D stadium models when the option is enabled.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local StadiumPack = V.require("StadiumPack")
local Stadium2Pack = V.require("Stadium2Pack")
local StadiumMon = V.require("StadiumMon")
local Voxel3D = V.require("Voxel3D")
local ModSetting = V.require("ModSetting")
local ColosseumMon = V.require("ColosseumMon")
local ColosseumDex = V.require("ColosseumDex")

local StadiumWilds = {}

-- Currently loaded StadiumMon instances per entity
local entityMons = setmetatable({}, { __mode = "k" })

-- Last seen frame for cleanup
local slots = setmetatable({}, { __mode = "k" })
local frameNo = 0

-- Configuration
local WILDS_SCALE = 0.8  -- Scale for wild Pokemon models

-- the key under options.modOptions.DRAMATIC_SHAPE
StadiumWilds.KEY = "stadiumWilds"
StadiumWilds.LABEL = "STADIUM WILDS"

-- Persisted setting for stadium wilds toggle
StadiumWilds.setting = ModSetting.new(StadiumWilds.KEY, StadiumWilds.LABEL,
                                     { false, true }, { "OFF", "ON" })
  :setGate(function(value)
    local ok1, install1 = pcall(V.require, "StadiumInstall")
    local ok2, install2 = pcall(V.require, "Stadium2Install")
    return (ok1 and install1 and install1.available()) or (ok2 and install2 and install2.available())
  end)

-- ------- Entity Management

-- Check if stadium wilds feature is enabled
function StadiumWilds.enabled()
  if not StadiumWilds.setting:get() then
    return false
  end

  -- Check if Stadium 1 or Stadium 2 packs are available
  local okInstall, StadiumInstall = pcall(V.require, "StadiumInstall")
  local stadium1Available = okInstall and StadiumInstall and StadiumInstall.available()

  local okInstall2, Stadium2Install = pcall(V.require, "Stadium2Install")
  local stadium2Available = okInstall2 and Stadium2Install and Stadium2Install.available()

  -- Colosseum covers the full 386-species Gen I-III roster on its own, so a
  -- player who has imported the Colosseum disc (but no Stadium ROM) still
  -- gets 3D wild/roamer models -- and every Gen III game gets them at all,
  -- since neither Stadium game ever shipped a Gen III model to fall back to.
  local colosseumAvailable = ColosseumMon.enabled()

  return stadium1Available or stadium2Available or colosseumAvailable
end

-- Enable or disable the feature
function StadiumWilds.setEnabled(enabled)
  local currentGame = V.mod.world and V.mod.world.game
  StadiumWilds.setting:setValue(enabled == true, currentGame)
  if not enabled then
    StadiumWilds.clearCache()
  end
end

-- Check if an entity is a wild Pokemon (from overworld_wild_spawns mod)
function StadiumWilds.isWildPokemon(entity)
  if not entity then 
    return false 
  end
  
  -- First, check if there's a nested entity (actual game entity)
  if entity.entity and type(entity.entity) == "table" then
    local nested = entity.entity
    if nested.species and not nested.isPlayer and not nested.isFollower then
      return true
    end
    if nested.overworldWildSpawn == true then
      return true
    end
  end
  
  -- Check for the overworld_wild_spawns marker (Gen 1)
  local isWild = entity.overworldWildSpawn == true
  
  -- Also check by spawnId pattern as fallback (Gen 1)
  if not isWild and entity.id and type(entity.id) == "string" then
    isWild = entity.id:find("wilds_of_kanto_entity") ~= nil
  end
  if not isWild and entity.spawnId and type(entity.spawnId) == "string" then
    isWild = entity.spawnId:find("wilds_of_kanto_entity") ~= nil
  end
  
  -- Gen 2 / general fallback: any entity with a species that's not player/follower
  if not isWild and entity.species and not entity.isPlayer and not entity.isFollower then
    isWild = true
  end
  
  -- Sprite-based detection - ONLY for sprites that look like Pokemon, not NPCs
  -- Exclude known NPC sprite names
  local npcSpriteNames = {
    ["fisher"] = true,
    ["cooltrainerf"] = true,
    ["cooltrainerm"] = true,
    ["teacher"] = true,
    ["pokeball"] = true,
    ["lass"] = true,
    ["pokefanm"] = true,
    ["gramps"] = true,
    ["youngster"] = true,
    ["rival"] = true,
    ["npc"] = true,
  }
  
  if not isWild and entity.sprite and entity.sprite.def then
    local def = entity.sprite.def
    if def.image then
      -- Extract sprite name from path
      local spriteName = def.image:match("([^/]+)%.png$") or def.image:match("([^/]+)$")
      spriteName = spriteName:lower()
      
      -- Skip if this is a known NPC sprite
      if npcSpriteNames[spriteName] then
        return false
      end
      
      -- Otherwise, if it has animation frames and is not player/follower, treat as Pokemon
      if def.frames and def.frames > 1 and not entity.isPlayer and not entity.isFollower then
        isWild = true
      end
    end
  end
  
  return isWild
end

-- Get the species dex number from an entity
function StadiumWilds.getEntitySpeciesDex(entity)
  if not entity then return nil end
  
  -- First check nested entity (the actual game entity)
  if entity.entity and type(entity.entity) == "table" then
    local nestedSpecies = entity.entity.species
    if nestedSpecies then
      -- If it's already a number, return it
      local num = tonumber(nestedSpecies)
      if num and num >= 1 and num <= ColosseumDex.speciesCount then
        return num
      end
      
      -- Handle "SPECIES_XXX" format from nested entity
      if type(nestedSpecies) == "string" then
        local dexStr = nestedSpecies:match("SPECIES_(%d+)")
        if dexStr then
          local dexNum = tonumber(dexStr)
          if dexNum and dexNum >= 1 and dexNum <= ColosseumDex.speciesCount then
            return dexNum
          end
        end
      end
    end
  end
  
  local species = entity.species
  if not species then return nil end
  
  -- If it's already a number, return it
  local num = tonumber(species)
  if num and num >= 1 and num <= ColosseumDex.speciesCount then
    return num
  end
  
  -- Handle "SPECIES_XXX" format (e.g., "SPECIES_016" -> 16)
  if type(species) == "string" then
    local dexStr = species:match("SPECIES_(%d+)")
    if dexStr then
      local dexNum = tonumber(dexStr)
      if dexNum and dexNum >= 1 and dexNum <= ColosseumDex.speciesCount then
        return dexNum
      end
    end
  end
  
  -- Try to get from game data
  local mod = V.mod
  local game = mod.world and mod.world.game
  if game and game.data and game.data.pokemon then
    local mon = game.data.pokemon[species]
    if mon and mon.dex then
      local dexNum = tonumber(mon.dex)
      if dexNum and dexNum >= 1 and dexNum <= ColosseumDex.speciesCount then
        return dexNum
      end
    end
    
    -- Try iterating through all pokemon to find by name
    for id, def in pairs(game.data.pokemon) do
      if def and def.name and def.name:upper() == tostring(species):upper() then
        local dexNum = tonumber(def.dex)
        if dexNum and dexNum >= 1 and dexNum <= ColosseumDex.speciesCount then
          return dexNum
        end
      end
      if tostring(id):upper() == tostring(species):upper() then
        local dexNum = tonumber(def.dex)
        if dexNum and dexNum >= 1 and dexNum <= ColosseumDex.speciesCount then
          return dexNum
        end
      end
    end
  end
  
  return nil
end

-- Load a stadium model for a wild Pokemon entity
function StadiumWilds.loadEntityModel(entity)
  if not entity or not StadiumWilds.enabled() then
    return false
  end

  local dex = StadiumWilds.getEntitySpeciesDex(entity)
  if not dex then
    return false
  end

  -- Check if already loaded
  if entityMons[entity] then
    return true
  end

  -- Stadium 1 (1-151) / Stadium 2 (1-251) are tried first when the species
  -- is in range, so a player who already set up Stadium packs keeps seeing
  -- those exact models. Gen III (252-386) has no Stadium source at all, and
  -- a player without any Stadium ROM has none either -- both fall through to
  -- the Colosseum cache below, which covers the complete 386 roster.
  if dex <= 251 then
    local ok, mon = pcall(StadiumMon.new, "overworld")
    if ok and mon then
      local okSpecies, ready = pcall(mon.setSpecies, mon, dex, true)
      if okSpecies and ready and mon.rig then
        -- Keep in cache - use the appropriate pack based on which one loaded the model
        if Stadium2Pack.available() then
          if type(Stadium2Pack.keep) == "function" then pcall(Stadium2Pack.keep, dex, false) end
        else
          if type(StadiumPack.keep) == "function" then pcall(StadiumPack.keep, dex, false) end
        end

        mon.scale = WILDS_SCALE
        entityMons[entity] = { kind = "stadium", mon = mon }
        slots[entity] = { lastSeen = frameNo }
        mon:play("idle", 1)
        return true
      end
    end
  end

  -- Colosseum fallback (also the primary path for dex > 251). ColosseumMon
  -- pools one Actor per species, same tradeoff RoamerStadium3D documents for
  -- its Stadium rig pool: several wild Pokemon of the same species on screen
  -- share one animation clock (they breathe in sync), but each still gets
  -- its own position/facing at draw time.
  if ColosseumMon.available(dex) then
    entityMons[entity] = { kind = "colosseum", dex = dex, variant = "normal" }
    slots[entity] = { lastSeen = frameNo }
    return true
  end

  return false
end

-- Check if an entity has a loaded stadium model
function StadiumWilds.hasModel(entity)
  if not entity then return false end
  return entityMons[entity] ~= nil
end

-- ------- Rendering

-- Update animation state for an entity
function StadiumWilds.updateEntity(entity, dt)
  if not entity then return end

  local slot = slots[entity]
  if not slot then return end
  slot.lastSeen = frameNo

  local model = entityMons[entity]
  if not model then return end

  local dtForFrame = dt or (1 / 60)
  if dtForFrame > 0.10 then dtForFrame = 0.10 end

  if model.kind == "colosseum" then
    ColosseumMon.update(model.dex, model.variant, dtForFrame)
  elseif model.mon then
    model.mon:update(dtForFrame)
  end
end

-- Draw a wild Pokemon entity
function StadiumWilds.drawEntity(entity)
  if not entity then return false end

  local model = entityMons[entity]
  if not model then return false end

  local mon = model.mon
  local x = entity.px or 0
  local y = entity.py or 0
  local gh = entity.gh or 0
  
  -- For Gen 2, ensure we get the correct ground height from the map
  -- This fixes sprite placement issues where sprites appear on top of ledges
  local mod = V.mod
  local map = mod and mod.world and mod.world.map
  if map and entity.cellX and entity.cellY then
    local VoxelScene = V.require("VoxelScene")
    local okGround, correctGh = pcall(VoxelScene.groundAt, map, entity.cellX, entity.cellY)
    if okGround and correctGh ~= nil then
      gh = correctGh
    end
  end
  
  -- Determine facing direction
  local facing = entity.facing or "down"
  
  -- Check if we're in free-roam mode (1st or 3rd person)
  local FirstPerson = V.require("FirstPerson")
  local b = FirstPerson.cardBlend()
  
  local fx, fz = 0, 1
  if b > 0 then
    -- In free-roam mode, use camera-relative direction
    local yaw = FirstPerson.cardYaw(x + 8, y + 8)
    fx, fz = math.sin(yaw), math.cos(yaw)
  else
    -- In normal mode, use entity's facing direction
    if facing == "up" then fx, fz = 0, -1
    elseif facing == "left" then fx, fz = -1, 0
    elseif facing == "right" then fx, fz = 1, 0
    end
  end
  
  if model.kind == "colosseum" then
    local matrix = ColosseumMon.matrix(model.dex, model.variant, x + 8, gh, y + 8, fx, fz)
    if not matrix then return false end
    return ColosseumMon.draw(model.dex, model.variant, matrix)
  end

  -- Build model matrix using StadiumMon's matrix method
  local okMatrix, matrix = pcall(mon.matrix, mon, x + 8, gh, y + 8, fx, fz)
  if not okMatrix or not matrix then return false end
  
  -- Build the mesh
  local okBuild, didBuild = pcall(mon.build, mon)
  if not okBuild or not didBuild then return false end
  
  -- Draw using the rig directly
  if mon.rig and mon.rig.draw then
    mon.rig:draw(matrix, nil, false)
  end
  
  return true
end

-- ------- Cleanup

-- Clear all cached data
function StadiumWilds.clearCache()
  entityMons = setmetatable({}, { __mode = "k" })
  slots = setmetatable({}, { __mode = "k" })
  pcall(ColosseumMon.clearCache)
end

-- Clear entity-specific data (called when entity is removed)
function StadiumWilds.clearEntity(entity)
  if not entity then return end
  entityMons[entity] = nil
  slots[entity] = nil
end

return StadiumWilds