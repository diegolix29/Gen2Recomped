-- Fallback test: use standard 16x16 dimensions to test if the mod system works
return function(mod)
  mod.log:info("Standard dimension test mod starting...")
  
  local spritePath = mod.assets:path("hagoromo_sprite.png")
  mod.log:info("Sprite path: %s", spritePath or "nil")
  
  -- Try with standard dimensions first
  local ok, err = pcall(function()
    mod.content.sprites:register("SPRITE_HAGOROMO", {
      image = spritePath,
      frames = 4,              -- Standard frame count
      -- No frameWidth/frameHeight specified - uses default 16x16
      walker = true,
      trueColor = true,
    })
  end)
  
  if not ok then
    mod.log:error("Failed to register sprite with standard dims: %s", err)
    return
  end
  
  mod.log:info("Sprite registration with standard dims succeeded")
  
  local ok2, err2 = pcall(function()
    mod.content.field:patch("playerSprites", {
      walk = "SPRITE_HAGOROMO",
    })
  end)
  
  if not ok2 then
    mod.log:error("Failed to patch playerSprites: %s", err2)
    return
  end
  
  mod.log:info("Standard dimension test mod loaded successfully")
end