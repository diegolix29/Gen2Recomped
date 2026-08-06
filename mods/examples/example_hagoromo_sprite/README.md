# Hagoromo Sprite Example

This example mod demonstrates how to use larger custom sprites with custom frame dimensions in gen1recomp.

## Features

- Replaces the player's walking sprite with a larger custom sprite
- Shows how to configure custom frame dimensions (width, height, layout)
- Demonstrates the new sprite schema fields for larger sprites

## New Sprite Schema Fields

The following new fields have been added to the sprite schema to support larger sprites:

- `frameWidth`: Width of each frame in pixels (defaults to 16)
- `frameHeight`: Height of each frame in pixels (defaults to 16)  
- `framesPerRow`: Number of frames per row in the sprite sheet (defaults to 1 for vertical stacking)

## Configuration

Edit `main.lua` to adjust the sprite configuration based on your sprite sheet:

```lua
mod.content.sprites:register("SPRITE_HAGOROMO", {
  image = mod.assets:path("hagoromo_sprite.png"),
  frames = 4,              -- Total number of frames
  frameWidth = 32,         -- Width of each frame
  frameHeight = 48,        -- Height of each frame
  framesPerRow = 2,        -- Frames per row (2 = 2x2 grid layout)
  walker = true,           -- Enable walking animation
  trueColor = true,        -- Preserve original colors
})
```

## Sprite Sheet Layout

The system now supports two layout modes:

1. **Vertical Stacking (default)**: Frames are stacked vertically when `framesPerRow = 1`
2. **Grid Layout**: Frames are arranged in a grid when `framesPerRow > 1`

For a 2x2 grid with 4 frames:
- Frame 0: (0, 0)
- Frame 1: (frameWidth, 0) 
- Frame 2: (0, frameHeight)
- Frame 3: (frameWidth, frameHeight)

## Installation

1. Place this mod in your `mods/` directory
2. Enable it in the mod menu
3. The player sprite will be replaced with the custom larger sprite

## Notes

- Larger sprites are automatically centered on the tile
- The system calculates proper positioning offsets based on frame size
- Palette effects and rendering modes work with larger sprites
- Walking animation timing is preserved regardless of sprite size