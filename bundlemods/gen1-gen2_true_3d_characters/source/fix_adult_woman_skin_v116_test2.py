"""Warm the adult-woman skin base without touching non-skin artwork."""

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "assets" / "adult_woman_atlas.png"
image = Image.open(PATH).convert("RGBA")
pixels = np.array(image)

# The corrected eye/face sheet occupies the upper-left 512x512 pixels of the
# reserved eye slot. The body skin sheet occupies its own lower-left region.
regions = ((1024, 0, 1536, 512), (0, 1024, 512, 2048))
changed = 0
for x0, y0, x1, y1 in regions:
    block = pixels[y0:y1, x0:x1]
    rgb = block[:, :, :3].astype(np.int16)
    alpha = block[:, :, 3]
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

    # Select only the very pale peach base and highlights. Neutral whites,
    # pupils, lashes, blush, outlines, hair, and clothing fail this mask.
    mask = (
        (alpha > 8)
        & (r >= 235)
        & (g >= 224)
        & (b >= 207)
        & ((r - g) >= 7)
        & ((g - b) >= 6)
    )
    strength = np.clip((g - 224) / 13.0, 0.0, 1.0)
    rgb[:, :, 1] -= np.rint(16.0 * strength * mask).astype(np.int16)
    rgb[:, :, 2] -= np.rint(20.0 * strength * mask).astype(np.int16)
    block[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    changed += int(mask.sum())

Image.fromarray(pixels, "RGBA").save(PATH, optimize=True)
print(f"Warmed {changed} adult-woman skin pixels")
