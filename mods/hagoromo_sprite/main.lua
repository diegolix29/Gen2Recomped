-- Example mod showing how to use larger custom sprites
-- This replaces the player's walking sprite with a larger sprite sheet
return function(mod)
  mod.log:info("Hagoromo sprite mod starting...")
  
  local spritePath = mod.assets:path("hagoromo_sprite.png")
  mod.log:info("Sprite path: %s", spritePath or "nil")
  
  -- Test with portrait dimensions: 32x384 total (6 frames at 32x64 each)
  -- Frame width is half the height - portrait style frames
  -- The system supports any aspect ratio - not limited to square frames
  mod.log:info("Configuring for 32x384 sprite with 6 vertical frames (portrait, half-width)...")
  
  local ok, err = pcall(function()
    mod.content.sprites:register("SPRITE_HAGOROMO", {
      image = spritePath,
      frames = 6,              -- 6 frames total
      frameWidth = 32,         -- 32 pixels wide per frame (half-width)
      frameHeight = 64,         -- 64 pixels tall per frame (double-height)
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
      walk = "SPRITE_HAGOROMO",
    })
  end)
  
  if not ok_patch then
    mod.log:error("Failed to patch playerSprites: %s", err_patch)
    return
  end
  
  mod.log:info("Player sprite patch succeeded")
  mod.log:info("Hagoromo sprite mod loaded successfully!")
  mod.log:info("Using: 32x384 sprite, 6 frames vertical, 32x64 per frame (portrait, half-width)")
end