# Player Model Customization

This mod now supports loading custom 3D models to replace the default player sprite.

## Supported Formats

- **.obj** - Wavefront OBJ files (fully supported)
- **.gltf** - glTF JSON format (not yet implemented)
- **.glb** - glTF binary format (not yet implemented)

**Currently only .obj files are supported.** If you have a .glb or .gltf file, you need to convert it to .obj format first.

## How to Use

1. **Prepare your model**:
   - **Important: Currently only .obj files are supported**
   - If you have a .glb or .gltf file, convert it to .obj first:
     - Open your file in Blender
     - File → Export → Wavefront (.obj)
     - Make sure to include mesh data and apply modifiers
   - For best results, center your model at the origin and ensure it's in a standing pose
   - The model should be roughly human-sized (scale will be adjusted automatically)

2. **Install the model**:
   - Launch the game with the Dramatic Shape Voxel Mod enabled
   - Go to Options → Display
   - Find the "PLAYER MODEL" row
   - Click to open a file picker dialog
   - Select your .obj file
   - The model will be copied to the save directory and loaded automatically

3. **Remove the model**:
   - Delete the model file from the save directory's `player_models/` folder
   - Or clear the model through the options (not yet implemented)

## Current Limitations

- Only basic .obj geometry is supported (vertices and faces)
- No texture mapping or materials yet
- No animation support
- No bone rigging
- glTF/.glb support is planned but not yet implemented
- Models may need manual scaling adjustments

## Technical Details

The player model system uses the same infrastructure as the Pokemon Stadium model importer:

- **File picker**: Uses platform-specific dialogs (PowerShell on Windows, osascript on macOS, zenity/kdialog on Linux)
- **Storage**: Models are stored in the save directory under `player_models/`
- **Loading**: Custom OBJ parser that handles various face formats
- **Rendering**: Integrates with the existing Voxel3D rendering pipeline
- **Caching**: Models are cached to avoid reloading every frame

## Model Specifications

For best results, your .obj model should:

- Be centered at the origin (0, 0, 0)
- Use a consistent scale (the system auto-scales to ~0.1 world units)
- Have a reasonable polygon count (keep it under 10,000 triangles for performance)
- Use triangle faces (quads are automatically converted)
- Be in a T-pose or neutral standing pose

## File Structure

```
save_directory/
└── player_models/
    ├── model.info          # Marker file with current model info
    └── your_model.obj      # Your custom model files
```

## Troubleshooting

**Model doesn't appear**:
- Check that the .obj file is valid
- Ensure the model has vertices and faces
- Try adjusting the scale in PlayerModel.lua

**Model appears too small/large**:
- Edit the scale value in `lib/PlayerModel.lua` (line ~209)
- Default scale is 0.1, increase for larger models

**Model appears upside down**:
- The system automatically flips the Y-axis to match the game's coordinate system
- If still wrong, you may need to rotate your model in Blender before export

## Future Enhancements

- [ ] Full glTF/.glb support with textures and materials
- [ ] Animation support for walking/idle states
- [ ] Bone rigging for articulated movement
- [ ] UI for adjusting model scale and position
- [ ] Multiple model slots for different outfits
- [ ] Per-save model selection

## Development

The player model system consists of three main modules:

- **PlayerModelPick.lua**: File picker dialog for selecting models
- **PlayerModelInstall.lua**: Model management and storage
- **PlayerModel.lua**: Model loading, parsing, and rendering

Integration points:
- `main.lua`: Loads modules and initializes system
- `VoxelScene.lua`: Renders custom model instead of sprite when available
- Options menu: Adds player model selection row
