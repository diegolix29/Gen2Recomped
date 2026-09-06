"""Give every exposed skin surface one decisive per-NPC base palette.

Earlier tests preserved too much of the source atlas and baked-light range.
TEST6 deliberately unifies face, ear, arm, hand, leg, and foot base pixels and
uses one baked-light value on those pixels in every neutral and walking mesh.
"""

from pathlib import Path
import re

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

# Warm reference colors taken from each archetype's own ear/face artwork.
# These are intentionally decisive rather than incremental.
SKIN_TARGETS = {
    "adult_man": (213, 163, 136),
    "adult_woman": (224, 170, 143),
    "cook": (225, 176, 146),
    "elderly_man": (223, 166, 137),
    "elderly_woman": (231, 184, 163),
    "fat": (215, 148, 118),
    "guard": (220, 165, 130),
    "juvenile_boy": (204, 130, 95),
    "juvenile_girl": (215, 149, 107),
    "kid_boy": (226, 157, 116),
    "kid_girl": (222, 163, 126),
    "middle_man": (222, 163, 121),
    "middle_woman": (235, 180, 145),
    "muscle": (218, 171, 138),
    "scientist": (201, 153, 123),
    "staff_man": (212, 158, 127),
    "staff_woman": (233, 159, 126),
    "young_boy": (209, 156, 126),
    "young_girl": (219, 157, 123),
}

SKIN_REGIONS = ((1024, 0, 2048, 1024), (0, 1024, 512, 2048))
VERTEX_RE = re.compile(
    r"\{\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+),"
    r"\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\}"
)


def is_skin(r, g, b, alpha=255):
    return (
        alpha > 8
        and r >= 180
        and g >= 105
        and b >= 70
        and r >= g >= b
        and 15 <= r - g <= 100
        and 8 <= g - b <= 60
    )


def unify_atlas(name, target):
    path = ASSETS / f"{name}_atlas.png"
    pixels = np.array(Image.open(path).convert("RGBA"))
    changed = 0
    for x0, y0, x1, y1 in SKIN_REGIONS:
        block = pixels[y0:y1, x0:x1]
        rgb = block[:, :, :3].astype(np.int16)
        alpha = block[:, :, 3]
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
        mask = (
            (alpha > 8)
            & (r >= 180)
            & (g >= 105)
            & (b >= 70)
            & (r >= g)
            & (g >= b)
            & ((r - g) >= 15)
            & ((r - g) <= 100)
            & ((g - b) >= 8)
            & ((g - b) <= 60)
        )
        altered = mask & (
            (r != target[0]) | (g != target[1]) | (b != target[2])
        )
        rgb[:, :, 0] = np.where(mask, target[0], r)
        rgb[:, :, 1] = np.where(mask, target[1], g)
        rgb[:, :, 2] = np.where(mask, target[2], b)
        block[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
        changed += int(altered.sum())
    Image.fromarray(pixels, "RGBA").save(path, optimize=True)
    return changed


def unify_mesh(path, atlas):
    text = path.read_text(encoding="utf-8")
    width, height = atlas.size
    changed = 0

    def replace(match):
        nonlocal changed
        x, y, z, u, v, shade = map(float, match.groups())
        if (u >= 0.5 and v < 0.5) or (u < 0.25 and v >= 0.5):
            px = min(width - 1, max(0, int(u * width)))
            py = min(height - 1, max(0, int(v * height)))
            r, g, b, alpha = atlas.getpixel((px, py))
            if is_skin(r, g, b, alpha) and shade != 0.86:
                shade = 0.86
                changed += 1
        return f"{{{x:.6f},{y:.6f},{z:.6f},{u:.6f},{v:.6f},{shade:.6f}}}"

    start = text.index("vertices = {")
    end = text.index("indices = {")
    updated = text[:start] + VERTEX_RE.sub(replace, text[start:end]) + text[end:]
    path.write_text(updated, encoding="utf-8", newline="\n")
    return changed


pixel_total = 0
vertex_total = 0
mesh_total = 0
for model, target in SKIN_TARGETS.items():
    pixels = unify_atlas(model, target)
    atlas = Image.open(ASSETS / f"{model}_atlas.png").convert("RGBA")
    paths = [ASSETS / f"{model}_mesh.lua"]
    paths.extend(sorted(ASSETS.glob(f"{model}_walk_*.lua")))
    vertices = sum(unify_mesh(path, atlas) for path in paths)
    pixel_total += pixels
    vertex_total += vertices
    mesh_total += len(paths)
    print(
        f"{model}: target={target}, pixels={pixels}, "
        f"vertices={vertices}, meshes={len(paths)}",
        flush=True,
    )

print(
    f"Total: unified {pixel_total} skin pixels and {vertex_total} vertices "
    f"across {mesh_total} neutral/walking meshes",
    flush=True,
)
