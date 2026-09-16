-- Pokemon Colosseum models for overworld Pokemon entities.
--
-- This module reuses the existing Colosseum model system (PokemonActors)
-- for overworld rendering, similar to how OverworldStadium works for Stadium models.
--
-- Integration contract:
--   * VoxelScene captures the real entity beside each rendered pose.
--   * prepare(posed) resolves an exact species, loads a Colosseum model, and stores it.
--   * draw(pose) renders the Colosseum model instead of the 2D sprite.
--
-- Companion mods can tag a spawned NPC:
--
--   local ds = mod.find("DRAMATIC_SHAPE")
--   local ow = ds and ds.exports and ds.exports.lib
--              and ds.exports.lib.require("OverworldColosseum")
--   if ow then ow.tag(npc, "PIKACHU") end
--
-- Accepted tags are National Dex numbers (1-386) or engine species strings.
local V = ...

local ColosseumDex = nil  -- Load lazily
local PokemonActors = nil  -- Load lazily
local GeneratedAssets = nil  -- Load lazily
local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")

-- Cache root for Colosseum models
local CACHE_ROOT = "cache/pokemon"

local OverworldColosseum = {}

-- Initialize global tag state in V namespace to share across module instances
if not V._colosseumTagState then
  V._colosseumTagState = {
    tagged = setmetatable({}, { __mode = "k" }),
    taggedById = {},
    entityDexCache = setmetatable({}, { __mode = "k" }),
    slots = setmetatable({}, { __mode = "k" }),
    nameCache = {},
    frameNo = 0,
    reported = {},
    modelCache = {}
  }
end

local tagged = V._colosseumTagState.tagged
local taggedById = V._colosseumTagState.taggedById
local entityDexCache = V._colosseumTagState.entityDexCache
local slots = V._colosseumTagState.slots
local nameCache = V._colosseumTagState.nameCache
local frameNo = V._colosseumTagState.frameNo
local reported = V._colosseumTagState.reported
local STALE_FRAMES = 120
local modelCache = V._colosseumTagState.modelCache

-- Reverse mapping from ColosseumDex species names to dex numbers
local colosseumNameToDex = nil

local function logOnce(key, fmt, ...)
  if reported[key] then return end
  reported[key] = true
  local log = V.mod and V.mod.log
  if log and log.warn then pcall(log.warn, log, fmt, ...) end
end

-- Build reverse mapping from ColosseumDex species names to dex numbers
local function buildColosseumNameMapping()
  if colosseumNameToDex then return colosseumNameToDex end

  if not ColosseumDex then
    local ok, cd = pcall(V.require, "ColosseumDex")
    if ok and cd then
      ColosseumDex = cd
    else
      return {}
    end
  end

  if not ColosseumDex or not ColosseumDex.species then
    return {}
  end

  local mapping = {}
  for dex, data in pairs(ColosseumDex.species) do
    if type(data) == "table" and data[1] then
      local speciesName = data[1]
      mapping[speciesName] = dex
      -- Also add lowercase variant for case-insensitive matching
      mapping[speciesName:lower()] = dex
    end
  end

  colosseumNameToDex = mapping
  return mapping
end

-- Resolve species name to dex number using ColosseumDex
local function resolveSpeciesNameToDex(speciesName)
  if type(speciesName) ~= "string" then return nil end

  -- Try to load ColosseumDex if not already loaded
  if not ColosseumDex then
    local ok, cd = pcall(V.require, "ColosseumDex")
    if ok and cd then
      ColosseumDex = cd
    end
  end

  -- Build mapping if not already built
  local mapping = buildColosseumNameMapping()
  if not mapping then return nil end

  -- Try exact match first
  if mapping[speciesName] then
    return mapping[speciesName]
  end

  -- Try lowercase match
  if mapping[speciesName:lower()] then
    return mapping[speciesName:lower()]
  end

  return nil
end

local function dtForFrame()
  local dt = 1 / 60
  if love and love.timer and love.timer.getDelta then
    local ok, got = pcall(love.timer.getDelta)
    if ok and type(got) == "number" and got > 0 and got < 0.25 then
      dt = got
    end
  end
  return dt
end

local function releaseSlot(slot)
  if slot and slot.model and slot.model.actor then
    pcall(slot.model.actor.release, slot.model.actor)
  end
end

local function gameObject()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or type(Game) ~= "table" then return nil end
  return Game
end

local function gameData()
  local Game = gameObject()
  return Game and Game.data or nil
end

local function cleanName(v)
  if type(v) ~= "string" then return nil end
  local s = v:upper()
  s = s:gsub("[^A-Z0-9]", "")
  return s ~= "" and s or nil
end

local function dexNumber(v)
  if type(v) == "number" then
    local n = math.floor(v)
    return n >= 1 and n <= 386 and n or nil
  elseif type(v) == "string" then
    local n = tonumber(v)
    if n then return dexNumber(n) end
  end
  return nil
end

local function speciesDex(v)
  -- Resolve English species names to dex numbers using game data
  if type(v) == "number" then
    local n = math.floor(v)
    return n >= 1 and n <= 386 and n or nil
  elseif type(v) == "string" then
    local n = tonumber(v)
    if n then return dexNumber(n) end
    
    -- Try to resolve English species name using game data
    local data = gameData()
    if data and data.pokemon then
      -- Try exact match first
      for dex, mon in pairs(data.pokemon) do
        if mon.name and mon.name:upper() == v:upper() then
          local dexNum = tonumber(dex)
          if dexNum and dexNum >= 1 and dexNum <= 386 then
            return dexNum
          end
        end
      end
    end
  end
  return nil
end

local function facingVector(facing)
  if facing == "down" then return 0, 1
  elseif facing == "up" then return 0, -1
  elseif facing == "left" then return -1, 0
  elseif facing == "right" then return 1, 0
  end
  return 0, 1  -- Default to down
end

local function colosseumEnabled()
  -- Check if Colosseum overworld models are enabled
  -- PokemonActors being available indicates Colosseum is loaded
  if not PokemonActors then
    local mod = V.mod
    PokemonActors = mod and mod.exports and mod.exports.pokemonActorsOverworld
  end
  return PokemonActors ~= nil
end

function OverworldColosseum.safeClaimWilds(state)
  if not (state and state.entities) then return end
  for _, e in ipairs(state.entities) do
    if e and e.wildsAmbientPokemon then
      tagged[e] = false
    end
  end
end

-- Load Colosseum model using PokemonActors (Colosseum system)
local function prepareOneFromCache(p, dex, dt)
  if not (p and p.entity and dex) then return false end
  if p.stadiumMon then return false end

  -- Lazy-load PokemonActors (Colosseum system) - use the same bridge as ColosceumMon.lua
  if not PokemonActors then
    local mod = V.mod
    PokemonActors = mod and mod.exports and mod.exports.pokemonActorsOverworld
    if not PokemonActors then
      if not reported["no-pokemon-actors"] then
        reported["no-pokemon-actors"] = true
        local log = V.mod and V.mod.log
        if log and log.warn then
          pcall(log.warn, log, "Colosseum: PokemonActors not available via mod.exports.pokemonActorsOverworld")
        end
      end
      return false
    end
  end

  local slot = slots[p.entity]
  if not slot then
    -- Try cache first
    local cached = modelCache[dex]
    if not cached then
      -- Use PokemonActors.acquire with Pokedex-style context (informationSurface)
      -- This leverages the already-cached models and idle animations from ColosseumBattleEnvironments
      if PokemonActors.acquire then
        local ctx = {
          apiVersion = 1,
          game = V.mod and V.mod.game,
          battle = nil,
          sides = { player = { battler = { species = dex } }, enemy = { battler = nil } },
          phase = "information",
          progress = 1,
          groundY = 0,
          services = {
            cbeStandalone = true,
            informationSurface = true,
            informationAnimation = true
          }
        }
        local okActor, actor = pcall(PokemonActors.acquire, PokemonActors, "cbe-idle-warm", dex, "normal", { context = ctx })
        
        if okActor and actor then
          -- Setup actor for overworld use
          actor.spawnScale = 1
          pcall(actor.spawn, actor, 1)
          pcall(actor.selectNativeSlot, actor, "idle")
          pcall(actor.transition, actor, "idle")
          actor.worldScale = (actor.worldScale or 1) * 0.8

          cached = { actor = actor, dex = dex }
          modelCache[dex] = cached
          slot = cached
          slots[p.entity] = slot
          p._colosseumActor = actor  -- Set actor on pose object for drawing
          p._colosseumDex = dex
          return true
        end
      end
      
      if not reported["actor-load-fail"] then
        reported["actor-load-fail"] = true
        local log = V.mod and V.mod.log
        if log and log.warn then
          pcall(log.warn, log, "Colosseum: failed to acquire PokemonActors actor for dex %d", dex)
        end
      end
      return false
    else
      slot = cached
      slots[p.entity] = slot
      p._colosseumActor = slot.actor  -- Set actor on pose object for drawing
      p._colosseumDex = slot.dex
    end
  end

  if slot and slot.actor then
    p._colosseumActor = slot.actor
    p._colosseumDex = dex
    return true
  end

  return false
end

function OverworldColosseum.tag(entity, speciesOrDex)
  if type(entity) ~= "table" then
    return false
  end
  if speciesOrDex == nil then
    tagged[entity] = nil
    if entity.id then
      taggedById[entity.id] = nil
    end
    return true
  end
  if speciesOrDex == false then
    tagged[entity] = false
    if entity.id then
      taggedById[entity.id] = false
    end
    return true
  end

  -- Log what we're trying to tag (first few times)
  if not reported["tag-input"] then
    reported["tag-input"] = {}
  end
  if not reported["tag-input"][tostring(speciesOrDex)] and #reported["tag-input"] < 10 then
    reported["tag-input"][tostring(speciesOrDex)] = true
    local log = V.mod and V.mod.log
    if log and log.info then
      pcall(log.info, log, "Colosseum: tag called with speciesOrDex='%s' (type=%s)", tostring(speciesOrDex), type(speciesOrDex))
    end
  end

  -- Handle engine species constants like SPECIES_249, SPECIES_094, etc.
  if type(speciesOrDex) == "string" then
    local match = speciesOrDex:match("^SPECIES_(%d+)$")
    if match then
      local dex = tonumber(match)
      if dex and dex >= 1 and dex <= 386 then
        tagged[entity] = dex
        -- Also store by entity ID for more reliable matching
        if entity.id then
          taggedById[entity.id] = dex
          local log = V.mod and V.mod.log
          if log and log.info then
            pcall(log.info, log, "Colosseum: Tagged entity id='%s' with dex=%d", tostring(entity.id), dex)
          end
        end
        return true
      end
    end
  end
  
  local dex = nil
  
  -- Priority 1: Check if entity.sprite has dsSpecies (this is the dex number used by the sprite system)
  if entity.sprite and entity.sprite.dsSpecies then
    dex = dexNumber(entity.sprite.dsSpecies)
    if dex then
      tagged[entity] = dex
      if entity.id then
        taggedById[entity.id] = dex
      end
      return true
    end
  end

  -- Priority 2: Check if speciesOrDex is already a dex number
  dex = dexNumber(speciesOrDex)
  if dex then
    tagged[entity] = dex
    if entity.id then
      taggedById[entity.id] = dex
    end
    return true
  end

  -- Priority 3: Check if entity has dex/id field
  dex = dexNumber(entity.dex or entity.id or entity.speciesId)
  if dex then
    tagged[entity] = dex
    if entity.id then
      taggedById[entity.id] = dex
    end
    return true
  end
  
  -- Priority 4: Extract species name and try to resolve
  local speciesName = speciesOrDex
  if type(speciesOrDex) == "table" then
    speciesName = speciesOrDex.name or speciesOrDex.id or speciesOrDex.species or speciesOrDex.dex
  end
  
  if type(speciesName) ~= "string" then
    print("Colosseum: Could not resolve species from:", tostring(speciesOrDex))
    return false
  end
  
  -- Trim whitespace from species name
  speciesName = speciesName:match("^%s*(.-)%s*$")

  -- Log the species name being resolved (first few times)
  if not reported["species-resolve"] then
    reported["species-resolve"] = {}
  end
  if not reported["species-resolve"][speciesName] and #reported["species-resolve"] < 10 then
    reported["species-resolve"][speciesName] = true
    local log = V.mod and V.mod.log
    if log and log.info then
      pcall(log.info, log, "Colosseum: Trying to resolve species name: '%s'", tostring(speciesName))
    end
  end

  -- Try to get dex from species name using ColosseumDex first
  dex = resolveSpeciesNameToDex(speciesName)
  if dex then
    tagged[entity] = dex
    if entity.id then
      taggedById[entity.id] = dex
      local log = V.mod and V.mod.log
      if log and log.info then
        pcall(log.info, log, "Colosseum: Tagged entity id='%s' with dex=%d (from species name)", tostring(entity.id), dex)
      end
    end
    return true
  end

  -- Fallback: try manual species mapping
  dex = speciesDex(speciesName)
  if dex then
    tagged[entity] = dex
    if entity.id then
      taggedById[entity.id] = dex
      local log = V.mod and V.mod.log
      if log and log.info then
        pcall(log.info, log, "Colosseum: Tagged entity id='%s' with dex=%d (from species name fallback)", tostring(entity.id), dex)
      end
    end
    return true
  end

  -- Fallback: try to get dex from entity sprite if available
  if entity.sprite and entity.sprite.dsSpecies then
    local spriteDex = dexNumber(entity.sprite.dsSpecies)
    if spriteDex then
      tagged[entity] = spriteDex
      if entity.id then
        taggedById[entity.id] = spriteDex
      end
      return true
    end
  end

  -- Fallback: try to get dex from entity species field
  if entity.species then
    local entityDex = dexNumber(entity.species)
    if entityDex then
      tagged[entity] = entityDex
      return true
    end
  end

  -- Log failure for unknown species
  if not reported["unknown-species"] then
    reported["unknown-species"] = {}
  end
  if not reported["unknown-species"][speciesName] and #reported["unknown-species"] < 5 then
    reported["unknown-species"][speciesName] = true
    local log = V.mod and V.mod.log
    if log and log.warn then
      pcall(log.warn, log, "Colosseum: Could not resolve species name: '%s' - not in mapping", tostring(speciesName))
    end
  end

  return false
end

function OverworldColosseum.untag(entity)
  if type(entity) ~= "table" then return false end
  tagged[entity] = nil
  entityDexCache[entity] = nil
  return true
end

function OverworldColosseum.getTaggedDex(entity)
  if type(entity) ~= "table" then return nil end
  local direct = tagged[entity]
  if direct then
    -- direct is now stored as a dex number
    return tonumber(direct) or nil
  end
  if direct ~= nil then return direct or nil end

  -- Try looking up by entity ID
  if entity.id and taggedById[entity.id] then
    return tonumber(taggedById[entity.id]) or nil
  end

  return entityDexCache[entity] or nil
end

function OverworldColosseum.resolveDex(entity)
  if type(entity) ~= "table" then return nil end

  local function remember(d)
    if d and type(entity) == "table" then entityDexCache[entity] = d end
    return d
  end

  -- An explicit tag() call is authoritative developer intent (Roamer.lua,
  -- follower/control_engine.lua, ambient_pokemon.lua all call ow.tag(...)
  -- directly). It must win over every heuristic below -- in particular,
  -- Roamer entities are id'd "TR_ROAM_N" and can never match any single
  -- map's id prefix, and a wandering/ambient NPC can still be an explicitly
  -- tagged Pokemon. Check ID-keyed tags first (survives entity table
  -- identity changes across pose captures), then the direct table.
  if entity.id and taggedById[entity.id] then
    local idDex = taggedById[entity.id]
    if idDex ~= false and type(idDex) == "number" then
      return remember(idDex)
    end
  end

  local direct = tagged[entity]
  if direct ~= nil then
    if direct == false then return nil end
    if type(direct) == "number" then
      return remember(direct)
    end
  end

  -- Check cache
  local cached = entityDexCache[entity]
  if cached then return cached end

  -- Use same resolution approach as OverworldStadium
  -- Check entity fields for dex/species
  local keys = {
    "stadiumDex", "pokemonDex", "pokedex", "dexNo", "dexNumber",
    "stadiumSpecies", "pokemonSpecies", "species", "dex"
  }
  for _, key in ipairs(keys) do
    local d = speciesDex(entity[key])
    if d then return remember(d) end
  end

  -- Check nested entity structures
  for _, key in ipairs({ "def", "obj", "object", "objDef", "data", "event" }) do
    local sub = entity[key]
    if type(sub) == "table" then
      for _, innerKey in ipairs(keys) do
        local d = speciesDex(sub[innerKey])
        if d then return remember(d) end
      end
    end
  end

  -- Try to resolve from entity sprite
  if entity.sprite then
    -- Check sprite dsSpecies (dex number used by sprite system)
    if entity.sprite.dsSpecies then
      local spriteDex = dexNumber(entity.sprite.dsSpecies)
      if spriteDex then return remember(spriteDex) end
    end

    -- Check sprite species
    if entity.sprite.species then
      local spriteSpecies = entity.sprite.species
      -- Handle engine species constants
      if type(spriteSpecies) == "string" then
        local match = spriteSpecies:match("^SPECIES_(%d+)$")
        if match then
          local dex = tonumber(match)
          if dex and dex >= 1 and dex <= 386 then
            return remember(dex)
          end
        end
      end
      -- Try species name resolution
      local result = speciesDex(spriteSpecies)
      if result then return remember(result) end
    end
  end

  -- Fallback to entity fields for roaming/follower Pokemon
  local species = entity._wildsFollowerSpecies
               or entity.ambientSpecies
               or (entity.pokepcMon and entity.pokepcMon.species)
  if species then
    local result = speciesDex(species)
    if result then return remember(result) end
  end

  return nil
end

function OverworldColosseum.prepare(posed)
  local enabled = colosseumEnabled()
  if not reported["prepare-check"] then
    reported["prepare-check"] = true
    local log = V.mod and V.mod.log
    if log and log.info then
      pcall(log.info, log, "Colosseum: prepare called, enabled=%s, posed count=%d", tostring(enabled), #posed)
    end
  end

  if not enabled then return true end
  frameNo = frameNo + 1
  local dt = dtForFrame()

  local preparedCount = 0
  local entityCount = 0
  local stadiumCount = 0
  local resolvedCount = 0
  local supportedCount = 0
  local dexCheckCount = 0

  local debugSample = not reported["prepare-sample"]
  if debugSample then reported["prepare-sample"] = true end
  local seenIds
  if debugSample then seenIds = {} end
  local posedEntityIds
  if debugSample then posedEntityIds = {} end

  for _, p in ipairs(posed or {}) do
    p._colosseumModel = nil
    p._colosseumActor = nil
    p._colosseumMatrix = nil
    p._colosseumDex = nil

    if p.entity then
      entityCount = entityCount + 1
      if debugSample and p.entity.id then 
        seenIds[p.entity.id] = true
        posedEntityIds[#posedEntityIds + 1] = p.entity.id
      end
      if p.stadiumMon then
        stadiumCount = stadiumCount + 1
      else
        local okDex, dex = pcall(OverworldColosseum.resolveDex, p.entity)
        if okDex and dex then
          resolvedCount = resolvedCount + 1

          -- Log first few resolved dex values
          if resolvedCount <= 3 and not reported["dex-values"] then
            reported["dex-values"] = true
            local log = V.mod and V.mod.log
            if log and log.info then
              pcall(log.info, log, "Colosseum: resolved dex value %d (type=%s)", dex, type(dex))
            end
          end

          -- Try loading cached Colosseum mesh directly
          supportedCount = supportedCount + 1
          local ok, did = pcall(prepareOneFromCache, p, dex, dt)
          if ok and did then
            preparedCount = preparedCount + 1
          end
        end
      end
    end
  end

  if debugSample then
    local log = V.mod and V.mod.log
    if log and log.info then
      pcall(log.info, log, "Colosseum: All entity IDs in posed this frame: %s",
        #posedEntityIds > 0 and table.concat(posedEntityIds, ", ") or "(none)")
      
      -- Log all tagged IDs first
      local allTagged = {}
      for id, dex in pairs(taggedById) do
        allTagged[#allTagged + 1] = id .. "=" .. tostring(dex)
      end
      pcall(log.info, log, "Colosseum: All tagged IDs in taggedById table: %s",
        #allTagged > 0 and table.concat(allTagged, ", ") or "(none)")
      
      local present, missing = {}, {}
      for id, dex in pairs(taggedById) do
        if seenIds[id] then
          present[#present + 1] = id .. "=" .. tostring(dex)
        else
          missing[#missing + 1] = id .. "=" .. tostring(dex)
        end
      end
      pcall(log.info, log, "Colosseum: tagged IDs present in posed this frame: %s",
        #present > 0 and table.concat(present, ", ") or "(none)")
      pcall(log.info, log, "Colosseum: tagged IDs NOT present in posed this frame (never reach resolveDex at all): %s",
        #missing > 0 and table.concat(missing, ", ") or "(none)")
    end
  end

  -- Log detailed stats
  if not reported["prepare-stats"] then
    reported["prepare-stats"] = true
  end
  local log = V.mod and V.mod.log
  if log and log.info then
    pcall(log.info, log, "Colosseum: detailed stats - total=%d, stadium=%d, resolved=%d, supported=%d, prepared=%d",
      entityCount, stadiumCount, resolvedCount, supportedCount, preparedCount)
  end

  return true
end

function OverworldColosseum.safePrepare(posed)
  local ok, result = pcall(OverworldColosseum.prepare, posed)
  if not ok then
    logOnce("prepare-frame", "Colosseum overworld prepare error: %s", tostring(result))
    return false
  end
  return result ~= false
end

function OverworldColosseum.safeDraw(p)
  local ok, result = pcall(OverworldColosseum.draw, p)
  if not ok then
    logOnce("draw-frame", "Colosseum overworld draw error: %s", tostring(result))
    return false
  end
  return result ~= false
end

function OverworldColosseum.safeCast(p, ShadowMap)
  -- Shadow casting for Colosseum models
  if not (p and p._colosseumActor) then return false end
  local actor = p._colosseumActor
  local vp = Voxel3D and Voxel3D.vp
  if not vp or not ShadowMap then return false end

  local x = (p.px or 0) + 8
  local z = (p.py or 0) + 8
  local y = (p.gh or 0) + (p.lift or 0)
  local renderFacing = p.facing or "down"
  local fx, fz = facingVector(renderFacing)

  local ok, result = pcall(PokemonActors.withRenderer, vp, function()
    local okMatrix, matrix = pcall(actor.matrix, actor, x, y, z, fx, fz)
    if not okMatrix or not matrix then return false end
    -- Shadow casting would go here if supported
    return true
  end, { eye = Voxel3D.eye })
  return ok and result ~= false
end

function OverworldColosseum.draw(p)
  -- Use actor-based rendering with PokemonActors
  local actor = p and p._colosseumActor
  if not actor then return false end

  -- Calculate position and orientation
  local x = (p.px or 0) + 8
  local z = (p.py or 0) + 8
  local y = (p.gh or 0) + (p.lift or 0)

  local renderFacing = p.facing or "down"
  local fx, fz = facingVector(renderFacing)

  -- Handle first-person camera rotation
  local okFirstPerson, FirstPerson = pcall(V.require, "FirstPerson")
  if okFirstPerson and FirstPerson then
    local b = FirstPerson.cardBlend()
    if b > 0 then
      local cameraYaw = FirstPerson.cardYaw(p.px or 0, p.py or 0)
      local face = type(renderFacing) == "string" and string.lower(renderFacing) or renderFacing
      local yaw = 0
      if face == "down" then yaw = cameraYaw * b
      elseif face == "up" then yaw = (cameraYaw + math.pi) * b
      elseif face == "left" then yaw = (cameraYaw + math.pi / 2) * b
      elseif face == "right" then yaw = (cameraYaw - math.pi / 2) * b
      end
      fx = math.sin(yaw)
      fz = math.cos(yaw)
    end
  end

  -- Update actor and draw
  local dt = dtForFrame()
  pcall(actor.update, actor, dt)
  pcall(actor.spawn, actor, 1)

  -- Create transformation matrix using actor's matrix method (like battle system)
  local vp = Voxel3D and Voxel3D.vp
  if not vp then return false end

  local ok, result = pcall(PokemonActors.withRenderer, vp, function()
    -- Get matrix from actor (same approach as battle system)
    local okMatrix, matrix = pcall(actor.matrix, actor, x, y, z, fx, fz)
    if not okMatrix or not matrix then
      error("colosseum overworld draw declined")
    end
    local drew = actor:draw(matrix)
    if drew == false then error("colosseum overworld draw declined") end
    return true
  end, { eye = Voxel3D.eye })
  return ok and result ~= false
end

-- VoxelScenePatch installs the pose-level hooks (safePrepare/safeDraw/safeCast).
function OverworldColosseum.install()
  -- Ensure ColosseumDex is loaded for PokemonActors
  if not V.ColosseumDex then
    local ok, CD = pcall(V.require, "ColosseumDex")
    if ok and CD then
      V.ColosseumDex = CD
    end
  end

  -- Ensure GeneratedAssets is available
  if not GeneratedAssets then
    GeneratedAssets = V.GeneratedAssets
  end

  -- Preload common species for better performance
  local commonSpecies = { 25, 63, 142, 16, 19, 32, 131, 147, 150, 151 }  -- Pikachu, Abra, Aerodactyl, Pedgey, Rattata, NidoranM, Lapras, Dratini, Mewtwo, Mew
  OverworldColosseum.preloadSpecies(commonSpecies)
  return true
end

-- Preload models for overworld use (called during initialization)
function OverworldColosseum.preloadSpecies(dexList)
  -- Ensure ColosseumDex is loaded for PokemonActors
  if not V.ColosseumDex then
    local ok, CD = pcall(V.require, "ColosseumDex")
    if ok and CD then
      V.ColosseumDex = CD
    end
  end

  -- Ensure PokemonActors is loaded
  if not PokemonActors then
    local mod = V.mod
    PokemonActors = mod and mod.exports and mod.exports.pokemonActorsOverworld
    if not PokemonActors then return 0 end
  end

  if not (PokemonActors and PokemonActors.acquire) then return 0 end

  local count = 0
  for _, dex in ipairs(dexList or {}) do
    if not modelCache[dex] then
      local ctx = { arena = { figureScale = 1.0 } }
      local okModel, actor = pcall(PokemonActors.acquire, "cbe-prewarm", dex, "normal", { context = ctx })
      if okModel and actor then
        actor.spawnScale = 1
        pcall(actor.spawn, actor, 1)
        pcall(actor.selectNativeSlot, actor, "idle")
        pcall(actor.transition, actor, "idle")
        actor.worldScale = (actor.worldScale or 1) * 0.8

        modelCache[dex] = { dex = dex, variant = "normal", actor = actor }
        count = count + 1
      end
    end
  end
  return count
end

-- VoxelScenePatch installs the pose-level hooks (safePrepare/safeDraw/safeCast).
function OverworldColosseum.install()
  -- Ensure ColosseumDex is loaded for PokemonActors
  if not V.ColosseumDex then
    local ok, CD = pcall(V.require, "ColosseumDex")
    if ok and CD then
      V.ColosseumDex = CD
    end
  end

  -- Ensure GeneratedAssets is available
  if not GeneratedAssets then
    GeneratedAssets = V.GeneratedAssets
  end

  -- Preload common species for better performance
  local commonSpecies = { 25, 63, 142, 16, 19, 32, 131, 147, 150, 151 }  -- Pikachu, Abra, Aerodactyl, Pidgey, Rattata, NidoranM, Lapras, Dratini, Mewtwo, Mew
  OverworldColosseum.preloadSpecies(commonSpecies)
  return true
end

return OverworldColosseum