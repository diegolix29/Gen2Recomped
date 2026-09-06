"""Match exposed skin brightness and hue across every generic NPC pose.

TEST4 corrected the pale hue in the shared atlases, but the meshes also carry
baked directional brightness in vertex slot six.  Strong highlights on arms,
hands, and legs therefore remained visibly whiter than faces and ears.  This
pass corrects both sources while retaining a narrow, natural shading range.
"""

from pathlib import Path
import re

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

# Representative ear/base colors measured per archetype.  Very dark samples
# can come from the ear's shadowed edge, so the base red channel has a safe
# floor.  The red-green and red-blue spacing still preserves complexion.
EAR_BASES = {
    "adult_man": (221, 179, 155),
    "adult_woman": (253, 204, 179),
    "cook": (229, 184, 157),
    "elderly_man": (233, 191, 168),
    "elderly_woman": (239, 197, 177),
    "fat": (247, 189, 161),
    "guard": (242, 195, 162),
    "juvenile_boy": (236, 194, 165),
    "juvenile_girl": (201, 139, 103),
    "kid_boy": (205, 132, 90),
    "kid_girl": (223, 164, 127),
    "middle_man": (243, 201, 164),
    "middle_woman": (255, 201, 159),
    "muscle": (215, 167, 134),
    "scientist": (227, 183, 153),
    "staff_man": (222, 173, 143),
    "staff_woman": (233, 180, 155),
    "young_boy": (249, 218, 195),
    "young_girl": (255, 194, 166),
}

SKIN_REGIONS = ((1024, 0, 2048, 1024), (0, 1024, 512, 2048))
VERTEX_RE = re.compile(
    r"\{\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+),"
    r"\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\}"
)


def safe_target(base):
    r, g, b = base
    target_r = max(225, min(253, r))
    gap_g = max(30, min(50, r - g))
    gap_b = max(50, min(75, r - b))
    return target_r, target_r - gap_g, target_r - gap_b


def skin_like(r, g, b, alpha=255):
    return (
        alpha > 8
        and r >= 180
        and g >= 120
        and b >= 80
        and r >= g >= b
        and (r - b) > 20
    )


def correct_atlas(name, target):
    path = ASSETS / f"{name}_atlas.png"
    pixels = np.array(Image.open(path).convert("RGBA"))
    target_r, target_g, target_b = target
    changed = 0
    for x0, y0, x1, y1 in SKIN_REGIONS:
        block = pixels[y0:y1, x0:x1]
        rgb = block[:, :, :3].astype(np.int16)
        alpha = block[:, :, 3]
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

        # Restrict the edit to light peach base/highlight pixels.  Dark facial
        # lines, blush, lips, eye whites, clothes, and hair stay untouched.
        mask = (
            (alpha > 8)
            & (r >= 225)
            & (g >= 180)
            & (b >= 150)
            & (r >= g)
            & (g >= b)
            & ((r - b) > 20)
        )
        nr = np.minimum(r, target_r)
        ng = np.minimum(g, target_g)
        nb = np.minimum(b, target_b)
        altered = mask & ((nr != r) | (ng != g) | (nb != b))
        rgb[:, :, 0] = np.where(mask, nr, r)
        rgb[:, :, 1] = np.where(mask, ng, g)
        rgb[:, :, 2] = np.where(mask, nb, b)
        block[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
        changed += int(altered.sum())

    Image.fromarray(pixels, "RGBA").save(path, optimize=True)
    return changed


def correct_mesh(path, atlas):
    text = path.read_text(encoding="utf-8")
    width, height = atlas.size
    changed = 0

    def replace(match):
        nonlocal changed
        x, y, z, u, v, shade = map(float, match.groups())
        in_region = (
            (u >= 0.5 and v < 0.5)
            or (u < 0.25 and v >= 0.5)
        )
        if in_region:
            px = min(width - 1, max(0, int(u * width)))
            py = min(height - 1, max(0, int(v * height)))
            r, g, b, alpha = atlas.getpixel((px, py))
            if skin_like(r, g, b, alpha) and shade > 0.86:
                shade = 0.86
                changed += 1
        return f"{{{x:.6f},{y:.6f},{z:.6f},{u:.6f},{v:.6f},{shade:.6f}}}"

    start = text.index("vertices = {")
    end = text.index("indices = {")
    updated = text[:start] + VERTEX_RE.sub(replace, text[start:end]) + text[end:]
    path.write_text(updated, encoding="utf-8", newline="\n")
    return changed


atlas_total = 0
vertex_total = 0
mesh_total = 0
for model, base in EAR_BASES.items():
    target = safe_target(base)
    atlas_count = correct_atlas(model, target)
    atlas_total += atlas_count
    atlas = Image.open(ASSETS / f"{model}_atlas.png").convert("RGBA")
    paths = [ASSETS / f"{model}_mesh.lua"]
    paths.extend(sorted(ASSETS.glob(f"{model}_walk_*.lua")))
    model_vertices = 0
    for path in paths:
        count = correct_mesh(path, atlas)
        model_vertices += count
        mesh_total += 1
    vertex_total += model_vertices
    print(
        f"{model}: target={target}, atlas_pixels={atlas_count}, "
        f"highlight_vertices={model_vertices}, meshes={len(paths)}"
    )

print(
    f"Total: {atlas_total} atlas pixels and {vertex_total} baked highlights "
    f"corrected across {mesh_total} neutral/walking meshes"
)
