-- Options for Advanced Terrarium Voxel Mod.
-- Stadium ROM picker option for both Gen 1 (Stadium 1) and Gen 2 (Stadium 2).
-- Gen 2 specific options for voxel rendering.
return {
  {
    key = "voxel3d",
    type = "toggle",
    label = "3D VOXEL WORLD",
    default = true,
    description = "Enables the Gold Gen-2 voxel world. Turn this switch OFF to return to Gold's real 2D overworld. Stadium 2 ROM selection is not required for terrain.",
  },
  {
    key = "stadiumRomFile",
    type = "choice",
    label = "STADIUM ROM FILE",
    default = "choose",
    choices = {
      { "CHOOSE", "choose" },
    },
    description = "Choose your legally obtained Pokemon Stadium ROM (Stadium 1 for Gen 1 games, Stadium 2 for Gen 2 games) to build 3D models. The mod will automatically detect which generation you're playing and use the appropriate ROM reader.",
  },
}
