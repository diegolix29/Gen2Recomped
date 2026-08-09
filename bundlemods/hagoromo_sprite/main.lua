-- Alternative configuration for larger portrait sprites
-- This replaces the player's walking sprite with a larger portrait sprite sheet
-- File naming is dynamic based on mod ID from manifest
return function(mod)
  mod.log:info("Custom sprite mod starting...")
  mod.log:info("Mod ID: %s", mod.id)
  
  -- Dynamic file naming based on mod ID
  -- Expected files: {mod_id}.png, {mod_id}_battle_sprite.png, {mod_id}_card_sprite.png
  local modId = mod.id
  local spritePath = mod.assets:path(modId .. ".png")
  local battleSpritePath = mod.assets:path(modId .. "_battle_sprite.png")
  local cardSpritePath = mod.assets:path(modId .. "_card_sprite.png")
  
  mod.log:info("Overworld sprite path: %s", spritePath or "nil")
  mod.log:info("Battle sprite path: %s", battleSpritePath or "nil")
  mod.log:info("Card sprite path: %s", cardSpritePath or "nil")
  
  -- Register the overworld sprite with custom dimensions
  -- Assuming 64x768 total (6 frames at 64x128 each) for portrait layout
  -- Adjust these values based on your actual sprite dimensions
  mod.log:info("Configuring overworld sprite with separate width/height scaling...")
  
  local ok, err = pcall(function()
    mod.content.sprites:register("SPRITE_CUSTOM", {
      image = spritePath,
      frames = 6,              -- 6 frames total
      frameWidth = 64,         -- 64 pixels wide per frame (adjust as needed)
      frameHeight = 128,       -- 128 pixels tall per frame (adjust as needed)
      scale = 0.2,            -- Width scale: 20% of original width
      heightScale = 0.15,     -- Height scale: 15% of original height
      -- No framesPerRow needed - defaults to 1 for vertical layout
      walker = true,           -- This is a walking sprite
      trueColor = true,        -- Preserve original colors
    })
  end)
  
  if not ok then
    mod.log:error("Failed to register sprite: %s", err)
    return
  end
  
  mod.log:info("Sprite registration succeeded")
  
  -- Patch the player's walking sprite
  local ok_patch, err_patch = pcall(function()
    mod.content.field:patch("playerSprites", {
      walk = "SPRITE_CUSTOM",
    })
  end)
  
  if not ok_patch then
    mod.log:error("Failed to patch playerSprites: %s", err_patch)
    return
  end
  
  mod.log:info("Player sprite patch succeeded")
  
  -- Store custom sprite paths for the player.sprite hook
  local customSprites = {
    battle = battleSpritePath,
    card = cardSpritePath,
  }
  
  -- Use the player.sprite hook to force trueColor for custom battle/card sprites
  -- This ensures they display in HD like the overworld sprite, without GB palette filters
  mod.events:on("player.sprite", function(next, path, ctx)
    -- Check if this is a custom sprite we want to replace
    local customPath = nil
    
    if ctx.side == "back" and customSprites.battle then
      local Assets = require("src.render.Assets")
      if Assets.exists(customSprites.battle) then
        customPath = customSprites.battle
        ctx.trueColor = true  -- Force HD rendering
        mod.log:debug("Using custom battle sprite with trueColor")
      end
    elseif ctx.side == "front" and customSprites.card then
      local Assets = require("src.render.Assets")
      if Assets.exists(customSprites.card) then
        customPath = customSprites.card
        ctx.trueColor = true  -- Force HD rendering
        mod.log:debug("Using custom card sprite with trueColor")
      end
    end
    
    -- Return custom path if we have one, otherwise use original
    if customPath then
      return customPath
    end
    
    return next(path, ctx)
  end)
  
  mod.log:info("Player sprite hook registered for HD battle/card rendering")
  
  -- Still patch playerPics for the paths, but the hook handles the HD rendering
  local picsToPatch = {}
  
  -- Check if battle sprite exists and is valid
  if battleSpritePath then
    local Assets = require("src.render.Assets")
    if Assets.exists(battleSpritePath) then
      picsToPatch.back = battleSpritePath
      mod.log:info("Battle sprite file found, will override with HD rendering")
    else
      mod.log:warn("Battle sprite file not found: %s", battleSpritePath)
    end
  end
  
  -- Check if card sprite exists and is valid
  if cardSpritePath then
    local Assets = require("src.render.Assets")
    if Assets.exists(cardSpritePath) then
      picsToPatch.front = cardSpritePath
      mod.log:info("Card sprite file found, will override with HD rendering")
    else
      mod.log:warn("Card sprite file not found: %s", cardSpritePath)
    end
  end
  
  -- Only patch if we have valid overrides
  if next(picsToPatch) ~= nil then
    local ok_pics, err_pics = pcall(function()
      mod.content.field:patch("playerPics", picsToPatch)
    end)
    
    if ok_pics then
      mod.log:info("Player pics patch succeeded with %d override(s) - HD rendering enabled", #picsToPatch)
    else
      mod.log:error("Failed to patch playerPics: %s", err_pics)
      mod.log:info("Battle and card sprites will use defaults")
    end
  else
    mod.log:info("No valid battle/card sprite files found, using defaults")
  end
  
  mod.log:info("Custom sprite mod loaded successfully!")
  mod.log:info("Using mod ID: %s", modId)
  mod.log:info("Expected files: %s.png, %s_battle_sprite.png, %s_card_sprite.png", modId, modId, modId)
  mod.log:info("All sprites will render in HD (trueColor) without GB palette filters")
end