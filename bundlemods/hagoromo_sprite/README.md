# Custom Player Sprite Mod

This example mod demonstrates how to use larger custom sprites with custom frame dimensions, separate width/height scaling, and full-color battle/trainer card sprites in gen1recomp.

## Features

- Replaces the player's walking sprite with a larger custom sprite
- Shows how to configure custom frame dimensions (width, height, layout)
- Demonstrates separate width/height scaling for precise proportion control
- Overrides battle sprites and trainer card with full-color versions
- Dynamic file naming based on mod ID from manifest

## File Naming Convention

The mod uses the `id` field from `manifest.json` for dynamic file naming:

- **Overworld sprite**: `{mod_id}.png`
- **Battle sprite**: `{mod_id}_battle.png`  
- **Trainer card sprite**: `{mod_id}_card.png`

**Example**: If your manifest has `"id": "my_character"`, the files should be:
- `my_character.png` (overworld sprite)
- `my_character_battle.png` (battle back sprite)
- `my_character_card.png` (trainer card sprite)

## New Sprite Schema Fields

The following new fields have been added to the sprite schema to support larger sprites:

- `frameWidth`: Width of each frame in pixels (defaults to 16)
- `frameHeight`: Height of each frame in pixels (defaults to 16)  
- `framesPerRow`: Number of frames per row in the sprite sheet (defaults to 1 for vertical stacking)
- `scale`: Overall width scale multiplier (defaults to 1.0)
- `heightScale`: Independent height scale multiplier (defaults to scale value)

## Configuration

Edit `main_large_portrait.lua` to adjust the sprite configuration:

```lua
mod.content.sprites:register("SPRITE_" .. mod.id:upper(), {
  image = mod.assets:path(mod.id .. ".png"),
  frames = 6,              -- Total number of frames
  frameWidth = 64,         -- Width of each frame
  frameHeight = 128,       -- Height of each frame
  scale = 0.5,            -- Width scale (50% of original)
  heightScale = 0.35,     -- Height scale (35% of original)
  walker = true,           -- Enable walking animation
  trueColor = true,        -- Preserve original colors
})
```

## Separate Width/Height Scaling

The system supports independent scaling for width and height:

```lua
scale = 0.5        -- Width: 50% of original
heightScale = 0.35 -- Height: 35% of original
```

This allows precise control over sprite proportions without compressing pixels.

## Battle and Trainer Card Sprites

The mod automatically overrides:
- **Battle back sprite**: Shown during Pokémon battles
- **Trainer card sprite**: Shown on trainer card and Hall of Fame

These are forced to render in full-color (trueColor) instead of GB's limited color palette.

## Installation

1. Place this mod in your `mods/` directory
2. Rename the mod folder and update `manifest.json` with your desired `id`
3. Name your sprite files according to the naming convention
4. Enable the mod in the mod menu
5. The player sprites will be replaced with your custom sprites

## Notes

- Larger sprites are automatically centered on the tile
- The system calculates proper positioning offsets based on frame size
- Palette effects and rendering modes work with larger sprites
- Walking animation timing is preserved regardless of sprite size
- Battle and card sprites render in full color