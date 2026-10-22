#!/usr/bin/env python3
"""Derive a HDPokemonSheets geometry table (data/hd_sheet_meta_*.lua) from data/hd_pokemon.lua.

data/hd_pokemon.lua is what tools/import_hd_pokemon.py writes; the game itself only reads the
hd_sheet_meta*.lua tables ({width, height, columns, frames, scale, frame_ms} per stem). This is the
same derivation that produced data/hd_sheet_meta_gen5.lua, for any dex range.

  python tools/hd_pokemon_to_meta.py --min-dex 650 --max-dex 721 --out data/hd_sheet_meta_gen6.lua
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROW = re.compile(
    r'^\s*(?P<key>default|male|female|\["(?P<form>[a-z0-9]+)"\]) = \{ image = "[^"]*", '
    r"width = (?P<w>\d+), height = (?P<h>\d+), columns = (?P<c>\d+), frames = (?P<f>\d+), "
    r"durations = \{(?P<d>[^}]*)\}, displayScale = (?P<s>[\d.]+) \},?\s*$"
)


def parse(path: Path):
    """yield (dex, side, color, stem_suffix, w, h, cols, frames, scale, frame_ms)"""
    dex = side = color = None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^  \[(\d+)\] = \{", line)
        if m:
            dex = int(m.group(1)); continue
        m = re.match(r"^    (front|back) = \{", line)
        if m:
            side = m.group(1); continue
        m = re.match(r"^      (normal|shiny) = \{", line)
        if m:
            color = m.group(1); continue
        m = ROW.match(line)
        if m and dex and side and color:
            key = m.group("key")
            suffix = "" if key == "default" else "-m" if key == "male" else "-f" if key == "female" else "-" + m.group("form")
            ds = [int(x) for x in m.group("d").split(",") if x.strip()] or [50]
            yield (dex, side, color, suffix, int(m.group("w")), int(m.group("h")), int(m.group("c")),
                   int(m.group("f")), float(m.group("s")), max(1, int(round(sum(ds) / len(ds)))))


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", type=Path, default=root / "data" / "hd_pokemon.lua")
    ap.add_argument("--min-dex", type=int, required=True)
    ap.add_argument("--max-dex", type=int, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--label", default="")
    a = ap.parse_args()

    table = {"front": {"normal": {}, "shiny": {}}, "back": {"normal": {}, "shiny": {}}}
    n = 0
    for dex, side, color, suffix, w, h, cols, frames, scale, ms in parse(a.source):
        if a.min_dex <= dex <= a.max_dex:
            table[side][color][f"{dex:03d}{suffix}"] = "%d, %d, %d, %d, %.6f, %d" % (w, h, cols, frames, scale, ms)
            n += 1
    lines = [
        f"-- {a.label or 'Sheet geometry'} ({a.min_dex}-{a.max_dex}), generated from data/hd_pokemon.lua by tools/hd_pokemon_to_meta.py.",
        "-- Same format as data/hd_sheet_meta.lua: {width, height, columns, frames, scale, frame_ms}",
        "return {",
    ]
    for side in ("front", "back"):
        lines.append(f"  {side} = {{")
        for color in ("normal", "shiny"):
            lines.append(f"    {color} = {{")
            for stem in sorted(table[side][color]):
                lines.append(f'      ["{stem}"] = {{{table[side][color][stem]}}},')
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {n} rows -> {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
