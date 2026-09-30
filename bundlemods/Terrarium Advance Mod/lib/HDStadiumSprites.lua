-- HD Sprite provider for Terrarium - KIM fallback integration
--
-- This module provides HD 2D sprites as a fallback when Stadium/Colosseum 3D models
-- are unavailable, particularly for Gen 4 Pokemon (387-493). It integrates with
-- Kanto in Motion's cache system via mod.find("animated_menu_pokemon").
--
-- Integration points:
--   * National Dex cap: 1-493 (Platinum coverage)
--   * Asset loading: Uses KIM's mod._kimAssetProvider when available
--   * Sprite lookup: front/back normal/shiny variants
--   * Animation: Supports frame-based animation from KIM atlases
--   * Registration: Registers on CurrentSpriteModels.battleSprites capability

local V = ...

local HDStadiumSprites = {}

-- National Dex cap for Gen 4 (Platinum ends at 493)
local NATIONAL_DEX_MAX = 493

-- Cache KIM mod handle and asset provider
local kimMod = nil
local kimAssetProvider = nil
local kimSpriteData = nil
local kimNationalData = nil

-- Gen 4 asset manager for Pokemon 387-493
local gen4AssetManager = nil

-- Local caches
local imageCache = {}
local frameCache = {}
local renderCache = {}
local reported = {}

-- Load KIM mod and its assets
local function loadKimAssets()
  if kimMod then return kimMod, kimAssetProvider end
  
  -- Try to find KIM mod
  local ok, handle = pcall(V.mod.find, "animated_menu_pokemon")
  if not ok or not handle then
    if not reported["kim-not-found"] then
      reported["kim-not-found"] = true
      local log = V.mod and V.mod.log
      if log and log.info then
        pcall(log.info, log, "HDStadiumSprites: KIM mod not found, trying Gen 4 asset manager")
      end
    end
    return nil, nil
  end
  
  kimMod = handle
  
  -- Get KIM's asset provider
  if handle._kimAssetProvider then
    kimAssetProvider = handle._kimAssetProvider
  else
    if not reported["kim-no-provider"] then
      reported["kim-no-provider"] = true
      local log = V.mod and V.mod.log
      if log and log.warn then
        pcall(log.warn, log, "HDStadiumSprites: KIM found but no asset provider available")
      end
    end
  end
  
  -- Load KIM's sprite data
  if handle._kantoInMotionSpriteData then
    kimSpriteData = handle._kantoInMotionSpriteData
  end
  
  if handle._kantoInMotionNationalData then
    kimNationalData = handle._kantoInMotionNationalData
  end
  
  return kimMod, kimAssetProvider
end

-- Load Gen 4 asset manager for Pokemon 387-493
local function loadGen4Assets()
  if gen4AssetManager then return gen4AssetManager end
  
  -- Try to load Gen4AssetManager
  local ok, manager = pcall(V.require, "Gen4AssetManager")
  if not ok or not manager then
    if not reported["gen4-not-found"] then
      reported["gen4-not-found"] = true
      local log = V.mod and V.mod.log
      if log and log.info then
        pcall(log.info, log, "HDStadiumSprites: Gen4AssetManager not available")
      end
    end
    return nil
  end
  
  gen4AssetManager = manager
  return gen4AssetManager
end

-- Helper function to format dex number as 3-digit string
local function formatDex(dex)
  return string.format("%03d", dex)
end

-- Check if KIM has sprite for specific dex and variant
local function kimSpriteExists(dex, side, color)
  if not kimAssetProvider then return false end
  
  local side = side or "front"
  local color = color or "normal"
  local dexStr = formatDex(dex)
  
  -- Construct KIM asset path
  local path = string.format("assets/battle/hd-pokemon/%s/%s/%s.png", side, color, dexStr)
  
  -- Check if asset exists
  local ok, exists = pcall(kimAssetProvider.exists, kimAssetProvider, path)
  return ok and exists == true
end

-- Load image from KIM cache or Gen4AssetManager
local function loadKimImage(path, dex)
  -- Check cache first
  if imageCache[path] then
    return imageCache[path]
  end
  
  -- For Gen 4 Pokemon, try Gen4AssetManager first
  if dex and dex >= 387 then
    loadGen4Assets()
    if gen4AssetManager then
      local side = path:match("battle/hd%-pokemon/([^/]+)/")
      local color = path:match("battle/hd%-pokemon/[^/]+/([^/]+)/")
      local image = gen4AssetManager:image(dex, side, color)
      if image then
        imageCache[path] = image
        return image
      end
    end
  end
  
  -- Fall back to KIM for 1-386
  if not kimAssetProvider then return nil
  
  -- Check cache first
  if imageCache[path] then
    return imageCache[path]
  end
  
  -- Check if asset exists
  local ok, exists = pcall(kimAssetProvider.exists, kimAssetProvider, path)
  if not ok or not exists then
    imageCache[path] = false
    return nil
  end
  
  -- Load image
  local okImg, image = pcall(kimAssetProvider.image, kimAssetProvider, path)
  if not ok or not image then
    imageCache[path] = false
    return nil
  end
  
  -- Set nearest filtering for pixel art
  if image.setFilter then
    pcall(image.setFilter, image, "nearest", "nearest")
  end
  
  imageCache[path] = image
  return image
end

-- Generate default sprite metadata for KIM sprites
-- Since KIM cache may not have metadata for Gen 4, we generate reasonable defaults
local function generateKimSpriteMetadata(dex, side, color)
  local dexStr = formatDex(dex)
  local path = string.format("assets/battle/hd-pokemon/%s/%s/%s.png", side, color, dexStr)
  
  -- Try to load image to get dimensions
  local image = loadKimImage(path, dex)
  if not image then return nil end
  
  local width, height = image:getDimensions()
  
  -- Generate default animation metadata
  -- Most Pokemon sprites are around 64x64 to 96x96 with simple 2-4 frame animations
  local frameWidth = math.min(width, 96)
  local frameHeight = math.min(height, 96)
  local columns = math.max(1, math.floor(width / frameWidth))
  local frames = math.max(1, math.floor((width / frameWidth) * (height / frameHeight)))
  
  -- Cap frames to reasonable number
  frames = math.min(frames, 8)
  
  -- Default durations (50ms per frame for smooth animation)
  local durations = {}
  for i = 1, frames do
    durations[i] = 50
  end
  
  return {
    image = path,
    width = frameWidth,
    height = frameHeight,
    columns = columns,
    frames = frames,
    durations = durations,
    displayScale = 1.0
  }
end

-- Resolve sprite metadata for a Pokemon
local function resolveSpriteMetadata(dex, side, color)
  dex = tonumber(dex)
  if not dex or dex < 1 or dex > NATIONAL_DEX_MAX then return nil end
  
  side = side or "front"
  color = color or "normal"
  
  -- Ensure KIM is loaded for 1-386
  if dex < 387 then
    loadKimAssets()
    
    -- Try to get metadata from KIM's data if available
    if kimSpriteData then
      local dexStr = formatDex(dex)
      local entry = kimSpriteData[dexStr]
      if entry and entry[side] and entry[side][color] then
        return entry[side][color]
      end
    end
    
    -- Fall back to generated metadata
    if kimSpriteExists(dex, side, color) then
      return generateKimSpriteMetadata(dex, side, color)
    end
  else
    -- For Gen 4 (387-493), use Gen4AssetManager
    loadGen4Assets()
    
    if gen4AssetManager and gen4AssetManager:exists(dex, side, color) then
      return generateKimSpriteMetadata(dex, side, color)
    end
  end
  
  return nil
end

-- Render a single frame from sprite sheet
local function renderFrame(metadata, frameNum, dex)
  if not metadata or not metadata.image then return nil end
  
  local image = loadKimImage(metadata.image, dex)
  if not image then return nil end
  
  local frameWidth = metadata.width or 64
  local frameHeight = metadata.height or 64
  local columns = metadata.columns or 1
  local totalFrames = metadata.frames or 1
  
  frameNum = math.max(1, math.min(frameNum, totalFrames))
  
  -- Calculate source coordinates
  local frameIndex = frameNum - 1
  local col = frameIndex % columns
  local row = math.floor(frameIndex / columns)
  local sx = col * frameWidth
  local sy = row * frameHeight
  
  -- Create canvas for this frame
  if not love or not love.graphics or not love.graphics.newCanvas then
    return nil
  end
  
  local canvas = love.graphics.newCanvas(frameWidth, frameHeight)
  if canvas.setFilter then
    pcall(canvas.setFilter, canvas, "nearest", "nearest")
  end
  
  -- Create quad for source rectangle
  local quad = love.graphics.newQuad(sx, sy, frameWidth, frameHeight, image:getDimensions())
  
  -- Render frame to canvas
  local previousCanvas = love.graphics.getCanvas and love.graphics.getCanvas() or nil
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(image, quad, 0, 0)
  if previousCanvas then love.graphics.setCanvas(previousCanvas) else love.graphics.setCanvas() end
  love.graphics.pop()
  
  return canvas
end

-- Get current animation frame
local function getCurrentFrame(metadata)
  if not metadata or not metadata.frames or metadata.frames <= 1 then
    return 1
  end
  
  local frames = metadata.frames
  local durations = metadata.durations or {}
  local totalDuration = 0
  
  for i = 1, frames do
    totalDuration = totalDuration + (durations[i] or 50)
  end
  
  if totalDuration <= 0 then return 1 end
  
  -- Get current time
  local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
  local time = (now * 1000) % totalDuration
  
  -- Find current frame
  local accumulated = 0
  for i = 1, frames do
    accumulated = accumulated + (durations[i] or 50)
    if time < accumulated then return i end
  end
  
  return frames
end

-- Main sprite resolution function for battleSprites capability
function HDStadiumSprites.resolve(context, side, battler)
  if not context or not battler then return nil end
  
  local mon = battler.mon
  if not mon then return nil end
  
  -- Get dex number
  local dex = mon.dex or mon.speciesIndex
  if not dex then
    -- Try to resolve from species name
    local game = context.game or (context.battle and context.battle.game)
    if game and game.data and game.data.pokemon then
      local def = game.data.pokemon[mon.species]
      dex = def and (def.dex or def.index or def.number)
    end
  end
  
  dex = tonumber(dex)
  if not dex or dex < 1 or dex > NATIONAL_DEX_MAX then return nil end
  
  -- Determine side and color
  local viewSide = (side == "enemy") and "front" or "back"
  local color = "normal"
  
  -- Check for shiny
  if mon.shiny or (mon.dvs and mon.dvs.attack == 2 or mon.dvs.attack == 3 or 
                   mon.dvs.attack == 6 or mon.dvs.attack == 7 or mon.dvs.attack == 10 or
                   mon.dvs.attack == 11 or mon.dvs.attack == 14 or mon.dvs.attack == 15) then
    if mon.dvs and mon.dvs.defense == 10 and mon.dvs.speed == 10 and mon.dvs.special == 10 then
      color = "shiny"
    elseif mon.shiny then
      color = "shiny"
    end
  end
  
  -- Resolve sprite metadata
  local metadata = resolveSpriteMetadata(dex, viewSide, color)
  if not metadata then return nil end
  
  -- Render current frame
  local frameNum = getCurrentFrame(metadata)
  local canvas = renderFrame(metadata, frameNum, dex)
  if not canvas then return nil end
  
  -- Return sprite data
  return {
    image = canvas,
    width = metadata.width,
    height = metadata.height,
    source = "hdstadiumsprites",
    dex = dex,
    side = viewSide,
    color = color,
    frame = frameNum
  }
end

-- Check if HD sprite is available for a Pokemon
function HDStadiumSprites.available(dex, side, color)
  dex = tonumber(dex)
  if not dex or dex < 1 or dex > NATIONAL_DEX_MAX then return false end
  
  loadKimAssets()
  return kimSpriteExists(dex, side or "front", color or "normal")
end

-- Initialize the provider
function HDStadiumSprites.install()
  -- Pre-load KIM assets
  loadKimAssets()
  
  if kimMod then
    local log = V.mod and V.mod.log
    if log and log.info then
      pcall(log.info, log, "HDStadiumSprites: Installed with KIM integration, National Dex cap: %d", NATIONAL_DEX_MAX)
    end
  else
    local log = V.mod and V.mod.log
    if log and log.warn then
      pcall(log.warn, log, "HDStadiumSprites: Installed but KIM not available - HD sprites disabled")
    end
  end
  
  return true
end

-- Export battleSprites capability
HDStadiumSprites.battleSprites = {
  version = 1,
  resolve = HDStadiumSprites.resolve,
  priority = 10, -- Lower priority than 3D models, higher than vanilla
}

return HDStadiumSprites