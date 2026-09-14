-- STADIUM FOLLOWER: Replace Yellow's Pikachu follower with any Stadium Pokémon.
--
-- This module extends the gen1recomp Pikachu follower system to use 3D Stadium
-- models instead of 2D sprites. It hooks into the overworld rendering to draw
-- Stadium models for the follower NPC.
--
-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local StadiumPack = V.require("StadiumPack")
local Stadium2Pack = V.require("Stadium2Pack")
local StadiumRig = V.require("StadiumRig")
local StadiumMon = V.require("StadiumMon")
local Voxel3D = V.require("Voxel3D")

local StadiumFollower = {}

-- Cache for loaded follower rigs
local rigCache = {}

-- Cache for loaded follower sprites
local spriteCache = {}

-- Current follower species (nil = disabled, 1-151 = dex number)
local currentSpecies = nil

-- ------- Colosseum actor source (GC6E01 extraction, via PokemonActors)
--
-- A separate source from the Stadium DSM path above: PokemonActors.lua is
-- loaded through main.lua's own Colosseum runtime namespace, not through
-- this file's V.require, so it is reached as a plain field main.lua bridges
-- onto V once the Colosseum runtime has actually installed it (see
-- initializeColosseumIntegration in main.lua). It may legitimately be nil
-- -- no ROM imported, Colosseum runtime disabled, or not installed yet --
-- so every use below is nil-checked and falls through to the Stadium DSM
-- path, exactly like a missing Stadium pack already falls through to the
-- sprite fallback.
local function actorService()
  local pa = V.PokemonActors
  return pa and pa.service
end

-- Prefer a Colosseum actor over the Stadium DSM model when both are
-- available. Colosseum covers the full Gen 1-3 dex (386) against Stadium's
-- 151, and is the same model battles already use. A plain in-memory flag
-- for now -- wire a real menu row to StadiumFollower.setColosseumPreferred
-- the same way RoamerStadium3D/StadiumWilds wire their own toggles.
local colosseumPreferred = true
function StadiumFollower.setColosseumPreferred(value)
  colosseumPreferred = value ~= false
end
function StadiumFollower.colosseumPreferred()
  return colosseumPreferred
end

-- Current Colosseum actor (nil unless the follower is riding the Colosseum
-- path). currentModel/currentRig above stay nil while this is set, and vice
-- versa -- the two paths are mutually exclusive per species, same as the
-- existing sprite-fallback flag below.
local currentActor = nil

-- Facing string -> the (towardX, towardZ) unit-ish vector Actor:matrix
-- wants. This matches YAW_BY_FACING / StadiumWilds' own fx,fz exactly:
-- Actor:matrix does yaw = atan2(towardX, towardZ), which gives yaw 0 for
-- "down" (0,1), pi/2 for "right" (1,0), pi for "up" (0,-1) and -pi/2 for
-- "left" (-1,0) -- the same rotation table StadiumFollower's own 3D branch
-- below already produces by hand for the Stadium path.
local FACING_VECTOR = {
  down = { 0, 1 }, right = { 1, 0 }, up = { 0, -1 }, left = { -1, 0 },
}

-- Overworld-appropriate sizing for a Colosseum actor: see StadiumMon.
-- colosseumScaleFor's own header for why actor.worldScale as PokemonActors
-- computes it (battle-arena units) can't be used here directly.

-- ------- Persistence

-- Where the follower marker file is kept
StadiumFollower.MARKER = "stadium_follower.info"

-- Format version for the marker file
StadiumFollower.FORMAT = "SF1"

local function fs()
  return love and love.filesystem
end

local function isFile(path)
  local f = fs()
  if not (f and f.getInfo) then return false end
  local ok, info = pcall(f.getInfo, path, "file")
  return (ok and info) and true or false
end

-- Read the marker file to get the saved follower species
local function readMarker()
  local f = fs()
  if not (f and isFile(StadiumFollower.MARKER)) then return nil end
  local ok, text = pcall(f.read, StadiumFollower.MARKER)
  if not (ok and type(text) == "string") then return nil end
  local format, dexStr = text:match("^(%S+)%s+(.+)$")
  if not format or format ~= StadiumFollower.FORMAT then return nil end
  local dex = tonumber(dexStr)
  return dex and (dex > 0 and dex <= 386) and dex or nil
end

-- Write the marker file with the current follower species
local function writeMarker(dex)
  local f = fs()
  if not (f and f.write) then return false end
  local content = StadiumFollower.FORMAT .. " " .. (dex or 0)
  local ok, err = pcall(f.write, StadiumFollower.MARKER, content)
  return ok, err
end

-- Current rig and model
local currentRig = nil
local currentModel = nil
local currentSprite = nil
local usingSpriteFallback = false

-- Animation state
local animTime = 0
local currentAnim = 1  -- 1 = idle

-- ------- Configuration

-- Scale for the follower model (smaller than player)
local FOLLOWER_SCALE = 0.9  -- 0.3 * 3 = 0.9 (3x larger)

-- Load a sprite as fallback for follower
local function loadSpriteFallback(dex)
  if not dex then return false, "no dex number" end
  
  print("StadiumFollower.loadSpriteFallback: Attempting to load sprite for dex", dex)
  
  -- Check sprite cache first
  if spriteCache[dex] then
    currentSprite = spriteCache[dex]
    currentSpecies = dex
    usingSpriteFallback = true
    print("StadiumFollower.loadSpriteFallback: Loaded sprite from cache")
    return true
  end
  
  -- Try to get Pokemon data to find the sprite path
  local ok, game = pcall(function() return V.require("src.core.Game") end)
  if not ok or not game then
    print("StadiumFollower.loadSpriteFallback: Could not access Game module")
    return false, "could not access game data"
  end
  
  local currentGame = game.get and game:get()
  if not currentGame then
    print("StadiumFollower.loadSpriteFallback: Could not get current game instance")
    return false, "could not get game instance"
  end
  
  local data = currentGame.data
  if not data then
    print("StadiumFollower.loadSpriteFallback: No game data available")
    return false, "no game data"
  end
  
  -- Try to get species name from dex number
  local species = nil
  if data.pokemon then
    for speciesId, def in pairs(data.pokemon) do
      if def and def.dex == dex then
        species = speciesId
        break
      end
    end
  end
  
  if not species then
    print("StadiumFollower.loadSpriteFallback: Could not find species for dex", dex)
    return false, "could not find species"
  end
  
  -- Try to get the Pokemon definition to find the sprite path directly
  local pokemonDef = data.pokemon and data.pokemon[species]
  if not pokemonDef then
    print("StadiumFollower.loadSpriteFallback: Could not find Pokemon definition for", species)
    return false, "could not find pokemon definition"
  end
  
  -- Try to get the front sprite path from the Pokemon definition
  local spritePath = pokemonDef.spriteFront
  if not spritePath or spritePath == "" then
    print("StadiumFollower.loadSpriteFallback: No spriteFront defined for", species)
    return false, "no sprite front defined"
  end
  
  -- Try to load the image
  local okImage, Assets = pcall(function() return V.require("src.render.Assets") end)
  if not okImage or not Assets then
    print("StadiumFollower.loadSpriteFallback: Could not access Assets module")
    return false, "could not access assets"
  end
  
  local image = Assets.image(spritePath)
  if not image then
    print("StadiumFollower.loadSpriteFallback: Could not load sprite image from", spritePath)
    return false, "could not load sprite image"
  end
  
  -- Cache the sprite
  spriteCache[dex] = image
  currentSprite = image
  currentSpecies = dex
  usingSpriteFallback = true
  
  print("StadiumFollower.loadSpriteFallback: Successfully loaded sprite fallback from", spritePath)
  return true
end

-- ------- Species Management

-- Set the follower species by dex number (1-386; 152-386 only actually
-- resolve to a 3D model through the Colosseum path below -- Stadium DSM
-- tops out at 151 and falls through to the sprite card same as before)
function StadiumFollower.setSpecies(dex)
  if dex == currentSpecies then return true end
  
  -- Clear current rig, actor and sprite
  if currentRig then
    currentRig:release()
    currentRig = nil
  end
  if currentActor then
    pcall(function() currentActor:release() end)
    currentActor = nil
  end
  currentModel = nil
  currentSprite = nil
  currentSpecies = nil
  usingSpriteFallback = false
  
  if not dex or dex < 1 or dex > 386 then
    -- Save the disabled state
    writeMarker(nil)
    return true  -- Disabled
  end

  -- Try the Colosseum actor first. Cheap availability check before
  -- acquiring: a cold species triggers on-demand extraction inside
  -- acquire(), which is fine to pay once here but not worth attempting when
  -- the Colosseum runtime simply isn't installed for this session.
  if colosseumPreferred then
    local api = actorService()
    if api and api.available("follower", dex) then
      local ok, actor = pcall(api.acquire, "follower", dex, "normal", {})
      if ok and actor then
        actor.worldScale = StadiumMon.colosseumScaleFor(actor)
        pcall(actor.spawn, actor, 1)
        pcall(actor.idle, actor)
        currentActor = actor
        currentSpecies = dex
        usingSpriteFallback = false
        writeMarker(dex)
        print("StadiumFollower: Loaded Colosseum follower dex", dex)
        return true
      end
      print("StadiumFollower: Colosseum actor unavailable for dex", dex,
        ", falling back:", tostring(not ok and actor or "acquire returned nil"))
    end
  end
  
  -- Check 3D model cache first
  if rigCache[dex] then
    currentRig = rigCache[dex]
    currentModel = currentRig.model
    currentSpecies = dex
    usingSpriteFallback = false
    -- Save the enabled state
    writeMarker(dex)
    return true
  end
  
  -- Check sprite cache first
  if spriteCache[dex] then
    currentSprite = spriteCache[dex]
    currentSpecies = dex
    usingSpriteFallback = true
    -- Save the enabled state
    writeMarker(dex)
    return true
  end
  
  -- Try to load the 3D Stadium model first
  local model = StadiumPack.load(dex, false)
  
  if model and not model.staticPose then
    -- Create the rig
    local rig = StadiumRig.new(model)
    if rig then
      -- Cache and set current
      rigCache[dex] = rig
      currentRig = rig
      currentModel = model
      currentSpecies = dex
      usingSpriteFallback = false
      
      -- Save the enabled state
      writeMarker(dex)
      
      -- Start idle animation
      rig:pose(1, 0, true)
      rig:skin(0)
      
      print("StadiumFollower: Loaded 3D follower dex", dex)
      return true
    end
  end
  
  -- If 3D model failed, try sprite fallback
  print("StadiumFollower: 3D model unavailable for dex", dex, ", trying sprite fallback")
  local spriteOk, spriteErr = loadSpriteFallback(dex)
  if spriteOk then
    -- Save the enabled state
    writeMarker(dex)
    print("StadiumFollower: Loaded sprite fallback for dex", dex)
    return true
  else
    print("StadiumFollower: Sprite fallback also failed:", spriteErr)
    return false, "could not load 3D model or sprite: " .. tostring(spriteErr)
  end
end

-- Get the current follower species
function StadiumFollower.getSpecies()
  return currentSpecies
end

-- Read the saved follower species from marker file without loading the model
function StadiumFollower.readSaved()
  return readMarker()
end

-- Load the saved follower species from marker file and set it (which loads the model)
function StadiumFollower.loadSaved()
  local saved = readMarker()
  if saved and saved > 0 then
    print("StadiumFollower: Loading saved follower dex", saved)
    -- setSpecies now handles both 3D model and sprite fallback internally
    local ok = StadiumFollower.setSpecies(saved)
    if ok then
      print("StadiumFollower: Successfully loaded saved follower")
    else
      print("StadiumFollower: Failed to load saved follower")
    end
  else
    print("StadiumFollower: No saved follower or disabled")
  end
end

-- Try to load deferred follower species (called when Stadium models become available)
function StadiumFollower.tryDeferredLoad()
  if StadiumFollower.deferredLoad then
    print("StadiumFollower: Loading deferred follower dex", StadiumFollower.deferredLoad)
    local ok = StadiumFollower.setSpecies(StadiumFollower.deferredLoad)
    if ok then
      print("StadiumFollower: Successfully loaded deferred follower")
      StadiumFollower.deferredLoad = nil
    else
      print("StadiumFollower: Failed to load deferred follower")
    end
  end
end

-- Check for deferred load and try to load if models are now available
function StadiumFollower.checkDeferred()
  if StadiumFollower.deferredLoad then
    local okInstall, StadiumInstall = pcall(V.require, "StadiumInstall")
    if okInstall and StadiumInstall and StadiumInstall.available() then
      StadiumFollower.tryDeferredLoad()
    end
  end
end

-- ------- Rendering

-- Update animation state
function StadiumFollower.update(dt)
  if currentActor then
    pcall(currentActor.update, currentActor, dt)
    return
  end
  if not currentRig then return end
  
  animTime = animTime + dt
  currentRig:pose(currentAnim, animTime * 30, true)  -- 30 FPS
  currentRig:anchor(0.75, dt)
  currentRig:textures(nil)
end

-- Draw the follower at the given position
-- x, y: world coordinates (pixel position)
-- facing: direction the follower is facing ("up", "down", "left", "right")
function StadiumFollower.draw(x, y, facing)
  print("[StadiumFollower.draw] Called with x:", x, "y:", y, "facing:", facing, "currentRig:", currentRig ~= nil, "currentModel:", currentModel ~= nil, "currentSprite:", currentSprite ~= nil, "usingSpriteFallback:", usingSpriteFallback)
  
  -- Handle sprite fallback
  if usingSpriteFallback and currentSprite then
    return StadiumFollower.drawSprite(x, y, facing)
  end

  -- Handle the Colosseum actor. Facing/free-roam yaw math mirrors the
  -- Stadium branch below exactly (same FirstPerson.cardYaw blend), just
  -- expressed as a (towardX, towardZ) vector at the end instead of a bare
  -- yaw, because Actor:matrix wants the direction and derives its own yaw
  -- from it (see FACING_VECTOR's comment for why that lines up).
  if currentActor then
    local FirstPerson = V.require("FirstPerson")
    local b = FirstPerson.cardBlend()
    local fx, fz
    if b > 0 then
      local cameraYaw = FirstPerson.cardYaw(x, y)
      local yaw = 0
      if facing == "down" then yaw = cameraYaw * b
      elseif facing == "up" then yaw = (cameraYaw + math.pi) * b
      elseif facing == "left" then yaw = (cameraYaw + math.pi / 2) * b
      elseif facing == "right" then yaw = (cameraYaw - math.pi / 2) * b end
      fx, fz = math.sin(yaw), math.cos(yaw)
    else
      local v = FACING_VECTOR[facing] or FACING_VECTOR.down
      fx, fz = v[1], v[2]
    end
    -- groundY 0, matching the Stadium branch below (Mat4.translate(x, 0, y))
    -- -- StadiumFollower has never accounted for sloped/ledge ground height
    -- here (unlike StadiumWilds/PlayerModel, which read entity.gh), and this
    -- keeps the Colosseum path visually consistent with that existing
    -- behaviour rather than introducing a new mismatch between the two.
    local ok, matrix = pcall(currentActor.matrix, currentActor, x, 0, y, fx, fz)
    if not ok or not matrix then return false end
    local api = actorService()
    if not api then return false end
    local drewOk, drew = pcall(api.withRenderer, Voxel3D.vp, function()
      return currentActor:draw(matrix)
    end, { eye = Voxel3D.eye })
    return drewOk and drew == true
  end
  
  -- Handle 3D model
  if not currentRig or not currentModel then return false end

  -- Calculate the model matrix
  local m = Mat4.translate(x, 0, y)

  -- Check if we're in free-roam mode (1st or 3rd person)
  local FirstPerson = V.require("FirstPerson")
  local b = FirstPerson.cardBlend()

  -- Apply rotation based on facing direction
  local yaw = 0

  if b > 0 then
    -- In free-roam mode, use camera-relative rotation like the player model
    local cameraYaw = FirstPerson.cardYaw(x, y)

    if facing == "down" then
      -- Moving backwards: face the camera
      yaw = cameraYaw * b

    elseif facing == "up" then
      -- Moving forward: face away from the camera
      yaw = (cameraYaw + math.pi) * b

    elseif facing == "left" then
      -- Moving left: turn 90 degrees left
      yaw = (cameraYaw + math.pi / 2) * b

    elseif facing == "right" then
      -- Moving right: turn 90 degrees right
      yaw = (cameraYaw - math.pi / 2) * b
    end

  else
    -- In other modes, rotate based on movement direction
    if facing == "right" then
      yaw = math.pi / 2
    elseif facing == "up" then
      yaw = math.pi
    elseif facing == "left" then
      yaw = -math.pi / 2
    end
  end

  if yaw ~= 0 then
    m = Mat4.mul(m, Mat4.rotateY(yaw))
  end
  
  -- Apply scaling
  local model = currentModel
  local scale = StadiumMon.scaleFor(model) * FOLLOWER_SCALE
  m = Mat4.mul(m, Mat4.scale(scale, scale, scale))
  
  -- Stand the model on its own lowest point and give back HOVER_CAP of any
  -- authored hover, same as StadiumWilds/PlayerModel/battle Pokemon --
  -- otherwise a hovering or origin-centred species renders sunk into the
  -- ground instead of standing on it.
  local lift = StadiumMon.liftFor(model)
  if lift ~= 0 then
    m = Mat4.mul(m, Mat4.translate(0, -lift, 0))
  end
  
  -- Skin and draw
  currentRig:skin(yaw)
  currentRig:draw(m)
  
  return true
end

-- Draw the sprite fallback at the given position
function StadiumFollower.drawSprite(x, y, facing)
  if not currentSprite then
    return false
  end
  
  print("[StadiumFollower.drawSprite] Drawing sprite at x:", x, "y:", y, "facing:", facing)
  
  -- Try to use love.graphics for sprite rendering
  local lg = love and love.graphics
  if not lg then
    print("[StadiumFollower.drawSprite] love.graphics not available")
    return false
  end
  
  lg.push()
  lg.translate(x, y)
  lg.scale(FOLLOWER_SCALE, FOLLOWER_SCALE)
  
  -- Draw sprite centered
  local sw, sh = currentSprite:getDimensions()
  lg.draw(currentSprite, -sw/2, -sh/2)
  
  lg.pop()
  
  return true
end

-- ------- Cleanup

-- Clear all cached rigs
function StadiumFollower.clearCache()
  for dex, rig in pairs(rigCache) do
    if rig then
      pcall(function() rig:release() end)
    end
  end
  rigCache = {}
  
  -- Clear sprite cache
  spriteCache = {}

  if currentActor then
    pcall(function() currentActor:release() end)
  end
  currentActor = nil
  currentRig = nil
  currentModel = nil
  currentSprite = nil
  currentSpecies = nil
  usingSpriteFallback = false
  animTime = 0
end

-- Check if a follower is currently loaded
function StadiumFollower.loaded()
  local result = currentActor ~= nil or (currentRig ~= nil and currentModel ~= nil) or (currentSprite ~= nil)
  print("[StadiumFollower.loaded] Returning:", result, "currentActor:", currentActor ~= nil, "currentRig:", currentRig ~= nil, "currentModel:", currentModel ~= nil, "currentSprite:", currentSprite ~= nil, "currentSpecies:", currentSpecies, "usingSpriteFallback:", usingSpriteFallback)
  return result
end

-- Check if the follower is using sprite fallback
function StadiumFollower.isUsingSpriteFallback()
  return usingSpriteFallback
end

return StadiumFollower