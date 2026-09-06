"""Normalize washed-out generic-NPC skin toward each model's ear palette."""

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

# Red-minus-green and red-minus-blue gaps measured from the warm ear surfaces
# in each model. Extreme source values are capped below to preserve a natural
# range and avoid turning shaded child/youngster textures overly saturated.
EAR_GAPS = {
    "adult_man": (42, 66),
    "adult_woman": (49, 74),
    "cook": (45, 72),
    "elderly_man": (42, 65),
    "elderly_woman": (42, 62),
    "fat": (58, 86),
    "guard": (47, 80),
    "juvenile_boy": (42, 71),
    "juvenile_girl": (62, 98),
    "kid_boy": (73, 115),
    "kid_girl": (59, 96),
    "middle_man": (42, 79),
    "middle_woman": (54, 96),
    "muscle": (48, 81),
    "scientist": (44, 74),
    "staff_man": (49, 79),
    "staff_woman": (53, 78),
    "young_boy": (31, 54),
    "young_girl": (61, 89),
}


def normalize(name: str, gap_g: int, gap_b: int) -> int:
    path = ASSETS / f"{name}_atlas.png"
    image = Image.open(path).convert("RGBA")
    pixels = np.array(image)
    changed = 0

    # Safety caps retain complexion variety without allowing unusually dark
    # sampled ear shadows to drive the whole skin sheet orange.
    gap_g = max(30, min(50, gap_g))
    gap_b = max(50, min(75, gap_b))
    for x0, y0, x1, y1 in ((1024, 0, 2048, 1024),
                           (0, 1024, 512, 2048)):
        block = pixels[y0:y1, x0:x1]
        rgb = block[:, :, :3].astype(np.int16)
        alpha = block[:, :, 3]
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

        # Only light peach pixels qualify. Neutral whites (eye highlights),
        # outlines, blush, hair, clothes, and already-warm skin are preserved.
        mask = (
            (alpha > 8)
            & (r >= 225)
            & (g >= 200)
            & (b >= 180)
            & ((r - g) >= 7)
            & ((g - b) >= 6)
        )
        new_g = np.minimum(g, np.maximum(0, r - gap_g))
        new_b = np.minimum(b, np.maximum(0, r - gap_b))
        altered = mask & ((new_g != g) | (new_b != b))
        rgb[:, :, 1] = np.where(mask, new_g, g)
        rgb[:, :, 2] = np.where(mask, new_b, b)
        block[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
        changed += int(altered.sum())

    Image.fromarray(pixels, "RGBA").save(path, optimize=True)
    return changed


total = 0
for model, gaps in EAR_GAPS.items():
    count = normalize(model, *gaps)
    total += count
    print(f"{model}: {count} skin pixels normalized")
print(f"Total: {total} skin pixels normalized across {len(EAR_GAPS)} archetypes")
