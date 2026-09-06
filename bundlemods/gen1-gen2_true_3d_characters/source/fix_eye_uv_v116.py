"""Repair half-size eye textures in the generated neutral and walk meshes.

Six source models use 512x512 eye sheets.  The older atlas builder reserved a
1024x1024 slot for every eye sheet and scaled UVs as if every source sheet
filled that slot.  That doubled the sampled area, placing multiple blink rows
across the face.  The textures themselves are already stored at native size in
the upper-left of the reserved slot, so only the generated eye UVs need to be
contracted by one half around the slot origin.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
AFFECTED = (
    "adult_woman",
    "cook",
    "elderly_woman",
    "fat",
    "staff_man",
    "staff_woman",
)
MARKER = "-- Eye-atlas UV fix v1.1.6 (native 512x512 eye sheet).\n"

VERTEX = re.compile(
    r"(\{\s*-?[\d.]+,\s*-?[\d.]+,\s*-?[\d.]+,\s*)"
    r"(-?[\d.]+)(,\s*)(-?[\d.]+)(,\s*-?[\d.]+\s*\})"
)


def repair(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    if text.startswith(MARKER):
        return 0

    changed = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal changed
        u = float(match.group(2))
        v = float(match.group(4))
        # Eye material occupies the atlas's top-right quadrant.  The strict U
        # test avoids touching body vertices that land exactly on the seam.
        if u > 0.500001 and v <= 0.500001:
            u = 0.5 + (u - 0.5) * 0.5
            v *= 0.5
            changed += 1
            return (
                f"{match.group(1)}{u:.6f}{match.group(3)}"
                f"{v:.6f}{match.group(5)}"
            )
        return match.group(0)

    fixed = VERTEX.sub(replace, text)
    if changed:
        path.write_text(MARKER + fixed, encoding="utf-8", newline="\n")
    return changed


total_files = 0
total_vertices = 0
for model in AFFECTED:
    paths = [ASSETS / f"{model}_mesh.lua"]
    paths.extend(sorted(ASSETS.glob(f"{model}_walk_*.lua")))
    if len(paths) != 25:
        raise RuntimeError(f"Expected 25 mesh files for {model}, found {len(paths)}")
    for mesh_path in paths:
        count = repair(mesh_path)
        if count:
            total_files += 1
            total_vertices += count

print(f"Repaired {total_vertices} eye vertices across {total_files} mesh files")
