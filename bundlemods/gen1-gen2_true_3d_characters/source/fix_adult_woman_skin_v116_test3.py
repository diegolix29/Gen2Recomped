"""Match the adult-woman pale skin base directly to her ear palette."""

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "assets" / "adult_woman_atlas.png"
image = Image.open(PATH).convert("RGBA")
pixels = np.array(image)

regions = ((1024, 0, 1536, 512), (0, 1024, 512, 2048))
changed = 0
for x0, y0, x1, y1 in regions:
    block = pixels[y0:y1, x0:x1]
    rgb = block[:, :, :3].astype(np.int16)
    alpha = block[:, :, 3]
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

    # TEST2's subtle adjustment remained visibly pale under Battle Art's blue
    # daylight tint.  Match only the remaining pale peach pixels to the hue of
    # the model's own ear base (approximately 253/204/179). Neutral whites and
    # all darker facial artwork remain outside the mask.
    mask = (
        (alpha > 8)
        & (r >= 235)
        & (g >= 214)
        & (b >= 195)
        & ((r - g) >= 7)
        & ((g - b) >= 6)
    )
    target_g = np.maximum(0, r - 49)
    target_b = np.maximum(0, r - 74)
    rgb[:, :, 1] = np.where(mask, np.minimum(g, target_g), g)
    rgb[:, :, 2] = np.where(mask, np.minimum(b, target_b), b)
    block[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    changed += int(mask.sum())

Image.fromarray(pixels, "RGBA").save(PATH, optimize=True)
print(f"Matched {changed} adult-woman skin pixels to the ear palette")
