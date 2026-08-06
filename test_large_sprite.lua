-- Simple test to verify larger sprite support
-- Run with: love test_large_sprite.lua (if love is in PATH)

local SpriteRenderer = require("src.render.SpriteRenderer")

print("Testing larger sprite support...")

-- Test 1: Default values (backwards compatibility)
print("\nTest 1: Default values (backwards compatibility)")
local defaultSprite = SpriteRenderer.new({
  image = "assets/generated/sprites/red.png",
  frames = 1
})
assert(defaultSprite.frameWidth == 16, "Default frameWidth should be 16")
assert(defaultSprite.frameHeight == 16, "Default frameHeight should be 16")
assert(defaultSprite.framesPerRow == 1, "Default framesPerRow should be 1")
print("✓ Default values work correctly")

-- Test 2: Custom frame dimensions
print("\nTest 2: Custom frame dimensions")
local largerSpriteDef = {
  image = "assets/generated/sprites/red.png",
  frames = 4,
  frameWidth = 32,
  frameHeight = 48,
  framesPerRow = 2,
  walker = true,
}

local largerSprite = SpriteRenderer.new(largerSpriteDef)
assert(largerSprite.frameWidth == 32, "Custom frameWidth should be 32")
assert(largerSprite.frameHeight == 48, "Custom frameHeight should be 48")
assert(largerSprite.framesPerRow == 2, "Custom framesPerRow should be 2")
assert(#largerSprite.frames == 4, "Should create 4 frames")
print("✓ Custom frame dimensions work correctly")

-- Test 3: Frame quad calculation
print("\nTest 3: Frame quad calculation")
assert(largerSprite.frames[0] ~= nil, "Frame 0 quad should exist")
assert(largerSprite.frames[1] ~= nil, "Frame 1 quad should exist")
assert(largerSprite.frames[2] ~= nil, "Frame 2 quad should exist")
assert(largerSprite.frames[3] ~= nil, "Frame 3 quad should exist")
print("✓ Frame quads calculated correctly")

print("\n✅ All tests passed!")
print("Larger sprite support is working correctly.")